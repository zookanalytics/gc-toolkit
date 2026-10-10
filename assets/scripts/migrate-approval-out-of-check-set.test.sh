#!/usr/bin/env bash
# Hermetic test for assets/scripts/migrate-approval-out-of-check-set.sh.
# Covers: dry-run (the default) reports every rewrite and writes nothing; --apply
# drops the approval token from a mixed check_set (order and siblings kept),
# collapses an approval-ONLY set to the `none` sentinel (never empty, which would
# hold the merge), leaves a clean set and a boundary token ("approvalx") alone;
# a second --apply is a true no-op; an unreadable listing is refused; and the
# full LIVE status set migrates. No live city, Dolt, gc, bd or gh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-migrate-approval-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/migrate-approval-out-of-check-set.sh"
SUT="$SD/migrate-approval-out-of-check-set.sh"

# The SUT enumerates rigs via `gc rig list` and reaches each store with
# `gc bd ... --db <path>`; shim both onto the harness gc stub (the
# migrate-codex-to-correctness.test.sh pattern).
mkdir -p "$TMP/bin2"
export STUB_RIGS="$TMP/rigs.json"
export STUB_BD_LIST_GARBAGE=""
cat > "$TMP/bin2/gc" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = "rig" ] && [ "\${2:-}" = "list" ]; then cat "\${STUB_RIGS:?}"; exit 0; fi
if [ "\${1:-}" = "bd" ] && [ "\${2:-}" = "list" ] && [ -n "\${STUB_BD_LIST_GARBAGE:-}" ]; then
  printf '%s\n' "\$STUB_BD_LIST_GARBAGE"; exit 0
fi
exec "$BIN/gc" "\$@"
SHIM
chmod +x "$TMP/bin2/gc"
export PATH="$TMP/bin2:$PATH"

mkdir -p "$TMP/rig"
printf '{"rigs":[{"name":"gc-toolkit","path":"%s","suspended":false}]}\n' "$TMP/rig" > "$STUB_RIGS"

anchor() { # id status check_set
  printf '{"id":"%s","status":"%s","assignee":"","title":"t-%s","metadata":{"check_set":"%s"}}' \
    "$1" "$2" "$1" "$3"
}

# Fixture: a mixed set (approval dropped, order kept); an approval-only set
# (collapses to none); an approval-first set; a clean set (untouched); a boundary
# token "approvalx" (not the approval token).
fixture() {
  store "[$(anchor A1 open 'correctness,approval,triage'),\
$(anchor A2 open 'approval'),\
$(anchor A3 open 'approval,correctness'),\
$(anchor A4 open 'correctness,triage'),\
$(anchor A5 open 'approvalx')]"
}
fixture

echo "# dry-run (the default) reports every rewrite and writes NOTHING"
cp "$STUB_STORE" "$TMP/store.before"
out=$("$SUT" --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "dry-run exits 0"
has "$out" "DRY-RUN" "dry-run announces itself"
has "$out" "gc-toolkit A1: would set check_set 'correctness,approval,triage' -> 'correctness,triage'" "A1 drops approval, keeps order and siblings"
has "$out" "gc-toolkit A2: would set check_set 'approval' -> 'none'" "A2 approval-only collapses to the none sentinel"
has "$out" "gc-toolkit A3: would set check_set 'approval,correctness' -> 'correctness'" "A3 drops a leading approval token"
hasnt "$out" "A4:" "A4 (already clean) is nothing to do"
hasnt "$out" "A5:" "A5 (approvalx) is not the approval token — untouched"
cmp -s "$STUB_STORE" "$TMP/store.before"; eq "$?" 0 "dry-run left the store byte-identical"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "dry-run issued zero bd updates"

echo
echo "# --apply rewrites the check_sets"
: > "$STUB_GC_LOG"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "apply exits 0"
eq "$(meta A1 check_set)" "correctness,triage" "A1 approval dropped, order and siblings kept"
eq "$(meta A2 check_set)" "none" "A2 approval-only became the none sentinel, never empty"
eq "$(meta A3 check_set)" "correctness" "A3 leading approval dropped"
eq "$(meta A4 check_set)" "correctness,triage" "A4 untouched"
eq "$(meta A5 check_set)" "approvalx" "A5 (approvalx) untouched"

echo
echo "# --apply again: a true no-op once everything has landed"
cp "$STUB_STORE" "$TMP/store.after1"
: > "$STUB_GC_LOG"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "second apply exits 0"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "second apply issued zero bd updates"
cmp -s "$STUB_STORE" "$TMP/store.after1"; eq "$?" 0 "second apply left the store byte-identical"
has "$out" "no anchor names the approval token; nothing to migrate" "reports nothing to do"

echo
echo "# an unreadable listing is refused, never read as 'nothing to migrate'"
fixture
export STUB_BD_LIST_GARBAGE='{"error":"boom"}'
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 1 "a non-array listing (rc 0) exits 1"
has "$out" "anchor listing unreadable" "the loud NOT-migrated message fires"
hasnt "$out" "nothing to migrate" "garbage is never read as an empty, fully-migrated store"
export STUB_BD_LIST_GARBAGE=""

echo
echo "# the migration covers the full LIVE status set, not just open"
store "[$(anchor AH hooked 'correctness,approval'),$(anchor AP pinned 'approval'),$(anchor AD deferred 'approval,triage')]"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "apply over the live-status fixture exits 0"
eq "$(meta AH check_set)" "correctness" "a hooked anchor migrates"
eq "$(meta AP check_set)" "none" "a pinned approval-only anchor collapses to none"
eq "$(meta AD check_set)" "triage" "a deferred anchor migrates"

echo
echo "# --rig as the final argument errors rather than looping forever"
# `shift 2` with one argument left is a no-op returning non-zero in bash, so
# `--rig` with no value used to spin `while [ \$# -gt 0 ]` forever. timeout proves
# it now terminates; the exit code and message prove it refused the missing value.
out=$(timeout 10 "$SUT" --apply --rig 2>&1); rc=$?
eq "$rc" 2 "--rig with no value exits 2 (never spins the arg loop)"
has "$out" "--rig requires a value" "it names the missing value, not a timeout kill (124)"

echo
echo "# a --rig that matches no rig fails loudly, never 'done' + exit 0"
fixture
out=$("$SUT" --apply --rig no-such-rig 2>&1); rc=$?
eq "$rc" 1 "a --rig typo exits non-zero"
has "$out" "matched no rig" "it says the name matched nothing"
hasnt "$out" "done" "a typo never looks like a successful migration"
# the real rig still migrates, so the guard is scoped to the no-match case
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "a --rig that DOES match still migrates (exit 0)"

echo
echo "migrate-approval-out-of-check-set.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
