#!/usr/bin/env bash
# demo-repo-artifact.sh — the demo check's repo-artifact modality: find the
# visuals a reviewed commit already carries, and attach the chosen one to the
# PR inline.
#
# `deliver` writes the file exactly as the reviewed commit stores it, never the
# working tree's copy, so what posts is what was reviewed. It hands the file to
# demo-deliver.sh, the delivery every demo modality uses, which uploads it to
# GitHub's user-attachments and posts it inline in a comment on the subject's
# PR.
#
# `candidates` is the search. A visual is a file of an image or video type
# GitHub accepts as an attachment (the extensions in VISUAL_EXTS below, in any
# case). Each visual present at the reviewed commit is listed once, under the
# strongest reason that applies:
#   changed  the diff adds or edits it.
#   named    a line the diff adds names it, as a path from the repository root
#            or from that file's own directory, or the anchor bead's title,
#            description, design, notes or pr_summary names it from the root.
#   near     its directory is at most two steps from a changed file's. The same
#            directory is zero steps, the parent or a child is one, and a
#            sibling, the grandparent or a grandchild is two. Nearest first,
#            and at most NEAR_CAP of them.
# The list says where to look. Which visual shows the change is the reviewer's
# call.
#
# Usage:
#   demo-repo-artifact.sh candidates --base <ref> --oid <commit> [--anchor <bead>] [--repo <dir>]
#   demo-repo-artifact.sh deliver --path <path> --oid <commit> --subject <bead> [--body <text>] [--repo <dir>]
#
#   --base     the ref the change is reviewed against. The diff runs from its
#              merge base with --oid, the three-dot diff a review reads.
#   --oid      the reviewed commit.
#   --anchor   the bead whose text may name a visual.
#   --repo     the repository holding both commits (default: the current
#              directory).
#   --path     the visual to deliver, as a path from the repository root.
#   --subject  the bead whose PR receives it, passed to demo-deliver.sh.
#   --body     the comment text. By default it names the path and the commit.
#
#   candidates prints one line per visual, "<reason><TAB><path>": changed
#   first, then named, then near.
#
# Exit: candidates: 0 listed, 3 no visual at the commit is changed, named or
#   near. deliver: 0 delivered, otherwise demo-deliver.sh's exit. Both: 2 bad
#   arguments, 1 anything else that stopped them, such as a commit that does not
#   resolve or a path that is not a committed visual.
set -uo pipefail

PROG=demo-repo-artifact
VISUAL_EXTS="png jpg jpeg gif svg mp4 mov webm"
NEAR_CAP=20
TAB=$(printf '\t')
DELIVER="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/demo-deliver.sh"

usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
usage_err() { echo "$PROG: $1" >&2; usage >&2; exit 2; }
fail() { echo "$PROG: $1" >&2; exit 1; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

is_visual() {
  local ext
  case "$1" in *.*) ext=$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]') ;; *) return 1 ;; esac
  case " $VISUAL_EXTS " in *" $ext "*) return 0 ;; esac
  return 1
}

need_value() { [ "$2" -gt 1 ] || usage_err "$1 needs a value"; }

resolve_commit() {
  git -C "$REPO" rev-parse --verify -q "$2^{commit}" 2>/dev/null \
    || fail "$1 '$2' is not a commit in $REPO"
}

# ---------------------------------------------------------------------------
# The lines each file's diff adds, as "<file><TAB><line>". A header line is
# only read between `diff --git` and the first hunk, so an added line that
# itself begins "++ " is never taken for a `+++` header.
ADDED_LINES_AWK='
/^diff --git / { hdr = 1; f = ""; next }
hdr && /^\+\+\+ / { f = substr($0, 5); if (substr(f, 1, 2) == "b/") f = substr(f, 3); else f = ""; next }
hdr && /^@@/ { hdr = 0; next }
hdr { next }
/^\+/ { if (f != "") print f "\t" substr($0, 2) }
'

# Keeps the regular files of `git ls-tree -r` whose extension is a visual's. A
# symlink or a submodule is not a file deliver could attach.
VISUAL_FILTER_AWK='
BEGIN { n = split(exts, e, " "); for (i = 1; i <= n; i++) ok[e[i]] = 1 }
{
  t = index($0, "\t"); if (t == 0) next
  if (substr($0, 1, t - 1) !~ "^100(644|755) blob ") next
  path = substr($0, t + 1)
  k = split(path, parts, "."); if (k > 1 && (tolower(parts[k]) in ok)) print path
}
'

