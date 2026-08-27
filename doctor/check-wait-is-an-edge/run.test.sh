#!/usr/bin/env bash
# Hermetic test for doctor/check-wait-is-an-edge (I1). Stub gc/bd; no live city.
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

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha/.beads" "$TMP/beta/.beads"
# `aa-tool` is a rig whose NAME matches the id shape, which is the collision the
# known-identifier filter exists for.
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","prefix":"aa","path":"$TMP/alpha","suspended":false},
         {"name":"beta","prefix":"bb","path":"$TMP/beta","suspended":false},
         {"name":"aa-tool","prefix":"","path":"","suspended":false}]}
EOF

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
# `show` serves <store>.show.json when present, so a fixture can render an edge
# in the bd-show spelling ({dependency_type,id}) that bd-list never emits.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
sub="${1:-}"; shift || true
db=""; status=""; prev=""; ids=()
for a in "$@"; do
  case "$prev" in
    --db) db="$a" ;;
    --status|-s) status="$a" ;;
    *) case "$a" in --*) ;; *) ids+=("$a") ;; esac ;;
  esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
case "$sub" in
  list)
    f="$STORES/$name.json"; if [ ! -f "$f" ]; then printf '[]'; exit 0; fi
    # `list` FILTERS BY STATUS, because that is the thing under test: a stub
    # that served every row would pass this suite just as happily with the scan
    # narrowed back to open. Unfiltered means open only and an unknown value is
    # refused, both as real bd behaves — a typo in the status list must fail the
    # store closed here too, not quietly select nothing.
    sel="${status:-open}"
    IFS=, read -ra want <<< "$sel"
    for one in "${want[@]}"; do
      case "$one" in
        open|in_progress|blocked|deferred|closed|pinned|hooked) ;;
        *) printf 'Error: invalid status "%s"\n' "$one" >&2; exit 1 ;;
      esac
    done
    # The row's status is bound BEFORE the pipe: read as `.status` to the right
    # of one, it would resolve against the split array and select every row.
    if out=$(jq -c --arg sel "$sel" '[ .[] | select((.status // "open") as $st | ($sel | split(",")) | index($st) != null) ]' < "$f" 2>/dev/null); then
      printf '%s' "$out"
    else
      # A fixture carrying RAW control bytes is not parseable JSON and cannot be
      # filtered here. It passes through for run.sh's own scrubber to face,
      # which is the property such a fixture exists to test.
      cat "$f"
    fi ;;
  show)
    f="$STORES/$name.show.json"; [ -f "$f" ] || f="$STORES/$name.json"
    if [ ! -f "$f" ] || [ "${#ids[@]}" -eq 0 ]; then
      printf '{"error":"no issues found matching the provided IDs"}'; exit 1
    fi
    echo "${#ids[@]}" >> "${SHOW_CALLS:-/dev/null}"
    # Real bd reads a DB and emits parseable JSON, so the stub scrubs the raw
    # control bytes a fixture puts in the LIST payload before parsing it here.
    out=$(scrub < "$f" \
          | jq -c '[ .[] | select(.id as $i | ($ARGS.positional | index($i))) ]' --args "${ids[@]}")
    if [ "$out" = "[]" ]; then
      printf '{"error":"no issues found matching the provided IDs"}'; exit 1
    fi
    printf '%s' "$out" ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"
run_check() { RIGS_JSON="$TMP/rigs.json" bash "$CHECK" 2>&1; }
store() { printf '%s' "$1" > "$TMP/stores/alpha.json"; rm -f "$TMP/stores/alpha.show.json"; }
bstore() { printf '%s' "$1" > "$TMP/stores/beta.json"; }
reset_beta() { printf '[]' > "$TMP/stores/beta.json"; rm -f "$TMP/stores/beta.show.json"; }
reset_beta

