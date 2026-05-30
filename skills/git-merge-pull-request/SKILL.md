---
id: git-merge-pull-request
name: git-merge-pull-request
description: Use when merging a pull request. LLM-validated squash merge — re-checks the title and description against the FINAL diff, confirms review + approval + CI on the exact head being merged, then squash-merges. The merge actor is the LLM, and correctness is validated immediately before the merge.
---

# Merge Pull Request (LLM merge gate)

**You, an LLM, perform the merge — and you validate that the PR is _in fact
correct_ on the exact head you are about to merge, before merging.** This is
not a `gh pr merge` wrapper and it is not GitHub auto-merge. GitHub owns "did a
human approve and is CI green"; **this gate owns "does the title and
description still describe what actually shipped."**

A PR can cycle `ready → draft → ready` many times, and an approval or a review
can predate the final head. So **every check below is evaluated against the
current head SHA** — never a cached or earlier state. That late binding is the
whole point: it closes the gap where a PR is approved, then changes, and the
stale description merges with nobody noticing.

## Determine the PR

**If a PR number was given:** use it.

**Otherwise, derive from the current branch:**

```bash
git branch --show-current
gh pr list --head <branch-name> --json number --jq '.[0].number'
```

- Not found → "No PR found for branch `<branch-name>`."
- Multiple → list them and ask which.

## Pin the head

Capture the head SHA once. Everything validates against **this** SHA. If the
head moves while you work, start over against the new head.

```bash
gh pr view <number> --json \
  number,title,body,headRefName,headRefOid,baseRefName,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,reviews
# HEAD_SHA := .headRefOid
```

## Pre-merge validation — fail closed

Any check you cannot positively confirm **blocks the merge**. Never merge
optimistically; never push code to make a check pass.

### 1. Mergeable and on-target

- **Not draft.** A draft PR means the codex review gate hasn't released it — block.
- **`mergeable == MERGEABLE`.** If `UNKNOWN`, GitHub is still computing — re-poll
  up to 3 times, 5s apart. Still `UNKNOWN` → stop, tell the user to retry shortly.
  `CONFLICTING` → stop, the branch needs rebase/conflict resolution.
- **Base is the intended branch.** Usually `main`. A `integration/*` base is a
  convoy-internal merge — see the integration-branch note at the end.

### 2. CI green on HEAD_SHA

`statusCheckRollup` mixes two node types that report their result in
**different fields** — conflating them is exactly how a failed run slips
through this last gate:

- **`CheckRun`** (GitHub Actions / Checks API) — the pass/fail lives in
  `conclusion`, **not** `status`. `status == COMPLETED` only means the run
  reached a terminal state; a `FAILURE`, `CANCELLED`, `TIMED_OUT`,
  `ACTION_REQUIRED`, or `STARTUP_FAILURE` run is *also* `COMPLETED`. Green
  requires `conclusion == SUCCESS` (or a legitimate `SKIPPED` — a
  conditional/platform workflow that didn't apply). **Any completed run whose
  `conclusion` is not `SUCCESS`/`SKIPPED` blocks.** While a run is still going
  `conclusion` is `null` — not green, so it blocks too.
- **`StatusContext`** (legacy commit-status API) — the result lives in `state`.
  Green requires `state == SUCCESS`. `FAILURE`/`ERROR` block; `PENDING`/`EXPECTED`
  hasn't passed yet, so it blocks until it does.

You must positively confirm every check is green; anything you can't confirm
blocks (fail closed). The gate is clear only when this lists nothing:

```bash
gh pr view <number> --json statusCheckRollup --jq '
  .statusCheckRollup[]
  | select(
      (.__typename == "CheckRun"      and .conclusion != "SUCCESS" and .conclusion != "SKIPPED")
      or
      (.__typename == "StatusContext" and .state != "SUCCESS")
    )
  | {name: (.name // .context), type: .__typename, status, conclusion, state}'
```

A flaky check may be re-run; a genuine failure means STOP and inform the user.

### 3. Approval is on HEAD_SHA  *(Gas City checks this itself)*

The repo ruleset does **not** dismiss stale approvals on push, so an approval
can sit on an older commit. Confirm:

- `reviewDecision == APPROVED`, **and**
- the latest `APPROVED` review's `commit` equals `HEAD_SHA`.

If the approval is on an older commit → **block**: "Approval is stale (approved
`<sha>`, head is `<HEAD_SHA>`) — re-approve the final head." This is the
"approved before the final head" case, and GitHub will not catch it here.

### 4. Codex review resolved on HEAD_SHA  *(Gas City review gate)*

The refinery opens `mr`-mode PRs as a draft and dispatches a codex review bead
(`task_kind=review`, `pr_number=<n>`) to the codex polecat pool. The reviewer
posts its verdict as a GitHub PR review and then **closes its own bead.** That
last fact is the trap: a query for `open`/`in_progress` review beads returns
empty in three states you must not conflate — reviewed on this head, reviewed on
an *older* head (stale), and never reviewed at all. An empty bead list is the
default, **not** evidence of a current review. The durable record of *which
commit was reviewed* is the GitHub review's `commit_id`; bind the gate to that,
never to bead status alone.

Confirm both:

**No review is still pending** — a bead mid-flight hasn't posted its verdict:

