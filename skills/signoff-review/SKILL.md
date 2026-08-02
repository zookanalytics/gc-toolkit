---
name: signoff-review
description: Use when you hold a dispatched review bead — metadata.task_kind=review carrying review_branch (pre-open) or pr_number (post-open) — and owe it a signoff verdict that a check-set gate consumes. Not for checking over your own work before handing it to the refinery, not for general code reading, and not for any task without a review bead.
---

# Signoff Review

The method for a dispatched signoff review. One reviewer — you — pins a
commit, reads its diff, runs its tests, and records a verdict the gate
consumes.

> **Only with a review bead in hand.** This is the method for a
> *dispatched* signoff: a bead whose `metadata.task_kind` is `review`,
> carrying `review_branch` or `pr_number`. Checking over your own work
> before handoff is your formula's self-review step, not this. The
> matching engine may surface this skill on near-matches; this guardrail
> is the second line of defense.

Reviewing is a property of the **step**, not of the agent. Any polecat
may be handed a review, under any provider. Nothing here assumes which
one you are.

## One agent. No fan-out.

**You are the reviewer.** Read the diff yourself, run the tests
yourself, write the verdict yourself.

Do **not** spawn subagents, persona reviewers ("security reviewer",
"architecture reviewer", …), or any parallel review pass. Do not
delegate the diff read or the test run to anything.

This prohibition is the point of the skill, not a performance note. The
fan-out it replaces ran ~4.9 subagents and ~4.7M tokens per review and
produced no better verdict than the single-pass reviews alongside it. If
you find yourself reaching for a subagent, stop — the answer is to read
the code.

## 1. Pin what you are reviewing

```bash
BEAD=<work-bead>          # the review bead you claimed
M=$(gc bd show "$BEAD" --json | jq -c '.[0].metadata')
BRANCH=$(printf '%s' "$M" | jq -r '.review_branch // empty')
BASE=$(printf   '%s' "$M" | jq -r '.review_base   // empty')
PR=$(printf     '%s' "$M" | jq -r '.pr_number     // empty')
```

Two shapes, discriminated by which of those is set:

- **PRE-OPEN** (`review_branch`, no `pr_number`) — no PR exists yet.
  Your verdict decides whether it opens at all.
- **POST-OPEN** (`pr_number`) — the PR is published and held on your
  signoff.

Either way, pin the exact commit before you read anything:

```bash
if [ -n "$PR" ]; then
  # POST-OPEN: the PR is authoritative for both ends of the range.
  BRANCH=$(gh pr view "$PR" --json headRefName -q .headRefName)
  BASE=$(gh pr view "$PR" --json baseRefName -q .baseRefName)
elif [ -z "$BASE" ]; then
  # PRE-OPEN, no review_base — a malformed or older review bead. Resolve
  # the anchor's landing target; do not assume main.
  ANCHOR=$(printf '%s' "$M" | jq -r '.anchor_bead // empty')
  [ -n "$ANCHOR" ] && BASE=$(gc bd show "$ANCHOR" --json | jq -r '.[0].metadata.target // empty')
  [ -n "$BASE" ] || { echo "no review_base, no anchor target: refusing to guess a base" >&2; exit 1; }
fi

git fetch origin "$BASE" "$BRANCH"
REVIEWED_OID=$(git rev-parse "origin/$BRANCH")
```

Never fall back to `main`. A convoy child lands on
`integration/<convoy-id>`, and diffing it against `main` shows you
every commit the integration branch already carries — a diff the branch
never made, reviewed as if it had. If neither `review_base` nor the
anchor's `target` resolves, the bead is malformed: escalate it rather
than pick a base for it.

The diff you read, the tests you run, and the OID you stamp are all that
one commit. The head can advance while you review; a verdict recorded
against a head you never read certifies unreviewed code.

## 2. Read the diff

```bash
git diff --stat "origin/$BASE...$REVIEWED_OID"
git diff       "origin/$BASE...$REVIEWED_OID"
```

Three dots — compare against the merge-base, so you review what the
branch changed rather than what the base moved on underneath it.

Read the whole diff. A large one gets read in chunks, not sampled, and
the chunks are still yours.

Read the intent too: the anchor bead (`metadata.anchor_bead`), the PR or
branch description, and any refinery context note on the review bead —
which round this is and what earlier rounds found tells you where to
look hardest.

## 3. Run the tests at the pinned commit

Use a detached worktree, so you disturb no checkout of your own and
never fight a branch checked out elsewhere:

```bash
REVIEW_WT=$(mktemp -d "/tmp/gc-review-$BEAD.XXXXXX")
git worktree add "$REVIEW_WT" --detach "$REVIEWED_OID"
cd "$REVIEW_WT"
```

Run the suites the diff touches — the changed files' own tests, plus
whatever exercises the changed code path. Record actual pass/fail
counts; they go in the verdict.

```bash
cd - >/dev/null && git worktree remove --force "$REVIEW_WT"
```

