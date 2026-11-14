---
name: converse-continue
description: Converse's continuation of an open conversation, which answers the operator's turns, carries out a ruling given before the end, opens a conversation on a new concern, and picks a sitting up after a restart while its hold stands.
---

# Continue the conversation

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

## Each turn

While the conversation is open, every operator turn continues the sitting.
Before you answer a turn, read the gates again, as `converse-prep` primes them:
the read shows a gate filed on the subject while the sitting runs, and a gate
another answer has cleared.

When the operator rules on a gate in a turn that does not end the sitting,
answer that gate at once, so a later dismiss leaves nothing they ruled on open:

1. Reply to the gate and name what the answer releases (`converse-settle`,
   Answer the gates).
2. Then settle the subject's dispatch path, as `converse-settle` gives it.
3. Then answer through the sign-off's writer with `--answer`, never with a bare
   gate resolve. A gate can hold a merge, so the writer puts the ruling's
   consequences in place before it resolves the gate. The writer resolves only
   the gates it names, leaves the conversation open, and exits non-zero when it
   stopped short. Until it exits 0, do not tell the operator the ruling is in
   place:

```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate> \
  --ruling "<the operator's ruling, one line>" \
  --outcome "<where the subject stands now, at most 140 characters, or 95 when the ruling leaves an open PR standing>"
  # when the ruling reaches an open PR, add --rework, --no-rework or --retire <kind> (converse-settle)
  # when it takes the subject's recommendation, --answer its gate and add --accept (converse-settle)
  # --waiting-on <bead> for each bead this turn routed work into, or --no-wait
  # --close-brief "<what that work's landing settles here, and what to check once it has>" beside a --waiting-on on work, unless the sign-off arms no closer for the subject (converse-settle)
```

Once the answer exits 0, carry out a ruling that sends the subject on, as the
end's cases do. When another answer reached the gate first, that answer
stands, and the writer prints it: tell the operator. Pass on each line the
writer prints about an open PR whose merge still waits on GitHub, after
whatever else the ruling leaves holding that PR. The sign-off later reads a
gate answered here as already cleared, and leaves it. Record what each turn
settles, and sign off once nothing important is pending (`converse-settle`).

## A new concern

A new concern is a conversation of its own, whether the operator raises it or
another subject turns out to need them. Open it on its bead, where it waits in
the operator's queue until they engage it:
`"$CONV/gc-helm.sh" open <bead> --reason "<what it is about>" --body "<the ask the sitting reads>"`.

## After a restart

The entry says `interrupted` and names this skill when a restart came while the
hold stood. Take the case that fits:

- **Your thread holds the framing you posted.** Wait for the operator: there is
  nothing else to do.
- **Your thread does not hold the framing.** Re-open the sitting from the
  record: prepare it again (`converse-prep`), then hold again
  (`converse-hold`). The new framing can repeat the hand-back the entry
  printed. Skip the premise re-check: it was made when the sitting began, and a
  re-check now can close a conversation the operator is part way through.

## When the conversation closes

The sitting ends once the conversation closes, by your sign-off or the
operator's dismiss. Run `gc runtime drain-ack` once every write after the close
has landed, and run nothing after it. A dismiss stops this session itself. A
tab still attached holds that stop until the tab detaches. Until then the tab's
title leads with `done`, and once it detaches, the tab prints the last
hand-back recorded on the conversation.
