---
name: review-correctness
description: Use when you hold a review bead whose check is correctness, or when asked whether a change is correct and safe to merge.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# The correctness check

The correctness check is the standing review of whether a change is correct
and safe as merged. It is the concern, not a tool: no reviewer is presumed.

## What it reads

The whole diff at `<reviewed_oid>`, in `<worktree>`:
`git diff origin/<review_base>...HEAD`. A large diff gets read in chunks, not
sampled. The review formula printed the rest. The anchor `<anchor_bead>` says
what the change was asked to do. The PR as published is what the What to check
list's last dimensions read. What `gctk rig` recorded at `<reviewed_oid>` is
the test evidence, below. The rig's guidance for this check is
`docs/review-correctness.md` at the reviewed commit, printed when the commit
carries one.

## What it judges

### Settle the test evidence

Every run of the rig's tests through `gctk rig`, whether by a self-review, the
refinery or an earlier review, is recorded against the commit it ran at, and
every worktree of the rig's clone reads the records. The review formula printed
a line for each check `gctk rig` records at `<reviewed_oid>`, and the gctk
binary it read them with. That binary is the gate, and a suite you run through
the gate calls it by that path. The `test` line is the test evidence:

- A pass of the whole suite (scope `full`) or of the subset the commit's diff
  selects (scope `affected`) is evidence. Run no suite.
- A fail the line calls pre-existing fails on the base too, and the trackers it
  names carry the failure. It goes in the verdict as context, with its
  trackers, and is not run again.
- Any other fail is the commit's. Run the record's command again through the
  gate, `gctk rig test --scope <its scope> --command '<its command>' --force`,
  to see what failed, and check whether it fails on the base too.
- Nothing recorded, a pass that ran nothing (scope `none`, a rig that declares
  no test command), or a record gctk could not read is no evidence. Run the
  suites the diff touches in `<worktree>` through the gate, so that run is
  recorded as well, `gctk rig test --scope affected --command '<the suites>'`,
  and record the real pass and fail counts. With no gctk binary there is no
  gate, so run them plain. A suite is one the diff touches when the diff
  changes it or a file it reads or runs. When the diff touches none, as when it
  changes only a document that no suite reads, there is nothing to run. Run
  nothing, and the Verification line says so, with how you found that no suite
  touches the diff.

Either way you may run one targeted suite for a gap you suspect, and the run of
each new case against the pre-change code that the Testing dimension asks for
is yours. Run those plain, each as `bash -c '<suite>'`, because a gate call
with another command replaces the reviewed commit's record. Every suite runs
under the claim-lease keepalive the review formula names. A failing suite is
not automatically a finding: check whether it fails on the base too. A
pre-existing failure belongs in the verdict as context, not as this branch's
defect.

### What to check

Work the whole list on every round. A P0 or a P1 is not a stopping point: a
blocking finding discovered a round later costs another rework and another
full review, so one verdict enumerates every blocking finding this diff
carries, not the first one that appears.

- **Intent** — does it do what the anchor bead asked? Deviations are fine
  when they are better; flag them either way.

The hunting angles come next. Each reads the whole diff from its own
direction, and a defect one direction passes over can be in plain view from
another. So work every angle, even after another has raised a finding at the
same place. A defect two angles find is one finding, raised under the angle
that names its cause.

- **Line by line** — read every changed line inside the whole function, block
  or section that encloses it, not the hunk alone. Bugs in the unchanged lines
  of a touched function are in scope, because a change's defect often sits in
  a line it left alone: one that now receives a new input, runs under a new
  condition or in a new order, or reads a value the change redefined. At each
  line, ask what input or state makes it wrong: a condition that tests the
  wrong thing or misses a case, a boundary handled on one side only, a value
  used before it is checked, two writers that race, a limit or a cache that
  never resets, an error swallowed or reported as success, outside input taken
  unchecked, the failure mode nobody wrote a test for. A defect in an
  unchanged line is this diff's when the change brought it about, and one the
  line already had is real but not this diff's.
