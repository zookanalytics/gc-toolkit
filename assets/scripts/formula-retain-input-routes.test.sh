#!/usr/bin/env bash
# formula-retain-input-routes.test.sh — retain_input_routes is declared true, at
# the top level of the formula, on exactly the formulas that react to their
# subject without driving it.
#
# Starting a graph.v2 workflow retires gc.routed_to on the bead it is attached to
# and on every member of its input convoy, so the workflow is the only live
# dispatch surface for that work. A formula that declares
# `retain_input_routes = true` keeps those routes, and a gc formula compiler
# that reads the key stamps gc.retain_input_routes=true on the workflow root
# (gascity formula spec v2). The key belongs only on a formula that hands its
# subject on instead of working it:
#   mol-first-reaction         annotates the subject, then routes, holds or
#                              gates it, so it declares the key
# Every other formula that takes a subject through an input convoy drives it and
# keeps the retire, so no pool can hand the subject to a second worker while the
# workflow runs:
#   mol-polecat-work           builds the subject and hands it to the refinery
#   mol-review and
#   mol-review-quorum-signoff  judge the review bead, which signoff.sh disposes of
#   mol-validate               rules a findings batch and closes its own pass bead
#   mol-validate-close         closes the subject or escalates it
#   mol-rig-demo               captures a demo and closes the request bead
#
# The suite catches two mistakes before a pour does. A key written below a table
# header belongs to that table, so it is not the formula's declaration. And a
# driving formula that gains the key, itself or through extends, leaves its
# subject's route live while it works the subject. The detector runs against the
# real formulas (must pass) and against a fixture of each broken shape (must be
# flagged), so it cannot pass vacuously.
#
# Hermetic: reads the pack's own formula sources with a tomllib Python. No city,
# network, or build.
#
# run-tests-scope: tree
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FORMULAS="$ROOT/formulas"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-retain-input-routes.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # tomllib_python only; the assertions below are this suite's own
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

TOML_PY="$(tomllib_python)" \
  || { echo "skip - every check here reads the formulas' TOML structure: $TOML_PY"; exit 0; }

# The formulas that react to their subject without driving it.
REACTING="mol-first-reaction"

# --- The detector. -----------------------------------------------------------
# argv: <comma-separated reacting names> <formula.toml>...
# A formula's name is its `formula` value, else its file name. Fail-closed:
#   exit 0 — the declarations match the reacting set (prints one OK line)
#   exit 1 — at least one VIOLATION (prints each)
#   exit 2 — a reacting name has no formula, so the set is stale
#   exit 3 — a file will not parse as TOML
# It is the same code path for the real formulas and the fixtures.
cat > "$TMP/check.py" <<'PY'
import os, sys, tomllib

KEY = "retain_input_routes"
reacting = {n for n in sys.argv[1].split(",") if n}
formulas = {}
for path in sys.argv[2:]:
    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except Exception as e:
        print(f"PARSE-ERROR {os.path.basename(path)}: {e}")
        sys.exit(3)
    name = data.get("formula") or os.path.splitext(os.path.basename(path))[0]
    formulas[name] = data

def nested(node, where):
    """Every table path below the top level that holds the key."""
    found = []
    if isinstance(node, dict):
        for k, v in node.items():
            if k == KEY and where:
                found.append(".".join(where))
            found += nested(v, where + [k])
    elif isinstance(node, list):
        for i, v in enumerate(node):
            label = v.get("id", str(i)) if isinstance(v, dict) else str(i)
            found += nested(v, where[:-1] + [f"{where[-1]}[{label}]"] if where else [str(i)])
    return found

def retains(name, seen=()):
    """The formula's own declaration, or one it inherits from a parent here."""
    data = formulas.get(name)
    if data is None or name in seen:
        return False
    if data.get(KEY) is True:
        return True
    return any(retains(p, seen + (name,)) for p in data.get("extends", []) or [])

