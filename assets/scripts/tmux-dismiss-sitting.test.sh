#!/usr/bin/env bash
# Test for tmux-dismiss-sitting.sh — prefix+X, the keystroke that ends the
# converse sitting in view — and for the binding tmux-bindings.sh installs for
# it.
#
# Three halves:
#
#   HERMETIC — the script run directly, with tmux, gc and gc-helm.sh stubbed.
#     No tmux server, no city.
#   BIND     — a real tmux server on a private socket: what tmux-bindings.sh
#     installs for prefix+X.
#   LIVE     — real key presses through a real pty client: prefix+X, then y or
#     n at the confirm prompt. Guarded on tmux + script(1) and a TERM tmux can
#     attach under; skipped with a notice where any is missing.
#
# What the cases are guarding:
#
#   (CONVERSE)  a converse sitting is dismissed under its OWN identity:
#               gc-helm.sh dismiss runs with the session name, id, alias and rig
#               from the session record, and the operator is told which subject
#               ended. That identity is what dismiss's inference reads.
#   (AMBIENT)   an identity or store pin already in the job's environment is
#               replaced by the record's, never inherited. A record with no alias
#               leaves GC_ALIAS empty rather than passing an ambient one through.
#   (NOTCONV)   a Gas City session that is not a converse sitting is refused and
#               gc-helm.sh never runs. Its own identity may hold a visit that
#               dismiss would close all the same. A template that merely starts
#               with the word is not converse either.
#   (UNKNOWN)   a pane whose session is not in the list is refused.
#   (CLOSEDREC) a closed record under the pane's name is a past session.
#   (AMBIG)     two live records under one name are refused, not guessed.
#   (LISTFAIL)  an unreadable session list is refused with its own message: a
#               read that did not answer is a fault, not "not converse".
#   (NOSESSION) a press tmux cannot place in a session is refused.
#   (REFUSED)   a dismiss that exits non-zero reports its reason and does not
#               claim the sitting ended.
#   (NOOP)      a dismiss that found no open visit says so.
#   (GATE)      a dismiss held for a gate decision (exit 5 with the held object)
#               names each gate, the bead it blocks and its question, and the
#               two decisions, rather than dismiss's last stderr line, which
#               names no gate. An exit 5 without that object is a refusal.
#   (QUIET)     every path exits 0 with nothing on stdout: run-shell lays a view
#               pane over the operator's thread when a job prints or fails.
#   (FMT)       a # in shown text is doubled, so tmux displays it instead of
#               expanding it; #(...) in a format runs a command.
#   (CITY)      --city-path reaches gc-helm.sh as GC_CITY_PATH.
#   (NOHELM)    a config dir with no gc-helm.sh is reported, not ignored.
#   (BIND)      prefix+X is confirm-before around a backgrounded run-shell of
#               the script: no send-keys, and no format in the body, because
#               confirm-before expands formats before tmux parses the body.
#   (LIVE-YES)  prefix+X, y in a converse pane runs dismiss once under that
#               pane's identity, through confirm-before's re-parse of a config
#               dir whose path holds a space, a quote, a $ and a double quote,
#               and leaves the pane out of view mode.
#   (LIVE-NO)   prefix+X, n runs nothing.
#   (LIVE-GUARD) prefix+X, y in a non-converse pane is refused with a message.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/tmux-dismiss-sitting.sh"
BINDINGS="$HERE/tmux-bindings.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-tmux-dismiss-test.XXXXXX")"
SOCKET="gcdis-test-$$"
PROBE_SOCKET="gcdis-probe-$$"
# kill-server leaves the socket file behind, so the suite removes its own two.
SOCKET_DIR="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
cleanup() {
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    tmux -L "$PROBE_SOCKET" kill-server >/dev/null 2>&1 || true
    rm -f "$SOCKET_DIR/$SOCKET" "$SOCKET_DIR/$PROBE_SOCKET"
    rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0; SKIP=0
ok()    { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()   { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
skip()  { SKIP=$((SKIP + 1)); echo "skip - $1"; }
eq()    { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()   { [[ "$1" == *"$2"* ]] && ok "$3" || bad "$3 (in: $1)"; }
hasnt() { [[ "$1" == *"$2"* ]] && bad "$3 (in: $1)" || ok "$3"; }

# The LIVE half runs on the tmux server, backgrounded, so its observables are
# written after the key press returns. Poll for each one under one wall-clock
# budget rather than a fixed sleep a loaded host can outrun.
WAIT_SECS="${GC_TMUX_TEST_WAIT_SECS:-30}"
wait_for() {            # wait_for <predicate> [args…]
    local _deadline=$(( SECONDS + WAIT_SECS ))
    while :; do
        "$@" && return 0
        [ "$SECONDS" -ge "$_deadline" ] && return 1
        sleep 0.1
    done
}
calls_ge() { local n; n=$(grep -c '^ARGS=' "$2" 2>/dev/null); [ "${n:-0}" -ge "$1" ]; }   # calls_ge N FILE
msg_has()  { grep -qF -- "$1" < <(tmux -L "$SOCKET" show-messages 2>/dev/null); }

[ -f "$SCRIPT" ] && ok "tmux-dismiss-sitting.sh present" || { bad "missing at $SCRIPT"; exit 1; }
[ -x "$SCRIPT" ] && ok "tmux-dismiss-sitting.sh executable" || bad "tmux-dismiss-sitting.sh not executable"

# ── Session list fixture ────────────────────────────────────────────────────
# One live converse sitting per shape the guard must accept, and every shape it
# must refuse: a polecat, a template that only starts with the word, a closed
# past session, and two live records sharing a name.
SESSIONS='{"sessions":[
 {"id":"lx-conv1","session_name":"s-lx-conv1","alias":"gc-toolkit/gc-toolkit.tk-vis1","template":"gc-toolkit/gc-toolkit.converse-opus","rig":"gc-toolkit","state":"active","closed":false,"attached":true},
 {"id":"lx-base1","session_name":"s-lx-base1","alias":"other/gc-toolkit.tk-vis2","template":"other/gc-toolkit.converse","rig":"other","closed":false},
 {"id":"lx-noal1","session_name":"s-lx-noal1","template":"gc-toolkit/gc-toolkit.converse-fable","rig":"gc-toolkit","closed":false},
 {"id":"lx-pole1","session_name":"gc-toolkit__polecat-lx-pole1","alias":"gc-toolkit/gc-toolkit.polecat-1","template":"gc-toolkit/gc-toolkit.polecat","rig":"gc-toolkit","closed":false},
 {"id":"lx-near1","session_name":"s-lx-near1","alias":"gc-toolkit/gc-toolkit.tk-vis3","template":"gc-toolkit/gc-toolkit.conversely","rig":"gc-toolkit","closed":false},
 {"id":"lx-old1","session_name":"s-lx-old1","alias":"gc-toolkit/gc-toolkit.tk-vis0","template":"gc-toolkit/gc-toolkit.converse-opus","rig":"gc-toolkit","closed":true},
 {"id":"lx-dup1","session_name":"s-dup","template":"gc-toolkit/gc-toolkit.converse-opus","rig":"gc-toolkit","closed":false},
 {"id":"lx-dup2","session_name":"s-dup","template":"gc-toolkit/gc-toolkit.converse-opus","rig":"gc-toolkit","closed":false}
]}'

# ── Fake config dir: the script resolves gc-helm.sh under it ────────────────
# The gc-helm.sh stub logs the identity it was handed and answers the way the
# case asks: its stdout, its stderr, its exit code.
mkcfg() {               # mkcfg <dir>
    mkdir -p "$1/assets/scripts"
    cat > "$1/assets/scripts/gc-helm.sh" <<'HELMSTUB'
#!/bin/sh
{ printf 'ARGS=%s\n' "$*"
  printf 'GC_SESSION_NAME=%s\n' "${GC_SESSION_NAME-<unset>}"
  printf 'GC_SESSION_ID=%s\n' "${GC_SESSION_ID-<unset>}"
  printf 'GC_ALIAS=%s\n' "${GC_ALIAS-<unset>}"
  printf 'GC_RIG=%s\n' "${GC_RIG-<unset>}"
  printf 'BEADS_DIR=%s\n' "${BEADS_DIR-<unset>}"
  printf 'GC_CITY_PATH=%s\n' "${GC_CITY_PATH-<unset>}"; } >> "$HELM_CALLS"
[ -n "${FAKE_HELM_ERR:-}" ] && printf '%s\n' "$FAKE_HELM_ERR" >&2
if [ -n "${FAKE_HELM_OUT+set}" ]; then
    printf '%s' "$FAKE_HELM_OUT"
else
    printf '%s' '{"subject":"tk-sub1","matched":[{"id":"tk-vis1","identity":"stamp"}],"closed":1,"ok":true}'
fi
exit "${FAKE_HELM_RC:-0}"
HELMSTUB
    chmod +x "$1/assets/scripts/gc-helm.sh"
    ln -sf "$SCRIPT" "$1/assets/scripts/tmux-dismiss-sitting.sh"
}

###############################################################################
# HERMETIC — the script run directly against stubs.
###############################################################################
mkdir -p "$TMP/bin"
# tmux: display-message -p answers the format it is asked for; any other
# display-message is a message to the operator and is only logged.
cat > "$TMP/bin/tmux" <<'TMUXSTUB'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "$TMUX_CALLS"
if [ "$1" = display-message ]; then
    for a in "$@"; do
        if [ "$a" = "-p" ]; then
            case "${!#}" in
                '#{client_tty}')     printf '%s\n' "${FAKE_CLIENT-/dev/pts/9}" ;;
                '#{client_session}') printf '%s\n' "${FAKE_CLIENT_SESSION-${FAKE_SESSION:-}}" ;;
                '#{session_name}')   printf '%s\n' "${FAKE_SESSION:-}" ;;
            esac
            exit 0
        fi
    done
