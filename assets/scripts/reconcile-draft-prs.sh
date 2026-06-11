#!/usr/bin/env bash
# reconcile-draft-prs — converge codex-gated PRs out of draft once their
# review has concluded. The convergent net for the un-draft one-shot.
#
# The codex review gate (review_gate="codex") opens every refinery PR as a
# draft and un-drafts it in the APPROVE|COMMENT arm of the review polecat's
# done sequence (template-fragments/polecat-non-impl-done.template.md). That
# un-draft is a single best-effort `gh pr ready`; if it fails for ANY reason
# — a transient GraphQL 401 (the PR#104 incident), the review polecat killed
# between recording its verdict and un-drafting, a deploy/restart mid-flow, a
# Dolt wedge — the PR is silently stranded in draft with no other recovery.
# A retry loop at that one call site only covers transient-error classes; a
# reconciler recovers from ANY cause by convergence, fitting the town's
# recovery architecture (config-drift drain, witness orphan-recovery,
# scale_check). See tk-24kxx.
#
# The refinery patrol runs this on each idle wake (folded into the find-work
# step's sleep loop). For every draft PR the bot owns it un-drafts ONLY when
# BOTH guards hold:
#
#   (a) a codex review bead for that PR EXISTS and is CLOSED — a review
#       actually concluded. This also scopes the pass to codex-gated PRs: a
#       human's manual draft PR has no review bead and is NEVER touched.
#   (b) NO open/in_progress bead references the PR — no review still running,
#       and no REQUEST_CHANGES rework in flight (that arm files a fix bead
#       carrying pr_number=N; an open one means the PR must stay draft).
#
# Idempotent + best-effort: once readied a PR leaves the --draft set, so the
# next pass skips it; a blipped `gh pr ready` is simply retried next idle
# pass. Nothing escalates on a single failure.
#
# NOT set -e: this is best-effort and must never abort the patrol's idle loop.
set -uo pipefail

# gh is the only way to enumerate/ready PRs here (the codex gate assumes it,
# like the fragment's `gh pr ready`). Without it there is nothing to do.
command -v gh >/dev/null 2>&1 || exit 0

# Draft PRs authored by this bot in the current repo. `--author "@me"` is a
# cheap narrowing; guard (a) below is the authoritative scope, so even if the
# author filter over-includes, a PR with no concluded codex review is skipped.
DRAFTS=$(gh pr list --draft --author "@me" --state open \
  --json number,headRefName 2>/dev/null \
  | jq -r '.[] | "\(.number)\t\(.headRefName)"' 2>/dev/null)
[ -n "$DRAFTS" ] || { echo "reconcile-draft-prs: no owned draft PRs"; exit 0; }

reconciled=0
skipped=0
while IFS=$'\t' read -r num head; do
  [ -n "${num:-}" ] || continue

  # Guard (a): a CLOSED codex review bead for this PR must exist (review
  # concluded). No such bead -> mid-review, or a human's manual draft -> skip.
  closed_review=$(gc bd list \
    --metadata-field task_kind=review \
    --metadata-field pr_number="$num" \
    --status closed --limit=1 --json 2>/dev/null \
    | jq -r '.[0].id // empty' 2>/dev/null)
  if [ -z "$closed_review" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  # Guard (b): no open/in_progress bead may reference this PR. An open review
  # bead means a review is still running; an open fix bead (pr_number=N, filed
  # by the REQUEST_CHANGES arm) means rework is in flight. Either way the PR
  # must stay draft.
  inflight=$(gc bd list \
    --metadata-field pr_number="$num" \
    --status open,in_progress --limit=1 --json 2>/dev/null \
    | jq -r '.[0].id // empty' 2>/dev/null)
  if [ -n "$inflight" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  # Both guards hold: converge to ready. Best-effort — a failure here is
  # retried on the next idle pass, never escalated.
  if gh pr ready "$num" >/dev/null 2>&1; then
    reconciled=$((reconciled + 1))
    echo "reconcile-draft-prs: un-drafted PR#$num ($head) — review concluded, no rework in flight"
  else
    echo "reconcile-draft-prs: PR#$num ready failed; will retry next idle pass" >&2
  fi
done <<< "$DRAFTS"

echo "reconcile-draft-prs: $reconciled reconciled, $skipped skipped"
exit 0
