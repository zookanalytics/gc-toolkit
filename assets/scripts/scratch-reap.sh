#!/usr/bin/env bash
# scratch-reap.sh — remove the scratch of Claude Code sessions that have ended
# or gone inactive.
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
# Two rules. The horizon: a session tree untouched for INACTIVE_AFTER is
# removed whole, and files loose above the session trees age the same way. A
# tree is aged by the NEWEST entry anywhere inside it, directories included, so
# one stale file cannot condemn a session that is still working.
#
# A session with a running child process is held whatever its mtime: Claude
# Code exports CLAUDE_CODE_SESSION_ID to its children, so /proc names the
# sessions that are certainly alive. The signal is one-directional — a session
# between turns owns no process and does not appear — so it only ever protects,
# and the horizon carries the rest.
#
# Ended sessions: a tree whose session has ended is removed at the next pass
# rather than at the horizon. A session has ended when nothing can still own its
# tree, and three readings decide that, each only ever holding a tree:
#   - No process names its id, in CLAUDE_CODE_SESSION_ID or on a command line.
#     gc launches every agent session with --session-id or --resume, so an agent
#     between turns is named by its own claude process.
#   - No process standing in the session's project directory, or below it,
#     started before the tree was last written. Claude Code keeps its main
#     process in the directory it was launched from and names the tree after
#     that directory, so a session minted inside a running process (a /clear,
#     an interactive session) is written after that process started.
#   - No open gc session in any registered city holds the id as its key. A
#     sleeping session that wakes by --resume reuses its tree, and gc's list is
#     the only record of it, so a list that cannot be read in full judges
#     nothing and every tree waits for the horizon.
# A tree goes only when its last write is ENDED_AFTER older than the pass and
# than the earliest process standing in its directory, which covers a session
# starting mid-pass and the one-second resolution of a start time. Only a tree
# Claude Code wrote is judged: a UUID-named tree under a project directory
# named for an absolute path. A project name over 200 characters carries a hash
# of the path that cannot be recomputed here, so those trees wait for the
# horizon as well.
#
# A caller retiring a specific session names it with --session <id>: that one
# tree goes now, without the horizon and without the running-process hold. The
# retiring session is itself that running process, so the hold would refuse the
# very tree it means to take; the caller overrides it because it knows the
# session is done where the horizon only estimates. The hourly pass is the
# backstop for sessions that end without naming themselves.
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
#   scratch-reap.sh                reap, print one summary line
#   scratch-reap.sh --dry-run      report the plan, touch nothing
#   scratch-reap.sh --session <id> remove exactly that session's tree now
# Env: SCRATCH_REAP_ROOT, SCRATCH_REAP_INACTIVE_AFTER, SCRATCH_REAP_ENDED_AFTER,
#      SCRATCH_REAP_BUDGET (seconds, except the root); SCRATCH_REAP_GC, the gc
#      binary that lists the open sessions.
# Exit: 0 reaped or nothing to do · 2 usage or an unsafe root.
# Callers: the scratch-reap exec order (full pass); the cycle-recycle hook
# (--session, the retiring session's own tree). See docs/scratch-reclaim.md.
set -euo pipefail

PROG="${0##*/}"
DRY_RUN=0
SESSION=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --session) [ "$#" -ge 2 ] || { echo "$PROG: --session needs an id" >&2; exit 2; }
                   SESSION="$2"; shift 2 ;;
        --session=*) SESSION="${1#--session=}"; shift ;;
        *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# A session id names a directory this script deletes recursively, so it has to
# be a bare id and never a path: the [A-Za-z0-9-] charset the harness uses for
# CLAUDE_CODE_SESSION_ID cannot carry a '/' or a '..'.
if [ -n "$SESSION" ]; then
    case "$SESSION" in
        *[!A-Za-z0-9-]*) echo "$PROG: --session id must match [A-Za-z0-9-]" >&2; exit 2 ;;
    esac
fi

