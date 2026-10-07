#!/usr/bin/env bash
# Hermetic test: a patrol chain carries only the vars its startup pour chose.
#
# Each patrol (witness, deacon, refinery) is a chain of --root-only wisps. The
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
#       is carried; a var it leaves to the formula default is not.
#   (C) CHAIN. A refinery chain started under one check_set and
#       default_merge_strategy default renders the new defaults on its next
#       wisp once the formula defaults change, and the merge-push stamp
#       (`check-set-normalize`) stamps the new check_set. A witness chain does
#       the same for event_timeout. Every var the next-iteration pour names is
#       read off the current wisp's rendered root, the surface the agent
#       substitutes from. A CONTROL puts the forwarded vars back and shows the
#       chain keeping the old values.
#
# No live city, Dolt or network. A stub `gc` renders each wisp the way bd
# renders a --root-only wisp: the formula's top-level description, with each
# declared var's {{name}} replaced by the value passed, or by the declared
# default read from the formula file at that pour. bd accepts and ignores an
# undeclared var, and so does the stub.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-patrol-pour-vars-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for this test" >&2; exit 1; }

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
  python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["description"])' "$1"
}

# declared_vars <toml> — the formula's declared var names, one per line.
declared_vars() {
  python3 -c 'import sys, tomllib; print("\n".join(tomllib.load(open(sys.argv[1], "rb")).get("vars", {})))' "$1"
}

# pour_line <title> — the lines of stdin that pour <title>.
pour_line() { grep -F "gc bd mol wisp $1 " || true; }

# var_names — the var names the pour lines on stdin pass, sorted, one line.
var_names() {
  { grep -oE -- '--var [A-Za-z_][A-Za-z0-9_]*=' || true; } \
    | sed 's/^--var //; s/=$//' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# set_default <toml> <var> <value> — rewrite [vars.<var>] default in place.
set_default() {
  python3 - "$@" <<'PY'
import re, sys
path, var, value = sys.argv[1:4]
with open(path, encoding="utf-8") as f:
    text = f.read()
section = re.compile(r'(^\[vars\.' + re.escape(var) + r'\]\n(?:(?!\[).*\n)*?default = )"[^"\n]*"', re.M)
text, n = section.subn(lambda m: m.group(1) + '"' + value + '"', text, count=1)
if n != 1:
    sys.exit("set_default: no [vars.%s] default in %s" % (var, path))
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
}

# --- Stub `gc` and the wisp renderer. ---------------------------------------
mkdir -p "$TMP/bin" "$TMP/store" "$TMP/formulas"
cat > "$TMP/render.py" <<'PY'
import sys, tomllib
path, *pairs = sys.argv[1:]
with open(path, "rb") as f:
    doc = tomllib.load(f)
values = {name: str(spec.get("default", "")) for name, spec in doc.get("vars", {}).items()}
for pair in pairs:
    name, _, value = pair.partition("=")
    if name in values:
        values[name] = value
text = doc["description"]
for name, value in values.items():
    text = text.replace("{{" + name + "}}", value)
sys.stdout.write(text)
PY
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
# Stand-in for the gc calls a patrol pour makes. `bd mol wisp` renders the
# wisp's root from the formula file under $STUB_FORMULAS as it stands at this
# call, stores it as $STUB_STORE/w<n>.root and prints the new id. Every other
# call (update, burn, drain-ack) succeeds and is only logged.
set -u
printf '%s\n' "$*" >> "$STUB_STORE/calls.log"
if [ "${1:-}" = bd ] && [ "${2:-}" = mol ] && [ "${3:-}" = wisp ]; then
  shift 3
  formula="${1:?formula}"; shift
  vars=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --var)   vars+=("${2:-}"); shift 2 ;;
      --var=*) vars+=("${1#--var=}"); shift ;;
      *)       shift ;;
    esac
  done
  n=$(( $(cat "$STUB_STORE/seq" 2>/dev/null || echo 0) + 1 ))
  printf '%s\n' "$n" > "$STUB_STORE/seq"
  python3 "$STUB_RENDER" "$STUB_FORMULAS/$formula.toml" ${vars[@]+"${vars[@]}"} > "$STUB_STORE/w$n.root" || exit 1
  printf '{"new_epic_id":"w%s"}\n' "$n"
