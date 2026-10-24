#!/usr/bin/env bash
# Hermetic test for assets/scripts/human-gate.sh — one open human gate per bead
# and situation, and the hand-off at its old name, escalate.sh. Stubbed gc over
# a JSON store; no live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/human-gate.sh"
OLD_NAME="$HERE/escalate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-human-gate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

# The stub models the bd calls the helper makes, as bd 1.3.1 answers them:
#   dep list <bead> --type blocks --json — every bead the given bead waits on
#     through a `blocks` edge, open and closed, each row the far bead's fields
#     plus dependency_type; a bead it cannot find is an error object, exit 1.
#   gate create --type=human --blocks <bead> --await-id <k> --title <t>
#     --reason <r> --json — a gate bead blocking <bead>, its description a line
#     naming <bead> and then the reason; a missing <bead> is an error, exit 1.
#     STUB_CREATE_RACE=<id>|<created_at> files a second writer's gate under the
#     same key on the same bead in the same call, as a writer racing it would.
#   gate resolve <id> --reason <r> — closes an open gate with that reason; on a
#     gate already closed it keeps the first reason and still reports success.
#     STUB_THIRD_WRITER=<id>|<created_at>, at the first resolve, files a third
#     writer's gate under the same key on the beads the resolved gate blocks,
#     and resolves STUB_CREATE_RACE's gate as that gate's duplicate, as the
#     racing writer would once it saw the third gate.
#   show <id> --json — the bead's row; a bead it cannot find is an error object,
#     exit 1. STUB_SHOW_FAIL=1 fails it with nothing on stdout, as a store that
#     did not answer does, STUB_SHOW_RAW=<payload> answers it with that payload
#     verbatim, and STUB_SHOW_RC=<n> exits n after the answer. None touches the
#     other calls.
# The store is a JSON array of beads; EDGES holds `<waiter>|blocks|<gate>` lines.
BIN="$TMP/bin"; mkdir -p "$BIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
STORE="${STUB_STORE:?}"; EDGES="${STUB_EDGES:?}"
{ printf 'CALL'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "${STUB_GC_LOG:?}"
[ "${1:-}" = "bd" ] || exit 0
shift
exists() { jq -e --arg id "$1" 'any(.[]; .id == $id)' "$STORE" >/dev/null 2>&1; }
save() { local t; t=$(mktemp "${STUB_TMP:?}/store.XXXXXX"); cat > "$t" && mv "$t" "$STORE"; }
case "${1:-} ${2:-}" in
  "dep list")
    [ -n "${STUB_DEP_FAIL:-}" ] && { echo "bd: store unreachable" >&2; exit 1; }
    bead="${3:-}"
    exists "$bead" || { printf '{"error":"not found: issue %s","schema_version":1}\n' "$bead"; exit 1; }
    ids=$(awk -F'|' -v b="$bead" '$1 == b && $2 == "blocks" { print $3 }' "$EDGES")
    jq -c --arg ids "$ids" '($ids | split("\n") | map(select(. != ""))) as $w
      | [ .[] | select(.id as $i | $w | index($i)) | . + {dependency_type: "blocks"} ]' "$STORE"
    exit 0 ;;
  "gate create")
    shift 2
    blocks=""; key=""; title=""; reason=""; typ=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --type=*) typ="${1#--type=}" ;;
        --blocks) shift; blocks="${1:-}" ;;
        --await-id) shift; key="${1:-}" ;;
        --title) shift; title="${1:-}" ;;
        --reason) shift; reason="${1:-}" ;;
      esac
      shift || true
    done
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo '{"error":"simulated refusal","schema_version":1}'; exit 1; }
    exists "$blocks" || { printf '{"error":"issue not found: %s","schema_version":1}\n' "$blocks"; exit 1; }
    n=$(cat "$STUB_SEQ"); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    id="gate-$n"
    jq -c --arg id "$id" --arg t "$title" --arg k "$key" --arg ty "$typ" \
      --arg d "Ad-hoc gate blocking $blocks

