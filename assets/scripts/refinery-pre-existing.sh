#!/usr/bin/env bash
# refinery-pre-existing.sh — the refinery's path for a failed check that is
# already red on the target: track it once, mark it on the bead, and let the
# landing go ahead.
#
#   refinery-pre-existing.sh --bead <id> --check <test|lint|typecheck|setup|build>
#     (--test <function> | --target <path> | --lint <linter> <path>) [--log-file <file>]
#
# One call per failure: each failing test function, each failing target that
# has none, and each file a linter flagged is its own key and its own tracker.
# The key comes from preexisting-failure.sh, never from prose, so the gate
# that filed a tracker and the next one that meets the same red reach one
# bead. The lookup reads every live status, and a lookup that does not answer
# is unknown, never "none": nothing is filed and nothing lands. With no
# tracker, one is filed with the failure's evidence, read from --log-file or
# stdin: the check, where it ran, and its raw output.
#
# The bead must be assigned to this refinery ($GC_AGENT), and the refinery's
# tree for it must hold its branch (refinery-lib.sh). The tracker is then
# marked on the bead whose PR a review reads at the prepared head
# (rig-check-pre-existing.sh): the bead's anchor_bead when it names one, else
# the bead. A mark that does not land changes nothing else, since a review at
# that head runs the suite itself.
#
# stdout: the tracker's id.
# Exit: 0 the failure is tracked, so the landing goes ahead · 1 no tracker was
#       found or filed, so nothing lands; the output says why · 2 usage
set -uo pipefail

PROG="refinery-pre-existing"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }

usage() { echo "usage: $PROG --bead <id> --check <check> (--test <function> | --target <path> | --lint <linter> <path>) [--log-file <file>]" >&2; exit 2; }
BEAD=""; CHECK=""; KEY_ARGS=(); LOG_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead|--check|--log-file)
      [ "$#" -ge 2 ] || usage
      case "$1" in --bead) BEAD="$2" ;; --check) CHECK="$2" ;; *) LOG_FILE="$2" ;; esac
      shift 2 ;;
    --test|--target) [ "$#" -ge 2 ] && [ "${#KEY_ARGS[@]}" -eq 0 ] || usage; KEY_ARGS=("$1" "$2"); shift 2 ;;
    --lint) [ "$#" -ge 3 ] && [ "${#KEY_ARGS[@]}" -eq 0 ] || usage; KEY_ARGS=("$1" "$2" "$3"); shift 3 ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$BEAD" ] && [ -n "$CHECK" ] && [ "${#KEY_ARGS[@]}" -gt 0 ] || usage
case "$CHECK" in test|lint|typecheck|setup|build) ;; *) echo "$PROG: --check takes test, lint, typecheck, setup or build, not '$CHECK'" >&2; usage ;; esac

stop() { echo "$PROG: $1; nothing is filed, and $BEAD does not land" >&2; exit 1; }

HOME_DIR=$(refinery_home) || stop "the refinery's own worktree is unknown"
refinery_bead "$BEAD" || stop "$BEAD did not read"
[ -n "${GC_AGENT:-}" ] && [ "$(bead_field assignee)" = "$GC_AGENT" ] \
  || stop "$BEAD is assigned to $(bead_field assignee), not this refinery (${GC_AGENT:-GC_AGENT unset})"
refinery_require "$HOME_DIR" "$BEAD" "$(bead_meta branch)" || stop "this iteration did not prepare $BEAD"
TARGET=$(bead_meta target)
[ -n "$TARGET" ] || TARGET=$(refinery_default_branch "$HOME_DIR") || TARGET="its target"

if [ -n "$LOG_FILE" ]; then
  LOG=$(cat -- "$LOG_FILE") || stop "the failure's log $LOG_FILE did not read"
else
  LOG=$(cat)
fi
[ -n "$(printf '%s' "$LOG" | tr -d '[:space:]')" ] || stop "no evidence of the failure was given, and a tracker with none cannot be judged"

PF="$HERE/preexisting-failure.sh"
KEY=$("$PF" key "${KEY_ARGS[@]}") || stop "no failure key was derived"
TRACKER=$("$PF" find "$KEY") || stop "the lookup of $KEY did not answer, which is not the same as no tracker"
if [ -n "$TRACKER" ]; then
  echo "$PROG: $KEY is already tracked as $TRACKER" >&2
else
  TRACKER=$("$PF" file "$KEY" --message "Observed on $TARGET while the refinery merged $BEAD, and classified as pre-existing on $TARGET rather than a regression from that branch.

## Failure

$LOG") || stop "no tracker was filed for $KEY"
  [ -n "$TRACKER" ] || stop "the filing of $KEY named no tracker"
  echo "$PROG: $KEY is tracked as $TRACKER, filed now" >&2
fi

MARKED_ON=$(bead_meta anchor_bead)
[ -n "$MARKED_ON" ] || MARKED_ON="$BEAD"
"$HERE/rig-check-pre-existing.sh" --bead "$MARKED_ON" --check "$CHECK" --commit "$PREP_HEAD" --worktree "$PREP_TREE" --trackers "$TRACKER" >&2 \
  || echo "$PROG: the mark on $MARKED_ON did not land; the landing goes on, and a review at $PREP_HEAD runs the suite itself" >&2
printf '%s\n' "$TRACKER"
