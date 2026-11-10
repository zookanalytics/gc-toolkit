---
name: Gas City search for gc-helm's home page and its seats
description: The search the arch check asks for before the pack adds gc-helm's home page (a bare gc-helm on a terminal, helm-svc form --home) and the seat verbs gc-helm po and gc-helm mechanik. What Gas City ships for choosing among sessions and for opening a named seat's sitting with its prompt from any state, read at a named upstream commit; why each seat verb is that attach alone; and the deployed-version prerequisite the change waits on, because the city's gc predates the attach it composes. Read it when checking whether the home page or a seat verb can move onto a Gas City primitive, or what the change waits on before it lands.
---

# Gas City search for gc-helm's home page and its seats

A bare `gc-helm` on a terminal now opens a home page with four entries: the
po, mechanik, starting a conversation and returning to one. The change adds
this surface:

- A bare `gc-helm.sh` on a terminal hands the terminal to the conversation form
  on its home page. Without a terminal it keeps its usage and exit 2.
- `helm-svc form --home`, which opens the form on the home page. Esc on the
  start or the return screen goes back to it.
- `gc-helm.sh po` and `gc-helm.sh mechanik`, each of which attaches the
  terminal to its seat's session from whatever state the seat is in.

Gas City read at upstream main `8b1d799b8` (gastownhall/gascity, fetched
2026-11-10). The city runs a fork build, `cb80c5354`, whose last common commit
with upstream is `9f807760c`. That build is not evidence of a primitive. It is
read only for the one fact the change's timing turns on: it does not carry
upstream's attach change, `64ba02c02`.

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

**Opening a named seat's sitting with its prompt, from any state.**
`gc session attach` covers it, all but one window inside the attach that the
next paragraph names. It attaches to a running session as it
stands. While the city's controller runs, it asks the controller to start a
session whose runtime is not running, recording the wake `gc session wake`
records, waits up to `--wait-timeout` (two minutes by default) for the session
to run, and attaches through a runtime-only handle that never starts the
runtime itself (`cmdSessionAttachWith`, `sessionAttach.run` and
`attachOnceControllerStarts`, `cmd/gc/cmd_session.go`, from `64ba02c02`,
#9011). A configured named session with no open session is materialized first
(`resolveSessionIDMaterializingNamed`). The controller's start hands the agent
its prompt as its first message, so a po whose last sitting ended, one whose
sitting slept, and one with no session yet each come up prompted, and a wake
the controller will not act on, or a start that has not run within the wait,
fails the attach with its reason. Each seat verb is therefore that attach on
the seat's name and nothing else: it reads no session state, sends no nudge,
records no wake of its own and runs no wait. The verb adds only what the attach
does not print, the line that names how to return once the terminal comes back
and the re-run once an attach fails.

The window is a stop that completes inside the attach. A seat that runs at the
attach's own check (`a.sp.IsRunning` in `sessionAttach.run`) is attached through
the session's handle, whose `Manager.Attach` (`internal/session/manager.go`)
starts the runtime from the attach's process when it has stopped since that
check and no stop is pending on the seat's record (`startRefusal` and
`ensureRunningOn`, `internal/session/chat.go`). So a po whose sitting ends in
the span between the check and the attach comes up without the controller's
start. The pack has no primitive that closes it. `--no-start` attaches through
the runtime-only handle, which never starts a seat, so a seat that is not running
would need the pack's own start again. A state read before the attach leaves a
wider window of the same kind, and an attach with `--no-start` followed by a
plain attach once it refuses leaves this one in the second call. The window is
Gas City's to close, and it is recorded as upstream finding tk-dmqcnln.

The po wakes fresh (`wake_mode = "fresh"`), and the controller's start clears a
fresh session's key before it starts it (`preWakePatch`, `cmd/gc/session_wake.go`,
and `PreWakePatch`, `internal/session/lifecycle_transition.go`), so a po
sitting that slept comes back as a new sitting. The pack's docs and the po's
prompt say so.

The attach carries no message, so neither verb carries one. The operator says
what a sitting is for in the sitting.

The other primitives were read for the same need, and each leaves part of it:
`gc session wake` asks the controller to start a session and attaches nothing
(`newSessionWakeCmd`, `cmd/gc/cmd_session_wake.go`); `gc session nudge` to a
managed session that is not running queues its message and asks the controller
for the start, attaching nothing, and to a session still running, a draining one
included, delivers it in place (`queueManagedSessionNudgeWake` and
`shouldQueueManagedNudgeWake`, `cmd/gc/cmd_nudge.go`); `gc session submit`
decides itself whether to wake, inject or queue a message and attaches nothing
(`newSessionSubmitCmd`).

## The deployed-version prerequisite

The city's gc, the fork build `cb80c5354`, predates `64ba02c02`. Its
`gc session attach` has no `--wait-timeout` or `--no-start`, and it starts a
session that is not running from its own process whether or not a controller
runs (`Manager.Attach`, `internal/session/manager.go`, and `ensureRunningOn`,
`internal/session/chat.go`). There a po whose last sitting a drain-ack ended
keeps no session key, so the attach starts a new conversation with no first
message, and `gc prime --hook` primes only a session whose record reads active,
awake, creating or start_pending (`primeHookLiveManagedSession`,
`cmd/gc/cmd_prime.go`), so that sitting comes up with no prompt. That is a
deployment lag, not a missing primitive. The change therefore lands only once
the city's gc carries `64ba02c02`, which arrives with the next upstream sync of
the fork: a human gate on the change's anchor holds its merge until the synced
build runs. The verbs pass no flag to the attach, so either build accepts the
call, and the gate alone decides when the verbs ship.
