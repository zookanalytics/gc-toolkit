---
name: converse-epic-review
description: Converse's review of an epic, whenever its contract or its course needs the operator's judgment and at its Epic Checkpoint after work lands, where the operator rules continue, shift or close (safety-critical).
---

# Reviewing an epic

One procedure reviews an epic whenever its contract or its course needs the
operator's judgment (`docs/epics.md`, "Reviewing an epic"). The same steps
serve a thin epic just filed, an epic whose contract lacks something or is
contradicted by what has been found, and the Epic Checkpoint that follows the
landing of a Delivery under the epic. A Delivery has landed when it has
Stories and every one has closed.

At every review you read the contract and the evidence, propose the changes
the evidence calls for, gate only the work that waits on the answer, and frame
the judgments the operator owes. The operator rules continue, shift or close
(`docs/epics.md`, "How an epic closes"), and you make the ruling's writes in
the order below. An Epic Checkpoint also reads the work that landed and closes
each landed Delivery.

No field or status marks an epic as reviewed or unreviewed. A past ruling
records what the operator judged then. It never stands in for a judgment of
the contract as it reads now, so every review judges the contract as it reads.

The ruling is the operator's. You gather the evidence, frame the choice, and
once the operator rules, make its writes in the order below. The steps keep
their own skills: the prep, the hold, the record and the sign-off still run
from `converse-prep`, `converse-hold` and `converse-settle`, and this skill says
what a review adds to each.

Each tool call starts a fresh shell, so set `CONV`, `CONVERSATION`, `SUBJECT`
and `EPIC` literally at the top of every call below. `EPIC` is the epic the
review judges. It is the subject, unless the subject is a Delivery, an epic
whose parent is an epic and which carries no `epic_hypothesis`, or work that
waits on a judgment about an epic. Then `EPIC` is the Delivery's parent, or the
epic named in the message of the gate that holds the work. A landed Delivery is
one of the Deliveries the checkpoint closes. This read tells them apart:
```bash
gc bd show "$SUBJECT" --json | jq -r '.[0] | "type=\(.issue_type) parent=\(.parent // "none") hypothesis=\((.metadata.epic_hypothesis // "none") | .[0:80])"'
```

## Read the contract and the evidence

Do this at the prep, once the subject is primed. The worker that built work
under the epic never judges it, so read the work itself rather than any
worker's account of it.

Read the epic's contract and its notes. The notes are its history, newest last:
the note its filer wrote on whose words each field is, each review's block
with the commits its measures were run at, and each proposal an agent recorded
since:
```bash
gc bd show "$EPIC"
gc bd show "$EPIC" --json | jq -r '.[0].metadata | to_entries[] | select(.key | startswith("epic_")) | "\(.key): \(.value)"'
```
Whose words a field is comes from that history: the filer's note, or the block
of the review that last set the field. On an epic whose notes say neither, read
the field's write history (`gc bd history "$EPIC" --events --json`) and the
conversations that track the epic. A field that no record shows the operator
stating or approving is the proposal of whoever wrote it.

Then assess the contract as it reads, whoever wrote it and whatever a past
ruling said. Wherever one of these finds a gap, write the change you propose:

- a field the contract lacks: the floor (the handle, the hypothesis and the
  boundaries) first, then the closure condition and the indicators;
- the hypothesis's signal. Could it still come out wrong once the work lands?
  A count the work moves by itself, such as lines removed or members closed,
  cannot, so it is a leading indicator and not the signal. Can it be read soon
  after the work lands, without waiting for data that does not exist yet?
- the boundaries, against the ones the other open epics record and the
  deletion schedule in `docs/built-once-target.md`, either of which can own the
  epic's ground already:
  `gc bd list -t epic --status open --limit 0 --json | jq -r '.[] | "\(.id) \(.metadata.epic_boundaries // "none")"'`;
- each proposal recorded since the last review;
- what the evidence below contradicts.

