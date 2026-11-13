#!/usr/bin/env bash
# work-submit — hand a finished run of mol-polecat-work to the refinery, or end a
# run whose whole product is store work, and drain.
#
#   work-submit.sh --convoy <id>|--bead <id> --base <branch> --notes "<text>"
#                  [--anchor <id>] [--summary-file <path>] [--title "<text>"]
#   work-submit.sh --bead <id> --held-by <conversation> --notes "<text>"
#                  [--summary-file <path>] [--title "<text>"]
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
# carries a merge_result for this branch, which pr-open.sh, the refinery and
# merge.sh read. On fresh work that is this bead. A convoy's rebuild child, a rework that
# answers no review and no ruling, has the convoy it names, as merge-push resolves
# it. A rework child's metadata.anchor_bead answers when the branch list cannot.
# The summary and a retitle go onto the anchor in one write, `gctk pr summary`,
# which the pr domain owns. It is its own write, ahead of the handoff, because a
# failure to land it costs the PR a current body or title, not the handoff.
#
# The handoff is three writes, not one, because bd's claim guard refuses a write
# that reassigns a bead while it is in_progress, and that refusal rolls back
# everything batched into it. So: the metadata and notes, which bypass the guard,
# clearing the route while the status is still in_progress; then the status, which
# carries no assignee change; then the assignee, accepted once the bead is open.
# The bead is unrouted in between, so no pool is offered it. A refused write stops
# the chain and the run ends on a gate. The session pins go in the first write
# because the witness ranks them ahead of the assignee, so a pin left behind names
# a drained session and reads as an orphan.
#
# The worktree goes last, after every durable write and the step's close, because
# removing it destroys the shape the branch gate reads. It goes with its local
# branch, and work_dir is cleared, so no tree outlives the hand-off on commits that
# only its local branch reaches: once a squash merge deletes origin's branch,
# nothing would reach them, and the controller's reaper never removes such a tree.
# A rework or a re-dispatch makes a fresh tree from origin's branch. Only the tree
# work_dir records and this call runs in is removed, never a session's own
# directory, and never by force: a tree with an uncommitted or untracked path stays
# on its branch, work_dir still names it, and the call says so. A tree that holds a
# checkout of any repository stays the same way. Git deletes an ignored path with
# the tree, and a checkout under one is ignored whole: its uncommitted files go,
# and a clone's own commits with them. So a .git anywhere below the tree's own
# keeps the tree, and so does a walk that cannot read every directory under it.
# A session that dies before the removal leaves the tree on
# its branch, which the reaper removes once the bead closes. The removal reads the
# repository from where the tree was, so a tree the reaper took first costs only
# the local branch's delete.
#
# A claimant with no poured workflow holds the work bead itself: `gc hook current`
# names it and it carries no gc.step_ref, so there is no step to close and no other
# bead to write. Any other --bead caller must hold this step, as claim-close.sh judges
# it. Both are read before anything is pushed or written, because a close refused
# after the handoff can only be reported.
#
# A converse sitting hands its change off with --held-by <conversation> beside
# --bead. Its claim is the conversation, so in place of that check the bead must
# show that the sitting holds it (work_held_by_proof in work-lib.sh), which
# refuses a bead the refinery holds as it refuses any other holder's. The bead's
# target is its base, and there is no step to close. The sitting outlives the
# call and is in the conversation to hear why it stopped, so no stop files a
# gate, cancels or drains. The rest is this same code. The hand-off removes the
# edge onto the conversation as its last write, after the assignment and before
# the wake, because the refinery's queue leaves an assigned bead that a wait of
# its own holds, so the assignment starts nothing while the edge stands. A call
# that stops before the assignment leaves the bead unassigned and still held,
# and the call run again finishes it, appending its notes again. Once the
# assignment lands, every run is refused as the refinery's, whether or not the
# release landed.
#
# --anchor-only prints the anchor and its title, for the caller to judge whether
# the title opens with the type and scope that fit and names what the branch
# does, and writes nothing.
#
# exit: 0 handed off, or halted as asked, and drained · 3 the caller owes something
# first, nothing handed off, no drain · 1 stopped, and what follows was taken care
# of · 2 usage. Under --held-by nothing drains, and 1 is a stop that asked and
# ended nothing.
set -uo pipefail

