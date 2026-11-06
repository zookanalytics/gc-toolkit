---
name: backlog-refinement
description: Use when you are the po in a backlog refinement sitting, working the queue of held new work (gc beads list --label hold:mayor) with the operator, such as sorting the queue into proposals, sequencing the work to place, bringing it in pieces and applying each ruling. For a portfolio sync over the epics, your prompt's levers are the method.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Backlog refinement

A backlog refinement sitting works the queue with the operator: every bead that
Gas City's `hold:mayor` label holds. You propose one disposition for each bead,
with your reasons, and the operator rules. You apply each ruling through its
lever and read it back before you bring the next piece. Nothing starts without
the operator's word, and the queue waits between sittings for as long as the
operator chooses.

The pack's scripts are called through `gc <binding> scripts-dir`, where
`<binding>` is the name the city imports the pack under. `gc skill list` prints
it in this skill's FROM column.

## 1. Read the queue against the target

Open from the target of each rig the queue reaches, which the rig's `AGENTS.md`
states (your prompt's "The rig's target"). Then list the queue, grouped by rig,
with each bead's priority:

```bash
gc beads list --label hold:mayor --format=json \
  | jq -r '(if type == "array" then . else .beads end)[] | "\(.id)\tP\(.priority // "-")\t\(.title)"' | sort
```

Read the open epics of each rig the queue reaches, with what holds each, since
most dispositions name one (your prompt's "Reads").

## 2. Propose one disposition for each bead

| Disposition | When | It names |
|---|---|---|
| close as fixed | the default branch already has the fix; cite what shows it | the commit, or the bead that fixed it |
| close as duplicate | another bead, open or closed, carries the same need | that bead |
| close as not needed | the premise is gone, or the work is not worth doing; say why | the bead the ruling rests on |
| send where the rig says | the rig's `AGENTS.md` says where this kind of problem goes, such as onto the bead that retires the code it lives in | that bead |
| place under an epic | the work serves the hypothesis of an epic nothing parks | the epic, or its open Delivery whose aim covers the bead |
| park with its epic | the work belongs to an epic that a park holds, so it waits with that epic | the epic |
| place on its own | a defect that hurts the operator or a rig now and is worth building without an epic; say what it hurts | nothing |
| leave held | it waits for a later sitting, such as for an epic that does not exist yet | nothing |
| ask | it needs the operator's judgment, such as a design or product question, or you cannot tell; put the question in the reason | nothing |

Check before you propose:

- **Send where the rig says:** the file still exists on the rig's default branch,
  and the bead that takes the problem is still open. A file that is gone means
  close as fixed or as not needed.
- **Place or park:** read the epic's description and check that the bead serves
  its hypothesis, not only its area. An area that carries no hypothesis is not an
  epic (`docs/epics.md`, "Epics are mortal"), so it is never a placement target.
- **Place on its own:** use it sparingly, and name the harm.

Read only what settles the bead, about two reads a bead and four at most. When
that does not settle it, propose `ask` or say that your confidence is low.

- One bead, without its long notes:
  `gc bd --rig <rig> show <id> --json | jq -r '(if type == "array" then .[0] else . end) | .title, .status, .description, ((.notes // "") | .[0:1500])'`
- A first reaction's card in the notes (Understanding, Found, Proposal,
  Disposition) is a strong lead. Check it, because it can be stale.
- Code, on the rig's default branch only, in the rig's checkout:
  `git -C <checkout> show origin/<branch>:<path>`,
  `git -C <checkout> log origin/<branch> -- <path>` and
  `git -C <checkout> grep <pattern> origin/<branch> -- <paths>`. Fetch nothing,
  check out nothing and change nothing.
- Duplicates:
  `gc bd --rig <rig> search "<distinctive words>" --status all --limit 20 --json | jq -r '.[] | "\(.id) \(.status) \(.title)"'`

## 3. Sequence what you would place

Order the beads you propose to place by WSJF against the rig's target, as your
prompt's "Sequencing: WSJF" says: value, time criticality, and
risk reduction or opportunity enablement, over job size. Compare them with one
another and recommend each bead's priority, or its shift under its parent, with
the reasoning in words. Store no score.

## 4. A queue too long to read in the sitting

Sort it before you bring it, with read-only subagents, once the operator agrees.
Tell the operator how long the sort will run and that they can step away while
it does.

- Split the queue into chunks of about 20 beads, and start one sorter per chunk,
  all at once. Give each its chunk, the open epics with what holds each, each
  rig's `AGENTS.md` target, and sections 2 and 3 of this skill.
- A sorter changes nothing: no bead writes, no slings, no closes, no notes, and
  no edits, fetches or checkouts in any repository. It writes one file, one
  tab-separated row per bead in its chunk: id, priority, disposition, what it
  names (or `-`), confidence (`high`, `med` or `low`), a reason of one plain
  sentence, and a short title. It checks its row count against its chunk.
- A sorter proposes one disposition and one sentence, so read further on any
  bead the operator asks about.

## 5. Bring it in pieces

- Each piece fits one screen, says what its items are in plain words, and carries
  a recommendation for each item.
- The first piece is the clear ones, as lists the operator can accept in a word
  or pull items from: the closes and the beads sent where the rig says, where
  your confidence is high.
- Then bring the rest by disposition and by subject, at most about 25 items a
  piece, with the work to place in its WSJF order.

## 6. Apply each ruling

Apply the piece's rulings through your prompt's levers, read each write back, and
only then bring the next piece. Each ruling's note gives the operator's reason in
words. When the operator turns down a proposal that moves no lever, append their
reason to that bead's notes, so a later sitting reads it before proposing the
same again:

```bash
gc bd --rig <rig> update <bead> --append-notes "Backlog refinement: <what was proposed>; the operator declined: <their reason>."
```

A bead sent where the rig says takes the edge the waits skill gives for it, and
gets no route. It loses its hold: list its labels
(`gc bd --rig <rig> label list <bead>`), remove each one that spells
`hold:mayor` in any case, one `--remove-label` each
(`gc bd --rig <rig> update <bead> --remove-label hold:mayor`), and list them
again to see that none is left, because bd removes a label only by its exact
text.

## 7. Stop when the operator says

Each ruling is on its bead, and what is left stays held, so the next queue read
shows where the next sitting starts. Run `gc runtime drain-ack` once the operator
says the sitting is done.
