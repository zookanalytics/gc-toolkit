#!/usr/bin/env bash
# rig-root.sh — print the path of a rig's checkout, the path a formula step
# names its repository by.
#
# Usage:
#   rig-root.sh               the rig this session works: GC_RIG_ROOT, else the
#                             roster entry for GC_RIG
#   rig-root.sh --rig <name>  the roster entry for <name>, whatever GC_RIG_ROOT
#                             says, for a formula that works one fixed rig
#
# A step that chooses a repository names it as `git -C "$ROOT"`, because
# nothing pins a session's cwd between steps. An empty root would let
# `git -C ""` run in the cwd, so a rig that does not resolve prints nothing and
# exits 1 with the reason on stderr, and the caller decides what that stops. A
# roster entry resolves only when one path carries the name.
#
# Exit: 0 printed the path; 1 no path resolved; 2 usage.
set -u

PROG="rig-root.sh"
usage() { echo "usage: $PROG [--rig <name>]" >&2; exit 2; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

NAME=""; NAMED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rig) [ $# -ge 2 ] && [ -n "$2" ] || usage; NAME="$2"; NAMED=1; shift 2 ;;
    *) usage ;;
  esac
done

if [ -z "$NAMED" ]; then
  if [ -n "${GC_RIG_ROOT:-}" ]; then
    printf '%s\n' "$GC_RIG_ROOT"
    exit 0
  fi
  NAME="${GC_RIG:-}"
  if [ -z "$NAME" ]; then
    echo "$PROG: cannot resolve the rig root: GC_RIG_ROOT and GC_RIG are both unset" >&2
    exit 1
  fi
  WHAT="GC_RIG_ROOT unset, and GC_RIG='$NAME'"
else
  WHAT="'$NAME'"
fi

PATHS=$(gc rig list --json 2>/dev/null | scrub \
  | jq -r --arg r "$NAME" '[.rigs[]? | objects | select(.name == $r) | .path | strings | select(. != "")] | unique | .[]' 2>/dev/null)
case "$(printf '%s' "$PATHS" | awk 'NF { n++ } END { print n + 0 }')" in
  1) printf '%s\n' "$PATHS" ;;
  0) echo "$PROG: cannot resolve the rig root: $WHAT matched no rig in the roster" >&2; exit 1 ;;
  *) echo "$PROG: cannot resolve the rig root: $WHAT matched more than one rig path in the roster" >&2; exit 1 ;;
esac
