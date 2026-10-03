#!/usr/bin/env bash
# epic-steward — one pass of epic stewardship over this rig's open epics.
# Driven by orders/epic-steward.toml (cooldown, scope=rig): the controller
# supplies the loop, cwd = the rig root, and the env (GC_RIG, GC_PACK_STATE_DIR).
# It is the second steward in the pack after the refinery and wears the same
# shape — enumerate the stewarded object, run independent arms, surface the
# follow-up.
#
# For each open epic the pass runs independent arms. Each files ONE deduped
# operator visit (escalate.sh, keyed by concern) when the epic owes a decision
# only the operator can make, and files nothing when it does not:
#   floor     — no recorded hypothesis: the epic cannot be classified into or
#               judged complete until it carries the floor contract (a handle, a
#               one-sentence hypothesis, boundaries). Propose it for ratification.
#   contract  — floor set but the closure condition or leading indicators are
#               absent: propose the rest of the contract.
#   ruling    — every unit has landed and no ruling is recorded: an epic closes
#               by a persevere/pivot/close ruling on its hypothesis after a
#               validation step, never as a side effect of its last unit merging
#               (docs/epics.md). The visit's tracks edge also holds the epic's
#               finalize (finalize-gate.sh clause_no_open_visit), and the arm
#               retracts it once a ruling is recorded.
# The judgment each visit asks for is the operator's; the pass only detects what
# is owed. A membership-sweep arm (re-home work that has drifted outside its
# epic) is deferred: it needs a repair primitive and a scope classification the
# pass cannot do in shell (docs/epic-stewardship.md names the deferral).
#
# This is NOT a doctor check (doctor is over-leveraged): doctor's only epic role
# is asserting this order is live (check-cadence-live, which covers any orders/
# file) and the closed-implies-ruled invariant (check-epic-closed-implies-ruled).
#
# NOT set -e / pipefail: the arms are independent, so one that fails must not
# skip the rest, and the next tick retries everything.
set -u

PROG="epic-steward"

# Rig identity comes from the order runner; a scope="rig" order with no rig has
# nothing to steward.
RIG="${GC_RIG:-}"
if [ -z "$RIG" ]; then
  echo "$PROG: GC_RIG is unset — this runs as a scope=\"rig\" order and has no rig to steward" >&2
  exit 2
fi
# Siblings resolve from $0: the pack lives under the owning rig.
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# escalate.sh files (and retracts) the operator visits; overridable so the test
# captures the calls without a live store.
ESCALATE="${GC_ESCALATE_TOOL:-$SCRIPTS_DIR/escalate.sh}"

# bd-lib supplies bd_list / bd_json, the consolidated store readers the lint rule
# requires in scope. Every store read in this pass goes through them, so they
# carry the only scrub it needs and it defines none of its own.
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || {
  echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }

# Per-rig single-flight. A pass re-files nothing — escalate.sh dedups by
# (subject, key) — but a long pass must not overlap the next tick, so one flock
# serialises passes per rig. Fail closed: no usable lock, no pass, because an
# unguarded pair of passes racing escalate.sh's find-or-file read could file a
# duplicate before either sees the other's visit.
RIG_KEY="$(printf '%s' "$RIG" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
case "$RIG_KEY" in ''|.|..) RIG_KEY=rig ;; esac
STATE_DIR="${EPIC_STEWARD_STATE_DIR:-${GC_PACK_STATE_DIR:-${TMPDIR:-/tmp}/gc}/epic-steward}/$RIG_KEY"
mkdir -p "$STATE_DIR" 2>/dev/null || true
LOCK="$STATE_DIR/pass.lock"
if ! command -v flock >/dev/null 2>&1 || ! ( : >> "$LOCK" ) 2>/dev/null; then
  echo "$PROG[$RIG]: single-flight UNGUARDED (no usable flock at $LOCK) — refusing to run any arm" >&2
  exit 1
fi
exec 9>>"$LOCK" || { echo "$PROG[$RIG]: cannot open $LOCK" >&2; exit 1; }
if ! flock -n 9; then
  echo "$PROG[$RIG]: a pass is already in flight — skipping this tick"
  exit 0
fi

