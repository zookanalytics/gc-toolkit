#!/usr/bin/env bash
# distiller-cadence-gate.test.sh — mol-feedback-distiller's cadence gate (D7)
# judges the pending observations on volume, on urgency, or on the age of the
# oldest one.
#
# The age arm is the trickle guard. A few observations that never reach the
# volume floor are still judged once the oldest passes distill_max_age_days,
# and an age the gate cannot read forces it open. So a timestamp parse that
# fails on one host reads every pending set as stale there, and the gate opens
# on every run that has anything pending. The cases below pin the age the gate
# computes and the verdict on each side of the limit.
#
# The block is extracted verbatim between the distiller-cadence-gate markers
# and EXECUTED against a scratch pending set, so what passes is the shipped
# formula text and not a paraphrase of it.
#
# Hermetic: no gc, no city.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
TOML="$REPO/formulas/mol-feedback-distiller.toml"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gctk-distiller-cadence-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

echo "── the block extracts ──"
RAW_BLOCK="$(awk '
  /# >>> distiller-cadence-gate/ { inb = 1; next }
  /# <<< distiller-cadence-gate/ { inb = 0; next }
  inb' "$TOML")"

if [ -n "$RAW_BLOCK" ]; then
  ok "block extracted between distiller-cadence-gate markers"
else
  bad "block extracted between distiller-cadence-gate markers" "no marked block in $TOML"
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; exit 1
fi

# The formula body is a TOML basic string, which reads a backslash as an
# escape. A block with none runs exactly as extracted. The vars render at the
# formula's defaults.
case "$RAW_BLOCK" in
  *'\'*) bad "the block is backslash-free" "TOML reads a backslash as an escape, so the extracted text is not what runs" ;;
  *)     ok "the block is backslash-free" ;;
esac

BLOCK="$(printf '%s\n' "$RAW_BLOCK" \
  | sed 's/{{distill_min_pending}}/5/g; s/{{distill_max_age_days}}/14/g')"

case "$BLOCK" in
  *'{{'*) bad "every var the block reads is rendered" "an unrendered {{var}} is left in the block" ;;
  *)      ok "every var the block reads is rendered" ;;
esac

printf '%s\n' "$BLOCK" > "$SANDBOX/block.sh"
if bash -n "$SANDBOX/block.sh" 2>"$SANDBOX/syntax.err"; then
  ok "extracted block is syntactically valid bash"
else
  bad "extracted block is syntactically valid bash" "$(cat "$SANDBOX/syntax.err")"
fi

# ago_days <d> -> the stamp d days and one hour back, in bd's created_at form.
# The extra hour keeps the whole-day count clear of the clock tick between here
# and the block. GNU date reads epoch seconds with -d @N and BSD date with -r N.
ago_days() {
  local s=$(( $(date -u +%s) - $1 * 86400 - 3600 ))
  date -u -d "@$s" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$s" +%Y-%m-%dT%H:%M:%SZ
}

# gate <created_at ...> -> "<verdict> <oldest age in days>" for a pending set
# with one observation per argument. An empty argument is an observation that
# carries no created_at.
gate() {
  jq -n '$ARGS.positional
    | map({metadata: {task_kind: "observation"}}
          + (if . == "" then {} else {created_at: .} end))' --args "$@" > "$SANDBOX/pending.json"
  PENDING="$SANDBOX/pending.json" bash "$SANDBOX/block.sh" 2>"$SANDBOX/err" \
    | sed -n 's/^DISTILL_RUN=\([a-z]*\) .*oldest \([0-9]*\)d.*/\1 \2/p'
}

echo "── below the volume floor, the oldest observation's age decides ──"
eq "$(gate "$(ago_days 1)")" "gated 1" "a day-old observation waits for volume"
eq "$(cat "$SANDBOX/err")" "" "and the gate reads its age without an error"
eq "$(gate "$(ago_days 20)")" "open 20" "a 20-day-old one opens the gate"
eq "$(gate "$(ago_days 2)" "$(ago_days 16)" "$(ago_days 3)")" "open 16" "the oldest of several is the one that counts"

echo "── the limit itself still waits ──"
eq "$(gate "$(ago_days 14)")" "gated 14" "an observation 14 whole days old waits"
eq "$(gate "$(ago_days 15)")" "open 15" "one 15 whole days old opens the gate"

echo "── an age the gate cannot read opens it ──"
eq "$(gate "not-a-date")" "open 15" "an unparseable created_at forces the trickle guard open"
eq "$(gate "")" "open 15" "so does an observation with no created_at"

echo "── the stamp is read as UTC whatever zone the distiller runs in ──"
# HST10 is a POSIX TZ string for ten hours behind UTC and needs no zoneinfo
# file. A parse that read the stamp as local time would make it ten hours
# younger, and a day and an hour would count as no whole day.
eq "$(TZ=HST10 gate "$(ago_days 1)")" "gated 1" "ten hours behind UTC, a day-old observation is still a day old"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
