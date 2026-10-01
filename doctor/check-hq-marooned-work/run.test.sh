#!/usr/bin/env bash
# Hermetic test for doctor/check-hq-marooned-work. Stub gc/bd only; no city,
# no network. Covers: a marooned bug and a pool-routed task are flagged; every
# legitimate HQ resident is exempt (infra type, human route, task_kind=visit,
# deacon-ledger label, debt label, gc-doctor title, an assigned bead, a bead
# routed to a city-scoped agent, a warrant label, a standing subject); the
# machinery types bd's ready-work query excludes (step, convoy,
# startup-health-episode) are exempt while a marooned spec is still flagged; the
# city-route exemption keys off the agent's scope not its name; a warrant is
# still exempt when the agent list is down; a mix names only the marooned beads;
# an empty store passes; and the fail-closed arms — no locatable city, an
# unreadable store (with its stderr surfaced), and the GC_CITY_PATH fallback
# when `gc agent list` cannot answer.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-hq-marooned-work-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

CITY="$TMP/testcity"
mkdir -p "$TMP/bin" "$TMP/stores" "$CITY"

cat > "$TMP/agents.json" <<EOF
{"city_path":"$CITY","agents":[{"qualified_name":"gc-toolkit/gc-toolkit.polecat","scope":"rig"},{"qualified_name":"gc-toolkit.dog","scope":"city"}]}
EOF
printf '{"city_path":"","agents":[]}' > "$TMP/agents-nocity.json"

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "agent list") rc="${AGENTS_RC:-0}"; [ "$rc" -eq 0 ] || { [ -n "${AGENTS_ERR:-}" ] && printf '%s\n' "$AGENTS_ERR" >&2; exit "$rc"; }; cat "$AGENTS_JSON" ;;
  "bd "*) shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The check reaches the HQ store through `gc bd`; a direct `bd` is the
# regression this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && { [ -n "${BD_ERR:-}" ] && printf '%s\n' "$BD_ERR" >&2; exit 3; }
case "$sub" in
  list) f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi ;;
  *) printf '[]' ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"

run_check() {
    AGENTS_JSON="${AGENTS_JSON:-$TMP/agents.json}" \
    GC_CITY_PATH="${WANT_CITY_PATH:-}" GC_CITY="" \
    PATH="$TMP/bin:$PATH" STORES="$TMP/stores" \
    bash "$CHECK" 2>&1
}
store() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/testcity.json"; }

B_BUG='{"id":"m-bug","status":"open","issue_type":"bug","title":"real marooned defect"}'
B_POOL='{"id":"m-pool","status":"open","issue_type":"task","title":"work routed nowhere readable","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}'
B_SESSION='{"id":"ok-sess","status":"open","issue_type":"session","title":"gc-toolkit/gc-toolkit.witness"}'
B_HUMAN='{"id":"ok-human","status":"open","issue_type":"task","title":"operator disk-size call","metadata":{"gc.routed_to":"human"}}'
B_VISIT='{"id":"ok-visit","status":"open","issue_type":"task","title":"visit: operator pick","metadata":{"task_kind":"visit"}}'
B_LEDGER='{"id":"ok-ledger","status":"open","issue_type":"task","title":"deacon ledger 2026-09-29","labels":["deacon-ledger"]}'
B_DEBT='{"id":"ok-debt","status":"open","issue_type":"task","title":"gc doctor: 2 new findings (dolt-drift)","labels":["debt"]}'
B_DOCTOR='{"id":"ok-doctor","status":"open","issue_type":"task","title":"gc doctor: agent-token-telemetry"}'
B_ASSIGNED='{"id":"ok-assigned","status":"open","issue_type":"bug","title":"already being worked","assignee":"gc-toolkit/gc-toolkit.polecat"}'
B_WARRANT='{"id":"ok-warrant","status":"open","issue_type":"task","title":"warrant: shut down lx-x","labels":["warrant"],"metadata":{"gc.routed_to":"gc-toolkit.dog"}}'
B_DOGROUTE='{"id":"ok-dogroute","status":"open","issue_type":"task","title":"city task the dog claims","metadata":{"gc.routed_to":"gc-toolkit.dog"}}'
B_DOGQUAL='{"id":"ok-dogqual","status":"open","issue_type":"task","title":"city task routed at the qualified form","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.dog"}}'
B_WARRANT_UNROUTED='{"id":"ok-warrant-unrouted","status":"open","issue_type":"task","title":"warrant with its route cleared","labels":["warrant"]}'
B_TRIAGE='{"id":"ok-triage","status":"open","issue_type":"task","title":"triage: escalations raised from an ephemeral subject (this rig)","metadata":{"task_kind":"triage-subject","triage.scope":"ephemeral-subject-findings"}}'
B_FEEDBACK='{"id":"ok-feedback","status":"open","issue_type":"task","title":"feedback pattern host","metadata":{"task_kind":"feedback-pattern"}}'
B_STARTUP='{"id":"ok-startup","status":"open","issue_type":"startup-health-episode","title":"Startup health: gc-toolkit__ripley-pool"}'
B_STEP='{"id":"ok-step","status":"open","issue_type":"step","title":"mol-polecat-work.implement"}'
B_CONVOY='{"id":"ok-convoy","status":"open","issue_type":"convoy","title":"convoy: an epic"}'
B_SPEC='{"id":"m-spec","status":"open","issue_type":"spec","title":"spec for a real feature marooned in HQ"}'

