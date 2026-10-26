---
name: Gas City search for the review evidence gather and the finding contract
description: The search the arch check asks for before the pack adds surface of its own. What Gas City, the packs it publishes and bd ship for a review reading what a rig's checks recorded at the commit it judges, for judging a recorded fail pre-existing, and for a review finding's grade, category, failure scenario and verification, read at named upstream commits, and why none of it covers what review-evidence.sh, rig-check-lib.sh, signoff.sh's check of a finding set, finding.sh's contract flags and P2 refusal, and the finding contract's keys do. Read it when checking whether the review path still needs that surface.
---

# Gas City search for the review evidence gather and the finding contract

This change adds pack surface for what a review is handed and for what its
findings carry. Every review's gather runs `review-evidence.sh`, which prints
what `gctk rig` recorded for a rig's checks at the commit the review reads, and
whether the anchor's pre-existing mark holds a recorded fail, judged by
`rig-check-lib.sh`'s one definition. And a reviewer's findings carry a
contract: a grade, a category, a failure scenario and, on a blocking finding, a
verification. `signoff.sh` checks a finding set against it before it writes
anything and renders the set on the verdict, `finding.sh upsert` stamps it on
the finding bead as new keys, and `finding.sh set-disposition` refuses to defer
a P2. So the arch check asks what Gas City already ships for each need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships the store the contract is kept in, and the change composes it.
The contract's keys are bd metadata, which bd names its extension point, and the
contract is written into the finding bead's description as well. The contract
also names its grade `severity`, the field the review lane object of Gas City's
`core` pack gives a finding, which the pack's quorum lanes already fill with the
grade the check's method gives. For the rest of the surface the search found
nothing that covers the need. Gas City reads GitHub's check results for open
pull requests, records them only on repair work for one that is failing, and
keeps no record of a rig's own checks at a commit. The packs it bundles judge a
failing check pre-existing in the run that meets it, track the failure as a
bug, and record nothing a later run at the same commit can read. The review
findings the bundled packs define carry no category or failure scenario.
`core`'s lane object lives in one run's step output, and no Gas City code
reads its findings. The build pack's verdict report ties its worst severity to
the review's outcome, but any finding makes it a `fail`, where under the P2 rule
the operator ruled a review whose findings are all P2 approves, and it is a file
among a build's artifacts, not a record the validator rules. Packs Gas City
publishes but does not bundle carry more of the contract, `gstack`'s security
review nearly all of it, but each in a format of its own skills that no Gas City
component reads. None of the surface is a pack noun: the finding bead is a kind
the pack already has, and its new fields are keys. So it takes no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2), and the
change touches no path or key that a warrant in
[warrants.md](../../docs/warrants.md) covers.

## The surface and the need

- `review-evidence.sh --anchor <bead> --commit <sha>` runs in a review's
  worktree, checked out at the commit the review reads. For each of test, lint
  and typecheck it reads the record `gctk rig` keeps at that commit with
  `gctk rig <check> --check`, which runs nothing, and prints one line: the
  result, scope, exit code and command, that nothing is recorded, or that the
  record could not be read. For a recorded fail it reads the anchor's
  `rig_check_pre_existing.<check>` mark and says whether the mark holds that
  very record and which trackers carry it. mol-review's `load-dispatch` step
  and the quorum's lanes and synthesis run it in their gather, so every
  check's review is handed the same lines.
- `rig-check-lib.sh` defines that judgment once, as a jq function the readers
  source. A mark answers only at the commit it names, for the record it was
  written against, and when it names a tracker. `self-review-check.sh` applies
  it to the work bead at HEAD, and `review-evidence.sh` to the anchor at the
  reviewed commit.
