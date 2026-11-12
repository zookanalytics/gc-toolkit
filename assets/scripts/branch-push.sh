#!/usr/bin/env bash
# branch-push.sh — push a commit onto a branch on origin under git's lease on the
# commit the writer read there, and never force it.
#
#   branch-push.sh --repo <dir> --branch <branch> --head <commit>
#                  (--from <commit> | --new | --from-origin)
#
# --from names the commit the writer read on origin's <branch>, and --new says
# the writer read no such branch. --from-origin reads the branch on origin now
# (git ls-remote) and takes what it reads as the writer's read, for a writer
# that holds no earlier read of its own. The push goes under
# `--force-with-lease=refs/heads/<branch>:<from>`, or `refs/heads/<branch>:` for
# a branch that must not exist yet. git's client reads the branch on the server
# again when it pushes, and the lease makes it send the update only while the
# branch still holds the commit the writer read, so a push someone made after
# that read is refused, never overwritten. A lease that matches also lets git
# send an update that is not a fast-forward, so the script first checks that
# <head> descends from <from>, and sends nothing when it does not. With that
# check the lease never forces.
#
# The lease names the commit the writer read, never the remote-tracking ref
# that every worktree's fetch moves. A push whose answer never reached its
# writer can still land only while the branch holds that commit, so a retry
# that reads the branch afresh never overwrites it either.
#
# <dir> is the repository the push runs in, and its origin is the remote. Every
# git call names it with -C, so the caller's cwd plays no part.
#
# Exit: 0 pushed, or the branch already holds <head>
#       1 the push failed for another reason, <head> or <from> is not a
#         commit in <dir>, or --from-origin's read did not answer; the output
#         says which
#       2 usage
#       3 the branch moved after the writer read it, so nothing landed
#       4 <head> does not descend from <from>, so nothing was sent
set -uo pipefail

PROG="branch-push"
usage() {
  echo "usage: $PROG --repo <dir> --branch <branch> --head <commit> (--from <commit> | --new | --from-origin)" >&2
  exit 2
}

REPO=""; BRANCH=""; HEAD_REF=""; FROM=""; NEW=""; ORIGIN_READ=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--branch|--head|--from)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 needs a value" >&2; usage; }
      case "$1" in
        --repo)   REPO="$2" ;;
        --branch) BRANCH="$2" ;;
        --head)   HEAD_REF="$2" ;;
        *)        FROM="$2" ;;
      esac
      shift 2 ;;
    --new) NEW=1; shift ;;
    --from-origin) ORIGIN_READ=1; shift ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$REPO" ] && [ -n "$BRANCH" ] && [ -n "$HEAD_REF" ] || { echo "$PROG: --repo, --branch and --head are required" >&2; usage; }
MODES=0
for MODE in "$FROM" "$NEW" "$ORIGIN_READ"; do [ -z "$MODE" ] || MODES=$((MODES + 1)); done
[ "$MODES" = 1 ] || { echo "$PROG: name the commit read on $BRANCH with one of --from, --new or --from-origin" >&2; usage; }
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || { echo "$PROG: '$BRANCH' is not a branch name" >&2; exit 2; }
if [ -n "$ORIGIN_READ" ]; then
  # ls-remote --exit-code exits 2 for a branch origin does not carry, and
  # anything else for a read that did not answer.
  LS=$(git -C "$REPO" ls-remote --exit-code --heads origin "refs/heads/$BRANCH" 2>&1)
  case $? in
    0) FROM=$(printf '%s' "$LS" | awk 'NR == 1 { print $1 }') ;;
    2) NEW=1 ;;
    *) echo "$PROG: $BRANCH on origin did not read: $(printf '%s' "$LS" | tr -s '[:space:]' ' '); nothing was sent" >&2; exit 1 ;;
  esac
fi

HEAD_OID=$(git -C "$REPO" rev-parse --verify -q "${HEAD_REF}^{commit}") \
  || { echo "$PROG: '$HEAD_REF' is not a commit in $REPO; nothing was sent" >&2; exit 1; }
if [ -n "$FROM" ]; then
  FROM_OID=$(git -C "$REPO" rev-parse --verify -q "${FROM}^{commit}") \
    || { echo "$PROG: '$FROM', the commit read on $BRANCH, is not a commit in $REPO; nothing was sent" >&2; exit 1; }
  if ! git -C "$REPO" merge-base --is-ancestor "$FROM_OID" "$HEAD_OID"; then
    echo "$PROG: $HEAD_OID does not descend from $FROM_OID, the commit read on $BRANCH, so pushing it would rewrite the branch; nothing was sent" >&2
    exit 4
  fi
  LEASE="refs/heads/$BRANCH:$FROM_OID"
  READ="$FROM_OID"
else
  LEASE="refs/heads/$BRANCH:"
  READ="no branch"
fi

if OUT=$(git -C "$REPO" push --porcelain --force-with-lease="$LEASE" origin "$HEAD_OID:refs/heads/$BRANCH" 2>&1); then
  echo "$PROG: $BRANCH on origin holds $HEAD_OID"
  exit 0
fi
SAID=$(printf '%s' "$OUT" | tr -s '[:space:]' ' ' | sed 's/ $//')
case "$OUT" in
  *"stale info"*|*"incorrect old value"*)
    echo "$PROG: $BRANCH on origin moved after the writer read $READ there, so nothing landed: $SAID" >&2
    exit 3 ;;
esac
echo "$PROG: the push of $HEAD_OID onto $BRANCH failed: ${SAID:-git said nothing}" >&2
exit 1
