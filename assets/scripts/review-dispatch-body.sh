#!/usr/bin/env bash
# review-dispatch-body — emit the METHOD carried by a dispatched signoff review
# bead, on stdout. The single source of truth for what a review dispatch says,
# shared by every call site that files one (tk-jufvl).
#
# THE BUG. The review dispatch named no method. `gc bd create "Review PR#177:
# <title>" -t task` produced a bead with a title and routing metadata and
# nothing else: enough to know WHAT to review, nothing about HOW. A polecat
# handed that bead looks for a method and finds one by description match, and
# the catalog entry that advertised "Use when reviewing code changes before
# creating a PR" won every time — a 6-persona fan-out that measured, over
# 2026-07-31..08-02, 518 codex sessions / 794M tokens, 4.9 subagents and ~4.7M
# tokens per review, for 12 merged PRs. Rescoping that one skill (city commit
# a68a29b0) stopped THAT skill being selected; it did not give reviews a method,
# so the next review-shaped entry in a polecat's catalog reintroduces the drift.
#
# THE FIX. Carry the method IN THE DISPATCH, so it is a property of the review
# bead rather than of whatever happens to be in the reviewing agent's catalog.
# gc has no per-agent skill allowlist to fall back on (`skills = [...]` is a
# tombstone, a parse error in v0.16), so the dispatch naming the method IS the
# control surface.
#
# ONE AUTHORED COPY. The method itself lives in the `signoff-review` skill
# (skills/signoff-review/SKILL.md, tk-wghh1) — reviewing is a property of the
# STEP, not of the agent, so every polecat has it. This emitter NAMES that skill
# and inlines its text verbatim, so the bead is self-contained for a reviewer
# whose catalog does not carry it, while the skill file stays the only copy
# anyone edits. Nothing here restates the method in parallel prose that could
# drift out of step with the skill.
#
# FAIL-SOFT, NEVER FAIL-STOP. If the skill file cannot be read — an older pack
# checkout, or this landing ahead of tk-wghh1 — the dispatch must still carry a
# usable method rather than regress to a bare title. The FALLBACK below is that
# degraded path: a complete-enough single-pass method, clearly marked, plus a
# stderr WARN so an operator sees the pack is missing the skill. A caller that
# cannot run this emitter at all falls back to a title-only bead (its own
# concern) — a dispatch must never be blocked on prose.
#
# NOT set -e: a caller embeds this in a best-effort dispatch loop that must not
# abort on a read error. Every failure path still prints a usable body.
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: review-dispatch-body.sh [--note <text>]

