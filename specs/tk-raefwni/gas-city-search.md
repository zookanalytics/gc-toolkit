---
name: Gas City search for the note command
description: The Gas City and bd primitives read for `gctk bead note`, the one command an agent puts a note on a bead with, which with --notify tells each session working the bead; what each covers at a named upstream commit, how a nudge reaches a busy Claude Code or Codex session on the city's releases, and the gap the command fills. Read it to review the command's surface, or before changing how a note is written, or how it finds a session or reaches one.
---

# Gas City search for the note command

The run half of the search was read on 2026-11-23 at `gastownhall/gascity` main
dfd5200c3e. The note-writing half was read on 2026-11-25 at `gastownhall/gascity`
main 887a253144 and at `github.com/steveyegge/beads` v1.3.4, the version that
commit's go.mod pins. The 2026-11-23 delivery measurements ran on the city as it
stood that day: gc 1.4.3, built from the city's fork at 6589a7df45, Claude Code
2.1.330 and codex-cli 0.167.2. Each behavior they show is cited to the upstream
code that has it. What was read from source is kept apart from what was
measured: the Codex delivery below was read, not measured.

## The need

Agents put notes on beads all the time: an outcome, evidence, a placement, a
ruling. Some of those notes change what the work on the bead should do, such as
a premise that changed or a requirement added or dropped. When work on the bead
is running, the session doing it must have such a note before it builds further
on what the note overrules, and a session that takes the work later must find
it too.

Whether anyone is working the bead is not the writer's to judge. Twice a sitting
wrote such a change on the bead's notes, and the session doing the work read it
only at its next read of the notes, after it had built on the old premise. Both
cases are in the work bead's description. In the second, the sitting's own check
read the bead open and unassigned while a polecat worked its run: a bead whose
work runs on a poured workflow names no session. tk-raefwni read open, with no
assignee, while this bead's first build held its run's load-context and
implement steps.

## What was searched: writing the note

- **bd's own append.** `bd note <id> <text>` appends a note to a bead's notes,
  "Shorthand for 'bd update <id> --append-notes "text"'" (`noteCmd` in
  `cmd/bd/note.go`, beads v1.3.4). It resolves the bead, appends the text in one
  write and returns. Nothing in it reads who is working the bead or tells
  anyone, so a note written through it reaches a running session only at that
  session's next read of the notes. The command's write is this append, made as
  `gc bd update <bead> --append-notes <note>` in the store gc routes the bead
  to, so a note written without `--notify` is the write an agent made before.
- **`gc mail send --notify`**, whose alias is `--nudge`. It sends a message bead
  to a recipient and then nudges that recipient for a turn (`cmdMailSendJSON`
  and `newMailNudgeFunc` in `cmd/gc/cmd_mail.go`, gascity 887a253144). It
  addresses a recipient the sender names, so the sender must already know who is
  working the bead, which is the judgment this command takes from the writer.
  Its message lands in the recipient's mail, not on the bead whose work it
  changes, where whoever takes the work later reads. The command takes its
  flag's name from it: a write, then a nudge to whoever should have it at once.

## What was searched: finding who works the bead

- **The bead's own assignee.** A claim or an assignment on the bead itself
  names the session it was delivered to, and the command reads it first. A
  graph.v2 run claims its steps and leaves the bead open and unassigned, so the
  assignee covers only a bead claimed or assigned itself.
- **`gc convoy delete-source <bead>`**, run without `--apply`, which only
  previews (`gc convoy delete-source` in `docs/reference/cli.md`). It finds the
  live workflow roots sourced from a bead by their `gc.source_bead_id`
  (`ListLiveRoots` in `internal/sourceworkflow/sourceworkflow.go`). A run Gas
  City pours over an input convoy names the convoy in `gc.input_convoy_id` and
  carries no `gc.source_bead_id`, so the preview misses this city's runs: on
  tk-raefwni, with its run live, it printed `matched_roots=0`.
