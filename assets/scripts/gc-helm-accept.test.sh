#!/usr/bin/env bash
# Hermetic test for the gc-helm `accept` verb (Accept/Discuss recommendation
# flow).
#
# WHAT accept DOES: accept a recommendation straight off the board — dispatch
# the subject's gc.recommended_formula AT the subject and dismiss its visit, in
# one procedural order with no sitting. It is the low-friction actuation of a
# ruling a human has made; Discuss (engage) stays the path for one they want to
# weigh instead.
#
# THE CONTRACT this pins:
#   - dispatch is `gc sling <subject> --on <formula> --var issue=<subject>`: the
#     subject is the routed anchor AND is passed as gc.var.issue so the worker
#     reads its card (a slung formula does not receive the description).
#   - SLING FIRST, dismiss only on success: a failed dispatch leaves the visit
#     for the operator to retry or Discuss, never a dismissed decision with
#     nothing running.
#   - a subject with NO gc.recommended_formula is discuss-only: accept refuses,
#     dispatching and dismissing nothing (the same key the board derives
#     Accept-ability from, so a refusal here is a row the board would not offer).
#   - a subject whose visit is already ENGAGED (in_progress, or open and bound to
#     a session or an assignee) — or that has no open visit at all — is refused,
#     dispatching and dismissing nothing: accept mirrors the board's un-engaged
#     predicate (unengagedVisit) and fails closed on a visit state it cannot read.
#   - a visit id resolves to its subject the way dismiss does.
#   - fail CLOSED on an unverifiable subject.
#
# It runs the REAL gc-helm.sh via `sh` (as shipped) with a stubbed `gc` on PATH
# — no live city, Dolt, network or sessions. Mutating calls (sling, close,
# update) are recorded to $FAKE_CALLS so "nothing dispatched" is asserted
# against actual argv, not exit status alone.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-accept-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- gc stub ------------------------------------------------------------------
# One rig (prefix tk). `bd show` answers per the requested id:
#   the SUBJECT id -> open, gc.recommended_formula = $FAKE_FORMULA (empty =>
#     discuss-only), no gc.superseded_by (so the resolver passes it through);
#     $FAKE_SUBJECT_MODE=missing makes it the {"error":…} not-found object.
#   the VISIT id   -> a task_kind=visit bead tracking the subject, with its
#     gc.outcome and gc.outcome_reason read back from the state $FAKE_OUTCOME_DIR
#     holds. dismiss stamps both on the visit and reads both back before the
#     irreversible close, so the stub models that write-then-read rather than
#     faking a fixed outcome; an unstamped visit reads empty, as the store answers
#     before dismiss runs.
# `bd list` (the accept guard's live-visit read AND dismiss's visit lookup)
# yields one visit on the subject when $FAKE_VISIT is set, with status
# $FAKE_VISIT_STATUS (default open), assignee $FAKE_VISIT_ASSIGNEE and
# gc.session_name $FAKE_VISIT_SESSION — the fields the un-engaged predicate
# reads; $FAKE_LIST_MODE=notarray/fail drives the fail-closed path. sling and
# close are recorded; update is recorded AND persists gc.outcome/gc.outcome_reason
# to $FAKE_OUTCOME_DIR; sling's exit is $FAKE_SLING_RC.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
sub="${1:-}"; verb="${2:-}"
case "$sub" in
  rig)
    jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  sling)
    printf '%s\n' "$*" >> "$FAKE_CALLS"
    exit "${FAKE_SLING_RC:-0}" ;;
  bd)
    case "$verb" in
      show)
        id="$3"
        case "$id" in
          "${FAKE_VISIT_ID:-__novisit__}")
            # gc.outcome / gc.outcome_reason read back from the state the `update`
            # arm persisted, so dismiss's read-back sees exactly what it stamped;
            # an unstamped visit reads empty, the way the store answers before
            # dismiss runs.
            oc="$(cat "${FAKE_OUTCOME_DIR:-/dev/null}/$id" 2>/dev/null || true)"
            or="$(cat "${FAKE_OUTCOME_DIR:-/dev/null}/$id.reason" 2>/dev/null || true)"
            if [ -n "${FAKE_VISIT_EDGE:-}" ]; then
              # The su-ab9je shape: the continuation_group stamp landed EMPTY and
              # only the tracks edge names the subject, rendered in the bd show
              # dep shape {dependency_type, id}.
              jq -n --arg i "$id" --arg s "$FAKE_SUBJECT_ID" --arg oc "$oc" --arg or "$or" \
                '[{id:$i, status:"open", title:"visit on the subject",
                   metadata:{task_kind:"visit","gc.continuation_group":"","gc.outcome":$oc,"gc.outcome_reason":$or},
                   dependencies:[{id:$s, dependency_type:"tracks"}]}]'
            else
              jq -n --arg i "$id" --arg s "$FAKE_SUBJECT_ID" --arg oc "$oc" --arg or "$or" \
                '[{id:$i, status:"open", title:"visit on the subject",
                   metadata:{task_kind:"visit","gc.continuation_group":$s,"gc.outcome":$oc,"gc.outcome_reason":$or}}]'
            fi ;;
          "${FAKE_SUBJECT_ID:-__nosubj__}")
            case "${FAKE_SUBJECT_MODE:-found}" in
              missing) printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1 ;;
              *)
                # The live recommendation is FAKE_FORMULA until an accept strip is
                # logged for this subject (reco_stripped), then it reads absent —
                # the store behaviour accept's mark-dispatched read-back relies on.
                # The dispatched marker is FAKE_DISPATCHED (an already-actuated
                # subject a resume reads) or what a strip write recorded.
                _live="${FAKE_FORMULA:-}"; [ -e "${FAKE_OUTCOME_DIR:-/dev/null}/$id.reco_stripped" ] && _live=""
                _disp="$(cat "${FAKE_OUTCOME_DIR:-/dev/null}/$id.reco_dispatched" 2>/dev/null || printf '%s' "${FAKE_DISPATCHED:-}")"
                jq -n --arg i "$id" --arg f "$_live" --arg d "$_disp" \
                   '[{id:$i, status:"open", title:"the subject",
                      metadata:( (if $f=="" then {} else {"gc.recommended_formula":$f} end)
                                 + (if $d=="" then {} else {"gc.recommended_formula_dispatched":$d} end) )}]' ;;
            esac ;;
          *) printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1 ;;
        esac ;;
      list)
        case "${FAKE_LIST_MODE:-ok}" in
          notarray) printf '{"not":"an array"}\n'; exit 0 ;;
          fail)     exit 1 ;;
        esac
        if [ -n "${FAKE_VISIT:-}" ]; then
          jq -n --arg v "$FAKE_VISIT_ID" --arg s "$FAKE_SUBJECT_ID" \
                --arg st "${FAKE_VISIT_STATUS:-open}" \
                --arg as "${FAKE_VISIT_ASSIGNEE:-}" \
                --arg se "${FAKE_VISIT_SESSION:-}" \
            '[{id:$v, status:$st, assignee:$as,
               metadata:{task_kind:"visit","gc.continuation_group":$s,"gc.session_name":$se}}]'
        else printf '[]\n'; fi ;;
      close)  printf '%s\n' "$*" >> "$FAKE_CALLS" ;;
      update)
        printf '%s\n' "$*" >> "$FAKE_CALLS"
        # Persist the dismiss stamps so `bd show` reads them back: gc.outcome to
        # $FAKE_OUTCOME_DIR/<id>, gc.outcome_reason to <id>.reason, keyed by the
        # bead id ($3). dismiss reads both back before the irreversible close, so
        # the stub models the write instead of faking a fixed outcome. accept's
        # mark-dispatched write is modelled the same way: reco_dispatched records
        # gc.recommended_formula_dispatched, and an --unset of gc.recommended_formula
        # records reco_stripped so the read-back sees the key gone — unless
        # FAKE_STRIP_FAILS models a silent drop the read-back must catch.
        _prev=""
        for a in "$@"; do
          case "$a" in
            gc.outcome=*)        [ -n "${FAKE_OUTCOME_DIR:-}" ] && printf '%s' "${a#gc.outcome=}" > "$FAKE_OUTCOME_DIR/$3" ;;
            gc.outcome_reason=*) [ -n "${FAKE_OUTCOME_DIR:-}" ] && printf '%s' "${a#gc.outcome_reason=}" > "$FAKE_OUTCOME_DIR/$3.reason" ;;
            gc.recommended_formula_dispatched=*) [ -n "${FAKE_OUTCOME_DIR:-}" ] && printf '%s' "${a#gc.recommended_formula_dispatched=}" > "$FAKE_OUTCOME_DIR/$3.reco_dispatched" ;;
            gc.recommended_formula) [ "$_prev" = "--unset-metadata" ] && [ -z "${FAKE_STRIP_FAILS:-}" ] && [ -n "${FAKE_OUTCOME_DIR:-}" ] && : > "$FAKE_OUTCOME_DIR/$3.reco_stripped" ;;
          esac
          _prev="$a"
        done ;;
    esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# pr-visit-comment.sh stub. dismiss updates the subject's PR reminder after it
