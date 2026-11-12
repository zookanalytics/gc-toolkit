---
name: Standing memory triage and the guidance for writing memory (tk-zlot608.2)
description: The design of the weekly triage that sorts each agent memory store by the operator's three questions, carries what a note shows into the pack's reviewed paths or onto a bead, and removes the note, and of the guidance that tells agents what a note should carry. Read it to build or review the triage, or to judge what becomes of a memory note.
---

# Standing memory triage and the guidance for writing memory

Agent memory stays an intake. Agents keep writing notes, and a weekly triage
sorts each note one to two weeks after it is written. It carries what the note
shows to the place that holds such things, a reviewed fix in the pack, the
learning loop or a bead, and then removes the note. The backlog triage's record,
[specs/tk-zlot608.1/report.md](../tk-zlot608.1/report.md), is the worked
example: the standing triage sorts the way that record did, and its record keeps
the same columns.

## What the operator ruled, and what this design proposes

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

When they asked for the audit (tk-ljv34vu), they wrote that memories "should
become structural items in the pack, or skills, or changes in a rig, or new
functionality".

Everything else on this page is this design's proposal, for the operator's
review of its PR. That includes the two-week limit, which the filing sitting
proposed from how quickly notes stop being read.

## 1. Where the analysis runs, and how often

A Gas City order, `memory-triage`, pours the formula `mol-memory-triage` onto
the `gc-toolkit.polecat` pool once a week (`trigger = "cooldown"`,
`interval = "168h"`). The order is scoped to the rig, so it comes with the pack
to every rig, as the feedback miner's order does, and each rig sorts its own
store. Gas City runs one at a time: its dispatcher skips an order whose earlier
run is still open. [gas-city-search.md](gas-city-search.md) records the search
for a primitive that covers the need. An order covers the schedule, and nothing
in Gas City, bd or Claude Code sorts or empties an agent's memory.

The analysis is the polecat's own reading. Read-only subagents may sort batches,
as they did for the backlog (71 batches for 2,161 units), and the polecat checks
every row they return and owns the record. A week's intake is about 220 notes,
from the audit's count of about 32 a day (tk-ljv34vu's notes).

The triage is a formula of its own, not a step of the miner:

- The miner no-ops a rig whose checkout has no usable GitHub, and the triage
  needs none.
- The miner records and changes nothing. The triage removes notes and sends
  fixes.
- The miner reads a window of pull requests every day. The triage reads a host
  directory every week.

Joined, each would inherit the other's no-op and the other's failures.

It is not the distiller either. The distiller judges observations, and filing
every note as one would be the stream the operator ruled out. The triage sits in
front of the learning loop and passes on only what its analysis finds.

**Which notes a run sorts.** A run sorts each note that was already in the store
when the previous run copied it. A note the run sees for the first time waits
for the next run, so every note is sorted one to two weeks after it is written.
A daily run would sort notes in their first days, which is when other sessions
read them: in the audit's week, another session opened 171 of the 221 new notes,
and about 110 of the 1,232 older ones. A store's first run sorts nothing. It
copies the store, records what it saw and writes the guidance block (section 5).

## 2. How a note leaves the store

**When.** At the triage, once what the note shows has been carried to where it
goes (section 3). A note whose content could not be carried, because a write
failed, stays for the next run. Removal does not wait for a fix to land:

- A note rarely prevents a repeat. Of the 34 sampled notes that describe a
  problem a check or script would remove, any session opened 5 in the audit's
  week.
- A note kept until its fix lands keeps an unreviewed rule steering agents for
  as long as the slowest fix takes, and the triage would have to track every
  fix across runs.
- A problem that comes back before its fix lands gets written down again, and
  the next run counts the new note as a repeat of the same finding, which
  raises its severity.

