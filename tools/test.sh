#!/usr/bin/env bash
# test.sh — the repository's two test commands, which the Makefile at the root
# names: `make test` runs `test.sh all`, and `make test-affected` runs
# `test.sh affected <base>`.
#
#   test.sh all [RUN-TESTS-OPTION ...]
#   test.sh affected BASE [RUN-TESTS-OPTION ...]
#
# all runs every test in the repository, of three kinds:
#   - go: every Go package's tests, `go test ./...` from the root;
#   - web: the board web app's checks in services/helm/web, after `npm ci`:
#     its typecheck, its tests, and its build, whose output must match the
#     committed dist/ file for file;
#   - shell: every *.test.sh, through tools/run-tests.sh.
#
# affected runs the tests the change HEAD's commits make since BASE can affect,
# BASE being a ref such as origin/main. It reads the change as
# tools/run-tests.sh --affected does, and runs:
#   - go: every Go package's tests, as all runs them, since a Go test's reach
#     is Go's own command over the module to decide;
#   - web: the same checks, when the change touches services/helm, the board
#     the app is the page of. The app's tests render the document helm's read
#     builds, its golden in internal/rigboard/testdata, so a change to the read
#     can fail them with no change to the app;
#   - shell: the suites `tools/run-tests.sh --affected BASE` selects.
# A change that names no file runs nothing.
#
# A RUN-TESTS-OPTION goes to tools/run-tests.sh, such as CI's -j and --seconds.
#
# Each kind runs whether or not the one before it passed, and the run ends with
# one line for each kind it ran. go and web run as run-tests.sh runs a suite:
# with no GC_* or BEADS_* variable of the caller's, and with the test floor,
# tools/test-floor, at the front of PATH. A city session's environment names
# its live city and the gc that reaches it, so a test that reached for gc, bd
# or gh there would reach that city, and the floor refuses the call instead.
#
# The web build writes to a directory of its own, which is compared with dist/,
# so a run changes no tracked file. npm ci rewrites services/helm/web's
# node_modules, which git ignores.
#
# exit: 0 every kind it ran passed · 1 a kind failed · 2 usage, a BASE git
# cannot read, or a tree without the test floor

set -uo pipefail

PROG="test"
usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$PROG: not inside a git repository ($HERE)" >&2; exit 2; }

MODE="${1:-}"
[ "$#" -eq 0 ] || shift
case "$MODE" in
  all) ;;
  affected)
    BASE="${1:-}"
    case "$BASE" in
      '') echo "$PROG: affected needs a base, such as origin/main" >&2; exit 2 ;;
      -*) echo "$PROG: affected needs a base, such as origin/main, not the option '$BASE'" >&2; exit 2 ;;
    esac
    shift ;;
  -h|--help) usage; exit 0 ;;
  '') echo "$PROG: needs a mode, all or affected" >&2; exit 2 ;;
  *) echo "$PROG: the mode is all or affected, not '$MODE'" >&2; exit 2 ;;
esac

FLOOR="$ROOT/tools/test-floor"
[ -x "$FLOOR/gc" ] || { echo "$PROG: no test floor at $FLOOR; not running" >&2; exit 2; }

WEB=1
if [ "$MODE" = affected ]; then
  # git writes the names NUL-separated, as for tools/run-tests.sh, so a name git
  # would quote, such as one with a non-ASCII character or a tab, arrives whole.
  change_file="$(mktemp "${TMPDIR:-/tmp}/test-change.XXXXXX")" || {
    echo "$PROG: mktemp failed" >&2; exit 2; }
  if ! git -C "$ROOT" diff --no-color --name-only --no-renames -z "${BASE}...HEAD" -- >"$change_file"; then
    rm -f "$change_file"
    echo "$PROG: cannot read the change from $BASE to HEAD (git diff ${BASE}...HEAD failed)" >&2
    exit 2
  fi
  changed=0 WEB=0
  while IFS= read -r -d '' path; do
    changed=1
    case "$path" in services/helm/*) WEB=1 ;; esac
  done <"$change_file"
  rm -f "$change_file"
  if [ "$changed" -eq 0 ]; then
    echo "$PROG: ${BASE}...HEAD changes no file — nothing to run"
    exit 0
  fi
fi

# hermetic <command>... — runs the command as the header says go and web run.
hermetic() {
  (
    unset "${!GC_@}" "${!BEADS_@}"
    export PATH="$FLOOR:$PATH"
    "$@"
  )
}

go_tests() {
  cd "$ROOT" && go test ./...
}

web_checks() {
  local out rc=0
  out="$(mktemp -d "${TMPDIR:-/tmp}/test-web.XXXXXX")" || { echo "$PROG: mktemp failed" >&2; return 1; }
  (
    cd "$ROOT/services/helm/web" &&
      npm ci &&
      npm run typecheck &&
      npm test &&
      npm run build -- --outDir "$out/dist" --emptyOutDir &&
      { diff -r "$out/dist" dist || { echo "$PROG: the build of services/helm/web differs from its committed dist/ above; run npm run build there and commit dist/" >&2; false; }; }
  ) || rc=$?
  rm -rf -- "$out"
  return "$rc"
}

declare -a RAN=() FAILED=()
kind() { # <name> <command>...
  local name="$1"
  shift
  printf '\n%s: %s\n' "$PROG" "$name"
  RAN+=("$name")
  "$@" || FAILED+=("$name")
}

kind go hermetic go_tests
if [ "$WEB" -eq 1 ]; then
  kind web hermetic web_checks
fi
if [ "$MODE" = affected ]; then
  kind shell "$ROOT/tools/run-tests.sh" "$@" --affected "$BASE"
else
  kind shell "$ROOT/tools/run-tests.sh" "$@"
fi

printf '\n'
for name in "${RAN[@]}"; do
  case " ${FAILED[*]} " in
    *" $name "*) printf '%s: %s FAIL\n' "$PROG" "$name" ;;
    *) printf '%s: %s pass\n' "$PROG" "$name" ;;
  esac
done
[ "${#FAILED[@]}" -eq 0 ]
