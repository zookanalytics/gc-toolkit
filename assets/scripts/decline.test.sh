#!/usr/bin/env bash
# Hermetic test for assets/scripts/decline.sh: work ends only with its record in
# place, so each part runs in order and a part that does not land stops the rest.
# A step ends with its run. A claim with no run, held on the work bead itself, is
# handed back with its route cleared when no gate holds it.
#
# No live city, Dolt or network: stubs of the scripts it calls, and of gc. The
# claim cases run the real hand-back.sh and the real run-cancel.sh over a gc stub
# that keeps the beads it is shown, so a decline that asks to cancel a run the
# claim does not have meets the guard that refuses it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-decline-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
PACK="$TMP/pack"; mkdir -p "$PACK" "$TMP/bin"
cp "$HERE/decline.sh" "$PACK/"
for pair in human-gate.sh:GATE:GATE_RC await-ruling.sh:AWAIT:AWAIT_RC run-cancel.sh:CANCEL:CANCEL_RC; do
  IFS=: read -r name word rc <<<"$pair"
  cat > "$PACK/$name" <<STUB
#!/usr/bin/env bash
printf '$word\n' >> "\$LOG"
printf '%s\n' "\$*" >> "\$ARGS.$word"
exit "\${$rc:-0}"
STUB
  chmod +x "$PACK/$name"
done
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1 $2" = "runtime drain-ack" ] && printf 'DRAIN\n' >> "$LOG"
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" LOG="$TMP/log" ARGS="$TMP/args"

run() {
  : > "$LOG"; rm -f "$ARGS".*
  OUT=$("$PACK/decline.sh" "$@" 2>&1); RC=$?
  TRACE=$(tr '\n' ' ' < "$LOG")
}
args() { cat "$ARGS.$1" 2>/dev/null; }
GATED=(--step mol.x --reason why --subject tk-w --key k1 --message "the message.")

run --step mol.x --reason why
eq "$RC" 0 "no gate: exits 0"
eq "$TRACE" "CANCEL DRAIN " "no gate: nobody is asked, the run ends and the session drains"
eq "$(args CANCEL)" "--step mol.x --reason why" "the cancel names the step and the reason"

run "${GATED[@]}"
eq "$TRACE" "GATE CANCEL DRAIN " "a gate with no formula: asks, then ends the run, with no wait"
eq "$(args GATE)" "--subject tk-w --key k1 --message the message." "the gate gets the message as given, and declares no quiet window"

run "${GATED[@]}" --formula mol-f
eq "$TRACE" "GATE AWAIT CANCEL DRAIN " "a gate with a formula: asks, waits, ends the run, drains"
eq "$(args AWAIT)" "tk-w --key k1 --formula mol-f" "the wait names the subject, the key and the formula"
has "$(args GATE)" "the message. Then clear this gate: tk-w waits on it, and clearing it re-slings tk-w." "the gate tells the person what clearing it does"
has "$(args GATE)" "To stand down instead, do not clear this gate: run $(cd "$PACK" && pwd)/stand-down.sh tk-w --key k1 --ruling '<why>'." "and how to stand down, under the gate's own key"

GATE_RC=1 run "${GATED[@]}" --formula mol-f
eq "$RC" 1 "a gate that does not land exits 1"
eq "$TRACE" "GATE " "and nothing follows it"
has "$OUT" "recorded no gate" "and it says so"
AWAIT_RC=1 run "${GATED[@]}" --formula mol-f
eq "$RC" 1 "a wait that does not land exits 1"
eq "$TRACE" "GATE AWAIT " "and the run is not cancelled"
CANCEL_RC=1 run "${GATED[@]}" --formula mol-f
eq "$RC" 1 "a cancel that does not land exits 1"
eq "$TRACE" "GATE AWAIT CANCEL " "and the session does not drain"
has "$OUT" "NOT draining" "and it says so"
GATE_RC=1 run "${GATED[@]}"
no "$OUT" "run-cancel" "a stop at the gate never names the cancel as tried"

for bad_args in "" "--step mol.x" "--reason why" "--step mol.x --reason why --subject tk-w" \
  "--step mol.x --reason why --key k" "--step mol.x --reason why --formula f" "--nope" "--step"; do
  # shellcheck disable=SC2086  # each case's words are the arguments
  run $bad_args
  eq "$RC" 2 "usage error for: ${bad_args:-no arguments}"
  eq "$TRACE" "" "and nothing runs for: ${bad_args:-no arguments}"
done

