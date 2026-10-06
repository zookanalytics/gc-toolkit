#!/usr/bin/env bash
# pool-slot-reap.sh — close the asleep pool session beads that hold a pool slot
# with no runtime and no work, so a pool does not run below its cap behind a
# session nothing will wake or free.
#
# The controller counts every open pool session bead except a failed create as
# occupying its slot, whatever its state. It frees a slot only when the session
# in it sleeps for a reason on core's freeable list (idle, idle-timeout,
# city-stop, failed-create, runtime-missing, provider-terminal-error,
# max-session-age and drained among them), and it reuses an asleep bead only
# for a one_shot pool. `gc session kill` puts a
# session to sleep with sleep_reason=killed, which is not on that list, so a
# killed pool session that holds no work keeps its slot with nothing running in
# it until someone closes the bead. Core's undesired-pool sweep closes some of
# these beads and leaves others for hours or days, including beads that sleep
# for a freeable reason. Meanwhile the pool reports its cap and runs below it.
#
# This pass is the backstop. It closes a session bead with `gc session close`
# only when all of these hold:
#   - the bead is pool-managed (session_origin=ephemeral, pool_managed=true, or
#     a pool_slot), and is neither a configured named session nor a manual one;
#   - its persisted state is asleep (or drained), and both its slept_at and any
#     wake_requested_at are older than the grace window;
#   - it carries no deliberate hold: no user-hold, wait-hold, quarantine,
#     context-churn or rate_limit sleep, no held_until, quarantined_until or
#     wait_hold marker, and no pin_awake;
#   - no bead in any rig's store is open or in_progress under its id, its
#     session_name, its configured named identity, or, unless it sits in an
#     ordinary numbered pool (below), its alias or a prior alias;
#   - a second read just before the close finds the same lifecycle facts.
#
# Runtime liveness comes from the persisted state. The controller heals a row
# whose runtime it sees alive back to awake on its next tick, and a
# `gc session kill` fences that heal only while its own teardown runs (five
# minutes at most). So a bead that has been asleep for the whole grace window
# has had no runtime the controller could see for that long. `gc session close`
# stops a runtime that is running, which is why the grace window and the
# second read gate every close.
#
# The grace window also leaves core the first move. Core closes a bead whose
# reason it frees on the tick the runtime goes, so a bead still open past the
# window is one core has left behind, whatever its reason.
#
# A numbered pool slot's name (agent_name, e.g. <rig>/<pack>.polecat-2) is not
# an identity this pass searches for work. The slot passes to whichever session
# holds it next, and core's own work guards never treat it as an owner. Work
# assigned under it belongs to the slot, and it is the slot this close frees.
# An older bead of an ordinary numbered pool can also carry the slot name as its
# alias or a prior alias, so for such a bead neither is searched. The configured
# agent decides, as it does for core's guards: a slotted bead whose agent has no
# namepool and a cap other than 1 is in an ordinary numbered pool. A namepool
# name or a canonical singleton's name stays with its session, so it is searched.
#
# Blocked work does not keep a bead open either. It is parked behind a hold a
# human or an edge releases, and nothing executes it until that release
# re-homes it. Core's close gates count open and in_progress work only, for the
# same reason.
#
# Each close is recorded as one `cleanup` entry in the city's incident ledger
# (gc-deacon-ledger.sh), naming the bead, its slot and why it slept. The
# summary line lists the beads closed.
#
# City scope: session beads live in the city store and their work can sit in
# any rig's store, so one pass reads the whole city. A pass skipped or cut short
# costs only the close the next pass takes instead. Candidates past the pass
# budget are deferred to the next pass, not dropped.
#
# Bias: an unreadable probe closes NOTHING. A bead that cannot be read, a store
# that cannot be queried, or a second read that differs from the first leaves
# the bead open for a later pass. An alias the pass cannot place in a pool kind
# is searched as an owner. That covers every alias when the agent config cannot
# be read or fails core's validation, and the aliases of a bead whose template
# matches no configured agent or agents of both kinds.
#
# Environment:
#   POOL_SLOT_REAP_GRACE_S   seconds a bead must have been asleep (default 900)
#   POOL_SLOT_REAP_BUDGET_S  seconds after which remaining candidates are
#                            deferred to the next pass (default 240)
#
# Usage:
#   pool-slot-reap.sh            close ghost pool sessions, print a summary
#   pool-slot-reap.sh --dry-run  report the plan, close nothing
# Exit: 0 closed or nothing to do · 1 the session list or the rig roster could
#       not be read, the candidate set could not be enumerated, or a close could
#       not be recorded in the ledger · 2 usage
# Caller: the pool-slot-reap cooldown order.
set -uo pipefail

