#!/usr/bin/env bash
# Hermetic test for assets/scripts/liveness-classify.sh, the one liveness
# classifier. Covers:
#   (DEF)      sourcing the file exposes $LIVENESS_CLASSIFY_JQ, and with the defs
#              it builds on it classifies every ready bead, a bead held for
#              placement (placement.sh) among them
#   (CONV)     a bead a conversation tracks converses only while a live sitting
#              holds that conversation: one in the queue of the operator, a task
#              whose alias names another id, and a task tracking two beads hold
#              nothing
#   (GATE)     a bead whose blocks edge reaches an open human gate is held by
#              design, read from the not-closed listing; a gate of another type
#              holds nothing
#   (EMPTY)    each read beyond the bead set drops only what it names, so passed
#              empty it drops nothing; the precheck's superset rests on this
#   (LIVENESS) unreadable_liveness_covers decides whether a conversation a
#              sitting holds covers its subject when the session list was
#              unreadable
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

# shellcheck source=bd-lib.sh
. "$HERE/bd-lib.sh" || { echo "FAIL - cannot source bd-lib.sh" >&2; exit 1; }
# shellcheck source=conversation.sh
. "$HERE/conversation.sh" || { echo "FAIL - cannot source conversation.sh" >&2; exit 1; }
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
# the subject of a conversation a sitting holds, for the liveness policy, and
# the beads the conversation and gate arms must leave alone.
cat > "$TMP/ready.json" <<'JSON'
[
  {"id":"n-pr","title":"parked on an open PR","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://github.com/o/r/pull/7"}},
  {"id":"n-preopen","title":"pre-open, its one gate green","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"correctness"}},
  {"id":"n-worked","title":"a bead a convoy drives","issue_type":"bug"},
  {"id":"n-husk","title":"a step of a husk molecule","issue_type":"task"},
  {"id":"n-plain","title":"an ordinary idle bug","issue_type":"bug"},
  {"id":"n-subj","title":"the subject of a conversation a sitting holds","issue_type":"task"},
  {"id":"n-queue","title":"the subject of a conversation in the queue","issue_type":"task"},
  {"id":"n-foreign","title":"tracked by a task whose alias names another id","issue_type":"task"},
  {"id":"n-twin","title":"one of two beads a task tracks","issue_type":"task"},
  {"id":"n-gated","title":"blocked by a human gate filed after the ready read","issue_type":"task"},
  {"id":"n-timer","title":"blocked by a gate of another type","issue_type":"task"},
  {"id":"n-placement","title":"held for the placement sitting","issue_type":"bug","metadata":{"placement":"pending"}},
  {"id":"n-placed","title":"placed under an epic, its marker left behind","issue_type":"task","dependencies":[{"issue_id":"n-placed","depends_on_id":"e-1","type":"parent-child"}],"metadata":{"placement":"pending"}}
]
JSON
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"tk-cv1","title":"about n-subj","issue_type":"task","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.tk-cv1",
   "dependencies":[{"issue_id":"tk-cv1","depends_on_id":"n-subj","type":"tracks"}]},
  {"id":"tk-cq1","title":"about n-queue","issue_type":"task","status":"open","assignee":"human",
   "dependencies":[{"issue_id":"tk-cq1","depends_on_id":"n-queue","type":"tracks"}]},
  {"id":"tk-cf1","title":"about n-foreign","issue_type":"task","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.tk-other",
   "dependencies":[{"issue_id":"tk-cf1","depends_on_id":"n-foreign","type":"tracks"}]},
  {"id":"tk-c2","title":"about two beads","issue_type":"task","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.tk-c2",
   "dependencies":[{"issue_id":"tk-c2","depends_on_id":"n-twin","type":"tracks"},{"issue_id":"tk-c2","depends_on_id":"n-plain","type":"tracks"}]},
  {"id":"g-human","title":"a person owes this","issue_type":"gate","await_type":"human","await_id":"some-key","status":"open"},
  {"id":"g-timer","title":"a timer","issue_type":"gate","await_type":"timer","status":"open"},
  {"id":"n-gated","title":"blocked by a human gate filed after the ready read","issue_type":"task","status":"open",
   "dependencies":[{"issue_id":"n-gated","depends_on_id":"g-human","type":"blocks"}]},
  {"id":"n-timer","title":"blocked by a gate of another type","issue_type":"task","status":"open",
   "dependencies":[{"issue_id":"n-timer","depends_on_id":"g-timer","type":"blocks"}]}
]
JSON
cp "$TMP/live.json" "$TMP/alive.json"