# --- A claim with no run --------------------------------------------------------
REAL="$TMP/real"; mkdir -p "$REAL" "$TMP/real-bin"
cp "$HERE/decline.sh" "$HERE/hand-back.sh" "$HERE/run-cancel.sh" "$HERE/bd-lib.sh" "$REAL/"
cp "$PACK/human-gate.sh" "$PACK/await-ruling.sh" "$REAL/"
BEADS="$TMP/beads.json"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/real-bin/gc" <<'GC'
# The beads this stub is shown live in $BEADS, an object keyed by id. A guarded
# update that matches applies its status, assignee and metadata edits there, the
# way bd applies one write whole.
case "$1 $2" in
  "hook current") printf '%s\n' "${FAKE_CURRENT:-}"; exit 0 ;;
  "bd show")
    jq -e --arg id "$3" 'has($id)' "$BEADS" >/dev/null 2>&1 \
      || { printf '{"error":"no issues found matching the provided IDs"}\n'; exit 1; }
    jq -c --arg id "$3" '[.[$id]]' "$BEADS"; exit 0 ;;
  "bd list") printf '[]\n'; exit 0 ;;
  "bd update")
    id="$3"; shift 3
    printf 'UPDATE\n' >> "$LOG"; printf '%s %s\n' "$id" "$*" >> "$ARGS.UPDATE"
    [ "${FAKE_UPDATE_RC:-0}" = 0 ] || exit "$FAKE_UPDATE_RC"
    prog='.'
    for a in "$@"; do
      case "$a" in
        --if-status=*)   [ "$(jq -r --arg id "$id" '.[$id].status // ""' "$BEADS")" = "${a#*=}" ] || exit 13 ;;
        --if-assignee=*) [ "$(jq -r --arg id "$id" '.[$id].assignee // ""' "$BEADS")" = "${a#*=}" ] || exit 13 ;;
      esac
    done
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*)       prog="$prog | .[\$id].status = \"${1#*=}\"" ;;
        --assignee=*)     prog="$prog | .[\$id].assignee = \"${1#*=}\"" ;;
        --set-metadata)   k="${2%%=*}"; v="${2#*=}"; prog="$prog | .[\$id].metadata[\"$k\"] = \"$v\""; shift ;;
        --unset-metadata) prog="$prog | del(.[\$id].metadata[\"$2\"])"; shift ;;
        --append-notes)   shift ;;
      esac
      shift
    done
    jq --arg id "$id" "$prog" "$BEADS" > "$BEADS.new" && mv "$BEADS.new" "$BEADS"; exit 0 ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$LOG"; exit 0 ;;
esac
printf 'GC %s\n' "$*" >> "$LOG"
exit 2
GC
chmod +x "$TMP/real-bin/gc"

# claim <status> <assignee> [<gc.step_ref>] -> one bead tk-w, routed to a pool,
# the way gc bd show prints it
claim() {
  jq -nc --arg st "$1" --arg as "$2" --arg ref "${3:-}" '{id: "tk-w", status: $st, assignee: $as,
    metadata: ({"gc.routed_to": "rig/pool", "gc.execution_routed_to": "rig/pool", "gc.session_id": "sess-me"}
               + (if $ref == "" then {} else {"gc.step_ref": $ref, "gc.root_bead_id": "r-gone"} end))}'
}
run_claim() { # <bead json> <decline args...>
  : > "$LOG"; rm -f "$ARGS".*
  jq -nc --argjson b "$1" '{($b.id): $b}' > "$BEADS"; shift
  OUT=$(PATH="$TMP/real-bin:$PATH" BEADS="$BEADS" GC_SESSION_ID=sess-me GC_SESSION_NAME=hq-me "$REAL/decline.sh" "$@" 2>&1); RC=$?
  TRACE=$(tr '\n' ' ' < "$LOG")
}
now() { jq -r --arg f "$1" '.["tk-w"] | if $f == "status" or $f == "assignee" then .[$f] else .metadata[$f] end // "" | tostring' "$BEADS"; }
HELD="$(claim in_progress sess-me)"
GATED_CLAIM=(--step mol.x --reason why --subject tk-w --key k1 --message "the message." --formula mol-f)

FAKE_CURRENT=tk-w run_claim "$HELD" --step mol.x --reason "why it ends"
eq "$RC" 0 "a claim with no run, no gate: exits 0"
eq "$TRACE" "UPDATE DRAIN " "a claim with no run, no gate: handed back in one write, then the session drains"
has "$(args UPDATE)" "--if-status=in_progress --if-assignee=sess-me --status=open --assignee=" "the write is guarded on this session's claim"
has "$(args UPDATE)" "--set-metadata gc.routed_to=" "the same write clears the route"
eq "$(now status)|$(now assignee)|$(now gc.routed_to)|$(now gc.session_id)" "open|||" "and reads back open, unassigned, unrouted, with no pin"
eq "$(now gc.execution_routed_to)" "rig/pool" "and the pool a re-sling pours to stays"
no "$OUT" "cannot identify" "a claim with no run never asks for a run's cancel"