- **Removed behavior** — for every line the diff deletes or replaces, name
  the invariant it held: the check it made, the case it refused or answered,
  the error it reported, the guarantee its callers relied on. Then find where
  the new code re-establishes that invariant, on every path the old line
  covered. A replacement that drops a refusal, narrows a check, loses an error
  path, answers a batch differently from its items one at a time, or ports a
  function without one of its cases is a finding, unless the change says why
  the behavior goes and nothing still relies on it.
- **Cross-file trace** — follow everything the change touches into the files
  around it, to its callers and its callees. Does it break a caller, a stored
  format, a metadata key, or a script that greps for the old shape? Find the
  other call sites of anything it changed; the recurring defect class is a
  predicate fixed in one copy and left stale in two. Read each callee the
  change now relies on, for what it does with the input the change now passes
  it. A fact the change works out from a shape, such as a path, a name or a
  format, when another component records it, is a finding, and the fix reads
  that record. Search the same way for what it adds: a rule the diff writes
  where existing code already defines it, or one edit repeated across copies
  of a code path, is a finding until one definition serves every site, and a
  follow-up to fold the copies later does not answer it. Where the surface has
  no include mechanism, that definition is a marker-fenced block a test holds
  every copy to.
- **Language pitfalls** — hunt the defects each language and framework in the
  diff is known for, file by file: how it splits, quotes and expands, how it
  treats a missing or null value, what it converts silently, what it does by
  default on an error. A failed read taken as an empty or clean answer is one
  in every language. Where the rig's guidance for this check names the
  pitfalls this repository has met, and which of them its gates catch, hunt
  those first, and hardest where no gate reaches.
- **Wrappers and delegates** — where the change adds or edits a wrapper, a
  proxy, an adapter, or any code that hands its work to another, check the
  hand-off in both directions. Each argument, flag, input and environment
  value a caller passes must reach the delegate as the caller meant it, and
  each result, exit status, error and signal the delegate returns must reach
  the caller. A default the wrapper adds, a timeout or a retry it imposes, or
  an output it filters is checked against every caller that goes through it,
  including any that called the delegate directly before. A wrapper that
  swallows its delegate's failure, or reports success when the delegate never
  ran, is a finding. A diff in which nothing wraps or delegates leaves this
  angle nothing to read.
- **Scope claims** — check each sentence in the diff in which the change sums
  up its own scope, footprint or coverage against what the change builds: a
  design's headline, a line saying it adds no X or that only Y changes, a
  safeguard, compliance or coverage statement. A claim broader than what the
  change builds, or smaller than what it changes, is a finding. The honest
  form is the narrow sentence that is literally true, followed by the list of
  what it leaves out.
- **Testing** — do the tests exercise real behavior, is the new path
  covered, does a regression pin the bug that was fixed? A new case pins its
  change only if it fails when the change is reverted, so the correctness
  check runs each new case against the pre-change code, and confirms that a
  failure-path case's stub can produce the failure it names.
- **Readiness** — back-compat and migration, fail-closed where fail-closed
  was intended, docs the change just made false.
- **Comments** — a comment carries the code's non-obvious why. Narration of
  the change, the bead, or the design doc belongs in the commit message
  instead. Prose duplicated across files, or restating a comment a few lines
  up, is a finding. So is a fact narrated at a site that only consumes it:
  state it once, where it is defined. When a comment is long, ask whether the
  code is complex or the comment is making a simple thing look complex. A
  comment that explains a real why earns its place, so this is not a case for
  stripping comments. Tests and fixtures matter less here than the code they
  exercise. A docs/ page is held to the same rule: a section that restates a
  component's usage, commands, flags, environment or tests from its header,
  skill or formula is duplicated prose, so a component's page carries its
  rationale and the invariants other components rely on. A page with nothing
  else left is not warranted.
