#!/usr/bin/env bash
# Hermetic test for doctor/check-wait-is-an-edge (I1). Stubs `gc`; no live city.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/pack/lifecycle"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"hq","prefix":"hh","path":"$TMP/hq","hq":true,"suspended":false},
         {"name":"alpha","prefix":"aa","path":"$TMP/alpha","suspended":false},
         {"name":"beta","prefix":"bb","path":"$TMP/beta","suspended":false}]}
EOF

# The stub answers `gc bd` the way the real one does, and refuses what it
# refuses: `--rig` names a RIG and never the HQ entry, an unknown status fails
# the read, and the three hidden bead categories stay hidden unless their
# --include-* flag is passed. A stub that served every row would pass this
# suite just as happily with the scan narrowed back.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
city=""; rig=""
while [ $# -gt 0 ]; do
  case "$1" in
    --city) city="${2:-}"; shift 2 ;;
    --rig)  rig="${2:-}";  shift 2 ;;
    *) break ;;
  esac
done
case "${1:-}" in
  rig) [ "${2:-}" = "list" ] || exit 0
       rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON"; exit 0 ;;
  bd)  shift ;;
  *)   exit 0 ;;
esac
if [ -n "$rig" ]; then
  case "$rig" in
    alpha|beta) store="$rig" ;;
    *) echo "gc bd: rig \"$rig\" not found" >&2; exit 1 ;;
  esac
else
  [ -n "$city" ] || { echo "gc bd: no city" >&2; exit 1; }
  store="hq"
fi
sub="${1:-}"; shift || true
status=""; prev=""; ids=(); gates=0; infra=0; templates=0
for a in "$@"; do
  case "$a" in
    --include-gates) gates=1 ;;
    --include-infra) infra=1 ;;
    --include-templates) templates=1 ;;
  esac
  case "$prev" in
    --status|-s) status="$a" ;;
    *) case "$a" in --*|-n) ;; *) [ "$prev" = "--limit" ] || ids+=("$a") ;; esac ;;
  esac
  prev="$a"
