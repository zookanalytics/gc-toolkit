---
name: review-correctness
description: Use when you hold a review bead whose check is correctness, or when asked whether a change is correct and safe to merge.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# The correctness check

The correctness check is the standing review of whether a change is correct
and safe as merged. It is the concern, not a tool: no reviewer is presumed.
Approve a change that is correct and safe, even when it could be better, and
block one only for a defect that is worth another round of work.

## What it reads

The review formula you run under names the commit under review and the
worktree that holds it, and prints what the review reads:

- The change, which is the whole diff against its target. A large diff gets
  read in chunks, not sampled.
- What the change was asked to do, in the anchor bead where the formula prints
  one, and in the PR as published.
- The test evidence, which is what `gctk rig` recorded at the reviewed commit.
- The rig's guidance for this check, `docs/review-correctness.md` at the
  reviewed commit, when the commit carries one. It adds to this method and
  never replaces it.

## What it judges

### Settle the test evidence

Every run of the rig's tests through `gctk rig` is recorded against the commit
it ran at. The review formula printed a line for each check recorded at the
reviewed commit, and the gctk binary it read them with. That binary is the
gate. The `test` line is the test evidence:

- A pass of the whole suite (scope `full`) or of the subset the commit's diff
  selects (scope `affected`) is evidence. Run no suite.
- A fail the line calls pre-existing fails on the base too. It goes in the
  verdict as context, with the trackers the line names, and is not run again.
- Any other fail is the commit's. Run the record's command again through the
  gate, `gctk rig test --scope <its scope> --command '<its command>' --force`,
  to see what failed.
- Nothing recorded, a pass that ran nothing (scope `none`), or a record gctk
  could not read is no evidence. Run the suites the diff touches through the
  gate, `gctk rig test --scope affected --command '<the suites>'`, so that run
  is recorded as well, or plain when there is no gctk binary. A suite is one
  the diff touches when the diff changes it or a file it reads or runs. When
  the diff touches none, there is nothing to run. Run nothing, and the
  Verification line says so, with how you found that no suite touches the
  diff.

You may also run one targeted suite for a gap you suspect, and each new case
against the pre-change code, as Testing asks. Run those plain, each as
`bash -c '<suite>'`, because a gate call with another command replaces the
reviewed commit's record. A suite that fails on the base too is context in the
verdict, not this change's defect.

### What to check

Work the whole list on every round, and every angle even after another has
raised a finding at the same place. A blocking finding discovered a round
later costs another rework and another full review, so one verdict enumerates
every blocking finding this diff carries. A defect two angles find is one
finding, raised under the angle that names its cause.

- **Intent** — does it do what it was asked to do? Deviations are fine when
  they are better; flag them either way.
- **Complexity** — is it more complex than its job needs? Code that exists
  only to handle a failure a simpler design would rule out, or one that will
  rarely or never happen, is a finding. So are generality nobody asked for and
  machinery beside something that already does the job.
- **Line by line** — read every changed line inside the whole function, block
  or section that encloses it, not the hunk alone, and ask what input or state
  makes it wrong: a condition that tests the wrong thing, a boundary handled
  on one side only, a value used before it is checked, two writers that race,
  an error swallowed or reported as success. A defect in an unchanged line is
  this diff's when the change brought it about, and one the line already had
  is real but not this diff's.
- **Removed behavior** — for every line the diff deletes or replaces, name
  the invariant it held: the check it made, the case it refused, the error it
  reported. Then find where the new code re-establishes that invariant, on
  every path the old line covered. An invariant that is gone is a finding,
  unless the change says why it goes and nothing still relies on it.
- **Cross-file trace** — follow what the change touches to its callers and
  its callees, and find the other sites of anything it changed. Does it break
  a caller, a stored format, or anything that reads the old shape? A rule the
  diff writes where existing code already defines it, or one edit repeated
  across copies of a code path, is a finding until one definition serves every
  site. So is a fact the change works out from a path, a name or a format when
  another component records it.
- **Language pitfalls** — hunt the defects each language and framework in the
  diff is known for: how it splits, quotes and expands, how it treats a
  missing value, what it converts silently, what it does by default on an
  error. A failed read taken as an empty or clean answer is one in every
  language. Hunt first the pitfalls the rig's guidance names, and hardest
  where it says no gate reaches.
- **Wrappers and delegates** — where code hands its work to other code, check
  the hand-off both ways: what the caller passes reaches the delegate as the
  caller meant it, and every result, exit status and error comes back. A
  wrapper that swallows its delegate's failure, or reports success when the
  delegate never ran, is a finding.
