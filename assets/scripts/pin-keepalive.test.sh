#!/usr/bin/env bash
# pin-keepalive.test.sh — the config-drift pin keeper, both modes, hermetic.
#
# pin-keepalive.sh is the exec AND (in --check mode) the check of a
# condition-triggered order, so its whole check contract is its EXIT CODE:
# 0 runs the exec, non-zero does not. This file pins:
#
#   1. THE PREDICATE. A target is conversational (provider match) AND a
#      configured named singleton (configured_named_session=true) AND unpinned.
#      The claude-watch singletons (deacon/witness/refinery), the ephemeral
#      claude pool workers (empty alias / no configured_named_session), and an
#      already-pinned session are each excluded — and a converse sitting that
#      becomes a named conversational session is picked up with no code change.
#   2. FAIL-OPEN. An unreadable roster or session bead RUNS the pass; only
#      verified reads can reach SKIP.
#   3. THE COOLDOWN. A condition trigger has no interval; the cadence is the
#      stamp. A SKIP spends the window, the exec spends it at pass start, a RUN
#      never spends it, and an unwritable stamp refuses to run rather than storm.
#   4. THE READ-ONLY CHECK. --check never calls `gc session pin`; only the exec
#      pins, and it pins exactly the predicate's targets.
#   5. THE ORDER DECLARATION. orders/pin-keepalive.toml is a condition order,
#      city-scoped, naming these two scripts, with a timeout inside the
#      order-tracking-sweep window.
# Hermetic: stubs `gc`; no city, no Dolt, no network, no session touched.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/assets/scripts/pin-keepalive.sh"
WRAP="$ROOT/assets/scripts/pin-keepalive-precheck.sh"
ORDER="$ROOT/orders/pin-keepalive.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pin-keepalive-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

[ -s "$SCRIPT" ] || { echo "missing $SCRIPT"; exit 1; }
[ -x "$SCRIPT" ] || { echo "$SCRIPT is not executable"; exit 1; }

# Ambient city vars would let a case resolve the REAL city instead of the stub;
# strip every resolution source so the fixtures are the only truth.
unset GC_CITY GC_CITY_PATH GC_CITY_ROOT GC_PACK_STATE_DIR GC_RIG GC_RIG_ROOT 2>/dev/null || true

echo "── the scripts are valid shell ──"
bash -n "$SCRIPT" && ok "pin-keepalive.sh: valid bash" || bad "pin-keepalive.sh: valid bash" "bash -n failed"
bash -n "$WRAP"   && ok "pin-keepalive-precheck.sh: valid bash" || bad "pin-keepalive-precheck.sh: valid bash" "bash -n failed"

# --- the stub ----------------------------------------------------------------
# One `gc` serving `service list`, `session list`, `bd show <id>` from $FIX and
# logging `session pin`. The pin log is the read-only proof: --check must never
# add a line to it.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
sub="${1:-}"; shift || true
case "$sub" in
  service)
    [ -n "${STUB_SERVICE_FAIL:-}" ] && exit 1
    printf '{"city_path":"%s"}\n' "${STUB_CITY:-}"; exit 0 ;;
  session)
    verb="${1:-}"; shift || true
    case "$verb" in
      list)
        [ -n "${STUB_SESSION_LIST_FAIL:-}" ] && exit 1
        [ -n "${STUB_SESSION_LIST_GARBAGE:-}" ] && { printf '%s\n' '{"not":"an object with sessions"}'; exit 0; }
        cat "$FIX/sessions.json"; exit 0 ;;
      pin)
        a=""
        while [ $# -gt 0 ]; do case "$1" in --city) shift ;; --*) : ;; *) [ -z "$a" ] && a="$1" ;; esac; shift || true; done
        printf 'pin %s\n' "$a" >> "${STUB_PIN_LOG:?}"
        case " ${STUB_PIN_FAIL:-} " in *" $a "*) exit 1 ;; esac
        exit 0 ;;
      *) exit 0 ;;
    esac ;;
  bd)
    verb="${1:-}"; shift || true
    case "$verb" in
      show)
        id=""
        while [ $# -gt 0 ]; do case "$1" in --city) shift ;; --*) : ;; *) [ -z "$id" ] && id="$1" ;; esac; shift || true; done
        case " ${STUB_SHOW_FAIL:-} " in *" $id "*) exit 1 ;; esac
        f="$FIX/bead_$id.json"
        [ -s "$f" ] || { echo "gc bd: no such bead $id" >&2; exit 1; }
        cat "$f"; exit 0 ;;
      *) exit 0 ;;
    esac ;;
  *) echo "gc stub: unsupported '$sub'" >&2; exit 2 ;;
