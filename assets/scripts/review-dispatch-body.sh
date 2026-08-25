#!/usr/bin/env bash
# review-dispatch-body — emit the dispatch note carried by a signoff review
# bead, on stdout. The method itself is formulas/mol-review.toml, attached to
# the bead at dispatch (gc sling --on mol-review); this note names it, states
# the recovery path for a bead that lost its poured workflow, and forbids
# substituting any other method — the fan-out drift a bare title invites.
# Usage: review-dispatch-body.sh [--note <text>]  (--note appends dispatch-
# specific context, e.g. a stale-gate "the head moved, re-review it" note).
# Exit 0 always: a dispatch is never blocked on prose.
# Callers: gate-ensure.sh, pr-facts.sh.
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: review-dispatch-body.sh [--note <text>]

Prints the review bead's dispatch note on stdout.

  --note <text>   Dispatch-specific context appended as a final section.
U
}

NOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --note) NOTE="${2-}"; shift 2 || shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "review-dispatch-body: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

cat <<'H'
## Method: `formulas/mol-review.toml`

This is a **dispatched signoff review**. Its method is the `mol-review`
formula, attached to this bead at dispatch (`gc sling --on mol-review`); the
formula's step descriptions ARE the method — follow them in order.

**Recovery:** if you hold this bead with no poured workflow, run
`gc formula show mol-review` and follow its steps in order. In recovery there
is no input convoy: REVIEW_BEAD is this bead itself — substitute its id
wherever the steps derive REVIEW_BEAD from the convoy.

**Do not substitute any other review method.** Do not match a review-shaped
skill out of your catalog, and do not improvise one. **One agent, single
pass. No fan-out**: read the diff yourself, run the tests yourself, write
the verdict yourself — no subagents, no persona reviewers,
no parallel review pass.

**What to review** is on this bead's metadata: `pr_number` (post-open) or
`review_branch`/`review_base` (pre-open), plus `anchor_bead` for the intent.
**Where the verdict goes**: `signoff.sh --review-bead <this bead> --verdict
approve|request-changes` exactly once — it owns the mechanics. Never
`gh pr review --approve` — the city does not approve PRs.
H

if [ -n "$NOTE" ]; then
  echo
  echo "---"
  echo
  echo "## Context from the dispatch"
  echo
  printf '%s\n' "$NOTE"
fi
