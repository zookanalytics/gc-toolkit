#!/usr/bin/env bash
# review-dispatch-body — emit the dispatch note carried by a signoff review
# bead, on stdout. A review answers two orthogonal questions and this note
# carries both: the FORMULA is the dispatch topology (single-agent mol-review or
# the two-lane quorum), attached to the bead at dispatch (gc sling --on); the
# CHECK is the concern the review verifies, whose generic method is named here
# and whose rig-local extension, if the reviewed commit carries one, is appended
# to it. The note names the method, states the recovery path for a bead that
# lost its poured workflow, and forbids substituting any other method — the
# fan-out drift a bare title invites.
# Usage: review-dispatch-body.sh [--note <text>] [--formula <name>]
#                                [--check-name <check>] [--reviewed-oid <oid>]
# Exit 0 always: a dispatch is never blocked on prose.
# Caller: gate-ensure.sh.
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: review-dispatch-body.sh [--note <text>] [--formula <name>] [--check-name <check>] [--reviewed-oid <oid>]

Prints the review bead's dispatch note on stdout.

  --note <text>       Dispatch-specific context appended as a final section.
  --formula <name>    The review formula being attached (default mol-review).
                      mol-review emits the single-agent method note; any other
                      formula (e.g. the two-lane quorum) emits a note that
                      defers method and verdict path to that formula's steps.
  --check-name <check> The check this review satisfies (default correctness).
                      Selects the generic method section for that check.
  --reviewed-oid <oid> The commit under review. When the reviewed repo carries
                      docs/review-<check>.md at that commit, it is appended to
                      the generic method as the rig's local extension.
U
}

NOTE=""
FORMULA="mol-review"
CHECK_NAME="correctness"
REVIEWED_OID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --note) NOTE="${2-}"; shift 2 || shift ;;
    --formula) FORMULA="${2:-mol-review}"; shift 2 || shift ;;
    --check-name) CHECK_NAME="${2:-correctness}"; shift 2 || shift ;;
    --reviewed-oid) REVIEWED_OID="${2-}"; shift 2 || shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "review-dispatch-body: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ -n "$CHECK_NAME" ] || CHECK_NAME="correctness"

# --- The formula frame: the dispatch topology --------------------------------
if [ "$FORMULA" = "mol-review" ]; then
cat <<'H'
## Method: `formulas/mol-review.toml`

This is a **dispatched signoff review**. Its method is the `mol-review`
formula, attached to this bead at dispatch (`gc sling --on mol-review`); the
formula's step descriptions ARE the frame — follow them in order — and the
check method named below governs what you read and judge inside them.

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
`gh pr review --approve` — the city does not approve PRs. If it refuses
because a rebase took your pinned commit off the branch, do not re-submit the
same verdict: review the head it names and write the verdict that commit
earns.
H
else
cat <<'H' | sed "s|__FORMULA__|$FORMULA|g"
## Method: `formulas/__FORMULA__.toml`

This is a **dispatched signoff review** conducted by the `__FORMULA__`
formula, attached to this bead at dispatch (`gc sling --on __FORMULA__`). The
formula's step descriptions ARE the frame — follow the step you hold, in
order — and the check method named below governs what you read and judge. Do
not substitute a review-shaped skill from your catalog, and do not improvise a
verdict path: the formula decides how the review is conducted, how many lanes
read the diff, and which of its steps makes the single verdict.

**Recovery:** if you hold this bead with no poured workflow, run
`gc formula show __FORMULA__` and follow its steps in order.

**What to review** is on this bead's metadata: `pr_number` (post-open) or
`review_branch`/`review_base` (pre-open), plus `anchor_bead` for the intent.
H
fi

# --- The check section: the concern this review verifies ----------------------
# The generic method is pack content; a rig may extend it (below). Each arm
# names what the check judges, never how many lanes read it (that is the
# formula's question above). A shared specialist stance precedes every
# non-baseline arm, emitted once so no specialist skill or arm restates it;
# correctness and triage are exempt, being the baseline that holds its own
# stance in its own arm.
echo
echo "---"
echo
printf '## Check: `%s`\n' "$CHECK_NAME"
echo
case "$CHECK_NAME" in
  correctness|triage) : ;;   # baseline: its own stance is in its arm, below
  *)
    cat <<'S'