missing = sorted(reacting - formulas.keys())
if missing:
    for n in missing:
        print(f"NO-FORMULA {n} is in the reacting set, and no formula here is named that")
    sys.exit(2)

violations = []
for name, data in sorted(formulas.items()):
    for where in nested(data, []):
        violations.append(f"{name}: {KEY} sits under {where}, not at the top level, so it is not the formula's declaration")
    value = data.get(KEY)
    if value is not None and not isinstance(value, bool):
        violations.append(f"{name}: {KEY} = {value!r} is not a TOML boolean")
    if name in reacting:
        if value is not True:
            violations.append(f"{name}: reacts to its subject without driving it, so it must declare {KEY} = true at the top level")
    elif retains(name):
        how = "declares" if value is True else "inherits"
        via = "" if value is True else " through extends"
        violations.append(f"{name}: {how} {KEY} = true{via} but drives its subject, so starting it must retire the subject's route")
if violations:
    for v in violations:
        print(f"VIOLATION {v}")
    sys.exit(1)
print(f"OK {len(formulas)} formula(s); {KEY} declared on exactly: {', '.join(sorted(reacting)) or '(none)'}")
sys.exit(0)
PY

run_detector() { "$TOML_PY" "$TMP/check.py" "$@" >"$TMP/out" 2>&1; printf '%s' "$?"; }

