#!/usr/bin/env bash
# one-anchor-per-pr — the refinery's mr-mode terminal transition: a rework
# hand-back lands on an anchor that already gates its branch, and anything else
# becomes the branch's anchor in a gating state.
#
#   one-anchor-per-pr.sh resolve --work <bead> --branch <branch>
#   one-anchor-per-pr.sh land --work <bead> --branch <branch> --target <target>
#                             --check-set <set> --pre-open 0|1 --prep-wt <dir>
#                             [--recorded-pr <ref>] [--pr-url <url> --pr-number <n>]
#
# THE INVARIANT (doctor/check-one-anchor-per-pr): one open bead per branch
# carries a merge_result, the anchor. Branch is the join key, and a merge_result
# present is the whole predicate: every declared state carries one, so an anchor
# parked for a person (blocked, held, abandoned, retargeted,
# refused_false_completion) still owns its PR, and a lookup restricted to the
# gating states walks past it and mints the second anchor it exists to prevent.
# Several candidates resolve to the OLDEST, since the original predates any
# rework-minted duplicate; `created_at` is the real field. An empty branch never
# reaches the lookup, because `--metadata-field branch=` matches every bead that
# records no branch.
#
# `resolve` prints EXISTING_ANCHOR=<id or empty> and GATING_ANCHOR=<id>.
#
# `land`, when another open bead anchors the branch, treats --work as a rework
# hand-back. It moves the bead to `unanchored` through lifecycle.sh (the
# lifecycle field's only writer, and `unanchored` is the declared edge out of
# every gating state) and closes it landed-on-branch, never stamping a
# merge_result on it: a merge_result-carrying child joins the anchor enumeration
# as a gateless second anchor. Gating continues on the existing anchor, whose
# lane markers are states of the lane, not of the head. The landing is proved
# against origin first: a fetch that fails, or a refreshed origin/<branch> that
# is not the prepared head, records nothing, closes nothing, and drains with the
# bead still routed for the next pass to re-push. A refused transition leaves the
# bead open, because a bead closed still carrying a merge_result is an I5 error
# (doctor/check-closed-implies-landed). The close is `gc bd update
# --status=closed`, never `gc bd close`: bd's ownership check lives on the close
# verb and refuses a bead assigned to another principal, which every bead the
# refinery closes is, and that refusal repeats on every pass.
#
# Post-open, --recorded-pr names the PR the bead records (existing_pr, pr_url or
# pr_number). `land` reads its url and number through gh and refuses, exit 4 and
# no transition, a PR that is not OPEN with head <branch> and base <target>: the
# caller sends a caller-supplied existing_pr to its blocked arm and stops on any
# other. --pr-url and --pr-number pass the coordinates directly instead.
#
# Otherwise `land` stamps --work as the anchor, open and detached from both work
# queues: pull_request when the PR's url and number both resolved, else
# pre_open_gate, where pr-open.sh opens the PR or adopts the recorded one. An
# empty pr_number is unaddressable by merge.sh and pr-facts.sh forever, so a PR
# without both coordinates parks at pre_open_gate.
#
# Called by mol-refinery-patrol's merge-push step.
# env: GC_LIFECYCLE_TOOL replaces the sibling lifecycle.sh.
# exit: 0 landed or stamped, or a refused rework write reported for the next
#       pass to retry · 1 the rework landing is not proved on origin (drained)
#       · 2 usage · 4 the recorded PR does not match the branch (nothing written)
#       · lifecycle.sh's own code when the gating transition is refused
set -uo pipefail

PROG="one-anchor-per-pr"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LC="${GC_LIFECYCLE_TOOL:-$SCRIPTS_DIR/lifecycle.sh}"

usage() {
  cat >&2 <<'USAGE'
usage: one-anchor-per-pr.sh resolve --work <bead> --branch <branch>
       one-anchor-per-pr.sh land --work <bead> --branch <branch> --target <target>
                                 --check-set <set> --pre-open 0|1 --prep-wt <dir>
                                 [--recorded-pr <ref>] [--pr-url <url> --pr-number <n>]
USAGE
}

CMD="${1:-}"; [ $# -gt 0 ] && shift
WORK=""; BRANCH=""; TARGET=""; CHECK_SET=""; PRE_OPEN=""; PREP_WT=""; PR_URL=""; PR_NUMBER=""; RECORDED_PR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --work|--branch|--target|--check-set|--pre-open|--prep-wt|--pr-url|--pr-number|--recorded-pr)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; usage; exit 2; }
      case "$1" in
        --work)      WORK="$2" ;;
        --branch)    BRANCH="$2" ;;
        --target)    TARGET="$2" ;;
        --check-set) CHECK_SET="$2" ;;
        --pre-open)  PRE_OPEN="$2" ;;
        --prep-wt)   PREP_WT="$2" ;;
        --pr-url)    PR_URL="$2" ;;
        --pr-number) PR_NUMBER="$2" ;;
        --recorded-pr) RECORDED_PR="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ -n "$WORK" ] || { echo "$PROG: --work is required" >&2; usage; exit 2; }

