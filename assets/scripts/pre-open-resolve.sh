#!/usr/bin/env bash
# pre-open-resolve — open the PR for a PRE-OPEN-gated anchor once codex is green
# (the second half of the pre-open codex gate, tk-6d0vb.1.8). It is the mirror of
# the merge skill one step earlier in the lifecycle: the merge skill lands a ready
# PR; this pass CREATES the PR — but only after codex has vetted the branch, so a
# PR that becomes visible is codex-green at birth.
#
# Background. mol-refinery-patrol's merge-push step, when `codex` is a check-set
# member and there is no PR yet, does NOT open the PR. It dispatches the codex
# signoff against the BRANCH compare-range and parks the anchor in the
# `pre_open_gate` sub-state (open, assignee="", gc.routed_to="", merge_result=
# pre_open_gate, branch/merged_target set, NO pr_url/pr_number). The codex
# reviewer stamps `check.codex=green@<branch-head>` on the anchor (or files a
# rework child on REQUEST_CHANGES). THIS pass then opens the non-draft PR at that
# reviewed head and flips the anchor to `merge_result=pull_request`, handing it to
# the normal merge gate (merge-skill.sh) unchanged.
#
# Preserves #163 (the PR still opens NON-draft — no draft phase is reintroduced)
# and #185 (comment-only — the recorded codex verdict is replayed as a plain PR
# comment, never an approval; GitHub approval stays exclusively human/external).
#
# Per anchor, in order:
#   PR already open for the branch  -> flip THIS anchor to pull_request (record
#                                      pr_url/pr_number). Convergence: a sibling
#                                      anchor on the same branch (e.g. the original
#                                      convoy left in pre_open_gate after a pre-open
#                                      rework filed a child) becomes closeable on
#                                      merge instead of leaking open. Never opens a
#                                      second PR for a branch that already has one.
#   no PR + check.codex green@head  -> open the non-draft PR at the reviewed head,
#                                      replay the codex verdict as a comment, flip
#                                      to pull_request.
#   no PR + check.codex not green   -> HOLD (codex not done, or the head advanced
#                                      past the reviewed commit so the marker is
#                                      stale — a rework's review re-stamps the new
#                                      head; convergent, retried next idle pass).
#
# The gate here is codex-only, by design: pre-open moves ONLY the codex member
# ahead of PR-creation (CI + approval stay post-open). The FULL check-set is still
# enforced at merge time by merge-skill.sh, unchanged.
#
# Enumerated by BEAD (like merge-skill.sh / reconcile-merged-prs.sh): each anchor
# resolves in this repo by construction.
#
# NOT set -e: best-effort, must never abort the patrol's idle loop. A PR is opened
# ONLY on an authoritative check.codex=green@<live-head>; any tool error skips the
# anchor and retries next idle pass.
set -uo pipefail

# gh is the only way to read branch/PR state and open the PR here. Without it
# there is nothing to do (the anchor simply waits for a synced pack, like the
# other passes).
command -v gh >/dev/null 2>&1 || exit 0

# Open pre-open-gated anchors in this rig's ledger.
ANCHORS=$(gc bd list --status=open \
  --metadata-field merge_result=pre_open_gate \
  --limit=200 --json 2>/dev/null)
[ -n "$ANCHORS" ] && [ "$ANCHORS" != "[]" ] \
  || { echo "pre-open-resolve: no pre-open anchors"; exit 0; }

