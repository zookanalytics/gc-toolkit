---
name: Routing check of the shorter skill descriptions
description: Use when you want to know whether cutting the pack skills' descriptions to the load decision cost any routing, or you need to repeat that check on later wording.
---

# Routing check of the shorter skill descriptions

`assets/scripts/skill-needs.test.sh` is a floor on vocabulary, not a model of
the agent, so the rewritten descriptions were also run against a model, the way
[the first probe of these skills](../tk-fqw7x2b/hunts.md#a-live-probe-of-the-same-needs)
was.

## What ran

Each arm is a scratch directory whose `.claude/skills` holds the links a pack
agent receives, gc-toolkit's skills and the core pack's. The old arm links the
skills at ee18b1b1e, the commit this work branched from, and the new arm links
the rewritten ones. Only the descriptions matter, because the first tool call
comes before any body is read.

Each need ran once in each arm as one `claude -p` call on `claude-opus-5-5`, with
only read-only tools (`Skill,Read,Grep,Glob`), one turn, and `GC_*` and `BEADS_*`
unset. The appended system prompt was "You are the `<role>` agent in Gas City.
You check how to act before you act." The message was `<situation> Your next
thought, before you act: "<need>" Take your next step.` The first tool call is
the result.

## Result

The expected skill was the first thing loaded on all 17 needs that got an answer
with the new descriptions, and on 16 of those 17 with the old ones. The safeguard
refused the other need in both arms, on one turn and again on three, so it is no
routing result. The runs cost about three dollars.

The numbered rows quote `skill-needs.test.sh` verbatim, under
[their numbers in the hunts record](../tk-fqw7x2b/hunts.md). Rows h01 to h06 were
written for this check, to reach words the rewrite removed and skills no recorded
need covers.

| Row | Role | Situation | Need | Expected | Old | New |
|---|---|---|---|---|---|---|
| 1b | polecat | You just finished a design note and the implementation work is ready to send. | Let me confirm the exact sling incantation used elsewhere in the codebase for routing fresh implementation work to the polecat pool, so I route it the canonical way. | work | work | work |
| 10 | polecat | You found a bead that repeats one already tracked. | Now working out the right way to retire this duplicate, since polecats may not close work beads themselves. | work | work | work |
| 4b | mechanik | You are about to file a bug for another rig. | Checking cross-rig filing mechanics and default sling targets before creating. | work | work | work |
| 5 | mechanik | The operator wants a design pass before anything is built. | Since the drawing-board work is a **design** task, let me check which formula routes a design/spec pass while the subagents finish. | work | work | work |
| 11 | first reaction | You filed nothing yet and the fix depends on another bead landing. | No existing tracker covers the class gap. Checking the deferred-dispatch arm's usage before filing. | waits | refused | refused |
| 12 | first reaction | You want the follow-up to start only once its gate clears. | Before arming, I'll check that an arm behind the park gate fits how the gate is meant to work. | waits | waits | waits |
| 13 | witness | A bead is blocked on something only a person can clear. | I'm reading `escalate.sh` to see how it files the visit and whether it wires the subject to it. | waits | waits | waits |
| 16 | mechanik | The operator answered and the bead waits on that answer. | Checking the demand-resolution verb first. | waits | waits | waits |
| 26 | polecat | The bead you armed earlier should no longer dispatch. | First, the disarm command's usage. | waits | waits | waits |
| 19 | mechanik | The sitting decided the outcome and the board's line is stale. | Let me confirm the notes-append verb (I must not clobber the rich Sitting-1 notes) and re-stamp the takeaway. | records | records | records |
| 20 | polecat | A reviewer asked a question on the pull request you own. | While the suite runs, I'm reading `pr-post.sh` to see how it marks the city's reply, so I can draft the answer to the review. | prs | prs | prs |
| 22 | mechanik | A review found a defect in an open pull request. | Still routing: I'm finding the right way to send rework back to an open PR's branch, so the polecat works on the same PR rather than starting a new one. | prs | prs | prs |
| h01 | first reaction | A finding reports a problem in code another bead is about to fix. | This finding is moot once that fix lands, so I want it to close by itself instead of coming back to triage. | waits | waits | waits |
| h02 | polecat | You reached a question nobody but the operator can answer. | I need to ask the operator for a decision before this goes. | waits | waits | waits |
| h03 | mechanik | An epic needs one more piece of work. | This follow-up decomposes the epic, so I need to file it as a member in the right rig. | work | work | work |
| h04 | polecat | You finished comparing three designs and want to keep the result. | I've finished the analysis and need to write it up as a durable record. Where does it go? | filing-documentation | filing-documentation | filing-documentation |
| h05 | polecat | A feature shipped and the reviewer wants to see it working. | I need to record a demo video of this feature for the pull request. | demo-capture | review-demo | demo-capture |
| h06 | polecat | Another agent asked you for an opinion on a branch. | Does this change fit the architecture of the repo? | review-arch | review-arch | review-arch |

## What it does not show

- One run per need per arm rules out a broad loss of routing, not a small shift.
  The one row that differs could be chance.
- The model had a short system prompt and nothing else from an agent's context.
- The method skills are absent apart from h06. The review formula loads
  `review-<check>` by name, so its description decides little for a review.

## The same comparison on the scorer

Before the live runs, 42 needs written for this check went through the suite's
scorer in a scratch copy of the suite. They stay out of the suite, whose rows must
be needs an agent recorded. The old descriptions scored 36 of them highest on the
expected skill and the new ones 38. The new descriptions miss four, and the old
descriptions miss those four too:

- "This bead needs no work, so I need to retire it." expected work, ties prs.
- "I need to ask the operator for a decision before this goes." expected waits,
  behind handoff. The live run of the same need loaded waits in both arms.
- "I am about to write up this analysis as a spec." expected
  filing-documentation, ties records, whose neighbor clause names a spec and an
  analysis.
- "Which review checks does this diff warrant?" expected review-triage, ties
  review-demo.
