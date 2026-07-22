#!/usr/bin/env bash
# Hermetic test for gc-helm takeaway --release molecule-step quiescing (tk-xypcy).
#
# THE BUG (recurring polecat burn): `gc-helm takeaway <anchor> "..." --release`
# parks a work bead — the ANCHOR of a mol-polecat-work molecule — by clearing
# the ANCHOR's own route. But the molecule's STEP beads keep their own pins
# (gc.routed_to, an assignee, gc.session_affinity=require). Those pins
# independently re-attract the pool / the assigned-work hand-back, so the pool
# re-spawns a polecat onto the already-parked husk, which re-derives "nothing to
# do" and drains — one burned session per scale_check tick.
#
# THE FIX: on --release, after parking the anchor, walk the anchor's molecule
# (reverse: live mol-polecat-work steps -> gc.root_bead_id -> root's
# gc.input_convoy_id -> convoy's single member) and clear the re-attracting pins
# on exactly the steps whose root resolves to THIS parked anchor.
#
# This test runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a
# stubbed `gc` on PATH — no live city, Dolt, network, or sessions. Covered:
#   (RELEASE)   the anchor still gets the full reopen/unassign/clear-route bundle
#   (AFFINE)    an assigned+affine+routed step -> routed_to + assignee +
#               session_affinity ALL cleared, in ONE update
#   (POOL)      an unassigned+routed step -> routed_to only (nothing else to clear)
#   (ATOMIC)    each quiesced step is written exactly once (no split-update race)
#   (FINAL)     the workflow-finalize step keeps its control-dispatcher route
#   (IDEM)      an already-quiet step is not re-updated
#   (SCOPE)     a DIFFERENT molecule (anchor != parked bead) is left untouched
#   (FAILCLOSE) a root whose anchor cannot be resolved is skipped, not quiesced
#   (FILTER)    a non-mol-polecat-work step under the same root is ignored
#   (NOCLOSE)   no step is closed and no step status is rewritten (the DANGER
#               clause), asserted both dynamically and as a static guard
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- Fixture ------------------------------------------------------------------
# The bead being parked: A-PARKED (anchor of the mol-polecat-work molecule whose
# root is root-PARKED, tracked by convoy convoy-PARKED).
#
# Steps (bd list --json shape). Under root-PARKED:
#   s-load   affine  : assignee + routed + session_affinity -> clear all three
#   s-impl   pool    : routed only (already unassigned)      -> clear routed only
#   s-final  finalize: control-dispatcher route              -> MUST stay routed
#   s-quiet  quiet   : no pins at all                         -> not re-updated
#   s-nonmol filter  : a non-mol-polecat-work step_ref        -> ignored entirely
# Under a DIFFERENT molecule (root-OTHER -> convoy-OTHER -> A-OTHER != parked):
#   s-other  scope   : affine+routed                          -> MUST stay untouched
# Under root-ORPHAN (no convoy -> anchor unresolvable):
#   s-orphan failsafe: affine+routed                          -> MUST stay untouched
cat > "$TMP/steps.json" <<'JSON'
[
  {"id":"s-load","assignee":"gc-toolkit__polecat-lx-dead","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-impl","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-final","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/core.control-dispatcher"}},
  {"id":"s-quiet","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.self-review","gc.root_bead_id":"root-PARKED"}},
  {"id":"s-nonmol","assignee":"someone","metadata":{"gc.step_ref":"mol-other-formula.step","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-other","assignee":"gc-toolkit__polecat-lx-live","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-OTHER","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-orphan","assignee":"gc-toolkit__polecat-lx-x","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-ORPHAN","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}}
]
JSON

# Roots: root_id|convoy_id   (root-ORPHAN deliberately absent -> no convoy)
cat > "$TMP/roots" <<'R'
root-PARKED|convoy-PARKED
root-OTHER|convoy-OTHER
R

# Convoys: convoy_id|anchor_id
cat > "$TMP/convoys" <<'C'
convoy-PARKED|A-PARKED
convoy-OTHER|A-OTHER
C

: > "$TMP/updates"     # one line per `gc bd update` invocation (the full argv)

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "rig list")
    # A single rig so enumerate_rigs never exit-3s. Path has no .beads dir, so
    # gc-helm resolves db="" and issues un-scoped bd calls (the mock ignores --db).
    jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd list")
    cat "$FAKE_STEPS_JSON" ;;
  "bd show")
    id="$3"
    convoy=$(awk -F'|' -v r="$id" '$1==r{print $2; exit}' "$FAKE_ROOTS")
    if [ -n "$convoy" ]; then jq -n --arg c "$convoy" '[{metadata:{"gc.input_convoy_id":$c}}]'
    else printf '[{"metadata":{}}]\n'; fi ;;
  "convoy status")
    anchor=$(awk -F'|' -v c="$3" '$1==c{print $2; exit}' "$FAKE_CONVOYS")
    if [ -n "$anchor" ]; then jq -n --arg a "$anchor" '{children:[{id:$a}]}'
    else printf '{"children":[]}\n'; fi ;;
  "bd update")
    printf '%s\n' "$*" >> "$FAKE_UPDATES" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_STEPS_JSON="$TMP/steps.json" FAKE_ROOTS="$TMP/roots" \
       FAKE_CONVOYS="$TMP/convoys" FAKE_UPDATES="$TMP/updates"
