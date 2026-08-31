#!/usr/bin/env bash
# doctor/check-one-anchor-per-pr — I4: every PR has exactly one owning anchor.
# Groups OPEN ANCHORS city-wide (all stores) by their pr_url metadata: only
# merge_result-carrying beads count (anchors stamp pr_url and merge_result in
# one lifecycle.sh write; review beads and rework children carry pr_url with
# NO merge_result), and task_kind=review is excluded outright. Two or
# more open anchors naming the same PR is an error — N claimants on one PR means
# the weakest check-set decides the merge, and merge.sh's refuse-on-sight hold
# is only a runtime backstop that fires when someone tries to land it.
# Ledger-only, read-only. Exit 0=OK 1=Warning 2=Error. stdout: first line =
# message, then "  - detail" lines. Live probes are bounded; an UNREADABLE
# store warns (1), never passes — a store we cannot read could hide the twin.

set -u

dir="${GC_PACK_DIR:-.}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

errors=(); warnings=(); notes=()
US=$'\037'
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
    echo "cannot determine whether every PR has one owning anchor (I4)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

# pr_url US label/bead-id pairs accumulated across every readable store.
pairs=""
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    raw=$(run_bounded bd list --db "$rig_path/.beads" --status open \
        --has-metadata-key pr_url --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list open beads carrying pr_url in $rig_path/.beads (rc=$rc) — this store was NOT checked, and a second anchor there would be invisible")
        continue
    fi
    rows=$(printf '%s' "$raw" | scrub | jq -r '
        .[]? | (.metadata // {}) as $m
        | (($m.pr_url // "") | tostring | gsub("[[:cntrl:]]"; " ")) as $u
        | select($u != "")
        | select((($m.task_kind // "") | tostring) != "review")
        | select((($m.merge_result // "") | tostring) != "")
        | [$u, ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " "))] | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: pr_url listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    while IFS=$'\037' read -r url bid; do
        [ -n "$url" ] || continue
        pairs="$pairs$url$US$label/$bid
"
    done <<< "$rows"
done <<< "$scopes"

# City-wide grouping: the same PR anchored from two stores is the same defect.
dupes=""
if [ -n "$pairs" ]; then
    dupes=$(printf '%s' "$pairs" | awk -F'\037' '
        { n[$1]++; ids[$1] = ids[$1] ", " $2 }
        END { for (u in n) if (n[u] > 1) print u "\037" n[u] "\037" substr(ids[u], 3) }')
fi
if [ -n "$dupes" ]; then
    while IFS=$'\037' read -r url count bids; do
        [ -n "$url" ] || continue
        errors+=("PR $url has $count open anchors: $bids — one unit of work has exactly one anchor; close or re-point the duplicates so a single check_set owns the merge")
    done <<< "$dupes"
fi

if [ "${#errors[@]}" -ne 0 ]; then
    echo "PRs with more than one open anchor (I4): ${#errors[@]} PR(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "one-anchor-per-PR partially determined (I4)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: no PR is named by more than one open anchor"
detail ${notes[@]+"${notes[@]}"}
exit 0
