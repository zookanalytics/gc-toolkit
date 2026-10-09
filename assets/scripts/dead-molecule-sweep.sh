#!/usr/bin/env bash
# dead-molecule-sweep.sh — dispose the backlog of dead graph.v2 molecule husks
# in one store, by handing each non-closed workflow root to
# dead-molecule-dispose.sh.
#
# Why a sweep exists. A molecule parked by a prior molecule-hold whose teardown
# never ran, or drained mid-flight, leaves a non-closed root whose steps re-offer
# a finished molecule or sit `blocked` outside every readiness query. Nothing
# reaches them on its own: the witness patrol skips workflow roots, orphan
# recovery keys on an assignee these owner-less roots lack, and orphan-dispose
# routes only a CLOSED root to the disposer. So the husks accumulate until
# something enumerates the roots and disposes them. This is that something.
#
# All safety is the per-root disposer's. This script only enumerates and
# iterates: it holds no guard of its own, so it can neither dispose something the
# disposer would refuse nor refuse something it would dispose. The disposer
# de-routes before it closes, reads back each close, refuses a live molecule, an
# open escalation, a source mid-PR or a chain holding a work bead, and writes
# nothing on refuse. Running the sweep without --apply previews every root the
# same way.
#
# Enumeration is the non-closed workflow roots (gc.kind=workflow, status
# open/in_progress/blocked). A root the listing cannot produce is a root this
# sweep does not touch; an unreadable listing is NOT an empty one.
#
# Usage:
#   dead-molecule-sweep.sh [--apply] [--json] [--db <path>] [--dispose-tool <path>]
# Without --apply this previews every root and writes nothing. --db pins the
# store (default $GC_RIG_ROOT/.beads), passed through to the disposer so the two
# read one store. Across rigs, run it once per store.
# Exit: 0 every root ran (disposed, previewed, or refused with its chain intact)
#       · 1 the root listing was unreadable, or a disposer hit a hard error
#       · 2 usage · 3 a disposer left a chain half torn down (PARTIAL) — a human
#       is needed for the named roots.
# NOT set -e: each root's disposer runs to its own verdict and the sweep tallies.
set -uo pipefail

PROG="dead-molecule-sweep"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOUND="${GC_DEAD_MOLECULE_TIMEOUT:-60}"

APPLY=0
WANT_JSON=0
BD_DB="${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}"
DISPOSE="${GC_DEAD_MOLECULE_TOOL:-$HERE/dead-molecule-dispose.sh}"

usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --json)  WANT_JSON=1 ;;
        --db)
            if [ $# -lt 2 ]; then echo "$PROG: --db needs a value" >&2; exit 2; fi
            shift; BD_DB="$1" ;;
        --dispose-tool)
            if [ $# -lt 2 ]; then echo "$PROG: --dispose-tool needs a value" >&2; exit 2; fi
            shift; DISPOSE="$1" ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "$PROG: unknown flag: $1" >&2; usage >&2; exit 2 ;;
        *) echo "$PROG: unexpected argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }
[ -x "$DISPOSE" ] || { echo "$PROG: dispose tool not executable: $DISPOSE" >&2; exit 1; }

run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

bd_() { if [ -n "$BD_DB" ]; then run_bounded gc bd "$@" --db "$BD_DB"; else run_bounded gc bd "$@"; fi; }

# --- enumerate the non-closed workflow roots ---------------------------------
ROOTS_RAW="$(bd_ list --status open,in_progress,blocked --metadata-field gc.kind=workflow --json --limit 0 2>/dev/null | scrub)" || ROOTS_RAW=""
if [ -z "$ROOTS_RAW" ] || ! printf '%s' "$ROOTS_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$PROG: could not list workflow roots — NOT treating that as an empty backlog; nothing disposed" >&2
    [ "$WANT_JSON" = "1" ] && jq -cn '{result:"unreadable", roots:0}'
    exit 1
fi
ROOT_IDS="$(printf '%s' "$ROOTS_RAW" | jq -r '.[]? | .id // empty')"

# --- dispose each, tallying the per-root verdicts ----------------------------
TOTAL=0; DISPOSED=0; REFUSED=0; LIVE=0; PREVIEWED=0; CLEAN=0; PARTIAL=0; UNREADABLE=0; OTHER=0
PARTIAL_ROOTS=""; HARDERR=0
DISPOSE_ARGS=(); [ "$APPLY" = "1" ] && DISPOSE_ARGS+=(--apply)
[ -n "$BD_DB" ] && DISPOSE_ARGS+=(--db "$BD_DB")

while IFS= read -r R; do
    [ -n "$R" ] || continue
    TOTAL=$((TOTAL + 1))
    OUT="$("$DISPOSE" "$R" ${DISPOSE_ARGS[@]+"${DISPOSE_ARGS[@]}"} --json 2>/dev/null)"; DRC=$?
    RESULT="$(printf '%s' "$OUT" | scrub | jq -r '.result // "error"' 2>/dev/null)"
    [ -n "$RESULT" ] || RESULT="error"
    case "$RESULT" in
        disposed)   DISPOSED=$((DISPOSED + 1)) ;;
        refused)    REFUSED=$((REFUSED + 1)) ;;
        live_root)  LIVE=$((LIVE + 1)) ;;
        preview)    PREVIEWED=$((PREVIEWED + 1)) ;;
        clean)      CLEAN=$((CLEAN + 1)) ;;
        partial)    PARTIAL=$((PARTIAL + 1)); PARTIAL_ROOTS="${PARTIAL_ROOTS:+$PARTIAL_ROOTS,}$R" ;;
        unreadable) UNREADABLE=$((UNREADABLE + 1)); HARDERR=1 ;;
        *)          OTHER=$((OTHER + 1)); [ "$DRC" -ne 0 ] && HARDERR=1 ;;
    esac
    [ "$WANT_JSON" = "1" ] || printf '%s\t%s\n' "$R" "$(printf '%s' "$OUT" | scrub | jq -r '[.result, .detail] | map(select(. != null)) | join(" ")' 2>/dev/null)"
done <<EOF
$ROOT_IDS
EOF

if [ "$WANT_JSON" = "1" ]; then
    jq -cn --argjson total "$TOTAL" --argjson disposed "$DISPOSED" --argjson refused "$REFUSED" \
        --argjson live "$LIVE" --argjson previewed "$PREVIEWED" --argjson clean "$CLEAN" \
        --argjson partial "$PARTIAL" --argjson unreadable "$UNREADABLE" --argjson other "$OTHER" \
        --arg partial_roots "$PARTIAL_ROOTS" --argjson applied "$APPLY" '
        {applied: ($applied == 1), roots: $total,
         disposed: $disposed, previewed: $previewed, refused: $refused, live: $live,
         clean: $clean, partial: $partial, unreadable: $unreadable, other: $other,
         partial_roots: ($partial_roots | select(. != "") // null)}'
else
    printf '%s: %d root(s) — disposed=%d previewed=%d refused=%d live=%d clean=%d partial=%d unreadable=%d other=%d\n' \
        "$PROG" "$TOTAL" "$DISPOSED" "$PREVIEWED" "$REFUSED" "$LIVE" "$CLEAN" "$PARTIAL" "$UNREADABLE" "$OTHER"
    [ -n "$PARTIAL_ROOTS" ] && echo "$PROG: PARTIAL teardown on: $PARTIAL_ROOTS — a human is needed" >&2
fi

[ "$PARTIAL" -gt 0 ] && exit 3
[ "$HARDERR" -eq 1 ] && exit 1
exit 0
