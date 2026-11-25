---
name: Unattended sessions and Claude Code's permission prompts, with the Gas City search
description: What governs the "Do you want to proceed?" prompt a bypass-mode Claude Code session can still raise, how often it held this city's pool sessions and for how long, what Gas City already does about a session at a prompt, and why the remedy is a PermissionRequest hook in the overlays of the agents no person attends. Read it when judging that hook, when a Claude Code release changes its permission prompts, or when a session no person attends is found waiting at one.
---

# Unattended sessions and Claude Code's permission prompts

Claude Code asks a person before some Bash calls even in bypass permissions
mode, and a pool or heartbeat session has no person to answer. The change in
this bead makes each agent no person attends answer every permission prompt
itself, with a refusal: `overlays/work-context` and `overlays/cycle-recycle`
register a `PermissionRequest` hook for every tool that prints one fixed deny
with a message to the agent. It reaches polecat and proactive (the pools) and
refinery, witness and deacon (the heartbeat roles). The seats a person attends
take `overlays/gh-origin-guard`, which registers none.

This is the operational surface the change adds: a hook registration in two
overlays, and proactive's move from `overlays/gh-origin-guard` to
`overlays/work-context`. It adds no script, metadata key, bead kind or state.

Claude Code was read at 2.1.332, the version installed on 2026-11-24, with
2.1.330 and 2.1.331 compared where noted. Gas City was read at
`gastownhall/gascity` main `33a7d167c8b7` (2026-11-25). Measurements were taken
on 2026-11-25 between 16:56Z and 17:25Z.

## What Claude Code offers

The bead asked first which Claude Code settings govern these checks under
bypass mode. Read in the 2.1.332 binary, and measured where the table says so:

| Setting or mechanism | What it does | Why it is not the remedy |
|---|---|---|
| `CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS` (environment) | Waives the removal check in bypass mode. Claude Code's own notice: "dangerous rm commands can run without a prompt in bypass permissions mode once managed settings and plugin hooks have loaded". Read in the binary, not measured: it does not apply in a child session (`CLAUDE_CODE_CHILD_SESSION`), nor beside `permissions.blockReadsOutsideWorkingDirectories` or some deny and ask rules | It runs the removal. The check exists for an empty variable that turns `rm -rf "$D"/*` into `rm -rf /*`, and a pool agent's mistake would then reach the home or the disk |
| Feature flag `tengu_splendid_horizon` and `CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT` (environment) | Claude Code's own bound: a removal prompt shows "Claude Code will automatically block this request in 1:59, to avoid holding up an unattended session", then denies. Defaults: `enabled`, a `timeoutMs` of 120000 and `maxDialogTimeouts` of 3, after which it denies without showing a prompt. Only the server's payload can turn `enabled` off, and the environment variable turns it off. 2.1.330, 2.1.331 and 2.1.332 carry the same defaults | It applies only to the main thread's removal prompts. It skips a background subagent's, a teammate's and a remote run's, and measured below, a background subagent's prompt waited with no countdown. It also failed two main-thread prompts in this city (the census). No account's cached flag values (`cachedGrowthBookFeatures` in each `~/.claude.json`) hold the flag now, so what the server sent on 2026-11-23 cannot be read back, and why those two got no block is not determined |
| `--permission-prompts none` | "Who answers permission prompts with --print": nobody, so anything that would prompt is denied | Print mode only. Measured: an interactive session started with it still showed the prompt |
| Permission mode `dontAsk` | Read in the binary, not measured: denies what would prompt, and denies every call that no allow rule covers | It replaces these sessions' bypass mode with an allow list to keep current |
| `PermissionRequest` hook | Runs when Claude Code would show a permission dialog, for the main thread and for subagents, background ones included, and applies a hook's deny at once. The model reads the hook's message as the tool's error, and the call does not run. Its input carries `session_id`, `transcript_path`, `cwd`, `permission_mode`, `tool_name`, `tool_input` and `permission_suggestions`, and `agent_id` and `agent_type` for a subagent. It carries no reason for the prompt | Taken. Claude Code skips the hook for a prompt it marks for a person only, read in the binary as, for one, saving or uploading a file. None of the measured prompts was marked so |

