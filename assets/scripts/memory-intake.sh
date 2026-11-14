#!/usr/bin/env bash
# memory-intake.sh — the mechanics of the learning loop's second intake: agent
# memory notes, which mol-feedback-distiller judges beside the observations by
# the learning-distill skill's memory section.
#
#   memory-intake.sh read
#   memory-intake.sh due [--limit N | --count]
#   memory-intake.sh apply <decisions-file | ->
#
# read   The distiller's read-memory step. Off the pack's home rig it changes
#        nothing. On it, it places the memory directory of each of the city's
#        rigs and of its root, files a finding through patrol-finding.sh for a
#        place it cannot resolve and clears one it resolves again, ends each
#        wait that is done, takes out the index and collection-note lines that
#        link a note no longer in the directory, rewrites each index's
#        guidance block, and prints how many notes are due.
# due    The due notes, oldest first, as a JSON array for the pending set
#        (memory_ref, memory_kind, memory_dir, memory_file, memory_due,
#        memory_prior, created_at, and memory_text for a collection entry).
#        --limit N prints the N oldest, and --count how many are due.
# apply  One decision a line, by the ref `due` gave: `<ref> waits <bead-id>`,
#        `<ref> next <YYYY-MM-DD> [ask-use]` or `<ref> drop`. A note changed
#        since it was listed is refused, and stays due.
#
# A unit is a whole note, or an entry of a collection note (hub-*.md): a
# top-level list item, with the indented lines under it, that is more than one
# line or does not begin with a link. A one-line item that begins with a link
# is a pointer to a note, as every line of the index, MEMORY.md, is.
#
# Each directory's state is under <city>/.gc/runtime/packs/gc-toolkit/
# memory-intake/<SHA-256 of its real path>/: `path`, `list.tsv` (each unit
# the judge kept, with its hash and the bead it waits on or the date it is
# next due), `removed/<name>@<hash>` (each removed unit's text) and `lock`. A
# unit is due when the list does not hold it at its hash, or its date has
# come, and is as old as its last change or that date. A note's list hash
# leaves out its use lines. A unit is removed only once its text is kept, and
# it is removed, or a note, an index or a collection note edited, only while it
# is unchanged since it was read.
#
# A note on a closed feedback pattern leaves once a fix the pattern spawned has
# landed on its repository's default branch and none is still on its way, and
# is due again from the day the pattern closed when none landed. When none
# landed and the operator vetoed a prompt-update the pattern spawned, by
# closing its PR unmerged, the same run marks the note so agents stop
# following its rule: the note gains the veto line under any front matter and
# each pointer to it in the index and the collection notes gains the veto
# mark, or an entry gains the veto line under its first line. A note that
# waits on another bead leaves once that bead's merge lands, and is due again
# when it closed with no merge. A merge into an integration effort's branch
# lands with the effort's landing bead. The default branch is the one the
# checkout's origin/HEAD names. Where it names none, no merge there counts as
# landed, so the wait stays.
#
# Placement follows Claude Code's storage-location rules, from this session's
# environment, home and user settings, the managed settings, the city's
# --settings file and each checkout's local and shared project settings
# (place below). memory-guidance.md beside this script holds every word the
# intake writes for agents.
#
# GC_PATROL_FINDING_TOOL, MEMORY_INTAKE_STATE, MEMORY_INTAKE_MANAGED_SETTINGS
# and MEMORY_INTAKE_NOW (epoch seconds) replace patrol-finding.sh, the state
# directory, the managed settings file and the clock.
#
# Exit: 0 done (apply: each decision recorded, removed or refused as changed)
#       1 could not do it all, as printed · 2 usage
set -uo pipefail

PROG=memory-intake
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GUIDANCE="$HERE/memory-guidance.md"
PATROL_FINDING="${GC_PATROL_FINDING_TOOL:-$HERE/patrol-finding.sh}"
MANAGED_SETTINGS="${MEMORY_INTAKE_MANAGED_SETTINGS:-}"
if [ -z "$MANAGED_SETTINGS" ]; then
  case "$(uname -s)" in
    Darwin) MANAGED_SETTINGS="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
    *)      MANAGED_SETTINGS="/etc/claude-code/managed-settings.json" ;;
  esac
fi
LIST_HEAD=$'#memory-intake list 1\tkind\tname\thash\tjudged\twait\tnext\twhy'
USE_MARK='<!-- memory-intake: use -->'
# The guidance file's veto line goes into a note whole; its veto mark line
# gives, after the key, the text a pointer gains.
VETO_MARK='<!-- memory-intake: veto -->'
VETO_POINTER_KEY='<!-- memory-intake: veto mark -->'
# A use line, as the awk programs below match it.
USE_AWK_RE='^(- )?used [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
LEVELS=(managed city local project user)
LOCK_WAIT=120
# Rows are read into bash split on the unit separator: a tab is whitespace to
# read, which would close up an empty field.
US=$'\037'

err() { printf '%s: %s\n' "$PROG" "$*" >&2; }
say() { printf '%s: %s\n' "$PROG" "$*"; }
usage() {
  cat >&2 <<'U'
usage: memory-intake.sh read
       memory-intake.sh due [--limit N | --count]
       memory-intake.sh apply <decisions-file | ->
U
}

for t in jq git awk find; do
  command -v "$t" >/dev/null 2>&1 || { err "$t is not on PATH"; exit 1; }
done
NOW="${MEMORY_INTAKE_NOW:-$(date -u +%s)}"
case "$NOW" in ''|*[!0-9]*) err "MEMORY_INTAKE_NOW is not a count of seconds"; exit 2 ;; esac
TODAY=$(jq -rn --argjson t "$NOW" '$t | strftime("%Y-%m-%d")') || { err "jq cannot read the clock"; exit 1; }
NOW_ISO=$(jq -rn --argjson t "$NOW" '$t | todate')
if command -v sha256sum >/dev/null 2>&1; then SHA=(sha256sum); else SHA=(shasum -a 256); fi
if stat -c %Y / >/dev/null 2>&1; then MTIME=(stat -c '%Y %n'); else MTIME=(stat -f '%m %N'); fi

