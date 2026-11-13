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
#      which records the disposition and closes the PR (--retire). Either one
#      runs in that PR's own rig, its store, pool and checkout, whichever rig
#      the conversation lives in, and the PR it acts on is recorded on the
#      conversation before it acts, so a re-run of the same ruling acts on the
#      same PR even once that PR has closed. The rework is recorded there too
#      once it is filed, so a re-run once it has closed files no second one;
#   2. writes the subject's headline through gc-helm.sh takeaway, and stops
#      when takeaway refuses it, then, when the ruling leaves the subject
#      waiting on work, its close brief and the arm of its validating closer,
#      and lifts a hold:mayor that would keep that arm from sending it;
#   3. resolves each open gate the conversation replies to with
#      `ruled: <ruling>`, except each one --leave names, and reads each back. bd
#      resolves a closed gate without changing it and reports success either
#      way, so a close reason other than this one means another answer reached
#      the gate first: a filer's withdrawal, an Accept, another sitting, or a
#      person at the command line. The first answer wins, and the sign-off
#      reports it;
#   4. takes the subject's recommendation when the ruling takes it (--accept),
#      through gc-helm.sh accept, the writer the board's Accept runs: under the
#      subject's acceptance lock it answers the recommendation's gate, which
#      step 3 leaves to it, dispatches the recommended formula at the subject
#      and records the dispatch, or finishes an acceptance an earlier Accept
#      left unfinished without dispatching it again;
#   5. closes the conversation, or, when the operator agreed that the sitting
#      stays (--stay), leaves it open, waiting on the work this ruling sent;
#   6. draws the comment that shows the visit on the subject's PR again, from
#      the conversation, once it is closed.
# What it does to the subject's universe is recorded on the conversation as it
# lands, one comment in plain words for each act: the rework or the retirement,
# the ruling once the gates carry it, and the recommendation taken. The comment
# on the PR shows the conversation's comments as the visit's actions.
# A gate can hold a merge, and resolving it releases the merge, so everything
# the ruling puts in the merge's way is written before step 3: the rework
# child's blocks edge, the closed PR, and each wait the headline wires. The
# beads each gate releases are read before the first write, so a gate that
# releases an open PR other than the subject, such as an epic member's gate the
# epic's sitting answers, or a gate about the subject and another PR, puts the
# question of that PR to the ruling just as an open-PR subject does.
#
# A ruling is not an approval: the merge counts only an Approve review on GitHub
# from an account other than the city's (review-verdict.sh). So the headline
# says when an open PR the ruling leaves standing still needs one, naming one PR
# and counting several so the clause fits the cap, and a printed line gives the
# sitting each PR's link. The reviews are read before the first write, each call
# bounded at 20 seconds, so a stalled read cannot hold the ruling's writes. A PR
# whose reviews do not read counts as needing one: a needless ask costs a glance,
# and a missed one leaves the PR unmerged. A standing request for changes holds
# the merge whatever approval stands, so a PR with both needs no Approve, and its
# line names whose request holds it. The sign-off cannot tell which login is the
# operator's, so each line reads true whichever it is.
#
# A sitting that stays for the return (--stay) runs steps 1 to 4 as a sign-off
# does, so the record is as complete as a sign-off leaves it: the subject's
# headline, its wait on the work, its close brief and its validating closer's
# arm, and the gates answered. Step 5 then keeps the conversation open for the
# sitting's return. The sitting's entry (converse-entry.sh) reads the stay from
# two `staying:` lines in the conversation's notes, so a restart anywhere in the
# call finds what the call did. The first, `staying: <text>`, comes before every
# other write and names no work: a restart that finds it newest finds a stay
# whose sign-off has not finished, not a hold that stands or a sitting that held
# nothing. Once steps 1 to 4 have landed, the second,
# `staying: <text> (waits on <the work>)`, names the work, and the conversation
# then waits on that work through bd's blocks edge, one onto each --waiting-on
# bead that is no gate and onto the rework --rework filed. The entry reads a
# stay as waiting or returned only when each bead that line names has its edge
# or has closed. Last, one write guarded on the holder and the status it read
# leaves it open under the sitting that holds it, so it is no longer claimed
# work, and a conversation a dismiss closed while the call ran fails that guard
# and does not stay. Gas City then sleeps the sitting once no tab is attached,
# under the template's sleep_after_idle, and wakes the same session, with its
# thread, once the work closes: the conversation is then ready work assigned to
# the sitting (gascity cmd/gc/compute_awake_set.go, the assigned-work demand and
# the idle sleep it exempts). An attach in between wakes the sitting and changes
# nothing, and it sleeps again once the tab detaches. An edge onto a bead in
# another store holds nothing, so a stay waits only on work in the
# conversation's own store, and a sitting whose work is elsewhere ends at the
# hand-off.
#
# A ruling given on a turn that does not sign off (--answer) runs steps 1 to 3
# for the gates --answer names, and step 4 when it takes the recommendation,
# and stops there: the conversation stays open under its sitting, and the
# sign-off later reads each of those gates as already cleared.
#
# Cut short (--ruled no), it writes the headline, leaves every gate the
# conversation replies to open and owed, with its reply in place for the next
# sitting, and hands the conversation back to the operator's queue with one
# write guarded on the sitting that holds it and the status it read. A
# conversation that reads closed, before that write or because a dismiss closed
# it first, stays closed. The comment on the PR stays as it is, because an open
# conversation's comment shows nothing the hand-back changes.
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
# runs (converse-rework.sh, gc-helm.sh, pr-sitting-comment.sh) are
# its siblings in the pack's assets/scripts, found through pack_script.
#
# A ruling that leaves the subject waiting on work, a bead in the subject's own
# store that is no gate, also arms the subject's validating closer
# (mol-validate-close), the waits skill's "Have a bead checked and closed once
# other work lands". Once that work lands, the deferred-dispatch pass slings the
# closer, which checks the close brief (--close-brief) against what landed and
# closes the subject or puts it to a person. The headline's edges hold the
# subject only until the work closes and send it nowhere, so the arm is what
# brings it back. The brief and the arm are written in the subject's own rig,
# whose polecat pool runs the closer, after the headline has written those
# edges, and before any gate is answered. A subject held for placement carries
# Gas City's hold:mayor, and the deferred-dispatch pass sends no arm while that
# label holds its bead, so once the arm stands the sign-off lifts every spelling
# of it there, also before any gate is answered: the ruling places the subject,
# and its closer is its next actor. A closer already armed is the one the
# ruling arms, so it is armed no second time. Once its arm has sent it, a
# ruling made while its run works the subject arms it again, and Gas City
# refuses that second launch while the run is live. No closer is armed for a
# subject that something else sends on once its wait clears: an arm of another
# dispatch, a route or an assignee, the recommendation the ruling takes, or its
# own merge or members, when it is an anchor or an epic. Nor for one in the
# city's own store, whose closer no pool runs: a person closes that one, on a
# human gate that names the work.
#
# Usage:
#   converse-signoff.sh --conversation <task> --outcome "<headline, ≤140 chars>" \
#     [--subject <id>] [--ruled yes|no] [--ruling "<one line>"] \
#     [--leave <gate> ...] [--answer <gate> ...] \
#     [--no-wait | --waiting-on <bead> ... [--close-brief "<text>"]] \
#     [--rework | --no-rework | --retire <kind> [--successor <bead>]] \
#     [--pr-anchor <bead>] [--accept [--var <key>=<value> ...]] [--stay "<text>"]
#   --outcome is the subject's headline, and the close reason the sittings card
#   falls back to. A PR the ruling leaves standing with no Approve review adds a
#   clause saying so, which counts toward the cap. --ruled defaults to `no`.
#   --ruled yes requires --ruling, the answer each gate resolves with.
#   --subject, when given, must be the bead the conversation tracks.
#   --leave (with --ruled yes) names a gate the conversation replies to that the
#   ruling leaves owed: it stays open, and its reply stays as the record that
#   this conversation took it up.
#   --answer names a gate the conversation replies to that the ruling answers
#     on a turn that does not sign off. It carries a ruling, so it takes
#     --ruling and the open-PR answer below; it releases no subject and leaves
#     every other gate as it is, so --ruled no and --leave are refused beside
#     it.
#   --rework | --no-rework | --retire <kind> (with a ruling): what the ruling
#     does to an already-published PR it reaches: the subject at
#     merge_result=pull_request, the PR whose merge this conversation holds,
#     the anchor that depends on the conversation through a blocks edge, and
#     each bead at merge_result=pull_request that a human gate the ruling
#     answers releases, while the gate is open or once this ruling's own answer
#     has closed it, so a re-run reaches the PRs an earlier attempt did. A
#     ruling that reaches one must give one of them;
#     given none, it is refused with nothing written. --rework says the PR's branch must change: the rework is filed
#     against that PR's anchor, sourced by this conversation, and refused while
#     a rework the conversation filed for another ruling is open. --no-rework
#     says the branch of each such PR stands.
#     --retire says the PR will not land: pr-dispose.sh records the disposition
#     under <kind> (re-homed, folded, fixed-upstream, duplicate or not-needed)
#     and closes the PR. Its successor is --successor, the bead that carries
#     the work now, which every kind but not-needed requires; under not-needed
#     it defaults to this conversation, the evidence that ruled the work out.
#     --rework and --retire act on one PR, the one the ruling reaches, else
#     the subject. The rework or the retirement runs in that PR's rig, after
#     one write that records the PR on the conversation (gc.ruling_consequence)
#     and before every other write, and when it does not complete nothing else
#     is written. A re-run of the same ruling with the same answer acts on the
#     PR the record names, the one --pr-anchor named or the ruling reached
#     then, even once it has closed, as a retired PR closes when pr-facts
#     consummates its disposition; a PR that reads closed has nothing left for
#     the rework or the retirement to do, so the re-run goes on without it.
#     The record also names the child a --rework filed, written once
#     converse-rework.sh reports it, and a re-run that finds that child closed
#     files no second rework and supersedes no review again: the ruling's
#     rework is done, and a stay waits on that child.
#   --pr-anchor <bead> names the PR --rework or --retire acts on when the
#     ruling reaches more than one, which it requires; every other one the
#     ruling reaches stands. A conversation owns one live rework child, so a
#     sign-off files one rework, and a second PR whose branch must change takes
#     a ruling of its own: the gate that releases it stays owed until then. A
#     re-run may name the PR an earlier attempt of the same ruling recorded,
#     even once it has closed.
#   --accept (with a ruling) says the ruling takes the subject's
#     recommendation, gc.recommended_formula, which a first reaction put to the
#     operator through a human gate under the key first-reaction that blocks
#     the subject. That gate must be one the ruling answers: the conversation
#     replies to it, and on a turn that does not sign off --answer names it. A
#     gate under the key that blocks another bead, such as an epic's member,
#     asks that bead's recommendation, which --accept does not take. Step 3
#     leaves the subject's gate to step 4, which runs gc-helm.sh accept, the
#     one writer that dispatches a recommendation, so the sitting never slings
#     it itself. Accept answers each open gate under the key on the subject, or
#     with none open the newest one, and the ruling must answer each of those.
#     Under Accept's lock and its token, a dispatch the board's Accept already
#     poured is recorded and not sent again, even when that Accept stopped
#     before recording it. Refused while another open human gate that the
#     ruling does not answer holds the subject, since the dispatch waits for
#     every gate that holds it.
#   --var <key>=<value> (with --accept, repeatable) is a var the ruling settled
#     for the recommendation's dispatch, such as mol-design-convoy's
#     design_gated=false. Accept passes each one to its sling. A dispatch an
#     earlier Accept already made keeps the vars it was made with.
#   --close-brief "<text>" (with a ruling and --waiting-on) is the claim the
#     subject's validating closer checks once the work the subject waits on
#     lands: what that landing settles on the subject, and what to check once
#     it has. It is required when the closer is armed, refused where it is not,
#     and appended to the subject's notes as its close brief, unless the
#     subject's latest close brief is already this one, held on the same work.
#   --stay "<text>" (with --ruled yes) keeps the conversation open for the
#     sitting's return instead of closing it, waiting on each --waiting-on bead
#     that is no gate and on the rework --rework files. <text> is what the
#     sitting compares that work with once it lands, what the operator agreed,
#     in one line. The conversation's notes carry it as `staying: <text>` from
#     the call's first write, and as `staying: <text> (waits on <the work>)`
#     once all but the wait has landed, so a <text> that itself ends in
#     "(waits on ...)" is refused. Each bead of that work must be in the
#     conversation's own store, and none may wait on the conversation itself,
#     as the anchor of an open PR whose merge the conversation holds does,
#     since then neither could close. None may be the subject, which the
#     conversation tracks: bd keeps one edge from a bead onto another, so the
#     conversation cannot wait on the subject too, and a sitting whose work is
#     the subject itself, sent on a formula or taking its recommendation, ends
#     at the hand-off.
#     It is refused on a conversation no sitting holds, and with nothing to
#     wait on. The sitting signs off on its return with the same call less
#     --stay, with --no-wait in place of its --waiting-on and --close-brief,
#     and with --no-rework in place of a --rework, whose child has landed. The
#     closer the stay armed already checks that work, and a --waiting-on on
#     work that has landed would arm it again once its arm has sent it.
# Exit: 0 signed off, or with --answer the named gates answered, or with --stay
#   the conversation left waiting on the work; 1 stopped short — a read
#   failed, the rework did not file or its record did not land, the PR did not
#   retire, the headline, the close brief, the closer's arm or the lift of the
#   subject's hold:mayor did not land, a gate did not close, the
#   recommendation was not taken, or the conversation did not close, hand back
#   or stay — so do NOT post the sign-off, or report the ruling as carried out;
#   repair what it names and re-run, which repeats every write it made safely;
#   2 refused before any write: usage, a conversation that is not one, a gate
#   it does not reply to, a ruling that reaches an open PR and gave
#   none of --rework, --no-rework and --retire, a --rework or --retire on a
#   ruling that reaches more than one open PR without a --pr-anchor naming one
#   of them, or an --accept with none of the subject's own recommendation gates
#   among the gates the ruling answers, a gate Accept would answer that the
#   ruling does not, no recommendation on the subject, or another open human
#   gate the ruling does not answer, or a --var without --accept or not of the
#   form <key>=<value>, or a ruling that leaves the subject waiting on work its
#   closer would check with no --close-brief, a --close-brief where no closer
#   is armed, a subject waiting on work in the city's own store, or a
#   --waiting-on that names the subject itself.
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
PR_ANSWER=""
RETIRE_KIND=""
SUCCESSOR=""
PR_PICK=""
ACCEPT=""
ACCEPT_VARS=()
WAIT=()
WAIT_IDS=""
CLOSE_BRIEF=""
STAY=""
LEAVE=()
ANSWER_GATES=()
UNDONE="NOT SIGNED OFF — do NOT post the sign-off."

