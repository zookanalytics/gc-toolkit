#!/usr/bin/env bash
# Hermetic test for the refinery's rejection repool (both `mr-aware-rejection`
# blocks in formulas/mol-refinery-patrol.toml).
#
# THE CONTRACT:
#   1. The repool is ONE call to rejection-repool.sh, which owns the release and
#      the pour (rejection-repool.test.sh pins that script): the work bead, the
#      pool the binding prefix names, and the rejection reason as one word, in
#      bash and in zsh, the shells an agent pastes the block into.
#   2. FAIL CLOSED when rejection-repool.sh is missing: the block repools
#      nothing by hand, and ends the turn.
#   3. A repool that stops short but leaves an armed dispatch or a visit (exit 2)
#      ends the arm as a landed one does. One that recorded nothing (exit 1 or
#      3) ends the turn.
#   4. After the repool the block reads the bead once, shape-validated, for the
#      branch decision: an unreadable bead ends the turn with the branch kept.
#   5. The rejection KEEPS the branch unless the bead is direct-mode with
#      nothing PR-shaped on it. In mr mode the PR is opened later by the
#      cadence's pr-open, so "no PR on the bead yet" is not evidence that
#      nothing needs the branch.
#   6. Both steps that branch on the merge strategy read it through ONE
#      spliced block, so keeping a branch and opening a PR for it cannot
#      disagree about which mode the bead is in.
#   7. The delete is cleanup behind a repool that already stands, so a push
#      that cannot delete is reported and the cycle continues.
#
# Executes the real blocks extracted verbatim from the formula against stub
# `gc` + `rejection-repool.sh`. No live city, Dolt, network, or worktrees.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-mr-aware-rejection-failclosed-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

# --- Extract every marked copy (one file per block). ---------------------------
NBLOCKS=$(awk '
  /# >>> mr-aware-rejection$/ { n++; f=1; next }
  /# <<< mr-aware-rejection$/ { f=0; next }
  f { print > ("'"$TMP"'/block-" n ".sh") }
  END { print n }' "$TOML")
eq "$NBLOCKS" "2" "both rejection arms carry the mr-aware-rejection block"
cmp -s "$TMP/block-1.sh" "$TMP/block-2.sh" \
  && ok "the two rejection arms carry the same block" \
  || bad "the two rejection arms carry the same block"

for i in 1 2; do
  [ -s "$TMP/block-$i.sh" ] || { bad "block $i extracted"; continue; }
  case "$(cat "$TMP/block-$i.sh")" in
    *\\*) bad "block $i backslash-free (TOML would eat it)" ;;
    *)    ok  "block $i backslash-free (TOML would eat it)" ;;
  esac
  sed -e "s|{{binding_prefix}}|gc-toolkit.|g" "$TMP/block-$i.sh" > "$TMP/run-$i.sh"
  bash -n "$TMP/run-$i.sh" && ok "block $i is valid bash" || bad "block $i is valid bash"
done
# Positive control: a backslash-free run of the guard above proves nothing
# unless the guard still discriminates. Pin that `case … in *\\*` catches a
# literal backslash on this host, so a green suite is never a vacuous pass.
printf 'x\\y\n' > "$TMP/backslash-control"
case "$(cat "$TMP/backslash-control")" in
  *\\*) ok  "backslash guard detects a backslash (not vacuous)" ;;
  *)    bad "backslash guard is vacuous — a literal backslash went undetected" ;;
esac

# --- Stubs. ---------------------------------------------------------------------
# gc: bd show answers $FAKE_META (or nothing when FAKE_BD_FAILS=1); drain-ack
# and any bd update are recorded. rejection-repool.sh: records its argv, one
# argument per field, and exits $FAKE_REPOOL_RC; it lives under a fake rig root
# so the block's candidate resolution finds it.
mkdir -p "$TMP/bin" "$TMP/rig/assets/scripts"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd show") [ "${FAKE_BD_FAILS:-0}" = "1" ] && exit 1
             printf '[{"metadata":%s}]\n' "${FAKE_META:-{\}}"; exit 0 ;;
  "bd update") shift 2; printf 'UPDATE|%s\n' "$*" >> "$FAKE_LOG"; exit 0 ;;