sha_text() { printf '%s' "$1" | "${SHA[@]}" | cut -c1-64; }
sha_file() { "${SHA[@]}" < "$1" | cut -c1-64; }
one_line() { printf '%s' "$1" | tr '\t\n\r\037' '    ' | cut -c1-240; }
to_us() { tr '\t' '\037'; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-memory-intake.XXXXXX") || { err "cannot make a scratch directory"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# --- the city and its rigs --------------------------------------------------
RIGS_TSV=""; CITY=""; STATE_ROOT=""
declare -A STORE_OF=()
load_city() {
  local raw c name path kind prefix
  raw=$(gc rig list --json </dev/null 2>/dev/null) || { err "gc rig list did not answer, so no memory directory can be placed"; return 1; }
  RIGS_TSV=$(printf '%s' "$raw" | jq -r '.rigs[]? | select((.name // "") != "" and (.path // "") != "")
      | [.name, .path, (if .hq == true then "hq" else "rig" end), (.prefix // "-")] | @tsv' 2>/dev/null)
  [ -n "$RIGS_TSV" ] || { err "gc rig list named no rig, so no memory directory can be placed"; return 1; }
  for c in "${GC_CITY_PATH:-}" "${GC_CITY:-}" "${GC_CITY_ROOT:-}" \
      "$(printf '%s\n' "$RIGS_TSV" | awk -F'\t' '$3 == "hq" { print $2; exit }')"; do
    case "$c" in /*) if [ -d "$c" ]; then CITY=$c; break; fi ;; esac
  done
  [ -n "$CITY" ] || { err "the city root is unknown: GC_CITY_PATH is unset and gc rig list names no HQ"; return 1; }
  STATE_ROOT="${MEMORY_INTAKE_STATE:-$CITY/.gc/runtime/packs/gc-toolkit/memory-intake}"
  while IFS=$'\t' read -r name path kind prefix; do
    [ "$prefix" != - ] && STORE_OF[$prefix]=$path
  done <<< "$RIGS_TSV"
  return 0
}

# --- placement --------------------------------------------------------------
SETTINGS_JQ='def v(k): if type == "object" and has(k) then .[k] else null end;
  if type != "object" then error("settings are not an object") else
  [(v("autoMemoryDirectory") | tojson), (v("autoMemoryEnabled") | tojson),
   (v("permissions") | v("blockReadsOutsideWorkingDirectories") | tojson)] | @tsv end'
# settings_read <file> -> absent | unparsable | set<TAB><dir><TAB><enabled><TAB><block>,
# each value as JSON, null when the file does not set it.
settings_read() {
  local out
  [ -e "$1" ] || { echo absent; return 0; }
  out=$(jq -r "$SETTINGS_JQ" "$1" 2>/dev/null) || { echo unparsable; return 0; }
  case "$out" in
    '') echo absent ;;
    *$'\n'*) echo unparsable ;;
    *) printf 'set\t%s\n' "$out" ;;
  esac
}
key_safe() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-'; }
# A repository supplies its local settings when git tracks them or .claude is a link.
local_supplied() { [ -L "$1/.claude" ] || git -C "$1" ls-files --error-unmatch .claude/settings.local.json >/dev/null 2>&1; }

# place <name> <checkout> -> one line, tab-separated:
#   read <name> <real path> <how it is placed>
#   absent <name> <path or -> <why>
#   unresolved <name> <finding key> <why>
# Memory is off under CLAUDE_CODE_DISABLE_AUTO_MEMORY=1, or under
# autoMemoryEnabled false at the highest level that sets it unless that
# variable is 0. The directory is the highest level's autoMemoryDirectory, or
# else <config dir>/projects/<the checkout's path, each character not a letter
# or a digit as ->/memory. A place cannot be resolved when settings do not
# parse; when the deciding autoMemoryDirectory is relative, is set by the user
# or managed settings, or is set by the repository's settings while
# permissions.blockReadsOutsideWorkingDirectories is on; when
# CLAUDE_CODE_PROJECT_DIR_NAME names the project; or when the converted path
# passes 200 characters.
place() {
  local name=$1 co=$2 i st sd se sb d="" e="" b="" lvl="" val path conv real how rkey
  local -a files=("$MANAGED_SETTINGS" "$CITY/.gc/settings.json" "$co/.claude/settings.local.json" "$co/.claude/settings.json" "$CFG_DIR/settings.json")
  rkey="memory-intake.rig-$(key_safe "$name")"
  for i in 0 1 2 3 4; do
    case $i in 0) st=$S_MANAGED ;; 1) st=$S_SETTINGS ;; 4) st=$S_USER ;; *) st=$(settings_read "${files[$i]}") ;; esac
    case "$st" in
      absent) continue ;;
      unparsable)
        case $i in
          2|3) printf 'unresolved\t%s\t%s\t%s does not parse\n' "$name" "$rkey" "${files[$i]}" ;;
          *)   printf 'unresolved\t%s\tmemory-intake.settings-%s\t%s does not parse\n' "$name" "${LEVELS[$i]}" "${files[$i]}" ;;
        esac
        return 0 ;;
    esac
    IFS=$'\t' read -r _ sd se sb <<< "$st"
    if [ -z "$d" ] && [ "$sd" != null ]; then d=$sd; lvl=$i; fi
    if [ -z "$e" ] && [ "$se" != null ]; then e=$se; fi
    if [ -z "$b" ] && [ "$sb" != null ]; then b=$sb; fi
  done
  case "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-}" in
    1) printf 'absent\t%s\t-\tmemory is off: CLAUDE_CODE_DISABLE_AUTO_MEMORY=1\n' "$name"; return 0 ;;
    0) ;;
    *) if [ "$e" = false ]; then printf 'absent\t%s\t-\tmemory is off: autoMemoryEnabled is false\n' "$name"; return 0; fi ;;
  esac
  if [ -n "$d" ]; then
    case $lvl in
      0|4) printf 'unresolved\t%s\tmemory-intake.%s-level\tautoMemoryDirectory in the %s settings places one directory for every project their sessions start in, sessions the city does not run included\n' \
             "$name" "${LEVELS[$lvl]}" "${LEVELS[$lvl]}"; return 0 ;;
    esac
    val=$(printf '%s' "$d" | jq -r 'if type == "string" then . else "" end' 2>/dev/null)
    case "$val" in
      /*) path=$val ;;
      \~/*) path="$HOME/${val#\~/}" ;;
      *) [ "$lvl" = 1 ] && rkey=memory-intake.settings-directory
         printf 'unresolved\t%s\t%s\tautoMemoryDirectory %s in the %s settings is neither an absolute path nor one that starts with ~/\n' "$name" "$rkey" "$d" "${LEVELS[$lvl]}"
         return 0 ;;
    esac
    if [ "$b" = true ] && { [ "$lvl" = 3 ] || { [ "$lvl" = 2 ] && local_supplied "$co"; }; }; then
      printf 'unresolved\t%s\t%s\tthe %s settings the repository supplies place the directory while permissions.blockReadsOutsideWorkingDirectories is on, so Claude Code neither loads nor writes memory there\n' "$name" "$rkey" "${LEVELS[$lvl]}"
      return 0
    fi
    how="autoMemoryDirectory in the ${LEVELS[$lvl]} settings"
  else
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [[ "${CLAUDE_CODE_PROJECT_DIR_NAME:-}" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
      printf 'unresolved\t%s\tmemory-intake.project-dir-name\tCLAUDE_CODE_PROJECT_DIR_NAME names one directory for every project its sessions start in\n' "$name"
      return 0
    fi
    conv=$(printf '%s' "$co" | LC_ALL=C tr -c 'A-Za-z0-9' '-')
    if [ "${#conv}" -gt 200 ]; then
      printf 'unresolved\t%s\t%s\tthe checkout path converts to %d characters, past the 200 where Claude Code adds a hash its pages do not define\n' "$name" "$rkey" "${#conv}"
      return 0
    fi
    path="$CFG_DIR/projects/$conv/memory"
    how="named for the checkout"
  fi
  if [ ! -d "$path" ]; then printf 'absent\t%s\t%s\tno directory there\n' "$name" "$path"; return 0; fi
  if ! real=$(CDPATH='' cd -P -- "$path" 2>/dev/null && pwd -P); then
    printf 'unresolved\t%s\t%s\tthe directory %s cannot be entered\n' "$name" "$rkey" "$path"; return 0
  fi
  printf 'read\t%s\t%s\t%s\n' "$name" "$real" "$how"
}

PLACES=""; DIRS=()
declare -A DIR_KEY=() DIR_NAMES=()
place_all() {
  local name path kind prefix real
  CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  S_MANAGED=$(settings_read "$MANAGED_SETTINGS")
  S_SETTINGS=$(settings_read "$CITY/.gc/settings.json")
  S_USER=$(settings_read "$CFG_DIR/settings.json")
  PLACES=$(while IFS=$'\t' read -r name path kind prefix; do place "$name" "$path"; done <<< "$RIGS_TSV")
  DIRS=()
  while IFS=$'\t' read -r kind name real _; do
    [ "$kind" = read ] || continue
    if [ -z "${DIR_KEY[$real]+x}" ]; then
      DIRS+=("$real"); DIR_KEY[$real]=$(sha_text "$real"); DIR_NAMES[$real]=$name
    else
      DIR_NAMES[$real]="${DIR_NAMES[$real]}, $name"
    fi
  done <<< "$PLACES"
}
state_of() { printf '%s/%s' "$STATE_ROOT" "${DIR_KEY[$1]}"; }

# --- locks and writes -------------------------------------------------------
# The lock is held on fd 8, for one directory at a time. Nothing that can
# leave a process behind, such as gc, runs while it is held.
lock_dir() {
  mkdir -p "$1" 2>/dev/null || { err "cannot make $1"; return 1; }
  command -v flock >/dev/null 2>&1 || { err "flock is not on PATH, so nothing is written"; return 1; }
  exec 8>>"$1/lock" || { err "cannot open $1/lock"; return 1; }
  flock -w "$LOCK_WAIT" 8 || { exec 8>&-; err "another run held $1/lock for ${LOCK_WAIT}s"; return 1; }
  [ -f "$1/path" ] || printf '%s\n' "$2" > "$1/path"
}
unlock_dir() { exec 8>&-; }

# rewrite <file> <fn> [args] — <fn> reads the file's text on stdin and writes
# its new text. The new text is written only while the file still holds the
# text <fn> read, and is made again, up to three times, when another writer
# moved it. 0 written or nothing to change (REWROTE says which, and
# REWROTE_HASH is the hash of the text written), 3 the file kept moving, 1
# failure.
REWROTE=0; REWROTE_HASH=""
rewrite() {
  local file=$1 fn=$2 before after tmp; shift 2
  REWROTE=0; REWROTE_HASH=""
  for _ in 1 2 3; do
    before=$(sha_file "$file") || return 1
    tmp=$(mktemp "${file%/*}/.memory-intake.XXXXXX") || return 1
    cp -p "$file" "$tmp" 2>/dev/null
    if ! "$fn" "$@" < "$file" > "$tmp"; then rm -f "$tmp"; return 1; fi
    after=$(sha_file "$tmp")
    if [ "$after" = "$before" ]; then rm -f "$tmp"; return 0; fi
    if [ "$(sha_file "$file")" = "$before" ]; then
      mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
      REWROTE=1; REWROTE_HASH=$after; return 0
    fi
    rm -f "$tmp"
  done
  return 3
}

# keep_text <state dir> <name> <hash> <file> — files the text of a unit that is
# leaving at removed/<name>@<hash>. It is copied under another name and moved
# there only once the copy holds text of <hash>, so a file that no longer
# holds that text is refused. KEPT_NEW is the file it made, empty when that
# text was kept already, and unkeep takes it back when the unit stays.
KEPT_NEW=""
keep_text() {
  local dest="$1/removed/$2@$3" tmp
  KEPT_NEW=""
  mkdir -p "$1/removed" 2>/dev/null || return 1
  if [ -f "$dest" ] && [ "$(sha_file "$dest" 2>/dev/null)" = "$3" ]; then return 0; fi
  tmp=$(mktemp "$1/removed/.keep.XXXXXX" 2>/dev/null) || return 1
  if cp "$4" "$tmp" 2>/dev/null && [ "$(sha_file "$tmp")" = "$3" ] && mv -f "$tmp" "$dest" 2>/dev/null; then
    KEPT_NEW=$dest; return 0
  fi
  rm -f "$tmp"; return 1
}
unkeep() { [ -z "$KEPT_NEW" ] || rm -f "$KEPT_NEW"; KEPT_NEW=""; }

# remove_file <state dir> <dir> <name> <hash> — removes a note, or a
# collection note left with no entries, while it holds text of <hash>, once
# that text is kept. Agents write memory without the lock, so the file is read
# again right before it goes. 0 removed; 2 it holds other text or is gone, and
# stays; 1 its text was not kept or it could not be removed, and it stays.
remove_file() {
  local f="$2/$3"
  if ! keep_text "$1" "$3" "$4" "$f"; then
    [ "$(sha_file "$f" 2>/dev/null)" = "$4" ] && return 1
    return 2
  fi
  if [ "$(sha_file "$f" 2>/dev/null)" = "$4" ] && rm -f "$f"; then return 0; fi
  unkeep
  [ "$(sha_file "$f" 2>/dev/null)" = "$4" ] && return 1
  return 2
}

# remove_entry <state dir> <dir> <name> <hash> <entry file> — takes an entry
# out of its collection note once its text is kept, and the collection note
# with it when that leaves it with no entries (HUB_GONE). 0 removed; 2 the note
# no longer holds the entry or kept changing, and it stays; 1 its text was not
# kept or the note could not be written, and it stays; 3 removed, but the
# collection note it leaves with no entries stays, its text not kept.
HUB_GONE=0
remove_entry() {
  local sd=$1 dir=$2 name=$3 rc
  HUB_GONE=0
  keep_text "$sd" "$name" "$4" "$5" || return 1
  rewrite "$dir/$name" drop_entry "$5"; rc=$?
  if [ "$rc" != 0 ] || [ "$REWROTE" != 1 ]; then
    unkeep
    [ "$rc" = 1 ] && [ -e "$dir/$name" ] && return 1
    return 2
  fi
  grep -q '^- ' "$dir/$name" && return 0
  remove_file "$sd" "$dir" "$name" "$REWROTE_HASH"; rc=$?
  case $rc in
    0) HUB_GONE=1 ;;
    1) err "$dir/$name has no entries left and stays: its text was not kept, or it could not be removed"; return 3 ;;
  esac
  return 0
}

# --- reading a directory ------------------------------------------------------
# The entry boundary that every program reading a collection note shares, over
# a file's lines in L[1..n]. One top-level list item and the indented lines
# under it make an entry, and blank lines belong to it only when an indented
# line follows them. An entry of one line that begins with a link is a pointer.
BOUNDARY_AWK='
function link_start(s) { return s ~ /^\[\[[^]]+\]\]/ || s ~ /^\[[^]]*\]\([^)]+\)/ }
function entry_end(n, i,   k, e) {
  e = i
  for (k = i + 1; k <= n; k++) {
    if (L[k] ~ /^[ \t]*$/) continue
    if (L[k] !~ /^[ \t]/) break
    e = k
  }
  return e
}
function pointer(n, i) { return entry_end(n, i) == i && link_start(substr(L[i], 3)) }
'
ENTRY_AWK="$BOUNDARY_AWK"'
function emit(   i, e, f, x) {
  for (i = 1; i <= nl; i++) {
    if (substr(L[i], 1, 2) != "- ") continue
    e = entry_end(nl, i)
    if (!pointer(nl, i)) {
      k++; f = W "/e/" k
      for (x = i; x <= e; x++) print L[x] > f
      close(f)
      printf "%s\t%d\t%d\t%d\n", hub, k, i, e
    }
    i = e
  }
  nl = 0
}
FNR == 1 { emit(); hub = FILENAME; sub(/.*\//, "", hub) }
{ L[++nl] = $0 }
END { emit() }'

# incomplete <dir> — says that a scan of <dir> could not read a file it listed.
incomplete() { err "cannot read every note in $1; nothing there is removed, and its list stays as it is"; }
# scan <dir> <work> — the directory as <work>/files.tsv (name, hash, mtime of
# each note and collection note) and <work>/units.tsv (kind, name, hash for
# the list, full hash, mtime, entry text file). 1 when it cannot list the
# directory or read each file the listing names, as it says: a scan that is not
# whole would read as notes gone, so every caller leaves the list as it is.
scan() {
  local dir=$1 w=$2 f n i
  local -a all=() notes=() hubs=()
  rm -rf "$w"; mkdir -p "$w/e" "$w/s" || { err "cannot make $w, so $dir is not read"; return 1; }
  : > "$w/files.tsv"; : > "$w/units.tsv"
  if ! find "$dir" -maxdepth 1 -type f -name '*.md' -print0 > "$w/found" 2>/dev/null \
     || ! LC_ALL=C sort -z "$w/found" > "$w/listed"; then
    err "cannot list $dir; nothing there is removed, and its list stays as it is"
    return 1
  fi
  while IFS= read -r -d '' f; do
    n=${f##*/}
    case "$n" in
      MEMORY.md) continue ;;
      *$'\t'*|*$'\n'*|*\\*) err "leaving $f alone: its name holds a tab, a newline or a backslash"; continue ;;
    esac
    all+=("$f")
    case "$n" in hub-*.md) hubs+=("$f") ;; *) notes+=("$f") ;; esac
  done < "$w/listed"
  [ "${#all[@]}" -gt 0 ] || return 0
  "${SHA[@]}" "${all[@]}" > "$w/sha.out" 2>/dev/null
  "${MTIME[@]}" "${all[@]}" > "$w/mt.out" 2>/dev/null
  awk 'FNR == NR { h[substr($0, 67)] = substr($0, 1, 64); next }
       { i = index($0, " "); p = substr($0, i + 1); if (p in h) { n = p; sub(/.*\//, "", n); print n "\t" h[p] "\t" substr($0, 1, i - 1) } }' \
    "$w/sha.out" "$w/mt.out" > "$w/files.tsv"
  # A file joins files.tsv only with both its hash and its mtime, so a row
  # short of the listing is a file that could not be read.
  [ "$(grep -c . "$w/files.tsv")" = "${#all[@]}" ] || { incomplete "$dir"; return 1; }
  if [ "${#notes[@]}" -gt 0 ]; then
    # A note's list hash leaves out its use lines.
    for i in "${!notes[@]}"; do : > "$w/s/$i"; done
    if ! LC_ALL=C awk -v W="$w/s/" -v RE="$USE_AWK_RE" '
      BEGIN { for (j = 1; j < ARGC; j++) idx[ARGV[j]] = j - 1 }
      FNR == 1 { if (out != "") close(out); out = W idx[FILENAME] }
      $0 !~ RE { print > out }' "${notes[@]}"; then
      incomplete "$dir"; return 1
    fi
    "${SHA[@]}" "$w"/s/* > "$w/base.out" 2>/dev/null
    printf '%s\n' "${notes[@]}" > "$w/notes.lst"
    awk -F'\t' -v W="$w/s/" '
      FILENAME == ARGV[1] { b[substr($0, 67 + length(W))] = substr($0, 1, 64); next }
      FILENAME == ARGV[2] { n = $0; sub(/.*\//, "", n); base[n] = b[FNR - 1]; next }
      ($1 in base) { print "note\t" $1 "\t" base[$1] "\t" $2 "\t" $3 "\t" }' \
      "$w/base.out" "$w/notes.lst" "$w/files.tsv" >> "$w/units.tsv"
  fi
  if [ "${#hubs[@]}" -gt 0 ]; then
    LC_ALL=C awk -v W="$w" "$ENTRY_AWK" "${hubs[@]}" > "$w/entries.raw" || { incomplete "$dir"; return 1; }
    if [ -s "$w/entries.raw" ]; then
      "${SHA[@]}" "$w"/e/* > "$w/entry.out" 2>/dev/null
      awk -F'\t' -v W="$w/e/" '
        FILENAME == ARGV[1] { h[substr($0, 67 + length(W))] = substr($0, 1, 64); next }
        FILENAME == ARGV[2] { mt[$1] = $3; next }
        { print "entry\t" $1 "\t" h[$2] "\t" h[$2] "\t" mt[$1] "\t" W $2 }' \
        "$w/entry.out" "$w/files.tsv" "$w/entries.raw" >> "$w/units.tsv"
    fi
  fi
}

list_rows() { if [ -f "$1/list.tsv" ]; then grep -v '^#' "$1/list.tsv"; fi; return 0; }
# write_list <state dir> <rows file>
write_list() {
  local tmp
  tmp=$(mktemp "$1/.list.XXXXXX") || return 1
  if { printf '%s\n' "$LIST_HEAD"; LC_ALL=C sort -t "$(printf '\t')" -k2,2 -k1,1 -k3,3 "$2"; } > "$tmp" && mv -f "$tmp" "$1/list.tsv"; then
    return 0
  fi
  rm -f "$tmp"; return 1
}
# drop_row <rows file> <kind> <name> <hash> — a note's row goes by its name,
# an entry's by its hash.
drop_row() {
  awk -F'\t' -v k="$2" -v n="$3" -v h="$4" '!($1 == k && $2 == n && (k == "note" || $3 == h))' "$1" > "$1.next" && mv -f "$1.next" "$1"
}

# due_rows <dir> <work> — one line per due unit of a scanned directory:
# age kind (t or d), age, dir, key, kind, name, full hash, why due, prior, text file
due_rows() {
  local dir=$1 w=$2
  list_rows "$(state_of "$dir")" > "$w/list.rows"
  awk -F'\t' -v OFS='\t' -v TODAY="$TODAY" -v DIR="$dir" -v KEY="${DIR_KEY[$dir]}" '
    FILENAME == ARGV[1] {
      k = $1 SUBSEP $2 SUBSEP ($1 == "note" ? "" : $3)
      H[k] = $3; WT[k] = $5; NX[k] = $6; WHY[k] = $7; next }
    {
      k = $1 SUBSEP $2 SUBSEP ($1 == "note" ? "" : $3)
      prior = ""
      if (k in H) {
        if (WHY[k] != "") prior = WHY[k]
        else if (WT[k] != "") prior = "waited on " WT[k]
        else if (NX[k] != "") prior = "kept until " NX[k]
      }
      if (!(k in H)) print "t", $5, DIR, KEY, $1, $2, $4, "new", prior, $6
      else if (H[k] != $3) print "t", $5, DIR, KEY, $1, $2, $4, "changed", prior, $6
      else if (NX[k] != "" && NX[k] <= TODAY) print "d", NX[k], DIR, KEY, $1, $2, $4, "date", prior, $6
    }' "$w/list.rows" "$w/units.tsv"
}

# --- links in the index and collection notes ----------------------------------
# A pointer is a list item of one line whose text begins with a link to a note
# in this directory, and an item with lines under it is kept whole. A pointer
# line can hold several, joined by " · ". Each pointer to a note no longer in
# the directory is taken out with the text that follows it, and a line left
# with none goes. A listing that does not name the file being edited was not
# read, and nothing is taken out on it.
TARGET_AWK='
function target(s,   t) {
  if (s ~ /^\[\[/) { t = substr(s, 3); t = substr(t, 1, index(t, "]]") - 1); sub(/\|.*/, "", t); sub(/#.*/, "", t); if (t !~ /\.md$/) t = t ".md"; return t }
  t = s; sub(/^\[[^]]*\]\(/, "", t); t = substr(t, 1, index(t, ")") - 1)
  sub(/^</, "", t); sub(/>$/, "", t); sub(/#.*/, "", t); sub(/[ \t].*/, "", t)
  return t
}
'
PRUNE_AWK="$BOUNDARY_AWK$TARGET_AWK"'
function gone(s,   t) { t = target(s); if (t == "" || t ~ /[\/:]/ || t !~ /\.md$/) return 0; return !(t in present) }
BEGIN { while ((getline x < NAMES) > 0) present[x] = 1; if (!(SELF in present)) { unread = 1; exit 2 } }
{ L[NR] = $0 }
END {
  if (unread) exit 2
  for (i = 1; i <= NR; i++) {
    if (substr(L[i], 1, 2) != "- ") { print L[i]; continue }
    if (!pointer(NR, i)) { e = entry_end(NR, i); for (x = i; x <= e; x++) print L[x]; i = e; continue }
    n = split(substr(L[i], 3), seg, / · /); out = ""; kept = 0; keep = 1
    for (j = 1; j <= n; j++) {
      if (link_start(seg[j])) keep = !gone(seg[j])
      if (keep) out = (kept++ ? out " · " : "") seg[j]
    }
    if (kept) print "- " out
  }
}'
prune_links() { LC_ALL=C awk -v NAMES="$1" -v SELF="$2" "$PRUNE_AWK"; }

# Each pointer to the note NOTE gains, after its text and only once, the veto
# mark the file MARK holds.
MARK_AWK="$BOUNDARY_AWK$TARGET_AWK"'
BEGIN { if ((getline mark < MARK) <= 0 || mark == "") { unread = 1; exit 2 } }
{ L[NR] = $0 }
END {
  if (unread) exit 2
  for (i = 1; i <= NR; i++) {
    if (substr(L[i], 1, 2) != "- ") { print L[i]; continue }
    if (!pointer(NR, i)) { e = entry_end(NR, i); for (x = i; x <= e; x++) print L[x]; i = e; continue }
    n = split(substr(L[i], 3), seg, / · /); out = ""
    for (j = 1; j <= n; j++) {
      if (link_start(seg[j]) && target(seg[j]) == NOTE && !index(seg[j], mark)) seg[j] = seg[j] " " mark
      out = (j > 1 ? out " · " : "") seg[j]
    }
    print "- " out
  }
}'
mark_pointers() { LC_ALL=C awk -v NOTE="$1" -v MARK="$2" "$MARK_AWK"; }

# ENTRY names a file that holds one entry's lines. The first entry of the
# collection note that holds the same lines is taken out, or, when ADD names a
# file, gains the line that file holds under its own first line.
ENTRY_EDIT_AWK="$BOUNDARY_AWK"'
BEGIN { while ((getline x < ENTRY) > 0) E[++m] = x; if (ADD != "" && (getline add < ADD) <= 0) { unread = 1; exit 2 } }
{ L[NR] = $0 }
END {
  if (unread) exit 2
  done = 0
  for (i = 1; i <= NR; i++) {
    if (done || substr(L[i], 1, 2) != "- ") { print L[i]; continue }
    e = entry_end(NR, i)
    same = (e - i + 1 == m)
    for (x = 0; same && x < m; x++) if (L[i + x] != E[x + 1]) same = 0
    if (same) done = 1
    if (!same || ADD != "") for (x = i; x <= e; x++) { print L[x]; if (same && x == i) print add }
    i = e
  }
}'
drop_entry() { LC_ALL=C awk -v ENTRY="$1" -v ADD= "$ENTRY_EDIT_AWK"; }
add_to_entry() { LC_ALL=C awk -v ENTRY="$1" -v ADD="$2" "$ENTRY_EDIT_AWK"; }

# tidy <dir> <state dir> — takes the pointers to notes no longer in the
# directory out of the index and every collection note, and removes, with its
# text kept, a collection note this leaves with no entries. LINKS counts the
# files it edited. 1 when a collection note left with no entries stays because
# its text was not kept.
LINKS=0
tidy() {
  local dir=$1 sd=$2 f name had gone_hub rc fail=0
  for _ in 1 2 3; do
    gone_hub=0
    find "$dir" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null | sed 's|.*/||' > "$WORK/present"
    for f in "$dir/MEMORY.md" "$dir"/hub-*.md; do
      [ -f "$f" ] || continue
      name=${f##*/}
      had=$(grep -c '^- ' "$f" 2>/dev/null)
      rewrite "$f" prune_links "$WORK/present" "$name"; rc=$?
      case $rc in
        0) ;;
        3) err "$f kept changing while its links were tidied; the next run tries again"; continue ;;
        *) err "the links in $f were not tidied; the next run tries again"; continue ;;
      esac
      [ "$REWROTE" = 1 ] || continue
      LINKS=$((LINKS + 1))
      if [ "$name" != MEMORY.md ] && [ "${had:-0}" -gt 0 ] && ! grep -q '^- ' "$f"; then
        remove_file "$sd" "$dir" "$name" "$REWROTE_HASH"; rc=$?
        case $rc in
          0) gone_hub=1 ;;
          1) err "$f has no entries left and stays: its text was not kept, or it could not be removed"; fail=1 ;;
        esac
      fi
    done
    [ "$gone_hub" = 1 ] || break
  done
  return "$fail"
}