- The finding contract. In a reviewer's `findings.json`, every correctness
  finding, and any other finding a method grades, carries a `severity` of P0,
  P1 or P2, a `category` naming the part of the method that found it and a
  `failure_scenario`, and on a P0 or P1 a `verification` that opens CONFIRMED
  or PLAUSIBLE. `signoff.sh --findings-file` refuses, with nothing
  written, a set that lacks a field the contract requires, that carries a
  refuted candidate, or that disagrees with the verdict: an approve with a
  blocking finding, or a request-changes with none. It renders the set as the
  posted verdict's Findings block. `finding.sh upsert` takes them as
  `--severity`, `--category`, `--failure-scenario` and `--verification`, and at
  a finding's first raise stamps them as `finding.severity`, `finding.category`,
  `finding.failure_scenario` and `finding.verification`, and as lines of its
  description, outside `finding.key`. `finding.sh set-disposition` refuses to
  defer a finding whose `finding.severity` is P2. `lifecycle/lifecycle.toml`
  registers the keys.

What the gather needs is the result each check a rig declares recorded at the
exact commit a review reads, whichever run recorded it: a self-review, the
refinery, or an earlier review. The review reads it without running anything,
and before any pull request exists, since the pre-open gate reviews a branch
that has none. For a recorded fail it also needs a judgment, carried on the
anchor, that this very fail is pre-existing. What the contract needs is a grade
that decides whether a finding blocks the verdict, the failure scenario and
verification that support the grade, a refusal before a verdict is posted or a
bead filed when the set is incomplete, and a place on the finding bead, outside
its dedup key, where the validator reads the contract when it rules the finding
and a later round's re-raise finds the open finding again.

## Where the search looked

Each was read on 2026-10-26:

- Gas City at main `f78779e41522`: its documentation, its engineering docs, the
  `core` pack it bundles, and the source of its GitHub pull request monitor, of
  its formula runtime's step checks, retries and output requirements, of its
  review quorum contract, of `gc doctor` and `gc lint`, and of its bead metadata
  vocabulary.
