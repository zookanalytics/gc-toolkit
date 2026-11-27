#!/usr/bin/env bash
# Hermetic test: a patrol chain carries only the vars its startup pour chose.
#
# The deacon's patrol is a chain of --root-only wisps. The
# agent prompt's startup pour mints the first wisp, and each wisp's
# next-iteration step pours the next. bd renders a var the pour omits as the
# formula's declared default read at that pour, and a var the pour passes as
# the value passed. So a var the next-iteration pour passes keeps the first
# wisp's value for the life of the chain, and a default changed on main never
# reaches it. A var it omits re-renders the current default on every wisp.
#
#   (P) PARITY. The next-iteration pour (`patrol-wisp-pour`) and the pour line
#       in the formula's root description pass exactly the vars the startup
#       pour passes. A var the startup pour sets is the chain's own choice and
#       is carried; a var it leaves to the formula default is not. The prompt's
#       step read passes the startup pour's vars with their values, so a step's
#       text renders as the wisp runs it.
#
# The refinery's next pour is refinery-patrol.sh's, and refinery-patrol.test.sh
# holds it to the startup pour's vars. This suite holds the refinery prompt's
# step read to them.
#
# No live city, Dolt or network: the suite reads the prompts and formulas as
# text.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-patrol-pour-vars-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # tomllib_python only; the assertions below are this suite's own
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
TOML_PY="$(tomllib_python)" \
  || { echo "skip - every check here renders a formula read with tomllib: $TOML_PY"; exit 0; }

# extract <marker> <file> — the lines between the markers, exclusive. Renamed
# or removed markers extract nothing, and the checks below then fail loudly.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$2"
}

# root_template <toml> — the formula's top-level description, the text bd
# renders into every wisp's root.
root_template() {
  "$TOML_PY" -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["description"])' "$1"
}

# declared_vars <toml> — the formula's declared var names, one per line.
declared_vars() {
  "$TOML_PY" -c 'import sys, tomllib; print("\n".join(tomllib.load(open(sys.argv[1], "rb")).get("vars", {})))' "$1"
}

# pour_line <title> — the lines of stdin that pour <title>.
pour_line() { grep -F "gc bd mol wisp $1 " || true; }

# read_line <title> — the lines of stdin that read <title>'s step text.
read_line() { grep -F "gc formula show $1 " || true; }

# var_args — the --var arguments on stdin's lines, each name with its value,
# sorted, one line.
var_args() {
  { grep -oE -- "--var [A-Za-z_][A-Za-z0-9_]*=('[^']*'|\{\{[^}]*\}\}|[^ ]*)" || true; } \
    | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# var_names — the var names the pour lines on stdin pass, sorted, one line.
var_names() {
  { grep -oE -- '--var [A-Za-z_][A-Za-z0-9_]*=' || true; } \
    | sed 's/^--var //; s/=$//' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# --- (P) Parity of the three pour sites. ------------------------------------
AGENT=deacon
TITLE="mol-$AGENT-patrol"
PROMPT="$ROOT/agents/$AGENT/prompt.template.md"
TOML="$ROOT/formulas/$TITLE.toml"
echo
echo "== $AGENT: pour parity =="

STARTUP="$(pour_line "$TITLE" < "$PROMPT")"
NEXT_POUR="$(extract patrol-wisp-pour "$TOML" | pour_line "$TITLE")"
ROOT_POUR="$(root_template "$TOML" | pour_line "$TITLE")"
eq "$(printf '%s\n' "$STARTUP" | grep -c .)" "1" "$AGENT: the prompt carries exactly one startup pour"
eq "$(printf '%s\n' "$NEXT_POUR" | grep -c .)" "1" "$AGENT: patrol-wisp-pour carries exactly one pour"
eq "$(printf '%s\n' "$ROOT_POUR" | grep -c .)" "1" "$AGENT: the root description shows exactly one pour"

S_VARS="$(printf '%s\n' "$STARTUP" | var_names)"
[ -n "$S_VARS" ] && ok "$AGENT: the startup pour passes vars ($S_VARS)" \
  || bad "$AGENT: no --var found on the startup pour — extraction broke"
eq "$(printf '%s\n' "$NEXT_POUR" | var_names)" "$S_VARS" \
  "$AGENT: the next-iteration pour passes exactly the startup pour's vars"
eq "$(printf '%s\n' "$ROOT_POUR" | var_names)" "$S_VARS" \
  "$AGENT: the root description shows the pour the startup pour runs"

READ="$(read_line "$TITLE" < "$PROMPT")"
eq "$(printf '%s\n' "$READ" | grep -c .)" "1" "$AGENT: the prompt carries exactly one step read"
eq "$(printf '%s\n' "$READ" | var_args)" "$(printf '%s\n' "$STARTUP" | var_args)" \
  "$AGENT: the step read passes the startup pour's vars and values"

# The parity checks leave the refinery out, since its next pour is
# refinery-patrol.sh's, but its prompt's step read still passes the startup
# pour's vars and values.
echo
echo "== refinery: step read =="
PROMPT="$ROOT/agents/refinery/prompt.template.md"
STARTUP="$(pour_line mol-refinery-patrol < "$PROMPT")"
READ="$(read_line mol-refinery-patrol < "$PROMPT")"
eq "$(printf '%s\n' "$STARTUP" | grep -c .)" "1" "refinery: the prompt carries exactly one startup pour"
eq "$(printf '%s\n' "$READ" | grep -c .)" "1" "refinery: the prompt carries exactly one step read"
eq "$(printf '%s\n' "$READ" | var_args)" "$(printf '%s\n' "$STARTUP" | var_args)" \
  "refinery: the step read passes the startup pour's vars and values"

echo
echo "patrol-pour-vars: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
