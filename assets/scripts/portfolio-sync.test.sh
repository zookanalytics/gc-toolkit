#!/usr/bin/env bash
# portfolio-sync.test.sh — a portfolio sync finds the last sync by the heading
# its own notes write, and lists each epic closed or shifted since.
#
# The po keeps no memory, so the portfolio-sync skill dates the last sync by the
# newest note a sync wrote on the rig's epics, and its read lists what changed
# since that date. The note and the read are two blocks of the same skill, and
# only this suite ties the heading the note writes to the pattern the read
# scans for. A heading that drifted from the pattern would make every sync read
# as a rig's first, and list every epic the rig ever closed.
#
# Hermetic: runs the skill's two blocks in bash, and in zsh where it is
# installed, under a stub gc that answers the list from a fixture and records
# the note. No city, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SKILL="$ROOT/skills/portfolio-sync/SKILL.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-portfolio-sync-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

shells="bash"
command -v zsh >/dev/null 2>&1 && shells="bash zsh"

# block <marker> — the skill's fenced bash block that holds <marker>, with each
# <placeholder> filled with x.
block() {
    awk -v m="$1" '
        /^```bash[ \t]*$/ { inb = 1; buf = ""; hit = 0; next }
        /^```/ && inb { if (hit) { printf "%s", buf; exit } inb = 0; next }
        inb { buf = buf $0 "\n"; if (index($0, m)) hit = 1 }
    ' "$SKILL" | sed -e 's#<[^>]*>#x#g'
}

block 'scan("Portfolio sync, po sitting' >"$TMP/read.sh"
block '--append-notes "Portfolio sync, po sitting' >"$TMP/note.sh"
[ -s "$TMP/read.sh" ] && ok "the skill holds the read of what changed since the last sync" \
    || bad "the skill holds the read of what changed since the last sync" "no fenced bash block in $SKILL scans for the sync's heading"
[ -s "$TMP/note.sh" ] && ok "the skill holds the note a sync writes" \
    || bad "the skill holds the note a sync writes" "no fenced bash block in $SKILL appends a note under the sync's heading"

mkdir -p "$TMP/bin" "$TMP/away"
cat >"$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
# The rig's epics come from $FIXTURE, and a note's text goes to $NOTE_OUT.
case "$1 $2 $3 $4" in
    "bd --rig x list") cat "$FIXTURE" ;;
    "bd --rig x update")
        [ "${5:-}" = x ] && [ "${6:-}" = --append-notes ] || { echo "stub gc: unexpected update: $*" >&2; exit 2; }
        printf '%s' "$7" >"$NOTE_OUT" ;;
    *) echo "stub gc: unexpected call: $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$TMP/bin/gc"

# run <shell> <block> <fixture> — the block's output, run from outside any repo.
run() {
    (cd "$TMP/away" && env -u BASH_ENV -u ENV FIXTURE="$3" NOTE_OUT="$TMP/note" \
        PATH="$TMP/bin:$PATH" $1 "$2" 2>"$TMP/err")
}

