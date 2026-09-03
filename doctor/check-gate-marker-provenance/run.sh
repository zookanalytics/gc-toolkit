#!/usr/bin/env bash
# doctor/check-gate-marker-provenance — I7 (depth): a green gate marker names a
# commit that something actually reviewed. merge-skill.sh lands a PR once every
# gate in check_set reads green at the live head, so check.<gate>=green@<oid> is
# the token the merge path trusts; this check asks what stands behind it.
#
# Per store, every OPEN gating anchor (merge_result = pre_open_gate|pull_request)
# carrying a well-formed check.<g>=green@<oid> must produce evidence of a verdict
# at that same <oid>. Two resolvers, in order:
#   A (local, no network) — a task_kind=review bead whose anchor_bead is this
#     anchor, whose reviewed_oid is <oid>, and whose check_name is <gate>. The
#     gate is part of the key because merge-skill.sh gates every check_set member
#     separately; a key without it lets one recorded verdict clear each marker
#     standing at that commit, including gates nobody ran. A review bead carrying
#     no check_name resolves gate codex, mirroring signoff.sh, which defaults an
#     absent check_name to codex and stamps check.codex for that same bead.
#   B (network, residue only) — an APPROVED GitHub review on the anchor's
#     pr_number whose OWN commit_id is <oid>. B exists because the operator
#     approves a head directly on GitHub, which files no review bead. It compares
#     the approval's commit, never "the PR is approved": per tk-4yl2c this rig's
#     human approval is not head-bound, so an approval outlives the head it was
#     given at, and only the oid comparison makes it evidence. An approval names
#     no gate, so B clears every green marker at <oid>: the operator approved the
#     head itself, not one check standing on it.
# A bead whose own task_kind is review is not an anchor and is skipped — it may
# carry a green marker of its own.
#
# Both resolvers ran and neither found a verdict at <oid> — error. A found
# nothing and B could not run (no pr_number, no gh, unresolvable origin, failed
# query) — warning, undetermined: the marker is unbacked as far as this check can
# see, but the operator-approval path was not reachable to rule out.
#
# Marker GRAMMAR and the check_set declaration are check-gate-integrity's half of
# I7 (I6+I7 surface) and are not restated here; a malformed marker is that
# check's finding, so only well-formed green markers are candidates here.
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

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine gate marker provenance (I7)"
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

    # Candidates: well-formed green markers on open gating anchors that are not
    # themselves review beads.
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --status open \
        --has-metadata-key merge_result --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list open anchors in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
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
        | select(.value | test("^green@[0-9a-f]{40}$"))
        | {id: $id, gate: .key, oid: (.value | ltrimstr("green@")), pr: $pr} ]' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ] || [ -z "$cands" ]; then
        warnings+=("$label: anchor listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ "$(printf '%s' "$cands" | jq -r 'length' 2>/dev/null)" != "0" ] || continue

    # RESOLVE A. Read ALL statuses: signoff.sh closes a review bead when it
    # records its verdict, so the evidence for a live anchor is usually closed.
    idx_raw=$(run_bounded gc bd list --db "$rig_path/.beads" --all \
        --has-metadata-key reviewed_oid --json --limit 0 2>/dev/null); irc=$?
    if [ "$irc" -ne 0 ] || [ -z "$idx_raw" ]; then
        warnings+=("$label: could not read the review-bead index in $rig_path/.beads (rc=$irc) — this store was NOT checked")
        continue
    fi
    idx=$(printf '%s' "$idx_raw" | scrub | jq -c '[
        .[]? | (.metadata // {}) as $m
        | select(((($m.task_kind // "") | tostring)) == "review")
        | ((($m.anchor_bead // "") | tostring)) as $a
        | ((($m.reviewed_oid // "") | tostring)) as $o
        | (((($m.check_name // "") | tostring)) | if . == "" then "codex" else . end) as $g
        | select($a != "" and $o != "")
        | {key: ($a + "\u001f" + $o + "\u001f" + $g), value: ((.id // "?") | tostring)} ] | from_entries' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ] || [ -z "$idx" ]; then
        warnings+=("$label: review-bead index from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    residue=$(jq -nr --argjson c "$cands" --argjson m "$idx" '$c[]
        | select(($m[(.id + "\u001f" + .oid + "\u001f" + (.gate | ltrimstr("check.")))] // "") == "")
        | [.id, .gate, .oid, .pr] | join("\u001f")' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ]; then
        warnings+=("$label: could not join anchors to review beads in $rig_path/.beads — this store was NOT checked")
        continue
    fi
    expected=$(printf '%s\n' "$residue" | grep -c '[^[:space:]]')
    [ "$expected" -ne 0 ] || continue

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
    while IFS=$'\037' read -r id gate oid pr; do
        [ -n "$id" ] || continue
        processed=$((processed + 1))
        short="${oid:0:12}"
        gname="${gate#check.}"
        if [ -z "$pr" ]; then
            warnings+=("$label bead $id: $gate=\"green@$short…\" is backed by no review bead naming gate $gname, and the anchor records no pr_number — no GitHub approval could be looked for, so this marker is UNDETERMINED, not cleared")
            continue
        fi
        if [ -z "$slug" ] || ! command -v gh >/dev/null 2>&1; then
            warnings+=("$label bead $id: $gate=\"green@$short…\" is backed by no review bead naming gate $gname, and PR $pr could not be consulted (gh unavailable, or origin is not a github.com remote) — UNDETERMINED, not cleared")
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
                    | ((.commit_id // "") | tostring) ]' 2>/dev/null)
            fi
        fi
        approvals="${REVIEWS_CACHE[$key]}"
        if [ -z "$approvals" ]; then
            warnings+=("$label bead $id: $gate=\"green@$short…\" is backed by no review bead naming gate $gname, and the review list for PR $pr could not be read — UNDETERMINED, not cleared")
            continue
        fi
        [ "$(printf '%s' "$approvals" | jq -r --arg o "$oid" 'any(.[]; . == $o)' 2>/dev/null)" = "true" ] && continue
        errors+=("$label bead $id: $gate=\"green@$short…\" records a passed gate at a commit nothing reviewed it for — no review bead carries anchor_bead=$id with reviewed_oid=$oid and check_name=$gname, and no approval on PR $pr sits at that commit; merge-skill.sh will land this head on the strength of that marker")
    done <<< "$residue"
    if [ "$processed" -ne "$expected" ]; then
        warnings+=("$label: enumerated $processed of $expected unresolved marker(s) in $rig_path/.beads — the rest were NOT checked")
    fi
done <<< "$scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "gate marker provenance violated (I7): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "gate marker provenance holds with gaps (I7)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every green gate marker on an open gating anchor names a commit a recorded verdict covers"
detail ${notes[@]+"${notes[@]}"}
exit 0
