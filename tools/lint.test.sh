#!/usr/bin/env bash
# Hermetic test for lint.sh — the rig's shell, step text, go vet and gofmt lint
# entry point, which also prints the warrants a branch touches.
#
# The defects it guards against: a linter that could not run reads as a clean
# pass (fail-closed violated), shell or step-text findings get swallowed into 0,
# a tracked shell file goes unlinted because no change names it or because git
# quotes its path, a listing of
# the tracked files that could not be written or read back reads as a tree with
# no shell in it, one call's shell findings are lost among the calls the tree is
# split across, a go module
# is silently skipped, a Go file gofmt would rewrite passes, or go vet on macOS
# is not pointed at the icu4c headers services/helm's cgo needs, or a warrant
# list that could not run reads as nothing touched, or one that ran fails the
# lint or goes unprinted.
#
# Hermetic: a throwaway git repo holds a stub shellcheck-run.sh, a stub
# lint-step-text.sh and a stub warrants-touched.sh whose exit codes the test
# sets, and a tracked go.mod, and lint.sh runs with PATH pointing at a
# stub bin — so whether shellcheck, go and gofmt "ran" and what they returned
# is the test's to decide, and a stub nproc sets how many calls the shell lint
# makes. No real shellcheck or go toolchain is required. The host is stubbed the
# same way: a stub uname names it and a stub brew answers for icu4c, so the
# macOS path runs on any platform.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/lint.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lint-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

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

# Stub step-text lint (tools/lint-step-text.sh): records the files it was handed
# and exits the code the test asks for. lint.sh resolves it from the repo root,
# so it stands in for the real lint, which a lint.sh case has no base to run.
STEP="$REPO/tools/lint-step-text.sh"
make_step_text() {  # $1 = exit code
  mkdir -p "$REPO/tools"
  cat > "$STEP" <<EOF
#!/bin/sh
echo "stub-step-text ran: \$*" >> "$TMP/step.log"
exit $1
EOF
  chmod +x "$STEP"
}
make_step_text 0

# Stub warrant list (tools/warrants-touched.sh): prints a line the test looks for
# and exits the code the test asks for. tools/warrants-touched.test.sh holds the
# real list to its page.
WARRANTS="$REPO/tools/warrants-touched.sh"
make_warrants() {  # $1 = exit code
  mkdir -p "$REPO/tools"
  cat > "$WARRANTS" <<EOF
#!/bin/sh
echo "stub-warrants ran:\$*:"
exit $1
EOF
  chmod +x "$WARRANTS"
}
make_warrants 0

# --- Stub bin: only the externals lint.sh reaches for. -----------------------
# lint.sh needs git, basename, dirname, mktemp and rm; go and gofmt are stubbed
# so their presence and exit codes are the test's to set. The stub nproc prints
# STUB_NPROC, and with none set fails as on a host without nproc, which leaves
# the shell lint one call, since the bin holds no getconf or sysctl. Everything
# else lint.sh uses is a builtin.
STUB="$TMP/bin"; mkdir -p "$STUB"
for t in git basename dirname mktemp rm; do ln -s "$(command -v "$t")" "$STUB/$t"; done
cat > "$STUB/nproc" <<'EOF'
#!/bin/sh
[ -n "${STUB_NPROC:-}" ] || exit 1
echo "$STUB_NPROC"
EOF
chmod +x "$STUB/nproc"

# The stub go records the CGO flags it was handed, one run at a time.
make_go() {  # $1 = exit code
  cat > "$STUB/go" <<EOF
#!/bin/sh
echo "stub-go ran: \$*" >> "$TMP/go.log"
printf 'CGO_CPPFLAGS=%s\nCGO_LDFLAGS=%s\n' "\${CGO_CPPFLAGS:-}" "\${CGO_LDFLAGS:-}" > "$TMP/go-cgo.log"
exit $1
EOF
  chmod +x "$STUB/go"
}