esac
GC
chmod +x "$TMP/bin/gc"

FIX="$TMP/fix"; mkdir -p "$FIX"
export FIX PATH="$TMP/bin:$PATH"
export STUB_GC_LOG="$TMP/gc.log"
export STUB_PIN_LOG="$TMP/pin.log"
export STUB_CITY="$TMP/city"
STATE="$TMP/state"

# The default roster: mechanik (the one target when unpinned), the claude-watch
# singletons, two ephemeral claude pool workers, and a codex reviewer.
base_sessions() {
  cat > "$FIX/sessions.json" <<'JSON'
{"sessions":[
  {"id":"s-mech","alias":"gc-toolkit.mechanik","session_name":"gc-toolkit.mechanik","provider":"claude","state":"active"},
  {"id":"s-deacon","alias":"gc-toolkit.deacon","session_name":"gc-toolkit.deacon","provider":"claude-watch","state":"active"},
  {"id":"s-refinery","alias":"gc-toolkit/gc-toolkit.refinery","session_name":"gc-toolkit--gc-toolkit__refinery","provider":"claude-watch","state":"asleep"},
  {"id":"s-pol1","alias":"","session_name":"gc-toolkit--gc-toolkit__polecat-1-pool","provider":"claude","state":"active"},
  {"id":"s-conv","alias":"","session_name":"gc-toolkit--gc-toolkit__converse-2-pool","provider":"claude","state":"asleep"},
  {"id":"s-codex","alias":"gc-toolkit/gc-toolkit.hicks","session_name":"gc-toolkit--gc-toolkit__polecat-lx-hicks","provider":"codex","state":"active"}
]}
JSON
}
# A session bead: id + metadata. Pool workers and the codex reviewer are excluded
# before any bead read, so only the named claude/claude-watch singletons need one.
set_bead() { # set_bead <id> <metadata-json>
  printf '[{"id":"%s","metadata":%s}]\n' "$1" "$2" > "$FIX/bead_$1.json"
}
base_beads() {
  set_bead s-mech     '{"configured_named_session":"true","session_origin":"named","pin_awake":"true"}'
  set_bead s-deacon   '{"configured_named_session":"true","session_origin":"named"}'
  set_bead s-refinery '{"configured_named_session":"true","session_origin":"named","configured_named_mode":"on_demand"}'
}
reset_fix() { base_sessions; base_beads; }

# OUT and RC are set in the CALLER: a $(...) capture would run the script in a
# subshell and the exit code — the whole contract — would be the subshell's.
OUT=""; RC=0
run_check() { # run_check [args...]
  rm -rf "$STATE"; : > "$STUB_PIN_LOG"; : > "$STUB_GC_LOG"
  unset STUB_SERVICE_FAIL STUB_SESSION_LIST_FAIL STUB_SESSION_LIST_GARBAGE STUB_SHOW_FAIL STUB_PIN_FAIL 2>/dev/null || true
  OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" "$SCRIPT" --check "$@" 2>&1)"; RC=$?
}
run_exec() { # run_exec [args...]
  : > "$STUB_PIN_LOG"; : > "$STUB_GC_LOG"
  unset STUB_SERVICE_FAIL STUB_SESSION_LIST_FAIL STUB_SESSION_LIST_GARBAGE STUB_SHOW_FAIL STUB_PIN_FAIL 2>/dev/null || true
  OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" "$SCRIPT" "$@" 2>&1)"; RC=$?
}
pinlog() { cat "$STUB_PIN_LOG" 2>/dev/null; }

# ============================================================================
# 1. THE PREDICATE (check mode)
# ============================================================================
echo "── mechanik unpinned is the one target; the pass runs ──"
reset_fix; set_bead s-mech '{"configured_named_session":"true","session_origin":"named"}'
run_check
eq "$RC" "0" "an unpinned standing conversational session RUNs the pass"
has "$OUT" "RUN:" "the verdict is RUN"
has "$OUT" "gc-toolkit.mechanik" "and names mechanik as the unpinned session"
eq "$(pinlog)" "" "the check pins nothing — it is read-only"

