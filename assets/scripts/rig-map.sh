#!/usr/bin/env bash
# rig-map.sh — the pack's one read of the city's rig map, `gc rig list --json`.
#
# usage: rig-map.sh [--city <path>]
#
# Prints the listing as one line of JSON whose .rigs is an array, and exits 0.
# When the listing does not read, it prints nothing on stdout, names the reason
# on stderr, and exits 3, so a caller never has to guess why it has no map. It
# writes to stderr only then, so a caller may capture both streams in one.
# --city reads the named city's map instead of the one gc resolves.
#
# GC_RIG_LIST_TIMEOUT, in whole seconds, is the one bound on the call. It exists
# to cut off a gc that never answers, so it sits far above what the listing
# takes on a loaded host (docs/bead-store-resolution.md, "Reading the rig map",
# says why the listing is slow). A caller under an outside deadline, such as a
# doctor check inside `gc doctor`'s, bounds this call by what it has left, as
# it bounds any other.
#
# Exit: 0 read · 2 usage · 3 the listing did not read
set -uo pipefail

PROG="rig-map"
DEFAULT_SECS=120

usage() { echo "usage: rig-map.sh [--city <path>]   (prints \`gc rig list --json\`, or names on stderr why it did not read; GC_RIG_LIST_TIMEOUT=<seconds> bounds it, default $DEFAULT_SECS)" >&2; exit 2; }
CITY=""
case "$#:${1:-}" in
  0:) ;;
  2:--city) CITY="$2"; [ -n "$CITY" ] || usage ;;
  *) usage ;;
esac

SECS="${GC_RIG_LIST_TIMEOUT:-$DEFAULT_SECS}"
case "$SECS" in
  *[!0-9]*|'') SECS_OK=0 ;;
  *) [ "$SECS" -gt 0 ] && SECS_OK=1 || SECS_OK=0 ;;
esac
[ "$SECS_OK" = 1 ] || { echo "$PROG: GC_RIG_LIST_TIMEOUT='$SECS' is not a whole number of seconds above 0" >&2; exit 2; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

fail() { echo "$PROG: $*" >&2; exit 3; }

command -v gc >/dev/null 2>&1 || fail "gc is not on PATH, so the rig map cannot be read"

TO=""
for t in timeout gtimeout; do command -v "$t" >/dev/null 2>&1 && { TO="$t"; break; }; done

# gc's stderr is kept for the reason a failed listing gives. With no writable
# scratch file to keep it in, the listing is still read and the reason goes
# without it.
ERRF=$(mktemp "${TMPDIR:-/tmp}/gctk-rig-map.XXXXXX" 2>/dev/null) || ERRF=""
{ [ -f "$ERRF" ] && [ -w "$ERRF" ]; } || ERRF=""
trap '[ -z "$ERRF" ] || rm -f "$ERRF"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

# --foreground keeps gc in this process group, so a caller's deadline that
# signals the group reaches gc as well as this script.
if [ -n "$TO" ]; then
  OUT=$("$TO" --foreground -k 5 "$SECS" gc ${CITY:+--city "$CITY"} rig list --json </dev/null 2>"${ERRF:-/dev/null}" | scrub); RC=$?
else
  OUT=$(gc ${CITY:+--city "$CITY"} rig list --json </dev/null 2>"${ERRF:-/dev/null}" | scrub); RC=$?
fi

if [ -n "$TO" ] && { [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; }; then
  fail "\`gc rig list --json\` did not answer within ${SECS}s and was killed. Check whether gc or Dolt is wedged, or raise the bound with GC_RIG_LIST_TIMEOUT=<seconds>."
fi
if [ "$RC" -ne 0 ]; then
  WHY=$(sed -n '/[^[:space:]]/{p;q;}' "${ERRF:-/dev/null}" | scrub | cut -c1-300)
  [ -n "$WHY" ] || WHY=$(printf '%s' "$OUT" | jq -r '.error.message? // empty' 2>/dev/null | cut -c1-300)
  fail "\`gc rig list --json\` exited $RC${WHY:+: $WHY}. That is gc's data plane: try 'gc doctor' and check Dolt."
fi
[ -n "$OUT" ] || fail "\`gc rig list --json\` exited 0 but printed nothing, which usually means gc was killed or the city path is wrong. Check GC_CITY and 'gc doctor'."
printf '%s' "$OUT" | jq empty >/dev/null 2>&1 \
  || fail "\`gc rig list --json\` printed something that is not JSON: $(printf '%s' "$OUT" | cut -c1-120). Run it by hand to see what it printed; a stray log line on stdout is the usual cause."
MAP=$(printf '%s' "$OUT" | jq -c 'select(type == "object" and (.rigs | type) == "array")' 2>/dev/null)
[ -n "$MAP" ] || fail "\`gc rig list --json\` printed JSON with no '.rigs' array, which is a change in gc's output contract, not a city problem."
printf '%s\n' "$MAP"
