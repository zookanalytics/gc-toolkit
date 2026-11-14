#!/usr/bin/env bash
# refinery-prep.sh — the refinery patrol's rebase step: bring one bead's branch
# current with its target by merging the target in, in a tree of the
# refinery's own.
#
#   refinery-prep.sh --bead <id> [--pool <name>]
#
# The bead is the one find-work took: open or in progress, assigned to this
# refinery ($GC_AGENT), carrying a branch. Its target is metadata.target, else
# the rig's default branch. Before it stages anything, the prep stops a gate an
# interrupted iteration left running (detached-job.sh, in the rig's
# gc-refinery-gate) and removes every tree an earlier iteration left under the
# refinery's home, since it prepares one bead at a time.
#
# It fetches the branch and the target. A target or a branch origin does not
# carry is no conflict a polecat can resolve, so the bead is parked behind a
# human gate keyed refinery-target-missing or refinery-branch-missing, with
# merge_result=blocked, and stays with the refinery: clearing the gate hands
# it back. A fetch that fails for any other reason prepares nothing.
#
# It then adds the tree for the bead (refinery-lib.sh) detached at the commit
# it read on the branch, and records that commit in the tree's
# refs/worktree/refinery/<branch>, the commit every later push onto the branch
# leases on. A bead with a rework child an earlier requeue filed and never sent
# on (refinery-lib.sh) is prepared no further: refinery-requeue.sh sends the
# child on, and the tree is removed. When the target is already in the branch,
# the branch is the prepared head as it stands, with its merges kept. Otherwise
# the target is merged in, and a merge that conflicts is aborted and sent back
# to the pool through refinery-requeue.sh with the reason "Conflicts with
# <target> at <commit>", and the tree is removed. A branch is never rebased.
#
# Exit: 0 prepared: the next step runs the gate in the tree
#       1 nothing prepared, and the work stays with the refinery to retry; the
#         output says why
#       2 usage
#       3 the merge conflicted, and the work went back to the pool, or the
#         bead's unsent rework child was sent on, or the bead left the refinery
#         before the requeue wrote
#       4 the bead is parked behind a human gate
set -uo pipefail

PROG="refinery-prep"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }

usage() { echo "usage: $PROG --bead <id> [--pool <name>]" >&2; exit 2; }
BEAD=""; POOL="gc-toolkit.polecat"
while [ $# -gt 0 ]; do
  case "$1" in
    --bead|--pool)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 needs a value" >&2; usage; }
      if [ "$1" = --bead ]; then BEAD="$2"; else POOL="$2"; fi
      shift 2 ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$BEAD" ] || usage

stop() { echo "$PROG: $1; nothing is prepared, and $BEAD stays with the refinery to retry" >&2; exit 1; }

HOME_DIR=$(refinery_home) || stop "the refinery's own worktree is unknown"
refinery_bead "$BEAD" || stop "$BEAD did not read"
STATUS=$(bead_field status)
case "$STATUS" in open|in_progress) ;; *) stop "$BEAD is ${STATUS:-of no status}, not open or in progress" ;; esac
ASSIGNEE=$(bead_field assignee)
[ -n "${GC_AGENT:-}" ] && [ "$ASSIGNEE" = "$GC_AGENT" ] || stop "$BEAD is assigned to ${ASSIGNEE:-nobody}, not this refinery (${GC_AGENT:-GC_AGENT unset})"
BRANCH=$(bead_meta branch)
[ -n "$BRANCH" ] || stop "$BEAD carries no branch"
TARGET=$(bead_meta target)
[ -n "$TARGET" ] || TARGET=$(refinery_default_branch "$HOME_DIR") || stop "$BEAD carries no target, and origin/HEAD names no default branch in $HOME_DIR"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || stop "'$BRANCH' is not a branch name"
git check-ref-format --branch "$TARGET" >/dev/null 2>&1 || stop "'$TARGET' is not a branch name"
[ "$BRANCH" != "$TARGET" ] || stop "$BEAD's branch is its own target, $TARGET"

GATE=$(refinery_gate_dir "$HOME_DIR") || stop "no repository at $HOME_DIR"
# A gate an interrupted iteration left running runs in a tree this prep
# removes, so it is stopped first. Its TERM-to-KILL grace outlasts the ten
# seconds `gctk rig` takes to stop a check's command.
if ! OUT=$(DETACHED_JOB_STOP_GRACE=20 "$HERE/detached-job.sh" stop "$GATE" 2>&1); then
  printf '%s\n' "$OUT" >&2
  stop "the gate left running in $GATE did not stop, so no tree is rebuilt under it"
fi
for LEFT in "$HOME_DIR"/worktrees/*; do
  [ -d "$LEFT" ] || continue
  refinery_teardown "$HOME_DIR" "${LEFT##*/}" || stop "a tree an earlier iteration left is still there"
done

# park <key> <reason>: the bead waits behind a human gate, with
# merge_result=blocked, still assigned to the refinery (refinery_park), and the
# gate tells a person how to stand the work down instead.
park() {
  refinery_park "$BEAD" "$1" blocked "$2" "$2 Fix that, then clear this gate: clearing it hands $BEAD back to the refinery, which prepares it again. To drop the work instead, do not clear this gate: run $HERE/stand-down.sh $BEAD --key $1 --ruling '<why>'." \
    || stop "the $1 gate on $BEAD did not land ($2)"
}

