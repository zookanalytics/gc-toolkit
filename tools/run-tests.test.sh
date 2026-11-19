#!/usr/bin/env bash
# run-tests.test.sh — the serial re-run that tells a parallel-contention false
# failure from a real one, the runs a file with parts is split into, and how
# many runs the parallel wave holds at once and at what priority.
#
# A file can fail under -j for a reason that is not its own: a sibling job
# saturates the host and a command the file spawned is killed, so an assertion
# reads a 143 where it wanted a real exit. The runner re-runs each failed file
# serially, where no sibling competes with it, and only a file that fails alone
# too is a real failure. That reclassification is what this pins.
#
# It also pins the affected subset, the suites a set of changed paths selects:
# each shape of suite a change can break outside its sibling test is a --list
# case over a fixture repo. --affected, which reads the changed paths from the
# fixture repo's history, is pinned the same way.
#
# Asserted here:
#   - a file with parts runs once per declared part, each run handed its part
#     and the declared list, and each with its own guard, report line, serial
#     re-run and failure dump; only the opening comment block declares parts,
#     and a malformed declaration is a usage error;
#   - a run that keeps writing passes however long it runs past the timeout,
#     while one that writes nothing for the timeout is ended as hung, with every
#     process in its group, and reported as a TIMEOUT whose log says why;
#   - a run ends once the runner that started it is gone;
#   - a run ended as hung in the parallel wave that passes alone is recovered,
#     so the wave's TIMEOUT does not follow it to its serial re-run;
#   - a file that fails once then passes is recovered on serial re-run (default);
#   - a file that fails every time stays failed and the suite exits 1;
#   - --no-retry and --retry 0 report the raw parallel result;
#   - --retry N bounds the serial attempts;
#   - the serial run's log, not the parallel one, is what the failure dump shows;
#   - --retry rejects a non-integer;
#   - --seconds FILE empties the file, then gets one line per run of the
#     parallel wave, quiet or not, naming the run as its report line does with
#     its whole seconds and its status, and no line for a serial re-run; a FILE
#     that cannot be written, or a missing one, is a usage error;
#   - every file commits and tags with signing off, under a git config that
#     signs both with a signer that always fails, and a git config entry the
#     caller exported still reaches it;
#   - every file runs under the physical path of the caller's TMPDIR, or of
#     /tmp when it is unset, with no symlink and no trailing slash, while the
#     same file run directly gets the TMPDIR as given; a TMPDIR that names no
#     directory is a usage error;
#   - every file runs with the test floor at the front of PATH: gc, bd and gh
#     resolve to it and git does not, and a call made after a file's stub
#     directory is removed is refused there rather than reaching the binary
#     behind it, which the same file run directly reaches; a tree without the
#     floor does not run;
#   - every file runs with no GC_* or BEADS_* variable of the caller's and with
#     those outside both prefixes, while the same file run directly gets them
#     all; the gc binary GC_BIN names reaches a file as RUN_TESTS_GC_BIN, in
#     place of one the caller exported, and with no GC_BIN a file gets none;
#   - a run with files that source the shared harness builds the fake gc once
#     and hands each file its path as RUN_TESTS_FAKE_GC, in place of one the
#     caller exported; a run with none builds nothing, and a build that fails
#     is named and hands on nothing;
#   - with no -j and no TEST_JOBS the wave runs half the cores, at least one,
#     counted by nproc, else getconf, else sysctl, and capped at the run count;
#     TEST_JOBS and -j each override that default;
#   - a run of the parallel wave starts at a niceness 10 above the caller's,
#     and at ionice's lowest best-effort level where ionice can set it, while a
#     serial re-run keeps the caller's priority; an ionice that refuses the
#     class is left out and fails no run;
#   - a changed script reaches its sibling, every suite naming it on a line
#     that is not a comment, and the sibling of every script naming it so, one
#     hop and no further; no suite naming a longer name that ends in it, and
#     the same suites when the path is typed with ./;
#   - a changed library reaches every suite of each script that sources it,
#     through a `.` command or a shellcheck directive, and of whatever sources
#     those in turn; a message or a document that says "source" sources
#     nothing;
#   - every subset includes the suites whose opening comment block declares
#     the tree scope, and only those;
#   - a basename two tracked files share is matched with the parent directory
#     that tells them apart;
#   - a changed file that is not a script, or that no longer exists, reaches
#     the suites that name it;
#   - with no PATH every tracked suite is listed once;
#   - a scope other than tree, or an empty one, is a usage error in the
#     affected run and the full run alike;
#   - --affected BASE lists what the same change lists given as PATHs. The
#     change is the files HEAD's commits change since their merge base with
#     BASE, so neither a commit BASE made after the branch left it nor an
#     uncommitted edit is part of it. A renamed file counts under its old path
#     too, and a name with a space or a byte git quotes arrives whole;
#   - a change that names no file runs no suite, not even a tree-wide one: the
#     run prints one line saying so and exits 0, and --list prints nothing;
#   - a path a Go program is compiled from reaches the suites that compile it.
#     A file of a package the program imports, a file such a package embeds
#     and a Go file the package's directory no longer has each reach the suite
#     that compiles it inline, the suites calling the library function that
#     compiles it, or the library's function that calls that one, and the
#     sibling and the users of a script that compiles it outside a function,
#     with a here-document in a function's body read as no part of the body.
#     A change that deletes or moves a program's whole main package reaches
#     the suites that still compile it by its old path. A _test.go file, and a
#     file in no package's directory, reach no suite;
#     go.mod reaches every program's; a go that cannot list the packages, or
#     what a program imports, lets a .go file reach every such program and
#     nothing else reach any; and --affected reaches the same suites from a
#     branch's commit;
#   - a BASE git cannot read, a missing BASE, an option or a range where BASE
#     belongs, and a PATH beside --affected are usage errors;
#   - the runner runs no suite, and exits 2, unless its own bash and the first
#     bash on PATH from the repository root are both 5.1 or later.
#
# Hermetic: runs a copy of the runner over throwaway fixture *.test.sh files
# whose pass/fail is driven by a per-file invocation counter, so "fails the
# first time, passes the next" stands in for the contention the real flake needs
# a loaded host to produce. The job-count and priority cases put stub nproc,
# getconf, sysctl and ionice ahead of the real tools on PATH, so the counts and
# I/O class they assert are the same on every host. The affected-subset cases
# run a copy of the runner inside throwaway git repos whose tracked files are
# the fixtures, committed where a case reads its change from history. No live
# city, no network.

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
# The runner prints each file it runs with any doubled slash collapsed, and a
# TMPDIR ending in / leaves one in mktemp's path, so TMP is resolved before any
# expected path is built.
TMP="$(cd "$TMP" && pwd -P)" || { echo "cannot resolve the temp dir"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Ambient git config and the env knobs the runner reads must not reach it, so
# the default behaviour under test is the runner's own, not the host's.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_CONFIG_COUNT "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}"
unset TEST_JOBS TEST_TIMEOUT TEST_RETRY

# The runner derives its root from its own location, so give it a git repo to
# sit in, with the test floor it puts every file above. The fixtures live
# outside it and are passed by absolute path.
REPO="$TMP/repo"
mkdir -p "$REPO/tools"
cp "$RUNNER" "$REPO/tools/run-tests.sh"
cp -R "$HERE/test-floor" "$REPO/tools/"
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

# Part slow stays quiet past a short timeout; part quick does not.
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

echo "── parts: each part has its own guard ──"
reset_state
OUT="$(RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 2 -t 2 --no-retry "$FIX/partslow.test.sh" 2>&1)"; RC=$?
eq "$RC" 1 "the part that stays quiet past the timeout fails the suite"
has "$OUT" "TIMEOUT    $FIX/partslow.test.sh[slow]" "the timeout is the quiet part's"
has "$OUT" "1 passed, 1 failed" "the quick part passes under the same limit"

# The talker writes a line every quarter second for RUNTESTS_TALK seconds, then
# stays quiet for RUNTESTS_QUIET seconds and passes. It records its own pid,
# which leads the run's process group, and the pid of a child it leaves running
# in that group.
cat > "$FIX/talker.test.sh" <<'F'
#!/usr/bin/env bash
echo "$$" > "$RUNTESTS_FIXTURE_STATE/talker.pid"
sleep 300 &
echo "$!" > "$RUNTESTS_FIXTURE_STATE/talker.child"
end=$((EPOCHSECONDS + ${RUNTESTS_TALK:-0})); n=0
while [ "$EPOCHSECONDS" -lt "$end" ]; do n=$((n + 1)); echo "talk $n"; sleep 0.25; done
echo "TALKED $n"
sleep "${RUNTESTS_QUIET:-0}"
F

# gone <pid>: wait up to fifteen seconds for the process to be gone. No pid, as
# when the fixture never recorded one, is never gone.
gone() {
  [ -n "$1" ] || return 1
  for _ in $(seq 1 60); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.25
  done
  return 1
}

echo "── guard: a run that keeps writing is never ended for its length ──"
reset_state
OUT="$(RUNTESTS_TALK=8 RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 1 -t 5 --no-retry "$FIX/talker.test.sh" 2>&1)"; RC=$?
eq "$RC" 0 "a run that writes four lines a second passes, though it runs longer than the timeout"
has "$OUT" "PASS       $FIX/talker.test.sh" "it is reported as a pass"
gone "$(cat "$STATE/talker.child" 2>/dev/null)" && ok "the child it left behind is gone" \
  || bad "the child it left behind is gone" "pid $(cat "$STATE/talker.child" 2>/dev/null) still runs"

echo "── guard: a run that goes quiet is ended as hung, with everything in its group ──"
reset_state
started="$SECONDS"
OUT="$(RUNTESTS_TALK=4 RUNTESTS_QUIET=120 RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 1 -t 3 --no-retry "$FIX/talker.test.sh" 2>&1)"; RC=$?
took=$((SECONDS - started))
eq "$RC" 1 "a run that goes quiet fails the suite"
has "$OUT" "TIMEOUT    $FIX/talker.test.sh" "it is reported as a timeout"
has "$OUT" "TALKED" "it was not ended while it wrote, though it wrote for longer than the timeout"
has "$OUT" "run-tests: nothing written for 3s, so the run has hung and is ended" \
  "its log says why the runner ended it"
[ "$took" -lt 60 ] && ok "it is ended once quiet for the timeout, not when its quiet ends" \
  || bad "it is ended once quiet for the timeout, not when its quiet ends" "the runner took ${took}s"
gone "$(cat "$STATE/talker.child" 2>/dev/null)" && ok "the child it left running is ended with it" \
  || bad "the child it left running is ended with it" "pid $(cat "$STATE/talker.child" 2>/dev/null) still runs"

echo "── guard: a run ends once its runner is gone ──"
# The run writes for two minutes, so only its runner's end can end it here. The
# runner's temp goes under TMP, in case its stop leaves the log directory.
reset_state
mkdir -p "$TMP/stopped-tmp"
TMPDIR="$TMP/stopped-tmp" RUNTESTS_TALK=120 RUNTESTS_FIXTURE_STATE="$STATE" \
  "$RUNNER_COPY" -j 1 -t 30 --no-retry "$FIX/talker.test.sh" >/dev/null 2>&1 &
stopped_runner=$!
for _ in $(seq 1 120); do [ -s "$STATE/talker.child" ] && break; sleep 0.25; done
run_pid="$(cat "$STATE/talker.pid" 2>/dev/null)"
kill -TERM "$stopped_runner" 2>/dev/null; wait "$stopped_runner" 2>/dev/null
if [ -n "$run_pid" ] && gone "$run_pid"; then
  ok "the run ends within seconds of its runner's stop"
else
  bad "the run ends within seconds of its runner's stop" "run pid '${run_pid}' still runs"
  # The run still stands, so its pid still names its group.
  [ -z "$run_pid" ] || kill -KILL -- "-$run_pid" 2>/dev/null
fi
gone "$(cat "$STATE/talker.child" 2>/dev/null)" && ok "and so does the child it left running" \
  || bad "and so does the child it left running" "pid $(cat "$STATE/talker.child" 2>/dev/null) still runs"

# Goes quiet on its first run and passes on every later one.
cat > "$FIX/hangonce.test.sh" <<'F'
#!/usr/bin/env bash
c="$RUNTESTS_FIXTURE_STATE/hangonce.count"
n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$c"
echo "hangonce run $n"
[ "$n" -ge 2 ] || sleep 60
F

echo "── guard: a run ended as hung in the wave that passes alone is recovered ──"
reset_state
OUT="$(RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 1 -t 2 "$FIX/hangonce.test.sh" 2>&1)"; RC=$?
eq "$RC" 0 "a run that passes on its serial re-run passes the suite"
has "$OUT" "TIMEOUT    $FIX/hangonce.test.sh" "the wave reports its run as a timeout"
has "$OUT" "recovered serially after 1 attempt" "its re-run is judged on its own, not by the wave's timeout"

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

echo "── seconds: --seconds keeps one line per run of the parallel wave ──"
printf '#!/usr/bin/env bash\nsleep 1\n' > "$FIX/nap.test.sh"
SEC="$TMP/seconds.tsv"
printf 'stale\n' > "$SEC"
reset_state
OUT="$(RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 4 -t 30 -q --seconds "$SEC" \
  "$FIX/pass.test.sh" "$FIX/afail.test.sh" "$FIX/parts.test.sh" "$FIX/nap.test.sh" 2>&1)"; RC=$?
eq "$RC" 1 "the run exits as it would without --seconds"
eq "$(cut -f1,3 "$SEC" | sort | tr '\t\n' '| ')" \
  "$FIX/afail.test.sh|FAIL[1] $FIX/nap.test.sh|PASS $FIX/parts.test.sh[one]|PASS $FIX/parts.test.sh[three]|PASS $FIX/parts.test.sh[two]|PASS $FIX/pass.test.sh|PASS " \
  "each run of the wave has one line with its report name and status, under -q too, and the serial re-run adds none"
eq "$(cut -f2 "$SEC" | grep -cvE '^[0-9]+$')" 0 "…and every line's seconds are a whole number"
eq "$(awk -F'\t' '$1 ~ /nap/ { print ($2 >= 1) }' "$SEC")" 1 "…which is the run's wall time"
run --seconds "$TMP/no-such-dir/seconds.tsv" "$FIX/pass.test.sh"
eq "$RC" 2 "a --seconds file that cannot be written is a usage error"
has "$OUT" "cannot write the --seconds file '$TMP/no-such-dir/seconds.tsv'" "…named"
hasnt "$OUT" "1 passed" "…and nothing runs"
run "$FIX/pass.test.sh" --seconds
eq "$RC" 2 "--seconds with no file is a usage error"

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

echo "── tmpdir: every file runs under the physical path of the caller's TMPDIR ──"
# A temp directory named through a symlink, with a trailing slash, stands in for
# macOS's TMPDIR, which ends in a slash and sits under /var, a symlink to
# /private/var.
mkdir -p "$TMP/tmp-real"
ln -s "$TMP/tmp-real" "$TMP/tmp-link"
TMP_REAL="$(cd "$TMP/tmp-real" && pwd -P)"
cat > "$FIX/tmpdir.test.sh" <<'F'
#!/usr/bin/env bash
printf '%s\n' "${TMPDIR-unset}" > "$RUNTESTS_FIXTURE_STATE/tmpdir"
F
reset_state
TMPDIR="$TMP/tmp-link/" run "$FIX/tmpdir.test.sh"
eq "$RC" 0 "a file runs under a TMPDIR named through a symlink"
eq "$(cat "$STATE/tmpdir")" "$TMP_REAL" "it gets the directory's physical path, with no trailing slash"
# The same file run directly gets the TMPDIR it was given: the physical path
# above is the runner's doing.
reset_state
RUNTESTS_FIXTURE_STATE="$STATE" TMPDIR="$TMP/tmp-link/" bash "$FIX/tmpdir.test.sh"
eq "$(cat "$STATE/tmpdir")" "$TMP/tmp-link/" "the file run directly gets the TMPDIR as given"
reset_state
OUT="$(unset TMPDIR; RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 2 -t 30 "$FIX/tmpdir.test.sh" 2>&1)"; RC=$?
eq "$RC" 0 "a file runs with TMPDIR unset"
eq "$(cat "$STATE/tmpdir")" "$(cd /tmp && pwd -P)" "and gets the physical path of /tmp"
reset_state
TMPDIR="$TMP/no-such-dir" run "$FIX/tmpdir.test.sh"
eq "$RC" 2 "a TMPDIR that names no directory is a usage error"
has "$OUT" "cannot resolve the temp directory '$TMP/no-such-dir'" "…and named"
if [ -e "$STATE/tmpdir" ]; then bad "and no file runs" "the fixture ran"; else ok "and no file runs"; fi

echo "── floor: every file runs above the test floor ──"
# CANARY stands in for the directory holding the real gc, bd and gh: each one
# there records that it was reached. The fixture stubs gc the way a suite does,
# in a directory at the front of PATH, then removes that directory, as a killed
# suite's EXIT trap does, and calls gc again. Each call
# runs in a subshell, as a script under test makes most of its calls, so each
# one searches PATH afresh. A shell that ran gc itself remembers the stub's path
# and fails on the missing file without searching again.
CANARY="$TMP/canary"
mkdir -p "$CANARY"
for t in gc bd gh; do
  cat > "$CANARY/$t" <<C
#!/usr/bin/env bash
echo "$t reached" >> "\$RUNTESTS_FIXTURE_STATE/canary"
C
  chmod +x "$CANARY/$t"
done
cat > "$FIX/floor.test.sh" <<'F'
#!/usr/bin/env bash
S="$RUNTESTS_FIXTURE_STATE"
for t in gc bd gh git; do printf '%s=%s\n' "$t" "$(command -v "$t")"; done > "$S/resolved"
BIN="$(mktemp -d "${TMPDIR:-/tmp}/gctk-floor-fixture.XXXXXX")"
printf '#!/usr/bin/env bash\necho stub\n' > "$BIN/gc"
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
( gc bd show x > "$S/with-stub" )
rm -rf "$BIN"
( gc bd create debris 2> "$S/refusal"; echo "$?" > "$S/rc" )
F
reset_state
PATH="$CANARY:$PATH" run "$FIX/floor.test.sh"
eq "$RC" 0 "a file runs with the floor on PATH"
eq "$(grep '^gc=' "$STATE/resolved")" "gc=$REPO/tools/test-floor/gc" "gc resolves to the floor, ahead of the caller's PATH"
eq "$(grep '^bd=' "$STATE/resolved")" "bd=$REPO/tools/test-floor/bd" "…and bd"
eq "$(grep '^gh=' "$STATE/resolved")" "gh=$REPO/tools/test-floor/gh" "…and gh"
hasnt "$(grep '^git=' "$STATE/resolved")" "test-floor" "git is left to the caller's PATH, since suites run the real git"
eq "$(cat "$STATE/with-stub")" "stub" "the file's own stub answers ahead of the floor"
eq "$(cat "$STATE/rc")" "127" "with the stub directory gone, the call fails as a missing command"
has "$(cat "$STATE/refusal")" "test-floor: refused 'gc bd create'" "…refused by the floor, which names it"
if [ -e "$STATE/canary" ]; then bad "…and the binary behind the floor is never reached" "$(cat "$STATE/canary")"; else ok "…and the binary behind the floor is never reached"; fi
# Run directly the file has no floor, so the same call reaches the canary: the
# canary is reachable, and the runner is what stands in front of it.
reset_state
RUNTESTS_FIXTURE_STATE="$STATE" PATH="$CANARY:$PATH" bash "$FIX/floor.test.sh"
eq "$(cat "$STATE/canary" 2>/dev/null)" "gc reached" "the same file run directly reaches the binary behind its removed stub"
# A tree without the floor does not run.
NREPO="$TMP/nofloor-repo"
mkdir -p "$NREPO/tools"
cp "$RUNNER" "$NREPO/tools/run-tests.sh"
git -C "$NREPO" init -q
reset_state
OUT="$(RUNTESTS_FIXTURE_STATE="$STATE" "$NREPO/tools/run-tests.sh" -j 2 -t 30 "$FIX/floor.test.sh" 2>&1)"; RC=$?
eq "$RC" 2 "a runner whose tree has no floor refuses to run"
has "$OUT" "no test floor at $NREPO/tools/test-floor" "…and names the missing floor"
if [ -e "$STATE/resolved" ]; then bad "…and no file runs" "the fixture ran"; else ok "…and no file runs"; fi

echo "── env: no GC_* or BEADS_* variable of the caller's reaches a file ──"
# The seeds stand in for a city's session: its city, rig, store and session, and
# the gc binary it names. RUNTESTS_FIXTURE_KEPT is outside both prefixes, and
# the RUN_TESTS_GC_BIN seed is one the caller exported itself.
cat > "$FIX/env.test.sh" <<'F'
#!/usr/bin/env bash
S="$RUNTESTS_FIXTURE_STATE"
compgen -e | grep -E '^(GC|BEADS)_' > "$S/names"
printf 'kept=%s\ngc-bin=%s\n' "${RUNTESTS_FIXTURE_KEPT-unset}" "${RUN_TESTS_GC_BIN-unset}" > "$S/env"
F
session_env() {
  GC_CITY_PATH=/live/city GC_CITY=/live/city GC_RIG=gc-toolkit GC_SESSION_ID=live-session \
    BEADS_DIR=/live/city/.beads BEADS_ACTOR=live-actor GC_BIN="$TMP/session-gc" \
    RUN_TESTS_GC_BIN=/caller/gc RUNTESTS_FIXTURE_KEPT=kept "$@"
}
reset_state
session_env run "$FIX/env.test.sh"
eq "$RC" 0 "a file runs under a session's variables"
eq "$(cat "$STATE/names")" "" "it sees no GC_* or BEADS_* variable"
eq "$(grep '^kept=' "$STATE/env")" "kept=kept" "…and keeps a variable outside both prefixes"
eq "$(grep '^gc-bin=' "$STATE/env")" "gc-bin=$TMP/session-gc" "the gc binary GC_BIN names reaches it as RUN_TESTS_GC_BIN, in place of the caller's"
reset_state
OUT="$(unset GC_BIN; RUN_TESTS_GC_BIN=/caller/gc RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 2 -t 30 "$FIX/env.test.sh" 2>&1)"; RC=$?
eq "$RC" 0 "a file runs with GC_BIN unset"
eq "$(grep '^gc-bin=' "$STATE/env")" "gc-bin=unset" "…and gets no RUN_TESTS_GC_BIN, even one the caller exported"
# Run directly, the file gets the session's variables as they are: the clear
# above is the runner's doing.
reset_state
session_env env RUNTESTS_FIXTURE_STATE="$STATE" bash "$FIX/env.test.sh"
names="$(cat "$STATE/names")"
has "$names" "GC_CITY_PATH" "the same file run directly sees the session's GC_* variables"
has "$names" "BEADS_DIR" "…and its BEADS_* ones"
eq "$(grep '^gc-bin=' "$STATE/env")" "gc-bin=/caller/gc" "…and the caller's own RUN_TESTS_GC_BIN"

echo "── fake gc: one build for a run's harness files ──"
# A go ahead of the real one on PATH records each build and writes a stand-in
# binary where -o names, or fails when STUB_GO_FAIL is set. The fixture tree
# gets the fake's package directory, which the runner builds from.
mkdir -p "$TMP/gobin" "$REPO/services/gctk/internal/gcbd/fakegc"
cat > "$TMP/gobin/go" <<'F'
#!/bin/sh
echo "$*" >> "$RUNTESTS_FIXTURE_STATE/go-calls"
[ -z "${STUB_GO_FAIL:-}" ] || { echo "stub go: the build failed" >&2; exit 1; }
out=""; prev=""; for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
printf '#!/bin/sh\n' > "$out" && chmod +x "$out"
F
chmod +x "$TMP/gobin/go"
for n in a b; do
  cat > "$FIX/harness-$n.test.sh" <<'F'
#!/usr/bin/env bash
# A suite on the harness sources assets/scripts/test-harness.sh here.
S="$RUNTESTS_FIXTURE_STATE"
if [ -n "${RUN_TESTS_FAKE_GC:-}" ] && [ -x "$RUN_TESTS_FAKE_GC" ]; then echo built >> "$S/fake-gc"; else echo "${RUN_TESTS_FAKE_GC-unset}" >> "$S/fake-gc"; fi
F
done
reset_state
OUT="$(PATH="$TMP/gobin:$PATH" RUN_TESTS_FAKE_GC=/caller/gc RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 2 -t 30 "$FIX/harness-a.test.sh" "$FIX/harness-b.test.sh" "$FIX/pass.test.sh" 2>&1)"; RC=$?
eq "$RC" 0 "a run with two harness files passes"
eq "$(wc -l < "$STATE/go-calls" | tr -d ' ')" "1" "…and builds the fake gc once"
has "$(cat "$STATE/go-calls")" "build -buildvcs=false -o" "…with go build"
eq "$(sort "$STATE/fake-gc" | tr '\n' ' ')" "built built " "…and each harness file gets the build, in place of the caller's"
reset_state
OUT="$(PATH="$TMP/gobin:$PATH" RUN_TESTS_FAKE_GC=/caller/gc RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 2 -t 30 "$FIX/env.test.sh" 2>&1)"; RC=$?
eq "$RC" 0 "a run with no harness file passes"
if [ -e "$STATE/go-calls" ]; then bad "…and builds nothing" "$(cat "$STATE/go-calls")"; else ok "…and builds nothing"; fi
reset_state
OUT="$(PATH="$TMP/gobin:$PATH" STUB_GO_FAIL=1 RUN_TESTS_FAKE_GC=/caller/gc RUNTESTS_FIXTURE_STATE="$STATE" "$RUNNER_COPY" -j 2 -t 30 "$FIX/harness-a.test.sh" 2>&1)"; RC=$?
eq "$RC" 0 "a run whose build fails still runs its files"
has "$OUT" "the fake gc did not build" "…and says the build failed"
has "$OUT" "stub go: the build failed" "…with the compiler's message"
eq "$(cat "$STATE/fake-gc")" "unset" "…and hands on no fake gc, not even the caller's"
rm -rf "$REPO/services"

echo "── jobs: the default is half the cores, at least one ──"
# The runner counts cores with nproc, then getconf, then sysctl. Stubs ahead of
# the real tools on PATH answer from STUB_NPROC, STUB_GETCONF and STUB_SYSCTL,
# and fail with no output where theirs is unset, as a missing tool does. The
# file's twelve parts outnumber every default below but one, so the header line
# reports the default itself rather than the cap at the run count.
CORES_BIN="$TMP/cores-bin"
mkdir -p "$CORES_BIN"
cat > "$CORES_BIN/nproc" <<'F'
#!/usr/bin/env bash
[ -n "${STUB_NPROC:-}" ] || exit 127
echo "$STUB_NPROC"
F
cat > "$CORES_BIN/getconf" <<'F'
#!/usr/bin/env bash
{ [ "${1:-}" = _NPROCESSORS_ONLN ] && [ -n "${STUB_GETCONF:-}" ]; } || exit 1
echo "$STUB_GETCONF"
F
cat > "$CORES_BIN/sysctl" <<'F'
#!/usr/bin/env bash
{ [ "${1:-}" = -n ] && [ "${2:-}" = hw.ncpu ] && [ -n "${STUB_SYSCTL:-}" ]; } || exit 1
echo "$STUB_SYSCTL"
F
chmod +x "$CORES_BIN"/*
cat > "$FIX/wide.test.sh" <<'F'
#!/usr/bin/env bash
# run-tests-parts: p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12
F
# run_cores [VAR=value...] [-- runner-args...] -> sets RC, OUT, and PAR: the
# parallel count the header line reports for the twelve-part file, run with no
# -j unless one is given, under the core stubs and the given env.
run_cores() {
  local -a vars=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do vars+=("$1"); shift; done
  [ "$#" -eq 0 ] || shift
  OUT="$(env PATH="$CORES_BIN:$PATH" "${vars[@]}" "$RUNNER_COPY" -t 30 "$@" "$FIX/wide.test.sh" 2>&1)"; RC=$?
  PAR="$(printf '%s\n' "$OUT" | sed -n 's/^run-tests: .* runs, \([0-9]*\) parallel,.*/\1/p')"
}
run_cores STUB_NPROC=8
eq "$RC" 0 "a run on the default job count passes"
eq "$PAR" 4 "eight cores from nproc give four jobs"
run_cores STUB_GETCONF=6
eq "$PAR" 3 "with no nproc, six from getconf give three"
run_cores STUB_SYSCTL=10
eq "$PAR" 5 "with neither, ten from sysctl give five"
run_cores STUB_NPROC=1
eq "$PAR" 1 "one core gives one job, not none"
run_cores
eq "$RC" 0 "a host no tool reports a count for still runs"
eq "$PAR" 1 "on one job"
run_cores STUB_NPROC=64
eq "$PAR" 12 "a default wider than the runs is capped at the run count"
run_cores STUB_NPROC=8 TEST_JOBS=3
eq "$PAR" 3 "TEST_JOBS overrides the default"
run_cores STUB_NPROC=8 -- -j 5
eq "$PAR" 5 "and so does -j"

