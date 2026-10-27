#!/usr/bin/env bash
# Hermetic test for the refinery's rejection repool (both `mr-aware-rejection`
# blocks in formulas/mol-refinery-patrol.toml) and for its one reading of the
# merge strategy (merge-push's `merge-strategy-resolve` block).
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
#   4. The block reads no bead of its own, and the row rejection-repool.sh
#      prints is captured, not echoed into the cycle log.
#   5. Neither rejection arm deletes a branch. The rebuild the repool dispatches
#      resumes the branch, whatever the bead's merge strategy.
#   6. merge-push reads the merge strategy once, through one block. A bead that
#      names no strategy takes the formula's default, direct, and pr is mr. A
#      bead that would land direct on the default branch, or names no target,
#      resolves to mr, so the default branch takes work only through a PR.
#      local passes through, and merge-push's existing_pr rule after the block
#      still turns direct into mr.
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
# gc: drain-ack and any bd show or bd update are recorded, and bd show answers
# $FAKE_META, so a block that reads the bead itself is caught rather than
# served. rejection-repool.sh: records its argv, one argument per field, prints
# the row it read ($FAKE_META, or nothing when FAKE_NO_ROW=1) on stdout, and
# exits $FAKE_REPOOL_RC; it lives under a fake rig root so the block's candidate
# resolution finds it.
mkdir -p "$TMP/bin" "$TMP/rig/assets/scripts"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd show") printf 'SHOW|%s\n' "$3" >> "$FAKE_LOG"
             printf '[{"metadata":%s}]\n' "${FAKE_META:-{\}}"; exit 0 ;;
  "bd update") shift 2; printf 'UPDATE|%s\n' "$*" >> "$FAKE_LOG"; exit 0 ;;
esac
exit 0
GC
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/rig/assets/scripts/rejection-repool.sh" <<'REPOOL'
printf 'REPOOL' >> "$FAKE_LOG"
for a in "$@"; do printf '|%s' "$a" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
[ "${FAKE_NO_ROW:-0}" = "1" ] || printf '[{"id":"%s","metadata":%s}]\n' "$1" "${FAKE_META:-{\}}"
exit "${FAKE_REPOOL_RC:-0}"
REPOOL
chmod +x "$TMP/bin/gc" "$TMP/rig/assets/scripts/rejection-repool.sh"
export PATH="$TMP/bin:$PATH"

