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
# It also pins the affected subset, the suites a set of changed paths selects:
# each shape of suite a change can break outside its sibling test is a --list
# case over a fixture repo.
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
#     caller exported still reaches it;
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
#     affected run and the full run alike.
#
# Hermetic: runs a copy of the runner over throwaway fixture *.test.sh files
# whose pass/fail is driven by a per-file invocation counter, so "fails the
# first time, passes the next" stands in for the contention the real flake needs
# a loaded host to produce. The affected-subset cases run a copy of the runner
# inside throwaway git repos whose tracked files are the fixtures. No live city,
# no network.

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

printf '\nrun-tests: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
