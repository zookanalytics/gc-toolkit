#!/bin/sh
# worktree-setup.sh — idempotent git worktree creation for Gas City agents.
#
# Usage: worktree-setup.sh <rig-root> <target-dir> <agent-name> [--sync]
#
# Ensures <target-dir> is a git worktree of the rig repo, on a per-target
# branch cut from the remote default-branch tip. Called from agent pre_start
# (agents/*/agent.toml) before the session exists, so the agent starts IN the
# worktree. Existing worktrees are left alone; --sync fast-forwards them.

set -eu

RIG_ROOT="${1:?usage: worktree-setup.sh <rig-root> <target-dir> <agent-name> [--sync]}"
WT="${2:?missing target-dir}"
AGENT="${3:?missing agent-name}"
SYNC="${4:-}"

rebase_in_progress() {
    for STATE in rebase-merge rebase-apply; do
        DIR=$(git -C "$WT" rev-parse --git-path "$STATE" 2>/dev/null) || DIR=""
        if [ -n "$DIR" ] && [ -d "$DIR" ]; then
            return 0
        fi
    done
    return 1
}

sync_worktree() {
    [ "$SYNC" = "--sync" ] || return 0
    if ! git -C "$WT" remote get-url origin >/dev/null 2>&1; then
        return 0
    fi

    # Clear a conflicted index left by an earlier cycle; --abort restores the
    # branch tip, so no commit is at risk.
    if rebase_in_progress; then
        git -C "$WT" rebase --abort 2>/dev/null || true
    fi
    if git -C "$WT" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
        git -C "$WT" merge --abort 2>/dev/null || true
    fi

    git -C "$WT" fetch origin 2>/dev/null || true

    # Fast-forward only, never replay local commits: a `pull --rebase` replays
    # shed commits onto every fetched tip and parks the worktree mid-rebase.
    UPSTREAM=$(git -C "$WT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || return 0
    [ -n "$UPSTREAM" ] || return 0

    # A branch that cannot fast-forward is left as it stands, by design.
    git -C "$WT" merge --ff-only "$UPSTREAM" >/dev/null 2>&1 || true
}

branch_name() {
    # Namespace by target path so multiple cities/rigs can share one repo
    # without colliding on global refs.
    HASH=$(printf '%s' "$WT" | git -C "$RIG_ROOT" hash-object --stdin | cut -c1-12)
    printf 'gc-%s-%s' "$AGENT" "$HASH"
}

mkdir -p "$(dirname "$WT")"

# Stage dirs carry their target's name so a later run can tell its own orphaned
# stage (safe to reclaim) from another target's — the parent directory is
# shared by every agent in the rig, so the name is the only attribution.
STAGE_SLUG=$(printf '%s' "$(basename "$WT")" | tr -c 'A-Za-z0-9_-' '_')
STAGE=""

merge_stage_entry() (
    SRC="$1"
    DST="$2"

    if [ -d "$SRC" ]; then
        mkdir -p "$DST"
        for ENTRY in "$SRC"/.[!.]* "$SRC"/..?* "$SRC"/*; do
            [ -e "$ENTRY" ] || continue
            merge_stage_entry "$ENTRY" "$DST/$(basename "$ENTRY")"
        done
        rmdir "$SRC" 2>/dev/null || true
        exit 0
    fi

    # Existing destination wins; drop the losing source. Leaving it would keep
    # the stage/orphan dir non-empty, so the rmdir that reclaims it (here and in
    # restore_stage / adopt_orphan_stages) silently fails and the dir leaks.
    if [ -e "$DST" ]; then
        rm -f "$SRC"
        exit 0
    fi
    mv "$SRC" "$DST"
)

restore_stage() {
    [ -n "$STAGE" ] || return 0
    mkdir -p "$WT"
    for ENTRY in "$STAGE"/.[!.]* "$STAGE"/..?* "$STAGE"/*; do
        [ -e "$ENTRY" ] || continue
        merge_stage_entry "$ENTRY" "$WT/$(basename "$ENTRY")"
    done
    rmdir "$STAGE" 2>/dev/null || true
    STAGE=""
}

# Reclaim a stage dir a force-killed run left behind: its EXIT trap never ran,
# so nothing else merges it back and the staged contents are lost forever.
# Before touching the worktree — including on the already-a-worktree sync path
# below, where surviving orphans actually accumulate — reclaim any orphan this
# target can prove is its own, merging it back with the same "existing files
# win" rule restore_stage uses. Attribution lives entirely in the name, because
# the parent directory is shared by every agent in the rig:
#   - "<this-target>.XXXXXX": this target's own scoped orphan — adopt it.
#   - "<other-target>.XXXXXX": another target's scoped stage — leave it; it may
#     be that target's live, in-flight stage and its contents are not ours.
#   - "XXXXXX" with no target segment: a legacy orphan from before stages were
#     scoped. Nothing can prove which target created it, so adopting it into
#     whichever target runs first leaks one target's files into another. Such
#     unscoped names can no longer be created, so it is always old debris, never
#     a live stage — quarantine it out of the stage namespace with its contents
#     intact, for an attribution-aware manual sweep, and let no target claim it.
# Best-effort self-heal; it must never block worktree creation.
adopt_orphan_stages() {
    PARENT=$(dirname "$WT")
    [ -d "$PARENT" ] || return 0
    for ORPHAN in "$PARENT"/.gascity-worktree-stage.*; do
        [ -d "$ORPHAN" ] || continue
        REST=${ORPHAN##*/}
        REST=${REST#.gascity-worktree-stage.}
        case "$REST" in
            "$STAGE_SLUG".*) ;;   # this target's own scoped orphan — adopt below
            *.*) continue ;;      # another target's scoped stage — may be live, leave it
            *)                    # legacy un-scoped orphan — unprovable owner, quarantine it
                QUARANTINE="$PARENT/.gascity-worktree-orphan.$REST"
                if [ ! -e "$QUARANTINE" ] && mv "$ORPHAN" "$QUARANTINE" 2>/dev/null; then
                    echo "worktree-setup: quarantined unattributable legacy stage dir ${ORPHAN##*/} as ${QUARANTINE##*/} (owning target unknown; reclaim manually)" >&2
                fi
                continue ;;
        esac
        mkdir -p "$WT"
        for ENTRY in "$ORPHAN"/.[!.]* "$ORPHAN"/..?* "$ORPHAN"/*; do
            [ -e "$ENTRY" ] || continue
            merge_stage_entry "$ENTRY" "$WT/$(basename "$ENTRY")"
        done
        rmdir "$ORPHAN" 2>/dev/null || true
    done
}
adopt_orphan_stages || true

# Idempotent: an existing worktree is only synced.
if [ -d "$WT/.git" ] || [ -f "$WT/.git" ]; then
    sync_worktree
    exit 0
fi

# A non-empty target that is not yet a worktree: stage its contents aside,
# create the worktree, then merge them back (existing files win).
if [ -d "$WT" ] && [ "$(find "$WT" -mindepth 1 -maxdepth 1 | head -n 1)" ]; then
    STAGE=$(mktemp -d "$(dirname "$WT")/.gascity-worktree-stage.$STAGE_SLUG.XXXXXX")
    find "$WT" -mindepth 1 -maxdepth 1 -exec mv {} "$STAGE"/ \;
    trap 'restore_stage' EXIT HUP INT TERM
fi

rmdir "$WT" 2>/dev/null || true
git -C "$RIG_ROOT" worktree prune >/dev/null 2>&1 || true

BRANCH=$(branch_name)

# Cut the worktree branch from the refreshed remote default-branch tip, never
# from a stale local default branch — feature branches cut from a lagging tip
# carry already-merged commits the refinery rebase rejects.
DEFAULT_REF=$(git -C "$RIG_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
if [ -n "$DEFAULT_REF" ]; then
    DEFAULT_BRANCH=${DEFAULT_REF#refs/remotes/origin/}
    git -C "$RIG_ROOT" fetch origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
fi

if git -C "$RIG_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    if ! GIT_LFS_SKIP_SMUDGE=1 git -C "$RIG_ROOT" worktree add "$WT" "$BRANCH"; then
        echo "worktree-setup: failed to create worktree at $WT from $RIG_ROOT (branch $BRANCH)" >&2
        restore_stage
        exit 1
    fi
else
    # argv, not a command string, so paths with whitespace survive.
    set -- worktree add "$WT" -b "$BRANCH"
    if [ -n "$DEFAULT_REF" ]; then
        set -- "$@" "$DEFAULT_REF"
    fi
    if ! GIT_LFS_SKIP_SMUDGE=1 git -C "$RIG_ROOT" "$@"; then
        echo "worktree-setup: failed to create worktree at $WT from $RIG_ROOT (branch $BRANCH)" >&2
        restore_stage
        exit 1
    fi
fi

if [ -n "$STAGE" ]; then
    for ENTRY in "$STAGE"/.[!.]* "$STAGE"/..?* "$STAGE"/*; do
        [ -e "$ENTRY" ] || continue
        merge_stage_entry "$ENTRY" "$WT/$(basename "$ENTRY")"
    done
    rm -rf "$STAGE"
    STAGE=""
fi
trap - EXIT HUP INT TERM

# Bead redirect for filesystem beads.
mkdir -p "$WT/.beads"
echo "$RIG_ROOT/.beads" > "$WT/.beads/redirect"

git -C "$WT" submodule init 2>/dev/null || true

# Runtime ignores live in git metadata (--git-path resolves the exclude file
# for linked-worktree layouts), never in the tracked .gitignore.
EXCLUDE=$(git -C "$WT" rev-parse --git-path info/exclude)
case "$EXCLUDE" in
    /*) ;;
    *) EXCLUDE="$WT/$EXCLUDE" ;;
esac
mkdir -p "$(dirname "$EXCLUDE")"
touch "$EXCLUDE"

MARKER="# Gas City worktree infrastructure (local excludes)"
if ! grep -qF "$MARKER" "$EXCLUDE" 2>/dev/null; then
    if [ -s "$EXCLUDE" ] && [ "$(tail -c 1 "$EXCLUDE" 2>/dev/null || true)" != "" ]; then
        printf '\n' >> "$EXCLUDE"
    fi
    printf '%s\n' "$MARKER" >> "$EXCLUDE"
fi

append_exclude() {
    PATTERN="$1"
    grep -qxF "$PATTERN" "$EXCLUDE" 2>/dev/null || printf '%s\n' "$PATTERN" >> "$EXCLUDE"
}

append_exclude ".beads/redirect"
append_exclude ".beads/hooks/"
append_exclude ".beads/formulas/"
append_exclude ".runtime/"
append_exclude ".logs/"
append_exclude "worktrees/"
append_exclude "__pycache__/"
append_exclude ".claude/"
append_exclude ".codex/"
append_exclude ".gemini/"
append_exclude ".opencode/"
append_exclude ".github/hooks/"
append_exclude ".github/copilot-instructions.md"
append_exclude "state.json"

sync_worktree

exit 0
