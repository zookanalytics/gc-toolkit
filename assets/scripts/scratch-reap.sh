#!/usr/bin/env bash
# scratch-reap.sh — bound the retention of Claude Code agent scratch.
#
# Every agent session gets a private tree under the harness scratch root
# ($TMPDIR/claude-<uid>/<project-slug>/<session-id>/): a scratchpad, task
# output, shell snapshots. Nothing reclaims it when the session ends, so the
# tree is a standing floor under the per-uid tmpfs quota, and the binding
# limit is that quota rather than tmpfs capacity — `df` reports free space the
# quota will not hand out. Exhausting it is a city-wide outage rather than a
# disk problem: every command that prints fails with empty output while silent
# ones still succeed.
#
# Two horizons, because the two costs are different. Bytes live in files, so
# a session tree that has not been touched in EMPTY_AFTER loses its FILES and
# keeps its directories — a still-live session that has simply been idle finds
# its scratchpad where it left it. Inodes live in directories, so the tree
# itself goes only at REMOVE_AFTER, long past any plausible idle window.
#
# A session with a running child process is skipped outright, whatever its
# mtime: Claude Code exports CLAUDE_CODE_SESSION_ID to its children, so /proc
# names the sessions that are certainly alive. The signal is one-directional —
# a session between turns owns no process and does not appear — so it only
# ever protects, and the horizons carry the rest.
#
# Scope is the harness scratch root and nothing else. Other /tmp tenants
# (worktrees, build roots, tool temp dirs) are their own owners' to reclaim.
#
# Reclaim is reported as MEASURED before/after bytes, never as a count of
# removals: read-only trees (a Go module cache copied into scratch) refuse
# deletion, and a wrapped `rm -rf` reports success while freeing nothing. The
# chmod below is what makes them deletable; the measurement is what proves it.
#
# Usage:
#   scratch-reap.sh              reap, print one summary line
#   scratch-reap.sh --dry-run    report the plan, touch nothing
# Env: SCRATCH_REAP_ROOT, SCRATCH_REAP_EMPTY_AFTER, SCRATCH_REAP_REMOVE_AFTER,
#      SCRATCH_REAP_BUDGET (all seconds except the root).
# Exit: 0 reaped or nothing to do · 2 usage or an unsafe root.
# Caller: the scratch-reap exec order. See docs/scratch-reclaim.md.
set -euo pipefail

PROG="${0##*/}"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "$PROG: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

UID_NUM="$(id -u)"
ROOT="${SCRATCH_REAP_ROOT:-${TMPDIR:-/tmp}/claude-$UID_NUM}"
EMPTY_AFTER="${SCRATCH_REAP_EMPTY_AFTER:-43200}"    # 12h — files
REMOVE_AFTER="${SCRATCH_REAP_REMOVE_AFTER:-259200}" # 72h — the tree
BUDGET="${SCRATCH_REAP_BUDGET:-240}"

for v in EMPTY_AFTER REMOVE_AFTER BUDGET; do
    case "${!v}" in
        '' | *[!0-9]*) echo "$PROG: SCRATCH_REAP_$v must be a whole number of seconds" >&2; exit 2 ;;
    esac
done
[ "$EMPTY_AFTER" -gt 0 ] || { echo "$PROG: SCRATCH_REAP_EMPTY_AFTER must be positive" >&2; exit 2; }
[ "$REMOVE_AFTER" -ge "$EMPTY_AFTER" ] || {
    echo "$PROG: SCRATCH_REAP_REMOVE_AFTER ($REMOVE_AFTER) must be >= SCRATCH_REAP_EMPTY_AFTER ($EMPTY_AFTER)" >&2
    exit 2
}

# Rails on the root. The script deletes recursively, so it refuses anything
# that is not a scratch root this user owns: the basename names the harness
# and the uid, symlinks are resolved before the check (a link cannot smuggle
# in another tree), and every walk below is -xdev and -P.
[ -d "$ROOT" ] || { echo "$PROG: no scratch root at $ROOT — nothing to reap"; exit 0; }
ROOT="$(cd "$ROOT" && pwd -P)"
case "${ROOT##*/}" in
    "claude-$UID_NUM") : ;;
    *) echo "$PROG: refusing to reap '$ROOT' — the root must be a claude-$UID_NUM scratch directory" >&2; exit 2 ;;
