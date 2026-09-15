#!/usr/bin/env bash
# Hermetic test for the witness-patrol WORKTREE CLEANUP (part 5 of
# recover-orphaned-beads).
#
# THE BUG: cleanup ran `git worktree remove "$WORKTREE" --force` for any owned
# bead with a nonempty work_dir. A husk work_dir (git worktree removed, the
# directory left behind) and an already-removed path both name no registered
# worktree, so `git worktree remove` exits 128; under the step's `set -e` that
# aborted recover-orphaned-beads before `orphan-dispose.sh` could release or
# skip the bead — one husk stalled the whole patrol pass.
#
# THE FIX: catch the failed removal so cleanup stays best-effort, then prune and
# fall through to disposal. This test EXECUTES the real block extracted verbatim
# from the formula (between the `worktree-cleanup` markers) under `set -e`
# against REAL git repos, so it cannot drift from the shipped instruction. No
# live city, Dolt, network, or PRs — only git and a tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-worktree-cleanup-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

# --- Extract the REAL block from the formula. --------------------------------
# Pulls the lines between the markers (exclusive). If the markers or the block
# are removed/renamed, extraction yields nothing and the check below fails
# loudly — the contract cannot silently disappear.
BLOCK="$(awk '
  /# >>> worktree-cleanup/ {f=1; next}
  /# <<< worktree-cleanup/ {f=0}
  f' "$TOML")"

[ -n "$BLOCK" ] \
  && ok "block extracted between worktree-cleanup markers" \
  || bad "block extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$BLOCK" > "$TMP/cleanup.sh"
bash -n "$TMP/cleanup.sh" \
  && ok "extracted block is syntactically valid bash" \
  || bad "extracted block failed bash -n"

# The block must carry no line-ending backslash: the description is a TOML basic
# ("""") string, where a trailing `\` is a line-continuation that eats the
# newline and the next line's indent, corrupting the extracted shell.
if grep -qE '\\[[:space:]]*$' "$TMP/cleanup.sh"; then
  bad "extracted block has a line-ending backslash (corrupts a TOML basic string)"
else
  ok "extracted block has no line-ending backslash"
fi

# run_cleanup OWNED WORKTREE GC_RIG_ROOT -> runs the block under `set -e`, then
# prints a sentinel. The sentinel reaches stdout only if the block ran to
# completion without aborting the shell — which is exactly what part 5 needs so
# disposal runs after cleanup. Returns the block's exit status.
run_cleanup() {
  OWNED="$1" WORKTREE="$2" GC_RIG_ROOT="$3" bash -c '
    set -euo pipefail
    source "$0"
    echo "__CLEANUP_DONE__"
  ' "$TMP/cleanup.sh"
}

# --- A rig repo with two genuine worktrees and two absent paths. -------------
RIG="$TMP/rig"
mkdir -p "$RIG"
git -C "$RIG" init -q .
git -C "$RIG" config user.email t@t
git -C "$RIG" config user.name t
echo committed > "$RIG/tracked.txt"
git -C "$RIG" add -A
git -C "$RIG" commit -qm init

# (B) a genuine registered worktree — cleanup must still remove it.
LIVE_B="$TMP/live-b"
git -C "$RIG" worktree add -q "$LIVE_B" --detach HEAD
# (E) a second genuine worktree — used to prove the OWNED gate is preserved.
LIVE_E="$TMP/live-e"
git -C "$RIG" worktree add -q "$LIVE_E" --detach HEAD
# (A) a husk: a directory that exists but is NOT a registered worktree of RIG.
HUSK="$TMP/husk/.gc/worktrees/gc-toolkit/polecats/gc-toolkit.polecat/tk-dead"
mkdir -p "$HUSK"
# (C) an already-removed path: nonempty work_dir whose directory is gone.
GONE="$TMP/gone"

