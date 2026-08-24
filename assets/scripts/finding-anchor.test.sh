#!/usr/bin/env bash
# Hermetic test for finding-anchor.sh (tk-mvc72).
#
# WHAT IS BEING PROTECTED. finding-anchor.sh is the piece that lets the deacon
# use escalation-gate.sh at all: the gate stamps a BEAD, and a deacon finding is
# about a database or a doctor check, so something has to turn "dolt-noms-size"
# into "the one open bead tracking dolt-noms-size". Every bug below turns the
# storm back on, or turns it into a worse one, while the script still looks like
# it is deduping:
#
#   minting on a FAILED read      an unreadable ledger is not an empty one. Read
#                                 failures are transient and recur, so this mints
#                                 a fresh tracker every cycle — the mail storm
#                                 reborn as a BEAD storm, each one carrying its
#                                 own escalation (READFAIL, NOTARRAY)
#   answering after a failed      the returned id does not carry the lookup key,
#   stamp                         so the next cycle cannot find it and mints
#                                 another. Same bead storm, one step later
#                                 (STAMPFAIL)
#   a repeated --status flag      `bd list` keeps only the LAST -s/--status, so
#                                 `--status=open --status=in_progress` is an
#                                 in_progress-only query wearing the look of a
#                                 union — and the `open` tracker it cannot see is
#                                 the common case (STATUSUNION)
#   accepting a prose key         `bd search` matches a contiguous substring, and
#                                 a phrase composed from a finding's message is
#                                 the query shape the mayor measured returning
#                                 ZERO for beads that plainly cover it. The key
#                                 must be the finding's own name, one token
#                                 (WHITESPACE)
#   a key bd cannot store         a metadata key with '-' or '=' stamps a field
#                                 nothing reads back, so the tracker is invisible
#                                 to its own lookup (BADKEY, tk-cp6of)
#
# The `gc` stub REFUSES what the real tool refuses. A stub that accepts a flag
# combination bd rejects hides a dead branch behind a green suite, so the
# --status union is asserted positively (STATUSUNION) rather than assumed.
#
# Companion: assets/scripts/deacon-escalation-wiring.test.sh covers the formula
# lines that CALL this script. escalation-gate.test.sh covers the gate itself.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/finding-anchor.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$2" in *"$1"*) ok "$3" ;; *) bad "$3 (not found in: $2)" ;; esac; }
hasnt() { case "$2" in *"$1"*) bad "$3 (unexpectedly found '$1' in: $2)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }

export STUB_LOG="$TMP/log"
mkdir -p "$STUB_LOG" "$TMP/bin"
export PATH="$TMP/bin:$PATH"

# --- The gc stub --------------------------------------------------------------
#
# STUB_ROWS   what `bd list` returns, verbatim. Default "[]" (the shape the live
#             tool returns for a metadata query matching nothing — verified
#             against the real binary before this test was written).
# STUB_CREATE_FAIL   `bd create` emits nothing, both times.
# STUB_UPDATE_FAIL   `bd update` exits non-zero (the stamp cannot be written).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
S="$STUB_LOG"
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "list" ]; then
  shift 2
  for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$S/list-args.json"
  printf '%s' "${STUB_ROWS-[]}"
  exit 0
fi
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "create" ]; then
  shift 2
  for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$S/create-args.json"
  # Record the body so a test can assert what a minted tracker says.
  case " $* " in *" --body-file - "*) cat > "$S/create-body" ;; esac
  [ -n "${STUB_CREATE_FAIL:-}" ] && exit 1
  printf '{"id":"tk-minted"}'
  exit 0
fi
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "update" ]; then
  shift 2
  for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$S/update-args.json"
  echo update >> "$S/calls"
  [ -n "${STUB_UPDATE_FAIL:-}" ] && exit 1
  exit 0
fi
exit 0
GC
chmod +x "$TMP/bin/gc"

reset() {
  rm -rf "$STUB_LOG"; mkdir -p "$STUB_LOG"
  unset STUB_ROWS STUB_CREATE_FAIL STUB_UPDATE_FAIL
}

echo "== finding-anchor.sh =="

