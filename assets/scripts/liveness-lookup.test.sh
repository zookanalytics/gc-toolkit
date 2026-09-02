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

# state <liveness-map-json> <owner> -> prints the resolved STATE.
# The snippet is sourced exactly as the witness runs it: LIVENESS_MAP and OWNER
# preset by the per-bead loop, no set -e. OWNER is whichever identity the
# host-bead-skip filter stamped on the bead — an assignee, a session name, or a
# session id; the map is keyed on all three, so one lookup answers for any of
# them.
state() {
  LIVENESS_MAP="$1" OWNER="$2" bash -c '
    LIVENESS_MAP="$LIVENESS_MAP"
    OWNER="$OWNER"
    source "$0"
    printf "%s" "$STATE"
  ' "$TMP/lookup.sh" 2>/dev/null
}

# --- Compose the owner derivation with the lookup. ---------------------------
# The loop never sees a raw assignee: it resolves the `.owner` that the
# host-bead-skip filter stamped. Extract that filter too and run the two blocks
# in series, so a case can start from a whole bead rather than a bare identity.
FILTER="$(awk '
  /# >>> host-bead-skip/ {f=1; next}
  /# <<< host-bead-skip/ {f=0}
  f' "$TOML")"

[ -n "$FILTER" ] \
  && ok "owner filter extracted between host-bead-skip markers" \
  || bad "owner filter extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$FILTER" > "$TMP/filter.sh"

# bead_state <liveness-map-json> <bead-json> -> the resolved STATE, or the empty
# string when the filter drops the bead as naming no owner.
bead_state() {
  local owner
  owner=$(printf '[%s]' "$2" | bash "$TMP/filter.sh" 2>/dev/null | jq -r '.[0].owner // empty')
  [ -n "$owner" ] || return 0
  state "$1" "$owner"
}

# The exact-only lookup as it shipped BEFORE the fix, for the premise assertions.
old_state() {
  printf '%s' "$1" | jq -r --arg a "$2" '.[$a] // "absent"'
}

# --- Fixtures, transcribed from live `gc session list --json` output. ---------
# A city-scoped wisp registers a BARE alias; its beads carry a rig-qualified
# assignee. A pool polecat registers a RIG-QUALIFIED alias; a bead may carry the
# bare form. Same city, both directions, at the same time.
MAP_CITYWISP='{"lx-wisp-q5qbl":"active","s-lx-wisp-q5qbl":"active","gc-toolkit.gc-z0vi2":"active"}'
MAP_POOL='{"lx-fjnq1":"active","gc-toolkit__polecat-lx-fjnq1":"active","gc-toolkit/gc-toolkit.furiosa":"active"}'

# --- Premise: the bug is real and this is the exact shape that fired. ---------
eq "$(old_state "$MAP_CITYWISP" "gascity/gc-toolkit.gc-z0vi2")" "absent" \
   "(premise) exact-only lookup resolves a live city-scoped wisp to 'absent' (the bug)"
eq "$(old_state "$MAP_POOL" "gc-toolkit.furiosa")" "absent" \
   "(premise) exact-only lookup resolves a live pool polecat to 'absent' (reverse shape)"

# --- Behavioral matrix. ------------------------------------------------------
# (A) THE FIX, confirmed-firing shape: rig-qualified assignee, bare alias key.
#     `absent` here is what classifies a live agent's bead as orphaned.
eq "$(state "$MAP_CITYWISP" "gascity/gc-toolkit.gc-z0vi2")" "active" \
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
eq "$(state "$MAP_CITYWISP" "city/rig/gc-toolkit.gc-z0vi2")" "active" \
   "(J) multi-segment assignee resolves on its last segment"
# (K) Degenerate inputs: the loop skips unassigned beads, but an empty or
#     whitespace assignee must never resolve to some arbitrary session.
eq "$(state "$MAP_CITYWISP" "")" "absent" \
   "(K) empty assignee -> absent"
