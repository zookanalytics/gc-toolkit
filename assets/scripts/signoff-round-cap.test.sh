#!/usr/bin/env bash
# Hermetic test for the signoff rework-round cap (tk-uqfk1).
#
# Every REQUEST_CHANGES verdict files a rework child and wakes the fix pool;
# the hand-back then makes the refinery mint a fresh codex review and wake the
# codex pool. Both pools are wake_mode="fresh", so each round pays two cold
# full contexts. The loop is unbounded by construction — docs/work-bead-state-
# machine.md:360 says the PR is "a long-lived object across however many rework
# rounds it takes" — and one PR was observed reaching 15 rounds.
#
# The cap counts rounds off the anchor's own parent-child children (one child
# per round, by construction) and past the cap escalates INSTEAD of filing.
# Not filing is the fail-safe: the merge hold derives from OPEN children
# (assets/scripts/merge-skill.sh), so an anchor with zero children stays held
# and parks for a human with nothing left to spawn.
#
# This test EXECUTES the real counting snippet extracted verbatim from the
# template (between the `signoff-round-cap` markers) against a fake `gc`, so it
# cannot drift from the shipped instruction. No live city, Dolt, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TEMPLATE="$ROOT/template-fragments/polecat-non-impl-done.template.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: the single read the counting snippet performs. -----------------
# gc bd dep list <anchor> --direction=up -t parent-child --json
# FAKE_CHILDREN is a raw JSON array of child beads, echoed verbatim, so a test
# case can mix rework children (source_review_bead present) with other children
# (rebase/convoy members) and assert only the rework ones are counted.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || exit 0
[ "$2" = "dep" ] || exit 0
if [ -n "${FAKE_CHILDREN:-}" ]; then printf '%s\n' "$FAKE_CHILDREN"; else printf '[]\n'; fi
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# --- extract the shipped snippet verbatim ------------------------------------
awk '/# >>> signoff-round-cap/{f=1;next} /# <<< signoff-round-cap/{f=0} f' \
  "$TEMPLATE" > "$TMP/cap.sh"
[ -s "$TMP/cap.sh" ] || { echo "FAIL - could not extract signoff-round-cap snippet"; exit 1; }
grep -q 'source_review_bead' "$TMP/cap.sh" \
  && ok "snippet extracted from template and counts on source_review_bead" \
  || bad "extracted snippet does not filter on source_review_bead"

# run_cap <anchor> <children-json> [max] -> "ROUNDS CAP_HIT"
run_cap() {
  ANCHOR="$1" FAKE_CHILDREN="$2" GC_MAX_REVIEW_ROUNDS="${3-}" \
  bash -c 'set -euo pipefail; ANCHOR="${ANCHOR}"; source "$1"; echo "$ROUNDS $CAP_HIT"' _ "$TMP/cap.sh"
}

child() { printf '{"id":"%s","metadata":{"source_review_bead":"rv-%s"}}' "$1" "$1"; }

# --- default cap is 3 --------------------------------------------------------
eq "$(run_cap tk-anchor '[]')"                          "0 0" "no children -> 0 rounds, no cap"
eq "$(run_cap tk-anchor "[$(child a)]")"                "1 0" "1 round -> under cap"
eq "$(run_cap tk-anchor "[$(child a),$(child b)]")"     "2 0" "2 rounds -> under cap"
eq "$(run_cap tk-anchor "[$(child a),$(child b),$(child c)]")" \
                                                        "3 1" "3 rounds -> cap trips"
eq "$(run_cap tk-anchor "[$(child a),$(child b),$(child c),$(child d)]")" \
                                                        "4 1" "past cap stays tripped"

# --- only rework children count ----------------------------------------------
# A rebase/convoy child carries no source_review_bead and must not inflate the
# count; otherwise an anchor with unrelated children caps before its first
# real rework round and parks live work for a human.
eq "$(run_cap tk-anchor "[{\"id\":\"reb\",\"metadata\":{}},$(child a)]")" \
   "1 0" "non-rework children are not counted as rounds"
eq "$(run_cap tk-anchor '[{"id":"reb","metadata":{}},{"id":"cv","metadata":{"branch":"x"}}]')" \
   "0 0" "children with no source_review_bead at all -> 0 rounds"

# --- cap is tunable ----------------------------------------------------------
eq "$(run_cap tk-anchor "[$(child a)]" 1)"              "1 1" "GC_MAX_REVIEW_ROUNDS=1 trips at 1"
eq "$(run_cap tk-anchor "[$(child a),$(child b)]" 5)"   "2 0" "GC_MAX_REVIEW_ROUNDS=5 raises the bar"

# --- no anchor never caps ----------------------------------------------------
# Without an anchor there is no reliable round history. Capping on a guess would
# park live work for a human, so the cap must stay off.
eq "$(run_cap '' "[$(child a),$(child b),$(child c),$(child d)]")" \
   "0 0" "empty anchor -> never caps"

# --- degraded store must not cap ---------------------------------------------
# A failing/empty `gc bd dep list` reads as zero rounds, not as "past the cap".
# The wrong direction here would strand every review during a store outage.
eq "$(run_cap tk-anchor 'not-json')" "0 0" "unparseable dep list -> 0 rounds, no cap"

echo "--- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