- **Scope claims** — check each sentence in which the change sums up its own
  scope, footprint or coverage against what the change builds. A claim broader
  than what the change builds, or smaller than what it changes, is a finding.
- **Testing** — do the tests exercise real behavior, is the new path
  covered, does a regression pin the bug that was fixed? A new case pins its
  change only if it fails when the change is reverted, so run each new case
  against the pre-change code, and confirm that a failure-path case's stub can
  produce the failure it names.
- **Readiness** — back-compat and migration, fail-closed where fail-closed
  was intended, docs the change just made false.
- **Comments** — a comment carries the code's non-obvious why. Narration of
  the change belongs in the commit message, and a fact is stated once, where
  it is defined, so prose that repeats another file or a nearby comment is a
  finding, in a docs page as in a comment. When a comment is long, ask whether
  the code is complex or the comment is making a simple thing look complex.
- **The PR as published** — the PR's summary is where the merge is decided, so
  it accounts for the whole diff you read, and its title names what the diff
  does, by the skill `gc-toolkit.commit-conventions`. A summary that does not
  state what the whole diff does is a finding, and so is a title that misnames
  it. A false one blocks, and one that is true but merely weak is a P2. Where
  no PR page exists yet, read the summary and the title the review formula
  printed from the anchor, and a finding on either takes
  `anchor <id> / PR summary` or `anchor <id> / title` as its locus.
- **Work-quality standards** — hold the diff's output (code, comments,
  docs) to the "Standards for what you produce" entries of the work-quality
  fragments, which this skill carries in its `references/` directory as
  `references/work-quality-*.template.md`: the shared base and one fragment
  per role class. Read every one. A violation is a blocking finding. Read the
  exemplar corpus, `references/learning-exemplars.template.md`, in the same
  pass.

### What each finding carries

A finding is a defect you can show happening and that its author would fix on
seeing it. Each one names its failure scenario: the concrete input or state
that triggers it, how that trigger comes about, and the wrong output, crash or
wrong record that follows on the tree as merged. Name it for every candidate
whose trigger you can name, including one you are not sure is reached: a
blocking finding's verification says how sure you are. A concern with no
trigger you can name is not a finding.

Prose is text that a person or an agent reads and acts on, such as a document,
a prompt, a skill or a comment. A finding on prose has a reader where code has
an input, so its failure scenario names the text, the reader who acts on it,
and the wrong action or false belief that follows.

Each finding's message says what is wrong, why it matters and the fix, which
is the simplest change that removes the cause. A design in which the failure
cannot happen is a better fix than code that detects the failure and recovers
from it. When no such design is in reach, and the failure is rare and a later
run or a person can put it right, say so and ask for no code.

Each finding names its category: the dimension of What to check that found it,
spelled as the list spells it, or `Fresh-eyes sweep` for a defect the sweep
below found.

### The fresh-eyes sweep

When the hunt is done and its candidates are deduped, one fresh pass looks
only for defects that no candidate names yet. It aims at what a first pass
misses:

- **Moved code that dropped a guard** — a block the diff moves, extracts or
  reorders whose new copy lacks a check, an error path or a cleanup the old
  copy had. Read the two copies side by side.
- **Setup and teardown asymmetry in tests** — a test that creates, changes or
  stubs something and does not undo it on every exit, the failing ones
  included.
- **Config defaults that flipped** — a default the change alters, which every
  caller and configuration that relied on it without naming it now gets.
- **Second-tier footguns** — a hazard on the next path out from the one the
  change was written for: a second run, a retry, an empty or unexpected input,
  a caller the change did not have in mind.

Where your provider offers subagents, hand the sweep to a finder of its own
(below). Where it offers none, sweep yourself in a separate pass: read the
diff again from its first file rather than recall it. Either way the sweep is
given the candidates so far, so that it spends its reading on what they leave
out.

### Verify each blocking candidate

Before the verdict, check each candidate P0 and P1 in a context that did not
raise it: a verifier (below) where your provider offers subagents, and
otherwise a separate pass of your own once the hunt and the sweep are done.
Start from the candidate's locus and failure scenario alone, and read the code
along its trigger's path again rather than recall it. The question is whether
the trigger reaches the failure on the tree as merged, not whether the
argument that raised the candidate holds, so look first for the line that
would rule it out. On prose, read each claim against the files it is about,
and trace each instruction one step at a time as it is written.

The check returns one of these results:

- **CONFIRMED** — the evidence shows the trigger reaching the failure: a run,
  the line that does it, the caller that passes the input.
- **PLAUSIBLE** — the trigger is realistic and nothing rules the failure out,
  but the evidence that the trigger reaches it could not be had.
