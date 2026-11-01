#!/usr/bin/env bash
# script-callers.sh — the open steps whose poured text calls a pack script, in
# every store of the city, and whether a merge may remove a script yet.
#   script-callers.sh [--root <dir>] <script>...
#   script-callers.sh [--root <dir>] --check-merge <base> <head>
#
#   <script>...    each open step whose text names one of the scripts, given by
#                  file name (foo.sh), one line per step: the script, the step
#                  with its step ref, status and assignee, the run's root, and
#                  the rig whose store holds it.
#   --check-merge  the pack scripts that merging <head> into <base> removes,
#                  and for each the formulas at <base>, at <head> or at the
#                  checkout's HEAD that still name it and the open steps that
#                  call it.
#   --root <dir>   the repository <base> and <head> are read in, the current
#                  directory's by default.
#
# A run keeps the step text it was poured with, and that text calls the pack's
# scripts from the city's copy of the pack as each step runs. Once a merge that
# removes a script reaches that copy, every open step that names the script
# stops at it. While a formula still names the script, every run poured before
# the merge reaches the city calls it too, so no wait clears it: the change
# keeps a file at that path, a hand-off to what replaces the script, and a
# later change removes it. A script that only open steps call is clear to
# remove once their runs end.
#
# The checkout's HEAD counts because a city that imports the pack from a
# checkout pours its runs from the formulas there, and the checkout reaches
# the base only when it is fast-forwarded. gctk merge runs in the rig checkout
# this pack is imported from, so a formula the base has stopped naming still
# pours runs that call the script until that checkout moves.
#
# A text names a script when it holds the file name with no letter, digit,
# dot, dash or underscore on either side. A step is a bead carrying
# gc.step_ref, in any status but closed. The stores are those of every rig
# `gc rig list` names, the city's own among them. The pack scripts are the
# files under assets/scripts/ and under each sub-pack's
# packs/<name>/assets/scripts/, tests aside. The formulas are the files under
# formulas/ and under each sub-pack's packs/<name>/formulas/.
#
# Callers: gctk merge (services/gctk/internal/cli/merge.go), which asks about a
# pull request into the default branch and holds its merge on every exit but 0,
# and anyone about to remove a script.
#
# Exit: 0 no open step calls the scripts, or the merge removes no script that a
#       formula names or an open step calls · 1 a formula at <base>, at <head>
#       or at the checkout's HEAD names a script the merge removes · 2 usage, or
#       a revision, the checkout's HEAD, the rig list, a store or a loop's input
#       could not be read, so nothing was decided · 3 open steps call the
#       scripts, or a script the merge removes
set -uo pipefail

PROG="script-callers"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 2; }

usage() {
  [ -z "${1:-}" ] || echo "$PROG: $1" >&2
  echo "usage: $PROG [--root <dir>] <script>... | $PROG [--root <dir>] --check-merge <base> <head>" >&2
  exit 2
}
fail() { echo "$PROG: $1; nothing was decided" >&2; exit 2; }

# Every status a step holds until it closes.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
# The characters a script's file name is made of. A name with no other
# character on either side is the script.
NAME_CHARS="A-Za-z0-9_.-"

ROOT="."; MERGE_BASE=""; MERGE_HEAD=""; CHECK_MERGE=""; SCRIPTS=(); NSCRIPTS=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --check-merge)
      [ "$#" -ge 3 ] && [ -n "$2" ] && [ -n "$3" ] || usage "--check-merge needs <base> <head>"
      CHECK_MERGE=1; MERGE_BASE="$2"; MERGE_HEAD="$3"; shift 3 ;;
    -h|--help) usage ;;
    -*) usage "unknown option '$1'" ;;
    *)
      case "$1" in
        *[!A-Za-z0-9_.-]*) usage "'$1' is not a script's file name" ;;
      esac
      SCRIPTS+=("$1"); NSCRIPTS=$((NSCRIPTS + 1)); shift ;;
  esac
done
if [ -n "$CHECK_MERGE" ]; then
  [ "$NSCRIPTS" -eq 0 ] || usage "--check-merge takes no script names"
else
  [ "$NSCRIPTS" -gt 0 ] || usage "name a script, or --check-merge <base> <head>"
fi

