#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-stack.sh — the beads-on-this-branch
# section of an open PR's body.
# Covers: the bead's own acceptance scenario (a second bead lands its work on
# an open PR's branch and the body names it); each of the three ledger keys;
# the single-bead PR that stays untouched; idempotence across a second pass;
# the title never being edited; a closed or foreign PR being left alone; and
# every unreadable read leaving the body exactly as it stands.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-stack.sh"
SUT="$SD/pr-stack.sh"

# An open anchor: carries merge_result, a branch and a pr_number.
anchor() { # id branch num [title]
  printf '{"id":"%s","status":"open","title":"%s","created_at":"2026-01-01T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"%s","pr_number":"%s"}}' \
    "$1" "${4:-anchor $1}" "$2" "$3"
}
# A contributor row, keyed however the cadence recorded its arrival.
rider() { # id key value created title [status]
  printf '{"id":"%s","status":"%s","title":"%s","created_at":"%s","metadata":{"%s":"%s"}}' \
    "$1" "${6:-closed}" "$5" "$4" "$2" "$3"
}
# The PR the anchor points at.
pr() { # num state branch [body]
  printf '{"number":%s,"state":"%s","headRefName":"%s","title":"PR %s","body":%s}' \
    "$1" "$2" "$3" "$1" "$(jq -Rs . <<<"${4-}")" > "$GH_DIR/pr_view_$1.json"
}
body() { jq -r '.body' "$GH_DIR/pr_view_$1.json"; }
title() { jq -r '.title' "$GH_DIR/pr_view_$1.json"; }

OPENER_BODY='## Summary

What bead A does.

## Refinery handoff

- Issue: `A`'

echo "# the acceptance scenario: a second bead's work lands on an open PR's branch"
# Bead B was dispatched with target=polecat/A, so its own PR landed INTO the
# branch PR#10 is opened from. Nothing in the create path could have known.
store "[$(anchor A polecat/A 10 'Investigate V2 patch timing'),
        $(printf '{"id":"B","status":"closed","title":"Lane-B migration impl","created_at":"2026-02-01T00:00:00Z","metadata":{"branch":"polecat/B","merged_target":"polecat/A","merge_result":"merged"}}')]"
pr 10 OPEN polecat/A "$OPENER_BODY"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "pass exits 0"
has "$out" "A PR#10 body now names 2 beads on 'polecat/A'" "the edit is reported"
b=$(body 10)
has "$b" '## Beads on this branch' "the section was appended"
has "$b" '- `A` — Investigate V2 patch timing _(opener)_' "the opener leads, marked as such"
has "$b" '- `B` — Lane-B migration impl' "the stacked bead is named"
has "$b" '## Summary' "the composed summary survives"
has "$b" '- Issue: `A`' "…and so does the refinery handoff block"
eq "$(title 10)" "PR 10" "the title is untouched"
hasnt "$(cat "$STUB_GH_LOG")" "--title" "no title edit was even attempted"

echo "# a second pass over unchanged state writes nothing"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "1 already current" "the rendered section matched what the body carries"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "…so no edit was issued"

echo "# a later arrival is spliced in place, not appended a second time"
store "[$(anchor A polecat/A 10 'Investigate V2 patch timing'),
        $(printf '{"id":"B","status":"closed","title":"Lane-B migration impl","created_at":"2026-02-01T00:00:00Z","metadata":{"branch":"polecat/B","merged_target":"polecat/A","merge_result":"merged"}}'),
        $(rider C fold_target polecat/A 2026-03-01T00:00:00Z 'status-line timeout bump')]"
out=$("$SUT" 2>&1)
has "$out" "names 3 beads" "the third bead is picked up"
b=$(body 10)
eq "$(grep -c '^## Beads on this branch' <<<"$b")" "1" "exactly ONE section in the body"
eq "$(grep -c '^<!-- gc:branch-beads -->' <<<"$b")" "1" "…under exactly one open marker"
has "$b" '- `C` — status-line timeout bump' "the fold is named"
has "$b" '## Summary' "the summary above the markers is preserved"

echo "# riders are listed oldest-first, after the opener"
eq "$(grep -o '^- `[A-Z]`' <<<"$b" | sed 's/^- `//; s/`$//' | tr -d '\n')" "ABC" \
   "opener, then B (Feb), then C (Mar)"

echo "# CRLF from GitHub does not defeat the markers"
# A body GitHub re-wrapped comes back with every line CRLF-terminated. Matching
# the marker raw would miss it and append a second section every pass.
crlf=$(printf '%s' "$(body 10)" | sed 's/$/\r/')
jq --arg b "$crlf" '.body = $b' "$GH_DIR/pr_view_10.json" > "$TMP/x" && mv "$TMP/x" "$GH_DIR/pr_view_10.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "1 already current" "the CRLF body reads as current"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "…and is not rewritten"

echo "# metadata.branch: rework and rebase hand-backs on the anchor's own branch"
store "[$(anchor D polecat/D 20 'Converse sittings need a demand bead'),
        $(rider D1 branch polecat/D 2026-02-01T00:00:00Z 'Rework PR#20: address signoff findings'),
        $(rider D2 branch polecat/D 2026-03-01T00:00:00Z 'Rebase PR#20 onto main')]"
