#!/usr/bin/env bash
# Hermetic test for reconcile-refinery-handoffs.sh.
#
# Stubs `gc` (a JSON bead ledger + a canned session roster) on PATH. No live city,
# no Dolt, no network. Covers the repair, its idempotence, every refusal arm, the
# empty-roster fail-safe, the failed-write verdict, --dry-run, and the nudge rule.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-refinery-handoffs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CANON="su/gc-toolkit.refinery"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

assignee_of() { jq -r --arg id "$1" '.[] | select(.id==$id) | .assignee' "$TMP/beads.json"; }
meta_of()     { jq -r --arg id "$1" --arg k "$2" '.[] | select(.id==$id) | .metadata[$k] // ""' "$TMP/beads.json"; }
notes_of()    { jq -r --arg id "$1" '.[] | select(.id==$id) | .notes // ""' "$TMP/beads.json"; }

# --- the stub `gc` ---------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
  session)
    case "${2:-}" in
      list)  cat "$FAKE_SESSIONS" ;;
      nudge) printf '%s\n' "${3:-}" >> "$FAKE_NUDGES" ;;
    esac ;;
  mail)
    # Record the whole invocation: the subject's argv position is an implementation
    # detail of the caller, and an assertion keyed to it silently passes on nothing.
    printf '%s\n' "$*" >> "$FAKE_MAIL" ;;
  bd)
    shift; sub="${1:-}"; shift || true
    case "$sub" in
      list)
        if printf '%s\n' "$@" | grep -q -- '--type=session'; then
          cat "$FAKE_SESSION_BEADS"
        else
          # The handoff enumeration: open, non-epic, carrying metadata.branch.
          jq -c '[ .[]
                   | select(.status == "open")
                   | select((.issue_type // "task") != "epic")
                   | select(((.metadata // {}).branch // "") != "") ]' "$FAKE_BEADS"
        fi ;;
      show)
        jq -c --arg id "${1:-}" '[ .[] | select(.id == $id) ]' "$FAKE_BEADS" ;;
      update)
        id="${1:-}"; shift || true
        # Injected write failure: the update is accepted and does nothing, which is
        # exactly the shape the script's read-back exists to catch.
        if [ "${FAKE_UPDATE_FAIL:-}" = "$id" ]; then exit 0; fi
        while [ $# -gt 0 ]; do
          case "$1" in
            --assignee=*)
              v="${1#--assignee=}"
              jq -c --arg id "$id" --arg v "$v" \
                '[ .[] | if .id == $id then .assignee = $v else . end ]' \
                "$FAKE_BEADS" > "$FAKE_BEADS.new" && mv "$FAKE_BEADS.new" "$FAKE_BEADS"
              shift ;;
            --set-metadata)
              k="${2%%=*}"; v="${2#*=}"
              jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
                '[ .[] | if .id == $id then .metadata = ((.metadata // {}) + {($k): $v}) else . end ]' \
                "$FAKE_BEADS" > "$FAKE_BEADS.new" && mv "$FAKE_BEADS.new" "$FAKE_BEADS"
              shift 2 ;;
            --append-notes)
              v="${2:-}"
              jq -c --arg id "$id" --arg v "$v" \
                '[ .[] | if .id == $id then .notes = ((.notes // "") + $v) else . end ]' \
                "$FAKE_BEADS" > "$FAKE_BEADS.new" && mv "$FAKE_BEADS.new" "$FAKE_BEADS"
              shift 2 ;;
            *) shift ;;
          esac
        done ;;
    esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_BEADS="$TMP/beads.json" FAKE_SESSIONS="$TMP/sessions.json" \
       FAKE_SESSION_BEADS="$TMP/session-beads.json" FAKE_NUDGES="$TMP/nudges" \
       FAKE_MAIL="$TMP/mail"

# Roster: the canonical refinery is alive (on `alias`, the shape verified live),
# plus one session that really answers to a refinery-ish near-miss.
cat > "$TMP/sessions.json" <<JSON
{"sessions":[
  {"id":"s1","name":null,"session_name":"su--gc-toolkit__refinery","alias":"$CANON","agent_name":null,"state":"active","closed":null},
  {"id":"s2","name":null,"session_name":"su--held__refinery","alias":"su/held.refinery","agent_name":null,"state":"active","closed":null},
  {"id":"s3","name":null,"session_name":"su--dead__refinery","alias":"su/dead.refinery","agent_name":null,"state":"closed","closed":true}
]}
JSON
echo '[]' > "$TMP/session-beads.json"
: > "$TMP/nudges"
: > "$TMP/mail"

