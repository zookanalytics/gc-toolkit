#!/usr/bin/env bash
# doctor/check-hq-marooned-work — no rig-workable bead sits unclaimed in the HQ
# (city / lx) store where no worker will reach it. A city-scoped role (deacon,
# mechanik, dog) runs with GC_RIG unset, so a bare `bd create` resolves to the
# HQ store instead of a rig store. Rig pools never read the HQ store, so rig work
# filed there is marooned by construction: invisible to every rig queue, surfaced
# by nothing. A city-scoped pool DOES read the HQ store, so a bead routed to one
# (a warrant to the dog) is reachable and belongs there. This check reads the HQ
# store and flags each rig-workable bead that no worker is positioned to claim.
#
# Rig-workable = an OPEN, UNASSIGNED bead whose issue_type is not an infra type
# (the INFRA_TYPES set defined below), which is neither city machinery nor
# held-by-design, and which is unrouted or routed to a rig pool that cannot see
# it. The exclusions carve out the legitimate HQ
# residents: a bead routed to a city-scoped agent (resolved from `gc agent list`)
# is reachable there; a `warrant` label marks city machinery a rig never works; a
# standing record (a task_kind assets/scripts/standing-kinds.sh lists) is a
# held-by-design escalation host, not work; a `human` route or a task_kind=visit
# is an operator-queue decision; a `deacon-ledger` label is a daily digest; a
# `debt` label or a `gc doctor:` title is a doctor/tech-debt advisory record. An
# assigned bead is already claimed. What remains is rig work no worker can reach.
#
# The HQ store is $city_path/.beads, where city_path is `gc agent list`'s
# resolution (GC_CITY_PATH is the fallback). Read-only. Exit 0=OK 1=Warning
# 2=Error. stdout: message, then "  - detail" lines. Bounded probes; an
# unreadable HQ store warns (1), never passes.

set -u

city="${GC_CITY_PATH:-${GC_CITY:-}}"

# Infra issue_types a pool never works: the shape that marks a bead as HQ
# machinery rather than rig work. These mirror gascity's Ready() type exclusions
# (readyExcludeTypes in internal/beads/beads.go), the set the bd CLI's
# GetReadyWork query also excludes. No CLI surface dumps that map, so this list
# is a hand-kept copy; re-sync it when gascity adds a machinery type. Two local
# choices sit on top of the mirror: chore is added, because gascity files its
# nudge queue as chore beads and one in the HQ store is city machinery, not rig
# work; spec is left off, because a spec is real rig work and one marooned in the
# HQ store must still be caught.
INFRA_TYPES='["session","message","molecule","chore","rig","agent","role","gate","merge-request","step","convoy","startup-health-episode"]'

# Standing-record task_kinds: a held-by-design host for escalation or feedback
# state, not work anyone claims. The one definition, shared with the liveness
# sweep and the proactive scan, exposes $STANDING_KINDS_JQ. An unsourceable one
# warns: without it a standing record would read as marooned work.
# shellcheck source=../../assets/scripts/standing-kinds.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/standing-kinds.sh" || {
    echo "cannot determine whether the HQ store holds marooned work"
    printf '  - %s\n' "assets/scripts/standing-kinds.sh could not be sourced from this pack, so a standing record cannot be told from marooned work."
    exit 1
}