# classify <openprs> <worked> <husks> <preopen_green>
#          <livesessions> <livenessknown> <unreadable_liveness_covers>
# Prints the classes as one sorted "id:class" list.
classify() {
    jq -nr --slurpfile ready "$TMP/ready.json" --slurpfile live "$TMP/live.json" --slurpfile alive "$TMP/alive.json" \
        --argjson openprs "$1" --argjson worked "$2" --argjson husks "$3" \
        --argjson preopen_green "$4" \
        --argjson livesessions "$5" --argjson livenessknown "$6" --argjson unreadable_liveness_covers "$7" \
        "$HUMAN_GATE_JQ$CONVERSATION_JQ$STANDING_KINDS_JQ$DISPATCH_PATH_JQ$PLACEMENT_JQ$LIVENESS_CLASSIFY_JQ"'[ liveness_classify[] | "\(.id):\(.class)" ] | sort | join(" ")'
}
class_of() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2://p"; }

echo "# the classifier"
SITTING='["gc-toolkit/gc-toolkit.tk-cv1"]'
ALL="$(classify '["https://github.com/o/r/pull/7"]' '["n-worked"]' '["n-husk"]' '{"n-preopen":true}' "$SITTING" true true)"
eq "$(printf '%s\n' "$ALL" | tr ' ' '\n' | grep -c .)" "13" "(DEF) one row per ready bead"
eq "$(class_of "$ALL" n-pr)" "gated" "(DEF) a bead whose PR is open is gated"
eq "$(class_of "$ALL" n-preopen)" "gated" "(DEF) a pre-open anchor whose gates are all green is gated"
eq "$(class_of "$ALL" n-worked)" "worked" "(DEF) a convoy-worked bead is worked"
eq "$(class_of "$ALL" n-husk)" "husk" "(DEF) a husk step is husk"
eq "$(class_of "$ALL" n-subj)" "conversing" "(CONV) the subject of a conversation a live sitting holds is conversing"
eq "$(class_of "$(classify '[]' '[]' '[]' '{}' '["tk-cv1"]' true true)" n-subj)" "conversing" \
   "(CONV) …whether the session list names its alias bare or qualified"
eq "$(class_of "$ALL" n-queue)" "unnamed" "(CONV) the subject of a conversation in the queue of the operator is not conversing"
eq "$(class_of "$ALL" n-foreign)" "unnamed" "(CONV) a task whose alias names another id is no conversation"
eq "$(class_of "$ALL" n-twin)" "unnamed" "(CONV) a task tracking two beads is no conversation"
eq "$(class_of "$ALL" n-gated)" "held-by-design" "(GATE) a bead an open human gate blocks is held by design"
eq "$(class_of "$ALL" n-timer)" "unnamed" "(GATE) a gate of another type holds nothing"
eq "$(class_of "$ALL" n-plain)" "unnamed" "(DEF) a bead nothing names is an unnamed wait"
eq "$(class_of "$ALL" n-placement)" "awaiting-placement" "(DEF) a bead held for the placement sitting is a named wait"
eq "$(class_of "$ALL" n-placed)" "unnamed" "(DEF) a bead placed under an epic waits on nothing the sitting owes, marker or not"

echo "# an empty read drops nothing"
NONE="$(classify '[]' '[]' '[]' '{}' "$SITTING" true true)"
for id in n-pr n-preopen n-worked n-husk n-plain; do
    eq "$(class_of "$NONE" "$id")" "unnamed" "(EMPTY) $id is unnamed when every read beyond the bead set is empty"
done
# A pre-open anchor the map leaves out, or names with anything but true, is not
# gated: the sweep proved none of its gates green.
eq "$(class_of "$(classify '[]' '[]' '[]' '{"n-preopen":false}' "$SITTING" true true)" n-preopen)" "unnamed" \
   "(EMPTY) a pre-open anchor the map does not name true stays an unnamed wait"

echo "# an unreadable session list"
eq "$(class_of "$(classify '[]' '[]' '[]' '{}' '[]' false true)" n-subj)" "conversing" \
   "(LIVENESS) unreadable_liveness_covers true keeps a held conversation covering"
eq "$(class_of "$(classify '[]' '[]' '[]' '{}' '[]' false false)" n-subj)" "unnamed" \
   "(LIVENESS) unreadable_liveness_covers false leaves the subject unnamed"
eq "$(class_of "$(classify '[]' '[]' '[]' '{}' '[]' true true)" n-subj)" "unnamed" \
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
COPY_RE='def (liveness_classify|conversation_held_live|human_side_on|machine_convoy|order_wisp|topology_kind|pre_open_all_green)[^a-z_]'
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