echo "── mechanik already pinned: nothing owed, the board skips ──"
reset_fix   # base mechanik bead carries pin_awake=true
run_check
eq "$RC" "1" "an all-pinned roster SKIPs — no pass"
has "$OUT" "SKIP:" "the verdict is SKIP"
eq "$(pinlog)" "" "still pins nothing"

echo "── the claude-watch singletons are NOT conversational — excluded ──"
# deacon/refinery are unpinned and configured_named_session=true, but provider
# claude-watch. With mechanik pinned, the only survivors would be them; the board
# must still skip, or the order would pin an on-demand refinery awake.
reset_fix
run_check
eq "$RC" "1" "deacon/refinery (claude-watch) do not make the pass run"
hasnt "$OUT" "refinery" "and refinery is never named a target"

echo "── the ephemeral claude pool workers are NOT named — excluded ──"
# s-pol1/s-conv are provider=claude but have no alias and no session bead; the
# alias pre-filter drops them before any bead read. Prove the bead read never
# happened for them AND the board skips.
reset_fix
run_check
eq "$RC" "1" "empty-alias claude pool workers do not make the pass run"
hasnt "$(cat "$STUB_GC_LOG")" "bd show s-pol1" "no bead read for a pool worker (alias pre-filter)"
hasnt "$(cat "$STUB_GC_LOG")" "bd show s-conv" "no bead read for the converse pool worker"

echo "── a claude pool worker that somehow carries an alias is still not named ──"
# The authoritative gate is configured_named_session, not the alias pre-filter:
# a claude session with an alias but no configured_named_session is excluded.
reset_fix
cat > "$FIX/sessions.json" <<'JSON'
{"sessions":[
  {"id":"s-mech","alias":"gc-toolkit.mechanik","provider":"claude","state":"active"},
  {"id":"s-rogue","alias":"gc-toolkit/gc-toolkit.nux","provider":"claude","state":"active"}
]}
JSON
set_bead s-rogue '{"session_origin":"ephemeral"}'
run_check
eq "$RC" "1" "a claude session without configured_named_session=true is not a target"
hasnt "$OUT" "nux" "and the ephemeral session is never named"

echo "── a converse sitting reshaped to a named conversational session inherits ──"
# The whole point of the predicate: no code change when converse becomes named.
reset_fix
cat > "$FIX/sessions.json" <<'JSON'
{"sessions":[
  {"id":"s-mech","alias":"gc-toolkit.mechanik","provider":"claude","state":"active"},
  {"id":"s-conv1","alias":"gc-toolkit.converse-1","provider":"claude","state":"active"}
]}
JSON
set_bead s-conv1 '{"configured_named_session":"true","session_origin":"named"}'
run_check
eq "$RC" "0" "a newly-named converse conversational session makes the pass run"
has "$OUT" "gc-toolkit.converse-1" "and it is named a target with no code change"

# ============================================================================
# 2. FAIL-OPEN (check mode) — only verified reads reach SKIP
# ============================================================================
echo "── an unreadable roster RUNS the pass ──"
reset_fix
rm -rf "$STATE"; : > "$STUB_PIN_LOG"
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" STUB_SESSION_LIST_FAIL=1 "$SCRIPT" --check 2>&1)"; RC=$?
eq "$RC" "0" "a failed session list RUNs the pass — not an empty roster"
has "$OUT" "UNREADABLE" "and says the probe was unreadable"
hasnt "$OUT" "SKIP:" "a failed roster read never skips"

echo "── a non-object roster answer RUNS the pass ──"
reset_fix
rm -rf "$STATE"
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" STUB_SESSION_LIST_GARBAGE=1 "$SCRIPT" --check 2>&1)"; RC=$?
eq "$RC" "0" "a roster that is not {sessions:[...]} is unreadable, not empty"
has "$OUT" "UNREADABLE" "and says so"

echo "── an unreadable session bead RUNS the pass (fail-open on the probe) ──"
reset_fix; set_bead s-mech '{"configured_named_session":"true"}'
rm -rf "$STATE"
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" STUB_SHOW_FAIL="s-mech" "$SCRIPT" --check 2>&1)"; RC=$?
eq "$RC" "0" "a candidate whose bead will not read RUNs the pass"
has "$OUT" "UNREADABLE" "and reports the probe failure"

