#!/usr/bin/env bash
# converse-detach-wiring.test.sh — a converse sitting's tmux session carries
# detach-on-destroy on, so a plain client attached to it exits when the sitting
# ends, while a client attached with -f no-detach-on-destroy, and any client on
# another session, moves to another session.
#
# The option rides each converse-<model> template's session_live. Gas City
# expands {{.Session}} in it and runs it under sh -c with GC_TMUX_SOCKET naming
# the city's tmux server, after every start of the session. This suite reads the
# command from every template and replays it the same way against a private
# tmux server whose global detach-on-destroy is off.
#
#   (WIRED) every converse-<model> template carries the same one session_live
#           command, and it names the session by the {{.Session}} placeholder
#   (SET)   the command sets the option on the sitting's session alone: a
#           session whose name the sitting's name prefixes keeps no value of its
#           own, and the server's global value is left as it is
#   (AGAIN) running it again, as a re-apply does, succeeds and leaves it on
#   (EXITS) a plain client on the sitting exits, shown [exited], when the
#           session is destroyed
#   (FLAG)  a client attached with -f no-detach-on-destroy stays attached, on
#           another session
#   (OTHER) a plain client on a session that has no value of its own stays
#           attached, on another session
#
# The client checks need tmux, script(1) and a TERM tmux attaches under; they
# are skipped with a notice where any is missing. script(1) is util-linux's
# (`script -qec <cmd> <file>`) on CI and BSD's (`script -q <file> <cmd…>`) on
# macOS, and the suite uses whichever the host has.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/../.."
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-detach-test.XXXXXX")"
SOCK="gcdod-test-$$"
PROBE_SOCK="gcdod-probe-$$"
# kill-server leaves the socket file behind, so the suite removes its own.
SOCKET_DIR="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
T() { env -u TMUX -u TMUX_PANE -u GC_TMUX_SOCKET tmux -L "$SOCK" -f /dev/null "$@"; }
cleanup() {
    tmux -L "$SOCK" kill-server >/dev/null 2>&1 || true
    tmux -L "$PROBE_SOCK" kill-server >/dev/null 2>&1 || true
    rm -f "$SOCKET_DIR/$SOCK" "$SOCKET_DIR/$PROBE_SOCK"
    local f
    for f in "$TMP"/*.feeder; do
        [ -f "$f" ] && kill "$(cat "$f")" >/dev/null 2>&1
    done
    rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
skip() { SKIP=$((SKIP + 1)); echo "skip - $1"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

WAIT_SECS="${GC_TMUX_TEST_WAIT_SECS:-15}"
wait_for() {            # wait_for <predicate> [args…]
    local _deadline=$(( SECONDS + WAIT_SECS ))
    while :; do
        "$@" && return 0
        [ "$SECONDS" -ge "$_deadline" ] && return 1
        sleep 0.1
    done
}

###############################################################################
# (WIRED) — the command every template carries.
###############################################################################
SITTINGS=("$REPO"/agents/converse-*/agent.toml)
if [ ! -f "${SITTINGS[0]}" ]; then
    bad "(WIRED) no converse-<model> template under $REPO/agents"
    echo "converse-detach-wiring: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 1
fi
command -v python3 >/dev/null 2>&1 || { bad "(WIRED) python3 is required to read the templates"; exit 1; }

# session_live <agent.toml> — the field's entries, one per line; a field that is
# not a list of strings prints a line that matches no command.
session_live() {
    python3 -I -c '
import sys, tomllib
v = tomllib.load(open(sys.argv[1], "rb")).get("session_live", [])
if not (isinstance(v, list) and all(isinstance(x, str) for x in v)):
    print("<session_live is not a list of strings>")
else:
    for x in v:
        print(x)
' "$1"
}

CMD=""
for SITTING in "${SITTINGS[@]}"; do
    NAME="$(basename "$(dirname "$SITTING")")"
    LIVE="$(session_live "$SITTING")"
    if [ "$(printf '%s\n' "$LIVE" | grep -c .)" != "1" ]; then
        bad "(WIRED) $NAME carries one session_live command (got: ${LIVE:-none})"
        continue
    fi
    if [ -z "$CMD" ]; then
        CMD="$LIVE"
        ok "(WIRED) $NAME carries one session_live command"
    else
        eq "$LIVE" "$CMD" "(WIRED) $NAME carries the same session_live command as the others"
    fi
done
case "$CMD" in
    *'{{.Session}}'*) ok "(WIRED) the command names the session by {{.Session}}" ;;
    *) bad "(WIRED) the command names the session by {{.Session}} (got: ${CMD:-none})" ;;
esac

