#!/usr/bin/env bash
# work-setup — ensure a run of mol-polecat-work has its isolated worktree on its
# recorded branch. Every part is idempotent, so a run re-entering after a crash
# lands in the same place.
#
#   work-setup.sh --convoy <id>|--bead <id> --base <branch> [--step <ref>] [--formula <f>]
#   work-setup.sh --conclude-merge --convoy <id>|--bead <id>
#   work-setup.sh --stop-merge --convoy <id>|--bead <id> --path <file> --collided "<text>"
#                 --question "<text>" [--step <ref>] [--formula <f>]
#
# The worktree is the one metadata.work_dir records while it is on disk, else a
# new one scoped to the bead and registered in the rig's checkout, whatever repo
# this session's directory sits in. metadata.branch is authoritative when set: it
# is fetched and fast-forwarded, and divergence stops the run rather than making a
# different branch. Without one, polecat/<bead> is cut from the freshly fetched
# base, since a stale local base causes spurious conflicts at the refinery. Which
# tree the run entered and which session entered it are recorded on every path,
# because self-review and submit-and-exit find the tree there, and core's
# work-holder.sh reads the record to tell a run in flight from a tree left behind.
# gc.work_branch is recorded too: the claim stamps it from the pool slot's base
# checkout, and the close gate checks gc.work_commit is reachable on it.
#
# A branch another worktree has checked out stops the checkout, which is the one
# check two runs cannot race past. When a live run works the bead that records that
# tree, a sibling holds it, so this work waits on that sibling through a blocks edge
# and an armed re-sling. When no run does, the tree was left behind, so this run
# adopts it if it is clean. A dirty tree, and a tree no bead accounts for, go to a
# person.
#
# A rejected branch resumes by MERGE and is never rewritten: a rebase forces a
# push, which resets the PR's "changes since last review" and drifts its review
# comments. The round is recorded before the merge moves HEAD, so the hand-off's
# bring-current guard reads it whichever session re-runs the hand-off: where it
# starts, and whether bringing the branch current is this bead's whole job. An
# earlier round's audit and question are cleared. The rejection stays until the
# merge concludes, so a stop before then merges again on the next run.
#
# --conclude-merge commits a merge whose conflicts are resolved and audited.
# --stop-merge asks a person about a conflict that cannot be resolved without
# guessing, aborts the merge, and ends the run or hands the bead back.
#
# stdout: progress, then the path of the worktree as the last line, which the
# caller enters. Everything a person should read goes to stderr.
# exit: 0 ready · 3 the merge stopped on conflicts, which the worker resolves in
# the printed worktree · 1 stopped, and what follows was taken care of · 2 usage
set -uo pipefail

PROG="work-setup"

usage() {
  cat >&2 <<'USAGE'
usage: work-setup.sh --convoy <id>|--bead <id> --base <branch> [--step <ref>] [--formula <f>]
       work-setup.sh --conclude-merge --convoy <id>|--bead <id>
       work-setup.sh --stop-merge --convoy <id>|--bead <id> --path <file> --collided "<text>"
                     --question "<text>" [--step <ref>] [--formula <f>]

  --convoy   the run's input convoy; its one tracked bead is the work
  --bead     the work bead, for a claimant with no poured workflow
  --base     the branch the work is poured from
  --step     the step this session holds; default mol-polecat-work.workspace-setup
  --formula  the formula a re-sling pours; default mol-polecat-work

exit: 0 ready · 3 conflicts to resolve · 1 stopped · 2 usage
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
}

MODE=setup; CONVOY=""; BEAD=""; BASE=""; STEP="mol-polecat-work.workspace-setup"; FORMULA="mol-polecat-work"
AUDIT_PATH=""; COLLIDED=""; QUESTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --conclude-merge) MODE=conclude; shift ;;
    --stop-merge)     MODE=stop; shift ;;
    --convoy)   require_value "$@"; CONVOY="$2";     shift 2 ;;
    --bead)     require_value "$@"; BEAD="$2";       shift 2 ;;
    --base)     require_value "$@"; BASE="$2";       shift 2 ;;
    --step)     require_value "$@"; STEP="$2";       shift 2 ;;
    --formula)  require_value "$@"; FORMULA="$2";    shift 2 ;;
    --path)     require_value "$@"; AUDIT_PATH="$2"; shift 2 ;;
    --collided) require_value "$@"; COLLIDED="$2";   shift 2 ;;
    --question) require_value "$@"; QUESTION="$2";   shift 2 ;;
    -h|--help)  usage; exit 2 ;;
    *)          echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if { [ -n "$CONVOY" ] && [ -n "$BEAD" ]; } || { [ -z "$CONVOY" ] && [ -z "$BEAD" ]; }; then
  echo "$PROG: name the work with --convoy or --bead, not both" >&2
  usage
  exit 2