fi
exit 0
TMUXSTUB
chmod +x "$TMP/bin/tmux"
# gc: answers `session list` with the fixture, or fails like a dead data plane.
cat > "$TMP/bin/gc" <<'GCSTUB'
#!/usr/bin/env bash
if [ "$1 ${2:-}" = "session list" ]; then
    [ -n "${FAKE_LIST_RC:-}" ] && exit "$FAKE_LIST_RC"
    printf '%s\n' "$FAKE_LIST"
    exit 0
fi
exit 0
GCSTUB
chmod +x "$TMP/bin/gc"

CFG="$TMP/cfg"; mkcfg "$CFG"
export FAKE_LIST="$SESSIONS"

# run <session> — press the key "in" <session>. Leaves the script's exit code in
# RC, its stdout in OUT, the operator's messages in SAID and the dismiss calls
# in HELM. Ambient variables a case sets on the call line reach the script.
run() {
    export TMUX_CALLS="$TMP/tmux.log" HELM_CALLS="$TMP/helm.log"
    : > "$TMUX_CALLS"; : > "$HELM_CALLS"
    RC=0
    OUT=$(FAKE_SESSION="$1" PATH="$TMP/bin:$PATH" sh "$SCRIPT" "${RUN_CFG:-$CFG}" --city-path /my/city 2>/dev/null) || RC=$?
    SAID=$(grep 'display-message .*-d ' "$TMUX_CALLS" | tail -n 1)
    HELM=$(cat "$HELM_CALLS")
}
quiet() {               # quiet <label> — the view-mode guard, on every path
    eq "$RC" 0 "(QUIET) $1: exits 0"
    eq "$OUT" "" "(QUIET) $1: prints nothing on stdout"
}

