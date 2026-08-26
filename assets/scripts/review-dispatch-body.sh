#!/usr/bin/env bash
# review-dispatch-body — emit the dispatch note carried by a signoff review
# bead, on stdout. The frame is formulas/mol-review.toml, attached to the bead
# at dispatch (gc sling --on mol-review); this note names it, states the
# recovery path for a bead that lost its poured workflow, and names the METHOD
# for the gate being reviewed so the reviewer cannot substitute one out of its
# own catalog — the fan-out drift a bare title invites.
# Usage: review-dispatch-body.sh [--check-name <gate>] [--note <text>]
#   --check-name  the gate this review satisfies (default codex); selects the
#                 gate-method section. An undeclared gate gets the frame plus
#                 an explicit "no method declared" line, never a guess.
#   --note        dispatch-specific context appended as a final section.
# Exit 0 always: a dispatch is never blocked on prose.
# Callers: gate-ensure.sh, pr-facts.sh.
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: review-dispatch-body.sh [--check-name <gate>] [--note <text>]

Prints the review bead's dispatch note on stdout.

  --check-name <gate>   the gate being reviewed; selects the method section.
  --note <text>         Dispatch-specific context appended as a final section.
U
}

NOTE=""
CHECK_NAME="codex"
while [ $# -gt 0 ]; do
  case "$1" in
    --note) NOTE="${2-}"; shift 2 || shift ;;
    --check-name) CHECK_NAME="${2-}"; shift 2 || shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "review-dispatch-body: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ -n "$CHECK_NAME" ] || CHECK_NAME="codex"

cat <<'H'
## Method: `formulas/mol-review.toml`

This is a **dispatched signoff review**. Its method is the `mol-review`
formula, attached to this bead at dispatch (`gc sling --on mol-review`); the
formula's step descriptions ARE the frame — follow them in order — and the
gate method named below governs what you read and judge inside them.

**Recovery:** if you hold this bead with no poured workflow, run
`gc formula show mol-review` and follow its steps in order. In recovery there
is no input convoy: REVIEW_BEAD is this bead itself — substitute its id
wherever the steps derive REVIEW_BEAD from the convoy.

**Do not substitute any other review method.** Use the gate method this
dispatch names and no other: do not match a review-shaped skill out of your
catalog, and do not improvise one. **One agent, single pass. No fan-out**:
read the diff yourself, run the tests yourself, write the verdict yourself —
no subagents, no persona reviewers, no parallel review pass.

**What to review** is on this bead's metadata: `pr_number` (post-open) or
`review_branch`/`review_base` (pre-open), plus `anchor_bead` for the intent.
**Where the verdict goes**: `signoff.sh --review-bead <this bead> --verdict
approve|request-changes` exactly once — it owns the mechanics. Never
`gh pr review --approve` — the city does not approve PRs.
H

echo
echo "---"
echo
printf '## Gate method: `%s`\n' "$CHECK_NAME"
echo
case "$CHECK_NAME" in
  codex)
    cat <<'M'
The standing correctness review. The method is the `mol-review` steps
themselves: read the whole diff, run the tests the diff touches at the pinned
commit, hold the output to the operator profile, and grade findings P0/P1/P2
with file:line. Placement and architecture belong to the `arch` gate; judge
whether the change is correct and safe as merged.
M
    ;;
  triage)
    cat <<'M'
`skills/review-triage/SKILL.md` (Gas City: `gc-toolkit.review-triage`). Read
it before the diff.

Triage classifies, it does not judge. Read the repo's charter
(`docs/review-charter.md`), skim the diff, and decide which dedicated reviews
this change warrants from the charter's declared gate menu. Adding nothing is
the expected common case. Record the decision on the same verdict call:

    signoff.sh --review-bead <this bead> --verdict approve \
      --add-gates <gate>[,<gate>] --justification "<one line, per gate>"

Widening is monotonic and `signoff.sh` enforces it — you cannot remove a gate.
The one sanctioned narrowing is `--waive-gates`, accepted only for a gate the
charter marks waivable. Correctness findings are the `codex` gate's, not
yours.
M
    ;;
  arch)
    cat <<'M'
`skills/arch-review/SKILL.md` (Gas City: `gc-toolkit.arch-review`). Read it
before the diff.

Read exactly three things: the charter (`docs/review-charter.md`), this bead
and its anchor, and the diff. Not the whole repo. Judge placement against the
declared layer map and the admission test, not correctness — `codex` owns
correctness on this same commit.

A design objection is a decision, not a defect: use
`--verdict escalate` (stamps `exception@<head>` and files one visit framing
the choice) rather than handing back a rework child nobody can converge.
M
    ;;
  *)
    cat <<'M'
No gate method is declared for this gate in the dispatching pack. Follow the
`mol-review` steps as written, hold the diff to the repo's charter
(`docs/review-charter.md`) where one exists, and say in your verdict's
coverage line that the gate had no declared method — a gate whose method is
undeclared is a charter gap worth an observation.
M
    ;;
esac

if [ -n "$NOTE" ]; then
  echo
  echo "---"
  echo
  echo "## Context from the dispatch"
  echo
  printf '%s\n' "$NOTE"
fi
