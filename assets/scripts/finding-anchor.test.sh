#!/usr/bin/env bash
# SC2089/SC2090 want arrays for the STUB_*_ROWS values below. An array cannot
# cross the environment into a stub process, and every one of these values is
# deliberately an opaque JSON blob that the stub echoes back verbatim — the
# quotes in them are DATA, not shell syntax. File-level, because the pattern is
# the whole fixture surface of this test rather than one assignment.
# shellcheck disable=SC2089,SC2090
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

# `gc rig list --json` is what the city sweep is built from. The default city has
# an HQ store plus two rigs, because those are addressed DIFFERENTLY by the real
# tool and a one-store city would not exercise the difference.
DEFAULT_RIGS='{"rigs":[
  {"name":"loomington","prefix":"lx","hq":true,"path":"/city","beads":"initialized"},
  {"name":"alpha","prefix":"al","hq":false,"path":"/city/rigs/alpha","beads":"initialized"},
  {"name":"beta","prefix":"be","hq":false,"path":"/city/rigs/beta","beads":"initialized"}]}'
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
  echo rig-list >> "$S/calls"
  # STUB_RIGS_FAIL models an unreadable enumeration: empty output, zero exit —
  # which is how the real tool fails here, and why the array-shape assertion
  # rather than the exit code is what has to catch it.
  [ -n "${STUB_RIGS_FAIL:-}" ] && exit 0
  printf '%s' "${STUB_RIGS-$DEFAULT_RIGS}"
  exit 0
fi

if [ "${1:-}" != "bd" ]; then exit 0; fi
shift

# The store-routing flags come BEFORE the subcommand. `gc bd --rig` does not
# accept the HQ rig in the real tool, so the HQ leg is addressed by path with
# -C; the stub keeps the two distinguishable so a test can prove both legs ran.
SPEC="L:"
case "${1:-}" in
  -C)    SPEC="C:${2:-}"; shift 2 ;;
  --rig) SPEC="R:${2:-}"; shift 2 ;;
esac
SUB="${1:-}"
[ $# -gt 0 ] && shift

# A store named by STUB_*_STORE is the ONLY one that answers with rows; every
# other store answers `[]`. That is what makes "the tracker lives in another
# rig" testable rather than assumed.
answer() { # answer <rows-var-value> <wanted-spec>
  if [ -n "$2" ] && [ "$SPEC" != "$2" ]; then printf '[]'; else printf '%s' "$1"; fi
}

case "$SUB" in
  list)
    printf '%s\n' "$SPEC" >> "$S/list-stores"
    for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$S/list-args.json"
    if [ -n "${STUB_ROWS_BY_STORE:-}" ]; then
      printf '%s' "$STUB_ROWS_BY_STORE" | jq -c --arg s "$SPEC" '.[$s] // []'
      exit 0
    fi
    answer "${STUB_ROWS-[]}" "${STUB_ROWS_STORE:-}"
    exit 0 ;;
  search)
    printf '%s\n' "$SPEC" >> "$S/search-stores"
    for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$S/search-args.json"
    [ -n "${STUB_SEARCH_FAIL:-}" ] && exit 0
    if [ -n "${STUB_SEARCH_BY_STORE:-}" ]; then
      printf '%s' "$STUB_SEARCH_BY_STORE" | jq -c --arg s "$SPEC" '.[$s] // []'
      exit 0
    fi
    answer "${STUB_SEARCH_ROWS-[]}" "${STUB_SEARCH_STORE:-}"
    exit 0 ;;
  create)
    printf '%s\n' "$SPEC" >> "$S/create-stores"
    for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$S/create-args.json"
    # Record the body so a test can assert what a minted tracker says.
    case " $* " in *" --body-file - "*) cat > "$S/create-body" ;; esac
    [ -n "${STUB_CREATE_FAIL:-}" ] && exit 1
    printf '{"id":"tk-minted"}'
    exit 0 ;;
  update)
    printf '%s\n' "$SPEC" >> "$S/update-stores"
    for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$S/update-args.json"
    echo update >> "$S/calls"
    [ -n "${STUB_UPDATE_FAIL:-}" ] && exit 1
    exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

reset() {
  rm -rf "$STUB_LOG"; mkdir -p "$STUB_LOG"
  unset STUB_ROWS STUB_CREATE_FAIL STUB_UPDATE_FAIL STUB_ROWS_STORE \
        STUB_SEARCH_ROWS STUB_SEARCH_STORE STUB_SEARCH_FAIL STUB_RIGS STUB_RIGS_FAIL \
        STUB_ROWS_BY_STORE STUB_SEARCH_BY_STORE
}

