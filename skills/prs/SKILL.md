---
name: prs
description: Use when something has to happen to an open pull request or its anchor bead, such as answering its review comments, replying in or resolving a thread, sending it back for rework on its branch, holding its merge until something is settled, or retiring it because the work moved, is not needed, or is wrong. For work that is not a pull request yet, use work; for a bead that must wait on another, use waits.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# PRs: what happens to an open pull request

An open pull request is tracked by its anchor, the bead whose `merge_result` is
`pull_request_pending` on Gas Town's pending record, or
`pull_request_head_changed` while the refinery validates a head it has not. The
landing order reads the PR and its anchor on each run and merges the PR once it
is approved and nothing holds it. Each option says what
the message means, who acts on it, and the one writer that sends it. The
writer's `--help` carries its flags.

The writers are the gc-toolkit pack's own scripts.
`gc <binding> scripts-dir` prints their directory in the pack as gc loaded it,
so each example calls the pack's copy inside the command itself, and runs in a
fresh shell. `<binding>` is the name the city imports the pack under, which gc
puts in front of this skill's name: `gc-toolkit` in `gc-toolkit.prs`.
`gc skill list` prints it in this skill's FROM column.

## Answer its review comments

The message is the city's answer to a reviewer: a fix that landed, an answer to
a question, or a decision. The reviewer reads it, and the reconcile reads it as
the city's own post rather than new feedback.

Writer: `pr-post.sh`, the only way the pack posts on a pull request.

- A reply in a review thread:
  `"$(gc <binding> scripts-dir)/pr-post.sh" reply --host github.com --thread <the thread's PRRT_ id> --body-file <file>`.
- A conversation comment:
  `"$(gc <binding> scripts-dir)/pr-post.sh" comment --repo github.com/<owner>/<name> --pr <number> --body-file <file>`.

It appends the city's mark. The reconcile reads a post without that mark as new
feedback and routes it into rework, so never post with `gh` directly.

A rework that answers a review's findings posts no answer of its own. It records
each answer with `finding.sh answer`, as its work order says, and the city's one
living comment per review shows the reviewer how each point was answered. A
reply through `pr-post.sh` only adds detail that answer leaves out.

Resolve a thread only once its answer has landed. The write-back resolves a
thread whose fix a rework landed, and one whose declined or deferred point its
answer is on. A thread you answered yourself, a decline or a deferral included,
with nothing left to land, you resolve with GitHub's `resolveReviewThread`
mutation on the thread's `PRRT_` id:
`gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' -f t=<PRRT_ id>`.
Leave a thread open when a person replied in it after you, or when it holds a
needs-you point, because that person's ruling closes it. A reply in a thread
the city resolved is still feedback, which the reconcile reads and routes.

## Send it back for rework

The message is that the branch must change before it lands. An open PR has one
worker on its branch, its review run, and a sitting whose conversation holds the
PR can edit the branch beside it with the operator, pushing under the lease
(`converse-edit`). A send-back that the sitting does not make itself is an ask
the run takes. A sitting files it through its sign-off, by adding `--rework` to
the `--ruled yes` call (the converse-settle step), or to the `--answer` call of
a turn that does not sign off (the converse-continue step), with
`--check <check>` once for each check the ruling sends back. Nothing returns to
unreviewed, because the run triages the head its fix pushes. A must-fix point on
an open PR that no sitting rules, such as one a sitting or the mechanik finds on
another open PR, is an ask of its own on that PR's bead. It holds that PR's
merge from the moment it is filed, and the first run that can take it rules it
as it rules a person's comment:

```bash
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
"$GCTK" review ask <the anchor of the PR> --reason "<what must change, why, and what done looks like>" --source <the bead the point came from>
```

Add `--check <check>` for each check the point sends back. Exit 0 prints
`<ask> filed`, or `<ask> found` for an ask of the same source and reason, open
or closed. Exit 3 refuses an anchor that owns no PR on the pending record, and
a check the index does not declare. Exit 2 is a read that did not answer, and
the next call finds an ask that landed.