done
[ "$store" = "${BD_FAIL_STORE:-}" ] && exit 3
[ "$sub" = "show" ] && [ -n "${SHOW_FAIL:-}" ] && exit 5
[ "$store" = "${BD_EMPTY_STORE:-}" ] && { printf ''; exit 0; }
[ "$store" = "${BD_JUNK_STORE:-}" ] && { printf 'not json'; exit 0; }
f="$STORES/$store.json"
case "$sub" in
  list)
    [ -f "$f" ] || { printf '[]'; exit 0; }
    sel="${status:-open}"
    IFS=, read -ra want <<< "$sel"
    for one in "${want[@]}"; do
      case "$one" in
        open|in_progress|blocked|deferred|closed|pinned|hooked) ;;
        *) printf 'Error: invalid status "%s"\n' "$one" >&2; exit 1 ;;
      esac
    done
    # Hidden categories are bd's: gate issues, the agent/role/message infra
    # types, and molecules labelled template.
    if out=$(jq -c --arg sel "$sel" --argjson g "$gates" --argjson i "$infra" --argjson t "$templates" '
        [ .[]
          | (.issue_type // "task") as $ty
          | select((.status // "open") as $st | ($sel | split(",")) | index($st) != null)
          | select(($g == 1) or ($ty != "gate"))
          | select(($i == 1) or (([ "agent","role","message" ] | index($ty)) == null))
          | select(($t == 1) or ($ty != "molecule")
                             or (((.labels // []) | index("template")) == null)) ]' < "$f" 2>/dev/null); then
      printf '%s' "$out"
    else
      # A fixture carrying RAW control bytes is not parseable JSON and cannot be
      # filtered here. It passes through for run.sh's own scrubber to face,
      # which is the property such a fixture exists to test.
      cat "$f"
    fi ;;
  show)
    # `show` serves <store>.show.json when present, so a fixture can render an
    # edge in the bd-show spelling ({dependency_type,id}) that list never emits.
    sf="$STORES/$store.show.json"; [ -f "$sf" ] && f="$sf"
    echo "$store:${#ids[@]}" >> "${SHOW_CALLS:-/dev/null}"
    if [ ! -f "$f" ] || [ "${#ids[@]}" -eq 0 ]; then
      printf '{"error":"no issues found matching the provided IDs"}'; exit 1
    fi
    out=$(scrub < "$f" | jq -c '[ .[] | select(.id as $i | ($ARGS.positional | index($i))) ]' --args "${ids[@]}")
    if [ "$out" = "[]" ]; then
      printf '{"error":"no issues found matching the provided IDs"}'; exit 1
    fi
    printf '%s' "$out" ;;
esac
GC
# Nothing in the check may reach for raw `bd`. This one fails every call, so a
# read that skipped `gc` would fail the store closed and be seen.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
echo "raw bd: circuit breaker open" >&2
exit 7
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

cat > "$TMP/pack/lifecycle/lifecycle.toml" <<'TOML'
[machine]
park_route = "human"

[holds]
marker_keys = ["triage.hold", "blocked_reason", "gc.takeaway"]
settled_keys = ["gc.takeaway=gc.takeaway_settled"]
marker_prefixes = ["dispatch_backstop."]
gate_marker_prefix = "check."
gate_hold_verb = "exception"
route_key = "gc.routed_to"
hold_severity = "warn"
TOML

run_check() { RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="${PACK:-$TMP/pack}" bash "$CHECK" 2>&1; }
store()  { printf '%s' "$1" > "$TMP/stores/alpha.json"; rm -f "$TMP/stores/alpha.show.json"; }
showq()  { printf '%s' "$1" > "$TMP/stores/alpha.show.json"; }
bstore() { printf '%s' "$1" > "$TMP/stores/beta.json"; }
hstore() { printf '%s' "$1" > "$TMP/stores/hq.json"; }
reset()  { bstore '[]'; hstore '[]'; rm -f "$TMP/stores/beta.show.json" "$TMP/stores/hq.show.json"; }
reset

# --- 1. a clean store passes ---------------------------------------------
store '[{"id":"aa-101","status":"open","metadata":{}},
        {"id":"aa-202","status":"open","metadata":{"other":"nothing held here"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store with no hold marker passes"
has "$OUT" "OK:" "the pass message is the OK line"
hasnt "$OUT" "circuit breaker" "no read reached for raw bd"

# --- 2. a marker with no edge is the finding ------------------------------
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"waiting for the operator"}},
        {"id":"aa-202","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "1" "a hold marker with no blocks edge warns"
has "$OUT" "aa-101" "the finding names the held bead"
has "$OUT" "triage.hold=waiting for the operator" "and the marker that holds it"
has "$OUT" "no \`blocks\` edge" "and says the graph carries nothing"

# --- 3. the same marker beside a live blocks edge is clean ----------------
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"waiting for the operator"},
         "dependencies":[{"issue_id":"aa-101","depends_on_id":"aa-202","type":"blocks"}]},
        {"id":"aa-202","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a hold marker beside a live blocks edge is not a finding"

# --- 4. the blocker has closed: the terminal degree, and an ERROR ----------
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"waiting for the operator"},
         "dependencies":[{"issue_id":"aa-101","depends_on_id":"aa-909","type":"blocks"}]}]'
showq '[{"id":"aa-909","status":"closed","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "1" "a hold whose only blocker has closed is a finding"
has "$OUT" "aa-909 is closed" "the finding names the dead blocker and its status"
has "$OUT" "rests on the string alone" "and says what the state now is"
has "$OUT" "whose every \`blocks\` blocker is gone" "and is grouped apart from the unedged half"

# --- 5. only a blocks edge answers a hold ---------------------------------
for t in tracks parent-child related; do
  store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"held"},
           "dependencies":[{"issue_id":"aa-101","depends_on_id":"aa-202","type":"'"$t"'"}]},
          {"id":"aa-202","status":"open","metadata":{}}]'
  OUT=$(run_check); RC=$?
  eq "$RC" "1" "a $t edge does not answer a hold"
done

# --- 6. the edge is read in the bd-show spelling too -----------------------
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"held"},
         "dependencies":[{"id":"aa-202","dependency_type":"blocks"}]},
        {"id":"aa-202","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a blocks edge keyed dependency_type/id is read"

# --- 7. every declared marker shape, and the values that are NOT holds -----
held() { # <metadata-json> <label>
  store '[{"id":"aa-101","status":"open","metadata":'"$1"'}]'
  OUT=$(run_check); RC=$?
  eq "$RC" "1" "$2 is a hold"
  has "$OUT" "aa-101" "$2 names the held bead"
}
notheld() { # <metadata-json> <label>
  store '[{"id":"aa-101","status":"open","metadata":'"$1"'}]'
  OUT=$(run_check); RC=$?
  eq "$RC" "0" "$2 is not a hold"
}
held '{"triage.hold":"x"}'                       "triage.hold"
held '{"blocked_reason":"the cap fired"}'        "blocked_reason"
held '{"gc.takeaway":"needs an operator ruling"}' "gc.takeaway"
held '{"gc.routed_to":"human"}'                  "gc.routed_to on the park route"
held '{"check.codex":"exception@abc123"}'        "check.<g> at the exception verb"
held '{"dispatch_backstop.codex":"5@abc123"}'    "dispatch_backstop.<g>"
notheld '{"gc.routed_to":"alpha/alpha.polecat"}' "gc.routed_to on a pool"
notheld '{"check.codex":"green@abc123"}'         "a green gate marker"
notheld '{"check.codex":"fixable@abc123"}'       "a fixable gate marker"
notheld '{"blocked_reason":""}'                  "an empty blocked_reason"
notheld '{"gc.takeaway":""}'                     "an empty gc.takeaway"
notheld '{"dispatch_count":"5"}'                 "a dispatch tally with no backstop stamp"

# --- 8. every non-closed status is in scope -------------------------------
for st in open in_progress blocked deferred hooked pinned; do
  store '[{"id":"aa-101","status":"'"$st"'","metadata":{"triage.hold":"held"}}]'
  OUT=$(run_check); RC=$?
  eq "$RC" "1" "a held bead in status=$st is scanned"
done
# The guard mutated out: the stub refuses a status it does not know, so a scan
# narrowed to a typo fails the store closed rather than reading as clean.
OUT=$(printf '[]' > "$TMP/stores/alpha.json"; gc --city "$TMP" --rig alpha bd list --status nonesuch --json 2>&1); RC=$?
eq "$RC" "1" "the stub refuses an unknown status, so a narrowed scan cannot read as clean"

# --- 9. the hidden bead categories are scanned ----------------------------
for cat in '"issue_type":"gate"' '"issue_type":"agent"' '"issue_type":"molecule","labels":["template"]'; do
  store '[{"id":"aa-101","status":"open",'"$cat"',"metadata":{"triage.hold":"held"}}]'
  OUT=$(run_check); RC=$?
  eq "$RC" "1" "a held bead with $cat is scanned"
done
# Vacuity guard: the stub really does hide those rows without the flags, so the
# assertions above are testing the flags and not a stub that serves everything.
store '[{"id":"aa-101","status":"open","issue_type":"gate","metadata":{"triage.hold":"held"}}]'
OUT=$(gc --city "$TMP" --rig alpha bd list --status open --json 2>&1)
eq "$OUT" "[]" "without --include-gates the stub hides the gate bead"

# --- 10. a live blocker in a hidden category still answers the hold --------
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"held"},
         "dependencies":[{"issue_id":"aa-101","depends_on_id":"aa-777","type":"blocks"}]}]'
