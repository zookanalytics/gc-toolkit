#!/usr/bin/env bash
# worktree-reap.sh — remove the git worktrees of work beads that have closed.
#
# A polecat creates a worktree per bead and records the path in
# metadata.work_dir. Nothing removes it when the bead closes: the refinery
# merges and moves on, the witness inventories but does not delete, and the
# polecat drains. The checkouts are therefore a monotonic floor under the
# disk, one full working tree each, and the only reclaim is an operator
# noticing the pressure.
#
# The disposability chain is the bead ledger, not the filesystem. A worktree
# is named by metadata.work_dir, so the reverse lookup is exact path equality
# and no bead id is ever parsed out of a path or a branch name — the two
# disagree in practice, since a rework child stands on its predecessor's
# branch while keeping its own directory.
#
# A worktree is removed when every one of these holds:
#   - some bead names the path in metadata.work_dir, and none of the beads
#     naming it is still open
#   - no open bead names its branch, and no open pull request has that branch
#     as its head — a branch in the pre-open gate carries no PR and is live
#   - the newest close among the beads naming it is older than CLOSED_AFTER
#   - `git status --porcelain` is empty
#   - it is not an agent home, a session work_dir, or any live process's cwd
#   - it is not a locked worktree, the main worktree, or the parent of another
#     registered worktree
#
# Removal is reversible rather than gated. Before each removal the tip is
# pinned by an annotated tag, so a detached HEAD whose commits no ref reaches
# survives the removal and the whole checkout is one `git worktree add` away.
# That is what lets an unattended pass take a destructive-looking act: nothing
# is destroyed, so nobody has to notice first.
#
# Enumeration is `git worktree list` over every rig repo and the town repo,
# never a path glob: a worktree under one rig's tree can be registered in
# another repo's git dir, and only the registry knows which.
#
# Reclaim is reported as a count of removals plus filesystem free space, and
# every removal is asserted on disk afterwards — `git worktree remove` can
# report success and leave the directory behind, which is the failure mode a
# count alone would hide. Free space moves for other writers too, so it is
# reported as the filesystem's, not as this pass's yield.
#
# Usage:
#   worktree-reap.sh              reap, print one summary line per repo
#   worktree-reap.sh --dry-run    report the plan, touch nothing
# Env: WORKTREE_REAP_CLOSED_AFTER (seconds, default 24h),
#      WORKTREE_REAP_BUDGET (seconds, default 420),
#      WORKTREE_REAP_TAG_PREFIX (default archive/worktree),
#      WORKTREE_REAP_REPOS (newline-separated repo paths, overriding the rig
#      list; the ledger is then read unscoped).
# Exit: 0 reaped or nothing to do · 2 usage.
# Caller: the worktree-reap exec order. See docs/worktree-reclaim.md.
set -euo pipefail

PROG="${0##*/}"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "$PROG: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

CLOSED_AFTER="${WORKTREE_REAP_CLOSED_AFTER:-86400}"
BUDGET="${WORKTREE_REAP_BUDGET:-420}"
TAG_PREFIX="${WORKTREE_REAP_TAG_PREFIX:-archive/worktree}"

for v in CLOSED_AFTER BUDGET; do
    case "${!v}" in
        '' | *[!0-9]*) echo "$PROG: WORKTREE_REAP_$v must be a whole number of seconds" >&2; exit 2 ;;
    esac
done
[ "$CLOSED_AFTER" -gt 0 ] || { echo "$PROG: WORKTREE_REAP_CLOSED_AFTER must be positive" >&2; exit 2; }

# Rows carry fields that are legitimately empty — a detached worktree has no
# branch, a bead can name a branch and no directory. `read` cannot see those
# with a tab: tab is an IFS WHITESPACE character, so runs of them collapse and
# every field after the empty one shifts left. A unit separator is not IFS
# whitespace, so an empty field stays an empty field.
US=$'\x1f'

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

START=$(date +%s)
NOW="$START"
over_budget() { [ "$BUDGET" -gt 0 ] && [ $(($(date +%s) - START)) -ge "$BUDGET" ]; }

