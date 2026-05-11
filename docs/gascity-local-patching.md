# Local Patching of gascity

> The recommended process for cities that need to carry local fixes against
> a `gascity` rig before/instead of upstream.
>
> **The goal is for this process to go away.** Every local patch is a tax —
> on rebase work, on review attention, on divergence risk. If you can wait
> for upstream, wait. If upstream is already converging on a fix, contribute
> there instead. This doc describes how to do it well *when you've decided
> you must*.

---

## When to local-patch

When you hit a bug or design gap in `gascity` that's blocking your city,
evaluate which of three options applies:

1. **Ignore.** Wait for upstream to resolve, accept the cost in the meantime.
   This is the right answer most of the time, especially when others are
   already working the problem.
2. **Local patch.** Carry the fix in your fork until upstream catches up.
   This doc is about that path.
3. **Engage upstream.** Only worthwhile if you have something *materially
   new* to contribute — a missing repro, a regression test, a consequence
   not yet noticed, a framing nobody's used. Engaging when others are
   already iterating on a fix is noise.

Default to option 1. Move to option 2 when the bug is hot and you can't
wait. Move to option 3 only when you have something new, *and* you've
decided you want the public footprint of an upstream PR.

---

## Fork setup

A city patching `gascity` should have two remotes on the rig:

```
origin    = git@github.com:<your-org>/gascity.git    # your fork
upstream  = git@github.com:gastownhall/gascity.git   # canonical
```

`origin/main` is what your city's `gc` binary is built from. `upstream/main`
is the moving target you're tracking.

---

## The patch flow

```
fix/<short-name>  →  PR against origin  →  merge  →  done
```

Standard git flow. Branch off `origin/main`, open a PR, merge normally,
delete the branch on merge. The merged commit is the durable artifact.

Every commit on `origin/main` that diverges from `upstream/main` is, by
definition, a future upstream-PR candidate. The git log *is* the
candidate set: `git log upstream/main..origin/main -- <path>` shows
exactly what your fork carries at any moment.

### Step-by-step

1. **Search upstream first.** Before writing a patch, check
   `gh search prs --repo gastownhall/gascity "<keywords>"` and the issues
   list. If a fix is already in flight upstream, prefer waiting over
   forking a parallel solution.

2. **Branch off `origin/main`.** Name it `fix/<short-name>` so the
   intent is visible.
   ```bash
   git fetch origin
   git checkout -b fix/cache-reconcile-self-event-loop origin/main
   ```

3. **Write the fix and a regression test.** A test that locks in the bug
   matters more than usual here — when you eventually rebase onto a moving
   `upstream/main`, the test is what tells you the patch still does what
   you intended.

4. **Open a PR against `origin/main`.** The PR description is where you
   pay the documentation cost. Treat it as the review packet you (or a
   future reviewer) will use months later when deciding whether to
   submit upstream.

5. **Merge normally.** Delete the branch on merge. The merge commit (or
   squashed commit) is now the durable artifact.

---

## Commit messages are the review packet

Because no candidate branches are retained, the commit message *is* the
record. Skimping here means losing context that you'll wish you had when
upstream is ready or when the patch needs to be rebased.

Every local-patch commit on `origin/main` should carry, in the body:

- **Symptom** — what the user/operator observed (events.jsonl growth,
  doctor warning, dispatch hang, etc.)
- **Root cause** — what's actually wrong in the code, ideally with file
  and function references
- **Regression provenance, if applicable** — which upstream commit/PR
  introduced the problem, and whether it looks deliberate or incidental.
  Reviewers upstream will want this context.
- **Fix and rationale** — what the patch does and why this approach over
  alternatives
- **Measured impact** — concrete numbers if available (event rate before
  vs after, latency, error count). This is the strongest argument for
  upstream merit.
- **Adjacent upstream issues** — links to related PRs/issues, with a
  one-line take on whether they overlap, complement, or address a
  different layer.
- **Local tracker** — the bead ID or other identifier so the city's
  decision history is reachable.

The shape to mirror: a commit body that reads like a self-contained
upstream PR description. If submitted upstream later, it should be
copy-pasteable with minimal editing.

---

## Promoting a commit to an upstream PR candidate

The path from local patch to upstream PR has one entry point: the city
operator picks a specific commit on `origin/main`, reviews it, and
chooses to promote it. The flow:

