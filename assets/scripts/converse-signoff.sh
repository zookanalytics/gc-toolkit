#!/usr/bin/env bash
# converse-signoff.sh — a sitting's sign-off: the durable trace it owes, written
# in one order every time.
#
# A sitting holds one conversation, a task that tracks the subject and replies
# to each human gate it answers. When the operator ruled (--ruled yes), the
# sign-off:
#   1. carries out what the ruling does to an open PR it reaches, the subject
#      or a bead a gate it answers releases: its rework, through
#      converse-rework.sh with the conversation as the rework's
#      source_ruling_bead (--rework), or its retirement, through pr-dispose.sh,
#      which records the disposition and closes the PR (--retire);
#   2. writes the subject's headline (gc-helm.sh takeaway) and reads it back;
#   3. resolves each open gate the conversation replies to with
#      `ruled: <ruling>`, except each one --leave names, and reads each back. bd
#      resolves a closed gate without changing it and reports success either
#      way, so a close reason other than this one means another answer reached
#      the gate first: a filer's withdrawal, an Accept, another sitting, or a
#      person at the command line. The first answer wins, and the sign-off
#      reports it;
#   4. releases a subject that reads `held`;
#   5. takes the subject's recommendation when the ruling takes it (--accept),
#      through gc-helm.sh accept, the writer the board's Accept runs: under the
#      subject's acceptance lock it answers the recommendation's gate, which
#      step 3 leaves to it, dispatches the recommended formula at the subject
#      and records the dispatch, or finishes an acceptance an earlier Accept
#      left unfinished without dispatching it again;
#   6. closes the conversation;
#   7. updates the subject's PR reminder.
# A gate can hold a merge, and resolving it releases the merge, so everything
# the ruling puts in the merge's way is written before step 3: the rework
# child's blocks edge, the closed PR, and each wait the headline wires. The
# beads each gate releases are read before the first write, so a gate that
# releases an open PR other than the subject, such as an epic member's gate the
# epic's sitting answers, or a gate about the subject and another PR, puts the
# question of that PR to the ruling just as an open-PR subject does. The
# acceptance follows the release, because a workflow poured at a bead that
# still reads `held` ends its run as finished.
#
# A ruling given on a turn that does not sign off (--answer) runs steps 1 to 3
# for the gates --answer names, and step 5 when it takes the recommendation,
# and stops there: the conversation stays open under its sitting, and the
# sign-off later reads each of those gates as already cleared.
#
# Cut short (--ruled no), it writes the headline, leaves every gate the
# conversation replies to open and owed, with its reply in place for the next
# sitting, and hands the conversation back to the operator's queue with one
# write guarded on the sitting that holds it and the status it read, then
# updates the reminder. A conversation that reads closed, before that write or
# because a dismiss closed it first, stays closed.
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
#     [--route <rig>/<agent>|human] [--leave <gate> ...] [--answer <gate> ...] \
#     [--no-wait | --waiting-on <bead> ...] \
#     [--rework | --no-rework | --retire <kind> [--successor <bead>]] \
#     [--pr-anchor <bead>] [--accept]
#   --outcome is the subject's headline, and the close reason the sittings card
#   falls back to. --ruled defaults to `no`. --ruled yes requires --ruling, the
#   answer each gate resolves with, and --route, where a `held` subject is
#   released to. --subject, when given, must be the bead the conversation tracks.
#   --leave (with --ruled yes) names a gate the conversation replies to that the
#   ruling leaves owed: it stays open, and its reply stays as the record that
#   this conversation took it up.
#   --answer names a gate the conversation replies to that the ruling answers
#     on a turn that does not sign off. It carries a ruling, so it takes
#     --ruling and the open-PR answer below; it releases no subject and leaves
#     every other gate as it is, so --ruled no, --route and --leave are refused
#     beside it.
#   --rework | --no-rework | --retire <kind> (with a ruling): what the ruling
#     does to an already-published PR it reaches: the subject at
#     merge_result=pull_request, and each bead at merge_result=pull_request
#     that a human gate the ruling answers releases, while the gate is open or
#     once this ruling's own answer has closed it, so a re-run reaches the PRs
#     an earlier attempt did. A ruling that reaches one must give one of them;
#     given none, it is refused with nothing written. --rework says the PR's branch must change: the rework is filed
#     against that PR's anchor, sourced by this conversation, and refused while
#     a rework the conversation filed for another ruling is open. --no-rework
#     says the branch of each such PR stands, and the PR reminder records that.
#     --retire says the PR will not land: pr-dispose.sh records the disposition
#     under <kind> (re-homed, folded, fixed-upstream, duplicate or not-needed)
#     and closes the PR. Its successor is --successor, the bead that carries
#     the work now, which every kind but not-needed requires; under not-needed
#     it defaults to this conversation, the evidence that ruled the work out.
#     --rework and --retire act on one PR, the one the ruling reaches, else
#     the subject. The rework or the retirement runs before every other write,
#     and when it does not complete nothing else is written.
#   --pr-anchor <bead> names the PR --rework or --retire acts on when the
#     ruling reaches more than one, which it requires; every other one the
#     ruling reaches stands. A conversation owns one live rework child, so a
#     sign-off files one rework, and a second PR whose branch must change takes
#     a ruling of its own: the gate that releases it stays owed until then.
#   --accept (with a ruling) says the ruling takes the subject's
#     recommendation, gc.recommended_formula, which a first reaction put to the
#     operator through the human gate under the key first-reaction. That gate
#     must be one the ruling answers: the conversation replies to it, and on a
#     turn that does not sign off --answer names it. Step 3 leaves it to step 5,
#     which runs gc-helm.sh accept, the one writer that dispatches a
#     recommendation, so the sitting never slings it itself. Under Accept's lock
#     and its token, a dispatch the board's Accept already poured is recorded
#     and not sent again, even when that Accept stopped before recording it.
#     Refused while another open human gate that the ruling does not answer
#     holds the subject, since the dispatch waits for every gate that holds it,
#     and, on a turn that does not sign off, while the subject reads `held`,
#     which only the sign-off releases.
# Exit: 0 signed off, or with --answer the named gates answered; 1 stopped
#   short — a read failed, the rework did not file, the PR did not retire, the
#   headline did not land, a gate did not close, the recommendation was not
#   taken, or the conversation did not close or hand back — so do NOT post the
#   sign-off, or report the ruling as carried out; repair what it names and
#   re-run, which repeats every write it made safely; 2 refused before any
#   write: usage, a conversation that is not one, a gate it does not reply to,
#   a ruling that reaches an open PR and gave none of --rework, --no-rework and
#   --retire, a --rework or --retire on a ruling that reaches more than one open
#   PR without a --pr-anchor naming one of them, or an --accept with no
#   recommendation's gate among the gates the ruling answers, no recommendation
#   on the subject, another open human gate the ruling does not answer, or a
#   held subject on a turn that does not sign off.
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
RULED=""
RULING=""
ROUTE=""
PR_ANSWER=""
RETIRE_KIND=""
SUCCESSOR=""
PR_PICK=""
ACCEPT=""
WAIT=()
LEAVE=()
ANSWER_GATES=()
UNDONE="NOT SIGNED OFF — do NOT post the sign-off."