Reason: $reason" \
      '. + [{id: $id, title: $t, description: $d, status: "open", issue_type: "gate",
             await_type: $ty, await_id: $k, created_at: "2026-10-22T00:00:00Z"}]' "$STORE" | save
    [ -n "${STUB_CREATE_NOEDGE:-}" ] || printf '%s|blocks|%s\n' "$blocks" "$id" >> "$EDGES"
    if [ -n "${STUB_CREATE_RACE:-}" ]; then
      jq -c --arg id "${STUB_CREATE_RACE%%|*}" --arg at "${STUB_CREATE_RACE#*|}" --arg k "$key" --arg ty "$typ" \
        '. + [{id: $id, title: "the racing writer", status: "open", issue_type: "gate",
               await_type: $ty, await_id: $k, created_at: $at}]' "$STORE" | save
      printf '%s|blocks|%s\n' "$blocks" "${STUB_CREATE_RACE%%|*}" >> "$EDGES"
    fi
    jq -c --arg id "$id" '.[] | select(.id == $id)' "$STORE"
    exit 0 ;;
  "gate resolve")
    id="${3:-}"; shift 3
    reason=""
    while [ $# -gt 0 ]; do case "$1" in --reason) shift; reason="${1:-}" ;; esac; shift || true; done
    exists "$id" || { echo "Error: gate not found: $id" >&2; exit 1; }
    [ "$(jq -r --arg id "$id" '.[] | select(.id == $id) | .issue_type' "$STORE")" = gate ] \
      || { echo "Error: $id is not a gate issue" >&2; exit 1; }
    # A third writer, whose gate came first but was not in this call's
    # read-back, resolves the racing writer's gate as its own duplicate in the
    # same instant, once.
    if [ -n "${STUB_THIRD_WRITER:-}" ] && [ ! -e "$STUB_TMP/third-writer.done" ]; then
      : > "$STUB_TMP/third-writer.done"
      zid="${STUB_THIRD_WRITER%%|*}"; zat="${STUB_THIRD_WRITER#*|}"; rid="${STUB_CREATE_RACE%%|*}"
      k=$(jq -r --arg id "$id" '.[] | select(.id == $id) | .await_id' "$STORE")
      jq -c --arg z "$zid" --arg at "$zat" --arg k "$k" --arg r "$rid" \
        'map(if .id == $r then .status = "closed" | .closed_at = "2026-10-22T00:00:01Z"
               | .close_reason = ("moot: a duplicate of gate " + $z + ", filed for the same situation in the same instant")
             else . end)
         + [{id: $z, title: "the third writer", status: "open", issue_type: "gate",
             await_type: "human", await_id: $k, created_at: $at}]' "$STORE" | save
      extra=$(awk -F'|' -v g="$id" -v z="$zid" '$2 == "blocks" && $3 == g { print $1 "|blocks|" z }' "$EDGES")
      [ -z "$extra" ] || printf '%s\n' "$extra" >> "$EDGES"
    fi
    [ -n "${STUB_RESOLVE_NOOP:-}" ] && { echo "✓ Gate resolved: $id"; exit 0; }
    [ -n "${STUB_RESOLVE_FAIL:-}" ] && { echo "Error: simulated refusal" >&2; exit 1; }
    # Another resolver closes the gate first, as a sitting's sign-off can.
    if [ -n "${STUB_RESOLVE_RACE:-}" ]; then
      jq -c --arg id "$id" 'map(if .id == $id and .status != "closed"
        then .status = "closed" | .close_reason = "ruled: answered in the sitting" | .closed_at = "2026-10-22T00:00:01Z"
        else . end)' "$STORE" | save
    fi
    now=$(jq -nr 'now | todate')
    jq -c --arg id "$id" --arg r "$reason" --arg at "$now" 'map(if .id == $id and .status != "closed"
      then .status = "closed" | .close_reason = $r | .closed_at = $at else . end)' "$STORE" | save
    printf '✓ Gate resolved: %s\n  Reason: %s\n' "$id" "$reason"
    exit 0 ;;
esac
case "${1:-}" in
  show)
    [ -n "${STUB_SHOW_FAIL:-}" ] && { echo "bd: store unreachable" >&2; exit 1; }
    [ -n "${STUB_SHOW_RAW:-}" ] && { printf '%s\n' "$STUB_SHOW_RAW"; exit 0; }
    out=$(jq -c --arg id "${2:-}" '[.[] | select(.id == $id)]' "$STORE")
    if [ "$(printf '%s' "$out" | jq 'length')" = 0 ]; then
      printf '{"error":"no issue found matching %s"}\n' "${2:-}"; exit 1
    fi
    printf '%s\n' "$out"
    exit "${STUB_SHOW_RC:-0}" ;;
  *) echo "stub gc: unexpected bd call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$BIN/gc"

export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/store.json" STUB_EDGES="$TMP/edges" STUB_GC_LOG="$TMP/gc.log" STUB_SEQ="$TMP/seq" STUB_TMP="$TMP"
unset GC_AGENT GC_RIG GC_ESCALATE_VERDICT_WINDOW 2>/dev/null || true

# iso_ago <seconds> — an RFC-3339 UTC time that many seconds ago.
iso_ago() { jq -nr --argjson s "$1" '(now - $s) | floor | todate'; }
task()   { printf '{"id":"%s","title":"%s","status":"open","issue_type":"task"}' "$1" "$1"; }
session() { printf '{"id":"%s","title":"%s","status":"open","issue_type":"session"}' "$1" "$1"; }
# gate <id> <key> <status> [<close_reason> <closed_at>] [<await_type>]
gate() {
  jq -nc --arg id "$1" --arg k "$2" --arg st "$3" --arg r "${4:-}" --arg at "${5:-}" --arg ty "${6:-human}" \
    '{id: $id, title: ("asks " + $k), status: $st, issue_type: "gate", await_type: $ty, await_id: $k,
      created_at: "2026-10-21T00:00:00Z"}
     + (if $r == "" then {} else {close_reason: $r, closed_at: $at} end)'
}
reset() {
  local beads="${1:-}"
  printf '[%s]' "$beads" > "$STUB_STORE"
  printf '%s' "${2:-}" > "$STUB_EDGES"
  : > "$STUB_GC_LOG"; printf '0' > "$STUB_SEQ"; rm -f "$STUB_TMP/third-writer.done"
  unset STUB_DEP_FAIL STUB_CREATE_FAIL STUB_CREATE_NOEDGE STUB_CREATE_RACE STUB_RESOLVE_NOOP STUB_RESOLVE_FAIL STUB_RESOLVE_RACE STUB_THIRD_WRITER STUB_SHOW_FAIL STUB_SHOW_RAW STUB_SHOW_RC 2>/dev/null || true
}
field()   { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .[$k]) // "<absent>"' "$STUB_STORE"; }
creates() { cat "$STUB_SEQ"; }
calls()   { cat "$STUB_GC_LOG"; }

