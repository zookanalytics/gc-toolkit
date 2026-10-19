---
name: Findings — why a convoy's work landed as one PR per bead
description: An input to this bead's design (design.md beside it). The 2026-10-18 investigation of how gc-toolkit came to open one PR per bead, with dated evidence, as mechanik wrote it. Copied below this header, verbatim except that each reference to another repository names what it was instead (2026-10-19).
---

# Why a convoy's work lands as one PR per bead instead of one PR

Investigation of 2026-10-18, at the operator's request. Three read-only
investigators covered the convoy landing mechanics, the per-bead PR path with
its doctrine, and the multi-stage PR feature. Repo references are gc-toolkit
`origin/main` at 804d0bfd2 unless noted.

## The operator's model, in their words

- 2026-06-23/24, review of #163: "double down on all PRs are a convoy… a convoy
  bead gets created and is the unit that tracks work to DONE." Also: "All
  children closed (i.e. all sub-work has been added to the branch) / The PR for
  our convoy has been merged." Also: "that's just for the convoy that holds the
  PR. For a unit of work bead, it'll close when it's work is done."
- 2026-09-18 (tk-6bji7k): "ideally it's the whole workflow as one PR, but this
  would need some step that happens part way through a PR."
- 2026-09-20 (sitting tk-adazyf): "Decision doc + the implementation should land
  into one PR… approved to move on from that decision point to implement, still
  in the same PR."
