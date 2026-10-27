#!/usr/bin/env bash
# Hermetic test for the refinery's branch-prep worktree (the
# `shared-branch-merge-mode` and `shared-branch-push-mode` blocks in
# formulas/mol-refinery-patrol.toml).
#
# THE INVARIANT: the rig canonical checkout's HEAD never moves, and the flow
# depends on no local `temp` branch. The refinery runs its rebase/land flow in
# whatever cwd its session has, which is often the rig root; a `git checkout -b
# temp` there survives any interrupt before cleanup (a suspend mid-flow) and
# strands the root off its branch. The blocks stage the branch under prep in a
# dedicated DETACHED worktree, so the root's HEAD is untouched no matter where
# the session sits, and a root already stranded on `temp` cannot block staging.
#
# The merge block also stops a gate an interrupted run left running in the prep
# worktree before it rebuilds the worktree, and drains without rebuilding it
# when that gate will not stop, or when no detached-job.sh or
# refinery-workspace.sh is reachable.
#
# merge-push's first block takes WORK and BRANCH from the record the stage left
# in the prep worktree. Run ahead of the push block in a shell carrying another
# bead's WORK or BRANCH, it sends the prepared head to the branch it was staged
# from and leaves the other bead's branch where it was. The push block run
# without it, with the same variables, force-pushes the prepared head over the
# other bead's branch.
#
# Runs the REAL blocks extracted verbatim from the formula against a real git
# repo (worktrees need one), the real detached-job.sh and refinery-workspace.sh,
# and a stub `gc`. cwd is deliberately the rig root — the exact case that used
# to strand it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-prep-worktree-test.XXXXXX")"
# git names the prep worktree under the repository's resolved path, so every
# path is built on a resolved root and compares to git's as a string, a TMPDIR
# behind a symlink or ending in a slash (as macOS's is) included.
TMP="$(cd "$TMP" && pwd -P)"
# A gate a failed assertion left running is stopped before the record goes.
cleanup() {
  local g
  for g in "$TMP"/*/rig/.git/gc-refinery-gate; do
    [ -f "$g/pid" ] && "$HERE/detached-job.sh" stop "$g" >/dev/null 2>&1
  done
  rm -rf "$TMP"
}
trap cleanup EXIT
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }

command -v jq  >/dev/null 2>&1 || { echo "jq required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git required" >&2; exit 1; }
[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

fence() { awk -v m="$1" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$TOML"; }

# --- 1. Extraction + shape. ----------------------------------------------------
fence shared-branch-merge-mode > "$TMP/merge.sh"
fence shared-branch-push-mode  > "$TMP/push.sh"
[ -s "$TMP/merge.sh" ] && ok "shared-branch-merge-mode extracted" || bad "shared-branch-merge-mode extracted"
[ -s "$TMP/push.sh" ]  && ok "shared-branch-push-mode extracted"  || bad "shared-branch-push-mode extracted"
for b in merge push; do
  case "$(cat "$TMP/$b.sh")" in
    *\\*) bad "$b block backslash-free (TOML would eat it)" ;;
    *)    ok  "$b block backslash-free (TOML would eat it)" ;;
  esac
  bash -n "$TMP/$b.sh" && ok "$b block is valid bash" || bad "$b block is valid bash"
done
# Positive control: a backslash-free run of the guard above proves nothing
# unless the guard still discriminates. Pin that `case … in *\\*` catches a
# literal backslash on this host, so a green suite is never a vacuous pass.
printf 'x\\y\n' > "$TMP/backslash-control"
case "$(cat "$TMP/backslash-control")" in
  *\\*) ok  "backslash guard detects a backslash (not vacuous)" ;;
  *)    bad "backslash guard is vacuous — a literal backslash went undetected" ;;
esac
# The whole point: no bare checkout/rebase/merge/switch that would move cwd HEAD.
grep -Eq 'git (checkout|switch|rebase|merge)( |$)' "$TMP/merge.sh" \
  && bad "merge block never runs a bare HEAD-moving git in cwd" \
  || ok "merge block never runs a bare HEAD-moving git in cwd"
grep -q 'git checkout temp' "$TMP/push.sh" \
  && bad "push block does not check temp out in cwd" \
  || ok "push block does not check temp out in cwd"

# --- 2. Stub gc: bd show returns $FAKE_META; bd update / drain-ack are no-ops. --
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "bd show")          printf '%s' "${FAKE_META:-[]}" ;;
  "bd update")        exit 0 ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  *)                  exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_LOG="$TMP/drain.log"

# The pack, where the merge block finds detached-job.sh to stop a gate left
# running in the prep worktree, and refinery-workspace.sh to stage it:
# $GC_CITY_PATH/rigs/gc-toolkit.
CITY="$TMP/city"
mkdir -p "$CITY/rigs/gc-toolkit/assets/scripts"
cp "$HERE/detached-job.sh" "$HERE/refinery-workspace.sh" "$CITY/rigs/gc-toolkit/assets/scripts/"
export DETACHED_JOB_POLL=1 DETACHED_JOB_STOP_GRACE=2

# --- Build a synthetic origin + rig, with the base advanced under the branch. --
build_repo() {
  local d="$1" feature_branch="$2"
  rm -rf "$d"; mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git init -q "$d/seed"; (
    cd "$d/seed"; git config user.email t@t; git config user.name t
    echo base > f; git add f; git commit -qm base
    git remote add origin ../origin.git; git push -q origin HEAD:main
    git checkout -qb "$feature_branch"; echo feat > g; git add g; git commit -qm feat
    git push -q origin "$feature_branch"
    git checkout -q -B main; echo landed > h; git add h; git commit -qm "landed underneath"
    git push -q origin HEAD:main
  )
  git clone -q "$d/origin.git" "$d/rig"
  ( cd "$d/rig"; git config user.email r@r; git config user.name r; git checkout -q -B main origin/main )
}

# Run an extracted block from INSIDE the rig root (the stranding case). RUN_CITY
# names another pack to find detached-job.sh in.
run_block() { # <rig> <block-file>
  ( cd "$1" && GC_RIG_ROOT="$1" GC_CITY_PATH="${RUN_CITY:-$CITY}" WORK=wb TARGET_BRANCH_DEFAULT=main bash "$2" ) >/dev/null 2>&1
}
head_of()  { git -C "$1" rev-parse --abbrev-ref HEAD; }
prep_of()  { echo "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"; }

# --- 3. a per-bead polecat/* branch is brought current by MERGE, not rebase. ----
R="$TMP/polecat"; build_repo "$R" "polecat/wb"
export FAKE_META='[{"metadata":{"branch":"polecat/wb","target":"main"}}]'
run_block "$R/rig" "$TMP/merge.sh" && ok "merge block (polecat/* branch) exits 0" || bad "merge block (polecat/* branch) exits 0"
eq "$(head_of "$R/rig")" "main" "polecat/* branch: rig root stays on main (never checked out temp)"
PW="$(prep_of "$R/rig")"
[ -d "$PW" ] && ok "polecat/* branch: staged in the prep worktree" || bad "polecat/* branch: staged in the prep worktree" "$PW"
eq "$(git -C "$PW" rev-parse --abbrev-ref HEAD 2>/dev/null)" "HEAD" "polecat/* branch: prep worktree is detached (creates no branch)"
git -C "$R/rig" show-ref --verify --quiet refs/heads/temp \
  && bad "polecat/* branch: no local temp branch created (the collision the fix removes)" \
  || ok "polecat/* branch: no local temp branch created (the collision the fix removes)"
case "$PW" in "$R/rig/.git/"*) ok "prep worktree lives inside the git dir (invisible to working trees)" ;; *) bad "prep worktree lives inside the git dir" "$PW" ;; esac
eq "$(git -C "$R/rig" status --porcelain | wc -l | tr -d ' ')" "0" "polecat/* branch: rig root working tree stays clean (no untracked prep dir)"
# Brought current by MERGE: the prepared head carries the base's landed commit (h)
# and the feature (g), the merge completed (no MERGE_HEAD left), and — the tell it
# was a merge and not a rewrite — origin/polecat/wb is still an ANCESTOR of the
# prepared head, so the push ships a fast-forward and never a force.
git -C "$PW" cat-file -e HEAD:h 2>/dev/null && git -C "$PW" cat-file -e HEAD:g 2>/dev/null \
  && ok "polecat/* branch: prepared head carries the feature and the advanced base" \
  || bad "polecat/* branch: prepared head carries the feature and the advanced base"
git -C "$PW" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && bad "polecat/* branch: merge completed (no conflict left)" || ok "polecat/* branch: merge completed (no conflict left)"
git -C "$PW" merge-base --is-ancestor origin/polecat/wb HEAD \
  && ok "polecat/* branch: origin/branch stays an ancestor of the prepared head (merged, not rewritten)" \
  || bad "polecat/* branch: origin/branch stays an ancestor of the prepared head (merged, not rewritten)"

# push block: ships the prepared head -> origin/<branch> without a cwd checkout; root unmoved.
( cd "$R/rig" && GC_RIG_ROOT="$R/rig" GC_CITY_PATH="$CITY" WORK=wb BRANCH=polecat/wb bash "$TMP/push.sh" ) >/dev/null 2>&1 \
  && ok "push block exits 0" || bad "push block exits 0"
eq "$(head_of "$R/rig")" "main" "after push: rig root still on main"
eq "$(git -C "$R/rig" rev-parse origin/polecat/wb)" "$(git -C "$PW" rev-parse HEAD)" "after push: origin/branch == the merged prepared head"

# --- 3b. a WORK or BRANCH the shell carries cannot steer the push. --------------
# The prep worktree holds one bead's prepared head. merge-push opens with
# prep-staged-work, which takes WORK and BRANCH from the record the stage left,
# and every block after it runs in the same shell. Origin carries two beads'
# branches, wb's head is staged, and the step's first block and its push block
# run together in a shell carrying another bead's variables.
# build_two <dir>: origin carries main, and polecat/wa and polecat/wb one commit
# each ahead of the base, with the base advanced under both.
build_two() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git init -q "$d/seed"; (
    cd "$d/seed"; git config user.email t@t; git config user.name t
    echo base > f; git add f; git commit -qm base; git branch -M main
    git remote add origin ../origin.git; git push -q origin main
    git checkout -qb polecat/wa; echo a > a; git add a; git commit -qm "wa's work"; git push -q origin polecat/wa
    git checkout -q main; git checkout -qb polecat/wb; echo b > b; git add b; git commit -qm "wb's work"; git push -q origin polecat/wb
    git checkout -q main; echo landed > h; git add h; git commit -qm "landed underneath"; git push -q origin main
  )
  git clone -q "$d/origin.git" "$d/rig"
  ( cd "$d/rig"; git config user.email r@r; git config user.name r; git checkout -q -B main origin/main )
}
# push_as <rig> <work> <branch> <block>: the block from inside the rig, with
# that WORK and BRANCH. Sets RC.
push_as() {
  : > "$FAKE_LOG"
  ( cd "$1" && GC_RIG_ROOT="$1" GC_CITY_PATH="$CITY" WORK="$2" BRANCH="$3" bash "$4" ) >"$TMP/push.out" 2>&1 && RC=0 || RC=$?
}
fence prep-staged-work > "$TMP/staged.sh"
[ -s "$TMP/staged.sh" ] && ok "prep-staged-work extracted" || bad "prep-staged-work extracted"
cat "$TMP/staged.sh" "$TMP/push.sh" > "$TMP/staged-push.sh"
T="$TMP/two"; build_two "$T"
export FAKE_META='[{"metadata":{"branch":"polecat/wb","target":"main"}}]'
run_block "$T/rig" "$TMP/merge.sh" && ok "two beads: wb's branch is prepared" || bad "two beads: wb's branch is prepared"
PWT="$(prep_of "$T/rig")"
WA_TIP=$(git -C "$T/origin.git" rev-parse polecat/wa)
git -C "$PWT" merge-base --is-ancestor origin/polecat/wa HEAD \
  && bad "precondition: origin/polecat/wa is no ancestor of wb's prepared head, so its push would take the force arm" \
  || ok "precondition: origin/polecat/wa is no ancestor of wb's prepared head, so its push would take the force arm"
for vars in "wa polecat/wa" "wa polecat/wb" "wb polecat/wa"; do
  read -r V_WORK V_BRANCH <<< "$vars"
  push_as "$T/rig" "$V_WORK" "$V_BRANCH" "$TMP/staged-push.sh"
  eq "$RC" 0 "WORK=$V_WORK BRANCH=$V_BRANCH over wb's prepared head: the first block and the push block exit 0"
  eq "$(git -C "$T/origin.git" rev-parse polecat/wb)" "$(git -C "$PWT" rev-parse HEAD)" \
    "WORK=$V_WORK BRANCH=$V_BRANCH: wb's prepared head goes to origin/polecat/wb, the branch it was staged from"
  eq "$(git -C "$T/origin.git" rev-parse polecat/wa)" "$WA_TIP" "WORK=$V_WORK BRANCH=$V_BRANCH: origin/polecat/wa is untouched"
  grep -q DRAIN "$FAKE_LOG" && bad "WORK=$V_WORK BRANCH=$V_BRANCH: the refinery does not drain" \
    || ok "WORK=$V_WORK BRANCH=$V_BRANCH: the refinery does not drain"
  [ "$V_WORK" = wa ] && { grep -qF "WORK was wa, but the prep worktree holds polecat/wb for wb, so this step acts for wb" "$TMP/push.out" \
    && ok "WORK=$V_WORK BRANCH=$V_BRANCH: the step says it acts for wb" \
    || bad "WORK=$V_WORK BRANCH=$V_BRANCH: the step says it acts for wb" "$(cat "$TMP/push.out")"; }
done

# Control: the push block run without the first block, in a shell carrying wa's
# variables, forces wb's prepared head over polecat/wa, so the first block's
# read of the record is what keeps the push on wb's branch above.
C="$TMP/two-control"; build_two "$C"
run_block "$C/rig" "$TMP/merge.sh" && ok "control: wb's branch is prepared" || bad "control: wb's branch is prepared"
push_as "$C/rig" wa polecat/wa "$TMP/push.sh"
eq "$(git -C "$C/origin.git" rev-parse polecat/wa)" "$(git -C "$(prep_of "$C/rig")" rev-parse HEAD)" \
  "control: without the first block, wa's variables put wb's prepared head on origin/polecat/wa"

# --- 4. idempotency: a leftover prep worktree from an interrupted run. ---------
run_block "$R/rig" "$TMP/merge.sh" && ok "merge block re-runs cleanly over a leftover prep worktree" || bad "merge block re-runs cleanly over a leftover prep worktree"
eq "$(head_of "$R/rig")" "main" "idempotent re-run: rig root still on main"

# --- 4b. a gate the interrupted run left running is stopped before the rebuild.
# Rebuilding the prep worktree under a gate that still runs in it either fails
# the add or stages the next branch under the old gate's writes.
GATE_R="$(git -C "$R/rig" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-gate"
"$CITY/rigs/gc-toolkit/assets/scripts/detached-job.sh" start "$GATE_R" -- bash -c 'cd "$1" && sleep 63' _ "$PW" >/dev/null
OLD=$(cat "$GATE_R/pid")
kill -0 "$OLD" 2>/dev/null && ok "precondition: a gate runs in the prep worktree" || bad "precondition: a gate runs in the prep worktree"
run_block "$R/rig" "$TMP/merge.sh" && ok "merge block over a running gate exits 0" || bad "merge block over a running gate exits 0"
kill -0 -- "-$OLD" 2>/dev/null && bad "the old gate's process group is gone before the rebuild" "it survived" \
  || ok "the old gate's process group is gone before the rebuild"
git -C "$PW" cat-file -e HEAD:g 2>/dev/null && ok "the prep worktree is rebuilt" || bad "the prep worktree is rebuilt"

# A launcher whose stop reports the gate still running, as detached-job.sh does
# when the gate's process group survives TERM and KILL.
STUCK="$TMP/stuck-city"
mkdir -p "$STUCK/rigs/gc-toolkit/assets/scripts"
cat > "$STUCK/rigs/gc-toolkit/assets/scripts/detached-job.sh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = stop ] || exit 0
printf "state=running\ndetail=the job's process group survived TERM and KILL\ndir=%s\n" "$2"
exit 1
STUB
chmod +x "$STUCK/rigs/gc-toolkit/assets/scripts/detached-job.sh"
: > "$PW/left-by-the-gate"
: > "$FAKE_LOG"
RUN_CITY="$STUCK" run_block "$R/rig" "$TMP/merge.sh" && bad "a gate that will not stop: the merge block exits non-zero" \
  || ok "a gate that will not stop: the merge block exits non-zero"
[ -e "$PW/left-by-the-gate" ] && ok "a gate that will not stop: the prep worktree is not rebuilt under it" \
  || bad "a gate that will not stop: the prep worktree is not rebuilt under it"
grep -q DRAIN "$FAKE_LOG" && ok "a gate that will not stop: the refinery drains, leaving the work to retry" \
  || bad "a gate that will not stop: the refinery drains, leaving the work to retry"

: > "$FAKE_LOG"
mkdir -p "$TMP/empty-city"
RUN_CITY="$TMP/empty-city" run_block "$R/rig" "$TMP/merge.sh" && bad "no detached-job.sh: the merge block exits non-zero" \
  || ok "no detached-job.sh: the merge block exits non-zero"
[ -e "$PW/left-by-the-gate" ] && ok "no detached-job.sh: the prep worktree is not rebuilt" \
  || bad "no detached-job.sh: the prep worktree is not rebuilt"
grep -q DRAIN "$FAKE_LOG" && ok "no detached-job.sh: the refinery drains, leaving the work to retry" \
  || bad "no detached-job.sh: the refinery drains, leaving the work to retry"

: > "$FAKE_LOG"
NOWS="$TMP/nows-city"
mkdir -p "$NOWS/rigs/gc-toolkit/assets/scripts"
cp "$HERE/detached-job.sh" "$NOWS/rigs/gc-toolkit/assets/scripts/"
RUN_CITY="$NOWS" run_block "$R/rig" "$TMP/merge.sh" && bad "no refinery-workspace.sh: the merge block exits non-zero" \
  || ok "no refinery-workspace.sh: the merge block exits non-zero"
[ -e "$PW/left-by-the-gate" ] && ok "no refinery-workspace.sh: the prep worktree is not rebuilt" \
  || bad "no refinery-workspace.sh: the prep worktree is not rebuilt"
grep -q DRAIN "$FAKE_LOG" && ok "no refinery-workspace.sh: the refinery drains, leaving the work to retry" \
  || bad "no refinery-workspace.sh: the refinery drains, leaving the work to retry"

# --- 5. merge mode (shared branch is brought current by merge, not rebase). ----
M="$TMP/merge"; build_repo "$M" "integration/conv"
export FAKE_META='[{"metadata":{"branch":"integration/conv","target":"main"}}]'
run_block "$M/rig" "$TMP/merge.sh" && ok "merge block (merge mode) exits 0" || bad "merge block (merge mode) exits 0"
eq "$(head_of "$M/rig")" "main" "merge mode: rig root stays on main"
PWM="$(prep_of "$M/rig")"
git -C "$PWM" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && bad "merge mode: merge completed (no conflict left)" || ok "merge mode: merge completed (no conflict left)"

# --- 6. Pre-stranded root: the rig root is already on a local `temp` branch. ---
# The exact state this bead exists to survive: the old code's `git checkout -b
# temp` in the root, left there by a mid-flow suspend. A `worktree add -B temp`
# refuses here ("cannot force update the branch 'temp' used by worktree"), the
# unstaged prepare then fails, and the flow mis-rejects the work as a target
# conflict while leaving the root stranded. A detached prep worktree touches no
# `temp` branch, so it stages regardless of what the root is on. The staged-and-
# prepared assertions are the discriminator: the old `-B temp` add never created
# the worktree in this state, so neither could hold.
S="$TMP/stranded"; build_repo "$S" "polecat/wb"
export FAKE_META='[{"metadata":{"branch":"polecat/wb","target":"main"}}]'
( cd "$S/rig" && git checkout -q -b temp )   # strand the root on temp, as the old bug did
run_block "$S/rig" "$TMP/merge.sh" \
  && ok "pre-stranded root: merge block stages instead of false-rejecting" \
  || bad "pre-stranded root: merge block stages instead of false-rejecting"
PWS="$(prep_of "$S/rig")"
[ -d "$PWS" ] && ok "pre-stranded root: prep worktree staged despite the root holding temp" || bad "pre-stranded root: prep worktree staged despite the root holding temp" "$PWS"
git -C "$PWS" cat-file -e HEAD:h 2>/dev/null && git -C "$PWS" cat-file -e HEAD:g 2>/dev/null \
  && ok "pre-stranded root: prepared head carries the feature and the advanced base" \
  || bad "pre-stranded root: prepared head carries the feature and the advanced base"
eq "$(head_of "$S/rig")" "temp" "pre-stranded root: rig root left exactly as found (un-stranding is reconcile's job, not the refinery's)"

echo "-----"
echo "refinery-prep-worktree: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
