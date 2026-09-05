#!/usr/bin/env bash
# gc-deacon-ledger.sh — the deacon's rolling incident ledger.
#
# What the deacon did over a shift lands in five separate places: mail beads,
# warrant beads, ephemeral nudges, memory-file edits, and cleanup actions that
# record nothing at all. Reconstructing a shift means a union of all of them,
# and a deacon that has just been recycled has the same problem an operator
# does. This is the one skimmable record: a single open bead labeled
# `deacon-ledger`, one comment per non-routine action.
#
#   gc-deacon-ledger.sh append <category> <one-line> [artifact-ref]
#   gc-deacon-ledger.sh current                 # id of the current ledger
#   gc-deacon-ledger.sh show [--since <dur>]    # entries, oldest first
#
# Entry:        <UTC-ts> [<category>] <one-line> -> <artifact-ref>
# Categories:   escalation warrant deviation boot config recovery cleanup note
# artifact-ref: mail:<id> · bead:<id> · memory:<path> · event:<seq> · -
#
# A routine on-track reading appends NOTHING. The ledger carries the actions a
# shift is reconstructed from, so anything that fires every cycle regardless of
# what was found belongs outside it.
#
# STORE. Every read and write here runs against the city store, from the city
# path with GC_RIG unset. `gc bd` selects a store from GC_RIG first and the
# working directory second, and callers arrive holding both: escalate.sh
# exports GC_RIG so its visit lands in the subject bead's rig, and the patrol
# formula binds one for the same reason. Taking the ambient store would file
# an escalation's entry in a rig ledger while the deacon reads the city one.
#
# ROTATION keeps each ledger skimmable: past the entry or age bound, the
# current bead gets a final `rotated -> <new-id>` entry and is closed, and a
# fresh one carrying `continues:<old-id>` takes over. `show --since` walks that
# chain backwards, so a rotation mid-window does not truncate the answer.
#
# Exit: 0 done · 1 the ledger could not be read or written · 2 usage
set -uo pipefail

LEDGER_LABEL="${GC_DEACON_LEDGER_LABEL:-deacon-ledger}"
MAX_ENTRIES="${GC_DEACON_LEDGER_MAX_ENTRIES:-40}"
MAX_AGE_DAYS="${GC_DEACON_LEDGER_MAX_AGE_DAYS:-7}"
MAX_LINE="${GC_DEACON_LEDGER_MAX_LINE:-200}"
# A `continues:` pointer is data, so a cycle in it is reachable. Bound the walk.
MAX_HOPS="${GC_DEACON_LEDGER_MAX_HOPS:-10}"
CATEGORIES="escalation warrant deviation boot config recovery cleanup note"

warn() { echo "gc-deacon-ledger: $*" >&2; }

usage() {
  cat >&2 <<'U'
usage: gc-deacon-ledger.sh append <category> <one-line> [artifact-ref]
       gc-deacon-ledger.sh current
       gc-deacon-ledger.sh show [--since <dur>]

  append  records one non-routine action. <category> is one of
          escalation warrant deviation boot config recovery cleanup note;
          [artifact-ref] points at the durable thing the action produced
          (mail:<id>, bead:<id>, memory:<path>, event:<seq>), default "-".
  current prints the current ledger bead id, creating one if none is open.
  show    prints entries oldest first. --since <dur> (30m, 48h, 7d, 900s)
          bounds the window and follows `continues:` back through rotations.
U
}

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

# The ledger lives in the city store; see STORE above.
CITY="${GC_CITY_PATH:-${GC_CITY:-}}"
if [ -n "$CITY" ] && [ -d "$CITY" ]; then
  cd "$CITY" || warn "could not enter $CITY — reading whatever store this directory selects"
else
  warn "neither GC_CITY_PATH nor GC_CITY names a directory — reading whatever store this directory selects"
fi
unset GC_RIG

bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }

now_epoch() { date -u +%s; }
now_utc()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ISO8601-UTC -> epoch seconds, 0 when unparseable. GNU takes -d, BSD/macOS
# needs -j -f; neither accepts the other's form, so try both.
epoch_of() {
  [ -n "${1:-}" ] || { echo 0; return 0; }
  date -u -d "$1" +%s 2>/dev/null \
    || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null \
    || echo 0
}

# epoch seconds -> ISO8601-UTC, empty when unparseable (same split).
iso_of() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || echo ""
}

# <n>[smhd] -> seconds. Empty on anything else, which the caller reports.
duration_secs() {
  local d="${1:-}" n u
  n="${d%[smhd]}"; u="${d#"$n"}"
  case "$n" in ''|*[!0-9]*) printf ''; return 0 ;; esac
  case "$u" in
    ''|s) printf '%s' "$n" ;;
    m)    printf '%s' "$((n * 60))" ;;
    h)    printf '%s' "$((n * 3600))" ;;
    d)    printf '%s' "$((n * 86400))" ;;
    *)    printf '' ;;
  esac
}

