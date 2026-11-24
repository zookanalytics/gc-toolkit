---
name: Gas City search for the refinery's edit of an open PR (tk-1tfzr71.237)
description: The primitives searched in Gas City for each need of moving the refinery's edit of an open PR's title and body onto `gctk pr compose --edit`, with what each covers and why the flag the change adds is the pack's. Read it when reviewing `gctk pr compose --edit --pr`, as AGENTS.md asks of a change that grows existing surface with a flag.
---

# Gas City search for the refinery's edit of an open PR

This change adds one flag, `--pr <url>`, to `gctk pr compose --edit`. It names
the open PR the edit takes when the bead that owns the PR records none yet,
such as a PR the refinery adopts from the bead's branch. `refinery-publish.sh`
calls the mode on every PR it publishes onto, in place of its own read of the
PR, its comparison and its `gh pr edit`. The change adds no bead key, no order,
no script and no mode. Each need names the primitive searched, at
`gastownhall/gascity` main d6d5784f9cff (2026-11-24).

## Edit an open PR's title and body

**Not covered by Gas City.** Gas City reads GitHub and writes nothing on a PR.
Its PR monitor's client, `GraphQLClient` in `internal/githubmonitor/client.go`,
"queries GitHub's GraphQL API for pull-request readiness state" through its one
request, `ListOpenPullRequests`. No file in the tree outside its tests runs
`gh pr edit` or GitHub's `updatePullRequest` (`git grep -E 'updatePullRequest|gh pr edit'`
over the tree). The edit is GitHub's own mutation, `updatePullRequest`
([GitHub's GraphQL reference](https://docs.github.com/en/graphql/reference/mutations#updatepullrequest)),
which `gctk pr compose --edit` already sends for a review run's push. The
refinery now calls the same mode, so one writer composes, compares and edits
the page.

## Name the PR an edit takes before the bead records it

**Not covered by Gas City.** The one PR key Gas City reads is
`pr_review.pr_url`, which `externalURL` (`internal/runproj/summary.go`) and the
dashboard's `resolvePrRef`
(`internal/api/dashboardspa/web/shared/src/links/relation-index.ts`) read to
link a run's lane to its PR. It is a link to display, which nothing in Gas City
writes outside its fixtures and no writer resolves to edit a PR. The pack's
own record is the pending record, which `gctk pr record` writes once the head
is pushed, under the store's record lock. Writing the PR onto the bead before
the edit would add a second write to the one publication. So the refinery
passes the URL of the PR it read and checked, as it already does to
`gctk pr draft --pr`, and the edit takes that PR.