echo "── no resolvable city SKIPs rather than storm a doomed exec ──"
rm -rf "$STATE"
OUT="$(env -u PIN_KEEPALIVE_CITY PIN_KEEPALIVE_STATE_DIR="$STATE" STUB_SERVICE_FAIL=1 "$SCRIPT" --check 2>&1)"; RC=$?
eq "$RC" "1" "no city → SKIP"
has "$OUT" "cannot resolve the city" "and says why"

# ============================================================================
# 3. THE COOLDOWN
# ============================================================================
echo "── a RUN verdict never spends the window ──"
reset_fix; set_bead s-mech '{"configured_named_session":"true"}'   # unpinned → RUN
run_check
eq "$RC" "0" "the run verdict is reached"
[ -f "$STATE/last-pass" ] && bad "a RUN does not spend the window" "the check stamped last-pass" \
    || ok "a RUN does not spend the window"
# Repeated evaluation keeps answering RUN — the check is not a one-shot latch.
PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" "$SCRIPT" --check >/dev/null 2>&1; RC2=$?
eq "$RC2" "0" "a second evaluation still RUNs — no latch"

echo "── a proven-quiet SKIP spends the window itself ──"
reset_fix   # mechanik pinned → SKIP
run_check
eq "$RC" "1" "the quiet roster skips"
[ -s "$STATE/last-pass" ] && ok "a SKIP spends the window" \
    || bad "a SKIP spends the window" "no last-pass — every tick would reclassify"
# The next evaluation answers from the window, silently, reading nothing.
: > "$STUB_GC_LOG"
OUT2="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" "$SCRIPT" --check 2>&1)"; RC2=$?
eq "$RC2" "1" "the next tick inside the window still skips"
eq "$OUT2" "" "and says nothing — the answer on almost every tick"
eq "$(wc -c < "$STUB_GC_LOG" | tr -d ' ')" "0" "and read nothing at all — the window bounds the poll"

echo "── --force reclassifies inside the window without moving it ──"
STAMPED="$(cat "$STATE/last-pass")"
sleep 1
OUT3="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" "$SCRIPT" --check --force 2>&1)"; RC3=$?
eq "$RC3" "1" "--force reclassifies the quiet roster"
eq "$(cat "$STATE/last-pass")" "$STAMPED" "--force leaves the window where it found it"

echo "── once the window elapses the pass classifies again ──"
printf '%s\n' "$(( $(date -u +%s) - 100000 ))" > "$STATE/last-pass"
reset_fix; set_bead s-mech '{"configured_named_session":"true"}'
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" "$SCRIPT" --check 2>&1)"; RC=$?
eq "$RC" "0" "an elapsed window reclassifies and runs"
# A shorter interval is honoured from one place.
printf '%s\n' "$(( $(date -u +%s) - 100 ))" > "$STATE/last-pass"
reset_fix
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" PIN_KEEPALIVE_INTERVAL=60 "$SCRIPT" --check 2>&1)"; RC=$?
eq "$RC" "1" "PIN_KEEPALIVE_INTERVAL is the single source of the cadence (100s > 60s → skip)"

echo "── an unwritable state dir refuses to run rather than storm ──"
if [ "$(id -u)" -eq 0 ]; then
  ok "unwritable state dir refuses (skipped: running as root)"
else
  reset_fix; set_bead s-mech '{"configured_named_session":"true"}'
  mkdir -p "$TMP/nowrite"; chmod 500 "$TMP/nowrite"
  OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$TMP/nowrite/state" "$SCRIPT" --check 2>&1)"; RC=$?
  chmod 700 "$TMP/nowrite"
  eq "$RC" "1" "an unwritable stamp refuses to run"
  has "$OUT" "CANNOT WRITE" "and says exactly what is broken"
fi

echo "── check and exec share one stamp path and one atomic writer ──"
grep -q 'STAMP="\$STATE_DIR/last-pass"' "$SCRIPT" && ok "the stamp path is \$STATE_DIR/last-pass" \
    || bad "the stamp path is \$STATE_DIR/last-pass" "the window is keyed elsewhere"
eq "$(grep -cE '> *"\$STAMP"' "$SCRIPT")" "0" "the stamp is never truncated in place"
eq "$(grep -c 'spend_window "' "$SCRIPT")" "3" "spend_window is called in the three intended places (check-skip, no-city, exec-start)"

