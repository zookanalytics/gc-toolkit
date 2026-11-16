#!/usr/bin/env bash
# review-workspace.sh — one review's directory on disk, and its reclaim.
#
# A review reads its pinned commit in a detached worktree, and runs there any
# suite its check calls for. The worktree belongs to the review, not to the
# shell that made it: a reviewer works across many shells, so a teardown bound
# to one of them either fires before the later shells run or is never
# installed, and each checkout left behind counts against the per-uid tmpfs
# quota (docs/scratch-reclaim.md).
#
# So a review's workspace is a directory named for its review bead, and any
# shell rebuilds the path from the bead id alone:
# <dir>/gc-review-<review-bead>, where <dir> is REVIEW_WORKSPACE_DIR, else
# $TMPDIR, else /tmp. The worktree is <workspace>/wt, and whatever else the
# review writes to disk goes beside it.
#
# A review run (formulas/mol-pr-review.toml) is the same, named for the run's
# root: <dir>/gc-review-<root>. Its steps are claimed by different sessions, so
# each takes a part of the workspace of its own, a directory holding a detached
# worktree in wt and whatever else the step writes beside it: triage takes
# triage, each lane takes lane-<check>, and rule-and-repair takes repair, the
# run's one worktree from which its fixes are pushed onto the PR's branch. A
# lane at a later iteration takes its part at the new head, so lanes that build,
# test or capture never share a tree, and the reap removes the whole workspace
# once the run's root closes, after the run has ruled every finding.
#
# Usage:
#   review-workspace.sh path   (--review-bead <id> | --root <id>)
#       print the workspace path
#   review-workspace.sh add    --review-bead <id> --oid <commit> [--repo <dir>]
#       print the path of <workspace>/wt, a worktree of <dir>'s repository
#       (default: the current directory) detached at <commit>. A worktree
#       already there at that commit is reused as it stands.
#   review-workspace.sh add    --root <id> (--triage | --lane <check> | --repair)
#                              --oid <commit> [--repo <dir>]
#       the same for the run's part: print <workspace>/<part>/wt. The repair
#       part is the run's one writing tree, so a worktree there at <commit> or
#       at a commit that descends from it is kept as it stands, with its own
#       commits and its uncommitted edits, and one at any other commit is
#       refused and kept (exit 3), never made again at <commit>
#   review-workspace.sh remove (--review-bead <id> | --root <id>)
#       remove the workspace now
#   review-workspace.sh reap [--dry-run]
#       remove every review workspace whose review or run has ended
#
# Removal takes each git worktree inside a workspace with `git worktree
# remove`, deepest first, so its registration goes with its directory. Nothing
# here runs `git worktree prune`, which is repository-wide: it drops the admin
# HEAD of every other worktree whose directory has gone, which for a detached
# worktree can be the only ref to its commits (docs/worktree-reclaim.md).
#
# reap reads every gc-review-* entry this user owns directly under the
# directory, and under /tmp as well unless REVIEW_WORKSPACE_DIR names the one
# to read. The bead an entry is named for is a review bead or a run's root,
# and either closes when its review ends. It takes an entry only when no
# process has its cwd or an open file inside it, and either
#   - the entry is named gc-review-<id> for a bead whose prefix is one of the
#     city's, and that bead is closed; or
#   - the entry names no such bead, or a bead the ledger no longer has, and
#     nothing inside it has changed for REVIEW_WORKSPACE_IDLE_AFTER (24h).
# A named bead that is not closed holds its workspace at any age, and so does
# one whose status cannot be read: an unreadable ledger is not a closed review.
# An entry whose age cannot be read is held the same way.
#
# Env: REVIEW_WORKSPACE_DIR, REVIEW_WORKSPACE_IDLE_AFTER (seconds).
# Exit: 0 done, or nothing to do · 1 add could not make the worktree, remove
#       left the workspace behind, or reap could not read the city's rigs ·
#       2 usage · 3 add refused the repair part's worktree, which is not at
#       --oid or past it, and kept it as it stands.
# Callers: formulas/mol-review.toml and mol-review-quorum-signoff.toml (add,
# path, remove); formulas/mol-rig-demo.toml (add); review-run.sh, for the
# steps of formulas/mol-pr-review.toml and mol-pr-review-lane.toml (path and
# add with --root); orders/review-workspace-reap.toml (reap). See
# docs/review-workspace.md.
set -uo pipefail

