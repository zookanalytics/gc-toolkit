#!/usr/bin/env bash
# work-submit — hand a finished run of mol-polecat-work to the refinery, or end a
# run whose whole product is store work, and drain.
#
#   work-submit.sh --convoy <id>|--bead <id> --base <branch> --notes "<text>"
#                  [--anchor <id>] [--summary-file <path>] [--title "<text>"]
#   work-submit.sh --anchor-only --convoy <id>|--bead <id>
#   work-submit.sh --store-only "<what the run filed>" --notes "<text>" [--done "<brief>"]
#                  --convoy <id>|--bead <id> --base <branch>
#
# The refinery merges the branch in metadata.branch, so a push from any other
# branch strands the bead: the invariant is CURRENT_BRANCH == metadata.branch, and
# polecat/<bead> is only how fresh work satisfies it. metadata.target says where
# the work lands. A caller-set target always wins, base fills in only for fresh
# work, and a bead that can name neither halts with nothing pushed, because
# recording the branch being pushed would be a self-merge. A work bead closed while
# its run was mid-flight was withdrawn, so the run ends there. A close that landed
# the work (gc.work_outcome=shipped, or merge_result=merged) is this step offered
# again after a claimant handed off and ended before it closed the step, so the
# step just closes.
#
# metadata.auto_push=false halts at branch-ready with nothing pushed. The release
# is two writes, the record and hand-back.sh, because gascity's orphan sweep and
# the witness both act on a released bead that still carries a session pin.
#
# The bead the summary and a retitle belong on is the anchor: the open bead that
# carries a merge_result for this branch, which pr-open.sh, pr-stack.sh and merge.sh
# read. On fresh work that is this bead. A convoy's rebuild child, a rework that
# answers no review and no ruling, has the convoy it names, as merge-push resolves
# it. A rework child's metadata.anchor_bead answers when the branch list cannot.
# A write to the anchor is its own write, ahead of the handoff, because a failure
# to land it costs the PR a current body or title, not the handoff.
#
# The handoff is three writes, not one, because bd's claim guard refuses a write
# that reassigns a bead while it is in_progress, and that refusal rolls back
# everything batched into it. So: the metadata and notes, which bypass the guard,
# clearing the route while the status is still in_progress; then the status, which
# carries no assignee change; then the assignee, accepted once the bead is open.
# The bead is unrouted in between, so no pool is offered it. A refused write stops
# the chain and the run ends on a gate. The session pins go in the first write
# because the witness ranks them ahead of the assignee, so a pin left behind names
# a drained session and reads as an orphan. metadata.work_holder goes with them,
# because this run is done with the tree.
#
# The local branch is released last, after every durable write, because releasing
# it destroys the shape the branch gate reads. A session that dies before that
# costs a held ref and nothing more, and a re-offered step finds the same branch.
#
# --anchor-only prints the anchor and its title, for the caller to judge whether
# the title still names what the branch does, and writes nothing.
#
# exit: 0 handed off, or halted as asked, and drained · 3 the caller owes something
# first, nothing handed off, no drain · 1 stopped, and what follows was taken care
# of · 2 usage
set -uo pipefail

PROG="work-submit"

usage() {
  cat >&2 <<'USAGE'
usage: work-submit.sh --convoy <id>|--bead <id> --base <branch> --notes "<text>"
                      [--anchor <id>] [--summary-file <path>] [--title "<text>"]
       work-submit.sh --anchor-only --convoy <id>|--bead <id>
       work-submit.sh --store-only "<what the run filed>" --notes "<text>" [--done "<brief>"]
                      --convoy <id>|--bead <id> --base <branch>

  --convoy         the run's input convoy; its one tracked bead is the work
  --bead           the work bead, for a claimant with no poured workflow
  --base           the branch the work was poured from
  --notes          appended to the work bead's notes with the handoff
  --anchor         the anchor --anchor-only printed; absent, it is resolved here
  --summary-file   the PR's summary; empty or absent writes none
  --title          the anchor's new title, in plain words; absent keeps it
  --store-only     the beads the run created or routed, for a run with no commit
  --done           with --store-only, the close brief when the record finishes
                   the bead
  --step           the step this session holds; default
                   mol-polecat-work.submit-and-exit
  --formula        the formula a re-sling pours; default mol-polecat-work
  --binding-prefix the pack's agent prefix with its dot; default gc-toolkit.

exit: 0 handed off or halted, and drained · 3 owed first, nothing handed off ·
      1 stopped · 2 usage
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
}

