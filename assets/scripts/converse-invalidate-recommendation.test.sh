#!/usr/bin/env bash
# converse-invalidate-recommendation.test.sh — the active strip of a first-reaction
# recommendation (assets/scripts/converse-invalidate-recommendation.sh): a subject
# carrying gc.recommended_formula has the key removed and the reason appended,
# leaving the subject and its visit open. This drives the script against a stub gc
# that records every write and reflects the strip on the next `bd show`.
#
# Hermetic: stubs gc, reads the repo only; no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/converse-invalidate-recommendation.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing '$2' in $(cat "$3")"; fi; }
hasnt() { if grep -qF -- "$2" "$3"; then bad "$1" "unexpected '$2' in $(cat "$3")"; else ok "$1"; fi; }

[ -r "$SUT" ] || { printf 'converse-invalidate-recommendation: cannot read %s\n' "$SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'converse-invalidate-recommendation: jq is required\n' >&2; exit 1; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-invalidate-rec-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; LOG="$TMPD/log"
mkdir -p "$BIN"

# A stateful stub gc. `bd update`/`bd close` append their args to the log. `bd
# show` reflects the world the script must see:
#   MODE=present  (default) — the subject carries gc.recommended_formula=mol-x
#                 until an unset of it is logged, then it reads absent (the real
#                 store behaviour a read-back relies on).
#   MODE=empty    — the subject never carries the key (already Discuss-only).
#   MODE=stubborn — the key is ALWAYS present, even after an unset is logged
#                 (a silent drop that the read-back must catch).
#   MODE=unreadable — show returns the object form bd emits when nothing
#                 resolves, which `.[0]` cannot index (an unreadable subject).
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 2
case "${2:-}" in
    update) printf 'update %s\n' "$*" >>"$LOG" ;;
    close)  printf 'close %s\n' "$*" >>"$LOG" ;;
    show)
        case "${MODE:-present}" in
            empty)      jq -nc '[{id:"tk-sub",metadata:{}}]' ;;
            stubborn)   jq -nc '[{id:"tk-sub",metadata:{"gc.recommended_formula":"mol-x"}}]' ;;
            unreadable) jq -nc '{}' ;;
            *)
                if grep -q -- '--unset-metadata gc.recommended_formula' "$LOG" 2>/dev/null; then
                    jq -nc '[{id:"tk-sub",metadata:{}}]'
                else
                    jq -nc '[{id:"tk-sub",metadata:{"gc.recommended_formula":"mol-x"}}]'
                fi ;;
        esac ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SUT" ] && ok "converse-invalidate-recommendation.sh is executable" || bad "converse-invalidate-recommendation.sh is executable" "chmod +x it"
bash -n "$SUT" && ok "converse-invalidate-recommendation.sh: valid bash" || bad "converse-invalidate-recommendation.sh: valid bash" "bash -n failed"

echo "── a live recommendation is stripped and the reason recorded, in one write ──"
: >"$LOG"
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" VISIT=v-x SUBJECT=tk-sub bash "$SUT" "a different course is right" ) >/dev/null || RC=$?
is "it exits 0" "$RC" "0"
has "gc.recommended_formula is unset on the subject" \
    'update tk-sub --unset-metadata gc.recommended_formula' "$LOG"
has "the same write appends the reason and the withdrawn formula" \
    "--append-notes recommendation invalidated (visit v-x): was 'mol-x'. a different course is right. Accept withdrawn; Discuss remains." "$LOG"

echo "── the strip and the note ride ONE update (record and act are atomic) ──"
is "exactly one update is written on the happy path" \
   "$(grep -c '^update ' "$LOG")" "1"

echo "── a subject with no recommendation is a no-op, and writes nothing ──"
: >"$LOG"
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" MODE=empty VISIT=v-x SUBJECT=tk-sub bash "$SUT" "not valid" ) >/dev/null || RC=$?
is "it exits 0 (already Discuss-only)" "$RC" "0"
hasnt "no unset is written when there is nothing to strip" '--unset-metadata gc.recommended_formula' "$LOG"
hasnt "no note is written when there is nothing to strip" '--append-notes' "$LOG"

echo "── a key that survives the unset fails closed (Accept would return) ──"
: >"$LOG"
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" MODE=stubborn VISIT=v-x SUBJECT=tk-sub bash "$SUT" "no longer valid" ) >/dev/null 2>&1 || RC=$?
is "it exits 4 when the key will not clear" "$RC" "4"
is "it retried a lone unset before giving up (two updates seen)" \
   "$(grep -c -- '--unset-metadata gc.recommended_formula' "$LOG")" "2"

echo "── an unreadable subject is refused, not read as 'nothing to strip' ──"
: >"$LOG"
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" MODE=unreadable VISIT=v-x SUBJECT=tk-sub bash "$SUT" "why" ) >/dev/null 2>&1 || RC=$?
is "it exits 3 on an unreadable subject" "$RC" "3"
hasnt "nothing is written when the subject cannot be read" '--unset-metadata' "$LOG"

echo "── VISIT is optional: the note omits it when unset ──"
: >"$LOG"
RC=0
( PATH="$BIN:$PATH" LOG="$LOG" SUBJECT=tk-sub bash "$SUT" "premise died" ) >/dev/null || RC=$?
is "it exits 0 without VISIT" "$RC" "0"
has "the note records the strip with no visit clause" \
    "--append-notes recommendation invalidated: was 'mol-x'. premise died. Accept withdrawn; Discuss remains." "$LOG"

echo "── every required field is checked (fail closed on a missing one) ──"
( PATH="$BIN:$PATH" LOG="$LOG" VISIT=v-x bash "$SUT" "reason" >/dev/null 2>&1 ); is "a missing SUBJECT is refused" "$?" "2"
( PATH="$BIN:$PATH" LOG="$LOG" VISIT=v-x SUBJECT=tk-sub bash "$SUT" >/dev/null 2>&1 ); is "a missing reason is refused" "$?" "2"

echo "── the converse role prompt wires this script (doctrine and tool do not drift) ──"
PROMPT="$REPO/agents/converse/prompt.template.md"
has "the prompt names converse-invalidate-recommendation.sh" \
    'converse-invalidate-recommendation.sh' "$PROMPT"

echo
echo "converse-invalidate-recommendation: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
