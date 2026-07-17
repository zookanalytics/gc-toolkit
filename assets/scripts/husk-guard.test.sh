#!/usr/bin/env bash
# Hermetic test for the witness-patrol HUSK GUARD (gc-7v0lx / gc-5v01w).
#
# THE BUG (SECURITY, HIGH): mol-witness-patrol Step 2 salvage reads the orphaned
# bead's metadata.work_dir into $WORKTREE, then Cases B/C/D `cd "$WORKTREE"` and
# run `git add -A && git commit && git push origin HEAD`. When work_dir is a
# HUSK — the git worktree was removed but the directory survives (typically only
# .gc/ left) — the `cd` still succeeds, but git finds no repo there and walks UP
# to the nearest enclosing repo: the TOWN repo at /home/zook/loomington. The
# salvage would then add, commit and PUSH the operator's uncommitted town-repo
# WIP to origin/main.
#
# THE FIX: before any salvage git write, assert work_dir is its OWN git worktree
# root (`git -C "$WORKTREE" rev-parse --show-toplevel` == work_dir's own root).
# If git resolves it to a parent/enclosing repo, refuse salvage (WORKTREE_SAFE=0)
# and handle the bead as Case E — escalate, fall through to cleanup/return-to-pool.
#
# This test EXECUTES the real guard extracted verbatim from the formula (between
# the `husk-guard` markers) against REAL git repos, so it cannot drift from the
# shipped instruction. Static guards then assert Cases B/C/D still gate on
# WORKTREE_SAFE. No live city, Dolt, network, or PRs — only git and a tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

# --- Extract the REAL guard from the formula. --------------------------------
# Pulls the lines between the markers (exclusive). If the markers or the guard
# are removed/renamed, extraction yields nothing and the check below fails
# loudly — the contract cannot silently disappear.
GUARD="$(awk '
  /# >>> husk-guard/ {f=1; next}
  /# <<< husk-guard/ {f=0}
  f' "$TOML")"

[ -n "$GUARD" ] \
  && ok "guard extracted between husk-guard markers" \
  || bad "guard extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$GUARD" > "$TMP/guard.sh"
bash -n "$TMP/guard.sh" \
  && ok "extracted guard is syntactically valid bash" \
  || bad "extracted guard failed bash -n"

# safe <work_dir> -> prints the resulting WORKTREE_SAFE value.
# The guard is sourced exactly as the witness runs it: WORKTREE preset, no set -e.
safe() {
  WORKTREE="$1" bash -c '
    WORKTREE="$WORKTREE"
    source "$0"
    printf "%s" "$WORKTREE_SAFE"
  ' "$TMP/guard.sh" 2>/dev/null
}

# --- Build a TOWN repo holding precious uncommitted operator WIP. -------------
TOWN="$TMP/town"
mkdir -p "$TOWN"
git -C "$TOWN" init -q .
git -C "$TOWN" config user.email t@t
git -C "$TOWN" config user.name t
echo committed > "$TOWN/tracked.txt"
git -C "$TOWN" add -A
git -C "$TOWN" commit -qm init
# The operator's uncommitted WIP — the thing that must never be pushed.
echo "OPERATOR WIP - MUST NEVER BE PUSHED" > "$TOWN/operator-wip.txt"

# A HUSK work_dir nested under the town repo: worktree gone, only .gc/ left.
HUSK="$TOWN/.gc/worktrees/gc-toolkit/polecats/gc-toolkit.polecat/tk-dead"
mkdir -p "$HUSK/.gc"

# A GENUINE git worktree — salvage must still work here (no false refusal).
LIVE="$TMP/live"
git -C "$TOWN" worktree add -q "$LIVE" --detach HEAD

# --- Premise: the hazard is real. --------------------------------------------
# From the husk, git resolves to the TOWN repo and `git add -A` stages the
# operator's WIP. If this ever stops being true the guard is moot — assert the
# premise so the test explains itself.
HUSK_TOPLEVEL="$(git -C "$HUSK" rev-parse --show-toplevel 2>/dev/null || true)"
eq "$HUSK_TOPLEVEL" "$(cd "$TOWN" && pwd -P)" \
   "(premise) git from a husk work_dir walks UP to the enclosing town repo"
(cd "$HUSK" && git add -A --dry-run 2>/dev/null | grep -q "operator-wip.txt") \
  && ok "(premise) unguarded 'git add -A' from a husk stages the town repo's operator WIP" \
  || bad "(premise) expected husk 'git add -A' to stage town operator WIP"

