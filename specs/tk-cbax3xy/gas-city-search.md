---
name: Gas City search for the claim-context read
description: The search the arch check asks for before claim-context.sh, the one read a pool session orients from after gc hook --claim. What Gas City, the packs it bundles and publishes, and bd ship for learning a claimed step's instructions, its workflow and the work its input convoy tracks, read at named upstream commits, and why the pack composes two bd show reads. It also separates the step_reminder that the gc this city runs puts on claim results from what Gas City ships. Read it when checking whether the pack still needs this read, or whether Gas City now returns a claim's context itself.
---

# Gas City search for the claim-context read

`assets/scripts/claim-context.sh` is the read a polecat session makes after
`gc hook --claim --json` to learn what it claimed: the step's `gc.step_ref`
and instructions, the workflow root with its formula and input convoy, and the
work bead's status, assignee, metadata, notes and description. The arch check
asks what Gas City already ships for that
([review-arch.md](../../docs/review-arch.md#the-checks), check 1). Gas City
answers a claim with identifiers. It delivers a step's instructions through
provider hooks when a session starts and when a prompt is submitted, so a step
that a session claims during its turn is not among them. No Gas City command
goes from a claimed step to the beads its input convoy tracks. `bd show`
returns a bead with each of its dependencies as a whole row, and a graph.v2
step's record carries its workflow root that way, so the script composes two
`gc bd show` reads. It writes nothing and adds no noun.

## The surface and the need

The script is operational surface: a script under `assets/scripts/`
([review-arch.md](../../docs/review-arch.md#when-the-lens-applies)). The
change's other files are prompt text (the claim contract in the polecat
doctrine and the two polecat nudges), the script's test, its row in the
component model and the seed-audit renders. None of them is operational
surface.

The need is orientation. A fresh pool session's first claim of a
`mol-polecat-work` or `mol-review` step must learn the step's instructions,
the workflow it belongs to, and the state of the work bead that the step's
blocks act on. That state is the bead's status and assignee, its metadata
(a branch to resume, a rejection reason, a target), the notes that carry
dispatch corrections, and its description. The claim contract used to
prescribe `gc bd show <id> --json | jq '.[0].metadata'`. That read returns
neither the step's instructions nor the work bead, so a session read the
step, its root and the work bead again before it started.

## Where the search looked

Each was read on 2026-10-26:

- Gas City at main `f78779e41522`, the commit the arch review read: the CLI
  reference, the supervisor API's OpenAPI schema, the engineering docs, the
  `core` pack it bundles, the hook settings it installs for each provider, and
  its source. The source was searched for the claim result's fields,
  `step_reminder`, the step reminder's renderer and its callers,
  `hook current`, `gc.input_convoy_id` and the edges a graph.v2 workflow is
  created with. Each hit outside the tests was read.
- Every pack Gas City publishes, at `dac12a4a802c`. Each pack was searched for
  `hook --claim`, `hook current`, `gc.input_convoy_id`, `mol current`,
  `show --current`, `prime --hook`, `nudge drain` and `step_reminder`, and for
  any mention of a claim, and each hit was read. Gas City bundles `gastown`
  and `gascity` from the packs at `66c672b5ed00`. Their claim instructions
  there differ from the head, so both are described below.
- bd at `249d7cde74db`: the JSON that `bd show` returns, its flags,
  `bd show --current` and `bd mol current`.

Each passage cited below from Gas City's and bd's documentation was also found
on the live sites, docs.gascity.com and beads.gascity.com.

## What Gas City ships

**A claim result carries identifiers.** The
[CLI Reference](https://docs.gascity.com/reference/cli#gc-hook) says that
`gc hook --claim` runs "the standard startup claim protocol for one work item"
and that `--json` emits "a JSON protocol result". In the `gc` command's
source, that result is `hookClaimJSONResult`. It holds the schema version,
`ok`, the command and the action, the reason, the bead id, the assignee and
the route, the root bead id, the continuation group with the continuation
beads assigned alongside the claim, and whether a drain was acknowledged. It
carries no step text and no bead record.

**`gc hook current` names the claim.** The CLI Reference's
[`gc hook current`](https://docs.gascity.com/reference/cli#gc-hook-current)
section says it prints "the work bead this session most recently claimed",
which it reads from the stamp the claim protocol writes on the session's own
bead. Gas City's "work bead" here is the bead the claim names, and for a
graph.v2 run that bead is the step. `doHookCurrent` prints the bead's id and
the session that claimed it, or the id alone with `--id-only`, and reads no
bead.

**A step reminder carries a step's instructions, written when a hook runs.**
`formatWispStepReminder` in the `gc` command renders a step as a
`<system-reminder>` block that holds the step's title, id and description
under "Your current active work assignment". `gc prime --hook` writes it when
a session starts, and `gc nudge drain --inject` writes it each time a prompt
is submitted. The settings that package `hooks` installs for Claude, and the
hook file the `core` pack ships for Codex, run the first at SessionStart and
the second at UserPromptSubmit. The controller serves the same step at
`GET /v0/city/{cityName}/work/active-step`, whose body in the supervisor API's
OpenAPI schema (`WorkActiveStepBody`, `ActiveWorkStep`) holds the step's id,
title and description. `resolveActiveWispStep` picks the step from what is in
progress for the session's identities when the hook runs. It takes an
in-progress molecule or wisp root and that root's in-progress or entry step.
Failing that, it takes the root that a claimed or routed bead's `molecule_id`
names, and then the newest in-progress bead with a description. A pool session
claims its step during its turn, after that turn's prompt hook has run, so the
step it claims is in no reminder until another prompt arrives. A reminder
carries no workflow, no input convoy and no work bead.

**A bead's record carries its dependencies whole.** bd's `show --json` returns
each bead with its dependencies as whole rows, each with its dependency type
(package `types`, `IssueDetails` and `IssueWithDependencyMetadata`). The
[bd show](https://beads.gascity.com/cli-reference/show) page says that
`--brief-deps` "drops description, design, notes and acceptance criteria"
from each dependency, and without that flag a dependency keeps them. Gas City
links the steps of a graph.v2 workflow to its root with a non-blocking
`tracks` edge (package `molecule`, `buildRecipeApplyPlan`), so a step's record
carries the root and the root's metadata. The root records its formula as
`gc.formula_name` (package `formula`, `toRecipeWithGraph`) and its input
convoy as `gc.input_convoy_id`. A convoy's record carries each bead it tracks
the same way. `gc bd` routes each read to the store that holds the bead
([CLI Reference](https://docs.gascity.com/reference/cli#gc-bd)).

**A graph.v2 run takes its work from an input convoy.** The engineering doc
"Convoy-First Formulas And Drain V0" makes every targeted graph.v2 invocation
"think in terms of an input convoy". A target that is a single bead becomes "a
visible real convoy containing that one bead", the formula receives
`convoy_id`, and "formulas inspect membership instead of special per-bead
metadata". The root records that convoy as `gc.input_convoy_id`. A
`mol-polecat-work` run's work bead is its input convoy's one member, so the
pack's work bead is the input this contract defines.

**No command goes from a claim to its input convoy's members whole.**
[`gc convoy status`](https://docs.gascity.com/reference/cli#gc-convoy-status)
shows "a table of all child issues with their status and assignee". Its JSON
(`writeConvoyStatusJSON`) gives each member's id, title, status, type and
assignee, without metadata, notes or description.
[`gc graph`](https://docs.gascity.com/reference/cli#gc-graph) prints a set's
beads with their status and what blocks them, and
[`gc beads show`](https://docs.gascity.com/reference/cli#gc-beads-show) shows
one bead. Each takes an id the session must already know, and none starts from
a claim.

**`bd mol current` and `bd show --current` answer other questions.**
[`bd mol current`](https://beads.gascity.com/cli-reference/mol#bd-mol-current)
shows "where you are in a molecule workflow": each step's state, with a hint
to run `bd show` on a step for its instructions. It loads a molecule through
parent-child edges (package `issueops`, `LoadMolecule`), so it does not reach
a step that is linked to its root only by a `tracks` edge, and the `core`
pack's `graph-worker` prompt tells a graph.v2 worker not to use it.
`bd show --current` shows one bead, the in-progress one assigned to the actor
(`resolveCurrentIssueID`), which a session already names from its claim.

**The packs read the claimed bead and resolve the work in their steps.**

- The `core` pack's `graph-worker` prompt claims with
  `gc hook --claim --drain-ack --json`, reads the claimed bead with
  `gc bd show <id>`, and executes "exactly that bead's description". Its
  `pool-worker` prompt reads a bead's `molecule_id` and walks that molecule
  with `gc bd mol current`.
- The build pack `gascity` has a `gc-role-worker` fragment, which the worker
  prompts of `bmad`, `compound-engineering`, `gstack`, `profiler` and
  `superpowers` also include. The fragment claims, re-reads the claimed bead
  with `gc bd show` to verify it, and keeps the claimed, root and continuation
  ids. At `66c672b5ed00` it does this in an inline block. At the packs' head
  it runs the pack's `claim` command, which returns those ids with the claimed
  bead's whole record. The worker then executes the claimed bead's description
  and result contract. The steps of the pack's `do-work` workflow find their
  work themselves. Its `prepare-worktree` step reads the root's
  `gc.input_convoy_id`, reads that convoy with `gc bd show`, takes the source
  anchor from it, and stamps the anchor on the root as `gc.source_anchor_id`
  for the later steps. The `claim` command reads an input convoy only to
  declare an explicit run's work to an observer (`declare_explicit_work`), and
  it prints none of that convoy.
- The `gastown` pack's polecat claims in a scripted block, re-reads the
  claimed bead with `gc bd show` to check that it owns the bead, and prints
  the bead's metadata. At `66c672b5ed00` the prompt's read is
  `gc bd show <id> --json | jq '.[0].metadata'`, the line this pack's claim
  contract carried before this change. The polecat then reads its formula's
  steps. At the packs' head, its resume path takes the work bead from
  `gc convoy status` and reads it with `gc bd show`.
- `contributing-to-gascity`, `pr-pipeline` and `pr-review` find their
  molecule's root with `gc bd mol current --json`.
- The other packs mention no claim.

**The `gc` this city runs adds a step reminder to its claim results, and Gas
City does not.** The installed `gc` is built from a fork of Gas City. Its
`hookClaimJSONResult` has a `step_reminder` field. `hookClaimStepReminder`
sets it on `existing_assignment` and `ready_assignment` results, and leaves it
off a `claimed` result, whose session made the claim on that same call. It
renders the claimed step through Gas City's own `formatWispStepReminder`. Gas
City's `hookClaimJSONResult` at `f78779e41522` has no such field, so this
record does not count the field as something Gas City ships.

## What the change does with it

The script composes Gas City's reads. It reads the claimed bead with
`gc bd show`, and that record carries the root through the `tracks` edge. It
then reads the root's input convoy with `gc bd show`, and that record carries
the work bead whole. When the step's record lacks the root, a third read
fetches it. The script prints the step's title and description in the shape
the step reminder uses, the root's formula and convoy, and the work bead's
fields. It writes nothing. It adds no metadata key, no bead kind and no
lifecycle state, and it expresses no claim lease, assignment, continuation
group or wait. So it is glue that runs native calls as one call, and it needs
no warrant ([review-arch.md](../../docs/review-arch.md#the-checks), check 2).

Its work bead is the convoy-first contract's input, the input convoy's
member, and `mol-polecat-work` requires exactly one. When a convoy tracks none
or several, or a workflow has no input convoy, such as one an order pours, the
read says so and prints no work bead.

The other reads do not cover the need. A reminder holds only the step, and a
hook writes it before the turn in which the session claims. `gc convoy status`
lacks the work bead's metadata, notes and description, which the convoy's
`gc bd show` record already carries. The build pack's `claim` command returns
the claimed bead whole, which covers the step, but its workers' contract is
that bead alone. A `mol-polecat-work` step acts on its input convoy's member,
so the convoy read stays.

The read does not depend on the fork's field. Called with no flag, it prints
the step's instructions whatever the claim's reason. `--no-step` drops them
only for a result whose `step_reminder` already carries them. Under Gas City
as shipped no result carries one, so a session runs the read as written after
each claim and learns the same things.

The capability Gas City lacks is a read from a claim to the work that its
workflow's input convoy tracks. The claim result names the step and its root,
a reminder carries the step's text when a hook runs, and every other read
takes one bead or one convoy's summary. The packs fill the gap in their own
steps. The build pack's `prepare-worktree` resolves the work and stamps it on
the root, and `gastown`'s resume path reads the convoy and then the bead.

This answer changes if Gas City's claim result, or a command it ships, returns
a claimed step's instructions together with its input convoy's members whole.
The script should then compose that read, or be retired. At `f78779e41522`
neither does.
