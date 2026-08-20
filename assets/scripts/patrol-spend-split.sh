#!/bin/sh
# patrol-spend-split.sh — model-call split by role over a 24h window.
#
# Exists so the before/after windows for tk-2qa85 are taken the SAME way. The
# cadence audit (tk-svgtz) had one adjacent number corrected in review precisely
# because the counting method lived only in a shell history; this is that method,
# committed.
#
# Counts usage records with kind="model" — i.e. model CALLS, not output tokens.
# The two orderings differ: measured as output tokens over 7 days polecats
# dominate, measured as calls over 24h the always-on patrol roles do. That
# difference is the whole subject of tk-2qa85.
#
# Usage:
#   patrol-spend-split.sh              # the last 24h
#   patrol-spend-split.sh <epoch>      # the 24h ending at <epoch> seconds
#   USAGE=/path/to/usage.jsonl patrol-spend-split.sh
#
# Roles are matched on the worker name, which carries the role for named
# sessions ("gascity--gc-toolkit__witness") and for pool workers
# ("gc-toolkit__polecat-lx-t7ug7"). polecat-codex counts as a polecat.

set -u

USAGE="${USAGE:-${GC_CITY:-/home/zook/loomington}/.gc/usage.jsonl}"
END="${1:-$(date +%s)}"
START=$((END - 86400))

[ -r "$USAGE" ] || { echo "patrol-spend-split: cannot read $USAGE" >&2; exit 1; }

echo "window: $(date -u -d "@$START" +%Y-%m-%dT%H:%M:%SZ) .. $(date -u -d "@$END" +%Y-%m-%dT%H:%M:%SZ)  (kind=model)"

jq -r --argjson s "$START" --argjson e "$END" '
  select(.kind == "model")
  | select((.at / 1000) >= $s and (.at / 1000) < $e)
  | .worker
' "$USAGE" 2>/dev/null | awk '
  /witness/  { w++; next }
  /deacon/   { d++; next }
  /polecat/  { p++; next }
  /refinery/ { r++; next }
             { o++ }
  END {
    t = w + d + p + r + o
    if (t == 0) { print "  (no model records in window)"; exit }
    printf "  witnesses (4)   %7d  %5.1f%%\n", w, 100 * w / t
    printf "  deacon          %7d  %5.1f%%\n", d, 100 * d / t
    printf "    -> combined   %7d  %5.1f%%\n", w + d, 100 * (w + d) / t
    printf "  polecats        %7d  %5.1f%%\n", p, 100 * p / t
    printf "  refinery        %7d  %5.1f%%\n", r, 100 * r / t
    printf "  everything else %7d  %5.1f%%\n", o, 100 * o / t
    printf "  TOTAL           %7d\n", t
  }'