# --- Behavioral matrix. ------------------------------------------------------
# (A) THE FIX: a husk must be refused — this is the case that would otherwise
#     commit and push the town repo's working tree to origin/main.
eq "$(safe "$HUSK")" "0" \
   "(A) husk work_dir (git walks up to town repo) -> REFUSED, WORKTREE_SAFE=0"
# (B) Non-regression: a genuine worktree must still salvage. A guard that
#     refused everything would silently discard real work.
eq "$(safe "$LIVE")" "1" \
   "(B) genuine git worktree -> allowed, WORKTREE_SAFE=1"
# (C) Missing directory (witness already cleaned it) -> Case E, no writes.
eq "$(safe "$TMP/does-not-exist")" "0" \
   "(C) missing work_dir -> WORKTREE_SAFE=0"
# (D) Empty/absent metadata.work_dir -> Case E, no writes. Without the -n test
#     an empty WORKTREE would make `cd ""` a no-op and git would resolve to the
#     witness's own cwd.
eq "$(safe "")" "0" \
   "(D) empty work_dir (metadata absent) -> WORKTREE_SAFE=0"
# (E) A husk nested inside a real WORKTREE (not the town root) — the gc-toolkit
#     layout, where a polecat home is itself a worktree of the rig repo. Git
#     walks up to that worktree, so this must be refused too.
HOMEWT="$TMP/polecat-home"
git -C "$TOWN" worktree add -q "$HOMEWT" --detach HEAD
mkdir -p "$HOMEWT/worktrees/tk-dead2/.gc"
eq "$(safe "$HOMEWT/worktrees/tk-dead2")" "0" \
   "(E) husk nested inside a real worktree (rig-repo variant) -> WORKTREE_SAFE=0"
# (F) A genuine worktree reached through a SYMLINKED path must NOT be falsely
#     refused: the guard compares `pwd -P` against git's toplevel, and a false
#     refusal here would skip legitimate salvage and lose work.
ln -sfn "$LIVE" "$TMP/link-to-live"
eq "$(safe "$TMP/link-to-live")" "1" \
   "(F) genuine worktree via a symlinked path -> allowed (no false refusal)"
# (G) The refusal must be observable — the witness escalates on this message.
#     Run the guard raw here (safe() deliberately swallows stderr to keep the
#     matrix output clean) so the diagnostic reaches $TMP/err.
WORKTREE="$HUSK" bash -c '
  WORKTREE="$WORKTREE"
  source "$0"
' "$TMP/guard.sh" >/dev/null 2>"$TMP/err" || true
grep -q "REFUSING salvage" "$TMP/err" \
  && ok "(G) refusal emits a REFUSING salvage diagnostic on stderr" \
  || bad "(G) refusal must emit a REFUSING salvage diagnostic on stderr"

# --- Static wiring: the salvage cases must honor the guard. -------------------
# The guard only protects anything if Cases B/C/D actually gate on it. Assert
# each write-bearing case references WORKTREE_SAFE, so a future edit that drops
# the gate fails here rather than silently re-exposing the town repo.
for marker in \
  'REFUSING Case C salvage writes' \
  'REFUSING Case D salvage writes' \
  'Case B does not apply'; do
  grep -qF "$marker" "$TOML" \
    && ok "(H) salvage case gated: '$marker'" \
    || bad "(H) missing WORKTREE_SAFE gate: '$marker'"
done

# Every `git add -A` in the formula must sit inside a WORKTREE_SAFE-gated block.
# Cheap structural proxy: no `git add -A` may appear before the guard is defined.
# Both patterns anchor to line start so prose and comments that merely *mention*
# `git add -A` / `WORKTREE_SAFE=0` (there are several) don't match — only real
# command lines and the guard's actual assignment count.
GUARD_LINE=$(grep -nE '^WORKTREE_SAFE=0' "$TOML" | head -1 | cut -d: -f1)
FIRST_ADD=$(grep -nE '^[[:space:]]*git add -A' "$TOML" | head -1 | cut -d: -f1)
[ -n "$GUARD_LINE" ] && [ -n "$FIRST_ADD" ] && [ "$GUARD_LINE" -lt "$FIRST_ADD" ] \
  && ok "(I) HUSK GUARD is defined before the first 'git add -A' in the formula" \
  || bad "(I) HUSK GUARD must be defined before any 'git add -A' (got guard@${GUARD_LINE:-none} add@${FIRST_ADD:-none})"

# The formula must still parse as TOML after the edit (the guard lives inside a
# multi-line basic string, where a stray backslash escape would corrupt it).
if command -v python3 >/dev/null 2>&1; then
  python3 - "$TOML" <<'PY' && ok "(J) formula still parses as TOML" || bad "(J) formula failed to parse as TOML"
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
