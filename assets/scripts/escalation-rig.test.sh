#!/usr/bin/env bash
# Hermetic test for assets/scripts/escalation-rig.sh — the bead id prefix is
# the only input, so the answer is the subject's store whatever the caller's
# ambient rig or the subject's route say. Stubbed gc; no live city.
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
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
[ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ] || exit 0
[ -n "${STUB_RIGS_FAIL:-}" ] && { echo "gc: rig list unavailable" >&2; exit 1; }
printf '%s\n' "${STUB_RIGS:-}"
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
unset STUB_RIGS_FAIL 2>/dev/null || true
export STUB_RIGS='{"rigs":[{"name":"loomington","prefix":"lx","path":"/c"},
  {"name":"gc-toolkit","prefix":"tk","path":"/c/rigs/gc-toolkit"},
  {"name":"gascity","prefix":"gc","path":"/c/rigs/gascity"},
  {"name":"signal-loom","prefix":"sl","path":"/c/rigs/signal-loom"}]}'

run() { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }

# The finding this guards: a warrant living outside gc-toolkit, whose route is
# a bare identity carrying no rig segment, still resolves to its own store.
export GC_RIG=gc-toolkit
run gc-yxpj8
eq "$RC" "0" "a non-gc-toolkit bead resolves while the caller sits in gc-toolkit (rc)"
eq "$OUT" "gascity" "  ... and names the bead's own rig, not the ambient one"

unset GC_RIG
run gc-yxpj8
eq "$OUT" "gascity" "the same answer with GC_RIG unset — the ambient rig is not an input"

run tk-3y6toq
eq "$RC" "0" "a gc-toolkit bead resolves (rc)"
eq "$OUT" "gc-toolkit" "  ... to gc-toolkit"

run sl-abc12
eq "$OUT" "signal-loom" "a signal-loom bead resolves to signal-loom"

# Fail closed: every unresolved shape refuses with empty stdout, so a caller
# binding GC_RIG=$(...) gets nothing to bind rather than a guess.
run zz-abc12
eq "$RC" "1" "an unknown prefix refuses (rc)"
eq "$OUT" "" "  ... printing no rig to stdout"
has "$ERR" "no rig carries the prefix 'zz'" "  ... and naming the prefix it could not place"

run abc12
eq "$RC" "1" "an id with no prefix segment refuses"
eq "$OUT" "" "  ... printing no rig to stdout"

STUB_RIGS='{"rigs":[{"name":"one","prefix":"dup","path":"/a"},{"name":"two","prefix":"dup","path":"/b"}]}' \
  run dup-abc12
eq "$RC" "1" "a prefix two rigs carry refuses rather than picking one"
eq "$OUT" "" "  ... printing no rig to stdout"
has "$ERR" "carried by 2 rigs" "  ... and saying how many carry it"

STUB_RIGS_FAIL=1 run tk-3y6toq
eq "$RC" "1" "an unreadable rig list refuses"
eq "$OUT" "" "  ... printing no rig to stdout"
has "$ERR" "could not read" "  ... reported apart from 'no such prefix', which has a different repair"

run
eq "$RC" "2" "no argument is a usage error"
run tk-3y6toq extra
eq "$RC" "2" "a second argument is a usage error"
run --help
eq "$RC" "2" "--help is a usage error"

# Callers bind the output directly, so it must carry nothing but the name.
export GC_RIG=gc-toolkit
BOUND=$(GC_RIG="$("$SUT" gc-yxpj8)" sh -c 'printf "[%s]" "$GC_RIG"')
eq "$BOUND" "[gascity]" "the output binds straight into GC_RIG with no trailing junk"

echo
echo "escalation-rig: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
