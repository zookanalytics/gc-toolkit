---
name: Gas City search for gc-helm's home page and its seats
description: The search the arch check asks for before the pack adds gc-helm's home page (a bare gc-helm on a terminal, helm-svc form --home) and the seat verbs gc-helm po and gc-helm mechanik. What Gas City ships for choosing among sessions and for opening a named seat's sitting with its prompt from any state, read at named upstream commits; why each seat verb is that attach alone; and the Gas City build the city runs, which carries the attach the verbs compose. Read it when checking whether the home page or a seat verb can move onto a Gas City primitive, or which Gas City build the seat verbs need.
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
2026-11-10), and the attach's paths read again at upstream `f14384642` on
2026-11-11. The city runs a fork build, `36ad5186a`, whose last common commit
with upstream is `f14384642`. That build is not evidence of a primitive. It is
read only for what the city runs (*The deployed version*, below).

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
`gc session attach` covers it. It attaches to a running session as it stands,
and refuses one with a stop pending on its record (`startRefusal`,
`internal/session/chat.go`), such as a po whose drain-ack stop the controller
has begun. While the city's controller runs, it asks the controller to start a
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

One start is the attach's own while the controller runs, after a stop that
completes inside the attach. A seat that runs at the attach's own check
(`a.sp.IsRunning` in `sessionAttach.run`) is attached
through the session's handle, whose `Manager.Attach`
(`internal/session/manager.go`) starts the runtime from the attach's process
when it has stopped since that check and no stop is pending on the seat's
record (`startRefusal` and `ensureRunningOn`, `internal/session/chat.go`). So a
po whose sitting ends in the span between the check and the attach is started
by the attach, not the controller. It still comes up with its prompt. The
session's handle takes its runtime from the worker factory's resolver, which
renders the agent's prompt into the start's startup nudge and marks the launch
as having delivered it (`sessionFromRecord`, `internal/worker/factory.go`,
`resolvedWorkerRuntimeWithConfigAndMetadata`, `cmd/gc/worker_handle.go`, and
`startupPromptCity.applyTo`, `cmd/gc/session_startup_prompt.go`, from
`4a4921a60`, #8465), as for an attach while no controller runs. The pack has no
primitive that moves this start to the controller. `--no-start` attaches
through the runtime-only handle, which never starts a seat, so a seat that is
not running would need the pack's own start again, and a state read before the
attach leaves a wider span of the same kind. The comment on `sessionAttach.run`
says a viewer never starts a runtime while the controller runs, and upstream
finding tk-dmqcnln records this start against it.

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

## The deployed version

The city's gc is the fork build `36ad5186a`, read on 2026-11-11, whose last
common commit with upstream is `f14384642`, so it carries `64ba02c02` and
`4a4921a60`. Its `gc session attach --help` documents the controller's start,
`--wait-timeout` and `--no-start`. The fork's own commits in the files the
attach runs through (`85751fbe1`, `5028a000f`, `51055e7d3` and `b9ffe10ea`)
change other session commands, a nudge's bead reference, a transcript lookup
and what a start records about a task's work directory, and none of the paths
above. So each seat verb runs on the city's gc as this page reads it.
