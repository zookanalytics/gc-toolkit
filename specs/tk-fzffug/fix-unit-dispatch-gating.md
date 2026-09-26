---
name: Gating the review fix-unit's finding edges behind the validator
description: Why tk-fzffug fixes the two-handler collision by hanging the fix-unit's finding edges from the validator's must-fix ruling (not at dispatch) and hardening the declined/deferred close, and why the remaining eager-dispatch race is deferred to tk-v7qqux.
---

# Gating the review fix-unit's finding edges behind the validator

## The defect

When a PR review requests changes (signoff.sh) or a human feedback batch arrives
(pr-facts.sh unanswered-feedback arm), two handlers were minted for one review in
one pass: a rework fix-unit, and one finding per objection plus a mol-validate
validation pass. Both handlers were cross-wired at dispatch — `finding.sh
wire-fix-unit` hung a `fix-unit --blocks finding` edge onto **every** finding,
including ones still `unvalidated`.

The validator rules each finding later. Its `declined` disposition closes the
finding (`finding.sh set-disposition`), but the old close stripped only the
finding's own `finding --blocks anchor` edge, never the inbound `fix-unit -->
finding` edge. `bd` refuses to close a blocked issue, so the declined close
exited rc=2, the mol-validate triage step jammed, and the pool re-offered it into
the same rc=2 — a husk / pool-slot loop. Live incident: PR#833 review 5320516045,
anchor tk-6r2asi (finding tk-g1751x, fix-unit tk-c8sgep, validation pass
tk-mtoa69, triage tk-ab9vo8), surfaced by converse visit tk-u0b77y.

## What this bead changes

The fix-unit must block **only** the findings the validator rules must-fix, and a
declined or deferred finding must be free to close no matter what blocks it.

- `finding.sh set-disposition must-fix` hangs the `fix-unit --blocks finding`
  close-ordering edge from the ruling: it finds the anchor's open fix-unit
  (`anchor_fix_unit`, a live down-blocks child carrying `source_review_bead`) and
  wires it onto the finding as it rules that finding must-fix. So a finding the
  validator has not yet ruled — one it may decline — never carries an inbound
  fix-unit block.
- `finding.sh set-disposition declined` and `deferred` strip **every** inbound
  blocks edge on the finding (`strip_inbound_blocks`) before the close /
  reclassification, so an edge left by an earlier must-fix ruling this pass
  overturns cannot refuse the close.
- `signoff.sh` (request-changes) and `pr-facts.sh` (unanswered-feedback arm) no
  longer call `wire-fix-unit` at dispatch. They still wire the fix-unit's
  `blocks` edge onto the **anchor** (the merge hold), file findings, and open the
  validation pass.
- `test-harness.sh` gains an opt-in `STUB_ENFORCE_BLOCKS` knob modelling bd's
  "cannot close a blocked issue" refusal, so the rc=2 regression is reproducible
  hermetically. Off by default; existing suites are unaffected.

## Scope decision: the collision, not the whole dispatch-gate

The bead title asks to "gate the fix-unit dispatch behind the validator." The
full form of that gate — not routing/slinging the fix-unit until the validator
rules — is deferred to **tk-v7qqux**, for two reasons found in the code:

1. The validator (`formulas/mol-validate.toml`, triage-findings) explicitly does
   not mint or route fix units and names the gate authority as the owner. Moving
   the mint to gate-ensure means reconstructing the PR-context signoff/pr-facts
   hold at verdict time (branch, target, existing_pr/pr_number, prepare_mode, the
   objection summary) from the anchor and the closed review bead — a build, not a
   move.
2. The spec's fix-unit --> finding **close-cascade** (review-cycle-architecture.md,
   "Closing runs the edges backwards": gate-ensure closes each finding whose
   blockers have all closed) is not implemented. Nothing closes a must-fix finding
   when its fix-unit lands today. Moving the fix-unit mint post-ruling without that
   cascade would strand must-fix findings — open, holding the merge, with nothing
   to close them — which is worse than the race it removes.

So this bead removes the **collision** (the reported rc=2 jam) structurally and
makes it cannot-recur: the fix-unit blocks only ruled-must-fix findings, and a
declined/deferred disposition always closes. The remaining **race** — the fix-unit
is still routed at request-changes/feedback time, so an all-declined batch wastes
a rework worker and answers the operator twice — is tracked in tk-v7qqux, which
must build the close-cascade before moving the dispatch.
