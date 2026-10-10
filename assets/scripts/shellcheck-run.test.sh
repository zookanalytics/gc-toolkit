#!/usr/bin/env bash
# Hermetic test for shellcheck-run.sh — the fail-closed shellcheck wrapper.
#
# The defect it guards against: a caller that cannot run shellcheck reports a
# clean run anyway. So the load-bearing assertions are the fail-closed one (exit
# 3 when no shellcheck is on PATH, never 0) and the findings pass-through (exit 1
# is not swallowed into 0). The repo's .shellcheckrc is guarded too: without it,
# a lint run from the repo root cannot open a file a suite sources, and reports
# a variable that only the sourced file exports as unused.
#
# Hermetic: the wrapper is invoked with PATH pointing at a stub bin, so whether
# it finds a shellcheck is the test's to decide. In A-D `shellcheck` is a fake
# whose presence and exit code the test controls. E runs the real shellcheck
# from the host on a fixture tree under $TMP, and is skipped without one.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/shellcheck-run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-shellcheck-run-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -f "$SUT" ] && ok "SUT exists at $SUT" || bad "SUT missing: $SUT"
bash -n "$SUT" && ok "wrapper is syntactically valid bash" || bad "wrapper failed bash -n"
[ -x "$SUT" ] && ok "wrapper is executable" || bad "wrapper is not executable"

# --- The stub bin. Only what the wrapper's own code reaches for. -------------
# The wrapper runs `shellcheck` and, in usage, `cat`; everything else it uses is
# a bash builtin.
STUB="$TMP/bin"; mkdir -p "$STUB"
ln -s "$(command -v cat)" "$STUB/cat"

# Fake shellcheck: records that it ran, exits the code the test asked for.
make_shellcheck() {  # $1 = exit code
  cat > "$STUB/shellcheck" <<EOF
#!/bin/sh
echo "fake-shellcheck ran: \$*" >> "$TMP/shellcheck.log"
exit $1
EOF
  chmod +x "$STUB/shellcheck"
}

# Run the wrapper with the stubbed PATH; capture rc without tripping set -e.
# Invoke bash by absolute path: with PATH=$STUB the command word itself is
# resolved against the stub, so a bare `bash` would not be found there.
BASH_BIN="${BASH:-$(command -v bash)}"
run_sut() {  # extra env is set by the caller; args are files
  if PATH="$STUB" "$BASH_BIN" "$SUT" "$@" >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
}

FIXTURE="$TMP/subject.sh"; printf '#!/usr/bin/env bash\ntrue\n' > "$FIXTURE"

# --- A: no shellcheck on PATH -> fail closed (exit 3), never a clean 0. -------
rm -f "$STUB/shellcheck"
run_sut "$FIXTURE"
[ "$rc" -eq 3 ] && ok "no runner: exits 3 (fail-closed)" || bad "no runner: expected 3, got $rc"
grep -qi 'finding' "$TMP/err" && ok "no runner: stderr says treat as a finding" \
  || bad "no runner: stderr does not tell the caller it is a finding"

# --- B: host shellcheck present, clean -> exit 0. ----------------------------
: > "$TMP/shellcheck.log"; make_shellcheck 0
run_sut "$FIXTURE"
[ "$rc" -eq 0 ] && ok "host shellcheck clean: exit 0" || bad "host clean: expected 0, got $rc"
grep -q 'fake-shellcheck ran' "$TMP/shellcheck.log" && ok "host path actually invoked shellcheck" \
  || bad "host path did not invoke shellcheck"
grep -qi 'via host shellcheck' "$TMP/err" && ok "host path announces the runner it used" \
  || bad "host path is silent about the runner"

# --- C: host shellcheck finds issues -> exit 1 passed through, not swallowed. -
make_shellcheck 1
run_sut "$FIXTURE"
[ "$rc" -eq 1 ] && ok "host shellcheck findings: exit 1 passed through" || bad "host findings: expected 1, got $rc"

# --- D: no files -> usage error (exit 2). ------------------------------------
run_sut
[ "$rc" -eq 2 ] && ok "no files: usage error (exit 2)" || bad "no files: expected 2, got $rc"

# --- E: the repo's .shellcheckrc lets the real runner read a sourced file. ----
# A suite assigns a variable that only the file it sources exports. Run from the
# tree root, the way tools/lint.sh runs from the repo root, shellcheck sees the
# variable as used only when it resolves source=lib.sh from the suite's own
# directory and reads lib.sh. --norc is the control: the same run without any rc
# reports the variable unused, so the clean run is the rc's doing.
REAL_SHELLCHECK="$(command -v shellcheck || true)"
if [ -z "$REAL_SHELLCHECK" ]; then
  echo "skip - .shellcheckrc source resolution (no shellcheck on this host)"
else
  TREE="$TMP/tree"; REAL="$TMP/realbin"
  mkdir -p "$TREE/sub" "$REAL"
  ln -s "$REAL_SHELLCHECK" "$REAL/shellcheck"
  cp "$HERE/../../.shellcheckrc" "$TREE/.shellcheckrc" \
    && ok "the repo root carries a .shellcheckrc" || bad "no .shellcheckrc at the repo root"
  printf '#!/usr/bin/env bash\nexport LIB_FLAG=""\n' > "$TREE/sub/lib.sh"
  cat > "$TREE/sub/suite.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
LIB_FLAG=1
EOF
  run_real() {  # extra env is set by the caller
    if (cd "$TREE" && PATH="$REAL" "$BASH_BIN" "$SUT" sub/suite.sh) >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
  }
  run_real
  [ "$rc" -eq 0 ] && ok "rc: a variable the sourced file exports is not reported unused" \
    || bad "rc: expected a clean run, got $rc: $(tr -s '\n' ' ' < "$TMP/out")"
  SHELLCHECK_OPTS=--norc run_real
  [ "$rc" -eq 1 ] && grep -q 'SC2034' "$TMP/out" \
    && ok "control: without the rc the same variable is reported unused (SC2034)" \
    || bad "control: expected SC2034 with --norc, got $rc: $(tr -s '\n' ' ' < "$TMP/out")"
fi

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