# --- The real formulas must match the reacting set. -------------------------
set -- "$FORMULAS"/*.toml
[ -e "$1" ] || { bad "no formulas found under $FORMULAS"; echo "$PASS passed, $FAIL failed"; exit 1; }
RC="$(run_detector "$REACTING" "$@")"
eq "$RC" "0" "the pack's formulas declare retain_input_routes on exactly the reacting set ($REACTING)"
[ "$RC" = "0" ] || { echo "    detector said:"; sed 's/^/      /' "$TMP/out"; }

# The positive read, independent of the detector: the real formula carries the
# key at its top level as a boolean true.
TOP="$("$TOML_PY" -c 'import sys, tomllib; print(repr(tomllib.load(open(sys.argv[1], "rb")).get("retain_input_routes")))' "$FORMULAS/mol-first-reaction.toml")"
eq "$TOP" "True" "mol-first-reaction.toml declares retain_input_routes = true at the top level"

# --- Discrimination: the detector must flag each broken shape. ---------------
fixture() { # <dir> <file> — reads the formula body on stdin
  mkdir -p "$TMP/$1"; cat > "$TMP/$1/$2"
}
DRIVES='formula = "mol-drives"
[requires]
formula_compiler = ">=2.0.0"
[[steps]]
id = "work"'

# (A) The reacting formula without the key: its starts retire the subject's route.
fixture absent mol-first-reaction.toml <<'TOML'
formula = "mol-first-reaction"
[requires]
formula_compiler = ">=2.0.0"
TOML
RC="$(run_detector "$REACTING" "$TMP/absent/mol-first-reaction.toml")"
eq "$RC" "1" "(A) a reacting formula without the key is flagged"
grep -q 'VIOLATION mol-first-reaction: reacts to its subject without driving it' "$TMP/out" \
  && ok "(A) …and the violation names the formula and why" \
  || { bad "(A) violation message missing or wrong"; sed 's/^/      /' "$TMP/out"; }

# (B) Declared false.
fixture false mol-first-reaction.toml <<'TOML'
formula = "mol-first-reaction"
retain_input_routes = false
TOML
RC="$(run_detector "$REACTING" "$TMP/false/mol-first-reaction.toml")"
eq "$RC" "1" "(B) a reacting formula declaring the key false is flagged"

# (C) Written below [requires], where it belongs to that table.
fixture requires mol-first-reaction.toml <<'TOML'
formula = "mol-first-reaction"
[requires]
formula_compiler = ">=2.0.0"
retain_input_routes = true
TOML
RC="$(run_detector "$REACTING" "$TMP/requires/mol-first-reaction.toml")"
eq "$RC" "1" "(C) the key written under [requires] is flagged"
grep -q 'retain_input_routes sits under requires, not at the top level' "$TMP/out" \
  && ok "(C) …and the violation names the table it landed in" \
  || { bad "(C) violation message missing or wrong"; sed 's/^/      /' "$TMP/out"; }

# (D) Written inside a step.
fixture step mol-first-reaction.toml <<'TOML'
formula = "mol-first-reaction"
retain_input_routes = true
[[steps]]
id = "load-bead"
retain_input_routes = true
TOML
RC="$(run_detector "$REACTING" "$TMP/step/mol-first-reaction.toml")"
eq "$RC" "1" "(D) the key written inside a step is flagged"
grep -q 'sits under steps\[load-bead\]' "$TMP/out" \
  && ok "(D) …naming the step by its id" \
  || { bad "(D) violation message missing or wrong"; sed 's/^/      /' "$TMP/out"; }

# (E) Quoted, so a string and not a boolean.
fixture string mol-first-reaction.toml <<'TOML'
formula = "mol-first-reaction"
retain_input_routes = "true"
TOML
RC="$(run_detector "$REACTING" "$TMP/string/mol-first-reaction.toml")"
eq "$RC" "1" "(E) a quoted \"true\" is flagged"
grep -q "retain_input_routes = 'true' is not a TOML boolean" "$TMP/out" \
  && ok "(E) …as not a TOML boolean" \
  || { bad "(E) violation message missing or wrong"; sed 's/^/      /' "$TMP/out"; }

# (F) A driving formula that declares the key.
fixture driver mol-first-reaction.toml <<'TOML'
formula = "mol-first-reaction"
retain_input_routes = true
TOML
printf '%s\nretain_input_routes = true\n' "${DRIVES%%$'\n'*}" > "$TMP/driver/mol-drives.toml"
RC="$(run_detector "$REACTING" "$TMP/driver/mol-first-reaction.toml" "$TMP/driver/mol-drives.toml")"
eq "$RC" "1" "(F) a driving formula that declares the key is flagged"
grep -q 'VIOLATION mol-drives: declares retain_input_routes = true but drives its subject' "$TMP/out" \
  && ok "(F) …naming the driving formula" \
  || { bad "(F) violation message missing or wrong"; sed 's/^/      /' "$TMP/out"; }

# (G) A driving formula that inherits the key through extends.
fixture inherit mol-first-reaction.toml <<'TOML'
formula = "mol-first-reaction"
retain_input_routes = true
TOML
printf 'extends = ["mol-first-reaction"]\n%s\n' "$DRIVES" > "$TMP/inherit/mol-drives.toml"
RC="$(run_detector "$REACTING" "$TMP/inherit/mol-first-reaction.toml" "$TMP/inherit/mol-drives.toml")"
eq "$RC" "1" "(G) a driving formula that extends a reacting one is flagged"
grep -q 'VIOLATION mol-drives: inherits retain_input_routes = true through extends' "$TMP/out" \
  && ok "(G) …as an inherited declaration" \
  || { bad "(G) violation message missing or wrong"; sed 's/^/      /' "$TMP/out"; }

# (H) A reacting name no formula carries: the set has gone stale.
fixture stale mol-drives.toml <<<"$DRIVES"
RC="$(run_detector "$REACTING" "$TMP/stale/mol-drives.toml")"
eq "$RC" "2" "(H) a reacting name with no formula fails closed (not a vacuous pass)"

# (I) The positive control: the reacting formula declares the key and a driving
#     formula does not, so the detector is not merely always-failing.
fixture healthy mol-first-reaction.toml <<'TOML'
formula = "mol-first-reaction"
retain_input_routes = true
[requires]
formula_compiler = ">=2.0.0"
TOML
fixture healthy mol-drives.toml <<<"$DRIVES"
RC="$(run_detector "$REACTING" "$TMP/healthy/mol-first-reaction.toml" "$TMP/healthy/mol-drives.toml")"
eq "$RC" "0" "(I) a healthy fixture passes"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