# --- a vetoed rule --------------------------------------------------------------
# The veto line the file LINE holds goes into a note under its front matter, or
# first when it has none.
VETO_NOTE_AWK='
BEGIN { if ((getline v < LINE) <= 0) { unread = 1; exit 2 } }
{ L[NR] = $0 }
END {
  if (unread) exit 2
  f = 0
  if (NR > 0 && L[1] == "---") { for (j = 2; j <= NR && L[j] != "---"; j++) ; if (j <= NR) f = j }
  for (i = 1; i <= f; i++) print L[i]
  print v
  for (i = f + 1; i <= NR; i++) print L[i]
}'
veto_note() { LC_ALL=C awk -v LINE="$1" "$VETO_NOTE_AWK"; }

# veto_unit <dir> <kind> <name> <entry file> <PR> — marks a unit whose rule the
# operator vetoed in <PR>, so agents stop following it. A note gains the veto
# line, naming <PR>, and each pointer to it in the index and the collection
# notes gains the veto mark. An entry, found by the text the judge read, gains
# the veto line under its first line. A unit that holds a veto line already
# gains none. VETO_HASH is the unit's list hash once it is marked. 0 marked; 2
# the note is gone, or its collection note no longer holds the entry; 1 a file
# could not be written or kept changing.
VETO_HASH=""
veto_unit() {
  local dir=$1 kind=$2 name=$3 ef=$4 line f
  VETO_HASH=""
  line=${VETO_LINE//"<PR>"/"$5"}
  [ -f "$dir/$name" ] || return 2
  if [ "$kind" = entry ]; then
    if grep -qF "$VETO_MARK" "$ef"; then VETO_HASH=$(sha_file "$ef"); return 0; fi
    printf '  %s\n' "$line" > "$WORK/veto" || return 1
    rewrite "$dir/$name" add_to_entry "$ef" "$WORK/veto" || return 1
    [ "$REWROTE" = 1 ] || return 2
    VETO_HASH=$(add_to_entry "$ef" "$WORK/veto" < "$ef" | "${SHA[@]}" | cut -c1-64)
    return 0
  fi
  printf '%s\n' "$VETO_POINTER" > "$WORK/veto.mark" || return 1
  for f in "$dir/MEMORY.md" "$dir"/hub-*.md; do
    [ -f "$f" ] || continue
    rewrite "$f" mark_pointers "$name" "$WORK/veto.mark" || return 1
  done
  if ! grep -qF "$VETO_MARK" "$dir/$name"; then
    printf '%s\n' "$line" > "$WORK/veto" || return 1
    rewrite "$dir/$name" veto_note "$WORK/veto" || return 1
  fi
  VETO_HASH=$(LC_ALL=C awk -v RE="$USE_AWK_RE" '$0 !~ RE' "$dir/$name" | "${SHA[@]}" | cut -c1-64)
  return 0
}

# --- the guidance block -------------------------------------------------------
# The block goes at the top of the index, after any front matter, in place of
# the block an earlier run wrote, with one blank line before the rest. A block
# that was not read whole is not written.
GUIDE_AWK='
BEGIN { while ((getline x < BLOCK) > 0) { blk = blk x "\n"; last = x }; if (last != "<!-- /memory-intake -->") { unread = 1; exit 2 } }
{ L[NR] = $0 }
END {
  if (unread) exit 2
  i = 1; head = ""
  if (NR > 0 && L[1] == "---") {
    for (j = 2; j <= NR && L[j] != "---"; j++) ;
    if (j <= NR) { for (k = 1; k <= j; k++) head = head L[k] "\n"; i = j + 1 }
  }
  s = 0; e = 0
  for (j = i; j <= NR; j++) {
    if (!s && L[j] ~ /^<!-- memory-intake:/ && L[j] !~ /^<!-- memory-intake: use/) s = j
    else if (s && L[j] == "<!-- /memory-intake -->") { e = j; break }
  }
  if (!e) s = 0
  printf "%s%s", head, blk
  rest = 0
  for (j = i; j <= NR; j++) {
    if (s && j >= s && j <= e) continue
    if (s && j == e + 1 && L[j] == "") continue
    if (!rest && L[j] != "") printf "\n"
    rest = 1; print L[j]
  }
}'
guide_edit() { LC_ALL=C awk -v BLOCK="$WORK/block" "$GUIDE_AWK"; }
USE_LINE=""; VETO_LINE=""; VETO_POINTER=""
load_guidance() {
  [ -r "$GUIDANCE" ] || { err "$GUIDANCE is missing"; return 1; }
  awk '{ print } $0 == "<!-- /memory-intake -->" { exit }' "$GUIDANCE" > "$WORK/block"
  grep -qx '<!-- /memory-intake -->' "$WORK/block" || { err "$GUIDANCE has no end to its block"; return 1; }
  USE_LINE=$(grep -F -m1 "$USE_MARK" "$GUIDANCE") || { err "$GUIDANCE has no use line"; return 1; }
  VETO_LINE=$(grep -F -m1 "$VETO_MARK" "$GUIDANCE") || { err "$GUIDANCE has no veto line"; return 1; }
  VETO_POINTER=$(grep -F -m1 "$VETO_POINTER_KEY" "$GUIDANCE") || { err "$GUIDANCE has no veto mark"; return 1; }
  VETO_POINTER=${VETO_POINTER#*"$VETO_POINTER_KEY"}; VETO_POINTER=${VETO_POINTER# }
  [ -n "$VETO_POINTER" ] || { err "$GUIDANCE has no veto mark"; return 1; }
}
# guide <dir> — writes the guidance block into the index, making the index
# when there is none. GUIDED says whether it wrote.
GUIDED=0
guide() {
  local idx="$1/MEMORY.md" tmp
  GUIDED=0
  if [ ! -e "$idx" ]; then
    tmp=$(mktemp "$1/.memory-intake.XXXXXX") || return 1
    cp "$WORK/block" "$tmp" && chmod 644 "$tmp" && mv -n "$tmp" "$idx"
    rm -f "$tmp"
    [ -e "$idx" ] || return 1
    GUIDED=1
  fi
  rewrite "$idx" guide_edit || return 1
  [ "$REWROTE" = 1 ] && GUIDED=1
  return 0
}

# --- beads: when a wait is done -----------------------------------------------
declare -A BEAD=() PR_STATE=()
# fetch <store> <id>... — reads the beads not read yet into BEAD, as one JSON
# row each, or - when the store answered and holds no such bead. 1 when the
# store did not answer.
fetch() {
  local store=$1 out id json; shift
  local -a want=()
  for id in "$@"; do [ -n "${BEAD[$store|$id]+x}" ] || want+=("$id"); done
  [ "${#want[@]}" -gt 0 ] || return 0
  out=$(cd / && gc bd -C "$store" show "${want[@]}" --json </dev/null 2>/dev/null | scrub)
  if printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1; then
    while IFS="$US" read -r id json; do
      [ -n "$id" ] && BEAD[$store|$id]=$json
    done < <(printf '%s' "$out" | jq -r '.[] | .id + "\u001f" + tojson')
  elif ! printf '%s' "$out" | jq -e 'type == "object" and ((.error // "") | test("no issues found"))' >/dev/null 2>&1; then
    return 1
  fi
  for id in "${want[@]}"; do [ -n "${BEAD[$store|$id]+x}" ] || BEAD[$store|$id]=-; done
  return 0
}
field() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
pr_state() {
  [ -n "$1" ] && command -v gh >/dev/null 2>&1 \
    && gh pr view "$1" --json state,baseRefName -q '.state + " " + .baseRefName' </dev/null 2>/dev/null \
    || echo unknown
}
# default_branch <store> — sets DEFAULT to the branch the origin/HEAD of the
# repository at <store> names. 1 when it names none, said once a run: no
# branch is taken for the default in its place.
declare -A DEFAULT_OF=()
DEFAULT=""
default_branch() {
  local ref
  if [ -z "${DEFAULT_OF[$1]+x}" ]; then
    ref=$(git -C "$1" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || ref=""
    case "$ref" in
      refs/remotes/origin/?*) DEFAULT_OF[$1]=${ref#refs/remotes/origin/} ;;
      *) DEFAULT_OF[$1]=""
         err "the origin/HEAD of $1 names no branch, so no merge there is taken as landed and each wait on one stays; set it with git -C '$1' remote set-head origin --auto" ;;
    esac
  fi
  DEFAULT=${DEFAULT_OF[$1]}
  [ -n "$DEFAULT" ]
}
# landed <store> <bead row> [depth] — sets LANDED: landed (its merge is on the
# default branch its repository's origin/HEAD names), vetoed (a prompt-update
# whose PR closed unmerged, which the distiller reads as the operator's veto;
# VETOED_PR names the PR), none (it closed with no merge on the way there), or
# pending.
LANDED=pending; VETOED_PR=""
landed() {
  local store=$1 j=$2 depth=${3:-0} mr tgt url st lid
  LANDED=pending; VETOED_PR=""
  [ "$(field "$j" '.status // ""')" = closed ] || return 0
  mr=$(field "$j" '.metadata.merge_result // ""')
  case "$mr" in
    # A landing records merged, or mr_merged on Gas Town's pending record,
    # each beside the branch it landed on.
    merged|mr_merged) tgt=$(field "$j" '.metadata.merged_target // .metadata.target // ""') ;;
    pull_request)
      url=$(field "$j" '.metadata.pr_url // ""')
      if [ -z "$url" ]; then
        err "$(field "$j" '.id // ""') has merge_result pull_request and no pr_url, so the wait it decides stays"
        return 0
      fi
      [ -n "${PR_STATE[$url]+x}" ] || PR_STATE[$url]=$(pr_state "$url")
      st=${PR_STATE[$url]}
      case "$st" in
        "MERGED "*) tgt=${st#MERGED } ;;
        CLOSED*)
          LANDED=none
          if [ "$(field "$j" '.metadata.task_kind // ""')" = prompt-update ]; then LANDED=vetoed; VETOED_PR=$(one_line "$url"); fi
          return 0 ;;
        *) return 0 ;;
      esac ;;
    *) LANDED=none; return 0 ;;
  esac
  default_branch "$store" || return 0
  if [ "$tgt" = "$DEFAULT" ]; then LANDED=landed; return 0; fi
  case "$tgt" in
    integration/?*)
      lid=${tgt#integration/}
      if [ "$depth" -lt 3 ] && fetch "$store" "$lid" && [ "${BEAD[$store|$lid]}" != - ]; then
        landed "$store" "${BEAD[$store|$lid]}" $((depth + 1))
      fi ;;
  esac
  return 0
}
# decide <id> — sets DECISION: wait, left (a fix landed),
# vetoed<US><date><US><why><US><PR> (a pattern done with no fix landed, after
# the operator vetoed a prompt-update it spawned in <PR>), or
# ended<US><date><US><why> (done with no fix landed).
DECISION="wait"
decide() {
  local id=$1 store j f any=0 veto="" day why reason deps
  local -a ups=()
  DECISION="wait"
  store=${STORE_OF[${id%%-*}]:-}
  [ -n "$store" ] || { err "no store of the city carries $id, so what waits on it stays"; return 0; }
  fetch "$store" "$id" || { err "the store at $store did not answer for $id"; return 0; }
  j=${BEAD[$store|$id]}
  if [ "$j" = - ]; then DECISION="ended$US$TODAY${US}waited on $id, which is not in its store"; return 0; fi
  [ "$(field "$j" '.status // ""')" = closed ] || return 0
  day=$(field "$j" '(.closed_at // "")[0:10]')
  [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && ! "$day" > "$TODAY" ]] || day=$TODAY
  reason=$(one_line "$(field "$j" '.close_reason // ""')")
  if [ "$(field "$j" '.metadata.task_kind // ""')" = feedback-pattern ]; then
    # A follow-up may be named only by the pattern's blocks edge, so an edge
    # list that was not read leaves the wait as it is.
    deps=$(cd / && gc bd -C "$store" dep list "$id" --json </dev/null 2>/dev/null | scrub)
    if ! printf '%s' "$deps" | jq -e 'type == "array"' >/dev/null 2>&1; then
      err "the store at $store did not answer for the follow-ups of $id"; return 0
    fi
    mapfile -t ups < <( { field "$j" '.metadata.proposal_bead // empty, .metadata.eng_bead // empty'
        printf '%s' "$deps" | jq -r '.[] | select((.dependency_type // .type // "") == "blocks") | .id // empty'; } | sort -u)
    if [ "${#ups[@]}" -gt 0 ] && ! fetch "$store" "${ups[@]}"; then
      err "the store at $store did not answer for the follow-ups of $id"; return 0
    fi
    for f in "${ups[@]}"; do
      [ "${BEAD[$store|$f]}" = - ] && continue
      landed "$store" "${BEAD[$store|$f]}"
      case "$LANDED" in pending) return 0 ;; landed) any=1 ;; vetoed) veto=${veto:-$VETOED_PR} ;; esac
    done
    if [ "$any" = 1 ]; then DECISION=left; return 0; fi
    why="waited on $id, which closed with no fix landed"
  else
    landed "$store" "$j"
    case "$LANDED" in landed) DECISION=left; return 0 ;; pending) return 0 ;; esac
    why="waited on $id, which closed with no merge"
  fi
  if [ -n "$veto" ]; then
    DECISION="vetoed$US$day$US$(one_line "$why after the operator vetoed $veto${reason:+: $reason}")$US$veto"
    return 0
  fi
  DECISION="ended$US$day$US$(one_line "$why${reason:+: $reason}")"
}

