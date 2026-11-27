---
name: Design — what remains of the convoys member
description: The design for tk-1tfzr71.249, the design child of tk-1tfzr71.23, the convoys member of the migration epic, read at main aa6f8f497, Gas City upstream main 6dce31bbb6, gascity-packs main 44b9db7168 and every store on 2026-11-27. It finds the member's Done already true for graduation, convoy membership and a convoy's landing, removes the closed-convoy parent edges the October move left on open beads, leaves an effort's bring-current to the one command for every branch, gives the design convoy's first step the gate the work formula's first step runs, corrects the texts that teach a convoy parent, and defines the one implementation unit. Read it to approve the design at its gate, or to build that unit.
---

# Design: what remains of the convoys member

This is the design record for tk-1tfzr71.249, the design child of tk-1tfzr71.23,
the convoys member of the migration epic (tk-1tfzr71). The member's description
dates from 2026-10-19. Since then the one-bead PR model (#1326, 3688e4a3b)
deleted graduation and the script that linked a convoy's members by parent, and
carried each integration effort to main on a landing bead. The pack was read at
main aa6f8f497, the commit `integration/tk-1tfzr71.23` was cut from. Gas City is
cited by symbol at `gastownhall/gascity` main 6dce31bbb6, read in the city's
clone at `upstream/main`. Gas Town and the build pack are cited at
`gastownhall/gascity-packs` main 44b9db7168. Every rig's store and the city's
were counted on 2026-11-27, and section 11 gives each count's query.

## What you approve

The one-bead PR model already did most of this member. No reader in the pack
takes a convoy's members from a parent edge, and no convoy carries work to
land. Four things remain:

1. **A design convoy waits for what holds its subject.** A sitting's sling or a
   hand sling can send a subject that still waits on other work, or that sits
   under a parked epic. The design convoy then cuts the subject's branch and
   sends its design child anyway. Under this design, its first step runs the
   gate the work formula's first step runs. A held subject's run ends with a
   re-sling armed, which starts it again on its own once nothing holds the
   subject. A parked subject's run ends behind a gate for a person. This has
   not happened yet: the three design convoys a sitting has slung since
   2026-11-15 all had subjects nothing held. The change ships one block in one
   formula step and two corrected lines in the gate's script. It asks nothing of
   you.
2. **An effort brings its branch current through the one command you ruled for
   every branch.** On 2026-11-25 you ruled one way to bring any branch current,
   and tk-1tfzr71.243 builds it. That bead also removes the effort's own
   hand-off. This member builds nothing for it. The deletion page says the
   hand-off ends when this member moves efforts onto `gc convoy land`, but that
   command runs no git, so the line is corrected to name tk-1tfzr71.243 as its
   end.
3. **Nine open beads lose a parent edge left over from October.** When the
   one-bead model moved each open convoy onto a landing bead, it kept each
   member's parent edge onto the convoy it then closed. That parent ranks
   nothing and holds nothing. It does hide the one member that has no dispatch
   and no hold from the sweep that would send it to placement, so that member's
   effort cannot land until someone notices it. It also makes placing two held
   members standalone take an extra command. No open epic exists to move them
   under, so each loses its edge onto the convoy. Eight are in another rig's
   store. The one unheld member then gets a first reaction in its rig, which
   holds a bead with no epic for your placement rather than sending it to a
   pool. Nothing else changes for any of them.
4. **Texts that teach a convoy parent are corrected.** Three texts say a bead
   can take its base from a convoy parent, or call a bead's parent its convoy.
   The deletion schedule's row for this member names readers that need no
   change, so the row goes.

All four are one unit of work (tk-1tfzr71.250) on `integration/tk-1tfzr71.23`,
laid out in section 10.

## 1. What is left of the member

### The member's Done, clause by clause

The member is done when "a finished convoy lands through Gas City's or Gas
Town's own landing, membership is read only from `tracks` edges, and
convoy-graduate.sh is gone."

- **convoy-graduate.sh is gone.** #1326 deleted it with its cadence arm and
  `orders/convoy-check.toml`, and deleted `convoy-seed.sh` with them.
- **Membership is read only from `tracks` edges.** No reader in the pack takes a
  convoy's members from a parent edge, as the next table shows. Gas City's own
  reader, `MembersIn` (`internal/convoy/membership.go`, `membersFrom`), lists a
  convoy's legacy parent-child children beside its `tracks` members. No open
  convoy in any store has a parent-child child, so for every convoy a formula
  reads, `gc convoy status` lists only what the convoy tracks. The newest child
  any convoy has was filed on 2026-10-23, before #1326 deleted its writers.
- **A finished convoy lands through Gas City's or Gas Town's own landing.** No
  convoy carries work to land. No open convoy in any store is owned or carries a
  `target`. An integration effort reaches main through its landing bead, an
  ordinary bead the refinery carries through one PR. `gc convoy land` and Gas
  Town's auto-land have nothing in the city to land (section 3).

So the Done holds on main. What the member still owes is section 10's unit.

### The readers

The member's description names six readers that took a convoy's membership
from a parent edge. Three of them have since moved into gctk. Each of them takes
a parent as a parent, with no type filter, and none of them reads a convoy's
members.

| Reader the description names | Where it lives now | What it reads |
|---|---|---|
| `priority-lib.sh` | the same file | A member follows its most urgent parent (`prio_follows`), and a closed or pinned parent is never followed (`prio_live`). |
| `hold-lib.sh` | `gctk bead holds`, in `services/gctk/waits` | A wait on a parent-child ancestor holds work that has not started, and a closed or pinned ancestor ends its line. |
| `converse-parent.sh` | the same file | The nearest parent that is not closed. |
| `placement.sh` | `services/gctk/place`, and intake's admit rule in `services/gctk/reaction/dispose.go` | Place refuses `--standalone` for a bead that has a parent. Intake admits a bead with any parent as "a member of" it. |
| `bead-context.sh` | the same file | The parent, shown as context, and the children, listed by `gc bd list --parent`. |
| `tools/gc-proactive.sh` | the sweep's candidate rule, `isCandidate` in `services/gctk/reaction/sweep.go` | A bead with a parent is no candidate. |

The readers that moved into gctk read a parent through the ledger's
`Record.Parents` (`services/gctk/internal/ledger/snapshot.go`). The rig board
(`services/helm/internal/rigboard/build.go`, `containers`) climbs parents to the
nearest epic or Delivery. A reader of a workflow's link to its bead reads
`tracks` (`run-lib.sh`, `run_tracked`). The formulas read their bead with
`gc convoy status`, which is Gas City's reader. The pack's one copy of a
convoy's legacy parent-child read is the test fake of `gc convoy status`
(`services/gctk/internal/gcbd/fakegc/convoy.go`). It mirrors Gas City and stays
as it is.

The deletion schedule gives this member "the membership readers on
parent-child" (`docs/built-once-target.md`, lane A), and `tools/deletion-plan.tsv`
has no row for it. Those readers carry no convoy code, so nothing is removed, and
the row goes when this member's unit lands.

## 2. Beads whose parent is a convoy

### The census

On 2026-11-27, nine open beads had a convoy for a parent, and every one of those
convoys is closed. One is in this rig's store: tk-fhkllrb, under tk-alyaztk. The
other eight are in one other rig's store, under four convoys. Each is a member of
an integration effort still in flight, and each carries its own `target`, the
effort's branch, which origin still has. Each effort has an open landing bead
assigned to its rig's refinery, and the landing bead waits on the member by a
`blocks` edge. In this rig's store, the landing bead tk-zvu0bd6 waits on
tk-fhkllrb, and its branch is `integration/tk-alyaztk`. Neither the landing
beads nor the convoys have a parent. Two of the members carry
ids minted under an epic, and those epics are closed. So no open epic exists to
move any of them under.

The old convoy recipes wrote these edges, since they linked a convoy's members by
parent, and the one-bead model's move left them. That move's section 10
(`specs/tk-0erzikn/design.md`, "Moving the open convoys that carry a branch")
wrote each open member's `target` and the landing bead's and summary task's
waits on it, then closed the convoy. Its step 3 moved no parent edge. No writer
makes a convoy parent now:

- `mol-design-convoy` files its children only under the subject's parent of
  type epic (`formulas/mol-design-convoy.toml`, its three filing steps).
- The integration-effort recipe files each bead with `--parent <epic>`.
- Gas City's convoy verbs link a member by `tracks` (`TrackItemIn` in
  `internal/convoy/membership.go`). The parent-child list in
  `cmd/gc/cmd_convoy.go` is a read.

