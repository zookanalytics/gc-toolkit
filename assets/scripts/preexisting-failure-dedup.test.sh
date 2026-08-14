#!/usr/bin/env bash
# Hermetic test for the pre-existing-failure dedup probe in
# mol-refinery-patrol.toml's `handle-failures` step (tk-277aj).
#
# The step's third branch ("if pre-existing on target") must find an already-filed
# bug for the same failure and NOT file another. The pre-fix instruction probed
# with:
#
#     gc bd list --type=bug --status=open --search "<failure summary>"
#
# `bd list` has no `--search` flag. bd rejects it with `unknown flag` on stderr
# and leaves stdout EMPTY, so the step read the failure as "no duplicate found"
# and fell through to the file-a-new-bead arm — every patrol that hit a
# pre-existing target failure filed a fresh P1, on every refinery, for as long as
# the failure persisted. The dedup guard had never once run.
#
# The fix (the `# >>> preexisting-failure-dedup` … `# <<< …` block) has three
# load-bearing parts, and this test pins each of them:
#   1. the REAL flag, `--title-contains` (a case-insensitive title substring);
#   2. a SHAPE check on the result, so an unreadable bd — which also produces an
#      empty stdout — cannot masquerade as "no match" and file a duplicate. A
#      readable empty result is the JSON array `[]`; anything else is UNKNOWN,
#      and unknown files nothing and merges nothing;
#   3. ONE FAIL_TOKEN reused for both the probe and the title of any bead filed,
#      so the NEXT patrol's substring probe actually matches what this one filed.
#      A prose summary is reworded every cycle and never matches.
#
# This EXECUTES the real snippet extracted verbatim from the formula (between the
# markers) against a fake `gc`, so the test cannot drift from the shipped
# instruction. No live city, Dolt, network, or PRs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: models the reads/writes the dedup snippet performs. -------------
#   gc runtime drain-ack   -> no-op (exit 0)
#   gc bd list ... --json  -> emit a list per LIST_SCENARIO:
#       dup        -> one open bug whose title contains the token
#       nodup      -> readable EMPTY result, i.e. the JSON array []
#       unreadable -> EMPTY stdout, exit 0 — bd's fails-open behavior, which the
#                     snippet must treat as UNKNOWN, never as "no duplicate"
#       badflag    -> the PRE-FIX behavior: unknown flag on stderr, empty stdout.
#                     Only reachable if someone reintroduces `--search`.
#     Every list invocation is recorded (with its flags) so the assertions can
#     prove WHICH flag shipped.
#   gc bd create ...       -> record CREATE_RAN + the --title value, so the
#     assertions can prove a duplicate was (or was not) filed, and that the
#     filed title carries the same token the probe searched for.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "runtime" ] && exit 0
[ "$1" = "bd" ] || exit 0
case "$2" in
  list)
    shift 2
    printf 'LIST|%s\n' "$*" >> "$FAKE_META"
    if grep -q -- '--search' <<< "$*"; then
      echo "Error: unknown flag: --search" >&2
      exit 0
    fi
    case "${LIST_SCENARIO:-nodup}" in
      dup)        printf '[{"id":"tk-dup01","title":"Pre-existing failure: test_widget_rebase (fails on main)"}]\n' ;;
      nodup)      printf '[]\n' ;;
      unreadable) : ;;   # empty stdout — bd fails open (error to stderr, nothing on stdout)
      badflag)    : ;;
    esac ;;
  create)
    shift 2
    echo "CREATE_RAN" >> "$FAKE_META"
    while [ $# -gt 0 ]; do
      case "$1" in
        --title=*) printf 'title|%s\n' "${1#--title=}" >> "$FAKE_META"; shift ;;
        --title)   printf 'title|%s\n' "$2" >> "$FAKE_META"; shift 2 ;;
        *) shift ;;
      esac
    done ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_META="$TMP/meta"

# --- Extract the real snippet from the formula. -------------------------------
# Missing or renamed markers => zero blocks => the guard below fails loudly.
awk -v tmp="$TMP" '
  /# >>> preexisting-failure-dedup/ { n++; f=1; next }
  /# <<< preexisting-failure-dedup/ { f=0; next }
  f { print > (tmp "/block" n ".sh") }