showq '[{"id":"aa-777","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a blocker the listing did not carry, but the store reports live, answers the hold"
has "$OUT" "the live listing did not carry aa-777 (open)" "and the short listing is noted as its own defect"

# --- 11. a cross-store blocker holds nothing ------------------------------
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"held"},
         "dependencies":[{"issue_id":"aa-101","depends_on_id":"bb-500","type":"blocks"}]}]'
bstore '[{"id":"bb-500","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "1" "a hold whose only blocker lives in another store is a finding"
has "$OUT" "bb-500 is in no store this scope can read" "the finding says the foreign blocker resolved nowhere here"
reset

# --- 12. the HQ store is read through --city, never as a rig --------------
hstore '[{"id":"hh-1","status":"open","metadata":{"gc.routed_to":"human"}}]'
store '[]'
OUT=$(run_check); RC=$?
eq "$RC" "1" "a held bead in the HQ store is found"
has "$OUT" "hh-1" "the HQ finding names its bead"
hasnt "$OUT" "rig \"hq\" not found" "the HQ entry was never addressed as a rig"
has "$OUT" "across 3 store(s)" "all three stores were checked"
reset

# --- 13. the marker list comes from lifecycle.toml ------------------------
mkdir -p "$TMP/pack2/lifecycle"
cat > "$TMP/pack2/lifecycle/lifecycle.toml" <<'TOML'
[machine]
park_route = "parked"

