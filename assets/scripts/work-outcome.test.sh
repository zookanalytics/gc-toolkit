#!/usr/bin/env bash
# work-outcome.test.sh — the shared visit work-outcome stamp
# (assets/scripts/work-outcome.sh). work_outcome_noop stamps gc.work_outcome=no-op
# in a write of its own, never over a work outcome the bead already records,
# reads it back and repairs a dropped write once, writes nothing to a bead that
# did not read, and returns 0 whatever the store does, so no caller's close
# waits on it.
#
# Every case runs under each shell a caller sources the lib from: sh (gc-helm.sh
# and converse-claim.sh are /bin/sh scripts), dash when present (CI's /bin/sh),
# and bash under `set -euo pipefail` (bead-rehome.sh), where an unguarded failure
# would abort the caller.
#
# Hermetic: a stub store script stands in for the caller's bd command; no city,
# no network.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/work-outcome.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }

[ -r "$LIB" ] || { printf 'work-outcome: cannot read %s\n' "$LIB" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'work-outcome: jq is required\n' >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-outcome-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
STORE="$TMP/store"; DRIVE="$TMP/drive.sh"
export STORE_DIR="$TMP/beads" STORE_LOG="$TMP/log"
mkdir -p "$STORE_DIR"

# The stub store: `[--db <dir>] show|update <bead> ...`, logging each call's argv.
# The optional --db pair stands in for a caller's store pin (bead-rehome.sh's
# bd_at). A bead's gc.work_outcome lives in $STORE_DIR/<bead>.wo; no file means
# no key. Knobs:
#   STORE_UNREAD=1  show answers a bare error object and exits 1
#   STORE_REFUSE=1  update exits 1 and writes nothing
#   STORE_DROP=<n>  the first n updates exit 0 and write nothing (the silent drop)
#   STORE_CTRL=1    show carries a raw C0 byte inside a string, invalid JSON
#                   until scrubbed
cat >"$STORE" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STORE_LOG"
[ "${1:-}" = "--db" ] && shift 2
verb="${1:-}"; bead="${2:-}"
f="$STORE_DIR/$bead.wo"
case "$verb" in
    show)
        [ -n "${STORE_UNREAD:-}" ] && { printf '{"error":"no issues found"}\n'; exit 1; }
        meta='{}'
        [ -f "$f" ] && meta=$(jq -nc --arg w "$(cat "$f")" '{"gc.work_outcome":$w}')
        if [ -n "${STORE_CTRL:-}" ]; then
            printf '[{"id":"%s","notes":"line one\001\tline two","metadata":%s}]\n' "$bead" "$meta"
        else
            printf '[{"id":"%s","metadata":%s}]\n' "$bead" "$meta"
        fi ;;
    update)
        [ -n "${STORE_REFUSE:-}" ] && exit 1
        n=$(cat "$STORE_DIR/.drops" 2>/dev/null || echo 0)
        if [ "$n" -lt "${STORE_DROP:-0}" ]; then echo $((n + 1)) >"$STORE_DIR/.drops"; exit 0; fi
        for a in "$@"; do
            case "$a" in gc.work_outcome=*) printf '%s' "${a#gc.work_outcome=}" >"$f" ;; esac
        done ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$STORE"

# The caller: source the lib, stamp, then report the status and a line after the
# call, so a run that aborted its caller is visible. STRICT=1 runs it the way
# bead-rehome.sh does, under errexit, nounset and (in bash) pipefail.
cat >"$DRIVE" <<'DRIVE'
lib="$1"; shift
if [ -n "${STRICT:-}" ]; then
    set -eu
    [ -n "${BASH_VERSION:-}" ] && set -o pipefail
fi
. "$lib" || { echo "cannot source $lib"; exit 90; }
work_outcome_noop "$@"
echo "rc=$?"
echo "after"
DRIVE

SHELLS="sh bash-strict"
command -v dash >/dev/null 2>&1 && SHELLS="$SHELLS dash"

