#!/usr/bin/env bash
# suite-time.test.sh — suite-time.sh's job summary of a seconds file, and the
# size comment's section on the suite's time: each job's time beside its limit,
# each suite job's test-seconds beside main's latest completed run that
# recorded them, and the test files a change adds, removes and moves.
#
# The section reads GitHub through a stub gh that serves each case's recorded
# responses by API path, copies a recorded seconds file for `gh run download`,
# and logs every call. The change is a real git repository. It sources
# test-harness.sh for the assertions only, because harness_init would stub git
# out. No jq.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/suite-time.sh"
[ -f "$SUT" ] || { echo "suite-time.test.sh: cannot find $SUT" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/suite-time-test.XXXXXX")" || { echo "suite-time.test.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=../../assets/scripts/test-harness.sh
. "$ROOT/assets/scripts/test-harness.sh"   # assertions only; harness_init would stub git out
PASS=0; FAIL=0

unset "${!GC_@}" "${!BEADS_@}" "${!GIT_@}" "${!GITHUB_@}" 2>/dev/null || true
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
git config --file "$GIT_CONFIG_GLOBAL" user.name T
git config --file "$GIT_CONFIG_GLOBAL" user.email t@e.com
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

# The stub gh. `api <path>` prints the recorded response the path names: a
# pull request's runs come from $GH_PR_RUNS, main's from main-runs.json, and a
# run's jobs and artifacts from jobs.<run>.json and arts.<run>.json. `run
# download <run> -n <name> -D <dir>` copies dl.<run>.<name>.tsv into <dir> as
# the artifact's file. A call whose words hold $GH_FAIL fails.
export FIX="$TMP/fix"; BIN="$TMP/bin"; mkdir -p "$FIX" "$BIN"
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
if [ -n "${GH_FAIL:-}" ]; then case "$*" in *"$GH_FAIL"*) exit 1 ;; esac; fi
if [ "$1 $2" = "run download" ]; then
  run=$3 name="" dir=""; shift 3
  while [ $# -gt 0 ]; do
    case "$1" in -n) name=$2 ;; -D) dir=$2 ;; esac
    shift 2
  done
  [ -f "$FIX/dl.$run.$name.tsv" ] || exit 1
  mkdir -p "$dir" && cp "$FIX/dl.$run.$name.tsv" "$dir/suite-times.tsv"
  exit 0
fi
[ "$1" = api ] || exit 1
id=${2#*/runs/}; id=${id%%/*}
case "$2" in
  */workflows/tests.yml/runs\?head_sha=*) cat "$GH_PR_RUNS" ;;
  */workflows/tests.yml/runs\?branch=main*) cat "$FIX/main-runs.json" ;;
  */runs/*/jobs*) cat "$FIX/jobs.$id.json" ;;
  */runs/*/artifacts*) cat "$FIX/arts.$id.json" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN/gh"

# section [<pr runs file>]: suite-time.sh's section for the change, with its
# output in OUT, its errors in ERR, its exit in RC, and the gh calls in CALLS
# with each download's directory left out.
section() {
  GH_LOG="$TMP/log.$RANDOM$RANDOM"
  OUT=$(cd "$REPO" && PATH="$BIN:$PATH" GH_LOG="$GH_LOG" GH_PR_RUNS="${1:-$FIX/pr-runs.json}" \
    "$SUT" section --repo github.com/o/r --head "$HEAD_SHA" --merge-base "$MB" 2>"$TMP/err")
  RC=$?
  ERR=$(cat "$TMP/err")
  CALLS=$(sed 's/ -D .*//' "$GH_LOG" 2>/dev/null)
}

echo "# summary: the runs' summed test-seconds and each run's seconds, slowest first"
printf 'a/one.test.sh\t3\tPASS\nb/two.test.sh[x]\t12\tFAIL[1]\nb/two.test.sh[y]\t3\tTIMEOUT\nbad`name.test.sh\t50\tPASS\na/zero.test.sh\tnine\tPASS\na/odd.test.sh\t4\tMAYBE\na/s.test.sh\t12s\tPASS\na/t.test.sh\t1234567\tPASS\n' > "$TMP/secs.tsv"
OUT=$("$SUT" summary "$TMP/secs.tsv"); RC=$?
eq "$RC" 0 "it exits 0"
eq "$OUT" '### Suite time

3 runs took 18 test-seconds. Each run'\''s seconds, slowest first:

