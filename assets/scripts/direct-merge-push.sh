#!/usr/bin/env bash
# direct-merge-push — the refinery's direct-mode landing: move the work bead's
# target to the prepared head as a fast-forward, verify the remote ref, and
# record and close the bead through one lifecycle transition.
#
#   direct-merge-push.sh --work <bead> --target <target-branch>
#
# The prepared head is the HEAD of the detached prep worktree the rebase step
# staged at <rig git dir>/gc-refinery-prep. It lands by commit id: the push
# names that commit as the new value of refs/heads/<target>, so nothing is
# checked out for the merge, no local branch moves, and nothing is left on disk
# to remove. git accepts a push without --force only as a fast-forward of the
# remote's own value, so the push is a fast-forward or nothing. Every git call
# names its repository with -C, and the rig root resolves from GC_RIG_ROOT or
# the roster entry for GC_RIG, never from the cwd, so a caller whose cwd sits in
# another repository cannot steer the push there.
#
# The fast-forward is checked against origin/<target> fetched first. A prepared
# head that is neither behind nor ahead of it was prepared on a target that has
# moved since. Nothing is pushed or recorded, and the exit (4) tells the caller
# that the next patrol prepares the branch again. A prepared head
# origin/<target> already carries has nothing to push and is recorded as
# landed: at the bead's direct_landing_sha when origin/<target> carries that
# too, else at the target's tip.
#
# Before the push, the commit is stamped on the bead as direct_landing_sha and
# read back, and a bead the stamp does not reach is not pushed. A landing whose
# record does not land therefore stays provable after the session that pushed
# it. The next patrol's zero-diff guard finds a branch with no change against a
# target that carries the stamped commit, and sends the bead back here, where
# it records as landed at that commit.
#
# A push that lands is read back from a fresh fetch, and the landing is
# recorded only once origin/<target> carries the pushed commit, at its tip or
# behind a commit landed after it. The read-back fetch and the transition are
# each tried DIRECT_MERGE_PUSH_ATTEMPTS times (default 3), with a pause of
# DIRECT_MERGE_PUSH_BACKOFF seconds (default 2) times the attempt between
# tries. The transition records and closes the bead and clears the stamp. It is
# handed this script's rig root as GC_RIG_ROOT, the checkout lifecycle.sh checks
# the landing in.
#
# A push refused for branch protection (GH006, GH013, "protected branch",
# "refusing to allow", "Changes must be made through a pull request",
# "approving review", "Cannot update this protected ref") landed nothing, so it
# promotes the bead to merge_strategy=pr and clears the stamp in one write, and
# exits 3: the caller takes the mr path, and the prep worktree still holds the
# prepared head for the PR push.
#
# It never drains the session; the caller decides what a failure ends.
#
# Called by mol-refinery-patrol's merge-push step when the bead's merge strategy
# is direct, or when its zero-diff guard finds a stamped landing to record.
# exit: 0 landed, verified and closed · 1 nothing landed or recorded, or a
#       landing that could not be verified or recorded (the output says which;
#       the stamp lets a later patrol record it) · 2 usage · 3 promoted to
#       merge_strategy=pr (take the mr path) · 4 origin/<target> moved after
#       the branch was prepared; nothing pushed or recorded
set -uo pipefail

PROG="direct-merge-push"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LC="$SCRIPTS_DIR/lifecycle.sh"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script; nothing landed"; exit 1; }

usage() { echo "usage: $PROG --work <bead> --target <target-branch>" >&2; exit 2; }

WORK=""; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --work|--target)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; usage; }
      if [ "$1" = --work ]; then WORK="$2"; else TARGET="$2"; fi
      shift 2 ;;
    -h|--help) usage ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$WORK" ] && [ -n "$TARGET" ] || { echo "$PROG: --work and --target are required" >&2; usage; }

ATTEMPTS="${DIRECT_MERGE_PUSH_ATTEMPTS:-3}"
case "$ATTEMPTS" in ''|*[!0-9]*|0) ATTEMPTS=3 ;; esac
BACKOFF="${DIRECT_MERGE_PUSH_BACKOFF:-2}"
case "$BACKOFF" in ''|*[!0-9]*) BACKOFF=2 ;; esac

# The rig root resolves as the patrol's blocks resolve it, so this script and
# the block that staged the prepared head name one repository.
RIG_ROOT="${GC_RIG_ROOT:-}"
[ -n "$RIG_ROOT" ] || RIG_ROOT=$(gc rig list --json | jq -r --arg r "${GC_RIG:-}" '.rigs[] | select(.name == $r) | .path')
[ -n "$RIG_ROOT" ] || { echo "cannot resolve the rig root (GC_RIG_ROOT unset, GC_RIG='${GC_RIG:-}' matched no rig in the roster); nothing landed"; exit 1; }
COMMON=$(git -C "$RIG_ROOT" rev-parse --path-format=absolute --git-common-dir) || { echo "no repository at $RIG_ROOT; nothing landed"; exit 1; }
PREP_WT="$COMMON/gc-refinery-prep"

