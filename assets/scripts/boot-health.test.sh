#!/usr/bin/env bash
# Hermetic test for boot-health.sh.
#
# A fake `gc` on PATH answers the two reads (pane peek, wisp list) and RECORDS
# the argv of the wisp query, so the flag assertions pin runtime behaviour
# rather than grepping the source. A fake patrol-finding.sh, reached through
# GC_PATROL_FINDING_TOOL, records each report and each clear the script files
# and lets each scenario SCRIPT its exit status. No dependency on the live
# city, Dolt, the deacon, or the network.
#
# The defect this file exists to pin: the wisp query FALSE-EMPTIES against a
# healthy deacon, which for a report-only detector means filing a bogus "deacon
# went cold" finding. It has now been introduced twice from two different
# directions — once by omitting --include-infra, once by keeping
# --status=in_progress (this order's own draft) — so both are
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
# when the filing was CONFIRMED — a failed or timed-out call leaves the episode
# DUE; (m) the report is a finding with a fixed identity, never mail; (n) a
# fresh wisp records the end of an episode that reported, or tried to, once,
# and keeps it owed until it lands.
#
# (i) guards the second defect this file has to hold: `last_report` silences the
# next REPORT_EVERY window, so a report recorded as filed when it was refused
# suppresses the only alert this order produces, during exactly the wedged-
# runtime incident it exists to catch.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/boot-health.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-boot-health-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# --- Fake gc: only the surface the script touches. ---------------------------
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
case "$1 $2" in
  # Every peek is logged, so a scenario can count the pane reads a pass made.
  # `${STUB_PANE-...}` omits the colon for the same reason STUB_WISPS does: an
  # explicitly EMPTY pane is the no-deacon answer, not the default pane.
  "session peek") printf '%s\n' "$*" >> "$PEEK_LOG"; printf '%s\n' "${STUB_PANE-deacon idle prompt}" ;;
  # `${STUB_WISPS-[]}` deliberately omits the colon: UNSET means "the ordinary
  # empty list", but an explicitly EMPTY value means "this probe answered
  # nothing at all", which is the unreadable-read case and a different verdict.
  "bd list")      printf '%s\n' "$*" >> "$ARGV_LOG"; printf '%s\n' "${STUB_WISPS-[]}" ;;
  # Any other call, a mail send among them, is logged so a scenario can prove
  # the script made none.
  *)              printf '%s\n' "$*" >> "$GC_OTHER_LOG"; exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/gc"

# --- Fake patrol-finding.sh. -------------------------------------------------
# One MARKER LINE per call in FINDING_LOG, `report` or `cleared` (a report's
# text is multi-line, so counting its lines would count one report as a dozen).
# The text goes to FINDING_BODY or CLEAR_BODY for the text assertions, and the
# rest of the argv to FINDING_ARGV on one line. The CALL is recorded before the
# outcome, so a scenario can tell "never tried" from "tried and refused".
# OWED_LOG gets the clear_owed the state file held as the call began, which is
# what a pass killed during the call would leave behind.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/patrol-finding" <<'STUB'
mode=report; msg=""; args=(); take=""
for a in "$@"; do
  if [ -n "$take" ]; then msg="$a"; take=""; continue; fi
  case "$a" in
    --message) take=1 ;;
    --cleared) mode=cleared; args+=("$a") ;;
    *) args+=("$a") ;;
  esac
done
printf '%s\n' "$mode" >> "$FINDING_LOG"
printf '%s\n' "${args[*]}" >> "$FINDING_ARGV"
owed="$(awk -F= '$1 == "clear_owed" {print $2}' "$BOOT_HEALTH_STATE_DIR/state" 2>/dev/null)"
printf '%s\n' "${owed:-none}" >> "$OWED_LOG"
if [ "$mode" = cleared ]; then
  printf '%s\n' "$msg" >> "$CLEAR_BODY"; outcome="${STUB_CLEARED:-ok}"
else
  printf '%s\n' "$msg" >> "$FINDING_BODY"; outcome="${STUB_FINDING:-ok}"
fi
case "$outcome" in
  ok)   echo "patrol-finding: stub recorded the $mode"; exit 0 ;;
  # The filer's answer to a clear with no live bead under the key.
  none) echo "patrol-finding: no live bead holds the key, so there is no clear to record"; exit 0 ;;
  fail) echo "patrol-finding: stub refused the $mode" >&2; exit 1 ;;
  hang) sleep 30 ;; # outlives the bound -> killed (124, or 137)
