#!/usr/bin/env bash
# Hermetic test: one witness patrol cycle gives back a visit whose sitting is
# gone, and the next cycle does not find it again.
#
# engage binds a visit to the sitting it spawns by that sitting's runtime name,
# while the visit is still open and before the sitting starts. A create that
# fails leaves the binding behind. A sitting that started and whose session then
# closed leaves its claim behind: the visit in_progress, its alias as assignee,
# gc.session_id and gc.session_name pinned. Gas City frees neither, because
# every release it runs keeps a claim routed to human
# (docs/gascity/human-engagement.md), and the helm board reads both visits as
# engaged. The witness's orphan recovery is what gives them back.
#
# This test runs recover-orphaned-beads the way the witness runs it: the
# candidate-pipeline, liveness-map-guard and liveness-lookup blocks extracted
# verbatim from mol-witness-patrol.toml, the classification by the dead states
# the step names, and the real orphan-dispose.sh for each orphan. It asserts:
#   * every gone sitting's visit is released, with the route, continuation
#     group and task_kind kept and the gone-sitting headline written, and the
#     board's engagedVisit rule then reads each as parked;
#   * a visit whose binding carries a byte the listing's control-character
#     strip removes is released all the same, so its dead claim is not skipped
#     every cycle as a changed one;
#   * a visit whose sitting is still starting, and one a live sitting holds,
#     are left alone;
#   * a human-gated work bead naming a dead session is never a candidate;
#   * the next cycle finds none of the released visits, so none is recovered
#     twice;
#   * a visit engage re-binds to a fresh sitting after the listing keeps that
#     binding, because each orphan is handed over with the claim its row
#     listed.
#
# No live city, Dolt, network, or sessions — stubs from test-harness.sh only.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
SCRIPT="$HERE/orphan-dispose.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-witness-visit-recovery-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# --- Extract the REAL blocks from the formula. -------------------------------
extract() {
  awk -v tag="$1" '
    $0 ~ ("# >>> " tag "$") {f=1; next}
    $0 ~ ("# <<< " tag "$") {f=0}
    f' "$TOML"
}
for tag in candidate-pipeline liveness-map-guard liveness-lookup; do
  extract "$tag" > "$TMP/$tag.sh"
  if [ -s "$TMP/$tag.sh" ] && bash -n "$TMP/$tag.sh"; then
    ok "$tag extracted from the formula and parses"
  else
    bad "$tag extraction EMPTY or unparseable — markers missing from $TOML"
  fi
done

# --- The rig: visits in each state a sitting can leave them in. ---------------
# gc-bound       bound to a sitting whose failed create closed its row
# gc-bound-open  bound to a sitting whose failed create is still an open row
# gc-claimed     claimed by a sitting whose session has since closed
# gc-del         bound to a gone sitting under a name that carries a DEL
# gc-starting    bound to a sitting the reconciler has not started yet
# gc-live        claimed by a live sitting
# gc-parked      parked on the board, held by nobody
# tk-gated       a work bead on a human gate, still naming its dead polecat
fixture() {
  store '[
    {"id":"gc-bound","status":"open","assignee":"s-lx-wisp-tjt3y","title":"visit: gc-ycww6 — a question",
     "metadata":{"task_kind":"visit","gc.routed_to":"human","gc.continuation_group":"gc-ycww6"}},
    {"id":"gc-del","status":"open","assignee":"s-lx-wisp-de\u007fl","title":"visit: gc-7del — a question",
     "metadata":{"task_kind":"visit","gc.routed_to":"human","gc.continuation_group":"gc-7del"}},
    {"id":"gc-bound-open","status":"open","assignee":"s-lx-wisp-12neh","title":"visit: gc-2ddu7 — a question",
     "metadata":{"task_kind":"visit","gc.routed_to":"human","gc.continuation_group":"gc-2ddu7"}},
    {"id":"gc-claimed","status":"in_progress","assignee":"gascity/gc-toolkit.gc-claimed","title":"visit: gc-3abc — a question",
     "metadata":{"task_kind":"visit","gc.routed_to":"human","gc.continuation_group":"gc-3abc",
                 "gc.session_id":"lx-wisp-gone","gc.session_name":"s-lx-wisp-gone"}},
    {"id":"gc-starting","status":"open","assignee":"s-lx-wisp-new","title":"visit: gc-4abc — a question",
     "metadata":{"task_kind":"visit","gc.routed_to":"human","gc.continuation_group":"gc-4abc"}},
    {"id":"gc-live","status":"in_progress","assignee":"gascity/gc-toolkit.gc-live","title":"visit: gc-5abc — a question",
     "metadata":{"task_kind":"visit","gc.routed_to":"human","gc.continuation_group":"gc-5abc",
                 "gc.session_id":"lx-wisp-live","gc.session_name":"s-lx-wisp-live"}},
    {"id":"gc-parked","status":"open","assignee":"","title":"visit: gc-6abc — a question",
     "metadata":{"task_kind":"visit","gc.routed_to":"human","gc.continuation_group":"gc-6abc"}},
    {"id":"tk-gated","status":"open","assignee":"","title":"a work bead on a merge gate",
     "metadata":{"gc.routed_to":"human","gc.session_id":"lx-dead","branch":"polecat/tk-gated"}}
  ]'
  : > "$STUB_GC_LOG"
}
# gc session list omits a closed session, so lx-wisp-tjt3y, lx-wisp-gone and
# lx-dead are absent. An open failed-create row is listed under that state.
cat > "$TMP/sessions.json" <<'JSON'
{"ok":true,"sessions":[
  {"id":"lx-wisp-live","alias":"gascity/gc-toolkit.gc-live","session_name":"s-lx-wisp-live","state":"active"},
  {"id":"lx-wisp-new","alias":"gascity/gc-toolkit.gc-starting","session_name":"s-lx-wisp-new","state":"start-pending"},
  {"id":"lx-wisp-12neh","session_name":"s-lx-wisp-12neh","state":"failed-create"},
  {"id":"lx-witness","alias":"gascity/gc-toolkit.witness","session_name":"gascity--witness","state":"active"}
]}
JSON
export STUB_SESSIONS="$TMP/sessions.json"

