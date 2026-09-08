#!/usr/bin/env bash
# Hermetic test for the witness-patrol SALVAGE SCOPE GATE.
#
# THE BUG: mol-witness-patrol step recover-orphaned-beads part 3 (salvage) reads
# metadata.work_dir and metadata.branch and part 4 verifies a branch merged. A
# polecat stamps those on the work (source) bead alone; a visit, a graph.v2 step
# and a graph.v2 root carry neither by construction. So the husk guard refused
# salvage for them and the fall-through filed a no-signal witness-salvage-refused,
# and part 4 read `unknown` off an empty branch and escalated
# witness-branch-recovery-unknown. On the gc-toolkit rig those non-work beads were
# roughly a third of every recovery pass.
#
# THE FIX: a scope gate classifies the bead the way part 5's orphan-dispose.sh
# does and sets IS_WORK_BEAD=1 only for a `source` work bead. The salvage block
# and part 4 branch on it, so a visit/step/root skips both and reaches part 5
# (disposal) directly, where orphan-dispose releases or skips it by that same
# class.
#
# What is exercised here:
#   * the gate EXTRACTED VERBATIM from the formula (between the salvage-scope-gate
#     markers), run exactly as the witness runs it — BEAD_JSON from `gc bd show`,
#     no set -e — so the test cannot drift from the shipped instruction;
#   * IS_WORK_BEAD across the four shapes recovery hands part 3, the precedence
#     (a visit outranks a step_ref), and the fail-safe (an unreadable bead
#     defaults to the work-bead path, so a real orphan is never skipped);
#   * CONFORMANCE: the gate and the real orphan-dispose.sh run over ONE store and
#     must agree — class=source iff IS_WORK_BEAD=1 — so the two classifiers cannot
#     drift apart;
#   * static wiring: the salvage refuse-branch and part 4 both branch on
#     IS_WORK_BEAD, and the gate is defined before the first salvage `git add -A`,
#     so an edit that drops the gate fails here rather than silently re-filing the
#     no-signal escalations;
#   * the formula still parses as TOML after the edit.
#
# No live city, Dolt, network, or beads — stubs from test-harness.sh only.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
SCRIPT="$HERE/orphan-dispose.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-salvage-scope-gate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# --- Extract the REAL gate from the formula. ---------------------------------
# If the markers or the gate are removed/renamed, extraction yields nothing and
# the check below fails loudly — the contract cannot silently disappear.
GATE="$(awk '
  /# >>> salvage-scope-gate/ {f=1; next}
  /# <<< salvage-scope-gate/ {f=0}
  f' "$TOML")"

[ -n "$GATE" ] \
  && ok "gate extracted between salvage-scope-gate markers" \
  || bad "gate extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$GATE" > "$TMP/gate.sh"
bash -n "$TMP/gate.sh" \
  && ok "extracted gate is syntactically valid bash" \
  || bad "extracted gate failed bash -n"

# gate_says <bead-id> -> prints IS_WORK_BEAD. The gate is sourced exactly as the
# witness runs it: BEAD_JSON is what `gc bd show <bead> --json` returned, no set -e.
gate_says() {
  BEAD_JSON="$(gc bd show "$1" --json)" bash -c '
    source "$0"
    printf "%s" "$IS_WORK_BEAD"
  ' "$TMP/gate.sh" 2>/dev/null
}

# --- The four shapes recovery hands part 3 (as in orphan-dispose.test.sh). ----
# The step's assignee and gc.session_id both name the dead session; the root
# carries gc.kind/gc.formula_contract and only gc.session_name; the visit carries
# task_kind; the work bead carries a branch and no kind/step markers.
fixture() {
  store '[
    {"id":"tk-step","status":"in_progress","assignee":"lx-dead","title":"Implement the solution",
     "metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"lx-dead",
                 "gc.session_name":"polecat-2-pool","gc.session_affinity":"require",
                 "gc.continuation_group":"cg-1",
                 "gc.native_step_dependencies.v1":"[\"mol-polecat-work.preflight-tests\"]"}},
    {"id":"tk-root","status":"in_progress","assignee":"","title":"mol-polecat-work",
     "metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2",
                 "gc.input_convoy_id":"tk-convoy","gc.routed_to":"gc-toolkit/gc-toolkit.polecat",
                 "gc.session_name":"polecat-2-pool"}},
    {"id":"tk-visit","status":"in_progress","assignee":"lx-dead","title":"visit",
     "metadata":{"task_kind":"visit","gc.routed_to":"gc-toolkit/gc-toolkit.converse",
                 "gc.continuation_group":"cg-visit","gc.session_id":"lx-dead"}},
    {"id":"tk-work","status":"in_progress","assignee":"lx-dead","title":"a work bead",
     "metadata":{"branch":"polecat/tk-work","gc.routed_to":"gc-toolkit/gc-toolkit.polecat",
                 "workflow_id":"tk-root","gc.session_id":"lx-dead","gc.session_name":"polecat-3-pool"}}
  ]'
}

