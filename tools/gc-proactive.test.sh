#!/usr/bin/env bash
# Hermetic test for tools/gc-proactive.sh's live-intake stand-down (tk-amc65l.1).
#
# A live operator intake — gc-helm engage --new-subject — creates the subject
# MARKED gc.interactive_intake=1, files the ONE visit, and spawns the sitting
# itself. The proactive worker must stand down so a sweep does not file a SECOND
# visit for a conversation already under way. Two gates are covered here, both
# exercised through the fixture seam (GC_PROACTIVE_FIXTURE), so no live city,
# Dolt, or gc is needed:
#   (SCAN-DROP)  scan_precision_filter drops a marked bead from the candidate set
#   (SCAN-KEEP)  …while an unmarked raw input bead is still a candidate
#   (SLING-SKIP) sling refuses a marked bead as a no-op (exit RC_ALREADY_REACTED)
#                and names gc.interactive_intake, filing nothing
#   (SLING-GO)   …while an unmarked bead proceeds to the dispatch
#
# gc-proactive.sh is a bash script (process substitution), so it is invoked via
# bash, not sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-proactive.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-proactive-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-proactive.sh present" || bad "gc-proactive.sh missing at $SCRIPT"

# A fixture dir short-circuits every gc call: scan reads scan.json, the sling
# guard reads beads.json, and a sling that passes the guard prints a dry line
# rather than dispatching.
export GC_PROACTIVE_FIXTURE="$TMP"

# scan.json: one raw input bead (tk-plain) and one live-intake subject
# (tk-intake, marked). Both otherwise pass the precision filter (task type, has a
# description, unrouted, no reaction/takeaway markers, top-level).
cat > "$TMP/scan.json" <<'JSON'
[
  {"id":"tk-plain",  "issue_type":"task", "description":"a raw input bead",      "title":"plain input",     "metadata":{}},
  {"id":"tk-intake", "issue_type":"task", "description":"a live intake subject", "title":"intake subject",  "metadata":{"gc.interactive_intake":"1","gc.origin":"operator"}}
]
JSON

echo "# scan_precision_filter drops a live-intake subject, keeps a raw input"
IDS="$(bash "$SCRIPT" scan --json 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' ')"
has "$IDS" "tk-plain"  "(SCAN-KEEP) an unmarked raw input bead is still a candidate"
hasnt "$IDS" "tk-intake" "(SCAN-DROP) a marked live-intake subject is dropped from the scan"

# beads.json: the metadata the sling guard reads per bead.
cat > "$TMP/beads.json" <<'JSON'
{
  "tk-intake": {"metadata":{"gc.interactive_intake":"1","gc.origin":"operator"}},
  "tk-plain":  {"metadata":{}}
}
JSON

echo "# sling refuses a marked bead as a no-op, naming the marker"
set +e
OUT="$(bash "$SCRIPT" sling tk-intake 2>&1)"; RC=$?
set -e
eq "$RC" 3 "(SLING-SKIP) sling of a marked bead exits RC_ALREADY_REACTED (3)"
has "$OUT" "gc.interactive_intake=1" "(SLING-SKIP) …naming the marker"
has "$OUT" "file a second" "(SLING-SKIP) …and why (a second visit)"
hasnt "$OUT" "would sling" "(SLING-SKIP) …nothing dispatched"

echo "# an unmarked bead still proceeds to the dispatch"
set +e
OUT="$(bash "$SCRIPT" sling tk-plain 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(SLING-GO) sling of an unmarked bead exits 0"
has "$OUT" "would sling" "(SLING-GO) …and dispatches (fixture dry line)"

echo
echo "gc-proactive stand-down: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