# No per-pass epic cap. Epics are a coarse per-rig anchor (few per rig), the pass
# is one jq emission plus a deduped visit only per owed decision, and the order's
# own timeout and the single-flight flock already bound how long one pass runs. A
# cap that took the first N in a stable listing order would never advance: epics
# past N would be audited on no tick, so one could reach "all units landed" and
# sit held forever with no ruling visit ever filed. The pass audits the whole
# live set instead.
filed=0
checked=0
failed=0

# file_visit <epic> <key> <message> — one deduped operator visit. escalate.sh
# files it, or refreshes the open one, and exits 0 either way; its tracks edge to
# the epic is what holds the epic's finalize until the conversation is answered.
file_visit() {
  _es_epic="$1"; _es_key="$2"; _es_msg="$3"
  if "$ESCALATE" --subject "$_es_epic" --key "$_es_key" --message "$_es_msg" >/dev/null 2>&1; then
    filed=$((filed + 1))
  else
    echo "$PROG[$RIG]: escalate.sh failed to file '$_es_key' on $_es_epic" >&2
    failed=$((failed + 1))
  fi
}

# retract_visit <epic> <key> <reading> — close the open visit this steward filed
# for a concern that has resolved on its own. Idempotent: no open visit is a
# no-op success, so this is safe to call every pass.
retract_visit() {
  _es_epic="$1"; _es_key="$2"; _es_msg="$3"
  "$ESCALATE" --retract --subject "$_es_epic" --key "$_es_key" --message "$_es_msg" >/dev/null 2>&1 || true
}

# epic_ruling_valid <value> — true only for a ruling docs/epics.md defines:
# persevere, pivot, or close. Empty, a draft ("pending"), or a typo is not a
# ruling, so the epic is not yet ruled. The same enum the finalize gate and the
# doctor check (I14) apply; the three readers stay in step, and an off-enum value
# never makes this arm stop asking while the gate still holds the close.
epic_ruling_valid() { case "${1:-}" in persevere|pivot|close) return 0 ;; *) return 1 ;; esac; }

# --- arms -------------------------------------------------------------------
# Each arm takes the epic id and the plain contract strings the pass already read.
# All three wear the same shape: when the concern is OWED, file one deduped visit;
# when it has CLEARED, retract the visit the arm would have filed, so a visit never
# outlives the condition that justified it (orders/epic-steward.toml). retract is
# idempotent — escalate.sh reads no open visit as a no-op success — so an arm whose
# concern was never raised retracts nothing.

arm_floor() { # <epic> <hypothesis>
  _a_epic="$1"; _a_hyp="$2"
  if [ -n "$_a_hyp" ]; then
    retract_visit "$_a_epic" "epic-floor" "a hypothesis is recorded; the floor contract is set"
    return 0
  fi
  file_visit "$_a_epic" "epic-floor" \
"This epic carries no recorded hypothesis, so work cannot be classified into it and it cannot be judged complete.

Draft and ratify its floor contract, then record it on the epic: a 3-5 word handle (epic_handle), a one-sentence hypothesis — for whom, what changes, the signal it worked — (epic_hypothesis), and its boundaries (epic_boundaries). A rough hypothesis is enough to start. docs/epic-stewardship.md names the fields; docs/epics.md is the contract. Subject: epic $_a_epic."
}

arm_contract() { # <epic> <hypothesis> <closure-condition> <indicators>
  _a_epic="$1"; _a_hyp="$2"; _a_clo="$3"; _a_ind="$4"
  # No floor yet: arm_floor owns that; a contract presupposes a hypothesis.
  [ -n "$_a_hyp" ] || return 0
  if [ -n "$_a_clo" ] && [ -n "$_a_ind" ]; then
    retract_visit "$_a_epic" "epic-contract" "the contract is complete; a closure condition and leading indicators are recorded"
    return 0
  fi
  _a_need=""
  [ -z "$_a_clo" ] && _a_need="a closure condition (epic_closure_condition: 3-6 operator-runnable checks that each fail today)"
  [ -z "$_a_ind" ] && _a_need="${_a_need:+$_a_need and }1-3 leading indicators (epic_indicators)"
  file_visit "$_a_epic" "epic-contract" \
"This epic has a hypothesis but is missing $_a_need, so it has no agreed test of done and no in-flight signal to steer by.

Fill in the rest of the contract on the epic. docs/epic-stewardship.md names the fields; docs/epics.md is the contract. Subject: epic $_a_epic."
}

