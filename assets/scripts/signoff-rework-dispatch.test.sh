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
#
# Two more model the way the WORK ORDER fails, which is the other half of the
# same fail-open (review tk-d97n8). The template body runs without errexit, so
# the `gc bd update` that stamps the child is best-effort: it can fail or drop
# fields and execution walks straight on into the dispatch.
#   FAKE_CHILD_META       — the metadata object the child READS BACK as. Anything
#                           short of the full work order must leave the child
#                           inert: a slung child with no branch/target reads like
#                           ordinary new work and the polecat branches fresh and
#                           (post-open) opens a SECOND PR.
#   FAKE_CHILD_UNREADABLE — `gc bd show` returns nothing at all for the child.
#                           The empty string a failed read produces must not pass
#                           for the empty string a clean check produces — which is
#                           what the jq "ok" sentinel is for.
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
      show)
        # Two different reads land here — the CHILD's work order (before the
        # sling) and the sling ROOT's route (after it). Serve each its own row,
        # keyed on the id, so a case can corrupt one without touching the other.
        if [ -n "${FAKE_SLING_ROOT:-}" ] && [ "${3:-}" = "$FAKE_SLING_ROOT" ]; then
          printf '[{"id":"%s","metadata":{"gc.routed_to":"%s"}}]\n' \
            "${3:-}" "${FAKE_ROOT_ROUTE:-}"
        elif [ -z "${FAKE_CHILD_UNREADABLE:-}" ]; then
          printf '[{"id":"%s","metadata":%s}]\n' "${3:-}" "${FAKE_CHILD_META:-null}"
        fi ;;
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

# The work-order read-back must PRECEDE the sling — verifying a stamp after
# arming the child is not a gate, it is a log line.
read_ln=$(grep -m1 -n 'FIX_MISSING=' "$TMP/dispatch.sh" || true); read_ln=${read_ln%%:*}
{ [ -n "$read_ln" ] && [ -n "$sling_ln" ] && [ "$sling_ln" -gt "$read_ln" ]; } \
  && ok "work-order read-back precedes the sling (read@$read_ln, sling@$sling_ln)" \
  || bad "the child's work order must be read back BEFORE it is slung (read@${read_ln:-none}, sling@${sling_ln:-none})"

# The work order a complete pre-open stamp leaves on the child, and the FIX_*
# values the arm above WROTE it from. The read-back compares the two, so these
# must agree for the default (happy-path) cases.
CHILD_PRE_OPEN='{"branch":"polecat/tk-work","target":"main","source_review_bead":"tk-review","merge_strategy":"mr","rejection_reason":"pre-open signoff requested changes on branch polecat/tk-work","gc.routed_to":"rig/rig.polecat"}'