[holds]
marker_keys = ["site.hold"]
marker_prefixes = ["quarantine."]
gate_marker_prefix = "gate."
gate_hold_verb = "waived"
route_key = "routed"
TOML
store '[{"id":"aa-101","status":"open","metadata":{"site.hold":"declared only in the fixture"}}]'
OUT=$(PACK="$TMP/pack2" run_check); RC=$?
eq "$RC" "1" "a marker declared only in lifecycle.toml is asserted"
has "$OUT" "site.hold" "and the finding names it"
store '[{"id":"aa-101","status":"open","metadata":{"quarantine.a":"x"}}]'
OUT=$(PACK="$TMP/pack2" run_check); RC=$?
eq "$RC" "1" "a declared marker PREFIX is asserted"
store '[{"id":"aa-101","status":"open","metadata":{"gate.codex":"waived@abc"}}]'
OUT=$(PACK="$TMP/pack2" run_check); RC=$?
eq "$RC" "1" "the declared gate prefix and hold verb are asserted"
store '[{"id":"aa-101","status":"open","metadata":{"routed":"parked"}}]'
OUT=$(PACK="$TMP/pack2" run_check); RC=$?
eq "$RC" "1" "the declared route key and park_route are asserted"
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"x","gc.takeaway":"y"}}]'
OUT=$(PACK="$TMP/pack2" run_check); RC=$?
eq "$RC" "0" "a marker the declaration drops is no longer asserted"

# A declaration that names only marker_keys does not inherit the rest: the
# built-ins are a whole substitute for an unreadable file, never a filler for
# fields a declaration dropped on purpose.
mkdir -p "$TMP/pack5/lifecycle"
{ echo '[machine]'; echo 'park_route = "human"'; echo; echo '[holds]'
  echo 'marker_keys = ["site.hold"]'; } > "$TMP/pack5/lifecycle/lifecycle.toml"
for m in '{"dispatch_backstop.codex":"5@abc"}' '{"check.codex":"exception@abc"}' '{"gc.routed_to":"human"}'; do
  store '[{"id":"aa-101","status":"open","metadata":'"$m"'}]'
  OUT=$(PACK="$TMP/pack5" run_check); RC=$?
  eq "$RC" "0" "a declaration that drops a marker does not inherit it: $m"
done
store '[{"id":"aa-101","status":"open","metadata":{"site.hold":"x"}}]'
OUT=$(PACK="$TMP/pack5" run_check); RC=$?
eq "$RC" "1" "...and the marker it does declare still asserts"

# Each half of a two-field arm is required. A gate prefix with no hold verb
# declares no gate hold, so nothing under that prefix is one — including the
# value an unguarded `startswith($verb + "@")` would match on an empty verb.
mkdir -p "$TMP/pack6/lifecycle"
{ echo '[machine]'; echo 'park_route = "human"'; echo; echo '[holds]'
  echo 'marker_keys = ["site.hold"]'; echo 'gate_marker_prefix = "check."'; } > "$TMP/pack6/lifecycle/lifecycle.toml"
store '[{"id":"aa-101","status":"open","metadata":{"check.codex":"@abc"}}]'
OUT=$(PACK="$TMP/pack6" run_check); RC=$?
eq "$RC" "0" "a gate prefix with no hold verb declares no gate hold"
# A route key with no park route likewise declares no route hold. The value to
# test with is the empty string, because clearing a route by setting it empty
# does not remove the key, so live beads really do carry it.
mkdir -p "$TMP/pack7/lifecycle"
{ echo '[holds]'; echo 'marker_keys = ["site.hold"]'; echo 'route_key = "gc.routed_to"'; } > "$TMP/pack7/lifecycle/lifecycle.toml"
store '[{"id":"aa-101","status":"open","metadata":{"gc.routed_to":""}}]'
OUT=$(PACK="$TMP/pack7" run_check); RC=$?
eq "$RC" "0" "a route key with no park route declares no route hold"

# --- 14. no declaration: the built-in list, and a note that says so -------
mkdir -p "$TMP/pack3"
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"x"}}]'
OUT=$(PACK="$TMP/pack3" run_check); RC=$?
eq "$RC" "1" "with no lifecycle.toml the built-in marker list still asserts"
has "$OUT" "built-in list" "and the substitution is noted rather than silent"

