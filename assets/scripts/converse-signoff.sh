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
# What is waiting on the subject is the caller's to state: one --waiting-on per
# bead it ROUTED work into, --no-wait when it settled the subject and nothing is
# waiting, and NEITHER where the subject is parked for a person. The writers
# (gc-helm.sh, lifecycle.sh) are SEARCHED for on the candidate roots.
#
# Usage:
#   converse-signoff.sh --visit <id> --outcome "<takeaway, ≤140 chars>" \
#     [--subject <id>] [--ruled yes|no] \
#     [--no-wait | --waiting-on <bead> ...] \
#     [--ruling "<one line>"] [--still-owed "<≤140 chars>"] [--route <rig>/<agent>|human] \
#     [--rework]
#   --outcome is required. --ruled defaults to `no`. --ruled yes requires
#   --ruling and --route; --ruled no requires --still-owed. --subject defaults
#   to the subject the visit records (its tracks edge, else its
#   gc.continuation_group stamp); with neither, the sign-off refuses and writes
#   nothing.
#   --rework (with --ruled yes): the ruling makes an already-published PR stale,
#     so file the rework demand against the subject anchor — the review verdict's
#     rework child, sourced by this visit — instead of only resolving the demand.
#     The filing runs before every other write, and when it does not land
#     nothing else is written.
# Exit: 0 the sign-off may proceed, once any write it reports as failed is
#   repaired; 1 --rework did not file and no trace was written — do NOT post
#   the sign-off or close the visit; 2 usage, nothing written.
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
REWORK=0
WAIT=()

die() { echo "converse-signoff: $1" >&2; exit 2; }

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
    --rework)     REWORK=1 ;;
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
if [ "$REWORK" = 1 ] && [ "$RULED" != yes ]; then
  die "--rework requires --ruled yes (the rework demand follows a ruling that settled the question)"
fi
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v gc >/dev/null 2>&1 || die "gc is required"

V=$(gc bd show "$VISIT" --json | scrub)
# Every write below lands on the subject or the visit. The caller passes the
# subject step 1 resolved, and the visit records it twice, as its tracks edge
# and as its gc.continuation_group stamp, so an absent --subject is recovered
# here the way converse-fold.sh recovers it. With neither, a cut-short sign-off
# would close the visit's demand and then fail to re-state it on an empty bead
# id, dropping the operator's open question, so it refuses before any write.
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
# A ruling can make an already-published PR stale: it changes what the branch
# must contain, while the PR still reads review-ready against a head that
# predates it. --rework turns that ruling into the rework demand a review verdict
# files — a fix unit that blocks the anchor and resumes its branch — sourced by
# this visit instead of a verdict. It is the sitting's explicit opt-in, because
# only the sitting knows a ruling's consequence reaches the open PR. The filing
# is independent of the demand discharge below: a ruling with no prior hold
# still needs its rework.
# The filing runs before every other write and fails the sign-off closed. Filed
# first, the child's blocks edge already holds the merge when the discharge
# resolves a merge hold this sitting took, so the hold passes to the edge with no
# gap in which the stale PR can land. A filing does not land when no script
# resolves, or when converse-rework.sh exits non-zero, as it does for any filing
# it refuses or cannot prove. Then the takeaway, the discharge and the release
# stay unwritten, every demand this sitting filed still stands, and exit 1 tells
# the sitting not to sign off or close the visit. A re-run starts clean, and
# converse-rework.sh adopts a child an earlier attempt filed rather than minting
# a second.
REWORK_FILED=""
if [ "$RULED" = yes ] && [ "$REWORK" = 1 ]; then
  CR=""
  for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
    [ -x "$cand/assets/scripts/converse-rework.sh" ] && { CR="$cand/assets/scripts/converse-rework.sh"; break; }
  done
  if [ -z "$CR" ]; then
    REWORK_OUT="no converse-rework.sh on any candidate root"
  elif REWORK_OUT=$("$CR" --anchor "$SUBJECT" --ruling-bead "$VISIT" --ruling "$RULING" 2>&1); then
    echo "$REWORK_OUT"
    REWORK_FILED=yes
  fi
  if [ -z "$REWORK_FILED" ]; then
    echo "REWORK NOT FILED on $SUBJECT: $REWORK_OUT"
    echo "Nothing is signed off: no takeaway, discharge or release was written, and every demand this sitting filed still stands. Do NOT post the sign-off or close the visit."
    echo "Repair the cause and re-run this sign-off. If $SUBJECT is not an open PR, file the ruling's consequence as work, then re-run without --rework and with --waiting-on <that bead>. If it cannot be repaired, raise it in the thread."
    exit 1
  fi
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
# Discharge the hold. A conversation wait gates the VISIT (the default — a
# conversation does not freeze its subject) and an explicit merge hold gates the
# SUBJECT; a sitting may have filed either or both. --include-gates: a demand is
# a human gate, hidden from `bd list` by default, so the discharge would
# otherwise never find it.
HELD_DEMAND=$(printf '%s' "$V" | jq -r '.[0].metadata["gc.hold_demand"] // ""')
DEMANDS_JSON=$(gc bd list --status=open,in_progress --include-gates --json --limit=0 | scrub)
# The open, unassigned demand THIS sitting filed on a given bead, or empty. Under
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
  # so it is closed on the same terms instead.
  for GATED in "$VISIT" "$SUBJECT"; do
    DEMAND=$(demand_on "$GATED")
    [ -n "$DEMAND" ] || continue
    gc bd gate resolve "$DEMAND" --reason "$RULING" \
      || gc bd close "$DEMAND" --reason "$RULING"
    # A demand's board sentence (gc.takeaway) is the QUESTION it was filed with,
    # and the ruling is the answer. Left only in the gate's close reason, which no
    # board reads, the closed demand lingers on the DONE band still asking and a
    # glance re-engages a settled decision. The takeaway verb overwrites it with the
    # ruling; --no-wait is what stamps gc.takeaway_settled, the settled mark only
    # that verb writes, so every board surface reads the answer as a discharged
    # wait. Run AFTER the close, so the demand never sits open-but-settled — the
    # shape doctor/check-wait-is-an-edge reads as a wait already discharged while it
    # still blocks. The verb's stamp is a plain metadata write, so it lands on the
    # closed demand; if it does not, the renderer still suppresses the stale question.
    "$HELM" takeaway "$DEMAND" "$RULING" --by converse --no-wait \
      || echo "COULD NOT STAMP THE RULING on $DEMAND — the board may still show its question; run: $HELM takeaway $DEMAND \"$RULING\" --by converse --no-wait"
  done