# settle — ends each wait that is done. A unit whose fix landed is removed
# with its text kept, and one whose wait ended with no fix is due again from
# the day it ended. One whose rule the operator vetoed is marked first, and its
# wait stays until it is. SETTLED_LEFT and SETTLED_DUE count them, and
# SETTLED_VETOED those of the due that were marked.
SETTLED_LEFT=0; SETTLED_DUE=0; SETTLED_VETOED=0
settle() {
  local dir sd wait store rc=0
  declare -A OUTCOME=() BY_STORE=()
  for dir in "${DIRS[@]}"; do
    while IFS= read -r wait; do
      [ -n "$wait" ] && [ -z "${OUTCOME[$wait]+x}" ] || continue
      OUTCOME[$wait]="wait"
      store=${STORE_OF[${wait%%-*}]:-}
      [ -n "$store" ] && BY_STORE[$store]="${BY_STORE[$store]:-} $wait"
    done < <(list_rows "$(state_of "$dir")" | awk -F'\t' '{ print $5 }')
  done
  # One read per store for every bead a unit waits on.
  for store in "${!BY_STORE[@]}"; do
    # shellcheck disable=SC2086  # bead ids split on the spaces between them
    fetch "$store" ${BY_STORE[$store]} || err "the store at $store did not answer, so the waits on its beads stay"
  done
  for wait in "${!OUTCOME[@]}"; do decide "$wait"; OUTCOME[$wait]=$DECISION; done
  for dir in "${DIRS[@]}"; do
    sd=$(state_of "$dir")
    list_rows "$sd" | to_us | while IFS="$US" read -r kind name hash _ wait _ _; do
      [ -n "$wait" ] && [ "${OUTCOME[$wait]:-wait}" != wait ] || continue
      printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$name" "$hash" "$wait" "${OUTCOME[$wait]}"
    done > "$WORK/plan"
    [ -s "$WORK/plan" ] || continue
    settle_dir "$dir" "$sd" "$WORK/plan" || rc=1
  done
  return "$rc"
}
settle_dir() {
  local dir=$1 sd=$2 plan=$3 w="$WORK/settle" kind name hash wait out day why pr unit full ef nh r rc=0
  lock_dir "$sd" "$dir" || return 1
  scan "$dir" "$w" || { unlock_dir; return 1; }
  list_rows "$sd" > "$w/rows"
  while IFS="$US" read -r kind name hash wait out day why pr; do
    # The row must still be the one the plan read.
    awk -F'\t' -v k="$kind" -v n="$name" -v h="$hash" -v wt="$wait" '$1 == k && $2 == n && $3 == h && $5 == wt { f = 1 } END { exit !f }' "$w/rows" || continue
    if [ "$out" = left ]; then
      # A unit changed since it was judged stays: it is due again.
      unit=$(awk -F'\t' -v k="$kind" -v n="$name" -v h="$hash" '$1 == k && $2 == n && $3 == h { print; exit }' "$w/units.tsv")
      [ -n "$unit" ] || continue
      IFS="$US" read -r _ _ _ full _ ef <<< "$(printf '%s' "$unit" | to_us)"
      if [ "$kind" = note ]; then remove_file "$sd" "$dir" "$name" "$full"; else remove_entry "$sd" "$dir" "$name" "$hash" "$ef"; fi
      r=$?
      case $r in
        0) ;;
        3) rc=1 ;;
        2) continue ;;
        *) err "$dir/$name stays, though its wait ended with a fix landed: its text was not kept, or its file could not be written"; rc=1; continue ;;
      esac
      drop_row "$w/rows" "$kind" "$name" "$hash"
      SETTLED_LEFT=$((SETTLED_LEFT + 1))
    else
      # A vetoed rule is marked in the note as it stands, or in the entry the
      # judge read, and the row takes the unit's hash once it is marked.
      nh=$hash
      if [ "$out" = vetoed ]; then
        ef=""
        if [ "$kind" = entry ]; then
          unit=$(awk -F'\t' -v n="$name" -v h="$hash" '$1 == "entry" && $2 == n && $3 == h { print; exit }' "$w/units.tsv")
          [ -n "$unit" ] || continue
          IFS="$US" read -r _ _ _ _ _ ef <<< "$(printf '%s' "$unit" | to_us)"
        fi
        veto_unit "$dir" "$kind" "$name" "$ef" "$pr"; r=$?
        case $r in
          0) nh=$VETO_HASH ;;
          2) continue ;;
          *) err "$dir/$name is not marked as vetoed, so it waits until a run marks it: a file could not be written, or it kept changing"; rc=1; continue ;;
        esac
        SETTLED_VETOED=$((SETTLED_VETOED + 1))
      fi
      # awk reads escapes in a -v value, so the reason, which can hold a
      # backslash, reaches it through the environment.
      WHY=$why awk -F'\t' -v OFS='\t' -v k="$kind" -v n="$name" -v h="$hash" -v nh="$nh" -v d="$day" \
        '$1 == k && $2 == n && $3 == h { $3 = nh; $5 = ""; $6 = d; $7 = ENVIRON["WHY"] } { print }' "$w/rows" > "$w/rows.next" && mv -f "$w/rows.next" "$w/rows"
      SETTLED_DUE=$((SETTLED_DUE + 1))
    fi
  done < <(to_us < "$plan")
  tidy "$dir" "$sd" || rc=1
  write_list "$sd" "$w/rows" || rc=1
  unlock_dir
  return "$rc"
}