PROG="${0##*/}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;/^set -u/d'; exit 0 ;;
        *) echo "$PROG: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }

GC="${POOL_SLOT_REAP_GC:-gc}"
LEDGER="${POOL_SLOT_REAP_LEDGER:-$HERE/gc-deacon-ledger.sh}"
GRACE_S="${POOL_SLOT_REAP_GRACE_S:-900}"
BUDGET_S="${POOL_SLOT_REAP_BUDGET_S:-240}"
CALL_TIMEOUT_S="${POOL_SLOT_REAP_CALL_TIMEOUT_S:-60}"
for knob in GRACE_S BUDGET_S CALL_TIMEOUT_S; do
    case "${!knob}" in
        ''|*[!0-9]*) echo "$PROG: POOL_SLOT_REAP_$knob must be a whole number of seconds (got '${!knob}')" >&2; exit 2 ;;
    esac
done

# Every gc call is bounded where the host has timeout(1), so one hung store read
# costs this candidate and not the pass. stdin is closed so no call can consume
# the candidate enumeration.
if command -v timeout >/dev/null 2>&1; then
    call() { timeout "$CALL_TIMEOUT_S" "$@" </dev/null; }
else
    call() { "$@" </dev/null; }
fi

START="$(date -u +%s)"

# Every session, every state. A non-object answer, or one without a .sessions
# array, is a listing we cannot trust: close nothing and say so with exit 1.
sessions_json="$(call "$GC" session list --state all --json 2>/dev/null)" || sessions_json=""
if ! printf '%s' "$sessions_json" | jq -e 'type=="object" and (.sessions|type=="array")' >/dev/null 2>&1; then
    echo "$PROG: could not read the session list — closing nothing" >&2
    exit 1
fi