# Neutralize any inherited helm fixture hook so enumerate_rigs uses the stub.
unset GC_HELM_FIXTURE || true

# --- Run: park A-PARKED with --release. ---------------------------------------
OUT="$(sh "$SCRIPT" takeaway A-PARKED "parked" --by proactive --release 2>"$TMP/err" || true)"
ERR="$(cat "$TMP/err")"
UP="$TMP/updates"

# helpers: capture a bead's update line(s); empty string if none.
line_for() { grep -E "^bd update $1( |\$)" "$UP" || true; }

# (RELEASE) the parked anchor still gets the full reopen/unassign/clear-route bundle.
A="$(line_for A-PARKED)"
[ -n "$A" ] && ok "(RELEASE) anchor A-PARKED was updated" || bad "(RELEASE) anchor never updated"
printf '%s' "$A" | grep -q -- '--status=open' \
  && ok "(RELEASE) anchor reopened (--status=open)" || bad "(RELEASE) anchor --status=open (got: $A)"
printf '%s' "$A" | grep -q 'gc.proactive_reaction=1' \
  && ok "(RELEASE) anchor marks the proactive reaction" || bad "(RELEASE) anchor proactive_reaction"
printf '%s' "$A" | grep -q 'gc.routed_to=' \
  && ok "(RELEASE) anchor route cleared" || bad "(RELEASE) anchor route cleared"
printf '%s' "$A" | grep -q 'gc.takeaway_by=proactive' \
  && ok "(RELEASE) anchor takeaway headline stamped" || bad "(RELEASE) anchor takeaway stamped"

# (AFFINE) affine step -> routed_to + assignee + session_affinity, in ONE update.
eq "$(grep -c '^bd update s-load' "$UP" || true)" "1" \
  "(ATOMIC) s-load quiesced in exactly one update (no split-update race)"
SL="$(line_for s-load)"
if printf '%s' "$SL" | grep -q -- '--unset-metadata gc.routed_to' \
   && printf '%s' "$SL" | grep -q -- '--assignee' \
   && printf '%s' "$SL" | grep -q -- '--unset-metadata gc.session_affinity'; then
  ok "(AFFINE) affine step -> routed_to + assignee + session_affinity all cleared"
else
  bad "(AFFINE) affine step must clear all three pins (got: $SL)"
fi