echo "── priority: the parallel wave runs niced, a serial re-run at the caller's priority ──"
# The file fails its first run and passes its second, so run 1 is the parallel
# wave's and run 2 the serial re-run's. Each records its niceness and the I/O
# class a stub ionice, ahead of any real one on PATH, exported to it. The stub
# refuses every class while STUB_IONICE_REFUSE is set. The niceness expected of
# the wave is what nice -n 10 gives a child of this shell, which the system caps,
# so the case holds when this suite itself runs niced, as it does in a wave.
PRIO_BIN="$TMP/prio-bin"
mkdir -p "$PRIO_BIN"
cat > "$PRIO_BIN/ionice" <<'F'
#!/usr/bin/env bash
[ -z "${STUB_IONICE_REFUSE:-}" ] || exit 1
class="" level=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -c) class="$2"; shift 2 ;;
    -n) level="$2"; shift 2 ;;
    *)  break ;;
  esac
done
export STUB_IONICE="class $class level $level"
exec "$@"
F
chmod +x "$PRIO_BIN/ionice"
cat > "$FIX/prio.test.sh" <<'F'
#!/usr/bin/env bash
c="$RUNTESTS_FIXTURE_STATE/prio.count"
n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$c"
printf '%s|%s\n' "$(ps -o ni= -p "$$" | tr -d ' ')" "${STUB_IONICE-none}" > "$RUNTESTS_FIXTURE_STATE/prio.$n"
[ "$n" -ge 2 ]
F
OWN_NICE="$(ps -o ni= -p "$$" | tr -d ' ')"
NICED="$(nice -n 10 sh -c 'ps -o ni= -p "$$"' | tr -d ' ')"
reset_state
PATH="$PRIO_BIN:$PATH" run "$FIX/prio.test.sh"
eq "$RC" 0 "the file passes on its serial re-run"
eq "$(cat "$STATE/prio.1" 2>/dev/null)" "$NICED|class 2 level 7" \
  "the wave's run is niced 10 and at ionice's lowest best-effort level"
