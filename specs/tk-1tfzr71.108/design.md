---
name: Design — a PR's checks run as lanes of one review run per head, attached to the bead that owns the PR
description: The design for tk-1tfzr71.108, the design child of initiative tk-1tfzr71.22, read at main f21639824 against Gas City upstream main 13bb101b8f and gascity-packs main 0f07496d2f. It replaces review beads, lane derivation, machine finding beads, validation passes and fix units with one formula check loop per PR head, whose lanes triage picks at that head, whose rule step rules every finding by its own lane's rule and whose repair step is the branch's one writer. It settles the draft cycle, the approval withdrawal, a person's comment until the intake member lands, the readers, the held problems, the shadow comparison, each rig's cutover and the units. Read it to approve the design at its gate, or to build one of its units.
---

# Design: a PR's checks run as lanes of one review run per head

This is the design record for tk-1tfzr71.108, the design child of the initiative
tk-1tfzr71.22. The pack was read at main f21639824, the commit
`integration/tk-1tfzr71.22` was cut from. Gas City is cited by symbol or page at
`gastownhall/gascity` main 13bb101b8f, and its packs by path at
`gastownhall/gascity-packs` main 0f07496d2f. The contract this design builds is
section 11 of the merge design
([specs/tk-1tfzr71.66/design.md](../tk-1tfzr71.66/design.md)), and the
operator's requirements and rulings recorded on tk-1tfzr71.22. The search behind
each piece of surface the units add is [gas-city-search.md](gas-city-search.md).

## What the operator approves

