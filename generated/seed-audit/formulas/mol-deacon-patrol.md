Formula: mol-deacon-patrol
Description: Deacon patrol loop. Poured as a root-only wisp on startup:

  gc bd mol wisp mol-deacon-patrol --root-only --var binding_prefix='{{binding_prefix}}'
  gc bd update $WISP --assignee=$GC_AGENT

Each wisp is ONE iteration: check inbox, run town-wide coordination
tasks, pour the next iteration. On crash, re-read the formula steps
and determine where you left off from context.

Formula steps are NOT materialized as child beads. Read the step
descriptions below and work through them in order.

The loop mechanism: every exit path (happy or early) pours the next
wisp before burning this one. The prompt only bootstraps the first wisp.

## Deacon Role

The deacon is the **LLM sidekick to the controller**. It handles periodic
tasks that require judgment or observation — things the Go controller
can't or shouldn't do.

1. **Work-layer health** — are witnesses and refineries making progress?
   (Not "are they running" — that's the controller's job.)
2. **Utility agent health** — detect stuck dogs, dispatch shutdown dance.
3. **Orphan process cleanup** — kill leaked claude/node subagent processes.
4. **System diagnostics** — run `gc doctor`, act on findings.

Mechanical tasks (gate evaluation, cross-rig deps, orphan bead sweeps,
wisp compaction) are handled by exec orders in the maintenance
pack — no LLM needed.

## Idle Town Principle

The deacon should be silent/invisible when the town is healthy and idle.
Skip health checks when no active work exists. Use exponential backoff
between patrol cycles.

## What the deacon does NOT do

- Start/stop/restart agents (controller handles this)
- Per-rig orphaned bead recovery (witness handles this)
- Code implementation (polecats do this)
- Kill agents directly (files warrants, dog pool runs shutdown dance)
- Pool sizing (controller pool reconciliation)

Read each step's description before acting — Config values override defaults.

Variables:
  {{binding_prefix}}: Import binding prefix for gastown agent identities, including trailing dot when bound. (default=)
  {{event_timeout}}: Seconds to wait before re-checking. Replaces former event-watch loop which hot-spun on cache-reconcile firehose. Spend it with a bounded until-loop, not a standalone sleep — the harness blocks a standalone sleep, and a blocked wait is not a slow patrol, it is NO pacing at all. Raised 60 -> 600 (tk-2qa85), together with the next-iteration defect that made the old value dead letter: the pour forwarded only binding_prefix, and a --root-only pour materializes no defaults, so from cycle 2 this var arrived unrendered and there was no interval left to honour. The deacon was 17.9% of all city model calls over 24h (6,273 of 34,983). 600 is the harness ceiling on a single bounded wait call, not a preference — see the same note on mol-witness-patrol. This value reaches the loop ONLY through the startup pour, which reads it from this default via `gc formula show`; city.toml [rigs].formula_vars cannot override it, because mergeRigFormulaVars preserves an explicit --var. (default=600)

Steps (8):
  ├── mol-deacon-patrol.check-inbox: Check mail
  ├── mol-deacon-patrol.orphan-process-cleanup: Kill orphaned claude subagent processes [needs: mol-deacon-patrol.check-inbox]
  ├── mol-deacon-patrol.health-scan: Check work-layer health [needs: mol-deacon-patrol.orphan-process-cleanup]
  ├── mol-deacon-patrol.queue-starvation-check: Cross-check assigned work against visible work signal [needs: mol-deacon-patrol.health-scan]
  ├── mol-deacon-patrol.utility-agent-health: Check utility agent (dog) health [needs: mol-deacon-patrol.queue-starvation-check]
  ├── mol-deacon-patrol.dolt-health: Run Dolt data-plane health check [needs: mol-deacon-patrol.utility-agent-health]
  ├── mol-deacon-patrol.system-health: Run system diagnostics [needs: mol-deacon-patrol.dolt-health]
  └── mol-deacon-patrol.next-iteration: Pour next iteration and loop [needs: mol-deacon-patrol.system-health]