| Run | Seconds | Status |
|---|---:|---|
| `b/two.test.sh[x]` | 12 | FAIL[1] |
| `a/one.test.sh` | 3 | PASS |
| `b/two.test.sh[y]` | 3 | TIMEOUT |' "…counting and listing only the lines of the runner's shape, ties by name"
OUT=$("$SUT" summary "$TMP/no-such.tsv"); RC=$?
eq "$RC:$OUT" '0:### Suite time

No run recorded its seconds.' "a job whose suite recorded nothing says so and exits 0"

# The change: the base carries the test files main times, and the head adds
# two, removes twenty-two and raises the test job's limit.
REPO="$TMP/repo"; mkdir -p "$REPO/.github/workflows" "$REPO/a" "$REPO/b"; cd "$REPO" && git init -q
workflow() { # <test job's limit>
  printf 'name: tests\non: [push]\njobs:\n'
  printf '  test:\n    runs-on: ubuntu-latest\n    timeout-minutes: %s\n    steps: []\n' "$1"
  printf '  test-macos:\n    runs-on: macos-latest\n    timeout-minutes: 60 # the slower runner\n    steps: []\n'
  printf '  go:\n    runs-on: ubuntu-latest\n    steps: []\n'
  printf '  docs:\n    runs-on: ubuntu-latest\n    timeout-minutes: ${{ fromJSON(vars.DOCS_LIMIT) }}\n    steps: []\n'
  printf '  lint:\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps: []\n'
}
workflow 25 > .github/workflows/tests.yml
for f in keep slow fast same big tiny edge gone; do echo "$f" > "a/$f.test.sh"; done
for i in $(seq -w 1 21); do echo "$i" > "b/rm$i.test.sh"; done
git add -A && git commit -q -m base
MB=$(git rev-parse HEAD)
workflow 30 > .github/workflows/tests.yml
mkdir -p c && echo new > a/new.test.sh && echo odd > 'c/we|rd.test.sh'
git rm -q a/gone.test.sh b/rm*.test.sh
git add -A && git commit -q -m "the head adds two test files, removes twenty-two and raises a limit"
HEAD_SHA=$(git rev-parse HEAD)
SHORT=${HEAD_SHA:0:12}

# The head's run, 900, and main's completed runs, newest first: 803 kept no
# seconds, 802 kept test's and an expired test-macos, and 801 kept both.
printf '{"workflow_runs":[{"id":900,"status":"completed","conclusion":"failure","html_url":"https://github.com/o/r/actions/runs/900"}]}' > "$FIX/pr-runs.json"
printf '{"total_count":5,"jobs":[
{"name":"test","conclusion":"success","started_at":"2026-11-17T03:11:10Z","completed_at":"2026-11-17T03:23:58Z"},
{"name":"test-macos","conclusion":"failure","started_at":"2026-11-17T03:11:25Z","completed_at":"2026-11-17T03:37:35Z"},
{"name":"go","conclusion":"success","started_at":"2026-11-17T03:11:10Z","completed_at":"2026-11-17T03:14:30Z"},
{"name":"docs","conclusion":"success","started_at":"2026-11-17T03:11:10Z","completed_at":"2026-11-17T03:12:10Z"},
{"name":"lint","conclusion":"skipped","started_at":"2026-11-17T03:34:28Z","completed_at":"2026-11-17T03:34:27Z"}]}' > "$FIX/jobs.900.json"
art() { printf '{"name":"%s","expired":%s}' "$1" "$2"; }
printf '{"artifacts":[%s,%s,%s]}' "$(art suite-times-test false)" "$(art suite-times-test-macos false)" "$(art other false)" > "$FIX/arts.900.json"
printf '{"workflow_runs":[{"id":803,"head_sha":"3333333333333333333333333333333333333333"},{"id":802,"head_sha":"1111111111111111111111111111111111111111"},{"id":801,"head_sha":"2222222222222222222222222222222222222222"}]}' > "$FIX/main-runs.json"
printf '{"artifacts":[]}' > "$FIX/arts.803.json"
printf '{"artifacts":[%s,%s]}' "$(art suite-times-test false)" "$(art suite-times-test-macos true)" > "$FIX/arts.802.json"
printf '{"artifacts":[%s,%s]}' "$(art suite-times-test false)" "$(art suite-times-test-macos false)" > "$FIX/arts.801.json"
# The head's seconds on test, with lines a change could forge that are not of
# the runner's shape, and on test-macos.
{
  printf 'a/keep.test.sh\t10\tPASS\na/slow.test.sh[one]\t15\tPASS\na/slow.test.sh[two]\t16\tPASS\n'
  printf 'a/fast.test.sh\t8\tPASS\na/same.test.sh\t21\tPASS\na/big.test.sh\t105\tPASS\n'
  printf 'a/tiny.test.sh\t3\tPASS\na/edge.test.sh\t22\tPASS\na/blip.test.sh\t4\tPASS\na/new.test.sh\t12\tPASS\n'
  printf 'main/later.test.sh\t5\tPASS\n'
  printf 'a/x`y.test.sh\t99\tPASS\na/z.test.sh\tabc\tPASS\na/w.test.sh\t5\tWEIRD\n'
} > "$FIX/dl.900.suite-times-test.tsv"
printf 'a/new.test.sh\t30\tPASS\na/keep.test.sh\t40\tFAIL[1]\n' > "$FIX/dl.900.suite-times-test-macos.tsv"
# Main's: test from 802, and from 801 numbers no case may show.
{
  printf 'a/keep.test.sh\t10\tPASS\na/slow.test.sh\t20\tPASS\na/fast.test.sh\t12\tPASS\n'
  printf 'a/same.test.sh\t20\tPASS\na/big.test.sh\t100\tPASS\na/tiny.test.sh\t1\tPASS\n'
  printf 'a/edge.test.sh\t20\tPASS\na/blip.test.sh\t3\tPASS\na/gone.test.sh\t4\tPASS\n'
  for i in $(seq -w 1 21); do printf 'b/rm%s.test.sh\t1\tPASS\n' "$i"; done
} > "$FIX/dl.802.suite-times-test.tsv"
printf 'a/keep.test.sh\t999\tPASS\n' > "$FIX/dl.801.suite-times-test.tsv"
{
  printf 'a/gone.test.sh\t9\tPASS\na/keep.test.sh\t38\tPASS\n'
  for i in $(seq -w 1 21); do printf 'b/rm%s.test.sh\t2\tPASS\n' "$i"; done
} > "$FIX/dl.801.suite-times-test-macos.tsv"

