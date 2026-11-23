---
name: Design — accept a question's one recommendation from the board
description: The design record for tk-3d1d6p0.3, the design child of initiative tk-3d1d6p0.2 under the epic Easy approvals on the board (tk-3d1d6p0). It decides which questions offer Accept and what the board reads to know, how Accept answers a question with the operator's yes and carries its recommendation out, what becomes of today's Accept, the epic's two open questions, how its indicators are read, and the four units the implementation child (tk-3d1d6p0.4) builds. Read it to approve the design at its gate, or to build one of its units.
---

# Design: accept a question's one recommendation from the board

This is the design record for tk-3d1d6p0.3, the design child of the initiative
tk-3d1d6p0.2. The pack was read at 8d778ffee, the commit
`integration/tk-3d1d6p0.2` was cut from. bd is cited by symbol at v1.3.4, the
version the city runs, and Gas City by symbol at upstream main cb9a2621ae. The
counts of questions read the human gates created from 2026-11-02 to 2026-11-23
in every rig's store and the city's. [gas-city-search.md](gas-city-search.md)
holds the search for the surface the design adds. Sections 1 to 9 answer the
design child's asks in its order: which questions qualify (1), how Accept
records your yes (2), how the recommendation is carried out (3 and 4), the
board (5), today's Accept (6), the open questions (7), the indicators (8) and
the boundaries (9). Section 10 is the implementation's breakdown.

## What you decide

Today every question that waits on you is a human gate on the bead it holds,
and you answer it in a conversation. Its row on the board offers that
conversation and nothing else. One kind of question can be accepted as it
stands: a first reaction's recommendation of a formula. Even that one is taken
in a sitting, whose sign-off runs Accept with `--accept`, or by running the
command yourself, because the board's Accept button went with the old board.

With this design, an agent that asks you with one recommendation records it on
the question, with what your yes does. The board shows Accept on that question
beside the conversation button, with the recommendation beside it. Accept
answers the question with your yes and carries out what was recorded, and the
row leaves Waiting on you. A question with several options, or none, keeps
only the conversation.

1. **Accept comes from a record the asker writes, never from the question's
   words.** Recommended. Nothing is accepted on a misreading of prose, and an
   asker that cannot carry its course out offers no Accept. The cost is reach.
   Leaving out conversation holds and test probes, 178 questions were filed
   since 2026-11-02. 87 of them came from the review run, the merge path and
   the patrols when something stopped, and only 3 of those name a course. They
   stay conversations under this design, because teaching them to recommend is
   the wording's work, which the epic leaves out. The other way is to read the
   recommendation from the text. It changes no asker, but Accept could act on a
   misreading.
2. **Your yes can do one of four things, each through a writer the pack
   already has.** It can let the waiting work go on, start a formula on a
   bead, stand the work down, or retire a PR. Recommended. At least six of your
   answers since 2026-11-02 closed a PR unmerged or stood work down. The
   smaller build, the first two only, leaves every recommendation to stop work
   a conversation.
3. **A yes with one change stays a conversation** (22 of the 83 answers the
   epic counted). Recommended. A change alters what the yes does, which
   someone must rewrite, and Discuss opens that conversation.
