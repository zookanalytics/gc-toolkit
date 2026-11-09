---
name: records
description: Use when you record an outcome or a finding in a bead's notes, sum up long notes, set the headline the board shows for a bead (its takeaway), or file an observation of feedback about standing agent behavior. To ask a person to decide, use waits; for a durable document such as a spec, use filing-documentation.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Records: notes, headlines and observations

Use this skill to record an outcome in a bead's notes, to sum up long notes in
a current-state block, to set the headline the board shows for a bead, or to
file an observation of feedback about standing agent behavior.

The headline command calls the gc-toolkit pack's script as
`"$(gc <binding> scripts-dir)/gc-helm.sh"`, and only that way. The call looks
up the pack gc loaded inside the command, so it runs no checkout's copy and
needs nothing an earlier call set. `<binding>` is the name the city imports the
pack under, which gc puts in front of this skill's name: `gc-toolkit` in
`gc-toolkit.records`. `gc skill list` prints it in this skill's FROM column.

## Record an outcome on a bead

Append the outcome to the bead notes: what was decided or found, why, and what
changed. Do not replace existing notes.

```bash
gc bd update <bead> --append-notes "<decision or finding, the reason, what changed>"
```

Never pass `--notes`: it replaces the whole field and erases every note other
writers left there.

When the notes have grown past a quick read, append a current-state block that
says where things stand, each decision in force and each open question. The
newest current-state block is the one in force:

```bash
gc bd update <bead> --append-notes "## Current state ($(date -u +%Y-%m-%d))
<where things stand>
Decisions in force: <each decision in force>
Open questions: <each open question, or none>"
```

Put a durable document, such as a spec, an analysis or a decision record, in a
file in a repo through the filing-documentation skill, not in the notes. A
sitting, a converse session with the operator, writes no files, so it files a
bead for the document instead (the work skill).

## Set the headline the board shows

Write one sentence that says what the bead needs now, and name what it waits
on:

```bash
"$(gc <binding> scripts-dir)/gc-helm.sh" takeaway <bead> "<what it needs now, at most 140 characters>" --no-wait
```

Pass `--no-wait` when the bead waits on nothing. When it waits, pass
`--waiting-on <bead>` in its place, once for each bead it waits on. Each named
wait is also written as a `blocks` edge, after the headline. A wait in another
store than the bead is refused before anything is written, because an edge
there would hold nothing, and an edge the store refuses leaves the headline
written and makes the call exit 4 (the waits skill). A headline with neither
flag leaves the bead waiting on its text alone, which
`doctor/check-wait-is-an-edge` reports unless a live `blocks` edge holds the
bead.

In a sitting, leave the headlines to the hold and the sign-off (the
converse-hold and converse-settle steps). The one other headline a sitting
writes is the one that comes with stopping work already sent (the work skill).

## Record feedback as an observation

When someone corrects how agents behave as a standing matter, such as the
operator correcting you, a PR review or comment, or a rework whose cause was a
habit rather than a one-off, fix the instance in front of you first. Then file
one observation before the turn ends, by
`references/file-feedback-observations.template.md` in this skill's directory:
it says which turns carry feedback, gives the one `gc bd create` call that
files the observation with every field, and says how to set its provenance,
category and directive.

Feedback about one change's content, such as a bug or a wrong approach, is
review, not an observation.
