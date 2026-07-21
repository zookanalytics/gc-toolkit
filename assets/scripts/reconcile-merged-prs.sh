#!/usr/bin/env bash
# reconcile-merged-prs — close-on-land DETECT-ONLY observer pass. Walk the open
# gating anchors (the bead parked OPEN on a published PR — a convoy graduating to
# main, or any mr-mode bead — marked merge_result=pull_request by
# mol-refinery-patrol merge-push step 4) and reconcile each to its pull request's
# real state. This is the OBSERVER half of close-on-land: it RECORDS merges it
# observes and ESCALATES discrepancies, but it has NO merge authority — the merge
# itself is performed by the merge skill (merge-skill.sh), the single writer of
# merged-truth. See docs/work-bead-state-machine.md "Merge: one writer of
# merged-truth".
#
#   PR merged           -> close the anchor "Merged to <target> at <sha>"
#                          (merge_result=merged, merged_sha) — mirrors direct-mode.
#                          This is the convergent RECORD: the merge skill records
#                          its own merge synchronously, and THIS path is the
#                          backstop for a skill that died between merging and
#                          recording (or a merge that happened out-of-band).
#   PR closed, unmerged -> out-of-band close (the refinery did not do it; it
#                          closes its own abandoned PRs + anchors together).
#                          Flag: merge_result=abandoned, route to human, escalate
#                          once. We lack context, so we never auto-close it.
#   PR open, ready      -> DETECT-ONLY: leave it for the merge skill. The observer
#                          never runs `gh pr merge`. The anchor stays OPEN until
#                          this pass observes an authoritative merge.
#   PR open, CONFLICTING -> stale base: the PR cannot merge and never will on its
#                          own. File a rework child to rebase the branch and route
#                          it to the fix pool. The anchor stays gating.
#   PR open, draft      -> skip (drafts are retired, so the refinery creates no
#                          draft PR; a stray draft is left untouched).
#
#   ANY state, retargeted (live base != anchor merged_target) -> never close as
#                          landed (the work would land on the wrong branch), and
#                          the merge skill independently refuses to merge it;
#                          route to human + escalate once.
#
# This is the bead-CLOSER + discrepancy-detector half of close-on-land: an anchor
# stays OPEN from PR-creation until THIS pass observes an authoritative merge.
# `closed` thus always means landed, never handed-off. The merge skill that
# actually lands a ready PR (validate -> merge -> record), and the composable
# check-set that gates it, live in merge-skill.sh and
# docs/work-bead-state-machine.md.
#
# The refinery patrol runs this on each idle wake, folded into the find-work
# step's sleep loop, AFTER the merge skill. Convergent + idempotent: a closed
# anchor leaves the gating set (status), an abandoned/retargeted anchor flips off
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

# Pool the stale-base arm routes its rework children to. Passed by the patrol
# (which alone can render {{binding_prefix}}); an anchor may override per-bead
# with metadata.fix_target_pool. Unresolvable -> that arm escalates to human
# instead of filing an unroutable child.
FIX_POOL_DEFAULT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix-pool)
      FIX_POOL_DEFAULT="${2:-}"
      if [ $# -ge 2 ]; then shift 2; else shift; fi
      ;;
    *) shift ;;
  esac
done

# gh is the only way to read PR state here (like the codex gate). Without it
# there is nothing to do.
command -v gh >/dev/null 2>&1 || exit 0

# Open gating anchors in this rig's ledger.
ANCHORS=$(gc bd list --status=open \
  --metadata-field merge_result=pull_request \
  --limit=200 --json 2>/dev/null)
[ -n "$ANCHORS" ] && [ "$ANCHORS" != "[]" ] \
  || { echo "reconcile-merged-prs: no gating anchors"; exit 0; }

# One compact JSON row per anchor. Built into a variable (not piped into the
# loop) so the loop runs in THIS shell and the counters below survive the
# pipe/subshell boundary.
ROWS=$(printf '%s' "$ANCHORS" \
  | jq -c '.[] | {id, pr: (.metadata.pr_number // ""), target: (.metadata.merged_target // ""), checkset: (.metadata.check_set // ""), branch: (.metadata.branch // ""), fixpool: (.metadata.fix_target_pool // ""), staled: (.metadata.stale_base_head // "")}' 2>/dev/null)
[ -n "$ROWS" ] || { echo "reconcile-merged-prs: no gating anchors"; exit 0; }

