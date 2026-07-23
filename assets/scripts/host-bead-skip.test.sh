#!/usr/bin/env bash
# Hermetic test for the witness-patrol GROUNDED-BEAD-HOST SKIP filter (tk-z130v.3).
#
# THE GUARDRAIL: gc-bead-host.sh now GROUNDS a bead-host by setting its work
# bead's `assignee` to its own session NAME, so the reconciler revives the host
# across an involuntary config-drift drain. That makes a host bead read as
# "assigned" in mol-witness-patrol's recover-orphaned-beads scan (which today
# only skips beads with NO assignee). A bead-host is NOT pool/ephemeral work —
# its lifecycle is owned by the bead-host tooling (gc-bead-host.sh link/unlink,
# gc-helm takeaway --release) — so orphan recovery must not reclaim it into the
# polecat pool. The revival scenario is already safe (drained/asleep classify as
# not-orphaned), but a host whose session went archived/closed/absent would be
# false-recovered; per the #206/#210 precedent this is closed by CODE, not
# witness judgment. The fix drops grounded host beads in the same filter that
# skips unassigned beads, recognizing them structurally:
# metadata.host_session_name == assignee.
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
# u1  unassigned bead                          -> DROP (skip-unassigned)
# p1  normal pool polecat, assigned            -> KEEP (a real orphan candidate)
# h1  grounded bead-host (assignee==host name) -> DROP (owned by bead-host tooling)
# h2  host bead whose assignee != host name    -> KEEP (assigned to a real agent,
#     NOT grounded to its own host — the filter is precise, it does not over-skip
#     every bead that merely carries a host_session_name)
# n1  assigned bead with NO metadata object    -> KEEP (robust to absent metadata)
FIX='[
  {"id":"u1","assignee":"",                              "metadata":{}},
  {"id":"p1","assignee":"gc-toolkit/gc-toolkit.furiosa", "metadata":{}},
  {"id":"h1","assignee":"s-h1",                          "metadata":{"host_session_name":"s-h1","host_session":"sb-h1"}},
  {"id":"h2","assignee":"someone-else",                  "metadata":{"host_session_name":"s-h2"}},
  {"id":"n1","assignee":"gc-toolkit/gc-toolkit.rictus"}
]'
eq "$(ids "$FIX")" "h2,n1,p1" \
   "drops unassigned (u1) + grounded host (h1); keeps assigned non-host (p1,n1) and a host assigned elsewhere (h2)"

# The grounded host is dropped regardless of the session_name FORM — a bare
# s-<id> or a rig-qualified alias both work, because equality is what matters
# (not a prefix pattern).
FIX2='[
  {"id":"a","assignee":"gascity/gc-toolkit.gc-z0vi2","metadata":{"host_session_name":"gascity/gc-toolkit.gc-z0vi2"}},
  {"id":"b","assignee":"gc-toolkit/gc-toolkit.furiosa","metadata":{}}
]'
eq "$(ids "$FIX2")" "b" \
   "drops a grounded host with a rig-qualified session_name assignee; keeps a normal polecat"

# Empty listing -> empty result (never errors).
eq "$(ids '[]')" "" "empty listing yields empty result"

echo
echo "host-bead-skip: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
