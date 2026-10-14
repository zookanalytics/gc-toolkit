#!/usr/bin/env bash
# Hermetic test for assets/scripts/liveness-classify.sh, the one liveness
# classifier. Covers:
#   (DEF)      sourcing the file exposes $LIVENESS_CLASSIFY_JQ, and with the defs
#              it builds on it classifies every ready bead, a bead held for
#              placement (placement.sh) among them
#   (EMPTY)    each read beyond the bead set drops only what it names, so passed
#              empty it drops nothing; the precheck's superset rests on this
#   (LIVENESS) unreadable_liveness_covers decides whether a claimed visit covers
#              its subject when the session list was unreadable
#   (READERS)  liveness-sweep.sh and liveness-sweep-precheck.sh source this file
#              and apply $LIVENESS_CLASSIFY_JQ
#   (NO-COPY)  no other file in the pack defines a classifier def of its own
# A reader with a private classifier drifts silently: an exclusion added to one
# copy is missing from the other, and nothing fails. The class-by-class
# behavior lives in liveness-sweep.test.sh, and the precheck's agreement with
# the sweep in liveness-sweep-precheck.test.sh.
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/liveness-classify.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-liveness-classify-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=visit-identity.sh
. "$HERE/visit-identity.sh" || { echo "FAIL - cannot source visit-identity.sh" >&2; exit 1; }
# shellcheck source=standing-kinds.sh
. "$HERE/standing-kinds.sh" || { echo "FAIL - cannot source standing-kinds.sh" >&2; exit 1; }
# shellcheck source=dispatch-path.sh
. "$HERE/dispatch-path.sh" || { echo "FAIL - cannot source dispatch-path.sh" >&2; exit 1; }
# shellcheck source=placement.sh
. "$HERE/placement.sh" || { echo "FAIL - cannot source placement.sh" >&2; exit 1; }
# shellcheck source=liveness-classify.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${LIVENESS_CLASSIFY_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$LIVENESS_CLASSIFY_JQ" \
    || bad "(DEF) sourcing the file exposes \$LIVENESS_CLASSIFY_JQ"

# One ready bead for each read beyond the bead set, a control no read names,
# and the subject of a CLAIMED visit, for the liveness policy.
cat > "$TMP/ready.json" <<'JSON'
[
  {"id":"n-pr","title":"parked on an open PR","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://github.com/o/r/pull/7"}},
  {"id":"n-preopen","title":"pre-open, its one gate green","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"correctness","check.correctness":"green"}},
  {"id":"n-worked","title":"a bead a convoy drives","issue_type":"bug"},
  {"id":"n-husk","title":"a step of a husk molecule","issue_type":"task"},
  {"id":"n-plain","title":"an ordinary idle bug","issue_type":"bug"},
  {"id":"n-subj","title":"the subject of a claimed visit","issue_type":"task"},
  {"id":"n-placement","title":"held for the placement sitting","issue_type":"bug","metadata":{"placement":"pending"}},
  {"id":"n-placed","title":"placed under an epic, its marker left behind","issue_type":"task","dependencies":[{"issue_id":"n-placed","depends_on_id":"e-1","type":"parent-child"}],"metadata":{"placement":"pending"}}
]
JSON
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"v-claimed","title":"visit: n-subj","metadata":{"task_kind":"visit","gc.session_id":"s-1","gc.continuation_group":"n-subj"}}
]
JSON
cp "$TMP/live.json" "$TMP/alive.json"

# classify <openprs> <worked> <husks> <preopen_gates> <have_resolver>
#          <livesessions> <livenessknown> <unreadable_liveness_covers>
# Prints the classes as one sorted "id:class" list.
classify() {
    jq -nr --slurpfile ready "$TMP/ready.json" --slurpfile live "$TMP/live.json" --slurpfile alive "$TMP/alive.json" \
        --argjson openprs "$1" --argjson worked "$2" --argjson husks "$3" \
        --argjson preopen_gates "$4" --arg have_resolver "$5" \
        --argjson livesessions "$6" --argjson livenessknown "$7" --argjson unreadable_liveness_covers "$8" \
        "$VISIT_IDENTITY_JQ$STANDING_KINDS_JQ$DISPATCH_PATH_JQ$PLACEMENT_JQ$LIVENESS_CLASSIFY_JQ"'[ liveness_classify[] | "\(.id):\(.class)" ] | sort | join(" ")'
}
class_of() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2://p"; }

