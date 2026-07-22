#!/usr/bin/env bash
# Hermetic test for the witness-patrol LIVENESS LOOKUP normalization (tk-opfsi).
#
# THE BUG: mol-witness-patrol's recover-orphaned-beads resolved a bead's assignee
# against the session liveness map by EXACT key lookup:
#
#     STATE=$(printf '%s' "$LIVENESS_MAP" | jq -r --arg a "$ASSIGNEE" '.[$a] // "absent"')
#
# The map is keyed on session-registered identities, which routinely differ from
# the bead's assignee in nothing but the `<rig>/` prefix — and BOTH shapes occur
# live in this city:
#
#     bead assignee  gascity/gc-toolkit.gc-z0vi2  vs  alias  gc-toolkit.gc-z0vi2
#     bead assignee  gc-toolkit.furiosa           vs  alias  gc-toolkit/gc-toolkit.furiosa
#
# The lookup fell through to `absent`, which the step classifies as ORPHANED —
# "the owning session is gone and will never come back" — for a session that is
# active and running. Confirmed firing on gc-z0vi2.1 (status=open, owner active);
# containment held only because the witness agent noticed by judgment. Unlike the
# sibling orphan-sweep.sh path (tk-2l13a), this step enumerates `open` beads too,
# so the exposure was live, not latent.
#
# THE FIX: keep the exact lookup as the authoritative first pass, then retry ONCE
# on the identity's last `/`-separated segment. Because stripping the prefix can
# make two sessions in different cities collide on one bare identity, the retry
# resolves a collision toward LIFE: any matching session that is not
# closed/archived wins. It can therefore turn `absent` into a live state but can
# never manufacture an orphan.
#
# This test EXECUTES the real lookup extracted verbatim from the formula (between
# the `liveness-lookup` markers), so it cannot drift from the shipped instruction.
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

# --- Extract the REAL lookup from the formula. -------------------------------
# Pulls the lines between the markers (exclusive). If the markers or the lookup
# are removed/renamed, extraction yields nothing and the check below fails
# loudly — the contract cannot silently disappear.
LOOKUP="$(awk '
  /# >>> liveness-lookup/ {f=1; next}
  /# <<< liveness-lookup/ {f=0}
  f' "$TOML")"

[ -n "$LOOKUP" ] \
  && ok "lookup extracted between liveness-lookup markers" \
  || bad "lookup extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$LOOKUP" > "$TMP/lookup.sh"
bash -n "$TMP/lookup.sh" \
  && ok "extracted lookup is syntactically valid bash" \
  || bad "extracted lookup failed bash -n"

# state <liveness-map-json> <assignee> -> prints the resolved STATE.
# The snippet is sourced exactly as the witness runs it: LIVENESS_MAP and
# ASSIGNEE preset by the per-bead loop, no set -e.
state() {
  LIVENESS_MAP="$1" ASSIGNEE="$2" bash -c '
    LIVENESS_MAP="$LIVENESS_MAP"
    ASSIGNEE="$ASSIGNEE"
    source "$0"
    printf "%s" "$STATE"
  ' "$TMP/lookup.sh" 2>/dev/null
}

# The exact-only lookup as it shipped BEFORE the fix, for the premise assertions.
old_state() {
  printf '%s' "$1" | jq -r --arg a "$2" '.[$a] // "absent"'
}

# --- Fixtures, transcribed from live `gc session list --json` output. ---------
# A bead-host wisp registers a BARE alias; its beads carry a rig-qualified
# assignee. A pool polecat registers a RIG-QUALIFIED alias; a bead may carry the
# bare form. Same city, both directions, at the same time.
MAP_BEADHOST='{"lx-wisp-q5qbl":"active","s-lx-wisp-q5qbl":"active","gc-toolkit.gc-z0vi2":"active"}'
MAP_POOL='{"lx-fjnq1":"active","gc-toolkit__polecat-lx-fjnq1":"active","gc-toolkit/gc-toolkit.furiosa":"active"}'

# --- Premise: the bug is real and this is the exact shape that fired. ---------
eq "$(old_state "$MAP_BEADHOST" "gascity/gc-toolkit.gc-z0vi2")" "absent" \
   "(premise) exact-only lookup resolves a live bead-host to 'absent' (the bug)"
eq "$(old_state "$MAP_POOL" "gc-toolkit.furiosa")" "absent" \
   "(premise) exact-only lookup resolves a live pool polecat to 'absent' (reverse shape)"

# --- Behavioral matrix. ------------------------------------------------------
# (A) THE FIX, confirmed-firing shape: rig-qualified assignee, bare alias key.
#     `absent` here is what classifies a live agent's bead as orphaned.
eq "$(state "$MAP_BEADHOST" "gascity/gc-toolkit.gc-z0vi2")" "active" \
   "(A) qualified assignee vs bare alias key -> live, not orphaned"
# (B) Reverse direction: bare assignee, rig-qualified alias key. Both shapes are
#     live in the same city, so a one-directional fix would still false-orphan.
eq "$(state "$MAP_POOL" "gc-toolkit.furiosa")" "active" \
   "(B) bare assignee vs qualified alias key -> live, not orphaned"
