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
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat >&2 <<'U'
usage: review-dispatch-body.sh [--note <text>] [--formula <name>] [--check-name <check>] [--reviewed-oid <oid>]

Prints the review bead's dispatch note on stdout.

  --note <text>       Dispatch-specific context appended as a final section.
  --formula <name>    The review formula being attached (default mol-review).
                      mol-review emits the single-agent method note; any other
                      formula (e.g. the two-lane quorum) emits a note that
                      defers method and verdict path to that formula's steps.
  --check-name <check> The check this review satisfies (default correctness),
                      in any case: it is matched by its name case-folded, as
                      the check index's resolver matches a check_set token.
                      Selects the check section, which names the method skill
                      the reviewer loads.
  --reviewed-oid <oid> The commit under review. When the reviewed repo carries
                      docs/review-<check>.md at that commit, it is appended to
                      the note as the rig's local extension of the method.
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
# A check is known by its name case-folded, the rule review-checks.sh resolves a
# check_set token by, and the caller passes the token in the case the anchor's
# check_set wrote it. Folding it once here means the stance, the method skill,
# the index row and the rig extension below are all looked up by the check
# itself, whatever case its token was written in.
CHECK_NAME=$(printf '%s' "$CHECK_NAME" | tr '[:upper:]' '[:lower:]')

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

**Do not substitute any other review method.** Load the method skill the
check section below names, and no other review-shaped skill out of your
catalog; do not improvise one. **One agent, single pass. No fan-out**: read
the diff yourself and write the verdict yourself — no subagents,
no persona reviewers, no parallel review pass.

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
order — and the check method named below governs what you read and judge.
Load the method skill the check section names and no other review-shaped
skill from your catalog, and do not improvise a verdict path: the formula
decides how the review is conducted, how many lanes read the diff, and
which of its steps makes the single verdict.

**Recovery:** if you hold this bead with no poured workflow, run
`gc formula show __FORMULA__` and follow its steps in order.

**What to review** is on this bead's metadata: `pr_number` (post-open) or
`review_branch`/`review_base` (pre-open), plus `anchor_bead` for the intent.
H
fi

# --- The check section: the concern this review verifies ----------------------
# A check's method lives once, in its pack skill, and the section names that
# skill without repeating any of it; a rig may extend it (below). A shared
# specialist stance precedes every non-baseline check's section, emitted once so
# no specialist skill restates it; correctness and triage are exempt, being the
# baseline whose methods state their own stance.
echo
echo "---"
echo
printf '## Check: `%s`\n' "$CHECK_NAME"
echo
case "$CHECK_NAME" in
  correctness|triage) : ;;   # baseline: its method states its own stance
  *)
    cat <<'S'
**The specialist stance.** Every specialist check holds it, so no check's skill
restates it. You are the author's peer and the gatekeeper of the
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
# A declared check's method is its skill, which the note names as gascity
# surfaces every pack skill, gc-toolkit.<directory>, for the reviewer to load
# from its catalog (below). The catalog links the installed pack, so a branch
# that edits a method is not judged by its own edit, and a rig other than
# gc-toolkit has the method too. An undeclared check has no skill, so its
# section says which case it is.
METHOD_SKILL=""
case "$CHECK_NAME" in
  correctness|triage|demo|arch|pm) METHOD_SKILL="review-$CHECK_NAME" ;;
  *)
    # The check's purpose, from its row in the index at the reviewed commit
    # (the working tree's index when no commit is named), through the index's
    # one parser, which matches the row's name case-folded too. Empty when no
    # row there declares the check.
    PURPOSE=""
    for root in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do
      [ -n "$root" ] || continue
      if [ -n "$REVIEWED_OID" ]; then IDX=$(git -C "$root" show "$REVIEWED_OID:review-checks.toml" 2>/dev/null)
      else IDX=$(cat "$root/review-checks.toml" 2>/dev/null); fi
      PURPOSE=$(printf '%s\n' "$IDX" | bash "$HERE/review-checks.sh" --file /dev/stdin --check "$CHECK_NAME" 2>/dev/null | cut -f3)
      [ -n "$PURPOSE" ] && break
    done
    if [ -n "$PURPOSE" ]; then
      cat <<M
The reviewed repo's \`review-checks.toml\` declares the \`$CHECK_NAME\` check,
and this pack ships no method for it. Judge the diff against the check's
purpose, as its row states it:

> $PURPOSE

Say in your verdict's coverage line that the pack has no method for this
check. The missing method is a gap worth an observation.
M
    else
      cat <<M
Neither this pack nor the reviewed repo's \`review-checks.toml\` declares the
\`$CHECK_NAME\` check, so nothing says what it judges. Approve, and pass
\`--needs-you\` on the verdict call saying the check is declared nowhere, so
the operator decides whether it stays in this anchor's check set.
M
    fi
    ;;
esac

if [ -n "$METHOD_SKILL" ]; then
  cat <<R
**Your method is the \`gc-toolkit.$METHOD_SKILL\` skill.**
Load it from your skill catalog and apply it; a copy in the review worktree is
the change under review, not your method.
R
fi

# The rig's local extension, appended to the generic method — read from the
# COMMIT UNDER REVIEW, never the working tree, so a branch is judged against the
# extension its own commit declared. Absent is the common case and changes nothing.
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
