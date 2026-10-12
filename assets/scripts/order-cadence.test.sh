#!/usr/bin/env bash
# Hermetic test for assets/scripts/order-cadence.sh, the one definition of an
# order's cadence window. Covers:
#   (INTERVAL) cadence_interval_secs and cadence_order_interval read an order
#              interval in seconds, and answer nothing for one that does not parse
#   (BUDGET)   cadence_budget reads [orders] max_dispatches_per_tick, and falls
#              back to the built-in 4 when it is unset, not positive, or elsewhere
#   (FLOOR)    the floor is one trip of the rotation, ceil(registrations / budget)
#              passes at the pass spacing, never below the minimum, and only
#              enabled clock-driven registrations take a rotation slot
#   (WINDOW)   the window is max(3 × interval, floor)
#   (READERS)  both doctor checks that judge a cadence source this file
#   (NO-COPY)  no other file carries a cadence window of its own
# The behavioral half lives beside each reader, in
# doctor/check-cadence-live/run.test.sh and
# doctor/check-armed-dispatch-owed/run.test.sh.
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/order-cadence.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-order-cadence-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

# shellcheck source=order-cadence.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }

echo "# (INTERVAL) an order interval in seconds"
eq "$(cadence_interval_secs 30s)" "30" "30s is 30"
eq "$(cadence_interval_secs 5m)" "300" "5m is 300"
eq "$(cadence_interval_secs 2h)" "7200" "2h is 7200"
for bad_iv in "" 5 5x m 1h30m -5m; do
    eq "$(cadence_interval_secs "$bad_iv")" "" "'$bad_iv' does not parse, so it answers nothing"
done
printf '[order]\ntrigger = "cooldown"\ninterval = "5m"\n' > "$TMP/dd.toml"
eq "$(cadence_order_interval "$TMP/dd.toml")" "300" "an order file's [order] interval is read"
printf 'interval = "1h"\n[order]\ntrigger = "condition"\n' > "$TMP/cond.toml"
eq "$(cadence_order_interval "$TMP/cond.toml")" "" "an interval outside [order] is not the order's"
eq "$(cadence_order_interval "$TMP/missing.toml")" "" "a missing order file answers nothing"

echo "# (BUDGET) the per-pass dispatch budget"
eq "$(cadence_budget "$TMP/missing.toml")" "4" "no city.toml means the built-in budget of 4"
eq "$(cadence_budget "")" "4" "no path means the built-in budget"
printf '[orders]\nskip = ["x"]\n' > "$TMP/c-unset.toml"
eq "$(cadence_budget "$TMP/c-unset.toml")" "4" "an [orders] table without the key keeps 4"
printf '[orders]\nmax_dispatches_per_tick = 8 # raised\n' > "$TMP/c-8.toml"
eq "$(cadence_budget "$TMP/c-8.toml")" "8" "a set budget is read, trailing comment and all"
printf '[orders]\nmax_dispatches_per_tick = 0\n' > "$TMP/c-0.toml"
eq "$(cadence_budget "$TMP/c-0.toml")" "4" "zero falls back to 4, as gascity's dispatcher does"
printf '[orders]\nmax_dispatches_per_tick = -2\n' > "$TMP/c-neg.toml"
eq "$(cadence_budget "$TMP/c-neg.toml")" "4" "a negative budget falls back to 4"
printf '[daemon]\nmax_dispatches_per_tick = 9\n[orders]\nskip = []\n' > "$TMP/c-other.toml"
eq "$(cadence_budget "$TMP/c-other.toml")" "4" "the key under another table is not the orders budget"
printf '[orders]\nskip = []\n[[orders.overrides]]\nname = "x"\nmax_dispatches_per_tick = 9\n' > "$TMP/c-ovr.toml"
eq "$(cadence_budget "$TMP/c-ovr.toml")" "4" "the key inside an [[orders.overrides]] block is not the orders budget"