# The host is a fixture too. lint.sh points go vet's cgo at Homebrew's icu4c
# only on macOS, so uname and brew are stubs and every run names its host:
# HOST_OS is what uname prints (Linux when empty), ICU_PREFIX is what
# `brew --prefix icu4c` prints (nothing when empty), and $TMP/brew.log records
# every brew call. CGO_CPPFLAGS_IN and CGO_LDFLAGS_IN are the CGO flags the run
# starts with, so one the caller's shell exports cannot leak into a case.
cat > "$STUB/uname" <<'EOF'
#!/bin/sh
echo "${STUB_HOST_OS:-Linux}"
EOF
cat > "$STUB/brew" <<EOF
#!/bin/sh
echo "\$*" >> "$TMP/brew.log"
if [ "\$*" = "--prefix icu4c" ] && [ -n "\${STUB_ICU_PREFIX:-}" ]; then
  echo "\$STUB_ICU_PREFIX"
  exit 0
fi
exit 1
EOF
chmod +x "$STUB/uname" "$STUB/brew"
HOST_OS=""; ICU_PREFIX=""; CGO_CPPFLAGS_IN=""; CGO_LDFLAGS_IN=""; NPROC=""

# Invoke bash by absolute path: with PATH=$STUB the command word itself resolves
# against the stub, where there is no bash. Each run gets a TMPDIR of its own,
# so a case can see what a run left there.
BASH_BIN="${BASH:-$(command -v bash)}"
LINT_TMP="$TMP/lint-tmp"; mkdir -p "$LINT_TMP"
run_sut() {  # args = files; runs in $REPO with the stubbed PATH and host
  if ( cd "$REPO" && PATH="$STUB" STUB_HOST_OS="$HOST_OS" STUB_ICU_PREFIX="$ICU_PREFIX" \
         STUB_NPROC="$NPROC" TMPDIR="$LINT_TMP" \
         CGO_CPPFLAGS="$CGO_CPPFLAGS_IN" CGO_LDFLAGS="$CGO_LDFLAGS_IN" \
         "$BASH_BIN" "$SUT" "$@" ) >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
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

# --- F: no files given -> the shell lint still covers the tracked tree. -----
# lint.sh lists the tracked shell files itself, so a run handed no file still
# lints subject.sh, and go vet still runs.
make_wrapper 0; make_go 0; : > "$TMP/go.log"; : > "$TMP/wrapper.log"
run_sut
[ "$rc" -eq 0 ] && ok "no files: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "no files: expected 0, got $rc"; }
grep -q 'subject.sh' "$TMP/wrapper.log" \
  && ok "no files: the tracked shell file is still linted" \
  || bad "no files: subject.sh never reached shellcheck-run.sh"
grep -q 'shell: 1 file(s) clean' "$TMP/out" && ok "no files: the shell lint reports it clean" \
  || bad "no files: no clean shell line: $(cat "$TMP/out")"
grep -q 'stub-go ran' "$TMP/go.log" && ok "no files: go vet still ran" || bad "no files: go vet did not run"

# --- F2: the files given do not narrow the shell lint. -----------------------
# Handed only a non-shell file, it still lints every tracked shell file. An
# untracked shell file it is handed is not part of the merge and stays out, as
# an untracked Go file does.
make_wrapper 0; make_go 0; : > "$TMP/wrapper.log"
printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/loose.sh"
run_sut services/foo/go.mod loose.sh
[ "$rc" -eq 0 ] && ok "files given: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "files given: expected 0, got $rc"; }
grep -q 'subject.sh' "$TMP/wrapper.log" \
  && ok "files given: a tracked shell file no change names is linted" \
  || bad "files given: subject.sh never reached shellcheck-run.sh"
grep -q 'loose.sh' "$TMP/wrapper.log" \
  && bad "files given: an untracked shell file was linted" \
  || ok "files given: an untracked shell file is out of scope"
rm -f "$REPO/loose.sh"

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
git -C "$REPO" add hook-noext
git -C "$REPO" commit -qm 'add an extensionless shell script'
run_sut
[ "$rc" -eq 0 ] && ok "shebang shell file: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "shebang shell file: expected 0, got $rc"; }
grep -q 'hook-noext' "$TMP/wrapper.log" \
  && ok "shebang shell file: shellcheck-run.sh received it" \
  || bad "shebang shell file: dropped — shellcheck-run.sh never saw it"
grep -q 'shell: 2 file(s) clean' "$TMP/out" \
  && ok "shebang shell file: counted with the tracked shell files" \
  || bad "shebang shell file: not counted: $(cat "$TMP/out")"

# --- J: an extensionless non-shell script is still dropped. ------------------
# The predicate admits only shells shellcheck can lint; a python shebang handed
# to shellcheck would turn a clean run into a spurious finding, so it drops out.
make_wrapper 0; make_go 0; : > "$TMP/wrapper.log"
printf '#!/usr/bin/env python3\nprint("hi")\n' > "$REPO/script-noext"
git -C "$REPO" add script-noext
git -C "$REPO" commit -qm 'add an extensionless python script'
run_sut
[ "$rc" -eq 0 ] && ok "non-shell shebang: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "non-shell shebang: expected 0, got $rc"; }
grep -q 'script-noext' "$TMP/wrapper.log" \
  && bad "non-shell shebang: wrongly linted as shell" \
  || ok "non-shell shebang: dropped, not linted"
grep -q 'shell: 2 file(s) clean' "$TMP/out" \
  && ok "non-shell shebang: not counted as a shell file" \
  || bad "non-shell shebang: counted: $(cat "$TMP/out")"

# --- K: a tracked shell file whose path git quotes is still linted. ----------
# git's default listing quotes a path that holds a double quote, a backslash or
# a control character, and no file is found under the quoted name, so the file
# dropped out of the lint. The stub wrapper logs each file it is handed on a
# line of its own, and the file leaves the tree once the case has run.
QUOTED=$'odd"na\\me\tx.sh'
printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/$QUOTED"
git -C "$REPO" add -- "$QUOTED"
cat > "$WRAP" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >> "$TMP/wrapper-files.log"
exit 0
EOF
chmod +x "$WRAP"
make_go 0; : > "$TMP/wrapper-files.log"
run_sut
[ "$rc" -eq 0 ] && ok "quoted path: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "quoted path: expected 0, got $rc"; }
grep -qxF -- "$QUOTED" "$TMP/wrapper-files.log" \
  && ok "quoted path: shellcheck-run.sh received the file under its own name" \
  || bad "quoted path: dropped, shellcheck-run.sh got: $(cat "$TMP/wrapper-files.log")"
grep -q 'shell: 3 file(s) clean' "$TMP/out" \
  && ok "quoted path: counted with the tracked shell files" \
  || bad "quoted path: not counted: $(cat "$TMP/out")"
git -C "$REPO" rm -q --cached -- "$QUOTED"; rm -f "$REPO/$QUOTED"

# --- The calls the shell lint splits the tree across. ------------------------
# Three more tracked shell files make five. The stub wrapper logs each call's
# files on a line of its own.
for n in 1 2 3; do printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/s$n.sh"; done
git -C "$REPO" add s1.sh s2.sh s3.sh
git -C "$REPO" commit -qm 'add three shell files'
SHELL_SET="$(printf '%s\n' hook-noext s1.sh s2.sh s3.sh subject.sh | sort | tr '\n' ' ')"
called_files() {  # every logged call's files, sorted, a duplicate kept
  sed 's/^stub-shellcheck-run ran: //' "$TMP/wrapper.log" | tr ' ' '\n' | grep . | sort | tr '\n' ' '
}

# --- X: one call per core, and each file in exactly one call. ----------------
make_wrapper 0; make_go 0; : > "$TMP/wrapper.log"; NPROC=3
run_sut
[ "$rc" -eq 0 ] && ok "three cores: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "three cores: expected 0, got $rc"; }
eq "$(grep -c . "$TMP/wrapper.log")" 3 "three cores: shellcheck-run.sh is called three times"
eq "$(called_files)" "$SHELL_SET" "three cores: every tracked shell file reaches exactly one call"
grep -q 'shell: 5 file(s) clean' "$TMP/out" && ok "three cores: the summary counts every file" \
  || bad "three cores: no clean line for five files: $(cat "$TMP/out")"

# --- X2: more cores than files -> one call per file. -------------------------
: > "$TMP/wrapper.log"; NPROC=64
run_sut
[ "$rc" -eq 0 ] && ok "more cores than files: exit 0" || bad "more cores than files: expected 0, got $rc"
eq "$(grep -c . "$TMP/wrapper.log")" 5 "more cores than files: one call per file"
eq "$(called_files)" "$SHELL_SET" "more cores than files: each file in one call"

# --- Y: one call's findings fail the lint, and only that call's output prints.
# The wrapper finds a defect only in s2.sh: the call that holds it prints the
# finding and a line on stderr and exits 1, and every other call prints a line
# of its own and exits 0.
cat > "$WRAP" <<EOF
#!/bin/sh
echo "stub-shellcheck-run ran: \$*" >> "$TMP/wrapper.log"
case " \$* " in
  *" s2.sh "*) echo "stub finding in s2.sh"; echo "stub note on stderr" >&2; exit 1 ;;