# Two syncs noted, the newest on 2026-11-14. Since then, e3 shifted, e5 closed,
# and c1, a child epic with a hypothesis of its own, closed. e7 closed earlier
# on the day of the last sync, which the read counts, since a note carries the
# day only. Before it, e4 shifted and e6 closed. e2's latest ruling is continue,
# and d1 is a Delivery, an epic under an epic with no hypothesis.
cat >"$TMP/synced.json" <<'JSON'
[
  {"id": "e1", "status": "open", "notes": "Portfolio sync, po sitting 2026-11-13: in focus, left unparked.", "metadata": {}},
  {"id": "e2", "status": "open", "notes": "An older note.\nPortfolio sync, po sitting 2026-11-14: parked behind gate g1.", "metadata": {"epic_ruling": "continue", "epic_ruling_at": "2026-11-15T01:00:00Z"}},
  {"id": "e3", "status": "open", "notes": "", "metadata": {"epic_ruling": "shift", "epic_ruling_at": "2026-11-15T02:00:00Z", "epic_ruling_reason": "re-aimed"}},
  {"id": "e4", "status": "open", "metadata": {"epic_ruling": "shift", "epic_ruling_at": "2026-11-12T00:00:00Z", "epic_ruling_reason": "old shift"}},
  {"id": "e5", "status": "closed", "closed_at": "2026-11-15T03:00:00Z", "close_reason": "held", "metadata": {"epic_ruling": "close"}},
  {"id": "e6", "status": "closed", "closed_at": "2026-11-10T00:00:00Z", "close_reason": "old close", "metadata": {"epic_ruling": "close"}},
  {"id": "e7", "status": "closed", "closed_at": "2026-11-14T00:30:00Z", "close_reason": "same day", "metadata": {"epic_ruling": "close"}},
  {"id": "d1", "status": "closed", "parent": "e5", "closed_at": "2026-11-15T03:30:00Z", "close_reason": "checkpoint", "metadata": {}},
  {"id": "c1", "status": "closed", "parent": "e5", "closed_at": "2026-11-15T04:00:00Z", "close_reason": "answered", "metadata": {"epic_hypothesis": "for whom, what changes, and the signal", "epic_ruling": "close"}}
]
JSON
cat >"$TMP/synced.want" <<'WANT'
last sync: 2026-11-14
2026-11-14T00:30:00Z e7 closed: same day
2026-11-15T02:00:00Z e3 shifted: re-aimed
2026-11-15T03:00:00Z e5 closed: held
2026-11-15T04:00:00Z c1 closed: answered
WANT
# The same epics with no sync's note: every close and shift, Deliveries left out.
jq '[.[] | .notes = ""]' "$TMP/synced.json" >"$TMP/first.json"
cat >"$TMP/first.want" <<'WANT'
last sync: none
2026-11-10T00:00:00Z e6 closed: old close
2026-11-12T00:00:00Z e4 shifted: old shift
2026-11-14T00:30:00Z e7 closed: same day
2026-11-15T02:00:00Z e3 shifted: re-aimed
2026-11-15T03:00:00Z e5 closed: held
2026-11-15T04:00:00Z c1 closed: answered
WANT

for sh_ in $shells; do
    sh_run=$sh_
    [ "$sh_" = zsh ] && sh_run="zsh -f"
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/synced.json"); rc=$?
    if [ "$rc" -eq 0 ] && [ "$got" = "$(cat "$TMP/synced.want")" ]; then
        ok "($sh_) the read dates the last sync by the newest sync note, and lists each epic closed or shifted since"
    else
        bad "($sh_) the read dates the last sync by the newest sync note, and lists each epic closed or shifted since" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') $(cat "$TMP/err")"
    fi
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/first.json"); rc=$?
    if [ "$rc" -eq 0 ] && [ "$got" = "$(cat "$TMP/first.want")" ]; then
        ok "($sh_) a rig with no sync noted lists every epic closed or shifted, Deliveries left out"
    else
        bad "($sh_) a rig with no sync noted lists every epic closed or shifted, Deliveries left out" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') $(cat "$TMP/err")"
    fi

    # The note a sync writes today is the one the next sync's read dates it by.
    rm -f "$TMP/note"
    before=$(date -u +%Y-%m-%d)
    run "$sh_run" "$TMP/note.sh" /dev/null >/dev/null; rc=$?
    after=$(date -u +%Y-%m-%d)
    note=$(cat "$TMP/note" 2>/dev/null)
    jq -n --arg n "$note" '[{id: "e1", status: "open", notes: $n, metadata: {}}]' >"$TMP/noted.json"
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/noted.json" | head -n 1)
    if [ "$rc" -eq 0 ] && { [ "$got" = "last sync: $before" ] || [ "$got" = "last sync: $after" ]; }; then
        ok "($sh_) the note a sync writes dates that sync for the next one's read"
    else
        bad "($sh_) the note a sync writes dates that sync for the next one's read" \
            "exit $rc, note: '$note', read: '$got' $(cat "$TMP/err")"
    fi
done

printf '\nportfolio-sync: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
