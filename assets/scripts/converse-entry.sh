#!/usr/bin/env bash
# converse-entry.sh — a converse sitting's way in. It claims through Gas City's
# hook, reads the conversation's record, and prints which entry this is, the
# values every later call sets, and the skill to load next:
#
#   fresh        a conversation this sitting has just taken up
#                (converse-recheck-premise)
#   interrupted  a restart mid-sitting: the hold stands (converse-continue),
#                nothing was held yet (converse-recheck-premise), or a stay
#                stopped short of leaving the conversation waiting for its
#                return, or the sitting filed a stay's gate and has not stayed
#                yet (converse-stay)
#   waiting      the sitting stays for work that is still out, read right after
#                its stay lands or on a visit before that work is back
#                (converse-stay)
#   returned     the work the sitting stayed for is back: the stay's gate has
#                closed, or the work it waited on has; or a gate the sitting
#                filed closed before it stayed (converse-stay)
#   none         this session holds no conversation (drain)
#   stop         Gas City refused the claim to stop this session, as when a
#                drain is under way or the session has closed (drain, and
#                go on with the conversation when the ack is refused over it)
#
# A state that does not read is no answer. The script then prints
# `ENTRY unreadable` and exits 1, so the sitting neither drains nor closes on
# it. The hook's own claim is the only write it makes.
#
# What it reads:
# - `gc hook --claim --json`: `work` and the bead it claimed, or `drain` with
#   exit 1. Its reason tells a restart (`existing_assignment`) from a new
#   claim. It gives the same new-claim answer for a conversation a sitting
#   first takes up and for one whose work has returned, so the record tells
#   those two apart. A drain's reason says why. `no_work` is the one answer
#   about this session's work: no ready work is assigned to it. The hook serves
#   no bead that waits on open work, an in-progress one included, so on
#   `no_work` the script lists the open and in-progress conversations under
#   this session's alias. `claims_errored` is ready work whose claim did not
#   land, which reads as unreadable, so the sitting claims again. Every other
#   reason, such as `drain_pending` or `stale_session`, is Gas City stopping
#   this session, and the hook hands it no work, whatever the conversation's
#   state. The script answers `stop` and prints what the hook wrote to stderr,
#   which can name the acknowledgement to run. Gas City refuses that
#   acknowledgement while the session holds a claim it started and has not
#   finished, as a conversation in progress under it is, and tells the session
#   to continue the claim, so the answer says the sitting then goes on.
# - the conversation's row: its shape (conversation.sh), its subject, the gates
#   it replies to, the beads it waits on through its own `blocks` edges, its
#   notes, and the last hand-back recorded on it.
# - `gctk bead holds`, the one rule for what holds a bead: whether any of those
#   beads is still open, and which of them is a stay's gate.
# - the newest of the conversation's `holding:` and `staying:` lines, which the
#   hold and the stay write as their records (the converse-hold skill,
#   converse-signoff.sh --stay). A `holding:` line newest means the operator
#   owes the hold an answer. A stay writes two `staying:` lines, and nothing
#   but a stay, and the gate a sitting files before it stays, gives a
#   conversation a `blocks` edge. Its first line,
#   `staying: <what was agreed>`, comes before every other write it makes, and
#   says its sign-off has not finished. Its second, `staying: <what was agreed>
#   (waits on <ids>)`, comes once everything but the wait has landed and names
#   what the conversation waits on. A stay in a rig's store names its gate, of
#   the type conversation.sh's $STAY_GATE_TYPE, whose await id is the work it
#   comes back for. A stay in the city's own store, and one made before stays
#   waited on a gate, names the work itself. So the entry reads a stay as
#   waiting or returned only when the record agrees with that second line: the
#   conversation waits through a `blocks` edge on each bead it names, or the
#   bead has closed. Until then, the stay stopped short. An edge alone proves
#   nothing, because a conversation keeps its edges onto what a stay that
#   returned waited on.
# - the beads the conversation waits on, with each one's type, status, await
#   id and close reason (`gc bd dep list <conversation> --type blocks`), which
#   tell a stay's gate from work and give the gate's work. It is read for a
#   stay whose line names something, and for a claimed conversation that has
#   neither line and waits on a stay's gate: one the sitting filed and has not
#   stayed on yet while it is open, and one whose work is back once it has
#   closed after the last hand-back with no stay naming it.
# - for each bead the newest `staying:` line names that the conversation has no
#   edge onto, its status.
#
# Output: a first line `ENTRY <entry>: <what it means>`, then `NEXT=<skill>`
# (`NEXT=drain` for none and stop), then one KEY=value line each for CONV,
# CONVERSATION, SUBJECT and GATES, and for a stay WORK, the work the stay comes
# back for (a gate's await id, or the work its newest line names), and AGREED.
# An interrupted entry whose hold stands ends with the last hand-back recorded
# on the conversation. A stop, and an unreadable claim, end with what the hook
# wrote to stderr.
#
# Environment: GC_ALIAS, this session's alias, which the conversation it holds
# is assigned to; GCTK_BIN or GC_CITY_PATH, to find gctk.
# Exit: 0 an entry, 1 unreadable, 2 usage.
set -u

