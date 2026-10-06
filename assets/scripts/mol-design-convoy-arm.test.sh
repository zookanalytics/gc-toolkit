#!/usr/bin/env bash
# Hermetic test for mol-design-convoy's gate-shape resolution and its two arm
# steps.
#
# design-gated-resolve turns the design_gated var into exactly true or false.
# It reads the value case-insensitively and falls back to the design-gated
# default on anything it does not recognize, so a typo never drops the design
# gate. load-context and arm-implementation each carry a copy, and the copies
# must stay identical.
#
# arm-design-dispatch and arm-implementation-dispatch stamp gc.design_armed and
# gc.impl_armed. A resume skips an arm whose marker is set, so the marker may be
# stamped only after every setup write landed and read back. A parent-child link
# that is missing sends the child's PR to the default branch, and a missing
# blocks edge lets the deferred dispatch sling the implementation before the
# design is approved. Each case below breaks one write and checks that nothing
# downstream of it ran: no sling, no arm, and no marker.
#
# EXECUTES the real snippets extracted verbatim between the formula markers, so
# the test cannot drift from the shipped instruction. No live city or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-design-convoy.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-design-convoy-arm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# extract_copy <marker> <n>: the lines of the n-th marked copy (exclusive).
extract_copy() {
  awk -v m="$1" -v want="$2" '
    $0 ~ ("# >>> " m "$") {n++; f=(n == want); next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}
copies() { grep -c -- "# >>> $1\$" "$TOML" || true; }

# --- static pins ---------------------------------------------------------------

for m in design-gated-resolve arm-design-dispatch arm-implementation-dispatch; do
  BLOCK="$(extract_copy "$m" 1)"
  [ -n "$BLOCK" ] && ok "$m extracted between markers" \
    || bad "$m extraction EMPTY — markers missing from $TOML"
  # A TOML triple-quoted string eats a trailing backslash (line-ending escape)
  # and silently joins lines, so a shipped snippet must be backslash-free.
  case "$BLOCK" in
    *\\*) bad "$m contains a backslash — TOML escapes will mangle it" ;;
    *)    ok  "$m is backslash-free" ;;
  esac
done

eq "$(copies design-gated-resolve)" "2" "design-gated-resolve has two copies (load-context, arm-implementation)"
if [ "$(extract_copy design-gated-resolve 1)" = "$(extract_copy design-gated-resolve 2)" ]; then
  ok "the design-gated-resolve copies are identical"
else
  bad "the design-gated-resolve copies differ — load-context would report a shape arm-implementation does not act on"
fi

# Gate 1 binds through merge.sh's universal approval rule, so the formula stamps
# no check_set, and the retired codex lane appears nowhere.
if grep -qE -- '--set-metadata "?check_set' "$TOML"; then
  bad "the formula writes check_set — gate 1 needs no lane token under the universal approval rule"
else
  ok "the formula writes no check_set"
fi
if grep -qi 'codex' "$TOML"; then
  bad "the formula names the retired codex lane"
else
  ok "the formula does not name the retired codex lane"
fi
# The object-or-array alternative crashes jq on a refused create instead of
# reporting bd's reason.
if grep -qE '\.id[[:space:]]*//[[:space:]]*\.\[0\]\.id|\.\[0\]\.id[[:space:]]*//[[:space:]]*\.id([^[:alnum:]_]|$)' "$TOML"; then
  bad "the formula reads a bd answer's id as an object-or-array alternative"
else
  ok "the formula reads bd answers' ids type-guarded"
fi

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=(zsh)
else
  echo "note - zsh not present; executing under bash only"
fi

# --- design-gated-resolve --------------------------------------------------------

RESOLVE="$(extract_copy design-gated-resolve 1)"

# resolve <shell> <value>: the block with {{design_gated}} replaced by <value>
# the way the formula engine substitutes it. Prints the resolved value; stderr
# goes to $TMP/resolve.err.
resolve() {
  local sh="$1" val="$2"
  {
    printf '%s\n' "${RESOLVE//\{\{design_gated\}\}/$val}"
    printf 'printf "%%s\\n" "$DESIGN_GATED"\n'
  } > "$TMP/resolve.sh"
  "$sh" "$TMP/resolve.sh" 2> "$TMP/resolve.err"
}

