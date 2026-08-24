#!/usr/bin/env bash
# review-dispatch-body — emit the METHOD carried by a dispatched signoff review
# bead, on stdout. The single source of truth for what a review dispatch says:
# a bead with a bare title lets the reviewer pick a method out of its own
# catalog, which is the fan-out drift this emitter exists to prevent.
# The method itself is skills/signoff-review/SKILL.md, inlined verbatim so the
# bead is self-contained; nothing here restates it in parallel prose. If the
# skill file is unreadable the FALLBACK below is emitted instead, with a WARN —
# fail-soft, never fail-stop: a dispatch is never blocked on prose.
# Usage: review-dispatch-body.sh [--note <text>]  (--note appends dispatch-
# specific context, e.g. a stale-gate "the head moved, re-review it" note).
# Callers: every pass that files a review bead (gate-ensure.sh, pr-facts.sh,
# mol-refinery-patrol's first-round dispatch).
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: review-dispatch-body.sh [--note <text>]

Prints the signoff-review method (the review bead's description) on stdout.

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

# Resolve through a symlink so a symlinked deploy still finds skills/ beside
# the REAL script; GC_RIG_ROOT wins because the patrol runs this from a rig
# checkout whose layout is the pack's.
_self="${BASH_SOURCE[0]}"
_real="$(readlink -f "$_self" 2>/dev/null || true)"
[ -n "$_real" ] && _self="$_real"
HERE="$(cd "$(dirname "$_self")" && pwd)"
SKILL_REL="skills/signoff-review/SKILL.md"
SKILL_FILE=""
CANDIDATES=()
[ -n "${GC_RIG_ROOT:-}" ] && CANDIDATES+=("$GC_RIG_ROOT/$SKILL_REL")
CANDIDATES+=("$HERE/../../$SKILL_REL")
for cand in "${CANDIDATES[@]}"; do
  if [ -r "$cand" ]; then SKILL_FILE="$cand"; break; fi
done

# The enforcement half, ahead of the method text: which method, and that no
# other one — least of all a fan-out — may be substituted.
cat <<'H'
## Method: the `signoff-review` skill

This is a **dispatched signoff review**. Its method is fixed by this bead, not
chosen by you.

**Use the `signoff-review` skill** (`gc-toolkit.signoff-review`; source:
`skills/signoff-review/SKILL.md` in the gc-toolkit pack). Invoke it if your
skill catalog carries it. If it does not, the same method is inlined below —
follow it as written.

**Do not select any other review method.** Do not match a review-shaped skill
out of your catalog, and do not improvise one. A catalog entry advertising
"reviewing code changes" is not this method and must not be substituted.

**One agent, single pass. No fan-out.** You are the reviewer: read the diff
yourself, run the tests yourself, write the verdict yourself. Do NOT spawn
subagents, persona reviewers ("security reviewer", "architecture reviewer", …),
or any parallel review pass. This prohibition is the point of the dispatch, not
a performance note.

**What to review** is on this bead's metadata, not in this text: `pr_number`
(post-open) or `review_branch`/`review_base` (pre-open), plus `anchor_bead` for
the intent. **Where the verdict goes**: run `signoff.sh --review-bead <this
bead> --verdict approve|request-changes` exactly once — it owns the mechanics.
A `COMMENT` verdict is the signoff PASS and stamps
`check.<check_name>=green@<reviewed_oid>` on the anchor; `REQUEST_CHANGES`
files a rework child instead. Never `gh pr review --approve` — the city does
not approve PRs.

H

if [ -n "$SKILL_FILE" ]; then
  echo "---"
  echo
  echo "## The method, inlined from \`$SKILL_REL\`"
  echo
  echo "Verbatim copy of the skill, so this bead is self-contained. The file is"
  echo "the source of truth; this copy is generated at dispatch."
  echo
  # Strip the YAML frontmatter and demote the skill's H1 so the bead keeps one
  # document outline.
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---"      { fm = 0; next }
    fm                     { next }
    { sub(/^# /, "## "); print }
  ' "$SKILL_FILE"
else
  echo "review-dispatch-body: WARN $SKILL_REL not readable from ${GC_RIG_ROOT:-<unset>} or $HERE/../..; dispatching the inline FALLBACK method (install the signoff-review skill in the pack)" >&2
  cat <<'F'
---

## The method (fallback)

The `signoff-review` skill was not readable from this pack checkout, so the
method is spelled out here, condensed. Follow it as written.

**1. Pin the commit.** Resolve the branch and base from this bead's metadata,
`git fetch origin "$BASE" "$BRANCH"`, then
`REVIEWED_OID=$(git rev-parse "origin/$BRANCH")`. The diff you read, the tests
you run, and the OID you hand to signoff.sh are all that one commit.

**2. Read the whole diff** — `git diff "origin/$BASE...$REVIEWED_OID"` (three
dots: compare against the merge-base, so you review what the branch changed).
Read the intent too: the anchor bead and what earlier rounds found.

**3. Run the tests at the pinned commit** in a detached worktree
(`git worktree add "$WT" --detach "$REVIEWED_OID"`). Record real pass/fail
counts; a suite that fails on the base too is context, not a finding.

**4. Check** intent, correctness, contract (other call sites of anything it
changed), testing, readiness. **Severity:** P0 broken/unsafe as merged; P1 a
real defect that will bite; P2 worth fixing, not worth blocking. Every finding
carries **file:line**, impact, and the fix.

**5. Decide exactly one verdict** — `COMMENT` (no P0/P1; the pass) or
`REQUEST_CHANGES` — and record it as:

```
VERDICT: <COMMENT|REQUEST_CHANGES>
Reviewed branch/base/commit: <branch> <base> <REVIEWED_OID>
Scope checked: <what you actually read>
Findings: <P0/P1/P2 — each with file:line, impact, and the fix>
Verification: <suite -> N passed, M failed, at the reviewed commit>
```

Say what you did NOT check. Then hand off through signoff.sh with the OID you
pinned in step 1, never a freshly re-derived head.
F
fi

if [ -n "$NOTE" ]; then
  echo
  echo "---"
  echo
  echo "## Context from the dispatch"
  echo
  printf '%s\n' "$NOTE"
fi