# ============================================================================
# 4. THE READ-ONLY CHECK and the EXEC action
# ============================================================================
echo "── the exec pins exactly the predicate's targets ──"
reset_fix; set_bead s-mech '{"configured_named_session":"true"}'   # unpinned
run_exec
eq "$RC" "0" "the exec completes"
eq "$(pinlog)" "pin gc-toolkit.mechanik" "it pins mechanik, and only mechanik"
has "$OUT" "pinned 1, failed 0" "and reports one pin"
[ -s "$STATE/last-pass" ] && ok "the exec stamps the window at pass start" \
    || bad "the exec stamps the window at pass start" "no last-pass"

echo "── the exec pins nothing when every target is already pinned ──"
reset_fix   # mechanik pinned
run_exec
eq "$RC" "0" "the exec completes with nothing to do"
eq "$(pinlog)" "" "no session is pinned"

echo "── the exec never pins a watcher or a pool worker ──"
reset_fix; set_bead s-mech '{"configured_named_session":"true"}'
run_exec
hasnt "$(pinlog)" "refinery" "refinery (claude-watch) is never pinned"
hasnt "$(pinlog)" "deacon" "deacon (claude-watch) is never pinned"
hasnt "$(pinlog)" "polecat" "a pool worker is never pinned"

echo "── two named conversational sessions are both pinned ──"
reset_fix
cat > "$FIX/sessions.json" <<'JSON'
{"sessions":[
  {"id":"s-mech","alias":"gc-toolkit.mechanik","provider":"claude","state":"active"},
  {"id":"s-conv1","alias":"gc-toolkit.converse-1","provider":"claude","state":"active"}
]}
JSON
set_bead s-mech  '{"configured_named_session":"true"}'
set_bead s-conv1 '{"configured_named_session":"true"}'
run_exec
has "$(pinlog)" "pin gc-toolkit.mechanik" "mechanik is pinned"
has "$(pinlog)" "pin gc-toolkit.converse-1" "converse-1 is pinned"
has "$OUT" "pinned 2, failed 0" "and both are reported"

echo "── --dry-run pins nothing and stamps nothing ──"
reset_fix; set_bead s-mech '{"configured_named_session":"true"}'
rm -rf "$STATE"
run_exec --dry-run
eq "$(pinlog)" "" "dry-run pins nothing"
has "$OUT" "DRY-RUN would pin gc-toolkit.mechanik" "but reports what it would pin"
[ -f "$STATE/last-pass" ] && bad "dry-run does not stamp" "it wrote last-pass" || ok "dry-run does not stamp"

echo "── an unreadable roster aborts the exec (non-zero) ──"
reset_fix
: > "$STUB_PIN_LOG"
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" STUB_SESSION_LIST_FAIL=1 "$SCRIPT" 2>&1)"; RC=$?
eq "$RC" "1" "an unreadable roster aborts the exec"
has "$OUT" "ABORTED" "and says it aborted"

echo "── an unreadable session bead does not drop its target — the exec pins it fail-open ──"
# probe_fail must not read as "nothing owed": the check RUNs on it, and the exec
# must attempt the idempotent pin for the candidate it could not confirm — else a
# config-drift restart could take down the very session this order protects while
# the pass records a clean no-op and spends the cooldown window.
reset_fix; set_bead s-mech '{"configured_named_session":"true"}'
: > "$STUB_PIN_LOG"; rm -rf "$STATE"
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" STUB_SHOW_FAIL="s-mech" "$SCRIPT" 2>&1)"; RC=$?
eq "$RC" "0" "the exec completes — probe_fail is not list_fail, so it does not abort"
eq "$(pinlog)" "pin gc-toolkit.mechanik" "the unreadable candidate is pinned anyway (fail-open)"
has "$OUT" "pinned 1, failed 0" "the pass reports the fail-open pin, not a clean pinned-0 no-op"
has "$OUT" "probe_status=probe_fail" "and surfaces that a probe was unreadable"

echo "── a pin failure is reported but does not abort the pass ──"
reset_fix; set_bead s-mech '{"configured_named_session":"true"}'
: > "$STUB_PIN_LOG"; rm -rf "$STATE"
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" STUB_PIN_FAIL="gc-toolkit.mechanik" "$SCRIPT" 2>&1)"; RC=$?
eq "$RC" "0" "the pass ran, even though the pin failed"
has "$OUT" "FAILED to pin gc-toolkit.mechanik" "the failure is reported"
[ -s "$STATE/last-pass" ] && ok "the window is still stamped so the next pass retries after the interval" \
    || bad "the window is still stamped" "no last-pass"

