#!/usr/bin/env bash
# stale-branch-triage.sh — reclaim the origin branches nobody owns.
#
# Merged PRs delete their own head branch, a GitHub repo setting; nothing
# deletes the branch of work that never merged. Every abandoned attempt — a
# superseded retry, a cold research branch, an unmerged spike — leaves its
# origin ref behind, and the list grows without a ceiling. The only disposal on
# offer was a human's: land unassessed work or delete it, both terminal, neither
# with a safe default, so the branch waits for someone who feels like deciding.
# That wait is the thing this sweep removes.
#
# The move is to make the default disposition reversible. A branch whose work is
# unmerged and cold is ARCHIVED — an annotated tag archive/<branch>@<short-sha>
# pinning the tip and carrying the classification — and only then deleted. The
# objects survive under the tag, restoring is one command, and the branch list
# stops growing. Because the act is reversible, the sweep may take it without
# consent; that is the whole mechanism.
#
# For each origin branch with no live owner:
#   SUPERSEDED     every commit already reachable from the target -> delete. The
#                  work is on the target, so nothing is lost and no archive is
#                  needed.
#   COLD+UNMERGED  the newest commit is older than the cold horizon and not on
#                  the target -> archive, verify the tag on origin, then delete.
#   CONTESTED      an open PR heads it, or its tip or the target could not be
#                  read -> file a durable finding carrying the classification,
#                  and leave the branch untouched. Fail closed: never archive
#                  what was not read.
# A branch younger than the horizon, or one a live (non-closed) bead names in
# metadata.branch or metadata.target, is kept silently — the live bead is the
# tracked form of "a session owns it", and a branch touched inside the horizon
# is not abandoned.
#
# This is the pack's first direct mutation of origin refs. The merge cadence
# lands commits through `gh pr merge` and lets GitHub sign them, and nothing
# else writes origin; the signed-commit rule is about commits reaching a
# protected ref. A branch delete adds no commit, and an annotated tag is not a
# commit, so neither is subject to it. Both go through the gh token the order is
# handed, via `gh api`, the house style for every GitHub write in the pack. The
# rationale and the operator controls are in docs/stale-branch-triage.md.
#
# Rails, after worktree-reap.sh: liveness is resolved first and fail-closed — an
# unreadable ledger, PR list, or branch list sweeps nothing, because every
# branch would then read as unowned, and a ledger listing that does not parse as
# a bead list is unreadable; the archive tag is verified on origin
# before the branch is deleted; a dry run is the review surface and touches
# nothing; a time budget bounds the pass and the next pass takes the rest.
#
# Usage:
#   stale-branch-triage.sh            classify and dispose; one summary line
#   stale-branch-triage.sh --dry-run  report the plan, touch nothing
# Env: STALE_BRANCH_COLD_DAYS (default 14, matches the helm board's stale bump),
#      STALE_BRANCH_BUDGET (seconds, default 300, 0 disables),
#      STALE_BRANCH_TAG_PREFIX (default archive),
#      STALE_BRANCH_PROTECT (newline/space-separated glob patterns of branch
#        names never archived or deleted; a protected branch that is otherwise
#        cold and unmerged is reported contested instead),
#      STALE_BRANCH_TARGET (override the default branch; default origin/HEAD).
# Rig: GC_RIG (required — this is a scope="rig" order), GC_RIG_ROOT (the rig
#      checkout; PWD fallback).
# Exit: 0 acted or nothing to do · 2 usage.
# Caller: the stale-branch-triage exec order. See docs/stale-branch-triage.md.
set -euo pipefail

PROG="${0##*/}"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "$PROG: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

COLD_DAYS="${STALE_BRANCH_COLD_DAYS:-14}"
BUDGET="${STALE_BRANCH_BUDGET:-300}"
TAG_PREFIX="${STALE_BRANCH_TAG_PREFIX:-archive}"

for v in COLD_DAYS BUDGET; do
    case "${!v}" in
        '' | *[!0-9]*) echo "$PROG: STALE_BRANCH_$v must be a whole number" >&2; exit 2 ;;
    esac
done
[ "$COLD_DAYS" -gt 0 ] || { echo "$PROG: STALE_BRANCH_COLD_DAYS must be positive" >&2; exit 2; }
COLD_SECS=$((COLD_DAYS * 86400))

# Rows carry fields that are legitimately empty (a bead names a branch and no
# target). A unit separator is not IFS whitespace, so an empty field between two
# separators stays an empty field where a tab would collapse and shift the rest.
US=$'\x1f'

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gctk-stale-branch-triage.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