echo "# a converse sitting is dismissed under its own identity"
run s-lx-conv1
has "$HELM" "ARGS=dismiss --json" "(CONVERSE) gc-helm.sh dismiss runs, with no bead named"
has "$HELM" "GC_SESSION_NAME=s-lx-conv1" "(CONVERSE) …under the record's session name"
has "$HELM" "GC_SESSION_ID=lx-conv1" "(CONVERSE) …its id"
has "$HELM" "GC_ALIAS=gc-toolkit/gc-toolkit.tk-vis1" "(CONVERSE) …its alias"
has "$HELM" "GC_RIG=gc-toolkit" "(CONVERSE) …and its rig"
has "$SAID" "the sitting on tk-sub1 is over (visit tk-vis1 closed)" "(CONVERSE) the operator is told which subject ended"
has "$(cat "$TMP/tmux.log")" "-c /dev/pts/9" "(CONVERSE) messages go to the client that pressed the key"
has "$HELM" "GC_CITY_PATH=/my/city" "(CITY) --city-path reaches gc-helm.sh as GC_CITY_PATH"
quiet "converse"

echo "# the base converse template, under another rig, is a converse sitting too"
run s-lx-base1
has "$HELM" "GC_SESSION_ID=lx-base1" "(CONVERSE) the base converse agent is accepted"
has "$HELM" "GC_RIG=other" "(CONVERSE) …with the rig its record names"

