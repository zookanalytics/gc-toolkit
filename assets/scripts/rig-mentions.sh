#!/usr/bin/env bash
# rig-mentions.sh — list each place a change names another rig of this city:
# the rig's name, a bead id from its store, or a path into its checkout.
#   rig-mentions.sh [--rig <name>] [--branch <base>] [--bead <id>]
#                   [--file <path>]... [--tree]
#
#   --branch <base>  the lines the branch adds since it left <base>, and the
#                    messages of its commits that no remote has yet
#   --bead <id>      the title, summary and dispatch text the bead's pull
#                    request publishes. A rework child's pull request is its
#                    anchor's, so the anchor's are read.
#   --file <path>    a whole file, such as a summary not yet on a bead
#   --tree           every tracked file
#   --rig <name>     the rig the change is for. Without it, that is the rig
#                    whose checkout holds this repository, else $GC_RIG.
#
# Rigs shouldn't use other rigs for data in a commit or a PR. The squash merge
# takes its commit message from the pull request's body, so the title, summary
# and dispatch text land in the history as surely as a file does.
#
# The names come from the city the script runs in (`gc rig list`), so a
# repository never commits the names it looks for. The rig the change is for
# is not another rig, and neither is a rig the pack runs on or with: Gas City,
# the platform (gascity), the pack itself (gc-toolkit), and the engine its demo
# capture drives (sprintshow). Each of those is named as a dependency, not used
# for data. A name matches whole, case aside, with its separators written any
# way (rig-a, Rig A, riga); a bead id is a rig's prefix, a dash, and at least
# two more letters or digits; a path is the rig's path as the city lists it.
#
# The list is advice. It cannot tell a rig used for data from a word that
# happens to be a rig's name, so the reader decides what to change.
#
# Callers: the self-review of formulas/mol-polecat-work.toml, on the branch and
# the work bead, and its submit-and-exit, on the summary it composes. Each
# reads the list and fixes what it finds, and neither stops on it.
#
# Exit: 0 no other rig named · 1 mentions printed, one per line, then the
#       advice · 2 usage, or the rig list, a bead, a file or the repository
#       could not be read, so nothing was checked
set -uo pipefail

PROG="rig-mentions"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 2; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

PACK_DEPENDENCIES="gascity gc-toolkit sprintshow"

usage() {
  [ -z "${1:-}" ] || echo "$PROG: $1" >&2
  echo "usage: $PROG [--rig <name>] [--branch <base>] [--bead <id>] [--file <path>]... [--tree]" >&2
  exit 2
}
fail() { echo "$PROG: $1; nothing was checked" >&2; exit 2; }

RIG=""; BASE=""; BEAD=""; TREE=""; FILES=(); NFILES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --rig|--branch|--bead|--file)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage "$1 needs a value"
      case "$1" in
        --rig) RIG="$2" ;;
        --branch) BASE="$2" ;;
        --bead) BEAD="$2" ;;
        --file) FILES+=("$2"); NFILES=$((NFILES + 1)) ;;
      esac
      shift 2 ;;
    --tree) TREE=1; shift ;;
    -h|--help) usage ;;
    *) usage "unknown argument '$1'" ;;
  esac
done
[ -n "$BASE$BEAD$TREE" ] || [ "$NFILES" -gt 0 ] || usage "name what to read: --branch, --bead, --file or --tree"

