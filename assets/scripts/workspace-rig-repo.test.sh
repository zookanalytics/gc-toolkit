#!/usr/bin/env bash
# Hermetic test for mol-polecat-work's `workspace-setup` rig-repo contract.
#
# What it holds:
#   1. RIG ROOT — the rig checkout is named from the agent environment
#      (GC_RIG_ROOT, else `gc rig list` keyed on GC_RIG), never from cwd, and
#      a rig that resolves to nothing drains instead of guessing.
#   2. TASK WORKTREE — the per-bead worktree is a worktree of the RIG repo
#      whatever repo cwd sits in; a recorded work_dir in some other repo is
#      set aside rather than worked in; a good one is reused untouched; and a
#      working directory whose origin is not the rig's fails closed.
#
# This EXECUTES the real snippets extracted verbatim from the formula (between
# the markers) against real local git repos and a fake `gc`, so the test cannot
# drift from the shipped instruction. No network, no city, no Dolt.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$2" in *"$1"*) ok "$3" ;; *) bad "$3 (not in: $2)" ;; esac; }
hasnt() { case "$2" in *"$1"*) bad "$3 (found in: $2)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract the REAL snippets from the formula. ------------------------------
# Pulls the lines between the markers (exclusive). Removing or renaming a
# marker yields an empty extraction and the checks below fail loudly, so the
# guard cannot silently disappear from the shipped step.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}

RIG_ROOT_BLOCK="$(extract workspace-rig-root)"
WORKTREE_BLOCK="$(extract workspace-worktree-rig)"

[ -n "$RIG_ROOT_BLOCK" ] \
  && ok "rig-root resolver extracted between workspace-rig-root markers" \
  || bad "rig-root extraction EMPTY — markers missing from $TOML"
[ -n "$WORKTREE_BLOCK" ] \
  && ok "worktree block extracted between workspace-worktree-rig markers" \
  || bad "worktree extraction EMPTY — markers missing from $TOML"

# `extract` is a flag-flip over the whole file, so two regions sharing one name
# concatenate into a single extraction and every assertion below silently runs
# the snippet twice. Pin each name to one occurrence.
eq "$(sed -n '/^# >>> workspace-rig-root$/p' "$TOML" | wc -l | tr -d ' ')" "1" \
   "exactly one workspace-rig-root region"
eq "$(sed -n '/^# >>> workspace-worktree-rig$/p' "$TOML" | wc -l | tr -d ' ')" "1" \
   "exactly one workspace-worktree-rig region"

# A TOML `"""` string treats a trailing backslash as a line-ending escape and
# eats the newline plus the following indentation, silently joining lines. Both
# snippets are backslash-free so what the polecat reads is what this test runs.
case "$RIG_ROOT_BLOCK$WORKTREE_BLOCK" in
  *\\*) bad "snippets contain a backslash — TOML line-ending escapes will mangle them" ;;
  *)    ok  "snippets are backslash-free (safe inside a TOML triple-quoted string)" ;;
esac

# `{{base_branch}}` is the one placeholder these snippets carry, substituted
# below exactly as the materializer does. A placeholder nobody substitutes
# reaches git as a literal ref name, so a newly added one has to fail here.
# The `|| true` is load-bearing: grep -c exits non-zero on no match, which is
# the passing outcome.
LEFTOVER="$(printf '%s\n%s\n' "$RIG_ROOT_BLOCK" "$WORKTREE_BLOCK" \
  | sed 's|{{base_branch}}||g' | grep -c '{{' || true)"
eq "$LEFTOVER" "0" "no placeholder beyond {{base_branch}} is left unsubstituted"

# --- Fixtures: two unrelated real repos, each with an agent home worktree. -----
# `rig` stands for the rig the polecat serves; `town` stands for any other repo
# the session might be sitting in.
seed_repo() {
  NAME="$1"
  git init --bare -q -b main "$TMP/$NAME.git"
  git init -q -b main "$TMP/$NAME"
  git -C "$TMP/$NAME" config user.email test@example.invalid
  git -C "$TMP/$NAME" config user.name "Test"
  git -C "$TMP/$NAME" config commit.gpgsign false
  echo "$NAME" > "$TMP/$NAME/marker"
  git -C "$TMP/$NAME" add marker
  git -C "$TMP/$NAME" commit -q -m "seed $NAME"
  git -C "$TMP/$NAME" remote add origin "$TMP/$NAME.git"
  git -C "$TMP/$NAME" push -q origin main
  git -C "$TMP/$NAME" fetch -q origin
}

