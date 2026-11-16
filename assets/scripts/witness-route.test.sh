#!/usr/bin/env bash
# Hermetic test for the two witness-patrol blocks that file work, neither of
# which stamps an address: no-progress-finding, one call to seat-progress.sh,
# and bug-file, which holds a pack defect for placement. It also holds every
# step of the formula to resolving each address it builds. Stubbed gc and
# patrol-finding.sh; no live city, Dolt or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-witness-route-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

extract() { awk -v n="$1" '
  $0 ~ "^[[:space:]]*# >>> " n "[[:space:]]*$" {inb=1; next}
  $0 ~ "^[[:space:]]*# <<< " n "[[:space:]]*$" {inb=0}
  inb' "$TOML"; }

# {{binding_prefix}} is substituted exactly as the materializer does it, and
# <bead> as the witness fills it from the row it is judging.
render() { printf '%s\n' "$1" | sed -e 's|{{binding_prefix}}|gc-toolkit.|g' -e 's|<bead>|tk-claim|g'; }

PROGRESS="$(extract no-progress-finding)"
BUG="$(extract bug-file)"
[ -n "$PROGRESS" ] && ok "no-progress-finding block extracted" || bad "no-progress-finding block EMPTY — markers missing from $TOML"
[ -n "$BUG" ] && ok "bug-file block extracted" || bad "bug-file block EMPTY — markers missing from $TOML"

echo "# neither block writes an address of its own"
# Inside a block, {{binding_prefix}} belongs in exactly three places: the
# binding a block asks gc for the pack's scripts under, an argument to the
# resolver, and a diagnostic naming what failed to resolve. Anywhere else it is
# a rendered address on its way to a stamp.
PACK_CALL="\$(b='{{binding_prefix}}'; gc \"\${b%.}\" scripts-dir)"
unpack() { awk -v c="$PACK_CALL" '{ while ((i = index($0, c)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(c)); print }'; }
stray() { printf '%s\n' "$1" | unpack | grep -n '{{binding_prefix}}' \
  | grep -v 'resolve-route.sh' | grep -vE '^[0-9]+: *echo ' || true; }
has "$PROGRESS" "$PACK_CALL/seat-progress.sh\" --bead <bead>" "no-progress-finding is one call to seat-progress.sh on the row's bead"
eq "$(stray "$PROGRESS")" "" "no-progress-finding renders no address"
hasnt "$PROGRESS" 'resolve-route.sh' "no-progress-finding asks the resolver for no agent"
hasnt "$PROGRESS" 'gc.routed_to' "no-progress-finding stamps no route"
# A pack defect is held for placement, so the bug block names no pool at all:
# routing it is the placement sitting's move.
hasnt "$BUG" '{{binding_prefix}}' "bug-file renders no address"
hasnt "$BUG" 'gc.routed_to' "bug-file stamps no route"
hasnt "$BUG" 'resolve-route.sh' "bug-file asks the resolver for no pool"

echo "# no step anywhere in the formula builds an address it does not resolve"
# The same rule holds for every step, the stamps above and the refinery queue
# read alike: a query by an address no agent holds returns a valid empty array.
# Outside the pack lookup, the resolver and a diagnostic, the token appears only
# where a pour forwards the variable to the next patrol wisp.
FORMULA_STRAY=$(unpack < "$TOML" | grep -n '{{binding_prefix}}' \
  | sed "s/--var binding_prefix='{{binding_prefix}}'//g" \
  | grep '{{binding_prefix}}' | grep -v 'resolve-route.sh' | grep -vE '^[0-9]+: *echo ' || true)
eq "$FORMULA_STRAY" "" "every {{binding_prefix}} in the formula is resolved, a diagnostic, or forwarded to the next pour"

# The pack gc names for `gc gc-toolkit scripts-dir`: the real seat-progress.sh
# and the library it sources, beside a patrol-finding.sh that records the
# filing one argument per line.
RIGROOT="$TMP/rig"; mkdir -p "$RIGROOT/assets/scripts"
cp "$ROOT/assets/scripts/seat-progress.sh" "$ROOT/assets/scripts/bd-lib.sh" "$RIGROOT/assets/scripts/"
chmod +x "$RIGROOT/assets/scripts/seat-progress.sh"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$RIGROOT/assets/scripts/patrol-finding.sh" <<'STUB'
for a in "$@"; do printf '%s\n' "$a"; done >> "${STUB_FINDING_LOG:?}"
echo "patrol-finding: filed tk-find for the stub"
STUB
chmod +x "$RIGROOT/assets/scripts/patrol-finding.sh"

BIN="$TMP/bin"; mkdir -p "$BIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-} ${2:-}" = "bd --db" ]; then
  [ "${3:-}" = "${STUB_CITY_DB:?}" ] || { echo "unexpected store: ${3:-}" >&2; exit 99; }
  case "${4:-}" in
    show) printf '%s\n' "${STUB_SESSION_BEAD:?}" ;;
    sql)  printf '%s\n' '[{"newest":null}]' ;;
    *) echo "unexpected gc invocation: $*" >&2; exit 99 ;;
  esac
  exit 0
