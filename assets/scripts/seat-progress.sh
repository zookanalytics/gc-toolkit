#!/usr/bin/env bash
# seat-progress — file a finding on a live pool seat whose pane prints but which
# has written nothing to a store for three hours. It kills nothing.
#
# Usage: seat-progress.sh --bead <bead-id>
#   <bead> is judged only when it is the claim a live pool seat holds now: in
#   progress, its gc.session_id the seat's session, and assigned to the seat's
#   own identity. The seat's writes are the rows whose actor is that identity in
#   the events and wisp_events tables of the rig's store, the one a plain
#   `gc bd` reads, and the city's, $GC_CITY_PATH/.beads, counted from no earlier
#   than the seat's last wake. The finding is keyed no-progress.<session> and is
#   about the claim.
# Output: one line saying what it judged, after patrol-finding.sh's own line
#   when it files.
# Exit: 0 judged: the finding filed or recorded, the seat spared, or <bead> no
#       claim of a live pool seat · 1 a read or the filing failed, and nothing
#       was judged · 2 usage
set -uo pipefail

PROG="seat-progress"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
FINDING="${GC_PATROL_FINDING_TOOL:-$HERE/patrol-finding.sh}"

# Gas City's work ladder reads a pane quiet for 90 seconds as a quiet seat
# (idleClaimNudgeGrace in cmd/gc/idle_nudge.go), so each seat judged here is busy.
PRINTING_SECS=90
BOUND_SECS=10800

say() { printf '%s: %s\n' "$PROG" "$*"; }
usage() { echo "usage: seat-progress.sh --bead <bead-id>" >&2; }