reset() { rm -f "$STORE_DIR"/* "$STORE_DIR/.drops"; : >"$STORE_LOG"; }
# stamp <shell> <args to work_outcome_noop...>
OUT=""
stamp() {
    _sh="$1"; shift
    case "$_sh" in
        bash-strict) OUT=$(STRICT=1 bash "$DRIVE" "$LIB" "$@" 2>&1) ;;
        *)           OUT=$("$_sh" "$DRIVE" "$LIB" "$@" 2>&1) ;;
    esac
}
updates() { grep -cE '(^| )update ' "$STORE_LOG" || true; }
value()   { cat "$STORE_DIR/$1.wo" 2>/dev/null || true; }
carried_on() { is "$1: the caller carries on past the call" "$OUT" "rc=0
after"; }

echo "── the lib parses in every shell that sources it ──"
sh -n "$LIB" && ok "valid sh" || bad "valid sh" "sh -n failed"
bash -n "$LIB" && ok "valid bash" || bad "valid bash" "bash -n failed"
if command -v dash >/dev/null 2>&1; then
    dash -n "$LIB" && ok "valid dash" || bad "valid dash" "dash -n failed"
fi

for SH in $SHELLS; do
    echo "── $SH ──"

    reset
    stamp "$SH" b-1 "$STORE"
    carried_on "$SH unstamped"
    is "$SH: an unstamped bead gets gc.work_outcome=no-op" "$(value b-1)" "no-op"
    is "$SH: …in one write, read back once" "$(updates)" "1"

    reset; printf 'abandoned' >"$STORE_DIR/b-1.wo"
    stamp "$SH" b-1 "$STORE"
    carried_on "$SH recorded"
    is "$SH: a work outcome the bead records is left as it is" "$(value b-1)" "abandoned"
    is "$SH: …and nothing is written over it" "$(updates)" "0"

    reset
    STORE_DROP=1 stamp "$SH" b-1 "$STORE"
    carried_on "$SH dropped once"
    is "$SH: a write that exits 0 and lands nothing is repaired" "$(value b-1)" "no-op"
    is "$SH: …by one more write" "$(updates)" "2"

    reset
    STORE_DROP=9 stamp "$SH" b-1 "$STORE"
    carried_on "$SH always dropped"
    is "$SH: a store that never keeps it is written twice, not looped on" "$(updates)" "2"
    is "$SH: …and the key stays unrecorded" "$(value b-1)" ""

    reset
    STORE_REFUSE=1 stamp "$SH" b-1 "$STORE"
    carried_on "$SH refused"
    is "$SH: a refused write records nothing" "$(value b-1)" ""

    reset
    STORE_UNREAD=1 stamp "$SH" b-1 "$STORE"
    carried_on "$SH unread"
    is "$SH: a bead that does not read is not written" "$(updates)" "0"

    reset
    STORE_CTRL=1 stamp "$SH" b-1 "$STORE"
    carried_on "$SH control bytes"
    is "$SH: a payload with a raw control byte in a string still reads, scrubbed" "$(value b-1)" "no-op"
    is "$SH: …and is written once" "$(updates)" "1"

    reset
    stamp "$SH" b-1 "$STORE" --db "$TMP/pinned"
    carried_on "$SH pinned"
    is "$SH: the caller's command and its store pin reach the read" \
        "$(grep -c "^--db $TMP/pinned show b-1 --json$" "$STORE_LOG")" "2"
    is "$SH: …and the write" \
        "$(grep -c "^--db $TMP/pinned update b-1 --set-metadata gc.work_outcome=no-op$" "$STORE_LOG")" "1"

    reset
    stamp "$SH" b-1
    carried_on "$SH no command"
    stamp "$SH"
    carried_on "$SH no arguments"
    is "$SH: a call missing its bead or command reaches no store" "$(wc -l <"$STORE_LOG" | tr -d ' ')" "0"
done

echo
echo "work-outcome: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
