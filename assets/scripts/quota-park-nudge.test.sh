#!/usr/bin/env bash
# Hermetic test for quota-park-nudge.sh.
#
# A fake `gc` on PATH serves a fixed session list, a canned pane per session,
# and records every nudge and mail. No live city, no Dolt, no provider.
#
# Covers: (a) a Claude session-limit park is nudged; (b) a Codex usage-limit
# park is nudged (the fix is not provider-specific); (c) a busy pane is never
# nudged even when it contains the banner text — this is the agent *reading
# about* the bug; (d) a clean pane is left alone; (e) an attached session is
# skipped; (f) backoff — no second nudge inside the window, one after it;
# (g) an episode ends (state cleared) when the pane goes clean; (h) escalation
# fires once per episode, not once per cycle; (i) the nudge text does not
# itself match the detector, so a recovered agent cannot re-trigger forever;
# (j) an idle agent that *quoted* the banner in a report is not nudged — the
# live false positive this script hit on its first real run; (k) a banner
# scrolled up out of the tail window is history, not a park; (l) a parked
# session with `running: null` IS recovered — that is a live session mid
# controller churn, and gating on `.running == true` would skip it; (m) an
# ordinary "API rate limit exceeded" tool error is not a provider quota banner
# and is never nudged; (n) one wedged `gc` call cannot strand the sessions
# behind it in the sweep, and a sweep that runs past its budget defers the
# remainder to the next cycle instead of overlapping it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/quota-park-nudge.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
nudges_for() { grep -c "^nudge $1\$" "$TMP/nudges" 2>/dev/null || true; }

mkdir -p "$TMP/panes" "$TMP/state" "$TMP/bin"
: > "$TMP/nudges"; : > "$TMP/mail"

# --- Session list. One attached; one with `running: null`, which is what an
# active session looks like during controller churn (same shape the helm's
# owner-liveness fixture pins, tools/helm-surface-fixture.sh) — it must be
# treated as live, or the parked agents we most need to reach are invisible.
cat > "$TMP/sessions.json" <<'JSON'
{"sessions":[
 {"id":"lx-claude","alias":"gc-toolkit/gc-toolkit.witness","state":"active","running":true,"attached":false},
 {"id":"lx-codex","alias":"gc-toolkit/gc-toolkit.ripley","state":"active","running":true,"attached":false},
 {"id":"lx-churn","alias":"gc-toolkit/gc-toolkit.hicks","state":"active","running":null,"attached":false},
 {"id":"lx-busy","alias":"gc-toolkit/gc-toolkit.furiosa","state":"active","running":true,"attached":false},
 {"id":"lx-clean","alias":"gc-toolkit/gc-toolkit.refinery","state":"active","running":true,"attached":false},
 {"id":"lx-quoting","alias":"gc-toolkit.su-uzy9","state":"active","running":true,"attached":false},
 {"id":"lx-scrolled","alias":"gc-toolkit.mechanik","state":"active","running":true,"attached":false},
 {"id":"lx-apierr","alias":"gc-toolkit.deacon","state":"active","running":true,"attached":false},
 {"id":"lx-attached","alias":"gc-toolkit.mayor","state":"active","running":true,"attached":true}
]}
JSON

# Panes as the two providers actually render them (typographic apostrophe and
# all — the detector must not depend on it).
cat > "$TMP/panes/lx-claude" <<'PANE'
  ⎿  You’ve hit your session limit · resets 10:10am (UTC)
     /usage-credits to finish what you're working on.

❯
PANE
cat > "$TMP/panes/lx-codex" <<'PANE'
• You’ve hit your usage limit. Try again at Aug 8th, 2026 7:56 PM.

› Use /skills to list available skills
  gpt-5.5 xhigh · ~/loomington/.gc/worktrees/gc-toolkit/polecat-codex
PANE
# The false positive this must not produce: an agent working ON this bug, with
# the banner text quoted in its own output.
cat > "$TMP/panes/lx-busy" <<'PANE'
  The bead says the pane shows "You've hit your usage limit" and then parks.
• Working (13s • esc to interrupt) · 1 background terminal running
PANE
cat > "$TMP/panes/lx-clean" <<'PANE'
• Merged PR #242. Queue is empty.
❯
PANE
# The live false positive, verbatim: a bead-host that reported the outage to
# the operator and went idle with the banner quoted in its own report.
cat > "$TMP/panes/lx-quoting" <<'PANE'
  All three codex slots are affected. The banner reads:

  ▎ "You've hit your usage limit… try again at Aug 8th, 2026 7:56 PM"

  I mailed the mayor since codex dispatch is their role. Your call: add
  credits now, or accept a 6-day park on anything needing the gate.

✻ Cooked for 3m 4s
───────────────────────────────────────────
❯
───────────────────────────────────────────
  zook@ai-development:~/loomington ctx:22% wk:39%
  ⏵⏵ bypass permissions on (shift+tab to cycle)
