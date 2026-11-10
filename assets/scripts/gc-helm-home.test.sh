#!/usr/bin/env bash
# Hermetic test for gc-helm's home page and its two seats: a bare `gc-helm`,
# `gc-helm po` and `gc-helm mechanik`.
#
# Runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a stubbed `gc` on
# PATH that answers `gc session list --json` from a walk of the seat's states,
# one per listing, and records each nudge and attach. No live city, controller,
# tmux or session. Covered:
#   (HOME)        a bare gc-helm on a terminal hands it to the conversation form
#                 on its home page
#   (HOME-NOTTY)  without a terminal it names the verbs and the home page,
#                 prints the usage and exits 2, opening no form
#   (HOME-MISSING) with no form built it exits 3, naming each entry's command
#   (PO-LIVE, PO-SLEPT) a live po sitting, and one its idle limit put to sleep,
#                 are attached to as they stand: no nudge, no controller read,
#                 and what the sitting is for is said not to have been sent
#   (PO-ENDED, PO-NONE, PO-STARTING) a seat whose last sitting ended, one with
#                 no session and one the controller is starting are started by a
#                 nudge to the seat that says the operator is opening a sitting,
#                 with what it is for, and attached only once a listing reads the
#                 session active, never before
#   (PO-PICK)     the seat's active session is the one attached to, though a
#                 newer one is listed; an unrelated session whose name holds
#                 "po" is never taken for the seat
#   (PO-DRAINING) a po still ending its last sitting is waited on until it has
#                 stopped, and only then nudged; one that stops into a slept
#                 sitting is attached to with no nudge
#   (PO-PROGRESS) the wait says when it opens and each change of state
#   (PO-TIMEOUT, PO-NOSTART) a start the controller has not made by the bound,
#                 or a seat in a state it does not start from, attaches nothing
#                 and exits 4, naming why
#   (PO-NUDGE-FAIL, PO-CTRL-DOWN, PO-LIST-FAIL, PO-ATTACH-FAIL) a nudge that
#                 fails, a controller that is down and a listing that does not
#                 read each start and attach nothing, and a failed attach exits 4
#   (PO-INTERRUPT) Ctrl-C stops the wait, attaching nothing and naming the re-run
#   (PO-ARGS, MK-ARGS) an argument or an unknown flag exits 2
#   (MK-LIVE, MK-START) mechanik is attached to once it runs, waited on while the
#                 controller starts it, and never nudged
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
SCRIPT_REAL="$(readlink -f "$SCRIPT" 2>/dev/null || printf '%s' "$SCRIPT")"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-home-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()    { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# The session's own city must not reach a hermetic run.
unset GC_CITY_PATH GC_CITY GC_CITY_ROOT GC_RIG BEADS_DIR GC_HELM_FIXTURE GC_HELM_ASSUME_TTY GC_HELM_FORM_BIN || true
unset GC_HELM_ENGAGE_WAIT_TIMEOUT FAKE_CLOCK FAKE_CLOCK_SCALE || true
export CALLS="$TMP/calls" POLLS="$TMP/polls" STATE="$TMP/state"
mkdir -p "$TMP/bin" "$STATE" "$TMP/agents/converse-opus"
export GC_HELM_AGENTS_DIR="$TMP/agents" TMPDIR="$TMP"

# The stub answers `gc session list --json` with the seat $SEAT's row walking
# $SEAT_ROWS, one token per listing, the last repeating. A token is a state,
# with :<reason> when the row carries one; "none" lists no row for the seat,
# "broken" fails the listing, and "dup:<old>,<new>" lists two rows for the
# seat, an older lx-old and a newer lx-new. Every listing also carries a
# polecat and a converse sitting, neither of them the seat.
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" | tr '\n' ' ' >> "$CALLS"; printf '\n' >> "$CALLS"
row() { # <id> <state[:reason]> <created_at>
  jq -nc --arg id "$1" --arg tok "$2" --arg seat "$SEAT" --arg at "$3" '
    ($tok | split(":")) as $t
    | {id: $id, alias: $seat, template: $seat, session_name: "s-\($id)", state: $t[0],
       attached: false, closed: false, created_at: $at}
      + (if ($t | length) > 1 then {reason: $t[1]} else {} end)'
}
case "$1 ${2:-}" in
  "rig list") cat "$STATE/rigs.json" ;;
  "status --json") cat "$STATE/status.json" ;;
  "session list")
    _n=$(( $(cat "$POLLS" 2>/dev/null || echo 0) + 1 )); printf '%s' "$_n" > "$POLLS"
    set -- ${SEAT_ROWS:-active}
    [ "$_n" -le $# ] || _n=$#
    eval "_tok=\${$_n}"
    case "$_tok" in
      broken) echo "session list: data plane down" >&2; exit 1 ;;
      none) _rows='[]' ;;
      dup:*) _pair=${_tok#dup:}
             _rows="[$(row lx-old "${_pair%%,*}" 2026-11-01T00:00:00Z),$(row lx-new "${_pair#*,}" 2026-11-09T00:00:00Z)]" ;;
      *) _rows="[$(row lx-seat "$_tok" 2026-11-09T00:00:00Z)]" ;;
    esac
    jq -nc --argjson seat "$_rows" '{schema_version: "1", ok: true, sessions: ($seat + [
      {id: "lx-pc", alias: null, template: "gc-toolkit/gc-toolkit.polecat", state: "active", attached: false, created_at: "2026-11-09T01:00:00Z"},
      {id: "lx-cv", alias: "gc-toolkit/gc-toolkit.tk-po1", template: "gc-toolkit/gc-toolkit.converse-opus", state: "asleep", reason: "idle", attached: false, created_at: "2026-11-09T02:00:00Z"}])}' ;;
  "session nudge") exit "${NUDGE_RC:-0}" ;;
  "session attach") exit "${ATTACH_RC:-0}" ;;
  *) echo "stub gc: unhandled: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gc"

