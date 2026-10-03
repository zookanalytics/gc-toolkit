#!/usr/bin/env bash
# run-tests.test.sh — the serial re-run that tells a parallel-contention false
# failure from a real one.
#
# A file can fail under -j for a reason that is not its own: a sibling job
# saturates the host and a command the file spawned is killed, so an assertion
# reads a 143 where it wanted a real exit. The runner re-runs each failed file
# serially, where no sibling competes with it, and only a file that fails alone
# too is a real failure. That reclassification is what this pins.
#
# Asserted here:
#   - a file that fails once then passes is recovered on serial re-run (default);
#   - a file that fails every time stays failed and the suite exits 1;
#   - --no-retry and --retry 0 report the raw parallel result;
#   - --retry N bounds the serial attempts;
#   - the serial run's log, not the parallel one, is what the failure dump shows;
#   - --retry rejects a non-integer.
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

echo "── 8. --retry rejects a non-integer ──"
run --retry abc "$FIX/pass.test.sh"
eq "$RC" 2 "a non-integer --retry is a usage error"
has "$OUT" "--retry must be a non-negative integer" "and says why"

printf '\nrun-tests: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
