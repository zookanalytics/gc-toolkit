---
name: First-reaction triage on merits, and the validating closer
description: Record of tk-mw3bso — removing the categorical operator-origin gate so first-reaction triages every bead on its merits (Lever 1), and adding a `close` disposition that routes a confident no-op to a validating closer (mol-validate-close) instead of a recommend-close human card (Lever 2). Carries the 2026-09-19 board-card measurement and the closer design decision.
---

# First-reaction triage on merits, and the validating closer

first-reaction triages an un-slung bead into a disposition and never closes a
bead. Two hard paths used to force a human card even when the triage would move
work forward: an `gc.origin=operator` gate, and the absence of any exit for a
confident no-op other than a recommend-close card. This bead removes the first
and adds an exit for the second. The operator ruling (converse sitting on
tk-jr8rw, 2026-09-19, "go" with the cheap-model constraint) is the mandate:
first-reaction triages and routes on a cheap model; a capable downstream worker
validates and resolves, including close, only when fully confident.

## Measurement (helm board, 2026-09-19)

The channels this change targets, measured over the non-closed subjects
carrying `gc.first_reaction=ruling` (the beads first-reaction sent to a human
card):

| Channel | Count | Drained by |
|---|---|---|
| operator-origin (`gc.origin=operator`) | 26 | Lever 1 — triaged on merits, most route or hold |
| recommend-close (takeaway/reason `recommend close`) | 11 | Lever 2 — routed to the validating closer |
| genuine question (neither) | 8 | unchanged — a real fork stays a card |
| **total** | **45** | |

The two mechanical channels are 37 of 45 (82%). The classification is by
metadata: operator-origin wins when both apply, so the 26 bucket still contains
captures that are also no-ops or genuine forks — Lever 1 sends those to the
triage rubric, which routes or closes the reversible ones and cards only the
forks. The 8 "genuine" also include a few actions and self-resolved findings
phrased without the `recommend close` prefix, so the true operator-only residue
is smaller than 8. Directionally: the change drains the mechanical channels and
leaves genuine forks as cards, which is the acceptance.

Query used (subject side, non-closed):
`gc bd list --metadata-field gc.first_reaction=ruling --status=open,in_progress,blocked --json`.

## Lever 1 — triage every bead on its merits

`assets/scripts/first-reaction-dispose.sh` no longer refuses the actionable and
blocked exits on `gc.origin=operator`. Origin is a fact the reacting agent
weighs, not a gate the script enforces. The guardrail — a genuine fork, an
irreversible or destructive action, or a policy call still goes to a human —
lives in the reacting agent's rubric (`formulas/mol-first-reaction.toml`),
which is what chooses the disposition; the script performs the one it is given.
The route-deliverability and same-store guards stay: they catch a disposition
that cannot land, whatever the reacting agent intended.

## Lever 2 — a confident no-op routes to a validating closer

first-reaction runs on a cheap model and must not have the last word on a
close. A confident no-op takes a new `close` disposition, which routes the bead
to a capable pool instead of parking a recommend-close card. The pool runs a new
formula, `formulas/mol-validate-close.toml`, which re-checks the no-work
conclusion against live state and closes the subject (`gc.work_outcome=no-op`)
when it holds, or files a visit when it does not. first-reaction never closes:
the record and the route are its act, and the closer's own confident check is
what closes.

### Why a new formula, run by the existing pool

The `actionable` exit routes a raw bead with `gc-helm takeaway --release
--route`, which stamps no formula, so the pool runs its default,
`mol-polecat-work`. That formula implements code and hands to the refinery; its
store-only arm names a disposition for someone else to close, and it never
closes a bead. So a no-op routed as actionable would not be closed. The close
disposition therefore hands the bead to a dedicated formula, `mol-validate-close`,
on the rig's capable `polecat` pool. No new pool is defined: a dedicated closer
pool would need city-level config outside this pack, and the operator's model
(cheap triage → capable worker closes) is satisfied by the pool the city already
runs.

### The closer is deferred, not poured beside the live reaction