- **REFUTED** — the candidate is wrong, and the check quotes the line that
  proves it. A refutation that quotes no line, or quotes one that does not say
  what the refutation claims, is not one, and the candidate stands as
  PLAUSIBLE.

A CONFIRMED or PLAUSIBLE candidate stands. When the evidence shows a failure
other than the one the candidate named, write the failure it shows as the
scenario, and grade the candidate again on it. A REFUTED candidate is dropped:
it is not a finding, it does not block, and the findings you write do not
carry it. Its refutation stays in the trail (The verdict, below).

### Finders and verifiers

A finder is a subagent that hunts with one angle, or with the sweep's targets,
and returns every candidate whose trigger it can name, each with its locus and
failure scenario. A verifier is one that checks a single blocking candidate,
given as its locus and failure scenario without the argument for it, and
returns the check's result with its evidence. An angle may go to a finder
where it adds a fresh reading or reads files you would not otherwise open.

Give a subagent the diff and the files its angle or candidate runs through,
and none of your conversation, which some providers copy into a subagent
unless told not to. Apart from the candidates so far, which the sweep's finder
gets, a subagent gets neither the anchor, the PR, another candidate nor a
conclusion of yours. It works under the rules the formula you run under sets
for subagents, and its brief states them. What it returns is a candidate or
evidence: the findings and the verdict are yours to write.

## What blocks

Grade each finding on what its failure scenario states: what one occurrence
costs, and how likely its trigger is.

- **P0** — broken or unsafe as merged: data loss, a merge that bypasses a
  check, a crash on the normal path.
- **P1** — a real defect that will bite. Either the code will meet its trigger
  in ordinary use, as with wrong behavior on a reachable input or a fail-open
  where fail-closed was intended, or one occurrence is unsafe or cannot be
  undone, however rare its trigger: lost data, work landed past a check, a
  wrong record that nothing would show.
- **P2** — worth fixing, not worth blocking: a failure that needs an unlikely
  fault, such as a process stopped at one particular moment, and that a later
  run or a person can put right; a narrow hazard; a test gap; a clarity
  problem that no work-quality standard names.

Grade honestly: a P2 inflated to P1 costs a whole rework round; a P1
discounted to P2 merges the bug. When you can't tell whether something is
reachable, say what you checked and grade on what you know.

On prose, a finding blocks when its failure scenario is one of these:

- A claim about the tree that the tree as merged contradicts.
- An instruction that does the wrong thing when it is followed as written.
- A behavior the text commits to that fails on a reachable case.

Read its grade off the wrong action or belief, as you read code's off the
wrong output. A failure that depends on how work the text leaves open is later
built does not block, because the text leaves that choice to the work that
builds it. It is a P2 at most, or a note in the trail for that work.

P0 and P1 are the blocking findings. The verdict is request-changes when the
diff carries at least one, each with its required fix, and approve when it
carries none. A request-changes sends its P2s back beside the blocking
findings, and the round that rules them decides which are fixed. An approve
records its P2s on the verdict, and they are neither filed nor fixed.

## The verdict

The findings you write, `findings.json` or the output's `findings` as the
formula you run under names them, carry every finding, P0, P1 and P2, each as
one object with its `locus` and `message` and the fields of its contract: its
`severity`, its `category`, its `failure_scenario`, and on a P0 or P1 its
`verification`.

```json
{"locus": "<file>:<symbol or section>", "message": "<what is wrong, why it matters, and the fix>",
 "severity": "P1", "category": "<the dimension of What to check that found it, or Fresh-eyes sweep>",
 "failure_scenario": "<the input or state, how it comes about, then the wrong output>",
 "verification": "CONFIRMED: <the evidence>"}
```

The verdict goes where the formula you run under says, and its write refuses,
with nothing written, a set that lacks one of these fields, an entry whose
verification is REFUTED, an approve that carries a P0 or P1, and a
request-changes that carries neither. After `Filed:`, the trail carries a line
that says how the sweep ran and what it added, then a line for each candidate
its check refuted, and it ends with the line that records the test evidence
the review relied on:

```
Swept: <by a subagent, or in a separate pass>: <the locus of each candidate it added, or "none">
Refuted: <locus>: <its failure scenario>. <file>:<line> reads `<the quoted line>`, so <why the failure cannot follow>
Verification: <test evidence relied on; each suite run at the reviewed commit, N passed, M failed; or that no suite touches the diff, and how you found it>
```

The check adds nothing of its own to the verdict the formula records. An
approve of a change that edits `review-checks.toml` or a `docs/review-*.md`
carries the verdict's needs-you note, `--needs-you` or the output's
`needs_you` as the formula you run under names it, saying what the edit changes
about the review that ran under it, and the verdict's write refuses one without
it.
