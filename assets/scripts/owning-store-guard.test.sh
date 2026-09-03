#!/usr/bin/env bash
# Hermetic test for the witness-patrol OWNING STORE GUARD.
#
# The hazard: step 5 removes a worktree on the authority of the bead that owns
# it, and a bare `gc bd show` cannot prove that bead absent — it resolves a
# live id from whichever store holds it, but a miss is answered by the store
# the caller stands in, not the one the prefix names, so an id the witness
# cannot place reads as an unowned directory and licenses the delete. The
# guard makes removal wait on a bead
# proven present in the store its own prefix names, and refuses every shape
# that leaves the question open.
#
# The guard is EXECUTED verbatim from the formula, extracted between its
# markers, so it cannot drift from the shipped instruction. bead-store.sh is
# stubbed over its exit codes alone — the real one has its own suite.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

GUARD="$(awk '
  /# >>> owning-store-guard/ {f=1; next}
  /# <<< owning-store-guard/ {f=0}
  f' "$TOML")"
[ -n "$GUARD" ] \
  && ok "guard extracted between owning-store-guard markers" \
  || bad "guard extraction EMPTY — markers missing from $TOML"

# The witness substitutes the bead it is disposing of for the <bead> placeholder.
printf '%s\n' "${GUARD//<bead>/tk-subject}" > "$TMP/guard.sh"
bash -n "$TMP/guard.sh" \
  && ok "extracted guard is syntactically valid bash" \
  || bad "extracted guard failed bash -n"

# A rig root carrying a stubbed bead-store.sh, found the way the guard looks
# for one. STUB_RC is the verdict the real tool would return.
RIG="$TMP/rig"; mkdir -p "$RIG/assets/scripts"
cat > "$RIG/assets/scripts/bead-store.sh" <<'BS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_BS_LOG"
exit "${STUB_RC:-0}"
BS
chmod +x "$RIG/assets/scripts/bead-store.sh"
export STUB_BS_LOG="$TMP/bs.log"; : > "$STUB_BS_LOG"

# owned <rc> -> the OWNED value the guard settles on for that verdict.
owned() {
  STUB_RC="$1" GC_RIG_ROOT="$RIG" WORKTREE="$TMP/wt" bash -c '
    source "$0"
    printf "%s" "$OWNED"
  ' "$TMP/guard.sh" 2>/dev/null
}

# 0 is the only verdict that authorizes the removal. 1 (proven absent) and 3
# (no store could be asked) must both hold the worktree: a bead whose owner
# cannot be placed is not an unowned one.
eq "$(owned 0)" "1" "a bead proven present in its own store authorizes the removal"
eq "$(owned 1)" "0" "a bead its own store denies does NOT — the witness is not the judge of that"
eq "$(owned 3)" "0" "an unproven store refuses: unknown prefix, ambiguous prefix, unreadable store"
eq "$(owned 2)" "0" "a usage failure refuses too — no exit code but 0 is permission"

eq "$(tail -1 "$STUB_BS_LOG")" "--present tk-subject" \
  "the guard asks --present about the bead it was given, not --absent about a directory"

# A rig root with no bead-store.sh at all: the tool's absence is not a verdict.
NOTOOL="$TMP/notool"; mkdir -p "$NOTOOL"
OUT=$(GC_RIG_ROOT="$NOTOOL" GC_CITY_PATH="$NOTOOL" WORKTREE="$TMP/wt" bash -c '
  cd /
  source "$0"
  printf "%s" "$OWNED"
' "$TMP/guard.sh" 2>"$TMP/err")
eq "$OUT" "0" "a missing bead-store.sh refuses rather than falling through to the delete"
case "$(cat "$TMP/err")" in
  *"REFUSING to remove"*) ok "  ... and says what it refused" ;;
  *) bad "  ... and must say what it refused (got: $(cat "$TMP/err"))" ;;
esac

# --- static wiring: the removal must actually branch on the guard -----------
grep -qF 'if [ "$OWNED" = "1" ]' "$TOML" \
  && ok "the worktree removal branches on OWNED" \
  || bad "the worktree removal must branch on OWNED"

# No `git worktree remove` may appear before the guard is defined. Anchored to
# line start so the prose that mentions the command does not match.
GUARD_LINE=$(grep -nE '^OWNED=0' "$TOML" | head -1 | cut -d: -f1)
FIRST_RM=$(grep -nE '^[[:space:]]*git .*worktree remove' "$TOML" | head -1 | cut -d: -f1)
[ -n "$GUARD_LINE" ] && [ -n "$FIRST_RM" ] && [ "$GUARD_LINE" -lt "$FIRST_RM" ] \
  && ok "the guard is defined before the first 'git worktree remove' in the formula" \
  || bad "the guard must precede any 'git worktree remove' (guard@${GUARD_LINE:-none} rm@${FIRST_RM:-none})"

if command -v python3 >/dev/null 2>&1; then
  python3 - "$TOML" <<'PY' && ok "formula still parses as TOML" || bad "formula failed to parse as TOML"
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
fi

echo
echo "owning-store-guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
