---
name: converse-settle
description: Converse's end of a sitting, which records the outcome, sends the work a ruling needs, answers the gates it settles, signs off and closes the conversation (safety-critical).
---

# End the sitting

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

The sign-off answers the gates the ruling settles and closes the conversation,
so take it only when nothing important is pending. When the operator still has
something to read or answer, such as a live decision or a routing answer, post
the hand-back, keep the conversation open, and go on (`converse-continue`),
which answers at once a gate they have ruled on. A settled sitting signs off
here rather than waiting for a dismiss. A sitting that stays runs everything
below up to the sign-off, then signs off through `converse-stay` in place of
the close.

## Record

Append the outcome to the subject's notes (the `records` skill). Notes are
append-only, so never pass `--notes`, which replaces them:

```bash
gc bd update "$SUBJECT" --append-notes "<the decision>. <why>. <what changed>."
```

When the notes have grown past a quick read, append a current-state block too.
The newest one is in force, and the prep primes from it:

```bash
gc bd update "$SUBJECT" --append-notes "## Current state ($(date -u +%Y-%m-%d))
<where things stand>
Decisions in force: <each decision in force>
Open questions: <each open question, or none>"
```

When the operator judged an epic's contract or its course, the
`converse-epic-review` skill's writes record it, each field in its own key.
The record goes on the subject alone. A gate the sitting answers can block a
bead that is not the subject, and that bead reads the answer in the gate's
resolve reason.

## Send the work

When the ruling needs work, file it and send it before the sign-off, then name
it in the sign-off's `--waiting-on` with a `--close-brief`. The `work` skill
says which bead carries the work and how to choose its formula. The sling runs
only once the create returned the bead's id, and the comment records the
dispatch as one of the visit's actions, which the comment on the subject's PR
lists:

```bash
WORK=$(gc bd create "<title>" -t task -d "<what needs doing, why, and what done looks like>" --json | jq -er '.id') \
  && gc sling <rig>/<pool> "$WORK" --on <formula> \
  && gc bd comment "$CONVERSATION" "Sent work: <what it will do, in plain words>"
```

Record any other act on the subject's universe the same way once it lands, in
one plain sentence that names no other rig or its beads.

- **Beside the subject, not under it.** Work the subject waits on is a
  dependency. Add `--parent <epic>` only when the work belongs to that epic.
  The subject's parent, as `"$CONV/converse-parent.sh" "$SUBJECT"` prints it,
  applies only when the work serves the same epic. It is the subject's own parent, or the nearest open
  bead above it once that parent has closed. Under a Delivery whose aim does
  not cover the work, the work goes under that Delivery's epic.
- **An epic's own decomposition is its member**, created with `--parent "$SUBJECT"`,
  and it gets no `--waiting-on`, because bd refuses a `blocks` edge from a
  parent to its own descendant.
- **Another rig's pool**: run the create as `gc bd --rig <rig> create`.
- **An epic the ruling files** takes the `work` skill's epic create, then a
  note saying whose words each field is:

  ```bash
  gc bd update <the new epic> --append-notes "Filed $(date -u +%Y-%m-%d) by $GC_SESSION_NAME in conversation $CONVERSATION. Proposed by this sitting: <each field it wrote, or none>. Stated by the operator: <each field they stated or approved, quoting their words, or none>."
  ```

**A follow-up that cannot start until another bead lands is armed** (the
`waits` skill), never sent now and never left for someone to send later. It
waits on the blocker, then the arm sends it once the blocker closes. A
`dep add` onto a bead in another store exits 0 and holds nothing, so the edge
is written only when both ids carry one prefix, the text before the first
`-`, and the arm runs only once the edge exits 0. Each call names the
follow-up's rig:

```bash
[ "$(echo <follow-up> | cut -d- -f1)" = "$(echo <blocker> | cut -d- -f1)" ] \
  && gc bd --rig <rig> dep add <follow-up> <blocker> --type=blocks \
  && "$CONV/deferred-dispatch.sh" arm <follow-up> --target <rig>/<pool> --reason "waits for <blocker>"
```

