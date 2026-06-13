---
name: doc-keeper Rolling-Cycle Mechanism
description: The branch + PR lifecycle for doc-keeper's rolling docs cycle — how docs/rolling-N is created, advanced, and resolved, and the single idempotent discover-or-create entry point (assets/scripts/doc-keeper-rolling-cycle.sh) that every doc-keeper formula calls at step 0 to pin its target branch. Supersedes the convoy-batching sketch in the scout architecture (tk-yw3zb.1 §3) with a plain long-lived branch + long-lived PR.
---

# doc-keeper Rolling-Cycle Mechanism

doc-keeper (epic `tk-yw3zb`) keeps gc-toolkit's **agent brief** current by
filing small `doc-update` beads, turning each into a one-doc branch, and
merging them — many polecats, **one** operator-reviewed PR. This spec defines
the lifecycle of that one PR: who creates `docs/rolling-N`, who opens the PR,
when `N+1` starts, and what happens when a cycle PR sits unmerged or is
abandoned. It also defines the single idempotent mechanism every doc-keeper
formula calls to resolve the current cycle's target branch.

The mechanism ships as one script: **`assets/scripts/doc-keeper-rolling-cycle.sh`**
(hermetic test: `doc-keeper-rolling-cycle.test.sh`).

## 1. Model: rolling target branch, not a convoy

Each `doc-update` work bead carries `metadata.target = docs/rolling-N`. The
refinery's **existing `direct` merge mode** fast-forwards each completed doc
edit onto that branch — exactly as it does for any bead today, with no
refinery change. `docs/rolling-N` is the head of a **long-lived GitHub PR**
(`docs/rolling-N → main`) that GitHub auto-updates as the branch advances. The
operator watches one PR fill up and merges the batch when it looks complete.

```
   drift-audit (cron)      memory-audit (cron)      organic (any agent)
          │                       │                        │
          │   step 0: resolve the current rolling cycle    │
          │   (doc-keeper-rolling-cycle.sh) ───────────────┤
          ▼                       ▼                        ▼
        file doc-update beads with metadata.target = docs/rolling-N
                                  │
                                  ▼
              worker polecat (mol-doc-update, tk-yw3zb.5)
              branches polecat/<bead> from origin/docs/rolling-N,
              edits ONE doc, hands to refinery
                                  │
                                  ▼
        refinery `direct` mode fast-forwards onto docs/rolling-N
                                  │
                                  ▼
        long-lived PR  docs/rolling-N → main  auto-updates on GitHub
                                  │
                       operator reviews & merges
                                  ▼
        cycle N resolved → next audit opens cycle N+1
```

### Why this supersedes the scout's convoy sketch

The scout architecture (`specs/tk-yw3zb.1/doc-keeper-architecture.md` §3)
proposed batching via an **owned convoy** with an `integration/doc-keeper-<period>`
target and `gc convoy land` at cycle close. This spec deliberately replaces
that with a plain long-lived branch + PR. Rationale:

| | Convoy + `gc convoy land` (scout §3) | Rolling target branch (this spec) |
|---|---|---|
| PR visible from | cycle close (`land` opens it) | cycle **start** — operator watches it fill |
| Machinery | convoy create/land, graduation bead | none beyond `gh` + `git` |
| Refinery mode | `mr` graduation | unchanged `direct` per edit |
| "Unmerged → next cycle piles in" (epic) | awkward — land already fired | natural — same open PR keeps accruing |

The rolling branch matches the epic's stated property — *"PR is rolling: if it
sits unmerged, the next cycle's work piles into the same PR"* — directly,
without convoy state. Convoys remain the right tool for **code** integration
lines; they are heavier than doc batching needs.

## 2. Resolved decisions

The bead (`tk-yw3zb.4`) posed four open questions. Resolved here with the
bead's own tiebreakers:

1. **When does cycle N+1 begin?** → **Operator-merge-triggered.** There is
   always *at most one* open rolling PR. A new cycle opens only once the
   current PR leaves the open set (merged, or closed/abandoned). Cycles are
   **not** time-based — an unmerged PR keeps accruing edits indefinitely.
2. **Who creates the branch + PR?** → **Whichever doc-keeper formula runs
   first with no cycle open**, via the shared idempotent script as **step 0**.
   No separate "cycle-starter" cron entry (the bead's tiebreaker: *bake it into
   the audit formulas*). The script's idempotency makes "first one in creates,
   the rest discover" safe.
3. **How is the current rolling PR discovered?** → **GitHub query**, no
   separate state store: the lowest-numbered open PR whose head matches
   `docs/rolling-*` and whose base is `main`.
4. **PR closed without merging?** → **Cycle abandoned.** Its number stays
   retired (the next cycle is `N+1`, never a reuse); the next formula run opens
   the new cycle. Work stranded on the abandoned branch is git history, not
   auto-recovered.

Per the epic rescope, there is **no `[doc-keeper]` config block**. The two
constants are inlined: branch prefix `docs/rolling-`, PR base `main`. (The
script exposes `DOC_KEEPER_CYCLE_{PREFIX,BASE,REMOTE}` env overrides for tests
only.)

## 3. Lifecycle

**Creation.** With no open `docs/rolling-*` PR, the script:
1. computes `N = (highest cycle number ever seen in PR history) + 1`;
2. builds an **empty seed commit** on top of `origin/main` with
   `git commit-tree` (no working-tree side effects) so the tracking PR has a
   diff to open against — GitHub refuses a PR with zero commits between head
   and base;
3. pushes it to `refs/heads/docs/rolling-N`;
4. opens the long-lived PR `docs/rolling-N → main`.

