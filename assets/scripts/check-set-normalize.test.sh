#!/usr/bin/env bash
# Hermetic test for the merge-push CHECK-SET NORMALIZATION (tk-4na1b).
#
# THE BUG (GOVERNANCE, HIGH): `{{check_set}}` is hand-substituted from the raw
# TOML on the --root-only patrol path — the wisp stamps no `gc.var.*`, so the
# formula's declared `default = "codex"` never reaches the substitution as a
# value. A mis-substitution therefore yields the EMPTY string, and an empty
# check_set declares NO gates: merge-skill.sh then lands the PR on CI + approval
# alone, with no review ever dispatched. That is how shutupandlisten landed 11/11
# PRs with zero automated review since 2026-07-01 — silently, because "empty"
# reads as a legitimate configuration rather than a failure.
#
# THE FIX: an empty value must never out-rank the non-empty formula default.
# The merge-push step recovers the declared default (empty -> "codex"), mirroring
# the `MERGE_STRATEGY="${MERGE_STRATEGY:-direct}"` idiom already in the same step.
#
# THE ESCAPE HATCH: a genuinely gateless rig must still be able to opt out, so it
# does so EXPLICITLY via the `none`/`off` sentinel, which normalizes to the
# CANONICAL `none` that merge-skill.sh reads as "no gates". merge-skill.sh's
# empty-means-ungated behavior is deliberately UNCHANGED (#163/#182): the former
# code held merges unconditionally on a missing signoff_head and stranded
# human-approved CLEAN PRs forever. This fix stays strictly UPSTREAM of the merge
# loop — it fixes what gets STAMPED, never how the stamp is READ.
#
# tk-i48ca AMENDED THE SENTINEL'S NORMALIZED FORM: `none`/`off` used to collapse to
# the EMPTY string. That made "gateless by choice" and "never normalized" the same
# value on the anchor, so nothing downstream could distinguish them — and a
# hand-RECOVERED bead, which bypasses this formula entirely and therefore arrives
# with an empty check_set, was indistinguishable from a deliberate opt-out and
# merged with no codex review. The sentinel is now STAMPED as `none`, so every
# formula-normalized anchor carries a NON-EMPTY check_set and an empty one is an
# unambiguous "never normalized" signal that check-set-heal.sh repairs at the
# refinery boundary. merge-skill.sh reads `none`/`off` as no-gates so the opt-out
# still lands; its empty read is untouched (guards O + P below).
#
# This test EXECUTES the real normalization extracted verbatim from the formula
# (between the `check-set-normalize` markers), so it cannot drift from the
# shipped instruction. Static guards then assert the normalized value is what
# actually reaches the membership test and both stamp sites, and that the merge
# skill's empty-means-ungated read is untouched. No live city, Dolt, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
SKILL="$ROOT/assets/scripts/merge-skill.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# --- Extract the REAL normalization from the formula. ------------------------
# Pulls the lines between the markers (exclusive). If the markers or the
# normalization are removed/renamed, extraction yields nothing and the check
# below fails loudly — the contract cannot silently disappear.
NORM="$(awk '
  /# >>> check-set-normalize/ {f=1; next}
  /# <<< check-set-normalize/ {f=0}
  f' "$TOML")"

[ -n "$NORM" ] \
  && ok "normalization extracted between check-set-normalize markers" \
  || bad "normalization NOT extractable — markers missing or renamed"

# The extracted snippet must be template-free so it can be executed directly.
printf '%s' "$NORM" | grep -q '{{' \
  && bad "extracted snippet still contains a {{template}} — it must be env-driven" \
  || ok "extracted snippet is template-free (env-driven)"

# --- Execute it against the truth table. -------------------------------------
# The snippet reads and rewrites $CHECK_SET, so drive it through the env exactly
# as the formula does after rendering `CHECK_SET="{{check_set}}"`.
cat > "$TMP/run.sh" <<RUNNER
set -u
$NORM
printf '%s' "\$CHECK_SET"
RUNNER

norm() { CHECK_SET="$1" bash "$TMP/run.sh"; }

check() { # <input> <expected> <label>
  local got; got="$(norm "$1")"
  [ "$got" = "$2" ] && ok "$3" || bad "$3 (got '$got' want '$2')"
}

# The bug itself: an empty render must recover the declared default, NOT sail
# through as "no gates".
check ''            'codex' "(A) empty render recovers the declared default 'codex'"
check '   '         'codex' "(B) whitespace-only render recovers the default"
# A value that NAMES no gates is as ungated as an empty one — merge-skill.sh
# splits on comma, trims, and drops empties, so ",,," declares nothing. It must
# recover the default too, or it is just the same silent bypass wearing a mask.
check ',,,'         'codex' "(C0) separator-only render names no gates -> recovers the default"

