#!/usr/bin/env bash
# warrants-touched.sh — list the warrants in docs/warrants.md a branch touches,
# each with its Verified date and what in the branch touches it.
#
# A change that touches what a warrant covers re-verifies that warrant in the
# same change, and the arch check's divergence lens sends back one that does
# not. The list comes from each entry's Covers line, so an added or edited entry
# needs no registry of its own. An entry is a `## ` section holding a Covers
# bullet, other than the page's `## An entry`, which describes the format.
# "An entry" on the page states what a Covers line can name and what touches it.
#
# The change runs from the merge base of BASE and HEAD to the working tree, the
# change `git diff --name-only BASE...HEAD` names for the rig's lint_command,
# and a renamed file counts under both its paths. A name is edited in code or
# config, so a changed line in a markdown file, a test or specs/ does not touch
# one, and Covers names a page it covers as a path. A named block or table that
# its file does not carry on either side counts the whole file, so a stale name
# lists too much rather than nothing.
#
# The list is advice. It fails nothing, because the arch review judges each
# re-verification. Callers: tools/lint.sh, which is how the list reaches the
# polecat's self-review, and a reviewer or author running it by hand.
#
# Usage: warrants-touched.sh [--base REV] [--covers]
#   --base REV  the revision a change is measured from (default: origin/main)
#   --covers    print what each entry's Covers line names, and read no change:
#               entry, kind, term and home file, tab-separated. A kind is path,
#               name, block or table, and `none` marks an entry naming nothing.
#
# Exit: 0 no warrant touched · 1 warrants listed · 2 it could not operate (not a
#       repository, a BASE git cannot read, or a page it cannot read or that
#       holds no entry), so nothing was checked
set -uo pipefail

PROG=warrants-touched
PAGE=docs/warrants.md
BASE=origin/main
COVERS_ONLY=0

fail() { echo "$PROG: $1" >&2; exit 2; }

usage() {
  [ -z "${1:-}" ] || echo "$PROG: $1" >&2
  echo "usage: $PROG [--base REV] [--covers]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || usage "--base needs a revision"; BASE=$2; shift 2 ;;
    --base=*) BASE=${1#--base=}; shift ;;
    --covers) COVERS_ONLY=1; shift ;;
    *) usage "unknown argument '$1'" ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a git repository"
cd "$ROOT" || fail "cannot enter the repository root $ROOT"
[ -r "$PAGE" ] || fail "cannot read $PAGE"

