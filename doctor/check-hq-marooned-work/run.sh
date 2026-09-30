#!/usr/bin/env bash
# doctor/check-hq-marooned-work — no rig-workable bead sits unclaimed in the HQ
# (city / lx) store. A city-scoped role (deacon, mechanik, mayor, dog) runs with
# GC_RIG unset, so a bare `bd create` resolves to the HQ store instead of a rig
# store. No pool reads the HQ store, so a work bead filed there is marooned by
# construction — unclaimable, invisible to every rig queue, and surfaced by
# nothing. This check reads the HQ store and flags each rig-workable bead in it.
#
# Rig-workable = an OPEN, UNASSIGNED bead whose issue_type is not an infra type
# (session/message/molecule/chore/rig/agent/role/gate/merge-request) and which is
# either unrouted or routed to a pool. The exclusions carve out the legitimate
# HQ residents: a bead routed to `human` or carrying task_kind=visit is an
# operator-queue decision; a `deacon-ledger` label is a daily digest; a `debt`
# label or a `gc doctor:` title is a doctor/tech-debt advisory record. An
# assigned bead is already claimed, not marooned. What remains is work no rig
# worker can reach.
#
# The HQ store is $city_path/.beads, where city_path is `gc agent list`'s
# resolution (GC_CITY_PATH is the fallback). Read-only. Exit 0=OK 1=Warning
# 2=Error. stdout: message, then "  - detail" lines. Bounded probes; an
# unreadable HQ store warns (1), never passes.

set -u

city="${GC_CITY_PATH:-${GC_CITY:-}}"

# Infra issue_types a pool never works — the shape that marks a bead as HQ
# machinery rather than rig work. Mirrors beads' ready-work exclusions plus the
# session type, which `bd list` also surfaces.
INFRA_TYPES='["session","message","molecule","chore","rig","agent","role","gate","merge-request"]'

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
# >>> probe-stderr-capture
# The gc probes below send stderr to $PROBE_ERR, not /dev/null, so a failure the
# check reports names the reason it failed instead of only its rc. Each probe's
# `2>"$PROBE_ERR"` truncates the file, so it never holds a prior probe's stderr.
# probe_err returns the first non-blank line, control characters stripped to keep
# it one line and length-capped. mktemp failing degrades to /dev/null (always
# empty), so probe_err yields nothing and every detail reads as before.
PROBE_ERR=$(mktemp "${TMPDIR:-/tmp}/gctk-check-hq-marooned-work.XXXXXX" 2>/dev/null) || PROBE_ERR=/dev/null
[ "$PROBE_ERR" = /dev/null ] || trap 'rm -f "$PROBE_ERR"' EXIT
probe_err() {
    [ -s "$PROBE_ERR" ] || return 0
    tr -d '\000-\010\013-\037' < "$PROBE_ERR" 2>/dev/null | grep -m1 '[^[:space:]]' | cut -c1-200
}
# <<< probe-stderr-capture

# --- Locate the HQ store ----------------------------------------------------
# `gc agent list` resolves the city root authoritatively; GC_CITY_PATH is the
# fallback when that probe cannot answer. Without a city root there is no HQ
# store to read, so the check cannot run — a warning, never a clean pass.
agents_raw=$(run_bounded gc agent list --json 2>"$PROBE_ERR"); agents_rc=$?; agents_err=$(probe_err)
city_path=""
[ "$agents_rc" -eq 0 ] && city_path=$(printf '%s' "$agents_raw" | scrub | jq -r '.city_path // ""' 2>/dev/null)
[ -n "$city_path" ] || city_path="$city"
if [ -z "$city_path" ]; then
    echo "cannot determine whether the HQ store holds marooned work"
    detail "\`gc agent list --json\` reported no city_path (rc=$agents_rc) and neither GC_CITY_PATH nor GC_CITY is set, so the HQ store cannot be located."
    [ -n "$agents_err" ] && detail "\`gc agent list\` stderr: $agents_err"
    exit 1
fi
STORE="$city_path/.beads"

# --- Read the HQ store and classify ----------------------------------------
raw=$(run_bounded gc bd list --db "$STORE" --status open --json --limit 0 2>"$PROBE_ERR"); rc=$?; list_err=$(probe_err)
if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
    echo "cannot determine whether the HQ store holds marooned work"
    detail "could not list open beads in $STORE (rc=$rc) — the HQ store was NOT checked; an unreadable store is not proof it is clean.${list_err:+ \`gc bd list\` stderr: $list_err}"
    exit 1
fi
rows=$(printf '%s' "$raw" | scrub | jq -r --argjson infra "$INFRA_TYPES" '
    .[]? | . as $b
    | (($b.issue_type // "") | tostring) as $t
    | (($b.metadata // {})) as $m
    | (($m["task_kind"] // "") | tostring) as $tk
    | (($m["gc.routed_to"] // "") | tostring) as $rt
    | (($b.labels // []) | map(tostring)) as $labels
    | (($b.title // "") | tostring) as $title
    | (($b.assignee // "") | tostring) as $as
    | select(($infra | index($t)) == null)            # not HQ machinery (infra type)
    | select($as == "")                               # unassigned — not already claimed
    | select($tk != "visit")                          # not an operator-queue converse visit
    | select($rt != "human")                          # not an operator-queue decision routed to a person
    | select(($labels | index("deacon-ledger")) == null)  # not a daily digest
    | select(($labels | index("debt")) == null)       # not a parked tech-debt / advisory record
    | select(($title | test("^gc doctor:")) == false) # not a doctor advisory record
    | [ ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")),
        (if $t == "" then "untyped" else $t end),
        (if $rt == "" then "unrouted" else "routed to " + $rt end)
      ] | join("\u001f")' 2>/dev/null)
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
examined=$(printf '%s' "$raw" | scrub | jq -r 'length' 2>/dev/null)
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
