# tk-x5qa8: amend-existing-PR workflow — investigation

| Doc-type | Producer | Source location (path + commit SHA) | Surveyed at |
|---|---|---|---|
| analysis | polecat tk-x5qa8 (gc-toolkit.furiosa) | `specs/tk-x5qa8/analysis.md` @ `polecat/tk-x5qa8-pr-amend-investigation` (branched from gc-toolkit `74eda8bc`) | gascity `5d6890f2`, gc-toolkit `74eda8bc` |

## TL;DR

**The "amend existing PR" mechanism the bead asks for already exists in gascity
and is already wired into the gc-toolkit refinery patrol.** Gascity issue
[#709](https://github.com/gastownhall/gascity/issues/709) (filed 2026-04-14,
closed 2026-04-19) and PR
[#904](https://github.com/gastownhall/gascity/pull/904) (merged 2026-04-19) made
the polecat respect a pre-set `metadata.branch` and made the refinery validate
and reuse `metadata.existing_pr` instead of opening a duplicate PR.

The reason the close-and-replace cycle still happened on tk-wzcvj/tk-trafv
(2026-05-11) is **discoverability**, not capability:

1. The mayor and mechanik agent prompts say nothing about `existing_pr` —
   only the polecat and refinery prompts do, and only as receive-side docs.
2. `gc sling` has no first-class flag for it; the caller has to chain
   `gc bd update <bead> --set-metadata existing_pr=... --set-metadata branch=...`
   before slinging.
3. No rig README, gc-toolkit doc, or skill describes the "supplement bead for
   scope miss" recipe end-to-end.
4. When the refinery reuses an existing PR it does **not** post a comment or
   amend the PR body to record the supplement bead ID, so the audit trail
   ("PR carries both bead IDs in its history" — bead acceptance language) is
   incomplete even when the mechanism is used correctly.

**Recommended verdict: adopt + document** rather than design a new workflow.
Two follow-up beads cover the gaps (§5).

## 1. What the bead asked for

From `gc bd show tk-x5qa8`:

> A supported workflow where:
> - Mechanik discovers a scope miss after a PR is open.
> - Files a "supplement" bead with the additional scope (could be just docs, just tests, additional refactor, etc.).
> - Dispatches a polecat that branches off the **existing PR's branch** and commits new work.
> - The new commits land on the existing PR (PR auto-updates), not a separate PR.
> - The supplement bead closes when the polecat finishes; the original PR carries both bead IDs in its history.

The bead enumerates three options it considered (close-and-replace, stacked PR,
direct branch edit) and asks for a fourth that achieves a single coherent PR
even when scope discovery is iterative.

## 2. The mechanism (already present)

The capability lives in three coordinated places:

### 2.1 Polecat — `workspace-setup` honors pre-set `metadata.branch`

`gascity/.beads/formulas/mol-polecat-work.toml:98-133` (production formula, also
mirrored at `gc-toolkit/formulas` via pack inheritance):

```bash
BRANCH=$(gc bd show {{issue}} --json | jq -r '.[0].metadata.branch // empty')

**If branch exists in metadata** — treat it as authoritative. This
metadata may come from rejection recovery or from a caller that wants
work applied to an existing branch.
```

The polecat fetches `origin/$BRANCH`, fast-forwards (or stops on divergence),
and works on top of it. Identical recovery path to the rejection-resume case
(`metadata.rejection_reason`), so the code path is exercised on every rejection
cycle.

### 2.2 Polecat — `submit-and-exit` preserves `metadata.existing_pr`

`gascity/.beads/formulas/mol-polecat-work.toml:211-221`:

```text
... If an existing pull request was provided by the caller,
`metadata.existing_pr` is preserved for refinery validation. The refinery
records canonical `pr_url` only after verifying the PR is open and matches
the branch, base, and origin repository.
```

The polecat does **not** write or canonicalize `pr_url` itself — only the
refinery does, after validation. This protects against a caller pointing at
a stale or wrong PR.

### 2.3 Refinery — `merge-push` validates and reuses

`gascity/.beads/formulas/mol-refinery-patrol.toml:276-373` (and the mirrored
gc-toolkit copy at `formulas/mol-refinery-patrol.toml:276-373`):

```bash
EXISTING_PR=$(gc bd show $WORK --json | jq -r '.[0].metadata.existing_pr // empty')

if [ -n "$EXISTING_PR" ] && [ "$MERGE_STRATEGY" = "direct" ]; then
  echo "metadata.existing_pr requires pull-request handoff; using merge_strategy=mr."
  MERGE_STRATEGY="mr"
fi
```

Auto-promotion to `mr` strategy means **callers only need to set
`existing_pr` + `branch`** — they do not have to also set `merge_strategy=mr`.

Validation checks (lines 326-373) block-and-escalate if any of these mismatch:

| Check | Block reason |
|---|---|
| PR state | "Existing PR $EXISTING_PR is $STATE, want OPEN." |
| PR head ref | "...targets branch $PR_HEAD, want $BRANCH." |
| PR base ref | "...targets base $PR_BASE, want $TARGET." |
| PR origin repo | "...belongs to repo $PR_REPO, want $ORIGIN_REPO." |
| PR head repo | "...head repo $PR_HEAD_REPO, want $ORIGIN_REPO." |
| `branch` metadata present | "metadata.existing_pr is set but metadata.branch is missing." |

A validation failure routes the bead to `gc.routed_to=human` and mails mayor.
No silent retargeting; no second PR.

After validation, the refinery rebases the polecat branch onto `$TARGET` in a
`temp` branch, then pushes back with `--force-with-lease`:

`mol-refinery-patrol.toml:496-503`:

```bash
git checkout temp
git push origin HEAD:$BRANCH --force-with-lease
```

GitHub auto-updates the open PR with the new tip. The existing PR carries the
new commits as additional pushes — no second PR is created.

### 2.4 Test coverage

`gascity/examples/gastown/gastown_test.go:379-499` asserts both formulas
contain the expected validation literals (33 string assertions across the
two TOMLs). The capability is contract-tested at the formula text level, not
just runtime-tested.

### 2.5 What the caller has to do today

Concrete recipe — discovered by reading the formulas, not from any doc:

```bash
# 1. Find the existing PR's head branch.
BRANCH=$(gh pr view <PR-URL> --json headRefName -q .headRefName)

# 2. File the supplement bead. Title + description describe the new scope only.
NEW=$(gc bd create -t "scope supplement: <what's added>" \
        -d "Adds <X> to existing PR <PR-URL>.  Branches from $BRANCH.  ..." \
        --json | jq -r '.id')

# 3. Set the amend metadata BEFORE slinging (sling has no flag for this).
gc bd update "$NEW" \
  --set-metadata branch="$BRANCH" \
  --set-metadata existing_pr="<PR-URL>" \
  --set-metadata target=main
# merge_strategy is auto-promoted to "mr" by refinery; no need to set it.

# 4. Sling to the polecat pool as usual.
gc sling <rig>/polecat "$NEW"
```

The polecat picks up, checks out `$BRANCH` (the existing PR's head), commits
new work, pushes, and reassigns to refinery. Refinery validates the PR, rebases
`$BRANCH` onto `main`, force-pushes — the PR auto-updates with the supplement
commits. Single PR. Two bead IDs in the work-bead ledger.

## 3. Why the bead's premise reads "no supported pattern"

The mechanism landed upstream 2026-04-19. The tk-wzcvj close-and-replace
happened 2026-05-11 — **22 days after** the feature was available. Three
factors plausibly contributed:

1. **The mechanik and mayor prompts don't mention it.** Searched
   `agents/mechanik/prompt.template.md`, `agents/mayor-thread/agent.toml`,
   `examples/gastown/packs/gastown/agents/mayor/prompt.template.md` — zero
   hits for `existing_pr` outside polecat/refinery files.
2. **`gc sling --help` doesn't surface it.** Sling flags cover formula vars,
   merge strategy, convoys, scope, but there is no `--existing-pr`,
   `--branch`, or `--set-metadata` flag. The caller has to know to use
   `gc bd update --set-metadata` first.
3. **`specs/tk-uuzyw/branch-workflow-research.md:170` only mentions
   `existing_pr` in a one-line metadata table** and labels it as relevant only
   to `merge_strategy=mr`, without describing the dispatcher recipe. The
   research that surveyed the workflow predates the close-and-replace
   incident but did not extract the "scope-miss supplement" pattern.

So at decision time the mayor/mechanik searched their own prompts and the
sling help, didn't find anything, and reasoned from first principles that the
only options were the three in the bead description. Mechanism present;
knowledge absent.

## 4. The four bead prongs — answered

### 4.1 Mechanic check

> What does the refinery actually need to support an "amend PR #N" mode?

**Nothing additional.** Bead-side: `metadata.existing_pr` (URL) +
`metadata.branch` (head ref). Refinery side: already validates, rebases,
force-pushes (`mol-refinery-patrol.toml:276-595`). Polecat side: already
branches from `metadata.branch` when present (`mol-polecat-work.toml:98-133`).
Sling side: no flag; caller must `gc bd update --set-metadata` first.

The bead's hypothetical sling UX (`gc sling … --amend-pr <existing-pr>` or
`--base-branch <existing-branch>`) would be ergonomic sugar, not new
capability. See follow-up §5.2.

### 4.2 Stacked-PR alternative

The bead description correctly observes stacked PRs are worse for this case:
"Still two PRs." Two additional notes from this audit:

- **Stacked PRs already work** in gc-toolkit via `metadata.target =
  polecat/<previous-bead>`. The polecat resolution chain (`mol-polecat-work`
  workspace-setup `{{base_branch}}` resolution) honors arbitrary refs as
  the base. The refinery merges into whatever `metadata.target` says, not
  just `main` (`mol-refinery-patrol.toml:275`). This is also how owned
  convoys with `integration/<convoy-id>` work
  (`polecat CLAUDE.md` "Integration branches (owned convoys)" section).
- **Stacked PRs are the right tool when the supplement is independently
  reviewable** (e.g., adding tests for code already in review). The
  amend-existing-PR pattern is the right tool when the supplement is
  *part of the same logical change* (the tk-wzcvj/tk-trafv case — docs
  and caveats for the change in PR #5).

Both patterns coexist. The choice is editorial, not technical.

### 4.3 Upstream signal

Gascity already has the feature. No upstream advocacy needed for the core
mechanism. Two narrower upstream candidates worth filing if we want them
(§5):

- **`gc sling --existing-pr <url>` flag** — pure UX, lives in
  `cmd/gc/cmd_sling.go`.
- **Refinery posts a PR comment when amending** — lives in the refinery
  formula text, fits in the `mr` branch right before the final
  `gc bd update --set-metadata pr_url=...` block.

### 4.4 Scope-discovery hygiene

Adjacent and broader than this bead. The dispatch-side equivalent of "don't
let scope misses happen in the first place" is essentially the brief-quality
question, which is well-trodden territory. Worth noting but **not a blocker**
for adopting the amend-PR pattern — even with perfect briefs, late-discovered
scope happens (mid-review feedback, follow-up bugs found in the diff, security
findings, etc.).

If we want to take a swing at it: a pre-dispatch checklist in the mayor
prompt ("before slinging, run `gc bd show <bead> | grep -E '<key-acceptance-
keywords>'` against the brief; …") would be the lightweight move. Tracking
that question would be a separate bead, not a child of this one.

## 5. Recommendations and follow-up beads

### 5.1 Adopt the existing mechanism — document the recipe

**File a gc-toolkit implementation bead** with:

- Update `agents/mechanik/prompt.template.md` to include a "Scope-miss
  recovery: amend existing PR" subsection with the 4-step recipe from §2.5.
- Update `agents/mayor-thread/agent.toml` (or its companion prompt) with the
  dispatcher-side framing: "When mechanik flags a scope miss on an open PR,
  file a supplement bead with `existing_pr` + `branch` metadata; do not
  close-and-replace."
- Add a "PR amend recipe" section to `docs/` (or to a new
  `docs/dispatch-patterns.md`) with the same recipe and a worked example
  (the tk-wzcvj → tk-trafv close-and-replace as the cautionary tale).
- Add the recipe to a gc-toolkit skill (probably new: `skills/pr-amend/`)
  so it surfaces via slash-command discovery.

**Acceptance**: mechanik prompt + mayor prompt + docs all mention the
`existing_pr` + `branch` pattern with the 4-step recipe; gc-toolkit's
formula and refinery prompt patches still match gascity (no drift).

This is a docs-and-prompts bead — small surface, gc-toolkit-internal, no
upstream change required. Estimated p3, ~1 polecat dispatch.

### 5.2 Upstream-candidate bead: sling UX for amend metadata (optional)

**File against gascity** (issue + PR candidate):

- Add `--existing-pr <url>` flag to `gc sling` that:
  - Validates the PR exists and is OPEN (mirroring the refinery's check).
  - Resolves the PR's head ref and sets `metadata.branch` on the bead.
  - Sets `metadata.existing_pr` and `metadata.target` (PR's base ref) on
    the bead.
  - Optionally auto-promotes `merge_strategy=mr`.
- Equivalent to `gc bd update --set-metadata` + `gc sling`, but a single
  atomic call.
- Skip if §5.1 is enough — most dispatch happens from an agent that can
  string two commands together cheaply.

This one is **optional**. The two-step recipe is fine; adding a flag is
sugar. We could file it speculatively at p3 and let the gascity maintainers
prioritize, or hold off and revisit if the close-and-replace pattern recurs
after §5.1 lands.

### 5.3 Optional: refinery records supplement bead ID on existing PR

The bead's stated goal includes: "the original PR carries both bead IDs in
its history." Today, refinery just force-pushes new commits — the original
PR description still names only the original bead.

A small refinery formula change in the `EXISTING_PR != ""` branch (somewhere
around `mol-refinery-patrol.toml:520-535`) could post a PR comment:

```bash
if [ -n "$EXISTING_PR" ]; then
  gh pr comment "$EXISTING_PR" --body "Amended via $WORK ($(gc bd show $WORK --json | jq -r '.[0].title'))."
  PR_REF="$EXISTING_PR"
else
  ...
fi
```

Best filed upstream (gascity issue + PR) since it touches the canonical
formula. p3.

## 6. Outstanding caveats

- **Concurrent amendments** to the same PR branch: polecat does
  `git push origin HEAD` without `--force-with-lease`. If two amendment
  polecats race on the same branch, the second will fail non-FF. This is
  arguably correct behavior — concurrent supplements should serialize —
  but the failure mode surfaces as a generic push failure with no
  user-friendly message. Existing rejection-aware resume covers the
  follow-up. No action recommended; flag if it bites.
- **The original PR's description does not update** with the supplement
  bead's text. PR body still says "Issue: <original-bead>". Search the PR
  events for the second push to find the supplement. §5.3 closes this gap
  via a comment; updating the body would be more invasive (rewriting
  body sections written by a different polecat).
- **`metadata.branch` divergence**: if the rig's `polecat/<bead>` branch
  was deleted from origin (e.g., refinery `delete_merged_branches=true`
  on a previous failed cycle, or manual cleanup), the polecat's
  `git fetch origin "+refs/heads/$BRANCH:..."` will fail and stop. The
  failure message ("metadata.branch=$BRANCH was set but no local or
  origin branch exists") is clear but the caller has to know to
  recreate the branch or pick a different recovery path. Documenting
  this in §5.1's recipe avoids surprise.

## 7. Provenance

| Source | Path | Commit |
|---|---|---|
| Polecat formula | `gascity:.beads/formulas/mol-polecat-work.toml` | `5d6890f2` |
| Refinery formula (gascity) | `gascity:.beads/formulas/mol-refinery-patrol.toml` | `5d6890f2` |
| Refinery formula (gc-toolkit) | `gc-toolkit:formulas/mol-refinery-patrol.toml` | `74eda8bc` |
| Polecat prompt (gastown) | `gascity:examples/gastown/packs/gastown/agents/polecat/prompt.template.md` | `5d6890f2` |
| Refinery prompt patch (gc-toolkit) | `gc-toolkit:patches/refinery-prompt.template.md` | `74eda8bc` |
| Mechanik prompt | `gc-toolkit:agents/mechanik/prompt.template.md` | `74eda8bc` |
| Gascity issue | https://github.com/gastownhall/gascity/issues/709 | closed 2026-04-19 |
| Gascity PR | https://github.com/gastownhall/gascity/pull/904 | merged 2026-04-19 |
| Trigger incident | tk-wzcvj (PR #5) → tk-trafv (PR #11), both closed 2026-05-11 | — |
| Prior research | `gc-toolkit:specs/tk-uuzyw/branch-workflow-research.md:170` | — |
