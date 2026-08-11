#!/usr/bin/env bash
# Hermetic test for the signoff rework-DISPATCH tail (tk-7xvz5).
#
# A REQUEST_CHANGES verdict files a rework child and links it parent-child under
# the still-open anchor. That anchor is BLOCKED (on workflow-finalize) for the
# whole time it is in flight, and blocked status cascades down parent-child
# edges — so the child inherits is_blocked and drops out of `bd ready`. A bead
# that is not `bd ready` never drives poolDesired, so `gc.routed_to` alone never
# self-spawns a polecat on an idle pool, and the `gc session wake` below it is a
# no-op (the live instance su-iyng sat 18h until the mayor slung it by hand).
#
# The fix is to ALSO `gc sling` the child after the parent-child dep: sling mints
# a PARENTLESS mol-polecat-work root that carries the ready demand while the
# parent edge stays for visibility (the canonical dep-add-then-sling pattern in
# convoy-integration-branch.template.md).
#
# This test EXECUTES the real dispatch snippet extracted verbatim from the
# template (between the `signoff-rework-dispatch` markers) against a fake `gc`,
# so it cannot drift from the shipped instruction and a future edit cannot
# silently drop the sling again. No live city, Dolt, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TEMPLATE="$ROOT/template-fragments/polecat-non-impl-done.template.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: record the dispatch actions the snippet performs. ---------------
# Every write goes to a per-action sink so the assertions can prove WHICH bead
# was slung / linked / woken, and prove the sling fires independently of the
# best-effort parent-child edge.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1" in
  sling)   shift; printf '%s\n' "$*" >> "$FAKE_SLINGS" ;;
  session) [ "${2:-}" = "wake" ] && printf '%s\n' "${3:-}" >> "$FAKE_WAKES" ;;
  bd)
    case "${2:-}" in
      dep)    shift 2; printf '%s\n' "$*" >> "$FAKE_DEPS" ;;
      update) shift 2; printf '%s\n' "$*" >> "$FAKE_UPDATES" ;;
    esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_SLINGS="$TMP/slings" FAKE_WAKES="$TMP/wakes" \
       FAKE_DEPS="$TMP/deps" FAKE_UPDATES="$TMP/updates"

# --- extract the shipped snippet verbatim ------------------------------------
awk '/# >>> signoff-rework-dispatch/{f=1;next} /# <<< signoff-rework-dispatch/{f=0} f' \
  "$TEMPLATE" > "$TMP/dispatch.sh"
[ -s "$TMP/dispatch.sh" ] || { echo "FAIL - could not extract signoff-rework-dispatch snippet"; exit 1; }
grep -q 'gc sling' "$TMP/dispatch.sh" \
  && ok "snippet extracted from template and contains a gc sling" \
  || bad "extracted snippet does not sling the rework child — routing alone strands it (tk-7xvz5)"

# The sling MUST follow the parent-child dep (canonical dep-add-then-sling order:
# the sling mints the parentless root that carries the demand the edge suppresses).
# `grep -m1 -n` stops at the first match and needs no downstream `head`, so there
# is no pipe for the reader to SIGPIPE under `pipefail` (the check-pipefail-grep-q
# hazard). Strip the `N:` prefix with a builtin, no second process.
dep_ln=$(grep -m1 -n 'gc bd dep add' "$TMP/dispatch.sh" || true); dep_ln=${dep_ln%%:*}
sling_ln=$(grep -m1 -n 'gc sling' "$TMP/dispatch.sh" || true); sling_ln=${sling_ln%%:*}
{ [ -n "$dep_ln" ] && [ -n "$sling_ln" ] && [ "$sling_ln" -gt "$dep_ln" ]; } \
  && ok "sling follows the parent-child dep (dep@$dep_ln, sling@$sling_ln)" \
  || bad "sling must come after the parent-child dep (dep@${dep_ln:-none}, sling@${sling_ln:-none})"

# run_dispatch <FIX_BEAD> <ANCHOR> <FIX_POOL>
# The snippet's tail is `[ -n "$FIX_BEAD" ] && { ... }` guard-idiom, which is NOT
# meant to run under `set -e` (a false guard is a legitimate no-op that returns 1,
# exactly the cap-arm/no-child case). Run it the way the template body runs — with
# -u and pipefail for real-bug safety but without -e — and swallow the guard's
# trailing non-zero so this (set -e) harness does not abort on it.
run_dispatch() {
  : > "$FAKE_SLINGS"; : > "$FAKE_WAKES"; : > "$FAKE_DEPS"; : > "$FAKE_UPDATES"
  FIX_BEAD="$1" ANCHOR="$2" FIX_POOL="$3" CHECK_NAME="codex" \
    bash -c 'set -uo pipefail; source "$1"' _ "$TMP/dispatch.sh" || true
}

# --- anchored case: child filed WITH a resolved anchor -----------------------
# The common path. The child is linked parent-child under the anchor AND slung
# so the (otherwise cascade-blocked) child gets a ready workflow root.
run_dispatch fix-1 tk-anchor rig/rig.polecat
{ grep -q 'fix-1' "$FAKE_DEPS" && grep -q 'tk-anchor' "$FAKE_DEPS"; } \
  && ok "anchored: rework child linked parent-child under the anchor" \
  || bad "anchored: rework child not linked under the anchor (got: $(cat "$FAKE_DEPS"))"
{ grep -q 'fix-1' "$FAKE_SLINGS" && grep -q 'rig/rig.polecat' "$FAKE_SLINGS"; } \
  && ok "anchored: rework child SLUNG to the fix pool (parentless root -> ready demand)" \
  || bad "anchored: rework child must be slung, not just linked+woken (got: $(cat "$FAKE_SLINGS"))"
grep -qx 'rig/rig.polecat' "$FAKE_WAKES" \
  && ok "anchored: fix pool woken (latency nudge on top of the sling)" \
  || bad "anchored: fix pool not woken (got: $(cat "$FAKE_WAKES"))"

# --- unlinked case: child filed but NO anchor resolved -----------------------
# The anchor edge is best-effort — a filed child with no anchor must STILL be
# dispatched, or it is exactly as stranded as the bug. The sling is guarded on
# FIX_BEAD, not on the anchor, so it fires here too; the dep does not.
run_dispatch fix-2 '' rig/rig.polecat
grep -q 'fix-2' "$FAKE_SLINGS" \
  && ok "unlinked: rework child still slung when no anchor resolved" \
  || bad "unlinked: an anchorless rework child must still be slung (got: $(cat "$FAKE_SLINGS"))"
grep -q 'fix-2' "$FAKE_DEPS" \
  && bad "unlinked: no parent-child dep should be attempted without an anchor (got: $(cat "$FAKE_DEPS"))" \
  || ok "unlinked: no dep attempted without an anchor"

# --- no-child case: cap arm / signoff pass filed nothing ---------------------
# When the cap arm escalates instead of filing, FIX_BEAD is empty. Slinging then
# would spawn the very session the cap exists to prevent, so nothing must fire.
run_dispatch '' tk-anchor rig/rig.polecat
eq "$(wc -c < "$FAKE_SLINGS" | tr -d ' ')" "0" "no child -> nothing slung (cap arm must not spawn)"
eq "$(wc -c < "$FAKE_WAKES"  | tr -d ' ')" "0" "no child -> pool not woken"

echo "--- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
