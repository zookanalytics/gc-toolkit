#!/usr/bin/env bash
# branch-supersession — tells a conflicting branch that a landed change made moot
# from one that has only drifted, before a conflict arm sends a polecat to bring
# it current.
#
# The conflict arms (pre-open-rebase.sh, and pr-facts.sh's CONFLICTING arm) see
# only that a branch no longer merges into its target. Usually the target merely
# moved and a merge-in child is the answer. Sometimes a change that already landed
# deleted or rewrote the code the branch edits, or shipped the branch's purpose
# under the same names. Then bringing the branch current is a decision about
# whether it still has work to do. A polecat sent to merge it either keeps its side
# of a conflict on code the target removed, which reverts the landed change, or
# stops and asks the operator, after the session is spent.
#
#   branch-supersession.sh classify <base> <branch>
#     Trial-merges <branch> into <base> with `git merge-tree` (nothing is checked
#     out) and reads the result for three tells. Evidence goes to stdout, one
#     tab-separated line per finding:
#       deleted-block   <path>  <size>  a conflict hunk: the branch changes a block
#       rewritten-block <path>  <size>  the base side deleted (kept none of its
#                                       words) or rewrote (kept at most
#                                       MAIN_KEEP_MAX% of them)
#       deleted-file    <path>  <size>  a modify/delete conflict: the base side
#                                       deleted a file the branch edits
#       duplicate-definition <scope> <name>
#                                       a function or type both sides newly define
#                                       in one file (one package directory for Go)
#                                       that the merge result defines twice
#       landed          <sha>   <subject>
#                                       the base-side commits that did it
#     A block or file counts only at MIN_BLOCK_WORDS words or more. One whose
#     lines reappear among the base side's added lines was moved, not deleted,
#     and is no tell; nor is one averaging more than MAX_WORDS_PER_LINE words a
#     line, which is minified or bundled output. Files the repository declares
#     generated (linguist-generated) and test files are not read: their
#     conflicts are regenerated, or follow the code under test. The thresholds
#     and the history they were checked against are in
#     specs/tk-b7c72m/supersession-tells.md.
#     Exit: 0 superseded · 1 not superseded · 2 could not tell.
#
#   branch-supersession.sh hold --anchor <id> --branch <name> --target <name>
#                               --base <commit> --head <commit> [--pr <n>]
#     The conflict arm's question: should the merge-in dispatch wait for a
#     person's decision? It waits while a rework-base-supersession visit is open
#     on the anchor and its route addresses somebody, judged the way escalate.sh
#     judges the route of an open visit it finds. Otherwise it classifies <head>
#     against <base>, and on a supersession files that visit through
#     escalate.sh, with the evidence and the ways out, then waits behind it. An
#     open visit whose route addresses nobody is repointed there rather than
#     filed again. A visit a sitting closes `benign` (the overlap was
#     incidental) lets the next pass dispatch the ordinary child, through
#     escalate.sh's verdict window.
#     Exit: 0 hold: a supersession decision is open on the anchor and routed to
#             somebody, so dispatch nothing.
#           1 proceed: dispatch the ordinary merge-in child. This is also the
#             answer when the tells are not met, the trial merge cannot be read,
#             or no open visit that addresses somebody stands behind the hold, so
#             this guard only ever removes a dispatch a person has been asked
#             about.
#           2 usage.
#
# Callers: pre-open-rebase.sh and pr-facts.sh's CONFLICTING arm, after their own
# vetoes and dedup, immediately before they file or re-route a merge-in child.
set -uo pipefail

PROG="branch-supersession"

SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ESCALATE="$SCRIPTS_DIR/escalate.sh"
# The route reading escalate.sh applies to an open visit it finds.
POOL_ROUTE="$SCRIPTS_DIR/pool-route.sh"
# The situation key a polecat files by hand when it finds this mid-rework, so
# both routes land the same question on one key.
KEY="rework-base-supersession"
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# A block counts from about six lines of code. A smaller rewrite is drift that a
# merge-in child re-applies routinely.
MIN_BLOCK_WORDS=50
MAIN_KEEP_MAX=25
# A block is moved, not deleted, when more than this share of its lines (of 8
# characters or more, so braces and blank lines do not count) appears among the
# base side's added lines.
MOVED_MAX=50
# Hand-written code and wrapped prose average about a dozen words a line; a
# minified bundle averages hundreds, and a rebuild of one on each side reads as a
# rewrite of the whole file.
MAX_WORDS_PER_LINE=40
# Wide conflict markers, so a 7-character marker-like line inside a file is not
# read as a hunk boundary.
MARKER_SIZE=19

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 2; }