CONVOY=""; BEAD=""; BASE=""; NOTES=""; ANCHOR=""; ANCHOR_SET=0; SUMMARY_FILE=""; TITLE=""; STORE_ONLY=""; DONE_BRIEF=""
ANCHOR_ONLY=0; STEP="mol-polecat-work.submit-and-exit"; FORMULA="mol-polecat-work"; BINDING_PREFIX="gc-toolkit."
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor-only)    ANCHOR_ONLY=1; shift ;;
    --convoy)         require_value "$@"; CONVOY="$2";         shift 2 ;;
    --bead)           require_value "$@"; BEAD="$2";           shift 2 ;;
    --base)           require_value "$@"; BASE="$2";           shift 2 ;;
    --notes)          require_value "$@"; NOTES="$2";          shift 2 ;;
    --anchor)         require_value "$@"; ANCHOR="$2"; ANCHOR_SET=1; shift 2 ;;
    --summary-file)   require_value "$@"; SUMMARY_FILE="$2";   shift 2 ;;
    --title)          require_value "$@"; TITLE="$2";          shift 2 ;;
    --store-only)     require_value "$@"; STORE_ONLY="$2";     shift 2 ;;
    --done)           require_value "$@"; DONE_BRIEF="$2";     shift 2 ;;
    --step)           require_value "$@"; STEP="$2";           shift 2 ;;
    --formula)        require_value "$@"; FORMULA="$2";        shift 2 ;;
    --binding-prefix) require_value "$@"; BINDING_PREFIX="$2"; shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if { [ -n "$CONVOY" ] && [ -n "$BEAD" ]; } || { [ -z "$CONVOY" ] && [ -z "$BEAD" ]; }; then
  echo "$PROG: name the work with --convoy or --bead, not both" >&2
  usage
  exit 2
fi
if [ "$ANCHOR_ONLY" = 0 ] && { [ -z "$NOTES" ] || [ -z "$BASE" ]; }; then
  echo "$PROG: --notes and --base are required" >&2
  usage
  exit 2
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=work-lib.sh
. "$SCRIPT_DIR/work-lib.sh"

work_resolve "$CONVOY" "$BEAD"
case $? in
  0) ;;
  2) echo "$PROG: input convoy $CONVOY does not have exactly one tracked member" >&2; exit 1 ;;
  *) work_outage "could not read input convoy $CONVOY" ;;
esac
work_read "$WORK_ID"
case $? in
  0) ;;
  3) echo "$PROG: the store has no bead $WORK_ID, so there is nothing to hand off" >&2; exit 1 ;;
  *) work_outage "could not read work bead $WORK_ID" ;;
esac

close_step() {
  "$SCRIPT_DIR/claim-close.sh" --step "$STEP" \
    || { echo "$PROG: this step is not closed. What it owed is written. Run claim-close.sh --step $STEP again, then gc runtime drain-ack." >&2; exit 1; }
}

if [ "$ANCHOR_ONLY" = 0 ] && [ "$(work_field .status)" = closed ]; then
  if [ "$(work_meta gc.work_outcome)" = shipped ] || [ "$(work_meta merge_result)" = merged ]; then
    close_step
    gc runtime drain-ack
    exit 0
  fi
  "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "work bead $WORK_ID was closed while its run was mid-flight"
  exit 1
fi

WORKTREE=$(work_meta work_dir)
if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
  cd "$WORKTREE" || exit 1
fi

if [ -n "$STORE_ONLY" ]; then
  # store-only-exit.sh refuses a run with work to land, and writes nothing then.
  "$SCRIPT_DIR/store-only-exit.sh" --bead "$WORK_ID" --base "$BASE" ${CONVOY:+--convoy "$CONVOY"} --done "$DONE_BRIEF" \
    || { gc runtime drain-ack; exit 1; }
  gc bd update "$WORK_ID" --set-metadata halt_reason=store_only --append-notes "Store-only exit: filed $STORE_ONLY. $NOTES" </dev/null >/dev/null || exit 1
  "$SCRIPT_DIR/hand-back.sh" "$WORK_ID" --set-metadata gc.routed_to="" --unset-metadata work_holder || exit 1
  close_step
  gc runtime drain-ack
  exit 0
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
METADATA_BRANCH=$(work_meta branch)