# The conversation form's stand-in records the argv it was handed.
cat > "$TMP/bin/form-stub" <<'FORM'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done > "$FORM_ARGV_FILE"
echo "form-stub ran"
FORM
chmod +x "$TMP/bin/form-stub"
export FORM_ARGV_FILE="$TMP/form.argv"

# The waits read the time with `date +%s` and sleep a second between listings.
# With $FAKE_CLOCK naming a file, `date +%s` prints the epoch second it holds,
# and a whole-second `sleep N` returns at once and moves that clock N times
# ${FAKE_CLOCK_SCALE:-1} seconds on, so a case can wait minutes in a few
# listings. Without it both are the real commands.
REAL_DATE=$(command -v date); REAL_SLEEP=$(command -v sleep)
cat > "$TMP/bin/date" <<EOF
#!/bin/sh
if [ -n "\${FAKE_CLOCK:-}" ] && [ "\$*" = "+%s" ]; then cat "\$FAKE_CLOCK"; exit 0; fi
exec "$REAL_DATE" "\$@"
EOF
cat > "$TMP/bin/sleep" <<EOF
#!/bin/sh
[ -n "\${FAKE_CLOCK:-}" ] || exec "$REAL_SLEEP" "\$@"
case "\${1:-}" in ''|*[!0-9]*) exec "$REAL_SLEEP" "\$@" ;; esac
echo \$(( \$(cat "\$FAKE_CLOCK") + \$1 * \${FAKE_CLOCK_SCALE:-1} )) > "\$FAKE_CLOCK"
EOF
chmod +x "$TMP/bin/date" "$TMP/bin/sleep"
export PATH="$TMP/bin:$PATH"

# reset — a city whose controller runs, no calls recorded, the walk at its start.
reset() {
  : > "$CALLS"; rm -f "$POLLS" "$FORM_ARGV_FILE"
  jq -n --arg h "$TMP" '{rigs: [{name: "hq", path: $h, prefix: "hq", hq: true, running: true},
    {name: "gc-toolkit", path: ($h + "/rig"), prefix: "tk", suspended: false}]}' > "$STATE/rigs.json"
  echo '{"controller":{"running":true}}' > "$STATE/status.json"
  echo 1000 > "$TMP/clock"
}

# run <verb> [args...] -> RC/OUT/CALLED. stdin is /dev/null, so no terminal.
# The waits run on the fake clock, so a listing a second apart costs nothing.
run() {
  set +e
  OUT="$(FAKE_CLOCK="${FAKE_CLOCK:-$TMP/clock}" sh "$SCRIPT" "$@" </dev/null 2>"$TMP/err")"; RC=$?
  set -e
  OUT="$OUT$(cat "$TMP/err")"
  CALLED="$(cat "$CALLS")"
}

# lists_before <pattern> — how many listings CALLED records before the first
# call that starts with <pattern>, or "never".
lists_before() {
  printf '%s\n' "$CALLED" | awk -v p="$1" '
    index($0, p) == 1 { print n + 0; found = 1; exit }
    index($0, "session list") == 1 { n++ }
    END { if (!found) print "never" }'
}

