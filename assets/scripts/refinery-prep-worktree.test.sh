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
# the exact case that used to strand it. Also covers the prepare's conflict
# handling: a conflict confined to generated/seed-audit is finished by
# regen-merge.sh and pushed as a fast-forward, while a hand-written conflict, or
# a host where the resolver is unreachable, still fails the prepare.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-prep-worktree-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
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
( cd "$R/rig" && GC_RIG_ROOT="$R/rig" BRANCH=polecat/wb bash "$TMP/push.sh" ) >/dev/null 2>&1 \
  && ok "push block exits 0" || bad "push block exits 0"
eq "$(head_of "$R/rig")" "main" "after push: rig root still on main"
eq "$(git -C "$R/rig" rev-parse origin/polecat/wb)" "$(git -C "$PW" rev-parse HEAD)" "after push: origin/branch == the merged prepared head"

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

# --- 7. A conflict confined to generated/seed-audit is finished by a render. ----
# The base moved a render input the branch also moved, at another line: the
# input merges cleanly and the manifest record both sides rewrote conflicts.
# The block reaches the real regen-merge.sh the way the refinery does on a rig
# that is not the pack, through GC_CITY_PATH/rigs/gc-toolkit, and the merged
# tree's own renderer is a stub that writes the tree as a pure function of
# inputs/. A hand-written conflict on another branch still fails the prepare,
# and so does the generated one when no resolver is reachable.
CITY="$TMP/city"; mkdir -p "$CITY/rigs/gc-toolkit/assets/scripts"
cp "$HERE/regen-merge.sh" "$CITY/rigs/gc-toolkit/assets/scripts/regen-merge.sh"
chmod +x "$CITY/rigs/gc-toolkit/assets/scripts/regen-merge.sh"
# In-place edit that BSD and GNU sed read alike: BSD sed takes the word after -i
# as a backup suffix and GNU sed takes it as the script, so the suffix is attached.
# The backup is removed at once, before a fixture commit can pick it up.
sedi() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }
build_regen_repo() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git init -q -b main "$d/seed"; (
    cd "$d/seed"; git config user.email t@t; git config user.name t
    mkdir -p inputs assets/scripts
    cat > assets/scripts/render-seed-audit.sh <<'RENDER'
#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/generated/seed-audit"
rm -rf "$OUT"; mkdir -p "$OUT"
for f in "$ROOT"/inputs/*.txt; do
  printf 'inputs/%s\n%s\n' "$(basename "$f")" "$(cksum < "$f" | cut -d' ' -f1)" >> "$OUT/SOURCES.txt"
done
RENDER
    chmod +x assets/scripts/render-seed-audit.sh
    printf 'b1\nb2\nb3\nb4\nb5\nb6\n' > inputs/b.txt
    printf 'n1\nn2\nn3\n' > notes.txt
    bash assets/scripts/render-seed-audit.sh; git add -A; git commit -qm base
    git remote add origin ../origin.git; git push -q origin HEAD:main
    git checkout -qb polecat/gen
    sedi 's/^b1$/b1 by the branch/' inputs/b.txt
    bash assets/scripts/render-seed-audit.sh; git add -A; git commit -qm gen; git push -q origin polecat/gen
    git checkout -qb polecat/hand main
    sedi 's/^n2$/n2 by the branch/' notes.txt; git commit -qam hand; git push -q origin polecat/hand
    git checkout -q main
    sedi 's/^b6$/b6 by main/' inputs/b.txt; sedi 's/^n2$/n2 by main/' notes.txt
    bash assets/scripts/render-seed-audit.sh; git add -A; git commit -qm "main moves b and notes"
    git push -q origin HEAD:main
  ) >/dev/null 2>&1
  git clone -q "$d/origin.git" "$d/rig"
  ( cd "$d/rig"; git config user.email r@r; git config user.name r; git checkout -q -B main origin/main )
}
# The block with its verdict appended, since PREPARE_FAILED is what the step
# after it reads.
{ cat "$TMP/merge.sh"; printf '\necho "PREPARE_FAILED=[$PREPARE_FAILED]"\n'; } > "$TMP/merge-verdict.sh"
run_verdict() { # <rig> <city-path or ""> — prints the block's verdict line
  ( cd "$1" && GC_RIG_ROOT="$1" GC_CITY_PATH="$2" WORK=wb TARGET_BRANCH_DEFAULT=main bash "$TMP/merge-verdict.sh" ) 2>/dev/null \
    | grep '^PREPARE_FAILED='
}

G="$TMP/regen"; build_regen_repo "$G"
export FAKE_META='[{"metadata":{"branch":"polecat/gen","target":"main"}}]'
eq "$(run_verdict "$G/rig" "$CITY")" "PREPARE_FAILED=[]" "generated-only conflict: the prepare succeeds instead of repooling"
PWG="$(prep_of "$G/rig")"
git -C "$PWG" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && bad "generated-only conflict: merge committed (none left in progress)" || ok "generated-only conflict: merge committed (none left in progress)"
eq "$(git -C "$PWG" rev-parse HEAD^1)" "$(git -C "$G/rig" rev-parse origin/polecat/gen)" "generated-only conflict: the merge's first parent is the branch"
eq "$(git -C "$PWG" rev-parse HEAD^2)" "$(git -C "$G/rig" rev-parse origin/main)" "generated-only conflict: …and its second is the target"
( cd "$PWG" && bash assets/scripts/render-seed-audit.sh >/dev/null 2>&1 )
eq "$(git -C "$PWG" status --porcelain | wc -l | tr -d ' ')" "0" "generated-only conflict: the prepared head carries a render of the merged inputs"
eq "$(head_of "$G/rig")" "main" "generated-only conflict: rig root stays on main"
( cd "$G/rig" && GC_RIG_ROOT="$G/rig" BRANCH=polecat/gen bash "$TMP/push.sh" ) >/dev/null 2>&1 \
  && ok "generated-only conflict: push block exits 0" || bad "generated-only conflict: push block exits 0"
eq "$(git -C "$G/rig" rev-parse origin/polecat/gen)" "$(git -C "$PWG" rev-parse HEAD)" "generated-only conflict: origin/branch fast-forwards to the resolved merge"

export FAKE_META='[{"metadata":{"branch":"polecat/hand","target":"main"}}]'
eq "$(run_verdict "$G/rig" "$CITY")" "PREPARE_FAILED=[1]" "hand-written conflict: the prepare still fails, for the repool"
PWG="$(prep_of "$G/rig")"
git -C "$PWG" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && bad "hand-written conflict: the abort ran (no merge left in progress)" || ok "hand-written conflict: the abort ran (no merge left in progress)"
eq "$(git -C "$PWG" rev-parse HEAD)" "$(git -C "$G/rig" rev-parse origin/polecat/hand)" "hand-written conflict: nothing was committed over the branch"

G2="$TMP/regen-noresolver"; build_regen_repo "$G2"
export FAKE_META='[{"metadata":{"branch":"polecat/gen","target":"main"}}]'
eq "$(run_verdict "$G2/rig" "")" "PREPARE_FAILED=[1]" "no resolver reachable: a generated-only conflict fails the prepare as before"
git -C "$(prep_of "$G2/rig")" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && bad "no resolver reachable: the abort ran" || ok "no resolver reachable: the abort ran"

echo "-----"
echo "refinery-prep-worktree: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