BEAD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead) [ $# -ge 2 ] || { usage; exit 2; }; BEAD="$2"; shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done
[ -n "$BEAD" ] || { usage; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is required; nothing judged" 1

# RFC 3339 in UTC, as Gas City and bd render a time, to epoch seconds, or
# nothing when it does not parse.
EPOCH_JQ='def epoch: (try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | floor) catch empty);'
epoch_of() { jq -rn --arg t "$1" "$EPOCH_JQ"' $t | epoch' 2>/dev/null; }
iso_of() { jq -rn --argjson s "$1" '$s | todate' 2>/dev/null; }
first_row() { jq -c 'if type == "array" then (.[0] // empty) else empty end' 2>/dev/null; }

NOW=$(date +%s)

# ── Is <bead> a claim a session holds? ───────────────────────────────────────
CLAIM=$(bd_json show "$BEAD" | first_row) || CLAIM=""
[ -n "$CLAIM" ] || die "could not read $BEAD; nothing judged" 1
STATUS=$(printf '%s' "$CLAIM" | jq -r '.status // ""')
SESSION=$(printf '%s' "$CLAIM" | jq -r '.metadata["gc.session_id"] // ""')
ACTOR=$(printf '%s' "$CLAIM" | jq -r '.assignee // ""')
if [ "$STATUS" != "in_progress" ] || [ -z "$SESSION" ]; then
  say "$BEAD is no claim a session holds (status ${STATUS:-unknown}, session ${SESSION:-none}); nothing judged"
  exit 0
fi

# ── The seat, read now: whether its pane prints is a fact about this moment ──
LIST=$(gc session list --json 2>/dev/null | scrub) || LIST=""
printf '%s' "$LIST" | jq -e 'type == "object" and (.sessions | type) == "array"' >/dev/null 2>&1 \
  || die "gc session list printed no readable session list; nothing judged" 1
SEAT=$(printf '%s' "$LIST" | jq -c --arg s "$SESSION" '[ .sessions[] | select(.id == $s) ] | first // empty')
if [ -z "$SEAT" ]; then
  say "no open session is $SESSION, the session $BEAD names; nothing judged"
  exit 0
fi
ALIAS=$(printf '%s' "$SEAT" | jq -r '.alias // ""')
AGENT=$(printf '%s' "$SEAT" | jq -r '.agent_name // ""')
# The seat's own identity is the one its writes carry, so a claim assigned to
# any other name would be judged on someone else's writes.
if [ -z "$ACTOR" ] || { [ "$ACTOR" != "$SESSION" ] && [ "$ACTOR" != "$ALIAS" ]; }; then
  say "$BEAD is assigned to ${ACTOR:-nobody}, not to the identity of its session $SESSION; nothing judged"
  exit 0
fi

# ── A pool seat whose pane prints, and when it last woke ─────────────────────
[ -n "${GC_CITY_PATH:-}" ] || die "GC_CITY_PATH is unset, so the city store cannot be read; nothing judged" 1
CITY_DB="$GC_CITY_PATH/.beads"
SESSION_BEAD=$(bd_json --db "$CITY_DB" show "$SESSION" | first_row) || SESSION_BEAD=""
[ -n "$SESSION_BEAD" ] || die "could not read the session bead $SESSION in the city store; nothing judged" 1
if [ "$(printf '%s' "$SESSION_BEAD" | jq -r '.metadata.pool_managed // ""')" != "true" ]; then
  say "$SESSION is not a pool seat; nothing judged"
  exit 0
fi
ACTIVE_AT=$(printf '%s' "$SEAT" | jq -r '.last_active // ""')
ACTIVE=$(epoch_of "$ACTIVE_AT") || ACTIVE=""
if [ -z "$ACTIVE" ] || [ $(( NOW - ACTIVE )) -gt "$PRINTING_SECS" ]; then
  say "spared $SESSION: its pane has printed nothing since ${ACTIVE_AT:-it last ran}, and the controller paces a quiet pool seat"
  exit 0
fi
WOKE_AT=$(printf '%s' "$SESSION_BEAD" | jq -r '.metadata.last_woke_at // ""')
[ -n "$WOKE_AT" ] || WOKE_AT=$(printf '%s' "$SEAT" | jq -r '.created_at // ""')
WOKE=$(epoch_of "$WOKE_AT") || WOKE=""
[ -n "$WOKE" ] || die "could not read when $SESSION woke; nothing judged" 1

# ── Its newest write, in this rig's store and the city's ─────────────────────
# The identity goes into the query text, so only the characters an identity
# carries may reach it, and no quote can end the literal.
case "$ACTOR" in
  *[!A-Za-z0-9._/-]*) die "the claim's assignee '$ACTOR' carries a character the store query cannot hold; nothing judged" 1 ;;
esac
QUERY="SELECT MAX(t) AS newest FROM (SELECT MAX(created_at) AS t FROM events WHERE actor = '$ACTOR' UNION ALL SELECT MAX(created_at) AS t FROM wisp_events WHERE actor = '$ACTOR') AS w"
# newest_in [--db <store>] prints the newest write's epoch seconds, or `none`
# when the store holds no write by the identity, and fails when the read does.
newest_in() {
  local out
  out=$(bd_json "$@" sql "$QUERY") || return 1
  printf '%s' "$out" | jq -er "$EPOCH_JQ"'
    if type == "array" and length == 1 then
      (.[0].newest | if . == null then "none" else (epoch // error("unparsed")) end)
    else error("not a result") end' 2>/dev/null
}
RIG_NEWEST=$(newest_in) || die "could not read the writes of $ACTOR in this rig's store; nothing judged" 1
CITY_NEWEST=$(newest_in --db "$CITY_DB") || die "could not read the writes of $ACTOR in the city store; nothing judged" 1
NEWEST=""
for t in "$RIG_NEWEST" "$CITY_NEWEST"; do
  [ "$t" != "none" ] || continue
  if [ -z "$NEWEST" ] || [ "$t" -gt "$NEWEST" ]; then NEWEST="$t"; fi
done

if [ -n "$NEWEST" ] && [ "$NEWEST" -ge "$WOKE" ]; then
  SINCE=$NEWEST
  SINCE_TEXT="its newest write as $ACTOR to this rig's store or the city's was at $(iso_of "$NEWEST")"
else
  SINCE=$WOKE
  SINCE_TEXT="it has written nothing as $ACTOR to this rig's store or the city's since it woke at $(iso_of "$WOKE")"
fi
AGE=$(( NOW - SINCE ))
if [ "$AGE" -lt "$BOUND_SECS" ]; then
  say "spared $SESSION: $SINCE_TEXT, under three hours ago"
  exit 0
fi

# ── File it ──────────────────────────────────────────────────────────────────
HOURS=$(( AGE / 3600 ))
LABEL="${AGENT:-$SESSION}"
TITLE="$LABEL prints but has written nothing for $HOURS hours, holding $BEAD"
MESSAGE="The pool seat $SESSION ($LABEL) holds $BEAD, and its pane printed in the $PRINTING_SECS seconds before the witness read it, but $SINCE_TEXT. Gas City's work ladder takes no step on a pool seat whose pane keeps printing.

\`gc session peek $SESSION\` shows what it prints. The witness kills nothing, so restarting the seat is a person's decision. \`gc session kill $SESSION\` ends its runtime without discarding its work, and a pool seat holding started work restarts in place with its claims."
FILE_RC=0
FILE_OUT=$("$FINDING" --scope witness-findings --key "no-progress.$SESSION" --about "$BEAD" --distinct \
  --title "$TITLE" --message "$MESSAGE" 2>&1) || FILE_RC=$?
[ -z "$FILE_OUT" ] || printf '%s\n' "$FILE_OUT"
[ "$FILE_RC" -eq 0 ] || die "patrol-finding.sh filed nothing for $SESSION (exit $FILE_RC); the next call judges it again" 1
say "reported $SESSION: no write for $HOURS hours while its pane prints, holding $BEAD"
