---
name: Two-lane review quorum pilot — design, runbook, and caveats
description: Work record for tk-ehhpkh. Builds mol-review-quorum-signoff (two provider review lanes + a synthesizer that makes the single signoff) and wires it into the codex review dispatch behind a default-off env switch. Read before enabling the pilot on a live refinery, before widening or reverting it, and before assuming the fan-out is battle-tested — it is the rig's first fan-out formula and has not run a live end-to-end pour.
---

# Two-lane review quorum pilot

Work record for bead tk-ehhpkh — operator-approved slate item 4 / B1 (sitting
tk-nt5uda, resolved at visit tk-rfxy3e, 2026-09-20).

## Scope

Covers the pilot that lets a code review run as two reviewer lanes on
different providers, synthesized into one signoff verdict: the
`mol-review-quorum-signoff` formula, the default-off dispatch switch in
`gate-ensure.sh` / `refinery-reconcile.sh`, the amendment to mol-review's
single-pass rule, and how to enable, measure, and revert the pilot. It does
not cover the single-agent `mol-review` lifecycle (unchanged), the signoff
machinery (untouched), or the other slate items.

## Goal

Raise per-round finding yield so fewer anchors need a second whole-diff
review. Baseline to beat: 51% of anchors needed >=2 reviews (324/636, 2026-09).
The bet is that two independent reviewers on different providers catch, in one
round, findings that one reviewer would miss and a later round would surface —
removing rounds. It is a bet, measured then widened or reverted on the data.

## What ships

- `formulas/mol-review-quorum-signoff.toml` — two read-only reviewer lanes
  (`review-lane-one`, `review-lane-two`) that each apply mol-review's review
  rubric to the diff and write a `review-quorum.lane.v1` object to their step
  bead's `gc.output_json`, plus `synthesize-and-signoff` (needs both lanes)
  that reads both lane outputs, runs the suite once at the pinned commit,
  unions and dedupes the findings, writes `findings.md`/`findings.json`, and
  makes THE ONE `signoff.sh` call.
- `gate-ensure.sh` — new `--review-formula <name>` (default `mol-review`) and
  repeatable `--sling-var k=v` (forwarded verbatim to the pour). Inert unless
  passed.
- `refinery-reconcile.sh` — reads `REFINERY_RECONCILE_REVIEW_FORMULA` (default
  `mol-review`) and, when it names the quorum, derives the lane config from the
  refinery's binding prefix and forwards it to gate-ensure.
- `mol-review.toml` — the "one agent, single pass ... no parallel review pass"
  hard rule is amended to permit the quorum while keeping the honest-single-pass
  invariant and one-verdict-per-claim.

## Preserved invariants

- **One verdict per claim.** The synthesizer makes the single `signoff.sh`
  call; the lanes never call it.
- **COMMENT-only verdict.** `signoff.sh` is untouched; it posts the artifact as
  a PR comment and never runs `gh pr review --approve`.
- **The signoff round cap stays dynamic.** `signoff.sh` still owns it (rework
  rounds since the last operator-feedback batch, reset by a new batch). Nothing
  in the quorum counts rounds, and no compile-time loop budget replaces it.

## Design decisions

- **Distinct rig name, not `mol-review-quorum`.** The core (city-owned) pack
  ships an inert `mol-review-quorum` scaffold; a same-named rig formula would
  collide. `mol-review-quorum-signoff` is gc-toolkit's wired variant and reads
  as "the quorum shape that ends in a signoff".
