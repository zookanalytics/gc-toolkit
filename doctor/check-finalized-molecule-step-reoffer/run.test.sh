#!/usr/bin/env bash
# Hermetic test for doctor/check-finalized-molecule-step-reoffer (tk-ciuad).
#
# THE BUG the check guards: a graph.v2 step bead is left OPEN under a molecule
# whose root already CLOSED. `gc hook --claim` has no gate on the root's state,
# and a step is offer-able through the ROOT's route even when its own
# `gc.routed_to` is blank — so the pool hands the step to a fresh polecat and it
# re-executes in full against a molecule that has no reader left. tk-ciuad's
# instance burned four polecat incarnations re-running a city-wide census before
# a human noticed; the never-closed variant sat for four days in one rig and
# seven in another, reported by nothing.
#
# What is exercised here:
#   * both ERROR arms, kept distinct — REOPENED (the step carries `gc.outcome`,
#     so it completed and was reset afterwards) and NEVER-CLOSED (no outcome).
#     They are different defects with different fixes and must not be merged
#     into one message;
#   * the grouping — one line per (molecule, shape), so a seven-step strand
#     cannot bury the single-step reopen loop that is the more urgent finding;
#   * the QUERY itself. If `--status open`, `--has-metadata-key
#     gc.root_bead_id` or `--limit 0` drifts, the check silently stops seeing
#     the beads it exists to find and reports a clean city;
#   * the grace window, in BOTH directions. Finalize closes the root seconds
#     BEFORE the terminal step's own close lands, so a zero-grace check would
#     flag every healthy molecule at the instant it completes — and a grace
#     window that swallowed an old strand would restore the original silence;
#   * every shape that must NOT be flagged: an open step under a LIVE root, a
#     closed step under a closed root, and a store with no step beads at all;
#   * the QUIET path — a store with nothing wrong still exits 0 and names no
#     bead. A check that only ever gets exercised on dirty fixtures can pass its
#     tests while flagging a healthy city;
#   * the fail-CLOSED arms. Every probe that cannot be READ must warn, never
#     pass: an unreadable store is exactly as silent as no check at all, which
#     is the condition this check exists to remove.
#
# No live city, Dolt, network, or beads — only jq, stub `gc`/`bd`, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$CHECK" ] || chmod +x "$CHECK" 2>/dev/null

CITY="$TMP/testcity"
mkdir -p "$CITY" "$TMP/steps" "$TMP/roots" "$TMP/bin"