echo "# the job's ambient identity never reaches dismiss"
GC_SESSION_NAME=intruder GC_SESSION_ID=intruder GC_ALIAS=intruder GC_RIG=wrong BEADS_DIR=/wrong/.beads run s-lx-noal1
has "$HELM" "GC_SESSION_NAME=s-lx-noal1" "(AMBIENT) the record's session name replaces an ambient one"
has "$HELM" "GC_SESSION_ID=lx-noal1" "(AMBIENT) …and its id"
has "$HELM" "GC_RIG=gc-toolkit" "(AMBIENT) …and its rig"
has "$HELM" "BEADS_DIR=<unset>" "(AMBIENT) an ambient store pin is dropped"
hasnt "$HELM" "intruder" "(AMBIENT) a record with no alias leaves no ambient identity behind"
quiet "ambient"

echo "# a session that is not a converse sitting is refused"
run gc-toolkit__polecat-lx-pole1
eq "$HELM" "" "(NOTCONV) a polecat pane runs no dismiss"
has "$SAID" "is not a converse sitting (template 'gc-toolkit/gc-toolkit.polecat')" "(NOTCONV) …and says why"
quiet "not converse"
run s-lx-near1
eq "$HELM" "" "(NOTCONV) a template that only starts with the word is refused"

echo "# a pane outside the session list is refused"
run my-own-shell
eq "$HELM" "" "(UNKNOWN) no dismiss for a session the list does not hold"
has "$SAID" "'my-own-shell' is not a live Gas City session" "(UNKNOWN) …and it says so"
quiet "unknown"
run s-lx-old1
eq "$HELM" "" "(CLOSEDREC) a closed record is not the pane on screen"
run s-dup
eq "$HELM" "" "(AMBIG) two live records under one name run no dismiss"
has "$SAID" "2 live sessions are named 's-dup'" "(AMBIG) …and it says so"

echo "# an unreadable session list is a fault, not a refusal on the merits"
FAKE_LIST_RC=1 run s-lx-conv1
eq "$HELM" "" "(LISTFAIL) a failed list runs no dismiss"
has "$SAID" "could not read 'gc session list'" "(LISTFAIL) …and names the fault"
quiet "list failed"
FAKE_LIST='Error: no city' run s-lx-conv1
eq "$HELM" "" "(LISTFAIL) a list that is not JSON runs no dismiss"
has "$SAID" "could not read 'gc session list'" "(LISTFAIL) …with the same message"
FAKE_LIST='{"error":"down"}' run s-lx-conv1
eq "$HELM" "" "(LISTFAIL) an answer with no sessions array runs no dismiss"

echo "# a press tmux cannot place is refused"
FAKE_CLIENT_SESSION="" run ""
eq "$HELM" "" "(NOSESSION) no session, no dismiss"
has "$SAID" "tmux did not say which session" "(NOSESSION) …and it says so"
quiet "no session"

