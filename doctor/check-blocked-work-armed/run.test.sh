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

# --- 1. the finding: blocked plainly-work bead with no route and no arm ------
blocked_store alpha "$(bwork a-1)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a blocked plainly-work bead with no dispatch path warns (exit 1)"
has "$OUT" "no dispatch path" "the headline names the defect"
has "$OUT" "alpha bead a-1" "the finding names the rig and bead"
has "$OUT" "deferred-dispatch.sh arm a-1" "the finding names the arm remedy for that bead"
clear_stores

# gc.execution_routed_to is execution provenance, not a dispatch path: a bead
# carrying only it still strands when its blocker clears — a FINDING.
blocked_store alpha "$(bexec a-1)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a blocked task carrying only gc.execution_routed_to is flagged"
has "$OUT" "alpha bead a-1" "the exec-routed-only bead is named as a finding"
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
