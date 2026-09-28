#!/usr/bin/env bash
# materiality.test.sh — hermetic tests for the human-approval materiality gate.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-materiality-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
unset GC_RIG 2>/dev/null || true
harness_init
SUT="$HERE/materiality.sh"

ANCHOR='{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex,approval","pr_number":"42"}}'
NOPR='{"id":"tk-nopr","status":"open","assignee":"","title":"pre-open","notes":"","metadata":{"merge_result":"pre_open_gate","check_set":"codex"}}'

# GitHub reviews fixture: one row per review, latest-per-login wins.
reviews() { printf '%s' "$1" > "$GH_DIR/reviews_42.json"; }
# compare(<base>...<head>) file set. Empty = the head added nothing.
compare() { printf '%s' "$2" > "$GH_DIR/compare_$1.json"; }
classify() { "$SUT" classify "$@"; }
record()   { "$SUT" record "$@"; }

APPROVED_AT() { printf '[{"id":1,"user":{"login":"johnzook"},"state":"APPROVED","commit_id":"%s","submitted_at":"2026-09-28T10:00:00Z"}]' "$1"; }

# ---------------------------------------------------------------------------
# No PR on the anchor: there is no GitHub approval to weigh.
# ---------------------------------------------------------------------------
store "[$NOPR]"
eq "$(classify --anchor tk-nopr)" "none" "a pre-open anchor with no PR classifies none"

# ---------------------------------------------------------------------------
# No APPROVED review: the approval gate is unmet by any approval.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
reviews '[{"id":1,"user":{"login":"johnzook"},"state":"COMMENTED","commit_id":"aaaa","submitted_at":"2026-09-28T10:00:00Z"}]'
eq "$(classify --anchor tk-anc)" "none" "a PR with only a COMMENTED review classifies none"

# ---------------------------------------------------------------------------
# Approval at the live head: trivially covered, no diff read needed.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
reviews "$(APPROVED_AT hhhh)"
printf '{"headRefOid":"hhhh"}' > "$GH_DIR/pr_view_42.json"
eq "$(classify --anchor tk-anc)" "at-head" "an approval at the live head is at-head"

# ---------------------------------------------------------------------------
# Approval behind the head, but the head adds no file change: immaterial,
# decided mechanically without an agent verdict.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
reviews "$(APPROVED_AT aaaa)"
printf '{"headRefOid":"hhhh"}' > "$GH_DIR/pr_view_42.json"
compare "aaaa...hhhh" '{"files":[]}'
eq "$(classify --anchor tk-anc)" "immaterial" "an approval behind a no-op rewrite stands (immaterial)"

# ---------------------------------------------------------------------------
# Approval behind a content change, no verdict recorded: a re-review is owed.
# This is the fail-closed default — the case an agent judgment relaxes.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
reviews "$(APPROVED_AT aaaa)"
compare "aaaa...hhhh" '{"files":[{"filename":"x.sh","patch":"@@ -1 +1 @@\n-a\n+b"}]}'
eq "$(classify --anchor tk-anc --head hhhh)" "owed" "a content change since the approval, unjudged, is owed"

# ---------------------------------------------------------------------------
# An agent's recorded verdict for this exact head wins over the mechanical read.
# ---------------------------------------------------------------------------
STANDS='{"id":"tk-anc","status":"open","assignee":"","title":"a","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex,approval","pr_number":"42","approval_materiality":"stands@aaaa..hhhh"}}'
store "[$STANDS]"
reviews "$(APPROVED_AT aaaa)"
compare "aaaa...hhhh" '{"files":[{"filename":"x.sh","patch":"@@"}]}'
eq "$(classify --anchor tk-anc --head hhhh)" "stands" "an agent verdict stands@a..h covers a content change"

OWED='{"id":"tk-anc","status":"open","assignee":"","title":"a","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex,approval","pr_number":"42","approval_materiality":"owed@aaaa..hhhh"}}'
store "[$OWED]"
reviews "$(APPROVED_AT aaaa)"
compare "aaaa...hhhh" '{"files":[]}'
eq "$(classify --anchor tk-anc --head hhhh)" "owed" "an agent verdict owed@a..h holds even when the head adds nothing"

# ---------------------------------------------------------------------------
# A verdict recorded for a DIFFERENT head is stale: it is ignored and the
# current head is judged fresh. A commit past the judged head is unjudged.
# ---------------------------------------------------------------------------
STALE='{"id":"tk-anc","status":"open","assignee":"","title":"a","notes":"","metadata":{"merge_result":"pull_request","check_set":"codex,approval","pr_number":"42","approval_materiality":"stands@aaaa..OLDHEAD"}}'
store "[$STALE]"
reviews "$(APPROVED_AT aaaa)"
compare "aaaa...hhhh" '{"files":[{"filename":"x.sh","patch":"@@"}]}'
eq "$(classify --anchor tk-anc --head hhhh)" "owed" "a stands verdict for a superseded head does not cover a later head"

# ---------------------------------------------------------------------------
# Latest review per reviewer wins: an APPROVED later retracted by the same
# account's CHANGES_REQUESTED is no standing approval.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
reviews '[{"id":1,"user":{"login":"johnzook"},"state":"APPROVED","commit_id":"aaaa","submitted_at":"2026-09-28T10:00:00Z"},{"id":2,"user":{"login":"johnzook"},"state":"CHANGES_REQUESTED","commit_id":"hhhh","submitted_at":"2026-09-28T11:00:00Z"}]'
eq "$(classify --anchor tk-anc --head hhhh)" "none" "an approval the same reviewer later retracted is not standing"