esac
STUB
chmod +x "$TMP/bin/patrol-finding"
export PATH="$TMP/bin:$PATH"
export GC_PATROL_FINDING_TOOL="$TMP/bin/patrol-finding"
export PEEK_LOG="$TMP/peeks" OWED_LOG="$TMP/owed"
# The stubs answer instantly, so a timeout only ever adds a fork. 0 makes each
# call a passthrough (same no-bound behavior as `timeout 0`). The one case that
# must see a real timeout, the hanging filing below, sets a 1s bound inline.
export BOOT_HEALTH_CALL_TIMEOUT=0 BOOT_HEALTH_FILE_TIMEOUT=0

NOW="$(date +%s)"
iso() { jq -rn --argjson s "$1" '$s | todateiso8601'; }
wisp() { # $1=status  $2=age seconds
    printf '[{"id":"hq-wisp-t","title":"mol-deacon-patrol","status":"%s","updated_at":"%s"}]' \
        "$1" "$(iso $((NOW - $2)))"
}

# Run the script one or more passes against a fresh state dir. The first cold
# pass only records (one observation is not evidence), so a report needs two.
LOGS=(finding body clear fargv gcother argv peeks owed)
reset() {
    local f
    rm -rf "$TMP/state"; mkdir -p "$TMP/state"
    for f in "${LOGS[@]}"; do : > "$TMP/$f"; done
}
# One pass against the CURRENT state dir (for tests that vary input per pass).
# BOOT_HEALTH_DB pins the ledger the wisp query runs against. It is set here for
# the same reason the script demands it: with no ledger to pin, the probe is
# unreadable and the script correctly declines to report — so a harness that
# left it unset would exercise only that refusal and never the detector.
pass() {
    env BOOT_HEALTH_STATE_DIR="$TMP/state" FINDING_LOG="$TMP/finding" FINDING_BODY="$TMP/body" \
        CLEAR_BODY="$TMP/clear" FINDING_ARGV="$TMP/fargv" GC_OTHER_LOG="$TMP/gcother" \
        ARGV_LOG="$TMP/argv" BOOT_HEALTH_DB="$TMP/fake.beads" "$@" \
        bash "$SCRIPT" >/dev/null 2>&1 || true
}
run() { # $1=passes, rest=env assignments
    local passes="$1"; shift
    reset
    local i
    for ((i = 0; i < passes; i++)); do pass "$@"; done
}
# Same as pass(), but hands back what the script SAID. The pacing split below
# is only observable in the script's own output and in `last_report`.
pass_out() {
    env BOOT_HEALTH_STATE_DIR="$TMP/state" FINDING_LOG="$TMP/finding" FINDING_BODY="$TMP/body" \
        CLEAR_BODY="$TMP/clear" FINDING_ARGV="$TMP/fargv" GC_OTHER_LOG="$TMP/gcother" \
        ARGV_LOG="$TMP/argv" BOOT_HEALTH_DB="$TMP/fake.beads" "$@" \
        bash "$SCRIPT" 2>&1 || true
}
# grep -c prints 0 AND exits 1 on no match, so take the count from the
# assignment and let the failure branch supply the value, never both.
reports() { local n; n="$(grep -c '^report$' "$TMP/finding" 2>/dev/null)" || n=0; printf '%s\n' "$n"; }
clears()  { local n; n="$(grep -c '^cleared$' "$TMP/finding" 2>/dev/null)" || n=0; printf '%s\n' "$n"; }
peeks()  { local n; n="$(grep -c . "$TMP/peeks" 2>/dev/null)" || n=0; printf '%s\n' "$n"; }
reported() { [ "$(reports)" -gt 0 ] && echo yes || echo no; }
state_get() { awk -F= -v k="$1" '$1 == k {print $2}' "$TMP/state/state" 2>/dev/null; }
# Has the pacing clock been written? An absent state file reads as "no" rather
# than erroring, so a scenario that never got that far still answers.
paced()  { local v; v="$(state_get last_report)"; [ "${v:-0}" -gt 0 ] && echo yes || echo no; }

