#!/usr/bin/env bash
# Hermetic test for tmux-new-subject.sh (tk-amc65l.1), the prefix+A wrapper that
# opens `gc-helm engage --new-subject` in a fresh tmux window. gc-helm.sh is
# stubbed, so no live city or gc is needed; the test proves the wrapper hands
# engage the right verb and flags and wires the city env the binding baked in.
#   (RUN)    it invokes gc-helm.sh engage --new-subject --no-attach
#   (CITY)   it exports the baked --city-path as GC_CITY_PATH for gc
#   (NOCITY) with no --city-path it still runs (gc falls back to its own default)
#   (NOCFG)  a missing config-dir is refused (exit 1)
#   (NOHELM) a config-dir with no gc-helm.sh is refused (exit 1)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/tmux-new-subject.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-tmux-new-subject-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "tmux-new-subject.sh present" || bad "tmux-new-subject.sh missing at $SCRIPT"

# Hermetic: the wrapper passes an AMBIENT GC_CITY_PATH through when no --city-path
# is given, so clear it here or the suite's own env leaks into the NOCITY case.
unset GC_CITY_PATH || true

# A config-dir carrying a gc-helm.sh stub that echoes its env and argv.
CFG="$TMP/cfg"
mkdir -p "$CFG/assets/scripts"
cat > "$CFG/assets/scripts/gc-helm.sh" <<'STUB'
#!/bin/sh
echo "CITY=${GC_CITY_PATH-<unset>}"
echo "ARGS=$*"
STUB
chmod +x "$CFG/assets/scripts/gc-helm.sh"

echo "# it runs engage --new-subject --no-attach, exporting the baked city path"
OUT="$(sh "$SCRIPT" "$CFG" --city-path /my/city </dev/null 2>&1)"
has "$OUT" "ARGS=engage --new-subject --no-attach" "(RUN) invokes gc-helm engage --new-subject --no-attach"
has "$OUT" "CITY=/my/city" "(CITY) exports --city-path as GC_CITY_PATH for gc"

echo "# with no --city-path it still runs (gc uses its own default)"
OUT="$(sh "$SCRIPT" "$CFG" </dev/null 2>&1)"
has "$OUT" "ARGS=engage --new-subject --no-attach" "(NOCITY) still invokes engage"
has "$OUT" "CITY=<unset>" "(NOCITY) leaves GC_CITY_PATH unset rather than exporting an empty one"

echo "# a missing config-dir is refused"
set +e
sh "$SCRIPT" </dev/null >/dev/null 2>&1; RC=$?
set -e
eq "$RC" 1 "(NOCFG) missing config-dir exits 1"

echo "# a config-dir with no gc-helm.sh is refused"
set +e
OUT="$(sh "$SCRIPT" "$TMP/empty" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 1 "(NOHELM) a config-dir without gc-helm.sh exits 1"
has "$OUT" "gc-helm.sh not found" "(NOHELM) …naming the fault"

echo
echo "tmux-new-subject: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
