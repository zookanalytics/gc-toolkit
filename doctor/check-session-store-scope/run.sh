#!/usr/bin/env bash
# doctor/check-session-store-scope — a live agent's store env names its own
# scope. Two reads, answering two different questions:
#
#   PANE PROCESS — what the running agent actually has. A pane process carries
#   the session env plus whatever the tmux server's global environment showed
#   through, so it is the only place a leak is observable at all.
#   SESSION ENV — what the NEXT process in that pane will get. `respawn-pane`
#   takes no env argument, so a key the server holds and the session does not
#   mark removed reaches the respawned agent.
#
# Scope comes from the session's own identity — GC_ALIAS's rig prefix, else the
# `<rig>--` session-name prefix — and never from config: the proposition is
# that a session agrees with itself, which stays checkable when the config it
# was spawned from has since changed.
#
# GC_BEADS_PREFIX is not judged on its own, because its correct value is a
# property of the store rather than of the session. It never travels alone:
# in the gascity rig both writers, orderExecEnvWithError (cmd/gc/order_store.go)
# and the bd override builder (cmd/gc/cmd_bd.go), set GC_RIG, GC_RIG_ROOT,
# BEADS_DIR, GC_STORE_ROOT and GC_STORE_SCOPE into the same map beside it, and
# those five are judged here.
#
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Bounded probes; an unreadable session list warns, never passes.

set -u

city="${GC_CITY_PATH:-${GC_CITY:-}}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
PROC="${GC_DOCTOR_PROC_ROOT:-/proc}"

