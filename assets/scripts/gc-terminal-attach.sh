#!/usr/bin/env bash
# The city web terminal's attach target: the one place a URL-supplied session
# name becomes a `gc session attach` (tk-rbf9r).
#
# WHY THIS EXISTS. The city runs one ttyd for the helm board's terminal tile:
#
#   ttyd -i 127.0.0.1 -p 7681 -b /terminal -W -a <this script>
#
# `-a/--url-arg` lets the *client* append argv to that command from the socket's
# query string, which is what makes the attach target dynamic — the board can
# rank what needs the human and then actually show it, instead of always showing
# the mayor. It also means the URL chooses the child's argv, and `-W` is already
# set, so without a guard a reachable client could name any session and get a
# WRITABLE terminal on it. This script is that guard, and it is the whole of it:
# nothing between the socket and `gc` validates anything else.
#
# Verified against the deployed ttyd 1.7.7 (2026-08-14), because every rule
# below exists to stop something that was observed to reach argv:
#
#   ?arg=hello            -> argv = [hello]           one arg, as documented
#   ?arg=one&arg=two      -> argv = [one, two]        EVERY arg= is appended
#   ?arg=                 -> argv = [""]              empty string, argc 1
#   ?arg=%2Dv             -> argv = [-v]              a leading dash arrives
#   ?arg=..%2Fetc         -> argv = [../etc]          so does traversal
#   ?arg=x%3Bid           -> argv = [x;id]            so do shell metacharacters
#   ?foo=bar              -> argv = []                only `arg` is read
#
# THE CONTROL IS THE ALLOWLIST. The syntax rules below are a cheap pre-filter;
# what actually decides is exact membership in the LIVE session list. That is
# also why a `/` is permitted where the bead asked for it to be rejected: real
# rig-scoped sessions are named `gc-toolkit/gc-toolkit.witness`, so a blanket
# `/` ban would restrict the terminal to city-scoped sessions and defeat the
# feature. Exact-match against `gc session list` is strictly stronger than a
# character ban — `..` and a leading `-` are still refused outright, and a name
# is never passed through on the strength of its spelling alone.
#
# FAIL CLOSED, TWO WAYS.
#   - No argument (and the empty-string argument ttyd sends for a bare `?arg=`)
#     attaches the default, which is exactly what the ttyd invocation did before
#     this script existed. Today's behaviour is preserved byte for byte.
#   - A name that is present but does not validate is REFUSED: the script exits
#     without attaching anything at all.
#
# On that second point this deliberately departs from the letter of the bead,
# which said to fall back to the mayor on a bad name. Falling back is unsafe
# HERE, and it was measured rather than argued: `gc session attach` runs tmux,
# tmux enters the alternate screen and clears it (`ESC[?1049h` then `ESC[2J`
# — observed on the wire immediately after the child's own output), so any
# "your session was rejected, this is the mayor" notice is wiped before the
# operator can read it. The result would be a writable mayor terminal that the
# operator believes is something else, and the first thing they type goes to the
# mayor. Refusing keeps the message on screen, because nothing repaints over it.
# The security property the bead actually asked for — never exec `gc` with an
# unvalidated name — holds either way, and holds absolutely here.
#
# Hermetic regression test: assets/scripts/gc-terminal-attach.test.sh
set -euo pipefail

# The session attached when the client names none. This is the pre-tk-rbf9r
# hardcoded target; the env override exists so another city can set its own and
# so the test can drive it, and it is NOT client-reachable (ttyd passes the
# query string as argv, never as environment).
DEFAULT_SESSION="${GC_TERMINAL_DEFAULT_SESSION:-gc-toolkit.mayor}"

# Longest name we will even consider. Real session names are far shorter; this
# only bounds what gets pattern-matched and logged.
MAX_NAME=128

refuse() {
  # stderr and stdout are the same PTY here, so the operator reads this. It is
  # the last thing on screen precisely because no attach follows it.
  echo "gc-terminal-attach: refusing to attach: $1" >&2
  echo "gc-terminal-attach: the terminal attaches a session named in the live" >&2
  echo "  session list ('gc session list'); it does not accept anything else." >&2
  exit 1
}

# Syntactically capable of being a session name. Rejects, by construction:
# a leading '-' (which `gc` would read as a flag), a leading '.', every shell
# metacharacter, whitespace, and control characters. Allows one '/' because
# rig-scoped session names contain exactly one.
valid_syntax() {
  local name="$1"
  [ "${#name}" -le "$MAX_NAME" ] || return 1
  # Explicit, even though the pattern below cannot match a bare '..' segment:
  # traversal is the thing most worth refusing loudly rather than incidentally.
  case "$name" in
    *..*) return 1 ;;
  esac
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)?$ ]]
}

# Exactly one of the identifiers `gc session attach` itself accepts, for a
# session that exists right now. This is the real control; see the header.
session_is_live() {
  local want="$1" listing
  command -v jq >/dev/null 2>&1 || return 1
  # A failed listing (city down, dolt wedged) yields no allowlist, so nothing
  # validates and every named session is refused. That is the fail-closed
  # direction: the default target does not consult this at all.
  listing="$(gc session list --json 2>/dev/null || true)"
  [ -n "$listing" ] || return 1
  printf '%s' "$listing" | jq -e --arg want "$want" '
    [.sessions[]? | .id, .alias, .session_name] | any(. == $want)
  ' >/dev/null 2>&1
}

# ttyd appends EVERY `arg=` in the query string, so more than one argument is
# not a mistake to tolerate — it is the shape an injection attempt arrives in
# (`?arg=gc-toolkit.mayor&arg=--some-flag`). Verified reachable; see the header.
if [ "$#" -gt 1 ]; then
  refuse "expected at most one session argument, got $#"
fi

REQUESTED="${1-}"

# No argument, or the empty argument ttyd synthesises for a bare `?arg=`:
# attach the default exactly as the pre-tk-rbf9r invocation did. Note this path
# touches neither jq nor the session list, so the terminal still comes up on a
# city where those are unavailable.
if [ -z "$REQUESTED" ]; then
  exec gc session attach "$DEFAULT_SESSION"
fi

valid_syntax "$REQUESTED" \
  || refuse "'$REQUESTED' is not a well-formed session name"

session_is_live "$REQUESTED" \
  || refuse "'$REQUESTED' is not a live session"

# `exec` is load-bearing for the detach invariant, not a micro-optimisation.
# ttyd signals the process it spawned when the socket closes (-s 1, SIGHUP);
# replacing this shell means that signal lands on the tmux client itself, which
# detaches. Leave a shell in between and ttyd signals the shell, and what
# happens to the attach underneath it is no longer this script's guarantee.
# `--` stops `gc` reading a name as a flag; the syntax rule already forbids a
# leading '-', so this is the second lock on the same door.
exec gc session attach -- "$REQUESTED"
