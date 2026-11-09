---
name: converse-epic-review
description: Converse's review of an epic, where the operator rules continue, shift or close on it (safety-critical).
---

# Reviewing an epic

A review is the sitting where the operator judges an epic: its contract, its
course, and any work that has landed under it. It ends in one of three rulings:

- **continue**: the hypothesis is not answered yet, and the course holds;
- **shift**: the course changes, and the hypothesis may change with it;
- **close**: the hypothesis is answered, with its outcome: it held, it was
  disproven, it cannot be met as stated, it stalled, or it ran past what it was
  worth.

The review after a Delivery lands is the epic's Epic Checkpoint, and it also
closes each landed Delivery. A Delivery is an epic under an epic, with an
`Aim:` line and no hypothesis, and it has landed when it has Stories and every
one has closed. Every review judges the contract as it reads now: nothing marks
an epic as reviewed, and a past ruling never stands in for that judgment.

The ruling is the operator's. This skill adds to the prep, the hold, the record
and the sign-off, which still run from `converse-prep`, `converse-hold` and
`converse-settle`.

Each tool call starts a fresh shell, so set `CONV`, `CONVERSATION`, `SUBJECT`
and `EPIC` literally at the top of every call below. `EPIC` is the subject,
with two exceptions: for a Delivery it is the Delivery's parent, and for work
that waits on a judgment about an epic it is the epic its gate's message names.
This read tells them apart:
```bash
gc bd show "$SUBJECT" --json | jq -r '.[0] | "type=\(.issue_type) parent=\(.parent // "none") hypothesis=\((.metadata.epic_hypothesis // "none") | .[0:80])"'
```

## Read the contract and the evidence

Do this at the prep. The worker that built the work never judges it, so read
the work itself, never a worker's account of it.

Read the epic's contract and its notes, its history newest last: the filer's
note on whose words each field is, each review's block with the commits its
measures ran at, and each proposal recorded since:
```bash
gc bd show "$EPIC"
gc bd show "$EPIC" --json | jq -r '.[0].metadata | to_entries[] | select(.key | startswith("epic_")) | "\(.key): \(.value)"'
```
A field is the operator's words only where a record shows them stating or
approving it: the filer's note, or the block of the review that last set it.
When the notes say neither, read the field's write history
(`gc bd history "$EPIC" --events --json`) and the conversations on the epic.
Any other field is the proposal of whoever wrote it.

Judge the contract as it reads, whoever wrote it and whatever a past ruling
said, and write the change you propose for each gap:

- a missing field: the handle, the hypothesis and the boundaries first, then
  the closure condition and the indicators;
- the hypothesis's signal. Could it still come out wrong once the work lands?
  A count the work moves by itself, such as lines removed or members closed,
  cannot, so it is a leading indicator and not the signal. The signal must also
  be readable soon after the work lands, not only once data that does not exist
  yet arrives;
- boundaries on ground another epic owns until it closes, whatever its status.
  The list always includes this epic, so a run without it has not answered:
  `gc bd list -t epic --status open,in_progress,blocked,deferred,hooked,pinned --limit 0 --json | jq -r '.[] | "\(.id) \(.metadata.epic_boundaries // "none")"'`;
- each proposal recorded since the last review, and anything the evidence below
  contradicts.

Read the work under the epic, then each Delivery's Stories with the commit and
the PR each one landed. Read what sits under a bead from its parent-child edges,
as bd's close does, because the `--parent` filter of `gc bd list` also returns a
bead moved out from under its parent:
```bash
gc bd dep list "$EPIC" --direction=up -t parent-child --json | jq -r '.[] | "\(.id) [\(.issue_type) \(.status)] \(.title)"'
gc bd dep list <delivery> --direction=up -t parent-child --json | jq -r '.[] | "\(.id) [\(.status)] \(.metadata.merged_sha // "-") \(.metadata.pr_url // "-") \(.title)"'
```
Then read or run what the epic has of these:

- each landed Story's merged change and its closed bead
  (`git show --stat <merged_sha>`, `gh pr view <pr_url>`, `gc bd show <story>`);
