#!/usr/bin/env bash
# The one way to run shellcheck in this rig, fail-closed.
#
# The host has no shellcheck on its PATH, but a shellcheck container is
# available, so whether the lint ran used to depend on each caller rediscovering
# the container path; a caller that probed `command -v shellcheck`, found
# nothing, and moved on reported green without linting anything. This wrapper is
# the single invocation every caller shares: it runs the lint through the host
# binary when one exists and otherwise through the pinned shellcheck image under
# podman, and when neither is available it EXITS NON-ZERO rather than reporting
# a clean run. A linter that could not run is never a pass.
#
# Usage: shellcheck-run.sh <file> [<file>...]
#   Severity defaults to `warning`; override with SHELLCHECK_SEVERITY.
#   Extra shellcheck options: SHELLCHECK_OPTS (word-split), e.g. "-x".
#
# Exit codes:
#   0   shellcheck ran and found nothing
#   1   shellcheck ran and found issues (shellcheck's own exit, passed through)
#   2   usage error
#   3   NO RUNNER: neither a host shellcheck nor a usable podman image. The
#       shell half did not run — the caller must treat this as a finding, not a
#       pass, and must not conflate it with exit 0.
set -uo pipefail

PROG=shellcheck-run
NO_RUNNER=3

usage() {
  cat >&2 <<U
usage: $PROG.sh <file> [<file>...]

Runs shellcheck on each FILE via the host binary or, failing that, the pinned
shellcheck container under podman. Exits $NO_RUNNER (fail-closed) when neither
is available: a lint that could not run is not a pass.

  SHELLCHECK_SEVERITY   minimum severity (default: warning)
  SHELLCHECK_OPTS       extra shellcheck options, word-split (e.g. "-x")
U
}

case "${1-}" in
  -h|--help) usage; exit 0 ;;
  "") echo "$PROG: no files given" >&2; usage; exit 2 ;;
esac

# Options are carried in the environment, never mixed into the positional file
# list, so the podman path can translate the files (and only the files) to
# container paths without having to tell a flag from a filename.
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

# --- Runner 1: a host shellcheck. Paths pass through unchanged. --------------
if command -v shellcheck >/dev/null 2>&1; then
  echo "$PROG: linting via host shellcheck ($(command -v shellcheck))" >&2
  shellcheck "${OPTS[@]}" "${FILES[@]}"
  exit $?
fi

# --- Runner 2: the pinned shellcheck image under podman. ---------------------
# The container sees only what is mounted, so mount the files' root read-only
# and address them relative to it. The root is the git top-level when the files
# live in a checkout (the review and test callers both do); otherwise it is the
# first file's directory.
if command -v podman >/dev/null 2>&1; then
  IMAGE=""
  for cand in docker.io/koalaman/shellcheck:stable koalaman/shellcheck:stable; do
    if podman image exists "$cand" 2>/dev/null; then IMAGE="$cand"; break; fi
  done
  if [ -z "$IMAGE" ]; then
    IMAGE=$(podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
      | grep -m1 'koalaman/shellcheck' || true)
  fi
  if [ -z "$IMAGE" ]; then
    echo "$PROG: podman is present but no koalaman/shellcheck image is pulled;" >&2
    echo "$PROG: the shell lint did NOT run (treat as a finding, not a pass)." >&2
    echo "$PROG: enable it with: podman pull koalaman/shellcheck:stable" >&2
    exit "$NO_RUNNER"
  fi

  first_dir=$(cd "$(dirname "${FILES[0]}")" && pwd) || {
    echo "$PROG: cannot resolve directory of ${FILES[0]}" >&2; exit "$NO_RUNNER"; }
  ROOT=$(git -C "$first_dir" rev-parse --show-toplevel 2>/dev/null) || ROOT=""
  [ -n "$ROOT" ] || ROOT="$first_dir"

  REL=()
  for f in "${FILES[@]}"; do
    abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    case "$abs" in
      "$ROOT"/*) REL+=("${abs#"$ROOT"/}") ;;
      *)
        echo "$PROG: $f is outside the mount root $ROOT;" >&2
        echo "$PROG: run $PROG.sh once per root. Nothing linted (treat as a finding)." >&2
        exit "$NO_RUNNER"
        ;;
    esac
  done

  echo "$PROG: linting via podman image $IMAGE" >&2
  podman run --rm -v "$ROOT:/mnt:ro" -w /mnt "$IMAGE" "${OPTS[@]}" "${REL[@]}"
  exit $?
fi

# --- No runner. Fail closed. -------------------------------------------------
echo "$PROG: no 'shellcheck' on PATH and no 'podman' to run the container;" >&2
echo "$PROG: the shell lint did NOT run. Treat this as a finding, not a pass." >&2
echo "$PROG: enable it with: install shellcheck, or 'podman pull koalaman/shellcheck:stable'." >&2
exit "$NO_RUNNER"
