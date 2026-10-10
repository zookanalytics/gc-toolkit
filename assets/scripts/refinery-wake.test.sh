#!/usr/bin/env bash
# refinery-wake.test.sh — the wake for a refinery idle at its prompt while its
# find-work queue waits. A stub gc serves the agent roster, the queue, the
# session list and the resolved config, and records every nudge. Proves the
# pass nudges exactly when the oldest queued handoff has waited past the bound
# AND the refinery's pane has been quiet, with the refinery's own nudge text,
# paces and caps its wakes per stall, and otherwise does nothing: an empty or
# young queue, a parked anchor, a busy, attached or absent session, and every
# read it cannot make all leave the refinery alone.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAKE="$HERE/refinery-wake.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-wake-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
[ -x "$WAKE" ] || { echo "missing or not executable: $WAKE"; exit 1; }
bash -n "$WAKE" && ok "refinery-wake.sh is valid bash" || bad "refinery-wake.sh is valid bash" "bash -n failed"

NOW=$(date +%s)
# iso <seconds ago> [offset]: an RFC3339 time that many seconds before NOW,
# in UTC (Z) or written at a -06:00 offset as gc session list renders it.
iso() {
  local t=$((NOW - $1)) fmt='+%Y-%m-%dT%H:%M:%S'
  if [ "${2:-}" = "-06:00" ]; then t=$((t - 21600)); fi
  local s
  s=$(date -u -d "@$t" "$fmt" 2>/dev/null || date -u -r "$t" "$fmt")
  if [ "${2:-}" = "-06:00" ]; then printf '%s-06:00' "$s"; else printf '%sZ' "$s"; fi
}

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "agent list")   cat "$STUB_AGENTS" ;;
  "bd list")      [ "${STUB_QUEUE_RC:-0}" = 0 ] || exit "$STUB_QUEUE_RC"; cat "$STUB_QUEUE" ;;
  "session list") [ "${STUB_SESSIONS_RC:-0}" = 0 ] || exit "$STUB_SESSIONS_RC"; cat "$STUB_SESSIONS" ;;
  "config show")  [ "${STUB_CONFIG_RC:-0}" = 0 ] || exit "$STUB_CONFIG_RC"; cat "$STUB_CONFIG" ;;
  "session nudge") printf '%s\n' "$*" >> "$STUB_NUDGES"; exit "${STUB_NUDGE_RC:-0}" ;;
  *) echo "stub gc: unexpected: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$BIN/gc"

export STUB_LOG="$TMP/gc.log" STUB_NUDGES="$TMP/nudges.log"
export STUB_AGENTS="$TMP/agents.json" STUB_QUEUE="$TMP/queue.json"
export STUB_SESSIONS="$TMP/sessions.json" STUB_CONFIG="$TMP/config.json"
export REFINERY_WAKE_STATE_DIR="$TMP/state"
unset REFINERY_WAKE_AGENT GC_PACK_NAME

cat > "$STUB_AGENTS" <<'JSON'
{"agents":[{"qualified_name":"other/gc-toolkit.refinery"},{"qualified_name":"r1/gc-toolkit.polecat"},{"qualified_name":"r1/gc-toolkit.refinery"}]}
JSON
cat > "$STUB_CONFIG" <<'JSON'
{"config":{"Agents":[{"Dir":"other","Name":"refinery","Nudge":"wrong rig"},{"Dir":"r1","Name":"polecat","Nudge":"wrong agent"},{"Dir":"r1","Name":"refinery","Nudge":"Configured refinery nudge."}]}}
JSON

queue() { # queue <id:age[:merge_result]> ... — the rows gc bd list returns
  local spec id age mr rows=""
  for spec in "$@"; do
    IFS=: read -r id age mr <<< "$spec"
    rows="$rows${rows:+,}{\"id\":\"$id\",\"updated_at\":\"$(iso "$age")\",\"metadata\":{\"branch\":\"polecat/$id\"${mr:+,\"merge_result\":\"$mr\"}}}"
  done
  printf '[%s]\n' "$rows" > "$STUB_QUEUE"
}
session() { # session <state> <attached> <last_active>
  printf '{"sessions":[{"id":"ses-other","agent_name":"other/gc-toolkit.refinery","alias":"other/gc-toolkit.refinery","state":"active","attached":false,"last_active":"%s"},{"id":"ses-r1","agent_name":"r1/gc-toolkit.refinery","alias":"r1/gc-toolkit.refinery","state":"%s","attached":%s,"last_active":"%s","closed":false}]}\n' \
    "$(iso 9999)" "$1" "$2" "$3" > "$STUB_SESSIONS"
}
run() { # run the pass for rig r1; sets OUT and RC
  : > "$STUB_NUDGES"
  OUT=$(PATH="$BIN:$PATH" GC_RIG=r1 "$WAKE" 2>&1); RC=$?
}
nudges() { cat "$STUB_NUDGES"; }
idle_session() { session active false "$(iso 1200 -06:00)"; }

echo "── GC_RIG is required ──"
OUT=$(PATH="$BIN:$PATH" env -u GC_RIG "$WAKE" 2>&1); RC=$?
eq "$RC" 2 "no GC_RIG exits 2"