fi
case "${1:-} ${2:-}" in
  "gc-toolkit scripts-dir")
    [ -n "${STUB_PACK:-}" ] || exit 1
    printf '%s/assets/scripts\n' "$STUB_PACK" ;;
  "agent list") printf '%s\n' "${STUB_AGENTS:-}" ;;
  "session list") printf '%s\n' "${STUB_SESSIONS:?}" ;;
  "bd show") printf '%s\n' "${STUB_CLAIM:?}" ;;
  "bd sql") printf '%s\n' "${STUB_RIG_NEWEST:?}" ;;
  "bd create")
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo "gc: bd create failed" >&2; exit 1; }
    printf '%s\n' "${STUB_CREATE:-{\"id\":\"tk-new\"}}" ;;
  "bd update") : ;;
  *) echo "unexpected gc invocation: $*" >&2; exit 99 ;;
esac
STUB
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/git" <<'STUB'
exit 1
STUB
chmod +x "$BIN/gc" "$BIN/git"
export PATH="$BIN:$PATH"
unset GC_PATROL_FINDING_TOOL GC_BD_LIB BEADS_DIR
export STUB_PACK="$RIGROOT" GC_RIG_ROOT="" GC_RIG=gc-toolkit
export GC_CITY_PATH="$TMP/city" STUB_CITY_DB="$TMP/city/.beads"
export STUB_GC_LOG="$TMP/gc.log" STUB_FINDING_LOG="$TMP/finding.log"

# A polecat's claim, its pane printing now, its session a pool seat that woke
# five hours ago, and its newest write four hours old.
NOW=$(date +%s)
# The fixture's values are exported once, so each case assigns them plainly.
export STUB_CLAIM STUB_SESSIONS STUB_SESSION_BEAD STUB_RIG_NEWEST
ago() { jq -rn --argjson s "$(( NOW - $1 ))" '$s | todate'; }
STUB_CLAIM='[{"id":"tk-claim","status":"in_progress","assignee":"hq-wisp-seat1","metadata":{"gc.session_id":"hq-wisp-seat1"}}]'
STUB_SESSIONS="{\"sessions\":[{\"id\":\"hq-wisp-seat1\",\"agent_name\":\"gc-toolkit/gc-toolkit.polecat-1\",\"state\":\"active\",\"last_active\":\"$(ago 5)\",\"created_at\":\"$(ago 21600)\"}]}"
STUB_SESSION_BEAD="[{\"id\":\"hq-wisp-seat1\",\"metadata\":{\"pool_managed\":\"true\",\"last_woke_at\":\"$(ago 18000)\"}}]"
STUB_RIG_NEWEST="[{\"newest\":\"$(ago 14400)\"}]"

