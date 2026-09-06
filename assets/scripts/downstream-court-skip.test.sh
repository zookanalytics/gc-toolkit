#!/usr/bin/env bash
# Hermetic test for the witness-patrol DOWNSTREAM-COURT SKIP filter.
#
# THE GUARDRAIL: mol-witness-patrol's recover-orphaned-beads must not recover a
# bead whose work has ALREADY REACHED a downstream court. Orphan recovery returns
# LOST work to the pool, but a bead in the refinery's landing pipeline or on a
# person's board is not lost. The polecat handoff and the human-gate handoff both
# leave the dead session's gc.session_id/gc.session_name on the bead, so the
# owner filter (host-bead-skip) resolves that dead owner and the liveness loop
# false-orphans it — even though its branch is pushed and its PR is in flight.
# Returning it to the pool re-dispatches finished work AND stamps a recovery, and
# the downstream crash-loop signal reads that stamp as a RATE off
# recovered_at/recovered_count, so a bead that keeps arriving here escalates a
# moot visit every cycle. Dropping such beads from the candidate set before the
# liveness loop is what stops both the re-dispatch and the escalation.
#
# Three states name work that is not the pool's to recover:
#   * an in-flight PR      — merge_result is pre_open_gate or pull_request;
#   * a progressing machine — pr.machine (a state@oid@ts stamp) whose state
#     segment is `progressing`;
#   * a human gate         — gc.routed_to=human.
# It is a state exclusion, not a kind exclusion: host-bead-skip keeps every owned
# bead (no class exempt), and this runs on its result to remove the ones already
# downstream. A bead carrying none of the three is still the pool's to recover.
#
# This test EXECUTES the real filters extracted verbatim from the formula
# (between the `downstream-court-skip` and `host-bead-skip` markers), so it cannot
# drift from the shipped instruction. No live city, Dolt, network, or sessions —
# only jq and a tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
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

FILTER="$(extract downstream-court-skip)"
HOSTSKIP="$(extract host-bead-skip)"

[ -n "$FILTER" ] \
  && ok "filter extracted between downstream-court-skip markers" \
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
# downstream-court-skip, the way the candidate set is built before the loop.
pipeline() {
  printf '%s' "$1" | bash "$TMP/hostskip.sh" 2>/dev/null | bash "$TMP/filter.sh" 2>/dev/null \
    | jq -r 'sort_by(.id) | map(.id) | join(",")'
}

# --- Each state, dropped. ----------------------------------------------------
# d1  merge_result pre_open_gate           -> DROP (in-flight, pre-open codex gate)
# d2  merge_result pull_request            -> DROP (in-flight, open PR)
# d3  pr.machine progressing@oid@ts        -> DROP (merge machine advancing)
# d4  gc.routed_to human                   -> DROP (a person owns it)
# k1  merge_result merged                  -> KEEP (landed; step 4 closes it)
# k2  merge_result empty                   -> KEEP (no PR — the pool's to recover)
# k3  no metadata key                      -> KEEP (robust to absent metadata)
FIX='[
  {"id":"d1","metadata":{"merge_result":"pre_open_gate"}},
  {"id":"d2","metadata":{"merge_result":"pull_request"}},
  {"id":"d3","metadata":{"pr.machine":"progressing@abc123@2026-09-05T00:00:00Z"}},
  {"id":"d4","metadata":{"gc.routed_to":"human"}},
  {"id":"k1","metadata":{"merge_result":"merged"}},
  {"id":"k2","metadata":{"merge_result":""}},
  {"id":"k3","assignee":"gc-toolkit/gc-toolkit.rictus"}
]'
eq "$(keep "$FIX")" "k1,k2,k3" \
   "drops in-flight PR (pre_open_gate/pull_request), progressing machine, and human gate; keeps merged/empty/absent"

# pr.machine is a state@oid@ts stamp: only the `progressing` state segment drops.
# `settled` (landed) and `wedged-exception` (already caught by merge_result/human
# on live beads) are not `progressing`, and a bare state without @ still parses.
FIX2='[
  {"id":"p1","metadata":{"pr.machine":"progressing@oid@ts"}},
  {"id":"p2","metadata":{"pr.machine":"settled@oid@ts"}},
  {"id":"p3","metadata":{"pr.machine":"wedged-exception@oid@ts"}},
  {"id":"p4","metadata":{"pr.machine":"progressing"}}
]'
eq "$(keep "$FIX2")" "p2,p3" \
   "drops on the progressing state segment only (with or without @oid@ts); keeps settled and wedged-exception"

# Exact match on merge_result and gc.routed_to: a resembling value survives, so a
# later substring loosening cannot start dropping work it should recover.
FIX3='[
  {"id":"e1","metadata":{"merge_result":"pull_request"}},
  {"id":"e2","metadata":{"merge_result":"pull_request_draft"}},
  {"id":"e3","metadata":{"gc.routed_to":"human"}},
  {"id":"e4","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.human-review"}}
]'
eq "$(keep "$FIX3")" "e2,e4" \
   "exact match: drops pull_request and human; keeps pull_request_draft and human-review"

# Empty listing -> empty result (never errors).
eq "$(keep '[]')" "" "empty listing yields empty result"

# Degenerate metadata neither errors nor drops: null and absent metadata carry no
# downstream state, so the bead is still the pool's to recover.
FIX4='[
  {"id":"m1","metadata":null},
  {"id":"m2","assignee":""},
  {"id":"m3","metadata":{"gc.session_id":"lx-1"}}
]'
eq "$(keep "$FIX4")" "m1,m2,m3" \
   "null, absent, and unrelated metadata all survive (no downstream state to read)"

# Survivors keep every field they arrived with — the liveness loop reads the
# bead, not just its state, and host-bead-skip's `.owner` stamp must survive.
eq "$(printf '%s' '[{"id":"f1","owner":"lx-9","metadata":{"merge_result":"merged","gc.session_id":"lx-9"}}]' \
      | bash "$TMP/filter.sh" 2>/dev/null | jq -r '.[0].owner')" "lx-9" \
   "a survivor keeps its fields (including the .owner host-bead-skip stamped)"

# --- The composed pipeline: host-bead-skip then downstream-court-skip. --------
# The shape that reaches the loop as a false orphan: an OWNED bead (a dead-session
# pin in gc.session_name) whose work already reached an in-flight PR.
# host-bead-skip keeps it because it names an owner, so downstream-court-skip is
# what must drop it, leaving the composed candidate set with nothing to offer the
# loop. Two in-flight shapes drop: an open PR (merge_result pull_request, on a
# human gate, its merge machine wedged) and a pre-open gate (merge_result
# pre_open_gate). The genuine orphan beside them (a dead session, a pushed branch,
# but NO PR) survives to be recovered.
FIX5='[
  {"id":"tk-owned-pr","assignee":null,"metadata":{"gc.session_name":"polecat-1-pool","merge_result":"pull_request","gc.routed_to":"human","pr.machine":"wedged-exception@c142@ts"}},
  {"id":"tk-owned-gate","assignee":null,"metadata":{"gc.session_name":"polecat-2-pool","merge_result":"pre_open_gate","gc.routed_to":"human"}},
  {"id":"tk-lost","assignee":"gc-toolkit--gc-toolkit__polecat-1-pool","metadata":{"gc.session_id":"lx-dead","branch":"polecat/tk-lost"}}
]'
eq "$(pipeline "$FIX5")" "tk-lost" \
   "host-bead-skip | downstream-court-skip drops the in-flight orphans (owned PR + pre-open gate), keeps the genuine dead-session orphan (tk-lost)"

echo
echo "downstream-court-skip: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