echo "# files a native human gate that blocks the subject"
reset "$(task tk-w)"
out=$("$SUT" --subject tk-w --key polecat-blocked --message "Blocked: the target branch is gone. Need: a new target." 2>"$TMP/err"); rc=$?
err=$(cat "$TMP/err")
eq "$rc" 0 "filing exits 0"
eq "$(creates)" 1 "exactly one gate filed"
eq "$out" "gate-1" "stdout is the id of the gate it filed"
eq "$(field gate-1 issue_type)" "gate" "the bead is a gate"
eq "$(field gate-1 await_type)" "human" "its await type is human"
eq "$(field gate-1 await_id)" "polecat-blocked" "its await id is the situation key"
has "$(cat "$STUB_EDGES")" "tk-w|blocks|gate-1" "it blocks the subject"
eq "$(field gate-1 title)" "Blocked: the target branch is gone. Need: a new target." "its title is the message's first line"
has "$(field gate-1 description)" "Need: a new target." "its description carries the message"
has "$(calls)" "[gate] [create] [--type=human] [--blocks] [tk-w] [--await-id] [polecat-blocked]" "the create names the subject as its own word after --blocks"
hasnt "$(calls)" "[--db]" "no --db pin: gc bd files the gate in the subject's own store"
hasnt "$(calls)" "[--rig]" "no --rig either"
hasnt "$(calls)" "[create] [-t]" "no plain bd create: no visit is filed"
has "$err" "filed gate gate-1 on tk-w [polecat-blocked]" "it reports what it filed on stderr"

echo "# the title is the first line, cut at 140 characters with an ellipsis"
long=$(printf 'word%.0s ' $(seq 1 60))
reset "$(task tk-w)"
"$SUT" --subject tk-w --key k --message "$long
second line" >/dev/null 2>&1
t=$(field gate-1 title)
eq "$(printf '%s' "$t" | jq -Rr 'length')" "140" "an over-long first line is cut to 140 characters"
has "$t" "…" "the cut is marked with an ellipsis"
hasnt "$t" "second line" "only the first line becomes the title"
has "$(field gate-1 description)" "second line" "the description keeps the whole message"

echo "# an open human gate under the key already asks: nothing more is filed"
reset "$(task tk-w),$(gate g-open polecat-blocked open)" "tk-w|blocks|g-open
"
out=$("$SUT" --subject tk-w --key polecat-blocked --message m 2>"$TMP/err"); rc=$?
eq "$rc" 0 "the dedup exits 0"
eq "$(creates)" 0 "no second gate"
eq "$out" "g-open" "stdout is the open gate's id"
has "$(cat "$TMP/err")" "already asks" "it says the person is already asked"

echo "# a gate filed on another bead that the subject waits on counts too"
# A rework child waits on its anchor's bring-current gate through its own edge,
# so a child-side call under the same key files nothing more.
reset "$(task tk-anchor),$(task tk-child),$(gate g-bc bring-current-conflict open)" "tk-anchor|blocks|g-bc
tk-child|blocks|g-bc
"
out=$("$SUT" --subject tk-child --key bring-current-conflict --message m 2>/dev/null); rc=$?
eq "$rc" 0 "exits 0"
eq "$(creates)" 0 "nothing filed: the child already waits on the anchor's gate"
eq "$out" "g-bc" "it names that gate"

echo "# only an open human gate under this key dedups"
reset "$(task tk-w),$(gate g-other other-key open),$(gate g-pr polecat-blocked open "" "" gh:pr),$(gate g-closed polecat-blocked closed "ruled: go ahead" "$(iso_ago 60)")" \
"tk-w|blocks|g-other
tk-w|blocks|g-pr
tk-w|blocks|g-closed
"
out=$("$SUT" --subject tk-w --key polecat-blocked --message m 2>/dev/null); rc=$?
eq "$rc" 0 "exits 0"
eq "$(creates)" 1 "a gate under another key, a gate of another await type and a closed gate leave the situation unasked"
eq "$out" "gate-1" "and it files a new one"

echo "# a human gate the subject does not wait on is not its gate"
# The await id is read only among the subject's own blocks edges; a gate under
# the same key that blocks another bead asks about that bead.
reset "$(task tk-w),$(task tk-x),$(gate g-x polecat-blocked open)" "tk-x|blocks|g-x
"
"$SUT" --subject tk-w --key polecat-blocked --message m >/dev/null 2>&1
eq "$(creates)" 1 "a gate on another bead does not dedup this bead's situation"

echo "# of two open gates under the key, the first by created_at, then id, asks"
# bd lists g-b ahead of g-a here; both were created in the same second.
reset "$(task tk-w),$(gate g-b k open),$(gate g-a k open)" "tk-w|blocks|g-b
tk-w|blocks|g-a
"
out=$("$SUT" --subject tk-w --key k --message m 2>/dev/null)
eq "$out" "g-a" "the dedup names the gate whose id sorts first, not bd's listing order"

