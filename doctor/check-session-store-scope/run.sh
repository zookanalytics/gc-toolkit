#!/usr/bin/env bash
# doctor/check-session-store-scope — a live agent's store env names its own
# scope. Two reads, answering two different questions:
#
#   PANE PROCESS — what the running agent actually has. A pane process carries
#   the session env plus whatever the tmux server's global environment showed
#   through, so it is the only place a leak is observable at all. Linux exposes
#   it as $PROC/<pid>/environ, and a host with no proc filesystem, such as macOS,
#   prints it through `ps -E`. macOS hides the environment of its own binaries,
#   /bin/zsh and /bin/sleep among them, so a pane running one is a note on that
#   session. When no pane can be read at all, this arm has judged nothing, so
#   the check warns once and cannot pass.
#   SESSION ENV — what the NEXT process in that pane will get. `respawn-pane`
#   takes no env argument, so that process comes up with the store-scope values
#   the session env itself sets, plus any key the server's global holds that the
#   session neither sets nor marks removed. A value the session sets wrong is as
#   reachable by that respawn as one it lets inherit, so both are checked.
#
# Scope comes from the session's own environment and never from config: the
# proposition is that a session agrees with itself, which stays checkable when
# the config it was spawned from has since changed. A qualified GC_ALIAS,
# `<rig>/<binding>.<agent>`, names the session's rig, and an unqualified one
# names a city-scoped agent. A session with no alias, such as a member of an
# unaliased pool, takes its scope from GC_TEMPLATE: `<rig>/<binding>.<agent>`
# on a rig-scoped session and `<binding>.<agent>` on a city-scoped one. The
# session name is not read for scope. A pool member is named
# `<binding>__<agent>-<id>` whichever rig imported its pack, so the name opens
# with the pack binding, not the rig. A session carrying neither key has no
# scope to agree with, so it warns as unverified.
#
# GC_BEADS_PREFIX is not judged on its own, because its correct value is a
# property of the store rather than of the session. It never travels alone:
# in the gascity rig both writers, orderExecEnvWithError (cmd/gc/order_store.go)
# and the bd override builder (cmd/gc/cmd_bd.go), set GC_RIG, GC_RIG_ROOT,
# BEADS_DIR, GC_STORE_ROOT and GC_STORE_SCOPE into the same map beside it, and
# those five are judged here.
#
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Bounded probes; an unreadable session list or global environment
# warns, never passes.

set -u

city="${GC_CITY_PATH:-${GC_CITY:-}}"
PROC="${GC_DOCTOR_PROC_ROOT:-/proc}"
pane_reader="$PROC"; [ -d "$PROC" ] || pane_reader="ps -E"

