#!/usr/bin/env bash
# convoy-seed — stand up an owned integration convoy in one worker-run act:
# create the convoy, set its target to integration/<convoy-id>, and cut+push
# that branch from a DISPOSABLE worktree. Encapsulates the owned-convoy
# hand-recipe so a worker performs it in place of a person.
#
# The disposable worktree is load-bearing: reconcile keeps the rig root
# fast-forwarded to the default branch and directory-imported packs build from
# its working tree, so a branch checkout or commit there would park the deploy
# off the default branch. The branch is cut in a throwaway worktree under
# mktemp and the rig root's working tree is never moved.
#
# Idempotent for resume: an already-created convoy is reused when its id is
# supplied with --convoy, and the branch cut is skipped when origin already
# carries the branch.
#
# Usage:
#   convoy-seed.sh --name <initiative> [--convoy <id>] [--id-file <path>]
#                  [--artifact <src> [--artifact-dest <repo-rel-path>]
#                   --artifact-message <msg>]
#                  [--rig-root <path>] [--json]
#
# --id-file <path> receives the convoy id the instant the convoy is created,
# before the fallible target-set and branch cut. A caller that records it can
# resume against this convoy after a crash instead of creating a second one.
#
# Output (stdout): convoy_id and branch, one per line, or a JSON object with
# --json:
#   convoy_id=<id>
#   branch=integration/<id>
set -u

PROG="convoy-seed"
die() { echo "$PROG: $*" >&2; exit 1; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

NAME=""
CONVOY_ID=""
IDFILE=""
ARTIFACT=""
ARTIFACT_DEST=""
ARTIFACT_MSG=""
RIG_ROOT="${GC_RIG_ROOT:-}"
JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --name)             NAME="${2:-}"; shift 2 ;;
    --convoy)           CONVOY_ID="${2:-}"; shift 2 ;;
    --id-file)          IDFILE="${2:-}"; shift 2 ;;
    --artifact)         ARTIFACT="${2:-}"; shift 2 ;;
    --artifact-dest)    ARTIFACT_DEST="${2:-}"; shift 2 ;;
    --artifact-message) ARTIFACT_MSG="${2:-}"; shift 2 ;;
    --rig-root)         RIG_ROOT="${2:-}"; shift 2 ;;
    --json)             JSON=1; shift ;;
    *)                  die "unknown argument: $1" ;;
  esac
done

[ -n "$NAME" ] || die "--name <initiative> is required"

# Resolve the rig root the git operations bind to. An empty -C runs against cwd,
# which is the coupling the disposable worktree exists to avoid, so fail closed.
[ -n "$RIG_ROOT" ] || RIG_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$RIG_ROOT" ] || die "cannot resolve rig root (GC_RIG_ROOT unset, cwd is not a git repo); pass --rig-root"
git -C "$RIG_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "rig root '$RIG_ROOT' is not a git repository"

RIG_FLAG=()
[ -n "${GC_RIG:-}" ] && RIG_FLAG=(--rig "$GC_RIG")

# 1. Create the owned convoy, unless a caller supplied an existing id (resume).
if [ -z "$CONVOY_ID" ]; then
  CREATE_JSON=$(gc convoy create "$NAME" "${RIG_FLAG[@]}" --owned --json 2>/dev/null) \
    || die "gc convoy create failed for '$NAME'"
  CONVOY_ID=$(printf '%s' "$CREATE_JSON" | scrub | jq -r '.convoy_id // .id // empty' 2>/dev/null)
  [ -n "$CONVOY_ID" ] || die "gc convoy create returned no convoy id (output: $CREATE_JSON)"
fi

# Persist the resolved convoy id the instant it exists — before the fallible
# target-set and branch cut below — so a caller that records it resumes against
# this convoy after a crash rather than creating a second owned convoy.
[ -n "$IDFILE" ] && { printf '%s\n' "$CONVOY_ID" > "$IDFILE" || die "could not write --id-file '$IDFILE'"; }

