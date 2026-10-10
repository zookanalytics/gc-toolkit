#!/usr/bin/env bash
# work-tree-holder — whether a live session is working a work bead's tree, so a
# second dispatch does not adopt a tree that a run is still using.
#
#   work-tree-holder.sh --bead <id> [--work-dir <path>] [--branch <name>]
#
# A session running mol-polecat-work never claims its work bead. The bead stays
# open and unassigned for the refinery, so its assignee cannot show a run in
# flight, and a dispatch gate that reads only the assignee lets a second
# dispatch through. workspace-setup then adopts the first run's tree. The run's
# tree is the signal the assignee is not. The work's trees are the worktree
# --work-dir names (the bead's metadata.work_dir, which workspace-setup adopts)
# and the worktree with the work's branch checked out, as `git worktree list`
# reports it. The branch is --branch, or the polecat/<bead> branch that
# workspace-setup cuts for fresh work when the bead records none.
#
# A tree inside this session's own directory ($GC_DIR) is this session's to
# resume. A tree that is another session's directory is held by that session.
# A tree under another session's directory (<dir>/worktrees/<name>) needs one
# more fact. A pool slot directory outlives the session that created a tree in
# it, and a per-bead tree stays on disk after its run hands off, so the session
# in that directory now is often on other work. Such a session holds the tree
# only while one of its claims is this work. A claim is an open or in_progress
# bead assigned to the session under any of its names. The claim is this work
# when it is the bead itself, or when it is a step of a molecule whose input
# convoy tracks a bead that is this bead, stands on this branch, or records
# this tree as its work_dir. The branch match covers the anchor and a sibling
# rework child. Directories are compared with `-ef`, because git lists a
# worktree by its resolved path and a session records the path it was given.
#
# A session absent from `gc session list --state all` is gone, and a tree with
# no listed session in its directory is adoptable. That is how a re-dispatch
# recovers a crashed run. Every input the answer depends on fails closed: a
# failed `git worktree list`, an unreadable session list or bead listing, a
# tree no session directory accounts for, and a claim whose molecule cannot be
# traced to its work.
#
# stdout: one line naming each tree outside $GC_DIR, its count of uncommitted
#         paths, and what was found; nothing when there is no such tree.
# Caller: mol-polecat-work load-context's duplicate-dispatch gate.
# exit: 0 adoptable · 1 a live session is working this work there · 2 undecided · 64 usage
set -uo pipefail

PROG="work-tree-holder"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: work-tree-holder.sh --bead <id> [--work-dir <path>] [--branch <name>]

  --bead      the work bead (required)
  --work-dir  the bead's metadata.work_dir; empty when it records none
  --branch    the bead's metadata.branch; empty means polecat/<bead>

env: GC_DIR is this session's directory; a tree inside it is this session's
     own. GC_RIG_ROOT is the repository whose worktrees are listed, and the
     current directory is used when it is unset.

exit: 0 adoptable · 1 a live session is working this work there · 2 undecided · 64 usage
USAGE
}

# `OPT="$2"; shift 2` hangs the parse loop when the option ends argv. An empty
# value is valid: the caller passes the bead's metadata as it finds it.
require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 64
  fi
  case "$2" in
    --bead|--work-dir|--branch|-h|--help)
      echo "$PROG: $1 requires a value, but the next argument is the option '$2'" >&2
      usage
      exit 64 ;;
  esac
}

BEAD=""; WORK_DIR=""; BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead)     require_value "$@"; BEAD="$2";     shift 2 ;;
    --work-dir) require_value "$@"; WORK_DIR="$2"; shift 2 ;;
    --branch)   require_value "$@"; BRANCH="$2";   shift 2 ;;
    -h|--help)  usage; exit 64 ;;
    *)          echo "$PROG: unknown argument '$1'" >&2; usage; exit 64 ;;
  esac
done
if [ -z "$BEAD" ]; then
  echo "$PROG: --bead is required" >&2
  usage
  exit 64
