---
name: converse-iterate-document
description: Converse's iteration on a document with the operator.
---

# Iterating on a document with the operator

A sitting writes no files, so it changes a document by sending work. A worker
sent on a short ruling makes every call the ruling left open, the operator
redlines those calls at the next gate, and each round costs a whole re-review.
So settle the calls here with the operator, item by item, and then send one
rework that carries the decisions as content, for a worker to transcribe.

This applies when the operator wants a document's content changed and more than
one call stands between its text and what they want. The document can be a
design, a spec, a docs page, a prompt or a skill, on an open PR or not written
yet. A ruling that asks for one plain change needs none of this: it goes straight
to the sign-off (step 7).

The steps keep their own skills. The hold still records what the operator owes
before the first framing, each hand-back is still recorded before you post it,
and the sign-off still closes the conversation. Each tool call starts a fresh
shell, so set `CONV`, `CONVERSATION` and `SUBJECT` literally, from what step 1
found, at the top of every call below.

## Settle it, one item at a time

- **Start from a read of the document.** Send it to a read-only subagent where
  one is offered, so the conclusions reach the thread and the file does not. Ask
  for findings with line references at the commit it read. When the subject's
  notes hold an earlier scaffold, ask first whether its rework carried it, item
  by item, and then what fresh eyes find. No review check compares a rework with
  its scaffold, so this read is the one that does.
- **Put up one item a turn, with your recommendation.** The operator rules on
  it, and you move on. Items of one kind can go up together as a table to
  redline, one row each with your proposed verdict.
- **Keep the big picture yourself.** You hold what is settled, what is open and
  what comes next, and you say so when the whole has moved, so the operator can
  stay on the item in front of them.
- **Check a claim before you offer it.** A proposal the operator accepts becomes
  a decision the worker transcribes. Read what another system does or cannot do
  at a named commit, and send a call the document rests on to a subagent charged
  with breaking it.
- **Record each ruling on the subject when it lands (step 6),** dated, in the
  operator's words where they gave them.

## Where the big picture lives between sittings

It lives on the subject's notes: the dated rulings, and the newest
`## Current state` block, which the next sitting primes from (step 4). When a
sitting stops with items still open, write that block with them under
`Open questions`. A spec cannot hold it, because a sitting writes no files and a
spec moves only when a rework lands. A spec gains the decisions as a line of the
scaffold, when the document's reasons belong in the repo.

## Write the scaffold

Once nothing is open, name what the rework will carry in the hand-back and take
the operator's go. Their go is the ruling, and the block is how it is written
down, so they owe no second read of it.

Then write every decision into one `## Current state` block. That block is the
scaffold, the rework's whole brief. A worker who reads only the block, the
document and the sources the block cites must be able to finish with no call the
operator would want to make. Read each line that way:

- **Every section gets a verb:** keep, cut, rewrite or add. A closed set says it
  is closed, and says what becomes of whatever it does not name.
- **A rewrite carries its substance:** what the section must say, with the
  operator's words quoted where they gave them. Copy an accepted proposal's text
  in, because "as recommended" sends the worker to a transcript.
- **A rule states its test.** A rule for the whole document names the test each
  row or sentence must pass and a line to copy the register from, and the worker
  runs it on each one.
- **A line decides.** "Consider", "as appropriate" and "X or Y" with both open
  hand the worker a call. Take that call back to the operator.
- **A fact nobody has settled goes under `VERIFY`,** with where to read it and
  where the document states it.

The block goes on the subject. When the PR's anchor is another bead, it goes on
that anchor instead, because the rework's reviewers read it there, so use that
bead's id in place of `$SUBJECT`. The first lines below are the worker's rules,
so keep them as they stand:

```bash
TODAY=$(date -u +%Y-%m-%d) \
  && gc bd update "$SUBJECT" --append-notes "## Current state ($TODAY)
$(cat <<'SCAFFOLD'
<what the operator ruled and where the document stands, in a sentence or two>

This block is the rework's scaffold: decisions, not questions, settled against <the files> at <the commit>.
Where a file's text and this block disagree, this block wins.
Its facts are yours to check: re-derive each count, line reference and claim about another system, and where one is false, write what is true and say so in a note on this bead.
Where it names a thing and leaves the form open, take the smallest form that carries the decided content and list each choice in that note, because the re-review reads this bead.
Self-review reads the branch against this block, line by line.
A point this block and its sources cannot settle goes to the operator through a human gate. Never decide it.

Decisions in force:
WHOLE DOCUMENT: <each rule, its test, and a line to copy the register from>
<file>, <section> (lines <a>-<b>): keep
<file>, <section> (lines <a>-<b>): cut
<file>, <section> (lines <a>-<b>): rewrite. <what it must say>
<file>, after <section>: add. <what it must say>
OTHER FILES: <each other file the decisions reach, with the same verbs, and what the PR's summary must say>
VERIFY: <each fact nobody has settled, where to read it, and where the document states it>

Open questions: none
SCAFFOLD
)" \
  && gc bd show "$SUBJECT" --json | tr -d '[:cntrl:]' | jq -e --arg h "## Current state ($TODAY)" '(.[0].notes // "") | contains($h)' >/dev/null \
  && echo "the scaffold reads back, dated $TODAY"
```

No closing line means the scaffold did not land: send nothing.

## Send one rework

On an open PR the sign-off files the rework, and its ruling line is what the
worker starts from, so that line names the block. Pass the bead that holds it and
the date the write printed:

```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" \
  --outcome "<what this sitting settled, and that the rework is sent, at most 140 characters>" \
  --ruled yes --ruling "Rework PR #<number> to the scaffold in the notes of <bead>, the block headed ## Current state (<date>)" \
  --route human --no-wait --rework
```

The `converse-settle` step carries the rest of that call, such as `--pr-anchor`
when the ruling reaches more than one PR. Send it only when no rework is running
on the branch: a running worker may never read a newer block, and two workers on
one branch collide at the push.

With no PR open, `--rework` has nothing to act on. A subject that is the work
keeps the block in its own notes, and work on a new bead names the block in its
description the same way the ruling line does. Send either one as the
`converse-settle` step says.

A further round is another block and one more rework, and the newest block is the
one in force. When the operator engages the document again, start again from the
read above.
