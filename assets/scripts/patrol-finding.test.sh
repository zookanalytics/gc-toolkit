#!/usr/bin/env bash
# Hermetic test for assets/scripts/patrol-finding.sh — one durable bead per
# distinct patrol finding, and a recurrence that lands on it instead of filing
# another. Stubbed gc and gc-proactive.sh; no live city, Dolt, or network.
#
# The load-bearing case is RECURRENCE. escalate.sh's visit dedup held only
# while its visit was open, and a converse sitting closed each visit before the
# next patrol sweep ran, so one situation filed 14 visits in a day under an
# identical key. The bead this files stays open across the recurrence, so the
# same 14 ticks have to come back as one bead.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/patrol-finding.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }
# Single-line needles only: grep -F reads an embedded newline as alternation,
# so a multi-line needle passes on EITHER line. Count with grep -c instead.

BIN="$TMP/bin"; mkdir -p "$BIN"

# ── gc stub ──────────────────────────────────────────────────────────
# A JSON bead store with the create/list/show/update/dep surface the script
# uses. --metadata rides the create, exactly as bd merges it, because the
# script's duplicate-recovery depends on the key being present on a bead whose
# id the create did not return.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
STORE="${STUB_STORE:?}"; DEPS="${STUB_DEPS:?}"
printf '[%s] %s\n' "${GC_RIG:-<unset>}" "$*" >> "${STUB_GC_LOG:?}"
[ "${1:-}" = "bd" ] || exit 0
shift
case "${1:-}" in
  list)
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "bd: down" >&2; exit 1; }
    shift
    fields=(); statuses=""; limit=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --status) shift; statuses="${1:-}" ;;
        --limit=*) limit="${1#--limit=}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
        --metadata-field=*) fields+=("${1#--metadata-field=}") ;;
      esac
      shift || true
    done
    out=$(jq -c --arg st ",$statuses," \
      '[ .[] | select((.status // "open") as $s | $st | contains("," + $s + ",")) ]' "$STORE")
    for f in ${fields[@]+"${fields[@]}"}; do
      k="${f%%=*}"; v="${f#*=}"
      out=$(printf '%s' "$out" | jq -c --arg k "$k" --arg v "$v" \
        '[ .[] | select(((.metadata // {})[$k] // "") == $v) ]')
    done
    # limit 0 is unbounded, as bd reads it.
    case "$limit" in ''|0|*[!0-9]*) : ;; *) out=$(printf '%s' "$out" | jq -c --argjson n "$limit" '.[0:$n]') ;; esac
    printf '%s\n' "$out" ;;
  show)
    shift; id="${1:-}"
    out=$(jq -c --arg id "$id" '[.[] | select(.id == $id)]' "$STORE")
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      echo '{"error":"no issues found"}'
    else printf '%s\n' "$out"; fi ;;
  create)
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo "bd: refused" >&2; exit 1; }
    shift
    title=""; body=""; typ="task"; metajson="{}"; prio=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="${1:-}" ;;
        -d) shift; body="${1:-}" ;;
        -t) shift; typ="${1:-}" ;;
        --metadata) shift; metajson="${1:-\{\}}" ;;
        --priority) shift; prio="${1:-}" ;;
      esac
      shift || true
    done
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    tmp=$(mktemp)
    jq -c --arg id "fnd-$n" --arg t "$title" --arg d "$body" --arg ty "$typ" \
          --arg p "$prio" --argjson m "$metajson" \
      '. + [{"id":$id,"status":"open","assignee":"","title":$t,"description":$d,
             "issue_type":$ty,"priority":$p,"metadata":$m,"notes":""}]' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    # STUB_CREATE_NO_ID: bd files the bead but answers with an empty id — the
    # shape that makes a blind retry file the duplicate.
    if [ -n "${STUB_CREATE_NO_ID:-}" ]; then printf '{"id":""}\n'; else printf '{"id":"fnd-%s"}\n' "$n"; fi ;;
  update)
    shift; id="${1:-}"; shift
    [ -n "${STUB_UPD_FAIL:-}" ] && { echo "bd: update refused" >&2; exit 1; }
    tmp=$(mktemp); cp "$STORE" "$tmp"
    drops="${STUB_DROP_KEYS:-}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          case ",$drops," in *",$k,"*) ;; *)
            jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
              'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
          esac ;;
        --append-notes) shift; note="${1:-}"
          jq -c --arg id "$id" --arg n "$note" \
            'map(if .id == $id then .notes = ((.notes // "") + (if (.notes // "") == "" then "" else "\n" end) + $n) else . end)' \
            "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
      shift || true
    done
    mv "$tmp" "$STORE"; echo "updated $id" ;;
  close)
    shift; id="${1:-}"
    tmp=$(mktemp)
    jq -c --arg id "$id" 'map(if .id == $id then .status = "closed" else . end)' "$STORE" > "$tmp" && mv "$tmp" "$STORE" ;;
  dep)
    shift
    if [ "${1:-}" = "add" ]; then
      a="${2:-}"; b="${3:-}"; ty=""
      shift 3 || true
      while [ $# -gt 0 ]; do
        case "$1" in --type=*) ty="${1#--type=}" ;; --type) shift; ty="${1:-}" ;; esac
        shift || true
      done
      printf '%s|%s|%s\n' "$a" "$ty" "$b" >> "$DEPS"
    fi ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN/gc"