PANE
# A live session mid controller churn (`running: null`), parked on the Claude
# banner in its other rendering — "Claude usage limit reached", no possessive.
cat > "$TMP/panes/lx-churn" <<'PANE'
  ⎿  Claude usage limit reached · resets 3pm
     /usage-credits to finish what you're working on.

❯
PANE
# NOT a provider quota park: an ordinary tool/API error on an otherwise idle
# pane. Nudging this session would be noise against an agent that is fine.
cat > "$TMP/panes/lx-apierr" <<'PANE'
  ⎿  Error: API rate limit exceeded for installation. Retry after 60s.
  Retrying the fetch with backoff.

❯
PANE
# Same banner, unquoted, but scrolled up past the tail window — history from a
# block the agent already recovered from, not a park.
{
    printf '  You have hit your usage limit. Try again later.\n'
    for _ in $(seq 14); do printf '  ...output after recovering...\n'; done
    printf '❯\n'
} > "$TMP/panes/lx-scrolled"
cp "$TMP/panes/lx-claude" "$TMP/panes/lx-attached"

# --- Fake gc: only the surface the script touches. --------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "session list") cat "$FAKE_SESSIONS" ;;
  # `exec` so the sleep REPLACES this process: timeout signals its direct child,
  # and an orphaned sleep would hold the caller's command-substitution pipe open
  # long past the bound, hiding the very thing this fixture tests.
  "session peek")
    [ "${FAKE_HANG_PEEK:-}" = "$3" ] && exec sleep 30
    [ -f "$FAKE_PANES/$3" ] && cat "$FAKE_PANES/$3" ;;
  "session nudge")
    shift 2
    [ "$1" = "--delivery" ] && { [ "${FAKE_NO_DELIVERY_FLAG:-0}" = "1" ] && exit 2; shift 2; }
    printf 'nudge %s\n' "$1" >> "$FAKE_NUDGES"
    printf 'msg %s\n' "$2" >> "$FAKE_NUDGES" ;;
  "mail send") printf 'mail %s\n' "$3" >> "$FAKE_MAIL" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_SESSIONS="$TMP/sessions.json" FAKE_PANES="$TMP/panes"
export FAKE_NUDGES="$TMP/nudges" FAKE_MAIL="$TMP/mail"
export QUOTA_PARK_STATE_DIR="$TMP/state"
export QUOTA_PARK_BACKOFF_BASE=120 QUOTA_PARK_BACKOFF_CAP=900
export QUOTA_PARK_ESCALATE_AFTER=7200

# --- Run 1: both parks nudged, nothing else touched. ------------------------
bash "$SCRIPT" > "$TMP/out1"
eq "$(nudges_for lx-claude)"   "1" "Claude session-limit park is nudged"
eq "$(nudges_for lx-codex)"    "1" "Codex usage-limit park is nudged (not provider-specific)"
eq "$(nudges_for lx-churn)"    "1" "parked session with running:null is nudged (liveness is .state)"
eq "$(nudges_for lx-busy)"     "0" "busy pane quoting the banner is NOT nudged"
eq "$(nudges_for lx-clean)"    "0" "clean pane is not nudged"
eq "$(nudges_for lx-quoting)"  "0" "idle agent quoting the banner in a report is NOT nudged"
eq "$(nudges_for lx-scrolled)" "0" "banner scrolled past the tail window is history, not a park"
eq "$(nudges_for lx-apierr)"   "0" "plain API rate-limit error is NOT a provider quota park"
eq "$(nudges_for lx-attached)" "0" "attached session is skipped (human is watching)"
grep -q "3 parked, 3 nudged" "$TMP/out1" && ok "summary counts parked and nudged" \
    || bad "summary counts parked and nudged ($(tail -1 "$TMP/out1"))"

# (i) The nudge text must not match the detector — otherwise our own message
# keeps the episode alive after the agent is back. Read the pattern out of the
# script rather than restating it: a copy here drifts silently, and the drift
# would land on exactly the assertion meant to catch a self-matching nudge.
MSG=$(grep -m1 '^msg ' "$TMP/nudges" | cut -d' ' -f2-)
MATCH_RE=$(grep -m1 '^DEFAULT_MATCH=' "$SCRIPT" | cut -d"'" -f2)
[ -n "$MATCH_RE" ] && ok "detector pattern read from the script" \
    || bad "detector pattern read from the script (DEFAULT_MATCH not found)"
printf '%s\n' "$MSG" | grep -qEi -- "$MATCH_RE" \
    && bad "nudge text must not match the quota detector" \
    || ok "nudge text does not match the quota detector"

# --- Run 2: still parked, inside the backoff window -> no second nudge. -----
bash "$SCRIPT" > /dev/null
eq "$(nudges_for lx-claude)" "1" "no re-nudge inside the backoff window"