eq "$(cat "$STATE/prio.2" 2>/dev/null)" "$OWN_NICE|none" \
  "the serial re-run keeps the caller's niceness and I/O class"
reset_state
STUB_IONICE_REFUSE=1 PATH="$PRIO_BIN:$PATH" run "$FIX/prio.test.sh"
eq "$RC" 0 "an ionice that refuses the class fails no run"
eq "$(cat "$STATE/prio.1" 2>/dev/null)" "$NICED|none" \
  "the wave's run is still niced 10, without ionice"

# The affected subset is read from what a repo tracks, so its cases get a repo
# whose tracked files are the fixtures. The runner sits in it as it does in the
# pack, and every path below is passed relative to the root, the way
# `git diff --name-only` prints it.
AREPO="$TMP/affected"
mkdir -p "$AREPO/tools" "$AREPO/lib" "$AREPO/guard" "$AREPO/a" "$AREPO/b" "$AREPO/c" "$AREPO/conf"
cp "$RUNNER" "$AREPO/tools/run-tests.sh"
fixture() { mkdir -p "$(dirname "$AREPO/$1")"; cat > "$AREPO/$1"; }

# A library, a script that sources it with a `.` command, and a script that
# sources that one through a variable, which only its shellcheck directive names.
fixture lib/shared.sh <<'F'
#!/usr/bin/env bash
shared_fn() { echo shared; }
F
fixture lib/consumer.sh <<'F'
#!/usr/bin/env bash
. "$(dirname "$0")/shared.sh"
shared_fn
F
fixture lib/wrapper.sh <<'F'
#!/usr/bin/env bash
LIB="$(dirname "$0")/consumer.sh"
# shellcheck source=consumer.sh
. "$LIB"
F
# Names the library in a comment and in a message that says "source", and
# sources nothing; a document whose prose does the same and that shows the
# command, and a suite that reads that document.
fixture lib/mention.sh <<'F'
#!/usr/bin/env bash
# . "$(dirname "$0")/shared.sh" is what a consumer would run.
echo "run this after you source shared.sh"
F
fixture docs/notes.md <<'F'
Whichever source wins, `shared.sh` decides. A consumer loads it with

    . "$HERE/shared.sh"