die() { echo "converse-signoff: $1" >&2; exit 2; }
# stopped <why> — refuse the sign-off (exit 1). Whatever ran before it is a write
# a re-run repeats safely.
stopped() {
  echo "converse-signoff: $1" >&2
  echo "$UNDONE Repair what is named above, then re-run this call."
  exit 1
}
# pr_answer <rework|no-rework|retire> — the one answer to what a ruling does to
# an open PR.
pr_answer() {
  [ -z "$PR_ANSWER" ] || [ "$PR_ANSWER" = "$1" ] || die "--rework, --no-rework and --retire answer one question; give one"
  PR_ANSWER="$1"
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
# The one read of which human gates still hold a bead, the read gc-helm.sh
# accept makes. Exposes bd_open_human_gates.
# shellcheck source=bd-lib.sh
. "$HERE/bd-lib.sh" || die "cannot source bd-lib.sh from $HERE"

while [ $# -gt 0 ]; do
  case "$1" in
    --conversation) shift; [ $# -gt 0 ] || die "--conversation needs a value"; CONVERSATION="$1" ;;
    --subject)    shift; [ $# -gt 0 ] || die "--subject needs a value"; SUBJECT="$1" ;;
    --outcome)    shift; [ $# -gt 0 ] || die "--outcome needs a value"; OUTCOME="$1" ;;
    --ruled)      shift; [ $# -gt 0 ] || die "--ruled needs yes|no"; RULED="$1" ;;
    --ruling)     shift; [ $# -gt 0 ] || die "--ruling needs a value"; RULING="$1" ;;
    --route)      shift; [ $# -gt 0 ] || die "--route needs a value"; ROUTE="$1" ;;
    --leave)      shift; [ $# -gt 0 ] || die "--leave needs a gate id"; LEAVE+=("$1") ;;
    --answer)     shift; [ $# -gt 0 ] || die "--answer needs a gate id"; ANSWER_GATES+=("$1") ;;
    --rework)     pr_answer rework ;;
    --no-rework)  pr_answer no-rework ;;
    --retire)     shift; [ $# -gt 0 ] || die "--retire needs a kind"; pr_answer retire; RETIRE_KIND="$1" ;;
    --successor)  shift; [ $# -gt 0 ] || die "--successor needs a bead id"; SUCCESSOR="$1" ;;
    --pr-anchor)  shift; [ $# -gt 0 ] || die "--pr-anchor needs a bead id"; PR_PICK="$1" ;;
    --accept)     ACCEPT=yes ;;
    --no-wait)    WAIT+=(--no-wait) ;;
    --waiting-on) shift; [ $# -gt 0 ] || die "--waiting-on needs a bead id"; WAIT+=(--waiting-on "$1") ;;
    -h|--help)    sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            die "unknown argument '$1'" ;;
  esac
  shift