4. **A confirmation can be accepted** (10 more in the epic's count). Its
   recommendation is that the work waiting on it goes on, so Accept is your
   confirmation. Recommended.

Approving the design as it stands takes each recommendation.

## 1. Which questions offer Accept

A question is an open human gate, which the board shows as a Question. It
offers Accept when all of these hold:

- the gate carries its asker's recommendation record, `gc.recommendation`;
- the gate is assigned to nobody, since an assigned gate asks for an action
  only that person performs (the waits skill);
- no open conversation replies to the gate or tracks the bead it holds. A
  sitting may be ruling on it, and the sitting takes the recommendation
  through its sign-off's `--accept`.

The record is a JSON object on the gate. `course` is the one line the board
shows beside Accept and the answer names. `act` is what a yes does (section
3), with the fields that act needs, and `bead` is the bead the question is
about, the one the act works on. `rev` names this version of the record, and
each write of the record gives it a new one. The board reads the record, never
the question's text, through gctk's listing, which decodes each key the board
shows.

A question with several options or none carries no record, so it shows only
the conversation. That includes a question that lists its answers and marks
one recommended, as the review run's question often does
(`review-run.sh question`). The operator's words leave a choice among options
to a conversation ("if the point is we're choosing multiple choices, it's
probably a conversation", conversation tk-dnvb9pt), and since PR #1565 the
waits skill asks every question to give one course and nothing else. A
question written that way carries a record once its asker writes one.

## 2. How Accept records your yes

Your yes is the gate's own answer, the resolve reason bd keeps with the closed
gate:

```text
ruled: accepted: <course> accept:<token>
```

Accept writes it through bd's gate resolve, which bd documents as the same act
as closing the gate with that reason (bd v1.3.4, `gateResolveCmd` in
`cmd/bd/gate.go`). Gas City answers a gate the same way. Its supervisor API has
no route of its own for a gate, and its bead close route takes a reason and
runs bd's close with it (gas-city-search.md, section 1). So the record is the
platform's, and a reader takes your yes from the gate as it takes a sitting's
answer.

- It opens with `ruled:`, because you decided.
- It names the course you accepted, which whoever works the bead next inherits
  from the gate.
- It carries the acceptance's token, which tells Accept's own answer from one
  that reached the gate first. bd's resolve exits 0 on a gate already closed
  and keeps the first answer, so Accept reads the gate after it answers, and
  the first answer stands, as it does today.

Accept is one command, `gctk gate accept <gate> --rev <rev>`. Its caller names
the version of the record you read: the board names the `rev` its row showed,
and a sitting's sign-off names the `rev` its sitting put to you. Accept
refuses, writing nothing, when the live record's `rev` differs. So your yes
reaches only the recommendation you read, and a record written again after you
read it waits for a new yes, whatever the write changed. A sitting's sign-off
also names its own conversation, which the refusal of section 1 passes over.

## 3. How the recommendation is carried out

The asker decides what its yes does when it asks, and records it. Most askers
have ended by the time you answer: a polecat that declined has drained, and a
first reaction's or a validating closer's run has finished. So Accept carries
the recommendation out right after the answer, from the record, through the
writer the pack already uses for each act, and in the order that writer needs.

| `act` | What a yes does | The writer, and its order with the answer |
|---|---|---|
| `proceed` | The work waiting on the question goes on by the wait it already has: an arm that re-slings it once the gate clears, a merge the gate holds, or the next run that reads the answer. | The answer alone. |
| `sling` | Starts `formula` on the bead, with `vars`. | Today's Accept: it removes the bead's arm, answers, slings once under the token, and lifts `hold:mayor`, since a sling is a placement. |
| `stand-down` | The waiting work does not go on, and the bead closes as not needed. | `stand-down.sh`, which removes the arm, ends the run, answers the gate, and closes the bead with the gate as its evidence. |
| `retire` | The bead's PR does not land, as `kind` says, with `successor` where the kind needs one. | `pr-dispose.sh` first, then the answer, since an answered gate would let an approved PR merge before its retirement. |

Accept runs the act, rather than leaving it to the gate's close, because a gate
closes on any answer: a sitting's ruling the other way, or its filer's
`moot:`. Nothing in bd or Gas City starts work on one answer and not another
(gas-city-search.md, section 3). Work that starts when the gate clears suits
`proceed` alone, where every answer releases the same wait, and that is how
`await-ruling.sh` and the review run's next round already work.

When an act does not land, Accept says what landed and what runs it again, as
today. A sling that poured nothing reopens the gate from Accept's own answer,
so the question is back on your board. A run that stopped after its answer is
finished by the next run under the same token, whoever runs it, and that holds
for every act.

## 4. The askers

| Asker | Its question | What it records |
|---|---|---|
| A first reaction's recommend exit | A formula it judges needs your trigger. | `sling` with that formula (unit 1). |
| The validating closer, step 2b of `mol-validate-close` | The one course it recommends when it cannot confirm a close. | `sling` to fix the bead or start another formula on it, `stand-down` to close it, or `proceed` (unit 4). |
| A polecat that declines its run | The work waits on your ruling, and clearing the gate re-slings it. | `proceed` or `stand-down`, recorded before `decline.sh` (unit 4). |
| Any agent asking through the waits skill, a wait on outside work included | The one course the wording rule asks for. | The act that course needs (unit 4). |
| The review run's question | Several answers, often with one of them marked. | Nothing, until it puts one course to you. |
| The review run, the merge path and the patrols when something stops | A report that names no course. | Nothing. |

An asker records with one command:

```bash
gctk gate recommend --subject <bead> --key <situation-key> --course "<one line>" \
  --act <proceed|sling|stand-down|retire> [--formula <name>] [--var <key>=<value>]... \
  [--kind <kind>] [--successor <bead>] [--message <the question>]
```

It finds the open human gate under the key that holds the bead. Given
`--message` and none open, it files the gate through `human-gate.sh` first, as
the first reaction files its gate today, so an asker that ends in one call,
such as `decline.sh`, records first and the decline then finds the gate open.
It checks that the act can run on the bead: a formula for `sling`, no open PR
for `stand-down`, and a PR on the pending record for `retire`. It then writes
the record in one write, with a new `rev`. A recommendation recorded again
replaces the last, so Accept refuses a click on a row that showed the last one.
A question whose record did not land keeps the conversation and loses only
Accept.

## 5. The board

On a row that qualifies (section 1), Accept sits beside Start the
conversation, with the recommendation's course beside it. A click posts the
gate and the `rev` of the record the row showed to a third write route,
`POST /helm/accept`, beside `/helm/open` and `/helm/engage`. The route runs
`gctk gate accept <gate> --rev <rev>` and drops the rig's cached document, as a
write does. The side panel shows Accept's answer as it shows an
engage's: what was accepted and what started, or why nothing did. The row
then reads as the answer left it. Discuss opens a conversation as today. The
board's design as a whole is the Board UI design epic's (tk-yhquh93), so this
is one button and its answer.

## 6. What becomes of today's Accept

It grows into the general one. `gctk reaction accept <bead>` becomes
`gctk gate accept <gate>`, moving from the reaction domain to a gate domain by
the rules a domain move follows (docs/gctk-architecture.md). It keeps what
makes it safe:

- its lock, held from the live read to the last write (docs/warrants.md,
  Accept's lock);
- its token, which titles the pour and names the answer;
- its record of what was accepted, `gc.acceptance` on the gate, which now holds
  the accepted record's `rev` and its act, with any var a sitting's ruling
  settled;
- the read that lets the first answer stand;
- the reopen when a sling pours nothing, and the finishing of an acceptance an
  earlier run left.

Four things change. It reads the recommendation from the question, not from
the bead. It takes any question whose asker recorded one, and only the version
of its record that the caller read. It carries out four acts where it carried
out one. It refuses while a conversation other than the
caller's is open on the question, where today it only warns.

So the first reaction's recommendation moves from `gc.recommended_formula` on
the bead to its gate's record. The bead keys `gc.recommended_formula` and
`gc.recommended_formula_dispatched` retire, with their lifecycle entries and
their readers:

- The sign-off's `--accept` names the gate its ruling answers and the `rev` its
  sitting put to you, and leaves the refusals to Accept.
- `converse-invalidate-recommendation.sh` retires. It strips a recommendation
  so that no Accept runs during the sitting, and under this design no Accept
  runs while the sitting's conversation is open. The sitting answers the gate
  when it rules, and a sitting that ends with no ruling leaves the
  recommendation standing, which is right, since nothing was decided.

The gate domain declares `gc.recommendation` and takes over `gc.acceptance`
from the reaction domain, so each key's name appears once in gctk. Unit 1
changes every other place that spells the two retiring keys or the old verb.
A grep of their spellings outside `specs/` at 8d778ffee finds these:

- the scripts `converse-signoff.sh`, and `dispatch-path.sh` in a comment;
- the skills `converse-settle` and `work`, and `skill-needs.test.sh`, which
  pins the work skill's calls;
- gctk's `key-registry.json`, its README and its CLI wiring;
- the rig board's test data;
- the docs authority-map, component-model, deferred-dispatch, design-convoy,
  gctk-architecture, human-engagement, install, steering and warrants.

Unit 1 also changes every reader of Accept's answer, whose form moves from
`ruled: accepted <formula> accept:<token>` to section 2's. Accept's own check
of the answer moves with the verb. When Accept exits non-zero, the sign-off's
`take_recommendation` greps the gate's answer for the old form to tell
Accept's answer from one that reached the gate first. Left as it is, it would
read an acceptance Accept left unfinished as another answer, and close the
conversation where it now stops for the run that finishes the acceptance.
docs/human-engagement.md states the old form, and the sign-off's tests pin it.

Six open beads still carry `gc.recommended_formula`, five in gc-toolkit's
store and one in gascity's, and none of them waits on a gate (read on
2026-11-23), so nothing reads them and nothing moves for them. The move takes
over tk-ssm8qns.23, which would have moved the key's shell reads into the
reaction domain. The implementation child has it wait on unit 1, armed to the
validating closer, which closes it once unit 1 lands.

## 7. The epic's open questions

A yes with one change (22 of 83) stays a conversation. Accept takes the
recommendation as recorded, and a change alters the act, which an agent must
rewrite and you must see, so Discuss opens the conversation where that
happens. The checkpoint can count how many of those changes were small enough
to have been an Accept with a note before anything is built for them.

The confirmations (10) are accepted. A confirmation asks you to confirm
something you did, and its recommendation is that the work waiting on it goes
on, so its asker records `proceed`, and Accept is your confirmation.

## 8. How the indicators are read

Both read the gates in every rig's store and the city's at the epic's
checkpoint, over a window that starts when the board's Accept lands.

- **Your plain yeses given from the board.** The numerator is the gates
  answered in Accept's form (`ruled: accepted: ... accept:<token>`) that no
  conversation replies to. The denominator is every plain yes: that numerator;
  the gates answered in Accept's form that a conversation replies to, which a
  sitting's `--accept` gave; and the plain yeses a sitting gave to a
  recommendation no asker recorded, which only its hand-back shows and which
  are read as the 2026-11-18 baseline read them. Beside the share, the
  checkpoint gives how many questions reached you with a record, which bounds
  how far the board can go (decision 1).
- **Accepted questions whose work went ahead with nothing more from you.** Of
  the gates answered in Accept's form, the share whose act landed, with no new
  human gate or conversation on the same bead in the seven days after the
  answer. An act landed when its answer stands, and, for `sling`, when a root
  titled with the token is not a failed pour, for `stand-down` when the bead
  closed as not needed with the gate as its evidence, and for `retire` when the
  PR closed with its disposition. A question Accept put back on the board
  counts against the share.

## 9. The boundaries, read against every file the units change

No unit changes a file `tools/deletion-plan.tsv` lists. Against the epic's
boundaries:

- **The board's second data plane, its pack-stamped rows and its verbs that
  only call Gas City (tk-1tfzr71.24).** That retirement has landed. Unit 3
  changes the board that replaced it: `services/helm/internal/rigboard`, the
  rig page under `services/helm/web/src/rigboard`, and the write routes in
  `services/helm/internal/server` and `services/helm/internal/verbs`.
- **Its old Go contract and TypeScript mirror (tk-1tfzr71.25,
  tk-1tfzr71.70).** Unit 3 adds a field to the rig document in Go, whose
  TypeScript tygo generates (`document.gen.ts`), and adds no parity test. Its
  route's request and answer are mirrored by hand beside the page's fetch, as
  `/helm/engage`'s are (`services/helm/web/src/actuate/client.ts`), which no
  scheduled bead retires. Unit 1 removes the lifecycle entries of the two keys
  it retires, as a retirement does, and adds none, since only gctk writes the
  new key.
- **Whether a question reaches you, and what stands out (tk-99h9ijx).** No unit
  changes which questions reach you or their order.
- **The board's design as a whole (tk-yhquh93).** Unit 3 adds one button and
  its answer.
- **The wording every question follows (tk-tem3f2a).** No unit changes how a
  question is worded. The closer's step and the waits skill gain the call that
  records the course their wording already states.

The units change no script beyond a fix in place and add none. The sign-off
only changes the command its `--accept` runs, the closer's step and the waits
skill call a gctk verb, and one script, `converse-invalidate-recommendation.sh`,
is deleted. Each new rule is Go in gctk, apart from the board's own code in
its service.

## 10. Units

Each unit lands on `integration/tk-3d1d6p0.2` and changes, in the same change,
the living docs its change makes true, such as the ones section 6 lists for
unit 1. This design's own change states the target in docs/architecture.md,
with a Debt entry that the last unit to land removes.

| Unit | What it builds | Waits on |
|---|---|---|
| 1 | The gate domain: the `gc.recommendation` record; `gctk gate recommend` with `proceed` and `sling`; `gctk gate accept`, moved from `gctk reaction accept`, with the same two acts, the refusal of a `rev` that is not the live one, and the refusal while another conversation is open. The first reaction's recommend exit records on its gate. `gc.recommended_formula`, `gc.recommended_formula_dispatched` and `converse-invalidate-recommendation.sh` retire, and the sign-off's `--accept` calls the gate verb. | nothing |
| 2 | `stand-down` and `retire` in both verbs, each in its writer's order. | unit 1 |
| 3 | The board's Accept: the course on a row that qualifies, the button, `POST /helm/accept`, the panel's answer, and the Question row of docs/bead-standing.md. | unit 1 |
| 4 | The askers: the validating closer's step 2b records its course; the waits skill says how any asker records one, which a decliner and a wait on outside work follow; the polecat doctrine's paragraph on declining points there. | units 1 and 2 |