### What a closed convoy parent does

- **To priority and holds, nothing.** `priority-lib.sh` never follows a closed
  parent, and `gctk bead holds` ends an ancestor's line at a closed bead. Each
  member competes at its own priority, as it would with no parent.
- **To where a member's work starts, nothing.** Gas City's sling takes the base
  from the bead's own `target` first (`BeadMetadataTarget` in
  `internal/sling/sling.go`), and each member carries one.
- **To the sweep, intake and place: they read the member as placed.** The sweep
  passes over a bead that has a parent. Intake admits it to a pool as "a member
  of" the convoy. Place refuses `--standalone` until the parent is removed, and
  its refusal prints the removal. Six of the nine are armed, and deferred
  dispatch reads none of this. Two others wait for placement under `hold:mayor`,
  so placing either standalone takes the removal first. The last one has no arm
  and no hold, so nothing will ever offer it. Its landing bead waits on it, so
  its effort cannot land until someone notices it. The first reaction's sweep
  runs in that rig (`city.toml` turns it off only in gc-toolkit and gascity), and
  only the parent edge keeps the sweep from taking that bead.

### Decision

The unit removes the parent-child edge onto the convoy from each open bead whose
parent is a convoy, with `gc bd --rig <rig> dep remove <bead> <convoy>`, and reads
each bead back. The bead's `target` and the landing bead's wait on it stay. The
armed members are dispatched as before. The two held members wait for placement
as before, and either places standalone in one call. The unheld member becomes a
candidate for its rig's sweep. A first reaction that would send it to a pool
holds it for placement instead, because it has no parent epic (intake's admit
rule), and your placement sitting then places it or closes it.