START=$(date +%s)
NOW="$START"
over_budget() { [ "$BUDGET" -gt 0 ] && [ $(($(date +%s) - START)) -ge "$BUDGET" ]; }

# --- rig identity ----------------------------------------------------------
# GC_RIG comes from the order runner; guessing would sweep one rig's origin
# while reading another rig's ledger. RIG_ROOT is the rig checkout, where the
# origin remote and its refs resolve. Siblings resolve from $0, since an
# importer rig's own root carries no assets/scripts.
RIG="${GC_RIG:-}"
if [ -z "$RIG" ]; then
    echo "$PROG: GC_RIG is unset — this runs as a scope=\"rig\" order and has no rig to sweep" >&2
    exit 2
fi
RIG_ROOT="${GC_RIG_ROOT:-$PWD}"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
git -C "$RIG_ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "$PROG: $RIG_ROOT is not a git checkout — nothing to sweep" >&2
    exit 0
}

# --- origin identity -------------------------------------------------------
# The slug parse the merge cadence uses (merge.sh, pr-facts.sh, pr-open.sh); an
# origin that will not resolve to host/owner/repo is swept as nothing, the same
# fail-closed a wrong target would force. The source is the DECLARED origin url
# (`config --get`), not `remote get-url`: identity is who the origin is, which a
# transport-time url.insteadOf rewrite must not change.
command -v gh >/dev/null 2>&1 || { echo "$PROG: gh not on PATH; nothing swept this pass" >&2; exit 0; }
ORIGIN_HOST=""; ORIGIN_REPO=""
u=$(git -C "$RIG_ROOT" config --get remote.origin.url 2>/dev/null | tr -d '[:space:]' || true)
case "$u" in
    git@github.com:* | https://github.com/* | ssh://git@github.com/*)
        ORIGIN_HOST="github.com"
        ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
            -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/* | /* | */) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
if [ -z "$ORIGIN_REPO" ]; then
    echo "$PROG: cannot resolve this checkout's origin repository; NOTHING is swept this pass" >&2
    exit 0
fi
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"
gh_api_origin() { gh api --hostname "$ORIGIN_HOST" "$@"; }

# --- the default branch, the merge authority -------------------------------
# origin/HEAD is the landing target; the comparisons below ask whether a branch
# is already reachable from it. No readable target means no proof is possible,
# so the whole pass is held.
TARGET="${STALE_BRANCH_TARGET:-}"
if [ -z "$TARGET" ]; then
    TARGET="$(git -C "$RIG_ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
    TARGET="${TARGET#origin/}"
fi
[ -n "$TARGET" ] || TARGET=main

# Bring remote-tracking refs current so ancestry, age and size read off local
# objects. A partial fetch is tolerated: a branch whose object is still missing
# below reads as contested-unreadable and is never archived.
git -C "$RIG_ROOT" fetch --prune origin "+refs/heads/*:refs/remotes/origin/*" >/dev/null 2>&1 || true
TARGET_REF="refs/remotes/origin/$TARGET"
if ! git -C "$RIG_ROOT" rev-parse --verify --quiet "$TARGET_REF" >/dev/null 2>&1; then
    echo "$PROG: default branch '$TARGET' is unreadable on origin; sweeping nothing" >&2
    exit 0
fi

# --- the ledger: branches a live bead owns (fail-closed) -------------------
# Live is the bead-status contract's, not a list kept here: every status but the
# `done` category keeps a worktree, and keeps a branch the same way. A live bead
# protects the branch it names (metadata.branch) AND the branch it targets
# (metadata.target) — an integration branch is a live convoy's landing ref and
# is named only as a target. A store whose live statuses or live rows will not
# read contributes no protectors, and the pass is refused rather than reading
# every branch as unowned.
LIVE_STATUSES="$(gc bd --rig "$RIG" statuses --json 2>/dev/null | scrub \
    | jq -r '[.. | objects | select(has("name") and has("category"))
             | select(.category != "done") | .name] | unique | join(",")' 2>/dev/null || true)"
if [ -z "$LIVE_STATUSES" ]; then
    echo "$PROG: live statuses for rig '$RIG' are unreadable; sweeping nothing rather than reading every branch as unowned" >&2
    exit 0