PROG="work-submit"

usage() {
  cat >&2 <<'USAGE'
usage: work-submit.sh --convoy <id>|--bead <id> --base <branch> --notes "<text>"
                      [--anchor <id>] [--summary-file <path>] [--title "<text>"]
       work-submit.sh --bead <id> --held-by <conversation> --notes "<text>"
                      [--summary-file <path>] [--title "<text>"]
       work-submit.sh --anchor-only --convoy <id>|--bead <id>
       work-submit.sh --store-only "<what the run filed>" --notes "<text>" [--done "<brief>"]
                      --convoy <id>|--bead <id> --base <branch>

  --convoy         the run's input convoy; its one tracked bead is the work
  --bead           the work bead, for a claimant with no poured workflow, which
                   this session must hold; exit 3 when it holds neither that bead
                   nor this step
  --held-by        the conversation a converse sitting holds, whose blocks edge
                   holds the --bead; the bead's target is the base, and no stop
                   gates, cancels or drains
  --base           the branch the work was poured from
  --notes          appended to the work bead's notes with the handoff
  --anchor         the anchor --anchor-only printed; absent, it is resolved here
  --summary-file   the PR's summary; empty or absent writes none
  --title          the anchor's new title: the branch's subject line, with its
                   type and scope and no bead id; absent keeps it
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
ANCHOR_ONLY=0; STEP="mol-polecat-work.submit-and-exit"; FORMULA="mol-polecat-work"; BINDING_PREFIX="gc-toolkit."; WORK_HELD_BY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor-only)    ANCHOR_ONLY=1; shift ;;
    --convoy)         require_value "$@"; CONVOY="$2";         shift 2 ;;
    --bead)           require_value "$@"; BEAD="$2";           shift 2 ;;
    --held-by)        require_value "$@"; WORK_HELD_BY="$2";   shift 2 ;;
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
if [ -n "$WORK_HELD_BY" ] && { [ -n "$CONVOY" ] || [ -n "$BASE" ] || [ -n "$STORE_ONLY" ] || [ "$ANCHOR_ONLY" = 1 ]; }; then
  echo "$PROG: --held-by hands off the bead --bead names, to its own target, so it takes no --convoy, no --base and no other mode" >&2
  usage
  exit 2
fi
if [ "$ANCHOR_ONLY" = 0 ] && [ -z "$NOTES" ]; then
  echo "$PROG: --notes is required" >&2
  usage
  exit 2
fi
if [ "$ANCHOR_ONLY" = 0 ] && [ -z "$BASE" ] && [ -z "$WORK_HELD_BY" ]; then
  echo "$PROG: --base is required" >&2
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
# The summary and a retitle are recorded through gctk's pr domain.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin

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

REFINERY_TARGET="${GC_RIG:+$GC_RIG/}${BINDING_PREFIX}refinery"
DIRECT_CLAIM=0
refuse_claim() {
  echo "$PROG: $1 Nothing is pushed, and $WORK_ID is NOT handed off." >&2
  exit 3
}
if [ -n "$WORK_HELD_BY" ]; then
  # A sitting holds the bead through its conversation, and has no step to close.
  work_held_by_proof || exit 1
  BASE=$(work_meta target)
  [ -n "$BASE" ] || work_held_stop "$WORK_ID records no target, the branch its change lands on, so nothing is pushed"
  DIRECT_CLAIM=1
