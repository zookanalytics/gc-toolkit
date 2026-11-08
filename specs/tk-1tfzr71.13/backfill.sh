#!/usr/bin/env bash
# backfill.sh — the cut-over for tk-1tfzr71.13. A closed bead disposed before
# the edges named its successor in the retired gc.superseded_by key (or its bare
# superseded_by form). This gives each such bead the bd edge the readers now
# read: `duplicates` when its close named it a duplicate of that bead,
# `supersedes` otherwise. It writes nothing without --apply.
#
#   backfill.sh [--apply] [--rig <name>]...
#
# With no --rig it reads every rig `gc rig list` names, suspended ones included,
# each through `gc bd --db <path>/.beads`; a store that does not answer is
# reported and skipped. A bead that is not closed is left alone: a live bead
# carrying the key is a disposition whose close never landed, and the follow-up
# closes it through bead-rehome.sh.
#
# bd keeps one edge per pair of beads, so an edge the bead already carries onto
# its successor gives way to the disposition's. A blocks edge is a wait the
# disposition ended. A tracks, until, related or relates-to edge is one no reader
# acts on for a closed bead (cut-over.md names each type's readers), and a note on
# the bead says what it replaced and how to put it back. Left alone and reported:
# an input convoy's tracks edge, which is what makes it a convoy, a pair joined by
# any other type, and a bead whose edge already names another successor.
#
# Prints one line per bead it writes or would write, or leaves alone for a
# reason, and one count line per store. Exit 0 when every store answered and
# every write read back, 1 otherwise.
set -uo pipefail

APPLY=""; RIGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --rig)   RIGS+=("${2:?--rig needs a name}"); shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "backfill: unknown argument '$1'" >&2; exit 64 ;;
  esac
