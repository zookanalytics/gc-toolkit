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

# A stub gc that records every write and reflects it back PER BEAD ID, so the
# readback that gates the close reads exactly what was stamped — and the fold
# hold-transfer (to a second bead, the holder) reads back independently of the
# folded visit. Metadata is kept per id in "$LOG.m/<id>.json", status in
# "$LOG.m/<id>.status". Failure knobs:
#   FAIL_STAMP  any update exits 0 but records nothing (the silent drop)
#   FAIL_XFER   an update carrying pr_number exits 0 but records nothing (the
#               fold hold-transfer's silent drop)
#   FAIL_CLOSE  the close logs but the status never becomes closed
#   NEED_FORCE  a plain close is refused; only a --force close takes
#   FAIL_DEP    an edge write is refused (the holder cannot be joined)
# The anchor graph reads answer an anchor with no children yet, and an edge
# write is logged as "dep add <child> <anchor> ...".
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 2
sub="${2:-}"; id="${3:-}"; MDIR="$LOG.m"
case "$sub" in
    list) echo '[]' ;;
    dep)
        case "$id" in
            list) echo '[]' ;;
            add)
                printf 'dep %s\n' "${*:3}" >>"$LOG"
                [ -z "${FAIL_DEP:-}" ] || exit 1 ;;
            *) exit 2 ;;
        esac ;;
    update)
        printf 'update %s\n' "$*" >>"$LOG"
        [ -n "${FAIL_STAMP:-}" ] && exit 0
        case "${FAIL_XFER:-}" in "") ;; *) case "$*" in *pr_number=*) exit 0 ;; esac ;; esac
        mkdir -p "$MDIR"; f="$MDIR/$id.json"; [ -f "$f" ] || printf '{}' >"$f"
        prev=""
        for a in "$@"; do
            if [ "$prev" = "--set-metadata" ]; then
                k="${a%%=*}"; v="${a#*=}"
                t=$(jq -c --arg k "$k" --arg v "$v" '.[$k]=$v' "$f") && printf '%s' "$t" >"$f"
            fi
            prev="$a"
        done ;;
    close)
        forced=0; for a in "$@"; do [ "$a" = "--force" ] && forced=1; done
        if [ -n "${NEED_FORCE:-}" ] && [ "$forced" -eq 0 ]; then
            printf 'close-refused %s\n' "$*" >>"$LOG"; exit 1
        fi
        printf 'close %s\n' "$*" >>"$LOG"
        [ -n "${FAIL_CLOSE:-}" ] || { mkdir -p "$MDIR"; printf 'closed' >"$MDIR/$id.status"; } ;;
    show)
        f="$MDIR/$id.json"; m='{}'; [ -f "$f" ] && m=$(cat "$f")
        s="open"; [ -f "$MDIR/$id.status" ] && s=$(cat "$MDIR/$id.status")
        jq -nc --arg id "$id" --arg s "$s" --argjson m "$m" \
          '[{id:$id,status:$s,metadata:$m}]' ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"

reset() { : >"$LOG"; rm -rf "$LOG.m"; }
# Pre-seed a metadata key on a bead, the way an earlier write would have left it.
seed_meta() { # <id> <key> <value>
  mkdir -p "$LOG.m"; local f="$LOG.m/$1.json"; [ -f "$f" ] || printf '{}' >"$f"
  local t; t=$(jq -c --arg k "$2" --arg v "$3" '.[$k]=$v' "$f") && printf '%s' "$t" >"$f"
}
meta_of() { # <id> <key> — the live stub value, for an assertion
  PATH="$BIN:$PATH" LOG="$LOG" gc bd show "$1" --json | jq -r --arg k "$2" '.[0].metadata[$k] // ""'
}

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

echo "── fold: the merge-hold keys move to the holder, then the folded visit closes ──"
reset
seed_meta v-x pr_number 559
seed_meta v-x pr_url https://github.com/o/r/pull/559
seed_meta v-x anchor_bead tk-anchor
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --visit v-x --subject tk-sub --into v-hold \
    --outcome folded --reason "folded into v-hold" ) || RC=$?
