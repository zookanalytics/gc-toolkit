#!/usr/bin/env bash
# build-scratch-reap.sh — reclaim build and test scratch left behind by killed
# or crashed runs.
#
# A run that exits normally removes its own temp on an EXIT trap. A run that is
# killed or crashes skips that trap, and its scratch is left on the host's
# shared tmpfs: Go toolchain trees (go-build*, go-link*), the gascity gc.test
# binary's per-run trees (gct<pid>-<n>, gct-<pid>-<n>), the build scripts' Go
# scratch (run.<pid> under /var/tmp/gotmp), and templated tool temp (gctk-*).
# Nothing reclaims these, so they accumulate against the per-uid tmpfs quota
# until it is exhausted, at which point every agent's shell output capture fails
# silently and the host loses its shells. This is the backstop that reclaims
# them.
#
# Safety model: a holder, never age or size. An entry is removed only when it
# has NO live holder — lsof reports no process with a file inside it open and no
# process whose cwd is inside it — AND, for the pid-encoded names
# (gct<pid>-<n>, gct-<pid>-<n>, run.<pid>), the process with that pid is gone.
# Both gates are re-checked immediately before the remove, because the
# scan-to-delete gap is a TOCTOU window. Age and size are never a signal: a 6G
# gc.test tree nine minutes into a live run holds a lock file and is kept; a 1K
# tree whose owner died is reaped. A name that looks pid-encoded but whose pid
# is empty or non-numeric is unparseable and is left alone, and so is a pid
# whose process cannot be shown gone.
#
# Scope: the host's shared build/test scratch, under every root this host's
# runs point their temp at (tmpfs today, /var/tmp if a run redirects there).
# One pass serves every rig that shares the host, held under a per-uid lock so
# the sweep is not repeated once per rig. Rebuild-cost caches (.pnpm-store,
# node-compile-cache) match none of the patterns and are left alone. The
# harness session scratch under claude-<uid> belongs to scratch-reap.sh, not to
# this script.
#
# Usage:
#   build-scratch-reap.sh              reap, print one summary line
#   build-scratch-reap.sh --dry-run    report the plan, remove nothing
#   build-scratch-reap.sh --root DIR   scan DIR (repeatable; replaces defaults)
#   build-scratch-reap.sh --verbose    name each entry and why it was kept/reaped
#   build-scratch-reap.sh --no-lock    skip the single-flight lock
# Env: BUILD_SCRATCH_REAP_LOCK_DIR (lock location; default XDG_RUNTIME_DIR or
#      /tmp/gc-build-scratch-reap.<uid>), GC_GCTK_GOTMP / GC_HELM_GOTMP (the Go
#      scratch roots the build scripts use), TMPDIR.
# Exit: 0 reaped or nothing to do · 1 cannot verify holders (refused) · 2 usage.
# Caller: the build-scratch-reap cooldown order (orders/build-scratch-reap.toml).
# See specs/tk-jp1fg5/build-scratch-reap.md.
set -euo pipefail

PROG="${0##*/}"
DRY_RUN=0
VERBOSE=0
NO_LOCK=0
LSOF_TIMEOUT=30
ROOTS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        --no-lock) NO_LOCK=1; shift ;;
        --root) [ "$#" -ge 2 ] || { echo "$PROG: --root needs a directory" >&2; exit 2; }
                ROOTS+=("$2"); shift 2 ;;
        --root=*) ROOTS+=("${1#--root=}"); shift ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^set -euo.*//'; exit 0 ;;
        *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
    esac
done

log() { [ "$VERBOSE" -eq 1 ] && echo "$PROG: $1" || true; }

# Holders are read through lsof; refuse to reap if it cannot be trusted. A
# missing lsof, or one that reports nothing for this very process (every process
# has open files), would make every entry look unheld and reap live scratch.
LSOF="$(command -v lsof || true)"
[ -n "$LSOF" ] || { echo "$PROG: lsof not found; cannot verify holders, refusing to reap" >&2; exit 1; }
if [ -z "$("$LSOF" -w -p "$$" 2>/dev/null)" ]; then
    echo "$PROG: lsof present but returned nothing for this process; refusing to reap blind" >&2
    exit 1