# closes a visit; point that tool at a recording no-op so the close path stays
# hermetic (no gh, no network), the way gc-helm.test.sh and gc-helm-engage.test.sh do.
cat > "$TMP/bin/rec-pvc" <<'PVC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${REC_PVC_LOG:-/dev/null}"
exit 0
PVC
chmod +x "$TMP/bin/rec-pvc"

export PATH="$TMP/bin:$PATH"
export FAKE_CALLS="$TMP/calls"
# The visit's dismiss stamps land here and read back from here, so the stub
# models the store's write-then-read instead of faking a fixed outcome.
export FAKE_OUTCOME_DIR="$TMP/outcomes"; mkdir -p "$FAKE_OUTCOME_DIR"
export GC_VISIT_COMMENT_TOOL="$TMP/bin/rec-pvc" REC_PVC_LOG="$TMP/pvc.log"
# Hermetic: no inherited fixture hook, no ambient rig steering the resolver, and
# the cache stays out of the operator's real dir.
unset GC_HELM_FIXTURE GC_RIG || true
export TMPDIR="$TMP"

# run_accept <arg...> -> sets RC/OUT/ERR/CALLS from the per-case FAKE_* env.
run_accept() {
    : > "$FAKE_CALLS"
    rm -f "$FAKE_OUTCOME_DIR"/* 2>/dev/null || true
    set +e
    OUT="$(sh "$SCRIPT" accept "$@" 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"
    CALLS="$(cat "$FAKE_CALLS")"
}

SUBJ="tk-subj1"; VIS="tk-vis1"; FORMULA="mol-dispose-pr"

# --- (DISPATCH) the happy path, as a positive control FIRST -------------------
# A verb that refused everything would pass every fail-closed assertion below
# while dispatching nothing, so prove the dispatch lands before probing refusals.
export FAKE_SUBJECT_ID="$SUBJ" FAKE_VISIT_ID="$VIS" FAKE_FORMULA="$FORMULA" FAKE_VISIT=1 FAKE_SUBJECT_MODE=found FAKE_SLING_RC=0
run_accept "$SUBJ"
eq "$RC" "0" "(DISPATCH) accepting a recommendation exits 0"
grep -q "sling .*$SUBJ --on $FORMULA" <<< "$CALLS" \
  && ok "(DISPATCH) slings the recommended formula at the subject" || bad "(DISPATCH) sling --on formula (calls: $CALLS)"
grep -q 'sling .*--var issue='"$SUBJ" <<< "$CALLS" \
  && ok "(DISPATCH) passes the subject as gc.var.issue" || bad "(DISPATCH) --var issue=<subject> (calls: $CALLS)"
grep -q "bd close $VIS" <<< "$CALLS" \
  && ok "(DISPATCH) dismisses the visit after the dispatch lands" || bad "(DISPATCH) visit dismissed (calls: $CALLS)"
# Sling must precede the dismiss: the recording order is the execution order.
# One awk pass — no `grep | head`, whose SIGPIPE trips pipefail and aborts the run.
order_ok="$(awk -v v="$VIS" '/^sling /{s=NR} $0 ~ ("^bd close " v){c=NR} END{print (s>0 && c>0 && s<c) ? "yes" : "no"}' <<< "$CALLS")"
eq "$order_ok" "yes" "(DISPATCH) sling happens BEFORE the dismiss"

# --- (MARK) a landed Accept strips the live recommendation and records the dispatch
# So a later open visit on the subject cannot re-offer Accept for a formula that
# already ran (a second dispatch), and a re-run resumes rather than re-slinging.
run_accept "$SUBJ"
eq "$RC" "0" "(MARK) accepting exits 0"
grep -q "bd update $SUBJ .*--unset-metadata gc.recommended_formula" <<< "$CALLS" \
  && ok "(MARK) the live gc.recommended_formula is withdrawn on dispatch" || bad "(MARK) strip (calls: $CALLS)"
grep -q "bd update $SUBJ .*gc.recommended_formula_dispatched=$FORMULA" <<< "$CALLS" \
  && ok "(MARK) the dispatched formula is recorded" || bad "(MARK) dispatched marker (calls: $CALLS)"
# The withdrawal must land before the dismiss: a dismiss that closed the visit
# first would leave a window where the live key is still readable.
mark_ok="$(awk -v v="$VIS" '/^bd update .*--unset-metadata gc.recommended_formula/{m=NR} $0 ~ ("^bd close " v){c=NR} END{print (m>0 && c>0 && m<c) ? "yes":"no"}' <<< "$CALLS")"
eq "$mark_ok" "yes" "(MARK) the withdrawal lands before the dismiss"

# --- (RESUME) a subject already dispatched (marker set, live key gone) resumes ---
# The prior run slung and withdrew the recommendation but its dismiss did not
# finish. accept must NOT sling again — that is the double dispatch — and must
# finish the dismiss.
export FAKE_FORMULA="" FAKE_DISPATCHED="$FORMULA"
run_accept "$SUBJ"
eq "$RC" "0" "(RESUME) a dispatched-marked subject with an open visit exits 0"
grep -q '^sling ' <<< "$CALLS" \
  && bad "(RESUME) must NOT sling again — that is a second dispatch (calls: $CALLS)" \
  || ok "(RESUME) does not sling again"
grep -q "bd close $VIS" <<< "$CALLS" \
  && ok "(RESUME) finishes the dismiss" || bad "(RESUME) visit dismissed (calls: $CALLS)"
unset FAKE_DISPATCHED; export FAKE_FORMULA="$FORMULA"

# --- (STRIPFAIL) the withdrawal will not stick -> fail closed, dismiss nothing ---
# A live key that survives is Accept still live; refuse the dismiss so a later
# visit cannot dispatch the formula a second time.
export FAKE_STRIP_FAILS=1
run_accept "$SUBJ"
eq "$RC" "4" "(STRIPFAIL) a withdrawal that will not stick fails closed (exit 4)"
grep -q "bd close $VIS" <<< "$CALLS" \
  && bad "(STRIPFAIL) must NOT dismiss when the recommendation could not be withdrawn (calls: $CALLS)" \
  || ok "(STRIPFAIL) the visit is not dismissed"
grep -qi 'still reads live' <<< "$ERR" \
  && ok "(STRIPFAIL) names the key that would not withdraw" || bad "(STRIPFAIL) message (err: $ERR)"
unset FAKE_STRIP_FAILS

# --- (DISCUSSONLY) no gc.recommended_formula -> refuse, dispatch nothing -------
export FAKE_FORMULA=""
run_accept "$SUBJ"
eq "$RC" "2" "(DISCUSSONLY) a subject with no recommended formula is refused (exit 2)"
grep -qi 'discuss-only' <<< "$ERR" \
  && ok "(DISCUSSONLY) names it discuss-only and points at engage" || bad "(DISCUSSONLY) message (err: $ERR)"
[ -z "$CALLS" ] \
  && ok "(DISCUSSONLY) nothing slung and nothing dismissed" || bad "(DISCUSSONLY) must dispatch nothing (calls: $CALLS)"
export FAKE_FORMULA="$FORMULA"

# --- (VISITID) a visit id resolves to its subject, then dispatches -------------
run_accept "$VIS"
eq "$RC" "0" "(VISITID) accepting a visit id exits 0"
grep -q "sling .*$SUBJ --on $FORMULA" <<< "$CALLS" \
  && ok "(VISITID) slings the SUBJECT the visit tracks, not the visit" || bad "(VISITID) sling targets subject (calls: $CALLS)"
grep -q "bd close $VIS" <<< "$CALLS" \
  && ok "(VISITID) dismisses the visit" || bad "(VISITID) visit dismissed (calls: $CALLS)"

# --- (VISITEDGE) an empty continuation_group stamp resolves via the tracks edge -
# The su-ab9je shape (bd show dep {dependency_type, id}). The resolution must not
# read the bd list dep shape here, which would silently miss the subject.
export FAKE_VISIT_EDGE=1
run_accept "$VIS"
eq "$RC" "0" "(VISITEDGE) an edge-only visit id still resolves and dispatches"
grep -q "sling .*$SUBJ --on $FORMULA" <<< "$CALLS" \
  && ok "(VISITEDGE) slings the subject named by the tracks edge" || bad "(VISITEDGE) sling targets subject (calls: $CALLS)"
unset FAKE_VISIT_EDGE

# --- (REREADVERIFY) the subject re-read after visit resolution fails -> exit 4 ---
# A visit id resolves to its subject, which is re-read to read gc.recommended_formula.
# If THAT read fails transiently the formula reads empty; without re-verifying the
# re-read, accept would misreport the subject "discuss-only" (exit 2). The contract
# for an unverifiable subject is to fail closed (exit 4). The first read (of the
# visit) succeeds; only the subject re-read is made to fail.
export FAKE_SUBJECT_MODE=missing
run_accept "$VIS"
eq "$RC" "4" "(REREADVERIFY) a failed subject re-read after visit resolution fails closed (exit 4)"
[ -z "$CALLS" ] \
  && ok "(REREADVERIFY) nothing slung on an unverifiable re-read" || bad "(REREADVERIFY) must dispatch nothing (calls: $CALLS)"
grep -qi 'this visit names' <<< "$ERR" \
  && ok "(REREADVERIFY) names the subject it could not verify on the re-read" || bad "(REREADVERIFY) message (err: $ERR)"
export FAKE_SUBJECT_MODE=found

# --- (SLINGFAIL) a failed dispatch leaves the visit, dismisses nothing ---------
export FAKE_SLING_RC=1
run_accept "$SUBJ"
[ "$RC" -ne 0 ] \
  && ok "(SLINGFAIL) a failed sling exits non-zero" || bad "(SLINGFAIL) non-zero exit (rc=$RC)"
grep -q 'bd close' <<< "$CALLS" \
  && bad "(SLINGFAIL) must NOT dismiss the visit when the dispatch failed (calls: $CALLS)" \
  || ok "(SLINGFAIL) the visit is left open — nothing dismissed"
grep -qi 'left open' <<< "$ERR" \
  && ok "(SLINGFAIL) says the visit is left for retry or Discuss" || bad "(SLINGFAIL) message (err: $ERR)"
export FAKE_SLING_RC=0

# --- (MISSING) an unverifiable subject fails closed, dispatches nothing --------
export FAKE_SUBJECT_MODE=missing
run_accept "$SUBJ"
eq "$RC" "4" "(MISSING) an unresolvable subject exits 4"
[ -z "$CALLS" ] \
  && ok "(MISSING) nothing slung on an unverified subject" || bad "(MISSING) must dispatch nothing (calls: $CALLS)"
export FAKE_SUBJECT_MODE=found

# --- (PENDINGENGAGE) an open visit already BOUND by engage's assignee ----------
# The pending-engagement window: engage binds the visit by assignee while it is
# still open, before the claim stamps the session. The board suppresses Accept
# here, and so must the verb — else a copied command actuates after the operator
# has moved to Discuss. This is the case the P1 finding named.
export FAKE_VISIT_ASSIGNEE="gc-toolkit.converse-opus"
run_accept "$SUBJ"
eq "$RC" "4" "(PENDINGENGAGE) an assignee-bound open visit is refused (exit 4)"
[ -z "$CALLS" ] \
  && ok "(PENDINGENGAGE) nothing slung and nothing dismissed" || bad "(PENDINGENGAGE) must dispatch nothing (calls: $CALLS)"
grep -qi 'pending engagement' <<< "$ERR" \
  && ok "(PENDINGENGAGE) names the pending engagement" || bad "(PENDINGENGAGE) message (err: $ERR)"
unset FAKE_VISIT_ASSIGNEE

# --- (CLAIMED) an in_progress visit is a live conversation -> refuse -----------
export FAKE_VISIT_STATUS="in_progress"
run_accept "$SUBJ"
eq "$RC" "4" "(CLAIMED) an in_progress visit is refused (exit 4)"
[ -z "$CALLS" ] \
  && ok "(CLAIMED) nothing slung and nothing dismissed" || bad "(CLAIMED) must dispatch nothing (calls: $CALLS)"
grep -qi 'in progress' <<< "$ERR" \
  && ok "(CLAIMED) names the live conversation" || bad "(CLAIMED) message (err: $ERR)"
unset FAKE_VISIT_STATUS

# --- (SESSIONBOUND) an open visit with a bound session -> refuse --------------
export FAKE_VISIT_SESSION="gc-toolkit--gc-toolkit__converse-opus-1"
run_accept "$SUBJ"
eq "$RC" "4" "(SESSIONBOUND) a session-bound visit is refused (exit 4)"
[ -z "$CALLS" ] \
  && ok "(SESSIONBOUND) nothing slung and nothing dismissed" || bad "(SESSIONBOUND) must dispatch nothing (calls: $CALLS)"
grep -qi 'bound to session' <<< "$ERR" \
  && ok "(SESSIONBOUND) names the bound session" || bad "(SESSIONBOUND) message (err: $ERR)"
unset FAKE_VISIT_SESSION

# --- (ABSENT) no open visit on the subject -> refuse, dispatch nothing ---------
# accept actuates a recommendation the board is OFFERING; with no un-engaged
# visit there is no offer, and slinging would then dismiss nothing.
FAKE_VISIT=""
run_accept "$SUBJ"
eq "$RC" "4" "(ABSENT) a subject with no open visit is refused (exit 4)"
[ -z "$CALLS" ] \
  && ok "(ABSENT) nothing slung and nothing dismissed" || bad "(ABSENT) must dispatch nothing (calls: $CALLS)"
grep -qi 'no open visit' <<< "$ERR" \
  && ok "(ABSENT) says there is nothing to accept" || bad "(ABSENT) message (err: $ERR)"
export FAKE_VISIT=1

# --- (UNREADABLE) the visit listing does not parse -> FAIL CLOSED --------------
# A state the verb cannot read is not proof the visit is un-engaged, so it
# refuses rather than dispatching on an unread state.
export FAKE_LIST_MODE="notarray"
run_accept "$SUBJ"
eq "$RC" "4" "(UNREADABLE) an unreadable visit listing fails closed (exit 4)"
[ -z "$CALLS" ] \
  && ok "(UNREADABLE) nothing slung on an unread state" || bad "(UNREADABLE) must dispatch nothing (calls: $CALLS)"
grep -qi 'unread state' <<< "$ERR" \
  && ok "(UNREADABLE) names the unread state" || bad "(UNREADABLE) message (err: $ERR)"
unset FAKE_LIST_MODE

# --- (NOARG) accept with no bead is a usage error -----------------------------
run_accept
eq "$RC" "2" "(NOARG) accept with no bead exits 2"
grep -q 'accept needs' <<< "$ERR" \
  && ok "(NOARG) prints the usage error" || bad "(NOARG) usage error (err: $ERR)"

# --- (WIRING) the verb is reachable and documented ----------------------------
grep -qE '^[[:space:]]*accept\)[[:space:]]*shift; cmd_accept' "$SCRIPT" \
  && ok "(WIRING) accept is in the dispatch case" || bad "(WIRING) accept dispatch case missing"
grep -q 'gc-helm accept <bead-id>' "$SCRIPT" \
  && ok "(WIRING) accept is in the usage block" || bad "(WIRING) accept usage line missing"
grep -qE 'try:.*accept.*help' "$SCRIPT" \
  && ok "(WIRING) accept is in the unknown-verb hint" || bad "(WIRING) accept hint missing"

echo
echo "gc-helm-accept.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
