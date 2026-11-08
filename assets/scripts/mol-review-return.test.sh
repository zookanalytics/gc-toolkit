#!/usr/bin/env bash
# Hermetic test for a review's return to its pool once its run has ended:
# mol-review's review-return block, which load-dispatch runs after a failed
# gather's cancel and verdict-and-drain after a failed verdict's step close,
# and the same sling the quorum sign-off's synthesis names after its own close.
#
# The block routes the review with `gc sling "$GC_TEMPLATE" <review>
# --no-formula --no-convoy`. $GC_TEMPLATE is the pool the session serves, so
# the block reads nothing from the store, and a store that does not answer
# cannot leave the review with no route and no run. A sling that fails is
# noted on the review, which then rests unrouted, and the session drains
# either way. Each copy is taken from the parsed formula, as a pour renders it,
# and run against a stub gc that logs every call. No live city, store or
# network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
REVIEW_TOML="$ROOT/formulas/mol-review.toml"
QUORUM_TOML="$ROOT/formulas/mol-review-quorum-signoff.toml"
MARK=review-return
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-mol-review-return-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions and tomllib_python only
PASS=0; FAIL=0

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
for f in "$REVIEW_TOML" "$QUORUM_TOML"; do
  [ -s "$f" ] || { echo "formula not found: $f" >&2; exit 1; }
done
if ! PY="$(tomllib_python)"; then
  echo "skip - review return: $PY"
  exit 0
fi

# copies <toml> — every review-return block in the formula's steps, as JSON:
# the step that carries it, the block as the pour renders it, and the step's
# text before it.
copies() {
  "$PY" - "$1" "$MARK" <<'PY'
import json, re, sys, tomllib
path, mark = sys.argv[1], sys.argv[2]
pat = re.compile(r"^# >>> " + re.escape(mark) + r"\n(.*?)^# <<< " + re.escape(mark) + r"$", re.S | re.M)
out = []
with open(path, "rb") as f:
    for step in tomllib.load(f)["steps"]:
        text = step.get("description", "")
        for m in pat.finditer(text):
            out.append({"step": step["id"], "block": m.group(1), "before": text[:m.start()]})
print(json.dumps(out))
PY
}
REVIEW_COPIES="$(copies "$REVIEW_TOML")"
eq "$(printf '%s' "$REVIEW_COPIES" | jq -r '[.[].step] | join(" ")')" "load-dispatch verdict-and-drain" \
  "mol-review: the return is in load-dispatch's and verdict-and-drain's failure arms, once each"
BLOCK="$(printf '%s' "$REVIEW_COPIES" | jq -r '.[0].block')"
[ -n "$BLOCK" ] && ok "the block extracts between its markers" || bad "the block extracts between its markers (none found)"
eq "$(printf '%s' "$REVIEW_COPIES" | jq -r 'map(.block) | unique | length')" "1" "both copies are the same block"
# shellcheck disable=SC2016  # the sling as the step text spells it, unexpanded
SLING='gc sling "$GC_TEMPLATE" "{{review_bead}}" --no-formula --no-convoy'
has "$BLOCK" "$SLING" "the block's sling is the one the quorum sign-off names"

# Each copy runs only once the run has ended: after load-dispatch's cancel, and
# after the failed verdict's step close.
before() { # <copies> <step> — the step's text before its block, on one line
  printf '%s' "$1" | jq -r --arg s "$2" '.[] | select(.step == $s) | .before | gsub("\\s+"; " ")'
}
has "$(before "$REVIEW_COPIES" load-dispatch)" "run-cancel.sh\" --step mol-review.load-dispatch" \
  "load-dispatch: the return follows the cancel of the run"
has "$(before "$REVIEW_COPIES" verdict-and-drain)" "close this step with part 3's claim-close.sh call; then, only after the step is closed, return the review" \
  "verdict-and-drain: the return follows the step's close"

# The quorum's synthesis gives the same sling in the prose of its failure arms,
# after the step's close, with the note a failed sling leaves.
QTEXT="$("$PY" - "$QUORUM_TOML" <<'PY'
import re, sys, tomllib
with open(sys.argv[1], "rb") as f:
    for step in tomllib.load(f)["steps"]:
        if step["id"] == "synthesize-and-signoff":
            print(re.sub(r"\s+", " ", step["description"]))