echo "# section: a finished run's time beside main's, and the files the change adds, removes and moves"
section
eq "$RC" 0 "it exits 0"
eq "$ERR" "" "…and says nothing on stderr"
eq "$CALLS" "api repos/o/r/actions/workflows/tests.yml/runs?head_sha=$HEAD_SHA&event=pull_request&per_page=1 --hostname github.com
api repos/o/r/actions/runs/900/jobs?per_page=100 --hostname github.com
api repos/o/r/actions/runs/900/artifacts?per_page=100 --hostname github.com
run download 900 -R github.com/o/r -n suite-times-test
run download 900 -R github.com/o/r -n suite-times-test-macos
api repos/o/r/actions/workflows/tests.yml/runs?branch=main&event=push&status=completed&per_page=10 --hostname github.com
api repos/o/r/actions/runs/803/artifacts?per_page=100 --hostname github.com
api repos/o/r/actions/runs/802/artifacts?per_page=100 --hostname github.com
run download 802 -R github.com/o/r -n suite-times-test
api repos/o/r/actions/runs/801/artifacts?per_page=100 --hostname github.com
run download 801 -R github.com/o/r -n suite-times-test-macos" \
  "it reads the head's newest pull request run, then main's completed runs newest first until each check has its own, passing over an expired artifact"
ROWS=$(for i in $(seq -w 1 19); do printf '| `b/rm%s.test.sh` | 1 | 2 |\n' "$i"; done)
eq "$OUT" "From the [tests run](https://github.com/o/r/actions/runs/900) at head \`$SHORT\`, beside main's latest completed run that recorded each check's seconds:

