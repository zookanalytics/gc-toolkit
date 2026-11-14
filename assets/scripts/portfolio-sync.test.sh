#!/usr/bin/env bash
# portfolio-sync.test.sh — a portfolio sync lists each epic closed or shifted
# since a sync last noted that epic, by the heading its own notes write.
#
# The po keeps no memory, so the portfolio-sync skill reads, on each of the
# rig's epics, the newest note a sync wrote there, and lists the epic when it
# closed or shifted on or after that note's day, or has no such note. Each epic
# answers for itself, so a sitting that ends before it notes every epic it
# listed leaves the rest on the next sync's list. The note and the read are two
# blocks of the same skill, and only this suite ties the heading the note
# writes to the pattern the read scans for. A heading that drifted from the
# pattern would leave every epic unnoted, so every sync would list every epic
# the rig ever closed.
#
# The read decides what the sitting weighs by what it lists, so a store that
# did not answer must stop it rather than read as a rig where nothing changed.
# The suite runs it under a gc that fails with no answer, one that fails after
# printing a list, and one that answers with something other than a list.
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
[ -s "$TMP/read.sh" ] && ok "the skill holds the read of what changed since a sync last noted each epic" \
    || bad "the skill holds the read of what changed since a sync last noted each epic" "no fenced bash block in $SKILL scans for the sync's heading"
[ -s "$TMP/note.sh" ] && ok "the skill holds the note a sync writes" \
    || bad "the skill holds the note a sync writes" "no fenced bash block in $SKILL appends a note under the sync's heading"

mkdir -p "$TMP/bin" "$TMP/away"
cat >"$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
# The rig's epics come from $FIXTURE, the list exits $LIST_EXIT, and a note's
# text goes to $NOTE_OUT.
case "$1 $2 $3 $4" in
    "bd --rig x list") cat "$FIXTURE"; exit "${LIST_EXIT:-0}" ;;
    "bd --rig x update")
        [ "${5:-}" = x ] && [ "${6:-}" = --append-notes ] || { echo "stub gc: unexpected update: $*" >&2; exit 2; }
        printf '%s' "$7" >"$NOTE_OUT" ;;
    *) echo "stub gc: unexpected call: $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$TMP/bin/gc"

# run <shell> <block> <fixture> [<list exit>] — the block's output, run from
# outside any repo.
run() {
    (cd "$TMP/away" && env -u BASH_ENV -u ENV FIXTURE="$3" LIST_EXIT="${4:-0}" \
        NOTE_OUT="$TMP/note" PATH="$TMP/bin:$PATH" $1 "$2" 2>"$TMP/err")
}