F
fixture c/notes.test.sh <<'F'
#!/usr/bin/env bash
grep -q wins "$(git rev-parse --show-toplevel)/docs/notes.md"
F
fixture lib/consumer.test.sh <<'F'
#!/usr/bin/env bash
bash "$(dirname "$0")/consumer.sh"
F
fixture lib/wrapper.test.sh <<'F'
#!/usr/bin/env bash
bash "$(dirname "$0")/wrapper.sh"
F
fixture lib/mention.test.sh <<'F'
#!/usr/bin/env bash
bash "$(dirname "$0")/mention.sh"
F
# Suites other than the siblings that run the consumer, the wrapper and the
# mention.
fixture c/consumer-run.test.sh <<'F'
#!/usr/bin/env bash
bash "$(git rev-parse --show-toplevel)/lib/consumer.sh" --check
F
fixture c/wrapper-run.test.sh <<'F'
#!/usr/bin/env bash
bash "$(git rev-parse --show-toplevel)/lib/wrapper.sh" --check
F
fixture c/mention-run.test.sh <<'F'
#!/usr/bin/env bash
bash "$(git rev-parse --show-toplevel)/lib/mention.sh" --check
F

# A script with its sibling, a second suite that runs it, one that only
# mentions it in a comment, and one that runs a script whose name ends in its.
fixture lib/tool.sh <<'F'
#!/usr/bin/env bash
echo tool
F
fixture lib/tool.test.sh <<'F'
#!/usr/bin/env bash
bash "$(dirname "$0")/tool.sh"
F
fixture lib/tool-more.test.sh <<'F'
#!/usr/bin/env bash
bash "$(dirname "$0")/tool.sh" --more
F
fixture lib/tool-prose.test.sh <<'F'
#!/usr/bin/env bash
# Mentions tool.sh, and runs none of it.
true
F
fixture lib/mytool.test.sh <<'F'
#!/usr/bin/env bash
bash "$(dirname "$0")/mytool.sh"
F
# A script that runs the tool in place, and one that runs that script in turn,
# each with its sibling, neither of which names the tool.
fixture lib/runner.sh <<'F'
#!/usr/bin/env bash
"$(dirname "$0")/tool.sh"
F
fixture lib/runner.test.sh <<'F'
#!/usr/bin/env bash
bash "$(dirname "$0")/runner.sh"
F
fixture lib/outer.sh <<'F'
#!/usr/bin/env bash
"$(dirname "$0")/runner.sh"
F
fixture lib/outer.test.sh <<'F'
#!/usr/bin/env bash
bash "$(dirname "$0")/outer.sh"
F