One kind of note stays: a guard. A note that is the only guard against a
high-severity harm, such as the rule never to kill processes by name pattern on
a host where one user runs every session, stays until the pack carries a guard
of its own. It is the stopgap already in place, and removing it would bring the
harm back. Each run sorts it again and removes it once the pack carries the fix.
The record lists every note held this way, with the observation that carries
its fix.

**How long a note may stay.** Two weeks, plus any delay the pool adds to a run.
A held guard is the one exception, and each run's record names it.

**The copy.** Before it removes anything, a run copies the whole store to
`<city>/.gc/runtime/packs/gc-toolkit/memory-triage/<store>/<run start>/` and
checks the copy file for file. That is the pack's state directory, which Gas
City names for each pack in a city. The town repository ignores `.gc/`, and no
session loads it. The next run reads this copy to learn which notes are due.
`<store>` is the store's real path with each `/` and `.` as `-`, so each store
keeps its own copies whichever run sorts it (section 6). Copies are kept, and
nothing prunes them. A copy of this rig's store at the audit's intake is a few
megabytes. The backlog's copy stays where tk-zlot608.3 put it.

**Concurrent writers.** Every Claude session in the rig can write the store
while a run works.

- A note is removed only while its hash still matches the copy. A note changed
  since the copy is skipped and sorted next run, and a note written since the
  copy is not due.
- A collection note (`hub-*.md`) is sorted entry by entry and removed whole once
  every entry has been carried or let go. The triage never edits a note, since
  another session may be writing it.
- A link to a removed note, in a note not yet sorted, stays until that note is
  sorted, within a cycle. That covers the 313 links in collection notes and the
  649 in other notes that the backlog removal left (tk-zlot608.3).

**The index.** Claude Code loads the first 200 lines or 25 KB of `MEMORY.md`
into every session. A run changes two things in it. It takes out the entries of
the notes it removed, and it rewrites the guidance block at the top (section 5).
For each edit it reads the file just before writing and writes only if nothing
changed since that read, or it reads again. tk-zlot608.3 removed the backlog's
notes the same way.

## 3. What each answer becomes

A run sorts each due note, or each entry of a due collection note, under one
answer. The answers are the backlog record's, with its "fits none" read for what
the standing triage does with it.

| Answer | What it is | What becomes of it |
|---|---|---|
| Point-in-time (question 1) | finished work, something that no longer holds, something the pack already says, one moment's state | removed |
| Wording fix (question 2) | a vague or misleading direction that a change of at most two words fixes | listed on the run's wording-fix bead, then removed |
| Structural (question 3) | something off that a script, a check or a more robust instruction would fix, including knowledge agents keep needing that the pack lacks | a finding, weighed and sent on (below), then removed, unless the note is a held guard |
| Live work | the state of work still open | what its bead lacks is appended to the bead, then removed |
| Let go | knowledge still true with no pack defect behind it, which an agent can learn again | removed |

The backlog's 1,374 "fits none" units are mostly recipes, facts about tools the
pack does not own, and Gas City behavior. Each is let go unless the run finds
that agents rely on it, and the copy keeps its text. An agent that needs one works it out again and may write it down
again, and a lesson that keeps coming back is question 3's "agents regularly
getting confused". So a later run sorts it as structural and carries it. A note
many sessions read is also structural, since agents rely on what it says
(section 4). The backlog's 159 unwritten rules are each either structural or a
ruling (below): a rule the pack lacks is either something off or something for
the operator to decide.

### Wording fixes

Each fix names the instruction at main by file and section, its current words,
the replacement and the change in words, as the backlog record's do. A fix adds
at most two words, the largest the backlog needed. A fix that needs more is
structural, because its instruction is silent rather than misleading.

A run files one wording-fix bead for each repository that holds an instruction
at fault, in that repository's rig store (`gc bd --rig`). The bead lists every
fix with the note that showed it, and it is slung to that rig's polecat pool on
`mol-polecat-work`. The builder re-reads each instruction at main, skips a fix
whose words have changed, and shows each instruction's size before and after in
the PR. The operator's review of the PR is the gate on every change to an
instruction.

