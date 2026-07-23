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
#   PR open, gate STALE -> the check-set is green@<oid> at a head that has since
#                          MOVED (a direct push to the PR branch filed no rework
#                          bead), so merge-skill.sh holds forever (green@<oid> !=
#                          live head) with nothing re-dispatching the review. File
#                          a codex RE-REVIEW child at the live head, routed to the
#                          review pool; the anchor stays gating. One re-review per
#                          head (stale_gate_head); a poolless hold uses a distinct
#                          stale_gate_nopool_head so a pool configured later still
#                          dispatches. Symmetric with CONFLICTING.
#   PR open, draft      -> skip (drafts are retired, so the refinery creates no
#                          draft PR; a stray draft is left untouched).
#
#   Open PR, no live bead -> ANCHORLESS: the PR outlived its gating bead, so no
#                          automated path can see it at all. Report it and
#                          escalate once. DETECT + SURFACE ONLY — never merge,
#                          close, or reopen it; disposition is an operator call.
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
# Reconciled from BOTH sides. The per-anchor pass above walks BEAD -> PR: each
# anchor's pr_number resolves in this repo by construction, so there is no
# cross-repo PR-number collision. But that direction can only ever see PRs a live
# bead still names — so the anchorless pass at the end walks PR -> BEAD, and
# reports open PRs no live bead points at. Neither direction alone covers the
# state where a PR outlives its anchor.
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
# Pool the stale-GATE arm routes its codex RE-REVIEW children to (the codex pool,
# e.g. <rig>/<rig>.polecat-codex — the SAME source as check-set-heal.sh's
# --review-pool). Unset -> that arm cannot dispatch and leaves the anchor HELD
# (it never hand-stamps the gate green), retrying once a pool is configured.
REVIEW_POOL_DEFAULT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix-pool)
      FIX_POOL_DEFAULT="${2:-}"
      if [ $# -ge 2 ]; then shift 2; else shift; fi
      ;;
    --review-pool)
      REVIEW_POOL_DEFAULT="${2:-}"
      if [ $# -ge 2 ]; then shift 2; else shift; fi
      ;;
    *) shift ;;
  esac
done

# gh is the only way to read PR state here (like the codex gate). Without it
# there is nothing to do.
command -v gh >/dev/null 2>&1 || exit 0

# Statuses that still mean "a live bead owns this rework". `closed` is the ONLY
# status that releases a branch; every other one — `blocked` and `deferred` above
# all, which is exactly how an operator parks a runaway child — still owns it.
# The conflict arm's pre-dispatch probe used to ask for open,in_progress only, so
# neutralising a child by BLOCKING it (the standard operator move) made that child
# invisible here and the arm filed a second one on the very next pass, dispatching
# a concurrent force-push onto a branch a human had just frozen (tk-gajop).
#
# This is the COMPLEMENT of `closed` over `bd statuses`, enumerated rather than
# expressed as a negation because --status takes a positive list. Any status
# omitted here is a branch owner this probe cannot see, and an invisible owner is
# a second force-push: `hooked` (a child sitting on an agent's hook) and `pinned`
# are just as branch-owning as `blocked`. Re-derive this list if `bd statuses`
# ever grows a new non-closed status.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# Every non-closed bead whose metadata <field> equals <value>, as compact rows:
# the id, whether it is an anchor (merge_result set) rather than a rework child,
# and its rebase_hold marker. --limit=0 so the probe sees the whole set, not a
# page of it: a truncated page could hide the one held child that must veto.
#
# Returns NON-ZERO on a failed ledger read, which the caller must treat as "I
# cannot tell" and NOT as "nobody holds this branch" — the same ""-vs-"[]"
# distinction the anchorless scan fails closed on. A genuinely empty result is
# the literal "[]" and returns zero with no rows.
#
# The guards below answer four DIFFERENT questions, because the failure they
# share is silent: a probe that reports "no rows" when it actually failed reads
# as "nobody holds this branch" and dispatches the force-push. Non-empty stdout
# alone does NOT mean success — `gc ... --json` reports its own failures as a
# non-empty JSON *object* on stdout (`{"error": ...}`, exit 1), which survives an
# emptiness test, yields zero rows through the projection below, and so fails
# OPEN in the one direction that is unrecoverable.
#
# (1), (3) and (4) are each mutation-pinned by a shape only that guard rejects —
# see the (23) table in the test suite. Delete one and exactly one case goes red.
probe_beads() {
  local raw rc out
  raw=$(gc bd list --metadata-field "$1=$2" \
    --status "$LIVE_STATUSES" --limit=0 --json 2>/dev/null)
  rc=$?
  # (1) The command's own verdict, checked even when it wrote to stdout.
  [ "$rc" -eq 0 ] || return 1
  # (2) No output at all — a broken `gc bd list`, as distinct from "[]". Strictly
  #     an early-out: (3) also rejects empty input (`jq -e` exits non-zero on it),
  #     so no test pins this line alone. Kept because it states the ""-vs-"[]"
  #     contract this helper is built on, in the one place a reader looks for it,
  #     without spawning jq to say it.
  [ -n "$raw" ] || return 1
  # (3) The payload must be the ARRAY of beads we asked for. Rejects an error
  #     object that arrived with a ZERO exit status — and, more sharply, an object
  #     whose values are bead-shaped: `.[]` iterates those happily, so (4) sees a
  #     clean projection and only this guard can tell it was never a bead list.
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  # (4) The projection's own status. Captured into a variable first: emitted
  #     straight to stdout, jq's failure would be the function's LAST status and
  #     still be discarded by the callers' `probe=$(...)` capture.
  out=$(printf '%s' "$raw" \
    | jq -c '.[] | {id, mres: (.metadata.merge_result // ""), rhold: (.metadata.rebase_hold // "")}' 2>/dev/null) \
    || return 1
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

# Truthy in the operators' sense: set, and not one of the explicit "off" spellings.
# Mirrors merge-skill.sh's reading of merge_hold exactly, so a marker that holds a
# merge there cannot fail to hold a force-push here.
is_held() {
  case "${1:-}" in
    ""|false|False|FALSE|0|null) return 1 ;;
    *) return 0 ;;
  esac
}