seed_beads() {
  cat > "$TMP/beads.json" <<JSON
[
 {"id":"b1","status":"open","assignee":"su/refinery","metadata":{"branch":"polecat/b1"}},
 {"id":"b2","status":"open","assignee":"refinery","metadata":{"branch":"polecat/b2"}},
 {"id":"b3","status":"open","assignee":"su/gc-toolkit.refinery-2","metadata":{"branch":"polecat/b3"}},
 {"id":"b4","status":"open","assignee":"su/refinery","metadata":{"branch":"polecat/b4","merge_result":"pull_request"}},
 {"id":"b5","status":"open","assignee":"su/refinery","metadata":{"branch":"polecat/b5","gc.routed_to":"su/gc-toolkit.polecat"}},
 {"id":"b6","status":"open","assignee":"other/refinery","metadata":{"branch":"polecat/b6"}},
 {"id":"b7","status":"open","assignee":"su/held.refinery","metadata":{"branch":"polecat/b7"}},
 {"id":"b8","status":"open","assignee":"$CANON","metadata":{"branch":"polecat/b8"}},
 {"id":"b9","status":"open","assignee":"su/refinery","metadata":{}},
 {"id":"b10","status":"closed","assignee":"su/refinery","metadata":{"branch":"polecat/b10"}},
 {"id":"b11","status":"open","assignee":"su/dead.refinery","metadata":{"branch":"polecat/b11"}}
]
JSON
}

# --- Run 1: the repair, and every refusal, in one pass. --------------------
seed_beads
rc1=0
GC_AGENT="su/gc-toolkit.witness" bash "$SCRIPT" --refinery "$CANON" > "$TMP/out1" 2>"$TMP/err1" || rc1=$?
eq "$rc1" "0" "a pass with no failed write exits 0"

eq "$(assignee_of b1)" "$CANON"                 "near-miss missing the binding prefix is repaired"
eq "$(meta_of b1 refinery_address_repaired)" "su/refinery" "the repair records the address it replaced"
grep -q "polecat/b1" <<< "$(notes_of b1)" && ok "the repair notes the branch it recovered" \
  || bad "the repair notes the branch it recovered"
eq "$(assignee_of b2)" "$CANON"                 "bare 'refinery' (no rig qualifier) is repaired"
eq "$(assignee_of b3)" "su/gc-toolkit.refinery-2" "a role that only RESEMBLES refinery is untouched"
eq "$(assignee_of b4)" "su/refinery"            "a bead carrying merge_result is left to check-set-heal"
eq "$(assignee_of b5)" "su/refinery"            "a bead with a live gc.routed_to still belongs to its pool"
eq "$(assignee_of b6)" "other/refinery"         "another rig's refinery is never rewritten"
eq "$(meta_of b6 refinery_handoff_flagged)" "other/refinery" "the cross-rig case is flagged instead"
eq "$(assignee_of b7)" "su/held.refinery"       "an address a LIVE session answers to is never rewritten"
eq "$(meta_of b7 refinery_handoff_flagged)" "su/held.refinery" "the live-holder case is flagged instead"
eq "$(assignee_of b8)" "$CANON"                 "a correctly-addressed handoff is not a candidate"
eq "$(assignee_of b9)" "su/refinery"            "a bead with no branch is not a merge handoff"
eq "$(assignee_of b10)" "su/refinery"           "a closed bead is out of scope"
eq "$(assignee_of b11)" "$CANON"                "a CLOSED session's address counts as dead and is repaired"
grep -q "2 reported" "$TMP/out1" && ok "the refusals are counted as reported" || bad "the refusals are counted as reported"
grep -q "3 repaired" "$TMP/out1" && ok "the repairs are counted" || bad "the repairs are counted ($(cat "$TMP/out1"))"
eq "$(wc -l < "$TMP/nudges" | tr -d ' ')" "1" "a non-refinery caller nudges the refinery once"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "0" "the benign refusals do not mail (a live holder, cross-rig routing)"

# --- Run 2: idempotent, and the flag does not repeat. ----------------------
: > "$TMP/nudges"
bash "$SCRIPT" --refinery "$CANON" > "$TMP/out2" 2>"$TMP/err2"
grep -q "0 repaired" "$TMP/out2" && ok "a re-run repairs nothing" || bad "a re-run repairs nothing"
grep -q "WARN b6" "$TMP/err2" && bad "the flag repeats every cycle" || ok "an already-flagged bead does not re-warn"
eq "$(wc -l < "$TMP/nudges" | tr -d ' ')" "0" "no repairs means no nudge"

