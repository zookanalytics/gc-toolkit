Formula: mol-witness-patrol
Description: Witness patrol loop — rig work-health RECOVERY only. Poured as a root-only
wisp on startup (the agent prompt's startup reconcile adopts before it
pours):

  gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='{{binding_prefix}}'
  gc bd update $WISP --assignee=$GC_AGENT

Each wisp is ONE iteration: mail, orphan recovery, refinery queue health,
pour the next iteration. Steps are not materialized; read each description
as you reach it. Never exit the wisp from an intermediate step — continue,
or jump to next-iteration to pour and burn. A pass ends at next-iteration,
which defers the next wisp an hour and ends the turn, and the controller's
reassignment restart runs the next pass in a fresh session once the hour has
passed.

Scope: the witness recovers work whose owner died, files a finding when a live
pool seat keeps printing but has written nothing for three hours, files a bug
bead that waits for the operator's placement when mail reports a defect in the
pack, and watches the refinery queue. It does NOT manage processes
(controller), write code (polecats), merge (refinery/cadence), kill or restart
a session (the controller recovers a pool seat that goes quiet, and a person
decides on a seat a finding names), or run the batch unnamed-wait triage (the
liveness-sweep exec order owns that surface). A finding becomes one deduped
BEAD through assets/scripts/patrol-finding.sh, and a proactive first reaction
disposes it: routed to a pool, held for the operator's placement sitting, held
on an edge, or put to the operator as a human gate on the finding.
assets/scripts/human-gate.sh files a human gate on a bead directly, for an
emergency about that bead that needs a human now.

Every address this formula stamps or queries comes from
assets/scripts/resolve-route.sh. The refinery whose queue it reads is
rig-scoped, so its identity carries `<rig>/`, and the bare rendered form names
no agent. A query by a hand-written address fails quietly: listing beads by an
address no agent holds returns a valid empty array, which reads as an empty
queue.

Marked blocks (bug-file, notice-finding, candidate-pipeline,
host-bead-skip, downstream-court-skip, topology-root-skip,
liveness-map-guard, liveness-lookup, no-progress-finding, husk-guard,
owning-store-guard, recovery-stamp-gate, crash-loop-window,
patrol-wisp-pour, refinery-stuck-handoff) are extracted and executed by
their tests; keep markers, keep them backslash-free.

Variables:
  {{binding_prefix}}: Agent identity prefix with trailing dot. Non-empty default on purpose: this patrol builds its refinery address from it, and an empty prefix renders bare roles like <rig>/refinery that no agent holds. (default=gc-toolkit.)

Steps (4):
  ├── mol-witness-patrol.check-inbox: Check mail
  ├── mol-witness-patrol.recover-orphaned-beads: Recover orphaned work beads [needs: mol-witness-patrol.check-inbox]
  ├── mol-witness-patrol.check-refinery: Check refinery queue health [needs: mol-witness-patrol.recover-orphaned-beads]
  └── mol-witness-patrol.next-iteration: Pour the next iteration, defer it an hour and end the turn [needs: mol-witness-patrol.check-refinery]