# --- 15. an unreadable probe warns and never passes -----------------------
store '[{"id":"aa-101","status":"open","metadata":{}}]'
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a store whose listing fails warns"
has "$OUT" "could not list live beads (rc=3)" "and names the read that failed and its status"
has "$OUT" "was NOT checked" "and says the store was not checked"
has "$OUT" "across 2 store(s)" "the checked count excludes it"
OUT=$(BD_EMPTY_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an empty-STRING listing is not an empty store"
has "$OUT" "the live listing returned no output" "and is told apart from a store that answered []"
OUT=$(BD_JUNK_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a listing that is not a JSON array warns"
has "$OUT" "is not a JSON array" "and says what was wrong with it"
OUT=$(BD_FAIL_STORE=alpha BD_EMPTY_STORE=beta BD_JUNK_STORE=hq run_check); RC=$?
eq "$RC" "1" "with no store readable the check cannot determine the answer"
has "$OUT" "No bead store could be examined." "and says exactly that"

# --- 16. a blocker resolve that FAILS fails the store closed --------------
# The listing is served and `show` is then refused. A partial resolve would
# report a live blocker as a dead one, which is an invented error, and would
# bury the real findings behind it.
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"held"},
         "dependencies":[{"issue_id":"aa-101","depends_on_id":"aa-909","type":"blocks"}]}]'
OUT=$(SHOW_FAIL=1 run_check); RC=$?
eq "$RC" "1" "a store whose blocker resolve fails is not checked"
has "$OUT" "could not resolve the blockers" "and says which probe failed"
hasnt "$OUT" "aa-101" "no finding is invented from the unresolved half"

# --- 17. the rig roster itself ------------------------------------------
OUT=$(RIGS_RC=4 run_check); RC=$?
eq "$RC" "1" "a failed rig listing cannot determine the answer"
has "$OUT" "gc rig list" "and names the probe that failed"
printf '{"rigs":[]}' > "$TMP/rigs2.json"
OUT=$(RIGS_JSON="$TMP/rigs2.json" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "an empty roster cannot determine the answer"

# --- 18. a suspended rig is skipped, not read ----------------------------
cat > "$TMP/rigs3.json" <<EOF
{"rigs":[{"name":"hq","prefix":"hh","path":"$TMP/hq","hq":true,"suspended":false},
         {"name":"alpha","prefix":"aa","path":"$TMP/alpha","suspended":true}]}
EOF
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"held"}}]'
OUT=$(RIGS_JSON="$TMP/rigs3.json" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a suspended rig is skipped, and its beads are not read"
has "$OUT" "skipped (suspended" "and the skip is noted"
has "$OUT" "across 1 store(s)" "the checked count counts only what was read"

# --- 19. raw control bytes do not abort the scan -------------------------
printf '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"held\001here"}}]' > "$TMP/stores/alpha.json"
rm -f "$TMP/stores/alpha.show.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a payload carrying a raw C0 byte is still scanned"
has "$OUT" "aa-101" "and the finding survives the scrub"

# --- 20. the detail cap prints less, never finds less ---------------------
rows=""
for i in 1 2 3 4 5 6; do
  rows="$rows{\"id\":\"aa-10$i\",\"status\":\"open\",\"metadata\":{\"triage.hold\":\"held\"}},"
done
store "[${rows%,}]"
OUT=$(GC_DOCTOR_WAIT_DETAILS=2 run_check); RC=$?
eq "$RC" "1" "the capped run still warns"
has "$OUT" "6 finding(s)" "the headline count is taken before the cap"
has "$OUT" "and 4 more, not printed" "and the remainder is counted, not dropped"
OUT=$(GC_DOCTOR_WAIT_DETAILS=0 run_check)
hasnt "$OUT" "not printed" "cap 0 prints every finding"
has "$OUT" "aa-106" "including the last one"

# --- 21. the reporting posture is declared, not compiled in ---------------
mkdir -p "$TMP/pack4/lifecycle"
posture_pack() { # <hold_severity line>
  { echo '[machine]'; echo 'park_route = "human"'; echo; echo '[holds]'
    echo 'marker_keys = ["triage.hold"]'; echo "$1"; } > "$TMP/pack4/lifecycle/lifecycle.toml"
}
store '[{"id":"aa-101","status":"open","metadata":{"triage.hold":"held"}}]'
posture_pack 'hold_severity = "error"'
OUT=$(PACK="$TMP/pack4" run_check); RC=$?
eq "$RC" "2" "hold_severity=error makes a finding an error"
hasnt "$OUT" "reported as a warning" "and the headline drops the warn-only clause"
posture_pack 'hold_severity = "warn"'
OUT=$(PACK="$TMP/pack4" run_check); RC=$?
eq "$RC" "1" "hold_severity=warn makes the same finding a warning"
has "$OUT" "while the conversion backlog stands" "and the headline says why"
posture_pack 'hold_severity = "loud"'
OUT=$(PACK="$TMP/pack4" run_check); RC=$?
eq "$RC" "1" "an undeclared posture reports as a warning rather than guessing"
has "$OUT" "is not one of warn|error" "and says the declaration is unreadable"
posture_pack '# no posture declared'
OUT=$(PACK="$TMP/pack4" run_check); RC=$?
eq "$RC" "1" "with no posture declared the built-in one warns"
# The same store, clean, under the error posture: a posture is not a finding.
store '[{"id":"aa-101","status":"open","metadata":{}}]'
posture_pack 'hold_severity = "error"'
OUT=$(PACK="$TMP/pack4" run_check); RC=$?
eq "$RC" "0" "the error posture still passes a store with nothing held"

# --- 22. the settled-key: a marker its own writer answered ----------------
# The two shapes one ritual produces. A sign-off stamps a headline on the
# subject it settled and on the one it parked for a person, and the sentence
# reads the same either way; the settled-key is the writer saying which, and
# only the parked one is a wait nothing re-asks.
notheld '{"gc.takeaway":"resolved — no human action was needed","gc.takeaway_settled":"1"}' \
        "a takeaway its writer settled"
held    '{"gc.takeaway":"retention policy UNRULED — needs the operator"}' \
        "a takeaway that parks a bead for a person"
held    '{"gc.takeaway":"parked","gc.takeaway_settled":""}' \
        "a takeaway whose settled-key is empty"
# The key answers its OWN marker and nothing else, so a bead holding two
# markers is still held by the other one.
held '{"gc.takeaway":"settled","gc.takeaway_settled":"1","triage.hold":"waiting on the migration"}' \
     "a settled takeaway beside another marker"
OUT=$(run_check)
hasnt "$OUT" "gc.takeaway=settled" "and the settled marker is not listed among what holds it"
held '{"gc.takeaway":"settled","gc.takeaway_settled":"1","gc.routed_to":"human"}' \
     "a settled takeaway on a bead parked on the park route"
# A settled marker is answered, not exempted: the bead is judged on every other
# marker it carries, and one whose only marker is settled leaves the store clean
# rather than unscanned.
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"settled","gc.takeaway_settled":"1"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store whose only marker is a settled one passes"
has "$OUT" "across 3 store(s)" "and the store was scanned, not skipped"

# The pairing is DECLARED, like the markers it governs. A declaration that
# names markers and no pairing answers no marker with a key: the settled stamp
# is data nothing has been told to read.
mkdir -p "$TMP/pack8/lifecycle"
{ echo '[holds]'; echo 'marker_keys = ["gc.takeaway"]'; } > "$TMP/pack8/lifecycle/lifecycle.toml"
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"settled","gc.takeaway_settled":"1"}}]'
OUT=$(PACK="$TMP/pack8" run_check); RC=$?
eq "$RC" "1" "a declaration with no settled_keys answers no marker with a key"
# Half a pair is worse than none — a marker answered by a key no writer stamps
# reads every hold as settled — so a malformed entry is dropped.
mkdir -p "$TMP/pack9/lifecycle"
{ echo '[holds]'; echo 'marker_keys = ["gc.takeaway"]'
  echo 'settled_keys = ["gc.takeaway=", "=gc.takeaway_settled", "gc.takeaway"]'
  } > "$TMP/pack9/lifecycle/lifecycle.toml"