elif [ -n "$BEAD" ] && [ "$ANCHOR_ONLY" = 0 ]; then
  CLAIMED=$(gc hook current --id-only </dev/null 2>/dev/null) || CLAIMED=""
  OWNER=$(work_field .assignee)
  if [ -n "$(work_meta gc.step_ref)" ]; then
    refuse_claim "$WORK_ID is the step $(work_meta gc.step_ref), and --bead names the work bead."
  elif [ "$CLAIMED" != "$WORK_ID" ]; then
    "$SCRIPT_DIR/claim-close.sh" --step "$STEP" --dry-run >/dev/null \
      || refuse_claim "--bead $WORK_ID is not this session's claim, and neither is $STEP."
  elif [ -n "$OWNER" ] && [ "$OWNER" != "$REFINERY_TARGET" ] && ! work_is_self "$OWNER"; then
    refuse_claim "$WORK_ID is held by $OWNER, not this session."
  else
    DIRECT_CLAIM=1
  fi
fi

close_step() {
  [ "$DIRECT_CLAIM" = 0 ] || return 0
  "$SCRIPT_DIR/claim-close.sh" --step "$STEP" \
    || { echo "$PROG: this step is not closed. What it owed is written. Run claim-close.sh --step $STEP again, then gc runtime drain-ack." >&2; exit 1; }
}

if [ "$ANCHOR_ONLY" = 0 ] && [ "$(work_field .status)" = closed ]; then
  if [ "$(work_meta gc.work_outcome)" = shipped ] || [ "$(work_meta merge_result)" = merged ]; then
    close_step
    work_drain
    exit 0
  fi
  if [ "$DIRECT_CLAIM" = 1 ]; then
    echo "$PROG: $WORK_ID was closed while this session held it, so nothing is handed off." >&2
    work_drain
    exit 1
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
    || { work_drain; exit 1; }
  gc bd update "$WORK_ID" --set-metadata halt_reason=store_only --append-notes "Store-only exit: filed $STORE_ONLY. $NOTES" </dev/null >/dev/null || exit 1
  "$SCRIPT_DIR/hand-back.sh" "$WORK_ID" --set-metadata gc.routed_to="" || exit 1
  close_step
  work_drain
  exit 0
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
METADATA_BRANCH=$(work_meta branch)
# The tree the hand-off removes, read while it is still here: the bead's recorded
# work_dir, when this call runs in it, and the repository it belongs to.
OWN_TREE=$(git rev-parse --show-toplevel 2>/dev/null) || OWN_TREE=""
{ [ -n "$OWN_TREE" ] && [ -n "$WORKTREE" ] && [ "$OWN_TREE" -ef "$WORKTREE" ]; } || OWN_TREE=""
COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || COMMON_DIR=""

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
# Recorded as soon as the gate has proved it, before the push: the bring-current
# guard finds the anchor through metadata.branch, and a stop below that re-slings
# the work resumes this branch rather than cutting a new one from the base.
if [ -z "$METADATA_BRANCH" ]; then
  gc bd update "$WORK_ID" --set-metadata "branch=$CURRENT_BRANCH" </dev/null >/dev/null \
    || work_outage "could not record branch=$CURRENT_BRANCH on $WORK_ID, so nothing is pushed"
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
  "$SCRIPT_DIR/hand-back.sh" "$WORK_ID" --set-metadata gc.routed_to="" || exit 1
  close_step
  work_drain
  exit 0
fi

# The commit origin's branch holds as this run reads it: the push goes under the
# lease on it (branch-push.sh), so a push someone made after this read is never
# overwritten, and it is where the bring-current guard starts reading when no
# resume recorded a start. ls-remote --exit-code exits 2 for a branch origin
# does not carry, a branch that must not exist yet, as branch-push.sh's
# --from-origin reads it. Any other exit is a read that did not answer, which
# says nothing about the branch, so nothing is pushed.
LS_OUT=$(git ls-remote --exit-code --heads origin "refs/heads/$CURRENT_BRANCH" 2>&1)
case $? in
  0) PRE_PUSH_HEAD=$(printf '%s' "$LS_OUT" | awk 'NR == 1 { print $1 }'); LEASE=(--from "$PRE_PUSH_HEAD") ;;
  2) PRE_PUSH_HEAD=""; LEASE=(--new) ;;
  *)
    echo "ORIGIN UNREAD: $CURRENT_BRANCH on origin did not read, so nothing was pushed and $WORK_ID stays with this run. Whether the branch is there is unknown, not absent; re-run submit-and-exit once origin answers: $(printf '%s' "$LS_OUT" | tr -s '[:space:]' ' ')" >&2
    work_drain
    exit 1 ;;
