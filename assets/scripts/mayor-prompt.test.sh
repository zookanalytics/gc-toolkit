#!/usr/bin/env bash
# mayor-prompt.test.sh — the commands the mayor's prime gives it run as
# written, each in a fresh shell, since a variable one tool call sets does not
# reach the next.
#
#   1. Every pack script the prime calls is found in the call itself, by
#      "$(gc <binding> scripts-dir)/<script>".
#   2. The command that names the rig for a matter of the whole city prints
#      the rig whose checkout holds the pack, whatever key the city imports it
#      under: never the HQ or a rig that only shares the key's name, and
#      nothing for a copy gc fetched into a cache, where the mayor asks the
#      operator instead.
#
# Hermetic: reads the render the seed audit commits, and runs the command it
# extracts under a stub gc.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# The prompt and its render, named whole so that a change to either runs this
# suite (tools/run-tests.sh).
PROMPT="$ROOT/agents/mayor/prompt.template.md"
RENDER="$ROOT/generated/seed-audit/agents/mayor.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

[ -f "$PROMPT" ] && [ -f "$RENDER" ] || { echo "mayor-prompt: the prompt or its render is missing" >&2; exit 1; }

echo "── 1. each script call finds its script ──"
calls=$(grep -o -E '"[^"`]*/[A-Za-z0-9_-]+\.sh"' "$RENDER" || true)
[ -n "$calls" ] && ok "the prime calls pack scripts" \
  || bad "the prime calls pack scripts" "no quoted call to a .sh in $RENDER, so this suite reads nothing"
loose=$(printf '%s\n' "$calls" | grep -v -E '^"\$\(gc [A-Za-z0-9_.-]+ scripts-dir\)/[A-Za-z0-9_-]+\.sh"$' || true)
[ -z "$loose" ] && ok "every call resolves the scripts directory in the call itself" \
  || bad "every call resolves the scripts directory in the call itself" "$loose"

echo "── 2. a matter of the whole city goes to the rig that holds the pack ──"
# The render names the binding gc-toolkit, so the stub city holds a rig of that
# name that is not the pack's, beside the HQ and the rig whose checkout is.
RESOLVER=$(grep -E '^ *`gc rig list --json \| jq ' "$RENDER" | sed -E 's/^ *`//; s/`[.,]?$//')
if [ -z "$RESOLVER" ]; then
  bad "the prime gives the command that names the pack's rig" "no line in $RENDER starts with \`gc rig list --json | jq"
else
  ok "the prime gives the command that names the pack's rig"
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/mayor-prompt-test.XXXXXX")"
  trap 'rm -rf "${TMP:?}"' EXIT
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "rig list --json")
    printf '{"rigs":[{"name":"city","path":"%s","hq":true},{"name":"gc-toolkit","path":"%s/rigs/gc-toolkit","hq":false},{"name":"toolkit","path":"%s/rigs/toolkit","hq":false},{"name":"tool","path":"%s/rigs/tool","hq":false}]}\n' "$CITY" "$CITY" "$CITY" "$CITY" ;;
  *" scripts-dir") printf '%s\n' "$SCRIPTS" ;;
  *) echo "stub gc: unexpected: $*" >&2; exit 2 ;;
esac
STUB
  chmod +x "$TMP/bin/gc"
  resolve() { CITY="$TMP/city" SCRIPTS="$1" PATH="$TMP/bin:$PATH" bash -c "$RESOLVER" 2>&1; }
  got=$(resolve "$TMP/city/rigs/toolkit/assets/scripts")
  [ "$got" = "toolkit" ] && ok "a pack imported from a rig's checkout names that rig, not the HQ or the rig named for the key" \
    || bad "a pack imported from a rig's checkout names that rig, not the HQ or the rig named for the key" "printed: $got"
  got=$(resolve "$TMP/city/.gc/cache/packs/gc-toolkit/assets/scripts")
  [ -z "$got" ] && ok "a pack gc fetched into a cache names no rig" \
    || bad "a pack gc fetched into a cache names no rig" "printed: $got"
fi

printf '\nmayor-prompt: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