# --- (a) A YOUNG wisp is healthy in BOTH live statuses. ----------------------
# `open` is the regression: a just-poured wisp is open until the deacon claims
# it, and the deacon burns the previous wisp BEFORE claiming the next, so a
# status-filtered query is empty right here — against a deacon patrolling
# normally.
for st in open in_progress; do
    run 2 STUB_WISPS="$(wisp "$st" 60)" BOOT_HEALTH_REPORT_AFTER=0
    eq "$(reported)" no "young wisp with status=$st reads healthy — no report"
done

# A young wisp must also CLEAR a running episode, not merely stay silent.
run 2 STUB_WISPS="$(wisp open 60)" BOOT_HEALTH_REPORT_AFTER=0
eq "$(grep -c '^cold_since=0' "$TMP/state/state" || true)" 1 \
   "young wisp clears the cold clock (episode re-arms)"

# --- (b) The query must not narrow, cap, or reach into closed history. -------
ARGV="$(cat "$TMP/argv")"
has   "$ARGV" "--include-infra" "wisp query passes --include-infra (wisps are infra beads; hq-ody8m)"
has   "$ARGV" "--type=molecule" "wisp query is typed to molecule"
has   "$ARGV" "--limit=0"       "wisp query is uncapped (a cap goes dead silently, under load only)"
hasnt "$ARGV" "--status"        "wisp query carries NO --status filter (tk-qdhnd: hides the poured-but-unclaimed wisp)"
hasnt "$ARGV" "--all"           "wisp query does NOT include closed rows (a burned wisp must not read as fresh)"
# The LEDGER, which is the third way this same query false-empties: `gc bd`
# resolves its store from the invoking rig and ignores BEADS_DIR, so an unpinned
# query reads the rig ledger while the deacon's wisps live in the town one.
# Correct flags are not enough if they are aimed at the wrong ledger.
has   "$ARGV" "--db"            "wisp query PINS the ledger (unpinned reads the rig store, never the town one)"

# --- (c) A STALE wisp reports, and names the status it OBSERVED. -------------
run 2 STUB_WISPS="$(wisp open 7200)" BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" yes "wisp past the freshness gate reports"
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
eq "$(reported)" yes "absent wisp reports"
has "$(cat "$TMP/body")" "no live patrol wisp" "absent-wisp text asserts no status"

# The report names the second the episode went cold, as a UTC timestamp. The
# state is seeded with a known second, so the expected text is fixed here
# rather than computed the way the script computes it.
reset
printf '%s\n' '#boot-health-state-v2' 'pane_hash=' 'cold_since=1791443608' 'last_report=0' > "$TMP/state/state"
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(grep -cxF '  cold since      2026-10-08T07:13:28Z' "$TMP/body" || true)" 1 \
   "report names when the episode went cold, as a UTC timestamp"

# --- (e) The wisp survives a flood of unrelated rows. ------------------------
# --limit=0 lifts the default 50-row cap; the title match keeps the answer to
# patrol wisps. Without both, a loaded deacon pushes the wisp out of the result
# and the age check goes dead exactly when the detector matters most.
run 2 STUB_WISPS="$(awk -v n=120 -v old="$(iso $((NOW - 7200)))" -v new="$(iso $((NOW - 60)))" 'BEGIN{
    printf "[";
    for (i = 0; i < n; i++) printf "{\"id\":\"hq-noise-%d\",\"title\":\"other molecule\",\"status\":\"in_progress\",\"updated_at\":\"%s\"},", i, old;
    printf "{\"id\":\"hq-wisp-t\",\"title\":\"mol-deacon-patrol\",\"status\":\"open\",\"updated_at\":\"%s\"}]", new }')" \
    BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" no "a young wisp behind 120 unrelated rows still reads healthy"

# --- (f) The pane is a FALLBACK, not an override. -----------------
# The pre-inversion bug this section now pins: a busy or advancing pane exited
# "healthy" BEFORE the wisp was ever consulted, so an expired-login session —
# which paints a busy, animating pane while completing no work — read as alive
# across a 3h51m stall (~105 passes, cold_since never left 0). The wisp measures
# WORK COMPLETED, so it wins when it can be read; the pane speaks only when it
# cannot. Precedence: fresh wisp > readable stale/absent wisp > pane.

# A busy marker does NOT rescue an absent-but-READABLE wisp. This is the stall
# this order missed: the ledger says no patrol completed, and no interrupt
# affordance in the pane can override that.
run 2 STUB_PANE='working... (esc to interrupt)' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" yes "busy pane does NOT suppress a readable ABSENT wisp (the missed stall)"