# --- repos and the city root ----------------------------------------------
# Rig name and repo path travel together: the ledger a worktree's beads live
# in is the rig's, and `gc bd` needs the name to reach it.
REPO_NAMES=(); REPO_PATHS=()
CITY="${GC_CITY_PATH:-}"
if [ -n "${WORKTREE_REAP_REPOS:-}" ]; then
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        REPO_NAMES+=(""); REPO_PATHS+=("$p")
    done <<< "$WORKTREE_REAP_REPOS"
else
    RIGS="$(gc rig list --json 2>/dev/null | jq -r '.rigs[]? | [.name, .path, (.hq // false | tostring)] | join("\u001f")' 2>/dev/null)" || RIGS=""
    if [ -z "$RIGS" ]; then
        echo "$PROG: no rigs readable — nothing to reap"
        exit 0
    fi
    while IFS="$US" read -r name path hq; do
        [ -n "${path:-}" ] && [ -d "$path/.git" ] || continue
        REPO_NAMES+=("$name"); REPO_PATHS+=("$path")
        [ "${hq:-false}" = "true" ] && [ -z "$CITY" ] && CITY="$path"
    done <<< "$RIGS"
fi
[ "${#REPO_PATHS[@]}" -gt 0 ] || { echo "$PROG: no repositories to scan"; exit 0; }

# --- what may never be removed --------------------------------------------
declare -A PROTECT_PATH=()
PROTECT_HOME_RX=()

# An agent home is created by worktree-setup.sh at the agent's configured
# work_dir, before any session exists, and it outlives every session that ever
# ran in it — a stopped pool member still owns its home. The roster states the
# shape as a path template, so matching the shape is what protects the home of
# an agent that is merely idle, which no liveness probe can see.
#
# Each template becomes an anchored regex whose substitutions widen to one path
# SEGMENT. A shell glob cannot express that: `*` crosses `/`, so
# `.gc/worktrees/*/polecats/*` also matches every per-bead worktree nested
# under an agent home, and the reaper would protect the whole population it
# exists to take.
if [ -n "$CITY" ]; then
    while IFS= read -r tmpl; do
        [ -n "$tmpl" ] || continue
        # Sentinel first, escape second: escaping would otherwise mangle the
        # braces the substitutions are written in.
        rx="$(printf '%s' "$CITY/$tmpl" | sed -e 's/{{[^}]*}}/\x01/g' -e 's/[][\.^$*+?(){}|]/\\&/g' -e 's/\x01/[^\/]\+/g')"
        PROTECT_HOME_RX+=("^$rx$")
    done < <(gc agent list --json 2>/dev/null | jq -r '.agents[]? | select((.work_dir // "") != "") | .work_dir' 2>/dev/null | sort -u)
fi

# A protected directory protects every worktree containing it, not only an
# exact path match: an agent whose cwd is a subdirectory still stands inside
# the tree, and removing the tree from under it is the same mistake.
protect_with_ancestors() { # <path> <why>
    local d="$1"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        PROTECT_PATH["$d"]="$2"
        d="${d%/*}"
    done
}

# Sessions name their own directory, which covers an agent whose home is not
# under the templated roots.
while IFS= read -r d; do
    [ -n "$d" ] && protect_with_ancestors "$d" session
done < <(gc session list --state all --json 2>/dev/null | jq -r '.sessions[]? | select((.work_dir // "") != "") | .work_dir' 2>/dev/null)

# A running process's cwd is the one certain signal: whatever the ledger says,
# something is standing in that directory right now. The signal only ever
# protects — a session between turns owns no process — so the checks above
# carry the rest.
#
# `find` walks /proc rather than a glob over it. A shell glob stats every
# candidate and drops what it cannot read, and passing the survivors to
# `readlink` in bulk drops more still: measured on this host, find reported
# around 360 cwds on every sample while the pair returned between 27 and 180,
# and the pair missed a process started a moment earlier in 3 of 15 trials
# where find missed none in 42. A protection that finds a varying fraction of
# the live processes is worse than none, because it still reads as a check.
while IFS= read -r d; do
    [ -n "$d" ] && protect_with_ancestors "$d" live-cwd
