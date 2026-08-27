#!/usr/bin/env bash
# Hermetic test for doctor/check-cadence-live (I10). Stub gc; fixture pack.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/pack/orders" "$TMP/hist"
cat > "$TMP/pack/orders/tick.toml" <<'EOF'
[order]
trigger = "cooldown"
interval = "60s"
scope = "rig"
EOF
cat > "$TMP/pack/orders/citywide.toml" <<'EOF'
[order]
trigger = "cooldown"
interval = "5m"
scope = "city"
EOF
cat > "$TMP/pack/orders/gated.toml" <<'EOF'
[order]
trigger = "condition"
scope = "rig"
EOF
cat > "$TMP/rigs.json" <<'EOF'
{"rigs":[{"name":"alpha","suspended":false},{"name":"beta","suspended":false}]}
EOF
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "order list")    rc="${ORDERS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$ORDERS_JSON" ;;
  "rig list")      rc="${RIGS_RC:-0}";   [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "order history")
      printf '%s\n' "$*" >> "${HIST_ARGS:-/dev/null}"
      rc="${HIST_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"
      f="$HIST_DIR/$3.json"; if [ -f "$f" ]; then cat "$f"; else printf '{"entries":[]}'; fi ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" HIST_DIR="$TMP/hist" HIST_ARGS="$TMP/hist-args.log"