done

[ -n "$CONVERSATION" ] || die "--conversation is required"
[ -n "$OUTCOME" ] || die "--outcome is required"
case "${RULED:-no}" in yes|no) ;; *) die "--ruled must be yes or no" ;; esac
ANSWERING=""
if [ "${#ANSWER_GATES[@]}" -gt 0 ]; then
  ANSWERING=yes
  [ "${RULED:-yes}" = yes ] || die "--answer carries a ruling, so it cannot be --ruled no"
  [ -n "$RULING" ] || die "--answer requires --ruling (the answer each gate it names resolves with)"
  [ -z "$ROUTE" ] || die "--route is where a sign-off releases a held subject to, and --answer releases nothing"
  [ "${#LEAVE[@]}" -eq 0 ] || die "--answer resolves only the gates it names, so --leave has nothing to leave"
  RULED=yes
  UNDONE="NOT ANSWERED — do NOT tell the operator the ruling is carried out."
fi
RULED="${RULED:-no}"
if [ "$RULED" = yes ]; then
  [ -n "$RULING" ] || die "--ruled yes requires --ruling (the answer each gate resolves with)"
  [ -n "$ANSWERING" ] || [ -n "$ROUTE" ] || die "--ruled yes requires --route (where a held subject is released to)"
else
  [ -z "$PR_ANSWER" ] || die "--rework, --no-rework and --retire require a ruling (they answer what it does to an open PR)"
  [ "${#LEAVE[@]}" -eq 0 ] || die "--leave requires --ruled yes: a cut-short sign-off leaves every gate open"
  [ -z "$ACCEPT" ] || die "--accept requires a ruling (--ruled yes, or --answer): it takes the recommendation the operator ruled to take"
fi
if [ "$PR_ANSWER" = retire ]; then
  case "$RETIRE_KIND" in
    re-homed|folded|fixed-upstream|duplicate|not-needed) ;;
    *) die "--retire takes a kind: re-homed, folded, fixed-upstream, duplicate or not-needed (got '$RETIRE_KIND')" ;;
  esac
  [ "$RETIRE_KIND" = not-needed ] || [ -n "$SUCCESSOR" ] \
    || die "--retire $RETIRE_KIND requires --successor, the bead that carries the work now"
else
  [ -z "$SUCCESSOR" ] || die "--successor names a retired PR's successor, so it requires --retire"
fi
case "$PR_ANSWER" in
  rework|retire) ;;
  *) [ -z "$PR_PICK" ] || die "--pr-anchor names the open PR --rework or --retire acts on, so it requires one of them" ;;
esac
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
for g in "${ANSWER_GATES[@]+"${ANSWER_GATES[@]}"}"; do
  printf '%s\n' "$REPLIES" | grep -qxF -- "$g" \
    || die "--answer $g names a gate conversation $CONVERSATION does not reply to; add the reply first, then re-run. Nothing was written"
done
[ "$PR_ANSWER" != retire ] || [ -n "$SUCCESSOR" ] || SUCCESSOR="$CONVERSATION"
# Each gate the conversation replies to, read now: a gate that does not read
# could be one still open, so the sign-off stops before it writes anything.
GATES_JSON='[]'
for g in $REPLIES; do
  GROW=$(show_row "$g") || stopped "gate $g, which conversation $CONVERSATION replies to, could not be read; nothing was written"
  GATES_JSON=$(printf '%s' "$GATES_JSON" | jq -c --argjson r "$GROW" '. + [$r]')
