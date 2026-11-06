---
name: Probe of the witness's ending
description: Whether the next-iteration step makes the witness's model pour, assign and defer its next wisp, burn the current one and stop, measured against a stubbed gc. Read it to check the probe numbers in this change's summary, or to rerun the probe after changing that step or the witness's prompt.
---

# Probe of the witness's ending

A model's reading of step text decides whether a pass ends as designed, so this probe
runs the `next-iteration` step on the witness's model before it lands. It shows what
the text makes the model do. It cannot show the controller's restart or the spacing of
real passes: [the live proof](deferred-restart-proof.md) shows those on one rig.

## Method

Each run was one `claude -p` call on the witness's model, `claude-sonnet-5-5`, with
Bash as its only tool, from an empty directory, with a stub `gc` first on `PATH`. The
stub logs every call and answers as the store would: a list returns the current wisp
until it is burned, a pour returns a new id, and an update or a burn succeeds.

The system prompt was this change's render of `generated/seed-audit/agents/witness.md`.
The user message said the session had adopted its wisp and worked the earlier steps
with nothing to do, then gave the `next-iteration` description rendered from this
change's formula, with `binding_prefix` filled in.

## Result

Three runs on 2026-11-06, for $0.22 in all:

| Runs | Tool calls | Writes, in order | Last text | After the idle line |
|---|---|---|---|---|
| 3 of 3 | one, the pour block | pour, rig stamp, assign, `--defer=+1h`, burn of the current wisp | `IDLE: no work, exiting turn.` | nothing: no command, no background task, no status write on the next wisp |

Each run took the block as written, so the defer sat between the assign and the burn
in all three.

## Earlier rounds

The step this change replaced waited 600 seconds before it poured. Its probe, of 14
runs, is this file at commit `7b6d0be45`. It found that a session told to wait first
did so in one call or in a call of its own, and that a configured nudge arriving after
the idle line made the session adopt its next wisp and run one more pass in the same
conversation. That last finding concerns the startup reconcile, not the wait, so it
holds for this step too: such a session now adopts its deferred wisp and runs the pass
early. The nudge arrives near a session's start on the Claude Code versions in use:
196 of 199 witness sessions from 2026-10-27 took it within 21 seconds of starting,
counted on 2026-10-31.

## What it does not show

The stub answers instantly and the earlier steps are described, not run, so the pass
here is thinner than a real one, and three runs show a direction and not a rate. Whether
real witnesses end their passes this way, and how far apart the passes run, is what the
first real passes show.
