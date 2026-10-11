#!/usr/bin/env bash
# Hermetic test for zero-diff-guard.sh: the refinery never lands a prepared
# branch that changes nothing against its target.
#
# What it holds:
#   1. PASS — a prepared head carrying a real change past its merge-base with
#      origin/<target> passes, writing nothing and draining nothing.
#   2. REFUSE — a head equal to the target, an empty commit, and a commit whose
#      tree is the target's are each refused: parked at refused_false_completion,
#      routed to a human, escalated, drained, exit 1.
#   3. FAIL CLOSED — a missing prep worktree is refused rather than passed, and
#      an unresolvable rig drains before touching the bead.
#   4. WIRING — mol-refinery-patrol's merge-push step runs the guard.
#
# Builds throwaway git repositories and fakes gc, lifecycle.sh and escalate.sh;
# no city, Dolt, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/zero-diff-guard.sh"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-zero-diff-guard-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }

[ -x "$SUT" ] || { echo "not executable: $SUT" >&2; exit 1; }
grep -qF '/zero-diff-guard.sh" --work "$WORK" --branch "$BRANCH" --target "$TARGET"' "$TOML" \
  && ok "merge-push runs zero-diff-guard.sh on the step's pins" \
  || bad "merge-push runs zero-diff-guard.sh on the step's pins"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# gc: `runtime drain-ack` and `rig list` (an empty roster) are all it is asked.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG" ;;
  "rig list")          printf '{"rigs":[]}\n' ;;
esac
exit 0
GC
cat > "$TMP/bin/lifecycle" <<'LC'
#!/usr/bin/env bash
printf 'LC %s\n' "$*" >> "$FAKE_LOG"
LC
cat > "$TMP/bin/escalate" <<'ESC'
#!/usr/bin/env bash
printf 'ESCALATE %s\n' "$*" >> "$FAKE_LOG"
ESC
chmod +x "$TMP/bin/gc" "$TMP/bin/lifecycle" "$TMP/bin/escalate"
export PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log"
export GC_LIFECYCLE_TOOL="$TMP/bin/lifecycle" GC_ESCALATE_TOOL="$TMP/bin/escalate"

# rig <dir>: an origin with main, a rig clone of it, and the prep worktree
# path the rebase step stages into (not yet created).
rig() {
  git init -q --bare -b main "$1/origin.git"
  git init -q -b main "$1/seed"
  printf 'base\n' > "$1/seed/f.txt"
  git -C "$1/seed" add f.txt
  git -C "$1/seed" commit -q -m base
  git -C "$1/seed" push -q "$1/origin.git" main
  git clone -q "$1/origin.git" "$1/rig"
  PREP="$(git -C "$1/rig" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"
}

# stage <dir> <how>: put the prep worktree's HEAD at a head of the given shape.
stage() {
  git -C "$1/rig" worktree add -q --detach "$PREP" origin/main
  case "$2" in
    change)   printf 'new\n' >> "$PREP/f.txt"; git -C "$PREP" commit -q -am change ;;
    same)     : ;;
    empty)    git -C "$PREP" commit -q --allow-empty -m empty ;;
    reverted) printf 'x\n' >> "$PREP/f.txt"; git -C "$PREP" commit -q -am x
              git -C "$PREP" revert --no-edit HEAD >/dev/null ;;
  esac
}

# guard <dir> -> "<rc>|<trace>"
guard() {
  : > "$FAKE_LOG"
  local rc=0
  ( cd "$TMP" && GC_RIG_ROOT="$1/rig" "$SUT" --work tk-w --branch polecat/tk-w --target main ) > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(sed 's/ .*//' "$FAKE_LOG" | tr '\n' ',' | sed 's/,$//')"
}

# --- 1. Pass. -----------------------------------------------------------------
rig "$TMP/a"; stage "$TMP/a" change
eq "$(guard "$TMP/a")" "0|" "a head with a real change passes, writing and draining nothing"

# --- 2. Refuse. ---------------------------------------------------------------
for how in same empty reverted; do
  rig "$TMP/$how"; stage "$TMP/$how" "$how"
  eq "$(guard "$TMP/$how")" "1|LC,ESCALATE,DRAIN" "a '$how' head is refused: parked, escalated, drained"
done
has "$(grep '^LC ' "$FAKE_LOG")" "transition tk-w --to refused_false_completion --assignee  --route human" \
   "the refusal parks the bead at refused_false_completion, routed to a human"
has "$(grep '^ESCALATE ' "$FAKE_LOG")" "--subject tk-w --key refinery-false-completion" \
   "and escalates under refinery-false-completion"

# --- 3. Fail closed. ----------------------------------------------------------
rig "$TMP/noprep"
eq "$(guard "$TMP/noprep")" "1|LC,ESCALATE,DRAIN" "a missing prep worktree is refused, not passed"
: > "$FAKE_LOG"
NORIG_RC=0
( cd "$TMP" && GC_RIG_ROOT="" GC_RIG=nowhere "$SUT" --work tk-w --branch b --target main ) > "$TMP/out" 2>&1 || NORIG_RC=$?
eq "$NORIG_RC|$(sed 's/ .*//' "$FAKE_LOG" | tr '\n' ',' | sed 's/,$//')" "1|DRAIN" \
   "an unresolvable rig drains before touching the bead"
eq "$("$SUT" --work tk-w > /dev/null 2>&1; echo $?)" "2" "a missing --target refuses as usage"

echo
echo "zero-diff-guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