fi
TIMEOUT_BIN="$(command -v timeout || true)"
UID_NUM="$(id -u 2>/dev/null || echo 0)"
# GNU stat takes its format after -c and BSD stat after -f; both read %u as the
# owner's uid, of a symlink itself rather than what it names.
if stat -c %u -- / >/dev/null 2>&1; then STAT=(stat -c); else STAT=(stat -f); fi

# Single-flight across the host. The lock lives at a per-uid path every session
# shares and that matches none of the reaped patterns, so a pass never reaps its
# own lock. flock is contended -> another pass is running, nothing to do. flock
# missing -> run unlocked and say so; two passes racing is safe (each re-checks
# the holder before removing, and removing an already-gone tree is a no-op).
if [ "$NO_LOCK" -eq 0 ]; then
    LOCK_DIR="${BUILD_SCRATCH_REAP_LOCK_DIR:-}"
    if [ -z "$LOCK_DIR" ]; then
        if [ -n "${XDG_RUNTIME_DIR:-}" ]; then LOCK_DIR="$XDG_RUNTIME_DIR/gc-build-scratch-reap"
        else LOCK_DIR="/tmp/gc-build-scratch-reap.$UID_NUM"; fi
    fi
    if command -v flock >/dev/null 2>&1 && mkdir -p "$LOCK_DIR" 2>/dev/null && ( : >>"$LOCK_DIR/lock" ) 2>/dev/null; then
        exec 9>>"$LOCK_DIR/lock"
        if ! flock -n 9; then
            log "another pass holds $LOCK_DIR/lock; skipping"
            exit 0
        fi
    else
        echo "$PROG: lock unavailable ($LOCK_DIR); proceeding unlocked" >&2
    fi
fi

# Default roots: wherever this host's runs land their temp. De-duplicate by
# realpath and keep only directories that exist.
if [ "${#ROOTS[@]}" -eq 0 ]; then
    ROOTS=("${TMPDIR:-/tmp}" /tmp /var/tmp "${GC_GCTK_GOTMP:-/var/tmp/gotmp}" "${GC_HELM_GOTMP:-/var/tmp/gotmp}")
fi
SCAN_ROOTS=()
for r in "${ROOTS[@]}"; do
    [ -d "$r" ] || continue
    rp="$(realpath "$r" 2>/dev/null || echo "$r")"
    dup=0
    for s in ${SCAN_ROOTS[@]+"${SCAN_ROOTS[@]}"}; do [ "$s" = "$rp" ] && { dup=1; break; }; done
    [ "$dup" -eq 0 ] && SCAN_ROOTS+=("$rp")
done
[ "${#SCAN_ROOTS[@]}" -gt 0 ] || { log "no scan roots exist"; exit 0; }

# Holders are read from one global lsof snapshot, not a scan per entry. lsof
# walks every process's descriptors on each call, so a per-entry scan is
# O(entries x host descriptors) and times the pass out on a busy host. One
# snapshot of every open path — descriptors AND cwd — is O(host descriptors)
# once, and each entry is then matched against it in memory. -n and -P skip host
# and port name resolution so the scan never blocks on DNS; a timeout bounds a
# pathological host.
LSOF_FLAGS=(-w -n -P)
snapshot() {
    if [ -n "$TIMEOUT_BIN" ]; then
        "$TIMEOUT_BIN" "$LSOF_TIMEOUT" "$LSOF" "${LSOF_FLAGS[@]}" -F n 2>/dev/null | sed -n 's/^n//p'
    else
        "$LSOF" "${LSOF_FLAGS[@]}" -F n 2>/dev/null | sed -n 's/^n//p'
    fi
}

# Which candidates does the snapshot show a holder for? One awk pass marks a
# candidate held when an open path is the candidate itself (a cwd, a directory
# descriptor, or the file) or lies within it — i.e. some ancestor of the open
# path is a candidate. One pass is O(open paths) and independent of the
# candidate count, where a scan per candidate re-reads the whole snapshot once
# per entry and times the pass out when hundreds have accumulated. Matching is on
# whole path components, so a sibling that merely shares a candidate's name as a
# prefix never matches, and a glob character in a path is inert. Reads the
# candidate paths (CAND) as the first input and the snapshot as the second.
compute_held() {   # compute_held "$snapshot"  ->  held candidate paths, one per line
    awk '
        NR == FNR { cand[$0] = 1; have = 1; next }
        !have { exit }
        {
            if ($0 in cand) { held[$0] = 1; next }
            n = split($0, part, "/"); acc = ""
            for (i = 2; i <= n; i++) {
                acc = acc "/" part[i]
                if (acc in cand) { held[acc] = 1; break }
            }
        }
        END { for (c in held) print c }
    ' <(printf '%s\n' "${CAND[@]}") <(printf '%s\n' "$1")
}