echo "── an idle refinery whose oldest handoff waited past the bound is nudged ──"
queue young:60 old:2400 older:3000
idle_session
run
eq "$RC" 0 "the pass exits 0"
N=$(nudges)
has "$N" "session nudge --delivery immediate ses-r1" "it nudges this rig's refinery session, immediately"
has "$N" "has held older for 50m" "the nudge names the oldest bead and its wait"
has "$N" "Configured refinery nudge." "the nudge carries the refinery's configured nudge text"
hasnt "$N" "wrong" "the nudge text comes from this rig's refinery, not another agent's"
has "$(grep 'bd list' "$STUB_LOG")" "--rig r1 --assignee r1/gc-toolkit.refinery --status open --exclude-type epic --has-metadata-key branch" \
  "the queue read is find-work's filter, scoped to this rig's refinery"
has "$(cat "$TMP/state/r1.log")" "nudged ses-r1 (wake 1 of 3)" "the wake is logged"
has "$OUT" "nudged ses-r1" "the pass says it nudged"

echo "── a second pass inside the backoff does not nudge again ──"
run
eq "$(nudges)" "" "no nudge inside the backoff"
has "$OUT" "backing off" "it says it is backing off"

echo "── wakes per stall are spaced and capped ──"
age_state() { sed "s/^last=.*/last=$((NOW - 1000))/" "$TMP/state/r1" > "$TMP/state/r1.new" && mv "$TMP/state/r1.new" "$TMP/state/r1"; }
age_state; run
has "$(nudges)" "ses-r1" "wake 2 after the backoff"
age_state; run
has "$(nudges)" "ses-r1" "wake 3 after the backoff"
age_state; run
eq "$(nudges)" "" "no fourth wake for the same stall"
has "$OUT" "gave up on older after 3 wake(s)" "it says it gave up and on which bead"

echo "── a different oldest bead is a new stall ──"
queue old:2400 fresh-stall:3600
run
has "$(nudges)" "has held fresh-stall for 60m" "a new oldest bead is woken for"
has "$(cat "$TMP/state/r1")" "wakes=1" "its count starts over"

echo "── an empty queue clears the stall record and nudges nothing ──"
printf '[]\n' > "$STUB_QUEUE"
run
eq "$(nudges)" "" "no nudge on an empty queue"
[ -e "$TMP/state/r1" ] && bad "the stall record is cleared" "it is still there" || ok "the stall record is cleared"

echo "── a queue inside the bound nudges nothing ──"
queue a:600 b:1500
run
eq "$(nudges)" "" "no nudge while every bead is inside the bound"
has "$OUT" "inside the 30m bound" "it says the wait is inside the bound"

echo "── a parked anchor (merge_result set) is not queue work ──"
queue anchor:9000:pull_request
run
eq "$(nudges)" "" "an old anchor alone wakes nothing"
has "$OUT" "is empty" "the queue reads empty without it"

echo "── a busy, attached, or absent session is left alone ──"
queue old:3000
session active false "$(iso 5)"
run
eq "$(nudges)" "" "a pane that printed 5s ago is busy"
has "$OUT" "busy, left alone" "it says the refinery is busy"
session active true "$(iso 3000)"
run
eq "$(nudges)" "" "an attached session is left alone"
session asleep false "$(iso 3000)"
run
eq "$(nudges)" "" "an asleep session is not nudged"
has "$OUT" "no active session" "it says there is no active session"
session active false "$(iso -30)"
run
eq "$(nudges)" "" "a pane whose last output is later than the pass's start is busy"
has "$OUT" "printed 0s ago" "it reads as printing just now"
session active false "0001-01-01T00:00:00Z"
run
eq "$(nudges)" "" "a pane whose last output cannot be read is treated as busy"

echo "── a read it cannot make does nothing ──"
idle_session
STUB_QUEUE_RC=1 run
eq "$(nudges)" "" "an unreadable queue nudges nothing"
has "$(tail -1 "$TMP/state/r1.log")" "could not read the find-work queue" "the failed read is logged"
printf 'not json\n' > "$STUB_QUEUE"
run
eq "$(nudges)" "" "a queue that is not JSON nudges nothing"
queue old:3000
STUB_SESSIONS_RC=1 run
eq "$(nudges)" "" "an unreadable session list nudges nothing"

echo "── an unreadable config falls back to the standing nudge ──"
STUB_CONFIG_RC=1 run
has "$(nudges)" "process the merge queue." "the fallback text still says what to do"

echo "── a nudge that fails fast is not counted; one cut off is ──"
queue cnt:3000
STUB_NUDGE_RC=1 run
has "$OUT" "FAILED" "a fast failure is reported"
[ -e "$TMP/state/r1" ] && [ "$(sed -n 's/^bead=//p' "$TMP/state/r1")" = cnt ] && bad "a fast failure is not counted" "a wake was recorded" \
  || ok "a fast failure is not counted"
STUB_NUDGE_RC=124 run
has "$OUT" "UNCONFIRMED" "a cut-off nudge is reported unconfirmed"
has "$(cat "$TMP/state/r1")" "wakes=1" "and counted as a wake"

echo "── the refinery is discovered per rig ──"
printf '{"agents":[]}\n' > "$STUB_AGENTS"
run
eq "$(nudges)" "" "no refinery bound, nothing nudged"
has "$OUT" "no refinery agent bound" "it says no refinery is bound"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
