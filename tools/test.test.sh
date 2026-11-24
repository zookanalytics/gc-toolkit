#!/usr/bin/env bash
# test.test.sh — the repository's two test commands: the Makefile's targets and
# tools/test.sh, which they run.
#
# Asserted here:
#   - make test runs `tools/test.sh all`, and make test-affected runs
#     `tools/test.sh affected origin/main`; BASE replaces the base, and
#     RUN_TESTS_FLAGS reaches the runner after either;
#   - all runs the Go tests, `go test ./...` from the root, then the web app's
#     checks in services/helm/web (npm ci, its typecheck, its tests, and a build
#     into a directory of its own), then the shell suites through
#     tools/run-tests.sh with the options given and nothing else, and ends with
#     a pass line for each;
#   - go and npm run with no GC_* or BEADS_* variable of the caller's and with
#     the test floor first on PATH, while run-tests.sh gets the caller's
#     variables, which it hands on and clears itself;
#   - a kind that fails fails the run and stops none of the kinds after it, and
#     the end names it; a web check that fails stops the web checks after it;
#   - a build that does not match the committed dist/ fails the web checks,
#     names what differs and says how to fix it, and leaves every tracked file
#     as it was;
#   - affected reads the change HEAD's commits make since BASE: it runs the Go
#     tests and the runner's --affected BASE subset, and the web checks only
#     when the change touches services/helm, the app's own files or another
#     file of helm's, such as the read's golden board the app's tests render,
#     a file whose name git quotes, with a non-ASCII character or a tab,
#     included; a change that names no file runs nothing and exits 0;
#   - no mode, another mode, affected with no BASE or with an option for one,
#     a BASE git cannot read, and a tree without the test floor are usage
#     errors that run nothing.
#
# Hermetic: runs a copy of the Makefile and tools/test.sh in a throwaway git
# repository, with stand-ins for go, npm and tools/run-tests.sh that log each
# call, and the repository's own test floor. No network, no Go build, no npm
# install.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-test-test.XXXXXX")" || { echo "cannot mktemp"; exit 1; }
TMP="$(cd "$TMP" && pwd -P)" || { echo "cannot resolve the temp dir"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
STUBS="$TMP/stubs"
LOG="$TMP/calls"
mkdir -p "$REPO/tools" "$REPO/services/helm/web/dist/assets" \
  "$REPO/services/helm/internal/rigboard/testdata" "$REPO/docs" "$STUBS"
cp "$SRC/Makefile" "$REPO/Makefile"
cp "$SRC/tools/test.sh" "$REPO/tools/test.sh"
cp -R "$SRC/tools/test-floor" "$REPO/tools/"
printf '<html>board</html>\n' > "$REPO/services/helm/web/dist/index.html"
printf 'console.log(1)\n' > "$REPO/services/helm/web/dist/assets/index.js"
printf '{"rows":[]}\n' > "$REPO/services/helm/internal/rigboard/testdata/gc-toolkit.board.json"
printf '# notes\n' > "$REPO/docs/notes.md"

# Each stand-in logs one line: its name and arguments, the directory it ran in,
# the names of the caller's GC_* and BEADS_* variables it can see, and, for go
# and npm, the gc PATH resolves for it.
cat > "$REPO/tools/run-tests.sh" <<'F'
#!/usr/bin/env bash
printf 'shell %s | cwd=%s vars=,%s\n' "$*" "$PWD" "$(env | grep -oE '^(GC_|BEADS_)[A-Za-z0-9_]*' | sort | tr '\n' ,)" >> "$STUB_LOG"
exit "${STUB_SHELL_RC:-0}"
F
cat > "$STUBS/go" <<'F'
#!/usr/bin/env bash
printf 'go %s | cwd=%s vars=,%s gc=%s\n' "$*" "$PWD" "$(env | grep -oE '^(GC_|BEADS_)[A-Za-z0-9_]*' | sort | tr '\n' ,)" "$(command -v gc)" >> "$STUB_LOG"
exit "${STUB_GO_RC:-0}"
F
# npm's build writes STUB_BUILD's tree where --outDir names, as a build would.
cat > "$STUBS/npm" <<'F'
#!/usr/bin/env bash
printf 'npm %s | cwd=%s vars=,%s gc=%s\n' "$*" "$PWD" "$(env | grep -oE '^(GC_|BEADS_)[A-Za-z0-9_]*' | sort | tr '\n' ,)" "$(command -v gc)" >> "$STUB_LOG"
case " $* " in *" ${STUB_NPM_FAIL:-none} "*) exit 1 ;; esac
if [ "${1:-} ${2:-}" = "run build" ]; then
  out=""; prev=""
  for a in "$@"; do [ "$prev" = --outDir ] && out="$a"; prev="$a"; done
  mkdir -p "$out" && cp -R "$STUB_BUILD"/. "$out"/
