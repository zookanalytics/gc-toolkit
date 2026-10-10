#!/usr/bin/env bash
# converse-signoff.sh — step 7 of the converse loop: write the durable trace a
# finished sitting owes to the subject, and discharge the hold, BEFORE the
# sign-off is posted and the visit is closed.
#
# It stamps the closing takeaway on the subject, reads it back, and discharges
# the demands the hold filed. A conversation wait gates the VISIT, an explicit
# merge hold gates the anchor; a sitting may have filed either or both, and each
# is discharged. One question decides each discharge: did the decision this hold
# waited on land here (--ruled yes) or not (--ruled no)?
#   --ruled yes: the operator ruled in this thread. Each gate is RESOLVED (a
#     pre-gate demand is closed on the same terms), and where the subject still
#     reads `held` it is released back to the pool that owns it.
#   --ruled no:  cut short, or the question outlived the sitting. The wait is
#     consolidated onto the SUBJECT — a demand gating the VISIT is closed and
#     re-stated there — so it outlives the visit's close, the liveness sweep
#     (keyed on gc.demand_for=<subject>) re-offers the next sitting, and on a PR
#     anchor the merge waits; a pre-PR subject stays `held`.
# `held` follows this sitting's outcome, not the state read off the subject,
# because the cut-short exit runs this discharge on a subject still waiting.
#
# Every store read the discharge depends on runs before the first write and
# fails closed: the visit, the open demands, the demand the visit's
# gc.hold_demand names, and on a ruling the subject's lifecycle state. A read
# that fails is not an empty answer. Taken as one, a failed demand listing finds
# no demand, the discharge skips a gate that still blocks, and the sitting signs
# off while the hold stands. For the same reason a demand counts as discharged
# only once it reads back closed.
#
# What is waiting on the subject is the caller's to state: one --waiting-on per
# bead it ROUTED work into, --no-wait when it settled the subject and nothing is
# waiting, and NEITHER where the subject is parked for a person. The writers
# (gc-helm.sh, lifecycle.sh) are SEARCHED for on the candidate roots.
#
# Usage:
#   converse-signoff.sh --visit <id> --outcome "<takeaway, ≤140 chars>" \
#     [--subject <id>] [--ruled yes|no] \
#     [--no-wait | --waiting-on <bead> ...] \
#     [--ruling "<one line>"] [--still-owed "<≤140 chars>"] [--route <rig>/<agent>|human]
#   --outcome is required. --ruled defaults to `no`. --ruled yes requires
#   --ruling and --route; --ruled no requires --still-owed. --subject defaults
#   to the subject the visit records (its tracks edge, else its
#   gc.continuation_group stamp); with neither, the sign-off refuses and writes
#   nothing.
# Exit: 0 the trace is written and the hold discharged — the sign-off may
#   proceed, once any write it reports as failed is repaired; 1 it stopped
#   short because a read failed, a demand did not close, or a cut-short wait did
#   not re-state — do NOT post the sign-off or close the visit; repair what it
#   names and re-run, which repeats every write it made safely; 2 usage, or no
#   subject resolves — nothing written.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

VISIT=""
SUBJECT="${SUBJECT:-}"
OUTCOME=""
RULED=no
RULING=""
STILL_OWED=""
ROUTE=""
WAIT=()