for sh in "${SHELLS[@]}"; do
  for v in true True TRUE 1 yes On " true "; do
    eq "$(resolve "$sh" "$v")" "true" "[$sh] design_gated='$v' resolves to true"
  done
  for v in false False FALSE 0 no off " Off "; do
    eq "$(resolve "$sh" "$v")" "false" "[$sh] design_gated='$v' resolves to false"
  done
  eq "$(resolve "$sh" "")" "true" "[$sh] an empty design_gated falls back to true"
  grep -q 'not a recognized boolean' "$TMP/resolve.err" \
    && ok "[$sh] an empty design_gated is reported" \
    || bad "[$sh] an empty design_gated fell back silently"
  eq "$(resolve "$sh" "flase")" "true" "[$sh] a misspelled design_gated falls back to true"
  grep -q "design_gated='flase'" "$TMP/resolve.err" \
    && ok "[$sh] the misspelled value is named in the warning" \
    || bad "[$sh] the misspelled value is not named in the warning"
  eq "$(resolve "$sh" "{{design_gated}}")" "true" "[$sh] an unsubstituted placeholder falls back to true"
  resolve "$sh" "false" >/dev/null
  [ -s "$TMP/resolve.err" ] && bad "[$sh] a recognized value printed a warning" \
    || ok "[$sh] a recognized value prints no warning"
done

# --- stubs for the arm blocks ------------------------------------------------------
# The gc stub logs every call, one line each, and answers by env:
#   DEP_ADD_PARENT_RC / DEP_ADD_BLOCKS_RC  exit of `gc bd dep add ... --type=<t>`
#   LIST_PARENT / LIST_BLOCKS              JSON `gc bd dep list ... -t <t> --json` prints
#   SLING_RC, UPDATE_RC                    exit of `gc sling` / `gc bd update`
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GC_LOG"
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "dep" ] && [ "${3:-}" = "add" ]; then
  case "${6:-}" in
    --type=parent-child) exit "${DEP_ADD_PARENT_RC:-0}" ;;
    --type=blocks)       exit "${DEP_ADD_BLOCKS_RC:-0}" ;;
  esac
  exit 0
fi
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "dep" ] && [ "${3:-}" = "list" ]; then
  t=""; prev=""
  for a in "$@"; do [ "$prev" = "-t" ] && t="$a"; prev="$a"; done
  case "$t" in
    parent-child) printf '%s\n' "${LIST_PARENT:-[]}" ;;
    blocks)       printf '%s\n' "${LIST_BLOCKS:-[]}" ;;
    *)            printf '[]\n' ;;
  esac
  exit 0
fi
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "update" ]; then exit "${UPDATE_RC:-0}"; fi
if [ "${1:-}" = "sling" ]; then exit "${SLING_RC:-0}"; fi
exit 0
STUB
cat > "$TMP/bin/deferred-dispatch.sh" <<'STUB'
#!/usr/bin/env bash
printf 'deferred-dispatch %s\n' "$*" >> "$GC_LOG"
exit "${ARM_RC:-0}"
STUB
chmod +x "$TMP/bin/gc" "$TMP/bin/deferred-dispatch.sh"

PARENT_OK='[{"id":"cv-1","dependency_type":"parent-child","status":"open"}]'
PARENT_OTHER='[{"id":"cv-9","dependency_type":"parent-child","status":"open"}]'
BLOCKS_OK='[{"id":"dz-design","dependency_type":"blocks","status":"open"}]'

