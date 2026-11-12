#!/usr/bin/env bash
# Hermetic wiring test for how the pack's formulas decline work.
#
# A molecule's lifecycle is gascity's. A worker that declines its work cancels
# its run through run-cancel.sh (gascity's run cancel), after it files the human
# gate and records the wait on the work bead where a person must rule. No
# formula holds a molecule, de-routes another step, or retires a molecule by
# hand.
#
# What is exercised here:
#   * NO PACK LIFECYCLE: no formula, doctrine fragment or agent prompt calls
#     molecule-hold.sh, dead-molecule-dispose.sh or dead-molecule-sweep.sh, or
#     tells a reader to retire a molecule with `gc convoy delete`. The two
#     disposers do not ship. molecule-hold.sh ships only as the name that step
#     text from an earlier version of a formula calls: it hands the call to
#     run-cancel.sh and reads or writes no bead itself;
#   * OWN STEP: every run-cancel.sh or decline.sh --step call in a formula names
#     the step it sits in, so a decline cancels the run this shell is executing
#     and no other;
#   * OPEN GATE: every await-ruling.sh call in a formula follows a human-gate.sh
#     filing that declares no quiet window, or bring-current-audit.sh's ask,
#     because a wait needs an open gate and a quiet window files none for a
#     situation a person already answered moot or benign;
#   * STAND-DOWN: a gate that arms a re-sling tells a person how to rule the other
#     way, through stand-down.sh under the gate's own key, and nothing tells them
#     to close a bead the gate blocks, which bd refuses. bring-current-audit.sh's
#     ask is the one that does not, because its gate asks how to resolve a conflict.
#     The skills a person's ruling reaches give the command;
#
# decline.test.sh holds the order of a decline, and work-setup.test.sh,
# work-enter.test.sh, work-submit.test.sh and mol-rig-demo-capture-arm.test.sh
# each arm that calls it. No live city, Dolt, or network: this suite reads the
# pack's formulas, prompts, skills and scripts.
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
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

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
  for f in mol-review mol-validate mol-rig-demo; do
    out=$("$TOML_PY" - "$ROOT/formulas/$f.toml" <<'PY'
import re, sys, tomllib
path = sys.argv[1]
d = tomllib.load(open(path, "rb"))
formula = d.get("formula", "")
bad = []
calls = 0
for st in d.get("steps", []):
    for m in re.finditer(r'(?:run-cancel|decline)\.sh"? --step "?([^"` ,]+)', st.get("description", "")):
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
      0\|*) bad "$f: no run-cancel.sh or decline.sh --step call found" ;;
      *\|) ok "$f: each of its ${out%%|*} run-cancel.sh and decline.sh --step calls names the step it sits in" ;;
      *) bad "$f: a cancel names another step: ${out#*|}" ;;
    esac
  done
else
  echo "skip - own-step check: $TOML_PY"
fi

# --- 2b. A wait sits on an open gate. -------------------------------------------
# human-gate.sh files nothing for a situation a person answered moot or benign
# inside a quiet window the call declares, and the wait needs an open gate. So
# the filing each await-ruling.sh call follows declares no --quiet-window, or is
# bring-current-audit.sh's ask, which declares none itself
# (bring-current-audit.test.sh holds it to that).
if TOML_PY="$(tomllib_python)"; then
  for f in mol-validate mol-rig-demo; do
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
            if re.search(r'human-gate\.sh" --subject', lines[j]) or re.search(r'"\$BCA" ask', lines[j]):
                filer = lines[j]
                break
        if filer is None:
            bad.append("%s: a wait with no human gate filed before it" % st["id"])
        elif 'human-gate.sh"' in filer and "--quiet-window" in filer:
            bad.append("%s: the filing before a wait declares a quiet window" % st["id"])
print("%d|%s" % (waits, "; ".join(bad)))
PY
)
    case "$out" in
      0\|) ok "$f: no wait to check" ;;
      *\|) ok "$f: each of its ${out%%|*} waits follows a filing with no quiet window" ;;
      *) bad "$f: ${out#*|}" ;;
    esac
  done
else
  echo "skip - open-gate check: $TOML_PY"
fi

# --- 2c. A wait says how to rule the other way. ---------------------------------
# bd refuses to close a bead an open gate blocks, and clearing the gate re-slings
# armed work, so the one way to rule that it will not go on is stand-down.sh.
CLOSE_FIRST=$(git -C "$ROOT" grep -n -E 'closes the work bead first|close \$[A-Z_]+,? (first|then clear)' \
  -- 'formulas/*.toml' 'template-fragments/*.md' 'agents/*' 'skills/*' 'assets/scripts/await-ruling.sh' \
  'assets/scripts/decline.sh' 'assets/scripts/work-*.sh' ':!assets/scripts/*.test.sh' 2>/dev/null || true)
eq "$CLOSE_FIRST" "" "nothing tells a person to close a bead before they clear the gate that blocks it"
grep -q 'stand-down\.sh' "$ROOT/template-fragments/polecat-doctrine.template.md" \
  && ok "the doctrine names stand-down.sh for a ruling not to proceed" \
  || bad "the doctrine does not name stand-down.sh for a ruling not to proceed"
skill_has() { # <skill> <text> <label>: a phrase may wrap across lines there
  local text
  text=$(tr '\n' ' ' < "$ROOT/skills/$1/SKILL.md" | tr -s ' ')
  case "$text" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2')" ;; esac
}
skill_has waits '/stand-down.sh" <bead> --key <situation-key> --ruling "' "the waits skill gives the stand-down's command"
skill_has waits 'Never answer the gate first and close afterwards' "the waits skill rules out answering the gate first"
skill_has waits '--successor <the bead that records the ruling>' "the waits skill gives the evidence a gate that holds another bead needs"
skill_has waits 'Never remove that edge yourself first' "the waits skill rules out taking an armed bead off a gate by hand"
skill_has work '/stand-down.sh" <bead> --key <situation-key> --ruling "' "the work skill gives the stand-down's command"
skill_has work 'It leaves a deferred-dispatch arm in place' "the work skill says a stop that keeps the bead leaves its arm"
skill_has converse-settle '/stand-down.sh" "$SUBJECT" --key <situation-key> --ruling "<the ruling, one line>" --successor "$CONVERSATION"' "the converse-settle step gives the stand-down's command, with the conversation as its evidence"
skill_has converse-settle 'Stand it down first' "the converse-settle step stands the subject down before the sign-off"
skill_has converse-settle 'add `--leave <gate>` to the sign-off' "the converse-settle step keeps a gate's other bead waiting through the sign-off"
# mol-polecat-work's step scripts file their gates through decline.sh, which ends
# the message of each gate that arms a re-sling with the stand-down under that
# gate's own key (decline.test.sh holds the sentence). So no work script arms a
# gate's re-sling itself, apart from bring-current-audit.sh's question.
OWN_WAITS=$(git -C "$ROOT" grep -n -E 'await-ruling\.sh" "\$[A-Z_]+" --key ' \
  -- 'assets/scripts/work-*.sh' ':!assets/scripts/*.test.sh' 2>/dev/null | grep -v -F -- '--key "bring-current-question.' || true)
eq "$OWN_WAITS" "" "mol-polecat-work's scripts arm a gate's re-sling only through decline.sh, apart from the bring-current question"
echo
echo "decline-wiring.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
