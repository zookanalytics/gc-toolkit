#!/usr/bin/env bash
# Hermetic test for validate-dispatch-body.sh — the dispatch note carried by
# every validation-pass bead. No live city, Dolt, network, or PRs.
# The method itself lives in formulas/mol-validate.toml, attached at dispatch;
# the note's job is to NAME that method, state the recovery path for a bead
# with no poured workflow, and forbid substituting any other method.
# Covered:
#   (NAME)      names mol-validate and its formula file path.
#   (RECOVER)   states the no-poured-workflow recovery (gc formula show).
#   (NOOTHER)   forbids substituting another method.
#   (NOFANOUT)  forbids subagents / persona validators / parallel passes.
#   (WRITES)    names the disposition + review-outcome writes; never check.<lane>.
#   (PEER)      the human-finding rule is the peer model — decline on merits +
#               owed reply — not the retired referral (hold must-fix, refer by
#               visit, only the raiser withdraws).
#   (NOAPPROVE) never gh pr review --approve.
#   (RC)        exits 0: a dispatch is never blocked on prose.
#   (NOTE)      --note appends a dispatch-context section; absent without it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/validate-dispatch-body.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-validate-dispatch-body-test.XXXXXX")"
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
hasF "$OUT" 'mol-validate' "(NAME) names the mol-validate formula"
hasF "$OUT" 'formulas/mol-validate.toml' "(NAME) names the formula's file path"
hasF "$OUT" 'gc formula show mol-validate' "(RECOVER) states the no-poured-workflow recovery command"
hasF "$OUT" 'VALIDATION_PASS is this bead itself' "(RECOVER) tells the recovery agent the bead IS the validation-pass bead"
hasF "$OUT" 'Do not substitute any other method' "(NOOTHER) forbids substituting another method"
hasF "$OUT" 'No fan-out' "(NOFANOUT) forbids fan-out"
hasF "$OUT" 'no persona validators' "(NOFANOUT) forbids persona validators"
hasF "$OUT" 'no parallel validation pass' "(NOFANOUT) forbids a parallel validation pass"
hasF "$OUT" 'finding.disposition' "(WRITES) names the disposition write"
hasF "$OUT" 'review-outcome.sh' "(WRITES) names the review-outcome write"
hasF "$OUT" 'never stamps a `check.<lane>` marker' "(WRITES) forbids the retired lane marker"
hasF "$OUT" 'ruled on its merits like a machine one' "(PEER) a human finding is ruled on its merits, not held gospel"
hasF "$OUT" 'owes them an answer' "(PEER) declining a human objection owes a reply"
hasF "$OUT" "posted to their PR thread by pr-facts.sh's write-back" "(PEER) the owed reply rides the write-back"
notF "$OUT" 'referred to the operator by a visit' "(PEER) the retired referral rule is gone"
notF "$OUT" 'only they may withdraw' "(PEER) the only-the-raiser-withdraws rule is gone"
hasF "$OUT" 'gh pr review --approve' "(NOAPPROVE) addresses --approve (never used)"

echo "# --note"
bash "$SCRIPT" --note 'BATCH-h1: human feedback set.' > "$TMP/note.out" 2>/dev/null
hasF "$TMP/note.out" '## Context from the dispatch' "(NOTE) --note adds the dispatch-context section"
hasF "$TMP/note.out" 'BATCH-h1: human feedback set.' "(NOTE) --note text reaches the body"
notF "$TMP/plain.out" '## Context from the dispatch' "(NOTE) the section is absent without --note"

echo "# the named formula really ships in this pack"
ROOT="$(cd "$HERE/../.." && pwd)"
[ -r "$ROOT/formulas/mol-validate.toml" ] \
  && ok "(NAME) formulas/mol-validate.toml exists where the note points" \
  || bad "(NAME) formulas/mol-validate.toml missing — the note names a formula the pack does not ship"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
