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
#   validate: the PR is claimed by exactly ONE open anchor (a second anchor
#             would let the weakest check_set decide the merge — tk-ynz4b),
#             the PR's live base == the anchor's merged_target (no retarget),
#             every gate the anchor declares in check_set is green AT THE LIVE
#             HEAD (per-gate marker check.<name>=green@<head>, so a stale approval
#             or a post-review commit re-gates instead of merging), no open
#             rework/review child references the PR (an open child holds the
#             merge — an anchor lands only when ALL its children are closed), and
#             GitHub reports the PR mergeable with its required check-set green
#             (mergeStateStatus=CLEAN folds CI + approval + base-current +
#             no-conflict into one signal).
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
  | jq -c '.[] | {id, pr: (.metadata.pr_number // ""), target: (.metadata.merged_target // ""), checkset: (.metadata.check_set // ""), hold: (.metadata.merge_hold // ""), meta: (.metadata // {})}' 2>/dev/null)
[ -n "$ROWS" ] || { echo "merge-skill: no gating anchors"; exit 0; }

# One-anchor-per-PR guard (tk-ynz4b): the loop below validates each anchor
# INDEPENDENTLY, so a PR claimed by more than one open anchor is gated by its
# WEAKEST anchor — e.g. a rework child that leaked into the anchor class with no
# check_set would land the PR while the real anchor's codex gate is red, and
# (carrying merge_result) that same leaked bead is invisible to the in-flight
# rework hold below. One gating anchor per PR is the design intent
# (docs/work-bead-state-machine.md); the refinery no longer mints a second
# anchor on rework hand-back (mol-refinery-patrol.toml one-anchor-per-pr arm),
# so a duplicate here is legacy/out-of-band state. Precompute the pr_numbers
# claimed by >1 open anchor; EVERY anchor of such a PR is held in validate.
DUP_PRS=$(printf '%s\n' "$ROWS" \
  | jq -rs '[.[] | .pr | select(. != "")] | group_by(.) | map(select(length > 1) | .[0]) | .[]' 2>/dev/null)

merged=0; held=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  hold=$(printf '%s' "$row" | jq -r '.hold // empty')
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
  # Operator hold: metadata.merge_hold on the anchor is an explicit operator gate
  # ("do not land yet — awaiting manual sign-off"). When truthy the skill must NOT
  # merge no matter how green the PR looks. Checked FIRST, before every PR-state
  # gate: it is the cheapest gate (metadata already in hand) and the highest
  # priority (an intentional operator block, independent of PR state), so a held
  # anchor short-circuits before the referencing-bead `gc bd list`. Before this
  # gate the hold was honored only INCIDENTALLY — when the PR happened to be
  # non-CLEAN (BLOCKED/BEHIND) — so a fully-CLEAN held PR would squash-merge to the
  # target with no operator signal. Truthy = set and not empty/false/0 (operators
  # set merge_hold=true); an unset or explicitly-false marker does not hold.
  case "$hold" in
    ""|false|False|FALSE|0|null) : ;;
    *)
      echo "merge-skill: PR#$num merge_hold set (operator gate); merge held for operator (anchor $id)"
      held=$((held + 1)); continue ;;
  esac
  # One-anchor-per-PR (tk-ynz4b): this PR is claimed by multiple open anchors,
  # so no single anchor's check_set can be trusted to speak for the PR — the
  # weakest would decide the merge. Hold every anchor of the PR; the hold
  # releases on a later pass once exactly one open anchor remains (close/demote
  # the duplicate — usually the rework-minted one — to repair the taxonomy).
  if [ -n "$DUP_PRS" ] && printf '%s\n' "$DUP_PRS" | grep -qxF "$num"; then
    echo "merge-skill: PR#$num has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor $id) — close/demote the duplicate anchor to release (tk-ynz4b)"
    held=$((held + 1)); continue
  fi
  # Retarget: live base must still match the anchor's recorded merged_target. A
  # mismatch means the PR was retargeted after publication; merging would land on
  # the WRONG branch. Hold — the observer (reconcile-merged-prs.sh) escalates the
  # retarget to a human; the skill must never merge across the mismatch.
  if [ -n "$target" ] && [ -n "$base" ] && [ "$target" != "$base" ]; then
    echo "merge-skill: PR#$num base '$base' != target '$target' (retargeted); merge held (anchor $id, observer escalates)"
    held=$((held + 1)); continue
  fi
  # Check-set: every gate the anchor declares in check_set must be green AT THE
  # LIVE HEAD, recorded as a per-gate marker check.<name>=green@<head_oid>. The
  # green@<sha> form folds two checks the old single signoff_head conflated —
  # "this gate passed" and "title/description current at this commit" — into one
  # value: a post-review commit moves the head, so a marker stamped at the old
  # head (green@<old-sha>) no longer matches and the gate re-gates, stopping a
  # stale approval from carrying an out-of-date PR onto the target. An EMPTY
  # check_set declares NO gates, and the merge is then governed only by the
  # remaining members below (no-retarget, no-open-child, mergeStateStatus=CLEAN
  # = CI + approval). That empty case is the bug fix: the former code held the
  # merge UNCONDITIONALLY on a missing signoff_head even when no signoff gate was
  # required, stranding human-approved CLEAN PRs forever; a no-gate check_set now
  # lands once CLEAN. `hold_gate` is the first gate not green at the live head
  # (empty string when all are), computed in jq so a dynamic marker key
  # (check.<name>) needs no bash-array gymnastics.
  #
  # The `none`/`off` SENTINEL is read as no-gates too (tk-i48ca). A gateless rig
  # used to express that as the empty string, which is why empty had to mean
  # ungated — but empty is ALSO what a hand-recovered anchor carries when it never
  # ran the formula's normalization, so the two were indistinguishable and a
  # recovered bead merged with no codex review. The formula now stamps the literal
  # `none` for a deliberate opt-out, so the reading here must honour it or a
  # gateless rig would hold forever on a gate named "none" that nothing can stamp.
  # Empty is deliberately still ungated HERE (#163/#182 unchanged — this script is
  # not the fail-closed point); check-set-heal.sh normalizes an empty check_set
  # upstream, on the pass that runs immediately before this one.
  hold_gate=$(printf '%s' "$row" | jq -r --arg head "$head_oid" '
    . as $row
    | (($row.checkset // "")
        | split(",")
        | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
        | map(select(length > 0))
        | map(select((. | ascii_downcase) as $g | $g != "none" and $g != "off"))) as $gates
    | (first( $gates[] | select( (($row.meta["check." + .]) // "") != ("green@" + $head) ) )) // ""
  ' 2>/dev/null)
  if [ -n "$hold_gate" ]; then
    have=$(printf '%s' "$row" | jq -r --arg k "check.$hold_gate" '.meta[$k] // "none"' 2>/dev/null)
    echo "merge-skill: PR#$num check '$hold_gate' not green at live head (have '$have', want 'green@$head_oid'); merge held (anchor $id)"
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
