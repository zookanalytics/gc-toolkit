#!/usr/bin/env bash
# Hermetic test for the two witness-patrol blocks that stamp an address:
# warrant-file (the dog pool) and bug-dispatch (the polecat pool).
#
# The witness files to agents at two different scopes, and the qualifier one
# needs is exactly the qualifier the other must not carry. Both blocks are run
# here against the real resolve-route.sh over a roster where the rendered
# `{{binding_prefix}}<role>` form is WRONG, so a block that stamped what the
# template rendered would file an address nothing claims and still exit clean.
# Stubbed gc and git; no live city, Dolt or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
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

# {{binding_prefix}} is substituted exactly as the materializer does it.
render() { printf '%s\n' "$1" | sed 's|{{binding_prefix}}|gc-toolkit.|g'; }

WARRANT="$(extract warrant-file)"
BUG="$(extract bug-dispatch)"
[ -n "$WARRANT" ] && ok "warrant-file block extracted" || bad "warrant-file block EMPTY — markers missing from $TOML"
[ -n "$BUG" ] && ok "bug-dispatch block extracted" || bad "bug-dispatch block EMPTY — markers missing from $TOML"

echo "# neither block writes an address of its own"
# Inside a block, {{binding_prefix}} belongs in exactly two places: an argument
# to the resolver, and a diagnostic naming what failed to resolve. Anywhere
# else it is a rendered address on its way to a stamp.
stray() { printf '%s\n' "$1" | grep -n '{{binding_prefix}}' \
  | grep -v 'resolve-route.sh' | grep -vE '^[0-9]+: *echo ' || true; }
for pair in "warrant-file:$WARRANT" "bug-dispatch:$BUG"; do
  name="${pair%%:*}"; body="${pair#*:}"
  has "$body" 'resolve-route.sh' "$name resolves its address"
  eq "$(stray "$body")" "" "$name renders no address it does not resolve"
done

# The rig root the blocks probe first, holding a copy of the real resolver so
# $SCRIPTS resolution is exercised without reaching the live tree.
RIGROOT="$TMP/rig"; mkdir -p "$RIGROOT/assets/scripts"
cp "$ROOT/assets/scripts/resolve-route.sh" "$RIGROOT/assets/scripts/"
chmod +x "$RIGROOT/assets/scripts/resolve-route.sh"

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
case "${1:-} ${2:-}" in
  "agent list")
    [ -n "${STUB_AGENTS_FAIL:-}" ] && { echo "gc: agent list unavailable" >&2; exit 1; }
    printf '%s\n' "${STUB_AGENTS:-}" ;;
  "bd list")   printf '%s\n' "${STUB_OPEN:-[]}" ;;
  "bd create")
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo "gc: bd create failed" >&2; exit 1; }
    printf '%s\n' "${STUB_CREATE:-{\"id\":\"tk-new\"}}" ;;
  "bd update") : ;;
  *) echo "unexpected gc invocation: $*" >&2; exit 99 ;;
esac
STUB
cat > "$BIN/git" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$BIN/gc" "$BIN/git"
export PATH="$BIN:$PATH"
export GC_RIG_ROOT="$RIGROOT" GC_RIG=gc-toolkit
export STUB_GC_LOG="$TMP/gc.log"

# run <rendered-block-file> <prelude> -> transcript in OUT, gc calls in LOG
run() {
  : > "$STUB_GC_LOG"
  OUT=$( { printf '%s\n' "$2"; cat "$1"; } | bash 2>&1 ); RC=$?
  LOG=$(cat "$STUB_GC_LOG")
}
render "$WARRANT" > "$TMP/warrant.sh"
render "$BUG" > "$TMP/bug.sh"
bash -n "$TMP/warrant.sh" && ok "rendered warrant-file is valid bash" || bad "warrant-file failed bash -n"
bash -n "$TMP/bug.sh" && ok "rendered bug-dispatch is valid bash" || bad "bug-dispatch failed bash -n"

WARRANT_PRELUDE='TARGET=gc-toolkit--gc-toolkit__converse-2-pool; REASON="No progress on tk-a for 6h"'
BUG_PRELUDE='TITLE="submit-and-exit strands pushed work"; BODY="the branch-shape gate re-runs against a detached HEAD"'

