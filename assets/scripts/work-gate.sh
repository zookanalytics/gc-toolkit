#!/usr/bin/env bash
# work-gate — whether this run of mol-polecat-work may build its work bead.
#
#   work-gate.sh --convoy <id> [--step <ref>] [--formula <f>]
#   work-gate.sh --bead <id>   [--step <ref>] [--formula <f>]
#
# Two dispatch surfaces can reach one work bead, this workflow and a direct pool
# route left on the bead. When both fire, two workers set up the same branch and
# one silently destroys the other's commits. So before the workspace is touched,
# the bead must be readable, not parked, not in flight under another live owner
# or in another live run, not held by a wait, and not finished.
#
# Every refusal ends the run through decline.sh, and they split by whether a
# person has a decision to make:
#   * nobody decides when the bead is finished (closed, handed off, or carrying
#     a merge_result) or another live run is building this same bead;
#   * nobody decides when a wait holds the bead, by the answer of
#     `gctk bead holds`: it waits through that wait and an armed re-sling;
#   * a person decides when the bead is parked, because nothing re-slings it when
#     it is released;
#   * a bead the store does not have cannot be blocked, so it files a patrol
#     finding that names it.
# A store that does not answer is none of these: the step goes back to the pool.
#
# Owner liveness gates only the in-flight case. An idle pool worker between
# claims looks identical to an abandoned one, so an in_progress bead is a conflict
# only while `gc session list` lists its owner. That listing holds every session
# that has not closed, asleep ones included, and a list that cannot be read
# proves nobody gone.
#
# This workflow never claims its work bead, so the assignee cannot show a run in
# flight. The run's root does (run-lib.sh), and `gc sling` judges the same record
# when it refuses a second live run of one formula on a bead under its per-bead
# launch lock. What can still reach this gate beside a live run is a forced
# relaunch and a claimant with no poured workflow. Of the live runs of this formula
# on the bead the oldest builds it and the others refuse, a rule both dispatches
# reach alike from the same rows, with nothing written. A claimant with no run of
# its own refuses any of them. While the oldest's gate has not let it through, that
# gate can still refuse the claim it reads as a live owner, so the claimant first
# leaves the bead waiting on that gate's step with a re-sling armed, which offers
# the bead again unless the gate lets its run through. Another formula's run is no
# duplicate, as it is none to `gc sling`. A sibling on the branch is met at
# workspace-setup's checkout, which no two runs can race past. What holds the bead
# is read first, because a bead that must wait has no business meeting another run.
#
# exit: 0 this run builds the bead · 1 it does not, and decline.sh or the step's
# retry has what follows · 2 usage
set -uo pipefail

PROG="work-gate"

usage() {
  cat >&2 <<'USAGE'
usage: work-gate.sh --convoy <id> [--step <ref>] [--formula <f>]
       work-gate.sh --bead <id>   [--step <ref>] [--formula <f>]

  --convoy   the run's input convoy; its one tracked bead is the work
  --bead     the work bead, for a claimant with no poured workflow
  --step     the step this session holds; default mol-polecat-work.load-context
  --formula  the formula a re-sling pours; default mol-polecat-work

exit: 0 this run builds the bead · 1 it does not · 2 usage
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
}

CONVOY=""; BEAD=""; STEP="mol-polecat-work.load-context"; FORMULA="mol-polecat-work"
while [ $# -gt 0 ]; do
  case "$1" in
    --convoy)  require_value "$@"; CONVOY="$2";  shift 2 ;;
    --bead)    require_value "$@"; BEAD="$2";    shift 2 ;;
    --step)    require_value "$@"; STEP="$2";    shift 2 ;;
    --formula) require_value "$@"; FORMULA="$2"; shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *)         echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if { [ -n "$CONVOY" ] && [ -n "$BEAD" ]; } || { [ -z "$CONVOY" ] && [ -z "$BEAD" ]; }; then
  echo "$PROG: name the work with --convoy or --bead, not both" >&2
  usage
  exit 2
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=work-lib.sh
. "$SCRIPT_DIR/work-lib.sh"
# shellcheck source=run-lib.sh
. "${GC_RUN_LIB:-$SCRIPT_DIR/run-lib.sh}" || { echo "$PROG: cannot source run-lib.sh beside this script" >&2; exit 1; }

DISPATCHED_BY="${CONVOY:+Convoy $CONVOY}"
DISPATCHED_BY="${DISPATCHED_BY:-A direct route}"
SELF="${GC_SESSION_NAME:-${GC_SESSION_ID:-this session}}"

