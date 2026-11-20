#!/usr/bin/env bash
# converse-rework.sh — an operator ruling's entry to rework. A converse sitting
# can reach a ruling that changes what an already-published PR's branch must
# contain, while the PR still reads review-ready against a head that predates the
# ruling. A PR on Gas Town's pending record (merge_result pull_request_pending or
# pull_request_head_changed) has one worker on its branch, its review run
# (specs/tk-1tfzr71.108/design.md, section 1), so the ruling goes to the run as
# an ask (`gctk review ask`): the ruling as its reason, the conversation as its
# source, and the checks the ruling names (--check), which the run picks at the
# first head it judges once it can take the ask. The run applies the ruling as
# ruled and triages the head its fix pushes. A re-run of the same ruling finds
# the ask the first filed, open or closed, by its source and reason, and files
# nothing. A ruling whose change the sitting makes itself, on the branch with
# the operator, goes through `gctk pr push` instead (docs/authority-map.md).
#
# Usage:
#   converse-rework.sh --anchor <anchor-bead> --ruling-bead <conversation> \
#     --ruling "<the ruling, one line>" [--check <check>]...
#   The anchor must be an open PR: live in the store, at merge_result
#   pull_request_pending or pull_request_head_changed on the pending record,
#   carrying no disposition (gc.pr_close_disposition_kind or a duplicates or
#   supersedes edge onto a successor), and naming its branch, its landing
#   target and its PR.
#   --ruling-bead is the conversation the ruling was reached in.
#   --check names a check the ruling sends back, once per check, from the
#   check index.
# Output: "<ask> ask <filed|found>".
# Exit: 0 once the ask stands, filed or found, and 2 when it was refused or did
#   not answer. A refusal here, before the ask is filed, exits 2 with nothing
#   written.
set -u

_lib_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 2; }
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)
# The ask a ruling files on the pending record is gctk's, from the binary the
# city builds.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin

DIE_STATUS=2
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

ANCHOR=""; RULING_BEAD=""; RULING=""; CHECKS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)      shift; [ $# -gt 0 ] || die "--anchor needs a value"; ANCHOR="$1" ;;
    --ruling-bead) shift; [ $# -gt 0 ] || die "--ruling-bead needs a value"; RULING_BEAD="$1" ;;
    --ruling)      shift; [ $# -gt 0 ] || die "--ruling needs a value"; RULING="$1" ;;
    --check)       shift; [ $# -gt 0 ] || die "--check needs a check's name"; CHECKS+=("$1") ;;
    -h|--help)     sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "unknown argument '$1'" ;;
  esac
  shift
done
[ -n "$ANCHOR" ]      || die "--anchor is required"
[ -n "$RULING_BEAD" ] || die "--ruling-bead is required (the conversation the ruling was reached in)"
[ -n "$RULING" ]      || die "--ruling is required (the one-line ruling the rework answers)"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v gc >/dev/null 2>&1 || die "gc is required"

ANCHOR_ROW=$(bd_json show "$ANCHOR")
printf '%s' "$ANCHOR_ROW" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
  || die "anchor $ANCHOR does not resolve; nothing filed"

# A ruling on an anchor in any other state reaches it by another route (a pre-PR
# hold, a dispose), so no child is filed against a non-PR anchor. merge_result
# alone does not prove the PR open: a hand-closed anchor keeps the field, and an
# anchor pr-dispose.sh has disposed keeps its record with its PR already closed
# until the landing order consummates the close. A child filed on either would
# block a bead on its way to closed and send a worker to a branch whose PR is
# gone. So the anchor must also be live and carry no disposition.
STATUS=$(printf '%s' "$ANCHOR_ROW" | jq -r '(.[0].status // "") | tostring | ascii_downcase' 2>/dev/null)
case ",$LIVE_STATUSES," in
  *",${STATUS:-none},"*) : ;;
  *) die "anchor $ANCHOR is status='${STATUS:-unset}', not live; the ruling-rework path applies only to an open PR" ;;
esac
MERGE_RESULT=$(row_meta "$ANCHOR_ROW" merge_result)
case "$MERGE_RESULT" in
  pull_request_pending|pull_request_head_changed) : ;;
  *) die "anchor $ANCHOR is merge_result='${MERGE_RESULT:-unset}', not an open PR's (pull_request_pending or pull_request_head_changed); the ruling-rework path applies only to an open PR" ;;
esac
DISPOSITION=$(row_meta "$ANCHOR_ROW" gc.pr_close_disposition_kind)
[ -z "$DISPOSITION" ] \
  || die "anchor $ANCHOR is disposed (gc.pr_close_disposition_kind=$DISPOSITION), so its PR is closing; nothing filed"
SUCCESSOR=$(printf '%s' "$ANCHOR_ROW" | jq -r "$DISPOSITION_JQ"'.[0] | disposed_to' 2>/dev/null)
[ -z "$SUCCESSOR" ] \
  || die "anchor $ANCHOR is superseded by $SUCCESSOR (its disposition edge names it); nothing filed"

BRANCH=$(row_meta "$ANCHOR_ROW" branch)
[ -n "$BRANCH" ] || die "anchor $ANCHOR names no branch; cannot resume it"
TARGET=$(row_meta "$ANCHOR_ROW" merged_target)
[ -n "$TARGET" ] || TARGET=$(row_meta "$ANCHOR_ROW" target)
[ -n "$TARGET" ] || die "anchor $ANCHOR names no landing target (merged_target and target both empty)"
# The script's contract is an open PR, and an anchor that names no PR is not
# one.
PR_URL=$(row_meta "$ANCHOR_ROW" existing_pr)
[ -n "$PR_URL" ] || PR_URL=$(row_meta "$ANCHOR_ROW" pr_url)
[ -n "$PR_URL" ] || die "anchor $ANCHOR names no PR (existing_pr and pr_url both empty), so it is not an open PR; nothing filed"
REASON="operator ruling (conversation $RULING_BEAD): $RULING"

ASK_ARGS=(review ask "$ANCHOR" --reason "$REASON" --source "$RULING_BEAD")
for c in "${CHECKS[@]+"${CHECKS[@]}"}"; do ASK_ARGS+=(--check "$c"); done
# The checks --check names are read from the pack's check index beside the
# pack's scripts directory, this script's own, whatever binding the rig imports
# the pack under.
ASK_OUT=$(GCTK_SCRIPTS_DIR="$SCRIPT_DIR" "$GCTK" "${ASK_ARGS[@]}" 2>&1) \
  || die "the ask that carries the ruling to $ANCHOR's review run did not stand ($(printf '%s' "$ASK_OUT" | tr -s '[:space:]' ' ')); a re-run finds one that landed"
read -r ASK HOW _ <<< "$(printf '%s\n' "$ASK_OUT" | tail -n 1)"
[ -n "$ASK" ] || die "gctk review ask named no ask for $ANCHOR; a re-run finds one that landed"
echo "converse-rework: the ruling goes to the review run of $ANCHOR's PR as ask $ASK, which holds its merge; nothing is superseded, because the run triages the head its fix pushes" >&2
printf '%s ask %s\n' "$ASK" "$HOW"
