#!/usr/bin/env bash
# anchor-edges-backfill.sh — join each anchor's children to it by the
# membership edge, and mark the store joined.
#
#   anchor-edges-backfill.sh [--check | --mark] [<anchor>...]
#
# A bead that hangs off a PR anchor names it in anchor_bead and carries a
# `related` edge onto it (bd-lib.sh, "The anchor graph"). In a store marked
# joined, an anchor's closed children are read through that edge, so a closed
# child without it goes unread. For each anchor this reads the anchor_bead
# children once, every status, and joins the ones the edge read does not reach,
# in one write per anchor. When bd refuses that write, each pair is joined
# alone, and a pair bd refuses on its own is printed with bd's reason.
# Idempotent: a second run joins nothing.
#
# With no anchor named it visits every anchor a reader asks about: each
# non-closed bead carrying merge_result, the key the anchor arms enumerate by,
# and each anchor a live bead names in anchor_bead. A closed anchor with no
# live child is left alone, since only history tooling reads its children. An
# anchor a live bead names that does not resolve in this store has no children
# to join, so it is reported and skipped.
#
# --check joins nothing, reports what a run would join, and says whether the
# store is marked.
#
# --mark runs as a plain run over every anchor. When it found no child missing
# its edge, it marks the store joined (bd-lib.sh's ANCHOR_JOINED_KEY in
# `gc bd kv`), the mark bd-lib.sh reads before it reads closed children through
# the edge. A run that joined children marks nothing, so a writer still filing
# children without the edge keeps the store unmarked; run it again later.
#
# Exits: 0 every visited anchor's children are joined (with --check, none is
# missing an edge; with --mark, the store is marked) · 1 a join or the mark did
# not land (with --check, an anchor is missing an edge) · 2 a read did not
# answer · 3 (--mark) the run joined children, so the store is not marked yet.
set -uo pipefail

PROG="anchor-edges-backfill"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../assets/scripts/bd-lib.sh
. "${GC_BD_LIB:-$REPO_ROOT/assets/scripts/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh" >&2; exit 2; }

MODE=""; ANCHORS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--mark)
      [ -z "$MODE" ] || { echo "$PROG: --check and --mark do not combine" >&2; exit 2; }
      MODE="$1" ;;
    -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "$PROG: unknown option '$1'" >&2; exit 2 ;;
    *) ANCHORS+=("$1") ;;
  esac
  shift
done
if [ "$MODE" = --mark ] && [ "${#ANCHORS[@]}" -gt 0 ]; then
  echo "$PROG: --mark visits every anchor, so it names none" >&2; exit 2
fi
LIVE="open,in_progress,blocked,deferred,hooked,pinned"

# The anchors a live bead names. Each is visited; one that does not resolve is
# reported rather than read as a store that did not answer.
NAMED=""
if [ "${#ANCHORS[@]}" -eq 0 ]; then
  rows=$(bd_list --has-metadata-key merge_result --status="$LIVE") \
    || { echo "$PROG: could not enumerate the live anchors; nothing joined" >&2; exit 2; }
  kids=$(bd_list --has-metadata-key anchor_bead --status="$LIVE") \
    || { echo "$PROG: could not enumerate the live anchor children; nothing joined" >&2; exit 2; }
  NAMED=$(printf '%s' "$kids" | jq -r '[ .[] | (.metadata.anchor_bead // "") | tostring | select(. != "") ] | unique | .[]' 2>/dev/null)
  while IFS= read -r a; do
    [ -n "$a" ] && ANCHORS+=("$a")
  done <<ANCHORS_EOF
$( { printf '%s' "$rows" | jq -r '.[].id // empty' 2>/dev/null; printf '%s\n' "$NAMED"; } | awk 'NF && !seen[$0]++')
ANCHORS_EOF
fi

# unresolved <anchor> — 0 when bd answers that <anchor> is no bead in this
# store: no row for it, or bd's not-found error. bd exits 1 with that error, so
# its answer is read before it is tested and the exit status decides nothing.
unresolved() {
  local row
  row=$(bd_json show "$1")
  printf '%s' "$row" | jq -e '
    (type == "array" and length == 0)
    or (type == "object" and ((.error // "") | tostring | test("not found|no issues? found"; "i")))' >/dev/null 2>&1
}

check=""; [ "$MODE" = --check ] && check=--check
visited=0; joined=0; owed=0; failed=0; unreadable=0; skipped=0
for a in ${ANCHORS[@]+"${ANCHORS[@]}"}; do
  out=$(bd_anchor_backfill "$a" $check); rc=$?
  if [ "$rc" -eq 2 ] && unresolved "$a"; then
    skipped=$((skipped + 1))
    echo "$PROG: $a — named in anchor_bead but no bead in this store; skipped"
    continue
  fi
  visited=$((visited + 1))
  n=$(printf '%s' "$out" | awk 'NF { c++ } END { print c + 0 }')
  ids=$(printf '%s' "$out" | paste -sd' ' -)
  case "$rc" in
    0)
      [ "$n" -gt 0 ] || continue
      if [ -n "$check" ]; then
        owed=$((owed + 1))
        echo "$PROG: $a — $n child(ren) lack the edge: $ids"
      else
        joined=$((joined + n))
        echo "$PROG: $a — joined $n child(ren): $ids"
      fi ;;
    1)
      failed=$((failed + 1)); joined=$((joined + n))
      echo "$PROG: $a — not every child joined${ids:+ (joined: $ids)}; bd's refusals are above" >&2 ;;
    *)
      unreadable=$((unreadable + 1))
      echo "$PROG: $a — its children did not read; nothing joined" >&2 ;;
  esac
done

if [ "$MODE" = --check ]; then
  if _bd_store_joined; then marked="marked joined"; else marked="not marked joined"; fi
  echo "$PROG: checked $visited anchor(s); $owed missing an edge, $unreadable unreadable, $skipped skipped; the store is $marked"
else
  echo "$PROG: visited $visited anchor(s); joined $joined child(ren); $failed anchor(s) not fully joined, $unreadable unreadable, $skipped skipped"
fi
[ "$unreadable" -eq 0 ] || exit 2
[ "$failed" -eq 0 ] && [ "$owed" -eq 0 ] || exit 1
[ "$MODE" = --mark ] || exit 0

if [ "$joined" -gt 0 ]; then
  echo "$PROG: the run joined $joined child(ren), so the store is not marked; run --mark again once no writer files a child without its edge"
  exit 3
fi
stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gc bd kv set "$ANCHOR_JOINED_KEY" "$stamp" </dev/null >/dev/null 2>&1 || true
if GC_RECONCILE_BD_CACHE="" _bd_store_joined; then
  echo "$PROG: marked the store joined ($ANCHOR_JOINED_KEY=$stamp)"
  exit 0
fi
echo "$PROG: the mark did not land ($ANCHOR_JOINED_KEY does not read back); the store still reads closed children by anchor_bead" >&2
exit 1
