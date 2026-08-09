#!/usr/bin/env bash
# Hermetic test for doctor/check-rig-scoped-orders-bound (tk-gi2pc).
#
# THE BUG the check guards: order discovery scans a pack's orders/ twice — once
# at city scope and once per importing rig — and reads `scope` only on the rig
# pass. So an order declaring `scope = "rig"` with a BARE pool ALSO gets a
# registration with no rig bound. With no rig the bare pool cannot be
# qualified, the wisp lands in the city store routed to a name no pool can
# claim, and the order re-strands on every cooldown. mol-liveness-sweep and
# mol-triage-recurrence went dark that way with every config file correct.
#
# The check turns that into a doctor error. What is exercised here:
#   * the ERROR arm, judged from the listed entry's own source file (so it
#     generalizes past this pack's orders);
#   * the name-key FALLBACK when that source cannot be read;
#   * the three shapes that must NOT be flagged — rig-bound entries, an
#     explicit scope="city" order, and an order with no scope at all;
#   * the fail-CLOSED arms: an unreadable or malformed listing warns, it never
#     passes silently. That fail-open is the exact bug class the check exists
#     to remove, so a check that reported OK when it could not see would be
#     worse than no check.
#   * a POSITIVE CONTROL over the real shipped orders/, so a passing suite
#     cannot mean "the scope regex matches nothing anymore".
#
# No live city, Dolt, network, or orders — only jq, a stub `gc`, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECK="$ROOT/doctor/check-rig-scoped-orders-bound/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$CHECK" ] || chmod +x "$CHECK" 2>/dev/null

# --- Fixture pack: three order files, one per scope shape. -------------------
PACK="$TMP/pack"
mkdir -p "$PACK/orders"
cat > "$PACK/orders/sweep-rig.toml" <<'EOF'
[order]
description = "rig-scoped with a bare pool — the shape that strands when unbound"
formula = "mol-sweep"
trigger = "cooldown"
interval = "6h"
pool = "gc-toolkit.polecat"
scope = "rig"
EOF
cat > "$PACK/orders/patrol-city.toml" <<'EOF'
[order]
description = "city-scoped — an unbound registration is exactly what it asked for"
exec = "true"
trigger = "cooldown"
interval = "5m"
scope = "city"
EOF
cat > "$PACK/orders/legacy-noscope.toml" <<'EOF'
[order]
description = "no scope declared at all — unset is not a declaration"
exec = "true"
trigger = "cooldown"
interval = "5m"
EOF

# --- Stub gc: only `order list --json`, answering from ORDERS_JSON. ----------
# ORDERS_JSON names a file so a scenario can hand over malformed bytes; an
# unset STUB_RC means the probe succeeded.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "order list")
      rc="${STUB_RC:-0}"
      [ "$rc" -eq 0 ] || exit "$rc"
      cat "$ORDERS_JSON"
      ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# entry <name> <rig> <source>
entry() { printf '{"name":"%s","rig":"%s","source":"%s","enabled":true}' "$1" "$2" "$3"; }
listing() { # each arg is one entry object
    local IFS=,
    printf '{"schema_version":"1","ok":true,"orders":[%s]}' "$*"
}
run_check() { # $1=orders json file ; echoes output, sets RC
    ORDERS_JSON="$1" GC_PACK_DIR="$PACK" bash "$CHECK" 2>&1
}

# --- 0. Positive control -----------------------------------------------------
# Prove the fixture is real before trusting any verdict computed from it: a
# malformed listing would make every "no findings" case below pass for the
# wrong reason.
listing "$(entry sweep-rig "" "$PACK/orders/sweep-rig.toml")" > "$TMP/control.json"
eq "$(jq -r '.orders | length' "$TMP/control.json" 2>/dev/null)" "1" \
   "positive control: fixture listing parses and holds one entry"
eq "$(jq -r '.orders[0].name' "$TMP/control.json" 2>/dev/null)" "sweep-rig" \
   "positive control: the entry is the one the scenarios name"
if grep -qE '^scope[[:space:]]*=[[:space:]]*"rig"' "$PACK/orders/sweep-rig.toml"; then
    ok "positive control: the fixture order file really declares scope = \"rig\""
else
    bad "positive control: fixture order file lost its scope declaration"
fi

# --- 1. ERROR: rig-scoped order registered with no rig ----------------------
OUT=$(run_check "$TMP/control.json"); RC=$?
eq "$RC" "2" "unbound scope=rig order is an ERROR"
has "$OUT" "sweep-rig" "the error names the offending order"
has "$OUT" "NO rig bound" "the error says what is wrong"

