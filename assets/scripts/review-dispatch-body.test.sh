#!/usr/bin/env bash
# Hermetic test for review-dispatch-body.sh — the method carried by every
# dispatched signoff review (tk-jufvl). No live city, Dolt, network, or PRs.
#
# EVERY skill file this suite resolves is a fixture it builds, and every arm
# names the pack root it resolves from, so no arm's meaning depends on whether
# the real `signoff-review` skill (tk-wghh1) happens to be in this checkout.
# That independence has to be constructed, not assumed — see the FALLBACK
# fixture below for the arm that silently lost it (tk-yp3ca). The one arm that
# reads the real pack skill, (REALSKILL), is explicitly about that file and
# skips when it is absent.
#
# THE BUG. The review dispatch created a bead with a title and routing metadata
# and nothing else. Nothing said HOW to review, so the reviewing polecat matched
# a method out of its own skill catalog — a 6-persona fan-out at ~4.9 subagents
# and ~4.7M tokens per review. The dispatch carrying the method is the control
# surface (gc has no per-agent skill allowlist to fall back on).
#
# Covered:
#   (NAME)     both modes NAME the signoff-review skill and its file path.
#   (NOOTHER)  both modes forbid substituting another review method.
#   (NOFANOUT) both modes forbid subagents / persona reviewers / parallel passes.
#   (GATE)     both modes state the gate contract unchanged: COMMENT is the pass
#              and stamps check.<check_name>=green@<oid>, REQUEST_CHANGES files a
#              rework child, and `gh pr review --approve` is never used.
#   (INLINE)   with the skill readable, its text is inlined VERBATIM (one authored
#              copy, no parallel prose), frontmatter stripped, H1 demoted, and
#              nothing is written to stderr.
#   (RIGROOT)  GC_RIG_ROOT wins over the script-relative path (the refinery runs
#              these from a rig checkout).
#   (FALLBACK) with the skill unreadable — the emitter run from a COPY inside a
#              skill-less pack, so BOTH resolution candidates miss — a
#              COMPLETE-ENOUGH method is still emitted (pin the OID, 3-dot diff,
#              tests, severity, verdict shape) and a WARN goes to stderr; never a
#              method-less body, and never a skill inlined instead.
#   (RC)       both modes exit 0: a dispatch is never blocked on prose.
#   (NOTE)     --note appends a dispatch-context section; absent without it.
#   (REALSKILL) if the pack really carries skills/signoff-review/SKILL.md, the
#              emitter inlines THAT file (guards the path from rotting once
#              tk-wghh1 lands). Skipped while the skill is absent.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/review-dispatch-body.sh"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
# grep -F: the patterns are literal prose/markdown, never regex.
hasF() { grep -qF -- "$2" "$1" && ok "$3" || bad "$3 (missing: $2)"; }
notF() { grep -qF -- "$2" "$1" && bad "$3 (unexpected: $2)" || ok "$3"; }

# --- fixture pack: a stand-in skill with a recognisable marker ----------------
# Deliberately NOT a copy of the real skill: the assertion is that whatever the
# file says is what reaches the bead, so a fixture with a unique sentinel proves
# the inlining is a real read rather than baked-in prose. It is otherwise SHAPED
# like the real skill (pins an OID, reads a diff) so the "actionable standalone"
# assertions below exercise pass-through rather than the fixture's thinness.
FIXPACK="$TMP/pack"
mkdir -p "$FIXPACK/skills/signoff-review"
cat > "$FIXPACK/skills/signoff-review/SKILL.md" <<'S'
---
name: signoff-review
description: fixture frontmatter that must NOT reach the bead body
---

# Signoff Review

FIXTURE-SENTINEL-9c3f: the body of the skill, which must be inlined verbatim.

## 1. Pin what you are reviewing

    REVIEWED_OID=$(git rev-parse "origin/$BRANCH")

## 2. Read the diff

    git diff "origin/$BASE...$REVIEWED_OID"
S

