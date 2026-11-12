---
name: Gas City search for Engage's seats and a po for each rig
description: The search the arch check asks for before the pack makes Engage the way in to gc-helm, with a People page that lists mechanik and each rig's po with the state of each one's session, adds the seat verbs gc-helm po --rig and gc-helm mechanik, and makes the po a named session of each rig. What Gas City ships for choosing among sessions, for a seat's state, for a session of each rig and the name an attach gives one, for a seat's name under whatever binding the city imports the pack with, and for opening a named seat's sitting with its prompt from any state, read at named upstream commits; why each seat verb is that attach alone; and the Gas City build the city runs, which carries the attach the verbs compose. Read it when checking whether a seat, its state or the po's rig scope can move onto a Gas City primitive, or which Gas City build the seat verbs need.
---

# Gas City search for Engage's seats and a po for each rig

Engage is the way in to `gc-helm`, and each rig has its own po. The change adds
this surface:

- A bare `gc-helm.sh` on a terminal runs engage, which opens the conversation
  form on starting a conversation. Without a terminal it keeps its usage and
  exit 2.
- The form's pages are tabs, and a People page beside starting a
  conversation and returning to one lists the seats: mechanik, and each rig's
  po by its rig's name and prefix, each with the state of its session. Once
  the form has left the terminal it runs the verb of the seat picked.
- `gc-helm.sh conversations --json` gains `seats`, which the People page
  reads: each seat, with the open session Gas City's session list holds under
  the name the seat's verb attaches to, or none. It gains `roster_unread` too,
  which says the agent roster that names the seats' sessions could not be read.
  It then lists no seat, still lists the conversations and the rigs, and
  exits 4 after the list.
- `gc-helm.sh po --rig <name>` and `gc-helm.sh mechanik`, each of which
  attaches the terminal to its seat's session from whatever state the seat is
  in. Each reads its seat's session name from the agent roster first, and
  refuses with exit 4 when the roster cannot be read or names no session for
  the seat, or several.
- The po is a named session of each rig: its agent and its `[[named_session]]`
  in `pack.toml` take `scope = "rig"`, as the witness and the refinery do.

Gas City read at upstream main `8b1d799b8` (gastownhall/gascity, fetched
2026-11-10), the attach's paths read again at upstream `f14384642` on
2026-11-11, the named session's rig scope read at upstream `6bd609f5bf` on
2026-11-11, and a seat's state, a seat's name and a partial answer read at
upstream `6bd609f5bf` on 2026-11-12. The city runs a fork build, `36ad5186a`,
whose last common commit with upstream is `f14384642`. That build is not
evidence of a primitive. It is
read only for what the city runs (*The deployed version*, below).

## What was searched, and what each leaves

**A choice among sessions.** `gc session list --json` lists every open session
with its alias, template, state and whether a terminal is attached
(`sessionListJSONRow`, `cmd/gc/cmd_session.go`), and `gc session attach`
attaches to the one session it names (`newSessionAttachCmd`, `cobra.ExactArgs(1)`).
No `gc session` subcommand offers a choice among sessions, and upstream's
`go.mod` carries no terminal UI library. `gc dashboard` is a web page. So the
choice among the seats is a page of the terminal form the pack already ships
(helm-svc form, whose search is
[specs/tk-po06sre/gas-city-search.md](../tk-po06sre/gas-city-search.md)), and
the form runs a gc-helm verb for the seat picked, so the form starts and writes
nothing for a seat itself.

