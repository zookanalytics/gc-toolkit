#!/usr/bin/env bash
# formula-step-size.test.sh — every formula step a hook delivers fits in it.
#
# gc gives an agent its current step as a step reminder, a <system-reminder>
# holding the step bead's title and its whole description
# (formatWispStepReminder in gascity's cmd/gc/wisp_step_inject.go). Two hooks
# deliver it: `gc nudge drain --inject` on UserPromptSubmit and `gc prime
# --hook` on SessionStart. Claude Code keeps 10,000 characters of a hook's
# output and gives the agent a file path and a 2,000-character preview of a
# longer one. Codex keeps 10,000 bytes when the hook sets no
# additionalContextLimit, and gc's hooks set none (the hookLaneContextBudget
# comment in gascity's cmd/gc/conversation_lane_hook.go). So each step's
# reminder renders within BOUND bytes, which holds under both caps. The rest of
# the hook's output is left for what shares it: the drain's clock line and
# queued nudges, prime's opening line and unread mail, and any value a pour
# gives a var that runs longer than the placeholder this render keeps.
#
# The test covers every formula under formulas/ and packs/*/formulas/ except
# one the pack pours only as a root-only wisp. The reminder is built from a
# step bead (resolveActiveWispStep in the same file), and `gc bd mol wisp
# --root-only` pours the root alone, so no hook delivers that formula's steps.
# A formula is left out when a line of the pack's tracked text pours it that way
# and no line pours it any other way: a `mol wisp` or `mol pour` without the
# flag, a sling's `--on`, or a `formula` key outside a formula file, such as an
# order's. The patrols are poured root-only. A step a formula takes from another
# pack through `extends`, such as mol-polecat-work's implement, is that pack's
# text and is not read here.
#
# The render is what a pour writes and the reminder wraps. Each {{var}} in the
# title and the description takes the formula's own non-empty default and keeps
# its placeholder otherwise, as a pour keeps a var it cannot resolve. Both are
# trimmed and lose any <system-reminder> tag, as promptsafe's
# SanitizeForSystemReminder strips them. The bead id is a stand-in a little
# longer than a step bead's id.
#
# Hermetic: reads the tracked files of the pack and of the fixture trees it
# builds. No city, network or build.
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
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

if ! PY="$(tomllib_python)"; then
  echo "skip - formula step sizes: $PY"
  exit 0
fi
command -v git >/dev/null 2>&1 || { echo "git is required for this test" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-formula-step-size-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/steps.py" <<'PY'
"""steps.py steps|root-only <root>

steps      one line per step a hook delivers: <bytes> TAB <formula>.<step id>
root-only  one line per formula left out because the pack pours it root-only

<root> is a git work tree, and only its tracked files are read.
"""
import os
import re
import subprocess
import sys
import tomllib

BEAD_ID = "tk-xxxxxxxxx"
VAR = re.compile(r"\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}")
FORMULA_FILE = re.compile(r"^(?:packs/[^/]+/)?formulas/[^/]+\.toml$")
POUR = re.compile(r"(\bmol (?:wisp|pour) |--on[= ]|--formula[= ]|--sling-arg )[\"']?(mol-[A-Za-z0-9_-]+)")
FORMULA_KEY = re.compile(r"^\s*formula\s*=\s*\"(mol-[A-Za-z0-9_-]+)\"")
NOT_PACK_TEXT = re.compile(r"^(?:docs|specs|generated)/|\.test\.sh$|_test\.go$|/testdata/")


def tracked(root):
    out = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                         check=True, capture_output=True).stdout
    return sorted(path for path in out.decode().split("\0") if path)


def sanitize(text):
    while True:
        stripped = text.replace("</system-reminder>", "").replace("<system-reminder>", "")
        if stripped == text:
            return text
        text = stripped


def root_only(root, files):
    pours = {}
    for rel in files:
        if NOT_PACK_TEXT.search(rel):
            continue
        try:
            with open(os.path.join(root, rel), encoding="utf-8") as f:
                lines = f.read().splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        config = rel.endswith(".toml") and not FORMULA_FILE.match(rel)
        for line in lines:
            for m in POUR.finditer(line):
                rooted = m.group(1).startswith("mol wisp") and "--root-only" in line
                pours.setdefault(m.group(2), []).append(rooted)
            m = FORMULA_KEY.match(line)
            if m and config:
                pours.setdefault(m.group(1), []).append(False)
    return {name for name, rooted in pours.items() if all(rooted)}


