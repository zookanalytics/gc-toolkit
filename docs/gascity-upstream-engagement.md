---
name: gascity upstream engagement
description: When and how gc-toolkit engages upstream gascity — three-option framework, commit-as-review-packet, operator-gated PR submission.
---

# Gascity upstream engagement

This doc describes when and how gc-toolkit engages upstream
`gastownhall/gascity`. It is gc-toolkit-specific because the
engagement framing is a project convention, not a Gas City feature.

## The three-option framework

For every bug or design gap you hit in upstream `gascity`, evaluate
which of three options applies:

1. **Ignore** — wait for upstream to resolve, accept the cost in the
   meantime. This is the right answer most of the time, especially
   when others are already working the problem.
2. **Local patch** — carry the fix on `zookanalytics/gascity:main`
   until upstream catches up. The full mechanics live in
   [`gascity-local-patching.md`](./gascity-local-patching.md).
3. **Engage upstream** — only worthwhile when you have something
   **materially new** to add: a missing repro, a regression test, a
   consequence not yet noticed, a framing nobody has used. Engaging
   when others are already iterating on a fix is noise.

Default to option 1. Move to option 2 when the bug is hot and you
can't wait. Move to option 3 only when you have something new, *and*
you've decided you want the public footprint of an upstream PR.

## The commit message IS the review packet

Because gc-toolkit doesn't retain per-patch branches after merge, the
commit on `origin/main` carries the entire case for the change. The
review packet for a future upstream PR is the commit body — there is
no other artifact.

Each local-patch commit body should cover:

- **Symptom** the operator observed (event-rate, hang, error class).
- **Root cause** with file and function references.
- **Regression provenance** (when applicable) — which upstream commit
  or PR introduced the problem, and whether it looks deliberate or
  incidental.
- **Fix and rationale** — what the patch does and why this approach
  over alternatives.
- **Measured impact** — concrete numbers if available (event rate
  before/after, latency, error count). This is the strongest
  argument for upstream merit.
- **Adjacent upstream issues** — links to related PRs/issues with a
  one-line take on whether they overlap, complement, or address a
  different layer.
- **Local tracker** — bead ID so the city's decision history is
  reachable.

The body should read like a self-contained upstream PR description —
if promoted later it should be copy-pasteable with minimal editing.

## Operator-gated PR submission

**Agents do not file upstream PRs on their own initiative.** Upstream
submission is a user-gated, conversation-initiated decision. The
operator reviews local-patch commits at their discretion and may
flag a specific commit to initiate a "should this become an upstream
PR?" conversation. That conversation is the trigger; until it
happens, no PR work proceeds.

Concretely:

- Do not propose dispatching a polecat to file an upstream PR.
- Do not create beads whose acceptance criteria include "file
  upstream PR" or "submit to gastownhall".
- Do not push branches to the upstream remote.
- Do not recommend upstream PR work as a follow-up step or
  "what's left" item.
- Do not apply `upstream-candidate` labels or maintain any queue
  artifact — the git log on `origin/main` IS the candidate set.

Plans for closing local-patch decision beads stop at: local fix
shipped, measured, and bead updated with the full review-packet
context in the commit message. Upstream merge becomes a
stop-condition the operator evaluates later, not work the city
schedules.

## The candidate-set model

`gc-toolkit`'s convention is: **every commit on `origin/main` that
diverges from `upstream/main` is, by definition, a future
upstream-PR candidate.** No held branches, no labels, no separate
queue. The working tree on `origin/main` is the candidate list at
all times:

```bash
git log upstream/main..origin/main -- <path>
```

This keeps maintenance bounded — the candidate set is `git`-native
and shrinks naturally as upstream absorbs patches. The cost is
discipline: every commit on `origin/main` must carry full
review-packet context because there is no separate place to record
that context later.

## PR-creation handoff: compare URL, not `gh pr create`

When the operator chooses to promote a commit, the deliverable
back to them is a **GitHub compare URL** with title and body
pre-filled via query string — not a `gh pr create` command.

**Why:** The operator clicks the URL with their own `gh`-auth
identity. The PR is authored by them; the commit on the branch
stays authored by Zook Bot. Both get credit on the patch.

Template:

```
https://github.com/gastownhall/gascity/compare/main...zookanalytics:<branch>?expand=1&title=<urlencoded>&body=<urlencoded>
```

URL-encode title and body via `jq -sRr @uri`. PR bodies tend to land
under 4KB — comfortably below GitHub's URL limit.

The PR body must fit gascity's PR template
(`.github/pull_request_template.md` on `upstream/main`): Summary →
Testing checklist → Checklist (linked issue, tests, docs, breaking
changes). Adapt the commit body into that structure before locking
the URL in.

## When you are asked "what's left on this bead?"

Upstream PR work is **not** a valid answer. The right answer ends at
"local fix shipped, commit carries review packet; operator reviews
for upstream submission at their discretion."
