#!/usr/bin/env bash
# Hermetic test for the witness-patrol ASSIGNED-ONLY SKIP filter.
#
# THE GUARDRAIL: mol-witness-patrol's recover-orphaned-beads scan considers
# only beads WITH an assignee — an unassigned bead is already in the pool's
# court and needs no recovery. Assigned-but-dead beads are exactly the
# witness's recovery domain: with the v1 per-bead host mechanism retired there is
# no class of assigned bead that orphan recovery must skip. Visits and their
# converse sessions need no carve-out either — a visit whose session died
# mid-hold SHOULD return to the pool (respawn-and-reconstitute-from-the-record
# is the cold continuity path; specs/2026-08-fresh-start/spine-port.md, D4).
#
# This test EXECUTES the real filter extracted verbatim from the formula (between
# the `host-bead-skip` markers), so it cannot drift from the shipped instruction.
# No live city, Dolt, network, or sessions — only jq and a tmpdir.
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

# --- Extract the REAL filter from the formula. -------------------------------
# Pulls the lines between the markers (exclusive). If the markers or the filter
# are removed/renamed, extraction yields nothing and the check below fails
# loudly — the guardrail cannot silently disappear.
FILTER="$(awk '
  /# >>> host-bead-skip/ {f=1; next}
  /# <<< host-bead-skip/ {f=0}
  f' "$TOML")"

[ -n "$FILTER" ] \
  && ok "filter extracted between host-bead-skip markers" \
  || bad "filter extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$FILTER" > "$TMP/filter.sh"
bash -n "$TMP/filter.sh" \
  && ok "extracted filter is syntactically valid bash" \
  || bad "extracted filter failed bash -n"

# ids <bead-array-json> -> the surviving ids, sorted and comma-joined. The
# snippet is run exactly as the witness runs it: a jq filter over the listing on
# stdin.
ids() {
  printf '%s' "$1" | bash "$TMP/filter.sh" 2>/dev/null \
    | jq -r 'sort_by(.id) | map(.id) | join(",")'
}

# --- Fixtures. ---------------------------------------------------------------
# u1  unassigned bead                 -> DROP (skip-unassigned)
# p1  pool polecat, assigned          -> KEEP (a real orphan candidate)
# v1  visit bead, assigned            -> KEEP (a dead-session visit returns to
#     the pool — cold-restart is the continuity path; no visit carve-out)
# n1  assigned bead with NO metadata  -> KEEP (robust to absent metadata)
FIX='[
  {"id":"u1","assignee":"",                              "metadata":{}},
  {"id":"p1","assignee":"gc-toolkit/gc-toolkit.furiosa", "metadata":{}},
  {"id":"v1","assignee":"gc-toolkit/gc-toolkit.converse","metadata":{"task_kind":"visit","gc.continuation_group":"tk-subj"}},
  {"id":"n1","assignee":"gc-toolkit/gc-toolkit.rictus"}
]'
eq "$(ids "$FIX")" "n1,p1,v1" \
   "drops unassigned (u1); keeps every assigned bead incl. a visit (p1,v1,n1)"

# The assignee FORM does not matter — bare, rig-qualified, or a raw session
# name all read as assigned; only emptiness drops a bead.
FIX2='[
  {"id":"a","assignee":"gascity/gc-toolkit.gc-z0vi2","metadata":{}},
  {"id":"b","assignee":"gc-toolkit__polecat-lx-fjnq1","metadata":{}},
  {"id":"c","assignee":"","metadata":{"task_kind":"visit"}}
]'
eq "$(ids "$FIX2")" "a,b" \
   "keeps any non-empty assignee form; drops the unassigned visit (c)"

# Empty listing -> empty result (never errors).
eq "$(ids '[]')" "" "empty listing yields empty result"

echo
echo "host-bead-skip: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
