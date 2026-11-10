---
name: Gas City search for gc-helm's home page and its seats
description: The search the arch check asks for before the pack adds gc-helm's home page (a bare gc-helm on a terminal, helm-svc form --home) and the seat verbs gc-helm po and gc-helm mechanik. What Gas City ships for choosing among sessions, opening a named seat's sitting from any state with its prompt, waiting for a start and telling a slept seat from an ended one, read at a named upstream commit, and the gap each leaves that the verbs fill by composing them. Read it when checking whether the home page or a seat verb can move onto a Gas City primitive, such as once the city's gc carries upstream's attach that asks the controller for the start.
---

# Gas City search for gc-helm's home page and its seats

A bare `gc-helm` on a terminal now opens a home page with four entries: the
po, mechanik, starting a conversation and returning to one. The change adds
this surface:

- A bare `gc-helm.sh` on a terminal hands the terminal to the conversation form
  on its home page. Without a terminal it keeps its usage and exit 2.
- `helm-svc form --home`, which opens the form on the home page. Esc on the
  start or the return screen goes back to it.
- `gc-helm.sh po [--reason "<what the sitting is for>"]`, which opens a sitting
  with the po from whatever state its seat is in and attaches.
- `gc-helm.sh mechanik`, which attaches to mechanik's session once it runs.

Gas City read at upstream main `9aaf32449` (gastownhall/gascity, fetched
2026-11-10). The city runs a fork build, `cb80c5354`, whose last common commit
with upstream is `9f807760c`. That build is not evidence of a primitive. It is
read only for the one fact the search turns on: it does not carry upstream's
attach change, `64ba02c02`.

## What was searched, and what each leaves

**A choice among sessions.** `gc session list --json` lists every open session
with its alias, template, state and whether a terminal is attached
(`sessionListJSONRow`, `cmd/gc/cmd_session.go`), and `gc session attach`
attaches to the one session it names (`newSessionAttachCmd`, `cobra.ExactArgs(1)`).
No `gc session` subcommand offers a choice among sessions, and upstream's
`go.mod` carries no terminal UI library. `gc dashboard` is a web page. So the
page is an entry of the terminal form the pack already ships (helm-svc form,
whose search is [specs/tk-po06sre/gas-city-search.md](../tk-po06sre/gas-city-search.md)),
and each entry runs a gc-helm verb, so the page itself starts, reads and writes
nothing.

**Opening a named seat's sitting with its prompt.** Four primitives start or
reach a session, and none covers the seat in every state:

- `gc session attach` at upstream asks the controller to start a session that
  is not running, the same wake `gc session wake` records, waits up to
  `--wait-timeout` for it to run, and attaches only a running runtime
  (`cmdSessionAttachWith`, from `64ba02c02`, #9011). That covers a seat whose
  last sitting ended, because a controller start hands the agent its prompt as
  its first message. The city's gc predates it: there the attach starts the
  runtime from its own process, so a po that a drain-ack ended under
  `wake_mode = "fresh"`, which keeps no conversation key, comes up as a new
  conversation whose prompt only the session-start hook could deliver, and
  `primeHookLiveManagedSession` (`cmd/gc/cmd_prime.go`) primes only a session
  whose record reads active, awake, creating or start_pending. That is the
  cause the po verb names, and the reason it starts such a seat itself. Once
  the city's gc carries `64ba02c02`, the po verb's start can reduce to the
  attach.
- `gc session wake` asks the controller to start a session, creating a
  configured named session that has none (`newSessionWakeCmd`,
  `cmd/gc/cmd_session_wake.go`). It attaches nothing and carries no message.
- `gc session nudge` to a managed session that is not running queues its
  message and asks the controller for the start, materializing a configured
  named session with no row (`queueManagedSessionNudgeWake` and
  `resolveNudgeTargetInStore`, `cmd/gc/cmd_nudge.go`). It attaches nothing. To
  a session still running, a draining one included, it delivers the message in
  place and asks for no start (`shouldQueueManagedNudgeWake`). The po verb uses
  it for the start, because it carries what the sitting is for, and waits out a
  drain before it nudges.
- `gc session submit` decides itself whether to wake, inject or queue a
  message, and attaches nothing (`newSessionSubmitCmd`).

So `gc-helm.sh po` composes them: it reads the seat's row, attaches to a
running or slept session, waits out a drain, and otherwise nudges and attaches
once the session runs. `gc-helm.sh mechanik` composes `gc session list` and
`gc session attach`, and waits while the controller starts the seat, since
mechanik is a named session the controller keeps running and is never nudged.

**Waiting for the start.** `gc session wait` registers a dependency wait that
wakes a session when beads close, which is a wait for the session, not for the
caller. A session row's state says when its runtime runs (`start-pending`,
`creating`, then `active`). The verbs poll that state, as engage already does
before its own attach, under the same bound, `GC_HELM_ENGAGE_WAIT_TIMEOUT`.
Upstream's attach `--wait-timeout` is the same wait, and arrives with
`64ba02c02`.

**Telling a slept seat from an ended one.** `gc session list --json` reads
`asleep` for both. A row the city's API serves carries the session's
lifecycle reason, the sleep reason for an asleep session, and `idle` for one
its idle limit put to sleep (`Reason` on `sessionListJSONRow`, set only on an
API-served read, from `sessionListReasonParts`, `cmd/gc/cmd_session.go`). The
po verb reads that reason. A local read carries none, so the verb takes a
slept seat for an ended one and starts a new sitting with its prompt, which
costs the slept sitting's conversation and never a prompt.
