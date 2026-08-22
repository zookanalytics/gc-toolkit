#!/usr/bin/env bash
# Hermetic test for backfill-operator-origin.sh (tk-2cyxo). Stubs `gc` on PATH. No
# live city, Dolt, or network.
#
# The script carries the operator-origin marker from PROSE (the sentence
# gc-visit-open.sh appends to a subject's body) to a metadata key the sweep can
# select on. Every case here is about the same risk: the consumer of that key files
# a visit and spawns a conversation, so a bead stamped by mistake costs a session.
#
#   (MATCH)   a bead carrying the intake line verbatim is stamped, and the write is
#             READ BACK before it is reported as done
#   (QUOTE)   a bead that QUOTES the line while specifying it — indented, with the
#             script's own $PROG variable rather than a name — is refused. Three of
#             the thirteen live `--desc-contains` hits are this shape, including the
#             bead that commissioned this script
#   (NEARMISS) a different sentence that merely STARTS the same way ("Operator-origin
#             intake tk-yps55; sitting held by …") is refused
#   (BYHAND)  a variant an agent typed by hand ("Operator-origin intake, 2026-08-22
#             17:39. Recovered from …") is refused. It is genuinely operator-origin
#             and stamping it is one command; what must not happen is a pattern for a
#             script's output quietly deciding it matches
#   (HAVE)    a bead already carrying gc.origin is left exactly as it is, whatever
#             the value — this establishes an origin, it never overrules one
#   (CLOSED)  a CLOSED bead carrying the line is not touched: a stamp bumps
#             updated_at, and detect-stalled-workflows.sh dates a workflow by the max
#             updated_at over its members INCLUDING closed ones, so backfilling one
#             reads as movement and silences a real stall for a window
#   (VERIFY)  a write that exits 0 and persists NOTHING is reported as failed, not as
#             stamped — the failure a migration must never report as done
#   (WRITEFAIL) a refused write is reported and exits non-zero
#   (DRY)     --dry-run selects the same beads and writes nothing
#   (AGAIN)   a second run over the already-stamped store writes nothing more
#   (LISTFAIL) an unreadable listing stamps nothing and exits non-zero
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/backfill-operator-origin.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q -- "$2" "$1" && ok "$3" || bad "$3 (not found: $2)"; }
hasnt() { grep -q -- "$2" "$1" && bad "$3 (unexpectedly found: $2)" || ok "$3"; }

[ -f "$SCRIPT" ] && ok "backfill-operator-origin.sh present" || { bad "missing at $SCRIPT"; exit 1; }
mkdir -p "$TMP/bin"