fi
exit 0
F
chmod +x "$REPO/tools/run-tests.sh" "$STUBS/go" "$STUBS/npm"
# What the build stand-in writes: the committed dist/ as it is, or with one
# file changed or one added.
BUILT_SAME="$TMP/built-same"; BUILT_CHANGED="$TMP/built-changed"; BUILT_EXTRA="$TMP/built-extra"
for d in "$BUILT_SAME" "$BUILT_CHANGED" "$BUILT_EXTRA"; do cp -R "$REPO/services/helm/web/dist" "$d"; done
printf 'console.log(2)\n' > "$BUILT_CHANGED/assets/index.js"
printf 'new\n' > "$BUILT_EXTRA/assets/more.js"

gitc() { git -C "$REPO" -c user.name=test-test -c user.email=test-test@example.invalid -c commit.gpgsign=false "$@"; }
git -C "$REPO" init -q
printf 'node_modules/\n' > "$REPO/services/helm/web/.gitignore"
gitc add -A
gitc commit -q -m base
gitc branch base

# run <args...> -> RC, OUT and CALLS: a run of the copy's test.sh from the root,
# under a session's variables, with the stand-ins first on PATH.
run() {
  : > "$LOG"
  OUT="$(cd "$REPO" && env GC_CITY_PATH=/live/city GC_BIN=/live/gc BEADS_DIR=/live/.beads \
    STUB_LOG="$LOG" STUB_BUILD="${STUB_BUILD:-$BUILT_SAME}" PATH="$STUBS:$PATH" \
    bash tools/test.sh "$@" 2>&1)"; RC=$?
  CALLS="$(cat "$LOG")"
}
# kinds -> the kinds the log shows, in order, one word each.
kinds() { printf '%s\n' "$CALLS" | awk '{ print $1 }' | uniq | tr '\n' ' '; }

# fmake [NAME=value ...] make <args...> — a make in the fixture, clear of the
# make that may be running this suite, such as CI's `make test`. A make hands
# its flags and its command-line variables, RUN_TESTS_FLAGS among them, to the
# makes it starts, which also print the directories they enter.
fmake() { (cd "$REPO" && env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u MAKEOVERRIDES -u RUN_TESTS_FLAGS -u BASE "$@"); }

echo "── the Makefile's two targets ──"
eq "$(fmake make -n test)" "tools/test.sh all " "make test runs test.sh all"
eq "$(fmake make -n test-affected)" "tools/test.sh affected origin/main " "make test-affected runs test.sh affected against origin/main"
eq "$(fmake make -n test-affected BASE=base RUN_TESTS_FLAGS='-j 2 --seconds s.tsv')" "tools/test.sh affected base -j 2 --seconds s.tsv" \
  "BASE replaces the base, and RUN_TESTS_FLAGS follows it"