fi
declare -A OWNED_BRANCH=()
LIVE_ROWS="$(gc bd --rig "$RIG" list --status "$LIVE_STATUSES" --limit=0 --json 2>/dev/null)" || {
    echo "$PROG: live beads for rig '$RIG' are unreadable; sweeping nothing rather than reading every branch as unowned" >&2
    exit 0
}
# A listing that exits 0 is read only once it parses as exactly one array of
# bead rows. A non-JSON payload, an error object, an empty payload, or a row that
# is not a bead would otherwise contribute no protectors and leave every branch
# reading as unowned, so each refuses the pass the way a failed listing does.
OWNED_LIST="$(printf '%s' "$LIVE_ROWS" | scrub \
    | jq -rs 'if length == 1 and (.[0] | type) == "array" then .[0][]
              else error("not a bead list") end
              | (.metadata // {}) as $md
              | (($md.branch // ""), ($md.target // ""))
              | select(. != "")' 2>/dev/null)" || {
    echo "$PROG: live beads for rig '$RIG' did not parse as a bead list; sweeping nothing rather than reading every branch as unowned" >&2
    exit 0
}
while IFS= read -r b; do
    [ -n "$b" ] && OWNED_BRANCH["$b"]=1
done <<< "$OWNED_LIST"

# --- open pull requests: a head under review is contested ------------------
# One listing for the repo. An unreadable listing holds the whole pass: this is
# the backstop for a ledger that already disagrees with reality, so degrading it
# to fail-open would drop it exactly where it earns its place. --limit is
# required; gh pr list silently truncates at 30.
declare -A PR_BRANCH=()
if ! PR_OUT="$(gh pr list --repo "$ORIGIN_REPO_Q" --state open --limit 1000 --json headRefName -q '.[].headRefName' 2>/dev/null)"; then
    echo "$PROG: open pull requests for $ORIGIN_REPO_Q are unreadable; sweeping nothing this pass" >&2
    exit 0
fi
while IFS= read -r b; do
    [ -n "$b" ] && PR_BRANCH["$b"]=1
done <<< "$PR_OUT"

# --- extra-protected branch name patterns ----------------------------------
PROTECT_GLOBS=()
if [ -n "${STALE_BRANCH_PROTECT:-}" ]; then
    # shellcheck disable=SC2206
    PROTECT_GLOBS=(${STALE_BRANCH_PROTECT})
fi
protected_name() { # <branch>
    local b="$1" g
    for g in ${PROTECT_GLOBS[@]+"${PROTECT_GLOBS[@]}"}; do
        # shellcheck disable=SC2254
        case "$b" in $g) return 0 ;; esac
    done
    return 1
}

# --- enumerate origin heads ------------------------------------------------
# One ls-remote per pass, the authority for what still exists on origin. An
# unreadable listing sweeps nothing, because every branch would read as deleted.
HEADS="$(git -C "$RIG_ROOT" ls-remote --heads origin 2>/dev/null)" || HEADS=""
if [ -z "$HEADS" ]; then
    echo "$PROG: origin's branch list is unreadable; sweeping nothing rather than reading every branch as deleted" >&2
    exit 0
fi

BEAD_RE='[a-z][a-z]-[a-z0-9]+(\.[0-9]+)*'

# --- classify: build the plan ----------------------------------------------
# Each candidate lands in exactly one plan file as kind<US>fields. Classification
# is read-only; the plan is executed below and skipped entirely in a dry run.
: > "$WORK/plan"
n_super=0; n_archive=0; n_contested=0; n_kept=0
landed_built=0

while IFS= read -r line; do
    [ -n "$line" ] || continue
    sha="${line%%$'\t'*}"
    ref="${line#*$'\t'}"
    branch="${ref#refs/heads/}"
    [ -n "$branch" ] && [ -n "$sha" ] || continue
    case "$branch" in "$TARGET" | HEAD) continue ;; esac

    # A live bead names or targets it -> kept, silently.
    [ -n "${OWNED_BRANCH[$branch]:-}" ] && { n_kept=$((n_kept + 1)); continue; }

    bref="refs/remotes/origin/$branch"
    # The tip must be a readable object to reason about. A head ls-remote named
    # but the fetch did not land is contested-unreadable: never archived.
    if ! git -C "$RIG_ROOT" rev-parse --verify --quiet "$bref^{commit}" >/dev/null 2>&1; then
        printf 'contested%s%s%s%s%s%s\n' "$US" "$branch" "$US" "$sha" "$US" "tip unreadable" >> "$WORK/plan"
        n_contested=$((n_contested + 1)); continue
    fi

    # Superseded: the tip is reachable from the target, or (for a branch whose
    # name is a bead id) that bead id rode a squash-merge commit subject onto
    # the target. A squash tip is a new sha and never an ancestor, so the subject
    # scan is the only signal that catches it.
    superseded=0
    if git -C "$RIG_ROOT" merge-base --is-ancestor "$bref" "$TARGET_REF" 2>/dev/null; then
        superseded=1
    else
        bead="$(grep -oE "^$BEAD_RE$" <<< "$branch" || true)"
        [ -z "$bead" ] && bead="$(grep -oE "^$BEAD_RE$" <<< "${branch#polecat/}" || true)"
        if [ -n "$bead" ]; then
            if [ "$landed_built" -eq 0 ]; then
                git -C "$RIG_ROOT" log "$TARGET_REF" --format='%s' 2>/dev/null \
                    | grep -oE "\($BEAD_RE\)" | tr -d '()' | sort -u > "$WORK/landed" 2>/dev/null || : > "$WORK/landed"
                landed_built=1
            fi
            grep -qxF "$bead" "$WORK/landed" 2>/dev/null && superseded=1
        fi
    fi

    if [ "$superseded" -eq 1 ]; then
        # Already on the target. A head still under an open PR, or one the
        # operator pinned, is left for the refinery / the operator rather than
        # deleted out from under it.
        if [ -n "${PR_BRANCH[$branch]:-}" ] || protected_name "$branch"; then
            n_kept=$((n_kept + 1)); continue
        fi
        printf 'superseded%s%s%s%s%s%s\n' "$US" "$branch" "$US" "$sha" "$US" "reachable from $TARGET" >> "$WORK/plan"
        n_super=$((n_super + 1)); continue
    fi

    # Unmerged. Too fresh to be abandoned -> kept.
    ct="$(git -C "$RIG_ROOT" log -1 --format=%ct "$bref" 2>/dev/null || echo 0)"
    case "$ct" in '' | *[!0-9]*) ct=0 ;; esac
    age_days=$(( (NOW - ct) / 86400 ))
    if [ "$ct" -eq 0 ] || [ $((NOW - ct)) -lt "$COLD_SECS" ]; then
        n_kept=$((n_kept + 1)); continue
    fi

    # Cold and unmerged. The classification every disposition carries.
    ahead="$(git -C "$RIG_ROOT" rev-list --count "$TARGET_REF..$bref" 2>/dev/null || echo 0)"
    lines="$(git -C "$RIG_ROOT" diff --shortstat "$TARGET_REF...$bref" 2>/dev/null | tr -d '\n' || true)"
    [ -n "$lines" ] || lines="no diff"
    author="$(git -C "$RIG_ROOT" log -1 --format='%an' "$bref" 2>/dev/null || echo unknown)"
    class="${age_days}d old, $ahead commit(s) ahead, $lines, last by $author"

    # An open PR heads it, or the operator protected the name -> contested, left
    # untouched, the real question recorded. Otherwise -> archive.
    if [ -n "${PR_BRANCH[$branch]:-}" ]; then
        printf 'contested%s%s%s%s%s%s\n' "$US" "$branch" "$US" "$sha" "$US" "open PR heads it; $class" >> "$WORK/plan"
        n_contested=$((n_contested + 1)); continue
    fi
    if protected_name "$branch"; then
        printf 'contested%s%s%s%s%s%s\n' "$US" "$branch" "$US" "$sha" "$US" "protected name; $class" >> "$WORK/plan"
        n_contested=$((n_contested + 1)); continue
    fi
    printf 'archive%s%s%s%s%s%s\n' "$US" "$branch" "$US" "$sha" "$US" "$class" >> "$WORK/plan"
    n_archive=$((n_archive + 1))
