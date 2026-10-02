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

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# bd-lib supplies bd_list / bd_json, the consolidated store readers the lint rule
# requires in scope (it carries its own scrub; the block above is for the direct
# dep-list read below).
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

# Bound the work one pass does so a rig with many epics cannot overrun the order
# timeout; the remainder is audited next tick. A ceiling, not active pacing.
MAX_EPICS="${EPIC_STEWARD_MAX_EPICS_PER_PASS:-50}"

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

meta_field() { # <metadata-json> <key>
  printf '%s' "$1" | jq -r --arg k "$2" '(.[$k] // "") | tostring' 2>/dev/null
}

# --- arms -------------------------------------------------------------------

arm_floor() { # <epic> <metadata-json>
  _a_epic="$1"; _a_meta="$2"
  [ -n "$(meta_field "$_a_meta" epic_hypothesis)" ] && return 0
  file_visit "$_a_epic" "epic-floor" \
"This epic carries no recorded hypothesis, so work cannot be classified into it and it cannot be judged complete.

Draft and ratify its floor contract, then record it on the epic: a 3-5 word handle (epic_handle), a one-sentence hypothesis — for whom, what changes, the signal it worked — (epic_hypothesis), and its boundaries (epic_boundaries). A rough hypothesis is enough to start. docs/epic-stewardship.md names the fields; docs/epics.md is the contract. Subject: epic $_a_epic."
}

arm_contract() { # <epic> <metadata-json>
  _a_epic="$1"; _a_meta="$2"
  # No floor yet: arm_floor owns that; a contract presupposes a hypothesis.
  [ -n "$(meta_field "$_a_meta" epic_hypothesis)" ] || return 0
  _a_clo=$(meta_field "$_a_meta" epic_closure_condition)
  _a_ind=$(meta_field "$_a_meta" epic_indicators)
  [ -n "$_a_clo" ] && [ -n "$_a_ind" ] && return 0
  _a_need=""
  [ -z "$_a_clo" ] && _a_need="a closure condition (epic_closure_condition: 3-6 operator-runnable checks that each fail today)"
  [ -z "$_a_ind" ] && _a_need="${_a_need:+$_a_need and }1-3 leading indicators (epic_indicators)"
  file_visit "$_a_epic" "epic-contract" \
"This epic has a hypothesis but is missing $_a_need, so it has no agreed test of done and no in-flight signal to steer by.

Fill in the rest of the contract on the epic. docs/epic-stewardship.md names the fields; docs/epics.md is the contract. Subject: epic $_a_epic."
}

arm_ruling() { # <epic> <metadata-json>
  _a_epic="$1"; _a_meta="$2"
  # A ruling answers a hypothesis; without one, arm_floor owns the epic first.
  [ -n "$(meta_field "$_a_meta" epic_hypothesis)" ] || return 0
  if [ -n "$(meta_field "$_a_meta" epic_ruling)" ]; then
    # Ruled: release any ruling visit still holding the epic's finalize.
    retract_visit "$_a_epic" "epic-ruling" "hypothesis ruled ($(meta_field "$_a_meta" epic_ruling)); the epic may close"
    return 0
  fi
  # The epic's units are its children; they point at it (incoming parent-child).
  _a_kids=$(gc bd dep list "$_a_epic" --direction=up -t parent-child --json 2>/dev/null | scrub)
  printf '%s' "$_a_kids" | jq -e 'type == "array"' >/dev/null 2>&1 || return 0
  _a_total=$(printf '%s' "$_a_kids" | jq 'length' 2>/dev/null)
  [ "${_a_total:-0}" -gt 0 ] 2>/dev/null || return 0        # no units yet
  _a_unlanded=$(printf '%s' "$_a_kids" | jq '[ .[] | select((.status // "") != "closed") ] | length' 2>/dev/null)
  [ "${_a_unlanded:-1}" -eq 0 ] 2>/dev/null || return 0     # units still in flight
  file_visit "$_a_epic" "epic-ruling" \
"Every unit under this epic has landed and its hypothesis has no recorded ruling, so the epic is complete but cannot close.

An epic closes by a ruling on its hypothesis — persevere, pivot, or close — after a validation step, never as a side effect of its last unit merging (docs/epics.md). Judge the hypothesis against the landed work and record the ruling (epic_ruling, with epic_ruling_evidence naming this visit). Subject: epic $_a_epic ($_a_total units landed)."
}

# --- main pass --------------------------------------------------------------

EPICS_JSON=$(bd_list --type=epic --status=open) || {
  echo "$PROG[$RIG]: could not read open epics (bd_list failed) — nothing stewarded this pass" >&2
  exit 1
}

while IFS= read -r epic; do
  [ -n "$epic" ] || continue
  checked=$((checked + 1))
  meta=$(printf '%s' "$EPICS_JSON" | jq -c --arg id "$epic" '(.[] | select(.id == $id) | .metadata) // {}' 2>/dev/null)
  [ -n "$meta" ] || meta='{}'
  arm_floor    "$epic" "$meta"
  arm_contract "$epic" "$meta"
  arm_ruling   "$epic" "$meta"
done < <(printf '%s' "$EPICS_JSON" | jq -r '.[].id' 2>/dev/null | head -n "$MAX_EPICS")

echo "$PROG[$RIG]: checked $checked open epic(s), filed or refreshed $filed visit(s), $failed escalate failure(s)"
[ "$failed" -eq 0 ]
