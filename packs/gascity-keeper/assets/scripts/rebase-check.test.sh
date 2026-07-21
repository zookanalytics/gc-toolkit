#!/usr/bin/env bash
# Hermetic test for rebase-check.sh, the exit condition of the `rebase` check
# loop in mol-upstream-gc-rebase.
#
# This script decides whether a rebase is finished and safe to install/push, so
# every wrong PASS force-pushes an unverified history onto the fork's main
# branch and every wrong FAIL burns an iteration. The cases below pin both
# directions, with particular attention to the two ways a stale stamp could
# certify the wrong tree:
#
#   - check_passed_sha left over from an earlier HEAD (gate ran, then more
#     commits landed), and
#   - a `git rebase --abort` that returns HEAD to the pre-rebase tip, which an
#     old check_passed_sha stamped on that same tip would otherwise match.
#
# EXECUTES the real shipped script against stub `bd` / `gc` binaries and a real
# temporary git repo. No live city, Dolt, network, or worktrees.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/rebase-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }

# --- stubs -------------------------------------------------------------------
# Both stubs read $TMP/state.env, so each case can vary the bead metadata the
# script sees without re-writing the stubs.
mkdir -p "$TMP/bin"

cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# bd show <id> --json
. "$STATE"
[ "$1" = "show" ] || exit 1
case "$2" in
  "$ROOT_ID")
    printf '[{"id":"%s","metadata":{"gc.input_convoy_id":"%s"}}]' "$ROOT_ID" "$CONVOY_ID"
    ;;
  "$ISSUE_ID")
    printf '[{"id":"%s","metadata":{' "$ISSUE_ID"
    sep=""
    [ -n "$MD_WORK_DIR" ]   && { printf '%s"work_dir":"%s"' "$sep" "$MD_WORK_DIR"; sep=","; }
    [ -n "$MD_ONTO" ]       && { printf '%s"rebase_onto_sha":"%s"' "$sep" "$MD_ONTO"; sep=","; }
    [ -n "$MD_GATE" ]       && { printf '%s"check_passed_sha":"%s"' "$sep" "$MD_GATE"; sep=","; }
    printf '}}]'
    ;;
  *)
    # An iteration bead: carries the root pointer for the GC_WISP_ID fallback.
    printf '[{"id":"%s","metadata":{"gc.root_bead_id":"%s"}}]' "$2" "$ROOT_ID"
    ;;
esac
BD

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# gc convoy status <convoy> --json
. "$STATE"
if [ "$1" = "convoy" ] && [ "$2" = "status" ]; then
  if [ "$CONVOY_MEMBERS" = "1" ]; then
    printf '{"children":[{"id":"%s"}]}' "$ISSUE_ID"
  else
    printf '{"children":[]}'
  fi
  exit 0
fi
exit 0
GC

chmod +x "$TMP/bin/bd" "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export STATE="$TMP/state.env"

# --- fixture repo ------------------------------------------------------------
# UPSTREAM_SHA is the tip the rebase targets; HEAD carries one replayed commit
# on top of it. DIVERGENT_SHA models a commit that is NOT an ancestor of HEAD.
WT="$TMP/worktree"
mkdir -p "$WT"
git -C "$WT" init -q
git -C "$WT" config user.email t@example.com
git -C "$WT" config user.name  Test
echo base > "$WT/f"; git -C "$WT" add f; git -C "$WT" commit -qm base
UPSTREAM_SHA=$(git -C "$WT" rev-parse HEAD)
git -C "$WT" checkout -q -b divergent
echo other > "$WT/g"; git -C "$WT" add g; git -C "$WT" commit -qm divergent
DIVERGENT_SHA=$(git -C "$WT" rev-parse HEAD)
git -C "$WT" checkout -q master 2>/dev/null || git -C "$WT" checkout -q main
echo kept > "$WT/f"; git -C "$WT" add f; git -C "$WT" commit -qm "kept commit"
HEAD_SHA=$(git -C "$WT" rev-parse HEAD)