findings=(); warnings=(); notes=()
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
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
# >>> doctor-parallel-reads
# A check that overlaps its probes runs each one as a background job, and a job
# cannot hand its parent a variable, so every read lands in a file under one
# scratch tree. reads_init <check> makes that tree, sets WORK to it, and removes
# it when the check exits. It holds a file in the tree open on fd 9, because the
# host's scratch reaper removes any gctk-* tree that no process holds open. It
# returns non-zero when the tree cannot be made or held, and then nothing can be
# read.
reads_init() {
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-$1.XXXXXX" 2>/dev/null) || { WORK=""; return 1; }
    trap '[ -z "$WORK" ] || rm -rf "$WORK"' EXIT
    { exec 9>"$WORK/.hold"; } 2>/dev/null
}
# read_to <file> <probe...> runs one bounded probe with its stdout scrubbed into
# <file> and its stderr in <file>.err, and returns the probe's own exit status.
# err_of <file> prints the first non-blank line of that stderr, with control
# characters stripped and cut to 200 characters, so the warning for a failed
# read names why it failed and not only its rc. Before a `gc bd` list, ready,
# search or show runs bd, gc writes a line naming the store that answers it,
# whether or not the read then fails. That line never says why a read failed,
# so err_of passes over it.
read_to() {
    local f="$1"; shift
    run_bounded "$@" 2>"$f.err" | scrub >"$f"
    return "${PIPESTATUS[0]}"
}
err_of() {
    [ -s "$1.err" ] || return 0
    tr -d '\000-\010\013-\037' <"$1.err" 2>/dev/null \
        | grep -v '^gc bd: answering from the .* store$' | grep -m1 '[^[:space:]]' | cut -c1-200
}
# fanout <command...> starts <command> as a background job once fewer than
# FANOUT_CAP of the jobs fanout started are still running, so a check scans at
# most that many stores at once however many rigs the city lists. FANOUT_PID is
# the job it started. fanout_wait <pid> waits for one of those jobs and returns
# its exit status, which the cap keeps for a job it has already waited for. The
# cap waits only for fanout's own jobs, because a bare `wait -n` also returns
# for the check's other background reads, and the count of running jobs would
# drift. When `wait -n` reports no job, the cap waits for the oldest one, so
# each wait frees a slot. GC_DOCTOR_FANOUT overrides the cap, in jobs.
FANOUT_CAP="${GC_DOCTOR_FANOUT:-8}"
case "$FANOUT_CAP" in ''|*[!0-9]*) FANOUT_CAP=8 ;; esac
[ "$FANOUT_CAP" -ge 1 ] 2>/dev/null || FANOUT_CAP=8
fanout_live=(); declare -A fanout_rc=()
fanout_reaped() {
    local p keep=()
    fanout_rc["$1"]="$2"
    for p in ${fanout_live[@]+"${fanout_live[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
    fanout_live=(${keep[@]+"${keep[@]}"})
}
fanout() {
    local pid rc
    while [ "${#fanout_live[@]}" -ge "$FANOUT_CAP" ]; do
        pid=""; wait -n -p pid "${fanout_live[@]}"; rc=$?
        if [ -z "$pid" ]; then pid="${fanout_live[0]}"; wait "$pid"; rc=$?; fi
        fanout_reaped "$pid" "$rc"
    done
    "$@" &
    FANOUT_PID=$!
    fanout_live+=("$FANOUT_PID")
}
fanout_wait() {
    local rc
    if [ -n "${fanout_rc[$1]+set}" ]; then return "${fanout_rc[$1]}"; fi
    wait "$1"; rc=$?
    fanout_reaped "$1" "$rc"
    return "$rc"
}
# <<< doctor-parallel-reads
if ! reads_init check-hq-marooned-work; then
    echo "cannot determine whether the HQ store holds marooned work"
    detail "could not create a scratch directory under ${TMPDIR:-/tmp}, which every probe reads into; the HQ store was NOT checked."
    exit 1
fi

# --- Locate the HQ store ----------------------------------------------------
# `gc agent list` resolves the city root authoritatively; GC_CITY_PATH is the
# fallback when that probe cannot answer. Without a city root there is no HQ
# store to read, so the check cannot run — a warning, never a clean pass.
read_to "$WORK/agents.json" gc agent list --json; agents_rc=$?; agents_err=$(err_of "$WORK/agents.json")
city_path=""
[ "$agents_rc" -eq 0 ] && city_path=$(jq -r '.city_path // ""' "$WORK/agents.json" 2>/dev/null)
[ -n "$city_path" ] || city_path="$city"
# City-scoped agents read the HQ store, so a bead routed to one is reachable, not
# marooned. Resolve their identities from the same agent list (bare, the form a
# route carries — resolve-route.sh). When the list cannot answer the set is
# empty, and only the `warrant` label still exempts city machinery.
CITY_ROUTES='[]'
[ "$agents_rc" -eq 0 ] && CITY_ROUTES=$(jq -c '[.agents[]? | select(.scope == "city") | .qualified_name // empty] | unique' "$WORK/agents.json" 2>/dev/null)
[ -n "$CITY_ROUTES" ] || CITY_ROUTES='[]'
if [ -z "$city_path" ]; then
    echo "cannot determine whether the HQ store holds marooned work"
    detail "\`gc agent list --json\` reported no city_path (rc=$agents_rc) and neither GC_CITY_PATH nor GC_CITY is set, so the HQ store cannot be located."
    [ -n "$agents_err" ] && detail "\`gc agent list\` stderr: $agents_err"
    exit 1
fi
STORE="$city_path/.beads"

# --- Read the HQ store and classify ----------------------------------------
listing="$WORK/open.json"
read_to "$listing" gc bd list --db "$STORE" --status open --json --limit 0; rc=$?; list_err=$(err_of "$listing")
if [ "$rc" -ne 0 ] || [ ! -s "$listing" ]; then
    echo "cannot determine whether the HQ store holds marooned work"
    detail "could not list open beads in $STORE (rc=$rc) — the HQ store was NOT checked; an unreadable store is not proof it is clean.${list_err:+ \`gc bd list\` stderr: $list_err}"
    exit 1
fi
rows=$(jq -r --argjson infra "$INFRA_TYPES" --argjson city_routes "$CITY_ROUTES" "$STANDING_KINDS_JQ"'
    .[]? | . as $b
    | (($b.issue_type // "") | tostring) as $t
    | (($b.metadata // {})) as $m
    | (($m["task_kind"] // "") | tostring) as $tk
    | (($m["gc.routed_to"] // "") | tostring) as $rt
    | (($b.labels // []) | map(tostring)) as $labels
    | (($b.title // "") | tostring) as $title
    | (($b.assignee // "") | tostring) as $as
    | ($rt | sub("^.*/"; "")) as $rtb                 # bare identity a city route carries (resolve-route.sh)
    | select(($infra | index($t)) == null)            # not HQ machinery (infra type)
    | select($as == "")                               # unassigned — not already claimed
    | select(($city_routes | index($rtb)) == null)    # not routed to a city-scoped agent that reads the HQ store
    | select(($labels | index("warrant")) == null)    # not a warrant (city machinery a rig never works)
    | select(($b | is_standing_kind) | not)           # not a held-by-design standing record
    | select($tk != "visit")                          # not an operator-queue converse visit
    | select($rt != "human")                          # not an operator-queue decision routed to a person
    | select(($labels | index("deacon-ledger")) == null)  # not a daily digest
    | select(($labels | index("debt")) == null)       # not a parked tech-debt / advisory record
    | select(($title | test("^gc doctor:")) == false) # not a doctor advisory record
    | [ ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")),
        (if $t == "" then "untyped" else $t end),
        (if $rt == "" then "unrouted" else "routed to " + $rt end)
      ] | join("\u001f")' "$listing" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "cannot determine whether the HQ store holds marooned work"
    detail "the open-bead listing from $STORE could not be parsed — the HQ store was NOT checked."
    exit 1
fi

while IFS=$'\037' read -r id type route; do
    [ -n "$id" ] || continue
    findings+=("$id ($type, $route): rig-workable bead in the HQ store $STORE — no pool reads that store, so it is unclaimable and shows in no rig queue; re-home it into a rig with assets/scripts/bead-rehome.sh, or route it to a rig pool")
done <<< "$rows"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
examined=$(jq -r 'length' "$listing" 2>/dev/null)
if [ "${#findings[@]}" -ne 0 ]; then
    echo "rig-workable bead(s) marooned in the HQ store: ${#findings[@]} finding(s)"
    detail "${findings[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "HQ-store marooned-work check partially determined"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: no rig-workable bead is marooned in the HQ store ($STORE; ${examined:-0} open bead(s) examined, all legitimate HQ contents)"
detail ${notes[@]+"${notes[@]}"}
exit 0