usage() {
  cat >&2 <<'U'
usage: branch-supersession.sh classify <base> <branch>
       branch-supersession.sh hold --anchor <id> --branch <name> --target <name>
                                   --base <commit> --head <commit> [--pr <n>]

  classify  trial-merge <branch> into <base> and print the supersession
            evidence. Exit 0 superseded, 1 not superseded, 2 could not tell.
  hold      decide whether a conflict arm's merge-in dispatch waits for a
            person. Exit 0 hold (a rework-base-supersession visit is open on
            the anchor and routed to somebody), 1 proceed with the ordinary
            child, 2 usage.
U
}

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT

is_test_path() { # <path>; 0 = a test file by this repository's naming
  case "${1##*/}" in
    *_test.go|*.test.*|*.spec.*|test_*.py|*_test.py) return 0 ;;
  esac
  return 1
}

in_list() { # <needle> <file>; 0 = an exact line of <file>
  awk -v n="$1" '$0 == n { f = 1; exit } END { exit !f }' "$2"
}

# Paths, one per line on stdin, whose evidence is not read: what the repository
# declares generated at <base>, and test files.
skip_paths() { # <base-commit>
  local list
  list=$(cat)
  printf '%s\n' "$list" | sed '/^$/d' | tr '\n' '\0' \
    | git check-attr --source="$1" -z --stdin linguist-generated 2>/dev/null \
    | tr '\0' '\n' | paste - - - | awk -F'\t' '$3 == "set" || $3 == "true" { print $1 }'
  printf '%s\n' "$list" | while IFS= read -r p; do
    [ -n "$p" ] && is_test_path "$p" && printf '%s\n' "$p"
  done
}

# One line per content-conflict hunk that is a tell, from `git merge-file
# --diff3` output on stdin. The base side is "ours", the branch is "theirs".
hunk_tells() { # <path> <base-added-file>
  awk -v path="$1" -v ADDED="$2" -v MS="$MARKER_SIZE" -v MINW="$MIN_BLOCK_WORDS" \
      -v MAINMAX="$MAIN_KEEP_MAX" -v MOVMAX="$MOVED_MAX" -v WPL="$MAX_WORDS_PER_LINE" '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function marker(c,   s, i) { s = ""; for (i = 0; i < MS; i++) s = s c; return s }
    function opens(line, m) { return line == m || index(line, m " ") == 1 }
    function tally(line, arr,   k, i, w) { k = split(line, w, /[ \t\r]+/); for (i = 1; i <= k; i++) if (w[i] != "") arr[w[i]]++ }
    BEGIN {
      while ((getline l < ADDED) > 0) added[l] = 1
      OPEN = marker("<"); BASE = marker("|"); MID = marker("="); CLOSE = marker(">")
      st = 0
    }
    st == 0 && opens($0, OPEN) { st = 1; olines = 0; blines = 0; bfull = 0; split("", bw); split("", ow); split("", olist); next }
    st == 1 && opens($0, BASE) { st = 2; next }
    (st == 1 || st == 2) && $0 == MID { st = 3; next }
    st == 3 && opens($0, CLOSE) {
      st = 0
      nb = 0; okeep = 0
      for (w in bw) { nb += bw[w]; okeep += (bw[w] < ow[w] + 0) ? bw[w] : ow[w] + 0 }
      if (nb < MINW) next
      if (nb > WPL * bfull) next
      if (okeep * 100 > MAINMAX * nb) next
      moved = 0; counted = 0; probe = ""
      for (i = 1; i <= blines; i++) {
        x = trim(B[i]); if (length(x) < 8) continue
        counted++; if (x in added) moved++
        # The longest line the base side dropped names the commit that dropped
        # it (git log -S). A tab would not survive the evidence line.
        if (!(x in olist) && index(x, "\t") == 0 && length(x) > length(probe)) probe = x
      }
      if (counted > 0 && moved * 100 > MOVMAX * counted) next
      printf "%s\t%s\t%d lines, %d%% kept by the base\t%s\n", (olines == 0 ? "deleted-block" : "rewritten-block"), path, blines, int(okeep * 100 / nb), probe
      next
    }
    st == 1 { x = trim($0); if (x != "") { olines++; olist[x] = 1 }; tally($0, ow); next }
    st == 2 { blines++; B[blines] = $0; if (trim($0) != "") bfull++; tally($0, bw); next }
  '
}