echo "--- behavioral matrix ---"
fixture
eq "$(gate_says tk-step)"  "0" "graph.v2 step  -> not a work bead (skip salvage)"
eq "$(gate_says tk-root)"  "0" "graph.v2 root  -> not a work bead (skip salvage)"
eq "$(gate_says tk-visit)" "0" "visit          -> not a work bead (skip salvage)"
eq "$(gate_says tk-work)"  "1" "source work bead -> IS_WORK_BEAD=1 (salvage runs)"

# A visit that also carries step metadata is still a visit — task_kind outranks a
# step_ref, exactly as orphan-dispose.sh's classification order does.
store '[{"id":"tk-v2","status":"in_progress","assignee":"lx-dead","title":"visit",
         "metadata":{"task_kind":"visit","gc.step_ref":"mol-visit.converse",
                     "gc.routed_to":"r","gc.session_id":"lx-dead"}}]'
eq "$(gate_says tk-v2)" "0" "task_kind=visit outranks a step_ref"

# Fail safe: an unreadable/absent bead must default to the work-bead path so a
# real orphan is never skipped. `gc bd show` of a missing id returns [], which
# has no metadata — the else arm, IS_WORK_BEAD=1.
store '[]'
eq "$(gate_says tk-missing)" "1" "absent bead -> defaults to the work-bead path"

echo "--- conformance: the gate and orphan-dispose.sh agree ---"
# Both classifiers read the same store. class=source is exactly the work-bead
# case, so IS_WORK_BEAD must be 1 there and 0 for visit/workflow-root/workflow-step.
# If either classifier's precedence drifts, this fails.
fixture
for id in tk-step tk-root tk-visit tk-work; do
  CLASS="$("$SCRIPT" "$id" --json | jq -r '.class // ""')"
  GW="$(gate_says "$id")"
  WANT=$([ "$CLASS" = "source" ] && echo 1 || echo 0)
  eq "$GW" "$WANT" "conformance: $id is class=$CLASS <-> IS_WORK_BEAD=$WANT"
done

echo "--- static wiring: salvage and verify must honor the gate ---"
# The gate protects anything only if the salvage refuse-branch and part 4 branch
# on IS_WORK_BEAD. Assert both, so an edit that drops a gate fails here rather
# than silently re-filing the no-signal escalations.
grep -qF 'if [ "$IS_WORK_BEAD" != "1" ]; then' "$TOML" \
  && ok "salvage block short-circuits when IS_WORK_BEAD != 1" \
  || bad "salvage block must branch on IS_WORK_BEAD"
grep -qF 'if [ "$IS_WORK_BEAD" = "1" ]; then' "$TOML" \
  && ok "part 4 verify runs only when IS_WORK_BEAD = 1" \
  || bad "part 4 verify must branch on IS_WORK_BEAD"

# The gate must be DEFINED before the first salvage `git add -A`, or salvage
# would run against an unset IS_WORK_BEAD. Anchor both to line start so prose
# mentioning either does not match.
GATE_LINE=$(grep -nE '^IS_WORK_BEAD=' "$TOML" | head -1 | cut -d: -f1)
FIRST_ADD=$(grep -nE '^[[:space:]]*git add -A' "$TOML" | head -1 | cut -d: -f1)
[ -n "$GATE_LINE" ] && [ -n "$FIRST_ADD" ] && [ "$GATE_LINE" -lt "$FIRST_ADD" ] \
  && ok "scope gate is defined before the first salvage 'git add -A'" \
  || bad "scope gate must be defined before any 'git add -A' (got gate@${GATE_LINE:-none} add@${FIRST_ADD:-none})"

echo "--- formula still parses as TOML ---"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$TOML" <<'PY' && ok "formula still parses as TOML" || bad "formula failed to parse as TOML"
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