echo "== finding-anchor.sh =="

# --- EXISTING: a live tracker is returned, and nothing is minted ---------------
reset
STUB_ROWS='[{"id":"tk-tracker","status":"open"}]'
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

# --- CITYWIDE: the sweep reaches every store, not just the ambient one -------
# The defect this closes: `bd` answers for ONE store, and the beads already
# tracking a deacon finding were filed wherever whoever noticed was standing.
# Measured live 2026-08-24 — gc-b1n7a and gc-ltbm5 both track
# bd-backup-freshness, both are open, both live in rigs/gascity, and the
# identical --metadata-field query from rigs/gc-toolkit returns neither. A
# single-store lookup calls that finding untracked and mints a third tracker.
reset
STUB_ROWS='[{"id":"gc-b1n7a","status":"open"}]'
STUB_ROWS_STORE='R:beta'          # the tracker exists ONLY in a foreign rig
export STUB_ROWS STUB_ROWS_STORE
OUT=$("$SCRIPT" bd-backup-freshness --title "should not be used" 2>"$TMP/err"); RC=$?
eq "$RC" 0 "CITYWIDE: exits 0 on a tracker held in another rig's store"
eq "$OUT" "gc-b1n7a" "CITYWIDE: returns the foreign-store tracker"
[ -f "$STUB_LOG/create-args.json" ] && bad "CITYWIDE: minted a duplicate beside a live foreign tracker" \
  || ok "CITYWIDE: minted nothing"
SEEN=$(sort -u < "$STUB_LOG/list-stores" | tr '\n' ' ')
has "C:/city" "$SEEN" "CITYWIDE: the HQ store is swept by path (--rig cannot address it)"
has "R:alpha" "$SEEN" "CITYWIDE: a rig store is swept by name"

# --- ADOPT: a pre-existing title-only tracker is adopted, not duplicated ------
# Every tracker filed before finding-anchor.sh existed is title-only: gc-b1n7a
# and gc-ltbm5 carry neither finding_key nor doctor_check. Reading metadata
# absence as tracker absence mints a third bead beside two live ones and mails
# about it — the exact false "no open bead in any store matches" that filed the
# duplicate gc-woe2r.
reset
STUB_ROWS='[]'                                   # tier 1 misses everywhere
STUB_SEARCH_ROWS='[{"id":"gc-ltbm5","status":"open","created_at":"2026-08-10T23:01:34Z","title":"doctor: bd-backup-freshness checks the RETIRED bd backup sync mechanism"},{"id":"gc-b1n7a","status":"open","created_at":"2026-08-14T02:20:08Z","title":"doctor: bd-backup-freshness labels server-mode Dolt scopes"}]'
STUB_SEARCH_STORE='R:beta'
export STUB_ROWS STUB_SEARCH_ROWS STUB_SEARCH_STORE
OUT=$("$SCRIPT" bd-backup-freshness --title "should not be used" 2>"$TMP/err"); RC=$?
eq "$RC" 0 "ADOPT: exits 0 on a legacy title-only tracker"
eq "$OUT" "gc-ltbm5" "ADOPT: picks the OLDEST live match (deterministic across cycles)"
[ -f "$STUB_LOG/create-args.json" ] && bad "ADOPT: minted a duplicate beside a legacy tracker" \
  || ok "ADOPT: minted nothing"
UARGS=$(jq -r '.[]' < "$STUB_LOG/update-args.json")
has "finding_key=bd-backup-freshness" "$UARGS" "ADOPT: stamps the adopted bead so tier 1 owns it next cycle"
has "gc-ltbm5" "$UARGS" "ADOPT: stamps the bead it actually returned"
eq "$(tail -1 < "$STUB_LOG/update-stores")" "R:beta" "ADOPT: stamps it in the store it was found in"
SARGS=$(jq -r '.[]' < "$STUB_LOG/search-args.json")
has "bd-backup-freshness" "$SARGS" "ADOPT: searched the finding's own token, verbatim"
has "open,in_progress,blocked" "$SARGS" "ADOPT: search excludes closed beads (a closed tracker did not fix it)"

# --- ADOPTORDER: tier 2 runs only after tier 1 has missed everywhere ----------
# The exact match is authoritative; a title search that could pre-empt it would
# reintroduce substring matching into the common case.
reset
STUB_ROWS='[{"id":"tk-stamped","status":"open"}]'
STUB_SEARCH_ROWS='[{"id":"gc-legacy","status":"open","created_at":"2020-01-01T00:00:00Z","title":"dolt-noms-size tracker"}]'
export STUB_ROWS STUB_SEARCH_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "should not be used" 2>"$TMP/err")
eq "$OUT" "tk-stamped" "ADOPTORDER: the exact metadata match wins over an older title match"
[ -f "$STUB_LOG/search-args.json" ] && bad "ADOPTORDER: ran a title search despite an exact hit" \
  || ok "ADOPTORDER: no title search is issued once tier 1 hits"

