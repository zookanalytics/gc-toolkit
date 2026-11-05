#!/usr/bin/env bash
# Hermetic test for doctor/check-blocked-work-armed. Stubs gc/bd and
# run-lib.sh's verbs only; no live city, Dolt, or network. Covers: the finding
# (blocked plainly-work bead with neither route nor arm, including one carrying
# only gc.execution_routed_to — provenance, not a dispatch path — and one whose
# route or arm holds only whitespace), every exemption (routed, armed, assigned,
# worked by a live run, merge anchor, waiting for placement,
# review/step/workflow metadata, every standing kind,
# decision/epic/infra types), a marked bead placed under an epic, the per-rig
# labelling, the remedy string, the fail-closed probes (unreadable blocked
# listing, unreadable runs, unreadable marked listing, a marked listing that
# fails after printing its rows, unreadable rig list), a raw control byte in a
# listing's row, and the quiet paths (empty store, all-armed store).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-blocked-work-armed-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/beta" "$TMP/pack"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"}]}
EOF

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)     shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
case "$sub" in
  blocked) [ "$name" = "${BD_FAIL_BLOCKED:-}" ] && exit 3
           f="$STORES/$name.blocked.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi ;;
  # `list --metadata-field placement=pending` is the placement step's read of the
  # marked beads, in the shape `bd list` prints (a parent included); each one is
  # logged so a case can tell whether the check made it. BD_PARTIAL_MARKED names
  # a store whose listing prints its rows and then fails.
  list) case " $* " in
          *" placement=pending "*)
            printf '%s\n' "$name" >> "$STORES/marked.calls"
            [ "$name" = "${BD_FAIL_MARKED:-}" ] && exit 3
            f="$STORES/$name.marked.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
            if [ "$name" = "${BD_PARTIAL_MARKED:-}" ]; then exit 3; fi ;;
          *) echo "stub bd: unexpected list: $*" >&2; exit 2 ;;
        esac ;;
  *) printf '[]'; exit 0 ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
