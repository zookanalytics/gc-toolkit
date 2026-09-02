Formula: mol-deacon-patrol
Description: Deacon patrol loop — city infrastructure health. Poured as a root-only wisp
on startup (the agent prompt's startup reconcile adopts before it pours):

  gc bd mol wisp mol-deacon-patrol --root-only --var binding_prefix='{{binding_prefix}}' --var event_timeout='{{event_timeout}}' --var doctor_interval='{{doctor_interval}}'
  gc bd update $WISP --assignee=$GC_AGENT

Each wisp is ONE iteration: mail, orphan-process cleanup, Dolt health,
doctor sweep, pour the next iteration. Steps are not materialized; read
each description as you reach it, and never exit the wisp from an
intermediate step. The deacon is the controller's judgment layer — it never
starts/stops agents, never recovers per-rig beads (witness), never writes
code. Escalations go through assets/scripts/escalate.sh — one open visit
per situation key.

The marked backup-manifest-check block is extracted and executed by
assets/scripts/dolt-backup-manifest-check.test.sh; keep the markers and
keep it backslash-free.

Variables:
  {{binding_prefix}}: Agent identity prefix, including trailing dot when bound. (default=)
  {{doctor_interval}}: Seconds between doctor sweeps. The sweep step gates itself on this, so the patrol keeps its faster cadence for mail and Dolt while the sweep runs hourly. 1800 is the shortest the operator asked for. doctor-sweep.sh owns the default, so a value that never reaches it still sweeps hourly. (default=3600)
  {{event_timeout}}: Seconds to wait before the next cycle. Spent as a bounded until-loop (the harness blocks a standalone sleep). Ceiling 600: the harness caps one call at 600s. (default=600)

Steps (5):
  ├── mol-deacon-patrol.check-inbox: Check mail
  ├── mol-deacon-patrol.orphan-process-cleanup: Kill orphaned claude subagent processes [needs: mol-deacon-patrol.check-inbox]
  ├── mol-deacon-patrol.dolt-health: Run Dolt data-plane health check [needs: mol-deacon-patrol.orphan-process-cleanup]
  ├── mol-deacon-patrol.system-health: Run gc doctor sweep [needs: mol-deacon-patrol.dolt-health]
  └── mol-deacon-patrol.next-iteration: Pour next iteration and loop [needs: mol-deacon-patrol.system-health]