- **The run API.** `GET /v0/city/{cityName}/runs` takes a limit and no bead
  (`RunsListInput` in `internal/api/huma_types_runs.go`), and
  `GET .../runs/{run_id}/steps` gives each step's assignee once the run is known
  (`RunStep`). No route goes from a bead to its runs. The pack's run link does:
  it follows the convoy that tracks the bead to the roots poured over it
  (`waits.LiveRunsOf`, which copies `assets/scripts/run-lib.sh`), and
  `waits.RunHolders` reads the assignees of each run's members. The command
  composes those.
- **Gas City's run cancel**, `POST /v0/city/{cityName}/runs/{run_id}/cancel`,
  finds the sessions that hold a run's members in order to interrupt them, and
  ends the run. The work must go on, so it is not the act.
- **`gc session list --json`** (`sessionListJSONRow` in
  `cmd/gc/cmd_session.go`). It lists every session that has not closed, by its
  id, session name and alias, with the provider it runs, which is empty for a
  session that runs a command of its own in place of an agent, as the
  control-dispatcher does. It names no claim. It covers telling a live holder
  from one that has gone and finding a session that has no agent to read a
  message, and the command reads it once.
- **`gc session nudge`** (`gc session nudge` in `docs/reference/cli.md`,
  `sessionNudgeOpPolicy` in `cmd/gc/cmd_nudge.go`). Its immediate mode steers,
  which Gas City's API schema defines as delivery "into the running turn, where
  the runtime can steer" (`docs/reference/schema/openapi.json`), and falls back
  to the turn's boundary on a runtime that cannot. Its wait-idle and queue modes
  deliver at the boundary. The command composes the immediate mode as
  `gc session nudge --delivery immediate <session> <message>`, with only flags
  `newSessionNudgeCmd` registers upstream: `--delivery`, `--json` and `--key`,
  at 887a253144 and again on 2026-11-26 at main d38ec7842f. The city's build
  also carries `--reference-bead` from its fork, which collapses repeated
  queued nudges about one bead. Gas City as shipped has no such flag, so the
  command does not pass it, and the nudge it prints to send by hand does not
  either.
- **`gc session submit --intent interrupt_now`** interrupts the running turn and
  then delivers the message. It cuts short the tool call the work is running,
  and the work is meant to go on, so it is not the act.
- **`gc mail send`** without `--notify`. The hooks Gas City installs read mail
  into a session with `gc mail check --inject` when a prompt is submitted, so a
  session working through a long turn reads mail only once something is typed
  into it.

## How a nudge reaches a busy session

- **Claude Code, immediate, measured.** This session nudged itself mid-turn with
  `gc session nudge --delivery immediate` at 10:59:11Z on 2026-11-23. Claude
  Code queued the typed text at 10:59:13.7Z and handed it to the model with the
  next tool result at 10:59:15.8Z, inside the same turn (the transcript's
  `queue-operation` and `queued_command` records). Gas City types it at once,
  since a plain Enter does not interrupt a Claude Code turn
  (`submitSequenceInterrupts` in `internal/runtime/tmux/tmux.go`). The typed
  message also fired the prompt-submit hooks, whose `gc nudge drain --inject`
  brought in two reminders queued earlier in the turn.
- **Claude Code, wait-idle, the default, measured.** Gas City queues a wait-idle
  nudge to a busy Claude Code session (`deliverSessionNudgeLegacy` in
  `cmd/gc/cmd_nudge.go`), and its queue types the nudge once the pane has been
  quiet for three seconds (`defaultNudgePollQuiescence`). One sent to this
  session mid-turn printed `Queued nudge ... (the session never reached an idle
  boundary; the queued dispatcher delivers it)` and was still pending, never
  attempted, after a 40-second tool call (`gc nudge status`), when it was
  dropped. Later in the same turn the queue typed four other reminders while
  the model composed a long reply, and Claude Code handed them over 37 seconds
  after that, at the next tool result. So a queued nudge reaches a working
  session at whatever pause the queue finds, which the work does not schedule.
