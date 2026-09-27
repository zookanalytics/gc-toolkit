#!/usr/bin/env bash
# Hermetic test for assets/scripts/migrate-codex-to-correctness.sh.
# Covers: dry-run (the default) reports every rewrite and writes nothing; --apply
# rewrites the check_name=codex backing on open AND closed reviews, rewrites the
# codex token inside a check_set (order and sibling checks kept), and moves a
# check.codex marker to check.correctness (value copied verbatim, old key unset);
# a token that only CONTAINS "codex" (codexy) is left alone, proving the
# comma-boundary match; a stray check.codex marker on an anchor whose check_set
# never named codex is still moved; a second --apply is a true no-op; a write that
# does not read back leaves the legacy name standing and exits 1, and a re-run
# recovers it; an unreadable listing (garbage at rc 0, or a non-zero rc) is
# refused, never read as "nothing to migrate"; a suspended rig is skipped
# unqueried; an empty rig list exits 1; and --rig walks only the named rig.
# No live city, Dolt, network, gc, bd or gh — stubs from test-harness.sh plus a
# thin `gc rig list` / `gc bd list` shim (the migrate-lane-states.test.sh pattern).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-migrate-codex-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/migrate-codex-to-correctness.sh"
SUT="$SD/migrate-codex-to-correctness.sh"

# The SUT enumerates rigs via `gc rig list` (which the shared harness stub does
# not implement) and reaches each store with `gc bd ... --db <path>`; shim both
# onto the harness gc stub. STUB_BD_LIST_GARBAGE, when set, answers `gc bd list`
# with its literal content at rc 0 — the "printed a body but still exited 0"
# shape no rc check alone catches.
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

review() { # id status check_name
  printf '{"id":"%s","status":"%s","assignee":"","title":"t-%s","metadata":{"task_kind":"review","check_name":"%s"}}' \
    "$1" "$2" "$1" "$3"
}
anchor() { # id check_set extra-metadata-json (starts with a comma, or empty)
  printf '{"id":"%s","status":"open","assignee":"","title":"t-%s","metadata":{"check_set":"%s"%s}}' \
    "$1" "$1" "$2" "${3:-}"
}

# Fixture: two codex reviews (one open, one closed — both backings migrate); one
# review already named correctness (invisible to the codex query); an anchor whose
# check_set IS codex plus a check.codex marker; a multi-check check_set proving the
# comma-token rewrite keeps order and siblings; a stray marker on an already-clean
# check_set; a "codexy" token proving the boundary; and a fully-clean anchor.
fixture() {
  store "[$(review R1 open codex),$(review R2 closed codex),$(review R3 open correctness),\
$(anchor A1 codex ',"check.codex":"green"'),\
$(anchor A2 "lint,codex,arch" ''),\
$(anchor A3 correctness ',"check.codex":"green"'),\
$(anchor A4 codexy ''),\
$(anchor A5 "correctness,triage" '')]"
}
fixture