- **The PR as published** — the `## Summary` is the human-facing
  merge-decision surface, so it must holistically and currently account for
  the ENTIRE branch diff you just read, not one contributor's share of it. A
  summary that does not state what the whole diff does is a finding — a
  placeholder, a restatement of the dispatch, and an account of other work
  each qualify. So is a title whose type or words misname what the diff does,
  by the skill `gc-toolkit.subject-lines`. The title becomes the
  squash commit's subject, so a false one blocks as a false summary does, and
  one that is true but merely weak is a P2. `chore` is false on a diff another
  type describes, and a type the diff could fairly take is the author's call
  even where you would pick another. Judge what the title says, not its form.
  Where the summary and the title live depends on the state. Post-open, read
  the page the review formula printed from `<review_pr_url>`. Pre-open there
  is no page, but `pr-open.sh` will publish the anchor's `pr_summary` verbatim
  as `## Summary` once the check goes green, falling back to the dispatch
  description and then a placeholder when it is absent. Read that pending
  summary among the anchor's metadata, which the review formula printed, and
  hold it to the same standard. An absent or empty pre-open summary ships the
  dispatch description in its place — what the work was asked to do, not what
  the diff did — so it is a finding unless that text already accounts for the
  whole diff; its locus is `anchor <id> / pr_summary`. The pending title is
  the anchor's title, and `pr-open.sh` gives one that opens with no type a
  type from the bead's kind, so a task's title reads `chore: <its title>`; its
  locus is `anchor <id> / title`. When the published body looks wrong, read
  `pr-open.sh`, among the pack's scripts the review formula printed, for the
  shape this pack's opener emits, and `pr-stack.sh` beside it for the
  delimited beads-on-this-branch section the cadence keeps current below it. A
  section naming more than the anchor means the branch carries work from more
  than one bead, and your verdict covers every one of them. Pre-open, your
  verdict becomes the PR's opening comment.
- **Work-quality standards** — hold the diff's output (code, comments,
  docs) to the "Standards for what you produce" entries of the work-quality
  fragments, which this skill carries in its `references/` directory as
  `references/work-quality-*.template.md`: the shared base, which holds the
  universal standards, and one fragment per role class. Read every one. A
  violation is a blocking (request-changes) finding. The operator profile is
  not read here: its entries govern how a role addresses the operator at
  runtime, which is a property of an agent and not of a diff. Read the
  exemplar corpus, `references/learning-exemplars.template.md`, in the same
  pass: it carries the lessons that are a shape rather than a statement, and
  no prompt carries it.

### What each finding carries

A finding is a defect you can show happening, so each one names its failure
scenario: the concrete input or state that triggers it, then the wrong output,
the crash or the wrong record that follows on the tree as merged. Name it for
every candidate whose trigger you can name, including one you are not sure is
reached, rather than drop a half-believed one; a blocking finding's
verification says how sure you are. A concern with no trigger you can name is
not a finding.

Prose is text that a person or an agent reads and acts on, such as a document,
a spec, a prompt, a skill or a comment. A finding on prose has a reader where
code has an input, so its failure scenario names the text, the reader who acts
on it, and the wrong action or false belief that follows on the tree as merged.

Each P0 and P1 also carries its verification, one line that opens with
CONFIRMED or PLAUSIBLE, the result its check returned (below), and then the
evidence behind that result.

Each finding names its category: the dimension of What to check that found
it, spelled as the list spells it, or `Fresh-eyes sweep` for a defect the
sweep below found. A defect a hunting angle found names that angle. Each
finding also names its severity, the grade below.

### The fresh-eyes sweep

When the hunt is done and its candidates are deduped, one fresh pass looks
only for defects that no candidate names yet. It aims at what a first pass
misses:

- **Moved code that dropped a guard** — a block the diff moves, extracts into
  a helper, inlines or reorders, whose new copy lacks a check, an early exit,
  an error path, a lock or a cleanup the old copy had, or runs before the
  state it relies on is set. A move reads as code that did not change, so pair
  each block the diff deletes with the place it reappears, and read the two
  copies side by side.
- **Setup and teardown asymmetry in tests** — a test or fixture that creates,
  changes or stubs something and does not undo it on every exit, the failing
  ones included: a file, a directory, an environment value, the working
  directory, a process, a global. A teardown that undoes what its setup never
  made, or that is registered only after a step that can fail first, is the
  same defect from the other end. Either leaves a later test passing or
  failing by the order the suite runs in, or leaves state behind on the
  machine that ran it.
- **Config defaults that flipped** — a default the change alters: a flag's, a
  setting's, a parameter's, or what an unset environment value or an absent
  key means. Every caller, configuration and deployment that relied on the old
  default without naming it changes with it. A key renamed without reading its
  old name sends every configuration that set it to the default.
