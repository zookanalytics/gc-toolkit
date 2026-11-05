---
name: converse-settle
description: Converse's record, its answer to each gate the ruling settles, the sign-off, and the conversation's close (safety-critical).
---

# Steps 6–7 — Record, sign off, and close the conversation

Each tool call starts a fresh shell, so set `CONV`, `CONVERSATION` and
`SUBJECT` literally, from what step 1 found, at the top of every call below.
Run these once the operator has replied to the held sitting (step 5).

## 6. Record

Append the sitting's outcome to the subject's notes: the decision, its
rationale, and what changed (the `records` skill). Notes are append-only, so
never pass `--notes`, which replaces them:
```bash
gc bd update "$SUBJECT" --append-notes "<the decision>. <why>. <what changed>."
```
When the notes have grown past a quick read, append a current-state block too.
The newest one is the one in force, and step 4 primes from it:
```bash
gc bd update "$SUBJECT" --append-notes "## Current state ($(date -u +%Y-%m-%d))
<where things stand>
Decisions in force: <each decision in force>
Open questions: <each open question, or none>"
```
The record goes on the subject alone. A gate the sitting answers can block a
bead that is not the subject, such as a rework child waiting on its anchor's
bring-current gate, or a member of an epic whose gate the epic's sitting
answers. That bead reads the answer in the gate's resolve reason, and the
record and headline stay off it.

## 7. Sign off, then close the conversation — only when nothing important is still pending

The sign-off is the terminal act: it answers the gates the ruling settles and
closes the conversation. So before you take it, ask whether this is a sign-off
turn at all. **If there is important information you want to communicate to
the operator — a live decision, a routing answer, anything they need to read
or may want to respond to, anything past "settled and done" — do not sign off
this turn.** Post the hand-back in the shape the prompt's Definitions define
(**The hand-back**), recorded on the conversation first by the block below the
sign-off's shape, leave the conversation OPEN, and wait for operator input
the way a held sitting does; signing off now would close the conversation
under a message they have not read. A gate the operator has already ruled on
is still answered now, through the sign-off's `--answer` (step 8), so a
dismiss that ends the sitting later leaves nothing they ruled on open. The
sitting ends on a later turn: the
operator's `gc-helm dismiss`, further engagement, or a genuinely terminal
sign-off once nothing important is pending. Whether a sign-off is terminal is
still your judgment, and a sitting that is genuinely settled still signs off
and closes here rather than waiting for a manual dismiss.

**A gate is answered through the conversation's reply, and the operator hears
what the answer releases first.** The sitting answers only the gates its
conversation replies to: the gate engage was pointed at, one its hold filed,
and any other human gate the operator rules on within the subject's universe.
To answer one the conversation does not reply to yet, add the reply and read
it back, then name every bead the answer releases, read from the gate's
`blocks` dependents, so an answer that releases a bead beyond the subject is
given knowingly:
```bash
gc bd dep add "$CONVERSATION" <gate> --type replies-to \
  && gc bd list --id "$CONVERSATION" --all --json | jq -e --arg g <gate> 'any(.[0].dependencies[]?; .type == "replies-to" and .depends_on_id == $g)' >/dev/null \
  && gc bd dep list <gate> --direction=up --type blocks --json | jq -r '.[] | "\(.id) [\(.status)] \(.title)"'
```
A gate with no tie to the subject takes its own conversation, so that its
outcome does not land in the notes of a bead that is not about it. A gate
assigned to a person is that person's to clear: reply to it only when they
rule on it in this sitting.