echo "# a bare gc-helm opens the home page on a terminal, and without one prints its usage"
reset
set +e
OUT="$(GC_HELM_ASSUME_TTY=1 GC_HELM_FORM_BIN="$TMP/bin/form-stub" sh "$SCRIPT" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(HOME) a bare gc-helm on a terminal runs the form"
eq "$(paste -s -d'|' - < "$FORM_ARGV_FILE" 2>/dev/null || true)" "form|--helm|$SCRIPT_REAL|--models|opus|--home" "(HOME) …on its home page, handed this script's path"
reset
set +e
OUT="$(GC_HELM_FORM_BIN="$TMP/bin/form-stub" sh "$SCRIPT" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 2 "(HOME-NOTTY) a bare gc-helm without a terminal exits 2"
has "$OUT" "name a verb" "(HOME-NOTTY) …asking for a verb"
has "$OUT" "a bare gc-helm opens the home page" "(HOME-NOTTY) …saying what it does on a terminal"
has "$OUT" "gc-helm po [--reason" "(HOME-NOTTY) …and printing the usage, the seats included"
eq "$(cat "$FORM_ARGV_FILE" 2>/dev/null || true)" "" "(HOME-NOTTY) …opening no form"
reset
set +e
OUT="$(GC_HELM_ASSUME_TTY=1 GC_HELM_FORM_BIN="$TMP/no-such-form" sh "$SCRIPT" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 3 "(HOME-MISSING) with no form built a bare gc-helm exits 3"
has "$OUT" "no helm-svc binary is built" "(HOME-MISSING) …saying the form is not built"
has "$OUT" "gc-helm po to open the po, gc-helm mechanik to attach to mechanik" "(HOME-MISSING) …naming the seats' commands"
has "$OUT" "gc-helm attach <conversation> to return" "(HOME-MISSING) …and the conversations' commands"

export SEAT="gc-toolkit.po"

echo "# a live po sitting, and one its idle limit put to sleep, are attached to as they stand"
reset; SEAT_ROWS="active" run po
eq "$RC" 0 "(PO-LIVE) po on a live sitting exits 0"
has "$OUT" "the po's sitting is live (session lx-seat)" "(PO-LIVE) …saying the sitting is live"
has "$CALLED" "session attach lx-seat" "(PO-LIVE) …attaching to its session"
hasnt "$CALLED" "session nudge" "(PO-LIVE) …sending no nudge"
hasnt "$CALLED" "rig list" "(PO-LIVE) …and reading no controller"
has "$OUT" "Return to the po with: gc-helm po" "(PO-LIVE) …and naming how to return once the attach comes back"
reset; SEAT_ROWS="asleep:idle" run po
eq "$RC" 0 "(PO-SLEPT) po on a slept sitting exits 0"
has "$OUT" "attaching wakes it into its conversation" "(PO-SLEPT) …saying the attach wakes it"
has "$CALLED" "session attach lx-seat" "(PO-SLEPT) …attaching to its session"
hasnt "$CALLED" "session nudge" "(PO-SLEPT) …sending no nudge, which would start a new conversation"
reset; SEAT_ROWS="active" run po --reason "backlog refinement"
has "$OUT" "what it is for was not sent: say it there" "(PO-LIVE-REASON) a reason for a sitting already open is said not to be sent"
hasnt "$CALLED" "session nudge" "(PO-LIVE-REASON) …and is not nudged into it"