# Ranks each visual: 1 changed, 2 named, 3 near (with its step count). A token
# is a maximal run of path characters, less any trailing dots, so a.png.bak and
# a.png/b are not references to a.png. Splitting keeps the scan linear: a regex
# search for path-shaped runs restarts at every byte of a long run, such as a
# base64 data URI, and goes quadratic.
RANK_AWK='
function dirof(p,   i) { i = match(p, "/[^/]*$"); return i ? substr(p, 1, i - 1) : "" }
function dsplit(d, arr) { return (d == "") ? 0 : split(d, arr, "/") }
function norm(p,   n, parts, out, k, i, seg) {
  n = split(p, parts, "/"); k = 0
  for (i = 1; i <= n; i++) {
    seg = parts[i]
    if (seg == "" || seg == ".") continue
    if (seg == "..") { if (k == 0) return ""; k--; continue }
    out[++k] = seg
  }
  p = ""
  for (i = 1; i <= k; i++) p = p (i > 1 ? "/" : "") out[i]
  return p
}
function mark(p, r) { if (!(p in rank) || r < rank[p]) rank[p] = r }
function scan(line, from,   n, toks, i, tok, k, parts, p) {
  n = split(line, toks, "[^A-Za-z0-9_./@+~-]+")
  for (i = 1; i <= n; i++) {
    tok = toks[i]
    while (tok != "" && substr(tok, length(tok)) == ".") tok = substr(tok, 1, length(tok) - 1)
    k = split(tok, parts, ".")
    if (k < 2 || !(tolower(parts[k]) in ok)) continue
    if (from != "") { p = norm(dirof(from) "/" tok); if (p in vis) mark(p, 2) }
    p = norm(tok); if (p in vis) mark(p, 2)
  }
}
BEGIN {
  n = split(exts, e, " ")
  for (i = 1; i <= n; i++) ok[e[i]] = 1
  while ((getline line < visfile) > 0) vis[line] = 1
  while ((getline line < chgfile) > 0) {
    if (line in vis) mark(line, 1)
    d = dirof(line)
    if (!(d in seen)) {
      seen[d] = 1; m = dsplit(d, tmp); cdn[++ncd] = m
      for (k = 1; k <= m; k++) cdp[ncd, k] = tmp[k]
    }
  }
  while ((getline line < addfile) > 0) {
    t = index(line, "\t")
    if (t > 0) scan(substr(line, t + 1), substr(line, 1, t - 1))
  }
  while ((getline line < anchfile) > 0) scan(line, "")
  # Steps between two directories: up from one to their common parent, then
  # down to the other.
  for (p in vis) {
    if (p in rank) continue
    nv = dsplit(dirof(p), pv); best = 3
    for (j = 1; j <= ncd && best > 0; j++) {
      m = cdn[j]
      if (nv - m > 2 || m - nv > 2) continue
      c = 0
      while (c < nv && c < m && pv[c + 1] == cdp[j, c + 1]) c++
      s = (nv - c) + (m - c)
      if (s < best) best = s
    }
    if (best <= 2) { rank[p] = 3; dist[p] = best }
  }
  for (p in rank) printf "%d\t%d\t%s\n", rank[p], (rank[p] == 3 ? dist[p] : 0), p
}
'

# Names each ranked line and holds near to its cap; the count cut goes to
# cutfile, and the exit says whether anything was listed.
EMIT_AWK='
BEGIN { FS = "\t"; split("changed named near", name, " ") }
{ if ($1 == 3 && ++near > cap) { cut++; next } print name[$1] "\t" $3; shown++ }
END { print (cut + 0) > cutfile; exit (shown ? 0 : 3) }
'

# ---------------------------------------------------------------------------
cmd_candidates() {
  local base="" oid="" anchor=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --base)   need_value "$1" $#; shift; base="$1" ;;
      --oid)    need_value "$1" $#; shift; oid="$1" ;;
      --anchor) need_value "$1" $#; shift; anchor="$1" ;;
      --repo)   need_value "$1" $#; shift; REPO="$1" ;;
      -h|--help) usage; exit 0 ;;
      *) usage_err "unknown argument '$1'" ;;
    esac
    shift
  done
  [ -n "$base" ] || usage_err "--base is required"
  [ -n "$oid" ] || usage_err "--oid is required"
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || fail "'$REPO' is not a git repository"

  local c b mb
  c=$(resolve_commit --oid "$oid") || exit 1
  b=$(resolve_commit --base "$base") || exit 1
  mb=$(git -C "$REPO" merge-base "$b" "$c" 2>/dev/null) || fail "'$base' and '$oid' share no merge base"

  TMPD=$(mktemp -d "${TMPDIR:-/tmp}/demo-repo-artifact.XXXXXX") || fail "cannot make a temp dir"
  trap 'rm -rf "$TMPD"' EXIT
  git -C "$REPO" -c core.quotePath=false ls-tree -r --full-tree "$c" \
    | awk -v exts="$VISUAL_EXTS" "$VISUAL_FILTER_AWK" >"$TMPD/visuals" \
    || fail "cannot list the files at $oid"
  git -C "$REPO" -c core.quotePath=false diff --name-only --no-renames --no-relative "$mb" "$c" >"$TMPD/changed" \
    || fail "cannot list the files changed between '$base' and '$oid'"
  git -C "$REPO" -c core.quotePath=false diff --no-color --no-ext-diff --no-textconv --no-renames --no-relative \
      --unified=0 --src-prefix=a/ --dst-prefix=b/ "$mb" "$c" \
    | awk "$ADDED_LINES_AWK" >"$TMPD/added" \
    || fail "cannot read the diff between '$base' and '$oid'"
  : >"$TMPD/anchor"
  if [ -n "$anchor" ]; then
    if ! command -v gc >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
      echo "$PROG: gc or jq not found, so the text of anchor $anchor was not searched" >&2
    elif ! gc bd show "$anchor" --json 2>/dev/null | scrub \
        | jq -r '.[0] | [.title, .description, .design, .notes, .metadata.pr_summary] | .[] | select(type == "string")' \
        >"$TMPD/anchor" 2>/dev/null; then
      echo "$PROG: could not read anchor $anchor, so its text was not searched" >&2
      : >"$TMPD/anchor"
    fi
  fi

  awk -v exts="$VISUAL_EXTS" -v visfile="$TMPD/visuals" -v chgfile="$TMPD/changed" \
      -v addfile="$TMPD/added" -v anchfile="$TMPD/anchor" "$RANK_AWK" </dev/null \
    | LC_ALL=C sort -t "$TAB" -k1,1n -k2,2n -k3 \
    | awk -v cap="$NEAR_CAP" -v cutfile="$TMPD/cut" "$EMIT_AWK"
  # Every stage's status is read, because pipefail would report a failed
  # ranking as the last stage's 3, an empty list.
  local st="${PIPESTATUS[*]}" cut
  cut=$(cat "$TMPD/cut" 2>/dev/null)
  case "$st" in
    "0 0 0") [ "${cut:-0}" -gt 0 ] && echo "$PROG: $cut more visual(s) near the diff not listed" >&2; exit 0 ;;
    "0 0 3") echo "$PROG: no visual at $oid is changed, named or near the diff" >&2; exit 3 ;;
    *) fail "ranking the candidates failed (exit statuses: $st)" ;;
  esac
}

