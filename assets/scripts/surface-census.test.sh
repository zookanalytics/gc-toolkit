#!/usr/bin/env bash
# Behavior check for the surface-census oracle: it runs against this repo,
# emits the nine documented integer fields, and the entry-point breakdown
# partitions the source scripts exactly. The numbers themselves are not
# asserted — they move as the surface shrinks; the shape and the invariants do
# not.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
CENSUS="$HERE/surface-census.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -x "$CENSUS" ] || { echo "missing or non-executable $CENSUS" >&2; exit 1; }

JSON=$(bash "$CENSUS" --json "$ROOT" 2>/dev/null) || { echo "census --json exited non-zero" >&2; exit 1; }

printf '%s' "$JSON" | jq -e . >/dev/null 2>&1 \
  && ok "emits valid JSON" || bad "output is not valid JSON"

FIELDS="source_scripts source_lines outside_startable docs_only internal_only metadata_keys metadata_keys_bare metadata_keys_single_use drifted_helpers"
missing=""
for k in $FIELDS; do
  printf '%s' "$JSON" | jq -e --arg k "$k" 'has($k) and (.[$k]|type=="number")' >/dev/null 2>&1 || missing="$missing $k"
done
[ -z "$missing" ] && ok "all nine fields present and numeric" || bad "missing or non-numeric fields:$missing"

neg=$(printf '%s' "$JSON" | jq -r '[to_entries[] | select((.value|type=="number") and ((.value < 0) or (.value != (.value|floor))))] | length')
[ "$neg" = 0 ] && ok "all values are non-negative integers" || bad "$neg field(s) not a non-negative integer"

part_ok=$(printf '%s' "$JSON" | jq -r '(.outside_startable + .docs_only + .internal_only) == .source_scripts')
[ "$part_ok" = true ] \
  && ok "entry-point breakdown partitions source_scripts exactly" \
  || bad "outside_startable + docs_only + internal_only != source_scripts"

# Cross-check metric 1 against an independent count of the same set. That count
# includes surface-census.sh itself, so this also proves the oracle counts
# itself among the source scripts.
IND=$(git -C "$ROOT" ls-files 'assets/scripts/*.sh' | grep -vc '\.test\.sh$')
SRC=$(printf '%s' "$JSON" | jq -r '.source_scripts')
[ "$SRC" = "$IND" ] \
  && ok "source_scripts=$SRC matches an independent count (includes the oracle itself)" \
  || bad "source_scripts=$SRC != independent count=$IND"

sub_ok=$(printf '%s' "$JSON" | jq -r '(.metadata_keys_bare <= .metadata_keys) and (.metadata_keys_single_use <= .metadata_keys)')
[ "$sub_ok" = true ] \
  && ok "bare and single-use key counts are subsets of the key total" \
  || bad "bare or single-use exceeds metadata_keys"

bash "$CENSUS" "$ROOT" >/dev/null 2>&1 \
  && ok "human-readable mode exits 0" || bad "human-readable mode failed"

echo
echo "surface-census: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