EXISTING_ANCHOR=""
if [ -n "$BRANCH" ]; then
  ANCHOR_ROWS=$(gc bd list --status=open --metadata-field branch="$BRANCH" --limit=0 --json 2>/dev/null) || ANCHOR_ROWS=""
  EXISTING_ANCHOR=$(printf '%s' "$ANCHOR_ROWS" | jq -r --arg self "$WORK" '[ .[]? | select(.id != $self)
       | select((((.metadata // {}).merge_result // "") | tostring) != "") ]
     | sort_by(.created_at // .created // .id) | .[0].id // empty' 2>/dev/null) || EXISTING_ANCHOR=""
fi
GATING_ANCHOR="${EXISTING_ANCHOR:-$WORK}"

case "$CMD" in
  resolve)
    printf 'EXISTING_ANCHOR=%s\nGATING_ANCHOR=%s\n' "$EXISTING_ANCHOR" "$GATING_ANCHOR"
    exit 0 ;;
  land) ;;
  *) usage; exit 2 ;;
esac
if [ -z "$TARGET" ] || [ -z "$PRE_OPEN" ] || [ -z "$PREP_WT" ]; then
  echo "$PROG: land requires --target, --pre-open and --prep-wt" >&2
  usage
  exit 2
fi

if [ "$PRE_OPEN" != 1 ] && [ -n "$RECORDED_PR" ] && command -v gh >/dev/null 2>&1; then
  PR_VIEW=$(gh pr view "$RECORDED_PR" --json url,number,state,headRefName,baseRefName 2>/dev/null)
  PR_URL=$(printf '%s' "$PR_VIEW" | jq -r '.url // empty' 2>/dev/null)
  PR_NUMBER=$(printf '%s' "$PR_VIEW" | jq -r '.number // empty | tostring' 2>/dev/null)
  if [ -n "$PR_URL" ]; then
    PR_FACTS=$(printf '%s' "$PR_VIEW" | jq -r '[.state, .headRefName, .baseRefName] | join(" ")' 2>/dev/null)
    if [ "$PR_FACTS" != "OPEN $BRANCH $TARGET" ]; then
      echo "merge-push: recorded PR $RECORDED_PR reads '$PR_FACTS', want 'OPEN $BRANCH $TARGET'; transitioning nothing" >&2
      exit 4
    fi
  fi
fi

if [ -n "$EXISTING_ANCHOR" ]; then
  if ! git -C "$PREP_WT" fetch origin "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}" >/dev/null 2>&1; then
    echo "merge-push: could not fetch origin/$BRANCH to read back the rework landing; recording no landing and closing nothing. $WORK stays routed for the next pass to re-push." >&2
    gc runtime drain-ack
    exit 1
  fi
  PREPARED_HEAD=$(git -C "$PREP_WT" rev-parse HEAD 2>/dev/null || echo "")
  REMOTE_HEAD=$(git -C "$PREP_WT" rev-parse "origin/$BRANCH" 2>/dev/null || echo "")
  if [ -z "$PREPARED_HEAD" ] || [ -z "$REMOTE_HEAD" ] || [ "$PREPARED_HEAD" != "$REMOTE_HEAD" ]; then
    echo "merge-push: origin/$BRANCH is '${REMOTE_HEAD:-absent}', want prepared head '${PREPARED_HEAD:-absent}' — the rework fix is not on origin; recording no landing and closing nothing. $WORK stays routed for the next pass to re-push." >&2
    gc runtime drain-ack
    exit 1
  fi
  REWORK_SHA=$(git -C "$PREP_WT" rev-parse --short "origin/$BRANCH" 2>/dev/null || echo "")
  gc bd update "$EXISTING_ANCHOR" --append-notes "Rework $WORK landed on $BRANCH${REWORK_SHA:+ at $REWORK_SHA}; re-gate belongs to the cadence (one-anchor-per-PR)." >/dev/null 2>&1 || true
  if "$LC" transition "$WORK" --to unanchored --unset rejection_reason; then
    if ! gc bd update "$WORK" --status=closed --append-notes "Rework landed on $BRANCH${REWORK_SHA:+ at $REWORK_SHA}; gating continues on anchor $EXISTING_ANCHOR"; then
      echo "merge-push: $WORK left the anchor class but the close was refused; it stays unanchored and open, and the next pass retries both idempotently" >&2
    fi
  else
    echo "merge-push: $WORK could not be moved off its anchor state; left OPEN for the next pass rather than closed still carrying one (doctor/check-closed-implies-landed)" >&2
  fi
elif [ "$PRE_OPEN" = 1 ] || [ -z "$PR_URL" ] || [ -z "$PR_NUMBER" ]; then
  if [ "$PRE_OPEN" != 1 ]; then
    echo "merge-push: $WORK records a PR but url/number did not both resolve (url='$PR_URL' number='$PR_NUMBER'); parking at pre_open_gate so pr-open.sh adopts the PR — an empty pr_number is unaddressable by merge.sh and pr-facts.sh forever." >&2
  fi
  "$LC" transition "$WORK" --to pre_open_gate --assignee "" --route "" --set merged_target="$TARGET" --set check_set="$CHECK_SET" --unset rejection_reason
else
  "$LC" transition "$WORK" --to pull_request --assignee "" --route "" --set pr_url="$PR_URL" --set pr_number="$PR_NUMBER" --set merged_target="$TARGET" --set check_set="$CHECK_SET" --unset rejection_reason
fi