# --- 1. a marooned bug is flagged -------------------------------------------
store "$B_BUG"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a rig-workable bug in the HQ store is an ERROR"
has "$OUT" "m-bug" "the finding names the bead"
has "$OUT" "bead-rehome.sh" "the finding names the re-home remedy"
has "$OUT" "HQ store" "the finding says it is in the HQ store"

# --- 2. a pool-routed task is flagged, and the route is named ----------------
store "$B_POOL"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a task routed to a pool but sitting in the HQ store is an ERROR"
has "$OUT" "routed to gc-toolkit/gc-toolkit.polecat" "the finding names the pool route"

# --- 3. every legitimate HQ resident is exempt ------------------------------
store "$B_SESSION" "$B_HUMAN" "$B_VISIT" "$B_LEDGER" "$B_DEBT" "$B_DOCTOR" "$B_ASSIGNED"
OUT=$(run_check); RC=$?
eq "$RC" "0" "session/human/visit/ledger/debt/doctor/assigned are all legitimate HQ contents"
has "$OUT" "OK:" "the pass message is the OK line"
hasnt "$OUT" "ok-sess" "an infra session type is not flagged"
hasnt "$OUT" "ok-human" "a decision routed to human is not flagged"
hasnt "$OUT" "ok-visit" "a task_kind=visit is not flagged"
hasnt "$OUT" "ok-ledger" "a deacon-ledger daily digest is not flagged"
hasnt "$OUT" "ok-debt" "a debt-labelled advisory is not flagged"
hasnt "$OUT" "ok-doctor" "a gc-doctor-titled advisory with no label is not flagged"
hasnt "$OUT" "ok-assigned" "an already-assigned bead is not flagged"

# --- 4. a mix names only the marooned beads ---------------------------------
store "$B_BUG" "$B_SESSION" "$B_DEBT" "$B_HUMAN" "$B_DOCTOR"
OUT=$(run_check); RC=$?
eq "$RC" "2" "one marooned bead among legitimate contents is still an ERROR"
has "$OUT" "1 finding" "the count is the marooned beads alone"
has "$OUT" "m-bug" "the marooned bead is named"
hasnt "$OUT" "ok-debt" "the legitimate contents are not named in a mixed store"
hasnt "$OUT" "ok-doctor" "the legitimate contents are not named in a mixed store"

# --- 5. an empty HQ store passes --------------------------------------------
printf '[]' > "$TMP/stores/testcity.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an empty HQ store is OK"
has "$OUT" "OK:" "the empty store reports the OK line"

