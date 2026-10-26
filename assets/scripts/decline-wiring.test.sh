#!/usr/bin/env bash
# Hermetic wiring test for how the pack's formulas decline work.
#
# A molecule's lifecycle is gascity's. A worker that declines its work cancels
# its run through run-cancel.sh (gascity's run cancel), after it files the visit
# and records the wait on the work bead where a person must rule. No formula
# holds a molecule, de-routes another step, or retires a molecule by hand.
#
# What is exercised here:
#   * NO PACK LIFECYCLE: no formula, doctrine fragment or agent prompt calls
#     molecule-hold.sh, dead-molecule-dispose.sh or dead-molecule-sweep.sh, or
#     tells a reader to retire a molecule with `gc convoy delete`. The two
#     disposers do not ship. molecule-hold.sh ships only as the name that step
#     text from an earlier version of a formula calls: it hands the call to
#     run-cancel.sh and reads or writes no bead itself;
#   * OWN STEP: every run-cancel.sh --step call names the step it sits in, so a
#     decline cancels the run this shell is executing and no other;
#   * OPEN VISIT: every await-ruling.sh call follows an escalation that runs
#     with escalate.sh's verdict window off, or bring-current-audit.sh's ask,
#     because a wait needs an open visit and the window files none for a
#     situation a person already closed moot or benign;
#   * ORDER, executed: workspace-setup's missing-branch arm files the visit,
#     records the wait, cancels, then drains, and stops at the first part that
#     does not land;
#   * WITHDRAWN WORK, executed: the self-review and submit-and-exit entry gates
#     cancel the run when the work bead was closed mid-run, fall through when it
#     is open, and do not drain when the cancel does not land. A close that
#     landed the work (gc.work_outcome=shipped, or merge_result=merged) is not a
#     withdrawal: submit-and-exit closes its chain with outcome pass instead.
#
# No live city, Dolt, or network: the blocks are extracted verbatim from the
# formulas and run against a fake `gc` and stub scripts.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-decline-wiring-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # tomllib_python only; the assertions below are this suite's own
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# --- 1. No pack lifecycle. -------------------------------------------------------
LEFT=$(git -C "$ROOT" grep -n -E 'molecule-hold\.sh|dead-molecule-dispose\.sh|dead-molecule-sweep\.sh' \
  -- 'formulas/*.toml' 'template-fragments/*.md' 'agents/*' 'skills/*' 2>/dev/null || true)
eq "$LEFT" "" "no formula, fragment, prompt or skill names a pack hold or disposer"
RETIRE=$(git -C "$ROOT" grep -n -F 'gc convoy delete' -- 'formulas/*.toml' 'template-fragments/*.md' 2>/dev/null || true)
eq "$RETIRE" "" "no formula or fragment tells a reader to retire a molecule with gc convoy delete"
for script in dead-molecule-dispose.sh dead-molecule-sweep.sh; do
  [ -e "$HERE/$script" ] && bad "$script still ships" || ok "$script does not ship"
done
HOLD_CODE=$(grep -v -E '^[[:space:]]*#' "$HERE/molecule-hold.sh" 2>/dev/null || true)
# shellcheck disable=SC2016  # the literal text of the script's exec line
has "$HOLD_CODE" 'exec "$RUN_CANCEL"' "molecule-hold.sh hands its call to run-cancel.sh"
case "$HOLD_CODE" in
  *"gc bd"*|*"bd update"*|*"bd_json"*|*"bd-lib"*|*"--status"*|*"routed_to"*)
    bad "molecule-hold.sh reads or writes a bead itself" ;;
  *) ok "molecule-hold.sh reads and writes no bead itself" ;;
esac

# --- 2. Each cancel names the step it sits in. ----------------------------------
if TOML_PY="$(tomllib_python)"; then
  for f in mol-polecat-work mol-validate mol-rig-demo; do
    out=$("$TOML_PY" - "$ROOT/formulas/$f.toml" <<'PY'
import re, sys, tomllib
path = sys.argv[1]
d = tomllib.load(open(path, "rb"))
formula = d.get("formula", "")
bad = []
calls = 0
for st in d.get("steps", []):
    for m in re.finditer(r'run-cancel\.sh"? --step "?([^"` ,]+)', st.get("description", "")):
        ref = m.group(1)
        if not ref.startswith(formula + "."):
            continue
        calls += 1
        if ref != formula + "." + st["id"]:
            bad.append("%s names %s" % (st["id"], ref))
print("%d|%s" % (calls, "; ".join(bad)))
PY
)
    case "$out" in
      0\|*) bad "$f: no run-cancel.sh --step call found" ;;
      *\|) ok "$f: each of its ${out%%|*} run-cancel.sh --step calls names the step it sits in" ;;
      *) bad "$f: a cancel names another step: ${out#*|}" ;;
    esac
  done