**A seat's state.** `gc session list --json` covers it. Each row carries the
session's alias, its state as Gas City's lifecycle names it, and whether a
terminal is attached (`sessionListJSONRow`, `cmd/gc/cmd_session.go`, at
`6bd609f5bf`). The list holds the open sessions only (`sessionListInfos`), so a
configured named session with no open session, such as a po that has never run,
has no row, and the attach materializes it
(`resolveSessionIDMaterializingNamed`). So `seats` reads the list once, the read
`conversations` already makes for the live sittings, and takes for each seat the
open session whose alias is the name the seat's verb attaches to, or none, with
Gas City's state word as it stands. Which seats there are is the pack's: the
seat verbs' names, and a po for each rig `gc rig list` gives but the city's HQ,
as `ExpandGenericRigNamedSessions` stamps one for each of `cfg.Rigs`, each
listed once the agent roster names its session (*A seat's name*, below). Gas City
also classifies each configured named session, `gc status` printing its state,
or `reserved-unmaterialized` while it has no session (`namedSessionStatusForCity`
and `cityStatusSnapshot.NamedSessions`, `cmd/gc/city_status_snapshot.go`), and
it leaves part of the need: `gc status --json` carries no named session
(`StatusJSON`, `cmd/gc/cmd_citystatus.go`), the text runs an identity of 24
characters or more into its status (`%-24s%s`), and neither says whether a
terminal is attached. The supervisor API's status carries the same
classification as JSON (`StatusBody.NamedSessionDetails`,
`named_session_details`, `internal/api/huma_types_patches.go`), with no
attached either, and the form reads only through gc-helm's verbs, which read
through the gc CLI.

**A session of each rig, and the name an attach gives one.** Gas City ships
it. A `[[named_session]]` with `scope = "rig"` and no `dir` is a generic
declaration, which config composition stamps once for each of the city's rigs
after packs are expanded (`ExpandGenericRigNamedSessions`,
`internal/config/config.go`, called from `internal/config/compose.go`, at
`6bd609f5bf`). A stamped session's identity is its rig, a slash and its
binding-qualified name (`NamedSession.QualifiedName` and
`NamedSession.IdentityName`), and the binding is the key the city imports the
pack under, so a rig's po is `<rig>/<binding>.po`. The city imports the pack as
gc-toolkit, and lists the same shape for the pack's witness and refinery
(`gc session list`, `gc-toolkit/gc-toolkit.witness`). `gc session attach
<rig>/<binding>.po` names that identity: the attach resolves its target
through `resolveSessionIDMaterializingNamed` (`cmd/gc/session_resolve.go`),
which finds the configured named session the target names
(`session.FindNamedSessionSpecForTarget` and `config.FindNamedSession`) and
materializes it when it has no open session. A rig-scoped agent's prompt
renders its rig's name, root and bead prefix (`RigName`, `RigRoot` and
`IssuePrefix` of `PromptContext`, `cmd/gc/prompt.go`, the prefix from
`findRigPrefix`), so the po's reads name its own rig with no lookup of their
own. Its working directory is a worktree of its rig, which the pack's
`worktree-setup.sh` makes at the session's `pre_start`, as it makes the
witness's, so the po's bare `gh` and `git` resolve to its rig. The pack adds no
session of its own for a rig: the po is the platform's rig-scoped named
session.

**A seat's name.** `gc agent list --json` covers it. It lists each agent of the
city's resolved config with its `name`, its `dir` and its `qualified_name`,
which is the dir, a slash and the binding-qualified name (`AgentListItem` and
`agentListItems`, `cmd/gc/cmd_agent.go`, and `Agent.QualifiedName`,
`internal/config/config.go`, at `6bd609f5bf`). A named session takes the name
its stanza gives it, or else its template's (`NamedSession.IdentityName`), and
`pack.toml` gives the seats' stanzas none, so a seat's identity is the
qualified name of the agent of its template (`NamedSession.TemplateQualifiedName`):
the one agent named `mechanik` with no dir, and for a rig's po the one agent
named `po` whose dir is the rig. Both verbs and `seats` take it from there, as
`queue-priority.sh` finds its pool, and `seats` reads the roster `conversations`
already reads for each rig's converse, so the page makes no new call. No agent
of the template there, or several, leaves the seat unnamed: the verb refuses
and says which, and `seats` leaves the seat out. A roster that cannot be read
names no seat. The verbs then refuse with a re-run. `conversations --json`
lists no seat, sets `roster_unread` and exits 4 after the list, as it does for
a store that did not read. The conversations do not need the roster, and the
rigs read it fail-open, as converse-capability.sh reads it for every caller, so
the return list and the start page still list, and the People page says the
seats did not read. A seat listed with no session
while its name is unknown would claim a state the read never saw.

