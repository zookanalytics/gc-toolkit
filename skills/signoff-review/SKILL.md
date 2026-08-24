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

This prohibition is the point of the skill, not a performance note. If
you find yourself reaching for a subagent, stop — the answer is to read
the code.

## 1. Pin what you are reviewing

```bash
BEAD=<work-bead>          # the review bead you claimed
M=$(gc bd show "$BEAD" --json | jq -c '.[0].metadata')
BRANCH=$(printf '%s' "$M" | jq -r '.review_branch // empty')
BASE=$(printf   '%s' "$M" | jq -r '.review_base   // empty')
PR=$(printf     '%s' "$M" | jq -r '.pr_number     // empty')
PR_URL=$(printf '%s' "$M" | jq -r '.pr_url        // empty')
```

Two shapes, discriminated by which of those is set:

- **PRE-OPEN** (`review_branch`, no `pr_number`) — no PR exists yet.
  Your verdict decides whether it opens at all.
- **POST-OPEN** (`pr_number`) — the PR is published and held on your
  signoff.

Either way, pin the exact commit before you read anything:

```bash
if [ -n "$PR" ]; then
  # POST-OPEN: the PR is authoritative for both ends of the range — but a
  # number names a pull request only inside one repository on one host, so
  # pin both from the bead's own pr_url before asking gh anything.
  PR_REPO_Q=$(printf '%s' "$PR_URL" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p')
  [ -n "$PR_REPO_Q" ] || { echo "post-open review bead has no parseable pr_url: refusing to resolve PR#$PR from ambient gh context" >&2; exit 1; }
  PR_HOST="${PR_REPO_Q%%/*}"   # <host>         — for gh api --hostname
  PR_REPO="${PR_REPO_Q#*/}"    # <owner>/<repo> — for gh api REST paths

  BRANCH=$(gh pr view "$PR" --repo "$PR_REPO_Q" --json headRefName -q .headRefName)
  BASE=$(gh pr view "$PR" --repo "$PR_REPO_Q" --json baseRefName -q .baseRefName)
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

Carry all three forms of that pin for the rest of the review:
`--repo "$PR_REPO_Q"` on every `gh pr` call, and `--hostname "$PR_HOST"`
plus an explicit `repos/$PR_REPO/...` path on every `gh api` call.
`PR_REPO_Q` is host-qualified (`<host>/<owner>/<repo>`) because that is
what `--repo` wants — a hostless pin gets completed from `$GH_HOST` and
can name a different host's identically-named repository. A REST path
carries `<owner>/<repo>` and no host, so `--hostname` is what pins the
other half.

A bare number is resolved from whatever repository gh infers — your
worktree's remote, `$GH_REPO`, `$GH_HOST` — and the bead you are holding
was dispatched by a pass that may have been nowhere near this checkout.
Every repository has a pull request with the number you were handed. Get
this wrong and you read one PR's diff,
post the verdict on a stranger's PR of the same number, and hand the done
sequence an OID that was never this PR's head — the anchor gets stamped
from a verdict about the wrong object while the PR you were meant to gate
stays ungated. So it fails closed: an unparseable `pr_url` on a post-open
bead is a malformed bead, and refusing costs one re-dispatch, while
guessing costs a review posted on someone else's work.

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

### Documents-only branches are reviewed as designs, not as code

Everything from §3 down is calibrated for code. Before applying it, check
whether this branch contains any code at all:

```bash
# >>> review-mode-classify
# Executed verbatim as a regression by assets/scripts/review-dispatch-body.test.sh.
# Keep it self-contained: the test extracts these lines between the markers and
# runs them against a fake `git`, so it cannot drift from what you are told here.
FILES=$(git diff --name-only "origin/$BASE...$REVIEWED_OID")
if [ -z "$FILES" ]; then
  echo "empty diff at $REVIEWED_OID: nothing to review" >&2; exit 1
elif printf '%s\n' "$FILES" | grep -qvE '^(specs|docs)/.*\.md$'; then
  MODE=code
else
  MODE=design
fi
# <<< review-mode-classify
```

`MODE=design` means every changed path is Markdown under `specs/` or
`docs/`: the deliverable is a document and there is nothing executable on
the branch. One script, one config, one fixture alongside it makes it
`MODE=code` and the rest of this skill applies unchanged. The test reads
as "is any path *not* a document", so it fails toward `code`, the
stricter mode.

A code diff has a bounded review surface: does this code do what it
claims. A design document has no such bound. A reviewer reading a
700-line concurrency design can always find one more reachable
interleaving, one more platform fact the design did not anticipate — and
each one, graded on the §5 scale, is "wrong behavior on a reachable
input", which is a P1, which blocks. That loop has no terminus.
signal-loom's `sl-kg9z6.1.1` ran **seven** rounds on a branch of one file
and zero code. Every round found something genuinely new and real; the
implementation bead it blocked sat idle 33 hours.

So under `MODE=design`, two things change.

**What still blocks** (P0/P1 → REQUEST_CHANGES) — defects that live in
the document and can only be fixed in the document:

- **Self-contradiction.** Two rules it states cannot both hold.
- **A false claim about what exists.** It describes current behavior, an
  API, a schema, or a constraint that the repo does not have. Cite the
  code you checked.
- **A missing decision.** The question the document exists to settle is
  not settled — an enumerated case with no stated outcome, a named
  invariant with no mechanism.

**What does not block** — record it, do not gate on it:

- **An implementation discovery.** A fact about the runtime, library, or
  platform that the design did not anticipate and that an implementer
  meets in the first afternoon and settles with a test: *"scheduled
  actions run at most once"*, *"cancel cannot stop a job that already
  started"*, *"that predicate needs an index"*. True, worth writing
  down, and not resolvable in prose — a document has no compiler and no
  test to adjudicate it.
- **One more interleaving, ordering, or edge case** the design does not
  enumerate. A design's enumeration is never complete. If the missing
  case changes the design's *shape*, it is a missing decision above; if
  it is one more instance of a hazard the design already names and
  handles, it is this.

Grade those **P2** and put them on **the implementation bead** rather
than into a rework of the document — that is where an implementer will
meet them and where a test can settle them:

```bash
ANCHOR=$(printf '%s' "$M" | jq -r '.anchor_bead // empty')
IMPL=$(gc bd dep list "$ANCHOR" --direction=up -t blocks --json \
  | jq -r '[.[].id] | if length == 1 then .[0] else empty end')