- **Claude Code, size, measured.** Typed into Claude Code's input box with
  `tmux send-keys -l`, as gc types a nudge, a line of 800 characters stayed
  typed text, and lines of 801 and 1000 characters became a `[Pasted text #N]`
  paste. This ran in a private tmux server with no model call. A model reads
  pasted text as material whose instructions it follows only where its user's
  own words ask, so a nudge stays within 800 bytes.
- **Codex, read from source, not measured.** Gas City types into a Codex pane
  only when its composer reads idle, because Codex's submit keys lead with
  Escape, which cancels a running turn (`nudgeSubmitKeySequences` and
  `refuseInterruptingSubmitWhileBusy` in `internal/runtime/tmux/tmux.go`,
  `awaitIdleComposerBeforeTyping` in
  `internal/runtime/tmux/submit_turn_guard.go`). A nudge of either mode to a
  Codex session running a turn is queued (`runtime.ErrSessionBusy` in
  `deliverSessionNudgeLegacy`), and the queue delivers it once the turn ends.
  The supervisor's log holds this city's cases: nudges to Codex polecats
  deferred on 2026-11-13 and 2026-11-17 because each session "is still running
  a turn and its submit keys (Escape Enter) would interrupt it". No Codex turn
  was probed, since no Codex polecat ran on either day of the build and a probe
  session would run its role's work.

## Why the command

One command writes every note an agent puts on a bead, so no writer picks a
command by whether the work on the bead is running. Without `--notify` it is
bd's append and nothing more: it reads no run, no session and no row of the
bead. For a note that changes the work, no primitive goes from a bead to the
sessions working it, and the pieces that cover each part leave the act's order
to a caller. With `--notify` the command composes the pack's run link, the
session list and the immediate nudge after the append, and adds what they leave
out:

- the note lands first, as written, so the nudge points at durable state, and a
  note that does not land tells no one. The command adds no stamp, so each line
  a reader parses, such as a conversation's `holding:` line or a `## Current
  state` block, keeps the shape its writer gave it;
- the holders come from the bead's assignee and from each live run's members,
  matched to sessions by the forms a claim writes (`gascity.Named`, which
  `gctk bead takeaway` reads too);
- a session with no agent, and the session writing the note, take no nudge;
- a closed bead has no work on it to tell, and a bead nobody works says the
  note waits for whoever picks it up;
- the nudge is one typed line within 800 bytes that names the bead and says
  its notes hold the note whole;
- the exit tells a note that reached each session working the bead from one
  that landed but whose nudges may not have, with the nudge to send by hand.

## The command, run on the city

On 2026-11-23, run from a shell with this session's identity unset, the first
build's `gctk bead revise tk-raefwni` found this bead's polecat through its
run's implement step while the bead read open and unassigned. It appended the
note at 11:18:05Z, and Claude Code handed the nudge to the model at 11:18:12Z
with the result of the call that sent it.

On 2026-11-25 the rework's build ran twice on tk-raefwni from a shell with the
identity unset, while the bead read blocked with no assignee and the review run
on its PR (tk-zf88rdo) held its rule-and-repair step in this session:

- `gctk bead note tk-raefwni "<probe>"` printed `noted tk-raefwni` and exited 0
  in half a second, and no nudge reached any session.
- `gctk bead note --notify tk-raefwni "<probe>"` printed `noted tk-raefwni`,
  then `sent to lx-wisp-qgkjrj: Nudged lx-wisp-qgkjrj`, found through the run's
  step. The call ran from 19:52:59Z to 19:53:09.9Z. Claude Code queued the typed
  nudge at 19:53:07.5Z and handed it to the model at 19:53:09.97Z with the
  result of that call, inside the running turn.

Both probe notes say they ask for no change to the work.