**Advancement.** Worker polecats branch from `origin/docs/rolling-N`, edit one
doc, and hand off; the refinery fast-forwards each onto `docs/rolling-N`. The
GitHub PR auto-updates. No script involvement — advancement is just the normal
polecat→refinery flow with `target = docs/rolling-N`.

**Resolution.** The operator merges (or closes) the PR on GitHub. On the next
audit, the script finds no open cycle and opens `N+1`.

## 4. The mechanism: `doc-keeper-rolling-cycle.sh`

A single idempotent script. **Contract:**

| | |
|---|---|
| **Invocation** | `assets/scripts/doc-keeper-rolling-cycle.sh` (no args), from a gc-toolkit worktree whose `origin` is the GitHub remote |
| **stdout** | exactly one line — the rolling target branch, e.g. `docs/rolling-7` |
| **stderr** | progress/diagnostics (safe to discard) |
| **exit** | `0` on success; non-zero only on a hard precondition failure (`gh`/`jq` absent, base unfetchable) |
| **prereqs** | `gh` (authenticated), `jq`, `git`; network to `origin` |
| **side effects** | at most: one branch + one PR created when no cycle is open. **Never** touches the caller's checkout (HEAD/index/working tree) |

Capture and use it like:

```bash
target="$(assets/scripts/doc-keeper-rolling-cycle.sh)"   # e.g. docs/rolling-7
gc bd update "$bead" --set-metadata target="$target"
```

## 5. Integration contract for downstream sub-beads

This bead owns the mechanism; the formulas that call it are downstream. The
contract each relies on:

- **`tk-yw3zb.6` drift-audit / `tk-yw3zb.7` memory-audit formulas.** Run the
  script as **step 0**. Capture the printed branch and stamp it as
  `metadata.target` on **every** `doc-update` bead they file that cycle. This
  is the create point: the first audit with no open cycle opens it; later
  audits discover the same one.
- **`tk-yw3zb.5` doc-update worker formula (`mol-doc-update`).** Prefer the
  `metadata.target` already stamped by the audit. For an **organically** filed
  bead with no rolling target, run the script at step 0 to resolve one, then
  proceed. `mol-polecat-work`'s `workspace-setup` already branches from
  `{{base_branch}} = metadata.target`, so once `target` is `docs/rolling-N`,
  no further change is needed — the refinery rebases onto and fast-forwards the
  rolling branch via `direct` mode.
- **`tk-yw3zb.8` cron registration.** The audit orders gate on
  `doc-keeper.enabled`; the **script is unconditional** (calling it means you
  want a cycle), so the enable gate lives on the orders, not in the script.
  An order may also invoke the script directly as
  `exec = "$PACK_DIR/assets/scripts/doc-keeper-rolling-cycle.sh"`.

**Repo-relative invocation is the contract.** doc-keeper formulas run inside a
gc-toolkit worktree, so the script is reachable at
`assets/scripts/doc-keeper-rolling-cycle.sh` from the worktree root.
(`$PACK_DIR` is set for exec orders but is **not** a reliable agent env var
inside formula steps — use the repo-relative path there.) Because `tk-yw3zb.4`
blocks `tk-yw3zb.5`, the script is merged to `main` before any consumer runs.

## 6. Races and idempotency

Step-0 calls can overlap (two audits, or several organic workers). The design
converges without locking:

- **Numbering from PR history only** (`gh pr list --state all`), never from
  live branches. Two callers that both see "no open cycle" read the *same*
  history and compute the *same* `N`, so they target the same branch. The
  branch push is idempotent (the loser's push is rejected and tolerated); the
  PR create tolerates "already exists". Both then re-discover and return the
  same branch.
- **Lowest-N open PR wins** discovery. If a rare interleaving ever leaves two
  cycles open at once, every subsequent caller deterministically picks the
  lower-numbered one; the operator closes the stray and the system self-heals.
- **Audits are lagged** (drift and memory audits run ~24h apart per the scout
  §7 schedule), so concurrent step-0 creation is unlikely in practice; the
  above makes it *correct* even when it happens.

## 7. Edge cases

- **Abandoned cycle (PR closed, not merged).** Closed PRs remain in
  `--state all`, so the number stays retired; the next run opens `N+1`. The
  abandoned branch is left as history.
- **Crashed creation (branch pushed, PR never opened).** History-only
  numbering does **not** count the orphan branch, so the retry recomputes the
  *same* `N`: the push is a no-op (ref exists) and the missing PR is opened —
  the half-done cycle **heals** instead of forking a duplicate. (Covered by the
  test's "crashed creation self-heals" case.)
- **Seed commit on merge.** The empty `docs: open rolling cycle N` commit rides
  along when the PR merges (or is erased by a squash-merge). Harmless either
  way.
- **Branch auto-deleted after merge.** Fine — numbering reads PR history, which
  survives head-branch deletion.

## 8. Out of scope

- Per-doc conflict resolution within a cycle — the refinery's existing
  rejection-on-conflict path applies; a rejected worker resumes via the normal
  rejection-resume flow.
- A "what's in the rolling PR right now" tool — that is a GitHub query
  (`gh pr view <N> --json files`), not a doc-keeper surface.
- The audit/worker/cron formulas themselves — `tk-yw3zb.5/.6/.7/.8`.

## 9. Acceptance (this bead)

- ✅ Documented spec for cycle creation, advancement, and resolution (this
  file, §3).
- ✅ An idempotent way to discover/create the current rolling PR
  (`assets/scripts/doc-keeper-rolling-cycle.sh`, §4; 17 hermetic test cases).
- ✅ The worker formula (`tk-yw3zb.5`) can call it at step 0 to pin its target
  branch (§5).