A failing suite is not automatically a finding: check whether it fails
on the base too. A pre-existing failure belongs in the verdict as
context, not as this branch's defect.

## 4. What to check

- **Intent** — does it do what the anchor bead asked? Deviations are
  fine when they are better; flag them either way so the author can
  confirm they were meant.
- **Correctness** — bugs, reachable edge cases, error handling, the
  failure mode nobody wrote a test for.
- **Contract** — does it break a caller, a stored format, a metadata
  key, or a script that greps for the old shape? Go find the *other*
  call sites of anything it changed. The recurring defect class here is
  a predicate fixed in one copy and left stale in two.
- **Testing** — do the tests exercise real behavior, is the new path
  covered, does a regression pin the bug that was fixed?
- **Readiness** — back-compat and migration, fail-closed where
  fail-closed was intended, docs that the change just made false.

## 5. Calibrate severity

- **P0** — broken or unsafe as merged: data loss, a merge that bypasses
  a gate, a crash on the normal path.
- **P1** — a real defect that will bite: wrong behavior on a reachable
  input, a fail-open where fail-closed was intended, an unhandled
  identity or ordering hazard.
- **P2** — worth fixing, not worth blocking: a narrow hazard, a test
  gap, a clarity problem.

Grade honestly. Not everything is P0. A P2 inflated to P1 costs a whole
rework round; a P1 discounted to P2 merges the bug. When you can't tell
whether something is reachable, say what you checked and grade on what
you know.

Every finding carries **file:line**, what is wrong, why it matters, and
what would fix it. A finding without a location isn't actionable, and
"improve error handling" isn't a finding.

## 6. Decide the verdict

Exactly one:

- **COMMENT** — no P0 and no P1. The signoff passes; remaining P2s ride
  along as non-blocking notes.
- **REQUEST_CHANGES** — at least one P0 or P1, each with its required
  fix.

COMMENT *is* the pass. It is never an approval — the city does not
approve PRs; approval is external and human. Never run
`gh pr review --approve`.

Record it in this shape, as `VERDICT_BODY`. Keep the bare word in
`VERDICT` (`COMMENT` or `REQUEST_CHANGES`) as well — the done sequence
switches on that word, and the body is what gets posted or noted.

```
VERDICT: <COMMENT|REQUEST_CHANGES>
Reviewed branch: <branch>
Reviewed base:   <base>
Reviewed commit: <REVIEWED_OID>

Scope checked: <what you actually read>

Findings: <P0/P1/P2 — each with file:line, impact, and the fix>

Verification: <suite -> N passed, M failed, run at the reviewed commit>
```

Say what you did **not** check. An honest coverage line is worth more
than an implied "I read everything".

## 7. Hand the verdict off

Two things are yours: the **verdict**, and the **`REVIEWED_OID` you
pinned in step 1**. Never approve, and never re-derive the head.

**POST-OPEN — re-check the head before you post.** GitHub attaches a
review to whatever head is live when you submit it, and the done
sequence stamps the gate at that attached commit. If the head advanced
while you were reading, posting now certifies a commit you never read:

```bash
HEAD_NOW=$(gh pr view "$PR" --json headRefOid -q .headRefOid)
if [ "$HEAD_NOW" != "$REVIEWED_OID" ]; then
  echo "head moved $REVIEWED_OID -> $HEAD_NOW: post nothing, stamp nothing" >&2
  exit 1
fi

gh pr review "$PR" --comment         --body "$VERDICT_BODY"   # pass
gh pr review "$PR" --request-changes --body "$VERDICT_BODY"   # changes
```

A moved head is not a finding and not a failure — it is a different
commit. Re-pin `REVIEWED_OID` at the new head, redo steps 2–6, and post
against that. What you must not do is post the verdict you already have.

The window between that check and the submission is narrow, not zero, so
confirm where the review actually landed — GitHub records it on the
review itself:

```bash
ME=$(gh api user -q .login)
gh api "repos/{owner}/{repo}/pulls/$PR/reviews" \
  | jq -r --arg me "$ME" \
      '[.[] | select(.user.login == $me)] | sort_by(.submitted_at) | last | .commit_id'
```

If that is not `REVIEWED_OID`, your verdict attached to a commit you did
not read. Say so, and re-review at the new head — do not hand that OID
on as though you had reviewed it.

**PRE-OPEN — nothing to post.** There is no PR. Record the verdict in
the review bead's notes, and stamp the commit you pinned:

```bash
gc bd update "$BEAD" --set-metadata reviewed_oid="$REVIEWED_OID" \
  --notes "$VERDICT_BODY"
```

The refinery replays those notes when it opens the PR.

Everything past this point — which marker lands on the anchor, how a
rework child is filed, when the review bead closes — belongs to the
**non-impl done sequence** in your prompt. That is its source of truth;
this skill does not restate it. Follow it exactly, and hand it the OID
you pinned.
