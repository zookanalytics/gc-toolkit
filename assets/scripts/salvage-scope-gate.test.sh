#!/usr/bin/env bash
# Hermetic test for the witness-patrol SALVAGE SCOPE GATE.
#
# Orphan recovery (mol-witness-patrol, step recover-orphaned-beads) salvages a
# dead owner's worktree in part 3, checks whether its branch merged in part 4,
# and hands the bead to orphan-dispose.sh for disposal in part 5. Salvage and
# the merge check read metadata.work_dir and metadata.branch, which a polecat
# stamps on the work (source) bead alone. A visit, a review, a graph.v2 step and
# a graph.v2 root carry neither. A review's review_branch names the anchor under
# review, not work of its own.
#
# The scope gate classifies the bead in the order orphan-dispose.sh uses: a
# visit, then a review (both by task_kind), then a graph.v2 root, then a
# graph.v2 step, else a source. It sets IS_WORK_BEAD=1 only for a source, and
# salvage and the merge check run only when IS_WORK_BEAD=1. A visit, review,
# step or root skips both checks, so salvage files no witness-salvage-refused
# for it and the merge check escalates no witness-branch-recovery-unknown. It
# still reaches part 5, where orphan-dispose.sh releases or skips it by the same
# class. The nothing-to-salvage gate gives the same path to a source bead that
# carries neither a work_dir nor a branch, since it has no worktree to salvage
# and no branch to check.
#
# What is exercised here:
#   * the gate EXTRACTED VERBATIM from the formula (between the salvage-scope-gate
#     markers), run exactly as the witness runs it — BEAD_JSON from `gc bd show`,
#     no set -e — so the test cannot drift from the shipped instruction;
#   * IS_WORK_BEAD across the five shapes recovery hands part 3, the precedence
#     (a visit outranks a step_ref), and the fail-safe (an unreadable bead
#     defaults to the work-bead path, so a real orphan is never skipped);
#   * CONFORMANCE: the gate and the real orphan-dispose.sh run over ONE store and
#     must agree — class=source iff IS_WORK_BEAD=1 — so the two classifiers cannot
#     drift apart;
#   * the NOTHING-TO-SALVAGE gate, extracted verbatim and run over work_dir/branch
#     combinations: a source bead with neither never had a worktree, so salvage
#     and part 4 skip it rather than file witness-salvage-refused and escalate
#     witness-branch-recovery-unknown for a branch that never existed;
#   * static wiring: the salvage refuse-branch and part 4 branch on IS_WORK_BEAD
#     and on NOTHING_TO_SALVAGE, and both gates are defined before the first
#     salvage `git add -A`, so an edit that drops either fails here rather than
#     silently filing the no-signal escalations;
#   * the formula parses as TOML.
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

# --- The shapes recovery hands part 3 (as in orphan-dispose.test.sh). ----------
# The step's assignee and gc.session_id both name the dead session; the root
# carries gc.kind/gc.formula_contract and only gc.session_name; the visit and the
# review carry task_kind (a review's review_branch names the anchor under review,
# not work of its own); the work bead carries a branch and no kind/step markers.
# The pre-work source bead (tk-bare) carries neither work_dir nor branch — its
# owner died before workspace-setup — so it classifies as a source the
# nothing-to-salvage arm skips.
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
    {"id":"tk-review","status":"in_progress","assignee":"lx-dead","title":"Review branch polecat/tk-anc -> main: a finding",
     "metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"tk-anc",
                 "review_branch":"polecat/tk-anc","review_base":"main",
                 "gc.routed_to":"gc-toolkit/gc-toolkit.polecat-codex",
                 "gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat-codex",
                 "gc.session_id":"lx-dead","gc.session_name":"polecat-5-pool"}},
    {"id":"tk-work","status":"in_progress","assignee":"lx-dead","title":"a work bead",
     "metadata":{"branch":"polecat/tk-work","gc.routed_to":"gc-toolkit/gc-toolkit.polecat",
                 "workflow_id":"tk-root","gc.session_id":"lx-dead","gc.session_name":"polecat-3-pool"}},
    {"id":"tk-bare","status":"in_progress","assignee":"lx-dead","title":"a pre-work source bead",
     "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat",
                 "gc.session_id":"lx-dead","gc.session_name":"polecat-4-pool"}}
  ]'
}

echo "--- behavioral matrix ---"
fixture
eq "$(gate_says tk-step)"  "0" "graph.v2 step  -> not a work bead (skip salvage)"
eq "$(gate_says tk-root)"  "0" "graph.v2 root  -> not a work bead (skip salvage)"
eq "$(gate_says tk-visit)" "0" "visit          -> not a work bead (skip salvage)"
eq "$(gate_says tk-review)" "0" "review         -> not a work bead (skip salvage/verify)"
eq "$(gate_says tk-work)"  "1" "source work bead -> IS_WORK_BEAD=1 (salvage runs)"
eq "$(gate_says tk-bare)"  "1" "pre-work source bead, no work_dir/branch -> IS_WORK_BEAD=1"

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
# case, so IS_WORK_BEAD must be 1 there and 0 for
# visit/review/workflow-root/workflow-step. If either classifier's precedence
# drifts, this fails.
fixture
for id in tk-step tk-root tk-visit tk-review tk-work tk-bare; do
  CLASS="$("$SCRIPT" "$id" --json | jq -r '.class // ""')"
  GW="$(gate_says "$id")"
  WANT=$([ "$CLASS" = "source" ] && echo 1 || echo 0)
  eq "$GW" "$WANT" "conformance: $id is class=$CLASS <-> IS_WORK_BEAD=$WANT"
