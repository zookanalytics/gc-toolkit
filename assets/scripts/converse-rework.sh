#!/usr/bin/env bash
# converse-rework.sh — turn an operator ruling into rework demand on an
# already-published PR.
#
# A converse sitting can reach a ruling whose consequence is that an open PR is
# now stale: the ruling changes what the branch must contain, while the PR reads
# review-ready against a head that predates it. The review-driven rework path
# (signoff.sh) cannot carry that demand — it is minted from a verdict and keyed
# on source_review_bead, and a ruling has no verdict. This is the ruling's own
# entry into the same rework machinery: it files the fix unit signoff.sh files,
# sourced by source_ruling_bead instead, blocks the anchor on it, and slings
# mol-polecat-work. converse never pushes code; the molecule does
# (docs/authority-map.md).
#
# The child's shape is signoff.sh's rework child, field for field — task_kind,
# anchor_bead, branch, target, merge_strategy=mr, the PR fields — so merge.sh,
# pr-facts.sh and mol-polecat-work read it with no new case. The anchor's own
# branch is resumed, so the PR keeps its history and its green checks; closing
# the PR and re-pouring discards both.
#
# Usage:
#   converse-rework.sh --anchor <anchor-bead> --ruling-bead <visit> \
#     --ruling "<the ruling, one line>" [--pool <pool-name>]
#   The anchor must be an open PR (merge_result=pull_request) and must name its
#   branch and landing target. --ruling-bead is the visit the ruling was reached
#   in, stamped as source_ruling_bead. --pool defaults to gc-toolkit.polecat.
set -u

_lib_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
# pool-route.sh lives beside this script; the rework route is proved through it
# before the child is filed.
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")

warn() { echo "converse-rework: $*" >&2; }
die()  { warn "$1"; exit 2; }
row_meta() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

ANCHOR=""; RULING_BEAD=""; RULING=""; POOL_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)      shift; [ $# -gt 0 ] || die "--anchor needs a value"; ANCHOR="$1" ;;
    --ruling-bead) shift; [ $# -gt 0 ] || die "--ruling-bead needs a value"; RULING_BEAD="$1" ;;
    --ruling)      shift; [ $# -gt 0 ] || die "--ruling needs a value"; RULING="$1" ;;
    --pool)        shift; [ $# -gt 0 ] || die "--pool needs a value"; POOL_NAME="$1" ;;
    -h|--help)     sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# The ruling-rework path is for an already-published PR. An anchor in any other
# state is converse's by a different route (a pre-PR hold, a dispose), so refuse
# rather than mint a child against a non-PR anchor.
MERGE_RESULT=$(row_meta "$ANCHOR_ROW" merge_result)
[ "$MERGE_RESULT" = "pull_request" ] \
  || die "anchor $ANCHOR is merge_result='${MERGE_RESULT:-unset}', not pull_request; the ruling-rework path applies only to an open PR"

# The fix unit resumes the anchor's own branch and lands where the anchor lands,
# so both must be named on the anchor. branch is authoritative for the resume:
# mol-polecat-work checks it out, never cutting a new one.
BRANCH=$(row_meta "$ANCHOR_ROW" branch)
[ -n "$BRANCH" ] || die "anchor $ANCHOR names no branch; cannot resume it"
TARGET=$(row_meta "$ANCHOR_ROW" merged_target)
[ -n "$TARGET" ] || TARGET=$(row_meta "$ANCHOR_ROW" target)
[ -n "$TARGET" ] || die "anchor $ANCHOR names no landing target (merged_target and target both empty)"
PR_URL=$(row_meta "$ANCHOR_ROW" existing_pr)
[ -n "$PR_URL" ] || PR_URL=$(row_meta "$ANCHOR_ROW" pr_url)
PR_NUMBER=$(row_meta "$ANCHOR_ROW" pr_number)

# Prove the pool route before the child exists: a child nothing claims is a
# human's to find, where a dispatch left unfiled is simply retried.
[ -n "$POOL_NAME" ] || POOL_NAME="gc-toolkit.polecat"
POOL=$("$SCRIPT_DIR/pool-route.sh" "$POOL_NAME") \
  || die "the rework child would route to '$POOL_NAME', which no live pool claims; nothing filed"