Read the work under it, Deliveries and Stories alike, and then each Delivery's
Stories with the commit and the PR each one landed. Every read of what sits
under a bead uses its parent-child edges, the ones bd's close reads, because
the `--parent` filter of `gc bd list` also returns a bead moved out from under
it whose id still carries the parent's:
```bash
gc bd dep list "$EPIC" --direction=up -t parent-child --json | jq -r '.[] | "\(.id) [\(.issue_type) \(.status)] \(.title)"'
gc bd dep list <delivery> --direction=up -t parent-child --json | jq -r '.[] | "\(.id) [\(.status)] \(.metadata.merged_sha // "-") \(.metadata.pr_url // "-") \(.title)"'
```
Then read or run each of these that the epic has:

- each landed Story's merged change on main and its closed bead, read directly
  (`git show --stat <merged_sha>`, `gh pr view <pr_url>`, `gc bd show <story>`);
- each check in `epic_closure_condition`, run again;
- each measured criterion, run by one method at the commit of the latest landing
  you read and at the last review's commit, or at main's head as the baseline
  while nothing has landed. A measure the city's other work also moves is read
  against that work, so the landed work is not credited with the whole change;
- each graded criterion, which the operator grades. One with no way to grade it
  is recorded as such;
- the leading indicators in `epic_indicators`, and the backstop invariant;
- each landed Delivery's `Aim:` line, against what its landing showed about that
  portion of the hypothesis;
- the epic's other open work: each open Delivery, each member under the epic
  itself, and each PR in flight under either, a member at
  `merge_result=pull_request`.

An Epic Checkpoint reads every Delivery of the epic that has landed by now and
closes each under its one ruling. Each ruling overwrites the epic's last one,
so two sittings run back to back would each write the ruling fields, and the
second would overwrite the first's.

## Hold: gate only what waits for the ruling

Work under the epic that no judgment holds goes on while the operator decides.
What waits for the ruling is each bead whose next step depends on it. At a
checkpoint, that is the close of each landed Delivery: in the hold's gate step,
file the gate on each landed Delivery, with that Delivery as the bead that must
wait. At any review, it is also each bead whose work depends on a judgment you
frame, such as a Story whose scope the boundaries decide, and you file the gate
on that bead the same way. Run the hold's block once for each, with one of
these messages:
```
Rule on <epic>'s Epic Checkpoint: <delivery> has landed, and its close waits for the ruling
<what the operator rules on, and what the ruling closes>
```
```
Rule on <epic>'s review: <bead> waits for <the judgment>
<the judgment, the change you propose for it, and what waits on it>
```
A landed Delivery has nothing unstarted under it, so its gate pauses no work.
Gate no other part of the epic, and never the epic itself: a gate on the epic
holds every unstarted part of it until the operator rules. A review with
nothing waiting for its ruling needs no gate.

When the choice you frame would retire a PR in flight under the epic, or move
one into another rig's store, its merge waits for the ruling too. Gate that
PR's anchor the same way, with the message naming what the ruling decides
about it. The ruling can then retire it through the sign-off's writer, which
reaches a PR only through the subject or a gate it answers.

The framing leads with your recommendation, continue, shift or close, and what
each costs. Above the recommendation, give what you read: the contract as it
reads, with whose words each field is and what the test of its signal found,
the measures with their commits, the grades the operator owes, each landed
Delivery's aim against what it showed, and the open work. Quote each change
you propose, as your proposal, so that a yes approves words the operator has
read. Ask each judgment the ruling needs as a question of its own, and say what
waits on it. A yes covers only what the framing quoted. On a close, the framing
asks the operator what becomes of each piece of open work.

## The writes, in order

Once the operator rules, make these writes in this order. Notes are
append-only, so never pass `--notes`.