# Two scripts that share a basename, and a suite that runs one of them by the
# path that tells them apart.
for d in a b; do
  printf '#!/usr/bin/env bash\necho %s\n' "$d" | fixture "$d/run.sh"
  printf '#!/usr/bin/env bash\nbash "$(dirname "$0")/run.sh"\n' | fixture "$d/run.test.sh"
done
fixture c/pick.test.sh <<'F'
#!/usr/bin/env bash
bash "$(git rev-parse --show-toplevel)/a/run.sh"
F

# A file that is not a script, a suite that reads it, and a suite that runs a
# script the tree no longer has.
printf 'key = 1\n' | fixture conf/settings.toml
fixture c/config.test.sh <<'F'
#!/usr/bin/env bash
grep -q key "$(git rev-parse --show-toplevel)/conf/settings.toml"
F
fixture c/legacy.test.sh <<'F'
#!/usr/bin/env bash
bash "$(git rev-parse --show-toplevel)/lib/gone.sh"
F

# A suite that declares the tree scope, and one whose declaration sits below
# its opening comment block, which is not one.
fixture guard/scan.test.sh <<'F'
#!/usr/bin/env bash
# Scans every tracked file for a pattern.
#
# run-tests-scope: tree
git ls-files
F
fixture guard/late.test.sh <<'F'
#!/usr/bin/env bash
# No scope is declared up here.
: <<'X'
# run-tests-scope: tree
X
F
git -C "$AREPO" init -q
git -C "$AREPO" add -A

# alist [paths...] -> sets RC, OUT, and LIST: what --list printed, sorted onto
# one line. -j is wider than the fixture set, so the order is not by size.
alist() {
  OUT="$("$AREPO/tools/run-tests.sh" -j 64 --list "$@" 2>&1)"; RC=$?
  LIST="$(printf '%s\n' "$OUT" | LC_ALL=C sort | tr '\n' ' ')"
}

echo "── 10. a script reaches its sibling, every suite naming it in code, and the sibling of every script naming it ──"
alist lib/tool.sh
eq "$RC" 0 "--list over a changed script exits 0"
eq "$LIST" "guard/scan.test.sh lib/runner.test.sh lib/tool-more.test.sh lib/tool.test.sh " \
  "the sibling, the suite that runs it, the sibling of the script that runs it in place, and the tree-wide suite"
hasnt "$LIST" "lib/outer.test.sh" "not the suite of a script one more hop away"
hasnt "$LIST" "lib/tool-prose.test.sh" "not a suite that mentions it only in a comment"
hasnt "$LIST" "lib/mytool.test.sh" "not a suite naming a longer name that ends in it"
alist ./lib/tool.sh
eq "$LIST" "guard/scan.test.sh lib/runner.test.sh lib/tool-more.test.sh lib/tool.test.sh " \
  "a path typed with ./ selects each suite once, under the same name"
alist lib//
eq "$(printf '%s\n' "$OUT" | grep -c .)" "$(printf '%s\n' "$OUT" | sort -u | grep -c .)" \
  "a directory typed with a trailing slash lists no suite twice"

echo "── 11. a sourced library reaches every suite of what sources it, transitively ──"
alist lib/shared.sh
eq "$LIST" "c/consumer-run.test.sh c/wrapper-run.test.sh guard/scan.test.sh lib/consumer.test.sh lib/mention.test.sh lib/wrapper.test.sh " \
  "the suites running its consumer, by a . command, and its consumer's consumer, by a shellcheck directive; the sibling of the script naming it"
hasnt "$LIST" "c/mention-run.test.sh" "a script whose message says source is not a consumer"
hasnt "$LIST" "c/notes.test.sh" "nor is a document that shows the command"