# --- EXISTING: a live tracker is returned, and nothing is minted ---------------
reset
# SC2089/SC2090 want an array here. An array cannot cross the environment into a
# stub process, and the value is deliberately an opaque JSON blob echoed back
# verbatim by the stub — its quotes are DATA, not shell syntax.
# shellcheck disable=SC2089
STUB_ROWS='[{"id":"tk-tracker","status":"open"}]'
# shellcheck disable=SC2090
export STUB_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "should not be used" 2>"$TMP/err"); RC=$?
eq "$RC" 0 "EXISTING: exits 0"
eq "$OUT" "tk-tracker" "EXISTING: returns the tracker already open"
[ -f "$STUB_LOG/create-args.json" ] && bad "EXISTING: minted a duplicate tracker" \
  || ok "EXISTING: minted nothing"

# --- STATUSUNION: the lookup asks ONE comma-separated --status ----------------
# Repeated --status flags are silently reduced by bd to the LAST one, so a union
# spelled as two flags is an in_progress-only query that cannot see the common
# case. Assert the flag shape that actually reaches the tool.
ARGS=$(jq -r '.[]' < "$STUB_LOG/list-args.json")
NSTATUS=$(printf '%s\n' "$ARGS" | grep -c -- '--status' || true)
eq "$NSTATUS" 1 "STATUSUNION: exactly one --status argument"
has "open,in_progress,blocked" "$ARGS" "STATUSUNION: all three live statuses in one value"
has "finding_key=dolt-noms-size" "$ARGS" "EXISTING: looked up by exact metadata match"
hasnt "search" "$ARGS" "EXISTING: never uses bd search (it matches substrings, not tokens)"

# --- MINT: no tracker exists, so one is minted AND stamped --------------------
reset
STUB_ROWS='[]'
export STUB_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "doctor check dolt-noms-size is firing" 2>"$TMP/err"); RC=$?
eq "$RC" 0 "MINT: exits 0"
eq "$OUT" "tk-minted" "MINT: returns the new tracker id"
UARGS=$(jq -r '.[]' < "$STUB_LOG/update-args.json")
has "finding_key=dolt-noms-size" "$UARGS" "MINT: stamps the lookup key on the new bead"

# --- MINT is invisible without the stamp -------------------------------------
# The stamp IS the tracker. A mint whose stamp is missing cannot be found by the
# lookup above, so the next cycle mints another one and the bead storm begins.
hasnt "doctor_check" "$UARGS" "MINT: default key is finding_key, not doctor_check"

# --- KEY: --key doctor_check converges with doctor-finding-gate.sh ------------
reset
STUB_ROWS='[]'
export STUB_ROWS
OUT=$("$SCRIPT" dolt-noms-size --key doctor_check --title "t" 2>"$TMP/err")
eq "$OUT" "tk-minted" "KEY: returns the minted id"
LARGS=$(jq -r '.[]' < "$STUB_LOG/list-args.json")
UARGS=$(jq -r '.[]' < "$STUB_LOG/update-args.json")
has "doctor_check=dolt-noms-size" "$LARGS" "KEY: looks up on the caller's key"
has "doctor_check=dolt-noms-size" "$UARGS" "KEY: stamps the caller's key"

# --- READFAIL: an unreadable ledger is NOT an empty one -----------------------
# The single most dangerous failure: mint-on-read-failure turns one transient
# error into a duplicate tracker every cycle, each carrying its own escalation.
reset
STUB_ROWS=''
export STUB_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "t" 2>"$TMP/err"); RC=$?
eq "$RC" 2 "READFAIL: exits 2 (indeterminate)"
eq "$OUT" "" "READFAIL: prints no id, so the caller has no anchor to mail on"
[ -f "$STUB_LOG/create-args.json" ] && bad "READFAIL: minted on a failed read" \
  || ok "READFAIL: minted nothing"
has "a failed read is not an empty one" "$(cat "$TMP/err")" "READFAIL: says why on stderr"

# --- NOTARRAY: a non-array payload is a failed read, not an empty one ---------
reset
STUB_ROWS='gc: unexpected error'
export STUB_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "t" 2>"$TMP/err"); RC=$?
eq "$RC" 2 "NOTARRAY: exits 2"
eq "$OUT" "" "NOTARRAY: prints no id"
[ -f "$STUB_LOG/create-args.json" ] && bad "NOTARRAY: minted on a garbage payload" \
  || ok "NOTARRAY: minted nothing"

