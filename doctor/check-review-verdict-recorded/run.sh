#!/usr/bin/env bash
# doctor/check-review-verdict-recorded — I7 (disposal): a review bead dispatched
# for a gate does not reach closed without saying what it concluded. The two
# authorized closers both record one: signoff.sh stamps gc.outcome=recorded when
# it writes a verdict, review-sweep.sh stamps gc.outcome=moot and appends the
# reason it had none to give. A review that closes through neither leaves the
# gate exactly as it found it while spending a dispatch against gate-ensure.sh's
# GC_MAX_REVIEW_DISPATCHES ceiling, so the backstop fires on a round that never
# reported anything and the anchor parks in front of an operator with no record
# of what the review saw.
#
# Per store, every CLOSED task_kind=review bead whose anchor_bead names an OPEN
# bead must carry close-time evidence. Any one of these clears it:
#   gc.outcome        the disposal stamp both authorized closers write
#   notes             a verdict body, or a declination naming why there is none
#   verdict           the pre-rewrite verdict stamp
#   review_state      the pre-rewrite GitHub review state
#   review_note       the pre-rewrite disposal note
#   duplicate_of      closed as a duplicate of another review
#   gc.work_outcome   the reviewing session's own outcome stamp
# The last five have no writer in the current pack; they are accepted because
# beads carrying them recorded a disposal under the code of their day, and a
# check that reported them would be reporting its own anachronism.
#
# ONLY close-time evidence counts. reviewed_oid, check_name, review_branch,
# review_base, review_pool and fix_target_pool are stamped by the DISPATCHER
# before any reviewer reads the diff, so a review carrying them has been asked a
# question, not answered one.
#
# Scope is anchor-open because that is where the silence still costs something:
# the gate is owed, the dispatch ceiling is counting, and the missing record is
# the one an operator needs. Under a closed anchor the same residue is history.
# A review naming no anchor_bead is left alone — the scope condition cannot be
# tested, and an untested condition is not a satisfied one.
#
# Whether the verdict a review DID record stands behind a green marker is
# check-gate-marker-provenance's half of I7 and is not restated here.
#
# Read-only, ledger-only, no network. Exit 0=OK 1=Warning 2=Error. stdout:
# message, then "  - detail" lines. An UNREADABLE store warns (1), never passes.

set -u

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
    echo "cannot determine review verdict disposal (I7)"
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

    # Candidates: closed reviews carrying an anchor, stripped to those that
    # recorded nothing at close time. anchor_bead narrows the listing to beads
    # that can be in scope at all; task_kind is what makes one a review.
    raw=$(run_bounded bd list --db "$rig_path/.beads" --status closed \
        --has-metadata-key anchor_bead --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list closed review beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    silent=$(printf '%s' "$raw" | scrub | jq -c '
        def blank: (. // "") | tostring | (test("[^[:space:]]") | not);
        [ .[]? | (.metadata // {}) as $m
        | select(((($m.task_kind // "") | tostring)) == "review")
        | ((($m.anchor_bead // "") | tostring)) as $a
        | select($a != "")
        | select(($m["gc.outcome"] | blank) and (.notes | blank)
                 and ($m.verdict | blank) and ($m.review_state | blank)
                 and ($m.review_note | blank) and ($m.duplicate_of | blank)
                 and ($m["gc.work_outcome"] | blank))
        | {id: ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")),
           anchor: $a,
           gate: ((($m.check_name // "") | tostring) | if . == "" then "codex" else . end),
           closed: ((.closed_at // "") | tostring | .[0:10])} ]' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ] || [ -z "$silent" ]; then
        warnings+=("$label: closed-review listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ "$(printf '%s' "$silent" | jq -r 'length' 2>/dev/null)" != "0" ] || continue

    # The scope filter. Read the open beads ONCE and test anchors against that
    # set: an anchor absent from a listing that WAS read is closed or gone, and
    # either way its review's silence is history, not a live hold.
    open_raw=$(run_bounded bd list --db "$rig_path/.beads" --status open \
        --json --limit 0 2>/dev/null); orc=$?
    if [ "$orc" -ne 0 ] || [ -z "$open_raw" ]; then
        warnings+=("$label: could not read the open-bead set in $rig_path/.beads (rc=$orc) — $(printf '%s' "$silent" | jq -r 'length') closed review(s) recorded nothing, but whether their anchors are still open is unknown, so this store was NOT checked")
        continue
    fi
    open_set=$(printf '%s' "$open_raw" | scrub | jq -c '[ .[]? | {key: ((.id // "") | tostring), value: 1} ] | from_entries' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ] || [ -z "$open_set" ]; then
        warnings+=("$label: open-bead set from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    residue=$(jq -nr --argjson s "$silent" --argjson o "$open_set" '$s[]
        | select(($o[.anchor] // 0) == 1)
        | [.id, .anchor, .gate, .closed] | join("\u001f")' 2>/dev/null); jrc=$?
    if [ "$jrc" -ne 0 ]; then
        warnings+=("$label: could not join silent reviews to open anchors in $rig_path/.beads — this store was NOT checked")
        continue
    fi
    expected=$(printf '%s\n' "$residue" | grep -c '[^[:space:]]')
    [ "$expected" -ne 0 ] || continue

    processed=0
    while IFS=$'\037' read -r id anchor gate closed; do
        [ -n "$id" ] || continue
        processed=$((processed + 1))
        errors+=("$label bead $id: closed${closed:+ on $closed} with no verdict and no recorded declination, and its anchor $anchor is still open — gate $gate stands exactly where the dispatch found it, the round is spent against the dispatch ceiling, and nothing says what the review concluded. Both authorized closers record one: signoff.sh stamps gc.outcome=recorded, review-sweep.sh stamps gc.outcome=moot with the reason.")
    done <<< "$residue"
    if [ "$processed" -ne "$expected" ]; then
        warnings+=("$label: enumerated $processed of $expected silent review(s) in $rig_path/.beads — the rest were NOT checked")
    fi
done <<< "$scopes"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "review verdicts disposed without a record (I7): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "review verdict disposal holds with gaps (I7)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every closed review bead under an open anchor recorded a verdict or a declination"
detail ${notes[@]+"${notes[@]}"}
exit 0