# bd writes JSON with Go's encoder, which emits DEL raw where the stub's jq
# escapes it. A gc in front of the harness's puts the raw byte back in what bd
# reads print, so the listing's strip meets it the way it does in a city.
DEL="$(printf '\177')"
mkdir -p "$TMP/raw-del-bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'NEXT=%q\nDEL=%q\n' "$TMP/bin/gc" "$DEL"; cat; } > "$TMP/raw-del-bin/gc" <<'STUB'
case "${1:-} ${2:-}" in
  "bd list"|"bd show")
    out=$("$NEXT" "$@"); rc=$?
    printf '%s\n' "$out" | sed "s/\\\\u007f/$DEL/g"
    exit "$rc" ;;
esac
exec "$NEXT" "$@"
STUB
chmod +x "$TMP/raw-del-bin/gc"
export PATH="$TMP/raw-del-bin:$PATH"

# patrol_pass [<jq>] — one recover-orphaned-beads pass over the stub store.
# Prints one `<bead> <state> <result>` line per candidate, sorted: the state the
# lookup resolved for its owner, and orphan-dispose.sh's result for an orphan,
# or `owned` for a bead whose owner is not dead. The dead states are the ones
# the step's classification names; the lookup's own `dead` definition names the
# same set except `absent`. Each orphan is handed over with the claim from its
# row, as part 5's call hands it. A <jq> is another writer's change, landed on
# the store after the listing and before the first disposal.
patrol_pass() {
  local map rows bead owner claim state result
  map=$(bash -c 'source "$0"; [ -z "$MAP_TRIP" ] || exit 1; printf "%s" "$LIVENESS_MAP"' \
    "$TMP/liveness-map-guard.sh" 2>/dev/null) || { echo "MAP_TRIP"; return; }
  rows=$(bash "$TMP/candidate-pipeline.sh" 2>/dev/null)
  if [ -n "${1:-}" ]; then
    jq -c "$1" "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
  fi
  while read -r bead owner claim; do
    [ -n "$bead" ] || continue
    state=$(LIVENESS_MAP="$map" OWNER="$owner" bash -c 'source "$0"; printf "%s" "$STATE"' \
      "$TMP/liveness-lookup.sh" 2>/dev/null)
    case "$state" in
      archived|closed|failed-create|absent)
        result=$("$SCRIPT" "$bead" --claim "$claim" --apply --json 2>/dev/null \
          | jq -r '.result // "unread"') ;;
      *) result=owned ;;
    esac
    printf '%s %s %s\n' "$bead" "$state" "$result"
  done <<< "$rows"
}

# The call part 5 makes is the one patrol_pass makes: the claim from the row.
has "$(grep -F 'DISPOSE_JSON=$("$OD" <bead>' "$TOML")" '--claim "$CLAIM" --apply --json' \
  "part 5's disposal call hands over the claim from the row"

# The headline a released visit parks under, read from the disposal's fence.
GONE_TAKEAWAY="$(awk '/^# >>> gone-sitting-takeaway$/ {f = 1; next} /^# <<< gone-sitting-takeaway$/ {f = 0} f' "$SCRIPT" \
  | sed -n 's/^GONE_SITTING_TAKEAWAY="\(.*\)"$/\1/p')"