The hook's message carries the guidance Claude Code's own refusal gives, because
the hook cannot see the reason for the prompt: what held the call, and what to
send instead. A call that removes nothing goes again in plain syntax bash and
zsh both read. A removal goes again only with a literal or `${VAR:?}`-guarded
path, and never by a route around the check.

## The census

`gc events --type session.pending --since 72h` and its `session.pending_cleared`
pair, read on 2026-11-25 at about 17:23Z, from the first event at
2026-11-23T00:46Z. Gas City records a session's pending interaction with its
kind. The census paired each pending event with its cleared event by
`request_id`. A letter stands for one session, so a letter shown twice is one
session that met two prompts.

| Started (UTC) | Session | Claude Code | Waited | Ended |
|---|---|---|---|---|
| 2026-11-23 00:46 | gc-toolkit polecat, session A | | 1 m | resolved |
| 2026-11-23 00:57 | gc-toolkit polecat, session A | | 2 m | resolved |
| 2026-11-23 08:32 | gascity polecat, session B | | 1 m | resolved |
| 2026-11-23 10:36 | gc-toolkit polecat, session C | | 1 m | resolved |
| 2026-11-23 20:13 | gc-toolkit polecat, session D, main thread | 2.1.330 | 434 m | resolved by the mechanik's answer |
| 2026-11-23 21:04 | gc-toolkit polecat, session E, background Explore subagent | 2.1.330 | 384 m | resolved by the mechanik's answer |
| 2026-11-24 03:29 | gc-toolkit polecat, session D | | 2 m | resolved |
| 2026-11-24 06:49 | gc-toolkit polecat, session F, main thread | 2.1.331 | 846 m | session gone |
| 2026-11-24 21:31 | gc-toolkit polecat, session F | | 2 m | resolved |

Nine approval prompts reached pool sessions in the window. Six cleared within
two minutes, which matches Claude Code's own block. Three held their session for
6.4, 7.2 and 14.1 hours, and the third ended only when its session went away.
The ten `question` events in the window are all the po's, which a person
attends. The bead named the first two of the three. The third is the same fault:
a main-thread command that removed variable paths inside a loop and ran a
`sh -c` script.

## Measurements

Each probe was an interactive Claude Code 2.1.332 session on a private tmux
socket, started with `--dangerously-skip-permissions`, `--setting-sources
project,local`, `--strict-mcp-config` and Haiku, under `env -i`, so it loaded no
user settings and none of the city's hooks.

| Command sent | Hook | Result |
|---|---|---|
| `D=<literal path>; mkdir -p "$D" && rm -rf "$D"/*` | probe hook | Ran, no prompt |
| The bead's quoted command, `D="$HOME/…/m1635"; mkdir -p "$D" && rm -rf "$D"/*` | probe hook | Ran, no prompt. The stuck command was longer: four `$(…)` captures came before it |
| `D=$(printf '%s' "$HOME/…/m1635"); mkdir -p "$D" && rm -rf "$D"/* && ls "$D"` | probe hook | Denied by the hook at once, not run |
| The stuck Explore subagent's exact echo, printf and awk command, from the main thread | probe hook | Denied by the hook at once, not run |
| The same command from a background subagent, twice | probe hook | Denied by the hook at once, not run. The hook's input named the subagent |
| The `$(printf …)` removal | none | Prompt with the two-minute countdown, blocked at 2:00. The model read "Permission for this command was denied by a built-in Claude Code safety check, not by the user" |
| A harmless copy of the 434-minute command's shape | none | Prompt with the two-minute countdown |
| The `$(printf …)` removal, with `--permission-prompts none` | none | Prompt with the two-minute countdown |
| The stuck Explore subagent's command from a background subagent | none | "Bash command · from the general-purpose agent … Claude Code can't be sure it read this command the way the shell will". No countdown, and still waiting 2 m 49 s later |
| The `$(printf …)` removal, and the subagent case twice | the work-context overlay's `settings.json` as project settings | Denied by the hook at once, not run, with the overlay's message |
| A harmless copy of the 846-minute command's shape | the same | Ran, no prompt: 2.1.332 held nothing in it |