# ── gc-proactive.sh stub ─────────────────────────────────────────────
# deliverable answers per STUB_DELIVERABLE_RC; sling logs and answers per
# STUB_SLING_RC. Both land in their own log so a run that never reached the
# reaction is distinguishable from one whose reaction failed.
cat > "$BIN/gc-proactive.sh" <<'PRO'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_PROACTIVE_LOG:?}"
case "${1:-}" in
  deliverable) exit "${STUB_DELIVERABLE_RC:-0}" ;;
  sling) [ "${STUB_SLING_RC:-0}" = "0" ] || { echo "sling failed" >&2; exit "${STUB_SLING_RC}"; }; exit 0 ;;
esac
exit 0
PRO
chmod +x "$BIN/gc-proactive.sh"

export PATH="$BIN:$PATH"
export GC_PROACTIVE_TOOL="$BIN/gc-proactive.sh"
export STUB_STORE="$TMP/beads.json" STUB_DEPS="$TMP/deps.txt"
export STUB_GC_LOG="$TMP/gc.log" STUB_PROACTIVE_LOG="$TMP/pro.log"
export STUB_SEQ="$TMP/seq"

reset() {
  echo '[]' > "$STUB_STORE"; : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_PROACTIVE_LOG"
  printf '0' > "$STUB_SEQ"
  export STUB_CREATE_FAIL="" STUB_UPD_FAIL="" STUB_LIST_FAIL="" STUB_DROP_KEYS=""
  export STUB_CREATE_NO_ID="" STUB_DELIVERABLE_RC=0 STUB_SLING_RC=0
  export GC_RIG="gc-toolkit"
}