esac
if ! "$SCRIPT_DIR/branch-push.sh" --repo "$PWD" --branch "$CURRENT_BRANCH" --head HEAD "${LEASE[@]}"; then
  echo "PUSH FAILED: $WORK_ID stays with this run. A branch that moved under you, or a head that does not hold it, means: re-fetch, MERGE origin in, and retry. Never force-push: branches are brought current by merge, never rebase." >&2
  work_drain
  exit 1
fi
REMOTE_REF=$(git ls-remote origin "refs/heads/$CURRENT_BRANCH" 2>/dev/null | awk '{print $1}')
LOCAL_HEAD=$(git rev-parse HEAD)
if [ -z "$REMOTE_REF" ] || [ "$REMOTE_REF" != "$LOCAL_HEAD" ]; then
  echo "PUSH VERIFICATION FAILED: origin/$CURRENT_BRANCH (${REMOTE_REF:-absent}) != local HEAD ($LOCAL_HEAD). Aborting handoff." >&2
  work_drain
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
    work_drain
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
ROSTER=$(gc agent list --json 2>/dev/null </dev/null | jq -r '.agents[]? | .qualified_name // empty | ., (split("/") | .[-1])' 2>/dev/null) || true
if [ -z "$ROSTER" ]; then
  echo "roster unreadable: handing off to $REFINERY_TARGET unchecked"
elif ! grep -qxF "$REFINERY_TARGET" <<< "$ROSTER"; then
  BOUND=$(grep 'refinery$' <<< "$ROSTER" | sort -u | tr '[:space:]' ' ') || true
  echo "REFINERY ADDRESS NAMES NO AGENT: $REFINERY_TARGET" >&2
  echo "The refinery reads its queue by exact-match assignee, so a bead sent here is never seen and nothing reports it." >&2
  echo "Bound refineries: $BOUND" >&2
  work_drain
  exit 1
fi

# A summary file of whitespace alone writes no summary, and the retitle still goes.
ACCOUNT=()
if [ -s "${SUMMARY_FILE:-/dev/null}" ] && [ -n "$(tr -d '[:space:]' < "$SUMMARY_FILE")" ]; then
  ACCOUNT+=(--file "$SUMMARY_FILE")
fi
if [ -n "$(printf '%s' "$TITLE" | tr -d '[:space:]')" ]; then ACCOUNT+=(--title "$TITLE"); fi
if [ "${#ACCOUNT[@]}" -gt 0 ] && ! ACCOUNT_ERR=$("$GCTK" pr summary "${ANCHOR:-$WORK_ID}" "${ACCOUNT[@]}" 2>&1 </dev/null); then
  echo "the summary and retitle given did not reach ${ANCHOR:-$WORK_ID}, so its PR keeps the body and title it would have without them: ${ACCOUNT_ERR:-gctk pr summary exited non-zero}" >&2
fi
HANDOFF_META=(--set-metadata "target=$LANDING_TARGET" --set-metadata gc.routed_to="" --unset-metadata gc.session_id --unset-metadata gc.session_name)

if ! { gc bd update "$WORK_ID" "${HANDOFF_META[@]}" --append-notes "$NOTES" </dev/null >/dev/null \
    && gc bd update "$WORK_ID" --status=open </dev/null >/dev/null \
    && gc bd update "$WORK_ID" "--assignee=$REFINERY_TARGET" </dev/null >/dev/null; }; then
  [ -z "$WORK_HELD_BY" ] || work_held_stop "HANDOFF REFUSED: a gc bd update in the handoff exited non-zero and rolled itself back, so $WORK_ID is not yet assigned to $REFINERY_TARGET. The branch is pushed and the edge onto $WORK_HELD_BY stands, so this call run again finishes the hand-off"
  echo "HANDOFF REFUSED: a gc bd update in the handoff exited non-zero and rolled itself back, so $WORK_ID is not open, assigned to $REFINERY_TARGET, and unrouted. The branch is pushed, and this run is cancelled after the wait below lands." >&2
  work_stop_with_gate polecat-handoff-refused \
    "Refinery handoff for $WORK_ID was refused: a gc bd update exited non-zero and rolled back. The branch is pushed but the bead is not open+assigned to the refinery, and its run is cancelled." \
    "refinery handoff refused: a gc bd update exited non-zero and rolled back; the branch is pushed but the bead is not handed off"
