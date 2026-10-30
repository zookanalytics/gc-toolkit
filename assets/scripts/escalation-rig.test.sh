#!/usr/bin/env bash
# Hermetic test for assets/scripts/escalation-rig.sh, the hand-off that runs
# bead-store.sh for a run or a session that still names the old path. It pins
# the two forms those callers use, that bead-store.sh's answer and exit come
# back unchanged, and that each caller's derivation, as it was poured, still
# reaches human-gate.sh through the hand-off at escalate.sh. Stubbed gc; no live
# city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/escalation-rig.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-escalation-rig-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { if grep -qF -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"
# The stub answers `gc rig list --json` from STUB_RIGS, and `gc bd show <id>
# --json` with a task row for the id, as a warrant or a work bead reads, because
# the hand-off at escalate.sh reads its subject's row. Any other call prints
# nothing and exits 0.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
if [ "${1:-} ${2:-}" = "bd show" ]; then
  printf '[{"id":"%s","status":"open","issue_type":"task"}]\n' "${3:-}"
  exit 0
fi
[ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ] || exit 0
[ -n "${STUB_RIGS_FAIL:-}" ] && { echo "gc: rig list unavailable" >&2; exit 1; }
printf '%s\n' "${STUB_RIGS:-}"
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
unset STUB_RIGS_FAIL GC_RIG 2>/dev/null || true
export STUB_RIGS='{"rigs":[{"name":"mycity","prefix":"hq","path":"/c"},
  {"name":"gc-toolkit","prefix":"tk","path":"/c/rigs/gc-toolkit"},
  {"name":"gascity","prefix":"gc","path":"/c/rigs/gascity"}]}'

run() { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }

echo "# the two forms the old callers use answer as bead-store.sh does"
run gc-yxpj8
eq "$RC" "0" "a bead's rig resolves (rc)"
eq "$OUT" "gascity" "  ... to the rig its id prefix names"
run --db gc-yxpj8
eq "$RC" "0" "--db resolves (rc)"
eq "$OUT" "/c/rigs/gascity/.beads" "  ... to that rig's .beads path"
run hq-abc12
eq "$OUT" "mycity" "a city-store bead names the city's rig"
BOUND=$(GC_RIG="$("$SUT" tk-3y6toq)" sh -c 'printf "[%s]" "$GC_RIG"')
eq "$BOUND" "[gc-toolkit]" "the output binds straight into GC_RIG with no trailing junk"

echo "# bead-store.sh's refusals come back with their exit codes"
run zz-abc12
eq "$RC" "1" "an unknown prefix is a proven no-such-bead (exit 1)"
eq "$OUT" "" "  ... printing nothing to bind"
has "$ERR" "no rig carries the prefix 'zz'" "  ... with bead-store.sh's reason"
STUB_RIGS_FAIL=1 run tk-3y6toq
eq "$RC" "3" "an unreadable rig list is unproven (exit 3)"
eq "$OUT" "" "  ... printing nothing to bind"
run
eq "$RC" "2" "no argument is a usage error"

# Each caller, as it was poured, runs from a private copy of the pack's scripts
# whose human-gate.sh records what reached it.
PACK="$TMP/pack"; mkdir -p "$PACK"
cp "$SUT" "$HERE/bead-store.sh" "$HERE/escalate.sh" "$HERE/bd-lib.sh" "$PACK/"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$PACK/human-gate.sh" <<'STUB'
{ printf 'GC_RIG=%s' "${GC_RIG:-}"; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "${STUB_HG_LOG:?}"
echo "gate-1"
STUB
chmod +x "$PACK"/*.sh
export STUB_HG_LOG="$TMP/hg.log"
SCRIPTS="$PACK"

echo "# the deacon's emergency recipe still files through both old names"
: > "$STUB_HG_LOG"
ESC_RIG=$("$SCRIPTS/escalation-rig.sh" tk-3y6toq) \
  && GC_RIG="$ESC_RIG" "$SCRIPTS/escalate.sh" --subject tk-3y6toq --key dolt-outage --message "Dolt is down" >/dev/null 2>&1
eq "$?" "0" "the chain exits 0"
eq "$(cat "$STUB_HG_LOG")" "GC_RIG=gc-toolkit [--subject] [tk-3y6toq] [--key] [dolt-outage] [--message] [Dolt is down]" \
  "human-gate.sh receives the call, with the derived rig bound"

echo "# the dog's warrant derivation still lets its wedged-session call file"
: > "$STUB_HG_LOG"
warrant_id=hq-w4rr4nt target=hq-wisp-p3
ESC_RIG="$("$SCRIPTS/escalation-rig.sh" "$warrant_id")" || ESC_RIG=""
if [ -n "$ESC_RIG" ]; then
  GC_RIG="$ESC_RIG" "$SCRIPTS/escalate.sh" --subject "$warrant_id" --key "wedged-$target" --message "kill failed" >/dev/null 2>&1
fi
eq "$ESC_RIG" "mycity" "the warrant's store resolves, so the call is made"
has "$(cat "$STUB_HG_LOG")" "[--subject] [hq-w4rr4nt] [--key] [wedged-hq-wisp-p3]" "human-gate.sh receives the wedged-session call on the warrant"

echo
echo "escalation-rig: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
