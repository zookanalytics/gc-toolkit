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
# whatever provisioning it lacks, and --sync fast-forwards it to the
# default-branch tip at every start, or fails the start and reports what in
# the home stopped it (sync_worktree).
#
# docs/warrants.md, "Agent home provisioning", says why a home is not a
# `gc worktree` tree.

set -eu

RIG_ROOT="${1:?usage: worktree-setup.sh <rig-root> <target-dir> <agent-name> [--sync]}"
WT="${2:?missing target-dir}"
AGENT="${3:?missing agent-name}"
SYNC="${4:-}"
FINDING="${GC_PATROL_FINDING_TOOL:-$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/patrol-finding.sh}"

# What gc writes into a home, one gitignore pattern per line: the bead redirect
# and bd's files beside it, each provider's settings, hooks and skills, runtime
# state and logs, the per-bead worktrees under the home, the city settings
# session start stages under .gc/, and the marker the worker-dir prune leaves
# in a home it keeps. The skill links an ownership manifest records join them
# (gc_writes). provision_worktree hides each from git status, and sync_worktree
# counts none of them as an edit.
GC_WRITES='.beads/redirect
.beads/hooks/
.beads/formulas/
.runtime/
.logs/
worktrees/
__pycache__/
.claude/
.codex/
.gemini/
.opencode/
.github/hooks/
.github/copilot-instructions.md
state.json
.agents/skills/.gc-skill-ownership.json
.gc/
.beads.gate.lock
.worktree-stale'

# The provider settings files gc merges its hooks into, Gas City's
# mergeablePaths. In a rig that tracks one of them, gc's merge is a tracked
# change in every home, so sync_worktree does not count it as an edit.
GC_MERGED='.agents/hooks.json
.claude/settings.json
.gemini/settings.json
.codex/hooks.json
.cursor/hooks.json
.github/hooks/gascity.json'

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

    gc_writes | while IFS= read -r PATTERN; do
        [ -n "$PATTERN" ] || continue
        grep -qxF "$PATTERN" "$EXCLUDE" 2>/dev/null || printf '%s\n' "$PATTERN" >> "$EXCLUDE"
    done
}

# gc_writes — GC_WRITES, then each skill link gc records in the ownership
# manifest of this worktree and of the rig checkout, one pattern per line.
gc_writes() {
    printf '%s\n' "$GC_WRITES"
    skill_links "$WT"
    skill_links "$RIG_ROOT"
}

# skill_links <checkout> — gc links each skill into .agents/skills/ for Codex
# and pi, one symlink per skill, and records each link's name in an ownership
# manifest beside them. A person can keep files, links and skills of their own
# in that directory, so only the names the manifest records are gc's, each by
# its exact path. A link gc adds later counts once a run reads it, and the
# exclude file only gains lines, so a name gc drops stays hidden. git reads
# each line as a pattern, so a name is taken only when it is letters, digits,
# dots, dashes and underscores, which git matches literally. The match is
# anchored with \A and \z, because jq's $ also matches before a final newline,
# and a name ending in one would reach git as another name. Any other name
# stays visible rather than risk a pattern that hides a person's file. A
# missing or unreadable manifest, or no jq, gives no name.
skill_links() {
    MANIFEST="$1/.agents/skills/.gc-skill-ownership.json"
    [ -f "$MANIFEST" ] || return 0
    NAMES=$(jq -r '.targets | keys[] | select(test("\\A[A-Za-z0-9._-]+\\z") and . != "." and . != "..")' \
        "$MANIFEST" 2>/dev/null) || return 0
    [ -z "$NAMES" ] || printf '%s\n' "$NAMES" | sed 's#^#.agents/skills/#'
}