# GCTK_BIN is pinned to a path that does not exist so arm 3 stays out of every
# order case: unset, it would resolve through the AMBIENT city and read the live
# binary, which is neither hermetic nor what those cases are about. The gctk
# cases below override it deliberately. An order case that hand-rolls its own
# `bash "$CHECK"` loses that pin, so vary ORDERS_JSON or RIGS_JSON and call this.
run_check() { : > "$HIST_ARGS"; ORDERS_JSON="${ORDERS_JSON:-$TMP/orders.json}" RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" GCTK_BIN="${GCTK_BIN:-$TMP/no-such-gctk}" bash "$CHECK" 2>&1; }

# A pack dir that is its own git repo, so arm 3 has a tree revision to compare
# against. Local and never pushed; the identity is scaffolding.
gctk_stub() { # <version-output> -> installs a fake gctk at $TMP/bin/gctk-stub
    printf '#!/bin/sh\n[ "$1" = version ] && echo "%s"\n' "$1" > "$TMP/bin/gctk-stub"
    chmod +x "$TMP/bin/gctk-stub"
}

# Fully healthy registry: tick on both rigs, gated on both, citywide unbound.
cat > "$TMP/orders.json" <<'EOF'
{"orders":[
  {"name":"tick","rig":"alpha"},{"name":"tick","rig":"beta"},
  {"name":"gated","rig":"alpha"},{"name":"gated","rig":"beta"},
  {"name":"citywide","rig":""}]}
EOF
printf '{"entries":[{"rig":"alpha"},{"rig":"beta"}]}' > "$TMP/hist/tick.json"
printf '{"entries":[{"rig":""}]}' > "$TMP/hist/citywide.json"

# --- 1. everything registered and fresh -----------------------------------------
OUT=$(run_check); RC=$?
eq "$RC" "0" "registered everywhere + fired inside the window is OK"
has "$OUT" "condition-triggered" "the interval-less order is noted, not time-judged"
ARGS=$(cat "$HIST_ARGS")
has "$ARGS" "--limit 0" "the history read is unbounded (--limit 0 is load-bearing)"
has "$ARGS" "tick --since 900s" "the window is max(3x60s, 15m) = the 15m floor"
has "$ARGS" "citywide --since 900s" "a 5m order also floors at 15m"
hasnt "$ARGS" "gated" "no history is read for a condition-triggered order"

# --- 2. a rig importing the pack with a missing registration ----------------------
cat > "$TMP/orders-missing.json" <<'EOF'
{"orders":[
  {"name":"tick","rig":"alpha"},
  {"name":"gated","rig":"alpha"},{"name":"gated","rig":"beta"},
  {"name":"citywide","rig":""}]}
EOF
OUT=$(ORDERS_JSON="$TMP/orders-missing.json" run_check); RC=$?
eq "$RC" "2" "an importing rig with no registration for a rig-scoped order is an ERROR"
has "$OUT" "tick: rig beta" "the missing registration names order and rig"

# --- 3. a registered rig that stopped firing --------------------------------------
printf '{"entries":[{"rig":"alpha"}]}' > "$TMP/hist/tick.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a registered rig with no run inside the window is an ERROR"
has "$OUT" "beta" "the stale rig is named"
has "$OUT" "900s" "the window is stated"
printf '{"entries":[{"rig":"alpha"},{"rig":"beta"}]}' > "$TMP/hist/tick.json"

# --- 4. a suspended rig is not judged stale ----------------------------------------
cat > "$TMP/rigs-susp.json" <<'EOF'
{"rigs":[{"name":"alpha","suspended":false},{"name":"beta","suspended":true}]}
EOF
printf '{"entries":[{"rig":"alpha"}]}' > "$TMP/hist/tick.json"
OUT=$(RIGS_JSON="$TMP/rigs-susp.json" run_check); RC=$?
eq "$RC" "0" "a suspended rig's silence is a note, not an error"
has "$OUT" "suspended" "the skip is noted"
printf '{"entries":[{"rig":"alpha"},{"rig":"beta"}]}' > "$TMP/hist/tick.json"

# --- 5. a city-scoped order that never fires ----------------------------------------
printf '{"entries":[]}' > "$TMP/hist/citywide.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a city-scoped order with no run inside the window is an ERROR"
has "$OUT" "citywide" "the stopped order is named"
printf '{"entries":[{"rig":""}]}' > "$TMP/hist/citywide.json"

# --- 6. a city-scoped order with no registration at all ------------------------------
cat > "$TMP/orders-nocity.json" <<'EOF'
{"orders":[
  {"name":"tick","rig":"alpha"},{"name":"tick","rig":"beta"},
  {"name":"gated","rig":"alpha"},{"name":"gated","rig":"beta"}]}
EOF
OUT=$(ORDERS_JSON="$TMP/orders-nocity.json" run_check); RC=$?
eq "$RC" "2" "an unregistered city-scoped order is an ERROR"
has "$OUT" "NO live registration" "the finding says the pass never runs"

# --- 7. fail-CLOSED -------------------------------------------------------------
OUT=$(ORDERS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable order registry warns, never passes"
OUT=$(HIST_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable history warns (the liveness arm did not run)"

# --- 8. arm 3: the deployed gctk is the one this checkout describes -------------
# Orders can fire perfectly while the cadence runs logic several commits old,
# because the data plane is a binary a build order publishes. Nothing in arms 1
# and 2 can see that.
git -C "$TMP/pack" init -q >/dev/null 2>&1
git -C "$TMP/pack" add -A >/dev/null 2>&1
git -C "$TMP/pack" -c user.email=fixture@example.invalid -c user.name=fixture \
    -c commit.gpgsign=false commit -q -m fixture >/dev/null 2>&1
PACK_REV=$(git -C "$TMP/pack" rev-parse HEAD 2>/dev/null)
[ -n "$PACK_REV" ] && ok "the fixture pack has a revision for arm 3 to compare" \
                   || bad "no fixture revision; the gctk arm would pass vacuously"

OUT=$(run_check); RC=$?
eq "$RC" "0" "no deployed binary is the supported migration state, not a finding"
has "$OUT" "shell fallbacks" "and it says which implementation is answering"

gctk_stub "$PACK_REV"
OUT=$(GCTK_BIN="$TMP/bin/gctk-stub" run_check); RC=$?
eq "$RC" "0" "a binary built from this checkout is OK"
has "$OUT" "matches this checkout" "and says so"

gctk_stub "0000000000000000000000000000000000000000"
OUT=$(GCTK_BIN="$TMP/bin/gctk-stub" run_check); RC=$?
eq "$RC" "1" "a binary built from another revision WARNS"
has "$OUT" "0000000000000000000000000000000000000000" "the finding names what is actually running"
has "$OUT" "$PACK_REV" "and what the checkout expects"

gctk_stub "unknown"
OUT=$(GCTK_BIN="$TMP/bin/gctk-stub" run_check); RC=$?
eq "$RC" "1" "an unstamped binary warns — it cannot be compared, which is not a pass"

printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gctk-stub"; chmod +x "$TMP/bin/gctk-stub"
OUT=$(GCTK_BIN="$TMP/bin/gctk-stub" run_check); RC=$?
eq "$RC" "1" "a binary that will not answer warns, never passes"

# --- 9. no orders/ at all is vacuously OK ---------------------------------------------
mkdir -p "$TMP/empty-pack"
OUT=$(GC_PACK_DIR="$TMP/empty-pack" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a pack shipping no orders has no cadence to assert"

echo
echo "check-cadence-live: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