esac
echo "stub clean call"
exit 0
EOF
chmod +x "$WRAP"
: > "$TMP/wrapper.log"; NPROC=3
run_sut
[ "$rc" -eq 1 ] && ok "one call fails: exit 1" || bad "one call fails: expected 1, got $rc"
grep -q 'stub finding in s2.sh' "$TMP/out" && ok "one call fails: its findings print" \
  || bad "one call fails: its findings are lost: $(cat "$TMP/out")"
grep -q 'stub note on stderr' "$TMP/err" && ok "one call fails: its stderr prints on stderr" \
  || bad "one call fails: its stderr is lost: $(cat "$TMP/err")"
grep -q 'stub clean call' "$TMP/out" \
  && bad "one call fails: a clean call's output printed" \
  || ok "one call fails: no clean call's output prints"
grep -q 'shell: FAIL — shellcheck findings (shellcheck-run.sh exit 1)' "$TMP/out" \
  && ok "one call fails: the summary names the findings" \
  || bad "one call fails: no findings line: $(cat "$TMP/out")"

# --- Z: no shellcheck on PATH in any call -> fail-closed, said once. ---------
cat > "$WRAP" <<EOF
#!/bin/sh
echo "stub-shellcheck-run ran: \$*" >> "$TMP/wrapper.log"
echo "stub: no shellcheck" >&2
exit 3
EOF
chmod +x "$WRAP"
: > "$TMP/wrapper.log"; NPROC=3
run_sut
[ "$rc" -eq 1 ] && ok "no runner in any call: exit 1 (fail-closed)" || bad "no runner in any call: expected 1, got $rc"
eq "$(grep -c 'stub: no shellcheck' "$TMP/err")" 1 "no runner in any call: the message prints once"
grep -q 'shellcheck could not run' "$TMP/out" && ok "no runner in any call: the summary names the fail-closed" \
  || bad "no runner in any call: the summary is silent: $(cat "$TMP/out")"
