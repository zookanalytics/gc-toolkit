---
name: Probe of the witness's ending
description: Whether the rewritten next-iteration step makes the witness's model wait first, leave its next wisp open and stop, measured against a stubbed gc. Read it to check the probe numbers in this change's summary, or to rerun the probe after changing that step or the witness's prompt.
---

# Probe of the witness's ending

No witness has run the new `next-iteration` step, and a model's reading of step text
decides whether the pass ends as designed. So this probe runs the step before it
lands. It shows what the text makes the witness's model do. It cannot show the
controller's restart or the spacing of real passes, and
[the search record](gas-city-search.md#the-comparison) holds the measurements for
those.

## Method

Each run was one `claude -p` call on the witness's model, `claude-sonnet-5-5`, with
Bash as its only tool, from an empty directory, with a stub `gc` first on `PATH`. The
stub logs every call and answers as the store would: a list returns the current wisp
until it is burned, a pour returns a new id, and an update or a burn succeeds.

The system prompt was the arm's render of `generated/seed-audit/agents/witness.md`.
The old arm is this branch before the rework, and the new arm is this change. The user
message said the session had adopted its wisp and worked the earlier steps with
nothing to do, then gave the `next-iteration` description decoded from the arm's
formula. Two cases resumed a new-arm conversation with one more prompt, the text a
session would be sent.

| Case | Prompt | Wait | Runs |
|---|---|---|---|
| End of a pass | the step | 20s | old 3, new 4 |
| End of a pass | the step | the real 600s | new 3 |
| Late configured nudge | the agent's `nudge`, after the idle line | 20s | new 3 |
| The order's nudge | `witness-nudge.sh`'s text, after the idle line | 20s | new 1 |

That is 14 runs, for $0.87 in all.

## Result

| Case | Waited before the pour | Marked the next wisp in progress | Last text |
|---|---|---|---|
| End of a pass, old, 20s | 0 of 3: each poured, then waited | 0 of 3 | a summary of the step |
| End of a pass, new, 20s | 4 of 4, the wait and the pour in one call | 0 of 4 | the idle line, in all 4 |
| End of a pass, new, 600s | 3 of 3, the wait in a call of its own | 0 of 3 | the idle line, in all 3 |
| Late configured nudge, new | 3 of 3 on the second pass | 3 of 3, through the startup reconcile | the idle line, in all 3 |
| The order's nudge, new | 1 of 1 on the second pass | 1 of 1, through the startup reconcile | the idle line |

- **At the real wait** each run took about 610 seconds. Each passed a tool timeout of
  600,000 or 610,000 ms, the harness moved the wait to the background at its cap, and
  the model carried on to the pour when it finished. None ran a command after the burn.
- **The old arm's marking.** It did not reproduce a session marking its next wisp in
  progress. That shape is rare even in the field, 8 of the 381 sessions since the build
  that poured, so three runs could not be expected to show it. The arm's control value
  is the order of the wait and the pour, and the summary it ends on.
- **A late configured nudge** makes the session adopt its next wisp and run one more
  pass in the same conversation, which ends at `next-iteration` like any other. That
  costs a pass, and the restart takes over at the next turn end. The nudge arrives near
  a session's start on the Claude Code versions in use: on versions 2.1.311 and
  2.1.314, the sessions since 2026-10-27, 196 of 199 witness sessions took it a median
  2 seconds after starting, and at most 21. On 2.1.310 and earlier a session could
  still be holding it when its first turn ended, which 179 sessions show from 2026-10-14
  to 10-26. So no text was added for this case.
- **The order's nudge** still works under the prompt's rule against adopting a next
  wisp in the same conversation. The session ran the reconcile as the nudge asks.

## What it does not show

The stub answers instantly and the earlier steps are described, not run, so the pass
here is thinner than a real one, and three or four runs a cell show a direction and
not a rate. The prompt's own text is the only pressure toward stopping, with nothing
like a real session's longer context. Whether real witnesses take the wait, and how
far apart their passes run, is what the first real passes show.