# run_arm <marker> <shell>: runs the block with the step's variables in the
# environment and the stubs first on PATH. Sets RC; the call log is $GC_LOG. A
# sentinel after the block records whether execution ran past it: the step's
# contract is that a failed write stops it, not merely that the block's last
# command happened to fail.
run_arm() {
  local m="$1" sh="$2"
  { extract_copy "$m" 1; printf 'printf "past\\n" > "%s"\n' "$TMP/past.flag"; } > "$TMP/arm.sh"
  : > "$TMP/gc.log"; rm -f "$TMP/past.flag"
  RC=0
  PATH="$TMP/bin:$PATH" GC_LOG="$TMP/gc.log" SCRIPTS="$TMP/bin" \
    SUBJECT="sub-1" CONVOY_ID="cv-1" POOL="rig/gc-toolkit.polecat" \
    DESIGN_CHILD="dz-design" IMPL_CHILD="dz-impl" \
    "$sh" "$TMP/arm.sh" >/dev/null 2>"$TMP/arm.err" || RC=$?
}
logged()     { grep -qF -- "$1" "$TMP/gc.log"; }
not_logged() { ! grep -qF -- "$1" "$TMP/gc.log"; }
stopped()    { [ "$RC" -ne 0 ] && [ ! -e "$TMP/past.flag" ]; }