NPROC=""
eq "$(ls -A "$LINT_TMP")" "" "the shell lint's runs, passed or failed, leave nothing in TMPDIR"

# --- The tracked-file listing fails -> structural error (exit 2). ------------
# An empty list from a failed git ls-files reads like a tree with no shell in
# it, which skips the shell lint and passes. The git wrapper refuses only that
# listing, the whole tree's, and hands every other git call on.
make_wrapper 0; make_go 0
REAL_GIT="$(command -v git)"
rm -f "$STUB/git"
cat > "$STUB/git" <<EOF
#!/bin/sh
case " \$* " in
  *" ls-files -z ") echo "stub-git: ls-files refused" >&2; exit 128 ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$STUB/git"
run_sut subject.sh
[ "$rc" -eq 2 ] && ok "tracked listing fails: structural error (exit 2)" || bad "tracked listing fails: expected 2, got $rc"
grep -q 'cannot enumerate tracked files under' "$TMP/err" \
  && ok "tracked listing fails: error names the failed listing" \
  || bad "tracked listing fails: error is silent about the listing"
rm -f "$STUB/git"; ln -s "$REAL_GIT" "$STUB/git"

# --- The listing cannot be written -> structural error (exit 2). -------------
# The shell lint reads its listing back from a file, so a write that failed
# must stop it. Read from a here-string, a listing past 64 KiB is backed by a
# temp file bash writes, and when that write failed the loop read nothing,
# which skipped the shell lint and passed. A thousand more tracked files take
# the listing past 64 KiB, and the run refuses every file write: SIGXFSZ
# ignored and a file size limit of 0. Its output comes back through a pipe,
# which the limit leaves alone.
make_wrapper 0; make_go 0
pads=()
for ((i = 0; i < 1000; i++)); do pads+=("pad-$(printf '%064d' "$i").txt"); done
( cd "$REPO" && for p in "${pads[@]}"; do : > "$p"; done )
git -C "$REPO" add -- "${pads[@]}"
if out="$( ( cd "$REPO" && trap '' XFSZ && ulimit -f 0 \
       && PATH="$STUB" STUB_HOST_OS="$HOST_OS" STUB_ICU_PREFIX="$ICU_PREFIX" \
          STUB_NPROC="$NPROC" TMPDIR="$LINT_TMP" \
          CGO_CPPFLAGS="$CGO_CPPFLAGS_IN" CGO_LDFLAGS="$CGO_LDFLAGS_IN" \
          "$BASH_BIN" "$SUT" subject.sh ) 2>&1 )"; then rc=0; else rc=$?; fi
