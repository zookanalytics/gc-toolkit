---
name: gascity polecat patterns
description: gc-toolkit operational patterns for polecat work — assignee-cleared-on-close querying, rotation salvage policy, refinery PR-handoff contract.
---

# Gascity polecat patterns

Operational patterns for polecat work in gc-toolkit. These are
fork-side conventions, not Gas City features: each is a "how we use
the SDK" decision rather than a description of what the SDK does.

## Assignee is cleared on close — query `gc.routed_to`, not `assignee`

When a polecat finishes work and closes a bead, the `assignee`
field is cleared to `null`. Routing only persists in
`metadata["gc.routed_to"]`.

**Implication:** Auditing polecat activity by filtering on
`assignee` produces wrong answers for closed beads. A query like
`select(.assignee | contains("polecat"))` will silently miss every
polecat-completed bead and surface only patrol / refinery /
control-dispatcher names.

The correct query targets routing metadata:

```bash
gc bd list --status=closed --json \
  | jq '.[] | select(.metadata["gc.routed_to"] // "" | contains("polecat"))'
```

Open polecat-routed beads still have `assignee` set (until claimed);
only closed ones get cleared. Confirmed in production 2026-05-06
against signal-loom pilot beads.

**Related:** pool routing requires `gc.routed_to` to be set
explicitly (via `gc sling` or formula). Bare `bd create` calls
produce beads with no routing — they sit in the queue forever
until someone slings them. That is not a regression; it is the
model.

## Rotation salvage: accept loss by default

When a polecat session ends mid-work on a bead and the pool spawns
a replacement that picks up the same bead with a fresh branch, do
**not** salvage the predecessor's worktree to a preservation branch
by default.

Parallel-history risk from a preservation branch is not worth it
for routine rotations. Redo beats preserve. The predecessor's
worktree on disk preserves the work for forensic reference without
polluting the canonical branch graph.

Two-rule policy:

- **Routine rotation** — predecessor thought less than ~2 hours,
  OR the bead is not on the critical path. Accept loss. Leave the
  worktree on disk. Log an informational mail to mayor; do not
  push anywhere.
- **High-cost rotation** — predecessor thought more than ~2 hours
  AND the bead is on the critical path. Ping mayor with that
  specific context before acting. Mayor may authorize salvage to
  a preservation branch.

**Never** silently push to the original polecat branch when a
successor has already replaced `metadata.branch`. That creates a
parallel-history conflict.

This is a refinement of the witness orphan-recovery formula's
recovery cases — those assume no successor in flight. With a
successor active, the formula's "push to branch" step is no
longer the right move.

## Refinery PR-handoff contract

When the refinery closes an impl bead with metadata
`merge_result=pull_request` and `pr_url=<url>`, the work is
**done from the refinery's perspective**. The PR sits OPEN on
GitHub (mergeable, all checks green). The operator merges through
their external GitHub-queue process.

Refinery's scope today is "ensure code lands in a PR-ready state."
Auto-merging is intentionally not its job. The longer-term plan is
to pull the merge step into gc-toolkit so the refinery can land
the merge itself, but as of 2026-05-06 that is still external.

**Practical consequences:**

- A closed impl bead with `merge_result=pull_request` and the
  GitHub PR still OPEN is **not** "stuck" and **not** a refinery
  bug.
- Do not try to auto-merge or enable GitHub auto-merge unless the
  operator explicitly asks.
- Once the impl bead is closed by the refinery, that chain is
  mayor-complete from the dispatch perspective. Move on to the
  next bead.
- A handoff truly stalls only when the bead **stays open**, no
  `merge_result` metadata appears, and the refinery is alive but
  not picking up the work. The trigger to investigate is "bead
  never closed," not "PR not merged."

## Cross-references

- [`gascity-rebase-conventions.md`](./gascity-rebase-conventions.md)
  — rebase polecats own their own force-push step; refinery never
  force-pushes. Closely related to the refinery contract above.
- [`gascity-upstream-engagement.md`](./gascity-upstream-engagement.md)
  — operator-gated PR submission framing. The refinery contract
  here covers the *internal* gc-toolkit fork merge step, not the
  *external* upstream submission.
