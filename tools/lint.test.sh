#!/usr/bin/env bash
# Test for lint.sh — the rig's lint entry point for shell, step and skill text,
# Go and the pack, which also prints the warrants a branch touches.
#
# The defects it guards against: a linter that could not run reads as a clean
# pass (fail-closed violated), shell or step-text findings get swallowed into 0,
# a tracked shell file goes unlinted because no change names it, because git
# quotes its path or because its name reads as an option, a listing of
# the tracked files that could not be written or read back reads as a tree with
# no shell and no module in it, the Go lint takes its modules from a listing of
# its own that no check covers, one call's shell findings are lost among the
# calls the tree is split across, a go module is silently skipped, or goes
# unlinted because git quotes its path or because its name reads as an option,
# the Go lint runs a golangci-lint other than the release .golangci-lint-version
# names, or runs at all when the pin is missing or names no release, a finding
# of a linter .golangci.yml enables passes, or a warrant list that could not
# run reads as nothing touched, or one that ran fails the lint or goes
# unprinted.
#
# For the pack lint, the defects are a gc finding, a missing gc or a failed
# copy that passes, a report that names the copy's paths, and a gc that lints
# the checkout or an untracked file, or looks for a city above the copy.
#
# Hermetic but for the last section: a throwaway git repo holds stubs of
# assets/scripts/shellcheck-run.sh, tools/lint-step-text.sh and
# tools/warrants-touched.sh whose exit codes the test sets, a tracked go.mod and
# a pin, and lint.sh runs with PATH pointing at a stub bin. So the test decides
# whether shellcheck, go and gc "ran" and what they returned, and a stub nproc
# sets how many calls the shell lint makes.
# The last section runs the real golangci-lint, at the repository's pin on the
# repository's config, over a module of its own, so it needs the Go toolchain
# and, before Go has cached the linter's build, the network.
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
# The fixture's pin names no real release: only the stub go ever sees it.
PIN=v9.9.9
GOLANGCI=github.com/golangci/golangci-lint/v2/cmd/golangci-lint
printf '%s\n' "$PIN" > "$REPO/.golangci-lint-version"
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
# lint.sh needs git, dirname, mktemp, rm, mkdir and tar; go and gc are stubbed
# so their presence and exit codes are the test's to set. The stub nproc prints
# STUB_NPROC, and with none set fails as on a host without nproc, which leaves
# the shell lint one call, since the bin holds no getconf or sysctl. Everything
# else lint.sh uses is a builtin.
STUB="$TMP/bin"; mkdir -p "$STUB"
for t in git dirname mktemp rm mkdir tar; do ln -s "$(command -v "$t")" "$STUB/$t"; done
cat > "$STUB/nproc" <<'EOF'
#!/bin/sh
[ -n "${STUB_NPROC:-}" ] || exit 1
echo "$STUB_NPROC"
EOF
chmod +x "$STUB/nproc"

# The stub go stands in for `go run` of golangci-lint. It logs its argv and the
# directory it ran in.
make_go() {  # $1 = exit code
  cat > "$STUB/go" <<EOF
#!/bin/sh
echo "stub-go ran: \$*" >> "$TMP/go.log"
pwd >> "$TMP/go-dirs.log"
exit $1
EOF
  chmod +x "$STUB/go"
}

# The stub gc stands in for gc lint. It logs its argv, the directory it ran in,
# its GC_CEILING_DIRECTORIES and every file and link below that directory. Its
# finding names a file the way gc does, under the directory's PWD.
REAL_FIND="$(command -v find)"
make_gc() {  # $1 = exit code
  cat > "$STUB/gc" <<EOF
#!/bin/sh
echo "stub-gc ran: \$*" >> "$TMP/gc.log"
printf '%s\n' "\$PWD" > "$TMP/gc-dir.log"
printf '%s\n' "\${GC_CEILING_DIRECTORIES:-}" > "$TMP/gc-ceiling.log"
"$REAL_FIND" . -type f -o -type l > "$TMP/gc-files.log"
[ $1 -eq 0 ] || echo "\$PWD/agents/x/prompt.template.md:3: stub finding" >&2
exit $1
EOF
  chmod +x "$STUB/gc"
}
make_gc 0