# Nor does it rescue a STALE readable wisp — the wedged-runtime signature stated
# in the bead: pane moving/busy + no patrol completed in the freshness window.
# This is the case that FAILS if the script exits healthy on stale-wisp+busy-pane.
run 2 STUB_PANE='working... (esc to interrupt)' STUB_WISPS="$(wisp in_progress 7200)" BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" yes "busy pane does NOT suppress a STALE wisp (pane moving + no work in window = wedged)"

# But when the wisp is UNREADABLE, the pane IS the only signal, so a busy marker
# still suppresses — reporting coldness on evidence never gathered is the cry-
# wolf failure this order exists to avoid.
run 2 STUB_PANE='working... (esc to interrupt)' STUB_WISPS='' BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" no "busy pane still suppresses when the wisp is UNREADABLE (pane is the fallback)"

# Pane MOVEMENT is likewise a fallback-only signal now, and digit-normalization
# still governs what counts as movement. Claude Code paints a self-advancing
# post-turn duration, so a byte-exact hash would report "changed" every cycle;
# digits are stripped before hashing so a numeric-only change reads as STATIC.
# Observe both against an UNREADABLE ledger (the only path where the pane hash
# still steers the verdict): open a cold clock with a readable absent wisp, then
# feed one unreadable pass and watch whether it clears the episode.
#
# Real new TEXT reads as alive and clears the episode:
reset
pass STUB_PANE='idle 1m' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0                 # readable absent: cold clock opens
pass STUB_PANE='now running a patrol step' STUB_WISPS='' BOOT_HEALTH_REPORT_AFTER=0 # unreadable + real movement
eq "$(state_get cold_since)" 0 "unreadable + real pane movement clears the episode (fallback liveness)"

# A numeric-only change reads as STATIC (digits normalized) and leaves the clock
# standing — if digit-stripping regressed, this pass would clear the episode too.
reset
pass STUB_PANE='idle 1m' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0                 # readable absent: cold clock opens
COLD_OPENED="$(state_get cold_since)"
pass STUB_PANE='idle 2m' STUB_WISPS='' BOOT_HEALTH_REPORT_AFTER=0                   # unreadable + numeric-only change
eq "$(state_get cold_since)" "$COLD_OPENED" "unreadable + numeric-only change is STATIC (digits normalized) — clock stands"

# --- (f2) The report describes the pane HONESTLY. -------
# The inversion (f) makes the report fire on a stale/absent wisp REGARDLESS of
# the pane, so the wedge it catches has a pane that looks alive — busy AND
# moving. The report text must NOT keep hardcoding the old static-pane predicate:
# a report whose summary says "no pane change", whose body calls the session
# "static", and whose evidence says "busy marker absent" is false at the exact
# moment it fires against a busy expired-login pane. Two cold passes with
# DIFFERENT busy panes so movement (not just the busy marker) is live at report
# time; the summary is the report text's first line, so both are checked.
reset
pass STUB_PANE='patrol step alpha (esc to interrupt)' STUB_WISPS="$(wisp in_progress 7200)" BOOT_HEALTH_REPORT_AFTER=0
pass STUB_PANE='patrol step beta (esc to interrupt)'  STUB_WISPS="$(wisp in_progress 7200)" BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" yes "busy+moving pane with a stale wisp still reports"
BODY="$(cat "$TMP/body")"
# Positive pins — each FAILS against the pre-fix text, which hardcoded the old
# static-pane predicate ("no pane change" / "static" / "busy marker absent").
has   "$BODY" "busy marker present" "report states the busy marker is present, not absent"
has   "$BODY" "changing"            "report states the pane is changing, not static"
hasnt "$BODY" "no pane change"      "summary does NOT claim 'no pane change' for a moving pane"
hasnt "$BODY" "static"              "report does NOT call a moving pane static"

# --- (g) One report per episode, then silence until REPORT_EVERY. ------------
run 4 STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(reports)" 1 "a persisting episode reports once, not once per pass"

# --- (h) Recovery closes the episode so the NEXT one reports again. ----------
# Same state dir throughout: cold -> report -> recover -> cold again. Without
# the re-arm, REPORT_EVERY=99999 would suppress the second episode entirely.
run 2 STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(reports)" 1 "first episode reported"
pass STUB_WISPS="$(wisp in_progress 60)" BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(reports)" 2 "recovery re-arms: a new episode reports again"