eq "$(state '{}' "gascity/gc-toolkit.gc-z0vi2")" "absent" \
   "(K) empty map -> absent (the fail-safe abort is the liveness-map-guard block)"
# (L) A trailing-slash identity must not match the whole map via an empty bare
#     form; keys are non-empty so this stays absent rather than aliasing.
eq "$(state "$MAP_CITYWISP" "gascity/")" "absent" \
   "(L) trailing-slash assignee -> absent (no empty-segment wildcard)"

# --- Whole-bead classification: owners that are not assignees. ----------------
# A workflow STEP bead carries no assignee at all — `gc bd list --json` omits the
# key when it is empty — and names its owner in gc.session_id, which is what
# gc.session_affinity=require pins it to. A workflow ROOT names only
# gc.session_name. Resolving those is what lets orphan recovery see graph.v2
# machinery; resolving them WRONG either strands the chain or yanks a live one.
MAP_STEP='{"lx-3rk8v":"active","gc-toolkit--gc-toolkit__polecat-1-pool":"active"}'

# (Q) The recovery case: the pinned session is gone from the map entirely.
eq "$(bead_state "$MAP_STEP" '{"id":"st1","metadata":{"gc.session_id":"lx-7xcse","gc.session_name":"gc-toolkit__polecat-lx-7xcse","gc.session_affinity":"require"}}')" "absent" \
   "(Q) step bead, no assignee, DEAD gc.session_id -> absent (orphaned)"
# (Q) The same shape on a live session must be left alone.
eq "$(bead_state "$MAP_STEP" '{"id":"st2","metadata":{"gc.session_id":"lx-3rk8v","gc.session_name":"gc-toolkit--gc-toolkit__polecat-1-pool","gc.session_affinity":"require"}}')" "active" \
   "(Q) step bead, no assignee, LIVE gc.session_id -> active (not orphaned)"
# (R) A dead id whose pool SLOT is live still reads dead. The slot name belongs
#     to whoever holds the slot now; the id belongs to the session that will
#     never return, and gc.session_affinity=require pins the bead to the id. This
#     is why the owner precedence puts the id ahead of BOTH labels.
eq "$(bead_state "$MAP_STEP" '{"id":"st3","metadata":{"gc.session_id":"lx-7xcse","gc.session_name":"gc-toolkit--gc-toolkit__polecat-1-pool"}}')" "absent" \
   "(R) dead session id outranks a live pool slot name -> still orphaned"
# (R) The same, one level in: this is the shape a pool session leaves when it
#     crashes mid-claim, before anything clears the bead. `assignee` is the SLOT,
#     which the next occupant makes live again, so an assignee-first precedence
#     reads the successor's life as the dead owner's and the bead is stranded
#     in_progress forever — the very repeat-recovery engine this step exists to
#     stop. Only the id remembers who died.
eq "$(bead_state "$MAP_STEP" '{"id":"st4","assignee":"gc-toolkit--gc-toolkit__polecat-1-pool","metadata":{"gc.session_id":"lx-7xcse","gc.session_name":"gc-toolkit--gc-toolkit__polecat-1-pool","gc.session_affinity":"require"}}')" "absent" \
   "(R) dead session id outranks a LIVE slot assignee -> orphaned, not stranded"
# (S) A workflow root has only a session name. A per-instance name dies with its
#     session; a slot name outlives it, and recovery must not yank the live one.
eq "$(bead_state "$MAP_STEP" '{"id":"rt1","metadata":{"gc.kind":"workflow","gc.session_name":"gc-toolkit--gc-toolkit__polecat-1-pool"}}')" "active" \
   "(S) workflow root on a live session name -> active"
eq "$(bead_state "$MAP_STEP" '{"id":"rt2","metadata":{"gc.kind":"workflow","gc.session_name":"gc-toolkit__polecat-lx-7xcse"}}')" "absent" \
   "(S) workflow root on a dead per-instance session name -> absent"
