#!/usr/bin/env bash
# Hermetic test for assets/scripts/input-convoy-reap.sh. Covers the live-namer
# gate in both directions: a convoy whose workflow is closed and a convoy no
# workflow ever named are closed, while a convoy a live root names, a convoy a
# root in an unlisted status names, and a convoy inside the grace window (or
# with an unreadable created_at) stay open. Also the scope boundary (owned,
# non-synthetic, differently titled and already-closed convoys untouched), the
# dry run, the close reason, --db reaching every call, a refused close, an
# unreadable listing, and the refusal when the store holds no workflow roots.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-input-convoy-reap-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/input-convoy-reap.sh"
SUT="$SD/input-convoy-reap.sh"
run() { "$SUT" "$@" 2>&1; }

OLD="2026-01-01T00:00:00Z"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# convoy <id> <tracked> <created_at> [labels-json] — an open synthetic input convoy.
convoy() {
  printf '{"id":"%s","status":"open","issue_type":"convoy","title":"input convoy for %s","created_at":"%s","labels":%s,"metadata":{"gc.synthetic":"true"},"dependencies":[{"type":"tracks","depends_on_id":"%s"}]}' \
    "$1" "$2" "$3" "${4:-[]}" "$2"
}
# root <id> <status> <convoy> — a workflow root naming the convoy.
root() {
  printf '{"id":"%s","status":"%s","issue_type":"task","title":"workflow %s","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"%s"}}' \
    "$1" "$2" "$1" "$3"
}