seed_repo rig
seed_repo town
RIG_URL="$TMP/rig.git"
TOWN_URL="$TMP/town.git"

# Agent homes. Each is a worktree of its own repo, which is what a session's
# cwd is: `home_rig` is the healthy case, `home_town` is a session that woke
# outside its rig.
git -C "$TMP/rig"  worktree add -q "$TMP/home_rig"  --detach origin/main
git -C "$TMP/town" worktree add -q "$TMP/home_town" --detach origin/main

# --- Fake `gc`. ---------------------------------------------------------------
# `gc bd show <id> --json` answers $FAKE_META as the metadata object,
# `gc rig list --json` answers $FAKE_RIGS, and every call is appended to
# $FAKE_LOG so the assertions can prove WHAT was written and WHETHER the block
# drained.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
printf '%s\n' "gc $*" >> "$FAKE_LOG"
case "${1:-} ${2:-}" in
  "bd show")  printf '[{"metadata":%s}]\n' "$FAKE_META" ;;
  "rig list") printf '%s\n' "$FAKE_RIGS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# run_case <cwd> <GC_RIG_ROOT> <GC_RIG> <FAKE_META> <FAKE_RIGS>
# Runs the two snippets back to back with the work bead already derived (the
# convoy read between them is not under test), then reports rc, final cwd and
# the origin of that cwd. Output is one pipe-joined line so `eq` can assert it.
run_case() {
  : > "$TMP/log"
  {
    printf '%s\n' "$RIG_ROOT_BLOCK"
    printf 'WORK_BEAD_ID=tk-work\n'
    printf '%s\n' "$WORKTREE_BLOCK" | sed "s|{{base_branch}}|main|g"
    printf 'printf "CWD=%%s\\n" "$(pwd)"\n'
    printf 'printf "ORIGIN=%%s\\n" "$(git remote get-url origin 2>/dev/null)"\n'
  } > "$TMP/case.sh"
  local rc=0
  ( cd "$1" && PATH="$TMP/bin:$PATH" GC_RIG_ROOT="$2" GC_RIG="$3" \
      FAKE_META="$4" FAKE_RIGS="$5" FAKE_LOG="$TMP/log" \
      bash "$TMP/case.sh" ) > "$TMP/out" 2>"$TMP/err" || rc=$?
  CASE_RC="$rc"
  CASE_CWD="$(sed -n 's/^CWD=//p' "$TMP/out")"
  CASE_ORIGIN="$(sed -n 's/^ORIGIN=//p' "$TMP/out")"
  CASE_LOG="$(tr '\n' ';' < "$TMP/log")"
  CASE_ERR="$(tr '\n' ';' < "$TMP/err")"
}

ALL_RIGS="$(printf '{"rigs":[{"name":"rig","path":"%s"},{"name":"town","path":"%s"}]}' "$TMP/rig" "$TMP/town")"
NO_RIGS='{"rigs":[]}'

# --- 1. Healthy: session sits in its own rig worktree. ------------------------
run_case "$TMP/home_rig" "$TMP/rig" rig '{}' "$ALL_RIGS"
eq "$CASE_RC" "0" "healthy home: block succeeds"
eq "$CASE_CWD" "$TMP/home_rig/worktrees/tk-work" "healthy home: task worktree is per-bead under the agent home"
eq "$CASE_ORIGIN" "$RIG_URL" "healthy home: task worktree is a worktree of the rig repo"
has "set-metadata work_dir=$TMP/home_rig/worktrees/tk-work" "$CASE_LOG" \
    "healthy home: work_dir recorded on the bead"
hasnt "runtime drain-ack" "$CASE_LOG" "healthy home: does not drain"

# --- 2. The reported failure: session sits in a DIFFERENT repo. ---------------
# GC_RIG_ROOT still names the rig, so the task worktree belongs to the rig repo
# even though cwd does not. This is the whole point of the block.
run_case "$TMP/home_town" "$TMP/rig" rig '{}' "$ALL_RIGS"
eq "$CASE_RC" "0" "foreign cwd: block succeeds"
eq "$CASE_ORIGIN" "$RIG_URL" "foreign cwd: task worktree is STILL the rig repo, not cwd's"
eq "$CASE_CWD" "$TMP/home_town/worktrees/tk-work" "foreign cwd: path stays under the agent home"