else
  echo "skip - own-step check: $TOML_PY"
fi

# --- 2b. A wait sits on an open visit. ------------------------------------------
# escalate.sh files nothing for a situation a person closed moot or benign inside
# its verdict window, and the wait needs an open visit. So the escalation each
# await-ruling.sh call follows runs with GC_ESCALATE_VERDICT_WINDOW set, or is
# bring-current-audit.sh's ask, which turns the window off itself
# (bring-current-audit.test.sh holds it to that). The refinery's patrol is read
# too: merge-push makes a convoy's rebuild child wait on a visit.
if TOML_PY="$(tomllib_python)"; then
  for f in mol-polecat-work mol-validate mol-rig-demo mol-refinery-patrol; do
    out=$("$TOML_PY" - "$ROOT/formulas/$f.toml" <<'PY'
import re, sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
bad = []
waits = 0
for st in d.get("steps", []):
    lines = st.get("description", "").splitlines()
    for i, line in enumerate(lines):
        if not re.search(r'await-ruling\.sh" "', line):
            continue
        waits += 1
        filer = None
        for j in range(i - 1, -1, -1):
            if re.search(r'escalate\.sh" --subject', lines[j]) or re.search(r'"\$BCA" ask', lines[j]):
                filer = lines[j]
                break
        if filer is None:
            bad.append("%s: a wait with no escalation before it" % st["id"])
        elif 'escalate.sh"' in filer and "GC_ESCALATE_VERDICT_WINDOW=" not in filer:
            bad.append("%s: the escalation before a wait keeps the verdict window" % st["id"])
print("%d|%s" % (waits, "; ".join(bad)))
PY
)
    case "$out" in
      0\|) ok "$f: no wait to check" ;;
      *\|) ok "$f: each of its ${out%%|*} waits follows an escalation with the verdict window off" ;;
      *) bad "$f: ${out#*|}" ;;
    esac
  done
else
  echo "skip - open-visit check: $TOML_PY"