PROG=converse-entry
HERE="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
  "") ;;
  -h|--help) sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# hook_said — what the claim wrote to stderr, as the hook wrote it, once the
# claim has run and wrote anything.
hook_said() {
  [ -n "${HOOK_ERR:-}" ] && [ -s "$HOOK_ERR" ] || return 0
  echo "The hook said:"
  cat "$HOOK_ERR"
}

unreadable() {
  echo "ENTRY unreadable: $*"
  echo "NEXT=none: do not drain and do not close anything. Run this again, and if it stays unreadable, say so in the thread, mail the witness HELP:, and wait"
  hook_said
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

# pending_of <id> — the open beads the conversation waits on, as the one-line
# JSON array of gctk bead holds' waits, each with its id, issue type and await
# type. Fails when holds does not answer in its own shape. ids_of prints the
# ids of such an array, space-separated.
pending_of() {
  local out
  out=$("$GCTK" bead holds "$1" 2>/dev/null) || return 1
  printf '%s\n' "$out" | scrub | jq -ec --arg id "$1" '
    if type == "object" and ((.id // "") | tostring) == $id and .error == null and (.pending | type) == "array"
    then [ .pending[] | objects ] else error("holds did not answer") end' 2>/dev/null
}
ids_of() { jq -r '[ .[] | (.id // "") | tostring ] | join(" ")'; }

# waits_of <id> — the beads the conversation waits on through its own blocks
# edges, each as `gc bd dep list` prints its row, with its type, status, await
# id and close reason, as one line of JSON. Fails when they do not list.
waits_of() {
  local json
  json=$(gc bd dep list "$1" --type blocks --json 2>/dev/null) || return 1
  printf '%s\n' "$json" | grep -av '^gc bd:' | scrub \
    | jq -ec 'if type == "array" then [ .[] | objects ] else error("not a list") end' 2>/dev/null
}

# The values every later call sets, from a conversation row on stdin.
values() {
  jq -r --arg conv "$HERE" '
    "CONV=" + $conv,
    "CONVERSATION=" + (.id | tostring),
    "SUBJECT=" + ([ .dependencies[]? | select((.type // "") == "tracks") | (.depends_on_id // "") ] | join(" ")),
    "GATES=" + ([ .dependencies[]? | select((.type // "") == "replies-to") | (.depends_on_id // "") ] | join(" ") | if . == "" then "none" else . end)'
}

# What a conversation row says of the newest `holding:` or `staying:` line in
# its notes: the line, its first word, the beads a `staying:` line names after
# "(waits on", none for the line a stay writes first, what the operator agreed,
# the beads the conversation waits on through its own `blocks` edges, and, with
# $deps those beads' rows as waits_of reads them, the work each bead the line
# names stands for: a stay's gate's await id, or the bead itself. It is read
# with conversation.sh's $STAY_GATE_JQ before it.
MARK_JQ='def newest_mark: [ (.notes // "") | split("\n")[] | select(startswith("holding:") or startswith("staying:")) ] | last // "";
  def mark_word: newest_mark | if . == "" then "" else split(":")[0] end;
  def stay_work: newest_mark | if startswith("staying:")
    then ([ capture(" \\(waits on (?<w>[^()]*)\\)$") | .w | split(", ")[] | select(. != "") ]) else [] end;
  def agreed: newest_mark | ltrimstr("staying:") | ltrimstr(" ") | sub(" \\(waits on [^()]*\\)$"; "");
  def edged: [ .dependencies[]? | select((.type // "") == "blocks") | (.depends_on_id // "") | tostring ];
  def unedged: edged as $e | [ stay_work[] | select(. as $w | $e | any(.[]; . == $w) | not) ];
  def stay_for($deps): [ stay_work[] as $w
    | ([ $deps[] | select(((.id // "") | tostring) == $w and stay_gate) | (.await_id // "") | tostring | select(. != "") ] | first) // $w ];'
MARK_JQ="$STAY_GATE_JQ$MARK_JQ"

# The work a stay's newest line stands for, and what the operator agreed, from
# the same row, with <deps> the beads the conversation waits on.
stay_values() {
  jq -r --argjson deps "$1" "$MARK_JQ"'"WORK=" + (stay_for($deps) | join(" ")), "AGREED=" + agreed'
}

# The newest `holding:` or `staying:` line's first word, from the same row.
mark_of() {
  jq -r "$MARK_JQ"'mark_word'
}

# still_out <ids> — those of the beads that have not closed, space-separated.
# Fails when one does not read as itself.
still_out() {
  local w json st out=""
  for w in $1; do
    json=$(gc bd list --id "$w" --all --json 2>/dev/null) || return 1
    st=$(printf '%s\n' "$json" | grep -av '^gc bd:' | scrub | jq -er --arg id "$w" '
      if type == "array" and length == 1 and ((.[0].id // "") | tostring) == $id
      then (.[0].status // "") | tostring | ascii_downcase else error("unread") end' 2>/dev/null) || return 1
    [ -n "$st" ] || return 1
    [ "$st" = closed ] || out="${out:+$out }$w"
  done
  printf '%s' "$out"
}

# hold_stands <conversation> <row> — the entry of a restart while the sitting's
# hold stands, with the last hand-back recorded on the conversation.
hold_stands() {
  echo "ENTRY interrupted: a restart came while this sitting held conversation $1, and its hold stands."
  echo "NEXT=converse-continue"
  printf '%s' "$2" | values
  printf '%s' "$2" | jq -r '(.metadata // {}) as $m
    | if (($m["gc.handback"] // "") | tostring) == "" then "No hand-back is recorded on the conversation."
      else "The last hand-back recorded on the conversation (" + (($m["gc.handback_at"] // "") | tostring) + "):", ($m["gc.handback"] | tostring) end'
  exit 0
}

# stay_entry <conversation> <row> <pending> — the entry of a conversation whose
# newest mark is a `staying:` line, read against the record, then its values.
# <pending> is the open beads it waits on through its edges, as holds reads
# them. The line a stay writes first names nothing, so its sign-off stopped
# before it finished. A gate the newer line names is the stay's, which waits
# while it is open and is back once it has closed, and the work it is for is
# its await id. A bead the line names with no edge onto it holds nothing: when
# it is still out, the stay stopped before it made the conversation wait on it,
# and when it has closed, it needs no edge.
stay_entry() {
  local c=$1 row=$2 pending=$3 work deps="[]" gate="" why="" unedged out
  work=$(printf '%s' "$row" | jq -r "$MARK_JQ"'stay_work | join(" ")')
  if [ -n "$work" ]; then
    deps=$(waits_of "$c") || unreadable "the beads conversation $c waits on did not read, to tell a stay's gate its staying: line names from work"
    # The stay's gate among what the line names: its id and its work, then why
    # it closed.
    gate=$(printf '%s' "$row" | jq -r --argjson deps "$deps" "$MARK_JQ"'
      [ stay_work[] as $w | $deps[] | select(((.id // "") | tostring) == $w and stay_gate) ] | first // empty
      | "\(.id // "") \(.await_id // "")\t\(.close_reason // "")"')
    why="${gate#*$'\t'}"; gate="${gate%%$'\t'*}"
  fi
  unedged=$(printf '%s' "$row" | jq -r "$MARK_JQ"'unedged | join(" ")')
  out=""
  if [ -n "$unedged" ]; then
    out=$(still_out "$unedged") || unreadable "conversation $c's stay names $unedged, which it has no edge onto, and one of them could not be read to tell whether it is still out"
  fi
  if [ -z "$work" ]; then
    echo "ENTRY interrupted: a stay on conversation $c stopped before its sign-off finished, so the conversation does not wait on its work yet. Run the stay's call again."
  elif [ -n "$out" ]; then
    echo "ENTRY interrupted: a stay on conversation $c stopped before it made the conversation wait on $out, which is still out. Run the stay's call again."
  elif [ -z "$pending" ] && [ -n "$gate" ]; then
    echo "ENTRY returned: the gate ${gate%% *} this sitting stayed on has closed${why:+ ($why)}, so ${gate#* } is back with conversation $c."
  elif [ -z "$pending" ]; then
    echo "ENTRY returned: the work this sitting stayed for has closed, and conversation $c is back with it."
  elif [ "$(printf '%s' "$row" | jq -r '(.status // "") | ascii_downcase')" = in_progress ]; then
    echo "ENTRY interrupted: conversation $c waits on work that is still open ($pending) but is still claimed, so a stay stopped short of leaving it to wait. Run the stay's call again."
  elif [ -n "$gate" ]; then
    echo "ENTRY waiting: this sitting stays for ${gate#* }, on its gate ${gate%% *}, which is still open."
  else
    echo "ENTRY waiting: this sitting stays for work that is still open ($pending)."
  fi
  echo "NEXT=converse-stay"
  printf '%s' "$row" | values
  printf '%s' "$row" | stay_values "$deps"
  exit 0
}

# gate_entry <entry and what it means> <row> <gate rows> — the entry of a
# claimed conversation with neither a `holding:` nor a `staying:` line that
# waits on a stay's gate, read from the gate's rows: its values, with the work
# each gate is for and nothing agreed, since no stay has recorded it.
gate_entry() {
  echo "ENTRY $1"
  echo "NEXT=converse-stay"
  printf '%s' "$2" | values
  printf '%s' "$3" | jq -r '"WORK=" + ([ .[] | (.await_id // "") | tostring | select(. != "") ] | unique | join(" "))'
  echo "AGREED="
  exit 0
}

# promised <conversation> <row> <pending> — the entry of a claimed conversation
# with neither line that waits on an open stay's gate: the sitting filed it for
# work it sent, and has not run the stay's call. Returns 1, printing nothing,
# for any other conversation, which <pending>, as pending_of prints it, tells.
promised() {
  local c=$1 row=$2 deps gates
  [ "$(printf '%s' "$row" | jq -r '(.status // "") | ascii_downcase')" = in_progress ] || return 1
  printf '%s' "$3" | jq -e "$STAY_GATE_JQ"'any(.[]; open_stay_gate)' >/dev/null 2>&1 || return 1
  deps=$(waits_of "$c") || unreadable "the beads conversation $c waits on did not read, to tell the work the stay's gate it waits on is for"
  gates=$(printf '%s' "$deps" | jq -c "$STAY_GATE_JQ"'[ .[] | select(open_stay_gate) ]')
  gate_entry "interrupted: conversation $c waits on the gate $(printf '%s' "$gates" | ids_of) the sitting filed for the work it sent, and no staying: line records a stay yet, so the stay's call has not run. Run it." "$row" "$gates"
}

# came_back <conversation> <row> — the entry of a restart on a conversation with
# neither line whose stay's gate has closed since the sitting filed it, after
# the last hand-back recorded on it and with no stay naming it: the work the
# sitting sent is back before it stayed, and its return is owed. Returns 1,
# printing nothing, when the conversation waits on no such gate.
came_back() {
  local c=$1 row=$2 deps gates why
  printf '%s' "$row" | jq -e 'any(.dependencies[]?; (.type // "") == "blocks")' >/dev/null 2>&1 || return 1
  deps=$(waits_of "$c") || unreadable "the beads conversation $c waits on did not read, to tell whether a gate the sitting filed has brought its work back"
  gates=$(printf '%s' "$deps" | jq -c --argjson conv "$row" "$STAY_GATE_JQ"'[ .[] | select(back_unstayed($conv)) ] | sort_by((.closed_at // "") | tostring) | if length > 0 then [ last ] else [] end')
  [ "$gates" != "[]" ] || return 1
  why=$(printf '%s' "$gates" | jq -r '.[0].close_reason // ""')
  gate_entry "returned: the gate $(printf '%s' "$gates" | ids_of) the sitting filed for $(printf '%s' "$gates" | jq -r '.[0].await_id // ""') closed before it stayed${why:+ ($why)}, so that work is back with conversation $c, and its return is owed." "$row" "$gates"
}

# The claim's stderr is kept for the answers that pass it on. Without a file
# to keep it in, it goes to this script's own stderr, which the sitting sees.
HOOK_ERR=$(mktemp "${TMPDIR:-/tmp}/converse-entry.XXXXXX" 2>/dev/null) || HOOK_ERR=""
trap '[ -z "$HOOK_ERR" ] || rm -f "$HOOK_ERR"' EXIT
HOOK=$(gc hook --claim --json 2>"${HOOK_ERR:-/dev/stderr}")
HOOK_RC=$?
ACTION=$(printf '%s\n' "$HOOK" | scrub | jq -er 'if type == "object" and ((.action // "") | tostring) != "" then .action | tostring else error("no action") end' 2>/dev/null) \
  || unreadable "gc hook --claim --json answered no action (exit $HOOK_RC)"
REASON=$(printf '%s\n' "$HOOK" | scrub | jq -r '.reason // "" | tostring')

case "$ACTION:$REASON" in
  drain:)
    unreadable "gc hook --claim --json answered drain with no reason, which does not say whether Gas City is stopping this session" ;;
  drain:claims_errored)
    unreadable "the hook found ready work for this session, and its claim did not land (claims_errored); run this again, which claims it once the store takes the write" ;;
  drain:no_work)
    # Nothing ready is assigned to this session. A sitting that stays gets
    # this answer while its work is out, because its conversation waits on
    # that work: open once the stay is written, still in progress when the
    # stay stopped before it left the conversation to wait. So does a sitting
    # that held after a stay whose work is still out.
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
    PENDING_JSON=$(pending_of "$C") || unreadable "gctk bead holds did not answer for conversation $C"
    PENDING=$(printf '%s' "$PENDING_JSON" | ids_of)
    [ -n "$PENDING" ] \
      || unreadable "conversation $C is assigned to this session with no work holding it, yet the claim found nothing; run this again, which claims it once it reads ready"
    case "$(printf '%s' "$ROW" | mark_of)" in
      holding) hold_stands "$C" "$ROW" ;;
      staying) stay_entry "$C" "$ROW" "$PENDING" ;;
      *) promised "$C" "$ROW" "$PENDING_JSON" \
           || unreadable "conversation $C waits on open work ($PENDING), and no staying: line records the stay that made it wait" ;;
    esac ;;
  drain:*)
    # Gas City is stopping this session, as for a drain under way, a stale or
    # unregistered session or a suspension, and hands it no work, whatever its
    # conversation's state. Nothing is read or written here, so the
    # conversation's record stays as it is. The acknowledgement is refused
    # while the session holds the conversation, which it claimed through this
    # entry and has not finished, and Gas City then tells it to continue.
    echo "ENTRY stop: Gas City is stopping this session ($REASON), and its claim hands it no work. Acknowledge the drain with gc runtime drain-ack, in the form the hook names when it names one, and end, with nothing written to the conversation. When the ack is refused because this session holds its conversation, which it started and has not finished, the sitting goes on with that conversation, and acknowledges the drain once the conversation is closed, back in the operator's queue or left to wait."
    echo "NEXT=drain"
    hook_said
    exit 0 ;;
  work:*) ;;
  *) unreadable "gc hook --claim --json answered action '$ACTION'" ;;
esac

BEAD=$(printf '%s\n' "$HOOK" | scrub | jq -r '.bead_id // "" | tostring')
[ -n "$BEAD" ] || unreadable "the claim named no bead"
ROW=$(row_of "$BEAD") || unreadable "the claim returned $BEAD, which did not read as a conversation"
PENDING=$(pending_of "$BEAD") || unreadable "gctk bead holds did not answer for conversation $BEAD"
PENDING=$(printf '%s' "$PENDING" | ids_of)
MARK=$(printf '%s' "$ROW" | mark_of)

# The hook serves no bead that waits on open work, so a claimed conversation
# that holds still reads as waiting has moved between the two reads.
[ -z "$PENDING" ] \
  || unreadable "the claim served conversation $BEAD, which still waits on open work ($PENDING); run this again"
if [ "$MARK" = staying ]; then
  stay_entry "$BEAD" "$ROW" ""
elif [ "$REASON" = existing_assignment ] && [ "$MARK" = holding ]; then
  hold_stands "$BEAD" "$ROW"
elif [ "$REASON" = existing_assignment ]; then
  came_back "$BEAD" "$ROW"
  echo "ENTRY interrupted: a restart came before this sitting held conversation $BEAD, so it starts from the premise."
  echo "NEXT=converse-recheck-premise"
  printf '%s' "$ROW" | values
else
  echo "ENTRY fresh: this sitting has just taken up conversation $BEAD."
  echo "NEXT=converse-recheck-premise"
  printf '%s' "$ROW" | values
fi
exit 0
