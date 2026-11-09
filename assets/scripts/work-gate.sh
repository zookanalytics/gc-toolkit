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
# its own refuses any of them. Another formula's run is no duplicate, as it is none
# to `gc sling`. A sibling on the branch is met at workspace-setup's checkout, which
# no two runs can race past. What holds the bead is read first, because a bead that
# must wait has no business meeting another run.
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
# what holds it, tab-separated.
# shellcheck disable=SC2016  # jq source; its $names are jq's
HOLD=$("$GCTK" bead holds "$WORK_ID" </dev/null 2>/dev/null | jq -r --arg id "$WORK_ID" '
  select(type == "object" and .id == $id)
  | (.waits // []) as $w | ($w | map(.id | tostring) | join(", ")) as $on
  | if .error != null then empty
    elif .status == "clear" then "clear"
    elif ($w | length) == 0 then empty
    elif .status == "blocked" then "blocked\t\($w[0].id)\theld by its own wait on \($on)"
    elif .status == "held" then "held\t\($w[0].id)\theld through its ancestor \($w[0].ancestor), which waits on \($on), and its work has not started"
    elif .status == "unjudged" then "unjudged\t\($w[0].id)\theld by its own waits-for edge onto \($on), which the store cannot judge yet"
    else empty end' 2>/dev/null | head -n 1)
[ -n "$HOLD" ] || work_outage "could not read what holds work bead $WORK_ID (gctk bead holds gave no answer for it)"
if [ "$HOLD" != clear ]; then
  IFS="$(printf '\t')" read -r HOLD_STATUS HOLD_ON HOLD_WHAT <<< "$HOLD"
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

if [ -n "$CONVOY" ]; then
  # A root's created_at has one form and a second's resolution, so its id breaks a
  # tie, and a root the store does not return cannot be the oldest.
  OLDEST=$(bd_json list --id "$(printf '%s' "$LIVE" | jq -r 'map(.root) | join(",")')" --all --include-ephemeral --limit 0 \
    | jq -r 'sort_by([.created_at, .id]) | .[0].id // empty' 2>/dev/null)
  [ -n "$OLDEST" ] || work_outage "could not read the age of the runs that work $WORK_ID"
  MINE=$(printf '%s' "$LIVE" | jq -r --arg mine "$CONVOY" '[.[] | select(.convoy == $mine) | .root] | .[0] // empty')
  [ "$OLDEST" != "$MINE" ] || exit 0
fi
refuse "$DUPLICATE_NOTE" "duplicate dispatch" "in flight in live run $OTHERS"
