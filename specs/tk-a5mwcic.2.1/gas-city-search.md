---
name: Gas City search for the suite-time section of the size comment (tk-a5mwcic.2.1)
description: The primitives searched in Gas City, GitHub Actions and an established test-report action for each need of the suite-time section that gc-toolkit's CI adds to each pull request's size comment, with what each covers and why the gaps need the runner's --seconds flag and suite-time.sh. Read it when building or reviewing that surface, as AGENTS.md asks of a change that adds a script or grows one with a flag.
---

# Gas City search for the suite-time section

The change adds operational surface to gc-toolkit's own CI: a `--seconds FILE`
flag on `tools/run-tests.sh`, the script `.github/workflows/suite-time.sh` with
its `summary` and `section` verbs, two steps in each suite job of
`.github/workflows/tests.yml`, the artifact `suite-times-<job>` those steps
upload, and a `workflow_run` trigger with `actions: read` on
`.github/workflows/pr-size.yml`. Each need below names the primitive searched,
at Gas City upstream main bc6bc28712 (2026-11-17), in GitHub's documentation as
the github/docs repository holds it at afa12590d7 (2026-11-16), and in the
README of EnricoMi/publish-unit-test-result-action at a68780caa0 (2026-11-12).

None of this runs in a city. It is gc-toolkit's CI, which no rig runs, so the
platform it builds on is GitHub Actions, and Gas City is searched for a
primitive that tests or reports a suite's time.

## Record each run's seconds

**Not covered, and the gap is one flag.** `tools/run-tests.sh` already measures
each run's wall time for the report line it prints, `PASS <file> (<n>s)`, and
the design's test-seconds are the sum of those lines over a job's log
(specs/tk-a5mwcic.1/measurements.md). `--seconds FILE` writes the same number
as data, one `<run>\t<seconds>\t<status>` line per run of the parallel wave, so
no reader parses the log.

- **Gas City** times its own Go tests. `scripts/go-test-observable` writes
  "opt-in timing artifacts", and `scripts/test-timing-summary.go` aggregates
  them "offline across caller-curated successful `main` push runs"
  (TESTING.md, "Historical timing summaries"). The artifacts are schema-v1
  JSON whose unit is a Go package, test and subtest (`artifactUnit` in
  `internal/testpolicy/timingsummary/summary.go`), and the package sits under
  `internal/`, which no other module can import. It has nothing for a run of a
  shell suite.

## Keep them with the job

**Covered by GitHub Actions: job summaries and artifacts.**

- The workflow-commands reference ("Adding a job summary") gives
  `GITHUB_STEP_SUMMARY`, which "is unique for each step in a job", and its
  limits: "each step is restricted to a maximum size of 1MiB" and "A maximum of
  20 job summaries from steps are displayed per job". Each suite job adds one
  summary of a few hundred rows.
- `actions/upload-artifact` (v7.0.2, cf430e030d) uploads the file, and its
  `if-no-files-found: ignore` covers a job that failed before its suite ran.
  "Artifacts are retained for 90 days by default."

Gas City's own CI uses both: `.github/workflows/bazel.yml` at bc6bc28712 writes
a lane's wall time to the job summary (`echo "bazel / $LANE: exit $rc, ...s
wall, mode $MODE" | tee -a "$GITHUB_STEP_SUMMARY"`) and uploads its reports
with `actions/upload-artifact`.

## Write on the pull request once its tests end

**Covered by `workflow_run`, in the pattern GitHub documents for it.** The
events reference (`workflow_run`) says the event "occurs when a workflow run is
requested or completed", that "The workflow started by the `workflow_run` event
is able to access secrets and write tokens, even if the previous workflow was
not", and that "This event will only trigger a workflow run if the workflow
file exists on the default branch". Its section "Using data from the triggering
workflow" is this change's shape: the first workflow uploads an artifact on
`pull_request`, and a `workflow_run` workflow with `actions: read` downloads it
by `github.event.workflow_run.id` and comments on the pull request.

The same section warns that "Running untrusted code on the `workflow_run`
trigger may lead to security vulnerabilities". pr-size.yml runs only the
default branch's scripts, and reads the artifact as data: suite-time.sh keeps
only lines of the runner's shape and runs nothing from them. The trigger also
names the run's pull request (`workflow_run.pull_requests[]`), which pr-size.sh
takes as `--pr`.

## Read the head's run, its jobs and main's latest runs

**Covered by the REST API, through `gh`.** "List workflow runs for a workflow"
filters by `head_sha`, `event`, `branch` and `status`. "List jobs for a workflow
run" returns "jobs from the most recent execution of the workflow run" by
default (`filter=latest`), each with its conclusion and its start and end.
"List workflow run artifacts" names each artifact of a run, and
`gh run download <run> -n <name> -D <dir>` fetches one. suite-time.sh composes
these and adds only the walk over main's completed runs, newest first, until
each suite job has its own: a run on main that the next push cancelled can
still hold a job that finished.

## Compare the head's time with main's and render it

**Not covered.** This is the gap suite-time.sh's `section` fills.

- **EnricoMi/publish-unit-test-result-action**, the established action for a
  test report on a pull request, publishes results "as a comment in related
  pull requests", as a check, as annotations and as a job summary, from JUnit,
  NUnit, XUnit, TRX and JSON files. With `compare_to_earlier_commit`, "Test
  results are compared to results of earlier commits to show changes", and the
  duration it compares is "The duration of all tests or runs". It shows no one
  file's move beyond the spread between runs and no job's time beside its
  `timeout-minutes`, and its report is a comment and a check of its own (it
  asks for `checks: write` and `pull-requests: write`), where rule 3 of
  docs/built-once-target.md puts the time beside the size in one comment. Using
  it would also mean a JUnit writer in the runner.
- **Gas City's timing summary** emits "the ten slowest top-level tests by
  observed p95 and the ten highest-variance top-level tests" over main's runs
  (TESTING.md, "Historical timing summaries"). It compares no pull request's
  run with main's and writes on no pull request.

So the comparison and its text are the change's own: each job's time beside the
head's `timeout-minutes`, each suite job's summed test-seconds beside main's
latest completed run that recorded them, and the test files the change adds,
removes and moves by more than 10% and at least 2 seconds on the Linux check
(specs/tk-a5mwcic.1/design.md, section 3).

## Why the code is a script beside pr-size.sh

AGENTS.md puts tooling that runs only on this repository outside the rule that
new pack code goes into gctk, and gctk is the pack's binary, which every rig
runs. suite-time.sh is gc-toolkit's own CI, so gctk is inappropriate for it, and
it sits in `.github/workflows/` beside pr-size.sh, whose comment it extends.