UID_NUM="$(id -u)"
ROOT="${SCRATCH_REAP_ROOT:-${TMPDIR:-/tmp}/claude-$UID_NUM}"
INACTIVE_AFTER="${SCRATCH_REAP_INACTIVE_AFTER:-86400}" # 24h
ENDED_AFTER="${SCRATCH_REAP_ENDED_AFTER:-600}"         # 10m
BUDGET="${SCRATCH_REAP_BUDGET:-240}"
GC="${SCRATCH_REAP_GC:-gc}"

for v in INACTIVE_AFTER ENDED_AFTER BUDGET; do
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

# du walks a tree other processes are writing; a vanished entry is an expected
# non-zero exit, not a reason to abandon the measurement.
tree_kb() { du -sk "$1" 2>/dev/null | awk 'NR == 1 { print $1 }' || true; }
gib() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1073741824 }'; }

# --- targeted mode: reap one named session's tree now ----------------------
# Found by a directory named exactly the session id at the session depth
# (<root>/<slug>/<id>), under the same -P and -xdev as the full pass, so a
# session id can only ever name a tree inside the validated root. No horizon
# and no live-process hold: the caller has named a session it knows is done.
if [ -n "$SESSION" ]; then
    session_dirs() { find -P "$ROOT" -mindepth 2 -maxdepth 2 -xdev -type d -name "$SESSION" "$@" 2>/dev/null; }
    if [ -z "$(session_dirs -print -quit)" ]; then
        echo "$PROG: no scratch tree for session $SESSION under $ROOT — nothing to reap"
        exit 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "$PROG: DRY RUN — would remove session $SESSION's tree under $ROOT:"
        session_dirs -print | sed 's/^/  /' || true
        exit 0
    fi
    BEFORE_KB="$(tree_kb "$ROOT")"; BEFORE_KB="${BEFORE_KB:-0}"
    # chmod before delete, as the full pass does: a read-only subtree (a Go
    # module cache copied into scratch) refuses rm, and a swallowed refusal
    # frees nothing. -exec is NUL-clean and a no-op when nothing matches.
    session_dirs -exec chmod -R u+w {} + || true
    session_dirs -exec rm -rf {} + || true
    # A slug directory emptied of its last session goes too, depth-pinned like
    # the full pass so a kept session one level down is never touched.
    find -P "$ROOT" -mindepth 1 -maxdepth 1 -xdev -type d -empty -delete 2>/dev/null || true
    AFTER_KB="$(tree_kb "$ROOT")"; AFTER_KB="${AFTER_KB:-0}"
    FREED_KB=$((BEFORE_KB - AFTER_KB)); [ "$FREED_KB" -ge 0 ] || FREED_KB=0
    printf '%s: reaped session %s — freed %s GiB\n' "$PROG" "$SESSION" "$(gib $((FREED_KB * 1024)))"
    exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gctk-scratch-reap.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
LIVE="$WORK/live"; NAMED="$WORK/named"; OCCUPIED="$WORK/occupied"
REMOVE_LIST="$WORK/remove"; ENDED_LIST="$WORK/ended"; KEYS="$WORK/gc-keys"
STRAY_LIST="$WORK/stray"; STRAY_LINK_LIST="$WORK/stray-links"
BIG_TREE_LIST="$WORK/big-tree"; BIG_STRAY_LIST="$WORK/big-stray"; BIG_ENDED_LIST="$WORK/big-ended"
SKIP_REASON="$WORK/skip"
: > "$LIVE"; : > "$NAMED"; : > "$OCCUPIED"; : > "$REMOVE_LIST"; : > "$ENDED_LIST"
: > "$KEYS"; : > "$STRAY_LIST"; : > "$STRAY_LINK_LIST"
: > "$BIG_TREE_LIST"; : > "$BIG_STRAY_LIST"; : > "$BIG_ENDED_LIST"

