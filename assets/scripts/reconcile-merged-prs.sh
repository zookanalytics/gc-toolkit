#!/usr/bin/env bash
# reconcile-merged-prs — close-on-land convergent pass. Walk the open gating
# anchors (the bead parked OPEN on a published PR — a convoy graduating to main,
# or any mr-mode bead — marked merge_result=pull_request by mol-refinery-patrol
# merge-push step 4) and reconcile each to its pull request's real state:
#
#   PR merged           -> close the anchor "Merged to <target> at <sha>"
#                          (merge_result=merged, merged_sha) — mirrors direct-mode.
#   PR closed, unmerged -> out-of-band close (the refinery did not do it; it
#                          closes its own abandoned PRs + anchors together).
#                          Flag: merge_result=abandoned, route to human, escalate
#                          once. We lack context, so we never auto-close it.
#   PR open, ready      -> queue `gh pr merge --auto` ONLY while the live head is
#                          signoff-validated (signoff_head == headRefOid — the
#                          check-set's title/description-current member) AND no
#                          open rework/review child references the PR (an open
#                          child holds the merge). A stale approval, a
#                          post-signoff rework commit, or in-flight rework
#                          therefore cannot merge prematurely. Branch protection
#                          still gates the real merge; the refinery never
#                          self-merges.
#   PR open, draft      -> skip (reconcile-draft-prs.sh owns un-drafting).
#
#   ANY state, retargeted (live base != anchor merged_target) -> never close as
#                          landed and never auto-merge (the work would land on
#                          the wrong branch); route to human + escalate once.
#
# This is the bead-CLOSER half of close-on-land: an anchor stays OPEN from
# PR-creation until THIS pass observes an authoritative merge. `closed` thus
# always means landed, never handed-off. The composable check-set that gates the
# merge lives in docs/work-bead-state-machine.md.
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
  | jq -c '.[] | {id, pr: (.metadata.pr_number // ""), target: (.metadata.merged_target // ""), signoff: (.metadata.signoff_head // "")}' 2>/dev/null)
[ -n "$ROWS" ] || { echo "reconcile-merged-prs: no gating anchors"; exit 0; }

closed=0; abandoned=0; automerge=0; escalated=0; retargeted=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  signoff_head=$(printf '%s' "$row" | jq -r '.signoff // empty')
  if [ -z "$id" ] || [ -z "$num" ]; then
    skipped=$((skipped + 1)); continue
  fi

  # Query `mergedAt`, NOT `merged`: `merged` is not a `gh pr view --json` field
  # on supported gh versions — it errors `Unknown JSON field: "merged"` and,
  # with stderr suppressed, empties PR_JSON, so every anchor is skipped forever
  # and close-on-land never closes anything. A non-null `mergedAt` (state also
  # reaches MERGED) is the authoritative merge signal. The test's gh stub
  # rejects unsupported fields to guard against reintroducing this.
  PR_JSON=$(gh pr view "$num" --json state,mergedAt,mergeCommit,isDraft,baseRefName,headRefOid 2>/dev/null)
  if [ -z "$PR_JSON" ]; then
    echo "reconcile-merged-prs: PR#$num view failed; skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
  merged=$(printf '%s' "$PR_JSON" | jq -r 'if (.mergedAt != null) or (.state == "MERGED") then "true" else "false" end')
  is_draft=$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')
  merge_oid=$(printf '%s' "$PR_JSON" | jq -r '.mergeCommit.oid // ""')
  head_oid=$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // ""')
  base=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // ""')
  # `target` is the anchor's recorded merged_target — the branch it expects to
  # land on. Keep the raw value for the retarget guard below; fall back to the
  # live base only when the anchor never recorded one (older anchors / direct
  # dispatches have nothing to mismatch against).
  recorded_target="$target"
  [ -n "$target" ] || target="${base:-main}"

  # --- Retarget guard: live base must still match the anchor's expected target.
  # The anchor stamped merged_target at publication. If PR#$num's LIVE base no
  # longer matches it, the PR was retargeted after publication, so a merge would
  # land (or has landed) on the WRONG branch: closing as "Merged to <expected>"
  # would record a landing that never happened, and queuing auto-merge would push
  # the work to the wrong target. Do neither while mismatched. Fires for the
  # merged close path and the open/ready auto-merge path — NOT open/draft (that
  # is reconcile-draft-prs.sh's domain) and NOT closed/unmerged (handled as
  # abandoned below). Flip the gating marker off pull_request so the anchor
  # leaves this scan: that escalates exactly once (mirroring out-of-band-close
  # handling), routes a human, and clears the now-meaningless signoff_head. The
  # anchor stays OPEN — the work has not landed on its target.
  if { [ "$merged" = "true" ] || { [ "$state" = "OPEN" ] && [ "$is_draft" != "true" ]; }; } \
       && [ -n "$recorded_target" ] && [ -n "$base" ] && [ "$recorded_target" != "$base" ]; then
    gc bd update "$id" \
      --assignee="" \
      --set-metadata merge_result=retargeted \
      --set-metadata gc.routed_to=human \
      --set-metadata blocked_reason="PR#$num retargeted: base '$base' != expected target '$recorded_target'" \
      --unset-metadata signoff_head >/dev/null 2>&1
    retargeted=$((retargeted + 1))
    if gc mail send mayor/ -s "ESCALATION: PR#$num retargeted ($base != $recorded_target) for $id" \
         -m "Gating anchor $id expects PR#$num to land on '$recorded_target' (merged_target,