echo "# a dismiss that refuses reports its reason"
FAKE_HELM_RC=2 FAKE_HELM_OUT="" FAKE_HELM_ERR="gc-helm: no open visit is assigned to this session (s-lx-conv1); there is no current sitting." run s-lx-conv1
has "$SAID" "NOT dismissed — gc-helm: no open visit is assigned to this session" "(REFUSED) the reason reaches the operator"
hasnt "$SAID" "is over" "(REFUSED) …and the sitting is not claimed ended"
quiet "refused"
FAKE_HELM_RC=4 FAKE_HELM_OUT="" FAKE_HELM_ERR="" run s-lx-conv1
has "$SAID" "gc-helm dismiss exited 4 with no diagnostic" "(REFUSED) a silent failure still says it failed"

echo "# a dismiss held for a gate decision names each gate and how to decide it"
HELD='{"subject":"tk-sub1","ok":false,"held_for_gate_decision":true,"gates":[{"id":"tk-g1","blocks":"tk-vis1","demand":"should the merge wait?"},{"id":"tk-g2","blocks":"tk-sub1","demand":"ship it\nnow #(x)"},{"id":"tk-g3","blocks":"tk-sub1","demand":""}]}'
FAKE_HELM_RC=5 FAKE_HELM_OUT="$HELD" FAKE_HELM_ERR="  Resolve only a ruling you hold; absent one, leave it open — never resolve a gate just to close a conversation." run s-lx-conv1
has "$SAID" "NOT dismissed — tk-sub1 carries open linked gate(s)" "(GATE) a held dismiss is reported as not dismissed, on its subject"
has "$SAID" 'tk-g1 (blocks tk-vis1) "should the merge wait?"' "(GATE) …naming each gate, the bead it blocks and its question"
has "$SAID" 'tk-g2 (blocks tk-sub1)' "(GATE) …every gate, not only the first"
has "$SAID" '"ship it now ##(x)"' "(GATE) …a question on one line, its # doubled"
has "$SAID" 'tk-g3 (blocks tk-sub1) "<no headline>"' "(GATE) …and a gate with no question is still named"
has "$SAID" '--resolve-gate <gate> --ruling "<decision>"' "(GATE) …with the resolve decision"
has "$SAID" "--leave-gate <gate>" "(GATE) …and the leave decision"
hasnt "$SAID" "Resolve only a ruling you hold" "(GATE) …not dismiss's last stderr line, which names no gate"
hasnt "$SAID" "is over" "(GATE) …and the sitting is not claimed ended"
quiet "gate hold"
FAKE_HELM_RC=5 FAKE_HELM_OUT="" FAKE_HELM_ERR="gc-helm: dismiss: something else" run s-lx-conv1
has "$SAID" "NOT dismissed — gc-helm: dismiss: something else" "(GATE) an exit 5 without the held object is an ordinary refusal"

echo "# a dismiss that found nothing open says so"
FAKE_HELM_OUT='{"subject":"tk-sub1","matched":[],"closed":0,"ok":true}' run s-lx-conv1
has "$SAID" "no open visit on tk-sub1" "(NOOP) nothing was holding a sitting"

echo "# shown text is never expanded as a tmux format"
run 's-#(touch pwned)'
has "$SAID" "'s-##(touch pwned)'" "(FMT) a # is doubled in the message"
hasnt "$SAID" "'s-#(touch pwned)'" "(FMT) …so no #( reaches tmux unescaped"

echo "# a config dir without gc-helm.sh is reported"
mkdir -p "$TMP/empty"
RUN_CFG="$TMP/empty" run s-lx-conv1
eq "$HELM" "" "(NOHELM) nothing runs"
has "$SAID" "gc-helm.sh not found" "(NOHELM) …and the message names the fault"
quiet "no gc-helm"