# --- findings -------------------------------------------------------------------
# One finding per place the run cannot resolve, keyed by what it cannot
# resolve. The keys raised are kept in <state>/findings, so a later run that
# resolves one marks it cleared.
report_places() {
  local owed="$STATE_ROOT/findings" key names why title msg keep="" rc=0
  local -a now_keys=()
  local -A raised=()
  mkdir -p "$STATE_ROOT" 2>/dev/null
  mapfile -t now_keys < <(printf '%s\n' "$PLACES" | awk -F'\t' '$1 == "unresolved" { print $3 }' | sort -u)
  for key in "${now_keys[@]}"; do raised[$key]=1; done
  for key in "${now_keys[@]}"; do
    names=$(printf '%s\n' "$PLACES" | awk -F'\t' -v k="$key" '$1 == "unresolved" && $3 == k { printf "%s%s", (n++ ? ", " : ""), $2 }')
    why=$(printf '%s\n' "$PLACES" | awk -F'\t' -v k="$key" '$1 == "unresolved" && $3 == k { print $4; exit }')
    title="Memory intake cannot place the Claude Code memory of $names"
    msg="The learning loop's memory intake cannot tell where Claude Code keeps memory for $names: $why. It reads and removes nothing there until it can. Undoing what is named, or setting autoMemoryDirectory in the city's or the rig's own Claude settings, lets the next run place it."
    if [ -x "$PATROL_FINDING" ] && "$PATROL_FINDING" --scope memory-intake --key "$key" --title "$(printf '%s' "$title" | cut -c1-200)" --message "$msg" --type bug --priority 3 >/dev/null; then
      :
    else
      err "the finding $key did not record: $names: $why"; rc=1
    fi
    keep="$keep$key"$'\n'
  done
  if [ -f "$owed" ]; then
    while IFS= read -r key; do
      [ -n "$key" ] || continue
      [ -z "${raised[$key]+x}" ] || continue
      if [ -x "$PATROL_FINDING" ] && "$PATROL_FINDING" --scope memory-intake --key "$key" --cleared --message "The memory intake places this memory again." >/dev/null; then
        say "cleared the finding $key"
      else
        err "the clear of $key did not record; the next run tries again"; keep="$keep$key"$'\n'; rc=1
      fi
    done < "$owed"
  fi
  printf '%s' "$keep" | sort -u > "$owed.next" && mv -f "$owed.next" "$owed"
  return "$rc"
}