printf '%s\n' "$out" > "$TMP/out"
[ "$rc" -eq 2 ] && ok "listing not written: structural error (exit 2)" \
  || bad "listing not written: expected 2, got $rc: $(cat "$TMP/out")"
grep -q 'cannot enumerate tracked files under' "$TMP/out" \
  && ok "listing not written: error names the failed listing" \
  || bad "listing not written: error is silent about the listing: $(cat "$TMP/out")"
grep -q 'no tracked shell files' "$TMP/out" \
  && bad "listing not written: read as a tree with no shell in it" \
  || ok "listing not written: not read as a tree with no shell in it"
eq "$(ls -A "$LINT_TMP")" "" "listing not written: the run leaves nothing in TMPDIR"
git -C "$REPO" rm -q --cached -- "${pads[@]}"
( cd "$REPO" && rm -f -- "${pads[@]}" )

# --- The listing cannot be read back -> structural error (exit 2). -----------
# The git wrapper writes the listing and then removes the file it wrote, so the
# loop that reads it back finds nothing to open.
make_wrapper 0; make_go 0
rm -f "$STUB/git"
cat > "$STUB/git" <<EOF
#!/bin/sh
case " \$* " in
  *" ls-files -z ") "$REAL_GIT" "\$@"; rc=\$?; rm -f "\$TMPDIR"/lint-shell.*/listing; exit \$rc ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$STUB/git"
run_sut subject.sh
[ "$rc" -eq 2 ] && ok "listing not read back: structural error (exit 2)" || bad "listing not read back: expected 2, got $rc"
grep -q 'cannot read the listing of tracked files' "$TMP/err" \
  && ok "listing not read back: error names the failed read" \
  || bad "listing not read back: error is silent about the read: $(cat "$TMP/out" "$TMP/err")"
rm -f "$STUB/git"; ln -s "$REAL_GIT" "$STUB/git"

# --- No directory for the shell lint's files -> structural error (exit 2). ---
rm -f "$STUB/mktemp"
printf '#!/bin/sh\nexit 1\n' > "$STUB/mktemp"; chmod +x "$STUB/mktemp"
run_sut subject.sh
[ "$rc" -eq 2 ] && ok "no directory for its files: structural error (exit 2)" || bad "no directory for its files: expected 2, got $rc"
grep -q "cannot make a directory for the shell lint's files" "$TMP/err" \
  && ok "no directory for its files: error names it" \
  || bad "no directory for its files: error is silent about it"
rm -f "$STUB/mktemp"; ln -s "$(command -v mktemp)" "$STUB/mktemp"

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

# --- The icu4c cgo flags go vet is handed. -----------------------------------
# services/helm reaches ICU through Dolt's go-icu-regex, a cgo package, and go
# vet runs cgo. On macOS Homebrew keeps icu4c off every default search path, so
# a vet that is not pointed at the keg stops at 'unicode/regex.h' file not found.
cgo_of() { sed -n "s/^$1=//p" "$TMP/go-cgo.log"; }  # as the stub go saw it
KEG="$TMP/opt/icu4c"
mkdir -p "$KEG/include/unicode" "$KEG/lib"
make_wrapper 0; make_go 0; make_gofmt 0

# --- P: on macOS, vet's cgo is pointed at the keg. ---------------------------
HOST_OS=Darwin; ICU_PREFIX="$KEG"; rm -f "$TMP/brew.log" "$TMP/go-cgo.log"
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "icu4c: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "icu4c: expected 0, got $rc"; }
eq "$(cgo_of CGO_CPPFLAGS)" "-I$KEG/include" "icu4c: vet's cgo is handed the keg's headers"
eq "$(cgo_of CGO_LDFLAGS)" "-L$KEG/lib" "icu4c: and its libraries"
eq "$(cat "$TMP/brew.log" 2>/dev/null)" "--prefix icu4c" "icu4c: brew is asked for icu4c's prefix"
grep -qF "icu4c at $KEG" "$TMP/out" && ok "icu4c: the output names the icu4c vet used" \
  || bad "icu4c: the output does not name $KEG"