echo "# the dog is city-scoped here: the bare identity the template renders is the live one"
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit.dog"},
  {"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]}'
export STUB_OPEN='[]'
run "$TMP/warrant.sh" "$WARRANT_PRELUDE"
has "$LOG" 'bd create' "a wedged session with no open warrant files one"
has "$LOG" '"gc.routed_to":"gc-toolkit.dog"' "routed at the city-scoped dog, unqualified"
has "$LOG" '"warrant.target":"gc-toolkit--gc-toolkit__converse-2-pool"' "carrying the dedup key"
has "$LOG" '"warrant.reason":"No progress on tk-a for 6h"' "and the reason as given"

echo "# the same block, a city whose dog is rig-scoped: the rendered form is now wrong"
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.dog"}]}'
run "$TMP/warrant.sh" "$WARRANT_PRELUDE"
has "$LOG" '"gc.routed_to":"gc-toolkit/gc-toolkit.dog"' "the warrant is routed at the identity that is live"
hasnt "$LOG" '"gc.routed_to":"gc-toolkit.dog"' "not at the one the template rendered"

echo "# a reason carrying a double quote cannot break the metadata payload"
run "$TMP/warrant.sh" 'TARGET=sess-1; REASON="bead \"tk-a\" stale 6h"'
has "$LOG" 'bd create' "the warrant is still filed"
printf '%s\n' "$LOG" | grep -F 'bd create' | sed 's/^.*--metadata //' | jq -e . >/dev/null 2>&1 \
  && ok "and its metadata is still parseable JSON" || bad "the metadata payload did not survive the quote"

echo "# no live dog: refuse rather than file an address nothing claims"
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]}'
run "$TMP/warrant.sh" "$WARRANT_PRELUDE"
hasnt "$LOG" 'bd create' "nothing is filed"
hasnt "$LOG" 'bd list' "and the dedup query is not even reached"
has "$OUT" "escalate instead of filing" "the step is told what to do instead"
eq "$RC" 0 "and the patrol step survives the refusal rather than aborting mid-sweep"

echo "# an open warrant for the same target still suppresses a second one"
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit.dog"}]}'
export STUB_OPEN='[{"id":"tk-old"}]'
run "$TMP/warrant.sh" "$WARRANT_PRELUDE"
hasnt "$LOG" 'bd create' "the dedup survives the resolver"
has "$OUT" "tk-old" "and names the warrant already open"
export STUB_OPEN='[]'

echo "# bug-dispatch: the polecat pool is rig-scoped, so the rendered bare form is wrong"
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit.dog"},
  {"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]}'
run "$TMP/bug.sh" "$BUG_PRELUDE"
has "$LOG" 'bd create' "a reported pack defect is filed as a bug"
has "$LOG" '-t bug' "typed as one"
has "$LOG" '"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"' \
  "and routed at the rig-qualified pool that is live"
hasnt "$LOG" '"gc.routed_to":"gc-toolkit.polecat"' "never the bare form the template rendered"
printf '%s\n' "$LOG" | grep -F 'bd create' | sed 's/^.*--metadata //;s/ --json.*$//' | jq -e . >/dev/null 2>&1 \
  && ok "the create metadata is parseable JSON" || bad "the metadata payload did not survive"

# The route is a field of the create, not a write that follows it: a bug that
# exists before it is routed is an open bead offered to nobody, and a route
# write that fails leaves it that way.
hasnt "$LOG" 'bd update' "the route is not a second write that can fail behind a success message"

echo "# a city whose polecat pool is city-scoped resolves the other way"
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit.polecat"}]}'
run "$TMP/bug.sh" "$BUG_PRELUDE"
has "$LOG" '"gc.routed_to":"gc-toolkit.polecat"' "the bare identity is stamped when it is the live one"

echo "# no live polecat pool: file nothing"
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit.dog"}]}'
run "$TMP/bug.sh" "$BUG_PRELUDE"
hasnt "$LOG" 'bd create' "an unroutable pool files no bug"
has "$OUT" "escalate instead of filing" "and says to escalate"
eq "$RC" 0 "and the step keeps running"

echo "# a create that returns no id is reported, and what it may have filed is routed"
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]}'
export STUB_CREATE='{}'
run "$TMP/bug.sh" "$BUG_PRELUDE"
has "$OUT" "reported no id" "the failure is reported"
has "$LOG" '"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"' \
  "and the one call that was made already carried the route"
unset STUB_CREATE

echo "# a create that fails outright files nothing and says so"
export STUB_CREATE_FAIL=1
run "$TMP/bug.sh" "$BUG_PRELUDE"
has "$OUT" "reported no id" "the failure is reported"
eq "$RC" 0 "and the step keeps running"
unset STUB_CREATE_FAIL

echo "# an unreadable roster files the work rather than muting the witness"
export STUB_AGENTS_FAIL=1
run "$TMP/warrant.sh" "$WARRANT_PRELUDE"
has "$LOG" '"gc.routed_to":"gc-toolkit.dog"' "the warrant goes out on the rendered address"
has "$OUT" "UNVERIFIED" "marked unproven"
run "$TMP/bug.sh" "$BUG_PRELUDE"
has "$LOG" '"gc.routed_to":"gc-toolkit.polecat"' "and so does the bug"
unset STUB_AGENTS_FAIL

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
