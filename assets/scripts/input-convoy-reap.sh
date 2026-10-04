#!/usr/bin/env bash
# input-convoy-reap.sh — close the synthetic input convoys no live workflow
# names. gc sling mints one "input convoy for <bead>" (gc.synthetic=true) per
# pour, and the pour's workflow root names it in gc.input_convoy_id. Nothing
# closes that convoy when its workflow finishes: a convoy closes once every
# member it tracks is closed, and the tracked bead often outlives the workflow
# (a first reaction leaves its subject open by design). A convoy minted for a
# pour that never landed is named by nothing at all.
#
# The gate is the live-namer rule the liveness sweep's worked-via-convoy block
# applies: a convoy is dead when no non-closed bead names it as
# gc.input_convoy_id. Neither the convoy's existence nor its tracked bead's
# status counts. The namer read takes every status and the ephemeral tier and
# keeps whatever is not closed, so a status this script does not list still
# protects a convoy. A convoy younger than the grace window is left alone, so a
# sling caught between the mint and the pour is never touched, and an unreadable
# created_at reads as young. Out of scope: owned convoys, convoys that are not
# synthetic input convoys, and convoys that are not open.
#
# The workflow roots are read from the convoys' own store. When no bead there
# names any input convoy at all while candidates exist, the roots may live in
# another store, so the pass refuses rather than reading every convoy as dead.
#
# Run by hand; no order schedules it. Without --apply it reports what it would
# close. Closes carry a reason and are read back with one re-listing; a close
# that did not land is reported and left for a re-run.
#
# Usage: input-convoy-reap.sh [--apply] [--grace-minutes N] [--db <beads-dir>]
#   --db defaults to $GC_RIG_ROOT/.beads when GC_RIG_ROOT is set, else the store
#   gc bd resolves from the working directory.
# Exit: 0 pass completed · 1 a listing could not be read, or the store holds no
# workflow roots (nothing closed) · 2 usage.
set -u

PROG="input-convoy-reap"
APPLY=0
GRACE_MIN="${INPUT_CONVOY_REAP_GRACE_MINUTES:-60}"
DB="${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --grace-minutes) shift; GRACE_MIN="${1:-}" ;;
    --grace-minutes=*) GRACE_MIN="${1#--grace-minutes=}" ;;
    --db) shift; DB="${1:-}" ;;
    --db=*) DB="${1#--db=}" ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$PROG: unexpected argument: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$GRACE_MIN" in ''|*[!0-9]*) echo "$PROG: --grace-minutes must be a whole number of minutes (got '$GRACE_MIN')" >&2; exit 2 ;; esac
command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

