#!/usr/bin/env bash
# patrol-continue-hook.test.sh — hermetic test for the Stop hook of the deacon
# and the witness, overlays/cycle-recycle/.claude/hooks/patrol-continue.sh.
#
# At a deacon or witness turn boundary the hook prints a block decision that
# hands the next patrol cycle back. It prints nothing for any other agent, while
# a background task runs, or on a payload it cannot read. After MAX_RAPID stops
# in a row that each came within MIN_TURN seconds of a hand-back, it resets the
# session instead, unless an operator is attached or, for the deacon, its
# recovery line does not reach the incident ledger. A reset that fails or
# outlasts its bound hands the turn back. Every path exits 0, so the exit code
# tells nothing apart; this test reads stdout, the state file and the calls the
# hook makes.
#
# It runs the SHIPPED script, never a copy. gc and tmux are stubbed by pointing
# HOME at the sandbox: the hook prepends "$HOME/go/bin" to PATH itself, so a
# stub placed there wins over the real one. The ledger is stubbed at the path
# the hook resolves under GC_CITY_PATH. Every run starts from env -i, so no live
# GC_* or TMUX variable reaches the hook.
#
# The test lives under assets/scripts/ rather than beside the hook because
# everything under overlays/cycle-recycle/.claude/ is staged into the patrol
# agents' work dirs, where a test file would ship to production sessions.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
HOOK="$REPO/overlays/cycle-recycle/.claude/hooks/patrol-continue.sh"
SETTINGS="$REPO/overlays/cycle-recycle/.claude/settings.json"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1', want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in: $1" ;; esac; }

