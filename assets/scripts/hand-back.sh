#!/usr/bin/env bash
# hand-back — give back a bead this session claimed, in ONE write that reopens
# it, clears its assignee and removes the claim's session pins.
#
#   hand-back.sh <bead> [<gc bd update flag>...]
#
# Every further argument is a gc bd update flag carried by the same write, such
# as the route the released bead rests on. bd applies a write's field and
# metadata edits in one atomic operation, so the hand-back lands whole or not at
# all. Split into parts, it can stop half-way: a store that takes the clear and
# fails the reopen leaves the bead in_progress with no assignee, which no pool's
# work query serves, and pins removed ahead of a release that then fails leave
# a held bead that no longer names its session in them. A refused write leaves
# the claim as it was, in_progress under this session with its pins and route
# in place.
#
# The write goes ahead only while the bead shows this session's claim, or none:
#   in_progress, assigned to one of this session's identities;
#   open, unassigned or assigned to one of them.
# This session's identities are whichever of $GC_ALIAS, $GC_SESSION_ID,
# $GC_SESSION_NAME and $GC_AGENT are set. A claim `gc hook --claim` takes inside
# a session is recorded under $GC_ALIAS when the session has one, else under
# $GC_SESSION_ID (hookClaimAssigneeIdentity, cmd/gc/cmd_hook.go in gascity).
# The write is guarded with --if-status and --if-assignee on what the bead
# showed, so a claim or a close that lands after that read refuses it whole.
# bd skips its reassign fence for a write guarded on the assignee, which is
# what lets one write clear the assignee of an in_progress bead.
#
# Anything else is not this session's to release: a closed or parked bead, one
# held by someone else, one in_progress with no assignee, or one that cannot be
# read. Nothing is written to it but a note saying what it showed. A write the
# store refuses gets the same note, naming what the bead shows after it.
#
# Callers: mol-polecat-work's hand-back arms (the stop to ask a person about a
# bead with no molecule, the store-only exit, the auto_push=false halt) and
# converse-claim.sh's release of an out-of-group turn.
# exit: 0 handed back · 1 not handed back, noted on the bead · 2 usage
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: hand-back.sh <bead> [<gc bd update flag>...]

Reopens <bead>, clears its assignee and removes gc.session_id and
gc.session_name in one write, guarded on the status and assignee the bead
shows, when it shows this session's claim or none. Further arguments are
gc bd update flags carried by the same write.
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  ""|-*)     usage; exit 2 ;;
esac
BEAD="$1"; shift

# show <bead> -> "<status>|<assignee>", empty fields when the bead does not read.
show() {
  local row
  row=$(gc bd show "$1" --json 2>/dev/null | scrub) || true
  printf '%s' "$row" \
    | jq -r 'if type == "array" and length > 0 then "\(.[0].status // "")|\(.[0].assignee // "")" else "|" end' 2>/dev/null \
    || printf '|'
}

# mine <identity> -> 0 when it is one of this session's identities.
mine() {
  local id
  [ -n "$1" ] || return 1
  for id in "${GC_ALIAS:-}" "${GC_SESSION_ID:-}" "${GC_SESSION_NAME:-}" "${GC_AGENT:-}"; do
    [ -n "$id" ] && [ "$id" = "$1" ] && return 0
  done
  return 1
}

# refuse <note>: the bead keeps whatever it shows; the note says why.
refuse() {
  echo "hand-back: $1" >&2
  gc bd update "$BEAD" --append-notes "Hand-back refused: $1" >/dev/null 2>&1 \
    || echo "hand-back: the note did not land on $BEAD either" >&2
  exit 1
}

STATE=$(show "$BEAD")
STATUS="${STATE%%|*}"
HOLDER="${STATE#*|}"

OURS=0
case "$STATUS" in
  in_progress) mine "$HOLDER" && OURS=1 ;;
  open)        { [ -z "$HOLDER" ] || mine "$HOLDER"; } && OURS=1 ;;
esac
if [ "$OURS" != 1 ]; then
  [ -n "$STATUS" ] || refuse "$BEAD could not be read, so nothing was released."
  refuse "$BEAD shows status $STATUS and assignee ${HOLDER:-none}, which is not a claim this session can hand back, so nothing was released."
fi

RC=0
gc bd update "$BEAD" --if-status="$STATUS" --if-assignee="$HOLDER" --status=open --assignee="" \
  --unset-metadata gc.session_id --unset-metadata gc.session_name ${@+"$@"} >/dev/null || RC=$?
if [ "$RC" -eq 0 ]; then
  echo "hand-back: $BEAD is open and unassigned, its claim released"
  exit 0
fi
case "$RC" in
  13) WHY="the bead changed after it was read" ;;
  *)  WHY="the store refused it" ;;
esac
AFTER=$(show "$BEAD")
NOW_STATUS="${AFTER%%|*}"
NOW_HOLDER="${AFTER#*|}"
if [ -n "$NOW_STATUS" ]; then
  NOW="It shows status $NOW_STATUS and assignee ${NOW_HOLDER:-none}."
else
  NOW="It could not be read after the write."
fi
refuse "the write that reopens $BEAD and releases this session's claim exited $RC ($WHY). $NOW"
