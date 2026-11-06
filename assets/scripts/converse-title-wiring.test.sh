#!/usr/bin/env bash
# converse-title-wiring.test.sh — a converse sitting's tmux session passes its
# pane title on to the terminal of a client attached to it, so the operator's
# tab shows the title the sitting sets with `gctk session title`.
#
# The setting rides each converse-<model> template's session_live, beside the
# detach-on-destroy command converse-detach-wiring.test.sh covers. Gas City
# expands {{.Session}} in it and runs it under sh -c with GC_TMUX_SOCKET naming
# the city's tmux server, after every start of the session. This suite reads
# the command from every template and replays it the same way against a private
# tmux server whose global set-titles is off, as the city's is.
#
#   (WIRED) every converse-<model> template carries one session_live command
#           that sets set-titles, the same in each, and it names the session by
#           the {{.Session}} placeholder
#   (SET)   the command sets set-titles on and set-titles-string #T on the
#           sitting's session alone: a session whose name the sitting's name
#           prefixes keeps no value of its own, even once the sitting's session
#           has gone, and the server's global values are left as they are
#   (AGAIN) running it again, as a re-apply does, succeeds and leaves them so
#   (CARRY) a client attached to the sitting from the pane of a second tmux
#           server, which stands in for the operator's terminal, gives that
#           pane the sitting's pane title, and a later title too; a client
#           attached to a session without the setting gives it no such title
#
# The live checks need tmux, and are skipped with a notice where it is missing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/../.."
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-title-test.XXXXXX")"
SOCK="gcttl-test-$$"
OUTER_SOCK="gcttl-outer-$$"
# kill-server leaves the socket file behind, so the suite removes its own.
SOCKET_DIR="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
T() { env -u TMUX -u TMUX_PANE -u GC_TMUX_SOCKET tmux -L "$SOCK" -f /dev/null "$@"; }
O() { env -u TMUX -u TMUX_PANE -u GC_TMUX_SOCKET tmux -L "$OUTER_SOCK" -f /dev/null "$@"; }
cleanup() {
    O kill-server >/dev/null 2>&1 || true
    T kill-server >/dev/null 2>&1 || true
    rm -f "$SOCKET_DIR/$SOCK" "$SOCKET_DIR/$OUTER_SOCK"
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
    echo "converse-title-wiring: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 1
fi
command -v python3 >/dev/null 2>&1 || { bad "(WIRED) python3 is required to read the templates"; exit 1; }

# titles_live <agent.toml> — the field's entries that set set-titles, one per
# line; a field that is not a list of strings prints a line that matches no
# command.
titles_live() {
    python3 -I -c '
import sys, tomllib
v = tomllib.load(open(sys.argv[1], "rb")).get("session_live", [])
if not (isinstance(v, list) and all(isinstance(x, str) for x in v)):
    print("<session_live is not a list of strings>")
else:
    for x in v:
        if "set-titles" in x:
            print(x)
' "$1"
}

CMD=""
for SITTING in "${SITTINGS[@]}"; do
    NAME="$(basename "$(dirname "$SITTING")")"
    LIVE="$(titles_live "$SITTING")"
    if [ "$(printf '%s\n' "$LIVE" | grep -c .)" != "1" ]; then
        bad "(WIRED) $NAME carries one session_live command that sets set-titles (got: ${LIVE:-none})"
        continue
    fi
    if [ -z "$CMD" ]; then
        CMD="$LIVE"
        ok "(WIRED) $NAME carries one session_live command that sets set-titles"
    else
        eq "$LIVE" "$CMD" "(WIRED) $NAME carries the same set-titles command as the others"
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
    skip "(SET) (AGAIN) (CARRY) tmux is not installed"
    echo "converse-title-wiring: $PASS passed, $FAIL failed, $SKIP skipped"
    [ "$FAIL" -eq 0 ]; exit
fi

SIT="gc-toolkit__converse-opus-hq-t$$"
SIB="${SIT}9"
T new-session -d -s "$SIT" -x 80 -y 24 'sleep 600' >/dev/null 2>&1
T new-session -d -s "$SIB" -x 80 -y 24 'sleep 600' >/dev/null 2>&1
T set-option -g set-titles off >/dev/null 2>&1
GLOBAL_STRING="$(T show-options -g -v set-titles-string 2>&1)"

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
eq "$(T show-options -t "=$SIT:" -v set-titles 2>&1)" "on" \
   "(SET) the sitting's session reads set-titles on"
eq "$(T show-options -t "=$SIT:" -v set-titles-string 2>&1)" "#T" \
   "(SET) the sitting's session reads set-titles-string #T, its pane's title"
eq "$(T show-options -t "=$SIB:" set-titles 2>&1)$(T show-options -t "=$SIB:" set-titles-string 2>&1)" "" \
   "(SET) a session whose name the sitting's name prefixes keeps no value of its own"
eq "$(T show-options -g -v set-titles 2>&1)" "off" \
   "(SET) the server's global set-titles is left as it is"
eq "$(T show-options -g -v set-titles-string 2>&1)" "$GLOBAL_STRING" \
   "(SET) the server's global set-titles-string is left as it is"
# A run whose session has already gone must not reach the session its name
# prefixes, which a target without the exact-match "=" would.
GONE="gc-toolkit__converse-opus-gone-t$$"
T new-session -d -s "${GONE}9" -x 80 -y 24 'sleep 600' >/dev/null 2>&1
run_live "$GONE" >/dev/null 2>&1
eq "$(T show-options -t "=${GONE}9:" set-titles 2>&1)" "" \
   "(SET) for a session that has gone, it sets nothing on a session its name prefixes"
if run_live "$SIT" >"$TMP/again.out" 2>&1; then
    ok "(AGAIN) running it again succeeds"
else
    bad "(AGAIN) running it again succeeds ($(tr '\n' ' ' < "$TMP/again.out"))"
fi
eq "$(T show-options -t "=$SIT:" -v set-titles 2>&1)" "on" \
   "(AGAIN) …and leaves set-titles on"

###############################################################################
# (CARRY) — a client's terminal, played by a pane of a second tmux server.
###############################################################################
# outer <name> <session> — an outer session whose pane runs a client attached
# to <session> on the sitting's server. The client names an xterm terminal,
# whose terminfo every host carries and which tmux sets titles on.
outer() {
    O new-session -d -s "$1" -x 90 -y 26 \
        "env -u TMUX -u TMUX_PANE TERM=xterm-256color tmux -L $SOCK attach-session -t =$2" >/dev/null 2>&1
}
attached() { grep -qxF -- "$1" < <(T list-clients -F '#{client_session}' 2>/dev/null); }
outer_title() { O display-message -p -t "=$1:" '#{pane_title}' 2>/dev/null; }
outer_shows() { [ "$(outer_title "$1")" = "$2" ]; }

FIRST="tk-test — the sitting's first topic"
LATER="tk-test — the sitting's next topic"
O new-session -d -s keep -x 90 -y 26 'sleep 600' >/dev/null 2>&1
outer on "$SIT"
if wait_for attached "$SIT"; then
    T select-pane -t "=$SIT:" -T "$FIRST" >/dev/null 2>&1
    if wait_for outer_shows on "$FIRST"; then
        ok "(CARRY) the client's terminal takes the sitting's pane title"
    else
        bad "(CARRY) the client's terminal takes the sitting's pane title (got '$(outer_title on)')"
    fi
    T select-pane -t "=$SIT:" -T "$LATER" >/dev/null 2>&1
    if wait_for outer_shows on "$LATER"; then
        ok "(CARRY) …and a later title"
    else
        bad "(CARRY) …and a later title (got '$(outer_title on)')"
    fi
else
    bad "(CARRY) a client attached to the sitting"
fi

outer off "$SIB"
if wait_for attached "$SIB"; then
    T select-pane -t "=$SIB:" -T "$FIRST" >/dev/null 2>&1
    # Nothing arrives to wait for: give the title the time the sitting's took.
    sleep 1
    if [ "$(outer_title off)" != "$FIRST" ]; then
        ok "(CARRY) a client on a session without the setting gives its terminal no such title"
    else
        bad "(CARRY) a client on a session without the setting gives its terminal no such title"
    fi
else
    bad "(CARRY) a client attached to the session without the setting"
fi

echo "converse-title-wiring: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