# START comes before every reading of /proc. The ended rule takes only a tree
# quiet for ENDED_AFTER before START, so a session that starts while the pass
# runs, which no reading below can see, owns only trees the rule holds.
START=$(date +%s)

# Sessions with a running child. Best-effort and quiet: most of /proc belongs
# to other uids and is unreadable, which is the expected case, not an error.
# environ is NUL-separated, so -a reads it as text and -o cuts the one setting
# out of it.
grep -aho 'CLAUDE_CODE_SESSION_ID=[A-Za-z0-9-]*' /proc/[0-9]*/environ 2>/dev/null \
    | sed 's/^CLAUDE_CODE_SESSION_ID=//' > "$LIVE" || true
sort -u -o "$LIVE" "$LIVE"
LIVE_N=$(wc -l < "$LIVE")

# Session ids on a command line. gc starts an agent as `claude --session-id
# <id>` and wakes one as `claude --resume <id>`, so a session between turns is
# still named by its own process. Every UUID on every command line counts,
# which only ever holds more.
find /proc -mindepth 2 -maxdepth 2 -name cmdline -type f -exec grep -ahoE \
    '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' {} + \
    > "$NAMED" 2>/dev/null || true

# The directories this uid's processes stand in, each keyed by the project name
# Claude Code derives from a path (every character outside [A-Za-z0-9] becomes
# '-') and carrying the earliest start of a process standing in it or below it.
# Runs of '-' are collapsed in the key and in the names it is matched against:
# Claude Code replaces a non-ASCII character per UTF-16 unit and this pass per
# byte, and a coarser key only ever holds more. A process absent from the ps
# listing started after it, so it is dated START; a listing with no process in
# it at all, when this script is one, means the start times are unknown, and
# the ended rule judges nothing. /proc is walked with find, not a glob, for the
# reason worktree-reap.sh records.
ENDED_SKIP=""
ps -u "$UID_NUM" -o pid=,etimes= > "$WORK/ages" 2>/dev/null || true
[ -s "$WORK/ages" ] || ENDED_SKIP="process start times could not be read"
find /proc -mindepth 2 -maxdepth 2 -name cwd -type l -user "$UID_NUM" -printf '%h\t%l\n' \
    > "$WORK/cwds" 2>/dev/null || true