# Is the process gone? kill -0 answers for a process of this uid, on Linux and
# macOS alike. A live process another uid owns refuses the signal, so ps, which
# lists every uid's processes, answers for the rest. Each one reporting it
# alive returns 1. Gone is only ever what ps shows, and only when its listing
# shows this very process: a ps that cannot list the host cannot show any
# process gone. That, and an empty or non-numeric pid, which is unparseable,
# report "cannot tell" (return 2), never "dead".
PS_OK=0
[ "$(ps -p "$$" -o pid= 2>/dev/null | tr -d ' ')" = "$$" ] && PS_OK=1
pid_is_dead() {
    local pid="$1"
    case "$pid" in ''|*[!0-9]*) return 2 ;; esac
    kill -0 "$pid" 2>/dev/null && return 1
    [ -n "$(ps -p "$pid" -o pid= 2>/dev/null)" ] && return 1
    [ "$PS_OK" -eq 1 ] || return 2
    return 0
}

# Phase 1 — the gates that need no holder scan: the name must be a known scratch
# form, the entry must be ours, and a pid-encoded name whose pid is still alive
# (or not shown gone) is kept untouched. What survives is dead scratch unless a
# holder says otherwise, which phase 2 decides.
CAND=()        # candidate paths, dead by name/pid, pending the holder gate
CAND_PID=()    # parallel: the pid for a pid-encoded name, "" otherwise
KEPT_N=0
for root in "${SCAN_ROOTS[@]}"; do
    while IFS= read -r -d '' entry; do
        [ -e "$entry" ] || continue
        base="${entry##*/}"
        pid=""; suf=""; form=""
        case "$base" in
            .pnpm-store|node-compile-cache) log "keep (rebuild-cost cache): $entry"; KEPT_N=$((KEPT_N + 1)); continue ;;
            # gc.test per-run trees. The owned shapes are gct<pid>-<n> and
            # gct-<pid>-<n>: a numeric pid AND a numeric run-counter <n>, the
            # -<n> suffix required. The scan covers broad roots (/tmp, /var/tmp),
            # so a name that is merely gct plus a pid, with no -<n>, is some other
            # user's path and reaping it on a dead pid would delete an unrelated
            # directory. Parse the whole name here; the shape is validated below.
            gct-[0-9]*-[0-9]*) rest="${base#gct-}"; pid="${rest%%-*}"; suf="${rest#*-}"; form=pid ;;
            gct[0-9]*-[0-9]*)  rest="${base#gct}";  pid="${rest%%-*}"; suf="${rest#*-}"; form=pid ;;
            # Go scratch: run.<pid>, the raw numeric pid with no suffix (GOTMP/run.$$).
            run.[0-9]*) pid="${base#run.}"; form=pid ;;
            go-build*|go-link*|gctk-*) form=holder ;;
            *) log "skip (unrecognized): $entry"; continue ;;   # e.g. gctfoo-1, gct<pid> with no -<n>, run.bogus
        esac
        # The gct run-counter <n> must be numeric; a non-numeric or multi-dash
        # suffix (set only for the gct forms, empty otherwise) only resembles
        # the shape and is not ours to reap. The pid is held to the same bar by
        # pid_is_dead below, which keeps an unparseable pid rather than reaping.
        case "$suf" in *[!0-9]*) log "skip (run-counter not numeric): $entry"; continue ;; esac
        # Must be our own scratch. A path we do not own is not ours to reclaim,
        # and bounding to our uid is also what keeps an empty lsof result
        # trustworthy: we can always read our own trees, so a path missing from
        # the snapshot is idle, not merely unreadable.
        if [ "$("${STAT[@]}" %u -- "$entry" 2>/dev/null || echo -1)" != "$UID_NUM" ]; then
            log "keep (not owned by uid $UID_NUM): $entry"; KEPT_N=$((KEPT_N + 1)); continue
        fi
        if [ "$form" = pid ]; then
            d=0; pid_is_dead "$pid" || d=$?
            if [ "$d" -eq 2 ]; then log "keep (pid '$pid' not shown gone): $entry"; KEPT_N=$((KEPT_N + 1)); continue; fi
            if [ "$d" -eq 1 ]; then log "keep (pid $pid alive): $entry"; KEPT_N=$((KEPT_N + 1)); continue; fi
        fi
        CAND+=("$entry"); CAND_PID+=("$pid")
    done < <(find "$root" -maxdepth 1 -mindepth 1 \
                \( -name 'go-build*' -o -name 'go-link*' -o -name 'gct*' -o -name 'run.*' \) \
                -print0 2>/dev/null)
