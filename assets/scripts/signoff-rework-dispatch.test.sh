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
# was slung / linked / woken / escalated, and prove the sling fires independently
# of the best-effort parent-child edge.
#
# Three knobs model the ways a dispatch fails to produce runnable demand:
#   FAKE_SLING_RC   — the sling exits non-zero (the failure a bare `|| true`
#                     swallowed outright).
#   FAKE_SLING_ROOT — the workflow root id the real `gc sling --json` reports;
#                     unset means a gc that names none, where the exit status is
#                     the only evidence available.
#   FAKE_ROOT_ROUTE — what that root's `gc.routed_to` READS BACK as. Empty is the
#                     failure an exit status cannot see: the sling reported
#                     success and the root carries no route, so it is offered to
#                     nobody and the child is as stranded as if nothing ran.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1" in
  sling)
    shift; printf '%s\n' "$*" >> "$FAKE_SLINGS"
    [ -n "${FAKE_SLING_ROOT:-}" ] \
      && printf '{"schema_version":"1","success":true,"workflow_id":"%s"}\n' "$FAKE_SLING_ROOT"
    exit "${FAKE_SLING_RC:-0}" ;;
  session) [ "${2:-}" = "wake" ] && printf '%s\n' "${3:-}" >> "$FAKE_WAKES" ;;
  mail)    shift; printf '%s\n' "$*" >> "$FAKE_MAIL" ;;
  bd)
    case "${2:-}" in
      dep)    shift 2; printf '%s\n' "$*" >> "$FAKE_DEPS" ;;
      update) shift 2; printf '%s\n' "$*" >> "$FAKE_UPDATES" ;;
      show)   printf '[{"id":"%s","metadata":{"gc.routed_to":"%s"}}]\n' \
                "${3:-}" "${FAKE_ROOT_ROUTE:-}" ;;
    esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_SLINGS="$TMP/slings" FAKE_WAKES="$TMP/wakes" \
       FAKE_DEPS="$TMP/deps" FAKE_UPDATES="$TMP/updates" FAKE_MAIL="$TMP/mail"

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
  : > "$FAKE_MAIL"
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

eq "$(wc -c < "$FAKE_MAIL" | tr -d ' ')" "0" "anchored: a dispatch that took does not escalate"

# --- verified dispatch: the sling NAMES the root it minted -------------------
# The stronger evidence, available whenever gc reports a workflow id: the demand
# is real only if that parentless root reads back carrying the pool route, which
# is what the offer predicate matches on.
export FAKE_SLING_ROOT="wf-1" FAKE_ROOT_ROUTE="rig/rig.polecat"
run_dispatch fix-3 tk-anchor rig/rig.polecat
grep -qx 'rig/rig.polecat' "$FAKE_WAKES" \
  && ok "verified: root reads back routed to the pool -> armed, pool woken" \
  || bad "verified: a root routed to the pool must count as dispatched (wakes: $(cat "$FAKE_WAKES"))"
eq "$(wc -c < "$FAKE_MAIL" | tr -d ' ')" "0" "verified: a verified dispatch does not escalate"
unset FAKE_SLING_ROOT FAKE_ROOT_ROUTE

# --- sling FAILS: the swallowed `|| true` case (tk-c9rh7 finding 2) ----------
# The child is filed and linked under the still-blocked anchor, so it is offered
# to nobody; the review closes moments later. Without an escalation that is a
# silent terminal hold — the exact deadlock the sling exists to prevent, reached
# one step further along.
export FAKE_SLING_RC=1
run_dispatch fix-4 tk-anchor rig/rig.polecat
eq "$(wc -c < "$FAKE_WAKES" | tr -d ' ')" "0" "sling failed -> pool NOT woken (nothing is ready to claim)"
grep -q 'ESCALATION' "$FAKE_MAIL" \
  && ok "sling failed -> mayor escalated" \
  || bad "sling failed -> a failed dispatch must not close silently (mail: $(cat "$FAKE_MAIL"))"
grep -q '^tk-anchor .*gc.routed_to=human' "$FAKE_UPDATES" \
  && ok "sling failed -> anchor routed to human" \
  || bad "sling failed -> anchor must be routed to human (got: $(cat "$FAKE_UPDATES"))"
grep -q '^fix-4 .*NOT dispatched' "$FAKE_UPDATES" \
  && ok "sling failed -> child marked with why it is sitting still + the repair" \
  || bad "sling failed -> child must carry its own undispatched marker (got: $(cat "$FAKE_UPDATES"))"
grep -q 'gc sling rig/rig.polecat fix-4' "$FAKE_MAIL" \
  && ok "sling failed -> escalation names the one-command repair" \
  || bad "sling failed -> escalation must name the repair command (mail: $(cat "$FAKE_MAIL"))"
unset FAKE_SLING_RC

# --- sling reports SUCCESS but the root is UNROUTED --------------------------
# The failure an exit status cannot see: rc=0, a root exists, and it carries no
# route — so no pool is ever offered it. Only the read-back catches this, which is
# why the verification is not `|| true` on the exit code.
export FAKE_SLING_ROOT="wf-2" FAKE_ROOT_ROUTE=""
run_dispatch fix-5 tk-anchor rig/rig.polecat
grep -q 'fix-5' "$FAKE_SLINGS" \
  && ok "unrouted root: the sling DID run (the read-back, not the exit code, catches it)" \
  || bad "unrouted root: expected a sling attempt (got: $(cat "$FAKE_SLINGS"))"
eq "$(wc -c < "$FAKE_WAKES" | tr -d ' ')" "0" "unrouted root -> pool NOT woken"
grep -q 'ESCALATION' "$FAKE_MAIL" \
  && ok "unrouted root -> mayor escalated (rc=0 is not proof of demand)" \
  || bad "unrouted root -> must escalate; an unrouted root is offered to nobody"
unset FAKE_SLING_ROOT FAKE_ROOT_ROUTE

# --- unlinked child whose sling fails ----------------------------------------
# No anchor resolved, so there is nothing to route to a human — the escalation
# must still fire, or an anchorless undispatched child is invisible everywhere.
export FAKE_SLING_RC=1
run_dispatch fix-6 '' rig/rig.polecat
grep -q 'ESCALATION' "$FAKE_MAIL" \
  && ok "unlinked + sling failed -> still escalated" \
  || bad "unlinked + sling failed -> must still escalate (mail: $(cat "$FAKE_MAIL"))"
grep -q 'gc.routed_to=human' "$FAKE_UPDATES" \
  && bad "unlinked + sling failed -> no anchor exists to route to human (got: $(cat "$FAKE_UPDATES"))" \
  || ok "unlinked + sling failed -> no anchor write attempted"
unset FAKE_SLING_RC

# --- no-child case: cap arm / signoff pass filed nothing ---------------------
# When the cap arm escalates instead of filing, FIX_BEAD is empty. Slinging then
# would spawn the very session the cap exists to prevent, so nothing must fire.
run_dispatch '' tk-anchor rig/rig.polecat
eq "$(wc -c < "$FAKE_SLINGS" | tr -d ' ')" "0" "no child -> nothing slung (cap arm must not spawn)"
eq "$(wc -c < "$FAKE_WAKES"  | tr -d ' ')" "0" "no child -> pool not woken"
eq "$(wc -c < "$FAKE_MAIL"   | tr -d ' ')" "0" "no child -> nothing escalated (the cap already did)"

echo "--- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
