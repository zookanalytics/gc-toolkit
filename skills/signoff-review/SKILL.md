---
name: signoff-review
description: Use when you hold a dispatched review bead — metadata.task_kind=review carrying review_branch (pre-open) or pr_number (post-open) — and owe it a signoff verdict that a check-set gate consumes. Not for checking over your own work before handing it to the refinery, not for general code reading, and not for any task without a review bead.
---

# Signoff Review

The method for a dispatched signoff review. One reviewer — you — pins a
commit, reads its diff, runs its tests, and hands one verdict to
`signoff.sh`, the single writer of gate verdicts.

> **Only with a review bead in hand.** This is the method for a
> *dispatched* signoff: a bead whose `metadata.task_kind` is `review`,
> carrying `review_branch` or `pr_number`. Checking over your own work
> before handoff is your formula's self-review step, not this.

Reviewing is a property of the **step**, not of the agent. Nothing here
assumes which agent you are.

## One agent. No fan-out.

**You are the reviewer.** Read the diff yourself, run the tests yourself,
write the verdict yourself. Do **not** spawn subagents, persona reviewers,
or any parallel review pass. This prohibition is the point of the skill: if
you find yourself reaching for a subagent, stop — the answer is to read the
code.

## 1. Pin what you are reviewing

```bash
BEAD=<work-bead>          # the review bead you claimed
M=$(gc bd show "$BEAD" --json | jq -c '.[0].metadata')
BRANCH=$(printf '%s' "$M" | jq -r '.review_branch // empty')
BASE=$(printf   '%s' "$M" | jq -r '.review_base   // empty')
PR=$(printf     '%s' "$M" | jq -r '.pr_number     // empty')
PR_URL=$(printf '%s' "$M" | jq -r '.pr_url        // empty')
```

Two shapes, discriminated by which of those is set: **PRE-OPEN**
(`review_branch`, no `pr_number` — your verdict decides whether the PR
opens at all) and **POST-OPEN** (`pr_number` — the PR is published and held
on your signoff). Either way, pin the exact commit before you read
anything:

```bash
if [ -n "$PR" ]; then
  # POST-OPEN: a number names a PR only inside one repository on one host,
  # so pin both from the bead's own pr_url before asking gh anything.
  PR_REPO_Q=$(printf '%s' "$PR_URL" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p')
  [ -n "$PR_REPO_Q" ] || { echo "post-open review bead has no parseable pr_url: refusing to resolve PR#$PR from ambient gh context" >&2; exit 1; }
  PR_HOST="${PR_REPO_Q%%/*}"   # <host>         — for gh api --hostname
  PR_REPO="${PR_REPO_Q#*/}"    # <owner>/<repo> — for gh api REST paths

  BRANCH=$(gh pr view "$PR" --repo "$PR_REPO_Q" --json headRefName -q .headRefName)
  BASE=$(gh pr view "$PR" --repo "$PR_REPO_Q" --json baseRefName -q .baseRefName)
elif [ -z "$BASE" ]; then
  # PRE-OPEN, no review_base — resolve the anchor's landing target; never
  # assume main.
  ANCHOR=$(printf '%s' "$M" | jq -r '.anchor_bead // empty')
  [ -n "$ANCHOR" ] && BASE=$(gc bd show "$ANCHOR" --json | jq -r '.[0].metadata.target // empty')
  [ -n "$BASE" ] || { echo "no review_base, no anchor target: refusing to guess a base" >&2; exit 1; }
fi

git fetch origin "$BASE" "$BRANCH"
REVIEWED_OID=$(git rev-parse "origin/$BRANCH")
```

Carry the pin on every call: `--repo "$PR_REPO_Q"` for `gh pr`,
`--hostname "$PR_HOST"` plus explicit `repos/$PR_REPO/...` paths for
`gh api`. A bare number resolves from ambient gh context (worktree remote,
`$GH_REPO`, `$GH_HOST`), and every repository has a PR with the number you
were handed — an unpinned read reviews one PR and gates another. Fail
closed: an unparseable `pr_url` on a post-open bead is a malformed bead;
refusing costs one re-dispatch, guessing posts a review on someone else's
work.

**Never fall back to `main`.** A convoy child lands on
`integration/<convoy-id>`; diffing it against `main` reviews a diff the
branch never made. If neither `review_base` nor the anchor's `target`
resolves, the bead is malformed — escalate it, don't pick a base for it.

The diff you read, the tests you run, and the OID you hand off are all
that one commit. A verdict recorded against a head you never read
certifies unreviewed code.