# Timestamps are computed, never hardcoded: the whole point of the grace window
# is its distance from NOW, and a frozen literal would drift into or out of the
# window depending on when the suite runs.
iso_at() { # iso_at <seconds-ago>
    local ago="$1" now
    now=$(date -u +%s)
    date -u -d "@$(( now - ago ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -r "$(( now - ago ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

LONG_AGO=$(iso_at 86400)   # a day — unambiguously past any settle window
JUST_NOW=$(iso_at 5)       # five seconds — a molecule mid-finalize

cat > "$TMP/rigs.json" <<EOF
{"schema_version":"1","ok":true,"rigs":[
  {"name":"testcity","path":"$CITY"},
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"}
]}
EOF

# --- Fixture builders --------------------------------------------------------
# step <id> <root-id> [outcome] — an OPEN step bead. An outcome present means it
# already ran to completion, which is the REOPENED discriminator.
step() {
    local id="$1" root="$2" outcome="${3:-}"
    if [ -n "$outcome" ]; then
        printf '{"id":"%s","status":"open","metadata":{"gc.root_bead_id":"%s","gc.outcome":"%s"}}' "$id" "$root" "$outcome"
    else
        printf '{"id":"%s","status":"open","metadata":{"gc.root_bead_id":"%s"}}' "$id" "$root"
    fi
}
# step_xstore <id> <root-id> <store-ref> — a step whose root lives elsewhere.
step_xstore() {
    printf '{"id":"%s","status":"open","metadata":{"gc.root_bead_id":"%s","gc.root_store_ref":"%s"}}' "$1" "$2" "$3"
}
# root <id> <status> [closed_at]
root() {
    local id="$1" status="$2" closed="${3:-}"
    if [ -n "$closed" ]; then
        printf '{"id":"%s","status":"%s","closed_at":"%s"}' "$id" "$status" "$closed"
    else
        printf '{"id":"%s","status":"%s"}' "$id" "$status"
    fi
}
put() { # put <steps|roots> <store> <json>... — writes the array file
    local kind="$1" name="$2"; shift 2
    local IFS=,
    printf '[%s]' "$*" > "$TMP/$kind/$name.json"
}
clear_store() { rm -f "$TMP/steps/$1.json" "$TMP/roots/$1.json"; }

# --- Stubs -------------------------------------------------------------------
# `gc rig list`, answering from a file so a scenario can hand over malformed
# bytes. RIGS_RC forces a failed probe.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list")
      rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"
      cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# `bd`: `list` answers from $STEPS/<rig>.json and `show` from $ROOTS/<rig>.json,
# both keyed off the --db path. Every invocation appends its full argv to
# $BD_ARGS so the query itself can be asserted. The *_FAIL_STORE knobs make one
# named store's probe fail; BD_EMPTY_STORE makes `list` return nothing at all,
# which is NOT the same as `[]`.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BD_ARGS"
verb="$1"
db=""
prev=""
for a in "$@"; do
  [ "$prev" = "--db" ] && db="$a"
  prev="$a"
done
name=$(basename "$(dirname "$db")")
case "$verb" in
  list)
    [ "$name" = "${BD_LIST_FAIL_STORE:-}" ] && exit 3
    [ "$name" = "${BD_EMPTY_STORE:-}" ] && exit 0
    f="$STEPS/$name.json"
    if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi ;;
  show)
    [ "$name" = "${BD_SHOW_FAIL_STORE:-}" ] && exit 3
    # The REAL `bd show` answers an object at rc=0 when none of the requested
    # ids resolves, and arbitrary bytes only if the store is corrupt.
    [ "$name" = "${BD_SHOW_NONE_STORE:-}" ] && {
      printf '{"error":"no issues found matching the provided IDs","schema_version":1}'; exit 0; }
    [ "$name" = "${BD_SHOW_GARBAGE_STORE:-}" ] && { printf 'not json at all'; exit 0; }
    f="$ROOTS/$name.json"
    if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi ;;
  *) exit 0 ;;
esac
BD
chmod +x "$TMP/bin/bd"

export PATH="$TMP/bin:$PATH"
export STEPS="$TMP/steps" ROOTS="$TMP/roots"
BD_ARGS="$TMP/bd-args.log"
export BD_ARGS

run_check() {
    : > "$BD_ARGS"
    RIGS_JSON="${RIGS_JSON_OVERRIDE:-$TMP/rigs.json}" bash "$CHECK" 2>&1
}

# --- 0. Positive control -----------------------------------------------------
# Prove the fixture and the stubs are real before trusting any verdict computed
# from them. A `bd` stub that answered nothing would make every "no findings"
# case pass for entirely the wrong reason.
put steps alpha "$(step a-s1 a-r1 pass)"
put roots alpha "$(root a-r1 closed "$LONG_AGO")"
eq "$(bd list --db "$TMP/alpha/.beads" --json | jq -r '.[0].id')" "a-s1" \
   "positive control: the stub bd list answers the alpha step fixture"
eq "$(bd show --db "$TMP/alpha/.beads" a-r1 --json | jq -r '.[0].status')" "closed" \
   "positive control: the stub bd show answers the alpha root fixture"
eq "$(printf '%s' "$LONG_AGO" | grep -c 'Z$')" "1" \
   "positive control: the computed timestamp is ISO-8601 with a Z suffix"

# --- 1. ERROR: the REOPENED shape (tk-ciuad) --------------------------------
OUT=$(run_check); RC=$?
eq "$RC" "2" "an open step carrying gc.outcome under a closed root is an ERROR"
has "$OUT" "a-s1" "the error names the reopened step"
has "$OUT" "a-r1" "the error names the finalized molecule"
has "$OUT" "already carry gc.outcome" "the error identifies the REOPENED shape"
has "$OUT" "RESET afterwards" "the error says the step completed before being reset"