When nothing important is pending, sign off. Write the durable trace first,
then post the sign-off as the thread's last word. `converse-signoff.sh` writes
the trace in one order every time: the ruling's rework or the PR's retirement,
the subject's headline, the answer on each gate the conversation replies to,
the release of a `held` subject, the subject's recommendation when the ruling
takes it, the conversation's close, and the PR reminder. You tell it
what this sitting settled. `--ruled yes` resolves each open gate the
conversation replies to with `ruled: <the ruling>`, except each one a
`--leave` names, which the ruling leaves owed with its reply in place, and
`--route` is where a `held` subject is released to, chosen as below.
`--ruled no` answers nothing: it leaves every gate open and owed and hands the
conversation back to the operator's queue, which is the low-context path in
the prompt's Rules. What is waiting on the subject is yours to state: one
`--waiting-on <bead>` per dependency this sitting ROUTED work into, or the gate
still holding it, `--no-wait` when it settled the subject and nothing is
waiting, and NEITHER where the subject is parked for a person. It exits
non-zero when it stopped short, and then you must NOT post the sign-off:
```bash
if "$CONV/converse-signoff.sh" --conversation "$CONVERSATION" \
     --outcome "<outcome> — <what this sitting settled or needs next, at most 140 characters>" \
     --ruled yes --ruling "<the ruling, one line>" --route human --no-wait
     # --route <rig>/<agent> releases a held subject to that pool instead
     # --leave <gate>, once for each gate the ruling leaves owed
     # --waiting-on <bead> [--waiting-on <bead> ...] in place of --no-wait
     # --rework, --no-rework or --retire <kind>: one is required when the ruling reaches an open PR
     # --pr-anchor <bead> names the PR --rework or --retire acts on, when it reaches more than one
     # --accept when the ruling takes the subject's recommendation (below)
then
  : # signed off — report any answer it says reached a gate first, then post the sign-off below
else
  # NOT signed off: a read failed, the rework did not file, the PR did not
  # retire, the headline did not land, a gate did not close, a held subject
  # did not release, the recommendation was not taken, or the conversation did
  # not close or hand back. Do NOT post the sign-off. Repair what it printed
  # and re-run, or raise it in the thread.
  exit 1
fi
```
Re-running it is safe. What it wrote before it stopped is written again the
same way, a gate it already answered reads as answered, and a gate it did not
reach is still open for the re-run to find.

**The first answer wins.** bd resolves a gate that is already closed without
changing it, so the sign-off reads each gate back after its resolve. A close
reason other than its own means another answer reached the gate first: a
filer's withdrawal, an Accept, another sitting, or a person at the command
line. The sign-off prints that answer and leaves it standing. Tell the
operator, in the sign-off, which gate it was and what that answer said,
instead of claiming your own.

**On `--ruled yes`, the `--route` follows which bead carries the work** (the
`work` skill says why):
- **The subject is the work.** Sign off with `--ruled yes --route human --no-wait`,
  then send the subject: `gc sling <rig>/<pool> "$SUBJECT" --on <formula>`.
  The formula the subject recommends is never sent this way; take it as the
  next case says.
- **The subject takes its recommendation.** The operator rules to take the
  formula a first reaction recommended, `gc.recommended_formula`. Make the
  conversation reply to the recommendation's gate, the human gate under the
  key `first-reaction` that blocks the subject, as for any gate you answer. A
  gate under that key on an epic's member asks the member's recommendation,
  which the sign-off does not take. Then sign off with
  `--ruled yes --route human --no-wait --accept`. Send nothing yourself: the
  sign-off answers that gate through `gc-helm.sh accept`, the writer the
  board's Accept runs, after every other write but the close. Under the
  subject's acceptance lock it dispatches the formula, or records a dispatch
  an Accept already made, so the work goes once (the `work` skill). A var the
  operator settles for that dispatch rides beside `--accept` as
  `--var <key>=<value>`; the formula's own description names the vars it
  takes. It refuses, writing nothing, while a human gate the ruling does not
  answer still holds the subject, or while the subject carries another gate
  under the key, one Accept would answer, that the ruling does not answer.
  Answer that gate in the same ruling once the operator rules on it, or sign
  off without `--accept` and with `--leave` on the recommendation's gate, and
  the board offers Accept once the other gate is cleared.
