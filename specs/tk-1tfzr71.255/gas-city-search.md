---
name: Gas City search for sending pool work only as a started run
description: The Gas City primitives read for how the pack sends work to a pool, the reason Gas City gives for keeping a claim route off a started workflow, this city's count of the race between a bare claim and a run, and the Gas City gap the change leaves in place. Read it to review why gctk bead takeaway's --route now pours the pool's default formula.
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
of the city's stores: HQ, gc-toolkit, signal-loom, gascity, shutupandlisten,
sprintshow and growth-factor. It counts the two notes `work-gate.sh` appends
when it refuses. A run writes "already in_progress under live <owner>" when a
bare claimant holds the bead. A claimant writes "in flight in live run <run>"
when a run works the bead.

Four beads carry the run's note. In gc-toolkit they are tk-u5vx1d and
tk-kboai6, last updated 2026-10-04 and 2026-10-08. In shutupandlisten they are
su-kmstq and su-a0fs.1, last updated 2026-08-17 and 2026-08-19. No bead carries
the claimant's note, and none carries both, which is what the stall leaves.
The race is rare here, so the change removes the bare sends outside retiring
code and adds nothing that detects or repairs the stall.

## The gap left in place

Gas City clears the claim route after the pour rather than before it, so a
raw route followed by `gc sling --on` still leaves the window open. By my
reading, not built, the fix at the source is small: clear the bead's
`gc.routed_to` before `InstantiateSlingFormula` on the `NeedsAttach` path, so a
pool worker cannot meet a raw route once a pour starts, plus a test of that
order. tk-ov8s4vi records it as a Gas City finding, set aside with nothing sent
upstream.