Rejected:

- **Leaving the edges.** The one unheld member stays offered to nobody, and its
  effort cannot land.
- **A reader that skips a convoy parent.** That puts convoy code into each
  reader to cover leftovers whose writers are gone, which is what the member's
  own Test 3 rules out.

### The three texts

| File | Says today | Says under the design |
|---|---|---|
| `formulas/mol-polecat-work.toml`, workspace-setup's base-branch line | "resolved by `gc sling`: the bead's own metadata.target, else the first convoy target on the one parent chain bd reports, else the rig default branch" | "resolved by `gc sling`: the bead's own metadata.target, else the rig's default branch" |
| `skills/work/integration-effort.md`, "Start a workflow from another branch" | "`gc sling` starts a `mol-polecat-work` workflow from the bead's `target`, else the `target` of a convoy among its parents, else the rig's default branch" | "`gc sling` starts a `mol-polecat-work` workflow from the bead's `target`, else the rig's default branch" |
| `skills/gc-demo-script/SKILL.md`, the bead's fields and Step A3 | "`parent` — the convoy/molecule wrapping this work", and "If the bead has a parent convoy or `metadata.molecule_id`, read it" | "`parent`: the epic the work belongs to", and "If the bead has a parent or a `metadata.molecule_id`, read it" |

Gas City's lookup also takes a convoy ancestor's `target`
(`BeadMetadataTarget`). After the unit's edge removals no open bead has a convoy
ancestor, and no writer gives a bead one, so the shorter line is the whole of
what the lookup does in this city. `docs/gascity/routing-model.md`'s line on a
convoy target is about slinging a convoy itself, so it stays.

