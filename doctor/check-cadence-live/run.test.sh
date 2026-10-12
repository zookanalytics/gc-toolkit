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
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
# With BARRIER set, each of the three reads the check overlaps marks itself
# started and waits until all three are, giving up after 20s. Reads made one
# after another never get past the first.
barrier() {
    [ -n "${BARRIER:-}" ] || return 0
    : > "$BARRIER/$1"
    for _ in $(seq 1 200); do
        [ -f "$BARRIER/orders" ] && [ -f "$BARRIER/rigs" ] && [ -f "$BARRIER/runs" ] && return 0
        sleep 0.1
    done
    exit 7
}
case "$1 $2" in
  "order list")    barrier orders; rc="${ORDERS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$ORDERS_JSON" ;;
  "rig list")      barrier rigs;   rc="${RIGS_RC:-0}";   [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "order history")
      barrier runs
      printf '%s\n' "$*" >> "${HIST_ARGS:-/dev/null}"
      rc="${HIST_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"
      if [ -n "${HIST_RAW:-}" ]; then cat "$HIST_RAW"; exit "${HIST_RC_AFTER:-0}"; fi
      # Every order's runs, as a read naming no order returns them, or the named
      # order's alone. Each $HIST_DIR/<order>.json holds one order's entries, and
      # an entry's "age" is the seconds since it fired (none = just now). --since
      # drops older runs, and a city run carries no rig, as the real answer omits it.
      # HIST_DELAY keeps the read from returning for that many seconds after its
      # runs were taken, as a slow read does.
      only=""; case "${3:-}" in ""|-*) ;; *) only="$3" ;; esac
      since=0; prev=""
      for a in "$@"; do [ "$prev" = "--since" ] && since="${a%s}"; prev="$a"; done
      now=$(date +%s)
      for f in "$HIST_DIR"/*.json; do
          [ -f "$f" ] || continue
          o=$(basename "$f" .json)
          [ -z "$only" ] || [ "$o" = "$only" ] || continue
          jq -c --arg o "$o" --argjson now "$now" --argjson s "$since" '
              .entries[] | select($s == 0 or (.age // 0) < $s)
              | {order: $o, rig: (.rig // ""), created_at: ($now - (.age // 0) | todate)}
              | if .rig == "" then del(.rig) else . end' "$f"
      done | jq -cs '{entries: .}'
      [ -z "${HIST_DELAY:-}" ] || sleep "$HIST_DELAY"
      exit "${HIST_RC_AFTER:-0}" ;;
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
eq "$(grep -c . "$HIST_ARGS")" "1" "one history read serves every order"
hasnt "$ARGS" "tick" "…and it names no order, so it answers with every order's runs"
hasnt "$ARGS" "gated" "no history is read for a condition-triggered order"
# This registry names no clock-driven trigger, so the rotation is empty and the
# floor is the 30m minimum (assets/scripts/order-cadence.sh).
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
eq "$(printf '%s\n' "$OUT" | grep -c 'could not read the order run history')" "1" \
    "…in one warning naming the one read, not one per order"
OUT=$(HIST_RC=1 ORDERS_JSON="$TMP/orders-missing.json" run_check); RC=$?
eq "$RC" "2" "a missing registration is still an ERROR while the history is unreadable"
has "$OUT" "tick: rig beta imports this pack but has NO registration" "…because the registration arm does not read the history"
# A read that answered in full and then exited non-zero is not read.
OUT=$(HIST_RC_AFTER=1 run_check); RC=$?
eq "$RC" "1" "a history read that answered and then failed warns, never passes"

# --- 7b. the history is read whole or not at all ----------------------------------
# A run whose time or order cannot be read leaves that order's last run
# unjudgeable, and an unjudged run reads as a stopped order.
cat > "$TMP/runs-badtime.json" <<'EOF'
{"entries":[{"order":"tick","rig":"alpha","created_at":"2026-10-12T07:00:00Z"},
  {"order":"tick","rig":"beta","created_at":"not a time"},
  {"order":"citywide","created_at":"2026-10-12T07:00:00Z"}]}
EOF
OUT=$(HIST_RAW="$TMP/runs-badtime.json" run_check); RC=$?
eq "$RC" "1" "a run with no parseable time warns"
hasnt "$OUT" "has NOT fired" "…and no order is called stopped on the history around it"
cat > "$TMP/runs-noorder.json" <<'EOF'
{"entries":[{"rig":"alpha","created_at":"2026-10-12T07:00:00Z"}]}
EOF
OUT=$(HIST_RAW="$TMP/runs-noorder.json" run_check); RC=$?
eq "$RC" "1" "a run that names no order warns"
hasnt "$OUT" "has NOT fired" "…and no order is called stopped"

# --- 7c. one read serves every order, each cut to its own window -------------------
# The read names no order, so it answers with every order's runs, another pack's
# included. Each order is judged on its own runs inside its own window, and a run
# older than one order's window can be inside another's.
cat > "$TMP/pack/orders/daily.toml" <<'EOF'
[order]
trigger = "cooldown"
interval = "24h"
scope = "city"
EOF
cat > "$TMP/orders-daily.json" <<'EOF'
{"orders":[
  {"name":"tick","rig":"alpha"},{"name":"tick","rig":"beta"},
  {"name":"gated","rig":"alpha"},{"name":"gated","rig":"beta"},
  {"name":"citywide","rig":""},{"name":"daily","rig":""}]}
EOF
printf '{"entries":[{"age":172800}]}' > "$TMP/hist/daily.json"   # two days ago
printf '{"entries":[{"rig":"alpha","age":600},{"rig":"beta","age":2500}]}' > "$TMP/hist/tick.json"
printf '{"entries":[{"rig":"beta"}]}' > "$TMP/hist/other-pack.json"   # not tick's run
OUT=$(ORDERS_JSON="$TMP/orders-daily.json" run_check); RC=$?
eq "$RC" "2" "a rig past its order's window is an ERROR within the shared read"
has "$OUT" "tick: registered on rig beta but has NOT fired there in the last" \
    "…tick's beta run is 2500s old, past tick's window, and another order's run there does not count"
hasnt "$OUT" "rig alpha but has NOT fired" "a run 600s old is inside tick's window"
hasnt "$OUT" "daily: registered but has NOT fired" "a run two days old is inside a 24h order's 72h window"
eq "$(grep -c . "$HIST_ARGS")" "1" "…every order judged from one read"
printf '{"entries":[{"age":300000}]}' > "$TMP/hist/daily.json"
OUT=$(ORDERS_JSON="$TMP/orders-daily.json" run_check); RC=$?
has "$OUT" "daily: registered but has NOT fired in the last 259200s" "a run older than 72h is past a 24h order's window"
rm -f "$TMP/pack/orders/daily.toml" "$TMP/hist/daily.json" "$TMP/hist/other-pack.json"
printf '{"entries":[{"rig":"alpha"},{"rig":"beta"}]}' > "$TMP/hist/tick.json"

# --- 7d. the registry, roster and history reads are in flight at once ---------------
# Each stubbed read waits for the other two to start, so a check that made them
# one after another could not read its registry, and would warn.
mkdir -p "$TMP/barrier"
OUT=$(BARRIER="$TMP/barrier" run_check); RC=$?
eq "$RC" "0" "the three reads overlap: each saw the other two in flight"
hasnt "$OUT" "could not read" "…and every one of them answered"

# --- 7e. the reads answer into one temp dir, removed when the check exits ------------
mkdir -p "$TMP/probe-tmp"
OUT=$(TMPDIR="$TMP/probe-tmp" run_check); RC=$?
eq "$RC" "0" "a run staging its reads under TMPDIR is OK"
eq "$(ls -A "$TMP/probe-tmp")" "" "…and leaves nothing behind"
OUT=$(TMPDIR="$TMP/no-such-dir" run_check); RC=$?
eq "$RC" "1" "no temp dir for the reads warns, never passes"
has "$OUT" "nothing was read" "…and says nothing was read"

# --- 7f. every window ends when the read is sent ------------------------------------
# The answer holds no run newer than its fetch, so a window anchored once the
# reads answer is cut short by however long they took, and a run near its far
# edge reads as stopped. tick's window comes from the check's own finding, beta's
# run is one second inside it as of the read's start, and the read answers two
# seconds later.
printf '{"entries":[{"rig":"alpha"}]}' > "$TMP/hist/tick.json"
W=$(run_check | sed -n 's/.*tick: registered on rig beta but has NOT fired there in the last \([0-9]*\)s.*/\1/p')
[ -n "$W" ] && ok "the stale-rig finding states tick's window (${W}s)" || bad "no window in the stale-rig finding"
printf '{"entries":[{"rig":"alpha"},{"rig":"beta","age":%s}]}' "$(( ${W:-900} - 1 ))" > "$TMP/hist/tick.json"
OUT=$(HIST_DELAY=2 run_check); RC=$?
eq "$RC" "0" "a run inside its window when the read was sent counts, however long the read took"
hasnt "$OUT" "has NOT fired" "…so the read's own latency calls no order stopped"
printf '{"entries":[{"rig":"alpha"},{"rig":"beta"}]}' > "$TMP/hist/tick.json"

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
eq "$RC" "0" "a busy rotation with every order fresh is OK"
has "$OUT" "cadence floor 2160s: 70 clock-driven registration(s) at 4 per dispatch pass" "the derivation is stated"
# A raised budget shortens the trip: ceil(70/8) = 9 passes is 1080s, under the
# 30m minimum, so the minimum holds.
mkdir -p "$TMP/city-budget8"
printf '[orders]\nmax_dispatches_per_tick = 8\n' > "$TMP/city-budget8/city.toml"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" CITY_DIR="$TMP/city-budget8" run_check); RC=$?
has "$OUT" "cadence floor 1800s" "a budget of 8 halves the trip, and the 30m minimum holds"
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
