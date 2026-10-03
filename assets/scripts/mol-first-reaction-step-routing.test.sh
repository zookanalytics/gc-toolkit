#!/usr/bin/env bash
# Regression guard for mol-first-reaction's per-step routing metadata.
#
# THE INVARIANT: every [[steps]] block in formulas/mol-first-reaction.toml
# declares a `metadata` table carrying BOTH gc.continuation_group and
# gc.session_affinity with a non-empty value.
#
# WHY IT MATTERS: mol-first-reaction is one cheap reaction that runs to its
# terminal step in a single session and drains. gc.continuation_group and
# gc.session_affinity are what keep every step in that one session and make the
# pour route and offer each step to the proactive pool. A step that declares
# neither is never offered by the pool's find-work tier: it sits open and
# unassigned, its workflow-finalize blocked behind it, until a human notices —
# the stranded-husk failure this guard exists to prevent.
#
# WHY ONLY THESE TWO KEYS: gc.routed_to is NOT a step-metadata key the formula
# controls. The pour engine derives per-step routing — it retires gc.routed_to
# on the work bead in favour of gc.execution_routed_to, persists gc.routed_to on
# the workflow root, and parks per-step routing as gc.deferred_routed_to until
# the step activates (docs/gascity-routing-model.md). The two keys asserted here
# are exactly the ones a formula edit can drop, so they are what a formula-level
# guard can hold.
#
# The detector is run against the real formula (must pass) and against synthetic
# fixtures that omit the keys (must be flagged), so the check cannot pass
# vacuously and discriminates the keyless shape that strands a step.
#
# No live city, Dolt, network, or PRs — only python3's tomllib and a tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-first-reaction.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-mfr-step-routing.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

command -v python3 >/dev/null 2>&1 \
  || { echo "FAIL - python3 is required to read the formula's TOML structure"; exit 1; }

# --- The detector. -----------------------------------------------------------
# Reads a formula TOML and checks every [[steps]] declares both continuation
# keys with a non-empty value. Fail-closed on shape:
#   exit 0 — every step carries both keys (prints one OK line)
#   exit 1 — at least one step is missing a key (prints each VIOLATION)
#   exit 2 — the formula declares no [[steps]] (a vacuous pass guard)
#   exit 3 — the file will not parse as TOML
# It is the SAME code path for the real formula and the fixtures, so a pass on
# the formula and a flag on a keyless fixture are the one detector agreeing.
cat > "$TMP/check.py" <<'PY'
import sys, tomllib
REQUIRED = ("gc.continuation_group", "gc.session_affinity")
try:
    with open(sys.argv[1], "rb") as f:
        data = tomllib.load(f)
except Exception as e:
    print(f"PARSE-ERROR {e}")
    sys.exit(3)
steps = data.get("steps", [])
if not steps:
    print("NO-STEPS formula declares no [[steps]]")
    sys.exit(2)
violations = []
for s in steps:
    sid = s.get("id", "<no-id>")
    meta = s.get("metadata", {}) or {}
    missing = [k for k in REQUIRED if not str(meta.get(k, "")).strip()]
    if missing:
        violations.append(f"{sid}: missing {', '.join(missing)}")
if violations:
    for v in violations:
        print(f"VIOLATION {v}")
    sys.exit(1)
print(f"OK {len(steps)} step(s) carry both continuation keys")
sys.exit(0)
PY

run_detector() { python3 "$TMP/check.py" "$1" >"$TMP/out" 2>&1; printf '%s' "$?"; }

# --- The real formula must be clean. -----------------------------------------
python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$TOML" 2>/dev/null \
  && ok "mol-first-reaction.toml parses as TOML" \
  || bad "mol-first-reaction.toml parses as TOML (tomllib rejected it)"

RC="$(run_detector "$TOML")"
eq "$RC" "0" "every declared step carries both continuation keys"
[ "$RC" = "0" ] || { echo "    detector said:"; sed 's/^/      /' "$TMP/out"; }

# The formula must actually declare steps — a zero-step formula would pass the
# loop vacuously, so the no-steps case is its own exit code and is asserted.
STEP_COUNT="$(python3 -c 'import tomllib,sys; print(len(tomllib.load(open(sys.argv[1],"rb")).get("steps",[])))' "$TOML")"
[ "${STEP_COUNT:-0}" -ge 1 ] \
  && ok "formula declares at least one [[steps]] block (count=$STEP_COUNT)" \
  || bad "formula declares no [[steps]] — nothing for the guard to check"

# --- Discrimination: the detector must flag the keyless shapes. ---------------
# (A) A step missing BOTH keys — the exact shape that stranded: the pour never
#     offered it, so it sat open for weeks.
cat > "$TMP/missing-both.toml" <<'TOML'
formula = "fixture"
[[steps]]
id = "healthy"
metadata = { "gc.continuation_group" = "main", "gc.session_affinity" = "require" }
[[steps]]
id = "stranded"
TOML
RC="$(run_detector "$TMP/missing-both.toml")"
eq "$RC" "1" "(A) a step missing BOTH keys is flagged"
grep -q 'VIOLATION stranded: missing gc.continuation_group, gc.session_affinity' "$TMP/out" \
  && ok "(A) the violation names the step and both missing keys" \
  || { bad "(A) violation message missing or wrong"; sed 's/^/      /' "$TMP/out"; }

# (B) A step missing ONE key — a partial regression must still be caught.
cat > "$TMP/missing-one.toml" <<'TOML'
formula = "fixture"
[[steps]]
id = "half"
metadata = { "gc.continuation_group" = "main" }
TOML
RC="$(run_detector "$TMP/missing-one.toml")"
eq "$RC" "1" "(B) a step missing one key is flagged"

# (C) An empty value is as broken as an absent key — the pour reads nothing.
cat > "$TMP/empty-value.toml" <<'TOML'
formula = "fixture"
[[steps]]
id = "blank"
metadata = { "gc.continuation_group" = "", "gc.session_affinity" = "require" }
TOML
RC="$(run_detector "$TMP/empty-value.toml")"
eq "$RC" "1" "(C) an empty continuation-key value is flagged"

# (D) A formula with no steps is its own failure, not a silent pass.
printf 'formula = "fixture"\n' > "$TMP/no-steps.toml"
RC="$(run_detector "$TMP/no-steps.toml")"
eq "$RC" "2" "(D) a formula with no [[steps]] fails closed (not a vacuous pass)"

# (E) The positive control: a fixture where every step is healthy passes, so
#     the detector is not merely always-failing.
cat > "$TMP/all-healthy.toml" <<'TOML'
formula = "fixture"
[[steps]]
id = "a"
metadata = { "gc.continuation_group" = "main", "gc.session_affinity" = "require" }
[[steps]]
id = "b"
metadata = { "gc.continuation_group" = "main", "gc.session_affinity" = "require" }
TOML
RC="$(run_detector "$TMP/all-healthy.toml")"
eq "$RC" "0" "(E) a fully-healthy fixture passes"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