# --- fixture pack: a skill-less pack that also holds a COPY of the emitter ----
# For the FALLBACK arm, and it has to carry that copy — an empty GC_RIG_ROOT is
# not enough to make the skill unreadable.
#
# The emitter resolves TWO candidates in order: `$GC_RIG_ROOT/$SKILL_REL`, then
# `$HERE/../../$SKILL_REL` relative to the script itself. Pointing GC_RIG_ROOT at
# an empty directory removes only the first; the second still finds the pack's
# OWN skill, so the emitter inlines it and the fallback never runs. That
# precedence is correct in production — a real skill beats the degraded copy —
# so the fixture must move the SCRIPT rather than try to hide the file: run the
# emitter from inside a pack root that carries no skills/, which is exactly the
# older-pack-checkout case the fallback exists for.
#
# This arm passed for the wrong reason until skills/signoff-review/SKILL.md
# landed (tk-wghh1). With no skill anywhere in the repo, both candidates missed
# and the fallback fired — by accident of what the repo did not contain, not by
# anything the fixture did. When the file landed, the arm silently flipped to
# exercising the INLINE path and went red on origin/main and every branch, which
# is how it was found (tk-yp3ca). Hence the assertion below that the fallback
# body inlines no skill at all: the arm must fail loudly if a candidate ever
# resolves again, whatever file it resolves to.
#
# A real COPY, never a symlink: the emitter resolves its own path through
# `readlink -f` deliberately (a symlinked deploy has to find skills/ beside the
# REAL script), so a symlink here would resolve straight back to the pack this
# fixture exists to escape.
FBPACK="$TMP/fbpack"
mkdir -p "$FBPACK/assets/scripts"
FB_SCRIPT="$FBPACK/assets/scripts/review-dispatch-body.sh"
cp "$SCRIPT" "$FB_SCRIPT"
if [ -e "$FBPACK/skills" ]; then
  echo "fixture error: $FBPACK must carry no skills/ — the FALLBACK arm is not isolated" >&2
  exit 1
fi

# --- run both modes ----------------------------------------------------------
# Each run names its own pack root, so neither depends on an ambient GC_RIG_ROOT.
RC_IN=0
GC_RIG_ROOT="$FIXPACK" bash "$SCRIPT" > "$TMP/inline.out" 2> "$TMP/inline.err" || RC_IN=$?
RC_FB=0
GC_RIG_ROOT="$FBPACK" bash "$FB_SCRIPT" > "$TMP/fb.out" 2> "$TMP/fb.err" || RC_FB=$?

eq "$RC_IN" "0" "(RC) inline mode exits 0"
eq "$RC_FB" "0" "(RC) fallback mode exits 0 (a dispatch is never blocked on prose)"

# --- (NAME) / (NOOTHER) / (NOFANOUT) / (GATE): true in BOTH modes -------------
for mode in inline fb; do
  OUT="$TMP/$mode.out"
  hasF "$OUT" 'signoff-review' "(NAME/$mode) names the signoff-review skill"
  hasF "$OUT" 'skills/signoff-review/SKILL.md' "(NAME/$mode) names the skill's file path"
  hasF "$OUT" 'Do not select any other review method' "(NOOTHER/$mode) forbids substituting another method"
  hasF "$OUT" 'Do NOT spawn' "(NOFANOUT/$mode) forbids spawning subagents"
  hasF "$OUT" 'persona reviewers' "(NOFANOUT/$mode) forbids persona reviewers"
  hasF "$OUT" 'parallel review pass' "(NOFANOUT/$mode) forbids a parallel review pass"
  hasF "$OUT" 'COMMENT' "(GATE/$mode) names the COMMENT verdict"
  hasF "$OUT" 'REQUEST_CHANGES' "(GATE/$mode) names the REQUEST_CHANGES verdict"
  hasF "$OUT" 'green@' "(GATE/$mode) states the green@<oid> stamp"
  hasF "$OUT" 'approve' "(GATE/$mode) addresses --approve (never used)"
  # The method must be actionable standalone: a reviewer with no skill still has
  # to know to pin a commit and to read the diff against the merge-base.
  hasF "$OUT" 'REVIEWED_OID' "(SELF/$mode) tells the reviewer to pin the commit"
  hasF "$OUT" 'git diff' "(SELF/$mode) tells the reviewer to read the diff"
done

# --- (INLINE) ----------------------------------------------------------------
hasF "$TMP/inline.out" 'FIXTURE-SENTINEL-9c3f' "(INLINE) inlines the skill file's text verbatim"
notF "$TMP/inline.out" 'fixture frontmatter that must NOT reach' "(INLINE) strips the YAML frontmatter"
notF "$TMP/inline.out" 'name: signoff-review' "(INLINE) strips the frontmatter name field"
eq "$(wc -c < "$TMP/inline.err" | tr -d ' ')" "0" "(INLINE) writes nothing to stderr when the skill is readable"
# The skill's own H1 is demoted so the bead keeps ONE document outline.
eq "$(grep -c '^# ' "$TMP/inline.out" || true)" "0" "(INLINE) demotes the skill H1 (no competing top-level heading)"
hasF "$TMP/inline.out" '## Signoff Review' "(INLINE) the demoted H1 survives as an H2"
# The inline mode must NOT also emit the fallback: one method, not two.
notF "$TMP/inline.out" '## The method (fallback)' "(INLINE) does not also emit the fallback method"