A prompt answered by a person's refusal ends the model's turn. Answered with the
menu's No option, the key Gas City's deny presses, twice at 17:30Z, and with
Escape once at 17:06Z, the probe showed "Interrupted · What should Claude do
instead?", and the model read "The user doesn't want to proceed with this tool
use … STOP what you are doing and wait for the user to tell you how to
proceed."

## What Gas City offers

| Primitive at `33a7d167c8b7` | What it gives | Why it does not cover the need |
|---|---|---|
| `runtime.AcceptStartupDialogs` (`internal/runtime/dialog.go`) | Dismisses the dialogs that block a session's start, Codex's hook review and Claude's bypass-mode warning among them | Startup only. A tool approval comes mid-session |
| `runtime.DismissMidSessionDialogs` and `midSessionDialogs` (`internal/runtime/dialog_midsession.go`) | Before a nudge, dismisses Claude's resume, session-feedback and session-limit dialogs with fixed keys | No approval dialog is among them, and an approval needs a decision, not a fixed key |
| `runtime.InteractionProvider`'s `Pending` and `Respond` (`internal/runtime/tmux/interaction.go`, captures in `internal/runtime/tmux/testdata/claude-approval/`), and the controller's pending-interaction lane (`internal/pendingwatch/pendingwatch.go`, `startPendingInteractionLane` in `cmd/gc/pending_interaction_lane.go`) | Reads an approval dialog off the pane, and every 5 seconds the lane records `session.pending` and `session.pending_cleared` on the city's event log, "so an order or agent gated on session.pending sees the same transitions". `Respond` answers by pressing the menu option an action names (`approvalOptionKey`) when an API caller asks (`/v0/session/{id}/respond`), with no text for an approval | Nothing in Gas City answers on its own. An order gated on `session.pending` could answer with `deny`, which presses No: measured above, that ends the agent's turn with Claude Code's "STOP … and wait for the user", so the session waits again, for a person who is not there. An order that tells a person reports the wait and does not end it |
| The nudge backstop's hold (`pendingInteractionBlocked` and `backstopHoldPendingInteraction` in `cmd/gc/nudge_backstop.go`) | Holds a nudge behind a pending interaction, so the nudge's text does not answer it | It holds. It neither answers nor reports |
| The work ladder's notices (`cmd/gc/work_ladder_notice.go`; `WorkLadder` defaults to `on` in `internal/config/config.go`, and this city's `city.toml` sets no `work_ladder`) | Counts a seat at a pending interaction as a refusal, and records `work.escalated` with reason `nudge_refused` at the third refusal in a row and while they go on | It records an alert and does not answer. In the census it fired 7, 6 and 8 times for the three long waits, first at 20:35Z, 21:51Z and 07:11Z, 22, 47 and 22 minutes in. Nothing in the pack reads `work.escalated` or `nudge_refused`, so it reached no one |

Gas City records a session at a prompt and answers only when a caller names the
answer. The prompt is Claude Code's, and Claude Code's hook answers it where it
rises, before the session waits, with a message the agent can act on.

## What the change leaves

- A prompt Claude Code marks for a person only skips the hook and still waits.
  None of the measured prompts was one, and the census cannot say whether any of
  the nine was. Such a wait shows as `session.pending` of kind `approval` and as
  Gas City's `work.escalated` alert, which the census above reads.
- The Codex pool, polecat-codex, reads no `.claude` overlay. Its approvals are
  Codex's.
- A prompt on a seat a person attends still waits for that person, by design.