- **New work carries it.** File and send that work (below), then sign off
  with `--ruled yes --route human --waiting-on <the work>`.
- **New work decomposes an epic subject.** File it as the subject's member and
  send it (below), then sign off with `--ruled yes --route human --no-wait`,
  or with `--waiting-on` naming only the dependencies the sitting also sent.
  A member takes no `--waiting-on`, because bd refuses that edge.

**On a `--ruled yes` sign-off that reaches an open PR
(`merge_result=pull_request`), answer what the ruling does to the PR.** The
ruling reaches the subject when it is an open PR, and each open PR that a gate
it answers releases, such as a member of an epic subject whose gate the
epic's sitting answers, or the other PR behind a gate about two. Pass
`--rework` when it changes what the branch must contain, since the PR still
reads review-ready against a head that predates the ruling (the `prs` skill,
sending it back for rework). Pass `--no-rework` when the branch stands as it
is. Pass `--retire <kind>` when the PR will not land (the `prs` skill,
retiring it): `not-needed` when nothing carries the work, with this
conversation as the evidence, or `duplicate`, `folded`, `re-homed` or
`fixed-upstream` with `--successor <bead>`, the bead that carries it now.
Given none of them on a ruling that reaches an open PR, the sign-off refuses
and writes nothing, because a ruling whose rework is never filed lands only in
notes nothing reads while the stale PR keeps reading ready, and a gate
answered before the PR is closed lets an approved PR merge. `--rework` and
`--retire` act on one PR. When the ruling reaches more than one,
`--pr-anchor <bead>` names it, and each other one stands under the ruling, as
`--no-rework` says of each. The rework or the retirement runs in that PR's
own rig, after the sign-off records on the conversation which PR it acts on
and before it writes anything else. One that does not complete stops the
sign-off there, and the script exits non-zero. No headline is written, no
gate is answered and the conversation stays open, so a merge hold your hold
filed still holds the PR. Re-run once the cause is repaired: the re-run
adopts a child an earlier attempt filed, and finds a PR an earlier attempt
closed. Given the same ruling and the same answer, it acts on the PR the
earlier attempt recorded, even one that has closed since. A
conversation's rework carries the ruling it was filed for, and a conversation
owns one live rework, on whichever PR it was filed. While one filed for an
earlier ruling of this conversation is open, `--rework` for another ruling is
refused, because the open one would never carry it: give a ruling that asks
nothing of the branch beyond it `--no-rework`, and keep the gate of one that
asks for more open (`--leave <gate>`, or cut the sitting short) until that
rework has landed. A second PR whose own branch must change waits the same
way: keep the gate that releases it open until a ruling of its own is carried
out. `--rework` and `--retire` apply only to an open PR. When the ruling
reaches none, file and send its consequence as work (below), and re-run
without them.