# The open bead carrying the ledger label, newest first. More than one is a
# lost create race rather than a state anything produces on purpose: the newest
# is the live one, and the extras are named so they can be closed by hand.
find_open_ledger() {
  local rows ids
  rows=$(bd_json list --status=open --label "$LEDGER_LABEL" --limit=0) || rows=""
  ids=$(printf '%s' "$rows" | jq -r '
    if type == "array"
    then ([.[] | select(.id != null)] | sort_by(.created_at // "") | reverse | .[].id)
    else empty end' 2>/dev/null)
  [ -n "$ids" ] || return 0
  local extras
  extras=$(printf '%s\n' "$ids" | sed '1d' | tr '\n' ' ')
  [ -n "${extras// /}" ] && warn "more than one open '$LEDGER_LABEL' bead; using the newest and leaving: $extras"
  printf '%s\n' "$ids" | sed -n '1p'
}

# The whole row for one bead, so a caller reads created_at and comment_count
# without a second round trip.
ledger_row() { bd_json show "$1" | jq -c 'if type == "array" then .[0] // {} else {} end' 2>/dev/null; }

create_ledger() { # [<predecessor-id>] -> new ledger id
  local prev="${1:-}" body id
  body="Rolling incident ledger for the deacon patrol: one comment per non-routine action.

  <UTC-ts> [<category>] <one-line> -> <artifact-ref>

categories:   $CATEGORIES
artifact-ref: mail:<id> · bead:<id> · memory:<path> · event:<seq> · -

Written by assets/scripts/gc-deacon-ledger.sh; read it with
\`gc-deacon-ledger.sh show --since 48h\`. Rotates past $MAX_ENTRIES entries or
$MAX_AGE_DAYS days, and the successor carries a continues: pointer back here."
  [ -n "$prev" ] && body="$body

continues:$prev"
  id=$(gc bd create --title "deacon ledger $(date -u +%Y-%m-%d)" -t task \
        -l "$LEDGER_LABEL" -d "$body" --json 2>/dev/null | scrub \
        | jq -r 'if type == "array" then (.[0].id // "") else (.id // "") end' 2>/dev/null)
  # `bd create --json` can answer with an empty id although the bead landed, so
  # a retry duplicates the ledger. Re-read the locator instead: it finds the
  # bead the create actually made, and finds nothing when it truly failed.
  [ -n "$id" ] || id=$(find_open_ledger)
  printf '%s' "$id"
}

# The current ledger, rotated first when it is over either bound. Rotation is
# ordered so a failure leaves a WRITABLE ledger: the successor is created
# before the predecessor is closed, and a create that fails keeps the old one.
current_ledger() {
  local id row created age_days entries new
  id=$(find_open_ledger)
  if [ -z "$id" ]; then
    id=$(create_ledger)
    [ -n "$id" ] || { warn "could not create a ledger bead"; return 1; }
    printf '%s' "$id"; return 0
  fi
  row=$(ledger_row "$id")
  entries=$(printf '%s' "$row" | jq -r '.comment_count // 0' 2>/dev/null)
  created=$(printf '%s' "$row" | jq -r '.created_at // ""' 2>/dev/null)
  case "$entries" in ''|*[!0-9]*) entries=0 ;; esac
  age_days=0
  if [ -n "$created" ]; then
    local c; c=$(epoch_of "$created")
    [ "$c" -gt 0 ] 2>/dev/null && age_days=$(( ($(now_epoch) - c) / 86400 ))
  fi
  if [ "$entries" -lt "$MAX_ENTRIES" ] && [ "$age_days" -lt "$MAX_AGE_DAYS" ]; then
    printf '%s' "$id"; return 0
  fi
  new=$(create_ledger "$id")
  if [ -z "$new" ] || [ "$new" = "$id" ]; then
    warn "rotation of $id could not create a successor; still appending to $id"
    printf '%s' "$id"; return 0
  fi
  gc bd comment "$id" "$(now_utc) [note] rotated -> $new ($entries entries, ${age_days}d) -> bead:$new" >/dev/null 2>&1 \
    || warn "could not write the rotation entry on $id"
  gc bd close "$id" --reason "ledger rotated -> $new" >/dev/null 2>&1 \
    || warn "could not close rotated ledger $id; it stays open beside $new until closed by hand"
  printf '%s' "$new"
}

# One line, control characters gone, whitespace runs collapsed, bounded. A
# ledger reads top to bottom, so an entry that wraps for a paragraph costs the
# skim the whole artifact exists to give.
one_line() {
  local s
  # Whitespace is folded BEFORE the control-char scrub: TAB is a C0 byte, so a
  # scrub-first order deletes it and joins the two words it separated.
  s=$(printf '%s' "$1" | tr '\n\r\t' '   ' | scrub | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//')
  if [ "${#s}" -gt "$MAX_LINE" ]; then
    s="${s:0:$((MAX_LINE - 3))}..."
  fi
  printf '%s' "$s"
}

cmd_append() {
  local category="${1:-}" line="${2:-}" ref="${3:--}" id entry
  [ -n "$category" ] && [ -n "$line" ] || { warn "append needs <category> and <one-line>"; usage; return 2; }
  case " $CATEGORIES " in
    *" $category "*) ;;
    *) warn "unknown category '$category'; use one of: $CATEGORIES"; return 2 ;;
  esac
  [ -n "$ref" ] || ref="-"
  case "$ref" in
    -|mail:?*|bead:?*|memory:?*|event:?*) ;;
    *) warn "artifact-ref '$ref' names no known kind; use mail:<id>, bead:<id>, memory:<path>, event:<seq>, or -"; return 2 ;;
  esac
  line=$(one_line "$line")
  ref=$(one_line "$ref")
  [ -n "$line" ] || { warn "the entry text collapsed to nothing"; return 2; }
  id=$(current_ledger) || return 1
  [ -n "$id" ] || { warn "no ledger to append to"; return 1; }
  entry="$(now_utc) [$category] $line -> $ref"
  if gc bd comment "$id" "$entry" >/dev/null 2>&1; then
    echo "$id: $entry"
    return 0
  fi
  warn "could not append to $id: $entry"
  return 1
}

cmd_current() {
  local id
  id=$(current_ledger) || return 1
  [ -n "$id" ] || return 1
  printf '%s\n' "$id"
}

# Entries of one ledger, oldest first, dropping every comment that is not one.
# A hand-written comment is a note to a reader, not a shift record.
entries_of() {
  gc bd comments "$1" --json 2>/dev/null | scrub \
    | jq -r 'if type == "array" then (.[] | .text // "") else empty end' 2>/dev/null \
    | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[' \
    | sort -s -k1,1
}

predecessor_of() {
  ledger_row "$1" | jq -r '.description // ""' 2>/dev/null \
    | sed -n 's/^continues:\([A-Za-z0-9._-]*\).*/\1/p' | sed -n '1p'
}

cmd_show() {
  local since="" cutoff="" secs id hops seen chain
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since="${2:-}"; shift 2 || { usage; return 2; } ;;
      --since=*) since="${1#--since=}"; shift ;;
      -h|--help) usage; return 2 ;;
      *) warn "unknown argument '$1'"; usage; return 2 ;;
    esac
  done
  if [ -n "$since" ]; then
    secs=$(duration_secs "$since")
    [ -n "$secs" ] || { warn "--since '$since' is not a duration (30m, 48h, 7d, 900s)"; return 2; }
    cutoff=$(iso_of "$(( $(now_epoch) - secs ))")
    [ -n "$cutoff" ] || { warn "could not compute a cutoff for --since $since"; return 2; }
  fi
  id=$(find_open_ledger)
  [ -n "$id" ] || { echo "gc-deacon-ledger: no open '$LEDGER_LABEL' bead — nothing recorded yet"; return 0; }

  # Oldest ledger first, so the chain reads forward. Walk back only while a
  # window is asked for and could still reach the predecessor.
  chain="$id"; hops=0; seen=" $id "
  while [ -n "$cutoff" ] && [ "$hops" -lt "$MAX_HOPS" ]; do
    local prev oldest
    prev=$(predecessor_of "$id")
    [ -n "$prev" ] || break
    case "$seen" in *" $prev "*) warn "continues: chain loops at $prev; stopping the walk"; break ;; esac
    oldest=$(ledger_row "$prev" | jq -r '.created_at // ""' 2>/dev/null)
    chain="$prev $chain"; seen="$seen$prev "; id="$prev"; hops=$((hops + 1))
    # A ledger created after the cutoff cannot hold anything older than it, so
    # its own predecessor is out of the window and the walk stops here.
    [ -n "$oldest" ] && [ "$oldest" \> "$cutoff" ] || break
  done

  local b
  for b in $chain; do
    local out
    out=$(entries_of "$b")
    [ -n "$cutoff" ] && out=$(printf '%s\n' "$out" | awk -v c="$cutoff" 'NF && $1 >= c')
    printf '# %s%s\n' "$b" "${cutoff:+ — entries since $cutoff}"
    if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "  (no entries in window)"; fi
  done
}

case "${1:-}" in
  append)  shift; cmd_append "$@" ;;
  current) shift; [ $# -eq 0 ] || { warn "current takes no arguments"; usage; exit 2; }; cmd_current ;;
  show)    shift; cmd_show "$@" ;;
  -h|--help|"") usage; exit 2 ;;
  *) warn "unknown command '$1'"; usage; exit 2 ;;
esac