```

The implementation bead is the one the design anchor **blocks**, so
`--direction=up -t blocks` — which excludes the rework children
(`parent-child`) and the convoy trackers (`tracks`) that also point at
the anchor. If exactly one bead resolves, append the finding to it with
`--append-notes` and say in your verdict that you did. If none or several
resolve, leave the finding in the verdict body under a
`CARRY TO IMPLEMENTATION:` heading and name the ambiguity — a finding
parked in a verdict is recoverable, one appended to the wrong bead is
not.

This is a rule about a finding's **class, not its round number**: it
applies on round 1, and needs no round counting. It is deliberately not
"a lower convergence cap for design branches" — the cap's terminal action
is to stop dispatching and route to a human, so capping a design branch
sooner spends operator attention *earlier* instead of saving it. That is
the observed failure: on `sl-kg9z6.1.1` the cap fired at round 3 and the
remaining four rounds ran on hand-authorized re-gates.

## 3. Run the tests at the pinned commit

Your session already has a gascity-managed worktree, but it is on some
other checkout — not the commit under review. Pin `REVIEWED_OID` in a
throwaway detached worktree so the tests run against exactly what you
reviewed, disturbing nothing else:

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

Under `MODE=design` there is no suite: the branch ships no executable
code, so there is nothing for a test run to tell you. Do not invent one,
and do not run the repo's full suite to have a number to report — it
exercises the base, not the branch. Run what actually applies to prose —
a formatter check, `git diff --check` — and say plainly in the
Verification line that no unit suite ran *because the branch changes only
documents*. An honest "not applicable, and here is why" is worth more
than a green count from a suite the diff never touched.

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

Under `MODE=design` (§2), **Contract**, **Testing** and **Readiness** have
nothing to bind to — there is no caller, no suite, and no migration. What
carries over is **Intent** (does the document settle what the anchor asked
it to settle) and a prose form of **Correctness**: is it consistent with
itself, and true about the code it describes.

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

On a documents-only branch (`MODE=design`, §2) apply the design grading
*before* this scale. Several findings that are P1 by the wording above —
a reachable interleaving, an unhandled ordering hazard — are P2
implementation notes there, because the document is not where they get
resolved. The blocking set shrinks to the three defect classes §2 lists;
it does not become empty.

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
HEAD_NOW=$(gh pr view "$PR" --repo "$PR_REPO_Q" --json headRefOid -q .headRefOid)
if [ "$HEAD_NOW" != "$REVIEWED_OID" ]; then
  echo "head moved $REVIEWED_OID -> $HEAD_NOW: post nothing, stamp nothing" >&2
  exit 1
fi

gh pr review "$PR" --repo "$PR_REPO_Q" --comment         --body "$VERDICT_BODY"   # pass
gh pr review "$PR" --repo "$PR_REPO_Q" --request-changes --body "$VERDICT_BODY"   # changes
```

A moved head is not a finding and not a failure — it is a different
commit. Re-pin `REVIEWED_OID` at the new head, redo steps 2–6, and post
against that. What you must not do is post the verdict you already have.

The window between that check and the submission is narrow, not zero, so
confirm where the review actually landed — GitHub records it on the
review itself:

```bash
ME=$(gh api --hostname "$PR_HOST" user -q .login)
gh api --hostname "$PR_HOST" --paginate \
    "repos/$PR_REPO/pulls/$PR/reviews?per_page=100" --jq '.[]' \
  | jq -rs --arg me "$ME" \
      '[.[] | select(.user.login == $me)] | sort_by(.submitted_at) | last | .commit_id'
```

Both calls are pinned for the same reason the rest are: an account name is
host-scoped, so an unpinned `gh api user` under a drifted `$GH_HOST` names
an account that never wrote any of these reviews, and the filter then
matches nothing. Paginate, too — GitHub pages this endpoint, and a PR that
has taken a few rounds is exactly the one whose newest review sits past the
first page, so an unpaginated read `last`s an *older* review of yours and
reports a mismatch that never happened.

If that is not `REVIEWED_OID`, your verdict attached to a commit you did
not read. Say so, and re-review at the new head — do not hand that OID
on as though you had reviewed it.

**PRE-OPEN — nothing to post.** There is no PR. Record the verdict in
the review bead's notes, and stamp the commit you pinned:

```bash
gc bd update "$BEAD" --set-metadata reviewed_oid="$REVIEWED_OID" \
  --append-notes "$VERDICT_BODY"
```

`--append-notes`, never `--notes`, which replaces. This field has a
second writer: when the done sequence cannot record the gate marker it
appends the "gate unrecorded" diagnostic to these same notes and
re-offers this same bead, so a replacing write on the retry erases the
only record of why the previous round failed.

The refinery replays those notes verbatim when it opens the PR, so write
a **self-contained** verdict — one that reads correctly as an opening PR
comment, not as a diff against the entry above it.

Everything past this point — which marker lands on the anchor, how a
rework child is filed, when the review bead closes — belongs to the
**non-impl done sequence** in your prompt. That is its source of truth;
this skill does not restate it. Follow it exactly, and hand it the OID
you pinned.