else
  # STILL OWED — cut short, or the question outlived the sitting. The wait must
  # persist on the SUBJECT, not on the VISIT: the liveness return trip keys on
  # gc.demand_for=<subject>, so a demand there re-offers the next sitting, and
  # on a PR anchor it also freezes the merge — a sitting that abandoned an
  # unresolved question is the one case the merge should wait. A demand gating
  # the VISIT cannot carry that wait: the visit is this sitting's record and
  # converse-settle closes it next, stranding any demand left on it as a gate on
  # closed work that gate-visit-sweep names on stderr forever and `gate resolve`
  # readies nothing. So move it — close the visit demand, re-state the wait on
  # the SUBJECT under this sitting's topic (idempotent: one open demand per
  # gated bead and topic, so an anchor already holding this sitting's opt-in
  # merge demand is simply refreshed, and a sibling sitting's demand on a shared
  # bucket is left alone). A sitting that filed NO demand re-states none: the
  # discharge records only the waits the hold actually took.
  VD=""
  [ "$VISIT" != "$SUBJECT" ] && VD=$(demand_on "$VISIT")
  ID=$(demand_on "$SUBJECT")
  if [ -n "$VD" ]; then
    gc bd gate resolve "$VD" --reason "cut short; wait re-stated on $SUBJECT" \
      || gc bd close "$VD" --reason "cut short; wait re-stated on $SUBJECT"
    # Settle its board question so the closed demand does not linger asking;
    # the live wait now rides the SUBJECT demand below.
    "$HELM" takeaway "$VD" "cut short; wait moved to $SUBJECT" --by converse --no-wait \
      || echo "COULD NOT STAMP the moved-wait note on $VD — the board may still show its question"
  fi
  if [ -n "$VD" ] || [ -n "$ID" ]; then
    "$HELM" demand "$SUBJECT" "$STILL_OWED" --by converse "${DEMAND_TOPIC[@]}"
  fi
fi
# `held` is cleared by a ruling, not by a sitting ending. The cut-short exit
# runs this same block on a subject still waiting, so the release is keyed to
# this sitting's outcome rather than to the state read off the subject. Erring
# toward the hold leaves a bead visibly routed to a person; erring the other
# way restores the untraceable wait this state exists to end.
LC=""
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/lifecycle.sh" ] && { LC="$cand/assets/scripts/lifecycle.sh"; break; }
done
if [ "$RULED" = yes ] && [ -n "$LC" ] && [ "$("$LC" state "$SUBJECT" 2>/dev/null)" = "held" ]; then
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
  [ -n "$REWORK_FILED" ] && SIGNOFF_ACTIONS="${SIGNOFF_ACTIONS}; filed ruling-driven rework on $SUBJECT"
elif [ -n "$STILL_OWED" ]; then
  SIGNOFF_ACTIONS="${SIGNOFF_ACTIONS:+$SIGNOFF_ACTIONS; }still owed: $STILL_OWED"
fi
gc bd update "$VISIT" \
  --set-metadata "gc.pr_visit_summary=$OUTCOME" \
  --set-metadata "gc.pr_visit_actions=$SIGNOFF_ACTIONS" \
  || echo "COULD NOT STASH the PR-reminder close text on $VISIT; its PR comment may stay 'open' after the visit closes"
