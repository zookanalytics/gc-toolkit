#!/usr/bin/env bash
# Hermetic test for the witness-patrol OWNED-ONLY SKIP filter.
#
# THE GUARDRAIL: mol-witness-patrol's recover-orphaned-beads scan considers
# only beads that name an OWNER, and stamps that owner as `.owner` for the
# liveness loop. A bead naming no owner is already in the pool's court and
# needs no recovery. Owned-but-dead beads are exactly the witness's recovery
# domain: no class of owned bead is exempt from
# orphan recovery. Visits and their
# converse sessions need no carve-out either — a visit whose session died
# mid-hold SHOULD return to the pool (respawn-and-reconstitute-from-the-record
# is the cold continuity path; specs/2026-08-fresh-start/spine-port.md, D4).
#
# A bead names its owner in one of three places. `assignee` is the direct form
# and the only one a `gc bd list --json` row shows on its own: the key is
# omitted when empty, which is the shape every workflow STEP bead has. A step
# names its owner in metadata.gc.session_id, which is what
# gc.session_affinity=require pins it to, and a workflow ROOT names only
# metadata.gc.session_name. A filter reading `assignee` alone therefore cannot
# see graph.v2 machinery at all, and orphan recovery cannot reach the beads it
# exists to recover.
#
# Precedence runs session id, then assignee, then session name. A session id is
# re-stamped on every claim and names the session actually holding the bead; the
# other two are labels a successor inherits, because pool work is assigned to the
# SLOT and the slot stays live under its next occupant. The order is what decides
# a crashed pool session's step bead, which keeps a live slot assignee beside its
# dead id.
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

# owners <bead-array-json> -> "<id>=<owner>" for each survivor, sorted and
# comma-joined, so a case can assert WHICH signal the filter resolved.
owners() {
  printf '%s' "$1" | bash "$TMP/filter.sh" 2>/dev/null \
    | jq -r 'sort_by(.id) | map("\(.id)=\(.owner)") | join(",")'
}

# The assignee-only predicate, for the premise assertions below.
assignee_only_ids() {
  printf '%s' "$1" | jq -r '[ .[] | select((.assignee // "") != "") ]
    | sort_by(.id) | map(.id) | join(",")'
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

# --- Owner signals that are not an assignee. ---------------------------------
# s1  workflow STEP bead: no assignee key at all, owner in gc.session_id
# s2  workflow ROOT bead: no assignee, owner in gc.session_name only
# s3  workflow machinery naming no session at all -> DROP (nothing to resolve)
FIX3='[
  {"id":"s1","metadata":{"gc.session_id":"lx-7xcse","gc.session_name":"gc-toolkit__polecat-lx-7xcse","gc.session_affinity":"require"}},
  {"id":"s2","metadata":{"gc.kind":"workflow","gc.session_name":"gc-toolkit--gc-toolkit__polecat-1-pool"}},
  {"id":"s3","metadata":{"gc.kind":"workflow","gc.root_bead_id":"tk-root"}}
]'
eq "$(assignee_only_ids "$FIX3")" "" \
   "(premise) an assignee-only predicate sees no workflow step or root at all"
eq "$(ids "$FIX3")" "s1,s2" \
   "keeps a step owned via gc.session_id and a root owned via gc.session_name; drops the ownerless s3"
eq "$(owners "$FIX3")" "s1=lx-7xcse,s2=gc-toolkit--gc-toolkit__polecat-1-pool" \
   "stamps .owner from whichever signal the bead carries"

# Precedence, most specific first: gc.session_id, then assignee, then
# gc.session_name. The whole order is load-bearing. Both labels are handed on to
# a slot's next occupant, so a bead pinned to a dead id must resolve against that
# id and not against the live session now holding the slot. a1 is the shape a
# crashed pool session leaves behind: assignee and session name both name the
# still-live slot, and only the id remembers who actually died.
FIX4='[
  {"id":"a1","assignee":"gc-toolkit--gc-toolkit__polecat-1-pool","metadata":{"gc.session_id":"lx-dead","gc.session_name":"gc-toolkit--gc-toolkit__polecat-1-pool"}},
  {"id":"a2","assignee":"","metadata":{"gc.session_id":"lx-dead","gc.session_name":"slot-1"}},
  {"id":"a3","assignee":"gc-toolkit/gc-toolkit.furiosa","metadata":{"gc.session_name":"slot-1"}},
  {"id":"a4","assignee":"","metadata":{"gc.session_name":"slot-1"}}
]'
eq "$(owners "$FIX4")" "a1=lx-dead,a2=lx-dead,a3=gc-toolkit/gc-toolkit.furiosa,a4=slot-1" \
   "owner precedence: gc.session_id, then assignee, then gc.session_name"

# Degenerate metadata must neither error nor invent an owner. A bead with every
# signal empty is as unowned as one with no metadata key.
FIX5='[
  {"id":"m1","assignee":"","metadata":null},
  {"id":"m2","assignee":""},
  {"id":"m3","metadata":{"gc.session_id":"","gc.session_name":""}},
  {"id":"m4","metadata":{"gc.session_id":"lx-live"}}
]'
eq "$(ids "$FIX5")" "m4" \
   "null metadata, absent metadata and empty session keys yield no owner"

# Survivors keep every field they arrived with — the liveness loop reads the
# bead, not just its owner.
eq "$(printf '%s' "$FIX3" | bash "$TMP/filter.sh" 2>/dev/null \
      | jq -r '.[] | select(.id == "s1") | .metadata["gc.session_affinity"]')" "require" \
   "the stamp adds .owner without dropping the bead's own fields"

echo
echo "host-bead-skip: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
