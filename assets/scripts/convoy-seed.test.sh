#!/usr/bin/env bash
# Hermetic test for assets/scripts/convoy-seed.sh. Runs the shipped script
# against a stub `gc` and REAL git repos (a bare origin plus a rig clone) so the
# worktree add / push / remove run for real, and asserts:
#   - the convoy is created once and its target set to integration/<id>,
#   - the integration branch is cut and pushed, starting == the default branch
#     when nothing is seeded and ahead of it when an artifact is,
#   - the rig root's working tree is NEVER moved (the disposable-worktree
#     safety constraint) and no worktree or local branch ref leaks,
#   - the cut is detached: it creates no local integration branch, so a crashed
#     run that leaked a checked-out integration branch does not block the retry,
#   - --id-file receives the convoy id the instant it is created, before the cut,
#     so a failure after create still lets the caller resume against that convoy,
#   - resume is idempotent: a supplied convoy id skips creation and an existing
#     origin branch skips the cut,
#   - it fails closed on a missing name or a non-git rig root.
# No live city, network, gc or bd.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/convoy-seed.sh"
[ -f "$SUT" ] || { echo "missing $SUT" >&2; exit 1; }

command -v jq  >/dev/null 2>&1 || { echo "jq required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git required" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-convoy-seed-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2'" ;; esac; }

# Own the environment: never read the operator's live city.
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true

# --- Stub gc: convoy create emits JSON and requires --owned; convoy target is
#     logged; every other subcommand is refused, as real `gc convoy` would. -----
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${GC_LOG:?}"
[ "${1:-}" = convoy ] || { echo "gc stub: unsupported '${1:-}'" >&2; exit 2; }
case "${2:-}" in
  create)
    case " $* " in *" --owned "*) ;; *) echo "gc convoy create: --owned required" >&2; exit 2 ;; esac
    printf '{"convoy_id":"%s"}\n' "${STUB_CONVOY_ID:-cv-seed-1}" ;;
  target)
    # STUB_TARGET_FAIL forces a failure AFTER convoy create, to prove the id is
    # persisted to --id-file before the cut can fail.
    [ -n "${STUB_TARGET_FAIL:-}" ] && { echo "gc convoy target: stub forced failure" >&2; exit 2; }
    : ;;
  *) echo "gc convoy stub: unsupported convoy subcommand '${2:-}'" >&2; exit 2 ;;
esac
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export GC_LOG="$TMP/gc.log"
: > "$GC_LOG"

# --- Build a REAL bare origin + rig clone so worktree/push run for real. -------
git init -q --bare "$TMP/origin.git"
RIG="$TMP/rig"
git init -q "$RIG"
git -C "$RIG" config user.email t@t
git -C "$RIG" config user.name  tester
git -C "$RIG" config commit.gpgsign false
printf 'base\n' > "$RIG/README.md"
git -C "$RIG" add README.md
git -C "$RIG" commit -qm base
git -C "$RIG" branch -M main
git -C "$RIG" remote add origin "$TMP/origin.git"
git -C "$RIG" push -q origin main
git -C "$RIG" remote set-head origin main
MAIN_TIP=$(git -C "$TMP/origin.git" rev-parse refs/heads/main)

# --- 1. Fresh happy path: no artifact -----------------------------------------
echo "# fresh seed (design-convoy, no artifact)"
IDF1="$TMP/idfile-1"
out=$( "$SUT" --name "Design convoy" --id-file "$IDF1" --rig-root "$RIG" 2>&1 ); rc=$?
eq "$rc" 0 "fresh seed exits 0"
eq "$(cat "$IDF1" 2>/dev/null)" "cv-seed-1" "fresh seed writes convoy id to --id-file"
has "$out" "convoy_id=cv-seed-1"          "prints convoy_id"
has "$out" "branch=integration/cv-seed-1" "prints branch"
eq "$(grep -c 'convoy create' "$GC_LOG")" 1 "convoy create called exactly once"
has "$(cat "$GC_LOG")" "convoy target cv-seed-1 integration/cv-seed-1" "target set to integration branch"
git -C "$TMP/origin.git" show-ref --verify --quiet refs/heads/integration/cv-seed-1 \
  && ok "integration branch pushed to origin" || bad "integration branch pushed to origin"
eq "$(git -C "$TMP/origin.git" rev-parse refs/heads/integration/cv-seed-1)" "$MAIN_TIP" \
  "unseeded integration branch starts == default branch"
# The safety constraint: the rig root's working tree is never moved.
eq "$(git -C "$RIG" symbolic-ref --short HEAD)" "main" "rig root HEAD still on default branch"
eq "$(git -C "$RIG" status --porcelain)" "" "rig root working tree clean"
eq "$(git -C "$RIG" worktree list | wc -l | tr -d ' ')" "1" "no leftover worktree"
git -C "$RIG" show-ref --verify --quiet refs/heads/integration/cv-seed-1 \
  && bad "no lingering local integration branch ref" || ok "no lingering local integration branch ref"