# An explicitly configured check-set is never rewritten.
check 'codex'       'codex' "(C) explicit 'codex' passes through unchanged"
check 'lint'        'lint'  "(D) a non-codex single gate passes through unchanged"
check 'lint, codex' 'lint, codex' "(E) multi-gate list preserved verbatim (spacing intact)"

# The explicit opt-out: a genuinely gateless rig says so with a sentinel, which
# normalizes to the CANONICAL `none` — STAMPED on the anchor, never collapsed to
# empty (tk-i48ca), so the opt-out survives as data that downstream can tell apart
# from a never-normalized recovery bead. merge-skill.sh reads it as "no gates".
check 'none'        'none'  "(F) sentinel 'none' opts out explicitly -> canonical 'none'"
check 'off'         'none'  "(G) sentinel 'off' canonicalizes to 'none'"
check 'NONE'        'none'  "(H) sentinel is case-insensitive"
check '  none  '    'none'  "(I) sentinel tolerates surrounding whitespace"

# The whole point of stamping the sentinel: an opt-out must never render as the
# empty value a bypassed/recovered anchor also carries, or the two are the same
# state again and check-set-heal.sh cannot safely repair either.
[ -n "$(norm 'none')" ] \
  && ok "(F2) the opt-out is a NON-EMPTY stamp (distinguishable from 'never normalized')" \
  || bad "(F2) opt-out normalized to empty — indistinguishable from a bypassed anchor (tk-i48ca)"

# --- Static guards: the normalized value must actually be USED. --------------
# A normalization that runs but is then bypassed by a re-render is a no-op. The
# membership test decides whether a codex review is dispatched AT ALL, so it must
# read $CHECK_SET — stamping a gate that was never dispatched would hold the
# merge forever on a marker nothing can stamp.
grep -q 'if printf .%s. "\$CHECK_SET" | tr .,. ' "$TOML" \
  && ok "(J) CODEX_GATE membership test reads the normalized \$CHECK_SET" \
  || bad "(J) membership test must read \$CHECK_SET, not a raw {{check_set}} re-render"

# Both gating-transition stamp sites (pre-open and post-open) must stamp the
# normalized value. A raw {{check_set}} here is the original footgun: it writes
# an empty, ungated check_set onto the gating anchor.
STAMPS="$(grep -c -- '--set-metadata check_set="\$CHECK_SET"' "$TOML" || true)"
[ "$STAMPS" -eq 2 ] \
  && ok "(K) both stamp sites (pre-open + post-open) stamp the normalized \$CHECK_SET" \
  || bad "(K) expected 2 normalized stamp sites, found $STAMPS"

grep -q -- '--set-metadata check_set="{{check_set}}"' "$TOML" \
  && bad "(L) a stamp site still writes the RAW {{check_set}} — empty would un-gate the anchor" \
  || ok "(L) no stamp site writes the raw {{check_set}}"

# Every raw render of {{check_set}} must be immediately normalized. Any bare
# render feeding a decision would reintroduce the bug on that path.
RENDERS="$(grep -c 'CHECK_SET="{{check_set}}"' "$TOML" || true)"
NORMS="$(grep -c '_cs_canon="\$(printf' "$TOML" || true)"
[ "$RENDERS" -eq "$NORMS" ] && [ "$RENDERS" -gt 0 ] \
  && ok "(M) every {{check_set}} render ($RENDERS) is paired with a normalization" \
  || bad "(M) $RENDERS raw renders but $NORMS normalizations — an unnormalized path remains"

# The formula default is the value the normalization recovers; they must agree.
grep -q '^default = "codex"' "$TOML" \
  && ok "(N) formula still declares default = \"codex\" (matches the recovered value)" \
  || bad "(N) formula default changed — the normalization would recover a stale value"

# --- Static guard: the merge skill must NOT be touched. ----------------------
# This fix is strictly upstream of the merge loop. merge-skill.sh reading an
# empty check_set as "no gates" is the DELIBERATE #163/#182 fix; making it
# fail-closed was considered (option C) and explicitly NOT approved.
grep -q 'EMPTY' "$SKILL" && grep -q 'declares NO gates' "$SKILL" \
  && ok "(O) merge-skill.sh still documents empty check_set as 'no gates' (unchanged)" \
  || bad "(O) merge-skill.sh's empty-means-ungated contract was altered — out of scope"

# --- Static guard: the merge skill MUST honour the sentinel. -----------------
# The stamped `none` reaches merge-skill.sh as a gate NAME. If the gate-splitting
# does not drop it, a gateless rig holds forever on `check.none` — a marker no
# reviewer can ever stamp. Moving the opt-out from "" to `none` is only safe
# because the merge skill drops it; this guard is that dependency, asserted.
grep -q '"none" and .* != "off"' "$SKILL" \
  && ok "(P) merge-skill.sh drops the none/off sentinel from the enforced gate list" \
  || bad "(P) merge-skill.sh must treat the none/off sentinel as no-gates, else a gateless rig holds on check.none"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
