#!/usr/bin/env bash
# lint.sh — the rig's one lint entry point: shell static analysis, step text,
# go vet and gofmt, and the list of the warrants a branch touches.
#
# Wired as the rig's lint_command, it runs at the polecat's self-review and on
# every merge. It runs these linters, each at the scope a merge gate can enforce
# given the tree's current finding-debt:
#
#   SHELL — shellcheck, through assets/scripts/shellcheck-run.sh, the one
#   fail-closed runner (host shellcheck at warning severity; exit 3 when none is
#   on PATH), over every tracked shell file, whatever files lint.sh is given.
#   Whole-tree for the reason gofmt is: the tree is shellcheck-clean, so checking
#   every file on every merge is zero-noise. It also keeps a finding from waiting
#   in a file no change names until an unrelated merge edits that file and fails
#   on a line it did not write. The files are split across one runner call per
#   core, so the run lasts about as long as the call that holds the slowest
#   files.
#
#   STEP TEXT — tools/lint-step-text.sh over the files passed on argv, which
#   checks the formulas among them for a procedure the change adds to step text
#   (docs/pack-authoring.md, "Step text calls a tested script"). It judges what
#   the change adds since the merge base of origin/main and HEAD, the change the
#   refinery's `git diff --name-only origin/main...HEAD` names, so step text
#   that predates the rule passes until its own rewrite.
#
#   GO — `go vet ./...` in every Go module (each go.mod tree). Whole-module, not
#   argv-scoped: vet is a per-package analysis, it is clean across the tree
#   today, so running it everywhere on every merge is zero-noise and still
#   catches a regression in a package the diff did not name. Vet runs cgo, so
#   it needs the C headers a cgo package includes, and services/helm reaches ICU
#   through one, Dolt's go-icu-regex. Each vet is handed the cgo flags
#   assets/scripts/icu4c-cgo.sh works out, which on macOS point at Homebrew's
#   keg-only icu4c, the same flags the helm-svc build uses.
#
#   GOFMT — `gofmt -l` over every tracked Go file. Whole-tree for the reason vet
#   is: the tree is gofmt-clean today, so checking every file on every merge is
#   zero-noise. It also catches drift in a file no diff named, such as a
#   toolchain whose gofmt formats differently. gofmt lists a file it would
#   rewrite and still exits 0, so the listing is the finding. lint.sh only
#   lists; it never rewrites a file.
#
#   WARRANTS — tools/warrants-touched.sh prints the docs/warrants.md entries the
#   branch touches, with their Verified dates, so the author re-verifies them
#   before the arch review reads them. It is the one part that judges nothing: a
#   touched warrant fails no lint, because the arch review judges the
#   re-verification. It reads the branch from git, so it takes no FILE.
#
# Fail-closed throughout: a linter that cannot run — no shellcheck, no go, no
# gofmt — is a finding, never a silent pass, the same contract shellcheck-run.sh
# enforces.
#
# Usage: lint.sh [FILE ...]
#   FILE ...  the files a change names; the formulas among them have their step
#             text checked, and the rest drop out. With no formula given step
#             text is not linted. The shell lint, go vet and gofmt cover the
#             tracked tree and the warrant list reads the branch, whatever files
#             are given.
#
# Exit: 0 everything clean; 1 a finding or a linter that could not run; 2 a usage
#       or repository-enumeration error (lint.sh itself could not operate).
set -uo pipefail

PROG=lint

# ── The icu4c cgo flags ──────────────────────────────────────────────────────
# Sourced from lint.sh's own checkout, before the cd below can change what a
# relative invocation path names. Its absence is a packaging error, as the
# shell-lint runner's is below.
# shellcheck source=../assets/scripts/icu4c-cgo.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../assets/scripts/icu4c-cgo.sh" \
  || { echo "$PROG: cannot source assets/scripts/icu4c-cgo.sh from lint.sh's checkout" >&2; exit 2; }

# ── Repository root ──────────────────────────────────────────────────────────
# Both linters are repo-relative: shell paths resolve from the root and go vet
# walks each module under it. A tree we cannot locate is a structural error (2),
# never an empty clean pass.
if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "$PROG: not inside a git repository" >&2
  exit 2
fi
cd "$ROOT" || { echo "$PROG: cannot enter repo root $ROOT" >&2; exit 2; }

# ── The one shell-lint runner ────────────────────────────────────────────────
# Its absence is a packaging error, not a lint finding — fail with the structural
# code so it is never mistaken for a clean or merely-findings run.
SHELLCHECK_RUN="$ROOT/assets/scripts/shellcheck-run.sh"
if [ ! -x "$SHELLCHECK_RUN" ]; then
  echo "$PROG: shell-lint runner missing or not executable: $SHELLCHECK_RUN" >&2
  exit 2
fi
STEP_TEXT_LINT="$ROOT/tools/lint-step-text.sh"
if [ ! -x "$STEP_TEXT_LINT" ]; then
  echo "$PROG: step-text lint missing or not executable: $STEP_TEXT_LINT" >&2
  exit 2
