---
name: A/B probe of the po's opening from a rig's product goals
description: Whether the po's prompt and backlog-refinement skill make a sitting open from the rig's docs/product-goals.md and the docs it draws its goals from, and, in a rig with no such page, ask the operator once through the PM check's request. Read it to check the numbers in the commits and the PR summary, or to rerun the probe after changing how a po sitting opens.
---

# A/B probe of the po's opening from a rig's product goals

The bead's done-when has three parts. A po sitting in this repository opens from
`docs/product-goals.md` and `docs/foundation.md` without asking. In a rig with no
such page, the po asks once, and the answer lands in that rig's
`docs/product-goals.md`. Nothing tells the po to write a target into `AGENTS.md`.
The first sitting under the old wording asked the operator what this rig's work
is for, so the change has to be shown to change what a sitting does when it
opens. The probe runs that opening under each wording.

## Method

Each run is one `claude -p` session standing in for the first turn of a po
sitting. The arms are revisions of the po's prompt and skill:

- **old**: `origin/main` at a4ee5ae43, which opened from "the target the rig's
  `AGENTS.md` states".
- **first**: 2f5193328, this branch's first wording.
- **second**: 514821709, which gives the docs the goals page draws from a
  sentence of their own.
- **third**: 20524b5b1, which makes the pointer to the skill an act to take
  before asking the operator anything.
- **final**: 0acdac690, whose opening sentence names those docs as part of what
  a sitting opens from. This is the wording the branch ships.

Each arm's prime is its own commit's render of the po,
`generated/seed-audit/agents/po.md`, with the city root filled in, appended to the
system prompt. The session's home holds that commit's
`skills/backlog-refinement/SKILL.md` as its `gc-toolkit.backlog-refinement`
skill, and a `CLAUDE.md` that loads the rig's `AGENTS.md`, as a po's home does.

The cases:

- **This repository, backlog refinement.** The rig root is this repository's
  checkout, whose default branch carries both `docs/product-goals.md` and
  `docs/foundation.md`.
- **A rig with no goals, backlog refinement.** `rig-a` is a git repository built
  for the probe. It has an origin and an `origin/HEAD`, an `AGENTS.md` that
  describes the rig and states no goals, and neither `docs/product-goals.md` nor
  `docs/review-pm.md`. Its prime is the same render with the rig's name, root and
  id prefix replaced.
- **A rig with no goals, portfolio sync.** The same rig, in a sitting whose method
  is not the skill, so only the prompt's pointer sends the po to it.
- **A recorded answer, portfolio sync.** The same rig, but its request for the page
  already carries an earlier sitting's answer in its notes and is routed to a pool.

The operator's line is "Let's start a backlog refinement sitting." or "Let's do a
portfolio sync.". Stubs stand in for the store and for writes, and each logs every
call. The `gc` stub answers the queue read with two held beads for each rig, the
epic read with none, and the request probe with `[]`, or with the routed request
in the last case. It refuses every write. The `git` stub passes read-only
subcommands to git and refuses the rest, and the `gh` stub answers `pr list` with
`[]`. Each run is:

`claude -p --model claude-opus-5-5 --setting-sources project --strict-mcp-config --tools "Bash,Read,Grep,Glob,Skill" --permission-mode bypassPermissions --max-turns 14 --no-session-persistence --output-format stream-json --verbose --append-system-prompt-file <prime> "<operator line>"`

It runs from the session's home, in an environment holding only `HOME`, `USER`,
`PATH` with the stubs first, `TERM`, `LANG`, `SHELL` and
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. There are three runs to a cell. The 51
counted runs cost $9.19, and one dry run of the first wording, not counted, cost
$0.21.

The reads are counted from each run's tool calls and the stubs' call log. Whether
a run asked, and where it says the answer goes, are counted by reading its final
message, beside the sentence the count rests on. A regex scorer missed two asks
that were not phrased as questions, and reading found them.

## Result

Each cell counts runs out of three. A blank arm was not run on that case.