# --- Run 3: backoff window elapsed -> nudge again (poll, don't trust the
#            banner's stated reset — here it claims Aug 8th). ----------------
sed -i "s/^last_nudge=.*/last_nudge=$(( $(date +%s) - 200 ))/" "$TMP/state/lx-claude"
bash "$SCRIPT" > /dev/null
eq "$(nudges_for lx-claude)" "2" "re-nudges after the backoff window elapses"
eq "$(grep -c '^attempts=2$' "$TMP/state/lx-claude" || true)" "1" "attempt count advances"

# --- Run 4: agent recovers -> episode ends, state file cleared. -------------
cp "$TMP/panes/lx-clean" "$TMP/panes/lx-claude"
bash "$SCRIPT" > /dev/null
[ -f "$TMP/state/lx-claude" ] && bad "recovered session clears its episode state" \
    || ok "recovered session clears its episode state"
eq "$(nudges_for lx-claude)" "2" "recovered session is not nudged again"

# --- Run 5: a long park escalates exactly once. -----------------------------
sed -i "s/^first_seen=.*/first_seen=$(( $(date +%s) - 9000 ))/;s/^last_nudge=.*/last_nudge=0/" \
    "$TMP/state/lx-codex"
bash "$SCRIPT" > /dev/null
eq "$(grep -c '^mail ' "$TMP/mail" || true)" "1" "long park escalates to a human once"
sed -i "s/^last_nudge=.*/last_nudge=0/" "$TMP/state/lx-codex"
bash "$SCRIPT" > /dev/null
eq "$(grep -c '^mail ' "$TMP/mail" || true)" "1" "escalation is not repeated every cycle"

# --- Run 6: a truncated state file must not abort the sweep. ----------------
cp "$TMP/panes/lx-codex" "$TMP/panes/lx-claude"
rm -f "$TMP/state/lx-claude"
printf 'first_seen=\nattempts=x' > "$TMP/state/lx-codex"
: > "$TMP/nudges"
bash "$SCRIPT" > /dev/null
eq "$(nudges_for lx-codex)"  "1" "corrupt state file is treated as a fresh episode"
eq "$(nudges_for lx-claude)" "1" "corrupt state on one session does not abort the sweep"

# --- Run 7: an older gc without --delivery still recovers the session. ------
cp "$TMP/panes/lx-codex" "$TMP/panes/lx-claude"
rm -f "$TMP/state/lx-claude"
: > "$TMP/nudges"
FAKE_NO_DELIVERY_FLAG=1 bash "$SCRIPT" > /dev/null
eq "$(nudges_for lx-claude)" "1" "falls back to plain nudge when --delivery is unsupported"

# --- Runs 8-9: call bounding. Both drive a peek that never returns, so each
# run is itself capped: a regression that removes the bound then FAILS these
# assertions instead of hanging the suite (and CI behind it) for 30s a run.
# Skipped where the script's own bound cannot exist — with no coreutils
# `timeout` it degrades to unbounded calls by design, so there is nothing here
# to assert.
if ! command -v timeout >/dev/null 2>&1; then
    echo "skip - call-bounding tests (no coreutils timeout on this host)"
else

# --- Run 8: a wedged gc call must not strand the sessions behind it. --------
# lx-claude is first in the session list, and its peek never returns. Without a
# per-call bound the sweep blocks there and every later session — including the
# parked ones this order exists to recover — is never inspected.
rm -f "$TMP/state"/*
: > "$TMP/nudges"
started=$(date +%s)
FAKE_HANG_PEEK=lx-claude QUOTA_PARK_CALL_TIMEOUT=1 QUOTA_PARK_SWEEP_BUDGET=0 \
    timeout 20 bash "$SCRIPT" > "$TMP/out8" || true
elapsed=$(( $(date +%s) - started ))
eq "$(nudges_for lx-codex)"  "1" "a wedged peek does not strand later sessions in the sweep"
eq "$(nudges_for lx-churn)"  "1" "sweep continues past the wedged session to the end of the list"
eq "$(nudges_for lx-claude)" "0" "the wedged session itself is skipped, not nudged blind"
[ "$elapsed" -lt 15 ] && ok "bounded sweep finishes promptly (${elapsed}s)" \
    || bad "bounded sweep finishes promptly (took ${elapsed}s)"

# --- Run 9: past the sweep budget, the remainder defers to the next cycle. --
rm -f "$TMP/state"/*
: > "$TMP/nudges"
FAKE_HANG_PEEK=lx-claude QUOTA_PARK_CALL_TIMEOUT=1 QUOTA_PARK_SWEEP_BUDGET=1 \
    timeout 20 bash "$SCRIPT" > "$TMP/out9" || true
eq "$(nudges_for lx-codex)" "0" "sessions past the sweep budget are deferred, not swept"
grep -q "deferred (sweep budget" "$TMP/out9" && ok "summary reports the deferred remainder" \
    || bad "summary reports the deferred remainder ($(tail -1 "$TMP/out9"))"

fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