# The liveness step asks run-lib.sh's map, which run-lib.stub.sh answers from
# the runs the fixture stores' roots and convoys make, by run-lib.sh's own
# run_rows. The ids are distinct across the stores, so one set of runs answers
# for every rig. RUN_LIB_STUB_FAIL fails the read, as an unreadable store does.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf '. %q || exit 1\n' "$HERE/../../assets/scripts/run-lib.sh"; cat; } > "$TMP/bin/fixture-runs" <<'RUNS'
cat "$STORES"/*.alive.json "$STORES"/*.show.*.json 2>/dev/null | jq -cs "$RUN_JQ"'add // [] | run_rows'
RUNS
chmod +x "$TMP/bin/fixture-runs"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"
export GC_RUN_LIB="$HERE/../../assets/scripts/run-lib.stub.sh" RUN_LIB_STUB_CMD="$TMP/bin/fixture-runs" RUN_LIB_STUB_FAIL=""

run_check() {
    RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1
}
blocked_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.blocked.json"; }
clear_stores() { rm -f "$TMP/stores/"*.json "$TMP/stores/marked.calls"; }
marked_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.marked.json"; }
marked_reads() { if [ -f "$TMP/stores/marked.calls" ]; then wc -l < "$TMP/stores/marked.calls" | tr -d ' '; else echo 0; fi; }

# A blocked plainly-work bead: type task, unassigned, no route/arm — a FINDING.
bwork()   { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","title":"do the thing","blocked_by":["x-0"],"metadata":{}}' "$1"; }
# The exemptions — each is a blocked bead that must NOT be flagged.
brouted() { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","blocked_by":["x-0"],"metadata":{"gc.routed_to":"alpha/pack.polecat"}}' "$1"; }
bexec()   { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","blocked_by":["x-0"],"metadata":{"gc.execution_routed_to":"alpha/pack.polecat"}}' "$1"; }
barmed()  { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","blocked_by":["x-0"],"metadata":{"gc.dispatch_when_ready":"alpha/pack.polecat"}}' "$1"; }
bassigned() { printf '{"id":"%s","status":"open","assignee":"someone/else","issue_type":"task","blocked_by":["x-0"],"metadata":{}}' "$1"; }
bmeta()   { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","blocked_by":["x-0"],"metadata":{"%s":"%s"}}' "$1" "$2" "$3"; }
btyped()  { printf '{"id":"%s","status":"open","assignee":"","issue_type":"%s","blocked_by":["x-0"],"metadata":{}}' "$1" "$2"; }
# Liveness fixtures, the rows the runs come from. A live workflow root names its
# input convoy, and the convoy tracks the work bead: present both and a live run
# works the bead, so it reads as in-flight.
alive_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.alive.json"; }
broot()       { printf '{"id":"%s","status":"in_progress","assignee":"","issue_type":"task","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"%s"}}' "$1" "$2"; }
convoy_tracks() { printf '[{"id":"%s","issue_type":"convoy","dependencies":[{"dependency_type":"tracks","id":"%s"}]}]' "$1" "$2" > "$TMP/stores/$3.show.$1.json"; }

# --- 1. the finding: blocked plainly-work bead with no route and no arm ------
blocked_store alpha "$(bwork a-1)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a blocked plainly-work bead with no dispatch path warns (exit 1)"
has "$OUT" "no dispatch path" "the headline names the defect"
has "$OUT" "alpha bead a-1" "the finding names the rig and bead"
has "$OUT" "deferred-dispatch.sh arm a-1" "the finding names the arm remedy for that bead"
clear_stores

# gc.execution_routed_to is execution provenance, not a dispatch path. When NO
# live molecule drives the bead (the alive listing is empty, so liveness is
# confirmed), a bead carrying only it still strands when its blocker clears — a
# FINDING. (The live-molecule case, where it must NOT be flagged, is below.)
blocked_store alpha "$(bexec a-1)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a blocked exec-routed bead no live molecule drives is flagged (stranded)"
has "$OUT" "alpha bead a-1" "the stranded exec-routed bead is named as a finding"
clear_stores

# --- F4: an in-flight bead under a LIVE molecule must NOT be flagged ---------
# A LIVE graph.v2 pour leaves the work bead open, unassigned, gc.routed_to
# retired, gc.execution_routed_to set — the same shape as a stranded bead. It is
# distinguished by a not-closed root naming a convoy that tracks it. Flagging it
# would have the operator arm a bead a live workflow already drives: a double
# dispatch. It is exempt.
blocked_store alpha "$(bexec a-1)"
alive_store  alpha "$(broot root-1 convoy-1)"
convoy_tracks convoy-1 a-1 alpha
OUT=$(run_check); RC=$?
eq "$RC" "0" "an exec-routed bead a live molecule drives is NOT flagged (F4)"
has "$OUT" "OK:" "the store with only an in-flight bead reads clean"
hasnt "$OUT" "alpha bead a-1" "the in-flight bead is not named as a finding"
clear_stores

# When the runs cannot be read, whether a live run works an exec-routed
# candidate is unconfirmed, so it is reported as unverifiable and NOT flagged:
# an unreadable run never becomes an arm-it-now that double-dispatches.
blocked_store alpha "$(bexec a-1)"
alive_store  alpha "$(broot root-1 convoy-1)"
convoy_tracks convoy-1 a-1 alpha
OUT=$(RUN_LIB_STUB_FAIL=map run_check); RC=$?
eq "$RC" "1" "an unconfirmable exec-routed bead makes the pass report (exit 1)"
has "$OUT" "whether a live run works it could not be confirmed" "it says the run could not be confirmed"
has "$OUT" "NOT flagged" "and that it withheld the flag rather than risk a double dispatch"
hasnt "$OUT" "no dispatch path" "it is a warning, not a stranded-work finding"
clear_stores
# A run that has finished works nothing: its exec-routed bead is stranded.
blocked_store alpha "$(bexec a-1)"
alive_store  alpha "$(broot root-1 convoy-1 | jq -c '.status = "closed"')"
convoy_tracks convoy-1 a-1 alpha
OUT=$(run_check); RC=$?
eq "$RC" "1" "an exec-routed bead whose run has finished is flagged (stranded)"
has "$OUT" "alpha bead a-1" "…as a finding"
clear_stores

# A bead with no exec stamp is hand-filed work, not a molecule bead: liveness is
# irrelevant and it is flagged whether or not the alive listing is readable.
blocked_store alpha "$(bwork a-1)"
alive_store  alpha "$(broot root-1 convoy-1)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a non-exec blocked work bead is flagged regardless of molecule liveness"
has "$OUT" "no dispatch path" "and it is a stranded-work finding, not a liveness warning"
clear_stores

# The allowlist admits every named work type, not just task (which bwork uses):
# a blocked bug/feature/chore/spike with no dispatch path is a finding too.
for t in bug feature chore spike; do
    blocked_store alpha "$(btyped a-1 "$t")"
    eq "$(run_check >/dev/null; echo $?)" "1" "a blocked $t with no dispatch path is flagged (work allowlist)"
    clear_stores
done

# A route or an arm holding only whitespace is no dispatch path
# (assets/scripts/dispatch-path.sh): a pool matches its route byte for byte, and
# gc sling refuses the value as a target. The bead strands like one with neither
# key, so each is a finding.
blocked_store alpha "$(bmeta a-1 gc.routed_to ' ')" "$(bmeta a-2 gc.dispatch_when_ready ' ')"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a blocked bead whose route or arm holds only whitespace warns (exit 1)"
has "$OUT" "alpha bead a-1" "…the whitespace route is named as a finding"
has "$OUT" "alpha bead a-2" "…and so is the whitespace arm"
clear_stores

# --- 2. exemptions: each must NOT be flagged --------------------------------
blocked_store alpha "$(brouted a-1)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a blocked bead already routed (gc.routed_to) is not flagged"
has "$OUT" "OK:" "clean run prints the OK line"
clear_stores

# A merge anchor (merge_result set) is driven by the merge cadence and offered
# by no pool queue (lifecycle.toml: anchor state = status x merge_result), so
# blocked-and-unrouted is not the anti-pattern for it — not flagged.
blocked_store alpha "$(bmeta a-1 merge_result pre_open_gate)"
eq "$(run_check >/dev/null; echo $?)" "0" "a blocked merge anchor (merge_result) is not flagged"
clear_stores

blocked_store alpha "$(barmed a-1)"
eq "$(run_check >/dev/null; echo $?)" "0" "a blocked bead already armed (gc.dispatch_when_ready) is not flagged"
clear_stores

# A bead intake held for the operator's placement sitting gets its dispatch when
# the sitting places it, so blocked-and-unrouted is not the anti-pattern for it,
# and the arm remedy would start work the operator has not placed. A marker that
# is not pending exempts nothing. `bd blocked` prints no parent, so each blocked
# row below carries none, the way the live listing prints it; the marked beads'
# own `bd list` row is the one that can name a parent.
# bmarked <id> [<parent by dependency>] [<parent by .parent>] — a marked bead's
# `bd list` row.
bmarked() {
    jq -nc --arg id "$1" --arg dep "${2:-}" --arg par "${3:-}" '
        {id: $id, status: "open", assignee: "", issue_type: "task", metadata: {placement: "pending"},
         dependencies: ([{depends_on_id: "x-0", type: "blocks"}]
                        + (if $dep != "" then [{depends_on_id: $dep, type: "parent-child"}] else [] end))}
        + (if $par != "" then {parent: $par} else {} end)'
}
blocked_store alpha "$(bmeta a-1 placement pending)"
marked_store  alpha "$(bmarked a-1)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a blocked bead waiting for placement (placement=pending) is not flagged"
hasnt "$OUT" "deferred-dispatch.sh arm a-1" "…and draws no arm remedy"
eq "$(marked_reads)" "1" "…judged on the marked beads' own listing, read once for the store"
clear_stores
blocked_store alpha "$(bmeta a-1 placement placed)"
eq "$(run_check >/dev/null; echo $?)" "1" "a placement marker that is not pending exempts nothing"
eq "$(marked_reads)" "0" "…and with no marked candidate the marked beads are not read"
clear_stores
# Placed under an epic, the bead is work again, marker or not: the sitting placed
# it, and a placed bead with no route or arm strands when its blocker closes.
# Either shape `bd list` prints a parent in places it.
blocked_store alpha "$(bmeta a-1 placement pending)" "$(bmeta a-2 placement pending)"
marked_store  alpha "$(bmarked a-1 "" tk-epic)" "$(bmarked a-2 tk-epic)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a bead placed under an epic is flagged even with its marker left behind"
has "$OUT" "deferred-dispatch.sh arm a-1" "…placed by .parent, it draws the arm remedy"
has "$OUT" "deferred-dispatch.sh arm a-2" "…placed by a parent-child dependency, so does it"
clear_stores
# When the marked beads cannot be read, a marked candidate is unverifiable: it
# may still wait for the sitting, so it is warned and NOT flagged.
blocked_store alpha "$(bmeta a-1 placement pending)"
OUT=$(BD_FAIL_MARKED=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable marked listing makes the pass report (exit 1)"
has "$OUT" "could not be read" "…it says the placement could not be read"
has "$OUT" "NOT flagged" "…and that it withheld the flag"
hasnt "$OUT" "no dispatch path" "…as a warning, not a stranded-work finding"
hasnt "$OUT" "deferred-dispatch.sh arm a-1" "…with no arm remedy"
clear_stores
# A listing that prints its rows and then fails has not answered for the store,
# so its rows vouch for nothing: the candidate is warned, not exempted.
blocked_store alpha "$(bmeta a-1 placement pending)"
marked_store  alpha "$(bmarked a-1)"
OUT=$(BD_PARTIAL_MARKED=alpha run_check); RC=$?
eq "$RC" "1" "a marked listing that prints rows and then fails makes the pass report (exit 1)"
has "$OUT" "could not be read" "…it says the placement could not be read, whatever the rows said"
hasnt "$OUT" "deferred-dispatch.sh arm a-1" "…with no arm remedy"
clear_stores

# --- a raw control byte in one row does not void its listing -----------------
# Each listing is scrubbed before jq first reads it, its type check included, so
# one bead whose title carries a raw control byte leaves the rest judged: the
# store is checked, and a marked candidate's placement is read. The runs are
# run-lib.sh's reads, which run-lib.test.sh scrubs.
CTL_ROW=$(printf '{"id":"a-9","status":"open","assignee":"someone/else","issue_type":"task","title":"bell\001here","metadata":{"placement":"pending"}}')
blocked_store alpha "$(bwork a-1)" "$CTL_ROW"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a blocked listing with a raw control byte in a title is still judged (exit 1)"
has "$OUT" "deferred-dispatch.sh arm a-1" "…its stranded bead is flagged"
hasnt "$OUT" "NOT checked" "…rather than the store reported unchecked"
clear_stores
blocked_store alpha "$(bmeta a-1 placement pending)"
marked_store  alpha "$(bmarked a-1)" "$CTL_ROW"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a marked listing with a raw control byte in a title still judges the placement"
hasnt "$OUT" "could not be read" "…so a bead that waits for the sitting is not warned as unverifiable"
clear_stores

blocked_store alpha "$(bassigned a-1)"
eq "$(run_check >/dev/null; echo $?)" "0" "an assigned blocked bead is not flagged (not unrouted-and-remember)"
clear_stores

for pair in "task_kind=review" "gc.step_ref=mol-x.step" "gc.kind=workflow"; do
    k="${pair%%=*}"; v="${pair#*=}"
    blocked_store alpha "$(bmeta a-1 "$k" "$v")"
    eq "$(run_check >/dev/null; echo $?)" "0" "a blocked bead carrying $k is not plainly work — not flagged"
    clear_stores
done
# A task still carrying a demand's gc.demand_for is plainly work: the key names
# no exemption any more, and a work bead a human gate blocks needs its arm. A
# human gate itself is a gate, which the type loop below leaves out.
blocked_store alpha "$(bmeta a-1 gc.demand_for a-9)"
eq "$(run_check >/dev/null; echo $?)" "1" "a blocked task carrying a leftover gc.demand_for is plainly work — flagged"
clear_stores

# A standing record is never dispatched, so blocked-and-unrouted is its resting
# state, and the arm remedy would sling it to a pool when its blocker closed.
# The kinds come from the shared definition itself, so a kind added there is
# exempted and covered here with no edit to this file.
# shellcheck source=../../assets/scripts/standing-kinds.sh
. "$HERE/../../assets/scripts/standing-kinds.sh"
KINDS=$(jq -nr "$STANDING_KINDS_JQ"'standing_kinds[]')
[ -n "$KINDS" ] && ok "the shared definition lists the standing kinds to exempt" \
    || bad "the shared definition lists the standing kinds to exempt" "standing_kinds read back empty"
for k in $KINDS; do
    blocked_store alpha "$(bmeta a-1 task_kind "$k")"
    OUT=$(run_check); RC=$?
    eq "$RC" "0" "a blocked standing record (task_kind=$k) is not flagged"
    hasnt "$OUT" "deferred-dispatch.sh arm a-1" "…and draws no arm remedy (task_kind=$k)"
    clear_stores
done

# A negative list would flag any type it forgot; the allowlist exempts every
# non-work type by naming what IS work. Topology/infra types `bd ready` excludes
# (step, convoy, session, spec, event, convergence) and container types (epic,
# milestone, story) must all pass — each of these is flagged by the pre-allowlist
# negative list, so this loop fails against the old check and proves the fix.
for t in decision epic merge-request gate molecule step convoy session spec event convergence story milestone; do
    blocked_store alpha "$(btyped a-1 "$t")"
    eq "$(run_check >/dev/null; echo $?)" "0" "a blocked $t is not pool work — not flagged"
    clear_stores
done

# --- 3. a mix: the finding is named, the armed sibling is not ----------------
blocked_store alpha "$(bwork a-1)" "$(barmed a-2)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a store mixing an unarmed and an armed blocked bead warns"
has "$OUT" "a-1" "the unarmed bead is named"
hasnt "$OUT" "bead a-2" "the armed bead is not named as a finding"
has "$OUT" "1 finding" "exactly one finding is counted"
clear_stores

# --- 4. per-rig labelling across stores --------------------------------------
blocked_store alpha "$(bwork a-1)"
blocked_store beta  "$(bwork b-1)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "findings across two rigs warn"
has "$OUT" "alpha bead a-1" "alpha's finding is labelled with its rig"
has "$OUT" "beta bead b-1" "beta's finding is labelled with its rig"
has "$OUT" "2 finding" "both rigs' findings are counted"
clear_stores

# --- F6: a suspended rig is skipped, not queried -----------------------------
# Querying a suspended rig's store with `gc bd blocked --db` auto-starts an
# orphan Dolt server, so the check skips it with a note (like the sibling store
# checks) rather than reading its blocked beads.
cat > "$TMP/rigs-suspended.json" <<EOF
{"rigs":[
  {"name":"alpha","path":"$TMP/alpha","suspended":true},
  {"name":"beta","path":"$TMP/beta"}]}
EOF
blocked_store alpha "$(bwork a-1)"
blocked_store beta  "$(bwork b-1)"
OUT=$(RIGS_JSON="$TMP/rigs-suspended.json" run_check); RC=$?
eq "$RC" "1" "a live rig's finding still warns while a suspended sibling is skipped"
has "$OUT" "alpha: skipped (suspended" "the suspended rig is skipped with a note"
hasnt "$OUT" "alpha bead a-1" "the suspended rig's blocked bead is neither read nor flagged"
has "$OUT" "beta bead b-1" "the live rig is still scanned in the same pass"
clear_stores; rm -f "$TMP/rigs-suspended.json"

# --- 5. quiet paths ----------------------------------------------------------
# No blocked-bead fixture at all: every store answers the empty array.
OUT=$(run_check); RC=$?
eq "$RC" "0" "a city with no blocked beads passes"
has "$OUT" "OK:" "the empty city prints OK"

blocked_store alpha "$(brouted a-1)" "$(barmed a-2)"
blocked_store beta  "$(bassigned b-1)"
eq "$(run_check >/dev/null; echo $?)" "0" "a city whose every blocked work bead has a dispatch path passes"
clear_stores

# --- 6. fail-closed: an unreadable store must NOT read as clean --------------
blocked_store beta "$(bwork b-1)"
OUT=$(BD_FAIL_BLOCKED=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable blocked listing warns (never passes)"
has "$OUT" "NOT checked" "the unreadable store is named as unchecked, not clean"
has "$OUT" "beta bead b-1" "the readable store is still scanned in the same pass"
clear_stores

# --- 7. fail-closed: an unreadable rig list cannot determine anything --------
OUT=$(RIGS_RC=3 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list warns"
has "$OUT" "cannot determine" "it says it could not determine the answer"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