echo "# a writer that raced another resolves its own gate when the other's comes first"
reset "$(task tk-w)"
out=$(STUB_CREATE_RACE="g-early|2026-10-21T23:59:59Z" "$SUT" --subject tk-w --key k --message m 2>"$TMP/err"); rc=$?
eq "$rc" 0 "exits 0"
eq "$out" "g-early" "stdout names the racing writer's gate, which came first"
eq "$(field gate-1 status)" "closed" "this call's own gate is resolved"
has "$(field gate-1 close_reason)" "moot: a duplicate of gate g-early" "as a duplicate of the first, headed moot:"
eq "$(field g-early status)" "open" "the first gate stands, so one answer clears the bead"
has "$(cat "$TMP/err")" "resolved this call's duplicate, gate gate-1" "it reports the duplicate it resolved"
reset "$(task tk-w)"
out=$(STUB_CREATE_RACE="g-0|2026-10-22T00:00:00Z" "$SUT" --subject tk-w --key k --message m 2>/dev/null)
eq "$out" "g-0" "in the same second, the gate whose id sorts first is the first"
eq "$(field gate-1 status)" "closed" "and the other writer's call resolves its own"

echo "# with three writers racing, the gate named is the one still open"
# This call reads back its own gate and the racing writer's. As this call
# resolves its own, the racing writer sees a third gate that came first and
# resolves its gate as that one's duplicate.
reset "$(task tk-w)"
out=$(STUB_CREATE_RACE="g-early|2026-10-21T23:59:59Z" STUB_THIRD_WRITER="g-first|2026-10-21T23:59:58Z" "$SUT" --subject tk-w --key k --message m 2>"$TMP/err"); rc=$?
eq "$rc" 0 "exits 0"
eq "$(field gate-1 status)" "closed" "this call's own gate is resolved as a duplicate"
eq "$(field g-early status)" "closed" "the racing writer's gate is resolved by its own writer"
eq "$out" "g-first" "stdout names the third writer's gate, the one still open, not the racing writer's"
has "$(cat "$TMP/err")" "gate g-first already asks for tk-w [k]" "  ... and stderr says so"

echo "# a writer whose gate comes first keeps it and leaves the other's alone"
reset "$(task tk-w)"
out=$(STUB_CREATE_RACE="g-late|2026-10-22T00:00:01Z" "$SUT" --subject tk-w --key k --message m 2>/dev/null); rc=$?
eq "$rc" 0 "exits 0"
eq "$out" "gate-1" "stdout names its own gate"
eq "$(field gate-1 status)" "open" "its own gate stands"
eq "$(field g-late status)" "open" "the other writer's gate is that writer's to resolve"

echo "# a duplicate that does not resolve is reported with its repair"
reset "$(task tk-w)"
out=$(STUB_CREATE_RACE="g-early|2026-10-21T23:59:59Z" STUB_RESOLVE_FAIL=1 "$SUT" --subject tk-w --key k --message m 2>"$TMP/err"); rc=$?
eq "$rc" 0 "exits 0: the first gate still asks"
eq "$out" "g-early" "stdout names the gate that asks"
has "$(cat "$TMP/err")" "repair: gc bd gate resolve gate-1" "the repair names the duplicate"

echo "# the duplicate is read back, because bd reports success on a resolve that closed nothing"
reset "$(task tk-w)"
out=$(STUB_CREATE_RACE="g-early|2026-10-21T23:59:59Z" STUB_RESOLVE_NOOP=1 "$SUT" --subject tk-w --key k --message m 2>"$TMP/err"); rc=$?
eq "$rc" 0 "exits 0: the first gate still asks"
eq "$out" "g-early" "stdout names the gate that asks"
eq "$(field gate-1 status)" "open" "the duplicate is still open"
has "$(cat "$TMP/err")" "did not resolve (its status reads 'open')" "the read-back reports that it stayed open"
has "$(cat "$TMP/err")" "repair: gc bd gate resolve gate-1" "  ... with the repair"
hasnt "$(cat "$TMP/err")" "resolved this call's duplicate" "  ... and never claims it resolved"
reset "$(task tk-w)"
STUB_CREATE_RACE="g-early|2026-10-21T23:59:59Z" STUB_RESOLVE_RACE=1 "$SUT" --subject tk-w --key k --message m >/dev/null 2>"$TMP/err"; rc=$?
eq "$rc" 0 "a duplicate another resolver cleared first is no failure"
has "$(cat "$TMP/err")" "was already cleared, and its answer stands: ruled: answered in the sitting" "  ... and the answer that stood is reported"

echo "# no quiet period unless the call declares one"
recent_moot="$(gate g-moot k closed "moot: the branch came back" "$(iso_ago 600)")"
reset "$(task tk-w),$recent_moot" "tk-w|blocks|g-moot
"
GC_ESCALATE_VERDICT_WINDOW=86400 "$SUT" --subject tk-w --key k --message m >/dev/null 2>&1; rc=$?
eq "$rc" 0 "exits 0"
eq "$(creates)" 1 "a moot answer ten minutes ago mutes nothing without --quiet-window, whatever GC_ESCALATE_VERDICT_WINDOW says"

echo "# a declared quiet window holds a re-detection after a moot or benign answer"
for head in moot benign; do
  reset "$(task tk-w),$(gate g-q k closed "$head: needs nobody" "$(iso_ago 600)")" "tk-w|blocks|g-q
"
  out=$("$SUT" --subject tk-w --key k --message m --quiet-window 3600 2>"$TMP/err"); rc=$?
  eq "$rc" 0 "$head: exits 0"
  eq "$(creates)" 0 "$head: nothing filed inside the window"
  eq "$out" "" "$head: nothing on stdout, because no gate asks"
  has "$(cat "$TMP/err")" "quiet window" "$head: it says the window held it"
done

