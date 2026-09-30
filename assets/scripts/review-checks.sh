#!/usr/bin/env bash
# review-checks — read the check index out of a repo and emit it as TSV, one
# row per check: <check>\t<method>\t<purpose>. The index is review-checks.toml
# at the repo root; this is the ONE parser of that grammar, so the triage
# method, signoff.sh and the index-agreement test all read the same rows.
#   review-checks.sh --file <index> [--check <name>]
# The index declares mechanical facts only — a check's name, a pointer to the
# method that governs it, and one line of purpose. When a check applies is a
# judgment its method states in prose, not a column here, so this parser reads
# no applies-when and no mandatory-paths field.
# Callers: signoff.sh, skills/review-triage, review-checks.test.sh.
# Exit: 0 rows emitted · 1 no readable index, or --check not declared · 2 usage.
set -uo pipefail

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

FILE=""; ONLY_CHECK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file)    FILE="${2:-}";       shift 2 || { usage >&2; exit 2; } ;;
    --check)   ONLY_CHECK="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    -h|--help) usage; exit 2 ;;
    *) echo "review-checks: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$FILE" ] || { usage >&2; exit 2; }
[ -r "$FILE" ] || { echo "review-checks: no readable index at '$FILE'" >&2; exit 1; }

# A check is a [checks.<name>] table with `method` and `purpose` string keys.
# The grammar is a minimal TOML subset: table headers, `key = "value"` lines,
# `#` comments, and blank lines. A value's surrounding double quotes are
# stripped; any other table ends the checks context so a stray key outside a
# [checks.*] header is never read into a check.
ROWS=$(awk '
function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
function val(l,   v) {
  v = l; sub(/^[^=]*=[[:space:]]*/, "", v)
  v = trim(v)
  sub(/^"/, "", v); sub(/"$/, "", v)
  return v
}
function flush() {
  if (name != "") printf "%s\t%s\t%s\n", name, method, purpose
  name = ""; method = ""; purpose = ""
}
/^[[:space:]]*#/ { next }
/^[[:space:]]*\[/ {
  flush()
  if ($0 ~ /^[[:space:]]*\[checks\.[A-Za-z0-9_-]+\][[:space:]]*$/) {
    h = $0; sub(/^[[:space:]]*\[checks\./, "", h); sub(/\][[:space:]]*$/, "", h)
    name = h
  }
  next
}
name != "" && /^[[:space:]]*method[[:space:]]*=/  { method  = val($0); next }
name != "" && /^[[:space:]]*purpose[[:space:]]*=/ { purpose = val($0); next }
END { flush() }
' "$FILE")

if [ -z "$ROWS" ]; then
  echo "review-checks: '$FILE' declares no checks" >&2
  exit 1
fi

if [ -n "$ONLY_CHECK" ]; then
  ROW=$(printf '%s\n' "$ROWS" | awk -F'\t' -v c="$ONLY_CHECK" '$1 == c { print; exit }')
  [ -n "$ROW" ] || { echo "review-checks: '$FILE' does not declare check '$ONLY_CHECK'" >&2; exit 1; }
  printf '%s\n' "$ROW"
  exit 0
fi
printf '%s\n' "$ROWS"
exit 0