Then post the **sign-off** — the sitting's last word, a hand-back in
the shape the prompt's Definitions define (**The hand-back**),
self-contained enough to act on from its last few lines:
```
<subject-id> — <short human label>

<2-4 plain sentences at executive altitude: what this sitting settled
and the consequence that mattered; if a decision is still open, lead
with its recommendation.>
```
A converse is about its one subject; name another bead only where the
conversation's substance genuinely leads there, and then as a plain
sentence. Record it on the conversation just before you post it (the
prompt's **Record each hand-back on the conversation, then post it**):
```bash
"$CONV/gc-helm.sh" handback "$CONVERSATION" <<'HANDBACK'
<the sign-off as you post it>
HANDBACK
```
The sign-off already closed the conversation, so nothing is said after this
message.
**If this sitting ROUTED work, file and send it, then pass
`--waiting-on <work-bead>` to the sign-off for each dependency it sent.** The
`work` skill says which bead carries the work and how to choose its formula.
The sling runs only once the create returned the bead's id:
```bash
WORK=$(gc bd create "<title>" -t task -d "<what needs doing, why, and what done looks like>" --json | jq -er '.id') \
  && gc sling <rig>/<pool> "$WORK" --on <formula>
```
File it beside the subject, not under it: work the subject waits on is a
dependency, and that is the default. Add `--parent <epic>` to the create only
when the work belongs to that epic. The subject's own parent,
`"$CONV/converse-parent.sh" "$SUBJECT"`, applies only when the new work serves
the same epic. Work that genuinely decomposes an epic subject is the one
exception. It is the subject's member, created with `--parent "$SUBJECT"`, and
it gets no `--waiting-on`, because bd refuses a `blocks` edge from a parent to
its own descendant. Run the create as `gc bd --rig <rig> create` when the
pool's rig is not this session's. The takeaway alone cannot carry the wait:
*waiting and holding are graph states, not comments.* An edge that will not
take warns on stderr and the takeaway still lands.

**A follow-up that cannot run until another bead lands is ARMED, not left
unrouted** (the `waits` skill). Slinging it now is wrong, because it is
blocked, and leaving it to route once the blocker closes is the
come-back-later that keeps you or a person on the hook. Make it wait on the
blocker, then arm it, so it routes itself when the blocker closes and the
sitting can queue everything and close. An arm with nothing holding the
follow-up sends it on the next pass, so the arm runs only once the follow-up's
own store reads the edge back. A `dep add` onto a bead in another rig's store
prints success and exits 0, but holds nothing. Each call names the
follow-up's rig, the one its pool reads: unpinned, a command that also names a
city bead is answered from the city's store.
```bash
gc bd --rig <rig> dep add <follow-up> <blocker> --type=blocks \
  && gc bd --rig <rig> dep list <follow-up> --direction=down -t blocks --json | tr -d '[:cntrl:]' | jq -e --arg b <blocker> 'any(.[]; .id == $b)' >/dev/null \
  && "$CONV/deferred-dispatch.sh" arm <follow-up> --target <rig>/<pool> --reason "waits for <blocker>"
```
When the edge does not read back and `dep list` warns that its target has no
row in this database, the blocker is in another rig's store, where no edge can
hold the follow-up. Make it wait on a human gate in its own store that names
the blocker, and arm it on that gate. The gate reaches the operator, who
clears it once the blocker lands, and the arm then sends the follow-up.
Remove the edge first, because the arm reads it as a blocker that holds
nothing and warns that the next pass sends the follow-up. The helper files the
gate in the follow-up's own store, and the message's first line is the gate's
title, cut at 140 characters, so keep that line to one plain sentence:
```bash
gc bd --rig <rig> dep remove <follow-up> <blocker> \
  && "$CONV/human-gate.sh" --subject <follow-up> --key waits-for-<blocker> --message "Clear once <what the blocker delivers> lands, so <what the follow-up does> can start
<follow-up> waits for <blocker> in <its rig>. Clear this gate once <blocker> closes." \
  && "$CONV/deferred-dispatch.sh" arm <follow-up> --target <rig>/<pool> --reason "waits for <blocker>, through its human gate"
```

**A recorded wait is also the return trip.** Once every recorded wait
closes, the subject returns through the liveness sweep
(`assets/scripts/liveness-sweep.sh`) as an unnamed wait; it reads
those edges AND children, so legacy work stays visible.

Never close a conversation by hand, and never end a held sitting without
its sign-off: a thread that stops after a decision with no wrap-up reads as a
crash, and a conversation closed by hand answers none of the gates it replies
to. The sign-off is owed to a sitting that was **held**; one closed before any
framing was posted (step 2's `moot` or `benign`) asked the operator nothing,
so closing it silently is the contract.

Then drain: a closed conversation ends this session (the prompt's **How this
thread ends**). Run `gc runtime drain-ack` once the sign-off has closed the
conversation and its message is posted, and run nothing after it. A sign-off
that stopped short leaves the conversation open and the sitting not over:
repair what `converse-signoff.sh` printed, or raise it in the thread, and do
not drain.
