#!/usr/bin/env bash
# Hermetic test for mol-polecat-work's workspace-setup worktree creation.
#
# The invariant: the per-bead task worktree belongs to the RIG checkout, not to
# whatever repo the session's cwd happens to be. workspace-setup names the rig
# by path — `git -C "$RIG_ROOT" worktree add` — so a session sitting in some
# other repo still registers its worktree in the rig. This EXECUTES the real
# block extracted verbatim from the formula against REAL git repos, so the test
# cannot drift from the shipped instruction. No live city, Dolt, or network.
#
# The discriminator: a control runs a BARE `git worktree add` from the same
# wrong cwd and proves it follows that cwd instead. Without the control the
# treatment's "landed in the rig, not cwd" would pass even if -C did nothing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-workspace-setup-worktree-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# Isolate from any ambient git context so cwd vs -C is the only thing steering,
# and from a global config that might sign or template commits.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- Extract the REAL snippet from the formula. ------------------------------
# Between the markers, exclusive. A reconciliation that drops or renames the
# markers yields nothing here and the checks below fail loudly.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}
ADD="$(extract workspace-setup-worktree-add)"
[ -n "$ADD" ] \
  && ok "worktree-add snippet extracted between markers" \
  || bad "worktree-add extraction EMPTY — markers missing from $TOML"

# `{{base_branch}}` is a formula placeholder, substituted here exactly as the
# molecule materializer does before the polecat reads the step.
SNIPPET="$TMP/add.sh"
printf '%s\n' "$ADD" | sed "s|{{base_branch}}|main|g" > "$SNIPPET"
bash -n "$SNIPPET" \
  && ok "extracted worktree-add snippet is valid bash" \
  || bad "extracted worktree-add snippet failed bash -n"

# The shipped line must name the rig by path, or the whole fix is gone.
case "$ADD" in
  *'git -C "$RIG_ROOT" worktree add'*) ok 'snippet names the rig by path (git -C "$RIG_ROOT")' ;;
  *) bad 'snippet does not use git -C "$RIG_ROOT" — a bare worktree add follows cwd' ;;
esac

# --- Two real repos: the rig, and an unrelated cwd. --------------------------
# Each carries refs/remotes/origin/main so `--detach origin/main` resolves
# without a network.
mk_repo() {
  git init -q "$1"
  ( cd "$1"
    git commit -q --allow-empty -m init
    git update-ref refs/remotes/origin/main HEAD )
}
RIG="$TMP/rig"
CWD="$TMP/elsewhere"
mk_repo "$RIG"
mk_repo "$CWD"

# in_wt_list <repo> <path> -> yes|no. Compares by realpath so a symlinked
# $TMPDIR does not turn a real match into a miss.
in_wt_list() {
  local want found=no p
  want="$(realpath -m "$2" 2>/dev/null || echo "$2")"
  while IFS= read -r p; do
    [ "$(realpath -m "$p" 2>/dev/null || echo "$p")" = "$want" ] && found=yes
  done < <(git -C "$1" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
  echo "$found"
}

# --- Treatment: the extracted snippet, run from the WRONG cwd. ---------------
# GC_RIG_ROOT names the rig; cwd is an unrelated repo. The worktree must land
# in the rig, and at the absolute WORKTREE_PATH the caller chose.
WT_FIX="$TMP/wt-fix"
( cd "$CWD"
  WORKTREE_PATH="$WT_FIX" GC_RIG_ROOT="$RIG" GC_RIG=ignored bash "$SNIPPET" ) >"$TMP/out.fix" 2>&1 \
  || { echo "snippet run failed:"; cat "$TMP/out.fix"; }
eq "$(in_wt_list "$RIG" "$WT_FIX")" yes "fix: worktree registered in the RIG repo"
eq "$(in_wt_list "$CWD" "$WT_FIX")" no  "fix: worktree NOT registered in the cwd repo"
[ -d "$WT_FIX" ] \
  && ok "fix: worktree created at the absolute WORKTREE_PATH, not under the rig" \
  || bad "fix: worktree path $WT_FIX does not exist"

# --- Control: a BARE worktree add, run from the same WRONG cwd. --------------
# What the formula used to ship. It proves the cwd genuinely steers a bare add,
# so the treatment above is a real discrimination, not a vacuous pass.
WT_BARE="$TMP/wt-bare"
( cd "$CWD"
  git worktree add "$WT_BARE" --detach origin/main ) >"$TMP/out.bare" 2>&1 \
  || { echo "control run failed:"; cat "$TMP/out.bare"; }
eq "$(in_wt_list "$CWD" "$WT_BARE")" yes "control: bare add follows cwd (registered in cwd repo)"
eq "$(in_wt_list "$RIG" "$WT_BARE")" no  "control: bare add never reaches the rig repo"

# --- Fallback: GC_RIG_ROOT empty resolves the rig via `gc rig list --json`. --
# The snippet's second arm. A fake `gc` answers the roster so the jq path runs
# without a live city.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<EOF
#!/bin/sh
if [ "\$1" = rig ] && [ "\$2" = list ]; then
  printf '%s\n' '{"rigs":[{"name":"myrig","path":"$RIG"}]}'
  exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/gc"
WT_FB="$TMP/wt-fallback"
( cd "$CWD"
  PATH="$TMP/bin:$PATH" WORKTREE_PATH="$WT_FB" GC_RIG_ROOT="" GC_RIG=myrig bash "$SNIPPET" ) >"$TMP/out.fb" 2>&1 \
  || { echo "fallback run failed:"; cat "$TMP/out.fb"; }
eq "$(in_wt_list "$RIG" "$WT_FB")" yes "fallback: gc rig list resolves the rig by name, worktree lands in it"
eq "$(in_wt_list "$CWD" "$WT_FB")" no  "fallback: worktree NOT registered in the cwd repo"

echo "----"
echo "workspace-setup-worktree-rig: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
