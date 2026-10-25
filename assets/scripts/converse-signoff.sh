#!/usr/bin/env bash
# converse-signoff.sh — a sitting's sign-off: the durable trace it owes, written
# in one order every time.
#
# A sitting holds one conversation, a task that tracks the subject and replies
# to each human gate it answers. When the operator ruled (--ruled yes), the
# sign-off:
#   1. routes the ruling's rework through converse-rework.sh, with the
#      conversation as the rework's source_ruling_bead (--rework);
#   2. writes the subject's headline (gc-helm.sh takeaway) and reads it back;
#   3. resolves each open gate the conversation replies to with
#      `ruled: <ruling>`, except each one --leave names, and reads each back. bd
#      resolves a closed gate without changing it and reports success either
#      way, so a close reason other than this one means another answer reached
#      the gate first: a filer's withdrawal, an Accept, another sitting, or a
#      person at the command line. The first answer wins, and the sign-off
#      reports it;
#   4. releases a subject that reads `held`;
#   5. closes the conversation;
#   6. updates the subject's PR reminder.
# Cut short (--ruled no), it writes the headline, leaves every gate the
# conversation replies to open and owed, with its reply in place for the next
# sitting, and hands the conversation back to the operator's queue with a write
# guarded on the sitting that holds it, then updates the reminder.
#
# It resolves no gate its conversation does not reply to: a gate the sitting
# never took up stays for whoever owes it. The gates are read from the
# conversation's own row (`gc bd list --id <task>`), whose edges keep a reply
# onto a gate in another store. Every read the sign-off depends on runs before
# its first write and fails closed, because a read that fails is no proof that
# nothing stands.
#
# What waits on the subject is the caller's to state: one --waiting-on per bead
# it ROUTED work into, --no-wait when it settled the subject and nothing is
# waiting, and NEITHER where the subject is parked for a person. The scripts it
# runs (converse-rework.sh, gc-helm.sh, lifecycle.sh, pr-sitting-comment.sh) are
# SEARCHED for on the candidate roots, in the one order pack_script holds.
#
# Usage:
#   converse-signoff.sh --conversation <task> --outcome "<headline, ≤140 chars>" \
#     [--subject <id>] [--ruled yes|no] [--ruling "<one line>"] \
#     [--route <rig>/<agent>|human] [--leave <gate> ...] \
#     [--no-wait | --waiting-on <bead> ...] [--rework | --no-rework]
#   --outcome is the subject's headline, and the close reason the sittings card
#   falls back to. --ruled defaults to `no`. --ruled yes requires --ruling, the
#   answer each gate resolves with, and --route, where a `held` subject is
#   released to. --subject, when given, must be the bead the conversation tracks.
#   --leave (with --ruled yes) names a gate the conversation replies to that the
#   ruling leaves owed: it stays open, and its reply stays as the record that
#   this conversation took it up.
#   --rework | --no-rework (with --ruled yes): whether the ruling changes what an
#     already-published PR's branch must contain. --rework files the rework
#     against the subject anchor, sourced by this conversation, and --no-rework
#     records in the PR reminder that the branch stands. A ruled sign-off on a
#     subject at merge_result=pull_request must give one; given neither, it is
#     refused with nothing written. The filing runs before every other write,
#     and when it does not land nothing else is written.
# Exit: 0 signed off; 1 stopped short — a read failed, the rework did not file,
#   the headline did not land, a gate did not close, or the conversation did not
#   close or hand back — so do NOT post the sign-off; repair what it names and
#   re-run, which repeats every write it made safely; 2 refused before any
#   write: usage, a conversation that is not one, or a ruled sign-off on an open
#   PR that answered neither --rework nor --no-rework.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

CONVERSATION=""
SUBJECT=""
OUTCOME=""
RULED=no
RULING=""
ROUTE=""
REWORK=""
WAIT=()
LEAVE=()

die() { echo "converse-signoff: $1" >&2; exit 2; }
# stopped <why> — refuse the sign-off (exit 1). Whatever ran before it is a write
# a re-run repeats safely.
stopped() {
  echo "converse-signoff: $1" >&2
  echo "NOT SIGNED OFF — do NOT post the sign-off. Repair what is named above, then re-run this sign-off."
  exit 1
}
# show_row <id> — the bead's row from `gc bd show <id> --json`, one line of
# JSON, or nothing (status 1) when it does not read as that bead.
show_row() {
  gc bd show "$1" --json 2>/dev/null | scrub \
    | jq -ce --arg id "$1" 'if type == "array" then (.[0] | select((.id // "") == $id)) else error("unread") end' 2>/dev/null
}