# Each epic answers for itself. e1 and e2 were noted, and neither closed nor
# shifted since: e2's latest ruling is continue. e3 shifted and e5 closed with
# no sync's note, and so did c1, a child epic with a hypothesis of its own. e4's
# shift and e6's close came before each one's newest note, so a sync weighed
# them, and e6 carries an older note too, from the day it closed. e7 closed on
# the day of its own newest note, which the read lists again, since a note
# carries the day only. p1 was noted when a sync parked it and shifted after.
# d1 is a Delivery, an epic under an epic with no hypothesis. o1 closed under a
# parent that is none of the rig's epics, so it is no Delivery and is listed.
cat >"$TMP/synced.json" <<'JSON'
[
  {"id": "e1", "status": "open", "notes": "Portfolio sync, po sitting 2026-11-13: in focus, left unparked.", "metadata": {}},
  {"id": "e2", "status": "open", "notes": "An older note.\nPortfolio sync, po sitting 2026-11-14: parked behind gate g1.", "metadata": {"epic_ruling": "continue", "epic_ruling_at": "2026-11-15T01:00:00Z"}},
  {"id": "e3", "status": "open", "notes": "", "metadata": {"epic_ruling": "shift", "epic_ruling_at": "2026-11-15T02:00:00Z", "epic_ruling_reason": "re-aimed"}},
  {"id": "e4", "status": "open", "notes": "Portfolio sync, po sitting 2026-11-13: its shift moves nothing.", "metadata": {"epic_ruling": "shift", "epic_ruling_at": "2026-11-12T00:00:00Z", "epic_ruling_reason": "old shift"}},
  {"id": "e5", "status": "closed", "closed_at": "2026-11-15T03:00:00Z", "close_reason": "held", "metadata": {"epic_ruling": "close"}},
  {"id": "e6", "status": "closed", "notes": "Portfolio sync, po sitting 2026-11-10: in focus.\nPortfolio sync, po sitting 2026-11-13: its close brings e2 forward.", "closed_at": "2026-11-10T00:00:00Z", "close_reason": "old close", "metadata": {"epic_ruling": "close"}},
  {"id": "e7", "status": "closed", "notes": "Portfolio sync, po sitting 2026-11-14: its close moves nothing.", "closed_at": "2026-11-14T00:30:00Z", "close_reason": "same day", "metadata": {"epic_ruling": "close"}},
  {"id": "p1", "status": "open", "notes": "Portfolio sync, po sitting 2026-11-13: parked behind gate g2.", "metadata": {"epic_ruling": "shift", "epic_ruling_at": "2026-11-15T06:00:00Z", "epic_ruling_reason": "shifted once parked"}},
  {"id": "d1", "status": "closed", "parent": "e5", "closed_at": "2026-11-15T03:30:00Z", "close_reason": "checkpoint", "metadata": {}},
  {"id": "c1", "status": "closed", "parent": "e5", "closed_at": "2026-11-15T04:00:00Z", "close_reason": "answered", "metadata": {"epic_hypothesis": "for whom, what changes, and the signal", "epic_ruling": "close"}},
  {"id": "o1", "status": "closed", "parent": "t1", "closed_at": "2026-11-15T05:00:00Z", "close_reason": "under a task", "metadata": {"epic_ruling": "close"}}
]
JSON
cat >"$TMP/synced.want" <<'WANT'
2026-11-14T00:30:00Z e7 closed: same day
2026-11-15T02:00:00Z e3 shifted: re-aimed
2026-11-15T03:00:00Z e5 closed: held
2026-11-15T04:00:00Z c1 closed: answered
2026-11-15T05:00:00Z o1 closed: under a task
2026-11-15T06:00:00Z p1 shifted: shifted once parked
WANT
# The same epics with no sync's note: every close and shift, Deliveries left out.
jq '[.[] | .notes = ""]' "$TMP/synced.json" >"$TMP/first.json"
cat >"$TMP/first.want" <<'WANT'
2026-11-10T00:00:00Z e6 closed: old close
2026-11-12T00:00:00Z e4 shifted: old shift
2026-11-14T00:30:00Z e7 closed: same day
2026-11-15T02:00:00Z e3 shifted: re-aimed
2026-11-15T03:00:00Z e5 closed: held
2026-11-15T04:00:00Z c1 closed: answered
2026-11-15T05:00:00Z o1 closed: under a task
2026-11-15T06:00:00Z p1 shifted: shifted once parked
WANT
# An interrupted sitting: a1 and b1 closed on 2026-11-13, and the sync of
# 2026-11-14 noted a1, then ended before it reached b1.
cat >"$TMP/interrupted.json" <<'JSON'
[
  {"id": "a1", "status": "closed", "closed_at": "2026-11-13T09:00:00Z", "close_reason": "weighed", "notes": "Portfolio sync, po sitting 2026-11-14: its close brings e2 forward.", "metadata": {"epic_ruling": "close"}},
  {"id": "b1", "status": "closed", "closed_at": "2026-11-13T10:00:00Z", "close_reason": "not reached", "metadata": {"epic_ruling": "close"}}
]
JSON
cat >"$TMP/interrupted.want" <<'WANT'
2026-11-13T10:00:00Z b1 closed: not reached
WANT
# What the read prints when it lists no epic.
NONE="No epic has closed or shifted since a sync last noted it."
# A store that answers with something other than a list, as when gc relays an
# error in place of the epics.
printf '{"error": "no store"}\n' >"$TMP/notalist.json"
# A rig with no epics answers with an empty list, which is an answer.
printf '[]\n' >"$TMP/empty.json"
# A note that carries a raw control byte, which jq refuses unscrubbed.
printf '[{"id": "k1", "status": "closed", "closed_at": "2026-11-15T07:00:00Z", "close_reason": "kept", "notes": "a raw \001 byte", "metadata": {}}]\n' >"$TMP/ctrl.json"
cat >"$TMP/ctrl.want" <<'WANT'
2026-11-15T07:00:00Z k1 closed: kept
WANT

