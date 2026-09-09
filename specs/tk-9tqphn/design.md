---
name: Correctness method-tier latitude and per-check method files
description: Design settling two facets of the review-gates system — (A) triage latitude over the correctness review's method-tier as a separate attribute, and (B) per-check method files (review-<check>.md) delivered as plain files, not skills — plus the review-policy naming that the rename/rollout bead tk-cwkmt2 is blocked on.
---

# Correctness method-tier latitude and per-check method files

This settles three coupled questions so the rename/rollout work can execute:

- **A. Method-tier latitude.** How triage varies the *correctness* review's
  method (a cheap pass, a standard model, a stronger model) without turning
  correctness into more than one check.
- **B. Per-check method files.** Whether each check's method lives in one file
  per check (`review-<check>.md`) or in a skill, and how the reviewer receives
  it.
- **C. Naming.** How `review-policy.md` and the `review-<check>.md` family are
  named as a rig-agnostic convention.

The executor beads are tk-cwkmt2 (rename `review-charter.md` →
`review-policy.md`, define the naming convention, author per-rig policies),
tk-uqlwe8 (per-check method files), and tk-3voqke (the tier attribute).
tk-cwkmt2 is blocked on this spike; it names this document as what settles the
`review-policy` and `review-<check>.md` naming it depends on.

## Where this sits

The review-gates design in
[specs/2026-08-review-gates/scope.md](../2026-08-review-gates/scope.md) adds a
triage check that widens each anchor's `check_set` from a declared menu, and
dedicated reviewers (`arch` first) that each read a small charter plus the diff.
That design is landing on `polecat/tk-kt4ubc` (PR #615, open and merge-blocked
at the time of writing); it is not yet on `main`. This spike refines two facets
of it and answers one naming question the rollout depends on. It changes no
lifecycle state and adds no new check to the menu.

Two vocabulary points from the parallel rename bead tk-yohbqe hold here: the
default check is being renamed `codex` → `correctness`, and `gate` is retired as
a noun in favor of `check`/`review`. This document uses `correctness` for the
baseline check and `check`/`review`/`lane` throughout; the live code still reads
`codex` and `gate` until tk-yohbqe lands.

## Current state

The live system runs exactly one review method, the `mol-review` formula,
dispatched for every check named in an anchor's `check_set`. The relevant
mechanics, read on `main` unless noted:

- **`check_set`** is anchor metadata: a flat comma-list of clean check names.
  The default is `codex` and the only opt-out sentinel is `none`
  (`lifecycle/lifecycle.toml:185-186`). An empty `check_set` is never treated as
  `none`; it holds the merge until normalized.
- **Dispatch.** `assets/scripts/gate-ensure.sh` splits `check_set` into checks
  (`:519`), skips `none`/`off`/`approval` (`:522-523`), derives each lane's
  green state, and for a lane short of green stamps a review bead
  (`task_kind=review`, `check_name`, `anchor_bead`, `review_branch`,
  `review_base`, `review_pool`, `reviewed_oid`; `:707-715`) and slings it with
  `gc sling "$REVIEW_POOL" "$RID" --on mol-review` (`:728`). The formula is
  `mol-review` regardless of the check name; `check_name` only labels which
  marker `signoff.sh` stamps.
- **Reviewer pool and model** are fixed per pool, not per review bead. The
  reviewer is the `polecat-codex` pool (`provider = codex`); `gate-ensure.sh`
  slings to a single `REVIEW_POOL`. There is no tier or model field on a review
  bead today.
- **The method is delivered as text, not as an injected skill.** The
  `mol-review` steps carry the checklist inline; correctness is one bullet on
  it (`formulas/mol-review.toml:196-197`). Supplementary "Standards for what you
  produce" content is resolved as a plain file and `cat`'d at review time
  (`mol-review.toml:231-253`, the `work-quality.template.md` fragment) precisely
  "because nothing injects it into a prompt."
- **On the in-flight branch** (`polecat/tk-kt4ubc`),
  `assets/scripts/review-dispatch-body.sh --check-name <check>` emits a
  method section keyed on the check name and instructs the reviewer to "use the
  gate method this dispatch names and no other: do not match a review-shaped
  skill out of your catalog." The same branch also adds `skills/review-triage`
  and `skills/arch-review` as pack-scope skills. So the method for triage and
  arch exists both as a dispatch-emitted section and as a skill, while
  correctness's method is the formula checklist plus a `cat`'d fragment. This
  heterogeneity is what facet B normalizes.

## A. Correctness method-tier latitude

### A1. The tier is a separate attribute, never a check_set token

Correctness is a forced baseline: always in `check_set`, never removable
(operator, this visit). What triage may vary is the *method tier* of that one
correctness review — a cheap pass for a trivial diff, a standard model normally,
a stronger model when the diff warrants.

The tier is modeled as a separate attribute, not as a dotted `check_set` token
such as `correctness.advanced`. Two tokens would be two check names, which
`gate-ensure.sh` splits into two lanes and dispatches as two `mol-review` beads
(`gate-ensure.sh:519`, `:707-728`), so correctness would be reviewed twice. One
attribute keeps one correctness lane, answered once at the chosen tier.

