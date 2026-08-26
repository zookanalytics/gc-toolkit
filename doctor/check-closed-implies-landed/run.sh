#!/usr/bin/env bash
# doctor/check-closed-implies-landed — I5: closed means landed. A CLOSED bead
# still carrying merge_result=pull_request or pre_open_gate left the merge
# queue without landing — merge.sh cannot enumerate a closed anchor, so its
# PR sits approved and unmerged forever (error). A closed merge_result=merged
# bead with no merged_sha recorded landed without evidence (warning).
# Ledger-only and offline-safe BY DESIGN: no gh calls — the ledger's own
# record is the invariant, whatever GitHub would add.
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
    raw=$(run_bounded bd list --db "$rig_path/.beads" --status closed \
        --has-metadata-key merge_result --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list closed anchors in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$raw" | scrub | jq -r '
        .[]? | (.metadata // {}) as $m
        | ((($m.merge_result // "") | tostring)) as $mr
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
        | ((($m.pr_url // "") | tostring) | gsub("[[:cntrl:]]"; " ")) as $pr
        | (if $mr == "pull_request" or $mr == "pre_open_gate" then ["unlanded", $id, $mr, $pr]
           elif $mr == "merged" and ((($m.merged_sha // "") | tostring) == "") then ["nosha", $id, $mr, $pr]
           else empty end)
        | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: closed-anchor listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    while IFS=$'\037' read -r kind id mr pr; do
        [ -n "$kind" ] || continue
        case "$kind" in
            unlanded) errors+=("$label bead $id: CLOSED carrying merge_result=$mr${pr:+ (PR $pr)} — closed but not landed; merge.sh cannot enumerate a closed anchor, so this PR will never merge. Repair it with \`lifecycle.sh reopen $id\` (or record the real terminal state via a lifecycle.sh transition)") ;;
            nosha)    warnings+=("$label bead $id: closed as merged${pr:+ (PR $pr)} but records NO merged_sha — the landing is unevidenced; recover the sha from the PR and record it") ;;
        esac
    done <<< "$rows"
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
