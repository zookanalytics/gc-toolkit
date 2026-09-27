#!/usr/bin/env bash
# migrate-codex-to-correctness — one-shot ledger migration for the correctness
# rename. DISPOSABLE: delete this script once every store has been migrated.
#
# The standing correctness check was named `codex`; it is now `correctness`
# (`codex` named the tool, not the concern). An anchor still carrying the old
# name reads as a lane whose method the pack no longer declares: gate-ensure
# dispatches its review against review-dispatch-body's `*)` no-method fallback,
# and its board vocabulary names a retired tool. This rewrites the old name in
# place on three surfaces, keeping each anchor and its backing reviews consistent
# so no lane loses the green it earned:
#   check_set          the `codex` token -> `correctness` (the comma list is kept)
#   check.codex marker -> check.correctness (value copied, the old key unset)
#   review beads       check_name=codex -> correctness (open AND closed backings)
#
# Backing review beads are rewritten BEFORE the anchor's check_set, so an
# interrupted run leaves an anchor still naming `codex` beside a `correctness`
# backing — not green, merge held, picked up again next run — never a false green.
#
# RUN IT AFTER the code lands, never before: the old code still defaults an absent
# check_name to `codex`, so a bead rewritten under it is re-stamped `codex` by the
# next dispatch.
#
# DEFAULT IS DRY-RUN: it reports what would change; --apply writes, every write is
# read back, and a second --apply run finds nothing to do.
# Usage: migrate-codex-to-correctness.sh [--apply] [--rig <name>]
# Exit: 0 migrated or nothing to do, 1 items need an operator.
set -u

PROG="migrate-codex-to-correctness"
BOUND="${GC_MIGRATE_TIMEOUT:-60}"

APPLY=0; ONLY_RIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --rig)   ONLY_RIG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;/^set -u/d'; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

RIG_DB=""
bd_show() { run_bounded gc bd show "$1" --json --db "$RIG_DB" 2>/dev/null | scrub; }
meta_of() { bd_show "$1" | jq -r --arg k "$2" '.[0].metadata[$k] // ""' 2>/dev/null; }

# The comma list with the `codex` token rewritten to `correctness`, order kept.
rewrite_set() {
  printf '%s' "$1" | tr ',' '\n' \
    | awk '{ v=$0; gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); if (v=="codex") v="correctness"; print v }' \
    | sed '/^$/d' | paste -sd, -
}

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

attention=0
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

  # 1) Backing review beads first (open AND closed), so a rewritten anchor never
  #    outruns its backing. A review bead names the lane in check_name.
  reviews=$(run_bounded gc bd list --db "$RIG_DB" --status open,in_progress,blocked,closed \
    --metadata-field check_name=codex --json --limit 0 2>/dev/null | scrub)
  if printf '%s' "$reviews" | jq -e 'type == "array"' >/dev/null 2>&1; then
    for rid in $(printf '%s' "$reviews" | jq -r '.[]?.id // empty' 2>/dev/null); do
      if [ "$APPLY" -eq 0 ]; then
        echo "$label $rid: would set check_name codex -> correctness"; continue
      fi
      run_bounded gc bd update "$rid" --db "$RIG_DB" --set-metadata check_name=correctness >/dev/null 2>&1
      if [ "$(meta_of "$rid" check_name)" = "correctness" ]; then
        echo "$label $rid: check_name codex -> correctness"
      else
        attention=$((attention + 1)); echo "$label $rid: check_name did not read back as correctness; still legacy, retry" >&2
      fi
    done
  else
    echo "$label: review listing unreadable — its check_name beads were NOT migrated" >&2
    attention=$((attention + 1))
  fi

  # 2) Anchors: the check_set token and the stray check.codex marker.
  raw=$(run_bounded gc bd list --db "$RIG_DB" --status open,in_progress,blocked \
    --has-metadata-key check_set --json --limit 0 2>/dev/null | scrub)
  if ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$label: anchor listing unreadable — its check_set/markers were NOT migrated" >&2
    attention=$((attention + 1)); continue
  fi
  rows=$(printf '%s' "$raw" | jq -r '
      .[]? | (.metadata // {}) as $m | ((.id // "") | tostring) as $id
      | select($id != "")
      | ((($m.check_set // "") | tostring)) as $cs
      | (($cs | test("(^|,)[[:space:]]*codex[[:space:]]*(,|$)"))) as $cshit
      | (($m | has("check.codex"))) as $mkhit
      | select($cshit or $mkhit)
      | [$id, $cs, (($m["check.codex"] // "") | tostring), ($cshit|tostring), ($mkhit|tostring)] | join("\u001f")' 2>/dev/null)
  if [ -z "$rows" ]; then
    echo "$label: no anchor names the codex check; nothing to migrate"
    continue
  fi
  while IFS=$'\037' read -r id cs marker cshit mkhit; do
    [ -n "$id" ] || continue
    newset=$(rewrite_set "$cs")
    if [ "$APPLY" -eq 0 ]; then
      [ "$cshit" = "true" ] && echo "$label $id: would set check_set '$cs' -> '$newset'"
      [ "$mkhit" = "true" ] && echo "$label $id: would move check.codex='$marker' -> check.correctness"
      continue
    fi
    args=()
    [ "$cshit" = "true" ] && args+=(--set-metadata "check_set=$newset")
    if [ "$mkhit" = "true" ]; then
      args+=(--set-metadata "check.correctness=$marker" --unset-metadata "check.codex")
    fi
    run_bounded gc bd update "$id" --db "$RIG_DB" "${args[@]}" >/dev/null 2>&1
    ok=1
    if [ "$cshit" = "true" ] && [ "$(meta_of "$id" check_set)" != "$newset" ]; then ok=0; fi
    if [ "$mkhit" = "true" ] && { [ "$(meta_of "$id" 'check.correctness')" != "$marker" ] || [ -n "$(meta_of "$id" 'check.codex')" ]; }; then ok=0; fi
    if [ "$ok" -eq 1 ]; then
      echo "$label $id: migrated (check_set='$newset'${mkhit:+, marker moved})"
    else
      attention=$((attention + 1)); echo "$label $id: writes did not read back cleanly; still legacy, retry" >&2
    fi
  done <<< "$rows"
done <<< "$scopes"

if [ "$attention" -ne 0 ]; then
  echo "$PROG: $attention item(s) need attention (see stderr); re-run after resolving" >&2
  exit 1
fi
echo "$PROG: done"
exit 0