This is additive to the settled design: `check_set` stays a flat list of clean
check names and dispatch stays data-driven by check name, so a tier attribute
changes neither.

### A2. Shape of the attribute

- A single anchor metadata key — `correctness_tier` — drawn from a small closed
  set, `cheap | standard | advanced`. The names map to reviewer pools/models;
  the exact model per tier is a rig-and-cost decision for the build, not fixed
  here.
- **The tier selects the reviewer pool/model at dispatch.** Model choice is a
  property of the pool a review is slung to (`gate-ensure.sh:713`, `:728`), so
  the correctness lane's `REVIEW_POOL` is resolved from the tier when that lane
  dispatches. This is the one code point the tier touches.
- **The tier never carries a "skip" value.** The cheapest tier still runs a
  correctness review. Not-reviewing is `check_set=none`, which stays the
  human-only opt-out that triage can never reach (scope.md "Rules that make it
  safe"). Keeping the skip decision out of the tier is what preserves the
  forced-baseline invariant: no tier value can silence correctness.

### A3. Held versus stamped (the deferred build-time decision)

The open question is the relationship between triage's tier choice and
correctness's dispatch. The operator deferred the final call to build time; this
records the options and a recommendation so the build starts from a position.

The realistic options narrow once you see that a tier is a *model*, and a model
is chosen when a review is slung to a pool:

1. **Triage as planner (correctness held).** `gate-ensure` dispatches triage
   first; triage stamps the tier (and adds any checks); the next cadence pass
   dispatches correctness at the stamped tier. Correctness runs once at the
   right tier. Cost: one extra cadence hop of latency on every correctness, and
   it changes the settled design's parallel dispatch (where `codex` and `triage`
   are both in the default set and dispatch together).
2. **Default and upgrade.** `gate-ensure` dispatches correctness at a default
   tier in parallel with triage; if triage stamps a higher tier, the
   correctness marker is invalidated and correctness re-dispatched at the higher
   tier. Cost: no common-case latency, but correctness double-runs on the subset
   triage upgrades — the same waste A1 avoids, now only for upgraded diffs.
3. **Late-bound.** Dispatch both in parallel and have the correctness reviewer
   read the tier when it starts. This works only if a tier is an *effort level
   within one model*, because a session's model is fixed when it spawns. For the
   model-selection tiers this spike describes, option 3 collapses into option 1
   or 2 and is not independently viable.