When the blocker is in another store, make the follow-up wait on a human gate
in its own store that names the blocker, and arm it on that gate. The operator
clears the gate once the blocker lands. The message's first line is the gate's
title, cut at 140 characters:

```bash
"$CONV/human-gate.sh" --subject <follow-up> --key waits-for-<blocker> --message "Clear once <what the blocker delivers> lands, so <what the follow-up does> can start
<follow-up> waits for <blocker> in <its rig>. Clear this gate once <blocker> closes." \
  && "$CONV/deferred-dispatch.sh" arm <follow-up> --target <rig>/<pool> --reason "waits for <blocker>, through its human gate"
```

## Answer the gates

The sitting answers only the gates its conversation replies to: the one
engage was pointed at, one its hold filed, and any other human gate the
operator rules on within the subject's universe. To answer one the
conversation does not reply to yet, add the reply, then name each bead the
answer releases, so an answer that releases more than the subject is given
knowingly:

```bash
gc bd dep add "$CONVERSATION" <gate> --type replies-to \
  && gc bd dep list <gate> --direction=up --type blocks --json | jq -r '.[] | "\(.id) [\(.status)] \(.title)"'
```

A gate with no tie to the subject takes a conversation of its own, so its
outcome does not land in the notes of a bead it is not about. A gate assigned
to a person is that person's to clear: reply to it only when they rule on it
in this sitting.

## Settle the subject's dispatch path

Every answer to a gate on the subject, at the sign-off or on a turn's
`--answer`, first settles the subject's arm and route. The hold kept both, so
once the gate is answered and nothing else holds the subject, an arm sends it
and a pool route has that pool claim it. Read them:

```bash
ROW=$(gc bd show "$SUBJECT" --json) \
  && printf '%s\n' "$ROW" | jq -er --arg s "$SUBJECT" 'if type == "array" and length == 1 and .[0].id == $s then (.[0].metadata // {}) | "arm: \(.["gc.dispatch_when_ready"] // "none") \(.["gc.dispatch_when_ready_args"] // "") route: \(.["gc.routed_to"] // "none")" else error("unread") end'
```

When the ruling sends the subject where its arm or route already sends it, by
the same method, keep them and send nothing yourself: once the gate is
answered, the arm or the route sends it. Under any other ruling, with or without
`--accept`, withdraw them before the answer. The block disarms an arm and
clears a pool route. It prints its `carries no arm and no pool route` line only
once each write has exited 0, and without that line you answer nothing:

```bash
WHY="<the ruling, one line>"
ROW=$(gc bd show "$SUBJECT" --json) \
  && ARM=$(printf '%s\n' "$ROW" | jq -er --arg s "$SUBJECT" 'if type == "array" and length == 1 and .[0].id == $s then (.[0].metadata["gc.dispatch_when_ready"] // "") | tostring else error("unread") end') \
  && ROUTE=$(printf '%s\n' "$ROW" | jq -er '(.[0].metadata["gc.routed_to"] // "") | tostring') \
  && { [ -z "$ARM" ] || "$CONV/deferred-dispatch.sh" disarm "$SUBJECT" --reason "$WHY"; } \
  && { [ -z "$ROUTE" ] || gc bd update "$SUBJECT" --unset-metadata gc.routed_to; } \
  && echo "$SUBJECT carries no arm and no pool route"
```

## Sign off

`converse-signoff.sh` writes the trace in one order every time: the ruling's
rework or the PR's retirement, the subject's headline, the answer on each gate
the conversation replies to, the subject's recommendation when the ruling takes
it, the conversation's close, which frees an open PR's merge the conversation
held, and the comment that shows the visit on the subject's PR. That comment
lists the ruling and each act recorded on the conversation, so keep other rigs
and their beads out of them. It exits non-zero when it stopped short, and then
you must NOT post the sign-off. A re-run with the same `--ruling` is safe,
because the writer keys what it recorded to that ruling:

```bash
if "$CONV/converse-signoff.sh" --conversation "$CONVERSATION" \
     --outcome "<outcome> — <what this sitting settled or needs next, at most 140 characters, or 95 when the ruling leaves an open PR standing>" \
     --ruled yes --ruling "<the ruling, one line>" --no-wait
     # --leave <gate>, once for each gate the ruling leaves owed
     # --waiting-on <bead> [--waiting-on <bead> ...] in place of --no-wait
     # --close-brief "<what that work's landing settles here, and what to check once it has>" beside a --waiting-on on work
     # --rework, --no-rework or --retire <kind>: one is required when the ruling reaches an open PR
     # --pr-anchor <bead> names the PR --rework or --retire acts on, when it reaches more than one
     # --accept when the ruling takes the subject's recommendation (below)
then
  : # signed off: report any answer it says reached a gate first, then post the sign-off
else
  # NOT signed off: a read failed, the rework did not file, the PR did not
  # retire, the headline did not land, a gate did not close, the
  # recommendation was not taken, or the conversation did not close. Repair
  # what it printed and re-run, or raise it in the thread.
  exit 1
fi
```

- `--ruled yes` resolves each open gate the conversation replies to with
  `ruled: <the ruling>`, except each one a `--leave` names, which stays owed
  with its reply in place.
- What the subject waits on is yours to state: a `--waiting-on` for each bead
  this sitting routed work into, or for the gate still holding it, with a
  `--close-brief` beside work. `--no-wait` when nothing waits, and neither when
  the subject is parked for a person. The brief is the claim the subject's
  validating closer tests once the work lands: what the landing settles on the
  subject, and what to check. A subject in the city's own store has no pool to
  run its closer, so the sign-off refuses it: wait on a human gate that names
  the work instead (the `waits` skill). A wait the store refuses only warns,
  with the command that wires it: run that command before you say what the
  subject waits on.
- **The first answer wins.** A gate another answer closed first, such as a
  withdrawal, an Accept or another sitting, keeps that answer, and the sign-off
  prints it. Tell the operator which gate it was and what that answer said.
  A gate this sitting answered on an earlier turn prints the same way, and
  that answer is its own.

Take the case that fits the ruling:

- **The subject is the work.** Sign off with `--ruled yes --no-wait`, then send
  it: `gc sling <rig>/<pool> "$SUBJECT" --on <formula>`. A formula the subject
  recommends is never sent this way.
- **The subject takes its recommendation.** Reply to the recommendation's gate,
  the human gate under the key `first-reaction` that blocks the subject, and sign off with
  `--ruled yes --no-wait --accept`. Send nothing yourself: the sign-off hands
  that gate to `gc-helm.sh accept`, the writer the board's Accept runs, which
  dispatches the formula once under the subject's acceptance lock. A var the
  operator settles rides beside it as `--var <key>=<value>`. It refuses,
  writing nothing, while a gate the ruling does not answer still holds the
  subject. Answer that gate in the same ruling once the operator rules on it,
  or sign off without `--accept` and with `--leave` on the recommendation's
  gate, and the board offers Accept once the other gate clears. A
  `first-reaction` gate on an epic's member asks the member's recommendation,
  which this does not take.
- **The work will not go on, and a human gate holds the subject.** Stand it
  down first, with the gate's `await_id` as the key:
  `"$CONV/stand-down.sh" "$SUBJECT" --key <situation-key> --ruling "<the ruling, one line>" --successor "$CONVERSATION"`.
  It removes the arm, ends any run beneath it, answers the gate and closes the
  subject. Then sign off with `--ruled yes --no-wait`. A gate that also holds
  another open bead is left in place, and it prints which bead. Unless the
  ruling settles that bead too, add `--leave <gate>` to the sign-off. When it
  exits non-zero, repair what it printed and re-run before you sign off. An
  open PR is retired instead (below).
- **New work carries it.** Send it (Send the work), then sign off with
  `--ruled yes --waiting-on <the work> --close-brief "<…>"`.
- **New work decomposes an epic subject.** Sign off with `--ruled yes --no-wait`,
  or `--waiting-on` only the dependencies the sitting also sent. An epic takes
  no `--close-brief`, because its members carry it.
