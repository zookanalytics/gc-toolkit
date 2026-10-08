#!/usr/bin/env bash
# Hermetic test for doctor/check-root-advancing (I13). Stubs gc/bd only; no
# city, Dolt, network or beads.
#
# The check fires on a workflow root that STARTED and then stranded — its
# session gone, its work unlanded, and a ready frontier step nothing can claim —
# and it must stay silent on every shape that is not that: a live session behind
# it (including the affinity slot a restart reuses), a molecule that never closed
# a step, one whose work has landed, one written recently (through a closed step
# too), a frontier that is routed, owned, empty, or all descriptor beads, and one
# parked on purpose. Every unestablished fact leaves the run silent, not
# guessing: an unread roster declines it, an unread store or convoy or closed
# listing leaves that unit unjudged.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-root-advancing-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/beta"

# Fixtures are written relative to real time because the check dates a molecule
# with jq's `now`. Each age is read when its fixture is written.
ago() { jq -nr --argjson t "$(( $(date -u +%s) - $1 ))" '$t | todate'; }
OLD=$((200 * 60))       # past the 120m default bound
FRESH=$((10 * 60))      # inside it

cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"},{"name":"beta","path":"$TMP/beta"}]}
EOF

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "session list") rc="${SESSIONS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$SESSIONS_JSON" ;;
  "rig list")     rc="${RIGS_RC:-0}";     [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)         shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
# The stub applies the same --db, --status, --metadata-field, --has-metadata-key,
# --id and --all filters the real bd applies server-side, and hides closed beads
# unless a --status names it or --all is passed — the visibility the landed check
# and the closed-step read both turn on.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; shift
db=""; status=""; hmk=""; ids=""; all=0; mfk=""; mfv=""; prev=""
for a in "$@"; do
  case "$prev" in
    --db) db="$a" ;;
    --status) status="$a" ;;
    --has-metadata-key) hmk="$a" ;;
    --id) ids="$a" ;;
    --metadata-field) mfk="${a%%=*}"; mfv="${a#*=}" ;;
  esac
  [ "$a" = "--all" ] && all=1
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
if [ "$sub" = "ready" ]; then
  [ "$name" = "${BD_READY_FAIL_STORE:-}" ] && exit 3
  r="$STORES/$name.ready.json"; [ -f "$r" ] || { printf '[]'; exit 0; }
  cat "$r"; exit 0
