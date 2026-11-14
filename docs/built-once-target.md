---
name: Built-once target — the shape gc-toolkit would have if built once, and where its weight is
description: What gc-toolkit would be if built once on Gas City as shipped, with each subsystem's estimated weight beside what it weighs at the baseline; what the tree carries that has no place in that shape and what retires it; the order the removals land in; and the rules every change follows. Read it before filing or building work in code the deletion plan retires, before writing formula step text, and when reading a PR's size change.
---

# Built-once target

Built once, on Gas City as shipped and with every fact said in one place,
gc-toolkit would weigh an estimated 64k lines: 35.0k of runtime and 28.5k of
tests. At the baseline it weighs 283.9k: 122.2k of runtime and 161.7k of tests.
The estimates show where the weight is. They set no limit, since useful code
grows. [The rules](#the-rules) aim at code written without value to the
operator: no new work in code the deletion plan retires, no procedures in step
text, and a computed size change on every PR. The migration epic's members
(tk-1tfzr71) carry most of the removals below.

## Scope

**Mandate.** The built-once shape of each gc-toolkit subsystem, with its
estimated weight beside its measured size, what the tree carries that the shape
has no place for and the trigger that retires it, the order the removals land
in, and the rules every change follows.

**Boundaries.** Which primitives the pack is built from, and which workflow a
component belongs to, is [component-model.md](component-model.md). What belongs
in the pack at all is [foundation.md](foundation.md#boundaries), and why a pack
noun survives beside Gas City is [warrants.md](warrants.md). Each removal's
design lives on the bead that carries it. A removal is scheduled only when a
bead carries it, and the operator funds each one.

## How the pack is measured

- **A line** is a physical line of a tracked text file at a commit, as
  `git diff --numstat` counts it. A symlink or a binary file counts nothing.
- **Pack weight** counts these kinds of line. Code is scripts, Go and the
  board's web source. Flow is formulas, orders and the other TOML and JSON config. Text
  is agent prompts, fragments and skills. Test is tests and their fixtures.
  Runtime is code, flow and text.
- **Beside the pack** are docs (18.9k), the tooling under `tools/` and
  `.github/` (16.0k), the record under `specs/` (87.3k) and generated files
  (6.9k). They are reported beside pack weight and are not part of it.
- **A path's subsystem** is its row in
  [component-model.md](component-model.md#4-where-each-component-sits) §4, and
  a test takes its script's row. §4 has a row for 114 of the 140 runtime
  scripts under `assets/scripts/`, and the measuring script's rules place the
  other 26 (6.4k lines).

`tools/measure.sh [REF]` prints a commit's table, `measure.sh BASE HEAD`
prints what a change adds net of what it removes, and `measure.sh --pr BASE
HEAD` prints a PR's size section ([rule 3](#the-rules)). The baseline is main
at 25cda8ace (2026-11-12). Every number on this page is derived in
[the measurement record](../specs/tk-1tfzr71.95/measurement.md).

## The built-once shape, subsystem by subsystem

Each subsystem's estimate is the weight of what survives in it, under these
assumptions:

- **Gas City as shipped.** Where Gas City ships the primitive, the subsystem
  is a call to it, and the pack's version weighs nothing.
- **Said once.** A fact, a rule or an idiom has one home, and a call site
  carries only its own facts. A comment states a reason the code cannot show,
  which the estimate puts at about 15% of a runtime file. Runtime shell is 36%
  comment today, and Go 29%.
- **Tests follow code.** The estimate puts a subsystem's tests at about the
  weight of its code and flow. A test pins the behavior of the one copy where it
  lives. No test extracts formula step text to run it, holds two copies equal,
  or asserts that a retired name stays retired.

| Subsystem | Built once, it is | Baseline runtime / tests | Built once, estimated runtime / tests |
|---|---|---|---|
| work | one formula extending core's polecat base | 6.4k / 10.4k | 2.5k / 2.5k |
| review | the declared checks as lanes of one check loop | 11.7k / 11.8k | 4.0k / 2.0k |
| merge | the pack's own refinery on Gas Town's flow and record, with the pack's approval contract | 15.4k / 25.2k | 2.0k / 2.0k |
| human engagement | native human gates and conversation tasks | 16.8k / 25.0k | 5.5k / 4.0k |
| board | a ranked render of platform objects | 21.0k / 26.4k | 5.0k / 5.0k |
| patrol | Gas City's orders, plus the patrols' judgment | 9.5k / 16.1k | 2.5k / 2.0k |
| doctor | one check per surviving invariant | 7.5k / 9.3k | 3.0k / 3.0k |
| shared glue | one call per series of native steps | 10.6k / 24.0k | 5.0k / 5.0k |
| gctk | the rig's actions: its check runner and records, and a copy of its UI | 11.5k / 10.6k | 1.5k / 1.5k |
| feedback | the learning loop | 2.4k / 1.9k | 2.0k / 1.5k |
| config | the pack, its check index and its key registry | 2.9k / 0 | 0.7k / 0 |
| doctrine | shared fragments and skills | 2.6k / 0 | 1.3k / 0 |
| keeper sub-pack | nothing: the built-once shape has no fork | 3.8k / 1.1k | 0 / 0 |
| **total** | | **122.2k / 161.7k** | **35.0k / 28.5k** |

The keeper is the opt-in `packs/gascity-keeper/`.

### Work

`mol-polecat-work` extends core's `mol-polecat-base` and overrides only what
differs: load-context's refusals, the per-bead worktree, cut with git and removed
at the handoff as core's own variants cut and remove theirs, the pre-flights and
the self-review loop over `gctk rig` records, and the push and handoff, each for
the reason its warrant gives. Each step closes
through `gc hook current`, and a decline is one call. Work owns the work branch
and the handoff write. Priority following stays under its warrant, and deferred
dispatch shrinks to the residual tk-1tfzr71.16 keeps under a warrant: sling on
unblock.

The trade: `implement` is core's, so a pack refinement of it goes in the polecat
doctrine or waits for upstream. A step inherited from core declares no
continuation group, so a session may take `implement` fresh.

### Review

The declared checks run as lanes of a formula check loop, each check's method
is its skill, and triage widens the check set. Review owns the check index
(`review-checks.toml`) and the methods, which are prose, and the demo
modalities. The shape of the loop is what tk-1tfzr71.22's design settles.

The trade: review beads, lane derivation, validation passes, machine finding
beads and the sweeps that close their leftovers go, and a lane's verdict lives
in the loop. A person's finding on a PR stays a record the operator rules on.

### Merge

The pack's own refinery lands a branch directly or publishes it as a PR, and
Gas Town's pending-through-merge record keeps the work's bead open until the
merge is verified on the target. The pack adds one approval contract for every PR the
city opens, on any target, in one evaluator of the PR's readiness that the
board and the merge read, a merge request pinned to the head the evaluator
judged, the PR's managed summary and title, and the step that takes a GitHub
event to the bead that owns it.

The trade: the pack's transition machine, its second copy of the approval
rule, the merge cadence's arms with their lock, cursors and crash detection,
and the rework and branch-currency machinery give way to Gas Town's record,
the bring-current-or-requeue of the pack's refinery, which merges the target in
where Gas Town's rebases, and one landing order. The approval behavior stays the
pack's, because no rule of GitHub's covers an integration branch, and the
operator ruled at tk-1tfzr71.20's design that the city requires an approval on
every target.

The refinery's target is Gas Town's refinery, and its patrol takes Gas Town's
steps one for one. The pack keeps a refinery of its own because the city imports
no gastown pack, and no gastown release carries the pending-through-merge record
yet. Each remaining difference names its reason and what ends it:

- **Merge, never rebase.** The refinery brings a branch current by merging its
  target in, and every push is a fast-forward. A push onto a work's branch goes
  under git's lease on the commit the writer read there, once the writer has
  checked that the new head descends from it, so the lease never forces. Gas
  Town rebases, and in `mr` it force-pushes with a lease that names no commit.
  A PR keeps the commits its approval and its threads were given on, and a push
  someone else made is refused, never overwritten. No end is planned.
- **A requeue keeps the branch and the PR.** Work the refinery will not land
  goes back to the pool through `gc sling` with its branch kept, as the bead
  itself when it has no PR open, and as its PR's rework child when it has one.
  Gas Town writes the pool route by hand and deletes the branch after a failure
  the branch caused. Dispatch goes only through `gc sling`, and deleting a PR's
  branch closes the PR. This ends when Gas Town requeues through `gc sling` and
  keeps the PR of a bead it sends back.
- **A pre-existing failure is tracked by its key.** `preexisting-failure.sh`
  keys a failure already on the target by its symptom, where Gas Town searches
  open bugs by title. Two agents title one failure two ways, and the key finds
  the tracker after a retitle. This ends when Gas Town keys its tracker.
- **Human gates in place of mayor mail.** Where a person must act, such as the
  refinery's park or an exception the landing order finds, the pack files a
  human gate on the bead, keyed by the case. Gas Town routes the bead to
  `human` and mails the mayor. The po owns only what a ruling gives it. This
  ends when an operator ruling gives the po escalation handling.
- **The PR opens as a draft.** The review loop (tk-1tfzr71.22) returns it to
  draft for each later round of the city's work and marks it ready once the
  lanes before the ready-for-review phase pass. Gas Town opens it ready and
  never returns it to draft. The city's checks run on the PR before it asks the
  operator, and a repository whose workflows skip drafts runs its CI on the
  head the loop marks ready. No end is planned.
- **The city merges.** The landing order asks GitHub to merge the head the
  refinery validated once the evaluator finds the PR ready, where Gas Town
  leaves the merge to a person. The operator approves and the city lands the
  PR, on every target. No end is planned.
- **Only the city's own PRs.** The `mr` step takes a PR only when the city's
  account opened it, and parks the bead behind a gate when another account
  opened the PR on its branch. Gas Town takes the PR open on the branch and
  never checks its author. The city merges every PR it takes, so its contract
  covers only the PRs it opens. No end is planned.
- **The record's writers.** The pack writes Gas Town's pending-through-merge
  record itself (`gctk pr record`, `gctk pr reconcile`), from a landing order
  rather than from the refinery's find-work, and its reconcile also decides
  readiness and requests the merge. Both writers take the store's record lock,
  and each write is guarded on the bead's status and assignee, so a bead that a
  close or a release reached first gets no record, and a run leaves a bead a
  release took as the release left it. Gas Town's one refinery session
  reconciles once per find-work, writes the record unconditionally and assigns
  the bead to the refinery at each check. No gastown release carries the
  command, and an order holds no session while a PR waits on its approval or
  its checks. This ends when the city takes a gastown release that carries the
  command, refuses a bead a close or a release reached first and leaves a bead
  a release took. The record and the close then become that command, and the
  pack keeps the readiness check and the merge request.
- **A refused close is an exception.** A verified merge whose close bd refuses,
  for an open child or a live blocker, is recorded as
  `pull_request_merged_close_refused`, with the merge's evidence, behind a human
  gate. Gas Town keeps the marker and tries the close again on each run, with
  nothing escalated. What holds the close is no fact a run can change, so a
  retry alone leaves a landed merge holding its work with no one told. This
  ends when Gas Town's command escalates a close it cannot make.
- **find-work reads waits.** It skips a bead something holds or whose branch
  another open bead works on, and takes a rework child before its anchor. Gas
  Town takes any bead assigned to the refinery. Two writers on one branch would
  overwrite each other's work. This ends when Gas Town's find-work reads waits.
- **A branch already on its target.** A direct landing an earlier pass pushed
  but did not record is recorded `merged`, at the commit the bead's
  `direct_landing_sha` names, and any other branch with no change is refused as
  `refused_false_completion`. Gas Town closes a branch that is an ancestor of
  its target, with a commit since its recorded fork point, as `already_merged`.
  Every reader that asks whether a direct landing happened asks one value. No
  end is planned.
- **The gate runs detached.** The rig's checks run as one `detached-job.sh`
  job, where Gas Town runs each inline, because a tool call is cut off at ten
  minutes and a gate can run longer. This ends when the gate runs where no tool
  call bounds it.
- **The integration-effort hand-off.** The refinery brings an integration
  effort's branch current with its target (`effort-bring-current.sh`). Gas Town
  has no integration efforts. This ends when the convoys member (tk-1tfzr71.23)
  moves efforts onto `gc convoy land`.
- **One worker per branch.** A conflict on a branch whose rework child is open
  goes to that child's notes. Gas Town has no rework children. This ends when
  the review loop (tk-1tfzr71.22) takes review feedback off rework children.

### Human engagement

What a person owes is a native human gate on the bead it blocks, and a
conversation is a task. A sitting is a converse session that holds the
conversation doctrine, and it also edits a change on the operator's ruling,
through Work's writers. Intake is slung work whose exits are native writes. The
subsystem owns the converse, first-reaction, mechanik and po prompts, the
converse skills and the po's refinement skill, the operator's intake and the
terminal surfaces.

New work no epic holds is owed to nobody. It carries Gas City's `hold:mayor`,
and its rig's po, a fresh on-demand session chartered as the operator's
prioritization partner, works that queue with the operator. A hold is the next
actor's queue, and a gate is an answer someone owes.

The po takes the agent shape of Gas Town's mayor, `wake_mode = "fresh"` and
`max_active_sessions = 1`, once for each rig: `scope = "rig"` and a rig
worktree, `work_dir = ".gc/worktrees/<rig>/po"`. Each difference names its reason, and each
but the last ends with an operator ruling that gives the seat the job:

- **Named `po`, not `mayor`.** Gas City's defaults and Gas Town's roles aim at
  the name `mayor`, so a seat that answers to it takes their sends. SAFe's word
  names the job.
- **One for each rig, where Gas Town's mayor is one for the city.** A rig's
  queue and its epics are weighed against that rig's target, so each rig's po
  works its own, one sitting at a time.
- **The operator's prioritization partner, not the human's point of contact.**
  It works backlog refinement and portfolio sync, by the operator's charter.
- **It places, parks and moves priority once the operator agrees in a sitting,
  where Gas Town's mayor dispatches liberally.** It owns little, and the final
  say is the operator's.
- **It changes no repo, where Gas Town's mayor fixes directly when that is
  fast.** The pools do the work, and mechanik edits the town repo.
- **It files or points, where Gas Town's mayor handles escalations.** Findings
  and human gates carry them.
- **It reads a rig's wake and sleep, and changes neither.** Those are the
  operator's and mechanik's.
- **No `gc handoff` and no carried memory.** A context carried from sitting to
  sitting would make the seat resident again.
- **`sleep_after_idle = "1h"` in place of `idle_timeout = "1h"`.** Gas City
  applies no `idle_timeout` to an always-on seat, so the mayor's hour never
  fires. The po is on demand, and it takes its hour as Gas City's idle sleep: a
  sitting no client is attached to sleeps once the hour has passed, and the
  operator's next attach starts a new sitting. This ends if the po runs always
  on, as the mayor does.

The trade: the first reaction stops being a bead kind of its own
(tk-1tfzr71.17).

### Board

The board renders platform objects (beads, human gates, conversations and the
supervisor's objects) read through the supervisor API, and ranks them by the
pack's attention model.

The trade: the second data plane that reads the store directly, the rows that
exist only because a pack writer stamped a route, and the hand-written
TypeScript mirror of the Go contract with the parity test that holds the two
equal all go. The web page is the board's one view for people, and
`helm-svc board --json` prints its rows for agents.

### Patrol

Gas City's orders keep the fleet clean: core's orphan sweep, reaper, wisp
compaction, spawn-storm detection, convoy backstop and branch pruning, the
controller's closed-bead worktree reaper, and the dolt pack's orders. The
pack's patrols carry only judgment: the witness's HELP-mail triage, salvage and
watch on the refinery's queue, and the deacon running `gc doctor` from an
order. Patrol owns the warranted Dolt reclaim and suspended-store backup, and the
reapers no native one covers: scratch and the review workspaces outside
`.gc/worktrees/`.

The trade: the liveness census stops filing human gates, the incident ledger
moves onto events and bead notes, and the dog's due process moves to the
controller's stall handling or to Gas Town's dance (tk-1tfzr71.18 and .19).

The witness's target is Gas Town's witness. Each remaining difference names its
reason and what ends it:

- **The spacing.** Its `next-iteration` defers the next wisp an hour, so Gas
  City's reassignment restart starts the next pass once the hour has passed. Gas
  Town's asks for that hour through `idle_timeout = "1h"`, which Gas City does
  not apply to an always-on session, so there its passes run back to back. This
  ends when Gas City gives an always-on patrol an idle interval.
- **Reading our anchors, PR states and conversations.** Our pipeline writes them.
  This ends as the old merge path's retirement (tk-1tfzr71.70) and tk-1tfzr71.22
  land.
- **Findings and human gates in place of mayor mail.** Gas Town's witness mails
  the mayor about emergencies, failures, recovered and handed-off orphans and
  queue health. This one files findings and human gates instead, because the po
  owns little and takes none of that load, and the operator ruled at
  tk-rl8gz4b.29's design that it stays. This ends when an operator ruling gives
  the po escalation handling. Gas Town's formula addresses `mayor/` by name,
  which reaches no seat in this city, so a copy taken by import would send its
  escalations to no reader. Such a copy keeps findings and human gates, or the
  import is ruled (tk-1tfzr71.19).
- **No stuck-polecat check.** The liveness sweep covers it. This ends when
  tk-1tfzr71.19 retires the sweep.
- **The nudge order.** Gas Town's deacon does this through a command and a step
  we do not carry. This ends when we take Gas Town's deacon or Gas City closes
  issue #4090 with a fix that also reaches a session stopped short of
  `next-iteration`.

### Doctor

Doctor keeps one check per invariant of a surviving pack noun or warranted
mechanism, and the checks of molecule execution (I8, I11 and I13) become one.

The trade: a check retires with the noun it guards, such as the anchor, a
lane, a raw route or a dispatch arm.

### Shared glue

Shared glue is one call per series of native steps that more than one workflow
runs: the store helpers, the human-gate helper, findings, run cancel,
hand-back, one decline call, one check that a `blocks` edge's two ends share a
store, PR posts with their provenance mark, the gh write guard under its
warrant, and the seed audit.

The trade: per-site read-backs give way to each write's own exit
(tk-1tfzr71.11).
The wrapper that provisions an agent's home stays under its warrant, because
`gc worktree` binds a tree to one bead and a home outlives every bead.

### gctk

`gctk rig` runs a rig's declared checks and records each result against the
commit it ran at, and runs a copy of the rig's UI from a checkout, which a demo
capture records and a sitting shows the operator. The copy came after the
baseline, so the estimate above does not weigh it.

The trade: `gctk merge`'s approval rule goes with the merge member, and its
compiled copy of the key registry goes with the registry. A domain moves into
gctk only when it survives the migration map, and it moves whole: the change
that ports it deletes the shell it replaces, and the PR's size line
([rule 3](#the-rules)) shows the port's net.

### Feedback, config and doctrine

Feedback is the miner and distiller formulas, the distiller's memory step and
the `memory-intake.sh` script it runs, the learning-distill skill and their
orders, and saying each fact once is the only cut its estimate takes.
Config is `pack.toml`, the check index, the overlays, the pack command, and a
key registry that declares only the keys of surviving warranted nouns, as data:
1,494 of the registry's 1,854 lines are comments today. Doctrine is the shared
fragments and skills, with each doctrine sentence in one home.

### Keeper sub-pack

The keeper maintains a fork of Gas City, and foundation answers a missing
primitive by reshaping the feature, never by a fork. It retires by its own
page's trigger, a fork with no diverging commit
([fork-patching.md](fork-patching.md#when-this-doc-should-disappear)). The fork
carries 77 today. The migration map keeps the keeper until then, and no bead
carries its retirement.

## What has no place in the built-once shape

Each piece names its extent at the baseline, the trigger that retires it, and
the bead that carries it.

### Shadow machinery

Gas City ships each primitive below, so its trigger has fired. Each was verified
present on 2026-10-26, at Gas City upstream main f78779e41 or in the installed
bd 1.3.2.

| Pack machinery | Gas City's primitive | Carried by |
|---|---|---|
| the hand-stamped routes in code other members retire, and the rescues that repair them | `gc sling --no-formula`, assignment | the member that retires each, tk-1tfzr71.17 to .22 |
| `orphan-dispose.sh`'s generic arms | core's orphan-sweep | tk-1tfzr71.19 |
| `pr-facts.sh` polling and its mirrored keys | the PR monitor and webhook receiver | tk-1tfzr71.21 |

### Copied boilerplate

A copy needs no trigger. It goes as soon as a change gives the fact one shared
home.

- The script-dir resolution: the candidate loop in the Claude Code overlays, which
  gc copies into a session with no template pass, so their text cannot name the
  binding. Carried by tk-rzic0sg. All other pack text asks gc, in one line per
  shell block that runs a pack script, since each block is its own shell.
- The decline sequence (file the human gate, cancel the run, drain): two copies
  in the step text of `mol-validate.toml`, which tk-1tfzr71.22 retires. Outside
  that file a decline calls `decline.sh`. `mol-review`'s failed gather cancels
  its own run, because it returns the review to its pool through `gc sling` once
  the cancel has landed.
- A rule kept in two languages, with a test holding the copies equal:
  `gctk merge` and `review-verdict.sh`, `gctk lifecycle` and the key registry,
  and the board's Go contract and its TypeScript mirror. Carried by
  tk-1tfzr71.70, the old merge path's retirement, and tk-1tfzr71.25.

### Compatibility debt

A compatibility piece carries a dated debt and the trigger that retires it,
and the change that fires the trigger deletes it.

- Readers of legacy shapes, which "legacy" names 23 times across 12 runtime
  files: the `gc.proactive_reaction=1` proof and PR bodies older than the
  managed region, among others. Trigger: no store or open PR holds the shape.
  Each goes with the member that rewrites its reader.

### Doctrine restated per call site

A restatement needs no trigger either, once the doctrine has its home.

- Comments: runtime shell is 36% comment (20.7k of 58.2k lines), Go 29%, the
  key registry 81% and the orders 65%.
- Formula step text: 2.8k of the formulas' 7.4k lines are shell inside code
  fences, and step prose restates doctrine the fragments hold. Rule 2 keeps new
  procedures out of step text.

### Tests that pin what should not exist

- 41 test files, 13.1k lines, have no script of their own. Each reads a marked
  block of formula step text, to run it or to pin its text, and 9 script tests
  read one too. Trigger: the step's mechanics become one call to a script with
  its own test, as rule 2 requires (P4).
- Tests that hold two copies equal, and tests that assert a retired name stays
  retired. Trigger: the copy or the name is gone. Carried by tk-1tfzr71.25.

## The deletion schedule

Stage 1, the native-gates convoy (tk-iirrmiw) and its cutover (tk-o6pd01i),
has landed, and so has stage 2, the removals its landing released. The baseline
is main at the commit that landed the last of them. Stage 3 runs in the order
below, and each of the page's own items starts when what it waits on lands. An
armed bead is blocked by what it waits on and slings itself when that lands. A
size is the lines of the whole files a bead's contract retires, with their
tests, at the baseline, so a bead that also rewrites part of a file retires
more than its size. A branch already in flight shows its measured net instead.

### 3. The lanes

Each member is armed behind the one before it, and at most two migrations are
in flight at once, on disjoint subsystems. The old merge path's retirement
(tk-1tfzr71.70), last in lane A, is the exception: it is armed behind every
rig's cutover, and each cutover waits on tk-1tfzr71.22. A member whose method
is a design convoy lands only after the operator approves its design.

| Lane | Member | What it removes | Size |
|---|---|---|---|
| A | tk-1tfzr71.22 | review beads, lane derivation, validation passes, machine findings, the bring-current guard and audit | 13,615 |
| A | tk-1tfzr71.21 | `pr-facts.sh` polling and mirroring, the merge cadence's driver and its pacing, the failure cap and the supersession check | 18,145 |
| A | tk-1tfzr71.23 | the membership readers on parent-child | partial files |
| A | tk-1tfzr71.70 | the old merge path, once every rig's cutover has moved its PRs onto the pending record: `gctk merge` and the transition machine, `pr-open.sh`'s create, `pre-open-rebase.sh`, `merge-tail-report.sh` | 1,288, and the rows it adds |
| B | tk-1tfzr71.17 | the reaction bead and the intake converters | 189, plus partial files |
| B | tk-1tfzr71.18 | warrants, the dance, pin keepalive, boot health, quota park, each after its re-check | 5,838 |
| B | tk-1tfzr71.19 | the doctor runner, the liveness census, the incident ledger, the copied patrol steps, the salvage's branch context | 8,317 |
| B | tk-1tfzr71.24 | the board's second data plane and pack-stamped rows, verbs that only call Gas City | partial files |
| B | tk-1tfzr71.25 | registry entries, wrapper lint rules, parity tests, the `board` stub verb | 1,490 |

The whole files that the migration members name come to 49k of
the 220k between the baseline and the built-once estimate. Their partial
rewrites carry more, chiefly the board, `gc-helm.sh`, the work and patrol
formulas and the sign-off. The page's own items below carry
the step-text tests.
Most of the comment and test weight of the code that survives has no bead.

### 4. The page's own items

Each item is carried by the bead it names.

| # | Item | Extent | Carried by | Waits on |
|---|---|---|---|---|
| P4 | Rule 2: step text calls tested scripts, and the block-extraction tests go with the blocks they extract | 2.8k lines of shell in step text, 41 tests of 13.1k lines | tk-1tfzr71.19, applying it to the formulas it rewrites | its place in its lane |
| P5 | Each Go port (tk-ssm8qns) carries only the migration map's surviving intents and deletes the shell it replaces in the same change, and rule 3's size line shows its net | the port's contract | a note on tk-ssm8qns | the port's blockers |

## The rules

Every change follows these rules.

1. **Code the deletion plan retires gets no new work.** The plan is the
   schedule above, and [`tools/deletion-plan.tsv`](../tools/deletion-plan.tsv)
   lists the whole files it retires, each with the bead that retires it.
   [AGENTS.md](../AGENTS.md) says what becomes of a problem found in that
   code. Every session that works in a gc-toolkit worktree loads it, a first
   reaction's included, and the mechanik's prompt points at it.
2. **Step text holds no procedures.**
   [pack-authoring.md](pack-authoring.md#step-text-calls-a-tested-script)
   states the rule where formulas are written, and `tools/lint-step-text.sh`
   fails a change that adds a procedure to step text.
3. **Every PR shows its size change.** The size line is computed from git, from
   the merge base to the head: the net runtime and test lines, by subsystem. It
   names separately the lines the change adds to code the plan retires, and the
   bead that retires each. It carries no budget, no prediction and no stored
   history. The PR's CI test run time can sit beside it as information.
   `tools/measure.sh --pr` computes it, and gc-toolkit's CI
   ([pr-size.yml](../.github/workflows/pr-size.yml)) posts it on each PR as one
   comment that it rewrites on each push and each change of the PR's base
   branch.

## Keeping it true

- A change that lands a schedule row removes the row, and a change that
  retires a file removes its row from `tools/deletion-plan.tsv`.
- A change that completes a stage of the schedule re-measures the baseline
  table, so the baseline is never more than one stage old.