# pack_script <name> — the first candidate root's assets/scripts/<name>: the rig
# root, then the git checkout of the working directory, then the city's
# gc-toolkit rig. Every script this sign-off runs is found through it, so they
# share one search order. Non-zero, printing nothing, when no root carries it.
pack_script() {
  local cand
  for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
    [ -x "$cand/assets/scripts/$1" ] && { printf '%s' "$cand/assets/scripts/$1"; return 0; }
  done
  return 1
}

HERE="$(cd "$(dirname "$0")" && pwd)"
# The one definition of a conversation's shape. Exposes $CONVERSATION_JQ.
# shellcheck source=conversation.sh
. "$HERE/conversation.sh" || die "cannot source conversation.sh from $HERE"
# The one gc.work_outcome stamp a conversation gets before it closes, shared
# with gc-helm.sh dismiss. Exposes work_outcome_noop.
# shellcheck source=work-outcome.sh
. "$HERE/work-outcome.sh" || die "cannot source work-outcome.sh from $HERE"

while [ $# -gt 0 ]; do
  case "$1" in
    --conversation) shift; [ $# -gt 0 ] || die "--conversation needs a value"; CONVERSATION="$1" ;;
    --subject)    shift; [ $# -gt 0 ] || die "--subject needs a value"; SUBJECT="$1" ;;
    --outcome)    shift; [ $# -gt 0 ] || die "--outcome needs a value"; OUTCOME="$1" ;;
    --ruled)      shift; [ $# -gt 0 ] || die "--ruled needs yes|no"; RULED="$1" ;;
    --ruling)     shift; [ $# -gt 0 ] || die "--ruling needs a value"; RULING="$1" ;;
    --route)      shift; [ $# -gt 0 ] || die "--route needs a value"; ROUTE="$1" ;;
    --leave)      shift; [ $# -gt 0 ] || die "--leave needs a gate id"; LEAVE+=("$1") ;;
    --rework)     [ "${REWORK:-yes}" = yes ] || die "--rework and --no-rework answer one question; give one"; REWORK=yes ;;
    --no-rework)  [ "${REWORK:-no}" = no ]   || die "--rework and --no-rework answer one question; give one"; REWORK=no ;;
    --no-wait)    WAIT+=(--no-wait) ;;
    --waiting-on) shift; [ $# -gt 0 ] || die "--waiting-on needs a bead id"; WAIT+=(--waiting-on "$1") ;;
    -h|--help)    sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            die "unknown argument '$1'" ;;
  esac
  shift
done

[ -n "$CONVERSATION" ] || die "--conversation is required"
[ -n "$OUTCOME" ] || die "--outcome is required"
case "$RULED" in yes|no) ;; *) die "--ruled must be yes or no" ;; esac
if [ "$RULED" = yes ]; then
  [ -n "$RULING" ] || die "--ruled yes requires --ruling (the answer each gate resolves with)"
  [ -n "$ROUTE" ]  || die "--ruled yes requires --route (where a held subject is released to)"
else
  [ -z "$REWORK" ] || die "--rework and --no-rework require --ruled yes (they answer what a ruling changes)"
  [ "${#LEAVE[@]}" -eq 0 ] || die "--leave requires --ruled yes: a cut-short sign-off leaves every gate open"
fi
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v gc >/dev/null 2>&1 || die "gc is required"

# The conversation's own row names its subject, its holder and the gates it
# answers, and its edges keep a reply onto a gate in another store.
CONV_ROW=$(gc bd list --id "$CONVERSATION" --all --json 2>/dev/null | grep -av '^gc bd:' | scrub \
  | jq -ce --arg c "$CONVERSATION" 'if type == "array" then (map(objects | select((.id // "") == $c)) | first // empty) else error("unread") end' 2>/dev/null)
