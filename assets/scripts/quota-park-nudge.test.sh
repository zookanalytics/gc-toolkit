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
# scrolled up out of the tail window is history, not a park.
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

# --- Session list: five sessions, one of them attached. ----------------------
cat > "$TMP/sessions.json" <<'JSON'
{"sessions":[
 {"id":"lx-claude","alias":"gc-toolkit/gc-toolkit.witness","state":"active","running":true,"attached":false},
 {"id":"lx-codex","alias":"gc-toolkit/gc-toolkit.ripley","state":"active","running":true,"attached":false},
 {"id":"lx-busy","alias":"gc-toolkit/gc-toolkit.furiosa","state":"active","running":true,"attached":false},
 {"id":"lx-clean","alias":"gc-toolkit/gc-toolkit.refinery","state":"active","running":true,"attached":false},
 {"id":"lx-quoting","alias":"gc-toolkit.su-uzy9","state":"active","running":true,"attached":false},
 {"id":"lx-scrolled","alias":"gc-toolkit.mechanik","state":"active","running":true,"attached":false},
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
  "session peek") [ -f "$FAKE_PANES/$3" ] && cat "$FAKE_PANES/$3" ;;
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
eq "$(nudges_for lx-busy)"     "0" "busy pane quoting the banner is NOT nudged"
eq "$(nudges_for lx-clean)"    "0" "clean pane is not nudged"
eq "$(nudges_for lx-quoting)"  "0" "idle agent quoting the banner in a report is NOT nudged"
eq "$(nudges_for lx-scrolled)" "0" "banner scrolled past the tail window is history, not a park"
eq "$(nudges_for lx-attached)" "0" "attached session is skipped (human is watching)"
grep -q "2 parked, 2 nudged" "$TMP/out1" && ok "summary counts parked and nudged" \
    || bad "summary counts parked and nudged ($(tail -1 "$TMP/out1"))"

# (i) The nudge text must not match the detector — otherwise our own message
# keeps the episode alive after the agent is back.
MSG=$(grep -m1 '^msg ' "$TMP/nudges" | cut -d' ' -f2-)
MATCH_RE="(hit|reached|exceeded) your [a-z0-9 -]{0,24}limit|(session|usage|rate) limit (reached|exceeded)|/usage-credits|limit will reset at"
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

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
