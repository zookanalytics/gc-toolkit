#!/usr/bin/env bash
# formula-step-size.test.sh — every formula step renders whole inside a hook.
#
# gc delivers an agent's current step as a <system-reminder> that carries the
# step bead's whole description (formatWispStepReminder in gascity's
# cmd/gc/wisp_step_inject.go). Two Claude Code hooks deliver it: the SessionStart
# additionalContext of `gc prime --hook`, and the stdout of `gc nudge drain
# --inject` on UserPromptSubmit. Claude Code caps each hook string at 10,000
# characters. A longer string reaches the agent as a saved-file path and a
# 2,000-character preview, with nothing asking the agent to read the file.
#
# So each step's reminder stays under BOUND, which leaves the rest of the cap
# for what shares the hook string: the session header, unread mail, queued
# nudges, and pour-time variable values longer than their placeholders. A step
# that does not fit keeps its instructions inline and moves its reference
# material into a doc, or its mechanics into a script, that the step names.
#
# The render matches what a pour writes and the reminder wraps. Each
# {{var}} takes the formula's own non-empty default and keeps its placeholder
# otherwise. The bead id is a stand-in of a real id's width. Length is counted
# in UTF-16 code units, the unit of the JavaScript string length the cap is
# measured in.
#
# Hermetic: reads the pack's own formula sources. No city, network, or build.
#
# run-tests-scope: tree
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BOUND=9000

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # tomllib_python only; the assertions below are this suite's own

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

if ! PY="$(tomllib_python)"; then
  echo "skip - formula step sizes: $PY"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-formula-step-size-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Prints one line per step: <rendered length> <tab> <formula>.<step id>.
cat > "$TMP/render.py" <<'PY'
import re, sys, tomllib

PLACEHOLDER = re.compile(r"\{\{([A-Za-z0-9_]+)\}\}")
BEAD_ID = "tk-xxxxxxxxx"

for path in sys.argv[1:]:
    with open(path, "rb") as f:
        formula = tomllib.load(f)
    defaults = {}
    for name, spec in (formula.get("vars") or {}).items():
        if isinstance(spec, dict) and spec.get("default") not in (None, ""):
            defaults[name] = str(spec["default"])
    for step in formula.get("steps") or []:
        description = PLACEHOLDER.sub(lambda m: defaults.get(m.group(1), m.group(0)),
                                      step.get("description", ""))
        reminder = ("<system-reminder>\nYour current active work assignment:\n\n"
                    f"## {step.get('title', '').strip()} ({BEAD_ID})\n\n"
                    f"{description.strip()}\n</system-reminder>\n")
        units = len(reminder.encode("utf-16-le")) // 2
        print(f"{units}\t{formula.get('formula', path)}.{step.get('id', '?')}")
PY

render() { "$PY" "$TMP/render.py" "$@"; }

# ── The renderer fires over the bound and stays silent at it ─────────────────
# A step whose reminder is BOUND+1 units fails and one of exactly BOUND passes,
# so a renderer that stopped counting cannot pass the real tree by accident.
fixture() {
  local out="$1" units="$2"
  "$PY" - "$out" "$units" <<'PY'
import sys
out, target = sys.argv[1], int(sys.argv[2])
head = ("<system-reminder>\nYour current active work assignment:\n\n"
        "## Sized (tk-xxxxxxxxx)\n\n")
tail = "\n</system-reminder>\n"
body = "x" * (target - len(head) - len(tail))
with open(out, "w") as f:
    f.write('formula = "mol-fixture"\n[[steps]]\nid = "sized"\ntitle = "Sized"\n')
    f.write('description = """\n' + body + '\n"""\n')
PY
}
fixture "$TMP/over.toml" "$((BOUND + 1))"
fixture "$TMP/at.toml" "$BOUND"
over="$(render "$TMP/over.toml" | cut -f1)"
at="$(render "$TMP/at.toml" | cut -f1)"
[ "$over" = "$((BOUND + 1))" ] \
  && ok "renderer measures a step one unit over the bound at $over" \
  || bad "renderer measured the over-bound fixture at '$over', want $((BOUND + 1))"
[ "$at" = "$BOUND" ] \
  && ok "renderer measures a step at the bound at $at" \
  || bad "renderer measured the at-bound fixture at '$at', want $BOUND"

# A default substitutes and an undeclared var keeps its placeholder.
cat > "$TMP/vars.toml" <<'TOML'
formula = "mol-vars"
[vars.long]
default = "0123456789"
[vars.empty]
default = ""
[[steps]]
id = "v"
title = "V"
description = "{{long}}{{empty}}{{missing}}"
TOML
vars_units="$(render "$TMP/vars.toml" | cut -f1)"
vars_want="$("$PY" -c '
head = "<system-reminder>\nYour current active work assignment:\n\n## V (tk-xxxxxxxxx)\n\n"
print(len(head + "0123456789{{empty}}{{missing}}" + "\n</system-reminder>\n"))')"
[ "$vars_units" = "$vars_want" ] \
  && ok "a declared default substitutes and an empty or undeclared var keeps its placeholder" \
  || bad "var render measured '$vars_units', want $vars_want"

# ── Every pack formula step fits ─────────────────────────────────────────────
formulas=()
for f in "$ROOT"/formulas/*.toml "$ROOT"/packs/*/formulas/*.toml; do
  [ -e "$f" ] && formulas+=("$f")
done
[ "${#formulas[@]}" -gt 0 ] || { echo "no formulas found under $ROOT" >&2; exit 2; }

render "${formulas[@]}" > "$TMP/sizes.tsv"
steps="$(wc -l < "$TMP/sizes.tsv" | tr -d ' ')"
[ "$steps" -gt 0 ] \
  && ok "rendered $steps steps across ${#formulas[@]} formulas" \
  || bad "rendered no steps from ${#formulas[@]} formulas"

over_count=0
while IFS=$'\t' read -r units step; do
  if [ "$units" -gt "$BOUND" ]; then
    over_count=$((over_count + 1))
    bad "$step renders $units characters, over the $BOUND bound"
  fi
done < "$TMP/sizes.tsv"
[ "$over_count" -eq 0 ] && ok "every step renders within $BOUND characters (largest: $(sort -rn "$TMP/sizes.tsv" | head -1 | tr '\t' ' '))"

echo
echo "formula-step-size: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