done <<< "$HEADS"

# --- dry run: the review surface -------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
    total=$((n_super + n_archive + n_contested))
    echo "$PROG: DRY RUN for $RIG ($ORIGIN_REPO) — $total of $(($(printf '%s\n' "$HEADS" | grep -c . ) - 1)) non-default origin branches would be acted on; $n_kept kept"
    if [ "$n_super" -gt 0 ]; then
        echo "  would DELETE $n_super superseded branch(es) (already on $TARGET):"
        awk -F"$US" '$1 == "superseded" { printf "    %s @%s  (%s)\n", $2, substr($3, 1, 12), $4 }' "$WORK/plan"
    fi
    if [ "$n_archive" -gt 0 ]; then
        echo "  would ARCHIVE then delete $n_archive cold unmerged branch(es), each pinned as $TAG_PREFIX/<branch>@<sha> first:"
        awk -F"$US" '$1 == "archive" { printf "    %s @%s  (%s)\n", $2, substr($3, 1, 12), $4 }' "$WORK/plan"
    fi
    if [ "$n_contested" -gt 0 ]; then
        echo "  would FILE a finding for $n_contested contested branch(es), left untouched:"
        awk -F"$US" '$1 == "contested" { printf "    %s @%s  (%s)\n", $2, substr($3, 1, 12), $4 }' "$WORK/plan"
    fi
    exit 0
