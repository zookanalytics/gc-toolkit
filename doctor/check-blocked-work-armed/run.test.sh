#!/usr/bin/env bash
# Hermetic test for doctor/check-blocked-work-armed. Stub gc/bd only; no live
# city, Dolt, or network. Covers: the finding (blocked plainly-work bead with
# neither route nor arm, including one carrying only gc.execution_routed_to —
# provenance, not a dispatch path), every exemption (routed, armed, assigned,
# merge anchor, review/step/workflow/demand metadata, decision/epic/infra
# types), the per-rig labelling, the remedy string, the fail-closed probes
# (unreadable blocked listing, unreadable rig list), and the quiet paths (empty
# store, all-armed store).
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

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)     shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
case "$sub" in
  blocked) [ "$name" = "${BD_FAIL_BLOCKED:-}" ] && exit 3
           f="$STORES/$name.blocked.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi ;;
  # The liveness step: `list --status open,in_progress` is the alive set the
  # candidate's molecule root is named in; `show <convoy>` renders the tracks
  # edge. Both read per-rig fixtures; a missing show fixture answers bd's
  # not-found OBJECT (not an array), which the check reads as liveness-unverified.
  list) f="$STORES/$name.alive.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi ;;
  show) sid="$2"; f="$STORES/$name.show.$sid.json"
        if [ -f "$f" ]; then cat "$f"; else printf '{"error":"no issues found matching the provided IDs"}'; fi ;;
  *) printf '[]'; exit 0 ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

run_check() {
    RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1
}
blocked_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.blocked.json"; }
clear_stores() { rm -f "$TMP/stores/"*.json; }

# A blocked plainly-work bead: type task, unassigned, no route/arm — a FINDING.
bwork()   { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","title":"do the thing","blocked_by":["x-0"],"metadata":{}}' "$1"; }
# The exemptions — each is a blocked bead that must NOT be flagged.
brouted() { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","blocked_by":["x-0"],"metadata":{"gc.routed_to":"alpha/pack.polecat"}}' "$1"; }
bexec()   { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","blocked_by":["x-0"],"metadata":{"gc.execution_routed_to":"alpha/pack.polecat"}}' "$1"; }
barmed()  { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","blocked_by":["x-0"],"metadata":{"gc.dispatch_when_ready":"alpha/pack.polecat"}}' "$1"; }
bassigned() { printf '{"id":"%s","status":"open","assignee":"someone/else","issue_type":"task","blocked_by":["x-0"],"metadata":{}}' "$1"; }
bmeta()   { printf '{"id":"%s","status":"open","assignee":"","issue_type":"task","blocked_by":["x-0"],"metadata":{"%s":"%s"}}' "$1" "$2" "$3"; }
btyped()  { printf '{"id":"%s","status":"open","assignee":"","issue_type":"%s","blocked_by":["x-0"],"metadata":{}}' "$1" "$2"; }
# Liveness fixtures. A not-closed workflow root names its input convoy (the LIVE
# NAMER); the convoy renders a tracks edge to the work bead. Present both and the
# work bead reads as in-flight; omit the convoy show and liveness is unverified.
alive_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.alive.json"; }
broot()       { printf '{"id":"%s","status":"in_progress","assignee":"","issue_type":"task","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"%s"}}' "$1" "$2"; }
convoy_tracks() { printf '[{"id":"%s","dependencies":[{"dependency_type":"tracks","id":"%s"}]}]' "$1" "$2" > "$TMP/stores/$3.show.$1.json"; }

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

# When the molecule liveness cannot be confirmed — the alive listing names a
# convoy the store will not render — an exec-routed candidate is reported as
# unverifiable and NOT flagged, so an unreadable molecule never becomes an
# arm-it-now that double-dispatches. (No convoy_tracks fixture: show answers a
# not-found object, not an array.)
blocked_store alpha "$(bexec a-1)"
alive_store  alpha "$(broot root-1 convoy-1)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unconfirmable exec-routed bead makes the pass report (exit 1)"
has "$OUT" "liveness could not be confirmed" "it says liveness was unverifiable"
has "$OUT" "NOT flagged" "and that it withheld the flag rather than risk a double dispatch"
hasnt "$OUT" "no dispatch path" "it is a warning, not a stranded-work finding"
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

blocked_store alpha "$(bassigned a-1)"
eq "$(run_check >/dev/null; echo $?)" "0" "an assigned blocked bead is not flagged (not unrouted-and-remember)"
clear_stores

for pair in "task_kind=review" "gc.step_ref=mol-x.step" "gc.kind=workflow" "gc.demand_for=a-9"; do
    k="${pair%%=*}"; v="${pair#*=}"
    blocked_store alpha "$(bmeta a-1 "$k" "$v")"
    eq "$(run_check >/dev/null; echo $?)" "0" "a blocked bead carrying $k is not plainly work — not flagged"
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