[ -s "$HOOK" ] || { echo "FATAL: missing hook script: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gctk-patrol-continue-hook-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

# The gc stub logs every call and exits GC_STUB_RC, so a reset reads as one
# "session reset <target>" line.
mkdir -p "$SANDBOX/home/go/bin"
cat > "$SANDBOX/home/go/bin/gc" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GC_LOG"
exit "${GC_STUB_RC:-0}"
STUB
chmod +x "$SANDBOX/home/go/bin/gc"

# The tmux stub logs every call and answers the attached-client count in
# TMUX_ATTACHED, or fails with TMUX_STUB_RC and prints nothing.
cat > "$SANDBOX/home/go/bin/tmux" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_LOG"
[ "${TMUX_STUB_RC:-0}" = 0 ] || exit "$TMUX_STUB_RC"
printf '%s\n' "${TMUX_ATTACHED:-0}"
STUB
chmod +x "$SANDBOX/home/go/bin/tmux"

# The timeout stub logs its bound and runs the command, or exits TIMEOUT_STUB_RC
# as a command that outlasted its bound does.
cat > "$SANDBOX/home/go/bin/timeout" <<'STUB'
#!/bin/sh
printf '%s\n' "$1" >> "$TIMEOUT_LOG"
[ "${TIMEOUT_STUB_RC:-0}" = 0 ] || exit "$TIMEOUT_STUB_RC"
shift
exec "$@"
STUB
chmod +x "$SANDBOX/home/go/bin/timeout"

# The ledger stub sits where the hook looks for gc-deacon-ledger.sh. It logs
# every call and exits LEDGER_STUB_RC, as the real script exits 1 when its
# append does not land.
CITY="$SANDBOX/city"
mkdir -p "$CITY/rigs/gc-toolkit/assets/scripts"
cat > "$CITY/rigs/gc-toolkit/assets/scripts/gc-deacon-ledger.sh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$LEDGER_LOG"
exit "${LEDGER_STUB_RC:-0}"
STUB
chmod +x "$CITY/rigs/gc-toolkit/assets/scripts/gc-deacon-ledger.sh"

STATE_DIR="$SANDBOX/tmp"
mkdir -p "$STATE_DIR"

# run_hook <agent> <payload> [VAR=value ...] — run the shipped hook as a Stop
# event delivers it; stdout goes to $OUT, stderr to $ERR, and the exit code to
# $RC. Extra arguments are added to the environment.
run_hook() {
    local agent="$1" payload="$2"; shift 2
    : > "$SANDBOX/gc.log"; : > "$SANDBOX/ledger.log"; : > "$SANDBOX/tmux.log"; : > "$SANDBOX/timeout.log"
    printf '%s' "$payload" | env -i HOME="$SANDBOX/home" PATH="/usr/bin:/bin:$(dirname "$(command -v jq)")" \
        TMPDIR="$STATE_DIR" GC_AGENT="$agent" GC_ALIAS="gc-toolkit.deacon" \
        GC_SESSION_ID="hq-sess" GC_SESSION_NAME="gc-toolkit__deacon" GC_CITY_PATH="$CITY" \
        GC_LOG="$SANDBOX/gc.log" LEDGER_LOG="$SANDBOX/ledger.log" TMUX_LOG="$SANDBOX/tmux.log" TIMEOUT_LOG="$SANDBOX/timeout.log" "$@" \
        sh "$HOOK" > "$SANDBOX/out" 2> "$SANDBOX/err"
    RC=$?
    OUT="$(cat "$SANDBOX/out")"
    ERR="$(cat "$SANDBOX/err")"
}

STATE="$STATE_DIR/gc-patrol-continue.hq-sess"
payload() { # payload <session-id> [background_tasks-json]
    jq -cn --arg sid "$1" --argjson bg "${2:-[]}" \
        '{session_id: $sid, transcript_path: "/dev/null", hook_event_name: "Stop", stop_hook_active: false, background_tasks: $bg}'
}
RUNNING='[{"id":"b1","type":"shell","status":"running","description":"wait out the cycle","command":"sleep 600"}]'
FINISHED='[{"id":"b1","type":"shell","status":"completed","description":"wait out the cycle","command":"sleep 600"}]'

echo "== role gate: only the deacon and the witness are handed back their turn =="
for agent in "gc-toolkit/gc-toolkit.refinery" "gc-toolkit.mechanik" "gc-toolkit.polecat" ""; do
    rm -f "$STATE"
    run_hook "$agent" "$(payload s1)"
    eq "$OUT|$RC" "|0" "${agent:-<no GC_AGENT>}: no output, exit 0"
    [ ! -e "$STATE" ] && ok "${agent:-<no GC_AGENT>}: no state written" || bad "${agent:-<no GC_AGENT>}: no state written" "found $STATE"
done

echo "== a deacon or witness turn boundary is handed back with its own patrol =="
# Each entry is the agent, then the role whose patrol formula the reason names.
for entry in "gc-toolkit.deacon deacon" "deacon deacon" "gc-toolkit/gc-toolkit.witness witness" "rig-a/gc-toolkit.witness witness"; do
    agent="${entry% *}"; role="${entry##* }"
    case "$role" in deacon) other=witness ;; *) other=deacon ;; esac
    rm -f "$STATE"
    run_hook "$agent" "$(payload s1)"
    eq "$RC" "0" "$agent: exit 0"
    eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "$agent: the decision blocks the stop"
    REASON="$(printf '%s' "$OUT" | jq -r '.reason' 2>/dev/null)"
    has "$REASON" "next-iteration" "$agent: the reason names next-iteration"
    has "$REASON" "a $role turn" "$agent: the reason names the $role's turn"
    has "$REASON" "mol-$role-patrol from check-inbox" "$agent: the reason names the $role's patrol formula"
    has "$REASON" "finish its inter-cycle wait if you skipped it" "$agent: the reason names the inter-cycle wait"
    case "$REASON" in
        *"mol-$other-patrol"*) bad "$agent: the reason names no other patrol" "mol-$other-patrol in: $REASON" ;;
        *) ok "$agent: the reason names no other patrol" ;;
    esac
    eq "$(printf '%s' "$OUT" | jq -r 'keys | join(",")' 2>/dev/null)" "decision,reason" "$agent: stdout is the decision object and nothing else"
    eq "$(cut -d' ' -f1,3 < "$STATE")" "s1 0" "$agent: the state names this conversation, no rapid stops"
done

rm -f "$STATE"
run_hook gc-toolkit.deacon '{"session_id":"s1","hook_event_name":"Stop"}'
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a payload with no task list (an older Claude Code) is handed back"