errors=(); warnings=(); notes=()
sessions_checked=0; panes_read=0
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
gcmux() { run_bounded tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

# env_val <key> <env-text> — the value of key, empty when absent or removed.
env_val() { printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1; }
# env_removed <key> <env-text> — true when tmux reports the key marked removed.
env_removed() { printf '%s\n' "$2" | grep -qx -- "-$1"; }
# rig_named_by <path> — the rig a path under <city>/rigs/ belongs to, else empty.
rig_named_by() {
    case "$1" in
        "$city"/rigs/*) local rest="${1#"$city"/rigs/}"; printf '%s' "${rest%%/*}" ;;
        *) : ;;
    esac
}

if ! command -v tmux >/dev/null 2>&1; then
    notes+=("tmux is not on PATH — a session environment is a runtime property, not verifiable here")
elif [ -z "$city" ]; then
    notes+=("no city in scope (GC_CITY_PATH/GC_CITY unset) — session environments not verifiable here")
else
    # Name and pane pid in one call: a per-session `list-panes` would double the
    # tmux round trips, and the doctor abandons a check at its own budget.
    sessions=$(gcmux list-sessions -F '#{session_name}	#{pane_pid}' 2>/dev/null); list_rc=$?
    global=$(gcmux show-environment -g 2>/dev/null)
    if [ "$list_rc" -ne 0 ]; then
        warnings+=("could not list tmux sessions (rc=$list_rc) — store-scope agreement UNVERIFIED. Not a benign skip: the symptom this check exists for is silent, and an agent reading the wrong store writes beads no queue that wants them can see.")
    elif [ -z "$sessions" ]; then
        notes+=("the tmux server holds no sessions — no agent environment to read")
    fi

    # Store-scope keys the runtime resolves per session. GC_STORE_SCOPE and
    # GC_BEADS_PREFIX are absent from a healthy session env: nothing seeds them
    # there, which is also why neither can be withheld on a respawn.
    scope_keys="GC_RIG GC_RIG_ROOT BEADS_DIR GC_STORE_ROOT GC_STORE_SCOPE GC_BEADS_PREFIX"
    path_keys="GC_RIG_ROOT BEADS_DIR GC_STORE_ROOT"

    TAB=$(printf '\t')
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        sess="${row%%"$TAB"*}"
        pane_pid=""
        case "$row" in *"$TAB"*) pane_pid="${row#*"$TAB"}" ;; esac
        [ -n "$sess" ] || continue
        # A session can end mid-scan; an unreadable one is not a finding.
        senv=$(gcmux show-environment -t "$sess" 2>/dev/null) || continue
        agent=$(env_val GC_AGENT "$senv")
        [ -n "$agent" ] || continue
        sess_city=$(env_val GC_CITY_PATH "$senv")
        [ -z "$sess_city" ] || [ "$sess_city" = "$city" ] || continue
        sessions_checked=$((sessions_checked + 1))

        # Rig prefix of the qualified alias when the session carries one; pool
        # members do not, and their session name carries the same prefix.
        alias_name=$(env_val GC_ALIAS "$senv")
        want_rig=""
        case "$alias_name" in
            */*) want_rig="${alias_name%%/*}" ;;
            "")  case "$sess" in *--*) want_rig="${sess%%--*}" ;; esac ;;
        esac
        want_scope="city"; [ -n "$want_rig" ] && want_scope="rig"
        scope_desc="city-scoped"; [ -n "$want_rig" ] && scope_desc="scoped to rig $want_rig"

        # --- Arm 1: the running process agrees with the session's own scope ---
        penv=""
        if [ -n "$pane_pid" ] && [ -r "$PROC/$pane_pid/environ" ]; then
            penv=$(tr '\0' '\n' < "$PROC/$pane_pid/environ" 2>/dev/null)
        fi
        if [ -z "$penv" ]; then
            notes+=("$sess: pane process environment unreadable (pane_pid=${pane_pid:-none}, $PROC) — what this agent actually holds was not read")
        else
            panes_read=$((panes_read + 1))
            got_rig=$(env_val GC_RIG "$penv")
            if [ "$got_rig" != "$want_rig" ]; then
                if [ -n "$got_rig" ]; then
                    errors+=("$sess is $scope_desc but its running process holds GC_RIG=$got_rig — every bd call it makes reads and writes rig $got_rig's store. Restart the session (\`gc agents restart $agent\`); if it recurs, the spawn is handing out a caller's scope.")
                else
                    errors+=("$sess is $scope_desc but its running process holds no GC_RIG — it resolves the city store instead of rig $want_rig's, so its work lands where that rig's queues cannot see it. Restart the session (\`gc agents restart $agent\`).")
                fi
            fi
            for key in $path_keys; do
                val=$(env_val "$key" "$penv")
                [ -n "$val" ] || continue
                named=$(rig_named_by "$val")
                [ -n "$named" ] || continue
                [ "$named" = "$want_rig" ] && continue
                errors+=("$sess is $scope_desc but its running process holds $key=$val, which names rig $named — restart the session (\`gc agents restart $agent\`) and re-read this check.")
            done
            got_scope=$(env_val GC_STORE_SCOPE "$penv")
            if [ -n "$got_scope" ] && [ "$got_scope" != "$want_scope" ]; then
                errors+=("$sess is $scope_desc but its running process holds GC_STORE_SCOPE=$got_scope, not $want_scope — restart the session (\`gc agents restart $agent\`).")
            fi
        fi

        # --- Arm 2: a respawn of this pane would not inherit a store key ------
        # Only city-scoped sessions are exposed: a rig-scoped one sets each key
        # to its own value, which shadows the server's.
        [ -n "$want_rig" ] && continue
        for key in $scope_keys; do
            gval=$(env_val "$key" "$global")
            [ -n "$gval" ] || continue
            [ -n "$(env_val "$key" "$senv")" ] && continue
            env_removed "$key" "$senv" && continue
            warnings+=("$sess is city-scoped and its session environment neither sets nor removes $key, while the tmux server's global environment holds $key=$gval — \`respawn-pane\` takes no env argument, so the next process in this pane inherits it. Clear it on the server (\`tmux set-environment -gu $key\`) and restart the session.")
        done
    done <<< "$sessions"
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
