#!/bin/sh
# worktree-setup.sh — provision an agent's home, the git worktree its sessions
# start in.
#
# Usage: worktree-setup.sh <rig-root> <target-dir> <agent-name> [--sync]
#
# Ensures <target-dir> is a git worktree of the rig repo, on a per-target
# branch cut from the remote default-branch tip, with the bead redirect and
# local excludes an agent needs (provision_worktree). Called from agent
# pre_start (agents/*/agent.toml) before the session exists, so the agent
# starts IN the worktree. An existing worktree is never re-created: it gets
# whatever provisioning it lacks, and --sync moves it to the default-branch
# tip at every start, saving first what the move would lose (sync_worktree).
#
# docs/warrants.md, "Agent home provisioning", says why a home is not a
# `gc worktree` tree.

set -eu

RIG_ROOT="${1:?usage: worktree-setup.sh <rig-root> <target-dir> <agent-name> [--sync]}"
WT="${2:?missing target-dir}"
AGENT="${3:?missing agent-name}"
SYNC="${4:-}"

# What an agent needs in its worktree beyond the checkout: the bead redirect,
# submodule config, and the runtime excludes. Every write is skipped when it is
# already in place, so this runs after a fresh add and on every later run. A
# worktree an earlier run left half-built is completed by the next one: git
# keeps the worktree when a checkout hook fails the add, and a run killed
# between the add and these writes leaves the same state. Only a linked
# worktree (.git is a file) is provisioned. A main checkout's .beads is the
# rig's own store, not a pointer to one, so it never gets a redirect.
provision_worktree() {
    [ -f "$WT/.git" ] || return 0

    # Bead redirect for filesystem beads. A non-empty one is kept, so a
    # deliberate redirect survives.
    mkdir -p "$WT/.beads"
    if [ ! -s "$WT/.beads/redirect" ]; then
        echo "$RIG_ROOT/.beads" > "$WT/.beads/redirect"
    fi

    git -C "$WT" submodule init 2>/dev/null || true

    # Runtime ignores live in git metadata (--git-path resolves the exclude file
    # for linked-worktree layouts), never in the tracked .gitignore. git shares
    # that file among all of a repo's worktrees, the rig checkout included, so
    # these rules hide gc's writes there too. A worktree whose git metadata git
    # cannot find has no exclude file to write, and git cannot stage anything
    # from it either.
    EXCLUDE=$(git -C "$WT" rev-parse --git-path info/exclude) || return 0
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
    # gc links each skill into .agents/skills/ for Codex and pi, one symlink per
    # skill, and records each link's name in an ownership manifest beside them.
    # A person can keep files, links and skills of their own in that directory,
    # so only the manifest and the names it records are hidden, each by its
    # exact path. The names come from this worktree's manifest and the rig
    # checkout's, so a link gc adds later shows until the next run reads it.
    # Lines are only ever added, so a name gc drops stays hidden.
    append_exclude ".agents/skills/.gc-skill-ownership.json"
    exclude_skill_links "$WT"
    exclude_skill_links "$RIG_ROOT"
    # Session start stages the city's .gc/settings.json into every Claude
    # session's work dir, and bd's workspace gate sits beside .beads, outside it.
    append_exclude ".gc/"
    append_exclude ".beads.gate.lock"
}

append_exclude() {
    PATTERN="$1"
    grep -qxF "$PATTERN" "$EXCLUDE" 2>/dev/null || printf '%s\n' "$PATTERN" >> "$EXCLUDE"
}

# exclude_skill_links <checkout> — hides each skill link whose name the
# ownership manifest in <checkout>/.agents/skills/ records. git reads each
# line of the exclude file as a pattern, so a name is taken only when it is
# letters, digits, dots, dashes and underscores, which git matches literally.
# The match is anchored with \A and \z, because jq's $ also matches before a
# final newline, and a name ending in one would reach the file as another name.
# Any other name stays visible rather than risk a pattern that hides a
# person's file. A missing or unreadable manifest, or no jq, adds nothing.
exclude_skill_links() {
    MANIFEST="$1/.agents/skills/.gc-skill-ownership.json"
    [ -f "$MANIFEST" ] || return 0
    NAMES=$(jq -r '.targets | keys[] | select(test("\\A[A-Za-z0-9._-]+\\z") and . != "." and . != "..")' \
        "$MANIFEST" 2>/dev/null) || return 0
    printf '%s\n' "$NAMES" | while IFS= read -r NAME; do
        [ -n "$NAME" ] || continue
        append_exclude ".agents/skills/$NAME"
    done
}

