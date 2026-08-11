#!/usr/bin/env bash
# Hermetic test for reconcile-refinery-handoffs.sh.
#
# Stubs `gc` (a JSON bead ledger + a canned session roster) on PATH. No live city,
# no Dolt, no network. Covers the repair, its idempotence, every refusal arm, the
# roster fail-safe in all three unreadable shapes, the rig pin, the failed-write
# verdict, --dry-run, and the nudge rule.
#
# TWO LEDGERS, on purpose. The stub serves the rig-scoped database only to a call
# that carries `--rig <FAKE_RIG>`, and serves a DIFFERENT ambient database to any
# unpinned call — the imported-rig shape, where the patrol's ambient ledger is not
# the rig whose refinery it was handed. Every assertion below reads the rig ledger,
# so dropping the pin on any single bead call fails the suite rather than passing
# quietly against the wrong database.
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

assignee_of()     { jq -r --arg id "$1" '.[] | select(.id==$id) | .assignee' "$TMP/beads.json"; }
meta_of()         { jq -r --arg id "$1" --arg k "$2" '.[] | select(.id==$id) | .metadata[$k] // ""' "$TMP/beads.json"; }
notes_of()        { jq -r --arg id "$1" '.[] | select(.id==$id) | .notes // ""' "$TMP/beads.json"; }
amb_assignee_of() { jq -r --arg id "$1" '.[] | select(.id==$id) | .assignee' "$TMP/ambient-beads.json"; }

