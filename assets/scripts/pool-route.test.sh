#!/usr/bin/env bash
# Hermetic test for assets/scripts/pool-route.sh — the shared answer to "does
# this pool name address anybody". Stubbed gc; no live city or network.
# The load-bearing property is not the happy path but the two silences it
# replaces: a bare name that matches no identity, and a live identity in a rig
# whose store the caller never writes to. Both must refuse with an EMPTY
# stdout, because every caller assigns the result and a diagnostic captured as
# a route is the same mute one stamp later.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/pool-route.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { if grep -qF -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = "agent" ] && [ "${2:-}" = "list" ]; then
  [ -n "${STUB_AGENTS_FAIL:-}" ] && { echo "gc: agent list unavailable" >&2; exit 1; }
  printf '%s\n' "${STUB_AGENTS:-}"
  exit 0
fi
exit 0
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"

# converse exists ONLY rig-scoped; deacon exists ONLY city-scoped. That split
# is the whole subject: neither name is routable at both scopes, and the
# conditional-prefix form the copies used to carry cannot tell them apart.
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse"},
  {"qualified_name":"signal-loom/gc-toolkit.converse"},
  {"qualified_name":"gc-toolkit/gc-toolkit.polecat"},
  {"qualified_name":"gc-toolkit.deacon"}]}'
unset STUB_AGENTS_FAIL 2>/dev/null || true

run() { # <route-or-flag>... -> stdout in OUT, stderr in ERR, status in RC
    OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
}

echo "# a rig-bound caller qualifies the bare pool name"
GC_RIG=gc-toolkit run gc-toolkit.converse
eq "$RC" 0 "exit 0"
eq "$OUT" "gc-toolkit/gc-toolkit.converse" "the route carries the caller's rig"
eq "$ERR" "" "and says nothing on the happy path"

echo "# a rig-less caller's bare name is refused, not returned"
# The defect this script replaces: ${GC_RIG:+\$GC_RIG/}<pool> renders bare when
# GC_RIG is unset, and the offer read is exact byte equality, so the stamp is
# clean and the bead is claimed by nobody, forever.
env -u GC_RIG "$SUT" gc-toolkit.converse >"$TMP/out" 2>"$TMP/err"; RC=$?
eq "$RC" 1 "exit 1"
eq "$(cat "$TMP/out")" "" "stdout is EMPTY — a caller assigning it captures no route"
has "$(cat "$TMP/err")" "matches no live agent identity" "says the name addresses nobody"
has "$(cat "$TMP/err")" "gc-toolkit/gc-toolkit.converse, signal-loom/gc-toolkit.converse" \
    "and names the live rig-qualified forms the caller could have meant"

echo "# a bare name that IS a live identity is returned bare"
# City-scoped agents carry unqualified identities, so 'bare' is not itself the
# defect — being unmatched is. A blanket "qualify everything" rule would refuse
# the deacon, who is only ever addressed this way.
env -u GC_RIG "$SUT" gc-toolkit.deacon >"$TMP/out" 2>"$TMP/err"; RC=$?
eq "$RC" 0 "exit 0"
eq "$(cat "$TMP/out")" "gc-toolkit.deacon" "the city identity survives unqualified"

echo "# an explicitly qualified name is taken as given"
GC_RIG=gc-toolkit run gc-toolkit/gc-toolkit.polecat
eq "$RC" 0 "exit 0"
eq "$OUT" "gc-toolkit/gc-toolkit.polecat" "no second qualifier is prepended"

echo "# a live pool in another rig is refused: well-formed is not reachable"
# GC_RIG picks the store the caller's bead lands in as well as the route, so an
# identity from another rig never lists the store it would have to read.
GC_RIG=gc-toolkit run signal-loom/gc-toolkit.converse
eq "$RC" 1 "exit 1"
eq "$OUT" "" "stdout is EMPTY"
has "$ERR" "which that pool never reads" "says the store and the route disagree"

echo "# only PROOF refuses: an unreadable agent set returns the route, loudly"
STUB_AGENTS_FAIL=1 GC_RIG=gc-toolkit run gc-toolkit.converse
eq "$RC" 0 "exit 0"
eq "$OUT" "gc-toolkit/gc-toolkit.converse" "the route is still returned"
has "$ERR" "UNVERIFIED" "and says it was never verified"

echo "# a control byte in the agent set does not silently mute the check"
# A raw C0 byte anywhere in the payload aborts jq on the WHOLE document, which
# reads as an empty identity set — the fail-open arm above. The scrub is what
# keeps the refusal reachable; without it this case returns the dead route.
STUB_AGENTS="$(printf '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse","work_query":"a\002b"}]}')" \
  env -u GC_RIG "$SUT" gc-toolkit.converse >"$TMP/out" 2>"$TMP/err"; RC=$?
eq "$RC" 1 "exit 1"
has "$(cat "$TMP/err")" "matches no live agent identity" "the route was actually checked, not skipped"

echo "# --verdict reads a route the caller did not write"
verdict() { GC_RIG="${2-gc-toolkit}" "$SUT" --verdict "$1" 2>/dev/null; }
eq "$(verdict gc-toolkit/gc-toolkit.converse)" "ok" "a live identity reads ok"
eq "$(verdict gc-toolkit.converse)" "no-identity" "the bare form reads no-identity"
eq "$(verdict signal-loom/gc-toolkit.converse)" "cross-rig" "another rig's pool reads cross-rig"
eq "$(verdict '')" "no-identity" "an empty route reads no-identity"
# The operator marker is a held route, not a pool name that failed to resolve;
# reading it as dead is how an operator-owned item gets handed back to a pool.
eq "$(verdict human)" "ok" "the human sentinel reads ok"
eq "$(STUB_AGENTS_FAIL=1 verdict gc-toolkit/gc-toolkit.converse)" "unknown" "an unreadable set reads unknown"
GC_RIG=gc-toolkit "$SUT" --verdict gc-toolkit.converse >/dev/null 2>&1
eq "$?" 0 "--verdict exits 0 even for a dead route — it reads, it does not judge"

echo "# usage"
"$SUT" >/dev/null 2>&1; eq "$?" 2 "no argument is a usage error"
"$SUT" a b >/dev/null 2>&1; eq "$?" 2 "two pool names is a usage error"
"$SUT" --verdict >/dev/null 2>&1; eq "$?" 2 "--verdict with no route is a usage error"
"$SUT" --nope x >/dev/null 2>&1; eq "$?" 2 "an unknown flag is a usage error"

echo
echo "pool-route.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