`first-reaction-dispose.sh`'s close exit runs from `mol-first-reaction`'s own
terminal step, so the subject is still tracked by a live reaction workflow.
Pouring `mol-validate-close` onto it there would leave the bead driven by two
dispatch surfaces at once, against `docs/reference/specs/formula-spec-v2.md` §3
("one live dispatch surface per unit of work"). So the close exit DEFERS: the
formula's `advance-and-drain` block resolves this reaction's own workflow root
and passes it as `--after-workflow`, the script holds the bead on that root and
arms a deferred dispatch (`deferred-dispatch.sh`), and the deferred-dispatch
reconcile pass slings `gc sling <pool> <bead> --on mol-validate-close` once the
root closes and the bead is the sole live workflow's target. Run by hand on a
bead with no live workflow, `--after-workflow` is omitted and the closer is
slung immediately.

The installed gc (v1.4.1) would not refuse the immediate sling: its
convoy-tracked-workflow guard is scoped to `(formula, bead)`, so distinct
formulas on one bead are permitted concurrent work
(`checkLegacySourceWorkflowConflict` → `liveConvoyTrackedWorkflowRoots`,
`internal/sling/sling_attachment.go`). Deferring is what keeps the
one-live-surface invariant regardless of gc version, and it matches the stricter
convoy-first guard `docs/gascity-routing-model.md` describes, under which the
immediate sling would be refused (`already has live workflow`) and the terminal
step would re-offer into that refusal.

### Close authority, and its guardrail

This is the one bead-closer outside the refinery. `docs/authority-map.md`
carries the grant: mol-validate-close closes a no-work subject on its own
re-derived check, and never a bead that carries a non-closed `merge_result`
(the refinery's, on a verified merge) or one whose close needs a successor
(`bead-rehome.sh`'s). Any doubt files a visit rather than closing. The
confidence gate is the formula's `validate-and-resolve` step: it treats the
reaction's `gc.first_reaction_reason` as a claim to verify, not a verdict.

### Never a double-sling

`close` records `gc.first_reaction=close` before the act, hands off the closer
(arms the deferred dispatch, or slings directly when run by hand with no live
workflow), and only then stamps `gc.proactive_reaction=1` — the marker the
second-dispose guard and the scan read. A handoff that fails leaves the record
without that marker, so the documented re-run resumes rather than queuing a
second closer.

## Acceptance mapping

- An operator-origin bead with a clear reversible action is routed or held, not
  carded — Lever 1 (`ORIGIN` tests in `first-reaction-dispose.test.sh`).
- A confident no-op routes to a validating closer, no recommend-close card —
  Lever 2 (`CLOSE` tests; the closer formula).
- Genuine forks, irreversible or destructive actions, and policy calls still
  card — the rubric's `ruling` exit, unchanged in mechanism.
- first-reaction still never closes a bead — the `NEVERCLOSE` test still holds:
  the script has no `status=closed` path; the close disposition routes.
- The tk-6d8uo0 shape (an operator capture bundling an obvious sub-fix with a
  genuine fork) no longer sweeps the mechanical part into the human wait: the
  rubric directs filing the mechanical part as its own bead and routing it,
  leaving the fork as the ruling.

## Verification notes

- `first-reaction-dispose.test.sh` and `gate-visit.test.sh` pass; the latter
  validates the closer's escalate block against the canonical gate-visit
  invariants.
- `mol-validate-close.toml` parses and matches the step/needs/metadata schema of
  the known-good `mol-review.toml`. Its live compile (`gc formula show`,
  `gc sling --on`) resolves the formula by filename from `formulas/`, so it is
  exercised once this lands in the rig checkout; it cannot be compiled from an
  unregistered worktree path pre-merge.
- The diff-scoped learned-lint (`tools/lint-learned.sh` over the changed files)
  is clean. A whole-tree lint of `main` reports two pre-existing
  `mktemp-untemplated` findings in `gh-origin-guard.test.sh` and
  `worktree-setup.test.sh`, both outside this diff and dormant under the
  diff-scoped gate.
