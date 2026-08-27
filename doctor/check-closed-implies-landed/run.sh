#!/usr/bin/env bash
# doctor/check-closed-implies-landed — I5: closed means landed. A CLOSED ANCHOR
# still carrying merge_result=pull_request or pre_open_gate left the merge queue
# without landing — merge.sh enumerates OPEN anchors only, so nothing will land
# it (error). A closed merge_result=merged anchor with no merged_sha recorded
# landed without evidence (warning).
# Carrying merge_result is NOT the same as being an anchor: rework and review
# children are stamped with the anchor's PR identity by the same machinery, and
# merge.sh never enumerates them. Two shapes are therefore out of scope, and
# both are readable from the ledger alone:
#   - a bead whose PARENT carries merge_result and names the same work (same
#     pr_number or same branch) — the parent is the anchor, so a finding, if
#     there is one, belongs to the parent and is reported there;
#   - a bead carrying gc.superseded_by — bead-rehome.sh is the sole writer of
#     that pointer, and it IS the "explicit terminal state" this check accepts.
# Ledger-only and offline-safe BY DESIGN: no gh calls — the ledger's own
# record is the invariant, whatever GitHub would add. That is also why an
# unlanded finding never asserts what the PR did; it names the repairs and
# leaves the reading of the PR to whoever acts on it.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: first line = message, then
# "  - detail" lines. Probes bounded; an UNREADABLE store warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether closed anchors landed (I5)"
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
    # Every status, not just closed: an OPEN parent is what proves a closed
    # child is not the anchor.
    raw=$(run_bounded bd list --db "$rig_path/.beads" --all \
        --has-metadata-key merge_result --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list merge_result-carrying beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$raw" | scrub | jq -r '
        . as $all
        | (reduce ($all[]? | select(((((.metadata // {}).merge_result) // "") | tostring) != "")) as $b ({};
              . + { ((($b.id // "") | tostring)):
                    [ (((($b.metadata // {}).pr_number) // "") | tostring),
                      (((($b.metadata // {}).branch)    // "") | tostring) ] })) as $idx
        | $all[]? | select(((.status // "") | tostring) == "closed")
        | (.metadata // {}) as $m
        | ((($m.merge_result // "") | tostring)) as $mr
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
        | ((($m.pr_url // "") | tostring)) as $u
        | ((if $u != "" then $u else (($m.existing_pr // "") | tostring) end)
           | gsub("[[:cntrl:]]"; " ")) as $pr
        | (if $mr == "pull_request" or $mr == "pre_open_gate" then "unlanded"
           elif $mr == "merged" and ((($m.merged_sha // "") | tostring) == "") then "nosha"
           else empty end) as $kind
        | (if ((($m["gc.superseded_by"] // "") | tostring) != "") then "exempt-disposed"
           else ((.parent // "") | tostring) as $par
              | (if $par == "" then null else $idx[$par] end) as $anc
              | ((($m.pr_number // "") | tostring)) as $cpr
              | ((($m.branch // "") | tostring)) as $cbr
              | (if $anc != null and ((($cpr != "") and ($cpr == $anc[0]))
                                      or (($cbr != "") and ($cbr == $anc[1])))
                 then "exempt-child" else $kind end)
           end) as $verdict
        | [$verdict, $id, $mr, $pr] | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: merge_result listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    n_child=0; n_disposed=0
    while IFS=$'\037' read -r kind id mr pr; do
        [ -n "$kind" ] || continue
        case "$kind" in
            unlanded)
                if [ "$mr" = "pull_request" ]; then
                    errors+=("$label bead $id: CLOSED carrying merge_result=pull_request${pr:+ (PR $pr)} — merge.sh enumerates open anchors only, so nothing will land this. Read the PR before repairing: merged means the ledger is stale (\`lifecycle.sh transition $id --to merged --close --set merged_sha=<sha>\`), still open means the anchor has to come back (\`lifecycle.sh reopen $id\`), and dropped on purpose means it needs a successor pointer (\`bead-rehome.sh --origin $id --successor <bead> --kind <kind>\`)")
                else
                    errors+=("$label bead $id: CLOSED carrying merge_result=$mr — no PR was ever opened and merge.sh enumerates open anchors only, so nothing will land this. Reopen the anchor to resume it (\`lifecycle.sh reopen $id\`), or record the disposition that ended it (\`bead-rehome.sh --origin $id --successor <bead> --kind <kind>\`)")
                fi ;;
            nosha)    warnings+=("$label bead $id: closed as merged${pr:+ (PR $pr)} but records NO merged_sha — the landing is unevidenced; recover the sha from the PR and record it") ;;
            exempt-child)    n_child=$((n_child + 1)) ;;
            exempt-disposed) n_disposed=$((n_disposed + 1)) ;;
        esac
    done <<< "$rows"
    if [ $((n_child + n_disposed)) -gt 0 ]; then
        notes+=("$label: $((n_child + n_disposed)) closed bead(s) carry merge_result but are not anchors, so they were not judged ($n_child child of a bead holding the same work, $n_disposed disposed via gc.superseded_by)")
    fi
done <<< "$scopes"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "closed-but-unlanded anchors (I5): ${#errors[@]} bead(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "closed-implies-landed holds with gaps (I5)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every closed anchor is merged with a recorded merged_sha or an explicit terminal state"
detail ${notes[@]+"${notes[@]}"}
exit 0