# Route a stale-gate re-review to the codex pool and, ONLY once that route is
# confirmed to have PERSISTED, arm the one-per-head guard (stale_gate_head) on the
# anchor. The route write is what makes the review claimable — a codex polecat
# cannot heal the gate from an unrouted bead — so it is the step that must succeed
# before the head is recorded "dispatched". Stamping stale_gate_head after an
# UNVERIFIED best-effort route was the tk-3xy37 finding: a dropped route write left
# the review unrouted (inert) yet marked the head dispatched, so the one-per-head
# guard skipped it forever and the merge sat held behind a bead nothing could claim
# — the exact silent hold this arm exists to heal. Read gc.routed_to back; on a miss
# return 1 and stamp NOTHING, so a later pass re-enters the arm (guard unstamped) and
# repairs the same bead via the in-flight probe. Returns 0 armed, 1 not persisted.
arm_stale_gate() {
  local bead="$1" anchor="$2" head="$3" stale="$4" pool="$5" num="$6" got
  # An empty pool can never make a bead claimable; never "arm" on one (the callers
  # already gate on a non-empty pool, but fail closed here too).
  [ -n "$pool" ] || return 1
  gc bd update "$bead" --set-metadata gc.routed_to="$pool" >/dev/null 2>&1
  got=$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.routed_to"] // empty' 2>/dev/null)
  [ "$got" = "$pool" ] || return 1
  gc bd update "$anchor" \
    --set-metadata stale_gate_head="${head:-unknown}" \
    --set-metadata blocked_reason="PR#$num check.codex stale (green@$stale, live head ${head:-?}); re-review $bead routed to $pool" >/dev/null 2>&1
  gc session wake "$pool" >/dev/null 2>&1 || true
  return 0
}

# Open gating anchors in this rig's ledger.
ANCHORS=$(gc bd list --status=open \
  --metadata-field merge_result=pull_request \
  --limit=200 --json 2>/dev/null)

# One compact JSON row per anchor. Built into a variable (not piped into the
# loop) so the loop runs in THIS shell and the counters below survive the
# pipe/subshell boundary.
ROWS=""
if [ -n "$ANCHORS" ] && [ "$ANCHORS" != "[]" ]; then
  ROWS=$(printf '%s' "$ANCHORS" \
    | jq -c '.[] | {id, pr: (.metadata.pr_number // ""), target: (.metadata.merged_target // ""), checkset: (.metadata.check_set // ""), branch: (.metadata.branch // ""), fixpool: (.metadata.fix_target_pool // ""), staled: (.metadata.stale_base_head // ""), stalegate: (.metadata.stale_gate_head // ""), stalegatenopool: (.metadata.stale_gate_nopool_head // ""), codexmark: (.metadata["check.codex"] // ""), hold: (.metadata.merge_hold // ""), rhold: (.metadata.rebase_hold // "")}' 2>/dev/null)
fi
# No anchors is NOT an early exit: the anchorless pass below walks PR -> BEAD and
# is at its MOST relevant here (zero live anchors + open PRs is precisely the
# stranded state it exists to surface). Returning early on an empty gating set —
# as this did before the anchorless arm — would blind the pass exactly when it
# matters. Only the per-anchor loop is skipped.
[ -n "$ROWS" ] || echo "reconcile-merged-prs: no gating anchors"