| Case | Arm | Looked for the goals page | Read the foundation | Opened `AGENTS.md` | Looked for the request | Asked what the rig's work is for | Where it says the answer goes |
|---|---|---|---|---|---|---|---|
| This repository | old | 0 | 0 | 3 | 0 | 3 | `AGENTS.md`, 3 |
| | first | 3 | 0 | 0 | 0 | 0 | no answer asked for |
| | second | 3 | 3 | 0 | 0 | 0 | no answer asked for |
| | third | 3 | 2 | 0 | 0 | 0 | no answer asked for |
| | final | 3 | 3 | 0 | 0 | 0 | no answer asked for |
| No goals, refinement | old | 0 | | 3 | 0 | 3 | `AGENTS.md`, 3 |
| | first | 3 | | 0 | 3 | 3 | the request for the page, 3 |
| | second | 3 | | 0 | 3 | 3 | the request for the page, 3 |
| | third | 3 | | 0 | 3 | 3 | the request for the page, 3 |
| | final | 3 | | 0 | 3 | 3 | the request for the page, 3 |
| No goals, portfolio sync | old | 0 | | 3 | 0 | 3 | `AGENTS.md`, 3 |
| | second | 3 | | 0 | 2 | 3 | the request, 2; the page by its own words, with no look for the request, 1 |
| | third | 3 | | 0 | 3 | 3 | the request for the page, 3 |
| | final | 3 | | 0 | 3 | 3 | the request for the page, 3 |
| Recorded answer, portfolio sync | old | 0 | | 3 | 0 | 3 | `AGENTS.md`, 3 |
| | third | 3 | | 0 | 3 | 0 | opened from the recorded answer, 3 |
| | final | 3 | | 0 | 3 | 0 | opened from the recorded answer, 3 |

The old arm reproduces the sitting that prompted the bead in every case. It opens
`AGENTS.md`, finds no target and asks: "The rig's instructions (`AGENTS.md`) don't
state a target. ... I'll file a task to write it into `AGENTS.md` so no later
sitting asks again."

Under the final wording, every run in this repository opens from the goals and asks
nothing, as in "this hits the goal that the board shows what actually happened".
Every run in a rig with no goals looks for the request before it asks, and says
the answer goes there: "Once you agree on the wording, I'll file it as one request
so a normal PR writes the goals page and no later sitting asks again." Every run
whose request already carries an answer opens from it, and neither asks again nor
sends the routed request a second time: "your words on the goals-page request
... A polecat already has that request, so I didn't ask you again or send it a
second time."

Each revision answers what the arm before it missed:

- The first wording put the cited docs and the `docs/review-pm.md` fallback in one
  sentence. No run read `docs/foundation.md`, so the second wording gave those
  docs a sentence of their own.
- In the second wording, the pointer said the skill is how the operator's words
  reach the page. In a portfolio sync one run asked at once, with no look for an
  earlier answer, which would ask again in a rig whose request already carries
  one. The third wording makes the skill an act to take before asking anything.
- Under the third wording, one run of three in this repository read only the
  goals page, which summarizes the foundation's goals. The final wording's
  opening sentence makes those docs part of what a sitting opens from.

The one call any stub refused was a read: `git remote get-url origin`, which the
`git` stub refuses with every other `remote` subcommand. No run tried a bead
write, a sling or a change to a file.

## What the probe does not show

- It covers only the opening turn: what a sitting reads, whether it asks, and what
  it says it will do with the answer. The writes that follow the operator's
  agreement are not run: the append, reopen or create on the request, and its
  place or sling. The stubs refuse writes, and every run ended its turn at the ask.
- The prime arrives appended to the system prompt, not as the first message a
  real start sends. One model ran every session, and three runs to a cell shows a
  direction, not a rate.
- The rig with no goals is a fixture, and its store is a stub holding two held
  beads. A real queue changes how much a sitting reads before it speaks.

## Rerunning it

The harness was three short scripts outside this repository. A setup builds the
fixture rig, each arm's prime and skill from its commit, and the stubs. A runner
starts one session for an arm, a case and a run number, and a scorer tabulates
each run's reads. The Method above is enough to rebuild them, and the call that
starts each session is quoted there.