# CONTROL for case 2: `git worktree add` with no `-C` takes its repo from cwd,
# which is the mechanism the block defends against. Without this the assertion
# above could pass for reasons unrelated to the fix.
( cd "$TMP/home_town" && git worktree add -q "$TMP/control_wt" --detach origin/main )
eq "$(git -C "$TMP/control_wt" remote get-url origin)" "$TOWN_URL" \
   "control: a bare 'git worktree add' follows cwd into the wrong repo"

# --- 3. Recorded work_dir belongs to another repo. ----------------------------
# It carries no branch this bead can land, so it is set aside and rebuilt. The
# aside copy is kept: nothing the block does is destructive.
STALE="$TMP/home_rig2/worktrees/tk-work"
git -C "$TMP/rig" worktree add -q "$TMP/home_rig2" --detach origin/main
git -C "$TMP/town" worktree add -q "$STALE" --detach origin/main
run_case "$TMP/home_rig2" "$TMP/rig" rig "$(printf '{"work_dir":"%s"}' "$STALE")" "$ALL_RIGS"
eq "$CASE_RC" "0" "stale work_dir: block succeeds"
eq "$CASE_CWD" "$STALE" "stale work_dir: rebuilt at the same per-bead path"
eq "$CASE_ORIGIN" "$RIG_URL" "stale work_dir: rebuilt worktree is the rig repo"
ASIDE="$(find "$TMP/home_rig2/worktrees" -maxdepth 1 -name 'tk-work.wrong-repo.*' | head -1)"
[ -n "$ASIDE" ] \
  && ok "stale work_dir: the foreign tree is moved aside, not deleted" \
  || bad "stale work_dir: no tk-work.wrong-repo.* left behind"
eq "$(git -C "${ASIDE:-$TMP}" remote get-url origin 2>/dev/null)" "$TOWN_URL" \
   "stale work_dir: the aside copy is the untouched foreign worktree"
has "set-metadata work_dir=$STALE" "$CASE_LOG" "stale work_dir: the rebuilt path is re-recorded"

# --- 4. Recorded work_dir is already a rig worktree: reuse it untouched. ------
REUSE="$TMP/reuse_wt"
git -C "$TMP/rig" worktree add -q "$REUSE" --detach origin/main
run_case "$TMP/home_rig" "$TMP/rig" rig "$(printf '{"work_dir":"%s"}' "$REUSE")" "$ALL_RIGS"
eq "$CASE_RC" "0" "good work_dir: block succeeds"
eq "$CASE_CWD" "$REUSE" "good work_dir: reused as recorded"
hasnt "set-metadata work_dir" "$CASE_LOG" "good work_dir: reuse does not rewrite the metadata"
hasnt "runtime drain-ack" "$CASE_LOG" "good work_dir: does not drain"

# --- 5. GC_RIG_ROOT unset: the rig is named by `gc rig list`. -----------------
# A second foreign home, because case 2 already built the per-bead path under
# the first one and a case that reuses it would prove nothing new.
git -C "$TMP/town" worktree add -q "$TMP/home_town2" --detach origin/main
run_case "$TMP/home_town2" "" rig '{}' "$ALL_RIGS"
eq "$CASE_RC" "0" "no GC_RIG_ROOT: block succeeds off the rig roster"
eq "$CASE_ORIGIN" "$RIG_URL" "no GC_RIG_ROOT: roster path still yields the rig repo"

# --- 6. Nothing resolves the rig: fail closed. -------------------------------
run_case "$TMP/home_town" "" nosuch '{}' "$NO_RIGS"
eq "$CASE_RC" "1" "unresolvable rig: exits non-zero"
has "runtime drain-ack" "$CASE_LOG" "unresolvable rig: drains"
has "no rig checkout for 'nosuch'" "$CASE_ERR" "unresolvable rig: says which rig it could not find"
hasnt "worktree add" "$CASE_LOG" "unresolvable rig: builds nothing"

# --- 7. The worktree cannot be created: fail closed, record nothing. ----------
# The path is occupied by a plain directory, so `git worktree add` refuses. The
# risk this covers is falling through to the agent home, which is shared.
git -C "$TMP/rig" worktree add -q "$TMP/home_rig4" --detach origin/main
mkdir -p "$TMP/home_rig4/worktrees/tk-work/occupied"
run_case "$TMP/home_rig4" "$TMP/rig" rig '{}' "$ALL_RIGS"
eq "$CASE_RC" "1" "uncreatable worktree: exits non-zero"
has "runtime drain-ack" "$CASE_LOG" "uncreatable worktree: drains"
hasnt "set-metadata work_dir" "$CASE_LOG" "uncreatable worktree: records no work_dir"
has "could not create $TMP/home_rig4/worktrees/tk-work" "$CASE_ERR" \
    "uncreatable worktree: names the path it could not build"