fi
# A sitting's edge goes only once the refinery holds the bead, so a call that
# stops before the assignment leaves the bead held for the call run again.
if [ -n "$WORK_HELD_BY" ] && ! gc bd dep remove "$WORK_ID" "$WORK_HELD_BY" </dev/null >/dev/null; then
  work_held_stop "$WORK_ID is handed off to $REFINERY_TARGET, but its blocks edge onto $WORK_HELD_BY stands, so the refinery leaves it while $WORK_HELD_BY is open. Remove the edge (gc bd dep remove $WORK_ID $WORK_HELD_BY), then wake the refinery (gc session wake $REFINERY_TARGET)"
fi
[ ! -f "${SUMMARY_FILE:-/nonexistent}" ] || rm -f "$SUMMARY_FILE"

gc session wake "$REFINERY_TARGET" </dev/null >/dev/null 2>&1 || true
gc session nudge "$REFINERY_TARGET" "Run 'gc prime' to check merge queue and begin processing." </dev/null >/dev/null 2>&1 || true

close_step

# The header says what goes and what stays. The hand-off is already written, so
# each way this stops short is said, and none fails the call.
release_tree() {
  local out nested=""
  cd "${GC_DIR:-/nonexistent}" 2>/dev/null || cd "$(dirname "${OWN_TREE:-/}")" 2>/dev/null || cd /
  if [ -z "$OWN_TREE" ] || [ -z "$COMMON_DIR" ]; then
    echo "$PROG: this call ran in no tree that $WORK_ID records as its work_dir, so no tree is removed, and $CURRENT_BRANCH stays checked out where it is." >&2
    return 0
  fi
  if [ -n "${GC_DIR:-}" ] && [ "$OWN_TREE" -ef "$GC_DIR" ]; then
    echo "$PROG: $OWN_TREE is this session's own directory, so it is not removed, and $CURRENT_BRANCH stays checked out there." >&2
    return 0
  fi
  if [ -e "$OWN_TREE" ] && ! nested=$(cd "$OWN_TREE" && find -P . -path ./.git -prune -o -name .git -print -quit 2>/dev/null); then
    echo "$PROG: not every directory under $OWN_TREE could be read, so it is not removed, and $CURRENT_BRANCH stays checked out there." >&2
    return 0
  fi
  if [ -n "$nested" ]; then
    nested="${nested#./}"
    echo "$PROG: $OWN_TREE holds the checkout at $OWN_TREE/${nested%/.git}, which would go with it, so it is not removed, and $CURRENT_BRANCH stays checked out there." >&2
    return 0
  fi
  if [ -e "$OWN_TREE" ] && ! out=$(git -C "$COMMON_DIR" worktree remove "$OWN_TREE" 2>&1) && [ -e "$OWN_TREE" ]; then
    echo "$PROG: $OWN_TREE stays, on $CURRENT_BRANCH, and work_dir still names it, because git would not remove it: $out" >&2
    return 0
  fi
  if git -C "$COMMON_DIR" show-ref --verify --quiet "refs/heads/$CURRENT_BRANCH" \
      && ! out=$(git -C "$COMMON_DIR" branch -D "$CURRENT_BRANCH" 2>&1); then
    echo "$PROG: the tree is gone, and the local branch $CURRENT_BRANCH stays: $out" >&2
  fi
  gc bd update "$WORK_ID" --unset-metadata work_dir </dev/null >/dev/null \
    || echo "$PROG: work_dir on $WORK_ID still names $OWN_TREE, which is gone, so a later run makes a fresh tree." >&2
}
release_tree

work_drain
exit 0
