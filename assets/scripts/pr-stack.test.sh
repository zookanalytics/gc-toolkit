#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-stack.sh — the beads-on-this-branch
# section of an open PR's body, its summary region, and its title.
# Covers: the bead's own acceptance scenario (a second bead lands its work on
# an open PR's branch and the body names it); each of the three ledger keys;
# the single-bead PR that stays untouched; idempotence across a second pass;
# a stacked bead never renaming the PR; a closed or foreign PR being left alone;
# a row that recorded no work — a closed duplicate, a no-op outcome carrying the
# anchor branch, or a rework child still routed to a pool before its fix is
# pushed — never entering the ledger; and every unreadable read leaving the
# body exactly as it stands. The title: a retitled anchor reaching its open PR
# in an edit of its own, composed as the create composes it; idempotence; a hand
# edit on the PR composed back from the anchor; whitespace never a difference;
# only a pull_request anchor's PR retitled; an unreadable PR title or an untitled
# anchor leaving the title as it stands; and a failed title edit costing the
# body refresh nothing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pr-stack-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-stack.sh" "$HERE/pr-summary-region.sh" "$HERE/review-checks.sh"
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
# The title pr-open.sh opened PR <num> with: the store's anchor recording that
# pr_number, composed by the shared cc_title and suffixed with its id. A PR with
# no anchor in the store keeps a plain placeholder.
# shellcheck source=pr-summary-region.sh
. "$SD/pr-summary-region.sh"
opened_title() { # num
  local row
  row=$(jq -c --arg n "$1" '[ .[]
      | select((((.metadata // {}).merge_result // "") | tostring) != "")
      | select((((.metadata // {}).pr_number // "") | tostring) == $n) ] | .[0] // empty' "$STUB_STORE")
  if [ -z "$row" ]; then printf 'PR %s' "$1"; return 0; fi
  printf '%s (%s)' "$(cc_title "$(jq -r '.title // ""' <<<"$row")" "$(jq -r '.issue_type // ""' <<<"$row")")" \
    "$(jq -r '.id' <<<"$row")"
}
# The PR the anchor points at. It carries the title it was opened with unless a
# scenario names another, so a pass over a PR nobody retitled has no title to write.
pr() { # num state branch [body] [head-oid] [title]
  local t="${6-}"
  [ -n "$t" ] || t=$(opened_title "$1")
  printf '{"number":%s,"state":"%s","headRefName":"%s","headRefOid":"%s","title":%s,"body":%s}' \
    "$1" "$2" "$3" "${5:-feedface00000000}" "$(jq -n --arg t "$t" '$t')" "$(jq -Rs . <<<"${4-}")" > "$GH_DIR/pr_view_$1.json"
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
has "$b" '- `B` — Lane-B migration impl _(merged in from `polecat/B`)_' \
    "the stacked bead is named, and says its work arrived by a merge"
has "$b" '## Summary' "the composed summary survives"
has "$b" '- Issue: `A`' "…and so does the refinery handoff block"
eq "$(title 10)" "chore: Investigate V2 patch timing (A)" \
   "a stacked bead never renames the PR: the title still names the anchor"
hasnt "$(cat "$STUB_GH_LOG")" "--title" "…so no title edit was even attempted"

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
# A hand-back committed onto this same branch, so it is a fix to the PR rather
# than a separate work item that merged in. Marking it would say the opposite.
has "$(body 20)" '- `D1` — Rework PR#20: address signoff findings' "the rework is named"
hasnt "$(body 20)" 'D1` — Rework PR#20: address signoff findings _(merged in' \
    "…and is NOT marked as merged in — its commits are on this branch"

echo "# an open rework child still routed to a pool is not yet on the branch"
# signoff.sh stamps branch=<this head> on the rework child at CREATION, before
# any polecat claims it. Open and still routed to a pool, its fix has not been
# pushed; listing it would tell a reviewer that approving the PR approves work
# the branch does not carry. The ledger drops it, the anchor stands alone, and
# the one-bead body pr-open.sh wrote is left byte-identical.
store "[$(anchor T polecat/T 100),
        $(printf '{"id":"T1","status":"open","title":"Rework branch polecat/T: address pre-open signoff findings","created_at":"2026-02-01T00:00:00Z","metadata":{"branch":"polecat/T","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","rejection_reason":"signoff requested changes"}}')]"
pr 100 OPEN polecat/T "$OPENER_BODY"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "1 single-bead" "the routed child drops out and the anchor stands alone"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "…so the one-bead body is never written"
eq "$(body 100)" "$OPENER_BODY" "the body is byte-identical"

echo "# the route is the discriminator: once the child's push clears it, it joins"
# The same child, its submit-and-exit route now cleared — the very signal
# merge.sh reads to tell a pushed hand-back from one a pool has yet to claim.
# Its commits are on the branch, so it enters the ledger and the body names both.
store "[$(anchor T polecat/T 100),
        $(printf '{"id":"T1","status":"open","title":"Rework branch polecat/T: address pre-open signoff findings","created_at":"2026-02-01T00:00:00Z","metadata":{"branch":"polecat/T","gc.routed_to":"","rejection_reason":"signoff requested changes"}}')]"
pr 100 OPEN polecat/T "$OPENER_BODY"
out=$("$SUT" 2>&1)
has "$out" "names 2 beads" "the hand-back joins once its route is cleared"
has "$(body 100)" '- `T1` — Rework branch polecat/T' "…and is listed as a contributor"

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

echo "# a body whose markers are not one well-formed pair is left alone"
# Under a lone marker the section read back is never the section written, so
# an arm that went ahead would rewrite the PR on every 60s tick.
for shape in "open-only:<!-- gc:branch-beads -->" \
             "close-only:<!-- /gc:branch-beads -->" \
             "inverted:<!-- /gc:branch-beads -->\n<!-- gc:branch-beads -->"; do
  name="${shape%%:*}"; markers="${shape#*:}"
  store "[$(anchor N polecat/N 110), $(rider N1 branch polecat/N 2026-02-01T00:00:00Z 'rider')]"
  pr 110 OPEN polecat/N "$(printf '## Summary\n\n%b\n' "$markers")"
  before=$(body 110)
  : > "$STUB_GH_LOG"
  out=$("$SUT" 2>&1)
  has "$out" "no well-formed marker pair" "$name: the malformed body is refused"
  hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "$name: …and nothing is written"
  eq "$(body 110)" "$before" "$name: the body is untouched"
done

echo "# a duplicated section is refused rather than half-rewritten"
sect='<!-- gc:branch-beads -->
## Beads on this branch
<!-- /gc:branch-beads -->'
store "[$(anchor P polecat/P 120), $(rider P1 branch polecat/P 2026-02-01T00:00:00Z 'rider')]"
pr 120 OPEN polecat/P "$(printf '## Summary\n\n%s\n\n%s\n' "$sect" "$sect")"
before=$(body 120)
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "no well-formed marker pair" "two pairs are refused"
eq "$(body 120)" "$before" "…and the body is untouched"

echo "# a closed no-op duplicate carrying the anchor branch is not a contributor"
# duplicate-sweep closes a rework or rebase twin as a no-op, and that row keeps
# metadata.branch naming this head. It committed nothing, so listing it would
# tell a reviewer to approve work that is not on the branch — the fidelity gap
# this arm exists to close, turned into over-reporting.
store "[$(anchor Q polecat/Q 130),
        $(printf '{"id":"Q1","status":"closed","title":"Rework PR#130: address signoff findings","created_at":"2026-02-01T00:00:00Z","metadata":{"branch":"polecat/Q","duplicate_of":"Q","gc.work_outcome":"no-op"}}')]"
pr 130 OPEN polecat/Q "$OPENER_BODY"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "the pass completes"
has "$out" "1 single-bead" "the no-op duplicate is filtered, leaving only the anchor"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "…so nothing is written"
eq "$(body 130)" "$OPENER_BODY" "the body is byte-identical to what pr-open.sh composed"

echo "# each no-op marker keeps a row out of the ledger, on its own"
# duplicate_of, work_outcome=no-op, and gc.work_outcome=no-op each drop a row
# that carries the anchor branch but committed nothing.
store "[$(anchor S polecat/S 150),
        $(printf '{"id":"S1","status":"closed","title":"dup by duplicate_of","created_at":"2026-02-01T00:00:00Z","metadata":{"branch":"polecat/S","duplicate_of":"S"}}'),
        $(printf '{"id":"S2","status":"closed","title":"no-op by work_outcome","created_at":"2026-03-01T00:00:00Z","metadata":{"branch":"polecat/S","work_outcome":"no-op"}}'),
        $(printf '{"id":"S3","status":"closed","title":"no-op by gc.work_outcome","created_at":"2026-04-01T00:00:00Z","metadata":{"branch":"polecat/S","gc.work_outcome":"no-op"}}')]"
pr 150 OPEN polecat/S "$OPENER_BODY"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "1 single-bead" "all three no-op rows are filtered, leaving only the anchor"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "…so nothing is written"

echo "# the filter discriminates: a real stacker survives beside a no-op duplicate"
store "[$(anchor R polecat/R 140),
        $(printf '{"id":"R1","status":"closed","title":"Lane-B migration impl","created_at":"2026-02-01T00:00:00Z","metadata":{"branch":"polecat/Rb","merged_target":"polecat/R","merge_result":"merged"}}'),
        $(printf '{"id":"R2","status":"closed","title":"duplicate rework no-op","created_at":"2026-03-01T00:00:00Z","metadata":{"branch":"polecat/R","duplicate_of":"R","gc.work_outcome":"no-op"}}')]"
pr 140 OPEN polecat/R "## Summary"
out=$("$SUT" 2>&1)
has "$out" "names 2 beads" "the anchor and the real stacker are named"
has "$(body 140)" '- `R1` — Lane-B migration impl' "the real stacker is listed"
hasnt "$(body 140)" 'duplicate rework no-op' "the no-op duplicate is never named"

# An anchor carrying a pr_summary and a check_set, for the gc:pr-summary region.
anchor_sum() { # id branch num check_set pr_summary [desc]
  printf '{"id":"%s","status":"open","title":"anchor %s","description":"%s","created_at":"2026-01-01T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"%s","pr_number":"%s","merged_target":"main","check_set":"%s","pr_summary":"%s"}}' \
    "$1" "$1" "${6:-}" "$2" "$3" "$4" "$5"
}
# A published gc:pr-summary region carrying <summary> and the open-mode pre-open
# sign-off line at <oldhead>, as pr-open.sh composed it at open. <gate-bullet>
# replaces that last handoff bullet.
opened_region() { # id branch checkset summary oldhead [gate-bullet]
  local gate="- Gates \`$3\` signed off pre-open at \`$5\`. For CI status, see the PR checks."
  printf '%s\n' \
    '<!-- gc:pr-summary -->' '## Summary' '' "$4" '' \
    '## Refinery handoff' '' "- Issue: \`$1\`" "- Source branch: \`$2\`" '- Target: `main`' \
    "${6:-$gate}" \
    '<!-- /gc:pr-summary -->'
}

# refresh_summary resolves the handoff bullet's gates through review-checks.sh at
# the PR head. The scenarios below use synthetic head oids that no `--at` read can
# resolve, so the resolver is pointed at a fixed index — the hermetic-test hook
# that wins over `--at` — and the bullets name the gates that index declares.
CHECKS_IDX="$TMP/review-checks.toml"
printf '[checks.correctness]\nmethod="m"\npurpose="p"\nphase="pre-open"\n[checks.triage]\nmethod="m"\npurpose="p"\nphase="pre-open"\n[checks.demo]\nmethod="m"\npurpose="p"\nphase="open-as-draft"\n' > "$CHECKS_IDX"
export GC_REVIEW_CHECKS_INDEX="$CHECKS_IDX"

echo "# a rework restamped the anchor summary; the open PR's gc:pr-summary region is refreshed"
# pr-open composes the region only at pre_open_gate and the anchor never returns
# there once the PR is open, so this arm is the only thing that republishes the
# reworked summary into the open PR — the merge surface and the squash message.
store "[$(anchor_sum W polecat/W 200 'correctness,codex' 'NEW: regrounded the PM method to peer-not-order-taker.')]"
STALE_W=$(printf '%s\n%s\n%s\n%s' \
  "$(opened_region W polecat/W 'correctness,codex' 'OLD: the three-question PM lens.' '0e0f1cbd')" \
  '' 'Operator note: keep this line.' \
  "$(printf '%s\n' '<!-- gc:branch-beads -->' '## Beads on this branch' '- `W`' '<!-- /gc:branch-beads -->')")
pr 200 OPEN polecat/W "$STALE_W" 6b321cdf00000000
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "the pass completes"
has "$out" "PR#200 summary region refreshed" "the refresh is reported"
b=$(body 200)
has "$b" 'NEW: regrounded the PM method to peer-not-order-taker.' "the reworked summary reached the published body"
hasnt "$b" 'OLD: the three-question PM lens.' "…and the stale summary is gone"
hasnt "$b" 'signed off pre-open' "the false pre-open sign-off claim at the reworked head is gone"
has "$b" '- Head `6b321cdf`; gates `correctness,codex`; see the PR checks for current status.' \
    "the handoff bullet names the current head and defers to the PR checks"
has "$b" 'Operator note: keep this line.' "operator text outside the markers is preserved"
has "$b" '## Beads on this branch' "pr-stack's own branch-beads section is preserved"
eq "$(grep -c 'pr edit 200' "$STUB_GH_LOG")" "1" "exactly one body edit"

echo "# the refresh is idempotent: a second pass over the now-current region writes nothing"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "the second pass issues no edit"
hasnt "$out" "summary region refreshed" "…and reports no refresh"

echo "# the opened-region fixture is byte-for-byte what pr-open's composer writes at open"
# The no-churn case below, and the stale-region cases around it, model a PR as
# pr-open.sh opened it, so the model is pinned to the shared composer: an
# open-mode wording this fixture does not carry fails here instead of leaving
# those cases testing a body no writer produces. The gates are resolved first and
# handed to the composer, as pr-open.sh does, against the fixed index above.
# shellcheck source=pr-summary-region.sh
composed_open=$(. "$SD/pr-summary-region.sh" && phased=$(prs_resolve_phased 'correctness' abcdef1234567890) && {
  printf '%s\n' "$PRS_MARK_OPEN"
  compose_managed 'CURRENT: the summary.' '' X polecat/X main 'correctness' abcdef1234567890 '' '' open "$phased"
  printf '%s\n' "$PRS_MARK_CLOSE"
})
eq "$(opened_region X polecat/X 'correctness' 'CURRENT: the summary.' 'abcdef12')" "$composed_open" \
   "the fixture matches compose_managed's open mode"
hasnt "$composed_open" 'opened green' "…and the open-mode bullet states no CI result"
has "$composed_open" '- Gates `correctness` signed off pre-open at `abcdef12`. For CI status, see the PR checks.' \
    "…naming the gates' sign-off and pointing to the PR checks for CI"

echo "# a PR whose region already carries the anchor summary is not churned"
# The region matches the anchor pr_summary and names the current head, so a PR as
# pr-open opened it keeps its 'signed off pre-open' line rather than being
# rewritten to the refresh wording.
store "[$(anchor_sum X polecat/X 210 'correctness' 'CURRENT: the summary the region already carries.')]"
CURR_X=$(opened_region X polecat/X 'correctness' 'CURRENT: the summary the region already carries.' 'abcdef12')
pr 210 OPEN polecat/X "$CURR_X" abcdef12000000
before_x=$(body 210)
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "the current region is left alone"
has "$(body 210)" 'signed off pre-open' "…and its open-mode handoff line is not churned"
eq "$(body 210)" "$before_x" "the body is byte-identical"

echo "# a handoff bullet that says the PR opened green is refreshed at a current summary and head"
# 'PR opened green' reads as a CI result, which a static body cannot know. The
# summary matches and the region names the current head, so only the bullet's
# claim makes this region behind, and the refresh drops it.
store "[$(anchor_sum G polecat/G 270 'correctness,codex' 'CURRENT: the summary a green-claim region already carries.')]"
GREEN_G=$(printf '%s\n\n%s' \
  "$(opened_region G polecat/G 'correctness,codex' 'CURRENT: the summary a green-claim region already carries.' '5555aaaa' \
     '- Gates `correctness,codex` signed off pre-open at `5555aaaa`; PR opened green.')" \
  'Operator note: keep this line.')
pr 270 OPEN polecat/G "$GREEN_G" 5555aaaa00000000
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "PR#270 summary region refreshed" "the green-claim region is refreshed"
b=$(body 270)
hasnt "$b" 'opened green' "the CI claim is gone from the body"
has "$b" '- Head `5555aaaa`; gates `correctness,codex`; see the PR checks for current status.' \
    "the handoff bullet names the head and defers to the PR checks"
has "$b" 'CURRENT: the summary a green-claim region already carries.' "the current summary is kept"
has "$b" 'Operator note: keep this line.' "operator text outside the markers is preserved"
eq "$(grep -c 'pr edit 270' "$STUB_GH_LOG")" "1" "exactly one body edit"

echo "# that green-claim refresh is idempotent: a second pass writes nothing"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "the second pass issues no edit"
hasnt "$out" "summary region refreshed" "…and reports no refresh"

echo "# the green-claim words quoted outside the handoff block never make a region stale"
# A summary can quote the claim on a line of its own, and so can operator text
# below the markers. Only the composed handoff bullet is the claim; reading a quote
# as one would rewrite the region on every pass.
GREEN_QUOTE='- Gates `correctness` signed off pre-open at `6666bbbb`; PR opened green.'
store "[$(anchor_sum Q polecat/Q 280 'correctness' 'CURRENT: drops the line that read\n\n- Gates `correctness` signed off pre-open at `6666bbbb`; PR opened green.')]"
CURR_Q=$(printf '%s\n\n%s\n%s' \
  "$(opened_region Q polecat/Q 'correctness' "$(printf '%s\n\n%s' 'CURRENT: drops the line that read' "$GREEN_QUOTE")" '6666bbbb')" \
  'Operator note quoting the old bullet:' "$GREEN_QUOTE")
pr 280 OPEN polecat/Q "$CURR_Q" 6666bbbb00000000
before_q=$(body 280)
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "a quoted claim is not read as the region's own"
eq "$(body 280)" "$before_q" "the body is byte-identical"

echo "# the green-claim check reads only the bullets under the region's last handoff heading"
# Each body quotes the claim where a reader might mistake it for the region's own:
# in a region with no handoff block, under a handoff heading a summary wrote
# above the composed one, and below the markers, bare or under a handoff heading
# of its own. The last body carries it as the region's own bullet, the positive
# control that also proves the library sourced.
# shellcheck source=pr-summary-region.sh
claim_of() { ( . "$SD/pr-summary-region.sh" && prs_region_says_opened_green "$1" ) && echo claim || echo none; }
PB="$TMP/claim-body"
OG='- Gates `correctness` signed off pre-open at `7777cccc`; PR opened green.'
printf '%s\n' '<!-- gc:pr-summary -->' '## Summary' '' 'S.' '' "$OG" '<!-- /gc:pr-summary -->' > "$PB"
eq "$(claim_of "$PB")" none "a region with no handoff block carries no claim, whatever its summary quotes"
printf '%s\n' '<!-- gc:pr-summary -->' '## Summary' '' 'S.' '' '## Refinery handoff' '' "$OG" '' \
  '## Refinery handoff' '' '- Issue: `P`' '<!-- /gc:pr-summary -->' > "$PB"
eq "$(claim_of "$PB")" none "only the block under the last handoff heading is the composed one"
printf '%s\n' '<!-- gc:pr-summary -->' '## Summary' '' 'S.' '' '## Refinery handoff' '' '- Issue: `P`' \
  '<!-- /gc:pr-summary -->' '' "$OG" > "$PB"
eq "$(claim_of "$PB")" none "a claim below the markers is not the region's"
printf '%s\n' '<!-- gc:pr-summary -->' '## Summary' '' 'S.' '' '## Refinery handoff' '' '- Issue: `P`' \
  '<!-- /gc:pr-summary -->' '' '## Refinery handoff' '' "$OG" > "$PB"
eq "$(claim_of "$PB")" none "…nor is one under a handoff heading of its own below them"
printf '%s\n' '<!-- gc:pr-summary -->' '## Summary' '' 'S.' '' '## Refinery handoff' '' '- Issue: `P`' "$OG" \
  '<!-- /gc:pr-summary -->' > "$PB"
eq "$(claim_of "$PB")" claim "the region's own handoff bullet is the claim"

echo "# a rework moved the head but left the summary unchanged; the stale handoff line is refreshed"
# The region's summary already matches the anchor, so the text comparison alone
# reads current — but its handoff bullet still names the pre-rework head with the
# pre-open sign-off claim. A head-only rework must still refresh, so the bullet
# names the current head and drops the false 'signed off pre-open' claim.
store "[$(anchor_sum H polecat/H 260 'correctness' 'STABLE: the summary a head-only rework did not touch.')]"
STALE_H=$(opened_region H polecat/H 'correctness' 'STABLE: the summary a head-only rework did not touch.' '11112222')
pr 260 OPEN polecat/H "$STALE_H" 3333444400000000
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "PR#260 summary region refreshed" "a head-only rework refreshes the region"
b=$(body 260)
hasnt "$b" 'signed off pre-open' "the false pre-open sign-off claim at the old head is gone"
has "$b" '- Head `33334444`; gates `correctness`; see the PR checks for current status.' \
    "the handoff bullet names the current head"
has "$b" 'STABLE: the summary a head-only rework did not touch.' "the unchanged summary is preserved"

echo "# that head-only refresh is idempotent: a second pass over the now-current region writes nothing"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "the second pass issues no edit"
hasnt "$out" "summary region refreshed" "…and reports no refresh"

echo "# a reworked summary and a newly stacked bead land in one edit"
store "[$(anchor_sum Y polecat/Y 220 'correctness' 'NEW: the reworked Y summary.'),
        $(printf '{"id":"Y2","status":"closed","title":"Stacked impl","created_at":"2026-02-01T00:00:00Z","metadata":{"branch":"polecat/Y2","merged_target":"polecat/Y","merge_result":"merged"}}')]"
STALE_Y=$(opened_region Y polecat/Y 'correctness' 'OLD: the pre-rework Y summary.' 'aaaa1111')
pr 220 OPEN polecat/Y "$STALE_Y" bbbb222200000000
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "PR#220 summary region refreshed" "the summary is refreshed"
has "$out" "PR#220 body now names 2 beads" "the branch-beads section is rendered in the same pass"
eq "$(grep -c 'pr edit 220' "$STUB_GH_LOG")" "1" "both regions land in exactly one edit"
b=$(body 220)
has "$b" 'NEW: the reworked Y summary.' "the new summary is published"
has "$b" '- `Y2` — Stacked impl' "the stacked bead is named"

echo "# a legacy markerless body is left for pr-open's adoption path, not reshaped here"
# No gc:pr-summary markers: establishing the region over a legacy prefix is the
# adoption path's job (pr-open.sh), so this arm leaves it rather than rewriting a
# body it did not compose.
store "[$(anchor_sum Z polecat/Z 230 'correctness' 'NEW: a summary with nowhere marked to go.')]"
LEGACY_Z=$(printf '%s\n' '## Summary' '' 'OLD legacy summary.' '' '## Refinery handoff' '' '- Issue: `Z`')
pr 230 OPEN polecat/Z "$LEGACY_Z" cccc333300000000
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "the markerless body is not rewritten"
eq "$(body 230)" "$LEGACY_Z" "…and is left byte-identical"

echo "# a pre_open_gate anchor's summary is arm 3's to refresh on adoption, not this arm's"
store "[$(printf '{"id":"PG","status":"open","title":"anchor PG","description":"","created_at":"2026-01-01T00:00:00Z","metadata":{"merge_result":"pre_open_gate","branch":"polecat/PG","pr_number":"250","merged_target":"main","check_set":"correctness","pr_summary":"NEW: a summary arm 3 will publish on adoption."}}')]"
STALE_PG=$(opened_region PG polecat/PG 'correctness' 'OLD PG summary.' 'ffff6666')
pr 250 OPEN polecat/PG "$STALE_PG" 9999888800000000
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "the pre_open_gate anchor's summary is left for arm 3"
eq "$(body 250)" "$STALE_PG" "…and the body is byte-identical"

echo "# a refresh whose edit fails is reported and retried, the body untouched"
store "[$(anchor_sum V polecat/V 240 'correctness' 'NEW: a summary whose edit never lands.')]"
STALE_V=$(opened_region V polecat/V 'correctness' 'OLD V summary.' 'dddd4444')
pr 240 OPEN polecat/V "$STALE_V" eeee555500000000
before_v=$(body 240)
out=$(STUB_PR_EDIT_RC=1 "$SUT" 2>&1)
has "$out" "PR#240 body edit failed" "the failed edit is reported"
hasnt "$out" "summary region refreshed" "…and no refresh is counted"
eq "$(body 240)" "$before_v" "the body never changed"

echo "# pacing: --deadline stops the walk after one PR and --cursor resumes after it"
# Three single-bead anchors, enumerated out of id order. A deadline of epoch 1
# has always passed, so a pass reads exactly one PR.
store "[$(anchor S3 polecat/S3 33), $(anchor S1 polecat/S1 31), $(anchor S2 polecat/S2 32)]"
pr 31 OPEN polecat/S1 "$OPENER_BODY"; pr 32 OPEN polecat/S2 "$OPENER_BODY"; pr 33 OPEN polecat/S3 "$OPENER_BODY"
SCUR="$TMP/stack.cursor"; rm -f "$SCUR"
views() { grep -o '^pr view [0-9]*' "$STUB_GH_LOG" | awk '{print $3}' | paste -sd, -; }
: > "$STUB_GH_LOG"
out=$("$SUT" --deadline 1 --cursor "$SCUR" 2>&1); rc=$?
eq "$rc" 0 "a paced pass exits 0"
eq "$(views)" "31" "a passed deadline reads the lowest id's PR and no other"
has "$out" "visited 1 PRs before the deadline; the next pass resumes at S2" "…and names where the next pass resumes"
eq "$(cat "$SCUR" 2>/dev/null)" "S1" "the cursor records the anchor finished"
: > "$STUB_GH_LOG"
out=$("$SUT" --deadline 1 --cursor "$SCUR" 2>&1)
eq "$(views)" "32" "the next pass resumes after the cursor"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(views)" "33,31,32" "with no pacing args every PR is read, in the enumerated order"
has "$out" "visited 3 of 3 PRs" "…and the walk reports all three"

# An open anchor carrying an issue_type and a title, for the PR title.
anchor_t() { # id branch num issue_type title [merge_result]
  printf '{"id":"%s","status":"open","issue_type":"%s","title":%s,"created_at":"2026-01-01T00:00:00Z","metadata":{"merge_result":"%s","branch":"%s","pr_number":"%s"}}' \
    "$1" "$4" "$(jq -n --arg t "$5" '$t')" "${6:-pull_request}" "$2" "$3"
}

echo "# a rework retitled the anchor; the open PR's title is composed from it again"
# pr-open writes the title once, at create, and the squash commit takes its subject
# from it. The anchor now names the reworked work, so the PR title follows it.
store "[$(anchor_t TA polecat/TA 300 bug 'Reject a moved head at merge')]"
pr 300 OPEN polecat/TA "$OPENER_BODY" "" "fix: Reject a moved head at open (TA)"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "the pass completes"
eq "$(title 300)" "fix: Reject a moved head at merge (TA)" \
   "the PR title is the anchor's current title, typed and suffixed as the create does"
has "$out" "PR#300 title now composed from the anchor" "the retitle is reported"
has "$out" "1 retitled" "…and counted"
eq "$(grep -c -- '--title' "$STUB_GH_LOG")" "1" "exactly one title edit"
hasnt "$(cat "$STUB_GH_LOG")" "--body-file" "a body already current is not rewritten alongside it"
eq "$(body 300)" "$OPENER_BODY" "…and stays byte-identical"

echo "# the retitle is idempotent: a second pass over the composed title writes nothing"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr edit" "the second pass issues no edit"
has "$out" "0 retitled" "…and counts no retitle"

echo "# a title edited on the PR itself is composed back from the anchor"
# The anchor owns the title, so a retitle is made there; a name typed into the PR
# alone is replaced on the next pass rather than kept beside a different anchor.
store "[$(anchor_t TB polecat/TB 310 feature 'Support integration branches')]"
pr 310 OPEN polecat/TB "$OPENER_BODY" "" "WIP: renamed by hand on the PR"
"$SUT" >/dev/null 2>&1
eq "$(title 310)" "feat: Support integration branches (TB)" "the hand-edited title is replaced by the anchor's"

echo "# an anchor title that already opens with a conventional type is not double-prefixed"
store "[$(anchor_t TC polecat/TC 320 task 'fix(pr-stack): keep the PR title current')]"
pr 320 OPEN polecat/TC "$OPENER_BODY" "" "chore: an older name (TC)"
"$SUT" >/dev/null 2>&1
eq "$(title 320)" "fix(pr-stack): keep the PR title current (TC)" \
   "the anchor's own type is kept and no derived type is prepended"

echo "# a title that differs only in whitespace is current, not rewritten every pass"
# Both sides are spaced differently from the composition: the anchor title, and
# the stored PR title. Neither is a difference in words.
store "[$(anchor_t TD polecat/TD 330 bug 'Tolerate  doubled   spaces ')]"
pr 330 OPEN polecat/TD "$OPENER_BODY" "" "$(printf 'fix:  Tolerate doubled spaces (TD)\n')"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "--title" "no title edit for a whitespace-only difference"
has "$out" "0 retitled" "…and none counted"

echo "# only a pull_request anchor's PR is retitled"
# The scope the summary refresh keeps: pre_open_gate is arm 3's state to adopt and
# flip, and a held anchor is parked for a person's decision.
store "[$(anchor_t TE polecat/TE 340 bug 'A new name' held),
        $(anchor_t TF polecat/TF 350 bug 'A new name' pre_open_gate)]"
pr 340 OPEN polecat/TE "$OPENER_BODY" "" "fix: An old name (TE)"
pr 350 OPEN polecat/TF "$OPENER_BODY" "" "fix: An old name (TF)"
: > "$STUB_GH_LOG"
"$SUT" >/dev/null 2>&1
hasnt "$(cat "$STUB_GH_LOG")" "--title" "neither a held nor a pre_open_gate anchor's PR is retitled"
eq "$(title 340),$(title 350)" "fix: An old name (TE),fix: An old name (TF)" "…and both titles stand"

echo "# a PR whose title reads back empty is never retitled blind"
store "[$(anchor_t TG polecat/TG 360 bug 'A title')]"
pr 360 OPEN polecat/TG "$OPENER_BODY"
jq 'del(.title)' "$GH_DIR/pr_view_360.json" > "$TMP/x" && mv "$TMP/x" "$GH_DIR/pr_view_360.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "the pass completes"
hasnt "$(cat "$STUB_GH_LOG")" "--title" "an unread title is not written over"

echo "# an anchor with no title leaves the PR's title as it stands"
store "[$(anchor_t TH polecat/TH 370 bug '  ')]"
pr 370 OPEN polecat/TH "$OPENER_BODY" "" "fix: what it opened as (TH)"
: > "$STUB_GH_LOG"
"$SUT" >/dev/null 2>&1
hasnt "$(cat "$STUB_GH_LOG")" "--title" "no bare type-and-id title is published"
eq "$(title 370)" "fix: what it opened as (TH)" "…and the title stands"

echo "# a failed title edit is reported and retried, and costs the body refresh nothing"
# A gh that refuses every title edit and serves everything else from the stub.
TITLEFAIL="$TMP/titlefail"
mkdir -p "$TITLEFAIL"
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${1:-} ${2:-}" = "pr edit" ]; then case " $* " in *" --title "*) printf "%s\n" "$*" >> "$STUB_GH_LOG"; exit 1 ;; esac; fi' \
  "exec \"$BIN/gh\" \"\$@\"" > "$TITLEFAIL/gh"
chmod +x "$TITLEFAIL/gh"
store "[$(anchor_sum TJ polecat/TJ 380 'correctness' 'NEW: the reworked TJ summary.')]"
STALE_TJ=$(opened_region TJ polecat/TJ 'correctness' 'OLD TJ summary.' 'aaaa0000')
pr 380 OPEN polecat/TJ "$STALE_TJ" bbbb000000000000 "chore: an old name (TJ)"
: > "$STUB_GH_LOG"
out=$(PATH="$TITLEFAIL:$PATH" "$SUT" 2>&1)
has "$(cat "$STUB_GH_LOG")" "--title chore: anchor TJ (TJ)" "the title edit was attempted"
has "$out" "PR#380 title edit failed" "the refused title is reported"
has "$out" "0 retitled" "…and not counted as retitled"
has "$out" "PR#380 summary region refreshed" "the body edit beside it still lands"
has "$(body 380)" 'NEW: the reworked TJ summary.' "…publishing the reworked summary"
eq "$(title 380)" "chore: an old name (TJ)" "the title is unchanged"
out=$("$SUT" 2>&1)
has "$out" "1 retitled" "the next pass retries the title"
eq "$(title 380)" "chore: anchor TJ (TJ)" "…and lands it"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
