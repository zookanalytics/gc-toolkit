#!/usr/bin/env bash
# worktree-reap.sh — remove the worktrees, and drop the local branches, of work
# beads that have closed.
#
# A polecat creates a worktree per bead and records the path in
# metadata.work_dir. Nothing removes it when the bead closes: the refinery
# merges and moves on, the witness inventories but does not delete, and the
# polecat drains. The checkouts are therefore a monotonic floor under the
# disk, one full working tree each, and the only reclaim is an operator
# noticing the pressure.
#
# The branch outlives the checkout: `git worktree remove` deletes the working
# tree and leaves the ref, so a polecat/<bead-id> branch accretes per work item
# with no ceiling. A second pass drops those refs once their bead has closed and
# their content is proven on the default branch. Its rules are its own — the
# disposability signal is the branch name's bead and the ref graph, not
# metadata.work_dir — so it is documented at the pass itself.
#
# The disposability chain is the bead ledger, not the filesystem. For worktree
# removal the identity is metadata.work_dir: the reverse lookup is exact path
# equality and no bead id is parsed out of a path. Path and branch disagree in
# practice, since a rework child stands on its predecessor's branch while
# keeping its own directory, so the worktree pass keys on the path and never on
# a branch name. The branch pass is the exception — it has no work_dir, so it
# parses the bead id out of the polecat/<bead-id> ref name, under rules
# documented at the pass.
#
# A worktree is removed when every one of these holds:
#   - some bead names the path in metadata.work_dir, and none of the beads
#     naming it is still live — live is every status but closed, so a deferred,
#     pinned or hooked bead holds its checkout exactly as an open one does
#   - no live bead names its branch, and no open pull request has that branch
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gctk-worktree-reap.XXXXXX")"
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
# Two questions, one read per store. What is still LIVE protects a path and a
# branch; what has CLOSED supplies the path's age and the bead the archive tag
# is named for.
#
# Live is the bead-status contract's, not a list kept here. `gc bd statuses`
# categorises every status and exactly one category, `done`, means the work is
# finished and its checkout disposable; the protector query asks for every
# other status the store defines. A status bd gains, or one a rig adds under
# status.custom, then protects its worktrees without a change here — where an
# enumerated allowlist would reap the checkout of any status written after it.
# A store whose contract will not read is skipped whole: its live statuses are
# unknown, and a reap decided without them could take a live tree, so it
# contributes neither protectors nor candidates and its worktrees leak instead.
#
# The reap side keys on `closed` alone, not the whole `done` category: it is
# the one done status with a defined close time, so a custom done status leaves
# a worktree unreaped (a leak) rather than reaped while live (a loss).
declare -A OPEN_PATH=() OPEN_BRANCH=()
declare -A CLOSED_AT=() CLOSED_BEAD=() CLOSED_BRANCHES=()
# A store is ledger-ready only when its live rows actually read. The branch pass
# gates on this: a repo whose live statuses or live rows did not read contributes
# no OPEN_BRANCH protectors, so it cannot be told that a closed, landed ref is
# still some live claimant's branch, and its whole family is held for the next
# pass — the same fail-closed the worktree pass takes when it cannot read a store.
declare -A LEDGER_OK=()
LEDGER_READ=0
for i in "${!REPO_PATHS[@]}"; do
    name="${REPO_NAMES[$i]}"; repo="${REPO_PATHS[$i]}"
    RIG_ARG=(); [ -n "$name" ] && RIG_ARG=(--rig "$name")

    LIVE_STATUSES="$(gc bd "${RIG_ARG[@]+${RIG_ARG[@]}}" statuses --json 2>/dev/null \
        | jq -r '[.. | objects | select(has("name") and has("category"))
                 | select(.category != "done") | .name] | unique | join(",")' 2>/dev/null || true)"
    [ -n "$LIVE_STATUSES" ] || continue
    seen=0

    # Capture the live-rows read's own exit status, not just its output: an empty
    # result is "no live beads" and still ready, a failed query is "unknown" and
    # is not. Only a read that succeeded marks the repo ledger-ready, so an empty
    # OPEN_BRANCH reads as knowledge and not as a store that never answered.
    LIVE_ROWS="$(gc bd "${RIG_ARG[@]+${RIG_ARG[@]}}" list --status "$LIVE_STATUSES" --limit=0 --json 2>/dev/null)" \
        && LEDGER_OK["$repo"]=1 || LIVE_ROWS=""

    while IFS="$US" read -r wd br; do
        [ -n "$wd" ] && OPEN_PATH["$wd"]=1
        [ -n "$br" ] && OPEN_BRANCH["$br"]=1
        seen=1
    done < <(printf '%s' "$LIVE_ROWS" \
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
# Pin, then prune, then list — and none of it in a dry run. An entry whose
# working tree is gone is registry litter, but `git worktree prune` reclaims it
# by deleting the entry's admin dir, and that dir holds its HEAD. For a detached
# worktree that HEAD is the only ref its commits have, so an unpinned prune is
# the same commit loss the removal path below pins against — and git drops the
# ref the moment it prunes, with no expiry to make it safe. `git worktree list
# --porcelain` reports each such row as `prunable` and carries its HEAD, so the
# tip is pinned by the same archive tag before git is let near it. A dry run
# neither pins nor prunes: it is the operator's review surface and touches
# nothing.
: > "$WORK/wt"
for i in "${!REPO_PATHS[@]}"; do
    repo="${REPO_PATHS[$i]}"
    if [ "$DRY_RUN" -eq 0 ]; then
        prune_ok=1
        while IFS="$US" read -r path sha; do
            [ -n "$path" ] && [ -n "$sha" ] || continue
            bead="${CLOSED_BEAD[$path]:-unknown}"
            tag="$TAG_PREFIX/$bead@${sha:0:12}"
            git -C "$repo" rev-parse -q --verify "refs/tags/$tag" </dev/null >/dev/null 2>&1 && continue
            git -C "$repo" -c tag.gpgSign=false tag -a "$tag" "$sha" \
                -m "prunable worktree $path (bead $bead) pinned before prune by $PROG
Restore: git -C $repo worktree add $path $tag" </dev/null >/dev/null 2>&1 || prune_ok=0
        done < <(git -C "$repo" worktree list --porcelain 2>/dev/null \
                 | awk -v S="$US" '/^worktree / { p = substr($0, 10); sha = "" }
                                   /^HEAD /     { sha = $2 }
                                   /^prunable/  { if (p != "" && sha != "") print p S sha }')
        # No pin, no prune: a tip left unpinned keeps its admin HEAD, so the ref
        # survives for the next pass rather than being dropped now. git prunes
        # every prunable entry at once, so one unpinnable tip holds the repo's.
        [ "$prune_ok" -eq 1 ] && git -C "$repo" worktree prune 2>/dev/null || true
    fi
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

# --- branch pass: drop the local refs the worktree pass leaves behind -------
# `git worktree remove` deletes a checkout but never its branch, so every
# reaped worktree — and every polecat worktree ever removed by hand — leaves a
# polecat/<bead-id> ref behind. They accrete with no ceiling, one per work item
# forever. A ref is disposable exactly when the work it named has closed AND its
# content already sits on the default branch, so deleting the ref discards
# nothing.
#
# One family only: polecat/<bead-id>. Any other ref names no bead this pass may
# reason about — a roadmap branch, a claude/* research branch, a design-doc
# trio — and is left alone whatever its state. Within the family a live bead
# (any status but closed) holds its branch, because that is resumable work; only
# a closed bead's ref is a candidate, and only once its content is proven on the
# default branch. A branch that fails the proof is kept: the reap must never
# take the only copy of unmerged work.
#
# origin/main, not the rig checkout's own main, is the authority for that proof
# — the shared checkout's local main lags behind the ref that work lands on. The
# proof is reachability (the tip is an ancestor of the default branch) or the
# squash signal (the bead id rode a commit subject onto it — a squash tip is a
# new sha and never an ancestor). A branch whose origin counterpart was deleted
# (`[gone]` upstream, the usual post-merge cleanup) is offered to `git branch
# -d` first, whose own merged-check is a second gate; anything it declines,
# every squash-merged tip among them, falls to `git branch -D` — safe, because
# the proof already showed the content landed.
BR_DROPPED=0; BR_D=0; BR_BIGD=0; br_stopped=""
: > "$WORK/brplan"
BEAD_RE='[a-z][a-z]-[a-z0-9]+(\.[0-9]+)*'

# Branches the worktree pass took (or, in a dry run, would take) are no longer
# held by a checkout. A real pass already dropped them from the registry;
# reading the plan lets a dry run predict the same branches a real pass, which
# removes first, would then be free to drop.
declare -A FREED=()
while IFS="$US" read -r _ ppath _; do
    [ -n "$ppath" ] || continue
    fb="$(awk -F"$US" -v p="$ppath" '$2 == p { print $3; exit }' "$WORK/wt")"
    [ -n "$fb" ] && FREED["$fb"]=1
done < "$WORK/plan"

for i in "${!REPO_PATHS[@]}"; do
    if over_budget; then br_stopped="budget"; break; fi
    repo="${REPO_PATHS[$i]}"; name="${REPO_NAMES[$i]}"
    RIG_ARG=(); [ -n "$name" ] && RIG_ARG=(--rig "$name")

    # Hold the whole family on the two signals that also hold a worktree. An
    # unreadable PR listing (REPO_HELD) means an open PR could head a ref
    # unseen; a live ledger that did not read (no LEDGER_OK) means a live
    # claimant's branch is unknown. Under either, an empty PR_BRANCH / OPEN_BRANCH
    # is absence of knowledge, not proof a closed, landed ref is disposable.
    [ -n "${REPO_HELD[$repo]:-}" ] && continue
    [ -n "${LEDGER_OK[$repo]:-}" ] || continue

    # The default branch is the landing target and the merge authority. No
    # readable one means no proof is possible here, so the whole family is held.
    default_ref="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    [ -n "$default_ref" ] || default_ref="origin/main"
    git -C "$repo" rev-parse --verify --quiet "$default_ref" >/dev/null 2>&1 || continue

    # Still checked out in a surviving worktree -> off limits. git refuses to
    # delete such a branch anyway; skipping keeps the pass quiet. This reads the
    # registry as it stands now, after the worktree removals above.
    unset CO; declare -A CO=()
    while IFS= read -r b; do
        [ -n "$b" ] && [ -z "${FREED[$b]:-}" ] && CO["$b"]=1
    done < <(git -C "$repo" worktree list --porcelain 2>/dev/null \
             | awk '/^branch /{ sub(/^branch refs\/heads\//, ""); print }')

    # Candidate refs and the bead ids they name, in one walk of the family.
    CANDS=(); unset CAND_BEAD; declare -A CAND_BEAD=(); ids=""
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        [ -n "${CO[$b]:-}" ] && continue
        # A live bead can record this exact ref in metadata.branch, or an open
        # PR can have it as head, while the bead its NAME encodes is closed and
        # landed: a rework or rebase child stands on its predecessor's branch,
        # and the ref is that child's only local copy of resumable work. The
        # worktree pass already holds a tree on this same OPEN_BRANCH/PR_BRANCH
        # signal; the ref needs it too.
        [ -n "${OPEN_BRANCH[$b]:-}" ] && continue
        [ -n "${PR_BRANCH[$b]:-}" ] && continue
        # The whole name after polecat/ must BE a bead id, not merely begin with
        # one: polecat/<bead-id>-arm is a different branch a different bead holds,
        # and a start-anchored match would read it as <bead-id> and drop it the
        # moment that bead closed and landed. Anchor both ends, so such a variant
        # names no bead and falls to the skip below with the out-of-family refs.
        bead="$(grep -oE "^$BEAD_RE$" <<< "${b#polecat/}")" || continue
        [ -n "$bead" ] || continue
        CANDS+=("$b"); CAND_BEAD["$b"]="$bead"; ids="$ids,$bead"
    done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/polecat 2>/dev/null)
    [ "${#CANDS[@]}" -gt 0 ] || continue

    # Which of those beads are closed. A missing id falls out of the answer, so a
    # branch naming a bead that no longer exists is never confirmed-closed and is
    # left alone. A ledger read that fails or comes back empty confirms nothing,
    # and the family is held for the next pass — the same fail-closed a down
    # store already forces on the worktree side.
    unset CLOSED_ID; declare -A CLOSED_ID=()
    while IFS= read -r id; do
        [ -n "$id" ] && CLOSED_ID["$id"]=1
    done < <(gc bd "${RIG_ARG[@]+${RIG_ARG[@]}}" list --status closed --id "${ids#,}" --limit 0 --json 2>/dev/null \
             | jq -r '.[]?.id // empty' 2>/dev/null || true)

    landed_built=0
    for b in "${CANDS[@]}"; do
        bead="${CAND_BEAD[$b]}"
        [ -n "${CLOSED_ID[$bead]:-}" ] || continue
        if over_budget; then br_stopped="budget"; break; fi

        # The proof that dropping loses nothing: the tip is reachable from the
        # default branch, or the bead id rode a commit subject onto it.
        reason=""
        if git -C "$repo" merge-base --is-ancestor "refs/heads/$b" "$default_ref" 2>/dev/null; then
            reason="reachable"
        else
            if [ "$landed_built" -eq 0 ]; then
                git -C "$repo" log "$default_ref" --format='%s' 2>/dev/null \
                    | grep -oE "\($BEAD_RE\)" | tr -d '()' | sort -u > "$WORK/landed" 2>/dev/null || : > "$WORK/landed"
                landed_built=1
            fi
            if grep -qxF "$bead" "$WORK/landed" 2>/dev/null; then reason="squashed"; fi
        fi
        [ -n "$reason" ] || continue

        printf '%s%s%s%s%s\n' "$bead" "$US" "$b" "$US" "$reason" >> "$WORK/brplan"
        [ "$DRY_RUN" -eq 1 ] && continue

        # Gone-origin branches go through git's own merged-check first, a second
        # gate over the proof above; a squash tip it cannot see as merged falls
        # to the force delete, which the proof has already made safe.
        dropped=""
        if [ "$(git -C "$repo" for-each-ref --format='%(upstream:track)' "refs/heads/$b" 2>/dev/null)" = "[gone]" ]; then
            git -C "$repo" branch -d "$b" >/dev/null 2>&1 || true
            git -C "$repo" show-ref --verify --quiet "refs/heads/$b" || dropped="-d"
        fi
        if [ -z "$dropped" ]; then
            git -C "$repo" branch -D "$b" >/dev/null 2>&1 || true
            git -C "$repo" show-ref --verify --quiet "refs/heads/$b" && continue
            dropped="-D"
        fi
        BR_DROPPED=$((BR_DROPPED + 1))
        if [ "$dropped" = "-d" ]; then BR_D=$((BR_D + 1)); else BR_BIGD=$((BR_BIGD + 1)); fi
    done
done

gib() { awk -v k="$1" 'BEGIN { printf "%.2f", k / 1048576 }'; }

if [ "$DRY_RUN" -eq 1 ]; then
    echo "$PROG: DRY RUN — $TOTAL registered worktrees across ${#REPO_PATHS[@]} repositories"
    echo "  would remove $planned worktrees, each pinned as $TAG_PREFIX/<bead>@<sha> first"
    # The whole plan, not a sample: --dry-run is the operator's review surface,
    # and a truncated list is not something anyone can approve.
    awk -F"$US" '{ printf "    %s  %s\n", $1, $2 }' "$WORK/plan"
    if [ -s "$WORK/brplan" ]; then
        brc=$(wc -l < "$WORK/brplan"); brc=$((brc))
        echo "  would drop $brc stale local branches, each naming a closed bead whose content is already on the default branch"
        awk -F"$US" '{ printf "    %s  %s  (%s)\n", $1, $2, $3 }' "$WORK/brplan"
    fi
    for repo in "${!REPO_HELD[@]}"; do echo "  held $repo: ${REPO_HELD[$repo]}"; done
    exit 0
fi

FS_AFTER="$(df -Pk "${REPO_PATHS[0]}" 2>/dev/null | awk 'NR == 2 { print $4 }')"; FS_AFTER="${FS_AFTER:-0}"
printf '%s: removed %d of %d registered worktrees in %ss — free space on %s: %s -> %s GiB\n' \
    "$PROG" "$removed" "$TOTAL" "$(($(date +%s) - START))" "${REPO_PATHS[0]}" "$(gib "$FS_BEFORE")" "$(gib "$FS_AFTER")"
for repo in "${!REMOVED[@]}"; do
    printf '%s:   %s — removed %d\n' "$PROG" "$repo" "${REMOVED[$repo]}"
done
[ "$BR_DROPPED" -gt 0 ] && printf '%s: dropped %d stale local branches (%d via git branch -d, %d via -D); no content lost — each was already on the default branch\n' "$PROG" "$BR_DROPPED" "$BR_D" "$BR_BIGD"
[ "$refused" -gt 0 ] && echo "$PROG: $refused removals refused (dirty tree, or the tip could not be pinned) — left for the next pass"
[ "$survived" -gt 0 ] && echo "$PROG: $survived removals reported success and left the directory standing — investigate, they freed nothing"
for repo in "${!REPO_HELD[@]}"; do
    echo "$PROG: held $repo — ${REPO_HELD[$repo]}; its worktrees and branches are the next pass's"
done
[ -n "$stopped" ] && echo "$PROG: yielded — ${BUDGET}s budget spent with $((planned - removed - refused - survived)) planned removals untaken; the next pass takes them"
[ -n "$br_stopped" ] && echo "$PROG: branch pass yielded on the ${BUDGET}s budget; the next pass drops the rest"
exit 0