# (T) With no session id to be more specific than it, the assignee decides —
#     the established assignee path is untouched for every bead that has one.
eq "$(bead_state '{"gc-toolkit/gc-toolkit.furiosa":"active"}' '{"id":"b1","assignee":"gc-toolkit/gc-toolkit.furiosa"}')" "active" \
   "(T) assignee alone still decides a bead carrying no session id"
# (T) A live session id keeps its bead when the assignee is the one that died,
#     so the reordering cannot manufacture an orphan either.
eq "$(bead_state '{"gc-toolkit/gc-toolkit.furiosa":"closed","lx-3rk8v":"active"}' '{"id":"b3","assignee":"gc-toolkit/gc-toolkit.furiosa","metadata":{"gc.session_id":"lx-3rk8v"}}')" "active" \
   "(T) live session id outranks a dead assignee -> not orphaned"
# (U) The normalizing retry applies to a session-derived owner like any other.
eq "$(bead_state '{"gascity/gc-toolkit.gc-z0vi2":"active"}' '{"id":"b2","metadata":{"gc.session_name":"gc-toolkit.gc-z0vi2"}}')" "active" \
   "(U) a session-name owner gets the same last-segment retry"
# (V) A bead naming no owner never reaches the lookup — recovery has nothing to
#     resolve, and inventing an owner for it would be the false-orphan path.
eq "$(bead_state "$MAP_STEP" '{"id":"n1","metadata":{"gc.kind":"workflow","gc.root_bead_id":"tk-root"}}')" "" \
   "(V) ownerless bead is dropped by the filter, never classified"

# --- Fail-safe guard: only an unloadable map may skip orphan recovery. -------
# THE SECOND BUG (tk-fc7h58): the fail safe read "never orphan on an EMPTY map",
# but it was prose with no predicate and no variable, so the witness applied it
# by judgment — and applied it to a POPULATED map in which some owners resolved
# absent. Two escalations in five days under witness-empty-liveness-map, each
# skipping orphan recovery and spending a converse sitting, both reporting the
# map as non-empty in their own text (16 and 22 sessions).
#
# The premise can never clear on its own. Closed sessions are excluded from
# `gc session list` by design on every path, so a bead naming a session that has
# since closed ALWAYS resolves absent. Reading that as drift suppresses orphan
# recovery permanently rather than for one cycle.
#
# THE FIX: the liveness-map-guard block computes MAP_COUNT and MAP_TRIP once per
# cycle, before the first bead is read. No bead is in scope where the decision is
# made, so an individual absent owner cannot reach it. These cases execute the
# real block over a stub `gc`.
GUARD="$(awk '
  /# >>> liveness-map-guard/ {f=1; next}
  /# <<< liveness-map-guard/ {f=0}
  f' "$TOML")"

[ -n "$GUARD" ] \
  && ok "guard extracted between liveness-map-guard markers" \
  || bad "guard extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$GUARD" > "$TMP/guard.sh"
bash -n "$TMP/guard.sh" \
  && ok "extracted guard is syntactically valid bash" \
  || bad "extracted guard failed bash -n"

# A `gc` that serves canned answers and REFUSES anything the guard is not
# supposed to call. Both real sources write clean JSON to stdout and their
# banner to stderr, which is what the guard's 2>/dev/null relies on.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GCSTUB'
#!/usr/bin/env bash
set -u
echo "gc: banner on stderr, as the real command does" >&2
case "${1:-} ${2:-}" in
  "session list")
    if [ -n "${STUB_SESSIONS_RC:-}" ]; then exit "$STUB_SESSIONS_RC"; fi
    cat "$STUB_SESSIONS_FILE" ;;
  "bd list")
    if [ -n "${STUB_BEADS_RC:-}" ]; then exit "$STUB_BEADS_RC"; fi
    cat "$STUB_BEADS_FILE" ;;
  *)
    echo "gc stub: unmodelled call: $*" >&2; exit 64 ;;
esac
GCSTUB
chmod +x "$TMP/bin/gc"
export STUB_SESSIONS_FILE="$TMP/sessions.json" STUB_BEADS_FILE="$TMP/session-beads.json"
export STUB_SESSIONS_RC="" STUB_BEADS_RC=""

