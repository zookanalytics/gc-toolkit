#!/usr/bin/env bash
# converse-rework.sh — an operator ruling's entry to rework. A converse sitting
# can reach a ruling that changes what an already-published PR's branch must
# contain, while the PR still reads review-ready against a head that predates the
# ruling. This files the fix unit a review verdict would file, through
# rework-child.sh, the one writer of a rework child, with the visit the ruling was
# reached in as its provenance (source_ruling_bead).
#
# What is the ruling's own to decide is decided here: the anchor must be an open
# PR, the child resumes the anchor's own branch and lands where the anchor lands,
# and its rejection_reason carries the ruling. Resuming the branch keeps the PR,
# its history and its review lanes, which closing the PR and re-pouring would
# discard. converse never pushes code; the molecule does (docs/authority-map.md).
#
# Usage:
#   converse-rework.sh --anchor <anchor-bead> --ruling-bead <visit> \
#     --ruling "<the ruling, one line>" [--pool <pool-name>]
#   The anchor must be an open PR (merge_result=pull_request) and must name its
#   branch and landing target. --ruling-bead is the visit the ruling was reached
#   in. --pool defaults to rework-child.sh's default.
# Output and exit: rework-child.sh's. A refusal here, before the writer runs,
#   exits 2 with nothing written.
set -u

_lib_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 2; }
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")

die() { echo "converse-rework: $1" >&2; exit 2; }
row_meta() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }

ANCHOR=""; RULING_BEAD=""; RULING=""; POOL_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)      shift; [ $# -gt 0 ] || die "--anchor needs a value"; ANCHOR="$1" ;;
    --ruling-bead) shift; [ $# -gt 0 ] || die "--ruling-bead needs a value"; RULING_BEAD="$1" ;;
    --ruling)      shift; [ $# -gt 0 ] || die "--ruling needs a value"; RULING="$1" ;;
    --pool)        shift; [ $# -gt 0 ] || die "--pool needs a value"; POOL_NAME="$1" ;;
    -h|--help)     sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "unknown argument '$1'" ;;
  esac
  shift
done
[ -n "$ANCHOR" ]      || die "--anchor is required"
[ -n "$RULING_BEAD" ] || die "--ruling-bead is required (the visit the ruling was reached in)"
[ -n "$RULING" ]      || die "--ruling is required (the one-line ruling the rework answers)"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v gc >/dev/null 2>&1 || die "gc is required"

ANCHOR_ROW=$(bd_json show "$ANCHOR")
printf '%s' "$ANCHOR_ROW" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
  || die "anchor $ANCHOR does not resolve; nothing filed"

# A ruling on an anchor in any other state reaches it by another route (a pre-PR
# hold, a dispose), so no child is filed against a non-PR anchor.
MERGE_RESULT=$(row_meta "$ANCHOR_ROW" merge_result)
[ "$MERGE_RESULT" = "pull_request" ] \
  || die "anchor $ANCHOR is merge_result='${MERGE_RESULT:-unset}', not pull_request; the ruling-rework path applies only to an open PR"

# branch is authoritative for the resume: mol-polecat-work checks it out and never
# cuts a new one.
BRANCH=$(row_meta "$ANCHOR_ROW" branch)
[ -n "$BRANCH" ] || die "anchor $ANCHOR names no branch; cannot resume it"
TARGET=$(row_meta "$ANCHOR_ROW" merged_target)
[ -n "$TARGET" ] || TARGET=$(row_meta "$ANCHOR_ROW" target)
[ -n "$TARGET" ] || die "anchor $ANCHOR names no landing target (merged_target and target both empty)"
PR_URL=$(row_meta "$ANCHOR_ROW" existing_pr)
[ -n "$PR_URL" ] || PR_URL=$(row_meta "$ANCHOR_ROW" pr_url)
PR_NUMBER=$(row_meta "$ANCHOR_ROW" pr_number)

if [ -n "$PR_NUMBER" ]; then
  TITLE="Rework PR#$PR_NUMBER: apply operator ruling"
else
  TITLE="Rework branch $BRANCH: apply operator ruling"
fi
ARGS=(--anchor "$ANCHOR" --ruling-bead "$RULING_BEAD" --branch "$BRANCH" --target "$TARGET"
      --title "$TITLE" --reason "operator ruling (converse visit $RULING_BEAD): $RULING")
[ -z "$PR_URL" ]    || ARGS+=(--pr-url "$PR_URL")
[ -z "$PR_NUMBER" ] || ARGS+=(--pr-number "$PR_NUMBER")
[ -z "$POOL_NAME" ] || ARGS+=(--pool "$POOL_NAME")
exec "$SCRIPT_DIR/rework-child.sh" "${ARGS[@]}"