# --- Premise: the hazard is real. --------------------------------------------
# `git worktree remove` on the husk exits non-zero, so without the catch the
# block would abort under `set -e`. If this ever stops being true the fix is
# moot — assert the premise so the test explains itself.
PREMISE_RC=0
git -C "$RIG" worktree remove "$HUSK" --force >/dev/null 2>&1 || PREMISE_RC=$?
[ "$PREMISE_RC" -ne 0 ] \
  && ok "(premise) raw 'git worktree remove <husk>' exits non-zero (rc=$PREMISE_RC)" \
  || bad "(premise) expected raw husk removal to fail"

# --- Behavioral matrix. Each run asserts the block did NOT abort (sentinel
#     present, exit 0) and that the intended side effect held. ---------------

# (A) THE FIX: a husk must not abort cleanup — this is the case that stalled the
#     whole patrol pass. The husk directory is left standing (removing a path
#     that resolves to an enclosing repo is the hazard the husk guard forbids).
A_OUT=""; A_RC=0
A_OUT="$(run_cleanup 1 "$HUSK" "$RIG")" || A_RC=$?
eq "$A_RC" "0" "(A) husk work_dir -> block exits 0 (no abort)"
grep -q "__CLEANUP_DONE__" <<< "$A_OUT" \
  && ok "(A) husk work_dir -> execution reaches disposal (sentinel printed)" \
  || bad "(A) husk work_dir aborted the step before disposal"
[ -d "$HUSK" ] \
  && ok "(A) husk directory is left standing (not deleted by cleanup)" \
  || bad "(A) cleanup deleted the husk directory"

# (B) Non-regression: a genuine registered worktree is still removed.
B_OUT=""; B_RC=0
B_OUT="$(run_cleanup 1 "$LIVE_B" "$RIG")" || B_RC=$?
eq "$B_RC" "0" "(B) genuine worktree -> block exits 0"
grep -q "__CLEANUP_DONE__" <<< "$B_OUT" \
  && ok "(B) genuine worktree -> execution reaches disposal" \
  || bad "(B) genuine worktree run aborted before disposal"
[ ! -d "$LIVE_B" ] \
  && ok "(B) genuine worktree was removed" \
  || bad "(B) genuine worktree survived — removal regressed"

# (C) An already-removed path (dir gone, still in metadata) must not abort.
C_OUT=""; C_RC=0
C_OUT="$(run_cleanup 1 "$GONE" "$RIG")" || C_RC=$?
eq "$C_RC" "0" "(C) already-removed path -> block exits 0 (no abort)"
grep -q "__CLEANUP_DONE__" <<< "$C_OUT" \
  && ok "(C) already-removed path -> execution reaches disposal" \
  || bad "(C) already-removed path aborted before disposal"

# (D) Empty work_dir (visit / graph.v2 step or root) -> the `-n` guard skips the
#     body entirely; the block is a no-op and never aborts.
D_OUT=""; D_RC=0
D_OUT="$(run_cleanup 1 "" "$RIG")" || D_RC=$?
eq "$D_RC" "0" "(D) empty work_dir -> block exits 0 (guard skips body)"
grep -q "__CLEANUP_DONE__" <<< "$D_OUT" \
  && ok "(D) empty work_dir -> execution reaches disposal" \
  || bad "(D) empty work_dir aborted before disposal"

# (E) OWNED=0 must not remove anything — the store guard refused ownership, so
#     the worktree is not the witness's to delete.
E_OUT=""; E_RC=0
E_OUT="$(run_cleanup 0 "$LIVE_E" "$RIG")" || E_RC=$?
eq "$E_RC" "0" "(E) OWNED=0 -> block exits 0"
[ -d "$LIVE_E" ] \
  && ok "(E) OWNED=0 -> worktree left intact (OWNED gate preserved)" \
  || bad "(E) OWNED=0 removed a worktree the guard refused to own"

# --- The formula must still parse as TOML after the edit (the block lives in a
#     multi-line basic string, where a stray escape would corrupt it). --------
if command -v python3 >/dev/null 2>&1; then
  python3 - "$TOML" <<'PY' && ok "(F) formula still parses as TOML" || bad "(F) formula failed to parse as TOML"
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