NPROC=""

# Invoke bash by absolute path: with PATH=$STUB the command word itself resolves
# against the stub, where there is no bash. Each run gets a TMPDIR of its own,
# so a case can see what a run left there.
BASH_BIN="${BASH:-$(command -v bash)}"
LINT_TMP="$TMP/lint-tmp"; mkdir -p "$LINT_TMP"
run_sut() {  # args = files; runs in $REPO with the stubbed PATH
  if ( cd "$REPO" && PATH="$STUB" STUB_NPROC="$NPROC" TMPDIR="$LINT_TMP" \
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

# --- D: golangci-lint findings (stub go exit 1) -> exit 1. -------------------
make_wrapper 0; make_go 1
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "go findings: exit 1" || bad "go findings: expected 1, got $rc"
grep -qF "go: FAIL — services/foo golangci-lint $PIN exit 1" "$TMP/out" \
  && ok "go findings: the summary names the module and the version" \
  || bad "go findings: no failure line: $(cat "$TMP/out")"

# --- E: no go on PATH -> exit 1, fail-closed. --------------------------------
make_wrapper 0; rm -f "$STUB/go"
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "go missing: exit 1 (fail-closed)" || bad "go missing: expected 1, got $rc"
grep -qi 'not on PATH' "$TMP/out" && ok "go missing: report names the missing runner" \
  || bad "go missing: report is silent about the missing go"

# --- F: no files given -> the shell lint still covers the tracked tree. -----
# lint.sh lists the tracked shell files itself, so a run handed no file still
# lints subject.sh, and the Go lint still runs.
make_wrapper 0; make_go 0; : > "$TMP/go.log"; : > "$TMP/wrapper.log"
run_sut
[ "$rc" -eq 0 ] && ok "no files: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "no files: expected 0, got $rc"; }
grep -q 'subject.sh' "$TMP/wrapper.log" \
  && ok "no files: the tracked shell file is still linted" \
  || bad "no files: subject.sh never reached shellcheck-run.sh"
grep -q 'shell: 1 file(s) clean' "$TMP/out" && ok "no files: the shell lint reports it clean" \
  || bad "no files: no clean shell line: $(cat "$TMP/out")"
grep -q 'stub-go ran' "$TMP/go.log" && ok "no files: the Go lint still ran" || bad "no files: the Go lint did not run"

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

# --- F3: the Go lint is golangci-lint at the pin, run over the module. ------
# go run builds the release .golangci-lint-version names, from the module, and
# golangci-lint lints every package under it.
make_wrapper 0; make_go 0; : > "$TMP/go.log"; : > "$TMP/go-dirs.log"
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "pinned run: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "pinned run: expected 0, got $rc"; }
eq "$(cat "$TMP/go.log")" "stub-go ran: run $GOLANGCI@$PIN run ./..." \
  "pinned run: go runs golangci-lint at the pinned release over every package"
eq "$(cat "$TMP/go-dirs.log")" "$(cd "$REPO/services/foo" && pwd -P)" "pinned run: from the module's directory"
grep -qxF "  go: services/foo golangci-lint $PIN clean" "$TMP/out" \
  && ok "pinned run: the summary names the module and the version" \
  || bad "pinned run: no clean line: $(cat "$TMP/out")"

# --- F4: a pin with no line end is still the pin. ----------------------------
printf '%s' "$PIN" > "$REPO/.golangci-lint-version"; : > "$TMP/go.log"
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "pin with no line end: exit 0" || bad "pin with no line end: expected 0, got $rc"
grep -qF "@$PIN run" "$TMP/go.log" && ok "pin with no line end: go runs the pinned release" \
  || bad "pin with no line end: go got: $(cat "$TMP/go.log")"
printf '%s\n' "$PIN" > "$REPO/.golangci-lint-version"

# --- F5: no pin, or a pin that names no release -> exit 1, nothing runs. ----
# A name such as latest pins nothing, so it is refused like no pin at all.
for pin in missing latest v2.15 ''; do
  if [ "$pin" = missing ]; then rm -f "$REPO/.golangci-lint-version"; else printf '%s\n' "$pin" > "$REPO/.golangci-lint-version"; fi
  : > "$TMP/go.log"
  run_sut subject.sh
  [ "$rc" -eq 1 ] && ok "pin '$pin': exit 1 (fail-closed)" || bad "pin '$pin': expected 1, got $rc"
  [ ! -s "$TMP/go.log" ] && ok "pin '$pin': go never runs" || bad "pin '$pin': go ran: $(cat "$TMP/go.log")"
  grep -q 'golangci-lint-version is missing or names no golangci-lint release' "$TMP/out" \
    && ok "pin '$pin': the summary names the pin" \
    || bad "pin '$pin': the summary is silent: $(cat "$TMP/out")"
done
printf '%s\n' "$PIN" > "$REPO/.golangci-lint-version"

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
grep -qxF -- "./$QUOTED" "$TMP/wrapper-files.log" \
  && ok "quoted path: shellcheck-run.sh received the file under its own name" \
  || bad "quoted path: dropped, shellcheck-run.sh got: $(cat "$TMP/wrapper-files.log")"
grep -q 'shell: 3 file(s) clean' "$TMP/out" \
  && ok "quoted path: counted with the tracked shell files" \
  || bad "quoted path: not counted: $(cat "$TMP/out")"
git -C "$REPO" rm -q --cached -- "$QUOTED"; rm -f "$REPO/$QUOTED"

# --- K2: a tracked shell file named like an option is still linted. ---------
# A file named --help is listed first, and handed on by its bare name it
# reached the runner as its help option, which exits 0 before shellcheck runs.
# The real runner stands in for the stub here, copied rather than linked
# because later cases write their stub over it. Under it a stub shellcheck logs
# each argument on a line of its own and reports a finding. The runner's
# `env bash` shebang needs a bash on the stub PATH while the case runs.
cp "$HERE/../assets/scripts/shellcheck-run.sh" "$WRAP"; chmod +x "$WRAP"
ln -s "$BASH_BIN" "$STUB/bash"
cat > "$STUB/shellcheck" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >> "$TMP/shellcheck-args.log"
echo "stub shellcheck finding"
exit 1
EOF
chmod +x "$STUB/shellcheck"
printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/--help"
git -C "$REPO" add -- --help
make_go 0; : > "$TMP/shellcheck-args.log"
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "option-like name: the finding fails the lint, exit 1" \
  || { cat "$TMP/out" "$TMP/err"; bad "option-like name: expected 1, got $rc"; }
grep -qxF -- ./--help "$TMP/shellcheck-args.log" \
  && ok "option-like name: shellcheck received it as a path" \
  || bad "option-like name: shellcheck got: $(cat "$TMP/shellcheck-args.log")"
grep -qxF -- ./subject.sh "$TMP/shellcheck-args.log" \
  && ok "option-like name: the files beside it are linted too" \
  || bad "option-like name: subject.sh never reached shellcheck"
grep -q 'shell: FAIL — shellcheck findings (shellcheck-run.sh exit 1)' "$TMP/out" \
  && ok "option-like name: the summary names the findings" \
  || bad "option-like name: no findings line: $(cat "$TMP/out")"
git -C "$REPO" rm -q --cached -- --help; rm -f -- "$REPO/--help"
rm -f "$STUB/bash" "$STUB/shellcheck"

# --- The calls the shell lint splits the tree across. ------------------------
# Three more tracked shell files make five. The stub wrapper logs each call's
# files on a line of its own.
for n in 1 2 3; do printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/s$n.sh"; done
git -C "$REPO" add s1.sh s2.sh s3.sh
git -C "$REPO" commit -qm 'add three shell files'
SHELL_SET="$(printf './%s\n' hook-noext s1.sh s2.sh s3.sh subject.sh | sort | tr '\n' ' ')"
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
  *" ./s2.sh "*) echo "stub finding in s2.sh"; echo "stub note on stderr" >&2; exit 1 ;;
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
# An empty list from a failed git ls-files reads like a tree with no shell, no
# module and no Go in it, which skips those checks and passes. The git wrapper
# refuses only that listing, the whole tree's, and hands every other git call
# on.
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
# lint.sh reads the listing back from a file, so a write that failed must stop
# it. Read from a here-string, a listing past 64 KiB is backed by a temp file
# bash writes, and when that write fails the loop reads nothing, which skips
# the checks the listing feeds and passes. A thousand more tracked files take
# the listing past 64 KiB, and the run refuses every file write: SIGXFSZ
# ignored and a file size limit of 0. Its output comes back through a pipe,
# which the limit leaves alone.
make_wrapper 0; make_go 0
pads=()
for ((i = 0; i < 1000; i++)); do pads+=("pad-$(printf '%064d' "$i").txt"); done
( cd "$REPO" && for p in "${pads[@]}"; do : > "$p"; done )
git -C "$REPO" add -- "${pads[@]}"
if out="$( ( cd "$REPO" && trap '' XFSZ && ulimit -f 0 \
       && PATH="$STUB" STUB_NPROC="$NPROC" TMPDIR="$LINT_TMP" \
          "$BASH_BIN" "$SUT" subject.sh ) 2>&1 )"; then rc=0; else rc=$?; fi
printf '%s\n' "$out" > "$TMP/out"
[ "$rc" -eq 2 ] && ok "listing not written: structural error (exit 2)" \
  || bad "listing not written: expected 2, got $rc: $(cat "$TMP/out")"
grep -q 'cannot enumerate tracked files under' "$TMP/out" \
  && ok "listing not written: error names the failed listing" \
  || bad "listing not written: error is silent about the listing: $(cat "$TMP/out")"
grep -q -e 'no tracked shell files' -e 'no go.mod modules' "$TMP/out" \
  && bad "listing not written: read as a tree with no shell or no module in it" \
  || ok "listing not written: not read as a tree with no shell or no module in it"
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
  *" ls-files -z ") "$REAL_GIT" "\$@"; rc=\$?; rm -f "\$TMPDIR"/lint.*/listing; exit \$rc ;;
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