PROG="${0##*/}"
usage() {
    echo "usage: $PROG path|remove (--review-bead <id> | --root <id>)" >&2
    echo "       $PROG add --review-bead <id> --oid <commit> [--repo <dir>]" >&2
    echo "       $PROG add --root <id> (--triage | --lane <check> | --repair) --oid <commit> [--repo <dir>]" >&2
    echo "       $PROG reap [--dry-run]" >&2
    exit 2
}

[ "$#" -ge 1 ] || usage
CMD="$1"; shift
BEAD=""; ROOT=""; PART=""; OID=""; REPO="."; DRY_RUN=0
part() { [ -z "$PART" ] || usage; PART="$1"; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --review-bead) [ "$#" -ge 2 ] || usage; BEAD="$2"; shift 2 ;;
        --root)        [ "$#" -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --triage)      part triage; shift ;;
        --repair)      part repair; shift ;;
        --lane)        [ "$#" -ge 2 ] || usage
                       case "$2" in '' | *[!A-Za-z0-9_-]*) echo "$PROG: --lane takes a check's name, got '$2'" >&2; exit 2 ;; esac
                       part "lane-$2"; shift 2 ;;
        --oid)         [ "$#" -ge 2 ] || usage; OID="$2"; shift 2 ;;
        --repo)        [ "$#" -ge 2 ] || usage; REPO="$2"; shift 2 ;;
        --dry-run)     DRY_RUN=1; shift ;;
        *) echo "$PROG: unknown argument: $1" >&2; usage ;;
    esac
done
# A review bead and a run's root name a workspace the same way; a part belongs
# to a run's workspace alone.
if [ -n "$ROOT" ]; then
    [ -z "$BEAD" ] || usage
    BEAD="$ROOT"
elif [ -n "$PART" ]; then
    usage
fi

UID_NUM="$(id -u)"
IDLE_AFTER="${REVIEW_WORKSPACE_IDLE_AFTER:-86400}"
case "$IDLE_AFTER" in
    '' | *[!0-9]*) echo "$PROG: REVIEW_WORKSPACE_IDLE_AFTER must be a whole number of seconds" >&2; exit 2 ;;
esac
[ "$IDLE_AFTER" -gt 0 ] || { echo "$PROG: REVIEW_WORKSPACE_IDLE_AFTER must be positive" >&2; exit 2; }

