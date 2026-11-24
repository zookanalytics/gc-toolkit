#!/usr/bin/env bash
# lint-change.sh — the repository's lint, which the Makefile at the root names:
# `make lint` runs `lint-change.sh <base>`.
#
#   lint-change.sh BASE
#
# It reads the change HEAD's commits make since BASE, a ref such as
# origin/main, as the files `git diff --name-only BASE...HEAD` names. From the
# root, it runs tools/lint-learned.sh and then tools/lint.sh, each given those
# files, and each says in its header what it checks in them and what it checks
# whatever it is given. Both run, so one run reports every finding, and the run
# fails when either fails. A change that names no file gives each of them none,
# and lint-learned.sh then lints every tracked file.
#
# exit: 0 both passed · 1 either failed · 2 usage, or a BASE git cannot read

set -uo pipefail

PROG="lint-change"
usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$PROG: not inside a git repository ($HERE)" >&2; exit 2; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') echo "$PROG: needs a base, such as origin/main" >&2; exit 2 ;;
  -*) echo "$PROG: needs a base, such as origin/main, not the option '$1'" >&2; exit 2 ;;
esac
[ "$#" -eq 1 ] || { echo "$PROG: takes one base, not $#: $*" >&2; exit 2; }
BASE="$1"

cd "$ROOT" || { echo "$PROG: cannot enter the root $ROOT" >&2; exit 2; }

# git writes the names NUL-separated, so a name with a space arrives as one
# file, and a name git would quote, such as one with a non-ASCII character or a
# tab, arrives as it is.
change_file="$(mktemp "${TMPDIR:-/tmp}/lint-change.XXXXXX")" || {
  echo "$PROG: mktemp failed" >&2; exit 2; }
if ! git diff --no-color --name-only -z "${BASE}...HEAD" -- >"$change_file"; then
  rm -f "$change_file"
  echo "$PROG: cannot read the change from $BASE to HEAD (git diff ${BASE}...HEAD failed)" >&2
  exit 2
fi
files=()
while IFS= read -r -d '' path; do files+=("$path"); done <"$change_file" || {
  rm -f "$change_file"
  echo "$PROG: cannot read back the change's files from $change_file" >&2
  exit 2
}
rm -f "$change_file"

rc=0
tools/lint-learned.sh ${files[@]+"${files[@]}"} || rc=1
tools/lint.sh ${files[@]+"${files[@]}"} || rc=1
exit "$rc"