FAKE_CURRENT=tk-w run_claim "$HELD" "${GATED_CLAIM[@]}"
eq "$RC" 0 "a claim with no run, with a gate: exits 0"
eq "$TRACE" "GATE AWAIT DRAIN " "a claim with no run, with a gate: asks, waits, drains, and cancels nothing"
eq "$(args UPDATE)" "" "and writes no hand-back, since the wait released the claim"

FAKE_CURRENT=tk-w run_claim "$(claim closed sess-me)" --step mol.x --reason why
eq "$RC" 0 "a claim whose bead is closed: exits 0"
eq "$TRACE" "DRAIN " "and there is nothing to hand back, so the session only drains"

# A caller that waits on a sibling (work-setup.sh) or a blocker (work-gate.sh)
# before it declines with no gate: its wait has released the claim and cleared
# the route and pins, and armed the re-sling, while gc hook current still names
# the bead.
RELEASED=$(jq -nc '{id: "tk-w", status: "open", assignee: "", metadata: {"gc.routed_to": "",
  "gc.execution_routed_to": "rig/pool", "gc.dispatch_when_ready": "rig/pool", "resling_target": "rig/pool"}}')
FAKE_CURRENT=tk-w run_claim "$RELEASED" --step mol.x --reason why
eq "$RC|$TRACE" "0|UPDATE DRAIN " "a claim its own wait released, no gate: the hand-back finds it unclaimed, and the session drains"
has "$(args UPDATE)" "--if-status=open --if-assignee= --status=open" "the write is guarded on the bead holding no claim"
eq "$(now status)|$(now assignee)|$(now gc.routed_to)" "open||" "and it reads back open, unassigned and unrouted"
eq "$(now gc.dispatch_when_ready)|$(now resling_target)|$(now gc.execution_routed_to)" "rig/pool|rig/pool|rig/pool" "and the re-sling the wait armed stays"

FAKE_CURRENT=tk-w run_claim "$(claim deferred sess-me)" --step mol.x --reason why --subject tk-w --key k1 --message "the message."
eq "$RC|$TRACE" "0|GATE DRAIN " "a claim whose gate asks for no wait, as on a parked bead: asks, drains, and cancels nothing"
eq "$(args UPDATE)" "" "and writes nothing to the bead"
eq "$(now status)" "deferred" "so the bead stays parked for the person the gate asks"

FAKE_CURRENT=tk-w GATE_RC=1 run_claim "$HELD" "${GATED_CLAIM[@]}"
eq "$RC" 1 "a claim whose gate does not land: exits 1"
eq "$TRACE" "GATE " "and nothing follows it, not even the drain"
has "$OUT" "tk-w is a claim with no run, so it stays with this session" "and it says what this session still holds"
no "$OUT" "next worker retries" "and names no next worker, since no step goes to one"
FAKE_CURRENT=tk-w AWAIT_RC=1 run_claim "$HELD" "${GATED_CLAIM[@]}"
eq "$TRACE" "GATE AWAIT " "a claim whose wait does not land: no drain"
no "$OUT" "next worker retries" "and names no next worker"

FAKE_CURRENT=tk-w run_claim "$(claim in_progress hq-other)" --step mol.x --reason why
eq "$RC" 1 "a claim another session now holds: exits 1"
eq "$TRACE" "UPDATE " "and the refusal is noted, and the session does not drain"
has "$(args UPDATE)" "Hand-back refused" "the note says the hand-back was refused"
eq "$(now status)|$(now assignee)" "in_progress|hq-other" "and the other session's claim is left as it was"
has "$OUT" "was not handed back" "and the decline says so"
no "$OUT" "next worker retries" "and names no next worker"

FAKE_CURRENT=tk-w FAKE_UPDATE_RC=1 run_claim "$HELD" --step mol.x --reason why
eq "$RC" 1 "a hand-back the store refuses: exits 1"
no "$TRACE" "DRAIN" "and the session does not drain"
has "$OUT" "the claim on tk-w was not handed back" "and the decline says so"


FAKE_CURRENT=tk-w run_claim "$(claim in_progress sess-me mol.x)" --step mol.x --reason why
eq "$RC" 1 "a step whose real cancel does not land: exits 1"
eq "$TRACE" "" "and nothing is handed back, and the session does not drain"
has "$OUT" "run-cancel.sh did not end the run; NOT draining, so the next worker retries." "and the next worker the step goes to retries"
FAKE_CURRENT=tk-other run_claim "$HELD" --step mol.x --reason why
eq "$TRACE" "" "gc hook current names a bead that does not read: a step, never handed back"
FAKE_CURRENT="" run_claim "$HELD" --step mol.x --reason why
eq "$TRACE" "" "gc hook current names nothing: nothing is handed back"

echo
echo "decline: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
