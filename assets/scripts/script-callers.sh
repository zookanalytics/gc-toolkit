#!/usr/bin/env bash
# script-callers.sh — the open steps whose poured text calls a pack script, in
# every store of the city, and whether a merge may remove a script yet.
#   script-callers.sh [--root <dir>] <script>...
#   script-callers.sh [--root <dir>] --check-merge <base> <head>
#
#   <script>...    each open step whose text names one of the scripts, given by
#                  file name (foo.sh), one line per step: the script, the step
#                  with its step ref, status and assignee, the run's root, the
#                  rig whose store holds it and whether it is suspended, and any
#                  gate that parks its run.
#   --check-merge  the pack scripts that merging <head> into <base> removes,
#                  and for each the formulas at <base>, at <head> or, failing
#                  those, at the checkout's HEAD that still name it and the open
#                  steps that call it.
#   --root <dir>   the repository <base> and <head> are read in, the current
#                  directory's by default.
#
# A run keeps the step text it was poured with, and that text calls the pack's
# scripts from the city's copy of the pack as each step runs. Once a merge that
# removes a script reaches that copy, every open step that names the script
# stops at it. While a formula at <base> or <head> names the script, every run
# poured before the merge reaches the city calls it too, so no wait clears it:
# the change keeps a file at that path, a hand-off to what replaces the script,
# and a later change removes it. A script that only open steps call is clear to
# remove once their runs end.
#
# The checkout's HEAD counts because a city that imports the pack from a
# checkout pours its runs from the formulas there, and the checkout reaches
# the base only when it is fast-forwarded. gctk merge runs in the rig checkout
# this pack is imported from, so a formula the base has stopped naming still
# pours runs that call the script until that checkout moves. The fast-forward
# clears it, so when only the checkout names the script the merge waits for it,
# and nothing on the change has to move.
#
# A run is parked when one of its open steps is blocked by a gate a person holds.
# The edge sits on one step and its later steps wait on the step before them, so
# a run is judged whole, and it ends only once a person releases the gate or
# cancels the run. A gate a person holds is any gate the city does not close by
# itself: a human gate, and a park, which carries no await type. A timer gate and
# a gate on a GitHub run or pull request close on their own (core's gate-sweep).
# A run in a suspended rig is parked too: the reconciler skips the rig's agents
# and gc hook returns empty, so nothing works the run until a person resumes the
# rig or cancels the run.
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
#       formula names or an open step calls · 1 a formula at <base> or at <head>
#       names a script the merge removes · 2 usage, or a revision, the checkout's
#       HEAD, the rig list, a store or a loop's input could not be read, so
#       nothing was decided · 3 open steps call the scripts, or a script the
#       merge removes, and none of their runs is parked · 4 only the checkout's
#       HEAD names a script the merge removes · 5 as 3, and at least one of their
#       runs is parked
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