# --- 1. a clean store passes ---------------------------------------------
store '[{"id":"aa-101","status":"open","metadata":{}},
        {"id":"aa-202","status":"open","metadata":{"gc.takeaway":"routed, nothing pending"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store with no stated wait passes"
has "$OUT" "OK:" "the pass message is the OK line"

# --- 2. RULE A: a wait-declaring KEY with no edge --------------------------
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"}},
        {"id":"aa-202","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a blocked_on key naming a bead with no edge is an ERROR"
has "$OUT" "aa-101" "the finding names the waiting bead"
has "$OUT" "aa-202" "the finding names the bead waited on"
has "$OUT" "blocked_on" "the finding names the metadata key that stated the wait"
has "$OUT" "aa-202 is open" "an OPEN target reports as the unedged case"

# --- 3. RULE A: the same wait on an already-CLOSED bead --------------------
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"}},
        {"id":"aa-202","status":"closed","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a wait on a CLOSED bead with no edge is an ERROR"
has "$OUT" "already CLOSED" "the frozen case is called out separately"

# --- 4. a BLOCKING edge in EITHER direction satisfies the invariant --------
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"},
         "dependencies":[{"type":"blocks","depends_on_id":"aa-202"}]},
        {"id":"aa-202","status":"open","metadata":{}}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "0" "a forward edge satisfies the wait"
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"}},
        {"id":"aa-202","status":"open","metadata":{},
         "dependencies":[{"type":"blocks","depends_on_id":"aa-101"}]}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "0" "an edge from the OTHER side also satisfies it"
# type=blocks is the only type that holds a bead out of `bd ready`, so every
# other type records the relation while leaving the wait as unanswerable as the
# bare string. Both projections are filtered, so both are pinned here.
for t in tracks parent-child related; do
    store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"},
             "dependencies":[{"type":"'"$t"'","depends_on_id":"aa-202"}]},
            {"id":"aa-202","status":"open","metadata":{}}]'
    eq "$(run_check >/dev/null 2>&1; echo $?)" "2" "a $t edge on the source does not satisfy the wait"
    store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"}},
            {"id":"aa-202","status":"open","metadata":{},
             "dependencies":[{"type":"'"$t"'","depends_on_id":"aa-101"}]}]'
    eq "$(run_check >/dev/null 2>&1; echo $?)" "2" "a reverse $t edge does not satisfy it either"
done
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"},
         "dependencies":[{"type":"tracks","depends_on_id":"aa-202"}]},
        {"id":"aa-202","status":"open","metadata":{}}]'
OUT=$(run_check)
has "$OUT" 'no `blocks` edge records it' "the finding says which edge type is missing, not that there is none"
# A wait that carries BOTH kinds is satisfied: the filter drops the tracks row,
# not the whole bead's edge list.
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"},
         "dependencies":[{"type":"tracks","depends_on_id":"aa-202"},
                         {"type":"blocks","depends_on_id":"aa-202"}]},
        {"id":"aa-202","status":"open","metadata":{}}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "0" "a blocks edge beside a tracks edge still satisfies the wait"

# --- 5. both edge spellings are read --------------------------------------
# bd list renders {type,depends_on_id}; bd show renders {dependency_type,id}
# for the same edge. Reading one spelling only reports every edged wait.
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"}},
        {"id":"aa-202","status":"open","metadata":{}}]'
cat > "$TMP/stores/alpha.show.json" <<'EOF'
[{"id":"aa-202","status":"open","metadata":{},"dependencies":[{"dependency_type":"blocks","id":"aa-101"}]}]
EOF
OUT=$(run_check); RC=$?
eq "$RC" "0" "an edge rendered in the bd-show spelling still counts"
# The type is keyed `.dependency_type` in that spelling. Reading only `.type`
# would leave every candidate-side edge bd show renders unfiltered.
cat > "$TMP/stores/alpha.show.json" <<'EOF'
[{"id":"aa-202","status":"open","metadata":{},"dependencies":[{"dependency_type":"tracks","id":"aa-101"}]}]
EOF
eq "$(run_check >/dev/null 2>&1; echo $?)" "2" "a NON-blocking edge in that spelling is refused, not passed"
rm -f "$TMP/stores/alpha.show.json"
# Both projections read both spellings, so both are pinned to. The source side
# is fed by bd list today; a source edge keyed the other way must still count,
# or a change of listing spelling reports every edged wait in the city as
# unedged.
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"},
         "dependencies":[{"dependency_type":"blocks","id":"aa-202"}]},
        {"id":"aa-202","status":"open","metadata":{}}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "0" "a SOURCE-side edge in the bd-show spelling counts too"

