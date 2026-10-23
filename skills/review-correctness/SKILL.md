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
sampled. The anchor `<anchor_bead>`, for what the change was asked to do, and
the PR as published, which the What to check list's last dimensions read. The
test evidence recorded at `<reviewed_oid>`, below. The rig's guidance for this
check, `docs/review-correctness.md` at the reviewed commit, which the review
formula printed when the commit carries one.

## What it judges

### Settle the test evidence

Every run of the rig's tests through `gctk rig`, whether by a self-review, the
refinery or an earlier review, is recorded against the commit it ran at, and
every worktree of the rig's clone reads the records. `gctk rig test --check`
reads the record at the reviewed commit and runs nothing. A test fail the
refinery judged pre-existing carries a mark on the anchor holding the record it
judged, which answers only while that record stands:

```bash
# >>> review-test-evidence
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
REC=""; RC=127
if [ -x "${GCTK:-}" ]; then REC=$(cd "<worktree>" && "$GCTK" rig test --check 2>/dev/null); RC=$?; fi
SCOPE=$(printf '%s' "$REC" | jq -r '.scope // empty' 2>/dev/null)
PRE=""
[ "$RC" = 1 ] && PRE=$(gc bd show "<anchor_bead>" --json 2>/dev/null | jq -r --arg c "<reviewed_oid>" --arg rec "$REC" '($rec | fromjson? // null) as $r | .[0].metadata["rig_check_pre_existing.test"] // empty | (if type == "string" then (fromjson? // empty) else . end) | select(type == "object" and .commit == $c and $r != null and .record == $r) | (.trackers // []) | join(", ")' 2>/dev/null)
if [ ! -x "${GCTK:-}" ]; then
  echo "no test evidence at <reviewed_oid>: no gctk binary at '${GCTK:-}' (GCTK_BIN, else the city's build, which its gctk-build order publishes); run the suites the diff touches plain, each under the keepalive"
elif [ "$RC" = 0 ] && { [ "$SCOPE" = full ] || [ "$SCOPE" = affected ]; }; then
  echo "test evidence: the rig's tests passed at <reviewed_oid> (scope $SCOPE); run no suite"
elif [ "$RC" = 1 ] && [ -n "$PRE" ]; then
  echo "test evidence: the tests fail at <reviewed_oid> as they do on the base, tracked by $PRE; do not run them again"
elif [ "$RC" = 1 ]; then
  echo "recorded fail at <reviewed_oid> ($(printf '%s' "$REC" | jq -r '"scope \(.scope // "none"), exit \(.exit_code), command: \(.command)"' 2>/dev/null)); run it again with --force to see what failed"
else
  echo "no test evidence at <reviewed_oid> (gctk rig test --check exit ${RC}${SCOPE:+, scope $SCOPE}); run the suites the diff touches through the gate"
fi
# <<< review-test-evidence
```

With evidence, run no suite. A pass recorded for the subset the commit's diff
selects (scope `affected`) counts as one for the whole suite. A fail marked
pre-existing goes in the verdict as context, with its trackers. A recorded
fail with no mark holding its record is the commit's: run the record's command
again through the gate, `"$GCTK" rig test --scope <its scope> --command
'<its command>' --force` with `GCTK` set as the block sets it, to see what
failed, and check whether it fails on the base too.
Without a record, or with a pass that ran nothing (scope `none`, a rig that
declares no test command), run the suites the diff touches in `<worktree>`
through the gate, so that run is recorded as well:
`"$GCTK" rig test --scope affected --command '<the suites>'`, and record the
real pass and fail counts. Either way you may run one targeted suite for a gap
you suspect, and the run of each new case against the pre-change code that the
Testing dimension asks for is yours. Run those plain, each as
`bash -c '<suite>'`, because a gate call with another command replaces the
reviewed commit's record. Every suite runs under the claim-lease keepalive the
review formula names. A failing suite is not automatically a finding: check
whether it fails on the base too. A pre-existing failure belongs in the verdict
as context, not as this branch's defect.

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
  formula printed from `<review_pr_url>`, or read it again with
  `gh pr view <review_pr_url> --json title,body`, which resolves the URL's own
  repository, never a bare number against ambient gh context. Pre-open there is
  no page, but `pr-open.sh` will publish the anchor's `metadata.pr_summary`
  verbatim as `## Summary` once the check goes green, falling back to the
  dispatch description and then a placeholder when it is absent
  (`assets/scripts/pr-open.sh`); read that pending summary and hold it to the
  same standard —
  `gc bd show <anchor_bead> --json | jq -r '.[0].metadata.pr_summary // empty'`.
  An absent or empty pre-open summary ships the dispatch description in its
  place — what the work was asked to do, not what the diff did — so it is a
  finding unless that text already accounts for the whole diff; its locus is
  `anchor <id> / pr_summary`. When the published body looks wrong, read
  `assets/scripts/pr-open.sh` for the shape this pack's opener emits, and
  `assets/scripts/pr-stack.sh` for the delimited beads-on-this-branch section
  the cadence keeps current below it. A section naming more than the anchor
  means the branch carries work from more than one bead, and your verdict
  covers every one of them. Pre-open, your verdict becomes the PR's opening
  comment.
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