# run <block#> <meta-json|-> [rig-root] [repool-rc] [shell] -> "<rc>|<log>"
# A meta of "-" is a repool that read no row.
run() {
  : > "$TMP/log"
  local rc=0 norow=0 meta="$2"
  [ "$meta" = "-" ] && { norow=1; meta='{}'; }
  # cwd = $TMP (not a git repo) so the block's `git rev-parse --show-toplevel`
  # fallback cannot resolve the real repo and shadow the stub repool.
  ( cd "$TMP" && \
    WORK=tk-work REJECT_REASON="conflict with main; resume by merge" \
    GC_RIG_ROOT="${3-$TMP/rig}" GC_CITY_PATH="" \
    FAKE_META="$meta" FAKE_NO_ROW="$norow" FAKE_REPOOL_RC="${4:-0}" FAKE_LOG="$TMP/log" \
    "${5:-bash}" "$TMP/run-$1.sh" > "$TMP/out" 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}
CALL="REPOOL|tk-work|--pool|gc-toolkit.polecat|--reason|conflict with main; resume by merge;"

for i in 1 2; do
  echo "── block $i ──"

  # (1) The repool is one call to rejection-repool.sh, and the block reads no
  #     bead after it: the stub gc logs any bd show.
  eq "$(run "$i" '{}')" "0|$CALL" \
     "block $i: one rejection-repool.sh call with the pool and the whole reason"
  grep -q '"id":"tk-work"' "$TMP/out" \
    && bad "block $i: the row the repool prints is captured, not echoed" \
    || ok "block $i: the row the repool prints is captured, not echoed"

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

  # (5) A repool that could read no row files a visit and exits 2. The arm ends
  #     as a landed one does, with no read of its own.
  eq "$(run "$i" - "$TMP/rig" 2)" "0|$CALL" \
     "block $i: no row from the repool (exit 2) -> the arm ends normally, no bd show"

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
  # The block captures the row and reads the exit status off the assignment, so
  # zsh has to hand back the script's status there too.
  eq "$(run 1 '{}' "$TMP/rig" 3 zsh)" "1|${CALL}DRAIN;" \
     "zsh: the status read off the capture is the repool's (exit 3 -> drain)"
else
  echo "skip - zsh not installed; the zsh run of the block is not exercised"
fi

# --- One reading of the merge strategy. -----------------------------------------
# merge-push is the one step that branches on the strategy, so it carries the
# one block that reads it, and no step reads metadata.merge_strategy anywhere
# else.
echo "── merge-strategy-resolve ──"
NSTRAT=$(awk '
  /# >>> merge-strategy-resolve$/ { n++; f=1; next }
  /# <<< merge-strategy-resolve$/ { f=0; next }
  f { print > ("'"$TMP"'/strategy-" n ".sh") }
  END { print n + 0 }' "$TOML")
eq "$NSTRAT" "1" "one block reads the strategy"
eq "$(awk '/^\[\[steps\]\]$/ { id = "" } /^id = "/ { id = $3; gsub(/"/, "", id) } /^# >>> merge-strategy-resolve$/ { print id }' "$TOML")" \
   "merge-push" "the block sits in merge-push, the step that branches on it"
STRAY=$(awk '
  /# >>> merge-strategy-resolve$/ { f=1; next }
  /# <<< merge-strategy-resolve$/ { f=0; next }
  !f' "$TOML" | grep -c 'jq .*metadata\.merge_strategy' || true)
eq "$STRAY" "0" "no step reads metadata.merge_strategy outside that block"

# --- The rejection keeps the branch. ---------------------------------------------
# The repool dispatches a rebuild that resumes metadata.branch, so a deleted
# branch would stop that rebuild at workspace-setup's missing-branch visit.
# Every line of both rejection arms counts, prose included: a command quoted in
# a step's prose is one an agent types.
echo "── the rejection keeps the branch ──"
step() { awk -v want="$1" '/^\[\[steps\]\]$/ { id = "" } /^id = "/ { id = $3; gsub(/"/, "", id) } id == want' "$TOML"; }
# deletes <file>... prints file:line for each command shape that removes a branch.
deletes() { grep -nE 'push[^#]*(--delete|[[:space:]]:[^[:space:]])|branch-end[.]sh|branch[[:space:]]+-[dD]([[:space:]]|$)' "$@" || true; }
cat > "$TMP/delete-shapes" <<'SAMPLE'
git push origin --delete "$BRANCH"
git -C "$RIG_ROOT" push origin :polecat/tk-work
"$SCRIPTS/branch-end.sh" polecat/tk-work
git branch -D "$BRANCH"
SAMPLE
cat > "$TMP/delete-free" <<'SAMPLE'
Do NOT delete `origin/$BRANCH` (the rebuild resumes it, in every merge mode).
git push origin HEAD:refs/heads/polecat/tk-work
gc workflow delete-source $WORK --apply && gc workflow reopen-source $WORK
git push --force-with-lease origin "$BRANCH"
SAMPLE
eq "$(deletes "$TMP/delete-shapes" | wc -l | tr -d ' ')" "4" "detector: flags every branch-delete shape in the sample"
eq "$(deletes "$TMP/delete-free" | wc -l | tr -d ' ')" "0" "detector: passes a push, a workflow delete and prose"
for s in rebase handle-failures; do
  step "$s" > "$TMP/step-$s.txt"
  grep -q '^# >>> mr-aware-rejection$' "$TMP/step-$s.txt" \
    && ok "$s: the extracted step carries the repool block" \
    || bad "$s: the extracted step carries the repool block"
  eq "$(deletes "$TMP/step-$s.txt")" "" "$s: the rejection arm deletes no branch"
done

# --- The resolve block, run on its own. -------------------------------------------
# It is filled with the formula's own defaults, read from its [vars], so a
# changed default changes the cases here instead of leaving a stale fixture.
echo "── the resolve block, run on its own ──"
var_default() {
  awk -v v="[vars.$1]" '$0 == v { f = 1; next } /^\[/ { f = 0 } f && /^default = / { sub(/^default = "/, ""); sub(/"$/, ""); print; exit }' "$TOML"
}
DEFAULT_MS=$(var_default default_merge_strategy)
DEFAULT_BRANCH=$(var_default target_branch)
eq "$DEFAULT_MS" "direct" "the formula's default merge strategy is direct"
eq "$DEFAULT_BRANCH" "main" "the formula's default branch is main"
case "$(cat "$TMP/strategy-1.sh")" in
  *\\*) bad "the resolve block is backslash-free (TOML would eat it)" ;;
  *)    ok  "the resolve block is backslash-free (TOML would eat it)" ;;
esac
render() { sed -e "s|{{default_merge_strategy}}|$DEFAULT_MS|g" -e "s|{{target_branch}}|$DEFAULT_BRANCH|g"; }
SHOW='printf "MS=%s\n" "$MERGE_STRATEGY"'
{ render < "$TMP/strategy-1.sh"; printf '%s\n' "$SHOW"; } > "$TMP/resolve.sh"
# merge-push's existing_pr rule: the lines after the block, through its fi.
awk '/# <<< merge-strategy-resolve$/ { f = 1; next } f { print } f && /^fi$/ { exit }' "$TOML" > "$TMP/existing-pr.sh"
grep -q 'EXISTING_PR=' "$TMP/existing-pr.sh" \
  && ok "merge-push's existing_pr rule follows the block" \
  || bad "merge-push's existing_pr rule follows the block"
{ render < "$TMP/strategy-1.sh"; cat "$TMP/existing-pr.sh"; printf '%s\n' "$SHOW"; } > "$TMP/resolve-pr.sh"
for f in resolve resolve-pr; do
  case "$(cat "$TMP/$f.sh")" in
    *'{{'*) bad "$f: no unrendered formula placeholder left" ;;
    *)      ok  "$f: no unrendered formula placeholder left" ;;
  esac
  bash -n "$TMP/$f.sh" && ok "$f: valid bash" || bad "$f: valid bash"
done

# resolve <meta-json> [script] [shell] -> the strategy the block resolves for a
# bead carrying that metadata, in the row merge-push read.
resolve() {
  BEAD_JSON="[{\"id\":\"tk-work\",\"metadata\":$1}]" "${3:-bash}" "${2:-$TMP/resolve.sh}" 2>&1 | sed -n 's/^MS=//p'
}
IB='"target":"integration/cv-1"'
PH='"target":"polecat/tk-anchor"'
MAIN='"target":"main"'
RX='"target":"release/x"'

# An integration effort's branch takes its beads with no PR of their own, and a
# stage asks for one with mr.
eq "$(resolve "{$IB}")" "direct" "integration/cv-1, no strategy -> direct"
eq "$(resolve "{$IB,\"merge_strategy\":\"direct\"}")" "direct" "integration/cv-1, direct -> direct"
eq "$(resolve "{$IB,\"merge_strategy\":\"mr\"}")" "mr" "integration/cv-1, mr -> mr (a stage's PR into the branch)"
eq "$(resolve "{$IB,\"merge_strategy\":\"pr\"}")" "mr" "integration/cv-1, pr -> mr"
eq "$(resolve "{$IB,\"merge_strategy\":\"\"}")" "direct" "integration/cv-1, an empty strategy -> direct"
# Another PR's head: no strategy folds onto it, and mr opens a PR into it.
eq "$(resolve "{$PH}")" "direct" "polecat/tk-anchor, no strategy -> direct (folds onto that head)"
eq "$(resolve "{$PH,\"merge_strategy\":\"mr\"}")" "mr" "polecat/tk-anchor, mr -> mr (a PR into that head)"
# The rule for main: the default branch takes work only through a PR.
eq "$(resolve "{$MAIN}")" "mr" "main, no strategy -> mr"
eq "$(resolve "{$MAIN,\"merge_strategy\":\"direct\"}")" "mr" "main, direct -> mr"
eq "$(resolve "{$MAIN,\"merge_strategy\":\"mr\"}")" "mr" "main, mr -> mr"
eq "$(resolve "{$MAIN,\"merge_strategy\":\"pr\"}")" "mr" "main, pr -> mr"
eq "$(resolve "{$MAIN,\"merge_strategy\":\"\"}")" "mr" "main, an empty strategy -> mr"
eq "$(resolve '{}')" "mr" "no target, no strategy -> mr (a bead with no target lands on main)"
eq "$(resolve '{"merge_strategy":"direct"}')" "mr" "no target, direct -> mr"
eq "$(resolve '{"target":"","merge_strategy":"direct"}')" "mr" "an empty target, direct -> mr (read as no target)"
eq "$(BEAD_JSON='' bash "$TMP/resolve.sh" 2>&1 | sed -n 's/^MS=//p')" "mr" \
   "a row merge-push could not read -> mr (the block fails toward a PR)"
# Any other branch lands as its strategy says.
eq "$(resolve "{$RX}")" "direct" "release/x, no strategy -> direct"
eq "$(resolve "{$RX,\"merge_strategy\":\"direct\"}")" "direct" "release/x, direct -> direct"
# local lands nothing, so the rule does not apply to it.
eq "$(resolve "{$MAIN,\"merge_strategy\":\"local\"}")" "local" "main, local -> local"
eq "$(resolve '{"merge_strategy":"local"}')" "local" "no target, local -> local"
eq "$(resolve "{$IB,\"merge_strategy\":\"local\"}")" "local" "integration/cv-1, local -> local"
# A bead's own PR to reuse needs the PR pipeline wherever it lands.
eq "$(resolve "{$PH,\"existing_pr\":\"https://github.com/o/r/pull/7\"}" "$TMP/resolve-pr.sh")" "mr" \
   "polecat/tk-anchor with its own existing_pr -> mr, through merge-push's existing_pr rule"
eq "$(resolve "{$PH}" "$TMP/resolve-pr.sh")" "direct" \
   "polecat/tk-anchor with no existing_pr -> direct through the same rule (the case above is not vacuous)"
if command -v zsh >/dev/null 2>&1; then
  eq "$(resolve "{$MAIN,\"merge_strategy\":\"direct\"}" "$TMP/resolve.sh" zsh)" "mr" "zsh: main, direct -> mr"
  eq "$(resolve "{$IB}" "$TMP/resolve.sh" zsh)" "direct" "zsh: integration/cv-1, no strategy -> direct"
else
  echo "skip - zsh not installed; the zsh run of the resolve block is not exercised"
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
