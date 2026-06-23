#!/usr/bin/env bash
# reconcile-merged-prs — close-on-merge convergent pass. Walk the open gating
# anchors (work beads parked OPEN on a published PR, marked
# merge_result=pull_request by mol-refinery-patrol merge-push step 4) and
# reconcile each to its pull request's real state:
#
#   PR merged           -> close the anchor "Merged to <target> at <sha>"
#                          (merge_result=merged, merged_sha) — mirrors direct-mode.
#   PR closed, unmerged -> abandoned: flip merge_result=abandoned, route to
#                          human, escalate to mayor once. Honest (the work did
#                          not land) but no longer a silent open anchor.
#   PR open, ready      -> best-effort `gh pr merge --auto` so the merge lands
#                          once approvals + checks pass. Branch protection still
#                          gates the real merge; auto-merge only drops the manual
#                          click. The refinery never self-merges.
#   PR open, draft      -> skip (reconcile-draft-prs.sh owns un-drafting).
#
# This is the bead-CLOSER half of close-on-merge: a work bead stays OPEN from
# PR-creation until THIS pass observes an authoritative merge. `closed` thus
# always means merged, never handed-off. See docs/work-bead-state-machine.md.
#
# The refinery patrol runs this on each idle wake, folded into the find-work
# step's sleep loop alongside reconcile-draft-prs.sh. Convergent + idempotent: a
# closed anchor leaves the gating set (status), an abandoned anchor flips off
# merge_result=pull_request, so neither is re-scanned; a transient failure is
# simply retried next idle pass. Cheap — one `gh pr view` per gating anchor, and
# gating anchors are few (bounded by in-flight PRs).
#
# Enumerated by BEAD, not by `gh pr list`: each anchor's pr_number resolves in
# this repo by construction, so there is no cross-repo PR-number collision.
#
# NOT set -e: best-effort, must never abort the patrol's idle loop. A bead is
# CLOSED only on an authoritative merged=true — any tool error skips the anchor,
# it never closes one.
set -uo pipefail

# gh is the only way to read PR state here (like the codex gate and the
# draft-PR reconciler). Without it there is nothing to do.
command -v gh >/dev/null 2>&1 || exit 0

# Open gating anchors in this rig's ledger.
ANCHORS=$(gc bd list --status=open \
  --metadata-field merge_result=pull_request \
  --limit=200 --json 2>/dev/null)
[ -n "$ANCHORS" ] && [ "$ANCHORS" != "[]" ] \
  || { echo "reconcile-merged-prs: no gating anchors"; exit 0; }

# One compact JSON row per anchor. Built into a variable (not piped into the
# loop) so the loop runs in THIS shell and the counters below survive — the
# same pipe/subshell guard reconcile-draft-prs.sh relies on.
ROWS=$(printf '%s' "$ANCHORS" \
  | jq -c '.[] | {id, pr: (.metadata.pr_number // ""), target: (.metadata.merged_target // "")}' 2>/dev/null)
[ -n "$ROWS" ] || { echo "reconcile-merged-prs: no gating anchors"; exit 0; }

closed=0; abandoned=0; automerge=0; escalated=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  if [ -z "$id" ] || [ -z "$num" ]; then
    skipped=$((skipped + 1)); continue
  fi

  PR_JSON=$(gh pr view "$num" --json state,merged,mergeCommit,isDraft,baseRefName 2>/dev/null)
  if [ -z "$PR_JSON" ]; then
    echo "reconcile-merged-prs: PR#$num view failed; skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
  merged=$(printf '%s' "$PR_JSON" | jq -r '.merged // false')
  is_draft=$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')
  merge_oid=$(printf '%s' "$PR_JSON" | jq -r '.mergeCommit.oid // ""')
  [ -n "$target" ] || target=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // "main"')

  # --- PR merged: close the anchor (close-FIRST for convergence). -----------
  # If the close fails the anchor stays open + merge_result=pull_request and is
  # retried next pass. The merged_sha/merge_result write is best-effort AFTER
  # the close — the close reason already names the merge commit, so a failed
  # metadata write loses no authority, only a forensic field.
  if [ "$merged" = "true" ]; then
    short=$(printf '%.8s' "$merge_oid")
    if gc bd close "$id" --reason "Merged to $target at ${short:-merge}" >/dev/null 2>&1; then
      gc bd update "$id" \
        --set-metadata merge_result=merged \
        --set-metadata merged_sha="$merge_oid" \
        --unset-metadata rejection_reason >/dev/null 2>&1 || true
      closed=$((closed + 1))
      echo "reconcile-merged-prs: closed $id — PR#$num merged to $target at ${short:-?}"
    else
      echo "reconcile-merged-prs: $id close failed for merged PR#$num; retry next pass" >&2
      skipped=$((skipped + 1))
    fi
    continue
  fi

  # --- PR closed, unmerged: abandoned path. --------------------------------
  # Flip off the gating marker (so this pass never re-scans it), route to human,
  # escalate to mayor once. Leave it OPEN — the work did not land, so closing
  # would falsely read as done. Mirrors block_existing_pr's human hand-off.
  if [ "$state" = "CLOSED" ]; then
    gc bd update "$id" \
      --assignee="" \
      --set-metadata merge_result=abandoned \
      --set-metadata gc.routed_to=human \
      --set-metadata blocked_reason="PR#$num closed without merging" >/dev/null 2>&1
    abandoned=$((abandoned + 1))
    if gc mail send mayor/ -s "ESCALATION: abandoned PR#$num for $id" \
         -m "Gating anchor $id is parked on PR#$num, which was CLOSED without merging.
The bead is left OPEN, routed to human (merge_result=abandoned). Decide: reopen
for rework (re-route to the fix pool with a rejection_reason) or close as
wontfix/duplicate/not-planned. Close-on-merge never auto-closes an unmerged
anchor." >/dev/null 2>&1; then
      escalated=$((escalated + 1))
    fi
    echo "reconcile-merged-prs: $id abandoned — PR#$num closed unmerged; routed to human + escalated"
    continue
  fi

  # --- PR open: queue auto-merge if ready, else leave draft to the other pass.
  if [ "$state" = "OPEN" ]; then
    if [ "$is_draft" = "true" ]; then
      skipped=$((skipped + 1)); continue
    fi
    # Best-effort + idempotent: queue auto-merge so GitHub lands the PR once
    # approvals + checks pass. Branch protection still gates the real merge.
    # --squash matches the repo's squash-merge convention (commit "(#N)" tail).
    if gh pr merge "$num" --auto --squash >/dev/null 2>&1; then
      automerge=$((automerge + 1))
      echo "reconcile-merged-prs: PR#$num auto-merge queued (anchor $id)"
    else
      skipped=$((skipped + 1))
    fi
    continue
  fi

  skipped=$((skipped + 1))
done <<< "$ROWS"

echo "reconcile-merged-prs: $closed closed, $abandoned abandoned ($escalated escalated), $automerge auto-merge queued, $skipped skipped"
exit 0
