#!/usr/bin/env bash
# Hermetic test for mol-validate-close's ask (the validate-close-ask block).
#
# A first reaction proposed closing the subject and validation did not confirm
# it, so the step asks the operator. The ask is a human gate on the subject under
# the key validate-close, which holds the bead until the operator answers. A
# bead with an open child is asked through a conversation instead, because a
# gate on the parent would pause the child's work, the very work the doubt is
# about. A children read that fails or does not parse files the gate, the
# ordinary ask. The block is extracted verbatim from the formula and run against
# a fake `gc` and stub scripts, in the shells an agent may run it in. No live
# city, Dolt or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-validate-close.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-mol-validate-close-ask-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

BLOCK="$(awk '
  /# >>> validate-close-ask$/ {f=1; next}
  /# <<< validate-close-ask$/ {f=0}
  f' "$TOML")"
[ -n "$BLOCK" ] && ok "validate-close-ask block extracted" || bad "validate-close-ask block extraction EMPTY"

# gc: `bd list` logs its argv and answers $FAKE_CHILDREN, or fails with
# $FAKE_LIST_RC and prints nothing, the way a failed listing does. human-gate.sh
# and gc-helm.sh record their verb in the ordered log and their argv where the
# assertions read it, and exit with a code the case controls.
mkdir -p "$TMP/bin" "$TMP/pack"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "bd list")
    printf '%s\n' "$*" >> "$FAKE_ARGS/list"
    [ "${FAKE_LIST_RC:-0}" = 0 ] || exit "$FAKE_LIST_RC"
    printf '%s\n' "${FAKE_CHILDREN:-[]}"
    exit 0 ;;
esac
echo "unexpected gc invocation: $*" >&2; exit 99
GC
for v in human-gate:GATE gc-helm:CONVERSE; do
  name="${v%%:*}"; verb="${v#*:}"
  { printf '#!%s\n' "${BASH:-/usr/bin/env bash}"
    printf 'printf %s >> "$FAKE_LOG"\n' "'$verb\\n'"
    printf 'printf %s "$*" >> "$FAKE_ARGS/%s"\n' "'%s\\n'" "$name"
    printf 'exit "${FAKE_%s_RC:-0}"\n' "$verb"; } > "$TMP/pack/$name.sh"
done
chmod +x "$TMP/bin/gc" "$TMP/pack/"*.sh
mkdir -p "$TMP/args"

# run [shell-prelude] [VAR=value...] -> "<rc>|<ordered verb log>". The step's
# lines above the block set WORK_BEAD_ID and SCRIPTS, so the run sets them too.
run() {
  local prelude="${1:-}"; shift || true
  : > "$TMP/log"; rm -f "$TMP/args"/*
  { printf '%s\n' "$prelude"; printf '%s\n' "$BLOCK"; } > "$TMP/run.sh"
  local rc=0
  env PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" FAKE_ARGS="$TMP/args" \
    WORK_BEAD_ID=tk-sub SCRIPTS="$TMP/pack" "$@" bash "$TMP/run.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}
args() { cat "$TMP/args/$1" 2>/dev/null || true; }

OPEN_CHILD='[{"id":"tk-sub.1","status":"open","issue_type":"task"}]'

for PRELUDE in '' 'set -e' 'set -euo pipefail'; do
  L="${PRELUDE:-plain shell}"

  # No open child: the gate holds the bead until the operator answers.
  eq "$(run "$PRELUDE")" "0|GATE;" "$L: a bead with no open child is asked through a human gate"
  has "$(args human-gate)" "--subject tk-sub --key validate-close --message Proposed close of tk-sub did not validate: accept or redirect." \
     "$L: the gate blocks the subject under validate-close, titled with the ask"
  has "$(args human-gate)" "A first reaction proposed closing tk-sub; validation did not confirm it." \
     "$L: the gate's description carries the ask"
  hasnt "$(args human-gate)" "--quiet-window" "$L: the ask is an event of this run, so it declares no quiet window"
  eq "$(args gc-helm)" "" "$L: no conversation is opened beside the gate"
  has "$(args list)" "--parent tk-sub" "$L: the children are read under the subject"
  has "$(args list)" "--include-gates --include-infra --include-templates" \
     "$L: the read counts a gate, an infra bead and a template among the children"
  has "$(args list)" "--json --limit 1" "$L: one child is enough to answer"

  # An open child: a gate on the parent would pause the child, so the ask is a
  # conversation on the bead, which holds nothing.
  eq "$(run "$PRELUDE" FAKE_CHILDREN="$OPEN_CHILD")" "0|CONVERSE;" \
     "$L: a bead with an open child is asked through a conversation"
  has "$(args gc-helm)" "open tk-sub --reason proposed close did not validate: accept or redirect --body A first reaction proposed closing tk-sub;" \
     "$L: the conversation is opened on the subject with the ask as its brief"
  eq "$(args human-gate)" "" "$L: no gate is filed on the parent"

  # A raw control byte in a child's row is stripped before the parse, so the
  # child still counts.
  eq "$(run "$PRELUDE" FAKE_CHILDREN='[{"id":"tk-sub.1","title":"a'"$(printf '\001')"'b"}]')" "0|CONVERSE;" \
     "$L: a raw control byte in a child's row does not hide the child"

  # A read that fails or does not parse files the gate, the ordinary ask.
  eq "$(run "$PRELUDE" FAKE_LIST_RC=1)" "0|GATE;" "$L: a children read that fails files the gate"
  eq "$(run "$PRELUDE" FAKE_CHILDREN='{"error":"store unavailable"}')" "0|GATE;" \
     "$L: a children read that is not an array files the gate"
  eq "$(run "$PRELUDE" FAKE_CHILDREN='null')" "0|GATE;" "$L: a null children read files the gate"

  # A filer that did not land stops the step loudly, so it is never closed over
  # an ask nobody filed.
  eq "$(run "$PRELUDE" FAKE_GATE_RC=1)" "1|GATE;" "$L: a gate that was not filed stops the step"
  has "$(cat "$TMP/out")" "human-gate.sh filed no gate on tk-sub" "$L: and says so"
  eq "$(run "$PRELUDE" FAKE_CHILDREN="$OPEN_CHILD" FAKE_CONVERSE_RC=1)" "1|CONVERSE;" \
     "$L: a conversation that was not opened stops the step"
  has "$(cat "$TMP/out")" "no conversation was opened on tk-sub" "$L: and says so"
done

echo
echo "mol-validate-close-ask: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
