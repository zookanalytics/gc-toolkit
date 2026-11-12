#!/usr/bin/env bash
# converse-entry.sh — a converse sitting's way in. It claims through Gas City's
# hook, reads the conversation's record, and prints which entry this is, the
# values every later call sets, and the skill to load next:
#
#   fresh        a conversation this sitting has just taken up
#                (converse-recheck-premise)
#   interrupted  a restart mid-sitting: the hold stands (converse-continue),
#                nothing was held yet (converse-recheck-premise), or a stay
#                stopped short of leaving the conversation to wait
#                (converse-stay)
#   waiting      the sitting stays for work that is still out, and an attach or
#                a restart woke it early (converse-stay)
#   returned     the work the sitting stayed for has closed (converse-stay)
#   none         this session holds no conversation (drain)
#
# A state that does not read is no answer. The script then prints
# `ENTRY unreadable` and exits 1, so the sitting neither drains nor closes on
# it. The hook's own claim is the only write it makes.
#
# What it reads:
# - `gc hook --claim --json`: `work` and the bead it claimed, or `drain` when
#   no ready work is assigned to this session, with exit 1. Its reason tells a
#   restart (`existing_assignment`) from a new claim. It gives the same
#   new-claim answer for a conversation a sitting first takes up and for one
#   whose work has returned, so the record tells those two apart. It serves no
#   bead that waits on open work, an in-progress one included, so on `drain`
#   the script lists the open and in-progress conversations under this
#   session's alias.
# - the conversation's row: its shape (conversation.sh), its subject, the gates
#   it replies to, the work it waits on through its own `blocks` edges, its
#   notes, and the last hand-back recorded on it.
# - `gctk bead holds`, the one rule for what holds a bead: whether any of that
#   work is still open.
# - the newest of the conversation's `holding:` and `staying:` lines, which the
#   hold and the stay write as their records (the converse-hold skill,
#   converse-signoff.sh --stay). A `staying:` line newest means the sitting
#   stayed and has not held since, so a claimed conversation whose work has all
#   closed is a return. A `holding:` line newest means the operator owes the
#   hold an answer.
#
# Output: a first line `ENTRY <entry>: <what it means>`, then `NEXT=<skill>`
# (`NEXT=drain` for none), then one KEY=value line each for CONV, CONVERSATION,
# SUBJECT and GATES, and for a stay WORK and AGREED. An interrupted entry whose
# hold stands ends with the last hand-back recorded on the conversation.
#
# Environment: GC_ALIAS, this session's alias, which the conversation it holds
# is assigned to; GCTK_BIN or GC_CITY_PATH, to find gctk.
# Exit: 0 an entry, 1 unreadable, 2 usage.
set -u

PROG=converse-entry
HERE="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
  "") ;;
  -h|--help) sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "$PROG: takes no arguments; it reads this session's claim" >&2; exit 2 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "$PROG: gc is required" >&2; exit 2; }