**Recommendation: a mechanical default from the policy, plus triage upgrade
(option 2 refined).** Give `review-policy.md` a mechanical tier rule readable at
dispatch (for example, "diff touches `<paths>` ⇒ advanced; diff under N lines ⇒
cheap"), the way the policy already carries mechanical mandatory-check rows
(scope.md "Mechanical backstop for misses"). `gate-ensure` reads that rule from
the reviewed commit and dispatches correctness at the right tier immediately, in
parallel with triage. Triage may still upgrade, which re-dispatches correctness
only when triage overrides the mechanical default — the rare case. This keeps
the common case single-run and un-serialized, and confines the double-run to
diffs where a session-level classifier genuinely disagrees with the mechanical
rule.

If a mechanical tier rule proves hard to express for a rig, option 1 (triage as
planner) is the fallback: it never double-runs, at the cost of one cadence hop
and blocking the baseline on the classifier. Option 2 with a blanket `standard`
default (no policy rule) is the weakest, because it double-runs every upgraded
diff.

One constraint bounds all three: `pr-open.sh` requires correctness green before
it opens the PR (scope.md "`codex` is not waivable before the PR exists"). Under
any option, the correctness review at the chosen tier must reach green at
`pre_open_gate`; option 1 simply adds a hop before that point.

## B. Per-check method files

### B1. One plain file per check

Each check's method — what the reviewer reads and judges for that check — is one
plain file per check: `review-correctness.md`, `review-arch.md`,
`review-triage.md`, `review-docs.md`, and one per check added later. They are
siblings of the menu file `review-policy.md`, flat under `docs/` (matching the
`docs/review-policy.md` name the rename bead already commits to). If the family
grows past roughly five, a `docs/review/` subdirectory is the accommodation
(docs/file-structure.md); until then, the `review-` prefix groups them in a flat
listing.

### B2. Files, not skills

The method is a plain file read at review time, not a skill. Four grounds, each
checked against current code:

1. The correctness method already delivers its supplementary content as a plain
   file `cat`'d at review time (`mol-review.toml:231-253`), explicitly because
   nothing injects it into a prompt. Per-check files extend a pattern the live
   reviewer already uses, rather than adding a second delivery mechanism.
2. The in-flight `review-dispatch-body.sh` already keys the method on
   `--check-name` and forbids the reviewer from matching a review-shaped skill
   from its catalog. A file keyed on check name is what that instruction already
   assumes; a skill is what it warns against.
3. Agent-scoped skills are unverified and unused (`docs/skills.md:72-75`), and
   pack-scope skills load their `name` + `description` into every agent's
   startup metadata (`docs/skills.md:124`). A review method as a pack-scope skill
   is noise in every non-reviewer agent and a second copy of the method to keep
   in sync with the dispatch section.
4. The per-rig, read-from-the-reviewed-commit model the rollout adopts
   (tk-cwkmt2: signoff reads the policy via `git show <oid>:docs/review-policy.md`)
   is a plain-file pattern. A skill is loaded from the agent's installed catalog,
   not from the diff's commit, so it cannot be per-rig and reviewed-commit-bound
   the way a file can.

### B3. Mechanism

`review-dispatch-body.sh --check-name <check>` resolves `docs/review-<check>.md`
from the reviewed commit (`git show <reviewed_oid>:docs/review-<check>.md`
through whichever local repo carries the object) and includes it as the method
section, extending the fragment resolution `mol-review` already performs. A
missing file degrades gracefully: correctness still runs, triage falls back to
the coarse rule in its own method text, and the reviewer files an
`obs.category=charter-gap` observation — the same degradation the rollout bead
specifies for a missing policy.

The method text that lives in `skills/review-triage` and `skills/arch-review`
on the in-flight branch moves into `docs/review-triage.md` and
`docs/review-arch.md`, and those two pack-scope skills retire. `review-correctness.md`
is extracted from the `mol-review` "What to check" list plus the work-quality
fragment. Because the exact split between the dispatch-emitted section and the
skill files on `polecat/tk-kt4ubc` was not read line-for-line here, the method-
files bead (tk-uqlwe8) verifies the current delivery against the landed PR #615
before removing anything.

### B4. Worked example: a `docs` check

`review-docs.md` — applies-when: the diff touches `docs/**`. Method: hold the
changed docs to `docs/file-structure.md` — correct tier (central `docs/` vs
local `specs/<bead-id>/`), present-tense authoritative content, a `## Scope`
section on a central doc, and no history, dates, or bead/PR ids in the prose.
This check is not added to any default `check_set` here; it is a menu row triage
can add when the diff warrants, and the example that shows a method file reads
cleanly as one file per check.

## C. Naming: review-policy and the review-<check> family

The menu file is `docs/review-policy.md`, renamed from `docs/review-charter.md`
(tk-cwkmt2, this visit). "Charter" bundled two roles: the architecture contract
a reviewer reads, and the check menu. This design keeps them separate:

- **`docs/review-policy.md` is the menu.** Each row is: check name → applies-when
  → its `review-<check>.md` method file → (for correctness) the mechanical tier
  rule → mandatory paths → whether triage may waive it.
- **The architecture contract stays where it is** — `component-model.md` §5 (the
  admission test) and `architecture.md`'s layer map (scope.md "Why small context
  works"). `review-arch.md` points at them. There is no separate "charter"
  artifact after the rename; `review-policy.md` plus the per-check method files
  carry what "charter" named.

The convention is rig-agnostic, so it carries no gc-toolkit-specific names: each
rig owns `docs/review-policy.md` and its `docs/review-<check>.md` files, read
from the reviewed commit, degrading gracefully when absent. Authoring each rig's
considered policy is tk-cwkmt2's fourth item.

## The plan the executor beads run against

| Bead | Owns | Blocked on |
|---|---|---|
| tk-cwkmt2 | Rename `review-charter.md` → `review-policy.md`; the rig-agnostic `review-policy.md` + `review-<check>.md` naming convention; the per-rig read-from-reviewed-commit model and graceful degradation; authoring each rig's policy | PR #615, this spike |
| tk-uqlwe8 | Per-check method files `docs/review-<check>.md`; migrate `skills/review-triage` and `skills/arch-review` into files and retire them; add `review-correctness.md` and `review-docs.md`; wire `review-dispatch-body.sh` to read from the reviewed commit | PR #615, this spike |
| tk-3voqke | The `correctness_tier` attribute; per-tier reviewer-pool resolution at dispatch; the mechanical default in `review-policy.md` and triage's upgrade; tests | PR #615, this spike |
| tk-yohbqe | Rename the `codex` check → `correctness`; retire `gate` as a noun | — |

The three new-work beads carry the same detail in their descriptions and point
back here. They are blocked so they cannot dispatch before PR #615 lands and this
spike closes; the settled design must be on `main` before its refinements are
built.

## Open questions

- **A3 held-versus-stamped** is the operator-deferred build-time decision above.
  The recommendation is the mechanical-default-plus-upgrade path; the build
  makes the final call once a rig's tier rule is written.
- **Tier value names and the model per tier** (`cheap`/`standard`/`advanced` →
  which model) are a per-rig cost decision left to tk-3voqke and the per-rig
  authoring.
- **Whether tk-uqlwe8 folds into tk-cwkmt2.** The method-files migration and the
  policy rename touch the same files and could be one bead; kept separate here
  because the skill retirement and dispatch wiring are a distinct mechanism
  change from the rename and per-rig authoring.
