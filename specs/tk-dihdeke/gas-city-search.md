---
name: Gas City search for starting the size check without pull_request_target (tk-dihdeke)
description: The primitives searched in GitHub Actions and Gas City for starting gc-toolkit's pr-size check on each push to a pull request and each change of its base branch once GitHub's default event policy blocks pull_request_target, what each covers, and why the change adds pr-size-start.yml. Read it when building or reviewing how the size check starts, as AGENTS.md asks of a change that adds operational surface.
---

# Gas City search for starting the size check

The change adds operational surface to gc-toolkit's own CI: the workflow
`.github/workflows/pr-size-start.yml`, and that workflow as a second source of
the `workflow_run` trigger of `.github/workflows/pr-size.yml`, which loses its
`pull_request_target` trigger. Each need below names the primitive searched, in
GitHub's documentation as the github/docs repository holds it at d7487f5deb
(2026-11-20), in the webhook payload schemas of octokit/webhooks at aa80c24a3f,
and in Gas City upstream main (gastownhall/gascity) at 1f1f1289df
(2026-11-22).

None of this runs in a city. It is gc-toolkit's CI, which no rig runs, so the
platform it builds on is GitHub Actions, and Gas City is searched for how its
own CI starts a job that writes on a pull request.

## Start a default-branch job on a pull request's own events

**Covered by `pull_request_target` until GitHub's default policy blocks it.**
The page "Securely using pull_request_target"
(`content/actions/reference/security/securely-using-pull_request_target.md`)
says that under the event "the workflow, and any subsequent `actions/checkout`
call that does not specify a `ref`, is taken from the **base repository's
default branch**". Its section "Default policy for `pull_request_target`" says
GitHub "provides a default event policy that blocks the `pull_request_target`
event in public repositories", that the policy "Does not apply to private or
internal repositories", and that "On December 2, 2026, GitHub will enforce the
default policy for affected repositories that were using the default
`pull_request_target` policy before general availability." gc-toolkit is
public, and pr-size.yml was its only workflow on the event.

The same section offers the way to keep the event: "create or update an
applicable Actions event policy that explicitly allows `pull_request_target`".
Only the operator can read or set the repository's policies. They chose to move
off the event instead, answering "yes change as recommended" (the ruling in
tk-dihdeke's description).

## Run on each push and change of base branch, into any branch

**Covered by `pull_request`.** The events reference
(`content/actions/reference/workflows-and-actions/events-that-trigger-workflows.md`,
section `pull_request`) says that "By default, a workflow only runs when a
`pull_request` event's activity type is `opened`, `synchronize`, or
`reopened`", and that `types` selects others. octokit's schema
`payload-schemas/api.github.com/pull_request/edited.schema.json` gives an
`edited` event's `changes` the optional keys `base`, `body` and `title`, so
`github.event.changes.base` is present only when an edit changed the branch the
pull request merges into. A `pull_request` trigger with no `branches` filter
runs for a pull request into any branch.

`pull_request` cannot hold the measuring job. It "runs the workflow file from
the **merge commit of the pull request**" (the pull_request_target page, "Risks
of `pull_request_target`"), so a change could edit the job, the tool or the
deletion plan to hide what it adds. pr-size-start.yml therefore holds no
permissions, checks out nothing and runs nothing from the pull request, and
only its end matters.

The event brings one limit the old trigger did not have. The events reference
says "Workflows will not run on `pull_request` activity if the pull request has
a merge conflict. The merge conflict must be resolved first. Conversely,
workflows with the `pull_request_target` event will run even if the pull
request has a merge conflict." A pull request with a merge conflict therefore
gets no size update until the conflict is resolved, which is also when its
tests run.

## Measure from the default branch when that run ends

**Covered by `workflow_run`, the trigger pr-size.yml already had.** The events
reference (section `workflow_run`) gives `GITHUB_SHA` as the "Last commit on
default branch", says that "This event will only trigger a workflow run if the
workflow file exists on the default branch"
(`data/reusables/actions/branch-requirement.md`), and that "The workflow
started by the `workflow_run` event is able to access secrets and write tokens,
even if the previous workflow was not." It names the triggering workflows by
name, of which "only one of the workflows needs to run", and says that "A
workflow run is triggered regardless of the conclusion of the previous
workflow", which the job reads in `github.event.workflow_run.conclusion`. It
also says "You can't use `workflow_run` to chain together more than three
levels of workflows". pr-size-start.yml to pr-size.yml is two.

octokit's `payload-schemas/api.github.com/common/workflow-run.schema.json`
gives the run's `name` ("The name of the workflow run"), its `event`, its
`conclusion` (success, failure, neutral, cancelled, timed_out, action_required,
stale, skipped or null) and its `pull_requests`, each with a `number`. On
gc-toolkit the runs list fills `pull_requests` for an open pull request into
main and into an integration branch, and none of the last 400 pull requests
(#1230 on) came from a fork.

Gas City's own CI composes the same pair of events.
`.github/workflows/docs-autofix.yml` at 1f1f1289df runs on `workflow_run` of its
`bazel` workflow, which runs on `pull_request`, with the job condition
`github.event.workflow_run.event == 'pull_request' &&
github.event.workflow_run.conclusion == 'failure'`, and its header says it
"runs with write permissions via workflow_run, so it never checks out or
executes PR code". The same tree's `pr-evidence-watchdog.yml` stays on
`pull_request_target` "so it still executes even when the head workflow itself
never triggered for that head commit", the case the merge-conflict limit above
names.

## Keep one writer for each pull request's comment

**Covered by `concurrency`, as before.**
`data/reusables/actions/actions-group-concurrency.md` says a group holds "at
most one running job or workflow", that `cancel-in-progress: true` also cancels
"any currently running job or workflow in the same concurrency group", and that
runs "are processed in first-in-first-out (FIFO) order according to the time
each one started waiting on the concurrency group, not the time each workflow
was dispatched". So every run that measures a pull request takes its group, and
pr-size.sh reads the head and base from the pull request itself.

A workflow-level group holds every run of the workflow, including one whose job
its `if:` skips, so a run that measures nothing takes a group of its own, and
the group's expression repeats the job's condition. A job-level group, which
tests.yml uses, would let the condition be written once, because a job its
`if:` skips never starts. The concurrency page does not say whether such a job
takes its group, and gc-toolkit's runs since tests.yml moved its groups to the
jobs neither show nor refute it: no draft's tests run started while a ready run
of the same pull request was in progress. So the change keeps the
workflow-level group, and pr-size.test.sh evaluates the condition and the group
against a sample of each event, so the two cannot drift apart.

## Show a failed size run on the pull request

**Not built, as the ruling accepts.** A `workflow_run` run's check sits on the
default branch's tip, so a size run that fails shows in the Actions tab and on
main's tip, not on the pull request. The REST API's "Create a check run" and
"Create a commit status" would let the job report on the pull request's head,
with `checks: write` or `statuses: write`. The work's description names this
gap among those the operator accepted with the course, and the check holds no
merge, so the change adds neither.

## Why a workflow and not gctk

AGENTS.md puts tooling that runs only on this repository outside the rule that
new pack code goes into gctk. pr-size-start.yml is GitHub Actions configuration
for gc-toolkit's own CI and holds no logic, so gctk is inappropriate for it.
