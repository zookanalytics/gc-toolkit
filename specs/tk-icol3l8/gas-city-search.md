---
name: Gas City search for a conversation's hold on an open PR's merge
description: Use when you judge how a conversation on an open PR holds the PR's merge, or whether a gate that closes itself when the conversation closes could replace the writers that answer or withdraw it.
---

# Gas City search for a conversation's hold on an open PR's merge

Read on 2026-11-09 at `gastownhall/gascity` main 0629c3fce24f and at beads
v1.3.4 (`steveyegge/beads`, the bd this city runs). The change makes a
conversation whose subject is an open PR hold the PR's merge for exactly as
long as the conversation is open. `gc-helm.sh open` files a human gate on the
PR's anchor under the conversation's key, `conversation.<id>`. Engage files it
when it starts a sitting on a conversation that lacks one. Every writer that
closes the conversation answers the gate or withdraws it.

## What the search looked for

- **A wait a person clears, which every reader treats alike.** bd's human gate
  (`bd gate create --type=human --blocks <bead> --await-id <key>`). It blocks
  the bead it names, so the anchor leaves `bd ready` and its merge waits, and
  Gas City's core pack announces it (`notify-on-human-gate-creation` in
  [internal/bootstrap/packs/core/README.md](https://github.com/gastownhall/gascity/blob/0629c3fce24f/internal/bootstrap/packs/core/README.md)).
  The change composes it through `assets/scripts/human-gate.sh`, which keeps
  one open gate per bead and key and files it in the anchor's own store.
- **A gate that closes itself when the conversation closes.** bd has one:
  `evaluateGates` (`cmd/bd/gate.go`, beads v1.3.4) resolves an `await_type`
  `bead` gate through `checkBeadGate` once the bead its await id names has
  closed. Nothing runs that check here. Gas City's `gate-sweep` order checks
  only timer and gh gates, and its script says bead-type gates are skipped
  until beads restores cross-rig routing
  ([gate-sweep.sh](https://github.com/gastownhall/gascity/blob/0629c3fce24f/internal/bootstrap/packs/core/assets/scripts/gate-sweep.sh)).
  The formula spec says no bundled watcher resolves any gate type
  ([formula-spec-v2.md](https://github.com/gastownhall/gascity/blob/0629c3fce24f/docs/reference/specs/formula-spec-v2.md),
  "Gate `type` vocabulary"). A bead gate would therefore stay open after its
  conversation closed until something the pack added checked it, and that
  check would be a sweep of its own. Its `await_type` is not `human`, so
  `prstatus.Holding` would not count it as a gate either, and the PR's
  `held:` label would read nothing while the merge waited.
- **A plain `blocks` edge from the anchor onto the conversation.** bd releases
  that one when the conversation closes, with no writer. But the edge makes
  the conversation the anchor's blocker, and `prstatus.Holding` counts a
  blocker that is no gate only when a person owes its next move: it is routed
  to a person, is a decision, or is a merge anchor waiting on a person. A
  conversation is none of these, so the label would read the conversation as
  work in flight, at most `held: blocked` once the merge pass's verdict names
  the blocker, never `held: gate`. Reading it as a gate would take a rule
  outside `prstatus`, which this work bead rules out. A conversation that
  blocks its subject also breaks the shape the board and engage read, a task
  that blocks nothing (`assets/scripts/conversation.sh`).
- **A Gas City primitive that ties a hold to a session's work.**
  `gc session wait --sleep --on-beads` sleeps a session until beads close. It
  holds the session, not another bead's merge.

## How the change uses what there is

The hold is the human gate, filed and withdrawn through `human-gate.sh`, whose
`--retract` resolves the filer's own gate `moot:` once its situation has gone.
The writers that close a conversation are the sign-off, dismiss and the premise
re-check's moot or benign close. The sign-off already answers every gate the
conversation replies to. Dismiss and the close block withdraw the gate under
the conversation's key on the subject's anchor. The sign-off refuses `--leave`
on that gate, because the gate ends with the conversation.

## Not built

A sweep that closes a `conversation.<id>` gate whose conversation has closed.
Each close path withdraws or answers the gate itself, and one whose withdrawal
does not land says so with the command that withdraws it.
