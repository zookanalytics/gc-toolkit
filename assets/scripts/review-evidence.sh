#!/usr/bin/env bash
# review-evidence.sh — what `gctk rig` recorded at the commit a review reads.
#   review-evidence.sh --anchor <bead> --commit <sha>
# Runs in the review's worktree, which must be checked out at <sha>. Callers:
# the review-gather block of formulas/mol-review.toml and of
# formulas/mol-review-quorum-signoff.toml, which every check's review runs.
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
# A fail's line says whether the anchor's rig_check_pre_existing.<check> holds
# that very record at <sha>, and which trackers carry it, by rig-check-lib.sh's
# definition of that judgment. The anchor is read only when some record fails.
#
# Exit: 0 printed · 1 nothing printed: the checkout is not at <sha>, or a lib
# beside this script or a temp file is missing · 2 usage
set -uo pipefail

PROG="review-evidence"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=rig-check-lib.sh
. "$HERE/rig-check-lib.sh" || { echo "$PROG: cannot source rig-check-lib.sh beside this script" >&2; exit 1; }

usage() {
  [ -z "${1:-}" ] || echo "$PROG: $1" >&2
  echo "usage: $PROG --anchor <bead> --commit <sha>" >&2
  exit 2
}

ANCHOR=""; COMMIT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --anchor|--commit)
      [ "$#" -ge 2 ] || usage "$1 needs a value"
      case "$1" in
        --anchor) ANCHOR="$2" ;;
        --commit) COMMIT="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage ;;
    *) usage "unknown argument: $1" ;;
  esac
done
[ -n "$ANCHOR" ] || usage "--anchor is required"
[ -n "$COMMIT" ] || usage "--commit is required"

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

ANCHOR_JSON=""; ANCHOR_READ=0
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
        if [ "$ANCHOR_READ" = 0 ]; then
          ANCHOR_READ=1
          ANCHOR_JSON=$(bd_json show "$ANCHOR")
          printf '%s' "$ANCHOR_JSON" | jq -e --arg id "$ANCHOR" 'type == "array" and (.[0].id // "") == $id' >/dev/null 2>&1 || ANCHOR_JSON=""
        fi
        if [ -z "$ANCHOR_JSON" ]; then
          LINE="$LINE; the anchor $ANCHOR did not read, so no pre-existing mark is known"
        else
          PRE=$(printf '%s' "$ANCHOR_JSON" | jq -r --arg k "rig_check_pre_existing.$CHECK" --arg c "$HEAD_SHA" --arg rec "$REC" \
            "$PRE_EXISTING_JQ"' pre_existing($k; $c; $rec)' 2>/dev/null)
          case "$PRE" in
            "tracked by "*) LINE="$LINE; pre-existing, $PRE" ;;
            "another run") LINE="$LINE; the anchor's pre-existing mark at this commit judged another run's fail" ;;
          esac
        fi
      fi
      printf '%s\n' "$LINE" ;;
    3) echo "$CHECK: nothing recorded" ;;
    *) echo "$CHECK: unread, gctk rig $CHECK --check exited $RC: $(head -n 1 "$ERR")" ;;
  esac
done
exit 0