echo "── no resolvable city aborts the exec ──"
rm -rf "$STATE"
OUT="$(env -u PIN_KEEPALIVE_CITY PIN_KEEPALIVE_STATE_DIR="$STATE" STUB_SERVICE_FAIL=1 "$SCRIPT" 2>&1)"; RC=$?
eq "$RC" "1" "no city → the exec aborts"
has "$OUT" "cannot resolve the city" "and says why"

echo "── source: gc session pin lives only in the exec path ──"
# The read-only contract, structurally: the one pin call site is guarded by the
# exec branch. The behavioural proof is every 'the check pins nothing' above;
# this pins the source so a refactor cannot move the call into the check.
eq "$(grep -c 'bounded gc session pin' "$SCRIPT")" "1" "there is exactly one gc session pin call site"

# ============================================================================
# 5. FAIL-OPEN on abort, per mode
# ============================================================================
echo "── an abort before the check decides RUNS the pass ──"
reset_fix
sed 's|^trap on_exit EXIT$|trap on_exit EXIT\nexit 3|' "$SCRIPT" > "$TMP/aborting.sh"
chmod +x "$TMP/aborting.sh"
grep -qx 'exit 3' "$TMP/aborting.sh" && ok "abort injection landed" \
    || bad "abort injection landed" "the trap line moved — this test checks nothing"
rm -rf "$STATE"
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" "$TMP/aborting.sh" --check 2>&1)"; RC=$?
eq "$RC" "0" "an abort before deciding RUNs the pass (check mode fails open)"
has "$OUT" "ABORTED before deciding" "and says it aborted"
OUT="$(PIN_KEEPALIVE_CITY="$TMP/city" PIN_KEEPALIVE_STATE_DIR="$STATE" "$TMP/aborting.sh" 2>&1)"; RC=$?
eq "$RC" "1" "an abort in the exec is a non-zero exit"

echo "── the verdict is logged, since a condition check's stdout is discarded ──"
reset_fix
run_check
[ -s "$STATE/pass.log" ] && ok "the verdict is appended to pass.log" \
    || bad "the verdict is appended to pass.log" "no log"

# ============================================================================
# 6. THE ORDER DECLARATION
# ============================================================================
echo "── orders/pin-keepalive.toml is a city-scoped condition order ──"
[ -s "$ORDER" ] || bad "orders/pin-keepalive.toml exists" "missing $ORDER"
O="$(cat "$ORDER" 2>/dev/null)"
has "$O" 'trigger = "condition"' "it is condition-triggered"
has "$O" 'scope = "city"' "it is city-scoped (mechanik is a city session)"
has "$O" 'assets/scripts/pin-keepalive-precheck.sh' "check names the precheck wrapper"
has "$O" 'assets/scripts/pin-keepalive.sh' "exec names the main script"
hasnt "$O" 'interval =' "a condition trigger declares no interval"
# The exec must finish inside the order-tracking-sweep window (10m) or a swept
# tracking bead un-gates the single-flight guard.
to="$(awk -F'"' '/^[[:space:]]*timeout[[:space:]]*=/{print $2}' "$ORDER" | head -1)"
tosecs="${to%s}"
case "$tosecs" in ''|*[!0-9]*) tosecs=0 ;; esac
[ "$tosecs" -gt 0 ] && [ "$tosecs" -le 600 ] && ok "timeout $to is inside the 10m tracking-sweep window" \
    || bad "timeout inside the tracking-sweep window" "timeout is '$to'"

# ============================================================================
# 7. THE PRECHECK WRAPPER delegates to --check
# ============================================================================
echo "── the precheck wrapper runs the main script in --check mode ──"
# Copy both into a private dir so the wrapper's sibling resolution hits the copy,
# and replace the main script with a shim that records its args.
mkdir -p "$TMP/wrapdir"
cp "$WRAP" "$TMP/wrapdir/pin-keepalive-precheck.sh"
cat > "$TMP/wrapdir/pin-keepalive.sh" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$WRAP_ARGS"
exit 0
SHIM
chmod +x "$TMP/wrapdir/pin-keepalive-precheck.sh" "$TMP/wrapdir/pin-keepalive.sh"
WRAP_ARGS="$TMP/wrap.args" "$TMP/wrapdir/pin-keepalive-precheck.sh" >/dev/null 2>&1
has "$(cat "$TMP/wrap.args" 2>/dev/null)" "--check" "the wrapper forwards --check to the main script"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
