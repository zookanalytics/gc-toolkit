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
#   --check-merge  the files under assets/scripts/ that merging <head> into
#                  <base> removes, tests aside, and for each the formulas at
#                  <base> or at <head> that still name it and the open steps
#                  that call it.
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
# A text names a script when it holds the file name with no letter, digit,
# dot, dash or underscore on either side. A step is a bead carrying
# gc.step_ref, in any status but closed. The stores are those of every rig
# `gc rig list` names, the city's own among them. The formulas are the files
# under formulas/ and under each sub-pack's packs/<name>/formulas/.
#
# Callers: gctk merge (services/gctk/internal/cli/merge.go), which holds a pull
# request's merge on every exit but 0, and anyone about to remove a script.
#
# Exit: 0 no open step calls the scripts, or the merge removes no script that a
#       formula names or an open step calls · 1 a formula at <base> or <head>
#       names a script the merge removes · 2 usage, or a revision, the rig list
#       or a store could not be read, so nothing was decided · 3 open steps
#       call the scripts, or a script the merge removes
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

# callers <script>... — collect each open step that names one of the scripts,
# in every store of the city, one line per step in CALLER_LINES, and count them
# in NCALLERS. A rig list or a store that cannot be read ends the script with
# exit 2.
NCALLERS=0; CALLER_LINES=""
callers() {
  local rigs rig path name rows lines
  rigs=$("$HERE/rig-map.sh" | jq -r '.rigs[]? | objects | select((.name // "") != "" and (.path // "") != "") | [.name, .path] | @tsv') \
    || fail "cannot read the city's rigs (gc rig list --json)"
  [ -n "$rigs" ] || fail "the city lists no rig, so no store was read"
  while IFS=$'\t' read -r rig path; do
    for name in "$@"; do
      rows=$(bd_list --db "$path/.beads" --has-metadata-key gc.step_ref --status "$LIVE_STATUSES" --desc-contains "$name") \
        || fail "cannot read the open steps in the store of rig '$rig' ($path/.beads)"
      lines=$(printf '%s' "$rows" | jq -r --arg s "$name" --arg re "$(name_re "$name")" --arg rig "$rig" '
        .[] | select((.description // "") | test($re))
        | "\($s): step \(.id) (\(.metadata["gc.step_ref"] // "?"), \(.status), \(.assignee // "" | if . == "" then "unassigned" else . end)) in run \(.metadata["gc.root_bead_id"] // "?"), store of rig \($rig)"') \
        || fail "cannot read the open steps in the store of rig '$rig' ($path/.beads)"
      [ -n "$lines" ] || continue
      CALLER_LINES="$CALLER_LINES$lines"$'\n'
      NCALLERS=$((NCALLERS + $(printf '%s\n' "$lines" | wc -l)))
    done
  done <<< "$rigs"
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

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository: $ROOT"
for rev in "$MERGE_BASE" "$MERGE_HEAD"; do
  git -C "$ROOT" rev-parse --verify --quiet "$rev^{commit}" >/dev/null || fail "'$rev' names no commit in $ROOT; fetch it first"
done
# The change's own deletions, from where it left <base>, that <base> still
# carries. A rename deletes the old path.
REMOVED=$(git -C "$ROOT" diff --name-only --no-renames --diff-filter=D "$MERGE_BASE...$MERGE_HEAD" -- assets/scripts) \
  || fail "cannot list what '$MERGE_HEAD' removes from '$MERGE_BASE'"
PATHS=(); NAMES=(); NREMOVED=0
while IFS= read -r p; do
  case "$p" in ''|*.test.sh|*/testdata/*) continue ;; esac
  git -C "$ROOT" cat-file -e "$MERGE_BASE:$p" 2>/dev/null || continue
  PATHS+=("$p"); NAMES+=("${p##*/}"); NREMOVED=$((NREMOVED + 1))
done <<< "$REMOVED"
if [ "$NREMOVED" -eq 0 ]; then
  echo "the merge removes no pack script"
  exit 0
fi

# named_in <rev> <script> — the formula files at <rev> that name the script.
named_in() {
  local out rc line
  out=$(git -C "$ROOT" grep -I -l -E -e "$(name_re "$2")" "$1" -- formulas packs 2>/dev/null); rc=$?
  case "$rc" in
    0) ;;
    1) return 0 ;;
    *) fail "cannot read the formulas at '$1'" ;;
  esac
  while IFS= read -r line; do
    line="${line#"$1":}"
    case "$line" in formulas/*|packs/*/formulas/*) printf '%s\n' "$line" ;; esac
  done <<< "$out"
}

NAMED=0; NAMED_LINES=""
for i in "${!PATHS[@]}"; do
  for side in base head; do
    if [ "$side" = base ]; then rev="$MERGE_BASE"; else rev="$MERGE_HEAD"; fi
    files=$(named_in "$rev" "${NAMES[$i]}") || exit 2
    [ -n "$files" ] || continue
    while IFS= read -r f; do
      NAMED_LINES="$NAMED_LINES${PATHS[$i]}: the merge removes it, and $f at the $side ($rev) still names it"$'\n'
      NAMED=$((NAMED + 1))
    done <<< "$files"
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