**1. Record the review on the epic.** The block says what prompted the review
and names each landed Delivery the checkpoint closes, or `none`. It gives the
contract as it reads after the ruling, with whose words each field is, and each
judgment still owed, with the gate that asks it and the work that waits on it.
While reviews run by hand, it also says what was mechanical, what took judgment
and what the contract lacked. The block reads back before anything else is
written:
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
  && gc bd show "$EPIC" --json | jq -e --arg b "$RECORD" '(.[0].notes // "") | contains($b)' >/dev/null \
  && echo "the review record is on $EPIC"
```
No closing line means the record did not land: write nothing more, and say so
in the thread. When the subject is the epic, this block is the record of the
settle step. When the subject is another bead, such as a Delivery or work that
waited on a judgment, that step's record on the subject is one line naming
this block.

**2. Record the ruling on the epic,** in the fields `docs/epic-stewardship.md`
registers ("Recording a ruling"). `epic_ruling_at` is when the operator ruled,
which is now. The evidence is each human gate the ruling clears, which the
conversation replies to. This lists them:
```bash
gc bd list --id "$CONVERSATION" --all --json | jq -r '[.[0].dependencies[]? | select(.type == "replies-to") | .depends_on_id] | join(" ")'
```
```bash
gc bd update "$EPIC" --set-metadata epic_ruling=<continue|shift|close> \
  --set-metadata epic_ruling_reason="<why; on a close, the outcome>" \
  --set-metadata epic_ruling_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --set-metadata epic_ruling_by="$GC_SESSION_NAME" \
  --set-metadata epic_ruling_evidence="<each gate the ruling clears, separated by spaces>"
```
When the ruling clears no gate, put `--unset-metadata epic_ruling_evidence` in
place of the last line, so the last ruling's evidence does not stand for this
one.

Then answer the gates now, on this turn, through the sign-off's writer. The
close gate refuses a bead that an open human gate holds, so every close below
waits for these answers, and the sign-off later reads each gate as already
cleared. One call answers, under the ruling, each gate a landed Delivery's
close waits on, and each gate on work whose judgment the ruling gave:
```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate> \
  --ruling "<the ruling, one line>" \
  --outcome "<where the epic stands now, at most 140 characters>" --no-wait
  # --answer <gate> once for each gate the ruling settles