- each check in `epic_closure_condition`, run again;
- each measured criterion, by one method, at the latest landing's commit and at
  the last review's, or at main's head while nothing has landed. Credit the
  landed work only with its share of a change the city's other work also moved;
- each graded criterion, for the operator to grade, or a note that it has no
  way to be graded;
- the leading indicators in `epic_indicators`, and the backstop that no
  capability is deleted to move a measure;
- each landed Delivery's `Aim:` line, against what its landing showed;
- the epic's other open work: each open Delivery, each member under the epic
  itself, and each PR in flight under either, a member at
  `merge_result=pull_request`.

A checkpoint reads every Delivery landed by now and closes them all under its
one ruling.

## Hold: gate only what waits for the ruling

Work that no judgment holds goes on while the operator decides. Gate only a bead
whose next step depends on the ruling:

- at a checkpoint, file the gate on each landed Delivery, with that Delivery as
  the bead that must wait. It has nothing unstarted under it, so its gate pauses
  no work;
- at any review, file it on each bead whose work depends on a judgment you
  frame, such as a Story whose scope the boundaries decide;
- a PR in flight that the ruling could retire or move (the next section).

Run the hold's block once for each, with one of these messages:
```
Rule on <epic>'s Epic Checkpoint: <delivery> has landed, and its close waits for the ruling
<what the operator rules on, and what the ruling closes>
```
```
Rule on <epic>'s review: <bead> waits for <the judgment>
<the judgment, the change you propose for it, and what waits on it>
```
Gate no other part of the epic, and never the epic itself: a gate on the epic
holds every unstarted part of it until the operator rules. A review that
nothing waits on needs no gate.

In the framing's decision, lead with your recommendation, continue, shift or
close, and what each costs. In the body above it, give what you read: the
contract with whose words each field is and what the test of its signal found,
the measures with their commits, the grades the operator owes, each landed
Delivery's aim against what it showed, and the open work. Quote each change you
propose, as your proposal: a yes covers only the words you quoted. Ask each
judgment the ruling needs as its own question, with what waits on it, and on a
close, ask what becomes of each piece of open work.

## A PR in flight under the epic

When the ruling could retire a PR in flight under the epic, or move one into
another rig's store, its merge waits for the ruling too. At the hold, gate that
PR's anchor the same way, with a message that names what the ruling decides
about it. The sign-off's writer reaches a PR only through the subject or a gate
it answers, so the ruling reaches the PR only through that gate.

Each gate on a PR's anchor is answered on a call of its own, under that PR's
own ruling: the review's ruling and what it does to that PR, naming the PR. The
sign-off records a retirement's PR under the words of its ruling, so a re-run of
the call finds its own PR. Without `--pr-anchor`, a second call under the same
words would act on the first PR again and answer the second PR's gate, leaving
that PR free to merge. A PR the ruling retires:
```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --answer <the gate on its anchor> \
  --ruling "<the ruling, one line>; it retires PR #<number> (<its anchor>)" --pr-anchor <its anchor> \
  --retire <kind> --outcome "<where the epic stands now, at most 140 characters>" --no-wait
  # and --successor <the bead that carries the work now>, unless the kind is not-needed
```
A PR the ruling leaves standing:
```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --answer <the gate on its anchor> \
  --ruling "<the ruling, one line>; PR #<number> (<its anchor>) stands" --no-rework \
  --outcome "<where the epic stands now, at most 95 characters>" --no-wait
```
Until a call exits 0, its part of the ruling is not in place: repair what it
printed and run the same call again. A call that leaves a PR standing prints a
line when that PR's merge still waits on GitHub: pass the line on, with its
link.

Once each PR's own call has exited 0, the sign-off reaches none of those PRs and
takes none of `--rework`, `--no-rework` or `--retire`. When it refuses because
it reaches an open PR, that PR's gate is still open: make the PR's own call
first, then sign off again. Never add a PR answer to the sign-off instead,
because it would answer that gate under the review's ruling.

