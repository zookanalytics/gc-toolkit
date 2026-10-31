#!/usr/bin/env bash
# Hermetic test for witness-nudge.sh and its order.
#
# A fake `gc` on PATH answers the session list and records each nudge's argv, so
# the assertions pin what a pass sends rather than grepping the script. No
# dependency on the live city, the store or a tmux server.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/witness-nudge.sh"
ORDER="$ROOT/orders/witness-nudge.toml"
FORMULA="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-witness-nudge-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
case "$1 $2" in
  "session list")
    printf 'GC_NO_API=%s args=%s\n' "${GC_NO_API:-}" "$*" >> "$LIST_LOG"
    [ "${STUB_LIST_RC:-0}" -eq 0 ] || exit "$STUB_LIST_RC"
    printf '%s' "${STUB_LIST-}"
    ;;
  "session nudge")
    printf '%s\n' "$*" >> "$NUDGE_LOG"
    case "$*" in *"${STUB_NUDGE_FAIL_ID:-no-such-id}"*) exit 1 ;; esac
    ;;
  *) echo "unexpected gc call: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$TMP/bin/gc"
PATH="$TMP/bin:$PATH"
export LIST_LOG="$TMP/list.log" NUDGE_LOG="$TMP/nudge.log"

NOW=$(date +%s)
# The script's clock stands at NOW, so a case one second from the bound stays there
# however long the suite takes to reach it.
printf '#!/bin/sh\necho %s\n' "$NOW" > "$TMP/bin/date"
chmod +x "$TMP/bin/date"
# iso <seconds ago> [offset]: an RFC3339 time that long ago, at that UTC offset.
iso() {
  local shift_secs=0 zone="${2:-Z}"
  case "$zone" in
    Z) ;;
    [+-]*) shift_secs=$(( ${zone:0:1}1 * (10#${zone:1:2} * 3600 + 10#${zone:4:2} * 60) )) ;;
  esac
  jq -rn --argjson s "$((NOW - $1 + shift_secs))" --arg z "$zone" '$s | todate | sub("Z$"; $z)'
}
# row <id> <template> <state> <attached> <last_active> <last_nudge>
row() {
  jq -cn --arg id "$1" --arg t "$2" --arg st "$3" --argjson at "$4" --arg la "$5" --arg ln "$6" \
    '{id: $id, alias: $t, template: $t, state: $st, attached: $at, last_active: $la}
     + (if $ln == "" then {} else {last_nudge_delivered_at: $ln} end)'
}
# list_of <row>...: the session list's JSON around those rows.
list_of() { printf '%s\n' "$@" | jq -s '{sessions: .}'; }

# run: one pass over STUB_LIST, with the outcome in OUT, ERR and RC.
run() {
  : > "$LIST_LOG"; : > "$NUDGE_LOG"
  OUT=$("$SCRIPT" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
  NUDGES=$(cat "$NUDGE_LOG")
}
count() { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }

W=gc-toolkit/gc-toolkit.witness

echo "--- a quiet witness is nudged once, typed live, by id"
export STUB_LIST; STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$(iso 900)" "")")
run
eq "$RC" 0 "a quiet witness's pass exits 0"
eq "$(count "$NUDGES")" 1 "one nudge"
has "$NUDGES" "session nudge --delivery immediate lx-1 " "the nudge is typed live and names the session id"
has "$NUDGES" "quiet for 15 minutes" "the nudge says how long the pane has been quiet"
has "$NUDGES" "startup wisp reconcile" "the nudge asks for the startup reconcile"
has "$NUDGES" "mol-witness-patrol from check-inbox" "the nudge names the patrol and where to start it"
hasnt "$NUDGES" "limit" "the nudge reads as no provider banner to the quota-park order"
has "$OUT" "1 checked, 1 nudged" "the summary counts it"
has "$(cat "$LIST_LOG")" "GC_NO_API=1 " "the list reads the local path"
has "$(cat "$LIST_LOG")" "session list --json" "the list asks for JSON"

echo "--- what leaves a witness alone"
STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$(iso 0)" "")"); run
eq "$(count "$NUDGES")" 0 "a pane that just printed is working"
eq "$RC" 0 "a working pane is a clean pass"
STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$(iso 659)" "")"); run
eq "$(count "$NUDGES")" 0 "a pane quiet for under the bound is left alone"
STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$(iso 660)" "")"); run
eq "$(count "$NUDGES")" 1 "a pane quiet for exactly the bound is nudged"
STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$(iso 7200)" "$(iso 300)")"); run
eq "$(count "$NUDGES")" 0 "a recent nudge restarts the quiet clock"
STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$(iso 7200)" "$(iso 3600)")"); run
eq "$(count "$NUDGES")" 1 "an old nudge does not hold a quiet pane"
has "$NUDGES" "quiet for 60 minutes" "the quiet clock runs from the newer of the two times"
STUB_LIST=$(list_of "$(row lx-1 "$W" active true "$(iso 7200)" "")"); run
eq "$(count "$NUDGES")" 0 "an attached operator can prompt the session themselves"
for st in asleep drained suspended creating start-pending; do
  STUB_LIST=$(list_of "$(row lx-1 "$W" "$st" false "$(iso 7200)" "")"); run
  eq "$(count "$NUDGES")" 0 "a witness in state $st is the controller's"
