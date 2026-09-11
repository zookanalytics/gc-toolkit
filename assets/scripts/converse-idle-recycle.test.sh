#!/usr/bin/env bash
# Hermetic test for converse-idle-recycle.sh — the auto-opened-sitting reclaim.
# Runs the REAL script with `gc` stubbed (via CONVERSE_IDLE_RECYCLE_GC) — no live
# city, Dolt, sessions, or network.
#
# What each case guards:
#   (UNREADABLE) a session listing that is not JSON reclaims NOTHING, exit 1.
#   (RECYCLE)    unattached + auto_opened + never attended + aged => close the
#                session AND re-park the visit (status=open, assignee="").
#   (YOUNG)      the same, still inside the budget => kept, no close.
#   (PROMOTE)    attached + not-yet-attended => stamp gc.auto_open_attended_at,
#                never close (this pass is the was-ever-attached history).
#   (ATTACHED-AGED) attached + aged => STILL promoted, never drained — the
#                operator's one hard no, regardless of age.
#   (HELD)       attended-then-detached (attended_at set) => kept, never reclaimed.
#   (NOTAUTO)    a visit with no gc.auto_opened (manual engage) is not ours.
#   (CLOSED)     a closed visit is converse-reap's, not ours.
#   (BADALIAS)   an alias that is not a bead id is skipped.
#   (DRY)        --dry-run closes nothing and writes nothing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/converse-idle-recycle.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-idle-recycle-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
has() { grep -qF -- "$2" <<< "$1" && ok "$3" || bad "$3 (in: $1)"; }
hasnt() { grep -qF -- "$2" <<< "$1" && bad "$3 (in: $1)" || ok "$3"; }

[ -f "$SUT" ] && ok "converse-idle-recycle.sh present" || { bad "missing at $SUT"; exit 1; }

mkdir -p "$TMP/bin" "$TMP/fix"
CALLS="$TMP/calls"
OLD="2020-01-01T00:00:00Z"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── stub gc ──────────────────────────────────────────────────────────────────
cat > "$TMP/bin/gc" <<EOF
#!/usr/bin/env bash
echo "gc \$*" >> "$CALLS"
case "\$1 \${2:-}" in
  "session list") cat "$TMP/fix/sessions.json" ;;
  "session close") exit \${FAKE_CLOSE_RC:-0} ;;
  "rig list") echo '{"rigs":[]}' ;;
  "bd show")
    f="$TMP/fix/show-\${3}.json"
    if [ -f "\$f" ]; then cat "\$f"; exit 0; fi
    echo '{"error":"no issues found"}'; exit 1 ;;
  "bd update") exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gc"
export CONVERSE_IDLE_RECYCLE_GC="$TMP/bin/gc"

# vfix <vid> <status> <assignee> <auto_opened> <auto_opened_at> <attended_at> [task_kind=visit]
vfix() {
  jq -n --arg id "$1" --arg st "$2" --arg as "$3" --arg ao "$4" --arg aoat "$5" --arg atat "$6" --arg tk "${7:-visit}" '
    [{id:$id, status:$st, assignee:$as, metadata: (
        {"task_kind":$tk}
        + (if $ao   != "" then {"gc.auto_opened":$ao} else {} end)
        + (if $aoat != "" then {"gc.auto_opened_at":$aoat} else {} end)
        + (if $atat != "" then {"gc.auto_open_attended_at":$atat} else {} end))}]' > "$TMP/fix/show-$1.json"
}
# one converse session bound to <vid>, attached=<true|false>, alias=<rig>/<pack>.<vid>
sess() { printf '{"sessions":[{"id":"lx-sess1","template":"converse-opus","closed":false,"attached":%s,"alias":"gc-toolkit/gc-toolkit.%s"}]}\n' "$1" "$2" > "$TMP/fix/sessions.json"; }
reset() { : > "$CALLS"; rm -f "$TMP/fix/show-"*.json; printf '{"sessions":[]}' > "$TMP/fix/sessions.json"; unset FAKE_CLOSE_RC; }
run() { OUT="$("$SUT" "$@" 2>&1)"; RC=$?; }