# --- 6. RULE B: the bead's own status prose -------------------------------
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"held, waiting on aa-202 to land"}},
        {"id":"aa-202","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "wait language in the bead's own takeaway is an ERROR"
has "$OUT" "waiting on aa-202" "the finding quotes the phrase it matched"
store '[{"id":"aa-101","status":"open","metadata":{"blocked_reason":"blocked by aa-202 until it lands"}},
        {"id":"aa-202","status":"open","metadata":{}}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "2" "a *_reason value is read as the bead's own prose"

# --- 7. the verb is bounded on BOTH sides ---------------------------------
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"unblocked by aa-202, shipping"}},
        {"id":"aa-202","status":"open","metadata":{}}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "0" "\"unblocked by\" does not match \"blocked by\""
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"blocked only on mechanism, see aa-202"}},
        {"id":"aa-202","status":"open","metadata":{}}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "0" "a verb matching a PREFIX of a longer word is not a wait"

# --- 8. a wait whose stated subject is ANOTHER bead is not this bead's -----
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"survey: aa-303 is blocked by aa-202"}},
        {"id":"aa-202","status":"open","metadata":{}},
        {"id":"aa-303","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a wait attributed to a named third party is not reported against the writer"
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"aa-101 is blocked by aa-202"}},
        {"id":"aa-202","status":"open","metadata":{}}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "2" "a wait whose named subject IS this bead is still reported"

# --- 9. a hierarchical subject id does not hide itself --------------------
# The sentence boundary is a period followed by space or end of line. A bare
# period would fall INSIDE aa-909.4 and put the subject outside the window.
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"* aa-909.4 -- collection bead, blocked by aa-202"}},
        {"id":"aa-202","status":"open","metadata":{}},
        {"id":"aa-909.4","status":"open","metadata":{}}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "0" "a subject whose id contains a dot is still seen as the subject"

# --- 10. EVERY id in a list, not just the first ---------------------------
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"blocked by aa-202, aa-303 and aa-404"},
         "dependencies":[{"type":"blocks","depends_on_id":"aa-202"}]},
        {"id":"aa-202","status":"open","metadata":{}},
        {"id":"aa-303","status":"open","metadata":{}},
        {"id":"aa-404","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a list after one verb is examined past its first member"
hasnt "$OUT" "aa-202," "the edged first member is not reported"
has "$OUT" "aa-303" "the second list member is judged"
has "$OUT" "aa-404" "the third list member is judged"

# --- 11. a sentence-final period is not part of the id --------------------
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"awaiting aa-202."}},
        {"id":"aa-202","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a trailing period is stripped so the id still resolves"
hasnt "$OUT" "resolves to no bead" "it is a real wait, not an unresolved note"

# --- 12. NOTES ARE NOT SCANNED -------------------------------------------
# Survey and audit beads record other beads' waits in first-person wording, so
# a free-text note cannot be attributed to the bead carrying it.
store '[{"id":"aa-101","status":"open","notes":"aa-101 is blocked by aa-202 and always will be","metadata":{}},
        {"id":"aa-202","status":"open","metadata":{}}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "0" "wait language in free-form notes is not a finding"

# --- 13. a name that merely shares the id SHAPE ---------------------------
store '[{"id":"aa-101","status":"open","metadata":{"gc.takeaway":"blocked on aa-tool being installed"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a rig name matching the id shape is not a wait"
hasnt "$OUT" "aa-tool" "and it is not left as noise in the output either"

# --- 14. an id that resolves nowhere is a NOTE, not a pass and not an error -
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-9999"}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "an unresolvable candidate does not manufacture an error"
has "$OUT" "resolves to no bead" "but it is reported as a note"

# --- 15. resolution crosses stores ---------------------------------------
# A candidate resolves in the store its PREFIX names. Looked up store-locally
# a cross-rig wait answers "no issues found" and downgrades to a note.
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"bb-707"}}]'
bstore '[{"id":"bb-707","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a cross-rig wait is resolved in the OWNING store and judged"
hasnt "$OUT" "resolves to no bead" "it is not downgraded to an unresolved note"
bstore '[{"id":"bb-707","status":"open","metadata":{},"dependencies":[{"type":"blocks","depends_on_id":"aa-101"}]}]'
eq "$(run_check >/dev/null 2>&1; echo $?)" "0" "a cross-rig wait that IS edged reads as ok"
reset_beta

# --- 16. batching stays within the chunk bound ---------------------------
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202, aa-303, aa-404, aa-505, aa-606"}},
        {"id":"aa-202","status":"open","metadata":{}},{"id":"aa-303","status":"open","metadata":{}},
        {"id":"aa-404","status":"open","metadata":{}},{"id":"aa-505","status":"open","metadata":{}},
        {"id":"aa-606","status":"open","metadata":{}}]'
