#!/usr/bin/env bash
# Hermetic test for assets/scripts/claim-close.sh.
#
# The constraint: a pool slot's assignee names every molecule it ever ran, so
# one step_ref under one assignee can match a prior run's bead. The close goes
# only to the bead `gc hook current` names, and only when that bead is the step
# the caller is finishing.
#
# No live city, Dolt or network: a tmpdir, a `gc` stub over a JSON store, and
# the script itself.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/claim-close.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-claim-close-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
set -u
S="${FAKE_STORE:?}"
printf '%s\n' "$*" >> "${GC_LOG:?}"
case "${1:-} ${2:-}" in
  "hook current")
    [ -n "${FAKE_HOOK_CURRENT:-}" ] || { echo "gc hook current: session has no current claim (stub)" >&2; exit 1; }
    printf '%s\n' "$FAKE_HOOK_CURRENT"; exit 0 ;;
esac
[ "${1:-}" = "bd" ] || { echo "gc stub: unsupported '$*'" >&2; exit 2; }
shift
verb="${1:-}"; shift || true
case "$verb" in
  show)
    [ -n "${FAKE_SHOW_FAIL:-}" ] && { echo "bd: store down (stub)" >&2; exit 1; }
    out=$(jq -c --arg id "${1:-}" '[ .[] | select(.id == $id) ]' "$S")
    if [ "$out" = "[]" ]; then printf '{"error":"no issue found matching %s"}\n' "${1:-}"; else printf '%s\n' "$out"; fi ;;
  update)
    id="${1:-}"; shift || true
    [ -n "${FAKE_UPDATE_FAIL:-}" ] && { echo "bd: refused (stub)" >&2; exit 1; }
    outcome=""; status=""
    for x in "$@"; do
      case "$x" in
        gc.outcome=*) outcome="${x#gc.outcome=}" ;;
        --status=*) status="${x#--status=}" ;;
      esac
    done
    jq --arg id "$id" --arg o "$outcome" --arg s "$status" \
      '[ .[] | if .id == $id then (.status = $s | .metadata["gc.outcome"] = $o) else . end ]' "$S" > "$S.new" && mv "$S.new" "$S" ;;
  *) echo "gc stub: unsupported bd verb '$verb'" >&2; exit 2 ;;
esac
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_STORE="$TMP/store.json" GC_LOG="$TMP/gc.log"
export GC_SESSION_ID=slot-session

# Two molecules this slot ran, each with the same step ref and assignee: the
# prior one left open, as a re-offered or stranded chain leaves it. A third
# bead is the next step of the live molecule, and a fourth is a plain work bead.
seed() {
  cat > "$FAKE_STORE" <<'JSON'
[
  {"id":"prior-impl","status":"open","assignee":"slot-session","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"prior-root"}},
  {"id":"live-impl","status":"in_progress","assignee":"slot-session","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"live-root"}},
  {"id":"live-next","status":"in_progress","assignee":"slot-session","metadata":{"gc.step_ref":"mol-polecat-work.submit-and-exit","gc.root_bead_id":"live-root"}},
  {"id":"plain","status":"in_progress","assignee":"slot-session","metadata":{}},
  {"id":"iter-2","status":"in_progress","assignee":"slot-session","metadata":{"gc.step_ref":"self-review.iteration.2"}},
  {"id":"gone","status":"closed","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.implement"}},
  {"id":"foreign","status":"in_progress","assignee":"other-session","metadata":{"gc.step_ref":"mol-polecat-work.implement"}},
  {"id":"released","status":"open","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.implement"}},
  {"id":"parked","status":"blocked","assignee":"slot-session","metadata":{"gc.step_ref":"mol-polecat-work.implement"}}
]
JSON
  : > "$GC_LOG"
}
status_of() { jq -r --arg id "$1" '.[] | select(.id == $id) | .status' "$FAKE_STORE"; }
outcome_of() { jq -r --arg id "$1" '.[] | select(.id == $id) | .metadata["gc.outcome"] // ""' "$FAKE_STORE"; }
run() { OUT=$("$SCRIPT" "$@" 2>&1); RC=$?; }

