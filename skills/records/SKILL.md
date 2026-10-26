---
name: records
description: Use when you need to write down what was decided, what happened, or what a bead needs, so whoever reads it next inherits it. Covers recording an outcome or a finding by appending to a bead's notes, summing up long notes under a Current state heading, and setting the one-line headline the board shows for a bead (its takeaway). To ask a person to decide, use waits; for a durable document such as a spec or an analysis, use filing-documentation.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Records: what a bead's next reader inherits

A bead carries its own record. The next worker, sitting or person who reads it
starts from what is written there, not from your context, which ends with your
session. Each option says what the record means, who reads it, and the one
writer that sends it.

The writers are the gc-toolkit pack's own scripts.
`gc <binding> scripts-dir` prints their directory in the pack as gc loaded it,
so each example calls the pack's copy inside the command itself, and runs in a
fresh shell. `<binding>` is the name the city imports the pack under, which gc
puts in front of this skill's name: `gc-toolkit` in `gc-toolkit.records`.
`gc skill list` prints it in this skill's FROM column.

## Record an outcome on a bead

The message is what was decided or found, why, and what changed. The next
reader of the bead picks it up: a sitting primes from the bead's notes, and a
worker reads them before it starts.

Writer: `gc bd update <bead> --append-notes "<decision or finding, the reason, what changed>"`.

Notes are append-only. `--notes` replaces the whole field and erases every
note other writers left there, so never use it.

When the notes have grown past a quick read, append a current-state block:
where things stand, the decisions in force, and the open questions. The newest
current-state block is the one in force, so a reader starts there:

```bash
gc bd update <bead> --append-notes "## Current state ($(date -u +%Y-%m-%d))
<where things stand>
Decisions in force: <each decision in force>
Open questions: <each open question, or none>"
```

A bead's notes are operational state. A durable document, such as a spec, an
analysis or a decision record, is a file in a repo, filed through the
filing-documentation skill. A sitting writes no files, so it files a bead for
the document instead (the work skill).

## Set the headline the board shows

The message is one sentence saying what the bead needs now. The helm board
shows it as the bead's NEEDS cell, except on a row with no PR that a human gate
or a conversation holds, where NEEDS names what the gate asks or that the bead
is in conversation. `doctor/check-wait-is-an-edge` checks the wait the headline
declares against the bead's `blocks` edges.

Writer: `"$(gc <binding> scripts-dir)/gc-helm.sh" takeaway <bead> "<what it needs now, at most 140 characters>" --no-wait`
when the bead waits on nothing, or `--waiting-on <bead>` (repeatable) for each
bead it waits on. Each named wait is also written as a `blocks` edge,
best-effort: an edge that will not take only warns, so read it back when the
wait matters (the waits skill). Saying neither parks the bead on prose, which
the doctor reports unless a live `blocks` edge holds it.

In a sitting, the hold and the sign-off write the headlines (the converse-hold
and converse-settle steps). The one other headline a sitting writes is a
stand-down, which stops work in flight (the work skill).
