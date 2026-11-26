---
name: The caller's seat replayed on #1657's reviewed head
description: Read it to check the done-when replay in tk-owrh3w1's summary, to see what the arch check's caller's-seat reading asked of #1657 at 4e8205898d45 and of a control PR the operator approved as built, or to re-run the replay on a later wording.
---

# The caller's seat replayed on #1657's reviewed head

tk-owrh3w1's done-when asks that the arch check's method, as this change leaves
it, raise the running-or-not choice when it runs over #1657's reviewed head,
4e8205898d45. At that head the work skill and converse-settle send a caller to
`gctk bead revise` for work already sent that goes on, and to bd's own note
append otherwise. The city's review at that head approved the change with no
finding, and the operator sent it back because a caller had to know whether the
work was in flight to pick its command.

This replay ran the arch check three times under main's text and three times
under each of three wordings of the new text, holding everything else the same.
It also ran the check twice on a control PR the operator approved as built.

## Results on #1657

| Text | Runs | Verdict | Finding on the running-or-not choice (revise or bd's note append) | Finding on the open-PR choice (revise or an ask on the PR) |
|---|---|---|---|---|
| main at 10701dd47 | 3 | approve in 3 | 0 | 0 |
| first wording, 283f79fcf6 | 3 | request-changes in 3 | 2 | 1 |
| second wording, 0a5e1d0af9 | 3 | request-changes in 3 | 1 | 2 |
| third wording, 9124c859f7 | 3 | request-changes in 3 | 1 | 2 |

Every run under the new text sent the change back on the caller's seat, each
with one blocking finding there. Each such finding said the caller must know
where work already sent stands before it picks a command, and that `revise`
could find this out itself. Four runs named the operator's pair: the caller
picks `revise` or bd's note append by whether the work runs. One put it this
way: "So the caller must know whether the bead's work runs and who holds it,
which is the state the doc's caller's-seat rule names as one a caller must not
track. The command already finds it out itself." The other five named a second
choice in the same teaching. The work skill sends a change to a bead whose work
already has an open PR as an ask on the PR, so the caller picks `revise` or an
ask by whether the work has an open PR, or has reached the refinery. The command
could read that state from the bead's pending record.

Two of those five took the choice between `revise` and the note append to be
the caller's own intent: "its caller must know that the work goes on with a
change (its own intent) and whether the bead's work already has an open PR,
which picks revise or an ask". #1657's teaching mixes the two. It opens on
intent ("When the work should go on with a change to what it does") and sends
on by state ("work already sent", "and that work goes on").

No run under main's text raised either choice. Two of them opened
`docs/gctk-architecture.md`, and one judged the verb by its mechanism: "the
revision still writes the note first; the nudge only tells the running
session". That matches the city's review at that head.

The divergence lens raised a finding of its own in five runs. #1657's nudge
passes `--reference-bead`, a flag only the city's fork of Gas City carries.
One run under main's text deferred it as a P2. Four runs under the new text
held the change for it and also deferred the older use of the flag in
`gctk bead takeaway`. The replay does not show whether the new text moved that
rate, since three runs per arm cannot tell it from chance.

## The wordings

- **First** (283f79fcf6): the two questions, the finding and the parallel rule
  read from the caller's seat. One run answered the first question against an
  ask on the PR alone and never weighed the native append.
- **Second** (0a5e1d0af9): before answering, list every other command the
  caller could run for what it means to do, the native ones among them. Every
  later run listed bd's note append in its Caller line. One then judged that
  the caller "need not know whether a run is live", because the command
  handles both states.
- **Third** (9124c859f7): a caller knows a command only as it is taught, so the
  first question is answered from the teaching. A verb the teaching uses in
  some states of an act, beside the native call it uses in the others, is a
  parallel even where the verb could carry the act in every state. The runs
  read one clause the commit narrows: they were told to answer both questions
  from the teaching. The commit keeps that for the first only, since the
  second asks what the command can find out.

The share of runs naming the running-or-not pair did not rise across the
wordings: 2, 1 and 1 of 3, which three runs per wording cannot tell from
chance. The replay stopped after the third round.

## The control: #1387

#1387 added `stand-down.sh`, the one command for a ruling that gated work will
not go on, and the operator approved it as it stood (report tk-ud5dv6g). Two
runs read it under the second wording at its merged head, b5162f79b2. Both
requested changes with one caller's-seat finding. `stand-down.sh` makes its
caller pass the gate's situation key, and the command could find that key
itself: every path that succeeds needs each open, unassigned human gate that
blocks the bead to share one key, and the command already reads them. Each run
judged the other flags it named, such as the ruling, its evidence and a dry
run, to carry only what the caller knows.

The report counts #1387 as landed with no change from the operator's
conversation on it, so on this one PR the check asks for a change their review
did not. Whether they would want it is for them to say. One run also deferred a
P2 on `docs/architecture.md`, which this replay does not concern.

## Method

- **The change under review.** A `git archive` of 4e8205898d45, the head of
  `polecat/tk-raefwni` when the PR opened and when the city's review approved
  it. Each arm laid `docs/review-arch.md` over it, main's at 10701dd47 for the
  current arm and the branch's for each new arm. Each new arm also applied the
  branch's diff of `docs/gctk-architecture.md` to the snapshot's copy, which
  #1657 itself changes in its verb table and its list of what each noun owns,
  away from the lines this change edits. The change is
  `git diff 3ee4ea5909b9...4e8205898d45` with its three commit messages. The PR
  as published is #1657's first title and its body as first published, the
  oldest node of its `userContentEdits`.
- **The method.** The pack's `review-arch`, `specialist-stance` and
  `architecture-document` skills at main 10701dd47, which this change leaves
  alone, the same in every arm.
- **The prompt.** It follows the lane step of `formulas/mol-pr-review-lane.toml`
  at main 10701dd47: the snapshot's `AGENTS.md`, the method, then what
  `review-run.sh lane` prints (the PR as published, the rig's guidance for arch
  and the change). It asks for the verdict body's lines under `TRAIL`, then the
  lane's output. The prompts differ only in the rig's guidance.
- **Gas City beside it.** `gastownhall/gascity` at main dfd5200c3e, the commit
  #1657's search read, read-only through `--add-dir`.
- **The control.** The same, at #1387's merged head b5162f79b2, with its diff
  from bd5769f680, its commit messages and its body as merged. The snapshot
  predates `docs/gctk-architecture.md`, so the branch's copy at the second
  wording was laid over it beside the branch's `docs/review-arch.md` at that
  wording. Gas City is the same snapshot, newer than #1387.
- **The run.** A clean headless Claude Opus 5.5 run per review, with no memory,
  hooks, skills or MCP and file tools only, in the arm's snapshot:

  ```bash
  env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Users/gc/.local/bin \
    TMPDIR="$TMPDIR" LANG=en_US.UTF-8 \
    claude -p --safe-mode --restricted --strict-mcp-config --disable-slash-commands \
      --no-session-persistence --permission-prompts none --tools "Read,Grep,Glob" \
      --model claude-opus-5-5 --max-turns 80 --output-format stream-json --verbose \
      --add-dir <gascity snapshot> < <arm prompt>
  ```

  The 14 runs ran on 2026-11-26 between 16:18:40Z and 16:27:39Z, three
  batches in parallel. Each took 7 to 32 turns and 61 to 163 seconds. Together
  they read 16.6M input tokens, 15.2M of them from cache, and wrote 135k output
  tokens.

## What this shows and what it does not

- The new text moves the arch check from approval to a send-back on #1657's
  reviewed head in every run. Each run names a choice its caller makes by where
  work already sent stands, a state the command could read. The exact pair the
  operator named, `revise` or the note append, comes up in 4 of 9 runs, so a
  single lane names that exact pair a little under half the time.
- The replay is one PR, which the wordings were written from. It does not show
  that the reading reaches a command unlike this one. The control shows it
  firing on a second, different command, a required key the command could
  derive, which the operator approved as built.
- A clean run cannot run a command, so no run looked anything up in a store,
  as a lane in the city can.
- The builder's side, the plan's answers, is not replayed here.
