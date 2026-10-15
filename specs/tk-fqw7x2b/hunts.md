---
name: Real hunts behind the ask-for-work skill descriptions
description: The needs agents stated, in their own words, just before they searched script source, docs and memory for how to ask for work, with where each was found, what the agent did next, and which of the work, waits, records and prs skills answers it. Records how the description check in assets/scripts/skill-needs.test.sh was built from them, and a live probe that ran them against a model with and without the new skills.
---

# Real hunts behind the ask-for-work skill descriptions

The operator settled the shape of the work, waits, records and prs skills in
the sitting on visit tk-o73de41, and named the descriptions as the part that
matters most (2026-10-15T02:54Z):

> And we think we can write the proper description that lets an agent know
> when to use the skill, that's arguably the most important part, it knows
> the skill is available and can articulate it's needs well enough to find the
> right skill.

The sitting proposed the proof and the operator approved it with "I like this
more, go with it": "The PR proves the descriptions: a handful of needs taken
from real hunts, each checked against the skill it should load." This page is
the record of those hunts, the check built from them, and a live probe of the
same needs.

## Where the needs came from

A read-only search went through the Claude Code transcripts of converse
sittings, the mechanik, the deacon, the witness, polecats and first reactions,
under `/Users/gc/orch-homes/*/.claude/projects/`. Each session appears as an
identical copy under agent1, agent2, agent3 and zook; paths below name the
agent1 copy. A hunt is a sentence where an agent stated what it needed to do,
followed by reads of script source, docs, memory or `--help` to find out how.
Hunts about how to do work, such as debugging a script, were left out. Every
quote below is verbatim.

### The capture's own case

Visit tk-wyqkhqz, on subject tk-m7n9yal, 2026-10-13
(`-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-wyqkhqz/72399f1c-a616-4361-87ed-0e1f1bcee98e.jsonl`).