**The specialist stance.** Every specialist check holds it, so no check's skill
or arm below restates it. You are the author's peer and the gatekeeper of the
concern you own. You raise the bar on what the city ships; you do not wave a
change through because its bead said to build it or its author worked hard.
Enforce through findings and never edit: a gap is the author's to fix, and you
touch the anchor only through `signoff.sh`. Correctness is the `correctness`
check's on this same commit, not yours; a concern another check owns is noted in
your verdict body and left to that check, never folded into your verdict. Read
the reference docs your check stewards, at the reviewed commit, before you judge;
a review that has not read what it holds the change to cannot hold it. File an
issue this change did not cause as its own bead, independent drift in the docs
you steward included. Judge fix-now versus follow-up, and name anything you defer
in the verdict body, which is posted where the change lands. One `signoff.sh
--review-bead <this bead> --verdict approve|request-changes` carries the verdict,
exactly once; never `gh pr review`, because the city does not approve its own PRs.

S
    ;;
esac
case "$CHECK_NAME" in
  correctness)
    cat <<'M'
The standing correctness review. Judge whether the change is correct and safe
as merged: read the whole diff, run the tests it touches at the pinned commit,
and hold it to the work-quality standards, grading findings P0/P1/P2 with
file:line. This is the concern, not a tool — no reviewer is presumed.
M
    ;;
  triage)
    cat <<'M'
Classify, do not judge. Whether the change is correct is the `correctness`
check's question and it is dispatched separately. Yours is narrower: which
specialist checks does this diff warrant? Read the check index
(`review-checks.toml`) at the reviewed commit, skim the diff, and add the
checks it warrants — no more. Adding nothing is the expected common case.

Record the decision on one verdict call, which both greens triage and widens
the anchor's check_set:

    signoff.sh --review-bead <this bead> --verdict approve --add-gates <check>[,<check>]

Widening is monotonic and `signoff.sh` enforces it: you cannot remove a check,
and only a triage verdict may add one. See `skills/review-triage/SKILL.md` for
the method. Correctness findings are the `correctness` check's, not yours.
M
    ;;
  demo)
    cat <<'M'
`skills/gc-demo-script/SKILL.md` then `skills/demo-capture/SKILL.md`. One method
in two steps: the first reads the anchor and the diff and writes a
`demo:capture`-format script, the second drives the browser from that script and
records the narrated video. Judge what the recording proves, not what the diff
claims. If no demo can be recorded, that is a finding against the change, not a
reason to approve it.
M
    ;;
  arch)
    cat <<'M'
The Architect — steward and gatekeeper of the repo's high-level architecture.
Read the architecture reference docs before you judge: `docs/architecture.md`
and the `docs/architecture/` directory it anchors; a review that has not read
the architecture cannot hold a change to it. Judge whether the change leverages
the existing architecture or works against its grain, and whether it moves the
architecture — if so, whether that move is justified and recorded in the
architecture docs in this same PR. The verdict is binary: approve when the
change fits, request changes otherwise (a moved architecture whose matching doc
update is not in the PR, or a move a design fitting the current architecture
would not have needed). `skills/review-arch/SKILL.md` carries the full method.
M
    ;;
  pm)
    cat <<'M'
`skills/review-pm/SKILL.md`. The product lens: judge whether the change is the
right thing for the people the product serves — the outcome its anchor named,
not a proxy — against the product goals (`docs/product-goals.md`, which names
who they are), then whether the PR lets the operator decide. Push back when the
diff does what its bead said but not what those people need. Grading a recording
is `demo`'s; your only demo concern is a change the operator must watch to trust
that the PR leaves unwatchable.
M
    ;;
  *)
    cat <<M
No generic method is declared for the \`$CHECK_NAME\` check in the dispatching
pack. Follow the \`mol-review\` steps as written, hold the diff to the reviewed
repo's own method for this check where one exists, and say in your verdict's
coverage line that the check had no declared method — an undeclared method is a
gap worth an observation.
M
    ;;
esac

# The rig's local extension, appended to the generic method — read from the
# COMMIT UNDER REVIEW, never the working tree, so a branch is judged against the
# method its own commit declared. Absent is the common case and changes nothing.
if [ -n "$REVIEWED_OID" ]; then
  EXT=""
  for root in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do
    [ -n "$root" ] || continue
    EXT=$(git -C "$root" show "$REVIEWED_OID:docs/review-$CHECK_NAME.md" 2>/dev/null) && [ -n "$EXT" ] && break
    EXT=""
  done
  if [ -n "$EXT" ]; then
    echo
    printf '### Rig extension: `docs/review-%s.md` @ %.12s\n' "$CHECK_NAME" "$REVIEWED_OID"
    echo
    printf '%s\n' "$EXT"
  fi
fi

if [ -n "$NOTE" ]; then
  echo
  echo "---"
  echo
  echo "## Context from the dispatch"
  echo
  printf '%s\n' "$NOTE"
fi