###############################################################################
# BIND — what tmux-bindings.sh installs.
###############################################################################
if command -v tmux >/dev/null 2>&1; then
    env -u TMUX -u TMUX_PANE tmux -L "$SOCKET" -f /dev/null new-session -d -x 80 -y 24 'sleep 600' >/dev/null 2>&1
    BIND_RC=0
    GC_TMUX_SOCKET="$SOCKET" GC_CITY_PATH=/my/city sh "$BINDINGS" "$CFG" >/dev/null 2>&1 || BIND_RC=$?
    eq "$BIND_RC" 0 "(BIND) tmux-bindings.sh installs cleanly"
    bound=$(tmux -L "$SOCKET" list-keys -T prefix 2>/dev/null | grep -E '^bind-key +-T prefix +X ' || true)
    has "$bound" "confirm-before" "(BIND) prefix+X asks before it acts"
    has "$bound" "run-shell -b" "(BIND) …then backgrounds the script, so a slow store never holds tmux"
    has "$bound" "tmux-dismiss-sitting.sh" "(BIND) …and the script is the one run"
    hasnt "$bound" "send-keys" "(BIND) nothing is typed into the pane"
    hasnt "$bound" "#{" "(BIND) no format rides through confirm-before's expansion"
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
else
    skip "(BIND) tmux not installed"
fi

###############################################################################
# LIVE — real key presses through a real pty client.
###############################################################################
# script(1) supplies the pty; \002 is C-b, the prefix on a server started with
# -f /dev/null. The TERM is resolved by attaching rather than by name, because
# tmux refuses a client under a terminal it cannot drive and an agent shell
# often has none; a machine with no usable entry skips the live half. The
# oracle is the client-attached hook firing, positive evidence a client
# connected.
term_attaches() {       # term_attaches <term>
    local t=$1 flag="$TMP/term-attached" rc=1
    rm -f "$flag"
    tmux -L "$PROBE_SOCKET" kill-server >/dev/null 2>&1 || true
    env -u TMUX -u TMUX_PANE tmux -L "$PROBE_SOCKET" -f /dev/null new-session -d -x 80 -y 24 'sleep 30' >/dev/null 2>&1 || return 1
    tmux -L "$PROBE_SOCKET" set-hook -g client-attached "run-shell \"touch '$flag'\"" >/dev/null 2>&1 || true
    { sleep 0.7; printf '\002d'; sleep 0.3; } \
        | TERM="$t" script -qec "tmux -L $PROBE_SOCKET attach" /dev/null >/dev/null 2>&1
    [ -f "$flag" ] && rc=0
    tmux -L "$PROBE_SOCKET" kill-server >/dev/null 2>&1 || true
    rm -f "$flag"
    return $rc
}

LIVE_TERM=""
if command -v tmux >/dev/null 2>&1 && command -v script >/dev/null 2>&1; then
    for cand in "${TERM:-}" xterm-256color xterm screen ansi vt100; do
        [ -n "$cand" ] || continue
        if term_attaches "$cand"; then LIVE_TERM="$cand"; break; fi
    done
fi