# --- IDPREFIX: an ID-like search hit whose TITLE lacks the token is refused ---
# `bd search` matches title AND id, and an ID-like query takes a prefix fast
# path: `bd search "gc-b1n7a"` returns gc-b1n7a whose title holds no such token
# (verified against the live tool). Adopting that anchors the escalation on an
# unrelated bead and MUTES the finding — worse than the storm it replaces.
reset
STUB_ROWS='[]'
STUB_SEARCH_ROWS='[{"id":"gc-b1n7a","status":"open","created_at":"2026-08-14T02:20:08Z","title":"doctor: something else entirely"}]'
export STUB_ROWS STUB_SEARCH_ROWS
OUT=$("$SCRIPT" gc-b1n7a --title "fresh tracker" 2>"$TMP/err")
eq "$OUT" "tk-minted" "IDPREFIX: an id-only match is not adopted; a real tracker is minted"
UARGS=$(jq -r '.[]' < "$STUB_LOG/update-args.json")
has "finding_key=gc-b1n7a" "$UARGS" "IDPREFIX: the minted bead is stamped, not the bead the id matched"

# --- ADOPTSTAMPFAIL: a failed stamp on an ADOPTED bead is not fatal -----------
# This is the deliberate asymmetry with STAMPFAIL above. An unstamped MINT is
# invisible to every future lookup, so it must not be used. An unstamped
# ADOPTION is still re-findable by the same title search, whose oldest-first
# pick is stable — so it converges on the same anchor anyway, and refusing would
# mute a finding that a live bead is tracking.
reset
STUB_ROWS='[]'
STUB_SEARCH_ROWS='[{"id":"gc-ltbm5","status":"open","created_at":"2026-08-10T23:01:34Z","title":"doctor: bd-backup-freshness checks the RETIRED mechanism"}]'
STUB_UPDATE_FAIL=1
export STUB_ROWS STUB_SEARCH_ROWS STUB_UPDATE_FAIL
OUT=$("$SCRIPT" bd-backup-freshness --title "should not be used" 2>"$TMP/err"); RC=$?
eq "$RC" 0 "ADOPTSTAMPFAIL: still answers (the title lookup re-finds it next cycle)"
eq "$OUT" "gc-ltbm5" "ADOPTSTAMPFAIL: returns the adopted tracker"
has "could not stamp it" "$(cat "$TMP/err")" "ADOPTSTAMPFAIL: names the repair on stderr"
[ -f "$STUB_LOG/create-args.json" ] && bad "ADOPTSTAMPFAIL: minted a duplicate" \
  || ok "ADOPTSTAMPFAIL: minted nothing"

# --- ENUMFAIL: an unreadable city enumeration must not mint ------------------
# Losing `gc rig list` means the sweep cannot see the other stores, so absence
# is unproven. Minting there is how one transient failure becomes a duplicate
# tracker every cycle — the bead storm this script exists to prevent.
reset
STUB_ROWS='[]'
STUB_RIGS_FAIL=1
export STUB_ROWS STUB_RIGS_FAIL
OUT=$("$SCRIPT" dolt-noms-size --title "fresh tracker" 2>"$TMP/err"); RC=$?
eq "$RC" 2 "ENUMFAIL: exits 2 rather than minting on an unprovable absence"
eq "$OUT" "" "ENUMFAIL: prints no id"
[ -f "$STUB_LOG/create-args.json" ] && bad "ENUMFAIL: minted on a partial sweep" \
  || ok "ENUMFAIL: minted nothing"

# ...but a tracker the ambient store CAN see is still an answer: a find is a
# find, and refusing it would mute a finding that is demonstrably tracked.
reset
STUB_ROWS='[{"id":"tk-tracker","status":"open"}]'
STUB_RIGS_FAIL=1
export STUB_ROWS STUB_RIGS_FAIL
OUT=$("$SCRIPT" dolt-noms-size --title "should not be used" 2>"$TMP/err"); RC=$?
eq "$RC" 0 "ENUMFAIL: a tracker found in the ambient store is still returned"
eq "$OUT" "tk-tracker" "ENUMFAIL: returns it"

