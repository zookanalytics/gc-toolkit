#!/usr/bin/env bash
# Hermetic test for shellcheck-run.sh — the fail-closed shellcheck wrapper.
#
# The defect it guards against: a caller that cannot run shellcheck reports a
# clean run anyway. So the load-bearing assertions are the two fail-closed ones
# (no runner, and podman-without-an-image both exit 3, never 0), the findings
# pass-through (exit 1 is not swallowed into 0), and that the podman fallback is
# actually taken when the host has no shellcheck.
#
# Hermetic: the wrapper is invoked with PATH pointing at a stub bin, so which
# runner it finds is the test's to decide. `shellcheck` and `podman` are fakes
# whose presence and exit codes the test controls; git/grep/coreutils are
# symlinked in because the wrapper's podman path needs them. No container is
# ever run and no real shellcheck is required.
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
STUB="$TMP/bin"; mkdir -p "$STUB"
for t in cat dirname basename git grep; do
  ln -s "$(command -v "$t")" "$STUB/$t"
done

# Fake shellcheck: records that it ran, exits the code the test asked for.
make_shellcheck() {  # $1 = exit code
  cat > "$STUB/shellcheck" <<EOF
#!/bin/sh
echo "fake-shellcheck ran: \$*" >> "$TMP/shellcheck.log"
exit $1
EOF
  chmod +x "$STUB/shellcheck"
}

# Fake podman: `image exists` honors FAKE_IMG_EXISTS, `images` prints
# FAKE_IMAGES, `run` records argv and exits FAKE_RUN_RC.
cat > "$STUB/podman" <<EOF
#!/bin/sh
case "\$1" in
  image)  [ "\$2" = exists ] && exit "\${FAKE_IMG_EXISTS:-0}" ;;
  images) printf '%s\n' "\${FAKE_IMAGES:-}" ;;
  run)    echo "podman run \$*" >> "$TMP/podman.log"; exit "\${FAKE_RUN_RC:-0}" ;;
esac
EOF
chmod +x "$STUB/podman"

# Run the wrapper with the stubbed PATH; capture rc without tripping set -e.
# Invoke bash by absolute path: with PATH=$STUB the command word itself is
# resolved against the stub, so a bare `bash` would not be found there.
BASH_BIN="${BASH:-$(command -v bash)}"
run_sut() {  # extra env is set by the caller; args are files
  if PATH="$STUB" "$BASH_BIN" "$SUT" "$@" >"$TMP/out" 2>"$TMP/err"; then rc=0; else rc=$?; fi
}

FIXTURE="$TMP/subject.sh"; printf '#!/usr/bin/env bash\ntrue\n' > "$FIXTURE"

# --- A: no runner at all -> fail closed (exit 3), never a clean 0. -----------
rm -f "$STUB/shellcheck" "$STUB/podman"
run_sut "$FIXTURE"
[ "$rc" -eq 3 ] && ok "no runner: exits 3 (fail-closed)" || bad "no runner: expected 3, got $rc"
grep -qi 'finding' "$TMP/err" && ok "no runner: stderr says treat as a finding" \
  || bad "no runner: stderr does not tell the caller it is a finding"
# restore podman stub for the remaining cases
cat > "$STUB/podman" <<EOF
#!/bin/sh
case "\$1" in
  image)  [ "\$2" = exists ] && exit "\${FAKE_IMG_EXISTS:-0}" ;;
  images) printf '%s\n' "\${FAKE_IMAGES:-}" ;;
  run)    echo "podman run \$*" >> "$TMP/podman.log"; exit "\${FAKE_RUN_RC:-0}" ;;
esac
EOF
chmod +x "$STUB/podman"

# --- B: podman present but no image -> fail closed (exit 3). -----------------
rm -f "$STUB/shellcheck"
export FAKE_IMG_EXISTS=1 FAKE_IMAGES=""
run_sut "$FIXTURE"
unset FAKE_IMG_EXISTS FAKE_IMAGES
[ "$rc" -eq 3 ] && ok "podman but no image: exits 3 (fail-closed)" || bad "podman no image: expected 3, got $rc"
grep -qi 'podman pull' "$TMP/err" && ok "podman no image: stderr names the pull remedy" \
  || bad "podman no image: stderr lacks the pull remedy"

# --- C: host shellcheck present, clean -> exit 0 via the host path. ----------
: > "$TMP/shellcheck.log"; make_shellcheck 0
run_sut "$FIXTURE"
[ "$rc" -eq 0 ] && ok "host shellcheck clean: exit 0" || bad "host clean: expected 0, got $rc"
grep -q 'fake-shellcheck ran' "$TMP/shellcheck.log" && ok "host path actually invoked shellcheck" \
  || bad "host path did not invoke shellcheck"
grep -qi 'via host shellcheck' "$TMP/err" && ok "host path announces the runner it used" \
  || bad "host path is silent about the runner"

# --- D: host shellcheck finds issues -> exit 1 passed through, not swallowed. -
make_shellcheck 1
run_sut "$FIXTURE"
[ "$rc" -eq 1 ] && ok "host shellcheck findings: exit 1 passed through" || bad "host findings: expected 1, got $rc"

# --- E: host absent, podman+image present -> runs via podman, exit 0. --------
rm -f "$STUB/shellcheck"; : > "$TMP/podman.log"
export FAKE_IMG_EXISTS=0 FAKE_RUN_RC=0
run_sut "$FIXTURE"
unset FAKE_IMG_EXISTS FAKE_RUN_RC
[ "$rc" -eq 0 ] && ok "podman fallback clean: exit 0" || bad "podman fallback: expected 0, got $rc"
grep -q 'podman run' "$TMP/podman.log" && ok "fallback actually invoked podman run" \
  || bad "fallback did not invoke podman run"
grep -q 'koalaman/shellcheck' "$TMP/podman.log" && ok "podman run used the shellcheck image" \
  || bad "podman run did not name the shellcheck image"
grep -q '/mnt:ro' "$TMP/podman.log" && ok "podman run mounts the root read-only" \
  || bad "podman run did not mount read-only"

# --- F: no files -> usage error (exit 2). ------------------------------------
run_sut
[ "$rc" -eq 2 ] && ok "no files: usage error (exit 2)" || bad "no files: expected 2, got $rc"

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