for sh in "${SHELLS[@]}"; do
  # --- arm-design-dispatch ---
  export ARMED="" DEP_ADD_PARENT_RC=0 LIST_PARENT="$PARENT_OK" SLING_RC=0 UPDATE_RC=0
  run_arm arm-design-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-design: a linked, read-back child is slung and the step succeeds"
  logged "sling rig/gc-toolkit.polecat dz-design --on mol-polecat-work" \
    && ok "[$sh] arm-design: the design child is slung" || bad "[$sh] arm-design: no sling"
  logged "gc.design_armed=1" && ok "[$sh] arm-design: gc.design_armed is stamped" \
    || bad "[$sh] arm-design: gc.design_armed not stamped"
  logged "bd dep add dz-design cv-1 --type=parent-child" \
    && ok "[$sh] arm-design: links the design child under the convoy" \
    || bad "[$sh] arm-design: no parent-child link under the convoy"

  export DEP_ADD_PARENT_RC=1
  run_arm arm-design-dispatch "$sh"
  stopped && ok "[$sh] arm-design: a failed link fails the step" \
    || bad "[$sh] arm-design: a failed link passed"
  not_logged "sling " && not_logged "gc.design_armed" \
    && ok "[$sh] arm-design: a failed link neither slings nor stamps" \
    || bad "[$sh] arm-design: a failed link still slung or stamped"

  export DEP_ADD_PARENT_RC=0 LIST_PARENT='[]'
  run_arm arm-design-dispatch "$sh"
  stopped && not_logged "sling " && not_logged "gc.design_armed" \
    && ok "[$sh] arm-design: a link that exits 0 but does not read back stops before the sling" \
    || bad "[$sh] arm-design: an unread link was trusted (rc=$RC)"

  export LIST_PARENT="$PARENT_OTHER"
  run_arm arm-design-dispatch "$sh"
  stopped && not_logged "sling " \
    && ok "[$sh] arm-design: a parent edge to another convoy does not count" \
    || bad "[$sh] arm-design: an edge to another convoy was accepted"

  export LIST_PARENT="$PARENT_OK" UPDATE_RC=1
  run_arm arm-design-dispatch "$sh"
  stopped && ok "[$sh] arm-design: a marker that does not record fails the step" \
    || bad "[$sh] arm-design: an unrecorded marker passed"

  export UPDATE_RC=0 ARMED=1
  run_arm arm-design-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-design: an armed subject is a no-op"
  [ -s "$TMP/gc.log" ] && bad "[$sh] arm-design: an armed subject still wrote" \
    || ok "[$sh] arm-design: an armed subject writes nothing"

  # --- arm-implementation-dispatch, design-gated ---
  export ARMED="" DESIGN_GATED=true DEP_ADD_PARENT_RC=0 DEP_ADD_BLOCKS_RC=0 \
    LIST_PARENT="$PARENT_OK" LIST_BLOCKS="$BLOCKS_OK" ARM_RC=0 SLING_RC=0 UPDATE_RC=0
  run_arm arm-implementation-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-impl gated: verified edges arm the deferred dispatch"
  logged "bd dep add dz-impl dz-design --type=blocks" \
    && ok "[$sh] arm-impl gated: the design child blocks the implementation (operand order)" \
    || bad "[$sh] arm-impl gated: blocks edge missing or reversed"
  logged "deferred-dispatch arm dz-impl --target rig/gc-toolkit.polecat" \
    && ok "[$sh] arm-impl gated: the deferred dispatch is armed" \
    || bad "[$sh] arm-impl gated: no deferred arm"
  not_logged "sling " && ok "[$sh] arm-impl gated: nothing is slung now" \
    || bad "[$sh] arm-impl gated: slung before the design closed"
  logged "gc.impl_armed=1" && ok "[$sh] arm-impl gated: gc.impl_armed is stamped" \
    || bad "[$sh] arm-impl gated: gc.impl_armed not stamped"

  export DEP_ADD_BLOCKS_RC=1
  run_arm arm-implementation-dispatch "$sh"
  stopped && not_logged "deferred-dispatch" && not_logged "gc.impl_armed" \
    && ok "[$sh] arm-impl gated: a failed blocks edge neither arms nor stamps" \
    || bad "[$sh] arm-impl gated: a failed blocks edge still armed or stamped (rc=$RC)"

  export DEP_ADD_BLOCKS_RC=0 LIST_BLOCKS='[]'
  run_arm arm-implementation-dispatch "$sh"
  stopped && not_logged "deferred-dispatch" && not_logged "gc.impl_armed" \
    && ok "[$sh] arm-impl gated: a blocks edge that does not read back stops before the arm" \
    || bad "[$sh] arm-impl gated: an unread blocks edge was trusted (rc=$RC)"

  export LIST_BLOCKS="$BLOCKS_OK" LIST_PARENT='[]'
  run_arm arm-implementation-dispatch "$sh"
  stopped && not_logged "--type=blocks" && not_logged "deferred-dispatch" \
    && ok "[$sh] arm-impl gated: an unread convoy link stops before the blocks edge" \
    || bad "[$sh] arm-impl gated: an unread convoy link was trusted (rc=$RC)"

  export LIST_PARENT="$PARENT_OK" ARM_RC=1
  run_arm arm-implementation-dispatch "$sh"
  stopped && not_logged "gc.impl_armed" \
    && ok "[$sh] arm-impl gated: a failed deferred arm leaves the marker unstamped" \
    || bad "[$sh] arm-impl gated: a failed deferred arm still stamped (rc=$RC)"

  export ARM_RC=0 UPDATE_RC=1
  run_arm arm-implementation-dispatch "$sh"
  stopped && ok "[$sh] arm-impl: a marker that does not record fails the step" \
    || bad "[$sh] arm-impl: an unrecorded marker passed"
  export UPDATE_RC=0

  # --- arm-implementation-dispatch, all-in-one ---
  export ARM_RC=0 DESIGN_GATED=false
  run_arm arm-implementation-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-impl all-in-one: a verified link slings the child now"
  logged "sling rig/gc-toolkit.polecat dz-impl --on mol-polecat-work" \
    && ok "[$sh] arm-impl all-in-one: the implementation child is slung" \
    || bad "[$sh] arm-impl all-in-one: no sling"
  not_logged "--type=blocks" && not_logged "deferred-dispatch" \
    && ok "[$sh] arm-impl all-in-one: no blocks edge and no deferred arm" \
    || bad "[$sh] arm-impl all-in-one: held behind the design anyway"

  export DEP_ADD_PARENT_RC=1
  run_arm arm-implementation-dispatch "$sh"
  stopped && not_logged "sling " && not_logged "gc.impl_armed" \
    && ok "[$sh] arm-impl all-in-one: a failed link neither slings nor stamps" \
    || bad "[$sh] arm-impl all-in-one: a failed link still slung or stamped (rc=$RC)"

  export DEP_ADD_PARENT_RC=0 ARMED=1
  run_arm arm-implementation-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-impl: an armed subject is a no-op"
  [ -s "$TMP/gc.log" ] && bad "[$sh] arm-impl: an armed subject still wrote" \
    || ok "[$sh] arm-impl: an armed subject writes nothing"
done

echo
echo "mol-design-convoy-arm: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