# rig-map.sh is the pack's one read of the rig map. It bounds the listing, and
# when the listing does not read it names why on stderr, ahead of the line below.
RIGS=$("$HERE/rig-map.sh" | jq -c '[.rigs[]? | objects
  | {name: (.name // "" | tostring), prefix: (.prefix // "" | tostring), path: (.path // "" | tostring)}
  | select(.name != "")]' 2>/dev/null) || RIGS=""
[ -n "$RIGS" ] && [ "$RIGS" != "[]" ] || fail "cannot read the city's rigs (gc rig list --json)"

# The rig whose checkout holds this repository: a worktree's common directory
# is the .git of the checkout it was added to.
if [ -z "$RIG" ] && common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  here=$(cd -P "$(dirname "$common")" 2>/dev/null && pwd) || here=""
  while IFS=$'\t' read -r name path; do
    [ -n "$here" ] && [ -n "$path" ] || continue
    [ "$(cd -P "$path" 2>/dev/null && pwd)" = "$here" ] && { RIG="$name"; break; }
  done < <(printf '%s' "$RIGS" | jq -r '.[] | [.name, .path] | @tsv')
fi
RIG="${RIG:-${GC_RIG:-}}"
[ -n "$RIG" ] || fail "cannot tell which rig this change is for: run it in a rig's checkout, or pass --rig"
printf '%s' "$RIGS" | jq -e --arg r "$RIG" 'any(.[]; .name == $r)' >/dev/null 2>&1 \
  || fail "'$RIG' is not a rig of this city"
SELF_PREFIX=$(printf '%s' "$RIGS" | jq -r --arg r "$RIG" 'first(.[] | select(.name == $r)) | .prefix')

# The other rigs, one per line: name, bead prefix, path.
OTHERS=$(printf '%s' "$RIGS" | jq -r --arg self "$RIG" --arg deps "$PACK_DEPENDENCIES" '
  ($deps | split(" ")) as $d
  | .[] | select(.name != $self) | select(.name as $n | $d | index($n) | not)
  | [.name, .prefix, .path] | @tsv')
if [ -z "$OTHERS" ]; then
  echo "$PROG: no other rig in this city to look for"
  exit 0
fi

LINES="$(mktemp "${TMPDIR:-/tmp}/gctk-rig-mentions.XXXXXX")" || fail "cannot make a temp file"
trap 'rm -f "$LINES"' EXIT

# Each source adds "<where>\t<text>" lines; one matcher reads them all.
number() { awk -v at="$1" '{ print at ":" NR "\t" $0 }'; }

if [ -n "$BASE" ]; then
  git rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1 || fail "cannot resolve '$BASE' in this repository"
  diff=$(git -c core.quotePath=false diff -U0 --no-color --no-ext-diff "$BASE...HEAD" 2>/dev/null) \
    || fail "cannot diff $BASE...HEAD"
  # git ends a +++ line with a tab when the file's name holds a space.
  printf '%s\n' "$diff" | awk '
    /^diff --git / { hunk = 0; file = ""; next }
    /^@@ / { hunk = 1; split($3, h, ","); line = substr(h[1], 2) + 0; next }
    !hunk && /^\+\+\+ / { file = substr($0, 5); sub(/^b\//, "", file); sub(/\t$/, "", file); next }
    hunk && /^\+/ { print file ":" line "\t" substr($0, 2); line++ }
  ' >> "$LINES"
  # A commit a remote already has is public, and changing its message needs a
  # force-push, so only the commits still local are read.
  commits=$(git rev-list HEAD --not "$BASE" --remotes 2>/dev/null) || fail "cannot list the commits since $BASE"
  for c in $commits; do
    git log -1 --format=%B "$c" | number "commit $(git rev-parse --short "$c")" >> "$LINES"
  done
fi

if [ -n "$BEAD" ]; then
  row=$(bd_json show "$BEAD")
  printf '%s' "$row" | jq -e '.[0].id' >/dev/null 2>&1 || fail "cannot read bead $BEAD"
  anchor=$(row_meta "$row" anchor_bead)
  if [ -n "$anchor" ] && [ "$anchor" != "$BEAD" ]; then
    BEAD="$anchor"
    row=$(bd_json show "$BEAD")
    printf '%s' "$row" | jq -e '.[0].id' >/dev/null 2>&1 || fail "cannot read bead $BEAD, the anchor whose pull request this is"
  fi
  printf '%s' "$row" | jq -r '.[0].title // ""' | number "$BEAD title" >> "$LINES"
  row_meta "$row" pr_summary | number "$BEAD pr_summary" >> "$LINES"
  printf '%s' "$row" | jq -r '.[0].description // ""' | number "$BEAD description" >> "$LINES"
fi

for f in ${FILES[@]+"${FILES[@]}"}; do
  [ -f "$f" ] && [ -r "$f" ] || fail "cannot read $f"
  number "$f" < "$f" >> "$LINES"
done

if [ -n "$TREE" ]; then
  top=$(git rev-parse --show-toplevel 2>/dev/null) || fail "--tree needs a repository"
  # Every line of every tracked text file. grep tells a binary file by its
  # content: git grep would also skip the files .gitattributes marks -diff,
  # such as generated/, which are as public as any other. A symlink is left
  # out, since grep would read its target, which is tracked and read on its
  # own. --null ends each path with a NUL, which awk cannot hold, so it
  # becomes a tab.
  ( cd "$top" && git -c core.quotePath=false ls-files -s \
      | awk '$1 != "120000" { sub(/^[^\t]*\t/, ""); print }' | tr '\n' '\000' \
      | xargs -0 grep -I -n -H --null -e '' -- 2>/dev/null ) | tr '\000' '\t' \
    | awk '{
        t = index($0, "\t"); file = substr($0, 1, t - 1); rest = substr($0, t + 1)
        c = index(rest, ":"); print file ":" substr(rest, 1, c - 1) "\t" substr(rest, c + 1)
      }' >> "$LINES"
fi

# The text is matched with a space on each side, so a name or an id at either
# end of a line still has a character before and after it to bound it.
FOUND=$(printf '%s\n' "$OTHERS" | awk -F'\t' '
  function say(msg) { if (!(msg in seen)) { seen[msg] = 1; print msg } }
  NR == FNR {
    n++; name[n] = $1; prefix[n] = $2; path[n] = $3
    # The separators of a name may be written any way, or left out.
    re = ""; k = split(tolower($1), part, /[-_. ]/)
    for (j = 1; j <= k; j++) re = re (j > 1 ? "[-_. ]?" : "") part[j]
    name_re[n] = "[^a-z0-9]" re "[^a-z0-9]"
    id_re[n] = "[^A-Za-z0-9]" prefix[n] "-[a-z0-9][a-z0-9]"
    next
  }
  {
    tab = index($0, "\t"); at = substr($0, 1, tab - 1); text = " " substr($0, tab + 1) " "
    for (i = 1; i <= n; i++) {
      if (tolower(text) ~ name_re[i]) say(at ": names rig " name[i])
      if (path[i] != "" && path[i] != "/" && index(text, path[i])) say(at ": names " path[i] ", the checkout of rig " name[i])
      if (prefix[i] == "") continue
      s = text
      while (match(s, id_re[i])) {
        s = substr(s, RSTART + 1)
        match(s, "^[a-z0-9]+(-[a-z0-9]+)*(\\.[0-9]+)*")
        say(at ": names bead " substr(s, 1, RLENGTH) " of rig " name[i])
        s = substr(s, RLENGTH + 1)
      }
    }
  }
' - "$LINES") || fail "cannot match the text read"

if [ -z "$FOUND" ]; then
  echo "$PROG: no other rig named"
  exit 0
fi
printf '%s\n' "$FOUND"
echo "$PROG: $(printf '%s\n' "$FOUND" | grep -c .) mention(s) of another rig. Rigs shouldn't use other rigs for data in a commit or a PR: write <rig> for a rig, and a $SELF_PREFIX- id for an example bead."
exit 1