echo "# the window ends, and only the newest closed gate decides"
reset "$(task tk-w),$(gate g-old k closed "moot: stale" "$(iso_ago 7200)")" "tk-w|blocks|g-old
"
"$SUT" --subject tk-w --key k --message m --quiet-window 3600 >/dev/null 2>&1
eq "$(creates)" 1 "an answer older than the window holds nothing"
reset "$(task tk-w),$(gate g-moot2 k closed "moot: gone" "$(iso_ago 1200)"),$(gate g-ruled k closed "ruled: fix it" "$(iso_ago 300)")" \
"tk-w|blocks|g-moot2
tk-w|blocks|g-ruled
"
"$SUT" --subject tk-w --key k --message m --quiet-window 3600 >/dev/null 2>&1
eq "$(creates)" 1 "a newer ruled answer means the person acted, so an older moot behind it mutes nothing"
reset "$(task tk-w),$(gate g-ruled2 k closed "ruled: fix it" "$(iso_ago 300)")" "tk-w|blocks|g-ruled2
"
"$SUT" --subject tk-w --key k --message m --quiet-window 3600 >/dev/null 2>&1
eq "$(creates)" 1 "a ruled answer opens no window"

echo "# a duplicate a writer resolved is no person's answer, so the window skips it"
# The duplicate's repair ran after the person answered the first gate, so the
# duplicate is the newest closed gate under the key.
dup_reason="moot: a duplicate of gate g-first, filed for the same situation in the same instant"
reset "$(task tk-w),$(gate g-first k closed "ruled: fix it" "$(iso_ago 600)"),$(gate g-dup k closed "$dup_reason" "$(iso_ago 60)")" \
"tk-w|blocks|g-first
tk-w|blocks|g-dup
"
"$SUT" --subject tk-w --key k --message m --quiet-window 3600 >/dev/null 2>&1
eq "$(creates)" 1 "the person ruled, so a re-detection files, though the duplicate closed moot after that"
reset "$(task tk-w),$(gate g-first k closed "moot: it healed" "$(iso_ago 600)"),$(gate g-dup k closed "$dup_reason" "$(iso_ago 60)")" \
"tk-w|blocks|g-first
tk-w|blocks|g-dup
"
"$SUT" --subject tk-w --key k --message m --quiet-window 3600 >/dev/null 2>"$TMP/err"
eq "$(creates)" 0 "the person answered moot, so the window holds"
has "$(cat "$TMP/err")" "on gate g-first (moot: it healed)" "  ... and names the person's answer, not the duplicate"

echo "# a bead with open children is filed on like any other"
# What a gate on a parent pauses is the caller's call-site policy; the helper
# refuses no bead for its shape and reads no children.
reset "$(task tk-epic),$(task tk-epic.1)"
"$SUT" --subject tk-epic --key k --message m >/dev/null 2>&1; rc=$?
eq "$rc" 0 "exits 0"
eq "$(creates)" 1 "the gate is filed on the parent"
hasnt "$(calls)" "[--parent]" "no children were read"

echo "# a wisp or a session names no bead that can wait, and is refused"
for subj in lx-wisp-abc12 tk-wisp-9f; do
  reset "$(task "$subj")"
  err=$("$SUT" --subject "$subj" --key k --message m 2>&1 >/dev/null); rc=$?
  eq "$rc" 2 "$subj: refused with exit 2"
  eq "$(creates)" 0 "$subj: nothing filed"
  eq "$(calls)" "" "$subj: no bd call at all"
  has "$err" "patrol-finding.sh" "$subj: it names the patrol finding as the durable route"
  "$SUT" --retract --subject "$subj" --key k --message m >/dev/null 2>&1; rc=$?
  eq "$rc" 2 "$subj: a retract on it is refused too"
done

echo "# a subject that names no bead files nothing"
reset "$(task tk-w)"
err=$("$SUT" --subject tk-nope --key k --message m 2>&1 >/dev/null); rc=$?
eq "$rc" 1 "exit 1"
eq "$(creates)" 0 "nothing filed"
has "$err" "could not read the human gates of 'tk-nope'" "it says the bead could not be read"

echo "# an unreadable store files nothing: an unread gate may already ask"
reset "$(task tk-w)"
STUB_DEP_FAIL=1 "$SUT" --subject tk-w --key k --message m >/dev/null 2>&1; rc=$?
eq "$rc" 1 "exit 1"
eq "$(creates)" 0 "nothing filed"

echo "# a create that returns no id is a failure"
reset "$(task tk-w)"
err=$(STUB_CREATE_FAIL=1 "$SUT" --subject tk-w --key k --message m 2>&1 >/dev/null); rc=$?
eq "$rc" 1 "exit 1"
has "$err" "simulated refusal" "bd's own reason is reported"

echo "# a gate that does not read back as blocking the subject is a failure"
reset "$(task tk-w)"
out=$(STUB_CREATE_NOEDGE=1 "$SUT" --subject tk-w --key k --message m 2>"$TMP/err"); rc=$?
eq "$rc" 1 "exit 1"
eq "$out" "" "no id is reported as asking"
has "$(cat "$TMP/err")" "repair: gc bd dep add tk-w gate-1 --type=blocks" "the repair names the missing edge"