# --- No directory for the lint's files -> structural error (exit 2). ---------
rm -f "$STUB/mktemp"
printf '#!/bin/sh\nexit 1\n' > "$STUB/mktemp"; chmod +x "$STUB/mktemp"
run_sut subject.sh
[ "$rc" -eq 2 ] && ok "no directory for its files: structural error (exit 2)" || bad "no directory for its files: expected 2, got $rc"
grep -q "cannot make a directory for the lint's files" "$TMP/err" \
  && ok "no directory for its files: error names it" \
  || bad "no directory for its files: error is silent about it"
rm -f "$STUB/mktemp"; ln -s "$(command -v mktemp)" "$STUB/mktemp"

# --- O: the Go lint takes its modules from the tracked listing. -------------
# A listing the Go lint made of its own would sit outside the listing's checks
# above, and one that failed would read as a tree with no module in it. The git
# wrapper refuses every listing but the whole tree's and hands every other git
# call on, and the module is still linted.
make_wrapper 0; make_go 0
REAL_GIT="$(command -v git)"
rm -f "$STUB/git"
cat > "$STUB/git" <<EOF
#!/bin/sh
case " \$* " in
  *" ls-files -z ") ;;
  *" ls-files "*) echo "stub-git: ls-files refused" >&2; exit 128 ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$STUB/git"
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "Go lint: exit 0 with every narrower listing refused" \
  || { cat "$TMP/out" "$TMP/err"; bad "Go lint: expected 0, got $rc"; }
