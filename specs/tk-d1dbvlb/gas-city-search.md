---
name: Gas City search for the store-only exit's validating closer
description: The arch check asks a change that adds pack surface to show why Gas City does not already cover it. Read this when checking whether the pack still needs assets/scripts/store-only-exit.sh --done, or whether Gas City now closes a bead whose run ends with no commit.
---

# Gas City search for the store-only exit's validating closer

A store-only run is a `mol-polecat-work` run whose whole product is store work,
such as a live verification or a bead filed in another store. It has no branch
for the refinery to land, so the run's submit step releases the work bead open,
unassigned and unrouted. When the record the run wrote finishes the bead, the
change hands the bead to its validating closer instead of leaving it to read as
work not yet done. `assets/scripts/store-only-exit.sh --done` appends the run's
close brief to the bead's notes, holds the bead on the root of its run with a
`blocks` edge, and arms `mol-validate-close` through the pack's deferred
dispatch. Once the run ends, the closer checks the record against live state,
then closes the bead as done or asks the operator. The arch check asks what Gas
City already ships for this
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City and its packs close a work bead on the word of the run that worked it,
once its branch lands, or in a verifier step that a formula pours into every
one of its runs. In Gas Town, a polecat run with no commit to land ends with a
person or a coordinator. Nothing ships a check that runs after a no-commit run
has ended and closes its bead as done. So the hand-off composes what Gas City
ships for each part it has: a `blocks` edge to hold the bead until the run ends,
the step a session claimed to name the run, and the typed work record for the
close. The pour after the run ends is the pack's deferred dispatch, because Gas
City ships no sling on unblock. The check is `mol-validate-close`, the closer
the pack already runs for a first reaction's close.

## The surface and the need

The change adds:

- `assets/scripts/store-only-exit.sh`, which the store-only arm of
  `mol-polecat-work`'s submit-and-exit step runs. Its refusal of a run that has
  work to land (a commit ahead of the base, an uncommitted change, or the branch
  on origin) was a procedure in the step text, and it moved into the script
  under rule 2 of the [built-once target](../../docs/built-once-target.md#the-rules).
  Its `--done` mode is new: the brief, the hold and the arm.
- A third case in `mol-validate-close`'s check, the store-only exit's brief,
  whose close records the bead as done.
- The brief's heading in the bead's notes,
  `## Close brief (store-only exit, <time>)`, which the closer reads.

It adds no bead kind, lifecycle state or metadata key. The hold is a bd
`blocks` edge, the arm is the `gc.dispatch_when_ready` that
`deferred-dispatch.sh arm` already writes, and the close writes Gas City's own
`gc.work_outcome`. So it adds no pack noun and needs no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2).

The bead asks that a store-only exit whose record finishes its bead never leave
that bead reading as pending work: either the bead closes on a check that
confirms the record, or the exit files the close as a demand the operator owns.
A sitting that closed such a bead by hand also found it had no honest way to
record the close as done. Holding that takes four things:

1. Something closes the bead once its run's record finishes it, without a
   person noticing the bead first.
2. The close rests on a check of the record against live state, not on the
   run's own word, and a record the check does not confirm reaches the
   operator.
3. The close records the bead as done, not as work that was never needed.
4. The check reads the record the run left after the run's last write to the
   bead, and never acts on the bead while the run still writes to it.

## Where the search looked

Each was read on 2026-10-30 (UTC):

- Gas City at main `3f3224faaeff`: the CLI reference for `gc sling`,
  `gc hook current` and `gc session wait`; the formula specification's steps,
  conditions, routing intent, check and on-complete sections; the orders
  tutorial; the `core` pack's formulas and orders. In its source: the workflow
  finalizer and the source-bead close (package dispatch), the attach path of
  `gc sling --on` and its live-workflow check (package sling), the work-record
  close gate (packages workrecord and beadmeta), the on-complete fan-out
  (package dispatch), readiness (package beads) and the `human` label
  (packages beadmeta and config).
- Gas City's packs repository at main `0b0d96250f66`, and the commits Gas City
  pins its public packs to: `gastown` at `cb6a612882b8` and `gascity` at
  `5bf643ca55bd` (package config, `PublicGastownPackVersion` and
  `PublicGascityPackVersion`). Every pack was searched for each command that
  closes a bead (`bd close`, `--status=closed`, and the Go and Python that build
  one), and each hit was read for the bead it closes and the evidence behind the
  close. The `gastown` polecat and refinery formulas were read for a run with
  no commit, the `gascity` pack's `do-work` and `implementation-base` formulas
  for their close step, and every formula for `[steps.on_complete]`.
