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
#                      merge_hold=signoff_cap (+ signoff_cap=<gate>), which is
#                      where the convergence cap's park lives now, plus one
#                      visit carrying the park's reason — closing a park
#                      silently removes a row from the board.
# Only check.<g> keys named in the anchor's own check_set are touched — a
# marker outside it governs nothing and nothing (not even this migration)
# rewrites it; it is reported and left for gate-ensure's stray-marker sweep.
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
  raw=$(printf '%s' "$raw" | scrub)
  if [ "$rc" -ne 0 ] || [ -z "$raw" ] || ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$label: listing unparseable — this store was NOT migrated" >&2
    total_attention=$((total_attention + 1)); continue
  fi
  # One row per legacy marker: <id> <key> <old value> <new state> <blocked_reason> <declared>.
  # An `exception@` carries the empty new state; the park arm below recognises it.
  # <declared> is "1" when the key names a gate in the anchor's own check_set,
  # "0" otherwise — an undeclared key is reported, never rewritten or parked.
  rows=$(printf '%s' "$raw" | jq -r '
      .[]? | (.metadata // {}) as $m
      | ((($m.merge_result // "") | tostring)) as $mr
      | select($mr == "pre_open_gate" or $mr == "pull_request")
      | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
      | ((($m.blocked_reason // "") | tostring | gsub("[[:cntrl:]]"; " "))) as $why
      | ((($m.check_set // "") | tostring | gsub("[[:space:]]"; ""))) as $csflat
      | (",\($csflat),") as $declared
      | $m | to_entries[]
      | select(.key | test("^check\\.[^.]+$"))
      | select((.value | type) == "string")
      | (.value | gsub("[[:cntrl:]]"; " ")) as $v
      | (if   ($v | startswith("green@"))     then "green"
         elif ($v | startswith("fixable@"))   then "fixing"
         elif ($v | startswith("exception@")) then ""
         else null end) as $to
      | select($to != null)
      | (.key | sub("^check\\."; "")) as $g
      | (if ($declared | contains(",\($g),")) then "1" else "0" end) as $decl
      | [$id, .key, $v, $to, $why, $decl] | join("\u001f")' 2>/dev/null)
  if [ -z "$rows" ]; then
    echo "$label: no legacy gate markers; nothing to migrate"
    continue
  fi

  migrated=0; parked=0; undeclared=0; attention=0
  while IFS=$'\037' read -r id key was to why decl; do
    [ -n "$id" ] || continue
    gate="${key#check.}"

    if [ "$decl" != "1" ]; then
      # check_set does not name this gate: no reader dispatches or merges
      # against it, and nothing here may rewrite it either. gate-ensure's
      # stray-marker sweep (or a hand unset) retires it; this is not our call.
      undeclared=$((undeclared + 1))
      echo "$label $id: $key=\"$was\" names a gate outside check_set; left as an undeclared legacy marker for gate-ensure's sweep (or a hand unset)"
      continue
    fi

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

    # --- a park: the marker goes, merge_hold=signoff_cap and a visit carry it -
    # The visit is filed FIRST, before the marker is touched: escalate.sh
    # dedups on --subject/--key, so a retried call after a partial failure
    # files nothing twice, and a park write that then fails (or is never
    # reached) leaves the legacy marker standing for the next run to pick
    # this row up again from here — never a hold with nothing on the board,
    # and never a re-run that duplicates the visit once the park has landed.
    PARK_WHY="$why"
    [ -n "$PARK_WHY" ] || PARK_WHY="the review cap parked this anchor ($key was \"$was\")"
    if [ "$APPLY" -eq 0 ]; then
      if [ -z "$rig_name" ]; then
        echo "$label $id: would need an operator to file the visit by hand (city scope has no rig-qualified converse pool); would NOT clear $key or park automatically" >&2
        attention=$((attention + 1)); continue
      fi
      echo "$label $id: would file visit [$VISIT_KEY], then clear $key=\"$was\" and set merge_hold=signoff_cap signoff_cap=$gate"
      parked=$((parked + 1)); continue
    fi
    if [ ! -x "$ESCALATOR" ]; then
      attention=$((attention + 1))
      echo "$label $id: $ESCALATOR is missing; NOT parked, no visit filed — file one by hand and retry" >&2
      continue
    fi
    if [ -z "$rig_name" ]; then
      # No rig-qualified pool exists at city scope, and GC_RIG has nothing to
      # be set to here. Rather than guess a store, leave the legacy marker
      # standing and ask a person to file the visit and park by hand.
      attention=$((attention + 1))
      echo "$label $id: city-scope park needs an operator — no rig to route the visit through ($PARK_WHY); NOT parked, legacy marker left in place — file by hand" >&2
      continue
    fi
    # GC_RIG picked explicitly, not inherited: GC_RIG outranks --pool inside
    # escalate.sh, so an exported GC_RIG from the caller's shell (gc-helm
    # shells and agent sessions export it) would otherwise steer the visit
    # into the wrong rig's store, or refuse it as cross-rig, regardless of
    # --pool. Pinning it to the rig this iteration is walking keeps the two
    # in agreement, the same way a rig-qualified --pool alone cannot.
    if ! GC_RIG="$rig_name" "$ESCALATOR" --subject "$id" --key "$VISIT_KEY" \
         --pool "$rig_name/gc-toolkit.converse" --message \
"The review cap's park on $id was carried across the lane-state migration and needs a person.

$PARK_WHY

The park used to be check.<gate>=exception@<head>, which a new commit cleared.
It is merge_hold=signoff_cap now, which no commit clears: a lane state is a
state of the lane. Retire it with a ruling, which lifts the hold and
re-baselines the round floor in one write:
  assets/scripts/signoff.sh reset $id --reason '<ruling>'
Or reject the branch and let the anchor close the way any rejected work does." >/dev/null; then
      attention=$((attention + 1))
      echo "$label $id: visit [$VISIT_KEY] did not file; NOT parked, legacy marker left in place for the next run" >&2
      continue
    fi
    run_bounded gc bd update "$id" --db "$RIG_DB" \
      --unset-metadata "$key" --set-metadata merge_hold=signoff_cap --set-metadata "signoff_cap=$gate" \
      --append-notes "$PROG: $key=\"$was\" retired. The convergence cap's park is merge_hold=signoff_cap now, and this anchor keeps it: $PARK_WHY" >/dev/null 2>&1
    got=$(meta_of "$id" "$key")
    hold=$(meta_of "$id" merge_hold)
    cap=$(meta_of "$id" signoff_cap)
    if [ -n "$got" ] || [ "$hold" != "signoff_cap" ] || [ -z "$cap" ]; then
      attention=$((attention + 1))
      echo "$label $id: visit [$VISIT_KEY] is filed but the park did not read back ($key='${got:-<cleared>}', merge_hold='${hold:-<unset>}', signoff_cap='${cap:-<empty>}'); legacy marker left in place — the next run retries the write, and the visit will not duplicate" >&2
      continue
    fi
    parked=$((parked + 1))
    echo "$label $id: $key=\"$was\" -> merge_hold=signoff_cap signoff_cap=$gate + visit [$VISIT_KEY]"
  done <<ROWS
$rows
ROWS

  echo "$label: $migrated lane state(s) migrated, $parked park(s) carried, $undeclared undeclared marker(s) left for gate-ensure, $attention needing an operator"
  total_attention=$((total_attention + attention))
done <<SCOPES
$scopes
SCOPES

if [ "$total_attention" -gt 0 ]; then
  echo "$PROG: $total_attention item(s) need an operator; re-run once they are resolved" >&2
  exit 1
fi
exit 0