esac
[ -O "$ROOT" ] || { echo "$PROG: refusing to reap '$ROOT' — not owned by uid $UID_NUM" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LIVE="$WORK/live"; REMOVE_LIST="$WORK/remove"; EMPTY_LIST="$WORK/empty"
STRAY_LIST="$WORK/stray"; BIG_LIST="$WORK/big"
: > "$LIVE"; : > "$REMOVE_LIST"; : > "$EMPTY_LIST"; : > "$STRAY_LIST"; : > "$BIG_LIST"

# Sessions with a running child. Best-effort and quiet: most of /proc belongs
# to other uids and is unreadable, which is the expected case, not an error.
# environ is NUL-separated, so -a reads it as text and -o cuts the one setting
# out of it.
grep -aho 'CLAUDE_CODE_SESSION_ID=[A-Za-z0-9-]*' /proc/[0-9]*/environ 2>/dev/null \
    | sed 's/^CLAUDE_CODE_SESSION_ID=//' > "$LIVE" || true
sort -u -o "$LIVE" "$LIVE"
LIVE_N=$(wc -l < "$LIVE")

START=$(date +%s)
# du and find both walk a tree other processes are writing; a vanished entry
# is an expected non-zero exit, not a reason to abandon the pass.
tree_kb() { du -sk "$1" 2>/dev/null | awk 'NR == 1 { print $1 }' || true; }
BEFORE_KB="$(tree_kb "$ROOT")"; BEFORE_KB="${BEFORE_KB:-0}"

# One walk answers every question. Each session tree is aged by the NEWEST
# mtime anywhere in it, including its directories, so a tree whose only recent
# activity was a mkdir still reads as active. Malformed rows — a newline in a
# filename splits one entry across two lines — fail the type test and are
# skipped, which loses a reap rather than misdirecting one.
remove_n=0; remove_b=0; empty_n=0; empty_b=0; stray_n=0; stray_b=0
keep_n=0; keep_b=0; live_n=0; live_b=0
{ find -P "$ROOT" -mindepth 1 -xdev -printf '%y\t%T@\t%s\t%p\n' 2>/dev/null || true; } \
  | awk -v root="$ROOT" -v now="$START" \
        -v empty_after="$EMPTY_AFTER" -v remove_after="$REMOVE_AFTER" \
        -v livefile="$LIVE" -v removefile="$REMOVE_LIST" \
        -v emptyfile="$EMPTY_LIST" -v strayfile="$STRAY_LIST" -v bigfile="$BIG_LIST" '
BEGIN {
    FS = "\t"
    while ((getline id < livefile) > 0) if (id != "") live[id] = 1
    close(livefile)
    skip = length(root) + 2   # strip "<root>/"
    big_floor = 8 * 1024 * 1024
}
$1 != "f" && $1 != "d" && $1 != "l" { next }
{
    typ = $1; mt = $2 + 0; sz = $3 + 0
    path = $4; for (i = 5; i <= NF; i++) path = path "\t" $i
    rel = substr(path, skip)
    n = split(rel, c, "/")

    # Loose files above a session tree are stray agent output, aging on
    # their own with no tree to protect them.
    if (n < 2 || (n == 2 && typ != "d")) {
        if (typ != "d" && now - mt >= empty_after) {
            printf "%s\0", path > strayfile
            stray_n++; stray_b += sz
        }
        next
    }

    key = c[1] "/" c[2]
    if (n == 2) session[key] = 1
    if (mt > newest[key]) newest[key] = mt
    if (typ != "d") {
        files[key]++
        bytes[key] += sz
        if (sz >= big_floor) { big_sz[path] = sz; big_key[path] = key }
    }
}
END {
    for (k in session) {
        split(k, c, "/")
        if (c[2] in live) { live_skipped++; live_bytes += bytes[k]; continue }
        age = now - newest[k]
        # A tree already down to bare directories has nothing to empty; it
        # waits for the remove horizon rather than being re-listed every pass.
        if (age >= remove_after)                     { printf "%s/%s\0", root, k > removefile; rm_n++; rm_b += bytes[k]; doomed[k] = 1 }
        else if (age >= empty_after && files[k] > 0) { printf "%s/%s\0", root, k > emptyfile;  em_n++; em_b += bytes[k]; doomed[k] = 1 }
        else                                         { keep_n++; keep_b += bytes[k] }
    }
    for (p in big_sz) if (big_key[p] in doomed) printf "%d\t%s\n", big_sz[p], p > bigfile
    printf "remove_n=%d\nremove_b=%d\nempty_n=%d\nempty_b=%d\nstray_n=%d\nstray_b=%d\nkeep_n=%d\nkeep_b=%d\nlive_n=%d\nlive_b=%d\n", \
        rm_n, rm_b, em_n, em_b, stray_n, stray_b, keep_n, keep_b, live_skipped, live_bytes
}' > "$WORK/plan" || true

# shellcheck disable=SC1090  # a generated key=value file, not a script
. "$WORK/plan"

gib() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1073741824 }'; }

