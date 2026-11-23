---
name: "The first-read section applied blind to #1430"
description: "Use when you want the evidence that the section of gc-toolkit's correctness guidance on prose an agent acts on blocks the text #1430 first offered for review, what it costs on the text the operator accepted, or when you change that section and need to repeat the check."
---

# The first-read section applied blind to #1430

## The question

tk-34phkel is done when `docs/review-correctness.md` carries a section on the
prose agents act on, and a correctness review of #1430's pre-rework head
ee369d0b9 under it returns request-changes on the section "Hold each one to
the rig's standard" in `skills/review-demo/SKILL.md`. The city's triage
approved that head on 2026-11-07. The operator then asked about the PR's
wording and ruled "a rework that drives an editorial pass" (conversation
tk-r2eajim, as pattern tk-3vz4dd records the ruling). The rework rewrote the
section as numbered steps under "Review against the rig's standards", and the
city's correctness review approved the reworked head, 272c86db1.

The bead names a cost: more request-changes rounds on gc-toolkit prose. So the
section was also run on #1430 as merged, caf4d4979, whose text the operator
accepted.

## Method

Each review was one clean headless Claude Code run on Opus 5.5:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Users/gc/.local/bin TMPDIR="$TMPDIR" LANG=en_US.UTF-8 \
  claude -p --safe-mode --restricted --strict-mcp-config --disable-slash-commands \
  --no-session-persistence --permission-prompts none --tools "Read,Grep,Glob" \
  --model claude-opus-5-5 --max-turns 80 --output-format json < prompt.md