note() { # <label> <what was found>
  gc bd update "$WORK_ID" --append-notes "$1: $SELF found $WORK_ID $2." </dev/null >/dev/null 2>&1 \
    || echo "$PROG: The refusal note did not land on $WORK_ID; the cancel reason on this step still records it." >&2
}

work_resolve "$CONVOY" "$BEAD"
case $? in
  0) ;;
  2)
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "input convoy $CONVOY does not have exactly one tracked member; the pour is malformed" \
      --subject "$CONVOY" --key polecat-malformed-convoy \
      --message "Input convoy $CONVOY does not have exactly one tracked member, so mol-polecat-work cannot derive its work bead; the pour is malformed. Its run is cancelled and nothing was touched. Sling the work again to pour a well-formed run, then clear this gate."
    exit 1 ;;
  *) work_outage "could not read input convoy $CONVOY" ;;
esac

work_read "$WORK_ID"
case $? in
  0) ;;
  3)
    WHY="unreadable (the store has no such bead)"
    note "Unreadable work bead; run cancelled for a person" "$WHY"
    if ! "$SCRIPT_DIR/patrol-finding.sh" --scope polecat-findings --key "polecat-unreadable-work.$WORK_ID" \
        --title "Work bead $WORK_ID could not be read at load-context" \
        --message "Could not read work bead $WORK_ID at load-context (the store has no such bead), so nothing proves it is safe to build. $DISPATCHED_BY dispatched it to $SELF. Its run is cancelled and no workspace was touched. Check that the bead exists and its store answers, then re-sling it."; then
      echo "$PROG: patrol-finding.sh recorded no finding; NOT cancelling or draining, so the next worker retries." >&2
      exit 1
    fi
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "unreadable work bead: $WORK_ID $WHY"
    exit 1 ;;
  *) work_outage "could not read work bead $WORK_ID" ;;
esac

STATUS=$(work_field .status)
OWNER=$(work_field .assignee)
MERGE_RESULT=$(work_meta merge_result)
MERGED=""
[ -z "$MERGE_RESULT" ] || MERGED="already carrying merge_result=$MERGE_RESULT; a PR or merge exists for this bead"

# A finished bead or a live duplicate: the note and the cancel say why, and
# nobody is asked anything.
refuse() { # <note label> <cancel label> <why>
  note "$1" "$3"
  "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "$2: $WORK_ID $3"
  exit 1
}
FINISHED_NOTE="Duplicate dispatch refused (work finished; run cancelled with nothing asked)"
FINISHED_CANCEL="duplicate dispatch (work finished)"
DUPLICATE_NOTE="Duplicate dispatch refused; run cancelled"

case "$STATUS" in
  closed)
    # A close that lands after the pour, such as a duplicate or a no-work close,
    # leaves the assignee empty and stamps no merge_result, so the reason carries
    # what the bead records about its close.
    [ -z "$MERGED" ] || refuse "$FINISHED_NOTE" "$FINISHED_CANCEL" "$MERGED"
    HOW=$(printf '%s' "$WORK_ROW" | jq -r "$DISPOSITION_JQ"'.[0] | [(disposed_to | select(length > 0) | "superseded by " + .), (.metadata["gc.outcome"] // "" | tostring | select(length > 0) | "outcome " + .), (.close_reason // "" | tostring | gsub("[[:space:]]+"; " ") | select(length > 0) | "close reason: " + .[0:200])] | join("; ")')
    refuse "Closed before claim; run cancelled with nothing asked" "closed before claim" "already closed${HOW:+ ($HOW)}; its work is done or was ruled unnecessary" ;;
  open|in_progress)
    if [ -n "$OWNER" ] && ! work_is_self "$OWNER"; then
      if [ "$STATUS" = open ]; then
        # The refinery's handoff leaves the bead open under the refinery, route
        # cleared. A fresh or rework dispatch reaches here with no assignee.
        refuse "$FINISHED_NOTE" "$FINISHED_CANCEL" "already handed off (open, held by $OWNER); another dispatch carried it past this point"
      fi
      LISTED=$(work_owner_listed "$OWNER")
      [ "$LISTED" = 0 ] || refuse "$DUPLICATE_NOTE" "duplicate dispatch" "already in_progress under live $OWNER"
    fi
    [ -z "$MERGED" ] || refuse "$FINISHED_NOTE" "$FINISHED_CANCEL" "$MERGED" ;;
  *)
    # Whoever parked the bead releases it, and nothing re-slings it then. A
    # merge_result still reads as finished: the PR is with the refinery.
    [ -z "$MERGED" ] || refuse "$FINISHED_NOTE" "$FINISHED_CANCEL" "$MERGED"
    WHY="parked (status $STATUS), so it is not this session's to build"
    note "Parked work bead; run cancelled for a person" "$WHY"
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "parked work bead: $WORK_ID $WHY" \
      --subject "$WORK_ID" --key polecat-parked-work \
      --message "Work bead $WORK_ID is $STATUS. $DISPATCHED_BY reached $SELF with it. A parked bead is not built, so its run is cancelled and no workspace was touched. Nothing re-slings it when it is released: once it is ready to build, re-sling it with gc sling <pool> $WORK_ID --on $FORMULA."
    exit 1 ;;
