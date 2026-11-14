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

A `held:` label names one kind of thing that holds the PR for a person. More
than one can show at once, and any of them makes the status
`needs-attention`.

| Label | What holds the PR | What you can do |
|---|---|---|
| `held: gate` | A question the city asked a person, about the PR or about work the PR waits on. | Answer the question on the board. |
| `held: review` | Review comments that wait for the city's answer, with no work under way to answer them. | Resolve the threads that are done, and decide what the city should do about the rest. |
| `held: blocked` | Something else only a person can move: a decision, an open conversation about the PR, or another PR it waits on that is itself waiting on a person. | Make the decision, close the conversation, or move the other PR. |

A PR can also read `needs-attention` with no `held:` label, for example when
a required check failed, the branch conflicts with its base, or merges are
frozen.

## The merge state on the bead

The bead's `merge_result` says where its PR stands, and `bd show <bead>`
prints it.

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

Two older values also appear. `merged` marks work that landed without a PR,
or through the older way of merging. `pull_request` marks an open PR on a rig
that still merges the older way. [state-machine.md](state-machine.md) lists
every value with the code that writes it.