# --- fixture ------------------------------------------------------------------
# Descriptions are the whole subject of this script, so they are written as real
# multi-line bodies. Each is a shape observed live in this rig on 2026-08-22.
jq -n '
[
 {id:"b-match", status:"open", metadata:{},
  description:("the operator typed this\n\n---\n" +
    "Operator-origin intake, filed by `gc-visit-open` on 2026-08-22T03:42:21Z.\n" +
    "The text above is the whole of what was said at the keystroke.")},

 {id:"b-quote", status:"open", metadata:{},
  description:("## The defect\n\ngc-visit-open.sh writes it as prose:\n\n" +
    "    Operator-origin intake, filed by $PROG on <ts>\n\n" +
    "Discriminating on a description regex is fragile.")},

 {id:"b-nearmiss", status:"open", metadata:{},
  description:"Operator-origin intake tk-yps55; sitting held by converse on visit tk-lrylu."},

 {id:"b-byhand", status:"open", metadata:{},
  description:"Operator-origin intake, 2026-08-22 17:39. Recovered from a preserved visit."},

 {id:"b-have", status:"open", metadata:{"gc.origin":"proactive"},
  description:("a topic\n\n---\n" +
    "Operator-origin intake, filed by `gc-visit-open` on 2026-08-21T09:00:00Z.")},

 {id:"b-closed", status:"closed", metadata:{},
  description:("an old topic\n\n---\n" +
    "Operator-origin intake, filed by `gc-visit-open` on 2026-08-20T20:56:35Z.")},

 {id:"b-other", status:"open", metadata:{}, description:"nothing to do with intake at all"}
]' > "$TMP/beads.json"

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "gc $*" >> "$FAKE_CALLS"
[ "${1:-}" = "bd" ] || { echo '[]'; exit 0; }
shift
[ "${1:-}" = "--rig" ] && shift 2
sub="${1:-}"; shift || true
case "$sub" in
  list)
    if [ "${FAKE_LIST_BROKEN:-0}" = "1" ]; then echo 'not json'; exit 0; fi
    statuses=""; contains=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*)      statuses="${1#--status=}" ;;
        --desc-contains) contains="${2:-}"; shift ;;
      esac
      shift
    done
    # Both filters are real: --desc-contains NARROWS (case-insensitive substring,
    # as bd does) and --status decides which statuses are in scope at all. A stub
    # that ignored the status filter would let the closed-bead case pass against a
    # script that stamps closed beads.
    jq -c --arg s "$statuses" --arg c "$contains" '
      ($s | split(",")) as $w
      | [ .[] | select(.status as $st | $w | index($st))
              | select($c == "" or ((.description // "") | ascii_downcase | contains($c | ascii_downcase))) ]' \
      "$FAKE_STORE"
    exit 0 ;;
  show)
    jq -c --arg i "${1:-}" '[ .[] | select(.id == $i) ]' "$FAKE_STORE"; exit 0 ;;
  update)
    printf 'update %s\n' "$*" >> "$FAKE_UPDATES"
    [ -n "${FAKE_UPDATE_FAIL:-}" ] && exit 1
    id="${1:-}"; shift || true
    # FAKE_LOSES_WRITE=1 is the write that exits 0 and stores nothing — the half a
    # `|| true` cannot see, and the only reason the script reads its own writes back.
    [ "${FAKE_LOSES_WRITE:-0}" = "1" ] && exit 0
    pairs=""
    while [ $# -gt 0 ]; do
      if [ "${1:-}" = "--set-metadata" ]; then pairs="${pairs}${2:-}
"; shift; fi
      shift
    done
    printf '%s' "$pairs" | jq -c -R -s --arg id "$id" --slurpfile store "$FAKE_STORE" '
      (split("\n") | map(select(length > 0))
       | map((index("=")) as $i | if $i == null then {key: ., value: ""} else {key: .[0:$i], value: .[$i+1:]} end)
       | from_entries) as $new
      | ($store[0] // [])
      | map(if .id == $id then (.metadata = ((.metadata // {}) + $new)) else . end)' \
      > "$FAKE_STORE.tmp" && mv "$FAKE_STORE.tmp" "$FAKE_STORE"
    exit 0 ;;
esac
echo '[]'
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_STORE="$TMP/store.json"

run() { # [args...]
  : > "$TMP/updates"; : > "$TMP/calls"
  cp "$TMP/beads.json" "$FAKE_STORE"
  export FAKE_UPDATES="$TMP/updates" FAKE_CALLS="$TMP/calls"
  set +e
  "$SCRIPT" "$@" > "$TMP/out" 2> "$TMP/err"
  RC=$?
  set -e
}

# --- main pass ----------------------------------------------------------------
run
eq "$RC" "0" "the pass exits 0"
has "$TMP/updates" "update b-match --set-metadata gc.origin=operator" "(MATCH) the bead carrying the intake line is stamped"
eq "$(jq -r '.[] | select(.id=="b-match") | .metadata["gc.origin"] // ""' "$FAKE_STORE")" "operator" \
  "(MATCH) and the key is actually persisted"

hasnt "$TMP/updates" "b-quote"    "(QUOTE) a bead that quotes the line while specifying it is refused"
hasnt "$TMP/updates" "b-nearmiss" "(NEARMISS) a different sentence that starts the same way is refused"
hasnt "$TMP/updates" "b-byhand"   "(BYHAND) a hand-typed variant is refused — a pattern for a script's output must not claim it"
has "$TMP/out" "matched the substring but not the intake line" "(QUOTE) and the refusals are reported rather than silent"
has "$TMP/out" "3 matched the substring but not the intake line" "(QUOTE) all three near-miss shapes, counted"

hasnt "$TMP/updates" "b-have" "(HAVE) a bead that already carries an origin is never overruled"
eq "$(jq -r '.[] | select(.id=="b-have") | .metadata["gc.origin"]' "$FAKE_STORE")" "proactive" \
  "(HAVE) and its existing value survives untouched"
has "$TMP/out" "1 already had an origin" "(HAVE) counted, so the census adds up"

hasnt "$TMP/updates" "b-closed" \
  "(CLOSED) a closed bead is out of scope — a stamp bumps updated_at, which dates a workflow as having just moved"
hasnt "$TMP/updates" "b-other" "(SCOPE) a bead with no intake line at all is never read for one"

# --- (AGAIN) idempotent -------------------------------------------------------
# The store from the run above is kept: every candidate already carries the key.
export FAKE_UPDATES="$TMP/updates2"; : > "$FAKE_UPDATES"
"$SCRIPT" > "$TMP/out2" 2>&1
eq "$(wc -l < "$TMP/updates2")" "0" "(AGAIN) a second run over a stamped store writes nothing"
has "$TMP/out2" "0 stamped" "(AGAIN) and reports an empty pass"
# The near-miss beads are re-read on every run and refused again: there is nowhere to
# record "this one is not operator-origin" that would not itself be a write made on a
# guess. Re-reading three descriptions is the cheaper half of that trade.
has "$TMP/out2" "3 matched the substring but not the intake line" \
  "(AGAIN) the beads it refuses stay refused rather than accumulating a marker of their own"

# --- (VERIFY) a write that exits 0 and persists nothing ------------------------
export FAKE_LOSES_WRITE=1
run
unset FAKE_LOSES_WRITE
has "$TMP/err" "read back as" "(VERIFY) the write is read back, and the loss is reported"
hasnt "$TMP/out" "stamped gc.origin=operator on b-match" "(VERIFY) and it is NOT reported as stamped"
eq "$RC" "1" "(VERIFY) the run exits non-zero"

# --- (WRITEFAIL) a refused write ----------------------------------------------
export FAKE_UPDATE_FAIL=1
run
unset FAKE_UPDATE_FAIL
has "$TMP/err" "the stamp did not stick" "(WRITEFAIL) a refused write is reported"
eq "$RC" "1" "(WRITEFAIL) and the run exits non-zero"

# --- (DRY) --------------------------------------------------------------------
run --dry-run
has "$TMP/out" "would stamp gc.origin=operator on b-match" "(DRY) the same bead is selected"
eq "$(wc -l < "$TMP/updates")" "0" "(DRY) and nothing is written"
eq "$RC" "0" "(DRY) exits 0"

# --- (LISTFAIL) ---------------------------------------------------------------
export FAKE_LIST_BROKEN=1
run
unset FAKE_LIST_BROKEN
eq "$RC" "1" "(LISTFAIL) an unreadable listing exits non-zero"
eq "$(wc -l < "$TMP/updates")" "0" "(LISTFAIL) and stamps nothing"
has "$TMP/err" "did not return a readable array" "(LISTFAIL) and says why"

echo
echo "backfill-operator-origin: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
