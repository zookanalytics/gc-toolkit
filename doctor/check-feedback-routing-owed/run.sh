#!/usr/bin/env bash
# doctor/check-feedback-routing-owed — operator PR feedback the posture arm
# recorded but nothing has routed.
#
# The merge cadence records a PR's review posture on the anchor bead in a cheap
# pre-merge arm (pr-facts.sh --posture-only) and routes the feedback under it in
# a second arm (pr-facts.sh, and now --route-comments-only). The two are
# separate metadata: `pr_posture` says a human is waiting (`commented` or
# `changes_requested`), and `pr_comment_disposition` says what answered them (a
# rework child or a visit). When the posture is stamped but the disposition is
# never written, the anchor reads as handled while the operator's review sits
# unrouted, and nothing else surfaces the gap — the operator only learns of it
# by noticing their comment went unanswered.
#
# This flags an OPEN anchor whose `pr_posture` is `commented`/`changes_requested`
# with NO `pr_comment_disposition`, once the posture has stood past the owed
# window. The window is measured from the posture's own `@<since>` component,
# the instant the posture arm first recorded this value at this head.
#
# Two shapes are NOT the gap and are exempted:
#   * a `pr_unengaged_threads` marker at the posture's head — the unengaged
#     review-thread arm files a visit and stamps that head instead of a
#     disposition, so the hold is tracked, just not through a disposition.
#   * a posture still carrying no `@<since>` instant (the pre-dated 2-component
#     shape) — its age cannot be bounded, so it waits for the next sweep, when
#     the posture arm will have re-dated it.
# A `changes_requested` from the city's own reviewer is not a false positive:
# the city posts no GitHub review (signoff.sh replays verdicts as comments), so a
# standing CHANGES_REQUESTED is always a human's and always routes.
#
# Read-only. Exit 0=OK 1=Warning. stdout: first line = message, then
# "  - detail" lines. Warn-only. An UNREADABLE probe warns (1), never passes —
# an unread store is not a clean one.

set -u

# A divergence owed longer than this has missed several merge-cadence passes. The
# refinery-reconcile order runs every 60s and its feedback arm routes on the same
# early tick the posture is stamped, so a disposition owed for half an hour is one
# the routing has not caught for many passes, not a slow single one.
# GC_FEEDBACK_ROUTING_OWED_SECONDS overrides it (whole seconds).
FEEDBACK_OWED_SECONDS="${GC_FEEDBACK_ROUTING_OWED_SECONDS:-1800}"
case "$FEEDBACK_OWED_SECONDS" in ''|*[!0-9]*) FEEDBACK_OWED_SECONDS=1800 ;; esac

K_POSTURE="pr_posture"
K_DISP="pr_comment_disposition"
K_UNENGAGED="pr_unengaged_threads"

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

now_epoch() { budget_now; }
# ISO-8601 UTC -> epoch seconds, or empty if it will not parse (GNU then BSD).
iso_to_epoch() {
    [ -n "$1" ] || { printf ''; return; }
    date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || printf ''
}

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)] | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether operator feedback is being routed"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

now=$(now_epoch)
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    # A suspended rig's store is cold; querying it would auto-start an orphan
    # Dolt server, so it is skipped the way the sibling store checks skip it.
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    # Every anchor carrying a recorded posture in this store.
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --has-metadata-key "$K_POSTURE" --all --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
        warnings+=("$label: could not list posture-bearing anchors in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$raw" | scrub | jq -r --arg posture "$K_POSTURE" --arg disp "$K_DISP" --arg un "$K_UNENGAGED" '
        .[]? | . as $b | ($b.metadata // {}) as $m
        | select((($b.status // "") | tostring) != "closed")
        | (($m[$posture] // "") | tostring) as $p
        | ($p | split("@")) as $pp
        | select((($pp[0] // "") == "commented") or (($pp[0] // "") == "changes_requested"))
        | [ ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")),
            (($pp[0] // "") | tostring),
            (($pp[1] // "") | tostring),
            (($pp[2] // "") | tostring),
            ((($m[$disp] // "") | tostring) | (. != "") | tostring),
            (($m[$un] // "") | tostring) ]
        | @tsv' 2>/dev/null) || {
        warnings+=("$label: could not evaluate posture-bearing anchors in $rig_path/.beads — this store was NOT checked")
        continue
    }
    [ -n "$rows" ] || continue

    while IFS=$'\t' read -r id posture oid since has_disp unengaged; do
        [ -n "$id" ] || continue
        [ "$has_disp" = "true" ] && continue          # routed: a disposition names what answered it
        # The unengaged review-thread arm records a visit and stamps the head in
        # pr_unengaged_threads instead of a disposition, so a marker at this same
        # head is a routed hold, not a gap.
        [ -n "$oid" ] && [ "$unengaged" = "$oid" ] && continue
        since_epoch=$(iso_to_epoch "$since")
        # A posture still in the pre-dated <value>@<oid> shape has no instant to
        # age; skip rather than cry wolf, and the next posture pass re-dates it.
        [ -n "$since_epoch" ] || continue
        age=$(( now - since_epoch ))
        if [ "$age" -ge "$FEEDBACK_OWED_SECONDS" ]; then
            findings+=("$label bead $id: pr_posture=$posture has stood for ${age}s (> ${FEEDBACK_OWED_SECONDS}s) with no pr_comment_disposition — the operator's review reads as consumed while nothing has routed it. Look at the merge cadence's pr-facts feedback arm: gc order history refinery-reconcile --since 1h --limit 0")
        fi
    done <<< "$rows"
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every store was scanned — what follows is partial, and a store skipped for time is not a store that passed")
fi
if [ "${#findings[@]}" -ne 0 ] || [ "${#warnings[@]}" -ne 0 ]; then
    if [ "${#findings[@]}" -ne 0 ]; then
        echo "operator feedback recorded but not routed: ${#findings[@]} finding(s)"
        detail "${findings[@]}"
        detail ${warnings[@]+"${warnings[@]}"}
    else
        echo "feedback-routing check ran partially"
        detail "${warnings[@]}"
    fi
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every recorded commented/changes_requested posture has a routing disposition or is within the owed window"
detail ${notes[@]+"${notes[@]}"}
exit 0