# --- (i) The report is PACED only when the filing was CONFIRMED. -------------
# `last_report` is what silences the next REPORT_EVERY window, so writing it for
# a filing that never landed suppresses the only alert this order produces,
# during precisely the wedged-runtime incident it exists to catch. The key
# dedups a filing, so a retry cannot file a second bead: a call that failed or
# timed out is left DUE, and only a confirmed one paces the window.

# Confirmed (rc 0): paced, and not refiled inside the window.
reset
pass STUB_WISPS='[]' STUB_FINDING=ok BOOT_HEALTH_REPORT_AFTER=0
OUT="$(pass_out STUB_WISPS='[]' STUB_FINDING=ok BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999)"
eq "$(reports)" 1 "confirmed: the report is filed"
has "$OUT" "boot-health: reported" "confirmed: says it reported"
has "$OUT" "patrol-finding: stub recorded the report" "confirmed: passes on what the filer said"
eq "$(paced)" yes "confirmed: last_report is paced"
pass STUB_WISPS='[]' STUB_FINDING=ok BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(reports)" 1 "confirmed: not refiled inside the REPORT_EVERY window"

# Refused (rc 1): nothing was filed, so NOTHING is paced and the episode stays
# DUE. This is the regression the split exists to prevent.
reset
pass STUB_WISPS='[]' STUB_FINDING=fail BOOT_HEALTH_REPORT_AFTER=0
OUT="$(pass_out STUB_WISPS='[]' STUB_FINDING=fail BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999)"
eq "$(reports)" 1 "failed: the filing was attempted"
has   "$OUT" "report FAILED (rc=1)" "failed: names the failure"
has   "$OUT" "stub refused the report" "failed: passes on why"
hasnt "$OUT" "boot-health: reported" "failed: does NOT claim it reported"
eq "$(paced)" no "failed: last_report is NOT paced (the next window stays open)"
eq "$(grep -c '^cold_since=0' "$TMP/state/state" || true)" 0 \
   "failed: the episode clock is still saved (only the pacing clock is withheld)"
pass STUB_WISPS='[]' STUB_FINDING=fail BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(reports)" 2 "failed: still DUE — the next pass retries"

# Bound expired mid-call (124, or 128+n if the hard kill lands first): not
# paced, because a retry finds the bead the call may have filed and records an
# occurrence on it rather than filing another.
reset
pass STUB_WISPS='[]' STUB_FINDING=hang BOOT_HEALTH_REPORT_AFTER=0 \
     BOOT_HEALTH_FILE_TIMEOUT=1 BOOT_HEALTH_KILL_AFTER=1
OUT="$(pass_out STUB_WISPS='[]' STUB_FINDING=hang BOOT_HEALTH_REPORT_AFTER=0 \
       BOOT_HEALTH_REPORT_EVERY=99999 BOOT_HEALTH_FILE_TIMEOUT=1 BOOT_HEALTH_KILL_AFTER=1)"
eq "$(reports)" 1 "timed out: the filing was attempted"
has   "$OUT" "report FAILED (rc=" "timed out: says it failed"
hasnt "$OUT" "boot-health: reported" "timed out: does NOT claim it reported"
eq "$(paced)" no "timed out: not paced, since a retry cannot file a second bead"
pass STUB_WISPS='[]' STUB_FINDING=ok BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=99999
eq "$(reports)" 2 "timed out: the next pass retries"
eq "$(paced)" yes "timed out: and the retry that lands paces the window"

# The probes keep the SWALLOWING form: a failed read is an empty one, which the
# script already treats as "no evidence". Only the filing's status is load-bearing.
# Two passes, because the first cold pass only records: a pane that did not stop
# the pass would report on the second.
reset
pass STUB_PANE='' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_PANE='' STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" no "an unreadable pane exits quietly rather than reporting"
eq "$(state_get cold_since)" "" "an unreadable pane starts no cold clock (no deacon is not a cold deacon)"

# --- (j) An UNREADABLE wisp probe is not evidence of a wedge. ----------------
# An empty ARRAY is an answer — no wisp is live — and still reports. No JSON at
# all is not an answer: the call failed, timed out, or was aimed at a ledger
# that cannot serve it. Those two were previously identical, and both read as
# "deacon wedged" — which is how a misdirected query becomes a bogus report
# about a perfectly healthy deacon.
reset
pass STUB_WISPS='' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='' BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" no "an unreadable wisp probe does NOT report (no evidence, no verdict)"