done

echo "--- the nothing-to-salvage gate ---"
# A source bead (IS_WORK_BEAD=1) with neither work_dir nor branch never reached
# workspace-setup. The gate marks it so salvage and part 4 skip it, instead of
# filing a no-signal witness-salvage-refused and escalating
# witness-branch-recovery-unknown for a branch that never existed. Extracted
# verbatim and run the way the gate above is, so the test cannot drift from the
# shipped instruction.
NTS="$(awk '
  /# >>> nothing-to-salvage-gate/ {f=1; next}
  /# <<< nothing-to-salvage-gate/ {f=0}
  f' "$TOML")"
[ -n "$NTS" ] \
  && ok "nothing-to-salvage gate extracted between its markers" \
  || bad "nothing-to-salvage gate extraction EMPTY — markers missing from $TOML"
printf '%s\n' "$NTS" > "$TMP/nts.sh"
bash -n "$TMP/nts.sh" \
  && ok "extracted nothing-to-salvage gate is syntactically valid bash" \
  || bad "extracted nothing-to-salvage gate failed bash -n"

# nts_says <is_work_bead> <worktree> <branch> -> prints NOTHING_TO_SALVAGE.
nts_says() {
  IS_WORK_BEAD="$1" WORKTREE="$2" BRANCH="$3" bash -c '
    source "$0"
    printf "%s" "$NOTHING_TO_SALVAGE"
  ' "$TMP/nts.sh" 2>/dev/null
}
eq "$(nts_says 1 '' '')"                "1" "source, no work_dir, no branch -> nothing to salvage"
eq "$(nts_says 1 /tmp/wt '')"           "0" "source with a work_dir -> salvage the worktree"
eq "$(nts_says 1 '' polecat/tk-x)"      "0" "source with a branch -> verify it merged"
eq "$(nts_says 1 /tmp/wt polecat/tk-x)" "0" "source with both -> salvage and verify"
eq "$(nts_says 0 '' '')"                "0" "non-work bead -> inert (scope gate already skips it)"

echo "--- static wiring: salvage and verify must honor the gate ---"
# The gate protects anything only if the salvage refuse-branch and part 4 branch
# on IS_WORK_BEAD. Assert both, so an edit that drops a gate fails here rather
# than silently filing the no-signal escalations.
grep -qF 'if [ "$IS_WORK_BEAD" != "1" ]; then' "$TOML" \
  && ok "salvage block short-circuits when IS_WORK_BEAD != 1" \
  || bad "salvage block must branch on IS_WORK_BEAD"
grep -qF 'if [ "$IS_WORK_BEAD" = "1" ]; then' "$TOML" \
  && ok "part 4 verify runs only when IS_WORK_BEAD = 1" \
  || bad "part 4 verify must branch on IS_WORK_BEAD"

# The nothing-to-salvage arm protects a bead only if salvage and part 4 honor it.
# Assert both, so an edit that drops it fails here rather than silently filing
# the no-signal escalations. The salvage arm and the verify skip carry distinct
# strings, so neither assertion matches the other.
grep -qF 'elif [ "$NOTHING_TO_SALVAGE" = "1" ]; then' "$TOML" \
  && ok "salvage block skips a nothing-to-salvage bead (no witness-salvage-refused)" \
  || bad "salvage block must branch on NOTHING_TO_SALVAGE"
grep -qF 'BRANCH_MERGED=skip   # never had a branch' "$TOML" \
  && ok "part 4 verify skips a nothing-to-salvage bead (no witness-branch-recovery-unknown)" \
  || bad "part 4 verify must set BRANCH_MERGED=skip for NOTHING_TO_SALVAGE"

# The gate must be DEFINED before the first salvage `git add -A`, or salvage
# would run against an unset IS_WORK_BEAD. Anchor both to line start so prose
# mentioning either does not match.
GATE_LINE=$(grep -nE '^IS_WORK_BEAD=' "$TOML" | head -1 | cut -d: -f1)
FIRST_ADD=$(grep -nE '^[[:space:]]*git add -A' "$TOML" | head -1 | cut -d: -f1)
[ -n "$GATE_LINE" ] && [ -n "$FIRST_ADD" ] && [ "$GATE_LINE" -lt "$FIRST_ADD" ] \
  && ok "scope gate is defined before the first salvage 'git add -A'" \
  || bad "scope gate must be defined before any 'git add -A' (got gate@${GATE_LINE:-none} add@${FIRST_ADD:-none})"

# The nothing-to-salvage gate sits downstream of the scope gate and upstream of
# salvage, so it too must be defined before the first `git add -A`.
NTS_LINE=$(grep -nE '^NOTHING_TO_SALVAGE=0' "$TOML" | head -1 | cut -d: -f1)
[ -n "$NTS_LINE" ] && [ -n "$FIRST_ADD" ] && [ "$NTS_LINE" -lt "$FIRST_ADD" ] \
  && ok "nothing-to-salvage gate is defined before the first salvage 'git add -A'" \
  || bad "nothing-to-salvage gate must be defined before any 'git add -A' (got nts@${NTS_LINE:-none} add@${FIRST_ADD:-none})"

echo "--- formula still parses as TOML ---"
if TOML_PY="$(tomllib_python)"; then
  "$TOML_PY" - "$TOML" <<'PY' && ok "formula still parses as TOML" || bad "formula failed to parse as TOML"
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
else
  echo "skip - formula still parses as TOML: $TOML_PY"
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