- **Plain fan-out steps, no `[steps.retry]`.** The retry/attempt-bead machinery
  is novel in this rig and its close idiom differs from `step-close.sh`'s. A
  dead lane is recovered by the existing stranded-step repair, the same as any
  pool step. Soft-fail retry (so the synthesizer proceeds on one lane when the
  other's provider is down) is the first future hardening.
- **Provider is the lane axis, not model.** Each lane runs on its pool's default
  work model (claude opus, codex default) and self-reports the model in its
  output. Codex has no configured model label to pin and an empty required var
  risks the pour, so the per-lane model vars are dropped. Model pinning is a
  straightforward future add (reintroduce `lane_*_model` + `opt_model`).
- **A script/agent synthesizer, not the Go finalizer.** `internal/reviewquorum`
  ships `Finalize`, but it lives in gascity (an upstream change to wire), it is
  invoked by nothing, and it produces only the durable `Summary` — it does not
  write `findings.md`/`findings.json` or call `signoff.sh`. The agent-executed
  synthesis step does the merge and the signoff seam, entirely inside this rig.
- **Lanes reference mol-review's rubric, not a copy.** The lane steps point at
  `formulas/mol-review.toml`'s review step for the "What to check" list and the
  work-quality standards, keeping one source of truth for the review method.
- **Lanes do not run the suite; the synthesizer runs it once.** Tests are
  deterministic, so one run at the pinned commit serves the quorum. A second
  provider costs a reasoning pass, not a second build.

## Runbook

### Enable (operator go-live)

Set one env var on the refinery so `refinery-reconcile.sh` pours the quorum:

```
REFINERY_RECONCILE_REVIEW_FORMULA=mol-review-quorum-signoff
```

Defaults derived from the refinery's binding prefix put lane one on the codex
pool (`<rig>/gc-toolkit.polecat-codex`, provider codex), lane two on the general
pool (`<rig>/gc-toolkit.polecat`, provider claude), and the synthesis on the
general pool. Each is overridable:
`REFINERY_RECONCILE_LANE_ONE_ID|_PROVIDER|_TARGET`,
`REFINERY_RECONCILE_LANE_TWO_ID|_PROVIDER|_TARGET`,
`REFINERY_RECONCILE_SYNTHESIS_TARGET`.

### Measure (against the 51% baseline)

Reviews-per-anchor is a group-by over the review-bead population — each carries
`task_kind=review` and `anchor_bead`. `--limit=0` is required for the
client-side filter, and `--status` must name closed explicitly (a
metadata-field query defaults to open only):

```
gc bd list --metadata-field task_kind=review \
  --status=open,in_progress,blocked,closed --limit=0 --json \
| jq '[.[] | .metadata.anchor_bead // empty] | group_by(.) | map(length) as $c
      | {anchors: ($c|length),
         needed_2plus: ([$c[]|select(.>=2)]|length),
         pct_2plus: (([$c[]|select(.>=2)]|length) * 100 / ($c|length))}'
```

`pct_2plus` is the number to compare to the 51% baseline. Scope it to the pilot
window (reviews created after the enable, e.g. add a `select(.created_at >= ...)`
on the beads) and compute the baseline the same way over the prior window; the
metric is formula-agnostic because the quorum still produces one review bead per
gate, so a like-for-like comparison holds.

### Revert

Unset `REFINERY_RECONCILE_REVIEW_FORMULA` (or set it back to `mol-review`). No
code change, no redeploy — the next cadence pass slings `mol-review` again.

## Cost model

Two lanes plus a synthesis is three sessions per review round, against one
today. It pays only if the removed second-review rounds exceed the added
sessions. 2 lanes only for the pilot; widen (more lanes/providers) or revert on
the measured `pct_2plus`.

## Caveats — read before enabling on a live refinery

- **This is the rig's first fan-out formula.** gc-toolkit has no other
  multi-lane, multi-session-routed formula. What is validated: the formula
  compiles with the intended fan-out -> join -> finalize topology (checked in an
  isolated synthetic city), and the dispatch wiring passes the formula and lane
  vars through (hermetic tests in `gate-ensure.test.sh` and
  `refinery-reconcile.test.sh`). What is NOT validated: a live end-to-end pour —
  two real provider sessions reviewing, the synthesizer reading both lane
  outputs, and the single signoff landing. **Enable it on one real review and
  watch it through before widening.**
- **Enabling is a go-live on the review artery.** Default off is deliberate:
  every anchor's merge flows through this dispatch. Merging this changes no live
  review; the env var does.
- **A dead lane is reduced coverage, and a never-closed lane stalls that one
  review.** The synthesizer treats a missing or failed lane as reduced coverage
  and will not approve blindly on one lane. A lane whose session dies without
  closing leaves the review blocked until the stranded-step repair re-offers the
  lane step — the same recovery as any pool step, not a new stall class.
- **PR #615 (review-gates) overlaps.** It is open but stalled
  (CONFLICTING/CHANGES_REQUESTED as of 2026-09-16) and touches `signoff.sh`,
  `gate-ensure.sh`, `pr-facts.sh`, and `mol-review.toml` — though not
  mol-review's lines 29-31. Whichever lands second resolves the conflict.

## Not done (future work)

- Soft-fail retry on the lanes so the synthesizer proceeds on one lane when the
  other provider is unavailable.
- Per-lane model pinning (`lane_*_model` + `opt_model`).
- Wiring `internal/reviewquorum.Finalize` (an upstream gascity change) if a
  deterministic merge is wanted over the agent synthesis.
- A dedicated claude-provider review pool, if mixing lane-two/synthesis review
  load into the general polecat pool proves contentious.
- A committed reviews-per-anchor metric script, if the runbook recipe proves
  worth making permanent.