reset
pass STUB_WISPS='error: connection refused' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='error: connection refused' BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" no "a non-JSON wisp answer does NOT report"

# ...and the distinction is real: the SAME two passes with a well-formed empty
# array DO report. Without this pair, (j) could pass by never reporting at all.
reset
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(reported)" yes "an EMPTY ARRAY is an answer — no live wisp still reports"

# With no ledger to pin, the probe cannot be read, so the script declines rather
# than reporting a wedge it never observed. The city vars are cleared too: the
# ledger falls back to $CITY/.beads, so leaving them set would quietly re-pin it
# from the ambient environment and this case would never be reached.
noledger_pass() {
    env -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT \
        BOOT_HEALTH_STATE_DIR="$TMP/state" FINDING_LOG="$TMP/finding" FINDING_BODY="$TMP/body" \
        CLEAR_BODY="$TMP/clear" FINDING_ARGV="$TMP/fargv" GC_OTHER_LOG="$TMP/gcother" \
        ARGV_LOG="$TMP/argv" BOOT_HEALTH_DB="" STUB_WISPS='[]' \
        BOOT_HEALTH_REPORT_AFTER=0 bash "$SCRIPT" >/dev/null 2>&1 || true
}
reset
noledger_pass
noledger_pass
eq "$(reported)" no "no ledger to pin: declines to report rather than guessing"
eq "$(grep -c -- '--db' "$TMP/argv" || true)" 0 "no ledger to pin: the query is not even attempted"

# --- (k) Every busy marker reaches grep. -------------------------------------
# The pane speaks only when the ledger is unreadable, and that path never reports,
# so a recognized marker shows in the episode clock instead: a readable absent
# wisp opens the clock, then an unreadable pass over the SAME pane clears it
# only if the pane reads busy. The ctrl alternative carries the pattern's only
# braces, and GNU grep reads a broken interval as literal text while still
# matching the esc form, so the ctrl forms show the whole default reaching grep.
busy_clears() { # $1=pane, rest=env assignments; yes when the episode cleared
    local pane="$1"; shift
    reset
    pass STUB_PANE="$pane" STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 "$@"
    pass STUB_PANE="$pane" STUB_WISPS='' BOOT_HEALTH_REPORT_AFTER=0 "$@"
    if [ "$(state_get cold_since)" = 0 ]; then echo yes; else echo no; fi
}
for marker in 'esc to interrupt' 'ctrl+c to interrupt' 'ctrl-c to stop'; do
    eq "$(busy_clears "patrol step ($marker)")" yes "busy marker '$marker' reads busy"
done
eq "$(busy_clears 'patrol step (waiting)')" no "a pane with no busy marker leaves the clock standing"
reset
hasnt "$(pass_out STUB_WISPS='[]')" "not a valid ERE" "grep accepts the default markers, so no fallback is named"

# An override grep rejects gives way to the default markers, and says so; one
# grep accepts replaces them.
eq "$(busy_clears 'patrol step (ctrl+c to interrupt)' BOOT_HEALTH_BUSY='busy (unclosed')" yes \
   "an override grep rejects gives way to the default markers"
reset
has "$(pass_out STUB_WISPS='[]' BOOT_HEALTH_BUSY='busy (unclosed')" "BOOT_HEALTH_BUSY is not a valid ERE" \
    "an override grep rejects is named"
eq "$(busy_clears 'patrol step (ctrl+c to interrupt)' BOOT_HEALTH_BUSY='no such marker')" no \
   "an override grep accepts replaces the default markers"

# --- (l) The pane is read only when the wisp cannot settle the pass. ---------
# A fresh wisp is the whole answer, so a healthy pass reads the ledger and no
# pane. Anything else needs the pane, and one peek both proves the deacon
# exists and supplies the pane facts.
reset
pass STUB_WISPS="$(wisp in_progress 60)"
eq "$(peeks)" 0 "a fresh wisp ends the pass with no pane read"
reset
pass STUB_WISPS="$(wisp in_progress 7200)"
eq "$(peeks)" 1 "a stale wisp reads the pane once"
reset
pass STUB_WISPS='[]'
eq "$(peeks)" 1 "an absent wisp reads the pane once"
reset
pass STUB_WISPS=''
eq "$(peeks)" 1 "an unreadable ledger reads the pane once"

