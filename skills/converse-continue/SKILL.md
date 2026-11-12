---
name: converse-continue
description: Converse's continuation of an open conversation, which answers the operator's turns, carries out a ruling given before the end, opens a conversation on a new concern, and picks a sitting up after a restart while its hold stands.
---

# Continue the conversation

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

## Each turn

While the conversation is open, every operator turn continues the sitting.
Before you answer, read the gates again, as `converse-prep` primes them: a gate
filed on the subject while the sitting runs shows up there, and so does one
another answer has cleared.

When the operator rules on a gate in a turn that does not end the sitting,
answer it at once, so a dismiss later leaves nothing they ruled on open. First
reply to the gate and name what the answer releases (`converse-settle`, Answer
the gates). Then settle the subject's dispatch path, as `converse-settle` gives it,
and answer through the sign-off's writer with `--answer`, never a bare gate
resolve. A
gate can hold a merge, so the writer puts the ruling's consequences in place
before it resolves the gate. It resolves only the gates it names, leaves the
conversation open, and exits non-zero when it stopped short. Until it exits 0,
do not tell the operator the ruling is in place:

```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate> \
  --ruling "<the operator's ruling, one line>" \
  --outcome "<where the subject stands now, at most 140 characters, or 95 when the ruling leaves an open PR standing>"
  # when the ruling reaches an open PR, add --rework, --no-rework or --retire <kind> (converse-settle)
  # when it takes the subject's recommendation, --answer its gate and add --accept (converse-settle)
  # --waiting-on <bead> for each bead this turn routed work into, or --no-wait
  # --close-brief "<what that work's landing settles here, and what to check once it has>" beside a --waiting-on on work
```

A ruling that sends the subject on is carried out once the answer exits 0, as
the end's cases do. An answer that reached the gate first stands, and the
writer prints it: tell the operator. Pass on each line it prints about an open
PR whose merge still waits on GitHub, after whatever else the ruling leaves
holding that PR. Record what each turn settles, and sign off once nothing
important is pending (`converse-settle`).

## A new concern

A new concern the operator raises is a conversation of its own. Open it on its
bead, where it waits in the operator's queue until they engage it:
`"$CONV/gc-helm.sh" open <bead> --reason "<what it is about>" --body "<the ask the sitting reads>"`.

## After a restart

The entry says `interrupted` and names this skill when a restart came while the
hold stood. When your thread holds the framing you posted, there is nothing to
do but wait for the operator. When it does not, re-open the sitting from the
record: prepare it again (`converse-prep`), then hold again (`converse-hold`),
whose framing can repeat the hand-back the entry printed. Skip the premise
re-check, which was made when the sitting began, because a re-check now can
close a conversation the operator is part way through.

## When the conversation closes

The sitting ends once the conversation closes, by your sign-off or the
operator's dismiss. Run `gc runtime drain-ack` once every write after the close
has landed, and nothing after it. A dismiss stops this session itself: a tab
still attached holds the stop until it detaches, with a title that leads with
`done`, and then prints the last hand-back recorded on the conversation.