# A modify/delete conflict whose base side deleted the file the branch edits.
deleted_file_tell() { # <path> <base-blob> <base-added-file>
  git cat-file blob "$2" 2>/dev/null | awk -v path="$1" -v ADDED="$3" -v MINW="$MIN_BLOCK_WORDS" \
      -v MOVMAX="$MOVED_MAX" -v WPL="$MAX_WORDS_PER_LINE" '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    BEGIN { while ((getline l < ADDED) > 0) added[l] = 1 }
    { n++; k = split($0, w, /[ \t\r]+/); for (i = 1; i <= k; i++) if (w[i] != "") nw++
      x = trim($0); if (x != "") full++; if (length(x) < 8) next; counted++; if (x in added) moved++ }
    END {
      if (nw < MINW) exit
      if (nw > WPL * full) exit
      if (counted > 0 && moved * 100 > MOVMAX * counted) exit
      printf "deleted-file\t%s\t%d lines\t\n", path, n
    }'
}

# Definition names, one "<scope>\t<name>" per occurrence, in the code files
# named by the pathspecs file under <tree>. The scope is the file, except for Go,
# where every file of a package directory shares one namespace.
definitions() { # <tree-ish> <pathspec-file>
  local specs=()
  mapfile -t specs < "$2"
  [ "${#specs[@]}" -gt 0 ] || return 0
  # A loose prefilter: git grep's regex engine is slow on the anchored per-language
  # shapes, so it only narrows the lines, and git_grep_names applies the shapes.
  git grep -I --null -E \
    -e '^(func|type|def|class|async|export|const|let|var|interface|enum|function)[[:space:]]' \
    -e '\(\)' \
    "$1" -- "${specs[@]}" 2>/dev/null | git_grep_names
}