# --- (m) The report is a finding with a fixed identity, never mail. ---------
# The operator reads the board, not the "human" mailbox, so the report goes
# through patrol-finding.sh under a key that names the situation: every episode
# of one deacon lands on one bead while that bead is live.
run 2 STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
FARGV="$(cat "$TMP/fargv")"
has   "$FARGV" "--key deacon-cold.gc-toolkit.deacon" "the finding is keyed on the deacon, not the episode"
has   "$FARGV" "--scope boot-health" "the finding's scope names the order"
has   "$FARGV" "--rig gc-toolkit" "the finding lands in the store the deacon's own findings use"
has   "$FARGV" "--priority 1" "the finding carries the priority the proactive scan weighs"
has   "$FARGV" "--title gc-toolkit.deacon went cold" "the title names the deacon and the situation"
hasnt "$FARGV" "--cleared" "a cold pass files a report, not a clear"
eq "$(grep -c 'mail' "$TMP/gcother" || true)" 0 "no mail is sent, to the human mailbox or anywhere"

# The rig and the deacon come from the order's env, and a deacon name the key
# cannot carry is folded into characters it can.
run 2 STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_RIG=rig-a BOOT_HEALTH_DEACON='rig-a/deacon one'
FARGV="$(cat "$TMP/fargv")"
has "$FARGV" "--rig rig-a" "BOOT_HEALTH_RIG names the finding's store"
has "$FARGV" "--key deacon-cold.rig-a-deacon-one" "a name the key cannot carry is folded into [A-Za-z0-9._-]"

# A refresh inside one episode repeats the text, because the text names
# instants and never ages, so the finding counts a recurrence and adds no note.
run 3 STUB_WISPS="$(wisp open 7200)" BOOT_HEALTH_REPORT_AFTER=0 BOOT_HEALTH_REPORT_EVERY=0
eq "$(reports)" 2 "with REPORT_EVERY=0, each cold pass after the first refreshes"
LINES="$(grep -c '' "$TMP/body")" || LINES=0
eq "$(head -n $((LINES / 2)) "$TMP/body")" "$(tail -n $((LINES / 2)) "$TMP/body")" \
   "a refresh in the same episode repeats the report's text exactly"
FIRST="$(head -n 1 "$TMP/body")"
if [ "${#FIRST}" -le 200 ]; then
    ok "the summary line fits the 200 characters a changed recurrence notes (${#FIRST})"
else
    bad "the summary line runs ${#FIRST} characters, past the 200 a changed recurrence notes"
fi
has "$FIRST" "gc-toolkit.deacon cold since" "the summary line names the deacon and when it went cold"
has "$FIRST" "(status open)" "the summary line names the wisp's status"
has "$FIRST" "pane static, busy marker absent" "the summary line carries the pane facts"

# A state file without clear_owed reads as nothing owed, and keeps its pacing.
reset
printf '%s\n' '#boot-health-state-v2' 'pane_hash=' "cold_since=$((NOW - 7200))" "last_report=$((NOW - 60))" > "$TMP/state/state"
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(reports)" 0 "a state file without clear_owed keeps its pacing clock"
eq "$(state_get clear_owed)" 0 "and reads as nothing owed"

# --- (n) A fresh wisp records the end of an episode that tried to report. ---
# The finding stays the one record of the situation, so the pass that sees the
# deacon patrolling again says so on it. Only a fresh wisp is that proof: a pane
# that clears the clock while the ledger is unreadable leaves the record owed to
# the next fresh pass, and a record that does not land stays owed too.
FRESH="$(wisp in_progress 60)"

# Cold, reported, then a fresh wisp: one record of the end, naming its proof.
reset
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
COLD_AT="$(state_get cold_since)"
OUT="$(pass_out STUB_WISPS="$FRESH" BOOT_HEALTH_REPORT_AFTER=0)"
eq "$(clears)" 1 "a fresh wisp after a reported episode records its end"
CLEAR="$(cat "$TMP/clear")"
has "$CLEAR" "gc-toolkit.deacon is patrolling again" "the record says the deacon is patrolling again"
has "$CLEAR" "newest patrol wisp updated $(iso $((NOW - 60))) (status in_progress)" "the record names the wisp that shows it"
has "$CLEAR" "cold since $(iso "$COLD_AT")" "the record names when the episode began"
has "$(tail -n 1 "$TMP/fargv")" "--key deacon-cold.gc-toolkit.deacon --scope boot-health --rig gc-toolkit --cleared" \
    "the record goes to the same finding, as a clear"
