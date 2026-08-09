#!/usr/bin/env bash
# Hermetic test for boot-health.sh.
#
# A fake `gc` on PATH answers the three reads (pane peek, wisp list, mail send),
# RECORDS the argv of the wisp query — so the flag assertions pin runtime
# behaviour rather than grepping the source — and lets each scenario SCRIPT the
# mail's exit status. No dependency on the live city, Dolt, the deacon, or the
# network.
#
# The defect this file exists to pin: the wisp query FALSE-EMPTIES against a
# healthy deacon, which for a report-only detector means mailing the mayor a
# bogus "deacon wedged". It has now been introduced twice from two different
# directions — once by omitting --include-infra (lx-ody8m), once by keeping
# --status=in_progress (tk-qdhnd, and this order's own draft) — so both are
# asserted mechanically, plus the row cap that would reproduce it a third way
# under load only.
#
# Covers: (a) a young wisp reads healthy in BOTH of its live statuses;
# (b) the query carries no narrowing filter and no cap; (c) a wisp beyond the
# freshness gate reports, naming the status it observed rather than asserting
# one; (d) an absent wisp reports without asserting a status; (e) the wisp
# survives a flood of unrelated rows; (f) busy marker and pane movement each
# clear the episode; (g) one report per episode, then silence until
# REPORT_EVERY; (h) recovery re-arms; (i) the report paces the next window only
# when the mail was actually DELIVERED — a failed send leaves the episode DUE.
#
# (i) guards the second defect this file has to hold: `last_report` silences the
# next REPORT_EVERY window, so a send recorded as delivered when it was refused
# suppresses the only alert this order produces, during exactly the wedged-
# runtime incident it exists to catch.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/boot-health.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# --- Fake gc: only the surface the script touches. ---------------------------
mkdir -p "$TMP/bin"
# One MARKER LINE per mail in MAIL_LOG (report bodies are multi-line, so
# counting body lines would count one report as a dozen); the body itself goes
# to MAIL_BODY for the text assertions.
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "session peek") printf '%s\n' "${STUB_PANE:-deacon idle prompt}" ;;
  "bd list")      printf '%s\n' "$*" >> "$ARGV_LOG"; printf '%s\n' "${STUB_WISPS:-[]}" ;;
  "mail send")    shift; printf 'MAIL\n' >> "$MAIL_LOG"; printf '%s\n' "$*" >> "$MAIL_BODY"
                  # The ATTEMPT is recorded above before the outcome below, so a
                  # scenario can tell "never tried" from "tried and refused".
                  case "${STUB_MAIL:-ok}" in
                    ok)   exit 0 ;;
                    fail) exit 42 ;;  # a fast rejection: nothing was delivered
                    hang) sleep 30 ;; # outlives the bound -> killed (124, or 137)
                  esac ;;
  *)              exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