```

Safe mode loads no `CLAUDE.md`, memory, hooks or skills, and restricted mode
keeps every read inside the run's directory. So no reviewer saw the operator's
later corrections, which the implementing session's memory and the city's
beads hold. Subagents were not used for the same reason: a subagent loads its
session's project instructions and memory index. The last two runs used
`--output-format stream-json --verbose`, so their tool calls are on record.

Each run's directory held the tree of the reviewed commit, from `git archive`,
with its `docs/review-correctness.md` replaced by the page under test. Beside
it, `_review/` held:

- the correctness method as main has it at 539a62ca9,
  `skills/review-correctness/SKILL.md`, with its references resolved;
- the description of the anchor tk-6bbqxxw, as the store holds it (last
  updated 2026-11-09);
- the diff from the reviewed base to the reviewed commit, and the commit
  messages between them.

Every run had the same prompt, given in full at the end of this record, apart
from the reviewed commit and base.

The section was run in two texts:

- **v1**, as first written. A passage failed when the reviewer's own first
  read of it left the agent unsure what to do or sure of the wrong thing. The
  shapes were what the finding named.
- **v2**, as this branch lands it. A sentence in one of the shapes fails the
  first read, a P1 is raised on each passage that holds one, and the finding's
  check confirms it when each quoted sentence takes the shape the finding
  names. The first shape's "several conditions" became "more than one
  condition". After the runs, the shape for a coined word or a term used
  before it is defined became two items, one for each, with the same words and
  fixes, because its one sentence carried two conditions.

| Run | Page | Reviewed | Turns | Seconds | Tokens |
|---|---|---|---|---|---|
| r1 | v1 | ee369d0b9 against 9bf2e2e12 | 25 | 82 | 582k |
| r2 | main's, no section | ee369d0b9 against 9bf2e2e12 | 35 | 97 | 1,333k |
| r4 | v2 | ee369d0b9 against 9bf2e2e12 | 21 | 94 | 424k |
| r3 | v2 | caf4d4979 against e68bf418f | 30 | 149 | 1,161k |

Nearly all the tokens are cache reads, the conversation read again on each
turn.

## Results

**r2, without the section: approve, with no findings.** Its trail checked the
test pins, the parse of the demo row's new purpose line, and four cases on the
next path out. It raised nothing on the new section's prose.

**r1, v1: approve, with one P2.** The P2 was on `skills/review-pm/SKILL.md`, a
sentence restating what the demo check judges, under the work-quality rule
that writes each fact where it applies. It raised nothing on the demo skill's
new section. Its tool calls are not on record, so whether it read that
section against v1 and passed it cannot be told.

**r4, v2: request-changes, with one P1 and one P2.** The P1's locus is
`skills/review-demo/SKILL.md`, "Hold each one to the rig's standard". It
quotes three sentences:

- "When the change alters a part that many screens show, such as a theme,
  capture the screens the guidance names for such a change, and where it names
  none, each screen that shows the part." It names this as more than one
  condition.
- "A departure is a finding against the change when the change brings it, and
  also when it is already on a screen or message the change alters, because
  the check holds each screen and message the change alters whole, as the
  change ships it." It names two conditions and a reason that changes nothing
  the agent does.
- "Such a departure is this diff's to fix, so it is one of this verdict's
  findings and not a bug filed apart." It names this as saying again what the
  sentence before it said.

Its fix gives each condition its own sentence, states the departure rule as two
items, cuts the reason and the repeat, and moves the pins in
`assets/scripts/review-methods.test.sh` with the text. Its verification read
CONFIRMED, quoting the lines and the shapes on the page. Its P2, under Intent,
asked whether a change to a shared part should hold every screen that shows
the part to the standard.

**r3, v2 on #1430 as merged: request-changes, with two P1s and one P2.** Both
P1s are on sentences in the third shape, in the section the editorial pass
wrote:

- step 5's "The change ships that screen or message, so the violation is this
  change's to fix.";
- the verdict's "The PR shows only the demo, so this list is how a person sees
  what the check covered." The P1 adds that the sentence is not quite true,
  because "Show each message" puts message captures on the PR beside the demo.

Its P2, under Line by line, found that a finding in a message outside the
example or two the PR gets names, as its evidence, a capture the PR never
shows.

## What it shows

- v2 moves a clean reviewer's verdict on ee369d0b9 from approve to
  request-changes, with a P1 on the section the operator sent to an editorial
  pass. In the same setup, the page without the section approved with no
  findings, and v1 approved with one P2 elsewhere.
- v1 left the judgment to the reviewer's own first read, and r1 raised nothing
  on the section. v2 makes the shapes the test and has the check confirm the
  shape. Its finding no longer waits on the reviewer finding the sentence hard
  to read.
- v2 blocks text the operator accepted. On #1430 as merged it would have asked
  for one more round to cut two sentences that give a reason, one of which also
  made a claim the skill contradicts. The operator's later reviews ask for that
  cut. Of a sentence in #1557's guidance they asked "does that change agents
  behavior or is it just commentary?" (conversation tk-kitxol9, 2026-11-19),
  and of the header of `tools/run-tests.sh` on #1525 "Why do I need 2
  paragraphs tod escribe all the reasons Bash 5.1 is used."
  (pr:zookanalytics/gc-toolkit#1525:comment:4580456972).

## Limits

- Each text ran once on each diff, and a model's review varies from run to
  run.
- v2 was amended from r1's result on ee369d0b9, so r4 checks it on the diff it
  was amended against. r3 is its one run on another diff.
- r3 shows that v2 can block text the operator accepted. One run cannot show
  how often it will.
- The reviewers ran on Claude with Read, Grep and Glob only, with no subagents
  and no PR summary. The city's review pool runs codex, under the review
  formula's full prompt.
- Each reviewer read main's method and the anchor's description as they stand
  now, not as they stood when #1430 was reviewed. Each tree, its `AGENTS.md`
  included, was the reviewed commit's own.

## The prompt

`@BASE@` and `@COMMIT@` were replaced by each run's reviewed base and commit.

````markdown
You are the correctness check on a change to the gc-toolkit repository. Review
the change with the method you are given, and with no other review skill, and
report your verdict. Nothing is posted: your verdict is your final message.

Your working directory is the tree at the reviewed commit, exported without its
git history. You can read files only inside it. Your tools are Read, Grep and
Glob. You have no shell, no subagents and no network.

## What the review reads

- The project instructions, `AGENTS.md` at the tree's root. Every session that
  works in this repository loads them, so read them first.
- The method, `_review/method/SKILL.md`, which is the skill
  `gc-toolkit.review-correctness`, with its references in
  `_review/method/references/`. A copy of a review skill elsewhere in the tree,
  such as `skills/review-correctness/`, is part of the tree under review, not
  your method.
- The rig's guidance for this check, `docs/review-correctness.md` in the tree.
  It adds to the method and never replaces it.
- The change: `_review/diff.patch`, the whole diff of the reviewed commit
  against its base, and `_review/commits.txt`, the branch's commit messages.
- What the change was asked to do: `_review/anchor.md`, the description of the
  anchor bead.

Reviewed base:   main at @BASE@
Reviewed commit: @COMMIT@

## Test evidence

gctk recorded this line at the reviewed commit:

    test: pass (scope affected)

It is the test evidence. Run no suite.

## What this review leaves out

- No PR page and no pending PR summary is available, so skip the method's
  dimension "The PR as published".
- With no subagents, run the fresh-eyes sweep and the check of each blocking
  candidate yourself, each in a separate pass, as the method says for a
  provider that offers none.
- File nothing. Where the review would file a bug for a finding that is real
  but not this diff's, name it in the trail's `Filed:` line as
  `would file: <what>`.

## What you return

Your final message is one JSON object and nothing else, in this shape:

{"verdict": "<approve or request-changes>",
 "findings": [<each finding, P0, P1 and P2, as the method's section The verdict shapes it>],
 "trail": "<the trail's lines, from Filed: through Verification:, as the method's section The verdict names them>"}
````