is "a fold that moves the hold exits 0" "$RC" "0"
has "pr_number is stamped on the holder" 'update v-hold --set-metadata pr_number=559' "$LOG"
is "the holder carries pr_number after the fold" "$(meta_of v-hold pr_number)" "559"
is "the holder carries pr_url after the fold" "$(meta_of v-hold pr_url)" "https://github.com/o/r/pull/559"
is "the holder carries anchor_bead after the fold" "$(meta_of v-hold anchor_bead)" "tk-anchor"
has "the holder is joined to the anchor by its edge" 'dep add v-hold tk-anchor --type related' "$LOG"
has "the folded visit closes" 'close v-x --reason folded: folded into v-hold' "$LOG"

echo "── fold: a holder that cannot be joined to the anchor still takes the merge hold, without anchor_bead ──"
reset
seed_meta v-x pr_number 559
seed_meta v-x anchor_bead tk-anchor
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" FAIL_DEP=1 bash "$SUT" --visit v-x --into v-hold \
    --outcome folded --reason "folded into v-hold" >/dev/null 2>&1 ) || RC=$?
is "a fold whose holder cannot be joined still exits 0" "$RC" "0"
is "the holder carries pr_number, the merge hold" "$(meta_of v-hold pr_number)" "559"
is "the holder takes no anchor_bead it has no edge for" "$(meta_of v-hold anchor_bead)" ""
has "the folded visit closes" 'close v-x --reason folded: folded into v-hold' "$LOG"

echo "── fold: a transfer that will not read back refuses the close (exit 5) ──"
reset
seed_meta v-x pr_number 559
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" FAIL_XFER=1 bash "$SUT" --visit v-x --into v-hold \
    --outcome folded --reason "folded into v-hold" >/dev/null 2>&1 ) || RC=$?
is "a dropped merge-hold transfer exits 5" "$RC" "5"
hasnt "the folded visit is NOT closed when the hold did not move" 'close v-x' "$LOG"

echo "── fold: a merge-holding visit with no --into is refused, never silently dropped (exit 5) ──"
reset
seed_meta v-x pr_number 559
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --visit v-x --outcome folded --reason "folded" >/dev/null 2>&1 ) || RC=$?
is "a merge-holding fold with no --into exits 5" "$RC" "5"
hasnt "nothing is closed without a holder for the hold" 'close v-x' "$LOG"

echo "── fold: a conflicting holder pr_number is refused, not clobbered (exit 5) ──"
reset
seed_meta v-x pr_number 559
seed_meta v-hold pr_number 560
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --visit v-x --into v-hold \
    --outcome folded --reason "folded into v-hold" >/dev/null 2>&1 ) || RC=$?
is "a holder already holding another PR refuses the fold (exit 5)" "$RC" "5"
is "the holder's pr_number is not clobbered" "$(meta_of v-hold pr_number)" "560"
hasnt "the folded visit is NOT closed on a conflict" 'close v-x' "$LOG"

echo "── fold: a visit with no merge hold needs no transfer and closes normally ──"
reset
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --visit v-x --into v-hold \
    --outcome folded --reason "folded into v-hold" ) || RC=$?
is "a fold with no pr_number exits 0" "$RC" "0"
hasnt "no pr_number is written when there is no hold to move" 'pr_number=' "$LOG"
has "the folded visit still closes" 'close v-x --reason folded: folded into v-hold' "$LOG"

echo "── a non-fold close of a merge-holding visit does not require --into ──"
reset
seed_meta v-x pr_number 559
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" bash "$SUT" --visit v-x --outcome moot --reason "premise died" ) || RC=$?
is "a moot close of a pr_number visit still exits 0" "$RC" "0"
has "the moot close takes" 'close v-x --reason moot: premise died' "$LOG"

echo
echo "visit-close: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
