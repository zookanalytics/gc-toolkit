#!/usr/bin/env bash
# Hermetic test for lint.sh — the rig's shell, go vet and gofmt lint entry point.
#
# The defects it guards against: a linter that could not run reads as a clean
# pass (fail-closed violated), shell findings get swallowed into 0, a go
# module is silently skipped, or a Go file gofmt would rewrite passes.
#
# Hermetic: a throwaway git repo holds a stub shellcheck-run.sh whose exit code
# the test sets and a tracked go.mod, and lint.sh runs with PATH pointing at a
# stub bin — so whether shellcheck, go and gofmt "ran" and what they returned
# is the test's to decide. No real shellcheck or go toolchain is required.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/lint.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lint-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -f "$SUT" ] && ok "SUT exists at $SUT" || bad "SUT missing: $SUT"
bash -n "$SUT" && ok "lint.sh is syntactically valid bash" || bad "lint.sh failed bash -n"
[ -x "$SUT" ] && ok "lint.sh is executable" || bad "lint.sh is not executable"

# --- A throwaway repo with a stub wrapper and a tracked module. --------------
REPO="$TMP/repo"
mkdir -p "$REPO/assets/scripts" "$REPO/services/foo"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
git -C "$REPO" config commit.gpgsign false
printf 'module foo\n\ngo 1.27\n' > "$REPO/services/foo/go.mod"
printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/subject.sh"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init

# Stub wrapper (assets/scripts/shellcheck-run.sh): records that it ran, exits the
# code the test asks for. lint.sh resolves it from the repo root, so it stands in
# for the real runner without a shellcheck binary.
WRAP="$REPO/assets/scripts/shellcheck-run.sh"
make_wrapper() {  # $1 = exit code
  cat > "$WRAP" <<EOF
#!/bin/sh
echo "stub-shellcheck-run ran: \$*" >> "$TMP/wrapper.log"
exit $1
EOF
  chmod +x "$WRAP"
}

# --- Stub bin: only the externals lint.sh reaches for. -----------------------
# lint.sh needs git, basename and dirname; go and gofmt are stubbed so their
# presence and exit codes are the test's to set. Everything else lint.sh uses is
# a builtin.
STUB="$TMP/bin"; mkdir -p "$STUB"
for t in git basename dirname; do ln -s "$(command -v "$t")" "$STUB/$t"; done

make_go() {  # $1 = exit code
  cat > "$STUB/go" <<EOF
#!/bin/sh
echo "stub-go ran: \$*" >> "$TMP/go.log"
exit $1
EOF
  chmod +x "$STUB/go"
}

# Invoke bash by absolute path: with PATH=$STUB the command word itself resolves
# against the stub, where there is no bash.
BASH_BIN="${BASH:-$(command -v bash)}"
run_sut() {  # args = files; runs in $REPO with the stubbed PATH
  if ( cd "$REPO" && PATH="$STUB" "$BASH_BIN" "$SUT" "$@" ) >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
}

# --- A: shell clean + go clean -> exit 0. ------------------------------------
make_wrapper 0; make_go 0
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "all clean: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "all clean: expected 0, got $rc"; }

# --- B: shell findings (wrapper exit 1) -> exit 1, not swallowed. ------------
make_wrapper 1; make_go 0
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "shell findings: exit 1" || bad "shell findings: expected 1, got $rc"

# --- C: no shellcheck (wrapper exit 3) -> exit 1, fail-closed. ---------------
make_wrapper 3; make_go 0
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "shell no-runner: exit 1 (fail-closed)" || bad "shell no-runner: expected 1, got $rc"
grep -qi 'could not run' "$TMP/out" && ok "shell no-runner: report names the fail-closed" \
  || bad "shell no-runner: report is silent about the fail-closed"

# --- D: go vet findings (stub go exit 1) -> exit 1. --------------------------
make_wrapper 0; make_go 1
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "go findings: exit 1" || bad "go findings: expected 1, got $rc"

