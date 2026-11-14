---
name: A distiller run against a scratch memory directory (tk-zlot608.5)
description: The record of one run of mol-feedback-distiller's memory steps, as the formula gives them, over a scratch memory directory with the live bead store read only. Read it to see what the memory intake does to a directory, its index and a collection note, and what it hands the judge.
---

# A distiller run against a scratch memory directory

The run took the formula's own text at this branch: read-memory's call, the
`distiller-pending-scratch` and `distiller-cadence-gate` blocks of
load-and-gate (with `rig_list` poured as the home rig and `$SC` naming this
branch's `claim-close.sh`), decision lines as judge-and-cluster writes them,
and file-and-dispatch's apply call. The script was this branch's
`memory-intake.sh`. The home was a scratch directory holding one memory
directory for the home rig's checkout, with four notes, an index and a
collection note. The state directory was scratch too. `gc` was the city's,
reading the rig list and the home rig's store, and the wait went on an open
feedback pattern there (tk-v0itc10). The city's other rigs and its root had no
memory directory in the scratch home, so the run read them as absent; their
lines are shown as one. Paths are shortened to `<home>` and `<state>`.

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
When a note you used asks for a record of each use, add the dated line it asks for at its end.
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
DISTILL_RUN=open — gate open: 6 pending, 1 urgent, oldest 0d
observations: 1, due memory notes:
  5c8ca614ee4ad8f7/lesson.md@d2e43c76bc5429ef  note  new  2026-11-14T08:03:08Z
  5c8ca614ee4ad8f7/moment.md@dd166fe73a083cc1  note  new  2026-11-14T08:03:08Z
  5c8ca614ee4ad8f7/stale.md@d849868939051583  note  new  2026-11-14T08:03:08Z
  5c8ca614ee4ad8f7/unsure.md@79bec6555dc7340b  note  new  2026-11-14T08:03:08Z
  5c8ca614ee4ad8f7/hub-topics.md@3489795453a0215e  entry  new  2026-11-14T08:03:09Z

=== judge-and-cluster: the decision lines
5c8ca614ee4ad8f7/stale.md@d849868939051583 drop
5c8ca614ee4ad8f7/lesson.md@d2e43c76bc5429ef waits tk-v0itc10
5c8ca614ee4ad8f7/moment.md@dd166fe73a083cc1 next 2026-11-21
5c8ca614ee4ad8f7/unsure.md@79bec6555dc7340b next 2026-12-14 ask-use
5c8ca614ee4ad8f7/hub-topics.md@3489795453a0215e waits tk-v0itc10

=== file-and-dispatch §2b: `memory-intake.sh apply <the decisions file>`
memory-intake: removed 5c8ca614ee4ad8f7/stale.md@d849868939051583, its text kept at <state>/5c8ca614ee4ad8f7d7772a6b848f75d6123bc67af32e8ca4119ea5a9943cb8bc/removed/stale.md@d849868939051583baa651382e0169077e89737379c17b514addd0c185338b06
memory-intake: recorded 5c8ca614ee4ad8f7/lesson.md@d2e43c76bc5429ef: waits on tk-v0itc10
memory-intake: recorded 5c8ca614ee4ad8f7/moment.md@dd166fe73a083cc1: due again on 2026-11-21
memory-intake: recorded 5c8ca614ee4ad8f7/unsure.md@79bec6555dc7340b: due again on 2026-12-14, with a request to record each use
memory-intake: recorded 5c8ca614ee4ad8f7/hub-topics.md@3489795453a0215e: waits on tk-v0itc10
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
When a note you used asks for a record of each use, add the dated line it asks for at its end.
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
entry	hub-topics.md	3489795453a0215e3ebc6c85b404585dce44e53eb174bab63dc479f168959397	2026-11-14T08:03:12Z	tk-v0itc10		
note	lesson.md	d2e43c76bc5429efb074365a587d35fffb4a2e8ce9dae4a696daccbac6c4d539	2026-11-14T08:03:12Z	tk-v0itc10		
note	moment.md	dd166fe73a083cc101b6adef6ba2bc8bcae09dcaf1c017d6c39c8e32f011ace1	2026-11-14T08:03:12Z		2026-11-21	
note	unsure.md	a2dfdee38667c0f83bd654f0347fc9df2bf0af41f5a2d68163a2146e49f2e657	2026-11-14T08:03:12Z		2026-12-14	

--- stale.md@d849868939051583baa651382e0169077e89737379c17b514addd0c185338b06
---
name: stale
---
The store was down on 2026-11-01 between 03:00 and 04:00.

=== unsure.md now asks for its uses
Run the slow suites last when the host is loaded.
<!-- memory-intake: use --> When this note steers your work, add a line at its end: used <YYYY-MM-DD>: <what it changed>

=== due now: 0

=== an agent edits lesson.md, which waits on the open pattern; read-memory, then the due list
memory-intake: waits ended: 0 unit(s) removed with a fix landed, their text kept; 0 due again with no fix landed
memory-intake: 1 due
  5c8ca614ee4ad8f7/lesson.md@8a3cb5745a600d74  changed  prior: waited on tk-v0itc10

=== lesson.md is still in place: yes; findings filed: 0
```
