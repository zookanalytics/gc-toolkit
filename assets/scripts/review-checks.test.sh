#!/usr/bin/env bash
# review-checks.test.sh — the one parser of the check-index grammar
# (assets/scripts/review-checks.sh). Asserts it emits <check>\t<method>\t<purpose>
# TSV, narrows with --check, and fails closed on a missing index, an undeclared
# check, and an index that declares nothing. Also asserts the repo's own
# review-checks.toml declares the forced baseline (correctness, triage).
#
# Hermetic: runs the script against fixtures in a mktemp dir; no gc, no bd, no
# network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/review-checks.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "'$2' has no '$3'" ;; esac; }

[ -x "$SUT" ] || { echo "missing or non-executable $SUT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-checks-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

IDX="$TMP/review-checks.toml"
cat >"$IDX" <<'TOML'
# a comment line, ignored
[checks.correctness]
method = "formulas/mol-review.toml"
purpose = "Is the change correct and safe as merged?"

[checks.triage]
method = "skills/review-triage/SKILL.md"
purpose = "Which specialist checks does this diff warrant?"

[checks.demo]
method = "skills/gc-demo-script/SKILL.md + skills/demo-capture/SKILL.md"
purpose = "Was the operator-watched surface recorded doing the thing?"

[unrelated]
method = "not-a-check"
TOML

# All rows.
OUT="$("$SUT" --file "$IDX")"; RC=$?
is  "all-rows exit 0" "$RC" "0"
is  "declares exactly three checks" "$(printf '%s\n' "$OUT" | grep -c .)" "3"
has "correctness row carries its method" "$OUT" "correctness	formulas/mol-review.toml	"
has "triage row present" "$OUT" "triage	skills/review-triage/SKILL.md	"
has "demo method keeps the + join" "$OUT" "gc-demo-script/SKILL.md + skills/demo-capture/SKILL.md"
case "$OUT" in *"unrelated"*) bad "a key outside [checks.*] is not read as a check" "leaked 'unrelated'" ;; *) ok "a key outside [checks.*] is not read as a check" ;; esac

# --check narrows to one row.
OUT="$("$SUT" --file "$IDX" --check triage)"; RC=$?
is  "--check exit 0" "$RC" "0"
is  "--check emits one row" "$(printf '%s\n' "$OUT" | grep -c .)" "1"
has "--check emits the asked row" "$OUT" "triage	skills/review-triage/SKILL.md	"

# --check for an undeclared check fails closed.
"$SUT" --file "$IDX" --check arch >/dev/null 2>&1
is "undeclared --check exits 1" "$?" "1"

# A missing index fails closed.
"$SUT" --file "$TMP/nope.toml" >/dev/null 2>&1
is "missing index exits 1" "$?" "1"

# An index that declares no checks fails closed.
EMPTY="$TMP/empty.toml"; printf '# nothing here\n[other]\nx = "y"\n' >"$EMPTY"
"$SUT" --file "$EMPTY" >/dev/null 2>&1
is "index with no checks exits 1" "$?" "1"

# No --file is a usage error.
"$SUT" >/dev/null 2>&1
is "no --file exits 2" "$?" "2"

# The repo's own index declares the forced baseline.
REAL="$REPO/review-checks.toml"
if [ -r "$REAL" ]; then
  "$SUT" --file "$REAL" --check correctness >/dev/null 2>&1
  is "repo index declares correctness" "$?" "0"
  "$SUT" --file "$REAL" --check triage >/dev/null 2>&1
  is "repo index declares triage" "$?" "0"
else
  bad "repo carries review-checks.toml" "no $REAL"
fi

echo
echo "review-checks: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