# --- E: no go on PATH -> exit 1, fail-closed. --------------------------------
make_wrapper 0; rm -f "$STUB/go"
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "go missing: exit 1 (fail-closed)" || bad "go missing: expected 1, got $rc"
grep -qi 'not on PATH' "$TMP/out" && ok "go missing: report names the missing runner" \
  || bad "go missing: report is silent about the missing go"

# --- F: no shell files given -> shell skipped, go still runs, exit 0. --------
make_wrapper 0; make_go 0; : > "$TMP/go.log"
run_sut
[ "$rc" -eq 0 ] && ok "no files: shell skipped, go clean, exit 0" || bad "no files: expected 0, got $rc"
grep -q 'stub-go ran' "$TMP/go.log" && ok "no files: go vet still ran" || bad "no files: go vet did not run"

# --- G: wrapper missing -> structural error (exit 2). ------------------------
make_go 0; rm -f "$WRAP"
run_sut subject.sh
[ "$rc" -eq 2 ] && ok "wrapper missing: structural error (exit 2)" || bad "wrapper missing: expected 2, got $rc"

# --- H: not a git repo -> structural error (exit 2). -------------------------
if ( cd "$TMP" && PATH="$STUB" "$BASH_BIN" "$SUT" ) >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
[ "$rc" -eq 2 ] && ok "not a repo: structural error (exit 2)" || bad "not a repo: expected 2, got $rc"

# --- I: an extensionless shell script (shell shebang) is recognized. ---------
# A real shell script need not end in .sh — assets/hooks/pre-commit is the live
# example, `#!/usr/bin/env bash`. lint.sh must hand it to shellcheck-run.sh, or
# the refinery reports a clean shell lint on a hook that was never checked.
make_wrapper 0; make_go 0; : > "$TMP/wrapper.log"
printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/hook-noext"
run_sut hook-noext
[ "$rc" -eq 0 ] && ok "shebang shell file: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "shebang shell file: expected 0, got $rc"; }
grep -q 'hook-noext' "$TMP/wrapper.log" \
  && ok "shebang shell file: shellcheck-run.sh received it" \
  || bad "shebang shell file: dropped — shellcheck-run.sh never saw it"
grep -qi 'no shell files given' "$TMP/out" \
  && bad "shebang shell file: reported as skipped" \
  || ok "shebang shell file: not reported as skipped"

# --- J: an extensionless non-shell script is still dropped. ------------------
# The predicate admits only shells shellcheck can lint; a python shebang handed
# to shellcheck would turn a clean run into a spurious finding, so it drops out.
make_wrapper 0; make_go 0; : > "$TMP/wrapper.log"
printf '#!/usr/bin/env python3\nprint("hi")\n' > "$REPO/script-noext"
run_sut script-noext
[ "$rc" -eq 0 ] && ok "non-shell shebang: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "non-shell shebang: expected 0, got $rc"; }
grep -q 'script-noext' "$TMP/wrapper.log" \
  && bad "non-shell shebang: wrongly linted as shell" \
  || ok "non-shell shebang: dropped, not linted"
grep -qi 'no shell files given' "$TMP/out" \
  && ok "non-shell shebang: reported skipped" \
  || bad "non-shell shebang: not reported skipped"

# --- Gofmt: a tracked Go file, judged by a stub gofmt. -----------------------
# Real gofmt -l prints each file it would rewrite and exits 0, and exits 2 when
# it cannot read or parse a file. The stub logs its argv, prints the files the
# test names, and exits the code the test sets.
printf 'package foo\n' > "$REPO/services/foo/foo.go"
git -C "$REPO" add services/foo/foo.go
git -C "$REPO" commit -qm 'add a Go file'

make_gofmt() {  # $1 = exit code; further args = files to list as not gofmt-clean
  local code=$1 f; shift
  {
    echo '#!/bin/sh'
    echo "echo \"stub-gofmt ran: \$*\" >> \"$TMP/gofmt.log\""
    for f in "$@"; do echo "echo '$f'"; done
    echo "exit $code"
  } > "$STUB/gofmt"
  chmod +x "$STUB/gofmt"
}