fi
WARRANTS_TOUCHED="$ROOT/tools/warrants-touched.sh"
if [ ! -x "$WARRANTS_TOUCHED" ]; then
  echo "$PROG: warrant list missing or not executable: $WARRANTS_TOUCHED" >&2
  exit 2
fi

fail=0
summary=()

# ── Shell: shellcheck over every tracked shell file ──────────────────────────
# A file is shell if its path ends in .sh, or its shebang names one of the
# shells the linter handles (sh, bash, dash, ksh, including the `env <shell>`
# form). The suffix alone misses the repo's extensionless scripts —
# assets/hooks/pre-commit is `#!/usr/bin/env bash` — and skipping one hands the
# refinery a clean shell lint that shellcheck-run.sh would have run on it, the
# gap the fail-closed contract forbids.
is_shell_file() {
  local f=$1 line body interp rest shell
  [ -f "$f" ] || return 1
  case "$f" in
    *.sh) return 0 ;;
  esac
  IFS= read -r line < "$f" 2>/dev/null || return 1
  case "$line" in
    '#!'*) ;;
    *) return 1 ;;
  esac
  # Interpreter is the first word after #!; for `env <shell>` it is the second.
  body=${line#"#!"}
  read -r interp rest <<<"$body"
  case "$interp" in
    */env|env) shell=${rest%% *} ;;
    *) shell=${interp##*/} ;;
  esac
  case "$shell" in
    sh|bash|dash|ksh) return 0 ;;
  esac
  return 1
}

# The shell lint keeps its files in a directory of its own, which every exit
# removes: the tracked listing, and the output of each runner call.
if ! shell_tmp="$(mktemp -d "${TMPDIR:-/tmp}/lint-shell.XXXXXX")"; then
  echo "$PROG: cannot make a directory for the shell lint's files" >&2
  exit 2
fi
trap 'rm -rf "$shell_tmp"' EXIT

# The listing is written to a file and read back from it, and both steps are
# checked. A listing that failed, or one that could not be read, would yield
# an empty list, which reads like a tree with no shell in it and skips the
# check. A `<<<` here-string would hide the failed read (docs/review-correctness.md,
# Loop input). The listing ends each path with a NUL and names it as it is:
# git's default listing quotes a path that holds a double quote, a backslash or
# a control character, and no file is found under the quoted name, so the file
# would drop out of the lint unchecked.
if ! git ls-files -z >"$shell_tmp/listing"; then
  echo "$PROG: cannot enumerate tracked files under $ROOT" >&2
  exit 2
fi
shell_files=()
while IFS= read -r -d '' f; do
  if [ -n "$f" ] && is_shell_file "$f"; then shell_files+=("$f"); fi
done <"$shell_tmp/listing" || {
  echo "$PROG: cannot read the listing of tracked files" >&2
  exit 2
}

# cores — the host's core count, as tools/run-tests.sh reads it: the first that
# nproc, getconf or sysctl reports, since stock macOS has no nproc. A count no
# tool reports leaves one.
cores() {
  local n
  n="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$(( 10#$n ))
  [ "$n" -ge 1 ] || n=1
  printf '%s\n' "$n"
}

if [ "${#shell_files[@]}" -eq 0 ]; then
  summary+=("shell: no tracked shell files — skipped")
