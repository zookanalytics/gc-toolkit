---
name: Gas City search for one definition of what holds a PR
description: The search the arch check asks for before `gctk pr-status derive --json` gains its `reasons` key, what each bd and Gas City primitive covers and leaves, and the mutant runs that show a change to the definition reaches every reader. Read it when judging whether that key or the prstatus gathering should exist, or when a later bd or Gas City release may retire them.
---

# Gas City search for one definition of what holds a PR

What holds a PR is decided in `services/gctk/prstatus`. `prstatus.Read` gathers
what the city records about each anchor through a `Store`, the reader's adapter
onto the bead store, and `Derive`, `Held`, `Reasons` and `Blocked` decide from it.
The PR's labels and `gc-helm.sh` engage reach it through `gctk pr-status derive`,
and the helm board imports it and hands it the beads library as its store. This
adds operational surface in one place:

- `gctk pr-status derive --json` gains a `reasons` key beside `status` and `held`:
  each thing behind the held values, `{"held", "id", "title"}`. Engage reads it,
  so the `gates` verb, whose only caller engage was, is removed.

It adds no metadata key, bead kind or lifecycle state. Read on 2026-11-06 at Gas
City upstream `74d62eb1e0c0` (`gastownhall/gascity`) and beads upstream
`8c3eb30f30f7` (`gastownhall/beads`).

## What was searched

| Primitive | What it gives | Why it does not cover the need |
|---|---|---|
| `bd list`'s gate decoration (`gatesByIssueID` in `cmd/bd/gated.go`) | Per listed bead, the open gates holding it back, by id, from the bead's own dependency rows, batched per page | One level. A gate on a rework or a review the anchor waits on is not a gate on the anchor's own edges, so it is not named. It knows nothing of a blocker a person owes, or of the PR's review threads and the merge pass's verdict |
| `bd human list` (`cmd/bd/human.go`) | The beads labeled `human` | A label a bead carries about itself. It names no bead that holds another, and nothing writes it for what holds a PR |
| Gas City's hold labels (`DispatchHoldLabels` and `HumanLabel` in `internal/beadmeta/hold_labels.go`) | `hold:mayor`, `hold:external` and `human`, the labels that keep a bead itself out of dispatch | They answer whether a bead is work for whoever asks, not what holds a PR from landing, and they follow no edge |
| Gas City's GitHub PR monitor (`EvaluatePullRequests` in `internal/githubmonitor/monitor.go`, run by `gc github pr backfill` in `cmd/gc/cmd_github.go`) | GitHub's readiness of a PR: clean, pending, failed, conflicted, behind, blocked, draft or unknown | It reads GitHub, and the held values read the city's own state: the human gates the anchor's edges reach, its blockers and the merge pass's recorded verdict and thread count. Its `blocked` is GitHub's mergeability block, which reads the same for a required check still running as for one that failed |
| Gas City's durable waits (`GET /v0/city/{cityName}/waits`, `WaitView` in `internal/api/huma_types_waits.go`) and `AwaitsHuman` (`internal/beadmeta/human_wait.go`) | A session's own wait, and a seat's ask about the work bead it claimed | Neither names what holds a PR |

The walk from an anchor to the human gates behind its blockers is
`prstatus.HoldingGates`, which landed with its own search
(`specs/tk-1tfzr71.34/gas-city-search.md`). This change adds no walk.

No primitive returns what holds a PR, and each thing behind it, from the bead
graph and the PR facts the city records. So the definition stays in the pack, in
the one package, and the change makes it the only one: the gathering moves into
`prstatus.Read`, and the key carries the reasons the definition already decides
for its held values, on the verb the label already calls. Engage reads them from
that answer instead of from a second verb.

What retires the package is the merge member, tk-1tfzr71.20: its notes record
that `prstatus` moves under `gctk pr status` with whichever of it and the
GitHub-intake member, tk-1tfzr71.21, rewrites the facts.

## What shows one change reaches every reader

`services/gctk/prstatus/fixture` holds the scenarios each reader is tested
against, as beads and their edges, and an in-memory `Store` over them.
`TestPRStatusDeriveReadsTheDefinition` renders each into the `gc bd` reads the
derive makes, and `TestBoardReadsTheDefinition` into the beads library's reads,
through the real gather and `BuildBoard`. Each compares its reader's answer with
what `prstatus.Read` gathers from the same beads, so the expected answer is the
definition's own. `TestScenariosPinTheRule` pins the definition's answers in
`prstatus` itself. Engage and the label call `gctk pr-status derive`, and their
shell suites run the built binary.

Three mutants, run with `go test -overlay` on 2026-11-06 at the branch's head:

| Mutant | The definition's pins | The verb's reach test | The board's reach test |
|---|---|---|---|
| The definition stops counting a blocker a person owes (`Reasons`) | fail: `TestScenariosPinTheRule`, `TestReasons` | pass | pass |
| The board drops `held: blocked` unless a decision blocks the anchor (`prHeld`) | pass | pass | fail: 4 scenarios |
| The verb drops `held: review` when a thread count is recorded (`prStatusDerive`) | pass | fail: 3 scenarios | pass |

A change to the definition reaches both readers with no edit to either, and a
reader that keeps a rule of its own parts from the definition on the scenarios
that rule changes.