has "$OUT" "the end of the cold episode is settled" "says the end is settled"
eq "$(state_get clear_owed)" 0 "nothing is owed once the record lands"
eq "$(state_get last_report)" 0 "the episode's pacing clock is cleared"
pass STUB_WISPS="$FRESH" BOOT_HEALTH_REPORT_AFTER=0
eq "$(clears)" 1 "a second fresh pass records nothing more"

# An episode that never reported has no end to record.
reset
pass STUB_WISPS='[]'
pass STUB_WISPS='[]'
pass STUB_WISPS="$FRESH"
eq "$(reports)" 0 "an episode shorter than REPORT_AFTER files no report"
eq "$(clears)" 0 "and records no end"

# A record that does not land stays owed, and the next fresh pass retries it.
reset
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
OUT="$(pass_out STUB_WISPS="$FRESH" STUB_CLEARED=fail)"
eq "$(clears)" 1 "the record was attempted"
has "$OUT" "is NOT recorded (rc=1)" "a failed record says so"
eq "$(state_get clear_owed)" 1 "a record that did not land stays owed"
eq "$(state_get cold_since)" 0 "and the episode clock is still cleared"
pass STUB_WISPS="$FRESH"
eq "$(clears)" 2 "the next fresh pass retries it"
eq "$(state_get clear_owed)" 0 "and nothing is owed once it lands"

# A pane that clears the clock while the ledger is unreadable records nothing,
# and the end is owed to the next fresh wisp.
reset
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_PANE='working... (esc to interrupt)' STUB_WISPS=''
eq "$(state_get cold_since)" 0 "an unreadable ledger with a busy pane clears the clock"
eq "$(clears)" 0 "but records no end on pane evidence"
eq "$(state_get clear_owed)" 1 "and leaves the record owed"
pass STUB_WISPS="$FRESH"
eq "$(clears)" 1 "the next fresh wisp records it"
hasnt "$(cat "$TMP/clear")" "cold since" "a record whose episode clock is gone names no start"

# A new episode's confirmed report settles an end still owed to the last one,
# because the finding is live again.
reset
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS="$FRESH" STUB_CLEARED=fail
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
eq "$(reports)" 2 "the new episode reports"
eq "$(state_get clear_owed)" 0 "its report settles the end owed to the last episode"
pass STUB_WISPS="$FRESH"
eq "$(clears)" 2 "the next fresh pass records the new episode's end, once"

# A filing that is not confirmed may still have written the finding, because
# the filer writes the bead before it reads the key back or slings the first
# reaction. So the end is owed, on disk, from before the call. Here the filing
# outlives its bound, and the deacon is patrolling again on the very next pass.
reset
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' STUB_FINDING=hang BOOT_HEALTH_REPORT_AFTER=0 \
     BOOT_HEALTH_FILE_TIMEOUT=1 BOOT_HEALTH_KILL_AFTER=1
eq "$(reports)" 1 "the filing that timed out was attempted"
eq "$(cat "$TMP/owed")" 1 "the end was owed on disk before the filing call began"
eq "$(paced)" no "a filing that timed out is not paced"
eq "$(state_get clear_owed)" 1 "and leaves the end owed"
pass STUB_WISPS="$FRESH"
eq "$(clears)" 1 "the next fresh pass records the end, though no report was confirmed"
eq "$(state_get clear_owed)" 0 "and nothing is owed once it lands"
pass STUB_WISPS="$FRESH"
eq "$(clears)" 1 "a second fresh pass records nothing more"

# A refused filing may have written nothing. The fresh pass's record then finds
# no live bead under the key, which the filer answers with exit 0, and that
# settles the debt.
reset
pass STUB_WISPS='[]' BOOT_HEALTH_REPORT_AFTER=0
pass STUB_WISPS='[]' STUB_FINDING=fail BOOT_HEALTH_REPORT_AFTER=0
eq "$(state_get clear_owed)" 1 "a refused filing leaves the end owed"
OUT="$(pass_out STUB_WISPS="$FRESH" STUB_CLEARED=none)"
eq "$(clears)" 1 "the next fresh pass tries the record"
has "$OUT" "no clear to record" "and passes on that no live bead took it"
eq "$(state_get clear_owed)" 0 "a record that finds no live bead settles the debt"

echo
echo "boot-health.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
