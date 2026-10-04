#!/usr/bin/env bash
# The one way to run shellcheck in this rig, fail-closed.
#
# Every caller shares this single invocation, so the shell lint runs the same
# way everywhere and no caller can turn a missing linter into a silent pass. It
# runs the host `shellcheck`; when none is on PATH it EXITS NON-ZERO instead of
# reporting success, and the caller must treat that as a finding, not a pass.
#
# Usage: shellcheck-run.sh <file> [<file>...]
#   Severity defaults to `warning`; override with SHELLCHECK_SEVERITY.
#   Extra shellcheck options: SHELLCHECK_OPTS (word-split), e.g. "-x".
#
# Exit codes:
#   0   shellcheck ran and found nothing
#   1   shellcheck ran and found issues (shellcheck's own exit, passed through)
#   2   usage error
#   3   NO RUNNER: no `shellcheck` on PATH. The shell half did not run — the
#       caller must treat this as a finding, not a pass, and must not conflate
#       it with exit 0.
set -uo pipefail

PROG=shellcheck-run
NO_RUNNER=3

usage() {
  cat >&2 <<U
usage: $PROG.sh <file> [<file>...]

Runs shellcheck on each FILE via the host binary. Exits $NO_RUNNER (fail-closed)
when no shellcheck is on PATH: a lint that could not run is not a pass.

  SHELLCHECK_SEVERITY   minimum severity (default: warning)
  SHELLCHECK_OPTS       extra shellcheck options, word-split (e.g. "-x")
U
}

case "${1-}" in
  -h|--help) usage; exit 0 ;;
  "") echo "$PROG: no files given" >&2; usage; exit 2 ;;
esac

OPTS=(-S "${SHELLCHECK_SEVERITY:-warning}")
if [ -n "${SHELLCHECK_OPTS:-}" ]; then
  # SHELLCHECK_OPTS is a caller-supplied option list, not one filename, so the
  # word-split is intentional.
  # shellcheck disable=SC2206
  OPTS+=(${SHELLCHECK_OPTS})
fi

FILES=("$@")
for f in "${FILES[@]}"; do
  [ -e "$f" ] || { echo "$PROG: no such file: $f" >&2; exit 2; }
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "$PROG: linting via host shellcheck ($(command -v shellcheck))" >&2
  shellcheck "${OPTS[@]}" "${FILES[@]}"
  exit $?
fi

# No runner. Fail closed: a lint that could not run is a finding, not a pass.
echo "$PROG: no 'shellcheck' on PATH; the shell lint did NOT run." >&2
echo "$PROG: treat this as a finding, not a pass. Install shellcheck to enable it." >&2
exit "$NO_RUNNER"
