#!/usr/bin/env bash
# migrate-lane-states — one-shot ledger migration for the lane-state grammar.
# DISPOSABLE: delete this script once every store has been migrated.
# check.<lane> stopped carrying <verb>@<40-hex oid> and now carries one bare
# state word. Every reader changed with it, so an anchor still holding the old
# grammar reads as a lane no reader knows: merge.sh holds it, and gate-ensure
# dispatches a review against it every pass. This rewrites the standing markers.
#   green@<oid>     -> green
#   fixable@<oid>   -> fixing
#   exception@<oid> -> the marker is cleared and the anchor is parked under
#                      merge_hold, which is where the convergence cap's park
#                      lives now, plus one visit carrying the park's reason —
#                      closing a park silently removes a row from the board.
# Absent stays absent: that is the unreviewed lane, and it needs no write.
# RUN IT AFTER the code lands, never before: the old readers compare a marker
# to a head, so a bare `green` written under them settles nothing and the next
# verdict stamps the old grammar back.
# DEFAULT IS DRY-RUN: report what would change; --apply writes, every write is
# read back, and a second --apply run finds nothing to do.
# Usage: migrate-lane-states.sh [--apply] [--rig <name>]
# Exit: 0 migrated or nothing to do, 1 items need an operator.
set -u

PROG="migrate-lane-states"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ESCALATOR="$SCRIPTS_DIR/escalate.sh"
BOUND="${GC_MIGRATE_TIMEOUT:-60}"
VISIT_KEY="gate-park-migrated"

APPLY=0; ONLY_RIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --rig)   ONLY_RIG="${2:-}"; shift 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

RIG_DB=""
bd_show() { run_bounded gc bd show "$1" --json --db "$RIG_DB" 2>/dev/null | scrub; }
meta_of() { bd_show "$1" | jq -r --arg k "$2" '.[0].metadata[$k] // ""' 2>/dev/null; }

MODE="DRY-RUN (no writes; pass --apply to perform them)"
[ "$APPLY" -eq 1 ] && MODE="APPLY"
echo "$PROG — $MODE"

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
  echo "$PROG: \`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; nothing to migrate against" >&2
  exit 1
fi