###############################################################################
# (SET) (AGAIN) — the command, replayed the way Gas City runs it.
###############################################################################
if ! command -v tmux >/dev/null 2>&1; then
    skip "(SET) tmux is not installed"
    echo "converse-detach-wiring: $PASS passed, $FAIL failed, $SKIP skipped"
    [ "$FAIL" -eq 0 ]; exit
fi

SIT="gc-toolkit__converse-opus-lx-t$$"
SIB="${SIT}9"
ELSEWHERE="elsewhere"
# The global value is set once the server exists: `set -g` before the first
# new-session finds no server.
T new-session -d -s "$ELSEWHERE" -x 80 -y 24 'sleep 600' >/dev/null 2>&1
T set-option -g detach-on-destroy off >/dev/null 2>&1
T new-session -d -s "$SIT" -x 80 -y 24 'sleep 600' >/dev/null 2>&1
T new-session -d -s "$SIB" -x 80 -y 24 'sleep 600' >/dev/null 2>&1

# run_live <session> — the command as Gas City runs it: the placeholder
# expanded, sh -c, GC_SESSION and GC_TMUX_SOCKET in the environment.
run_live() {
    local expanded="${CMD//'{{.Session}}'/$1}"
    env -u TMUX -u TMUX_PANE GC_TMUX_SOCKET="$SOCK" GC_SESSION="$1" sh -c "$expanded"
}

if run_live "$SIT" >"$TMP/set.out" 2>&1; then
    ok "(SET) the command runs clean"
else
    bad "(SET) the command runs clean ($(tr '\n' ' ' < "$TMP/set.out"))"
fi
eq "$(T show-options -t "=$SIT:" -v detach-on-destroy 2>&1)" "on" \
   "(SET) the sitting's session reads detach-on-destroy on"
eq "$(T show-options -t "=$SIB:" detach-on-destroy 2>&1)" "" \
   "(SET) a session whose name the sitting's name prefixes keeps no value of its own"
eq "$(T show-options -g -v detach-on-destroy 2>&1)" "off" \
   "(SET) the server's global value is left as it is"
if run_live "$SIT" >"$TMP/again.out" 2>&1; then
    ok "(AGAIN) running it again succeeds"
else
    bad "(AGAIN) running it again succeeds ($(tr '\n' ' ' < "$TMP/again.out"))"
fi
eq "$(T show-options -t "=$SIT:" -v detach-on-destroy 2>&1)" "on" \
   "(AGAIN) …and leaves the option on"

###############################################################################
# (EXITS) (FLAG) (OTHER) — real clients on a pty.
###############################################################################
# The form check reads /dev/null: BSD script refuses a socket as its stdin, and
# an agent's shell can hand the suite one.
SCRIPT_FORM=""
if command -v script >/dev/null 2>&1; then
    if script -qec true /dev/null </dev/null >/dev/null 2>&1; then SCRIPT_FORM=util
    elif script -q /dev/null true </dev/null >/dev/null 2>&1; then SCRIPT_FORM=bsd
    fi
fi

# client <name> <server> <attach-session args…> — one pty client in the
# background, its output in $TMP/<name>.out and script(1)'s pid in CLIENT_PID.
# Its stdin is a pipe a sleeping writer holds open, so util-linux script never
# reads end-of-file and hangs up the client first. BSD script refuses a FIFO as
# its stdin, so the writer is a pipeline member, and its pid goes to
# $TMP/<name>.feeder for cleanup to kill.
CLIENT_PID=""
client() {
    local name="$1" server="$2"; shift 2
    local cmd="tmux -L $server attach-session $*"
    if [ "$SCRIPT_FORM" = util ]; then
        { sleep 120 & echo "$!" > "$TMP/$name.feeder"; wait; } 2>/dev/null \
            | env -u TMUX -u TMUX_PANE TERM="$LIVE_TERM" script -qec "$cmd" /dev/null > "$TMP/$name.out" 2>&1 &
    else
        { sleep 120 & echo "$!" > "$TMP/$name.feeder"; wait; } 2>/dev/null \
            | env -u TMUX -u TMUX_PANE TERM="$LIVE_TERM" script -q /dev/null sh -c "$cmd" > "$TMP/$name.out" 2>&1 &
    fi
    CLIENT_PID=$!
}
clients_on() {          # clients_on <server> <session> — some client shows <session>
    grep -qxF -- "$2" < <(tmux -L "$1" list-clients -F '#{client_session}' 2>/dev/null)
}
no_clients() { [ -z "$(tmux -L "$1" list-clients 2>/dev/null)" ]; }
one_client_elsewhere() {   # one_client_elsewhere <server> <gone-session>
    local s; s=$(tmux -L "$1" list-clients -F '#{client_session}' 2>/dev/null)
    [ "$(printf '%s\n' "$s" | grep -c .)" = "1" ] && [ "$s" != "$2" ]
}

