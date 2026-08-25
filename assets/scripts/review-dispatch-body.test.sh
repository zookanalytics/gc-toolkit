#!/usr/bin/env bash
# Hermetic test for review-dispatch-body.sh — the dispatch note carried by
# every signoff review bead. No live city, Dolt, network, or PRs.
# The method itself lives in formulas/mol-review.toml, attached at dispatch;
# the note's job is to NAME that method, state the recovery path for a bead
# with no poured workflow, and forbid substituting any other method — the
# fan-out drift a bare title invites (a bead with only a title lets the
# reviewer pick a method out of its own catalog).
# Covered:
#   (NAME)      names mol-review and its formula file path.
#   (RECOVER)   states the no-poured-workflow recovery (gc formula show).
#   (NOOTHER)   forbids substituting another review method.
#   (NOFANOUT)  forbids subagents / persona reviewers / parallel passes.
#   (GATE)      one signoff.sh call; never gh pr review --approve.
#   (RC)        exits 0: a dispatch is never blocked on prose.
#   (NOTE)      --note appends a dispatch-context section; absent without it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/review-dispatch-body.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
# grep -F: the patterns are literal prose/markdown, never regex.
hasF() { grep -qF -- "$2" "$1" && ok "$3" || bad "$3 (missing: $2)"; }
notF() { grep -qF -- "$2" "$1" && bad "$3 (unexpected: $2)" || ok "$3"; }

RC=0
bash "$SCRIPT" > "$TMP/plain.out" 2> "$TMP/plain.err" || RC=$?
eq "$RC" "0" "(RC) exits 0"
eq "$(wc -c < "$TMP/plain.err" | tr -d ' ')" "0" "(RC) writes nothing to stderr"

OUT="$TMP/plain.out"
hasF "$OUT" 'mol-review' "(NAME) names the mol-review formula"
hasF "$OUT" 'formulas/mol-review.toml' "(NAME) names the formula's file path"
hasF "$OUT" 'gc formula show mol-review' "(RECOVER) states the no-poured-workflow recovery command"
hasF "$OUT" 'REVIEW_BEAD is this bead itself' "(RECOVER) tells the recovery agent the bead IS the review bead (no convoy to derive from)"
hasF "$OUT" 'Do not substitute any other review method' "(NOOTHER) forbids substituting another method"
hasF "$OUT" 'No fan-out' "(NOFANOUT) forbids fan-out"
hasF "$OUT" 'no persona reviewers' "(NOFANOUT) forbids persona reviewers"
hasF "$OUT" 'no parallel review pass' "(NOFANOUT) forbids a parallel review pass"
hasF "$OUT" 'exactly once' "(GATE) states the one-signoff-call rule"
hasF "$OUT" 'signoff.sh --review-bead' "(GATE) names the signoff.sh call shape"
hasF "$OUT" 'gh pr review --approve' "(GATE) addresses --approve (never used)"

echo "# --note"
bash "$SCRIPT" --note 'STALE-NOTE-a1b2: the head moved.' > "$TMP/note.out" 2>/dev/null
hasF "$TMP/note.out" '## Context from the dispatch' "(NOTE) --note adds the dispatch-context section"
hasF "$TMP/note.out" 'STALE-NOTE-a1b2: the head moved.' "(NOTE) --note text reaches the body"
notF "$TMP/plain.out" '## Context from the dispatch' "(NOTE) the section is absent without --note"

echo "# the named formula really ships in this pack"
ROOT="$(cd "$HERE/../.." && pwd)"
[ -r "$ROOT/formulas/mol-review.toml" ] \
  && ok "(NAME) formulas/mol-review.toml exists where the note points" \
  || bad "(NAME) formulas/mol-review.toml missing — the note names a formula the pack does not ship"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
