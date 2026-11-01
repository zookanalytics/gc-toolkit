---
name: Gas City search for the removed-script hold and the open-step census
description: The arch check asks a change that adds pack surface to show why Gas City does not already cover it. Read this when checking whether the pack still needs assets/scripts/script-callers.sh or the removed-script check in gctk merge, when Gas City ships a run that keeps the pack files it was poured from, when gc beads list gains a text filter, or when bd says whose a gate is.
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
filters for the reads in one store, `gc rig list` for the set of stores, and the
refinery's rejection for the repair. The decision of when a removal may land is
the pack's, because the pack's own rule, that step text calls a tested script,
is what makes a run depend on a script by name.

Upstream was read at these commits, on 2026-11-01:

- `gastownhall/gascity` 688b5c4e0acd
- `gastownhall/gascity-packs` 0b0d96250f66, and the Gas Town pack at its
  bundled pin cb6a612882b8 (`PublicGastownPackVersion`, package config)
- `gastownhall/beads` 6ebaacba8f5f

## The surface and the need

The change adds:

- `assets/scripts/script-callers.sh`, whose two modes are a census of the open
  steps that name a script, which also says which of them sit in a parked run,
  and `--check-merge <base> <head>`, which answers whether a merge may remove a
  pack script yet.
- A check in `gctk merge`, right before `gh pr merge` on a pull request into the
  default branch, that holds on the answer. When a formula at the base or the
  head names the script, it hands the branch back through the existing
  `rejection-repool.sh`, a new caller of that script and of its existing
  `pull_request` to `poured` edge. When only the rig checkout's HEAD names it, or
  open steps in moving runs call it, the arm records the existing `pr.machine`
  value `settled`. When a person's gate or a suspended rig parks a calling run,
  it records the existing value `blocked` with the existing cause `blocker`, whose
  definition
  widens to cover a blocker that holds the merge through a run. It files no gate.

It adds no metadata key, bead kind, lifecycle state or cause.

The census has to find, across every store of the city,
the open steps whose poured text names a script, and to say so when a store
could not be read, because "no caller" from a store nobody read would let a
deletion through. The hold has to answer at the merge, about the merge result,
because that is when a removal starts to reach the city. That is a merge into the
default branch, which the rig checkout follows. A merge into an integration
branch reaches no copy of the pack, and the landing PR lists what it removed. The
repair has to reach an agent, since the check names the remedy and a person has
nothing to decide. And a wait only a person can end has to read as that person's,
at the PR and on the board, for as long as it stands.

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
  `--has-metadata-key` and `--status`
  ([bd list](https://beads.gascity.com/cli-reference/list)). The script reads
  each store once for its open steps, through the pack's `bd_list`, and matches
  each name whole in their text. `--desc-contains` is a case-insensitive
  substring and takes one read per script per store, inside a merge pass with a
  time budget.
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
  the nearest native seam, and the change uses it where it fits: a formula that
  names the script is a failure the branch owns, so the branch goes back to a
  polecat. When only open steps call a script, or only the checkout names it,
  nothing on the branch has to change, so a rejection is the wrong answer there.
  The pack lands through `gctk merge` today. The migration member that moves
  landing onto Gas Town's flow (tk-1tfzr71.20) carries this hold on its notes, to
  settle in its design.
- **A native wait on each calling step.** A bd `bead` gate is the nearest wait
  across stores, but core's `gate-sweep.sh` skips bead gates ("Bead-type gates are
  skipped"), so nothing would clear it. It would also add a write per calling step
  for a state each merge pass can read again.
- **The repair.** `rejection-repool.sh` is the pack's form of that rejection: it
  records the reason, keeps the PR through `existing_pr`, and pours the work
  formula with `gc sling`, because a route on the bead would not survive a park
  on its epic. The nearer word, `rework-child.sh`, files a child that blocks the
  anchor, but it takes a source that is a review or a ruling, and a merge hold is
  neither. It retires under the deletion plan, so it gets no third source.
- **A person's ask, which the formula answer does not need.** A human gate through
  `human-gate.sh` is how `gctk merge` asks a person something. Here nobody has a
  decision to make, and a choice the worker cannot make goes through the worker's
  own gate.

## Telling a parked run from a moving one

A parked run ends only when a person acts, so the merge has to read as held by a
person. What decides it is which of a store's open steps a gate blocks, whether a
person holds that gate, and whether the store's rig is suspended.

- **The edges: bd's list rows, which the script already reads.**
  [bd list](https://beads.gascity.com/cli-reference/list) carries each row's
  `dependencies` (`Issue.Dependencies`, package types), so the read the census
  makes for a step's text gives its edges at no cost.
- **`bd blocked`, which does not add to that.**
  [bd blocked](https://beads.gascity.com/cli-reference/blocked) answers each
  blocked bead with the ids of its blockers (`BlockedIssue.BlockedBy`, package
  types), and not their types, so it needs the same second read, over every
  blocked bead in the store rather than the steps. On a chained run it names the
  gate only on the step the edge sits on, so it answers no more than the edges do.
- **The gates: bd's list again.** The second read is `bd list --type gate
  --include-gates`, once per store and only when that store holds a caller. It
  goes through the pack's guarded `bd_list`, so a failed read is exit 2.
  [bd gate](https://beads.gascity.com/cli-reference/gate) has `bd gate list`, which
  shows open gates and stops at 50 unless told otherwise (`gateListCmd`), where the
  list read takes the statuses the census takes.
- **Whose gate it is: core's sweep.** [bd
  gate](https://beads.gascity.com/cli-reference/gate) names the types, and the core
  pack's `gate-sweep.sh` runs `gc bd gate check` for timer and gh gates and no
  others, so those close on their own and every other gate stays open until
  someone closes it. Gas City ships no predicate for this, and the pack's own
  `human_gate` asks for `await_type=human`. That misses a park, the plain gate
  `gc-helm.sh park` files with no await type, which holds every parked run today.
- **A suspended rig: the rig list, which the script already reads.**
  [`gc rig suspend`](https://docs.gascity.com/reference/cli#gc-rig-suspend) says the
  reconciler skips the rig's agents, `gc hook` returns empty and the rig's store
  stays open, so its runs stay open and nothing works them until a person resumes
  the rig or cancels them. `gc rig list --json` carries each rig's `suspended`
  (`RigListItem`, package main), so this adds no read.
- **The runs API, which does not cover it.** `RunStep` carries no edge, as above.
- **An edge from the anchor onto the gate, which does not fit.** It is the shape a
  wait usually takes, and it would read as `held: gate` by itself. bd resolves an
  edge only within one store, and a caller's gate can sit in another rig's store.
  A gate also outlives a run cancelled from under it: a park holds many beads, so
  the anchor would stay held after its caller ended, and each pass would have to
  add and remove edges. The verdict is re-derived on every pass and leaves nothing
  to clean up.
- **The surface: the pack's machine axis.** A blocked verdict is what the status
  label and the board already read as a person's hold, as the Machine axis warrant
  records. The cause is the existing `blocker`, so no reader changes.

## What it leaves out

A gate in another store than its step holds nothing, so the parked read looks only
in the step's own store. A person can hold a run some other way, such as a live
blocker routed to them, and that run reads as moving. The check reads a formula's
file and each open step's text. A `description_file`
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
- Gas City or bd ships a predicate for whether a person holds a gate. The parked
  read then composes it in place of the rule it carries.
- The landing moves onto Gas Town's flow (tk-1tfzr71.20). `gctk merge` retires
  with that member, and the hold moves with its design.