A subject that is itself a PR's anchor is the exception, because every call
reaches it. A call under another PR's ruling leaves it standing. Each call under
the review's own ruling gives that PR's answer, as the settle step gives it, and
those are write 2's answer to the Deliveries' gates, write 5's to a re-homed
bead's gate, and the sign-off. Each gives the same ruling, word for word, and
the same answer, so the first carries out a rework or a retirement, and the
calls after it find it done. The subject's gate takes no call of its own, and
the sign-off answers it, unless a close retires the PR. Then write 5 answers
that gate on a call of its own, as write 2 answers one, because a bead above the
PR cannot close while the PR is open, and a retired PR has nothing left to
release.

## The writes, in order

Once the operator rules, make these writes in this order. Notes are
append-only, so never pass `--notes`.

**1. Record the review on the epic.** The block says what prompted the review,
the ruling, and the contract after it with whose words each field is. It names
each landed Delivery the checkpoint closes, or `none`, and each judgment still
owed with its gate and the work that waits on it. While reviews run by hand, it
also says what was mechanical, what took judgment and what the contract lacked.
The block is written before anything else, and its write's exit decides whether
it landed:
```bash
TODAY=$(date -u +%Y-%m-%d) \
  && RECORD="## Epic review, $TODAY
$(cat <<'BLOCK'
Prompted by: <what called this review: the epic's filing, the operator's call, a judgment an agent asked for, or each landed Delivery's id>
Ruling: <continue, shift or close>. <why; on a close, the outcome>
Contract: <each field as it reads after the ruling, and whose words it is: the operator's, or whose proposal and whether this ruling took it>
Measures: <each measure, its value, the commit it was run at, and the method, or none>
Grades: <each graded criterion and the operator's grade, or why it has no way to be graded, or none>
Indicators: <each leading indicator and the backstop invariant, as read, or none>
Deliveries: <each landed Delivery's aim and what its landing showed, or none>
Open: <each judgment still owed, the gate that asks it and the work that waits on it, or none>
Next: <what comes next; on a close, each piece of open work and what becomes of it>
Mechanical: <what was mechanical>
Judgment: <what took judgment>
Contract lacked: <what the contract lacked>
BLOCK
)" \
  && gc bd update "$EPIC" --append-notes "$RECORD" \
  && echo "the review record is on $EPIC"
```
No closing line means the store refused the record: write nothing more, and say
so in the thread. When the subject is the epic, this block is the settle step's
record. When the subject is another bead, the settle step's record on it is one
line naming this block.

**2. Record the contract and the ruling on the epic, then answer the gates the
closes wait on.** Whatever the ruling, record each contract field it sets in its
own key: a change the operator took, a field they stated, or a shift's new aim.
Leave out the line of each field the ruling does not set. A proposal the
operator did not take stays out of the keys, and the block says what became of
it. `epic_ruling_at` is when the operator ruled, which is now, and
`epic_ruling_evidence` names each human gate the ruling clears. Those are among
the gates the conversation replies to, which this lists:
```bash
gc bd list --id "$CONVERSATION" --all --json | jq -r '[.[0].dependencies[]? | select(.type == "replies-to") | .depends_on_id] | join(" ")'
```
```bash
gc bd update "$EPIC" --set-metadata epic_hypothesis="<the sentence: for whom, what changes, and the signal that shows it worked>" \
  --set-metadata epic_handle="<three to five words>" \
  --set-metadata epic_boundaries="<the axis it is cut on, and the work beside it that it is not, with where that lives>" \
  --set-metadata epic_closure_condition="<the checks a person runs to answer the hypothesis>" \
  --set-metadata epic_indicators="<the signals watched while it is in flight>" \
  --set-metadata epic_ruling=<continue|shift|close> \
  --set-metadata epic_ruling_reason="<why; on a close, the outcome>" \
  --set-metadata epic_ruling_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --set-metadata epic_ruling_by="$GC_SESSION_NAME" \
  --set-metadata epic_ruling_evidence="<each gate the ruling clears, separated by spaces>"
```
When the ruling clears no gate, put `--unset-metadata epic_ruling_evidence` in
place of the last line, so the last ruling's evidence does not stand for this
one.

