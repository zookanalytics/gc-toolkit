# shellcheck shell=bash
# refinery-lib.sh — what the refinery patrol's scripts share. Sourced by
# sibling path. It sources bd-lib.sh beside it for the store reads, and
# otherwise defines functions and sets nothing.
#
# The refinery prepares one bead's branch at a time, in a tree of its own: a
# git worktree at <refinery home>/worktrees/<bead>, where the home is the
# refinery's own worktree, the directory its session starts in ($GC_DIR). It
# is the per-bead layout a polecat's tree has under its home, so the home's
# sync reads it as gc's own (worktree-setup.sh's GC_WRITES) and never as an
# edit, and nothing the prep does moves the home's own HEAD.
#
# The prep checks the tree out detached at the commit it read on the bead's
# branch, and names that branch and that commit in one per-worktree ref,
# refs/worktree/refinery/<branch>. git keeps a per-worktree ref in the tree's
# own git dir and removes it with the tree. Each script takes the bead it acts
# for and reads the tree for that bead: a bead whose branch is not the one the
# tree holds, or a bead with no tree, gets no write. The commit the ref names
# is the one every push onto the branch leases on (branch-push.sh).

_refinery_lib_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_refinery_lib_dir/bd-lib.sh}" || return 1

REFINERY_READ_NS="refs/worktree/refinery"

# refinery_home — the refinery's own worktree, from GC_DIR, printed as a
# physical path. Non-zero, with a line on stderr, when GC_DIR is unset or is not
# the top of a git worktree, since a prep tree under any other directory would
# not be the refinery's.
refinery_home() {
  local home top
  [ -n "${GC_DIR:-}" ] || { echo "GC_DIR is unset, so the refinery's own worktree cannot be named" >&2; return 1; }
  home=$(cd "$GC_DIR" 2>/dev/null && pwd -P) || { echo "GC_DIR names no directory ($GC_DIR)" >&2; return 1; }
  top=$(git -C "$home" rev-parse --show-toplevel 2>/dev/null) && top=$(cd "$top" && pwd -P) || top=""
  [ "$top" = "$home" ] || { echo "$home is not the top of a git worktree, so it is not the refinery's own worktree" >&2; return 1; }
  printf '%s\n' "$home"
}

# refinery_tree <home> <bead> — the tree the prep stages <bead>'s branch in.
refinery_tree() { printf '%s/worktrees/%s\n' "$1" "$2"; }