# --- Q: CGO flags already set are kept, with the keg's appended. -------------
HOST_OS=Darwin; ICU_PREFIX="$KEG"; CGO_CPPFLAGS_IN=-DFROM_ENV; CGO_LDFLAGS_IN=-L/from/env
run_sut subject.sh
eq "$(cgo_of CGO_CPPFLAGS)" "-DFROM_ENV -I$KEG/include" "icu4c keep: CGO_CPPFLAGS keeps its value, the keg's headers after it"
eq "$(cgo_of CGO_LDFLAGS)" "-L/from/env -L$KEG/lib" "icu4c keep: CGO_LDFLAGS keeps its value, the keg's libraries after it"
CGO_CPPFLAGS_IN=""; CGO_LDFLAGS_IN=""

# --- R: a prefix with no icu4c installed under it adds nothing, and says so. --
# brew prints a formula's prefix whether or not it is installed.
HOST_OS=Darwin; ICU_PREFIX="$TMP/opt/not-installed"; mkdir -p "$ICU_PREFIX"; : > "$TMP/go.log"
run_sut subject.sh
eq "$(cgo_of CGO_CPPFLAGS)" "" "icu4c missing: no include path is added for a keg that is not there"
eq "$(cgo_of CGO_LDFLAGS)" "" "icu4c missing: nor a library path"
grep -q 'brew install icu4c' "$TMP/err" && ok "icu4c missing: the output names the missing prerequisite" \
  || bad "icu4c missing: nothing names the missing icu4c"
grep -q 'stub-go ran' "$TMP/go.log" && ok "icu4c missing: vet still runs and reports for itself" \
  || bad "icu4c missing: vet did not run"

# --- S: off macOS nothing is added, and brew is never asked. ------------------
# The system libicu is on the default search path there.
HOST_OS=""; ICU_PREFIX="$KEG"; CGO_CPPFLAGS_IN=-DFROM_ENV; rm -f "$TMP/brew.log"
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "icu4c off macOS: exit 0" || bad "icu4c off macOS: expected 0, got $rc"
eq "$(cgo_of CGO_CPPFLAGS)" "-DFROM_ENV" "icu4c off macOS: CGO_CPPFLAGS passes through untouched"
eq "$(cgo_of CGO_LDFLAGS)" "" "icu4c off macOS: and no library path is added"
[ ! -e "$TMP/brew.log" ] && ok "icu4c off macOS: brew is never asked" || bad "icu4c off macOS: brew was asked"
CGO_CPPFLAGS_IN=""

# --- T: a run with no vet to make never asks brew. ---------------------------
HOST_OS=Darwin; ICU_PREFIX="$KEG"; rm -f "$STUB/go" "$TMP/brew.log"
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "icu4c no go: exit 1 (fail-closed)" || bad "icu4c no go: expected 1, got $rc"
[ ! -e "$TMP/brew.log" ] && ok "icu4c no go: brew is never asked" || bad "icu4c no go: brew was asked"
make_go 0

# --- U: the icu4c helper missing -> structural error (exit 2). ---------------
# lint.sh sources it from its own checkout, so a lint.sh with no
# assets/scripts/icu4c-cgo.sh beside it is a packaging error, not a clean vet.
HOST_OS=""; ICU_PREFIX=""
mkdir -p "$TMP/lone/tools"; cp "$SUT" "$TMP/lone/tools/lint.sh"
if ( cd "$REPO" && PATH="$STUB" "$BASH_BIN" "$TMP/lone/tools/lint.sh" subject.sh ) >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
[ "$rc" -eq 2 ] && ok "helper missing: structural error (exit 2)" || bad "helper missing: expected 2, got $rc"
grep -q 'cannot source assets/scripts/icu4c-cgo.sh' "$TMP/err" \
  && ok "helper missing: error names the helper" \
  || bad "helper missing: error is silent about icu4c-cgo.sh"

# --- V: the warrant list prints, and only a list that could not run fails. ---
make_wrapper 0; make_go 0; make_gofmt 0; make_step_text 0; make_warrants 0
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "warrants none: exit 0" || bad "warrants none: expected 0, got $rc"
grep -q 'warrants: none touched' "$TMP/out" && ok "warrants none: summary says so" \
  || bad "warrants none: summary is silent: $(cat "$TMP/out")"