BRANCH="integration/$CONVOY_ID"

# 2. Set the convoy target, which gc sling takes as the base of a child that
#    names no target of its own and reports the convoy as its parent. Setting
#    the same target again is a no-op, so this is safe to re-run on resume.
gc convoy target "$CONVOY_ID" "$BRANCH" "${RIG_FLAG[@]}" >/dev/null 2>&1 \
  || die "gc convoy target failed for $CONVOY_ID -> $BRANCH"

# 3. Cut and push the integration branch, unless origin already carries it.
git -C "$RIG_ROOT" fetch --prune origin >/dev/null 2>&1 \
  || die "git fetch failed in $RIG_ROOT"

if ! git -C "$RIG_ROOT" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  # Cut from the refreshed default-branch tip — resolved, never hardcoded.
  DEFAULT_REF=$(git -C "$RIG_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
  DEFAULT_BRANCH=${DEFAULT_REF#refs/remotes/origin/}
  [ -n "$DEFAULT_BRANCH" ] && [ "$DEFAULT_BRANCH" != "$DEFAULT_REF" ] || DEFAULT_BRANCH="main"
  git -C "$RIG_ROOT" fetch origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
  git -C "$RIG_ROOT" show-ref --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH" \
    || die "default branch origin/$DEFAULT_BRANCH not found to cut $BRANCH from"

  SEED_DIR=$(mktemp -d "${TMPDIR:-/tmp}/convoy-seed.XXXXXX") || die "mktemp failed"
  SEED="$SEED_DIR/wt"
  # Tear the throwaway worktree down on any exit so a failure leaks nothing. The
  # cut below is detached and never creates a local integration branch, so there
  # is no branch ref to drop here.
  cleanup() {
    git -C "$RIG_ROOT" worktree remove --force "$SEED" >/dev/null 2>&1 || true
    rm -rf "$SEED_DIR" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  # Cut DETACHED, never `-b <branch>`. A named local branch left checked out in a
  # worktree a hard crash leaks cannot be deleted (git refuses a checked-out
  # branch) and then blocks the retry's own re-creation of it. A detached worktree
  # holds no branch ref, so a leaked one collides with nothing and the push below
  # writes HEAD straight to refs/heads/<branch>.
  git -C "$RIG_ROOT" worktree add "$SEED" --detach "origin/$DEFAULT_BRANCH" >/dev/null 2>&1 \
    || die "worktree add failed from origin/$DEFAULT_BRANCH"

  # A shared input artifact starts the branch ahead of default. A design-convoy
  # seeds nothing, so the branch starts equal to the default branch.
  if [ -n "$ARTIFACT" ]; then
    [ -f "$ARTIFACT" ] || die "artifact '$ARTIFACT' is not a file"
    DEST="$ARTIFACT_DEST"
    [ -n "$DEST" ] || DEST=$(basename "$ARTIFACT")
    case "$DEST" in
      /*|*..*) die "artifact dest '$DEST' must be a repo-relative path with no '..'" ;;
    esac
    mkdir -p "$SEED/$(dirname "$DEST")" || die "could not create artifact dir for $DEST"
    cp "$ARTIFACT" "$SEED/$DEST" || die "could not copy artifact to $DEST"
    git -C "$SEED" add -- "$DEST" || die "git add failed for $DEST"
    git -C "$SEED" commit -m "${ARTIFACT_MSG:-chore: seed integration branch $BRANCH}" >/dev/null 2>&1 \
      || die "git commit failed for the seed artifact"
  fi

  git -C "$SEED" push origin "HEAD:refs/heads/$BRANCH" >/dev/null 2>&1 \
    || die "push failed for $BRANCH"

  cleanup
  trap - EXIT
fi

if [ "$JSON" -eq 1 ]; then
  jq -cn --arg c "$CONVOY_ID" --arg b "$BRANCH" '{convoy_id:$c, branch:$b}'
else
  printf 'convoy_id=%s\nbranch=%s\n' "$CONVOY_ID" "$BRANCH"
fi