closed=0; abandoned=0; escalated=0; retargeted=0; rebased=0; rebase_held=0; regated=0; gate_held=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  hold=$(printf '%s' "$row" | jq -r '.hold // empty')
  rhold=$(printf '%s' "$row" | jq -r '.rhold // empty')
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

    # --- Operator gates, checked before anything is dispatched. ---------------
    # This arm is the most dangerous in the file: it does not merge, it DISPATCHES
    # A FORCE-PUSH (`--force-with-lease` onto the PR's head branch) to a live pool,
    # claimable within minutes. So it must honor every marker that would hold the
    # far gentler merge — anything less and the two scripts disagree about whether
    # an anchor is actionable, which is exactly what happened: merge-skill.sh
    # correctly refused to merge a merge_hold anchor, and seconds later, in the
    # SAME reconcile pass, this arm used that same anchor to dispatch a rebase
    # (tk-gajop).
    #
    # merge_hold is the operator's "do not land this yet"; rebase_hold is the
    # narrower "do not rebase/force-push this branch". Either one vetoes: a hold
    # on landing is necessarily a hold on rewriting the branch underneath it.
    if is_held "$hold"; then
      echo "reconcile-merged-prs: $id — PR#$num conflicted (stale base) but merge_hold set (operator gate); no rebase dispatched"
      rebase_held=$((rebase_held + 1)); continue
    fi
    if is_held "$rhold"; then
      echo "reconcile-merged-prs: $id — PR#$num conflicted (stale base) but rebase_hold set (operator gate); no rebase dispatched"
      rebase_held=$((rebase_held + 1)); continue
    fi

    # The head this pass would route. An unreadable head degrades to the literal
    # "unknown" rather than to "" — an empty marker would never match on the next
    # pass and the arm would re-file on every wake.
    head_key="${head_oid:-unknown}"
    # Already routed at this exact head: nothing changed, do not re-file.
    if [ "$prior" = "$head_key" ]; then
      skipped=$((skipped + 1)); continue
    fi

    # The branch a rebase child would rewrite. Resolved HERE, before the probes,
    # because the branch — not the anchor and not the PR — is what a force-push
    # actually endangers, so it is the right key to ask "is anyone already on
    # this?". `head_ref` is the PR's live head branch and is authoritative over
    # the anchor's recorded branch; the emptiness check stays below with the rest
    # of the filing preconditions.
    fix_branch="$head_ref"
    [ -n "$fix_branch" ] || fix_branch=$(printf '%s' "$row" | jq -r '.branch // empty')

    # --- Who else is already on this branch? ----------------------------------
    # Probe BOTH dimensions and union them; neither subsumes the other:
    #   pr_number — a rework child of THIS PR, including one filed by a different
    #               anchor. The stale_base_head marker above cannot catch that: it
    #               is keyed per-ANCHOR, so a PR carrying two anchors (the tk-ynz4b
    #               double-anchor trap) files one child per anchor, each blind to
    #               the other.
    #   branch    — anything naming the same branch under a different PR number,
    #               which is the unit a force-push actually collides on.
    # FAIL CLOSED on an unreadable probe. A failed ledger read is
    # indistinguishable from "no bead holds this branch", and reading it the
    # optimistic way dispatches a force-push precisely when we cannot verify a
    # freeze — the worst possible time. A deferred rebase costs one pass; a
    # force-push onto a branch a keeper had frozen is not recoverable by retry.
    if ! probe=$(probe_beads pr_number "$num"); then
      echo "reconcile-merged-prs: $id — PR#$num conflicted but the rework probe failed; no rebase dispatched (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if [ -n "$fix_branch" ]; then
      if ! branch_probe=$(probe_beads branch "$fix_branch"); then
        echo "reconcile-merged-prs: $id — PR#$num conflicted but the branch probe on '$fix_branch' failed; no rebase dispatched (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      probe=$(printf '%s\n%s' "$probe" "$branch_probe")
    fi

    # An operator freeze ANYWHERE on this branch — on an existing child, or on a
    # sibling bead naming it — vetoes the dispatch. rebase_hold=true is precisely
    # the marker a keeper sets on a runaway rebase child to stop it being redone;
    # re-dispatching past it re-creates the race the keeper just contained.
    frozen=$(printf '%s\n' "$probe" \
      | jq -r 'select((.rhold // "") as $h | ($h | ascii_downcase) as $l
               | $h != "" and $l != "false" and $l != "0" and $l != "null") | .id' 2>/dev/null \
      | head -1)
    if [ -n "$frozen" ]; then
      echo "reconcile-merged-prs: $id — PR#$num conflicted (stale base) but $frozen holds branch '${fix_branch:-?}' with rebase_hold (operator gate); no rebase dispatched"
      rebase_held=$((rebase_held + 1)); continue
    fi

    # Someone is already reworking this PR or this branch (a signoff
    # REQUEST_CHANGES child, an operator-parked one, or our own from an earlier
    # head). A second rework child would race it — two live children on one branch
    # is a concurrent force-push hazard on its own, independent of any freeze.
    # Beads carrying merge_result are anchors, not rework children, and are
    # excluded; the anchor under consideration is excluded by id.
    inflight=$(printf '%s\n' "$probe" \
      | jq -r --arg anchor "$id" 'select(.id != $anchor) | select(.mres == "") | .id' 2>/dev/null \
      | head -1)
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
    # `fix_branch` (resolved above, before the probes) is what the rework must
    # resume — existing_pr makes the patrol rework THAT PR rather than open a
    # second one. With no branch or no URL the child would have nothing to check
    # out: skip rather than file a dud.
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

  # --- PR open, STALE GATE: check-set green at a head that MOVED. -----------
  # The symmetric twin of the CONFLICTING arm above. A gating anchor whose codex
  # marker went green (check.codex=green@<oid>) and whose PR head then advanced
  # PAST <oid> through a path that filed NO rework bead — a direct push to the PR
  # branch, an operator fixup — sits in a SILENT indefinite hold: merge-skill.sh
  # correctly refuses (its stale-head guard: green@<oid> != live head), but before
  # this arm NOTHING re-dispatched the review, so the anchor was indistinguishable
  # from a healthy PR awaiting approval (WS4 GAP1, su-PR#31 class). check-set-heal.sh
  # heals the DISJOINT empty-check_set case and EXPLICITLY punts on stale-green
  # ("re-gates through the normal rework path") — the exact assumption this bug
  # disproves for the no-rework-bead path, so the two passes are complementary.
  #
  # The remedy is ALWAYS a real review at the live head, NEVER a hand-stamped
  # check.codex=green: stamping green here would certify an UNREVIEWED commit (the
  # tk-4na1b failure mode with a human author). So this files a codex RE-REVIEW
  # CHILD at the live head, routed to the review pool, anchored to the gating anchor
  # (one anchor per PR); the child's COMMENT signoff re-stamps
  # check.codex=green@<live-head> and the merge proceeds. The anchor KEEPS
  # merge_result=pull_request — like the CONFLICTING arm, unlike retarget/abandon —
  # because the PR still exists and still gates; the open review child holds the
  # merge meanwhile, and on hand-back the merge-push one-anchor-per-PR arm closes it
  # as landed-on-branch rather than minting a second anchor.
  #
  # Bound: ONE re-review per head, via stale_gate_head=<head at detection> (the
  # exact shape of stale_base_head). Re-arms only when the head moves again. Between
  # dispatch and signoff the open review child ALSO holds it (the in-flight probe),
  # so the marker is the belt to that suspenders — it still bounds the arm if a
  # review closes without re-stamping (e.g. REQUEST_CHANGES routes a rework instead).
  # A poolless hold uses a DISTINCT marker (stale_gate_nopool_head): stale_gate_head
  # would say "dispatched here" and suppress the dispatch forever once a review pool
  # is configured, so a no-pool pass must not stamp it (tk-v2b0k finding #1). The
  # no-pool marker only short-circuits the busy-loop while STILL poolless.
  #
  # Only `codex` is dispatchable (the sole check-set member this city can raise —
  # mirrors check-set-heal.sh); a non-codex stale gate is left to whatever raises it.
  # Kept self-contained so it ports if this self-heal is later re-housed inside a
  # convergence loop (the tk-zgse0 WS4 direction).
  if [ "$state" = "OPEN" ] && [ "$is_draft" != "true" ]; then
    checkset=$(printf '%s' "$row" | jq -r '.checkset // empty')
    codexmark=$(printf '%s' "$row" | jq -r '.codexmark // empty')
    stalegate=$(printf '%s' "$row" | jq -r '.stalegate // empty')
    # Separate from stalegate (stale_gate_head): this marks a head we HELD purely
    # for lack of a review pool — no review was dispatched. Kept distinct so a pool
    # configured later can still dispatch at that head instead of being suppressed
    # by the "already dispatched here" guard below (tk-v2b0k finding #1).
    stalegate_nopool=$(printf '%s' "$row" | jq -r '.stalegatenopool // empty')
    # fix_target_pool is where a REQUEST_CHANGES rework off this re-review routes.
    # Prefer the anchor's own override; fall back to the patrol's --fix-pool default.
    # Normal gating anchors carry NO fix_target_pool of their own (only the review
    # bead is stamped with one, by the regular codex dispatch) — so without this
    # fallback the re-review child is filed with an EMPTY fix pool, and its signoff
    # completion path (template-fragments/polecat-non-impl-done.template.md, which
    # gates every action on a non-empty fix_target_pool) can neither stamp
    # check.codex on COMMENT nor file a rework child on REQUEST_CHANGES. The review
    # then closes while the anchor keeps the stale check.codex=green@<old> +
    # stale_gate_head, re-creating the exact indefinite hold this arm exists to heal.
    # Symmetric with the CONFLICTING arm's fallback (`[ -n "$pool" ] || pool="$FIX_POOL_DEFAULT"`).
    fixpool=$(printf '%s' "$row" | jq -r '.fixpool // empty')
    [ -n "$fixpool" ] || fixpool="$FIX_POOL_DEFAULT"

    # `codex` must be a declared check-set member (trimmed, whole-token — the same
    # split merge-skill.sh / check-set-heal.sh use, so a spaced "lint, codex" is
    # recognized identically). none/off is not a member, so a gateless rig never
    # enters this arm.
    is_codex_member=""
    printf '%s' "$checkset" | tr ',' '\n' \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qxF codex && is_codex_member=1

    # Stale-green? The marker must be green at a NON-EMPTY oid that is NOT the live
    # head. An empty/absent marker is "never reviewed" (check-set-heal's / the normal
    # dispatch's job, not this bug); green@<live-head> is current (merges normally).
    # Only green@<other-oid> is the head-moved stall this arm heals.
    stale_oid=""
    case "$codexmark" in
      green@*)
        oid="${codexmark#green@}"
        if [ -n "$oid" ] && [ -n "$head_oid" ] && [ "$oid" != "$head_oid" ]; then
          stale_oid="$oid"
        fi ;;
    esac

    if [ -n "$is_codex_member" ] && [ -n "$stale_oid" ]; then
      # Operator hold: merge_hold is "do not land this yet". Re-dispatching a review
      # is pipeline work toward landing, so honor the same gate the merge honors
      # (symmetric with the CONFLICTING arm honoring it before a rebase). When the
      # operator releases the hold, the next pass heals the gate.
      if is_held "$hold"; then
        echo "reconcile-merged-prs: $id — PR#$num check.codex stale (green@$stale_oid != live head ${head_oid:-?}) but merge_hold set (operator gate); no re-review dispatched"
        gate_held=$((gate_held + 1)); continue
      fi
      # One re-review per head: already routed at this exact head -> nothing new.
      gate_key="${head_oid:-unknown}"
      if [ "$stalegate" = "$gate_key" ]; then
        skipped=$((skipped + 1)); continue
      fi
      # Held at this head ONLY for lack of a review pool, and STILL none configured:
      # the hold stands, so short-circuit before the in-flight probe (mirrors the
      # guard above). This reads stale_gate_nopool_head, NOT stale_gate_head — a pool
      # configured since (REVIEW_POOL_DEFAULT now non-empty) fails the `-z` test here,
      # so it falls through and dispatches, recovering the hold at the same head
      # (tk-v2b0k finding #1: a no-pool pass must not suppress a later configured
      # dispatch). The two markers are kept separate for exactly this transition.
      if [ -z "$REVIEW_POOL_DEFAULT" ] && [ -n "$stalegate_nopool" ] \
           && [ "$stalegate_nopool" = "$gate_key" ]; then
        gate_held=$((gate_held + 1)); continue
      fi
      # An open rework/review child already re-raises the gate — the SAME in-flight
      # set merge-skill.sh holds the merge on (pr_number, non-anchor). FAIL CLOSED
      # on an unreadable probe: a twin review is a lesser harm than the CONFLICTING
      # arm's force-push, but the guard errs to "someone's on it" the same way.
      if ! gate_probe=$(probe_beads pr_number "$num"); then
        echo "reconcile-merged-prs: $id — PR#$num check.codex stale but the in-flight probe failed; no re-review dispatched (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      inflight=$(printf '%s\n' "$gate_probe" \
        | jq -r --arg anchor "$id" 'select(.id != $anchor) | select(.mres == "") | .id' 2>/dev/null \
        | head -1)
      if [ -n "$inflight" ]; then
        # Normally a healthy in-flight review/rework already re-raises the gate, so
        # skip to avoid a twin (test 26). BUT a re-review left UNROUTED by a failed
        # route write (arm_stale_gate below) is inert — unclaimable by the codex pool
        # — while it still trips this probe, so the gate would sit held forever behind
        # a bead nothing can action. If the in-flight bead is exactly that (a codex
        # review anchored to THIS anchor with no gc.routed_to) and a review pool is
        # configured, re-route it (repair) rather than skip: heal the head an earlier
        # pass failed to arm. Anything else — routed, a rework child, or anchored
        # elsewhere — is left untouched, so twin-avoidance is unchanged for it.
        if_json=$(gc bd show "$inflight" --json 2>/dev/null)
        if_kind=$(printf '%s' "$if_json" | jq -r '.[0].metadata.task_kind // ""' 2>/dev/null)
        if_anchor=$(printf '%s' "$if_json" | jq -r '.[0].metadata.anchor_bead // ""' 2>/dev/null)
        if_routed=$(printf '%s' "$if_json" | jq -r '.[0].metadata["gc.routed_to"] // ""' 2>/dev/null)
        if [ -n "$REVIEW_POOL_DEFAULT" ] && [ "$if_kind" = "review" ] \
             && [ "$if_anchor" = "$id" ] && [ -z "$if_routed" ]; then
          if arm_stale_gate "$inflight" "$id" "$head_oid" "$stale_oid" "$REVIEW_POOL_DEFAULT" "$num"; then
            regated=$((regated + 1))
            echo "reconcile-merged-prs: $id — PR#$num re-review $inflight was left unrouted by an earlier failed route write; re-routed to $REVIEW_POOL_DEFAULT (stale-gate repair)"
          else
            echo "reconcile-merged-prs: $id — PR#$num re-review $inflight repair route still not persisting; retry next pass" >&2
            skipped=$((skipped + 1))
          fi
          continue
        fi
        skipped=$((skipped + 1)); continue
      fi
      if [ -z "$REVIEW_POOL_DEFAULT" ]; then
        # No review pool: cannot dispatch. Do NOT hand-stamp the gate green (that
        # certifies an unreviewed commit). Record a SEPARATE no-pool hold marker —
        # NOT stale_gate_head. stale_gate_head means "a review WAS dispatched at this
        # head" and the guard above skips it forever; stamping it here would suppress
        # the dispatch even after a pool is configured, re-creating the exact
        # indefinite hold this arm heals (tk-v2b0k finding #1). stale_gate_nopool_head
        # bounds the busy-loop via the short-circuit above WITHOUT blocking the later
        # configured dispatch. Surface it and leave the anchor gating — the merge
        # stays HELD on the stale marker, the safe side.
        gc bd update "$id" \
          --set-metadata stale_gate_nopool_head="${head_oid:-unknown}" \
          --set-metadata blocked_reason="PR#$num check.codex green@$stale_oid is stale (live head ${head_oid:-?}); no review pool configured to re-dispatch the signoff" >/dev/null 2>&1
        echo "reconcile-merged-prs: $id — PR#$num check.codex stale (green@$stale_oid, live head ${head_oid:-?}) but no --review-pool; cannot re-dispatch (merge stays held)" >&2
        gate_held=$((gate_held + 1)); continue
      fi
      # Need a PR url to point the review at (num is non-empty by the loop head).
      if [ -z "$pr_url" ]; then
        echo "reconcile-merged-prs: $id — PR#$num check.codex stale but PR url unreadable; skip (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      REVIEW_BEAD=$(gc bd create "Review PR#$num: re-review at live head (stale-gate self-heal)" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
      if [ -z "$REVIEW_BEAD" ]; then
        echo "reconcile-merged-prs: $id could not file re-review bead for PR#$num; retry next pass" >&2
        skipped=$((skipped + 1)); continue
      fi
      # Mirror the merge-push / check-set-heal.sh review shape so the codex signoff's
      # done-sequence finds exactly the fields it expects (task_kind=review,
      # check_name, pr_url/pr_number for the post-open review, anchor_bead the durable
      # link). fix_target_pool (resolved above: the anchor's own override, else the
      # patrol's --fix-pool default) is where a REQUEST_CHANGES rework routes — the
      # FIX pool, not the review pool. gc.routed_to is written LAST — it is what makes
      # the bead claimable, and a codex polecat that claimed a half-stamped review
      # would have no anchor_bead to stamp the gate on.
      gc bd update "$REVIEW_BEAD" \
        --set-metadata task_kind=review \
        --set-metadata check_name=codex \
        --set-metadata pr_url="$pr_url" \
        --set-metadata pr_number="$num" \
        --set-metadata anchor_bead="$id" \
        --set-metadata review_note="Stale-gate self-heal: check.codex was green@$stale_oid; the PR head moved to ${head_oid:-?} with no rework bead filed. Re-review the live head." >/dev/null 2>&1
      [ -n "$fixpool" ] && gc bd update "$REVIEW_BEAD" --set-metadata fix_target_pool="$fixpool" >/dev/null 2>&1
      # The review BLOCKS the anchor (anchor_bead is the durable fallback the signoff
      # resolves through when the edge is missing). Best-effort.
      gc bd dep "$REVIEW_BEAD" --blocks "$id" >/dev/null 2>&1 \
        || echo "reconcile-merged-prs: WARN could not attach re-review $REVIEW_BEAD as a gate-dep of $id (anchor_bead fallback persists the link)" >&2
      # Verify the anchor link persisted BEFORE routing: without it the review cannot
      # stamp check.codex on this anchor and the armed gate never clears. Unrouted, the
      # bead is inert and the next pass's in-flight probe reuses it rather than a twin.
      RECORDED_ANCHOR=$(gc bd show "$REVIEW_BEAD" --json 2>/dev/null | jq -r '.[0].metadata.anchor_bead // empty')
      if [ "$RECORDED_ANCHOR" != "$id" ]; then
        echo "reconcile-merged-prs: WARN re-review $REVIEW_BEAD did not record anchor_bead=$id; leaving unrouted (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      # Route the review and arm the one-per-head guard ONLY if the route PERSISTS.
      # A dropped route write must NOT stamp stale_gate_head: that would mark the head
      # "dispatched" while the review sits unrouted and unclaimable, and the
      # one-per-head guard would then skip it forever — the tk-3xy37 finding. On a
      # miss, leave the guard unstamped and skip; the next pass re-enters (guard
      # unstamped) and the in-flight probe above re-routes this same bead.
      if arm_stale_gate "$REVIEW_BEAD" "$id" "$head_oid" "$stale_oid" "$REVIEW_POOL_DEFAULT" "$num"; then
        regated=$((regated + 1))
        echo "reconcile-merged-prs: $id — PR#$num check.codex green@$stale_oid stale (live head ${head_oid:-?}); filed re-review $REVIEW_BEAD routed to $REVIEW_POOL_DEFAULT"
      else
        echo "reconcile-merged-prs: WARN re-review $REVIEW_BEAD route write did not persist gc.routed_to=$REVIEW_POOL_DEFAULT; leaving un-armed (retry/repair next pass)" >&2
        skipped=$((skipped + 1))
      fi
      continue
    fi
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