NOW="$(date +%s)"
iso() { date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'; }
wisp() { # $1=status  $2=age seconds
    printf '[{"id":"lx-wisp-t","title":"mol-deacon-patrol","status":"%s","updated_at":"%s"}]' \
        "$1" "$(iso $((NOW - $2)))"
}

# Run the script one or more passes against a fresh state dir. The first cold
# pass only records (one observation is not evidence), so a report needs two.
reset() {
    rm -rf "$TMP/state" "$TMP/mail" "$TMP/body" "$TMP/argv"
    mkdir -p "$TMP/state"; : > "$TMP/mail"; : > "$TMP/body"; : > "$TMP/argv"
}
# One pass against the CURRENT state dir (for tests that vary input per pass).
pass() {
    env BOOT_HEALTH_STATE_DIR="$TMP/state" MAIL_LOG="$TMP/mail" MAIL_BODY="$TMP/body" \
        ARGV_LOG="$TMP/argv" "$@" bash "$SCRIPT" >/dev/null 2>&1 || true
}
run() { # $1=passes, rest=env assignments
    local passes="$1"; shift
    reset
    local i
    for ((i = 0; i < passes; i++)); do pass "$@"; done
}
# Same as pass(), but hands back what the script SAID. The delivery split below
# is only observable in the script's own output and in `last_report`.
pass_out() {
    env BOOT_HEALTH_STATE_DIR="$TMP/state" MAIL_LOG="$TMP/mail" MAIL_BODY="$TMP/body" \
        ARGV_LOG="$TMP/argv" "$@" bash "$SCRIPT" 2>&1 || true
}
# grep -c prints 0 AND exits 1 on no match, so take the count from the
# assignment and let the failure branch supply the value, never both.
mails()  { local n; n="$(grep -c '^MAIL$' "$TMP/mail" 2>/dev/null)" || n=0; printf '%s\n' "$n"; }
mailed() { [ "$(mails)" -gt 0 ] && echo yes || echo no; }
state_get() { awk -F= -v k="$1" '$1 == k {print $2}' "$TMP/state/state" 2>/dev/null; }
# Has the pacing clock been written? An absent state file reads as "no" rather
# than erroring, so a scenario that never got that far still answers.
paced()  { local v; v="$(state_get last_report)"; [ "${v:-0}" -gt 0 ] && echo yes || echo no; }

# --- (a) A YOUNG wisp is healthy in BOTH live statuses. ----------------------
# `open` is the regression: a just-poured wisp is open until the deacon claims
# it, and the deacon burns the previous wisp BEFORE claiming the next, so a
# status-filtered query is empty right here — against a deacon patrolling
# normally. Reproduced live 2026-08-09 (lx-wisp-222j, open at 05:06:25Z).
for st in open in_progress; do
    run 2 STUB_WISPS="$(wisp "$st" 60)" BOOT_HEALTH_REPORT_AFTER=0
    eq "$(mailed)" no "young wisp with status=$st reads healthy — no report"
done

# A young wisp must also CLEAR a running episode, not merely stay silent.
run 2 STUB_WISPS="$(wisp open 60)" BOOT_HEALTH_REPORT_AFTER=0
eq "$(grep -c '^cold_since=0' "$TMP/state/state" || true)" 1 \
   "young wisp clears the cold clock (episode re-arms)"

# --- (b) The query must not narrow, cap, or reach into closed history. -------
ARGV="$(cat "$TMP/argv")"
has   "$ARGV" "--include-infra" "wisp query passes --include-infra (wisps are infra beads; lx-ody8m)"
has   "$ARGV" "--type=molecule" "wisp query is typed to molecule"
has   "$ARGV" "--limit=0"       "wisp query is uncapped (a cap goes dead silently, under load only)"
hasnt "$ARGV" "--status"        "wisp query carries NO --status filter (tk-qdhnd: hides the poured-but-unclaimed wisp)"
hasnt "$ARGV" "--all"           "wisp query does NOT include closed rows (a burned wisp must not read as fresh)"

# --- (c) A STALE wisp reports, and names the status it OBSERVED. -------------
run 2 STUB_WISPS="$(wisp open 7200)" BOOT_HEALTH_REPORT_AFTER=0
eq "$(mailed)" yes "wisp past the freshness gate reports"
BODY="$(cat "$TMP/body")"
has   "$BODY" "status open" "report names the status actually observed"
hasnt "$BODY" "no in_progress patrol wisp" \
      "report does not assert a status the query never filtered on"
# The report tells a human how to look for themselves; that command must not
# teach the very filter this order was fixed to drop.
hasnt "$BODY" "--status=in_progress" \
      "the report's own 'To inspect' command does not reproduce the false-empty"

# --- (d) No wisp at all: report, still without asserting a status. -----------
run 2 STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(mailed)" yes "absent wisp reports"
has "$(cat "$TMP/body")" "no live patrol wisp" "absent-wisp text asserts no status"

# --- (e) The wisp survives a flood of unrelated rows. ------------------------
# --limit=0 lifts the default 50-row cap; the title match keeps the answer to
# patrol wisps. Without both, a loaded deacon pushes the wisp out of the result
# and the age check goes dead exactly when the detector matters most.
run 2 STUB_WISPS="$(awk -v n=120 -v old="$(iso $((NOW - 7200)))" -v new="$(iso $((NOW - 60)))" 'BEGIN{
    printf "[";
    for (i = 0; i < n; i++) printf "{\"id\":\"lx-noise-%d\",\"title\":\"other molecule\",\"status\":\"in_progress\",\"updated_at\":\"%s\"},", i, old;
    printf "{\"id\":\"lx-wisp-t\",\"title\":\"mol-deacon-patrol\",\"status\":\"open\",\"updated_at\":\"%s\"}]", new }')" \
    BOOT_HEALTH_REPORT_AFTER=0
eq "$(mailed)" no "a young wisp behind 120 unrelated rows still reads healthy"

# --- (f) Either liveness signal clears the episode. --------------------------
run 2 STUB_PANE='working... (esc to interrupt)' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(mailed)" no "busy marker in the pane suppresses the report"

# Pane MOVEMENT, across two passes on one state dir. Digits are normalized out
# before hashing — Claude Code paints a self-advancing post-turn duration, so a
# byte-exact hash would report "changed" every cycle and the detector would
# never fire. A pane whose ONLY change is numeric must therefore read as static
# (and, with no dwell time configured, report).
reset
pass STUB_PANE='idle 1m' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_PANE='idle 2m' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(mailed)" yes "a pane whose only change is numeric reads as STATIC (digits normalized)"