# term_attaches <term> — a client attaches under this TERM on a throwaway server.
# A TERM tmux cannot drive ends the client at once, so the wait stops when the
# client is listed or when its script(1) has exited, and a loaded host gets the
# whole budget.
attached_or_gone() { clients_on "$PROBE_SOCK" probe || ! kill -0 "$CLIENT_PID" 2>/dev/null; }
term_attaches() {
    local rc=1
    LIVE_TERM="$1"
    tmux -L "$PROBE_SOCK" kill-server >/dev/null 2>&1 || true
    env -u TMUX -u TMUX_PANE tmux -L "$PROBE_SOCK" -f /dev/null new-session -d -s probe -x 80 -y 24 'sleep 60' >/dev/null 2>&1 || return 1
    client "probe-$1" "$PROBE_SOCK" -t =probe
    wait_for attached_or_gone
    clients_on "$PROBE_SOCK" probe && rc=0
    tmux -L "$PROBE_SOCK" kill-server >/dev/null 2>&1 || true
    return $rc
}

LIVE_TERM=""
if [ -n "$SCRIPT_FORM" ]; then
    TRIED=" "
    for cand in "${TERM:-}" xterm-256color tmux-256color xterm screen ansi vt100; do
        [ -n "$cand" ] || continue
        case "$TRIED" in *" $cand "*) continue ;; esac
        TRIED="$TRIED$cand "
        if term_attaches "$cand"; then break; fi
        LIVE_TERM=""
    done
fi

if [ -z "$LIVE_TERM" ]; then
    skip "(EXITS) (FLAG) (OTHER) script(1) or a TERM tmux attaches under is missing"
else
    # (EXITS) — a plain client on the sitting.
    client exits "$SOCK" -t "=$SIT"
    if wait_for clients_on "$SOCK" "$SIT"; then
        T kill-session -t "=$SIT" >/dev/null 2>&1
        if wait_for no_clients "$SOCK"; then
            ok "(EXITS) a plain client on the sitting exits when its session is destroyed"
        else
            bad "(EXITS) a plain client on the sitting exits when its session is destroyed (clients: $(T list-clients -F '#{client_session}' | tr '\n' ' '))"
        fi
        wait_for grep -qF '[exited]' "$TMP/exits.out" \
            && ok "(EXITS) …and the client shows [exited]" \
            || bad "(EXITS) …and the client shows [exited] (output: $(tr -cd '[:print:]' < "$TMP/exits.out" | tail -c 120))"
    else
        bad "(EXITS) the client attached to the sitting"
    fi

    # (FLAG) — the same sitting, its option set again by a fresh start, and a
    # client that opted out of the detach.
    T new-session -d -s "$SIT" -x 80 -y 24 'sleep 600' >/dev/null 2>&1
    run_live "$SIT" >/dev/null 2>&1
    client flag "$SOCK" -f no-detach-on-destroy -t "=$SIT"
    if wait_for clients_on "$SOCK" "$SIT"; then
        T kill-session -t "=$SIT" >/dev/null 2>&1
        if wait_for one_client_elsewhere "$SOCK" "$SIT"; then
            ok "(FLAG) a client attached with -f no-detach-on-destroy moves to another session"
        else
            bad "(FLAG) a client attached with -f no-detach-on-destroy moves to another session (clients: $(T list-clients -F '#{client_session}' | tr '\n' ' '))"
        fi
        T list-clients -F '#{client_tty}' 2>/dev/null | while read -r tty; do T detach-client -t "$tty" >/dev/null 2>&1; done
        wait_for no_clients "$SOCK" || bad "(FLAG) the moved client detached at the end of the case"
    else
        bad "(FLAG) the client attached to the sitting"
    fi

    # (OTHER) — a plain client on a session with no value of its own.
    client other "$SOCK" -t "=$SIB"
    if wait_for clients_on "$SOCK" "$SIB"; then
        T kill-session -t "=$SIB" >/dev/null 2>&1
        if wait_for one_client_elsewhere "$SOCK" "$SIB"; then
            ok "(OTHER) a plain client on a session without the option moves to another session"
        else
            bad "(OTHER) a plain client on a session without the option moves to another session (clients: $(T list-clients -F '#{client_session}' | tr '\n' ' '))"
        fi
    else
        bad "(OTHER) the client attached to the session"
    fi
fi

echo "converse-detach-wiring: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