# --- a claim after a prior molecule on the same pool slot closes the live one ---
seed; export FAKE_HOOK_CURRENT=live-impl
run --step mol-polecat-work.implement
eq "$RC" 0 "the current claim closes"
eq "$(status_of live-impl)" closed "the bead gc hook current names is closed"
eq "$(outcome_of live-impl)" pass "the outcome defaults to pass"
eq "$(status_of prior-impl)" open "the prior molecule's bead for the same step and assignee stays open"
has "$OUT" "closed live-impl" "the result names the bead"

seed; export FAKE_HOOK_CURRENT=live-impl
run --step mol-polecat-work.implement --outcome fail
eq "$(outcome_of live-impl)" fail "--outcome is written"

# --- a close re-run after the claim moved on closes nothing --------------------
seed; export FAKE_HOOK_CURRENT=live-next
run --step mol-polecat-work.implement
eq "$RC" 2 "a claim on another step refuses"
eq "$(status_of live-next)" in_progress "the step the claim moved to is not closed unrun"
has "$OUT" "gc hook --claim --json" "the refusal says how to take the step"

# --- a bead with no steps is refused, not closed --------------------------------
seed; export FAKE_HOOK_CURRENT=plain
run --step mol-dog-shutdown-dance.close
eq "$RC" 2 "a plain routed bead refuses"
eq "$(status_of plain)" in_progress "the plain bead stays as it was"

# --- a check loop's iteration closes by the loop's name -------------------------
seed; export FAKE_HOOK_CURRENT=iter-2
run --step self-review
eq "$RC" 0 "an iteration closes by its loop's name"
eq "$(status_of iter-2)" closed "the iteration is closed"
seed; export FAKE_HOOK_CURRENT=iter-2
run --step self
eq "$RC" 2 "a prefix of the loop's name is not its name"
seed; export FAKE_HOOK_CURRENT=live-impl
run --step mol-polecat-work
eq "$RC" 2 "a formula's name is not one of its steps"
eq "$(status_of live-impl)" in_progress "so the step it names stays open"

# --- a bead that is already closed is the retry of an interrupted close ---------
seed; export FAKE_HOOK_CURRENT=gone
run --step mol-polecat-work.implement
eq "$RC" 0 "an already-closed step exits 0"
has "$OUT" "already closed" "and says so"
if grep -q 'bd update' "$GC_LOG"; then bad "an already-closed step writes nothing"; else ok "an already-closed step writes nothing"; fi

# --- a step this session does not hold is refused ------------------------------
seed; export FAKE_HOOK_CURRENT=foreign
run --step mol-polecat-work.implement
eq "$RC" 2 "a step another session holds refuses"
eq "$(status_of foreign)" in_progress "another session's step stays as it was"
seed; export FAKE_HOOK_CURRENT=released
run --step mol-polecat-work.implement
eq "$RC" 2 "a step with no assignee refuses"
eq "$(status_of released)" open "a released step stays as it was"
seed; export FAKE_HOOK_CURRENT=parked
run --step mol-polecat-work.implement
eq "$RC" 2 "a parked step refuses"
eq "$(status_of parked)" blocked "a parked step stays as it was"

# --- each name a claim is recorded under holds it ------------------------------
for ident in GC_ALIAS GC_SESSION_NAME GC_AGENT; do
  seed
  jq '[ .[] | if .id == "live-impl" then .assignee = "held-name" else . end ]' "$FAKE_STORE" > "$FAKE_STORE.new" && mv "$FAKE_STORE.new" "$FAKE_STORE"
  export FAKE_HOOK_CURRENT=live-impl
  OUT=$(env "$ident=held-name" "$SCRIPT" --step mol-polecat-work.implement 2>&1); RC=$?
  eq "$RC" 0 "a claim recorded under $ident is this session's"