grep -qx 'stub-warrants ran::' "$TMP/out" \
  && ok "warrants: the list reads the branch from git, handed no file" \
  || bad "warrants: the list did not run bare: $(cat "$TMP/out")"

make_warrants 1
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "warrants listed: a list fails no lint" || bad "warrants listed: expected 0, got $rc"
grep -q 'stub-warrants ran' "$TMP/out" && ok "warrants listed: the list reaches lint's output" \
  || bad "warrants listed: the list is not in lint's output: $(cat "$TMP/out")"
grep -q 'warrants: touched, listed above' "$TMP/out" && ok "warrants listed: summary points at it" \
  || bad "warrants listed: summary is silent: $(cat "$TMP/out")"
[ "$(grep -n 'stub-warrants ran' "$TMP/out" | cut -d: -f1)" -lt "$(grep -n '^lint: summary' "$TMP/out" | cut -d: -f1)" ] \
  && ok "warrants listed: the list prints before the summary that points at it" \
  || bad "warrants listed: the summary comes first: $(cat "$TMP/out")"

make_warrants 2
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "warrants could not run: exit 1 (fail-closed)" || bad "warrants could not run: expected 1, got $rc"
grep -q 'warrants-touched.sh could not run (exit 2)' "$TMP/out" \
  && ok "warrants could not run: report names it" \
  || bad "warrants could not run: report is silent: $(cat "$TMP/out")"

rm -f "$WARRANTS"
run_sut subject.sh
[ "$rc" -eq 2 ] && ok "warrant list missing: structural error (exit 2)" || bad "warrant list missing: expected 2, got $rc"
grep -q 'warrant list missing' "$TMP/err" \
  && ok "warrant list missing: error names it" \
  || bad "warrant list missing: error is silent about it"
make_warrants 0

# --- W: the step-text lint gets every file, and its verdict is the gate's. ---
# It picks the formulas out itself, so lint.sh hands it the whole list.
HOST_OS=""; ICU_PREFIX=""
make_wrapper 0; make_go 0; make_gofmt 0; make_step_text 0; : > "$TMP/step.log"
run_sut subject.sh formulas/mol-x.toml
[ "$rc" -eq 0 ] && ok "step text clean: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "step text clean: expected 0, got $rc"; }
grep -qx 'stub-step-text ran: subject.sh formulas/mol-x.toml' "$TMP/step.log" \
  && ok "step text: lint-step-text.sh received every file lint.sh was handed" \
  || bad "step text: lint-step-text.sh did not receive the files: $(cat "$TMP/step.log")"
grep -q 'step text: clean' "$TMP/out" && ok "step text clean: reported clean" \
  || bad "step text clean: no clean line in the report"

make_step_text 1
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "step text finding: exit 1" || bad "step text finding: expected 1, got $rc"
grep -q 'step text: FAIL — a formula change adds a procedure' "$TMP/out" \
  && ok "step text finding: report names the finding" \
  || bad "step text finding: report is silent about it"

make_step_text 2
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "step text could not run: exit 1 (fail-closed)" || bad "step text could not run: expected 1, got $rc"
grep -q 'lint-step-text.sh could not run (exit 2)' "$TMP/out" \
  && ok "step text could not run: report names the fail-closed" \
  || bad "step text could not run: report is silent about the fail-closed"

rm -f "$STEP"
run_sut subject.sh
[ "$rc" -eq 2 ] && ok "step-text lint missing: structural error (exit 2)" || bad "step-text lint missing: expected 2, got $rc"
grep -q 'step-text lint missing' "$TMP/err" \
  && ok "step-text lint missing: error names it" \
  || bad "step-text lint missing: error is silent about it"
make_step_text 0

# --- V: invoked by a relative path from a subdirectory, it still finds it. ---
# lint.sh cds to the repo root, after which a relative invocation path names a
# different directory; the helper is located before that cd.
mkdir -p "$REPO/tools"; cp "$SUT" "$REPO/tools/lint.sh"
cp "$HERE/../assets/scripts/icu4c-cgo.sh" "$REPO/assets/scripts/icu4c-cgo.sh"
if ( cd "$REPO/services/foo" && PATH="$STUB" "$BASH_BIN" ../../tools/lint.sh ) >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
[ "$rc" -eq 0 ] && ok "relative invocation: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "relative invocation: expected 0, got $rc"; }
rm -f "$REPO/tools/lint.sh" "$REPO/assets/scripts/icu4c-cgo.sh"

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