# --- Anchorless open PRs: the PR outlived its gating bead. -------------------
# Everything above enumerates BEAD -> PR, so it can only ever see a PR some live
# bead still names. A PR whose bead is CLOSED (or gone) is invisible to EVERY
# automated path — not this pass, not the merge skill, not the patrol — because
# all of them start from the bead. Nothing reports it, so it does not read as
# broken; it reads as absent.
#
# Not hypothetical: the pre-#163 close-on-publish model closed the work bead at
# PR-CREATION rather than on land, and the PRs it stranded sat untouched for
# weeks — surfaced only when a human cross-checked `gh pr list` against the
# ledger by hand. The close-on-land model no longer creates that state, but the
# blind spot outlives its cause: any path where a PR outlives its anchor (an
# operator closing a bead early, a force-rewrite, a deleted bead) re-enters it.
#
# So close the loop from the other side: walk PR -> BEAD and report open PRs no
# live bead points at. DETECT + SURFACE ONLY — never merge, close, or reopen
# one. Disposition (land it, close it, rework it) needs context this pass does
# not have and stays an operator call; see docs/work-bead-state-machine.md.
anchorless=0
PR_LIST=$(gh pr list --state open --limit 200 \
  --json number,url,isDraft,headRefName,baseRefName 2>/dev/null)
