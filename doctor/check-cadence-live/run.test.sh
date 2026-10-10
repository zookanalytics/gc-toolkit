#!/usr/bin/env bash
# Hermetic test for doctor/check-cadence-live (I10). Stub gc; fixture pack.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-cadence-live-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/pack/orders" "$TMP/hist" "$TMP/empty-city"
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
      # --since bounds the answer as the real history does: an entry carrying an
      # "age" (seconds since it fired) is returned only inside the window. An
      # entry with no age is always inside it.
      since=0; prev=""
      for a in "$@"; do [ "$prev" = "--since" ] && since="${a%s}"; prev="$a"; done
      f="$HIST_DIR/$3.json"
      if [ -f "$f" ]; then jq -c --argjson s "$since" '.entries |= map(select((.age // 0) < $s))' "$f"
      else printf '{"entries":[]}'; fi ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" HIST_DIR="$TMP/hist" HIST_ARGS="$TMP/hist-args.log"
# A pack dir that is its own git repo, so arm 3 has a tree revision to compare
# against. Local and never pushed; the identity is scaffolding. The identity is
# the services/gctk subtree, not the commit: the build order records and stamps
# that, so a commit touching nothing under it is not a mismatch.
mkdir -p "$TMP/pack/services/gctk/cmd/gctk"
echo 'package main' > "$TMP/pack/services/gctk/cmd/gctk/main.go"
git -C "$TMP/pack" init -q >/dev/null 2>&1
git -C "$TMP/pack" add -A >/dev/null 2>&1
git -C "$TMP/pack" -c user.email=fixture@example.invalid -c user.name=fixture \
    -c commit.gpgsign=false commit -q -m fixture >/dev/null 2>&1
PACK_REV=$(git -C "$TMP/pack/services/gctk" rev-parse 'HEAD:./' 2>/dev/null)
PACK_COMMIT=$(git -C "$TMP/pack" rev-parse HEAD 2>/dev/null)
[ -n "$PACK_REV" ] && ok "the fixture pack has a revision for arm 3 to compare" \
                   || bad "no fixture revision; the gctk arm would pass vacuously"

gctk_stub() { # <version-output> -> installs a fake gctk at $TMP/bin/gctk-stub
    printf '#!/bin/sh\n[ "$1" = version ] && echo "%s"\n' "$1" > "$TMP/bin/gctk-stub"
    chmod +x "$TMP/bin/gctk-stub"
}
# The binary every order case runs against: deployed, and built from this
# fixture checkout, so arm 3 notes a match and adds nothing to those cases.
printf '#!/bin/sh\n[ "$1" = version ] && echo "%s"\n' "$PACK_REV" > "$TMP/bin/gctk-current"
chmod +x "$TMP/bin/gctk-current"