total_attention=0
while IFS=$'\037' read -r rig_name rig_path suspended; do
  [ -n "$rig_path" ] || continue
  [ -z "$ONLY_RIG" ] || [ "$rig_name" = "$ONLY_RIG" ] || continue
  label="${rig_name:-<city>}"
  if [ "$suspended" = "true" ]; then
    echo "$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)"
    continue
  fi
  RIG_DB="$rig_path/.beads"
  echo "== rig $label ($RIG_DB) =="

  raw=$(run_bounded gc bd list --db "$RIG_DB" --status open \
    --has-metadata-key merge_result --json --limit 0 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
    echo "$label: could not list open anchors (rc=$rc) — this store was NOT migrated" >&2
    total_attention=$((total_attention + 1)); continue
  fi
  # One row per legacy marker: <id> <key> <old value> <new state> <blocked_reason>.
  # An `exception@` carries the empty new state; the park arm below recognises it.
  rows=$(printf '%s' "$raw" | scrub | jq -r '
      .[]? | (.metadata // {}) as $m
      | ((($m.merge_result // "") | tostring)) as $mr
      | select($mr == "pre_open_gate" or $mr == "pull_request")
      | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
      | ((($m.blocked_reason // "") | tostring | gsub("[[:cntrl:]]"; " "))) as $why
      | $m | to_entries[]
      | select(.key | test("^check\\.[^.]+$"))
      | select((.value | type) == "string")
      | (.value | gsub("[[:cntrl:]]"; " ")) as $v
      | (if   ($v | startswith("green@"))     then "green"
         elif ($v | startswith("fixable@"))   then "fixing"
         elif ($v | startswith("exception@")) then ""
         else null end) as $to
      | select($to != null)
      | [$id, .key, $v, $to, $why] | join("\u001f")' 2>/dev/null)
  if [ -z "$rows" ]; then
    echo "$label: no legacy gate markers; nothing to migrate"
    continue
  fi

  migrated=0; parked=0; attention=0
  while IFS=$'\037' read -r id key was to why; do
    [ -n "$id" ] || continue
    if [ -n "$to" ]; then
      # --- a verdict that survives, as a lane state ---------------------------
      if [ "$APPLY" -eq 0 ]; then
        echo "$label $id: would rewrite $key=\"$was\" -> $to"; migrated=$((migrated + 1)); continue
      fi
      run_bounded gc bd update "$id" --db "$RIG_DB" --set-metadata "$key=$to" \
        --append-notes "$PROG: $key=\"$was\" migrated to the lane state \"$to\". A lane state is a state of the lane; no reader compares it to a head." >/dev/null 2>&1
      got=$(meta_of "$id" "$key")
      if [ "$got" = "$to" ]; then
        migrated=$((migrated + 1)); echo "$label $id: $key=\"$was\" -> $to"
      else
        attention=$((attention + 1))
        echo "$label $id: $key did not read back as \"$to\" (has '${got:-<empty>}'); still legacy, retry" >&2
      fi
      continue
    fi

    # --- a park: the marker goes, merge_hold and a visit carry it -------------
    # Cleared and held in ONE write. Between a cleared marker and an unset hold
    # the anchor is an ordinary unreviewed lane, and one reconcile pass through
    # that gap buys the review this park exists to refuse.
    PARK_WHY="$why"
    [ -n "$PARK_WHY" ] || PARK_WHY="the review cap parked this anchor ($key was \"$was\")"
    if [ "$APPLY" -eq 0 ]; then
      echo "$label $id: would clear $key=\"$was\", set merge_hold, and file one visit [$VISIT_KEY]"
      parked=$((parked + 1)); continue
    fi
    run_bounded gc bd update "$id" --db "$RIG_DB" \
      --unset-metadata "$key" --set-metadata merge_hold=true \
      --append-notes "$PROG: $key=\"$was\" retired. The convergence cap's park is merge_hold now, and this anchor keeps it: $PARK_WHY" >/dev/null 2>&1
    got=$(meta_of "$id" "$key")
    hold=$(meta_of "$id" merge_hold)
    case "$hold" in ""|false|False|FALSE|0|null) hold="" ;; esac
    if [ -n "$got" ] || [ -z "$hold" ]; then
      attention=$((attention + 1))
      echo "$label $id: the park did not read back ($key='${got:-<cleared>}', merge_hold='${hold:-<unset>}'); the anchor is NOT parked, retry" >&2
      continue
    fi
    parked=$((parked + 1))
    if [ ! -x "$ESCALATOR" ]; then
      attention=$((attention + 1))
      echo "$label $id: parked under merge_hold but $ESCALATOR is missing; NO visit filed — file one by hand" >&2
      continue
    fi
    if "$ESCALATOR" --subject "$id" --key "$VISIT_KEY" \
         ${rig_name:+--pool "$rig_name/gc-toolkit.converse"} --message \
"The review cap's park on $id was carried across the lane-state migration and needs a person.

$PARK_WHY

The park used to be check.<gate>=exception@<head>, which a new commit cleared.
It is merge_hold now, which no commit clears: a lane state is a state of the
lane. Retire it with a ruling, which lifts the hold and re-baselines the round
floor in one write:
  assets/scripts/signoff.sh reset $id --reason '<ruling>'
Or reject the branch and let the anchor close the way any rejected work does." >/dev/null; then
      echo "$label $id: $key=\"$was\" -> merge_hold + visit [$VISIT_KEY]"
    else
      attention=$((attention + 1))
      echo "$label $id: parked under merge_hold but the visit did not file; the park stands with nothing on the board saying so — file one by hand" >&2
    fi
  done <<ROWS
$rows
ROWS

  echo "$label: $migrated lane state(s) migrated, $parked park(s) carried, $attention needing an operator"
  total_attention=$((total_attention + attention))
done <<SCOPES
$scopes
SCOPES

if [ "$total_attention" -gt 0 ]; then
  echo "$PROG: $total_attention item(s) need an operator; re-run once they are resolved" >&2
  exit 1
fi
exit 0