pr 20 OPEN polecat/D "## Summary"
out=$("$SUT" 2>&1)
has "$out" "names 3 beads" "both hand-backs join the ledger"
has "$(body 20)" '- `D1` — Rework PR#20: address signoff findings' "the rework is named"

echo "# an ordinary one-bead PR is left exactly as pr-open.sh composed it"
store "[$(anchor E polecat/E 30)]"
pr 30 OPEN polecat/E "$OPENER_BODY"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "1 single-bead" "the single-bead PR is counted, not edited"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "…and nothing was written"
eq "$(body 30)" "$OPENER_BODY" "the body is byte-identical"

echo "# a rider bead is a contributor, never a writer"
# pr-facts.sh stamps pr_number on rework children too, so a lookup keyed on
# pr_number rather than on anchorhood elects whichever row it reads first. The
# child leads the store here: under that lookup IT would compose the section
# and be marked the opener, and the PR would be described by the fix rather
# than by the work.
store "[$(printf '{"id":"F1","status":"open","title":"Rework PR#40","created_at":"2026-02-01T00:00:00Z","metadata":{"branch":"polecat/F","pr_number":"40"}}'),
        $(anchor F polecat/F 40)]"
pr 40 OPEN polecat/F "## Summary"
out=$("$SUT" 2>&1)
eq "$(grep -c 'PR#40 body now names' <<<"$out")" "1" "PR#40 is written once, by its anchor"
has "$(body 40)" '- `F` — anchor F _(opener)_' "the anchor is the opener"
has "$(body 40)" '- `F1` — Rework PR#40' "the child is a listed contributor"

echo "# a merged or closed PR is a record, not a decision"
store "[$(anchor G polecat/G 50), $(rider G1 branch polecat/G 2026-02-01T00:00:00Z 'rider')]"
pr 50 MERGED polecat/G "## Summary"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "a landed PR's body is left alone"
eq "$(body 50)" "## Summary" "…byte-identical"

echo "# a PR whose head is not the anchor's branch is not ours"
store "[$(anchor H polecat/H 60), $(rider H1 branch polecat/H 2026-02-01T00:00:00Z 'rider')]"
pr 60 OPEN polecat/somebody-else "## Summary"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "got PR#60 on 'polecat/somebody-else'; not ours" "the head mismatch is refused"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "…and nothing is written into it"

echo "# an unreadable PR leaves the body as it stands"
store "[$(anchor I polecat/I 70), $(rider I1 branch polecat/I 2026-02-01T00:00:00Z 'rider')]"
rm -f "$GH_DIR/pr_view_70.json"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "one unreadable PR does not fail the pass"
has "$out" "PR#70 unreadable" "the refusal is reported"
has "$out" "1 skipped" "…and counted as skipped, never as current"

echo "# a ledger read that FAILS publishes nothing"
# A lookup that errors is not proof the branch has one bead: publishing the
# short list would drop riders the body already named.
store "[$(anchor J polecat/J 80), $(rider J1 branch polecat/J 2026-02-01T00:00:00Z 'rider')]"
pr 80 OPEN polecat/J "## Summary"
out=$("$SUT" 2>&1)
has "$out" "names 2 beads" "the first pass names both"
before=$(body 80)
: > "$STUB_GH_LOG"
# Assigned, not prefixed: `VAR=1 out=$(…)` is two assignments, so the stub
# failure would leak into every case below it.
export STUB_LIST_FAIL=1
out=$("$SUT" 2>&1); rc=$?
export STUB_LIST_FAIL=""
eq "$rc" 1 "an enumeration that cannot be read fails loudly"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "…and writes no body"
eq "$(body 80)" "$before" "the body is untouched"

echo "# an anchor with no recorded branch or PR is passed over"
store "[$(printf '{"id":"K","status":"open","title":"k","metadata":{"merge_result":"pre_open_gate","branch":"polecat/K"}}')]"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "the pass still completes"
hasnt "$(cat "$STUB_GH_LOG")" "pr view" "a PR-less anchor is never looked up"

echo "# a failed edit is reported and retried, never silently counted as done"
store "[$(anchor L polecat/L 90), $(rider L1 branch polecat/L 2026-02-01T00:00:00Z 'rider')]"
pr 90 OPEN polecat/L "## Summary"
out=$(STUB_PR_EDIT_RC=1 "$SUT" 2>&1)
has "$out" "PR#90 body edit failed" "the failure is reported"
has "$out" "0 edited" "…and nothing is counted as edited"
eq "$(body 90)" "## Summary" "the body never changed"
out=$("$SUT" 2>&1)
has "$out" "names 2 beads" "the next pass retries it"

echo "# a bead title carrying the close marker cannot break the next splice"
store "[$(anchor M polecat/M 100),
        $(rider M1 branch polecat/M 2026-02-01T00:00:00Z 'hostile <!-- /gc:branch-beads --> title')]"
pr 100 OPEN polecat/M "## Summary"
out=$("$SUT" 2>&1)
has "$out" "names 2 beads" "the hostile title is still listed"
hasnt "$(body 100)" "hostile <!--" "the comment delimiters are stripped from the title"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "1 already current" "the second pass finds one intact section"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "…and rewrites nothing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