echo "# usage"
reset "$(task tk-w)"
"$SUT" --subject tk-w --key k >/dev/null 2>&1; eq "$?" 2 "a missing --message is a usage error"
"$SUT" --subject tk-w --key "bad key" --message m >/dev/null 2>&1; eq "$?" 2 "a key outside [A-Za-z0-9._-] is refused"
"$SUT" --subject "tk-w tk-x" --key k --message m >/dev/null 2>&1; eq "$?" 2 "a subject of two words is refused"
"$SUT" --subject tk-w --key k --message m --pool gc-toolkit/gc-toolkit.polecat >/dev/null 2>&1; eq "$?" 2 "--pool is retired: a gate is not routed"
"$SUT" --subject tk-w --key k --message m --quiet-window 1h >/dev/null 2>&1; eq "$?" 2 "--quiet-window takes whole seconds"
"$SUT" --retract --subject tk-w --key k --message m --quiet-window 60 >/dev/null 2>&1; eq "$?" 2 "--retract keeps no window"
eq "$(creates)" 0 "no usage error files anything"

echo "# --retract resolves each open gate under the key, once, as moot"
reset "$(task tk-a),$(task tk-b),$(gate g1 k open),$(gate g2 k open),$(gate g3 other open),$(gate g4 k closed "ruled: earlier" "$(iso_ago 60)")" \
"tk-a|blocks|g1
tk-a|blocks|g2
tk-b|blocks|g2
tk-a|blocks|g3
tk-a|blocks|g4
"
out=$("$SUT" --retract --subject tk-a --key k --message "the branch came back" 2>"$TMP/err"); rc=$?
eq "$rc" 0 "the retract exits 0"
eq "$(field g1 status)" "closed" "g1 resolved"
eq "$(field g1 close_reason)" "moot: the branch came back" "its reason is the reading, headed moot:"
eq "$(field g2 status)" "closed" "g2, which blocks two beads, resolved too"
eq "$(grep -c '\[resolve\] \[g2\]' "$STUB_GC_LOG")" "1" "a gate that blocks two beads is resolved once"
eq "$(field g3 status)" "open" "a gate under another key is left alone"
eq "$(field g4 close_reason)" "ruled: earlier" "a closed gate is left alone"
eq "$out" "g1
g2" "stdout lists the gates it resolved"
eq "$(creates)" 0 "a retract files nothing"

echo "# --retract with nothing open is a no-op success"
reset "$(task tk-a),$(gate g3 other open)" "tk-a|blocks|g3
"
out=$("$SUT" --retract --subject tk-a --key k --message m 2>"$TMP/err"); rc=$?
eq "$rc" 0 "exit 0"
eq "$out" "" "nothing resolved"
has "$(cat "$TMP/err")" "nothing to withdraw" "it says so"

echo "# --retract reads back each gate and reports an answer that stood"
reset "$(task tk-a),$(gate g1 k open)" "tk-a|blocks|g1
"
err=$(STUB_RESOLVE_RACE=1 "$SUT" --retract --subject tk-a --key k --message m 2>&1 >/dev/null); rc=$?
eq "$rc" 0 "a gate another resolver closed first is no failure"
eq "$(field g1 close_reason)" "ruled: answered in the sitting" "the first answer stands"
has "$err" "already cleared; its answer stands: ruled: answered in the sitting" "and is reported"

echo "# --retract fails when a gate does not close"
reset "$(task tk-a),$(gate g1 k open)" "tk-a|blocks|g1
"
err=$(STUB_RESOLVE_NOOP=1 "$SUT" --retract --subject tk-a --key k --message m 2>&1 >/dev/null); rc=$?
eq "$rc" 1 "exit 1"
has "$err" "did not resolve" "it names the gate that stayed open"

echo "# --retract on an unreadable bead fails closed"
reset "$(task tk-a)"
STUB_DEP_FAIL=1 "$SUT" --retract --subject tk-a --key k --message m >/dev/null 2>&1; rc=$?
eq "$rc" 1 "an unread gate list is not proof that nothing is open"

echo "# the old name hands a call to human-gate.sh"
reset "$(task tk-w)"
out=$("$OLD_NAME" --subject tk-w --key k --message "via the old name" 2>/dev/null); rc=$?
eq "$rc" 0 "escalate.sh files through the helper"
eq "$out" "gate-1" "with the helper's output"
eq "$(field gate-1 await_id)" "k" "the gate carries the key"
out=$("$OLD_NAME" --retract --subject tk-w --key k --message gone 2>/dev/null); rc=$?
eq "$rc" 0 "a retract through the old name works too"
eq "$(field gate-1 close_reason)" "moot: gone" "and resolves the gate"
"$OLD_NAME" --subject tk-w --key "bad key" --message m >/dev/null 2>&1
eq "$?" 2 "the helper's own refusals come back through the old name"

echo "# the old name drops the retired --pool, so an old call still files"
reset "$(task tk-w)"
out=$("$OLD_NAME" --subject tk-w --key k --message m --pool gc-toolkit/gc-toolkit.converse 2>"$TMP/err"); rc=$?
eq "$rc" 0 "a call that carries --pool exits 0"
eq "$out" "gate-1" "and files its gate through the helper"
has "$(cat "$TMP/err")" "--pool gc-toolkit/gc-toolkit.converse dropped" "the dropped flag is reported on stderr"

