#!/usr/bin/env bash
# review-charter — read the gate menu out of a repo's review charter and emit
# it as TSV, one row per gate: <gate>\t<method>\t<mandatory paths>\t<waivable>.
# The menu is a declared table (docs/review-charter.md, "## Gate menu"); this
# is the ONE parser of that grammar, so the triage method, signoff.sh and the
# menu-agreement test all read the same rows.
#   review-charter.sh --file <charter> [--gate <name>]
# Mandatory paths come back space-separated, `-` for none; a path pattern is
# an exact path or a `dir/**` prefix, never a general glob. Waivable is
# yes|no, and anything unparseable reads `no`: a narrowing warrant must be
# declared, never inferred.
# Callers: signoff.sh, skills/review-triage, review-dispatch-body.test.sh.
# Exit: 0 rows emitted · 1 no readable menu (or --gate not in it) · 2 usage.
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: review-charter.sh --file <charter-path> [--gate <name>]

  --file  the charter to read (docs/review-charter.md in the reviewed repo)
  --gate  emit only this gate's row; exit 1 when the menu does not declare it

Output: TSV — gate, method, mandatory paths (space-separated, `-` for none),
waivable (yes|no).
U
}

FILE=""; ONLY_GATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --gate) ONLY_GATE="${2:-}"; shift 2 || { usage; exit 2; } ;;
    -h|--help) usage; exit 2 ;;
    *) echo "review-charter: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ -n "$FILE" ] || { usage; exit 2; }
[ -r "$FILE" ] || { echo "review-charter: no readable charter at '$FILE'" >&2; exit 1; }

ROWS=$(awk '
function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
function clean(s) { gsub(/`/, "", s); return trim(s) }
function is_rule(s,   t) { t = clean(s); return (t ~ /^:?-+:?$/) }
BEGIN { FS = "|"; state = 0 }
{
  if ($0 !~ /^[[:space:]]*\|/) { if (state == 2) exit; next }
  # $1 is the empty span before the leading pipe; cells start at $2.
  if (state == 0) { if (tolower(clean($2)) == "gate") state = 1; next }
  if (state == 1) { if (is_rule($2)) state = 2; else state = 0; next }
  gate = clean($2); method = clean($4); paths = clean($5); waivable = tolower(clean($6))
  if (gate == "") next
  if (paths == "" || paths == "-" || paths == "\342\200\224") paths = "-"
  if (waivable != "yes") waivable = "no"
  printf "%s\t%s\t%s\t%s\n", gate, method, paths, waivable
}' "$FILE" 2>/dev/null)

if [ -z "$ROWS" ]; then
  echo "review-charter: '$FILE' declares no parseable gate menu" >&2
  exit 1
fi

if [ -n "$ONLY_GATE" ]; then
  ROW=$(printf '%s\n' "$ROWS" | awk -F'\t' -v g="$ONLY_GATE" '$1 == g { print; exit }')
  [ -n "$ROW" ] || { echo "review-charter: '$FILE' does not declare gate '$ONLY_GATE'" >&2; exit 1; }
  printf '%s\n' "$ROW"
  exit 0
fi
printf '%s\n' "$ROWS"
exit 0
