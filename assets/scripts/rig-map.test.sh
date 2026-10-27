#!/usr/bin/env bash
# Hermetic test for assets/scripts/rig-map.sh: the listing it prints, the one
# bound it puts on `gc rig list --json`, and the reason it names for every
# listing that does not read. `gc` is a stub on PATH; no live city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/rig-map.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rig-map-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

mkdir -p "$TMP/bin"
export FAKE_GC_LOG="$TMP/gc.log" FAKE_PIDFILE="$TMP/gc.pid"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
printf '%s\n' "$*" >> "$FAKE_GC_LOG"
case "$*" in "rig list --json"|"--city "*" rig list --json") ;; *) echo "stub gc: unexpected call: $*" >&2; exit 64 ;; esac
echo "$$" > "$FAKE_PIDFILE"
case "${FAKE_MODE:-ok}" in
  ok)       printf '{"schema_version":"1","rigs":[{"name":"town","path":"/c","prefix":"lx","hq":true,"suspended":false,"running":true},{"name":"al\001pha","path":"/c/rigs/alpha","prefix":"al","hq":false,"suspended":true}]}\n' ;;
  # gc is one process, so exec: the bound signals gc itself and nothing else.
  slow)     exec sleep 30 ;;
  stderr)   echo "gc rig list: loading city.toml: permission denied" >&2; exit 1 ;;
  jsonerr)  printf '{"schema_version":"1","ok":false,"error":{"code":"config_load_failed","message":"gc rig list: city.toml: bad key"}}\n'; exit 1 ;;
  empty)    exit 0 ;;
  notjson)  echo "warning: stray log line"; printf '{"rigs":[]}\n' ;;
  norigs)   printf '{"schema_version":"1","ok":true}\n' ;;
  rigsobj)  printf '{"rigs":{"name":"town"}}\n' ;;
  stdin)    if read -r _; then echo "stub gc: read the caller's stdin" >&2; exit 65; fi; printf '{"rigs":[]}\n' ;;
esac
GC
chmod +x "$TMP/bin/gc"

run() { OUT=$(PATH="$TMP/bin:$PATH" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }

echo "# a listing that reads"
: > "$FAKE_GC_LOG"
run env FAKE_MODE=ok "$SUT"
eq "$RC" 0 "a listing that reads exits 0"
eq "$ERR" "" "  ... and says nothing on stderr"
eq "$(printf '%s' "$OUT" | jq -r '[.rigs[].name] | join(",")')" "town,alpha" "  ... and prints the rows, a raw control byte dropped"
eq "$(printf '%s' "$OUT" | jq -r '.rigs[1].suspended')" "true" "  ... with each row's fields as gc gave them"
eq "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" 1 "  ... on one line"
eq "$(cat "$FAKE_GC_LOG")" "rig list --json" "  ... from one call to gc rig list --json"

echo "# the one bound"
mkdir -p "$TMP/tobin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'printf "%%s\\n" "$*" > "%s"\nshift 4; exec "$@"\n' "$TMP/to.args"; } > "$TMP/tobin/timeout"
chmod +x "$TMP/tobin/timeout"
run env FAKE_MODE=ok PATH="$TMP/tobin:$TMP/bin:$PATH" "$SUT"
eq "$(cat "$TMP/to.args")" "--foreground -k 5 120 gc rig list --json" "with no GC_RIG_LIST_TIMEOUT the bound is 120s, in this process group"
run env FAKE_MODE=ok GC_RIG_LIST_TIMEOUT=45 PATH="$TMP/tobin:$TMP/bin:$PATH" "$SUT"
eq "$(cat "$TMP/to.args")" "--foreground -k 5 45 gc rig list --json" "GC_RIG_LIST_TIMEOUT sets the bound"

START=$SECONDS
run env FAKE_MODE=slow GC_RIG_LIST_TIMEOUT=1 "$SUT"
eq "$RC" 3 "a listing slower than the bound exits 3"
eq "$OUT" "" "  ... prints nothing on stdout"
has "$ERR" "did not answer within 1s and was killed" "  ... and names the bound it ran out of"
has "$ERR" "GC_RIG_LIST_TIMEOUT=<seconds>" "  ... and the knob that raises it"
[ $((SECONDS - START)) -lt 10 ] && ok "  ... and returns at the bound, not when gc would have" || bad "  ... returned after $((SECONDS - START))s"
if kill -0 "$(cat "$FAKE_PIDFILE")" 2>/dev/null; then bad "  ... and leaves gc running"; else ok "  ... and leaves no gc running"; fi

echo "# a caller's own deadline reaches gc"
rm -f "$FAKE_PIDFILE"
FAKE_MODE=slow PATH="$TMP/bin:$PATH" timeout 2 "$SUT" >/dev/null 2>&1; RC=$?
eq "$RC" 124 "a caller's timeout ends the read"
sleep 1
if [ -s "$FAKE_PIDFILE" ] && ! kill -0 "$(cat "$FAKE_PIDFILE")" 2>/dev/null; then ok "  ... and gc with it"; else bad "  ... and gc outlives it"; fi

echo "# the scratch file that holds gc's stderr"
mkdir -p "$TMP/scratch"
for mode in ok stderr; do
  TMPDIR="$TMP/scratch" FAKE_MODE=$mode PATH="$TMP/bin:$PATH" "$SUT" >/dev/null 2>&1
done
TMPDIR="$TMP/scratch" FAKE_MODE=slow GC_RIG_LIST_TIMEOUT=1 PATH="$TMP/bin:$PATH" "$SUT" >/dev/null 2>&1
TMPDIR="$TMP/scratch" FAKE_MODE=slow PATH="$TMP/bin:$PATH" timeout 2 "$SUT" >/dev/null 2>&1
eq "$(find "$TMP/scratch" -name 'gctk-rig-map.*' | wc -l | tr -d ' ')" 0 \
  "it is removed after a read, a failure, the bound running out, and the caller's deadline"
run env FAKE_MODE=ok TMPDIR="$TMP/absent" "$SUT"
eq "$RC" 0 "with no scratch file to be had, the listing is still read"
eq "$(printf '%s' "$OUT" | jq -r '.rigs | length')" 2 "  ... whole"
run env FAKE_MODE=jsonerr TMPDIR="$TMP/absent" "$SUT"
eq "$RC" 3 "  ... and a listing that fails still exits 3"
has "$ERR" "exited 1: gc rig list: city.toml: bad key" "  ... with the reason gc gave on stdout"
mkdir -p "$TMP/dirmk"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'd="%s/made.$$"; mkdir -p "$d" && printf "%%s\\n" "$d"\n' "$TMP/dirmk"; } > "$TMP/dirmk/mktemp"
chmod +x "$TMP/dirmk/mktemp"
run env FAKE_MODE=ok PATH="$TMP/dirmk:$TMP/bin:$PATH" "$SUT"
eq "$RC" 0 "a scratch path that is not a writable file does not stop the read"