# `git -C <wt> worktree remove <wt>` resolves <wt> after changing into it, so
# every path handed to git must be absolute.
DIR="${REVIEW_WORKSPACE_DIR:-${TMPDIR:-/tmp}}"
case "$DIR" in /*) ;; *) DIR="$PWD/$DIR" ;; esac
DIR="${DIR%/}"; DIR="${DIR:-/}"

# The bead id becomes a path that remove deletes recursively, so it must be a
# bare name: no '/', and no '.' leading or doubled.
valid_bead() {
    case "$1" in '' | *[!A-Za-z0-9._-]* | .* | *..*) return 1 ;; esac
    return 0
}
workspace() { printf '%s/gc-review-%s\n' "$DIR" "$1"; }
gone() { [ ! -e "$1" ] && [ ! -L "$1" ]; }

# Remove one entry; succeed only when it is gone. Worktrees inside go first,
# deepest first so a nested one is not orphaned by its parent's removal, each
# through its own repository; a path's depth is its count of '/', counted here
# because find's -printf is GNU-only. Then the tree, made writable first: a
# read-only subtree (a Go module cache) refuses rm, and a swallowed refusal
# frees nothing. chmod -R does not follow the symlinks it meets inside the tree.
teardown() { # <absolute path>
    local p="$1" g s
    if [ -d "$p" ] && [ ! -L "$p" ]; then
        while IFS= read -r -d '' g; do
            g="${g#*$'\t'}"
            git -C "${g%/.git}" worktree remove --force --force "${g%/.git}" >/dev/null 2>&1 || true
        done < <(find -P "$p" -xdev -name .git -type f -print0 2>/dev/null \
                   | while IFS= read -r -d '' g; do s="${g//[!\/]/}"; printf '%d\t%s\0' "${#s}" "$g"; done \
                   | sort -z -t "$(printf '\t')" -k1,1rn)
        chmod -R u+w "$p" 2>/dev/null || true
    fi
    rm -rf -- "$p" 2>/dev/null || true
    gone "$p"
}

cmd_path() {
    valid_bead "$BEAD" && [ -z "$PART" ] || usage
    workspace "$BEAD"
}

cmd_add() {
    valid_bead "$BEAD" && [ -n "$OID" ] || usage
    [ -z "$ROOT" ] || [ -n "$PART" ] || usage
    local ws wt commit
    ws="$(workspace "$BEAD")"; wt="$ws/wt"
    [ -z "$PART" ] || wt="$ws/$PART/wt"
    commit="$(git -C "$REPO" rev-parse --verify -q "$OID^{commit}")" \
        || { echo "$PROG: $OID is not a commit in $REPO" >&2; exit 1; }
    mkdir -m 700 "$ws" 2>/dev/null
    # /tmp is shared: a name another user or a link got to first is not ours.
    if [ -L "$ws" ] || [ ! -d "$ws" ] || [ ! -O "$ws" ]; then
        echo "$PROG: cannot use $ws: it must be a directory this user owns" >&2
        exit 1
    fi
    if [ -n "$PART" ]; then
        mkdir -m 700 "$ws/$PART" 2>/dev/null
        if [ -L "$ws/$PART" ] || [ ! -d "$ws/$PART" ]; then
            echo "$PROG: cannot use $ws/$PART: it must be a directory" >&2
            exit 1
        fi
    fi
    # Parallel shells of one review can run add at once. The lock makes the
    # later one wait and then find the worktree, rather than race the first
    # into `git worktree add`.
    if command -v flock >/dev/null 2>&1; then
        exec 9<"$ws" && flock -w 300 9 \
            || { echo "$PROG: timed out waiting for another add on $ws" >&2; exit 1; }
    fi
    if [ -f "$wt/.git" ]; then
        local at
        at="$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null)"
        if [ -n "$at" ] && [ "$at" = "$commit" ]; then
            printf '%s\n' "$wt"
            return 0
        fi
        # The repair part holds the round's fixes: its commits on the head and
        # the edits not yet committed, which a tree made again at the head
        # would lose. So it keeps a tree that is at the head or past it, and
        # refuses any other rather than remove it. Triage's and the lanes'
        # parts only read, so theirs are made again at the head they read.
        if [ "$PART" = repair ]; then
            if [ -n "$at" ] && git -C "$wt" merge-base --is-ancestor "$commit" "$at" 2>/dev/null; then
                echo "$PROG: keeping $wt as it stands, $(git -C "$wt" rev-list --count "$commit..$at") commit(s) past $commit" >&2
                printf '%s\n' "$wt"
                return 0
            fi
            echo "$PROG: $wt is at ${at:-no commit git can read}, which is not $commit or past it, so it is kept as it stands and not made again at $commit" >&2
            exit 3
        fi
    fi
    gone "$wt" || teardown "$wt" || { echo "$PROG: cannot clear $wt" >&2; exit 1; }
    # --force: a registration whose directory was deleted by hand still claims
    # the path, and the path is this review's own.
    git -C "$REPO" worktree add --force --detach "$wt" "$commit" >&2 \
        || { echo "$PROG: git worktree add failed for $wt" >&2; exit 1; }
    printf '%s\n' "$wt"
}

cmd_remove() {
    valid_bead "$BEAD" && [ -z "$PART" ] || usage
    local ws
    ws="$(workspace "$BEAD")"
    gone "$ws" && { echo "$PROG: no workspace at $ws"; return 0; }
    teardown "$ws" || { echo "$PROG: $ws could not be removed" >&2; exit 1; }
    echo "$PROG: removed $ws"
}

# --- reap -------------------------------------------------------------------
declare -A RIG_DB=()   # bead prefix -> that rig's store

# The bead an entry is named for, as "<id><TAB><store>": the whole name after
# gc-review-, when it is one of the city's prefixes followed by a bead hash.
# Prints nothing for any other name.
bead_of() { # <entry basename>
    local id="${1#gc-review-}" p
    for p in "${!RIG_DB[@]}"; do
        case "$id" in "$p"-*) ;; *) continue ;; esac
        [[ "${id#"$p"-}" =~ ^[a-z0-9]+(\.[0-9]+)*$ ]] || continue
        printf '%s\t%s\n' "$id" "${RIG_DB[$p]}"
        return 0
    done
}

# closed | live | missing | unknown. Only a row that reads closed is closed,
# and only bd's own not-found answer is missing; anything else is unknown,
# which holds.
bead_state() { # <id> <store>
    local raw st
    raw="$(gc bd show "$1" --db "$2" --json </dev/null 2>/dev/null)"
    if printf '%s' "$raw" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        st="$(printf '%s' "$raw" | jq -r '.[0].status // ""' 2>/dev/null)"
        case "$st" in closed) echo closed ;; '') echo unknown ;; *) echo live ;; esac
    elif printf '%s' "$raw" | jq -e 'type == "object" and ((.error // "") | test("no issues found"))' >/dev/null 2>&1; then
        echo missing
    else
        echo unknown
    fi
}

# Whether a process has its cwd, or a file open, inside <path>. Read fresh for
# each removal, because the gap between deciding and removing is a race. lsof
# lists the cwd and open files of every process this user can see, on Linux
# and macOS alike, and exits 0 on a walk it completed. A listing that failed,
# or that names no file at all, not even lsof's own, is a broken probe and
# reads as in use.
in_use() { # <path>
    local listing
    listing="$(lsof -w -n -P -F n 2>/dev/null)" || return 0
    awk -v p="$1" 'sub(/^n/, "") { n++; if (index($0, p "/") == 1 || $0 == p) f = 1 }
                   END { exit (n == 0 || f) ? 0 : 1 }' <<< "$listing"
}

# GNU stat takes its format after -c and BSD stat after -f. Both read %u as the
# owner's uid, of a symlink itself rather than what it names; the mtime in
# epoch seconds is %Y in GNU and %m in BSD.
if stat -c %u -- / >/dev/null 2>&1; then STAT=(stat -c); MTIME=%Y; else STAT=(stat -f); MTIME=%m; fi

# Newest mtime anywhere inside, directories included, so one stale file cannot
# condemn a workspace that is still in use. A walk that read no mtime, not even
# the entry's own, prints nothing.
newest() {
    find -P "$1" -xdev -exec "${STAT[@]}" "$MTIME" -- {} + 2>/dev/null \
        | awk '/^[0-9]+$/ { n++; if ($1 + 0 > m) m = $1 + 0 } END { if (n) print m + 0 }'
}
gib() { awk -v k="$1" 'BEGIN { printf "%.2f", k / 1048576 }'; }

cmd_reap() {
    local rigs prefix path d e name hit id st mt age kb seen=" " now dirs=()
    local took_closed=0 took_idle=0 took_kb=0 failed=0
    local kept_live=0 kept_unread=0 kept_active=0 kept_held=0
    rigs="$("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rig-map.sh" \
        | jq -r '.rigs[]? | select((.prefix // "") != "" and (.path // "") != "") | [.prefix, .path] | @tsv' 2>/dev/null)" || rigs=""
    [ -n "$rigs" ] || { echo "$PROG: could not read the city's rigs; reaping nothing" >&2; exit 1; }
    while IFS=$'\t' read -r prefix path; do RIG_DB["$prefix"]="$path/.beads"; done <<< "$rigs"

    # A reviewer's TMPDIR need not match this process's, so /tmp, where a shell
    # with no TMPDIR puts a workspace, is read as well.
    if [ -n "${REVIEW_WORKSPACE_DIR:-}" ]; then dirs=("$DIR"); else dirs=("$DIR" /tmp); fi

    keep() { [ "$DRY_RUN" -eq 1 ] && echo "  keep   $1 ($2)"; return 0; }
    take() { # <path> <why>; succeeds only when the entry is gone
        if in_use "$1"; then
            kept_held=$((kept_held + 1)); keep "$1" "in use by a process"; return 1
        fi
        if [ "$DRY_RUN" -eq 1 ]; then echo "  remove $1 ($2)"; return 0; fi
        kb="$(du -sk -- "$1" 2>/dev/null | awk 'NR == 1 { print $1 }')"
        if teardown "$1"; then took_kb=$((took_kb + ${kb:-0})); return 0; fi
        echo "$PROG: could not remove $1" >&2
        failed=$((failed + 1))
        return 1
    }

    [ "$DRY_RUN" -eq 1 ] && echo "$PROG: DRY RUN"
    now="$(date +%s)"
    for d in "${dirs[@]}"; do
        d="$(cd "$d" 2>/dev/null && pwd -P)" || continue
        case "$seen" in *" $d "*) continue ;; esac
        seen="$seen$d "
        for e in "$d"/gc-review-*; do
            gone "$e" && continue
            [ "$("${STAT[@]}" %u -- "$e" 2>/dev/null)" = "$UID_NUM" ] || continue
            name="${e##*/}"
            hit="$(bead_of "$name")"; id="${hit%%$'\t'*}"
            st=missing
            [ -n "$hit" ] && st="$(bead_state "$id" "${hit#*$'\t'}")"
            case "$st" in
                closed)
                    take "$e" "review $id closed" && took_closed=$((took_closed + 1))
                    continue ;;
                live)    kept_live=$((kept_live + 1)); keep "$e" "review $id not closed"; continue ;;
                unknown) kept_unread=$((kept_unread + 1)); keep "$e" "status of $id unreadable"; continue ;;
            esac
            mt="$(newest "$e")"
            if [ -z "$mt" ]; then
                kept_unread=$((kept_unread + 1)); keep "$e" "age unreadable"; continue
            fi
            age=$((now - mt))
            if [ "$age" -ge "$IDLE_AFTER" ]; then
                take "$e" "no live review named, idle $((age / 3600))h" && took_idle=$((took_idle + 1))
            else
                kept_active=$((kept_active + 1)); keep "$e" "changed $((age / 3600))h ago"
            fi
        done
    done
    [ "$DRY_RUN" -eq 1 ] && return 0
    printf '%s: removed %d workspaces (%s GiB): %d of closed reviews, %d idle; kept %d of reviews not closed, %d in use, %d unreadable, %d active\n' \
        "$PROG" $((took_closed + took_idle)) "$(gib "$took_kb")" "$took_closed" "$took_idle" \
        "$kept_live" "$kept_held" "$kept_unread" "$kept_active"
    [ "$failed" -eq 0 ] || echo "$PROG: $failed could not be removed; the next pass retries them"
    return 0
}

case "$CMD" in
    path)   cmd_path ;;
    add)    cmd_add ;;
    remove) cmd_remove ;;
    reap)   cmd_reap ;;
    *)      usage ;;
esac
