---
name: Gas City search for a session title its terminal shows
description: The search the arch check asks for before gctk adds `gctk session title`. What Gas City, the packs it publishes, Claude Code and Codex ship for giving a session a title that its record, its pane and an attached client's tab all show, for keeping the pull request a session is about on its record, and for typing into a session without landing on a person's draft, read at named upstream commits, and why the pack composes gc session rename and gc session nudge behind a read of the input box of its own. Read it when checking whether the command can move onto a Gas City primitive.
---

# Gas City search for a session title its terminal shows

A converse sitting names itself in its prep step. Until this change the name
reached only Gas City's session record, so the sitting's pane and the
operator's tab showed the title Claude Code generates for itself. This change
adds `gctk session title --subject <bead-id> --pr <n> --topic <words>
[--session <id-or-alias>]`. The title is `<subject> #<n> — <topic>`, and an
item not given is left out of it. The command renames the session in Gas City,
then types `/rename <title>` into the session's input box, once a read finds
the box empty. Each converse template also sets `set-titles on` with
`set-titles-string '#T'` on the sitting's own tmux session, so tmux hands the
pane title to the attached client. A gctk command is operational surface, so the arch check asks what Gas
City already ships for the need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships the two calls the command makes, `gc session rename` and `gc
session nudge`, and the command composes them. Nothing in Gas City puts a
session's title on its terminal, and its nudge types onto whatever the input
box holds. The command's own part is the read of the input box before the
nudge. Gas City has that reader too, inside its tmux runtime, but no command or
endpoint reaches it, so the pack ports it.

## The need

- A title stated once reaches the session's record, which `gc session list` and
  the board read, and the agent's own session name, which Claude Code and Codex
  draw as the terminal title.
- The title names the pull request the session is about, when there is one,
  beside the bead id, in each of those places.
- The title reaches the pane while the sitting's turn runs, within seconds of
  the prep step, because the operator's next message can be many minutes away.
- The typing never lands on a message the operator is writing.
- It works for each provider a converse template runs: Claude Code for
  `converse-opus` and `converse-fable`, and Codex for `converse-codex`.
- Nothing polls. The title is pushed when the sitting names itself.

## Where the search looked

Each was read on 2026-11-06:

- Gas City at upstream main `9f807760c` (gastownhall/gascity): its CLI
  reference and other docs, its engineering docs, the `core` pack it bundles,
  and its source.
- Every pack in `gastownhall/gascity-packs` at main `796d7ecd73cf`.
- Codex's source at openai/codex `rust-v0.164.0`, the release the city runs.
- Claude Code 2.1.318, the build the city runs, through sitting tk-vu6faf2's
  probes, recorded on tk-a8k8dpw's notes.
- Gas City at upstream main `bfd72756e`, for the pull request: its session
  record, its session commands and its session API.

The search looked for a session title, a rename, a pane title, tmux's
set-titles, a terminal-title write, a title passed to a provider at launch,
any read of a session's input box, and a field, label or metadata key on the
session record that holds a pull request or the bead a session is about.

## What Gas City ships near the need

### The session's title