stamped at publication), but the PR now targets '$base' — it was retargeted after
the refinery published it. The merge reconciler will NOT close this anchor as
landed nor queue auto-merge while base != expected target: either would
record/produce a landing on the wrong branch. The bead is left OPEN, routed to
human (merge_result=retargeted). Decide: retarget PR#$num back to
'$recorded_target' and reset merge_result=pull_request to re-engage, or update the
anchor's merged_target if the new base is intentional." >/dev/null 2>&1; then
      escalated=$((escalated + 1))
    fi
    echo "reconcile-merged-prs: $id flagged — PR#$num retargeted (base '$base' != target '$recorded_target'); routed to human + escalated"
    continue
  fi

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

  # --- PR closed, unmerged: out-of-band close. -----------------------------
  # This anchor is still OPEN with its gating marker, yet its PR is CLOSED —
  # so the refinery did NOT close it (a refinery abandonment closes the anchor
  # in the same step it closes the PR, and that anchor would no longer be in
  # this open scan). Someone closed it OUT OF BAND — a human, or a process
  # outside Gas City. We have no context for why, so we do not guess: flip off
  # the gating marker (so this pass never re-scans it), route to a human, and
  # escalate once. Leave it OPEN — the work did not land, so closing would
  # falsely read as done. (When *we* abandon, we close our own PR + anchor
  # proactively and never reach here — see docs/work-bead-state-machine.md.)
  if [ "$state" = "CLOSED" ]; then
    gc bd update "$id" \
      --assignee="" \
      --set-metadata merge_result=abandoned \
      --set-metadata gc.routed_to=human \
      --set-metadata blocked_reason="PR#$num closed out-of-band without merging" >/dev/null 2>&1
    abandoned=$((abandoned + 1))
    if gc mail send mayor/ -s "ESCALATION: out-of-band close of PR#$num for $id" \
         -m "Gating anchor $id is parked on PR#$num, which was CLOSED without merging
by something OUTSIDE the refinery (the refinery closes its own abandoned PRs and
their anchors together, so this was not us). The bead is left OPEN, routed to
human (merge_result=abandoned). Decide: reopen for rework (file a fix child with
a rejection_reason) or close as wontfix/duplicate/not-planned. The refinery never
auto-closes an unmerged anchor it did not abandon." >/dev/null 2>&1; then
      escalated=$((escalated + 1))
    fi
    echo "reconcile-merged-prs: $id flagged — PR#$num closed out-of-band; routed to human + escalated"
    continue
  fi

  # --- PR open: queue auto-merge if the check-set permits, else wait. -------
  if [ "$state" = "OPEN" ]; then
    if [ "$is_draft" = "true" ]; then
      skipped=$((skipped + 1)); continue
    fi
    # Title/description-current check (a composable check-set member; see
    # docs/work-bead-state-machine.md). Auto-merge fires the instant CI +
    # approval clear, which can be STALE — an approval from an earlier diff
    # whose title/body no longer describe what will land, or a rework commit
    # pushed after the signoff. The signoff stamps signoff_head = the head it
    # validated; we enable auto-merge ONLY while that still equals the live
    # head. A mismatch (a later commit, or no signoff yet) means the current
    # head is unvalidated: leave the PR open and unqueued so a fresh signoff
    # round runs first. This is what makes auto-merge safe to use broadly.
    if [ -z "$signoff_head" ] || [ "$signoff_head" != "$head_oid" ]; then
      echo "reconcile-merged-prs: PR#$num head not signoff-validated (have '${signoff_head:-none}', live '$head_oid'); auto-merge held (anchor $id)"
      skipped=$((skipped + 1)); continue
    fi
    # An open rework/review child holds the merge (docs/work-bead-state-machine.md:
    # an anchor lands only when ALL its children are closed). signoff_head alone
    # is not enough — the REQUEST_CHANGES arm clears it only best-effort when the
    # anchor edge resolves, and another check can file a rework child whose edge
    # is missing, so a stale signoff_head can coexist with open rework. Reuse
    # reconcile-draft-prs.sh guard (b): hold auto-merge while ANY open/in_progress
    # bead OTHER than this anchor references the PR. The anchor carries
    # merge_result; rework children and review beads do not — so excluding the
    # anchor's own id plus any merge_result-carrying bead leaves exactly the
    # in-flight rework/review set.
    inflight=$(gc bd list \
      --metadata-field pr_number="$num" \
      --status open,in_progress --limit=20 --json 2>/dev/null \
      | jq -r --arg anchor "$id" '[.[] | select(.id != $anchor) | select((.metadata.merge_result // "") == "")] | .[0].id // empty' 2>/dev/null)
    if [ -n "$inflight" ]; then
      echo "reconcile-merged-prs: PR#$num has open rework/review bead $inflight; auto-merge held (anchor $id)"
      skipped=$((skipped + 1)); continue
    fi
    # Best-effort + idempotent: queue auto-merge so GitHub lands the PR once
    # approvals + checks pass. Branch protection still gates the real merge.
    # --squash matches the repo's squash-merge convention (commit "(#N)" tail).
    if gh pr merge "$num" --auto --squash >/dev/null 2>&1; then
      automerge=$((automerge + 1))
      echo "reconcile-merged-prs: PR#$num auto-merge queued (anchor $id, head signoff-validated)"
    else
      skipped=$((skipped + 1))
    fi
    continue
  fi

  skipped=$((skipped + 1))
done <<< "$ROWS"

echo "reconcile-merged-prs: $closed closed, $abandoned abandoned ($escalated escalated), $retargeted retargeted, $automerge auto-merge queued, $skipped skipped"
exit 0