# --- SEARCHFAIL: an unreadable search leg must not mint either ---------------
# Tier 2 is part of the proof of absence. If one leg of it cannot be read, the
# sweep is partial and the same rule applies as for tier 1.
reset
STUB_ROWS='[]'
STUB_SEARCH_FAIL=1
export STUB_ROWS STUB_SEARCH_FAIL
OUT=$("$SCRIPT" dolt-noms-size --title "fresh tracker" 2>"$TMP/err"); RC=$?
eq "$RC" 2 "SEARCHFAIL: exits 2 rather than minting on a partial sweep"
[ -f "$STUB_LOG/create-args.json" ] && bad "SEARCHFAIL: minted on a partial sweep" \
  || ok "SEARCHFAIL: minted nothing"

# --- MINTLOCAL: the mint lands in the ambient store, never a foreign one -----
# The sweep READS every store; it writes only to its own. A cross-store create
# routed by name returns an EMPTY id rather than an error when the route is
# wrong, so a mint that tried to place itself elsewhere would fail silently.
reset
STUB_ROWS='[]'
export STUB_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "fresh tracker" 2>"$TMP/err")
eq "$OUT" "tk-minted" "MINTLOCAL: mints when the full sweep proves absence"
eq "$(tail -1 < "$STUB_LOG/create-stores")" "L:" "MINTLOCAL: created in the ambient store"
eq "$(tail -1 < "$STUB_LOG/update-stores")" "L:" "MINTLOCAL: stamped in the ambient store"

# --- CROSSSTORE: oldest-first is decided ACROSS stores, not within one -------
# Two open trackers for one finding is the observed live state (gc-b1n7a and
# gc-ltbm5), and they need not share a store. The pick has to be deterministic
# city-wide: a rule that lands on a different bead per cycle re-mails under a
# new anchor every cycle, which is the storm with extra steps. Each store here
# holds ONE candidate, so only the cross-store comparison can decide.
reset
STUB_ROWS='[]'
STUB_SEARCH_BY_STORE='{
  "R:alpha":[{"id":"al-newer","status":"open","created_at":"2026-08-14T02:20:08Z","title":"doctor: bd-backup-freshness labels server-mode Dolt scopes"}],
  "R:beta": [{"id":"be-older","status":"open","created_at":"2026-08-10T23:01:34Z","title":"doctor: bd-backup-freshness checks the RETIRED mechanism"}]}'
export STUB_ROWS STUB_SEARCH_BY_STORE
OUT=$("$SCRIPT" bd-backup-freshness --title "should not be used" 2>"$TMP/err")
eq "$OUT" "be-older" "CROSSSTORE: the oldest tracker city-wide wins, whichever store holds it"
eq "$(tail -1 < "$STUB_LOG/update-stores")" "R:beta" "CROSSSTORE: stamped in the winner's store, not the last one swept"

# --- CROSSSTORE1: the same rule for tier 1, across stores --------------------
reset
STUB_ROWS_BY_STORE='{"R:beta":[{"id":"be-stamped","status":"open"}]}'
export STUB_ROWS_BY_STORE
OUT=$("$SCRIPT" bd-backup-freshness --title "should not be used" 2>"$TMP/err")
eq "$OUT" "be-stamped" "CROSSSTORE1: an exact match in any store ends the sweep"
[ -f "$STUB_LOG/search-args.json" ] && bad "CROSSSTORE1: fell through to a title search despite an exact hit" \
  || ok "CROSSSTORE1: no title search once tier 1 hits in any store"

# --- ROLLUP: a bead already claimed by ANOTHER finding is never adopted ------
# Roll-up trackers are real: lx-0ojcv is open and its title names four findings
# at once. The gate keys `escalated.<kind>` on the ANCHOR, so one bead holds one
# deacon escalation slot. If two findings adopted the same bead they would not
# merge into one notice — each cycle would read the other's state fingerprint as
# a CHANGE and re-mail, which is the storm this whole change exists to end.
reset
STUB_ROWS='[]'
STUB_SEARCH_ROWS='[{"id":"lx-rollup","status":"open","created_at":"2020-01-01T00:00:00Z","title":"gc doctor: 4 new findings (session-model, dolt-noms-size, bd-backup-freshness)","metadata":{"finding_key":"session-model"}}]'
export STUB_ROWS STUB_SEARCH_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "fresh tracker" 2>"$TMP/err")
eq "$OUT" "tk-minted" "ROLLUP: a bead claimed by another finding is skipped; its own tracker is minted"
UARGS=$(jq -r '.[]' < "$STUB_LOG/update-args.json")
has "finding_key=dolt-noms-size" "$UARGS" "ROLLUP: the stamp lands on the NEW tracker"
hasnt "lx-rollup" "$UARGS" "ROLLUP: the claimed roll-up bead is not restamped"