for sh_ in $shells; do
    sh_run=$sh_
    [ "$sh_" = zsh ] && sh_run="zsh -f"
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/synced.json"); rc=$?
    if [ "$rc" -eq 0 ] && [ "$got" = "$(cat "$TMP/synced.want")" ]; then
        ok "($sh_) the read lists each epic closed or shifted on or after its own newest sync note, or with none"
    else
        bad "($sh_) the read lists each epic closed or shifted on or after its own newest sync note, or with none" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') $(cat "$TMP/err")"
    fi
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/first.json"); rc=$?
    if [ "$rc" -eq 0 ] && [ "$got" = "$(cat "$TMP/first.want")" ]; then
        ok "($sh_) a rig with no sync noted lists every epic closed or shifted, Deliveries left out"
    else
        bad "($sh_) a rig with no sync noted lists every epic closed or shifted, Deliveries left out" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') $(cat "$TMP/err")"
    fi
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/interrupted.json"); rc=$?
    if [ "$rc" -eq 0 ] && [ "$got" = "$(cat "$TMP/interrupted.want")" ]; then
        ok "($sh_) a sitting that ended before it noted every epic leaves the rest on the next sync's list"
    else
        bad "($sh_) a sitting that ended before it noted every epic leaves the rest on the next sync's list" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') $(cat "$TMP/err")"
    fi

    # A store that did not answer stops the read, which lists nothing and says
    # so, rather than reading as a rig where nothing closed or shifted.
    got=$(run "$sh_run" "$TMP/read.sh" /dev/null 17); rc=$?
    if [ "$rc" -ne 0 ] && [ -z "$got" ] && grep -q 'did not read' "$TMP/err"; then
        ok "($sh_) a gc that fails with no answer stops the read, which says so"
    else
        bad "($sh_) a gc that fails with no answer stops the read, which says so" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') stderr: $(cat "$TMP/err")"
    fi
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/synced.json" 1); rc=$?
    if [ "$rc" -ne 0 ] && [ -z "$got" ] && grep -q 'did not read' "$TMP/err"; then
        ok "($sh_) a gc that fails after printing a list stops the read, which says so"
    else
        bad "($sh_) a gc that fails after printing a list stops the read, which says so" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') stderr: $(cat "$TMP/err")"
    fi
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/notalist.json"); rc=$?
    if [ "$rc" -ne 0 ] && [ -z "$got" ] && grep -q 'did not read' "$TMP/err"; then
        ok "($sh_) an answer that is not a list stops the read, which says so"
    else
        bad "($sh_) an answer that is not a list stops the read, which says so" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') stderr: $(cat "$TMP/err")"
    fi
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/empty.json"); rc=$?
    if [ "$rc" -eq 0 ] && [ "$got" = "$NONE" ]; then
        ok "($sh_) a rig with no epics is an answer, not a read that failed"
    else
        bad "($sh_) a rig with no epics is an answer, not a read that failed" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') $(cat "$TMP/err")"
    fi
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/ctrl.json"); rc=$?
    if [ "$rc" -eq 0 ] && [ "$got" = "$(cat "$TMP/ctrl.want")" ]; then
        ok "($sh_) a raw control byte in a note costs the read nothing"
    else
        bad "($sh_) a raw control byte in a note costs the read nothing" \
            "exit $rc, got: $(printf '%s' "$got" | tr '\n' '|') $(cat "$TMP/err")"
    fi

    # The note a sync writes today shows an epic's close before today weighed,
    # and a close made today lists again, since the note carries the day only.
    # y1 closed the last second before today and t1 at today's first, so only
    # a note under today's date passes both.
    rm -f "$TMP/note"
    before=$(date -u +%Y-%m-%d)
    run "$sh_run" "$TMP/note.sh" /dev/null >/dev/null; rc=$?
    after=$(date -u +%Y-%m-%d)
    note=$(cat "$TMP/note" 2>/dev/null)
    y=$(jq -rn --arg d "$before" '$d + "T00:00:00Z" | fromdateiso8601 - 1 | todate')
    jq -n --arg n "$note" --arg y "$y" --arg t "${after}T00:00:00Z" '[
        {id: "y1", status: "closed", closed_at: $y, close_reason: "before today", notes: $n, metadata: {}},
        {id: "t1", status: "closed", closed_at: $t, close_reason: "today", notes: $n, metadata: {}}]' >"$TMP/noted.json"
    got=$(run "$sh_run" "$TMP/read.sh" "$TMP/noted.json")
    if [ "$rc" -eq 0 ] && [ "$got" = "${after}T00:00:00Z t1 closed: today" ]; then
        ok "($sh_) the note a sync writes today shows a close before today weighed, and lists one made today again"
    else
        bad "($sh_) the note a sync writes today shows a close before today weighed, and lists one made today again" \
            "exit $rc, note: '$note', read: '$(printf '%s' "$got" | tr '\n' '|')' $(cat "$TMP/err")"
    fi
done

printf '\nportfolio-sync: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