# store_parks <rig> <path> <rows> — the store's parked runs, as one JSON object
# from a run's root, or a step's id where it names none, to the gates that hold
# it. <rows> are the store's open steps, whose edges a list row carries. A store
# whose gates cannot be read ends the script with exit 2, through its caller.
store_parks() {
  local gates parks
  gates=$(bd_list --db "$2/.beads" --type gate --include-gates --status "$LIVE_STATUSES") \
    || fail "cannot read the gates in the store of rig '$1' ($2/.beads)"
  parks=$(printf '%s\n%s' "$3" "$gates" | jq -cn '
    input as $rows | input as $gates
    | [ $gates[] | ((.await_type // "") | tostring) as $await
        | select(($await == "timer" or ($await | startswith("gh:run")) or ($await | startswith("gh:pr"))) | not)
        | .id ] as $held
    | reduce ($rows[] | (.metadata["gc.root_bead_id"] // .id) as $run
              | (.dependencies // [])[]
              | select(.type == "blocks")
              | .depends_on_id as $gate
              | select($held | index($gate))
              | {run: $run, gate: $gate}) as $edge
        ({}; .[$edge.run] = (((.[$edge.run] // []) + [$edge.gate]) | unique))') \
    || fail "cannot read the gates in the store of rig '$1' ($2/.beads)"
  printf '%s' "$parks"
}

# callers <script>... — collect each open step that names one of the scripts,
# in every store of the city, one line per step in CALLER_LINES, and count them
# in NCALLERS. Each store is read once, so the cost does not grow with the
# scripts asked about. A store that holds a caller has its gates read once too:
# NPARKED counts the callers in a parked run, PARKED_GATES names the gates that
# park them and PARKED_RIGS the suspended rigs that do, each space-separated. A
# rig list or a store that cannot be read ends the script with exit 2.
NCALLERS=0; CALLER_LINES=""; NPARKED=0; PARKED_GATES=""; PARKED_RIGS=""
callers() {
  local rigs suspended rig path where name rows hits parks parked gate lines newlines count read_lines=0
  rigs=$("$HERE/rig-map.sh" | jq -r '.rigs[] | [(.suspended // false), .name, .path] | @tsv') \
    || fail "cannot read the city's rigs (gc rig list --json)"
  [ -n "$rigs" ] || fail "the city lists no rig, so no store was read"
  loop_input "$rigs"
  while IFS=$'\t' read -r suspended rig path; do
    read_lines=$((read_lines + 1))
    where="store of rig $rig"
    [ "$suspended" != true ] || where="$where, which is suspended"
    rows=$(bd_list --db "$path/.beads" --has-metadata-key gc.step_ref --status "$LIVE_STATUSES") \
      || fail "cannot read the open steps in the store of rig '$rig' ($path/.beads)"
    parks=""
    for name in "$@"; do
      hits=$(printf '%s' "$rows" | jq -c --arg re "$(name_re "$name")" '
        [ .[] | select((.description // "") | test($re))
          | { id, status, assignee: (.assignee // ""), ref: (.metadata["gc.step_ref"] // "?"),
              root: (.metadata["gc.root_bead_id"] // "?"), run: (.metadata["gc.root_bead_id"] // .id) } ]') \
        || fail "cannot read the open steps in the store of rig '$rig' ($path/.beads)"
      [ "$hits" != "[]" ] || continue
      [ -n "$parks" ] || parks=$(store_parks "$rig" "$path" "$rows") || exit 2
      lines=$(printf '%s' "$hits" | jq -r --arg s "$name" --arg where "$where" --argjson parks "$parks" '
        .[] | "\($s): step \(.id) (\(.ref), \(.status), \(if .assignee == "" then "unassigned" else .assignee end)) in run \(.root), \($where)"
              + (if $parks[.run] then ", parked behind " + ($parks[.run] | join(", ")) else "" end)') \
        || fail "cannot read the open steps in the store of rig '$rig' ($path/.beads)"
      parked=$(printf '%s' "$hits" | jq -r --argjson parks "$parks" '
        [ .[] | $parks[.run] // empty ] | "\(length) \(map(.[]) | unique | join(" "))"') \
        || fail "cannot read the open steps in the store of rig '$rig' ($path/.beads)"
      CALLER_LINES="$CALLER_LINES$lines"$'\n'
      newlines=${lines//[!$'\n']/}
      count=$((${#newlines} + 1))
      NCALLERS=$((NCALLERS + count))
      if [ "$suspended" = true ]; then
        NPARKED=$((NPARKED + count))
        case " $PARKED_RIGS " in
          *" $rig "*) ;;
          *) PARKED_RIGS="$PARKED_RIGS${PARKED_RIGS:+ }$rig" ;;
        esac
      else
        NPARKED=$((NPARKED + ${parked%% *}))
      fi
      for gate in ${parked#* }; do
        case " $PARKED_GATES " in
          *" $gate "*) ;;
          *) PARKED_GATES="$PARKED_GATES${PARKED_GATES:+ }$gate" ;;
        esac
      done
    done
  done < "$LOOP_FILE"
  [ "$read_lines" -eq "$LOOP_LINES" ] || fail "read $read_lines of the $LOOP_LINES rigs the city lists"
}

# parked_words — set PARKED_WHAT to what parks the callers NPARKED counts, and
# PARKED_ENDS to what ends that wait.
PARKED_WHAT=""; PARKED_ENDS=""
parked_words() {
  local gates=${PARKED_GATES// /, } rigs=${PARKED_RIGS// /, }
  if [ -n "$gates" ] && [ -n "$rigs" ]; then
    PARKED_WHAT="runs a person's gate parks ($gates) or in runs of a suspended rig ($rigs)"
    PARKED_ENDS="Release each gate, resume each rig or cancel each such run, and the merge goes on."
  elif [ -n "$rigs" ]; then
    PARKED_WHAT="runs of a suspended rig ($rigs)"
    PARKED_ENDS="Resume each rig or cancel each of its runs, and the merge goes on."
  else
    PARKED_WHAT="runs a person's gate parks ($gates)"
    PARKED_ENDS="Release each gate or cancel each parked run, and the merge goes on."
  fi
}

if [ -z "$CHECK_MERGE" ]; then
  callers "${SCRIPTS[@]}"
  if [ "$NPARKED" -gt 0 ]; then
    parked_words
    echo "$NCALLERS open step(s) call ${SCRIPTS[*]}, and $NPARKED of them sit in $PARKED_WHAT"
    printf '%s' "$CALLER_LINES"
    exit 5
  fi
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

# named_on <rev> <where> — named_in for every script the merge removes.
named_on() {
  local i
  for i in "${!PATHS[@]}"; do
    named_in "$1" "$2" "${PATHS[$i]}" "${NAMES[$i]}"
  done
}

named_on "$MERGE_BASE" "the base ($MERGE_BASE)"
named_on "$MERGE_HEAD" "the head ($MERGE_HEAD)"
if [ "$NAMED" -gt 0 ]; then
  echo "$NAMED formula file(s) name a script the merge removes. A formula that names a removed script pours runs that call it until the merge reaches the city, so no wait clears this. Keep a file at each such path, a hand-off to what replaces it, and remove it in a later change once no formula names it and $PROG lists no open step that calls it."
  printf '%s' "$NAMED_LINES"
  exit 1
fi
if [ "$CHECKOUT_OID" != "$BASE_OID" ] && [ "$CHECKOUT_OID" != "$HEAD_OID" ]; then
  named_on "$CHECKOUT_OID" "the checkout's HEAD (${CHECKOUT_OID:0:12})"
  if [ "$NAMED" -gt 0 ]; then
    echo "$NAMED formula file(s) at the checkout's HEAD name a script the merge removes, and neither side of the merge does. The checkout stops naming it once it is fast-forwarded to the base, so the merge waits for that, and nobody has to act."
    printf '%s' "$NAMED_LINES"
    exit 4
  fi
fi

callers "${NAMES[@]}"
if [ "$NPARKED" -gt 0 ]; then
  parked_words
  echo "$NCALLERS open step(s) call a script the merge removes (${PATHS[*]}), and $NPARKED of them sit in $PARKED_WHAT. $PARKED_ENDS"
  printf '%s' "$CALLER_LINES"
  exit 5
fi
if [ "$NCALLERS" -gt 0 ]; then
  echo "$NCALLERS open step(s) call a script the merge removes (${PATHS[*]}). The merge waits for their runs to end, unless the change keeps a file at each path."
  printf '%s' "$CALLER_LINES"
  exit 3
fi
echo "the merge removes ${PATHS[*]}; no formula names them and no open step calls them"
exit 0