# run <rendered-block-file> <prelude> -> transcript in OUT, gc calls in LOG,
# the finding's arguments in FILED
run() {
  : > "$STUB_GC_LOG"; : > "$STUB_FINDING_LOG"
  OUT=$( { printf '%s\n' "$2"; cat "$1"; } | bash 2>&1 ); RC=$?
  LOG=$(cat "$STUB_GC_LOG"); FILED=$(cat "$STUB_FINDING_LOG")
}
arg() { printf '%s\n' "$FILED" | awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }'; }
render "$PROGRESS" > "$TMP/progress.sh"
render "$BUG" > "$TMP/bug.sh"
bash -n "$TMP/progress.sh" && ok "rendered no-progress-finding is valid bash" || bad "no-progress-finding failed bash -n"
bash -n "$TMP/bug.sh" && ok "rendered bug-file is valid bash" || bad "bug-file failed bash -n"

echo "# no-progress-finding: a printing pool seat with no write for four hours"
run "$TMP/progress.sh" ""
eq "$RC" 0 "the block exits 0"
has "$LOG" 'gc-toolkit scripts-dir' "it finds seat-progress.sh through the pack lookup"
eq "$(arg --key)" "no-progress.hq-wisp-seat1" "the finding is keyed on the seat's session"
eq "$(arg --about)" "tk-claim" "and is about the bead the row named"
eq "$(arg --scope)" "witness-findings" "among the witness's findings"
hasnt "$FILED" 'routed_to' "the finding carries no route"
hasnt "$FILED" 'dog' "and addresses no dog"
hasnt "$LOG" 'agent list' "so no roster is read for an address"
hasnt "$LOG" 'session kill' "and the seat is not killed"
has "$OUT" "reported hq-wisp-seat1" "and the step's line says what it judged"

echo "# no-progress-finding: the same seat with a write ten minutes ago"
STUB_RIG_NEWEST="[{\"newest\":\"$(ago 600)\"}]"
run "$TMP/progress.sh" ""
eq "$FILED" "" "a seat that wrote recently gets no finding"
has "$OUT" "spared hq-wisp-seat1" "and the line says it was spared"
eq "$RC" 0 "and the step keeps running"

BUG_PRELUDE='TITLE="submit-and-exit strands pushed work"; BODY="the branch-shape gate re-runs against a detached HEAD"'

echo "# bug-file: a reported pack defect waits for the operator's placement"
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]}'
run "$TMP/bug.sh" "$BUG_PRELUDE"
has "$LOG" 'bd create' "a reported pack defect is filed as a bug"
has "$LOG" '-t bug' "typed as one"
has "$LOG" '--labels hold:mayor' "held with hold:mayor, so the placement sitting's queue lists it"
hasnt "$LOG" 'placement' "with no placement marker"
hasnt "$LOG" 'gc.routed_to' "and routed to no pool: new work reaches one only once it is placed"
hasnt "$LOG" 'agent list' "so no roster is read for an address it never stamps"
has "$OUT" "waits for placement" "and the step says where it went"

# The hold is a field of the create, not a write that follows it: a bug that
# exists before it is held is an open, unrouted bead in no queue, and a write
# that fails leaves it that way.
hasnt "$LOG" 'bd update' "the hold is not a second write that can fail behind a success message"
hasnt "$LOG" 'set-state' "…nor a set-state after the create"

echo "# a city with no live polecat pool still files the bug"
export STUB_AGENTS='{"agents":[]}'
run "$TMP/bug.sh" "$BUG_PRELUDE"
has "$LOG" '--labels hold:mayor' "holding for placement needs no pool to exist"
eq "$RC" 0 "and the step keeps running"

echo "# a create that returns no id is reported, and what it may have filed is held"
export STUB_CREATE='{}'
run "$TMP/bug.sh" "$BUG_PRELUDE"
has "$OUT" "reported no id" "the failure is reported"
has "$OUT" "gc beads list --label hold:mayor" "and names where to look before filing again"
has "$LOG" '--labels hold:mayor' "and the one call that was made already carried the hold"
unset STUB_CREATE

echo "# a create that fails outright files nothing and says so"
export STUB_CREATE_FAIL=1
run "$TMP/bug.sh" "$BUG_PRELUDE"
has "$OUT" "reported no id" "the failure is reported"
eq "$RC" 0 "and the step keeps running"
unset STUB_CREATE_FAIL

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