eq "$(fmake make -n test RUN_TESTS_FLAGS='-j 2')" "tools/test.sh all -j 2" "RUN_TESTS_FLAGS follows all too"
: > "$LOG"
OUT="$(fmake STUB_LOG="$LOG" STUB_BUILD="$BUILT_SAME" PATH="$STUBS:$PATH" make test 2>&1)"; RC=$?
eq "$RC" 0 "make test runs to a pass"
eq "$(awk '{ print $1 }' "$LOG" | uniq | tr '\n' ' ')" "go npm shell " "…through go, npm and the runner"

echo "── all: every kind, in order ──"
run all -j 3 --seconds "$TMP/seconds.tsv"
eq "$RC" 0 "all passes when every kind passes"
eq "$(kinds)" "go npm shell " "it runs go, then npm, then the runner"
eq "$(printf '%s\n' "$CALLS" | grep '^go ' | sed 's/ |.*//')" "go test ./..." "go runs go test ./..."
has "$(printf '%s\n' "$CALLS" | grep '^go ')" "cwd=$REPO " "…from the root"
npm_calls="$(printf '%s\n' "$CALLS" | grep '^npm ' | sed 's/ |.*//')"
eq "$(printf '%s\n' "$npm_calls" | head -3 | tr '\n' ';')" "npm ci;npm run typecheck;npm test;" "npm installs, typechecks and tests"
build_call="$(printf '%s\n' "$npm_calls" | sed -n 4p)"
case "$build_call" in
  "npm run build -- --outDir "*"/test-web."*"/dist --emptyOutDir") ok "…then builds into a directory of its own" ;;
  *) bad "…then builds into a directory of its own" "got '$build_call'" ;;
esac
hasnt "$build_call" "$REPO" "…outside the tree"
has "$(printf '%s\n' "$CALLS" | grep '^npm ci')" "cwd=$REPO/services/helm/web " "npm runs in services/helm/web"
eq "$(printf '%s\n' "$CALLS" | grep '^shell ' | sed 's/ |.*//')" "shell -j 3 --seconds $TMP/seconds.tsv" \
  "the runner gets the options given and nothing else"
for k in go npm; do
  line="$(printf '%s\n' "$CALLS" | grep "^$k " | head -1)"
  has "$line" "vars=, " "$k sees none of the caller's GC_* or BEADS_* variables"
  has "$line" "gc=$REPO/tools/test-floor/gc" "…and finds the test floor's gc first on PATH"
done
line="$(printf '%s\n' "$CALLS" | grep '^shell ')"
for v in BEADS_DIR GC_BIN GC_CITY_PATH; do
  has "$line" ",$v," "the runner gets the caller's $v, to hand on or clear itself"
done
has "$OUT" "test: go pass" "the end has a pass line for go"
has "$OUT" "test: web pass" "…for web"
has "$OUT" "test: shell pass" "…and for shell"
eq "$(git -C "$REPO" status --porcelain)" "" "the run changes no tracked file and leaves nothing git does not ignore"

echo "── a kind that fails ──"
STUB_GO_RC=1 run all
eq "$RC" 1 "a go test that fails fails the run"
eq "$(kinds)" "go npm shell " "…and the web checks and the shell suites still run"
has "$OUT" "test: go FAIL" "…and the end names go"
has "$OUT" "test: web pass" "…beside the kinds that passed"
STUB_SHELL_RC=1 run all
eq "$RC" 1 "a shell suite that fails fails the run"
has "$OUT" "test: shell FAIL" "…and the end names shell"
STUB_NPM_FAIL='test' run all
eq "$RC" 1 "a web test that fails fails the run"
hasnt "$CALLS" "npm run build" "…and the web checks after it do not run"
eq "$(kinds)" "go npm shell " "…while the shell suites still do"
has "$OUT" "test: web FAIL" "…and the end names web"

