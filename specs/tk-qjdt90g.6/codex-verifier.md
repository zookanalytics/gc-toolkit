---
name: What Codex offers a correctness verifier
description: The record of tk-qjdt90g.6's check of what Codex, the provider the city's correctness reviews run on, offers a clean-context verifier, read from the Codex CLI and the prompt it renders on 2026-10-26, and what the correctness method's verify step takes from it. Read it to judge how a codex review verifies its blocking candidates, or to re-check after a Codex upgrade.
---

# What Codex offers a correctness verifier

The operator ruled that a correctness review's verifier is a subagent where
the reviewing provider supports one, and otherwise the same agent in a
separate pass ([the epic's rulings](../tk-qjdt90g/review-coverage.md#at-the-contract-sitting)).
The merge cadence routes review beads to the polecat-codex pool
(`assets/scripts/refinery-reconcile.sh`, `REVIEW_POOL`), so this unit checked
what Codex offers.

## What was read

- The Codex CLI the city runs, `codex-cli 0.164.0`. The app-server daemon
  under the city's Codex home is the same release.
- `codex features list` under that home: `multi_agent` is stable and on, and
  `multi_agent_v2` is stable and off. The home's `config.toml` turns on one
  feature of its own, `code_mode_host`, and turns none off.
- The prompt a codex session's model receives, rendered by
  `codex debug prompt-input` under a copy of that home's model, feature and
  project settings. The model is `gpt-6.1-sol`, the one the city's codex
  provider selects.

## What Codex offers

- **A subagent tool.** The model is given `spawn_agent`, with `wait_agent`,
  `followup_task`, `send_message`, `interrupt_agent` and `list_agents`. A
  codex reviewer can hand a candidate to a verifier and wait for its answer.
- **A subagent inherits the whole conversation by default.** `spawn_agent`'s
  `fork_turns` parameter reads "Parent history to inherit. Defaults to `all`;
  use `none` to start without parent history." A verifier spawned with the
  default has read the reasoning that raised its candidate, so it is not a
  clean context. One spawned with `fork_turns="none"` starts with only the
  task it is given.
- **Nothing makes a subagent read-only.** "The spawned agent will have the
  same tools as you", and "All agents share the same directory", so an edit
  one makes is visible to all at once. Only its brief keeps a subagent from
  writing in the review's workspace or calling `signoff.sh`.
- **It spawns only when asked.** The rendered prompt tells the model: "Do not
  spawn sub-agents unless the user or applicable AGENTS.md/skill instructions
  explicitly ask for sub-agents, delegation, or parallel agent work." A
  method that only permits a subagent leaves a codex reviewer working alone.
- **Up to four agents run at once.** "There are 4 available concurrency
  slots, meaning that up to 4 agents can be active at once, including you."

## What the method takes from it

The correctness method stays written for any provider, and answers these
facts in its own terms:

- The verify step asks for a verifier outright where the provider offers
  subagents, while a finder stays the reviewer's choice.
- A finder or a verifier starts with none of the reviewer's conversation, and
  a provider that copies the conversation unless told not to is told not to.
  On Codex that is `fork_turns="none"`.
- A subagent's brief states the review formula's rules for subagents, because
  a subagent can hold every tool the reviewer holds.

So the method asks a codex review to verify its blocking candidates in
verifier subagents. The separate pass is the form for a provider that offers
no subagent, which includes a Codex whose `multi_agent` feature is off.

## Not observed

No codex correctness review has run under this text yet, so whether
`gpt-6.1-sol` spawns its verifiers, and passes `fork_turns="none"` when it
does, has not been seen. Either form the operator ruled on satisfies the
method. A verifier spawned with the whole conversation satisfies neither,
which is what the method's sentence on the conversation guards against.

## Re-checking after a Codex upgrade

Read the tool from the rendered prompt, `codex debug prompt-input` under the
city's Codex home, not from the feature list. `codex features list` reports
`multi_agent_v2` off, yet the tool the model is given takes `fork_turns` and
`task_name`. The binary also refuses an older `fork_context` parameter in
favor of `fork_turns`, so the tool's shape has moved before.