fi
exit 0
STUB
chmod +x "$TMP/bin/gc"

# run_sh <script> [<current-wisp>] — run an extracted block as the agent
# would, in a rig session with the stub on PATH, and print the newest wisp id.
run_sh() {
  ( cd "$TMP" && env PATH="$TMP/bin:$PATH" STUB_STORE="$TMP/store" \
      STUB_FORMULAS="$TMP/formulas" STUB_RENDER="$TMP/render.py" \
      GC_BEAD_ID="${2:-}" GC_AGENT="rig-a/gc-toolkit.patrol" GC_RIG="rig-a" \
      bash "$1" >/dev/null 2>&1 ) || true
  printf 'w%s\n' "$(cat "$TMP/store/seq" 2>/dev/null || echo 0)"
}

# root_has <wisp> <var> — the wisp's rendered root gives <var> a value, either
# as `--var <var>=` on the pour line or as a `<var>=` line.
root_has() { grep -qE "(^|[[:space:]])$2=" "$TMP/store/$1.root"; }

# root_value <wisp> <var> — that value, as the agent reads it off the root.
root_value() {
  { grep -oE "(^|[[:space:]])$2='?[^'[:space:]]*" "$TMP/store/$1.root" || true; } \
    | head -1 | sed -E "s/^[[:space:]]*$2='?//"
}

# substitute <file> <wisp> <toml> — fill each declared {{var}} in <file> from
# <wisp>'s rendered root, in place. Prints every var the file names that the
# root does not render: a value the agent would have to guess.
substitute() {
  local body name val missing=""
  body="$(cat "$1")"
  while IFS= read -r name; do
    case "$body" in *"{{$name}}"*) ;; *) continue ;; esac
    if ! root_has "$2" "$name"; then missing="$missing $name"; continue; fi
    val="$(root_value "$2" "$name")"
    body="${body//"{{$name}}"/"$val"}"
  done < <(declared_vars "$3")
  printf '%s\n' "$body" > "$1"
  printf '%s' "${missing# }"
}

# --- (P) Parity of the three pour sites. ------------------------------------
for AGENT in witness deacon refinery; do
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
done

# --- (C) A chain picks up a changed default on its next wisp. ---------------
# chain <agent> <var=old=new>... — start a chain under the old defaults with
# the prompt's startup pour, change the formula defaults to the new values,
# then pour the next wisp with the live formula's next-iteration block,
# substituted from the first wisp's root. Leaves FIRST and NEXT set.
chain() {
  local agent="$1"; shift
  local title="mol-$agent-patrol" spec var old new
  local live="$TMP/formulas/$title.toml"
  cp "$ROOT/formulas/$title.toml" "$live"
  for spec in "$@"; do
    IFS='=' read -r var old new <<< "$spec"
    set_default "$live" "$var" "$old"
  done

  pour_line "$title" < "$ROOT/agents/$agent/prompt.template.md" \
    | sed -e 's/{{ \.DefaultBranch }}/main/g' -e 's/{{ \.RigName }}/rig-a/g' \
          -e 's/{{ \.BindingPrefix }}/gc-toolkit./g' > "$TMP/startup.sh"
  if grep -q '{{' "$TMP/startup.sh"; then
    bad "$agent: the startup pour names a prompt var this test does not render: $(grep -o '{{[^}]*}}' "$TMP/startup.sh" | sort -u | tr '\n' ' ')"
  fi
  FIRST="$(run_sh "$TMP/startup.sh")"
  [ -s "$TMP/store/$FIRST.root" ] && ok "$agent: the startup pour minted the first wisp" \
    || bad "$agent: the startup pour minted nothing"
  for spec in "$@"; do
    IFS='=' read -r var old new <<< "$spec"
    eq "$(root_value "$FIRST" "$var")" "$old" "$agent: the chain starts under $var=$old"
    set_default "$live" "$var" "$new"
  done

  extract patrol-wisp-pour "$live" > "$TMP/next.sh"
  eq "$(substitute "$TMP/next.sh" "$FIRST" "$live")" "" \
    "$agent: every var the next-iteration pour names is rendered on the current wisp's root"
  grep -q '{{' "$TMP/next.sh" && bad "$agent: placeholders survive substitution: $(grep -o '{{[^}]*}}' "$TMP/next.sh" | sort -u | tr '\n' ' ')"
  NEXT="$(run_sh "$TMP/next.sh" "$FIRST")"
  [ "$NEXT" != "$FIRST" ] && [ -s "$TMP/store/$NEXT.root" ] \
    && ok "$agent: the next-iteration pour minted the next wisp" \
    || bad "$agent: the next-iteration pour minted nothing"
}