closed=0; abandoned=0; escalated=0; retargeted=0; rebased=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  if [ -z "$id" ] || [ -z "$num" ]; then
    skipped=$((skipped + 1)); continue
  fi

  # Query `mergedAt`, NOT `merged`: `merged` is not a `gh pr view --json` field
  # on supported gh versions — it errors `Unknown JSON field: "merged"` and,
  # with stderr suppressed, empties PR_JSON, so every anchor is skipped forever
  # and close-on-land never closes anything. A non-null `mergedAt` (state also
  # reaches MERGED) is the authoritative merge signal. The test's gh stub
  # rejects unsupported fields to guard against reintroducing this.
  PR_JSON=$(gh pr view "$num" --json state,mergedAt,mergeCommit,isDraft,baseRefName,headRefName,headRefOid,mergeable,mergeStateStatus,url 2>/dev/null)
  if [ -z "$PR_JSON" ]; then
    echo "reconcile-merged-prs: PR#$num view failed; skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
  merged=$(printf '%s' "$PR_JSON" | jq -r 'if (.mergedAt != null) or (.state == "MERGED") then "true" else "false" end')
  is_draft=$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')
  merge_oid=$(printf '%s' "$PR_JSON" | jq -r '.mergeCommit.oid // ""')
  base=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // ""')
  head_ref=$(printf '%s' "$PR_JSON" | jq -r '.headRefName // ""')
  head_oid=$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // ""')
  mergeable=$(printf '%s' "$PR_JSON" | jq -r '.mergeable // ""')
  merge_state=$(printf '%s' "$PR_JSON" | jq -r '.mergeStateStatus // ""')
  pr_url=$(printf '%s' "$PR_JSON" | jq -r '.url // ""')
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
  # would record a landing that never happened. Do not close while mismatched
  # (the merge skill independently refuses to merge across the mismatch). Fires
  # for the merged close path and any open/non-draft PR — NOT open/draft (a
  # stray draft is skipped) and NOT closed/unmerged (handled as
  # abandoned below). Flip the gating marker off pull_request so the anchor
  # leaves this scan: that escalates exactly once (mirroring out-of-band-close
  # handling), routes a human, and clears the now-meaningless per-gate check.*
  # markers (so a re-engaged anchor must re-earn every gate against the new base,
  # never merging on a review of the pre-retarget diff). The anchor stays OPEN —
  # the work has not landed on its target.
  if { [ "$merged" = "true" ] || { [ "$state" = "OPEN" ] && [ "$is_draft" != "true" ]; }; } \
       && [ -n "$recorded_target" ] && [ -n "$base" ] && [ "$recorded_target" != "$base" ]; then
    # Build --unset-metadata flags for each gate the anchor declared in check_set.
    # The markers are dynamic keys (check.<name>), so they cannot be a single
    # static flag; empty check_set yields no flags. Intentionally word-split on use.
    UNSET_CHECKS=$(printf '%s' "$row" | jq -r '
      ((.checkset // "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))
       | map("--unset-metadata", "check." + .) | .[])' 2>/dev/null | tr '\n' ' ')
    gc bd update "$id" \
      --assignee="" \
      --set-metadata merge_result=retargeted \
      --set-metadata gc.routed_to=human \
      --set-metadata blocked_reason="PR#$num retargeted: base '$base' != expected target '$recorded_target'" \
      $UNSET_CHECKS >/dev/null 2>&1
    retargeted=$((retargeted + 1))
    if gc mail send mayor/ -s "ESCALATION: PR#$num retargeted ($base != $recorded_target) for $id" \
         -m "Gating anchor $id expects PR#$num to land on '$recorded_target' (merged_target,
stamped at publication), but the PR now targets '$base' — it was retargeted after
the refinery published it. The merge reconciler will NOT close this anchor as
landed, and the merge skill will NOT merge it, while base != expected target:
either would record/produce a landing on the wrong branch. The bead is left OPEN,
routed to human (merge_result=retargeted). Decide: retarget PR#$num back to
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
      # Clear the in-flight blockers too: a landed anchor carrying a stale
      # blocked_reason / stale_base_head reads as still-stuck to a human.
      gc bd update "$id" \
        --set-metadata merge_result=merged \
        --set-metadata merged_sha="$merge_oid" \
        --unset-metadata rejection_reason \
        --unset-metadata blocked_reason \
        --unset-metadata stale_base_head >/dev/null 2>&1 || true
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

  # --- PR open, CONFLICTING: stale base — route a rebase. -------------------
  # The merge skill holds a conflicted PR and retries (correct: never merge a
  # conflict), but a conflict is NOT transient the way BLOCKED/UNSTABLE/UNKNOWN
  # are: retrying forever never clears it. The common cause is a rewritten base —
  # an upstream-rebase landing force-pushes the target, every open PR's base
  # commit is rewritten out, and every gating anchor goes CONFLICTING at once.
  # Before this arm nothing re-routed them: the anchor sits open, unassigned,
  # gc.routed_to="" (detached from both queues by design), so no polecat is ever
  # dispatched and the work is stranded indefinitely — invisibly, because a
  # gating anchor is only watched by this pass.
  #
  # The remedy is mechanical (rebase the branch onto the current base and
  # force-push), so this routes it instead of escalating: file a rework CHILD of
  # the anchor and hand it to the fix pool. A child — never the anchor reopened —
  # is how rework is filed (docs/work-bead-state-machine.md); it also carries
  # pr_number, so while it is open the merge skill's in-flight-rework gate holds
  # the merge, and on hand-back the patrol's one-anchor-per-PR arm recognizes the
  # shared branch and closes it as landed-on-branch instead of minting a second
  # anchor (tk-ynz4b).
  #
  # The anchor KEEPS merge_result=pull_request — deliberately unlike the
  # retargeted/abandoned arms, which flip it off to leave this scan. Those two
  # need a human decision; this one does not, and flipping the marker would
  # remove the anchor from the merge skill's scan too, so the rebased PR would
  # sit ready with nothing left to land it — trading a visible stall for a silent
  # one. Convergence comes instead from stale_base_head=<head at detection>: the
  # arm fires once per head, and re-arms only when the head moves (a later
  # rewrite conflicting the new head is a genuinely new stall).
  #
  # Bound: ONE auto-rework per head. If the rework closes without moving the head
  # the arm stays quiet — the anchor holds with blocked_reason set and its closed
  # child in the ledger, and the polecat that could not rebase escalates through
  # its own channel. Repeatedly re-filing children at an unchanged head would
  # spin the pool instead.
  #
  # `mergeable` (CONFLICTING) and `mergeStateStatus` (DIRTY) are computed
  # asynchronously by GitHub; UNKNOWN/blank means "still computing" and must NOT
  # fire — only the two definite conflict readings do.
  if [ "$state" = "OPEN" ] && [ "$is_draft" != "true" ] \
     && { [ "$mergeable" = "CONFLICTING" ] || [ "$merge_state" = "DIRTY" ]; }; then
    prior=$(printf '%s' "$row" | jq -r '.staled // empty')
    pool=$(printf '%s' "$row" | jq -r '.fixpool // empty')
    [ -n "$pool" ] || pool="$FIX_POOL_DEFAULT"
    # The head this pass would route. An unreadable head degrades to the literal
    # "unknown" rather than to "" — an empty marker would never match on the next
    # pass and the arm would re-file on every wake.
    head_key="${head_oid:-unknown}"
    # Already routed at this exact head: nothing changed, do not re-file.
    if [ "$prior" = "$head_key" ]; then
      skipped=$((skipped + 1)); continue
    fi
    # Someone is already reworking this PR (a signoff REQUEST_CHANGES child, or
    # our own from an earlier head). Adding a second rework child would race it.
    # Same query the merge skill's in-flight hold uses: referencing beads that
    # carry no merge_result are the open rework/review set. --limit=0 so the
    # check sees every child, not a page of them.
    inflight=$(gc bd list \
      --metadata-field pr_number="$num" \
      --status open,in_progress --limit=0 --json 2>/dev/null \
      | jq -r --arg anchor "$id" '[.[] | select(.id != $anchor) | select((.metadata.merge_result // "") == "")] | .[0].id // empty' 2>/dev/null)
    if [ -n "$inflight" ]; then
      skipped=$((skipped + 1)); continue
    fi
    if [ -z "$pool" ]; then
      # No pool to route to: this would file a child nothing ever claims, so
      # surface it as a human-routed stall instead (the pre-fix behaviour was to
      # surface nothing at all). merge_result is still left intact so the merge
      # skill lands it if a human rebases the branch by hand.
      gc bd update "$id" \
        --set-metadata stale_base_head="${head_oid:-unknown}" \
        --set-metadata gc.routed_to=human \
        --set-metadata blocked_reason="PR#$num conflicts with base '$base' (stale base); no fix pool configured to rebase it" >/dev/null 2>&1
      if gc mail send mayor/ -s "ESCALATION: PR#$num conflicted (stale base) with no fix pool for $id" \
           -m "Gating anchor $id is parked on PR#$num, which cannot merge: it conflicts with its
base '$base' (mergeable='${mergeable:-?}', mergeStateStatus='${merge_state:-?}'), typically
because the base branch was rewritten under it. The remedy is a rebase of branch
'${head_ref:-?}' onto '$base' + force-push, but no fix pool is configured (no
--fix-pool from the patrol, no metadata.fix_target_pool on the anchor), so the
reconciler cannot route it. Rebase it by hand — the anchor stays gating, so the
merge skill lands it once the conflict clears — or configure the pool." >/dev/null 2>&1; then
        escalated=$((escalated + 1))
      fi
      echo "reconcile-merged-prs: $id flagged — PR#$num conflicted (stale base) and no fix pool; routed to human + escalated"
      continue
    fi
    # `head_ref` is the PR's live head branch — authoritative over the anchor's
    # recorded branch — and is what the rework must resume (existing_pr makes the
    # patrol rework THAT PR rather than open a second one). With neither, the
    # child would have nothing to check out: skip rather than file a dud.
    fix_branch="$head_ref"
    [ -n "$fix_branch" ] || fix_branch=$(printf '%s' "$row" | jq -r '.branch // empty')
    if [ -z "$fix_branch" ] || [ -z "$pr_url" ]; then
      echo "reconcile-merged-prs: $id — PR#$num conflicted but head branch/url unreadable; skip (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    FIX_BEAD=$(gc bd create "Rebase PR#$num onto $base: base rewritten, PR conflicts" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
    if [ -z "$FIX_BEAD" ]; then
      echo "reconcile-merged-prs: $id could not file rebase bead for PR#$num; retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    # The routing fields ARE the dispatch — an unstamped child is an orphan no
    # pool ever claims. If the write fails, say so loudly and still stamp the
    # anchor below: the marker bounds this to ONE orphan rather than a fresh one
    # every wake, and the log line names the bead a human can route by hand.
    gc bd update "$FIX_BEAD" \
      --set-metadata branch="$fix_branch" \
      --set-metadata target="$base" \
      --set-metadata rejection_reason="stale base: PR#$num conflicts with '$base' (base rewritten under it). Rebase '$fix_branch' onto origin/$base, resolve conflicts, and force-push with --force-with-lease. Do NOT open a new PR — this reworks PR#$num." \
      --set-metadata merge_strategy=mr \
      --set-metadata existing_pr="$pr_url" \
      --set-metadata pr_url="$pr_url" \
      --set-metadata pr_number="$num" \
      --set-metadata source_anchor_bead="$id" \
      --set-metadata gc.routed_to="$pool" >/dev/null 2>&1 \
      || echo "reconcile-merged-prs: WARN rebase $FIX_BEAD for PR#$num created but not stamped; route it to $pool by hand" >&2
    # Parent-child keeps the dep graph honest and makes the rework visible under
    # the anchor. Best-effort: a failed edge must not strand the rebase, which is
    # already routed and independently linked by source_anchor_bead + pr_number.
    gc bd dep add "$FIX_BEAD" "$id" -t parent-child >/dev/null 2>&1 \
      || echo "reconcile-merged-prs: WARN could not link rebase $FIX_BEAD under anchor $id" >&2
    gc bd update "$id" \
      --set-metadata stale_base_head="${head_oid:-unknown}" \
      --set-metadata blocked_reason="PR#$num conflicts with base '$base' (stale base) at head ${head_oid:-unknown}; rebase $FIX_BEAD routed to $pool" >/dev/null 2>&1
    gc session wake "$pool" >/dev/null 2>&1 || true
    rebased=$((rebased + 1))
    echo "reconcile-merged-prs: $id — PR#$num conflicts with '$base' (stale base); filed rebase $FIX_BEAD routed to $pool"
    continue
  fi

  # --- PR open: DETECT-ONLY. The merge skill (merge-skill.sh) is the single
  # writer that lands a ready PR (validate -> merge -> record); the observer has
  # NO merge authority and never runs `gh pr merge`. A non-draft open PR is left
  # for the skill; a draft is skipped (drafts are retired). Either way the anchor
  # stays OPEN until the merged-close path above observes an authoritative merge.
  # The merge gate (the check_set markers, the open-rework-child hold,
  # mergeability) lives in the merge skill, not here — keeping the observer free
  # of merge authority.
  if [ "$state" = "OPEN" ]; then
    skipped=$((skipped + 1)); continue
  fi

  skipped=$((skipped + 1))
done <<< "$ROWS"

echo "reconcile-merged-prs: $closed closed, $abandoned abandoned ($escalated escalated), $retargeted retargeted, $rebased stale-base rebases routed, $skipped skipped"
exit 0