# One compact JSON row per anchor. Built into a variable (not piped into the loop)
# so the loop runs in THIS shell and the counters below survive the pipe boundary.
ROWS=$(printf '%s' "$ANCHORS" \
  | jq -c '.[] | {
      id,
      branch: (.metadata.branch // ""),
      target: (.metadata.merged_target // .metadata.target // ""),
      title:  (.title // ""),
      desc:   (.description // ""),
      notes:  (.notes // ""),
      itype:  (.issue_type // "task"),
      prio:   (.priority // ""),
      codex:  (.metadata["check.codex"] // "")
    }' 2>/dev/null)
[ -n "$ROWS" ] || { echo "pre-open-resolve: no pre-open anchors"; exit 0; }

created=0; flipped=0; held=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  branch=$(printf '%s' "$row" | jq -r '.branch // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  if [ -z "$id" ] || [ -z "$branch" ]; then
    skipped=$((skipped + 1)); continue
  fi
  [ -n "$target" ] || target="main"

  # --- A PR already exists for this branch (any state)? ------------------------
  # If a sibling anchor's resolve (or a post-open rework) already opened it, flip
  # THIS anchor to pull_request so it becomes visible to the merge skill + the
  # merged-close observer (never open a twin). --state ALL (not just open): a
  # sibling PR that already MERGED or closed must still flip this anchor onto the
  # pull_request scan the observer watches — otherwise a parent left in
  # pre_open_gate after a pre-open rework, whose sibling PR merged, would strand
  # open forever (reconcile-merged-prs.sh scans only pull_request). The flip
  # stamps NO gate marker, so the merge skill still re-gates before any merge.
  EXIST_JSON=$(gh pr list --head "$branch" --state all \
    --json number,url --limit 1 2>/dev/null)
  exist_num=$(printf '%s' "$EXIST_JSON" | jq -r '.[0].number // empty' 2>/dev/null)
  exist_url=$(printf '%s' "$EXIST_JSON" | jq -r '.[0].url // empty' 2>/dev/null)
  if [ -n "$exist_num" ]; then
    gc bd update "$id" \
      --set-metadata merge_result=pull_request \
      --set-metadata pr_url="$exist_url" \
      --set-metadata pr_number="$exist_num" \
      --set-metadata merged_target="$target" >/dev/null 2>&1
    flipped=$((flipped + 1))
    echo "pre-open-resolve: $id branch '$branch' already has PR#$exist_num; flipped to pull_request"
    continue
  fi

  # --- No PR yet: gate on check.codex=green@<live branch head>. -----------------
  # The reviewed OID is the branch head the pre-open signoff validated. Read the
  # LIVE head via gh (no local checkout needed). If codex is not green at that
  # exact head — reviewer not done, or a rework advanced the head so the marker is
  # stale — HOLD; a rework's fresh review re-stamps the new head next pass.
  head_oid=$(gh api "repos/{owner}/{repo}/commits/$branch" --jq '.sha' 2>/dev/null)
  if [ -z "$head_oid" ]; then
    echo "pre-open-resolve: $id branch '$branch' head unresolved; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  codex_mark=$(printf '%s' "$row" | jq -r '.codex // empty')
  if [ "$codex_mark" != "green@$head_oid" ]; then
    echo "pre-open-resolve: $id branch '$branch' codex not green at live head (have '${codex_mark:-none}', want 'green@$head_oid'); held"
    held=$((held + 1)); continue
  fi

  # --- Open the non-draft PR at the reviewed head. -----------------------------
  # Body mirrors merge-push: full description (the "why") + polecat notes (the
  # "what") + a handoff footer. --body-file avoids multi-line quoting hazards.
  title=$(printf '%s' "$row" | jq -r '.title // empty')
  desc=$(printf '%s'  "$row" | jq -r '.desc // empty')
  notes=$(printf '%s' "$row" | jq -r '.notes // empty')
  itype=$(printf '%s' "$row" | jq -r '.itype // "task"')
  prio=$(printf '%s'  "$row" | jq -r '.prio // empty')

  PR_BODY_FILE=$(mktemp)
  {
    echo "## Summary"
    echo
    if [ -n "$desc" ]; then printf '%s\n' "$desc"; else
      printf 'Refinery handoff for `%s` (no bead description recorded).\n' "$id"; fi
    if [ -n "$notes" ]; then
      echo; echo "## Implementation notes"; echo; printf '%s\n' "$notes"; fi
    echo
    echo "## Refinery handoff"
    echo
    printf -- '- Issue: `%s` (%s%s)\n' "$id" "$itype" "${prio:+, P$prio}"
    printf -- '- Source branch: `%s`\n' "$branch"
    printf -- '- Target: `%s`\n' "$target"
    printf -- '- Codex signed off pre-open at `%.8s`; PR opened codex-green.\n' "$head_oid"
  } > "$PR_BODY_FILE"

  PR_URL=$(gh pr create \
    --base "$target" \
    --head "$branch" \
    --title "$title ($id)" \
    --body-file "$PR_BODY_FILE" 2>/dev/null || true)
  rm -f "$PR_BODY_FILE"
  if [ -z "$PR_URL" ]; then
    # A create race (a concurrent open) is not fatal — discover the PR instead.
    PR_URL=$(gh pr view "$branch" --json url -q '.url' 2>/dev/null || true)
  fi
  if [ -z "$PR_URL" ]; then
    echo "pre-open-resolve: $id branch '$branch' PR create/discover failed; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  PR_NUMBER=$(gh pr view "$PR_URL" --json number -q '.number' 2>/dev/null)
  if [ -z "$PR_NUMBER" ]; then
    echo "pre-open-resolve: $id opened '$PR_URL' but PR number unresolved; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi

  # Replay the recorded codex verdict as a NON-blocking PR comment (#185: never an
  # approval — the city does not approve; approval is human/external). Best-effort:
  # the review bead (anchor_bead=$id, task_kind=review) carries the verdict in its
  # notes; the most recent one under this anchor is the signoff that just passed.
  REVIEW_ID=$(gc bd list \
    --metadata-field task_kind=review \
    --metadata-field anchor_bead="$id" \
    --status=closed,open,in_progress --limit=10 --json 2>/dev/null \
    | jq -r 'sort_by(.updated_at // .created_at) | last | .id // empty' 2>/dev/null)
  VERDICT=""
  [ -n "$REVIEW_ID" ] && VERDICT=$(gc bd show "$REVIEW_ID" --json 2>/dev/null \
    | jq -r '.[0].notes // ""' 2>/dev/null)
  if [ -n "$VERDICT" ]; then
    gh pr comment "$PR_NUMBER" --body "$(printf 'Codex signoff (pre-open, comment-only — not an approval):\n\n%s' "$VERDICT")" \
      >/dev/null 2>&1 || true
  else
    gh pr comment "$PR_NUMBER" --body "Codex signed off pre-open at \`${head_oid:0:8}\` (comment-only — not an approval)." \
      >/dev/null 2>&1 || true
  fi

  # Flip to the normal gating sub-state. check.codex is already green@head (the PR
  # is born at exactly the reviewed head), so merge-skill.sh merges once CI +
  # approval + CLEAN. Best-effort; a failed flip leaves the anchor in pre_open_gate
  # and next pass takes the "PR already open" branch above (idempotent).
  gc bd update "$id" \
    --set-metadata merge_result=pull_request \
    --set-metadata pr_url="$PR_URL" \
    --set-metadata pr_number="$PR_NUMBER" \
    --set-metadata merged_target="$target" >/dev/null 2>&1
  created=$((created + 1))
  echo "pre-open-resolve: $id opened PR#$PR_NUMBER for '$branch' at ${head_oid:0:8} (codex-green); flipped to pull_request"
done <<< "$ROWS"

echo "pre-open-resolve: $created opened, $flipped flipped, $held held, $skipped skipped"
exit 0