# --- 2. OK: the same order, only rig-bound ----------------------------------
listing "$(entry sweep-rig alpha "$PACK/orders/sweep-rig.toml")" \
        "$(entry sweep-rig beta  "$PACK/orders/sweep-rig.toml")" > "$TMP/bound.json"
OUT=$(run_check "$TMP/bound.json"); RC=$?
eq "$RC" "0" "rig-bound registrations only is OK"
has "$OUT" "OK:" "the pass message is the OK line"

# --- 3. OK: an unbound city-scoped order is not a finding -------------------
listing "$(entry patrol-city "" "$PACK/orders/patrol-city.toml")" > "$TMP/city.json"
OUT=$(run_check "$TMP/city.json"); RC=$?
eq "$RC" "0" "unbound scope=city order is not flagged"
hasnt "$OUT" "patrol-city" "the city-scoped order is not named as a finding"

# --- 4. OK: no scope declared is not a declaration --------------------------
# The loader DEFAULTS an absent scope to "rig", but this check flags explicit
# declarations only: erroring on every order that never considered scope would
# bury the real signal under the city's whole builtin order set.
listing "$(entry legacy-noscope "" "$PACK/orders/legacy-noscope.toml")" > "$TMP/noscope.json"
OUT=$(run_check "$TMP/noscope.json"); RC=$?
eq "$RC" "0" "unbound order with no scope declaration is not flagged"

# --- 5. ERROR via the name-key fallback -------------------------------------
# Source unreadable, but the name matches an order THIS pack ships as
# scope="rig" — we know what our own file declares without reading the copy.
listing "$(entry sweep-rig "" "$TMP/does-not-exist.toml")" > "$TMP/gone.json"
OUT=$(run_check "$TMP/gone.json"); RC=$?
eq "$RC" "2" "unreadable source + pack's own rig-scoped name is an ERROR"
has "$OUT" "unreadable" "the fallback says why it judged without the source"

# --- 6. OK-with-note: unreadable source, not this pack's order --------------
listing "$(entry someone-elses "" "$TMP/does-not-exist.toml")" > "$TMP/foreign.json"
OUT=$(run_check "$TMP/foreign.json"); RC=$?
eq "$RC" "0" "unreadable source for a foreign order does not fail the check"
has "$OUT" "someone-elses" "the unjudgeable entry is still reported in the details"

# --- 7. Fail-CLOSED: the probe could not be read ----------------------------
OUT=$(ORDERS_JSON="$TMP/control.json" STUB_RC=1 GC_PACK_DIR="$PACK" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "a failed \`gc order list\` warns (it must not report OK)"
has "$OUT" "cannot determine" "the warning says the answer is unknown, not clean"

printf 'not json at all' > "$TMP/garbage.json"
OUT=$(run_check "$TMP/garbage.json"); RC=$?
eq "$RC" "1" "a malformed listing warns"

printf '{"schema_version":"1","ok":true}' > "$TMP/noorders.json"
OUT=$(run_check "$TMP/noorders.json"); RC=$?
eq "$RC" "1" "a listing with no .orders array warns"

: > "$TMP/empty.json"
OUT=$(run_check "$TMP/empty.json"); RC=$?
eq "$RC" "1" "an empty listing warns"

# --- 8. An empty order set is a clean pass, not a crash ---------------------
listing > "$TMP/none.json"
OUT=$(run_check "$TMP/none.json"); RC=$?
eq "$RC" "0" "a listing with zero orders is OK"

# --- 9. A pack dir with no orders/ warns rather than passing blind ----------
mkdir -p "$TMP/emptypack"
OUT=$(ORDERS_JSON="$TMP/none.json" GC_PACK_DIR="$TMP/emptypack" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "a GC_PACK_DIR with no orders/ warns (the name-key arm is blind)"

# --- 10. Positive control over the REAL shipped orders ----------------------
# Pins the check to the files it actually guards: if the pack's rig-scoped
# orders are renamed, restyled, or lose their scope line, this fails here
# rather than turning the whole check into a silent no-op.
REAL_RIG=$(grep -lE '^scope[[:space:]]*=[[:space:]]*"rig"' "$ROOT"/orders/*.toml 2>/dev/null \
           | xargs -r -n1 basename | sed 's/\.toml$//' | sort | tr '\n' ' ')
has "$REAL_RIG" "liveness-sweep"   "shipped orders/: liveness-sweep is detected as rig-scoped"
has "$REAL_RIG" "triage-recurrence" "shipped orders/: triage-recurrence is detected as rig-scoped"
hasnt "$REAL_RIG" "boot-health"    "shipped orders/: the city-scoped boot-health is not miscounted"

echo
echo "check-rig-scoped-orders-bound: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