# run_dispatch <FIX_BEAD> <ANCHOR> <FIX_POOL>
# The snippet's tail is `[ -n "$FIX_BEAD" ] && { ... }` guard-idiom, which is NOT
# meant to run under `set -e` (a false guard is a legitimate no-op that returns 1,
# exactly the cap-arm/no-child case). Run it the way the template body runs — with
# -u and pipefail for real-bug safety but without -e — and swallow the guard's
# trailing non-zero so this (set -e) harness does not abort on it.
#
# FIX_*/FAKE_CHILD_META default to a complete PRE-OPEN work order; a case that
# wants the post-open shape or a dropped write exports its own before calling.
run_dispatch() {
  : > "$FAKE_SLINGS"; : > "$FAKE_WAKES"; : > "$FAKE_DEPS"; : > "$FAKE_UPDATES"
  : > "$FAKE_MAIL"
  FIX_BEAD="$1" ANCHOR="$2" FIX_POOL="$3" CHECK_NAME="codex" \
  FIX_BRANCH="${FIX_BRANCH:-polecat/tk-work}" FIX_TARGET="${FIX_TARGET:-main}" \
  FIX_PR_URL="${FIX_PR_URL:-}" FIX_PR_NUM="${FIX_PR_NUM:-}" \
  FAKE_CHILD_META="${FAKE_CHILD_META:-$CHILD_PRE_OPEN}" \
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

# --- work order DROPPED: the child was filed but never stamped ---------------
# The other half of the same fail-open (review tk-d97n8). The template body runs
# without errexit, so the `gc bd update` that writes the work order is
# best-effort — a failed one leaves the child carrying nothing and execution
# walks straight into the dispatch. Slinging THEN is the damaging outcome, not
# the safe one: mol-polecat-work over a bead with no branch/target reads like
# ordinary new work, so the polecat branches fresh from main and re-implements
# instead of resuming the branch under review. Inert-and-escalated is bounded;
# runnable-and-malformed force-pushes somewhere else.
export FAKE_CHILD_META='{}'
run_dispatch fix-7 tk-anchor rig/rig.polecat
eq "$(wc -c < "$FAKE_SLINGS" | tr -d ' ')" "0" "dropped work order -> NOT slung (a malformed work order must not become runnable demand)"
eq "$(wc -c < "$FAKE_WAKES"  | tr -d ' ')" "0" "dropped work order -> pool not woken"
grep -q 'fix-7' "$FAKE_DEPS" \
  && ok "dropped work order -> child still linked under the anchor (visibility survives)" \
  || bad "dropped work order -> the parent-child edge is independent of the stamp (got: $(cat "$FAKE_DEPS"))"
grep -q '^tk-anchor .*check.codex' "$FAKE_UPDATES" \
  && ok "dropped work order -> anchor gate marker still cleared (the head is unreviewed either way)" \
  || bad "dropped work order -> gate marker must still be cleared (got: $(cat "$FAKE_UPDATES"))"
grep -q 'ESCALATION' "$FAKE_MAIL" \
  && ok "dropped work order -> mayor escalated" \
  || bad "dropped work order -> an inert child must not close silently (mail: $(cat "$FAKE_MAIL"))"
grep -q '^fix-7 .*work order incomplete' "$FAKE_UPDATES" \
  && ok "dropped work order -> child marked with WHICH fields are missing" \
  || bad "dropped work order -> child must carry the incomplete-order reason (got: $(cat "$FAKE_UPDATES"))"
grep -q "gc bd show fix-7" "$FAKE_MAIL" \
  && ok "dropped work order -> escalation names the work-order inspection, not just the sling" \
  || bad "dropped work order -> repair must start at the stamp (mail: $(cat "$FAKE_MAIL"))"
grep -q '^tk-anchor .*gc.routed_to=human' "$FAKE_UPDATES" \
  && ok "dropped work order -> anchor routed to human" \
  || bad "dropped work order -> anchor must be routed to human (got: $(cat "$FAKE_UPDATES"))"
unset FAKE_CHILD_META

# --- work order PARTIAL: branch present, routing field dropped ---------------
# A single dropped `--set-metadata` is likelier than a wholesale failure, and it
# is invisible without a field-by-field read-back: the child looks plausible and
# is offered to nobody.
export FAKE_CHILD_META='{"branch":"polecat/tk-work","target":"main","source_review_bead":"tk-review","merge_strategy":"mr","rejection_reason":"x"}'
run_dispatch fix-8 tk-anchor rig/rig.polecat
eq "$(wc -c < "$FAKE_SLINGS" | tr -d ' ')" "0" "partial work order (no route) -> NOT slung"
grep -q '^fix-8 .*gc.routed_to' "$FAKE_UPDATES" \
  && ok "partial work order -> the missing field is named on the child" \
  || bad "partial work order -> must name the missing field (got: $(cat "$FAKE_UPDATES"))"
unset FAKE_CHILD_META

# --- the EXPECTATION itself is empty -----------------------------------------
# Post-open resolves branch/target/url from `gh pr view`. If those reads return
# nothing, the write stamps empty strings and a naive equality check compares ""
# to "" and passes — a work order verified to be blank. An empty expectation must
# count as missing, or the read-back certifies exactly the case it exists to stop.
export FIX_BRANCH="" FAKE_CHILD_META='{"branch":"","target":"main","source_review_bead":"tk-review","merge_strategy":"mr","rejection_reason":"x","gc.routed_to":"rig/rig.polecat"}'
run_dispatch fix-12 tk-anchor rig/rig.polecat
eq "$(wc -c < "$FAKE_SLINGS" | tr -d ' ')" "0" "empty expectation -> NOT slung ('' == '' must not pass for a stamped branch)"
grep -q '^fix-12 .*branch' "$FAKE_UPDATES" \
  && ok "empty expectation -> branch reported missing" \
  || bad "empty expectation -> must report branch missing (got: $(cat "$FAKE_UPDATES"))"
unset FIX_BRANCH FAKE_CHILD_META

# --- work order UNREADABLE: `gc bd show` returns nothing ----------------------
# The failure the "ok" sentinel exists for: a failed read yields the same empty
# string a clean check would, so without the sentinel an unreadable bead passes
# for a complete stamp.
export FAKE_CHILD_UNREADABLE=1
run_dispatch fix-9 tk-anchor rig/rig.polecat
eq "$(wc -c < "$FAKE_SLINGS" | tr -d ' ')" "0" "unreadable child -> NOT slung (empty output is not a passing check)"
grep -q '^fix-9 .*unreadable' "$FAKE_UPDATES" \
  && ok "unreadable child -> marked unreadable rather than silently armed" \
  || bad "unreadable child -> must report unreadable (got: $(cat "$FAKE_UPDATES"))"
unset FAKE_CHILD_UNREADABLE

# --- POST-OPEN work order: the PR fields are what keep it on ONE PR ----------
# existing_pr/pr_url/pr_number are the difference between reworking PR#N and
# opening a second PR against the same branch. They are required only when the
# arm that filed the child was the post-open one (FIX_PR_NUM non-empty), so the
# pre-open cases above must not be held to them.
export FIX_PR_URL="https://github.com/o/r/pull/7" FIX_PR_NUM="7"
export FAKE_CHILD_META='{"branch":"pr-head","target":"main","source_review_bead":"tk-review","merge_strategy":"mr","rejection_reason":"x","existing_pr":"https://github.com/o/r/pull/7","pr_url":"https://github.com/o/r/pull/7","pr_number":"7","gc.routed_to":"rig/rig.polecat"}'
export FIX_BRANCH="pr-head"
run_dispatch fix-10 tk-anchor rig/rig.polecat
grep -q 'fix-10' "$FAKE_SLINGS" \
  && ok "post-open: a complete PR work order IS slung" \
  || bad "post-open: a complete work order must dispatch (got: $(cat "$FAKE_SLINGS"))"
eq "$(wc -c < "$FAKE_MAIL" | tr -d ' ')" "0" "post-open: a complete PR work order does not escalate"

# Same child, PR fields dropped — the write that survived makes it look fine.
export FAKE_CHILD_META='{"branch":"pr-head","target":"main","source_review_bead":"tk-review","merge_strategy":"mr","rejection_reason":"x","gc.routed_to":"rig/rig.polecat"}'
run_dispatch fix-11 tk-anchor rig/rig.polecat
eq "$(wc -c < "$FAKE_SLINGS" | tr -d ' ')" "0" "post-open: dropped PR fields -> NOT slung (a slung child would open a SECOND PR)"
grep -q '^fix-11 .*pr_fields' "$FAKE_UPDATES" \
  && ok "post-open: dropped PR fields named on the child" \
  || bad "post-open: must name pr_fields as missing (got: $(cat "$FAKE_UPDATES"))"
grep -q 'ESCALATION' "$FAKE_MAIL" \
  && ok "post-open: dropped PR fields -> mayor escalated" \
  || bad "post-open: dropped PR fields must escalate (mail: $(cat "$FAKE_MAIL"))"
unset FAKE_CHILD_META FIX_PR_URL FIX_PR_NUM FIX_BRANCH

# --- no-child case: cap arm / signoff pass filed nothing ---------------------
# When the cap arm escalates instead of filing, FIX_BEAD is empty. Slinging then
# would spawn the very session the cap exists to prevent, so nothing must fire.
run_dispatch '' tk-anchor rig/rig.polecat
eq "$(wc -c < "$FAKE_SLINGS" | tr -d ' ')" "0" "no child -> nothing slung (cap arm must not spawn)"
eq "$(wc -c < "$FAKE_WAKES"  | tr -d ' ')" "0" "no child -> pool not woken"
eq "$(wc -c < "$FAKE_MAIL"   | tr -d ' ')" "0" "no child -> nothing escalated (the cap already did)"

echo "--- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