# --- verbs ------------------------------------------------------------------------
home_rig() {
  local repo
  repo=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -f "$repo/pack.toml" ] && grep -q '^name *= *"gc-toolkit"' "$repo/pack.toml"
}

due_all() {  # prints the due rows of every directory
  local dir i=0
  for dir in "${DIRS[@]}"; do
    i=$((i + 1))
    scan "$dir" "$WORK/due.$i" || continue
    due_rows "$dir" "$WORK/due.$i"
  done
}

cmd_read() {
  local dir sd w="$WORK/read" rc=0 kind name what why counts
  if ! home_rig; then say "off-home — not the gc-toolkit pack home rig; memory is not read here."; return 0; fi
  load_city || return 1
  load_guidance || return 1
  place_all
  while IFS=$'\t' read -r kind name what why; do
    case "$kind" in
      read) say "$name: $what ($why)" ;;
      absent) say "$name: absent: $why${what:+ ($what)}" ;;
      unresolved) say "$name: cannot place it: $why (finding $what)" ;;
    esac
  done <<< "$PLACES"
  report_places || rc=1
  for dir in "${DIRS[@]}"; do
    sd=$(state_of "$dir")
    lock_dir "$sd" "$dir" || { rc=1; continue; }
    LINKS=0
    tidy "$dir" "$sd" || rc=1
    guide "$dir" || { err "the guidance block of $dir/MEMORY.md was not written"; rc=1; }
    if scan "$dir" "$w"; then
      # A row whose unit is gone from the directory leaves the list.
      list_rows "$sd" | awk -F'\t' 'FILENAME == ARGV[1] { u[$1 SUBSEP $2 SUBSEP ($1 == "note" ? "" : $3)] = 1; next }
          (($1 SUBSEP $2 SUBSEP ($1 == "note" ? "" : $3)) in u)' "$w/units.tsv" - > "$w/rows"
      write_list "$sd" "$w/rows" || rc=1
    else
      rc=1
    fi
    unlock_dir
    counts=$(awk -F'\t' '{ c[$1]++ } END { printf "%d notes and %d entries", c["note"], c["entry"] }' "$w/units.tsv")
    say "${DIR_NAMES[$dir]}: $counts; links to gone notes taken out of $LINKS file(s)$([ "$GUIDED" = 1 ] && printf '; guidance block rewritten')"
  done
  SETTLED_LEFT=0; SETTLED_DUE=0; SETTLED_VETOED=0
  settle || rc=1
  say "waits ended: $SETTLED_LEFT unit(s) removed with a fix landed, their text kept; $SETTLED_DUE due again with no fix landed"
  [ "$SETTLED_VETOED" = 0 ] || say "vetoed: $SETTLED_VETOED of those due again marked, so agents stop following the rule the operator vetoed"
  say "$(due_all | grep -c .) due"
  return "$rc"
}

