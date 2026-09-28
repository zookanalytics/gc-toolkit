#!/usr/bin/env bash
# visit-close.test.sh — the shared guarded visit close (assets/scripts/visit-close.sh):
# it appends the reading to the subject when one is named, stamps gc.outcome and
# gc.outcome_reason on the visit, reads BOTH back, and only then closes — with the
# reason as the bead's close_reason. A missing field, a stamp that will not read
# back, and a close that does not take are each refused with a distinct exit code.
#
# Hermetic: stubs gc, reads the repo only; no city, no network.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/visit-close.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing '$2' in $(cat "$3")"; fi; }
hasnt() { if grep -qF -- "$2" "$3"; then bad "$1" "found '$2'"; else ok "$1"; fi; }

[ -r "$SUT" ] || { printf 'visit-close: cannot read %s\n' "$SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'visit-close: jq is required\n' >&2; exit 1; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-visit-close-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; LOG="$TMPD/log"
mkdir -p "$BIN"

# A stub gc that records every write and reflects it back, so the readback that
# gates the close reads exactly what was stamped. Failure knobs:
#   FAIL_STAMP  the update exits 0 but records nothing (the silent drop)
#   FAIL_CLOSE  the close logs but the status never becomes closed
#   NEED_FORCE  a plain close is refused; only a --force close takes
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 2
O="$LOG.o"; R="$LOG.r"; ST="$LOG.st"
case "${2:-}" in
    update)
        printf 'update %s\n' "$*" >>"$LOG"
        [ -n "${FAIL_STAMP:-}" ] && exit 0
        for a in "$@"; do
            case "$a" in
                gc.outcome=*)        printf '%s' "${a#gc.outcome=}" >"$O" ;;
                gc.outcome_reason=*) printf '%s' "${a#gc.outcome_reason=}" >"$R" ;;
            esac
        done ;;
    close)
        forced=0; for a in "$@"; do [ "$a" = "--force" ] && forced=1; done
        if [ -n "${NEED_FORCE:-}" ] && [ "$forced" -eq 0 ]; then
            printf 'close-refused %s\n' "$*" >>"$LOG"; exit 1
        fi
        printf 'close %s\n' "$*" >>"$LOG"
        [ -n "${FAIL_CLOSE:-}" ] || printf 'closed' >"$ST" ;;
    show)   jq -nc \
              --arg o "$(cat "$O" 2>/dev/null)" \
              --arg r "$(cat "$R" 2>/dev/null)" \
              --arg s "$(cat "$ST" 2>/dev/null)" \
              '[{id:"v-x",status:(if $s=="" then "open" else $s end),metadata:{"gc.outcome":$o,"gc.outcome_reason":$r}}]' ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"

reset() { : >"$LOG"; rm -f "$LOG.o" "$LOG.r" "$LOG.st"; }

echo "── shipped executable and syntactically valid ──"
[ -x "$SUT" ] && ok "visit-close.sh is executable" || bad "visit-close.sh is executable" "chmod +x it"
bash -n "$SUT" && ok "visit-close.sh: valid bash" || bad "visit-close.sh: valid bash" "bash -n failed"

echo "── every required field is refused when missing (fail closed) ──"
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --outcome moot --reason r >/dev/null 2>&1 ); is "no --visit is refused" "$?" "2"
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --visit v-x --reason r >/dev/null 2>&1 ); is "no --outcome is refused" "$?" "2"
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --visit v-x --outcome moot >/dev/null 2>&1 ); is "no --reason is refused" "$?" "2"

echo "── the happy path: subject note, both stamps, close carrying the reason ──"
reset; RC=0
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --visit v-x --subject tk-sub \
    --outcome moot --reason "premise died, subject already closed" ) || RC=$?
is "it exits 0" "$RC" "0"
has "the reading is appended to the subject" \
    'update tk-sub --append-notes visit v-x closed moot: premise died, subject already closed' "$LOG"
has "the outcome word is stamped" 'set-metadata gc.outcome=moot' "$LOG"
has "the board-visible reason is stamped" 'set-metadata gc.outcome_reason=premise died, subject already closed' "$LOG"
has "the close carries outcome+reason as its close_reason" \
    'close v-x --reason moot: premise died, subject already closed' "$LOG"

echo "── without --subject nothing is written to a subject ──"
reset; RC=0
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --visit v-x --outcome benign --reason "known acceptable state" ) || RC=$?
is "it exits 0" "$RC" "0"
hasnt "no subject append happens" '--append-notes' "$LOG"
has "the visit is still stamped and closed" 'close v-x --reason benign: known acceptable state' "$LOG"

echo "── a stamp that will not read back refuses the close (exit 3) ──"
reset; RC=0
( PATH="$BIN:$PATH" LOG="$LOG" FAIL_STAMP=1 bash "$SUT" --visit v-x --outcome moot --reason r >/dev/null 2>&1 ) || RC=$?
is "it exits 3" "$RC" "3"
hasnt "the visit is NOT closed" 'close v-x' "$LOG"

echo "── a close that does not take is reported (exit 4) ──"
reset; RC=0
( PATH="$BIN:$PATH" LOG="$LOG" FAIL_CLOSE=1 bash "$SUT" --visit v-x --outcome moot --reason r >/dev/null 2>&1 ) || RC=$?
is "it exits 4" "$RC" "4"

echo "── --force closes over a holder's claim; without it a refused close fails ──"
reset; RC=0
( PATH="$BIN:$PATH" LOG="$LOG" NEED_FORCE=1 bash "$SUT" --visit v-x --outcome dismissed --reason "operator ended it" --force ) || RC=$?
is "with --force it exits 0" "$RC" "0"
has "the forced close is the one that took" 'close v-x --reason dismissed: operator ended it --force' "$LOG"
reset; RC=0
( PATH="$BIN:$PATH" LOG="$LOG" NEED_FORCE=1 bash "$SUT" --visit v-x --outcome dismissed --reason "operator ended it" >/dev/null 2>&1 ) || RC=$?
is "without --force a refused close is not silently a success" "$RC" "4"

echo
echo "visit-close: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
