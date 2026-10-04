#!/usr/bin/env bash
# Hermetic test for lint.sh — the rig's shell + go lint entry point.
#
# The defects it guards against: a linter that could not run reads as a clean
# pass (fail-closed violated), shell findings get swallowed into 0, or a go
# module is silently skipped.
#
# Hermetic: a throwaway git repo holds a stub shellcheck-run.sh whose exit code
# the test sets and a tracked go.mod, and lint.sh runs with PATH pointing at a
# stub bin — so whether shellcheck and go "ran" and what they returned is the
# test's to decide. No real shellcheck or go toolchain is required.
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
# lint.sh needs git, basename and dirname; go is stubbed so its presence and
# exit code are the test's to set. Everything else lint.sh uses is a builtin.
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

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