# (POOL) unassigned+routed step -> routed_to only.
SI="$(line_for s-impl)"
printf '%s' "$SI" | grep -q -- '--unset-metadata gc.routed_to' \
  && ok "(POOL) unassigned+routed step -> routed_to cleared" || bad "(POOL) routed_to cleared (got: $SI)"
printf '%s' "$SI" | grep -q -- '--assignee' \
  && bad "(POOL) must not clear an assignee that was already empty" || ok "(POOL) no spurious assignee clear"
printf '%s' "$SI" | grep -q 'gc.session_affinity' \
  && bad "(POOL) must not clear a session_affinity that was absent" || ok "(POOL) no spurious affinity clear"

# (FINAL) workflow-finalize keeps its control-dispatcher route.
[ -z "$(line_for s-final)" ] \
  && ok "(FINAL) workflow-finalize step left untouched (keeps its escape route)" \
  || bad "(FINAL) must NOT de-route workflow-finalize"

# (IDEM) already-quiet step is not re-updated.
[ -z "$(line_for s-quiet)" ] \
  && ok "(IDEM) already-quiet step skipped" || bad "(IDEM) quiet step must not be updated"

# (FILTER) a non-mol-polecat-work step under the parked root is ignored.
[ -z "$(line_for s-nonmol)" ] \
  && ok "(FILTER) non-mol-polecat-work step ignored" || bad "(FILTER) non-mol-polecat-work step touched"

# (SCOPE) a different molecule (anchor != parked bead) is left untouched.
[ -z "$(line_for s-other)" ] \
  && ok "(SCOPE) molecule whose anchor != parked bead untouched" || bad "(SCOPE) wrong molecule quiesced"

# (FAILCLOSE) a root whose anchor cannot be resolved is skipped.
[ -z "$(line_for s-orphan)" ] \
  && ok "(FAILCLOSE) unresolved-anchor root skipped (fail closed)" || bad "(FAILCLOSE) unresolved anchor quiesced"

# (NOCLOSE dynamic) no STEP update ever closes a bead or rewrites its status.
STEP_UPDATES="$(grep -E '^bd update s-' "$UP" || true)"
if printf '%s' "$STEP_UPDATES" | grep -qE -- '--status|--close|bd close'; then
  bad "(NOCLOSE) a step update rewrote status or closed a bead (DANGER clause)"
else
  ok "(NOCLOSE) no step status rewrite / close (DANGER clause honored)"
fi

# (REPORT) the run announces the steps it quiesced.
printf '%s' "$OUT" | grep -q 'quiesced husk step s-load' \
  && ok "(REPORT) run reports the affine step it quiesced" || bad "(REPORT) run reports s-load (out: $OUT)"

# (STATIC NOCLOSE) the quiesce block itself contains no close/status-write cmd.
# The ONLY legitimate `--status` in the block is the `bd list` read filter
# (--status=open,in_progress selects which beads to consider); exclude that line
# so a genuine status-WRITE or `bd close` regression still trips the guard.
BLOCK="$(awk '/# >>> quiesce-release-molecule-steps/{f=1;next} /# <<< quiesce-release-molecule-steps/{f=0} f' "$SCRIPT")"
[ -n "$BLOCK" ] && ok "(MARKERS) quiesce block extracted between markers" || bad "(MARKERS) block extraction EMPTY — markers missing"
DANGER="$(printf '%s\n' "$BLOCK" | grep -v 'bd list --status' | grep -E 'bd close|--status|--close' || true)"
[ -z "$DANGER" ] \
  && ok "(NOCLOSE static) quiesce block writes no status and closes nothing (only the bd list read-filter uses --status)" \
  || bad "(NOCLOSE static) quiesce block contains a close/status-write: $DANGER"

# Surface any script stderr for debugging only (not an assertion).
if [ -n "$ERR" ]; then printf 'note: script stderr:\n%s\n' "$ERR" >&2; fi

echo ""
echo "gc-helm takeaway --release quiesce: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
