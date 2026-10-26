---
name: review-correctness
description: The method for the correctness check, the standing review of whether a change is correct and safe as merged. Read the whole diff, settle its test evidence, hunt with the What to check list's named angles and work the rest of the list, give every finding its failure scenario and the angle or dimension that found it, grade it P0, P1 or P2, verify each blocking one, and add the Verification line to the verdict. Use when you hold a review bead whose check is correctness, or when asked whether a change is correct and safe to merge.
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
  gate, so run them plain.

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
  each qualify — and so is a title that understates the scope. Where the
  summary lives depends on the state. Post-open, read the page the review
  formula printed from `<review_pr_url>`. Pre-open there is no page, but
  `pr-open.sh` will publish the anchor's `pr_summary` verbatim as `## Summary`
  once the check goes green, falling back to the dispatch description and then
  a placeholder when it is absent. Read that pending summary among the anchor's
  metadata, which the review formula printed, and hold it to the same standard.
  An absent or empty pre-open summary ships the dispatch description in its
  place — what the work was asked to do, not what the diff did — so it is a
  finding unless that text already accounts for the whole diff; its locus is
  `anchor <id> / pr_summary`. When the published body looks wrong, read
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

Each P0 and P1 also carries its verification, one line that opens with
CONFIRMED or PLAUSIBLE. CONFIRMED names the evidence that the trigger reaches
the failure: a run, the line that does it, the caller that passes the input.
PLAUSIBLE says why the trigger is realistic when the evidence could not be had.

Each finding names its category, which is the dimension of What to check that
found it, spelled as the list spells it. A defect a hunting angle found names
that angle. Each finding also names its severity, the grade below.

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
 "severity": "P1", "category": "<the dimension of What to check that found it>",
 "failure_scenario": "<the input or state, then the wrong output>",
 "verification": "CONFIRMED: <the evidence>"}
```

`signoff.sh` refuses, with nothing written, a set that lacks one of these
fields, an approve that carries a P0 or P1, and a request-changes that carries
neither. It renders the set as the posted verdict's Findings block, the most
severe first and counted per grade, as in `1 P1, 2 P2`. The trail ends with the
line that records the test evidence the review relied on, after `Filed:`:

```
Verification: <test evidence relied on; each suite run at the reviewed commit, N passed, M failed>
```

The check passes no `signoff.sh` flag of its own. An approve of a change that
edits `review-checks.toml` or a `docs/review-*.md` carries the formula's
`--needs-you`, saying what the edit changes about the review that ran under
it, and `signoff.sh` refuses one without it.