done

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
WORK=$(mktemp -d "${TMPDIR:-/tmp}/backfill.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

RIG_ROWS=$(gc rig list --json 2>/dev/null | jq -c '.rigs[]? | {name, path, suspended}' 2>/dev/null) \
  || { echo "backfill: gc rig list did not answer" >&2; exit 1; }
[ -n "$RIG_ROWS" ] || { echo "backfill: gc rig list named no rig" >&2; exit 1; }

# The row the readers read: a bead's `gc bd list` row, which carries every edge
# of the bead, one into another rig's store included.
list_row() { # <db> <id>
  gc bd --db "$1" list --id "$2" --all --include-gates --include-infra --json --limit 0 </dev/null 2>/dev/null \
    | grep -a -vE '^gc bd:' | scrub | jq -c --arg id "$2" '[ .[]? | select(.id == $id) ]' 2>/dev/null
}

# One verdict per candidate row, tab-separated: id, successor, edge type, what
# to do (write, unblock-write, replace:<type>, recorded, live, conflict:<other>,
# pair-taken:<type>, empty).
VERDICT_JQ='
  .[] | . as $b
  | (((.metadata // {})["gc.superseded_by"] // (.metadata // {}).superseded_by // "") | tostring) as $s
  | ((((.close_reason // "") | tostring) + " " + ((.notes // "") | tostring)) | contains("duplicate of " + $s + " ")) as $dup
  | (if $dup then "duplicates" else "supersedes" end) as $t
  | [ .dependencies[]? | select((.type // "") == "duplicates" or (.type // "") == "supersedes") ] as $disp
  | [ .dependencies[]? | select(((.depends_on_id // "") | tostring) == $s) | ((.type // "") | tostring) ] as $pair
  | (if $s == "" then "empty"
     elif ((.status // "") | tostring) != "closed" then "live"
     elif any($disp[]; ((.depends_on_id // "") | tostring) == $s) then "recorded"
     elif ($disp | length) > 0 then "conflict:" + (($disp[0].depends_on_id // "") | tostring)
     elif ($pair | length) == 0 then "write"
     elif $pair == ["blocks"] then "unblock-write"
     elif $pair == ["tracks"] and ((.issue_type // "") == "convoy") then "pair-taken:tracks"
     elif ($pair | length) == 1 and any(["tracks", "until", "related", "relates-to"][]; . == $pair[0]) then "replace:" + $pair[0]
     else "pair-taken:" + ($pair | join(",")) end) as $act
  | [ .id, $s, $t, $act ] | @tsv'

overall=0
while IFS= read -r rig; do
  name=$(printf '%s' "$rig" | jq -r .name); path=$(printf '%s' "$rig" | jq -r .path)
  susp=$(printf '%s' "$rig" | jq -r '.suspended // false')
  if [ "${#RIGS[@]}" -gt 0 ]; then
    case " ${RIGS[*]} " in *" $name "*) ;; *) continue ;; esac
  fi
  db="$path/.beads"
  read_ok=1
  for key in gc.superseded_by superseded_by; do
    gc bd --db "$db" list --all --include-gates --include-infra --has-metadata-key "$key" --json --limit 0 </dev/null 2>/dev/null \
      | grep -a -vE '^gc bd:' | scrub > "$WORK/$key.json"
    jq -e 'type == "array"' "$WORK/$key.json" >/dev/null 2>&1 || { read_ok=""; break; }
  done
  [ -z "$read_ok" ] || jq -c -s 'add | unique_by(.id)' "$WORK/gc.superseded_by.json" "$WORK/superseded_by.json" > "$WORK/rows.json"
  if [ -z "$read_ok" ]; then
    echo "$name: the store did not answer (suspended=$susp); nothing read or written"
    overall=1; continue
  fi
  n_write=0; n_unblock=0; n_replace=0; n_recorded=0; n_live=0; n_left=0; n_failed=0
  while IFS=$'\t' read -r id succ etype act; do
    [ -n "$id" ] || continue
    old=""
    case "$act" in
      recorded) n_recorded=$((n_recorded + 1)); continue ;;
      live)     n_live=$((n_live + 1)); echo "$name: $id is not closed; left for the follow-up (names $succ)"; continue ;;
      write) ;;
      unblock-write) old=blocks ;;
      replace:*) old="${act#replace:}" ;;
      *)        n_left=$((n_left + 1)); echo "$name: $id left alone: $act (names $succ)"; continue ;;
    esac
    how=""; [ -z "$old" ] || how=" (in place of its $old edge)"
    if [ -z "$APPLY" ]; then
      echo "$name: would write $id $etype $succ$how"
      case "$act" in
        write) n_write=$((n_write + 1)) ;;
        unblock-write) n_unblock=$((n_unblock + 1)) ;;
        *) n_replace=$((n_replace + 1)) ;;
      esac
      continue
    fi
    if [ -n "$old" ] \
       && ! gc bd --db "$db" dep remove "$id" "$succ" </dev/null >/dev/null 2>&1; then
      echo "$name: $id: the $old edge onto $succ did not drop; nothing written"
      n_failed=$((n_failed + 1)); continue
    fi
    if ! err=$(gc bd --db "$db" dep add "$id" "$succ" --type "$etype" </dev/null 2>&1 >/dev/null); then
      echo "$name: $id: dep add $etype $succ refused: $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-200)"
      [ -z "$old" ] || gc bd --db "$db" dep add "$id" "$succ" --type "$old" </dev/null >/dev/null 2>&1
      n_failed=$((n_failed + 1)); continue
    fi
    if list_row "$db" "$id" | jq -e --arg s "$succ" --arg t "$etype" \
         'any(.[0].dependencies[]?; (.depends_on_id // "") == $s and (.type // "") == $t)' >/dev/null 2>&1; then
      echo "$name: wrote $id $etype $succ$how"
      case "$act" in
        write) n_write=$((n_write + 1)) ;;
        unblock-write) n_unblock=$((n_unblock + 1)) ;;
        *)
          n_replace=$((n_replace + 1))
          gc bd --db "$db" update "$id" --append-notes "Cut-over $(date -u +%Y-%m-%dT%H:%MZ): the $old edge onto $succ became a $etype edge, because bd keeps one edge per pair of beads and this bead's retired successor key names $succ. To put it back: dep remove $id $succ, then dep add $id $succ --type $old." </dev/null >/dev/null 2>&1 \
            || echo "$name: $id: the note saying what the $etype edge replaced did not write; it replaced a $old edge" ;;
      esac
    else
      echo "$name: $id: the $etype edge onto $succ did not read back"
      n_failed=$((n_failed + 1))
    fi
  done < <(jq -r "$VERDICT_JQ" "$WORK/rows.json")
  verb="written"; [ -n "$APPLY" ] || verb="to write"
  echo "$name: $(jq length "$WORK/rows.json") carry the key: $n_write $verb, $n_unblock $verb after dropping a blocks edge, $n_replace $verb in place of another edge, $n_recorded already recorded, $n_live not closed, $n_left left alone, $n_failed failed (suspended=$susp)"
  [ "$n_failed" -eq 0 ] || overall=1
done <<< "$RIG_ROWS"
exit "$overall"