HERE="$(cd "$(dirname "$0")" && pwd)"
# The one read of a bead's human gates, the read gc-helm.sh accept makes, and
# the rule of which of them still hold it. Exposes bd_human_gates and
# $HUMAN_GATE_JQ, and the die this script reports through.
# shellcheck source=bd-lib.sh
. "$HERE/bd-lib.sh" || { echo "converse-signoff: cannot source bd-lib.sh from $HERE" >&2; exit 2; }
DIE_STATUS=2
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

# pack_script <name> — <name> beside this script, in the copy of the pack that
# is running. Every script this sign-off runs is found through it. Non-zero,
# printing nothing, when the pack does not carry it.
pack_script() {
  [ -x "$HERE/$1" ] || return 1
  printf '%s' "$HERE/$1"
}

# record_action <text> — record an act this sign-off took on the conversation,
# as a comment in plain words, which the comment that shows the visit on the
# subject's PR lists among its actions. A re-run finds the comment an earlier
# attempt recorded and adds no second one. The act itself is recorded where it
# lands, so a comment that does not land is reported and the sign-off goes on.
record_action() {
  local have
  have=$(gc bd comments "$CONVERSATION" --json 2>/dev/null | grep -av '^gc bd:' | scrub \
    | jq -r --arg t "$1" 'if type == "array" then any(.[]; objects | (.text // "") == $t) else "unread" end' 2>/dev/null)
  [ "$have" = true ] && return 0
  gc bd comment "$CONVERSATION" "$1" >/dev/null 2>&1 \
    || echo "converse-signoff: the action \"$1\" was not recorded on $CONVERSATION, so the visit's comment on the PR will not list it"
}
# pr_label <anchor> — the PR an anchor carries, named as a reader of the
# subject's PR knows it: by its number when it lives in the subject's rig, whose
# repository that number links into, and only as a PR of another repository
# when it does not, so no other rig is named.
pr_label() {
  local n
  if [ "${1%%-*}" != "${SUBJECT%%-*}" ]; then printf 'a PR in another repository'; return 0; fi
  n=$(show_row "$1" | jq -r '(.metadata // {}).pr_number // "" | tostring' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) printf 'the PR of %s' "$1" ;; *) printf 'PR #%s' "$n" ;; esac
}

# The one definition of a conversation's shape. Exposes $CONVERSATION_JQ.
# shellcheck source=conversation.sh
. "$HERE/conversation.sh" || die "cannot source conversation.sh from $HERE"
# The one gc.work_outcome stamp a conversation gets before it closes, shared
# with gc-helm.sh dismiss. Exposes work_outcome_noop.
# shellcheck source=work-outcome.sh
. "$HERE/work-outcome.sh" || die "cannot source work-outcome.sh from $HERE"
# The one definition of the approval rule the merge lands on. Exposes
# $REVIEW_VERDICT_DEF.
# shellcheck source=review-verdict.sh
. "$HERE/review-verdict.sh" || die "cannot source review-verdict.sh from $HERE"
# How the pack reads the host and repository of a PR's url. Exposes pr_coords.
# shellcheck source=review-dismissal.sh
. "$HERE/review-dismissal.sh" || die "cannot source review-dismissal.sh from $HERE"
# The one definition of a dispatch path, the route or the arm that sends a bead
# on once nothing holds it. Exposes $DISPATCH_PATH_JQ.
# shellcheck source=dispatch-path.sh
. "$HERE/dispatch-path.sh" || die "cannot source dispatch-path.sh from $HERE"

while [ $# -gt 0 ]; do
  case "$1" in
    --conversation) shift; [ $# -gt 0 ] || die "--conversation needs a value"; CONVERSATION="$1" ;;
    --subject)    shift; [ $# -gt 0 ] || die "--subject needs a value"; SUBJECT="$1" ;;
    --outcome)    shift; [ $# -gt 0 ] || die "--outcome needs a value"; OUTCOME="$1" ;;
    --ruled)      shift; [ $# -gt 0 ] || die "--ruled needs yes|no"; RULED="$1" ;;
    --ruling)     shift; [ $# -gt 0 ] || die "--ruling needs a value"; RULING="$1" ;;
    --leave)      shift; [ $# -gt 0 ] || die "--leave needs a gate id"; LEAVE+=("$1") ;;
    --answer)     shift; [ $# -gt 0 ] || die "--answer needs a gate id"; ANSWER_GATES+=("$1") ;;
    --rework)     pr_answer rework ;;
    --no-rework)  pr_answer no-rework ;;
    --retire)     shift; [ $# -gt 0 ] || die "--retire needs a kind"; pr_answer retire; RETIRE_KIND="$1" ;;
    --successor)  shift; [ $# -gt 0 ] || die "--successor needs a bead id"; SUCCESSOR="$1" ;;
    --pr-anchor)  shift; [ $# -gt 0 ] || die "--pr-anchor needs a bead id"; PR_PICK="$1" ;;
    --accept)     ACCEPT=yes ;;
    --var)        shift; [ $# -gt 0 ] || die "--var needs <key>=<value>"
                  case "$1" in
                    *$'\n'*) die "--var takes <key>=<value> on one line" ;;
                    [!=]*=*) ACCEPT_VARS+=(--var "$1") ;;
                    *)       die "--var takes <key>=<value>, not '$1'" ;;
                  esac ;;
    --no-wait)    WAIT+=(--no-wait) ;;
    --waiting-on) shift; [ $# -gt 0 ] || die "--waiting-on needs a bead id"; WAIT+=(--waiting-on "$1"); WAIT_IDS="${WAIT_IDS:+$WAIT_IDS }$1" ;;
    --close-brief) shift; [ -n "${1:-}" ] || die "--close-brief needs the brief's text"; CLOSE_BRIEF="$1" ;;
    --stay)       shift; [ -n "${1:-}" ] || die "--stay needs what the sitting compares the work with once it lands, in one line"; STAY="$1" ;;
    -h|--help)    sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            die "unknown argument '$1'" ;;
  esac
  shift