fi
# The landed check asks the convoy by id; failing that alone isolates it.
[ -n "$ids" ] && [ "$name" = "${BD_ID_FAIL_STORE:-}" ] && exit 3
# The per-survivor closed read is the only one asking --status closed; failing
# that alone isolates the closed-read degrade.
[ "$status" = "closed" ] && [ "$name" = "${BD_CLOSED_FAIL_STORE:-}" ] && exit 3
f="$STORES/$name.json"; [ -f "$f" ] || { printf '[]'; exit 0; }
jq -c --arg s "$status" --arg hmk "$hmk" --arg ids "$ids" --argjson all "$all" \
      --arg mfk "$mfk" --arg mfv "$mfv" '
  ($s | split(",") | map(select(. != ""))) as $S
  | ($ids | split(",") | map(select(. != ""))) as $I
  | [ .[] | ((.id // "") | tostring) as $bid | ((.status // "") | tostring) as $st
          | ((.metadata // {})) as $m
          | select(($S | length) == 0 or ($S | index($st) != null))
          | select($hmk == "" or ($m | has($hmk)))
          | select($mfk == "" or (($m[$mfk] // "") | tostring) == $mfv)
          | select(($I | length) == 0 or (($I | index($bid)) != null))
          | select($all == 1 or ($S | length) > 0 or $st != "closed") ]' "$f"
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

run_check() {
    SESSIONS_JSON="${SESSIONS_JSON:-$TMP/sessions.json}" RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" \
    bash "$CHECK" 2>&1
}
store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.json"; }
ready() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.ready.json"; }
clear_stores() { rm -f "$TMP/stores/"*.json; }
# sessions <json-rows...>
sessions() { local IFS=,; printf '{"sessions":[%s]}' "$*" > "$TMP/sessions.json"; }
# live <id> <session_name> [alias]
live() { printf '{"id":"%s","session_name":"%s","alias":"%s","state":"active"}' "$1" "$2" "${3:-}"; }
asleep() { printf '{"id":"%s","session_name":"%s","alias":"","state":"asleep"}' "$1" "$2"; }

# root <id> <convoy> <session_name> <updated-seconds-ago> [extra-meta-json]
root() { printf '{"id":"%s","status":"in_progress","updated_at":"%s","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"%s","gc.session_name":"%s","gc.formula_name":"mol-x"%s}}' \
    "$1" "$(ago "$4")" "$2" "$3" "${5:+,$5}"; }
# step <id> <root> <status> <updated-ago> [assignee] [sid] [routed] [exec] [kind] [extra-meta]
step() {
    local id="$1" root="$2" st="$3" ago="$4" as="${5:-}" sid="${6:-}" routed="${7:-}" exec="${8:-}" kind="${9:-}" extra="${10:-}"
    local md="\"gc.root_bead_id\":\"$root\",\"gc.step_ref\":\"mol-x.$id\""
    [ -n "$sid" ]    && md="$md,\"gc.session_id\":\"$sid\""
    [ -n "$routed" ] && md="$md,\"gc.routed_to\":\"$routed\""
    [ -n "$exec" ]   && md="$md,\"gc.execution_routed_to\":\"$exec\""
    [ -n "$kind" ]   && md="$md,\"gc.kind\":\"$kind\""
    [ -n "$extra" ]  && md="$md,$extra"
    printf '{"id":"%s","status":"%s","assignee":"%s","updated_at":"%s","metadata":{%s}}' "$id" "$st" "$as" "$(ago "$ago")" "$md"
}
# convoy <id> <status>
convoy() { printf '{"id":"%s","status":"%s","metadata":{}}' "$1" "$2"; }

# The default roster: the dead molecule's slot is NOT among the live sessions.
sessions "$(live lx-live gc-toolkit__other)"

echo "== 1. a started, session-less, unlanded molecule with an unclaimable ready frontier is an error =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead gc-toolkit/gc-toolkit.polecat)" \
            "$(step front1 R1 open "$OLD")" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$OLD")"
OUT="$(run_check)"; RC=$?
eq "$RC" "2" "exit 2 on a genuine strand"
has "$OUT" "root R1" "names the stranded root"
has "$OUT" "front1" "names the unreachable frontier step"
has "$OUT" "STRANDED" "labels it stranded"

echo "== 1b. a strand whose root carries NO gc.session_name is reported, not crashed =="
# A stranded root commonly has no session_name back-reference: the slot that
# drove it is gone and nothing restamped the root. The empty value must index
# nothing in the live-session set and fall through to member liveness, never
# abort the check on a bad associative-array subscript — the one shape that
# turned this detector into a no-op on exactly the roots it exists to catch.
clear_stores
store alpha "$(root R1b CV1b "" "$OLD")" \
            "$(step done1b R1b closed "$OLD" lx-dead lx-dead gc-toolkit/gc-toolkit.polecat)" \
            "$(step front1b R1b open "$OLD")" \
            "$(convoy CV1b open)"
ready alpha "$(step front1b R1b open "$OLD")"
OUT="$(run_check)"; RC=$?
eq "$RC" "2" "a session-less root strand is reported, not crashed"
has "$OUT" "root R1b" "names the session-less stranded root"
hasnt "$OUT" "bad array subscript" "an empty session_name does not abort the check"

echo "== 2. exempt: a live session holds a non-closed member =="
clear_stores
sessions "$(live lx-hold gc-toolkit__worker)"
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 in_progress "$OLD" lx-hold lx-hold)" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 in_progress "$OLD" lx-hold lx-hold)"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "a live member holder exempts the molecule"
hasnt "$OUT" "STRANDED" "no strand reported when held"
sessions "$(live lx-live gc-toolkit__other)"

echo "== 3. exempt: the root's affinity slot is live (a restart reuses it) =="
clear_stores
sessions "$(live lx-new gc-toolkit__polecat-7-pool)"
store alpha "$(root R1 CV1 gc-toolkit__polecat-7-pool "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 open "$OLD")" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$OLD")"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "a live affinity slot on the root exempts it"
sessions "$(live lx-live gc-toolkit__other)"

echo "== 4. exempt: never started (no closed step) — an inline husk, not a strand =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step front1 R1 open "$OLD")" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$OLD")"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "zero closed steps is exempt (never advanced)"

echo "== 5. exempt: work landed (input convoy closed) =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 open "$OLD")" \
            "$(convoy CV1 closed)"
ready alpha "$(step front1 R1 open "$OLD")"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "a closed input convoy (landed work) is exempt"

echo "== 6. exempt: a non-closed member was written recently (still advancing) =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 open "$FRESH")" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$FRESH")"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "a fresh non-closed member keeps it out of the silent set"

echo "== 7. exempt: a step CLOSED recently dates the molecule (closed members count for silence) =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$FRESH" lx-dead lx-dead)" \
            "$(step front1 R1 open "$OLD")" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$OLD")"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "a recently CLOSED step (advancement) exempts, though every open member is stale"

echo "== 8. exempt: the frontier is routed (reachable) =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 open "$OLD" '' '' gc-toolkit/gc-toolkit.polecat)" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$OLD" '' '' gc-toolkit/gc-toolkit.polecat)"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "a routed frontier is reachable (a pool has demand)"

echo "== 9. exempt: the frontier carries an EXECUTION route (the recovery-fix stamp) =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 open "$OLD" '' '' '' gc-toolkit/gc-toolkit.polecat)" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$OLD" '' '' '' gc-toolkit/gc-toolkit.polecat)"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "an execution-routed frontier reads as reachable"

echo "== 10. exempt: empty frontier (nothing ready) — a blocker names the wait =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 open "$OLD")" \
            "$(convoy CV1 open)"
ready alpha
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "no ready frontier is exempt"

echo "== 11. exempt: the only ready members are inert descriptor kinds (spec/scope) =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step spec1 R1 open "$OLD" '' '' '' '' spec)" \
            "$(step scope1 R1 open "$OLD" '' '' '' '' scope)" \
            "$(convoy CV1 open)"
ready alpha "$(step spec1 R1 open "$OLD" '' '' '' '' spec)" \
            "$(step scope1 R1 open "$OLD" '' '' '' '' scope)"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "a descriptor-only frontier is not an executable frontier"

echo "== 12. held on purpose is a NOTE, not a finding =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD" '"gc.takeaway":"operator parked this"')" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 open "$OLD")" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$OLD")"
OUT="$(run_check)"; RC=$?
eq "$RC" "0" "a parked molecule does not error"
has "$OUT" "held on purpose" "it is reported as a held note"

echo "== 13. fail-safe: an unreadable roster declines the whole run =="
clear_stores
export SESSIONS_RC=7; OUT="$(run_check)"; RC=$?; unset SESSIONS_RC
eq "$RC" "1" "roster read failure warns (1)"
has "$OUT" "session list" "and says why"

echo "== 14. fail-safe: an empty roster declines (every molecule would look unheld) =="
clear_stores
printf '{"sessions":[]}' > "$TMP/sessions.json"
OUT="$(run_check)"; RC=$?
eq "$RC" "1" "empty roster warns (1)"
sessions "$(live lx-live gc-toolkit__other)"

echo "== 15. fail-safe: an unreadable store is a warning, not a strand =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 open "$OLD")" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$OLD")"
export BD_FAIL_STORE=alpha; OUT="$(run_check)"; RC=$?; unset BD_FAIL_STORE
eq "$RC" "1" "an unreadable store warns rather than erroring"
has "$OUT" "NOT checked" "and names it as unchecked"

echo "== 16. fail-safe: an unreadable convoy leaves the candidate unjudged =="
clear_stores
store alpha "$(root R1 CV1 dead-slot "$OLD")" \
            "$(step done1 R1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 R1 open "$OLD")" \
            "$(convoy CV1 open)"
ready alpha "$(step front1 R1 open "$OLD")"
export BD_ID_FAIL_STORE=alpha; OUT="$(run_check)"; RC=$?; unset BD_ID_FAIL_STORE
eq "$RC" "1" "an unreadable convoy warns, not errors (landed is unproven)"
hasnt "$OUT" "STRANDED" "and does not flag the unjudged candidate"

echo "== 17. two rigs: a strand in beta is found while alpha is clean =="
clear_stores
store alpha "$(root A1 CVA live-clean "$FRESH")" "$(convoy CVA open)"
store beta  "$(root B1 CVB dead-slot "$OLD")" \
            "$(step done1 B1 closed "$OLD" lx-dead lx-dead)" \
            "$(step front1 B1 open "$OLD")" \
            "$(convoy CVB open)"
ready beta "$(step front1 B1 open "$OLD")"
OUT="$(run_check)"; RC=$?
eq "$RC" "2" "the strand in beta errors"
has "$OUT" "root B1" "names beta's stranded root"
hasnt "$OUT" "root A1" "does not name the clean alpha root"

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
