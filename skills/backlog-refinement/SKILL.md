---
name: backlog-refinement
description: Use when you are the po in a backlog refinement sitting, working the queue of held new work (the beads labeled hold:mayor) with the operator, such as sorting the queue into proposals, sequencing the work to place, bringing it in pieces and applying each ruling. For a portfolio sync over the epics, use portfolio-sync.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Backlog refinement

A backlog refinement sitting works your rig's queue with the operator: every
bead in your rig's store that Gas City's `hold:mayor` label holds. Each rig has
its own po, and another rig's queue is its po's. You sort the queue by the
outcomes its beads serve, then propose one disposition for each bead, with your
reasons. The operator rules on each. You apply each ruling through its
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

Read your rig's open epics, with each one's hypothesis and what holds it, since
the sort and most dispositions name one (your prompt's "Reads").

### When the goals are missing or change

A rig whose default branch carries no `docs/product-goals.md`, and whose
`docs/review-pm.md` names no other place for its goals, is asked for that page
by one request. A PM review files it under the token
`docs/product-goals.md: missing` and counts a closed one too, so a sitting looks
for that request first and never files a second:

```bash
gc bd --rig <rig> list --all --type=bug --title-contains "docs/product-goals.md: missing" --json
```

- **The request is closed**, whether or not it carries the operator's words:
  reopen it first, with
  `gc bd --rig <rig> reopen <bead> --reason "docs/product-goals.md is still missing"`.
  The page it asked for is still missing, `place` refuses a closed bead, and a
  sling would start work on a bead that stays closed. The reopen keeps its
  words, so the bullets below take it as an open request.
- **The request carries the operator's words**, in its description or its
  notes: open from them, and ask nothing.
- **Otherwise ask the operator what the rig's work is for.** Their answer is the
  rig's goals for this sitting. Once they agree on the words, put them on the
  request, so the page states them and no later sitting asks again:
  - the request the list found:
    `gc bd --rig <rig> update <bead> --append-notes "The operator's product goals: <their words>"`;
  - none, when the list printed `[]`:
    `gc bd --rig <rig> create "State the operator's product goals (docs/product-goals.md: missing)" -t bug -d "<their words>" --json`.

  A list that printed no JSON array did not answer: file nothing, and tell the
  operator their words wait for the store.
- **Send the request on**, so a normal PR writes the page. A request already
  routed or in progress is on its way, so send it nothing. While `hold:mayor`
  holds it, place it, which sends it and lifts the hold, and otherwise sling it
  (`gc sling <rig>/<binding>.polecat <bead>`):
```bash
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
GCTK_SCRIPTS_DIR="$(gc <binding> scripts-dir)" "$GCTK" bead place <bead> --standalone
```

When the operator changes goals the rig already keeps, file the change once they
agree on its words, with
`gc bd --rig <rig> create "docs: <the change> in the rig's product goals" -t task -d "<their words>" --json`,
and send it with `gc sling <rig>/<binding>.polecat <bead>`.

## 2. Sort by outcome, then propose one disposition for each bead

Read across the whole queue before you rule on any one bead. Group the beads
that serve one outcome: what their work changes, and for whom, as an epic's
hypothesis states it, not the code they touch. For each group, name the open
epic whose hypothesis covers that outcome. A group that no open epic's
hypothesis covers is a theme. Then propose a disposition for each bead, with
its group in view.

| Disposition | When | It names |
|---|---|---|
| close as fixed | the default branch already has the fix; cite the commit | the bead the commit names, under `fixed-upstream` |
| close as duplicate | a closed or shipped bead in this bead's store did the same work | that bead, under `duplicate` |
| fold into another | an open bead carries the same need | that bead, under `folded` |
| close as not needed | the work should not be done or kept, in a case its check below lists; say which, and why | the bead the ruling rests on, under `not-needed` |
| send where the rig says | the rig's `AGENTS.md` says where this kind of problem goes | the bead it names |
| place under an epic | the work serves the hypothesis of an epic nothing parks | the epic, or its open Delivery whose aim covers the bead |
| park with its epic | the work belongs to an epic that a park holds, so it waits with that epic | the epic |
| graduate into a new epic | its group needs an epic of its own, when each condition its check below lists holds | the beads it would hold, and the epic you propose: its handle, hypothesis and boundaries |
| place on its own | it cannot wait for an epic, in a case its check below lists; say which | nothing |
| wait on a bead | it cannot go until something else happens, in a case its check below lists | the bead it waits on, or what the operator owes |
| ask | it needs the operator's judgment, such as a design or product question, or you cannot tell; put the question in the reason | nothing |

Check before you propose:

- **Close as fixed:** the commit's subject names its bead, the id in parentheses
  (`git -C <checkout> log -1 --format=%s <commit>`), and `fixed-upstream` needs
  that bead closed or shipped in this bead's store. A fix whose commit names no
  such bead is an `ask`, with the commit in the reason.
- **Send where the rig says:** the rule is still in the rig's `AGENTS.md` on its
  default branch, and the bead it names is still open.
- **Place or park:** read the epic's description and check that the bead serves
  its hypothesis, not only its area. An area that carries no hypothesis is not an
  epic (`docs/epics.md`, "Epics are mortal"), so it is never a placement target.
- **Graduate into a new epic:** read the hypothesis of each open epic section 1
  listed. Propose it when each of these holds:
  - none of those hypotheses covers the group's outcome;
  - the rig's goals make that outcome worth a push of its own.

  Write the hypothesis from that outcome, never from the beads' own fixes. It
  says for whom, what changes and the signal that shows it worked. Write the
  boundaries from the hypothesis (`docs/epics.md`, "The contract an epic
  carries"). Standing work, such as a set of failures or open bugs that keeps
  returning, gets one bounded push. Its closure condition names the lines it
  closes on (`docs/epics.md`, "Epics are mortal").
- **Place on its own:** propose it in one of these cases, and name it:
  - an emergency that cannot wait for an epic, such as the host going down;
  - work the operator names to run on its own, with where they named it.

  That a defect hurts is not enough, since most real defects do. Such a
  defect goes under the epic its outcome belongs to, or into its theme's new
  epic.
- **Wait on a bead:** propose it in one of these cases:
  - it cannot start until another bead lands;
  - another bead's landing may end its job;
  - it cannot go until the operator answers or acts.

  The bead it waits on is open. One in another rig's store takes a human gate
  in place of the edge, as the `waits` skill says. Work that goes on once that
  bead lands is placed as any other bead, so its row names the epic too. Work
  whose job that landing may end needs no epic, because the validating closer
  checks it then.

  A bead that waits on the operator was ruled on already. It waits for
  something only they can give, such as a decision, an approval or a path. It
  waits on a human gate that says what they owe, and it is placed as any other
  bead, so its row names the epic too. A question to put to the operator in
  the sitting is an `ask` instead.
- **Close as not needed:** propose it in one of these cases, and say which:
  - the premise is gone;
  - the work is not worth doing;
  - the bead waits on nothing, and each condition below holds.

  A bead that waits on nothing closes, rather than stay held with nothing to
  release it, when each of these holds:
  - it serves no open epic;
  - it belongs to no theme worth a push;
  - something would file it again if it mattered.

  Ask of it: would anything file this again if it mattered? Answer with what
  would, and name it in the reason, such as the check, the patrol or the
  failing run that found the defect, which files it again when it runs. A
  defect may have nothing that would, such as one a person reported by hand,
  or one that a single run found.

  A bead is not proposed for closing for want of a release when both of these
  hold:
  - it serves the rig's goals;
  - nothing would file it again.

  That covers a product idea of the operator's, an opportunity an agent
  noticed once, a risk that bites only once and a defect nothing would find
  again. Such a bead stays held, with a note of one line that gives the
  question that would decide it: what would make it worth doing, and what we
  would look at to know. Once the operator agrees, write the note:
  `gc bd --rig <rig> update <bead> --append-notes "Backlog refinement: kept, since nothing would file it again. What would decide it: <the question>."`

  Work that serves none of the rig's goals is still proposed for closing, idea
  or not.

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
the reasoning in words. Recommend each proposed epic's priority against the
rig's open epics the same way. Store no score.

## 4. A queue too long to read in the sitting

Sort it before you bring it, with read-only subagents, once the operator agrees.
Tell the operator how long the sort will run and that they can step away while
it does.

- Split the queue into chunks of about 20 beads, and start one sorter per chunk,
  all at once. Give each its chunk, the open epics with each one's hypothesis
  and what holds it, the rig's goals as section 1 read them, and sections 2 and
  3 of this skill.
- A sorter changes nothing: no bead writes, no slings, no closes, no notes, and
  no edits, fetches or checkouts in any repository. It writes one file, one
  tab-separated row per bead in its chunk: id, priority, the outcome it serves
  in a few words, the open epic whose hypothesis covers that outcome (or `-`),
  disposition, what it names (or `-`), confidence (`high`, `med` or `low`), a
  reason of one plain sentence, and a short title. It checks its row count
  against its chunk.
- A sorter proposes one disposition and one sentence, so read further on any
  bead the operator asks about.
- Once every sorter has returned, group all the rows by outcome before you
  bring anything. A sorter sees only its chunk, so a theme can span chunks.
  Propose each graduation from the whole group, and recheck the dispositions
  of its beads.

## 5. Bring it in pieces

- Each piece fits one screen, says what its items are in plain words, and carries
  a recommendation for each item.
- The first piece is the clear ones, as lists the operator can accept in a word
  or pull items from: the closes and the beads sent where the rig says, where
  your confidence is high.
- Then bring the rest by disposition and by subject, at most about 25 items a
  piece, with the work to place in its WSJF order.
- Each epic you propose to graduate is a piece of its own: its handle,
  hypothesis and boundaries, its priority, the beads it would hold, and, when it
  is a push on standing work, the lines it closes on.

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

A bead sent where the rig says goes there by the commands the rig's `AGENTS.md`
gives.

A graduation runs in this order, each write taking its exit:

1. File the epic in your rig's store with the `work` skill's epic writer,
   `epic.sh`, with the fields the operator agreed to and the note that says
   whose words each field is.
2. Set its priority through your prompt's levers.
3. Park it through those levers when the ruling says its push waits.
4. Only then place each of its beads under it. A placement sends at once a
   bead that nothing holds. Parking the epic later stops no run that has
   started.

A wait runs through the `waits` skill. Work that goes on once the bead it waits
on lands takes that skill's edge ("Make a bead wait on other work"), then its
placement. The placement arms it while the edge holds it. Work whose job that
landing may end takes the close brief, the edge and the arm of "Have a bead
checked and closed once other work lands", then the lift of its hold that
section gives. A bead that waits on the operator takes the human gate of "Wait
on a person", whose message says what they owe, then its placement. The
placement arms it while the gate holds it and lifts its hold, so it leaves the
queue and shows on the operator's board as something they owe. It starts once
they clear the gate.

## 7. Stop when the operator says

Each ruling is on its bead, and what the sitting did not reach stays held, so
the next queue read shows where the next sitting starts. Run
`gc runtime drain-ack` once the operator says the sitting is done.