echo "== a running background task resumes the session itself =="
rm -f "$STATE"
run_hook gc-toolkit.deacon "$(payload s1 "$RUNNING")"
eq "$OUT|$RC" "|0" "a running background task: no output, exit 0"
[ ! -e "$STATE" ] && ok "a running background task: no hand-back counted" || bad "a running background task: no hand-back counted" "found $STATE"
run_hook gc-toolkit.deacon "$(payload s1 "$FINISHED")"
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a finished background task does not hold the hand-back"

echo "== an unreadable payload lets the turn end =="
for p in 'not json' '{"hook_event_name":"Stop"}' '{"session_id":"../x","background_tasks":[]}' '{"session_id":"s1","background_tasks":"x"}'; do
    rm -f "$STATE"
    run_hook gc-toolkit.deacon "$p"
    eq "$OUT|$RC" "|0" "payload $p: no output, exit 0"
done

echo "== the loop guard =="
now=$(date +%s)
printf 's1 %s 0\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)"
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a stop right after a hand-back is handed back again"
has "$(printf '%s' "$OUT" | jq -r '.reason' 2>/dev/null)" "too soon for a cycle and its inter-cycle wait" "the repeat hand-back says the last one was too short for a cycle and its wait"
eq "$(cut -d' ' -f3 < "$STATE")" "1" "the rapid stop is counted"

printf 's1 %s 1\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)"
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a second rapid stop is still handed back"
eq "$(cut -d' ' -f3 < "$STATE")" "2" "the second rapid stop is counted"
eq "$(cat "$SANDBOX/gc.log")" "" "no reset before the limit"

printf 's1 %s 2\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)"
eq "$OUT|$RC" "|0" "the third rapid stop is not handed back"
eq "$(cat "$SANDBOX/gc.log")" "session reset gc-toolkit.deacon" "the third rapid stop resets the session by its alias"
has "$(cat "$SANDBOX/ledger.log")" "append recovery patrol-continue reset the session: 3 turns in a row" "the reset is recorded in the ledger as a recovery"
eq "$(cat "$STATE")" "s1 0 0" "the reset starts the count over"

printf 's1 %s 2\n' "$((now - 1000))" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)"
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a stop long after the last hand-back is handed back"
eq "$(cut -d' ' -f3 < "$STATE")" "0" "a stop after a real cycle clears the rapid count"
eq "$(cat "$SANDBOX/gc.log")" "" "a stop after a real cycle resets nothing"

printf 's0 %s 2\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)"
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a new conversation is handed back"
eq "$(cut -d' ' -f1,3 < "$STATE")" "s1 0" "a new conversation starts the count over"

printf 'garbage line\n' > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)"
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "an unreadable state file counts nothing and hands back"

echo "== the reset's target and failure =="
printf 's1 %s 2\n' "$now" > "$STATE_DIR/gc-patrol-continue.hq-other"
run_hook gc-toolkit.deacon "$(payload s1)" GC_ALIAS= GC_SESSION_ID=hq-other
eq "$(cat "$SANDBOX/gc.log")" "session reset hq-other" "with no alias the reset names the session id, and the state is keyed by it"

printf 's1 %s 2\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)" GC_STUB_RC=1
eq "$RC" "0" "a failed reset still exits 0"
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a failed reset hands the turn back"
REASON="$(printf '%s' "$OUT" | jq -r '.reason' 2>/dev/null)"
has "$REASON" "could not reset the session" "the hand-back says the reset failed"
has "$REASON" "run the inter-cycle wait before you retry" "the hand-back paces a session whose bead commands are failing"
has "$ERR" "gc session reset gc-toolkit.deacon failed" "a failed reset is reported on stderr"
eq "$(cut -d' ' -f1,3 < "$STATE")" "s1 0" "a failed reset starts the count over"
[ "$(cut -d' ' -f2 < "$STATE")" -gt 0 ] && ok "a failed reset records its hand-back, so the next stop is counted" || bad "a failed reset records its hand-back, so the next stop is counted" "state: $(cat "$STATE")"

printf 's1 %s 2\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)" TIMEOUT_STUB_RC=124
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a reset that outlasts its bound hands the turn back"
RESET_BOUND_SET=$(sed -n 's/^RESET_BOUND=\([0-9][0-9]*\).*/\1/p' "$HOOK")
eq "$(cat "$SANDBOX/timeout.log")" "$RESET_BOUND_SET" "the reset runs under the hook's bound"