[`gc session rename`](https://docs.gascity.com/reference/cli#gc-session-rename)
renames a session, and
[`gc session new`](https://docs.gascity.com/reference/cli#gc-session-new) takes
`--title` and `--title-hint`. Both write the session bead and nothing else.
`cmdSessionRename` (cmd/gc/cmd_session.go) calls `SessionHandle.Rename`
(internal/worker/handle_lifecycle.go), which calls `Manager.Rename` and
`UpdatePresentation` (internal/session/manager.go). For a title,
`UpdatePresentation` is one bead update: only an alias change reaches the
running runtime, through `SyncRuntimeAlias`. `--title-hint` runs the
provider's CLI once to write a title, and `generateAndSetTitle`
(internal/api/title_generate.go) puts that on the bead too. The provider is
launched with no title, and the tmux runtime sets no pane title and no
set-titles. A
search of `internal/runtime` for `title` finds ACP tool titles and
`programstatus`, which records what a program reports about itself for
observers to read.

No pack in gascity-packs titles a session. Its hits for rename are about
renaming files.

### The session's pull request

The session record has no field for a pull request. At upstream main
`bfd72756e`, `session.Info` (internal/session/manager.go) carries a title and an
alias for a person to read, and `UpdatePresentation` writes only those two.
`ValidateTitle` (internal/session/names.go) refuses only a blank title, so a
title can carry `#<n>`. The record's fields that name a bead are the
controller's own. `TriggerBeadID` is the bead whose demand started a pool
session, and `CurrentClaimBeadID` is the work the session claimed, which for a
converse sitting is its conversation, not the bead the conversation is about.
The record's labels serve the controller's identity checks.
[`gc session list`](https://docs.gascity.com/reference/cli#gc-session-list)
shows the title in its table and in each `--json` row (`sessionListJSONRow` in
cmd/gc/cmd_session.go), and shows none of those fields, labels or metadata.
The table cuts its TITLE column at 30 bytes (`sessionListTitleOf`), so a
number before the topic leaves less of the topic there.

The session API takes metadata from a client, but not for this need.
`POST /v0/city/{cityName}/sessions` and
`PATCH /v0/city/{cityName}/session/{id}` write only `real_world_app_*` keys,
which Gas City calls "the session metadata family external clients own"
(`clientSessionMetadataPrefix` and `refuseNonClientSessionMetadata` in
internal/api/huma_handlers_sessions_command.go). The session response shows
those keys and `template_overrides`, and no other key (`filterMetadata` in
internal/api/handler_sessions.go). No gc command writes them. The list, the
pane and the tab show none of them. A pull request kept there would reach none
of the places the title is read, and it would sit under a name that belongs to
another client.

So the command puts the number in the title, which the record, the pane and
the tab all show.

### Typing into the session

[`gc session nudge`](https://docs.gascity.com/reference/cli#gc-session-nudge)
"Send[s] text input to a running session via the runtime provider ...
equivalent to typing the message into the session's terminal", and
`--delivery immediate` types into a running turn when the runtime can. The
command composes it to type `/rename <title>`. Claude Code runs a typed
`/rename` itself, with no model turn, and sitting tk-vu6faf2 saw a pane title
change within 2 seconds of an immediate nudge, mid-turn. Codex's `/rename`
renames the thread, takes its argument inline and runs during a turn
(`SlashCommand::Rename` in codex-rs/tui/src/slash_command.rs). With
`terminal_title` unset, Codex draws `activity`, `thread-name` and
`project-name` in the terminal title (codex-rs/config/src/types.rs). So the
same nudge titles a Codex sitting's terminal, though no Codex sitting has run
it yet.

The nudge does not keep a draft safe. `nudgeSession`
(internal/runtime/tmux/tmux.go) clears the input box before it pastes only
while no client is attached. While one is, it pastes onto what the box holds,
because a person may be mid-keystroke, and then sends the submit key, so a
half-written message goes out with the nudge's text joined to it. The
pending-interaction guard it runs first refuses a permission prompt or a
question, not a draft.

### Reading the input box

[`gc session peek`](https://docs.gascity.com/reference/cli#gc-session-peek)
prints a session's recent output, as plain text. Both providers draw a
placeholder dim in an empty input box. Claude Code draws "Try ..." and its
prompt suggestions, and Codex draws an example prompt whenever its composer is
empty (`placeholder_text` in codex-rs/tui/src/bottom_pane/chat_composer.rs). In
plain text the placeholder reads as typed text, so a read through peek would
take an empty Codex composer for a draft every time.

Gas City reads the box itself before it clears or resubmits one. That code is
`captureInputLines`, `stripDimText`, `readClaudeInput` and
`paneShowsDrainedComposer` (internal/runtime/tmux/composer_clear.go and
tmux.go), and it captures with `-e`, so dim text can be dropped. No command
reaches it, and no endpoint does. The session endpoints the API serves are
agents, close, kill, messages, ops, pending, permission-mode, pin, rename,
reset, respond, stop, stream, submit, suspend, transcript, turn, unpin and
wake. `pending` is a pending permission prompt or question, not the box's
text. Go's internal-package rule keeps gctk from importing the reader, so
`services/gctk/internal/composer` ports it and names each symbol it follows.

To find the pane the box is in, the command lists the session's panes with
Gas City's own agent-pane marker (`TmuxAgentPaneMarkerFormat` in
internal/runtime/tmux_agent_pane.go), as `agentInputTarget` does. To know
whether the session runs Claude Code or Codex, it reads the session bead the
way `ProviderFamilyFromMetadata` (internal/session/submit.go) does:
`builtin_ancestor`, then `provider_kind`, then `provider`.

### The title on the attached client

tmux's `set-titles` is a session option, off by default and off in the city.
With it on and `set-titles-string '#T'`, tmux gives the attached client's
terminal the pane title, which is the terminal title the agent draws. Gas City
already runs a template's `session_live` after every start of a session, with
`GC_TMUX_SOCKET` naming the city's server, and the converse templates already
set `detach-on-destroy` there. The new entry sits beside that one.

## What a Gas City change would let the pack drop

The input-box read is the one part Gas City could own. Either of these would
let the command drop its port and type through Gas City alone:

- a nudge mode that refuses to paste onto a box that holds text while a client
  is attached, or waits for it to empty;
- the input box's state on a gc command or API endpoint.

The first would also close a gap the command leaves. Its read and the nudge's
paste are two steps, so a key a person presses between them still meets the
nudge.

This record names the gap only. Sending it upstream is the operator's call.

## No pack noun

The command adds no bead kind, lifecycle state or metadata key. The pull
request goes into the title's text, so it adds no key either. The command runs
Gas City's rename and nudge as one call, with a read before the nudge that
decides whether it runs, and it adds no meaning a Gas City mechanism carries.
So it takes no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2).

## What landing restarts

Nothing. `CoreFingerprint` (internal/runtime/fingerprint.go) leaves
`session_live` out, so a changed entry is drift the controller applies to a
live session without a restart. The converse templates change nothing else
that is hashed. The converse-prep skill's new text changes its `skills:` key,
which `FingerprintExtraChangePolicy` takes at a session's next start. The same
holds at the deployed build, `e03752646`.
