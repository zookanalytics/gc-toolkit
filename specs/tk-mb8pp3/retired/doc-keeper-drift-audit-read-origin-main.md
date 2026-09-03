---
name: doc-keeper-drift-audit-read-origin-main
description: "drift-audit must judge the origin/main brief text, not the polecat worktree copy (which can be on a stale branch); dedup against open PRs of closed doc-update beads"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: b29c8151-ed87-4a67-9cfe-7172c543ad0d
---

The `mol-doc-keeper-drift-audit` formula's `audit-and-file` step reads briefs
from `$REPO` (`cd "$REPO" && ls docs/gascity-*.md`), i.e. the polecat
**worktree** checkout. That worktree may be on a stale branch — in the 2026-06-19
run (`tk-gz4x6`) `gc-toolkit.nux` was on `tk-l94qz-work` (based on the gone
`origin/polecat/tk-ej8s1`), **behind** `origin/main` by four landed doc-update
merges (#142/#146/#147/#148).

**Why:** the audit targets `main` (filed beads carry `target=main`), and recent
doc-update PRs that already fixed drift live on `origin/main` but not on a stale
branch. Auditing the worktree copy re-finds already-landed drift → false-positive
beads.

**How to apply:**
- Enumerate the brief **set** from `origin/main`, not the worktree glob: the
  step's `ls docs/gascity-*.md` runs in the stale worktree and *under-counts* —
  a brief added upstream after the worktree's base simply isn't on disk. Use
  `git -C "$GC_RIG_ROOT" ls-tree -r --name-only origin/main -- docs/ | grep
  gascity-`. (2026-06-24 run `tk-4zwtp`: worktree was **30 commits behind**
  origin/main and the glob missed `docs/gascity-packs.md`, added in #168 — the
  current HEAD that day; caught only by reading the reference brief's new link to
  it. As of that run the canonical set is **five** briefs: agents,
  local-patching, packs, reference, routing-model.)
- Extract and judge the `origin/main` brief versions: `git -C "$GC_RIG_ROOT" show
  origin/main:docs/gascity-<name>.md`. Fetch first.
- A rebased-away provenance SHA/line in a brief's "Verified at <sha>" table is
  **not** drift: when the upstream fork is rebased (2026-06-24: gascity HEAD
  `07a39a934` "clean QF1012 lint fallout from upstream rebase"), cited SHAs
  (`434d57656`→`a4c713b9a`) and test line-numbers (`sling_test.go:3809`→`:3390`)
  churn while the *substantive* claim stays true. Verify the symbol/behavior
  still exists; if it does, the breadcrumb staleness is provenance-pin churn, not
  a claim made false — leave it. Chasing it would re-file the brief after every
  upstream rebase.
- Run the FULL dedup before filing: live (non-closed) `doc-update` beads **plus
  the open PRs of recently-closed** `doc-update` beads — the refinery closes the
  bead when it opens the PR (`merge_strategy=mr`), so a bead-only query misses
  in-flight work. A productive prior sweep (the 2026-06-19 run found 7 open
  doc-update PRs: #141/#144/#145/#149/#150/#151/#153) makes a clean **0-finding**
  run the correct outcome, not a failure.
- Incompleteness (a new CLI verb/flag the brief omits, e.g. `gc session close`
  defaulting to `$GC_SESSION_ID`) is the *memory* audit's job, not drift. See
  [[doc-keeper-drift-audit-exclusions]] and [[gascity-agents-doc-source-of-truth]].
- The unit of judgment is the `origin/main` brief text, **not** in-flight PRs. An
  open doc-update PR can *add* content for a footgun upstream already fixed (the
  fix commit can predate the audit bead — 2026-06-21 run: gascity `02a0fdab0`
  "wake drained on_demand session" landed 2026-06-18, ~7h before PR #141 was filed
  to *document* that footgun). The current brief carries no falsifiable claim until
  that PR merges, so it's correctly a **no-report** — don't dup the topic, and
  don't `gc mail`/escalate about the possibly-stale PR; its GitHub reviewer owns
  it. Flagging an in-flight PR is scope-creep for a read-only brief audit.
