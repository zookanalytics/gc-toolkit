#!/usr/bin/env bash
# effort-bring-current.sh — the refinery's hand-off that brings an integration
# effort's branch current with its target.
#
#   effort-bring-current.sh --hand-off <id> --landing <id>
#
# A hand-off is a task assigned to the refinery that names the effort's landing
# bead. It is no landing: it moves work the target already carries into the
# effort's branch, never the reverse, so no check or review runs on it. The
# hand-off must be open with every bead that blocks it closed, and the landing
# bead must record an integration/<id> branch and a target.
#
# The branch is fast-forwarded to its target when it holds nothing the target
# lacks, and otherwise takes a merge of the target, made in the rig's
# repository without checking anything out, so nothing is left to remove. The
# merge commit is signed when the repository's commit.gpgSign says so, as
# `git merge` would sign it. A branch already current is pushed as it is. The
# push goes under the lease on the commit read on the branch (branch-push.sh),
# so a push someone made after the read is never overwritten, and the hand-off
# closes once the push has landed, which releases the bead waiting on it.
#
# A merge that conflicts is a polecat's to resolve, never the refinery's and
# never the operator's. The call pushes nothing and files the merge as a task on
# the effort's branch, under the hand-off's parent when it has one, which the
# hand-off and the landing bead wait on. It proves the polecat pool's route
# first (pool-route.sh), so a pool no agent claims files nothing. The task's
# create records the branch as its target and direct as its merge strategy. The
# call then settles the task and slings it to the pool on mol-polecat-work with
# --merge direct, because a sling otherwise stamps the rig's default merge
# strategy over it. The hand-off stays assigned to the refinery while it waits
# on the task, so Gas City nudges the refinery about it once the task lands. The
# task lands as a fast-forward of the effort's branch, so the polecat's merge
# commit reaches the branch as it is. A pull request lands by squash, which
# would leave the target's commits out of the branch's history, so the hand-off
# would meet the same conflict each time it came back. A create can write the
# task and still answer no id, so the call then looks for the task among what
# the hand-off waits on. A call that stops after it filed the task names the
# step that did not land, and a call again finds the hand-off waiting on the
# task and brings nothing current. Once the task lands, nothing is left to
# merge, and the next call closes the hand-off.
#
# The repository is the refinery's own worktree ($GC_DIR), a worktree of the
# rig's clone.
#
# Exit: 0 brought current and closed · 1 nothing pushed or closed; the output
#       says why, and names the step to finish from once the conflict's task is
#       filed, where a call again would bring nothing current · 2 usage · 3 the
#       hand-off is not ready: it is closed, or a blocker is still open · 4 the
#       merge conflicts, and the task the call sent has a polecat resolve it
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

PROG="effort-bring-current"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }

usage() { echo "usage: $PROG --hand-off <id> --landing <id>" >&2; exit 2; }
H=""; LANDING=""
while [ $# -gt 0 ]; do
  case "$1" in
    --hand-off|--landing)
      [ "$#" -ge 2 ] || usage
      if [ "$1" = --hand-off ]; then H="$2"; else LANDING="$2"; fi
      shift 2 ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$H" ] && [ -n "$LANDING" ] || usage

stop() { echo "$PROG: $1; nothing is brought current" >&2; exit 1; }
halt() { echo "$PROG: $1" >&2; exit 1; }
POOL="gc-toolkit.polecat"

refinery_bead "$H" || stop "$H did not read"
HJ=$BEAD_ROW
printf '%s' "$BEAD_ROW" | jq -e '.[0] | .status != "closed" and all(.dependencies[]?; .dependency_type != "blocks" or .status == "closed")' >/dev/null 2>&1 \
  || { echo "$PROG: $H does not read as open with every blocker closed, so nothing is brought current" >&2; exit 3; }
refinery_bead "$LANDING" || stop "$LANDING did not read"
BRANCH=$(bead_meta branch)
TARGET=$(bead_meta target)
case "$BRANCH" in integration/?*) ;; *) stop "$LANDING records no integration branch" ;; esac
[ -n "$TARGET" ] || stop "$LANDING records no target"

REPO_DIR=$(refinery_home) || stop "the refinery's own worktree is unknown"
git -C "$REPO_DIR" fetch --no-tags origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" "+refs/heads/$TARGET:refs/remotes/origin/$TARGET" >/dev/null 2>&1 \
  || stop "origin/$BRANCH and origin/$TARGET did not fetch"
OURS=$(git -C "$REPO_DIR" rev-parse --verify -q "refs/remotes/origin/$BRANCH^{commit}") || stop "origin carries no $BRANCH"
THEIRS=$(git -C "$REPO_DIR" rev-parse --verify -q "refs/remotes/origin/$TARGET^{commit}") || stop "origin carries no $TARGET"

NEW="$THEIRS"
if git -C "$REPO_DIR" merge-base --is-ancestor "$THEIRS" "$OURS"; then
  NEW="$OURS"