# `git grep --null` over a tree prints "<tree>:<path>", a NUL, then the line.
# Prints "<scope>\t<name>".
git_grep_names() {
  tr '\0' '\t' | awk '
    function ident(s, re) { if (match(s, re)) return substr(s, RSTART, RLENGTH); return "" }
    {
      i = index($0, "\t"); if (i == 0) next
      path = substr($0, 1, i - 1); text = substr($0, i + 1)
      sub(/^[^:]*:/, "", path)
      ext = path; sub(/^.*\//, "", ext); if (ext ~ /\./) sub(/^.*\./, "", ext); else ext = ""
      name = ""
      if (ext == "go") {
        if (text ~ /^func/) {
          s = text; sub(/^func[ \t]+/, "", s); recv = ""
          if (s ~ /^\(/) {
            r = s; sub(/\).*/, "", r); sub(/^\(/, "", r)
            m = split(r, parts, /[ \t*]+/); recv = parts[m]; sub(/\[.*/, "", recv)
            sub(/^\([^)]*\)[ \t]*/, "", s)
          }
          name = ident(s, "^[A-Za-z_][A-Za-z0-9_]*")
          if (name == "init" || name == "_") name = ""
          if (name != "" && recv != "") name = recv "." name
        } else if (text ~ /^type[ \t]/) {
          s = text; sub(/^type[ \t]+/, "", s); name = ident(s, "^[A-Za-z_][A-Za-z0-9_]*")
        }
      } else if (ext == "sh" || ext == "bash") {
        if (text ~ /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_:.-]*[ \t]*\(\)[ \t]*(\{|$)/) { s = text; sub(/^[ \t]*(function[ \t]+)?/, "", s); name = ident(s, "^[A-Za-z_][A-Za-z0-9_:.-]*") }
      } else if (ext == "py") {
        s = text
        if (s ~ /^(async[ \t]+)?def[ \t]/) { sub(/^(async[ \t]+)?def[ \t]+/, "", s); name = ident(s, "^[A-Za-z_][A-Za-z0-9_]*") }
        else if (s ~ /^class[ \t]/) { sub(/^class[ \t]+/, "", s); name = ident(s, "^[A-Za-z_][A-Za-z0-9_]*") }
      } else if (ext ~ /^(ts|tsx|js|jsx|mjs|cjs)$/) {
        s = text; sub(/^(export[ \t]+)?(default[ \t]+)?(async[ \t]+)?/, "", s)
        if (s ~ /^function/) { sub(/^function\*?[ \t]+/, "", s); name = ident(s, "^[A-Za-z_$][A-Za-z0-9_$]*") }
        else if (s ~ /^(const|let|var|class|interface|type|enum)[ \t]/) { sub(/^(const|let|var|class|interface|type|enum)[ \t]+/, "", s); name = ident(s, "^[A-Za-z_$][A-Za-z0-9_$]*") }
      }
      if (name == "") next
      if (ext == "go") { d = path; if (!sub(/\/[^\/]*$/, "", d)) d = "."; scope = d } else scope = path
      print scope "\t" name
    }'
}

# The scopes a definition can collide in, for a list of changed paths: the Go
# package directory, or the file itself for the other code languages.
code_scopes() {
  awk '
    /\.go$/ { d = $0; if (!sub(/\/[^\/]*$/, "", d)) d = "."; print "go\t" d; next }
    /\.(sh|bash|py|ts|tsx|js|jsx|mjs|cjs)$/ { print "file\t" $0 }
  ' | sort -u
}

duplicate_tells() { # <work> <merge-base> <base> <head> <merged-tree>
  local w="$1"
  awk -v S="$w/skip" 'BEGIN { while ((getline l < S) > 0) skip[l] = 1 } !($0 in skip)' "$w/base-files" | code_scopes > "$w/base-scopes"
  awk -v S="$w/skip" 'BEGIN { while ((getline l < S) > 0) skip[l] = 1 } !($0 in skip)' "$w/head-files" | code_scopes > "$w/head-scopes"
  comm -12 "$w/base-scopes" "$w/head-scopes" > "$w/scopes"
  [ -s "$w/scopes" ] || return 0
  awk -F'\t' '
    $1 == "go" { print ($2 == "." ? ":(glob)*.go" : ":(glob)" $2 "/*.go"); next }
    { print ":(literal)" $2 }' "$w/scopes" > "$w/specs"
  definitions "$2" "$w/specs" | sort -u > "$w/defs-mb"
  definitions "$3" "$w/specs" | sort -u > "$w/defs-base"
  definitions "$4" "$w/specs" | sort -u > "$w/defs-head"
  comm -23 "$w/defs-base" "$w/defs-mb" > "$w/new-base"
  comm -23 "$w/defs-head" "$w/defs-mb" > "$w/new-head"
  comm -12 "$w/new-base" "$w/new-head" > "$w/new-both"
  [ -s "$w/new-both" ] || return 0
  # Both sides adding the identical definition at one spot merges into one copy,
  # which is no collision. Count what the merge result actually carries; a
  # conflicted file keeps both sides' text, so a definition on each side counts
  # twice there too.
  definitions "$5" "$w/specs" | sort | uniq -c | awk '{ print $2 "\t" $3 "\t" $1 }' > "$w/defs-merged"
  awk -F'\t' -v M="$w/defs-merged" '
    BEGIN { while ((getline l < M) > 0) { split(l, f, "\t"); count[f[1] "\t" f[2]] = f[3] } }
    count[$1 "\t" $2] >= 2 { print "duplicate-definition\t" $1 "\t" $2 "\t" $2 }' "$w/new-both"
}

classify() { # <base> <branch>
  local base head mb rc tree p s1 s2 s3 w
  base=$(git rev-parse --verify --quiet "${1:-}^{commit}" 2>/dev/null) || return 2
  head=$(git rev-parse --verify --quiet "${2:-}^{commit}" 2>/dev/null) || return 2
  mb=$(git merge-base "$base" "$head" 2>/dev/null) || return 2
  [ -n "$mb" ] || return 2
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-branch-supersession.XXXXXX") || return 2
  # Set here as well as at the top: a command substitution runs classify in a
  # subshell, which does not inherit the EXIT trap.
  trap cleanup EXIT
  w="$WORK"
  git merge-tree --write-tree -z --no-messages "$base" "$head" > "$w/merge" 2>/dev/null; rc=$?
  # 1 is a conflict; anything else is a git that cannot run the probe.
  case "$rc" in 0|1) ;; *) return 2 ;; esac
  IFS= read -r -d '' tree < "$w/merge" || true
  [ -n "$tree" ] || return 2
  # Conflicted entries arrive as "<mode> <blob> <stage>\t<path>": one row per
  # path, its stage 1 (merge base), 2 (base side), 3 (branch) blobs, "-" absent.
  tr '\0' '\n' < "$w/merge" | tail -n +2 | awk -F'\t' '
    NF == 2 { split($1, a, " "); blob[$2, a[3]] = a[2]; seen[$2] = 1 }
    END { for (p in seen) printf "%s\t%s\t%s\t%s\n", p, ((p, 1) in blob ? blob[p, 1] : "-"), ((p, 2) in blob ? blob[p, 2] : "-"), ((p, 3) in blob ? blob[p, 3] : "-") }' \
    | sort > "$w/conflicts"
  git diff --name-only --no-renames "$mb" "$base" -- > "$w/base-files" 2>/dev/null || return 2
  git diff --name-only --no-renames "$mb" "$head" -- > "$w/head-files" 2>/dev/null || return 2
  { cut -f1 "$w/conflicts"; cat "$w/base-files" "$w/head-files"; } | sort -u | skip_paths "$base" | sort -u > "$w/skip"
  # Every line the base side added, trimmed. A block whose lines are here was
  # moved by the base side, not deleted.
  git diff --no-color --no-ext-diff --no-renames -U0 "$mb" "$base" -- 2>/dev/null \
    | awk '/^\+\+\+ / { next } /^\+/ { s = substr($0, 2); sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); if (length(s) >= 8) print s }' \
    | sort -u > "$w/base-added"
  : > "$w/evidence"
  while IFS=$'\t' read -r p s1 s2 s3; do
    [ -n "$p" ] || continue
    in_list "$p" "$w/skip" && continue
    if [ "$s1" != "-" ] && [ "$s2" = "-" ] && [ "$s3" != "-" ]; then
      deleted_file_tell "$p" "$s1" "$w/base-added" >> "$w/evidence"
    elif [ "$s1" != "-" ] && [ "$s2" != "-" ] && [ "$s3" != "-" ]; then
      git merge-file -p --diff3 --marker-size="$MARKER_SIZE" --object-id "$s2" "$s1" "$s3" 2>/dev/null \
        | hunk_tells "$p" "$w/base-added" >> "$w/evidence"
    fi
  done < "$w/conflicts"
  duplicate_tells "$w" "$mb" "$base" "$head" "$tree" >> "$w/evidence"
  [ -s "$w/evidence" ] || return 1
  cut -f1-3 "$w/evidence"
  # Name the commits that did it, not merely the latest ones on these paths: the
  # one that deleted the file, or the ones that changed how often the dropped line
  # or the doubled name occurs (git log -S).
  local tell path probe
  : > "$w/landed"
  while IFS=$'\t' read -r tell path _ probe; do
    if [ "$tell" = "deleted-file" ]; then
      git log --no-merges --diff-filter=D --format='%h%x09%s' "$mb..$base" -- "$path" </dev/null 2>/dev/null
    elif [ -n "$probe" ]; then
      git log --no-merges --format='%h%x09%s' "-S$probe" "$mb..$base" -- "$path" </dev/null 2>/dev/null
    fi
  done < "$w/evidence" >> "$w/landed"
  if [ ! -s "$w/landed" ]; then
    local paths=()
    mapfile -t paths < <(cut -f2 "$w/evidence" | sort -u)
    git log --no-merges --format='%h%x09%s' -n 3 "$mb..$base" -- "${paths[@]}" </dev/null 2>/dev/null > "$w/landed"
  fi
  awk '!seen[$0]++ && n++ < 5 { print "landed\t" $0 }' "$w/landed"
  return 0
}