beads()  { jq 'length' "$STUB_STORE"; }
meta()   { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id==$id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
notes()  { jq -r --arg id "$1" '(.[] | select(.id==$id) | .notes) // ""' "$STUB_STORE"; }
body()   { jq -r --arg id "$1" '(.[] | select(.id==$id) | .description) // ""' "$STUB_STORE"; }
title()  { jq -r --arg id "$1" '(.[] | select(.id==$id) | .title) // ""' "$STUB_STORE"; }
btype()  { jq -r --arg id "$1" '(.[] | select(.id==$id) | .issue_type) // ""' "$STUB_STORE"; }

echo "# patrol-finding.sh"

# ── 1. the first filing ──────────────────────────────────────────────
reset
OUT=$("$SUT" --key doctor-sweep-failed --scope deacon-findings \
        --title "doctor sweep failed" --message "state=failed elapsed=612 check=cadence" 2>&1)
RC=$?
eq "$RC" "0" "(first) exit 0"
eq "$(beads)" "1" "(first) exactly one bead filed"
eq "$(meta fnd-1 'finding.key')" "doctor-sweep-failed" "(first) finding.key rode the create"
eq "$(meta fnd-1 'finding.scope')" "deacon-findings" "(first) finding.scope recorded"
eq "$(meta fnd-1 'finding.occurrences')" "1" "(first) occurrences starts at 1"
eq "$(meta fnd-1 'gc.proactive')" "1" "(first) gc.proactive=1 is the standing scan opt-in"
eq "$(btype fnd-1)" "bug" "(first) default type is bug"
has "$(body fnd-1)" "state=failed elapsed=612" "(first) the finding text is the bead body, verbatim"
has "$OUT" "filed fnd-1" "(first) reports the bead it filed"
eq "$(meta fnd-1 'finding.first_seen')" "$(meta fnd-1 'finding.last_seen')" "(first) first_seen == last_seen"

# It reaches the reaction, and only after the bead verified.
has "$(cat "$STUB_PROACTIVE_LOG")" "deliverable" "(first) asks whether the pool can pick a reaction up"
has "$(cat "$STUB_PROACTIVE_LOG")" "sling fnd-1" "(first) slings the first reaction at the bead"
hasnt "$(cat "$STUB_GC_LOG")" "visit:" "(first) no visit is filed on this path"

# ── 2. the same finding, again — the case escalate.sh could not hold ─
OUT=$("$SUT" --key doctor-sweep-failed --scope deacon-findings \
        --title "doctor sweep failed" --message "state=failed elapsed=612 check=cadence" 2>&1)
eq "$(beads)" "1" "(recur/same) still exactly one bead — no duplicate"
eq "$(meta fnd-1 'finding.occurrences')" "2" "(recur/same) occurrence counted"
eq "$(notes fnd-1)" "" "(recur/same) unchanged text appends no note"
has "$OUT" "already tracks" "(recur/same) says the finding is already tracked"
has "$OUT" "text unchanged" "(recur/same) names why nothing was appended"
eq "$(grep -c 'sling fnd-1' "$STUB_PROACTIVE_LOG")" "1" "(recur/same) does not re-sling a reaction it already slung"

# Twelve more ticks, as the measured day had.
for _ in $(seq 1 12); do
  "$SUT" --key doctor-sweep-failed --scope deacon-findings \
    --title "doctor sweep failed" --message "state=failed elapsed=612 check=cadence" >/dev/null 2>&1
done
eq "$(beads)" "1" "(recur/x14) fourteen ticks of one situation are one bead"
eq "$(meta fnd-1 'finding.occurrences')" "14" "(recur/x14) all fourteen counted on it"

# ── 3. the same finding, changed text ────────────────────────────────
OUT=$("$SUT" --key doctor-sweep-failed --scope deacon-findings \
        --title "doctor sweep failed" --message "state=exceeded elapsed=1801 check=cadence" 2>&1)
eq "$(beads)" "1" "(recur/changed) still one bead"
eq "$(meta fnd-1 'finding.occurrences')" "15" "(recur/changed) occurrence counted"
has "$(notes fnd-1)" "state=exceeded elapsed=1801" "(recur/changed) the new text is appended as a note"
has "$OUT" "changed text" "(recur/changed) says the text moved"
has "$(cat "$STUB_GC_LOG")" "--append-notes" "(recur/changed) appends, never replaces"
hasnt "$(cat "$STUB_GC_LOG")" " --notes " "(recur/changed) --notes would erase the dispatch body"

# ── 4. a different key is a different finding ────────────────────────
reset
"$SUT" --key doctor-a --title "a" --message "finding a" >/dev/null 2>&1
"$SUT" --key doctor-b --title "b" --message "finding b" >/dev/null 2>&1
eq "$(beads)" "2" "(distinct keys) two situations are two beads"

# ── 5. --about narrows the dedup to one bead ─────────────────────────
reset
"$SUT" --key witness-salvage-refused --about tk-aaa --title "salvage refused" --message "no worktree" >/dev/null 2>&1
"$SUT" --key witness-salvage-refused --about tk-bbb --title "salvage refused" --message "no worktree" >/dev/null 2>&1
eq "$(beads)" "2" "(--about) one key over two beads is two findings"
"$SUT" --key witness-salvage-refused --about tk-aaa --title "salvage refused" --message "no worktree" >/dev/null 2>&1
eq "$(beads)" "2" "(--about) a repeat on the same bead files nothing new"
eq "$(meta fnd-1 'finding.about')" "tk-aaa" "(--about) the subject is stamped"
eq "$(cat "$STUB_DEPS")" "fnd-1|tracks|tk-aaa
fnd-2|tracks|tk-bbb" "(--about) tracks edges, never parent-child"

# An unscoped finding must not adopt an --about-scoped bead: finding.about is
# ABSENT there, which the listing filter alone cannot express.
"$SUT" --key witness-salvage-refused --title "salvage refused" --message "no worktree" >/dev/null 2>&1
eq "$(beads)" "3" "(--about) a finding with no subject is its own situation"
eq "$(meta fnd-3 'finding.about')" "<absent>" "(--about) and carries no subject stamp"

# ── 6. recurring after the bead was closed ───────────────────────────
reset
"$SUT" --key dolt-backup-gascity --title "manifest stale" --message "manifest is 30h old" >/dev/null 2>&1
gc bd close fnd-1 >/dev/null 2>&1
OUT=$("$SUT" --key dolt-backup-gascity --title "manifest stale" --message "manifest is 30h old" 2>&1)
eq "$(beads)" "2" "(after close) a finding that fires again after its fix gets a new bead"
eq "$(meta fnd-2 'finding.recurrence_of')" "fnd-1" "(after close) the new bead names the closed one"
has "$(body fnd-2)" "fired again after fnd-1 was closed" "(after close) the body says the fix did not hold"
has "$OUT" "recurrence of closed fnd-1" "(after close) reported"
# And it does not become a bead per tick: the new bead is open, so the next
# sweep lands on it.
"$SUT" --key dolt-backup-gascity --title "manifest stale" --message "manifest is 30h old" >/dev/null 2>&1
eq "$(beads)" "2" "(after close) the recurrence-after-close files exactly one new bead"
eq "$(meta fnd-2 'finding.occurrences')" "2" "(after close) later ticks land on the new bead"

# ── 7. the pool cannot take a reaction ───────────────────────────────
reset
export STUB_DELIVERABLE_RC=1
OUT=$("$SUT" --key doctor-x --title "x" --message "x fired" 2>&1); RC=$?
eq "$RC" "0" "(pool down) the filing still succeeds"
eq "$(beads)" "1" "(pool down) the bead is filed"
eq "$(meta fnd-1 'gc.proactive')" "1" "(pool down) the scan opt-in is what picks it up later"
hasnt "$(cat "$STUB_PROACTIVE_LOG")" "sling" "(pool down) no sling into a pool that cannot claim it"
has "$OUT" "waits for the next scan sweep" "(pool down) says how the reaction still happens"

reset
export STUB_SLING_RC=1
OUT=$("$SUT" --key doctor-y --title "y" --message "y fired" 2>&1); RC=$?
eq "$RC" "0" "(sling fails) a failed reaction does not lose the finding"
eq "$(beads)" "1" "(sling fails) the bead stands"
has "$OUT" "sling on fnd-1 failed" "(sling fails) reported"

# ── 8. --no-react ────────────────────────────────────────────────────
reset
"$SUT" --key doctor-z --title "z" --message "z fired" --no-react >/dev/null 2>&1
eq "$(beads)" "1" "(--no-react) the bead is filed"
eq "$(cat "$STUB_PROACTIVE_LOG")" "" "(--no-react) nothing is slung"

# ── 9. bd create answers with no id for a bead it did create ─────────
reset
export STUB_CREATE_NO_ID=1
OUT=$("$SUT" --key doctor-noid --title "noid" --message "noid fired" 2>&1); RC=$?
eq "$RC" "0" "(empty id) recovers"
eq "$(beads)" "1" "(empty id) the bead is NOT filed twice"
has "$OUT" "found by finding.key" "(empty id) says how it re-identified the bead"
has "$(cat "$STUB_PROACTIVE_LOG")" "sling fnd-1" "(empty id) the recovered bead still gets its reaction"

# ── 10. the key fails to stamp ───────────────────────────────────────
# An unstamped key is invisible to every later sweep, so this fails loud
# rather than filing a bead that guarantees duplicates.
reset
export STUB_CREATE_NO_ID=1 STUB_LIST_FAIL=1
OUT=$("$SUT" --key doctor-lost --title "lost" --message "lost fired" 2>&1); RC=$?
eq "$RC" "1" "(unfindable) exits non-zero when the bead cannot be identified"
has "$OUT" "re-run this command" "(unfindable) names the repair"

# ── 11. usage ────────────────────────────────────────────────────────
reset
OUT=$("$SUT" --key 'bad key=1' --title t --message m 2>&1); RC=$?
eq "$RC" "2" "(usage) a key with metacharacters is refused"
has "$OUT" "must contain only" "(usage) says which charset"
eq "$(beads)" "0" "(usage) nothing filed"

OUT=$("$SUT" --key ok-key --title t 2>&1); RC=$?
eq "$RC" "2" "(usage) --message is required"
OUT=$("$SUT" --title t --message m 2>&1); RC=$?
eq "$RC" "2" "(usage) --key is required"
OUT=$("$SUT" --key ok-key --message m 2>&1); RC=$?
eq "$RC" "2" "(usage) --title is required"

# ── 12. the rig binds the store and the pool ─────────────────────────
reset
unset GC_RIG
OUT=$("$SUT" --key doctor-rig --title "rig" --message "rig fired" 2>&1)
has "$OUT" "GC_RIG unset" "(rig) an unset rig is named, not silently guessed"
has "$(cat "$STUB_GC_LOG")" "[gc-toolkit] bd create" "(rig) the default rig binds the store the bead lands in"
reset
GC_RIG=other "$SUT" --key doctor-rig2 --title "rig2" --message "rig2 fired" >/dev/null 2>&1
has "$(cat "$STUB_GC_LOG")" "[other] bd create" "(rig) an ambient GC_RIG is honored"
reset
GC_RIG=other "$SUT" --key doctor-rig3 --rig third --title "rig3" --message "rig3 fired" >/dev/null 2>&1
has "$(cat "$STUB_GC_LOG")" "[third] bd create" "(rig) --rig outranks the ambient one"

# ── 13. a long title is cut at a word boundary ───────────────────────
reset
LONG=$(printf 'alpha bravo charlie delta %.0s' $(seq 1 40))
"$SUT" --key doctor-long --title "$LONG" --message "long fired" >/dev/null 2>&1
T=$(title fnd-1)
if [ "${#T}" -le 201 ]; then ok "(title) cut under the cap"; else bad "(title) too long (${#T})"; fi
hasnt "$T" "alph…" "(title) the cut lands on a word boundary, never mid-word"

# ── 14. --dry-run writes nothing ─────────────────────────────────────
reset
OUT=$("$SUT" --key doctor-dry --title "dry" --message "dry fired" --dry-run 2>&1); RC=$?
eq "$RC" "0" "(dry-run) exit 0"
eq "$(beads)" "0" "(dry-run) nothing filed"
eq "$(cat "$STUB_PROACTIVE_LOG")" "" "(dry-run) nothing slung"
has "$OUT" "key=doctor-dry" "(dry-run) prints what it would file"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