echo "# the old name files a call on a wisp as a patrol finding"
# The hand-off runs from a private copy whose patrol-finding.sh records what
# reached it.
HSUT="$TMP/handoff-sut"; mkdir -p "$HSUT"
cp "$OLD_NAME" "$SUT" "$HERE/bd-lib.sh" "$HSUT/"
cat > "$HSUT/patrol-finding.sh" <<'PFSTUB'
#!/usr/bin/env bash
{ printf 'patrol-finding'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "${STUB_PF_LOG:?}"
exit "${STUB_PF_RC:-0}"
PFSTUB
chmod +x "$HSUT"/*.sh
export STUB_PF_LOG="$TMP/pf.log"
reset "$(task tk-w)"; : > "$STUB_PF_LOG"
"$HSUT/escalate.sh" --subject lx-wisp-abc12 --key refinery-empty-identity --message "Refinery session started with empty GC_AGENT
Investigate the session harness." >/dev/null 2>"$TMP/err"; rc=$?
eq "$rc" 0 "the call exits with the finding's exit"
has "$(cat "$STUB_PF_LOG")" "patrol-finding [--key] [refinery-empty-identity] [--title] [Refinery session started with empty GC_AGENT] [--message] [Refinery session started with empty GC_AGENT" \
  "the finding takes the key, the message's first line as its title, and the whole message"
has "$(cat "$STUB_PF_LOG")" "Investigate the session harness.]" "the message keeps its later lines"
eq "$(calls)" "" "no gate is filed on the wisp, and no bd call is made"
has "$(cat "$TMP/err")" "filing the call as a patrol finding under [refinery-empty-identity]" "the translation is reported on stderr"
: > "$STUB_PF_LOG"
STUB_PF_RC=1 "$HSUT/escalate.sh" --subject lx-wisp-abc12 --key k --message m >/dev/null 2>&1
eq "$?" 1 "a finding that was not filed fails the call"
: > "$STUB_PF_LOG"
"$HSUT/escalate.sh" --retract --subject lx-wisp-abc12 --key k --message m >/dev/null 2>&1
eq "$?" 2 "a retract on a wisp goes to the helper, which refuses it"
eq "$(cat "$STUB_PF_LOG")" "" "and files no finding"

echo "# the old name files a call about a subject that names no bead as a patrol finding"
# The copy's bead-store.sh records what it is asked and answers with STUB_BS_RC.
cat > "$HSUT/bead-store.sh" <<'BSSTUB'
#!/usr/bin/env bash
{ printf 'bead-store'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "${STUB_BS_LOG:?}"
exit "${STUB_BS_RC:-0}"
BSSTUB
chmod +x "$HSUT/bead-store.sh"
export STUB_BS_LOG="$TMP/bs.log"
reset "$(task tk-w)"; : > "$STUB_PF_LOG"; : > "$STUB_BS_LOG"
STUB_BS_RC=1 "$HSUT/escalate.sh" --subject refinery --key refinery-empty-identity --message m >/dev/null 2>"$TMP/err"; rc=$?
eq "$rc" 0 "a subject bead-store.sh proves names no bead files a finding"
eq "$(cat "$STUB_BS_LOG")" "bead-store [refinery]" "  ... asked in bead-store.sh's resolution form"
eq "$(cat "$STUB_PF_LOG")" "patrol-finding [--key] [refinery-empty-identity] [--title] [m] [--message] [m]" "  ... under its key"
eq "$(creates)" 0 "  ... and no gate is filed"
has "$(cat "$TMP/err")" "'refinery' names no bead" "  ... and the translation says why on stderr"

echo "# the old name files a call about a session as a patrol finding, whatever the shape of its id"
reset "$(task tk-w),$(session lx-abc12)"; : > "$STUB_PF_LOG"
"$HSUT/escalate.sh" --subject lx-abc12 --key witness-refinery-queue-unreadable --message m >/dev/null 2>"$TMP/err"; rc=$?
eq "$rc" 0 "a subject that reads as a session bead files a finding"
eq "$(cat "$STUB_PF_LOG")" "patrol-finding [--key] [witness-refinery-queue-unreadable] [--title] [m] [--message] [m]" "  ... under its key"
eq "$(creates)" 0 "  ... and no gate blocks the session bead"
has "$(cat "$TMP/err")" "'lx-abc12' names a session" "  ... and the translation says why on stderr"
reset "$(task tk-w),$(session lx-abc12)"; : > "$STUB_PF_LOG"
STUB_SHOW_RAW="$(printf 'gc bd: answering from the city store\n[{"id":"lx-abc12","title":"a\001b","status":"open","issue_type":"session"}]')" \
  "$HSUT/escalate.sh" --subject lx-abc12 --key k --message m >/dev/null 2>&1; rc=$?
eq "$rc" 0 "a session row behind the store's notice line, carrying a raw control byte, still reads as a session"
eq "$(cat "$STUB_PF_LOG")" "patrol-finding [--key] [k] [--title] [m] [--message] [m]" "  ... and the call files its finding"
eq "$(creates)" 0 "  ... with no gate on the session bead"

echo "# a subject whose own row does not read fails the call before the helper"
# The helper's reads of the subject's edges and its create stay available in
# every case, so a call let through to the helper would file a gate on the
# session in place of its finding.
# unread_case <label> <stub-knob> — a call about session lx-abc12 whose row
# reads wrong under the knob.
unread_case() {
  reset "$(task tk-w),$(session lx-abc12)"; : > "$STUB_PF_LOG"
  out=$(env "$2" "$HSUT/escalate.sh" --subject lx-abc12 --key k --message m 2>"$TMP/err"); rc=$?
  eq "$rc" 1 "$1: the call exits 1, so its caller retries"
  eq "$out" "" "  ... names no gate"
  eq "$(creates)" 0 "  ... files no gate on the session bead"
  eq "$(cat "$STUB_PF_LOG")" "" "  ... files no finding"
  hasnt "$(calls)" "[dep] [list]" "  ... never runs the helper"
  has "$(cat "$TMP/err")" "'lx-abc12' did not read" "  ... and says on stderr that the subject did not read"
}
unread_case "a read that fails" STUB_SHOW_FAIL=1
unread_case "a read that exits 1 after the session's row" STUB_SHOW_RC=1
unread_case "a payload cut short" 'STUB_SHOW_RAW=[{"id":"lx-abc12","status":"open","issue_type":"sess'
unread_case "an error object" 'STUB_SHOW_RAW={"error":"no issue found matching lx-abc12"}'
unread_case "a row for a longer id" 'STUB_SHOW_RAW=[{"id":"lx-abc123","status":"open","issue_type":"session"}]'
unread_case "a row with no type" 'STUB_SHOW_RAW=[{"id":"lx-abc12","status":"open"}]'
reset "$(task tk-w)"; : > "$STUB_PF_LOG"
out=$("$HSUT/escalate.sh" --subject tk-gone --key k --message m 2>/dev/null); rc=$?
eq "$rc" 1 "a subject its store does not hold fails the call the same way"
eq "$out$(creates)" "0" "  ... with no gate filed or named"
eq "$(cat "$STUB_PF_LOG")" "" "  ... and no finding"
hasnt "$(calls)" "[dep] [list]" "  ... before the helper runs"

echo "# a subject the old name cannot prove is no bead goes to the helper"
for bsrc in 0 3; do
  reset "$(task tk-w)"; : > "$STUB_PF_LOG"
  out=$(STUB_BS_RC=$bsrc "$HSUT/escalate.sh" --subject tk-w --key k --message m 2>/dev/null); rc=$?
  eq "$rc" 0 "bead-store.sh exit $bsrc on a work bead: the helper files"
  eq "$out" "gate-1" "  ... its gate on the bead"
  eq "$(cat "$STUB_PF_LOG")" "" "  ... and no finding is filed"
done

echo "# the old name asks nothing about the subject of a retract or of a malformed call"
reset "$(task tk-w)"; : > "$STUB_PF_LOG"; : > "$STUB_BS_LOG"
STUB_BS_RC=1 "$HSUT/escalate.sh" --retract --subject refinery --key k --message m >/dev/null 2>&1
eq "$?" 1 "a retract on a subject that names no bead goes to the helper, which cannot read it"
STUB_BS_RC=1 "$HSUT/escalate.sh" --subject "{{convoy_id}}" --key k --message m >/dev/null 2>&1
eq "$?" 2 "a subject outside the id charset goes to the helper, which refuses it as usage"
STUB_BS_RC=1 "$HSUT/escalate.sh" --subject refinery --key k >/dev/null 2>&1
eq "$?" 2 "a filing with no message goes to the helper, which refuses it as usage"
eq "$(cat "$STUB_BS_LOG")" "" "  ... and bead-store.sh is asked about none of them"
eq "$(cat "$STUB_PF_LOG")" "" "  ... and no finding is filed"

echo "# the deacon's filed gates reach its incident ledger"
# The helper calls the ledger by sibling path, so it runs from a private copy
# with a recording gc-deacon-ledger.sh beside it.
LSUT="$TMP/ledger-sut"; mkdir -p "$LSUT"
cp "$SUT" "$HERE/bd-lib.sh" "$LSUT/"
cat > "$LSUT/gc-deacon-ledger.sh" <<'LSTUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LEDGER_LOG:?}"
[ -n "${STUB_LEDGER_FAIL:-}" ] && exit 1
exit 0
LSTUB
chmod +x "$LSUT/gc-deacon-ledger.sh" "$LSUT/human-gate.sh"
export STUB_LEDGER_LOG="$TMP/ledger.log"
ledger() { cat "$STUB_LEDGER_LOG" 2>/dev/null; }
reset "$(task tk-a)"; : > "$STUB_LEDGER_LOG"
GC_AGENT=gc-toolkit.deacon "$LSUT/human-gate.sh" --subject tk-a --key dolt-backup-loomington \
  --message "manifest is 30h old" >/dev/null 2>&1; rc=$?
eq "$rc" 0 "filing exits 0 with the ledger wired in"
eq "$(ledger | grep -c .)" "1" "a filed gate appends exactly one ledger entry"
has "$(ledger)" "dolt-backup-loomington: manifest is 30h old" "carrying the key and the title"
has "$(ledger)" "bead:gate-1" "and pointing at the gate it filed"
GC_AGENT=gc-toolkit.deacon "$LSUT/human-gate.sh" --subject tk-a --key dolt-backup-loomington --message m >/dev/null 2>&1
eq "$(ledger | grep -c .)" "1" "a dedup writes nothing more"
reset "$(task tk-a)"; : > "$STUB_LEDGER_LOG"
GC_AGENT=gc-toolkit/gc-toolkit.polecat "$LSUT/human-gate.sh" --subject tk-a --key k --message m >/dev/null 2>&1
eq "$(ledger | grep -c .)" "0" "a polecat's gate writes nothing to the deacon's ledger"
reset "$(task tk-a)"; : > "$STUB_LEDGER_LOG"
STUB_LEDGER_FAIL=1 GC_AGENT=deacon "$LSUT/human-gate.sh" --subject tk-a --key k --message m >/dev/null 2>&1; rc=$?
eq "$rc" 0 "a ledger failure never changes the exit: the gate is filed either way"

echo
echo "human-gate.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