# The list of open beads on this branch, read once. Parked and claimed beads count,
# because every state that carries a merge_result is an anchor state.
resolve_anchor() {
  local ANCHOR_ROWS SELF_ROW NAMED LANDS_ON LIST_OK=1
  ANCHOR=""
  ANCHOR_ROWS=""
  if [ -n "${CURRENT_BRANCH:-}" ]; then
    ANCHOR_ROWS=$(bd_json list --metadata-field "branch=$CURRENT_BRANCH" --limit 0)
    printf '%s' "$ANCHOR_ROWS" | jq -e 'type == "array"' >/dev/null 2>&1 || { ANCHOR_ROWS=""; LIST_OK=0; }
    ANCHOR=$(printf '%s' "$ANCHOR_ROWS" | jq -r --arg self "$WORK_ID" '
        [ .[]? | select(.id != $self)
          | select((((.metadata // {}).merge_result // "") | tostring) != "") ]
        | sort_by(.created_at // .created // .id) | .[0].id // empty' 2>/dev/null) || ANCHOR=""
  fi
  SELF_ROW="$WORK_ROW"
# >>> rebuild-child-lands-on
LANDS_ON=""
NAMED=$(printf '%s' "$SELF_ROW" | jq -r '(.[0].metadata // {}) as $m
  | if (($m.task_kind // "") | tostring) == "rework"
       and (($m.source_review_bead // "") | tostring) == ""
       and (($m.source_ruling_bead // "") | tostring) == ""
    then (($m.anchor_bead // "") | tostring) else "" end' 2>/dev/null) || NAMED=""
[ -z "$NAMED" ] || LANDS_ON=$(printf '%s' "$ANCHOR_ROWS" | jq -r --arg n "$NAMED" '
  [ .[]? | select(.id == $n) | select(((.issue_type // .type // "") | tostring) == "convoy") ]
  | .[0].id // empty' 2>/dev/null) || LANDS_ON=""
# <<< rebuild-child-lands-on
  ANCHOR="${ANCHOR:-$LANDS_ON}"
  if [ "$LIST_OK" = 0 ] && [ -z "$ANCHOR" ]; then
    ANCHOR=$(work_meta anchor_bead)
    [ -z "$ANCHOR" ] || echo "$PROG: could not list the branch's beads; using $WORK_ID's anchor_bead, $ANCHOR" >&2
  fi
}

if [ "$ANCHOR_ONLY" = 1 ]; then
  resolve_anchor
  if [ -n "$ANCHOR" ]; then
    echo "anchor: $ANCHOR (this bead is a child; the summary goes there)"
    echo "title: $(bd_json show "$ANCHOR" | jq -r '.[0].title // empty' 2>/dev/null)"
  else
    echo "anchor: none other on this branch (the claimed bead is the anchor)"
    echo "title: $(work_field .title)"
  fi
  exit 0
fi

if [ -n "$METADATA_BRANCH" ]; then
  EXPECTED_BRANCH="$METADATA_BRANCH"
  GATE_SOURCE="metadata.branch"
else
  EXPECTED_BRANCH="polecat/$WORK_ID"
  GATE_SOURCE="polecat/<bead-id> convention (metadata.branch unset)"
fi
if [ -z "$CURRENT_BRANCH" ] || [ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]; then
  echo "BRANCH SHAPE GATE FAILED"
  echo "  current branch:  ${CURRENT_BRANCH:-<detached HEAD>}"
  echo "  expected branch: $EXPECTED_BRANCH"
  echo "  gate source:     $GATE_SOURCE"
  echo "Refinery handoff merges metadata.branch; proceeding would strand the work."
  if [ -n "$METADATA_BRANCH" ]; then
    echo "This bead already names its branch: check out '$EXPECTED_BRANCH' at the pushed head, then re-run submit-and-exit."
    echo "  origin/$EXPECTED_BRANCH: $(git ls-remote origin "refs/heads/$EXPECTED_BRANCH" 2>/dev/null | awk '{print $1}')"
    echo "  local HEAD:              $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "  bead assignee:           $(work_field .assignee)"
  else
    echo "Re-run workspace-setup: create '$EXPECTED_BRANCH' from origin/$BASE, cherry-pick your commits, re-run submit-and-exit."
  fi
  work_stop_with_gate polecat-branch-shape \
    "Branch shape gate on $WORK_ID: on ${CURRENT_BRANCH:-detached HEAD}, expected $EXPECTED_BRANCH ($GATE_SOURCE). The refinery merges metadata.branch, so the commits must be moved onto $EXPECTED_BRANCH before handoff. Its run is cancelled and nothing was pushed." \
    "branch shape gate: on ${CURRENT_BRANCH:-detached HEAD}, expected $EXPECTED_BRANCH ($GATE_SOURCE); the work waits on the commits moving onto $EXPECTED_BRANCH"
fi

EXISTING_TARGET=$(work_meta target)
if [ -n "$EXISTING_TARGET" ]; then
  LANDING_TARGET="$EXISTING_TARGET"
elif [ "$BASE" != "$CURRENT_BRANCH" ]; then
  LANDING_TARGET="$BASE"
else
  echo "TARGET RESOLUTION FAILED"
  echo "  metadata.target: <unset>"
  echo "  base_branch:     $BASE"
  echo "  current branch:  $CURRENT_BRANCH"
  echo "Nothing names a landing branch, and base_branch is the branch being pushed: recording it would be a self-merge."
  echo "Set it, then re-run submit-and-exit:  gc bd update $WORK_ID --set-metadata target=<landing-branch>"
  work_stop_with_gate polecat-no-landing-target \
    "No landing branch for $WORK_ID: metadata.target is unset and base_branch is $BASE, so recording a target would be a self-merge. Set target on $WORK_ID. Its run is cancelled and nothing was pushed." \
    "no landing branch: metadata.target is unset and base_branch is $BASE; the work waits on a target"
fi
echo "landing target: $LANDING_TARGET"

if [ -n "$(git status --porcelain)" ]; then
  echo "UNCOMMITTED WORK: commit it, then re-run this call. Nothing is pushed with untracked work left behind, and $WORK_ID is NOT handed off:" >&2
  git status --porcelain >&2
  exit 3
fi

if [ "$(printf '%s' "$WORK_ROW" | jq -r '.[0].metadata | if has("auto_push") then (.auto_push | tostring) else "" end')" = false ]; then
  echo "auto_push=false: halting at branch-ready (no push, no refinery handoff)"
  gc bd update "$WORK_ID" --set-metadata "branch=$CURRENT_BRANCH" --set-metadata "target=$LANDING_TARGET" --set-metadata branch_ready=true --set-metadata halt_reason=auto_push_false --append-notes "Branch ready: auto_push=false (no push, no refinery handoff)" </dev/null >/dev/null || exit 1
  "$SCRIPT_DIR/hand-back.sh" "$WORK_ID" --set-metadata gc.routed_to="" --unset-metadata work_holder || exit 1
  close_step
  gc runtime drain-ack
  exit 0
fi

# Where the bring-current guard starts reading when no resume recorded a start.
PRE_PUSH_HEAD=$(git ls-remote origin "refs/heads/$CURRENT_BRANCH" 2>/dev/null | awk '{print $1}')
if ! git push origin HEAD; then
  echo "PUSH FAILED: $WORK_ID stays with this run. A non-fast-forward rejection means the branch moved under you; re-fetch, MERGE origin in, and retry. Never force-push: branches are brought current by merge, never rebase." >&2
  gc runtime drain-ack
  exit 1
fi
REMOTE_REF=$(git ls-remote origin "refs/heads/$CURRENT_BRANCH" 2>/dev/null | awk '{print $1}')
LOCAL_HEAD=$(git rev-parse HEAD)
if [ -z "$REMOTE_REF" ] || [ "$REMOTE_REF" != "$LOCAL_HEAD" ]; then
  echo "PUSH VERIFICATION FAILED: origin/$CURRENT_BRANCH (${REMOTE_REF:-absent}) != local HEAD ($LOCAL_HEAD). Aborting handoff." >&2
  gc runtime drain-ack
  exit 1
fi

"$SCRIPT_DIR/bring-current-guard.sh" guard --bead "$WORK_ID" --to "$LOCAL_HEAD" --from "${PRE_PUSH_HEAD:-}"
case $? in
  0) ;;
  3)
    echo "BRING-CURRENT AUDIT INCOMPLETE: the push stands, but $WORK_ID is NOT handed off. Record the entries the guard names above (bring-current-audit.sh add), or, when it asks where the work began, stamp bring_current_from and bring_current_scope with the command it prints, then re-run this call. Do not drain: finishing the audit is yours." >&2
    exit 3 ;;
  *)
    echo "BRING-CURRENT GUARD DID NOT FINISH: the push stands, but $WORK_ID is NOT handed off. It stays open, which holds any merge it gates, and the session that re-runs submit-and-exit retries the guard." >&2
    gc runtime drain-ack
    exit 1 ;;
esac

[ "$ANCHOR_SET" = 1 ] || resolve_anchor
if [ -n "$ANCHOR" ]; then
  echo "gating anchor: $ANCHOR (this bead is a child; the summary goes there)"
else
  echo "gating anchor: none other on this branch (the claimed bead is the anchor)"
fi

# The refinery's find-work is exact-match on assignee, so a bead sent to an address
# no agent holds is never read, and nothing reports the strand.
REFINERY_TARGET="${GC_RIG:+$GC_RIG/}${BINDING_PREFIX}refinery"
ROSTER=$(gc agent list --json 2>/dev/null </dev/null | jq -r '.agents[]? | .qualified_name // empty | ., (split("/") | .[-1])' 2>/dev/null) || true
if [ -z "$ROSTER" ]; then
  echo "roster unreadable: handing off to $REFINERY_TARGET unchecked"
elif ! grep -qxF "$REFINERY_TARGET" <<< "$ROSTER"; then
  BOUND=$(grep 'refinery$' <<< "$ROSTER" | sort -u | tr '[:space:]' ' ') || true
  echo "REFINERY ADDRESS NAMES NO AGENT: $REFINERY_TARGET" >&2
  echo "The refinery reads its queue by exact-match assignee, so a bead sent here is never seen and nothing reports it." >&2
  echo "Bound refineries: $BOUND" >&2
  gc runtime drain-ack
  exit 1
fi

PR_SUMMARY=""
if [ -s "${SUMMARY_FILE:-/dev/null}" ]; then PR_SUMMARY=$(cat "$SUMMARY_FILE"); fi
HANDOFF_META=(--set-metadata "target=$LANDING_TARGET" --set-metadata gc.routed_to="" --unset-metadata gc.session_id --unset-metadata gc.session_name --unset-metadata work_holder)
[ -n "$METADATA_BRANCH" ] || HANDOFF_META+=(--set-metadata "branch=$CURRENT_BRANCH")
if [ -n "$PR_SUMMARY" ]; then
  if [ -n "$ANCHOR" ]; then
    gc bd update "$ANCHOR" --set-metadata "pr_summary=$PR_SUMMARY" </dev/null >/dev/null \
      || echo "pr_summary did not reach anchor $ANCHOR; its PR body falls back to the dispatch text" >&2
  else
    HANDOFF_META+=(--set-metadata "pr_summary=$PR_SUMMARY")
  fi
fi
if [ -n "$(printf '%s' "$TITLE" | tr -d '[:space:]')" ]; then
  gc bd update "${ANCHOR:-$WORK_ID}" --title "$TITLE" </dev/null >/dev/null \
    || echo "the retitle did not reach ${ANCHOR:-$WORK_ID}; the PR title stays composed from the title it has" >&2
fi

if ! { gc bd update "$WORK_ID" "${HANDOFF_META[@]}" --append-notes "$NOTES" </dev/null >/dev/null \
    && gc bd update "$WORK_ID" --status=open </dev/null >/dev/null \
    && gc bd update "$WORK_ID" "--assignee=$REFINERY_TARGET" </dev/null >/dev/null; }; then
  echo "HANDOFF REFUSED: a gc bd update in the handoff exited non-zero and rolled itself back, so $WORK_ID is not open, assigned to $REFINERY_TARGET, and unrouted. The branch is pushed, and this run is cancelled after the wait below lands." >&2
  work_stop_with_gate polecat-handoff-refused \
    "Refinery handoff for $WORK_ID was refused: a gc bd update exited non-zero and rolled back. The branch is pushed but the bead is not open+assigned to the refinery, and its run is cancelled." \
    "refinery handoff refused: a gc bd update exited non-zero and rolled back; the branch is pushed but the bead is not handed off"
fi
[ ! -f "${SUMMARY_FILE:-/nonexistent}" ] || rm -f "$SUMMARY_FILE"

gc session wake "$REFINERY_TARGET" </dev/null >/dev/null 2>&1 || true
gc session nudge "$REFINERY_TARGET" "Run 'gc prime' to check merge queue and begin processing." </dev/null >/dev/null 2>&1 || true

close_step

if ! { git checkout --detach >/dev/null 2>&1 && git branch -D "$CURRENT_BRANCH" >/dev/null 2>&1; }; then
  echo "branch release failed: $CURRENT_BRANCH stays checked out here. The handoff is already written, so this costs a held ref, nothing more." >&2
fi

gc runtime drain-ack
exit 0
