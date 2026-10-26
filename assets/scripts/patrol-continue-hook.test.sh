#!/usr/bin/env bash
# patrol-continue-hook.test.sh — hermetic test for the deacon's Stop hook,
# overlays/cycle-recycle/.claude/hooks/patrol-continue.sh.
#
# At a deacon turn boundary the hook prints a block decision that hands the
# next patrol cycle back. It prints nothing for any other agent, while a
# background task runs, or on a payload it cannot read. After MAX_RAPID stops
# in a row that each came within MIN_TURN seconds of a hand-back, it resets the
# session instead. Every path exits 0, so the exit code tells nothing apart;
# this test reads stdout, the state file and the calls the hook makes.
#
# It runs the SHIPPED script, never a copy. gc is stubbed by pointing HOME at
# the sandbox: the hook prepends "$HOME/go/bin" to PATH itself, so a stub placed
# there wins over the real gc. The ledger is stubbed at the path the hook
# resolves under GC_CITY_PATH. Every run starts from env -i, so no live GC_*
# variable reaches the hook.
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

# The ledger stub sits where the hook looks for gc-deacon-ledger.sh.
CITY="$SANDBOX/city"
mkdir -p "$CITY/rigs/gc-toolkit/assets/scripts"
cat > "$CITY/rigs/gc-toolkit/assets/scripts/gc-deacon-ledger.sh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$LEDGER_LOG"
STUB
chmod +x "$CITY/rigs/gc-toolkit/assets/scripts/gc-deacon-ledger.sh"

STATE_DIR="$SANDBOX/tmp"
mkdir -p "$STATE_DIR"

# run_hook <agent> <payload> [VAR=value ...] — run the shipped hook as a Stop
# event delivers it; stdout goes to $OUT, stderr to $ERR, and the exit code to
# $RC. Extra arguments are added to the environment.
run_hook() {
    local agent="$1" payload="$2"; shift 2
    : > "$SANDBOX/gc.log"; : > "$SANDBOX/ledger.log"
    printf '%s' "$payload" | env -i HOME="$SANDBOX/home" PATH="/usr/bin:/bin:$(dirname "$(command -v jq)")" \
        TMPDIR="$STATE_DIR" GC_AGENT="$agent" GC_ALIAS="gc-toolkit.deacon" \
        GC_SESSION_ID="hq-sess" GC_SESSION_NAME="gc-toolkit__deacon" GC_CITY_PATH="$CITY" \
        GC_LOG="$SANDBOX/gc.log" LEDGER_LOG="$SANDBOX/ledger.log" "$@" \
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

echo "== role gate: only the deacon is handed back its turn =="
for agent in "gc-toolkit/gc-toolkit.witness" "gc-toolkit/gc-toolkit.refinery" "gc-toolkit.mechanik" "gc-toolkit.polecat" ""; do
    rm -f "$STATE"
    run_hook "$agent" "$(payload s1)"
    eq "$OUT|$RC" "|0" "${agent:-<no GC_AGENT>}: no output, exit 0"
    [ ! -e "$STATE" ] && ok "${agent:-<no GC_AGENT>}: no state written" || bad "${agent:-<no GC_AGENT>}: no state written" "found $STATE"
done

echo "== a deacon turn boundary is handed back =="
for agent in "gc-toolkit.deacon" "deacon"; do
    rm -f "$STATE"
    run_hook "$agent" "$(payload s1)"
    eq "$RC" "0" "$agent: exit 0"
    eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "$agent: the decision blocks the stop"
    REASON="$(printf '%s' "$OUT" | jq -r '.reason' 2>/dev/null)"
    has "$REASON" "next-iteration" "$agent: the reason names next-iteration"
    has "$REASON" "mol-deacon-patrol" "$agent: the reason names the patrol formula"
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
has "$(printf '%s' "$OUT" | jq -r '.reason' 2>/dev/null)" "no cycle run" "the repeat hand-back says the last one ran no cycle"
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
eq "$OUT|$RC" "|0" "a failed reset still exits 0 with no output"
has "$ERR" "gc session reset gc-toolkit.deacon failed" "a failed reset is reported on stderr"

echo "== wiring: the overlay runs the hook at every Stop, beside cycle-recycle =="
jq -e . "$SETTINGS" >/dev/null 2>&1 && ok "the overlay's settings.json parses" || bad "the overlay's settings.json parses" "jq rejected $SETTINGS"
STOP_CMDS="$(jq -r '[.hooks.Stop[]?.hooks[]? | select((.type // "command") == "command") | .command // empty] | .[]' "$SETTINGS" 2>/dev/null)"
eq "$(printf '%s\n' "$STOP_CMDS" | grep -c 'patrol-continue\.sh')" "1" "one Stop command runs patrol-continue.sh"
eq "$(printf '%s\n' "$STOP_CMDS" | grep -c 'cycle-recycle\.sh')" "1" "the cycle-recycle Stop command is still there"
eq "$(printf '%s\n' "$STOP_CMDS" | grep 'patrol-continue\.sh' | grep -cE '<[[:space:]]*/dev/null|0<')" "0" "the hook's stdin is not redirected away (the payload arrives on it)"
has "$(printf '%s\n' "$STOP_CMDS" | grep 'patrol-continue\.sh')" '/.claude/hooks/patrol-continue.sh' "the command runs the copy staged into the agent's work dir"

echo
echo "patrol-continue-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
