#!/usr/bin/env bash
# converse-close-out.test.sh — the step-2 silent close (assets/scripts/converse-close-out.sh):
# a visit whose premise died (moot) or holds but needs no human (benign) has its
# reading appended to the subject, its outcome stamped on the visit, and the
# visit closed — with no takeaway and nothing posted. This drives the script
# against a stub gc that records every write.
#
# Hermetic: stubs gc, reads the repo only; no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/converse-close-out.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing '$2' in $(cat "$3")"; fi; }

[ -r "$SUT" ] || { printf 'converse-close-out: cannot read %s\n' "$SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'converse-close-out: jq is required\n' >&2; exit 1; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-close-out-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; LOG="$TMPD/log"
mkdir -p "$BIN"

# A stub gc recording every write: `bd update`/`bd close` append their args to
# the log; `bd show` returns a visit carrying the outcome so the readback the
# script runs between the stamp and the close succeeds.
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 2
case "${2:-}" in
    update) printf 'update %s\n' "$*" >>"$LOG" ;;
    close)  printf 'close %s\n' "$*" >>"$LOG" ;;
    show)   jq -nc '[{id:"v-x",metadata:{"gc.outcome":"moot"}}]' ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SUT" ] && ok "converse-close-out.sh is executable" || bad "converse-close-out.sh is executable" "chmod +x it"
bash -n "$SUT" && ok "converse-close-out.sh: valid bash" || bad "converse-close-out.sh: valid bash" "bash -n failed"

echo "── a moot close records to the subject, stamps the visit, and closes it ──"
: >"$LOG"
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" VISIT=v-x SUBJECT=tk-sub bash "$SUT" moot "the frontier was routed" ) || RC=$?
is "it exits 0" "$RC" "0"
has "the reading is appended to the subject, keyed by outcome" \
    'update tk-sub --append-notes visit v-x closed moot: the frontier was routed' "$LOG"
has "the outcome is stamped on the visit" 'update v-x --set-metadata gc.outcome=moot' "$LOG"
has "the visit is closed" 'close v-x' "$LOG"

echo "── every field is required (fail closed on a missing one) ──"
( PATH="$BIN:$PATH" LOG="$LOG" SUBJECT=tk-sub bash "$SUT" moot detail >/dev/null 2>&1 ); is "a missing VISIT is refused" "$?" "2"
( PATH="$BIN:$PATH" LOG="$LOG" VISIT=v-x bash "$SUT" moot detail >/dev/null 2>&1 ); is "a missing SUBJECT is refused" "$?" "2"
( PATH="$BIN:$PATH" LOG="$LOG" VISIT=v-x SUBJECT=tk-sub bash "$SUT" >/dev/null 2>&1 ); is "a missing outcome word is refused" "$?" "2"
( PATH="$BIN:$PATH" LOG="$LOG" VISIT=v-x SUBJECT=tk-sub bash "$SUT" moot >/dev/null 2>&1 ); is "a missing reading is refused" "$?" "2"

echo
echo "converse-close-out: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