fi

NL='
'
US=$(printf '\037')
LOOKUP_BRANCH="${BRANCH:-polecat/$BEAD}"
REPO="${GC_RIG_ROOT:-.}"
OWN_DIR=$(cd "${GC_DIR:-.}" 2>/dev/null && pwd -P) || OWN_DIR=""

if ! WORKTREES=$(git -C "$REPO" worktree list --porcelain 2>/dev/null); then
  echo "git could not list the worktrees of $REPO, so a live run with $LOOKUP_BRANCH checked out cannot be ruled out"
  exit 2
fi
BRANCH_TREE=$(printf '%s\n' "$WORKTREES" | awk -v ref="branch refs/heads/$LOOKUP_BRANCH" 'index($0, "worktree ") == 1 { tree = substr($0, 10) } $0 == ref { print tree; exit }')

# The work's trees outside this session's directory, resolved, one per line. A
# recorded path with no directory behind it is nothing to adopt.
TREES=""
for TREE in "$WORK_DIR" "$BRANCH_TREE"; do
  [ -n "$TREE" ] || continue
  TREE_DIR=$(cd "$TREE" 2>/dev/null && pwd -P) || continue
  if [ -n "$OWN_DIR" ]; then
    case "$TREE_DIR/" in "$OWN_DIR"/*) continue ;; esac
  fi
  case "$NL$TREES" in *"$NL$TREE_DIR$NL"*) continue ;; esac
  TREES="$TREES$TREE_DIR$NL"
done
[ -n "$TREES" ] || exit 0

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-tree-holder.XXXXXX") || {
  echo "no scratch directory for the session list, so the holder of the work's tree cannot be ruled out"
  exit 2
}
trap 'rm -rf "$SCRATCH"' EXIT

# uncommitted DIR — how many paths git reports changed or untracked in DIR.
# The tree may be a live session's, so the read takes no optional lock: a plain
# status refreshes the index under index.lock, and a lock held at the wrong
# moment fails that session's own git command.
uncommitted() {
  local status
  if status=$(git --no-optional-locks -C "$1" status --porcelain 2>/dev/null); then
    printf '%s' "$status" | grep -c .
  else
    echo unreadable
  fi
}

gc session list --state all --json 2>/dev/null </dev/null | scrub > "$SCRATCH/sessions.json"
SESSIONS_READ=1
jq -e '.sessions | type == "array" and all(.[]; type == "object")' "$SCRATCH/sessions.json" >/dev/null 2>&1 || SESSIONS_READ=0
SESSION_DIRS=""
[ "$SESSIONS_READ" = 1 ] && SESSION_DIRS=$(jq -r '[.sessions[] | .work_dir | strings | select(length > 0)] | unique | .[]' "$SCRATCH/sessions.json")

# sessions_in DIRS — the session rows whose work_dir is one of DIRS, one per line.
sessions_in() {
  jq -c --arg dirs "$1" '($dirs | split("\n") | map(select(length > 0))) as $d | [.sessions[] | select((.work_dir // "") as $w | any($d[]; . == $w))]' "$SCRATCH/sessions.json"
}

# The open and in_progress beads, listed once, plus any row fetched by id. A
# live molecule's root, input convoy and work bead are all open or in_progress,
# so the fetch is for the rare row that is not.
BEADS_READ=""
read_beads() {
  [ -n "$BEADS_READ" ] && return "$BEADS_READ"
  gc bd list --status=open,in_progress --brief --json --limit 0 2>/dev/null </dev/null | scrub > "$SCRATCH/rows.json"
  if jq -e 'type == "array" and all(.[]; type == "object")' "$SCRATCH/rows.json" >/dev/null 2>&1; then
    BEADS_READ=0
  else
    BEADS_READ=1
  fi
  return "$BEADS_READ"
}

# need_rows IDS — make every id in IDS (one per line) a row of rows.json.
need_rows() {
  local missing fetched
  missing=$(printf '%s\n' "$1" | jq -R -r --slurpfile rows "$SCRATCH/rows.json" 'select(length > 0) | select(. as $i | $rows[0] | any(.[]; .id == $i) | not)' | sort -u | paste -sd, -)
  [ -n "$missing" ] || return 0
  fetched=$(gc bd list --id "$missing" --all --brief --json --limit 0 2>/dev/null </dev/null | scrub)
  printf '%s' "$fetched" | jq -e 'type == "array" and all(.[]; type == "object")' >/dev/null 2>&1 || return 1
  printf '%s' "$fetched" | jq -c --slurpfile rows "$SCRATCH/rows.json" '$rows[0] + .' > "$SCRATCH/rows.next" && mv "$SCRATCH/rows.next" "$SCRATCH/rows.json"
}

# judge TREE — set FINDING; return 0 adoptable, 1 held, 2 undecided.
judge() {
  local tree="$1" desc home="" d in_tree="" in_home="" names ids claims roots convoys traced untraced work_ids matches="" others="" w found branch wd
  desc="worktree $tree (uncommitted paths: $(uncommitted "$tree"))"
  if [ "$SESSIONS_READ" != 1 ]; then
    FINDING="$desc could not be cleared: the session list could not be read"
    return 2
  fi
  [ "$(basename "$(dirname "$tree")")" = worktrees ] && home=$(dirname "$(dirname "$tree")")
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ "$d" -ef "$tree" ]; then
      in_tree="$in_tree$d$NL"
    elif [ -n "$home" ] && [ "$d" -ef "$home" ]; then
      in_home="$in_home$d$NL"
    fi
  done <<EOF
$SESSION_DIRS
EOF
  if [ -n "$in_tree" ]; then
    FINDING="$desc is held by live $(sessions_in "$in_tree" | jq -r '[.[] | .session_name // .id] | join(", ")'), whose directory it is"
    return 1
  fi
  if [ -z "$in_home" ]; then
    if [ -n "$home" ]; then
      FINDING="$desc is adoptable: no listed session works in $home"
      return 0
    fi
    FINDING="$desc could not be cleared: no session directory accounts for it"
    return 2
  fi

  names=$(sessions_in "$in_home" | jq -r '[.[] | .session_name // .id] | join(", ")')
  ids=$(sessions_in "$in_home" | jq -c '[.[] | (.id, .session_name, .name, .agent_name, .alias) | strings | select(length > 0)] | unique')
  if ! read_beads; then
    FINDING="$desc could not be cleared: the beads could not be listed to read what live $names is working"
    return 2
  fi
  claims=$(jq -c --argjson ids "$ids" '[.[] | select(.status == "open" or .status == "in_progress") | select((.assignee // "") as $a | any($ids[]; . == $a))]' "$SCRATCH/rows.json")
  if [ "$(printf '%s' "$claims" | jq 'length')" = 0 ]; then
    FINDING="$desc is adoptable: live $names in $home holds no claim"
    return 0
  fi

  # A claim with no molecule root is the work itself. A step's work is what
  # its molecule's input convoy tracks.
  roots=$(printf '%s' "$claims" | jq -r '.[] | .metadata["gc.root_bead_id"] // empty | strings')
  if ! need_rows "$roots"; then
    FINDING="$desc could not be cleared: the molecules live $names is running could not be read"
    return 2
  fi
  convoys=$(jq -r --arg roots "$roots" '($roots | split("\n")) as $r | .[] | select(.id as $i | any($r[]; . == $i)) | .metadata["gc.input_convoy_id"] // .metadata["gc.var.convoy_id"] // empty | strings' "$SCRATCH/rows.json")
  if ! need_rows "$convoys"; then
    FINDING="$desc could not be cleared: the input convoys of the molecules live $names is running could not be read"
    return 2
  fi
  traced=$(jq -c --argjson claims "$claims" '
    (map({key: .id, value: .}) | from_entries) as $by
    | [$claims[] as $c
       | ($c.metadata["gc.root_bead_id"] // "" | tostring) as $r
       | if $r == "" then {claim: $c.id, work: [$c.id]}
         elif $by[$r] == null then {claim: $c.id, untraced: "molecule \($r) could not be read"}
         else ($by[$r].metadata["gc.input_convoy_id"] // $by[$r].metadata["gc.var.convoy_id"] // "" | tostring) as $cv
           | if $cv == "" then {claim: $c.id, untraced: "molecule \($r) names no input convoy"}
             elif $by[$cv] == null then {claim: $c.id, untraced: "convoy \($cv) could not be read"}
             else [$by[$cv].dependencies[]? | select((.type // .dependency_type) == "tracks") | (.depends_on_id // .id)] as $m
               | if ($m | length) == 0 then {claim: $c.id, untraced: "convoy \($cv) tracks no work"}
                 else {claim: $c.id, work: $m}
                 end
             end
         end]' "$SCRATCH/rows.json")
  untraced=$(printf '%s' "$traced" | jq -r '[.[] | select(.untraced) | "\(.claim): \(.untraced)"] | join("; ")')
  work_ids=$(printf '%s' "$traced" | jq -r '[.[] | .work[]?] | unique | .[]')
  if ! need_rows "$work_ids"; then
    FINDING="$desc could not be cleared: the work live $names is running could not be read"
    return 2
  fi

  # Fields are split on US (0x1f), which the scrub has removed from every
  # value. A tab would not do: read folds a run of tabs into one separator, so
  # an empty branch would shift the work_dir into its place.
  while IFS="$US" read -r w found branch wd; do
    [ -n "$w" ] || continue
    if [ "$w" = "$BEAD" ]; then
      matches="$matches${matches:+, }$w"
    elif [ "$found" != 1 ]; then
      untraced="$untraced${untraced:+; }work $w could not be read"
    elif [ -n "$branch" ] && [ "$branch" = "$LOOKUP_BRANCH" ]; then
      matches="$matches${matches:+, }$w on $branch"
    elif [ -n "$wd" ] && [ "$wd" -ef "$tree" ]; then
      matches="$matches${matches:+, }$w in this worktree"
    else
      others="$others${others:+, }$w"
    fi
  done <<EOF
$(jq -r --arg ids "$work_ids" '(map({key: .id, value: .}) | from_entries) as $by | $ids | split("\n")[] | select(length > 0) | . as $w | [$w, (if $by[$w] then "1" else "0" end), ($by[$w].metadata.branch // "" | tostring), ($by[$w].metadata.work_dir // "" | tostring)] | join("\u001f")' "$SCRATCH/rows.json")
EOF

  if [ -n "$matches" ]; then
    FINDING="$desc is held by live $names, which is working $matches"
    return 1
  fi
  if [ -n "$untraced" ]; then
    FINDING="$desc could not be cleared: live $names holds claims whose work could not be traced ($untraced)"
    return 2
  fi
  FINDING="$desc is adoptable: live $names in $home is working other work ($others)"
  return 0
}

HELD=""; UNDECIDED=""; ADOPTABLE=""
while IFS= read -r TREE_DIR <&3; do
  [ -n "$TREE_DIR" ] || continue
  FINDING=""
  judge "$TREE_DIR"
  case $? in
    0) ADOPTABLE="$ADOPTABLE${ADOPTABLE:+; }$FINDING" ;;
    1) HELD="$HELD${HELD:+; }$FINDING" ;;
    *) UNDECIDED="$UNDECIDED${UNDECIDED:+; }$FINDING" ;;
  esac
done 3<<EOF
$TREES
EOF

if [ -n "$HELD" ]; then
  echo "$HELD${UNDECIDED:+; }$UNDECIDED"
  exit 1
fi
if [ -n "$UNDECIDED" ]; then
  echo "$UNDECIDED${ADOPTABLE:+; }$ADOPTABLE"
  exit 2
fi
echo "$ADOPTABLE"
exit 0