Two kinds of fix go elsewhere:

- A fix in the words of an adopted learned rule becomes an observation on the
  rule's pattern bead, because the learning loop owns those words.
- A fix in a file `tools/deletion-plan.tsv` lists is appended to the notes of
  the bead that retires the file (AGENTS.md).

The intake rule in [steering.md](../../docs/steering.md#the-intake-rule) lets a
bead reach a pool only on one of the grounds it lists. **Proposed:** approving
this design makes the wording-fix bead a standing route, as the seed audit's
re-audit is, because each fix has a proven remedy and asks no policy question.
If the operator declines, the bead is filed held for placement instead, and each
week's fixes wait for a sitting before a polecat builds them.

### Structural findings

A run groups the structural notes and entries into findings, one for each
problem, as the backlog record did. Each finding names what is off, the notes
that show it, what it costs when it happens, its severity and the scope of its
fix.

- **Severity** is what the problem costs each time. High: it destroys or loses
  work, stops sessions, corrupts a store, exposes what must stay private, or
  lands a wrong change. Medium: it costs a rework, a failed gate or a repair by
  hand. Low: it costs a retry or a few minutes. Severity rises one level when
  the problem recurs: two or more notes show it, a note records a repeat, an
  earlier run's record holds the same finding, or many sessions read a note
  that works around it.
- **Scope** is the size of the fix. Small: a few lines of text, or one script
  or check. Medium: several scripts, or a new script or formula step. Large: a
  new subsystem, a redesign, or a change outside the pack.

| Severity | Small fix | Medium fix | Large fix |
|---|---|---|---|
| High | sent on | sent on | sent on |
| Medium | sent on | sent on | kept in the record |
| Low | kept in the record | kept in the record | kept in the record |

This table is the filter that keeps the intake from becoming a stream. A finding
kept in the record is not dropped for good. When later notes show it again, its
severity rises, and a later run sends it on.

A finding that is sent on goes the first way that applies:

1. A problem in a file `tools/deletion-plan.tsv` lists is appended to the
   retiring bead's notes (AGENTS.md).
2. A problem an open bead already carries is appended to that bead's notes as
   more evidence.
3. A problem in software the pack does not own goes the way the
   `gc-toolkit.external-issue` skill sends it.
4. Anything else becomes one observation in the learning loop
   ([feedback-learning.md](../../docs/feedback-learning.md)), filed in the run's
   rig store with `obs.source=self`, `obs.directive=standing`, a provenance that
   names the run, and the finding's slug as `obs.category`. A later run that
   finds the same problem reuses the slug, so the loop's repeat measure counts
   it.

The learning process then treats it as it treats any observation. The distiller
clusters it with feedback on the same problem from pull requests, sends a
structural remedy to an engineering bead (Gate 2), and holds back a rule that
only agents reported until the operator endorses it (Gate 1). Every proposal it
files waits for the operator's placement. So a structural finding reaches the
operator's queue through the learning process, and no note changes an
instruction without the operator's review.

### Live work

A note about work still open belongs on its bead. The run reads the bead's notes
and appends, in one append for each bead, what a later session on that work
needs and the notes do not already say, such as a decision, a blocker or a fact
about the branch. Then it removes the note. Most such notes repeat what the bead
or its pull request already shows, and leave with nothing appended.

### A ruling attributed to the operator

The run checks each ruling that a note attributes to the operator against the
source the note gives.

- **The source holds the operator's words.**
  - A ruling about one case lives with that case. Its note is point-in-time
    once the case has closed, and live work while it is open.
  - A standing ruling the pack already carries is point-in-time.
  - A standing ruling the pack does not carry becomes one observation that
    quotes the operator's words and links the source. The distiller checks the
    voice behind it, and the operator says yes or no at the PR that would adopt
    it.
- **The source does not hold those words, or the note gives none.** The rule is
  the writer's own. It is sorted by the three questions as the writer's, the
  record marks the attribution unsupported, and it never reaches the operator
  as theirs.

The backlog record marks 257 units that attribute a ruling to the operator,
taken from each note's own text. This check is what sorts those into rulings
that stand and agents' own inferences.

## 4. The run's record

Beside its copy, a run writes two files:

- `record.tsv` has one row for each unit it sorted, in the backlog record's
  columns: the unit, its kind, its hash, the answer, the detail, the ruling it
  attributes to the operator with the source it claims, and the retiring bead.
  Three columns are added: the sessions that read the note since the previous
  run, the earlier finding or lesson it repeats, and where it went (removed,
  skipped, held, an observation, a wording-fix bead, or a bead it was appended
  to).
- `summary.md` gives the counts under each answer, the notes removed, skipped
  and held, the notes that repeat an earlier run's lesson, the findings sent on
  and kept, and the wording-fix beads.

The epic's indicators come from these files: the count of notes in each store
from run to run, the share under each question, and how many new notes repeat a
lesson an earlier run sorted. The records stay on the host, because a store's
notes can name private rigs and paths. The next run reads the previous copy and
the records, and nothing else holds the triage's state.

**Reads.** The sessions that read a note are counted from the session
transcripts Claude Code keeps on the host, which record each tool call and the
files it read. A note many sessions read is one agents rely on, which raises the
severity of the problem it works around. A note no session has read since it was
written is evidence that it can go.

## 5. How agents are told to write memory well

The guidance sits at the top of each store's index. `MEMORY.md` loads into every
session that has memory, and an agent edits it after writing a note. Each run
rewrites the block from one file in the pack, so its words change only through a
reviewed PR. It adds nothing to the pack's prompts, and it reaches no agent whose
memory is off. **Proposed** words, for the unit that builds them:

```markdown
<!-- memory-triage: rewritten each week from the gc-toolkit pack -->
Notes here are an intake. A weekly triage sorts each one a week or two after it is written, sends what the pack should hold to a fix, and removes the note.
Write a lesson so it can be fixed: what you did, what happened, the instruction, command or script that led there, what it cost, and whether it happened before.
A rule is the operator's only with their words and where they said them. Otherwise it is yours, and the note says so.
The state of open work goes on its bead's notes, and corrective feedback from a review, a rework or the operator goes in an observation bead. Leave out what the pack already says.
<!-- /memory-triage -->
```

What a note carries so the analysis can act on it:

- A lesson gives the act, what happened, the instruction, command or script
  behind it by file and section or command line, the cost, and any earlier
  time it happened. With these the run can find the words to fix (question 2),
  or weigh a finding (question 3).
- A ruling gives the operator's words and where they gave them.

What does not belong in memory, and where it goes:

- The state of open work goes on the bead's notes.
- Corrective feedback from a durable source goes in an observation, by the route
  the `file-feedback-observations` fragment gives.
- What the pack or the repository already says goes nowhere.
- A durable document goes in the repository (`gc-toolkit.filing-documentation`).

The other place this guidance could live is a shared fragment in every Claude
role's prompt. That costs each session about the same text, but it sits away
from the act of writing, and it reaches the Product Owner, whose memory is off.
The block's own cost is that an agent may edit it between runs, and the next run
restores it.

## 6. The stores, the Product Owner and agents without memory

**Where a store is.** A run places each store as Claude Code's storage-location
rules do ([gas-city-search.md](gas-city-search.md#find-a-store)), from the
inputs Gas City starts the rig's Claude sessions with:

- Memory is off when the environment sets `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`,
  or when the highest settings level that sets `autoMemoryEnabled` sets it
  false.
- Otherwise the store is the `autoMemoryDirectory` of the highest settings
  level that sets one. The levels, highest first, are managed settings, the
  `--settings` file Gas City gives each Claude session it starts, the
  checkout's local settings, its shared project settings, and the user settings
  in the config directory.
- Otherwise the store is `<config dir>/projects/<project>/memory/`. The config
  directory is `CLAUDE_CONFIG_DIR`, or `.claude` under the session's home.
  `<project>` is `CLAUDE_CODE_PROJECT_DIR_NAME` when that is set beside
  `CLAUDE_CONFIG_DIR`, and otherwise the checkout's path with each `/` and `.`
  as `-`.

The environment and the user settings a run reads are its own session's. Gas
City starts the run on the rig's pool as it starts the rig's other Claude
sessions, so they match unless an agent's provider or its own configuration
sets a different environment, or a launch command gives each account a home of
its own, as this host's does. A run compares paths by their real path, because
those homes link their `projects` directories to one place, so one store shows
under several paths.

**Other rigs.** The order is scoped to the rig, so each rig's run sorts the
store that is the rig's own: the one named for its checkout, or one its own
local or shared project settings place. A run files observations in its own
rig's store, and the distiller reads observations across rigs. A wording fix
goes to the rig whose repository holds the instruction, so a fix in the pack's
files reaches the pack's own rig. A fix PR against this public repository
names no other rig, which self-review's `rig-mentions.sh` checks. On this host
the other rigs' stores hold about 550 notes.

**The city root.** The agents that run at the city root write a store of their
own, about 470 notes on this host. The run in the pack's home rig sorts it as
well. The home rig is the one whose `pack.toml` names gc-toolkit, the test the
distiller uses to decide where it runs.

**A store several rigs share.** A store placed by the `--settings` file is one
directory for the sessions of every rig and of the city root, and only the
sessions Gas City starts are given that file. The home rig's run sorts it, as it
sorts the city root's store, and the other rigs' runs leave it to that run. A
store placed at the user or managed level, or named by
`CLAUDE_CODE_PROJECT_DIR_NAME`, is also one directory for every project those
sessions start in, but sessions the city does not run can share it, and no run
can answer for their notes. No run sorts it. Each run that places a
store there reports it as a place it cannot resolve (below). A store placed at
the user level, or named by `CLAUDE_CODE_PROJECT_DIR_NAME`, comes under a run
once the city's or the rig's own Claude settings set `autoMemoryDirectory`
instead. Both rank above the user level, and a directory they set takes the
place of the one the variable names.

**An absent store, and a place a run cannot resolve.** A store is absent when
memory is off or no directory exists where the store is placed, provided no
session in the rig has written a memory index anywhere else since the previous
run. The run then changes nothing, and its record says so. A run cannot resolve
a place in these cases, and it removes nothing there:

- A settings file at one of the levels does not parse, or the deciding
  `autoMemoryDirectory` is neither an absolute path nor one that starts with
  `~/`, as the memory page requires. The run cannot tell what the sessions
  used.
- The rig's own settings place the store while
  `permissions.blockReadsOutsideWorkingDirectories` is on, so Claude Code
  neither loads nor writes memory there.
- The store is placed at a level no run sorts (above).
- A session in the rig has written a memory index (`MEMORY.md`) with Claude
  Code's file tools since the previous run, outside the store the run placed
  and outside the city's checkouts, where such a file is a repository's own.
  Another account's user settings, a managed source the run cannot read, such
  as server-managed settings, or workspace trust, which decides whether Claude
  Code honors a project's value, can each move a store to a place the run does
  not look. The run still sorts the store it placed.

The configuration places each store. The transcripts the run reads to count
reads (section 4) only add places to report, and they never make a store absent
or move one, since they show where sessions wrote, not where Claude Code places
a store no session has written yet.

A run records each place it cannot resolve and why, and files a finding through
`patrol-finding.sh` under a key for what it could not resolve, as the feedback
miner files its findings. A case that stays unresolved updates that one finding
from week to week, and a later run that resolves it marks the finding cleared.
A place that is not one rig's alone is filed in the home rig's store, so it is
one finding however many runs report it.

**The Product Owner.** Its memory stays off. `agents/po/agent.toml` sets
`CLAUDE_CODE_DISABLE_AUTO_MEMORY`, because a note would carry one sitting's
context into the next. It has no store, and the triage changes nothing for it.
What the triage sends on reaches the Product Owner's queue through the
distiller, held for placement like any other new work.

**Agents with no such memory.** Codex agents (`polecat-codex`, the
`converse-codex` sittings and `dog`) load no Claude Code store, and Codex's own
memory store on this host is empty. The triage reads no Codex store. Their
lessons keep the routes they have: an observation for corrective feedback, and
a bead's notes for the state of work. A lesson a Codex agent learns on its own
has no intake. That falls outside this epic's cut, and bd's memory plane would
be its natural intake if the operator wants one
([gas-city-search.md](gas-city-search.md)).

Stores keyed to directories outside the city's rigs and its root belong to
sessions the city does not run, and no run sorts them.

## 7. Size, and the deletion schedule

At main (986037bd4) the learning loop measures 2.4k runtime lines and 1.9k test
lines. [built-once-target.md](../../docs/built-once-target.md) estimates 2.0k
and 1.5k for its built-once shape, which has no memory triage. The unit below
adds about 0.7k runtime lines, chiefly a script of about 400 and a formula of
about 250, plus the order and the guidance file. It adds about 0.5k test lines.
It updates the page's feedback row and its paragraph to include the triage.

The triage adds nothing to a file `tools/deletion-plan.tsv` lists. Its method
sends a fix or a finding in such a file to the retiring bead's notes (section
3), so it gives that code no new work. That includes the feedback-routing doctor
check that tk-1tfzr71.21 retires, which the epic's boundaries name.

## 8. What the first runs do

Merging the unit starts the order in every rig. A store's first run only copies
the store, records what it saw and writes the guidance block. Its second run, a
week later, sorts every note the first one saw, so each store's backlog leaves
then.

- In this rig that is the 1,046 files left after the backlog removal. The unit
  seeds this store's records with the backlog record, so the second run weighs
  the backlog's 35 findings by the table in section 3 and sends on those that
  pass it.
- The city root's store and the other rigs' stores, about 1,000 notes between
  them, leave the same way.

The cost falls on the collection notes agents open most. In the audit's week the
busiest was opened by 131 sessions, and 47 notes were opened by ten or more.
Their entries leave at the second run. What agents rely on in them is sent on at
that run, its severity raised by its reads, and it waits for placement and a
build like any other finding. Until that lands, an agent that needs one of those
recipes works it out again, and a note it writes about it counts as a repeat.

## 9. The units that build it

| Unit | What it builds | Waits on |
|---|---|---|
| tk-zlot608.5 | The triage. `assets/scripts/memory-triage.sh` and its suite: verbs that place each store as Claude Code does and name the run that sorts it, copy it, list the due notes, count reads, remove notes with the hash and index checks, rewrite the guidance block, and report a place the run cannot resolve (section 6). The suite covers each input that moves a store or turns memory off, a shared store, an absent store and each case a run cannot resolve. `formulas/mol-memory-triage.toml`, `orders/memory-triage.toml` and the guidance file. The sort's method goes in the formula's sort step, or in a skill that step loads if the step would pass the step-size bound. It seeds this rig's records with the backlog record. It updates the docs this makes stale: the capture channels in docs/feedback-learning.md, the intake rule in docs/steering.md if the operator makes the route standing, the rows in docs/component-model.md §4, the feedback row in docs/built-once-target.md, and the Debt entry in docs/architecture.md, which it removes. | the operator's approval of this design, which closes tk-zlot608.2 |

One unit, because a script with no order to call it, or an order with no script,
does nothing on its own.