echo "# any other seat is started through the controller and attached only once it runs"
reset; SEAT_ROWS="asleep asleep creating active" run po
eq "$RC" 0 "(PO-ENDED) po on a seat whose last sitting ended exits 0"
has "$CALLED" "session nudge gc-toolkit.po The operator is opening a sitting with gc-helm po and attaches once you start." "(PO-ENDED) …nudging the seat, which asks the controller to start it"
eq "$(lists_before 'session nudge')" 1 "(PO-ENDED) …once the seat has read ended"
eq "$(lists_before 'session attach lx-seat')" 4 "(PO-ENDED) …and attaching on the listing that reads it active, never before"
has "$OUT" "asked the controller to start the po" "(PO-ENDED) …saying so"
reset; SEAT_ROWS="asleep active" run po --reason "backlog refinement"
has "$CALLED" "and attaches once you start. It is for: backlog refinement" "(PO-REASON) the nudge says what the sitting is for"
has "$OUT" "start the po for: backlog refinement" "(PO-REASON) …and so does the line the operator reads"
reset; SEAT_ROWS="none none creating active" run po
eq "$RC" 0 "(PO-NONE) po on a seat with no session exits 0"
has "$CALLED" "session nudge gc-toolkit.po" "(PO-NONE) …nudging the seat, which makes its session"
eq "$(lists_before 'session attach lx-seat')" 4 "(PO-NONE) …and attaching only once it runs"
reset; SEAT_ROWS="creating active" run po
has "$CALLED" "session nudge gc-toolkit.po" "(PO-STARTING) a seat the controller is starting is nudged too, its message queued for the start"
eq "$(lists_before 'session attach lx-seat')" 2 "(PO-STARTING) …and attached once it runs"
reset; SEAT_ROWS="dup:active,asleep" run po
has "$CALLED" "session attach lx-old" "(PO-PICK) the seat's active session is attached to, though a newer one is listed"
hasnt "$CALLED" "session nudge" "(PO-PICK) …with no nudge"
# The listings carry only sessions that are not the seat, so the start never
# reads active, and the fake clock reaches the bound in a few listings.
reset; FAKE_CLOCK="$TMP/clock" FAKE_CLOCK_SCALE=60 GC_HELM_ENGAGE_WAIT_TIMEOUT=120 SEAT=gc-toolkit.other SEAT_ROWS="active" run po
has "$CALLED" "session nudge gc-toolkit.po" "(PO-PICK) a polecat or a sitting whose name holds po is not the seat, so a seat with no session is started"
hasnt "$CALLED" "session attach" "(PO-PICK) …and none of them is attached to"

echo "# a po ending its last sitting is waited on until it has stopped"
reset; SEAT_ROWS="draining draining asleep creating active" run po
eq "$RC" 0 "(PO-DRAINING) po on a draining seat exits 0"
has "$OUT" "The po is ending its last sitting" "(PO-DRAINING) …saying it waits for the sitting to end"
eq "$(lists_before 'session nudge')" 3 "(PO-DRAINING) …nudging only once the drain has finished"
eq "$(lists_before 'session attach lx-seat')" 5 "(PO-DRAINING) …and attaching once the new start runs"
reset; SEAT_ROWS="draining asleep:idle" run po
has "$CALLED" "session attach lx-seat" "(PO-DRAINING-SLEPT) a drain that ends in a slept sitting is attached to"
hasnt "$CALLED" "session nudge" "(PO-DRAINING-SLEPT) …with no nudge"

echo "# the wait reports itself"
reset; SEAT_ROWS="asleep asleep creating creating active" run po
has "$OUT" "waiting for the controller to start the po (it is asleep), then attaching; Ctrl-C stops the wait" "(PO-PROGRESS) the wait says when it opens"
has "$OUT" "the po is creating, after" "(PO-PROGRESS) …and when the state changes"

echo "# a start that does not come attaches nothing"
reset; FAKE_CLOCK="$TMP/clock" FAKE_CLOCK_SCALE=60 GC_HELM_ENGAGE_WAIT_TIMEOUT=300 SEAT_ROWS="asleep" run po
eq "$RC" 4 "(PO-TIMEOUT) a seat still not started at the bound exits 4"
has "$OUT" "the controller has not started the po after 5m00s" "(PO-TIMEOUT) …naming the bound"
has "$OUT" "an attach now would bring it up without its prompt" "(PO-TIMEOUT) …and why it does not attach"
hasnt "$CALLED" "session attach" "(PO-TIMEOUT) …attaching nothing"
reset; SEAT_ROWS="asleep quarantined" run po
eq "$RC" 4 "(PO-NOSTART) a seat in a state the controller does not start from exits 4"
has "$OUT" "is quarantined, a state the controller does not start it from" "(PO-NOSTART) …naming the state"
hasnt "$CALLED" "session attach" "(PO-NOSTART) …attaching nothing"

