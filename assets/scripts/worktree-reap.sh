#!/usr/bin/env bash
# worktree-reap.sh — remove the per-bead worktrees and local branches that
# finished work leaves behind in a rig checkout.
#
# A polecat pours a worktree at <session-worktree>/worktrees/<bead-id> on
# branch polecat/<bead-id>, pushes, and drains. Nothing takes either one back.
# GitHub's delete_branch_on_merge clears the remote branch and the refinery
# closes the bead, so the local clone is the one place where a finished item
# leaves scaffolding, and the scaffolding is where the disk goes.
#
# Two gates, in this order, and the order is the point. A closed bead is the
# authority: the refinery closes a work bead only from merge-push on a verified
# merge, so closure IS the statement that the work landed. Tip-reachability
# from the default branch is the confirmation, not the gate — the merge is a
# squash, so a branch whose content is in main reads as unmerged. Gating on
# reachability alone would refuse nearly everything it should take.
#
# What holds a worktree:
#   - the bead named by its directory is open, in_progress or blocked
#   - it holds content that exists nowhere else: a modification, an addition,
#     an untracked file
#   - a running process has its cwd inside it
#   - the rig's ledger did not answer (an empty open-bead list is the
#     signature of a store that is down, not of a rig with no work)
#
# A pure deletion does NOT hold a worktree. The content is in HEAD, so nothing
# is lost by removing the directory, and holding on one costs the whole reclaim
# for an old tree: a file deleted from the default branch leaves every worktree
# cut before that commit permanently dirty. `git worktree remove` refuses a
# dirty tree, which is why the removal below passes --force.
#
# Branch deletion is gated separately, because a branch outlives its worktree,
# and it owns one family: polecat/<bead-id>. A branch that names no bead is
# left alone whatever its merge state. A polecat/<bead-id> branch is held while
# its bead is open, in_progress or blocked — a tip already merged into the
# default branch does not make a live work item's local ref disposable. Once
# the bead is no longer live the branch goes: when its tip is an ancestor of
# the default branch (git's own definition of merged), or when the bead id
# appears in a commit message there — the squash commit, which is what "the
# content landed" looks like after a squash-merge, since the branch's own
# commits never become ancestors.
#
# Scope is the per-bead worktree shape and that branch family. An agent's own
# session worktree, a review worktree under /tmp, the rig checkout, and any
# branch that names no bead are left alone.
#
# Usage:
#   worktree-reap.sh              reap every non-HQ rig, print one line each
#   worktree-reap.sh --dry-run    report the plan, touch nothing
#   worktree-reap.sh --rig <name> one rig only
# Env: WORKTREE_REAP_BUDGET (seconds, default 480).
# Exit: 0 reaped or nothing to do · 2 usage.
# Caller: the worktree-reap exec order. See docs/worktree-reclaim.md.
set -euo pipefail

PROG="${0##*/}"
DRY_RUN=0
ONLY_RIG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --rig) shift; ONLY_RIG="${1:-}"; [ -n "$ONLY_RIG" ] || { echo "$PROG: --rig needs a name" >&2; exit 2; } ;;
        --rig=*) ONLY_RIG="${1#--rig=}" ;;
        *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

BUDGET="${WORKTREE_REAP_BUDGET:-480}"
case "$BUDGET" in
    '' | *[!0-9]*) echo "$PROG: WORKTREE_REAP_BUDGET must be a whole number of seconds" >&2; exit 2 ;;
esac