cmd_deliver() {
  local path="" oid="" subject="" body=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --path)    need_value "$1" $#; shift; path="$1" ;;
      --oid)     need_value "$1" $#; shift; oid="$1" ;;
      --subject) need_value "$1" $#; shift; subject="$1" ;;
      --body)    need_value "$1" $#; shift; body="$1" ;;
      --repo)    need_value "$1" $#; shift; REPO="$1" ;;
      -h|--help) usage; exit 0 ;;
      *) usage_err "unknown argument '$1'" ;;
    esac
    shift
  done
  [ -n "$path" ] || usage_err "--path is required"
  [ -n "$oid" ] || usage_err "--oid is required"
  [ -n "$subject" ] || usage_err "--subject is required"
  path=${path#./}
  case "/$path/" in
    *//*|*/./*|*/../*) fail "--path '$path' must be a path from the repository root" ;;
  esac
  is_visual "$path" || fail "'$path' is not an image or video of a type GitHub accepts as an attachment ($VISUAL_EXTS)"
  [ -x "$DELIVER" ] || fail "demo-deliver.sh not found beside this script"

  local c entry mode type
  c=$(resolve_commit --oid "$oid") || exit 1
  entry=$(git -C "$REPO" ls-tree --full-tree "$c" -- "$path" 2>/dev/null)
  mode=${entry%% *}; type=${entry#* }; type=${type%% *}
  [ -n "$entry" ] && [ "$type" = blob ] || fail "'$path' is not a file at $oid"
  [ "$mode" != 120000 ] || fail "'$path' is a symlink at $oid, not the visual itself"

  TMPD=$(mktemp -d "${TMPDIR:-/tmp}/demo-repo-artifact.XXXXXX") || fail "cannot make a temp dir"
  trap 'rm -rf "$TMPD"' EXIT
  # gh reads what follows a '#' in an attachment path as the image's alt text.
  local name file lead short
  name=$(printf '%s' "${path##*/}" | tr '#' '_')
  file="$TMPD/$name"
  git -C "$REPO" cat-file blob "$c:$path" >"$file" 2>/dev/null || fail "cannot read '$path' at $oid"
  lead=""; IFS= read -r -n 41 lead <"$file" || true
  case "$lead" in
    "version https://git-lfs.github.com/spec/"*)
      fail "'$path' is stored in Git LFS: the commit holds a pointer to it, not the file" ;;
  esac

  short=$(git -C "$REPO" rev-parse --short "$c")
  [ -n "$body" ] || body="The committed visual \`$path\` as of $short, attached so it renders inline."
  "$DELIVER" --file "$file" --subject "$subject" --body "$body"
  local rc=$?
  [ "$rc" -eq 0 ] && echo "$PROG: delivered $path as of $short to the PR of $subject"
  exit "$rc"
}

REPO="."
TMPD=""
case "${1:-}" in
  candidates) shift; cmd_candidates "$@" ;;
  deliver)    shift; cmd_deliver "$@" ;;
  -h|--help)  usage; exit 0 ;;
  '') usage_err "a subcommand is required: candidates or deliver" ;;
  *)  usage_err "unknown subcommand '$1'" ;;
esac