echo "# a failed step starts and attaches nothing"
reset; NUDGE_RC=1 SEAT_ROWS="asleep active" run po
eq "$RC" 4 "(PO-NUDGE-FAIL) a nudge that fails exits 4"
has "$OUT" "gc session nudge exited 1" "(PO-NUDGE-FAIL) …naming it"
hasnt "$CALLED" "session attach" "(PO-NUDGE-FAIL) …attaching nothing"
reset
jq '.rigs[0].running = false' "$STATE/rigs.json" > "$STATE/tmp.json" && mv "$STATE/tmp.json" "$STATE/rigs.json"
echo '{"controller":{"running":false,"status":"stopped"}}' > "$STATE/status.json"
SEAT_ROWS="asleep active" run po
eq "$RC" 4 "(PO-CTRL-DOWN) a controller that is down exits 4"
has "$OUT" "the city controller did not answer" "(PO-CTRL-DOWN) …saying so"
hasnt "$CALLED" "session nudge" "(PO-CTRL-DOWN) …nudging nothing"
hasnt "$CALLED" "session attach" "(PO-CTRL-DOWN) …and attaching nothing"
reset; SEAT_ROWS="broken" run po
eq "$RC" 4 "(PO-LIST-FAIL) a listing that does not read exits 4"
has "$OUT" "could not read 'gc session list'" "(PO-LIST-FAIL) …saying so"
hasnt "$CALLED" "session nudge" "(PO-LIST-FAIL) …nudging nothing"
reset; ATTACH_RC=1 SEAT_ROWS="active" run po
eq "$RC" 4 "(PO-ATTACH-FAIL) an attach that fails exits 4"
has "$OUT" "could not attach to the po's session lx-seat" "(PO-ATTACH-FAIL) …naming the session"

echo "# Ctrl-C stops the wait"
# Job control puts the verb in a process group of its own, as a terminal puts
# its foreground job, and the signal goes to the whole group, as a terminal's
# Ctrl-C does. perl puts SIGINT's default back first, since a suite started in
# the background by a shell without job control inherits it ignored.
reset
set +e
set -m
SEAT_ROWS="asleep" GC_HELM_ENGAGE_WAIT_TIMEOUT=60 perl -e '$SIG{$_} = "DEFAULT" for qw(INT TERM HUP); exec @ARGV or die "exec: $!\n"' \
  sh "$SCRIPT" po </dev/null >"$TMP/out" 2>"$TMP/err" &
_pid=$!
set +m
_w=0
while [ "$(cat "$POLLS" 2>/dev/null || echo 0)" -lt 3 ] && [ "$_w" -lt 1200 ] && kill -0 "$_pid" 2>/dev/null; do
  sleep 0.05; _w=$((_w + 1))
done
kill -INT -- "-$_pid" 2>/dev/null
wait "$_pid"; RC=$?
set -e
OUT="$(cat "$TMP/out")$(cat "$TMP/err")"; CALLED="$(cat "$CALLS")"
eq "$RC" 130 "(PO-INTERRUPT) Ctrl-C during the wait exits 130"
has "$OUT" "stopped waiting after" "(PO-INTERRUPT) …saying the wait stopped"
has "$OUT" "open one again with: gc-helm po" "(PO-INTERRUPT) …and naming the re-run"
hasnt "$CALLED" "session attach" "(PO-INTERRUPT) …attaching nothing"

echo "# po's arguments"
reset; run po now
eq "$RC" 2 "(PO-ARGS) an argument exits 2"
has "$OUT" "say what the sitting is for with --reason" "(PO-ARGS) …naming --reason"
reset; run po --bogus
eq "$RC" 2 "(PO-ARGS) an unknown flag exits 2"
reset; run po --reason
eq "$RC" 2 "(PO-ARGS) --reason with no value exits 2"
eq "$(cat "$CALLS")" "" "(PO-ARGS) …each reading and writing nothing"

export SEAT="gc-toolkit.mechanik"

echo "# mechanik is attached to once it runs, and never nudged"
reset; SEAT_ROWS="active" run mechanik
eq "$RC" 0 "(MK-LIVE) mechanik on a running session exits 0"
has "$CALLED" "session attach lx-seat" "(MK-LIVE) …attaching to it"
hasnt "$CALLED" "rig list" "(MK-LIVE) …reading no controller"
has "$OUT" "Return to mechanik with: gc-helm mechanik" "(MK-LIVE) …and naming how to return"
reset; SEAT_ROWS="creating creating active" run mechanik
eq "$RC" 0 "(MK-START) mechanik the controller is starting exits 0"
has "$OUT" "the controller keeps it running, so the attach waits for it to start" "(MK-START) …saying it waits"
eq "$(lists_before 'session attach lx-seat')" 3 "(MK-START) …attaching only once it runs"
hasnt "$CALLED" "session nudge" "(MK-START) …and nudging nothing"
reset; SEAT_ROWS="none active" run mechanik
eq "$(lists_before 'session attach lx-seat')" 2 "(MK-NONE) mechanik with no session listed yet is waited on, then attached"
reset; run mechanik now
eq "$RC" 2 "(MK-ARGS) an argument exits 2"

echo
echo "gc-helm-home: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
