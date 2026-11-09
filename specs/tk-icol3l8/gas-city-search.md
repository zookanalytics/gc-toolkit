---
name: Gas City search for a conversation's hold on an open PR's merge
description: Use when you judge how a conversation on an open PR holds the PR's merge, or whether another primitive could hold it.
---

# Gas City search for a conversation's hold on an open PR's merge

Read on 2026-11-09 at `gastownhall/gascity` main 0629c3fce24f and at beads
v1.3.4 (`steveyegge/beads`, the bd this city runs). The change makes a
conversation on an open PR hold the PR's merge until the conversation closes,
and otherwise block nothing. The PR's anchor depends on the conversation
through a plain `blocks` edge, `gc bd dep add <anchor> <conversation> --type
blocks`. `gc-helm.sh open` adds it, engage adds it whenever it starts a
sitting, and the converse hold step adds it when the subject's PR has opened
since. No close path removes it. A sitting that is helping the PR land, or
whose conversation has nothing to do with whether it lands, lifts it with
`gc bd dep remove <anchor> <conversation>`.

## What the search looked for

- **A hold that clears itself when the conversation closes.** bd's `blocks`
  dependency is that hold. bd counts a bead blocked while one of its `blocks`
  edges names a bead that is not closed (`IsBlockedInTx` in
  `internal/storage/issueops/dependency_queries.go`, beads v1.3.4), so the
  anchor stays blocked while the conversation is open, and the conversation's close lifts the block by
  whatever route it closes, with no release to write. bd also refuses an
  unforced close of a bead with a live direct blocker (`CloseIssueCheckedInTx`
  in `internal/storage/issueops/close.go`, which `bd close` and
  `bd update --status=closed` both take), so the anchor's close waits too. The
  edge composes without a read first. An add of an edge bd already holds with
  the same type is a no-op that exits 0, and a remove of an edge that is not
  there is a no-op too (`addDependencyInTx` and `removeDependencyInTx` in
  `internal/storage/issueops/dependencies.go`). The edge raises no cycle
  against the conversation's `tracks` edge onto its subject, which is the
  anchor itself when the subject is the anchor, because the cycle check walks
  only `blocks`, `conditional-blocks` and `parent-child` edges
  (`cycleReachabilityQuery`), and the hierarchy check reads only
  `parent-child` ancestry (`CheckBlockingHierarchyInTx`).
- **A human gate on the anchor.** bd's human gate
  (`bd gate create --type=human --blocks <bead>`) holds the merge as well, but
  it is a second bead with a lifecycle of its own. Every writer that closes the
  conversation then has to answer or withdraw it, a close by hand leaves the
  merge waiting on a closed conversation, and a human gate comes to mean two
  things: a question someone must answer, and a hold that ends with a
  conversation.
- **A gate that closes itself when a bead closes.** bd has the `bead` gate
  type, which `evaluateGates` (`cmd/bd/gate.go`) resolves through
  `checkBeadGate` once the bead its await id names has closed. `bd gate create`
  does not offer it: its types are human, timer, gh:run and gh:pr
  (`gateCreateCmd`). Nothing in this city runs that check either. Gas City's
  `gate-sweep` order checks only timer and gh gates, and its script says
  bead-type gates are skipped
  ([gate-sweep.sh](https://github.com/gastownhall/gascity/blob/0629c3fce24f/internal/bootstrap/packs/core/assets/scripts/gate-sweep.sh)).
- **A parent-child link from the conversation to the anchor.** bd refuses an
  unforced close of a bead with open parent-child children
  (`CloseIssueCheckedInTx`), so such a link would hold the anchor's close. But
  bd keeps one link per pair of beads (`uk_dep_issue_target` in
  `internal/storage/schema/cli_migrations.go`), and when the subject is the
  anchor, the conversation's `tracks` link onto it already holds that pair.
- **A Gas City primitive that ties a hold to a session's work.**
  `gc session wait --sleep --on-beads` sleeps a session until beads close. It
  holds the session, not another bead's merge.

## How the change uses what there is

The hold is the `blocks` edge alone, and the readers of a PR anchor's blockers
read it as a person's. A conversation is told by its row: a task assigned to
`human` or to the alias that names its own id, the assignee half of the shape
in `services/gctk/conversation` and `assets/scripts/conversation.sh`.
`prstatus.IsPersonBlocker` counts it, so the PR reads `needs-attention` with
`held: blocked` naming the conversation, and the board's row asks the
operator. `blocker-holder.sh` reads it as a person's hold, neither an actor's
nor stuck, so the merge pass records no blocked verdict for it, and the pass
names it an open conversation when it holds the merge. The board's rule for a
conversation's shape moved from `services/helm/internal/source` into
`services/gctk/conversation`, beside `prstatus`, and the board imports it.

Before a PR opens, its anchor is the work itself. The same edge would stop the
pool's offer, `work-gate.sh` at load-context, the refinery's hand-off, the
bead's close and any arm, so only an open PR's anchor takes one.

## Not built

A release written by any close of the conversation, and a sweep that removes
an edge whose conversation has closed. bd lifts the block when the
conversation closes, so the edge onto a closed conversation holds nothing.