LC_ALL=C awk -F'\t' -v now="$START" -v agesfile="$WORK/ages" '
function claim(dir, since,    key) {
    key = dir; gsub(/[^A-Za-z0-9]/, "-", key); gsub(/-+/, "-", key)
    if (!(key in first) || since < first[key]) first[key] = since
}
BEGIN {
    while ((getline line < agesfile) > 0) {
        split(line, f, " ")
        if (f[1] ~ /^[0-9]+$/ && f[2] ~ /^[0-9]+$/) started[f[1]] = now - f[2]
    }
    close(agesfile)
}
{
    pid = $1; sub(/^\/proc\//, "", pid)
    dir = $2; for (i = 3; i <= NF; i++) dir = dir "\t" $i
    sub(/ \(deleted\)$/, "", dir)
    if (substr(dir, 1, 1) != "/") next
    since = (pid in started) ? started[pid] : now
    claim("/", since)
    n = split(dir, part, "/"); up = ""
    for (i = 2; i <= n; i++) if (part[i] != "") { up = up "/" part[i]; claim(up, since) }
}
END { for (k in first) printf "%s\t%d\n", k, first[k] }
' "$WORK/cwds" > "$OCCUPIED" 2>/dev/null || true

BEFORE_KB="$(tree_kb "$ROOT")"; BEFORE_KB="${BEFORE_KB:-0}"

# One walk answers every question. Malformed rows — a newline in a filename
# splits one entry across two lines — fail the type test and are skipped, which
# loses a reap rather than misdirecting one.
remove_n=0; remove_b=0; stray_n=0; stray_b=0; ended_n=0; ended_b=0
keep_n=0; keep_b=0; live_n=0; live_b=0; candidate_n=0; candidate_b=0
{ find -P "$ROOT" -mindepth 1 -xdev -printf '%y\t%T@\t%s\t%p\n' 2>/dev/null || true; } \
  | awk -v root="$ROOT" -v now="$START" -v inactive_after="$INACTIVE_AFTER" \
        -v ended_after="$ENDED_AFTER" -v livefile="$LIVE" -v namedfile="$NAMED" \
        -v occupiedfile="$OCCUPIED" -v removefile="$REMOVE_LIST" -v endedfile="$ENDED_LIST" \
        -v strayfile="$STRAY_LIST" -v straylinkfile="$STRAY_LINK_LIST" \
        -v bigtreefile="$BIG_TREE_LIST" -v bigstrayfile="$BIG_STRAY_LIST" \
        -v bigendedfile="$BIG_ENDED_LIST" '
# A session nothing can still own, judged only for a tree Claude Code wrote: a
# UUID-named tree under a project name drawn from an absolute path, short enough
# to carry no hash.
function ended(k, slug, id,    p, key, anchor) {
    if (slug !~ /^-[A-Za-z0-9-]*$/ || length(slug) > 200) return 0
    if (split(id, p, "-") != 5 || id !~ /^[0-9A-Fa-f-]+$/) return 0
    if (length(p[1]) != 8 || length(p[2]) != 4 || length(p[3]) != 4 || length(p[4]) != 4 || length(p[5]) != 12) return 0
    if (tolower(id) in named) return 0
    key = slug; gsub(/-+/, "-", key)
    anchor = now
    if ((key in first) && first[key] < anchor) anchor = first[key]
    return newest[k] + ended_after <= anchor
}
BEGIN {
    FS = "\t"
    while ((getline id < livefile) > 0) if (id != "") live[id] = 1
    close(livefile)
    while ((getline id < namedfile) > 0) if (id != "") named[tolower(id)] = 1
    close(namedfile)
    while ((getline line < occupiedfile) > 0) if (split(line, f, "\t") == 2) first[f[1]] = f[2] + 0
    close(occupiedfile)
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
        else if (ended(k, c[1], c[2]))       { printf "%s\t%s\t%d\n", tolower(c[2]), k, bytes[k] > endedfile; cand_n++; cand_b += bytes[k]; ending[k] = 1 }
        else                                 { keep_n++; keep_b += bytes[k] }
    }
    for (p in big_sz) {
        if (big_key[p] in doomed)      printf "%d\t%s\n", big_sz[p], p > bigtreefile
        else if (big_key[p] in ending) printf "%s\t%d\t%s\n", big_key[p], big_sz[p], p > bigendedfile
    }
    printf "remove_n=%d\nremove_b=%d\nstray_n=%d\nstray_b=%d\nkeep_n=%d\nkeep_b=%d\nlive_n=%d\nlive_b=%d\ncandidate_n=%d\ncandidate_b=%d\n", \
        rm_n, rm_b, stray_n, stray_b, keep_n, keep_b, live_skipped, live_bytes, cand_n, cand_b
}' > "$WORK/plan" || true

# shellcheck disable=SC1090  # a generated key=value file, not a script
. "$WORK/plan"