echo "# dry-run (the default) reports every rewrite and writes NOTHING"
cp "$STUB_STORE" "$TMP/store.before"
out=$("$SUT" --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "dry-run exits 0"
has "$out" "DRY-RUN" "dry-run announces itself"
has "$out" "gc-toolkit R1: would set check_name codex -> correctness" "R1 (open review) reported"
has "$out" "gc-toolkit R2: would set check_name codex -> correctness" "R2 (closed review) reported — closed backings migrate too"
hasnt "$out" "R3:" "R3 (already correctness) is invisible to the codex query"
has "$out" "gc-toolkit A1: would set check_set 'codex' -> 'correctness'" "A1 check_set rewrite reported"
has "$out" "gc-toolkit A1: would move check.codex='green' -> check.correctness" "A1 marker move reported"
has "$out" "gc-toolkit A2: would set check_set 'lint,codex,arch' -> 'lint,correctness,arch'" "A2 multi-check check_set keeps order and siblings"
hasnt "$out" "A2: would move check.codex" "A2 has no marker to move"
has "$out" "gc-toolkit A3: would move check.codex='green' -> check.correctness" "A3 stray marker move reported"
hasnt "$out" "A3: would set check_set" "A3 check_set already clean — not rewritten"
hasnt "$out" "A4:" "A4 (codexy) is not a codex token — untouched, unreported"
hasnt "$out" "A5:" "A5 (already correctness,triage) — nothing to do"
cmp -s "$STUB_STORE" "$TMP/store.before"; eq "$?" 0 "dry-run left the store byte-identical"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "dry-run issued zero bd updates"

echo
echo "# --apply: reviews (open AND closed), the check_set token, and the marker"
: > "$STUB_GC_LOG"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "apply exits 0"
eq "$(meta R1 check_name)" "correctness" "R1 open review rewritten"
eq "$(meta R2 check_name)" "correctness" "R2 closed review rewritten — closed backings too"
eq "$(meta R3 check_name)" "correctness" "R3 was already correctness, still correctness"
eq "$(meta A1 check_set)" "correctness" "A1 check_set token rewritten"
eq "$(meta A1 'check.correctness')" "green" "A1 marker value copied verbatim to check.correctness"
eq "$(meta A1 'check.codex')" "<absent>" "A1 old check.codex key unset"
eq "$(meta A2 check_set)" "lint,correctness,arch" "A2 multi-check check_set keeps order and siblings"
eq "$(meta A3 check_set)" "correctness" "A3 check_set unchanged (never named codex)"
eq "$(meta A3 'check.correctness')" "green" "A3 stray marker moved to check.correctness"
eq "$(meta A3 'check.codex')" "<absent>" "A3 old marker key unset"
eq "$(meta A4 check_set)" "codexy" "A4 (codexy) untouched — not a codex token"
eq "$(meta A5 check_set)" "correctness,triage" "A5 untouched"
has "$out" "gc-toolkit A1: migrated (check_set='correctness', marker moved)" "A1 apply reports both rewrites"
has "$out" "gc-toolkit A2: migrated (check_set='lint,correctness,arch')" "A2 apply reports the check_set rewrite"
hasnt "$out" "A2: migrated (check_set='lint,correctness,arch', marker moved)" "A2 never claims a marker move it did not make"

echo
echo "# --apply again: a true no-op once everything has landed"
cp "$STUB_STORE" "$TMP/store.after1"
: > "$STUB_GC_LOG"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "second apply exits 0"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "second apply issued zero bd updates"
cmp -s "$STUB_STORE" "$TMP/store.after1"; eq "$?" 0 "second apply left the store byte-identical"
has "$out" "no anchor names the codex check; nothing to migrate" "anchors report nothing to do"

echo
echo "# a review write that does not read back leaves the legacy name, exits 1"
fixture
export STUB_DROP_KEYS="R1:check_name"
: > "$STUB_GC_LOG"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 1 "a lost review write exits 1"
eq "$(meta R1 check_name)" "codex" "R1 still names codex — the write did not land"
has "$out" "R1: check_name did not read back as correctness" "the lost review write is reported as retryable"
export STUB_DROP_KEYS=""

echo
echo "# an anchor write that does not read back keeps the legacy marker, exits 1"
fixture
export STUB_DROP_KEYS="A1:check.codex"
: > "$STUB_GC_LOG"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 1 "a lost anchor unset exits 1"
eq "$(meta A1 'check.codex')" "green" "A1 still carries the legacy marker — the unset did not land"
has "$out" "A1: writes did not read back cleanly" "the lost anchor write is reported as retryable"
echo "# …and a re-run recovers: the leftover marker is picked up and cleared"
export STUB_DROP_KEYS=""
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "the retry exits 0"
eq "$(meta A1 'check.codex')" "<absent>" "A1's legacy marker is cleared on retry"
eq "$(meta A1 'check.correctness')" "green" "A1 keeps its correctness marker"

echo
echo "# an unreadable listing is refused, never read as 'nothing to migrate'"
fixture
export STUB_BD_LIST_GARBAGE='{"error":"boom"}'
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 1 "a non-array listing (rc 0) exits 1"
has "$out" "review listing unreadable" "the loud NOT-migrated message fires for reviews"
has "$out" "anchor listing unreadable" "…and for anchors"
hasnt "$out" "nothing to migrate" "garbage is never read as an empty, fully-migrated store"
export STUB_BD_LIST_GARBAGE=""

echo "# …and a listing that exits non-zero is refused the same way"
export STUB_LIST_FAIL="1"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 1 "a failed listing exits 1"
has "$out" "review listing unreadable" "a non-zero listing is refused too"
export STUB_LIST_FAIL=""

echo
echo "# a suspended rig is skipped, never queried"
printf '{"rigs":[{"name":"gc-toolkit","path":"%s","suspended":true}]}\n' "$TMP/rig" > "$STUB_RIGS"
: > "$STUB_GC_LOG"
out=$("$SUT" --apply 2>&1); rc=$?
eq "$rc" 0 "a run over only a suspended rig exits 0"
has "$out" "skipped (suspended" "the suspended rig is reported skipped"
eq "$(grep -c '^bd ' "$STUB_GC_LOG" || true)" "0" "no bd query ran against the suspended rig"

echo
echo "# an empty rig list exits 1 rather than reporting a clean run"
printf '{"rigs":[]}\n' > "$STUB_RIGS"
out=$("$SUT" --apply 2>&1); rc=$?
eq "$rc" 1 "no rigs to migrate against exits 1"
has "$out" "listed no rig paths" "the empty rig list is reported"

echo
echo "# --rig walks only the named rig"
mkdir -p "$TMP/rig2"
printf '{"rigs":[{"name":"gc-toolkit","path":"%s","suspended":false},{"name":"other","path":"%s","suspended":false}]}\n' "$TMP/rig" "$TMP/rig2" > "$STUB_RIGS"
fixture
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "the narrowed run exits 0"
has "$out" "== rig gc-toolkit" "the named rig is walked"
hasnt "$out" "== rig other" "the other rig is skipped by --rig"

echo
echo "migrate-codex-to-correctness.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
