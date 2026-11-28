#!/usr/bin/env bash
# refinery-patrol.sh — the refinery session's own checks: its identity, and
# the end of the session.
#
#   refinery-patrol.sh identity
#   refinery-patrol.sh end
#
# identity, the validate-identity step: the refinery reads its queue by
# $GC_AGENT, the identity the session harness guarantees, and an empty filter
# is no filter, so a refinery that polls on one idles while it looks healthy.
# An empty GC_AGENT has no bead of its own to gate, so it files a patrol
# finding (patrol-finding.sh --scope refinery-findings) and exits 1.
#
# end, the end-session step: it removes every tree the session left under the
# refinery's home, in whatever state the item left it, so the next session
# starts from a clean home. A tree it cannot remove is named, and the next
# prep of that bead removes it.
#
# Exit: 0 done · 1 the identity is empty, or a tree was not removed; the
#       output says which · 2 usage
set -uo pipefail

PROG="refinery-patrol"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }

usage() { echo "usage: $PROG identity | $PROG end" >&2; exit 2; }

case "${1:-}" in
  identity)
    [ $# -eq 1 ] || usage
    [ -z "${GC_AGENT:-}" ] || { echo "$PROG: the refinery polls as $GC_AGENT"; exit 0; }
    echo "$PROG: GC_AGENT is empty, so the refinery refuses to poll its queue with an empty filter" >&2
    "$HERE/patrol-finding.sh" --scope refinery-findings --key refinery-empty-identity \
      --title "Refinery session started with an empty GC_AGENT" \
      --message "Refinery session ${GC_SESSION_ID:-<unknown>} started with an empty GC_AGENT, so it cannot poll its queue and would idle while looking healthy; investigate the session harness." >&2 \
      || echo "$PROG: the refinery-empty-identity finding did not land" >&2
    exit 1 ;;
  end) [ $# -eq 1 ] || usage ;;
  -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) usage ;;
esac

HOME_DIR=$(refinery_home) || exit 1
RC=0
for LEFT in "$HOME_DIR"/worktrees/*; do
  [ -d "$LEFT" ] || continue
  refinery_teardown "$HOME_DIR" "${LEFT##*/}" || { echo "$PROG: the next prep of ${LEFT##*/} removes $LEFT" >&2; RC=1; }
done
[ "$RC" != 0 ] || echo "$PROG: no tree is left under $HOME_DIR/worktrees"
exit "$RC"
