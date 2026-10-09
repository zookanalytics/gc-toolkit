#!/usr/bin/env bash
# tmux-keeper-toggle.test.sh — the `S` picker's keeper pin entry, hermetic.
#
# tmux-keeper-toggle.sh answers one question for the picker: is the
# gascity-keeper pinned? `state` prints up, down or unknown, and `toggle`
# unpins on up, pins on down and refuses on unknown. The answer takes two
# reads. `gc session list --json` resolves the keeper's alias to its session
# bead id, and `gc bd show <id> --json` reports that bead's metadata.pin_awake.
# The suite drives the real script with `gc` and `tmux` stubbed on PATH.
#
# What each case pins:
#
#   (LIVE)    the rows `gc session list --json` prints: lower-case `id` and
#             `alias` under a `.sessions` envelope. A pinned keeper reads up.
#             A pinned session sits ahead of the keeper in the roster, so a
#             lookup that ignores the alias cannot pass for one that finds it.
#   (LEGACY)  older gc builds print a bare array of `ID`/`Alias` rows, and a
#             keeper in one still resolves.
#   (DOWN)    an unpinned keeper, and a roster with no keeper row, read down.
#   (UNKNOWN) a failed read, or an answer the script cannot parse, reads
#             unknown. Down is a claim about the keeper and picks the action
#             the picker offers; unknown shows a neutral label and the toggle
#             refuses.
#   (TOGGLE)  the action follows the state: unpin when up, pin when down,
#             neither when unknown.
#   (CITY)    --city-path reaches every gc call.
#
# Hermetic: stubs `gc` and `tmux`; no city, no Dolt, no tmux server, and no
# session is pinned or unpinned.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/tmux-keeper-toggle.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-tmux-keeper-toggle-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

[ -s "$SCRIPT" ] || { echo "missing $SCRIPT"; exit 1; }
[ -x "$SCRIPT" ] || { echo "$SCRIPT is not executable"; exit 1; }

# A set GC_TMUX_SOCKET puts `-L <socket>` ahead of every tmux call the stub logs.
unset GC_TMUX_SOCKET 2>/dev/null || true

echo "── the script is valid shell ──"
if sh -n "$SCRIPT"; then ok "tmux-keeper-toggle.sh: valid sh"; else bad "tmux-keeper-toggle.sh: valid sh" "sh -n failed"; fi

# --- the stubs ---------------------------------------------------------------
# `gc` serves `session list` from $FIX/sessions.json and `bd show <id>` from
# $FIX/bead_<id>.json, and logs every call. `session pin|unpin` only logs, to
# its own file, which is the record of what a toggle did.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
sub="${1:-}"; shift || true
verb="${1:-}"; shift || true
case "$sub/$verb" in
  session/list)
    [ -n "${STUB_LIST_FAIL:-}" ] && exit 1
    cat "$FIX/sessions.json" ;;
  bd/show)
    [ -n "${STUB_SHOW_FAIL:-}" ] && exit 1
    f="$FIX/bead_${1:-}.json"
    [ -f "$f" ] || { echo "gc bd: no such bead ${1:-}" >&2; exit 1; }
    cat "$f" ;;
  session/pin|session/unpin)
    printf '%s %s\n' "$verb" "${1:-}" >> "${STUB_PIN_LOG:?}" ;;
  *) echo "gc stub: unsupported '$sub $verb'" >&2; exit 2 ;;
esac
GC
cat > "$TMP/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_TMUX_LOG:?}"
TMUX
chmod +x "$TMP/bin/gc" "$TMP/bin/tmux"

FIX="$TMP/fix"; mkdir -p "$FIX"
export FIX PATH="$TMP/bin:$PATH"
export STUB_GC_LOG="$TMP/gc.log" STUB_PIN_LOG="$TMP/pin.log" STUB_TMUX_LOG="$TMP/tmux.log"

KEEPER="gascity/gascity-keeper.keeper"

roster() { printf '%s\n' "$1" > "$FIX/sessions.json"; }      # roster <json>
bead() { printf '[{"id":"%s","metadata":%s}]\n' "$1" "$2" > "$FIX/bead_$1.json"; } # bead <id> <metadata-json>

# The live row shape: a pinned mechanik, a pool worker with no alias, then the
# keeper.
LIVE_ROSTER='{"schema_version":"1","ok":true,"filters":{},"sessions":[
  {"id":"lx-mech","name":"gc-toolkit.mechanik","alias":"gc-toolkit.mechanik","template":"gc-toolkit.mechanik","state":"active","closed":false},
  {"id":"lx-pool","name":"gc-toolkit__polecat-lx-pool","template":"gc-toolkit/gc-toolkit.polecat","state":"active","closed":false},
  {"id":"lx-keeper","name":"gascity/gascity-keeper.keeper","alias":"gascity/gascity-keeper.keeper","template":"gascity/gascity-keeper.keeper","state":"asleep","closed":false}
],"summary":{"total":3}}'
bead lx-mech '{"pin_awake":"true"}'