# --- K: gofmt clean -> exit 0, over the whole tracked tree, listing only. ----
# lint.sh is handed subject.sh alone, so foo.go reaching gofmt is the whole-tree
# scope. An untracked Go file is not part of the merge and stays out.
make_wrapper 0; make_go 0; make_gofmt 0; : > "$TMP/gofmt.log"
printf 'package foo\n' > "$REPO/services/foo/scratch.go"
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "gofmt clean: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "gofmt clean: expected 0, got $rc"; }
grep -q 'gofmt: 1 Go file(s) clean' "$TMP/out" && ok "gofmt clean: reported clean" \
  || bad "gofmt clean: no clean line in the report"
grep -q '^stub-gofmt ran: -l .*services/foo/foo.go' "$TMP/gofmt.log" \
  && ok "gofmt clean: gofmt -l received a tracked Go file lint.sh was not handed" \
  || bad "gofmt clean: gofmt -l never received services/foo/foo.go"
grep -q -- ' -w' "$TMP/gofmt.log" \
  && bad "gofmt clean: gofmt was asked to rewrite files (-w)" \
  || ok "gofmt clean: gofmt only lists, never rewrites"
grep -q 'scratch.go' "$TMP/gofmt.log" \
  && bad "gofmt clean: an untracked Go file was checked" \
  || ok "gofmt clean: an untracked Go file is out of scope"
rm -f "$REPO/services/foo/scratch.go"

# --- L: gofmt lists a file -> exit 1, and the report names it. ---------------
make_wrapper 0; make_go 0; make_gofmt 0 services/foo/foo.go
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "gofmt drift: exit 1" || bad "gofmt drift: expected 1, got $rc"
grep -q 'services/foo/foo.go is not gofmt-clean' "$TMP/out" \
  && ok "gofmt drift: report names the file" \
  || bad "gofmt drift: report does not name services/foo/foo.go"

# --- M: gofmt cannot parse a file (exit 2, nothing listed) -> exit 1. --------
# The listing is empty, so only the exit code shows a file went unchecked.
make_wrapper 0; make_go 0; make_gofmt 2
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "gofmt error: exit 1, not read as clean" || bad "gofmt error: expected 1, got $rc"
grep -q 'gofmt exit 2' "$TMP/out" && ok "gofmt error: report names the gofmt exit" \
  || bad "gofmt error: report is silent about the gofmt exit"

# --- N: no gofmt on PATH while Go files are tracked -> exit 1, fail-closed. --
make_wrapper 0; make_go 0; rm -f "$STUB/gofmt"
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "gofmt missing: exit 1 (fail-closed)" || bad "gofmt missing: expected 1, got $rc"
grep -q "'gofmt' not on PATH" "$TMP/out" && ok "gofmt missing: report names the missing gofmt" \
  || bad "gofmt missing: report is silent about the missing gofmt"

# --- O: the Go-file listing fails -> structural error (exit 2). --------------
# An empty list from a failed git ls-files reads exactly like a tree with no Go
# in it, which skips gofmt and passes. The git wrapper refuses only that listing
# and hands every other git call to the real binary.
make_wrapper 0; make_go 0; make_gofmt 0
REAL_GIT="$(command -v git)"
rm -f "$STUB/git"
cat > "$STUB/git" <<EOF
#!/bin/sh
case " \$* " in
  *" ls-files "*"*.go"*) echo "stub-git: ls-files refused" >&2; exit 128 ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$STUB/git"
run_sut subject.sh
[ "$rc" -eq 2 ] && ok "Go listing fails: structural error (exit 2)" || bad "Go listing fails: expected 2, got $rc"
grep -q 'cannot enumerate tracked Go files' "$TMP/err" \
  && ok "Go listing fails: error names the failed listing" \
  || bad "Go listing fails: error is silent about the listing"
rm -f "$STUB/git"; ln -s "$REAL_GIT" "$STUB/git"

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