# Real new TEXT is liveness: it clears the episode instead.
reset
pass STUB_PANE='idle 1m' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_PANE='now running a patrol step' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(mailed)" no "new pane TEXT clears the episode"
eq "$(grep -c '^cold_since=0' "$TMP/state/state" || true)" 1 "pane movement resets the cold clock"

# --- (g) One report per episode, then silence until REPORT_EVERY. ------------
run 4 STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(mails)" 1 "a persisting episode mails once, not once per pass"

# --- (h) Recovery closes the episode so the NEXT one reports again. ----------
# Same state dir throughout: cold -> report -> recover -> cold again. Without
# the re-arm, REPORT_EVERY=99999 would suppress the second episode entirely.
run 2 STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(mails)" 1 "first episode reported"
pass STUB_WISPS="$(wisp in_progress 60)" BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(mails)" 2 "recovery re-arms: a new episode reports again"

# --- (i) The report is PACED only when it was actually DELIVERED. ------------
# `last_report` is what silences the next REPORT_EVERY window (6h by default),
# so writing it for a send that never landed suppresses the only alert this
# order produces — during precisely the wedged-runtime incident it exists to
# catch. Before the split, every gc call ran through a helper ending in
# `|| true`, so a definite mail failure printed "reported", paced the clock, and
# went quiet for 6h. Three outcomes, discriminated by the send's exit status.

# Confirmed (rc 0): paced, and not resent inside the window.
reset
pass STUB_WISPS='[]' STUB_MAIL=ok BOOT_HEALTH_REPORT_AFTER=0
OUT="$(pass_out STUB_WISPS='[]' STUB_MAIL=ok BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999)"
eq "$(mails)" 1 "confirmed: the report is sent"
has "$OUT" "boot-health: reported to" "confirmed: reports delivery"
eq "$(paced)" yes "confirmed: last_report is paced"
pass STUB_WISPS='[]' STUB_MAIL=ok BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(mails)" 1 "confirmed: not resent inside the REPORT_EVERY window"

# Fast rejection (rc 42): nothing was delivered, so NOTHING is paced and the
# episode stays DUE. This is the regression the split exists to prevent.
reset
pass STUB_WISPS='[]' STUB_MAIL=fail BOOT_HEALTH_REPORT_AFTER=0
OUT="$(pass_out STUB_WISPS='[]' STUB_MAIL=fail BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999)"
eq "$(mails)" 1 "failed: the send was attempted"
has   "$OUT" "report FAILED (rc=42)" "failed: names the failure"
hasnt "$OUT" "reported to" "failed: does NOT claim it reported"
eq "$(paced)" no "failed: last_report is NOT paced (the next window stays open)"
eq "$(grep -c '^cold_since=0' "$TMP/state/state" || true)" 0 \
   "failed: the episode clock is still saved (only the pacing clock is withheld)"
pass STUB_WISPS='[]' STUB_MAIL=fail BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(mails)" 2 "failed: still DUE — the next pass retries"

# Bound expired mid-send (124, or 128+n if the hard kill lands first): AMBIGUOUS.
# `gc mail send` writes durable mail through Dolt, so the write may well have
# committed — paced as sent so a retry cannot duplicate, and said out loud.
reset
pass STUB_WISPS='[]' STUB_MAIL=hang BOOT_HEALTH_REPORT_AFTER=0 \
     BOOT_HEALTH_CALL_TIMEOUT=1 BOOT_HEALTH_KILL_AFTER=1
OUT="$(pass_out STUB_WISPS='[]' STUB_MAIL=hang BOOT_HEALTH_REPORT_AFTER=0 \
       BOOT_HEALTH_REPORT_EVERY=99999 BOOT_HEALTH_CALL_TIMEOUT=1 BOOT_HEALTH_KILL_AFTER=1)"
eq "$(mails)" 1 "unconfirmed: the send was attempted"
has   "$OUT" "report UNCONFIRMED" "unconfirmed: says so out loud"
hasnt "$OUT" "reported to" "unconfirmed: does NOT claim confirmed delivery"
eq "$(paced)" yes "unconfirmed: paced as sent (a resend could duplicate a mail that did land)"
pass STUB_WISPS='[]' STUB_MAIL=hang BOOT_HEALTH_REPORT_AFTER=0 \
     BOOT_HEALTH_REPORT_EVERY=99999 BOOT_HEALTH_CALL_TIMEOUT=1 BOOT_HEALTH_KILL_AFTER=1
eq "$(mails)" 1 "unconfirmed: not resent this episode"

# The probes keep the SWALLOWING form: a failed read is an empty one, which the
# script already treats as "no evidence". Only the mail's status is load-bearing.
reset
pass STUB_PANE='' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(mailed)" no "an unreadable pane exits quietly rather than reporting"

echo
echo "boot-health.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