| Check | Job time | Test-seconds | Main | Factor |
|---|---|---:|---:|---:|
| test | 12m48s of 30m | 221 | 211 at \`111111111\` | 1.05 |
| test-macos | 26m10s of 60m, failure | 70 | 89 at \`222222222\` | 0.79 |
| go | 3m20s of 360m |  |  |  |
| docs | 1m00s |  |  |  |
| lint | skipped |  |  |  |

Test files the change adds, with their seconds at this head:

| File | test | test-macos |
|---|---:|---:|
| \`a/new.test.sh\` | 12 | 30 |
| \`c/we?rd.test.sh\` |  |  |

Test files the change removes, with their seconds on main:

| File | test | test-macos |
|---|---:|---:|
| \`a/gone.test.sh\` | 4 | 9 |
$ROWS

And 2 more.

Test files whose time on test moved by more than 10% and at least 2 seconds:

| File | Main | This head | Factor |
|---|---:|---:|---:|
| \`a/slow.test.sh\` | 20 | 31 | 1.55 |
| \`a/fast.test.sh\` | 12 | 8 | 0.67 |
| \`a/tiny.test.sh\` | 1 | 3 | 3.00 |" \
  "the section shows each job's time beside the head's limit, the summed seconds beside each check's own main run, and the files"

echo "# section: a head with no times of its own, and main with none"
printf '{"artifacts":[]}' > "$FIX/arts.901.json"
cp "$FIX/jobs.900.json" "$FIX/jobs.901.json"
printf '{"workflow_runs":[{"id":901,"status":"completed","conclusion":"cancelled","html_url":"u"}]}' > "$FIX/pr-901.json"
section "$FIX/pr-901.json"
eq "$RC" 0 "it exits 0"
has "$OUT" "| test | 12m48s of 30m | none recorded |  |  |" "a suite job that kept no seconds says none were recorded"
hasnt "$CALLS" "branch=main" "…and main's runs are not read"
has "$OUT" "No file's move on test is shown, because the run at this head recorded no seconds for test." "…nor a move shown"
printf '{"artifacts":[%s]}' "$(art suite-times-test false)" > "$FIX/arts.901.json"
cp "$FIX/dl.900.suite-times-test.tsv" "$FIX/dl.901.suite-times-test.tsv"
printf '{"workflow_runs":[]}' > "$FIX/main-runs.json"
section "$FIX/pr-901.json"
has "$OUT" "| test | 12m48s of 30m | 221 | none recorded |  |" "a check main has no seconds for is shown with none recorded for main"
has "$OUT" "No file's move on test is shown, because no recent run on main recorded seconds for test." "…and no move"

echo "# section: a head whose run has not finished, ran no job, or is not there"
printf '{"workflow_runs":[{"id":902,"status":"in_progress","conclusion":null,"html_url":"https://github.com/o/r/actions/runs/902"}]}' > "$FIX/pr-902.json"
section "$FIX/pr-902.json"
eq "$RC:$OUT" "0:The [tests run](https://github.com/o/r/actions/runs/902) at head \`$SHORT\` has not finished, so the suite's time shows once it does." \
  "a run in progress gets one sentence"
eq "$(printf '%s\n' "$CALLS" | wc -l | tr -d ' ')" 1 "…after the one read"
printf '{"workflow_runs":[{"id":903,"status":"completed","conclusion":"skipped","html_url":"https://github.com/o/r/actions/runs/903"}]}' > "$FIX/pr-903.json"
section "$FIX/pr-903.json"
eq "$RC:$OUT" "0:The [tests run](https://github.com/o/r/actions/runs/903) at head \`$SHORT\` ran no job, so the suite's time is not shown." \
  "a run that skipped every job, as a draft's does, gets one sentence"
printf '{"workflow_runs":[]}' > "$FIX/pr-none.json"
section "$FIX/pr-none.json"
eq "$RC:$OUT" "0:No tests run has tested head \`$SHORT\`, so the suite's time is not shown." \
  "a head no run tested gets one sentence"

echo "# section: a read that fails"
GH_FAIL=/jobs section
eq "$RC" 1 "a read that fails exits 1"
has "$ERR" "could not read repos/o/r/actions/runs/900/jobs" "…naming what it could not read"
eq "$OUT" "" "…and prints no section"
printf 'not json' > "$FIX/pr-bad.json"
section "$FIX/pr-bad.json"
eq "$RC:$OUT" "1:" "an answer that does not parse exits 1 with no section, never read as no run"
has "$ERR" "could not parse what repos/o/r/actions/workflows/tests.yml/runs?head_sha=$HEAD_SHA" "…naming the read"

echo "# usage"
"$SUT" section --repo github.com/o/r --head "$HEAD_SHA" >/dev/null 2>&1; eq "$?" 2 "a missing --merge-base is a usage error"
"$SUT" section --repo o/r --head "$HEAD_SHA" --merge-base "$MB" >/dev/null 2>&1; eq "$?" 2 "--repo must name its host"
"$SUT" tally >/dev/null 2>&1; eq "$?" 2 "an unknown verb is a usage error"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