def steps(root, files):
    left_out = root_only(root, files)
    for rel in files:
        if not FORMULA_FILE.match(rel):
            continue
        with open(os.path.join(root, rel), "rb") as f:
            formula = tomllib.load(f)
        name = formula.get("formula", rel)
        if name in left_out:
            continue
        defaults = {var: str(spec["default"]) for var, spec in (formula.get("vars") or {}).items()
                    if isinstance(spec, dict) and spec.get("default") not in (None, "")}
        render = lambda text: VAR.sub(lambda m: defaults.get(m.group(1), m.group(0)), text)
        for step in formula.get("steps") or []:
            title = sanitize(render(step.get("title", "")).strip())
            description = sanitize(render(step.get("description", "")).strip())
            reminder = ("<system-reminder>\nYour current active work assignment:\n\n"
                        f"## {title} ({BEAD_ID})\n\n{description}\n</system-reminder>\n")
            print(f"{len(reminder.encode('utf-8'))}\t{name}.{step.get('id', '?')}")


mode, root = sys.argv[1], sys.argv[2]
files = tracked(root)
if mode == "root-only":
    print("\n".join(sorted(root_only(root, files))))
else:
    steps(root, files)
PY

steps()     { "$PY" "$TMP/steps.py" steps "$1"; }
root_only() { "$PY" "$TMP/steps.py" root-only "$1"; }

# over <sizes file> — each step of a `steps` listing that renders past BOUND.
over() { awk -F'\t' -v bound="$BOUND" '$1 > bound { print $2 " renders " $1 " bytes" }' "$1"; }

# track <dir> — make <dir> a git work tree whose files are all tracked.
track() { git -C "$1" init -q && git -C "$1" add -A; }