# (C) Non-regression: an EXACT hit stays authoritative even when a bare-form
#     collision would answer differently. The retry must not override a literal
#     map key — that is how a genuinely dead session still gets recovered.
eq "$(state '{"gascity/gc-toolkit.furiosa":"closed","gc-toolkit.furiosa":"active"}' \
            "gascity/gc-toolkit.furiosa")" "closed" \
   "(C) exact match wins over a bare-form collision (dead session still orphaned)"
# (D) Non-regression, the witness's core job: an identity in NO session must
#     still resolve absent. A fallback that rescued everything would disable
#     orphan recovery entirely.
eq "$(state "$MAP_POOL" "gc-toolkit/gc-toolkit.long-gone")" "absent" \
   "(D) unknown identity -> absent (orphan recovery still works)"
# (E) Collision resolved toward LIFE: two cities' sessions bare to one identity,
#     one dead and one alive. Answering 'closed' here would re-introduce the bug
#     through the fix itself.
eq "$(state '{"gc-toolkit/gc-toolkit.furiosa":"closed","gascity/gc-toolkit.furiosa":"active"}' \
            "gc-toolkit.furiosa")" "active" \
   "(E) bare-form collision, one owner alive -> live wins (fail-safe direction)"
# (F) Ordering must not decide it — same collision, dead key listed second.
eq "$(state '{"gascity/gc-toolkit.furiosa":"active","gc-toolkit/gc-toolkit.furiosa":"closed"}' \
            "gc-toolkit.furiosa")" "active" \
   "(F) collision preference is order-independent"
# (G) Every live state in the step's classification list must beat a dead one,
#     not just 'active' — the controller/operator states own the session too.
for live in active awake creating asleep drained suspended draining quarantined; do
  eq "$(state "{\"a/x\":\"closed\",\"b/x\":\"$live\"}" "x")" "$live" \
     "(G) collision with a '$live' owner -> '$live' (not orphaned)"
done
# (H) When EVERY candidate owner is dead the fallback reports dead — the retry
#     rescues live sessions, it does not resurrect gone ones.
eq "$(state '{"r1/x":"closed","r2/x":"archived"}' "x")" "closed" \
   "(H) all candidates closed/archived -> dead state preserved (still orphaned)"
eq "$(state '{"r1/x":"archived"}' "x")" "archived" \
   "(H) archived-only candidate -> archived (still orphaned)"
# (I) Matching is on the WHOLE last segment, never a suffix/substring. A suffix
#     rule would silently alias distinct agents onto each other.
eq "$(state '{"gc-toolkit.furiosa":"active"}' "toolkit.furiosa")" "absent" \
   "(I) suffix-but-not-equal identity does not match (no substring aliasing)"
eq "$(state '{"gc-toolkit.furiosa":"active"}' "gc-toolkit.furiosa-2")" "absent" \
   "(I) sibling pool identity does not match"
# (J) Multi-segment assignees resolve on the last segment.
eq "$(state "$MAP_BEADHOST" "city/rig/gc-toolkit.gc-z0vi2")" "active" \
   "(J) multi-segment assignee resolves on its last segment"
# (K) Degenerate inputs: the loop skips unassigned beads, but an empty or
#     whitespace assignee must never resolve to some arbitrary session.
eq "$(state "$MAP_BEADHOST" "")" "absent" \
   "(K) empty assignee -> absent"
eq "$(state '{}' "gascity/gc-toolkit.gc-z0vi2")" "absent" \
   "(K) empty map -> absent (fail-safe abort is handled separately by MAP_COUNT)"
# (L) A trailing-slash identity must not match the whole map via an empty bare
#     form; keys are non-empty so this stays absent rather than aliasing.
eq "$(state "$MAP_BEADHOST" "gascity/")" "absent" \
   "(L) trailing-slash assignee -> absent (no empty-segment wildcard)"

# --- Static wiring: no un-normalized lookup may survive elsewhere. ------------
# The fix only holds if the marked snippet is the ONLY place an assignee is
# resolved. A second exact-only `.[$a] // "absent"` would re-open the hole.
EXACT_LOOKUPS=$(grep -cF '.[$a] // "absent"' "$TOML" || true)
eq "$EXACT_LOOKUPS" "1" \
   "(M) exactly one exact-match lookup in the formula (the guarded first pass)"

# The retry must be conditional on the exact pass missing, not unconditional.
grep -qF 'if [ "$STATE" = "absent" ]; then' "$TMP/lookup.sh" \
  && ok "(N) normalizing retry fires only when the exact lookup misses" \
  || bad "(N) normalizing retry must be gated on the exact lookup missing"

# The classification prose must not tell a future reader to decide on the exact
# lookup alone — that instruction is what the bug was made of.
grep -qF 'after BOTH the exact lookup and the' "$TOML" \
  && ok "(O) classification prose requires both passes before orphaning" \
  || bad "(O) classification prose must require both passes before orphaning"

# The formula must still parse as TOML after the edit (the snippet lives inside a
# multi-line basic string, where a stray backslash escape would corrupt it).
if command -v python3 >/dev/null 2>&1; then
  python3 - "$TOML" <<'PY' && ok "(P) formula still parses as TOML" || bad "(P) formula failed to parse as TOML"
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
