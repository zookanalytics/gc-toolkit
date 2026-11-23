---
name: What a pull request's labels and states mean
description: Read it when you meet a pull request the city opened and want to know what its labels and its bead's merge state mean, whose move it is, and what you can do.
---

# What a pull request's labels and states mean

The city lands most work through a pull request (PR) on GitHub. It opens the
PR when an agent finishes the work, and it merges the PR once nothing stops
it, such as a missing approval or a failing check. Each piece of work is
tracked as a bead, the city's record of one task, and the bead follows its PR
until the PR merges.

This page explains what you see along the way: the labels on the PR, which
say whose move it is, and the merge state on its bead, which says where the
PR is on its way to merging.

## Scope

**Mandate.** What a person reading a pull request the city opened sees of its
state, what each value means, and whose move it is.

**Boundaries.** Which part of the city writes each state, and when, is
[state-machine.md](state-machine.md). How the city decides when to merge is
[refinery-merge-cadence.md](refinery-merge-cadence.md). Where the PR's bead
stands on the board, and whose move it is, is
[bead-standing.md](bead-standing.md).

## The labels on a pull request

Each open PR the city opened carries exactly one `status:` label. The board
shows the same value on the PR's row.

| Label | What it means | What you can do |
|---|---|---|
| `status: working` | The city is still working on the PR, for example reviewing it or reworking it to answer review comments. | Nothing yet. |
| `status: needs-review` | The city has finished with the PR, and it waits for a person to review it. | Review it. Approve it, or comment, and the city works on your comments. |
| `status: merging` | The PR is approved and nothing known stops it. | Nothing. The city merges it once its required checks pass. |
| `status: needs-attention` | Something stops the PR that the city will not clear on its own. | Clear what stops it. A `held:` label usually names it. |

When more than one applies, the label shows the first that does, in this
order: `needs-attention`, `merging`, `working`, `needs-review`.

`services/gctk/prstatus` declares the four values as `State`, each with its
meaning, and `gctk pr status <bead>` prints the one a PR reads. The board also
places the PR's bead by whose move it is: a bead whose PR reads `needs-review`
or `needs-attention` waits on you, and one whose PR reads `working` or
`merging` is the city's
([bead-standing.md](bead-standing.md#where-a-beads-words-meet-its-pull-requests)).

A `held:` label names one kind of thing that holds the PR for a person, one of
the values `services/gctk/prstatus` declares as `Hold`. More than one can show
at once, and any of them makes the status `needs-attention`.

| Label | What holds the PR | What you can do |
|---|---|---|
| `held: gate` | A question the city asked a person, about the PR or about work the PR waits on. | Answer the question on the board. |
| `held: review` | Review comments that wait for the city's answer, with no work under way to answer them. | Resolve the threads that are done, and decide what the city should do about the rest. |
| `held: blocked` | Something else only a person can move: a decision, an open conversation about the PR, a bead in your queue (assigned to `human`), or another PR it waits on that is itself waiting on a person. | Make the decision, close the conversation, act on the bead in your queue, or move the other PR. |

A PR can also read `needs-attention` with no `held:` label, for example when
a required check failed, the branch conflicts with its base, or merges are
frozen.

## The merge state on the bead

The bead carries the pending record, the city's record of its PR from the
time the city publishes the PR until it merges
([state-machine.md](state-machine.md#the-pending-record)). The record's
`merge_result` is the bead's merge state: it says where the PR is on its way to
merging, and `bd show <bead>` prints it.

| `merge_result` | What it means | Whose move |
|---|---|---|
| no value | The work is not waiting on a PR: it has not reached one yet, or it was sent back to be worked on again. | The city's. |
| `pull_request_pending` | The PR is open at the version the city checked, and the bead waits for it to merge. The bead shows as blocked, with the reason "Awaiting verified merge of" and the PR's address. | The city's. It reads the PR every few minutes and merges it once it is ready. The PR's labels say whether it waits on you. |
| `pull_request_head_changed` | Someone pushed to the PR after the city checked it. | The city's. It checks the new version, then waits for the merge again. |
| `pull_request_record_incomplete` | The city stopped part way through recording the PR. | The city's. It checks the work again and records the PR afresh. |
| `mr_merged` | The PR merged the version the city checked. The bead is closed. | Nobody's. The work is done. |

### When a person must step in

Each value below stops the bead for a person. The city files a question on
the bead that says what happened and what to decide. Until someone answers
it, the bead stays blocked, and so does any work that waits on it.

| `merge_result` | What happened | What to decide |
|---|---|---|
| `pull_request_closed_unmerged` | The PR was closed without merging. | Reopen the PR and send the work back, or drop the work. |
| `pull_request_merged_unvalidated_head` | The PR merged a version the city had not checked. | Check what merged, then close the bead as landed or send the work back. |
| `pull_request_reconcile_invalid` | The PR no longer matches what the bead records, for example after its base branch changed. | Correct the bead or the PR, or drop the work. |
| `pull_request_merge_evidence_contradiction` | What GitHub says about the merge contradicts what the bead records. | Check what merged before you close the bead. |
| `pull_request_legacy_closed_unverified` | The bead was closed while it still waited on its PR, with no merge confirmed, so the city reopened it. | Check whether the PR merged. If it did, close the bead as landed. If not, send the work back or drop it. |
| `pull_request_merged_close_refused` | The PR merged, but the bead could not be closed, for example because work inside it is still open. | Clear what stops the close, then close the bead as landed. |

One more value appears. `merged` marks work that landed without a PR, pushed
straight onto its target. [state-machine.md](state-machine.md) lists every
value with the code that writes it.
