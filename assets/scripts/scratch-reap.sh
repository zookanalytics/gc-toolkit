#!/usr/bin/env bash
# scratch-reap.sh — remove the scratch of Claude Code sessions that have gone
# inactive.
#
# Every agent session gets a private tree under the harness scratch root
# ($TMPDIR/claude-<uid>/<project-slug>/<session-id>/): a scratchpad, task
# output, shell snapshots. Nothing reclaims it when the session ends, so the
# trees are a standing floor under the per-uid tmpfs quota, and the binding
# limit is that quota rather than tmpfs capacity — `df` reports free space the
# quota will not hand out. Exhausting it is a city-wide outage rather than a
# disk problem: every command that prints fails with empty output while silent
# ones still succeed.
#
# One rule. A session tree untouched for INACTIVE_AFTER is removed whole, and
# files loose above the session trees age the same way. A tree is aged by the
# NEWEST entry anywhere inside it, directories included, so one stale file
# cannot condemn a session that is still working.
#
# A session with a running child process is held whatever its mtime: Claude
# Code exports CLAUDE_CODE_SESSION_ID to its children, so /proc names the
# sessions that are certainly alive. The signal is one-directional — a session
# between turns owns no process and does not appear — so it only ever protects,
# and the horizon carries the rest.
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
# Env: SCRATCH_REAP_ROOT, SCRATCH_REAP_INACTIVE_AFTER, SCRATCH_REAP_BUDGET
#      (seconds, except the root).
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
INACTIVE_AFTER="${SCRATCH_REAP_INACTIVE_AFTER:-86400}" # 24h
BUDGET="${SCRATCH_REAP_BUDGET:-240}"

for v in INACTIVE_AFTER BUDGET; do
    case "${!v}" in
        '' | *[!0-9]*) echo "$PROG: SCRATCH_REAP_$v must be a whole number of seconds" >&2; exit 2 ;;
    esac
done
[ "$INACTIVE_AFTER" -gt 0 ] || { echo "$PROG: SCRATCH_REAP_INACTIVE_AFTER must be positive" >&2; exit 2; }

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
LIVE="$WORK/live"; REMOVE_LIST="$WORK/remove"
STRAY_LIST="$WORK/stray"; STRAY_LINK_LIST="$WORK/stray-links"
BIG_TREE_LIST="$WORK/big-tree"; BIG_STRAY_LIST="$WORK/big-stray"
: > "$LIVE"; : > "$REMOVE_LIST"; : > "$STRAY_LIST"; : > "$STRAY_LINK_LIST"
: > "$BIG_TREE_LIST"; : > "$BIG_STRAY_LIST"

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

# One walk answers every question. Malformed rows — a newline in a filename
# splits one entry across two lines — fail the type test and are skipped, which
# loses a reap rather than misdirecting one.
remove_n=0; remove_b=0; stray_n=0; stray_b=0
keep_n=0; keep_b=0; live_n=0; live_b=0
{ find -P "$ROOT" -mindepth 1 -xdev -printf '%y\t%T@\t%s\t%p\n' 2>/dev/null || true; } \
  | awk -v root="$ROOT" -v now="$START" -v inactive_after="$INACTIVE_AFTER" \
        -v livefile="$LIVE" -v removefile="$REMOVE_LIST" \
        -v strayfile="$STRAY_LIST" -v straylinkfile="$STRAY_LINK_LIST" \
        -v bigtreefile="$BIG_TREE_LIST" -v bigstrayfile="$BIG_STRAY_LIST" '
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
    # their own with no tree to protect them. A stray SYMLINK goes on its own
    # list, because chmod dereferences a symlink argument: making one writable
    # would change the mode of the target instead, and a stray link can point
    # anywhere outside the root.
    if (n < 2 || (n == 2 && typ != "d")) {
        if (typ != "d" && now - mt >= inactive_after) {
            out = (typ == "l") ? straylinkfile : strayfile
            printf "%s\0", path > out
            stray_n++; stray_b += sz
            if (sz >= big_floor) printf "%d\t%s\n", sz, path > bigstrayfile
        }
        next
    }

    key = c[1] "/" c[2]
    if (n == 2) session[key] = 1
    if (mt > newest[key]) newest[key] = mt
    if (typ != "d") {
        bytes[key] += sz
        if (sz >= big_floor) { big_sz[path] = sz; big_key[path] = key }
    }
}
END {
    for (k in session) {
        split(k, c, "/")
        if (c[2] in live)                    { live_skipped++; live_bytes += bytes[k] }
        else if (now - newest[k] >= inactive_after) { printf "%s/%s\0", root, k > removefile; rm_n++; rm_b += bytes[k]; doomed[k] = 1 }
        else                                 { keep_n++; keep_b += bytes[k] }
    }
    for (p in big_sz) if (big_key[p] in doomed) printf "%d\t%s\n", big_sz[p], p > bigtreefile
    printf "remove_n=%d\nremove_b=%d\nstray_n=%d\nstray_b=%d\nkeep_n=%d\nkeep_b=%d\nlive_n=%d\nlive_b=%d\n", \
        rm_n, rm_b, stray_n, stray_b, keep_n, keep_b, live_skipped, live_bytes
}' > "$WORK/plan" || true

