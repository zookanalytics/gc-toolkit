#!/usr/bin/env bash
# Hermetic test for mol-polecat-work's load-context bd-ready guard.
#
# A v2 formula-sling pours immediately and reads no `blocks` deps, so a work
# bead with an open blocker reaches a polecat as an offered claim (the routed
# record is the workflow root, not the work bead — docs/gascity-routing-model.md).
# This guard is the pack-level safety net: at load-context, if the work bead
# carries an open `blocks` blocker it refuses to build, contains the pour's
# delivery keys, arms a re-dispatch so the work re-offers when the blocker
# closes, and holds the molecule.
#
# What it holds:
#   1. DISCRIMINATION — fires ONLY on an OPEN `blocks` dep. A `relates-to` dep,
#      a `blocks` dep whose blocker is CLOSED, and no deps at all are all
#      no-ops that let load-context proceed.
#   2. CONTAINMENT + ARM — on an open blocker it appends a note, clears the
#      five delivery keys (so `arm` accepts the bead and reconcile slings it
#      rather than retiring a still-routed record), arms deferred-dispatch to
#      the pool the pour was executing on replaying `--on mol-polecat-work`,
#      then holds and drain-acks.
#   3. FAIL CLOSED — arm failure falls back to escalate; with no release path
#      recorded it neither holds nor drains; a hold that did not land does not
#      drain. The step is never left silently claimable or silently parked.
#
# EXECUTES the real snippet extracted verbatim from the formula against fake
# `gc` and stub scripts, so the test cannot drift from the shipped instruction.
# No live city, Dolt, network, or worktrees.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-load-context-blocked-work-gate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3" "'$2' unexpectedly in '$1'" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract the REAL snippet from the formula. -------------------------------
# The flag-flip pulls the lines between the markers (exclusive). If the markers
# are removed or renamed — the exact thing a wholesale reconciliation against
# base does — extraction yields nothing and the checks below fail loudly.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}

GATE="$(extract load-context-blocked-work-hold)"

[ -n "$GATE" ] \
  && ok "gate extracted between load-context-blocked-work-hold markers" \
  || bad "gate extraction EMPTY — markers missing from $TOML"

# Two regions sharing one marker name would concatenate into one extraction and
# double every assertion below; pin the opener to a single occurrence.
eq "$(grep -c '^# >>> load-context-blocked-work-hold$' "$TOML")" "1" \
   "exactly one load-context-blocked-work-hold region"

# TOML `"""` strings eat a trailing backslash (line-ending escape), silently
# joining lines. The snippet is written backslash-free; assert it, because
# reintroducing a continuation is an easy and invisible edit.
case "$GATE" in
  *\\*) bad "snippet contains a backslash — TOML line-ending escapes will mangle it" ;;
  *)    ok  "snippet is backslash-free (safe inside a TOML triple-quoted string)" ;;
esac

printf '%s\n' "$GATE" > "$TMP/gate.sh"
bash -n "$TMP/gate.sh" \
  && ok "extracted gate is syntactically valid bash" \
  || bad "extracted gate failed bash -n"

# --- Fakes. -------------------------------------------------------------------
# gc : `bd update` and `runtime drain-ack` record to $FAKE_LOG; the block reads
#      the work bead from $WORK_BEAD_JSON (set by the step), so no `bd show` is
#      needed. `bd update --append-notes ...` and the delivery-key clear both
#      arrive here; the argv is captured so the containment write is provable.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd update")         shift 2; printf 'UPDATE\n' >> "$FAKE_LOG"; printf '%s\n' "$*" >> "${FAKE_UPDATE:-/dev/null}"; exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# molecule-hold.sh, escalate.sh, deferred-dispatch.sh resolved out of
# $GC_PACK_DIR exactly as the arm resolves them. Each records its verb into the
# ordered trace and its argv where the reason/target assertions can read it,
# and returns a code the assertions control.
mkdir -p "$TMP/pack/assets/scripts"
cat > "$TMP/pack/assets/scripts/molecule-hold.sh" <<'HOLD'
#!/usr/bin/env bash
printf 'HOLD\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_HOLD:-/dev/null}"
exit "${FAKE_HOLD_RC:-0}"
HOLD
cat > "$TMP/pack/assets/scripts/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf 'ESCALATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_ESC:-/dev/null}"
exit "${FAKE_ESC_RC:-0}"
ESC
cat > "$TMP/pack/assets/scripts/deferred-dispatch.sh" <<'ARM'
#!/usr/bin/env bash
printf 'ARM\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_ARM:-/dev/null}"
exit "${FAKE_ARM_RC:-0}"
ARM
chmod +x "$TMP/pack/assets/scripts/molecule-hold.sh" \
         "$TMP/pack/assets/scripts/escalate.sh" \
         "$TMP/pack/assets/scripts/deferred-dispatch.sh"
export GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH=""