done
# The gates the ruling answers: those --answer names, or else each one the
# conversation replies to. Step 3 skips the ones --leave names, and resolves the
# rest with ANSWER.
TO_ANSWER=""
ANSWER=""
if [ "$RULED" = yes ]; then
  if [ -n "$ANSWERING" ]; then TO_ANSWER="${ANSWER_GATES[*]}"; else TO_ANSWER="$REPLIES"; fi
  case "$RULING" in ruled:*) ANSWER="$RULING" ;; *) ANSWER="ruled: $RULING" ;; esac
fi
# A ruling that changes what an open PR's branch must contain is demand on that
# PR, and nothing but --rework turns it into demand: unfiled, the ruling lands
# only in notes nothing reads, and the PR keeps reading ready against a head the
# ruling has outdated. A ruling that the PR will not land must close it before
# any gate it answers releases the merge, or an approved PR lands first. Only
# the sitting knows a ruling's consequence, so a ruling must answer the question
# for each open PR it reaches: the subject when it is one, and each bead at
# merge_result=pull_request that a human gate the ruling answers releases, such
# as an epic member whose gate the epic's sitting answers, or the other PR behind
# a gate about two. Such a gate is one still open, or one this ruling's own
# answer has closed: an attempt that stopped after resolving it had already
# acted on what it released, and the re-run it asks for must act on the same PR
# rather than fall back to the subject. What each such gate releases is read
# here, with the other reads. A listing of a gate's beads, or the row of a bead
# it releases, that does not read could hide an open PR, so the sign-off stops
# before it writes anything, and a subject that will not read cannot be told
# from an open PR either.
PR_ANCHORS=()
GATE_WAITERS='{}'
reaches_pr() { # <bead> — 0 when the ruling already reaches it as an open PR
  local p
  for p in "${PR_ANCHORS[@]+"${PR_ANCHORS[@]}"}"; do [ "$p" = "$1" ] && return 0; done
  return 1
}
if [ "$RULED" = yes ]; then
  if ! SUBJECT_ROW=$(show_row "$SUBJECT"); then
    [ -n "$PR_ANSWER" ] || die "could not read $SUBJECT to tell whether it is an open PR; nothing was written. Re-run with --rework, --no-rework or --retire <kind>"
    stopped "could not read $SUBJECT to tell whether it is an open PR, which decides the PR the ruling's answer acts on; nothing was written"
  fi
  [ "$(printf '%s' "$SUBJECT_ROW" | jq -r '.metadata.merge_result // ""')" = pull_request ] && PR_ANCHORS+=("$SUBJECT")
  for g in $TO_ANSWER; do
    printf '%s\n' "${LEAVE[@]+"${LEAVE[@]}"}" | grep -qxF -- "$g" && continue
    printf '%s' "$GATES_JSON" | jq -e --arg g "$g" --arg a "$ANSWER" 'any(.[]; .id == $g and (.issue_type // "") == "gate"
        and (.await_type // "") == "human"
        and (((.status // "") | ascii_downcase) != "closed" or (.close_reason // "") == $a))' >/dev/null 2>&1 || continue
    WAITERS=$(gc bd dep list "$g" --direction=up --type blocks --json 2>/dev/null | grep -av '^gc bd:' | scrub \
      | jq -ce 'if type == "array" then [ .[] | objects ] else error("unread") end' 2>/dev/null) \
      || stopped "the beads that wait on gate $g could not be read, and answering it releases them, so an open PR among them could not be told; nothing was written"
    GATE_WAITERS=$(printf '%s' "$GATE_WAITERS" | jq -c --arg g "$g" --argjson w "$WAITERS" '. + {($g): [ $w[] | (.id // "") | select(. != "") ]}')
    for b in $(printf '%s' "$WAITERS" | jq -r --arg s "$SUBJECT" '.[]
        | select(((.status // "") | tostring | ascii_downcase) != "closed")
        | (.id // "") | select(. != "" and . != $s)'); do
      reaches_pr "$b" && continue
      BROW=$(show_row "$b") \
        || stopped "$b, which gate $g releases, could not be read to tell whether it is an open PR; nothing was written"
      [ "$(printf '%s' "$BROW" | jq -r '.metadata.merge_result // ""')" = pull_request ] && PR_ANCHORS+=("$b")
    done
  done
fi
PR_LIST="${PR_ANCHORS[*]+"${PR_ANCHORS[*]}"}"
if [ "$RULED" = yes ] && [ -z "$PR_ANSWER" ] && [ -n "$PR_LIST" ]; then
  [ "$PR_LIST" != "$SUBJECT" ] \
    || die "$SUBJECT is an open PR (merge_result=pull_request), so a ruling on it must say what it does to the PR; nothing was written. Re-run with --rework to file the rework its branch needs, --no-rework if the branch stands, or --retire <kind> if the PR will not land"
  die "this ruling reaches $PR_LIST at merge_result=pull_request, as its subject or as a bead a gate it answers releases, so it must say what it does to each open PR; nothing was written. Re-run with --rework to file the rework a branch needs, --no-rework if the branch stands, or --retire <kind> if the PR will not land, and with --pr-anchor <bead> to name the one --rework or --retire acts on when it reaches more than one"
fi
# --rework and --retire act on one open PR: the one the ruling reaches, the one
# --pr-anchor names when it reaches more than one, or else the subject, which
# converse-rework.sh and pr-dispose.sh refuse unless it is an open PR. A
# conversation owns one live rework child (rework-child.sh), so one sign-off
# files one rework, and each other open PR the ruling reaches stands under it,
# as --no-rework says of every one.
PR_TARGET=""
STANDS=()
case "$PR_ANSWER" in
  rework|retire)
    if [ -n "$PR_PICK" ]; then
      reaches_pr "$PR_PICK" \
        || die "--pr-anchor $PR_PICK is no open PR this ruling reaches (${PR_LIST:-none}); nothing was written"
      PR_TARGET="$PR_PICK"
    elif [ "${#PR_ANCHORS[@]}" -gt 1 ]; then
      die "this ruling reaches more than one open PR ($PR_LIST), and --$PR_ANSWER acts on one; nothing was written. Name it with --pr-anchor <bead>, and each other one stands under this ruling. A conversation files one live rework, so a PR whose own branch must change or which must retire as well takes a ruling of its own: leave the gate that releases it owed, with --leave or out of --answer, until that ruling is carried out"
    else
      PR_TARGET="${PR_ANCHORS[0]:-$SUBJECT}"
    fi
    for p in "${PR_ANCHORS[@]+"${PR_ANCHORS[@]}"}"; do [ "$p" = "$PR_TARGET" ] || STANDS+=("$p"); done ;;
  no-rework)
    STANDS=("${PR_ANCHORS[@]+"${PR_ANCHORS[@]}"}")
    [ "${#STANDS[@]}" -gt 0 ] || STANDS=("$SUBJECT") ;;
esac
# --accept takes the subject's recommendation through the gate that put it to
# the operator, the human gate under the key first-reaction. That gate must be
# one the ruling answers, so the conversation's reply on it records which
# conversation took it up. Step 3 leaves it, and step 5 hands it to Accept's
# writer. Accept dispatches only once no other open human gate holds the
# subject, because a formula's sling reads no blocks edge, so a gate this
# ruling does not answer refuses the take here, before any write, rather than
# after step 3 has answered the others. Accept answers every open gate under
# the key, as it does on the board, so a twin that a race filed under the key
# does not count as another gate.
REC_GATES=""
REC_FORMULA=""
if [ -n "$ACCEPT" ]; then
  ANSWERED_GATES=""
  for g in $TO_ANSWER; do
    printf '%s\n' "${LEAVE[@]+"${LEAVE[@]}"}" | grep -qxF -- "$g" && continue
    ANSWERED_GATES="${ANSWERED_GATES:+$ANSWERED_GATES }$g"
    printf '%s' "$GATES_JSON" | jq -e --arg g "$g" 'any(.[]; .id == $g and (.issue_type // "") == "gate"
        and (.await_type // "") == "human" and (.await_id // "") == "first-reaction")' >/dev/null 2>&1 \
      && REC_GATES="${REC_GATES:+$REC_GATES }$g"
  done
  [ -n "$REC_GATES" ] \
    || die "--accept takes $SUBJECT's recommendation through the gate that puts it to the operator, the human gate under the key first-reaction, and no gate this ruling answers is that gate; nothing was written. Reply to it first${ANSWERING:+ and name it with --answer}, then re-run"
  REC_FORMULA=$(printf '%s' "$SUBJECT_ROW" | jq -r '(.metadata // {})["gc.recommended_formula"] // "" | tostring')
  REC_SENT=$(printf '%s' "$SUBJECT_ROW" | jq -r '(.metadata // {})["gc.recommended_formula_dispatched"] // "" | tostring')
  [ -n "$REC_FORMULA$REC_SENT" ] \
    || die "--accept takes $SUBJECT's recommendation, and $SUBJECT carries none (no gc.recommended_formula); nothing was written. Answer its gate without --accept"
  REC_FORMULA="${REC_FORMULA:-$REC_SENT}"
  HOLDING=$(bd_open_human_gates "$SUBJECT") \
    || stopped "the human gates that hold $SUBJECT could not be read, and its recommendation is dispatched only once no gate but its own holds it; nothing was written"
  OTHERS=$(printf '%s' "$HOLDING" | jq -r --arg answered "$ANSWERED_GATES" '
      ($answered | split(" ")) as $a
      | [ .[] | select(((.await_id // "") | tostring) != "first-reaction")
              | select(((.id // "") | tostring) as $i | ($a | index($i)) == null)
              | "\(.id) (\(.title // "untitled"))" ] | join("; ")')
  [ -z "$OTHERS" ] \
    || die "$SUBJECT's recommendation is dispatched only once no other human gate holds it, and $OTHERS still holds it, which this ruling does not answer; nothing was written. Answer that gate in the same ruling once the operator rules on it, or leave the recommendation's gate owed until it is cleared, when Accept on the board takes the recommendation"
fi
# A ruling releases a subject that still reads `held`, so the state is read
# here, with the other reads. lifecycle.sh exits 2 when the subject does not
# read, an answer that cannot say whether it is held. Any other refusal (an
# undeclared state, no gctk binary) answers as not held, the side that leaves
# the bead visibly waiting on a person. An answer releases nothing, so it reads
# no state unless it takes the recommendation: a workflow poured at a bead that
# reads `held` ends its run as finished, and only the sign-off releases one, so
# such an answer is refused.
LC=$(pack_script lifecycle.sh)
SUBJECT_STATE=""
if [ "$RULED" = yes ] && { [ -z "$ANSWERING" ] || [ -n "$ACCEPT" ]; } && [ -n "$LC" ]; then
  SUBJECT_STATE=$("$LC" state "$SUBJECT" 2>/dev/null)
  [ $? -ne 2 ] || stopped "the lifecycle state of $SUBJECT could not be read, so this ruling cannot tell whether it reads held; nothing was written"
fi
if [ -n "$ANSWERING" ] && [ -n "$ACCEPT" ] && [ "$SUBJECT_STATE" = held ]; then
  die "$SUBJECT reads held, which only the sign-off releases, and a workflow poured at a held bead ends its run as finished; nothing was written. Take the recommendation at the sign-off (--ruled yes with --accept)"
fi
HELM=$(pack_script gc-helm.sh) || stopped "no gc-helm.sh on any candidate root, so the subject's headline cannot be written; nothing was written"

# take_recommendation — step 5: hand the recommendation's gate to gc-helm.sh
# accept, the writer the board's Accept runs, and read back what it left. Accept
# exits 0 once it has dispatched the formula, or recorded a dispatch that an
# earlier Accept poured under its token. Any other exit is read off the gates
# and the subject. A recommendation already dispatched and withdrawn was taken,
# and an answer that reached the gate first stands, as in step 3. Anything
# else stops the sign-off here, before the conversation closes, so a re-run
# takes the recommendation once Accept can.
take_recommendation() {
  local out rc g row st why other="" open=""
  out=$("$HELM" accept "$SUBJECT" --conversation "$CONVERSATION" --reason "$RULING" 2>&1); rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then
    echo "took the recommendation: $REC_FORMULA at $SUBJECT, through Accept"
    ACTIONS+=("took the recommendation: $REC_FORMULA, through Accept")
    return 0
  fi
  for g in $REC_GATES; do
    row=$(show_row "$g") \
      || stopped "gc-helm.sh accept exited $rc, and gate $g could not be read back to tell whether the recommendation was taken; the conversation is not closed"
    st=$(printf '%s' "$row" | jq -r '(.status // "") | ascii_downcase')
    why=$(printf '%s' "$row" | jq -r '.close_reason // ""')
    if [ "$st" != closed ]; then
      open="${open:+$open }$g"
    elif ! printf '%s' "$why" | grep -qE '^ruled: accepted [^ ]+ accept:[0-9a-f]+$'; then
      other="${other:+$other; }$g: \"$why\""
    fi
  done
  if [ -z "$open" ] && [ -n "$other" ]; then
    echo "another answer reached the recommendation's gate first — $other. The first answer stands, so the recommendation is not taken."
    ACTIONS+=("left the recommendation untaken: another answer reached its gate first")
    return 0
  fi
  if [ -z "$open" ] && show_row "$SUBJECT" | jq -e '((.metadata // {})["gc.recommended_formula"] // "") == ""
      and ((.metadata // {})["gc.recommended_formula_dispatched"] // "") != ""' >/dev/null 2>&1; then
    echo "the recommendation was already taken: an Accept dispatched $REC_FORMULA at $SUBJECT and recorded it"
    ACTIONS+=("the recommendation was already taken through Accept")
    return 0
  fi
  stopped "the recommendation was not taken: gc-helm.sh accept exited $rc, and its output above says why${open:+, and its gate $open is still open}. The conversation is not closed. Repair what Accept names, then re-run, which finishes an acceptance Accept left unfinished without dispatching it twice"
}

# 1. What the ruling does to an open PR. --rework files the fix unit a review
# verdict files, sourced by this conversation, and returns every review lane to
# unreviewed; the child's blocks edge holds the merge. --retire records the
# disposition and closes the PR, so there is nothing left to merge. Either one
# runs before any gate this sitting answers is resolved. One that does not
# complete stops here with nothing else written, and a re-run adopts a child an
# earlier attempt filed, or finds the PR it closed.
CONSEQUENCE=""
case "$PR_ANSWER" in
  rework)
    CR=$(pack_script converse-rework.sh)
    if [ -z "$CR" ]; then
      PR_OUT="no converse-rework.sh on any candidate root"
    elif PR_OUT=$("$CR" --anchor "$PR_TARGET" --ruling-bead "$CONVERSATION" --ruling "$RULING" 2>&1); then
      echo "$PR_OUT"
      CONSEQUENCE="filed ruling-driven rework on $PR_TARGET"
    fi
    if [ -z "$CONSEQUENCE" ]; then
      echo "REWORK NOT COMPLETE on $PR_TARGET: $PR_OUT"
      echo "Nothing else was written: no headline, gate answer or close. $UNDONE"
      echo "Repair the cause and re-run. If $PR_TARGET is not an open PR, file the ruling's consequence as work, then re-run without --rework and with --waiting-on <that bead>. If it cannot be repaired, raise it in the thread."
      exit 1
    fi ;;
  retire)
    PD=$(pack_script pr-dispose.sh)
    if [ -z "$PD" ]; then
      PR_OUT="no pr-dispose.sh on any candidate root"
    elif PR_OUT=$("$PD" --anchor "$PR_TARGET" --successor "$SUCCESSOR" --kind "$RETIRE_KIND" --note "$RULING" 2>&1); then
      echo "$PR_OUT"
      CONSEQUENCE="retired the PR of $PR_TARGET ($RETIRE_KIND, successor $SUCCESSOR)"
    fi
    if [ -z "$CONSEQUENCE" ]; then
      echo "RETIREMENT NOT COMPLETE on $PR_TARGET: $PR_OUT"
      echo "Nothing else was written: no headline, gate answer or close, so each gate the conversation replies to still holds the merge. $UNDONE"
      echo "Repair the cause and re-run; pr-dispose.sh keeps a disposition an earlier attempt recorded and closes the PR it left open. If it cannot be repaired, raise it in the thread."
      exit 1
    fi ;;
esac
for p in "${STANDS[@]+"${STANDS[@]}"}"; do echo "the ruling leaves the branch of $p as it stands"; done

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
  # 3. The gates the ruling answers: those --answer names, or else each one the
  # conversation replies to. A reply onto a bead that is no human gate holds
  # nothing to resolve. The recommendation's gate, when the ruling takes the
  # recommendation, is step 5's to answer through Accept.
  UNCLOSED=""
  for g in $TO_ANSWER; do
    case " $REC_GATES " in *" $g "*) continue ;; esac
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
      RELEASED=$(printf '%s' "$GATE_WAITERS" | jq -r --arg g "$g" '(.[$g] // []) | join(" ")')
      echo "resolved gate $g: $ANSWER${RELEASED:+ (it held $RELEASED)}"
      ACTIONS+=("resolved gate $g")
    fi
  done
  [ -z "$UNCLOSED" ] || stopped "the ruling did not close $UNCLOSED; the conversation is not closed, so a re-run resolves it"
  if [ -n "$ANSWERING" ]; then
    [ -z "$ACCEPT" ] || take_recommendation
    echo "ANSWERED $TO_ANSWER for conversation $CONVERSATION on $SUBJECT; the conversation stays open, and its sign-off reads each of those gates as already cleared"
    exit 0
  fi

  # 4. `held` is cleared by a ruling, not by a sitting ending. The state was
  # read before the first write; nothing this sign-off writes changes it.
  RELEASE_FAILED=""
  if [ "$SUBJECT_STATE" = "held" ]; then
    "$LC" transition "$SUBJECT" --to unanchored --route "$ROUTE" \
      || { echo "RELEASE FROM held FAILED on $SUBJECT — it still reads as waiting on a person"; RELEASE_FAILED=yes; }
  fi
  ACTIONS+=("ruling: $RULING (released to $ROUTE)")
  [ -n "$CONSEQUENCE" ] && ACTIONS+=("$CONSEQUENCE")
  for p in "${STANDS[@]+"${STANDS[@]}"}"; do ACTIONS+=("ruling leaves the branch of $p as it stands"); done

  # 5. The recommendation, once nothing holds the subject back: a workflow
  # poured at a bead that still reads `held` ends its run as finished.
  if [ -n "$ACCEPT" ]; then
    [ -z "$RELEASE_FAILED" ] \
      || stopped "the recommendation is not taken while $SUBJECT reads held, because a workflow poured at a held bead ends its run as finished; the conversation is not closed, so a re-run releases it and then takes the recommendation"
    take_recommendation
  fi

  # 6. Close the conversation. The work-record gate the close runs wants
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
  # on the sitting that holds it and on the status read above, which drops the
  # claim's lease. A conversation already in the queue has no sitting to hand
  # it back from. One that reads closed has ended, by a dismiss or an earlier
  # sign-off, and bd's close keeps its assignee, so a write guarded on the
  # holder alone would reopen it: it stays closed. A dismiss that lands between
  # the read and the write fails the status guard, and the read-back finds the
  # conversation closed.
  [ -n "$REPLIES" ] && ACTIONS+=("left $(printf '%s' "$REPLIES" | tr '\n' ' ' | sed 's/ *$//') open and owed")
  BACK_AT=""
  if [ "$CONV_STATUS" = closed ]; then
    echo "conversation $CONVERSATION already reads closed, so it stays closed and is not handed back"
  elif [ "$HOLDER" = human ]; then
    BACK_AT="human/open"
  else
    gc bd update "$CONVERSATION" --if-assignee "$HOLDER" --if-status "$CONV_STATUS" --assignee human --status open >/dev/null 2>&1 || true
    BACK=$(show_row "$CONVERSATION") || BACK=""
    BACK_AT=$(printf '%s' "$BACK" | jq -r '"\(.assignee // "")/\((.status // "") | ascii_downcase)"' 2>/dev/null)
    case "$BACK_AT" in
      human/open) ;;
      */closed) echo "conversation $CONVERSATION was closed while this sign-off ran, so it stays closed and is not handed back" ;;
      *) stopped "conversation $CONVERSATION did not read back in the operator's queue (assignee human, status open) after its hand-back from $HOLDER; re-run once the store answers" ;;
    esac
  fi
  if [ "$BACK_AT" = human/open ]; then
    ACTIONS+=("conversation back in the operator's queue")
    REMINDER_OUTCOME="handed back"
  else
    REMINDER_OUTCOME=""
  fi
fi

# 7. The PR reminder, once the conversation reads closed or back in the queue.
# Best effort and update-only: a conversation no sitting engaged left no comment,
# and a cut-short sign-off on one already closed leaves the reminder its closer
# wrote.
REMINDER=$(pack_script pr-sitting-comment.sh)
if [ -n "$REMINDER" ] && [ -n "$REMINDER_OUTCOME" ]; then
  ACTIONS_TEXT=""
  for a in "${ACTIONS[@]+"${ACTIONS[@]}"}"; do ACTIONS_TEXT="${ACTIONS_TEXT:+$ACTIONS_TEXT; }$a"; done
  "$REMINDER" close --sitting "$CONVERSATION" --subject "$SUBJECT" \
    --outcome "$REMINDER_OUTCOME" --summary "$OUTCOME" --actions "$ACTIONS_TEXT" || true
fi
echo "SIGNED OFF conversation $CONVERSATION on $SUBJECT (${REMINDER_OUTCOME:-already closed})"
