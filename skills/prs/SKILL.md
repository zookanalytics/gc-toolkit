---
name: prs
description: Use when something has to happen to an open pull request or its anchor bead. Covers answering its review comments (posting a comment, replying in a thread, resolving a thread), sending it back for rework so its branch changes, holding its merge until something is settled, and retiring it (closing the PR and disposing of its anchor because the work moved, is not needed, or is wrong). For work that is not a pull request yet, use work; for a bead that must wait on another, use waits.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# PRs: what happens to an open pull request

An open pull request is tracked by its anchor, the bead whose `merge_result` is
`pull_request`. The refinery's reconcile reads the PR and its anchor every pass
and lands the PR once it is approved and nothing holds it. Each option says what
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
thread whose fix a rework landed. A thread you answered yourself, with nothing
left to land, you resolve with GitHub's `resolveReviewThread` mutation on the
thread's `PRRT_` id:
`gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' -f t=<PRRT_ id>`.
Leave a thread open when a person replied in it after you, or when it holds a
declined, deferred or needs-you point, because a person closes those.

## Send it back for rework

The message is that the branch must change before it lands. A rework child
blocks the anchor, which holds the merge, and a polecat resumes the PR's own
branch, so the PR keeps its history.

Writer: `rework-child.sh`, the one writer of a rework child that a ruling or a
review verdict sends. A sitting reaches it through its sign-off, by adding
`--rework` to the `--ruled yes` call (the converse-settle step), which also
returns every review lane to unreviewed so the whole branch is reviewed again
once the rework lands. A review verdict reaches it through the reviewer's own
sign-off.

Scope found while the PR is open, with no ruling behind it, rides a supplement
bead instead. A supplement is PR-finishing work, and its create sets up
everything the PR needs from it before it is sent to the polecat pool:

- `--rig <rig>` names the rig whose store holds the anchor. A pool reads only
  its own rig's store, and `gc sling` refuses a bead filed in another rig's
  store.
- `branch`, `existing_pr` and `target` are the PR's, so the polecat commits
  onto the PR's branch and the PR gains the commits. `target` is the PR's base,
  which for a PR under an owned convoy is `integration/<convoy-id>`, not the
  default branch. The refinery blocks a supplement whose `target` is not the
  PR's base.
- `anchor_bead` makes it a child of the anchor, joined to it by
  `related:<anchor>`, and `blocks:<anchor>` makes the anchor wait on it, so
  the PR does not merge before the supplement lands.

The command reads the edge back from the anchor before the sling, and slings
nothing when the edge is missing:

```bash
SUP=$(gc bd --rig <rig> create "<what the PR still needs>" -t task -d "<what to add, why, and what done looks like>" \
  --deps related:<anchor>,blocks:<anchor> \
  --metadata '{"anchor_bead":"<anchor>","branch":"<the PR head branch>","existing_pr":"<the PR url>","target":"<the PR base branch>"}' --json | jq -r '.id') \
  && gc bd --rig <rig> dep list <anchor> --direction=down -t blocks --json | tr -d '[:cntrl:]' | jq -e --arg s "$SUP" 'any(.[]; .id == $s)' >/dev/null \
  && gc sling <rig>/<pool> "$SUP"
```

Once the supplement's work lands on the branch, the refinery closes the
supplement and the anchor keeps gating the PR. Send one supplement at a time
on a branch. A polecat pushes with a plain `git push`, so a second supplement
in flight on the same branch is rejected non-fast-forward at its push and stays
with its polecat.

Replace a PR only when its implementation is wrong, never because it is
incomplete. Missing docs, a test a reviewer asked for or an edge case the diff
exposed is a supplement.

## Hold its merge

The message is that the PR must not land until something is settled. The merge
holds while any open bead blocks the anchor, and clearing that bead releases
it. The operator sees the gate on the anchor's row of the board and answers it
there or in a sitting.

Writer: a human gate on the anchor, filed through the helper, which keeps one
open gate per anchor and situation key:
`"$(gc <binding> scripts-dir)/human-gate.sh" --subject <anchor> --key <situation-key> --message "<what must be settled first, at most 140 characters>"`.
A sitting files its own with the key `conversation` and replies to it (the
converse-hold step). The gate is cleared with
`gc bd gate resolve <gate> --reason "ruled: <the answer>"`, and the same call
with `--retract` withdraws your own gate once the question has gone.

Every open bead the anchor waits on, and every open bead filed under it, holds
its merge, whatever it was for. Never make an anchor wait on a follow-up that
needs the PR on main to do its own work. Make the follow-up wait on the anchor
instead (the waits skill), and never file it under the anchor (the work skill).

## Retire it

The message is that the PR will not land because its work moved, is not needed,
or is wrong. The writer records the disposition on the anchor and closes the
PR, and the reconcile closes the anchor on its next pass through the
disposition writer, `bead-rehome.sh`.

Writer: `"$(gc <binding> scripts-dir)/pr-dispose.sh" --anchor <anchor> --successor <bead> --kind not-needed --note "<why, one sentence>"`.
The anchor must be open at `merge_result=pull_request`. Under `not-needed` the
successor is the evidence that ruled the work out, such as the conversation
where it was decided. Under `duplicate`, `folded`, `re-homed` and
`fixed-upstream` it is the bead that carries the work now. Never close the PR
by hand first: a PR closed with no disposition recorded reads as abandoned, and
the reconcile files a human gate on the anchor asking whether to rework it or
close it.

A supplement still open on the PR keeps its `blocks` edge on the anchor, so the
anchor's close waits until the supplement closes. Stop and close the supplement
too (the work skill). An open human gate on the anchor holds its close the same
way (`docs/finalize-gate.md`), so the reconcile closes the anchor once each
gate is cleared.

In a sitting, retire a PR only on the operator's ruling, once the sign-off has
answered the gates the ruling settles, with the sitting's conversation as the
successor:

```bash
"$(gc <binding> scripts-dir)/pr-dispose.sh" --anchor <anchor> --successor <conversation> --kind not-needed --note "<why, one sentence>"
```