esac
exit 0
GC
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/rig/assets/scripts/rejection-repool.sh" <<'REPOOL'
printf 'REPOOL' >> "$FAKE_LOG"
for a in "$@"; do printf '|%s' "$a" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
exit "${FAKE_REPOOL_RC:-0}"
REPOOL
chmod +x "$TMP/bin/gc" "$TMP/rig/assets/scripts/rejection-repool.sh"
export PATH="$TMP/bin:$PATH"

# run <block#> <meta-json|-> [rig-root] [repool-rc] [shell] -> "<rc>|<log>"
run() {
  : > "$TMP/log"
  local rc=0 fails=0 meta="$2"
  [ "$meta" = "-" ] && { fails=1; meta='{}'; }
  # cwd = $TMP (not a git repo) so the block's `git rev-parse --show-toplevel`
  # fallback cannot resolve the real repo and shadow the stub repool.
  ( cd "$TMP" && \
    WORK=tk-work REJECT_REASON="conflict with main; resume by merge" \
    GC_RIG_ROOT="${3-$TMP/rig}" GC_CITY_PATH="" \
    FAKE_META="$meta" FAKE_BD_FAILS="$fails" FAKE_REPOOL_RC="${4:-0}" FAKE_LOG="$TMP/log" \
    "${5:-bash}" "$TMP/run-$1.sh" > "$TMP/out" 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}
CALL="REPOOL|tk-work|--pool|gc-toolkit.polecat|--reason|conflict with main; resume by merge;"

for i in 1 2; do
  echo "── block $i ──"

  # (1) The repool is one call to rejection-repool.sh, and the bead is read
  #     once after it for the branch decision.
  eq "$(run "$i" '{}')" "0|$CALL" \
     "block $i: one rejection-repool.sh call with the pool and the whole reason"

  # (2) Missing rejection-repool.sh: repool nothing by hand, end the turn.
  eq "$(run "$i" '{}' "$TMP/nowhere")" "1|DRAIN;" \
     "block $i: missing rejection-repool.sh -> no repool, drain"

  # (3) An armed dispatch or a visit carries a repool that stopped short.
  eq "$(run "$i" '{}' "$TMP/rig" 2)" "0|$CALL" \
     "block $i: repool exit 2 (an arm or a visit carries it) -> the arm ends normally"

  # (4) A repool that recorded nothing ends the turn.
  eq "$(run "$i" '{}' "$TMP/rig" 3)" "1|${CALL}DRAIN;" \
     "block $i: repool exit 3 (nothing recorded) -> drain"
  eq "$(run "$i" '{}' "$TMP/rig" 1)" "1|${CALL}DRAIN;" \
     "block $i: repool exit 1 (usage) -> drain"

  # (5) An unreadable bead after the repool ends the turn; the repool stands.
  eq "$(run "$i" -)" "1|${CALL}DRAIN;" \
     "block $i: unreadable bead after the repool -> drain, branch decision skipped"

  # (6) The block never writes the bead itself — rejection-repool.sh is the writer.
  run "$i" '{}' >/dev/null
  grep -q '^UPDATE|' "$TMP/log" \
    && bad "block $i: no direct bead writes" "found a gc bd update" \
    || ok "block $i: no direct bead writes (rejection-repool.sh is the writer)"
done

# An agent pastes the block into its own shell, and zsh does not split an
# unquoted expansion. The reason has to reach the script as one word there too.
if command -v zsh >/dev/null 2>&1; then
  echo "── zsh ──"
  eq "$(run 1 '{}' "$TMP/rig" 0 zsh)" "0|$CALL" \
     "zsh: the same one call, with the reason as one word"
else
  echo "skip - zsh not installed; the zsh run of the block is not exercised"
fi

# --- One reading of the merge strategy. -----------------------------------------
# handle-failures decides whether the branch survives a rejection; merge-push
# decides whether a PR is opened for it. Two readings can disagree, and the
# disagreement that matters is silent: a delete guard keyed on "nothing
# PR-shaped on the bead" is satisfied for every mr-mode bead until pr-open runs.
echo "── merge-strategy-resolve ──"
NSTRAT=$(awk '
  /# >>> merge-strategy-resolve$/ { n++; f=1; next }
  /# <<< merge-strategy-resolve$/ { f=0; next }
  f { print > ("'"$TMP"'/strategy-" n ".sh") }
  END { print n }' "$TOML")
eq "$NSTRAT" "2" "both steps that branch on the strategy carry the resolve block"
cmp -s "$TMP/strategy-1.sh" "$TMP/strategy-2.sh" \
  && ok "the two resolve blocks are byte-identical (they cannot drift apart)" \
  || bad "the two resolve blocks are byte-identical (they cannot drift apart)"
STRAY=$(awk '
  /# >>> merge-strategy-resolve$/ { f=1; next }
  /# <<< merge-strategy-resolve$/ { f=0; next }
  !f' "$TOML" | grep -c 'jq .*metadata\.merge_strategy' || true)
eq "$STRAY" "0" "no step reads metadata.merge_strategy outside that block"

# --- The rejection's branch decision. -------------------------------------------
echo "── rejection-branch-keep ──"
awk '
  /# >>> rejection-branch-keep$/ { f=1; next }
  /# <<< rejection-branch-keep$/ { f=0; next }
  f' "$TOML" > "$TMP/branch-keep.sh"
[ -s "$TMP/branch-keep.sh" ] \
  && ok "the rejection arm carries the branch decision" \
  || bad "the rejection arm carries the branch decision"
for b in strategy-1 strategy-2 branch-keep; do
  case "$(cat "$TMP/$b.sh")" in
    *\\*) bad "$b is backslash-free (TOML would eat it)" ;;
    *)    ok  "$b is backslash-free (TOML would eat it)" ;;
  esac
done

# git: records the branch delete. Everything else fails, so the block's
# `git rev-parse --show-toplevel` fallback stays unresolved and the stub
# rejection-repool.sh under the fake rig root remains the only candidate.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<'GIT'
case "$1 $2 $3" in
  "push origin --delete")
    [ "${FAKE_DELETE_FAILS:-0}" = "1" ] && { printf 'DELETE-REFUSED|%s\n' "$4" >> "$FAKE_LOG"; exit 1; }
    printf 'DELETE|%s\n' "$4" >> "$FAKE_LOG"; exit 0 ;;
