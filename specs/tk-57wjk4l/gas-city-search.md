---
name: Gas City search for the removed-script hold and the open-step census
description: The arch check asks a change that adds pack surface to show why Gas City does not already cover it. Read this when checking whether the pack still needs assets/scripts/script-callers.sh or the removed-script check in gctk merge, when Gas City ships a run that keeps the pack files it was poured from, or when gc beads list gains a text filter.
---

# Gas City search for the removed-script hold and the open-step census

A run keeps the step text it was poured with, and that text calls the pack's
scripts from the pack as it stands when each step runs. A merge that removes a
script stops every open step that names it once the city's copy of the pack
takes the merge. The change adds a census of those steps and a check in the
merge that holds such a removal. The arch check asks what Gas City already ships
for this ([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships no way to keep a run on the pack revision it was poured from, and
detects formula drift only after the fact. It handles a missing script only for
a step's declared check, and only once the script is gone. It ships no list of
beads across stores that filters on text and reports a store it could not read.
So the change composes what Gas City ships for each part it has: bd's list
filters for the read in one store, `gc rig list` for the set of stores, and a
human gate for the ask. The decision of when a removal may land is the pack's,
because the pack's own rule, that step text calls a tested script, is what makes
a run depend on a script by name.

Upstream was read at these commits, on 2026-11-01:

- `gastownhall/gascity` 688b5c4e0acd
- `gastownhall/gascity-packs` 0b0d96250f66, and the Gas Town pack at its
  bundled pin cb6a612882b8 (`PublicGastownPackVersion`, package config)
- `gastownhall/beads` 6ebaacba8f5f

## The surface and the need

The change adds:

- `assets/scripts/script-callers.sh`, whose two modes are a census of the open
  steps that name a script, and `--check-merge <base> <head>`, which answers
  whether a merge may remove a pack script yet.
- A check in `gctk merge`, right before `gh pr merge`, that holds on the answer.
  It files one human gate under a new situation key,
  `script-callers-merge-gate.<n>`, when a formula still names the script. When
  only open steps call it, the arm records the existing `pr.machine` value
  `progressing` and files nothing.

It adds no metadata key, bead kind or lifecycle state.

The need has two parts. The census has to find, across every store of the city,
the open steps whose poured text names a script, and to say so when a store
could not be read, because "no caller" from a store nobody read would let a
deletion through. The hold has to answer at the merge, about the merge result,
because that is when a removal starts to reach the city.

## A run that keeps what it was poured from

This is the other shape the bead asked about, and it would remove the need for
the hold.

- **What a run keeps.**
  [Understanding Formulas](https://docs.gascity.com/guides/understanding-formulas)
  says applying a formula materializes its steps as beads, "and from that moment
  the work is independent of both the formula file and any agent session". That
  covers the step's text. Nothing there, or in the spec's
  [root stamping](https://docs.gascity.com/reference/specs/formula-spec-v2),
  records the pack files that text will call: the root carries
  `gc.formula_hash`, a hash of the formula file's bytes, and
  `gc.formula_source`, the file's path.
- **Drift.**
  [`gc formula version-check`](https://docs.gascity.com/reference/cli#gc-formula-version-check)
  compares that hash with the formula on disk and exits 1 when they differ. It
  detects, and changes nothing. A change that removes a script without editing
  the formula leaves the hash equal, so it reads as no drift.
- **Which revision a city runs.** An import selects a revision through the
  importing file and the lockfile
  ([Understanding Packs](https://docs.gascity.com/guides/understanding-packs),
  "Version constraints and the lockfile"). The pin belongs to the import, not to
  a run, and no key on a run's root names a pack revision.
- **Reading at a ref.** `GC_FORMULA_REF` (`SourceFromEnv`, package formula) makes
  a process read formula and description files at a git ref. It serves formula
  reads, is set per process, and leaves a step's script lookup alone.

Pinning would also be the wrong shape here. A run held on its pour's scripts
keeps writing whatever those scripts wrote, after the cutover that retired it,
and the pack's hand-offs exist to stop that.

## What Gas City does when a step's script is gone

The one script a formula step declares is its check. The spec's
[section 3.1](https://docs.gascity.com/reference/specs/formula-spec-v2#3-1-check),
under "A check that cannot be launched", says the step stays open rather than
failing, the orchestrator re-checks it every sweep, "the fix is out of band
(ship the script, `chmod +x` it)", and a stall emits one `control.stalled` event.
So Gas City also resolves a step's script when the step runs, and it answers a
missing one after the fact. It covers `check.path` only. A check runs after a
step's work, so it cannot stand in for the calls this pack's step bodies make.

The exposure comes from how this pack writes its steps. Core's formulas name no
`.sh` file, and neither do the Gas Town pack's formulas at its bundled pin. In
the rest of the packs repository the formula lines that name a script to run are
`check.path` entries. Its step assets name those same check scripts, mostly in
prose such as "this stage is gated by", and in one form an agent runs by hand
(`GC_BEAD_ID=<claimed-step-id> .gc/scripts/checks/build-artifact-valid.sh`). This
pack's [rule](../../docs/pack-authoring.md#step-text-calls-a-tested-script) that
step text calls a tested script holds procedures out of step text, and the price
is a step that depends on a script by name. Nothing upstream had to solve that.

## A census across stores

- **In one store: bd, which the script composes.** `bd list` takes
  `--desc-contains` and `--has-metadata-key`
  ([bd list](https://beads.gascity.com/cli-reference/list)). The script reads
  each store with both, through the pack's `bd_list`, and then matches the name
  whole, since `--desc-contains` is a case-insensitive substring.
- **The set of stores: `gc rig list`, which the script composes.** Core's own
  scripts read the rig list the same way (`cascade-nudge-on-blocker-close.sh`,
  `cross-rig-deps.sh`, `notify-on-human-gate-creation.sh`).
- **`gc beads list`, which does not cover it.** It is the native read across
  stores ([gc beads list](https://docs.gascity.com/reference/cli#gc-beads-list)),
  and it filters only on label and status, so the script would filter every
  nonclosed bead in the city on the client. The larger problem is a rig's store
  that fails. `humaHandleBeadList` reports `partial` and `partial_errors`, but
  `Client.ListBeads` (package api) returns only the rows and the cache age, so
  `routeBeadsList` cannot show the failure, and the store reads as having no
  rows. A hold that took that as "no caller" would pass the deletion.
- **The runs API, which does not cover it.** `GET /v0/city/{cityName}/runs` and
  `/runs/{run_id}/steps` list runs and their steps. `RunStep` carries an id, a
  title, a status, a kind and an assignee, and no text. The list is capped
  (`maxRunsListLimit`), and gc has no command for it.
- **bd's multi-repo hydration, which does not cover it.** `bd repo` adds other
  repositories to a store's `repos.additional`, to read them as one database. The
  city keeps its stores apart, and a census should not change what each store
  answers for every other reader.

## A hold at the merge

- **A pack doctor check.** The guide's
  [Encode known mistakes as doctor checks](https://docs.gascity.com/guides/multi-agent-engineering-environment#encode-known-mistakes-as-doctor-checks)
  is the nearest primitive for a recurring mistake. `PackScriptCheck` (package
  doctor) runs in the directory of the pack the city loaded, on `gc doctor`, so
  it could report a stranded step only after the deletion reached the city, when
  the step has already stopped. The built-in `pre-start-scripts` check verifies
  that a script an agent's `pre_start` names exists on disk, the same question
  for one config key, and it reads no step text.
- **`gc lint`.** `lintFormulaFiles` reports only `GraphV2OutputJSONWarnings`, from
  a fixed list a pack cannot add to, and it reads whole files rather than a
  change.
- **A rig's `lint_command`.** Core's `mol-polecat-base` runs it during a
  polecat's own run. That is too early for this question: runs poured after it,
  and a branch that lands days later, would go unseen.
- **Gas Town's refinery.** Its `mol-refinery-patrol` runs the rig's
  `lint_command` and `test_command` as it lands a branch, and a failure the
  branch caused puts the bead back in the pool with `rejection_reason`. This is
  the nearest native seam. It answers at the right moment, but a rejection sends
  work back to a polecat, and when only open steps call a script nothing on the
  branch has to change, so a rejection is the wrong answer there. The pack lands
  through `gctk merge` today. The migration member that moves landing onto Gas
  Town's flow (tk-1tfzr71.20) carries this hold on its notes, to settle in its
  design.
- **A native wait on each calling step.** A bd `bead` gate is the nearest wait
  across stores, but core's `gate-sweep.sh` skips bead gates ("Bead-type gates are
  skipped"), so nothing would clear it. It would also add a write per calling step
  for a state each merge pass can read again.
- **A person's ask.** The hold that needs a person composes Gas City's human gate
  through the pack's `human-gate.sh`, as every other hold in `gctk merge` does.

## What it leaves out

The check reads a formula's file and each open step's text. A `description_file`
over 4096 bytes reaches a step as a pointer to the file
([section 1.8](https://docs.gascity.com/reference/specs/formula-spec-v2#1-8-description-files)),
so its text would be in neither place. No formula in this pack declares one. A
change to a script's interface, and an inline block that writes a retired shape,
are outside the check, and tk-1tfzr71.36 tracks them.

## What would change this answer

- Gas City ships a run that resolves pack files at the revision it was poured
  from. The hold then has nothing to protect, and only the cutover question is
  left.
- `gc beads list` gains a text filter and reports a store it could not read. The
  census then composes it in place of the per-store loop.
- The landing moves onto Gas Town's flow (tk-1tfzr71.20). `gctk merge` retires
  with that member, and the hold moves with its design.