done

REAPED_N=0
REAPED_B=0
reap() {
    local p="$1" kb bytes
    # -k is the du size flag GNU and BSD share, so the count is the KiB on disk.
    kb="$(du -sk "$p" 2>/dev/null | awk 'NR==1{print $1}')" || true
    case "$kb" in ''|*[!0-9]*) kb=0 ;; esac
    bytes=$((kb * 1024))
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "$PROG: would reap $p ($(numfmt --to=iec "$bytes" 2>/dev/null || echo "${bytes}B"))"
    else
        chmod -R u+w "$p" 2>/dev/null || true   # Go caches land read-only
        rm -rf -- "$p" 2>/dev/null || { log "rm failed: $p"; return; }
    fi
    REAPED_N=$((REAPED_N + 1))
    REAPED_B=$((REAPED_B + bytes))
}

# Phase 2 — the holder gate and its TOCTOU recheck. SNAP1 drops anything held at
# scan time; SNAP2 is a fresh snapshot taken immediately before removal and the
# pid is re-read per entry, closing the window between proving an entry dead and
# removing it. An lsof that yields nothing is a broken probe, not an idle host:
# refuse rather than reap blind.
if [ "${#CAND[@]}" -gt 0 ]; then
    rc1=0; SNAP1="$(snapshot)" || rc1=$?
    if [ "$rc1" -ne 0 ] || [ -z "$SNAP1" ]; then
        echo "$PROG: lsof snapshot failed or was empty; refusing to reap blind" >&2
        exit 1
    fi
    declare -A HELD1=()
    while IFS= read -r h; do [ -n "$h" ] && HELD1["$h"]=1; done < <(compute_held "$SNAP1")
    REAP=(); REAP_PID=()
    for i in "${!CAND[@]}"; do
        c="${CAND[$i]}"
        if [ -n "${HELD1[$c]:-}" ]; then
            log "keep (open holder): $c"; KEPT_N=$((KEPT_N + 1))
        else
            REAP+=("$c"); REAP_PID+=("${CAND_PID[$i]}")
        fi
    done
    if [ "${#REAP[@]}" -gt 0 ]; then
        rc2=0; SNAP2="$(snapshot)" || rc2=$?
        if [ "$rc2" -ne 0 ] || [ -z "$SNAP2" ]; then
            echo "$PROG: recheck snapshot failed or was empty; removing nothing this pass" >&2
        else
            declare -A HELD2=()
            while IFS= read -r h; do [ -n "$h" ] && HELD2["$h"]=1; done < <(compute_held "$SNAP2")
            for i in "${!REAP[@]}"; do
                p="${REAP[$i]}"; pid="${REAP_PID[$i]}"
                [ -e "$p" ] || continue   # a peer may have removed it since the scan
                if [ -n "$pid" ]; then
                    pid_is_dead "$pid" || { log "keep (pid $pid returned): $p"; KEPT_N=$((KEPT_N + 1)); continue; }
                fi
                if [ -n "${HELD2[$p]:-}" ]; then
                    log "keep (holder appeared): $p"; KEPT_N=$((KEPT_N + 1)); continue
                fi
                reap "$p"
            done
        fi
    fi
fi

if [ "$DRY_RUN" -eq 1 ]; then VERB="would reap (dry-run)"; else VERB="reaped"; fi
echo "$PROG: $VERB $REAPED_N entr(ies), $(numfmt --to=iec "$REAPED_B" 2>/dev/null || echo "${REAPED_B}B"); kept $KEPT_N live/held"