# guard <sessions-stdout> <session-beads-stdout> -> "MAP_COUNT|MAP_TRIP"
# Optional 3rd/4th args are exit codes for the two sources.
guard() {
  printf '%s' "$1" > "$STUB_SESSIONS_FILE"
  printf '%s' "$2" > "$STUB_BEADS_FILE"
  STUB_SESSIONS_RC="${3:-}" STUB_BEADS_RC="${4:-}" \
  PATH="$TMP/bin:$PATH" bash -c '
    set -uo pipefail
    source "$0"
    printf "%s|%s" "$MAP_COUNT" "$MAP_TRIP"
  ' "$TMP/guard.sh" 2>/dev/null
}
# guard_map <sessions-stdout> <session-beads-stdout> -> the built LIVENESS_MAP.
guard_map() {
  printf '%s' "$1" > "$STUB_SESSIONS_FILE"
  printf '%s' "$2" > "$STUB_BEADS_FILE"
  STUB_SESSIONS_RC="" STUB_BEADS_RC="" \
  PATH="$TMP/bin:$PATH" bash -c '
    set -uo pipefail
    source "$0"
    printf "%s" "$LIVENESS_MAP"
  ' "$TMP/guard.sh" 2>/dev/null
}

# The live steady state: sessions exist, the session-bead source is empty
# because gc bd list drops issue_type=session outright.
SESSIONS_LIVE='{"ok":true,"sessions":[
  {"id":"lx-3rk8v","name":"gc-toolkit--gc-toolkit__polecat-1-pool","state":"active"},
  {"id":"lx-fjnq1","alias":"gc-toolkit/gc-toolkit.furiosa","state":"active"}]}'
NO_BEADS='[]'

# (W) THE REGRESSION. The exact shape both escalations fired on: a populated
#     map that omits the sessions the stalled beads name. Orphan recovery must
#     proceed. A trip here is the bug returning.
eq "$(guard "$SESSIONS_LIVE" "$NO_BEADS")" "4|" \
   "(W) populated map, owners it does not name -> no trip, recovery proceeds"
# (W) The two halves must agree: the same map that does not trip still resolves
#     the missing owner to 'absent', which is the orphan signal, not drift.
eq "$(state "$(guard_map "$SESSIONS_LIVE" "$NO_BEADS")" "lx-41aa7")" "absent" \
   "(W) an owner absent from a non-tripping map still classifies as orphaned"
# (W) And a named owner in that same map is still live — the map is usable, so
#     both answers come from it rather than from a blanket skip.
eq "$(state "$(guard_map "$SESSIONS_LIVE" "$NO_BEADS")" "gc-toolkit.furiosa")" "active" \
   "(W) a named owner in the same map resolves live"

# (X) The condition the fail safe is actually for: no keys at all.
eq "$(guard '{"ok":true,"sessions":[]}' "$NO_BEADS")" "0|liveness map empty" \
   "(X) genuinely empty map -> trip"

# (Y) Unreadable source A, three ways. A read that failed is not a city with no
#     sessions, and each must trip rather than orphan everything.
eq "$(guard '' "$NO_BEADS" 1)" "0|session list unreadable" \
   "(Y) session list exits non-zero -> trip"
eq "$(guard 'not json at all' "$NO_BEADS")" "0|session list unreadable" \
   "(Y) session list emits garbage -> trip"
eq "$(guard '{"ok":true}' "$NO_BEADS")" "0|session list unreadable" \
   "(Y) session list without a .sessions array (schema drift) -> trip"
eq "$(guard '[]' "$NO_BEADS")" "0|session list unreadable" \
   "(Y) session list returning an array instead of an object -> trip"

# (Z) Source B is never required. Its emptiness is the healthy answer, and its
#     failure must not decide a cycle that source A can answer.
eq "$(guard "$SESSIONS_LIVE" 'garbage')" "4|" \
   "(Z) unreadable session beads with a good session list -> no trip"