At 17:14:43Z the sitting wrote: "The operator's reply settles the open
question. I'll check how the sitting should carry out the routing before
acting." It then made 25 tool calls over 16.7 minutes before its sling
succeeded, 13 of them reads about how to act, and about 7 minutes of the span
was the operator's clarification. It read `gc-helm.sh`'s Accept verb, five
memory notes, `docs/gascity-human-engagement.md`, `converse-signoff.sh`,
`gc sling --help` and `mol-polecat-work.toml`. Its first sling copied Accept's
`--var issue=` and failed ("formulas v2 reserved variable "issue" cannot be
supplied by the caller"). It then slung `--on mol-polecat-work`, wrote the
dispatched marker by hand, and closed the visit. Mapped to work, taking a
recommendation.

### The hunts

The check column says whether `skill-needs.test.sh` carries the need, and why
not when it does not.

| # | Need (verbatim) | Role, session, time (UTC) | What it searched | What it did | Skill and option | In the check |
|---|---|---|---|---|---|---|
| 0 | "Before I route, I need to get the mechanics exactly right — the subject tk-5rh0v2 is the implementation task ("Wire a Dolt reclaim cadence"), so I must understand whether --route releases the held subject itself or expects a separate sibling bead." | converse, quoted by the operator in tk-6wq5ec, 2026-10-02 | `converse-signoff.sh`, a redispatch memory note, the polecat agent config | Concluded it should release the held subject to the pool through the sign-off | work, which bead carries the work in a sitting | yes |
| 1a | "Before the safety-critical writes, I need three things: the subject's own parent (work must be filed as a sibling), the right formula to route through (not a bare sling), and the exact `converse-signoff.sh` semantics." | converse, tk-jliz3j, 2026-09-27T04:03:26Z | 12 reads in 6 min: `converse-parent.sh`, `converse-signoff.sh`, `gc formula list`, `mol-polecat-work.toml`, `gc sling --help`, city.toml, a routing-doc grep, a memory note | `gc bd create` with no parent, then `gc sling gc-toolkit/gc-toolkit.polecat <bead> --on mol-polecat-work` | work, filing beside the subject, choosing the formula, sending it | yes |
| 1b | "Let me confirm the exact sling incantation used elsewhere in the codebase for routing fresh implementation work to the polecat pool, so I route it the canonical way." | same session, 04:05:37Z | as above | as above | work, sending to a pool on a formula | yes |
| 2 | "The record/sign-off procedure is clear, but I need to get the routing shape exactly right before I act — specifically whether `--route` in the sign-off itself performs the sling, and how a bug subject (already a workable bead) is routed versus filing a sibling." | converse, tk-nekbtz, 2026-10-04T00:39:56Z | 8 calls in 6 min, including the core `gc-dispatch` skill | Signed off, slung with no `--on`, then spent about 17 more minutes repairing what it read as a detached root | work, which bead carries the work in a sitting | yes |
| 3 | "Before dispatching a third time, let me confirm how the pool actually starts work — does the polecat pour the formula on claim, or does it need the convoy pre-built?" | converse, tk-0x913e, 2026-09-18T16:29:41Z | About 25 calls in 24 min, two wrong slings, three orphan convoys | `gc convoy add` and a sling `--on mol-polecat-work` | work, sending to a pool on a formula | yes |
| 4a | "Checking the subject's parent and the routing options first." | converse, tk-tomdkqk, 2026-10-12T17:41:45Z | 5 reads | A bare `gc sling` that left the recommendation gate open and `gc.recommended_formula` live; a polecat later finished the act by hand | work, filing beside the subject and sending it | yes |
| 4b | "Checking cross-rig filing mechanics and default sling targets before creating." | same session, 17:42:08Z | as above | as above | work, filing in the right rig | yes |
| 5 | "Since the drawing-board work is a **design** task, let me check which formula routes a design/spec pass while the subagents finish." | converse, tk-hpjrr0, 2026-10-02T16:26:47Z | 5 calls: formula descriptions, `gc formula list`, `mol-polecat-work.toml` | `gc bd create`, then a sling | work, choosing the formula | yes |
| 6 | "Let me gather what I need to execute correctly: the available formulas (to pick a routing shape that satisfies the constraint), the disposition writer's retire interface (safety-critical PR close), and the subject's parent (so the new bead is filed as a sibling, not a child)." | converse, tk-l26xp9, 2026-09-29T00:17:00Z | About 20 calls and an Explore subagent over 26 min | An owned convoy with edges and an arm, then `pr-dispose.sh --kind re-homed` | work and prs | no: two skills in one need |
| 7 | "The work bead's parent epic is parked behind the operator's "hold everything" gate, so I'm checking how to decline this pre-park molecule cleanly rather than build it." | polecat, tk-vd66j1.7, 2026-10-11T01:31:08Z | 14 reads in 5 min | `escalate.sh`, a note, `molecule-hold.sh` | a worker declining its own run, which the polecat prompt carries | no: not an option of these skills |
| 8 | "Found the tooling — there's a sanctioned `dead-molecule-dispose.sh` for exactly this. Let me read its contract and get the molecule's current state before I run anything." | mechanik, 2026-09-21T23:13:25Z | 6 calls in 5 min | `gc convoy delete --force`, then `bead-rehome.sh --kind duplicate` | work, stopping work and closing a bead | no: the need names a script, not an act |
| 9 | "These are four writes across two rigs, and resolving a `routed_to=human` gate + resuming held work is exactly the kind of actuation I want to get mechanically right rather than guess." | mechanik, 2026-09-20T17:53:39Z | Delegated to a subagent; the act came three hours later | `signoff.sh reset`, `gc convoy delete --force`, a re-sling | waits and work | no: two skills in one need |
| 10 | "Now working out the right way to retire this duplicate, since polecats may not close work beads themselves." | polecat, tk-k45o8u, 2026-10-12T09:49:20Z | About 28 reads in 4 min | Stamped `duplicate_of` and `gc.work_outcome=no-op`, held its run, and let duplicate-sweep close the bead | work, closing a bead that needs no work | yes |
| 11 | "No existing tracker covers the class gap. Checking the deferred-dispatch arm's usage before filing." | first reaction, proactive-2, 2026-10-04T19:46:54Z | 3 reads | `gc bd create`, a blocks edge, `deferred-dispatch.sh arm` | waits, arming | yes |
| 12 | "Before arming, I'll check that an arm behind the park gate fits how the gate is meant to work." | first reaction, proactive-1, 2026-10-10T23:55:18Z | About 7 reads | `deferred-dispatch.sh arm` | waits, arming | yes |
| 13 | "I'm reading `escalate.sh` to see how it files the visit and whether it wires the subject to it." | gascity polecat, gc-34931, 2026-10-09T08:24:47Z | 9 calls in 4.5 min | Filed a bead in the gc-toolkit store, then `escalate.sh` | waits, asking for a sitting | yes |
| 14 | "First, the two contracts I need: the gate-visit filing block and the sign-off writer's usage." | converse, tk-fw8w1w, 2026-09-29T16:35:06Z | 3 reads | Pasted the gate-visit block | waits and the settle step | no: two skills in one need |
| 15 | "Wiring the approved cleanup so it comes back to you on its own once the fix lands, and can't delete anything until you've approved the list. Checking the demand-filing verb first." | converse, tk-a9fnmtw, 2026-10-11T04:38:50Z | About 7 reads, including `gc-helm.sh` lines 1376–1470 | A blocks edge, then `gc-helm.sh demand` | waits, a wait on work and on a person | yes |
| 16 | "Checking the demand-resolution verb first." | converse, tk-eywd7n, 2026-09-27T04:24:32Z | 2 reads | Closed the demand gate with a bare `gc bd close` | waits, releasing a wait | yes |
| 17 | "Before filing anything, three quick discovery reads: how tk-tutb46's deferred dispatch is expressed (so the distillation bead can be armed the same way), the subject's parent (for sibling filing), and the dep/sling syntax." | converse, tk-eywd7n, 2026-09-22T05:39:37Z | 3 reads | Four creates, a hand-built rework bead, an arm made by hand-stamping metadata, a sling | work and waits | no: two skills in one need |
| 18 | "Recording the ruling and filing the rework. First I'll check how the comment poster, the sign-off and the notes writer expect their inputs." | converse, tk-vijqp9x, 2026-10-12T07:33:49Z | 7 reads | A Current state note, then the rework | records and prs | no: two skills in one need |
| 19 | "Let me confirm the notes-append verb (I must not clobber the rich Sitting-1 notes) and re-stamp the takeaway." | converse, tk-m8ibue, 2026-09-27T04:19:20Z | 2 reads and one wrong guess (`gc bd append-notes --help`) | `gc bd note`, then `gc-helm.sh takeaway` | records, both options | yes |
| 20 | "While the suite runs, I'm reading `pr-post.sh` to see how it marks the city's reply, so I can draft the answer to the review." | polecat, PR #1239, 2026-10-13T13:52:16Z | 6 reads, including the write-back's marker logic in `pr-facts.sh` | `pr-post.sh comment` | prs, answering review comments | yes |
| 21 | "Before executing the public PR actions, let me gather what I need and spot-verify the one still-current finding (…)" | converse, tk-ghgl4x, 2026-10-04T16:20:36Z | 7 reads in 6 min | GraphQL replies and resolves on five threads | prs, with four other lookups | no: one need lists five lookups |
| 22 | "Still routing: I'm finding the right way to send rework back to an open PR's branch, so the polecat works on the same PR rather than starting a new one." | converse, tk-hmhbznk, 2026-10-11T23:36:55Z | About 20 reads in 3 min | Hand-minted a rework child; `rework-child.sh` landed an hour later | prs, sending it back for rework | yes |
| 23 | "Before acting on your ruling, I'm checking that the PR's state hasn't moved overnight and reading how the sign-off files the rework." | converse, tk-r2zb925, 2026-10-14T14:38:58Z | About 11 reads | `converse-rework.sh`, then the sign-off with `--rework` | prs, sending it back for rework | yes |
| 24 | "Ruling A recorded. Before I act on it, I'm checking how the retire and the follow-up cleanup get wired, so the cleanup can't delete anything before you've seen the list." | converse, tk-a9fnmtw, 2026-10-11T04:33:49Z | 16 reads in 6 min | `pr-dispose.sh --kind re-homed` | prs and waits | no: two skills in one need |
| 25 | "I'll check the retire script's flags, then order the steps so that window is a few seconds at most." | converse, tk-glv85mz, 2026-10-12T16:06:27Z | A subagent and 5 reads | `pr-dispose.sh --kind not-needed` | prs, retiring it | no: "retire" is its only act word, and work uses it too for a bead |
| 26 | "First, the disarm command's usage." | polecat-3, 2026-10-08T15:48:34Z | the disarm usage | a disarm | waits, releasing a wait | yes |

No hunt was found for holding a merge (sittings ran `converse-hold.sh
--hold-merge` straight from the hold step), for withdrawing a recommendation
on its own, or for an assigned task demand. Neither the deacon nor the witness
had a qualifying hunt: the witness's escalations are scripted by its patrol
formula.

Session files, under `/Users/gc/orch-homes/agent1/.claude/projects/`:
1. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-jliz3j/10e87087-8917-4fc9-bc74-ad5743eb0162.jsonl`
2. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-nekbtz/6c01302e-2116-4e4d-9a38-f5c53b3c972f.jsonl`
3. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-0x913e/18518ac8-ac92-4cb5-8ebc-2e13f71d4405.jsonl`
4. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-fable-gc-toolkit-tk-tomdkqk/c165c45f-9c7c-4d8c-82eb-2bf0335e7970.jsonl`
5. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-hpjrr0/b1e99e3b-4753-424a-b4f3-ae0fb91d1b7a.jsonl`
6. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-l26xp9/3dd1d6b7-e4c2-419e-823a-bcf37f74447e.jsonl`
7. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-polecats-gc-toolkit-polecat-5/44c89b63-d199-475a-9fa4-5afc52cee60a.jsonl`
8. `-Users-gc-Code-loomington--gc-agents-mechanik/12cf364e-7ae1-4022-bd91-8a3f3d67a524.jsonl`
9. `-Users-gc-Code-loomington--gc-agents-mechanik/9606d217-ce4d-4ab1-ae6b-e07fd0d25e17.jsonl`
10. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-polecats-gc-toolkit-polecat-2/d6d44716-5f36-4de7-baf4-45d236de8984.jsonl`
11. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-proactive-gc-toolkit-proactive-2/bd09c0b1-783b-43e0-8e91-d14d8d647611.jsonl`
12. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-proactive-gc-toolkit-proactive-1/2da1b587-a367-4068-9139-ac34babe3ad6.jsonl`
13. `-Users-gc-Code-loomington--gc-worktrees-gascity-polecats-gc-toolkit-polecat-2/abf8066b-022e-47e2-968d-735aef67b537.jsonl`
14. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-fable-gc-toolkit-tk-fw8w1w/1d34eda6-c66d-400c-937b-c77dd7f68953.jsonl`
15. and 24. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-a9fnmtw/b1def40f-40f0-49ea-a4e6-d4ccb90e7dca.jsonl`
16. and 17. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-fable-gc-toolkit-tk-eywd7n/05d7d8cb-d80e-4f87-a5bc-9d6c2d39281e.jsonl`
18. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-vijqp9x/00947cbb-e6bd-48ae-b3d6-361ab703548f.jsonl`
19. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-m8ibue/409b8fb7-f9e2-422d-bb7b-1801f99eddac.jsonl`
20. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-polecats-gc-toolkit-polecat-5/1a90cfab-0820-4be4-b266-0bed5f8f2543.jsonl`
21. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-ghgl4x/2870ce8f-74d7-4801-a351-5a8f11a76929.jsonl`
22. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-hmhbznk/ffa6d173-74bf-4661-bc87-c13688b80ebe.jsonl`
23. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-r2zb925/83d72190-fb6e-4007-ad00-82433fa76257.jsonl`
25. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-converse-opus-gc-toolkit-tk-glv85mz/ea641b9f-f319-4234-aa60-de610911f34f.jsonl`
26. `-Users-gc-Code-loomington--gc-worktrees-gc-toolkit-polecats-gc-toolkit-polecat-3/7b1883f2-6c81-454c-b6fa-87b52c42ea86.jsonl`

## The description check

`assets/scripts/skill-needs.test.sh` carries every need marked yes above, with
bead ids elided. It scores each pack skill's name and description against each
need: the words they share, after function words and hunting words such as
"script", "usage" and "syntax" are dropped and one word ending is stripped,
each weighted by one over the number of descriptions that carry it. The
expected skill has to score strictly highest. The converse step skills do not
compete, because the converse prompt's step table loads them by name and
never by description.

Building it changed the descriptions. The first draft passed only the
capture's own need. The hunts used words the drafts lacked: "route" and "the
held subject" against "sibling" (rows 0 and 2), "parent" and "rig" (row 4),
"duplicate" and "retire" for a plain bead (row 10), "deferred-dispatch arm"
(row 11), "escalate" (row 13) and "disarm" (row 26). Each now appears in the
description that answers it. A needs row is a single act; a need that names
two skills' acts is recorded above and left out, because one expected skill
cannot be right for it.

Mutation: stripping "routing" and "sibling" from work's description fails
five needs: the capture's own and rows 0, 2, 4a and 5. Stripping
"duplicate", "retiring" and "disarming" fails rows 10 and 26.

## A live probe of the same needs

The check is a floor on vocabulary, not a model of the agent, so the needs
were also run against a model. Each run was one `claude -p` call
(claude-opus-5-5) from a scratch directory whose `.claude/skills` held the
same links a pack agent receives, gc-toolkit's skills and the core pack's,
with only read-only tools (`Skill,Read,Grep,Glob`) and one turn. The system
prompt said the model was the named agent in Gas City and checked how to act
before acting. The user message gave a one-line situation and the need, and
asked for the next step. The first tool call is the result. The control arm
used main's skills at 132909cb5, which have no work, waits, records or prs.

| Need | With the new skills | Main's skills |
|---|---|---|
| capture's own | converse-settle; on a three-turn re-run, work then converse-settle | API refusal; on a three-turn re-run, converse-settle, then a Glob for `converse-signoff.sh` and a Grep for `--route` |
| 0 | API refusal; on a three-turn re-run, work then converse-settle | API refusal; on a three-turn re-run, converse-settle, then a Glob and a Grep for `--route` |
| 1a, 1b, 2, 4a | work | converse-settle |
| 3, 5 | work | core gc-dispatch |
| 4b, 10 | work | core gc-work |
| 11 | waits | Grep for the deferred-dispatch arm |
| 12 | waits | Grep for the park gate and the arm |
| 13 | waits | Glob for `escalate.sh` |
| 15, 16 | waits | converse-hold |
| 26 | waits | Grep for disarm |
| 19 | records | converse-settle |
| 20 | prs | Glob for `pr-post.sh` |
| 22, 23, 24, 25 | prs | converse-settle |

With the new skills, every need reached its expected skill as the first skill
the model loaded. On the capture's own need, the one-turn run loaded
converse-settle first; that is the step a sitting is on, and it now points at
work. The "API refusal" rows are the model provider's safeguard rejecting the
probe prompt ("Opus 5.5's safeguards flagged this message"), not a routing
result. Without the new skills, five needs went straight to searching files,
four loaded a core skill that says how to run `gc sling` but none of the
city's conventions, and the rest loaded a converse step skill, from which the
three-turn runs went on to search files: the behavior the capture reported.
The probe cost about five dollars.

## Hunts these options do not answer

The same search found recurring hunts outside these skills' options:

- the converse sign-off's own flags (`--route`, `--ruled`, `--waiting-on`),
  about 30 sittings; the settle step now points at work for which route fits;
- which outcome words the visit close accepts, 5 sittings;
- first-reaction step mechanics (`step-close.sh` root resolution, the dispose
  script's exits and flags), about 100 first-reaction sessions;
- a polecat's hand-back to the refinery after a rework, about 60 sessions;
- a worker holding its own run with `molecule-hold.sh`, 7 sessions;
- editing a bead or PR title, about 9 sessions;
- one-offs: clearing mail, reaping pool sessions, filing upstream, and cutting
  a convoy's integration branch.