elif ! git -C "$REPO_DIR" merge-base --is-ancestor "$OURS" "$THEIRS"; then
  TREE=$(git -C "$REPO_DIR" -c core.quotePath=false merge-tree --write-tree --no-messages --name-only "$OURS" "$THEIRS")
  case $? in
    0) ;;
    1)
      FILES=$(printf '%s\n' "$TREE" | sed 1d)
      LIST=$(printf '%s\n' "$FILES" | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')
      ROUTE=$("$HERE/pool-route.sh" "$POOL") \
        || halt "pushed nothing: merging origin/$TARGET into $BRANCH conflicts in $LIST, and the pool $POOL resolves to no route, so no task was filed for it (pool-route.sh says why above); call again once it does"
      EPIC=$(printf '%s' "$HJ" | jq -r '[.[0].dependencies[]? | select(.dependency_type == "parent-child") | .id][0] // empty' 2>/dev/null)
      PARENT=(); [ -z "$EPIC" ] || PARENT=(--parent "$EPIC")
      TITLE="Merge origin/$TARGET into $BRANCH and resolve its conflicts"
      BRIEF="The refinery's hand-off $H could not bring $BRANCH, the branch of $LANDING, current with $TARGET: merging origin/$TARGET at $THEIRS into it at $OURS conflicts in these files, one per line:

$FILES

It pushed nothing, and $H waits on this task.

Merge origin/$TARGET into this task's branch, which is cut from $BRANCH, and resolve each conflict by keeping what each side meant. Make one merge commit whose second parent is origin/$TARGET, and never rebase or squash it, so that once it lands on $BRANCH the refinery finds nothing left to merge and closes $H. In its message, say for each file what collided and what you decided. The diff against $BRANCH holds all that $TARGET gained since the branch was cut, and your change is the resolution: run git show --remerge-diff on the merge to see only the hunks resolved by hand. Your checks run on the merged tree, and a check that reads a diff reads all of it. A check that fails the same way at origin/$TARGET is a failure of $TARGET's own, so treat it as pre-existing, as your self-review step says of a failure on its base.

When your resolution keeps $BRANCH's side of every file $TARGET changed, so that git diff --quiet origin/$BRANCH HEAD exits 0, the merge leaves the tree of $BRANCH as it is. The refinery refuses a landing that changes no file and puts the task to a person. Say so in the notes you hand off with, and name the merge commit, because pushing it to $BRANCH as a fast-forward and closing this task lands it.

The conflict is yours to resolve. Ask the operator only when a resolution needs a product decision, because the two sides want different behavior and nothing written settles which. Then ask through a human gate on this task with nothing pushed, as your prompt's section on blocked work and human gates says."
      TASK=$(gc bd create "$TITLE" -t task ${PARENT[@]+"${PARENT[@]}"} -d "$BRIEF" \
        --metadata "$(jq -nc --arg t "$BRANCH" '{target: $t, merge_strategy: "direct"}')" --deps "blocks:$H,blocks:$LANDING" --json </dev/null \
        | scrub | jq -r 'if type == "array" then .[0].id else .id end // empty' 2>/dev/null)
      if [ -z "$TASK" ]; then
        TASK=$(gc bd show "$H" --json </dev/null | scrub \
          | jq -er --arg t "$TITLE" '[.[0].dependencies[]? | select(.dependency_type == "blocks" and .status != "closed" and .title == $t) | .id] | if length < 2 then .[0] // "" else error("more than one") end' 2>/dev/null) \
          || halt "pushed nothing: merging origin/$TARGET into $BRANCH conflicts in $LIST. The create of its task returned no id, and reading $H did not settle whether the create wrote it. gc bd show $H lists what it waits on: finish from the settle with the open task titled \"$TITLE\", or call again when it waits on none"
        [ -n "$TASK" ] || halt "pushed nothing: merging origin/$TARGET into $BRANCH conflicts in $LIST, and the create of its task wrote nothing; call again"
      fi
      "$HERE/queue-priority.sh" settle "$TASK" </dev/null >/dev/null \
        || halt "pushed nothing and filed $TASK for the conflict in $LIST, but $TASK was not settled, so it was not sent; finish from the settle"
      gc sling "$ROUTE" "$TASK" --on mol-polecat-work --merge direct </dev/null >/dev/null \
        || halt "pushed nothing, filed $TASK for the conflict in $LIST and settled it, but its sling exited non-zero; finish from the send"
      echo "$PROG: pushed nothing: merging origin/$TARGET into $BRANCH conflicts in $LIST, so $TASK sends the merge to a polecat, and $H comes back to the refinery once $TASK lands"
      exit 4 ;;
    *) stop "git merge-tree could not merge origin/$TARGET into $BRANCH" ;;
  esac
  SIGN=--no-gpg-sign
  [ "$(git -C "$REPO_DIR" config --type=bool commit.gpgSign 2>/dev/null)" != true ] || SIGN=-S
  NEW=$(git -C "$REPO_DIR" commit-tree "$SIGN" "$TREE" -p "$OURS" -p "$THEIRS" -m "Merge origin/$TARGET into $BRANCH ($H)") \
    || stop "the merge commit of origin/$TARGET into $BRANCH was not made"
fi
"$HERE/branch-push.sh" --repo "$REPO_DIR" --branch "$BRANCH" --head "$NEW" --from "$OURS" >&2 \
  || stop "the push of $NEW onto $BRANCH did not land (branch-push.sh says why above); call again to read the branch afresh"
gc bd close "$H" --reason "Brought $BRANCH current with $TARGET at $(git -C "$REPO_DIR" rev-parse --short "$NEW")" </dev/null >/dev/null \
  || stop "$BRANCH holds $NEW, but $H did not close; call again, which finds nothing left to merge and closes it"
echo "$PROG: brought $BRANCH current with $TARGET at $NEW and closed $H"