# The decision a supersession puts to the operator, from the classify evidence.
brief() { # <label> <branch> <target> <anchor> <anchor-title> <head> <base> <pr> <evidence>
  local label="$1" branch="$2" target="$3" anchor="$4" title="$5" head="$6" base="$7" pr="$8" evidence="$9"
  local where landed more retire
  where=$(printf '%s\n' "$evidence" | awk -F'\t' -v t="$target" '
    $1 == "deleted-block"        { n++; split($3, s, " "); if (n <= 5) printf "- %s: %s deleted a %s-line block this branch edits\n", $2, t, s[1] }
    $1 == "rewritten-block"      { n++; split($3, s, " "); if (n <= 5) printf "- %s: %s rewrote a %s-line block this branch edits\n", $2, t, s[1] }
    $1 == "deleted-file"         { n++; if (n <= 5) printf "- %s: %s deleted this file, which this branch edits\n", $2, t }
    $1 == "duplicate-definition" { n++; if (n <= 5) printf "- %s: both sides now define %s\n", $2, $3 }
    END { if (n > 5) printf "- and %d more\n", n - 5 }')
  landed=$(printf '%s\n' "$evidence" | awk -F'\t' '$1 == "landed" { printf "- %s %s\n", $2, $3 }')
  [ -n "$landed" ] || landed="- (no commit on $target since the branch point touched these paths)"
  more=""; [ -n "$title" ] && more=" ($title)"
  if [ -n "$pr" ]; then retire="pr-dispose.sh closes the PR and disposes of the anchor"; else retire="bead-rehome.sh disposes of the anchor"; fi
  cat <<BRIEF
$label may be moot: a change already on $target deleted or rewrote code it edits

$label$more conflicts with $target, and the conflict is not drift. Bringing the branch current would mean either undoing what landed or rebuilding the branch on top of it. That is a decision about whether this work is still needed, so no merge-in rework was sent.

What landed on $target:
$landed

Where it collides:
$where

Your options:
- Retire it, if what landed covers this work. $retire, and nothing more is spent.
- Re-scope it, if part of the work still stands. Send a rework child that rebuilds the branch on top of what landed. That costs one polecat session.
- Bring it current anyway, if the overlap is incidental. Close this visit benign, and the next reconcile pass sends the ordinary merge-in child. That costs one polecat session.

No merge-in rework is sent for this branch while this visit is open. (anchor $anchor, branch $branch at ${head:0:8}, $target at ${base:0:8})
BRIEF
}

open_visits() { # <anchor>; prints "<id>\t<route>" per open supersession visit; non-zero when the store would not read
  local rows
  rows=$(bd_list --status="$LIVE_STATUSES" --metadata-field "escalation_key=$KEY" \
           --metadata-field "gc.continuation_group=$1") || return 1
  printf '%s' "$rows" | jq -r --arg a "$1" --arg k "$KEY" '
    .[] | select(((.metadata["gc.continuation_group"] // "") | tostring) == $a)
        | select(((.metadata.escalation_key // "") | tostring) == $k)
        | [.id, ((.metadata["gc.routed_to"] // "") | tostring)] | @tsv' 2>/dev/null
}

# The first of open_visits' rows whose route addresses somebody, by the verdict
# escalate.sh reads for an open visit it finds: `ok`, or `unknown` when the live
# agent set could not be read. No route, a pool no live agent carries, another
# rig's pool, and a rig-qualified route with no GC_RIG to check it against
# address nobody. Prints the visit id, or nothing.
asking_visit() { # <rows>
  local vid route
  while IFS=$'\t' read -r vid route; do
    [ -n "$vid" ] || continue
    case "$("$POOL_ROUTE" --verdict "$route" 2>/dev/null)" in
      ok|unknown) printf '%s\n' "$vid"; return 0 ;;
    esac
  done <<< "$1"
  return 0
}

hold() {
  local anchor="" branch="" target="" base="" head="" pr="" label rows prior vid route evidence crc title msg
  while [ $# -gt 0 ]; do
    case "$1" in
      --anchor) anchor="${2:-}"; shift 2 || { usage; return 2; } ;;
      --branch) branch="${2:-}"; shift 2 || { usage; return 2; } ;;
      --target) target="${2:-}"; shift 2 || { usage; return 2; } ;;
      --base)   base="${2:-}";   shift 2 || { usage; return 2; } ;;
      --head)   head="${2:-}";   shift 2 || { usage; return 2; } ;;
      --pr)     pr="${2:-}";     shift 2 || { usage; return 2; } ;;
      *) echo "$PROG: unknown argument '$1'" >&2; usage; return 2 ;;
    esac
  done
  if [ -z "$anchor" ] || [ -z "$branch" ] || [ -z "$target" ] || [ -z "$base" ] || [ -z "$head" ]; then
    echo "$PROG: hold needs --anchor, --branch, --target, --base and --head" >&2; usage; return 2
  fi
  label="Branch $branch"; [ -n "$pr" ] && label="PR#$pr"

  # A decision already open on this anchor holds the dispatch whatever the branch
  # looks like now: the person is ruling on this branch, and a merge-in child
  # performs one of the answers before they give it. The demand a sitting files
  # while working the visit sits on the visit, not the anchor, so the open visit
  # is what holds here. It holds only while its route addresses somebody. A visit
  # routed nowhere has asked nobody, so the branch is classified as though no
  # visit were open. On a supersession escalate.sh finds that visit and repoints
  # it, or refuses and the arm proceeds. On drift the arm proceeds. An unreadable
  # store answers nothing and falls through.
  rows=$(open_visits "$anchor") || rows=""
  vid=$(asking_visit "$rows")
  if [ -n "$vid" ]; then
    echo "$PROG: $anchor — $label conflicts with '$target'; supersession decision $vid is still open, no rework dispatched"
    return 0
  fi
  while IFS=$'\t' read -r vid route; do
    [ -n "$vid" ] && echo "$PROG: $anchor — supersession decision $vid is open, but its route '$route' addresses nobody, so it holds nothing" >&2
  done <<< "$rows"
  prior="$rows"

  evidence=$(classify "$base" "$head"); crc=$?
  case "$crc" in
    0) : ;;
    1) return 1 ;;
    *) echo "$PROG: $anchor — could not trial-merge $label against '$target'; treating the conflict as drift" >&2
       return 1 ;;
  esac

  title=$(bd_json show "$anchor" | jq -r '.[0].title // empty' 2>/dev/null)
  msg=$(brief "$label" "$branch" "$target" "$anchor" "$title" "$head" "$base" "$pr" "$evidence")
  if ! "$ESCALATE" --subject "$anchor" --key "$KEY" --message "$msg" >/dev/null 2>&1; then
    echo "$PROG: WARN $anchor — $label looks superseded, but the decision visit could not be filed or repointed at somebody; dispatching the ordinary merge-in child rather than holding with no record" >&2
    return 1
  fi
  # escalate.sh wrote to the store, so the pass's cached reads are stale.
  bd_cache_clear
  # The hold stands only behind an open visit that addresses somebody. escalate.sh
  # also exits 0 without filing when a sitting recently closed this situation moot
  # or benign, and that ruling is the release.
  rows=$(open_visits "$anchor") || rows=""
  vid=$(asking_visit "$rows")
  if [ -z "$vid" ]; then
    echo "$PROG: $anchor — $label looks superseded, but no supersession visit is open and routed to somebody (a recent moot or benign ruling answers it); dispatching the ordinary merge-in child"
    return 1
  fi
  # A visit that was open before escalate.sh ran, and addresses somebody only
  # now, is one it repointed.
  if grep -qxF -- "$vid" < <(cut -f1 <<< "$prior"); then
    echo "$PROG: $anchor — $label conflicts with '$target' because a landed change deleted or rewrote code it edits; repointed decision $vid at somebody, no rework dispatched"
  else
    echo "$PROG: $anchor — $label conflicts with '$target' because a landed change deleted or rewrote code it edits; filed decision $vid, no rework dispatched"
  fi
  return 0
}

case "${1:-}" in
  classify) shift; [ $# -eq 2 ] || { usage; exit 2; }; classify "$1" "$2"; exit $? ;;
  hold)     shift; hold "$@"; exit $? ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac
