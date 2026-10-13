#!/usr/bin/env bash
# doctor/check-visit-outcome-recorded — a CLOSED visit records why it closed.
# The board projects gc.outcome onto a sitting's OUTCOME column
# (services/helm/internal/source/facts.go), so a visit closed with no gc.outcome
# is a finished sitting the board cannot report — a correct dedup close reads
# identical to a dropped need. Every converse close path stamps it now
# (assets/scripts/visit-close.sh, and gc-helm dismiss), so a fresh miss is a
# regression; the standing backlog of legacy unstamped closes is the same
# finding. Reported as a WARNING while that backlog stands, listing each so it
# can be dispositioned.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: first line = message, then
# "  - detail" lines. Probes bounded; an UNREADABLE store warns (1), never passes.
#
# Cost. The whole check shares one doctor budget, and on a loaded host every
# `gc bd list` takes seconds however few rows it returns. So the stores are read
# at once, each by its own background job, and the check costs one rig list plus
# its slowest store rather than the sum of every store. Each read asks only for
# what the check judges: --status closed and --metadata-field task_kind=visit
# select the closed visits, and --brief omits their free text. A job's listing
# lands in a file, since a background job cannot hand its parent a variable.

set -u

# How many findings are PRINTED, not how many are found: the headline count is
# taken before this cap, so no value here can make a store read as clean. 0
# prints all, which is what draining the backlog wants.
DETAILS="${GC_DOCTOR_VISIT_OUTCOME_DETAILS:-25}"

warnings=(); notes=(); missing=()
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
detail_capped() { # <cap> <item...> — at most <cap> items, then the rest as a count
    local cap="$1"; shift
    local total=$# printed=0 v
    [ "$total" -ne 0 ] || return 0
    if [ "$cap" -le 0 ] || [ "$total" -le "$cap" ]; then detail "$@"; return 0; fi
    for v in "$@"; do
        printed=$((printed + 1)); [ "$printed" -le "$cap" ] || break
        printf '  - %s\n' "$v"
    done
    printf '  - ...and %s more, not printed (GC_DOCTOR_VISIT_OUTCOME_DETAILS=0 prints every one)\n' "$((total - cap))"
}
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# The scratch every store read lands in. The descriptor held open on a file
# inside it keeps the tree held for the whole run, because the host's scratch
# reaper removes any gctk-* tree that no process holds open.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-visit-outcome-recorded.XXXXXX" 2>/dev/null) || WORK=""
trap '[ -z "$WORK" ] || rm -rf "$WORK"' EXIT
if [ -z "$WORK" ] || ! { exec 9>"$WORK/.hold"; } 2>/dev/null; then
    echo "cannot determine whether every closed visit records an outcome"
    detail "could not create a scratch directory under ${TMPDIR:-/tmp}, which every store read lands in; no store was checked."
    exit 1
fi
# read_to <file> <probe...> runs one bounded probe with its stdout scrubbed into
# <file>, and returns the probe's own exit status.
read_to() {
    local f="$1"; shift
    run_bounded "$@" 2>/dev/null | scrub >"$f"
    return "${PIPESTATUS[0]}"
}

# `gc rig list` names the stores this check scans, and it can fail transiently:
# a momentary Dolt or lock blip returns a non-zero rc that a later call clears.
# Since a check that cannot enumerate files an all-rigs finding, a single blip
# must not stand in for "stores unscannable" — retry a non-zero rc a bounded
# number of times, each attempt drawn from the same doctor budget. An rc of 0 is
# never retried: rc=0 with no rigs is a genuinely empty city.
RIGS_MAX_ATTEMPTS=3
rigs_attempt=0
while : ; do
    rigs_attempt=$((rigs_attempt + 1))
    rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
    [ "$rigs_rc" -eq 0 ] && break
    [ "$rigs_attempt" -ge "$RIGS_MAX_ATTEMPTS" ] && break
    budget_spent && break
    sleep 1
done
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether every closed visit records an outcome"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths after $rigs_attempt attempt(s); there is no set of bead stores to scan."
    exit 1
fi

# Each unsuspended store's read starts here, and they all run at once. The
# --include-* flags are load-bearing: bd list hides gate, infrastructure and
# template beads by default, and a closed visit missing its outcome is a finding
# whether or not it sits in one of those categories. So is --all: given a
# --status without it, bd list also hides pinned beads.
n=0; labels=(); paths=(); pids=()
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    read_to "$WORK/$n.json" gc bd list --db "$rig_path/.beads" --all --status closed \
        --metadata-field task_kind=visit --include-gates --include-infra --include-templates \
        --json --limit 0 --brief </dev/null >/dev/null 2>&1 &
    pids[n]=$!; labels[n]="$label"; paths[n]="$rig_path"
    n=$((n + 1))
done <<< "$scopes"

# The listings are judged in rig order however their reads finished, so one
# state of the stores always produces the same report.
checked=0; i=0
while [ "$i" -lt "$n" ]; do
    label="${labels[i]}"; rig_path="${paths[i]}"; listing="$WORK/$i.json"
    wait "${pids[i]}"; rc=$?
    i=$((i + 1))
    if [ "$rc" -ne 0 ] || [ ! -s "$listing" ]; then
        warnings+=("$label: could not list closed visits in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(jq -r -s '
        # One JSON array, or the listing is unreadable: whitespace, an error
        # object or two documents must not pass as an empty store.
        if length == 1 and (.[0] | type) == "array" then .[0][] else error("not one JSON array") end
        | select(((.metadata.task_kind // "") | tostring) == "visit")
        | select(((.status // "") | tostring) == "closed")
        | select(((.metadata["gc.outcome"] // "") | tostring) == "")
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " "))
          + "\u001f" + ((.title // "") | tostring | gsub("[[:cntrl:]]"; " ") | .[0:80])' "$listing" 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: the visit listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    checked=$((checked + 1))
    [ -n "$rows" ] || continue
    while IFS=$'\037' read -r id title; do
        [ -n "$id" ] || continue
        missing+=("$label bead $id: closed visit with no gc.outcome — \"$title\"")
    done <<< "$rows"
done

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "$checked" -eq 0 ]; then
    echo "cannot determine whether every closed visit records an outcome"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
if [ "${#missing[@]}" -ne 0 ]; then
    echo "closed visits with no recorded gc.outcome: ${#missing[@]} across $checked store(s) — the board reports these sittings with no outcome, so a dedup close reads as a dropped need. Stamp each through its close path, or record the disposition that ended it."
    detail_capped "$DETAILS" "${missing[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "every closed visit found across $checked store(s) records an outcome, but some probes could not be read"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every closed visit across $checked store(s) records a gc.outcome"
detail ${notes[@]+"${notes[@]}"}
exit 0