# --- Run 3: the refinery running it on itself does not self-nudge. --------
seed_beads
: > "$TMP/nudges"
GC_AGENT="$CANON" bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>&1
eq "$(assignee_of b1)" "$CANON" "the refinery's own pass still repairs"
eq "$(wc -l < "$TMP/nudges" | tr -d ' ')" "0" "the refinery does not nudge itself"

# --- Run 4: empty roster -> fail-safe, never repair. -----------------------
seed_beads
echo '{"sessions":[]}' > "$TMP/sessions.json"
bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>"$TMP/err4"
eq "$(assignee_of b1)" "su/refinery" "an empty roster repairs nothing (fail-safe)"
grep -q "FAIL-SAFE" "$TMP/err4" && ok "the fail-safe says so on stderr" || bad "the fail-safe says so on stderr"

# --- Run 5: canonical identity resolves to nobody -> report, never rewrite. -
seed_beads
cat > "$TMP/sessions.json" <<JSON
{"sessions":[{"id":"s9","name":null,"session_name":"su--other","alias":"su/gc-toolkit.polecat","agent_name":null,"state":"active","closed":null}]}
JSON
bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>"$TMP/err5"
eq "$(assignee_of b1)" "su/refinery" "an unresolvable canonical identity blocks the rewrite"
grep -q "resolves to NO session either" "$TMP/err5" && ok "the unresolvable-canonical case is reported" \
  || bad "the unresolvable-canonical case is reported"
eq "$(grep -c 'STRANDED HANDOFF' "$TMP/mail" | tr -d ' ')" "4" "a strand this pass cannot fix escalates to the mayor"
bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>&1
eq "$(grep -c 'STRANDED HANDOFF' "$TMP/mail" | tr -d ' ')" "4" "the escalation is bounded — it does not repeat next cycle"
: > "$TMP/mail"

# --- Run 6: a configured-but-unspawned refinery is alive via session beads. -
seed_beads
cat > "$TMP/session-beads.json" <<JSON
[{"id":"sb1","status":"open","metadata":{"configured_named_identity":"$CANON","state":"asleep"}}]
JSON
bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>&1
eq "$(assignee_of b1)" "$CANON" "a named identity known only from session beads counts as alive"
echo '[]' > "$TMP/session-beads.json"

# --- Run 7: a write that does not stick is a verdict, not a silent pass. ---
seed_beads
cat > "$TMP/sessions.json" <<JSON
{"sessions":[{"id":"s1","name":null,"session_name":"su--gc-toolkit__refinery","alias":"$CANON","agent_name":null,"state":"active","closed":null}]}
JSON
rc=0
FAKE_UPDATE_FAIL=b1 bash "$SCRIPT" --refinery "$CANON" >"$TMP/out7" 2>"$TMP/err7" || rc=$?
eq "$rc" "1" "a repair that does not read back exits non-zero"
eq "$(assignee_of b1)" "su/refinery" "the unstuck bead is left as it was"
grep -q "did NOT stick" "$TMP/err7" && ok "the failed write is named on stderr" || bad "the failed write is named on stderr"
grep -q "1 failed" "$TMP/out7" && ok "the failure is counted" || bad "the failure is counted"

# --- Run 8: --dry-run mutates nothing. ------------------------------------
seed_beads
: > "$TMP/nudges"
bash "$SCRIPT" --refinery "$CANON" --dry-run >"$TMP/out8" 2>/dev/null
eq "$(assignee_of b1)" "su/refinery" "--dry-run does not reassign"
eq "$(meta_of b6 refinery_handoff_flagged)" "" "--dry-run does not flag"
eq "$(wc -l < "$TMP/nudges" | tr -d ' ')" "0" "--dry-run does not nudge"
grep -q "DRY-RUN would reassign b1" "$TMP/out8" && ok "--dry-run reports what it would do" \
  || bad "--dry-run reports what it would do"

# --- Run 9: no canonical identity -> skip entirely. ------------------------
seed_beads
bash "$SCRIPT" >/dev/null 2>"$TMP/err9"
eq "$(assignee_of b1)" "su/refinery" "no --refinery means nothing is touched"
grep -q "nothing to compare against" "$TMP/err9" && ok "the skip says why" || bad "the skip says why"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