- 2026-09-22 (#793 comment): "design document followed by implemention. Boht
  are to land as a single PR when completed."
- 2026-09-23 (tk-e6qphv): "3 stacked PRs, first being design, then spec, then
  implementation". The sitting proposed an owned convoy instead, described as
  "one convoy, three child PRs, three real checkpoint approvals, one landing".
  The operator said "go" on 09-25.
- 2026-09-25 (#793 comment): "a PR to main, a PR to an integration branch, or a
  direct commit to a branch".
- 2026-09-30 (tk-t5f0r7): "avoid the review every commit approach… reviewing a
  complete body of work."
- 2026-10-02 (sitting tk-kwmyg3): "a multi-PR workflow where only the final
  result lands on main in the final PR." Also: "every PR should have an
  approval… all are human gated."
- 2026-10-18 (mechanik chat): "a convoy can include multiple pieces of work, and
  that should all land as a single PR."

No kept record has the operator asking for a PR per bead.

## Timeline

| Date | Artifact | What changed |
|---|---|---|
| 05-05 | 8412dca89, GasTown roles copied in | The polecat cuts a branch per bead (`polecat/{{issue}}`). The refinery's default is `direct`, a push to the target with no PR. `mr` means one PR per bead. |
| 05-07 | tk-w7mjt, tk-jkesf, 6888c4119 | Owned convoys on `integration/<id>`: "the refinery merges polecat work back to the integration branch", then squashes to main "only when a complete unit of work is ready". |
| 05-19/20 | smoke-tests convoy (tk-yhh5mi, tk-3qis4y) | Children were fast-forward pushed onto the integration branch with no PR. The convoy never graduated. |
| 05-20 | #49 (tk-8de4p0 stamped `merge_strategy=pr`) | The first child PR into an integration branch. |
| 05-25 | tk-sma1xw, #68 | The refinery had pushed straight to another rig's main branch. The bead records "Operator's policy (2026-05-25): the entire loomington city defaults to `mr`". |
| 06-05 | the city's config sets `default_merge_strategy = "mr"` | Every bead opens its own PR whatever its target, convoy children included. No record shows convoy branches were considered. |
| 06-10 | #102 | A graduation PR carries to main the work its children had already merged through their own PRs. |
| 06-28 | #163 (tk-6d0vb.1.1), 40ea2d7a0 | A doc writes down the operator's model: "Every PR is owned by a convoy bead… a convoy has one stable PR head… A child contributes to the branch however it needs… There is no one-bead-one-commit rule… No bead lands on `main` except a convoy." The polecat and refinery flow did not change. |
| 07-21 | #197 (tk-4b9dr) | The formula's own default flips from `direct` to `mr`. |
| 07-23 | the city's config | `default_merge_strategy` leaves city.toml. The refinery formula's `mr` default keeps every unstamped bead in PR mode. |
| 08-25 | #465, the rewrite (9a6b86aea) | Deletes #163's doc. PR ownership moves to each work bead, its anchor, under invariant I4 "Every PR has exactly one owning anchor". Keeps the heading "an owned convoy is the PR unit". |
| 09-27 | #793 (tk-6bji7k.1) | The phase-checkpoint spec: "Each phase that needs a reviewed checkpoint… opens a child pull request". Also: "A bare commit with no pull request is still the right surface for scaffolding no one has to approve". |
| 09-27 on | #851 (tk-6bji7k.9) | The `base: integration` label and the "Approving it mints this phase" banner go on every PR into an integration branch. |
| 09-29 | #884 (tk-lz13i7), design-convoy spec | Approval only on the design child. Implementation PRs merge once checks pass. "All-in-one work has only gate 2; the graduation PR reviews everything at once." |
| 10-02 | sitting tk-kwmyg3 | Operator: "every PR should have an approval". |
| 10-03 | #994 (tk-sw5bu) | Convoy children (`integration/*`) keep their own PR "on purpose". Only a `polecat/*` target folds into an existing PR. |
| 10-06 | #966 (tk-yx2oqr.2), f7ed027d3 | Approval becomes universal. The commit notes that integration-branch PRs "could robot-merge on green with no review". |
| 10-07 | #1109 rework | The design-convoy spec now says each child's PR needs approval. |
| 10-10 | #936 | docs/design-convoy.md: "each child's PR onto the integration branch… pass through it". |

Merged child PRs into integration branches:
- Before 10-06, 21 of 25 had no operator review.
- All 4 graduation PRs had it (#102, #388, #843, #936).
- Since 10-06, 3 of 3 carry approval (#1109, #1271, #1277).

## What went wrong

1. **The machinery never treated the convoy as the PR unit.**
   - Each bead has had its own branch since 05-05.
   - Each bead has had its own PR since the 06-05 town-wide `mr` default. That default was set to stop direct pushes to another rig's main branch, and nothing shows convoy branches were considered.
2. **The operator's model was written down but never built.**
   - #163 described the convoy owning one PR, but the flow never changed to match.
   - The rewrite (#465) then deleted that doc and made one PR per bead the formal model. Only the old heading survived.
3. **It went unnoticed for months.** Child PRs merged on the city's checks, so the operator saw one PR per convoy.
4. **The multi-stage work then put each bead's PR in front of the operator.**
   - #793 made a stage "a child PR".
   - #851 labelled every PR into an integration branch a phase.
   - #966 required approval on every PR, matching the operator's 10-02 "every PR should have an approval".

In the operator's model the approval rule is right, because a PR is a body of
work. It multiplies reviews only because the system's PR is a bead.

## What exists today

**The per-bead path:**
- Branch: `polecat/<bead>` (formulas/mol-polecat-work.toml:750-758). The submit gate at :1474-1498 checks for it.
- PR: assets/scripts/pr-open.sh opens one with `--base "$target"` (`gh pr create` at :639).
- The refinery keeps `integration/*` targets on `mr` (formulas/mol-refinery-patrol.toml:625-655).
- docs/component-model.md:189 asserts I4.

**Ways several beads share one PR today:**
- Supplements (skills/prs/SKILL.md:64-99). One at a time, and the PR must already be open.
- Rework children, which push onto the PR's own branch.
- Fold-in for `polecat/*` targets (the mol-refinery-patrol merge-strategy block; specs/tk-sw5bu).
- pr-stack.sh, which lists in the PR body every bead whose work the PR carries.

None of these lets several sibling beads build one branch and open one PR at the end.

**Other relevant facts:**
- mol-polecat-work.toml:424-432 refuses an input convoy with more than one member. gascity core can hand a whole convoy to a formula as one input (internal/sling/sling_core.go:1975-1985).
- A child stamped `merge_strategy=direct` would probably be pushed onto the integration branch with no PR. This is inferred and undocumented; tk-sw5bu calls it a fast-forward "past the review gate".
- In gascity core, a convoy is a container bead with a merge setting (`direct`, `mr` or `local`) and a target its children inherit (internal/convoy/convoy_fields.go:12-18). The merge queue is pack behaviour.
- GasTown's refinery merged children with no PRs, then merged the convoy's branch to main as one unit.

## Open design questions for the fix

- **Landing a child without a PR:** how does a child's work reach its convoy's branch? Options are a direct push, extending fold-in to `integration/*`, or a convoy-level builder. Do the city's checks run per child, or once on the convoy's PR?
- **Multi-stage:** a stage convoy would land one PR into a parent integration branch, and the parent would then graduate to main. No spec describes this today; what was built is one integration branch per convoy.
- **What has to change:**
  - the anchor model's I4 (one owning bead per PR)
  - docs/design-convoy.md
  - the `base: integration` label text in docs/state-machine.md
  - the "phase" wording in pr-summary-region.sh and pr-status-label.sh
  - the mechanik dispatch doctrine

## Limits

- Claude transcripts on this host start 2026-09-18. The May and June operator words come from bead records and GitHub review comments.
- The 05-25 policy wording is quoted from bead tk-sma1xw's record, not from a transcript.