# ---------------------------------------------------------------------------
# Two standing approvers: record keys its marker on the MOST RECENT approval —
# the base merge.sh's reducer weighs (assets/scripts/merge.sh approval arm) — so
# the verdict an agent records is the one the merge gate reads back. group_by
# orders by login, so the first row after the reduction is the alphabetically
# first reviewer (alpha at the old commit), not the most recent (zeta at the new
# commit); keying the marker on that old commit would leave merge — which weighs
# zeta's new commit — unable to match it, and the hold would stay owed under a
# recorded stands verdict.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
reviews '[{"id":1,"user":{"login":"alpha"},"state":"APPROVED","commit_id":"oldsha","submitted_at":"2026-09-28T10:00:00Z"},{"id":2,"user":{"login":"zeta"},"state":"APPROVED","commit_id":"newsha","submitted_at":"2026-09-28T11:00:00Z"}]'
eq "$(record --anchor tk-anc --verdict stands --head hhhh)" "stands@newsha..hhhh" "record keys the marker on the most recent standing approval (zeta at 11:00), not the first"
eq "$(meta tk-anc approval_materiality)" "stands@newsha..hhhh" "…and persists that marker on the anchor"
# The merge gate weighs the same most-recent approval (newsha), so classify reads
# the recorded stands back — record and merge agree on the approved oid.
eq "$(classify --anchor tk-anc --approved-oid newsha --head hhhh)" "stands" "the most-recent approved oid reads the recorded verdict back"
# A classify keyed on the stale first approval (oldsha) does not match the marker
# and falls through to a fresh judgment — owed on a content change.
compare "oldsha...hhhh" '{"files":[{"filename":"x.sh","patch":"@@"}]}'
eq "$(classify --anchor tk-anc --approved-oid oldsha --head hhhh)" "owed" "the stale first-approval oid does not match the recorded verdict"

# ---------------------------------------------------------------------------
# Fail-closed reads: an unreadable reviews history or compare exits 2, which
# the merge gate reads as owed, never as covered.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
reviews "$(APPROVED_AT aaaa)"
STUB_GH_LIST_RC=1 classify --anchor tk-anc --head hhhh >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an unreadable reviews history exits 2 (fail-closed)"

store "[$ANCHOR]"
reviews "$(APPROVED_AT aaaa)"
rm -f "$GH_DIR/compare_aaaa...hhhh.json"
classify --anchor tk-anc --head hhhh >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an unreadable compare exits 2 (fail-closed)"

store "[]"
classify --anchor tk-gone --head hhhh >/dev/null 2>&1; rc=$?
eq "$rc" 2 "an anchor that does not resolve exits 2"

# ---------------------------------------------------------------------------
# The merge-gate call path: --approved-oid and --head passed in, so classify
# reads neither the reviews history nor the PR head itself.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
rm -f "$GH_DIR/reviews_42.json" "$GH_DIR/pr_view_42.json"
compare "aaaa...hhhh" '{"files":[]}'
eq "$(classify --anchor tk-anc --approved-oid aaaa --head hhhh)" "immaterial" "with oids supplied, classify needs no reviews/pr read"

# ---------------------------------------------------------------------------
# record: the agent's verdict is the only writer of approval_materiality.
# ---------------------------------------------------------------------------
store "[$ANCHOR]"
reviews "$(APPROVED_AT aaaa)"
out=$(record --anchor tk-anc --verdict stands --head hhhh); rc=$?
eq "$rc" 0 "record stands exits 0"
eq "$out" "stands@aaaa..hhhh" "record stands echoes the marker it wrote"
eq "$(meta tk-anc approval_materiality)" "stands@aaaa..hhhh" "record stands persisted the marker on the anchor"

store "[$ANCHOR]"
reviews "$(APPROVED_AT aaaa)"
record --anchor tk-anc --verdict owed --head hhhh >/dev/null
eq "$(meta tk-anc approval_materiality)" "owed@aaaa..hhhh" "record owed persisted the marker"

# record refuses when there is no standing approval to cover.
store "[$ANCHOR]"
reviews '[{"id":1,"user":{"login":"x"},"state":"COMMENTED","commit_id":"aaaa","submitted_at":"2026-09-28T10:00:00Z"}]'
record --anchor tk-anc --verdict stands --head hhhh >/dev/null 2>&1; rc=$?
eq "$rc" 1 "record refuses (exit 1) when no approval stands to cover"

# record refuses a bad verdict word.
store "[$ANCHOR]"
record --anchor tk-anc --verdict maybe --head hhhh >/dev/null 2>&1; rc=$?
eq "$rc" 1 "record refuses an unknown verdict word"

# A write that does not read back exits 2 (the gate stays owed).
store "[$ANCHOR]"
reviews "$(APPROVED_AT aaaa)"
STUB_DROP_KEYS="tk-anc:approval_materiality" record --anchor tk-anc --verdict stands --head hhhh >/dev/null 2>&1; rc=$?
eq "$rc" 2 "a verdict write that did not read back exits 2"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