esac
exit 1
GIT
chmod +x "$TMP/bin/git"

# The decision reads $BEAD_JSON from the repool block above it — the same shell,
# one read — so the whole arm is what gets executed here, not the tail alone.
# arm <meta-json|-> [default_merge_strategy] -> "<rc>|<deletes>"
arm() {
  : > "$TMP/log"
  local rc=0 fails=0 meta="$1"
  [ "$meta" = "-" ] && { fails=1; meta='{}'; }
  cat "$TMP/block-2.sh" "$TMP/branch-keep.sh" \
    | sed -e "s|{{binding_prefix}}|gc-toolkit.|g" \
          -e "s|{{default_merge_strategy}}|${2:-mr}|g" > "$TMP/run-arm.sh"
  ( cd "$TMP" && \
    WORK=tk-work REJECT_REASON="section 15e fixture clock" GC_RIG="" \
    GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
    FAKE_META="$meta" FAKE_BD_FAILS="$fails" FAKE_LOG="$TMP/log" \
    bash "$TMP/run-arm.sh" > "$TMP/out" 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(grep '^DELETE|' "$TMP/log" | tr '\n' ';')"
}
BR='"branch":"polecat/tk-work"'

# (6) THE BUG: mr is the shipped default and the PR does not exist until the
#     cadence's pr-open runs, so a first-pass test rejection lands in the
#     window where the bead carries no PR and the branch is still needed.
eq "$(arm "{$BR}")" "0|" \
   "(6) default mr, no PR yet -> branch kept (pr-open has not run)"
eq "$(arm "{$BR,\"merge_strategy\":\"mr\"}")" "0|" \
   "(7) explicit mr -> branch kept"
eq "$(arm "{$BR,\"merge_strategy\":\"pr\"}")" "0|" \
   "(8) pr -> branch kept"
grep -q 'merge_strategy=mr' "$TMP/out" \
  && ok "(8b) pr is normalised to mr, the vocabulary merge-push branches on" \
  || bad "(8b) pr is normalised to mr, the vocabulary merge-push branches on"
eq "$(arm "{$BR,\"merge_strategy\":\"direct\"}")" "0|DELETE|polecat/tk-work;" \
   "(9) direct with nothing PR-shaped -> branch deleted"
eq "$(arm "{$BR,\"merge_strategy\":\"direct\",\"pr_url\":\"https://github.com/o/r/pull/7\"}")" "0|" \
   "(10) direct + pr_url -> branch kept"
eq "$(arm "{$BR,\"merge_strategy\":\"direct\",\"pr_number\":7}")" "0|" \
   "(11) direct + pr_number -> branch kept"
eq "$(arm "{$BR,\"merge_strategy\":\"direct\",\"existing_pr\":\"https://github.com/o/r/pull/7\"}")" "0|" \
   "(12) direct + existing_pr -> branch kept"
eq "$(arm -)" "1|" \
   "(13) unreadable bead -> arm exits before the decision, branch kept"
# The mode comes from the formula's own var, so a rig that ships direct still
# gets the direct-mode cleanup.
eq "$(arm "{$BR}" direct)" "0|DELETE|polecat/tk-work;" \
   "(14) default_merge_strategy=direct, strategy unset -> branch deleted"
eq "$(arm '{"merge_strategy":"direct"}')" "0|" \
   "(15) direct with no metadata.branch -> no branch-less delete"
arm "{$BR}" >/dev/null
grep -q 'keeping origin/polecat/tk-work' "$TMP/out" \
  && ok "(16) a kept branch is named in the cycle log, not silently skipped" \
  || bad "(16) a kept branch is named in the cycle log, not silently skipped"
eq "$(arm '{}')" "0|" \
   "(17) mr with no metadata.branch -> nothing to delete"
grep -q 'no metadata.branch on tk-work' "$TMP/out" \
  && ok "(17b) a branch-less bead is named as such, not logged as 'keeping origin/'" \
  || bad "(17b) a branch-less bead is named as such, not logged as 'keeping origin/'"

# The delete is the last thing the arm does and the repool above it has already
# committed. A push that cannot delete leaves a branch for the later sweep,
# which the cycle tolerates; aborting here would strand the cycle instead.
export FAKE_DELETE_FAILS=1
eq "$(arm "{$BR,\"merge_strategy\":\"direct\"}")" "0|" \
   "(18) a refused delete does not fail the cycle"
grep -q 'could not delete origin/polecat/tk-work' "$TMP/out" \
  && ok "(18b) a refused delete is reported, not swallowed" \
  || bad "(18b) a refused delete is reported, not swallowed"
grep -q '^DELETE-REFUSED|polecat/tk-work$' "$TMP/log" \
  && ok "(18c) the delete was actually attempted (the case is not vacuous)" \
  || bad "(18c) the delete was actually attempted (the case is not vacuous)"
unset FAKE_DELETE_FAILS

# A target under polecat/ is another bead's per-bead PR head. Work landing there
# folds into that PR; opening a nested branch -> polecat/* PR is never the
# intent. The refinery resolves such a bead to direct and KEEPS its branch (the
# branch carries the fold), with no operator picking a strategy by hand.
# (19) fold-in target -> direct, branch kept (not a nested PR, not a deleted branch).
arm "{$BR,\"target\":\"polecat/tk-anchor\"}" >/dev/null
eq "$(grep -c '^DELETE|' "$TMP/log")" "0" "(19) fold-in target polecat/* + no own PR -> branch kept"
grep -q 'folds into the PR at polecat/tk-anchor' "$TMP/out" \
  && ok "(19b) kept for the fold reason (strategy resolved to direct, not mr)" \
  || bad "(19b) kept for the fold reason (strategy resolved to direct, not mr)"

# (20) A non-polecat non-default target (integration/*, a named branch) is NOT a
#      fold-in: it stays mr so convoy/integration work keeps its review PR.
arm "{$BR,\"target\":\"integration/cv-1\"}" >/dev/null
eq "$(grep -c '^DELETE|' "$TMP/log")" "0" "(20) integration/* target -> branch kept"
grep -q 'the PR pipeline needs the branch' "$TMP/out" \
  && ok "(20b) integration/* target -> stays mr (not flipped to a fold-in direct)" \
  || bad "(20b) integration/* target -> stays mr (not flipped to a fold-in direct)"

# (21) A bead already recording its own PR keeps mr even under a polecat/ target:
#      the recorded PR is reused, not folded over.
arm "{$BR,\"target\":\"polecat/tk-anchor\",\"existing_pr\":\"https://github.com/o/r/pull/7\"}" >/dev/null
eq "$(grep -c '^DELETE|' "$TMP/log")" "0" "(21) polecat/ target + own existing_pr -> branch kept (mr)"
grep -q 'the PR pipeline needs the branch' "$TMP/out" \
  && ok "(21b) own existing_pr keeps mr, not flipped to a fold-in direct" \
  || bad "(21b) own existing_pr keeps mr, not flipped to a fold-in direct"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
