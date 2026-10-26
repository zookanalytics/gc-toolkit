---
name: Built-once target — the measured model gc-toolkit is held against
description: What gc-toolkit weighs if built once on Gas City as shipped, subsystem by subsystem beside what it weighs at the baseline; what the tree carries that has no place in that shape and what retires it; the order the removals land in; and how a change's net size is predicted and checked. Read it before proposing an epic, and when reviewing what a change landed.
---

# Built-once target

Built once, on Gas City as shipped and with every fact said in one place,
gc-toolkit weighs about 64k lines: 35.0k of runtime and 28.5k of tests. At the
baseline it weighs 250.6k: 109.0k of runtime and 141.6k of tests. The runtime
target is the top of the 25-35k range the migration epic (tk-1tfzr71) was
ratified on. That epic's members and the native-gates convoy carry most of the
removals below. The rest of the distance is copies, comments and tests, which
only the proposals and the measurement discipline below carry.

## Scope

**Mandate.** The target shape and weight of each gc-toolkit subsystem, its
measured distance from the tree, what the tree carries that the target has no
place for and the trigger that retires it, the order the removals land in, and
the discipline that holds a change to the target.

**Boundaries.** Which primitives the pack is built from, and which workflow a
component belongs to, is [component-model.md](component-model.md). What belongs
in the pack at all is [foundation.md](foundation.md#boundaries), and why a pack
noun survives beside Gas City is [warrants.md](warrants.md). Each removal's
design lives on the bead that carries it. This page proposes: a removal is
scheduled only when a bead carries it, and the operator funds each one.

## How the pack is measured

- **A line** is a physical line of a tracked text file at a commit, as
  `git diff --numstat` counts it. A symlink or a binary file counts nothing.
- **Pack weight** counts these kinds of line. Code is scripts, Go and the
  board's web source. Flow is formulas, orders and the other TOML and JSON config. Text
  is agent prompts, fragments and skills. Test is tests and their fixtures.
  Runtime is code, flow and text.
- **Beside the pack** are docs (15.0k), the tooling under `tools/` and
  `.github/` (13.0k), the record under `specs/` (61.0k) and generated files
  (8.0k). They are reported and not budgeted.
- **A path's subsystem** is its row in
  [component-model.md](component-model.md#4-where-each-component-sits) §4, and
  a test takes its script's row. §4 has a row for 104 of the 145 runtime
  scripts under `assets/scripts/`, and the measuring script's rules place the
  other 41 (9.1k lines).

`specs/tk-11l1ejh/measure.sh [REF]` prints a commit's table, and
`measure.sh BASE HEAD` prints what a change adds net of what it removes. The
baseline is main at b09345315 (2026-10-25). Every number on this page is
derived in [the measurement record](../specs/tk-11l1ejh/measurement.md).

## The target, subsystem by subsystem

These rules derive every target from what survives in each subsystem:

1. **Gas City as shipped.** Where Gas City ships the primitive, the subsystem
   is a call to it, and the pack's version weighs nothing.
2. **Said once.** A fact, a rule or an idiom has one home, and a call site
   carries only its own facts. A comment states a reason the code cannot show,
   which keeps a runtime file to about 15% comment. Runtime shell is 36% comment
   today, and Go 32%.
3. **Tests follow code.** A subsystem's tests weigh no more than its code and
   flow. A test pins the behavior of the one copy where it lives. No test
   extracts formula step text to run it, holds two copies equal, or asserts that
   a retired name stays retired.

| Subsystem | Built once, it is | Baseline runtime / tests | Target runtime / tests |
|---|---|---|---|
| work | one formula extending core's polecat base | 6.7k / 12.6k | 2.5k / 2.5k |
| review | the declared checks as lanes of one check loop | 10.6k / 10.0k | 4.0k / 2.0k |
| merge | Gas Town's refinery flow under GitHub's branch rules | 16.6k / 25.2k | 2.0k / 2.0k |
| human engagement | native human gates and conversation tasks | 15.0k / 24.0k | 5.5k / 4.0k |
| board | a ranked render of platform objects | 15.6k / 18.4k | 5.0k / 5.0k |
| patrol | Gas City's orders, plus the patrols' judgment | 9.8k / 15.6k | 2.5k / 2.0k |
| doctor | one check per surviving invariant | 7.6k / 8.9k | 3.0k / 3.0k |
| shared glue | one call per series of native steps | 10.9k / 19.7k | 5.0k / 5.0k |
| gctk | the rig check runner and its records | 5.8k / 4.3k | 1.5k / 1.5k |
| feedback | the learning loop | 2.5k / 1.9k | 2.0k / 1.5k |
| config | the pack, its check index and its key registry | 2.5k / 0 | 0.7k / 0 |
| doctrine | shared fragments and skills | 1.7k / 0 | 1.3k / 0 |
| keeper sub-pack | nothing: the target has no fork | 3.8k / 1.1k | 0 / 0 |
| **total** | | **109.0k / 141.6k** | **35.0k / 28.5k** |

Human engagement is the workflow §4 calls visit. The keeper is the opt-in
`packs/gascity-keeper/`.

### Work

`mol-polecat-work` extends core's `mol-polecat-base` and overrides only what
differs: the per-bead worktree that `gc worktree` provisions, the self-review
loop over `gctk rig` records, and the push and handoff. Each step closes
through `gc hook current`, and a decline is one call. Work owns the work branch
and the handoff write. Priority following stays under its warrant, and deferred
dispatch shrinks to the residuals tk-1tfzr71.16 keeps under warrants: sling on
unblock, and close on an `until` edge.

The trade: load-context becomes core's, so a pack refinement of it waits for
upstream or carries a warrant of its own. The duplicate-dispatch gate is in the
fork's load-context and not in upstream's. Until upstream takes it, keeping the
gate keeps a fork commit or a warranted override.

### Review

The declared checks run as lanes of a formula check loop, each check's method
is its skill, and triage widens the check set. Review owns the check index
(`review-checks.toml`) and the methods, which are prose, and the demo
modalities. The shape of the loop is what tk-1tfzr71.22's design settles.

The trade: review beads, lane derivation, validation passes, machine finding
beads and the sweeps that close their leftovers go, and a lane's verdict lives
in the loop. A person's finding on a PR stays a record the operator rules on.

### Merge

Gas Town's refinery flow lands a branch, directly or through a PR whose
approval and required checks GitHub's branch rules enforce. The pack adds the
PR's managed summary and title, and the step that takes a GitHub event to the
bead that owns it.

The trade: the pack's own approval rule, the merge cadence's arms with their
lock, cursors and crash detection, and the rework and branch-currency machinery
give way to GitHub's rules and the refinery's rebase-or-requeue. An approval
nuance GitHub cannot express keeps a residual under a warrant. Moving the
policy onto GitHub is the operator's ruling at tk-1tfzr71.20's design.

### Human engagement

What a person owes is a native human gate on the bead it blocks, and a
conversation is a task. A sitting is a converse session that holds the
conversation doctrine. Intake is slung work whose exits are native writes. The
subsystem owns the converse, first-reaction and mechanik prompts, the converse
skills, the operator's intake and the terminal surfaces.

The trade: the visit kind, its folds, holds and sweeps, and the keys only they
read go with the native-gates convoy (tk-iirrmiw). The first reaction stops
being a bead kind of its own (tk-1tfzr71.17).

### Board

The board renders platform objects (beads, human gates, conversations and the
supervisor's objects) read through the supervisor API, and ranks them by the
pack's attention model.

The trade: the second data plane that reads the store directly, the visit
rows, the rows that exist only because a pack writer stamped a route, and the
hand-written TypeScript mirror of the Go contract with the parity test that
holds the two equal all go. Which views stay is the Helm UX epic's (tk-ikpyzn)
decision with tk-1tfzr71.24. This target is their budget.

### Patrol

Gas City's orders keep the fleet clean: core's orphan sweep, reaper, wisp
compaction, spawn-storm detection, convoy backstop and branch pruning, the
controller's closed-bead worktree reaper, and the dolt pack's orders. The
pack's patrols carry only judgment: the witness's HELP-mail triage, salvage and
watch on the refinery's queue, and the deacon running `gc doctor` from an
order. Patrol owns the warranted Dolt reclaim and the scratch reapers that no
native reaper covers.

The trade: the liveness census stops filing visits, the incident ledger moves
onto events and bead notes, and the dog's due process moves to the
controller's stall handling or to Gas Town's dance (tk-1tfzr71.18 and .19).

### Doctor

Doctor keeps one check per invariant of a surviving pack noun or warranted
mechanism, and the checks of molecule execution (I8, I11 and I13) become one.

The trade: a check retires with the noun it guards, such as the anchor, a
lane, a visit, a raw route or a dispatch arm.

### Shared glue

Shared glue is one call per series of native steps that more than one workflow
runs: the store helpers, the human-gate helper, findings, run cancel,
hand-back, one decline call, one read-back before an act that cannot be undone,
PR posts with their provenance mark, the gh write guard under its warrant, and
the seed audit.

The trade: per-site read-backs give way to one bd-durability warrant
(tk-1tfzr71.11), and step-close, the worktree wrapper and the hand-off shims
give way to native calls.

### gctk

`gctk rig` runs a rig's declared checks and records each result against the
commit it ran at.

The trade: `gctk merge`'s approval rule goes with the merge member, and its
compiled copy of the key registry goes with the registry. A domain moves into
gctk only when it survives the migration map, and it moves whole: the change
that ports it deletes the shell it replaces, so a port nets negative.

### Feedback, config and doctrine

Feedback is the miner and distiller formulas, the learning-distill skill and
their orders, and changes only by rule 2. Config is `pack.toml`, the check
index, the overlays, the pack command, and a key registry that declares only
the keys of surviving warranted nouns, as data: 1,428 of the registry's 1,791
lines are comments today. Doctrine is the shared fragments and skills, with
each doctrine sentence in one home.

### Keeper sub-pack

The keeper maintains a fork of Gas City, and foundation answers a missing
primitive by reshaping the feature, never by a fork. It retires by its own
page's trigger, a fork with no diverging commit
([fork-patching.md](fork-patching.md#when-this-doc-should-disappear)). The fork
carries 102 today. The migration map keeps the keeper until then, and no bead
carries its retirement.

## What has no place in the target

Each piece names its extent at the baseline, the trigger that retires it, and
the bead that carries it. A piece no bead carries has a proposal in the
schedule.

### Shadow machinery

Gas City ships each primitive below, so its trigger has fired. Each was verified
present on 2026-10-26, at Gas City upstream main f78779e41 or in the installed
bd 1.3.2.

| Pack machinery | Gas City's primitive | Carried by |
|---|---|---|
| `worktree-reap.sh`, `worktree-setup.sh` | the controller's closed-bead worktree reaper, `gc worktree` | tk-1tfzr71.10 |
| `orders/convoy-check.toml` | core's convoy-autoclose-backstop, the same `gc convoy check` | tk-tggczbp |
| `step-close.sh` | `gc hook current` | tk-1tfzr71.12 |
| `duplicate-sweep.sh` and the successor keys | `bd duplicate`, `bd supersede` | tk-1tfzr71.13 |
| hand-stamped routes and the sweeps that repair them | `gc sling --no-formula`, assignment | tk-1tfzr71.15 |
| `orphan-dispose.sh`'s generic arms | core's orphan-sweep | tk-1tfzr71.19 |
| `pr-facts.sh` polling and its mirrored keys | the PR monitor and webhook receiver | tk-1tfzr71.21 |
| visits, `gate-visit-sweep` and the converse plumbing | native human gates, core's notify and renudge orders | tk-iirrmiw, tk-o6pd01i |

### Copied boilerplate

A copy needs no trigger. It goes as soon as a change gives the fact one shared
home.

- The script-dir resolution loop: 122 copies in 20 files, 30 of them in
  `mol-polecat-work.toml`. Carried by tk-c8724xi.
- The decline sequence (escalate, record the wait, cancel the run, drain): 20
  copies in step text, 12 of them in `mol-polecat-work.toml` and one in the
  polecat doctrine fragment, with 29 copies of its refusal sentence. No bead
  carries it (P3).
- The step-close loop: 10 copies in 5 formulas. It goes with step-close.
- A rule kept in two languages, with a test holding the copies equal:
  `gctk merge` and `review-verdict.sh`, `gctk lifecycle` and the key registry,
  and the board's Go contract and its TypeScript mirror. Carried by
  tk-1tfzr71.20 and .25.

### Compatibility debt

A compatibility piece carries a dated debt and the trigger that retires it,
and the change that fires the trigger deletes it.

- The hand-offs at `escalate.sh` and `escalation-rig.sh`, 241 lines with their
  test at the head of the convoy's integration fix (tk-iirrmiw.1). Trigger: no
  open step bead names them, and no session started before the cutover still
  runs. Carried by tk-kvdomjb.
- `molecule-hold.sh`, for step text poured before `run-cancel.sh`, 168 lines
  with its test. Trigger: no open step bead names it. Carried by tk-1tfzr71.12.
- The PR reminder's old marker. Trigger: no open PR carries one. Carried by the
  cutover's follow-up, which tk-o6pd01i files.
- `migrate-approval-out-of-check-set.sh`, a one-shot migration its own header
  calls disposable, 276 lines with its test. Trigger: every store migrated,
  which its dry run shows by finding nothing to change. Carried by
  tk-1tfzr71.25, last in its lane.
- Readers of legacy shapes, which "legacy" names 30 times across 15 runtime
  files: the bare `superseded_by` key, the `gc.proactive_reaction=1` proof and
  PR bodies older than the managed region, among others. Trigger: no store or
  open PR holds the shape. Each goes with the member that rewrites its reader.

### Doctrine restated per call site

A restatement needs no trigger either, once the doctrine has its home.

- Comments: runtime shell is 36% comment (20.8k of 57.7k lines), Go 32%, the
  key registry 79% and the orders 66%.
- Formula step text: 3.9k of the formulas' 8.8k lines are shell inside code
  fences, and step prose restates doctrine the fragments hold.
- tk-c8724xi's census names the sentences restated at each site and carries
  them. Rule 2 holds every later change.

### Tests that pin what should not exist

- 52 test files, 16.4k lines, have no script of their own. Each reads a marked
  block of formula step text, to run it or to pin its text, and 13 script tests
  read one too. Trigger: the step's mechanics become one call to a script with
  its own test (P4).
- Tests that hold two copies equal, and tests that assert a retired name stays
  retired. Trigger: the copy or the name is gone. Carried by tk-c8724xi and
  tk-1tfzr71.25.

### Dead code

`assets/scripts/surface-census.sh`, `tools/gc-polecat-metrics.sh`,
`tools/bead-universe-reachability-fixture.sh` and the one-shot approval
migration: nothing in the tree calls them, and they weigh 1,675 lines with
their tests. Trigger: none. tk-1tfzr71.25 deletes three of them, last in its
lane (P2).

## The deletion schedule

The schedule runs in the order below. An armed bead is blocked by what it waits
on and slings itself when that lands. A size is the lines of the whole files a
bead's contract retires, with their tests, at the baseline, so a bead that also
rewrites part of a file retires more than its size. A branch already in flight
shows its measured net instead.

### 1. Landing now

| Bead | What it removes | Size | Waits on |
|---|---|---|---|
| tk-tggczbp, the one-bead PR model | graduation, the convoy seed, the convoy-check order | −268 net on its branch, which adds a run reader | the operator's review of its PR |
| tk-iirrmiw, the native-gates convoy | visits and their plumbing, onto native human gates | −2,771 net across its branches so far | review of unit C (tk-5u2xpan) |
| tk-o6pd01i, the cutover (unit D) | `gate-visit-sweep`, `visit-identity.sh`, the gate pass of `notification-wisp-reap`; it adds a migration that its follow-up deletes | 597 | unit C landing |

### 2. Armed on the native-gates convoy landing

| Bead | What it removes | Size | Waits on |
|---|---|---|---|
| tk-kvdomjb | the hand-offs at `escalate.sh` and `escalation-rig.sh` | 241 | tk-iirrmiw, then its drain check |
| tk-c8724xi | the 122 resolution loops, the doctrine its census names, its comment excess | 122 loops, about 35 restatements, about 150 comment lines | tk-iirrmiw |
| tk-1tfzr71.12, head of lane A | step-close, the work-tree holder, the lease wrapper, `molecule-hold.sh`, the work formula's copies of core's steps | 3,340 | tk-iirrmiw |
| tk-1tfzr71.10, head of lane B | the worktree reaper and wrapper | 2,233 | tk-iirrmiw |

### 3. The lanes

Each member is armed behind the one before it, and at most two migrations are
in flight at once, on disjoint subsystems. A member whose method is a design
convoy lands only after the operator approves its design.

| Lane | Member | What it removes | Size |
|---|---|---|---|
| A | tk-1tfzr71.11 | per-site read-backs, about 130 blocks in 46 files | partial files |
| A | tk-1tfzr71.20 | the merge cadence, the approval rule, rework and branch currency; the operator rules at its design | 10,899 |
| A | tk-1tfzr71.22 | review beads, lane derivation, validation passes, machine findings | 10,643 |
| A | tk-1tfzr71.21 | `pr-facts.sh` polling and mirroring | 14,850 |
| A | tk-1tfzr71.23 | the membership readers on parent-child, since tk-tggczbp's branch deletes graduation and the convoy seed | partial files |
| B | tk-1tfzr71.14 | the rig checkout healer; the operator rules at its design | 2,716 |
| B | tk-1tfzr71.13 | the duplicate sweep and the successor keys | 1,053 |
| B | tk-1tfzr71.15 | raw route stamps and the checks that police them | 1,173 |
| B | tk-1tfzr71.16 | deferred dispatch's notify path, lock, budget and crash marker | partial files |
| B | tk-1tfzr71.17 | the reaction bead and the intake converters | 189, plus partial files |
| B | tk-1tfzr71.18 | warrants, the dance, pin keepalive, boot health, quota park, each after its re-check | 5,571 |
| B | tk-1tfzr71.19 | the doctor runner, the liveness census, the incident ledger, the copied patrol steps | 7,859 |
| B | tk-1tfzr71.24 | the board's second data plane and pack-stamped rows, verbs that only call Gas City | partial files |
| B | tk-1tfzr71.25 | registry entries, wrapper lint rules, parity tests, unused tools | 2,688 |

The whole files that tk-o6pd01i, tk-kvdomjb and the migration members name come
to 64k of the 187k between the baseline and the target. Their partial rewrites
carry more, chiefly the board, `gc-helm.sh`, the work and patrol formulas,
deferred dispatch and the sign-off. The proposals below carry the rest.

### 4. Proposed

No bead carries these. Each waits for the operator to fund it.

| # | Proposal | Extent | Trigger | Waits on | The cost of waiting |
|---|---|---|---|---|---|
| P1 | Wire the discipline below: move `measure.sh` into `tools/`, add a size lens to the arch check's extension ([review-arch.md](review-arch.md)), and add the predicted net to an epic's contract ([epics.md](epics.md)) | about 150 lines of tooling and prose | the operator adopts this page | tk-iirrmiw, whose branch rewrites review-arch.md | each change lands unmeasured, so nothing stops a net-positive epic |
| P2 | Delete the dead code now | 1,675 lines | nothing calls it, and the approval migration's dry run finds nothing to change | nothing | three of the four files wait for the end of lane B, and the fixture for no bead at all |
| P3 | One decline call, replacing the 20 copies of the decline sequence in step text | 20 copies, 29 refusal sentences | none | tk-c8724xi, which edits the same files and whose scope this extends | every new step that declines copies the sequence again |
| P4 | Step text calls tested scripts, and the block-extraction tests go | 3.9k lines of shell in step text, 52 tests of 16.4k lines | none | tk-1tfzr71.12, .19 and .20, which rewrite those formulas and apply it as they do | each block test grows with its block |
| P5 | The Go port (tk-ssm8qns) ports only the map's surviving intents, and each port deletes the shell it replaces in the same change | the port's contract | the port is armed | its blockers | while shell and Go both hold a domain, the domain has two implementations |

## The measurement discipline

The discipline holds a change to the target the way the divergence lens holds
it to Gas City. Until P1 wires it into review, nothing applies it on its own,
and the operator can apply it by hand with `measure.sh`.

1. **An epic predicts its net.** Before its first unit is slung, an epic's
   contract states the net runtime and test lines it expects to land in each
   subsystem it touches, and the target each moves toward. An epic that grows a
   subsystem already above its target says why.
2. **A change reports its landed net.** A PR's summary states its net runtime
   and test lines, measured from the merge base to its head.
3. **Review compares the two.** A unit that lands more than its share of its
   epic's prediction is a finding, and so is a fix that grows the pack without
   naming the design change it defers. The change answers the finding, or the
   operator waives it.
4. **The target's rules hold every change.** New code says each fact once and
   keeps its comments to reasons, and a fix's test pins the behavior in the one
   place it lives.
5. **A target is a ceiling.** It rises only by an operator ruling, recorded on
   this page with its reason.

## Keeping it true

- A change that lands a schedule row removes the row.
- A change that completes a stage of the schedule re-measures the baseline
  table, so the baseline is never more than one stage old.