fi
if [ "$MODE" = setup ] && [ -z "$BASE" ]; then
  echo "$PROG: --base is required" >&2
  usage
  exit 2
fi
if [ "$MODE" = stop ] && { [ -z "$AUDIT_PATH" ] || [ -z "$COLLIDED" ] || [ -z "$QUESTION" ]; }; then
  echo "$PROG: --stop-merge needs --path, --collided and --question" >&2
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

if [ "$MODE" = conclude ]; then
  git commit --no-edit || exit 1
  gc bd update "$WORK_ID" --unset-metadata rejection_reason </dev/null >/dev/null || exit 1
  exit 0
fi

if [ "$MODE" = stop ]; then
  BCA="$SCRIPT_DIR/bring-current-audit.sh"
  "$BCA" ask --bead "$WORK_ID" --path "$AUDIT_PATH" --collided "$COLLIDED" --question "$QUESTION" \
    || { echo "$PROG: the question reached no gate; NOT stopping, since nothing asks it yet. Re-run the ask." >&2; exit 1; }
  git merge --abort
  CLAIMED=$(gc hook current --id-only </dev/null 2>/dev/null) || CLAIMED=""
  if [ -n "$CLAIMED" ] && [ "$CLAIMED" != "$WORK_ID" ]; then
    # ask filed the gate on the anchor, under a key that names this bead, and
    # await-ruling.sh gives the work bead its own edge onto it.
    ANCHOR=$("$BCA" anchor --bead "$WORK_ID") \
      && "$SCRIPT_DIR/await-ruling.sh" "$WORK_ID" --key "bring-current-question.$WORK_ID" --subject "$ANCHOR" --formula "$FORMULA" \
      || { echo "$PROG: the wait did not land on $WORK_ID; NOT cancelling or draining, so the next worker retries." >&2; exit 1; }
    work_release_holder
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "bringing the branch current needs a decision only a person can make; the bring-current-question gate on the anchor asks it"
    exit $?
  fi
  # A bead with no molecule parks to a person, naming what it waits for. The note
  # lands first, and the park rides the hand-back, one write that reopens the bead
  # and releases this session's claim. A refused hand-back leaves the claim on the
  # route it had, which Gas City can release when the session ends. No agent serves
  # the person route, so a claim parked there would stay held.
  gc bd update "$WORK_ID" --append-notes "Stopped bringing the branch current: a conflict needs a decision (the bring-current-question gate on the anchor asks it). Nothing was pushed." </dev/null >/dev/null
  "$SCRIPT_DIR/hand-back.sh" "$WORK_ID" --set-metadata gc.routed_to=human \
    --set-metadata "gc.takeaway=Needs a decision before its branch can be brought current; the gate on its anchor asks it" \
    --set-metadata "gc.takeaway_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" --set-metadata gc.takeaway_by=mol-polecat-work \
    --set-metadata gc.takeaway_settled=
  gc runtime drain-ack
  exit 0
fi

git fetch --prune origin >&2 || echo "$PROG: git fetch --prune origin failed; going on with the refs already here" >&2

work_read "$WORK_ID"
case $? in
  0) ;;
  3) echo "$PROG: the store has no bead $WORK_ID, so there is no work to set up" >&2; exit 1 ;;
  *) work_outage "could not read work bead $WORK_ID" ;;
esac

store_read() { gc bd "$@"; }
# A read that fails cannot rule a run out.
has_live_run() { # <bead>
  local runs
  runs=$(run_lib runs store_read "$1") || return 0
  printf '%s' "$runs" | jq -e 'any(.[]; .live)' >/dev/null 2>&1
}