- **The subject needs no work.** Sign off first, because an open gate on the
  subject holds its close, then close it through the disposition writer (the
  `work` skill), with this conversation as the evidence. The writer runs only
  once the no-op record lands:

  ```bash
  gc bd update "$SUBJECT" --set-metadata gc.work_outcome=no-op \
    && "$CONV/bead-rehome.sh" --origin "$SUBJECT" --successor "$CONVERSATION" --kind not-needed --note "<the sitting's reason, one sentence>"
  ```

  A gate the sitting did not answer makes it exit 5 with nothing closed: run
  it again once that gate clears. When another bead carries the work, name it
  as the successor, under `--kind duplicate`, `folded`, `re-homed` or
  `fixed-upstream`. An open PR, or a branch whose PR is not open yet, does not
  stop the ruling: an open PR is retired instead (below). An epic ruled close
  is the `converse-epic-review` skill's to close.

**A ruling that reaches an open PR** (`merge_result=pull_request`) says what it
does to the PR: the subject's PR, the PR whose merge this conversation holds,
or one a gate it answers releases. Pass `--rework` when the branch must change
(the `prs` skill), `--no-rework` when it stands, or `--retire <kind>` when it
will not land: `not-needed` with this conversation as the evidence, or
`duplicate`, `folded`, `re-homed` or `fixed-upstream` with
`--successor <bead>`. To retire the subject's PR:

```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --outcome "<headline>" --ruled yes --ruling "<the ruling, one line>" --no-wait --retire not-needed
```

Given none of them, the sign-off refuses and writes nothing, because a rework
never filed leaves the stale PR reading ready, and a gate answered before the
PR closes lets an approved PR merge. `--pr-anchor <bead>` names the PR the
rework or retirement acts on when the ruling reaches more than one, and each
other one stands. The rework or retirement runs first, in that PR's own rig,
and one that does not complete stops the sign-off with nothing answered, so
the conversation still holds the merge. A re-run of the same ruling adopts
the child an earlier attempt filed, files none again once that child has
closed, and finds the PR an earlier attempt left, even one closed since. A
conversation owns one live rework: while one filed for an earlier ruling is
open, `--rework` for another is refused, so give a ruling that asks nothing
more of the branch `--no-rework`, and keep the gate of one that does open
(`--leave <gate>`) until that rework lands. A second PR whose own branch must
change waits the same way, behind a gate kept open until a ruling of its own
is carried out. `--rework` and `--retire` act only on an open PR: when the
ruling reaches none, send its consequence as work and sign off without them.

**A ruling does not approve a PR.** A PR merges only on an Approve from an
account other than the city's. When a PR the ruling leaves standing still
waits on GitHub, the sign-off prints what its merge needs, with its link. Pass
each line on. Name the operator's Approve as the one thing left only when
nothing else holds the PR. When the ruling holds the PR back, leaves a gate
owed or waits on other work, or the line names a request for changes, say that
first, with what settles it, and give the Approve as the step after it. When no
line prints, leave the Approve out.

Then post the sign-off as the sitting's last word, a hand-back that opens with
where the subject stands. Its last words say what the record does next: what
the subject waits on, and what checks and closes it once that work lands, such
as its validating closer, the refinery's merge or a person's gate. Never
promise to confirm, check, watch or follow up yourself, in any words: nothing
brings an ended sitting back. Record it on the conversation before you post it
(the prompt's hand-back), and name no other rig or its beads, because the
comment on the subject's PR shows it word for word.

Once the sign-off has closed the conversation and its message is posted, run
`gc runtime drain-ack`, and nothing after it. A sign-off that stopped short
leaves the sitting open: repair what it printed, or raise it in the thread, and
do not drain. Never close a conversation by hand: a held sitting ends with its
sign-off, because a conversation closed by hand answers none of its gates.

## Ending early

When your context runs low before the operator answers, record the outcome so
far, sign off with `--ruled no`, record and post a hand-back that says the
conversation is back in their queue and what is still owed, and drain. The
sign-off answers nothing: every gate stays open and owed with its reply in
place, and the next engagement takes the conversation up from its record.
It is the one ending that drains with the conversation open, and a sitting the
operator has not ruled on is never ended to unblock something else.