Replace a PR only when its implementation is wrong, never because it is
incomplete. Missing docs, a test a reviewer asked for or an edge case the diff
exposed is an ask on the PR.

## Hold its merge

The message is that the PR must not land until something is settled. The merge
holds while any open bead blocks the anchor, and clearing that bead releases
it. The operator sees the gate on the anchor's row of the board and answers it
there or in a sitting.

Writer: a human gate on the anchor, filed through the helper, which keeps one
open gate per anchor and situation key:
`"$(gc <binding> scripts-dir)/human-gate.sh" --subject <anchor> --key <situation-key> --message "<what must be settled first, at most 140 characters>"`.
A conversation on an open PR holds its merge until it closes, and otherwise
blocks nothing: the anchor depends on the conversation through a `blocks`
edge, which `gc-helm.sh open` adds and engage adds again when it starts a
sitting, so two conversations on one PR each hold its merge, and each one's
close, by whatever route, frees what it held. A sitting that is helping the PR
land, or whose conversation has nothing to do with whether it lands, lifts its
hold with `gc bd dep remove <anchor> <conversation>` and records why on the
conversation (the converse-hold step). A hold that must outlast the
conversation is a gate of its own on the anchor, under a key that names what
it waits for. The gate is cleared with
`gc bd gate resolve <gate> --reason "ruled: <the answer>"`, and the same call
with `--retract` withdraws your own gate once the question has gone. A sitting
clears a gate the operator ruled on only through its sign-off writer (the
converse-settle and converse-continue steps), which first carries out what the
ruling does to the PR, its rework or its retirement, so the merge never lands
in between.

Every open bead the anchor waits on, and every open bead filed under it, holds
its merge, whatever it was for. Never make an anchor wait on a follow-up that
needs the PR on main to do its own work. Make the follow-up wait on the anchor
instead (the waits skill), and never file it under the anchor (the work skill).

## Retire it

The message is that the PR will not land because its work moved, is not needed,
or is wrong. The writer records the disposition on the anchor and closes the
PR, and the landing order then closes the anchor on its next run through the
disposition writer, `bead-rehome.sh`. The landing order requests no merge of
the PR once the disposition is recorded, and it closes the asks and the approval
withdrawals still open on the anchor, which no review run takes once the PR is
closed.

Writer: `"$(gc <binding> scripts-dir)/pr-dispose.sh" --anchor <anchor> --successor <bead> --kind not-needed --note "<why, one sentence>"`.
The anchor must own an open PR: not closed, at `merge_result`
`pull_request_pending` or `pull_request_head_changed`. Under `not-needed` the successor is the evidence
that ruled the work out, such as the conversation where it was decided. Under
`duplicate`, `folded`, `re-homed` and `fixed-upstream` it is the bead that
carries the work now. Never close the PR by hand first: a PR closed with no
disposition recorded reads as abandoned, and the reconcile or the landing order
files a human gate on the anchor asking whether to rework it or close it.

Every open bead that blocks the anchor holds its close: an open human gate on
the anchor (`docs/finalize-gate.md`), the sitting's own conversation and a
review run attached to the anchor, so the closer closes the anchor once each of
them has closed.

In a sitting, retire a PR only on the operator's ruling, and only through the
sign-off writer: `--retire <kind>` on its `--ruled yes` call (the
converse-settle step), or on its `--answer` call when the ruling comes on a
turn that does not sign off (the converse-continue step). The writer runs
`pr-dispose.sh` before it answers any gate, so a gate that holds the merge
keeps holding it until the PR is closed. Answered first, that gate would let
an approved PR merge before its retirement. Under `not-needed` the successor
is the sitting's conversation, and every other kind names the bead that
carries the work with `--successor <bead>`:

```bash
"$(gc <binding> scripts-dir)/converse-signoff.sh" --conversation <conversation> --outcome "<headline>" --ruled yes --ruling "<the ruling, one line>" --no-wait --retire not-needed
```
