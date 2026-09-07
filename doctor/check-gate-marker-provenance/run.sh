#!/usr/bin/env bash
# doctor/check-gate-marker-provenance — I7 (depth): a lane a merge path trusts as
# green stands on a verdict its writers actually produced. Two consumers read a
# lane's green two ways, so this check has two arms that never double-report.
#
# ARM B (outcome graph — the derivation merge.sh and pr-open.sh read). lane-state.sh
# stands a lane green on a CLOSED task_kind=review bead whose signoff_verdict is
# approve, whose reviewed_oid is non-empty, and whose gc.outcome is not
# superseded (or a legacy bead: no signoff_verdict, gc.outcome=recorded). It
# trusts those stamps; nothing else sweeps the store to prove them coherent. So
# per store, for every OPEN gating anchor (merge_result = pre_open_gate|pull_request),
# every closed approve review bead naming it (anchor_bead) that carries a
# reviewed_oid must record gc.outcome=recorded (a live backing) or superseded
# (retired). An approve carrying any other outcome — none at all, or a value no
# writer produces — STILL derives the lane green (lane-state.sh excludes only
# superseded) while standing on a verdict no writer recorded: that is the finding.
# signoff.sh (close_review) and review-outcome.sh (back-lane) co-stamp recorded
# with the approve; a supersede rewrites it to superseded; no writer pairs approve
# with a third value. The reviewed_oid clause matches lane-state.sh — a backing
# with no reviewed_oid derives no green there, so it is not a candidate here; the
# oid is required present, never compared to a head. A legacy no-verdict recorded
# bead carries no signoff_verdict, so this arm never fetches it.
#
# ARM A (marker — transition). gate-ensure.sh still reads check.<lane> off the
# anchor and treats green as settled, skipping a fresh dispatch. So a green marker
# with no backing wedges the anchor: gate-ensure raises no review while
# lane-state.sh holds the merge, and Arm B — which starts from outcome beads —
# never sees a green marker that has no bead behind it at all. Until the last
# marker consumer reads lane-state.sh instead (check-gate-integrity's
# marker-writer retirement, a sibling bead), this arm keeps the missing-backing
# audit: every check.<lane>=green on an open gating anchor must resolve to a
# backing — resolver A (local, no network) a CLOSED approve, or legacy recorded,
# review bead naming this anchor and lane, carrying a reviewed_oid; resolver B
# (network, residue only) an APPROVED GitHub review on the anchor's pr_number, the
# operator-approval path that files no bead. Neither found: error. A found nothing
# and B could not run (no pr_number, no gh, unresolvable origin, failed query):
# undetermined warning. Arm A asks only that SOME backing exists — whether that
# backing's outcome is coherent is Arm B's half — so a green marker over a
# malformed backing is Arm B's finding, not a second one here. When gate-ensure.sh
# no longer reads the marker, Arm A is removed and the markerless Arm B is the
# whole check.
#
# A bead whose own task_kind is review is not an anchor and is skipped. Marker
# GRAMMAR and the check_set declaration are check-gate-integrity's surface half of
# I7 and are not restated here; a marker outside the lane vocabulary is that
# check's finding, so only green lanes are Arm A candidates.
#
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE store warns (1), never passes.

set -u


errors=(); warnings=(); notes=()
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
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

declare -A REVIEWS_CACHE=()