cmd_due() {
  local limit="" count=0 i ef rows
  local -a args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) [ $# -ge 2 ] || { usage; return 2; }; limit=$2; shift 2 ;;
      --count) count=1; shift ;;
      *) usage; return 2 ;;
    esac
  done
  case "$limit" in *[!0-9]*) err "--limit takes a count"; return 2 ;; esac
  if ! load_city; then
    if [ "$count" = 1 ]; then echo 0; else echo '[]'; fi
    return 1
  fi
  place_all
  due_all > "$WORK/due.tsv"
  if [ "$count" = 1 ]; then grep -c . "$WORK/due.tsv"; return 0; fi
  # The fields are joined unescaped: none holds a tab or a newline, and the
  # reads below take each backslash as written.
  jq -Rnr --argjson lim "${limit:-null}" '[inputs | split("\t")
      | {age: (if .[0] == "d" then (.[1] | strptime("%Y-%m-%d") | mktime) else (.[1] | tonumber) end), row: .}]
    | sort_by(.age, .row[2], .row[5]) | (if $lim == null then . else .[0:$lim] end)
    | .[] | [(.age | todate)] + .row[2:] | join("\t")' < "$WORK/due.tsv" > "$WORK/due.sel" || { echo '[]'; return 1; }
  while IFS="$US" read -r i ef; do
    args+=(--rawfile "t$i" "$ef")
  done < <(awk -F'\t' -v OFS="$US" '$9 != "" { print NR - 1, $9 }' "$WORK/due.sel")
  rows=$(jq -Rn "${args[@]}" '[inputs | split("\t")] | to_entries | map(.key as $i | .value
      | {memory_ref: (.[2][0:16] + "/" + .[4] + "@" + .[5][0:16]), memory_kind: .[3], memory_dir: .[1],
         memory_file: (.[1] + "/" + .[4]), memory_due: .[6], memory_prior: .[7], created_at: .[0]}
        + (if .[8] != "" then {memory_text: $ARGS.named["t\($i)"]} else {} end))' < "$WORK/due.sel") || { echo '[]'; return 1; }
  printf '%s\n' "$rows"
}