# A branch checked out in another worktree: the tree its message names is some
# unclosed bead's work_dir. Returns 0 when this run has adopted the tree.
yield_to_tree() { # <git's message>
  local tree sibling id dir
  tree=$(printf '%s\n' "$1" | sed -n -e "s/.*already used by worktree at '\([^']*\)'.*/\1/p" -e "s/.*already checked out at '\([^']*\)'.*/\1/p" | head -n 1)
  sibling=""
  while IFS="$(printf '\t')" read -r id dir; do
    if [ -n "$id" ] && [ -n "$dir" ] && [ "$dir" -ef "$tree" ]; then
      sibling="$id"
      break
    fi
  done <<ROWS
$(bd_json list --metadata-field "branch=$BRANCH" --limit 0 | jq -r --arg me "$WORK_ID" '.[]? | select(.id != $me) | [.id, (.metadata.work_dir // "")] | @tsv' 2>/dev/null)
ROWS
  if [ -n "$sibling" ] && ! has_live_run "$sibling"; then
    if [ -n "$(git -C "$tree" status --porcelain 2>/dev/null)" ]; then
      work_stop_with_gate polecat-duplicate-dispatch \
        "Possible duplicate dispatch on $WORK_ID: $BRANCH is checked out in $tree, the tree $sibling records. No run works $sibling, but the tree holds uncommitted paths, so this run did not adopt it. Its run is cancelled and nothing was built. Salvage what the tree holds, then remove it or commit it." \
        "duplicate dispatch: $WORK_ID found $BRANCH checked out in $tree with uncommitted paths, and no run works $sibling"
    fi
    echo "$PROG: adopting $tree, where $BRANCH is checked out: no run works $sibling, and the tree is clean" >&2
    cd "$tree" || exit 1
    [ -z "$CREATED_TREE" ] || git -C "$tree" worktree remove --force "$CREATED_TREE" >&2 \
      || echo "$PROG: NOTE: the empty tree $CREATED_TREE was not removed" >&2
    return 0
  fi
  if [ -n "$sibling" ] && "$SCRIPT_DIR/await-ruling.sh" "$WORK_ID" --blocked-by "$sibling" --formula "$FORMULA"; then
    gc bd update "$WORK_ID" --append-notes "Yielded behind sibling $sibling on $BRANCH, whose tree holds the branch at $tree. A re-sling is armed for when it closes." </dev/null >/dev/null 2>&1 \
      || echo "$PROG: The note did not land on $WORK_ID; the cancel reason on this step still records it." >&2
    work_release_holder
    "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "work bead $WORK_ID waits on sibling $sibling, whose tree holds $BRANCH; a re-sling is armed for when it closes"
    exit 1
  fi
  work_stop_with_gate polecat-duplicate-dispatch \
    "Possible duplicate dispatch on $WORK_ID: $BRANCH is checked out in ${tree:-another worktree}, which no other unclosed bead on the branch records as its tree, so this run could not take the branch. Its run is cancelled and nothing was built. Check the tree: if a live run is using it, salvage its uncommitted and unpushed work and let that run own the bead." \
    "duplicate dispatch: $WORK_ID found $BRANCH checked out in ${tree:-another worktree}, which no other unclosed bead records"
}

checkout() { # <git checkout args...>
  local err
  if err=$(git checkout "$@" 2>&1); then
    return 0
  fi
  case "$err" in
    *"already used by worktree"*|*"already checked out at"*) yield_to_tree "$err"; return 0 ;;
  esac
  printf '%s\n' "$err" >&2
  exit 1
}

WORKTREE=$(work_meta work_dir)
CREATED_TREE=""
if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
  cd "$WORKTREE" || exit 1
else
  WORKTREE="${GC_DIR:-$PWD}/worktrees/$WORK_ID"
  RR="$SCRIPT_DIR/rig-root.sh"
  [ -x "$RR" ] || { echo "$PROG: rig-root.sh not found in the pack" >&2; exit 1; }
  RIG_ROOT=$("$RR")
  [ -n "$RIG_ROOT" ] || { echo "$PROG: cannot resolve the rig root" >&2; exit 1; }
  git -C "$RIG_ROOT" worktree add "$WORKTREE" --detach "origin/$BASE" >&2 || exit 1
  CREATED_TREE="$WORKTREE"
  cd "$WORKTREE" || exit 1
  gc bd update "$WORK_ID" --set-metadata work_dir="$WORKTREE" --set-metadata "work_holder=${GC_SESSION_ID:-}" </dev/null >/dev/null || exit 1