Today each check on a PR is a review bead that a merge-cadence pass files and
sends out. A sign-off script records its verdict and files each finding as a
bead, a validation pass rules the findings and decides whether the lanes
converged, and a rework child fixes them. Sweeps close what is left over. That
is how fixes merged with no triage after a convergence ruling (PRs #1305 and
#1481), how one lane's finding closed when another lane's fix landed, how demo,
pm and arch findings were ruled without that lane's evidence, how declined
findings went unanswered on the PR, how your nits were ruled must-fix and fixed
outside the reviewed diff, how wedged reviews held approved PRs for up to five
days, and how fix units filled the pool while their rulings waited for a slot.

Approving this design changes that, for every rig once it moves onto the
pending-through-merge record:

- **One run per head.** For each head the refinery validates on a PR, the city
  runs one review run, attached to the bead that owns the PR so the bead is
  held while the run works. Triage reads the change at that head and picks the
  checks it needs. Each picked check runs as a lane, by its own method. One step
  then rules every finding by that lane's own rule for what blocks, with that
  lane's evidence still on disk, answers each one on the PR in one comment for
  the head, and fixes what must be fixed. A fix is a new head, so the run
  triages its own fix before it can pass. The run ends with a result for the
  head and the target it judged, and the merge counts only that result. A head
  that only merges the target in costs the run's prepare, triage,
  rule-and-repair and record steps and no lane, because triage picks no check
  when git merged it without help.
- **The draft.** The PR is a draft while the city works on it. A round of the
  city's work returns it to draft before its first push, and the landing order
  marks it ready once the run has passed at the head the refinery validated,
  without waiting for CI.
- **Your approval** carries across rounds. When triage rules a head a material
  change, the city dismisses the approvals given before it, and the PR waits
  until GitHub shows them dismissed and you approve again.
- **Your comments** end the way your workflow for PR comments says: fixed and
  resolved, declined with the reason and resolved, or a question to you through a
  gate. The city grades each one on the bar the correctness method uses for a
  reviewer's finding, so a nit is answered rather than fixed into the PR.
- **A failed run** is poured again by the landing order. When a second run at the
  same head also ends without a result, a gate asks you, and the board names it
  as the machine's fault.

These calls carry a cost either way. The rulings so far do not settle them:

1. **Who fixes what the run rules must-fix.**
   - (a) The step that rules the findings also fixes them, in the same session.
     Each round costs one session, and the ruler is the fixer, as in your
     workflow for comments, where the city evaluates a comment and acts on it.
   - (b) A ruling step, then a separate fix step. Each round costs a second
     session, and no agent fixes what it ruled.
2. **A fix that reaches outside the reviewed diff** (proposed by the sitting in
   conversation tk-bap2vqv, not ruled).
   - (a) It goes to a bead of its own, armed to start once the PR lands, and the
     comment it answers says so. The PR stays the change you reviewed.
   - (b) It goes into the PR. The PR lands whole, and triage reads the fix, but
     you review code you did not ask for, as on PRs #1482 and #1483.

Approving as it stands ships the first option of each. The old review path keeps
running on each rig until that rig's cutover, and its code retires in a bead of
its own once every rig has moved (section 11).

## 1. The review run

### What pours it

A run judges one head of one PR. The landing order pours it, because the merge
design makes the order the one path that admits work on a pending record
([section 4](../tk-1tfzr71.66/design.md#4-where-triage-sits-and-how-the-city-decides-to-merge)).
Each order run already reads each record it checks and asks the evaluator
whether its PR is ready. The order pours a run for a PR when the answer at the
head the refinery validated includes `review` (no passed result for the live head
and target), or when the bead carries an open ask the run can take (below). It
pours only when nothing else writes the branch: no run is attached, no open bead
other than an ask names the branch, and no conversation's gate is on the bead,
since a sitting may be editing it. It pours none while a human gate holds the
bead, because a gate asks a person and the next run starts from the answer
(sections 6 and 7).
The pour runs under the record lock the order already holds for that record:

```bash
gc formula cook mol-pr-review --attach <bead> --var pr_bead=<bead> --var head=<head> --var target=<target> --var branch=<branch>
```

`gc formula cook --attach` is Gas City's primitive for late-bound expansion:
"any agent, script, or workflow step can call it to expand a bead into a
sub-workflow at runtime" (`docs/reference/cli.md`, `gc formula cook`). On a v2
formula it does four things this design rests on, at 13bb101b8f:

- The attached bead gains a `blocks` dependency on the run's root
  (`ensureFormulaCookAttachDep` in `cmd/gc/cmd_formula.go`). The bead is held
  while the run lives, through the edge the evaluator already reads as a wait,
  and the refinery's find-work skips a held bead, so no other writer reaches the
  branch while the run works it.
- The root names no source bead. The cook arm decorates the recipe with an empty
  source (`decorateFormulaCookGraphV2Recipe` passes none to
  `graphroute.DecorateGraphWorkflowRecipeWithDefaultBinding`), and finalize
  closes or marks only a root's `gc.source_bead_id`
  (`annotateSourceBeadFailure` in `internal/dispatch/runtime.go`). So no end of
  the run closes the bead that owns the PR, which the merge design forbids.
- The bead becomes the run's input through a one-item input convoy
  (`NormalizeInputConvoy` in `internal/graphv2/invocation.go`).
- Each step routes itself by its own `gc.run_target`, which the decoration turns
  into `gc.routed_to` (`internal/graphroute/graphroute.go`).

A city that serves the graph class from a storage binding of its own refuses a
v2 attach in a rig's store (the same page). This city is single-store
(`gc storage status`: every class served by the work store), and a city that
binds the graph class later pours the run with `gc sling <pool> mol-pr-review
--formula` and writes the `blocks` edge itself, in the run's first step.

The order counts no run as live from a list of its own. The runs attached to a
bead are its `blocks` edges onto roots of `mol-pr-review`, open or closed, and
each root carries the vars it was poured with. A closed root is the history the
order reads to re-offer a run (section 7).

### The formula

`mol-pr-review` composes Gas City's multi-lane review loop
([understanding-formulas.md, "Multi-Lane Review Loops"](https://docs.gascity.com/guides/understanding-formulas),
whose shipped example is `gascity/formulas/build-basic-review.formula.toml` in
gascity-packs). The loop is a `[[template]]` step carrying a `[template.check]`,
with the lanes and the steps after them as `[[template.children]]`. While the
check reads "not yet" and attempts remain, the orchestrator pours the whole
subtree again as the next iteration. A step cannot combine `check` with `expand`
(formula-spec-v2.md, `[steps.check]`), so the loop sits on the template step.

| Step | Who | What it does |
|---|---|---|
| `prepare` | the review pool (`<rig>/<binding>polecat-codex`, where reviews run today) | Reads the record and the PR, and stops the run with no result when the PR's head is no longer the run's head. Makes the run's workspace (below). |
| `review-loop` (template, checked) | the orchestrator | Holds one iteration per head the run judges. Its check is `gctk review passed <run>` (section 8). `max_attempts` is a formula var, 3 by default, the bound the pack's one check loop already uses (`mol-polecat-work`'s self-review). |
| `triage` (child) | the review pool | Judges the iteration's head: the change since the last head that passed, or since the run's first head when the run's own repair pushed this one, or else the whole PR (section 2). Its output names the checks the head needs and whether the change is material. |
| one lane per picked check | the review pool, or the check's own target | Bonded at runtime from triage's output, one `mol-pr-review-lane` per check. Each runs its check's method at the head in its own worktree and writes its verdict and findings as its output. |
| `rule-and-repair` (child) | the fix pool (`<rig>/<binding>polecat`, where fixes and validation passes run today) | Rules every finding and every ask the run can take, answers them in the head's comment, and makes the round's fixes as one push (section 6). |
| `record` | the review pool | Writes the result for the head and the target, closes the asks the run answered, and removes the workspace. |

The two pools are formula vars, `review_target` and `repair_target`, which the
landing order fills from the rig as `refinery-reconcile.sh` fills them today.

The lanes are picked at runtime. `[steps.on_complete]` is "a runtime for-each
fan-out over the step's structured output: when the step completes, a formula is
instantiated for each element of a collection in its output"
(formula-spec-v2.md), and a step that `needs` the source waits on the fan-out's
control. `triage` carries `on_complete = { for_each = "output.checks", bond =
"mol-pr-review-lane", vars = { check = "{item.check}", head = "{item.head}" } }`,
so `rule-and-repair` waits for every lane triage bonded and for nothing else. On
a child of a check step the fan-out is created again in each iteration
(`internal/dispatch/control.go`, and its test in `control_test.go`). No shipped
formula in either repository uses `on_complete` yet, so unit 3 starts with a
probe of exactly this shape in a scratch city (section 12). When the probe fails,
the fallback is one static lane child per pack check, each closing at once with
the verdict "not picked" when triage did not pick it, at the cost of a session
per check left out. Rig checks then run in one generic lane.

An exhausted check closes the template step with `gc.outcome=fail`, and the step
after it still runs, because "a `needs` edge is ordering-only"
(`internal/dispatch/drain.go`). `record` reads the loop's outcome itself, so an
exhausted loop never reads as a pass (section 7).

### Where it runs

A run's workspace is a directory of its own, named for the run's root, under
the review workspace root `review-workspace.sh` keeps today
(`<dir>/gc-review-<root>`, with `<dir>` the `REVIEW_WORKSPACE_DIR`, else
`$TMPDIR`). Each lane takes a detached worktree at its head inside it, so lanes
that build, test or capture never share a tree, and the repair takes the run's
one worktree on the PR's branch. `record` removes the directory once the run has
ruled every finding, so a demo capture stays readable until its finding is
ruled. The work's own worktree is not a candidate: it belongs to the pool slot
that built the work, whose reaper removes it once that slot moves on, and a run's
steps are claimed by other slots.

`orders/review-workspace-reap.toml` stays, as the backstop for a run that ends
without its `record` step, such as a cancelled run. Its script keys the reap on
the run's root instead of a review bead: it removes the directory of a run whose
root is closed, or which names no live bead and has been idle as long as today.

### What it records

The run's one write on the bead that owns the PR is its result, in
`review_results`, the JSON array of `{head, target, passed}` the evaluator reads
(`services/gctk/pr/ready_keys.go`). `record` writes it through
`gctk review record <run>`, which replaces the entry for the run's last judged
head and target, or adds one, under the store's record lock. `passed` is true
when the loop's check passed at that head and no gate the run filed is open. It
is false when the loop exhausted, or when the loop stopped on a question the run
put to a person (section 6).
The review domain owns the key from then on. `ready_keys.go` reads it through
the face the review domain exports, as it reads the record through the record
package.

The run writes no other key on that bead. What it judged at each head is in its
own steps' outputs, which Gas City keeps on the root's beads.

### Asks: work on the PR's branch

An ask is a request for a change on a PR's branch, or for a check at its next
head. It is an open bead that blocks the bead that owns the PR, names the PR's
branch in `branch`, and carries no route and no assignee, so no pool claims it
and the review run is the one that works it. It may name the checks it sends back
in `review_checks`, a comma list from the check index. `gctk review ask <bead>
--reason <text> [--check <name>]...` files one. The asks of the new path are:

- the refinery's conflict with the target, on a bead that owns an open PR
  (`refinery-requeue.sh`, in place of the rework child it files today);
- a person's comments, a failing required check and a conflict that
  `pr-facts.sh` routes on a PR on the record, until tk-1tfzr71.21 replaces it
  (section 6);
- a ruling a sitting makes that sends a PR back (`converse-rework.sh`), with the
  checks the ruling names;
- a must-fix point a sitting or the mechanik puts on another open PR
  (tk-bet1nt), filed with the command the `prs` skill gives.

The run takes every open ask it can take at each iteration, rules it with the
findings, and closes it once a head it judged carries the fix, or answers why
not. The landing order pours a run for such an ask even when the head already
passed, so a comment on a passed PR becomes a round. An ask is a task bead that
holds the PR's bead by its own `blocks` edge, the shape the merge design gives
work on a PR's branch, so no new bead kind comes with it. tk-1tfzr71.21's join
can file Gas City's PR monitor repair beads in the same shape, unrouted, so the
monitor's repair work joins the same queue rather than starting a writer of its
own.

An ask can also wait on other work through an edge of its own, as a sitting's
send-back that must wait on another bead does (tk-724u4pw). The run can take an
ask only when nothing holds it, which `gctk bead holds <ask>` reads as `clear`
([the bead holds contract](../../docs/gctk-architecture.md#the-bead-holds-contract)).
A `waits-for` edge reads `unjudged`, which a caller that acts treats as a hold.
`gctk review ask` files an ask with no parent, because an ask filed under the
bead it blocks would read `held` through that bead for as long as it stays
open. The order's pour and its ready transition, triage, the run's selection and
the pass rule all read an ask by that one test (sections 2, 5, 6 and 8). An ask
that waits therefore pours no run, is neither triaged nor taken, and fails no
iteration, so it spends no attempt and files no gate. It still holds the PR
through its own edge onto the bead, which the evaluator reads as a wait. Once
nothing holds it, the order's next pass pours a run that takes it, at a passed
head as at any other.

## 2. Triage at every head

The operator's requirement of 2026-10-23, recorded on tk-1tfzr71.22: "every
change to an open PR runs triage again, and triage decides whether the change
needs more checks", and the ruling the same day: "triage makes the per-change
decision after each push, reading the change itself. A ruling made before the
fix exists, from the findings alone, does not count as that decision. Small
fixes still need no recheck."

In the run, triage judges each head the run reaches, the run's first head and
each head its own repair pushes. It reads:

- **The change.** At a head with a passed result behind it on the branch, the
  change is `git diff <last passed head>..<head>`, two commits of one branch, so
  no rewrite of the target moves it. At a head the run's own repair pushed with no
  passed head behind it, as in a PR's first round, the change is the repair,
  `git diff <the run's first head>..<head>`, read with the rulings it answers, so
  a small fix needs no recheck there either. A merge commit in either range is
  read with `git show --remerge-diff`, which shows exactly the hunks resolved by
  hand, and the merge commit's message, where the worker writes what collided and
  what it decided (merge design, section 7). Otherwise, as at a PR's first judged
  head, the change is the whole PR.
- **The asks** open on the bead that the run can take (section 1), and the
  checks each sends back.
- **The check index** at the head, through `gctk review checks --at <head>`.

It writes, as its output, the head, the checks the head needs and whether the
change is material. The picks are closed over the index, as today. At a PR's
first judged head the rig's first checks are picked whatever the diff, which is
`correctness` today (the `check_set` default the refinery stamps on the old
path). The checks of an ask the run can take are picked whatever the change. A
head whose change needs no further check, such as a small fix or a merge of the
target that git made without help, picks none, and the head passes on the checks
earlier heads ran and the rulings that answered them.

`skills/review-triage/SKILL.md` says triage "never re-runs because the branch
grew". On the new path it runs at every head by the ruling above. Section 3 says
what changes in the skill.

**The phases** in `review-checks.toml` order the checks by the stage transition
by which each must read green (`pre-open < open-as-draft < ready-for-review <
merge`). Every PR on the new path opens as a draft, so `pre-open` has no moment
of its own. The run judges every check triage picks before it records a result,
and the landing order marks the PR ready only on a passed result, so every check
runs before the ready transition. No check uses `ready-for-review` or `merge`,
in the pack's index or in the two overlays the rigs' checkouts carried on
2026-11-14. The phase field has no reader on the new path, and it goes with the old path's retirement, along with
the board's pre-open stall reading (tk-7rquf68).

## 3. The methods kept, and where their verdicts go

The five check skills keep how they hunt and what blocks. What changes is where
each says its verdict goes, because the old path records a verdict through one
`signoff.sh` call and the run records it as the lane's output. Both paths run
side by side until the last rig moves, so each skill names the formula it runs
under rather than either mechanism:

| Skill | What changes | What stays byte-identical |
|---|---|---|
| `review-correctness` | The sentences that name `signoff.sh` (its refusal and its flags, lines 396 and 411-414 at f21639824) say the verdict goes where the formula you run says, and that `--needs-you` is the verdict's flag on either path. | Everything else: the angles, the subagents, the proof of each blocking finding, What blocks, the findings file. |
| `review-arch` | The two sentences that name `signoff.sh` (lines 138 and 172). | The lens, the checks, What blocks. |
| `review-pm` | The one sentence that names `signoff.sh` (line 164). | The rest. |
| `review-demo` | The sentences that name `signoff.sh` and its `--visual` flags (lines 231-232, 372 and 379-388) say the verdict carries its visual on either path. | The modalities, the capture, What blocks. |
| `review-triage` | What it reads and when it runs (section 2): it judges one change, the formula names the change and its base, and the account of a merge resolved by hand is read from the formula's print (the audit's render on the old path, the merge commits on the new). What it rules gains the material ruling at any head (section 4). The verdict section names the formula, and "never re-runs because the branch grew" goes. | How it reads the index, the closed set of checks, the rule that adding nothing is the common case, and the rule that it files no findings. |

The review-coverage epic (tk-qjdt90g) owns the correctness method, and none of
these rows changes it. A new skill, `review-ruling`, holds the bar the
`rule-and-repair` step applies (section 6), since the step's text stays within
`formula-step-size.test.sh`'s bound of 9,000 bytes and a rule read once per round
belongs in a skill.

## 4. The approval withdrawal

The merge design gives triage the approval decision: "If the steps believe
enough has changed, they are supposed to dismiss my review so it is no longer
there and otherwise, that review holds" (the operator, conversation tk-k3g9xbi,
quoted in its section 3). Today the lift is the conflicted round's ruling, which
`bring-current-guard.sh` carries out, and a validator ruling that a fresh review
is due, which `approval-withdraw.sh` carries out.

In the run, triage rules a head material by the rule the triage skill states for
a lift today, now applied at any head: the change made a call that is yours to
make, by changing what the PR does, inferring one side's intent, or choosing
between two live designs. A change that only alters how the approved behavior is
achieved is not material. When triage rules a head material, it files the
withdrawal before the run can record a result there:

```bash
gctk pr withdraw <bead> --head <head> --reason "<the call, what it means for the PR, and where to look>"
```

The withdrawal is a bead that blocks the bead that owns the PR and names the head
in `withdraw_head`, so the evaluator holds the PR from the moment it is filed,
whatever else the run records. The landing order carries it out, because that is
where the intake routes feedback once tk-1tfzr71.21 lands, and until then it runs
after `pr-facts.sh` has routed. On each pass, for each open withdrawal on a record
it checks:

1. When an approval it would dismiss carries comments the intake has not routed,
   it waits for the next pass, as `approval-withdraw.sh` does today, because a
   dismissal retires them unread (the lesson of tk-uos4onx).
2. It dismisses each approval that stands and was given on a commit that does
   not contain the withdrawal's head, with the reason as the message and the
   city's mark, through `gctk pr post`. A review's own `commit_id` is the commit
   it approved, and that commit contains the head when it is the head or
   descends from it, which GitHub's compare of the two
   (`compare/<withdraw_head>...<commit_id>`) reads as `identical` or `ahead`.
   The order already reads the reviews through gctk's `gh` adapter, so the
   compare is one more read of the same kind. An approval of the head, or of
   any later head of the branch, saw the change and stands, because every push
   onto a PR's branch on the new path is a fast-forward (merge design, section
   1), so every later head contains it. That covers a person who approves the
   repair's next head before the order carries out the withdrawal for the head
   before it, and a retry, which reads the reviews again and reaches no
   approval of a head that carries the change, so the withdrawal keeps no
   record of the set it dismissed. On a branch a person rewrote through the
   withdrawal's head, an approval of a rewritten head does not contain it and
   is dismissed, which errs on the safe side. No time is compared, and a
   compare GitHub does not answer leaves the withdrawal for the next pass.
3. It reads the reviews again, and closes the withdrawal only once no approval
   that stands was given on a commit that does not contain its head.
4. When GitHub refuses a dismissal, it files a human gate on the bead, keyed
   `approval-withdraw-refused`, naming the reviews. The gate holds the PR until a
   person dismisses them or rules otherwise.

It reads the city's login through `pr-post.sh acting-login`, which prints a
login only on gh's exit 0 and in a login's shape (the note of 2026-11-03).

`approval-withdraw.sh`, `bring-current-guard.sh` and `bring-current-audit.sh`
retire into this. The audit's account of a conflicted merge moves into the merge
commit's message, which triage reads with the remerge diff. The guard's hold on a
hand-off goes, because nothing needs to force a conflicted round in front of
triage once triage reads every head. The guard's lift line,
`bring_current_lifted_at`, goes with the old path, since the evaluator reads no
approval's age. On the old path the three scripts keep working until the old
path retires.

## 5. The draft cycle

**A round** is the city's work on a PR's branch between two ready transitions.
It begins at the city's first push onto the branch after the PR was last marked
ready, or at the PR's opening as a draft. It ends when the landing order marks
the PR ready again.

Each transition reads GitHub's draft flag first and changes it only when it
differs, so a retry, a restart or a person's own toggle leaves the cycle to
finish from where the PR stands.

- **Back to draft.** Every city writer onto an open PR's branch on the new path
  runs `gctk pr draft <bead>` before it pushes: the run's repair, and the
  refinery's `mr` step when it pushes a new head onto a PR the bead owns. The
  first push of a round finds the PR ready and converts it, and the later pushes
  find it a draft and change nothing. A return to draft dismisses no approval.
- **Ready.** The landing order marks a PR ready when the PR is a draft, its
  record is pending at the live head, a passed result names that head and the
  target, no run is attached to the bead and no ask the run can take is open on
  it, so that the order has no run to pour for the PR. That is also how a draft
  that someone else returned to draft is readied again once its lanes have
  passed. The order does not wait for CI. An ask that something holds does not
  keep the PR a draft, since it starts no round until a run takes it.

This departs from the merge design's wording, "the review loop marks it ready".
The run cannot tell whether the head it passed is the round's last: the refinery
validates a head only after the run lets go of the bead, and when the target has
moved it merges the target in, which is a new head the loop must still judge. A
run that marked its own head ready would start CI on a head the refinery then
replaces, so the order makes the transition once the record names the head the
run passed.

A draft is no hold. A human gate on the bead, an open ask, or `merge_hold` still
holds the PR after the order marks it ready, because the evaluator reads them as
it always does.

## 6. Rulings, and whose rule each follows

The `rule-and-repair` step rules every finding a lane raised at the iteration's
head and every ask open on the bead that the run can take (section 1), by the
rule its source carries, which `review-ruling` states:

- **A lane's finding** is ruled by that lane's own rule for what blocks, the
  What blocks section of its skill, with that lane's evidence in its worktree,
  which stays on disk until `record` removes the run's workspace. A blocking
  finding is fixed, unless the lane's own rule shows it does not hold, and then it
  is declined with that reason. A finding the lane raised and the run does not act
  on is answered where the PR shows that lane's verdict (tk-n4uafu5).
- **Each finding is answered by its own fix.** The step's output records, for each
  finding it ruled must-fix, the commit that fixes it. No finding is tied to
  another lane's fix, because there is no fix unit to share (tk-8tht7qk,
  tk-95xeo8v).
- **Siblings.** For each must-fix finding the step names the other sites in the
  change that share its cause, and fixes them in the same round. That is the gap
  four rounds on another rig's PRs showed, where a fix asked for the cited site
  and the next review raised its sibling (the distiller's case of 2026-10-30).
- **A person's comment** is graded on the scale the correctness method gives a
  reviewer's finding, and the method's rule for each grade applies: what it says
  blocks is fixed, what it says to fix only when low-risk and net-positive is
  fixed or declined on those terms, and a nit is answered and not fixed. The
  operator, conversation tk-bap2vqv: "We shoudl grade the fidnings here to figure
  out if it's nit picking issues or items that truly should have been caught". A
  fix that reaches outside the reviewed diff goes to a bead of its own, armed to
  start once the PR lands (call 2).
- **A ruling the operator made** in a sitting, carried by its ask, is applied, not
  graded again.
- **A question only a person can answer** goes to a human gate on the bead,
  which the operator's workflow names as the third end of a comment. The question
  counts as ruled, so the loop stops rather than spend attempts on it, and the run
  records no passed result at that head while the gate is open. The order pours no
  run while the gate holds the bead (section 1). Once a person answers, the next
  pass pours one, and that run reads the gate's close reason with the asks.

The step answers every finding and ask in one comment for the head, posted
through `gctk pr post` and found again by its mark, which names the run and the
head, so a retry edits the comment rather than posting a second. Each lane's
verdict sits in it with that lane's findings and how each was ruled. A demo lane
still delivers its capture to the PR as today.

No ruling of convergence exists. The run passes a head only on the facts at that
head (section 8), so a fix pushed after a pass is a new head with no result,
which the landing order gives a run of its own (tk-2w1w33v, PRs #1305 and #1481).

**A person's comment until tk-1tfzr71.21.** On a PR on the record,
`pr-facts.sh`'s feedback arm keeps routing a batch as today: each comment becomes
a human finding, the record tk-1tfzr71.21 decides the form of, and the batch's
fix unit is filed as an ask instead of a rework child, through `gctk review ask`.
It opens no validation pass. The run rules each human finding of the batch with
`finding.sh set-disposition`, unchanged, and its `record` step runs
`finding.sh close-answered`, unchanged, so each finding closes once its ask has
closed and `pr-facts.sh`'s write-back answers the comment as it does today. The
failing-check and conflict arms file their rework child as an ask the same way.
`finding.sh` is not changed, and its row moves to the bead that retires the old
path, which waits on tk-1tfzr71.21 (section 11). A comment that arrives after a
pass starts a round of its own, since the landing order pours a run for an open
ask that nothing holds.

**A must-fix point on another open PR** (tk-bet1nt, folded here by the operator's
placement ruling of 2026-10-30). The operator's seed: "Ideally, it has a way to
add a blocking bead that'll get processed just like any comment on the PR, code
review feedback, etc." A sitting or the mechanik files an ask on the PR's bead
with `gctk review ask`, from the command the `prs` skill gives. It holds the PR
from that moment, and the first run that can take it (section 1) rules it like a
person's comment, unless it carries the operator's own ruling.

## 7. A run that ends without a result

Wedged reviews held PRs #1317 and #1319, both approved, for four to five days,
and #1414 and #1430 for a day, until a person repaired each (the notes of
2026-10-30 and 2026-11-08). In each, a run ended without a verdict and nothing
re-offered it.

- **Inside a run,** Gas City does the re-offering. A step whose session dies goes
  back to its pool. A check that cannot read the store exits 75, which re-runs it
  without spending an attempt, up to 20 times (`maxCheckInfraRetries` in
  `internal/dispatch/ralph.go`).
- **A loop that exhausts its attempts** has failed to converge round after round,
  so `record` writes `passed: false` for the run's last judged head and files a
  human gate on the bead, keyed `review-loop-exhausted`, naming the head, the
  findings still open and the run. That is the one gate a run files about its
  own failure, and once a person clears it, the next pass pours a fresh run. A
  loop that a step's hard failure closed did not exhaust: Gas City ends it without
  running the check and records `gc.final_disposition = hard_fail`
  (formula-spec-v2.md, section 3.1, "A hard failure ends the loop"), and `record`
  writes no result and files no gate for it.
- **A run that ends without a result,** through a cancel, a hard failure or a
  decline, closes its root, and the `blocks` edge stops holding. The landing
  order's next pass finds no result at the head and no run attached, and pours
  another. When the last two runs attached to the bead at the live head both
  closed without a result, it files a human gate keyed `review-run-failed`
  instead, naming both runs and how each ended. It counts only runs that ended
  after the bead's last such gate closed, so a person who clears the gate gets one
  more run rather than the same gate again. The first failure is often
  transient, as when a gather's failure path cancelled a review's run together
  with its own session (tk-6qbps3w), and a second at the same head is a defect a
  person should see.
- **A run never ends as pass.** The result is written only by `record`, and
  `passed` is true only when the check passed at that head and no gate the run
  filed is open. A run's record is its own vars, which the order fills from the
  record it read under the lock. `prepare` refuses vars that do not name the bead's record, and stops the run
  with no result, so nothing pours a run with an empty record, the shape that
  wedged the arch reviews of PRs #1317 and #1319 (tk-11jxw8s).
- **An approval never stands in for a check.** The evaluator reads the review
  result and the approval as two conditions, and nothing reads an approval as a
  lane's green, so lane-state's GitHub-approval fallback has no successor. A
  check an ask sends back is picked at the first head judged once the run can
  take the ask, and that head does not pass until the check ran there and each
  of its findings was ruled.
- **The projection.** `prstatus` renders the evaluator's `review` condition with
  the state of the run, read from the bead's `blocks` edges onto run roots: a run
  attached reads as the city's work in flight, a closed run with no result at the
  head reads `needs-attention` as the machine's fault, naming the run, and the two
  gates above read the same way, by their keys. None reads as a person's hold or
  as a ruling owed.

## 8. gctk's review domain, and what is left of signoff.sh

The gctk domain move (design tk-ssm8qns.2, and
[gctk-architecture.md](../../docs/gctk-architecture.md#the-surface)) gives this
member the review domain. Its verbs:

| Verb | What it does | Callers |
|---|---|---|
| `gctk review checks [--at <oid>] [--resolve <set> \| --show \| --check <name>]` | The check index at a commit, with the rig's overlay laid over the pack's: the port of `review-checks.sh`'s verbs. Every caller moves in the same change and the shell goes, by the domain move's rule. | triage, the lanes, the old path's readers until it retires |
| `gctk review guidance <check> --at <oid>` | The rig's guidance for a check at the reviewed commit (`review-checks.sh --extension`). | each lane |
| `gctk review passed <run> [--explain]` | The loop's check script (below). `--explain` prints the iteration's lanes, verdicts, findings and rulings, which `rule-and-repair` reads before it rules, and which triage reads at a head the repair pushed. | the formula's check; triage; `rule-and-repair` |
| `gctk review record <run>` | Writes the result for the run's last judged head and target into `review_results` under the record lock, and closes the asks the run answered with `gc.work_outcome` and the commit. | `record` |
| `gctk review ask <bead> --reason <text> [--check <name>]...` | Files an ask (section 1). It refuses a bead that owns no PR on the record, and it finds an ask of the same source and reason, open or closed, before it files, so a re-run after the ask closed files nothing (the window PR #1480 left in `rework-child.sh`). | the refinery, `pr-facts.sh`, `converse-rework.sh`, the `prs` skill |
| `gctk pr draft <bead>` | Reads the PR's draft flag and converts it to draft only when it is ready (section 5). | the repair, the refinery's `mr` step |
| `gctk pr withdraw <bead> --head <oid> --reason <text>` | Files the withdrawal (section 4). The landing order carries it out. | triage |

**The pass rule.** `gctk review passed <run>` exits 0 when, in the iteration it
checks, triage wrote the head it judged, every lane triage bonded wrote its
verdict at that head, `rule-and-repair` ruled every finding and every ask it
took, ruled nothing must-fix and pushed nothing, and every ask open on the bead
that the run can take is one the step took. An ask that something holds counts
for nothing here, so it spends no attempt, and its own edge holds the PR until
nothing holds the ask and a later run takes it (section 1). Each finding the run
ruled must-fix at an earlier head must also name the commit that fixes it. A
finding declined by its lane's own rule counts as ruled, and so does a question
put to a person, so the loop stops there rather than spend its attempts on a
question only a person can settle, and `record` then writes no passed result
while that gate is open (section 1). It exits 1 otherwise, so the next
iteration triages the head the repair pushed. It exits 75 when the store does
not answer. It reads only the store, because a check runs inside the control
dispatcher with a `PATH` of the directories of bd, gc, dolt and jq plus the
system's (`conditionPATH` in `internal/convergence/condition.go`), which has no
`gh`. The steps' outputs carry the heads, so the check needs no GitHub read.

**What is left of signoff.sh.** Its verdict record becomes each lane's output
and the result `gctk review record` writes. Its post becomes the one comment per
head that `rule-and-repair` posts. Its widening of `check_set` becomes triage's
picks at each head. Its findings, its rework child and its validation pass have
no successor, because findings live in the run, the run repairs and the run rules.
Its call into `bring-current-guard.sh decide` becomes the withdrawal. The lanes'
synthesis stays judgment in `rule-and-repair`'s text and gets no verb. The script
itself keeps working for the old path, and the old path's retirement deletes it
(section 11). The dropped port, tk-tyopvq, is answered by the table above.

## 9. The readers

The description's census pattern, run on 2026-11-14 over the live files outside
tests, specs and generated files, also matches files whose only match is a name
that contains a term, such as `patrol-finding.sh` or `mol-validate-close`, which
are not this member's. `feedback-miner.sh` is one, since it names only
`patrol-finding.sh`. What the readers of the old path become:

| Reader | Today | On the new path | Built by |
|---|---|---|---|
| The evaluator (`services/gctk/pr`) | reads `review_results`, which nothing writes | reads the run's result; `ready_keys.go` reads the key through the review domain | unit 1 |
| `prstatus` and the status label | on the old path, `pr.machine` and the in-flight count of every bead naming the anchor | the evaluator's answer, with the run's state in the `review` condition (section 7); one in-flight set, the evaluator's waits | unit 4 |
| The board (`services/helm/internal/board`) | `checkLanes`, `laneGreen` (a copy of `lane-state.sh`), the pre-open stall and `prMachine` | renders `prstatus`; the lane readers serve the old path and go with it, and the board member (tk-1tfzr71.24) drops the dead clauses | unit 4; the retirement bead |
| `gctk merge` and `pr-open.sh` | lane green per lane, open must-fix findings, the verdict replay | old path only; they go with tk-1tfzr71.70 | tk-1tfzr71.70 |
| `pr-facts.sh` | files human findings, a validation pass and rework children; reads lane green | on a PR on the record its feedback, failing-check and conflict arms file asks and open no pass (section 6) | unit 4; tk-1tfzr71.21 replaces it |
| `refinery-requeue.sh` and `refinery-land.sh` | file a conflict's rework child; stamp `check_set` | on the new path a conflict on a bead with an open PR files an ask, and the `mr` push runs `gctk pr draft` first; the stamp stays for the old path | unit 2; unit 4 |
| `converse-rework.sh` and `converse-signoff.sh` | a ruling's rework child through `rework-child.sh`, then `review-outcome.sh supersede-anchor` | on a PR on the record, an ask carrying the ruling and the checks it names; nothing to supersede, because the run judges the next head itself | unit 4 |
| `converse-pr-conversation.sh` (tk-gwxsklm) | finds no PR on a review bead | no review bead exists on the new path; the old path's go with it | the retirement bead |
| `work-submit.sh`, `work-setup.sh`, `mol-polecat-work`'s workspace-setup | run the guard and the audit | the account of a merge resolved by hand also goes in the merge commit's message, on both paths; the guard and the audit calls go with the old path | unit 5; the retirement bead |
| `refinery-lib.sh` | tells a rework child by its source key | an ask carries no route and no assignee, and the refinery's find-work leaves it alone | unit 4 |
| `bead-rehome.sh`, `branch-end.sh`, `demo-deliver.sh` | refuse or skip review scaffolding | unchanged on the old path; nothing of the kind exists on the new | the retirement bead |
| The `prs` skill | `finding.sh answer`, `rework-child.sh` | an ask, for a send-back and for a point on another PR | unit 4 |
| The polecat prompt and doctrine | "a review bead carries `mol-review`", "closed by `signoff.sh` or `review-sweep.sh`" | the formula a claim carries decides it, so the run's steps need no sentence of their own; the review-bead sentences go with the old path | the retirement bead |
| `lifecycle/lifecycle.toml` and `key-registry.json` | the lane keys, finding keys, `pr.machine`, the bring-current keys | registers `review_checks` and `withdraw_head`, and gives `review_results` its writer; each old key goes in the change that removes its last writer (tk-1tfzr71.25's rule) | unit 1; unit 2; the retirement bead |
| The doctor | I6 (`check-gate-integrity`) and I7 (`check-gate-marker-provenance`) read `check_set` and the approve backings | old path only; they go with it | the retirement bead |
| `architecture.md` | `signoff.sh` writes verdicts on review beads that the merge cadence sends out, from the record `gate-ensure.sh` writes | the run's account is in this design's change, with the old path and its `--needs-you` rules under Debt; once the run is built, the Debt entry's clause that it is not built goes, and the entry goes with the old path | this design; unit 5; the retirement bead |
| The docs | `state-machine.md` (Checks, the machine axis, bringing a branch current), `component-model.md`, `authority-map.md`, `refinery-merge-cadence.md`, `review-workspace.md`, `review-demo.md`, `steering.md`, `warrants.md`, `built-once-target.md` | the new path's account, with the old path under Debt until it retires; built-once-target's Review section and the merge differences "The PR opens as a draft" and "One worker per branch" | unit 5 |

A reader the table does not name keeps working while the old path runs. The
retirement bead (section 11) runs the census pattern again and removes each
clause that names the old path along with the code it names.

A conversation that waits for its work's PR to be ready for approval
(tk-vrg93t0) waits for the landing order's ready transition, the moment the run
has passed at the head the refinery validated. tk-vrg93t0 builds the wake there:
the order marks ready each session wait that watches the PR's bead
(`gc wait ready`, `docs/reference/cli.md`) as it marks the PR ready. The loop
needs nothing more for it.

## 10. The problems held on this retirement

Each open bead that waits on the initiative (`gc bd dep list tk-1tfzr71.22
--direction=up`), less the members and cutovers, and each problem the notes fold
in under rule 1:

| Problem | The new path | Because |
|---|---|---|
| tk-11jxw8s: a review poured with an empty record | removes it | The order is the one pourer, from the record it read; `prepare` refuses vars that do not name the record; a run with no result never passes (section 7). |
| tk-2w1w33v, and PRs #1305 and #1481: a fix merged with no triage | removes it | No convergence is ruled. Every head the run pushes is triaged in the next iteration, and a push after a pass is a head with no result. |
| tk-a43j1j1: demo, pm and arch findings ruled without that lane's evidence | removes it | `rule-and-repair` rules each finding by its lane's What blocks, with the lane's worktree on disk until `record`. |
| tk-n4uafu5: a declined finding never answered | removes it | Each finding is answered in the head's comment beside its lane's verdict. |
| tk-8tht7qk, tk-95xeo8v, and the arch and pm cases on tk-ltcv43q and on another rig: a finding closed by another lane's fix | removes it | No fix unit exists to share; each must-fix finding records the commit that fixed it. |
| tk-v7qqux, tk-rmkr6l1, and the seat taken from another rig's validation pass: a fix before its ruling, a slot held while it waits | removes it | The step that rules is the step that fixes, and it closes after its push, so no repair waits on a check and none is ready beside the check that rules it. |
| The over-accepted operator feedback (#1482, #1483, #1484, #1481, and a PR on another rig) | removes it | A person's comment is graded on the correctness method's scale, and a fix outside the diff goes to a bead of its own (section 6). |
| The siblings the validator missed (four beads on another rig) | removes it | The ruling names every site in the change that shares a must-fix finding's cause. |
| The wedged reviews (#1317, #1319, #1414, #1430; tk-6qbps3w) | removes it | The order re-offers a run that ends without a result, and asks a person only at the second failure at one head (section 7). |
| tk-pdc0ovc: a lane reads the body before its refresh | removes it | The refinery edits the body before it pushes the head (merge design, section 8), and a run starts only after the record names that head. |
| tk-j5wrs and tk-8wg5eg9: the label and the board count different live work | removes it on the new path | Both render the evaluator, whose waits are the one in-flight set. Their close briefs hold once the old path retires. |
| tk-7rquf68: the board's pre-open stall counts every lane | removes it | The phases and the stall reading go with the old path; the new path's board renders `prstatus`. |
| tk-724u4pw: a sitting's rework cannot wait on another bead | removes it on the new path | An ask is filed, not slung, and it can carry its own `blocks` edge. While that edge holds it, the order pours no run for it and no run takes it or fails on it, and once the edge lands the order's next pass pours one (section 1). |
| tk-grjsnf6: a deferred follow-up on an integration PR pours from main | removes it | A deferral's bead takes the PR's target as its own `target`, so it starts from the branch the code lands on. |
| tk-6bovoni: the guard reads git's default merge base over a rewritten main | removes the guard's half | Triage reads the change between two commits of one branch. The edge moves to the retirement bead, which deletes the guard; the supersession half stays on tk-1tfzr71.21. |
| The re-filed ruling rework (PR #1480's window) | removes it | `gctk review ask` finds an ask of the same source and reason, open or closed, before it files. |
| tk-iy4cjst, tk-lz30h7x: a deferral or decline holds its thread on the reviewer | removes it | A deferred point is answered and its thread resolved, as the operator ruled for scheduled points ("resolve the comment if it's scheduled, that's more than sufficient", on tk-1tfzr71.21). |
| tk-z1wjjcn, tk-0dpxsl6, tk-qf1l1i2, tk-9qa0dae, tk-3p9bvai, tk-nvlo9e5 | removes each | No rework child, finding bead, validation pass or sweep exists on the new path; an ask is filed whole by one verb, and the run names no commit in an ask, since it judges its own heads. |
| The approval-withdraw login read (tk-a8nb8wo) | removes it | The withdrawal reads the login through `pr-post.sh acting-login`. |
| `gate-ensure.sh` swallowing unknown flags, `finding.sh` and `lane-state.sh` refusing `--help`, and `mol-validate`'s steps over the hook's cap | removes each | The verbs are gctk's, which refuse an unknown flag, and every step the run's formulas deliver is held to `formula-step-size.test.sh`'s bound. |
| A validation pass closed with no work outcome | removes it | `gctk review record` closes each ask with `gc.work_outcome`, and the run's root is Gas City's to close. |
| tk-e70808f: a sitting edits an open PR's branch | answers it | A sitting holds the bead through its conversation's gate while it edits, the order pours no run while a conversation's gate holds the bead, and the sitting's push runs `gctk pr draft` first and goes under the lease. When the sitting lets go, the head it left is validated and triaged like any other, so a small edit costs one triage. |
| tk-vrg93t0: wake a conversation when its PR is ready for approval | answers it | Section 9. |
| tk-1tfzr71.50: `bd-lib.sh`'s checked create | moves its edge | Its last callers (`gate-ensure.sh`, `finding.sh`, the validation-pass filing in `signoff.sh`) retire with the old path. |
| tk-69ncc80: `run-cancel.sh --bead` | moves its edge | `mol-validate` passes it, and the retirement bead deletes `mol-validate`. |
| tk-1tfzr71.71: the evaluator's `anchor_bead` reading | keeps its edges | The run, its asks and its withdrawals block the bead by their own edges. Until tk-1tfzr71.21 a person's unruled finding still holds through `anchor_bead`, so its edge onto that member stays. |
| tk-8gradm4.1: per-pass walks of every anchor | removes the review path's | Each run is poured per record by the order, which reads a bounded number of records per run, and `gate-ensure.sh` and the sweeps go with the old path. |

## 11. Shadow, cutover, and the old path's retirement

**The shadow comparison.** The description asks to run the new loop beside the
old lanes on a few PRs and compare verdicts. Before gc-toolkit's cutover, the
mechanik pours shadow runs on open gc-toolkit PRs that the old lanes are
reviewing:

```bash
gc sling <rig>/<binding>polecat-codex mol-pr-review --formula --var pr_bead=<bead> --var head=<head> --var target=<target> --var shadow=true --var max_attempts=1
```

A shadow run is attached to nothing, so it holds nothing, and with `shadow=true`
no step writes outside the run. Triage files no withdrawal, and a demo lane keeps
its capture in the run's workspace rather than delivering it. `rule-and-repair`
rules, and writes into its own output the comment it would post and the gates and
beads it would file, but it fixes, pushes, posts and files nothing. `record`
writes no result, closes no ask and files no gate. So it adds no writer, no post
and no hold on the PR. The mechanik compares, at the same head, each lane's verdict and each
finding's ruling with the old path's review beads and validation rulings, and
records the comparison on gc-toolkit's cutover bead. It stops once every check
has run in a shadow and every difference has a reason it can name. A difference it
cannot explain goes to the operator through a gate on the cutover bead before
step 2.

**Each rig's cutover** is the bead the merge effort filed (tk-1tfzr71.78, .80 to
.84), which waits on this member. This design adds to it:

- On gc-toolkit's, the shadow comparison before step 2.
- In step 3, for each bead that moves onto the record, `review-cutover.sh --bead
  <bead>` closes its open review beads, its open validation passes and its
  machine findings as superseded, because the first run judges the PR whole and
  the evaluator would otherwise hold the PR on each of them through
  `anchor_bead`. It leaves the bead's human findings, which the run rules, and an
  open rework child, which finishes as today: the refinery takes a handed-back
  rework child before its anchor, and the order pours no run while it works the
  branch.

**The old path finishes** once every rig's cutover bead has closed. A retirement
bead on the default branch, outside the effort, waits on every cutover bead and
on tk-1tfzr71.21, and is armed. Its drain check is that no open bead is a review
bead, a validation pass or a machine finding, and that no open run is poured on
`mol-review`, `mol-review-quorum-signoff` or `mol-validate`. It deletes the
member's 29 rows, among them `gate-ensure.sh`, `lane-state.sh`, `finding.sh`,
`mol-validate.toml`, `review-outcome.sh`, `approval-withdraw.sh`,
`review-sweep.sh`, `scaffolding-sweep.sh`, `rework-child.sh`,
`validate-dispatch-body.sh`, `bring-current-guard.sh`, `bring-current-audit.sh`
and the two doctor checks. It adds rows for `signoff.sh`, `mol-review.toml`,
`mol-review-quorum-signoff.toml`, the board's lane readers, the review phases and
the old keys. It waits on tk-1tfzr71.21 because `pr-facts.sh` files human
findings through `finding.sh` until that member replaces it.

## 12. The units

Each unit lands on `integration/tk-1tfzr71.22`, keeps the suite green and leaves
the city working. Until a rig cuts over, nothing on the new path runs there.

| Unit | What it does | Waits on | Releases |
|---|---|---|---|
| 1. The review domain | `gctk review checks` and `gctk review guidance`, the port of `review-checks.sh`, with every caller moved and the shell deleted; `gctk review passed` with its pass rule and `--explain`; `gctk review record`, which takes `review_results`'s declaration from `ready_keys.go`; `gctk review ask`, with the key `review_checks` registered. Tests for each case of the pass rule: a lane's finding ruled must-fix and one declined by its lane's rule, a question put to a person, a repair that pushed, a must-fix finding of an earlier head with no commit that fixes it, an untaken ask that nothing holds, which fails the check, and an ask an open bead holds, which neither fails it nor is taken, an ask's check not run at the head, a store that does not answer; for `record`, a result replaced at the same head and target, `passed: false` for an exhausted loop and while a gate the run filed is open, and no result for a loop a hard failure closed; an ask filed twice by one source and reason, open and closed, and an ask filed with no parent. | nothing | the formula (unit 3) |
| 2. The draft cycle and the withdrawal | `gctk pr draft`; `gctk pr withdraw` with `withdraw_head` registered; in the landing order's pass, the withdrawal carried out (waiting for routing, dismissing with the mark each approval on a commit that does not contain the withdrawal's head, reading back, a gate on refusal) and the ready transition; the refinery's `mr` push runs `gctk pr draft` first. Tests show section 10's draft-cycle items of the merge design: a round's first push returns a ready PR to draft and later pushes change nothing; the order readies a draft whose passed result names its validated head with no run attached, whoever drafted it, and not one whose record is not pending at that head; a cycle stopped between any two steps finishes from where the PR stands; a return to draft dismisses no approval, and a PR approved before a round merges on that approval after it unless triage ruled the round's head material; a gate or `merge_hold` still holds a PR the order readied; a withdrawal waits while an approval it would dismiss carries unrouted comments, holds the PR until no approval that stands was given on a commit without its head, and files its gate when GitHub refuses; a withdrawal for a head, carried out after a person approved a later head, keeps that approval, keeps an approval of the head itself, and still dismisses an approval of a commit that does not contain the head. | nothing | unit 4 |
| 3. The formula | First, a probe in a scratch city: `gc formula cook --attach` of a v2 formula whose template child carries `on_complete`, inside a `[template.check]` loop, with steps routed by `gc.run_target`, run over three iterations; its result picks `on_complete` or the static fallback (section 1). Then `mol-pr-review` and `mol-pr-review-lane`, each step calling a tested script within the step-size bound, which `formula-step-size.test.sh` learns to read in expansion templates and bonds; `review-workspace.sh` keyed by the run's root and the reap order with it; the shadow var; the skills' verdict sentences, triage's per-head method and material ruling, and the `review-ruling` skill (section 3). | unit 1 | unit 4 |
| 4. Admission and asks | The landing order's pass pours a run (no passed result at the validated head, or an open ask that nothing holds; none attached; no other writer, rework child or conversation's gate, on the branch; no human gate on the bead), re-offers a run that ended without a result, and files `review-run-failed` at the second failure at one head since that gate last closed. Its ready transition waits while an ask that nothing holds is open. The asks: the refinery's conflict path, `pr-facts.sh`'s three arms on a PR on the record, `converse-rework.sh` on such a PR, and the `prs` skill's command. `prstatus` renders the run's state; `refinery-lib.sh` leaves an ask alone. Tests: a head validated with no result gets one run and only one under overlapping passes; a run that ended without a result is poured again, and the second failure gets the gate; a cleared `review-run-failed` or `review-loop-exhausted` gate gets one more run; an open human gate on the bead keeps the order from pouring until it closes; an ask on a passed head starts a round; an ask an open bead holds, on a passed head, pours no run, files no gate and leaves the head's passed result, and the pass after that bead closes pours one run, which takes it; a draft with an open ask that nothing holds is not marked ready; a sitting's open gate keeps the run off the branch; a person's batch is ruled by grade, a nit answered and not fixed, a fix outside the diff deferred to a bead with the PR's target. | units 2 and 3 | unit 5 |
| 5. Docs, warrants, the plan and the cutover script | The pages in section 9's last row, and what its `architecture.md` row leaves; the account of a hand-resolved merge in the merge commit's message, in `mol-polecat-work`'s workspace-setup; the warrants' Covers lines; `review-cutover.sh` for the cutover beads; the deletion plan's rows moved to the retirement bead, with a note on it saying why; `built-once-target.md`'s Review section and the lane table. | units 1 to 4 | the landing |

**Rule 2.** Every step of the two formulas calls tested scripts or gctk verbs and
holds no shell procedure, and `tools/lint-step-text.sh` and
`formula-step-size.test.sh` hold them to it.

## 13. Edges and notes the implementation child adds

- The units are filed under the epic (tk-1tfzr71) with
  `target=integration/tk-1tfzr71.22` in each create. The landing bead
  (tk-1tfzr71.22) and the summary task (tk-1tfzr71.110) wait on every unit through
  a `blocks` edge. Each unit waits on the units its row names and is armed.
- The retirement bead is filed on the default branch, outside the effort,
  blocked by every rig's cutover bead and by tk-1tfzr71.21, and armed. Neither
  the landing bead nor the summary task waits on it.
- Each cutover bead (tk-1tfzr71.78, .80 to .84) gets a note naming what section
  11 adds to its steps, and gc-toolkit's names the shadow comparison.
- The held problems' edges move as section 10 says: tk-6bovoni's, tk-1tfzr71.50's
  and tk-69ncc80's onto the retirement bead, each with a note naming why. Each of
  the others keeps its edge onto the initiative, and its validating closer checks
  its close brief once the initiative lands. tk-j5wrs's and tk-8wg5eg9's briefs
  hold once the old path retires, so their edges move onto the retirement bead
  too.
- tk-1tfzr71.21 gets a note: the ask is the form its join files the PR monitor's
  repair beads in, and the run's ruling of a person's finding moves onto whatever
  form it gives that finding.
- tk-e70808f and tk-vrg93t0 get a note pointing at the section that answers each.
- Before filing, the child surveys the open branches against each unit's files
  again. At this reading, PR #1497 (tk-sll4qin) edits `review-checks.toml`, the
  demo skill and `docs/review-demo.md`, beside units 1, 3 and 5, and PR #1480
  (tk-pb9wnr3) edits `converse-signoff.sh`, `prstatus`, `lifecycle.toml` and
  `docs/state-machine.md`, beside units 4 and 5. The units that touch those files
  bring them in once they land.

## 14. Facts this design rests on

Gas City, at 13bb101b8f:

- `[steps.check]`: exit 0 passes, exit 75 or a timeout re-runs the check without
  spending an attempt, any other exit spends one, and exhaustion closes the step
  failed (formula-spec-v2.md, the check exit-code table; `internal/dispatch/control.go`).
  A `needs` edge is ordering-only, so the step after an exhausted loop still runs
  (`internal/dispatch/drain.go`). `check` combines with neither `expand` nor
  `on_complete` (formula-spec-v2.md; `internal/formula/types.go`).
- The multi-lane loop on a template's check: understanding-formulas.md, "Multi-Lane
  Review Loops", and `gascity/formulas/build-basic-review.formula.toml` in
  gascity-packs at 0f07496d2f.
- `[steps.on_complete]` fans out at runtime over a step's output, bonding an
  expansion formula per item (formula-spec-v2.md; `internal/dispatch/fanout.go`;
  `internal/formula/fragment.go`). No shipped formula in either repository uses it.
- `condition` and `count` loops are fixed when the formula compiles
  (formula-spec-v2.md), so they cannot pick lanes from triage's output.
- `gc formula cook --attach` on a v2 formula: the attached bead blocks on the
  root, the root names no source bead, the bead becomes a one-item input convoy,
  and each step routes by its own `gc.run_target` (`cmd/gc/cmd_formula.go`,
  `internal/graphv2/invocation.go`, `internal/graphroute/graphroute.go`). A city
  that binds the graph class to its own storage refuses it in a rig's store
  (`docs/reference/cli.md`).
- A check script runs in the control dispatcher with a `PATH` that has no `gh`
  (`internal/convergence/condition.go`).
- Order triggers are cooldown, cron, condition, event, manual and webhook; an
  event trigger matches the event type only, and no event reports a metadata
  change (`internal/orders/order.go`, `internal/events/events.go`).
- The PR monitor reads no review, treats a draft as not actionable and files a
  repair bead only for actionable PRs, one per PR head
  (`internal/githubmonitor/monitor.go`, `cmd/gc/cmd_github.go`).
- Nothing in Gas City or gascity-packs dismisses a GitHub review or moves an open
  PR between draft and ready (searched both, 2026-11-14).

The pack, at f21639824:

- The evaluator counts only a result that passed for the PR's live head and
  target (`passedAt` in `services/gctk/pr/pr.go`), and reads a draft as a
  condition not met.
- Reviews run on `<rig>/<binding>polecat-codex` and fixes and validation passes on
  `<rig>/<binding>polecat` (`refinery-reconcile.sh`).
- A review's workspace is `<dir>/gc-review-<review bead>` with a detached
  worktree, removed by its last step and reaped hourly otherwise
  (`review-workspace.sh`, `orders/review-workspace-reap.toml`).
- `review-checks.toml` declares correctness, triage, arch and pm at `pre-open`,
  and demo at `open-as-draft`.
- `mol-polecat-work`'s self-review is the pack's one check loop:
  `max_attempts = 3`, `self-review-check.sh`, which reads records rather than
  running checks because it runs in the control dispatcher.
