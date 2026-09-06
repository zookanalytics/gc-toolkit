#!/usr/bin/env bash
# pin-keepalive-precheck.sh — the CHECK entry of orders/pin-keepalive.toml.
# A condition order names its `check` and `exec` as two command paths; the
# precheck IS pin-keepalive.sh in --check mode. This wrapper keeps check and
# exec distinct paths (and the check read-only by construction) while the target
# predicate stays defined ONCE, in pin-keepalive.sh, so the two cannot drift.
# Exit 0 = run the exec, non-zero = do not.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/pin-keepalive.sh" --check "$@"