## 2. Read the diff

```bash
git diff --stat "origin/$BASE...$REVIEWED_OID"
git diff       "origin/$BASE...$REVIEWED_OID"
```

Three dots — compare against the merge-base, so you review what the branch
changed rather than what the base moved on underneath it. Read the whole
diff; a large one gets read in chunks, not sampled. Read the intent too:
the anchor bead (`metadata.anchor_bead`), the PR or branch description, and
any context note on the review bead — which round this is and what earlier
rounds found tells you where to look hardest.

## 3. Run the tests at the pinned commit

Pin `REVIEWED_OID` in a throwaway detached worktree so the tests run
against exactly what you reviewed:

```bash
REVIEW_WT=$(mktemp -d "/tmp/gc-review-$BEAD.XXXXXX")
git worktree add "$REVIEW_WT" --detach "$REVIEWED_OID"
cd "$REVIEW_WT"
```

Run the suites the diff touches — the changed files' own tests plus
whatever exercises the changed code path. Record actual pass/fail counts;
they go in the verdict.

```bash
cd - >/dev/null && git worktree remove --force "$REVIEW_WT"
```

A failing suite is not automatically a finding: check whether it fails on
the base too. A pre-existing failure belongs in the verdict as context, not
as this branch's defect.

## 4. What to check

- **Intent** — does it do what the anchor bead asked? Deviations are fine
  when they are better; flag them either way.
- **Correctness** — bugs, reachable edge cases, error handling, the
  failure mode nobody wrote a test for.
- **Contract** — does it break a caller, a stored format, a metadata key,
  or a script that greps for the old shape? Find the *other* call sites of
  anything it changed; the recurring defect class is a predicate fixed in
  one copy and left stale in two.
- **Testing** — do the tests exercise real behavior, is the new path
  covered, does a regression pin the bug that was fixed?
- **Readiness** — back-compat and migration, fail-closed where fail-closed
  was intended, docs the change just made false.

## 5. Calibrate severity

- **P0** — broken or unsafe as merged: data loss, a merge that bypasses a
  gate, a crash on the normal path.
- **P1** — a real defect that will bite: wrong behavior on a reachable
  input, a fail-open where fail-closed was intended.
- **P2** — worth fixing, not worth blocking: a narrow hazard, a test gap,
  a clarity problem.

Grade honestly. A P2 inflated to P1 costs a whole rework round; a P1
discounted to P2 merges the bug. When you can't tell whether something is
reachable, say what you checked and grade on what you know.

Every finding carries **file:line**, what is wrong, why it matters, and
what would fix it. A finding without a location isn't actionable, and
"improve error handling" isn't a finding.

## 6. Decide the verdict

Exactly one:

- **approve** — no P0 and no P1. The signoff passes; remaining P2s ride
  along as non-blocking notes. This is never a GitHub approval — the city
  does not approve PRs; approval is external and human.
- **request-changes** — at least one P0 or P1, each with its required fix.

Write the verdict body in this shape:

```
VERDICT: <approve|request-changes>
Reviewed branch: <branch>
Reviewed base:   <base>
Reviewed commit: <REVIEWED_OID>

Scope checked: <what you actually read>

Findings: <P0/P1/P2 — each with file:line, impact, and the fix>

Verification: <suite -> N passed, M failed, run at the reviewed commit>
```

Say what you did **not** check — an honest coverage line is worth more
than an implied "I read everything". Write it **self-contained**: pre-open,
it is replayed verbatim as the opening PR comment.

## 7. Hand the verdict off — one call

`signoff.sh` owns every mechanic past your judgment: posting the artifact
(`gh pr review --comment` post-open; bead notes with `reviewed_oid`
pre-open), stamping `check.<g>=green@<oid>` with read-back, filing and
slinging one rework child on request-changes, enforcing the round cap, and
refusing a head that moved past your pin. Run it exactly once:

```bash
"$PACK_DIR/assets/scripts/signoff.sh" \
  --review-bead "$BEAD" \
  --verdict <approve|request-changes> \
  --reviewed-oid "$REVIEWED_OID" \
  --body "$VERDICT_BODY"
```

Do not post the review yourself, do not touch `check.*`, and never run
`gh pr review --approve`. If `signoff.sh` reports the head moved, that is
not a failure — it is a different commit: re-pin at the new head, redo
steps 2–6, and call it again with the new OID. What you must not do is
hand it the verdict you already have.