## 3. The integration-effort bring-current

### How an effort's branch is brought current today

A bead of an effort that builds on work reaching main after the effort's branch
was cut waits on a hand-off. The hand-off is a task assigned to the refinery,
and it waits on the outside work (`skills/work/integration-effort.md`, "Bring
the effort's branch current"). Once the outside work lands, the refinery runs
`effort-bring-current.sh`. The script fast-forwards the branch, or merges main
into it without a checkout. It then pushes under the lease and closes the
hand-off.

The hand-off is in steady use. In gc-toolkit's store, 33 hand-offs closed this
way between 2026-11-12 and 2026-11-27, across 16 efforts: 26 merges and 7
fast-forwards. No other store has one.

The last of them shows the path's gap. tk-1tfzr71.187 was ready from 2026-11-26
at 23:32Z, when its one blocker closed. The refinery got the nudge that named it
two minutes later, ran find-work, which passes over a bead with no `branch`, and
ended its turn reading the hand-off as still held. A hand-off carries no `branch`
by design, and every reader that could catch it skips such a bead: find-work, the
witness's refinery-queue check, and `gctk refinery stuck`
(`services/gctk/refinery/refinery.go`). So nothing took the hand-off until a
nudge that named its call, at 2026-11-27 19:09Z, got it taken in 11 seconds (the
first reaction's note of 19:12Z on tk-1tfzr71.249, from finding tk-i3rbjyd).
#1719, which is still open, has the refinery take a bead with no branch through
its hook (`services/gctk/refinery/next.go` on its branch), and tk-1tfzr71.243
removes the hand-off.

### What Gas City and Gas Town offer

- `gc convoy land` (`newConvoyLandCmd` and `doConvoyLandJSON` in
  `cmd/gc/cmd_convoy.go`) refuses a bead that is not a convoy, a convoy without
  the `owned` label, and a convoy with open children unless it is forced. It
  closes the convoy and records `ConvoyClosed`. It runs no git, so it brings
  nothing current, and the city has no owned convoy for it to land.
- Gas Town's `integration_branch_auto_land`
  (`gastown/formulas/mol-refinery-patrol.toml`, step next-iteration, off by
  default) assigns a fully closed owned convoy to the refinery with its branch
  and a target, and the refinery then lands it like a work bead. It brings no
  branch current while work is in flight. Gas Town's refinery rebases a branch
  only as part of landing it.

So moving efforts onto `gc convoy land` ends nothing. The deletion page names
that end (`docs/built-once-target.md`, the refinery's differences under Merge,
"The integration-effort hand-off"), and so does the merge design
(`specs/tk-1tfzr71.66/design.md`, section 1's table of differences and section
11's row for this member). The merge design is a record of that bead's work, so
it stays as written, and this design is where its end is corrected.

### Decision

Efforts keep bringing their branch current, through the one command for every
branch. In conversation tk-j3x4yo5 on 2026-11-25, the operator ruled one path
for bringing any branch current, taken only on an approved PR or as an agent's
skill step. tk-1tfzr71.243 builds it as one gctk command that brings any branch
current, a PR's branch or an integration branch. The command sends a conflict to
an agent, and the refinery's prep, the approved-PR conflict path and an agent's
request all run it. The same bead removes the effort's own path, which is
`effort-bring-current.sh`, the refinery prompt's recipe and the section of
`integration-effort.md`, and it changes the deletion page's line. Under it, a bead of an
effort that builds on work reaching main asks for its branch to be brought
current through that command's skill step, as any agent asks for any branch.

This member builds nothing for it. If the deletion page's line still names this
member when this member's unit builds, its end names tk-1tfzr71.243 instead. Once
tk-1tfzr71.243 lands, the line changes with the path it names, as that bead's
Done says.

## 4. The conflicted bring-current

The recount: the hand-off has conflicted once, on 2026-11-10, before a conflict
went to a polecat (gate tk-ucjq40f, 14 files on `integration/tk-1tfzr71.15`). The
operator ruled "A polecat should do this", and tk-1tfzr71.94 resolved it. #1484
made a conflict a polecat task on 2026-11-13. Since then 29 hand-offs have
closed, and no task titled "Merge origin/<target> into <branch> and resolve its
conflicts" has been filed in any store.

The conflict path is tk-1tfzr71.243's. Its one command sends a conflict to an
agent. An integration branch has no PR and no review run, so there that agent is
a polecat. Retiring #1512 in conversation tk-hqhv36p on 2026-11-15, the operator
wrote: "merges are done by the refinery normally, not polecats. Is the
underlying issue that we are trying to use a polecat to do refinery work, which
is merging". That bears on how the polecat's resolution reaches the branch.
Today the polecat's merge lands through the work path. The work path's zero-diff
guard refuses a resolution that keeps the branch's side of every file the target
changed, and it puts that resolution to a person as missing work. tk-1tfzr71.23's
note of 2026-11-15 sketches the alternative: the polecat resolves on a branch, and
the bring-current checks the resolved merge and pushes it under the lease. Gas
City has a word for work a consumer takes from its branch: `merge_strategy=local`,
which "leaves the work on its branch with no merge and no request; the consumer
decides what to do with it" (`MergeStrategyLocal`, `internal/beadmeta/keys.go`).
Gas Town's refinery escalates `local` as unimplemented, and the pack's parks it
(`refinery-land.sh`). The unit gives these facts to tk-1tfzr71.243 in a note, so
its design settles them, and this member builds no conflict path of its own.

## 5. The design convoy's first step

### How a subject reaches the design convoy

`mol-design-convoy` stands an effort up on its subject. It cuts the subject's
branch, files the design, implementation and summary beads, hands the subject to
the refinery, and dispatches the work. Its first step, load-context, reads the
subject from its input convoy and reads the subject's card. It reads nothing that
holds the subject.

A subject reaches the design convoy in three ways:

- **An armed dispatch.** The deferred-dispatch start slings an armed bead only
  once nothing holds it (`services/gctk/arm/start.go`, `judge`), so it never
  sends a held subject.
- **A sitting's Accept.** `gctk reaction accept`
  (`services/gctk/reaction/accept.go`) refuses while another human gate blocks
  the subject, and otherwise slings. A wait on other work, or a parked epic
  above the subject, does not stop it.
- **A hand sling.** `gc sling --on mol-design-convoy` pours at once and reads no
  wait.

When a held subject arrives by either of the last two, the design convoy cuts
the branch, files the beads under the subject's epic, hands the subject to the
refinery, and slings the design child. The design child's own first step then
refuses only when a parked epic holds it. A wait of the subject's own, such as a
lane's order behind the member before it, holds none of the beads filed for it,
so the design is built out of turn.

In gc-toolkit's store, 27 design-convoy runs have been poured. The first whose
title carries the armed start's token, `arm:<bead>@<armed at>`, was poured on
2026-11-15. Of the 10 runs poured since then, 7 carry it, and 3 were slung by a
sitting seconds after it filed the subject. None of those three subjects waited
on anything when its run started: every wait on them now is onto a bead filed
after the pour. No run's title carries the `accept:` token Accept pours under.

### Decision

load-context runs the work formula's gate on its subject before it reads
anything else:

```bash
"$(b='{{binding_prefix}}'; gc "${b%.}" scripts-dir)/work-gate.sh" --convoy {{convoy_id}} --step mol-design-convoy.load-context --formula mol-design-convoy
```

Exit 0 goes on to the step's own read of the subject, which then finds the one
member the gate found. Any other exit stops the step and leaves it open, as in
the work formula. When the refusal is final, the gate has already recorded what
releases the subject, cancelled the run and drained. When the store did not
answer, the step goes back to the pool with nothing asked. The gate's cases
(`work-gate.sh`'s header) meet a subject this way:

- **Held** by a wait of its own, or, before anything has started on it, by a
  wait on an ancestor such as a parked epic, as `gctk bead holds` answers. The
  run is cancelled, and a re-sling on `mol-design-convoy` is armed
  (`await-ruling.sh --held-by`). Deferred dispatch fires it once nothing holds
  the subject, and nobody is asked.
- **Parked**, with a status that is not open, in progress or closed. The run is
  cancelled behind a gate for a person. The gate's message names
  `gc sling <pool> <subject> --on mol-design-convoy` for when the subject is
  ready.
- **Finished or already handed off**: closed, carrying a `merge_result`, or
  assigned to someone else, such as the refinery an earlier run handed it to.
  The run is cancelled with nothing asked.
- **In another live run of the design convoy.** The oldest run builds.

A malformed pour, an input convoy without exactly one member, is declined behind
a gate. Today the step's own check exits 1 there, which leaves the step open for
each polecat that claims it in turn.

Two lines of `work-gate.sh` name `mol-polecat-work` where the formula is the one
the gate was given: its header line, and the malformed-convoy gate's message,
"so mol-polecat-work cannot derive its work bead". Both name the formula passed
to the gate instead. That is a fix in place, with no new verb, mode or key.

One case only a design convoy can meet: a subject that an earlier run stood
partly up. Such a run filed beads but was cancelled before its dispatch step, so
the subject carries a branch. The gate reads a subject with a branch as work in
flight, held by its own waits, and those waits are its undispatched beads, so it
arms a re-sling that waits on them. Only a person's cancel can end a design
convoy between those steps, because none of its later steps cancels its own run:
a failing step exits 1 and is retried. Reaching this case takes a person's cancel
and then a new sling.

### The build pack's build-from-convoy

At gascity-packs 44b9db7168, `gascity/formulas/build-from-convoy.formula.toml`
extends `build-from-convoy-base`. That formula validates an existing
implementation convoy (prepare-convoy). It drains the convoy's members through
`do-work`, in a separate session per member or one shared session, and then hands
on to `build-from-review-base` for a review of the whole and a finalize. `publish`
pushes and opens a PR only when its vars authorize it. `do-work` prepares a
worktree for each item and implements it. It closes the item's source anchor with
`gc.outcome=pass` once the implementation commit and its summary are in the
worktree (`assets/workflows/do-work/close-source-anchor.md`). Its steps run at the
role targets `gc.run-operator`, `gc.implementation-worker` and `gc.publisher`, and
the city configures no agent for any of them.

None of it fits a part of the design convoy:

- The design convoy writes no code. It files an effort's beads and dispatches
  them, and the polecat pool and the refinery build and land them.
- An effort's beads are not a convoy's members. Each carries its own target and
  the landing bead's wait.
- Closing a bead at its implementation commit would skip the refinery's landing
  and the record that keeps work pending until its merge is verified.
- The design gate is your approval of a stage's PR, and no build-pack step asks
  for one. Its `design-review` formula reviews a design doc through a review
  agent (`gc.review-synthesizer`), not through a person's approval of a PR.

## 6. The anchor

The member's description folds the anchor into "a PR comes from one issue or one
convoy". Under the one-bead PR model a PR comes from one bead. An effort's PR
comes from its landing bead, which is an ordinary bead, so no PR comes from a
convoy. The one-bead design keeps the anchor and I4 as they are
(`specs/tk-0erzikn/design.md`, section 11, "What to correct", its closing
paragraph). `docs/component-model.md` already says so in its Anchor row, its
Convoy row ("It carries no branch: an integration effort reaches main through its
landing bead, an ordinary bead") and I4. This member owes nothing there.

## 7. Code this work must not grow

- Nothing in this design changes a file `tools/deletion-plan.tsv` lists.
  `liveness-classify.sh`, which tk-1tfzr71.174 retires, reads parent-child
  edges only to treat a bead with an open child as waiting, and it classes any
  convoy as machinery before that, so it needs nothing.
- The design convoy's gate composes `work-gate.sh`, which no bead retires,
  through flags it already takes. So the gate adds no script, verb, mode or key,
  and `work-gate.sh` takes only a fix in place.
- The conflict path that leaned on `mol-polecat-work`'s bring-current audit and
  guard, which tk-1tfzr71.122 retires, is tk-1tfzr71.243's to replace, and this
  member builds none.
- The gate accommodates a behavior of Gas City, a sling that pours onto a bead
  its waits still hold. Section 9 is that record.

## 8. Overlap, and an effort in flight

| Open PR | What it changes in this member's files | How the unit meets it |
|---|---|---|
| #1719 (tk-1tfzr71.242), the refinery one item per session | rewords other bullets of `docs/built-once-target.md`'s Merge section, `effort-bring-current.sh`'s header, `integration-effort.md`'s steps 6 and the hand-off's steps 1 and 3, the refinery prompt, and `mol-design-convoy.toml`'s dispatch prose | Its hunks reach neither lane A's row, the hand-off bullet, nor the lines section 2 rewrites. Whichever lands second merges the other in. |
| #1683 (tk-y3ud19l), a claimant and a run that both refuse | `work-gate.sh`'s header comment and its hold read, `await-ruling.sh`'s callers, and the Verified line of `docs/warrants.md`'s "The work formula's overrides" | Its hunks in `work-gate.sh` reach neither line 2 nor the malformed-convoy message. Both changes edit `await-ruling.sh`'s callers and re-stamp the same Verified line, so the second to land merges the callers and keeps the later date. |
| #1647 (tk-2358fdf), copied text taken as written | `mol-design-convoy.toml`'s load-context step 2 and its file-design step | The gate's block sits in step 1, beside #1647's first hunk. The second to land merges the other in. |
| #1634 (tk-72u5bsc), cross-store parent links | `bead-context.sh` | The unit does not touch it. |

An effort in flight meets nothing it has to cut over for:

- The text changes change no behavior.
- A run's step text is fixed when the run is poured, so the gate binds only design
  convoys poured after the unit reaches main, and no effort already past its first
  step meets it.
- The edge removals change no member's `target`, wait or arm.

## 9. The Gas City and Gas Town search

AGENTS.md asks a change that accommodates a behavior of Gas City for this record.

**The behavior.** `gc sling` pours a formula at once and reads none of the
bead's waits. That is how a held subject reaches the design convoy through Accept
or a hand sling. In `internal/sling`, `validateExistingBeadInQuerier`
(`sling_core.go`) checks only that the bead exists (`docs/warrants.md`, "Deferred
dispatch residual").

**Gas City's reason.** Gas City gives none. Upstream tracks the behavior as a
fault in two open bugs: #7163, "a formula slung onto a blocked bead runs before its
blockers close", and #8832, "native execution admission loses current input
readiness". Its fix is the open PR #8834, "preserve live native input readiness at
execution admission". All three were open on 2026-11-27. Measured here: of the
three design convoys a sitting has slung since 2026-11-15, none had a held
subject (section 5's census). The work formula's first step already gates the
same fault for its work beads (`docs/warrants.md`, "The work formula's
overrides").

**The fix at the source.** It is upstream's own PR #8834, carried by #7163 and
#8832. The city follows it through the deferred-dispatch warrant's trigger. When
it fires, the gate's held case becomes something Gas City does. The parked,
finished and handed-off refusals do not depend on it.

The other primitives this design searched:

- `gc convoy land`, which runs no git (section 3).
- Gas Town's `integration_branch_auto_land`, which lands a finished owned convoy
  and keeps nothing current in flight (section 3).
- Gas City's `MembersIn`, which reads legacy parent-child members. Nothing works
  around it, because the edges it would read are removed (section 2).
- `BeadMetadataTarget`, whose convoy-ancestor clause no bead reaches once the
  edges are gone (section 2).
- `merge_strategy=local`, handed to tk-1tfzr71.243 (section 4).
- The build pack's `build-from-convoy` and `design-review` (section 5).

## 10. The implementation unit

tk-1tfzr71.250 builds one unit, which lands on `integration/tk-1tfzr71.23` with
no PR of its own.

1. **The design convoy's gate.** `formulas/mol-design-convoy.toml`'s
   load-context runs section 5's block first and says what each exit means. The
   load-context row of `docs/design-convoy.md`'s step table names the gate and
   what a held, parked or finished subject meets there.
   `generated/seed-audit/formulas/mol-design-convoy.md` is regenerated. One case
   in `assets/scripts/mol-design-convoy-arm.test.sh` pins that load-context runs
   `work-gate.sh` with `--convoy {{convoy_id}}`, `--step
   mol-design-convoy.load-context` and `--formula mol-design-convoy` before it
   reads the card.
2. **The gate's script.** `work-gate.sh`'s header line and its malformed-convoy
   message name the formula the gate was given. A case in `work-gate.test.sh`
   pins that message for `--formula mol-design-convoy`. The change touches a path
   that "The work formula's overrides" covers, so that entry is re-verified and
   its Verified line re-stamped. The callers lines of `decline.sh` and
   `await-ruling.sh` name the design convoy's first step beside the work
   formula's.
3. **The parent edges.** Re-run section 11's census in every store. Remove each
   open bead's parent-child edge onto a convoy with `gc bd --rig <rig> dep remove
   <bead> <convoy>`, read each bead back, and record the writes in the unit's
   notes without naming another rig.
4. **The texts.** Section 2's three rows, with
   `generated/seed-audit/formulas/mol-polecat-work.md` regenerated.
5. **The deletion page.** Remove lane A's row for tk-1tfzr71.23 from
   `docs/built-once-target.md`. If the integration-effort hand-off's line still
   names this member, its end reads "This ends when tk-1tfzr71.243 brings every
   branch current through one command."
6. **The note.** Append to tk-1tfzr71.243's notes section 3's census, section
   4's diagnosis and the zero-diff fact, and Gas City's `local` merge strategy,
   for its conflict path on an integration branch.

The summary the unit records names goal G3 of `docs/foundation.md` for the gate:
a wait or a park someone set holds when the subject is handed to the design
convoy. The effort's summary task carries that into the PR you review.

The cost of waiting for it:

- A design convoy that a sitting or a hand sling pours on a held subject stands
  the effort up anyway, and builds its design out of turn.
- The one effort member that nothing offers keeps its effort from landing.
- Three texts teach a base taken from a convoy parent, which no bead in the city
  relies on.

## 11. Facts and queries

Each count ran on 2026-11-27, once per rig's store with `gc bd --rig <rig> sql
--json "<query>"`, and once for the city's store with
`gc bd --db "$GC_CITY_PATH/.beads" sql --json "<query>"`.

- **Beads whose parent is a convoy:** `SELECT c.id, c.status, p.id AS convoy,
  p.status AS convoy_status FROM dependencies d JOIN issues c ON c.id =
  d.issue_id JOIN issues p ON p.id = d.depends_on_issue_id WHERE d.type =
  'parent-child' AND p.issue_type = 'convoy'`. The open rows are section 2's
  census. A convoy whose status is not closed appears in no row.
- **Owned or targeted open convoys:** convoys whose status is not closed, joined
  to `labels` for `owned`, and the same with
  `JSON_EXTRACT(metadata, '$.target') IS NOT NULL`. Each store has none.
- **Hand-offs:** `close_reason LIKE 'Brought integration/% current with %'`,
  the close reason `effort-bring-current.sh` writes. A recorded head with two
  parents is a merge, and one with a single parent is a fast-forward to main,
  which lands by squash.
- **Conflict tasks:** `title LIKE 'Merge origin/% into integration/%'`, the
  title `effort-bring-current.sh` files.
- **Design-convoy runs:** workflow roots (`gc.kind=workflow`) titled
  `mol-design-convoy`, split by an `accept:` or `arm:` token in the title. A
  subject's waits at its pour are its `blocks` edges onto beads created before
  the pour and closed after it, leaving out its own children.
