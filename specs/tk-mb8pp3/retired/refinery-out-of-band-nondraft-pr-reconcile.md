---
name: refinery-out-of-band-nondraft-pr-reconcile
description: Waking to merge-ready beads whose PRs already exist non-draft + unreviewed (no review bead) → re-draft + dispatch codex review + close bead
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 6f3ca5b8-1627-40cb-9f16-1e5f144c89a7
---

> **SUPERSEDED (2026-06-30) by [[refinery-close-on-land-model]] (PR #163, drafts retired).** Re-drafting (`gh pr ready --undo`) is obsolete: PRs now open non-draft by design and the gate is `signoff_head`, not draft state. A **non-draft PR with an in-flight codex review bead is the HEALTHY state — do nothing**. Only the narrow case below still applies: a non-draft PR with **NO** review bead at all AND no `pr_url`/`merge_result` on the work bead (a truly orphaned out-of-band PR that never had codex dispatched) → dispatch ONE codex review bead (do NOT re-draft) and let the close-on-land loop land it. If a review bead already exists (open or in_progress), the handoff is healthy; never re-dispatch.

When the refinery wakes from sleep and finds queued work beads whose PRs **already exist on GitHub** but are **non-draft, zero reviews, no codex review bead, and the work beads are still open with no `pr_url`**, the PRs were created out-of-band (a prior refinery that crashed mid-handoff, or a recovery script) and never passed the codex gate. mechanik/bead-hosts may report "ZERO PRs" because they reason from bead state (`pr_url` empty), not GitHub.

**Why:** under `review_gate=codex`, non-draft is supposed to mean codex-approved (the reconcile-draft-prs net + codex done-template both assume ready=concluded-review). A non-draft+unreviewed PR violates that invariant — an operator could merge it thinking it's approved.

**How to apply:** treat it as a resumed merge-push in mr mode. For each: `gh pr ready <N> --undo` to re-draft (restore the invariant), create+route a codex review bead (`task_kind=review`, `pr_number`, `work_bead`, `fix_target_pool`, `gc.routed_to=<rig>/<prefix>polecat-codex`), then record `merge_result=pull_request`+`pr_url`+`pr_number`+`merged_target`, `--unset-metadata rejection_reason`, and `gc bd close`. `gc session wake/nudge` the codex pool fails "session not found" when it's on-demand — harmless; the **routed open review bead is the real spawn trigger** (pool spawns, review flips to in_progress within ~1 min). This is the startup-anomaly twin of [[formula-molecule-rendering-surfaces]]'s reconcile net (which handles the inverse: draft-but-review-concluded). Generalizes [[refinery-redraft-approved-pr-on-late-fix]] to a new trigger. See also [[refinery-mr-mode-pr-terminal-state]], [[refinery-pr-review-loop]].
