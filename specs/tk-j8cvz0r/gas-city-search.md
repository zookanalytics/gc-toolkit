---
name: Gas City search for the state each converse sitting carries on the board's wire
description: The search the arch check asks for before the board service adds `state` and `headline` to each sitting it serves, what each Gas City and bd primitive covers and leaves, and why the board composes them. Read it when judging whether those keys should exist, or when a later Gas City release may answer who holds a bead.
---

# Gas City search for the state each converse sitting carries

The board's list of converse sittings could not say whether a sitting was
waiting or had an active session, and its rows derived that state separately.
The operator ruled in sitting `tk-8wi5gcl`, recorded in the notes of
`tk-j8cvz0r`, that the board service derives one state per sitting and carries it
on the wire, that a row's `sitting_state` rolls up from that value, and that the
sitting's headline rides the wire too.

This grows the board service's output by two keys on each entry of `sittings`,
`state` and `headline`, and takes `status` off it. Both new keys are derived when
the board is built and nothing stores them. The change adds no metadata key, bead
kind or lifecycle state, and writes nothing.

Read on 2026-11-01 at Gas City upstream `879a71fa0` (`gastownhall/gascity`) and
beads upstream `062fe1e0d` (`gastownhall/beads`).

## What was searched

| Primitive | What it gives | Why it does not cover the need |
|---|---|---|
| `GET /v0/city/{cityName}/sessions` and `gc session list` (`sessionResponse` in `internal/api/handler_sessions.go`, `docs/reference/cli.md`) | One row per session: its `state`, `alias`, `session_name` and, on the API rendering, `running` | It says whether a session is alive and names no conversation it holds. It is half of what the state composes, and the board already reads it |
| `active_bead` on that row (`findActiveBeadForAssignees` in `internal/api/handler_agents.go`, filled by `enrichSessionResponseWithKeyedPaths`) | From a session, "the first in_progress bead" assigned to its identities | It runs from a session to one bead, and the need runs from a bead to its holder. A conversation no session holds appears on no row, so it cannot read waiting, and a session with a second claim can name the other bead |
| `bd show`, `bd list --assignee` (`docs/CLI_REFERENCE.md`) | A bead's status and assignee | They are the other half of the composition. They say who was given the bead and not whether that session is alive: a session that ends without handing the conversation back leaves it `in_progress` under its alias, which is the case the list read wrong |
| `activity`, `program_status` and `turn` on a session (`sessionResponse`) | Whether a session is in a turn | It is a per-session reading of a different question. A session idle between the operator's turns still holds its conversation |
| The extmsg conversation reference (`docs/guides/connected-clients.md`) | How an external chat client names its conversation with an agent | It binds an outside client to an agent. The pack's conversation is a task that tracks a bead, and this reference carries nothing about it |

No primitive says whether a live session holds a given bead, so the board service
composes the two reads it already makes, the task's status and assignee with the
session list's state. That is a view of platform objects: it mints no state of its
own, and the rule moves unchanged from the row's derivation to the sitting's. The
board's browser cannot do the join, because the wire does not carry the session
list, so the value has to ride the wire for every surface to print one reading.

`headline` is the pack's own fallback over a subject's takeaway, a close reason and
two titles. No primitive holds it, because the takeaway is a pack key, and moving
it onto the wire removes the second copy the web kept by hand.

A release of Gas City that answers who holds a bead would retire the join in
`Facts.sittingState`, and the keys would stay as what that answer prints. The
board's read of the store is itself on the deletion schedule under `tk-1tfzr71.24`,
which keeps the board's views and changes only what they read.