fi
# The same rule over the prose a worker declines by hand from.
FRAG_WAITS=0; FRAG_BAD=""
while IFS= read -r frag; do
  out=$(awk -v f="$frag" '
    /escalate\.sh" --subject/ || /"\$BCA" ask/ { filer = $0 }
    /await-ruling\.sh" "/ {
      n++
      if (filer == "") bad = bad f ": a wait with no escalation before it; "
      else if (filer ~ /escalate\.sh"/ && filer !~ /GC_ESCALATE_VERDICT_WINDOW=/) bad = bad f ": the escalation before a wait keeps the verdict window; "
    }
    END { printf "%d|%s", n, bad }' "$ROOT/$frag")
  FRAG_WAITS=$((FRAG_WAITS + ${out%%|*})); FRAG_BAD="$FRAG_BAD${out#*|}"
done < <(git -C "$ROOT" grep -l 'await-ruling.sh" "' -- 'template-fragments/*.md' 'agents/*' 'skills/*' 2>/dev/null)
if [ "$FRAG_WAITS" -eq 0 ]; then
  bad "no fragment, prompt or skill shows a wait; the doctrine's decline recipe is expected to"
elif [ -z "$FRAG_BAD" ]; then
  ok "each of the $FRAG_WAITS waits in fragments, prompts and skills follows an escalation with the verdict window off"
else
  bad "$FRAG_BAD"
fi

# --- Fakes for the executed blocks. -------------------------------------------
# gc: `runtime drain-ack` records DRAIN; `bd show` answers $FAKE_SHOW; every
# other call exits 0. The pack stubs record their verb and argv and exit with a
# code the case controls.
mkdir -p "$TMP/bin" "$TMP/pack/assets/scripts"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 ${2:-}" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd show") printf '%s\n' "${FAKE_SHOW:-[]}"; exit 0 ;;
esac
exit 0
GC
for v in escalate:ESCALATE await-ruling:AWAIT run-cancel:CANCEL step-close:STEPCLOSE; do
  name="${v%%:*}"; verb="${v#*:}"
  { printf '#!%s\n' "${BASH:-/usr/bin/env bash}"
    printf 'printf %s >> "$FAKE_LOG"\n' "'$verb\\n'"
    printf 'printf %s "$*" >> "$TMP_ARGS/%s"\n' "'%s\\n'" "$name"
    printf 'printf %s "${GC_ESCALATE_VERDICT_WINDOW-<unset>}" >> "$TMP_ARGS/%s.window"\n' "'%s\\n'" "$name"
    printf 'exit "${FAKE_%s_RC:-0}"\n' "$verb"; } > "$TMP/pack/assets/scripts/$name.sh"
done
chmod +x "$TMP/bin/gc" "$TMP/pack/assets/scripts/"*.sh
export PATH="$TMP/bin:$PATH" GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH="" TMP_ARGS="$TMP/args"
mkdir -p "$TMP_ARGS"

extract() { # <formula> <marker>
  awk -v m="$2" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$ROOT/formulas/$1.toml"
}
# run <block-file> [VAR=value...] -> "<rc>|<ordered verb log>"
run() {
  local block="$1"; shift
  : > "$TMP/log"; rm -f "$TMP_ARGS"/*
  local rc=0
  env FAKE_LOG="$TMP/log" "$@" bash "$block" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}
args() { cat "$TMP_ARGS/$1" 2>/dev/null; }

# --- 3. The missing-branch arm, in order. ----------------------------------------
extract mol-polecat-work workspace-setup-missing-branch-decline \
  | sed 's|{{convoy_id}}|tk-cv|g' > "$TMP/missing.sh"
[ -s "$TMP/missing.sh" ] && ok "missing-branch arm extracted" || bad "missing-branch arm extraction EMPTY"
set -- WORK_BEAD_ID=tk-work BRANCH=polecat/tk-work CLAIMED_STEP_BEAD_ID=st-setup
eq "$(run "$TMP/missing.sh" "$@")" "1|ESCALATE;AWAIT;CANCEL;DRAIN;" \
   "missing branch: visit, wait, cancel, drain, exit 1"
has "$(args escalate)" "--key polecat-missing-branch" "missing branch: the visit's key"
has "$(args escalate)" "closing it re-slings tk-work" "missing branch: the visit says closing it re-slings the work"
eq "$(args escalate.window)" "0" "missing branch: the visit is filed with escalate.sh's verdict window off"
eq "$(args await-ruling)" "tk-work --key polecat-missing-branch --formula mol-polecat-work" \
   "missing branch: the work bead waits on that visit"
has "$(args run-cancel)" "--step mol-polecat-work.workspace-setup --bead st-setup" \
   "missing branch: the cancel names this step and its claimed bead"
eq "$(run "$TMP/missing.sh" "$@" FAKE_ESCALATE_RC=1)" "1|ESCALATE;" \
   "missing branch: no visit, so no wait, no cancel, no drain"
eq "$(run "$TMP/missing.sh" "$@" FAKE_AWAIT_RC=1)" "1|ESCALATE;AWAIT;" \
   "missing branch: no wait, so no cancel, no drain"
eq "$(run "$TMP/missing.sh" "$@" FAKE_CANCEL_RC=1)" "1|ESCALATE;AWAIT;CANCEL;" \
   "missing branch: a cancel that did not land is not drained"

# --- 4. Withdrawn work. --------------------------------------------------------
extract mol-polecat-work self-review-withdrawn-work > "$TMP/review.sh"
extract mol-polecat-work submit-withdrawn-work | sed 's|{{convoy_id}}|tk-cv|g' > "$TMP/submit.sh"
[ -s "$TMP/review.sh" ] && ok "self-review gate extracted" || bad "self-review gate extraction EMPTY"
[ -s "$TMP/submit.sh" ] && ok "submit gate extracted" || bad "submit gate extraction EMPTY"
CLOSED='[{"id":"tk-work","status":"closed","metadata":{"gc.step_ref":"self-review.iteration.2"}}]'
OPEN='[{"id":"tk-work","status":"open","metadata":{"gc.step_ref":"self-review.iteration.2"}}]'

eq "$(run "$TMP/review.sh" WORK_BEAD_ID=tk-work CLAIMED_ITER_BEAD=it-2 WORK_JSON="$CLOSED" FAKE_SHOW="$CLOSED")" \
   "1|CANCEL;DRAIN;" "self-review: a work bead closed mid-run cancels the run, drains, exits 1"
has "$(args run-cancel)" "--step self-review.iteration.2 --bead it-2" \
   "self-review: the cancel names the iteration this session claimed"
has "$(args run-cancel)" "tk-work was closed while its run was mid-flight" "self-review: the reason names the withdrawn work"
eq "$(run "$TMP/review.sh" WORK_BEAD_ID=tk-work CLAIMED_ITER_BEAD=it-2 WORK_JSON="$OPEN" FAKE_SHOW="$OPEN")" \
   "0|" "self-review: open work falls through to the review"
eq "$(run "$TMP/review.sh" WORK_BEAD_ID=tk-work CLAIMED_ITER_BEAD=it-2 WORK_JSON="$CLOSED" FAKE_SHOW="$CLOSED" FAKE_CANCEL_RC=1)" \
   "1|CANCEL;" "self-review: a cancel that did not land is not drained"

eq "$(run "$TMP/submit.sh" WORK_BEAD_ID=tk-work CLAIMED_STEP_BEAD_ID=st-submit FAKE_SHOW="$CLOSED")" \
   "1|CANCEL;DRAIN;" "submit: a work bead closed mid-run cancels the run, drains, exits 1"
has "$(args run-cancel)" "--step mol-polecat-work.submit-and-exit --bead st-submit" \
   "submit: the cancel names this step and its claimed bead"
eq "$(run "$TMP/submit.sh" WORK_BEAD_ID=tk-work CLAIMED_STEP_BEAD_ID=st-submit FAKE_SHOW="$OPEN")" \
   "0|" "submit: open work falls through to the handoff"
eq "$(run "$TMP/submit.sh" WORK_BEAD_ID=tk-work CLAIMED_STEP_BEAD_ID=st-submit FAKE_SHOW='{"error":"store down"}')" \
   "0|" "submit: an unreadable work bead is not read as withdrawn"
eq "$(run "$TMP/submit.sh" WORK_BEAD_ID=tk-work CLAIMED_STEP_BEAD_ID=st-submit FAKE_SHOW="$CLOSED" FAKE_CANCEL_RC=1)" \
   "1|CANCEL;" "submit: a cancel that did not land is not drained"

# A close that landed the work: the step was offered again after its handoff, so
# it closes its chain with outcome pass rather than cancelling a delivered run.
CHAIN="STEPCLOSE;STEPCLOSE;STEPCLOSE;STEPCLOSE;STEPCLOSE;DRAIN;"
SHIPPED='[{"id":"tk-work","status":"closed","metadata":{"gc.work_outcome":"shipped","merge_result":"merged"}}]'
eq "$(run "$TMP/submit.sh" WORK_BEAD_ID=tk-work CLAIMED_STEP_BEAD_ID=st-submit FAKE_SHOW="$SHIPPED")" \
   "0|$CHAIN" "submit: a work bead closed as shipped closes the chain and drains, exits 0"
has "$(args step-close)" "--step mol-polecat-work.submit-and-exit --convoy tk-cv --outcome pass" \
    "submit: a shipped close records this step as passed, in its own molecule"
eq "$(args run-cancel)" "" "submit: a shipped close cancels nothing"
eq "$(run "$TMP/submit.sh" WORK_BEAD_ID=tk-work CLAIMED_STEP_BEAD_ID=st-submit FAKE_SHOW='[{"id":"tk-work","status":"closed","metadata":{"merge_result":"merged"}}]')" \
   "0|$CHAIN" "submit: a merge closed before gc.work_outcome was stamped is a landed close too"
eq "$(run "$TMP/submit.sh" WORK_BEAD_ID=tk-work CLAIMED_STEP_BEAD_ID=st-submit FAKE_SHOW='[{"id":"tk-work","status":"closed","metadata":{"gc.work_outcome":"shipped"}}]')" \
   "0|$CHAIN" "submit: a rework hand-back closed as shipped is a landed close"
eq "$(run "$TMP/submit.sh" WORK_BEAD_ID=tk-work CLAIMED_STEP_BEAD_ID=st-submit FAKE_SHOW='[{"id":"tk-work","status":"closed","metadata":{"merge_result":"pull_request"}}]')" \
   "1|CANCEL;DRAIN;" "submit: a bead closed with its PR still open was withdrawn, so the run is cancelled"
eq "$(run "$TMP/submit.sh" WORK_BEAD_ID=tk-work CLAIMED_STEP_BEAD_ID=st-submit FAKE_SHOW='[{"id":"tk-work","status":"closed","metadata":{"gc.work_outcome":"no-op"}}]')" \
   "1|CANCEL;DRAIN;" "submit: a no-op close was withdrawn, so the run is cancelled"

echo
echo "decline-wiring.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