```
A gate whose judgment the ruling leaves open stays owed: answer it on no call,
and name it with `--leave` at the sign-off (the `converse-settle` skill).

Each gate on a PR's anchor is answered on a call of its own, under that PR's
own ruling: the review's ruling and what it does to that PR, naming the PR.
When the subject is itself a PR's anchor, its own gate takes no call here,
because the sign-off answers it (the last step). The sign-off records the PR a
retirement acts on under the words of its ruling, so a re-run of the call
recovers its own PR. Two calls under the same words
share one record, and without `--pr-anchor` the second acts on the first PR
again and answers the second PR's gate with that PR left standing, free to
merge. A PR the ruling retires, with `--pr-anchor` naming it so that no other PR
is the target:
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
printed and run the same call again, which acts on the same PR. A call that
leaves a PR standing prints a line when that PR's merge still waits on GitHub:
pass the line on, with its link.

**3. At a checkpoint, close each landed Delivery.** Every close here and in
write 6 is made the same way, and none is forced. First, nothing under the
bead may be open. This prints what still is:
```bash
gc bd dep list <bead> --direction=up -t parent-child --json | jq -r '.[] | select(.status != "closed") | "\(.id) [\(.status)] \(.title)"'
```
A follow-up opened under a landed Delivery since it landed is settled with the
operator first, in one of the ways write 5 settles an item. A bead whose PR was
retired stays open until the refinery's next pass over that PR completes the
retirement, so the close waits for that pass.

Then release the bead from its park, if it has one. A park is the one `blocks`
edge `gc-helm.sh park` gives a bead, onto a gate of its own or onto an existing
bead it was parked behind, and another bead can be parked behind the same gate.
This lists the bead's open blockers, among them its park:
```bash
gc bd dep list <bead> --direction=down -t blocks --json | jq -r '.[] | select(.status != "closed") | "\(.id) [\(.issue_type)\(if (.await_type // "") != "" then " awaiting " + .await_type else "" end)] \(.title)"'
```
This lists every other bead still waiting on the park, or says that nothing else
does. It always prints a line, so one that prints nothing has not answered: run
it again before either write below.
```bash
gc bd dep list <park> --direction=up -t blocks --json | jq -r --arg b <bead> '[.[] | select(.id != $b and .status != "closed") | "\(.id) [\(.status)] \(.title)"] | if length == 0 then "nothing else waits on it" else .[] end'
```
A park's own gate, a gate with no await type, closes once that list says
`nothing else waits on it`, or once the ruling also releases each bead it lists:
`gc bd close <gate> --reason "<the ruling, one line>"`. Otherwise only this
bead's edge comes off, and the park holds the rest:
`gc bd dep remove <bead> <park>`. A blocker that is not a park's own gate never
closes here: a park behind an existing bead releases this bead by its edge
alone, and a gate awaiting a person clears only by an answer. Nothing under the
bead is open, so the release starts nothing.

Then close the bead through the close gate, with the ruling as its reason:
```bash
"$CONV/finalize-gate.sh" check <bead> && gc bd close <bead> --reason "<the ruling, one line>"
```
The gate refuses while a human gate holds the bead or a stewarded epic has no
close ruling, and bd refuses while anything under the bead is open or a blocker
still holds it. Settle what the refusal names and run the line again. Never
force a close.

**4. On continue or shift, aim the next body of work.** First record each
contract field the ruling sets, in its own key: each change the operator took,
each field the operator stated, and a shift's new aim. A field takes only the
operator's words or a change they approved, so leave out each line for a field
the ruling does not set. A proposal the operator did not take stays out of the
keys, and the block says what became of it:
```bash
gc bd update "$EPIC" --set-metadata epic_hypothesis="<the sentence: for whom, what changes, and the signal that shows it worked>" \
  --set-metadata epic_handle="<three to five words>" \
  --set-metadata epic_boundaries="<the axis it is cut on, and the work beside it that it is not, with where that lives>" \
  --set-metadata epic_closure_condition="<the checks a person runs to answer the hypothesis>" \
  --set-metadata epic_indicators="<the signals watched while it is in flight>"
```
On a shift, also re-aim each Delivery still open whose aim the shift changes.
A Delivery's aim is the `Aim:` line its description opens with, so read the
description, then write it whole with the new line:
`gc bd update <delivery> --description "<the description, with its new Aim: and Done when: lines>"`.

When the ruling aims a next Delivery, list the epic's open Deliveries first.
Work an open Delivery's aim already covers goes into that one, and a list that
errors is no empty answer, so file one only once the list has answered:
```bash
gc bd dep list "$EPIC" --direction=up -t parent-child --json | jq -r '.[] | select(.issue_type == "epic" and .status != "closed") | "\(.id) \(.title)"'
```
```bash
gc bd create "Delivery: <what it lands>" -t epic --parent "$EPIC" \
  -d "Aim: <the portion of the epic's hypothesis its landing tests>