# ── The page ─────────────────────────────────────────────────────────────────
# Prints one E row per entry (entry, Verified date, Verified text, Covers text)
# and one T row per term its Covers line names (entry, kind, term, home file).
# A path Covers names only as the home of a block or table is that block or
# table, and any other path counts whole.
# shellcheck disable=SC2016  # An awk program, whose $ is awk field syntax.
PARSE_AWK='
function strip(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

function resolve(p,    part, n, i, out, depth, stack) {
  n = split(p, part, "/"); depth = 0
  for (i = 1; i <= n; i++) {
    if (part[i] == "." || part[i] == "") continue
    if (part[i] == "..") { if (depth > 0) depth--; continue }
    stack[++depth] = part[i]
  }
  out = ""
  for (i = 1; i <= depth; i++) out = out (i > 1 ? "/" : "") stack[i]
  return out
}

function emit(entry, kind, term, home) {
  if ((entry, kind, term, home) in said) return
  said[entry, kind, term, home] = 1
  printf "T\t%s\t%s\t%s\t%s\n", entry, kind, term, home
}

function terms(entry, s,    n, rest, tok, after, kind, val, is_home, whole, i, t, body, target, a, home) {
  n = 0; rest = s
  while (match(rest, /`[^`]+`|\[[^]]*\]\([^)]*\)/)) {
    n++
    tok[n] = substr(rest, RSTART, RLENGTH)
    if (n > 1) after[n - 1] = substr(rest, 1, RSTART - 1)
    rest = substr(rest, RSTART + RLENGTH)
  }
  if (n > 0) after[n] = rest

  for (i = 1; i <= n; i++) {
    t = tok[i]
    if (substr(t, 1, 1) == "[") {
      target = t
      sub(/^\[[^]]*\]\(/, "", target); sub(/\)$/, "", target); sub(/#.*$/, "", target)
      if (target == "" || target ~ /:/) { kind[i] = "other"; continue }
      val[i] = resolve(PAGE_DIR "/" target)
      kind[i] = "path"
      continue
    }
    body = substr(t, 2, length(t) - 2)
    val[i] = body
    if (body ~ /^\[.*\]$/) kind[i] = "table"
    else if (body !~ / / && (body ~ /\// || (body in root_name))) {
      sub(/\/$/, "", val[i])
      kind[i] = "path"
    }
    else kind[i] = "word"
  }

  for (i = n; i >= 1; i--) {
    if (kind[i] != "word") continue
    a = after[i]
    if (a ~ /^ (key|keys|name|names|file)([^a-z]|$)/) kind[i] = "name"
    else if (a ~ /^ block (of|in) $/ && kind[i + 1] == "path") kind[i] = "block"
    else if (kind[i + 1] == "name" && a ~ /^(, | and | or |, and |, or )$/) kind[i] = "name"
  }

  for (i = 2; i <= n; i++) {
    if (kind[i] != "path") continue
    a = after[i - 1]
    if ((kind[i - 1] == "block" && a ~ /^ block (of|in) $/) \
        || (kind[i - 1] == "table" && a ~ /^( table)? (of|in) $/)) is_home[i] = 1
  }

  home = "-"
  for (i = 1; i <= n; i++) {
    if (kind[i] == "path") {
      if (val[i] ~ /\.toml$/) home = val[i]
      if (!is_home[i]) emit(entry, "path", val[i], "-")
    }
    else if (kind[i] == "name") emit(entry, "name", val[i], "-")
    else if (kind[i] == "block") emit(entry, "block", val[i], val[i + 1])
    else if (kind[i] == "table") {
      if (is_home[i + 1]) emit(entry, "table", val[i], val[i + 1])
      else if (home != "-") emit(entry, "table", val[i], home)
      else emit(entry, "name", val[i], "-")
    }
  }
}

function end_entry(    date) {
  if (heading == "" || covers == "" || heading == "An entry") return
  date = "none"
  if (match(verified, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) date = substr(verified, RSTART, RLENGTH)
  printf "E\t%s\t%s\t%s\t%s\n", heading, date, (verified == "" ? "none" : verified), covers
  terms(heading, covers)
}

BEGIN {
  n_root = split(ENVIRON["ROOT_NAMES"], root_list, "\n")
  for (r = 1; r <= n_root; r++) root_name[root_list[r]] = 1
  PAGE_DIR = ENVIRON["PAGE_DIR"]
}
/^## / { end_entry(); heading = strip(substr($0, 4)); covers = ""; verified = ""; field = ""; next }
/^- \*\*Covers\.\*\*/ { field = "covers"; covers = strip(substr($0, 14)); next }
/^- \*\*Verified\.\*\*/ { field = "verified"; verified = strip(substr($0, 16)); next }
/^- / || /^[ \t]*$/ { field = ""; next }
field == "covers" { covers = covers " " strip($0); next }
field == "verified" { verified = verified " " strip($0); next }
END { end_entry() }
'

parse_page() {
  ROOT_NAMES="$ROOT_NAMES" PAGE_DIR="${PAGE%/*}" awk "$PARSE_AWK"
}

ROOT_NAMES=$(git ls-tree --name-only HEAD 2>/dev/null)
ROWS=$(parse_page < "$PAGE") || fail "cannot parse $PAGE"
case "$ROWS" in
  E*) ;;
  *) fail "$PAGE holds no entry with a Covers line" ;;
esac

if [ "$COVERS_ONLY" = 1 ]; then
  # An E row with no T row beneath it is an entry naming nothing the list matches.
  printf '%s\n' "$ROWS" | awk -F'\t' '
    function close_entry() { if (open != "" && !named) printf "%s\tnone\t-\t-\n", open }
    $1 == "E" { close_entry(); open = $2; named = 0; next }
    $1 == "T" { named = 1; printf "%s\t%s\t%s\t%s\n", $2, $3, $4, $5 }
    END { close_entry() }
  '
  exit 0
fi

# ── The change ───────────────────────────────────────────────────────────────
BASE_OID=$(git rev-parse -q --verify "$BASE^{commit}") \
  || fail "cannot read base revision '$BASE', so the change is unknown"
MERGE_BASE=$(git merge-base "$BASE_OID" HEAD) || fail "HEAD shares no history with '$BASE'"
CHANGED=$(git -c core.quotePath=false diff --no-renames --name-only "$MERGE_BASE" --) \
  || fail "cannot list the files changed since $MERGE_BASE"

path_changed() {  # path: is it, or anything under it, among the changed files?
  printf '%s\n' "$CHANGED" | PATH_NAME="$1" awk '
    BEGIN { p = ENVIRON["PATH_NAME"] }
    $0 == p || index($0, p "/") == 1 { found = 1 }
    END { exit !found }
  '
}

# Prints a `# >>> name` fence, or a [table] with the tables under it, from stdin.
part_of() {  # kind name
  PART_KIND="$1" PART_NAME="$2" awk '
    function strip(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    BEGIN {
      kind = ENVIRON["PART_KIND"]; name = ENVIRON["PART_NAME"]
      under = substr(name, 1, length(name) - 1) "."
    }
    kind == "block" {
      line = strip($0)
      if (line == "# >>> " name) on = 1
      if (on) print
      if (line == "# <<< " name) on = 0
      next
    }
    /^\[/ {
      header = $0
      sub(/\].*$/, "]", header)
      on = (header == name || index(header, under) == 1)
    }
    on { print }
  '
}

# Prints name, then file, for each name a changed line carries whole, once per
# file. A line in the diff always opens with a marker, so `diff --git` and `@@`
# at the start of a line are always structure, and every header line up to the
# first hunk is skipped whatever its text.
# shellcheck disable=SC2016  # An awk program, whose $ is awk field syntax.
NAME_AWK='
function names(s, name,    at, pos, before, later) {
  pos = 1
  while ((at = index(substr(s, pos), name)) > 0) {
    at += pos - 1
    before = (at > 1) ? substr(s, at - 1, 1) : ""
    later = substr(s, at + length(name), 1)
    if (before !~ /[A-Za-z0-9_-]/ && later !~ /[A-Za-z0-9_-]/) return 1
    pos = at + 1
  }
  return 0
}
BEGIN { n = split(ENVIRON["NAMES"], name, "\n") }
/^diff --git / { in_header = 1; file = ""; next }
/^@@ / { in_header = 0; next }
in_header {
  if (index($0, "--- a/") == 1 || index($0, "+++ b/") == 1) file = substr($0, 7)
  next
}
/^[-+]/ {
  line = substr($0, 2)
  for (i = 1; i <= n; i++) {
    if (((i, file) in seen) || !names(line, name[i])) continue
    seen[i, file] = 1
    printf "%s\t%s\n", name[i], file
  }
}
'

NAMES=$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 == "T" && $3 == "name" && !seen[$4]++ { print $4 }')
NAME_HITS=""
if [ -n "$NAMES" ] && [ -n "$CHANGED" ]; then
  NAME_HITS=$(git -c core.quotePath=false diff --no-renames --no-color --no-ext-diff \
    --no-textconv --src-prefix=a/ --dst-prefix=b/ -U0 "$MERGE_BASE" -- . ':(exclude,glob)**/*.md' ':(exclude,glob)**/*.test.sh' ':(exclude,glob)**/*_test.go' ':(exclude)specs/**' \
    | NAMES="$NAMES" awk "$NAME_AWK") || fail "cannot read the lines changed since $MERGE_BASE"
fi

# ── What each term touches ───────────────────────────────────────────────────
HITS=""
hit() { HITS="$HITS$1"$'\t'"$2"$'\n'; }

while IFS=$'\t' read -r tag entry kind term home; do
  [ "$tag" = T ] || continue
  case "$kind" in
    path)
      path_changed "$term" && hit "$entry" "changes $term" ;;
    name)
      files=$(printf '%s\n' "$NAME_HITS" | NAME="$term" awk -F'\t' '
        $1 == ENVIRON["NAME"] { n++; if (n <= 3) out = out (n > 1 ? ", " : "") $2 }
        END { if (n > 3) out = out " and " (n - 3) " more"; print out }
      ')
      [ -z "$files" ] || hit "$entry" "a changed line names $term, in $files" ;;
    block|table)
      path_changed "$home" || continue
      old=$(git show "$MERGE_BASE:$home" 2>/dev/null | part_of "$kind" "$term")
      new=""
      [ ! -f "$home" ] || new=$(part_of "$kind" "$term" < "$home")
      if [ -z "$old" ] && [ -z "$new" ]; then
        hit "$entry" "changes $home, whose $kind $term Covers names and neither side carries"
      elif [ "$old" != "$new" ]; then
        hit "$entry" "changes the $kind $term of $home"
      fi ;;
  esac
done < <(printf '%s\n' "$ROWS")

if [ -z "$HITS" ]; then
  echo "$PROG: since $BASE, this branch touches no warrant in $PAGE"
  exit 0
fi

# ── The list ─────────────────────────────────────────────────────────────────
BASE_ROWS=$(git show "$MERGE_BASE:$PAGE" 2>/dev/null | parse_page)
LISTED=0
echo "$PROG: since $BASE, this branch touches these warrants in $PAGE:"
while IFS=$'\t' read -r tag entry date verified covers; do
  [ "$tag" = E ] || continue
  lines=$(printf '%s' "$HITS" | ENTRY="$entry" awk -F'\t' '$1 == ENVIRON["ENTRY"] { print "    " $2 }')
  [ -n "$lines" ] || continue
  LISTED=$((LISTED + 1))
  old_verified=$(printf '%s\n' "$BASE_ROWS" | ENTRY="$entry" awk -F'\t' '$1 == "E" && $2 == ENVIRON["ENTRY"] { print $4 }')
  if [ -z "$old_verified" ]; then state="added on this branch"
  elif [ "$old_verified" = "$verified" ]; then state="not updated on this branch"
  else state="updated on this branch"; fi
  echo "- $entry: Verified $date, $state"
  printf '%s\n' "$lines"
  echo "    Covers: $covers"
done < <(printf '%s\n' "$ROWS")
echo "$PROG: $LISTED warrant(s). A change that touches what a warrant covers re-verifies it in that change: check its Evidence against Gas City's current upstream documentation, test its Retires when trigger, and update Verified. A file Covers names for one part of it, such as a verb or a function, is touched only when the change reaches that part."
exit 1