echo "── 12. every subset includes the tree-wide suites ──"
alist docs/unrelated.md
eq "$RC" 0 "a path no suite names is not an error"
eq "$LIST" "guard/scan.test.sh " \
  "the suite declaring the tree scope runs; a declaration below the opening comment block is not one"
alist lib
eq "$LIST" "guard/scan.test.sh lib/consumer.test.sh lib/mention.test.sh lib/mytool.test.sh lib/outer.test.sh lib/runner.test.sh lib/tool-more.test.sh lib/tool-prose.test.sh lib/tool.test.sh lib/wrapper.test.sh " \
  "a directory runs every suite beneath it, plus the tree-wide ones"

echo "── 13. a shared basename is told apart by its parent directory ──"
alist a/run.sh
eq "$LIST" "a/run.test.sh c/pick.test.sh guard/scan.test.sh " \
  "the suite naming a/run.sh runs for it"
alist b/run.sh
eq "$LIST" "b/run.test.sh guard/scan.test.sh " \
  "and not for b/run.sh, whose own sibling names only run.sh"

echo "── 14. a file that is not a script, or no longer exists, reaches the suites that name it ──"
alist conf/settings.toml
eq "$LIST" "c/config.test.sh guard/scan.test.sh " "a config file reaches the suite that reads it"
alist lib/gone.sh
eq "$LIST" "c/legacy.test.sh guard/scan.test.sh " "a deleted script reaches the suite that still runs it"

echo "── 15. with no PATH every tracked suite is listed, once ──"
alist
eq "$(printf '%s\n' "$OUT" | grep -c .)" "$(git -C "$AREPO" ls-files '*.test.sh' | grep -c .)" \
  "the full list is every tracked *.test.sh"

echo "── 16. a scope other than tree is a usage error ──"
SREPO="$TMP/scope"
mkdir -p "$SREPO/tools"
cp "$RUNNER" "$SREPO/tools/run-tests.sh"
printf '#!/usr/bin/env bash\n# run-tests-scope: tre\n' > "$SREPO/typo.test.sh"
git -C "$SREPO" init -q
git -C "$SREPO" add -A
OUT="$("$SREPO/tools/run-tests.sh" --list typo.test.sh 2>&1)"; RC=$?
eq "$RC" 2 "a misspelled scope fails the affected run"
has "$OUT" "typo.test.sh declares an unknown scope 'tre'" "…and names the file and the value"
OUT="$("$SREPO/tools/run-tests.sh" --list 2>&1)"; RC=$?
eq "$RC" 2 "and the full run too"
printf '#!/usr/bin/env bash\n# run-tests-scope:\n' > "$SREPO/typo.test.sh"
OUT="$("$SREPO/tools/run-tests.sh" --list 2>&1)"; RC=$?
eq "$RC" 2 "an empty scope is refused as well"

echo "── 17. --affected BASE lists the subset of the change HEAD's commits make since BASE ──"
# The affected repo's fixtures become the base commit, and each case commits
# its change on a branch of its own. A config file whose name carries a space
# and a byte git quotes joins them, with a suite that reads it by that name.
gitc() { git -C "$AREPO" -c user.name=run-tests -c user.email=run-tests@example.invalid "$@"; }
printf 'key = 1\n' | fixture "conf/réglages locaux.toml"
fixture c/accents.test.sh <<'F'
#!/usr/bin/env bash
grep -q key "$(git rev-parse --show-toplevel)/conf/réglages locaux.toml"
F
gitc add -A
gitc commit -q -m base
gitc branch base

# The repo has no test floor, so a run that went past the empty change would
# stop with a usage error rather than exit 0.
gitc checkout -q -b same base
OUT="$("$AREPO/tools/run-tests.sh" --affected base 2>&1)"; RC=$?
eq "$RC" 0 "a branch with no commits of its own exits 0"
eq "$OUT" "run-tests: base...HEAD changes no file — nothing to run" \
  "…after one line saying its change names no file, having run nothing"
alist --affected base
eq "$RC" 0 "--list over an empty change exits 0"
eq "$OUT" "" "…and lists no run, not even the tree-wide suite"

gitc checkout -q -b tool base
printf '#!/usr/bin/env bash\necho tool, changed\n' > "$AREPO/lib/tool.sh"
gitc commit -q -am "change the tool"
alist lib/tool.sh; WANT="$LIST"
alist --affected base
eq "$RC" 0 "--list over a branch's change exits 0"
eq "$LIST" "$WANT" "…and lists what the changed path lists given as a PATH"
alist --affected=base
eq "$LIST" "$WANT" "--affected=BASE is the same option"

gitc checkout -q base
printf 'key = 2\n' > "$AREPO/conf/settings.toml"
gitc commit -q -am "the base moves on"
gitc checkout -q tool
alist --affected base
eq "$LIST" "$WANT" "a commit the base made after the branch left it is not part of the change"
printf 'key = 3\n' > "$AREPO/conf/settings.toml"
alist --affected base
eq "$LIST" "$WANT" "nor is an uncommitted edit"
gitc checkout -q -- conf/settings.toml

gitc checkout -q -b moved base
gitc mv a/run.sh a/start.sh
gitc commit -q -m "rename a/run.sh"
alist --affected base
eq "$LIST" "a/run.test.sh c/pick.test.sh guard/scan.test.sh " \
  "a renamed file counts under its old path too, so the suites that run a/run.sh are listed"

gitc checkout -q -b accents base
printf 'key = 4\n' > "$AREPO/conf/réglages locaux.toml"
gitc commit -q -am "change the config with the awkward name"
alist --affected base
eq "$LIST" "c/accents.test.sh guard/scan.test.sh " \
  "a name with a space and a byte git quotes arrives whole and reaches the suite that reads it"

alist --affected no-such-ref
eq "$RC" 2 "a BASE git cannot read is a usage error"
has "$OUT" "cannot read the change from no-such-ref to HEAD" "…that names the base"
alist --affected
eq "$RC" 2 "a missing BASE is a usage error"
has "$OUT" "--affected needs a base" "…that says a base is needed"
OUT="$("$AREPO/tools/run-tests.sh" --affected --list 2>&1)"; RC=$?
eq "$RC" 2 "an option where BASE belongs is a usage error"
has "$OUT" "not the option '--list'" "…that names the option"
alist --affected base...HEAD
eq "$RC" 2 "a range where BASE belongs is a usage error"
has "$OUT" "not the range 'base...HEAD'" "…that names the range"
alist --affected base lib/tool.sh
eq "$RC" 2 "a PATH beside --affected is a usage error"
has "$OUT" "takes no PATH" "…that says why"

