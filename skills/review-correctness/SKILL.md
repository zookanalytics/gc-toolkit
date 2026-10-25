---
name: review-correctness
description: The method for the correctness check, the standing review of whether a change is correct and safe as merged. Read the whole diff, settle its test evidence, work the What to check list, grade every finding P0, P1 or P2, and add the Verification line to the verdict. Use when you hold a review bead whose check is correctness, or when asked whether a change is correct and safe to merge.
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
- **Correctness** — bugs, reachable edge cases, error handling, the failure
  mode nobody wrote a test for.
- **Contract** — does it break a caller, a stored format, a metadata key, or
  a script that greps for the old shape? Find the other call sites of
  anything it changed; the recurring defect class is a predicate fixed in
  one copy and left stale in two. Search the same way for what it adds: a
  rule the diff writes where existing code already defines it, or one edit
  repeated across copies of a code path, is a finding until one definition
  serves every site, and a follow-up to fold the copies later does not
  answer it. Where the surface has no include mechanism, that definition is
  a marker-fenced block a test holds every copy to.
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

## What blocks

P0 — broken or unsafe as merged: data loss, a merge that bypasses a check, a
crash on the normal path. P1 — a real defect that will bite: wrong behavior on
a reachable input, a fail-open where fail-closed was intended. P2 — worth
fixing, not worth blocking: a narrow hazard, a test gap, a clarity problem.
Grade honestly: a P2 inflated to P1 costs a whole rework round; a P1
discounted to P2 merges the bug. When you can't tell whether something is
reachable, say what you checked and grade on what you know.

P0 and P1 are the blocking findings. The verdict is request-changes when the
diff carries at least one, each with its required fix, and approve when it
carries none, with every P2 riding along as a non-blocking note.

## The verdict

The envelope's Findings block lists every P0, P1 and P2, each with its grade,
location, impact and fix, and its summary counts them per grade, as in
`1 P1, 2 P2`. The trail ends with the line that records the test evidence,
after `Filed:`:

```
Verification: <test evidence relied on; each suite run at the reviewed commit, N passed, M failed>
```

Each P0 and P1 goes in `findings.json`; a P2 does not. The check passes no
`signoff.sh` flag of its own. An approve of a change that edits
`review-checks.toml` or a `docs/review-*.md` carries the formula's
`--needs-you`, saying what the edit changes about the review that ran under
it, and `signoff.sh` refuses one without it.