# --- 8. Post-condition: a working directory outside the rig repo fails closed.
# Reached only if the arms above ever hand back a foreign directory. Driven
# here by running the worktree block alone against a RIG_ORIGIN nothing matches.
: > "$TMP/log"
{
  printf 'RIG_ROOT=%s\n' "$TMP/rig"
  printf 'RIG_ORIGIN=https://example.invalid/other.git\n'
  printf 'WORK_BEAD_ID=tk-work\n'
  printf '%s\n' "$WORKTREE_BLOCK" | sed "s|{{base_branch}}|main|g"
} > "$TMP/post.sh"
POST_RC=0
( cd "$TMP/home_rig3" 2>/dev/null || { mkdir -p "$TMP/home_rig3"; cd "$TMP/home_rig3"; }
  PATH="$TMP/bin:$PATH" FAKE_META='{}' FAKE_RIGS="$NO_RIGS" FAKE_LOG="$TMP/log" \
    bash "$TMP/post.sh" ) > "$TMP/post.out" 2>"$TMP/post.err" || POST_RC=$?
eq "$POST_RC" "1" "post-condition: a non-rig working directory exits non-zero"
has "runtime drain-ack" "$(tr '\n' ';' < "$TMP/log")" "post-condition: drains"
has "is not the task worktree" "$(tr '\n' ';' < "$TMP/post.err")" \
    "post-condition: names the directory and the repo it required"
has "https://example.invalid/other.git" "$(tr '\n' ';' < "$TMP/post.err")" \
    "post-condition: names the rig origin it compared against"

# --- 9. Recorded work_dir is a plain directory inside the rig agent home. ------
# A husk with no .git of its own, left by an earlier fall-through. `git -C <husk>
# remote get-url origin` walks up to the enclosing rig worktree and reports the
# rig origin, so an origin check alone accepts it — but its git top-level is the
# parent, not itself, so it is no worktree the branch can land on. Checking out
# here would fork the branch in the shared agent home, the same setup failure the
# block exists to prevent. It is set aside on the top-level mismatch and rebuilt.
HUSK_HOME="$TMP/home_rig5"
git -C "$TMP/rig" worktree add -q "$HUSK_HOME" --detach origin/main
HUSK="$HUSK_HOME/worktrees/tk-work"
mkdir -p "$HUSK"
echo stale > "$HUSK/leftover"
eq "$(git -C "$HUSK" remote get-url origin 2>/dev/null)" "$RIG_URL" \
   "husk work_dir: origin resolves upward to the rig — an origin check alone would accept it"
eq "$(git -C "$HUSK" rev-parse --show-toplevel 2>/dev/null)" "$HUSK_HOME" \
   "husk work_dir: its git top-level is the parent worktree, not itself"
run_case "$HUSK_HOME" "$TMP/rig" rig "$(printf '{"work_dir":"%s"}' "$HUSK")" "$ALL_RIGS"
eq "$CASE_RC" "0" "husk work_dir: block succeeds"
eq "$CASE_CWD" "$HUSK" "husk work_dir: rebuilt at the same per-bead path"
eq "$CASE_ORIGIN" "$RIG_URL" "husk work_dir: rebuilt worktree is the rig repo"
eq "$(git -C "$HUSK" rev-parse --show-toplevel 2>/dev/null)" "$HUSK" \
   "husk work_dir: the rebuilt path is now its own worktree root"
ASIDE="$(find "$HUSK_HOME/worktrees" -maxdepth 1 -name 'tk-work.wrong-repo.*' | head -1)"
[ -n "$ASIDE" ] \
  && ok "husk work_dir: the husk is moved aside, not deleted" \
  || bad "husk work_dir: no tk-work.wrong-repo.* left behind"
[ -f "${ASIDE:-/nonexistent}/leftover" ] \
  && ok "husk work_dir: the aside copy keeps the husk's contents" \
  || bad "husk work_dir: aside copy lost the husk's contents"
has "set-metadata work_dir=$HUSK" "$CASE_LOG" "husk work_dir: the rebuilt path is re-recorded"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
