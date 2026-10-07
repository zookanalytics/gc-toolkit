#!/usr/bin/env bash
# Hermetic test for mol-polecat-work's workspace-setup work_dir + gc.work_branch
# stamp.
#
# `self-review` and `submit-and-exit` read `metadata.work_dir` from the work
# bead to locate its checkout; an unstamped path fails both closed (self-review
# burns its whole budget, one pool slot per attempt, then hands back). The
# worktree is resolved three ways — a fresh create, a reuse of a recorded one,
# and a rework child that adopts the anchor's already-checked-out worktree — and
# the create arm's own stamp covers only the first. This guard records the
# worktree on EVERY path by stamping the directory the polecat is in now.
#
# gc.work_branch is stamped the same way and for a parallel reason: the claim
# (hookClaimIdentityPatch) records it from the pool worktree's base checkout,
# never the branch the work lands on, so the close gate's reachability check
# (gc.work_commit on gc.work_branch) false-fires on every polecat-branch close
# until this block finalizes it to the branch HEAD is actually on here.
#
# What it holds:
#   1. PATH-AGNOSTIC — the stamp records `$(pwd)`, not a create-arm variable, so
#      it is correct wherever the worktree was resolved. A revert to
#      `work_dir="$WORKTREE_PATH"` (unset outside the create arm) is caught.
#   2. RECORDS THE ACTUAL CWD — run from any directory, it stamps that
#      directory, so reuse and the anchor-adopt path land the right value.
#   3. RECORDS THE REAL WORK BRANCH — gc.work_branch is stamped from the branch
#      HEAD is on, finalizing the claim-time base-checkout value so the close
#      gate checks gc.work_commit against the branch the work actually landed on.
#   4. SKIPS A DETACHED/UNRESOLVED HEAD — records no branch rather than blanking
#      the key, which would trip the gate's "shipped requires a branch" arm.
#
# EXECUTES the real snippet extracted verbatim from the formula against a fake
# `gc`, so the test cannot drift from the shipped instruction. No live city,
# Dolt, network, or worktrees.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-workspace-setup-record-worktree-gate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3" "'$2' unexpectedly in '$1'" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract the REAL snippet from the formula. -------------------------------
# The flag-flip pulls the lines between the markers (exclusive). Remove or
# rename the markers — the exact thing a wholesale reconciliation against base
# does — and extraction yields nothing and the checks below fail loudly.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}

BLOCK="$(extract workspace-setup-record-worktree)"

[ -n "$BLOCK" ] \
  && ok "block extracted between workspace-setup-record-worktree markers" \
  || bad "block extraction EMPTY — markers missing from $TOML"

# Two regions sharing one marker name would concatenate into one extraction and
# double every assertion below; pin the opener to a single occurrence.
eq "$(grep -c '^# >>> workspace-setup-record-worktree$' "$TOML")" "1" \
   "exactly one workspace-setup-record-worktree region"

# TOML `"""` strings eat a trailing backslash (line-ending escape), silently
# joining lines. The snippet is written backslash-free; assert it, because
# reintroducing a continuation is an easy and invisible edit.
case "$BLOCK" in
  *\\*) bad "snippet contains a backslash — TOML line-ending escapes will mangle it" ;;
  *)    ok  "snippet is backslash-free (safe inside a TOML triple-quoted string)" ;;
esac

printf '%s\n' "$BLOCK" > "$TMP/block.sh"
bash -n "$TMP/block.sh" \
  && ok "extracted block is syntactically valid bash" \
  || bad "extracted block failed bash -n"

# --- 1. Path-agnostic: records $(pwd), never a create-arm variable. -----------
# The bug was a stamp confined to the create arm. The fix records the directory
# the polecat is in, so it must not reach for WORKTREE_PATH (which exists only
# in that arm and is empty on the reuse and anchor-adopt paths).
has "$BLOCK" '$(pwd)' "stamp records the current directory"
no  "$BLOCK" 'WORKTREE_PATH' "stamp does not depend on the create-arm WORKTREE_PATH"

