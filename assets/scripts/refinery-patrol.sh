#!/usr/bin/env bash
# refinery-patrol.sh — the refinery patrol's own loop: its identity check and
# the pour of its next iteration.
#
#   refinery-patrol.sh identity
#   refinery-patrol.sh next
#
# identity, the validate-identity step: the refinery reads its queue by
# $GC_AGENT, the identity the session harness guarantees, and an empty filter
# is no filter, so a refinery that polls on one idles while it looks healthy.
# An empty GC_AGENT has no bead of its own to gate, so it files a patrol
# finding (patrol-finding.sh --scope refinery-findings) and exits 1.
#
# next, the next-iteration step: one wisp is one iteration, and every
# iteration that ends pours the next before it burns its own, so the loop
# never drops. It names the current wisp first, $GC_BEAD_ID or the newest
# ephemeral mol-refinery-patrol molecule assigned to $GC_AGENT, open or in
# progress (gc bd list hides the wisps' tier without --include-infra). It
# removes every tree the iteration left under the refinery's home. It pours the
# next wisp root-only with exactly the rig identity the startup pour passes
# (target_branch, the rig's default branch; rig_name, $GC_RIG; binding_prefix,
# $GC_AGENT's name less its role), so every other var renders the formula's
# current default. It stamps gc.rig on the new wisp before assigning it, so an
# interrupted pour leaves a rig-scoped orphan the startup reconcile collects,
# and it burns the current wisp only once the new one is assigned. A pour or an
# assign that fails burns what it poured and keeps the current wisp.
#
# Exit: 0 done · 1 the identity is empty, or the next wisp is not in place and
#       the current one is kept; the output says which · 2 usage
set -uo pipefail

PROG="refinery-patrol"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=refinery-lib.sh
. "$HERE/refinery-lib.sh" || { echo "$PROG: cannot source refinery-lib.sh beside this script" >&2; exit 1; }

FORMULA="mol-refinery-patrol"
usage() { echo "usage: $PROG identity | $PROG next" >&2; exit 2; }

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
  next) [ $# -eq 1 ] || usage ;;
  -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) usage ;;
esac

stop() { echo "$PROG: $1; the current wisp is kept" >&2; exit 1; }
[ -n "${GC_AGENT:-}" ] || stop "GC_AGENT is empty, so no wisp of this refinery can be named"

CURRENT="${GC_BEAD_ID:-}"
if [ -z "$CURRENT" ]; then
  ROWS=$(bd_json list --assignee="$GC_AGENT" --status=open,in_progress --type=molecule --include-infra --limit=0) || ROWS=""
  CURRENT=$(printf '%s' "$ROWS" | jq -r --arg f "$FORMULA" '[ .[]? | select(.title == $f) ] | sort_by(.created_at // "", .id) | last | .id // empty' 2>/dev/null)
fi
[ -n "$CURRENT" ] || stop "the current wisp could not be named, so no successor is poured"

if HOME_DIR=$(refinery_home 2>/dev/null); then
  for LEFT in "$HOME_DIR"/worktrees/*; do
    [ -d "$LEFT" ] || continue
    refinery_teardown "$HOME_DIR" "${LEFT##*/}" || echo "$PROG: the next prep removes $LEFT" >&2
  done
  TARGET_BRANCH=$(refinery_default_branch "$HOME_DIR") || TARGET_BRANCH=""
fi
[ -n "${TARGET_BRANCH:-}" ] || stop "the rig's default branch could not be read for the next pour"
NAME="${GC_AGENT##*/}"
PREFIX="${NAME%refinery}"

NEXT=$(gc bd mol wisp "$FORMULA" --root-only --var "target_branch=$TARGET_BRANCH" --var "rig_name=${GC_RIG:-}" \
  --var "binding_prefix=$PREFIX" --json </dev/null 2>/dev/null | jq -r '.new_epic_id // empty' 2>/dev/null)
[ -n "$NEXT" ] || stop "the next wisp did not pour"
gc bd update "$NEXT" --set-metadata "gc.rig=${GC_RIG:-}" </dev/null >/dev/null \
  || echo "$PROG: $NEXT carries no gc.rig, so an interrupted pour leaves it without a rig scope" >&2
if ! gc bd update "$NEXT" --assignee="$GC_AGENT" </dev/null >/dev/null; then
  gc bd mol burn "$NEXT" --force </dev/null >/dev/null 2>&1 \
    || echo "$PROG: $NEXT, poured and unassigned, did not burn; the startup reconcile collects it" >&2
  stop "the next wisp $NEXT was not assigned to $GC_AGENT"
fi
gc bd mol burn "$CURRENT" --force </dev/null >/dev/null 2>&1 \
  || { echo "$PROG: $NEXT is poured and assigned, but $CURRENT did not burn; the startup reconcile keeps the newest" >&2; exit 1; }
echo "$PROG: poured $NEXT and burned $CURRENT; begin it from the formula's first step"