echo "── a build that does not match dist/ ──"
STUB_BUILD="$BUILT_CHANGED" run all
eq "$RC" 1 "a build whose file differs from dist/ fails the run"
has "$OUT" "assets/index.js" "…naming the file"
has "$OUT" "run npm run build there and commit dist/" "…and saying how to fix it"
has "$OUT" "test: web FAIL" "…as a web failure"
eq "$(git -C "$REPO" status --porcelain)" "" "…with no tracked file changed"
eq "$(cat "$REPO/services/helm/web/dist/assets/index.js")" "console.log(1)" "…dist/ among them"
STUB_BUILD="$BUILT_EXTRA" run all
eq "$RC" 1 "a build with a file dist/ lacks fails the run"
has "$OUT" "more.js" "…naming the file"

echo "── affected: the change since BASE ──"
gitc checkout -q -b docs base
printf '# notes, changed\n' > "$REPO/docs/notes.md"
gitc commit -q -am "change a doc"
run affected base -j 2
eq "$RC" 0 "affected passes when every kind it runs passes"
eq "$(kinds)" "go shell " "a change outside services/helm runs go and the runner, and no web check"
eq "$(printf '%s\n' "$CALLS" | grep '^shell ' | sed 's/ |.*//')" "shell -j 2 --affected base" "the runner gets the options, then --affected BASE"
hasnt "$OUT" "test: web" "…and the end has no web line"
gitc checkout -q -b web base
printf '<html>board, changed</html>\n' > "$REPO/services/helm/web/dist/index.html"
gitc commit -q -am "change the board"
mkdir -p "$TMP/built-web"; cp -R "$REPO/services/helm/web/dist"/. "$TMP/built-web"/
STUB_BUILD="$TMP/built-web" run affected base
eq "$(kinds)" "go npm shell " "a change under services/helm/web runs the web checks too"
eq "$RC" 0 "…and passes when they do"
gitc checkout -q -b read base
printf '{"rows":[{"id":"tk-1"}]}\n' > "$REPO/services/helm/internal/rigboard/testdata/gc-toolkit.board.json"
gitc commit -q -am "change the read's golden board"
run affected base
eq "$(kinds)" "go npm shell " "a change elsewhere under services/helm, such as the golden board the app's tests render, runs them too"
eq "$RC" 0 "…and passes when they do"
# git quotes a name with a non-ASCII character when core.quotePath is on, its
# default, and a name with a tab always.
gitc config core.quotePath true
gitc checkout -q -b accent base
printf 'export const x = 1\n' > "$REPO/services/helm/web/caf"$'\xc3\xa9'".ts"
gitc add -A
gitc commit -q -m "add a file whose name holds a non-ASCII character"
run affected base
eq "$(kinds)" "go npm shell " "a change to a file under services/helm whose name holds a non-ASCII character runs the web checks"
gitc checkout -q -b tab base
printf 'export const y = 1\n' > "$REPO/services/helm/web/a"$'\t'"b.ts"
gitc add -A
gitc commit -q -m "add a file whose name holds a tab"
run affected base
eq "$(kinds)" "go npm shell " "…and so does one whose name holds a tab"
gitc checkout -q -b same base
run affected base
eq "$RC" 0 "a change that names no file exits 0"
eq "$OUT" "test: base...HEAD changes no file — nothing to run" "…saying so in one line"
eq "$CALLS" "" "…and runs nothing"

echo "── usage ──"
for args in "" "everything" "affected" "affected --list" "affected no-such-ref"; do
  # shellcheck disable=SC2086  # each case's words are the arguments
  run $args
  eq "$RC" 2 "'test.sh $args' is a usage error"
  eq "$CALLS" "" "…that runs nothing"
done
run affected no-such-ref
has "$OUT" "cannot read the change from no-such-ref to HEAD" "a BASE git cannot read is named"
mv "$REPO/tools/test-floor" "$TMP/floor-aside"
run all
eq "$RC" 2 "a tree without the test floor is refused"
has "$OUT" "no test floor" "…saying so"
eq "$CALLS" "" "…and runs nothing"
mv "$TMP/floor-aside" "$REPO/tools/test-floor"

printf '\ntest: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