# --- 2. The query the check relies on ---------------------------------------
# Drop any one of these and the check starts reporting clean on stores full of
# re-offerable steps.
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--status open" "the scan asks for open beads"
has "$ARGS" "--has-metadata-key gc.root_bead_id" "the scan asks for beads carrying a molecule root"
has "$ARGS" "--limit 0" "the scan is not silently truncated by a default limit"
has "$ARGS" "show --db $TMP/alpha/.beads a-r1" "roots are resolved by a batched show in the same store"

# --- 3. ERROR: the NEVER-CLOSED shape, and it stays distinct -----------------
put steps alpha "$(step a-s2 a-r2)" "$(step a-s3 a-r2)"
put roots alpha "$(root a-r2 closed "$LONG_AGO")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "open steps with no gc.outcome under a closed root are an ERROR"
has "$OUT" "never closed" "the never-closed shape is reported in its own words"
hasnt "$OUT" "RESET afterwards" "the never-closed shape is NOT described as a reopen"
has "$OUT" "a-s2, a-s3" "the steps of one molecule are grouped onto a single line"
has "$OUT" "1 molecule(s)" "two steps of one molecule count as ONE finding, not two"

# --- 4. Both shapes under one root are reported separately -------------------
# A molecule can hold both: a step that ran and was reset, beside one that never
# ran. Collapsing them would hide whichever is the rarer of the two.
put steps alpha "$(step a-s4 a-r3 pass)" "$(step a-s5 a-r3)"
put roots alpha "$(root a-r3 closed "$LONG_AGO")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a molecule holding both shapes is an ERROR"
has "$OUT" "2 molecule(s)" "the two shapes under one root are two findings"
has "$OUT" "a-s4" "the reopened step is named"
has "$OUT" "a-s5" "the never-closed step is named"

# --- 5. OK: an open step under a LIVE root ----------------------------------
# The overwhelmingly common case. Flagging it would make the check useless.
put steps alpha "$(step a-s6 a-r4)"
put roots alpha "$(root a-r4 in_progress)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open step under an in_progress root is not flagged"
hasnt "$OUT" "a-s6" "the live molecule's step is not named as a finding"

put roots alpha "$(root a-r4 open)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open step under an open root is not flagged"

# --- 6. The grace window, both directions ------------------------------------
# Finalize closes the root BEFORE the terminal step's own close lands, so a
# molecule caught mid-finalize is healthy and must not flap the check red...
put steps alpha "$(step a-s7 a-r5)"
put roots alpha "$(root a-r5 closed "$JUST_NOW")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a root closed seconds ago is inside the settle window, not a strand"
has "$OUT" "settle window" "the in-window molecule is still reported as a note"

# ...but the window must never grow large enough to swallow a real strand.
OUT=$(GC_DOCTOR_FINALIZED_STEP_GRACE=1 run_check); RC=$?
eq "$RC" "2" "the same molecule IS a finding once the settle window is shortened"

# A root closed long ago is never in the window, whatever the default is.
put roots alpha "$(root a-r5 closed "$LONG_AGO")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a root closed a day ago is past any settle window"
hasnt "$OUT" "settle window" "an old strand is not excused as finalize-in-progress"

# A closed root with NO closed_at cannot be given the benefit of the window.
put roots alpha "$(root a-r5 closed)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a closed root with no closed_at is a finding, not an exemption"
has "$OUT" "no closed_at" "the missing timestamp is disclosed in the finding"

# --- 7. Note, not error: a root that resolves in no store here ---------------
put steps alpha "$(step_xstore a-s8 zz-r9 rig:beta)"
put roots alpha
OUT=$(run_check); RC=$?
eq "$RC" "0" "a step whose root lives in another store does not fail the check"
has "$OUT" "zz-r9" "the cross-store root is still reported in the details"
has "$OUT" "rig:beta" "the note quotes the gc.root_store_ref it was told"
clear_store alpha

# --- 8. The QUIET path ------------------------------------------------------
# A city with nothing wrong must exit 0 and name no bead. This is the case a
# tightened check most easily strands: every other scenario here is dirty.
OUT=$(run_check); RC=$?
eq "$RC" "0" "a city with no open step beads passes"
has "$OUT" "OK:" "the clean verdict is an OK line"
hasnt "$OUT" "is CLOSED" "the clean verdict reports no finding"
eq "$(printf '%s' "$OUT" | wc -l)" "0" "the clean verdict is one line and nothing else"