# --- (RIGROOT) ---------------------------------------------------------------
# GC_RIG_ROOT must WIN over the script-relative pack: the refinery invokes these
# scripts from a rig checkout, and the rig's skill is the one its polecats hold.
# Proven by pointing GC_RIG_ROOT at the fixture and seeing the fixture sentinel,
# which the real pack skill (if any) does not contain.
hasF "$TMP/inline.out" 'FIXTURE-SENTINEL-9c3f' "(RIGROOT) GC_RIG_ROOT wins over the script-relative path"

# --- (FALLBACK) --------------------------------------------------------------
hasF "$TMP/fb.out" '## The method (fallback)' "(FALLBACK) emits the marked fallback method"
hasF "$TMP/fb.err" 'WARN' "(FALLBACK) WARNs on stderr that the skill is missing"
hasF "$TMP/fb.err" 'skills/signoff-review/SKILL.md' "(FALLBACK) the WARN names the missing file"
notF "$TMP/fb.out" 'FIXTURE-SENTINEL-9c3f' "(FALLBACK) does not leak fixture text"
# The arm's own isolation, asserted independently of any particular skill file.
# The sentinel check above proves only that the FIXTURE skill was not read —
# under the tk-yp3ca bug the body was the REAL pack skill and that check passed
# while the fallback never ran at all. This header line is emitted if and only if
# some candidate resolved, so it fails on ANY leaked candidate, whatever file it
# found, and keeps the arm from going vacuous again.
notF "$TMP/fb.out" '## The method, inlined from' "(FALLBACK) inlines no skill file (both candidates miss)"
# Complete-enough: the five load-bearing pieces of a usable single-pass review.
# Match a token that cannot straddle a wrapped line: the prose says "(three\ndots:
# compare against the merge-base ...)", and grep -F is line-oriented.
hasF "$TMP/fb.out" 'merge-base' "(FALLBACK) explains the 3-dot merge-base diff"
hasF "$TMP/fb.out" 'detached worktree' "(FALLBACK) says to run tests in a detached worktree"
hasF "$TMP/fb.out" 'P0' "(FALLBACK) carries the severity scale"
hasF "$TMP/fb.out" 'file:line' "(FALLBACK) requires file:line on every finding"
hasF "$TMP/fb.out" 'VERDICT:' "(FALLBACK) carries the verdict record shape"

# --- (NOTE) ------------------------------------------------------------------
GC_RIG_ROOT="$FIXPACK" bash "$SCRIPT" --note 'STALE-NOTE-a1b2: the head moved.' \
  > "$TMP/note.out" 2>/dev/null
hasF "$TMP/note.out" '## Context from the dispatch' "(NOTE) --note adds the dispatch-context section"
hasF "$TMP/note.out" 'STALE-NOTE-a1b2: the head moved.' "(NOTE) --note text reaches the body"
notF "$TMP/inline.out" '## Context from the dispatch' "(NOTE) the section is absent without --note"

# --- (REALSKILL) -------------------------------------------------------------
# Once tk-wghh1 lands, the script-relative path must still resolve the REAL pack
# skill with no GC_RIG_ROOT set — this is what catches the path rotting if the
# pack layout moves. Skipped (not failed) while the skill is absent, so this
# suite is green in either landing order.
REAL_SKILL="$ROOT/skills/signoff-review/SKILL.md"
if [ -r "$REAL_SKILL" ]; then
  (unset GC_RIG_ROOT; bash "$SCRIPT" > "$TMP/real.out" 2> "$TMP/real.err") || true
  eq "$(wc -c < "$TMP/real.err" | tr -d ' ')" "0" "(REALSKILL) resolves the pack skill script-relatively (no WARN)"
  # A distinctive line from the real skill must reach the body.
  MARKER="$(grep -m1 '^The method for a dispatched signoff review' "$REAL_SKILL" || true)"
  if [ -n "$MARKER" ]; then
    hasF "$TMP/real.out" "$MARKER" "(REALSKILL) inlines the real pack skill's text"
  else
    ok "(REALSKILL) real skill present; opening line changed — text-inlining covered by (INLINE)"
  fi
else
  ok "(REALSKILL) skipped: skills/signoff-review/SKILL.md not in this pack yet (tk-wghh1)"
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
