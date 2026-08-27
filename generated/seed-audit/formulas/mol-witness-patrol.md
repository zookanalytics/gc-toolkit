Formula: mol-witness-patrol
Description: Witness patrol loop — rig work-health RECOVERY only. Poured as a root-only
wisp on startup (the agent prompt's startup reconcile adopts before it
pours):

  gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='{{binding_prefix}}' --var event_timeout='{{event_timeout}}'
  gc bd update $WISP --assignee=$GC_AGENT

Each wisp is ONE iteration: mail, orphan recovery, refinery queue health,
pour the next iteration. Steps are not materialized; read each description
as you reach it. Never exit the wisp from an intermediate step — continue,
or jump to next-iteration to pour and burn.

Scope: the witness recovers work whose owner died, files ONE warrant bead
for the dog pool when an owner is alive but wedged, and watches the
refinery queue. It does NOT manage processes (controller), write code
(polecats), merge (refinery/cadence), kill sessions directly (the dog pool
executes warrants), or run the batch unnamed-wait triage (the
liveness-sweep exec order owns that surface). Escalations go through
assets/scripts/escalate.sh — one open visit per situation key.

Marked blocks (host-bead-skip, liveness-lookup, husk-guard, patrol-wisp-pour)
are extracted and executed by their tests; keep markers, keep them
backslash-free.

Variables:
  {{binding_prefix}}: Agent identity prefix, including trailing dot when bound. (default=)
  {{event_timeout}}: Seconds to wait before the next cycle. Spent as a bounded until-loop (the harness blocks a standalone sleep, which removes pacing entirely). Ceiling 600: the harness caps one call at 600s and SIGTERMs past it. (default=600)

Steps (4):
  ├── mol-witness-patrol.check-inbox: Check mail
  ├── mol-witness-patrol.recover-orphaned-beads: Recover orphaned work beads [needs: mol-witness-patrol.check-inbox]
  ├── mol-witness-patrol.check-refinery: Check refinery queue health [needs: mol-witness-patrol.recover-orphaned-beads]
  └── mol-witness-patrol.next-iteration: Pour next iteration and loop [needs: mol-witness-patrol.check-refinery]