# sized <file> <formula> <bytes> [ascii] — a formula of one step whose reminder
# renders exactly <bytes> bytes. Every tenth character is an em dash, three
# bytes long, so the step has fewer characters than bytes, unless the last
# argument asks for ASCII alone.
sized() {
  "$PY" - "$@" <<'PY'
import sys
path, name, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
ascii_only = len(sys.argv) > 4
head = "<system-reminder>\nYour current active work assignment:\n\n## Sized (tk-xxxxxxxxx)\n\n"
tail = "\n</system-reminder>\n"
room = target - len(head.encode()) - len(tail.encode())
body = "" if ascii_only else ("—" + "x" * 9) * (room // 12)
body += "x" * (room - len(body.encode()))
with open(path, "w", encoding="utf-8") as f:
    f.write(f'formula = "{name}"\n\n[[steps]]\nid = "sized"\ntitle = "Sized"\n')
    f.write("description = '''\n" + body + "\n'''\n")
PY
}

# ── A step fails one byte over the bound and passes at it ────────────────────
# The judgment below is the one the pack's own steps get, so a renderer that
# stopped counting, or counted characters, cannot pass the real tree by accident.
mkdir -p "$TMP/edge/formulas"
sized "$TMP/edge/formulas/mol-at-ascii.toml" mol-at-ascii "$BOUND" ascii
sized "$TMP/edge/formulas/mol-at-dash.toml" mol-at-dash "$BOUND"
sized "$TMP/edge/formulas/mol-over-ascii.toml" mol-over-ascii "$((BOUND + 1))" ascii
sized "$TMP/edge/formulas/mol-over-dash.toml" mol-over-dash "$((BOUND + 1))"
track "$TMP/edge"
steps "$TMP/edge" > "$TMP/edge.tsv"
eq "$(awk -F'\t' '$2 ~ /^mol-at-/ { print $1 }' "$TMP/edge.tsv" | sort -u)" "$BOUND" \
  "the render measures each at-bound fixture at $BOUND bytes"
eq "$(over "$TMP/edge.tsv" | awk '{ print $1 }' | tr '\n' ' ')" \
  "mol-over-ascii.sized mol-over-dash.sized " \
  "a step one byte over the bound fails, and a step at the bound passes"
dash_chars="$("$PY" -c 'import sys, tomllib; print(len(tomllib.load(open(sys.argv[1], "rb"))["steps"][0]["description"]))' "$TMP/edge/formulas/mol-over-dash.toml")"
[ "$dash_chars" -lt "$BOUND" ] \
  && ok "the bound counts bytes: the over-bound step with em dashes holds $dash_chars characters" \
  || bad "the em-dash fixture holds $dash_chars characters, so it does not tell bytes from characters"

# ── The render fills vars as a pour does and strips reminder tags ────────────
mkdir -p "$TMP/vars/formulas"
cat > "$TMP/vars/formulas/mol-vars.toml" <<'TOML'
formula = "mol-vars"

[vars.long]
default = "0123456789"

[vars.empty]
default = ""

[[steps]]
id = "v"
title = "  V {{long}}  "
description = "<system-reminder>{{long}}{{empty}}{{missing}}</system-</system-reminder>reminder>"
TOML
track "$TMP/vars"
want="$("$PY" -c '
r = ("<system-reminder>\nYour current active work assignment:\n\n## V 0123456789 (tk-xxxxxxxxx)\n\n"
     "0123456789{{empty}}{{missing}}\n</system-reminder>\n")
print(len(r.encode()))')"
eq "$(steps "$TMP/vars" | cut -f1)" "$want" \
  "a default fills its var in the title and the description, an empty or undeclared var keeps its placeholder, and every reminder tag is stripped"

# ── A formula the pack pours only as a root-only wisp is left out ────────────
mkdir -p "$TMP/patrol/formulas" "$TMP/patrol/agents/fx" "$TMP/patrol/docs"
sized "$TMP/patrol/formulas/mol-fx-patrol.toml" mol-fx-patrol "$((BOUND + 1))"
sized "$TMP/patrol/formulas/mol-fx-work.toml" mol-fx-work 100
printf '%s\n' 'WISP=$(gc bd mol wisp mol-fx-patrol --root-only --json | jq -r .new_epic_id)' \
  > "$TMP/patrol/agents/fx/prompt.template.md"
printf '%s\n' 'A page may say `gc sling pool bead --on mol-fx-patrol`; a page pours nothing.' \
  > "$TMP/patrol/docs/fx.md"
track "$TMP/patrol"
eq "$(root_only "$TMP/patrol")" "mol-fx-patrol" "a formula poured only as a root-only wisp is left out"
steps "$TMP/patrol" > "$TMP/patrol.tsv"
eq "$(cut -f2 "$TMP/patrol.tsv")" "mol-fx-work.sized" \
  "…its steps are not measured, and a formula with no pour in the pack's text is"

check_pour() { # <label> <file> <line> — the pour on <line> brings mol-fx-patrol back in
  rm -rf "$TMP/repour" && cp -R "$TMP/patrol" "$TMP/repour" && rm -rf "$TMP/repour/.git"
  mkdir -p "$TMP/repour/$(dirname "$2")"
  printf '%s\n' "$3" >> "$TMP/repour/$2"
  track "$TMP/repour"
  steps "$TMP/repour" > "$TMP/repour.tsv"
  eq "$(over "$TMP/repour.tsv" | awk '{ print $1 }')" "mol-fx-patrol.sized" "$1"
}
check_pour "a pour without --root-only measures the formula's steps" \
  agents/fx/prompt.template.md 'gc bd mol wisp mol-fx-patrol --json'
check_pour "a sling's --on measures the formula's steps" \
  skills/fx/SKILL.md 'gc sling <pool> <bead> --on mol-fx-patrol'
check_pour "an order's formula key measures the formula's steps" \
  orders/fx.toml 'formula = "mol-fx-patrol"'

# ── Every step the pack's hooks deliver fits ────────────────────────────────
if steps "$ROOT" > "$TMP/sizes.tsv"; then
  ok "rendered $(wc -l < "$TMP/sizes.tsv" | tr -d ' ') steps the pack's hooks deliver"
else
  bad "the render of the pack's formulas failed"
fi
left_out="$(root_only "$ROOT" | paste -sd ' ' -)"
ok "left out, poured only as root-only wisps: ${left_out:-none}"
oversize="$(over "$TMP/sizes.tsv")"
if [ -z "$oversize" ]; then
  ok "every step renders within $BOUND bytes (largest: $(sort -rn "$TMP/sizes.tsv" | head -1 | tr '\t' ' '))"
else
  while IFS= read -r line; do
    bad "$line, over the $BOUND-byte bound: keep its instructions inline, and move its reference prose into the doc it points to or its mechanics into a tested script (docs/pack-authoring.md, Step text calls a tested script)"
  done <<< "$oversize"
fi

echo
echo "formula-step-size: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
