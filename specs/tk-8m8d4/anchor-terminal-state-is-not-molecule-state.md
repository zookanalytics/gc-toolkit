---
name: Telling a dead molecule from a live one under a terminal anchor
description: Why quiesce-completed-workflows stripped a live rework molecule, what evidence survives on a bead to date an anchor's terminal state against the molecule in front of it, which candidate discriminators were measured and rejected, and why the fix needed two guards rather than one.
---

# Telling a dead molecule from a live one under a terminal anchor

Design record for the tk-8m8d4 fix to `assets/scripts/quiesce-completed-workflows.sh`.

## 1. What happened

The pass de-routed and un-assigned the frontier step of a LIVE rework molecule 87
seconds after a polecat claimed it (signal-loom `sl-xhfl`, step `sl-um8j`
`workspace-setup.attempt.1`, anchor `sl-ew4w` / PR #533). The molecule kept moving
for eleven more minutes and then stopped for good.

Reconstructed from `dolt_history_issues`, the strip is unambiguous — route cleared
first, assignee one second later, this pass's exact two-write signature:

| time (2026-08-11) | event |
|---|---|
| 19:16:41 | rework molecule `sl-xhfl` materialized (root + 29 step beads) |
| 19:17:42 | polecat `lx-vge0` claims `sl-um8j` |
| 19:19:09 | `gc.routed_to` cleared |
| 19:19:10 | assignee cleared |
| 19:19:39 | the molecule closes `load-context.attempt.1` — it was still running |
| 19:30:06 | last movement; silent thereafter |

The gate that let it through is `is_terminal_anchor()`, on `merge_result=pull_request`.
That marker was on the anchor continuously from the original round (verified: present
at 19:16:38, three seconds before the rework molecule existed, and never cleared by
the re-dispatch). It described the PR the rework was dispatched to FIX.

## 2. The general defect

An anchor outlives its molecules — the original, then one per rework round —
so every field on it describes the WORK, not the molecule standing in front of it.
Any predicate read from the anchor alone is therefore ambiguous in two directions:

1. **The marker predates the molecule.** A rework molecule is poured against an
   anchor already wearing the previous round's terminal state.
2. **The marker arrived mid-flight.** `mol-scoped-work` dispatches its steps one at
   a time and the refinery stamps the anchor at the submit step, while
   `cleanup-worktree` and `workflow-finalize` still have to run. Observed on
   `sl-jnjd`, whose `cleanup-worktree.attempt.1` (`sl-wmf1`) was left unrouted and
   never claimed, so the root could never close. Protecting only `workflow-finalize`
   does not help: the escape path is a chain, and this de-routes a link before it.

Both were live at filing, so this is not a theoretical widening.

## 3. What is NOT available to discriminate

The bead's three candidate remedies all reduce to "compare the molecule's
materialization time against the time the anchor became terminal". Nothing on a bead
records the latter. Measured, not assumed:

| Candidate | Verdict |
|---|---|
| a companion `merge_result_at` field | does not exist; every writer of `merge_result` in this pack stamps the value alone |
| the anchor's `updated_at` | rewritten constantly by other patrols — `sl-ew4w` was written 30+ times in the three minutes around the strip |
| the anchor's `started_at` | moves with the anchor's LATEST claim: `sl-ew4w` reads 2026-08-13, two days after the rework molecule it was supposed to date |
| `bd history <id> --json` | its snapshots carry no `metadata` and no `assignee` at all (keys stop at `updated_at`), so it cannot answer when a marker was written |
| `bd history <id> --events --json` | does carry metadata diffs, but is a strict subset of the commit history (44 events against 100+ commits on `sl-ew4w`) — an audit log, not a reconstruction source |
| the anchor's session vs the molecule's | ~half of real anchors carry no `gc.session_name` at all (12 recent gc-toolkit anchors sampled: 6 empty), and a freshly-poured root has none either, so the comparison fails closed on the common case and silently matches empty-to-empty on the dangerous one |
| a grace period on molecule age | narrows the window; a rework that runs longer than the grace is stripped exactly as before |

`gh pr view --json createdAt` would date the `pull_request` shape precisely, but it
adds a network call per root, needs auth inside the witness patrol, and answers
nothing for `pre_open_gate`, a refinery handoff, or a human park.

## 4. The fix: two guards

### Guard 1 — the marker predates the molecule

The pass records the one fact it can honestly know: `quiesce.terminal_since` on the
anchor, the first time THIS pass observed it terminal. A molecule whose
`created_at` is later than that instant was materialized while the anchor was
already terminal, and cannot have produced that state.

Properties that made this the choice:

- **No rollout gap.** The stamp is written on first sighting and the same pass
  proceeds to sweep. Every molecule alive when a stamp lands predates it, so
  behavior on the existing population is unchanged; only later-poured molecules are
  held back — which is the whole population at risk, since a rework is dispatched
  against an anchor that has been parked in the merge gate for hours.
- **Per-episode.** The stamp is cleared when the anchor is next seen non-terminal,
  so a repool-and-rework round is dated from its own first sighting rather than
  inheriting the previous one's.
- **Bounded error.** The residual window is one patrol cycle at the head of a
  terminal episode — the minutes just after a PR opens, when no rework can yet have
  been dispatched.

It costs the pass's "never writes to the anchor" invariant. The replacement
invariant is narrower and stated in both the script header and the patrol step: one
additive key, written by this pass, read by this pass, never a lifecycle field.
Verified against a live bead that a metadata write is not subject to bd's claim
guard, so the stamp lands on an anchor held by another session.

### Guard 2 — the marker arrived mid-flight

Only `closed` and `merge_result=merged` are anchor states no live molecule wears.
For every other shape the pass calls terminal, the molecule's own evidence decides:
a graph that has CLOSED a step is being driven step by step, and its open steps are
pending work rather than husks. Zero closed steps is the inline-execution signature
`mol-polecat-work` produces by construction, which is the population this pass was
built for.

This is the same two-state line `detect-stalled-workflows.sh` already draws from the
other side (tk-xesf6), and the reason it draws it is this same defect. The two
passes now agree about which anchor states prove anything.

The exemption for the two unambiguous states is not cosmetic: a husk can ACQUIRE a
closed step when somebody closes `load-context` by hand to stop the churn, and the
sibling pass measured three such molecules on this rig, all with landed anchors.

## 5. Why one guard was not enough

They cover each other's blind spot, and neither covers both live instances:

| | `sl-xhfl` (rework) | `sl-jnjd` (mid-flight teardown) |
|---|---|---|
| guard 1 | catches it — the anchor was terminal for three hours before the pour | misses — the anchor went terminal DURING the molecule's life |
| guard 2 | misses at the moment of the strip: the molecule had closed nothing yet (its first close came 30s later) | catches it — the graph had closed many steps |

Guard 2 alone would also have left the dominant case unfixed: a rework dispatched
with `mol-polecat-work` — the default implementation formula — closes no step ever,
so the husk signature can never distinguish it from a husk. Guard 1 is what
generalizes; guard 2 is what covers the formula whose anchor goes terminal early.

## 6. Fail-closed behavior

An undatable molecule, an unparseable stamp, and an unreadable closed-step listing
all skip the root and are counted `unresolved`, exactly like an unresolved anchor:
an un-quiesced husk wastes wisps, while a wrong sweep drains a polecat
mid-implementation. A refused stamp WRITE is the one failure that does not skip —
the molecule predates `now` either way — so the pass warns and sweeps, and the
episode stays undated until a later pass records it.

## 7. Not in this change

- Backfilling a true `merge_result_at` at every write site in the refinery patrol.
  It would make guard 1 exact rather than observation-bounded, at the cost of five
  writer sites in the merge path and a rollout window in which anchors parked today
  carry no stamp at all. The observation stamp converges on the same answer within
  one patrol cycle with a contained blast radius.
- Finalizing a husk's step graph rather than quiescing it, which remains the durable
  upstream fix and is out of scope here as it was in tk-p9ji9.
- Unsticking `sl-xhfl` / `sl-jnjd` themselves — both were already force-closed by
  hand on 2026-08-13/14, before this bead was claimed.