eq "$(guard "$SESSIONS_LIVE" '' "" 1)" "4|" \
   "(Z) session-bead read exits non-zero with a good session list -> no trip"
# (Z) But B cannot rescue a genuinely empty cycle either.
eq "$(guard '{"ok":true,"sessions":[]}' 'garbage')" "0|liveness map empty" \
   "(Z) empty session list plus unreadable beads -> still trips as empty"

# (Y) The builder dying behind a source that read fine. Normalizing the inputs
#     makes this rare, so it is injected rather than waited for: a jq that
#     answers the shape probes and fails the build. Without the non-numeric
#     arm MAP_TRIP stays empty here and the fail safe is skipped on a map that
#     does not exist — the fail-OPEN direction, the one that false-orphans.
mkdir -p "$TMP/badjq"
cat > "$TMP/badjq/jq" <<'JQSHIM'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "-n" ]; then exit 1; fi
done
exec "$REAL_JQ" "$@"
JQSHIM
chmod +x "$TMP/badjq/jq"
REAL_JQ="$(command -v jq)"
printf '%s' "$SESSIONS_LIVE" > "$STUB_SESSIONS_FILE"
printf '%s' "$NO_BEADS" > "$STUB_BEADS_FILE"
eq "$(REAL_JQ="$REAL_JQ" STUB_SESSIONS_RC="" STUB_BEADS_RC="" \
      PATH="$TMP/badjq:$TMP/bin:$PATH" bash -c '
        set -uo pipefail
        source "$0"
        printf "%s|%s" "$MAP_COUNT" "$MAP_TRIP"
      ' "$TMP/guard.sh" 2>/dev/null)" "|liveness map unreadable" \
   "(Y) map builder fails behind a readable source -> trip, never fall through"

# (AA) Both sources contribute keys; on a collision the session list wins,
#      because it is the source whose state field is authoritative.
eq "$(guard_map '{"ok":true,"sessions":[{"id":"x","state":"closed"}]}' \
                '[{"id":"x","status":"active"},{"id":"y","status":"active"}]' \
     | jq -r '.x + "," + .y')" "closed,active" \
   "(AA) session-list state wins the collision; bead-only keys survive"

# (AB) The structural guarantee, and the only one that keeps the bug from
#      coming back through prose: the decision is computed where no bead
#      exists. If the block ever reads per-bead state, an individual absent
#      owner can reach the fail safe again.
for v in OWNER STATE '$bead' '.owner'; do
  grep -qF -- "$v" "$TMP/guard.sh" \
    && bad "(AB) guard references per-bead state '$v' — the fail safe must not see a bead" \
    || ok "(AB) guard does not reference per-bead state '$v'"
done
# (AB) And it must run BEFORE the per-bead lookup, not beside it.
GUARD_LINE=$(grep -n '# >>> liveness-map-guard' "$TOML" | cut -d: -f1)
LOOKUP_LINE=$(grep -n '# >>> liveness-lookup' "$TOML" | cut -d: -f1)
[ "$GUARD_LINE" -lt "$LOOKUP_LINE" ] \
  && ok "(AB) the map guard is specified before the per-bead lookup" \
  || bad "(AB) the map guard must precede the per-bead lookup"

# (AC) The prose must hand the decision to the variable and must say, in the
#      formula itself, that an absent owner on a populated map is not drift.
#      The judgment call is what misfired; naming the predicate removes it.
grep -qF 'MAP_TRIP` is the entire test' "$TOML" \
  && ok "(AC) fail-safe prose binds the decision to MAP_TRIP" \
  || bad "(AC) fail-safe prose must bind the decision to MAP_TRIP"
grep -qF 'resolves `absent` against a POPULATED map is never grounds' "$TOML" \
  && ok "(AC) prose rules out an absent owner as fail-safe grounds" \
  || bad "(AC) prose must rule out an absent owner as fail-safe grounds"
grep -qF 'never returns a row' "$TOML" \
  && ok "(AC) prose records that closed sessions are excluded by design" \
  || bad "(AC) prose must record that closed sessions are excluded by design"

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
