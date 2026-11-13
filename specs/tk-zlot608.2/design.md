---
name: Agent memory as the learning loop's second intake (tk-zlot608.2)
description: The design by which the feedback distiller reads agent memory notes beside the loop's reports, judges each note by the operator's three questions, groups what notes show onto feedback patterns, and removes a note once its pattern closes or it holds nothing worth keeping, and the guidance that tells agents what goes in memory and what goes in a report. Read it to build or review the memory intake, or to judge what becomes of a memory note.
---

# Agent memory as the learning loop's second intake

Agent memory and the learning loop's reports are two intakes with one judge. A
memory note holds something that should change the next agent's behavior. A
report, an observation bead, holds something to be evaluated. The loop's
distiller already judges the reports. It also reads each memory note where it
is, by the operator's three questions, and groups what the note shows onto the
same feedback patterns, so a lesson an agent wrote down and a correction an
agent reported meet in one judgment. A note stays in memory while its pattern is
open. It leaves once the pattern closes and its fix has landed, or as soon as
the distiller finds nothing in it worth keeping. No note leaves because of its
age.

The backlog record, [specs/tk-zlot608.1/report.md](../tk-zlot608.1/report.md),
is the worked example of reading notes by the three questions.

## What the operator ruled

The operator ruled in conversation tk-1amy8sd on 2026-11-11:

> so yes empty, yes use it as an intake, but don't make it a full on stream,
> have some level of LLM based analysis occur before anything becomes an actual
> learning to feed into the learning process.

In the same turn they said "I think there is value in agents that know how to
write memory and do it well" and "not everything that gets written to memory
even needs a lesson observation", and they gave the three questions the analysis
asks:

1. "Which memories are effectively point in time knowledge that can go away"
2. "Which memories are clear examples of vague or misleading directions that
   can be fixed with effectively zero increase in instruction size. These can
   be fixed even if they were only recorded once."
3. "Which memories are indication of something structurally wrong that needs a
   larger fix. Agents regularly getting confused where a script or more robust
   instructions would have them do the right thing the first time. This is
   where we are balancing scope of fix against severity, since the claim here
   is something that is off."

Reviewing this design's first draft (review 5882522195 on PR #1474), they asked
whether the reviewing agent has the guidance to remove unnecessary rules, whether
a rule expected to be long-term should stay until something permanent replaces
it, and whether the memory-to-learning cycle had a bigger strategy. In the
sitting that followed (conversation tk-iyhd38d, 2026-11-13), they proposed
keeping "all not yet scheduled, still evaluating notes, or ungrouped notes, as
actual memories", "dropping the need to do a proposed learning and then
aggregate those again". They held that
there are "still two flows, memory notes + reported learnings", because without
reports "we have no way for an agent to say, this might be worth doing, but I
need approval to do it", nor to report a "do not do X" that may mean never or
only in that context. They ruled:

> I think memory is things that should change the next agents behavior and a
> report is an observation to be evaluated, or something roughly along those
> lines. And yes, the two intakes, one judge feels right.

The rest of the ruling is the sitting's framing, which the operator took, and
the close reason of gate tk-8z75eqq records it. The distiller is the one judge,
under the pattern lifecycle that PR #1486 brings. A note stays in memory while
its pattern is open and leaves when the pattern closes or when the judge finds
nothing worth keeping in it, with no age limit. The three questions are how the
judge reads a note, and an unneeded rule is dropped by the distiller's
retirement test. A list of note names and hashes, with each removed note's text,
takes the place of a copy of the whole directory. Everything else on this page
is this design's proposal.

## 1. Two intakes, one judge

**What goes where.**

- A memory note holds something that should change the next agent's behavior.
  Claude Code loads each memory directory's index into every session that has
  memory, and a session reads a note when it needs one, so a note steers agents
  from the moment it is written, with only its writer behind it.
- A report is an observation bead
  ([feedback-learning.md](../../docs/feedback-learning.md)). It holds something
  to be evaluated: corrective feedback from a review, a rework or the operator,
  feedback whose reach the writer cannot tell, and a change that needs approval.
  It steers no agent until the loop decides it.
