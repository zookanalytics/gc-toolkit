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
{{ end }}
