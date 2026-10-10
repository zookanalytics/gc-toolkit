#!/usr/bin/env bash
# anchor-edges-backfill.sh — join each live anchor's children to it by the
# membership edge every anchor-children reader follows.
#
#   anchor-edges-backfill.sh [--check] [<anchor>...]
#
# A bead that hangs off a PR anchor carries anchor_bead=<anchor> and a `related`
# edge onto the anchor, and the readers of an anchor's children follow the edge
# (bd-lib.sh, "The anchor graph"). A child filed before the edge existed, or by
# a writer that skipped it, is invisible to them. For each anchor this reads the
# anchor_bead children once, every status, because a closed review is a lane's
# backing, and joins the ones the edge read does not reach, in one write per
# anchor. Idempotent: a second run joins nothing.
#
# With no anchor named it visits every live anchor: a non-closed bead carrying
# merge_result, the key the anchor arms enumerate by. A closed anchor is left
# alone, since only history tooling reads its children.
#
# --check joins nothing and reports what a run would join.
#
# Exits: 0 every visited anchor's children are joined (with --check, none is
# missing an edge) · 1 a join did not land (with --check, an anchor is missing
# an edge) · 2 a read did not answer.
set -uo pipefail

PROG="anchor-edges-backfill"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../assets/scripts/bd-lib.sh
. "${GC_BD_LIB:-$REPO_ROOT/assets/scripts/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh" >&2; exit 2; }

CHECK=""; ANCHORS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=--check ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "$PROG: unknown option '$1'" >&2; exit 2 ;;
    *) ANCHORS+=("$1") ;;
  esac
  shift
done

if [ "${#ANCHORS[@]}" -eq 0 ]; then
  rows=$(bd_list --has-metadata-key merge_result --status=open,in_progress,blocked,deferred,hooked,pinned) \
    || { echo "$PROG: could not enumerate the live anchors; nothing joined" >&2; exit 2; }
  while IFS= read -r a; do
    [ -n "$a" ] && ANCHORS+=("$a")
  done <<ANCHORS_EOF
$(printf '%s' "$rows" | jq -r '.[].id // empty' 2>/dev/null)
ANCHORS_EOF
fi

visited=0; joined=0; owed=0; failed=0; unreadable=0
for a in ${ANCHORS[@]+"${ANCHORS[@]}"}; do
  visited=$((visited + 1))
  out=$(bd_anchor_backfill "$a" $CHECK); rc=$?
  n=$(printf '%s' "$out" | awk 'NF { c++ } END { print c + 0 }')
  ids=$(printf '%s' "$out" | paste -sd' ' -)
  case "$rc" in
    0)
      [ "$n" -gt 0 ] || continue
      if [ -n "$CHECK" ]; then
        owed=$((owed + 1))
        echo "$PROG: $a — $n child(ren) lack the edge: $ids"
      else
        joined=$((joined + n))
        echo "$PROG: $a — joined $n child(ren): $ids"
      fi ;;
    1)
      failed=$((failed + 1))
      echo "$PROG: $a — joining $n child(ren) did not land: $ids" >&2 ;;
    *)
      unreadable=$((unreadable + 1))
      echo "$PROG: $a — its children did not read; nothing joined" >&2 ;;
  esac
done

if [ -n "$CHECK" ]; then
  echo "$PROG: checked $visited anchor(s); $owed missing an edge, $unreadable unreadable"
else
  echo "$PROG: visited $visited anchor(s); joined $joined child(ren); $failed write(s) did not land, $unreadable unreadable"
fi
[ "$unreadable" -eq 0 ] || exit 2
[ "$failed" -eq 0 ] && [ "$owed" -eq 0 ] || exit 1
exit 0