die() { echo "converse-signoff: $1" >&2; exit 2; }
# stopped <why> — refuse the sign-off (exit 1). Whatever ran before it is a write
# a re-run repeats safely, and a demand it did not discharge still stands for the
# re-run to find.
stopped() {
  echo "converse-signoff: $1" >&2
  echo "NOT SIGNED OFF — do NOT post the sign-off or close the visit. Repair what is named above, then re-run this sign-off."
  exit 1
}
# show_one <id> — print `gc bd show <id> --json`, scrubbed, when it reads as an
# array whose first row is <id>. Returns 3 when the store answers that <id> does
# not exist, and 1 on any other failure. The exit status is read on its own: a
# pipeline answers with its last command's, and scrub succeeds whatever gc did.
# gc exits non-zero on a missing id but still prints its not-found object, so
# the output is classified before the status is trusted.
show_one() {
  local raw rc
  raw=$(gc bd show "$1" --json); rc=$?
  raw=$(printf '%s' "$raw" | scrub)
  if [ "$rc" -eq 0 ] && printf '%s' "$raw" | jq -e --arg id "$1" 'type == "array" and ((.[0].id // "") == $id)' >/dev/null 2>&1; then
    printf '%s' "$raw"
    return 0
  fi
  printf '%s' "$raw" | jq -e 'type == "object" and ((.error // "") | test("no issues found"))' >/dev/null 2>&1 && return 3
  return 1
}
# demand_closed <id> — the demand reads back closed. A read that fails is no
# proof of a close, so it answers as still open.
demand_closed() {
  local got
  got=$(show_one "$1") || return 1
  printf '%s' "$got" | jq -e '((.[0].status // "") | ascii_downcase) == "closed"' >/dev/null 2>&1
}

# The one definition of what subject a visit covers (its tracks edge, the
# gc.continuation_group stamp as fallback), shared with converse-fold.sh and the
# sweeps. Exposes $VISIT_IDENTITY_JQ.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=visit-identity.sh
. "$HERE/visit-identity.sh" || die "cannot source visit-identity.sh from $HERE"

while [ $# -gt 0 ]; do
  case "$1" in
    --visit)      shift; [ $# -gt 0 ] || die "--visit needs a value"; VISIT="$1" ;;
    --subject)    shift; [ $# -gt 0 ] || die "--subject needs a value"; SUBJECT="$1" ;;
    --outcome)    shift; [ $# -gt 0 ] || die "--outcome needs a value"; OUTCOME="$1" ;;
    --ruled)      shift; [ $# -gt 0 ] || die "--ruled needs yes|no"; RULED="$1" ;;
    --ruling)     shift; [ $# -gt 0 ] || die "--ruling needs a value"; RULING="$1" ;;
    --still-owed) shift; [ $# -gt 0 ] || die "--still-owed needs a value"; STILL_OWED="$1" ;;
    --route)      shift; [ $# -gt 0 ] || die "--route needs a value"; ROUTE="$1" ;;
    --no-wait)    WAIT+=(--no-wait) ;;
    --waiting-on) shift; [ $# -gt 0 ] || die "--waiting-on needs a bead id"; WAIT+=(--waiting-on "$1") ;;
    -h|--help)    sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            die "unknown argument '$1'" ;;
  esac
  shift
done

[ -n "$VISIT" ]   || die "--visit is required"
[ -n "$OUTCOME" ] || die "--outcome is required"
case "$RULED" in yes|no) ;; *) die "--ruled must be yes or no" ;; esac
if [ "$RULED" = yes ]; then
  [ -n "$RULING" ] || die "--ruled yes requires --ruling (the reason the gate resolves with)"
  [ -n "$ROUTE" ]  || die "--ruled yes requires --route (where the subject is released to)"
else
  [ -n "$STILL_OWED" ] || die "--ruled no requires --still-owed (what the subject still waits on)"
fi
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v gc >/dev/null 2>&1 || die "gc is required"

# The visit names the subject, this sitting's topic and the demand its hold
# filed. Read as empty, the topic would widen the discharge to a sibling
# sitting's demand on a shared bucket, so a visit that does not read stops here.
V=$(show_one "$VISIT"); VRC=$?
case "$VRC" in
  0) ;;
  3) stopped "visit $VISIT does not exist in the store gc bd answers from; nothing was written" ;;
  *) stopped "visit $VISIT could not be read, and its subject, topic and gc.hold_demand decide what this sign-off discharges; nothing was written" ;;
