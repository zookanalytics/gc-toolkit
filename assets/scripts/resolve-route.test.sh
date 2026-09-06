#!/usr/bin/env bash
# Hermetic test for assets/scripts/resolve-route.sh — the address a route or an
# assignee is stamped with, resolved against the live agent set.
#
# The fixture roster carries the shape that makes hand-written addresses wrong
# in opposite directions: a city-scoped dog whose identity has no rig segment,
# rig-scoped pools under three rigs that all share one bare name, and a second
# city binding so a bare role is genuinely ambiguous. Stubbed gc; no live city,
# Dolt or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/resolve-route.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-resolve-route-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = "agent" ] && [ "${2:-}" = "list" ]; then
  [ -n "${STUB_AGENTS_FAIL:-}" ] && { echo "gc: agent list unavailable" >&2; exit 1; }
  printf '%s\n' "${STUB_AGENTS:-}"
  exit 0
fi
echo "unexpected gc invocation: $*" >&2
exit 99
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"

export STUB_AGENTS='{"agents":[
  {"qualified_name":"bd.dog"},
  {"qualified_name":"gc-toolkit.dog"},
  {"qualified_name":"gc-toolkit.deacon"},
  {"qualified_name":"gc-toolkit/gc-toolkit.polecat"},
  {"qualified_name":"gc-toolkit/gc-toolkit.refinery"},
  {"qualified_name":"gc-toolkit/gc-toolkit.witness"},
  {"qualified_name":"gascity/gc-toolkit.polecat"},
  {"qualified_name":"shutupandlisten/gc-toolkit.polecat"}]}'

# run <name> [env-assignments...] -> stdout in OUT, stderr in ERR, status in RC
run() {
  local name="$1"; shift
  OUT=$(env GC_RIG=gc-toolkit "$@" "$SUT" "$name" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}

echo "# an identity that is already live resolves to itself"
run "gc-toolkit/gc-toolkit.polecat"
eq "$RC" 0 "a rig-scoped identity is accepted"
eq "$OUT" "gc-toolkit/gc-toolkit.polecat" "and comes back byte-identical"
run "gc-toolkit.dog"
eq "$RC" 0 "a city-scoped identity is accepted"
eq "$OUT" "gc-toolkit.dog" "and comes back byte-identical"

echo "# the over-qualified direction: a rig segment the city-scoped dog does not carry"
run "gc-toolkit/gc-toolkit.dog"
eq "$RC" 0 "an invented rig segment resolves rather than refusing"
eq "$OUT" "gc-toolkit.dog" "to the bare identity the dog actually holds"

echo "# the under-qualified direction: the rig segment a rig-scoped pool needs"
run "gc-toolkit.polecat"
eq "$RC" 0 "the bare form of a rig-scoped pool resolves"
eq "$OUT" "gc-toolkit/gc-toolkit.polecat" "to this rig's pool, not another rig's"

echo "# a bare role resolves when the store leaves exactly one candidate"
run "refinery"
eq "$RC" 0 "a role names one reachable identity"
eq "$OUT" "gc-toolkit/gc-toolkit.refinery" "and qualifies itself"

echo "# GC_RIG is what makes the bare pool name unambiguous"
OUT=$(env -u GC_RIG "$SUT" "gc-toolkit.polecat" 2>"$TMP/err"); RC=$?
ERR=$(cat "$TMP/err")
eq "$RC" 1 "with no rig bound, three rigs' pools share the name and none wins"
eq "$OUT" "" "nothing is printed for a caller to stamp"
has "$ERR" "gascity/gc-toolkit.polecat" "the refusal names the candidates"
has "$ERR" "shutupandlisten/gc-toolkit.polecat" "all of them"

echo "# two city bindings make a bare role ambiguous, and a guess is refused"
run "dog"
eq "$RC" 1 "'dog' resolves to two live identities"
eq "$OUT" "" "so nothing is stamped"
has "$ERR" "bd.dog, gc-toolkit.dog" "and both are named"

echo "# an identity live only under another rig is a refusal, not a resolution"
run "gascity/gc-toolkit.polecat"
eq "$RC" 1 "a cross-rig identity never reads this store"
eq "$OUT" "" "so it is not handed back to be stamped"
has "$ERR" "GC_RIG=gc-toolkit selects the store" "and the refusal says why"

echo "# a name no agent carries"
run "gc-toolkit.gremlin"
eq "$RC" 1 "an unknown name refuses"
eq "$OUT" "" "with nothing on stdout"
has "$ERR" "matches no live agent identity" "and says so"

echo "# the operator marker is held by its reader, not a name that failed to resolve"
run "human"
eq "$RC" 0 "'human' is accepted"
eq "$OUT" "human" "unchanged"
run "human" STUB_AGENTS_FAIL=1
eq "$RC" 0 "no agent carries it, so an unreadable roster cannot unsettle it"
eq "$OUT" "human" "and it still resolves to itself"

echo "# an unreadable roster is the absence of proof, not proof of an empty city"
run "gc-toolkit.polecat" STUB_AGENTS_FAIL=1
eq "$RC" 3 "a failed roster read is its own exit status"
eq "$OUT" "gc-toolkit.polecat" "the name comes back unchanged for the caller to decide on"
has "$ERR" "UNVERIFIED" "and is marked unproven"
run "gc-toolkit.polecat" STUB_AGENTS='{"agents":[]}'
eq "$RC" 3 "an empty roster reads the same way"
eq "$OUT" "gc-toolkit.polecat" "rather than condemning every address in the city"

echo "# a raw control byte in the roster costs the payload nothing"
run "gc-toolkit.polecat" \
  STUB_AGENTS="$(printf '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.polecat","note":"a\002b"}]}')"
eq "$RC" 0 "the roster still parses"
eq "$OUT" "gc-toolkit/gc-toolkit.polecat" "and the name resolves"

echo "# the capture idiom the usage text prescribes, and the formula blocks use"
ROUTE=$(env GC_RIG=gc-toolkit STUB_AGENTS_FAIL=1 "$SUT" "gc-toolkit.polecat" 2>/dev/null) || true
eq "$ROUTE" "gc-toolkit.polecat" "'|| true' keeps the unverified name for the caller to decide on"
ROUTE=$(env GC_RIG=gc-toolkit "$SUT" "gc-toolkit.gremlin" 2>/dev/null) || true
eq "$ROUTE" "" "and leaves the variable empty when the name was refused"

echo "# usage"
OUT=$("$SUT" 2>/dev/null); eq "$?" 2 "no argument is a usage error"
OUT=$("$SUT" a b 2>/dev/null); eq "$?" 2 "a second argument is a usage error"
OUT=$("$SUT" --help 2>/dev/null); eq "$?" 2 "--help prints usage"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
