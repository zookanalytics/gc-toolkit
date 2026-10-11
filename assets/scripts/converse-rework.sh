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
# and its rejection_reason carries the ruling. Resuming the branch keeps the PR
# and its history, which closing the PR and re-pouring would discard. converse
# never pushes code; the molecule does (docs/authority-map.md).
#
# A ruling has no lane of its own. Like a human feedback batch the validator rules
# not converged, it is operator input the whole diff was never reviewed against,
# so once the child is filed every lane the anchor declares returns to
# unreviewed (review-outcome.sh supersede-anchor). The child's blocks edge holds
# the merge and gate-ensure's quiescence holds every review dispatch while it is
# open; when it lands, each lane is re-reviewed at the new head. Without this,
# the reviews of the pre-ruling head would keep every lane green, and the merge
# would pass on content no review read.
#
# Usage:
#   converse-rework.sh --anchor <anchor-bead> --ruling-bead <visit> \
#     --ruling "<the ruling, one line>" [--pool <pool-name>]
#   The anchor must be an open PR: live in the store, at
#   merge_result=pull_request, carrying no disposition (gc.pr_close_disposition_kind
#   or gc.superseded_by), and naming its branch, its landing target and its PR.
#   --ruling-bead is the visit the ruling was reached in. --pool defaults to
#   rework-child.sh's default.
# Output: rework-child.sh's result line, "<child> <route> <filed|adopted|in-flight>".
# Exit: rework-child.sh's when it does not dispatch the child. Otherwise 0 once
#   every lane is back to unreviewed, and 2 when that supersede fails: the child
#   stands dispatched, and a re-run adopts it and retries the supersede. A
#   refusal here, before the writer runs, exits 2 with nothing written.
set -u

_lib_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 2; }
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")

die() { echo "converse-rework: $1" >&2; exit 2; }
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

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
# hold, a dispose), so no child is filed against a non-PR anchor. merge_result
# alone does not prove the PR open: a hand-closed anchor keeps the field, and an
# anchor pr-dispose.sh has disposed sits at pull_request with its PR already
# closed until pr-facts.sh consummates the close. A child filed on either would
# block a bead on its way to closed and send a worker to a branch whose PR is
# gone. So the anchor must also be live and carry no disposition.
STATUS=$(printf '%s' "$ANCHOR_ROW" | jq -r '(.[0].status // "") | tostring | ascii_downcase' 2>/dev/null)
case ",$LIVE_STATUSES," in
  *",${STATUS:-none},"*) : ;;
  *) die "anchor $ANCHOR is status='${STATUS:-unset}', not live; the ruling-rework path applies only to an open PR" ;;
esac
MERGE_RESULT=$(row_meta "$ANCHOR_ROW" merge_result)
[ "$MERGE_RESULT" = "pull_request" ] \
  || die "anchor $ANCHOR is merge_result='${MERGE_RESULT:-unset}', not pull_request; the ruling-rework path applies only to an open PR"
DISPOSITION=$(row_meta "$ANCHOR_ROW" gc.pr_close_disposition_kind)
[ -z "$DISPOSITION" ] \
  || die "anchor $ANCHOR is disposed (gc.pr_close_disposition_kind=$DISPOSITION), so its PR is closing; nothing filed"
SUCCESSOR=$(row_meta "$ANCHOR_ROW" gc.superseded_by)
[ -z "$SUCCESSOR" ] \
  || die "anchor $ANCHOR is superseded by $SUCCESSOR (gc.superseded_by); nothing filed"

# branch is authoritative for the resume: mol-polecat-work checks it out and never
# cuts a new one.
BRANCH=$(row_meta "$ANCHOR_ROW" branch)
[ -n "$BRANCH" ] || die "anchor $ANCHOR names no branch; cannot resume it"
TARGET=$(row_meta "$ANCHOR_ROW" merged_target)
[ -n "$TARGET" ] || TARGET=$(row_meta "$ANCHOR_ROW" target)
[ -n "$TARGET" ] || die "anchor $ANCHOR names no landing target (merged_target and target both empty)"
# The script's contract is an open PR, and an anchor that names no PR is not
# one. The URL also rides the child as existing_pr, which the refinery's
# merge-push checks (open, on this branch, toward this target) before it closes
# the child as landed, so a PR closed while the rework ran blocks the child for a
# person rather than taking its landing.
PR_URL=$(row_meta "$ANCHOR_ROW" existing_pr)
[ -n "$PR_URL" ] || PR_URL=$(row_meta "$ANCHOR_ROW" pr_url)
[ -n "$PR_URL" ] || die "anchor $ANCHOR names no PR (existing_pr and pr_url both empty); the child could not keep the rework on it"
PR_NUMBER=$(row_meta "$ANCHOR_ROW" pr_number)

if [ -n "$PR_NUMBER" ]; then
  TITLE="Rework PR#$PR_NUMBER: apply operator ruling"
else
  TITLE="Rework branch $BRANCH: apply operator ruling"
fi
ARGS=(--anchor "$ANCHOR" --ruling-bead "$RULING_BEAD" --branch "$BRANCH" --target "$TARGET"
      --title "$TITLE" --reason "operator ruling (converse visit $RULING_BEAD): $RULING"
      --pr-url "$PR_URL")
[ -z "$PR_NUMBER" ] || ARGS+=(--pr-number "$PR_NUMBER")
[ -z "$POOL_NAME" ] || ARGS+=(--pool "$POOL_NAME")
FILED=$("$SCRIPT_DIR/rework-child.sh" "${ARGS[@]}"); rc=$?
[ "$rc" -eq 0 ] || exit "$rc"
read -r CHILD _ <<< "$FILED"

# Run on every filing, an adopted or in-flight child's included, so a re-run
# finishes a supersede an earlier run did not. It is idempotent: a lane whose
# reviews are already superseded has nothing left to retire.
if ! RETIRED=$("$SCRIPT_DIR/review-outcome.sh" supersede-anchor --anchor "$ANCHOR" \
       --by "operator ruling (converse visit $RULING_BEAD)" \
       --reason "rework $CHILD changes what the branch must contain; every lane re-reviews it once it lands"); then
  die "rework $CHILD is dispatched, but the review lanes on $ANCHOR did not return to unreviewed (review-outcome.sh supersede-anchor failed), so its landing would read green on reviews of the branch before the ruling. Re-run: the writer adopts $CHILD and the supersede retries"
fi
echo "converse-rework: returned $ANCHOR's lanes to unreviewed ($RETIRED standing review(s) superseded); each is re-reviewed once $CHILD lands" >&2
printf '%s\n' "$FILED"
