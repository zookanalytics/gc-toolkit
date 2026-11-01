---
name: How a sitting iterates on a document
description: Use when you change how a converse sitting works a document with the operator, or want the evidence behind the scaffold's form, where the big picture lives, or why this is a skill and not a formula.
---

# How a sitting iterates on a document

A sitting writes no files, so it changes a document by sending work, and each
charter-to-rework round costs a full re-review. tk-cj4ke94 asked for the best way
for a sitting to execute, and above all iterate on, a document with the operator.
This records what was chosen and what it rests on. The procedure is the
`gc-toolkit.converse-iterate-document` skill, and `docs/human-engagement.md` states
the model.

## What the operator said

- The sketch, in sitting tk-ppb4639 on 2026-10-28: "I like being able to have live
  conversations about specific items, address them, and then move on. That might
  be just you keep track of the big picture, I weigh in, and once we're settled,
  you send the file scaffold of what to change to a rework."
- What it answers, in the same turn: "Take domains, either it reworks, comes back
  iwth a new domain proposal, and I push back on XYZ that went wrong, or we flesh
  it out at the executive level here, and then we send off the rework to do the
  full change it implies."
- The question behind the format, in the same turn: "can we get it fleshed out
  enough so that an Opus (lower quality model) can execute on it effectively".
- The same wish on another document, in sitting tk-opeco4l on 2026-10-29: "And this
  spec shoudl land correct, not mostly correct and adjusted later. So let's keep
  tlaking, find all we want to change, then make the change and I'll review and
  hopefully approve."
- The placement, to the mechanik on 2026-10-30. The mechanik asked about "The way
  you sketched for a sitting to work on a document with you: settle it live, then
  do one structured rework. It has run cleanly twice. I recommend adding it to the
  converse sittings' standing instructions once native gates land." The operator
  answered "Sure".

Everything below that is not in quotes is this bead's reading, and none of it has
been ruled on.

## Decisions

**The scaffold is a `## Current state` block with no open question.** It gives each
section of the document a verb, carries the substance of each rewrite, and opens
with the rules the worker follows for what it leaves open. It composes the block
the records skill already defines, whose newest copy a sitting already primes from.
The table under Evidence says what showed the need for each part. Cost: a sitting
writes more at the end, up to about 8 KB in the runs below. The operator's sketch
says "file", and this is a block in the subject's notes, because a sitting writes
no files.

**The big picture lives on the subject's notes.** Dated rulings land as they are
made, and the newest block says what is in force. A spec the rework maintains
cannot hold it: a sitting cannot write one, so it would lag every ruling until a
rework landed, and a sitting cut short would lose what it had settled. Cost: the
notes grow, to 51 KB on the longest run, which is what the block is for. A spec
gains the decisions only as a line of the scaffold.

**No formula, and one skill loaded by name.** All four runs below went through
`--rework` and `mol-polecat-work` with nothing added on the worker's side, so a
formula would duplicate that lane and pour steps for a conversation that is not a
molecule. The loop adds no script, key or state, so it
adds no operational surface. What the existing lanes lacked is the sitting's half,
and the options for that were:

| Home | When it loads | Result |
|---|---|---|
| Text in the converse prompt, the literal reading of "standing instructions" | Every sitting in every rig, at every turn | 25 of the 246 conversations filed across the city's stores since 2026-10-15, as visit beads then, ended in a ruling rework on a design or docs PR, 13 of 104 of them in this rig's store, so most sittings would carry it unused |
| A section of `converse-continue` | Every sitting that reaches step 8 | The same, a little later |
| An option in the `prs` or `records` skill | Any role that loads them | The loop is a sitting's, and those skills' descriptions keep converse's vocabulary out |
| A skill the prompt's step table names | Only when a sitting iterates on a document | Chosen |

The census reads each store on 2026-11-01. It counts the `visit:` beads and the
reworks whose `source_ruling_bead` names one, and a PR counts as design or docs when
it changes only markdown, or, like PR #1328, a page with its spec's measuring script.
Nothing has been filed in a conversation's shape under any other title.

The choice departs from the literal words the operator answered "Sure" to, and it
follows what the operator wrote on PR #1375 on 2026-11-01, review 5726471751, about
other text: "I'm not sure this is very token efficient, not so much in content, but
in where and when it is loaded." Cost: one table row, 205 bytes in each of the three
converse renders, and one short description line in every agent's skill list.

**The word stays "scaffold".** It is the operator's. The pack also says "review
scaffolding" and has `scaffolding-sweep.sh`, which name something else, so the skill
says what a scaffold is where it first uses the word.

## Evidence

### The runs

Each row is a sitting that settled a document with the operator and then sent one
rework. Only the first two carried the name scaffold, and calling the other two the
same shape is this bead's reading: a numbered list of nine decided changes on
PR #1352, and three rules with the page's fate on PR #1328.