# shellcheck disable=SC1090  # a generated key=value file, not a script
. "$WORK/plan"

gib() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1073741824 }'; }

# The largest files this pass is taking, so a recurring writer stays visible in
# the order log rather than only in the total. It reads both tiers, and a tier
# that yields to the budget clears its own list, so the report never names a
# file that is still on disk.
big_report() { # <printf format taking MiB then path>
    sort -rn "$BIG_TREE_LIST" "$BIG_STRAY_LIST" 2>/dev/null | head -5 \
        | awk -F'\t' -v fmt="$1\n" '{ printf fmt, $1 / 1048576, $2 }' || true
}

if [ "$DRY_RUN" -eq 1 ]; then
    echo "$PROG: DRY RUN — root $ROOT"
    echo "  would remove $remove_n session trees ($(gib "$remove_b") GiB) and delete $stray_n stray files ($(gib "$stray_b") GiB)"
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
# Session trees run unguarded and the stray files yield to the budget: the
# trees are where the bytes are, and a pass that spent its budget walking
# should still take them. A tier that yields reports zero and names no files,
# never its plan — what it left behind is the next pass's to take and report.
STOPPED=""
if [ -s "$REMOVE_LIST" ]; then
    xargs -0 -r chmod -R u+w < "$REMOVE_LIST" 2>/dev/null || true
    xargs -0 -r rm -rf       < "$REMOVE_LIST" 2>/dev/null || true
fi
if { [ -s "$STRAY_LIST" ] || [ -s "$STRAY_LINK_LIST" ]; } && ! over_budget; then
    xargs -0 -r chmod u+w < "$STRAY_LIST" 2>/dev/null || true
    xargs -0 -r rm -f     < "$STRAY_LIST" 2>/dev/null || true
    xargs -0 -r rm -f     < "$STRAY_LINK_LIST" 2>/dev/null || true
elif [ -s "$STRAY_LIST" ] || [ -s "$STRAY_LINK_LIST" ]; then
    STOPPED="stray"; stray_n=0; : > "$BIG_STRAY_LIST"
fi

# Project-slug directories that lost their last session. Depth-pinned: a
# directory deeper than that belongs to a session the pass chose to keep.
find -P "$ROOT" -mindepth 1 -maxdepth 1 -xdev -type d -empty -delete 2>/dev/null || true

AFTER_KB="$(tree_kb "$ROOT")"; AFTER_KB="${AFTER_KB:-0}"
FREED_KB=$((BEFORE_KB - AFTER_KB))
[ "$FREED_KB" -ge 0 ] || FREED_KB=0

printf '%s: freed %s GiB (%s -> %s GiB) in %ss — removed %d session trees, deleted %d stray files; kept %d trees, held %d live\n' \
    "$PROG" "$(gib $((FREED_KB * 1024)))" "$(gib $((BEFORE_KB * 1024)))" "$(gib $((AFTER_KB * 1024)))" \
    "$(($(date +%s) - START))" "$remove_n" "$stray_n" "$keep_n" "$live_n"
if [ -n "$STOPPED" ]; then
    echo "$PROG: yielded at the $STOPPED batch — ${BUDGET}s budget spent; the next pass takes it"
fi
big_report "$PROG: reaped %.0f MiB  %s"
exit 0