STORE="[$(convoy CFIN W1 "$OLD"),$(root RFIN closed CFIN),
$(convoy CUNN W2 "$OLD"),
$(convoy CLIVE W3 "$OLD"),$(root RLIVE in_progress CLIVE),$(root RLIVE0 closed CLIVE),
$(convoy CODD W4 "$OLD"),$(root RODD review CODD),
$(convoy CYOUNG W5 "$NOW"),
$(convoy CNODATE W6 "not-a-date"),
$(convoy COWN W7 "$OLD" '["owned"]'),
{\"id\":\"CPLAIN\",\"status\":\"open\",\"issue_type\":\"convoy\",\"title\":\"input convoy for W8\",\"created_at\":\"$OLD\",\"metadata\":{}},
{\"id\":\"CSLING\",\"status\":\"open\",\"issue_type\":\"convoy\",\"title\":\"sling-W9\",\"created_at\":\"$OLD\",\"metadata\":{\"gc.synthetic\":\"true\"}},
{\"id\":\"CDONE\",\"status\":\"closed\",\"issue_type\":\"convoy\",\"title\":\"input convoy for W10\",\"created_at\":\"$OLD\",\"metadata\":{\"gc.synthetic\":\"true\"}}]"

echo "# dry run: reports the dead convoys, closes nothing"
store "$STORE"
out=$(run); rc=$?
eq "$rc" 0 "a dry run exits 0"
has "$out" "would close CFIN (input convoy for W1): its workflow is closed (RFIN)" "a finished workflow's convoy is reported, naming the closed root"
has "$out" "would close CUNN (input convoy for W2): no workflow ever named it" "a never-named convoy is reported"
has "$out" "2 dead (1 finished, 1 never named) would close" "the summary counts the dead by kind"
has "$out" "2 live and 2 in the 60m grace window left alone" "…and the live and young convoys it leaves"
eq "$(bstatus CFIN)" "open" "the dry run closes nothing"
eq "$(bstatus CUNN)" "open" "…not even the never-named convoy"
if grep -q '^bd close' "$STUB_GC_LOG"; then bad "the dry run issued a close"; else ok "the dry run issued no close"; fi

echo "# --apply closes the dead and only the dead"
: > "$STUB_GC_LOG"
out=$(run --apply); rc=$?
eq "$rc" 0 "an applying pass exits 0"
eq "$(bstatus CFIN)" "closed" "the convoy of a closed workflow is closed"
eq "$(bstatus CUNN)" "closed" "a convoy no workflow ever named is closed"
eq "$(bstatus CLIVE)" "open" "a convoy a live root names stays open, though a closed root names it too"
eq "$(bstatus CODD)" "open" "a root in a status the script does not list still protects its convoy"
eq "$(bstatus CYOUNG)" "open" "a convoy inside the grace window stays open"
eq "$(bstatus CNODATE)" "open" "a convoy whose created_at does not parse reads as young"
eq "$(bstatus COWN)" "open" "an owned convoy is out of scope"
eq "$(bstatus CPLAIN)" "open" "a convoy without gc.synthetic is out of scope"
eq "$(bstatus CSLING)" "open" "a synthetic convoy with another title is out of scope"
eq "$(bstatus RFIN)" "closed" "the workflow roots are not touched"
eq "$(bstatus RLIVE)" "in_progress" "…live or closed"
has "$out" "closed CFIN" "each close is named"
has "$out" "2 dead (1 finished, 1 never named): 2 closed, 0 left open for a re-run" "the summary counts what closed"
has "$(grep '^bd close CFIN' "$STUB_GC_LOG")" "no live bead names this input convoy as gc.input_convoy_id" "the close carries the gate as its reason"
NCLOSE=$(grep -c '^bd close' "$STUB_GC_LOG")
eq "$NCLOSE" 2 "exactly two closes are issued"

echo "# a second pass finds nothing left to close"
out=$(run --apply)
has "$out" "0 dead (0 finished, 0 never named): 0 closed" "the pass is idempotent"

echo "# --db reaches every gc bd call"
store "$STORE"; : > "$STUB_GC_LOG"
run --apply --db /rig/.beads >/dev/null
NBD=$(grep -c '^bd ' "$STUB_GC_LOG")
NDB=$(grep -c -- '--db /rig/.beads' "$STUB_GC_LOG")
eq "$NDB" "$NBD" "every gc bd call carries the --db pin ($NBD calls)"

echo "# a refused close is reported and left for a re-run"
store "$STORE"
out=$(STUB_CLOSE_FAIL="CUNN" run --apply); rc=$?
eq "$rc" 0 "a refused close does not fail the pass"
eq "$(bstatus CUNN)" "open" "the refused convoy is still open"
eq "$(bstatus CFIN)" "closed" "…the other dead convoy still closes"
has "$out" "close of CUNN was refused" "the refusal is named"
has "$out" "1 closed, 1 left open for a re-run" "…and counted as left open"

echo "# a close that reports success but does not land is not counted"
store "$STORE"
mkdir -p "$TMP/shim"
cat > "$TMP/shim/gc" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = bd ] && [ "\$2" = close ] && [ "\$3" = CFIN ]; then exit 0; fi
exec "$BIN/gc" "\$@"
SHIM
chmod +x "$TMP/shim/gc"
out=$(PATH="$TMP/shim:$PATH" run --apply); rc=$?
eq "$rc" 0 "an unconfirmed close does not fail the pass"
eq "$(bstatus CFIN)" "open" "the convoy really is still open"
has "$out" "1 convoy(s) reported closed still list as open" "the read-back names the miss"
has "$out" "1 closed, 1 left open for a re-run" "…and the summary does not count it closed"

echo "# an unreadable listing closes nothing"
store "$STORE"
out=$(STUB_LIST_FAIL=1 run --apply); rc=$?
eq "$rc" 1 "an unreadable listing exits 1"
eq "$(bstatus CFIN)" "open" "…and closes nothing"
has "$out" "nothing closed" "…and says so"

echo "# a store where no bead names any input convoy is refused"
store "[$(convoy CA W1 "$OLD"),$(convoy CB W2 "$OLD")]"
out=$(run --apply); rc=$?
eq "$rc" 1 "no workflow roots in the store exits 1"
eq "$(bstatus CA)" "open" "…and closes nothing"
has "$out" "may live in another store" "…naming the reason"

echo "# usage"
out=$(run --grace-minutes soon); rc=$?
eq "$rc" 2 "a non-numeric grace window is a usage error"
out=$(run --bogus); rc=$?
eq "$rc" 2 "an unknown argument is a usage error"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