# ── (UNREADABLE) ──────────────────────────────────────────────────────────────
reset; printf 'not json' > "$TMP/fix/sessions.json"
run
[ "$RC" = "1" ] && ok "(UNREADABLE) exit 1 on an unreadable listing" || bad "(UNREADABLE) rc=$RC"
hasnt "$(cat "$CALLS")" "session close" "(UNREADABLE) closes nothing"

# ── (RECYCLE) unattached, auto_opened, never attended, aged ───────────────────
reset; sess false tk-v1; vfix tk-v1 open "" 1 "$OLD" ""
run
has "$(cat "$CALLS")" "session close lx-sess1" "(RECYCLE) closes the idle session"
has "$(cat "$CALLS")" "bd update tk-v1" "(RECYCLE) re-parks the visit"
has "$(cat "$CALLS")" "--status=open" "(RECYCLE) reopens the visit"
has "$(cat "$CALLS")" "--assignee=" "(RECYCLE) unassigns the visit"
has "$(cat "$CALLS")" "--unset-metadata gc.auto_opened" "(RECYCLE) clears the auto_opened mark"
has "$OUT" "recycled 1" "(RECYCLE) reports one reclaim"

# ── (YOUNG) inside the budget => kept ─────────────────────────────────────────
reset; sess false tk-v1; vfix tk-v1 open "" 1 "$NOW" ""
run
hasnt "$(cat "$CALLS")" "session close" "(YOUNG) does not close a young sitting"
has "$OUT" "recycled 0" "(YOUNG) reclaims nothing"

# ── (PROMOTE) attached, not yet attended => stamp, no close ───────────────────
reset; sess true tk-v1; vfix tk-v1 in_progress sitting 1 "$OLD" ""
run
hasnt "$(cat "$CALLS")" "session close" "(PROMOTE) never closes an attached sitting"
has "$(cat "$CALLS")" "--set-metadata gc.auto_open_attended_at=" "(PROMOTE) stamps the attended history"
has "$OUT" "promoted 1" "(PROMOTE) reports one promotion"

# ── (ATTACHED-AGED) attached + aged => still promoted, never drained ──────────
reset; sess true tk-v1; vfix tk-v1 in_progress sitting 1 "$OLD" ""
run
hasnt "$(cat "$CALLS")" "session close" "(ATTACHED-AGED) aged + attached is still never drained"

# ── (HELD) attended then detached => kept ─────────────────────────────────────
reset; sess false tk-v1; vfix tk-v1 in_progress sitting 1 "$OLD" "2026-09-11T00:00:00Z"
run
hasnt "$(cat "$CALLS")" "session close" "(HELD) a once-attended sitting is never reclaimed"
has "$OUT" "recycled 0" "(HELD) reclaims nothing"

# ── (NOTAUTO) no gc.auto_opened => not ours ───────────────────────────────────
reset; sess false tk-v1; vfix tk-v1 in_progress sitting "" "" ""
run
hasnt "$(cat "$CALLS")" "session close" "(NOTAUTO) a manually-engaged sitting is left alone"

# ── (CLOSED) closed visit => converse-reap's ──────────────────────────────────
reset; sess false tk-v1; vfix tk-v1 closed sitting 1 "$OLD" ""
run
hasnt "$(cat "$CALLS")" "session close" "(CLOSED) a closed visit is not this pass's"

# ── (BADALIAS) alias not a bead id => skipped ─────────────────────────────────
reset; printf '{"sessions":[{"id":"lx-sess1","template":"converse-opus","closed":false,"attached":false,"alias":"gc-toolkit/gc-toolkit.not_an_id"}]}\n' > "$TMP/fix/sessions.json"
run
hasnt "$(cat "$CALLS")" "session close" "(BADALIAS) an unresolvable alias is skipped"

# ── (DRY) --dry-run changes nothing ───────────────────────────────────────────
reset; sess false tk-v1; vfix tk-v1 open "" 1 "$OLD" ""
run --dry-run
hasnt "$(cat "$CALLS")" "session close" "(DRY) closes nothing"
hasnt "$(cat "$CALLS")" "bd update" "(DRY) writes nothing"
has "$OUT" "would recycle 1" "(DRY) reports the plan"

echo "converse-idle-recycle: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