Prints the signoff-review method (the review bead's description) on stdout.

  --note <text>   Dispatch-specific context appended as a final section, e.g.
                  the stale-gate re-review's "the head moved, re-review it"
                  note. Optional; omitted when empty.
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

# Resolved through a symlink: a symlinked deploy would otherwise look for skills/
# beside the LINK rather than beside the real script, and silently emit the
# fallback method forever.
_self="${BASH_SOURCE[0]}"
_real="$(readlink -f "$_self" 2>/dev/null || true)"
[ -n "$_real" ] && _self="$_real"
HERE="$(cd "$(dirname "$_self")" && pwd)"
# The pack root holds skills/ alongside assets/scripts/. GC_RIG_ROOT is honoured
# first for the same reason the refinery formula resolves SCRIPTS_DIR that way:
# the patrol may run this from a rig checkout whose layout is the pack's.
SKILL_REL="skills/signoff-review/SKILL.md"
SKILL_FILE=""
CANDIDATES=()
[ -n "${GC_RIG_ROOT:-}" ] && CANDIDATES+=("$GC_RIG_ROOT/$SKILL_REL")
CANDIDATES+=("$HERE/../../$SKILL_REL")
for cand in "${CANDIDATES[@]}"; do
  if [ -r "$cand" ]; then SKILL_FILE="$cand"; break; fi
done

# --- header: name the method, and forbid picking another one -----------------
# This is the enforcement half. It runs BEFORE the method text so a reviewer who
# reads only the top of the bead still gets the two things that matter: which
# method, and that no other one — least of all a fan-out — may be substituted.
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
the intent. **Where the verdict goes** is the non-impl done sequence in your
prompt — it is authoritative over anything below. In short: a `COMMENT` verdict
is the signoff PASS and stamps `check.<check_name>=green@<reviewed_oid>` on the
anchor; `REQUEST_CHANGES` files a rework child instead. Never
`gh pr review --approve` — the city does not approve PRs.

H

# --- the method itself -------------------------------------------------------
if [ -n "$SKILL_FILE" ]; then
  echo "---"
  echo
  echo "## The method, inlined from \`$SKILL_REL\`"
  echo
  echo "Verbatim copy of the skill, so this bead is self-contained. The file is"
  echo "the source of truth; this copy is generated at dispatch."
  echo
  # Strip the YAML frontmatter (the skill's name/description matter to the skill
  # matcher, not to a reviewer reading the bead) and demote the skill's own H1 so
  # the bead keeps one document outline.
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
method is spelled out here. Follow it as written.

**1. Pin the commit.** Read `review_branch`/`review_base` (pre-open: no PR
exists yet, your verdict decides whether it opens) or `pr_number` (post-open:
the PR is published and held on your signoff). Then:

```bash
git fetch origin "$BASE" "$BRANCH"
REVIEWED_OID=$(git rev-parse "origin/$BRANCH")
```

The diff you read, the tests you run, and the OID you stamp are all that one
commit. The head can advance while you review; a verdict recorded against a
head you never read certifies unreviewed code.

**2. Read the whole diff** — `git diff "origin/$BASE...$REVIEWED_OID"` (three
dots: compare against the merge-base, so you review what the branch changed
rather than what the base moved underneath it). A large diff gets read in
chunks, not sampled. Read the intent too: the anchor bead, the PR or branch
description, and what earlier rounds found.

**3. Run the tests at the pinned commit,** in a detached worktree
(`git worktree add "$WT" --detach "$REVIEWED_OID"`) so you disturb no checkout
and never fight a branch checked out elsewhere. Run the suites the diff touches.
Record actual pass/fail counts. A suite that fails on the base too is context,
not this branch's defect.

**4. Check:** intent (does it do what the anchor asked?); correctness (bugs,
reachable edge cases, error handling); contract (does it break a caller, a
stored format, a metadata key, or another call site of anything it changed —
the recurring defect is a predicate fixed in one copy and left stale in two);
testing (do the tests exercise real behavior, is the new path covered);
readiness (back-compat, fail-closed where intended, docs it just made false).

**5. Calibrate severity.** P0 — broken or unsafe as merged (data loss, a merge
that bypasses a gate, a crash on the normal path). P1 — a real defect that will
bite (wrong behavior on a reachable input, a fail-open where fail-closed was
intended). P2 — worth fixing, not worth blocking. Grade honestly; not everything
is P0. Every finding carries **file:line**, what is wrong, why it matters, and
what would fix it.

**6. Decide exactly one verdict.** `COMMENT` — no P0 and no P1; the signoff
passes and remaining P2s ride along as non-blocking notes. `REQUEST_CHANGES` —
at least one P0 or P1, each with its required fix. Record it as:

```
VERDICT: <COMMENT|REQUEST_CHANGES>
Reviewed branch: <branch>
Reviewed base:   <base>
Reviewed commit: <REVIEWED_OID>

Scope checked: <what you actually read>

Findings: <P0/P1/P2 — each with file:line, impact, and the fix>

Verification: <suite -> N passed, M failed, run at the reviewed commit>
```

Say what you did NOT check. An honest coverage line is worth more than an
implied "I read everything".

**7. Hand off** per the non-impl done sequence in your prompt — stamping the OID
you pinned in step 1, never a freshly re-derived head.
F
fi

# --- optional dispatch-specific context --------------------------------------
if [ -n "$NOTE" ]; then
  echo
  echo "---"
  echo
  echo "## Context from the dispatch"
  echo
  printf '%s\n' "$NOTE"
fi