# A home holds no work of its own, so --sync moves it to the remote default
# branch's tip at every start, on its per-target branch, whatever a session did
# to it. What the move would lose is saved first, under
# refs/gc-toolkit/home-save/<per-target branch>/<UTC time>/, and never on the
# stash stack, which every worktree of the repository shares, so another
# session's pop could take it. HEAD's commits are saved as head. The move resets
# the per-target branch, so when that branch points at another commit than HEAD,
# its commits are saved as branch. Neither is saved when another branch, a tag
# or a remote-tracking ref holds every commit it reaches.
#
# The move keeps each tracked change and untracked file it does not overwrite.
# gc writes provider settings into a home before pre_start runs, and in a rig
# that tracks such a file, gc's merge is a tracked change the session needs.
# When git refuses because the move would overwrite a tracked change or an
# untracked file, the tracked changes are saved as changes and the move is
# forced. A move that still fails ends the run non-zero, so the session does not
# start and gc reports git's error. Only a linked worktree moves, since a main
# checkout is the rig's own.
sync_worktree() {
    [ "$SYNC" = "--sync" ] || return 0
    [ -f "$WT/.git" ] || return 0
    if ! git -C "$WT" remote get-url origin >/dev/null 2>&1; then
        return 0
    fi

    git -C "$WT" fetch origin 2>/dev/null || true

    DEFAULT_REF=$(git -C "$WT" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || {
        printf 'worktree-setup: cannot sync %s: origin/HEAD is unset\n' "$WT" >&2
        exit 1
    }
    BRANCH=$(branch_name)
    SAVE="refs/gc-toolkit/home-save/$BRANCH/$(date -u +%Y%m%dT%H%M%SZ)"
    HEAD_COMMIT=$(git -C "$WT" rev-parse HEAD)
    OWN_COMMIT=$(git -C "$WT" rev-parse -q --verify "refs/heads/$BRANCH") || OWN_COMMIT=""
    save_if_alone head "$HEAD_COMMIT"
    [ "$OWN_COMMIT" = "$HEAD_COMMIT" ] || save_if_alone branch "$OWN_COMMIT"

    move 2>/dev/null && return 0
    CHANGES=$(GIT_AUTHOR_NAME=worktree-setup GIT_AUTHOR_EMAIL=worktree-setup@localhost \
        GIT_COMMITTER_NAME=worktree-setup GIT_COMMITTER_EMAIL=worktree-setup@localhost \
        git -C "$WT" stash create "worktree-setup: tracked changes in $WT before its move") || exit 1
    [ -z "$CHANGES" ] || save changes "$CHANGES"
    move -f || exit 1
}

# save_if_alone <name> <commit> — saves <commit> as <name> when a commit it
# reaches is held by no branch but the per-target one, no tag and no
# remote-tracking ref, or when git cannot say.
save_if_alone() {
    [ -n "$2" ] || return 0
    ALONE=$(git -C "$WT" rev-list -n 1 "$2" --not --exclude="$BRANCH" --branches --remotes --tags 2>/dev/null) || ALONE=unread
    [ -z "$ALONE" ] || save "$1" "$2"
}

# save <name> <commit> — pins <commit> at $SAVE/<name>. The empty old value
# makes the ref create-only, so no earlier save is replaced.
save() {
    git -C "$WT" update-ref -m "worktree-setup: saved before moving $WT to $DEFAULT_REF" "$SAVE/$1" "$2" "" || exit 1
}

# move [-f] — puts the worktree on its per-target branch at the default tip.
# Hooks are off, because a hook's exit status becomes the checkout's, and a move
# that carried a change over but read as failed would then be forced over it.
# --no-track leaves the upstream the worktree was created with, since setting it
# rewrites the repository's config, which every worktree shares.
move() {
    GIT_LFS_SKIP_SMUDGE=1 git -c core.hooksPath=/dev/null -C "$WT" checkout -q "$@" --no-track -B "$BRANCH" "$DEFAULT_REF"
}

branch_name() {
    # Namespace by target path so multiple cities/rigs can share one repo
    # without colliding on global refs.
    HASH=$(printf '%s' "$WT" | git -C "$RIG_ROOT" hash-object --stdin | cut -c1-12)
    printf 'gc-%s-%s' "$AGENT" "$HASH"
}

mkdir -p "$(dirname "$WT")"

STAGE=""

merge_stage_entry() (
    SRC="$1"
    DST="$2"

    if [ -d "$SRC" ]; then
        # A staged directory loses to an existing non-directory at the same
        # path: the existing file wins, so drop the whole losing source subtree.
        # Recursing would mkdir over the file, which fails and ends the run.
        if [ -e "$DST" ] && [ ! -d "$DST" ]; then
            rm -rf "$SRC"
            exit 0
        fi
        mkdir -p "$DST"
        for ENTRY in "$SRC"/.[!.]* "$SRC"/..?* "$SRC"/*; do
            [ -e "$ENTRY" ] || continue
            merge_stage_entry "$ENTRY" "$DST/$(basename "$ENTRY")"
        done
        rmdir "$SRC" 2>/dev/null || true
        exit 0
    fi

    # Existing destination wins; drop the losing source. Leaving it would keep
    # the stage dir non-empty, so the rmdir in restore_stage would leave it behind.
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

# Idempotent: an existing worktree is provisioned and synced, never re-created.
if [ -d "$WT/.git" ] || [ -f "$WT/.git" ]; then
    provision_worktree
    sync_worktree
    exit 0
fi

# A non-empty target that is not yet a worktree: stage its contents aside,
# create the worktree, then merge them back (existing files win).
if [ -d "$WT" ] && [ "$(find "$WT" -mindepth 1 -maxdepth 1 | head -n 1)" ]; then
    STAGE=$(mktemp -d "$(dirname "$WT")/.gascity-worktree-stage.XXXXXX")
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

provision_worktree
sync_worktree

exit 0
