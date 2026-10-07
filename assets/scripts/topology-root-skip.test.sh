#!/usr/bin/env bash
# Hermetic test for the witness-patrol TOPOLOGY-ROOT SKIP filter.
#
# THE GUARDRAIL: mol-witness-patrol's recover-orphaned-beads must not run its
# liveness loop over a graph.v2 topology ROOT. A root carries gc.kind in the
# topology set (workflow, scope, spec) and names its owner only in
# gc.session_name — the pool SLOT, which a successor session keeps alive. So the
# host-bead-skip owner filter resolves that slot label and the liveness loop
# reads a dead run's root as ACTIVE, which routes it to the live-but-wedged
# warrant path and files a warrant against the successor now holding the slot,
# killing unrelated live work (the successor-inherited-slot-label bug). Resolved
# the other way, absent, a root only churns a witness-salvage-refused notice: it
# has no worktree, and orphan-dispose.sh already refuses it as root_not_schedulable.
# A topology root is not recoverable work — its STEP beads carry the work and the
# gc.session_id, and its close is the control-dispatcher's workflow-finalize — so
# it is dropped from the candidate set before the loop, the same kind set the hook
# (hookCandidateClaimable) and pool demand (demandRowServable) refuse and
# liveness-sweep.sh's topology_kind mirrors.
#
# It is a KIND exclusion, the sibling of the state exclusion downstream-court-skip:
# host-bead-skip keeps every owned bead (a root included, so its owner is stamped),
# and this runs on that result to remove the roots. A step bead (gc.session_id, no
# topology kind) is not a root and survives to be recovered.
#
# This test EXECUTES the real filters extracted verbatim from the formula (between
# the topology-root-skip and host-bead-skip markers), so it cannot drift from the
# shipped instruction. No live city, Dolt, network, or sessions — only jq and a
# tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-topology-root-skip-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# --- Extract the REAL filters from the formula. ------------------------------
# Pulls the lines between each pair of markers (exclusive). If a marker or its
# filter is removed/renamed, extraction yields nothing and the check below fails
# loudly — the guardrail cannot silently disappear.
extract() {
  awk -v tag="$1" '
    $0 ~ ("# >>> " tag "$") {f=1; next}
    $0 ~ ("# <<< " tag "$") {f=0}
    f' "$TOML"
}

FILTER="$(extract topology-root-skip)"
HOSTSKIP="$(extract host-bead-skip)"

[ -n "$FILTER" ] \
  && ok "filter extracted between topology-root-skip markers" \
  || bad "filter extraction EMPTY — markers missing from $TOML"
[ -n "$HOSTSKIP" ] \
  && ok "host-bead-skip extracted (needed for the composed-pipeline case)" \
  || bad "host-bead-skip extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$FILTER" > "$TMP/filter.sh"
printf '%s\n' "$HOSTSKIP" > "$TMP/hostskip.sh"
bash -n "$TMP/filter.sh" \
  && ok "extracted filter is syntactically valid bash" \
  || bad "extracted filter failed bash -n"

case "$FILTER" in
  *'\'*) bad "the filter carries a backslash — TOML triple-quote eats continuations" ;;
  *)     ok "the filter is backslash-free, as the formula header requires" ;;
esac

# keep <bead-array-json> -> the surviving ids, sorted and comma-joined. Run
# exactly as the witness runs it: a jq filter over the listing on stdin.
keep() {
  printf '%s' "$1" | bash "$TMP/filter.sh" 2>/dev/null \
    | jq -r 'sort_by(.id) | map(.id) | join(",")'
}

# pipeline <bead-array-json> -> ids surviving host-bead-skip THEN
# topology-root-skip, the way the candidate set is built before the loop.
pipeline() {
  printf '%s' "$1" | bash "$TMP/hostskip.sh" 2>/dev/null | bash "$TMP/filter.sh" 2>/dev/null \
    | jq -r 'sort_by(.id) | map(.id) | join(",")'
}