# shellcheck source=conversation.sh
. "$HERE/conversation.sh" || { echo "$PROG: cannot read $HERE/conversation.sh" >&2; exit 2; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin

unreadable() {
  echo "ENTRY unreadable: $*"
  echo "NEXT=none: do not drain and do not close anything. Run this again, and if it stays unreadable, say so in the thread, mail the witness HELP:, and wait"
  exit 1
}

# row_of <id> — the bead's `gc bd list` row, compact, once it reads as that one
# bead in a conversation's shape. Notes keep their line breaks: only the bytes
# a JSON string may not carry raw are scrubbed, and bd escapes a line break.
row_of() {
  local json
  json=$(gc bd list --id "$1" --all --json 2>/dev/null) || return 1
  printf '%s\n' "$json" | grep -av '^gc bd:' | scrub | jq -ec --arg id "$1" "$CONVERSATION_JQ"'
    if type == "array" and length == 1 and ((.[0].id // "") | tostring) == $id and (.[0] | conversation)
    then .[0] else error("not one conversation") end' 2>/dev/null
}

# pending_of <id> — the open beads the conversation waits on, space-separated,
# from gctk bead holds. Fails when holds does not answer in its own shape.
pending_of() {
  local out
  out=$("$GCTK" bead holds "$1" 2>/dev/null) || return 1
  printf '%s\n' "$out" | scrub | jq -er --arg id "$1" '
    if type == "object" and ((.id // "") | tostring) == $id and .error == null and (.pending | type) == "array"
    then [ .pending[] | (.id // "") | tostring ] | join(" ") else error("holds did not answer") end' 2>/dev/null
}

# The values every later call sets, from a conversation row on stdin.
values() {
  jq -r --arg conv "$HERE" '
    "CONV=" + $conv,
    "CONVERSATION=" + (.id | tostring),
    "SUBJECT=" + ([ .dependencies[]? | select((.type // "") == "tracks") | (.depends_on_id // "") ] | join(" ")),
    "GATES=" + ([ .dependencies[]? | select((.type // "") == "replies-to") | (.depends_on_id // "") ] | join(" ") | if . == "" then "none" else . end)'
}

# The work a stay waits on, and what the operator agreed, from the same row.
stay_values() {
  jq -r '
    "WORK=" + ([ .dependencies[]? | select((.type // "") == "blocks") | (.depends_on_id // "") ] | join(" ")),
    "AGREED=" + ([ (.notes // "") | split("\n")[] | select(startswith("staying:")) ] | last // "" | ltrimstr("staying:") | ltrimstr(" "))'
}

# The newest `holding:` or `staying:` line's first word, from the same row.
mark_of() {
  jq -r '[ (.notes // "") | split("\n")[] | select(startswith("holding:") or startswith("staying:")) ] | last // "" | if . == "" then "" else split(":")[0] end'
}

HOOK=$(gc hook --claim --json 2>/dev/null)
HOOK_RC=$?
ACTION=$(printf '%s\n' "$HOOK" | scrub | jq -er 'if type == "object" and ((.action // "") | tostring) != "" then .action | tostring else error("no action") end' 2>/dev/null) \
  || unreadable "gc hook --claim --json answered no action (exit $HOOK_RC)"

case "$ACTION" in
  drain)
    # Nothing ready is assigned to this session. A sitting that stays gets
    # this answer while its work is out, because its conversation waits on
    # that work: open once the stay is written, still in progress when the
    # stay stopped before it left the conversation to wait.
    [ -n "${GC_ALIAS:-}" ] || unreadable "this session has no GC_ALIAS, so the conversation it may hold cannot be listed"
    LIST=$(gc bd list --assignee "$GC_ALIAS" --status open,in_progress --json 2>/dev/null) \
      || unreadable "the open and in-progress beads assigned to $GC_ALIAS did not list"
    ROWS=$(printf '%s\n' "$LIST" | grep -av '^gc bd:' | scrub | jq -ec "$CONVERSATION_JQ"'
      if type == "array" then [ .[] | select(conversation) ] else error("not a list") end' 2>/dev/null) \
      || unreadable "the open and in-progress beads assigned to $GC_ALIAS did not read as a list"
    # A conversation's alias names its own id (conversation.sh), so at most
    # one conversation is assigned to it.
    ROW=$(printf '%s' "$ROWS" | jq -c '.[0] // empty')
    if [ -z "$ROW" ]; then
      echo "ENTRY none: no conversation is assigned to this session, open or claimed."
      echo "NEXT=drain"
      exit 0
    fi
    C=$(printf '%s' "$ROW" | jq -r '.id')
    PENDING=$(pending_of "$C") || unreadable "gctk bead holds did not answer for conversation $C"
    [ -n "$PENDING" ] \
      || unreadable "conversation $C is assigned to this session with no work holding it, yet the claim found nothing; run this again, which claims it once it reads ready"
    if [ "$(printf '%s' "$ROW" | jq -r '.status // ""')" = in_progress ]; then
      echo "ENTRY interrupted: conversation $C waits on work that is still open ($PENDING) but is still claimed, so a stay stopped short of leaving it to wait. Run the stay's call again."
    else
      echo "ENTRY waiting: this sitting stays for work that is still open ($PENDING), and an attach or a restart woke it before that work closed."
    fi
    echo "NEXT=converse-stay"
    printf '%s' "$ROW" | values
    printf '%s' "$ROW" | stay_values
    exit 0 ;;
  work) ;;
  *) unreadable "gc hook --claim --json answered action '$ACTION'" ;;
esac

BEAD=$(printf '%s\n' "$HOOK" | scrub | jq -r '.bead_id // "" | tostring')
REASON=$(printf '%s\n' "$HOOK" | scrub | jq -r '.reason // "" | tostring')
[ -n "$BEAD" ] || unreadable "the claim named no bead"
ROW=$(row_of "$BEAD") || unreadable "the claim returned $BEAD, which did not read as a conversation"
PENDING=$(pending_of "$BEAD") || unreadable "gctk bead holds did not answer for conversation $BEAD"
MARK=$(printf '%s' "$ROW" | mark_of)

# The hook serves no bead that waits on open work, so a claimed conversation
# that holds still reads as waiting has moved between the two reads.
[ -z "$PENDING" ] \
  || unreadable "the claim served conversation $BEAD, which still waits on open work ($PENDING); run this again"
if [ "$MARK" = staying ]; then
  echo "ENTRY returned: the work this sitting stayed for has closed, and conversation $BEAD is back with it."
  echo "NEXT=converse-stay"
  printf '%s' "$ROW" | values
  printf '%s' "$ROW" | stay_values
elif [ "$REASON" = existing_assignment ] && [ "$MARK" = holding ]; then
  echo "ENTRY interrupted: a restart came while this sitting held conversation $BEAD, and its hold stands."
  echo "NEXT=converse-continue"
  printf '%s' "$ROW" | values
  printf '%s' "$ROW" | jq -r '(.metadata // {}) as $m
    | if (($m["gc.handback"] // "") | tostring) == "" then "No hand-back is recorded on the conversation."
      else "The last hand-back recorded on the conversation (" + (($m["gc.handback_at"] // "") | tostring) + "):", ($m["gc.handback"] | tostring) end'
elif [ "$REASON" = existing_assignment ]; then
  echo "ENTRY interrupted: a restart came before this sitting held conversation $BEAD, so it starts from the premise."
  echo "NEXT=converse-recheck-premise"
  printf '%s' "$ROW" | values
else
  echo "ENTRY fresh: this sitting has just taken up conversation $BEAD."
  echo "NEXT=converse-recheck-premise"
  printf '%s' "$ROW" | values
fi
exit 0