# OUT is the script's stdout; the three logs hold this run's calls only.
OUT=""
run() { # run <script args...>
  : > "$STUB_GC_LOG"; : > "$STUB_PIN_LOG"; : > "$STUB_TMUX_LOG"
  OUT="$("$SCRIPT" "$@" 2>/dev/null)"
}

echo "── LIVE: lower-case rows under .sessions ──"
roster "$LIVE_ROSTER"
bead lx-keeper '{"pin_awake":"true"}'
run state
eq "$OUT" "up" "LIVE: a pinned keeper reads up"
has "$(cat "$STUB_GC_LOG")" "bd show lx-keeper" "LIVE: ...read from the keeper's own session bead"

bead lx-keeper '{"session_origin":"named"}'
run state
eq "$OUT" "down" "LIVE: an unpinned keeper reads down, though another session is pinned"

bead lx-keeper '{"pin_awake":true}'
run state
eq "$OUT" "up" "LIVE: a boolean pin reads up"

echo "── LEGACY: a bare array of ID/Alias rows ──"
roster '[{"ID":"lx-mech","Alias":"gc-toolkit.mechanik"},{"ID":"lx-old","Alias":"gascity/gascity-keeper.keeper"}]'
bead lx-old '{"pin_awake":"true"}'
run state
eq "$OUT" "up" "LEGACY: a pinned keeper in the bare-array shape reads up"

echo "── DOWN: no keeper row ──"
roster '{"schema_version":"1","sessions":[{"id":"lx-mech","alias":"gc-toolkit.mechanik"}]}'
run state
eq "$OUT" "down" "DOWN: a roster with no keeper row reads down"
hasnt "$(cat "$STUB_GC_LOG")" "bd show" "DOWN: ...without reading any session bead"

roster '{"schema_version":"1","sessions":[]}'
run state
eq "$OUT" "down" "DOWN: an empty roster reads down"

echo "── UNKNOWN: an answer the script cannot read ──"
roster "$LIVE_ROSTER"
bead lx-keeper '{"pin_awake":"true"}'
export STUB_LIST_FAIL=1; run state; unset STUB_LIST_FAIL
eq "$OUT" "unknown" "UNKNOWN: a failed session list reads unknown"
export STUB_SHOW_FAIL=1; run state; unset STUB_SHOW_FAIL
eq "$OUT" "unknown" "UNKNOWN: a failed bead read reads unknown"

roster '{"schema_version":"1","ok":true}'
run state
eq "$OUT" "unknown" "UNKNOWN: a roster with no row array reads unknown, not down"

roster '{"schema_version":"1","sessions":[{"alias":"gascity/gascity-keeper.keeper","session_name":"lx-keeper"}]}'
run state
eq "$OUT" "unknown" "UNKNOWN: a keeper row with no id reads unknown, not down"

roster 'not json'
run state
eq "$OUT" "unknown" "UNKNOWN: a roster that is not JSON reads unknown"

: > "$FIX/sessions.json"
run state
eq "$OUT" "unknown" "UNKNOWN: an empty answer from a successful list reads unknown, not down"

echo "── TOGGLE: the action follows the state ──"
roster "$LIVE_ROSTER"
bead lx-keeper '{"pin_awake":"true"}'
run toggle
eq "$(cat "$STUB_PIN_LOG")" "unpin $KEEPER" "TOGGLE: a pinned keeper is unpinned"
has "$(cat "$STUB_TMUX_LOG")" "keeper unpinned" "TOGGLE: ...and the operator is told"

bead lx-keeper '{}'
run toggle
eq "$(cat "$STUB_PIN_LOG")" "pin $KEEPER" "TOGGLE: an unpinned keeper is pinned"
has "$(cat "$STUB_TMUX_LOG")" "keeper pinned" "TOGGLE: ...and the operator is told"

export STUB_LIST_FAIL=1; run toggle; unset STUB_LIST_FAIL
eq "$(cat "$STUB_PIN_LOG")" "" "TOGGLE: an unknown state pins and unpins nothing"
has "$(cat "$STUB_TMUX_LOG")" "not toggling" "TOGGLE: ...and says so"

echo "── CITY: --city-path reaches every gc call ──"
roster "$LIVE_ROSTER"
bead lx-keeper '{"pin_awake":"true"}'
run --city-path "$TMP/city" toggle
GC_CALLS="$(cat "$STUB_GC_LOG")"
has "$GC_CALLS" "session list --json --city $TMP/city" "CITY: the session list is the city's"
has "$GC_CALLS" "bd show lx-keeper --json --city $TMP/city" "CITY: the bead read is the city's"
has "$GC_CALLS" "session unpin $KEEPER --city $TMP/city" "CITY: the unpin is the city's"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
