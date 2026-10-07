#!/usr/bin/env bash
# regen-merge.sh — a merge conflict confined to a generated tree, and its one
# resolution: render the tree again from the merged inputs.
#   regen-merge.sh classify [--dir <repo>] <base-rev> <head-rev>
#   regen-merge.sh resolve  [--dir <worktree>]
#
# generated/seed-audit is committed on every branch but rendered from the whole
# source tree (render-seed-audit.sh). When the base and a branch both move render
# inputs, its SOURCES.txt and INDEX.md conflict even though every input merged
# cleanly, because each side rewrote the same hash or byte-count line. Such a
# conflict calls for no judgment. The tree's only correct content is the
# renderer's output over the merged inputs, so a render finishes the merge and a
# person reading the two sides adds nothing.
#
# classify answers whether a merge has that shape. It reads the object store
# only (`git merge-tree`), so a cadence arm choosing who brings a branch current
# can ask it of two fetched refs with no working tree and without running
# anything from the branch. It prints the conflicted paths, one per line, as git
# names them.
#   exit 0  every conflicted path is inside the generated tree, and the merged
#           tree carries the renderer
#        1  a conflict outside the tree, or no renderer in the merged tree
#        2  could not tell: a rev that names no commit, unrelated histories, or
#           a git without `merge-tree --write-tree` (2.38)
#        3  no conflict: the two merge cleanly
#
# resolve performs the resolution where `git merge` has stopped on conflicts in
# <worktree> (default: the current directory). It runs the renderer IN THE MERGED
# TREE, because that copy names the input set and the synthetic city the merged
# tree commits. It stages the tree and commits the merge. Before the commit it
# holds the render to git's own auto-merge of the same two commits: the staged
# tree may differ from it only at the conflicted paths and at paths both sides
# changed. A render that moves a file only one side changed, or neither, disagrees
# with what that side or the base committed, which a different `gc` binary or a
# leaked machine path produces, and settling that is a person's job. A refusal
# commits nothing and leaves the stopped merge for the caller to abort.
#   exit 0  the merge is committed
#        1  refused: a conflict outside the generated tree, no renderer, an
#           unstaged change or an untracked file besides the conflicts, a
#           failed render, or a render that changed or created a file outside
#           the tree or moved a path only one side, or neither, had changed
#        2  usage, or no merge in progress
#
# Callers: mol-refinery-patrol's prepare step (resolve), pr-facts.sh and
# pre-open-rebase.sh (classify).
set -uo pipefail

PROG="regen-merge"

# The generated tree a conflict may be confined to, and the renderer that writes
# it, both as paths inside the merged tree. The renderer replaces the whole tree
# on every run, so nothing under it is written by hand.
GEN_TREE="generated/seed-audit"
GEN_RENDERER="assets/scripts/render-seed-audit.sh"
# A render takes about ten seconds, even with the host loaded three times over.
# The bound turns a hung `gc` into a refusal while the caller's shell call is
# still waiting for an answer.
RENDER_TIMEOUT="${REGEN_MERGE_RENDER_TIMEOUT:-90}"
case "$RENDER_TIMEOUT" in ''|*[!0-9]*) RENDER_TIMEOUT=90 ;; esac

die()    { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }
refuse() { printf '%s: NOT resolved: %s\n' "$PROG" "$*" >&2; exit 1; }