printf 's1 %s 2\n' "$now" > "$STATE_DIR/gc-patrol-continue.s1"
run_hook gc-toolkit.deacon "$(payload s1)" GC_ALIAS= GC_SESSION_ID=
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a session nothing names is handed back"
eq "$(cat "$SANDBOX/gc.log")" "" "a session nothing names resets nothing"
has "$ERR" "nothing to reset" "a session nothing names is reported on stderr"

# With no timeout on PATH the reset runs unbounded, and the hook's own timeout
# in the overlay's settings is then its only bound.
BARE="$SANDBOX/bare"
mkdir -p "$BARE/go/bin" "$BARE/bin"
cp "$SANDBOX/home/go/bin/gc" "$BARE/go/bin/gc"
for tool in sh cat date jq; do ln -s "$(type -P "$tool")" "$BARE/bin/$tool"; done
printf 's1 %s 2\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)" HOME="$BARE" PATH="$BARE/bin"
eq "$(cat "$SANDBOX/gc.log")" "session reset gc-toolkit.deacon" "with no timeout on PATH the reset still runs"
eq "$(cat "$SANDBOX/timeout.log")" "" "with no timeout on PATH nothing bounds the reset"

echo "== an outage that fails every reset never ends the turn =="
# A store outage fails each cycle quickly, and the reset needs the same store.
# Each stop here comes right after the last hand-back, and the hook writes the
# time itself. Nothing else would give an ended turn another one.
WSTATE="$STATE_DIR/gc-patrol-continue.hq-witness"
WITNESS_ENV=(GC_ALIAS=rig-a/gc-toolkit.witness GC_SESSION_ID=hq-witness GC_SESSION_NAME=rig-a--gc-toolkit__witness)
rm -f "$WSTATE"
BLOCKS=0; RESETS=""
for stop in 1 2 3 4 5 6 7 8; do
    run_hook rig-a/gc-toolkit.witness "$(payload s1)" "${WITNESS_ENV[@]}" GC_STUB_RC=1
    [ "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" = block ] && BLOCKS=$((BLOCKS + 1))
    [ -s "$SANDBOX/gc.log" ] && RESETS="$RESETS $stop"
done
eq "$BLOCKS" "8" "every stop of a witness in an outage is handed back"
eq "$RESETS" " 4 7" "the reset is tried after each run of three rapid stops"
has "$(printf '%s' "$OUT" | jq -r '.reason' 2>/dev/null)" "mol-witness-patrol from check-inbox" "the outage's hand-back names the witness's patrol"
eq "$(cat "$SANDBOX/ledger.log")" "" "a witness's failed reset writes no ledger line"

echo "== an attached operator holds the reset =="
IN_TMUX="TMUX=$SANDBOX/tmux-socket,1,0"
printf 's1 %s 2\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)" "$IN_TMUX" TMUX_ATTACHED=1
eq "$OUT|$RC" "|0" "an attached operator: the third rapid stop is not handed back"
eq "$(cat "$SANDBOX/gc.log")" "" "an attached operator: the session is not reset"
eq "$(cat "$SANDBOX/ledger.log")" "" "an attached operator: no recovery line is written"
eq "$(cat "$STATE")" "s1 $now 2" "an attached operator: the state file keeps its count"
has "$(cat "$SANDBOX/tmux.log")" "session_attached" "the attachment is read from tmux"

run_hook gc-toolkit.deacon "$(payload s1)" "$IN_TMUX" TMUX_STUB_RC=1
eq "$OUT|$RC" "|0" "an unreadable attachment: no output, exit 0"
eq "$(cat "$SANDBOX/gc.log")" "" "an unreadable attachment holds the reset"

run_hook gc-toolkit.deacon "$(payload s1)" "$IN_TMUX" TMUX_ATTACHED=0
eq "$(cat "$SANDBOX/gc.log")" "session reset gc-toolkit.deacon" "with nobody attached, the next rapid stop takes the held reset"

printf 's1 %s 1\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)" "$IN_TMUX" TMUX_ATTACHED=1
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "an attached operator does not hold a hand-back below the limit"
eq "$(cat "$SANDBOX/tmux.log")" "" "below the limit the hook does not ask tmux"