done

[ -n "$CONVERSATION" ] || die "--conversation is required"
[ -n "$OUTCOME" ] || die "--outcome is required"
[ "${#ACCEPT_VARS[@]}" -eq 0 ] || [ -n "$ACCEPT" ] \
  || die "--var requires --accept: it is a var of the recommendation's dispatch"
case "${RULED:-no}" in yes|no) ;; *) die "--ruled must be yes or no" ;; esac
ANSWERING=""
if [ "${#ANSWER_GATES[@]}" -gt 0 ]; then
  ANSWERING=yes
  [ "${RULED:-yes}" = yes ] || die "--answer carries a ruling, so it cannot be --ruled no"
  [ -n "$RULING" ] || die "--answer requires --ruling (the answer each gate it names resolves with)"
  [ "${#LEAVE[@]}" -eq 0 ] || die "--answer resolves only the gates it names, so --leave has nothing to leave"
  RULED=yes
  UNDONE="NOT ANSWERED — do NOT tell the operator the ruling is carried out."
fi
RULED="${RULED:-no}"
if [ "$RULED" = yes ]; then
  [ -n "$RULING" ] || die "--ruled yes requires --ruling (the answer each gate resolves with)"
else
  [ -z "$PR_ANSWER" ] || die "--rework, --no-rework and --retire require a ruling (they answer what it does to an open PR)"
  [ "${#LEAVE[@]}" -eq 0 ] || die "--leave requires --ruled yes: a cut-short sign-off leaves every gate open"
  [ -z "$ACCEPT" ] || die "--accept requires a ruling (--ruled yes, or --answer): it takes the recommendation the operator ruled to take"
fi
if [ -n "$CLOSE_BRIEF" ]; then
  [ "$RULED" = yes ] || die "--close-brief requires a ruling (--ruled yes, or --answer): it is the claim the subject's validating closer checks once the work the ruling sent lands"
  [ -n "$WAIT_IDS" ] || die "--close-brief requires --waiting-on <the work>: it is the claim the subject's validating closer checks once that work lands"
fi
if [ -n "$STAY" ]; then
  [ "$RULED" = yes ] && [ -z "$ANSWERING" ] \
    || die "--stay keeps the conversation open in place of a sign-off's close, so it takes --ruled yes and no --answer"
  case "$STAY" in *$'\n'*) die "--stay takes one line" ;; esac
  case "$STAY" in *" (waits on "*")") die "--stay ends in \"(waits on ...)\", as the line that names the stay's work does, so the sitting's entry would read it as that line; end it otherwise" ;; esac
  [ -n "$WAIT_IDS" ] || [ "$PR_ANSWER" = rework ] \
    || die "--stay waits on the work this ruling sent, so it needs --waiting-on <the work> or --rework; nothing was written"
  UNDONE="NOT STAYING — do NOT post the hand-back as a sitting that stays."
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
# A --waiting-on never names the subject. The subject waits on nothing of its
# own, and the conversation, which tracks it, cannot wait on it either: bd keeps
# one edge from a bead onto another, so a stay's blocks edge onto the subject
# would be refused at the last write, after every gate is answered. A ruling
# whose work is the subject itself, sent on a formula or taking its
# recommendation, signs off with --no-wait, and a sitting that would stay for
# that work ends at the hand-off.
case " $WAIT_IDS " in
  *" $SUBJECT "*)
    die "--waiting-on $SUBJECT names the subject itself, which waits on nothing of its own${STAY:+, and conversation $CONVERSATION cannot wait on it, because it tracks $SUBJECT and bd keeps one edge from a bead onto another}; nothing was written. A ruling that sends the subject itself as the work, or takes its recommendation, signs off with --no-wait${STAY:+ and without --stay, so the sitting ends at the hand-off}" ;;