```bash
gc bd list --metadata-field task_kind=review --metadata-field pr_number=<number> \
  --status=open,in_progress --json
```

Any result → **block**: "Codex review still pending."

**A codex review resolved on HEAD_SHA** — positively confirm the verdict landed
on *this* head. The review beads record the `review_id` of the GitHub review
they posted; read those (include `closed` — the reviewer closes the bead after
posting), then read the PR's reviews with the commit each was submitted against:

```bash
# review_ids the codex reviewer recorded — the durable bead -> GitHub-review
# link, across every review round for this PR:
gc bd list --metadata-field task_kind=review --metadata-field pr_number=<number> \
  --status=open,in_progress,closed --json | jq '[.[].metadata.review_id // empty]'

# every review on the PR, with the commit it was submitted against:
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
gh api "repos/$REPO/pulls/<number>/reviews" \
  --jq '.[] | {id, user: .user.login, state, commit_id}'
```

A recorded codex `review_id` must appear with `commit_id == HEAD_SHA`. If **no**
codex review resolves on HEAD_SHA — none was ever dispatched, or every one sits
on an earlier commit (commits landed after the last review) — **block**: "No
current-head codex review (head `<HEAD_SHA>`) — re-dispatch the codex review for
the final head and wait." Fail closed: if the ledger recorded no `review_id`
(older reviews predate that field), fall back to requiring at least one PR
review submitted against HEAD_SHA **and** a dispatched review bead for this PR;
absent either, block. Never infer a current review from an empty bead list.

Codex review is a **requirement, not a ship decision** — it is a precondition
here, never the authorization. The human approval (step 3) is the authorization.

### 5. Title and description are TRUE on the final diff  *(the LLM judgment)*

This is the check GitHub structurally cannot do. Read what actually shipped:

```bash
gh pr diff <number>
git log origin/<baseRefName>..origin/<headRefName> --oneline
```

**Title** — conventional-commits, and an accurate one-line summary of the
change. It becomes the squash commit subject.
- Types: `build chore docs feat fix ops perf refactor revert security style test`
- Scope optional (`app`, `ci`, `deps`, …)
- Subject starts lowercase, ≤ 100 chars
- Shape: `type(scope)!: subject`

**Description** — must be 100% accurate to the final diff. Block-worthy drift:
- a feature the body says was added but was removed/changed
- an approach described that the code doesn't take
- a safeguard claimed but absent
- code snippets that no longer match
- required sections missing

**On drift: fix and merge** (safe — you are only making the wording match what
was already approved to ship; you are not changing what ships):

```bash
gh pr edit <number> --title "<corrected conventional-commit title>"
gh pr edit <number> --body "$(cat <<'EOF'
## Summary
<corrected — accurate to the final diff>

## Test plan
<verification steps>
EOF
)"
```

Re-read the corrected title/body, confirm they're accurate, then merge. Do
**not** bounce for re-approval — correcting wording to match the diff is a
mechanical accuracy fix, not a change to the shipped code.

## Merge — squash only

The repo ruleset permits squash merges only.

```bash
gh pr merge <number> --squash --delete-branch
```

The validated title/body are the squash commit message.

## If the merge fails

```bash
gh pr view <number> --json mergeable,mergeStateStatus
```

- `CONFLICTING` → needs rebase/resolution; user decides approach, then return to "Pin the head."
- Branch-protection/ruleset violation → re-check steps 2–4 (a required check or approval regressed).
- Permissions → inform the user.

Do **not** resolve merge failures by force or by pushing code without re-review.

## Post-merge

```bash
gh pr view <number> --json state,mergedAt   # confirm merged
```

Then, in Gas City terms:

- The refinery already closed the **work bead** at "PR ready." If it's still
  open, annotate it merged; close the **review bead** for this PR if open.
- If the base was `integration/<convoy>` and this was the graduation PR
  (`integration/* → main`), finalize the convoy: `gc convoy land <convoy-id>`.
- If you are running from a local checkout, sync it:

```bash
git checkout <baseRefName> && git pull && git fetch --prune
```

## Integration-branch note

A PR whose base is `integration/<convoy>` is a child → integration merge that
the refinery handles normally — proceed. The high-value gate is the
**graduation PR** (`integration/* → main`): its title and description become
`main`'s permanent history, so that is the one whose wording must be
re-validated against the full integration diff before it lands.

## Process violations (never do these)

- Merge PR changes by hand with `git merge`/cherry-pick to the base
- Copy code out of a PR without closing the PR
- Merge with an outdated description
- Push code to make CI pass without re-review
- Skip branch cleanup after merge

## Common rationalizations (stop)

| Thought | Reality |
| --- | --- |
| "The title is what matters" | The description is permanent history. Both must be true. |
| "The description can be fixed later" | It can't be edited after merge. Fix it now (and you can — fix-and-merge). |
| "It was approved, so it's fine" | Approval may predate the final head. Re-check on HEAD_SHA. |
| "Codex passed, ship it" | Codex is a precondition, not the ship decision. Approval on the head is. |
| "No open review bead, so it's been reviewed" | A closed or missing bead also means *stale* or *never* reviewed. Confirm a codex review's `commit_id` is HEAD_SHA. |
| "Mergeable is probably fine" | Run the check. UNKNOWN merges fail with misleading errors. |