| PR | Sitting | Operator's first to last turn | Operator turns | Rework filed to landed on the branch | Review after it | Findings after it |
|---|---|---|---|---|---|---|
| #1345, design | tk-ppb4639 | 3.5 h | 10 | tk-zizrql6, 65 min | 4 approve | 0 |
| #1345, design | tk-weluos5 | 1.7 h | 5 | tk-nrtvgdz, 56 min | 4 approve | 0 |
| #1352, spec | tk-opeco4l | 0.8 h | 7 | tk-qznlq5x, 54 min | 3 approve, 1 request changes | 1 |
| #1328, docs page | tk-v7c6973 | 2.4 h | 6 | tk-04b7hx0, 102 min | 4 approve | 0 |

The finding on PR #1352 was a gap in the design that the ruling had not covered, a
Delivery's own park left open at its close, and not a line the rework failed to
carry. Times, verdicts and counts are from the store. Operator turns are from each sitting's
transcript, leaving out task notifications, system reminders, skill bodies and the
role prompt, and read by eye for the two PR #1345 sittings. The two PR #1345
reworks ran on claude-opus-5-5 workers, read from their transcripts, and those
sittings ran on converse-fable.

### What the block carries, and what showed the need

| The block carries | What showed the need |
|---|---|
| A verb for every section, and a closed set that says so | The first scaffold named the agent class by listing four verbs and did not name `review`. The rework gave `gctk review checks` the agent class. All four review checks approved it, and the audit that opened the next sitting found it, the one deviation in ten items. |
| The substance of each rewrite, an accepted proposal's text included | The second scaffold's edit 8 named the naming rule tersely. Its worker said "The naming rule (edit 8) needs the operator's exact wording before I apply it across the verb table" and read the sitting's transcript, whose path its own transcript names 27 times. The first scaffold's worker's names it none. |
| A rule with its test, run on every row | The naming rule's test, "does a native call exist this could be mistaken for, and would its answer ever differ?", let the worker check each verb against `gc --help` and bd's command list and rename one the sitting had not named. |
| Lines that decide | The second scaffold's edit 2 ended "or defend the residual explicitly", and edit 4 "Reclass or defend each". The worker made those calls, and its self-review then had to correct the window it wrote for edit 2. |
| Facts to check, not to transcribe | The first scaffold copied "three changed live answers" from an old note, and the design had two. The accepted naming proposal said `arm` reuses gc's word, and Gas City has no dispatch primitive of that name. Both workers re-derived these and said so on the anchor. |
| Each choice of form, listed on the bead | Both workers listed theirs on the anchor. A review reads them there, because `mol-review` prints `gc bd show` of the anchor as it gathers. |
| A stop through a human gate | The runs' blocks said a stop "says so on this bead". The polecat doctrine holds that a run ending needs a gate behind it, so the block says that. No run had to stop. |
| Self-review against the block, with the worker's notes naming it | The first rework's self-review did this of its own accord. The block asks for it, because no review check compares a rework with its scaffold. A self-review session starts fresh and workspace-setup clears the `rejection_reason` that names the block, so it finds the block through the worker's notes. Both workers had written that note unasked. |
| The commit its line references read at | Both scaffolds named it, and the audit's line references read at the rework's head. |

### Against charter-to-rework rounds

The bead's stated cost is rounds. Counts for design and docs PRs in the same weeks:

| PR | Ruling reworks | Review reworks | PR-comment reworks | Findings, with the operator's own in brackets | Created to landed |
|---|---|---|---|---|---|
| #1345 | 2 | 1, before the first sitting | 0 | 1 (0) | 2.8 days |
| #1352 | 1 | 2, one before the sitting | 0 | 3 (0) | 1.8 days |
| #1328 | 1 | 0 | 0 | 0 (0) | 0.9 days |
| #1305 | 5 | 9 | 0 | 18 (0) | 3.2 days |
| #1298 | 3 | 6 | 2 | 37 (31) | 5.7 days |
| #1277 | 1 | 1 | 3 | 19 (18) | 1.2 days |
| #1220 | 1 | 4 | 1 | 18 (14) | 1.7 days |

This shows a direction and no more. The documents differ in subject and size, and
the larger ones drew more review: PR #1305's design is 2,966 lines at main and
PR #1298's 1,226, against 521 and 463 for PR #1345's page and design on their
integration branch, and 591 for PR #1352's and 388 for PR #1328's at main. The last ruling round on each of PR #1305 and
PR #1298 also carried a settled `## Current state` block, and each was still followed
by two review reworks. So a settled block does not by itself end review rounds on a
large design.

## The load probe

