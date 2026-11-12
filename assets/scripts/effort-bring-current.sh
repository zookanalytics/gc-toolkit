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
# A merge that conflicts is a decision, and the refinery never resolves one: it
# pushes nothing, puts the conflict to a person in a human gate on the hand-off
# keyed bring-current-conflict, and records the notice (deferred-dispatch.sh
# notify) that hands the hand-off back to the refinery once the gate clears.
# Once a person has pushed the merge, nothing is left to merge, and the next
# call closes the hand-off.
#
# The repository is the refinery's own worktree ($GC_DIR), a worktree of the
# rig's clone.
#
# Exit: 0 brought current and closed · 1 nothing pushed or closed, and a call
#       again retries; the output says why · 2 usage · 3 the hand-off is not
#       ready: it is closed, or a blocker is still open · 4 the merge conflicts,
#       and a person rules on it through the gate
set -uo pipefail

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

refinery_bead "$H" || stop "$H did not read"
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
  TREE=$(git -C "$REPO_DIR" merge-tree --write-tree --no-messages --name-only "$OURS" "$THEIRS")
  case $? in
    0) ;;
    1)
      FILES=$(printf '%s\n' "$TREE" | sed 1d | tr '\n' ' ' | sed 's/ $//')
      "$HERE/human-gate.sh" --subject "$H" --key bring-current-conflict --message "Merging origin/$TARGET at $THEIRS into $BRANCH at $OURS conflicts in: $FILES. The refinery resolves no conflict, so it pushed nothing. Merge $TARGET into $BRANCH, resolving those files, and push the branch, then clear this gate: the refinery takes $H again, finds nothing left to merge and closes it." >/dev/null \
        || stop "merging origin/$TARGET into $BRANCH conflicts in $FILES, and the bring-current-conflict gate on $H did not land"
      "$HERE/deferred-dispatch.sh" notify "$H" --agent "${GC_AGENT:-}" >/dev/null \
        || echo "$PROG: the notice that hands $H back once its gate clears did not land; assign $H to the refinery again by hand" >&2
      echo "$PROG: merging origin/$TARGET into $BRANCH conflicts in $FILES; pushed nothing, and $H waits on its bring-current-conflict gate"
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