done
for t in gc-toolkit/gc-toolkit.refinery gc-toolkit.deacon gc-toolkit.mechanik gc-toolkit/gc-toolkit.polecat gc-toolkit/gc-toolkit.notwitness gc-toolkit/gc-toolkit.witness-helper; do
  STUB_LIST=$(list_of "$(row lx-1 "$t" active false "$(iso 7200)" "")"); run
  eq "$(count "$NUDGES")" 0 "template $t is no witness"
done

echo "--- template shapes that are a witness"
for t in witness gc-toolkit.witness rig/witness rig/binding.witness; do
  STUB_LIST=$(list_of "$(row lx-1 "$t" active false "$(iso 7200)" "")"); run
  eq "$(count "$NUDGES")" 1 "template $t is a witness"
done

echo "--- time formats"
for zone in Z -06:00 +05:30; do
  STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$(iso 7200 "$zone")" "")"); run
  has "$NUDGES" "quiet for 120 minutes" "a quiet pane reads right at offset $zone"
  STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$(iso 60 "$zone")" "")"); run
  eq "$(count "$NUDGES")" 0 "a working pane reads right at offset $zone"
done
FRACTIONAL=$(iso 7200 | sed 's/Z$/.074123Z/')
STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$FRACTIONAL" "")"); run
has "$NUDGES" "quiet for 120 minutes" "fractional seconds parse"

echo "--- a row whose time cannot be read"
STUB_LIST=$(list_of "$(row lx-1 "$W" active false "0001-01-01T00:00:00Z" "")" "$(row lx-2 "rig/gc-toolkit.witness" active false "$(iso 900)" "")"); run
eq "$RC" 1 "an unset time fails the pass"
has "$ERR" "lx-1" "stderr names the unreadable row"
eq "$(count "$NUDGES")" 1 "the other witness is still nudged"
has "$NUDGES" "lx-2" "and that is the readable one"
STUB_LIST=$(list_of "$(row lx-1 "$W" active false "yesterday" "")"); run
eq "$RC" 1 "an unparseable time fails the pass"
eq "$(count "$NUDGES")" 0 "and nudges nothing for that row"
STUB_LIST=$(jq -cn --arg t "$W" '{sessions: [{id: "lx-1", template: $t, state: "active", attached: false}]}'); run
eq "$RC" 1 "a list with no last_active fails the pass"
eq "$(count "$NUDGES")" 0 "and nudges nothing, since nothing was measured"

echo "--- a list that cannot be read"
STUB_LIST='[]'; export STUB_LIST_RC=7; run; unset STUB_LIST_RC
eq "$RC" 1 "a failed list fails the pass"
eq "$(count "$NUDGES")" 0 "a failed list nudges nothing"
has "$ERR" "gc session list failed" "stderr says the list failed"
for shape in '' 'not json' '[]' '{}' '{"sessions": null}'; do
  STUB_LIST="$shape"; run
  eq "$RC" 1 "list output '$shape' fails the pass rather than reading as no witnesses"
  eq "$(count "$NUDGES")" 0 "list output '$shape' nudges nothing"