REJECTION_REASON="operator ruling (converse visit $RULING_BEAD): $RULING"
if [ -n "$PR_NUMBER" ]; then
  TITLE="Rework PR#$PR_NUMBER: apply operator ruling"
else
  TITLE="Rework branch $BRANCH: apply operator ruling"
fi

# One ruling owns at most one rework child. This path is re-runnable: a retry of
# the sitting re-enters here, so a create keyed to the ruling would mint a second
# child a polecat claims while another is already in flight. Dedup on
# source_ruling_bead — the visit id, unique to one sitting's ruling and stamped
# on nothing else — and adopt the open child that already answers it. When more
# than one carries the key, prefer the one in flight (gc.execution_routed_to
# stamped): re-slinging the inert one double-dispatches the molecule the routed
# child already owns. An unreadable query cannot be told from "no prior child",
# and a create on that ambiguity is the double-file this guard prevents, so
# refuse instead.
if PRIOR=$(bd_list --metadata-field "source_ruling_bead=$RULING_BEAD" --status="$LIVE_STATUSES"); then
  FIX_BEAD=$(printf '%s' "$PRIOR" | jq -r --arg r "$RULING_BEAD" '
      [ .[]? | select((.metadata.source_ruling_bead // "") == $r) ]
      | sort_by(.created_at // .id) as $all
      | ( ( [ $all[] | select((.metadata["gc.execution_routed_to"] // "") != "") ][0] )
          // $all[0] )
      | (.id // empty)' 2>/dev/null)
else
  die "could not read prior rework children for ruling $RULING_BEAD (dedup query failed); nothing filed, retry"
fi
if [ -n "$FIX_BEAD" ]; then
  # A child that already read back a pour is in flight: re-slinging it would
  # double-dispatch the molecule, so report and stop.
  ADOPT_ROUTE=$(row_meta "$(bd_json show "$FIX_BEAD")" "gc.execution_routed_to")
  if [ -n "$ADOPT_ROUTE" ]; then
    echo "converse-rework: rework child $FIX_BEAD (source_ruling_bead=$RULING_BEAD) already dispatched to $ADOPT_ROUTE; filing no second child"
    exit 0
  fi
  # Filed by a prior attempt that never dispatched: adopt it and finish the
  # dispatch this run owes, re-stamping the work order to repair a partial write.
  echo "converse-rework: adopting existing open rework child $FIX_BEAD for ruling $RULING_BEAD (a prior attempt filed it but never dispatched); filing no second child"
else
  FIX_BEAD=$(gc bd create "$TITLE" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
  [ -n "$FIX_BEAD" ] || die "could not create the rework child; nothing filed, retry"
fi

# The stamped fields ARE the work order (signoff.sh's rework child, field for
# field): branch/target say what to resume and where it lands, existing_pr keeps
# the rework on THIS PR, source_ruling_bead names the ruling it answers.
# task_kind and anchor_bead are the role marker — the child resumes the anchor's
# own branch, so with no marker a metadata read cannot tell the child from the
# anchor. prepare_mode is left unset on purpose: the resume defaults an absent
# stamp to merge (a shared PR branch is brought current by merge, never rebased)
# and the refinery re-stamps it on prepare, the same reliance signoff.sh's child
# stands on.
META=(
  --set-metadata "task_kind=rework"
  --set-metadata "anchor_bead=$ANCHOR"
  --set-metadata "branch=$BRANCH"
  --set-metadata "target=$TARGET"
  --set-metadata "source_ruling_bead=$RULING_BEAD"
  --set-metadata "merge_strategy=mr"
  --set-metadata "rejection_reason=$REJECTION_REASON"
)
if [ -n "$PR_URL" ]; then
  META+=(--set-metadata "existing_pr=$PR_URL" --set-metadata "pr_url=$PR_URL")
fi
[ -n "$PR_NUMBER" ] && META+=(--set-metadata "pr_number=$PR_NUMBER")
gc bd update "$FIX_BEAD" "${META[@]}" >/dev/null 2>&1 || true

# The child must BLOCK the anchor: the blocks edge is what holds the merge until
# the rework lands (merge.sh honors a dep-edge blocker regardless of its source).
# Recorded the other way round the child would wait on an anchor that closes only
# once the rework lands, so nothing would ever claim it. Skip when the edge is
# already there — an adopted child carries it from the prior attempt.
if ! bd_json dep list "$ANCHOR" --direction=down -t blocks \
     | jq -e --arg f "$FIX_BEAD" 'any(.[]?; .id == $f)' >/dev/null 2>&1; then
  gc bd dep "$FIX_BEAD" --blocks "$ANCHOR" >/dev/null 2>&1 || true
fi

# Verify the work order and the blocks edge BEFORE the pour, so a claimed rework
# can never run against absent fields.
FIX_ROW=$(bd_json show "$FIX_BEAD")
MISSING=$(printf '%s' "$FIX_ROW" | jq -r \
  --arg b "$BRANCH" --arg t "$TARGET" --arg pr "$PR_URL" --arg a "$ANCHOR" '
  (.[0] // {}) as $x | ($x.metadata // {}) as $m | [
    (if ($m.task_kind // "") == "rework" then empty else "task_kind" end),
    (if ($m.anchor_bead // "") == $a then empty else "anchor_bead" end),
    (if ($m.branch // "") == $b then empty else "branch" end),
    (if ($m.target // "") == $t then empty else "target" end),
    (if ($m.source_ruling_bead // "") != "" then empty else "source_ruling_bead" end),
    (if ($m.merge_strategy // "") == "mr" then empty else "merge_strategy" end),
    (if ($m.rejection_reason // "") != "" then empty else "rejection_reason" end),
    (if $pr == "" or ($m.existing_pr // "") == $pr then empty else "pr_fields" end)
  ] | join(",") | if . == "" then "ok" else . end' 2>/dev/null)
if [ "$MISSING" = "ok" ]; then
  EDGE=$(bd_json dep list "$ANCHOR" --direction=down -t blocks \
    | jq -r --arg f "$FIX_BEAD" 'if type == "array" and any(.[]; .id == $f) then "ok" else "" end' 2>/dev/null)
  [ "$EDGE" = "ok" ] || MISSING="blocks_edge"
fi
if [ "$MISSING" != "ok" ]; then
  die "rework child $FIX_BEAD work order incomplete (${MISSING:-unreadable}); it blocks the anchor but was not dispatched — repair with: gc bd show $FIX_BEAD --json | jq '.[0].metadata'"
fi

# Dispatch is a sling, not a bare route stamp. mol-polecat-work gives the rework
# the control-dispatcher driver and continuation affinity a bare gc.routed_to has
# no driver for. The pour retires gc.routed_to and stamps
# gc.execution_routed_to=<pool> on the child — that read-back is the proof. If it
# does not read back, the pour may still have started the workflow and only
# failed to stamp the route; a bare gc.routed_to stamp would then let the pool
# claim query and the workflow dispatcher both act on the same work. So never
# bare-stamp: exit non-zero and leave the child filed-but-undispatched for a
# retry. The child blocks the anchor either way, so the merge stays held while
# the retry runs.
WORK_FORMULA="mol-polecat-work"
gc sling ${GC_RIG:+--rig "$GC_RIG"} "$POOL" "$FIX_BEAD" --on "$WORK_FORMULA" >/dev/null 2>&1
if [ "$(row_meta "$(bd_json show "$FIX_BEAD")" "gc.execution_routed_to")" = "$POOL" ]; then
  gc session wake "$POOL" >/dev/null 2>&1 || true
  gc session nudge "$POOL" "Rework $FIX_BEAD for anchor $ANCHOR (operator ruling)" >/dev/null 2>&1 || true
else
  die "rework child $FIX_BEAD: mol-polecat-work pour did not stamp gc.execution_routed_to=$POOL; not falling back to a bare route (double-dispatch hazard) — the child blocks the anchor; retry the dispatch"
fi
echo "converse-rework: filed rework $FIX_BEAD on anchor $ANCHOR (branch $BRANCH -> $TARGET), slung $WORK_FORMULA to $POOL"
exit 0
