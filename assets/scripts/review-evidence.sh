#!/usr/bin/env bash
# review-evidence.sh — what `gctk rig` recorded at the commit a review reads.
#   review-evidence.sh --anchor <bead> --commit <sha> --worktree <path>
# Reads the review's worktree, which --worktree names and which must be checked
# out at <sha>, whatever directory the call is made in. Callers: a review run's
# lane (review-run.sh lane), and the review-gather block of
# formulas/mol-review.toml and of formulas/mol-review-quorum-signoff.toml.
#
# A call that names no worktree reads the checkout it is made in. A run keeps
# the step text it was poured with, and a review poured before its gather named
# the worktree makes that call after a cd into it. That form goes once no open
# step calls this script without --worktree.
#
# Every run of a rig's checks through `gctk rig`, by a self-review, the
# refinery or an earlier review, is recorded against the commit it ran at, and
# every worktree of the rig's clone reads the records. This reads each check's
# record at <sha> with `gctk rig <check> --check`, which runs nothing and calls
# nothing but git, and prints one line per check: its result, scope, exit code
# and command, that nothing is recorded, or that gctk could not read one. The
# first line names the gctk binary it read them with, the one a review runs a
# suite through, or says there is none and so no record to read. What a line
# means for a review is the check's method to say, so nothing here judges the
# commit.
#
# A record says what a command did at a commit and never whose failure it is.
# A fail's line adds what `gctk rig pre-existing` answers of the anchor's mark:
# "pre-existing, tracked by <trackers>" while the mark holds that very record
# and a tracker it names is open; why it does not hold when the mark judged
# another run, names no open tracker or could not be read; and nothing when the
# anchor carries no mark at <sha>. Only the first calls the fail pre-existing.
# The anchor is read only when some record fails.
#
# Exit: 0 printed · 1 nothing printed: the worktree cannot be entered or is not
# at <sha>, or a temp file is missing · 2 usage, a --worktree with no path
# included
set -uo pipefail

PROG="review-evidence"

usage() {
  [ -z "${1:-}" ] || echo "$PROG: $1" >&2
  echo "usage: $PROG --anchor <bead> --commit <sha> --worktree <path>" >&2
  exit 2
}

ANCHOR=""; COMMIT=""; WORKTREE=""; NAMED=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --anchor|--commit|--worktree)
      [ "$#" -ge 2 ] || usage "$1 needs a value"
      case "$1" in
        --anchor) ANCHOR="$2" ;;
        --commit) COMMIT="$2" ;;
        --worktree) WORKTREE="$2"; NAMED=1 ;;
      esac
      shift 2 ;;
    -h|--help) usage ;;
    *) usage "unknown argument: $1" ;;
  esac
done
[ -n "$ANCHOR" ] || usage "--anchor is required"
[ -n "$COMMIT" ] || usage "--commit is required"
# An empty path is a caller that lost its worktree, never the checkout it is in.
[ -z "$NAMED" ] || [ -n "$WORKTREE" ] || usage "--worktree needs a path"

# gctk rig reads the checkout of the directory it runs in, so every read below
# runs in the worktree.
if [ -n "$WORKTREE" ]; then
  CDPATH='' cd -- "$WORKTREE" 2>/dev/null || { echo "$PROG: cannot enter the worktree $WORKTREE, so no record of it can be read" >&2; exit 1; }
fi

# A record and a pre-existing mark both name a full sha, so the commit is the
# one the checkout's HEAD resolves to, and a checkout at any other commit has
# records that say nothing about this one.
HEAD_SHA=$(git rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)
WANT=$(git rev-parse --verify -q "$COMMIT^{commit}" 2>/dev/null)
if [ -z "$HEAD_SHA" ] || [ "$HEAD_SHA" != "$WANT" ]; then
  echo "$PROG: the checkout at $(pwd -P) is at ${HEAD_SHA:-no commit}, not at $COMMIT, so its records are not that commit's" >&2
  exit 1
fi

# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
if [ ! -x "$GCTK" ]; then
  echo "gctk: no binary at '$GCTK' (GCTK_BIN, else the city's build, which its gctk-build order publishes), so no record can be read"
  exit 0
fi
echo "gctk: $GCTK"

ERR=$(mktemp "${TMPDIR:-/tmp}/$PROG.XXXXXX") || { echo "$PROG: could not make a file to read gctk rig's lines into" >&2; exit 1; }
trap 'rm -f "$ERR"' EXIT

for CHECK in test lint typecheck; do
  REC=$("$GCTK" rig "$CHECK" --check 2>"$ERR"); RC=$?
  case "$RC" in
    0|1)
      LINE=$(printf '%s' "$REC" | jq -r --arg check "$CHECK" --arg result "$([ "$RC" = 0 ] && echo pass || echo fail)" '
        select(type == "object")
        | "\($check): \($result)" + (if (.scope // "") != "" then ", scope \(.scope)" else "" end)
          + ", exit \(.exit_code // "unknown"), command: \(.command // "")"' 2>/dev/null)
      if [ -z "$LINE" ]; then
        echo "$CHECK: unread, gctk rig $CHECK --check exited $RC with no record it could parse"
        continue
      fi
      if [ "$RC" = 1 ]; then
        PRE=$("$GCTK" rig pre-existing "$CHECK" --bead "$ANCHOR" 2>"$ERR"); PRC=$?
        if [ -n "$PRE" ]; then
          LINE="$LINE; $PRE"
        elif [ "$PRC" != 0 ] && [ "$PRC" != 1 ]; then
          LINE="$LINE; no pre-existing mark on $ANCHOR was judged, as gctk rig pre-existing exited $PRC: $(head -n 1 "$ERR")"
        fi
      fi
      printf '%s\n' "$LINE" ;;
    3) echo "$CHECK: nothing recorded" ;;
    *) echo "$CHECK: unread, gctk rig $CHECK --check exited $RC: $(head -n 1 "$ERR")" ;;
  esac
done
exit 0