grep -qF "go: services/foo golangci-lint $PIN clean" "$TMP/out" && ok "Go lint: the module is still linted" \
  || bad "Go lint: the module went unlinted: $(cat "$TMP/out")"
rm -f "$STUB/git"; ln -s "$REAL_GIT" "$STUB/git"

# --- Every tracked go.mod is a module, whatever its directory is called. -----
# The root's go.mod, one under a directory named like an option and one under a
# directory whose path git quotes are each linted. Handed to basename or
# dirname, -m/go.mod reads as their options, and git's default listing names
# the quoted directory under a name no directory has.
QDIR=$'q"d\\ir\tm'
mkdir -p "$REPO/-m" "$REPO/$QDIR"
for d in . -m "$QDIR"; do printf 'module m\n\ngo 1.27\n' > "$REPO/$d/go.mod"; done
git -C "$REPO" add -- go.mod -m/go.mod "$QDIR/go.mod"
make_wrapper 0; make_go 0; : > "$TMP/go.log"; : > "$TMP/go-dirs.log"
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "modules: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "modules: expected 0, got $rc"; }
for m in . services/foo -m "$QDIR"; do
  grep -qxF -- "  go: $m golangci-lint $PIN clean" "$TMP/out" && ok "modules: $m is linted" \
    || bad "modules: $m went unlinted: $(cat "$TMP/out")"
  grep -qxF -- "$(cd "$REPO/$m" && pwd -P)" "$TMP/go-dirs.log" && ok "modules: golangci-lint runs in $m" \
    || bad "modules: no run in $m: $(cat "$TMP/go-dirs.log")"
