---
name: A distiller run against a scratch memory directory (tk-zlot608.5)
description: The record of one run of mol-feedback-distiller's memory steps, as the formula gives them, over a scratch memory directory with the live bead store read only, and of a real Claude Code save recording a use. Read it to see what the memory intake does to a directory, its index and a collection note, what it hands the judge, and how a note records its uses.
---

# A distiller run against a scratch memory directory

The run took the formula's own text at this branch: read-memory's call, the
`distiller-pending-scratch` and `distiller-cadence-gate` blocks of
load-and-gate (with `rig_list` poured as the home rig and `$SC` naming this
branch's `claim-close.sh`), decision lines as judge-and-cluster writes them,
and file-and-dispatch's apply call. The script was this branch's
`memory-intake.sh`. The home was a scratch directory holding one memory
directory for the home rig's checkout, with four notes that carry the front
matter Claude Code writes, an index and a collection note. The state directory
was scratch too. `gc` was the city's, reading the rig list and the home rig's
store, and the wait went on an open feedback pattern there (tk-v0itc10). The
city's other rigs and its root had no memory directory in the scratch home, so
the run read them as absent; their lines are shown as one. Paths are shortened
to `<home>` and `<state>`.

One step is a real Claude Code save. A headless Claude Code 2.1.325 run on
haiku, given the scratch memory directory as its `autoMemoryDirectory`, used its
Edit tool to add the use line the note asks for, and the diff shows what that
save changed. The judge's later look at that note ran on the script's clock set
to 2026-12-15 (`MEMORY_INTAKE_NOW`).

```text
=== read-memory: `memory-intake.sh read`
memory-intake: <each other rig, and the city root>: absent: no directory there (<home>/.claude/projects/<its checkout>/memory)
memory-intake: gc-toolkit: <home>/.claude/projects/<the home rig's checkout>/memory (named for the checkout)
memory-intake: gc-toolkit: 4 notes and 1 entries; links to gone notes taken out of 2 file(s); guidance block rewritten
memory-intake: waits ended: 0 unit(s) removed with a fix landed, their text kept; 0 due again with no fix landed
memory-intake: 5 due

=== the index after read-memory
<!-- memory-intake: rewritten from the gc-toolkit pack each run -->
A note here holds something that should change the next agent's behavior. The learning loop reads each note, leaves it here while the lesson it shows is being judged or fixed, and removes it once that lesson is settled or the note holds nothing worth keeping.
Write a lesson so it can be acted on: what you did, what happened, the instruction, command or script that led there, what it cost, and whether it happened before.
A rule is the operator's only with their words and where they said them. Otherwise it is yours, and the note says so.
When a note you used asks for a record of the days it is used and holds no line for today, add the dated line it asks for at its end.
What is to be evaluated goes in a report, an observation bead the gc-toolkit.records skill files: corrective feedback from a review, a rework or the operator, feedback whose reach you cannot tell, and a change that needs approval. The state of open work goes on its bead's notes. Leave out what the pack already says.
<!-- /memory-intake -->

# Memory Index

- [Stale](stale.md) — outage · [Lesson](lesson.md) — formula copies
- [Moment](moment.md) — #1486
- [Unsure](unsure.md) — loaded host
- [Topics](hub-topics.md) — bd calls

=== the collection note after read-memory
# Topics

- [[stale]] (Stale): store outage
- (no file) Prefer one gc bd show with many ids to one call per id.

=== load-and-gate §2-§3: the pending set, seeded with the due notes (rig_list=gc-toolkit)
DISTILL_RUN=open — gate open: 6 pending, 0 urgent, oldest 0d
observations: 1, due memory notes:
  ac82f8d7133fe84d/lesson.md@e6cdd899ae8d388e  note  new  2026-11-14T22:52:02Z
  ac82f8d7133fe84d/moment.md@23ae82a6fdfb67e0  note  new  2026-11-14T22:52:02Z
  ac82f8d7133fe84d/stale.md@402c9fc31cf1cbc6  note  new  2026-11-14T22:52:02Z
  ac82f8d7133fe84d/unsure.md@06aa4c89e7c9276a  note  new  2026-11-14T22:52:02Z
  ac82f8d7133fe84d/hub-topics.md@3489795453a0215e  entry  new  2026-11-14T22:52:03Z

=== judge-and-cluster: the decision lines
ac82f8d7133fe84d/stale.md@402c9fc31cf1cbc6 drop
ac82f8d7133fe84d/lesson.md@e6cdd899ae8d388e waits tk-v0itc10
ac82f8d7133fe84d/moment.md@23ae82a6fdfb67e0 next 2026-11-21
ac82f8d7133fe84d/unsure.md@06aa4c89e7c9276a next 2026-12-14 ask-use
ac82f8d7133fe84d/hub-topics.md@3489795453a0215e waits tk-v0itc10

=== file-and-dispatch §2b: `memory-intake.sh apply <the decisions file>`
memory-intake: removed ac82f8d7133fe84d/stale.md@402c9fc31cf1cbc6, its text kept at <state>/ac82f8d7133fe84d8e603dcc471945ea7f72ca4c1edd8d0379a39dc7a98eb131/removed/stale.md@402c9fc31cf1cbc6012a2360ab7aee11b49004b5fc60df9358484bdefaf1eb2e
memory-intake: recorded ac82f8d7133fe84d/lesson.md@e6cdd899ae8d388e: waits on tk-v0itc10
memory-intake: recorded ac82f8d7133fe84d/moment.md@23ae82a6fdfb67e0: due again on 2026-11-21
memory-intake: recorded ac82f8d7133fe84d/unsure.md@06aa4c89e7c9276a: due again on 2026-12-14, with a request to record the days it is used, one line a day
memory-intake: recorded ac82f8d7133fe84d/hub-topics.md@3489795453a0215e: waits on tk-v0itc10
exit 0

=== the directory, the index and the collection note after apply
hub-topics.md
lesson.md
MEMORY.md
moment.md
unsure.md

<!-- memory-intake: rewritten from the gc-toolkit pack each run -->
A note here holds something that should change the next agent's behavior. The learning loop reads each note, leaves it here while the lesson it shows is being judged or fixed, and removes it once that lesson is settled or the note holds nothing worth keeping.
Write a lesson so it can be acted on: what you did, what happened, the instruction, command or script that led there, what it cost, and whether it happened before.
A rule is the operator's only with their words and where they said them. Otherwise it is yours, and the note says so.
When a note you used asks for a record of the days it is used and holds no line for today, add the dated line it asks for at its end.
What is to be evaluated goes in a report, an observation bead the gc-toolkit.records skill files: corrective feedback from a review, a rework or the operator, feedback whose reach you cannot tell, and a change that needs approval. The state of open work goes on its bead's notes. Leave out what the pack already says.
<!-- /memory-intake -->

# Memory Index

- [Lesson](lesson.md) — formula copies
- [Moment](moment.md) — #1486
- [Unsure](unsure.md) — loaded host
- [Topics](hub-topics.md) — bd calls

# Topics

- (no file) Prefer one gc bd show with many ids to one call per id.

=== the list, and the removed note text kept
#memory-intake list 1	kind	name	hash	judged	wait	next	why
entry	hub-topics.md	3489795453a0215e3ebc6c85b404585dce44e53eb174bab63dc479f168959397	2026-11-14T22:52:05Z	tk-v0itc10		
note	lesson.md	684d7e9f9b5708bb8de45a3e8f912ee1c4130daaac1578d7fb56cbfa57971387	2026-11-14T22:52:05Z	tk-v0itc10		
note	moment.md	45eb54dffc62624c13bd3d88bd9ce1f233098f0415140268a00d76df4d0c2e0f	2026-11-14T22:52:05Z		2026-11-21	
note	unsure.md	a71c711308ef037000319aed3310af3226b780762386d3330d95054b5af4b9c6	2026-11-14T22:52:05Z		2026-12-14	

--- stale.md@402c9fc31cf1cbc6012a2360ab7aee11b49004b5fc60df9358484bdefaf1eb2e
---
name: stale
description: "Store outage window"
metadata:
  node_type: memory
  type: project
  originSessionId: 5a0afee4-7b7b-4690-a147-ef378abd336c
  modified: 2026-11-14T09:00:00.000Z
---

The store was down on 2026-11-01 between 03:00 and 04:00.

=== unsure.md now asks for its uses
Run the slow suites last when the host is loaded.
<!-- memory-intake: use --> When this note steers your work and holds no used line for today, add one at its end: used <YYYY-MM-DD>: <what it changed>

=== due now: 0

=== an agent uses unsure.md: a Claude Code Edit (2.1.325, haiku) adds the use line it asks for
claude -p: <the scratch memory directory>, success
8c8
<   modified: 2026-11-14T09:00:00.000Z
---
>   modified: 2026-11-14T22:52:12.461Z
12a13
> used 2026-11-14: ran the slow suites last on a loaded host
due now: 0

=== the judge's next look at unsure.md, on 2026-12-15: `next 2027-01-14`, with no ask-use
due: ac82f8d7133fe84d/unsure.md@2aa1f66083c14c36 date
memory-intake: recorded ac82f8d7133fe84d/unsure.md@2aa1f66083c14c36: due again on 2027-01-14; its request to record the days it is used taken out
exit 0

Run the slow suites last when the host is loaded.
used 2026-11-14: ran the slow suites last on a loaded host
due on 2026-12-16: moment.md (date)

=== an agent edits lesson.md, which waits on the open pattern; read-memory, then the due list
memory-intake: waits ended: 0 unit(s) removed with a fix landed, their text kept; 0 due again with no fix landed
memory-intake: 1 due
  ac82f8d7133fe84d/lesson.md@cb1f1be69477bfb0  changed  prior: waited on tk-v0itc10

=== lesson.md is still in place: yes; findings filed: 0
```
