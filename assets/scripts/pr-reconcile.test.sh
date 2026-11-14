#!/usr/bin/env bash
# Hermetic test for pr-reconcile.sh, the landing order's script, and the order
# that runs it (orders/pr-reconcile.toml).
#
# The script runs in a scratch copy beside the real gctk-resolve.sh and a stub
# resolve-route.sh, with GCTK_BIN naming a stub gctk that records its arguments
# and the scripts directory it was handed. The invariants:
#   (a) the run acts for the refinery the roster names in the rig: it execs
#       `gctk pr reconcile --refinery <that identity>`, the order's own flags
#       passed through, with the scripts directory exported;
#   (b) a roster that does not read runs nothing, exit 2, because a run that
#       cannot name the refinery would read every marked bead as released;
#   (c) a rig whose roster names no refinery runs nothing and exits 0;
#   (d) the order is a rig-scoped cooldown exec order that runs this script,
#       with a timeout above the run's four-minute budget.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-reconcile-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (got '$1', wanted substring '$2')" ;; esac; }

mkdir -p "$TMP/scripts"
cp "$HERE/pr-reconcile.sh" "$HERE/gctk-resolve.sh" "$TMP/scripts/"
cat > "$TMP/scripts/resolve-route.sh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = refinery ] || { echo "stub resolve-route: asked for $1" >&2; exit 2; }
case "${STUB_ROUTE_RC:-0}" in
  0) echo "${GC_RIG:-rig}/gc-toolkit.refinery" ;;
  3) echo refinery; exit 3 ;;
  *) exit "$STUB_ROUTE_RC" ;;
esac
STUB
cat > "$TMP/gctk" <<'STUB'
#!/usr/bin/env bash
{ printf '%s\n' "$*"; printf 'scripts=%s\n' "${GCTK_SCRIPTS_DIR:-}"; } > "$GCTK_LOG"
STUB
chmod +x "$TMP/scripts/"*.sh "$TMP/gctk"
export GCTK_BIN="$TMP/gctk" GCTK_LOG="$TMP/gctk.log" GC_RIG=alpha

run() { rm -f "$GCTK_LOG"; OUT=$("$TMP/scripts/pr-reconcile.sh" "$@" 2>&1); RC=$?; }

echo "# (a) the run acts for the rig's refinery"
run --count 5
eq "$RC" 0 "the run exits as gctk does"
eq "$(sed -n 1p "$GCTK_LOG" 2>/dev/null)" "pr reconcile --refinery alpha/gc-toolkit.refinery --count 5" \
   "gctk pr reconcile runs for the refinery the roster names, with the order's flags"
eq "$(sed -n 2p "$GCTK_LOG" 2>/dev/null)" "scripts=$TMP/scripts" "the run is handed the scripts directory"

echo "# (b) a roster that does not read runs nothing"
STUB_ROUTE_RC=3 run
eq "$RC" 2 "an unreadable roster exits 2"
[ ! -e "$GCTK_LOG" ] && ok "and runs no gctk" || bad "and runs no gctk"
has "$OUT" "cannot tell the refinery's beads from released ones" "it says why"

echo "# (c) a rig with no refinery runs nothing"
STUB_ROUTE_RC=1 run
eq "$RC" 0 "no refinery in the rig exits 0"
[ ! -e "$GCTK_LOG" ] && ok "and runs no gctk" || bad "and runs no gctk"

echo "# (d) the order"
ORDER="$ROOT/orders/pr-reconcile.toml"
field() { sed -n "s/^$1 = \"\\(.*\\)\"$/\\1/p" "$ORDER"; }
eq "$(field trigger)" cooldown "the order runs on a cooldown"
eq "$(field scope)" rig "the order is rig-scoped"
eq "$(field exec)" '$PACK_DIR/assets/scripts/pr-reconcile.sh' "the order runs this script"
eq "$(field timeout)" 300s "the order's timeout is 300 seconds"
BUDGET=$(sed -n 's/^[[:space:]]*defaultRunBudget = \([0-9]*\) \* time.Minute$/\1/p' "$ROOT/services/gctk/internal/cli/prland.go")
[ -n "$BUDGET" ] && [ $((BUDGET * 60)) -lt 300 ] && ok "the run's budget, ${BUDGET}m, ends inside the timeout" \
  || bad "the run's budget '${BUDGET}' does not read, or does not end inside the 300-second timeout"
if grep -q '^trigger = "webhook"\|^on = ' "$ORDER"; then bad "no webhook fires the order"; else ok "no webhook fires the order"; fi

echo
echo "pr-reconcile: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
