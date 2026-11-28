---
name: Gas City search for sending pool work only as a started run
description: The Gas City primitives read for how the pack sends work to a pool, the reason Gas City gives for keeping a claim route off a started workflow, this city's count of the race between a bare claim and a run, the live run a route meets and this city's count of runs that overlapped on one bead, and the Gas City gap the change leaves in place. Read it to review why gctk bead takeaway's --route now pours the pool's default formula, and why it refuses a route the releasing session's own run would refuse.
---

# Gas City search for sending pool work only as a started run

Read on 2026-11-27 at `gastownhall/gascity` main 6dce31bbb6.

## The need

A pool takes work in one of two ways. It claims a bead routed to its queue
(`gc.routed_to`), or it claims the steps of a workflow poured on the bead
(`gc.execution_routed_to`). When the pack routes a bead bare and something then
slings a formula on it, a pool worker can claim the bead itself while the run
starts on it. Each then refuses the other, and nothing offers the bead again.
The need is a way to send work to a pool that never leaves a bead both a bare
claim and a run.

## What was searched

- **The plain sling.** `gc sling <target> <bead>` with no `--on` pours the
  target's `default_sling_formula` (`internal/sling/sling_core.go`, the case
  `!opts.NoFormula && a.EffectiveDefaultSlingFormula() != ""`). An empty `--on`
  reads the same, because `cmd/gc/cmd_sling.go` registers `--on` as a string
  flag whose default is empty. This city's `city.toml` sets
  `default_sling_formula = "mol-polecat-work"` in `[agent_defaults]`. The plain
  sling covers the need, and the change uses it: `gctk bead takeaway --route`
  runs it in place of `--no-formula --no-convoy`.
- **The raw route.** `gc sling --no-formula --no-convoy` writes `gc.routed_to`
  and pours nothing. It is the form for a named agent whose hook serves a bead
  routed to its own name, and the mechanik keeps it.
- **The reason Gas City gives for keeping a claim route off a started
  workflow.** `restampWorkBeadRouting` stamps `gc.execution_routed_to` and
  clears `gc.routed_to` once a graph workflow is attached. Its comment says
  "the pool's tier-3 claim query and the drain engine's own dispatch are two
  uncoordinated authorities", so a claim route beside a started workflow is
  "a structural double-dispatch hazard". `resolveIdempotentShortCircuit`'s
  `NeedsAttach` case lets `--on` pour onto a bead that an earlier plain sling
  routed raw, and its `SkippedForClaim` case leaves a bead alone once another
  worker has claimed it. The clear lands only after the pour, so a bead routed
  raw stays claimable while the pour runs.

## This city's measurement

On 2026-11-27 at about 22:30Z I ran one `gc bd sql` per store, over all seven
of the city's stores: the HQ store, gc-toolkit's and the five other rigs'. It
counts the two notes `work-gate.sh` appends when it refuses. A run writes "already in_progress under live <owner>" when a
bare claimant holds the bead. A claimant writes "in flight in live run <run>"
when a run works the bead.

Four beads carry the run's note. Two are in gc-toolkit, tk-u5vx1d and
tk-kboai6, last updated 2026-10-04 and 2026-10-08, and two are in one other
rig's store, last updated 2026-08-17 and 2026-08-19. No bead carries the
claimant's note, and none carries both, which is what the stall leaves.
The race is rare here, so the change removes the bare sends outside retiring
code and adds nothing that detects or repairs the stall.

## The live run a route meets

- **Gas City's rule.** A sling that pours a formula is refused while a live
  root of the same formula works the bead. `checkLegacySourceWorkflowConflict`
  in `internal/sling/sling_core.go` returns `sourceworkflow.ConflictError`,
  which `gc sling` exits 3 on, for each live root
  `liveConvoyTrackedWorkflowRoots` (`internal/sling/sling_attachment.go`)
  finds through the bead's own input convoy. A root of another formula is no
  conflict. The reason Gas City gives is in that function's comment: "distinct
  formulas targeting the same bead are legitimate concurrent work", and "Only
  relaunching the SAME formula against the SAME bead while its prior root is
  still live is the bug this guards". The plain sling keeps the refusal.
  `slingDefaultFormula` falls back to a raw route only when a molecule or wisp
  that is no workflow is attached to the bead, and the comment above
  `attachFormulaToBead` says "a live graph.v2 workflow conflict" "keeps
  hard-failing". Nothing in either check exempts a root the slinging session
  holds.
- **How the release meets it.** `gctk bead takeaway --release` ends each live
  run on the bead except one this session holds a step of, which closes its own
  chain, and only then slings the route. A session holding a step of a run of
  the formula the route pours would land the release and then meet exit 3,
  leaving the bead released and sent nowhere. So the takeaway refuses that
  route before it writes anything. A run of another formula takes the route's
  run beside it. The pack's one release with a route from inside a run on the
  bead is the first reaction's dispose, whose run is mol-first-reaction, while
  the polecat pools pour mol-polecat-work.
- **This city's measurement.** On 2026-11-28 at 00:22Z I ran one `gc bd sql`
  per store over all seven of the city's stores. It joined every root with
  `gc.kind=workflow` to the one bead its input convoy tracks, with the root's
  `gc.formula_name` and its created and closed times, and counted the pairs of
  roots on one bead whose lifetimes overlapped. Eleven pairs ran one formula at
  once: six in gc-toolkit's store and five in the other rigs' stores, nine of
  them mol-polecat-work and two with no formula name. The newest of them started
  on 2026-09-28, and none has since. Twenty-six pairs ran two formulas at once:
  mol-first-reaction beside mol-polecat-work 14 times, the newest on
  2026-10-10, mol-first-reaction beside mol-validate-close 11 times, the newest
  on 2026-11-28, and mol-polecat-work beside mol-validate-close once. No bead
  held two live roots when it ran. So Gas City's rule holds here, and a run of
  another formula beside the first reaction's own run is the shape this city
  already runs.
- **No fix at the source.** The rule is not a fault, and its reason holds here:
  two live runs of one formula on a bead start two workers on one branch, which
  the work skill's "One dispatch, never two" forbids as well.

## The gap left in place

Gas City clears the claim route after the pour rather than before it, so a
raw route followed by `gc sling --on` still leaves the window open. By my
reading, not built, the fix at the source is small: clear the bead's
`gc.routed_to` before `InstantiateSlingFormula` on the `NeedsAttach` path, so a
pool worker cannot meet a raw route once a pour starts, plus a test of that
order. tk-ov8s4vi records it as a Gas City finding, set aside with nothing sent
upstream.