put steps alpha "$(step a-s9 a-r6)"
put roots alpha "$(root a-r6 in_progress)"
put steps beta "$(step b-s1 b-r1)"
put roots beta "$(root b-r1 open)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a city whose molecules are all live passes"
clear_store alpha; clear_store beta

# --- 9. Fail-CLOSED: the store list cannot be read ---------------------------
OUT=$(RIGS_RC=7 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list is a WARNING, never a pass"
has "$OUT" "cannot determine" "the message says the question was not answered"

printf 'not json at all' > "$TMP/badrigs.json"
OUT=$(RIGS_JSON_OVERRIDE="$TMP/badrigs.json" run_check); RC=$?
eq "$RC" "1" "a malformed rig list is a WARNING, never a pass"

# --- 10. Fail-CLOSED: one store's step listing cannot be read ----------------
# The other stores are still scanned; the unreadable one is named as unchecked
# rather than counted as clean.
put steps beta "$(step b-s2 b-r2 pass)"
put roots beta "$(root b-r2 closed "$LONG_AGO")"
OUT=$(BD_LIST_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "2" "an unreadable store does not suppress findings in the others"
has "$OUT" "b-s2" "the readable store is still scanned"
has "$OUT" "alpha: could not list" "the unreadable store is named"
has "$OUT" "was NOT checked" "the unreadable store is reported as unchecked, not clean"
clear_store beta

OUT=$(BD_LIST_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store alone is a WARNING, not an OK"
hasnt "$OUT" "OK:" "a partial scan never prints the clean verdict"

# A store that returns NOTHING is not a store that returned `[]`.
OUT=$(BD_EMPTY_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a store whose listing produced no output at all is a WARNING"
has "$OUT" "returned no output" "the empty-output store is distinguished from an empty one"

# --- 11. Fail-CLOSED: roots cannot be resolved -------------------------------
# This is the subtle one. If root resolution fails and the check carries on,
# every step under the missing roots reclassifies as "cross-store, not judged"
# — a silent downgrade from ERROR to note, which is the original silence.
put steps alpha "$(step a-s10 a-r7 pass)"
put roots alpha "$(root a-r7 closed "$LONG_AGO")"
OUT=$(BD_SHOW_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a store whose roots cannot be resolved is a WARNING"
has "$OUT" "could not resolve molecule roots" "the failed root resolution is named"
hasnt "$OUT" "not judged" "an unresolvable-root store is NOT downgraded to a cross-store note"
hasnt "$OUT" "OK:" "a store with unresolved roots never prints the clean verdict"

# --- 12. `bd show` resolving NOTHING is an answer, not corruption -------------
# The real verb answers an OBJECT — {"error":"no issues found..."} — at rc=0
# when none of the requested ids resolves, and an ARRAY otherwise. Treating that
# object as a parse failure would warn "store NOT checked" for the ordinary case
# of a chunk made entirely of cross-store roots, and take every real finding in
# that store down with it.
put steps alpha "$(step_xstore a-s11 zz-r10 rig:beta)"
put steps beta "$(step b-s3 b-r3 pass)"
put roots beta "$(root b-r3 closed "$LONG_AGO")"
OUT=$(BD_SHOW_NONE_STORE=alpha run_check); RC=$?
eq "$RC" "2" "a store whose roots all resolve elsewhere does not suppress other stores"
has "$OUT" "b-s3" "the readable store's finding survives"
has "$OUT" "zz-r10" "the unresolved root is reported as a note"
hasnt "$OUT" "could not resolve molecule roots" "resolving nothing is not reported as a failed probe"
clear_store beta

OUT=$(BD_SHOW_NONE_STORE=alpha run_check); RC=$?
eq "$RC" "0" "a store whose roots all resolve elsewhere is not itself a finding"

# Genuine corruption still fails the store closed.
OUT=$(BD_SHOW_GARBAGE_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a root payload that is neither array nor object is a WARNING"
has "$OUT" "could not resolve molecule roots" "corrupt root bytes are reported as a failed probe"
clear_store alpha

# --- Summary ----------------------------------------------------------------
echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