# append_use <full hash> — the note's text with the use line added, while it
# still has the hash it was listed at.
append_use() {
  local text
  text=$(cat; printf x); text=${text%x}
  [ "$(sha_text "$text")" = "$1" ] || return 1
  printf '%s' "$text"
  case "$text" in *$'\n'|'') ;; *) printf '\n' ;; esac
  printf '%s\n' "$USE_LINE"
}

# apply_dir <dir> <decisions> — applies one directory's decisions under its lock.
APPLY_FAIL=0
apply_dir() {
  local dir=$1 lines=$2 sd w="$WORK/apply" ref verb arg ask name h16 kind full base ef rc drops=0 unit
  sd=$(state_of "$dir")
  lock_dir "$sd" "$dir" || { APPLY_FAIL=1; return; }
  scan "$dir" "$w" || { unlock_dir; APPLY_FAIL=1; return; }
  list_rows "$sd" > "$w/rows"
  while IFS="$US" read -r ref verb arg ask; do
    name=${ref#*/}; h16=${name##*@}; name=${name%@*}
    unit=$(awk -F'\t' -v n="$name" -v h="$h16" '$2 == n && index($4, h) == 1 { print; exit }' "$w/units.tsv")
    if [ -z "$unit" ]; then
      say "refused $ref: it changed since it was listed, or is gone; it stays, and is due while it is there"
      continue
    fi
    IFS="$US" read -r kind _ base full _ ef <<< "$(printf '%s' "$unit" | to_us)"
    if [ "$verb" = drop ]; then
      if [ "$kind" = note ]; then
        remove_file "$sd" "$dir" "$name" "$full"; rc=$?
        case $rc in
          0) say "removed $ref, its text kept at $sd/removed/$name@$full" ;;
          2) say "refused $ref: it changed since it was listed; it stays and is due"; continue ;;
          *) err "could not remove $ref, so it stays: its text was not kept, or it could not be removed"; APPLY_FAIL=1; continue ;;
        esac
      else
        remove_entry "$sd" "$dir" "$name" "$base" "$ef"; rc=$?
        case $rc in
          0|3) say "removed $ref, its text kept at $sd/removed/$name@$base" ;;
          2) say "refused $ref: its collection note kept changing or no longer holds it; it stays"; continue ;;
          *) err "could not remove $ref, so it stays: its text was not kept, or its collection note could not be written"; APPLY_FAIL=1; continue ;;
        esac
        [ "$rc" = 3 ] && APPLY_FAIL=1
        [ "$HUB_GONE" = 1 ] && say "removed $name, which has no entries left"
      fi
      drops=1
      drop_row "$w/rows" "$kind" "$name" "$base"
      continue
    fi
    if [ "$ask" = ask-use ]; then
      if [ "$kind" != note ]; then err "$ref: ask-use takes a whole note"; APPLY_FAIL=1; continue; fi
      if ! grep -qF "$USE_MARK" "$dir/$name"; then
        rewrite "$dir/$name" append_use "$full"; rc=$?
        if [ "$rc" != 0 ] || [ "$REWROTE" != 1 ]; then say "refused $ref: it changed since it was listed; it stays and is due"; continue; fi
        base=$(LC_ALL=C awk -v RE="$USE_AWK_RE" '$0 !~ RE' "$dir/$name" | "${SHA[@]}" | cut -c1-64)
      fi
    fi
    drop_row "$w/rows" "$kind" "$name" "$base"
    if [ "$verb" = waits ]; then
      printf '%s\t%s\t%s\t%s\t%s\t\t\n' "$kind" "$name" "$base" "$NOW_ISO" "$arg" >> "$w/rows"
      say "recorded $ref: waits on $arg"
    else
      printf '%s\t%s\t%s\t%s\t\t%s\t\n' "$kind" "$name" "$base" "$NOW_ISO" "$arg" >> "$w/rows"
      say "recorded $ref: due again on $arg${ask:+, with a request to record each use}"
    fi
  done < <(to_us < "$lines")
  if [ "$drops" = 1 ]; then tidy "$dir" "$sd" || APPLY_FAIL=1; fi
  write_list "$sd" "$w/rows" || APPLY_FAIL=1
  unlock_dir
}

cmd_apply() {
  local src=${1:-} raw line rest ref verb arg ask extra key16 name h16 dir d store ok
  [ -n "$src" ] && [ $# -eq 1 ] || { usage; return 2; }
  if [ "$src" = - ]; then raw=$(cat); else raw=$(cat -- "$src") || { err "cannot read $src"; return 1; }; fi
  load_city || return 1
  load_guidance || return 1
  place_all
  declare -A BY_KEY=() WANT=()
  for d in "${DIRS[@]}"; do BY_KEY[${DIR_KEY[$d]:0:16}]=$d; done
  : > "$WORK/apply.lines"
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    # A note's name can hold spaces, so the ref runs to the @ and sixteen hex
    # digits that end it, and the words after it are the decision.
    ref=""; rest=""
    if [[ "$line" =~ ^[[:space:]]*([0-9a-f]{16}/.*@[0-9a-f]{16})([[:space:]]+(.*))?$ ]]; then
      ref=${BASH_REMATCH[1]}; rest=${BASH_REMATCH[3]}
    fi
    read -r verb arg ask extra <<< "$rest"
    key16=${ref%%/*}; name=${ref#*/}; h16=${name##*@}; name=${name%@*}
    ok=1
    [[ "$ref" == */*@* && "$key16" =~ ^[0-9a-f]{16}$ && "$h16" =~ ^[0-9a-f]{16}$ && -n "$name" && "$name" != */* ]] || ok=0
    case "$verb" in
      waits) [ -n "$arg" ] && [ -z "$ask" ] || ok=0 ;;
      next) [[ "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && "$arg" > "$TODAY" ]] \
              && [ "$(jq -rn --arg d "$arg" '$d | strptime("%Y-%m-%d") | mktime | strftime("%Y-%m-%d")' 2>/dev/null)" = "$arg" ] \
              && { [ -z "$ask" ] || [ "$ask" = ask-use ]; } || ok=0 ;;
      drop) [ -z "$arg" ] || ok=0 ;;
      *) ok=0 ;;
    esac
    [ -z "$extra" ] || ok=0
    if [ "$ok" = 0 ]; then err "not a decision (<ref> waits <bead> | <ref> next <YYYY-MM-DD after today> [ask-use] | <ref> drop): $line"; APPLY_FAIL=1; continue; fi
    dir=${BY_KEY[$key16]:-}
    if [ -z "$dir" ]; then err "$ref: no memory directory the run reads now has that key"; APPLY_FAIL=1; continue; fi
    if [ "$verb" = waits ]; then
      store=${STORE_OF[${arg%%-*}]:-}
      if [ -z "$store" ]; then err "$ref: no store of the city carries $arg"; APPLY_FAIL=1; continue; fi
      WANT[$store]="${WANT[$store]:-} $arg"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$dir" "$ref" "$verb" "$arg" "$ask" >> "$WORK/apply.lines"
  done <<< "$raw"
  # Each bead a note waits on must be in its store before a note waits on it.
  for store in "${!WANT[@]}"; do
    # shellcheck disable=SC2086  # bead ids split on the spaces between them
    fetch "$store" ${WANT[$store]} || { err "the store at $store did not answer, so no note is recorded to wait on its beads"; APPLY_FAIL=1; }
  done
  for d in "${DIRS[@]}"; do
    : > "$WORK/apply.ok"
    while IFS="$US" read -r dir ref verb arg ask; do
      [ "$dir" = "$d" ] || continue
      if [ "$verb" = waits ]; then
        store=${STORE_OF[${arg%%-*}]}
        if [ "${BEAD[$store|$arg]:--}" = - ]; then err "$ref: $arg is not in its store, or its store did not answer"; APPLY_FAIL=1; continue; fi
      fi
      printf '%s\t%s\t%s\t%s\n' "$ref" "$verb" "$arg" "$ask" >> "$WORK/apply.ok"
    done < <(to_us < "$WORK/apply.lines")
    [ -s "$WORK/apply.ok" ] && apply_dir "$d" "$WORK/apply.ok"
  done
  return "$APPLY_FAIL"
}

case "${1:-}" in
  read)  shift; [ $# -eq 0 ] || { usage; exit 2; }; cmd_read; exit $? ;;
  due)   shift; cmd_due "$@"; exit $? ;;
  apply) shift; cmd_apply "$@"; exit $? ;;
  *) usage; exit 2 ;;
esac