echo "== the reset waits for its recovery line =="
printf 's1 %s 2\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)" LEDGER_STUB_RC=1
eq "$OUT|$RC" "|0" "a failed ledger append: the third rapid stop is not handed back"
has "$(cat "$SANDBOX/ledger.log")" "append recovery" "a failed ledger append: the recovery line was tried"
eq "$(cat "$SANDBOX/gc.log")" "" "a failed ledger append: the session is not reset"
eq "$(cat "$STATE")" "s1 $now 2" "a failed ledger append: the state file keeps its count"
has "$ERR" "the recovery line did not reach the ledger" "a failed ledger append is reported on stderr"

run_hook gc-toolkit.deacon "$(payload s1)"
has "$(cat "$SANDBOX/ledger.log")" "append recovery" "the next rapid stop writes the recovery line"
eq "$(cat "$SANDBOX/gc.log")" "session reset gc-toolkit.deacon" "the next rapid stop takes the held reset"
eq "$(cat "$STATE")" "s1 0 0" "the reset that follows the line starts the count over"

printf 's1 %s 2\n' "$now" > "$STATE"
run_hook gc-toolkit.deacon "$(payload s1)" GC_CITY_PATH="$SANDBOX/no-ledger"
eq "$OUT|$RC" "|0" "no ledger script: the third rapid stop is not handed back"
eq "$(cat "$SANDBOX/gc.log")" "" "no ledger script: the session is not reset"
eq "$(cat "$STATE")" "s1 $now 2" "no ledger script: the state file keeps its count"
has "$ERR" "gc-deacon-ledger.sh not found" "a missing ledger script is reported on stderr"

echo "== the witness's reset writes no ledger line =="
printf 's1 %s 1\n' "$now" > "$WSTATE"
run_hook rig-a/gc-toolkit.witness "$(payload s1)" "${WITNESS_ENV[@]}"
eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "a witness's second rapid stop is still handed back"
eq "$(cut -d' ' -f3 < "$WSTATE")" "2" "a witness's rapid stop is counted in its own state file"

printf 's1 %s 2\n' "$now" > "$WSTATE"
run_hook rig-a/gc-toolkit.witness "$(payload s1)" "${WITNESS_ENV[@]}"
eq "$OUT|$RC" "|0" "a witness's third rapid stop is not handed back"
eq "$(cat "$SANDBOX/gc.log")" "session reset rig-a/gc-toolkit.witness" "a witness's third rapid stop resets the session by its alias"
eq "$(cat "$SANDBOX/ledger.log")" "" "a witness's reset writes no ledger line"
eq "$(cat "$WSTATE")" "s1 0 0" "a witness's reset starts the count over"

printf 's1 %s 2\n' "$now" > "$WSTATE"
run_hook rig-a/gc-toolkit.witness "$(payload s1)" "${WITNESS_ENV[@]}" GC_CITY_PATH="$SANDBOX/no-ledger"
eq "$(cat "$SANDBOX/gc.log")" "session reset rig-a/gc-toolkit.witness" "a missing ledger script does not hold a witness's reset"

printf 's1 %s 2\n' "$now" > "$WSTATE"
run_hook rig-a/gc-toolkit.witness "$(payload s1)" "${WITNESS_ENV[@]}" "$IN_TMUX" TMUX_ATTACHED=1
eq "$OUT|$RC" "|0" "an attached operator: a witness's third rapid stop is not handed back"
eq "$(cat "$SANDBOX/gc.log")" "" "an attached operator holds a witness's reset"
eq "$(cat "$WSTATE")" "s1 $now 2" "an attached operator: a witness's state file keeps its count"