- The state of open work goes on its bead's notes, and what the pack already
  says goes nowhere.

**One judge.** The distiller (`mol-feedback-distiller`) judges both intakes. Its
`feedback-distiller` order fires once a day, the run does its work only in the
pack's home rig, and it already reads every rig's store for reports. In the same
run it reads the memory directories of the city's rigs and its root (section 7),
judges each note it has not read before, and groups what the note shows onto the
feedback patterns the reports are grouped onto. The patterns stay in the home
rig's store, under the lifecycle PR #1486 (tk-ltcv43q) brings: a pattern is
closed once resolved, waits on its follow-up through a `blocks` edge, or is
deferred with a date while it gathers evidence. Nothing turns a note into a
report first, so no lesson is grouped twice, and no judge keeps findings of its
own.

**A step of the distiller, not a pass of its own.** The ruling left this choice
to the design.

- One run judges both intakes, so a note and a report about one problem meet in
  one judgment, each pattern has one writer, and the distiller's dedup against
  work in flight and its cap on beads filed per run cover what both show.
- A pass of its own would write the same patterns from a second formula, with
  its own filing, dedup and cap, and two passes could decide one pattern at once.
  That is the second judge the ruling removed.
- The memory directories are on the host the distiller runs on.

The cost is the distiller's size. Every one of its steps sits near the bound a
step must render within when a hook delivers it, 9,000 bytes
([pack-authoring.md](../../docs/pack-authoring.md)): at PR #1486's head
(7feb0da0f) the descriptions of load-and-gate, judge-and-cluster and
file-and-dispatch run 7,612, 8,910 and 8,775 bytes.

**Where the work lives.**

- The mechanics are one script, `assets/scripts/memory-intake.sh`. It places
  each memory directory, lists the due notes, records each judged note, removes
  notes and edits the index and collection notes under the checks in section 4,
  rewrites the guidance block, and reports a place it cannot resolve.
- The judging method is a section of the `learning-distill` skill, which the
  distiller reads from origin/main as it reads the rest of its rubric.
- The formula gains one step, `read-memory`, run first, which holds only calls to
  the script. The script makes the home-rig check that load-and-gate opens with,
  so the step changes nothing on a rig that only imports the pack. It removes
  the notes whose wait has ended, rewrites the guidance block and lists the due
  notes for the later steps. load-and-gate's cadence gate
  counts the due notes, judge-and-cluster judges them beside the pending
  observations, and file-and-dispatch has the script record each judged note and
  remove the ones the judge dropped. Each of those steps gains a clause or a
  call, traded for weight the build moves into the script or the skill, since a
  step that grows past the bound fails `formula-step-size.test.sh`.

## 2. How the judge reads a note

The judge reads each due note, or each entry of a collection note that carries
text of its own (section 4), and gives it one outcome. The three questions are
how it reads.

- **Point-in-time** (question 1): finished work, something that no longer holds,
  something the pack already says, or the state of a moment that has passed. The
  note is dropped.
- **Live work**: the state of work still open. Its bead takes, in one append,
  what the note says that the bead lacks, and the note is dropped. A ruling
  about one case lives with that case the same way. A note about a moment that
  has not passed, with no bead to carry it, stays due for the next run.