# The ids gc can still wake a session into: the key of every open session in
# every city registered for this user, one per line. A registered city whose
# directory is gone holds no sessions. Any other failure writes its reason and
# returns non-zero, because a list read in part would let the ended rule take
# the tree of a sleeping session it never saw.
gc_session_keys() {
    local cities city list
    command -v "$GC" >/dev/null 2>&1 || { echo "$GC not found" > "$SKIP_REASON"; return 1; }
    command -v jq >/dev/null 2>&1 || { echo "jq not found" > "$SKIP_REASON"; return 1; }
    cities="$(timeout 30 "$GC" cities --json 2>/dev/null | jq -r '.cities[]?.path // empty' 2>/dev/null)" \
        || { echo "the city registry could not be read" > "$SKIP_REASON"; return 1; }
    [ -n "$cities" ] || { echo "no city is registered" > "$SKIP_REASON"; return 1; }
    while IFS= read -r city; do
        [ -d "$city" ] || continue
        list="$(timeout 30 "$GC" session list --state all --json --city "$city" 2>/dev/null)" \
            || { echo "the session list of $city could not be read" > "$SKIP_REASON"; return 1; }
        printf '%s' "$list" | jq -r '
            if (.sessions | type) == "array" then .sessions[] else error("no session list") end
            | select((.closed // false) != true and (.state // "") != "closed")
            | .session_key // empty' 2>/dev/null \
            || { echo "the session list of $city is not a session list" > "$SKIP_REASON"; return 1; }
    done <<< "$cities"
}

# Trees the walk judged ended go unless gc holds their id. The list is read
# only when there is a tree to judge, and an unreadable list keeps every one.
if [ "$candidate_n" -gt 0 ]; then
    if [ -z "$ENDED_SKIP" ] && gc_session_keys > "$KEYS"; then
        awk -F'\t' -v root="$ROOT" -v keysfile="$KEYS" -v removefile="$REMOVE_LIST" \
            -v bigendedfile="$BIG_ENDED_LIST" -v bigtreefile="$BIG_TREE_LIST" '
        BEGIN {
            while ((getline k < keysfile) > 0) if (k != "") open[tolower(k)] = 1
            close(keysfile)
        }
        $1 in open { held_n++; held_b += $3; next }
        { printf "%s/%s\0", root, $2 >> removefile; taken[$2] = 1; n++; b += $3 }
        END {
            while ((getline line < bigendedfile) > 0) {
                split(line, f, "\t")
                if (f[1] in taken) printf "%s\n", substr(line, length(f[1]) + 2) >> bigtreefile
            }
            printf "ended_n=%d\nended_b=%d\nheld_n=%d\nheld_b=%d\n", n, b, held_n, held_b
        }' "$ENDED_LIST" > "$WORK/ended-plan" || true
        held_n=0; held_b=0
        # shellcheck disable=SC1090  # a generated key=value file, not a script
        . "$WORK/ended-plan"
        keep_n=$((keep_n + held_n)); keep_b=$((keep_b + held_b))
    else
        [ -n "$ENDED_SKIP" ] || ENDED_SKIP="$(cat "$SKIP_REASON" 2>/dev/null || true)"
        ENDED_SKIP="${ENDED_SKIP:-the open sessions could not be read}"
        keep_n=$((keep_n + candidate_n)); keep_b=$((keep_b + candidate_b))
    fi
fi

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
    echo "  would remove $remove_n session trees past the horizon ($(gib "$remove_b") GiB) and delete $stray_n stray files ($(gib "$stray_b") GiB)"
    echo "  would remove $ended_n trees of ended sessions ($(gib "$ended_b") GiB)"
    if [ -n "$ENDED_SKIP" ]; then
        echo "  ended sessions not judged: $ENDED_SKIP — their $candidate_n trees wait for the horizon"
    fi
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

printf '%s: freed %s GiB (%s -> %s GiB) in %ss — removed %d session trees past the horizon and %d of ended sessions, deleted %d stray files; kept %d trees, held %d live\n' \
    "$PROG" "$(gib $((FREED_KB * 1024)))" "$(gib $((BEFORE_KB * 1024)))" "$(gib $((AFTER_KB * 1024)))" \
    "$(($(date +%s) - START))" "$remove_n" "$ended_n" "$stray_n" "$keep_n" "$live_n"
if [ -n "$ENDED_SKIP" ]; then
    echo "$PROG: ended sessions not judged — $ENDED_SKIP; their $candidate_n trees wait for the horizon"
fi
if [ -n "$STOPPED" ]; then
    echo "$PROG: yielded at the $STOPPED batch — ${BUDGET}s budget spent; the next pass takes it"
fi
big_report "$PROG: reaped %.0f MiB  %s"
exit 0