esac

# `gc sling --on` pours at once and reads no edge, so a held bead reaches a
# polecat as an offered claim. What holds it is the answer of `gctk bead holds`,
# the pack's one rule (docs/gctk-architecture.md, "The bead holds contract"):
# work that has not started is held by a wait of its own or one on a parent-child
# ancestor, and work in flight only by its own waits. A fresh dispatch reaches
# here unclaimed and with no branch, and this run's own load-context step is
# still open, so the answer reads it as not started and a parked ancestor holds
# it. A rework child carries its branch and a claimant with no poured workflow
# its claim, so each reads in flight. The store already keeps the wait, so the
# re-sling is armed with no new edge, and it fires once nothing holds the bead.
# A read with no answer is no fact about the work, so the step goes back to the
# pool.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
[ -x "$GCTK" ] || work_outage "could not read what holds work bead $WORK_ID: no gctk binary at '$GCTK'"
# The answer as one line: clear, or the status, the bead its first wait is on and
# what holds it, tab-separated, and for a blocked bead, the beads its waits are
# on, comma-separated.
hold_read() {
  # shellcheck disable=SC2016  # jq source; its $names are jq's
  "$GCTK" bead holds "$WORK_ID" </dev/null 2>/dev/null | jq -r --arg id "$WORK_ID" '
    select(type == "object" and .id == $id)
    | (.waits // []) as $w | ($w | map(.id | tostring) | join(", ")) as $on
    | if .error != null then empty
      elif .status == "clear" then "clear"
      elif ($w | length) == 0 then empty
      elif .status == "blocked" then "blocked\t\($w[0].id)\theld by its own wait on \($on)\t\($w | map(.id | tostring) | join(","))"
      elif .status == "held" then "held\t\($w[0].id)\theld through its ancestor \($w[0].ancestor), which waits on \($on), and its work has not started"
      elif .status == "unjudged" then "unjudged\t\($w[0].id)\theld by its own waits-for edge onto \($on), which the store cannot judge yet"
      else empty end' 2>/dev/null | head -n 1
}
HOLD=$(hold_read)
[ -n "$HOLD" ] || work_outage "could not read what holds work bead $WORK_ID (gctk bead holds gave no answer for it)"
# A claimant that hands this run the bead, below, leaves it waiting on this run's
# gate step, the bead this session holds (gc hook current). That wait is the
# hand-off and holds nothing against this run. When it is the bead's only wait of
# its own, its edge is removed and what holds the bead is read again, so an
# ancestor's wait on work that has not started still holds it. Any other wait of
# its own holds the bead with or without the hand-off.
if [ -n "$CONVOY" ] && [ "$HOLD" != clear ]; then
  IFS=$'\t' read -r HOLD_STATUS _ _ HOLD_OWN <<< "$HOLD"
  if [ "$HOLD_STATUS" = blocked ]; then
    HELD=$(gc hook current --id-only </dev/null 2>/dev/null) || HELD=""
    if [ -n "$HELD" ] && [ "$HOLD_OWN" = "$HELD" ]; then
      gc bd dep remove "$WORK_ID" "$HELD" </dev/null >/dev/null 2>&1 \
        || work_outage "could not remove the wait of work bead $WORK_ID on $HELD, the step this session holds"
      HOLD=$(hold_read)
      [ -n "$HOLD" ] || work_outage "could not read what holds work bead $WORK_ID (gctk bead holds gave no answer for it)"
    fi
  fi
fi
if [ "$HOLD" != clear ]; then
  IFS=$'\t' read -r HOLD_STATUS HOLD_ON HOLD_WHAT _ <<< "$HOLD"
  if "$SCRIPT_DIR/await-ruling.sh" "$WORK_ID" --held-by "$HOLD_ON" --formula "$FORMULA"; then
    note "Held work bead; run cancelled, re-sling armed" "$HOLD_WHAT (gctk bead holds: $HOLD_STATUS). A re-sling is armed to fire once nothing holds it"
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "work bead $WORK_ID is $HOLD_WHAT ($HOLD_STATUS); a re-sling is armed for when nothing holds it"
  else
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "work bead $WORK_ID is $HOLD_WHAT ($HOLD_STATUS)" \
      --subject "$WORK_ID" --key polecat-blocked-work \
      --message "Formula-slung $WORK_ID reached a polecat while $HOLD_WHAT (gctk bead holds: $HOLD_STATUS). Its run is cancelled and no workspace was touched. The re-sling could not be armed; re-sling this work once nothing holds it, when gctk bead holds $WORK_ID answers clear."
  fi
  exit 1
fi

store_read() { gc bd "$@"; }
RUNS=$(run_lib runs store_read "$WORK_ID") || work_outage "could not read the runs that work $WORK_ID"
LIVE=$(printf '%s' "$RUNS" | jq -c --arg f "$FORMULA" '[.[] | select(.live and .formula == $f)]')
OTHERS=$(printf '%s' "$LIVE" | jq -r --arg mine "$CONVOY" '[.[] | select($mine == "" or .convoy != $mine) | .root] | join(", ")')
[ -n "$OTHERS" ] || exit 0

# A root's created_at has one form and a second's resolution, so its id breaks a
# tie, and a root the store does not return cannot be the oldest.
OLDEST=$(bd_json list --id "$(printf '%s' "$LIVE" | jq -r 'map(.root) | join(",")')" --all --include-ephemeral --limit 0 \
  | jq -r 'sort_by([.created_at, .id]) | .[0].id // empty' 2>/dev/null)
[ -n "$OLDEST" ] || work_outage "could not read the age of the runs that work $WORK_ID"
if [ -n "$CONVOY" ]; then
  MINE=$(printf '%s' "$LIVE" | jq -r --arg mine "$CONVOY" '[.[] | select(.convoy == $mine) | .root] | .[0] // empty')
  [ "$OLDEST" != "$MINE" ] || exit 0
else
  # A claimant hands the bead to the oldest run. That run's gate step, the step at
  # --step under its root, closes with outcome pass once its gate lets the run
  # through. Until then the gate can still read this claim as a live owner and
  # refuse, which ends its run, and no row records when the claim was taken, so
  # the two cannot order themselves. So the bead waits on that step, with a
  # re-sling armed, before the claim is handed back. A gate that lets its run
  # through closes the step and leaves the run live, so the arm's start finds the
  # run working the bead (gc sling exits 3) and retires with no pour. A gate that
  # refuses, or a run cancelled at it, closes the step and ends the run, so the
  # arm re-slings the bead. A run with no such step, or one whose gate has passed,
  # builds the bead, and the claim is handed back as it is beside any live run.
  # A wait that does not land leaves that hand-back, with the live run as its
  # record.
  GATE_STEP=$(bd_json list --metadata-field "gc.root_bead_id=$OLDEST" --metadata-field "gc.step_ref=$STEP" --all --include-ephemeral --limit 0 \
    | jq -r 'if type != "array" then error("not a listing")
             elif any(.[]; (.status // "") == "closed" and (.metadata["gc.outcome"] // "") == "pass") then ""
             else (.[0].id // "") end' 2>/dev/null) \
    || work_outage "could not read the gate step of run $OLDEST, which works $WORK_ID"
  if [ -n "$GATE_STEP" ]; then
    AT_GATE="in flight in live run $OTHERS, and run $OLDEST's gate step $GATE_STEP has not let that run through"
    if "$SCRIPT_DIR/await-ruling.sh" "$WORK_ID" --blocked-by "$GATE_STEP" --formula "$FORMULA"; then
      note "Claim handed to a run at its gate; re-sling armed" "$AT_GATE. It waits on $GATE_STEP with a re-sling armed: a gate that lets the run through retires the arm with no pour, and one that refuses re-slings $WORK_ID"
      "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "duplicate dispatch: $WORK_ID $AT_GATE; it waits on $GATE_STEP with a re-sling armed"
      exit 1
    fi
    refuse "$DUPLICATE_NOTE" "duplicate dispatch" "$AT_GATE. The wait on $GATE_STEP did not land, so nothing re-slings it if that gate refuses it"
  fi
fi
refuse "$DUPLICATE_NOTE" "duplicate dispatch" "in flight in live run $OTHERS"