done
eq "$(grep -c 'stub-go ran' "$TMP/go.log")" 4 "modules: golangci-lint runs once in each module"
git -C "$REPO" rm -q --cached -- go.mod -m/go.mod "$QDIR/go.mod"
rm -f -- "$REPO/go.mod" "$REPO/-m/go.mod" "$REPO/$QDIR/go.mod"
rmdir -- "$REPO/-m" "$REPO/$QDIR"

# --- P: gc lint runs in a copy of the tracked files, under its own ceiling. ---
# An untracked pack.toml, such as a worktree nested in the checkout holds, stays
# out of the copy, and so does a tracked file the checkout has removed.
make_wrapper 0; make_go 0; make_gc 0; : > "$TMP/gc.log"
mkdir -p "$REPO/worktrees/nested"; printf '[pack]\n' > "$REPO/worktrees/nested/pack.toml"
rm -f "$REPO/s3.sh"
run_sut subject.sh
[ "$rc" -eq 0 ] && ok "pack clean: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "pack clean: expected 0, got $rc"; }
grep -qxF '  pack: gc lint clean' "$TMP/out" && ok "pack clean: the summary says so" \
  || bad "pack clean: no clean line: $(cat "$TMP/out")"
eq "$(cat "$TMP/gc.log")" "stub-gc ran: lint ." "pack: gc lints every pack below the directory it runs in"
gc_dir="$(cat "$TMP/gc-dir.log")"
case "$gc_dir" in
  "$(cd "$LINT_TMP" && pwd)"/*) ok "pack: gc runs in lint.sh's own directory, outside the checkout" ;;
  *) bad "pack: gc ran in $gc_dir, outside lint.sh's own directory" ;;
esac
eq "$(tr -s / < "$TMP/gc-ceiling.log")" "${gc_dir%/*}" "pack: gc looks for a city no higher than the copy's parent"
eq "$(sort "$TMP/gc-files.log")" "$(git -C "$REPO" ls-files | grep -vx s3.sh | sed 's|^|./|' | sort)" \
  "pack: the copy holds each tracked file the checkout has, and nothing else"
rm -rf "$REPO/worktrees"; git -C "$REPO" checkout -q -- s3.sh

# --- P2: a gc finding fails the lint, and the report names the repo path. ----
make_gc 1
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "pack finding: exit 1" || bad "pack finding: expected 1, got $rc"
grep -qxF 'agents/x/prompt.template.md:3: stub finding' "$TMP/out" \
  && ok "pack finding: the report names the file by its repo path" \
  || bad "pack finding: no finding under the repo path: $(cat "$TMP/out")"
grep -qxF '  pack: FAIL — gc lint exit 1; the report above names each finding, or why it could not run' "$TMP/out" \
  && ok "pack finding: the summary names gc's exit" || bad "pack finding: no failure line: $(cat "$TMP/out")"

# --- P3: no gc on PATH -> exit 1, fail-closed. -------------------------------
rm -f "$STUB/gc"
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "gc missing: exit 1 (fail-closed)" || bad "gc missing: expected 1, got $rc"
grep -qF "pack: FAIL — 'gc' not on PATH" "$TMP/out" && ok "gc missing: the summary names the missing gc" \
  || bad "gc missing: the summary is silent: $(cat "$TMP/out")"

# --- P4: a copy that could not be made -> exit 1, fail-closed, no gc run. ----
make_gc 0; : > "$TMP/gc.log"; rm -f "$STUB/tar"
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "no copy: exit 1 (fail-closed)" || bad "no copy: expected 1, got $rc"
[ ! -s "$TMP/gc.log" ] && ok "no copy: gc never runs" || bad "no copy: gc ran: $(cat "$TMP/gc.log")"
grep -qF 'pack: FAIL — the tracked files could not be copied for gc lint' "$TMP/out" \
  && ok "no copy: the summary names it" || bad "no copy: the summary is silent: $(cat "$TMP/out")"
ln -s "$(command -v tar)" "$STUB/tar"

# --- V: the warrant list prints, and only a list that could not run fails. ---
make_wrapper 0; make_go 0; make_step_text 0; make_warrants 0
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
# It picks the formulas and the skill files out itself, so lint.sh hands it the
# whole list.
make_wrapper 0; make_go 0; make_step_text 0; : > "$TMP/step.log"
run_sut subject.sh formulas/mol-x.toml
[ "$rc" -eq 0 ] && ok "step text clean: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "step text clean: expected 0, got $rc"; }
grep -qx 'stub-step-text ran: subject.sh formulas/mol-x.toml' "$TMP/step.log" \
  && ok "step text: lint-step-text.sh received every file lint.sh was handed" \
  || bad "step text: lint-step-text.sh did not receive the files: $(cat "$TMP/step.log")"
grep -q 'step and skill text: clean' "$TMP/out" && ok "step text clean: reported clean" \
  || bad "step text clean: no clean line in the report"

make_step_text 1
run_sut subject.sh
[ "$rc" -eq 1 ] && ok "step text finding: exit 1" || bad "step text finding: expected 1, got $rc"
grep -q 'step and skill text: FAIL — a change adds a procedure' "$TMP/out" \
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

# --- V: invoked by a relative path from a subdirectory, it lints the tree. ---
# lint.sh finds the repository root through git and cds to it, so a run from a
# subdirectory by a relative path lints the same tree.
mkdir -p "$REPO/tools"; cp "$SUT" "$REPO/tools/lint.sh"
if ( cd "$REPO/services/foo" && PATH="$STUB" "$BASH_BIN" ../../tools/lint.sh ) >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
[ "$rc" -eq 0 ] && ok "relative invocation: exit 0" || { cat "$TMP/out" "$TMP/err"; bad "relative invocation: expected 0, got $rc"; }
rm -f "$REPO/tools/lint.sh"

# --- The real linter: a finding of each enabled linter fails the lint. -------
# lint.sh runs the real golangci-lint, at the repository's pin and on the
# repository's .golangci.yml, over a module of its own whose go line is the
# repository's. golangci-lint itself names the linters and formatters the
# config enables, so a config that enables one with no finding below fails
# here. Each finding sits alone in the module, and the run fails naming its
# linter. The real go follows the stubs on PATH, and golangci-lint's own calls
# to go find it there. The stub gc stays ahead of it, so the pack lint passes
# without a real gc, which a runner on GitHub does not have.
ROOT_DIR="$(cd "$HERE/.." && pwd)"
REAL_GO="$(command -v go || true)"
plant() {  # $1 = a linter or formatter; writes a module file it reports
  case "$1" in
    errcheck) printf 'package fx\n\nimport "os"\n\n// Drop removes a file and drops its error.\nfunc Drop() { os.Remove("x") }\n' ;;
    govet) printf 'package fx\n\nimport "fmt"\n\n// Say formats a string as a number.\nfunc Say() string { return fmt.Sprintf("%%d", "x") }\n' ;;
    ineffassign) printf 'package fx\n\n// Last assigns values it never reads.\nfunc Last() int {\n\tn := 1\n\tn = 2\n\tn = 3\n\treturn n\n}\n' ;;
    staticcheck) printf 'package fx\n\n// Same compares a value with itself.\nfunc Same(n int) bool { return n == n }\n' ;;
    unused) printf 'package fx\n\nfunc unusedHelper() int { return 1 }\n' ;;
    gofmt) printf 'package fx\n\n// Odd is spaced as gofmt never spaces it.\nfunc   Odd() int { return 1 }\n' ;;
    *) return 1 ;;
  esac > "$REAL/finding.go"
}
if [ -z "$REAL_GO" ]; then
  bad "real linter: no go on PATH, so the real linter cannot run"
else
  REAL="$TMP/real"
  mkdir -p "$REAL/assets/scripts" "$REAL/tools"
  git -C "$REAL" init -q
  cp "$ROOT_DIR/.golangci.yml" "$ROOT_DIR/.golangci-lint-version" "$REAL/"
  printf 'module fx\n\ngo %s\n' "$(sed -n 's/^go //p' "$ROOT_DIR/go.mod")" > "$REAL/go.mod"
  printf 'package fx\n\n// Sum adds two numbers.\nfunc Sum(a, b int) int { return a + b }\n' > "$REAL/sum.go"
  for f in assets/scripts/shellcheck-run.sh tools/lint-step-text.sh tools/warrants-touched.sh; do
    printf '#!/bin/sh\nexit 0\n' > "$REAL/$f"; chmod +x "$REAL/$f"
  done
  git -C "$REAL" add -A
  REAL_PIN="$(cat "$REAL/.golangci-lint-version")"
  rm -f "$STUB/go"; make_gc 0
  run_real() {
    if ( cd "$REAL" && PATH="$STUB:$(dirname "$REAL_GO"):$PATH" TMPDIR="$LINT_TMP" \
           CGO_CPPFLAGS="" CGO_LDFLAGS="" "$BASH_BIN" "$SUT" ) >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
  }

  run_real
  [ "$rc" -eq 0 ] && ok "real linter: a clean module passes" || { cat "$TMP/out" "$TMP/err"; bad "real linter: clean module: expected 0, got $rc"; }
  grep -qxF "  go: . golangci-lint $REAL_PIN clean" "$TMP/out" && ok "real linter: the summary names the pinned release" \
    || bad "real linter: no clean line: $(cat "$TMP/out")"

  if enabled="$(cd "$REAL" && { go run "$GOLANGCI@$REAL_PIN" linters --json && go run "$GOLANGCI@$REAL_PIN" formatters --json; } \
                 | jq -r '.Enabled[].name' | sort)"; then
    eq "$(printf '%s\n' "$enabled" | tr '\n' ' ')" "errcheck gofmt govet ineffassign staticcheck unused " \
      "real linter: the config enables the standard set and gofmt"
  else
    bad "real linter: golangci-lint did not name the linters the config enables"
  fi
  for linter in $enabled; do
    if ! plant "$linter"; then
      bad "real linter: no finding is planted for $linter, which the config enables"
      continue
    fi
    run_real
    [ "$rc" -eq 1 ] && ok "real linter: a finding of $linter fails the lint" || bad "real linter: a finding of $linter: expected 1, got $rc"
    grep -q "($linter)\$" "$TMP/out" && ok "real linter: the report names $linter" \
      || bad "real linter: $linter is not in the report: $(cat "$TMP/out")"
    rm -f "$REAL/finding.go"
  done
  eq "$(ls -A "$LINT_TMP")" "" "real linter: the runs leave nothing in TMPDIR"
fi

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