START=$(date +%s)
over_budget() { [ "$BUDGET" -gt 0 ] && [ $(($(date +%s) - START)) -ge "$BUDGET" ]; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A bead id as it appears in a directory name or a commit message: two letters,
# a dash, and an optional .N suffix for a bead split off another.
BEAD_RE='[a-z][a-z]-[a-z0-9]+(\.[0-9]+)?'

# Processes with a cwd on disk. One walk, and `-printf %l` reads each symlink
# without following it, so a host with thousands of processes costs one command
# rather than one per process. Best-effort and quiet: most of /proc belongs to
# other uids and reads back empty, which is the expected case, not an error.
# The signal is one-directional — a worktree nobody is standing in owns no
# entry — so it only ever protects.
# find exits non-zero on the /proc entries it cannot read, which is most of
# them, so its status is collected and discarded rather than piped: under
# pipefail a fallback on the pipeline would empty the file on every host and
# leave this guard silently inert. An unreadable entry prints an empty target,
# which matches no worktree path.
: > "$WORK/cwds"
find /proc -mindepth 2 -maxdepth 2 -name cwd -printf '%l\n' > "$WORK/cwds" 2>/dev/null || true
sort -u -o "$WORK/cwds" "$WORK/cwds" 2>/dev/null || true

# True when a live process stands in <path> or below it.
occupied() { # <path>
    local cwd
    while IFS= read -r cwd; do
        case "$cwd" in "$1" | "$1"/*) return 0 ;; esac
    done < "$WORK/cwds"
    return 1
}

# True when the worktree holds content that exists nowhere else. Every status
# line must be a deletion — ' D' unstaged, 'D ' staged; anything else is
# content this directory is the only copy of. A status that cannot be read
# holds the worktree too.
holds_unique_content() { # <worktree-path>
    local out line
    out="$(git -C "$1" status --porcelain 2>/dev/null)" || return 0
    [ -n "$out" ] || return 1
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "${line:0:2}" in " D" | "D ") ;; *) return 0 ;; esac
    done <<< "$out"
    return 1
}

gib() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1073741824 }'; }

# Delete a branch and report whether the ref actually went. A swallowed refusal
# would otherwise count as a deletion, which is how a pass reports a reclaim it
# did not make.
drop_branch() { # <repo> <branch>
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi
    git -C "$1" branch -D "$2" >/dev/null 2>&1 || true
    ! git -C "$1" show-ref --verify --quiet "refs/heads/$2"
}

TOTAL_WT=0; TOTAL_BR=0; TOTAL_KB=0; TOTAL_HELD=0; YIELDED=""

reap_rig() { # <rig-name> <rig-path>
    local rig="$1" repo="$2"
    local default_ref open_json wt_removed=0 wt_held=0 br_removed=0 freed_kb=0

    git -C "$repo" fetch --prune --quiet origin 2>/dev/null || true

    default_ref="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
    if ! git -C "$repo" rev-parse --verify --quiet "$default_ref" >/dev/null 2>&1; then
        echo "$PROG: $rig — no $default_ref to gate against; skipped"
        return 0
    fi

    # The ledger, read once. Fail closed twice over: a lookup that errors is
    # not an all-clear, and neither is an empty answer — a Dolt store that is
    # down answers "no work" in exactly that shape, and every bead would then
    # read as closed.
    open_json="$(gc bd --rig "$rig" list --status open,in_progress,blocked --limit 0 --json 2>/dev/null)" || open_json=""
    if ! printf '%s' "$open_json" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        echo "$PROG: $rig — ledger returned no open beads; holding everything (a store that is down answers the same way)"
        return 0
    fi
    printf '%s' "$open_json" | jq -r '.[].id // empty' | sort -u > "$WORK/open"

    # --- worktrees ---------------------------------------------------------
    # Only the shape mol-polecat-work pours: <anything>/worktrees/<bead-id>.
    # An agent's own session worktree, a review worktree, and the rig checkout
    # all fail this test and are never candidates.
    git -C "$repo" worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{ print substr($0, 10) }' > "$WORK/wt" || : > "$WORK/wt"

    local path bead kb wt_branch
    : > "$WORK/unpinned"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -d "$path" ] || continue
        case "$path" in */worktrees/*) ;; *) continue ;; esac
        bead="${path##*/}"
        [ "$(basename "$(dirname "$path")")" = worktrees ] || continue
        grep -qxE "$BEAD_RE" <<< "$bead" || continue

        # The budget is spent deciding as much as removing — every gate below
        # costs a `git status` — so it is read before the gates, not after.
        if over_budget; then YIELDED="worktrees"; break; fi
        if grep -qxF "$bead" "$WORK/open"; then wt_held=$((wt_held + 1)); continue; fi
        if occupied "$path"; then wt_held=$((wt_held + 1)); continue; fi
        if holds_unique_content "$path"; then wt_held=$((wt_held + 1)); continue; fi

        # The branch this worktree pins, so the branch pass can still reach it.
        # A real pass drops it from `git worktree list` by removing the
        # directory; a dry run has to carry it by hand or under-report.
        wt_branch="$(git -C "$path" branch --show-current 2>/dev/null)" || wt_branch=""
        kb="$(du -sk "$path" 2>/dev/null | awk 'NR == 1 { print $1 }')" || kb=""
        if [ "$DRY_RUN" -eq 1 ]; then
            wt_removed=$((wt_removed + 1)); freed_kb=$((freed_kb + ${kb:-0}))
            [ -n "$wt_branch" ] && printf '%s\n' "$wt_branch" >> "$WORK/unpinned"
            continue
        fi
        # --force overrides the dirty check, which a pure deletion trips. The
        # gates above are what make that safe; git's own check cannot tell a
        # deletion from an edit.
        git -C "$repo" worktree remove --force "$path" >/dev/null 2>&1 || true
        if [ -d "$path" ]; then wt_held=$((wt_held + 1)); else
            wt_removed=$((wt_removed + 1)); freed_kb=$((freed_kb + ${kb:-0}))
            [ -n "$wt_branch" ] && printf '%s\n' "$wt_branch" >> "$WORK/unpinned"
        fi
    done < "$WORK/wt"

    # --- branches ----------------------------------------------------------
    # Checked-out branches are off limits whatever their bead says: the
    # worktree that holds one either survived a gate above or was never a
    # candidate.
    git -C "$repo" worktree list --porcelain 2>/dev/null \
        | awk '/^branch /{ sub(/^branch refs\/heads\//, ""); print }' | sort -u > "$WORK/pinned" || : > "$WORK/pinned"
    # Branches the worktree pass freed are no longer pinned. A real pass has
    # already dropped them from `git worktree list`; the subtraction is what
    # makes a dry run report the same branches the run would take.
    grep -vxF -f "$WORK/unpinned" "$WORK/pinned" > "$WORK/checkedout" 2>/dev/null || : > "$WORK/checkedout"

    # Merged by git's own definition: the tip is an ancestor of the default
    # branch, so deleting the ref discards no commit.
    git -C "$repo" branch --merged "$default_ref" --format='%(refname:short)' 2>/dev/null \
        | sort -u > "$WORK/merged" || : > "$WORK/merged"

    local branch bare_default
    bare_default="${default_ref#origin/}"
    : > "$WORK/landed"
    local landed_built=0

    # This reaper owns one branch family: polecat/<bead-id>. Any other ref — an
    # agent session branch, a long-lived claude/research-* or roadmap branch, a
    # design-doc trio — names no bead this pass may reason about and is left
    # alone whatever its merge state. Within the family the order is the point:
    # a live bead (open, in_progress or blocked) holds its branch BEFORE the
    # merged test, because a tip already an ancestor of the default branch (a
    # fast-forward land, or content that reached main another way) does not make
    # a resumable work item's local ref disposable. Only once the bead is no
    # longer live does merge state decide it.
    git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null > "$WORK/branches" || : > "$WORK/branches"
    while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        if [ "$branch" = "$bare_default" ]; then continue; fi
        if grep -qxF "$branch" "$WORK/checkedout"; then continue; fi

        case "$branch" in polecat/*) ;; *) continue ;; esac
        bead="${branch#polecat/}"
        bead="$(grep -oE "^$BEAD_RE" <<< "$bead")" || continue
        [ -n "$bead" ] || continue
        if grep -qxF "$bead" "$WORK/open"; then continue; fi

        if grep -qxF "$branch" "$WORK/merged"; then
            if drop_branch "$repo" "$branch"; then br_removed=$((br_removed + 1)); fi
            continue
        fi

        # Unmerged: goes only once the squash commit that carries its content is
        # on the default branch.
        if [ "$landed_built" -eq 0 ]; then
            git -C "$repo" log "$default_ref" --format='%s%n%b' 2>/dev/null \
                | grep -oE "\($BEAD_RE\)" | tr -d '()' | sort -u > "$WORK/landed" || : > "$WORK/landed"
            landed_built=1
        fi
        if ! grep -qxF "$bead" "$WORK/landed"; then continue; fi

        if drop_branch "$repo" "$branch"; then br_removed=$((br_removed + 1)); fi
    done < "$WORK/branches"

    [ "$DRY_RUN" -eq 1 ] || git -C "$repo" worktree prune 2>/dev/null || true

    TOTAL_WT=$((TOTAL_WT + wt_removed)); TOTAL_BR=$((TOTAL_BR + br_removed))
    TOTAL_KB=$((TOTAL_KB + freed_kb)); TOTAL_HELD=$((TOTAL_HELD + wt_held))
    printf '%s: %s — %s %d worktrees (%s GiB) and %d branches; held %d worktrees\n' \
        "$PROG" "$rig" "$([ "$DRY_RUN" -eq 1 ] && echo 'would take' || echo 'took')" \
        "$wt_removed" "$(gib $((freed_kb * 1024)))" "$br_removed" "$wt_held"
}

RIGS="$(gc rig list --json 2>/dev/null | jq -r '.rigs[]? | select(.hq != true) | "\(.name)\t\(.path)"' 2>/dev/null)" || RIGS=""
if [ -z "$RIGS" ]; then
    echo "$PROG: no rigs to reap"
    exit 0
fi

while IFS=$'\t' read -r NAME PATH_; do
    [ -n "${NAME:-}" ] || continue
    [ -z "$ONLY_RIG" ] || [ "$NAME" = "$ONLY_RIG" ] || continue
    [ -d "$PATH_/.git" ] || continue
    reap_rig "$NAME" "$PATH_"
done <<< "$RIGS"

printf '%s: %s %d worktrees (%s GiB) and %d branches across every rig; held %d worktrees in %ss\n' \
    "$PROG" "$([ "$DRY_RUN" -eq 1 ] && echo 'DRY RUN — would take' || echo 'freed')" \
    "$TOTAL_WT" "$(gib $((TOTAL_KB * 1024)))" "$TOTAL_BR" "$TOTAL_HELD" "$(($(date +%s) - START))"
if [ -n "$YIELDED" ]; then
    echo "$PROG: yielded in the $YIELDED pass — ${BUDGET}s budget spent; the next pass takes the rest"
fi
exit 0