echo "# the classifier"
ALL="$(classify '["https://github.com/o/r/pull/7"]' '["n-worked"]' '["n-husk"]' '{"n-preopen":["correctness"]}' 1 '["s-1"]' true true)"
eq "$(printf '%s\n' "$ALL" | tr ' ' '\n' | grep -c .)" "8" "(DEF) one row per ready bead"
eq "$(class_of "$ALL" n-pr)" "gated" "(DEF) a bead whose PR is open is gated"
eq "$(class_of "$ALL" n-preopen)" "gated" "(DEF) a pre-open anchor whose gates are all green is gated"
eq "$(class_of "$ALL" n-worked)" "worked" "(DEF) a convoy-worked bead is worked"
eq "$(class_of "$ALL" n-husk)" "husk" "(DEF) a husk step is husk"
eq "$(class_of "$ALL" n-subj)" "conversing" "(DEF) the subject of a live-held visit is conversing"
eq "$(class_of "$ALL" n-plain)" "unnamed" "(DEF) a bead nothing names is an unnamed wait"
eq "$(class_of "$ALL" n-placement)" "awaiting-placement" "(DEF) a bead held for the placement sitting is a named wait"
eq "$(class_of "$ALL" n-placed)" "unnamed" "(DEF) a bead placed under an epic waits on nothing the sitting owes, marker or not"

echo "# an empty read drops nothing"
NONE="$(classify '[]' '[]' '[]' '{}' 1 '["s-1"]' true true)"
for id in n-pr n-preopen n-worked n-husk n-plain; do
    eq "$(class_of "$NONE" "$id")" "unnamed" "(EMPTY) $id is unnamed when every read beyond the bead set is empty"
done
# have_resolver "0" means the resolver never answered, and the pre-open arm then
# reads the anchor's own check_set. A caller that wants that arm to drop nothing
# passes "1" with an empty map.
eq "$(class_of "$(classify '[]' '[]' '[]' '{}' 0 '["s-1"]' true true)" n-preopen)" "gated" \
   "(EMPTY) with have_resolver 0 the pre-open arm falls back to the check_set"

echo "# an unreadable session list"
eq "$(class_of "$(classify '[]' '[]' '[]' '{}' 1 '[]' false true)" n-subj)" "conversing" \
   "(LIVENESS) unreadable_liveness_covers true keeps a claimed visit covering"
eq "$(class_of "$(classify '[]' '[]' '[]' '{}' 1 '[]' false false)" n-subj)" "unnamed" \
   "(LIVENESS) unreadable_liveness_covers false leaves the subject unnamed"
eq "$(class_of "$(classify '[]' '[]' '[]' '{}' 1 '[]' true true)" n-subj)" "unnamed" \
   "(LIVENESS) a readable list without the holder leaves the subject unnamed either way"

echo "# every reader sources the one classifier"
READERS="assets/scripts/liveness-sweep.sh
assets/scripts/liveness-sweep-precheck.sh"
for r in $READERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    grep -qE '^[[:space:]]*\.[[:space:]].*liveness-classify\.sh' "$f" \
        && ok "(READERS) $r sources liveness-classify.sh" \
        || bad "(READERS) $r sources liveness-classify.sh"
    grep -q 'LIVENESS_CLASSIFY_JQ' "$f" \
        && ok "(READERS) $r applies \$LIVENESS_CLASSIFY_JQ" \
        || bad "(READERS) $r applies \$LIVENESS_CLASSIFY_JQ"
done

echo "# no private copies"
# A copy is a jq def of the classifier or of one of its arms. Specs and
# generated renders are history and output, not readers.
COPY_RE='def (liveness_classify|holder_live|machine_convoy|order_wisp|topology_kind|pre_open_all_green)[^a-z_]'
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/liveness-classify.test.sh") continue ;; esac
        COPIES="$COPIES ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$COPY_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside liveness-classify.sh defines a classifier def"

echo
echo "liveness-classify: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