Done when: <what lands>" --json
```
A Delivery goes to no pool, because its Stories are the work. The `work` skill
files its Stories under it.

Then set the epic's next priority and park, as the ruling names them. An epic
with no parent takes a P-value, and one under a parent takes a shift
(`--shift <±n>` in place of the P-value):
```bash
"$CONV/gc-helm.sh" priority "$EPIC" <P0-P4>
"$CONV/gc-helm.sh" park "$EPIC" "<the ruling, and what releases the park>"
```
A park the ruling makes states the ruling in its gate's title, as above. A
ruling that unparks the epic releases it from its park instead, by write 3's
release step with `"$EPIC"` as the bead. Its park's gate closes only when
nothing else waits on it or the ruling also releases what does, and otherwise
only the epic's edge comes off: `gc bd dep remove "$EPIC" <park>`. A ruling
that names no change to either leaves it as it is.

**5. On close, settle the epic's other open work before anything is
released.** bd refuses to close the epic while any child of it is open, and it
can still hold other Deliveries, Stories under the epic itself, and PRs in
flight under either. The operator decides each item, whatever the outcome, and
you carry out the decision. Meanwhile the epic's park, if it has one, keeps each
unstarted item from starting. A PR in flight the ruling retires, whose anchor
no gate of this conversation holds yet, gets one first, filed the way the hold
files it, so that its own call in write 2 can reach it. Each item goes one of
three ways:

- **Work that still coheres around a hypothesis moves to the epic that owns
  it.** File that epic when none does yet (the `work` skill). In the same store
  the bead takes a new parent, that epic's open Delivery whose aim covers it or
  else the epic itself, and a run or PR in flight goes on under it:
  `gc bd update <bead> --parent <delivery-or-epic>`. An edge holds only within
  one store, so work whose epic is in another rig's store is filed again there,
  and this bead then closes as re-homed onto the new one. With a PR in flight
  that close is the PR's retirement, on the PR's own call as write 2 shows,
  with `--retire re-homed --successor <new bead>`. Without one, it is the
  disposition writer:
  `"$CONV/bead-rehome.sh" --origin <bead> --successor <new bead> --kind re-homed --note "<the ruling, one sentence>"`.
  A whole Delivery does not move, because its aim answers this epic's
  hypothesis, so its Stories move one by one.
- **Work worth doing on its own, which serves no hypothesis, moves out to
  ordinary flow** with no parent: `gc bd update <bead> --parent ""`. That is a
  decision about the item, never the default for whatever is left.
- **Work that served only this hypothesis is retired.** A PR in flight is
  retired on its own call as write 2 shows, with `--retire not-needed`.
  Any other bead closes as the `work` skill closes a bead that needs no work:
  stop a run in flight and disarm an arm first, then record the no-op and run
  the disposition writer, with this conversation as the evidence that ruled it
  out:
  ```bash
  gc bd update <bead> --set-metadata gc.work_outcome=no-op \
    && "$CONV/bead-rehome.sh" --origin <bead> --successor "$CONVERSATION" --kind not-needed --note "<the ruling, one sentence>"
  ```

**6. On close, close each other Delivery, then the epic,** the way write 3
closes a bead. A Delivery's close reason is the ruling. The epic's park is
released before the epic closes, because its own edge to the park is a live
blocker. The close gate passes the epic once write 2 has recorded the close
ruling with its outcome, and so does the doctor invariant that reads it after
the close.

**Last, whatever the ruling, sign off** as the settle step says, once nothing
important is pending:
`--ruled yes --ruling "<the ruling, one line>" --no-wait`, with an
outcome of at most 140 characters. Add `--leave <gate>` for each gate write 2
left owed. The sign-off answers every gate the conversation replies to that no
`--leave` names, so a gate left out would be answered and would release the
work still waiting on its judgment. When one of those gates holds the subject,
leave out `--no-wait` too, because the subject is then parked for a person.

Unless the subject is a PR's anchor, the sign-off reaches a PR only through a
gate still open, or one closed with its own answer. Once each PR's own call has
exited 0, every gate on a PR's anchor carries that PR's own ruling, so the
sign-off reaches none of those PRs and takes none of `--rework`, `--no-rework`
or `--retire`. It reads each gate write 2 answered as cleared and closes the
conversation. When it refuses because it reaches an open PR, that PR's gate is
still open: make the PR's own call first, then sign off again. A PR answer added
to the sign-off itself would answer that gate under the review's ruling instead
of the PR's own. A subject that is a PR's anchor is the one PR the sign-off
always reaches, so its own gate takes no call in write 2, and the sign-off
answers it with that PR's answer, as the settle step gives it. Then drain.