: > "$TMP/show-calls"
OUT=$(SHOW_CALLS="$TMP/show-calls" GC_DOCTOR_WAIT_CHUNK=2 run_check); RC=$?
eq "$RC" "2" "a candidate set larger than the chunk bound still yields findings"
for want in aa-202 aa-303 aa-404 aa-505 aa-606; do has "$OUT" "$want" "chunked resolve still judges $want"; done
OVER=$(awk '$1 > 2' "$TMP/show-calls" | wc -l | tr -d ' ')
eq "$OVER" "0" "no bd show batch exceeded the chunk bound"

# --- 17. fail-CLOSED arms -------------------------------------------------
store '[]'
eq "$(RIGS_RC=1 run_check >/dev/null 2>&1; echo $?)" "1" "a failed \`gc rig list\` warns, never passes"
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"}}]'
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped, not clean"
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"
has "$OUT" "NOT checked" "the unparseable store is reported as unchecked"
cat > "$TMP/rigs-noprefix.json" <<EOF
{"rigs":[{"name":"alpha","prefix":"","path":"$TMP/alpha","suspended":false}]}
EOF
store '[]'
OUT=$(RIGS_JSON="$TMP/rigs-noprefix.json" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "a roster with no usable issue prefixes warns rather than guessing"

# --- 18. a suspended rig is skipped, not probed --------------------------
cat > "$TMP/rigs-susp.json" <<EOF
{"rigs":[{"name":"alpha","prefix":"aa","path":"$TMP/alpha","suspended":true},
         {"name":"beta","prefix":"bb","path":"$TMP/beta","suspended":false}]}
EOF
store '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"}},{"id":"aa-202","status":"open","metadata":{}}]'
OUT=$(RIGS_JSON="$TMP/rigs-susp.json" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a suspended rig is skipped rather than probed"
has "$OUT" "suspended" "the skip is noted, not silent"

# --- 19. a rig with no bead store is noted, not silently dropped ---------
cat > "$TMP/rigs-nostore.json" <<EOF
{"rigs":[{"name":"alpha","prefix":"aa","path":"$TMP/alpha","suspended":false},
         {"name":"gamma","prefix":"cc","path":"$TMP/gamma-never-initialised","suspended":false}]}
EOF
store '[{"id":"aa-101","status":"open","metadata":{}}]'
OUT=$(RIGS_JSON="$TMP/rigs-nostore.json" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a rig whose store does not exist does not fail the run"
has "$OUT" "no bead store" "an absent store is reported rather than skipped in silence"

# --- 20. control characters do not cost the store ------------------------
printf '[{"id":"aa-101","status":"open","metadata":{"blocked_on":"aa-202"},"notes":"tab\there\001etc"},
        {"id":"aa-202","status":"open","metadata":{}}]' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a payload carrying raw control characters still yields the finding"
has "$OUT" "aa-101" "the finding survives the control characters"

# --- 21. the scan covers every LIVE status, not just open -----------------
# A wait does not become answerable because the bead stating it was claimed or
# parked. Filtering to `open` drops exactly the waits that have sat long enough
# for their bead to move status, and calls the store clean.
for st in in_progress blocked deferred hooked pinned; do
    store '[{"id":"aa-101","status":"'"$st"'","metadata":{"blocked_on":"aa-202"}},
            {"id":"aa-202","status":"open","metadata":{}}]'
    OUT=$(run_check); RC=$?
    eq "$RC" "2" "an unedged wait stated by a $st bead is reported"
    has "$OUT" "aa-101" "the $st bead is named as the waiter"
done

# --- 22. a CLOSED bead's stated wait is not a finding ---------------------
# Closed is the one status that ends a wait, so the scan stops there rather
# than reaching for --all. This also pins the stub: were --status ignored, the
# closed bead below would be listed and reported, and every case in 21 would
# pass against a scan that never left `open`.
store '[{"id":"aa-101","status":"closed","metadata":{"blocked_on":"aa-202"}},
        {"id":"aa-202","status":"open","metadata":{}}]'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a wait stated by a CLOSED bead is not reported"
hasnt "$OUT" "aa-101" "the closed bead is not named in the output"

echo
echo "check-wait-is-an-edge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