bdx() { if [ -n "$DB" ]; then gc bd "$@" --db "$DB"; else gc bd "$@"; fi; }
# bd_rows <outfile> <gc-bd-args...> — one listing as a JSON array in <outfile>.
# Non-zero means "could not tell", never "nothing there". The "gc bd:" notice
# line is dropped whichever stream carries it.
bd_rows() {
  local out="$1"; shift
  bdx "$@" --json </dev/null 2>/dev/null | grep -av '^gc bd:' | scrub > "$out"
  jq -e 'type == "array"' "$out" >/dev/null 2>&1
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-input-convoy-reap.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

bd_rows "$TMP/convoys.json" list --type=convoy --status=open --limit 0 \
  || { echo "$PROG: could not list open convoys; nothing closed" >&2; exit 1; }
bd_rows "$TMP/namers.json" list --has-metadata-key gc.input_convoy_id --all --include-ephemeral --limit 0 \
  || { echo "$PROG: could not list the beads that name an input convoy; nothing closed" >&2; exit 1; }

NOW=$(date -u +%s)
# One row per open synthetic input convoy: live (a non-closed bead names it),
# grace (younger than the window), finished (only closed beads name it), or
# unnamed (nothing names it).
jq -c -n --slurpfile cv "$TMP/convoys.json" --slurpfile nm "$TMP/namers.json" \
    --argjson now "$NOW" --argjson grace "$((GRACE_MIN * 60))" '
  def epoch: (. // "") | tostring | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch null);
  def cid: (.metadata["gc.input_convoy_id"] // "") | tostring;
  ([ $nm[0][] | select((.status // "") != "closed") | cid | select(. != "") ] | unique) as $live
  | ([ $nm[0][] | select((.status // "") == "closed") | {c: cid, id} | select(.c != "") ]
     | group_by(.c) | map({key: .[0].c, value: map(.id)}) | from_entries) as $closedby
  | $cv[0][]
  | select((.issue_type // "") == "convoy" and (.status // "") == "open")
  | select(((.metadata // {})["gc.synthetic"] // "") == "true")
  | select((.title // "") | startswith("input convoy for "))
  | select(((.labels // []) | index("owned")) == null)
  | .id as $me
  | (.created_at | epoch) as $born
  | ($closedby[$me] // []) as $roots
  | {id: $me,
     tracked: (([ .dependencies[]? | select(((.type // .dependency_type) // "") == "tracks")
                  | (.depends_on_id // "") | select(. != "") ] | first)
               // ((.title // "") | sub("^input convoy for "; ""))),
     roots: $roots,
     class: (if ($live | index($me)) != null then "live"
             elif $born == null or ($now - $born) < $grace then "grace"
             elif ($roots | length) > 0 then "finished"
             else "unnamed" end)}' > "$TMP/rows.jsonl" 2>/dev/null \
  || { echo "$PROG: could not classify the convoys; nothing closed" >&2; exit 1; }

count() { jq -s --arg c "$1" 'map(select(.class == $c)) | length' "$TMP/rows.jsonl"; }
N_LIVE=$(count live); N_GRACE=$(count grace); N_FIN=$(count finished); N_UNN=$(count unnamed)
N_ALL=$((N_LIVE + N_GRACE + N_FIN + N_UNN))
N_NAMERS=$(jq 'length' "$TMP/namers.json")
if [ "$N_ALL" -gt 0 ] && [ "$N_NAMERS" -eq 0 ]; then
  echo "$PROG: $N_ALL open input convoy(s) but no bead in this store names any input convoy; the workflow roots may live in another store, so nothing is closed" >&2
  exit 1
fi

: > "$TMP/closed-ids"
closed=0; failed=0
while IFS=$'\t' read -r id tracked class roots; do
  [ -n "${id:-}" ] || continue
  if [ "$class" = "finished" ]; then
    why="its workflow is closed ($roots)"
  else
    why="no workflow ever named it"
  fi
  if [ "$APPLY" -eq 0 ]; then
    echo "$PROG: would close $id (input convoy for $tracked): $why"
    continue
  fi
  if bdx close "$id" --reason "$PROG: no live bead names this input convoy as gc.input_convoy_id; $why" </dev/null >/dev/null 2>&1; then
    closed=$((closed + 1))
    printf '%s\n' "$id" >> "$TMP/closed-ids"
    echo "$PROG: closed $id (input convoy for $tracked): $why"
  else
    failed=$((failed + 1))
    echo "$PROG: close of $id was refused; left open for a re-run" >&2
  fi
done < <(jq -r 'select(.class == "finished" or .class == "unnamed")
                | [.id, .tracked, .class, (.roots | join(","))] | @tsv' "$TMP/rows.jsonl")

stuck=0
if [ "$APPLY" -eq 1 ] && [ "$closed" -gt 0 ]; then
  if bd_rows "$TMP/after.json" list --type=convoy --status=open --limit 0; then
    stuck=$(jq -n --slurpfile a "$TMP/after.json" --rawfile ids "$TMP/closed-ids" '
      ($ids | split("\n") | map(select(. != ""))) as $done
      | [ $a[0][] | select(.id as $i | ($done | index($i)) != null) ] | length' 2>/dev/null)
    case "$stuck" in
      ''|*[!0-9]*) stuck=0; echo "$PROG: could not compare the re-listing with the closes to confirm them" >&2 ;;
      0) ;;
      *) echo "$PROG: $stuck convoy(s) reported closed still list as open; re-run to retry" >&2 ;;
    esac
  else
    echo "$PROG: could not re-list open convoys to confirm the closes" >&2
  fi
  closed=$((closed - stuck))
fi

if [ "$APPLY" -eq 1 ]; then
  echo "$PROG: $((N_FIN + N_UNN)) dead ($N_FIN finished, $N_UNN never named): $closed closed, $((failed + stuck)) left open for a re-run; $N_LIVE live and $N_GRACE in the ${GRACE_MIN}m grace window left alone"
else
  echo "$PROG: $((N_FIN + N_UNN)) dead ($N_FIN finished, $N_UNN never named) would close; $N_LIVE live and $N_GRACE in the ${GRACE_MIN}m grace window left alone (dry run; --apply closes)"
fi
exit 0