done < <(find /proc -maxdepth 2 -name cwd -type l -printf '%l\n' 2>/dev/null || true)
SELF_CWD="$(pwd -P 2>/dev/null || true)"
[ -n "$SELF_CWD" ] && protect_with_ancestors "$SELF_CWD" self

protected_shape() { # <path>
    local p="$1" rx
    [ -n "${PROTECT_PATH[$p]:-}" ] && return 0
    for rx in ${PROTECT_HOME_RX[@]+"${PROTECT_HOME_RX[@]}"}; do
        [[ "$p" =~ $rx ]] && return 0
    done
    return 1
}

# --- the ledger ------------------------------------------------------------
# Two questions, one read per rig. What is still open protects a path and a
# branch; what has closed supplies the path's age and the bead the archive tag
# is named for.
declare -A OPEN_PATH=() OPEN_BRANCH=()
declare -A CLOSED_AT=() CLOSED_BEAD=() CLOSED_BRANCHES=()
LEDGER_READ=0
for i in "${!REPO_PATHS[@]}"; do
    name="${REPO_NAMES[$i]}"
    RIG_ARG=(); [ -n "$name" ] && RIG_ARG=(--rig "$name")
    seen=0

    while IFS="$US" read -r wd br; do
        [ -n "$wd" ] && OPEN_PATH["$wd"]=1
        [ -n "$br" ] && OPEN_BRANCH["$br"]=1
        seen=1
    done < <(gc bd "${RIG_ARG[@]+${RIG_ARG[@]}}" list --status open,in_progress,blocked --limit=0 --json 2>/dev/null \
        | jq -r '.[]? | (.metadata // {}) as $md
                 | select((($md.work_dir // "") != "") or (($md.branch // "") != ""))
                 | [($md.work_dir // ""), ($md.branch // "")] | join("\u001f")' 2>/dev/null || true)

    while IFS="$US" read -r wd id at br; do
        [ -n "$wd" ] || continue
        case "${at:-}" in '' | *[!0-9]*) continue ;; esac
        # Many beads can name one directory; the newest close is the one the
        # horizon is measured from, so a rework child closing today holds the
        # tree its predecessor closed in last week. Every branch any of them
        # recorded is kept, though — one stale bead's branch can be the ref an
        # open bead elsewhere is still working.
        if [ -z "${CLOSED_AT[$wd]:-}" ] || [ "$at" -gt "${CLOSED_AT[$wd]}" ]; then
            CLOSED_AT["$wd"]="$at"; CLOSED_BEAD["$wd"]="$id"
        fi
        [ -n "$br" ] && CLOSED_BRANCHES["$wd"]="${CLOSED_BRANCHES[$wd]:-}$US$br"
        seen=1
    done < <(gc bd "${RIG_ARG[@]+${RIG_ARG[@]}}" list --status closed --limit=0 --json 2>/dev/null \
        | jq -r '.[]? | . as $r | (.metadata // {}) as $md
                 | select(($md.work_dir // "") != "")
                 | [$md.work_dir, $r.id,
                    (($r.closed_at // $r.updated_at // "") | if . == "" then 0 else (fromdateiso8601? // 0) end | tostring),
                    ($md.branch // "")] | join("\u001f")' 2>/dev/null || true)

    [ "$seen" -eq 1 ] && LEDGER_READ=$((LEDGER_READ + 1))
done

# A ledger that answered nothing anywhere is a broken lookup, not an empty
# city, and every path would read as unclaimed. Refuse the pass.
if [ "$LEDGER_READ" -eq 0 ]; then
    echo "$PROG: no ledger answered — refusing to reap on an unreadable bead store" >&2
    exit 0
fi

# --- enumerate the registry ------------------------------------------------
# Prune first: an entry whose directory is already gone is registry litter,
# and git's own expiry decides when it is safe to drop.
: > "$WORK/wt"
for i in "${!REPO_PATHS[@]}"; do
    repo="${REPO_PATHS[$i]}"
    git -C "$repo" worktree prune 2>/dev/null || true
    git -C "$repo" worktree list --porcelain 2>/dev/null \
      | awk -v repo="$repo" -v S="$US" '
            function flush() {
                if (p != "") printf "%s%s%s%s%s%s%s%s%s\n", repo, S, p, S, br, S, sha, S, (main "," lock)
                p = ""; br = ""; sha = ""; lock = ""
            }
            /^worktree /  { flush(); p = substr($0, 10); if (first == "") { first = p; main = "main" } else main = "" ; next }
            /^HEAD /      { sha = $2; next }
            /^branch /    { br = $2; sub(/^refs\/heads\//, "", br); next }
            /^detached$/  { br = ""; next }
            /^bare$/      { lock = "bare"; next }
            /^locked/     { lock = "locked"; next }
            END           { flush() }' >> "$WORK/wt"
done
TOTAL=$(wc -l < "$WORK/wt")

# A registry that enumerated nothing means the walk failed, not that the city
# has one checkout: the main worktree of every repo is always a row.
if [ "$TOTAL" -eq 0 ]; then
    echo "$PROG: worktree registry enumerated 0 entries across ${#REPO_PATHS[@]} repositories — refusing to act on an empty walk" >&2
    exit 0
fi

# Parents are excluded and only leaves are removed, so a nested pair drains
# over successive passes rather than taking a child's tree out from under it.
declare -A PARENT=()
while IFS="$US" read -r _ p _ _ _; do
    d="${p%/*}"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        PARENT["$d"]=1
        d="${d%/*}"
    done
done < "$WORK/wt"

# --- open pull requests ----------------------------------------------------
# One listing per repo, not one per worktree. A repo whose PR listing fails
# holds its own worktrees for the next pass: this is the backstop for a bead
# ledger that already disagrees with reality, so degrading it to fail-open
# would remove it exactly where it earns its place.
declare -A PR_BRANCH=() REPO_HELD=()
for i in "${!REPO_PATHS[@]}"; do
    repo="${REPO_PATHS[$i]}"
    url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || url=""
    [ -n "$url" ] || continue   # no origin, so no pull requests to protect
    case "$url" in *github.com*) ;; *) continue ;; esac
    slug="${url##*github.com}"; slug="${slug#[:/]}"; slug="${slug%.git}"
    if ! out="$(gh pr list -R "$slug" --state open --limit 500 --json headRefName -q '.[].headRefName' 2>/dev/null)"; then
        REPO_HELD["$repo"]="open pull requests unreadable"
        continue
    fi
    while IFS= read -r b; do
        [ -n "$b" ] && PR_BRANCH["$b"]=1
    done <<< "$out"
done

# --- decide and act --------------------------------------------------------
declare -A REMOVED=() REFUSED=() SURVIVED=() KEPT=()
planned=0; removed=0; refused=0; survived=0; stopped=""
: > "$WORK/plan"

FS_BEFORE="$(df -Pk "${REPO_PATHS[0]}" 2>/dev/null | awk 'NR == 2 { print $4 }')"; FS_BEFORE="${FS_BEFORE:-0}"

while IFS="$US" read -r repo path branch sha flags; do
    case ",$flags," in *,main,* | *,bare,* | *,locked,*) continue ;; esac
    [ -n "${REPO_HELD[$repo]:-}" ] && continue
    [ -d "$path" ] || continue
    [ -n "${PARENT[$path]:-}" ] && continue
    protected_shape "$path" && continue
    [ -n "${OPEN_PATH[$path]:-}" ] && continue

    at="${CLOSED_AT[$path]:-}"
    [ -n "$at" ] || continue                       # no bead names it; not ours to take
    [ $((NOW - at)) -ge "$CLOSED_AFTER" ] || continue

    # The branch the worktree is on and the branches its beads recorded are not
    # always the same ref, and any of them being live is a reason to keep the
    # tree.
    live_branch=""
    IFS="$US" read -r -a BRANCHES <<< "$branch${CLOSED_BRANCHES[$path]:-}"
    for b in ${BRANCHES[@]+"${BRANCHES[@]}"}; do
        [ -n "$b" ] || continue
        if [ -n "${OPEN_BRANCH[$b]:-}" ] || [ -n "${PR_BRANCH[$b]:-}" ]; then
            live_branch="$b"; break
        fi
    done
    [ -n "$live_branch" ] && continue

    [ -z "$(git -C "$path" status --porcelain </dev/null 2>/dev/null)" ] || continue

    [ -n "$sha" ] || continue   # nothing to pin the tip with
    planned=$((planned + 1))
    bead="${CLOSED_BEAD[$path]:-unknown}"
    printf '%s%s%s%s%s\n' "$bead" "$US" "$path" "$US" "${sha:0:12}" >> "$WORK/plan"
    [ "$DRY_RUN" -eq 1 ] && continue

    if over_budget; then stopped="budget"; break; fi

    # Pin before removing. A detached worktree's HEAD is often the only ref
    # reaching its commits, and squash-merged work is never an ancestor of the
    # default branch, so both shapes look unpushed the moment the checkout is
    # gone. No pin, no removal.
    tag="$TAG_PREFIX/$bead@${sha:0:12}"
    if ! git -C "$repo" rev-parse -q --verify "refs/tags/$tag" </dev/null >/dev/null 2>&1; then
        if ! git -C "$repo" -c tag.gpgSign=false tag -a "$tag" "$sha" \
                -m "worktree $path (bead $bead, branch ${branch:-<detached>}) reaped by $PROG
Restore: git -C $repo worktree add $path $tag" </dev/null >/dev/null 2>&1; then
            REFUSED["$repo"]=$(( ${REFUSED[$repo]:-0} + 1 )); refused=$((refused + 1))
            continue
        fi
    fi

    # No --force: git's own dirty check is the last gate, and it runs after
    # the status probe above rather than instead of it.
    if ! git -C "$repo" worktree remove "$path" </dev/null >/dev/null 2>&1; then
        REFUSED["$repo"]=$(( ${REFUSED[$repo]:-0} + 1 )); refused=$((refused + 1))
        continue
    fi
    # A removal that reported success and left the tree standing freed
    # nothing; a count of return codes would call that a reap.
    if [ -d "$path" ]; then
        SURVIVED["$repo"]=$(( ${SURVIVED[$repo]:-0} + 1 )); survived=$((survived + 1))
        continue
    fi
    REMOVED["$repo"]=$(( ${REMOVED[$repo]:-0} + 1 )); removed=$((removed + 1))
done < "$WORK/wt"

gib() { awk -v k="$1" 'BEGIN { printf "%.2f", k / 1048576 }'; }

if [ "$DRY_RUN" -eq 1 ]; then
    echo "$PROG: DRY RUN — $TOTAL registered worktrees across ${#REPO_PATHS[@]} repositories"
    echo "  would remove $planned worktrees, each pinned as $TAG_PREFIX/<bead>@<sha> first"
    # The whole plan, not a sample: --dry-run is the operator's review surface,
    # and a truncated list is not something anyone can approve.
    awk -F"$US" '{ printf "    %s  %s\n", $1, $2 }' "$WORK/plan"
    for repo in "${!REPO_HELD[@]}"; do echo "  held $repo: ${REPO_HELD[$repo]}"; done
    exit 0
fi

FS_AFTER="$(df -Pk "${REPO_PATHS[0]}" 2>/dev/null | awk 'NR == 2 { print $4 }')"; FS_AFTER="${FS_AFTER:-0}"
printf '%s: removed %d of %d registered worktrees in %ss — free space on %s: %s -> %s GiB\n' \
    "$PROG" "$removed" "$TOTAL" "$(($(date +%s) - START))" "${REPO_PATHS[0]}" "$(gib "$FS_BEFORE")" "$(gib "$FS_AFTER")"
for repo in "${!REMOVED[@]}"; do
    printf '%s:   %s — removed %d\n' "$PROG" "$repo" "${REMOVED[$repo]}"
done
[ "$refused" -gt 0 ] && echo "$PROG: $refused removals refused (dirty tree, or the tip could not be pinned) — left for the next pass"
[ "$survived" -gt 0 ] && echo "$PROG: $survived removals reported success and left the directory standing — investigate, they freed nothing"
for repo in "${!REPO_HELD[@]}"; do
    echo "$PROG: held $repo — ${REPO_HELD[$repo]}; its worktrees are the next pass's"
done
[ -n "$stopped" ] && echo "$PROG: yielded — ${BUDGET}s budget spent with $((planned - removed - refused - survived)) planned removals untaken; the next pass takes them"
exit 0