Then answer, before any close below, each gate on a landed Delivery, through
the sign-off's writer: the close gate refuses a bead an open human gate holds.
Each gate on a PR's anchor takes its own call, as the section above gives it:
```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate> \
  --ruling "<the ruling, one line>" \
  --outcome "<where the epic stands now, at most 140 characters, or 95 when it leaves the subject's PR standing>" --no-wait
  # --answer <gate> once for each gate on a landed Delivery
  # and, when the subject is a PR's anchor, that PR's answer (the section above)
```
A gate on work that waits for a judgment takes no call here, because its answer
sends that work on. The sign-off answers it once every write below has landed,
unless write 5 closes that work first. A gate whose judgment the ruling leaves
open stays owed: name it with `--leave` at the sign-off.

**3. At a checkpoint, close each landed Delivery.** Write 6 closes beads the
same way, and no close is ever forced. First, nothing under the bead may be
open. This prints what still is:
```bash
gc bd dep list <bead> --direction=up -t parent-child --json | jq -r '.[] | select(.status != "closed") | "\(.id) [\(.status)] \(.title)"'
```
Settle a follow-up opened since the Delivery landed with the operator first, as
write 5 settles an item. A bead whose PR was retired stays open until the
refinery's next pass over that PR finishes the retirement, so its close waits
for that pass.

Then release the bead from its park, if it has one. `gc-helm.sh park` gives a
bead one `blocks` edge, onto a gate of its own or onto a bead it was parked
behind, and other beads can be parked behind the same gate. This lists the
bead's open blockers, its park among them:
```bash
gc bd dep list <bead> --direction=down -t blocks --json | jq -r '.[] | select(.status != "closed") | "\(.id) [\(.issue_type)\(if (.await_type // "") != "" then " awaiting " + .await_type else "" end)] \(.title)"'
```
This lists every other bead still waiting on the park. It always prints a line,
so a run that prints nothing has not answered: run it again before either write
below.
```bash
gc bd dep list <park> --direction=up -t blocks --json | jq -r --arg b <bead> '[.[] | select(.id != $b and .status != "closed") | "\(.id) [\(.status)] \(.title)"] | if length == 0 then "nothing else waits on it" else .[] end'
```
A park's own gate, one with no await type, closes when that list says
`nothing else waits on it`, or when the ruling also releases each bead it lists:
`gc bd close <gate> --reason "<the ruling, one line>"`. Otherwise take off only
this bead's edge, and the park holds the rest: `gc bd dep remove <bead> <park>`.
A blocker that is not a park's own gate never closes here: a park behind
another bead releases this one by its edge alone, and a gate awaiting a person
clears only by an answer.

Then close the bead through the close gate, with the ruling as its reason:
```bash
"$CONV/finalize-gate.sh" check <bead> && gc bd close <bead> --reason "<the ruling, one line>"
```
The gate refuses while a human gate holds the bead or a stewarded epic has no
close ruling, and bd refuses while anything under the bead is open or a blocker
holds it. Settle what the refusal names and run the line again.

**4. On continue or shift, aim the next body of work.** On a shift, re-aim
each open Delivery whose aim the shift changes. Read its description, then
write it back whole with the new `Aim:` line:
`gc bd update <delivery> --description "<the description, with its new Aim: and Done when: lines>"`.

When the ruling aims a next Delivery, list the epic's open Deliveries first, and
put work an open Delivery's aim already covers into that one. A list that errors
is no empty answer, so file a new one only once the list has answered:
```bash
gc bd dep list "$EPIC" --direction=up -t parent-child --json | jq -r '.[] | select(.issue_type == "epic" and .status != "closed") | "\(.id) \(.title)"'
```
```bash
gc bd create "Delivery: <what it lands>" -t epic --parent "$EPIC" \
  -d "Aim: <the portion of the epic's hypothesis its landing tests>
Done when: <what lands>" --json
```
A Delivery goes to no pool, because its Stories are the work, and the `work`
skill files them under it.

