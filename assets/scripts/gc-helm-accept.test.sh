#!/usr/bin/env bash
# Hermetic test for the gc-helm `accept` verb (Accept/Discuss recommendation
# flow, design tk-hsm4d9; work tk-qulxvk).
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
#   the VISIT id   -> a task_kind=visit bead tracking the subject, and carrying
#     gc.outcome=dismissed so dismiss's stamp read-back (meta_now) is satisfied
#     without the stub having to model state.
# `bd list` (dismiss's visit lookup) yields the one open visit when $FAKE_VISIT
# is set. sling/close/update are recorded; sling's exit is $FAKE_SLING_RC.
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
            if [ -n "${FAKE_VISIT_EDGE:-}" ]; then
              # The su-ab9je shape: the continuation_group stamp landed EMPTY and
              # only the tracks edge names the subject, rendered in the bd show
              # dep shape {dependency_type, id}.
              jq -n --arg i "$id" --arg s "$FAKE_SUBJECT_ID" \
                '[{id:$i, status:"open", title:"visit on the subject",
                   metadata:{task_kind:"visit","gc.continuation_group":"","gc.outcome":"dismissed"},
                   dependencies:[{id:$s, dependency_type:"tracks"}]}]'
            else
              jq -n --arg i "$id" --arg s "$FAKE_SUBJECT_ID" \
                '[{id:$i, status:"open", title:"visit on the subject",
                   metadata:{task_kind:"visit","gc.continuation_group":$s,"gc.outcome":"dismissed"}}]'
            fi ;;
          "${FAKE_SUBJECT_ID:-__nosubj__}")
            case "${FAKE_SUBJECT_MODE:-found}" in
              missing) printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1 ;;
              *) jq -n --arg i "$id" --arg f "${FAKE_FORMULA:-}" \
                   '[{id:$i, status:"open", title:"the subject",
                      metadata:( if $f=="" then {} else {"gc.recommended_formula":$f} end )}]' ;;
            esac ;;
          *) printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1 ;;
        esac ;;
      list)
        if [ -n "${FAKE_VISIT:-}" ]; then
          jq -n --arg v "$FAKE_VISIT_ID" --arg s "$FAKE_SUBJECT_ID" \
            '[{id:$v, metadata:{task_kind:"visit","gc.continuation_group":$s}}]'
        else printf '[]\n'; fi ;;
      close)  printf '%s\n' "$*" >> "$FAKE_CALLS" ;;
      update) printf '%s\n' "$*" >> "$FAKE_CALLS" ;;
    esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_CALLS="$TMP/calls"
# Hermetic: no inherited fixture hook, no ambient rig steering the resolver, and
# the cache stays out of the operator's real dir.
unset GC_HELM_FIXTURE GC_RIG || true
export TMPDIR="$TMP"

# run_accept <arg...> -> sets RC/OUT/ERR/CALLS from the per-case FAKE_* env.
run_accept() {
    : > "$FAKE_CALLS"
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
