#!/usr/bin/env bash
# run-tests.test.sh — the serial re-run that tells a parallel-contention false
# failure from a real one, and the runs a file with parts is split into.
#
# A file can fail under -j for a reason that is not its own: a sibling job
# saturates the host and a command the file spawned is killed, so an assertion
# reads a 143 where it wanted a real exit. The runner re-runs each failed file
# serially, where no sibling competes with it, and only a file that fails alone
# too is a real failure. That reclassification is what this pins.
#
# Asserted here:
#   - a file with parts runs once per declared part, each run handed its part
#     and the declared list, and each with its own timeout, report line, serial
#     re-run and failure dump; only the opening comment block declares parts,
#     and a malformed declaration is a usage error;
#   - a file that fails once then passes is recovered on serial re-run (default);
#   - a file that fails every time stays failed and the suite exits 1;
#   - --no-retry and --retry 0 report the raw parallel result;
#   - --retry N bounds the serial attempts;
#   - the serial run's log, not the parallel one, is what the failure dump shows;
#   - --retry rejects a non-integer;
#   - every file commits and tags with signing off, under a git config that
#     signs both with a signer that always fails, and a git config entry the
#     caller exported still reaches it.
#
# Hermetic: runs a copy of the runner over throwaway fixture *.test.sh files
# whose pass/fail is driven by a per-file invocation counter, so "fails the
# first time, passes the next" stands in for the contention the real flake needs
# a loaded host to produce. No live city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$HERE/run-tests.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-run-tests-test.XXXXXX")" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Ambient git config and the env knobs the runner reads must not reach it, so
# the default behaviour under test is the runner's own, not the host's.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_CONFIG_COUNT "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}"
unset TEST_JOBS TEST_TIMEOUT TEST_RETRY

# The runner derives its root from its own location, so give it a git repo to
# sit in. The fixtures live outside it and are passed by absolute path.
REPO="$TMP/repo"
mkdir -p "$REPO/tools"
cp "$RUNNER" "$REPO/tools/run-tests.sh"
git -C "$REPO" init -q
RUNNER_COPY="$REPO/tools/run-tests.sh"

STATE="$TMP/state"
FIX="$TMP/fixtures"
mkdir -p "$FIX"
reset_state() { rm -rf "$STATE"; mkdir -p "$STATE"; }

# Each fixture counts its own invocations in $RUNTESTS_FIXTURE_STATE. The two
# invocations of one file (parallel wave, then serial retry) are sequential, so
# the counter needs no locking.

# Passes on run 2 and after: fails in the parallel wave, passes on serial retry.
cat > "$FIX/flaky.test.sh" <<'F'
#!/usr/bin/env bash
c="$RUNTESTS_FIXTURE_STATE/flaky.count"
n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$c"
echo "flaky run $n"
[ "$n" -ge 2 ]
F

# Passes only on run 3: needs two serial retries to recover.
cat > "$FIX/twice.test.sh" <<'F'
#!/usr/bin/env bash
c="$RUNTESTS_FIXTURE_STATE/twice.count"
n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$c"
echo "twice run $n"
[ "$n" -ge 3 ]
F

# Fails every time, printing its invocation number so the dump reveals which run
# produced the log it shows.
cat > "$FIX/afail.test.sh" <<'F'
#!/usr/bin/env bash
c="$RUNTESTS_FIXTURE_STATE/afail.count"
n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$c"
echo "FAILMARKER run $n"
exit 1
F

cat > "$FIX/pass.test.sh" <<'F'
#!/usr/bin/env bash
echo "pass ok"
F

# run [runner-args...] -> sets RC and OUT. Always serial-safe: -j 2, short -t.
run() { OUT="$(RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 2 -t 30 "$@" 2>&1)"; RC=$?; }

echo "── 1. a clean file never triggers a re-run ──"
reset_state
run "$FIX/pass.test.sh"
eq "$RC" 0 "an all-pass run exits 0"
has "$OUT" "1 passed, 0 failed" "the summary reports no failures"
hasnt "$OUT" "re-running serially" "no failures means no serial phase"

echo "── 2. a file that fails once then passes is recovered (default retry) ──"
reset_state
run "$FIX/flaky.test.sh"
eq "$RC" 0 "a parallel-contention false failure recovers and the suite passes"
has "$OUT" "re-running serially" "the serial phase runs when a file failed"
has "$OUT" "recovered serially after 1 attempt" "the file is reported recovered"
has "$OUT" "1 recovered on serial re-run" "the summary names the recovery"

echo "── 3. a file that fails every time stays failed ──"
reset_state
run "$FIX/afail.test.sh"
eq "$RC" 1 "a file that fails serially too fails the suite"
has "$OUT" "failed serially too" "the file is reported as a real failure"
has "$OUT" "1 failed" "the summary counts it failed"

echo "── 4. the serial run's log is the authority the dump prints ──"
# The parallel wave is run 1, the serial retry run 2; the dump must show run 2.
has "$OUT" "FAILMARKER run 2" "the dump shows the serial re-run's log"
hasnt "$OUT" "FAILMARKER run 1" "the parallel log was overwritten, not shown"

echo "── 5. --no-retry and --retry 0 report the raw parallel result ──"
reset_state
run --no-retry "$FIX/flaky.test.sh"
eq "$RC" 1 "--no-retry lets the parallel false failure stand"
hasnt "$OUT" "re-running serially" "--no-retry skips the serial phase"
hasnt "$OUT" "recovered" "--no-retry recovers nothing"
reset_state
run --retry=0 "$FIX/flaky.test.sh"
eq "$RC" 1 "--retry=0 is the same as --no-retry"
hasnt "$OUT" "re-running serially" "--retry=0 skips the serial phase"

echo "── 6. --retry N bounds the serial attempts ──"
reset_state
run --retry 2 "$FIX/twice.test.sh"
eq "$RC" 0 "two serial retries recover a file that needs the third run"
has "$OUT" "recovered serially after 2 attempt" "the attempt count is reported"
reset_state
run --retry 1 "$FIX/twice.test.sh"
eq "$RC" 1 "one retry is not enough for a file that passes only on run 3"
has "$OUT" "failed serially too" "and it is reported failed"

echo "── 7. a mixed run reclassifies independently ──"
reset_state
run "$FIX/pass.test.sh" "$FIX/flaky.test.sh" "$FIX/afail.test.sh"
eq "$RC" 1 "one unrecoverable failure fails the suite despite a recovery"
has "$OUT" "2 passed (1 recovered on serial re-run), 1 failed" "the summary splits recovered from real"

# A file with parts declares them in its opening comment block. Each fixture
# below records the part each run was handed, so the assertions read what the
# runner exported, not just what it printed.
cat > "$FIX/parts.test.sh" <<'F'
#!/usr/bin/env bash
# run-tests-parts: one two three
echo "${RUN_TESTS_PART-unset}|${RUN_TESTS_PARTS-unset}" >> "$RUNTESTS_FIXTURE_STATE/parts.runs"
F

# Part two fails its first run and passes after; the other parts always pass.
cat > "$FIX/partflaky.test.sh" <<'F'
#!/usr/bin/env bash
# run-tests-parts: one two three
c="$RUNTESTS_FIXTURE_STATE/partflaky.$RUN_TESTS_PART"
n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$c"
[ "$RUN_TESTS_PART" != two ] || [ "$n" -ge 2 ]
F

# Part two always fails, printing which part produced the log.
cat > "$FIX/partfail.test.sh" <<'F'
#!/usr/bin/env bash
# run-tests-parts: one two
echo "PARTMARKER $RUN_TESTS_PART"
[ "$RUN_TESTS_PART" != two ]
F

# Part slow outlasts a short timeout; part quick does not.
cat > "$FIX/partslow.test.sh" <<'F'
#!/usr/bin/env bash
# run-tests-parts: quick slow
[ "$RUN_TESTS_PART" != slow ] || sleep 20
F

# A declaration below the opening comment block is not one.
cat > "$FIX/lateparts.test.sh" <<'F'
#!/usr/bin/env bash
# no parts are declared up here
echo "${RUN_TESTS_PART-unset}" >> "$RUNTESTS_FIXTURE_STATE/late.runs"
: <<'X'
# run-tests-parts: never
X
F

printf '#!/usr/bin/env bash\n# run-tests-parts: one bad/name\n' > "$FIX/badparts.test.sh"
printf '#!/usr/bin/env bash\n# run-tests-parts: one one\n' > "$FIX/dupparts.test.sh"

echo "── parts: a file with parts runs once per part, told its part and every declared part ──"
reset_state
run "$FIX/parts.test.sh"
eq "$RC" 0 "every part passes, so the suite passes"
eq "$(sort "$STATE/parts.runs" | tr '\n' ' ')" "one|one two three three|one two three two|one two three " \
  "each declared part ran exactly once, handed its own name and the declared list"
has "$OUT" "1 files as 3 runs" "the header counts the runs beside the files"
has "$OUT" "parts.test.sh[two] (" "each run is reported under its file and part"
has "$OUT" "3 passed, 0 failed, 3 total" "the summary counts runs"

echo "── parts: a failed part re-runs serially on its own ──"
reset_state
run "$FIX/partflaky.test.sh"
eq "$RC" 0 "the part that failed under -j recovers serially"
has "$OUT" "partflaky.test.sh[two] (recovered serially after 1 attempt" "the recovery names the part"
eq "$(cat "$STATE/partflaky.one") $(cat "$STATE/partflaky.two") $(cat "$STATE/partflaky.three")" "1 2 1" \
  "only the failed part ran again"

echo "── parts: a part that fails serially too is reported and dumped by itself ──"
reset_state
run "$FIX/partfail.test.sh"
eq "$RC" 1 "a part that fails alone too fails the suite"
has "$OUT" "partfail.test.sh[two] (failed serially too)" "the failure names the part"
has "$OUT" "----- $FIX/partfail.test.sh[two] -----" "the dump is headed by the part"
has "$OUT" "PARTMARKER two" "the dump shows that part's log"
hasnt "$OUT" "PARTMARKER one" "a part that passed is not dumped"
has "$OUT" "1 passed, 1 failed, 2 total" "the passing part still counts as a pass"

echo "── parts: each part has its own timeout ──"
reset_state
OUT="$(RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 2 -t 2 --no-retry "$FIX/partslow.test.sh" 2>&1)"; RC=$?
eq "$RC" 1 "the part that outlasts the timeout fails the suite"
has "$OUT" "TIMEOUT    $FIX/partslow.test.sh[slow]" "the timeout is the slow part's"
has "$OUT" "1 passed, 1 failed" "the quick part passes under the same limit"

echo "── parts: only the opening comment block declares parts ──"
reset_state
RUN_TESTS_PART=leaked run "$FIX/lateparts.test.sh"
eq "$RC" 0 "a file whose only declaration sits below its opening comments runs"
eq "$(cat "$STATE/late.runs")" "unset" "it runs once, as a whole file, with no part exported, whatever the caller had set"
has "$OUT" "run-tests: 1 files, 1 parallel" "no runs beyond the file are counted"

echo "── parts: --list prints one line per run ──"
run --list "$FIX/parts.test.sh" "$FIX/pass.test.sh"
eq "$RC" 0 "--list exits 0"
eq "$(printf '%s\n' "$OUT" | sort | tr '\n' ' ')" \
  "$FIX/parts.test.sh[one] $FIX/parts.test.sh[three] $FIX/parts.test.sh[two] $FIX/pass.test.sh " \
  "a file with parts is listed once per part, a file without once"

echo "── parts: a malformed declaration is a usage error ──"
run "$FIX/badparts.test.sh"
eq "$RC" 2 "a part name with characters outside [A-Za-z0-9_-] is refused"
has "$OUT" "declares a malformed part name 'bad/name'" "…and named"
run "$FIX/dupparts.test.sh"
eq "$RC" 2 "a part declared twice is refused"
has "$OUT" "declares part 'one' twice" "…and named"

echo "── 8. --retry rejects a non-integer ──"
run --retry abc "$FIX/pass.test.sh"
eq "$RC" 2 "a non-integer --retry is a usage error"
has "$OUT" "--retry must be a non-negative integer" "and says why"

echo "── 9. every file runs with commit and tag signing off ──"
# A git config that signs commits and tags with a signer that always fails
# stands in for a host whose signing agent is unreachable. The probe entry is
# the caller's own GIT_CONFIG_COUNT config, which must survive the runner's.
cat > "$TMP/signing.gitconfig" <<'G'
[commit]
	gpgsign = true
[tag]
	gpgsign = true
[gpg]
	format = ssh
[gpg "ssh"]
	program = false
[user]
	signingkey = /nonexistent/signing-key.pub
G
cat > "$FIX/signing.test.sh" <<'F'
#!/usr/bin/env bash
set -e
r="$(mktemp -d "$RUNTESTS_FIXTURE_STATE/repo.XXXXXX")"
git init -q "$r"
git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m c
git -C "$r" -c user.email=t@t -c user.name=t tag -m t t1
probe="$(git config --get gctk.probe || true)"
echo "probe=$probe"
[ "$probe" = kept ]
F
signing_env() {
  GIT_CONFIG_GLOBAL="$TMP/signing.gitconfig" \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=gctk.probe GIT_CONFIG_VALUE_0=kept "$@"
}
reset_state
signing_env run "$FIX/signing.test.sh"
eq "$RC" 0 "a file commits and tags with signing off, keeping the caller's config"
has "$OUT" "1 passed, 0 failed" "and passes in the parallel wave"
# The same file run directly, with the same config, fails at its commit: the
# pass above is the runner's doing, not a config that never signed.
reset_state
OUT="$(RUNTESTS_FIXTURE_STATE="$STATE" signing_env bash "$FIX/signing.test.sh" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ]; then ok "the file run directly fails"; else bad "the file run directly fails" "it exited 0"; fi
has "$OUT" "failed to write commit object" "because the commit could not be signed"

printf '\nrun-tests: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