# GCTK_BIN is pinned to that binary so arm 3 stays out of every order case:
# unset, it would resolve through the AMBIENT city and read the live binary,
# which is neither hermetic nor what those cases are about, and a missing binary
# is a finding of its own. The gctk cases below override it deliberately. An
# order case that hand-rolls its own `bash "$CHECK"` loses that pin, so vary
# ORDERS_JSON or RIGS_JSON and call this.
# GC_CITY_PATH is pinned the same way, to a fixture city (empty by default) so
# the registration arm never reads the AMBIENT city.toml; the disable cases set
# CITY_DIR to a fixture that carries [[orders.overrides]] / skip entries.
run_check() { : > "$HIST_ARGS"; ORDERS_JSON="${ORDERS_JSON:-$TMP/orders.json}" RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" GCTK_BIN="${GCTK_BIN:-$TMP/bin/gctk-current}" GC_CITY_PATH="${CITY_DIR:-$TMP/empty-city}" bash "$CHECK" 2>&1; }

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
# This registry names no clock-driven trigger, so the rotation is empty and the
# floor is the 30m minimum (assets/scripts/order-cadence.sh).
has "$ARGS" "tick --since 1800s" "the window is max(3x60s, floor) = the 30m minimum floor"
has "$ARGS" "citywide --since 1800s" "a 5m order also takes the floor"
hasnt "$ARGS" "gated" "no history is read for a condition-triggered order"
has "$OUT" "cadence floor 1800s" "the floor and its basis are stated"

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
has "$OUT" "1800s" "the window is stated"
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

# --- 8. arm 3: a gctk is deployed, and it is the one this checkout describes ----
# Orders can fire perfectly while the cadence runs logic several commits old,
# because the data plane is a binary a build order publishes. Nothing in arms 1
# and 2 can see that, nor a binary that was never published at all.
#
# lifecycle.sh execs the binary and has no other implementation, so a missing
# one is an error: every lifecycle transition is refused until one lands.
OUT=$(GCTK_BIN="$TMP/no-such-gctk" run_check); RC=$?
eq "$RC" "2" "no deployed binary is an ERROR — lifecycle.sh has nothing else to exec"
has "$OUT" "no binary at $TMP/no-such-gctk" "the finding names where the binary should be"
has "$OUT" "gctk-build" "…and the order that publishes it"

gctk_stub "$PACK_REV"
OUT=$(GCTK_BIN="$TMP/bin/gctk-stub" run_check); RC=$?
eq "$RC" "0" "a binary built from this checkout is OK"
has "$OUT" "matches this checkout" "and says so"

# A hand build carries the toolchain's commit stamp; the subtree that commit
# holds is what the checkout is compared against.
gctk_stub "$PACK_COMMIT"
OUT=$(GCTK_BIN="$TMP/bin/gctk-stub" run_check); RC=$?
eq "$RC" "0" "a binary stamped with the commit that holds this subtree is OK"
has "$OUT" "matches this checkout" "and says so"

# A commit that touches nothing under services/gctk moves HEAD, not the identity.
echo '# unrelated' >> "$TMP/pack/orders/tick.toml"
git -C "$TMP/pack" add -A >/dev/null 2>&1
git -C "$TMP/pack" -c user.email=fixture@example.invalid -c user.name=fixture \
    -c commit.gpgsign=false commit -q -m unrelated >/dev/null 2>&1
gctk_stub "$PACK_REV"
OUT=$(GCTK_BIN="$TMP/bin/gctk-stub" run_check); RC=$?
eq "$RC" "0" "a commit outside services/gctk does not make the deployed binary stale"

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

# The city chain, with no GCTK_BIN to shortcut it. GC_CITY_PATH is the city root
# an agent session carries — GC_CITY and GC_CITY_ROOT are absent there — so a
# resolver blind to it reports "no binary deployed" against a city that has one.
CITY="$TMP/city"
mkdir -p "$CITY/.gc/services/gctk/bin"
gctk_stub "$PACK_REV"
cp "$TMP/bin/gctk-stub" "$CITY/.gc/services/gctk/bin/gctk"
check_by_city() { # <env assignments...> — run the check with no GCTK_BIN pin
    : > "$HIST_ARGS"
    env -u GCTK_BIN -u GC_CITY -u GC_CITY_ROOT -u GC_CITY_PATH "$@" \
        ORDERS_JSON="$TMP/orders.json" RIGS_JSON="$TMP/rigs.json" \
        GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1
}
OUT=$(check_by_city GC_CITY_PATH="$CITY"); RC=$?
eq "$RC" "0" "GC_CITY_PATH alone resolves the deployed binary"
has "$OUT" "matches this checkout" "and the arm compared it, rather than reporting no deploy"

# A named city with nothing at the path lifecycle.sh would exec: a fresh city
# before the gctk-build order's first build, or one whose builds never succeed.
mkdir -p "$TMP/bare-city"
OUT=$(check_by_city GC_CITY_PATH="$TMP/bare-city"); RC=$?
eq "$RC" "2" "a named city with no binary deployed is an ERROR"
has "$OUT" "no binary at $TMP/bare-city/.gc/services/gctk/bin/gctk" "and the finding names the path lifecycle.sh would exec"

# The control. Same city on disk, named by nothing: without it the case above
# would also pass on a resolver that found the binary by some other route. With
# no city to look in, the arm reports that it did not look, not that the binary
# is missing.
OUT=$(check_by_city); RC=$?
eq "$RC" "1" "no city named at all WARNS: the arm could not look"
has "$OUT" "was NOT checked" "and it says the binary was not checked, rather than calling it missing"

# --- 9. no orders/ at all is vacuously OK ---------------------------------------------
mkdir -p "$TMP/empty-pack"
OUT=$(GC_PACK_DIR="$TMP/empty-pack" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a pack shipping no orders has no cadence to assert"

# --- 10. a deliberate city.toml disable is a NOTE, not a missing registration ------
# `gc order list` omits a disabled order, so arm 1 sees it as unregistered. The
# check reads city.toml and tells an intended disable apart from a real gap, so a
# true stall (arm 2) is never buried beside a deliberate one.
mkdir -p "$TMP/city-tick-beta"
cat > "$TMP/city-tick-beta/city.toml" <<'EOF'
[orders]
[[orders.overrides]]
name = "tick"
rig = "beta"
enabled = false
EOF
# tick registered on alpha only (orders-missing.json); beta's gap is the disable.
OUT=$(ORDERS_JSON="$TMP/orders-missing.json" CITY_DIR="$TMP/city-tick-beta" run_check); RC=$?
eq "$RC" "0" "a rig-scoped order disabled on a rig is a NOTE, not an error"
has "$OUT" "deliberately disabled on rig beta" "the disable is named as intended, not as a gap"
hasnt "$OUT" "rig beta imports this pack but has NO registration" "and it did not stay a missing-registration error"

# A disabled rig (note) beside a registered-but-stopped rig (error): the real
# stall must survive, un-buried.
printf '{"entries":[]}' > "$TMP/hist/tick.json"   # alpha registered but did not fire
OUT=$(ORDERS_JSON="$TMP/orders-missing.json" CITY_DIR="$TMP/city-tick-beta" run_check); RC=$?
eq "$RC" "2" "a real stall is still an ERROR while a disabled rig is only a note"
has "$OUT" "has NOT fired" "the stall is reported"
has "$OUT" "deliberately disabled on rig beta" "the deliberate disable rides along as a note"
hasnt "$OUT" "rig beta imports this pack but has NO registration" "the disable did not add a false error"
printf '{"entries":[{"rig":"alpha"},{"rig":"beta"}]}' > "$TMP/hist/tick.json"

# A gap the config does NOT disable stays an error — the true positive preserved.
mkdir -p "$TMP/city-unrelated"
cat > "$TMP/city-unrelated/city.toml" <<'EOF'
[orders]
[[orders.overrides]]
name = "some-other-order"
rig = "beta"
enabled = false
EOF
OUT=$(ORDERS_JSON="$TMP/orders-missing.json" CITY_DIR="$TMP/city-unrelated" run_check); RC=$?
eq "$RC" "2" "a gap the city config does not explain is still an ERROR"
has "$OUT" "tick: rig beta imports this pack but has NO registration" "the genuine gap is still named"

# An unscoped (rigless) enabled=false covers a rig-scoped order on every rig.
mkdir -p "$TMP/city-tick-all"
cat > "$TMP/city-tick-all/city.toml" <<'EOF'
[orders]
[[orders.overrides]]
name = "tick"
enabled = false
EOF
OUT=$(ORDERS_JSON="$TMP/orders-missing.json" CITY_DIR="$TMP/city-tick-all" run_check); RC=$?
eq "$RC" "0" "an unscoped disable covers a rig-scoped order's missing rig"
has "$OUT" "tick: deliberately disabled on rig beta" "the missing rig reads as deliberate"

# A city-scoped order: an unscoped disable answers its city-wide question.
mkdir -p "$TMP/city-wide-off"
cat > "$TMP/city-wide-off/city.toml" <<'EOF'
[orders]
[[orders.overrides]]
name = "citywide"
enabled = false
EOF
OUT=$(ORDERS_JSON="$TMP/orders-nocity.json" CITY_DIR="$TMP/city-wide-off" run_check); RC=$?
eq "$RC" "0" "a city-scoped order disabled by an unscoped override is a NOTE"
has "$OUT" "citywide: deliberately disabled" "the disabled city order is noted"
hasnt "$OUT" "NO live registration" "and not reported as never registered"

# The [orders] skip list is the other deliberate-disable mechanism.
mkdir -p "$TMP/city-skip"
cat > "$TMP/city-skip/city.toml" <<'EOF'
[orders]
skip = ["citywide"]
EOF
OUT=$(ORDERS_JSON="$TMP/orders-nocity.json" CITY_DIR="$TMP/city-skip" run_check); RC=$?
eq "$RC" "0" "an order in the [orders] skip list is a NOTE, not an error"
has "$OUT" "citywide: deliberately disabled" "the skipped order is noted"

# --- 11. the floor is one trip of the dispatch rotation --------------------------
# The supervisor fires at most max_dispatches_per_tick clock-driven orders per
# pass, so a short-interval order fires once per trip around the rotation. With
# the pack's three clock-driven registrations plus 67 others (70 in all) at the
# default budget of 4, a trip is ceil(70/4) = 18 passes, and at 120s a pass the
# floor is 2160s. A condition order takes no rotation slot.
{
    printf '{"orders":[{"name":"tick","rig":"alpha","trigger":"cooldown"},{"name":"tick","rig":"beta","trigger":"cooldown"},'
    printf '{"name":"gated","rig":"alpha","trigger":"condition"},{"name":"gated","rig":"beta","trigger":"condition"},'
    printf '{"name":"citywide","rig":"","trigger":"cooldown"}'
    for i in $(seq 1 67); do printf ',{"name":"other-%s","rig":"","trigger":"cooldown"}' "$i"; done
    printf ']}\n'
} > "$TMP/orders-busy.json"
printf '{"entries":[{"rig":"alpha"},{"rig":"beta"}]}' > "$TMP/hist/tick.json"
printf '{"entries":[{"rig":""}]}' > "$TMP/hist/citywide.json"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" run_check); RC=$?
ARGS=$(cat "$HIST_ARGS")
eq "$RC" "0" "a busy rotation with every order fresh is OK"
has "$ARGS" "tick --since 2160s" "the floor is one trip of the rotation: ceil(70/4) passes at 120s"
has "$ARGS" "citywide --since 2160s" "…and it is the window of a 5m order too"
has "$OUT" "cadence floor 2160s: 70 clock-driven registration(s) at 4 per dispatch pass" "the derivation is stated"
# A raised budget shortens the trip: ceil(70/8) = 9 passes is 1080s, under the
# 30m minimum, so the minimum holds.
mkdir -p "$TMP/city-budget8"
printf '[orders]\nmax_dispatches_per_tick = 8\n' > "$TMP/city-budget8/city.toml"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" CITY_DIR="$TMP/city-budget8" run_check); RC=$?
ARGS=$(cat "$HIST_ARGS")
has "$ARGS" "tick --since 1800s" "a budget of 8 halves the trip, and the 30m minimum holds"
has "$OUT" "at 8 per dispatch pass" "the budget city.toml sets is the one used"

# --- 12. a gap longer than 900s but inside the trip is not a stopped order -------
# Healthy 5m orders run up to about 18 minutes apart while the rotation is
# saturated. The 900s window this replaced read such a gap as a stopped pass.
printf '{"entries":[{"rig":"alpha","age":1200},{"rig":"beta","age":1200}]}' > "$TMP/hist/tick.json"
printf '{"entries":[{"rig":"","age":1200}]}' > "$TMP/hist/citywide.json"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" run_check); RC=$?
eq "$RC" "0" "orders last fired 1200s ago are live inside a 2160s trip"
hasnt "$OUT" "has NOT fired" "…and no pass is called stopped"
# A gap past the window is still a stopped pass.
printf '{"entries":[{"rig":"alpha","age":1200},{"rig":"beta","age":2500}]}' > "$TMP/hist/tick.json"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" run_check); RC=$?
eq "$RC" "2" "a rig that last fired 2500s ago, past the 2160s window, is an ERROR"
has "$OUT" "tick: registered on rig beta but has NOT fired there in the last 2160s" "…naming the rig and the window"
printf '{"entries":[{"rig":"alpha"},{"rig":"beta"}]}' > "$TMP/hist/tick.json"
printf '{"entries":[{"rig":""}]}' > "$TMP/hist/citywide.json"

# --- 13. the window is the shared definition, not a constant of this check -----
if grep -qE '^[[:space:]]*FLOOR=[0-9]' "$CHECK"; then
    bad "the check carries no floor constant of its own"
else ok "the check carries no floor constant of its own"; fi
grep -qF 'assets/scripts/order-cadence.sh' "$CHECK" && ok "the check sources assets/scripts/order-cadence.sh" \
    || bad "the check sources assets/scripts/order-cadence.sh"

echo
echo "check-cadence-live: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