echo "== a real cycle outlasts the rapid-stop bound =="
# A turn that runs a cycle spends the patrol's whole event_timeout in its
# inter-cycle wait, so MIN_TURN must sit under every event_timeout the pack
# pours with. Otherwise each real cycle counts as a rapid stop and the hook
# resets the session every MAX_RAPID cycles.
MIN_TURN_SET=$(sed -n 's/^MIN_TURN=\([0-9][0-9]*\).*/\1/p' "$HOOK")
formula_wait() { awk '/^\[vars\.event_timeout\]/ { f = 1; next } /^\[/ { f = 0 } f && /^default *=/ { gsub(/[^0-9]/, ""); print; exit }' "$REPO/formulas/$1.toml"; }
FORMULA_WAIT=$(formula_wait mol-deacon-patrol)
POUR_WAIT=$(grep -F 'gc bd mol wisp mol-deacon-patrol ' "$REPO/agents/deacon/prompt.template.md" | sed -n "s/.*--var event_timeout='\([0-9][0-9]*\)'.*/\1/p")
WITNESS_WAIT=$(formula_wait mol-witness-patrol)
for pair in "the deacon formula default=$FORMULA_WAIT" "the deacon startup pour=$POUR_WAIT" "the witness formula default=$WITNESS_WAIT"; do
    name="${pair%%=*}"; wait_s="${pair#*=}"
    case "$MIN_TURN_SET" in '' | *[!0-9]*) bad "MIN_TURN is read from the hook" "got '$MIN_TURN_SET'"; continue ;; esac
    case "$wait_s" in '' | *[!0-9]*) bad "the event_timeout of $name is read" "got '$wait_s'"; continue ;; esac
    if [ "$MIN_TURN_SET" -lt "$wait_s" ]; then
        ok "MIN_TURN ($MIN_TURN_SET) is under the event_timeout of $name ($wait_s)"
    else
        bad "MIN_TURN is under the event_timeout of $name" "MIN_TURN $MIN_TURN_SET, event_timeout $wait_s"
    fi
done
# The witness's pours pass no event_timeout, so every witness wisp waits the
# formula default checked above.
for f in agents/witness/prompt.template.md formulas/mol-witness-patrol.toml; do
    POURS=$(grep -F 'gc bd mol wisp mol-witness-patrol ' "$REPO/$f")
    if [ -n "$POURS" ]; then ok "$f: its witness pour is read"; else bad "$f: its witness pour is read" "no pour line found"; fi
    eq "$(printf '%s\n' "$POURS" | grep -c 'event_timeout')" "0" "$f: no witness pour passes an event_timeout of its own"
done

echo "== wiring: the overlay runs the hook at every Stop, beside cycle-recycle =="
jq -e . "$SETTINGS" >/dev/null 2>&1 && ok "the overlay's settings.json parses" || bad "the overlay's settings.json parses" "jq rejected $SETTINGS"
STOP_CMDS="$(jq -r '[.hooks.Stop[]?.hooks[]? | select((.type // "command") == "command") | .command // empty] | .[]' "$SETTINGS" 2>/dev/null)"
eq "$(printf '%s\n' "$STOP_CMDS" | grep -c 'patrol-continue\.sh')" "1" "one Stop command runs patrol-continue.sh"
eq "$(printf '%s\n' "$STOP_CMDS" | grep -c 'cycle-recycle\.sh')" "1" "the cycle-recycle Stop command is still there"
eq "$(printf '%s\n' "$STOP_CMDS" | grep 'patrol-continue\.sh' | grep -cE '<[[:space:]]*/dev/null|0<')" "0" "the hook's stdin is not redirected away (the payload arrives on it)"
has "$(printf '%s\n' "$STOP_CMDS" | grep 'patrol-continue\.sh')" '/.claude/hooks/patrol-continue.sh' "the command runs the copy staged into the agent's work dir"
# The harness ends the turn when it kills the hook, so the reset has to give up
# first for its failure to reach the hand-back.
HOOK_TIMEOUT="$(jq -r '[.hooks.Stop[]?.hooks[]? | select((.command // "") | contains("patrol-continue.sh")) | .timeout // empty] | first // empty' "$SETTINGS" 2>/dev/null)"
case "$RESET_BOUND_SET|$HOOK_TIMEOUT" in
    *[!0-9\|]* | \|* | *\|) bad "the reset's bound and the hook's timeout are read" "got '$RESET_BOUND_SET' and '$HOOK_TIMEOUT'" ;;
    *) if [ "$RESET_BOUND_SET" -lt "$HOOK_TIMEOUT" ]; then ok "the reset's bound is under the hook's timeout"; else bad "the reset's bound is under the hook's timeout" "RESET_BOUND $RESET_BOUND_SET, timeout $HOOK_TIMEOUT"; fi ;;
esac

echo
echo "patrol-continue-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
