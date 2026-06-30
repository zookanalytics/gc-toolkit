#!/usr/bin/env bash
# merge-skill — the single writer of merged-truth (docs/work-bead-state-machine.md
# "Merge: one writer of merged-truth"). This is the main-PR LANDING path: it
# replaces GitHub auto-merge (`gh pr merge --auto`) with an explicit merge the
# refinery performs itself. The refinery is the single writer — it does not
# delegate the landing to GitHub and then poll for the result.
#
# Runs on the refinery's idle wake, folded into mol-refinery-patrol's find-work
# loop, BEFORE the detect-only observer (reconcile-merged-prs.sh). For each OPEN
# gating anchor (the bead parked OPEN on a published PR, marked
# merge_result=pull_request by mol-refinery-patrol merge-push step 4) whose PR is
# open, non-draft, and whose full check-set is satisfied, it performs the three
# merge-skill actions IN ORDER:
#
#   validate -> merge -> record
#
#   validate: the PR's live base == the anchor's merged_target (no retarget),
#             the live head == signoff_head (the check-set's title/description-
#             current member), no open rework/review child references the PR (an
#             open child holds the merge — an anchor lands only when ALL its
#             children are closed), and GitHub reports the PR mergeable with its
#             required check-set green (mergeStateStatus=CLEAN folds CI +
#             approval + base-current + no-conflict into one signal).
#   merge:    `gh pr merge --squash` — an IMMEDIATE merge, NOT `--auto`. Branch
#             protection still gates the real merge server-side; a server-side
#             refusal leaves the anchor OPEN and is retried next idle pass.
#   record:   close the anchor "Merged to <target> at <sha>" and stamp
#             merge_result=merged + merged_sha — synchronous, because the skill
#             that merged is the one that knows it merged. If the record half
#             dies after a successful merge, the observer's merged-close path
#             (reconcile-merged-prs.sh) is the convergent backstop next pass.
#
# Single writer, on purpose: the merge is performed in exactly ONE place. Any
# anchor that is NOT open/ready — already merged, closed-unmerged, retargeted,
# draft — is LEFT untouched for the observer to record or escalate; the skill
# only ever MERGES, it never records a transition it did not perform. Keeping one
# authority over "did it land" means no second place for that state to drift.
#
# NOT set -e: best-effort, must never abort the patrol's idle loop. A merge is
# performed ONLY on an authoritative all-green validate; any tool error or a
# non-CLEAN state simply skips the anchor and retries next idle pass.
#
# Enumerated by BEAD, not by `gh pr list`: each anchor's pr_number resolves in
# this repo by construction, so there is no cross-repo PR-number collision.
set -uo pipefail

# gh is the only way to read PR state and perform the merge here. Without it
# there is nothing to do (the observer's merged-close path also no-ops without
# gh, so an un-merged anchor simply waits).
command -v gh >/dev/null 2>&1 || exit 0

# Open gating anchors in this rig's ledger.
ANCHORS=$(gc bd list --status=open \
  --metadata-field merge_result=pull_request \
  --limit=200 --json 2>/dev/null)
[ -n "$ANCHORS" ] && [ "$ANCHORS" != "[]" ] \
  || { echo "merge-skill: no gating anchors"; exit 0; }

# One compact JSON row per anchor. Built into a variable (not piped into the
# loop) so the loop runs in THIS shell and the counters below survive the
# pipe/subshell boundary.
ROWS=$(printf '%s' "$ANCHORS" \
  | jq -c '.[] | {id, pr: (.metadata.pr_number // ""), target: (.metadata.merged_target // ""), signoff: (.metadata.signoff_head // "")}' 2>/dev/null)
[ -n "$ROWS" ] || { echo "merge-skill: no gating anchors"; exit 0; }