fetch_target() { git -C "$RIG_ROOT" fetch origin "+refs/heads/${TARGET}:refs/remotes/origin/${TARGET}"; }
carries() { git -C "$RIG_ROOT" merge-base --is-ancestor "$2" "$1" 2>/dev/null; }
# retry <command>...: the command, run until it succeeds or has run ATTEMPTS times.
retry() {
  local n=1
  until "$@"; do
    [ "$n" -lt "$ATTEMPTS" ] || return 1
    sleep $((BACKOFF * n))
    n=$((n + 1))
  done
}
# shellcheck disable=SC2329  # run through retry
record() {
  GC_RIG_ROOT="$RIG_ROOT" "$LC" transition "$WORK" --to merged --close --set merged_sha="$MERGED_SHA" --set merged_target="$TARGET" --unset rejection_reason --unset direct_landing_sha --append-notes "Merged to $TARGET at $(git -C "$RIG_ROOT" rev-parse --short "$MERGED_SHA")"
}

fetch_target || { echo "could not fetch origin/$TARGET; nothing landed"; exit 1; }
PREPARED=$(git -C "$PREP_WT" rev-parse --verify -q HEAD) || { echo "no prepared head in $PREP_WT; nothing landed"; exit 1; }
TIP=$(git -C "$RIG_ROOT" rev-parse --verify -q "refs/remotes/origin/$TARGET") || { echo "origin/$TARGET did not resolve after its fetch; nothing landed"; exit 1; }
STAMP=""
if carries "$TIP" "$PREPARED"; then
  STAMP=$(row_meta "$(bd_json show "$WORK")" direct_landing_sha)
  if [ -n "$STAMP" ] && carries "$TIP" "$STAMP"; then
    MERGED_SHA="$STAMP"
  else
    STAMP=""
    MERGED_SHA="$TIP"
  fi
  echo "origin/$TARGET at $TIP already carries the prepared head $PREPARED, so nothing is pushed; recording the landing at $MERGED_SHA"
elif carries "$PREPARED" "$TIP"; then
  MERGED_SHA="$PREPARED"
  if ! SHORT=$(bd_meta_ensure "$WORK" "$(jq -nc --arg s "$MERGED_SHA" '{direct_landing_sha: $s}')"); then
    echo "could not stamp direct_landing_sha=$MERGED_SHA on $WORK (short: ${SHORT:-unknown}), and without it a landing whose record failed would read as a branch with no work; nothing pushed"
    exit 1
  fi
  STAMP="$MERGED_SHA"
  if ! PUSH_OUT=$(git -C "$RIG_ROOT" push origin "$MERGED_SHA:refs/heads/$TARGET" 2>&1); then
    case "$PUSH_OUT" in
      *GH006*|*GH013*|*"protected branch"*|*"refusing to allow"*|*"Changes must be made through a pull request"*|*"approving review"*|*"Cannot update this protected ref"*)
        echo "Direct push to '$TARGET' rejected (protected branch). Auto-promoting to merge_strategy=pr."
        gc bd update "$WORK" --set-metadata merge_strategy=pr --unset-metadata direct_landing_sha || { echo "could not record merge_strategy=pr on $WORK; nothing landed"; exit 1; }
        exit 3 ;;
    esac
    echo "Push failed: $PUSH_OUT. STOP. Debug and retry; do NOT continue."
    exit 1
  fi
  retry fetch_target || { echo "PUSH UNVERIFIED — could not re-fetch origin/$TARGET after the push. STOP; do not mutate bead state. $WORK keeps direct_landing_sha=$STAMP, so a later patrol records the landing once origin/$TARGET reads back carrying it."; exit 1; }
  REMOTE=$(git -C "$RIG_ROOT" rev-parse --verify -q "refs/remotes/origin/$TARGET")
  if [ -z "$REMOTE" ] || ! carries "$REMOTE" "$MERGED_SHA"; then
    echo "PUSH FAILED — origin/$TARGET is ${REMOTE:-unresolved}, which does not carry $MERGED_SHA. STOP; do not mutate bead state."
    exit 1
  fi
elif git -C "$RIG_ROOT" merge-base "$PREPARED" "$TIP" >/dev/null 2>&1; then
  echo "the prepared head $PREPARED is not a fast-forward of origin/$TARGET at $TIP, which moved after the branch was prepared; nothing pushed or recorded, so the next patrol prepares the branch again"
  exit 4
else
  echo "the prepared head $PREPARED and origin/$TARGET at $TIP share no history; nothing pushed or recorded"
  exit 1
fi

if ! retry record; then
  echo "origin/$TARGET carries $MERGED_SHA, so $WORK has landed, but the transition recording it as merged did not land (lifecycle.sh's output above says why)${STAMP:+; $WORK keeps direct_landing_sha=$STAMP, so the next patrol records the landing}"
  exit 1
fi
exit 0
