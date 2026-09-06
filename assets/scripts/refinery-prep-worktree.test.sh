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
# Runs the REAL blocks extracted verbatim from the formula against a real git
# repo (worktrees need one) and a stub `gc`. cwd is deliberately the rig root —
# the exact case that used to strand it.
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
  grep -q '[\]' "$TMP/$b.sh" && bad "$b block backslash-free (TOML would eat it)" || ok "$b block backslash-free (TOML would eat it)"
  bash -n "$TMP/$b.sh" && ok "$b block is valid bash" || bad "$b block is valid bash"
done
# The whole point: no bare checkout/rebase/merge/switch that would move cwd HEAD.
grep -Eq 'git (checkout|switch|rebase|merge)( |$)' "$TMP/merge.sh" \
  && bad "merge block never runs a bare HEAD-moving git in cwd" \
  || ok "merge block never runs a bare HEAD-moving git in cwd"
grep -q 'git checkout temp' "$TMP/push.sh" \
  && bad "push block does not check temp out in cwd" \
  || ok "push block does not check temp out in cwd"

# --- 2. Stub gc: bd show returns $FAKE_META; bd update / drain-ack are no-ops. --
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
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

# Run an extracted block from INSIDE the rig root (the stranding case).
run_block() { # <rig> <block-file>
  ( cd "$1" && GC_RIG_ROOT="$1" WORK=wb TARGET_BRANCH_DEFAULT=main bash "$2" ) >/dev/null 2>&1
}
head_of()  { git -C "$1" rev-parse --abbrev-ref HEAD; }
prep_of()  { echo "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"; }

# --- 3. rebase mode (polecat/* branch). ---------------------------------------
R="$TMP/rebase"; build_repo "$R" "polecat/wb"
export FAKE_META='[{"metadata":{"branch":"polecat/wb","target":"main"}}]'
run_block "$R/rig" "$TMP/merge.sh" && ok "merge block (rebase mode) exits 0" || bad "merge block (rebase mode) exits 0"
eq "$(head_of "$R/rig")" "main" "rebase mode: rig root stays on main (never checked out temp)"
PW="$(prep_of "$R/rig")"
[ -d "$PW" ] && ok "rebase mode: branch staged in the prep worktree" || bad "rebase mode: branch staged in the prep worktree" "$PW"
eq "$(git -C "$PW" rev-parse --abbrev-ref HEAD 2>/dev/null)" "HEAD" "rebase mode: prep worktree is detached (creates no branch)"
git -C "$R/rig" show-ref --verify --quiet refs/heads/temp \
  && bad "rebase mode: no local temp branch created (the collision the fix removes)" \
  || ok "rebase mode: no local temp branch created (the collision the fix removes)"
case "$PW" in "$R/rig/.git/"*) ok "prep worktree lives inside the git dir (invisible to working trees)" ;; *) bad "prep worktree lives inside the git dir" "$PW" ;; esac
eq "$(git -C "$R/rig" status --porcelain | wc -l | tr -d ' ')" "0" "rebase mode: rig root working tree stays clean (no untracked prep dir)"
# The prepared head actually rebased: it carries the base's landed commit (h) plus the feature (g).
git -C "$PW" cat-file -e HEAD:h 2>/dev/null && git -C "$PW" cat-file -e HEAD:g 2>/dev/null \
  && ok "rebase mode: prepared head carries feature rebased onto advanced base" \
  || bad "rebase mode: prepared head carries feature rebased onto advanced base"

# push block: ships the prepared head -> origin/<branch> without a cwd checkout; root unmoved.
( cd "$R/rig" && GC_RIG_ROOT="$R/rig" BRANCH=polecat/wb bash "$TMP/push.sh" ) >/dev/null 2>&1 \
  && ok "push block exits 0" || bad "push block exits 0"
eq "$(head_of "$R/rig")" "main" "after push: rig root still on main"
eq "$(git -C "$R/rig" rev-parse origin/polecat/wb)" "$(git -C "$PW" rev-parse HEAD)" "after push: origin/branch == the rebased prepared head"

# --- 4. idempotency: a leftover prep worktree from an interrupted run. ---------
run_block "$R/rig" "$TMP/merge.sh" && ok "merge block re-runs cleanly over a leftover prep worktree" || bad "merge block re-runs cleanly over a leftover prep worktree"
eq "$(head_of "$R/rig")" "main" "idempotent re-run: rig root still on main"

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
# unstaged rebase then fails, and the flow mis-rejects the work as a target
# conflict while leaving the root stranded. A detached prep worktree touches no
# `temp` branch, so it stages regardless of what the root is on. The staged-and-
# rebased assertions are the discriminator: the old `-B temp` add never created
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
  && ok "pre-stranded root: prepared head carries feature rebased onto advanced base" \
  || bad "pre-stranded root: prepared head carries feature rebased onto advanced base"
eq "$(head_of "$S/rig")" "temp" "pre-stranded root: rig root left exactly as found (un-stranding is reconcile's job, not the refinery's)"

echo "-----"
echo "refinery-prep-worktree: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