echo "── 18. a bash older than 5.1 runs nothing ──"
# macOS's /bin/bash is 3.2. The fixture marks the state directory when it runs.
cat > "$FIX/ran.test.sh" <<'F'
#!/usr/bin/env bash
touch "$RUNTESTS_FIXTURE_STATE/ran"
F
OLD_BASH=/bin/bash
old="$("$OLD_BASH" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2>/dev/null)"
case "$old" in
  [0-4].*|5.0)
    old_version="$("$OLD_BASH" -c 'echo "$BASH_VERSION"')"
    refused="run-tests: needs bash 5.1 or later, and $OLD_BASH is bash $old_version, so nothing ran"
    reset_state
    OUT="$(RUNTESTS_FIXTURE_STATE="$STATE" "$OLD_BASH" "$RUNNER_COPY" -j 2 -t 30 "$FIX/ran.test.sh" 2>&1)"; RC=$?
    eq "$RC" 2 "a run under bash $old is refused"
    eq "$OUT" "$refused" "…with one line naming the bash"
    eq "$(ls "$STATE")" "" "…and runs no suite"
    gitc checkout -q tool
    OUT="$("$OLD_BASH" "$AREPO/tools/run-tests.sh" --affected base 2>&1)"; RC=$?
    eq "$RC" 2 "--affected over a branch's change under bash $old is refused, not passed"
    eq "$OUT" "$refused" "…with the same one line"
    OUT="$("$OLD_BASH" "$AREPO/tools/run-tests.sh" --list --affected base 2>&1)"; RC=$?
    eq "$RC" 2 "--list under bash $old is refused too"
    eq "$OUT" "$refused" "…listing nothing"
    # The test's own bash runs the runner, and the older bash comes first on PATH.
    mkdir -p "$TMP/old-first"; ln -s "$OLD_BASH" "$TMP/old-first/bash"
    reset_state
    OUT="$(PATH="$TMP/old-first:$PATH" RUNTESTS_FIXTURE_STATE="$STATE" "$BASH" "$RUNNER_COPY" -j 2 -t 30 "$FIX/ran.test.sh" 2>&1)"; RC=$?
    eq "$RC" 2 "a run whose first bash on PATH is bash $old is refused under a newer bash too"
    eq "$OUT" "run-tests: each file starts with the first bash on PATH, and $TMP/old-first/bash is bash $old_version, older than 5.1, so nothing ran" \
      "…with one line naming the bash on PATH"
    eq "$(ls "$STATE")" "" "…and starts no suite"
    reset_state
    run "$FIX/ran.test.sh"
    eq "$RC" 0 "the same run under the bash on PATH passes"
    if [ -e "$STATE/ran" ]; then ok "…having run the suite"; else bad "…having run the suite" "no mark in $STATE"; fi
    alist --affected base
    eq "$LIST" "$WANT" "the same --affected under the bash on PATH lists the change's subset"
    ;;
  *) printf '  SKIP  %s is bash %s, so the runner was not run under a bash older than 5.1\n' "$OLD_BASH" "${old:-unknown}" ;;
esac

echo "── 19. a file starts with the bash the runner held to its floor ──"
# Each file starts from the repository root, so with bin first on PATH the
# runner must judge and start the root's bin/bash, not the caller's.
BREPO="$TMP/bash-repo"
CALLER="$TMP/caller"
mkdir -p "$BREPO/tools" "$BREPO/bin" "$CALLER/bin"
cp "$RUNNER" "$BREPO/tools/run-tests.sh"
cp -R "$HERE/test-floor" "$BREPO/tools/"
git -C "$BREPO" init -q
cat > "$TMP/bash-3.2" <<'F'
#!/bin/sh
[ "$1" = -c ] && echo "3.2 3.2.57(1)-release"
exit 0
F
cat > "$TMP/no-version" <<'F'
#!/bin/sh
exit 0
F
chmod +x "$TMP/bash-3.2" "$TMP/no-version"
cat > "$FIX/which.test.sh" <<'F'
#!/usr/bin/env bash
printf '%s\n' "$BASH" > "$RUNTESTS_FIXTURE_STATE/ran"
F
# from_caller <caller's bin/bash> <root's bin/bash> [runner-args...] -> RC and OUT
from_caller() {
  ln -sf "$1" "$CALLER/bin/bash"; ln -sf "$2" "$BREPO/bin/bash"; shift 2
  reset_state
  OUT="$(cd "$CALLER" && PATH="bin:$PATH" RUNTESTS_FIXTURE_STATE="$STATE" "$BASH" "$BREPO/tools/run-tests.sh" "$@" 2>&1)"; RC=$?
}
from_caller "$BASH" "$TMP/bash-3.2" -j 2 -t 30 "$FIX/which.test.sh"
eq "$RC" 2 "an older bash in bin under the root is refused, though the caller's bin holds a newer one"
eq "$OUT" "run-tests: each file starts with the first bash on PATH, and $BREPO/bin/bash is bash 3.2.57(1)-release, older than 5.1, so nothing ran" \
  "…with one line naming the root's bash by its full path"
eq "$(ls "$STATE")" "" "…and starts no suite"
for t in 30 0; do
  from_caller "$TMP/bash-3.2" "$BASH" -j 2 -t "$t" "$FIX/which.test.sh"
  eq "$RC" 0 "a newer bash in bin under the root runs the file, though the caller's bin holds an older one (-t $t)"
  eq "$(cat "$STATE/ran" 2>/dev/null)" "$BREPO/bin/bash" "…which starts under the root's bash, by its full path (-t $t)"
done
from_caller "$BASH" "$TMP/no-version" -j 2 -t 30 "$FIX/which.test.sh"
eq "$RC" 2 "a bash that reports no version is refused"
eq "$OUT" "run-tests: each file starts with the first bash on PATH, and $BREPO/bin/bash reports no bash version, so nothing ran" \
  "…with one line naming it"
eq "$(ls "$STATE")" "" "…and starts no suite"
# Only the caller's directory reaches a bash, so from the root PATH has none.
# The rest of PATH holds only the tools the runner calls for one file before it
# looks bash up.
NOBASH="$TMP/no-bash-path"
mkdir -p "$NOBASH" "$CALLER/only"
for t in dirname git awk sed paste sort grep cut; do ln -s "$(type -P "$t")" "$NOBASH/$t"; done
ln -s "$BASH" "$CALLER/only/bash"
reset_state
OUT="$(cd "$CALLER" && PATH="only:$NOBASH" RUNTESTS_FIXTURE_STATE="$STATE" "$BASH" "$BREPO/tools/run-tests.sh" -j 2 -t 30 "$FIX/which.test.sh" 2>&1)"; RC=$?
eq "$RC" 2 "a bash only the caller's directory reaches is refused, since from the root PATH has none"
eq "$OUT" "run-tests: each file starts with the first bash on PATH, and PATH has no bash, so nothing ran" \
  "…with one line saying so"
eq "$(ls "$STATE")" "" "…and starts no suite"

echo "── 20. a path a Go program is compiled from reaches the suites that compile it ──"
# A Go module with two programs a library compiles, tool and fake, and a third,
# server, one suite compiles inline. tool imports lib, which embeds a file from
# a directory beneath it, and server imports store. The real go lists the
# packages, with no toolchain download and no workspace.
GREPO="$TMP/go-repo"
mkdir -p "$GREPO/tools"
cp "$RUNNER" "$GREPO/tools/run-tests.sh"
gfix() { mkdir -p "$(dirname "$GREPO/$1")"; cat > "$GREPO/$1"; }
printf 'module example.invalid/fx\n\ngo 1.21\n' | gfix go.mod
gfix svc/cmd/tool/main.go <<'F'
package main

import "example.invalid/fx/svc/lib"

func main() { println(lib.Hello()) }
F
gfix svc/lib/lib.go <<'F'
package lib

import _ "embed"

//go:embed words/greeting.txt
var greeting string

func Hello() string { return greeting }
F
printf 'hello\n' | gfix svc/lib/words/greeting.txt
gfix svc/lib/lib_test.go <<'F'
package lib

import "testing"

func TestHello(t *testing.T) {}
F
gfix svc/fake/main.go <<'F'
package main

func main() {}
F
gfix other/store/store.go <<'F'
package store

func Open() {}
F
gfix other/cmd/server/main.go <<'F'
package main

import "example.invalid/fx/other/store"

