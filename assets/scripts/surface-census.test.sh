#!/usr/bin/env bash
# Behavior check for the surface-census oracle: it runs against this repo,
# emits the documented fields, and the entry-point breakdown partitions the
# source scripts exactly. The numbers themselves are not asserted — they move
# as the surface shrinks; the shape and the invariants do not.
#
# A final regression runs the oracle against a throwaway repo to pin one
# classification rule that this repo's moving numbers cannot: a source script
# named only from a skill is outside-startable, not a docs-only mention.
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

FIELDS="source_scripts source_lines outside_startable called_by_other_scripts docs_only unreferenced internal_only metadata_keys metadata_keys_bare metadata_keys_single_use duplicated_helpers drifted_helpers"
missing=""
for k in $FIELDS; do
  printf '%s' "$JSON" | jq -e --arg k "$k" 'has($k) and (.[$k]|type=="number")' >/dev/null 2>&1 || missing="$missing $k"
done
[ -z "$missing" ] && ok "all documented count fields present and numeric" || bad "missing or non-numeric fields:$missing"

neg=$(printf '%s' "$JSON" | jq -r '[to_entries[] | select((.value|type=="number") and ((.value < 0) or (.value != (.value|floor))))] | length')
[ "$neg" = 0 ] && ok "all numeric values are non-negative integers" || bad "$neg field(s) not a non-negative integer"

# The four entry-point classes partition the source scripts exactly, and
# internal_only is their called-by-other + unreferenced roll-up.
part_ok=$(printf '%s' "$JSON" | jq -r '(.outside_startable + .called_by_other_scripts + .docs_only + .unreferenced) == .source_scripts')
[ "$part_ok" = true ] \
  && ok "entry-point classes partition source_scripts exactly" \
  || bad "outside_startable + called_by_other_scripts + docs_only + unreferenced != source_scripts"

roll_ok=$(printf '%s' "$JSON" | jq -r '.internal_only == (.called_by_other_scripts + .unreferenced)')
[ "$roll_ok" = true ] \
  && ok "internal_only is the called-by-other + unreferenced roll-up" \
  || bad "internal_only != called_by_other_scripts + unreferenced"

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

# The namespace breakdown assigns every key to exactly one namespace, so its
# counts sum to the key total.
ns_ok=$(printf '%s' "$JSON" | jq -r '(([.metadata_namespaces[]] | add) // 0) == .metadata_keys')
[ "$ns_ok" = true ] \
  && ok "namespace breakdown sums to metadata_keys" \
  || bad "metadata_namespaces counts do not sum to metadata_keys"

# The emitted single-use list has one entry per single-use key.
sul_ok=$(printf '%s' "$JSON" | jq -r '(.metadata_single_use_keys | length) == .metadata_keys_single_use')
[ "$sul_ok" = true ] \
  && ok "single-use key list length matches its count" \
  || bad "metadata_single_use_keys length != metadata_keys_single_use"

# Drift is a subset of the duplicated helpers, and the named list matches the
# drift count.
drift_ok=$(printf '%s' "$JSON" | jq -r '(.drifted_helpers <= .duplicated_helpers) and ((.drifted_helper_names | length) == .drifted_helpers)')
[ "$drift_ok" = true ] \
  && ok "drift is a subset of duplicated, and its named list matches the count" \
  || bad "drifted_helpers exceeds duplicated_helpers or its list length is wrong"

bash "$CENSUS" "$ROOT" >/dev/null 2>&1 \
  && ok "human-readable mode exits 0" || bad "human-readable mode failed"

# Regression: a source script named only from a skill is outside-startable.
# Skills carry runnable instructions that start scripts by filename
# ("$CONV/foo.sh"), so a script reachable only through skills/ is startable from
# outside assets/scripts — not a docs-only mention. Census a throwaway repo whose
# one script is referenced nowhere but a SKILL.md and confirm its class. Without
# skills/ in the oracle's execution surface this lands in docs-only instead.
SKFIX=$(mktemp -d "${TMPDIR:-/tmp}/gctk-census-skills.XXXXXX")
(
  cd "$SKFIX" || exit 1
  git init -q
  mkdir -p assets/scripts skills/demo
  printf '#!/usr/bin/env bash\necho started\n' > assets/scripts/skill-started.sh
  printf '# Demo skill\n\nRun it:\n\n    "$CONV/skill-started.sh" --go\n' > skills/demo/SKILL.md
  git add -A
)
SKJSON=$(bash "$CENSUS" --json "$SKFIX" 2>/dev/null)
sk_ok=$(printf '%s' "$SKJSON" | jq -r '.source_scripts==1 and .outside_startable==1 and .docs_only==0 and .called_by_other_scripts==0 and .unreferenced==0' 2>/dev/null)
[ "$sk_ok" = true ] \
  && ok "a script referenced only from skills/ is counted outside-startable" \
  || bad "skills-only script not outside-startable (got $(printf '%s' "$SKJSON" | jq -c '{source_scripts,outside_startable,called_by_other_scripts,docs_only,unreferenced}' 2>/dev/null))"
rm -rf "$SKFIX"

echo
echo "surface-census: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
