#!/usr/bin/env bash
# migrate-approval-out-of-check-set — one-shot ledger migration for the approval
# relocation. DISPOSABLE: delete this script once every store has been migrated.
#
# `approval` was a check_set token that armed merge.sh's human-approval
# requirement. That requirement is now a UNIVERSAL merge rule — every PR needs a
# standing non-city APPROVED review, armed for every anchor — so the token
# arms nothing and names no lane. The resolver already drops it, so a stale token
# is harmless; this removes it so a check_set names only real lanes:
#   check_set  the `approval` token is dropped (the comma list and its order kept)
#
# An anchor whose ONLY token was `approval` becomes the gateless sentinel `none`,
# never an empty set: empty is "never normalized" and holds the merge, whereas
# `none` is the explicit no-lanes opt-out the old approval-only anchor meant. The
# universal rule still requires the approval either way.
#
# approval takes no check.approval marker and no review or finding bead, so unlike
# migrate-codex-to-correctness there is nothing else to rewrite — only the token.
#
# RUN IT AFTER the code lands: before it, merge.sh still reads the token to arm
# approval per-anchor, so removing it from an anchor that is NOT otherwise covered
# would drop the requirement. After it, the rule is universal and the token is
# inert.
#
# DEFAULT IS DRY-RUN: it reports what would change; --apply writes, every write is
# read back, and a second --apply run finds nothing to do.
# Usage: migrate-approval-out-of-check-set.sh [--apply] [--rig <name>]
# Exit: 0 migrated or nothing to do, 1 items need an operator.
set -u

PROG="migrate-approval-out-of-check-set"
BOUND="${GC_MIGRATE_TIMEOUT:-60}"

APPLY=0; ONLY_RIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    # `shift 2` with only one argument left is a no-op that returns non-zero in
    # bash, so `--rig` as the final argument would spin `while [ $# -gt 0 ]`
    # forever. Require the value explicitly.
    --rig)   [ $# -ge 2 ] || { echo "$PROG: --rig requires a value" >&2; exit 2; }
             ONLY_RIG="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;/^set -u/d'; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

RIG_DB=""
bd_show() { run_bounded gc bd show "$1" --json --db "$RIG_DB" 2>/dev/null | scrub; }
meta_of() { bd_show "$1" | jq -r --arg k "$2" '.[0].metadata[$k] // ""' 2>/dev/null; }

# The comma list with the `approval` token dropped, order kept; a list that held
# nothing else collapses to the `none` sentinel rather than to empty.
rewrite_set() {
  local out
  out=$(printf '%s' "$1" | tr ',' '\n' \
    | awk '{ v=$0; gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); if (tolower(v)=="approval") next; print v }' \
    | sed '/^$/d' | paste -sd, -)
  [ -n "$out" ] || out="none"
  printf '%s' "$out"
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

attention=0; matched_rig=0
while IFS=$'\037' read -r rig_name rig_path suspended; do
  [ -n "$rig_path" ] || continue
  [ -z "$ONLY_RIG" ] || [ "$rig_name" = "$ONLY_RIG" ] || continue
  # Past the filter with --rig set means this rig matched the requested name —
  # record it (even if suspended, below), so a --rig typo that matches nothing
  # fails loudly rather than printing "done" and exiting 0.
  [ -z "$ONLY_RIG" ] || matched_rig=1
  label="${rig_name:-<city>}"
  if [ "$suspended" = "true" ]; then
    echo "$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)"
    continue
  fi
  RIG_DB="$rig_path/.beads"
  echo "== rig $label ($RIG_DB) =="

  # Every live anchor carrying a check_set; the token can sit in deferred/hooked/
  # pinned exactly as in open, so the query spans the full live set. Closed anchors
  # are past gating and need no rewrite.
  raw=$(run_bounded gc bd list --db "$RIG_DB" --status open,in_progress,blocked,deferred,hooked,pinned \
    --has-metadata-key check_set --json --limit 0 2>/dev/null | scrub)
  if ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$label: anchor listing unreadable — its check_sets were NOT migrated" >&2
    attention=$((attention + 1)); continue
  fi
  rows=$(printf '%s' "$raw" | jq -r '
      .[]? | (.metadata // {}) as $m | ((.id // "") | tostring) as $id
      | select($id != "")
      | ((($m.check_set // "") | tostring)) as $cs
      | select($cs | ascii_downcase | test("(^|,)[[:space:]]*approval[[:space:]]*(,|$)"))
      | [$id, $cs] | join("\u001f")' 2>/dev/null)
  if [ -z "$rows" ]; then
    echo "$label: no anchor names the approval token; nothing to migrate"
    continue
  fi
  while IFS=$'\037' read -r id cs; do
    [ -n "$id" ] || continue
    newset=$(rewrite_set "$cs")
    if [ "$APPLY" -eq 0 ]; then
      echo "$label $id: would set check_set '$cs' -> '$newset'"; continue
    fi
    run_bounded gc bd update "$id" --db "$RIG_DB" --set-metadata "check_set=$newset" >/dev/null 2>&1
    if [ "$(meta_of "$id" check_set)" = "$newset" ]; then
      echo "$label $id: check_set '$cs' -> '$newset'"
    else
      attention=$((attention + 1)); echo "$label $id: check_set did not read back as '$newset'; still carries approval, retry" >&2
    fi
  done <<< "$rows"
done <<< "$scopes"

if [ -n "$ONLY_RIG" ] && [ "$matched_rig" -eq 0 ]; then
  echo "$PROG: --rig '$ONLY_RIG' matched no rig in \`gc rig list\`; nothing migrated (a typo looks like success otherwise)" >&2
  exit 1
fi
if [ "$attention" -ne 0 ]; then
  echo "$PROG: $attention item(s) need attention (see stderr); re-run after resolving" >&2
  exit 1
fi
echo "$PROG: done"
exit 0