echo "# (FLOOR) one trip of the rotation, never below the minimum"
eq "$CADENCE_FLOOR_MIN" "1800" "the minimum floor is 30m"
eq "$CADENCE_PASS_SPACING" "120" "a window allows 120s a pass"
eq "$(cadence_floor_of 64 4)" "1920" "64 registrations at 4 a pass are 16 passes, 1920s"
eq "$(cadence_floor_of 70 4)" "2160" "70 at 4 round up to 18 passes, 2160s"
eq "$(cadence_floor_of 70 8)" "1800" "70 at 8 are 9 passes, 1080s, so the minimum holds"
eq "$(cadence_floor_of 0 4)" "1800" "an empty rotation takes the minimum"
eq "$(cadence_floor_of 64 0)" "1920" "a zero budget is the built-in 4"
REG='{"orders":[
  {"name":"a","trigger":"cooldown"},{"name":"b","trigger":"cron"},{"name":"c","trigger":"event"},
  {"name":"d","trigger":"condition"},{"name":"e","trigger":"cooldown","enabled":false},
  {"name":"f","rig":"alpha","trigger":"cooldown"},{"name":"f","rig":"beta","trigger":"cooldown"}]}'
eq "$(cadence_clock_registrations "$REG")" "5" "cooldown, cron and event registrations count, each rig's on its own; condition and disabled ones do not"
eq "$(cadence_clock_registrations "not json")" "" "an unreadable registry answers nothing"
eq "$(cadence_clock_registrations '{"error":"x"}')" "" "a registry with no .orders array answers nothing"
BIG=$(jq -nc '{orders: [range(0; 70) | {name: "o\(.)", trigger: "cooldown"}]}')
eq "$(cadence_floor "$BIG" "$TMP/missing.toml")" "2160" "the floor reads the live registry at the default budget"
eq "$(cadence_floor "$BIG" "$TMP/c-8.toml")" "1800" "…and the budget city.toml sets"
eq "$(cadence_floor "not json" "$TMP/missing.toml")" "1800" "an unreadable registry takes the minimum"

echo "# (WINDOW) max(3 × interval, floor)"
eq "$(cadence_window 300 1920)" "1920" "a 5m order takes the floor"
eq "$(cadence_window 60 1800)" "1800" "a 60s order takes the floor"
eq "$(cadence_window 3600 1920)" "10800" "an hourly order keeps three intervals"
eq "$(cadence_window 601 1800)" "1803" "three intervals win as soon as they pass the floor"

echo "# (READERS) every cadence reader sources the one definition"
for r in doctor/check-cadence-live/run.sh doctor/check-armed-dispatch-owed/run.sh; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    grep -qF 'assets/scripts/order-cadence.sh' "$f" \
        && ok "(READERS) $r sources order-cadence.sh" \
        || bad "(READERS) $r sources order-cadence.sh"
    grep -qE 'cadence_window ' "$f" \
        && ok "(READERS) $r takes its window from cadence_window" \
        || bad "(READERS) $r takes its window from cadence_window"
done

echo "# (NO-COPY) no file carries a cadence window of its own"
# A constant floor or owed window in a reader, or the old formula in a doc, is a
# copy that drifts from the definition. Specs and generated renders are history
# and output, not readers.
copies=$(cd "$ROOT" && git ls-files -- ':!specs/' ':!generated/' ':!assets/scripts/order-cadence.test.sh' 2>/dev/null \
    | while IFS= read -r p; do
        [ -f "$p" ] || continue
        grep -lE '^[[:space:]]*(FLOOR|OWED_WINDOW_SECONDS)=[0-9]|max\(3×interval, 15m\)' "$p" 2>/dev/null
      done)
if [ -z "$copies" ]; then ok "(NO-COPY) no other file carries a floor constant or the 15m formula"
else bad "(NO-COPY) a copied cadence window survives in: $(printf '%s' "$copies" | tr '\n' ' ')"; fi

echo
echo "order-cadence: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