esac
# Every write below lands on the subject or the visit. The caller passes the
# subject step 1 resolved, and the visit records it twice, as its tracks edge
# and as its gc.continuation_group stamp, so an absent --subject is recovered
# here the way converse-fold.sh recovers it. With neither, every write would
# land on an empty bead id, so it refuses before any write.
if [ -z "$SUBJECT" ]; then
  SUBJECT=$(printf '%s' "$V" | jq -r "$VISIT_IDENTITY_JQ"'(.[0] // {}) | visit_subject' 2>/dev/null || true)
fi
[ -n "$SUBJECT" ] || die "no subject: --subject was not given and visit $VISIT names none (no tracks edge, no gc.continuation_group stamp); nothing was written — re-run with --subject <id>"
# The topic scopes the discharge to THIS sitting's demands, so a sibling sitting
# on a shared standing-scope bucket (same subject, distinct escalation_key)
# keeps its own demand: this sign-off neither resolves it nor overwrites its
# operator question with a re-state. escalation_key is that per-sitting
# discriminator, empty on an ordinary visit — which keeps the pre-topic
# behaviour. An array so an empty topic expands to no argument under zsh.
TOPIC=$(printf '%s' "$V" | jq -r '.[0].metadata.escalation_key // ""')
DEMAND_TOPIC=()
[ -n "$TOPIC" ] && DEMAND_TOPIC=(--topic "$TOPIC")
# The hold to discharge. A conversation wait gates the VISIT (the default — a
# conversation does not freeze its subject) and an explicit merge hold gates the
# SUBJECT; a sitting may have filed either or both. --include-gates: a demand is
# a human gate, hidden from `bd list` by default, so the discharge would
# otherwise never find it. The listing's exit status is read on its own line and
# its output must parse as an array, because an unread listing is no proof that
# no demand stands.
HELD_DEMAND=$(printf '%s' "$V" | jq -r '.[0].metadata["gc.hold_demand"] // ""')
DEMANDS_JSON=$(gc bd list --status=open,in_progress --include-gates --json --limit=0)
DEMANDS_RC=$?
DEMANDS_JSON=$(printf '%s' "$DEMANDS_JSON" | scrub)
if [ "$DEMANDS_RC" -ne 0 ] || ! printf '%s' "$DEMANDS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  stopped "the open-demand listing could not be read (gc bd list exited $DEMANDS_RC), so nothing shows whether this sitting's demands still stand; nothing was written"
fi
# The demand the hold filed is read directly, by the id converse-hold stamped on
# the visit as gc.hold_demand, so it is found in whatever live status it stands
# in; the listing holds open and in_progress rows only. The listing still serves
# what carries no stamp: an opt-in merge hold, a hold that predates the stamp,
# and an orphan the await_id recovers. A stamped demand that no longer exists
# blocks nothing, and one that does not read stops the sign-off as the listing
# does.
if [ -n "$HELD_DEMAND" ]; then
  HELD_JSON=$(show_one "$HELD_DEMAND"); HELD_RC=$?
  case "$HELD_RC" in
    0) MERGED=$(printf '%s' "$DEMANDS_JSON" | jq -c --argjson h "$HELD_JSON" '
           ($h[0]) as $d
           | if ((($d.status // "") | ascii_downcase) == "closed") or any(.[]; .id == $d.id)
             then . else . + [$d] end' 2>/dev/null)
       [ -n "$MERGED" ] || stopped "the stamped demand $HELD_DEMAND read, but could not be joined to the open demands; nothing was written"
       DEMANDS_JSON="$MERGED" ;;
    3) : ;;
    *) stopped "the demand $HELD_DEMAND, which gc.hold_demand on $VISIT names, could not be read; nothing was written" ;;
  esac
fi
# A ruling releases a subject that still reads `held`, so the state is read
# here, with the other reads. lifecycle.sh exits 2 when the subject does not
# read, an answer that cannot say whether it is held. Any other refusal (an
# undeclared state, no gctk binary) answers as not held, the side that leaves
# the bead visibly waiting on a person.
LC=""
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/lifecycle.sh" ] && { LC="$cand/assets/scripts/lifecycle.sh"; break; }
done
SUBJECT_STATE=""
if [ "$RULED" = yes ] && [ -n "$LC" ]; then
  SUBJECT_STATE=$("$LC" state "$SUBJECT" 2>/dev/null)
  [ $? -ne 2 ] || stopped "the lifecycle state of $SUBJECT could not be read, so this ruling cannot tell whether to release it from held; nothing was written"
fi
HELM=""
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/gc-helm.sh" ] && { HELM="$cand/assets/scripts/gc-helm.sh"; break; }
done
[ -n "$HELM" ] || echo "NO TAKEAWAY WRITER on any candidate root — say so in the sign-off; the subject carries no trace of this sitting"
# What is waiting on $SUBJECT now that this sitting is over. Three shapes,
# exactly one true, and this sitting is the last reader that can tell them
# apart: one --waiting-on per bead it ROUTED work into; --no-wait when it
# settled the subject and nothing is waiting; EMPTY only where the subject
# is parked for a person, which doctor/check-wait-is-an-edge reports as a
# wait nothing re-asks, because that is what it is.
# An ARRAY, not a string: this city runs zsh, which does not word-split an
# unquoted parameter, so a populated string arrives as ONE argument and the
# call dies with `unknown flag` on exactly the sittings the flag exists for.
# "${WAIT[@]}" expands to nothing when empty and to one argument per element
# otherwise, in both bash and zsh.
"$HELM" takeaway "$SUBJECT" "$OUTCOME" --by converse "${WAIT[@]}" \
  || echo "TAKEAWAY FAILED on $SUBJECT — re-run it before closing; nothing below records this sitting"
# Read the takeaway back on the SUBJECT. The gc.outcome check below proves the
# VISIT stamp and says nothing about the subject, so a takeaway that died still
# closes clean — the unstamped close this block exists to prevent, one bead
# over.
gc bd show "$SUBJECT" --json | scrub \
  | jq -e '.[0].metadata["gc.takeaway"] // empty' >/dev/null \
  || echo "NO TAKEAWAY ON $SUBJECT — do not close until it lands"
# The live, unassigned demand THIS sitting filed on a given bead, or empty. Under
# a standing scope sibling sittings share the subject and each holds its own
# topic-keyed demand on it, so a first match on gc.demand_for alone would resolve
# or re-state a sibling's operator question. converse-hold stamps the
# conversation demand's id as gc.hold_demand on the visit, so that exact demand
# wins wherever it gates this bead. Any other demand (the merge hold, which
# carries no stamp, or a hold predating the stamp) is matched under this
# sitting's topic, and the topic-encoding await_id recovers an orphan whose
# gc.demand_for stamp never landed. An empty topic keeps the pre-topic match on
# the bead alone. An empty target would match every bead that carries no
# gc.demand_for at all, so it returns nothing.
demand_on() {
  [ -n "$1" ] || { printf ''; return; }
  local aid
  if [ -n "$TOPIC" ]; then aid="gc-demand:$1:$TOPIC"; else aid="gc-demand:$1"; fi
  printf '%s' "$DEMANDS_JSON" \
    | jq -r --arg i "$1" --arg d "$HELD_DEMAND" --arg t "$TOPIC" --arg aid "$aid" '
        [ .[]? | select((.assignee // "") == "") ] as $open
        | ([ $open[] | select($d != "" and .id == $d
                              and (.metadata["gc.demand_for"] // "") == $i) | .id ] | first)
          // ([ $open[] | select(
                  ((.metadata["gc.demand_for"] // "") == $i
                     and ($t == "" or (.metadata["gc.demand_topic"] // "") == $t))
                  or (.issue_type == "gate" and .await_type == "human"
                     and (.await_id // "") == $aid)) | .id ] | first)
          // empty'
}
if [ "$RULED" = yes ]; then
  # SETTLED — the operator ruled in this thread. Resolve each gate where it
  # sits: the visit demand lets the conversation conclude, the anchor demand
  # releases the merge. A demand filed before demands were gates
  # (issue_type=decision) is refused by `gate resolve` ("is not a gate issue"),
  # so it is closed on the same terms instead. Whether the demand closed is
  # decided by reading it back, not by either call's exit status. One that still
  # reads open still blocks, so it gets no ruling and the sign-off stops once
  # every demand has been tried.
  UNCLOSED=""
  for GATED in "$VISIT" "$SUBJECT"; do
    DEMAND=$(demand_on "$GATED")
    [ -n "$DEMAND" ] || continue
    gc bd gate resolve "$DEMAND" --reason "$RULING" \
      || gc bd close "$DEMAND" --reason "$RULING"
    if ! demand_closed "$DEMAND"; then
      echo "DEMAND $DEMAND DID NOT CLOSE — it still blocks $GATED, so the ruling is not stamped on it"
      UNCLOSED="${UNCLOSED:+$UNCLOSED }$DEMAND"
      continue
    fi
    # A demand's board sentence (gc.takeaway) is the QUESTION it was filed with,
    # and the ruling is the answer. Left only in the gate's close reason, which no
    # board reads, the closed demand lingers on the DONE band still asking and a
    # glance re-engages a settled decision. The takeaway verb overwrites it with the
    # ruling; --no-wait is what stamps gc.takeaway_settled, the settled mark only
    # that verb writes, so every board surface reads the answer as a discharged
    # wait. Run only once the close reads back, so the demand never sits
    # open-but-settled — the shape doctor/check-wait-is-an-edge reads as a wait
    # already discharged while it still blocks. The verb's stamp is a plain
    # metadata write, so it lands on the closed demand; if it does not, the
    # renderer still suppresses the stale question.
    "$HELM" takeaway "$DEMAND" "$RULING" --by converse --no-wait \
      || echo "COULD NOT STAMP THE RULING on $DEMAND — the board may still show its question; run: $HELM takeaway $DEMAND \"$RULING\" --by converse --no-wait"
  done
  [ -z "$UNCLOSED" ] || stopped "the ruling did not close $UNCLOSED; the discharge stopped there, so the subject is not released"
else
  # STILL OWED — cut short, or the question outlived the sitting. The wait must
  # persist on the SUBJECT, not on the VISIT: the liveness return trip keys on
  # gc.demand_for=<subject>, so a demand there re-offers the next sitting, and
  # on a PR anchor it also freezes the merge — a sitting that abandoned an
  # unresolved question is the one case the merge should wait. A demand gating
  # the VISIT cannot carry that wait: the visit is this sitting's record and
  # converse-settle closes it next, stranding any demand left on it as a gate on
  # closed work that gate-visit-sweep names on stderr forever and `gate resolve`
  # readies nothing. So move it — re-state the wait on the SUBJECT under this
  # sitting's topic (idempotent: one open demand per gated bead and topic, so an
  # anchor already holding this sitting's opt-in merge demand is simply
  # refreshed, and a sibling sitting's demand on a shared bucket is left alone),
  # then close the visit demand. A sitting that filed NO demand re-states none:
  # the discharge records only the waits the hold actually took.
  # The re-state comes first and must land before the visit demand closes. Closed
  # first, a visit demand whose re-state then failed would leave a re-run finding
  # neither demand, and the operator's open question would be gone. gc-helm.sh
  # demand reads the blocks edge back off the subject before it exits 0 and
  # prints `demand <id>`, so its status is read on its own line, as
  # converse-hold.sh reads it.
  VD=""
  [ "$VISIT" != "$SUBJECT" ] && VD=$(demand_on "$VISIT")
  ID=$(demand_on "$SUBJECT")
  if [ -n "$VD" ] || [ -n "$ID" ]; then
    RESTATE_OUT=$("$HELM" demand "$SUBJECT" "$STILL_OWED" --by converse "${DEMAND_TOPIC[@]}")
    RESTATE_RC=$?
    [ -n "$RESTATE_OUT" ] && printf '%s\n' "$RESTATE_OUT"
    RESTATED=$(printf '%s\n' "$RESTATE_OUT" | awk '/^demand /{print $2; exit}')
    if [ "$RESTATE_RC" -ne 0 ] || [ -z "$RESTATED" ]; then
      KEPT=""
      [ -n "$VD" ] && KEPT="; the visit demand $VD was left open, so a re-run finds it again"
      stopped "the wait did not re-state on $SUBJECT (gc-helm.sh demand exited $RESTATE_RC)$KEPT"
    fi
  fi
  if [ -n "$VD" ]; then
    gc bd gate resolve "$VD" --reason "cut short; wait re-stated on $SUBJECT" \
      || gc bd close "$VD" --reason "cut short; wait re-stated on $SUBJECT"
    demand_closed "$VD" \
      || stopped "the visit's demand $VD did not close, and closing the visit now would strand it as a gate on closed work; the wait already stands on $SUBJECT as $RESTATED, and a re-run refreshes it"
    # Settle its board question so the closed demand does not linger asking;
    # the live wait now rides the SUBJECT demand above.
    "$HELM" takeaway "$VD" "cut short; wait moved to $SUBJECT" --by converse --no-wait \
      || echo "COULD NOT STAMP the moved-wait note on $VD — the board may still show its question"
  fi
fi
# `held` is cleared by a ruling, not by a sitting ending. The cut-short exit
# runs this same block on a subject still waiting, so the release is keyed to
# this sitting's outcome rather than to the state read off the subject. Erring
# toward the hold leaves a bead visibly routed to a person; erring the other
# way restores the untraceable wait this state exists to end. The state was read
# before the first write; nothing this sign-off writes changes it.
if [ "$RULED" = yes ] && [ "$SUBJECT_STATE" = "held" ]; then
  "$LC" transition "$SUBJECT" --to unanchored --route "$ROUTE" \
    || echo "RELEASE FROM held FAILED on $SUBJECT — it still reads as waiting on a person"
fi

# Stash what the visit's PR-reminder close will say, for the writer that runs
# AFTER the visit is actually closed: converse-settle's close step on a normal
# sign-off, or converse-claim.sh's stranded-finish recovery. This script is the
# PRE-close durable trace, so posting "closed" here would run before the close
# lands — a death, a failed outcome stamp, or a failed close between here and
# there would leave the PR saying the visit closed while it is still open and
# holding the merge. The takeaway is the Summary; Actions Taken is what the
# sitting did: the work it routed, the ruling it reached, or what is still owed.
# The stamp lands even though this session still holds the visit, because a
# metadata write bypasses the claim guard.
routed=""
i=0
while [ "$i" -lt "${#WAIT[@]}" ]; do
  [ "${WAIT[$i]}" = "--waiting-on" ] && { i=$((i + 1)); routed="${routed:+$routed, }${WAIT[$i]}"; }
  i=$((i + 1))
done
SIGNOFF_ACTIONS=""
[ -n "$routed" ] && SIGNOFF_ACTIONS="routed work to $routed"
if [ "$RULED" = yes ]; then
  SIGNOFF_ACTIONS="${SIGNOFF_ACTIONS:+$SIGNOFF_ACTIONS; }ruling: $RULING (released to $ROUTE)"
elif [ -n "$STILL_OWED" ]; then
  SIGNOFF_ACTIONS="${SIGNOFF_ACTIONS:+$SIGNOFF_ACTIONS; }still owed: $STILL_OWED"
fi
gc bd update "$VISIT" \
  --set-metadata "gc.pr_visit_summary=$OUTCOME" \
  --set-metadata "gc.pr_visit_actions=$SIGNOFF_ACTIONS" \
  || echo "COULD NOT STASH the PR-reminder close text on $VISIT; its PR comment may stay 'open' after the visit closes"