# The lines of a path list that name nothing inside the generated tree. git
# C-quotes a path that carries a control character, so such a path starts with
# a double quote and lands here, never inside the tree.
outside_tree() { # <newline-separated paths>
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in "$GEN_TREE"/*) : ;; *) printf '%s\n' "$p" ;; esac
  done <<< "$1"
}

sorted() { printf '%s\n' "$1" | sed '/^$/d' | LC_ALL=C sort -u; }

# The files in a working tree that git neither tracks nor ignores, one per line
# as git quotes them, or NUL-separated and unquoted given -z. `git diff` never
# lists such a file, though the render reads it and the commit leaves it out.
untracked() { git -C "$1" ls-files --others --exclude-standard "${@:2}"; }

classify() { # <repo> <base-rev> <head-rev>
  local repo="$1" base="$2" head="$3" rev out rc tree paths
  for rev in "$base" "$head"; do
    git -C "$repo" rev-parse --verify --quiet "$rev^{commit}" >/dev/null 2>&1 \
      || { printf '%s: %s names no commit\n' "$PROG" "$rev" >&2; exit 2; }
  done
  out=$(git -C "$repo" merge-tree --write-tree --name-only --no-messages "$base" "$head" 2>/dev/null); rc=$?
  case "$rc" in
    0) exit 3 ;;
    1) : ;;
    *) printf '%s: merge-tree could not merge %s into %s (rc=%s)\n' "$PROG" "$head" "$base" "$rc" >&2; exit 2 ;;
  esac
  tree="${out%%$'\n'*}"
  paths="${out#*$'\n'}"
  if [ "$paths" = "$out" ] || [ -z "$(sorted "$paths")" ] \
     || ! git -C "$repo" cat-file -e "$tree^{tree}" 2>/dev/null; then
    printf '%s: merge-tree reported a conflict without a merged tree and the paths in it\n' "$PROG" >&2
    exit 2
  fi
  printf '%s\n' "$paths"
  [ -z "$(outside_tree "$paths")" ] || exit 1
  git -C "$repo" cat-file -e "$tree:$GEN_RENDERER" 2>/dev/null || exit 1
  exit 0
}

run_bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout "$RENDER_TIMEOUT" "$@" </dev/null; else "$@" </dev/null; fi
}

resolve() { # <worktree>
  local dir="$1" mh unmerged outside dirty loose mt_out mt_rc mt mt_paths render_out wrote created gone p new changed both mb stray msg_file subject
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || die "$dir is not a git worktree"
  mh=$(git -C "$dir" rev-parse --verify --quiet MERGE_HEAD 2>/dev/null) || die "no merge in progress in $dir"
  unmerged=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null) || refuse "could not list the unmerged paths"
  unmerged=$(sorted "$unmerged")
  [ -n "$unmerged" ] || refuse "the merge stopped with no unmerged path, so it is not a conflict a render can finish"
  outside=$(outside_tree "$unmerged")
  [ -z "$outside" ] || refuse "conflicts outside $GEN_TREE need a person: $(printf '%s' "$outside" | tr '\n' ' ')"
  [ -f "$dir/$GEN_RENDERER" ] || refuse "the merged tree carries no $GEN_RENDERER to render $GEN_TREE with"
  # The render reads the working tree and the commit takes the index, so an
  # unstaged change or an untracked file would shape the render and stay out of
  # the commit. The renderer finds its inputs on disk, not through git. With
  # neither present here, every unstaged change or untracked file the checks
  # after the render find is the render's own, and undoing those discards
  # nothing a person wrote.
  dirty=$(git -C "$dir" diff --name-only 2>/dev/null) || refuse "could not list the unstaged changes"
  loose=$(untracked "$dir" 2>/dev/null) || refuse "could not list the untracked files"
  dirty=$(LC_ALL=C comm -23 <(sorted "$dirty"$'\n'"$loose") <(printf '%s\n' "$unmerged"))
  [ -z "$dirty" ] \
    || refuse "unstaged changes or untracked files besides the conflicts would feed the render and stay out of the commit: $(printf '%s' "$dirty" | head -5 | tr '\n' ' ')"

  # The baseline the render is held to: git's own auto-merge of the same two
  # commits, which must name exactly the paths the stopped merge left unmerged.
  mt_out=$(git -C "$dir" merge-tree --write-tree --name-only --no-messages HEAD "$mh" 2>/dev/null); mt_rc=$?
  [ "$mt_rc" -eq 1 ] || refuse "merge-tree does not reproduce the stopped merge (rc=$mt_rc)"
  mt="${mt_out%%$'\n'*}"
  mt_paths=$(sorted "${mt_out#*$'\n'}")
  [ "$mt_paths" = "$unmerged" ] \
    || refuse "merge-tree names other conflicted paths than the stopped merge, so it is no baseline for the render"

  echo "$PROG: every conflict is inside $GEN_TREE; rendering it from the merged inputs"
  render_out=$(cd "$dir" && run_bounded bash "$GEN_RENDERER" 2>&1) \
    || refuse "the render failed: $(printf '%s' "$render_out" | tail -3 | tr '\n' ' ')"
  printf '%s\n' "$render_out" | tail -3

  git -C "$dir" add -A -- "$GEN_TREE" || refuse "could not stage $GEN_TREE"
  [ -z "$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null)" ] \
    || refuse "paths are still unmerged after the render"
  # The renderer writes inside its own tree, and the staging took every change
  # and new file in it. Anything else the render changed or created would be left
  # out of the commit while the checks that run next read it. A created file is
  # no unstaged change, so `git diff` misses it and the untracked listing finds
  # it. Both kinds are undone before the one refusal, because the caller's abort
  # stops on either: it refuses a path carrying unstaged changes on top of merged
  # ones, and it will not write a path back over an untracked file, which a
  # render that recreates a path the merge deleted leaves there. git clean takes
  # each created file by its literal path and deletes no tracked file.
  wrote=""
  if ! git -C "$dir" diff --quiet 2>/dev/null; then
    git -C "$dir" checkout -- . >/dev/null 2>&1 || true
    wrote="changed files outside $GEN_TREE"
  fi
  created=$(untracked "$dir" 2>/dev/null) || refuse "could not list the untracked files after the render"
  if [ -n "$created" ]; then
    gone=()
    while IFS= read -r -d '' p; do gone+=("$p"); done < <(untracked "$dir" -z 2>/dev/null)
    [ "${#gone[@]}" -eq 0 ] || git -C "$dir" --literal-pathspecs clean -f -q -- "${gone[@]}" >/dev/null 2>&1 || true
    wrote="${wrote:+$wrote, and }created files outside $GEN_TREE: $(printf '%s' "$created" | head -5 | tr '\n' ' ')"
  fi
  [ -z "$wrote" ] || refuse "the render $wrote"
  new=$(git -C "$dir" write-tree 2>/dev/null) || refuse "could not write the resolved tree"
  changed=$(git -C "$dir" diff --name-only --no-renames "$mt" "$new" 2>/dev/null) \
    || refuse "could not compare the resolved tree with git's auto-merge"
  # Besides the conflicted paths, the render may move a path BOTH sides changed.
  # git merges two edits of a generated file as text, and a value derived from
  # both inputs comes out stale even when the text merged cleanly: two sides that
  # each grew one prompt by the same byte count rewrite its index row the same
  # way, so the row merges to one side's count instead of the sum. A path only
  # one side changed, or neither, is what that side or the base committed, and a
  # render that moves it disagrees with them. Two merge bases leave no single
  # base to measure "both sides" from, so then only the conflicted paths count.
  both=""
  if [ "$(git -C "$dir" merge-base --all HEAD "$mh" 2>/dev/null | wc -l | tr -d ' ')" = 1 ]; then
    mb=$(git -C "$dir" merge-base HEAD "$mh" 2>/dev/null)
    both=$(LC_ALL=C comm -12 \
      <(sorted "$(git -C "$dir" diff --name-only --no-renames "$mb" HEAD 2>/dev/null)") \
      <(sorted "$(git -C "$dir" diff --name-only --no-renames "$mb" "$mh" 2>/dev/null)"))
  fi
  stray=$(LC_ALL=C comm -23 <(sorted "$changed") <(sorted "$unmerged"$'\n'"$both"))
  [ -z "$stray" ] \
    || refuse "the render changed paths only one side, or neither, had changed, so it disagrees with what was committed: $(printf '%s' "$stray" | head -5 | tr '\n' ' ')"

  msg_file=$(git -C "$dir" rev-parse --path-format=absolute --git-path MERGE_MSG 2>/dev/null)
  subject=$(sed -n '1p' "$msg_file" 2>/dev/null)
  [ -n "$subject" ] || subject="Merge $mh"
  # --no-verify: the pre-commit hook renders this same tree again, which repeats
  # the render just checked and is the one step that could move the tree after
  # that check.
  if ! printf '%s\n\nEvery conflict was inside %s, which is rendered from the merged\ninputs, so %s rendered it again:\n%s\n' \
       "$subject" "$GEN_TREE" "assets/scripts/regen-merge.sh" "$(printf '%s\n' "$unmerged" | sed 's/^/  /')" \
       | git -C "$dir" commit --no-verify -q -F -; then
    refuse "git commit failed"
  fi
  echo "$PROG: merge committed at $(git -C "$dir" rev-parse --short HEAD) with $GEN_TREE re-rendered: $(printf '%s' "$unmerged" | tr '\n' ' ')"
  exit 0
}

CMD="${1:-}"; [ $# -gt 0 ] && shift
DIR="."
case "$CMD" in
  classify|resolve) : ;;
  -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "usage: regen-merge.sh classify [--dir <repo>] <base-rev> <head-rev> | resolve [--dir <worktree>]" ;;
esac
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; [ -n "$DIR" ] || die "--dir needs a path"; shift 2 ;;
    *)     ARGS+=("$1"); shift ;;
  esac
done
case "$CMD" in
  classify)
    [ "${#ARGS[@]}" -eq 2 ] || die "classify needs <base-rev> <head-rev>"
    classify "$DIR" "${ARGS[0]}" "${ARGS[1]}" ;;
  resolve)
    [ "${#ARGS[@]}" -eq 0 ] || die "resolve takes no positional arguments"
    resolve "$DIR" ;;
esac
