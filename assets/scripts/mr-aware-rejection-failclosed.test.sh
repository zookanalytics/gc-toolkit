#!/usr/bin/env bash
# Hermetic test for the refinery's rejection repool (both `mr-aware-rejection`
# blocks in formulas/mol-refinery-patrol.toml).
#
# THE CONTRACT:
#   1. FAIL CLOSED on an unreadable bead — `gc bd` fails open (errors to
#      stderr, empty stdout), so an unread bead must never be repooled as if
#      it were a plain direct-mode work bead.
#   2. FAIL CLOSED when lifecycle.sh is missing — every merge_result
#      transition goes through the one writer; a hand-rolled repool is how
#      split transitions come back.
#   3. The repool is ONE lifecycle transition to `unanchored`: assignee
#      cleared, routed back to the polecat pool, rejection_reason carried.
#   4. A bead with a live PR (pr_url) carries it over as existing_pr, so the
#      rework reuses the same PR instead of minting a duplicate.
#   5. The rejection KEEPS the branch unless the bead is direct-mode with
#      nothing PR-shaped on it. In mr mode the PR is opened later by the
#      cadence's pr-open, so "no PR on the bead yet" is not evidence that
#      nothing needs the branch.
#   6. Both steps that branch on the merge strategy read it through ONE
#      spliced block, so keeping a branch and opening a PR for it cannot
#      disagree about which mode the bead is in.
#
# Executes the real blocks extracted verbatim from the formula against stub
# `gc` + `lifecycle.sh`. No live city, Dolt, network, or worktrees.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
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

for i in 1 2; do
  [ -s "$TMP/block-$i.sh" ] || { bad "block $i extracted"; continue; }
  grep -q '[\]' "$TMP/block-$i.sh" \
    && bad "block $i backslash-free (TOML would eat it)" \
    || ok "block $i backslash-free (TOML would eat it)"
  sed -e "s|{{binding_prefix}}|gc-toolkit.|g" "$TMP/block-$i.sh" > "$TMP/run-$i.sh"
  bash -n "$TMP/run-$i.sh" && ok "block $i is valid bash" || bad "block $i is valid bash"
done

# --- Stubs. ---------------------------------------------------------------------
# gc: bd show answers $FAKE_META (or nothing when FAKE_BD_FAILS=1); drain-ack
# is recorded. lifecycle.sh: records its argv, lives under a fake rig root so
# the block's candidate resolution finds it.
mkdir -p "$TMP/bin" "$TMP/rig/assets/scripts"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd show") [ "${FAKE_BD_FAILS:-0}" = "1" ] && exit 1
             printf '[{"metadata":%s}]\n' "${FAKE_META:-{\}}"; exit 0 ;;
  "bd update") shift 2; printf 'UPDATE|%s\n' "$*" >> "$FAKE_LOG"; exit 0 ;;
esac
exit 0
GC
cat > "$TMP/rig/assets/scripts/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
printf 'LIFECYCLE|%s\n' "$*" >> "$FAKE_LOG"
exit 0
LC
chmod +x "$TMP/bin/gc" "$TMP/rig/assets/scripts/lifecycle.sh"
export PATH="$TMP/bin:$PATH"

# run <block#> <meta-json|-> [rig-root] -> "<rc>|<log>"
run() {
  : > "$TMP/log"
  local rc=0 fails=0 meta="$2"
  [ "$meta" = "-" ] && { fails=1; meta='{}'; }
  # cwd = $TMP (not a git repo) so the block's `git rev-parse --show-toplevel`
  # fallback cannot resolve the real repo and shadow the stub lifecycle.sh.
  ( cd "$TMP" && \
    WORK=tk-work REJECT_REASON="conflict with main" GC_RIG="" \
    GC_RIG_ROOT="${3-$TMP/rig}" GC_CITY_PATH="" \
    FAKE_META="$meta" FAKE_BD_FAILS="$fails" FAKE_LOG="$TMP/log" \
    bash "$TMP/run-$1.sh" > "$TMP/out" 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

for i in 1 2; do
  echo "── block $i ──"

  # (1) Unreadable bead: repool NOTHING; leave the bead with the refinery.
  eq "$(run "$i" -)" "1|DRAIN;" \
     "block $i: unreadable bead -> no repool, drain (fails closed)"

  # (2) Missing lifecycle.sh: same fail-closed shape — never hand-roll the write.
  eq "$(run "$i" '{}' "$TMP/nowhere")" "1|DRAIN;" \
     "block $i: missing lifecycle.sh -> no repool, drain (single-writer rule)"

  # (3) Plain work bead: one lifecycle transition to unanchored, routed back to
  #     the polecat pool with the reason; no existing_pr invented.
  eq "$(run "$i" '{}')" \
     "0|LIFECYCLE|transition tk-work --to unanchored --assignee  --route gc-toolkit.polecat --set rejection_reason=conflict with main;" \
     "block $i: plain bead -> one unanchored transition, routed to the pool"

  # (4) An anchor with a live PR carries it over so the rework reuses the PR.
  eq "$(run "$i" '{"merge_result":"pull_request","pr_url":"https://github.com/o/r/pull/7"}')" \
     "0|LIFECYCLE|transition tk-work --to unanchored --assignee  --route gc-toolkit.polecat --set rejection_reason=conflict with main --set existing_pr=https://github.com/o/r/pull/7;" \
     "block $i: mr anchor -> existing_pr carried into the repool"

  # (5) The block never writes the bead directly — lifecycle.sh is the writer.
  run "$i" '{}' >/dev/null
  grep -q '^UPDATE|' "$TMP/log" \
    && bad "block $i: no direct bead writes" "found a gc bd update" \
    || ok "block $i: no direct bead writes (lifecycle.sh is the writer)"
done

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
  grep -q '[\]' "$TMP/$b.sh" \
    && bad "$b is backslash-free (TOML would eat it)" \
    || ok "$b is backslash-free (TOML would eat it)"
done

# git: records the branch delete. Everything else fails, so the block's
# `git rev-parse --show-toplevel` fallback stays unresolved and the stub
# lifecycle.sh under the fake rig root remains the only candidate.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "push origin --delete") printf 'DELETE|%s\n' "$4" >> "$FAKE_LOG"; exit 0 ;;
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

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