func main() { store.Open() }
F
# A library suites source. build_tool compiles tool after a here-document whose
# lines would end a body if read as script; harness_up compiles fake through
# _fake; greet compiles nothing.
gfix lib/harness.sh <<'F'
#!/usr/bin/env bash
greet() { echo hi; }
build_tool() {
  cat > "$TMP/note" <<'NOTE'
}
NOTE
  ( cd "$(dirname "${BASH_SOURCE[0]}")/../svc" && go build -o "$TMP/tool" ./cmd/tool )
}
_fake() {
  ( cd "$(dirname "${BASH_SOURCE[0]}")/../svc" && go build -o "$TMP/fake" ./fake )
}
harness_up() {
  _fake
}
F
# A script that compiles tool outside any function, its sibling, and a suite
# that runs it.
gfix lib/stub.sh <<'F'
#!/usr/bin/env bash
( cd "$(dirname "$0")/../svc" && go build -o "$1/tool" ./cmd/tool )
F
gfix lib/stub.test.sh <<'F'
#!/usr/bin/env bash
bash "$(dirname "$0")/stub.sh" "$TMPDIR"
F
gfix t/uses-stub.test.sh <<'F'
#!/usr/bin/env bash
bash "$(git rev-parse --show-toplevel)/lib/stub.sh" "$TMPDIR"
F
gfix t/inline.test.sh <<'F'
#!/usr/bin/env bash
( cd "$(git rev-parse --show-toplevel)/svc" && go build -o ./out/tool ./cmd/tool )
F
gfix t/server.test.sh <<'F'
#!/usr/bin/env bash
( cd "$(git rev-parse --show-toplevel)/other" && go run ./cmd/server )
F
gfix t/builds-tool.test.sh <<'F'
#!/usr/bin/env bash
. "$(git rev-parse --show-toplevel)/lib/harness.sh"
build_tool
harness_up
F
gfix t/harness-only.test.sh <<'F'
#!/usr/bin/env bash
. "$(git rev-parse --show-toplevel)/lib/harness.sh"
harness_up
F
gfix t/sources-only.test.sh <<'F'
#!/usr/bin/env bash
. "$(git rev-parse --show-toplevel)/lib/harness.sh"
greet
F
gfix t/comment.test.sh <<'F'
#!/usr/bin/env bash
# go build ./cmd/tool is what a suite would run here.
true
F
git -C "$GREPO" init -q
git -C "$GREPO" add -A
# glist [args...] -> sets RC, OUT and LIST, as alist does, over the Go repo.
glist() {
  OUT="$(cd "$GREPO" && GOTOOLCHAIN=local GOWORK=off GOFLAGS='' "$GREPO/tools/run-tests.sh" -j 64 --list "$@" 2>&1)"; RC=$?
  LIST="$(printf '%s\n' "$OUT" | LC_ALL=C sort | tr '\n' ' ')"
}
TOOL_SUITES="lib/stub.test.sh t/builds-tool.test.sh t/inline.test.sh t/uses-stub.test.sh "
if ! command -v go >/dev/null 2>&1; then
  bad "the Go cases need go on PATH" "no go found"
else
  glist svc/lib/lib.go
  eq "$RC" 0 "--list over a Go file exits 0"
  eq "$LIST" "$TOOL_SUITES" \
    "a file of a package tool imports reaches the suite compiling tool inline, the suite calling the function that compiles it, and the sibling and the user of the script compiling it outside a function"
  hasnt "$LIST" "t/harness-only.test.sh" "…not a suite calling only the library's other compiling function"
  hasnt "$LIST" "t/sources-only.test.sh" "…nor one that sources the library and calls nothing that compiles"
  hasnt "$LIST" "t/comment.test.sh" "…nor one whose go build is a comment"
  glist svc/lib/words/greeting.txt
  eq "$LIST" "$TOOL_SUITES" "a file a package of tool embeds, below the package's directory, reaches the same suites"
  glist svc/lib/gone.go
  eq "$LIST" "$TOOL_SUITES" "so does a Go file the package's directory no longer has"
  glist svc/lib/lib_test.go
  eq "$OUT" "" "a _test.go file compiles into no program, so it reaches no suite"
  glist svc/fake/main.go
  eq "$LIST" "t/builds-tool.test.sh t/harness-only.test.sh " \
    "fake's file reaches the suites calling harness_up, the library's caller of the function compiling fake"
  glist other/store/store.go
  eq "$LIST" "t/server.test.sh " "a package only server imports reaches the suite that runs server with go run"
  glist go.mod
  eq "$LIST" "lib/stub.test.sh t/builds-tool.test.sh t/harness-only.test.sh t/inline.test.sh t/server.test.sh t/uses-stub.test.sh " \
    "go.mod reaches every program's suites"
  glist svc/notes.md
  eq "$OUT" "" "a file in no package's directory reaches no program"
  # A go that fails stands for one that cannot list the packages.
  mkdir -p "$TMP/failing-go"
  printf '#!/bin/sh\necho "stub go: cannot list" >&2\nexit 1\n' > "$TMP/failing-go/go"
  chmod +x "$TMP/failing-go/go"
  OUT="$(cd "$GREPO" && PATH="$TMP/failing-go:$PATH" "$GREPO/tools/run-tests.sh" -j 64 --list other/store/store.go 2>&1)"; RC=$?
  LIST="$(printf '%s\n' "$OUT" | LC_ALL=C sort | tr '\n' ' ')"
  eq "$RC" 0 "--list over a Go file with a go that cannot list exits 0"
  eq "$LIST" "lib/stub.test.sh t/builds-tool.test.sh t/harness-only.test.sh t/inline.test.sh t/server.test.sh t/uses-stub.test.sh " \
    "…and a .go file then reaches every program's suites"
  OUT="$(cd "$GREPO" && PATH="$TMP/failing-go:$PATH" "$GREPO/tools/run-tests.sh" -j 64 --list svc/lib/words/greeting.txt 2>&1)"; RC=$?
  eq "$OUT" "" "…while a file that is not Go source reaches none"
  # A go that lists the module's programs and fails to list what each imports.
  mkdir -p "$TMP/deps-go"
  printf '#!/bin/sh\ncase " $* " in *" -deps "*) echo "stub go: cannot list the imports" >&2; exit 1 ;; esac\nexec %s "$@"\n' \
    "'$(command -v go)'" > "$TMP/deps-go/go"
  chmod +x "$TMP/deps-go/go"
  OUT="$(cd "$GREPO" && PATH="$TMP/deps-go:$PATH" GOTOOLCHAIN=local GOWORK=off GOFLAGS='' "$GREPO/tools/run-tests.sh" -j 64 --list other/store/store.go 2>&1)"; RC=$?
  LIST="$(printf '%s\n' "$OUT" | LC_ALL=C sort | tr '\n' ' ')"
  eq "$LIST" "lib/stub.test.sh t/builds-tool.test.sh t/harness-only.test.sh t/inline.test.sh t/server.test.sh t/uses-stub.test.sh " \
    "a go that cannot list a program's imports lets a .go file reach that program's suites"
  OUT="$(cd "$GREPO" && PATH="$TMP/deps-go:$PATH" GOTOOLCHAIN=local GOWORK=off GOFLAGS='' "$GREPO/tools/run-tests.sh" -j 64 --list svc/lib/words/greeting.txt 2>&1)"; RC=$?
  eq "$OUT" "" "…and a file that is not Go source reach none of them"
  git -C "$GREPO" -c user.name=run-tests -c user.email=run-tests@example.invalid commit -q -m base
  git -C "$GREPO" branch base
  git -C "$GREPO" checkout -q -b change-lib
  printf 'package lib\n\nfunc Bye() string { return "bye" }\n' > "$GREPO/svc/lib/bye.go"
  git -C "$GREPO" add -A
  git -C "$GREPO" -c user.name=run-tests -c user.email=run-tests@example.invalid commit -q -m "add a file to lib"
  glist --affected base
  eq "$LIST" "$TOOL_SUITES" "--affected reaches the same suites when the change is a branch's commit"
  # go no longer lists a package the change deletes whole, so the suites that
  # still compile it by its path are found by the path alone.
  git -C "$GREPO" checkout -q -b delete-fake base
  git -C "$GREPO" rm -q -r svc/fake
  git -C "$GREPO" -c user.name=run-tests -c user.email=run-tests@example.invalid commit -q -m "delete the fake's package"
  glist --affected base
  eq "$LIST" "t/builds-tool.test.sh t/harness-only.test.sh " \
    "a change that deletes fake's whole package reaches the suites that still compile it"
  git -C "$GREPO" checkout -q -b move-server base
  git -C "$GREPO" mv other/cmd/server other/cmd/api
  git -C "$GREPO" -c user.name=run-tests -c user.email=run-tests@example.invalid commit -q -m "move the server's package"
  glist --affected base
  eq "$LIST" "t/server.test.sh " "…and one that moves server's reaches the suite that still runs it by its old path"
fi

printf '\nrun-tests: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