fi

# --- execute ---------------------------------------------------------------
# Origin mutations, verified on origin before the next step. Budget is checked
# between branches, so a pass cut short leaves a consistent origin and the next
# pass takes the rest.
deleted=0; archived=0; filed=0; refused=0; stopped=""

slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }

delete_origin_branch() { # <branch> <expected-full-sha> ; 0 deleted and verified gone
    local cur
    # Match-head before delete. git/refs DELETE takes no match-sha, so a branch
    # that moved since classification — a new commit the archive tag never pinned
    # — must not be deleted out from under that commit. Re-read origin now and
    # refuse unless it is exactly the tip this pass reasoned about.
    cur="$(git -C "$RIG_ROOT" ls-remote --heads origin "refs/heads/$1" 2>/dev/null | awk 'NR == 1 { print $1 }' || true)"
    [ -n "$cur" ] || return 1
    [ "$cur" = "$2" ] || return 1
    gh_api_origin -X DELETE "repos/$ORIGIN_REPO/git/refs/heads/$1" >/dev/null 2>&1 || return 1
    [ -z "$(git -C "$RIG_ROOT" ls-remote --heads origin "refs/heads/$1" 2>/dev/null)" ]
}

archive_tip() { # <branch> <full-sha> <message> ; 0 tag created and verified on origin
    local tag="$TAG_PREFIX/$1@${2:0:12}" tagsha
    # Already pinned (a prior pass archived the same tip) -> done.
    if [ -n "$(git -C "$RIG_ROOT" ls-remote --tags origin "refs/tags/$tag" 2>/dev/null)" ]; then
        return 0
    fi
    tagsha="$(gh_api_origin -X POST "repos/$ORIGIN_REPO/git/tags" \
        -f tag="$tag" -f message="$3" -f object="$2" -f type=commit -q '.sha' 2>/dev/null)" || return 1
    [ -n "$tagsha" ] || return 1
    gh_api_origin -X POST "repos/$ORIGIN_REPO/git/refs" \
        -f ref="refs/tags/$tag" -f sha="$tagsha" >/dev/null 2>&1 || return 1
    # Read it back on origin before anyone relies on it as the restore point.
    [ -n "$(git -C "$RIG_ROOT" ls-remote --tags origin "refs/tags/$tag" 2>/dev/null)" ]
}

while IFS="$US" read -r kind branch full detail; do
    [ -n "$kind" ] || continue
    short="${full:0:12}"
    if over_budget; then stopped="budget"; break; fi
    case "$kind" in
        superseded)
            if delete_origin_branch "$branch" "$full"; then
                deleted=$((deleted + 1))
            else
                refused=$((refused + 1))
            fi
            ;;
        archive)
            tag="$TAG_PREFIX/$branch@$short"
            msg="stale-branch-triage: $detail
Restore: git fetch origin refs/tags/$tag && git branch $branch $tag^{commit} && git push origin $branch"
            if archive_tip "$branch" "$full" "$msg" && delete_origin_branch "$branch" "$full"; then
                archived=$((archived + 1))
            else
                # Tag unverified, or the delete failed after it: leave the branch.
                # The tag, if it landed, is harmless and the next pass reuses it.
                refused=$((refused + 1))
            fi
            ;;
        contested)
            key="stale-branch-$(slug "$branch")"
            title="stale branch $branch: $detail"
            message="Origin branch \`$branch\` (tip ${short}) is stale but cannot be archived autonomously: $detail.

The reversible disposition does not apply here, so this needs a decision: archive it under $TAG_PREFIX/$branch@$short and delete it, land it, or keep it. $PROG files this and leaves the branch untouched."
            if "$SCRIPTS_DIR/patrol-finding.sh" --rig "$RIG" --key "$key" \
                --scope stale-branch-triage --type task \
                --title "$title" --message "$message" >/dev/null 2>&1; then
                filed=$((filed + 1))
            else
                refused=$((refused + 1))
            fi
            ;;
    esac
done < "$WORK/plan"

# --- summary ---------------------------------------------------------------
printf '%s: %s (%s) — deleted %d superseded, archived %d cold, filed %d contested; %d kept\n' \
    "$PROG" "$RIG" "$ORIGIN_REPO" "$deleted" "$archived" "$filed" "$n_kept"
[ "$refused" -gt 0 ] && echo "$PROG: $refused disposition(s) refused (tip not verifiable on origin, or a finding could not be filed) — left for the next pass"
[ -n "$stopped" ] && echo "$PROG: yielded — ${BUDGET}s budget spent; the next pass takes the rest"
exit 0