write_state() {
  cat > "$STATE" <<EOF
ROOT_ID="${ROOT_ID-wisp-1}"
CONVOY_ID="${CONVOY_ID-convoy-1}"
CONVOY_MEMBERS="${CONVOY_MEMBERS-1}"
ISSUE_ID="${ISSUE_ID-gc-issue}"
MD_WORK_DIR="${MD_WORK_DIR-$WT}"
MD_ONTO="${MD_ONTO-$UPSTREAM_SHA}"
MD_GATE="${MD_GATE-$HEAD_SHA}"
EOF
}

# Run the script in a cwd that is deliberately NOT the fixture worktree: the
# script must resolve the worktree from bead metadata, never from cwd.
run_case() {
  local desc="$1" want="$2"
  ( cd "$TMP" && GC_WISP_ID="${ROOT_ID-wisp-1}" GC_BEAD_ID=iter-1 bash "$SCRIPT" ) >"$TMP/out" 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then
    ok "$desc (exit $got)"
  else
    bad "$desc (got exit $got, want $want)"
    sed 's/^/       /' "$TMP/out"
  fi
}

reset_env() {
  unset ROOT_ID CONVOY_ID CONVOY_MEMBERS ISSUE_ID MD_WORK_DIR MD_ONTO MD_GATE
}

# --- 1. happy path -----------------------------------------------------------
reset_env; write_state
run_case "PASS when rebase is done, tree clean, and gate green at HEAD" 0

# --- 2. rebase still in progress --------------------------------------------
reset_env; write_state
mkdir -p "$WT/.git/rebase-merge"
run_case "FAIL while a rebase is in progress (rebase-merge)" 1
rmdir "$WT/.git/rebase-merge"

reset_env; write_state
mkdir -p "$WT/.git/rebase-apply"
run_case "FAIL while a rebase is in progress (rebase-apply)" 1
rmdir "$WT/.git/rebase-apply"

# --- 3. dirty worktree -------------------------------------------------------
reset_env; write_state
echo dirty >> "$WT/f"
run_case "FAIL when the worktree has uncommitted changes" 1
git -C "$WT" checkout -q -- f

# --- 4. gate not yet run -----------------------------------------------------
reset_env; MD_GATE=""; write_state
run_case "FAIL when no check_passed_sha is recorded" 1

# --- 5. stale gate stamp -----------------------------------------------------
reset_env; MD_GATE="$UPSTREAM_SHA"; write_state
run_case "FAIL when check_passed_sha is stale (gate ran at an older HEAD)" 1

# --- 6. the abort trap -------------------------------------------------------
# HEAD back at the pre-rebase tip with a matching stamp from an earlier run:
# the ancestry check is the only thing standing between this and a wrong PASS.
reset_env; MD_ONTO="$DIVERGENT_SHA"; MD_GATE="$HEAD_SHA"; write_state
run_case "FAIL when HEAD is not descended from rebase_onto_sha" 1

# --- 7. missing loop state ---------------------------------------------------
reset_env; MD_ONTO=""; write_state
run_case "FAIL when rebase_onto_sha was never stamped" 1

reset_env; MD_WORK_DIR=""; write_state
run_case "FAIL when the work bead has no work_dir" 1

reset_env; MD_WORK_DIR="$TMP/does-not-exist"; write_state
run_case "FAIL when the recorded work_dir is missing from disk" 1

reset_env; MD_WORK_DIR="$TMP"; write_state
run_case "FAIL when the recorded work_dir is not a git worktree" 1

reset_env; CONVOY_MEMBERS=0; write_state
run_case "FAIL when the convoy does not have exactly one tracked member" 1

# --- 8. HEAD exactly at the upstream tip (empty kept set) --------------------
# A rebase that drops every divergent commit is legitimate: --is-ancestor is
# true for equal commits, so this must PASS rather than look like an abort.
git -C "$WT" checkout -q -B empty-kept "$UPSTREAM_SHA"
reset_env; MD_GATE="$UPSTREAM_SHA"; write_state
run_case "PASS when every commit was dropped and HEAD equals the upstream tip" 0

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