echo
echo "== refinery: chain =="
chain refinery 'check_set=codex=correctness,triage,pm' 'default_merge_strategy=direct=pr'
eq "$(root_value "$NEXT" check_set)" "correctness,triage,pm" \
  "refinery: REGRESSION: the next wisp renders the changed check_set default"
eq "$(root_value "$NEXT" default_merge_strategy)" "pr" \
  "refinery: REGRESSION: the next wisp renders the changed default_merge_strategy default"

# The stamp reads the wisp's check_set through the line that precedes the
# normalize block; run that line and the block as the next wisp's merge-push.
LIVE="$TMP/formulas/mol-refinery-patrol.toml"
STAMP_SRC="$(awk '/# >>> check-set-normalize$/ {print prev; exit} {prev = $0}' "$LIVE")"
eq "$STAMP_SRC" 'CHECK_SET="{{check_set}}"' "refinery: the stamp reads the wisp's check_set var"
{ printf '%s\n' "$STAMP_SRC"; extract check-set-normalize "$LIVE"; printf '%s\n' 'printf "%s\n" "$CHECK_SET"'; } > "$TMP/stamp.sh"
substitute "$TMP/stamp.sh" "$NEXT" "$LIVE" >/dev/null
eq "$(bash "$TMP/stamp.sh")" "correctness,triage,pm" \
  "refinery: REGRESSION: the next wisp stamps the changed check_set on its anchors"

# CONTROL: put the policy vars back on the next-iteration pour. The chain then
# carries the first wisp's values past the default change.
sed '/gc bd mol wisp mol-refinery-patrol /s/ --json / --var default_merge_strategy={{default_merge_strategy}} --var check_set={{check_set}} --json /' \
  "$LIVE" > "$TMP/control.toml"
if cmp -s "$LIVE" "$TMP/control.toml"; then
  bad "refinery: control did not re-add the forwarded vars — the pour line changed shape, re-check the sed"
else
  extract patrol-wisp-pour "$TMP/control.toml" > "$TMP/control.sh"
  substitute "$TMP/control.sh" "$FIRST" "$LIVE" >/dev/null
  CONTROL="$(run_sh "$TMP/control.sh" "$FIRST")"
  eq "$(root_value "$CONTROL" check_set)" "codex" \
    "refinery: CONTROL: forwarding check_set keeps the first wisp's codex past the default change"
  eq "$(root_value "$CONTROL" default_merge_strategy)" "direct" \
    "refinery: CONTROL: forwarding default_merge_strategy keeps the first wisp's value"
fi

echo
echo "== witness: chain =="
chain witness 'event_timeout=600=300'
eq "$(root_value "$NEXT" event_timeout)" "300" \
  "witness: REGRESSION: the next wisp renders the changed event_timeout default"

LIVE="$TMP/formulas/mol-witness-patrol.toml"
sed "/gc bd mol wisp mol-witness-patrol /s/ --json / --var event_timeout='{{event_timeout}}' --json /" "$LIVE" > "$TMP/control.toml"
if cmp -s "$LIVE" "$TMP/control.toml"; then
  bad "witness: control did not re-add the forwarded var — the pour line changed shape, re-check the sed"
else
  extract patrol-wisp-pour "$TMP/control.toml" > "$TMP/control.sh"
  substitute "$TMP/control.sh" "$FIRST" "$LIVE" >/dev/null
  CONTROL="$(run_sh "$TMP/control.sh" "$FIRST")"
  eq "$(root_value "$CONTROL" event_timeout)" "600" \
    "witness: CONTROL: forwarding event_timeout keeps the first wisp's value past the default change"
fi

echo
echo "patrol-pour-vars: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