# --- STAMPFAIL: a tracker that could not be stamped must not be used ----------
# It would answer this cycle and be invisible to the next one's lookup.
reset
STUB_ROWS='[]'
STUB_UPDATE_FAIL=1
export STUB_ROWS STUB_UPDATE_FAIL
OUT=$("$SCRIPT" dolt-noms-size --title "t" 2>"$TMP/err"); RC=$?
eq "$RC" 2 "STAMPFAIL: exits 2"
eq "$OUT" "" "STAMPFAIL: does not hand back an id that cannot dedupe"
has "will not dedupe" "$(cat "$TMP/err")" "STAMPFAIL: names the repair on stderr"

# --- CREATEFAIL: no bead, no answer ------------------------------------------
reset
STUB_ROWS='[]'
STUB_CREATE_FAIL=1
export STUB_ROWS STUB_CREATE_FAIL
OUT=$("$SCRIPT" dolt-noms-size --title "t" 2>"$TMP/err"); RC=$?
eq "$RC" 2 "CREATEFAIL: exits 2"
eq "$OUT" "" "CREATEFAIL: prints no id"

# --- WHITESPACE: a prose-composed key is refused -----------------------------
# This is the mayor's measured constraint made mechanical. "backup freshness"
# returns nothing from bd search for a bead titled bd-backup-freshness, so a
# phrase must never become the dedupe key.
reset
STUB_ROWS='[]'
export STUB_ROWS
OUT=$("$SCRIPT" "backup freshness" --title "t" 2>"$TMP/err"); RC=$?
eq "$RC" 2 "WHITESPACE: refuses a multi-word finding name"
eq "$OUT" "" "WHITESPACE: prints no id"
has "single token" "$(cat "$TMP/err")" "WHITESPACE: explains the constraint"
[ -f "$STUB_LOG/list-args.json" ] && bad "WHITESPACE: queried anyway" \
  || ok "WHITESPACE: refused before touching the ledger"

# --- BADKEY: a key bd cannot store is refused --------------------------------
for k in "doctor-check" "a=b" ""; do
  reset
  STUB_ROWS='[]'
  export STUB_ROWS
  OUT=$("$SCRIPT" some-finding --key "$k" --title "t" 2>"$TMP/err"); RC=$?
  eq "$RC" 2 "BADKEY('$k'): refused"
  eq "$OUT" "" "BADKEY('$k'): prints no id"
done

# --- ARGEAT: a flag missing its value must not swallow the next flag ---------
# `--title --key x` would otherwise mint a bead literally titled "--key".
reset
STUB_ROWS='[]'
export STUB_ROWS
OUT=$("$SCRIPT" some-finding --title --key doctor_check 2>"$TMP/err"); RC=$?
eq "$RC" 2 "ARGEAT: --title with no value is refused"
has "requires a value" "$(cat "$TMP/err")" "ARGEAT: says which flag"

# --- NOTITLE: a mint needs a name --------------------------------------------
reset
STUB_ROWS='[]'
export STUB_ROWS
OUT=$("$SCRIPT" some-finding 2>"$TMP/err"); RC=$?
eq "$RC" 2 "NOTITLE: --title is required"

# --- PERDB: a per-database finding name round-trips through the lookup -------
# `dolt-backup-manifest:lx` carries a colon, which must survive as a metadata
# value or per-database dedup silently collapses to one shared tracker.
reset
STUB_ROWS='[]'
export STUB_ROWS
OUT=$("$SCRIPT" "dolt-backup-manifest:lx" --title "lx has no restorable backup" 2>"$TMP/err")
eq "$OUT" "tk-minted" "PERDB: colon-bearing name is accepted"
LARGS=$(jq -r '.[]' < "$STUB_LOG/list-args.json")
UARGS=$(jq -r '.[]' < "$STUB_LOG/update-args.json")
has "finding_key=dolt-backup-manifest:lx" "$LARGS" "PERDB: looked up verbatim"
has "finding_key=dolt-backup-manifest:lx" "$UARGS" "PERDB: stamped verbatim"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