- Every pack Gas City publishes, at `dac12a4a802c`, and the `gastown` and
  `gascity` packs at `66c672b5ed00`, the commit Gas City's `go.mod` pins and
  bundles them from
  ([Builtin Packs](https://docs.gascity.com/reference/system-packs)).
- bd at main `249d7cde74db`: its issue model, its labels, its metadata and its
  gates.

The search covered the results of tests, lint, typecheck, builds and CI, and
where they are kept (status checks, check runs, `gh pr checks`, test evidence);
failures judged pre-existing, known, flaky or present on the base; and a
finding's severity, grade or priority, category, failure scenario, verification
or confidence (CONFIRMED, PLAUSIBLE, REFUTED), where findings are stored, how a
set of them is checked, and how they are deduped. Each part the search found
was read.

## What Gas City ships near each need

### A check's result at a commit

Gas City keeps no record of a rig's checks at a commit. The nearest it ships
reads GitHub. A GitHub PR monitor queries the open pull requests of a
repository it is configured for, reads the status checks and check runs on each
one's head commit, and judges its readiness: clean, pending, failed,
conflicted, behind, blocked or draft
([GitHubPRMonitor](https://docs.gascity.com/reference/config#githubprmonitor);
package `githubmonitor`, `EvaluatePullRequests` and `classifyChecks`). For a
pull request whose readiness fails, `gc github pr backfill
--create-repair-beads` files or refreshes one repair bead per pull request and
head, with the head's sha and the names of its failed and pending checks in its
metadata, and routes it to the monitor's repair route
([gc github pr backfill](https://docs.gascity.com/reference/cli#gc-github-pr-backfill);
package `main`, `githubPRRepairMetadata`). That is a record of GitHub's checks,
written only for an open pull request that is failing, and it names the
failing checks without their commands. A review reads its evidence at a commit
it pins, and the pre-open review runs before any pull request exists. What
saves it a run is a recorded pass, which the monitor never writes.

bd's gates wait on GitHub too. A `gh:run` gate waits for one GitHub Actions
run, named by its run id, and `bd gate check` closes it when the run succeeds
and escalates it when the run fails or is canceled
([Gates](https://beads.gascity.com/workflows/gates),
[bd gate](https://beads.gascity.com/cli-reference/gate)). It holds a step until
one run finishes, and keeps no result a later reader can look up by commit.

A formula step can decide whether its own work passed. `[steps.check]` runs a
script after each iteration of the step closes, and a nonzero exit spawns the
next iteration while budget remains
([Check](https://docs.gascity.com/reference/specs/formula-spec-v2#3-1-check)).
The dispatcher also holds a retry attempt's pass to its postconditions: a
required output must be present and parse as JSON, and a required artifact must
exist in the run's worktree (package `dispatch`, `classifyRetryAttempt` and
`validateRequiredArtifacts`). Each answers for one run's step, and none is a
result of the rig's checks that another run at the same commit can read back.

Gas City's work record keeps the verification behind shipped work. When a
worker closes a bead it shipped, `core`'s `mol-do-work` stamps
`gc.work_verification` with the commands it ran, beside `gc.work_commit`.
Package `beadmeta` declares the key as "the verification record (gate result,
"manual", or a link) backing a shipped outcome" (`WorkVerificationMetadataKey`),
and no Gas City code reads it. It is one free-text value on the work bead,
written when the work closes. A review reads each check's result at the commit
it pins while the work is still open, which that record does not hold.

The bundled packs run a rig's checks themselves, or judge the proof a build's
own tasks recorded. `core`'s `mol-polecat-base` runs the typecheck, lint and
test commands a rig sets in its `formula_vars`, in its `preflight-tests` step,
before any work starts. `gastown`'s refinery runs the checks on the merged head,
and when one fails and it blames the branch, it writes the failure into the
work bead's `rejection_reason`, as free text, for the next worker
(`mol-refinery-patrol`). In the build pack, each task writes its first
verification command, its final proof command and the pass or fail it observed
into its implementation summary (`do-work`'s `implement` step). The review
loop, `build-basic-review`, gathers those summaries into one context file and
gives test evidence a lane of its own
([Multi-Lane Review Loops](https://docs.gascity.com/guides/understanding-formulas#multi-lane-review-loops)).
That lane checks that each task recorded its verification and proof commands,
judges whether those commands cover the acceptance criteria, and writes its
findings and an `approve` or `iterate` verdict
(`code_review.test_evidence_verdict`). At the packs' head, newer than the
bundled copy, the lane also runs the proof commands in the build's
implementation worktree. Its evidence is what the build's tasks wrote about
themselves, not a record of the rig's checks at a commit that any run can read.
Gas City's test-policy packages, such as `bepsummary`, which summarizes Bazel's
build event files, police Gas City's own Bazel test suite, not a city's rigs.

Among the packs Gas City publishes, the check results a pack reads from
outside itself are GitHub's, for an open pull request, read live. `gstack`'s
`land-and-deploy` skill reads and watches a pull request's checks before it
merges. `pr-pipeline`'s `mol-pr-from-issue` counts the status checks on the
pull request it opened. `pr-review`'s `mol-adopt-pr` and `mol-pr-merge-only`
wait on a pull request's checks before they merge, `mol-pr-ci-diagnose` lists
them to diagnose a failure, and `mol-pr-iterate` reads its coverage check's
link. Their own records of a check are a task's account of itself, as in the
build pack, or a run's notes: `pr-pipeline`'s `mol-pr-ship` notes on its run's
root which gates passed. The `release-gates` directory holds one release
decision, written as a document that names the reviewed commit, the merged
tree and whether the tests passed, and nothing reads it back. None reads a
record of a rig's checks at a commit, made by whichever run ran them, before it
runs anything itself.

So the pack keeps `review-evidence.sh`. It reads the records `gctk rig` keeps
at a commit in the rig clone's git directory, which every run of a rig's checks
writes, prints them the same way for every check's review, and runs nothing.

### A recorded fail judged pre-existing

The packs Gas City bundles judge a failing check pre-existing in the run that
meets it. `core`'s `mol-polecat-base` runs the checks on the base branch in its
`preflight-tests` step, before any work starts, and a failure there "is on the
base branch, so it is not yours". The worker finds a bug bead whose title
carries the failing test function's name and confirms it with a comment, or
files a P1 bug titled `Pre-existing failure: <key>`, and gets on with its own
work. `gastown`'s refinery does the same at the merge. When a check fails on
the merged head, it diagnoses "branch regression or pre-existing on target",
and it merges past a pre-existing failure once a `Pre-existing failure` bug is
found or filed (`mol-refinery-patrol`). Each tracks the failure once, as a bug,
and acts on its judgment in the run that made it. Neither records which fail,
at which commit, the judgment covered, so a later run at the same commit, such
as a review, cannot tell a fail that was judged from a new one. The other
judgment `core` ships with the word in it is the mutation baseline of its
review quorum lanes: a lane runs `git status` before and after it reviews, and
reports only the change between, so dirty state that was there before it is
not the reviewer's.

The packs Gas City publishes judge a failure in the session that meets it too.
`contributing-to-gascity`'s `review` skill runs a failing test on a clean
`main` checkout and calls one that fails there as well a pre-existing flake,
"not yours, note it and move on". `superpowers`' `using-git-worktrees` runs
the tests as a baseline before work starts, so that new bugs can be told from
pre-existing ones, and asks the person whether to go on when they fail.
`gstack`'s `ship` workflow triages pre-existing test failures instead of
stopping on them. `pr-pipeline`'s `mol-pr-ship` classifies a failure that the
repository's CI docs list as a baseline flake as baseline noise, and surfaces
that in its ship report, and `pr-review`'s `mol-pr-ci-diagnose` sorts a pull
request's failing checks by cause, an infrastructure flake among them, from
their logs. The `pre_existing` flag of a `compound-engineering` review finding,
and the `bmad` code review's deferral of a pre-existing issue, mark a finding
about code the change did not touch, not a failing check. None records a
judgment that a later run at the same commit reads.

So the pack keeps `rig-check-lib.sh`. The mark it reads, and the tracker ledger
behind it, are the pack's existing `rig_check_pre_existing` key and
`preexisting-failure.sh`. What the change adds is one definition of when a mark
answers, which the self-review's exit condition and the review's gather share.

### A finding's grade and record

`core`'s `mol-review-quorum` fans a review out to read-only reviewer lanes and
a synthesis. Each lane writes a `review-quorum.lane.v1` object to its step
bead's `gc.output_json`, with `findings` listed as "array of findings with
severity, title, body, file, line or range". Package `reviewquorum` declares the
contract. A `Finding` carries a title, a body, a file, a start and end line, a
free-text severity, the lanes that raised it, and evidence. A lane's verdict is
`pass`, `pass_with_findings`, `fail` or `blocked`, and the lane chooses it.
`Finalize` merges the lanes' findings on a key of the severity, title, body,
file and range. The engineering doc *Dispatch (Sling)* says the finalizer
"defines the durable contract but is not invoked by formula synthesis yet". No
Go code outside the package imports it, so no `gc` command runs it and a pack
has no way to call it.

The pack's quorum lanes already write this object, `mol-review-quorum-signoff`'s
lanes putting the grade the check's method gives a finding in its `severity`,
and the finding contract names its grade `severity` too. The object does not
carry the rest of the need. A finding in it has no category, failure scenario or
verification. Its severity is free text that no rule ties to the verdict. It
lives in one run's step output, where nothing rules it, while the pack's finding
is a bead on the anchor that the validator rules one by one, through rounds of
rework. And its merge key holds the body and the severity, so a re-raise that
rewords its body or regrades it is another finding. The pack's key is the lane
and the normalized locus and message, and leaves the contract out, so a re-raise
whose scenario is reworded finds the open finding.

The build pack Gas City bundles, `gascity`, defines a review report and ties
its grades to the outcome. A `gc.verdict-report.v1` report's front matter
carries a verdict, `pass` or `fail`, a severity, and its findings, each with an
id, a severity of `minor`, `major` or `blocker`, a title, its evidence and the
fix it requires (the pack's README, and `validate_verdict_report.py`).
`github_reports.py` turns the verdict and the worst severity into the outcome
its pull request review comment shows: approve, comment, request changes or
block (`review_outcome`). That is the nearest native shape for a grade that
decides the verdict. It does not carry the rest of the need. Its finding has no
locus, category or failure scenario. It asks every finding for evidence, where
the contract asks each blocking finding whether its trigger was confirmed or is
plausible, and leaves out a candidate that was refuted. A report that carries
any finding is a `fail`, because a `pass` must have severity `none` and the
report's severity must be its worst finding's, while under the P2 rule the
operator ruled, a review whose findings are all P2 approves
([review-coverage.md](../tk-qjdt90g/review-coverage.md#at-the-contract-sitting)).
And the report is a file among a build's artifacts, read by that build, where
the pack's finding is a bead that the validator rules on its own and a later
round finds again. The build pack's loops gate on the grade the same way: the
gap-analysis loop's check script fails while the report still names a
critical, blocker or major finding, so the loop runs again until none remains
(`gap-analysis-approved.sh`). Its build workflows write their review as a
`gc.build.review.v1` artifact instead, whose findings are a Markdown section
with no field per finding (`schemas/build/review.v1.yaml`).

The bundled packs keep a review's findings where the run that made them reads
them. The build pack's fix loop turns a report's findings into a fix convoy of
work beads, created or resumed by a key of the run, the loop's kind and
iteration, the report's hash, the finding's hash and the convoy under fix
(`fix-convoy`'s `create-fix-convoy` step). The key holds the iteration and the
report's hash, so each round's findings key fix work of their own. `gastown`'s
review legs write each leg's full report, its findings a Markdown section, into
the leg bead's notes, where the coordinator reads it back (`mol-review-leg`,
`mol-idea-to-plan`). Those legs review plans, not code.

Gas City grades its own diagnostics. `gc doctor` marks a check blocking or
advisory (package `doctor`, `CheckSeverity`), `gc lint` reports a pack's
diagnostics with a severity, a path and a line
([gc lint](https://docs.gascity.com/reference/cli#gc-lint)), and the emergency
spool keeps a severity on each record it writes (package `emergency`, `Record`).
Each grades what Gas City found in a city or a pack, not a reviewer's finding on
a change.

bd's issue has a priority, from 0, Critical, to 4, Backlog
([Priorities](https://beads.gascity.com/core-concepts/issues#priorities)). bd
calls it how urgent the work is
([Labels](https://beads.gascity.com/core-concepts/labels#design-philosophy)),
and Gas City offers ready work in canonical ready order, priority first
([gc ready](https://docs.gascity.com/reference/cli#gc-ready)).
A finding's grade says whether its defect blocks the merge, which is not how
soon anyone works the finding. In this pack the field is also taken: a finding
bead carries `anchor_bead`, so `priority-lib.sh` computes its priority from its
anchor's, and the next computation overwrites any other value written there.
bd has no severity field, and its labels are tags. A published pack does carry
a grade as a label: `oversight-rig`'s project lead labels each rollup bead
`severity:escalate` or `severity:info`, and its `escalate-rollups` order
delivers the escalating ones. A finding's grade and category are read with its
scenario and verification, which are prose a label cannot hold, so the pack
keeps the contract together in the finding's metadata.

Among the packs Gas City publishes, each reviewing pack defines a finding of
its own, and between them they carry most of the contract's fields. `gstack`'s
`cso` security review comes nearest. Each of its findings has a severity, a
category, an exploit scenario, a status of `VERIFIED`, `UNVERIFIED` or
`TENTATIVE`, and whether it was verified independently or by its own reviewer.
Its reports are JSON files under `.gstack/security-reports/`, which match a
finding across reports by a hash of its category, file and title. `gstack`'s
`review` skill logs each finding's fingerprint, its path, line and category,
with its severity and what was done with it, and a later review suppresses a
finding the user skipped while its file is unchanged. `compound-engineering`'s
`ce-code-review` gives its reviewer personas a JSON schema whose finding
carries a title, a severity from P0 to P3, a file and line, why it matters (its
impact and failure mode), a fix class, an owner, a suggested fix, a confidence
anchor from 0 to 100, its evidence and whether it is pre-existing
(`findings-schema.json`). Its findings are the artifacts of one run. Those left
unfixed go to the user, who applies them, files each as a ticket in the
project's tracker with its severity and reviewer as labels, records them as
known residuals, or stops (`ce-work`'s `shipping-workflow.md` and
`tracker-defer.md`). `pr-review`'s `review-pr` gives each finding a category, a
grade of `blocker`, `major`, `minor` or `nit`, a confidence, its evidence and
why it matters, in the review it posts. `bmad`'s code review gives a finding an
id, its source, a title, its detail and a location, and sorts each into
`decision_needed`, `patch`, `defer` or `dismiss`. `pr-pipeline`'s `mol-pr-ship`
scores each finding by category, severity and confidence, its lead challenges
every blocker and major against the diff and drops one that no reviewer can
ground, and its run's root notes the counts per iteration, not the findings.
Each format is one pack's own, kept in its run artifacts, logs, report files or
posted comments and read by its own skills. No validator rules any of them
finding by finding, and no Gas City component reads them, so none is a
primitive the pack could compose.

Their rules for a grade mostly agree with the P2 rule's verdict and differ on
deferral. Several approve a review whose findings are all minor:
`pr-pipeline`'s `mol-pr-review` maps purely minor or nit findings to `approve`,
and a blocker to `block` or `request_changes` by its category, and
`mol-pr-ship` ships once only minors remain. Where a pack ties deferral to a
grade, it defers the lowest: `superpowers`' `requesting-code-review` fixes
Critical issues at once and Important ones before going on, and notes Minor
ones for later. The P2 rule decides the other way for a P2 filed beside a
blocking finding, which is ruled must-fix or declined in that round and never
deferred, so `finding.sh` refuses its deferral. Other packs defer by something
other than the grade: `bmad` an issue the change did not cause, and
`compound-engineering` an advisory finding, one with no concrete fix, or one
that waits on a design decision.

So the pack keeps the contract's fields. `finding.sh upsert` writes them
where the finding's record already lives: its `finding.*` metadata, beside
`finding.key`, `finding.lane`, `finding.source` and `finding.disposition`, and
its description, which is what the validator reads.

### A finding set checked and rendered

Gas City can check a step's output before the next step runs. A
`[steps.check]` script runs once an iteration of the step closes, and a nonzero
exit spawns the step's next iteration while budget remains
([Check](https://docs.gascity.com/reference/specs/formula-spec-v2#3-1-check)).
mol-review's reviewer writes its finding set in the `review` step and calls
`signoff.sh` in the next step, `verdict-and-drain`, so a check on `review` would
run before anything is written. A set that failed it would cost a new
iteration of the review, where `signoff.sh`'s refusal lists each problem to the
agent that holds the review and costs one corrected call. The quorum's
synthesis writes its set and calls `signoff.sh` in one step, so a check there
would run only after the writes. The build pack takes the check route for its
own artifacts: each stage of its build workflows, review among them, is gated
by a check script that validates the stage's artifact against its schema
(`build-artifact-valid.sh`, which runs `validate_build_artifact.py`). A review
artifact's findings are a Markdown section, so that check holds the report's
status, trace and sections, not a field of any finding.

The build pack checks its review report before anything is posted from it.
`validate_verdict_report.py` refuses a report whose severity is not its worst
finding's, a `pass` with a severity, a `fail` with no findings and a finding
that lacks a field, and `github_reports.py` renders no comment from a report it
refuses. It checks the build pack's report, whose shape the section above
compares with the contract. The comment it renders from a valid report
(`render_pr_review_comment`) gives the outcome, the report's verdict and
severity, whether a person approved, and where the report is, and lists none
of the findings. `signoff.sh`'s Findings block lists each finding on the posted
verdict, with its grade, category, locus, message, failure scenario and
verification, so the contract is readable on every verdict.

The other checks Gas City makes of a step's output test less.
`gc.output_json_required` makes a retry attempt transient when its output is
missing or does not parse as JSON, and checks nothing of its shape (package
`dispatch`, `classifyRetryAttempt`). The `gc.output_json_schema` key a quorum
step carries is read by no Go code. `gc lint` warns, for each graph.v2 step
that requires `gc.output_json` and has no drain, that `gc.output_json` "is
deprecated; use drain in v2 formulas" (package `formula`,
`GraphV2OutputJSONWarnings`). `reviewquorum`'s `Finalize` refuses a
lane whose finding count does not match its findings, or whose verdict reports
findings it does not list, and nothing calls it.

Among the packs Gas City publishes, `compound-engineering`'s `ce-code-review`
checks each reviewer's return for its schema's fields and values, as a step its
orchestrating model runs, and drops a malformed return or finding instead of
refusing it. It then merges findings on the file, a band of lines and the
title, and hands the survivors, every P0 and P1 among them, to validator
subagents, one per finding, each of which keeps or drops its finding. No script
in the packs loads that schema: the skill writes it into its reviewers'
prompts. Among every pack's scripts, the build pack's
`validate_verdict_report.py` is the one that checks a review finding's fields.
`bmad`, `compound-engineering`, `gstack` and `superpowers` gate their review
artifacts with the build pack's check script, which holds a report's status,
trace and sections, `gstack`'s `review` skill skips an output line that is not
valid JSON, and `pr-review`'s `review-pr` stops when a reviewer's output is
empty or malformed.

So `signoff.sh` keeps the check and the Findings block. It is the one writer
of every verdict, so the contract holds on every path to one, and it refuses a
set that breaks the contract before any write.

### Keys on the finding bead

Gas City leaves a pack's private metadata keys undeclared. Package `beadmeta`
names its own scope as "engine-touched bead-metadata KEY NAMES", and says that
pack- and prompt-private keys that no Go file reads "stay open-world by design
and are intentionally NOT declared here". The engineering doc *Bead Store* says
the namespace "is deliberately open-world at the edges". bd calls metadata "the
preferred extension point" for data specific to an integration, an orchestrator
or a team workflow, and reserves only the `bd:` and `_` prefixes
([Issue Metadata](https://beads.gascity.com/core-concepts/metadata#reserved-key-prefixes)).
So the finding contract's keys are pack keys, registered in the pack's
lifecycle registry with the rest of a finding's.

## What the pack keeps

The pack keeps `review-evidence.sh` and `rig-check-lib.sh`, the finding
contract's keys, `finding.sh upsert`'s contract flags, `set-disposition`'s
refusal to defer a P2, and `signoff.sh`'s check and rendering of a finding
set. The gather reads the records of a rig's own checks at a commit, which Gas
City does not keep. The judgment is a record of which fail, at which commit, a
tracked failure covers, so that a later run at that commit can read it, where
Gas City's packs act on the judgment only in the run that makes it. The contract
keeps on a finding bead what Gas City's review findings lack, in bd's metadata
and the bead's description. This record goes stale, and the surface moves onto
Gas City, when Gas City keeps a rig's check results at a commit where a review
can read them before a pull request exists, records a pre-existing judgment that
a later run at the same commit can read, or ships a review finding that a
validator rules on its own and that carries a grade with its failure scenario
and verification.