done
STUB_LIST='{"sessions": []}'; run
eq "$RC" 0 "an empty session list is a clean pass"
has "$OUT" "0 checked, 0 nudged" "and the summary says so"

echo "--- several witnesses"
STUB_LIST=$(list_of \
  "$(row lx-1 "a/gc-toolkit.witness" active false "$(iso 900)" "")" \
  "$(row lx-2 "b/gc-toolkit.witness" active false "$(iso 0)" "")" \
  "$(row lx-3 "c/gc-toolkit.witness" active false "$(iso 900)" "")"); run
eq "$(count "$NUDGES")" 2 "each quiet witness gets its own nudge"
hasnt "$NUDGES" "lx-2" "a working witness among them is left alone"
has "$OUT" "3 checked, 2 nudged" "the summary counts all three"
export STUB_NUDGE_FAIL_ID=lx-1; run; unset STUB_NUDGE_FAIL_ID
eq "$RC" 1 "a failed nudge fails the pass"
has "$ERR" "lx-1" "stderr names the session whose nudge failed"
eq "$(count "$NUDGES")" 2 "a failed nudge does not stop the next witness's"
has "$OUT" "3 checked, 1 nudged" "the summary counts only the accepted nudge"

echo "--- the quiet bound"
STUB_LIST=$(list_of "$(row lx-1 "$W" active false "$(iso 120)" "")")
export WITNESS_NUDGE_QUIET_SECS=60; run
eq "$(count "$NUDGES")" 1 "the bound can be set in the order's environment"
for bad_value in '' abc 10m 0 -5; do
  export WITNESS_NUDGE_QUIET_SECS="$bad_value"; run
  if [ -z "$bad_value" ]; then
    eq "$RC" 0 "an empty bound falls back to the default"
  else
    eq "$RC" 1 "bound '$bad_value' is refused"
    eq "$(count "$(cat "$LIST_LOG")")" 0 "bound '$bad_value' reads nothing"
  fi
done
unset WITNESS_NUDGE_QUIET_SECS

echo "--- the order's wiring"
order_key() { awk -F' = ' -v k="$1" '$1 == k { gsub(/"/, "", $2); print $2; exit }' "$ORDER"; }
eq "$(order_key trigger)" cooldown "the order runs on a cooldown"
eq "$(order_key interval)" 5m "every 5m"
eq "$(order_key scope)" city "once, city-wide"
eq "$(order_key exec)" '$PACK_DIR/assets/scripts/witness-nudge.sh' "it runs this script"
eq "$(order_key idempotent)" true "a contended store does not skip it"
timeout_secs=$(order_key timeout); timeout_secs=${timeout_secs%s}
if [ "$timeout_secs" -lt 300 ]; then ok "a pass ends before the next one starts"; else bad "timeout ${timeout_secs}s reaches the 5m interval"; fi
[ -x "$SCRIPT" ] && ok "the script is executable" || bad "the script is not executable"

echo "--- the bound stays over the formula's inter-cycle wait"
default_quiet=$(sed -n 's/^QUIET_SECS="${WITNESS_NUDGE_QUIET_SECS:-\([0-9]*\)}"$/\1/p' "$SCRIPT")
wait_default=$(awk '/^\[vars\.event_timeout\]/ { inb = 1; next } /^\[/ { inb = 0 } inb && /^default[[:space:]]*=/ { v = $0; gsub(/[^0-9]/, "", v); print v; exit }' "$FORMULA")
if [ -n "$default_quiet" ] && [ -n "$wait_default" ] && [ "$default_quiet" -gt "$wait_default" ]; then
  ok "the ${default_quiet}s bound is over the ${wait_default}s wait"
else
  bad "the bound '$default_quiet' must stay over mol-witness-patrol's event_timeout default '$wait_default'"
fi

echo
echo "witness-nudge.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