esac
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
# for each open PR it reaches: the subject when it is one, the PR whose merge
# the conversation holds, and each bead at merge_result=pull_request that a
# human gate the ruling answers releases, such as an epic member whose gate the
# epic's sitting answers, or the other PR behind a gate about two. A
# conversation about an open PR holds its merge through the anchor's blocks
# edge onto the conversation (gc-helm.sh, conversation_hold_merge), so the
# beads that depend on the conversation are that PR's anchor, which a
# conversation on the PR's review reaches through nothing else. The edge
# stays once the conversation closes, so a re-run reaches the same PR. Such a
# gate is one still open, or one this ruling's own
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
  HELD=$(gc bd dep list "$CONVERSATION" --direction=up --type blocks --json 2>/dev/null | grep -av '^gc bd:' | scrub \
    | jq -ce 'if type == "array" then [ .[] | objects ] else error("unread") end' 2>/dev/null) \
    || stopped "the beads that depend on conversation $CONVERSATION could not be read, and an open PR whose merge it holds could be among them; nothing was written"
  for b in $(printf '%s' "$HELD" | jq -r '.[] | select(((.status // "") | tostring | ascii_downcase) != "closed") | (.id // "") | select(. != "")'); do
    reaches_pr "$b" && continue
    BROW=$(show_row "$b") \
      || stopped "$b, which depends on conversation $CONVERSATION, could not be read to tell whether it is an open PR whose merge the conversation holds; nothing was written"
    [ "$(printf '%s' "$BROW" | jq -r '.metadata.merge_result // ""')" = pull_request ] && PR_ANCHORS+=("$b")
  done
  for g in $TO_ANSWER; do
    printf '%s\n' "${LEAVE[@]+"${LEAVE[@]}"}" | grep -qxF -- "$g" && continue
    printf '%s' "$GATES_JSON" | jq -e --arg g "$g" --arg a "$ANSWER" "$HUMAN_GATE_JQ"'any(.[]; .id == $g
        and (open_human_gate("") or (human_gate and (.close_reason // "") == $a)))' >/dev/null 2>&1 || continue
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
  die "this ruling reaches $PR_LIST at merge_result=pull_request, as its subject, as the PR whose merge this conversation holds, or as a bead a gate it answers releases, so it must say what it does to each open PR; nothing was written. Re-run with --rework to file the rework a branch needs, --no-rework if the branch stands, or --retire <kind> if the PR will not land, and with --pr-anchor <bead> to name the one --rework or --retire acts on when it reaches more than one"
fi
# --rework and --retire act on one open PR: the one the ruling reaches, the one
# --pr-anchor names when it reaches more than one, or else the subject, which
# converse-rework.sh and pr-dispose.sh refuse unless it is an open PR. A
# conversation owns one live rework child (rework-child.sh), so one sign-off
# files one rework, and each other open PR the ruling reaches stands under it,
# as --no-rework says of every one.
#
# The PR a ruling's rework or retirement acts on is recorded on the conversation
# (gc.ruling_consequence, keyed by the ruling's answer) before it acts, because
# what it acts on can close in between: pr-facts consummates a retirement by
# closing the retired PR's anchor, and a closed bead is no open PR the ruling
# reaches. A re-run of the same ruling with the same answer recovers that PR
# from the record, so it never falls back to the subject or acts on another PR,
# and a recorded PR that reads closed has nothing left for the answer to do. A
# re-run that answers differently is a new answer, and the record does not
# bind it.
#
# A rework's record also names the child it filed, once converse-rework.sh
# reports it, because the store cannot name it later: a conversation's rework
# children all carry its id as source_ruling_bead, and the ruling a child
# carries as its rejection_reason is cleared once its worker resumes the branch
# (work-setup.sh). The writer adopts only a live child, so
# a re-run once the child has closed would file a second rework on the same
# ruling, block the PR again and supersede the reviews of the reworked branch.
# So a recorded child that has closed is this ruling's rework done: the re-run
# files nothing and supersedes nothing, and a stay waits on that child, which
# returns it at once. A stop after the child is filed and before its record
# lands leaves the record without it, and the re-run then adopts the child
# while it is live. The child's writer, rework-child.sh, is retired by the
# deletion plan, so it gains no record of the ruling.
CONSEQUENCE_JQ='def consequences: ((.metadata // {})["gc.ruling_consequence"] // {})
  | (if type == "string" then (fromjson? // {}) else . end) | if type == "object" then . else {} end;'
RECORDED_ON=""
RECORDED_CHILD=""
case "$PR_ANSWER" in
  rework|retire)
    RECORDED_ON=$(printf '%s' "$CONV_ROW" | jq -r --arg a "$ANSWER" --arg act "$PR_ANSWER" "$CONSEQUENCE_JQ"'
      consequences | .[$a] // {} | select(((.act // "") | tostring) == $act) | (.anchor // "") | tostring' 2>/dev/null)
    RECORDED_CHILD=$(printf '%s' "$CONV_ROW" | jq -r --arg a "$ANSWER" --arg act "$PR_ANSWER" "$CONSEQUENCE_JQ"'
      consequences | .[$a] // {} | select(((.act // "") | tostring) == $act) | (.child // "") | tostring' 2>/dev/null) ;;
esac
PR_TARGET=""
TARGET_CLOSED=""
CHILD_CLOSED=""
STANDS=()
case "$PR_ANSWER" in
  rework|retire)
    if [ -n "$PR_PICK" ]; then
      reaches_pr "$PR_PICK" || [ "$PR_PICK" = "$RECORDED_ON" ] \
        || die "--pr-anchor $PR_PICK is no open PR this ruling reaches (${PR_LIST:-none}); nothing was written"
      PR_TARGET="$PR_PICK"
    elif [ -n "$RECORDED_ON" ]; then
      PR_TARGET="$RECORDED_ON"
      echo "an earlier attempt of this ruling recorded $PR_TARGET as the PR its --$PR_ANSWER acts on; acting on it again"
    elif [ "${#PR_ANCHORS[@]}" -gt 1 ]; then
      die "this ruling reaches more than one open PR ($PR_LIST), and --$PR_ANSWER acts on one; nothing was written. Name it with --pr-anchor <bead>, and each other one stands under this ruling. A conversation files one live rework, so a PR whose own branch must change or which must retire as well takes a ruling of its own: leave the gate that releases it owed, with --leave or out of --answer, until that ruling is carried out"
    else
      PR_TARGET="${PR_ANCHORS[0]:-$SUBJECT}"
    fi
    for p in "${PR_ANCHORS[@]+"${PR_ANCHORS[@]}"}"; do [ "$p" = "$PR_TARGET" ] || STANDS+=("$p"); done
    if [ -n "$RECORDED_ON" ] && [ "$PR_TARGET" = "$RECORDED_ON" ]; then
      TROW=$(show_row "$PR_TARGET") \
        || stopped "$PR_TARGET, the PR an earlier attempt of this ruling recorded for its --$PR_ANSWER, could not be read to tell whether it is still open; nothing was written"
      [ "$(printf '%s' "$TROW" | jq -r '(.status // "") | ascii_downcase')" = closed ] && TARGET_CLOSED=yes
      # The recorded rework matters while its PR is open, which it would rework
      # again, and to a stay, which waits on it whatever the PR's state.
      if [ -n "$RECORDED_CHILD" ] && { [ -z "$TARGET_CLOSED" ] || [ -n "$STAY" ]; }; then
        CHROW=$(show_row "$RECORDED_CHILD") \
          || stopped "$RECORDED_CHILD, the rework an earlier attempt of this ruling filed on $PR_TARGET, could not be read to tell whether it has closed; nothing was written"
        printf '%s' "$CHROW" | jq -e --arg c "$CONVERSATION" '((.metadata // {}).source_ruling_bead // "") == $c' >/dev/null 2>&1 \
          || stopped "$RECORDED_CHILD, which the record on conversation $CONVERSATION names as this ruling's rework on $PR_TARGET, does not read as this conversation's rework; nothing was written"
        [ "$(printf '%s' "$CHROW" | jq -r '(.status // "") | ascii_downcase')" = closed ] && CHILD_CLOSED=yes
      fi
    fi ;;
  no-rework)
    STANDS=("${PR_ANCHORS[@]+"${PR_ANCHORS[@]}"}")
    [ "${#STANDS[@]}" -gt 0 ] || STANDS=("$SUBJECT") ;;
esac
# The rework or the retirement acts in the rig of the PR it acts on, which can
# be another rig than the conversation's when a gate in another store releases
# it. converse-rework.sh and rework-child.sh find the rework pool, file and
# deduplicate the child, prove its blocks edge onto the anchor and sling it in
# the store and rig GC_RIG names; pr-dispose.sh reads the anchor there; and the
# review lanes read their check index from the checkout. So the consequence
# runs with GC_RIG, GC_RIG_ROOT and the working directory all pinned to that
# rig, resolved from the PR's id prefix by bead-store.sh, the one resolver of
# a bead's store. The conversation stays the rework's provenance.
TARGET_RIG=""
TARGET_PATH=""
if [ -n "$PR_TARGET" ] && [ -z "$TARGET_CLOSED" ]; then
  BS=$(pack_script bead-store.sh) \
    || stopped "no bead-store.sh beside $0, so the rig that holds $PR_TARGET, where its --$PR_ANSWER acts, could not be resolved; nothing was written"
  TARGET_RIG=$("$BS" "$PR_TARGET" 2>/dev/null) && TARGET_PATH=$("$BS" --path "$PR_TARGET" 2>/dev/null) && [ -d "$TARGET_PATH" ] \
    || stopped "the rig that holds $PR_TARGET could not be resolved from its id ('bead-store.sh $PR_TARGET' says why), and its --$PR_ANSWER acts in that rig's store, pool and checkout; nothing was written"
fi
# in_target_rig <cmd> [args...] — run <cmd> in the rig of the PR the
# consequence acts on.
in_target_rig() { ( cd "$TARGET_PATH" && GC_RIG="$TARGET_RIG" GC_RIG_ROOT="$TARGET_PATH" "$@" ); }
# --accept takes the subject's recommendation through the gate that put it to
# the operator: a human gate under the key first-reaction that blocks the
# subject. A gate under the key that blocks another bead, such as a member of
# the epic a sitting is about, asks that bead's recommendation, and Accept on
# the subject never answers it. The gate must be one the ruling answers, so the
# conversation's reply on it records which conversation took it up. Step 3
# leaves it, and step 4 hands it to Accept's writer, which answers the gates it
# chooses on the subject: each open one under the key, or with none open the
# newest, whose acceptance an earlier Accept left unfinished. The sign-off
# answers no gate its conversation does not reply to, so each gate Accept
# answers must be one this ruling answers. Accept dispatches only once no other
# open human gate holds the subject, because a formula's sling reads no blocks
# edge, so a gate this ruling does not answer refuses the take here, before any
# write, rather than after step 3 has answered the others. One listing of the
# subject's human gates answers each of these checks.
REC_GATES=""
REC_FORMULA=""
if [ -n "$ACCEPT" ]; then
  SUBJECT_GATES=$(bd_human_gates "$SUBJECT") \
    || stopped "the human gates that hold $SUBJECT could not be read, and its recommendation is taken only through its own gate, once no gate but its own holds it; nothing was written"
  ANSWERED_GATES=""
  for g in $TO_ANSWER; do
    printf '%s\n' "${LEAVE[@]+"${LEAVE[@]}"}" | grep -qxF -- "$g" && continue
    ANSWERED_GATES="${ANSWERED_GATES:+$ANSWERED_GATES }$g"
    printf '%s' "$SUBJECT_GATES" | jq -e --arg g "$g" 'any(.[]; .id == $g and ((.await_id // "") | tostring) == "first-reaction")' >/dev/null 2>&1 \
      && REC_GATES="${REC_GATES:+$REC_GATES }$g"
  done
  [ -n "$REC_GATES" ] \
    || die "--accept takes $SUBJECT's recommendation through the gate that puts it to the operator, a human gate under the key first-reaction that blocks $SUBJECT, and no gate this ruling answers is that gate; nothing was written. A gate under the key that blocks another bead asks that bead's recommendation, which Accept on $SUBJECT does not take. Reply to $SUBJECT's own gate first${ANSWERING:+ and name it with --answer}, then re-run"
  ACCEPT_ANSWERS=$(printf '%s' "$SUBJECT_GATES" | jq -r "$HUMAN_GATE_JQ"'
      [ .[] | select(((.await_id // "") | tostring) == "first-reaction") ] as $rec
      | [ $rec[] | select(open_human_gate("first-reaction")) | .id ] as $open
      | (if ($open | length) > 0 then $open else [ $rec | sort_by(.created_at // "") | last // empty | .id ] end)
      | join(" ")')
  UNANSWERED=""
  for g in $ACCEPT_ANSWERS; do
    case " $ANSWERED_GATES " in *" $g "*) ;; *) UNANSWERED="${UNANSWERED:+$UNANSWERED }$g" ;; esac
  done
  [ -z "$UNANSWERED" ] \
    || die "Accept takes $SUBJECT's recommendation by answering $UNANSWERED, which this ruling does not answer, and the sign-off answers no gate its conversation does not reply to; nothing was written. Reply to it${ANSWERING:+ and name it with --answer}, then re-run"
  REC_FORMULA=$(printf '%s' "$SUBJECT_ROW" | jq -r '(.metadata // {})["gc.recommended_formula"] // "" | tostring')
  REC_SENT=$(printf '%s' "$SUBJECT_ROW" | jq -r '(.metadata // {})["gc.recommended_formula_dispatched"] // "" | tostring')
  [ -n "$REC_FORMULA$REC_SENT" ] \
    || die "--accept takes $SUBJECT's recommendation, and $SUBJECT carries none (no gc.recommended_formula); nothing was written. Answer its gate without --accept"
  REC_FORMULA="${REC_FORMULA:-$REC_SENT}"
  OTHERS=$(printf '%s' "$SUBJECT_GATES" | jq -r --arg answered "$ANSWERED_GATES" "$HUMAN_GATE_JQ"'
      ($answered | split(" ")) as $a
      | [ .[] | select(open_human_gate("")) | select(((.await_id // "") | tostring) != "first-reaction")
              | select(((.id // "") | tostring) as $i | ($a | index($i)) == null)
              | "\(.id) (\(.title // "untitled"))" ] | join("; ")')
  [ -z "$OTHERS" ] \
    || die "$SUBJECT's recommendation is dispatched only once no other human gate holds it, and $OTHERS still holds it, which this ruling does not answer; nothing was written. Answer that gate in the same ruling once the operator rules on it, or leave the recommendation's gate owed until it is cleared, when Accept on the board takes the recommendation"
fi
# The subject's validating closer. A ruling that leaves the subject waiting on
# work arms it, so the subject is checked and closed once that work lands.
# Work is a wait in the subject's own store that is no gate: a gate is what a
# person owes, and a wait in another store is no edge, which the headline
# refuses. Each wait is read here, with the other reads, because one that does
# not read could be work. Something else sends the subject on once its wait
# clears when the ruling takes its recommendation, when it is an epic, whose
# members carry it, or an anchor (a merge_result), which the refinery closes
# on its merge, and when it is assigned, has a dispatch path (a route, or an
# arm of another dispatch, as dispatch-path.sh defines one), or is at a status
# other than open, which is set deliberately. Then no closer is armed. The
# closer's own arm is no other dispatch path. A closer an earlier attempt armed
# is this one, so a re-run arms it no second time. Once the arm has sent the
# closer, the arm is gone, so a ruling made while the closer's run works the
# subject arms it again. Gas City refuses that second launch while the run is
# live.
CLOSER_WAITS=""
CLOSER_RIG=""
CLOSER_PATH=""
CLOSER_ARMED=""
if [ "$RULED" = yes ]; then
  for w in $WAIT_IDS; do
    [ "$w" != "$SUBJECT" ] && [ "${w%%-*}" = "${SUBJECT%%-*}" ] || continue
    WROW=$(show_row "$w") \
      || stopped "$w, which this ruling leaves $SUBJECT waiting on, could not be read to tell whether it is work whose landing $SUBJECT's validating closer checks; nothing was written"
    printf '%s' "$WROW" | jq -e '(.issue_type // "") == "gate"' >/dev/null 2>&1 \
      || CLOSER_WAITS="${CLOSER_WAITS:+$CLOSER_WAITS }$w"
  done
fi
if [ -n "$CLOSER_WAITS" ]; then
  ELSEWHERE=$(printf '%s' "$SUBJECT_ROW" | jq -r --arg accept "$ACCEPT" "$DISPATCH_PATH_JQ"'(.metadata // {}) as $m
    | def v($k): ($m[$k] // "") | tostring;
    (if v("gc.dispatch_when_ready_args") | contains("mol-validate-close")
       then .metadata |= del(.["gc.dispatch_when_ready"]) else . end) as $other
    | ($other.metadata // {}) as $o
    | if $accept != "" then "takes its recommendation, whose dispatch carries it"
    elif (.issue_type // "") == "epic" then "is an epic, whose members carry it"
    elif v("merge_result") != "" then "is an anchor (merge_result=\(v("merge_result"))), which the refinery closes on its merge"
    elif ((.assignee // "") | tostring) != "" then "is assigned to \(.assignee), whose hook offers it once its wait clears"
    elif ($other | has_dispatch_path)
      then "has a dispatch path (\([ dispatch_path_keys[] as $k | select({metadata: {($k): $o[$k]}} | has_dispatch_path) | "\($k)=\($o[$k])" ] | join(", "))), which sends it on once its wait clears"
    elif ((.status // "") | ascii_downcase) != "open" then "is \(.status // "of no status"), which is set deliberately"
    else "" end' 2>/dev/null) \
    || stopped "$SUBJECT could not be read to tell whether anything but its validating closer sends it on once its work lands; nothing was written"
  if [ -n "$ELSEWHERE" ]; then
    [ -z "$CLOSE_BRIEF" ] \
      || die "--close-brief arms $SUBJECT's validating closer, and $SUBJECT $ELSEWHERE, so no closer is armed for it; nothing was written. Drop --close-brief to leave it to that, or, when the ruling sends it to the closer instead, withdraw that first (the converse-settle step's block) and re-run"
    echo "no validating closer is armed for $SUBJECT: it $ELSEWHERE"
    CLOSER_WAITS=""
  else
    # The closer runs in the subject's own rig: its pool claims the sling, and
    # its deferred-dispatch pass sends the arm from its store. The rig map names
    # that rig from the subject's prefix. The city's own store has no polecat
    # pool and no such pass, so a person closes a subject there.
    RM=$(pack_script rig-map.sh) \
      || stopped "no rig-map.sh beside $0, so the rig whose pool runs $SUBJECT's validating closer could not be resolved; nothing was written"
    MAP=$("$RM" 2>&1) \
      || stopped "the rig map did not read ($(printf '%s' "$MAP" | tr '\n' ' ')), so the rig whose pool runs $SUBJECT's validating closer could not be resolved; nothing was written"
    CLOSER_ROW=$(printf '%s' "$MAP" | scrub | jq -c --arg p "${SUBJECT%%-*}" '[ .rigs[]? | objects | select(.prefix == $p) ] | if length == 1 then .[0] else empty end' 2>/dev/null)
    [ -n "$CLOSER_ROW" ] \
      || stopped "no one rig in the rig map carries the prefix ${SUBJECT%%-*}, so the rig whose pool runs $SUBJECT's validating closer could not be resolved; nothing was written"
    if printf '%s' "$CLOSER_ROW" | jq -e '.hq == true' >/dev/null 2>&1; then
      die "$SUBJECT is in the city's own store, where no polecat pool runs a validating closer, so nothing would check it once $CLOSER_WAITS lands; nothing was written. A person closes it then: file a human gate on $SUBJECT that asks them to close it once $CLOSER_WAITS lands (the waits skill, \"Wait on a person\"), and sign off with --waiting-on <that gate> in place of --waiting-on $CLOSER_WAITS, and no --close-brief"
    fi
    [ -n "$CLOSE_BRIEF" ] \
      || die "this ruling leaves $SUBJECT waiting on work ($CLOSER_WAITS), and nothing else sends it on once that work lands, so the sign-off arms its validating closer, which checks a close brief against what landed; nothing was written. Re-run with --close-brief \"<what that work's landing settles on $SUBJECT, and what to check once it has>\""
    CLOSER_RIG=$(printf '%s' "$CLOSER_ROW" | jq -r '.name // "" | tostring')
    CLOSER_PATH=$(printf '%s' "$CLOSER_ROW" | jq -r '.path // "" | tostring')
    [ -n "$CLOSER_RIG" ] && [ -n "$CLOSER_PATH" ] \
      || stopped "the rig map names no rig and path for the prefix ${SUBJECT%%-*}, so the rig whose pool runs $SUBJECT's validating closer could not be resolved; nothing was written"
    printf '%s' "$SUBJECT_ROW" | jq -e '((.metadata // {})["gc.dispatch_when_ready_args"] // "") | tostring | contains("mol-validate-close")' >/dev/null 2>&1 \
      && CLOSER_ARMED=yes
  fi
fi
[ -z "$CLOSE_BRIEF" ] || [ -n "$CLOSER_RIG" ] \
  || die "--close-brief is the claim $SUBJECT's validating closer checks once the work it waits on lands, and none of --waiting-on${WAIT_IDS:+ ($WAIT_IDS)} is work in $SUBJECT's own store, a bead that is no gate, so no closer is armed; nothing was written. Drop --close-brief"
HELM=$(pack_script gc-helm.sh) || stopped "no gc-helm.sh beside $0, so the subject's headline cannot be written; nothing was written"

# gh_bounded <args...> — gh, stopped after 20 seconds. A call stopped that way exits
# non-zero, as one that failed does. A host with neither timeout tool makes no call
# and exits non-zero too, so every PR left standing reads as one whose reviews did
# not read, an approved one included: the sign-off exists to get a ruling's writes
# down, and an unbounded call ahead of them could hold them.
gh_bounded() {
  local t
  for t in timeout gtimeout; do
    command -v "$t" >/dev/null 2>&1 || continue
    "$t" -k 5 20 gh "$@" </dev/null
    return
  done
  return 1
}
# pr_approval <pr-url> <pr-number> <bring_current_lifted_at> — what the rule the
# merge lands on finds, as a word and the login it names for a standing request
# for changes: `approved` when an approval stands and no request does, `vetoed
# <login>` when both do, and `owed [<login>]` when no approval stands. Non-zero,
# printing nothing, when the reviews do not read.
pr_approval() {
  local self reviews
  pr_coords "$1" "$2" || return 1
  self=$(gh_bounded api --hostname "$PR_HOST" user --jq '.login' 2>/dev/null) && [ -n "$self" ] || return 1
  reviews=$(gh_bounded api --hostname "$PR_HOST" --paginate "repos/$PR_REPO/pulls/$2/reviews?per_page=100" --jq '.[]' 2>/dev/null) || return 1
  printf '%s' "$reviews" | scrub | jq -sr --arg self "$self" --arg lifted "$3" "$REVIEW_VERDICT_DEF"'
    review_verdict($self; $lifted)
    | "\(if .approver == "" then "owed" elif .veto == "" then "approved" else "vetoed" end) \(.veto)"' 2>/dev/null
}
APPROVE_OWED=()
APPROVE_TELL=()
for p in "${STANDS[@]+"${STANDS[@]}"}"; do
  reaches_pr "$p" || continue
  PROW=$(show_row "$p") \
    || stopped "$p, an open PR this ruling leaves standing, could not be read to tell whether its merge still needs an Approve review; nothing was written"
  P_URL=$(printf '%s' "$PROW" | jq -r '.metadata.pr_url // .metadata.existing_pr // ""')
  P_NUM=$(printf '%s' "$PROW" | jq -r '.metadata.pr_number // "" | tostring')
  [ -n "$P_NUM" ] || P_NUM=$(printf '%s' "$P_URL" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p')
  P_LIFTED=$(printf '%s' "$PROW" | jq -r '.metadata.bring_current_lifted_at // ""')
  P_READ=$(pr_approval "$P_URL" "$P_NUM" "$P_LIFTED") || P_READ=""
  P_VETO="${P_READ#* }"
  P_READ="${P_READ%% *}"
  [ "$P_READ" != approved ] || continue
  P_NAME="PR #$P_NUM"
  [ -n "$P_NUM" ] || P_NAME="$p's PR"
  case "$P_READ" in
    vetoed)
      P_SAYS="An approval stands on $P_NAME, and a request for changes from $P_VETO holds its merge until $P_VETO approves or the request is dismissed. This ruling does neither." ;;
    owed)
      APPROVE_OWED+=("$P_NAME")
      P_SAYS="$P_NAME still needs the operator's Approve review on GitHub before it can merge, and this ruling does not count as one."
      [ -z "$P_VETO" ] || P_SAYS="$P_SAYS A request for changes from $P_VETO also stands: the operator's Approve replaces it only if $P_VETO is their own account, and otherwise it holds the merge until $P_VETO approves or the request is dismissed." ;;
    *)
      APPROVE_OWED+=("$P_NAME")
      P_SAYS="The reviews of $P_NAME could not be read, so its merge may still need the operator's Approve review on GitHub, and this ruling does not count as one." ;;
  esac
  APPROVE_TELL+=("$P_SAYS Tell them so in plain words${P_URL:+ and link it: $P_URL}")
done
APPROVE_CLAUSE=""
case "${#APPROVE_OWED[@]}" in
  0) ;;
  1) APPROVE_CLAUSE="${APPROVE_OWED[0]} still needs your Approve on GitHub" ;;
  *) APPROVE_CLAUSE="${#APPROVE_OWED[@]} PRs still need your Approve on GitHub" ;;
esac
[ -z "$APPROVE_CLAUSE" ] || OUTCOME="${OUTCOME%.}; $APPROVE_CLAUSE"
tell_approval() {
  local line
  for line in "${APPROVE_TELL[@]+"${APPROVE_TELL[@]}"}"; do echo "$line"; done
}

# take_recommendation — step 4: hand the recommendation's gate to gc-helm.sh
# accept, the writer the board's Accept runs, and read back what it left. Accept
# exits 0 once it has dispatched the formula, or recorded a dispatch that an
# earlier Accept poured under its token. Any other exit is read off the gates
# and the subject. A recommendation already dispatched and withdrawn was taken,
# and an answer that reached the gate first stands, as in step 3. Anything
# else stops the sign-off here, before the conversation closes, so a re-run
# takes the recommendation once Accept can.
take_recommendation() {
  local out rc g row st why other="" open=""
  out=$("$HELM" accept "$SUBJECT" --conversation "$CONVERSATION" --reason "$RULING" \
    "${ACCEPT_VARS[@]+"${ACCEPT_VARS[@]}"}" 2>&1); rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then
    echo "took the recommendation: $REC_FORMULA at $SUBJECT, through Accept"
    record_action "Took the recommendation and started its work."
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
    return 0
  fi
  if [ -z "$open" ] && show_row "$SUBJECT" | jq -e '((.metadata // {})["gc.recommended_formula"] // "") == ""
      and ((.metadata // {})["gc.recommended_formula_dispatched"] // "") != ""' >/dev/null 2>&1; then
    echo "the recommendation was already taken: an Accept dispatched $REC_FORMULA at $SUBJECT and recorded it${ACCEPT_VARS[*]:+. That dispatch keeps the vars it was made with, so the --var given here does not reach it}"
    return 0
  fi
  stopped "the recommendation was not taken: gc-helm.sh accept exited $rc, and its output above says why${open:+, and its gate $open is still open}. The conversation is not closed. Repair what Accept names, then re-run, which finishes an acceptance Accept left unfinished without dispatching it twice"
}

# waits_on_conversation <bead> — the bead whose edge onto the conversation ends
# a path from <bead> to it, a path bd would close into a cycle with the
# conversation's edge onto <bead>, and refuse. bd's cycle check walks every
# blocks, conditional-blocks and parent-child edge from <bead>, whatever the
# status of the beads it passes (beads 7ef2fd05e,
# issueops.cycleReachabilityQuery), and only its own store's edges, so a bead
# in another store ends a path. The walk reads one level at a time through
# `gc bd list --id`. Prints that bead and returns 0 when a path reaches the
# conversation, 1 when none does, 2 when a level did not read as the beads it
# asked for, and 3 when the walk went past 50 levels, the depth bd's dep tree
# stops at.
waits_on_conversation() {
  local frontier="$1" seen=" $1 " level=0 json out
  while [ -n "$frontier" ]; do
    level=$((level + 1))
    [ "$level" -le 50 ] || return 3
    json=$(gc bd list --id "$(printf '%s' "$frontier" | tr ' ' ',')" --all --json 2>/dev/null) || return 2
    out=$(printf '%s\n' "$json" | grep -av '^gc bd:' | scrub | jq -r --arg want "$frontier" --arg seen "$seen" \
        --arg c "$CONVERSATION" --arg p "${CONVERSATION%%-*}-" '
      if type != "array" or ([ .[] | (.id // "") | tostring ] | sort) != ($want | split(" ") | sort)
      then error("not the beads asked for") else . end
      | [ .[] | (.id | tostring) as $from | .dependencies[]? | objects
          | select(((.type // .dependency_type) // "") as $t
              | $t == "blocks" or $t == "conditional-blocks" or $t == "parent-child")
          | {from: $from, on: ((.depends_on_id // "") | tostring)}
          | select(.on | startswith($p)) ] as $edges
      | ([ $edges[] | select(.on == $c) | .from ] | first) as $hit
      | if $hit != null then "HIT " + $hit
        else "NEXT " + ([ $edges[] | .on | select(. as $o | $seen | contains(" " + $o + " ") | not) ] | unique | join(" "))
        end' 2>/dev/null) || return 2
    case "$out" in
      "HIT "*) printf '%s' "${out#HIT }"; return 0 ;;
      "NEXT "*) frontier="${out#NEXT }"; seen="$seen$frontier " ;;
      *) return 2 ;;
    esac
  done
  return 1
}

# The work a sitting that stays waits on: each --waiting-on bead that is no
# gate, read now, and the rework step 1 files. A stay keeps the conversation for
# the sitting that holds it, so one in the operator's queue has none to stay.
# An edge from the conversation onto a bead in another store holds nothing, and
# a conversation that waited on nothing would read as ready work at once and
# wake its sitting before the work landed, so each bead carries the
# conversation's own prefix. A bead that waits on the conversation already,
# itself or through the beads it waits on, as the anchor of an open PR whose
# merge the conversation holds does, would close a cycle that bd refuses, and
# neither bead could close, so it is refused here, before any write.
STAY_ON=""
if [ -n "$STAY" ]; then
  if [ "$HOLDER" = human ] || { [ "$CONV_STATUS" != in_progress ] && [ "$CONV_STATUS" != open ]; }; then
    die "--stay keeps conversation $CONVERSATION open for the sitting that holds it, and it reads ${CONV_STATUS:-of no status} under ${HOLDER:-no one}; nothing was written"
  fi
  for w in $WAIT_IDS; do
    [ "$w" != "$CONVERSATION" ] || die "--stay waits on the work this ruling sent, and $w is this conversation; nothing was written"
    [ "${w%%-*}" = "${CONVERSATION%%-*}" ] \
      || die "--stay would make conversation $CONVERSATION wait on $w, in another store, where its edge holds nothing; nothing was written. A sitting whose work is in another rig ends at the hand-off: sign off without --stay"
    WROW=$(show_row "$w") \
      || stopped "$w, which this sitting would stay for, could not be read to tell whether it is work or a gate; nothing was written"
    printf '%s' "$WROW" | jq -e '(.issue_type // "") == "gate"' >/dev/null 2>&1 && continue
    HOLDS_RC=0
    HOLDS_IT=$(waits_on_conversation "$w") || HOLDS_RC=$?
    case "$HOLDS_RC" in
      0)
        if [ "$HOLDS_IT" = "$w" ]; then
          THROUGH="$w already waits on $CONVERSATION"
        else
          THROUGH="$w already waits on $CONVERSATION through $HOLDS_IT, which waits on it"
        fi
        die "--stay would make conversation $CONVERSATION wait on $w, and $THROUGH, as the anchor of an open PR whose merge the conversation holds does, so neither could close; nothing was written. When the operator wants that PR to land first, lift the hold (gc bd dep remove $HOLDS_IT $CONVERSATION, the converse-hold skill) and re-run; otherwise sign off without --stay" ;;
      1) ;;
      3) stopped "the beads $w waits on lead more than 50 levels deep, so the sign-off could not tell whether one of them waits on conversation $CONVERSATION, which would make bd refuse the stay's edge; nothing was written. Sign off without --stay" ;;
      *) stopped "the beads $w waits on could not be read to tell whether one of them waits on conversation $CONVERSATION, which would make bd refuse the stay's edge; nothing was written" ;;
    esac
    STAY_ON="${STAY_ON:+$STAY_ON }$w"
  done
  [ -n "$STAY_ON" ] || [ "$PR_ANSWER" = rework ] \
    || die "--stay waits on the work this ruling sent, and each --waiting-on is a gate; nothing was written"
fi

# A stay records itself before anything else is written, as `staying: <text>`,
# which names no work yet. Every later write of the stay follows it, so the
# sitting's entry reads a stay that stops anywhere as one, never as a hold that
# stands or as a sitting that held nothing, which would send it to frame the
# ruling again or to the premise re-check. A re-run keeps that line while it is
# newest, because the call that wrote it has not finished, and the re-run
# finishes it. A line that names work ends a call that reached step 5, this one
# run again or an earlier stay with the same text, and nothing in it says
# which: it names no ruling, and a --rework stay does not know all its own work
# until step 1 files the child. Taken as this call's own, an earlier stay's
# line would leave a call that stops before step 5 reading as that stay's wait
# or return. So any other call records itself again, and step 5 names its work
# again, which on a re-run of a stay that had named its work repeats two lines
# of the same record.
if [ -n "$STAY" ]; then
  STAY_MARK="staying: $STAY"
  NEWEST_MARK=$(printf '%s' "$CONV_ROW" | jq -r '[ (.notes // "") | split("\n")[] | select(startswith("holding:") or startswith("staying:")) ] | last // ""')
  if [ "$NEWEST_MARK" != "$STAY_MARK" ]; then
    gc bd update "$CONVERSATION" --append-notes "$STAY_MARK" >/dev/null 2>&1 \
      || stopped "the store refused the staying: line that records the stay on conversation $CONVERSATION before its other writes; nothing was written"
  fi
fi

# 1. What the ruling does to an open PR. --rework files the fix unit a review
# verdict files, sourced by this conversation, and returns every review lane to
# unreviewed; the child's blocks edge holds the merge. --retire records the
# disposition and closes the PR, so there is nothing left to merge. Either one
# runs in the PR's own rig, after the record of the PR it acts on and before
# any gate this sitting answers is resolved. One that does not complete stops
# here with nothing else written, and a re-run adopts a child an earlier
# attempt filed, or finds the PR it closed.
CONSEQUENCE=""
# The PR the answer acts on is recorded first, so an attempt that stops at any
# later write leaves its re-run that PR to act on. A record the store refuses
# stops the sign-off with nothing else written, because the act on the PR
# cannot be undone.
if [ -n "$PR_TARGET" ] && [ "$RECORDED_ON" != "$PR_TARGET" ]; then
  RECORD=$(printf '%s' "$CONV_ROW" | jq -c --arg a "$ANSWER" --arg act "$PR_ANSWER" --arg t "$PR_TARGET" "$CONSEQUENCE_JQ"'
    consequences + {($a): {act: $act, anchor: $t}}' 2>/dev/null)
  [ -n "$RECORD" ] && gc bd update "$CONVERSATION" --set-metadata "gc.ruling_consequence=$RECORD" >/dev/null 2>&1 \
    || stopped "the PR this ruling's --$PR_ANSWER acts on ($PR_TARGET) could not be recorded on conversation $CONVERSATION (gc.ruling_consequence), and a re-run needs it once that PR closes; nothing else was written${STAY:+ but the staying: line that records the stay}"
fi
ACTING="$PR_ANSWER"
if [ -n "$TARGET_CLOSED" ]; then
  echo "$PR_TARGET, the PR an earlier attempt of this ruling recorded for its --$PR_ANSWER, reads closed, so the $PR_ANSWER has nothing left to act on"
  CONSEQUENCE="found $PR_TARGET closed, so the $PR_ANSWER had nothing left to act on"
  ACTING=""
elif [ -n "$CHILD_CLOSED" ]; then
  echo "$RECORDED_CHILD, the rework an earlier attempt of this ruling filed on $PR_TARGET, has closed, so the rework has nothing left to do"
  CONSEQUENCE="found the rework $RECORDED_CHILD closed, so the rework had nothing left to do"
  ACTING=""
fi
CHILD=""
case "$ACTING" in
  rework)
    CR=$(pack_script converse-rework.sh)
    if [ -z "$CR" ]; then
      PR_OUT="no converse-rework.sh beside $0"
    elif PR_OUT=$(in_target_rig "$CR" --anchor "$PR_TARGET" --ruling-bead "$CONVERSATION" --ruling "$RULING" 2>&1); then
      echo "$PR_OUT"
      CONSEQUENCE="filed ruling-driven rework on $PR_TARGET"
    fi
    if [ -z "$CONSEQUENCE" ]; then
      echo "REWORK NOT COMPLETE on $PR_TARGET: $PR_OUT"
      echo "Nothing else was written${STAY:+ but the staying: line that records the stay}: no headline, gate answer or close. $UNDONE"
      echo "Repair the cause and re-run. If $PR_TARGET is not an open PR, file the ruling's consequence as work, then re-run without --rework and with --waiting-on <that bead>. If it cannot be repaired, raise it in the thread."
      exit 1
    fi
    # The child the writer names on its last line
    # ("<child> <route> <filed|adopted|in-flight>") is recorded under the
    # ruling before anything else is written, so a re-run once it has closed
    # finds it there. A refused record stops here, and a re-run while the
    # child is open adopts it and records it.
    read -r CHILD _ <<EOF
$(printf '%s\n' "$PR_OUT" | tail -n 1)
EOF
    case "$CHILD" in -*|*-|*[!A-Za-z0-9._-]*) CHILD="" ;; *-*) ;; *) CHILD="" ;; esac
    if [ -n "$CHILD" ] && [ "$CHILD" != "$RECORDED_CHILD" ]; then
      RECORD=$(printf '%s' "$CONV_ROW" | jq -c --arg a "$ANSWER" --arg t "$PR_TARGET" --arg c "$CHILD" "$CONSEQUENCE_JQ"'
        consequences + {($a): {act: "rework", anchor: $t, child: $c}}' 2>/dev/null)
      [ -n "$RECORD" ] && gc bd update "$CONVERSATION" --set-metadata "gc.ruling_consequence=$RECORD" >/dev/null 2>&1 \
        || stopped "rework $CHILD is filed on $PR_TARGET, but the store refused its record on conversation $CONVERSATION (gc.ruling_consequence), which a re-run reads once $CHILD has closed so that it files no second rework; nothing else was written${STAY:+ but the staying: line that records the stay}. Re-run while $CHILD is open, which adopts it"
    fi
    record_action "Sent $(pr_label "$PR_TARGET") back for rework." ;;
  retire)
    PD=$(pack_script pr-dispose.sh)
    if [ -z "$PD" ]; then
      PR_OUT="no pr-dispose.sh beside $0"
    elif PR_OUT=$(in_target_rig "$PD" --anchor "$PR_TARGET" --successor "$SUCCESSOR" --kind "$RETIRE_KIND" --note "$RULING" 2>&1); then
      echo "$PR_OUT"
      CONSEQUENCE="retired the PR of $PR_TARGET ($RETIRE_KIND, successor $SUCCESSOR)"
      record_action "Retired $(pr_label "$PR_TARGET")."
    fi
    if [ -z "$CONSEQUENCE" ]; then
      echo "RETIREMENT NOT COMPLETE on $PR_TARGET: $PR_OUT"
      echo "Nothing else was written${STAY:+ but the staying: line that records the stay}: no headline, gate answer or close, so each gate the conversation replies to still holds the merge. $UNDONE"
      echo "Repair the cause and re-run; pr-dispose.sh keeps a disposition an earlier attempt recorded and closes the PR it left open. If it cannot be repaired, raise it in the thread."
      exit 1
    fi ;;
esac
for p in "${STANDS[@]+"${STANDS[@]}"}"; do echo "the ruling leaves the branch of $p as it stands"; done

# A stay waits on this ruling's rework, read back as this conversation's rework
# in the conversation's own store: the child step 1 filed, or the one an
# earlier attempt filed that has closed, which returns the stay at once.
[ -z "$CHILD_CLOSED" ] || CHILD="$RECORDED_CHILD"
if [ -n "$STAY" ] && { [ "$ACTING" = rework ] || [ -n "$CHILD_CLOSED" ]; }; then
  CROW=""
  if [ -n "$CHILD" ] && [ "${CHILD%%-*}" = "${CONVERSATION%%-*}" ]; then
    CROW=$(show_row "$CHILD") || CROW=""
  fi
  printf '%s' "$CROW" | jq -e --arg c "$CONVERSATION" '((.metadata // {}).source_ruling_bead // "") == $c' >/dev/null 2>&1 \
    || stopped "the rework is filed, but ${CHILD:-its child} could not be read as this conversation's rework in its own store, so the conversation has nothing to wait on and does not stay. Sign off without --stay to end at the hand-off; it adopts the same rework"
  case " $STAY_ON " in *" $CHILD "*) ;; *) STAY_ON="${STAY_ON:+$STAY_ON }$CHILD" ;; esac
fi
[ -z "$STAY" ] || [ -n "$STAY_ON" ] \
  || stopped "the PR this ruling's rework acts on reads closed and filed no rework, and no --waiting-on names other work, so the conversation has nothing to wait on and does not stay. Sign off without --stay"

# 2. The headline. An ARRAY, not a string: this city runs zsh, which does not
# word-split an unquoted parameter, so "${WAIT[@]}" is what passes each flag as
# its own argument, and nothing when it is empty. The resolves, the release and
# the close below cannot be undone, so they wait on takeaway's exit.
"$HELM" takeaway "$SUBJECT" "$OUTCOME" --by converse "${WAIT[@]+"${WAIT[@]}"}" \
  || stopped "gc-helm.sh takeaway did not finish on $SUBJECT, and its message above says which write it could not make${APPROVE_CLAUSE:+. It carries \"; $APPROVE_CLAUSE\" after --outcome, which counts toward the cap, so a shorter --outcome makes room}; no gate was resolved and the conversation is not closed"
# The subject's validating closer, once the headline's edges hold the subject
# on the work: first the close brief the closer checks, then its arm, then the
# lift of a hold that would keep the arm from sending it, all in the subject's
# own rig and all before any gate is answered, so a write that does not land
# stops the sign-off with every gate still open. A re-run finds the brief and
# the arm an earlier attempt wrote, and writes neither again.
# The closer checks the latest close brief in the subject's notes: the last
# `## Close brief (` heading and the lines after it, up to the next heading.
# The notes deferred-dispatch.sh appends end it too: the arm's own note
# follows the brief, and the record's clearing follows that once the closer
# is sent. So the brief counts as written only when that heading is held on
# these same waits and its lines are this brief. The same words anywhere
# else, such as in an older brief or in a sitting's notes, do not count,
# because the closer would then check the older claim.
if [ -n "$CLOSER_RIG" ]; then
  if printf '%s' "$SUBJECT_ROW" | jq -e --arg b "$CLOSE_BRIEF" --arg w "$CLOSER_WAITS" '
      def rtrim: sub("[[:space:]]+$"; "");
      ((.notes // "") | tostring | split("\n")) as $l
      | ([ range(0; $l | length) | select($l[.] | startswith("## Close brief (")) ] | last) as $i
      | if $i == null then false
        else ([ range($i + 1; $l | length) | select($l[.] | startswith("## ") or startswith("deferred-dispatch: ")) ]
                | first // ($l | length)) as $end
          | ((($l[$i] | capture("^## Close brief \\(held on (?<w>[^ ]+), [^ ]+\\)$") | .w) // "")
              | split(",") | map(select(. != "")) | unique) == ($w | split(" ") | map(select(. != "")) | unique)
            and (($l[$i + 1:$end] | join("\n") | rtrim) == ($b | rtrim))
        end' >/dev/null 2>&1; then
    echo "$SUBJECT's latest close brief is already this one, held on $CLOSER_WAITS"
  else
    gc bd update "$SUBJECT" --db "$CLOSER_PATH/.beads" --append-notes "## Close brief (held on $(printf '%s' "$CLOSER_WAITS" | tr ' ' ','), $(date -u +%Y-%m-%dT%H:%M:%SZ))
$CLOSE_BRIEF" >/dev/null 2>&1 \
      || stopped "the store refused the close brief on $SUBJECT, which its validating closer checks, so the closer was not armed; the headline is written, no gate was resolved and the conversation is not closed"
  fi
  if [ -n "$CLOSER_ARMED" ]; then
    echo "$SUBJECT's validating closer is already armed"
  else
    DD=$(pack_script deferred-dispatch.sh) \
      || stopped "no deferred-dispatch.sh beside $0, so $SUBJECT's validating closer was not armed; the headline and the close brief are written, no gate was resolved and the conversation is not closed"
    ( cd "$CLOSER_PATH" && GC_RIG="$CLOSER_RIG" GC_RIG_ROOT="$CLOSER_PATH" "$DD" arm "$SUBJECT" --db "$CLOSER_PATH/.beads" \
        --target "$CLOSER_RIG/gc-toolkit.polecat" --sling-arg --on --sling-arg mol-validate-close \
        --reason "waits for $CLOSER_WAITS, the work conversation $CONVERSATION's ruling sent; the validating closer checks it once that lands" ) \
      || stopped "$SUBJECT's validating closer was not armed, and deferred-dispatch.sh's message above says why; the headline and the close brief are written, no gate was resolved and the conversation is not closed"
  fi
  # A subject held for placement carries Gas City's hold:mayor, and the
  # deferred-dispatch pass sends no arm while a hold label holds its bead, so
  # the closer would never be sent. The ruling places the subject: it waits on
  # the work, and the closer is its next actor. So once the arm stands, the
  # sign-off lifts the hold in the subject's own rig, before any gate is
  # answered, in one write that removes each spelling of hold:mayor the subject
  # carries, because Gas City reads the label trimmed and in any case and bd
  # removes a label only by its exact text. The labels are read here, after
  # the arm, so the lift removes the spellings the subject carries now. A
  # re-run finds the brief and the arm, and lifts a hold an earlier attempt
  # could not.
  HOLD_ROW=$(show_row "$SUBJECT") \
    && HOLD_SP=$(printf '%s' "$HOLD_ROW" | jq -r "$DISPATCH_PATH_JQ"'dispatch_hold_spellings("hold:mayor")[]' 2>/dev/null) \
    || stopped "$SUBJECT's labels could not be read to tell whether hold:mayor keeps its validating closer from being sent; the headline, the close brief and the arm are written, no gate was resolved and the conversation is not closed"
  if [ -n "$HOLD_SP" ]; then
    HOLD_LIFT=()
    while IFS= read -r sp; do
      [ -z "$sp" ] || HOLD_LIFT+=(--remove-label "$sp")
    done <<EOF
$HOLD_SP
EOF
    gc bd update "$SUBJECT" --db "$CLOSER_PATH/.beads" "${HOLD_LIFT[@]}" >/dev/null 2>&1 \
      || stopped "the store refused the write that lifts hold:mayor from $SUBJECT, and the deferred-dispatch pass sends no arm while that label holds it, so its validating closer would never be sent; the headline, the close brief and the arm are written, no gate was resolved and the conversation is not closed. A re-run lifts it, and so does this write by hand: gc bd update $SUBJECT --db $(printf '%q' "$CLOSER_PATH/.beads")$(printf ' %q' "${HOLD_LIFT[@]}")"
    echo "lifted hold:mayor from $SUBJECT, so its validating closer is sent once $CLOSER_WAITS lands"
  fi
  record_action "Arranged the check that closes this once the work it waits on lands."
fi

if [ "$RULED" = yes ]; then
  # 3. The gates the ruling answers: those --answer names, or else each one the
  # conversation replies to. A reply onto a bead that is no human gate holds
  # nothing to resolve. The recommendation's gate, when the ruling takes the
  # recommendation, is step 4's to answer through Accept.
  UNCLOSED=""
  for g in $TO_ANSWER; do
    case " $REC_GATES " in *" $g "*) continue ;; esac
    if printf '%s\n' "${LEAVE[@]+"${LEAVE[@]}"}" | grep -qxF -- "$g"; then
      echo "gate $g stays open and owed: the ruling leaves it, and this conversation's reply stays on it"
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
    fi
  done
  [ -z "$UNCLOSED" ] || stopped "the ruling did not close $UNCLOSED; the conversation is not closed, so a re-run resolves it"
  # The ruling is the answer those gates now carry, recorded in the sitting's
  # own words among the visit's actions.
  record_action "Ruled: $(printf '%s' "$ANSWER" | sed 's/^ruled: *//')"
  if [ -n "$ANSWERING" ]; then
    [ -z "$ACCEPT" ] || take_recommendation
    echo "ANSWERED $TO_ANSWER for conversation $CONVERSATION on $SUBJECT; the conversation stays open, and its sign-off reads each of those gates as already cleared"
    tell_approval
    exit 0
  fi

  # 4. The recommendation.
  [ -z "$ACCEPT" ] || take_recommendation

  if [ -n "$STAY" ]; then
    # 5. Stay for the return. The `staying:` line that names the work comes
    # first, once everything but the wait has landed, so the sitting's entry
    # finds which work the stay waits on and tells a stay that stopped before
    # its edges from one whose work is out or has returned. The edges onto
    # that work come next, before the status write, so the conversation is
    # never open and assigned with nothing holding it, which Gas City would
    # read as ready work and wake the sitting for at once.
    # The guarded write last drops the claim and its lease and keeps the
    # assignee, so the sitting idle-sleeps once no tab is attached and the
    # work's close makes the conversation its ready work, which wakes it. On a
    # conversation that already reads open, as on a re-run or a second stay
    # from a sitting woken early, the write changes nothing, and its guard is
    # what finds a dismiss that closed the conversation while this call ran.
    STAY_LINE="staying: $STAY (waits on $(printf '%s' "$STAY_ON" | sed 's/ /, /g'))"
    gc bd update "$CONVERSATION" --append-notes "$STAY_LINE" >/dev/null 2>&1 \
      || stopped "the store refused the staying: line that names the work conversation $CONVERSATION waits on, which the sitting's entry reads to tell a stay that stopped short from one whose work is out; every gate above is answered, the conversation is not yet left to wait, and a re-run writes it"
    for w in $STAY_ON; do
      gc bd dep add "$CONVERSATION" "$w" --type blocks >/dev/null 2>&1 \
        || stopped "the store refused the edge that makes conversation $CONVERSATION wait on $w, so it would not wake its sitting when $w closes; every gate above is answered, its staying: line names the work, the conversation is not yet left to wait, and a re-run writes the edge"
    done
    STAY_RC=0
    gc bd update "$CONVERSATION" --if-assignee "$HOLDER" --if-status "$CONV_STATUS" --status open >/dev/null 2>&1 || STAY_RC=$?
    case "$STAY_RC" in
      0) ;;
      13)
        BACK=$(show_row "$CONVERSATION") || BACK=""
        case "$(printf '%s' "$BACK" | jq -r '"\(.assignee // "")/\((.status // "") | ascii_downcase)"' 2>/dev/null)" in
          "$HOLDER/open") ;;
          */closed) stopped "conversation $CONVERSATION was closed while this call ran, by a dismiss or another sign-off, so nothing stays" ;;
          *) stopped "conversation $CONVERSATION moved while this call ran, so it was not left waiting for its sitting's return; re-run to stay from where it is now" ;;
        esac ;;
      *) stopped "the store refused the write that leaves conversation $CONVERSATION waiting under $HOLDER (gc bd update exited $STAY_RC); its edges and its staying: line are written, and a re-run makes the write" ;;
    esac
    record_action "Kept this conversation open until the work it sent lands, to compare it then with what was agreed."
    # A stay whose only work is a rework that has closed already is ready at
    # once, so nothing wakes its sitting: the sitting turns to the return now.
    if [ -n "$CHILD_CLOSED" ] && [ "$STAY_ON" = "$RECORDED_CHILD" ]; then
      echo "STAYING conversation $CONVERSATION on $SUBJECT: it waits on $STAY_ON under $HOLDER, which has closed already, so the work is back. Run the entry again, which reads it as returned, and carry out the return"
    else
      echo "STAYING conversation $CONVERSATION on $SUBJECT: it waits on $STAY_ON under $HOLDER. Its sitting sleeps once no tab is attached and wakes with this thread when that work closes"
    fi
    tell_approval
    exit 0
  fi

  # 5. Close the conversation. The work-record gate the close runs wants
  # gc.work_outcome, stamped in a write of its own so it never decides whether
  # the conversation closes. The sitting holds the conversation, so a plain
  # close is the holder's own; --force covers an actor bd does not read as its
  # holder. The PR comment drawn after it cannot be taken back, so a close the
  # store refuses both ways stops the sign-off.
  if [ "$CONV_STATUS" != closed ]; then
    work_outcome_noop "$CONVERSATION" gc bd
    gc bd close "$CONVERSATION" --reason "$OUTCOME" >/dev/null 2>&1 \
      || gc bd close "$CONVERSATION" --reason "$OUTCOME" --force >/dev/null 2>&1 \
      || stopped "the store refused the close of conversation $CONVERSATION; every gate above is answered, and a re-run closes it"
  fi
  SIGNED=closed
else
  # Cut short: the gates stay open and owed, with their replies in place, and
  # the conversation goes back to the operator's queue with one write guarded
  # on the sitting that holds it and on the status read above, which drops the
  # claim's lease. A conversation already in the queue has no sitting to hand
  # it back from. One that reads closed has ended, by a dismiss or an earlier
  # sign-off, and bd's close keeps its assignee, so a write guarded on the
  # holder alone would reopen it: it stays closed. A dismiss that lands between
  # the read and the write fails the status guard (exit 13), and a read then
  # finds the conversation closed. A guard that misses because another writer
  # already put the conversation back in the queue leaves it where this
  # hand-back puts it.
  BACK_AT=""
  if [ "$CONV_STATUS" = closed ]; then
    echo "conversation $CONVERSATION already reads closed, so it stays closed and is not handed back"
  elif [ "$HOLDER" = human ]; then
    BACK_AT="human/open"
  else
    BACK_RC=0
    gc bd update "$CONVERSATION" --if-assignee "$HOLDER" --if-status "$CONV_STATUS" --assignee human --status open >/dev/null 2>&1 || BACK_RC=$?
    case "$BACK_RC" in
      0) BACK_AT="human/open" ;;
      13)
        BACK=$(show_row "$CONVERSATION") || BACK=""
        BACK_AT=$(printf '%s' "$BACK" | jq -r '"\(.assignee // "")/\((.status // "") | ascii_downcase)"' 2>/dev/null)
        case "$BACK_AT" in
          human/open) ;;
          */closed) echo "conversation $CONVERSATION was closed while this sign-off ran, so it stays closed and is not handed back" ;;
          *) stopped "conversation $CONVERSATION moved while this sign-off ran (it reads ${BACK_AT:-unreadable}), so its hand-back from $HOLDER was not written; re-run to hand it back from where it is now" ;;
        esac ;;
      *) stopped "the store refused the hand-back of conversation $CONVERSATION from $HOLDER to the operator's queue (gc bd update exited $BACK_RC); re-run once the store answers" ;;
    esac
  fi
  SIGNED="already closed"
  [ "$BACK_AT" != human/open ] || SIGNED="back in the operator's queue"
fi

# 6. The comment that shows the visit on the subject's PR, drawn again from
# the conversation now that it reads closed, so it shows the conclusion and the
# actions. Best effort and update-only: a conversation whose sitting named no
# topic has no comment, and the hand-back recorded after this sign-off draws it
# again with the closing words. A cut-short conversation is open, and its
# comment shows nothing the hand-back changed.
if [ "$SIGNED" = closed ]; then
  REMINDER=$(pack_script pr-sitting-comment.sh) && { "$REMINDER" refresh --sitting "$CONVERSATION" || true; }
fi
echo "SIGNED OFF conversation $CONVERSATION on $SUBJECT ($SIGNED)"
tell_approval