# board_reads <bead> — what the helm board's engagedVisit rule
# (services/helm/internal/board/derive.go) makes of a visit: engaged when it is
# in_progress, or not closed with a session (gc.session_name) or an assignee
# bound to it; parked when it stands open with neither.
board_reads() {
  jq -r --arg id "$1" '.[] | select(.id == $id)
    | if .status == "in_progress" then "engaged"
      elif .status != "closed" and ((.metadata["gc.session_name"] // "") != "" or (.assignee // "") != "") then "engaged"
      elif .status == "open" then "parked"
      else .status end' "$STUB_STORE"
}

fixture
for id in gc-bound gc-bound-open gc-claimed gc-del; do
  eq "$(board_reads "$id")" "engaged" "(premise) before the patrol the board reads $id as engaged"
done
eq "$(bash "$TMP/candidate-pipeline.sh" 2>/dev/null | awk '$1 == "gc-del" {print $2 " " $3}')" \
   "s-lx-wisp-del s-lx-wisp-del:open:s-lx-wisp-del" \
   "(premise) the listing reads gc-del's binding without the DEL the store holds"

echo "--- one patrol cycle ---"
eq "$(patrol_pass | sort | paste -sd ',' -)" \
   "gc-bound absent disposed,gc-bound-open failed-create disposed,gc-claimed absent disposed,gc-del absent disposed,gc-live active owned,gc-starting start-pending owned" \
   "the cycle releases the four visits whose sitting is gone, and leaves the starting and the live sitting's visits"
hasnt "$(cat "$STUB_GC_LOG")" "update tk-gated" "the human-gated work bead is never written"
hasnt "$(cat "$STUB_GC_LOG")" "update gc-parked" "the parked visit is never written"
hasnt "$(cat "$STUB_GC_LOG")" "update gc-live" "the live sitting's visit is never written"
hasnt "$(cat "$STUB_GC_LOG")" "update gc-starting" "the starting sitting's visit is never written"

for id in gc-bound gc-bound-open gc-claimed gc-del; do
  eq "$(board_reads "$id")" "parked" "after one cycle the board reads $id as parked"
  eq "$(bassignee "$id")" "" "$id names no assignee"
  eq "$(meta "$id" gc.session_id)$(meta "$id" gc.session_name)" "<absent><absent>" "$id carries no session pin"
  eq "$(meta "$id" gc.routed_to)" "human" "$id keeps its route to the board"
  eq "$(meta "$id" task_kind)" "visit" "$id is still a visit"
  eq "$(meta "$id" gc.takeaway)" "$GONE_TAKEAWAY" "$id parks under the gone-sitting headline"
done
eq "$(meta gc-bound gc.continuation_group)" "gc-ycww6" "the bound visit keeps its continuation group"
eq "$(meta gc-claimed gc.continuation_group)" "gc-3abc" "the claimed visit keeps its continuation group"
eq "$(board_reads gc-live)" "engaged" "the live sitting's visit still reads engaged"
eq "$(board_reads gc-starting)" "engaged" "the starting sitting's visit still reads engaged"

echo "--- the next cycle ---"
: > "$STUB_GC_LOG"
eq "$(patrol_pass | sort | paste -sd ',' -)" \
   "gc-live active owned,gc-starting start-pending owned" \
   "the next cycle finds none of the released visits"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "the next cycle writes nothing"

echo "--- a visit engage re-binds after the listing ---"
# engage reclaims a visit bound to a gone sitting and binds a fresh one, and it
# can do that after this cycle listed the visit and found its sitting gone. The
# disposal is handed the claim the row listed, so it leaves the fresh binding
# alone and reports a skip, which the patrol records as no recovery.
fixture
eq "$(patrol_pass 'map(if .id == "gc-bound" then .assignee = "s-lx-wisp-fresh" else . end)' | sort | paste -sd ',' -)" \
   "gc-bound absent skipped,gc-bound-open failed-create disposed,gc-claimed absent disposed,gc-del absent disposed,gc-live active owned,gc-starting start-pending owned" \
   "the visit re-bound after the listing is skipped, and the cycle releases the others"
eq "$(bassignee gc-bound)" "s-lx-wisp-fresh" "the fresh binding survives the cycle"
eq "$(grep -c -E '^bd update gc-bound ' "$STUB_GC_LOG")" "0" "the re-bound visit takes no write"
eq "$(meta gc-bound gc.takeaway)" "<absent>" "and no headline is written over it"

echo
echo "witness-visit-recovery: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