Moving text out of a prompt risks a load that never happens, so this measures
whether a sitting loads the skill and what it then does. Each run puts the rendered
converse prompt in the first user message, followed by a case saying steps 1 to 5
ran and giving the operator's turn. It runs
`claude -p --tools "Skill,Read,Grep,Glob,Bash" --setting-sources project --strict-mcp-config --max-turns 4`
from a fixture holding only the skills, with `GC_*`, `BEADS_*` and `CLAUDE_*` unset
and auto memory off, and with 10 turns for the send case. Codex runs
`codex exec -s read-only -m gpt-6.1-sol` with the skills under `.agents/skills`. A
load is a Skill call, or a Codex command that reads the `SKILL.md`. In the Claude
arms 302 of 311 shell calls came back refused, and the other nine were `pwd` and
`ls -la`. Codex ran read-only and outside any city, where `gc bd` answers "not in a
city directory". So nothing was sent. 67 Claude runs cost $16.96, beside 6 Codex
runs.

| Case | The operator's turn | Opus | Fable | Codex |
|---|---|---|---|---|
| D1 | tk-ppb4639: "ZERO chance this gets approved as written" | 7 of 7 | 2 of 2 | 2 of 2 |
| D2 | tk-opeco4l: "let's keep tlaking, find all we want to change" | 4 of 4 | 2 of 2 | 2 of 2 |
| D3 | tk-v7c6973: six numbered answers to a page's flagged items | 4 of 4 | | |
| D4 | tk-weluos5: one verb's overlap with native calls | 4 of 4 | | |
| D5 | Written for the probe: go through a page with no PR, then rewrite it | 6 of 6 | | |
| N1 | Written for the probe, a code PR: rename a flag and land it | 0 of 4 | | |
| N3 | Written for the probe, a code PR: where does this stand? | 0 of 3 | | |
| N4 | Written for the probe, a docs PR: not needed, close it | 0 of 3 | | |
| N5 | Written for the probe, a code PR: why does this retry three times? | 0 of 3 | | |
| N2 | Written for the probe, a docs PR: one stated fix to one number | 2 of 5 | 2 of 2 | 1 of 2 |

N2 is the one miss. It is a document with one plain change, and the skill says such
a ruling needs none of this. All nine N2 runs took that path whether or not they
loaded it: no block, and where a run reached the sign-off, a one-line ruling. So a
load there costs one read of the skill's 7.8 KB and changes nothing.

The load cases ran on the skill's first two texts, and the description and table
row that decide a load are the same in all three texts below.

The send case hands a sitting a five-section page and five settled rulings, one an
accepted proposal and one in the operator's words, then "Yes, send it." Base is the
prompt and skills at 451687e63. The branch rows span three texts of the skill. The
first took 4 Opus and 2 Fable runs. The second moved one paragraph and changed two
clauses, and took 3 Opus runs. The committed text took 3 Opus and 2 Fable runs. It
also says what a scaffold is before first using the word, reads the whole block
back, and adds the lines that name the block for self-review and the next sitting.

| Arm | Writes a block before the sign-off | A verb for every section | Accepted text and operator's words in it | Worker's rules in it | Ruling line names the block |
|---|---|---|---|---|---|
| Branch, Opus | 10 of 10 | 10 of 10 | 10 of 10 | 10 of 10 | 10 of 10 |
| Branch, Fable | 4 of 4 | 4 of 4 | 4 of 4 | 4 of 4 | 4 of 4 |
| Base, Opus | 1 of 4 | 0 of 4 | 1 of 4 | 0 of 4 | 0 of 4 |

On base, three runs put the decisions in one long `--ruling` line, and the fourth
wrote a block with neither verbs nor rules and did not name it. That line is also
each gate's resolve reason, and workspace-setup clears `rejection_reason` once its
merge concludes, so decisions carried only there leave the rework's record. This
measures the sitting's half. The worker's half is the runs above.

## Limits

- **Four rounds on three documents, under one operator, within one week.** Nothing
  here is a controlled comparison.
- **A clean review is no proof the scaffold was carried.** The four approvals at
  8fb013e8 sat beside one deviation and five soft spots that the next sitting's audit
  found. That audit runs only when the operator engages the document again. The
  block's self-review line covers the first read, and on PR #1345 a self-review
  already ran and missed that deviation.
- **Live time is the price.** The rounds took 3.5 h and 1.7 h from the operator's
  first turn to the last, though most of that was the sitting and its subagents
  working, at 10 and 5 operator turns.
- **No worker below Opus was measured.** Opus is the tier the operator named.
- **A document at `pre_open_gate` has no route here.** `converse-rework.sh` refuses
  any anchor not at `pull_request`, and no run met this case.
- **The rework route moves with the review rebuild.** `rework-child.sh`, which
  `--rework` runs, is on the deletion plan under tk-1tfzr71.22, so the skill's send
  line changes when the sign-off's does. No file this branch changes is on the plan.
