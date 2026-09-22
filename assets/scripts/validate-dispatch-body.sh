#!/usr/bin/env bash
# validate-dispatch-body — emit the dispatch note carried by a validation-pass
# bead, on stdout. The method itself is formulas/mol-validate.toml, attached to
# the bead at dispatch (gc sling --on mol-validate); this note names it, states
# the recovery path for a bead that lost its poured workflow, and forbids
# substituting any other method — the drift a bare title invites.
# Usage: validate-dispatch-body.sh [--note <text>]  (--note appends dispatch-
# specific context, e.g. "this batch is a human feedback set" from pr-facts.sh).
# Exit 0 always: a dispatch is never blocked on prose.
# Callers: signoff.sh and pr-facts.sh — the two surfaces that OPEN a validation
# pass, on a machine request-changes batch and a human feedback batch. (gate-
# ensure.sh dispatches the validator onto an open pass; it opens none, so it
# builds no note.)
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: validate-dispatch-body.sh [--note <text>]

Prints the validation-pass bead's dispatch note on stdout.

  --note <text>   Dispatch-specific context appended as a final section.
U
}

NOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --note) NOTE="${2-}"; shift 2 || shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "validate-dispatch-body: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

cat <<'H'
## Method: `formulas/mol-validate.toml`

This is a **dispatched validation pass**. Its method is the `mol-validate`
formula, attached to this bead at dispatch (`gc sling --on mol-validate`); the
formula's step descriptions ARE the method — follow them in order.

**Recovery:** if you hold this bead with no poured workflow, run
`gc formula show mol-validate` and follow its steps in order. In recovery there
is no input convoy: VALIDATION_PASS is this bead itself — substitute its id
wherever the steps derive VALIDATION_PASS from the convoy.

**Do not substitute any other method.** Do not match a review- or validate-
shaped skill out of your catalog, and do not improvise one. **One agent, single
pass. No fan-out**: read the finding batch yourself and rule it yourself — no
subagents, no persona validators, no parallel validation pass. You judge
convergence; you do not re-run the review.

**What to validate** is on this bead's metadata: `anchor_bead` (the gating
anchor), `check_name` (the lane whose batch this pass rules), and `reviewed_oid`
(the head the batch was produced at). The findings to rule are the open
`task_kind=finding` beads on that anchor for that lane.

**What the pass writes**: a `finding.disposition` on each finding via
`finding.sh set-disposition` (must-fix, deferred, or declined — decisions 1 and
2; a human-sourced finding is ruled on its merits like a machine one — the
operator is a highly informed peer, not an authority the pass may not overrule —
but declining a human objection owes them an answer, passed as `--reply` and
posted to their PR thread by pr-facts.sh's write-back, never a silent decline; a
re-raise re-blocks because the closed finding re-adopts fresh on re-review),
and one convergence outcome via `review-outcome.sh` whose shape follows
`check_name` (decision 3). A reviewer's lane batch backs its lane (`back-lane`)
on convergence, or supersedes it (`supersede-lane`) when a fresh whole-diff
review is warranted. A `human` batch is anchor-wide: unconverged, it supersedes
every lane the anchor's `check_set` declares (`supersede-anchor`); converged, it
writes no outcome, leaving the declared lanes' green and the open must-fix
findings to hold the merge. It never stamps a `check.<lane>` marker, never closes
or routes the anchor, and never runs `gh pr review --approve` — the city does not
approve PRs. Closing the validation-pass bead is the terminal step; the
dispositions and any convergence outcome above are what carry the lane state.
H

if [ -n "$NOTE" ]; then
  echo
  echo "---"
  echo
  echo "## Context from the dispatch"
  echo
  printf '%s\n' "$NOTE"
fi