' "$TOML"

NBLOCKS=$(ls "$TMP"/block*.sh 2>/dev/null | wc -l | tr -d ' ')
eq "$NBLOCKS" "1" "dedup snippet extracted between preexisting-failure-dedup markers"
BLK="$TMP/block1.sh"

# The shipped snippet carries a placeholder token; substitute a concrete one so
# the block is executable, exactly as the refinery would fill it in.
sed -i 's/<failing test name or error symbol>/test_widget_rebase/' "$BLK"

# run <scenario> -> echo the snippet's exit code; leaves $FAKE_META populated.
run() {
  : > "$FAKE_META"
  if LIST_SCENARIO="$1" WORK=work-1 bash "$BLK" >/dev/null 2>&1; then
    echo 0
  else
    echo "$?"
  fi
}

# (0) THE FLAG. The probe must ship `--title-contains` and must NOT ship
#     `--search`. Asserted on the recorded invocation, not on the file text, so
#     it is the flag actually PASSED that is pinned.
run nodup >/dev/null
grep -q '^LIST|.*--title-contains' "$FAKE_META" \
  && ok "(0) probe uses the real flag --title-contains" \
  || bad "(0) probe does not pass --title-contains"
if grep -q '^LIST|.*--search' "$FAKE_META"; then
  bad "(0) probe passes --search — bd has no such flag; it fails open and files a duplicate every patrol"
else
  ok "(0) probe does not pass --search"
fi
grep -q '^LIST|.*--json' "$FAKE_META" \
  && ok "(0) probe requests --json (shape-checkable output)" \
  || bad "(0) probe does not request --json"

# (A) A duplicate EXISTS -> proceed (exit 0) and file NOTHING.
eq "$(run dup)" "0" "(A) duplicate found -> snippet proceeds (exit 0)"
if grep -q '^CREATE_RAN$' "$FAKE_META"; then
  bad "(A) filed a bug despite an existing duplicate — the exact bug this fix prevents"
else
  ok "(A) duplicate found -> no second bead filed"
fi

# (B) No duplicate, READABLE -> proceed (exit 0) and file exactly one bead whose
#     title carries the SAME token the probe searched for, so the next patrol's
#     substring probe matches it.
eq "$(run nodup)" "0" "(B) readable empty result -> snippet proceeds (exit 0)"
grep -q '^CREATE_RAN$' "$FAKE_META" \
  && ok "(B) no duplicate -> a bug is filed" || bad "(B) no duplicate -> nothing filed"
eq "$(grep -c '^CREATE_RAN$' "$FAKE_META")" "1" "(B) exactly one bead filed"
if grep -q '^title|.*test_widget_rebase' "$FAKE_META"; then
  ok "(B) filed title carries the probe token (next patrol's probe will match it)"
else
  bad "(B) filed title does not carry the probe token — dedup cannot match next cycle"
fi

# (C) THE FIX: unreadable probe (empty stdout, the same shape a rejected flag
#     produces) -> FAIL CLOSED. Non-zero exit, and NOTHING filed: an unreadable
#     list must never be read as "no duplicate".
eq "$(run unreadable)" "1" "(C) unreadable probe -> fail-closed defer (exit 1)"
if grep -q '^CREATE_RAN$' "$FAKE_META"; then
  bad "(C) filed a bug on an unreadable probe — cannot tell 'no match' from 'bd down'"
else
  ok "(C) unreadable probe -> nothing filed (next patrol re-probes)"
fi

# (D) Regression canary for the ORIGINAL defect: if `--search` is ever
#     reintroduced, the stub reproduces bd's real response (unknown flag on
#     stderr, empty stdout). The shape check must catch that too — fail closed,
#     file nothing — rather than filing a duplicate as the pre-fix step did.
eq "$(run badflag)" "1" "(D) empty stdout from a rejected flag -> fail-closed defer (exit 1)"
if grep -q '^CREATE_RAN$' "$FAKE_META"; then
  bad "(D) filed a bug on a rejected-flag empty stdout — the original tk-277aj defect"
else
  ok "(D) rejected-flag empty stdout -> nothing filed"
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