# --- 6. no locatable city fails CLOSED --------------------------------------
OUT=$(AGENTS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc agent list\` with no GC_CITY_PATH warns, never passes"
has "$OUT" "cannot be located" "the warning says the HQ store could not be located"
OUT=$(AGENTS_RC=1 AGENTS_ERR="dolt: connection refused" run_check); RC=$?
has "$OUT" "connection refused" "the agent-list warning carries the probe's stderr"

# --- 7. GC_CITY_PATH is the fallback when agent list cannot answer -----------
store "$B_BUG"
OUT=$(AGENTS_RC=1 WANT_CITY_PATH="$CITY" run_check); RC=$?
eq "$RC" "2" "with agent list down, GC_CITY_PATH still locates the HQ store and the bug is flagged"
has "$OUT" "m-bug" "the fallback path names the marooned bead"
# ...and also when agent list answers but carries an empty city_path.
OUT=$(AGENTS_JSON="$TMP/agents-nocity.json" WANT_CITY_PATH="$CITY" run_check); RC=$?
eq "$RC" "2" "an empty city_path from agent list falls back to GC_CITY_PATH"

# --- 8. an unreadable HQ store fails CLOSED, surfacing its stderr ------------
store "$B_BUG"
OUT=$(BD_FAIL_STORE=testcity run_check); RC=$?
eq "$RC" "1" "an unreadable HQ store warns instead of passing"
has "$OUT" "NOT checked" "the warning says the store was skipped, not clean"
OUT=$(BD_FAIL_STORE=testcity BD_ERR="dolt: relation \"issues\" does not exist" run_check); RC=$?
eq "$RC" "1" "an unreadable HQ store still warns"
has "$OUT" "does not exist" "the store-skip warning carries \`gc bd list\` stderr"

# --- 9. city machinery and standing subjects are exempt; a real marooned bead
#        among them is still caught -----------------------------------------
store "$B_WARRANT" "$B_DOGROUTE" "$B_DOGQUAL" "$B_WARRANT_UNROUTED" "$B_TRIAGE" "$B_FEEDBACK" "$B_BUG"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a real marooned bug among city machinery is still an ERROR"
has "$OUT" "1 finding" "only the marooned bug is a finding"
has "$OUT" "m-bug" "the marooned bug is named"
hasnt "$OUT" "ok-warrant" "a warrant routed to the city dog is not flagged"
hasnt "$OUT" "ok-dogroute" "a task routed to the city dog (bare identity) is not flagged"
hasnt "$OUT" "ok-dogqual" "a task routed to the dog at the qualified form is not flagged"
hasnt "$OUT" "ok-warrant-unrouted" "a warrant with no route is exempt by its label"
hasnt "$OUT" "ok-triage" "a standing triage-subject is not flagged"
hasnt "$OUT" "ok-feedback" "a standing feedback-pattern is not flagged"

# --- 10. the city-route exemption keys off scope, not the name 'dog' ---------
# With the dog marked rig-scoped, its pool cannot read the HQ store, so a bead
# routed to it and sitting here IS unreachable and must still be flagged.
cat > "$TMP/agents-dogrig.json" <<EOF
{"city_path":"$CITY","agents":[{"qualified_name":"gc-toolkit.dog","scope":"rig"}]}
EOF
store "$B_DOGROUTE"
OUT=$(AGENTS_JSON="$TMP/agents-dogrig.json" run_check); RC=$?
eq "$RC" "2" "a task routed to a NON-city-scoped dog is still marooned"
has "$OUT" "ok-dogroute" "the exemption is scope-driven, not a hardcoded 'dog' name"

# --- 11. with the agent list down, the warrant label still exempts -----------
# CITY_ROUTES cannot resolve without the roster, but a warrant is city machinery
# a rig never works regardless of route resolution.
store "$B_WARRANT_UNROUTED"
OUT=$(AGENTS_RC=1 WANT_CITY_PATH="$CITY" run_check); RC=$?
eq "$RC" "0" "a warrant is exempt by label even when the agent list is unreadable"
has "$OUT" "OK:" "the roster-down warrant store reports the OK line"

# --- 12. machinery types mirrored from bd's ready-work exclusions are exempt,
#         but spec (real rig work) is still caught --------------------------
# step/convoy/startup-health-episode are in gascity's readyExcludeTypes, so the
# check must exempt them. spec is deliberately NOT excluded, so a spec marooned
# in the HQ store is still work no rig can reach and must be reported.
store "$B_STARTUP" "$B_STEP" "$B_CONVOY" "$B_SPEC"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a marooned spec among machinery types is still an ERROR"
has "$OUT" "1 finding" "only the spec is a finding"
has "$OUT" "m-spec" "the marooned spec is named"
hasnt "$OUT" "ok-startup" "a startup-health-episode host is not flagged"
hasnt "$OUT" "ok-step" "a formula step bead is not flagged"
hasnt "$OUT" "ok-convoy" "a convoy container is not flagged"

echo
echo "check-hq-marooned-work: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
