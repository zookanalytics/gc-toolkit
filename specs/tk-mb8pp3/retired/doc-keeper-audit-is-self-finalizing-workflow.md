---
name: doc-keeper-audit-is-self-finalizing-workflow
description: "mol-doc-keeper-drift-audit (and -memory-audit) is a graph.v2 self-finalizing workflow. POST-#169 MODEL (CURRENT): each step advances by CLOSING its own step bead (gc.outcome=pass --status=closed); the terminal `drain` step closes itself THEN drain-acks, so no open assigned step remains to trip re-pool churn. CRITICAL GOTCHA: the formula's close commands are guarded by `[ -n \"${GC_BEAD_ID:-}\" ]`, which silently NO-OPs for a manually-claimed pool polecat (GC_BEAD_ID unset) — you MUST close each step bead by EXPLICIT id or the churn returns. EXECUTE fresh pours; the old block-and-unassign containment lore is HISTORICAL (pre-#169)."
metadata:
  node_type: memory
  type: project
  originSessionId: 2aa6ad94-da03-469d-85e9-3b78c1069ac7
---

## CURRENT MODEL (post-#169) — read this FIRST

PR#169 (`fix(workflow): doc-keeper graph.v2 audit steps close their step bead
before drain-ack`, tk-s5d5p, gc-toolkit HEAD `7d53fe4`) **fixed the re-pool
churn.** The doc-keeper graph.v2 audits (`mol-doc-keeper-drift-audit`, and its
sibling `mol-doc-keeper-memory-audit`) now self-finalize correctly:

- Steps are `prime → audit-and-file → drain → workflow-finalize`.
- **Each step advances by CLOSING its own step bead**
  (`gc bd update <step> --set-metadata gc.outcome=pass --status=closed`). The
  same session continues through the steps (continuation-group affinity). This
  REVERSES the old "do NOT close any bead" rule *for the step beads*.
- The **terminal `drain` step closes ITS OWN bead, THEN runs `gc runtime
  drain-ack`** — in that order. Because every step the session owns is closed
  before the drain-ack, there is no `in_progress` assigned step left to trip the
  runtime's `drain_acked_with_assigned_work` re-pool handler. That handler firing
  was the entire old churn; closing the steps removes the trigger.
- `workflow-finalize` (a no-command sink, `assignee=<rig>--control-dispatcher`)
  is processed asynchronously by the dispatcher to close the `kind=workflow`
  root. It stays `open` for a tick or two after your drain-ack — that is normal,
  NOT the bug. The worker NEVER closes it.

**The worker still does NOT close two things:** the **root** (workflow-finalize
closes it) and any **filed `doc-update` bead** (the refinery closes those when it
opens their PR). Only the *step* beads (prime/audit-and-file/drain) get closed by
the worker.

## CRITICAL GOTCHA — `GC_BEAD_ID` is unset for a manually-claimed pool polecat

The formula writes every close as:

```bash
[ -n "${GC_BEAD_ID:-}" ] && gc bd update "$GC_BEAD_ID" --set-metadata gc.outcome=pass --status=closed
```

A pool polecat that **claims the prime bead from the pool** (not hooked via a
wisp) has **`GC_BEAD_ID` UNSET**, so every one of those guarded closes silently
**NO-OPs** — the step beads never close, and the pre-#169 churn comes right back.
**You MUST close each step bead by its EXPLICIT id** (`gc bd update tk-xxxxx
--set-metadata gc.outcome=pass --status=closed`), not via `$GC_BEAD_ID`. Confirmed
2026-06-24 on root `tk-dy4aj` (steps prime `tk-ldz5z` → audit-and-file `tk-ki7y6`
→ drain `tk-pb40o`, finalize `tk-7hrw7`): GC_BEAD_ID was unset; closing all three
by literal id advanced the graph cleanly and the drain-ack did not re-pool.

## EXECUTE fresh pours — do NOT apply the old containment

A **new** drift/memory audit root (a fresh root id, all four steps freshly
materialized, `gc.session_name` = your session) is a legitimate pour of the
re-modeled formula — **run it**: prime → audit-and-file → drain, closing each
step by explicit id, then drain-ack. Do NOT apply the historical block-and-unassign
containment to a fresh root; that would strand a legitimate audit. The one-glance
tell you have the fixed model: the step descriptions say "a graph.v2 step advances
by CLOSING its bead" and the drain step says "closes its **own** step bead … before
draining."

## HISTORICAL — the pre-#169 churn and the two contained roots

Before #169, the worker drain-acked *without closing the step beads*; the open
`in_progress` entry step assigned to the draining session tripped
`drain_acked_with_assigned_work`, which re-pooled the step and respawned a fresh
polecat forever (PR#164 had fixed only materialization, not this). The fix at the
time was containment: set root + entry step `status=blocked --assignee=""` (block
removes it from `bd ready`/pool queries; the empty assignee guarantees a clean
drain-ack), verify with `gc hook` returning `[]` (NOT `gc graph`, whose READY
column is dependency-derived and lies for a manually-blocked root), and escalate
to the witness — never `gc bd close` the root. The fastest proof of the old bug
was `gc events | grep <root>` showing `session.drain_acked_with_assigned_work`
right after `session.stopped`.

Two roots were block-contained under the OLD model and should **stay blocked**
(they are pre-#169 artifacts, not fresh pours — do not resurrect or claim them):
- `mol-doc-keeper-memory-audit` root **tk-awhe3** — HALTED 2026-06-23.
- `mol-doc-keeper-drift-audit` root **tk-is0ir** — CONTAINED 2026-06-24 (verified
  still `status=blocked` 2026-06-24 during the tk-dy4aj run).

If a *fresh* root re-surfaces on your hook AFTER a documented clean close-chain +
drain-ack (steps all closed, finalize processed), only THEN is finalize still
broken — escalate to the witness and block-contain that specific root. Under the
#169 model this should not happen.

## Substantive audit guidance (unchanged)

When you DO run the audit: read the `origin/main` brief set + text, not the stale
polecat worktree ([[doc-keeper-drift-audit-read-origin-main]] — the worktree was
31 commits behind on the 2026-06-24 run and its glob missed `gascity-packs.md`;
canonical set is **five** briefs: agents, local-patching, packs, reference,
routing-model). DRIFT = a claim made false by a *specific upstream commit* (cite
it); incompleteness is the memory audit's job, not drift. Apply
[[doc-keeper-drift-audit-exclusions]] (pre-evaluated not-drift candidates) and
[[doc-keeper-audit-same-line-overlap]]; remember gascity-agents.md citations
resolve to the external pinned gastown pack ([[gascity-agents-doc-source-of-truth]]).
Dedup surface = live (non-closed) `doc-update` beads + open PRs of recently-closed
`doc-update` beads; cap MAX 5 filed/run. A clean **0-finding** run is correct and
common (the #142–#153 doc-update wave cleared the backlog; tk-dy4aj 2026-06-24 was
0/0).
