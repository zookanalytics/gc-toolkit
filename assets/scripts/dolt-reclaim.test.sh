#!/usr/bin/env bash
# Hermetic test for assets/scripts/dolt-reclaim.sh — the size-triggered Dolt
# reclaim pass. A stubbed `gc` on PATH supplies the database list, the compact
# help (with or without --gc-only), the health probe, and the compact itself
# (logging its args and simulating the freed space by emptying the fixture
# noms dir). No live city, no real dolt. Fixture noms dirs are small real files
# crossed by a small MiB threshold, so the whole suite stays fast.
#
# The load-bearing assertion across every case: a reclaim is ONLY ever
# `gc dolt compact --gc-only --only-db <db>`, and a bare flatten is never run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/dolt-reclaim.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-dolt-reclaim-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { if grep -qF -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (missing '$2' in: $1)"; fi; }
hasnt() { if grep -qF -- "$2" <<< "$1"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

# --- the stub gc -------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"
STUB_DOLT_ROOT="$TMP/dolt"; mkdir -p "$STUB_DOLT_ROOT"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
sub="${1:-} ${2:-}"
case "$sub" in
  "service list")
    # The city resolver's fallback. A bare answer (STUB_NO_CITY) is how the test
    # drives the "no city resolvable" refusal.
    if [ -n "${STUB_NO_CITY:-}" ]; then printf '{"services":[]}'
    else printf '{"city_path":"%s","services":[]}' "${STUB_CITY_PATH:-/fixture-city}"; fi ;;
  "dolt list")
    cat "$STUB_DOLT_LIST" ;;
  "dolt health")
    for a in "$@"; do case "$a" in --city | --city=*) echo "gc dolt health: unknown flag: --city" >&2; exit 1 ;; esac; done
    [ -n "${STUB_HEALTH_SLEEP:-}" ] && sleep "$STUB_HEALTH_SLEEP"
    if [ -n "${STUB_HEALTH:-}" ]; then printf '%s' "$STUB_HEALTH"
    else printf '%s' '{"server":{"reachable":true,"latency_ms":120}}'; fi
    exit "${STUB_HEALTH_RC:-0}" ;;
  "dolt compact")
    shift 2
    if [ "${1:-}" = "--help" ]; then
      echo "gc dolt compact — flatten/reclaim"
      [ -z "${STUB_NO_GC_ONLY:-}" ] && echo "  --gc-only   reclaim via DOLT_GC('--full')"
      echo "  --only-db <name>"
      echo "  --dry-run"
      exit 0
    fi
    # The deployed compact leaf rejects --city; model that so a pass that reaches
    # for the flag instead of the environment fails here as it would in a city.
    for a in "$@"; do case "$a" in --city | --city=*) echo "compact: unknown flag --city (supported: --gc-only, --only-db <name>, --dry-run, --skip-fetch)" >&2; exit 2 ;; esac; done
    # Record the city conveyed by environment, so the test can prove it reached
    # the leaf without a flag.
    printf '%s\n' "${GC_CITY_PATH:-<unset>}" >> "${CITY_LOG:?}"
    # An actual compact. Log the verbatim args so the test can prove every
    # invocation carries --gc-only, then simulate the reclaim.
    printf '%s\n' "$*" >> "${COMPACT_LOG:?}"
    db=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --only-db) db="${2:-}"; shift 2 ;;
        --only-db=*) db="${1#--only-db=}"; shift ;;
        *) shift ;;
      esac
    done
    [ -n "${STUB_COMPACT_SLEEP:-}" ] && sleep "$STUB_COMPACT_SLEEP"
    if [ -n "${STUB_COMPACT_FAIL_DB:-}" ] && [ "$db" = "$STUB_COMPACT_FAIL_DB" ]; then
      echo "stub: $db is quarantined" >&2
      exit "${STUB_COMPACT_FAIL_RC:-1}"
    fi
    [ -n "$db" ] && rm -rf "${STUB_DOLT_ROOT:?}/$db/.dolt/noms"/* 2>/dev/null
    exit 0 ;;
  *)
    exit 0 ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
export STUB_DOLT_ROOT
# The city must come from the stubbed `gc service list`, never the ambient
# session, so every gc call the script makes is the stub's to answer.
unset GC_CITY_PATH GC_CITY GC_CITY_ROOT GC_RIG 2>/dev/null || true

# --- fixtures ----------------------------------------------------------------
# make_db <name> <noms_bytes>: a database dir with a noms file of that size.
# A size of -1 means "no noms directory" (an unmanaged/absent store).
make_db() {
  local name="$1" bytes="$2" d="$STUB_DOLT_ROOT/$1"
  rm -rf "$d"; mkdir -p "$d/.dolt"
  if [ "$bytes" != "-1" ]; then
    mkdir -p "$d/.dolt/noms"
    head -c "$bytes" /dev/zero > "$d/.dolt/noms/data"
  fi
}
# write_list <name>...: the TSV `gc dolt list` returns, name<TAB>path/ .
write_list() {
  : > "$TMP/list.tsv"
  local n
  for n in "$@"; do printf '%s\t%s/\n' "$n" "$STUB_DOLT_ROOT/$n" >> "$TMP/list.tsv"; done
}
export STUB_DOLT_LIST="$TMP/list.tsv"

OVER=$((3 * 1024 * 1024))     # 3 MiB — over a 1 MiB threshold
UNDER=$((64 * 1024))          # 64 KiB — under it
export GC_DOLT_RECLAIM_THRESHOLD_MIB=1

reset_case() {
  COMPACT_LOG="$TMP/compact.log"; : > "$COMPACT_LOG"; export COMPACT_LOG
  CITY_LOG="$TMP/city.log"; : > "$CITY_LOG"; export CITY_LOG
  export STUB_HEALTH="" STUB_HEALTH_RC=0 STUB_HEALTH_SLEEP="" STUB_NO_GC_ONLY=""
  export STUB_COMPACT_FAIL_DB="" STUB_COMPACT_FAIL_RC=1 STUB_COMPACT_SLEEP=""
  export STUB_NO_CITY="" STUB_CITY_PATH="/fixture-city"
  unset GC_DOLT_RECLAIM_BUDGET GC_DOLT_RECLAIM_HEALTH_TIMEOUT 2>/dev/null || true
}
BASH_BIN="$(command -v bash)"
run() { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }
compact_lines() { awk 'END { print NR + 0 }' "$COMPACT_LOG" 2>/dev/null || echo 0; }
# Every logged compact must carry --gc-only; a line without it is a bare flatten.
every_compact_is_gc_only() {
  [ ! -s "$COMPACT_LOG" ] && return 0
  ! grep -vq -- '--gc-only' "$COMPACT_LOG"
}

# --- usage guards ------------------------------------------------------------
reset_case
run --bogus
eq "$RC" "2" "an unknown argument exits 2"

mkdir -p "$TMP/nowhere"
OUT=$(PATH="$TMP/nowhere" "$BASH_BIN" "$SUT" 2>&1); RC=$?
eq "$RC" "2" "no gc on PATH exits 2"
has "$OUT" "gc is not on PATH" "  ... and says so"

reset_case
write_list   # empty
run
eq "$RC" "2" "an empty database list exits 2"

# --- a city that resolves nowhere is a loud refusal, not a silent no-op ------
reset_case
make_db fat "$OVER"; write_list fat
export STUB_NO_CITY=1
run
eq "$RC" "2" "a city that resolves nowhere exits 2"
has "$OUT$ERR" "cannot resolve the city" "  ... and says why, rather than silently reclaiming nothing"
eq "$(compact_lines)" "0" "  ... and never touches a store"

# --- stale dolt pack: no --gc-only is a HARD STOP, never a bare flatten ------
reset_case
make_db big "$OVER"; write_list big
export STUB_NO_GC_ONLY=1
run
eq "$RC" "2" "a deployed compact without --gc-only exits 2"
has "$OUT$ERR" "no --gc-only" "  ... and names the missing flag"
eq "$(compact_lines)" "0" "  ... and never invokes compact at all"
export STUB_NO_GC_ONLY=""

# --- nothing over the line ---------------------------------------------------
reset_case
make_db a "$UNDER"; make_db b "$UNDER"; write_list a b
run
eq "$RC" "0" "nothing over the line exits 0"
has "$OUT" "nothing to reclaim" "  ... and says nothing to reclaim"
eq "$(compact_lines)" "0" "  ... and runs no compact"
has "$OUT" "a: " "  ... and still reports every store's size"
has "$OUT" "b: " "  ... (both of them)"

# --- one store over: the reclaim is --gc-only --only-db ----------------------
reset_case
make_db a "$UNDER"; make_db fat "$OVER"; write_list a fat
run
eq "$RC" "0" "a reclaimable store exits 0"
eq "$(compact_lines)" "1" "  ... runs exactly one compact"
has "$(cat "$COMPACT_LOG")" "--gc-only" "  ... with --gc-only"
has "$(cat "$COMPACT_LOG")" "--only-db fat" "  ... scoped to the over-threshold store"
hasnt "$(cat "$COMPACT_LOG")" "--only-db a" "  ... and NOT the under-threshold one"
if every_compact_is_gc_only; then ok "  ... no bare flatten was issued"; else bad "a bare flatten was issued"; fi
has "$OUT" "fat reclaimed" "  ... and reports the reclaim as measured bytes"
has "$OUT" "1 reclaimed, 0 failed" "  ... with a one-store summary"

# --- the city reaches the dolt leaves by env, never as a --city flag ---------
# The deployed `gc dolt compact` and `gc dolt health` reject --city (only
# `gc dolt list` honors it), so the pass conveys the resolved city through the
# environment. The stub leaves refuse --city exactly as the real ones do, so a
# green reclaim here proves the flag is gone and the env carries the city.
reset_case
make_db fat "$OVER"; write_list fat
run
eq "$RC" "0" "the reclaim succeeds when the dolt leaves refuse --city"
hasnt "$(cat "$COMPACT_LOG")" "--city" "  ... compact is invoked without --city"
eq "$(cat "$CITY_LOG")" "/fixture-city" "  ... and the resolved city reaches compact by GC_CITY_PATH"
has "$OUT" "fat reclaimed" "  ... and the store is reclaimed"

# --- dry run: plan only, never a compact -------------------------------------
reset_case
make_db fat "$OVER"; write_list fat
run --dry-run
eq "$RC" "0" "dry-run exits 0"
has "$OUT" "DRY RUN" "  ... announces the dry run"
has "$OUT" "would run 'gc dolt compact --gc-only --only-db fat'" "  ... names the exact command"
eq "$(compact_lines)" "0" "  ... and mutates nothing"

# --- degraded data plane defers (a full GC must not pile on) -----------------
reset_case
make_db fat "$OVER"; write_list fat
export STUB_HEALTH='{"server":{"reachable":false}}'
run
eq "$RC" "0" "an unreachable server defers, exit 0"
has "$OUT" "deferred" "  ... says deferred"
has "$OUT" "unreachable" "  ... names the reason"
eq "$(compact_lines)" "0" "  ... and runs no compact"

reset_case
make_db fat "$OVER"; write_list fat
export STUB_HEALTH='{"server":{"reachable":true,"latency_ms":9000}}'
run
eq "$RC" "0" "an overloaded server (latency>5000) defers"
has "$OUT" "latency" "  ... names the latency"
eq "$(compact_lines)" "0" "  ... and runs no compact"

reset_case
make_db fat "$OVER"; write_list fat
export GC_DOLT_RECLAIM_HEALTH_TIMEOUT=1 STUB_HEALTH_SLEEP=2
run
eq "$RC" "0" "a health probe that outruns its bound defers"
has "$OUT" "too slow" "  ... says the plane is too slow"
eq "$(compact_lines)" "0" "  ... and runs no compact"

# --- a compact that fails surfaces as exit 1 ---------------------------------
reset_case
make_db fat "$OVER"; write_list fat
export STUB_COMPACT_FAIL_DB=fat STUB_COMPACT_FAIL_RC=3
run
eq "$RC" "1" "a failed reclaim exits 1"
has "$OUT$ERR" "fat FAILED" "  ... names the store that failed"
has "$OUT" "0 reclaimed, 1 failed" "  ... and counts it in the summary"

# --- several over the line: each reclaimed, each --gc-only -------------------
reset_case
make_db fat1 "$OVER"; make_db small "$UNDER"; make_db fat2 "$OVER"; write_list fat1 small fat2
run
eq "$RC" "0" "two reclaimable stores exit 0"
eq "$(compact_lines)" "2" "  ... run two compacts"
if every_compact_is_gc_only; then ok "  ... both --gc-only"; else bad "a bare flatten slipped in"; fi
has "$OUT" "2 reclaimed, 0 failed" "  ... summarized as two"

# --- a store with no noms directory is skipped, not failed -------------------
reset_case
make_db nonoms "-1"; make_db fat "$OVER"; write_list nonoms fat
run
eq "$RC" "0" "a store missing its noms dir does not fail the pass"
has "$OUT" "no noms directory" "  ... it is reported as skipped"
eq "$(compact_lines)" "1" "  ... and only the real store is reclaimed"

# --- budget stops STARTING new reclaims, never interrupts a running one ------
reset_case
make_db fatA "$OVER"; make_db fatB "$OVER"; write_list fatA fatB
export GC_DOLT_RECLAIM_BUDGET=1 STUB_COMPACT_SLEEP=2
run
eq "$RC" "0" "a spent budget still exits 0"
eq "$(compact_lines)" "1" "  ... the first store is reclaimed"
has "$OUT" "deferred — 1s budget spent" "  ... and the second is deferred to the next pass"

echo "----"
echo "dolt-reclaim.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