arm_ruling() { # <epic> <hypothesis> <ruling>
  _a_epic="$1"; _a_hyp="$2"; _a_ruling="$3"
  # A ruling answers a hypothesis; without one, arm_floor owns the epic first.
  [ -n "$_a_hyp" ] || return 0
  if epic_ruling_valid "$_a_ruling"; then
    # Ruled: release any ruling visit still holding the epic's finalize.
    retract_visit "$_a_epic" "epic-ruling" "hypothesis ruled ($_a_ruling); the epic may close"
    return 0
  fi
  # The epic's units are its children; they point at it (incoming parent-child).
  _a_kids=$(bd_json dep list "$_a_epic" --direction=up -t parent-child)
  if ! printf '%s' "$_a_kids" | jq -e 'type == "array"' >/dev/null 2>&1; then
    # An unreadable children probe is not "no ruling owed": count it a failure so
    # the summary says so and the order exits non-zero, rather than the ruling arm
    # going silently dark on a persistent breakage (flag drift, store permission)
    # that only the doctor backstop would catch, and only after a hand-close. The
    # pass still continues — the next tick retries the whole set.
    echo "$PROG[$RIG]: children probe unreadable for $_a_epic — ruling arm skipped it this pass" >&2
    failed=$((failed + 1))
    return 0
  fi
  _a_total=$(printf '%s' "$_a_kids" | jq 'length' 2>/dev/null)
  [ "${_a_total:-0}" -gt 0 ] 2>/dev/null || return 0        # no units yet
  _a_unlanded=$(printf '%s' "$_a_kids" | jq '[ .[] | select((.status // "") != "closed") ] | length' 2>/dev/null)
  [ "${_a_unlanded:-1}" -eq 0 ] 2>/dev/null || return 0     # units still in flight
  file_visit "$_a_epic" "epic-ruling" \
"Every unit under this epic has landed and its hypothesis has no recorded ruling, so the epic is complete but cannot close.

An epic closes by a ruling on its hypothesis — persevere, pivot, or close — after a validation step, never as a side effect of its last unit merging (docs/epics.md). Judge the hypothesis against the landed work and record the ruling (epic_ruling, with epic_ruling_evidence naming this visit). Subject: epic $_a_epic ($_a_total units landed)."
}

# --- main pass --------------------------------------------------------------

# The gate holds every non-closed epic (finalize-gate.sh clause_epic_ruling_
# recorded is status-agnostic), so the pass audits the same live set. Open-only
# would miss an in_progress (or blocked/deferred) epic whose units all land: no
# ruling visit would ever be filed and the gate would hold its close forever.
EPICS_JSON=$(bd_list --type=epic --status=open,in_progress) || {
  echo "$PROG[$RIG]: could not read live epics (bd_list failed) — nothing stewarded this pass" >&2
  exit 1
}

# One jq emission reads every epic's id and the four contract fields the arms
# need, unit-separated (\037) so an empty field — the common case the arms detect
# — keeps its column; a whitespace IFS would collapse a run of empties and
# misalign the row. The arms take plain strings, so the pass spawns one jq, not
# the ~7 per epic a re-parse-per-field loop did.
while IFS=$'\037' read -r epic hyp clo ind ruling; do
  [ -n "$epic" ] || continue
  checked=$((checked + 1))
  arm_floor    "$epic" "$hyp"
  arm_contract "$epic" "$hyp" "$clo" "$ind"
  arm_ruling   "$epic" "$hyp" "$ruling"
done < <(printf '%s' "$EPICS_JSON" | jq -r '
  .[] | [ (.id // "" | tostring),
          (.metadata.epic_hypothesis // "" | tostring),
          (.metadata.epic_closure_condition // "" | tostring),
          (.metadata.epic_indicators // "" | tostring),
          (.metadata.epic_ruling // "" | tostring) ]
      | join("\u001f")' 2>/dev/null)

echo "$PROG[$RIG]: checked $checked live epic(s), filed or refreshed $filed visit(s), $failed failure(s)"
[ "$failed" -eq 0 ]