merged=0; held=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  signoff_head=$(printf '%s' "$row" | jq -r '.signoff // empty')
  if [ -z "$id" ] || [ -z "$num" ]; then
    skipped=$((skipped + 1)); continue
  fi

  # Read live PR state. Only request fields supported by `gh pr view --json` on
  # supported gh versions — an unknown field errors and, with stderr suppressed,
  # empties PR_JSON, skipping the anchor forever. mergeStateStatus is the
  # composite gate (CLEAN = mergeable, required checks green, approved, base
  # current); the test's gh stub rejects unsupported fields to guard this.
  PR_JSON=$(gh pr view "$num" --json state,isDraft,baseRefName,headRefOid,mergeStateStatus,mergeable 2>/dev/null)
  if [ -z "$PR_JSON" ]; then
    echo "merge-skill: PR#$num view failed; skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
  is_draft=$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')
  base=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // ""')
  head_oid=$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // ""')
  merge_state=$(printf '%s' "$PR_JSON" | jq -r '.mergeStateStatus // ""')
  mergeable=$(printf '%s' "$PR_JSON" | jq -r '.mergeable // ""')

  # The merge skill acts ONLY on an OPEN, non-draft PR. Merged / closed-unmerged /
  # retargeted are the observer's to record or escalate; the skill never records
  # a transition it did not perform (single writer of merged-truth).
  [ "$state" = "OPEN" ] || { skipped=$((skipped + 1)); continue; }
  [ "$is_draft" != "true" ] || { skipped=$((skipped + 1)); continue; }

  # --- validate -----------------------------------------------------------
  # Retarget: live base must still match the anchor's recorded merged_target. A
  # mismatch means the PR was retargeted after publication; merging would land on
  # the WRONG branch. Hold — the observer (reconcile-merged-prs.sh) escalates the
  # retarget to a human; the skill must never merge across the mismatch.
  if [ -n "$target" ] && [ -n "$base" ] && [ "$target" != "$base" ]; then
    echo "merge-skill: PR#$num base '$base' != target '$target' (retargeted); merge held (anchor $id, observer escalates)"
    held=$((held + 1)); continue
  fi
  # Title/description-current: the signed-off head must still be the live head.
  # A mismatch (a post-signoff commit, or no signoff yet) means the current head
  # is unvalidated — hold so a fresh signoff round validates it first. This is
  # the check-set member that stops a stale approval carrying an out-of-date PR.
  if [ -z "$signoff_head" ] || [ "$signoff_head" != "$head_oid" ]; then
    echo "merge-skill: PR#$num head not signoff-validated (have '${signoff_head:-none}', live '$head_oid'); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # An open rework/review child holds the merge (docs/work-bead-state-machine.md:
  # an anchor lands only when ALL its children are closed). The anchor carries
  # merge_result; rework children and review beads do not — so excluding the
  # anchor's own id plus any merge_result-carrying bead leaves exactly the
  # in-flight rework/review set. --limit=0 (unbounded): the gate must see EVERY
  # referencing bead, not a page of them, or a child past the cap could let a PR
  # merge while rework is still open.
  inflight=$(gc bd list \
    --metadata-field pr_number="$num" \
    --status open,in_progress --limit=0 --json 2>/dev/null \
    | jq -r --arg anchor "$id" '[.[] | select(.id != $anchor) | select((.metadata.merge_result // "") == "")] | .[0].id // empty' 2>/dev/null)
  if [ -n "$inflight" ]; then
    echo "merge-skill: PR#$num has open rework/review bead $inflight; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # CI + approval + base-current + no-conflict: GitHub's composite
  # mergeStateStatus. CLEAN is the only state that is mergeable with every
  # required check green and approved. BLOCKED (missing approval/required check),
  # BEHIND (base moved), UNSTABLE (a required check pending/failing), DIRTY
  # (conflict), UNKNOWN (GitHub still computing) all hold the merge and retry.
  if [ "$merge_state" != "CLEAN" ]; then
    echo "merge-skill: PR#$num not mergeable yet (mergeStateStatus='${merge_state:-unknown}', mergeable='${mergeable:-?}'); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- merge (single writer; IMMEDIATE, not --auto) -----------------------
  # --squash matches the repo's squash-merge convention (commit "(#N)" tail).
  # The full check-set validated above; this is the terminal check. A server-side
  # refusal (branch protection, a race) leaves the anchor OPEN to retry next pass.
  MERGE_ERR=$(gh pr merge "$num" --squash 2>&1); merge_rc=$?
  if [ "$merge_rc" -ne 0 ]; then
    echo "merge-skill: PR#$num merge attempt failed (rc=$merge_rc); merge held (anchor $id): $MERGE_ERR" >&2
    held=$((held + 1)); continue
  fi

  # --- record (synchronous; observer is the convergent backstop) ----------
  # Re-read the squash commit GitHub produced. Close FIRST for convergence: if
  # the close fails the anchor stays open + merge_result=pull_request and the
  # observer's merged-close path closes it next pass. The merged_sha/merge_result
  # write is best-effort AFTER the close — the close reason already names the
  # merge commit, so a failed metadata write loses no authority, only a field.
  merge_oid=$(gh pr view "$num" --json mergeCommit 2>/dev/null | jq -r '.mergeCommit.oid // ""')
  short=$(printf '%.8s' "$merge_oid")
  if gc bd close "$id" --reason "Merged to $target at ${short:-merge}" >/dev/null 2>&1; then
    gc bd update "$id" \
      --set-metadata merge_result=merged \
      --set-metadata merged_sha="$merge_oid" \
      --unset-metadata rejection_reason >/dev/null 2>&1 || true
    merged=$((merged + 1))
    echo "merge-skill: merged + recorded $id — PR#$num squashed to $target at ${short:-?}"
  else
    echo "merge-skill: PR#$num MERGED but close failed for $id; observer records next pass" >&2
    skipped=$((skipped + 1))
  fi
done <<< "$ROWS"

echo "merge-skill: $merged merged, $held held, $skipped skipped"
exit 0