# run <work-bead-json> -> prints "<rc>|<ordered verb log>"
#   FAKE_*_RC control each stub's exit; FAKE_UPDATE/HOLD/ESC/ARM capture argv.
run() {
  : > "$TMP/log"; : > "$TMP/update"; : > "$TMP/hold"; : > "$TMP/esc"; : > "$TMP/arm"
  local rc=0
  WORK_BEAD_ID=tk-work \
  WORK_BEAD_JSON="$1" \
  CLAIMED_STEP_BEAD_ID=st-load \
  FAKE_LOG="$TMP/log" FAKE_UPDATE="$TMP/update" FAKE_HOLD="$TMP/hold" \
  FAKE_ESC="$TMP/esc" FAKE_ARM="$TMP/arm" \
  FAKE_HOLD_RC="${FAKE_HOLD_RC:-0}" FAKE_ESC_RC="${FAKE_ESC_RC:-0}" FAKE_ARM_RC="${FAKE_ARM_RC:-0}" \
    bash "$TMP/gate.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

POOL="gc-toolkit/gc-toolkit.polecat"
META_ROUTED='{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}'

# --- 1. Discrimination: the gate is a no-op unless an OPEN blocks dep exists. --

eq "$(run "[{\"metadata\":$META_ROUTED,\"dependencies\":[]}]")" \
   "0|" \
   "no dependencies: no-op, load-context proceeds"

eq "$(run "[{\"metadata\":$META_ROUTED,\"dependencies\":[{\"id\":\"tk-rel\",\"dependency_type\":\"relates-to\",\"status\":\"open\"}]}]")" \
   "0|" \
   "relates-to dep (not blocks): no-op — discriminates on dependency_type"

eq "$(run "[{\"metadata\":$META_ROUTED,\"dependencies\":[{\"id\":\"tk-done\",\"dependency_type\":\"blocks\",\"status\":\"closed\"}]}]")" \
   "0|" \
   "blocks dep whose blocker is CLOSED: no-op — discriminates on status"

# --- 2. The case the gate exists for: an OPEN blocks blocker. -----------------

BLOCKED_JSON="[{\"metadata\":$META_ROUTED,\"dependencies\":[{\"id\":\"tk-blk\",\"dependency_type\":\"blocks\",\"status\":\"open\"}]}]"
eq "$(run "$BLOCKED_JSON")" \
   "1|UPDATE;UPDATE;ARM;HOLD;DRAIN;" \
   "open blocker: notes, clears keys, arms, holds, drain-acks, exits 1"

# The containment write clears every delivery key, execution route included —
# arm keys on gc.routed_to, not the execution stamp, but the arm carries --on,
# and reconcile retires an --on arm whose gc.execution_routed_to is set (a pour
# that already ran) rather than slinging it.
run "$BLOCKED_JSON" >/dev/null
has "$(cat "$TMP/update")" 'gc.execution_routed_to=' "containment clears gc.execution_routed_to"
has "$(cat "$TMP/update")" 'gc.deferred_execution_routed_to=' "containment clears gc.deferred_execution_routed_to"
has "$(cat "$TMP/update")" 'gc.routed_to=' "containment clears gc.routed_to"
has "$(cat "$TMP/update")" 'gc.deferred_routed_to=' "containment clears gc.deferred_routed_to"
has "$(cat "$TMP/update")" 'gc.deferred_assignee=' "containment clears gc.deferred_assignee"
has "$(cat "$TMP/update")" '--append-notes' "records the refusal on the work bead"

# The re-dispatch is armed to the pool the pour was executing on, replaying the
# formula, so the work re-offers itself when the blocker closes.
has "$(cat "$TMP/arm")" "arm tk-work --target $POOL" "arms re-dispatch to the pour's pool"
has "$(cat "$TMP/arm")" '--sling-arg --on --sling-arg mol-polecat-work' "replays --on mol-polecat-work"

# The hold names this step and blocker so a reader knows what releases it.
has "$(cat "$TMP/hold")" 'mol-polecat-work.load-context' "holds THIS step"
has "$(cat "$TMP/hold")" 'tk-blk' "hold reason names the blocker"

# A closed blocker in the same set must not appear in OPEN_BLOCKERS; only the
# open one is named.
MIXED_JSON="[{\"metadata\":$META_ROUTED,\"dependencies\":[{\"id\":\"tk-open\",\"dependency_type\":\"blocks\",\"status\":\"open\"},{\"id\":\"tk-done\",\"dependency_type\":\"blocks\",\"status\":\"closed\"}]}]"
eq "$(run "$MIXED_JSON")" \
   "1|UPDATE;UPDATE;ARM;HOLD;DRAIN;" \
   "mixed set: fires on the open blocker"
run "$MIXED_JSON" >/dev/null
has "$(cat "$TMP/hold")" 'tk-open' "names the open blocker"
no  "$(cat "$TMP/hold")" 'tk-done' "omits the closed blocker from the set"

# --- 3. Fail-closed arms. -----------------------------------------------------

# arm cannot be recorded (deferred-dispatch exits non-zero): fall back to a
# human visit, then hold and drain. (The RC override must reach the `run`
# function itself — an env prefix on `eq` would apply after the command
# substitution has already expanded.)
out="$(FAKE_ARM_RC=1 run "$BLOCKED_JSON")"
eq "$out" "1|UPDATE;UPDATE;ARM;ESCALATE;HOLD;DRAIN;" \
   "arm fails: escalate fallback, then hold + drain"

# No execution route to derive a target from: arm is skipped (POOL empty) and
# escalation carries the work forward.
NOPOOL_JSON="[{\"metadata\":{},\"dependencies\":[{\"id\":\"tk-blk\",\"dependency_type\":\"blocks\",\"status\":\"open\"}]}]"
eq "$(run "$NOPOOL_JSON")" \
   "1|UPDATE;UPDATE;ESCALATE;HOLD;DRAIN;" \
   "no pool target: skips arm, escalates, holds, drains"

# Neither release path recorded: NEVER hold or drain — the step stays claimable
# and the next worker retries the release.
out="$(FAKE_ARM_RC=1 FAKE_ESC_RC=1 run "$BLOCKED_JSON")"
eq "$out" "1|UPDATE;UPDATE;ARM;ESCALATE;" \
   "no release path: does not hold, does not drain"

# Release recorded but the hold did not land: do NOT drain — the molecule can
# still be re-offered.
out="$(FAKE_HOLD_RC=1 run "$BLOCKED_JSON")"
eq "$out" "1|UPDATE;UPDATE;ARM;HOLD;" \
   "hold fails after arm: does not drain"

# --- Summary. -----------------------------------------------------------------
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