if [ -z "$PR_LIST" ]; then
  # Distinct from "[]" (a real, empty result): empty output means the call
  # failed. Skip rather than guess — retried next pass.
  echo "reconcile-merged-prs: open-PR enumeration failed; anchorless scan skipped (retry next pass)" >&2
elif [ "$PR_LIST" != "[]" ]; then
  # Every PR number named by a LIVE bead — gating anchors, rework children, and
  # review beads alike. ONE ledger query rather than one per PR: a PR named by
  # ANY live bead is tracked by something and is not a finding, whether or not
  # that bead is the anchor.
  LIVE=$(gc bd list --status open,in_progress,blocked --limit=0 --json 2>/dev/null)
  if [ -z "$LIVE" ]; then
    # FAIL CLOSED. Empty output here is indistinguishable from a failed ledger
    # read, and treating it as "nothing is tracked" would flag every open PR at
    # once and escalate a storm. A genuinely empty ledger returns "[]", a
    # different string, and does fall through to the scan below.
    echo "reconcile-merged-prs: live-bead read failed; anchorless scan skipped (retry next pass)" >&2
  else
    TRACKED=$(printf '%s' "$LIVE" \
      | jq -r '[.[] | .metadata.pr_number // empty | tostring] | unique | .[]' 2>/dev/null)
    PR_ROWS=$(printf '%s' "$PR_LIST" \
      | jq -r '.[] | [(.number|tostring), .url, (.isDraft|tostring), .headRefName, .baseRefName] | join("|")' 2>/dev/null)
    while IFS='|' read -r pnum purl pdraft phead pbase; do
      [ -n "${pnum:-}" ] || continue
      # Tracked by a live bead -> not a finding. Exact-match so PR#7 is never
      # satisfied by PR#77.
      printf '%s\n' "$TRACKED" | grep -qxF "$pnum" && continue

      # Resolve the bead that DID name this PR, if one still exists. A closed one
      # is the high-confidence signature (a Gas City PR whose anchor closed out
      # from under it) AND the only durable place to bound the escalation.
      # --limit=0 (all), not a page: the pick below is "oldest carrying
      # merge_result", so a truncated page could hide the very bead we want.
      # The pr_number filter keeps the result to a handful either way.
      dead=$(gc bd list --status closed --metadata-field pr_number="$pnum" \
               --limit=0 --json 2>/dev/null)
      # Several closed beads routinely name one PR — the anchor that opened it,
      # its review beads, and any "address findings" rework children. Pick the
      # bead that OPENED the PR, since that is the one an operator reopens to
      # re-engage it: filter to those carrying merge_result (the gating-anchor
      # signature, which review beads lack), then take the OLDEST, because the
      # rework children that share that marker were all created later. Fall back
      # to the oldest bead of any kind if none carries the marker.
      dead_row=$(printf '%s' "$dead" | jq -c '
        (map(select((.metadata.merge_result // "") != "")) | sort_by(.created_at // "")) as $anchors
        | (if ($anchors | length) > 0 then $anchors else sort_by(.created_at // "") end)
        | .[0] // empty' 2>/dev/null)
      dead_id=$(printf '%s' "$dead_row" | jq -r '.id // empty' 2>/dev/null)
      dead_flag=$(printf '%s' "$dead_row" | jq -r '.metadata.anchorless_flagged // empty' 2>/dev/null)
      # Every closed bead naming this PR, oldest first. The disposition may touch
      # more than the one we mark, so the operator gets the whole set, not just
      # our pick.
      dead_all=$(printf '%s' "$dead" \
        | jq -r '[sort_by(.created_at // "") | .[].id] | join(", ")' 2>/dev/null)
      anchorless=$((anchorless + 1))
      draft_note=""
      [ "$pdraft" = "true" ] && draft_note=" (draft)"

      if [ -z "$dead_id" ]; then
        # No bead names this PR in any state. It may never have been Gas City's
        # (a human or bot opened it), so this is reported but NOT escalated:
        # there is nothing durable to mark, and an unbounded mail would repeat
        # every wake. The log line is the surface.
        echo "reconcile-merged-prs: ANCHORLESS PR#$pnum$draft_note ($phead -> $pbase) — no bead in any state references it; not tracked by any automated path"
        continue
      fi
      if [ "$dead_flag" = "$pnum" ]; then
        # Already escalated for this PR. Keep reporting it (it is still stranded)
        # but do not re-mail.
        echo "reconcile-merged-prs: ANCHORLESS PR#$pnum$draft_note ($phead -> $pbase) — anchor $dead_id is CLOSED; already escalated, awaiting operator disposition"
        continue
      fi
      # Stamp FIRST, mail second — the same close-FIRST convergence the merged
      # path uses. If the stamp fails we have no bound, so we must NOT mail:
      # report loudly and retry next pass. A delayed escalation is recoverable;
      # a mail storm is not.
      if gc bd update "$dead_id" --set-metadata anchorless_flagged="$pnum" >/dev/null 2>&1; then
        if gc mail send mayor/ -s "ESCALATION: anchorless open PR#$pnum (bead $dead_id is closed)" \
             -m "PR#$pnum is OPEN but its bead $dead_id is CLOSED, so no automated path can see it.
Every close-on-land path — this reconciler, the merge skill, the refinery patrol —
enumerates from the BEAD, so a closed bead with an open PR is invisible to all of
them: it will never be landed, rejected, or escalated on its own.

  PR:     $purl$draft_note
  Branch: ${phead:-?} -> ${pbase:-?}
  Bead:   $dead_id (closed) — the bead that opened the PR
  All:    ${dead_all:-$dead_id} (every closed bead naming PR#$pnum, oldest first)

The refinery took NO action: disposition is an operator call, not a merge-processor
one. Decide: LAND it (approve on GitHub, then reopen the bead as a gating anchor —
status=open, merge_result=pull_request, check_set/check.* at the live head — so the
merge skill lands and closes it), CLOSE the PR as abandoned (the bead is already
closed; nothing else to do), or REWORK it (reopen the bead and route it to a
polecat). This pass reports it once and will not act on it." >/dev/null 2>&1; then
          escalated=$((escalated + 1))
        fi
        echo "reconcile-merged-prs: ANCHORLESS PR#$pnum$draft_note ($phead -> $pbase) — anchor $dead_id is CLOSED; routed to operator + escalated"
      else
        echo "reconcile-merged-prs: ANCHORLESS PR#$pnum$draft_note — could not mark bead $dead_id; not escalating unbounded (retry next pass)" >&2
      fi
    done <<< "$PR_ROWS"
  fi
fi

echo "reconcile-merged-prs: $closed closed, $abandoned abandoned ($escalated escalated), $retargeted retargeted, $rebased stale-base rebases routed, $rebase_held rebases held, $regated stale-gate re-reviews routed, $gate_held stale-gate re-reviews held, $anchorless anchorless open PRs, $skipped skipped"
exit 0