OUT=$(PACK="$TMP/pack9" run_check); RC=$?
eq "$RC" "1" "a settled_keys entry missing either half is dropped"
# A pairing declared for a marker of the declaration's own choosing.
mkdir -p "$TMP/pack10/lifecycle"
{ echo '[holds]'; echo 'marker_keys = ["site.hold"]'
  echo 'settled_keys = ["site.hold=site.answered"]'; } > "$TMP/pack10/lifecycle/lifecycle.toml"
store '[{"id":"aa-101","status":"open","metadata":{"site.hold":"x","site.answered":"1"}}]'
OUT=$(PACK="$TMP/pack10" run_check); RC=$?
eq "$RC" "0" "a pairing declared only in lifecycle.toml is honored"
store '[{"id":"aa-101","status":"open","metadata":{"site.hold":"x"}}]'
OUT=$(PACK="$TMP/pack10" run_check); RC=$?
eq "$RC" "1" "...and the same marker without its key still holds"
# With no lifecycle.toml at all the built-in pairing stands in with the
# built-in markers, so the standby list is the shipped one.
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"settled","gc.takeaway_settled":"1"}}]'
OUT=$(PACK="$TMP/pack3" run_check); RC=$?
eq "$RC" "0" "the built-in list carries the built-in pairing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
