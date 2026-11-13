# shellcheck shell=bash
# refinery-lib.sh — what the refinery patrol's scripts share. Sourced by
# sibling path. It sources bd-lib.sh beside it for the store reads and
# dispatch-path.sh for what dispatches a bead, and otherwise defines functions
# and sets only its constants.
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
# shellcheck source=dispatch-path.sh
. "$_refinery_lib_dir/dispatch-path.sh" || return 1

REFINERY_READ_NS="refs/worktree/refinery"

# A rework child the requeue filed and never sent on. refinery-requeue.sh files
# a bead's rework child whole, with its blocks edge onto the bead in the create,
# then settles and slings it, and a settle or a sling can still fail after the
# create, or the run can end there. The child it leaves is open on the bead's
# branch, with no assignee, no pour and no dispatch path or dispatch hold
# (dispatch-path.sh), so no one works it. find-work counts such a child,
# once nothing holds it, as neither a wait on the bead nor a writer of its
# branch, and the bead's prep runs the requeue again, which sends the child on.
# A child carrying a review's or a ruling's source key was filed by
# rework-child.sh, and a re-run of its filer adopts it and sends it on, so it
# is never one of these.
#   jq "$REFINERY_UNSENT_JQ"' map(select(refinery_unsent($bead; $branch))) '
# shellcheck disable=SC2034  # read by the scripts that source this file
REFINERY_UNSENT_JQ="$DISPATCH_PATH_JQ"'
  def refinery_unsent($anchor; $branch):
    (.metadata // {}) as $m
    | ((.status // "") | tostring) == "open"
      and (($m.task_kind // "") | tostring) == "rework"
      and (($m.anchor_bead // "") | tostring) == $anchor
      and (($m.branch // "") | tostring) == $branch
      and ((.assignee // "") | tostring) == ""
      and ([ "gc.execution_routed_to", "source_review_bead", "source_ruling_bead" ]
           | all(. as $k | (($m[$k] // "") | tostring) == ""))
      and ((has_dispatch_path or has_dispatch_hold) | not);
'

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

# refinery_park <bead> <key> <merge_result> <reason> <message> [<home>] — park
# <bead> behind a human gate keyed <key>, still assigned to this refinery
# ($GC_AGENT), so clearing the gate hands it back. The gate is filed first,
# with <message>, and a gate that does not land parks nothing: the call returns
# non-zero, with nothing written, and the caller stops. Otherwise one write,
# guarded on the assignee, sets merge_result to <merge_result> and
# blocked_reason to <reason>; a write that does not land is named on stderr,
# and the gate still holds the bead. With <home>, the bead's tree under it is
# removed. The call then ends the step: it prints what was parked and exits 4,
# the exit every refinery step gives a parked bead.
refinery_park() {
  "$_refinery_lib_dir/human-gate.sh" --subject "$1" --key "$2" --message "$5" >/dev/null || return 1
  gc bd update "$1" --if-assignee="$GC_AGENT" --set-metadata "merge_result=$3" --set-metadata "blocked_reason=$4" </dev/null >/dev/null \
    || echo "${PROG:-refinery}: the $2 gate holds $1, but merge_result=$3 did not land on it" >&2
  [ -z "${6:-}" ] || refinery_teardown "$6" "$1" || echo "${PROG:-refinery}: the next prep removes the tree for $1" >&2
  echo "${PROG:-refinery}: parked $1 behind its $2 gate: $4"
  exit 4
}

# refinery_formula_vars — mol-refinery-patrol's vars as this rig sets them, read
# once with `gc formula show --rig $GC_RIG --json` into REFINERY_VARS, so every
# step and every session reads the same values. Non-zero, with a line on stderr,
# when GC_RIG is unset or the read does not answer with the vars, since an
# unread answer would look like a rig that sets none.
refinery_formula_vars() {
  REFINERY_VARS=""
  [ -n "${GC_RIG:-}" ] || { echo "GC_RIG is unset, so the rig's formula vars cannot be read" >&2; return 1; }
  REFINERY_VARS=$(gc formula show mol-refinery-patrol --rig "$GC_RIG" --json </dev/null 2>/dev/null) || REFINERY_VARS=""
  printf '%s' "$REFINERY_VARS" | jq -e '.ok == true and (.vars | type == "array")' >/dev/null 2>&1 \
    || { echo "the formula vars of rig '$GC_RIG' did not read (gc formula show --rig)" >&2; return 1; }
}

# refinery_formula_var [--default] <name> — one var off REFINERY_VARS: the rig's
# own value when it sets one, an empty one included, else the formula's default,
# else empty. --default reads the formula's default alone.
refinery_formula_var() {
  local which=rig
  [ "$1" != --default ] || { which=default; shift; }
  printf '%s' "$REFINERY_VARS" | jq -r --arg n "$1" --arg w "$which" '[.vars[] | select(.name == $n)][0]
    | if . == null then "" elif $w == "rig" and .rig_default != null then .rig_default else (.default // "") end'
}

# refinery_gate_dir <dir> — the record of the rig's gate (refinery-gate.sh), in
# the git common dir of the repository <dir> sits in, printed. One per rig,
# since the refinery prepares and gates one bead at a time.
refinery_gate_dir() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  printf '%s/gc-refinery-gate\n' "$common"
}

# refinery_owner <bead> <branch> — the bead whose PR the work on <branch>
# lands on, in OWNER, with its row in OWNER_ROW. BEAD_ROW must be <bead>'s row.
# It is the bead <bead> names as its anchor_bead when that bead is open on
# <branch>. A rework that names a bead and carries no review's or ruling's
# source key can be a convoy's rebuild child, which carries its convoy's PR and
# so lands on no other bead. When the bead it names is not open on <branch>,
# that bead is read by its id in every status, and when it is a convoy, or the
# store holds no bead by that id, the call returns 3, with OWNER empty and the
# message of the human gate the caller parks <bead> behind in OWNER_REFUSED.
# The gate is keyed refinery-rebuild-convoy-not-open, and the caller files it
# before it pushes, publishes or records anything. A named bead of any other
# kind leaves the rest of this rule. Else it is <bead> itself when <bead>
# carries a merge_result or records a PR (existing_pr, pr_url or pr_number),
# since any recorded state, a park included, still owns its PR. Else it is the
# oldest other open bead on <branch> that carries a merge_result and names no
# other bead as its anchor_bead, since such a bead, a rework child among them,
# lands on that anchor's PR and never owns one, though a park stamps a
# merge_result on it too. Else it is <bead> itself. Non-zero, with a line on
# stderr, when the open beads on <branch>, or the bead a rework names, do not
# read.
# shellcheck disable=SC2034  # OWNER_ROW and OWNER_REFUSED are read by the scripts that source this
refinery_owner() {
  local on named key rows found
  on=$(bd_json list ${GC_RIG:+--rig="$GC_RIG"} --metadata-field "branch=$2" \
    --status=open,in_progress,blocked,deferred,hooked,pinned --limit=0) || on=""
  printf '%s' "$on" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { echo "the open beads on $2 did not list, so the bead whose PR they land on cannot be told" >&2; return 1; }
  named=$(bead_meta anchor_bead)
  OWNER=""; OWNER_REFUSED=""
  [ -z "$named" ] || [ "$named" = "$1" ] \
    || OWNER=$(printf '%s' "$on" | jq -r --arg n "$named" '[ .[] | select(.id == $n) ] | .[0].id // empty')
  if [ -z "$OWNER" ] && [ -n "$named" ] && [ "$named" != "$1" ] && [ "$(bead_meta task_kind)" = rework ] \
     && [ -z "$(bead_meta source_review_bead)" ] && [ -z "$(bead_meta source_ruling_bead)" ]; then
    rows=$(bd_json list ${GC_RIG:+--rig="$GC_RIG"} --id "$named" --all --limit=0) || rows=""
    found=$(printf '%s' "$rows" | jq -r --arg n "$named" 'if type != "array" then empty
      else ([ .[] | objects | select(.id == $n) ][0]) as $r
        | if $r == null then "the store holds no bead \($n)"
          elif (($r.issue_type // $r.type // "") | tostring) != "convoy" then "kept"
          elif (($r.status // "") | tostring) == "closed" then "\($n) is closed"
          else (($r.metadata.branch // "") | tostring) as $b
            | "\($n) is \(($r.status // "") | tostring) " + (if $b == "" then "with no branch" else "on \($b)" end)
          end
      end' 2>/dev/null)
    case "$found" in
      "") echo "$named, which $1 names as its anchor_bead, did not read, so whether $1 rebuilds a convoy cannot be told" >&2
          return 1 ;;
      kept) ;;
      *) OWNER_REFUSED="$1, the rebuild of $named, lands on $named's PR, but $found, so no bead on $2 can carry that PR, and the refinery pushed, published and recorded nothing for $1. To go on with the graduation, make $named open with branch $2, then clear this gate: clearing it hands $1 back to the refinery, whose next pass lands it on $named. To abandon the graduation, run $_refinery_lib_dir/stand-down.sh $1 --key refinery-rebuild-convoy-not-open --ruling '<why>'."
         return 3 ;;
    esac
  fi
  if [ -z "$OWNER" ]; then
    for key in merge_result existing_pr pr_url pr_number; do
      [ -z "$(bead_meta "$key")" ] || { OWNER="$1"; break; }
    done
  fi
  [ -n "$OWNER" ] || OWNER=$(printf '%s' "$on" | jq -r --arg self "$1" '[ .[] | select(.id != $self)
    | select(((.metadata.anchor_bead // "") | tostring) as $a | $a == "" or $a == .id)
    | select(((.metadata.merge_result // "") | tostring) != "") ] | sort_by(.created_at // .id) | .[0].id // empty')
  if [ -z "$OWNER" ] || [ "$OWNER" = "$1" ]; then
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