errors=(); warnings=(); notes=()
sessions_checked=0; panes_read=0
# >>> doctor-budget
# One deadline for the whole check, anchored at process start. `gc doctor
# --check-timeout` (default 60s) abandons an overrunning check and discards
# everything it had buffered, so a check that has not printed by then is never
# heard. A per-probe constant does not hold that line: the probes below run
# once per rig, so their ceilings sum. Each probe gets the time still left
# instead, capped at half the budget so one wedged store cannot eat the rest,
# and a probe that no longer fits is refused with 124 — `timeout`'s own expiry
# code, which every caller's "this store was NOT checked" arm already handles.
# GC_DOCTOR_CHECK_TIMEOUT overrides the default, in whole seconds. Nothing
# exports it: the runner passes GC_CITY_PATH and GC_PACK_DIR and no budget.
BUDGET_DEFAULT=60; BUDGET_RESERVE=5; BUDGET_MIN_PROBE=2
budget_now() { if [ -n "${EPOCHSECONDS:-}" ]; then printf %s "$EPOCHSECONDS"; else date +%s; fi; }
budget_init() {
    BUDGET_TOTAL="${GC_DOCTOR_CHECK_TIMEOUT:-$BUDGET_DEFAULT}"; BUDGET_TOTAL="${BUDGET_TOTAL%s}"
    case "$BUDGET_TOTAL" in ''|*[!0-9]*) BUDGET_TOTAL="$BUDGET_DEFAULT" ;; esac
    BUDGET_CAP=$(( BUDGET_TOTAL / 2 ))
    BUDGET_DEADLINE=$(( $(budget_now) - SECONDS + BUDGET_TOTAL - BUDGET_RESERVE ))
}
budget_slice() {
    local left=$(( BUDGET_DEADLINE - $(budget_now) ))
    [ "$left" -le "$BUDGET_CAP" ] || left="$BUDGET_CAP"
    [ "$left" -ge 0 ] || left=0
    printf %s "$left"
}
budget_spent() { [ "$(budget_slice)" -lt "$BUDGET_MIN_PROBE" ]; }
run_bounded() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@" </dev/null; else "$@" </dev/null; fi; }
# A probe fed from a pipe cannot borrow run_bounded's </dev/null.
run_piped() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi; }
budget_init
# <<< doctor-budget
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
gcmux() { run_bounded tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# env_val <key> <env-text> — the value of key, empty when absent or removed. A
# value is any bytes, and BSD sed stops at one its locale cannot decode, which
# would read every key after it as absent.
env_val() { printf '%s\n' "$2" | LC_ALL=C sed -n "s/^$1=//p" | head -1; }
# env_removed <key> <env-text> — true when tmux reports the key marked removed.
env_removed() { printf '%s\n' "$2" | grep -qx -- "-$1"; }
# rig_named_by <path> — the rig a path under <city>/rigs/ belongs to, else empty.
rig_named_by() {
    case "$1" in
        "$city"/rigs/*) local rest="${1#"$city"/rigs/}"; printf '%s' "${rest%%/*}" ;;
        *) : ;;
    esac
}

# pane_env <pid> — the environment <pid> was started with, one KEY=value per line
# and empty when it cannot be read. Exit 124 is the check budget, which refused
# the read or cut it short, so this process was NOT read.
#
# `ps -E` prints the command line and then the environment, joined by spaces, and
# marks neither end. The command line is read on its own and cut off the front,
# because an agent's arguments carry its prompt, and a KEY=value written in that
# text is not its environment. The cut goes by length, because removing a prefix
# by pattern takes bash seconds on a prompt of 50 KB. What remains must open with
# an entry, or ps showed no environment. An entry then starts at a space followed
# by a name and `=`, so a value holding a space stays whole. ps gives no way to
# tell a value from the next entry, so a value holding " NAME=" reads as two
# entries, and an entry whose name is not an identifier, such as an exported shell
# function's, reads as part of the value before it. A store key is misread when
# its own value holds such a word, when another variable's value spells out that
# key's assignment, or when such an entry follows it.
pane_env() {
    local pid="$1" cmd full rest rc
    [ -n "$pid" ] || return 0
    if [ "$pane_reader" = "$PROC" ]; then
        [ -r "$PROC/$pid/environ" ] && tr '\0' '\n' < "$PROC/$pid/environ" 2>/dev/null
        return 0
    fi
    cmd=$(run_bounded ps -ww -o command= -p "$pid" 2>/dev/null); rc=$?
    [ "$rc" -ne 124 ] || return 124
    [ "$rc" -eq 0 ] || return 0
    full=$(run_bounded ps -E -ww -o command= -p "$pid" 2>/dev/null); rc=$?
    [ "$rc" -ne 124 ] || return 124
    [ "$rc" -eq 0 ] || return 0
    case "$full" in "$cmd "*) rest="${full:${#cmd}+1}" ;; *) return 0 ;; esac
    case "${rest%%=*}" in ''|"$rest"|[!A-Za-z_]*|*[!A-Za-z0-9_]*) return 0 ;; esac
    printf '%s\n' "$rest" | LC_ALL=C sed -E 's/ ([A-Za-z_][A-Za-z0-9_]*=)/\
\1/g'
}

if ! command -v tmux >/dev/null 2>&1; then
    notes+=("tmux is not on PATH — a session environment is a runtime property, not verifiable here")
elif [ -z "$city" ]; then
    notes+=("no city in scope (GC_CITY_PATH/GC_CITY unset) — session environments not verifiable here")
else
    # Name and pane pid in one call: a per-session `list-panes` would double the
    # tmux round trips, and the doctor abandons a check at its own budget.
    sessions=$(gcmux list-sessions -F '#{session_name}	#{pane_pid}' 2>/dev/null); list_rc=$?
    global=$(gcmux show-environment -g 2>/dev/null); global_rc=$?
    if [ "$list_rc" -ne 0 ]; then
        warnings+=("could not list tmux sessions (rc=$list_rc) — store-scope agreement UNVERIFIED. Not a benign skip: the symptom this check exists for is silent, and an agent reading the wrong store writes beads no queue that wants them can see.")
    elif [ -z "$sessions" ]; then
        notes+=("the tmux server holds no sessions — no agent environment to read")
    fi
    # Arm 2 reads only $global; an unreadable global environment makes every key
    # look absent, so the respawn-inheritance arm would silently pass. A failed
    # probe is UNVERIFIED, not clean — warn so the aggregate can never be OK.
    if [ "$global_rc" -ne 0 ]; then
        warnings+=("could not read the tmux server global environment (rc=$global_rc) — warm-respawn inheritance UNVERIFIED. Not a benign skip: with the global environment unread, a store key the server holds is invisible here yet still reaches the next process in a respawned pane.")
    fi

    # Store-scope keys the runtime resolves per session. GC_STORE_SCOPE and
    # GC_BEADS_PREFIX are absent from a healthy session env: nothing seeds them
    # there, which is also why neither can be withheld on a respawn.
    scope_keys="GC_RIG GC_RIG_ROOT BEADS_DIR GC_STORE_ROOT GC_STORE_SCOPE GC_BEADS_PREFIX"
    path_keys="GC_RIG_ROOT BEADS_DIR GC_STORE_ROOT"

    # scope_disagreements <env-text> — one line per store-scope key in <env-text>
    # that disagrees with this session's derived scope (want_rig, want_scope), as
    # "<kind>\t<key>\t<value>[\t<rig>]"; empty output is agreement. It judges the
    # same five keys named above — GC_RIG, the path keys, GC_STORE_SCOPE — and
    # not GC_BEADS_PREFIX. The pane arm and the session-env arm both read it, so a
    # key added here is judged against both the running process and the respawn.
    scope_disagreements() {
        local env="$1" got_rig key val named got_scope
        got_rig=$(env_val GC_RIG "$env")
        if [ "$got_rig" != "$want_rig" ]; then
            if [ -n "$got_rig" ]; then printf 'rig-wrong\tGC_RIG\t%s\n' "$got_rig"
            else printf 'rig-missing\tGC_RIG\t\n'; fi
        fi
        for key in $path_keys; do
            val=$(env_val "$key" "$env")
            [ -n "$val" ] || continue
            named=$(rig_named_by "$val")
            if [ -n "$named" ]; then
                [ "$named" = "$want_rig" ] && continue
                printf 'path-rig\t%s\t%s\t%s\n' "$key" "$val" "$named"
            elif [ -n "$want_rig" ] && { [ "$val" = "$city" ] || [ "$val" = "$city/.beads" ]; }; then
                # A path rig_named_by cannot place is skipped — no rig resolves
                # without config — EXCEPT the city store itself, whose root and
                # .beads path are known here. A rig-scoped session pointed at it
                # reads the city store, not this rig's.
                printf 'path-city\t%s\t%s\n' "$key" "$val"
            fi
        done
        got_scope=$(env_val GC_STORE_SCOPE "$env")
        if [ -n "$got_scope" ] && [ "$got_scope" != "$want_scope" ]; then
            printf 'scope-wrong\tGC_STORE_SCOPE\t%s\n' "$got_scope"
        fi
    }

    # scan_cut <session> — the warning for a read run_bounded refused with 124.
    scan_cut() {
        warnings+=("store-scope scan hit the check budget before reading $1 (rc=124) — that session and any listed after it are UNVERIFIED. Not a benign skip: a still-listed session left unread can be resolving the wrong store, the exact symptom this check exists for. Raise the check budget (\`gc doctor --check-timeout\`, or GC_DOCTOR_CHECK_TIMEOUT).")
    }

    pane_unread=()
    TAB=$(printf '\t')
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        sess="${row%%"$TAB"*}"
        pane_pid=""
        case "$row" in *"$TAB"*) pane_pid="${row#*"$TAB"}" ;; esac
        [ -n "$sess" ] || continue
        # A session can end mid-scan; an unreadable one is not a finding. But a
        # 124 is run_bounded refusing the probe because the whole-check budget is
        # spent, not a vanished session (tmux would run and return its own code),
        # so this session is still listed and now UNVERIFIED. Skipping it the way
        # a vanished one is skipped lets a budget-truncated scan reach the OK line
        # past sessions it never read. Warn and stop — the deadline is fixed, so
        # every session after this one is out of budget too.
        senv=$(gcmux show-environment -t "$sess" 2>/dev/null); senv_rc=$?
        if [ "$senv_rc" -ne 0 ]; then
            if [ "$senv_rc" -eq 124 ]; then
                scan_cut "$sess"
                break
            fi
            continue
        fi
        agent=$(env_val GC_AGENT "$senv")
        [ -n "$agent" ] || continue
        sess_city=$(env_val GC_CITY_PATH "$senv")
        [ -z "$sess_city" ] || [ "$sess_city" = "$city" ] || continue

        # Gas City sets GC_TEMPLATE on each session it spawns from that
        # session's own template, over whatever the spawning process passed
        # through, so a scope a caller leaks cannot also move the scope the
        # session is judged against.
        alias_name=$(env_val GC_ALIAS "$senv")
        template=$(env_val GC_TEMPLATE "$senv")
        want_rig=""; scope_known=1
        case "$alias_name" in
            */*) want_rig="${alias_name%%/*}" ;;
            "")  case "$template" in
                     */*) want_rig="${template%%/*}" ;;
                     "")  scope_known=0 ;;
                 esac ;;
        esac
        want_scope="city"; [ -n "$want_rig" ] && want_scope="rig"
        scope_desc="city-scoped"; [ -n "$want_rig" ] && scope_desc="scoped to rig $want_rig"

        if [ "$scope_known" -eq 0 ]; then
            scope_desc="of undetermined scope"
            warnings+=("$sess carries GC_AGENT but neither GC_ALIAS nor GC_TEMPLATE, so its store scope cannot be derived and the store keys it holds are UNVERIFIED. Not a benign skip: an agent reading the wrong store writes beads no queue that wants them can see. Read its store keys by hand (\`tmux show-environment -t $sess\`). If every pool session reads this way, Gas City has stopped writing GC_TEMPLATE, and this check needs another source of scope.")
        else
            sessions_checked=$((sessions_checked + 1))

            # --- Arm 1: the running process agrees with the session's own scope
            penv=$(pane_env "$pane_pid"); penv_rc=$?
            if [ "$penv_rc" -eq 124 ]; then
                scan_cut "$sess"
                break
            fi
            if [ -z "$penv" ]; then
                pane_unread+=("$sess: pane process environment unreadable (pane_pid=${pane_pid:-none}, $pane_reader) — what this agent actually holds was not read")
            else
                panes_read=$((panes_read + 1))
                while IFS="$TAB" read -r kind key val named; do
                    [ -n "$kind" ] || continue
                    case "$kind" in
                        rig-wrong)   errors+=("$sess is $scope_desc but its running process holds $key=$val — every bd call it makes reads and writes rig $val's store. Restart the session (\`gc session reset $agent\`); if it recurs, the spawn is handing out a caller's scope.") ;;
                        rig-missing) errors+=("$sess is $scope_desc but its running process holds no GC_RIG — it resolves the city store instead of rig $want_rig's, so its work lands where that rig's queues cannot see it. Restart the session (\`gc session reset $agent\`).") ;;
                        path-rig)    errors+=("$sess is $scope_desc but its running process holds $key=$val, which names rig $named — restart the session (\`gc session reset $agent\`) and re-read this check.") ;;
                        path-city)   errors+=("$sess is $scope_desc but its running process holds $key=$val, the city store, not rig $want_rig's — its work lands where that rig's queues cannot see it. Restart the session (\`gc session reset $agent\`).") ;;
                        scope-wrong) errors+=("$sess is $scope_desc but its running process holds $key=$val, not $want_scope — restart the session (\`gc session reset $agent\`).") ;;
                    esac
                done <<< "$(scope_disagreements "$penv")"
            fi

            # --- Arm 1b: the session environment names the session's own scope
            # respawn-pane takes no env argument, so a store-scope value the
            # session environment SETS is what the next process in this pane
            # comes up with. Arm 2 cannot see it: that arm flags only keys the
            # session leaves open for the server to fill, never a wrong value
            # the session sets itself. The running process can still hold the
            # right scope (Arm 1 clean) while the session env already names
            # another store, so this is an error the same as the pane's —
            # `gc session reset` recreates the session from its derived scope.
            # Absence is not judged here: an unset key is Arm 2's to weigh, and
            # one the session sets is validated at the pane above.
            while IFS="$TAB" read -r kind key val named; do
                [ -n "$kind" ] || continue
                case "$kind" in
                    rig-wrong)   errors+=("$sess is $scope_desc but its session environment sets $key=$val — \`respawn-pane\` takes no env argument, so the next process in this pane comes up reading rig $val's store. Reset the session (\`gc session reset $agent\`).") ;;
                    path-rig)    errors+=("$sess is $scope_desc but its session environment sets $key=$val, which names rig $named — \`respawn-pane\` hands it to the next process in this pane. Reset the session (\`gc session reset $agent\`).") ;;
                    path-city)   errors+=("$sess is $scope_desc but its session environment sets $key=$val, the city store, not rig $want_rig's — \`respawn-pane\` hands it to the next process in this pane. Reset the session (\`gc session reset $agent\`).") ;;
                    scope-wrong) errors+=("$sess is $scope_desc but its session environment sets $key=$val, not $want_scope — \`respawn-pane\` hands it to the next process in this pane. Reset the session (\`gc session reset $agent\`).") ;;
                esac
            done <<< "$(scope_disagreements "$senv")"
        fi

        # --- Arm 2: a respawn of this pane would not inherit a store key ------
        # The per-key test governs both scopes: a session shadows only the keys
        # it sets. A rig-scoped session sets GC_RIG, GC_RIG_ROOT and BEADS_DIR,
        # so a server value for those cannot reach its respawn — but it sets none
        # of GC_STORE_ROOT, GC_STORE_SCOPE, GC_BEADS_PREFIX, and a global value
        # for one of those inherits into the next process exactly as it would on
        # a city-scoped session. Skipping rig-scoped sessions wholesale is the
        # fail-open this arm exists to catch.
        for key in $scope_keys; do
            gval=$(env_val "$key" "$global")
            [ -n "$gval" ] || continue
            [ -n "$(env_val "$key" "$senv")" ] && continue
            env_removed "$key" "$senv" && continue
            warnings+=("$sess is $scope_desc and its session environment neither sets nor removes $key, while the tmux server's global environment holds $key=$gval — \`respawn-pane\` takes no env argument, so the next process in this pane inherits it. Clear it on the server (\`tmux set-environment -gu $key\`) and restart the session.")
        done
    done <<< "$sessions"

    # An unread pane among read ones is that session's own note: it may have just
    # ended, or run a binary that hides its environment. With none read, the
    # running-process arm has judged nothing, and one line says so for the run.
    if [ "${#pane_unread[@]}" -ne 0 ]; then
        if [ "$panes_read" -eq 0 ]; then
            warnings+=("no agent session's running process could be read (${#pane_unread[@]} tried, through $pane_reader), so what these agents actually hold is UNVERIFIED. Not a benign skip: the session environment says what the next process in a pane gets, so a store leak that lives only in a running agent goes unreported.")
        else
            notes+=("${pane_unread[@]}")
        fi
    fi
fi

if [ "${#errors[@]}" -ne 0 ]; then
    echo "agent sessions disagree with their own store scope: ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "store-scope agreement partially determined: ${#warnings[@]} finding(s)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: $sessions_checked agent session(s) agree with their own store scope, $panes_read read at the running process"
detail ${notes[@]+"${notes[@]}"}
exit 0
