---
name: Operator review dispositions, PR #475
description: What each of the fifteen operator review threads on PR #475 asked for, what answered it, and which were resolved — the record behind the in-thread replies.
bead: tk-awa7hv
---

# The fifteen threads

The operator opened fifteen line-level threads on PR #475 between 16:46 and
17:06 on 2026-08-26, in a review submitted as COMMENTED. No signoff rework
path fires on a COMMENTED review, so nothing routed them and they sat
unanswered through three codex rounds. The CHANGES_REQUESTED review of
2026-08-27 said so in one line: "Comments still don't have replies."

Every thread carries a reply and every thread is resolved. Nine were
resolved because what they asked for has landed. The remaining six are one
defect that is tangential to this PR, and review 5074283592 set the rule for
that case: a comment that is not about the process at hand is triaged to a
bead rather than waited on.

## Resolved: changed in this PR

| Thread | Comment | What answers it |
|---|---|---|
| `template-fragments/learning-exemplars.md:71` | the corpus should sit with the other learnings, not in `docs/`; then, on the reply, that the whole file is loaded as "the exemplars" and that it breaks the sibling naming format | moved from `docs/learning-exemplars.md` to `template-fragments/learning-exemplars.template.md`, beside the profile and both learned-conventions fragments; the 74 lines of authoring doctrine moved to `skills/learning-distill/SKILL.md`, leaving a 331-byte carrier of the managed-by anchor and the entries, and the filename, define and heading now match the sibling fragments (`tk-z01mq2`) |
| `converse.md:596` | the lead-with-the-decision entry contradicts ending with the decision | the ordering half of `rule:tk-vglpm` is gone; the entry now states self-containment only (`operator-profile.template.md:9-12`) |
| `converse.md:612` | structural cause should also mean preventing the thing by design | `rule:tk-b80kkz` now says find what allowed it and prefer a design in which it cannot happen again (`operator-profile.template.md:25-29`) |
| `converse.md:625` | a code-comment rule landed in an agent that never writes code | moved to `learned-conventions-polecat.template.md:7` and `learned-conventions-mechanik.template.md:21`; it reaches polecat, polecat-codex and mechanik, and no longer reaches converse |

## Resolved: answered, no change needed

`learning-recurrence.sh` — "No sign report.json ever gets cleaned up."
`$TMP` comes from `mktemp -d` with an EXIT trap on line 112, and
`$TMP/report.json` is the only path the file ever has. It is written once,
read back twice, and removed with the directory on any exit. The rework added
the comment at :151-152 so the answer is visible where the file is read.

`learning-recurrence.sh:1` — "Is there some common key it runs on, does it use
an LLM even though it's a script?" Two literal string keys and no model call:
M1 groups on `obs.category`, M2 on `obs.distilled`. Neither compares meaning.

That question was also the finding. Repeats are by construction
`categorised - distinct`, so while the slug is minted per capture the M1
numerator says only how many distinct slugs capture minted. Measured on the
live corpus 2026-08-28: 241 events, 222 distinct, 19 repeats, and
241 - 222 = 19. The report now withholds the rate below 1.5 events per
category rather than printing a number that reads as loop health.
`recurrence-metric-keying.md` holds the full derivation.

## Resolved: a bead was what the operator asked for

`converse.md:45` and `:101` — the injected bash blocks — are `tk-jfw6qr` (P2,
open). The source is `agents/converse/prompt.template.md`, the `CLAIMER`
search at :46 and the marked `visit-fold-check` block at :97-139, neither
touched by this PR. The thread's open question is answered on the bead: the
blocks are not pre-executed, the renderer expands Go template directives only,
and the agent runs the bash itself at claim time.

`converse.md:563` — the closing paragraph must be self-contained and say why —
is `tk-h3kum6` (P2, open). It was filed depending on the `:596` contradiction
above, which this PR settles, so it now has one rule to write against.

## Triaged to a bead: the broadcast has no per-role targeting

Six threads across `deacon.md:1`, `:85`, `:132`, `keeper.md:345`,
`refinery.md:127` and `:184` are all one defect, filed as `tk-ixpfau` (P1,
open): shared fragments render into every agent that includes them, with no
per-role gate. Two of the six name fragments this branch does not touch at
all — **Rename yourself when your focus shifts**, and **End With the
Operator's Decision** rendering into a refinery that is never interactive.

This PR does not widen the reach. `{{ template "operator-profile" . }}` is
elected by seven agent templates and the fragment lands in nine rendered agent
files, and that set is identical on `origin/main` and on this branch. What the
PR changes is the content: the profile grows from three entries to nine, which
makes an untargeted broadcast more expensive without changing who receives it.

An earlier round left the six open, on the reasoning that resolving them
would claim a fix that had not landed. Review 5074283592 rejected that
reasoning: a tangential comment is triaged to a bead and worked there, and
only a comment about the process at hand is waited on. Nothing this PR could
change is what these six want, so they are resolved against `tk-ixpfau`
rather than held.

# Replying is not blocked

`tk-01n5cc` — PR write-back — is open and routed to a human, and the round-3
signoff offered to pull it forward on the premise that the city cannot post
replies. That premise is false. All fifteen replies here were posted with

    gh api repos/<owner>/<repo>/pulls/<n>/comments/<comment-id>/replies -f body=@<file>

and the nine resolutions with the GraphQL `resolveReviewThread` mutation, both
under the city's existing `zook-bot` token and its `repo` scope. No new
capability was needed.

What `tk-01n5cc` still buys is that this round was hand-instructed. The
mechanism exists; nothing in the loop invokes it, so answering a review
depends on an agent being told to, which is how fifteen threads went
unanswered through three rounds. That is the argument for the bead, and it is
a different argument from the one the signoff made.
