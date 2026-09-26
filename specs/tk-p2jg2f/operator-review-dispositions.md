---
name: PR#808 operator review dispositions
description: How each unanswered thread on the operator's CHANGES_REQUESTED review of PR#808 (review 5262733166) was answered — a code change, an in-thread answer, or a referred decision — so the next reviewer reads a table instead of re-deriving the threads.
---

# PR#808 operator review dispositions

Review 5262733166 (`johnzook`, CHANGES_REQUESTED) carried two inline comments and
no body. The fix appends to `polecat/tk-p2jg2f` fast-forward, so the review and
both line-anchored threads stay live at their commits.

| Comment | Locus | Disposition |
|---|---|---|
| 4058986418 | `assets/scripts/pr-facts.sh:466` | answered in-thread; rationale made durable on `finding.sh` |
| 4058996699 | `assets/scripts/validate-dispatch-body.sh:58` | referred to the operator — visit `tk-8njogj` |

## 4058986418 — "Do review comments not have a stable ID provided by GitHub?"

They do: a review, an inline comment, and a Conversation comment each carry a
stable GitHub id, and `pr-facts.sh` already keys the per-source watermark on it.
The dedup key is deliberately not that id. `finding.key` identifies an
*objection*, not the GitHub row that carried it, and the two diverge: a
re-review re-raises a still-standing objection under a fresh review and comment
id, so an id-keyed finding would twin every review pass where the content key
re-adopts. The line an inline comment sits on is normalized out of the key, so a
rebase that renumbers a file does not re-raise the finding either. The clause
added at `finding.sh`'s `compute_key` states this so the next reader of the key
does not have to ask.

## 4058996699 — the bar for human-sourced findings

The comment questions the rule that a human-sourced finding the validator would
decline is held must-fix and withdrawable only by its raiser: it over-elevates
human input toward gospel, when the human is a highly-informed peer who
sometimes lands tentative notes. This changes the feature's core semantics, so
it is the operator's ruling, not a fix to make here. Visit `tk-8njogj` carries
the decision, a proposed "peer" model (the validator may decline a human finding
on its merits but owes a posted reply, and the raiser can re-raise), and the two
alternatives. The thread is left unresolved pending that ruling.
