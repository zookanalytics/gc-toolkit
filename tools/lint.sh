#!/usr/bin/env bash
# lint.sh — the rig's one lint entry point: shell static analysis, go vet and
# gofmt.
#
# Wired as the refinery's lint_command, it runs on every merge. It runs three
# linters, each at the scope a merge gate can enforce given the tree's current
# finding-debt:
#
#   SHELL — shellcheck, through assets/scripts/shellcheck-run.sh, the one
#   fail-closed runner (host shellcheck at warning severity; exit 3 when none is
#   on PATH). Scoped to the shell files passed on argv, so the refinery feeds it
#   the merge's changed files — `lint.sh $(git diff --name-only origin/main...HEAD)`
#   — and the gate judges what a change touches. Whole-tree is deliberately NOT
#   the gate scope: main carries pre-existing warning-level findings, so a gate
#   that failed on an untouched file would block every unrelated merge. Scan the
#   whole tree by hand by passing the files: `lint.sh $(git ls-files '*.sh')`.
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
# Fail-closed throughout: a linter that cannot run — no shellcheck, no go, no
# gofmt — is a finding, never a silent pass, the same contract shellcheck-run.sh
# enforces.
#
# Usage: lint.sh [FILE ...]
#   FILE ...  files to lint; the shell scripts among them — a .sh suffix or a
#             shell shebang (sh, bash, dash, ksh) — are shellchecked, and the
#             rest drop out. With no shell file given none is linted, and go vet
#             and gofmt still run.
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

fail=0
summary=()

# ── Shell: shellcheck over the given shell files ─────────────────────────────
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

shell_files=()
for f in "$@"; do
  is_shell_file "$f" && shell_files+=("$f")
done

if [ "${#shell_files[@]}" -eq 0 ]; then
  summary+=("shell: no shell files given — skipped")
else
  if "$SHELLCHECK_RUN" "${shell_files[@]}"; then
    summary+=("shell: ${#shell_files[@]} file(s) clean")
  else
    rc=$?
    fail=1
    if [ "$rc" -eq 3 ]; then
      summary+=("shell: FAIL — shellcheck could not run (none on PATH); fail-closed, treated as a finding")
    else
      summary+=("shell: FAIL — shellcheck findings (shellcheck-run.sh exit $rc)")
    fi
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

# ── Report ───────────────────────────────────────────────────────────────────
echo "$PROG: summary"
for line in ${summary[@]+"${summary[@]}"}; do echo "  $line"; done

if [ "$fail" -ne 0 ]; then
  echo "$PROG: FAIL" >&2
  exit 1
fi
echo "$PROG: OK"
exit 0