# name_re <script> — the extended regular expression that finds the script's
# name in a text.
name_re() {
  printf '(^|[^%s])%s([^%s]|$)' "$NAME_CHARS" "$(printf '%s' "$1" | sed 's/\./\\./g')" "$NAME_CHARS"
}

# A loop that falls through answers for every line of its list, so it must have
# read every line. bash backs a large here-string with a temp file it creates
# silently, and a loop whose redirection fails runs zero times. So each list goes
# through a checked temp file, and a loop that read fewer lines than the list
# holds decides nothing. The loops do not nest, so they share one file.
LOOP_FILE=""; LOOP_LINES=0
trap '[ -z "$LOOP_FILE" ] || rm -f "$LOOP_FILE"' EXIT

# loop_input <list> — write a list that is not empty to LOOP_FILE for the next
# loop to read, and count its lines in LOOP_LINES.
loop_input() {
  local newlines=${1//[!$'\n']/}
  [ -n "$LOOP_FILE" ] || LOOP_FILE=$(mktemp "${TMPDIR:-/tmp}/gctk-script-callers.XXXXXX") \
    || fail "cannot create a temp file for a loop's input"
  printf '%s\n' "$1" > "$LOOP_FILE" || fail "cannot write a loop's input to $LOOP_FILE"
  LOOP_LINES=$(( ${#newlines} + 1 ))
}

# callers <script>... — collect each open step that names one of the scripts,
# in every store of the city, one line per step in CALLER_LINES, and count them
# in NCALLERS. Each store is read once, so the cost does not grow with the
# scripts asked about. A rig list or a store that cannot be read ends the script
# with exit 2.
NCALLERS=0; CALLER_LINES=""
callers() {
  local rigs rig path name rows lines newlines read_lines=0
  rigs=$("$HERE/rig-map.sh" | jq -r '.rigs[] | [.name, .path] | @tsv') \
    || fail "cannot read the city's rigs (gc rig list --json)"
  [ -n "$rigs" ] || fail "the city lists no rig, so no store was read"
  loop_input "$rigs"
  while IFS=$'\t' read -r rig path; do
    read_lines=$((read_lines + 1))
    rows=$(bd_list --db "$path/.beads" --has-metadata-key gc.step_ref --status "$LIVE_STATUSES") \
      || fail "cannot read the open steps in the store of rig '$rig' ($path/.beads)"
    for name in "$@"; do
      lines=$(printf '%s' "$rows" | jq -r --arg s "$name" --arg re "$(name_re "$name")" --arg rig "$rig" '
        .[] | select((.description // "") | test($re))
        | "\($s): step \(.id) (\(.metadata["gc.step_ref"] // "?"), \(.status), \(.assignee // "" | if . == "" then "unassigned" else . end)) in run \(.metadata["gc.root_bead_id"] // "?"), store of rig \($rig)"') \
        || fail "cannot read the open steps in the store of rig '$rig' ($path/.beads)"
      [ -n "$lines" ] || continue
      CALLER_LINES="$CALLER_LINES$lines"$'\n'
      newlines=${lines//[!$'\n']/}
      NCALLERS=$((NCALLERS + ${#newlines} + 1))
    done
  done < "$LOOP_FILE"
  [ "$read_lines" -eq "$LOOP_LINES" ] || fail "read $read_lines of the $LOOP_LINES rigs the city lists"
}

if [ -z "$CHECK_MERGE" ]; then
  callers "${SCRIPTS[@]}"
  if [ "$NCALLERS" -gt 0 ]; then
    echo "$NCALLERS open step(s) call ${SCRIPTS[*]}"
    printf '%s' "$CALLER_LINES"
    exit 3
  fi
  echo "no open step calls ${SCRIPTS[*]}"
  exit 0
fi

# Every path below is read from the top of the checkout, wherever <dir> sits in
# it. A pathspec is relative to the directory git runs in, so from below the top
# the deletions read empty and the merge seems to remove nothing.
TOP=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) || fail "not a git checkout: $ROOT"
ROOT=$TOP
BASE_OID=$(git -C "$ROOT" rev-parse --verify --quiet "$MERGE_BASE^{commit}") || fail "'$MERGE_BASE' names no commit in $ROOT; fetch it first"
HEAD_OID=$(git -C "$ROOT" rev-parse --verify --quiet "$MERGE_HEAD^{commit}") || fail "'$MERGE_HEAD' names no commit in $ROOT; fetch it first"
CHECKOUT_OID=$(git -C "$ROOT" rev-parse --verify --quiet "HEAD^{commit}") || fail "the checkout in $ROOT has no HEAD commit"
# The change's own deletions of pack scripts, from where it left <base>, that
# <base> still carries. A rename deletes the old path.
REMOVED=$(git -C "$ROOT" diff --name-only --no-renames --diff-filter=D "$MERGE_BASE...$MERGE_HEAD" -- assets/scripts packs) \
  || fail "cannot list what '$MERGE_HEAD' removes from '$MERGE_BASE'"
PATHS=(); NAMES=(); NREMOVED=0
if [ -n "$REMOVED" ]; then
  loop_input "$REMOVED"
  read_lines=0
  while IFS= read -r p; do
    read_lines=$((read_lines + 1))
    case "$p" in assets/scripts/*|packs/*/assets/scripts/*) ;; *) continue ;; esac
    case "$p" in *.test.sh|*/testdata/*) continue ;; esac
    carried=$(git -C "$ROOT" ls-tree "$MERGE_BASE" -- "$p") \
      || fail "cannot read '$p' at '$MERGE_BASE'"
    [ -n "$carried" ] || continue
    PATHS+=("$p"); NAMES+=("${p##*/}"); NREMOVED=$((NREMOVED + 1))
  done < "$LOOP_FILE"
  [ "$read_lines" -eq "$LOOP_LINES" ] || fail "read $read_lines of the $LOOP_LINES paths '$MERGE_HEAD' removes"
fi
if [ "$NREMOVED" -eq 0 ]; then
  echo "the merge removes no pack script"
  exit 0
fi

# named_in <rev> <where> <path> <script> — add each formula file at <rev> that
# names the script at <path> to NAMED_LINES, and count them in NAMED. <where>
# says which side of the merge <rev> is.
NAMED=0; NAMED_LINES=""
named_in() {
  local out rc line read_lines=0
  out=$(git -C "$ROOT" grep -I -l -E -e "$(name_re "$4")" "$1" -- formulas packs 2>/dev/null); rc=$?
  case "$rc" in
    0) ;;
    1) return 0 ;;
    *) fail "cannot read the formulas at '$1'" ;;
  esac
  loop_input "$out"
  while IFS= read -r line; do
    read_lines=$((read_lines + 1))
    line="${line#"$1":}"
    case "$line" in
      formulas/*|packs/*/formulas/*)
        NAMED_LINES="$NAMED_LINES$3: the merge removes it, and $line at $2 still names it"$'\n'
        NAMED=$((NAMED + 1)) ;;
    esac
  done < "$LOOP_FILE"
  [ "$read_lines" -eq "$LOOP_LINES" ] || fail "read $read_lines of the $LOOP_LINES files at '$1' that name $4"
}

SIDES=(base head)
[ "$CHECKOUT_OID" = "$BASE_OID" ] || [ "$CHECKOUT_OID" = "$HEAD_OID" ] || SIDES+=(checkout)
for i in "${!PATHS[@]}"; do
  for side in "${SIDES[@]}"; do
    case "$side" in
      base) rev="$MERGE_BASE"; where="the base ($MERGE_BASE)" ;;
      head) rev="$MERGE_HEAD"; where="the head ($MERGE_HEAD)" ;;
      checkout) rev="$CHECKOUT_OID"; where="the checkout's HEAD (${CHECKOUT_OID:0:12})" ;;
    esac
    named_in "$rev" "$where" "${PATHS[$i]}" "${NAMES[$i]}"
  done
done
if [ "$NAMED" -gt 0 ]; then
  echo "$NAMED formula file(s) name a script the merge removes. A formula that names a removed script pours runs that call it until the merge reaches the city, so no wait clears this. Keep a file at each such path, a hand-off to what replaces it, and remove it in a later change once no formula names it and $PROG lists no open step that calls it."
  printf '%s' "$NAMED_LINES"
  exit 1
fi

callers "${NAMES[@]}"
if [ "$NCALLERS" -gt 0 ]; then
  echo "$NCALLERS open step(s) call a script the merge removes (${PATHS[*]}). The merge waits for their runs to end, unless the change keeps a file at each path."
  printf '%s' "$CALLER_LINES"
  exit 3
fi
echo "the merge removes ${PATHS[*]}; no formula names them and no open step calls them"
exit 0