# The listing's state is the runtime overlay: persisted awake and drained read
# as active and asleep, and an awake row whose runtime is gone reads as asleep.
# So asleep here is the cheap superset; the persisted state on the bead itself
# decides.
candidates="$(printf '%s' "$sessions_json" | jq -r '
    .sessions[]?
    | select((.closed // false) == false)
    | select((.state // "") == "asleep")
    | .id // empty')"; cand_rc=$?
if [ "$cand_rc" -ne 0 ]; then
    echo "$PROG: could not enumerate asleep sessions (jq exit $cand_rc) — closing nothing" >&2
    exit 1
fi

verb="closed"; [ "$DRY_RUN" -eq 1 ] && verb="would close"
summary() { # <closed> <kept> <skipped> <deferred>
    echo "$PROG: $verb $1, kept $2, skipped $3, deferred $4 of the asleep sessions; a close needs a pool session asleep past ${GRACE_S}s with no runtime and no work"
}

if [ -z "$candidates" ]; then
    summary 0 0 0 0
    exit 0
fi

# Every rig's store, the city's own included: work assigned to a session can
# sit in any of them. The roster's city path is also where the incident ledger
# runs, so each close is recorded in the city whose stores this pass searched.
rigs_json="$(call "$GC" rig list --json 2>/dev/null)" || rigs_json=""
CITY_PATH="$(printf '%s' "$rigs_json" | jq -r '(.city_path // "") | strings' 2>/dev/null)"
STORE_LIST=()
mapfile -t STORE_LIST < <(printf '%s' "$rigs_json" | jq -r '[.rigs[]? | (.path // "") | select(. != "") | . + "/.beads"] | unique | .[]' 2>/dev/null)
if [ -z "$CITY_PATH" ] || [ "${#STORE_LIST[@]}" -eq 0 ]; then
    echo "$PROG: could not read the rig roster (gc rig list --json) — closing nothing" >&2
    exit 1
fi

# The same city's configured agents, each marked stable when its pool members
# keep their names (a namepool, or a cap of 1) and not when its slots rebind.
# identities() reads this to tell an ordinary numbered pool's slot alias from a
# name that stays with its session. An answer with no agent list fails the read,
# and a failed read leaves AGENTS null, so every alias is searched as an owner.
# So does a config that fails core's validation, because the controller refuses
# to load one and keeps running the config it had.
cfg_json="$(call "$GC" config show --json --city "$CITY_PATH" 2>/dev/null)" || cfg_json=""
AGENTS="$(printf '%s' "$cfg_json" | jq -c '
    if .validation.ok == true then
        [.config.Agents[] | {dir: ((.Dir // "") | tostring), name: ((.Name // "") | tostring),
            stable: ((((.Namepool // "") | tostring) != "") or (((.NamepoolNames // []) | length) > 0)
                     or (.MaxActiveSessions == 1))}]
    else null end' 2>/dev/null)" || AGENTS=""
if [ -z "$AGENTS" ] || [ "$AGENTS" = "null" ]; then
    AGENTS="null"
    echo "$PROG: could not read a valid agent config (gc config show --json) — every alias is searched as an owner this pass" >&2
fi

# One bead's lifecycle verdict, read from a `gc bd show --json` answer:
#   <verdict>\x1f<detail>\x1f<slot>\x1f<sleep_reason>\x1f<slept_at>\x1f<fingerprint>
# verdict is eligible, or keep/skip with the reason in detail. The fingerprint
# is the set of lifecycle facts the second read must find unchanged.
classify() { # <bead-id> <show-json>
    printf '%s' "$2" | jq -r --arg id "$1" --argjson now "$(date -u +%s)" --argjson grace "$GRACE_S" '
        def ts: (. // "") | tostring
            | if . == "" then null
              else (sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch null)) end;
        def row: if type == "array" then (map(select((.id // "") == $id)) | first)
                 elif type == "object" and (.id // "") == $id then .
                 else null end;
        row as $b
        | if $b == null then ["skip", "unreadable: no bead answered for this id", "", "", "", ""]
          else
            ($b.metadata // {}) as $m
            | def s(k): ($m[k] // "") | tostring;
            (s("sleep_reason")) as $sr
            | (s("state")) as $st
            | ([($b.status // ""), $st, $sr, s("slept_at"), s("wake_request"), s("wake_requested_at"),
                s("held_until"), s("quarantined_until"), s("wait_hold"), s("pin_awake"),
                s("pending_create_claim")] | join("|")) as $fp
            | (if s("agent_name") != "" then s("agent_name") else s("template") end) as $slot
            | (s("slept_at") | ts) as $slept
            | (s("wake_requested_at") | ts) as $woke
            | (if $woke != null and $slept != null and $woke > $slept then $woke else $slept end) as $since
            | (if ($b.issue_type // "") != "session" then ["skip", "not a session bead"]
               elif ($b.status // "") != "open" then ["skip", "already " + ($b.status // "closed")]
               elif s("configured_named_session") == "true" then ["keep", "named session"]
               elif s("session_origin") == "manual" or s("manual_session") == "true" then ["keep", "manual session"]
               elif (s("session_origin") != "ephemeral" and s("pool_managed") != "true" and s("pool_slot") == "")
                 then ["keep", "not pool-managed"]
               elif ($st != "asleep" and $st != "drained") then ["keep", "persisted state " + (if $st == "" then "unset" else $st end)]
               elif (["user-hold", "wait-hold", "quarantine", "context-churn", "rate_limit"] | any(. == $sr))
                 then ["keep", "held (" + $sr + ")"]
               elif s("held_until") != "" or s("quarantined_until") != "" or s("wait_hold") != ""
                 then ["keep", "held (hold marker set)"]
               elif s("pin_awake") == "true" then ["keep", "pinned awake"]
               elif $slept == null then ["keep", "unaged: no readable slept_at"]
               elif ($now - $since) < $grace then ["keep", "settling: asleep or wake-requested within the grace window"]
               else ["eligible", "asleep since " + s("slept_at")] end)
            + [$slot, $sr, s("slept_at"), $fp]
          end
        | map(tostring) | join("\u001f")' 2>/dev/null
}

# The identities work can be assigned to this session under: its id, its
# session_name, its configured named identity, and its alias and any prior
# alias. The aliases are left out for a bead in an ordinary numbered pool: one
# with a pool_slot whose template names only agents AGENTS marks not stable. A
# template names an agent by its dir, the part before the last "/", and its
# name, the part after the last "." (agent names hold no dot). The binding
# between them is not in the config read, so agents of two bindings can match,
# and the aliases are left out only when none of them is stable.
identities() { # <bead-id> <show-json>
    printf '%s' "$2" | jq -r --arg id "$1" --argjson agents "$AGENTS" '
        (if type == "array" then (map(select((.id // "") == $id)) | first)
         elif type == "object" and (.id // "") == $id then . else null end) as $b
        | ($b.metadata // {}) as $m
        | def s(k): ($m[k] // "") | tostring | gsub("^\\s+|\\s+$"; "");
        (s("template")) as $t
        | ($t | if test("/") then sub("/[^/]*$"; "") else "" end) as $dir
        | ($t | sub("^.*/"; "") | sub("^.*\\."; "")) as $name
        | [($agents // [])[] | select(.dir == $dir and .name == $name)] as $cfg
        | (s("pool_slot") != "" and ($cfg | length) > 0 and ($cfg | all(.stable | not))) as $numbered
        | ([$b.id, s("session_name"), s("configured_named_identity")]
           + (if $numbered then [] else [s("alias")] + (s("alias_history") | split(",")) end))
        | map((. // "") | tostring | gsub("^\\s+|\\s+$"; "")) | map(select(. != "")) | unique | .[]' 2>/dev/null
}

# held_work <identity>... -> prints "none", "held <store> <bead>", or
# "unreadable <store> <identity>". Session beads are not work, as in core's own
# guard. The first store answer that is not a JSON array ends the search
# unreadable: a failed read is not an empty one. "none" is printed only after
# every store was asked about every identity, so a search that ran short never
# reads as a proven no.
held_work() {
    local store ident out first asked=0
    [ "$#" -gt 0 ] || { printf 'unreadable - no identities\n'; return 0; }
    for store in "${STORE_LIST[@]}"; do
        for ident in "$@"; do
            out="$(call "$GC" bd list --db "$store" --assignee "$ident" --status open,in_progress \
                --limit 0 --include-infra --include-ephemeral --json 2>/dev/null)" || out=""
            if ! printf '%s' "$out" | jq -e 'type=="array"' >/dev/null 2>&1; then
                printf 'unreadable %s %s\n' "$store" "$ident"; return 0
            fi
            first="$(printf '%s' "$out" | jq -r '[.[] | select((.issue_type // "") != "session")] | first | .id // empty' 2>/dev/null)" || {
                printf 'unreadable %s %s\n' "$store" "$ident"; return 0
            }
            if [ -n "$first" ]; then
                printf 'held %s %s\n' "$store" "$first"; return 0
            fi
            asked=$((asked + 1))
        done
    done
    if [ "$asked" -eq $(( ${#STORE_LIST[@]} * $# )) ]; then
        printf 'none\n'
    else
        printf 'unreadable - asked %s of %s store reads\n' "$asked" "$(( ${#STORE_LIST[@]} * $# ))"
    fi
}

closed=0; kept=0; skipped=0; deferred=0; unrecorded=0
closed_lines=""; other_lines=""

# tally <kept|skipped|deferred> <session-id> <why>: count one candidate that
# was not closed and say why, so a hand run reads as a plan.
tally() {
    case "$1" in
        kept)     kept=$((kept + 1)) ;;
        skipped)  skipped=$((skipped + 1)) ;;
        deferred) deferred=$((deferred + 1)) ;;
    esac
    other_lines="${other_lines}  $2 ${slot:--} $1: $3
"
}

# Drive the loop from a checked, producer-named temp file rather than a `<<<`
# here-string. bash backs `<<<` with an implicit temp file; under disk pressure
# that file cannot be created, the redirection fails with no `set -e` to catch
# it, the loop runs zero times, and the summary would print a closed-nothing
# all-clear. A checked mktemp, a checked write, and a processed-equals-expected
# assertion each abort non-zero instead. Reading from the file keeps the loop in
# this shell, so the counters survive.
ROWS="$(mktemp "${TMPDIR:-/tmp}/gctk-pool-slot-reap.XXXXXX" 2>/dev/null)" || {
    echo "$PROG: could not create a temp file to enumerate asleep sessions — closing nothing" >&2
    exit 1
}
trap 'rm -f "$ROWS" 2>/dev/null' EXIT
printf '%s\n' "$candidates" > "$ROWS" || {
    echo "$PROG: could not write the asleep-session enumeration — closing nothing" >&2
    exit 1
}
expected="$(grep -c . "$ROWS" 2>/dev/null || true)"; case "$expected" in ''|*[!0-9]*) expected=0 ;; esac
processed=0

while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    processed=$((processed + 1))
    slot=""

    if [ $(( $(date -u +%s) - START )) -ge "$BUDGET_S" ]; then
        tally deferred "$sid" "the pass budget (${BUDGET_S}s) ran out"; continue
    fi

    # Fields arrive through process substitution, never a here-string: a read
    # that fails leaves them empty, and an empty verdict is a skip.
    show="$(call "$GC" bd show "$sid" --json 2>/dev/null)" || true
    verdict=""; detail=""; reason=""; slept=""; fp=""
    IFS=$'\037' read -r verdict detail slot reason slept fp < <(classify "$sid" "$show")
    case "$verdict" in
        eligible) ;;
        keep) tally kept "$sid" "$detail"; continue ;;
        skip) tally skipped "$sid" "$detail"; continue ;;
        *)    tally skipped "$sid" "unreadable: the bead read could not be classified"; continue ;;
    esac

    ID_LIST=()
    mapfile -t ID_LIST < <(identities "$sid" "$show")
    work="$(held_work "${ID_LIST[@]}")"
    case "$work" in
        none) ;;
        held\ *)
            tally kept "$sid" "work ${work##* } is assigned to it"; continue ;;
        *)
            tally skipped "$sid" "assigned work could not be read (${work#unreadable })"; continue ;;
    esac

    # The second read: the work search above takes seconds, and a session someone
    # has just woken, held, or reassigned must not be closed on the first read.
    show2="$(call "$GC" bd show "$sid" --json 2>/dev/null)" || true
    verdict2=""; fp2=""
    IFS=$'\037' read -r verdict2 _ _ _ _ fp2 < <(classify "$sid" "$show2")
    if [ "$verdict2" != "eligible" ] || [ "$fp2" != "$fp" ]; then
        tally kept "$sid" "its lifecycle changed during the pass"; continue
    fi

    line="${sid} ${slot} (sleep_reason=${reason:-none}, asleep since ${slept}): no runtime, no assigned work"
    if [ "$DRY_RUN" -eq 1 ]; then
        closed=$((closed + 1))
        closed_lines="${closed_lines}  ${line}
"
        continue
    fi
    if ! call "$GC" session close "$sid" >/dev/null 2>&1; then
        tally skipped "$sid" "gc session close failed; left for the next pass"
        echo "$PROG: could not close $sid — left for the next pass" >&2
        continue
    fi
    closed=$((closed + 1))
    closed_lines="${closed_lines}  ${line}
"
    if ! GC_CITY_PATH="$CITY_PATH" call "$LEDGER" append cleanup \
            "pool-slot-reap closed $line" "bead:$sid" >/dev/null 2>&1; then
        unrecorded=$((unrecorded + 1))
        echo "$PROG: closed $sid but could not record it in the incident ledger: $line" >&2
    fi
done < "$ROWS"
rm -f "$ROWS"

# A loop that read fewer rows than were enumerated did not see the whole
# candidate set. Abort non-zero rather than print an all-clear for a partial
# pass.
[ "$processed" -eq "$expected" ] || {
    echo "$PROG: read $processed of $expected candidate rows — the pass is incomplete" >&2
    exit 1
}

summary "$closed" "$kept" "$skipped" "$deferred"
[ -n "$closed_lines" ] && printf '%s' "$closed_lines"
[ -n "$other_lines" ] && printf '%s' "$other_lines"
[ "$unrecorded" -eq 0 ] || exit 1
exit 0