[ -n "$CONV_ROW" ] || stopped "conversation $CONVERSATION could not be read, and its row names the subject and the gates this sign-off answers; nothing was written"
printf '%s' "$CONV_ROW" | jq -e "$CONVERSATION_JQ"'conversation' >/dev/null 2>&1 \
  || die "$CONVERSATION is not a conversation (a task that tracks one bead, assigned to human or to the alias that names its id); nothing was written"
TRACKED=$(printf '%s' "$CONV_ROW" | jq -r "$CONVERSATION_JQ"'conversation_subjects[0]')
if [ -n "$SUBJECT" ] && [ "$SUBJECT" != "$TRACKED" ]; then
  die "--subject $SUBJECT is not the bead conversation $CONVERSATION tracks ($TRACKED), and its record goes on that bead alone; nothing was written"
fi
SUBJECT="$TRACKED"
CONV_STATUS=$(printf '%s' "$CONV_ROW" | jq -r '(.status // "") | ascii_downcase')
HOLDER=$(printf '%s' "$CONV_ROW" | jq -r '(.assignee // "") | tostring')
REPLIES=$(printf '%s' "$CONV_ROW" | jq -r '[ .dependencies[]? | objects
    | select(((.type // .dependency_type) // "") == "replies-to")
    | ((.depends_on_id // .id) // "") | select(. != "") ] | unique | .[]')
for g in "${LEAVE[@]+"${LEAVE[@]}"}"; do
  printf '%s\n' "$REPLIES" | grep -qxF -- "$g" \
    || die "--leave $g names a gate conversation $CONVERSATION does not reply to; nothing was written"
done
# Each gate the conversation replies to, read now: a gate that does not read
# could be one still open, so the sign-off stops before it writes anything.
GATES_JSON='[]'
for g in $REPLIES; do
  GROW=$(show_row "$g") || stopped "gate $g, which conversation $CONVERSATION replies to, could not be read; nothing was written"
  GATES_JSON=$(printf '%s' "$GATES_JSON" | jq -c --argjson r "$GROW" '. + [$r]')
done
# A ruling that changes what an open PR's branch must contain is demand on that
# PR, and nothing but --rework turns it into demand: unfiled, the ruling lands
# only in notes nothing reads, and the PR keeps reading ready against a head the
# ruling has outdated. Only the sitting knows a ruling's consequence, so a ruled
# sign-off on an open PR must answer the question either way. A subject that
# will not read cannot be told from an open PR, so it is refused the same way.
if [ "$RULED" = yes ] && [ -z "$REWORK" ]; then
  SUBJECT_ROW=$(show_row "$SUBJECT") \
    || die "could not read $SUBJECT to tell whether it is an open PR; nothing was written. Re-run with --rework or --no-rework"
  if [ "$(printf '%s' "$SUBJECT_ROW" | jq -r '.metadata.merge_result // ""')" = pull_request ]; then
    die "$SUBJECT is an open PR (merge_result=pull_request), so a --ruled yes sign-off must say whether the ruling changes what its branch must contain; nothing was written. Re-run with --rework to file the rework, or --no-rework if the branch stands"
  fi
fi
# A ruling releases a subject that still reads `held`, so the state is read
# here, with the other reads. lifecycle.sh exits 2 when the subject does not
# read, an answer that cannot say whether it is held. Any other refusal (an
# undeclared state, no gctk binary) answers as not held, the side that leaves
# the bead visibly waiting on a person.
LC=$(pack_script lifecycle.sh)
SUBJECT_STATE=""
if [ "$RULED" = yes ] && [ -n "$LC" ]; then
  SUBJECT_STATE=$("$LC" state "$SUBJECT" 2>/dev/null)
  [ $? -ne 2 ] || stopped "the lifecycle state of $SUBJECT could not be read, so this ruling cannot tell whether to release it from held; nothing was written"
fi
HELM=$(pack_script gc-helm.sh) || stopped "no gc-helm.sh on any candidate root, so the subject's headline cannot be written; nothing was written"

# 1. The rework. A ruling can make an already-published PR stale: --rework
# files the fix unit a review verdict files, sourced by this conversation, and
# returns every review lane to unreviewed. Filed first, the child's blocks edge
# already holds the merge before any gate this sitting answers is resolved. A
# filing that does not complete stops the sign-off with nothing else written,
# and a re-run adopts a child an earlier attempt filed.
REWORK_FILED=""
if [ "$RULED" = yes ] && [ "$REWORK" = yes ]; then
  CR=$(pack_script converse-rework.sh)
  if [ -z "$CR" ]; then
    REWORK_OUT="no converse-rework.sh on any candidate root"
  elif REWORK_OUT=$("$CR" --anchor "$SUBJECT" --ruling-bead "$CONVERSATION" --ruling "$RULING" 2>&1); then
    echo "$REWORK_OUT"
    REWORK_FILED=yes
  fi
  if [ -z "$REWORK_FILED" ]; then
    echo "REWORK NOT COMPLETE on $SUBJECT: $REWORK_OUT"
    echo "Nothing is signed off: no headline, gate or close was written. Do NOT post the sign-off."
    echo "Repair the cause and re-run this sign-off. If $SUBJECT is not an open PR, file the ruling's consequence as work, then re-run without --rework and with --waiting-on <that bead>. If it cannot be repaired, raise it in the thread."
    exit 1
  fi
fi

# 2. The headline. An ARRAY, not a string: this city runs zsh, which does not
# word-split an unquoted parameter, so "${WAIT[@]}" is what passes each flag as
# its own argument, and nothing when it is empty.
"$HELM" takeaway "$SUBJECT" "$OUTCOME" --by converse "${WAIT[@]+"${WAIT[@]}"}" \
  || stopped "the headline did not land on $SUBJECT (gc-helm.sh takeaway refused it); no gate was resolved and the conversation is not closed"
show_row "$SUBJECT" | jq -e '(.metadata["gc.takeaway"] // "") != ""' >/dev/null 2>&1 \
  || stopped "no headline reads back on $SUBJECT; no gate was resolved and the conversation is not closed"

ACTIONS=()
routed=""
i=0
while [ "$i" -lt "${#WAIT[@]}" ]; do
  [ "${WAIT[$i]}" = "--waiting-on" ] && { i=$((i + 1)); routed="${routed:+$routed, }${WAIT[$i]}"; }
  i=$((i + 1))
done
[ -n "$routed" ] && ACTIONS+=("routed work to $routed")

if [ "$RULED" = yes ]; then
  # 3. The gates the ruling answers. A reply onto a bead that is no human gate
  # holds nothing to resolve.
  case "$RULING" in ruled:*) ANSWER="$RULING" ;; *) ANSWER="ruled: $RULING" ;; esac
  UNCLOSED=""
  for g in $REPLIES; do
    if printf '%s\n' "${LEAVE[@]+"${LEAVE[@]}"}" | grep -qxF -- "$g"; then
      echo "gate $g stays open and owed: the ruling leaves it, and this conversation's reply stays on it"
      ACTIONS+=("left gate $g owed")
      continue
    fi
    GROW=$(printf '%s' "$GATES_JSON" | jq -c --arg g "$g" '.[] | select(.id == $g)')
    if ! printf '%s' "$GROW" | jq -e '(.issue_type // "") == "gate" and (.await_type // "") == "human"' >/dev/null 2>&1; then
      echo "$g, which conversation $CONVERSATION replies to, is no human gate; nothing to resolve there"
      continue
    fi
    if [ "$(printf '%s' "$GROW" | jq -r '(.status // "") | ascii_downcase')" = closed ]; then
      echo "gate $g was already cleared before this sign-off: \"$(printf '%s' "$GROW" | jq -r '.close_reason // ""')\". That answer stands."
      continue
    fi
    gc bd gate resolve "$g" --reason "$ANSWER" >/dev/null 2>&1 || true
    BACK=$(show_row "$g") || BACK=""
    BACK_STATUS=$(printf '%s' "$BACK" | jq -r '(.status // "") | ascii_downcase' 2>/dev/null)
    BACK_REASON=$(printf '%s' "$BACK" | jq -r '.close_reason // ""' 2>/dev/null)
    if [ "$BACK_STATUS" != closed ]; then
      echo "GATE $g DID NOT CLOSE — it still holds what waits on it"
      UNCLOSED="${UNCLOSED:+$UNCLOSED }$g"
    elif [ "$BACK_REASON" != "$ANSWER" ]; then
      echo "another answer reached gate $g first: \"$BACK_REASON\". The first answer stands, and this ruling is not its answer."
    else
      RELEASED=$(gc bd dep list "$g" --direction=up --type blocks --json 2>/dev/null | scrub \
        | jq -r '[ .[]? | objects | .id // empty ] | join(" ")' 2>/dev/null || true)
      echo "resolved gate $g: $ANSWER${RELEASED:+ (it held $RELEASED)}"
      ACTIONS+=("resolved gate $g")
    fi
  done
  [ -z "$UNCLOSED" ] || stopped "the ruling did not close $UNCLOSED; the conversation is not closed, so a re-run resolves it"

  # 4. `held` is cleared by a ruling, not by a sitting ending. The state was
  # read before the first write; nothing this sign-off writes changes it.
  if [ "$SUBJECT_STATE" = "held" ]; then
    "$LC" transition "$SUBJECT" --to unanchored --route "$ROUTE" \
      || echo "RELEASE FROM held FAILED on $SUBJECT — it still reads as waiting on a person"
  fi
  ACTIONS+=("ruling: $RULING (released to $ROUTE)")
  [ -n "$REWORK_FILED" ] && ACTIONS+=("filed ruling-driven rework on $SUBJECT")
  [ "$REWORK" = no ] && ACTIONS+=("ruling leaves the branch of $SUBJECT as it stands")

  # 5. Close the conversation. The work-record gate the close runs wants
  # gc.work_outcome, stamped in a write of its own so it never decides whether
  # the conversation closes. The sitting holds the conversation, so a plain
  # close is the holder's own; --force covers an actor bd does not read as its
  # holder. A close counts once it reads back.
  if [ "$CONV_STATUS" != closed ]; then
    work_outcome_noop "$CONVERSATION" gc bd
    gc bd close "$CONVERSATION" --reason "$OUTCOME" >/dev/null 2>&1 \
      || gc bd close "$CONVERSATION" --reason "$OUTCOME" --force >/dev/null 2>&1 \
      || true
    [ "$(show_row "$CONVERSATION" | jq -r '(.status // "") | ascii_downcase' 2>/dev/null)" = closed ] \
      || stopped "conversation $CONVERSATION did not close; every gate above is answered, and a re-run closes it"
  fi
  REMINDER_OUTCOME=settled
else
  # Cut short: the gates stay open and owed, with their replies in place, and
  # the conversation goes back to the operator's queue with one write guarded
  # on the sitting that holds it, which drops the claim's lease. A conversation
  # already in the queue has no sitting to hand it back from.
  if [ "$HOLDER" != human ]; then
    gc bd update "$CONVERSATION" --if-assignee "$HOLDER" --assignee human --status open >/dev/null 2>&1 || true
    BACK=$(show_row "$CONVERSATION") || BACK=""
    if [ "$(printf '%s' "$BACK" | jq -r '"\(.assignee // "")/\(.status // "")"' 2>/dev/null)" != "human/open" ]; then
      stopped "conversation $CONVERSATION did not read back in the operator's queue (assignee human, status open) after its hand-back from $HOLDER; re-run once the store answers"
    fi
  fi
  [ -n "$REPLIES" ] && ACTIONS+=("left $(printf '%s' "$REPLIES" | tr '\n' ' ' | sed 's/ *$//') open and owed")
  ACTIONS+=("conversation back in the operator's queue")
  REMINDER_OUTCOME="handed back"
fi

# 6. The PR reminder, once the conversation reads closed or back in the queue.
# Best effort and update-only: a conversation no sitting engaged left no comment.
REMINDER=$(pack_script pr-sitting-comment.sh)
if [ -n "$REMINDER" ]; then
  ACTIONS_TEXT=""
  for a in "${ACTIONS[@]+"${ACTIONS[@]}"}"; do ACTIONS_TEXT="${ACTIONS_TEXT:+$ACTIONS_TEXT; }$a"; done
  "$REMINDER" close --sitting "$CONVERSATION" --subject "$SUBJECT" \
    --outcome "$REMINDER_OUTCOME" --summary "$OUTCOME" --actions "$ACTIONS_TEXT" || true
fi
echo "SIGNED OFF conversation $CONVERSATION on $SUBJECT ($REMINDER_OUTCOME)"