# The largest files this pass is taking, so a recurring writer stays visible in
# the order log rather than only in the total.
big_report() { # <printf format taking MiB then path>
    [ -s "$BIG_LIST" ] || return 0
    sort -rn "$BIG_LIST" 2>/dev/null | head -5 \
        | awk -F'\t' -v fmt="$1\n" '{ printf fmt, $1 / 1048576, $2 }' || true
}

if [ "$DRY_RUN" -eq 1 ]; then
    echo "$PROG: DRY RUN — root $ROOT"
    echo "  would remove $remove_n session trees ($(gib "$remove_b") GiB), empty $empty_n ($(gib "$empty_b") GiB), delete $stray_n stray files ($(gib "$stray_b") GiB)"
    echo "  would keep $keep_n trees ($(gib "$keep_b") GiB); $live_n live sessions held ($(gib "$live_b") GiB), $LIVE_N session ids seen running"
    big_report "  large: %.0f MiB  %s"
    exit 0
fi

over_budget() { [ "$BUDGET" -gt 0 ] && [ $(($(date +%s) - START)) -ge "$BUDGET" ]; }

# chmod before delete: a read-only tree refuses deletion, and a swallowed
# refusal frees nothing while reporting success. Every batch tolerates a
# partial failure and keeps going, because the before/after measurement is
# what reports the truth either way.
#
# Removal runs unguarded and the cheaper tiers yield to the budget: removal is
# where the bytes are, and a pass that spent its budget walking should still
# take them. A tier that yields reports zero, never its plan.
STOPPED=""
if [ -s "$REMOVE_LIST" ]; then
    xargs -0 -r chmod -R u+w < "$REMOVE_LIST" 2>/dev/null || true
    xargs -0 -r rm -rf       < "$REMOVE_LIST" 2>/dev/null || true
fi
if [ -s "$EMPTY_LIST" ] && ! over_budget; then
    xargs -0 -r chmod -R u+w < "$EMPTY_LIST" 2>/dev/null || true
    xargs -0 -r sh -c 'find -P "$@" -mindepth 1 -xdev \( -type f -o -type l \) -delete' _ \
        < "$EMPTY_LIST" 2>/dev/null || true
elif [ -s "$EMPTY_LIST" ]; then
    STOPPED="empty"; empty_n=0
fi
if [ -s "$STRAY_LIST" ] && ! over_budget; then
    xargs -0 -r chmod u+w < "$STRAY_LIST" 2>/dev/null || true
    xargs -0 -r rm -f     < "$STRAY_LIST" 2>/dev/null || true
elif [ -s "$STRAY_LIST" ]; then
    STOPPED="${STOPPED:-stray}"; stray_n=0
fi

# Project-slug directories that lost their last session. Depth-pinned: an
# empty directory INSIDE a session tree is a scratchpad an idle session still
# expects to find.
find -P "$ROOT" -mindepth 1 -maxdepth 1 -xdev -type d -empty -delete 2>/dev/null || true

AFTER_KB="$(tree_kb "$ROOT")"; AFTER_KB="${AFTER_KB:-0}"
FREED_KB=$((BEFORE_KB - AFTER_KB))
[ "$FREED_KB" -ge 0 ] || FREED_KB=0

printf '%s: freed %s GiB (%s -> %s GiB) in %ss — removed %d trees, emptied %d, deleted %d stray files; kept %d trees, held %d live\n' \
    "$PROG" "$(gib $((FREED_KB * 1024)))" "$(gib $((BEFORE_KB * 1024)))" "$(gib $((AFTER_KB * 1024)))" \
    "$(($(date +%s) - START))" "$remove_n" "$empty_n" "$stray_n" "$keep_n" "$live_n"
if [ -n "$STOPPED" ]; then
    echo "$PROG: yielded at the $STOPPED batch — ${BUDGET}s budget spent; the next pass takes it"
fi
big_report "$PROG: reaped %.0f MiB  %s"
exit 0
