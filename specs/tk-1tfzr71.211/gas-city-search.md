---
name: Gas City search for a review round's fix in the PR's summary (tk-1tfzr71.211)
description: The primitives searched in Gas City and GitHub for each need of letting a review run's round fix the PR's title and summary, with what each covers and why each gap is the pack's. Read it when reviewing the surface the change adds, `gctk pr compose --edit` and a ruling's `summary` field, as AGENTS.md asks of a change that adds a mode or a key.
---

# Gas City search for a review round's fix in the PR's summary

This change adds one mode, `gctk pr compose --edit`, which brings an open PR's
title and body to the composition the bead that owns it records, and one key,
`summary`, a field of a review run's rule-and-repair output that says the round
fixed a point in the PR's title or summary. `review-run.sh push` gains one call
of the mode, and the gh adapter gains a read of a PR's title and body and an
edit of them. It adds no bead key, no order and no script. Each need names the
primitive searched, at `gastownhall/gascity` main 21ad051d002e (2026-11-23).

## Write a PR's title and body

**Not covered by Gas City.** Gas City reads GitHub and writes nothing on a PR.
The PR monitor's client, `GraphQLClient` in `internal/githubmonitor/client.go`,
"queries GitHub's GraphQL API for pull-request readiness state" through its
one request, `ListOpenPullRequests`. `gc github pr backfill`
(`cmd/gc/cmd_github.go`) files repair beads from what the monitor reads, and
the PR watchdog (`scripts/prwatchdog`) reads check runs. No Go file in Gas City
outside its tests runs `gh pr edit` or GitHub's `updatePullRequest`, and the
core pack's formulas leave the PR to the work they run
(`mol-polecat-report.toml`: "Zero calls to `git push` or `gh pr create`"). So
the write is GitHub's own mutation,
`updatePullRequest`
([GitHub's GraphQL reference](https://docs.github.com/en/graphql/reference/mutations#updatepullrequest)),
made through the pack's gh adapter as its other GitHub writes are, and what it
writes is the pr domain's composition, the one the refinery already publishes
with (`refinery-publish.sh`). The mode composes as the refinery does and edits
only what moved, so the two writers leave the same page.

## Record that a ruling's fix is in the PR's summary

**Covered in part: a step's output.** A step's result is its `gc.output_json`
(`internal/beadmeta/keys.go`, `OutputJSONMetadataKey`), which a review run's
steps already write, so the field rides that output and adds no bead key. Gas
City reads an output's fields only where a fan-out names them
(`internal/dispatch/fanout.go`), and the review run's fan-out reads triage's
picks alone, so what a ruling says is the pack's review domain's to read
(`services/gctk/review`).

## Judge the fixed summary before the run records its result

**Covered: the checked loop.** A step's `check` runs its script after each
iteration, and "any other nonzero exit is a "not yet" verdict that spawns the
next iteration while budget remains" (`docs/reference/specs/formula-spec-v2.md`,
"3.1. Check"). The review run's loop already has that check, `gctk review
passed`, so the pass rule decides that a round which fixed a point in the
summary has not passed, and that a later iteration passes only once the check
that raised the point has run again. No new primitive is needed.