# refinery_held <home> <bead> — what the tree for <bead> holds, in PREP_TREE,
# PREP_BRANCH (the branch the prep read), PREP_READ (the commit it read there)
# and PREP_HEAD (the prepared head). 0 when the tree is a worktree of its own
# holding one prep, 1 otherwise: no tree, a husk whose git calls reach an
# enclosing repository, or no single read recorded.
# shellcheck disable=SC2034  # PREP_* are read by the scripts that source this
refinery_held() {
  local top refs
  PREP_TREE=$(refinery_tree "$1" "$2"); PREP_BRANCH=""; PREP_READ=""; PREP_HEAD=""
  [ -d "$PREP_TREE" ] || return 1
  PREP_TREE=$(cd "$PREP_TREE" && pwd -P) || return 1
  top=$(git -C "$PREP_TREE" rev-parse --show-toplevel 2>/dev/null) && top=$(cd "$top" && pwd -P) || return 1
  [ "$top" = "$PREP_TREE" ] || return 1
  refs=$(git -C "$PREP_TREE" for-each-ref --format='%(refname)%09%(objectname)' "$REFINERY_READ_NS/" 2>/dev/null) || return 1
  [ -n "$refs" ] && [ "$(printf '%s\n' "$refs" | wc -l | tr -d ' ')" = 1 ] || return 1
  PREP_BRANCH=${refs%%$'\t'*}
  PREP_BRANCH=${PREP_BRANCH#"$REFINERY_READ_NS/"}
  PREP_READ=${refs#*$'\t'}
  PREP_HEAD=$(git -C "$PREP_TREE" rev-parse --verify -q HEAD) || return 1
}

# refinery_require <home> <bead> <branch> — refinery_held, and the branch the
# tree holds is <branch>. Non-zero, with a line on stderr naming what the tree
# holds, otherwise.
refinery_require() {
  if ! refinery_held "$1" "$2"; then
    echo "no prepared branch for $2 in $(refinery_tree "$1" "$2"), so nothing is written for $2" >&2
    return 1
  fi
  if [ "$PREP_BRANCH" != "$3" ]; then
    echo "the tree for $2 holds $PREP_BRANCH, not $2's branch $3, so nothing is written for $2" >&2
    return 1
  fi
}

# refinery_bead <bead> — the bead's `gc bd show` row, in BEAD_ROW. Non-zero
# when the store does not return that bead, which a read of one key cannot tell
# from a bead that lacks the key.
refinery_bead() {
  BEAD_ROW=$(bd_json show "$1") || BEAD_ROW=""
  printf '%s' "$BEAD_ROW" | jq -e --arg id "$1" 'type == "array" and ((.[0].id // "") | tostring) == $id' >/dev/null 2>&1
}

# bead_meta <key> — a metadata value off BEAD_ROW, empty when absent.
bead_meta() { row_meta "$BEAD_ROW" "$1"; }

# bead_field <field> — a top-level field off BEAD_ROW, empty when absent.
bead_field() { printf '%s' "$BEAD_ROW" | jq -r --arg f "$1" '(.[0][$f] // "") | tostring' 2>/dev/null; }

# refinery_default_branch <home> — the rig's default branch, as origin/HEAD in
# the refinery's own worktree names it: the branch a bead with no target lands
# on.
refinery_default_branch() {
  local ref
  ref=$(git -C "$1" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || return 1
  printf '%s\n' "${ref#refs/remotes/origin/}"
}

# refinery_teardown <home> <bead> — remove the tree for <bead>, in whatever
# state the iteration left it. A `worktree add` killed partway leaves its
# worktree locked, and git refuses a locked worktree a single --force, so the
# removal gives it twice. A directory git does not know as a worktree is left
# alone and named. 0 once no tree is there.
refinery_teardown() {
  local tree out
  tree=$(refinery_tree "$1" "$2")
  [ -e "$tree" ] || return 0
  if ! out=$(git -C "$1" worktree remove --force --force "$tree" 2>&1) && [ -e "$tree" ]; then
    echo "the tree $tree was not removed: $(printf '%s' "$out" | tr -s '[:space:]' ' ')" >&2
    return 1
  fi
}

# refinery_owner <bead> <branch> — the bead whose PR the work on <branch>
# lands on, in OWNER, with its row in OWNER_ROW. BEAD_ROW must be <bead>'s row.
# It is the bead <bead> names as its anchor_bead when that bead is open on
# <branch>; else the oldest other open bead on <branch> that carries a
# merge_result, since any recorded state, a park included, still owns its PR;
# else <bead> itself. Non-zero, with a line on stderr, when the open beads on
# <branch> do not read.
# shellcheck disable=SC2034  # OWNER_ROW is read by the scripts that source this
refinery_owner() {
  local on named
  on=$(bd_json list ${GC_RIG:+--rig="$GC_RIG"} --metadata-field "branch=$2" \
    --status=open,in_progress,blocked,deferred,hooked,pinned --limit=0) || on=""
  printf '%s' "$on" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { echo "the open beads on $2 did not list, so the bead whose PR they land on cannot be told" >&2; return 1; }
  named=$(bead_meta anchor_bead)
  OWNER=""
  [ -z "$named" ] || [ "$named" = "$1" ] \
    || OWNER=$(printf '%s' "$on" | jq -r --arg n "$named" '[ .[] | select(.id == $n) ] | .[0].id // empty')
  [ -n "$OWNER" ] || OWNER=$(printf '%s' "$on" | jq -r --arg self "$1" '[ .[] | select(.id != $self)
    | select(((.metadata.merge_result // "") | tostring) != "") ] | sort_by(.created_at // .id) | .[0].id // empty')
  if [ -z "$OWNER" ]; then
    OWNER="$1"; OWNER_ROW="$BEAD_ROW"
  else
    OWNER_ROW=$(printf '%s' "$on" | jq -c --arg o "$OWNER" '[ .[] | select(.id == $o) ]')
  fi
}

# origin_repo <dir> — the GitHub owner/repo that <dir>'s origin names, printed,
# as its configured URL names it. Non-zero for an origin that is not a
# github.com repository.
origin_repo() {
  local url repo
  url=$(git -C "$1" config --get remote.origin.url 2>/dev/null | tr -d '[:space:]') || return 1
  case "$url" in
    git@github.com:*|https://github.com/*|ssh://git@github.com/*) ;;
    *) return 1 ;;
  esac
  repo=$(printf '%s' "$url" | sed -e 's#^ssh://git@github.com/##' -e 's#^git@github.com:##' \
    -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##')
  case "$repo" in */*/*|/*|*/) return 1 ;; */?*) printf '%s\n' "$repo" ;; *) return 1 ;; esac
}