- bd at main `f7b94653eb89`: its `human` command and its gates.

Each passage quoted below from Gas City's and bd's documentation was also found
on docs.gascity.com and beads.gascity.com.

## What Gas City and the packs ship

**A workflow that passes closes the bead it was launched from, and a
convoy-first launch names none.** When a workflow root finishes with
`gc.outcome=pass`, its finalizer closes the bead the root names in
`gc.source_bead_id` and each source above that one (package dispatch,
`closeSourceBeadChain`). `gc sling <pool> <bead> --on <formula>` launches a
graph.v2 formula convoy-first, and that branch passes an empty source on
purpose: "the source is tracked through the input convoy, not
gc.source_bead_id" (package sling, `attachFormulaToBead`). `mol-polecat-work`
is launched that way, so its finalizer closes nothing outside the run. Where
the source close does apply, it follows from the run passing, with no check of
what the run recorded.

**The work record types a close, and `no-op` is the value for one that ships no
commit.** Gas City's work record (ADR-0009, which package beadmeta cites) puts
the close's disposition in `gc.work_outcome`, one of `shipped`, `no-op`,
`blocked` and `abandoned`. Its close gate (package workrecord, `Gated` and
`ValidateOnClose`) covers plain task beads, and it requires a `shipped` outcome
to name a `gc.work_commit` reachable on `gc.work_branch`. For the rest, "no-op /
blocked / abandoned carry their reason in the close-reason; no commit artifact
is required". The gate only warns unless `GC_WORK_RECORD_ENFORCE` is set to a
true value. The `core`
pack's `mol-do-work` describes `no-op` as "the bead needed no change (already
satisfied / duplicate)". `gc.work_verification` is "the verification record ...
backing a shipped outcome" (package beadmeta), and no Go code in Gas City reads
it. So the record has no value for finished work that ships no commit, and the
close reason is where a close says the work was done.

**A run closes its own work bead.** In the `core` pack, `mol-do-work` closes
its work bead with "Done:" or "No-op:" and a typed outcome, `mol-polecat-report`
writes its findings to the bead's notes and closes it with "Report:", and
`mol-polecat-commit` and `mol-prompt-synth` close theirs once their commit or
file is written. Among the published packs, `pr-pipeline` and `contributing-to-gascity`
close their run's root with the path of the report it wrote, `github` and
`discord` close the issue bead they were given, and `gastown`'s crew and dog
prompts, `mol-digest-generate` and `mol-review-leg` close the work they were
assigned. Each close rests on the word of the run that makes it. The Go and
Python services in `github`, `discord` and `slack-full` close only an intake
message or a failed dispatch.

**A polecat's work bead closes when its branch lands, and a run with no commit
goes to a person.** `gastown`'s refinery closes a work bead when it merges the
bead's branch, or finds the branch already merged, and its witness closes an
orphaned one whose branch is already on main. At the packs repository's main,
its `pr-merge-reconcile` command also closes one whose pull request has merged.
In the pinned `gastown`, a branch with no change against its base reaches the
refinery, whose `halt_false_completion` blocks the bead, routes it to `human`,
records `merge_result=refused_false_completion`, and nudges the mayor and the
witness. At the packs repository's main, `mol-polecat-work` stops such a run
before the push: its content gate records `halt_reason=no_commits`, leaves the
bead open, unassigned and unrouted, and nudges the mayor and the witness. It
tells the polecat that a run whose honest answer is that no code change is
warranted "is a legitimate outcome — but it is reported, not handed off."
Either way the bead closes only when the person or coordinator the nudge
reaches closes it. That is the release the store-only exit made before this
change.