done

# --- failures name the step and do not claim success ---------------------------
seed; unset FAKE_HOOK_CURRENT
run --step mol-polecat-work.implement
eq "$RC" 1 "no current claim exits 1"
has "$OUT" "names no bead this session claimed" "and says why"
if grep -q 'bd update' "$GC_LOG"; then bad "no current claim writes nothing"; else ok "no current claim writes nothing"; fi

seed; export FAKE_HOOK_CURRENT=live-impl FAKE_SHOW_FAIL=1
run --step mol-polecat-work.implement
eq "$RC" 1 "a read that fails exits 1"
eq "$(status_of live-impl)" in_progress "a read that fails writes nothing"
unset FAKE_SHOW_FAIL

seed; export FAKE_HOOK_CURRENT=missing
run --step mol-polecat-work.implement
eq "$RC" 1 "a claim the store does not return exits 1"

seed; export FAKE_HOOK_CURRENT=live-impl FAKE_UPDATE_FAIL=1
run --step mol-polecat-work.implement
eq "$RC" 1 "a close that does not land exits 1"
has "$OUT" "did not land" "and says the step is still open"
unset FAKE_UPDATE_FAIL

# --- --dry-run reports and writes nothing ---------------------------------------
seed; export FAKE_HOOK_CURRENT=live-impl
run --step mol-polecat-work.implement --dry-run
eq "$RC" 0 "--dry-run exits 0"
has "$OUT" "would close live-impl" "--dry-run names the bead"
eq "$(status_of live-impl)" in_progress "--dry-run writes nothing"

# --- usage ----------------------------------------------------------------------
seed
run
eq "$RC" 2 "no --step is refused"
run --step '{{step}}'
eq "$RC" 2 "an unsubstituted --step is refused"
run --step mol.x --outcome 'a b'
eq "$RC" 2 "an --outcome with a space is refused"
run --step
eq "$RC" 2 "--step with no value is refused"
run --nope
eq "$RC" 2 "an unknown flag is refused"
if grep -q 'bd update' "$GC_LOG"; then bad "a usage error writes nothing"; else ok "a usage error writes nothing"; fi

# --- each formula's close names the step it sits in -----------------------------
# A close that names another step refuses at run time, and the step stays open. A
# check loop's iterations carry the loop's bare name.
ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # tomllib_python only; the assertions above are this suite's own
if TOML_PY="$(tomllib_python)"; then
  CHECKED=0
  for f in "$ROOT"/formulas/*.toml; do
    grep -q 'claim-close\.sh' "$f" || continue
    out=$("$TOML_PY" - "$f" <<'CHECK'
import re, sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
formula = d.get("formula", "")
bad = []
calls = 0
for st in d.get("steps", []):
    for m in re.finditer(r'(?:claim-close\.sh|\$SC|\$\{SC:\?[^}]*\})"? --step ([A-Za-z0-9._<>-]+)', st.get("description", "")):
        ref = m.group(1)
        if "<" in ref:
            continue
        calls += 1
        if ref not in (formula + "." + st["id"], st["id"]):
            bad.append("%s names %s" % (st["id"], ref))
print("%d|%s" % (calls, "; ".join(bad)))
CHECK
)
    case "$out" in
      0\|*) ;;
      *\|) CHECKED=$((CHECKED + 1)); ok "$(basename "$f"): each of its ${out%%|*} closes names the step it sits in" ;;
      *) bad "$(basename "$f"): a close names another step: ${out#*|}" ;;
    esac
  done
  [ "$CHECKED" -ge 5 ] && ok "the check reached the formulas that close steps ($CHECKED)" || bad "expected at least five formulas closing steps, found $CHECKED"
else
  echo "skip - own-step check: $TOML_PY"
fi

echo
echo "passed: $PASS failed: $FAIL"
[ "$FAIL" -eq 0 ]
