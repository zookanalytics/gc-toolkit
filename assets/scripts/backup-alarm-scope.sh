#!/usr/bin/env bash
# backup-alarm-scope.sh — keeps the deacon's backup alarms off a suspended rig.
#
# usage: backup-alarm-scope.sh databases [<health-json>]
#        backup-alarm-scope.sh payload <doctor-payload-file>
#
# Gas City's mol-dog-backup order backs up every bead scope except a suspended
# rig's, so that rig's backup ages by design. A suspended rig is one
# `gc rig list --json` reports as suspended.
#
# `databases` prints, one per line, the databases the deacon's manifest check
# scans: those in the health report, less each one that only suspended rigs name
# in .beads/metadata.json. <health-json> is that report; empty or absent, it
# asks `gc dolt health --json`. A health report that lists no database prints
# nothing and exits 1, and the check reads that as a finding.
#
# `payload` narrows the bd-backup-freshness result in a doctor sweep's payload,
# in place. Each clause of its message that names a suspended rig's scope goes,
# and a result with no clause left reads ok, so the sweep counts no finding and
# the patrol files none. Every other result stays as it is. Gas City's check
# itself is unchanged, and so is what `gc doctor` prints.
#
# A rig map that does not read leaves nothing out and names the reason on
# stderr, so an alarm that cannot tell still flags. GC_RIG_LIST_TIMEOUT bounds
# the read, here 60 seconds by default, because the deacon's tool call around
# either verb gets two minutes.
#
# Exit: 0 done · 1 no database listed, or a payload left as it was · 2 usage
set -uo pipefail

PROG="backup-alarm-scope"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { echo "usage: backup-alarm-scope.sh databases [<health-json>] | payload <doctor-payload-file>" >&2; exit 2; }

NARROWED=""
trap '[ -z "$NARROWED" ] || rm -f "$NARROWED"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

rig_map() { GC_RIG_LIST_TIMEOUT="${GC_RIG_LIST_TIMEOUT:-60}" "$HERE/rig-map.sh"; }

# A clause reads "scope <path>: ..." or "city: ...", the path relative to the
# city unless the scope sits outside it, and clauses join on "; ". A piece that
# opens neither way belongs to the clause before it.
NARROW_JQ='
def clauses:
  reduce split("; ")[] as $piece ([];
    if ($piece | startswith("scope ") or startswith("city:")) or length == 0
    then . + [$piece]
    else .[-1] += "; " + $piece
    end);
def scope_root($city):
  [capture("^scope (?<path>[^:]+):")] | .[0].path // empty
  | if startswith("/") then . else $city + "/" + . end;
($map.city_path // "") as $city
| [$map.rigs[] | select(.suspended == true) | .path] as $suspended
| .results |= map(
    if .name == "bd-backup-freshness" and .status != "ok" then
      ((.message // "") | clauses) as $all
      | [$all[] | select(any(scope_root($city); IN($suspended[])) | not)] as $kept
      | if ($kept | length) == ($all | length) then .
        elif ($kept | length) > 0 then .message = ($kept | join("; "))
        else .status = "ok"
          | .message = "every scope named belongs to a suspended rig, which the backup order skips by design"
          | del(.fix_hint)
        end
    else . end)'

cmd_databases() {
  local health="${1:-}" names map suspended="" running="" is_suspended path db name
  [ -n "$health" ] || health=$(gc dolt health --json)
  names=$(printf '%s' "$health" | jq -r '.databases[].name' 2>/dev/null)
  if [ -z "$names" ]; then
    echo "$PROG: the health report listed no databases" >&2
    return 1
  fi
  # Each store's name comes from the file Gas City's own doctor reads, so no bd
  # call reaches a store the backup order leaves cold.
  if map=$(rig_map); then
    while read -r is_suspended path; do
      db=$(jq -r '.dolt_database // empty' "$path/.beads/metadata.json" 2>/dev/null)
      [ -n "$db" ] || continue
      if [ "$is_suspended" = "true" ]; then suspended="$suspended $db "; else running="$running $db "; fi
    done < <(printf '%s' "$map" | jq -r '.rigs[] | "\(.suspended == true) \(.path)"')
  else
    echo "$PROG: the rig map did not read, so no suspended rig's database is left out" >&2
  fi
  printf '%s\n' "$names" | while IFS= read -r name; do
    case "$suspended" in
      *" $name "*) case "$running" in *" $name "*) ;; *) continue ;; esac ;;
    esac
    printf '%s\n' "$name"
  done
}

cmd_payload() {
  local payload="$1" map
  # A sweep with no such finding pays for no rig listing.
  jq -e 'any(.results[]?; .name == "bd-backup-freshness" and .status != "ok")' "$payload" >/dev/null 2>&1 || return 0
  if ! map=$(rig_map); then
    echo "$PROG: the rig map did not read, so $payload keeps every scope it names" >&2
    return 1
  fi
  if ! NARROWED=$(mktemp "$payload.XXXXXX"); then
    echo "$PROG: no scratch file beside $payload, so it keeps every scope it names" >&2
    return 1
  fi
  if ! jq --argjson map "$map" "$NARROW_JQ" "$payload" > "$NARROWED" 2>/dev/null \
    || ! jq -e '.results | type == "array"' "$NARROWED" >/dev/null 2>&1 \
    || ! mv "$NARROWED" "$payload"; then
    echo "$PROG: could not narrow $payload, so it keeps every scope it names" >&2
    return 1
  fi
}

case "$#:${1:-}" in
  1:databases) cmd_databases ;;
  2:databases) cmd_databases "$2" ;;
  2:payload) cmd_payload "$2" ;;
  *) usage ;;
esac
