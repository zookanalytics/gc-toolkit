#!/usr/bin/env bash
# Hermetic tests for gc-helm.sh's retired board verb and its rig-enumeration
# helper. open, engage, dismiss and the other verbs each have a suite of their
# own (gc-helm-<verb>.test.sh), and gctk's takeaway and reaction packages hold
# the takeaway's and accept's. Runs the REAL script with a stubbed `gc` on PATH:
# no live city, Dolt, network, or sessions. Covered:
#   the retired board verb refuses and names helm-svc board
#   the rig-enumeration helper leaving no trap installed on its caller
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

# The script needs a gc on PATH to start, and the board verb refuses before it
# calls one.
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; echo 'exit 0'; } > "$TMP/bin/gc"
chmod +x "$TMP/bin/gc"
SAVED_PATH="$PATH"; export PATH="$TMP/bin:$PATH"
unset GC_SESSION_NAME GC_SESSION_ID GC_ALIAS GC_AGENT GC_RIG BEADS_DIR GC_HELM_FIXTURE || true

# ── the board verb is retired (moved to helm-svc board) ──────────────────────
BRC=0
BERRTXT="$(sh "$SCRIPT" board --json 2>&1 >/dev/null)" || BRC=$?
eq "$BRC" "2" "(NOBOARD) 'board' is a usage error now"
grep -q 'helm-svc board' <<< "$BERRTXT" \
  && ok "(NOBOARD) …and the refusal points at helm-svc board" \
  || bad "(NOBOARD) refusal must name the successor (got: $BERRTXT)"

PATH="$SAVED_PATH"

# ── the rig-enumeration helper restores the caller's trap table ──────────────
# A trap is process-global: one installed inside a helper and left there
# rewrites how every later line of the caller answers a signal. The helper is
# lifted and run directly, with the real rig-map.sh it reads the map through —
# every real call site is a command substitution, whose subshell would hide
# the residue. Assert the table is unchanged across the call, not that it is
# empty: a caller can inherit a disposition the helper never touches — a parent
# that ignores SIGPIPE shows up as `trap -- '' SIGPIPE`, which bash reports and
# the helper can neither set nor clear — and the invariant is that the helper
# leaves the table exactly as it found it.
ENUM="$TMP/enum-helper.sh"
sed -n '/^rigs_count() {/,/^}/p;/^enumerate_rigs() {/,/^}/p' "$SCRIPT" > "$ENUM"
mkdir -p "$TMP/enumbin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/enumbin/gc" <<'ENUMGC'
[ "$1 ${2:-}" = "rig list" ] && printf '{"rigs":[{"name":"r","path":"/p","prefix":"tk"}]}\n'
exit 0
ENUMGC
chmod +x "$TMP/enumbin/gc"
# The probe sources city-liveness.sh ($2) first, for the projection the helper
# runs, as the script does, and finds rig-map.sh in $3, as the script finds it
# beside itself.
cat > "$TMP/enum-probe.sh" <<'ENUMPROBE'
set -eu
PROG=probe; FIXTURE=""; RIGS=""; SCRIPT_DIR="$3"
. "$2"
. "$1"
before="$(trap)"
enumerate_rigs
after="$(trap)"
printf 'RIGS[%s]\n' "$RIGS"
[ "$before" = "$after" ] && printf 'TRAPDELTA[]\n' \
  || printf 'TRAPDELTA[before=<%s> after=<%s>]\n' "$before" "$after"
ENUMPROBE
ENUMTMP="$TMP/enumtmp"; mkdir -p "$ENUMTMP"
EOUT="$(TMPDIR="$ENUMTMP" PATH="$TMP/enumbin:$PATH" bash "$TMP/enum-probe.sh" "$ENUM" "$HERE/city-liveness.sh" "$HERE" 2>&1 || true)"
grep -q 'RIGS\[\[' <<< "$EOUT" \
  && ok "(ENUM) the helper enumerated, through rig-map.sh" \
  || bad "(ENUM) the helper did not enumerate (out: $EOUT)"
grep -q 'TRAPDELTA\[\]' <<< "$EOUT" \
  && ok "(ENUM) …and left the caller's trap table as it found it" \
  || bad "(ENUM) the helper changed the caller's traps (out: $EOUT)"
eq "$(find "$ENUMTMP" -name 'gctk-rig-map.*' | wc -l | tr -d ' ')" "0" \
   "(ENUM) …and rig-map.sh removed its stderr capture"

echo ""
echo "gc-helm board refusal + rig enumeration: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