# --- the stub `gc` ---------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
  session)
    case "${2:-}" in
      list)
        # Injected roster failure. A read that FAILS is the case the fail-safe
        # exists for, and it must stay distinguishable from an empty city: the
        # script sees a non-zero exit and (as `gc` would) no payload.
        if [ -n "${FAKE_SESSIONS_RC:-}" ]; then exit "$FAKE_SESSIONS_RC"; fi
        cat "$FAKE_SESSIONS" ;;
      nudge) printf '%s\n' "${3:-}" >> "$FAKE_NUDGES" ;;
    esac ;;
  mail)
    # Record the whole invocation: the subject's argv position is an implementation
    # detail of the caller, and an assertion keyed to it silently passes on nothing.
    printf '%s\n' "$*" >> "$FAKE_MAIL" ;;
  bd)
    shift
    # The rig pin, consumed the way `gc` consumes it: either spelling, before or
    # after the subcommand. It decides WHICH LEDGER the call lands in, and an
    # unpinned call is both served the ambient database and recorded, so a test can
    # assert that no bead call escaped the pin.
    pin=""; args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --rig)   pin="${2:-}"; shift 2 ;;
        --rig=*) pin="${1#--rig=}"; shift ;;
        *)       args+=("$1"); shift ;;
      esac
    done
    if [ "${#args[@]}" -gt 0 ]; then set -- "${args[@]}"; else set --; fi
    if [ -n "$pin" ] && [ "$pin" = "${FAKE_RIG:-}" ]; then
      DB="$FAKE_BEADS"; SESSION_DB="$FAKE_SESSION_BEADS"
    else
      DB="$FAKE_AMBIENT_BEADS"; SESSION_DB="$FAKE_AMBIENT_SESSION_BEADS"
      printf '%s\n' "pin='$pin' $*" >> "$FAKE_UNPINNED"
    fi
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        if grep -q -- '--type=session' <<< "$(printf '%s\n' "$@")"; then
          cat "$SESSION_DB"
        else
          # The handoff enumeration: open, non-epic, carrying metadata.branch.
          jq -c '[ .[]
                   | select(.status == "open")
                   | select((.issue_type // "task") != "epic")
                   | select(((.metadata // {}).branch // "") != "") ]' "$DB"
        fi ;;
      show)
        jq -c --arg id "${1:-}" '[ .[] | select(.id == $id) ]' "$DB" ;;
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
                "$DB" > "$DB.new" && mv "$DB.new" "$DB"
              shift ;;
            --set-metadata)
              k="${2%%=*}"; v="${2#*=}"
              jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
                '[ .[] | if .id == $id then .metadata = ((.metadata // {}) + {($k): $v}) else . end ]' \
                "$DB" > "$DB.new" && mv "$DB.new" "$DB"
              shift 2 ;;
            --append-notes)
              v="${2:-}"
              jq -c --arg id "$id" --arg v "$v" \
                '[ .[] | if .id == $id then .notes = ((.notes // "") + $v) else . end ]' \
                "$DB" > "$DB.new" && mv "$DB.new" "$DB"
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
       FAKE_MAIL="$TMP/mail" \
       FAKE_AMBIENT_BEADS="$TMP/ambient-beads.json" \
       FAKE_AMBIENT_SESSION_BEADS="$TMP/ambient-session-beads.json" \
       FAKE_UNPINNED="$TMP/unpinned"

# The rig every run below is scoped to, and the one the script must derive from
# $GC_RIG without being told.
export FAKE_RIG="surig"
export GC_RIG="surig"

# Roster: the canonical refinery is alive (on `alias`, the shape verified live),
# plus one session that really answers to a refinery-ish near-miss.
seed_roster() {
  cat > "$TMP/sessions.json" <<JSON
{"sessions":[
  {"id":"s1","name":null,"session_name":"su--gc-toolkit__refinery","alias":"$CANON","agent_name":null,"state":"active","closed":null},
  {"id":"s2","name":null,"session_name":"su--held__refinery","alias":"su/held.refinery","agent_name":null,"state":"active","closed":null},
  {"id":"s3","name":null,"session_name":"su--dead__refinery","alias":"su/dead.refinery","agent_name":null,"state":"closed","closed":true}
]}
JSON
}
seed_roster
echo '[]' > "$TMP/session-beads.json"
echo '[]' > "$TMP/ambient-session-beads.json"
: > "$TMP/nudges"
: > "$TMP/mail"
: > "$TMP/unpinned"

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
  # The AMBIENT ledger, which is not this rig's. It holds a bead of exactly the
  # shape this pass repairs, so any run that loses the rig pin repairs the wrong
  # database — and every assertion that reads the rig ledger fails.
  cat > "$TMP/ambient-beads.json" <<JSON
[
 {"id":"amb1","status":"open","assignee":"su/refinery","metadata":{"branch":"polecat/amb1"}}
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

# --- Run 6b: session beads can prove ALIVE but never prove DEAD. -----------
# The live roster is the only census. When it does not read, a session-bead
# fallback must not stand in for it: appending those identities used to make the
# merged set non-empty, which read as "the roster is fine" and let the pass rewrite
# assignees on the strength of a read that never happened. All three unreadable
# shapes are covered — a failed call, a payload that is not {"sessions":[...]},
# and a roster that answers with nothing at all.
seed_beads
: > "$TMP/mail"
FAKE_SESSIONS_RC=42 bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>"$TMP/err6b"
eq "$(assignee_of b1)" "su/refinery" "a FAILED session-list read repairs nothing, even with a session bead naming the canonical identity"
grep -q "FAIL-SAFE" "$TMP/err6b" && ok "the failed roster read is reported as the fail-safe" \
  || bad "the failed roster read is reported as the fail-safe"
grep -q "exited 42" "$TMP/err6b" && ok "the failed roster read names the exit status" \
  || bad "the failed roster read names the exit status"

seed_beads
echo '{"error":"boom"}' > "$TMP/sessions.json"
bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>"$TMP/err6c"
eq "$(assignee_of b1)" "su/refinery" "a MALFORMED roster payload repairs nothing, even with a session bead naming the canonical identity"
grep -q "did not PARSE" "$TMP/err6c" && ok "the malformed roster payload is named as such" \
  || bad "the malformed roster payload is named as such"

seed_beads
echo '{"sessions":[]}' > "$TMP/sessions.json"
bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>"$TMP/err6d"
eq "$(assignee_of b1)" "su/refinery" "an EMPTY roster repairs nothing, even with a session bead naming the canonical identity"
grep -q "is EMPTY" "$TMP/err6d" && ok "the empty roster is named as such" || bad "the empty roster is named as such"
echo '[]' > "$TMP/session-beads.json"
seed_roster

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

# --- Run 10: the rig pin, stated outright. --------------------------------
# Every run above already asserts it implicitly (the stub serves a different
# ledger to an unpinned call), so this run names the two halves the reviewer's
# finding turns on: the AMBIENT database is neither read nor written, and no bead
# call escaped the pin at all — not the candidate list, the session-bead list, the
# read-back, the flag, or the repair.
seed_beads
seed_roster
: > "$TMP/unpinned"
bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>&1
eq "$(assignee_of b1)" "$CANON"        "with GC_RIG set, the rig's own stranded handoff is repaired"
eq "$(amb_assignee_of amb1)" "su/refinery" "a same-shaped bead in the AMBIENT ledger is never touched"
eq "$(wc -l < "$TMP/unpinned" | tr -d ' ')" "0" "no bead call is issued without the rig pin"

# --- Run 11: an explicit --rig overrides the environment. -----------------
seed_beads
: > "$TMP/unpinned"
GC_RIG="wrongrig" bash "$SCRIPT" --refinery "$CANON" --rig "$FAKE_RIG" >/dev/null 2>&1
eq "$(assignee_of b1)" "$CANON" "--rig overrides \$GC_RIG for every bead call"
eq "$(wc -l < "$TMP/unpinned" | tr -d ' ')" "0" "the overridden pin is applied to every bead call"

# --- Run 12: an HQ-only city (no rig anywhere) still works unpinned. ------
# The pin is a default, not a requirement: with no $GC_RIG and no --rig there is
# no rig to scope to, and the pass must still run against the ambient ledger
# rather than silently skipping every bead.
seed_beads
: > "$TMP/unpinned"
env -u GC_RIG bash "$SCRIPT" --refinery "$CANON" >/dev/null 2>&1
eq "$(amb_assignee_of amb1)" "$CANON" "with no rig configured the pass falls back to the ambient ledger"
eq "$(assignee_of b1)" "su/refinery"  "and it does not reach into a rig it was never given"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