- **Wording fix** (question 2): a vague or misleading direction that a change of
  about zero size fixes, as the backlog's were
  ([report.md](../tk-zlot608.1/report.md#wording-fixes)). It is filed even when
  seen once, as the question allows. The note joins or seeds its pattern, and
  the pattern waits on the bead that carries the fix.
- **The rest joins a pattern** (question 3 and what it leaves): something off
  that a script, a check or a more robust instruction would fix, and a rule or a
  recipe agents keep needing that the pack lacks. The judge weighs it as it
  weighs a report, by the rubric's judgments and its gates on promotion, and
  writes its reasoning on the pattern. Question 3's balance of a fix's scope
  against the problem's severity is part of that reasoning, and no table stands
  in for it.
- **Not worth keeping**: a rule the note states is asked the retirement pass's
  questions, whether it still binds and whether something the pack carries
  subsumes it. A rule current agents follow untold, or one the pack already
  carries, is dropped, and so is anything else the judge finds nothing worth
  keeping in.

**A note on a pattern.** The pattern's evidence names the note by its memory
directory, its name and the hash the judge read. A note is one occurrence in its
writer's voice, and a note that cites an event a report already carries counts
with that event once. A pattern backed only by notes meets the loop's first gate,
which holds back a rule only agents reported until the operator endorses it or
another voice backs it, so notes alone never promote a rule into a carrier every
agent pays for. A structural fix and a wording fix go to a bead, which that gate
does not guard. A ruling a note attributes to the operator is checked against the
source the note gives, as the distiller checks the voice behind a self-reported
observation. The note is the operator's voice only when that source holds their
words. Otherwise the rule is the writer's own and never reaches the operator as
theirs. The pack's files cite a note only as `memory`, because a note's directory
or its name can name a rig the pack's public files must not name.

**Where a fix goes.** The judge files a pattern's follow-up the way the
distiller files every follow-up, held for the operator's placement
([steering.md](../../docs/steering.md#the-intake-rule)), and takes these routes
first:

- A fix in the words of an adopted learned rule joins that rule's pattern, and
  its follow-up is the distiller's update proposal.
- A fix in a file the deletion schedule retires is appended to the notes of the
  retiring bead, which the pattern waits on (AGENTS.md).
- A problem an open bead already carries is appended there as more evidence, and
  the pattern waits on that bead.
- A problem in software no rig of the city owns becomes an upstream finding by
  the `gc-toolkit.external-issue` skill, and the pattern waits on the finding.
- A fix in another rig's repository is that rig's work, as the external-issue
  skill says of a problem a rig of the city owns. The judge files it in that
  rig's store with the `gc-toolkit.work` skill, held for placement, or appends it
  to the open bead there that carries it. The note waits on that bead and joins
  no pattern, because a pattern's `blocks` edge can name only a bead in the
  pattern's own store.

One run's wording fixes in one repository are one bead, so one PR carries them
and they count once against the distiller's cap.

## 3. When a note leaves memory

A note leaves in one of two ways, and never because of its age.

- **When the judge drops it.** A point-in-time note, a live-work note once its
  bead has what it lacked, and a note with nothing worth keeping leave in the
  run that judged them, once the run has carried what each shows to where it
  goes.
- **When what it waits on is done.** A note on a pattern leaves once the pattern
  closes and every follow-up of the pattern that closed on a merge has landed. A
  note that waits on a bead in another rig's store leaves once that bead closes
  and, if it closed on a merge, has landed.

A follow-up has landed when its merge is on its repository's default branch.
Closing is not enough, because a follow-up placed under an integration effort
closes when it lands on the effort's branch: tk-jvl45ot closed on 2026-10-31 at
14:50Z with `merged_target` set to `integration/tk-nrsd2fd`, and the effort's
PR, #1379, merged at 22:48Z. So a follow-up merged into an effort's branch has
landed once the effort's landing bead has merged into the default branch. A
follow-up that closed with no merge, such as a proposal the operator vetoed,
ends the wait at its close.

A note on a held pattern stays through the pattern's deferral, which lasts
`pattern_defer_days` (90). When the window ends with no recurrence, the
distiller dismisses the pattern and the note leaves. When the lesson recurs, the
distiller judges the pattern again on the new evidence, and the note stays while
the pattern is open. A lesson that comes back after its notes left is new
evidence on its closed pattern, which the rubric's recurrence bar decides
whether to reopen.

The operator's two concerns, in that cycle:

- **Removing unnecessary rules.** The retirement test drops a rule in memory that
  agents no longer need, as the distiller already asks of each adopted rule
  (skills/learning-distill/SKILL.md, Retirement questions).
- **Keeping a long-term rule until something permanent replaces it.** A note
  worth keeping stays while its pattern is open, which lasts until the pattern's
  fix has landed, or until its deferral passes with no recurrence.

The cost is that memory shrinks only as fast as the distiller decides and fixes
land, and until a rule's replacement lands, a rule the judge kept steers agents
with only its writer behind it.

## 4. The list, and how a note is removed

A memory directory is the directory of note files Claude Code keeps for one
project (section 7). It is not a bead store.

For each memory directory, the run keeps two things in the pack's state
directory, `<city>/.gc/runtime/packs/gc-toolkit/memory-intake/<directory key>/`,
where `<directory key>` is the directory's real path with each `/` and `.` as
`-`:

- **The list**, one row for each note or entry the judge has read and kept: its
  name, the hash the judge read, the date it was judged, and what it waits on,
  its pattern or the bead in another rig's store.
- **Each removed note's text**, as it was when removed, filed under its name and
  hash. Nothing prunes these.

A note is due when the list does not hold it at its current hash, so the list is
all the next run needs of the last. The run keeps no copy of the directory and
no findings record. The town repository ignores `.gc/`, and no session loads it.

Other writers and other runs:

- Every Claude session in the city can write a memory directory while a run
  works. A note is removed only while its hash still matches the hash the judge
  read, and a note changed since is due again.
- The index, `MEMORY.md`, holds pointers and is never judged. Claude Code loads
  its first 200 lines or 25 KB into every session. The run takes out each line of
  the index or a collection note that links a note no longer in the directory.
  That includes the 313 links in collection notes to notes the backlog removal
  took out (tk-zlot608.3).
- A collection note (`hub-*.md`) is judged entry by entry, as the backlog record
  sorted it. A line that links a whole note stands for that note. An entry with
  text of its own is judged like a note and keyed on the list by its own hash.
  When such an entry leaves, the run takes its lines out, and it removes a
  collection note that has no entries left.
- A link inside a whole note's own text stays as written.
- An edit to the index or a collection note is written only if the file is
  unchanged since the run read it. Otherwise the run reads it again.
- Two distiller runs can overlap, so the script holds a lock on each directory
  while it writes the list, removes notes and edits the index.

## 5. Which notes a run reads

A note is due from the first run that finds it, new or changed since the judge
read it. The judge's own question, whether a note can go away, decides whether a
fresh note leaves, so no age decides when a note is read.

Due notes are pending like reports. They count toward the distiller's cadence
gate beside the pending observations, and a gated run leaves them due. With
about 50 notes a day the gate opens on nearly every run, and it already sees
steady volume from reports: this rig's store took in 186 observations from
2026-11-01 to 2026-11-13. While due notes remain, a hold whose window ends is
deferred to the next run, as the rubric defers one while observations remain
unjudged, since a due note may be its recurrence.

A run reads at most `memory_notes_per_run` due notes, oldest first, and the rest
stay due. The proposed default is 200. The city's memory directories took in
about 360 notes in the week to 2026-11-13, about 50 a day, so a run reads the
day's intake and about 150 of the backlog. Read-only subagents may read batches
of due notes and return what each says, as they did for the backlog record (71
batches for 2,161 units). The judge decides each note itself and makes every
write.

**The first runs.** The city's memory directories hold about 2,070 whole notes
today, beside their indexes and this rig's collection notes: about 1,040 in this
rig's, 470 in the city root's and 560 across the other rigs'. The backlog record
found 741 entries with text of their own in this rig's collection notes. At about
150 a run past the day's intake, the backlog is read in about three weeks.
Memory shrinks first by the notes the judge drops and then as patterns close.
The backlog record's structural findings need no seeding, because the judge
reads the notes behind them and groups them as it goes.

## 6. How agents are told what goes in memory

The guidance sits at the top of each memory directory's index, which loads into
every session that has memory and which an agent edits after writing a note.
`read-memory` rewrites the block each run from one file in the pack, so its
words change only through a reviewed PR. It adds nothing to the pack's prompts,
and it reaches no agent whose memory is off. **Proposed** words, for the unit
that builds them:

```markdown
<!-- memory-intake: rewritten from the gc-toolkit pack each run -->
A note here holds something that should change the next agent's behavior. The learning loop reads each note, leaves it here while the lesson it shows is being judged or fixed, and removes it once that lesson is settled or the note holds nothing worth keeping.
Write a lesson so it can be acted on: what you did, what happened, the instruction, command or script that led there, what it cost, and whether it happened before.
A rule is the operator's only with their words and where they said them. Otherwise it is yours, and the note says so.
What is to be evaluated goes in a report, an observation bead the gc-toolkit.records skill files: corrective feedback from a review, a rework or the operator, feedback whose reach you cannot tell, and a change that needs approval. The state of open work goes on its bead's notes. Leave out what the pack already says.
<!-- /memory-intake -->
```

What a note carries so the judge can act on it:

- A lesson gives the act, what happened, the instruction, command or script
  behind it by file and section or command line, the cost, and any earlier time
  it happened. With these the judge can find the words to fix (question 2), or
  weigh a problem against its fix (question 3).
- A ruling gives the operator's words and where they gave them.

The block's cost is that an agent may edit it between runs, and the next run
restores it. The other place for it is a fragment in every Claude prompt, which
costs each session about the same text, sits away from the act of writing, and
reaches the Product Owner, whose memory is off.

## 7. The memory directories, the Product Owner and agents without memory

**Where a memory directory is.** The run places each directory as Claude Code's
storage-location rules do
([gas-city-search.md](gas-city-search.md#find-a-memory-directory)), from the
inputs Gas City starts each rig's Claude sessions with:

- Memory is off when the environment sets `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`.
  It is also off when the highest settings level that sets `autoMemoryEnabled`
  sets it false, unless the environment sets that variable to `0`, which turns
  memory on.
- Otherwise the directory is the `autoMemoryDirectory` of the highest settings
  level that sets one. The levels, highest first, are managed settings, the
  `--settings` file Gas City gives each Claude session it starts, the
  checkout's local settings, its shared project settings, and the user settings
  in the config directory. A value that starts with `~/` is under the session's
  home.
- Otherwise the directory is `<config dir>/projects/<project>/memory/`. The
  config directory is `CLAUDE_CONFIG_DIR`, or `.claude` under the session's home.
  `<project>` is `CLAUDE_CODE_PROJECT_DIR_NAME` when that is set beside
  `CLAUDE_CONFIG_DIR` and is 1 to 64 letters, digits, hyphens or underscores.
  Otherwise it is the checkout's path with each character that is not a letter
  or a digit as `-`.

The environment, the home and the user settings the run reads are its own
session's. Gas City starts every rig's Claude sessions as it starts the run, so
they match unless an agent's provider or its own configuration sets a different
environment, or a launch command gives each account a home of its own, as this
host's does. The run compares paths by their real path, because those homes link
their `projects` directories to one place, so one directory shows under several
paths.

**Which directories the run reads.** It reads each rig's own directory, the one
named for its checkout or the one the rig's own local or shared project settings
place, and the city root's. A directory the city's `--settings` file places is
one for every rig and the city root, and the run reads it once. A directory
placed at the user or managed level, or named by `CLAUDE_CODE_PROJECT_DIR_NAME`,
is one directory for every project those sessions start in, and sessions the
city does not run can share it, so the run reads none of it and reports it as a
place it cannot resolve. One placed at the user level, or named by the variable,
comes under the run once the city's or the rig's own Claude settings set
`autoMemoryDirectory`: both rank above the user level, and a directory they set
takes the place of the one the variable names. A directory keyed to a path
outside the city's rigs and its root belongs to sessions the city does not run,
and the run reads none of it.

**An absent directory, and a place the run cannot resolve.** A directory is
absent when memory is off or nothing exists where it is placed, and the run
changes nothing there. The run cannot resolve a place, and removes nothing
there, when:

- a settings file at one of the levels does not parse, the deciding
  `autoMemoryDirectory` is neither an absolute path nor one that starts with
  `~/`, or the checkout's converted path passes 200 characters, where Claude
  Code appends a hash the pages do not define;
- a settings file the repository supplies places the directory while
  `permissions.blockReadsOutsideWorkingDirectories` is on, so Claude Code
  neither loads nor writes memory there. That is the rig's shared project
  settings, or its local settings when git tracks them or `.claude` is a link;
- the directory is placed at a level the run does not read (above).

The run files one finding for each such place through `patrol-finding.sh`, under
a key for what it could not resolve, as the feedback miner files its findings. A
case that stays unresolved updates that finding from run to run, and a run that
resolves it marks the finding cleared. An input the run cannot read, such as
another account's user settings or a `~/` value under its home, server-managed
settings, or workspace trust, which decides whether Claude Code honors a
project's value, can move a directory where the run does not look. That
directory's notes then stay unread, as every directory's are today.

**The Product Owner.** Its memory stays off. `agents/po/agent.toml` sets
`CLAUDE_CODE_DISABLE_AUTO_MEMORY`, because a note would carry one sitting's
context into the next. It has no memory directory, and nothing here changes for
it. What the distiller files reaches the Product Owner's queue held for
placement, like any other new work.

**Agents with no such memory.** Codex agents (`polecat-codex`, the
`converse-codex` sittings and `dog`) load no Claude Code memory directory, and
Codex's own memory on this host holds nothing. Their lessons keep the routes
they have: a report for what is to be evaluated, and a bead's notes for the
state of work. A lesson a Codex agent learns on its own has no memory intake,
which this design leaves as it is.

## 8. The epic's contract

The ruling changes epic tk-zlot608. Its boundaries now reach the learning loop's
sorting of memory notes, and its two-week closure condition and its signal of a
memory directory with no note older than two weeks go. The sitting that ruled
puts the redrafted contract to the operator (conversation tk-iyhd38d), so this
design proposes no wording for it, and the closure-condition changes its first
draft proposed on the epic's notes are withdrawn. The list and the removed notes'
text give the counts an indicator can read: the notes in each directory from run
to run, how many wait on an open pattern, and how many the judge dropped.

## 9. Size, and the deletion schedule

The learning loop measures 2.4k runtime lines and 1.9k test lines in
[built-once-target.md](../../docs/built-once-target.md), against a built-once
estimate of 2.0k and 1.5k that has no memory intake. The unit below adds about
0.5k runtime lines: the script, about 350, the formula's new step and the
clauses the other steps gain, the skill's memory section and the guidance file.
It adds about 0.4k test lines. It updates the page's feedback paragraph to name
the memory step.

Nothing it changes is in `tools/deletion-plan.tsv`. A fix the judge finds in a
file the plan lists goes to the retiring bead's notes (section 2), so the intake
gives that code no new work. That includes the feedback-routing doctor check
that tk-1tfzr71.21 retires, which the epic's boundaries name.

## 10. The unit that builds it

| Unit | What it builds | Waits on |
|---|---|---|
| tk-zlot608.5 | `assets/scripts/memory-intake.sh` and its suite: verbs that place each memory directory as Claude Code does, list the due notes, record each judged note on the list, remove a note under the hash, index and collection-note checks while keeping its text, end a note's wait once its pattern or bead is done and its fix has landed, rewrite the guidance block, and report a place the run cannot resolve. The suite covers each input that moves a directory or turns memory on or off, a shared directory, an absent directory, each case the run cannot resolve, a note changed since it was judged, and a follow-up that landed on an effort's branch. `mol-feedback-distiller`'s `read-memory` step, its `memory_notes_per_run` variable and the clauses the other steps gain, within the step-size bound. The `learning-distill` skill's memory section. The guidance file. The docs this makes stale: the intake and promotion path in docs/feedback-learning.md, the rows in docs/component-model.md §4 for the distiller and the script, the feedback paragraph in docs/built-once-target.md, and the Debt entry in docs/architecture.md, which it removes. | this design's merge (tk-zlot608.2), and the pattern change it builds on (tk-ltcv43q, PR #1486) |

One unit, because the step with no script, or the script with no step, does
nothing on its own.