PY
)"
has "$QTEXT" "close this step, then return the review to your pool with \`$SLING\`" \
  "the quorum's synthesis: its failure arms return the review with the same sling, after the step's close"
has "$QTEXT" "append what a failed sling said to the review bead's notes, and drain" "…noting a failed sling on the review"

# Nothing in either formula routes a review by hand or reads the pool the
# dispatch stamped.
for f in "$REVIEW_TOML" "$QUORUM_TOML"; do
  n="${f##*/}"
  eq "$(grep -c -- '--set-metadata gc.routed_to' "$f")" "0" "$n: no route is written by hand"
  eq "$(grep -c 'review_pool' "$f")" "0" "$n: nothing reads the review's review_pool"
done

# The block as a pour renders it for review bead rb.
printf '%s' "$BLOCK" | sed -e 's|{{review_bead}}|rb|g' -e 's|{{binding_prefix}}|gc-toolkit.|g' > "$TMP/return.sh"
hasnt "$(cat "$TMP/return.sh")" "{{" "the rendered block keeps no placeholder"
bash -n "$TMP/return.sh" && ok "the rendered block is valid bash" || bad "the rendered block is valid bash"

# gc: every call is logged. A sling refuses an empty target, as gc refuses an
# agent city.toml does not name, and STUB_SLING_ERR fails it with that message.
# STUB_BD_DOWN fails every bd call, a store that does not answer.
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1" in
  sling)
    [ -n "${2:-}" ] || { echo 'gc sling: agent "" not found in city.toml' >&2; exit 1; }
    [ -z "${STUB_SLING_ERR:-}" ] || { echo "$STUB_SLING_ERR" >&2; exit 1; }
    echo "Slung $3 to $2"; exit 0 ;;
  bd) [ -z "${STUB_BD_DOWN:-}" ] || { echo "bd: the store did not answer" >&2; exit 1; } ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

ret() { # [VAR=value...] — runs the rendered block; sets RC and OUT, and LOG to the gc calls
  : > "$TMP/gc.log"
  RC=0
  OUT="$(env -u GC_TEMPLATE -u STUB_SLING_ERR -u STUB_BD_DOWN PATH="$TMP/bin:$PATH" STUB_LOG="$TMP/gc.log" "$@" bash "$TMP/return.sh" 2>&1)" || RC=$?
  LOG="$(cat "$TMP/gc.log")"
}
POOL=gc-toolkit/gc-toolkit.polecat

ret GC_TEMPLATE="$POOL"
eq "$RC" "0" "a sling that lands: the block exits 0"
eq "$LOG" "sling $POOL rb --no-formula --no-convoy
runtime drain-ack" "…it slings the review to the session's pool with no formula and no convoy, then drains, and makes no other call"
has "$OUT" "Slung rb to $POOL" "…printing what the sling said"

ret GC_TEMPLATE="$POOL" STUB_BD_DOWN=1
eq "$RC|$LOG" "0|sling $POOL rb --no-formula --no-convoy
runtime drain-ack" "a store that does not answer: the return reads nothing from it, so it still slings and drains"

ret GC_TEMPLATE="$POOL" STUB_SLING_ERR="gc sling: refusing cross-store route"
eq "$(printf '%s\n' "$LOG" | sed -n 1p)" "sling $POOL rb --no-formula --no-convoy" "a sling that fails: it was asked once"
eq "$(printf '%s\n' "$LOG" | sed -n 2p)" "bd update rb --append-notes gc sling could not return this review to its pool '$POOL', so it rests unrouted until gate-ensure asks a person: gc sling: refusing cross-store route" \
  "…the review's notes say so, with the pool and the sling's refusal"
eq "$(printf '%s\n' "$LOG" | sed -n '3,$p')" "runtime drain-ack" "…and the session drains"
hasnt "$LOG" "gc.routed_to" "…writing no route by hand"

ret
eq "$(printf '%s\n' "$LOG" | sed -n 1p)" "sling  rb --no-formula --no-convoy" "no GC_TEMPLATE: the sling names no pool, which gc refuses"
has "$(printf '%s\n' "$LOG" | sed -n 2p)" "bd update rb --append-notes gc sling could not return this review" "…and the refusal is noted on the review"
eq "$(printf '%s\n' "$LOG" | grep -c -e '^bd show' -e '^bd list')" "0" "…with no read of the store for a pool"
eq "$(printf '%s\n' "$LOG" | tail -1)" "runtime drain-ack" "…and the session drains"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