# ARM A — the transition missing-backing marker audit. Appends to the shared
# errors/warnings arrays; a soft failure returns without killing Arm B.
arm_a_marker() {
    local label="$1" rig_path="$2" raw="$3"
    local cands jrc idx_raw irc idx residue expected slug u processed id gate pr gname key body grc approvals
    cands=$(printf '%s' "$raw" | scrub | jq -c '[
        .[]? | (.metadata // {}) as $m
        | ((($m.merge_result // "") | tostring)) as $mr
        | select($mr == "pre_open_gate" or $mr == "pull_request")
        | select(((($m.task_kind // "") | tostring)) != "review")
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
        | ((($m.pr_number // "") | tostring | gsub("[^0-9]"; ""))) as $pr
        | $m | to_entries[]
        | select(.key | test("^check\\.[^.]+$"))
        | select((.value | type) == "string")
        | select(.value == "green")
        | {id: $id, gate: .key, pr: $pr} ]' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ] || [ -z "$cands" ]; then
        warnings+=("$label: anchor listing from $rig_path/.beads could not be parsed for the marker arm — this store was NOT checked")
        return
    fi
    [ "$(printf '%s' "$cands" | jq -r 'length' 2>/dev/null)" != "0" ] || return

    # RESOLVE A. Read ALL statuses: an open bead (dispatched, no verdict yet)
    # and a closed request-changes bead must be SEEN so they can be excluded,
    # not merely absent because a status filter never fetched them.
    idx_raw=$(run_bounded gc bd list --db "$rig_path/.beads" --all \
        --has-metadata-key reviewed_oid --json --limit 0 2>/dev/null); irc=$?
    if [ "$irc" -ne 0 ] || [ -z "$idx_raw" ]; then
        warnings+=("$label: could not read the review-bead index in $rig_path/.beads (rc=$irc) — this store was NOT checked")
        return
    fi
    idx=$(printf '%s' "$idx_raw" | scrub | jq -c '[
        .[]? | (.metadata // {}) as $m
        | select(((($m.task_kind // "") | tostring)) == "review")
        | ((($m.anchor_bead // "") | tostring)) as $a
        | ((($m.reviewed_oid // "") | tostring)) as $o
        | (((($m.check_name // "") | tostring)) | if . == "" then "codex" else . end) as $g
        | (((.status // "") | tostring | ascii_downcase)) as $st
        | (($m.signoff_verdict // "") | tostring) as $sv
        | ((($m["gc.outcome"] // "") | tostring)) as $oc
        # A verdict backs a lane only once it is judged AND closed: an open
        # bead never counts. A closed bead counts when signoff_verdict reads
        # approve, or, for a legacy bead written before that stamp existed,
        # when it carries no signoff_verdict at all and gc.outcome=recorded
        # is the only sign left that it closed on a verdict.
        | select($a != "" and $o != "" and $st == "closed")
        | select($sv == "approve" or ($sv == "" and $oc == "recorded"))
        | {key: ($a + "" + $g), value: ((.id // "?") | tostring)} ] | from_entries' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ] || [ -z "$idx" ]; then
        warnings+=("$label: review-bead index from $rig_path/.beads could not be parsed — this store was NOT checked")
        return
    fi
    residue=$(jq -nr --argjson c "$cands" --argjson m "$idx" '$c[]
        | select(($m[(.id + "" + (.gate | ltrimstr("check.")))] // "") == "")
        | [.id, .gate, .pr] | join("")' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ]; then
        warnings+=("$label: could not join anchors to review beads in $rig_path/.beads — this store was NOT checked")
        return
    fi
    expected=$(printf '%s\n' "$residue" | grep -c '[^[:space:]]')
    [ "$expected" -ne 0 ] || return

    # RESOLVE B, consulted only for what A left over.
    slug=""
    u=$(run_bounded git -C "$rig_path" remote get-url origin 2>/dev/null | tr -d '[:space:]')
    case "$u" in
      git@github.com:*|https://github.com/*|ssh://git@github.com/*)
        slug=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
          -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    esac
    case "$slug" in */*/*|/*|*/) slug="" ;; */*) : ;; *) slug="" ;; esac

    processed=0
    while IFS=$'\037' read -r id gate pr; do
        [ -n "$id" ] || continue
        processed=$((processed + 1))
        gname="${gate#check.}"
        if [ -z "$pr" ]; then
            warnings+=("$label bead $id: $gate=\"green\" is backed by no closed, approve-verdict review bead naming gate $gname, and the anchor records no pr_number — no GitHub approval could be looked for, so this lane is UNDETERMINED, not cleared")
            continue
        fi
        if [ -z "$slug" ] || ! command -v gh >/dev/null 2>&1; then
            warnings+=("$label bead $id: $gate=\"green\" is backed by no closed, approve-verdict review bead naming gate $gname, and PR $pr could not be consulted (gh unavailable, or origin is not a github.com remote) — UNDETERMINED, not cleared")
            continue
        fi
        key="$slug#$pr"
        if [ -z "${REVIEWS_CACHE[$key]+set}" ]; then
            body=$(run_bounded gh api "repos/$slug/pulls/$pr/reviews?per_page=100" --paginate 2>/dev/null); grc=$?
            if [ "$grc" -ne 0 ] || [ -z "$body" ]; then
                REVIEWS_CACHE[$key]=""
            else
                # --paginate emits one array PER PAGE, so slurp before flattening:
                # without -s a second page becomes a second jq output and the
                # membership test below only ever sees the first.
                REVIEWS_CACHE[$key]=$(printf '%s' "$body" | scrub | jq -sc '[
                    .[][]? | select(((.state // "") | tostring) == "APPROVED")
                    | ((.id // "") | tostring) ]' 2>/dev/null)
            fi
        fi
        approvals="${REVIEWS_CACHE[$key]}"
        if [ -z "$approvals" ]; then
            warnings+=("$label bead $id: $gate=\"green\" is backed by no closed, approve-verdict review bead naming gate $gname, and the review list for PR $pr could not be read — UNDETERMINED, not cleared")
            continue
        fi
        [ "$(printf '%s' "$approvals" | jq -r 'length > 0' 2>/dev/null)" = "true" ] && continue
        errors+=("$label bead $id: $gate=\"green\" records a passed gate nothing reviewed — no closed review bead carries anchor_bead=$id with check_name=$gname and a recorded approve verdict, and PR $pr carries no APPROVED review; merge.sh will land this branch on the strength of that lane")
    done <<< "$residue"
    if [ "$processed" -ne "$expected" ]; then
        warnings+=("$label: enumerated $processed of $expected unresolved marker(s) in $rig_path/.beads — the rest were NOT checked")
    fi
}

# ARM B — the markerless outcome-coherence audit. Appends to the shared
# errors/warnings arrays; a soft failure returns without having killed Arm A.
arm_b_outcome() {
    local label="$1" rig_path="$2" raw="$3"
    local gating jrc vraw vrc bad id anchor lane oc
    # Live merge candidates: open gating anchors that are not themselves review
    # beads. A malformed approve backing only lands a merge while its anchor can
    # still merge, so a closed or abandoned anchor's outcome beads are out of
    # scope.
    gating=$(printf '%s' "$raw" | scrub | jq -c '[
        .[]? | (.metadata // {}) as $m
        | ((($m.merge_result // "") | tostring)) as $mr
        | select($mr == "pre_open_gate" or $mr == "pull_request")
        | select(((($m.task_kind // "") | tostring)) != "review")
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) ]' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ] || [ -z "$gating" ]; then
        warnings+=("$label: anchor listing from $rig_path/.beads could not be parsed for the outcome arm — this store was NOT checked")
        return
    fi
    [ "$(printf '%s' "$gating" | jq -r 'length' 2>/dev/null)" != "0" ] || return

    # Every closed review bead carrying a verdict. An approve backing always
    # carries signoff_verdict (both writers stamp it), so this key is the tight
    # candidate set; a legacy no-verdict backing lacks it and is well-formed, so
    # it is correctly never fetched. --status closed: only a closed bead backs a
    # lane, so an open one cannot be a malformed backing.
    vraw=$(run_bounded gc bd list --db "$rig_path/.beads" --status closed \
        --has-metadata-key signoff_verdict --json --limit 0 2>/dev/null); vrc=$?
    if [ "$vrc" -ne 0 ] || [ -z "$vraw" ]; then
        warnings+=("$label: could not read closed review outcomes in $rig_path/.beads (rc=$vrc) — this store was NOT checked")
        return
    fi
    bad=$(printf '%s' "$vraw" | scrub | jq -cr --argjson g "$gating" '
        ($g | map({(.): true}) | add // {}) as $set
        | .[]? | (.metadata // {}) as $m
        | select(((($m.task_kind // "") | tostring)) == "review")
        | select(((($m.signoff_verdict // "") | tostring)) == "approve")
        # reviewed_oid required: lane-state.sh derives no green from a local
        # backing without it, so a no-oid approve is no green risk to audit.
        | select(((($m.reviewed_oid // "") | tostring)) != "")
        | ((($m["gc.outcome"] // "") | tostring)) as $oc
        | select($oc != "recorded" and $oc != "superseded")
        | ((($m.anchor_bead // "") | tostring)) as $a
        | select(($set[$a] // false) == true)
        | [ ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")),
            ($a | gsub("[[:cntrl:]]"; " ")),
            (((($m.check_name // "") | tostring) | if . == "" then "codex" else . end) | gsub("[[:cntrl:]]"; " ")),
            ($oc | gsub("[[:cntrl:]]"; " ")) ]
        | join("")' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ]; then
        warnings+=("$label: could not join review outcomes to anchors in $rig_path/.beads — this store was NOT checked")
        return
    fi
    while IFS=$'\037' read -r id anchor lane oc; do
        [ -n "$id" ] || continue
        errors+=("$label bead $id: approve outcome for lane $lane on anchor $anchor records gc.outcome=\"${oc:-<unset>}\", not recorded or superseded — lane-state.sh excludes only superseded, so this still derives $lane green and merge.sh will land the branch on an approve whose outcome no writer recorded")
    done <<< "$bad"
}

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine gate provenance (I7)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi

    # Both arms read the same open-gating-anchor listing; an unreadable store
    # defeats both, so its failure is the one place a rig is skipped whole.
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --status open \
        --has-metadata-key merge_result --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list open anchors in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    arm_a_marker "$label" "$rig_path" "$raw"
    arm_b_outcome "$label" "$rig_path" "$raw"
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "gate provenance violated (I7): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "gate provenance holds with gaps (I7)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every green marker names a backing and every approve outcome is coherent"
detail ${notes[@]+"${notes[@]}"}
exit 0