# ...and the exclusion is keyed on the finding, not on merely HAVING metadata:
# a bead already stamped for THIS finding is still a valid adoption.
reset
STUB_ROWS='[]'
STUB_SEARCH_ROWS='[{"id":"lx-mine","status":"open","created_at":"2020-01-01T00:00:00Z","title":"dolt-noms-size tracker","metadata":{"finding_key":"dolt-noms-size"}}]'
export STUB_ROWS STUB_SEARCH_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "should not be used" 2>"$TMP/err")
eq "$OUT" "lx-mine" "ROLLUP: a bead stamped for THIS finding is still adopted"

# ...and a cross-key claim counts too: doctor_check and finding_key name the
# same kind of ownership, so a doctor tracker is not stolen by a plain finding.
reset
STUB_ROWS='[]'
STUB_SEARCH_ROWS='[{"id":"lx-doc","status":"open","created_at":"2020-01-01T00:00:00Z","title":"dolt-noms-size rollup","metadata":{"doctor_check":"pipefail-grep-q"}}]'
export STUB_ROWS STUB_SEARCH_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "fresh tracker" 2>"$TMP/err")
eq "$OUT" "tk-minted" "ROLLUP: a doctor_check claim by another check also blocks adoption"

# ...and a bead with NO metadata at all is adoptable (the legacy case).
reset
STUB_ROWS='[]'
STUB_SEARCH_ROWS='[{"id":"lx-legacy","status":"open","created_at":"2020-01-01T00:00:00Z","title":"dolt-noms-size is firing","metadata":null}]'
export STUB_ROWS STUB_SEARCH_ROWS
OUT=$("$SCRIPT" dolt-noms-size --title "should not be used" 2>"$TMP/err")
eq "$OUT" "lx-legacy" "ROLLUP: null metadata is absence of a claim, not a claim"

# --- EMPTYCITY: an enumeration that parses but names no usable store ---------
# A well-formed `{"rigs":[]}` is not a city with nothing in it — it is an answer
# this script cannot act on. It must degrade to the ambient store and refuse to
# mint, exactly as an unreadable enumeration does.
reset
STUB_ROWS='[]'
STUB_RIGS='{"rigs":[]}'
export STUB_ROWS STUB_RIGS
OUT=$("$SCRIPT" dolt-noms-size --title "fresh tracker" 2>"$TMP/err"); RC=$?
eq "$RC" 2 "EMPTYCITY: exits 2 rather than minting on an empty enumeration"
[ -f "$STUB_LOG/create-args.json" ] && bad "EMPTYCITY: minted on an empty enumeration" \
  || ok "EMPTYCITY: minted nothing"

# ...and a rig whose beads store is not initialised is skipped, not queried.
reset
STUB_ROWS='[{"id":"tk-tracker","status":"open"}]'
STUB_RIGS='{"rigs":[{"name":"alpha","hq":false,"path":"/c/alpha","beads":"initialized"},{"name":"ghost","hq":false,"path":"/c/ghost","beads":"uninitialized"}]}'
export STUB_ROWS STUB_RIGS
OUT=$("$SCRIPT" dolt-noms-size --title "should not be used" 2>"$TMP/err")
eq "$OUT" "tk-tracker" "UNINIT: still answers from the initialised stores"
hasnt "R:ghost" "$(cat "$STUB_LOG/list-stores" 2>/dev/null)" "UNINIT: an uninitialised rig store is never queried"

# --- LOCALFIRST: the ambient store is swept before any other -----------------
# Not a speed tweak. `doctor-finding-gate.sh` mints and reads its successors
# per store by design, so a check whose tracker was minted locally has to keep
# resolving to that local bead — otherwise the two scripts name different beads
# for one check and the convergence `--key doctor_check` promises is lost. The
# sweep may only change the answer when the ambient store has nothing.
reset
STUB_ROWS_BY_STORE='{
  "L:":      [{"id":"tk-local","status":"open"}],
  "R:beta":  [{"id":"be-foreign","status":"open"}]}'
export STUB_ROWS_BY_STORE
OUT=$("$SCRIPT" doctor-run-incomplete --key doctor_check --title "should not be used" 2>"$TMP/err")
eq "$OUT" "tk-local" "LOCALFIRST: a local tracker wins over a foreign one (converges with doctor-finding-gate)"
eq "$(head -1 < "$STUB_LOG/list-stores")" "L:" "LOCALFIRST: the ambient store is queried first"
eq "$(grep -c . < "$STUB_LOG/list-stores")" "1" "LOCALFIRST: and a local hit costs exactly one query"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
