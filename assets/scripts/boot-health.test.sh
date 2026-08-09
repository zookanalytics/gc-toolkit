#!/usr/bin/env bash
# Hermetic test for boot-health.sh — the report-delivery split.
#
# A fake `gc` on PATH answers the three probes (pane peek, wisp list) and lets
# each scenario dictate what `gc mail send` does. No live city, no Dolt, no
# network, no LLM.
#
# What it pins is the one thing that decides whether a human ever hears about a
# wedged deacon: `last_report` paces the next REPORT_EVERY window (default 6h),
# so it may only advance when a mail actually went out. Three outcomes:
#
#   rc 0            confirmed  -> paced, not resent this episode
#   rc 124 / >=128  UNCONFIRMED-> paced anyway (the bound expired mid-send and
#                                 `gc mail send` writes durable mail through
#                                 Dolt, so a resend could duplicate), and said
#                                 out loud
#   any other rc    FAILED     -> nothing delivered, nothing paced, still DUE
#                                 on the next pass — a retry cannot duplicate
#
# The middle and last cases are the regression: before the fix every gc call ran
# through a helper ending in `|| true`, so a definite mail failure printed
# "reported", wrote last_report, and suppressed the next 6h of alerts.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/boot-health.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (output: $(printf '%s' "$1" | tr '\n' ' '))" ;; esac; }

# --- Fake gc: static pane, no wisps, scripted mail outcome. ------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "session peek") printf 'deacon\nwaiting for work\n' ;;   # static, no busy marker
  "bd list")      printf '[]\n' ;;                          # no in_progress wisp -> cold
  "mail send")
      printf 'attempt\n' >> "$FAKE_MAIL_LOG"
      case "$FAKE_MAIL_MODE" in
        ok)   exit 0 ;;
        fail) exit 42 ;;   # a fast rejection: definitely nothing delivered
        hang) sleep 30 ;;  # outlives the bound -> timeout kills it (124, or 137)
      esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

export BOOT_HEALTH_DEACON=test.deacon
export BOOT_HEALTH_REPORT_TO=mayor/
export BOOT_HEALTH_REPORT_AFTER=0        # any cold streak is reportable
export BOOT_HEALTH_REPORT_EVERY=21600    # ...but only once per episode
export BOOT_HEALTH_CALL_TIMEOUT=1        # so the `hang` scenario is quick
export BOOT_HEALTH_KILL_AFTER=1

mails()     { wc -l < "$1" | tr -d ' '; }
state_get() { awk -F= -v k="$2" '$1 == k {print $2}' "$1/state" 2>/dev/null; }

# Primes an episode: the first cold pass only records (one observation is not
# evidence), so every scenario needs it before the report step is reachable.
prime() {
    FAKE_MAIL_MODE="$1" FAKE_MAIL_LOG="$2" BOOT_HEALTH_STATE_DIR="$3" \
        bash "$SCRIPT" >/dev/null
}
run() {
    FAKE_MAIL_MODE="$1" FAKE_MAIL_LOG="$2" BOOT_HEALTH_STATE_DIR="$3" \
        bash "$SCRIPT" 2>&1
}

# --- 1. Confirmed delivery ----------------------------------------------------
SD="$TMP/s-ok"; LOG="$TMP/m-ok"; mkdir -p "$SD"; : > "$LOG"
prime ok "$LOG" "$SD"
eq "$(mails "$LOG")" "0" "first cold pass records only — no mail yet"
OUT="$(run ok "$LOG" "$SD")"
eq "$(mails "$LOG")" "1" "confirmed: the report is sent"
has "$OUT" "reported to mayor/" "confirmed: reports delivery"
if [ "$(state_get "$SD" last_report)" -gt 0 ]; then
    ok "confirmed: last_report is paced"
else
    bad "confirmed: last_report is paced (got '$(state_get "$SD" last_report)')"
fi
run ok "$LOG" "$SD" >/dev/null
eq "$(mails "$LOG")" "1" "confirmed: not resent inside the REPORT_EVERY window"

# --- 2. Fast failure — the regression ----------------------------------------
# `gc mail send` exits 42. Nothing was delivered, so the episode must stay DUE.
SD="$TMP/s-fail"; LOG="$TMP/m-fail"; mkdir -p "$SD"; : > "$LOG"
prime fail "$LOG" "$SD"
OUT="$(run fail "$LOG" "$SD")"
eq "$(mails "$LOG")" "1" "failed: the send was attempted"
has "$OUT" "report FAILED (rc=42)" "failed: reports the failure, not success"
case "$OUT" in
  *"reported to"*) bad "failed: must NOT claim it reported" ;;
  *)               ok  "failed: does not claim it reported" ;;
esac
eq "$(state_get "$SD" last_report)" "0" "failed: last_report is NOT paced"
if [ "$(state_get "$SD" cold_since)" -gt 0 ]; then
    ok "failed: the episode clock is still saved"
else
    bad "failed: the episode clock is still saved"
fi
run fail "$LOG" "$SD" >/dev/null
eq "$(mails "$LOG")" "2" "failed: still DUE — the next pass retries"

# --- 3. Bound expired mid-send — ambiguous, paced as sent --------------------
SD="$TMP/s-hang"; LOG="$TMP/m-hang"; mkdir -p "$SD"; : > "$LOG"
prime hang "$LOG" "$SD"
OUT="$(run hang "$LOG" "$SD")"
eq "$(mails "$LOG")" "1" "unconfirmed: the send was attempted"
has "$OUT" "report UNCONFIRMED" "unconfirmed: says so out loud"
case "$OUT" in
  *"reported to"*) bad "unconfirmed: must NOT claim confirmed delivery" ;;
  *)               ok  "unconfirmed: does not claim confirmed delivery" ;;
esac
if [ "$(state_get "$SD" last_report)" -gt 0 ]; then
    ok "unconfirmed: paced as sent (a resend could duplicate)"
else
    bad "unconfirmed: paced as sent (got '$(state_get "$SD" last_report)')"
fi
run hang "$LOG" "$SD" >/dev/null
eq "$(mails "$LOG")" "1" "unconfirmed: not resent this episode"

# --- 4. Recovery closes the episode ------------------------------------------
# A busy marker means the deacon is mid-turn: state clears, so the next cold
# streak is a NEW episode and reports again even though one already went out.
SD="$TMP/s-recover"; LOG="$TMP/m-recover"; mkdir -p "$SD"; : > "$LOG"
prime ok "$LOG" "$SD"
run ok "$LOG" "$SD" >/dev/null
eq "$(mails "$LOG")" "1" "recovery: first episode reported once"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "session peek") printf 'working\nesc to interrupt\n' ;;
  "bd list")      printf '[]\n' ;;
  "mail send")    printf 'attempt\n' >> "$FAKE_MAIL_LOG"; exit 0 ;;
esac
exit 0
GC
run ok "$LOG" "$SD" >/dev/null
eq "$(state_get "$SD" last_report)" "0" "recovery: a busy pane clears the episode"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