- **Second-tier footguns** — a hazard off the path the change was written
  for, on the next path out: a second run, a retry, a resume after an
  interrupt, the error path of an error path, an empty or unexpected input, a
  caller the change did not have in mind. An interface the diff calls in a way
  that is easy to get wrong, or adds in a shape that invites the wrong call, is
  one too.

Where your provider offers subagents, hand the sweep to a finder of its own
(below). Where it offers none, sweep yourself in a separate pass: read the
diff again from its first file rather than recall it, with only these targets
in mind. Either way the sweep is given the candidates so far, each as its
locus and failure scenario, so that it spends its reading on what they leave
out.

Judge each candidate the sweep returns against the diff, and drop one that
repeats a candidate already raised. Each one it adds carries every field a
finding carries (above), and each P0 and P1 among them is verified with the
rest (below). The trail records the sweep on a `Swept:` line (The verdict,
below).

### Verify each blocking candidate

Before the verdict, check each candidate P0 and P1 in a context that did not
raise it. Where your provider offers subagents, hand each one to a verifier
(below). Where it offers none, check each one yourself in a separate pass once
the hunt and the sweep are done: take the candidates one at a time, start from
a candidate's locus and failure scenario alone, and read the code along its
trigger's path again rather than recall it. Either way the question is whether
the trigger reaches the failure on the tree as merged, not whether the
argument that raised the candidate holds, so look first for the line that
would rule it out.

On prose, the tree the text describes answers that question. Read each claim
against the files it is about at the reviewed commit, trace each instruction
one step at a time as it is written, and walk a behavior the text commits to
through the case the candidate names. A line that makes the text true refutes
the candidate. A line that contradicts it, a step that does the wrong thing, or
a case the behavior fails confirms it.

The check returns one of these results:

- **CONFIRMED** — the evidence shows the trigger reaching the failure: a run,
  the line that does it, the caller that passes the input.
- **PLAUSIBLE** — the trigger is realistic and nothing rules the failure out,
  but the evidence that the trigger reaches it could not be had. This is the
  usual result for a race or a rare path.
- **REFUTED** — the candidate is wrong, and the check quotes the line that
  proves it: the guard that stops the trigger, the caller that never passes
  the input, the line that already does what the candidate says is missing,
  or the line of a run's output that shows the failure does not follow. A
  refutation that quotes no line, or quotes one that does not say what the
  refutation claims, is not one, and the candidate stands as PLAUSIBLE.

A CONFIRMED or PLAUSIBLE candidate stands, and its verification is that result
and its evidence. When the evidence shows a failure other than the one the
candidate named, write the failure it shows as the scenario, and grade the
candidate again on it. A REFUTED candidate is dropped: it is not a finding, it
does not block, and `findings.json` does not carry it. Read its quoted line
where it sits before you drop it. Its refutation stays in the trail, on a
`Refuted:` line of its own (The verdict, below).

### Finders and verifiers

Where your provider offers subagents, you may hand an angle to a finder, you
hand the sweep to a finder of its own, and you hand each blocking candidate to
a verifier. Use a finder for an angle where it adds unbiased feedback, or
where it costs fewer tokens in all than doing that reading yourself. Where
your provider offers none, you do this reading yourself.

- **A finder** hunts with one angle and returns every candidate whose trigger
  it can name, each with its locus and failure scenario, including one it is
  not sure is reached. Its feedback is unbiased by your reading, because it
  starts without the anchor's account of what the change was meant to do and
  without the path your earlier angles took through the diff, so it reads
  what the code does. It saves tokens when its angle reads files you would
  not otherwise open, such as the callers a cross-file trace follows. A file
  you read stays in your context for the rest of the review, and from a
  finder only its candidates come back.
- **A verifier** checks one blocking candidate: whether its trigger reaches
  its failure on the tree as merged. Its feedback is unbiased by the finding,
  because it never saw the reasoning that raised the candidate, so it has no
  stake in the answer. It returns the check's result, with the evidence or the
  quoted line behind it.