Then set the epic's priority and park as the ruling names them. An epic under a
parent takes `--shift <±n>` in place of the P-value:
```bash
"$CONV/gc-helm.sh" priority "$EPIC" <P0-P4>
"$CONV/gc-helm.sh" park "$EPIC" "<the ruling, and what releases the park>"
```
A ruling that unparks the epic releases it from its park instead, by write 3's
release step with `"$EPIC"` as the bead. When another bead still waits on that
park, only the epic's edge comes off: `gc bd dep remove "$EPIC" <park>`.

**5. On close, settle the epic's other open work before anything is
released.** bd refuses to close an epic while a child of it is open, and the
epic can still hold other Deliveries, Stories under itself and PRs in flight.
The operator decides each item, whatever the outcome. A PR the ruling retires
whose anchor no gate holds yet gets one first, filed the way the hold files
one. Each item goes one of three ways:

- **Work that serves another hypothesis moves to the epic that owns it**, filed
  first when there is none (the `work` skill). In the same store the bead takes
  a new parent, that epic's open Delivery whose aim covers it or else the epic
  itself, and a run or PR in flight goes on under it:
  `gc bd update <bead> --parent <delivery-or-epic>`. An edge holds only within
  one store, so work whose epic is in another rig's store is filed again there,
  and this bead closes as re-homed onto the new one. With a PR in flight, that
  close is the PR's retirement on its own call, with
  `--retire re-homed --successor <new bead>`, and otherwise it is the
  disposition writer:
  `"$CONV/bead-rehome.sh" --origin <bead> --successor <new bead> --kind re-homed --note "<the ruling, one sentence>"`.
  The writer refuses a bead a human gate holds, and the gate's answer would
  send that bead on in this store. So disarm and release such a bead first,
  then answer its gate on a call of its own, as write 2 answers one, and run
  the writer last:
  `"$CONV/deferred-dispatch.sh" disarm <bead> --reason "<the ruling, one sentence>" && "$CONV/gc-helm.sh" takeaway <bead> "<the ruling, one sentence>" --release --no-wait`.
  A Delivery never moves whole, because its aim answers this epic's hypothesis,
  so its Stories move one by one.
- **Work worth doing on its own moves out to ordinary flow** with no parent:
  `gc bd update <bead> --parent ""`. That is a decision about the item, never
  the default for whatever is left.
- **Work that served only this hypothesis is retired.** Retire a PR in flight on
  its own call, with `--retire not-needed`. Any other bead closes as the `work`
  skill closes a bead that needs no work: stop a run in flight and disarm an arm
  first, then record the no-op and run the disposition writer, with this
  conversation as the evidence that ruled it out:
  ```bash
  gc bd update <bead> --set-metadata gc.work_outcome=no-op \
    && "$CONV/bead-rehome.sh" --origin <bead> --successor "$CONVERSATION" --kind not-needed --note "<the ruling, one sentence>"
  ```
  A bead a human gate holds is stood down instead, with the gate's `await_id`
  as the key. It removes the arm and ends the run before it answers the gate,
  then closes the bead:
  `"$CONV/stand-down.sh" <bead> --key <situation-key> --ruling "<the ruling, one sentence>" --successor "$CONVERSATION"`.

**6. On close, close each other Delivery, then the epic,** as write 3 closes a
bead, with the ruling as each close's reason. Release the epic's park first,
because its edge to the park blocks the close. The close gate passes the epic
once write 2 has recorded the close ruling with its outcome.

**Last, whatever the ruling, sign off** as the settle step says, once nothing
important is pending: `--ruled yes --ruling "<the ruling, one line>" --no-wait`,
with an outcome of at most 140 characters, or 95 when it leaves the subject's
PR standing. Add `--leave <gate>` for each gate write 2 left owed: the sign-off
answers every gate the conversation replies to that no `--leave` names, which
would release the work still waiting on that judgment. When a gate left owed
holds the subject, leave out `--no-wait` too, because the subject is then parked
for a person. Then drain.