# press <session> <answer> [<predicate> args…] — attach to <session>, press
# prefix+X, answer the confirm prompt, and detach once the predicate holds. The
# script's messages go to the client that pressed the key, so the client stays
# attached until the outcome is shown; a message aimed at a client that has
# already detached is never shown at all. The message log is copied to
# PRESS_MSGS before the detach, because tmux 3.4 answers show-messages with
# "no current client" once no client is attached.
PRESS_MSGS="$TMP/press-messages"
press() {
    local s="$1" answer="$2"; shift 2
    : > "$PRESS_MSGS"
    { sleep 1.2; printf '\002'; sleep 0.4; printf 'X'; sleep 0.8; printf '%s' "$answer"
      if [ $# -gt 0 ]; then wait_for "$@"; sleep 0.3; else sleep 1.5; fi
      tmux -L "$SOCKET" show-messages > "$PRESS_MSGS" 2>&1
      printf '\002d'; sleep 0.4
    } | TERM="$LIVE_TERM" script -qec "tmux -L $SOCKET attach -t $s" /dev/null >/dev/null 2>&1
}

if [ -n "$LIVE_TERM" ]; then
    # The config dir's path carries a space, a single quote, a $ and a double
    # quote: confirm-before parses the run-shell body a second time, and only a
    # body quoted for both layers reaches the script with its path intact.
    LIVE_CFG="$TMP/live cfg'\$x\"q"; mkcfg "$LIVE_CFG"
    LIVE_CITY="$TMP/the city"
    LIVE_CALLS="$TMP/live-helm.log"; : > "$LIVE_CALLS"
    # livebin holds ONLY gc, so the real tmux and script still resolve. The
    # server starts with it on PATH and with the stubs' inputs in its global
    # environment, which run-shell jobs inherit. It starts with no TMUX,
    # TMUX_PANE or GC_TMUX_SOCKET from this shell, and GC_TMUX_SOCKET then names
    # the private socket, so every tmux call a job makes lands on this server
    # and never on the one the suite happens to run under.
    mkdir -p "$TMP/livebin"; cp "$TMP/bin/gc" "$TMP/livebin/gc"
    env -u TMUX -u TMUX_PANE -u GC_TMUX_SOCKET PATH="$TMP/livebin:$PATH" \
        tmux -L "$SOCKET" -f /dev/null new-session -d -s s-lx-conv1 -x 100 -y 30 'sleep 600' >/dev/null 2>&1
    tmux -L "$SOCKET" new-session -d -s gc-toolkit__polecat-lx-pole1 -x 100 -y 30 'sleep 600' >/dev/null 2>&1
    tmux -L "$SOCKET" set-environment -g GC_TMUX_SOCKET "$SOCKET" >/dev/null 2>&1
    tmux -L "$SOCKET" set-environment -g HELM_CALLS "$LIVE_CALLS" >/dev/null 2>&1
    tmux -L "$SOCKET" set-environment -g FAKE_LIST "$SESSIONS" >/dev/null 2>&1
    GC_TMUX_SOCKET="$SOCKET" GC_CITY_PATH="$LIVE_CITY" sh "$BINDINGS" "$LIVE_CFG" >/dev/null 2>&1

    echo "# LIVE: prefix+X, y in a converse pane"
    press s-lx-conv1 y msg_has "the sitting on tk-sub1 is over"
    live=$(cat "$LIVE_CALLS" 2>/dev/null)
    has "$live" "ARGS=dismiss --json" "(LIVE-YES) a real press, confirmed, runs dismiss"
    eq "$(grep -c '^ARGS=' "$LIVE_CALLS")" "1" "(LIVE-YES) …exactly once"
    has "$live" "GC_SESSION_NAME=s-lx-conv1" "(LIVE-YES) …under the pressed pane's session"
    has "$live" "GC_ALIAS=gc-toolkit/gc-toolkit.tk-vis1" "(LIVE-YES) …and its alias"
    has "$live" "GC_CITY_PATH=$LIVE_CITY" "(LIVE-YES) …with the city path baked in at install"
    has "$(cat "$PRESS_MSGS")" "the sitting on tk-sub1 is over" "(LIVE-YES) the outcome reaches the operator"
    # View mode would open as the job exits, just after its last message, so
    # give the exit a beat before reading the pane.
    sleep 1
    eq "$(tmux -L "$SOCKET" display-message -p -t s-lx-conv1 '#{pane_in_mode}' 2>/dev/null)" "0" \
        "(LIVE-YES) the pane is not put into view mode over the thread"

    echo "# LIVE: prefix+X, n — then y in a polecat pane"
    : > "$LIVE_CALLS"
    press s-lx-conv1 n
    # The refused press below is the barrier: once its message is shown, the
    # declined press before it has had every chance to run something.
    press gc-toolkit__polecat-lx-pole1 y msg_has "is not a converse sitting"
    has "$(cat "$PRESS_MSGS")" "is not a converse sitting" "(LIVE-GUARD) a confirmed press in a polecat pane is refused out loud"
    eq "$(cat "$LIVE_CALLS")" "" "(LIVE-NO) declining the prompt runs nothing, and (LIVE-GUARD) neither does the refused pane"
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
else
    skip "(LIVE) tmux, script(1) or a TERM tmux can attach under is missing"
fi

echo
echo "passed: $PASS  failed: $FAIL  skipped: $SKIP"
[ "$FAIL" -eq 0 ]
