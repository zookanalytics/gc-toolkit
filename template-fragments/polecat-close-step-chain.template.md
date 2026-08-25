{{ define "polecat-close-step-chain" }}
### Close your step chain before drain-ack

**This section supersedes the ending of every copy of the done sequence
above** — `### The Done Sequence` near the top, `## FINAL REMINDER: RUN THE
DONE SEQUENCE` at the bottom, and the same text again in `mol-polecat-work`'s
`submit-and-exit` step. All three finish at `gc runtime drain-ack`. One step
comes first.

A graph.v2 step advances only by closing its own bead. Drain with your step
beads open and the whole chain is left behind: the steps keep `gc.routed_to`
pointing at the polecat pool, the drain releases their assignee, and
`load-context` — the one step nothing blocks — goes ready and claimable. The
next polecat is then offered your finished run as though it were new work,
and taking that at face value has `workspace-setup` rebuild a branch that may
already be green-gated under a live review. At the census that filed this,
490 of 746 open beads in the store were husk chains (tk-y389z, tk-zab6q).

Immediately before `gc runtime drain-ack`, on **both** terminal exits — the
refinery handoff, and the `auto_push=false` branch-ready halt:

```bash
SC=""
for c in "${GC_PACK_DIR:-}" "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$c/assets/scripts/step-close.sh" ] && { SC="$c/assets/scripts/step-close.sh"; break; }
done
: "${SC:?step-close.sh not found in the pack; close each step by its (assignee, gc.step_ref) pair, never by an id read from the environment (tk-niu2f)}"
for STEP in load-context workspace-setup preflight-tests implement self-review submit-and-exit; do
  "$SC" --step "mol-polecat-work.$STEP" --outcome pass || echo "step-close: mol-polecat-work.$STEP was not this session's to close — left for the finalizer"
done
```

**The order is forward, and `bd` enforces it.** Each step is blocked by the
one before it, and `bd` refuses to close a blocked issue (`cannot close
blocked issue: X is blocked by [Y]`). Only `load-context` starts unblocked;
closing it unblocks `workspace-setup`, and so on. Reverse the loop and it
closes exactly one bead and reports five refusals.

**Run it only after the handoff.** Closing a step makes the next one ready, so
the loop does briefly publish a ready `workspace-setup` — the step that
rebuilds a branch. That is bounded, not eliminated: the steps stay assigned to
you for the whole loop (pool fallback only offers unassigned beads), the work
is already the refinery's, and the loop is six consecutive local calls.

**Never close `workflow-finalize`.** It is routed to
`core.control-dispatcher`, whose finalizer closes the workflow root and then
force-closes any member still open. `submit-and-exit` closes last and is that
step's only blocker, so finishing the loop arms this as a backstop for
anything it missed.

This does not soften the work-bead rule. The work bead is still the
refinery's and you still never close it; a step bead is machinery, not work,
and `step-close.sh` can only ever close a bead your session already owns,
because it resolves by the `(assignee, gc.step_ref)` pair.

### The third exit: a HOLD is quiesced, never closed

The loop above is for a run that FINISHED. A run you **hold** — a live sitting
owns the decision, the filed premise is falsified, a peer already has the
branch — reaches neither terminal exit, and closing its chain would record work
that was never done. It still has to be parked, and parking the *bead* is not
parking the *dispatch*.

The anchor is one record; the molecule is seven more, each carrying
`gc.routed_to` at the polecat pool and `gc.session_affinity=require`. Clear the
anchor's route by hand and the chain outlives you: your drain releases the step
assignees, `load-context` is the one step nothing blocks, and open + unassigned
+ routed + ready is the pool's offer predicate — so the next polecat is handed
your dead chain as new work. Nothing sweeps it, either.
`quiesce-completed-workflows.sh` gates on a TERMINAL anchor, and a parked-open
one is not terminal, so the witness pass declines it every cycle forever
(observed: anchor tk-iljtmq held 09:52Z, molecule tk-p3p9iv re-offered to a
fresh full-context polecat ~3h later — tk-oqseh6).

**Never park by hand — the park is six delivery keys across eight beads, and a
half-park reports success.** One writer:

```bash
HD=""
for c in "${GC_PACK_DIR:-}" "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$c/assets/scripts/hold-dispatch.sh" ] && { HD="$c/assets/scripts/hold-dispatch.sh"; break; }
done
: "${HD:?hold-dispatch.sh not found in the pack; do NOT hand-park — clearing only the anchor's route leaves the molecule re-offering itself forever (tk-oqseh6)}"
"$HD" --bead <work-bead> --reason "<why you are holding, in full — this is the only record>" \
  || { echo "hold-dispatch exited non-zero — the molecule is NOT parked; do NOT drain" >&2; exit 1; }
gc runtime drain-ack
```

It records your reason on the bead *before* it de-routes anything, clears every
delivery channel the anchor and each step actually carries, releases only claims
that are yours, and appends what it did. `workflow-finalize` keeps its
control-dispatcher route, and **no step is closed** — a molecule with a closed
step reads as "being driven step by step" and becomes permanently unsweepable
(`specs/tk-8m8d4` guard 2). Pass `--steps-only` when the anchor belongs to
somebody else and only your molecule is dead; the duplicate-dispatch refusal in
`load-context` is exactly that case.

**The drain is gated on that exit status, and the gate is not decoration.**
`hold-dispatch.sh` exits `1` when a write did not land and `2` when it refused
outright, and a partial park is the case it is reporting: a step whose delivery
keys are still set, or one another session still holds. Drain through that and
the session dies with those pins live — which is the re-offer this whole
mechanism exists to prevent, now with nothing but stderr to say so. A non-zero
line does not stop the next one in the shell an agent actually runs, so the
`||` has to be written down. `doctor/check-hold-dispatch-wired` fails if this
snippet ever drains unconditionally again.

**Do not run the close loop above on this path.** A held run closes nothing.
Regression test: `assets/scripts/hold-dispatch.test.sh` (hermetic; stubs `gc`
and `bd`), and `doctor/check-hold-dispatch-wired` keeps this fragment and the
script from drifting apart.
{{ end }}