# --- Fake gc: `bd update` records its argv; everything else is a quiet no-op. -
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "bd update") shift 2; printf '%s\n' "$*" >> "${FAKE_UPDATE:-/dev/null}" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# Fake git: resolves the work branch the block records. FAKE_BRANCH drives it so
# the detached ("HEAD") and unresolved ("") cases are reproducible with no repo.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
[ "$1" = "rev-parse" ] && { printf '%s\n' "${FAKE_BRANCH:-}"; exit 0; }
exit 0
GIT
chmod +x "$TMP/bin/git"
export PATH="$TMP/bin:$PATH"

# run_from <dir> [branch] -> prints the single `gc bd update` argv the block
#   emitted. The block stamps $(pwd), so running it from <dir> must stamp <dir>;
#   [branch] is what the fake git reports for the work branch (default none).
run_from() {
  : > "$TMP/update"
  ( cd "$1" && WORK_BEAD_ID=tk-work FAKE_BRANCH="${2:-}" FAKE_UPDATE="$TMP/update" bash "$TMP/block.sh" )
  cat "$TMP/update"
}

# --- 2. Records the actual cwd on whatever path reached here. ------------------
# Two distinct worktrees stand in for "created here" and "adopted the anchor's".
# The stamp must follow the cwd, not a fixed path, so each run records its own.
CREATED="$TMP/created";  mkdir -p "$CREATED";  CREATED="$(cd "$CREATED" && pwd)"
ADOPTED="$TMP/adopted";  mkdir -p "$ADOPTED";  ADOPTED="$(cd "$ADOPTED" && pwd)"

OUT_CREATED="$(run_from "$CREATED")"
has "$OUT_CREATED" "work_dir=$CREATED" "create path: stamps the worktree it is in"
has "$OUT_CREATED" "tk-work"           "stamp targets the work bead"

OUT_ADOPTED="$(run_from "$ADOPTED")"
has "$OUT_ADOPTED" "work_dir=$ADOPTED" "anchor-adopt path: stamps the adopted worktree, not a fixed create path"

# Exactly one stamp per run — the block records once, idempotently.
eq "$(run_from "$CREATED" | grep -c 'work_dir=')" "1" "one work_dir stamp per run"

# --- 3. gc.work_branch records the real branch, finalizing the claim-time stamp.
# The claim records gc.work_branch from the pool worktree's base checkout (main),
# never the branch the work lands on; recording the branch HEAD is on here is what
# the close gate's reachability check reads. The stamp rides the same update as
# work_dir, so one `gc bd update` carries both.
OUT_BRANCH="$(run_from "$CREATED" "polecat/tk-work")"
has "$OUT_BRANCH" "gc.work_branch=polecat/tk-work" "on a branch: records the real work branch"
has "$OUT_BRANCH" "work_dir=$CREATED"              "…in the same update as work_dir"
no  "$OUT_BRANCH" "gc.work_branch=main"            "…not the claim-time base branch"
eq  "$(run_from "$CREATED" "polecat/tk-work" | grep -c 'gc.work_branch=')" "1" \
    "one gc.work_branch stamp per run"

# --- 4. A detached or unresolved HEAD records no branch rather than blanking it.
# A blank gc.work_branch trips the gate's "shipped requires a branch" arm, a
# different false-fire; the guard must skip the stamp, not write an empty value.
no  "$(run_from "$CREATED" "HEAD")" "gc.work_branch"   "detached HEAD: records no branch"
has "$(run_from "$CREATED" "HEAD")" "work_dir=$CREATED" "detached HEAD: still records work_dir"
no  "$(run_from "$CREATED" "")"     "gc.work_branch"   "unresolved HEAD: records no branch"
has "$(run_from "$CREATED" "")"     "work_dir=$CREATED" "unresolved HEAD: still records work_dir"

# --- Summary. -----------------------------------------------------------------
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