# --- Each kind, dropped or kept. ---------------------------------------------
# r1  gc.kind workflow  -> DROP (topology root)
# r2  gc.kind scope     -> DROP (scope latch)
# r3  gc.kind spec      -> DROP (step-spec sidecar)
# s1  no gc.kind, step  -> KEEP (a step carries the work; it is recovered)
# w1  no gc.kind, work  -> KEEP (an ordinary owned work bead)
# v1  task_kind visit   -> KEEP (a visit is not a topology root; it returns to
#     the pool — no kind carve-out, unlike the topology roots)
FIX='[
  {"id":"r1","metadata":{"gc.kind":"workflow","gc.session_name":"slot-1"}},
  {"id":"r2","metadata":{"gc.kind":"scope","gc.session_name":"slot-1"}},
  {"id":"r3","metadata":{"gc.kind":"spec","gc.session_name":"slot-1"}},
  {"id":"s1","metadata":{"gc.session_id":"lx-1","gc.session_affinity":"require"}},
  {"id":"w1","assignee":"gc-toolkit/gc-toolkit.rictus"},
  {"id":"v1","metadata":{"task_kind":"visit","gc.continuation_group":"tk-subj"}}
]'
eq "$(keep "$FIX")" "s1,v1,w1" \
   "drops the topology roots (workflow/scope/spec); keeps a step, an ordinary work bead, and a visit"

# Exact match on gc.kind: only the three literal topology kinds drop. A resembling
# value survives, so a later substring loosening cannot start dropping work — and
# workflow-finalize, a control bead the dispatcher-routed exclusion handles, is
# NOT a topology root and is not this filter's to drop.
FIX2='[
  {"id":"e1","metadata":{"gc.kind":"workflow-finalize"}},
  {"id":"e2","metadata":{"gc.kind":"workflows"}},
  {"id":"e3","metadata":{"gc.kind":"workflow"}},
  {"id":"e4","metadata":{"gc.kind":"ralph"}}
]'
eq "$(keep "$FIX2")" "e1,e2,e4" \
   "exact match: drops workflow; keeps workflow-finalize, workflows, and ralph"

# Empty listing -> empty result (never errors).
eq "$(keep '[]')" "" "empty listing yields empty result"

# Degenerate metadata neither errors nor drops: null, absent, and empty gc.kind
# carry no topology kind, so the bead is not a root and survives.
FIX3='[
  {"id":"m1","metadata":null},
  {"id":"m2","assignee":""},
  {"id":"m3","metadata":{"gc.kind":""}},
  {"id":"m4","metadata":{"gc.session_id":"lx-9"}}
]'
eq "$(keep "$FIX3")" "m1,m2,m3,m4" \
   "null, absent, and empty gc.kind all survive (no topology kind to match)"

# Survivors keep every field they arrived with — the liveness loop reads the bead,
# and host-bead-skip's `.owner` stamp must survive.
eq "$(printf '%s' '[{"id":"f1","owner":"lx-9","metadata":{"gc.session_id":"lx-9"}}]' \
      | bash "$TMP/filter.sh" 2>/dev/null | jq -r '.[0].owner')" "lx-9" \
   "a survivor keeps its fields (including the .owner host-bead-skip stamped)"

# --- The composed pipeline: host-bead-skip then topology-root-skip. -----------
# The exact shape the finding reported (tk-usezg2): an OWNED workflow ROOT — no
# assignee, no gc.session_id, only a gc.session_name naming a pool SLOT a live
# successor now holds. host-bead-skip KEEPS it (it names an owner), so
# topology-root-skip is what must drop it, leaving the loop nothing to warrant.
# The genuine step orphan beside it (a dead gc.session_id, no topology kind)
# survives to be recovered.
FIX4='[
  {"id":"tk-root","assignee":null,"metadata":{"gc.kind":"workflow","gc.session_name":"gc-toolkit--gc-toolkit__polecat-2-pool"}},
  {"id":"tk-step","assignee":null,"metadata":{"gc.session_id":"lx-dead","gc.session_affinity":"require","branch":"polecat/tk-step"}}
]'
eq "$(pipeline "$FIX4")" "tk-step" \
   "host-bead-skip | topology-root-skip drops the owned workflow root (tk-usezg2 shape), keeps the dead-session step orphan"

# The root's owner IS resolved by host-bead-skip — the drop is topology-root-skip's
# job, not a claim that the root names no owner. host-bead-skip alone keeps both.
eq "$(printf '%s' "$FIX4" | bash "$TMP/hostskip.sh" 2>/dev/null | jq -r 'sort_by(.id)|map(.id)|join(",")')" "tk-root,tk-step" \
   "host-bead-skip alone keeps the root (it names an owner); topology-root-skip is the drop"

echo
echo "topology-root-skip: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
