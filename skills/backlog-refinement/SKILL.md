---
name: backlog-refinement
description: Use when you are the po in a backlog refinement sitting, working the queue of held new work (the beads labeled hold:mayor) with the operator, such as sorting the queue into proposals, sequencing the work to place, bringing it in pieces and applying each ruling. For a portfolio sync over the epics, your prompt's levers are the method.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Backlog refinement

A backlog refinement sitting works your rig's queue with the operator: every
bead in your rig's store that Gas City's `hold:mayor` label holds. Each rig has
its own po, and another rig's queue is its po's. You propose one disposition for each bead,
with your reasons, and the operator rules. You apply each ruling through its
lever before you bring the next piece, and the write's exit says whether it
landed. Nothing starts without
the operator's word, and the queue waits between sittings for as long as the
operator chooses.

The pack's scripts are called through `gc <binding> scripts-dir`, where
`<binding>` is the name the city imports the pack under. `gc skill list` prints
it in this skill's FROM column.

## 1. Read the queue against the rig's goals

Open from your rig's product goals and each doc that page says its goals come
from, as your prompt's "The rig's goals" reads them from the default branch.
Then list the queue with each bead's priority, by the queue read in your
prompt's "Reads", piped through `sort`. That read keeps the beads of your rig's
store and takes the label trimmed and in any case, as Gas City's hold does.
`--label hold:mayor` matches only the exact text, so it would leave out a bead a
person labeled `Hold:Mayor`, which no worker is served either.

Read your rig's open epics, with what holds each, since most dispositions name
one (your prompt's "Reads").

### When the goals are missing or change

A rig whose default branch carries no `docs/product-goals.md`, and whose
`docs/review-pm.md` names no other place for its goals, is asked for that page
by one request. A PM review files it under the token
`docs/product-goals.md: missing` and counts a closed one too, so a sitting looks
for that request first and never files a second:

```bash
gc bd --rig <rig> list --all --type=bug --title-contains "docs/product-goals.md: missing" --json
```

- **The request carries the operator's words**, in its description or its
  notes: open from them, and ask nothing.
- **Otherwise ask the operator what the rig's work is for.** Their answer is the
  rig's goals for this sitting. Once they agree on the words, put them on the
  request, so the page states them and no later sitting asks again:
  - an open request:
    `gc bd --rig <rig> update <bead> --append-notes "The operator's product goals: <their words>"`;
  - a closed one, since the page it asked for is still missing: reopen it with
    `gc bd --rig <rig> reopen <bead> --reason "docs/product-goals.md is still missing"`,
    then append their words as above;
  - none, when the list printed `[]`:
    `gc bd --rig <rig> create "State the operator's product goals (docs/product-goals.md: missing)" -t bug -d "<their words>" --json`.

  A list that printed no JSON array did not answer: file nothing, and tell the
  operator their words wait for the store.
- **Send the request on**, so a normal PR writes the page. While `hold:mayor`
  holds it, place it, which sends it and lifts the hold:
  `"$(gc <binding> scripts-dir)/gc-helm.sh" place <bead> --standalone`.
  Otherwise sling it: `gc sling <rig>/<binding>.polecat <bead>`. A request
  already routed or in progress is on its way, so send it nothing.

When the operator changes goals the rig already keeps, file the change once they
agree on its words, with
`gc bd --rig <rig> create "docs: <the change> in the rig's product goals" -t task -d "<their words>" --json`,
and send it with `gc sling <rig>/<binding>.polecat <bead>`.

## 2. Propose one disposition for each bead

| Disposition | When | It names |
|---|---|---|
| close as fixed | the default branch already has the fix; cite the commit | the bead the commit names, under `fixed-upstream` |
| close as duplicate | a closed or shipped bead in this bead's store did the same work | that bead, under `duplicate` |
| fold into another | an open bead carries the same need | that bead, under `folded` |
| close as not needed | the premise is gone, or the work is not worth doing; say why | the bead the ruling rests on, under `not-needed` |
| send where the rig says | the rig's `AGENTS.md` says where this kind of problem goes, such as onto the bead that retires the code it lives in | that bead |
| place under an epic | the work serves the hypothesis of an epic nothing parks | the epic, or its open Delivery whose aim covers the bead |
| park with its epic | the work belongs to an epic that a park holds, so it waits with that epic | the epic |
| place on its own | a defect that hurts the operator or a rig now and is worth building without an epic; say what it hurts | nothing |
| leave held | it waits for a later sitting, such as for an epic that does not exist yet | nothing |
| ask | it needs the operator's judgment, such as a design or product question, or you cannot tell; put the question in the reason | nothing |

Check before you propose:

- **Close as fixed:** the commit's subject names its bead, the id in parentheses
  (`git -C <checkout> log -1 --format=%s <commit>`), and `fixed-upstream` needs
  that bead closed or shipped in this bead's store. A fix whose commit names no
  such bead is an `ask`, with the commit in the reason.
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

Order the beads you propose to place by WSJF against the rig's goals, as your
prompt's "Sequencing: WSJF" says: value, time criticality, and
risk reduction or opportunity enablement, over job size. Compare them with one
another and recommend each bead's priority, or its shift under its parent, with
the reasoning in words. Store no score.

## 4. A queue too long to read in the sitting

Sort it before you bring it, with read-only subagents, once the operator agrees.
Tell the operator how long the sort will run and that they can step away while
it does.

- Split the queue into chunks of about 20 beads, and start one sorter per chunk,
  all at once. Give each its chunk, the open epics with what holds each, the
  rig's goals as section 1 read them, and sections 2 and 3 of this skill.
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

Apply the piece's rulings through your prompt's levers, let each write's exit
say whether it landed, and only then bring the next piece. Each ruling's note
gives the operator's reason in words. When the operator turns down a proposal
that moves no lever, append their reason to that bead's notes, so a later
sitting reads it before proposing the same again:

```bash
gc bd --rig <rig> update <bead> --append-notes "Backlog refinement: <what was proposed>; the operator declined: <their reason>."
```

A close runs the `work` skill's disposition writer, `bead-rehome.sh`, with the
kind and the bead its row names as `--kind` and `--successor`, and the operator's
reason in `--note`, with the commit for a fix.

A bead sent where the rig says takes the edge the waits skill gives for it, and
gets no route. It loses its hold: list its labels
(`gc bd --rig <rig> label list <bead>`), remove each one that spells
`hold:mayor` in any case, one `--remove-label` each
(`gc bd --rig <rig> update <bead> --remove-label hold:mayor`), because bd
removes a label only by its exact text.

## 7. Stop when the operator says

Each ruling is on its bead, and what is left stays held, so the next queue read
shows where the next sitting starts. Run `gc runtime drain-ack` once the operator
says the sitting is done.