for bound in abc 0 -5 1.5; do
  run env FAKE_MODE=ok GC_RIG_LIST_TIMEOUT="$bound" "$SUT"
  eq "$RC" 2 "GC_RIG_LIST_TIMEOUT='$bound' is refused (exit 2)"
  has "$ERR" "is not a whole number of seconds above 0" "  ... with its reason"
done

echo "# a listing that does not read names why"
run env FAKE_MODE=stderr "$SUT"
eq "$RC" 3 "gc exiting non-zero exits 3"
has "$ERR" "\`gc rig list --json\` exited 1: gc rig list: loading city.toml: permission denied" "  ... carrying gc's exit and its first stderr line"
run env FAKE_MODE=jsonerr "$SUT"
has "$ERR" "exited 1: gc rig list: city.toml: bad key" "a failure stated only in gc's JSON error carries that message"
run env FAKE_MODE=empty "$SUT"
eq "$RC" 3 "gc printing nothing exits 3"
has "$ERR" "exited 0 but printed nothing" "  ... and says so"
run env FAKE_MODE=notjson "$SUT"
eq "$RC" 3 "output that is not JSON exits 3"
has "$ERR" "printed something that is not JSON: warning: stray log line" "  ... and quotes what it printed"
run env FAKE_MODE=norigs "$SUT"
eq "$RC" 3 "JSON with no .rigs exits 3"
has "$ERR" "printed JSON with no '.rigs' array" "  ... and says which field is missing"
run env FAKE_MODE=rigsobj "$SUT"
eq "$RC" 3 "a .rigs that is not an array exits 3"
eq "$OUT" "" "  ... and prints nothing a caller could read as a map"

echo "# gc missing, and no timeout command"
mkdir -p "$TMP/nogc"
for t in bash jq tr sed cut mktemp rm cat env sleep; do ln -sf "$(command -v "$t")" "$TMP/nogc/$t"; done
OUT=$(PATH="$TMP/nogc" "$SUT" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
eq "$RC" 3 "no gc on PATH exits 3"
has "$ERR" "gc is not on PATH" "  ... and says so"
ln -sf "$TMP/bin/gc" "$TMP/nogc/gc"
OUT=$(FAKE_MODE=ok PATH="$TMP/nogc" "$SUT" 2>"$TMP/err"); RC=$?
eq "$RC" 0 "with no timeout command the listing is still read"
eq "$(printf '%s' "$OUT" | "$TMP/nogc/jq" -r '.rigs | length')" 2 "  ... whole"

echo "# the caller's stdin"
OUT=$(printf 'a line the caller still needs\n' | { FAKE_MODE=stdin PATH="$TMP/bin:$PATH" "$SUT" >/dev/null 2>"$TMP/err"; echo "rc=$?"; read -r line; echo "$line"; })
eq "$OUT" "rc=0
a line the caller still needs" "gc reads none of the caller's stdin, so a read inside a while-read loop keeps its input"

echo "# --city"
: > "$FAKE_GC_LOG"
run env FAKE_MODE=ok "$SUT" --city "/a city"
eq "$RC" 0 "--city reads the named city's map"
eq "$(cat "$FAKE_GC_LOG")" "--city /a city rig list --json" "  ... by passing it to gc whole"

echo "# usage"
run "$SUT" --json
eq "$RC" 2 "an argument it does not take is a usage error (exit 2)"
has "$ERR" "usage: rig-map.sh" "  ... with the usage line"
for args in "--city" "--city ''" "--city /c extra"; do
  eval "set -- $args"
  run "$SUT" "$@"
  eq "$RC" 2 "rig-map.sh $args is a usage error (exit 2)"
done

echo
echo "rig-map: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