# --- 2. Idempotent resume: origin already has the branch, id supplied ----------
echo "# resume (idempotent)"
: > "$GC_LOG"
out=$( "$SUT" --name "Design convoy" --convoy cv-seed-1 --rig-root "$RIG" 2>&1 ); rc=$?
eq "$rc" 0 "resume seed exits 0"
grep -q "convoy create" "$GC_LOG" && bad "resume skips convoy create" || ok "resume skips convoy create"
has "$(cat "$GC_LOG")" "convoy target cv-seed-1 integration/cv-seed-1" "resume re-sets target (idempotent)"
eq "$(git -C "$TMP/origin.git" rev-parse refs/heads/integration/cv-seed-1)" "$MAIN_TIP" \
  "resume does not re-cut the branch"
eq "$(git -C "$RIG" worktree list | wc -l | tr -d ' ')" "1" "resume leaves no worktree"

# --- 3. Artifact seeding ------------------------------------------------------
echo "# artifact seed"
: > "$GC_LOG"
export STUB_CONVOY_ID=cv-seed-2
printf 'shared decisions\n' > "$TMP/decisions.md"
out=$( "$SUT" --name "Artifact convoy" --artifact "$TMP/decisions.md" \
       --artifact-dest "docs/decisions.md" --artifact-message "chore: seed decisions" \
       --rig-root "$RIG" 2>&1 ); rc=$?
eq "$rc" 0 "artifact seed exits 0"
git -C "$TMP/origin.git" cat-file -e refs/heads/integration/cv-seed-2:docs/decisions.md 2>/dev/null \
  && ok "artifact committed on the branch" || bad "artifact committed on the branch"
[ "$(git -C "$TMP/origin.git" rev-parse refs/heads/integration/cv-seed-2)" != "$MAIN_TIP" ] \
  && ok "seeded branch is ahead of default" || bad "seeded branch is ahead of default"
eq "$(git -C "$RIG" worktree list | wc -l | tr -d ' ')" "1" "artifact seed leaves no worktree"
unset STUB_CONVOY_ID

# --- 4. Fail-closed -----------------------------------------------------------
echo "# fail-closed"
"$SUT" --rig-root "$RIG" >/dev/null 2>&1 && bad "missing --name fails" || ok "missing --name fails"
mkdir -p "$TMP/notgit"
"$SUT" --name X --rig-root "$TMP/notgit" >/dev/null 2>&1 \
  && bad "non-git rig root fails" || ok "non-git rig root fails"

# --- 5. --json output ---------------------------------------------------------
echo "# json output"
: > "$GC_LOG"
export STUB_CONVOY_ID=cv-seed-3
js=$( "$SUT" --name "JSON convoy" --json --rig-root "$RIG" 2>/dev/null ); rc=$?
eq "$rc" 0 "json mode exits 0"
eq "$(printf '%s' "$js" | jq -r '.convoy_id')" "cv-seed-3"            "json convoy_id"
eq "$(printf '%s' "$js" | jq -r '.branch')"    "integration/cv-seed-3" "json branch"
unset STUB_CONVOY_ID

# --- 6. Crash-resume: a leaked worktree still holds a local integration branch -
# A hard crash mid-cut (before the trap or the push) leaves a worktree holding a
# checked-out integration/<id> branch while origin has no such branch yet. The
# pre-fix `branch -D` could not delete a checked-out branch and the retry's
# `worktree add -b` then failed because the branch existed. The detached cut must
# sail past the leak.
echo "# crash-resume with a stale checked-out integration branch"
: > "$GC_LOG"
export STUB_CONVOY_ID=cv-seed-4
STALE_WT="$TMP/stale-seed-wt"
git -C "$RIG" worktree add -q "$STALE_WT" -b integration/cv-seed-4 main
out=$( "$SUT" --name "Crash convoy" --convoy cv-seed-4 --rig-root "$RIG" 2>&1 ); rc=$?
eq "$rc" 0 "crash-resume exits 0 despite a leaked checked-out branch"
git -C "$TMP/origin.git" show-ref --verify --quiet refs/heads/integration/cv-seed-4 \
  && ok "crash-resume cut pushes the branch to origin" || bad "crash-resume cut pushes the branch to origin"
# Undo the simulated leak so the worktree-count invariant holds for any later run.
git -C "$RIG" worktree remove --force "$STALE_WT" >/dev/null 2>&1 || true
git -C "$RIG" branch -D integration/cv-seed-4 >/dev/null 2>&1 || true
eq "$(git -C "$RIG" worktree list | wc -l | tr -d ' ')" "1" "crash-resume leaves no extra worktree"
unset STUB_CONVOY_ID

# --- 7. id-file persisted before a failing cut --------------------------------
# convoy create succeeds, then the cut step fails. The id must already be in
# --id-file so the caller can resume against this convoy, not create a second.
echo "# id-file written before a failing cut"
: > "$GC_LOG"
export STUB_CONVOY_ID=cv-seed-5
IDF5="$TMP/idfile-5"
out=$( STUB_TARGET_FAIL=1 "$SUT" --name "IdFile convoy" --id-file "$IDF5" --rig-root "$RIG" 2>&1 ); rc=$?
[ "$rc" -ne 0 ] && ok "seed fails when the cut step fails" || bad "seed fails when the cut step fails"
eq "$(grep -c 'convoy create' "$GC_LOG")" 1 "convoy created exactly once before the failure"
eq "$(cat "$IDF5" 2>/dev/null)" "cv-seed-5" "convoy id persisted to --id-file before the cut failed"
unset STUB_CONVOY_ID

echo
echo "convoy-seed.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