else
  # The files are dealt in turn across one runner call per core, and the calls
  # run at once. Each call's output waits in a file until that call has ended,
  # and only a failing call's is printed, so the findings of one call never
  # interleave with another's.
  calls="$(cores)"
  [ "$calls" -le "${#shell_files[@]}" ] || calls=${#shell_files[@]}
  pids=()
  for ((c = 0; c < calls; c++)); do
    share=()
    for ((i = c; i < ${#shell_files[@]}; i += calls)); do share+=("${shell_files[i]}"); done
    "$SHELLCHECK_RUN" "${share[@]}" >"$shell_tmp/$c.out" 2>"$shell_tmp/$c.err" &
    pids+=("$!")
  done
  # The summary names the first failing call's exit. An exit 3 says the runner
  # found no shellcheck on PATH, which every call shares, so its message prints
  # once.
  shell_rc=0; no_runner=0
  for ((c = 0; c < calls; c++)); do
    rc=0; wait "${pids[c]}" || rc=$?
    [ "$rc" -ne 0 ] || continue
    if [ "$rc" -eq 3 ]; then
      if [ "$no_runner" -eq 0 ] && [ -s "$shell_tmp/$c.err" ]; then
        printf '%s\n' "$(<"$shell_tmp/$c.err")" >&2
      fi
      no_runner=1
      continue
    fi
    [ ! -s "$shell_tmp/$c.out" ] || printf '%s\n' "$(<"$shell_tmp/$c.out")"
    [ ! -s "$shell_tmp/$c.err" ] || printf '%s\n' "$(<"$shell_tmp/$c.err")" >&2
    [ "$shell_rc" -ne 0 ] || shell_rc=$rc
  done
  if [ "$no_runner" -eq 1 ]; then
    fail=1
    summary+=("shell: FAIL — shellcheck could not run (none on PATH); fail-closed, treated as a finding")
  elif [ "$shell_rc" -ne 0 ]; then
    fail=1
    summary+=("shell: FAIL — shellcheck findings (shellcheck-run.sh exit $shell_rc)")
  else
    summary+=("shell: ${#shell_files[@]} file(s) clean")
  fi
fi

# ── Step text: no procedure added to a formula step ─────────────────────────
# The lint picks the formulas out of the files itself. Its exit 2 says it could
# not read the change, which fails closed like a linter that could not run.
if "$STEP_TEXT_LINT" "$@"; then
  summary+=("step text: clean")
else
  rc=$?
  fail=1
  if [ "$rc" -eq 1 ]; then
    summary+=("step text: FAIL — a formula change adds a procedure to step text")
  else
    summary+=("step text: FAIL — lint-step-text.sh could not run (exit $rc); fail-closed, treated as a finding")
  fi
fi

# ── Go: go vet ./... in every module ─────────────────────────────────────────
# A go.mod basename test keeps paths like `cargo.mod` out of the module list,
# which the `*go.mod` pathspec would otherwise match.
modules=()
while IFS= read -r gomod; do
  [ -n "$gomod" ] || continue
  [ "$(basename "$gomod")" = go.mod ] || continue
  modules+=("$(dirname "$gomod")")
done < <(git ls-files '*go.mod')

if [ "${#modules[@]}" -eq 0 ]; then
  summary+=("go: no go.mod modules found — skipped")
elif ! command -v go >/dev/null 2>&1; then
  # Fail-closed, the same contract as the shell half: a vet that could not run is
  # a finding, not a pass.
  fail=1
  summary+=("go: FAIL — 'go' not on PATH; ${#modules[@]} module(s) unvetted; fail-closed, treated as a finding")
else
  # Worked out once, and only when vet is about to run, so a tree with nothing
  # to vet never asks brew.
  icu4c_cgo_flags "$PROG"
  for m in "${modules[@]}"; do
    if ( cd "$ROOT/$m" && CGO_CPPFLAGS="$ICU4C_CGO_CPPFLAGS" CGO_LDFLAGS="$ICU4C_CGO_LDFLAGS" go vet ./... ); then
      summary+=("go: $m vet clean")
    else
      rc=$?
      fail=1
      summary+=("go: FAIL — $m go vet exit $rc")
    fi
  done
fi

# ── Gofmt: gofmt -l over every tracked Go file ───────────────────────────────
# The listing is checked before it is read. A git ls-files that failed would
# yield an empty list, which reads exactly like a tree with no Go in it and
# skips the check. core.quotePath=false keeps a non-ASCII path unquoted so gofmt
# can open it; a path git still quotes cannot be opened, and gofmt fails on it
# loudly rather than the file dropping out unchecked.
if ! go_listing="$(git -c core.quotePath=false ls-files -- '*.go')"; then
  echo "$PROG: cannot enumerate tracked Go files under $ROOT" >&2
  exit 2
fi
go_files=()
while IFS= read -r f; do
  [ -n "$f" ] && go_files+=("$f")
done <<<"$go_listing"

if [ "${#go_files[@]}" -eq 0 ]; then
  summary+=("gofmt: no tracked Go files — skipped")
elif ! command -v gofmt >/dev/null 2>&1; then
  fail=1
  summary+=("gofmt: FAIL — 'gofmt' not on PATH; ${#go_files[@]} Go file(s) unchecked; fail-closed, treated as a finding")
else
  # A non-zero exit means gofmt could not read or parse a file. That fails the
  # check on its own, whatever the listing holds.
  if unformatted="$(gofmt -l "${go_files[@]}")"; then rc=0; else rc=$?; fi
  listed=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    listed=$((listed + 1))
    summary+=("gofmt: FAIL — $f is not gofmt-clean; gofmt -d $f shows the rewrite")
  done <<<"$unformatted"
  if [ "$rc" -ne 0 ]; then
    fail=1
    summary+=("gofmt: FAIL — gofmt exit $rc; a Go file could not be read or parsed")
  fi
  if [ "$listed" -gt 0 ]; then
    fail=1
  elif [ "$rc" -eq 0 ]; then
    summary+=("gofmt: ${#go_files[@]} Go file(s) clean")
  fi
fi

# ── Warrants: the entries this branch touches ───────────────────────────────
# Its exit 1 is a list for the author, which fails nothing. Its exit 2 says it
# could not read the page or the change, which fails closed like a linter that
# could not run.
if "$WARRANTS_TOUCHED"; then
  summary+=("warrants: none touched")
else
  rc=$?
  if [ "$rc" -eq 1 ]; then
    summary+=("warrants: touched, listed above")
  else
    fail=1
    summary+=("warrants: FAIL — warrants-touched.sh could not run (exit $rc); fail-closed, treated as a finding")
  fi
fi

# ── Report ───────────────────────────────────────────────────────────────────
echo "$PROG: summary"
for line in ${summary[@]+"${summary[@]}"}; do echo "  $line"; done

if [ "$fail" -ne 0 ]; then
  echo "$PROG: FAIL" >&2
  exit 1
fi
echo "$PROG: OK"
exit 0