Give a finder or a verifier the diff and the files its angle or candidate
runs through, never your whole context, and start it with none of your
conversation. Some providers copy your conversation into a subagent unless
told not to, so tell yours not to. A finder gets its angle as What to
check states it, and the rig's guidance for this check when the angle reads
it. The sweep's finder gets the sweep's targets in place of an angle, and the
candidates so far. A verifier gets the candidate's locus and failure scenario,
without the argument for it. Apart from the candidates so far the sweep's
finder gets, neither gets the anchor, the PR, another candidate or a
conclusion of yours. A subagent reads again whatever it needs that you already
hold, so a finder whose angle reads only files you have read saves no tokens
and earns its place by its fresh reading alone.

A subagent works under the review formula's rules for subagents, so a run it
needs comes back to you as the run to make, and you make it. Its brief states
those rules, because a subagent can hold every tool you hold. What it returns
is a candidate or evidence: you judge each candidate against the diff, and
every finding, its fields and the verdict are yours to write.

## What blocks

P0 — broken or unsafe as merged: data loss, a merge that bypasses a check, a
crash on the normal path. P1 — a real defect that will bite: wrong behavior on
a reachable input, a fail-open where fail-closed was intended. P2 — worth
fixing, not worth blocking: a narrow hazard, a test gap, a clarity problem.
Grade honestly: a P2 inflated to P1 costs a whole rework round; a P1
discounted to P2 merges the bug. Read the grade off the failure scenario: a
reachable trigger whose wrong output is a durable wrong record, or a fail-open
where fail-closed was intended, is P1 however rare the trigger. When you can't
tell whether something is reachable, say what you checked and grade on what
you know.

On prose, a finding blocks when its failure scenario is one of these:

- A claim about the tree that the tree as merged contradicts.
- An instruction that does the wrong thing when it is followed as written.
- A behavior the text commits to that fails on a reachable case.

Read its grade off the wrong action or belief, as you read code's off the
wrong output, so an instruction that loses data when it is followed as written
is P0. A failure that depends on how work the text leaves open is later built
does not block, because the text leaves that choice to the work that builds
it. It is a P2 at most, or a note in the trail for that work.

P0 and P1 are the blocking findings. The verdict is request-changes when the
diff carries at least one, each with its required fix. The PR then goes back
for a rework round anyway, so its P2s go back with it: each is filed beside the
blocking findings, and the validator rules it must-fix when its fix is low-risk
and net-positive and declines it when it is risky or marginal. The verdict is
approve when the diff carries no P0 or P1, and its P2s are recorded on the
verdict and neither filed nor fixed.

## The verdict

`findings.json` carries every finding, P0, P1 and P2, each as one object with
its `locus` and `message` and the fields of its contract: its `severity`, its
`category`, its `failure_scenario`, and on a P0 or P1 its `verification`.

```json
{"locus": "<file>:<symbol or section>", "message": "<what is wrong, why it matters, and the fix>",
 "severity": "P1", "category": "<the dimension of What to check that found it, or Fresh-eyes sweep>",
 "failure_scenario": "<the input or state, then the wrong output>",
 "verification": "CONFIRMED: <the evidence>"}
```

`signoff.sh` refuses, with nothing written, a set that lacks one of these
fields, an entry whose verification is REFUTED, an approve that carries a P0 or
P1, and a request-changes that carries neither. It renders the set as the
posted verdict's Findings block, the most severe first and counted per grade,
as in `1 P1, 2 P2`. After `Filed:`, the trail carries a `Swept:` line that
says how the sweep ran and what it added, then a `Refuted:` line for each
candidate its check refuted, and it ends with the line that records the test
evidence the review relied on:

```
Swept: <by a subagent, or in a separate pass>: <the locus of each candidate it added, or "none">
Refuted: <locus>: <its failure scenario>. <file>:<line> reads `<the quoted line>`, so <why the failure cannot follow>
Verification: <test evidence relied on; each suite run at the reviewed commit, N passed, M failed; or that no suite touches the diff, and how you found it>
```

The check passes no `signoff.sh` flag of its own. An approve of a change that
edits `review-checks.toml` or a `docs/review-*.md` carries the formula's
`--needs-you`, saying what the edit changes about the review that ran under
it, and `signoff.sh` refuses one without it.