fi

BRANCH=$(work_meta branch)
RECORD_BRANCH=()
if [ -n "$BRANCH" ]; then
  git fetch origin "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}" >&2 \
    || echo "$PROG: could not fetch metadata.branch=$BRANCH; checking local refs" >&2
  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
      checkout "$BRANCH"
      if ! git merge --ff-only "origin/$BRANCH" >&2; then
        work_stop_with_gate polecat-branch-divergence \
          "Local $BRANCH diverged from origin/$BRANCH while resuming $WORK_ID; the two must be reconciled by hand before this work can proceed. Its run is cancelled and nothing was touched. Reconcile them." \
          "local $BRANCH diverged from origin/$BRANCH; the work waits on the reconcile"
      fi
    else
      checkout --track -b "$BRANCH" "origin/$BRANCH"
    fi
  elif git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    checkout "$BRANCH"
  else
    work_stop_with_gate polecat-missing-branch \
      "metadata.branch=$BRANCH on $WORK_ID names a branch that exists neither locally nor on origin; restore it or clear metadata.branch before this work can resume. Its run is cancelled and nothing was touched." \
      "metadata.branch=$BRANCH names a branch that exists neither locally nor on origin; the work waits on its restore"
  fi
else
  git fetch origin "$BASE" >&2 || echo "$PROG: could not fetch $BASE; cutting from the ref already here" >&2
  BRANCH="polecat/$WORK_ID"
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
  checkout -B "$BRANCH" "origin/$BASE"
  RECORD_BRANCH=(--set-metadata "branch=$BRANCH")
fi

# Every path is on the real branch here, unless HEAD is detached, which records
# no branch rather than blanking the key.
RECORD=(--set-metadata "work_dir=$(pwd)" --set-metadata "work_holder=${GC_SESSION_ID:-}" "${RECORD_BRANCH[@]+"${RECORD_BRANCH[@]}"}")
WORK_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || WORK_BRANCH=""
if [ -n "$WORK_BRANCH" ] && [ "$WORK_BRANCH" != HEAD ]; then
  RECORD+=(--set-metadata "gc.work_branch=$WORK_BRANCH")
fi
gc bd update "$WORK_ID" "${RECORD[@]}" </dev/null >/dev/null || exit 1

REJECTION=$(work_meta rejection_reason)
if [ -n "$REJECTION" ] && [ -n "$(work_meta branch)" ]; then
  echo "resuming rejected branch by MERGE (git merge --no-edit origin/$BASE); never rebase or force-push"
  RESUME_FROM=$(git rev-parse -q --verify "refs/remotes/origin/$BRANCH" || git rev-parse HEAD)
  # A conflict or stale-base rejection asks for nothing else, so a commit of the
  # bead's own is then an edit beyond the merge and owes an audit entry; any other
  # rejection carries work of its own.
  case "$REJECTION" in
    "stale base at head "*|"Conflicts with "*) RESUME_SCOPE=merge-only ;;
    *) RESUME_SCOPE=with-work ;;
  esac
  if ! gc bd update "$WORK_ID" --set-metadata "bring_current_from=$RESUME_FROM" --set-metadata "bring_current_scope=$RESUME_SCOPE" \
      --unset-metadata conflict_audit --unset-metadata conflict_question </dev/null >/dev/null; then
    echo "$PROG: the round did not land on $WORK_ID; NOT merging, since the guard reads the round from the start, and a start with no scope beside it as a resume that owes no audit. Re-run this step." >&2
    exit 1
  fi
  if git merge --no-edit "origin/$BASE" >&2; then
    gc bd update "$WORK_ID" --unset-metadata rejection_reason </dev/null >/dev/null || exit 1
  else
    if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
      echo "$PROG: the merge of origin/$BASE stopped on conflicts in:" >&2
      git diff --name-only --diff-filter=U >&2
      pwd
      exit 3
    fi
    echo "$PROG: git refused to start the merge of origin/$BASE" >&2
    exit 1
  fi
fi

pwd
exit 0