Gas City reports an answer whose parts did not all read with `partial` and
`partial_errors`: a flag for the whole answer, and a message for each read that
failed (`StatusJSON.Partial` and `StatusJSON.PartialErrors`,
`cmd/gc/cmd_citystatus.go`, and `SessionList.Partial` and
`SessionList.PartialErrors`, `internal/api/decode_session_list.go`, at
`6bd609f5bf`). That leaves part of the need. The People page has to know that
the seats in particular did not read while the return list shows its rows, and
a flag for the whole answer would leave the form to find which part failed in a
message. `conversations --json` already gives the part that did not read a key
of its own, as `unread` names each rig whose store did not, so `roster_unread`
is a key of that kind.

Three other primitives were read for the name, and each leaves part of it.
`gc session attach` also takes a bare name, which matches a configured named
session's name without its binding (`session.ResolveNamedSessionSpecForConfigTarget`
and `namedSessionBareName`, `internal/session/named_config.go`), but a
rig-scoped one only when the call stands in that rig, which `currentRigContext`
(`cmd/gc/cmd_agent.go`) reads from `GC_DIR` and then the working directory. A
person's terminal names no rig there, and an agent's `GC_DIR` can name another
rig, and the People page still needs the name itself to find the seat's
session, because a session list row names its session only by binding-qualified
names (`sessionListJSONRow`'s `template`, `alias` and `agent_name`). The
supervisor API's status lists each configured named session's identity
(`StatusNamedSessionDetail.Identity`) with no template or rig to say which is a
seat. `gc config show --json` drops a named session's binding
(`NamedSession.BindingName` carries `json:"-"`).

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
the seat's name, read from the agent roster, and nothing else: it reads no
session state, sends no nudge, records no wake of its own and runs no wait. The
verb adds only what the attach does not print, the line that names how to
return once the terminal comes back and the re-run once an attach fails, and
`po` checks that its rig is one of the city's configured rigs and runs. `gc rig list` lists the city's HQ, the city
itself, beside its rigs (`RigListItem.HQ`, built ahead of the `cfg.Rigs` loop in
`cmd/gc/cmd_rig.go`), and `ExpandGenericRigNamedSessions` stamps a session only
for each of `cfg.Rigs`, both at `6bd609f5bf`, so the HQ has no po. Gas City starts no session in a
suspended rig.

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

The attach carries no message, so neither verb carries one, and the form takes
no question for a seat. The operator says what a sitting is for in the sitting.

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
above. `cmd/gc/cmd_session.go` is the same at `f14384642` and `6bd609f5bf`, and
the fork's commits there add a nudge's bead reference and `gc session
release-name`, leaving `sessionListJSONRow` and `sessionListInfos` as upstream
has them, so the city's `gc session list --json` gives each open session's
alias, state and attached as the seats read them. Read on 2026-11-12, it lists
mechanik's session under the alias `gc-toolkit.mechanik`, active with a
terminal attached. The city's sessions show the rig-scoped named session's
identity on that build: the pack's witness and refinery run as
`<rig>/gc-toolkit.witness` and `<rig>/gc-toolkit.refinery` in every rig. The
fork changes `cmd/gc/cmd_agent.go` only in which config warnings a command
prints, and none of the naming functions above, and its `gc agent list --json`,
read on 2026-11-12, lists mechanik with the name `mechanik`, no dir and the
qualified name `gc-toolkit.mechanik`, and each rig's agents with the rig as
their dir. So each seat verb, its name, and a po for each rig, run on the
city's gc as this page reads it.