# --sync brings a home to the remote default branch's tip at every start. A
# home is gc's, so what a session leaves in it is a sign of a bug: a session
# that moved the home, committed in it or edited it. The sync then saves,
# discards and forces nothing. It reports what it found through
# patrol-finding.sh, one report per home, and exits non-zero, so the session
# does not start. The next start that finds the home clean records that the
# report has cleared.
#
# A home on its own branch fast-forwards to the tip. A detached home whose HEAD
# the tip contains moves there too, back onto its own branch when that branch
# fast-forwards to the tip, and otherwise detached at the tip. Anything else
# fails the start: a commit the tip lacks, a branch not the home's own, a
# rebase, merge or other operation stopped partway, a change to a tracked file
# other than gc's merge into a provider settings file, an untracked file gc did
# not write, and a fast-forward git refuses. A failed fetch leaves the last tip
# fetched. Only a linked worktree syncs, since a main checkout is the rig's
# own, and a repository with no origin is left alone.
sync_worktree() {
    [ "$SYNC" = "--sync" ] || return 0
    [ -f "$WT/.git" ] || return 0
    if ! git -C "$WT" remote get-url origin >/dev/null 2>&1; then
        return 0
    fi

    git -C "$WT" fetch origin 2>/dev/null || true

    BRANCH=$(branch_name)
    FOUND=""; FIX=""; DETAIL=""
    if ! DEFAULT_REF=$(git -C "$WT" symbolic-ref -q refs/remotes/origin/HEAD) \
        || ! git -C "$WT" rev-parse -q --verify "$DEFAULT_REF^{commit}" >/dev/null; then
        found "an origin/HEAD that names no commit, so no default branch to move to" \
            "set it with git -C '$WT' remote set-head origin --auto"
        report
    fi
    TIP=${DEFAULT_REF#refs/remotes/}
    check_operation
    check_head
    check_changes
    [ -z "$FOUND" ] || report

    if ! ERR=$(fast_forward 2>&1); then
        if [ -n "$CURRENT" ]; then MOVE="merge --ff-only origin/HEAD"; else MOVE="checkout --detach origin/HEAD"; fi
        found "a fast-forward to $TIP that git refused" \
            "clear what git names below, then make the move by hand with git -C '$WT' $MOVE, since a file gc writes comes back before the next start's sync"
        DETAIL=$ERR
        report
    fi
    "$FINDING" --key "$(report_key)" --scope home-sync --cleared \
        --message "$WT started clean at $TIP" >/dev/null 2>&1 || true
}

# found <what> <how to clear it> — records one thing that keeps the home from
# starting.
found() {
    FOUND="${FOUND:+$FOUND; }$1"
    FIX="${FIX:+$FIX; }$2"
}

# check_operation — a rebase, git am, merge, cherry-pick, revert or bisect that
# a session left stopped partway.
check_operation() {
    OPS=""
    for STATE in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD sequencer BISECT_LOG; do
        F=$(git -C "$WT" rev-parse --path-format=absolute --git-path "$STATE") || continue
        [ ! -e "$F" ] || OPS="${OPS:+$OPS, }$STATE"
    done
    [ -z "$OPS" ] || found "a git operation stopped partway ($OPS)" \
        "finish or abort it, as git -C '$WT' status says"
}

# check_head — a HEAD the tip does not contain, or a branch not the home's own.
# The move that clears a commit the tip lacks is also the one a rewrite of the
# default branch, such as a fork's rebase, asks of every home in the rig.
check_head() {
    CURRENT=$(git -C "$WT" symbolic-ref -q --short HEAD) || CURRENT=""
    if ! git -C "$WT" rev-parse -q --verify 'HEAD^{commit}' >/dev/null; then
        found "a HEAD that names no commit" \
            "check out the tip with git -C '$WT' checkout --detach origin/HEAD"
        return 0
    fi
    if [ -n "$CURRENT" ] && [ "$CURRENT" != "$BRANCH" ]; then
        found "branch $CURRENT checked out, not its own $BRANCH" \
            "switch it back with git -C '$WT' switch $BRANCH"
    fi
    if ! git -C "$WT" merge-base --is-ancestor HEAD "$DEFAULT_REF" 2>/dev/null; then
        AHEAD=$(git -C "$WT" rev-list --count HEAD --not "$DEFAULT_REF" 2>/dev/null) || AHEAD="?"
        found "commits $TIP lacks on its HEAD ($AHEAD, newest $(git -C "$WT" rev-parse --short HEAD))" \
            "keep what they hold elsewhere, then move it with git -C '$WT' checkout --detach origin/HEAD, the step that moves every home of a rig whose default branch was rewritten"
    fi
}

# check_changes — a change to a tracked file other than gc's merge into a
# provider settings file, and an untracked file gc did not write. Each pattern
# gc writes reaches git as a command-line exclude, which outranks a .gitignore
# that re-includes one of those paths.
check_changes() {
    set --
    while IFS= read -r P; do
        [ -z "$P" ] || set -- "$@" ":(exclude)$P"
    done <<EOF
$GC_MERGED
EOF
    TRACKED=$(git -C "$WT" status --porcelain --untracked-files=no --no-renames -- . "$@") || {
        TRACKED=""
        found "git status failing in it" "repair it until git -C '$WT' status runs"
    }
    set --
    while IFS= read -r P; do
        [ -z "$P" ] || set -- "$@" "--exclude=$P"
    done <<EOF
$(gc_writes)
EOF
    UNTRACKED=$(git -C "$WT" ls-files --others --exclude-standard --directory --no-empty-directory "$@") || {
        UNTRACKED=""
        found "git failing to list its untracked files" "repair it until git -C '$WT' status runs"
    }
    [ -z "$TRACKED" ] || found "changes to files git tracks ($(listing "$(printf '%s\n' "$TRACKED" | cut -c4-)"))" \
        "keep what matters elsewhere and discard the changes with git -C '$WT' reset --hard"
    [ -z "$UNTRACKED" ] || found "files git does not track ($(listing "$UNTRACKED"))" \
        "move or remove the untracked files"
}

# listing <lines> — the first five lines, joined by commas, and how many more.
listing() {
    printf '%s\n' "$1" | awk 'NR <= 5 { out = out (NR > 1 ? ", " : "") $0 }
        END { if (NR > 5) out = out ", and " (NR - 5) " more"; print out }'
}

# fast_forward — moves the home to the tip, as the checks leave it: on its own
# branch, or detached on a commit the tip contains. A detached home is done
# once its HEAD is the tip, since a post-checkout hook's exit status becomes
# the checkout's after the checkout has moved the home.
fast_forward() {
    if [ -n "$CURRENT" ]; then
        git -C "$WT" merge -q --ff-only "$DEFAULT_REF"
        return
    fi
    if ! git -C "$WT" show-ref --verify --quiet "refs/heads/$BRANCH" \
        || git -C "$WT" merge-base --is-ancestor "refs/heads/$BRANCH" "$DEFAULT_REF" 2>/dev/null; then
        GIT_LFS_SKIP_SMUDGE=1 git -C "$WT" checkout -q --track -B "$BRANCH" "$DEFAULT_REF" || true
    fi
    at_tip || GIT_LFS_SKIP_SMUDGE=1 git -C "$WT" checkout -q --detach "$DEFAULT_REF" || at_tip
}

at_tip() {
    [ "$(git -C "$WT" rev-parse HEAD)" = "$(git -C "$WT" rev-parse "$DEFAULT_REF^{commit}")" ]
}

# report — files what keeps this home from starting, one report per home, and
# ends the run non-zero, so the session does not start. A report that does not
# land still fails the start, and gc keeps the run's output in its error.
report() {
    MESSAGE="$WT did not start, because its sync found $FOUND. To clear it, $FIX. The next start that finds it clean clears this report."
    [ -z "$DETAIL" ] || MESSAGE="$MESSAGE

$DETAIL"
    "$FINDING" --key "$(report_key)" --scope home-sync --priority 1 \
        --title "Agent home $AGENT did not start: ${FOUND%%; *}" --message "$MESSAGE" >&2 \
        || printf 'worktree-setup: the report on %s did not land\n' "$WT" >&2
    printf 'worktree-setup: %s\n' "$MESSAGE" >&2
    exit 1
}

# report_key — the home's report key, from its per-target branch, which names
# the agent and carries a hash of the home's path.
report_key() {
    printf 'home-sync.%s' "$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._-' '-')"
}

branch_name() {
    # Namespace by target path so multiple cities/rigs can share one repo
    # without colliding on global refs.
    HASH=$(printf '%s' "$WT" | git -C "$RIG_ROOT" hash-object --stdin | cut -c1-12)
    printf 'gc-%s-%s' "$AGENT" "$HASH"
}

mkdir -p "$(dirname "$WT")"

# The stage dir beside the home holds what the home held while git adds the
# worktree, each move in a numbered set of its own, and SETS counts the sets.
STAGE=""
SETS=0

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

# restore_stage — merges every set back into the home, the newest first, and
# removes the stage dir once it is empty. What the home already holds wins over
# every set, so a file the checkout brought stays, and a newer set wins over an
# older one, because a later rewrite is gc's current content.
restore_stage() {
    [ -n "$STAGE" ] || return 0
    mkdir -p "$WT"
    while [ "$SETS" -gt 0 ]; do
        for ENTRY in "$STAGE/$SETS"/.[!.]* "$STAGE/$SETS"/..?* "$STAGE/$SETS"/*; do
            [ -e "$ENTRY" ] || continue
            merge_stage_entry "$ENTRY" "$WT/$(basename "$ENTRY")"
        done
        rmdir "$STAGE/$SETS" 2>/dev/null || true
        SETS=$((SETS - 1))
    done
    rmdir "$STAGE" 2>/dev/null || true
    STAGE=""
}

# stage_home — moves what the home holds into a new set and removes the emptied
# home, because git adds a worktree only where nothing is. Once anything is
# staged, the run's exit restores it, and a signal ends the run, so the grace gc
# gives a stopped pre_start goes to the restore and not to another attempt.
stage_home() {
    if [ -d "$WT" ] && [ -n "$(find "$WT" -mindepth 1 -maxdepth 1 | head -n 1)" ]; then
        if [ -z "$STAGE" ]; then
            STAGE=$(mktemp -d "$(dirname "$WT")/.gascity-worktree-stage.XXXXXX")
            trap 'restore_stage' EXIT
            trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
        fi
        SETS=$((SETS + 1))
        mkdir "$STAGE/$SETS"
        find "$WT" -mindepth 1 -maxdepth 1 -exec mv {} "$STAGE/$SETS"/ \;
    fi
    rmdir "$WT" 2>/dev/null || true
}

# home_came_back — whether, after a failed add, the home is a directory again
# with no .git, as a writer that re-creates it leaves it. An add that fails
# after git has made the worktree leaves its .git, and is not tried again.
home_came_back() {
    [ -d "$WT" ] && [ ! -e "$WT/.git" ]
}

# add_worktree — adds the home on its per-target branch, which is cut from the
# default tip when it does not exist yet. A failed add can leave the branch it
# made, so every attempt checks for it again.
add_worktree() {
    if git -C "$RIG_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
        GIT_LFS_SKIP_SMUDGE=1 git -C "$RIG_ROOT" worktree add "$WT" "$BRANCH"
        return
    fi
    # argv, not a command string, so paths with whitespace survive.
    set -- worktree add "$WT" -b "$BRANCH"
    if [ -n "$DEFAULT_REF" ]; then
        set -- "$@" "$DEFAULT_REF"
    fi
    GIT_LFS_SKIP_SMUDGE=1 git -C "$RIG_ROOT" "$@"
}

# Idempotent: an existing worktree is provisioned and synced, never re-created.
if [ -d "$WT/.git" ] || [ -f "$WT/.git" ]; then
    provision_worktree
    sync_worktree
    exit 0
fi

# What can wait on the network or a busy host runs while the home still holds
# its files, so nothing between the home's emptying and the add waits on it.
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

# A home that is not yet a worktree holds what gc staged for the start. Its
# contents move aside, git adds the worktree, and they merge back. gc writes
# into the home each time it builds the city's desired state, so a build can
# re-create the home before the add, and git then refuses it. What the build
# wrote moves aside as another set, and the add runs again after a pause
# longer than a build's writes take, up to ADD_ATTEMPTS adds in all.
ADD_ATTEMPTS=3
ATTEMPT=1
stage_home
until add_worktree; do
    if [ "$ATTEMPT" -ge "$ADD_ATTEMPTS" ] || ! home_came_back; then
        echo "worktree-setup: failed to create worktree at $WT from $RIG_ROOT (branch $BRANCH)" >&2
        restore_stage
        exit 1
    fi
    ATTEMPT=$((ATTEMPT + 1))
    printf 'worktree-setup: %s was written to again before the add, so what it holds is staged as well and the add runs again (attempt %s of %s)\n' \
        "$WT" "$ATTEMPT" "$ADD_ATTEMPTS" >&2
    sleep 1
    stage_home
done

restore_stage
trap - EXIT HUP INT TERM

provision_worktree
sync_worktree

exit 0
