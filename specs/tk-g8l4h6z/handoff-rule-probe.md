---
name: A/B probe of the mechanik's handoff trigger
description: Read it to check the numbers in the landing PR's decision about the mechanik's "with nothing left that only you can do", to see what that clause moves, or to re-run the probe on a later wording.
---

# A/B probe of the mechanik's handoff trigger

The filed bullet closes any bead assigned to the mechanik when a handoff would carry
it, and a correctness review blocked on that: it orders a bring-current task closed
before its merge, which starts the bead waiting on it from a stale branch, and it
orders a town-repo edit closed with no other owner. This measures what an agent does
with the filed text and with the clause added.

The clause moved no decision, and the filed text does not fail the way its literal
reading says. No run with either text closes a bead that holds work only the mechanik
can do. What the clause changes is the reasoning. Filed-text runs on a bring-current
task set the rule aside, in words like "the rule against carrying beads across a
handoff can't override that". Clause runs read the rule as not reaching the bead, in
words like "the close rule only applies when nothing is left that only I can do". The
clause closes nothing less on the beads behind the correction: both texts close them
in every run.

| Case | The bead | Filed text | With the clause |
|---|---|---|---|
| A, bring-current task | Prerequisite landed, merge undone, dependent armed on its close, all spelled out | keep open 3 of 3 | keep open 3 of 3 |
| B, town-repo edit | Edit unmade, waits on a pull request | keep open 3 of 3 | keep open 3 of 3 |
| G, A as a hook line | A title and `ready`, with no edge named | keep open 3 of 3 | keep open 3 of 3 |
| H, B as a hook line | A title and `blocked by`, with no edge named | keep open 3 of 3 | keep open 3 of 3 |
| C, the correction's incident | P1, fixes live, kept so the next session sees it | close 3 of 3 | close 3 of 3 |
| D, someone else's work | Cause found in a pack script, fix unwritten | close 3 of 3 | close 3 of 3 |
| F, a watcher | A reminder to look at an order's log in a week | close 3 of 3 | close 3 of 3 |
| E, the operator's direction | Theirs, "not yet", waits on an epic, nothing in it for the mechanik to do | keep open 3 of 3 | keep open 3 of 3 |

In case E every run in both arms reassigns the bead to the operator with its edge
intact and tells them once. The bead's builder had read the bullet as closing it, so
that reading is not what these runs do.

These readings are mine. Sorting the runs in A, B, G and H by what they say about the
rule is a judgment, and the table counts only their decisions.

## Method

Each arm's system prompt held a role line, the whole "Learned conventions" section of
`template-fragments/learned-conventions-mechanik.template.md`, the prompt's paragraph
on bringing a branch current, the authority map's town-repo row, and the prompt's
Session End list. The filed arm's section came from the commit before this clause and
the other from the commit that adds it. The two differ by the clause and the line
breaks it moves. The role line:

> You are the mechanik, the coordinator of a software city's agents. You work with the
> operator in a live session, and pool agents called polecats build changes to the
> pack's repository.

The user message was the same in both arms for a given case: the operator's "Wrap up,
I want a fresh session", no time for more work in this session, the one bead on the
hook, and a request to open with `DECISION: close` or `DECISION: keep open` and give
the reason in at most three sentences. Each run was one call from an empty directory,
with every `GC_*` and `BEADS_*` variable unset:

`claude -p --model claude-opus-5-5 --tools "" --max-turns 1 --setting-sources "" --strict-mcp-config --disable-slash-commands --no-session-persistence --output-format json --system-prompt "$(cat <arm>)" "$(cat <case>)"`

Eight cases, two arms and three runs a cell made 48 calls, for $0.81.

## What it cannot show

It is a cut-down prompt with no tools and few runs a cell, and it ran on Claude only.
Each case asks directly what to do with the bead, which a real handoff does not, so a
real session in a hurry may read the rule less carefully than these runs did. It shows
that the clause costs nothing on the beads it should still close. It does not show
that the filed text is safe, and the review's reading of what that text orders stands.