if ! FETCH=$(git -C "$HOME_DIR" fetch --no-tags origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" "+refs/heads/$TARGET:refs/remotes/origin/$TARGET" 2>&1); then
  # ls-remote --exit-code exits 2 for a ref origin does not carry, and
  # anything else for a read that did not happen.
  git -C "$HOME_DIR" ls-remote --exit-code --heads origin "refs/heads/$TARGET" >/dev/null 2>&1
  [ "$?" != 2 ] || park refinery-target-missing "$BEAD's target branch $TARGET is not on origin, so there is nothing to merge its branch $BRANCH onto. This is no conflict a polecat can resolve: set metadata.target on $BEAD to a branch origin carries, or push $TARGET."
  git -C "$HOME_DIR" ls-remote --exit-code --heads origin "refs/heads/$BRANCH" >/dev/null 2>&1
  [ "$?" != 2 ] || park refinery-branch-missing "$BEAD's branch $BRANCH is not on origin, so there is no work to prepare. Push the branch, or set metadata.branch on $BEAD to the branch that carries its work."
  stop "the fetch of $BRANCH and $TARGET failed: $(printf '%s' "$FETCH" | tr -s '[:space:]' ' ')"
fi
READ=$(git -C "$HOME_DIR" rev-parse --verify -q "refs/remotes/origin/$BRANCH^{commit}") || stop "origin/$BRANCH did not resolve after its fetch"
TIP=$(git -C "$HOME_DIR" rev-parse --verify -q "refs/remotes/origin/$TARGET^{commit}") || stop "origin/$TARGET did not resolve after its fetch"

TREE=$(refinery_tree "$HOME_DIR" "$BEAD")
mkdir -p "$HOME_DIR/worktrees" || stop "cannot make $HOME_DIR/worktrees"
# git can still register the tree's path after its directory is gone, locked
# when an add was killed partway, and a plain add refuses such a path on every
# retry. -f given twice reuses it, locked or not, and still refuses a path
# whose directory holds files, so nothing there is staged over.
if ! OUT=$(git -C "$HOME_DIR" worktree add -q -f -f --detach "$TREE" "$READ" 2>&1); then
  stop "the tree $TREE was not added: $(printf '%s' "$OUT" | tr -s '[:space:]' ' ')"
fi
git -C "$TREE" update-ref "$REFINERY_READ_NS/$BRANCH" "$READ" || stop "the commit read on $BRANCH was not recorded in $TREE"

# A rework child an earlier requeue filed for the bead and never sent on
# (refinery-lib.sh) holds the bead until it lands, so the bead is taken no
# further than sending it on. The requeue finds it on the branch and makes it
# whole, its blocks edge and its priority, before its sling.
KIDS=$(bd_json list ${GC_RIG:+--rig="$GC_RIG"} --metadata-field "anchor_bead=$BEAD" --status=open --limit=0) || KIDS=""
printf '%s' "$KIDS" | jq -e 'type == "array"' >/dev/null 2>&1 || stop "the open beads that name $BEAD as their anchor did not read"
UNSENT=$(printf '%s' "$KIDS" | jq -r --arg a "$BEAD" --arg b "$BRANCH" "$REFINERY_UNSENT_JQ"'[ .[] | select(refinery_unsent($a; $b)) | .id ] | join(", ")')
if [ -n "$UNSENT" ]; then
  echo "$PROG: $BEAD's rework child $UNSENT was filed and never sent on, so it is sent on, and $BRANCH is not merged" >&2
  "$HERE/refinery-requeue.sh" --bead "$BEAD" --reason "its rework child was filed and never sent on" --pool "$POOL"
  RQ=$?
  refinery_teardown "$HOME_DIR" "$BEAD" || echo "$PROG: the next prep removes the tree for $BEAD" >&2
  case "$RQ" in
    0|3) exit 3 ;;
    *) echo "$PROG: $BEAD's unsent rework child was not sent on (refinery-requeue.sh exit $RQ, its output above says why)" >&2
       exit 1 ;;
  esac
fi

if git -C "$TREE" merge-base --is-ancestor "$TIP" "$READ"; then
  echo "$PROG: prepared $BEAD: $BRANCH at $READ already carries $TARGET at $TIP, so it is the prepared head as it stands"
  exit 0
fi
if OUT=$(git -C "$TREE" merge --no-edit "$TIP" -m "Merge origin/$TARGET into $BRANCH ($BEAD)" 2>&1); then
  echo "$PROG: prepared $BEAD: merged $TARGET at $TIP into $BRANCH at $READ, at $(git -C "$TREE" rev-parse HEAD)"
  exit 0
fi
git -C "$TREE" merge --abort >/dev/null 2>&1 || true
REASON="Conflicts with $TARGET at $TIP"
echo "$PROG: merging $TARGET at $TIP into $BRANCH at $READ conflicts: $(printf '%s' "$OUT" | tr -s '[:space:]' ' ')" >&2
"$HERE/refinery-requeue.sh" --bead "$BEAD" --reason "$REASON" --pool "$POOL"
RQ=$?
refinery_teardown "$HOME_DIR" "$BEAD" || echo "$PROG: the next prep removes the tree for $BEAD" >&2
case "$RQ" in
  0) exit 3 ;;
  3) echo "$PROG: $BEAD left the refinery or changed status before the requeue wrote, so it is left as it is" >&2
     exit 3 ;;
  *) echo "$PROG: $BEAD's conflict with $TARGET did not go back to the pool (refinery-requeue.sh exit $RQ, its output above says why)" >&2
     exit 1 ;;
esac