1. **The operator initiates.** They name a specific commit (or set of
   commits) and start a conversation: "I want to evaluate this for
   upstream — walk me through it."
2. **Agents support the evaluation.** Pull the commit message, summarize
   the change, surface adjacent upstream issues/PRs, identify what's
   materially new vs. what's already in flight upstream.
3. **The operator decides.** If yes, agents help with prep: confirm the
   commit rebases cleanly onto current `upstream/main`, draft a PR
   description from the commit message, run tests on the rebased branch.
4. **Submission and follow-up are operator-driven.** Pushing to the
   upstream remote and opening the PR happen under explicit approval,
   in that conversation, not as a queued action.

The bar for promotion is high. Most local patches will not clear it. A
patch is more likely to be worth submitting when it:

- Fixes a regression that affects users with default configuration
- Has a clean repro and measured impact
- Restores behavior dropped incidentally (e.g., during a refactor) rather
  than removed by deliberate redesign
- Is small, surgical, and well-tested

A patch is less likely to be worth submitting when it:

- Is niche to your city's topology or in-house tooling
- Restores behavior upstream removed deliberately
- Overlaps active upstream work converging on a different fix
- Risks regressions for users with different configurations

In ambiguous cases, default to keeping the patch local. Local-fix cost
is bounded; an upstream PR that needs revision, stalls in review, or
introduces a regression is not.

---

## Dropping a patch when upstream lands a fix

When upstream merges its own fix for something you carry, drop your
local patch:

1. Confirm the upstream fix is functionally equivalent (or strictly
   better). It often differs from yours in style or scope — that's fine
   as long as it solves the same root cause.
2. Revert the local commit on `origin/main` with a message linking the
   upstream merge SHA. Don't `git rebase` your patch out — the revert
   keeps the history clean and explains the drop.
3. Rebuild and verify the running install picks up the new behavior.
4. Close the local tracker bead with a reference to both the original
   commit and the upstream merge.

Branches on `origin/main` that no longer exist (because they were
deleted at merge) need no further action.

---

## Sync workflow

```bash
git fetch upstream main
git checkout main
git rebase upstream/main          # may surface conflicts on patches you carry
go build ./cmd/gc && go test ./...
git push --force-with-lease origin main
```

Conflicts during rebase are the signal that upstream has touched code
your patch covers. Read the upstream change carefully — sometimes it's
your fix landing under a different name (drop your patch), sometimes
it's an adjacent change you can adapt to (rebase the patch), sometimes
it's a fundamental redesign that requires rewriting your patch.

### Agent-driven rebase

In agent-driven cities the keeper dispatches `mol-upstream-gc-rebase` to
do this work. The polecat runs the survey + rebase + test + install +
push chain autonomously. When the rebase halts on a kept commit because
upstream shifted the surrounding code, the polecat does NOT auto-resolve
in favor of upstream (that silently drops your patch's work) and does
NOT abort wholesale (that defeats agent dispatch). Instead it dispatches
a focused rework polecat with fresh context that re-implements the
commit's *intent* on the new upstream layer.

The rework polecat self-classifies its work:
- **mechanical** — the intent transfers cleanly, only anchors shifted.
  Rebase continues with the rework commit replacing the conflicted apply.
- **dropped-absorbed** — upstream already provides the behavior; the
  commit is skipped.
- **judgment-required** — the rework required a design call. A second
  polecat reviews the rework before the rebase continues; if rejected,
  a fresh rework is dispatched with the rejection reason in context.
- **infeasible** — the rework couldn't be done from the polecat's
  context. The keeper hands the bead back for operator intervention.

The keeper's completion mail surfaces a per-conflict audit log so the
operator can see which kept commits required rework and how each was
classified. The full audit lives in `metadata.conflict_resolutions` on
the rebase bead.

**Never run destructive git operations directly in a `gascity` rig that
has active worktrees.** Polecats and other agents may be working there.
Use `git worktree add` for isolation, or coordinate via the city's
agents before rebasing.

---

## When this doc should disappear

Ideally, you don't need it. The end state is:

- `gastown` and `gascity` upstream churn settles
- Bugs you would have local-patched get fixed upstream first
- Your `origin/main` matches `upstream/main` modulo nothing

If your fork has been at zero diverging commits for a while, you can
drop the `origin` remote entirely and use `gastownhall/gascity`
directly. That's the goal.