**The build pack closes its anchor in a verifier step of every run.** The
`gascity` pack's `do-work` and `implementation-base` formulas end in a
`close-source-anchor` step, routed to another role through its step metadata,
`gc.run_target = "gc.run-operator"`. A step's `gc.run_target` "is compile-time
routing intent: at dispatch the router resolves it into `gc.routed_to`"
([Formula Specification v2](https://docs.gascity.com/reference/specs/formula-spec-v2#2-compilation)).
The step verifies the implementation commit and its summary in the worktree and
closes the source anchor with the commit in its reason. `do-work`'s implement
step also carries an exec check of the build artifact. `bmad`'s story
development, `compound-engineering`'s work, `gstack`'s work and `superpowers`'
development formulas extend `do-work` and keep its close step. The step is the
same at the pinned `gascity`.

**A formula chooses its steps when it is poured.** "A step `condition` is a
compile-time include/exclude filter evaluated during compilation, before any
beads exist"
([Formula Specification v2](https://docs.gascity.com/reference/specs/formula-spec-v2#1-5-conditions)).
`[steps.check]` runs a script after each iteration of its step, and `exec` is
the only checker mode it supports
([3.1. Check](https://docs.gascity.com/reference/specs/formula-spec-v2#3-1-check)).
`[steps.on_complete]` "is a runtime for-each fan-out over the step's structured
output: when the step completes, a formula is instantiated for each element of
a collection in its output"
([3.4. On-Complete And Tally](https://docs.gascity.com/reference/specs/formula-spec-v2#3-4-on-complete-and-tally)).
The fan-out compiles that formula as an expansion fragment and grafts it into
the same run (package dispatch, `processFanout`), and the fan-out's control
holds the run's later steps until the fragment completes. The compiler marks
the source step as owing structured output, and the same section calls `drain`
"the graph-native canonical fan-out". No formula in the `core` pack, the packs
repository or the pinned packs uses `[steps.on_complete]`.

**Gas City lets a second formula run on a live bead, and pours it at once.**
`gc sling --on` instantiates the formula and starts its workflow in the same
call, and no flag of
[`gc sling`](https://docs.gascity.com/reference/cli#gc-sling) holds the pour
until the bead's blockers close. Its live-workflow check refuses only the same
formula relaunched on the bead while its root is live: "distinct formulas
targeting the same bead are legitimate concurrent work" (package sling,
`checkLegacySourceWorkflowConflict` and `liveConvoyTrackedWorkflowRoots`).

**Nothing pours a formula when a blocker closes.** The `core` pack's
`cascade-nudge-on-blocker-close` order nudges the assignee of each dependent of
a closed blocker, or its `gc.routed_to` target when it has no assignee. A bead
the store-only exit releases has neither, and a nudge pours nothing.
[`gc session wait`](https://docs.gascity.com/reference/cli#gc-session-wait)
wakes a session when the beads it watches close, with a reminder, and it pours
nothing either. An order with `trigger = "event"` and `on = "bead.closed"`
"fires whenever the named event appears on the bus"
([Tutorial 07 - Orders](https://docs.gascity.com/tutorials/07-orders#trigger-types)),
and the order supplies what it runs. Gas City's readiness holds a bead behind
an open `blocks` blocker (package beads, `IsReadyBlockingDependencyType`).

**A session records the step it claimed.**
[`gc hook current`](https://docs.gascity.com/reference/cli#gc-hook-current)
"Prints the work bead this session most recently claimed with gc hook
--claim", and "A formula step that must close the bead it is running reads the
stamp back here". The claimed step names its run's root in `gc.root_bead_id`.

**A person's decision has native forms.** A bd gate blocks "dependent work
until an external condition is met"
([Dependencies and Gates](https://beads.gascity.com/core-concepts/dependencies#gates)),
and a `human` gate waits on manual approval. The `core` pack's
`notify-on-human-gate-creation` order mails a human gate's addressee when the
gate is created, and nudges one that is a session, and
`renudge-stale-human-gates` does it again for a gate left open. bd's `human`
label marks a bead waiting on a person:
[`bd human list`](https://beads.gascity.com/cli-reference/human) lists
"human-needed beads", and Gas City's pool dispatch skips a bead that carries
the label (package beadmeta, `HumanLabel`; package config,
`PoolDemandServeRulesForQuery`).

## What the change does with it

The hand-off takes each part Gas City ships:

- **The hold** is a bd `blocks` edge from the work bead onto its run's root.
  Gas City's readiness keeps the bead out of `bd ready` while the root is open,
  and the pack's deferred-dispatch pass slings nothing that a blocker holds. The
  root closes when the run's finalizer runs, after the run's last write to the
  bead, so the edge is what makes need 4 hold.
- **The run** is the one the session executes. `gc hook current` names the step
  the session claimed, the step names its root, and `run-lib.sh`, the pack's one
  definition of how a run links to its bead, confirms that run is live and works
  the bead over the step's input convoy. The first version of the change asked
  `run-lib.sh` for every run poured over the convoy instead. The search found
  the claimed step, and the rework moved the read onto it.
- **The close** is Gas City's work record: the closer stamps
  `gc.work_outcome=no-op`, the record's value for a close that ships no commit,
  and its close reason names the work as done, so need 3 holds within the
  record's own vocabulary.

Two parts are the pack's, because Gas City ships nothing for them:

- **The pour after the run ends** is `deferred-dispatch.sh arm`. Gas City ships
  no sling on unblock, and the built-once target keeps sling on unblock as a
  residual of deferred dispatch under a warrant that tk-1tfzr71.16 owes
  ([built-once-target.md](../../docs/built-once-target.md#work)).
- **The check** is `mol-validate-close`, the pack's existing validating closer,
  which a first reaction's close disposition already pours. The change adds the
  store-only brief to the cases it checks. Its escalation is the path a record
  that fails the check takes to the operator, so need 2 holds.

Each nearer primitive fails a need, or meets them at a cost this change does
not take:

- The finalizer's source close never reaches a convoy-first run's work bead,
  and where it applies it closes on the run passing, with no check. It fails
  need 2.
- The run closing its own bead with a typed outcome, as `mol-do-work` and
  `mol-polecat-report` do, closes on the run's own word. It fails need 2. The
  pack also gives a work bead's close to `merge.sh` after a verified merge, or to
  a person, and never to its own polecat
  ([authority-map.md](../../docs/authority-map.md)), as Gas Town's polecat
  formula never closes its work bead.
- Gas Town's no-commit halt leaves the bead with whoever its nudge reaches, and
  a nudge is not a record anything acts on. It fails need 1, and it is the
  release this change replaces for a finished record.
- A verifier step in the run, shaped like `close-source-anchor`, would be
  poured into every `mol-polecat-work` run, because a step's condition is
  settled at the pour and the store-only case is decided in submit-and-exit. A
  pool session would claim it in each run, the ones the refinery lands
  included.
- An exec check runs one script for every record, and the records a store-only
  run finishes a bead with share no shape a script could judge. The closer's
  check reads what the brief names and re-runs a check the record cites.
- `[steps.on_complete]` meets the needs at a cost. The closer would become an
  expansion fragment grafted into the run, a second shape of
  `mol-validate-close` beside the run a first reaction pours, and every
  submit-and-exit would owe structured output to the fan-out, whichever arm it
  took. No formula upstream uses it, and the specification names `drain` as the
  canonical fan-out.
- A closer slung at the exit would be accepted, since Gas City lets distinct
  formulas run on one bead, but it would start while the run still writes to
  the bead. The step records the exit and hands the bead back after the script
  returns, and the hand-back (`assets/scripts/hand-back.sh`) is guarded on what
  the bead showed, so a close that lands first makes it refuse. It fails need 4.
- bd's `until` dependency type marks a bead "active until" its target closes,
  and it does not hold the bead out of Gas City's readiness. Neither bd, Gas
  City nor a published pack acts on the edge. The pack's own deferred-dispatch
  pass closes a bead once its `until` targets have closed, through
  `bead-rehome.sh`, with no check of a record and with the target as the bead's
  successor. It fails needs 2 and 3.
- A `gc session wait` on the run's root would leave the pour to this run's pool
  session, which would have to wake after its terminal step and sling the
  closer from a reminder. The deferred-dispatch pass needs no session to outlive
  the run.
- A human gate or the `human` label is the bead's other option, a demand that
  only a person's judgment satisfies. A finished record needs a check, not that
  judgment, so the change asks a person only when the check fails.
- An order that `bead.closed` triggers would still run pack code to find the
  bead and pour its closer, which is what the deferred-dispatch pass already
  does. An event is a trigger the pass could take in place of its cadence, and
  the pass's trigger is outside this change.

This answer changes if Gas City ships a pour held until a bead's blockers
close, a typed work outcome for finished work that ships no commit, a step a
run adds once it is running, or a finalizer close made on a check. At Gas
City's `3f3224faaeff` none of these exists. The arm should then move onto the
pour, and the close onto the outcome or the check.
