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
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-patrol-finding-test.XXXXXX")"
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
    # STUB_LIST_FAIL_FIELD: only a listing that filters on this metadata field
    # fails, so one lookup can be broken while the others still read.
    for f in ${fields[@]+"${fields[@]}"}; do
      [ -n "${STUB_LIST_FAIL_FIELD:-}" ] && [ "${f%%=*}" = "$STUB_LIST_FAIL_FIELD" ] \
        && { echo "bd: down" >&2; exit 1; }
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
    # bd list puts each bead's outgoing edges on its row as
    # {issue_id, depends_on_id, type}, and leaves the key off a bead with none.
    out=$(printf '%s' "$out" | jq -c --rawfile edges "$DEPS" '
      [ $edges | split("\n")[] | select(. != "") | split("|")
        | {issue_id: .[0], type: .[1], depends_on_id: .[2]} ] as $e
      | map(.id as $id | [ $e[] | select(.issue_id == $id) ] as $mine
            | if ($mine | length) > 0 then . + {dependencies: $mine} else . end)')
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
        --status=*|--status)
          if [ "$1" = "--status" ]; then shift; st="${1:-}"; else st="${1#--status=}"; fi
          jq -c --arg id "$id" --arg s "$st" 'map(if .id == $id then .status = $s else . end)' \
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
  export STUB_CREATE_FAIL="" STUB_UPD_FAIL="" STUB_LIST_FAIL="" STUB_LIST_FAIL_FIELD="" STUB_DROP_KEYS=""
  export STUB_CREATE_NO_ID="" STUB_DELIVERABLE_RC=0 STUB_SLING_RC=0
  export GC_RIG="gc-toolkit"
}

beads()  { jq 'length' "$STUB_STORE"; }
meta()   { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id==$id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
notes()  { jq -r --arg id "$1" '(.[] | select(.id==$id) | .notes) // ""' "$STUB_STORE"; }
body()   { jq -r --arg id "$1" '(.[] | select(.id==$id) | .description) // ""' "$STUB_STORE"; }
title()  { jq -r --arg id "$1" '(.[] | select(.id==$id) | .title) // ""' "$STUB_STORE"; }
btype()  { jq -r --arg id "$1" '(.[] | select(.id==$id) | .issue_type) // ""' "$STUB_STORE"; }
findings() { jq --arg k "$1" '[.[] | select(.metadata["finding.key"] == $k)] | length' "$STUB_STORE"; }
# put_bead <id> <status> — a bead that is not a finding: the fix or the visit a
# held finding waits on, or the subject one is about.
put_bead() {
  local tmp
  tmp=$(mktemp "$TMP/store.XXXXXX")
  jq -c --arg id "$1" --arg s "$2" '. + [{"id":$id,"status":$s,"title":$id,"metadata":{}}]' \
    "$STUB_STORE" > "$tmp" && mv "$tmp" "$STUB_STORE"
}
# hold <finding> <status> [<blocker>...] — park a finding bead at <status>,
# waiting on each blocker through a `blocks` edge.
hold() {
  local f="$1" st="$2" b
  shift 2
  for b in "$@"; do gc bd dep add "$f" "$b" --type=blocks >/dev/null 2>&1; done
  gc bd update "$f" --status="$st" >/dev/null 2>&1
}

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
# A per-bead key (one finding per subject) passes --distinct on every call, so a
# second subject under the key is its own finding, and --distinct leaves the
# exact match in force: a repeat on the same subject still lands on its bead.
reset
"$SUT" --key witness-salvage-refused --about tk-aaa --distinct --title "salvage refused" --message "no worktree" >/dev/null 2>&1
"$SUT" --key witness-salvage-refused --about tk-bbb --distinct --title "salvage refused" --message "no worktree" >/dev/null 2>&1
eq "$(beads)" "2" "(--about) one per-bead key over two beads is two findings"
"$SUT" --key witness-salvage-refused --about tk-aaa --distinct --title "salvage refused" --message "no worktree" >/dev/null 2>&1
eq "$(beads)" "2" "(--about) a repeat on the same bead files nothing new, --distinct or not"
eq "$(meta fnd-1 'finding.occurrences')" "2" "(--about) the repeat is counted on the first subject's bead"
eq "$(meta fnd-1 'finding.about')" "tk-aaa" "(--about) the subject is stamped"
eq "$(cat "$STUB_DEPS")" "fnd-1|tracks|tk-aaa
fnd-2|tracks|tk-bbb" "(--about) tracks edges, never parent-child"

# A finding with no --about must not adopt an --about-scoped bead: finding.about
# is ABSENT there, which the listing filter alone cannot express.
"$SUT" --key witness-salvage-refused --distinct --title "salvage refused" --message "no worktree" >/dev/null 2>&1
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

# ── 10. the dedup lookup itself cannot be read — fail CLOSED ──────────
# bd list exits non-zero (the store is momentarily unreadable) while bd create
# would still succeed. The dedup probe cannot then tell "no existing finding"
# from "could not look"; reading the empty result as "none" files a fresh bead
# for a key that may already be open — a duplicate produced during the very
# store-read failure the dedup exists to survive. It must refuse before any
# create runs. Regression: the fail-OPEN probe filed fnd-1 and exited 0.
reset
export STUB_LIST_FAIL=1
OUT=$("$SUT" --key doctor-unreadable --scope deacon-findings \
        --title "doctor sweep failed" --message "state=failed elapsed=612" 2>&1); RC=$?
eq "$RC" "1" "(list fails) fails closed — not exit 0 — on an unreadable dedup probe"
eq "$(beads)" "0" "(list fails) files NOTHING; no duplicate while the store is unreadable"
hasnt "$OUT" "filed fnd" "(list fails) reports no filed bead"
has "$OUT" "dedup lookup failed" "(list fails) says the lookup, not the finding, failed"
has "$OUT" "refusing to file" "(list fails) says it refused"
eq "$(cat "$STUB_PROACTIVE_LOG")" "" "(list fails) no reaction slung for a finding it would not file"

# The refusal is decided at the dedup probe, before create — so it stands
# whatever create would have done (the old create-returns-no-id case, which the
# fail-open probe let reach create, now stops one step earlier).
reset
export STUB_LIST_FAIL=1 STUB_CREATE_NO_ID=1
OUT=$("$SUT" --key doctor-lost --title "lost" --message "lost fired" 2>&1); RC=$?
eq "$RC" "1" "(list fails + create no-id) still fails closed at the dedup probe"
eq "$(beads)" "0" "(list fails + create no-id) nothing filed — the guard precedes create"

# The dedup probe reads clean but bd create fails outright: nothing was filed,
# so it says so and names the repair rather than reporting a success.
reset
export STUB_CREATE_FAIL=1
OUT=$("$SUT" --key doctor-createfail --title "cf" --message "cf fired" 2>&1); RC=$?
eq "$RC" "1" "(create fails) a failed create exits non-zero"
eq "$(beads)" "0" "(create fails) nothing filed"
has "$OUT" "re-run this command" "(create fails) names the repair"

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
OUT=$("$SUT" --key doctor-dry --title "dry" --message "dry fired" --distinct --dry-run 2>&1)
has "$OUT" " distinct" "(dry-run) and names --distinct when it is given"
eq "$(beads)" "0" "(dry-run) --distinct still files nothing"

# ── 15. --check derives the doctor key from the check name ───────────
# The doctor JSON names a check `<rig>:<check>`, and dedup is exact-match on the
# key, so the key must not vary with how the `<rig>:` prefix is rendered. --check
# strips the prefix, resolving every rendering of one check to one key.
reset
"$SUT" --check "gc-toolkit:check-step-terminal" --scope deacon-findings \
  --title "doctor gc-toolkit:check-step-terminal: I8 holds" --message "step-terminal I8" >/dev/null 2>&1
eq "$(meta fnd-1 'finding.key')" "doctor-check-step-terminal" "(check) the <rig>: prefix is stripped to one canonical key"

# A bare check name (no `<rig>:` prefix) passes through unchanged.
reset
"$SUT" --check "fork-rate" --title "doctor fork-rate: high" --message "240 forks/s" >/dev/null 2>&1
eq "$(meta fnd-1 'finding.key')" "doctor-fork-rate" "(check) a prefix-less name yields doctor-<name>"

# One check is one bead: the derived key is stable, so a recurrence lands on the
# open bead instead of filing another.
reset
"$SUT" --check "gc-toolkit:check-step-terminal" --title "t" --message "first" >/dev/null 2>&1
"$SUT" --check "gc-toolkit:check-step-terminal" --title "t" --message "first" >/dev/null 2>&1
eq "$(beads)" "1" "(check) one check is one bead across recurrences"
eq "$(meta fnd-1 'finding.occurrences')" "2" "(check) the recurrence counted on it"

# --key and --check name the same slot; giving both is ambiguous and refused.
reset
OUT=$("$SUT" --key doctor-x --check "gc-toolkit:check-x" --title t --message m 2>&1); RC=$?
eq "$RC" "2" "(check) --key and --check together are refused"
has "$OUT" "mutually exclusive" "(check) says why"
eq "$(beads)" "0" "(check) nothing filed on the ambiguous call"

# ── The doctor-<check> namespace is derived, never hand-typed ─────────
# --check derives doctor-<check> with the <rig>: prefix stripped; a hand-typed
# --key in a rendering the derivation never emits (a '.' after "doctor", or the
# rig name embedded) splits one check across beads. patrol-finding.sh refuses
# those renderings and names --check.
reset
OUT=$("$SUT" --key doctor.pool-idle-routed-work --scope deacon-findings --title t --message m 2>&1); RC=$?
eq "$RC" "2" "(doctor-key) a hand-typed dot-form doctor key is refused"
has "$OUT" "--check" "(doctor-key) the refusal names --check"
eq "$(beads)" "0" "(doctor-key) nothing filed on the refused dot-form call"

reset
OUT=$("$SUT" --key doctor-gc-toolkit-check-cadence-live --scope deacon-findings --title t --message m 2>&1); RC=$?
eq "$RC" "2" "(doctor-key) a hand-typed rig-embedded (dash) doctor key is refused"

reset
OUT=$("$SUT" --key doctor-gc-toolkit.check-cadence-live --scope deacon-findings --title t --message m 2>&1); RC=$?
eq "$RC" "2" "(doctor-key) a hand-typed rig-embedded (dot) doctor key is refused"

# The whole-sweep failure names no check, so its key is the one hand-typed
# doctor key the guard lets through.
reset
"$SUT" --key doctor-sweep-failed --scope deacon-findings --title t --message m >/dev/null 2>&1
eq "$(beads)" "1" "(doctor-key) the doctor-sweep-failed sentinel is allowed"

# The canonical path is untouched: --check still derives and files doctor-<check>.
reset
"$SUT" --check "gc-toolkit:pool-idle-routed-work" --scope deacon-findings --title t --message m >/dev/null 2>&1
eq "$(beads)" "1" "(doctor-key) --check still files the canonical bead"
eq "$(meta fnd-1 'finding.key')" "doctor-pool-idle-routed-work" "(doctor-key) --check yields doctor-<check>, prefix stripped"

# A non-doctor key that merely contains the rig name is not in the namespace.
reset
"$SUT" --key dolt-backup-gc-toolkit --scope deacon-findings --title t --message m >/dev/null 2>&1
eq "$(beads)" "1" "(doctor-key) a non-doctor key is unaffected"

# ── 16. a bead held at blocked still tracks its finding ──────────────
# The finding's bead is parked at blocked behind the fix it waits on, and an
# older bead for the same key is closed. A lookup that reads only open and
# in_progress misses the held bead, files a second one, and names the older
# closed bead as the predecessor whose fix "did not hold".
reset
"$SUT" --key doctor-held --title "held" --message "held fired" >/dev/null 2>&1
gc bd close fnd-1 >/dev/null 2>&1
"$SUT" --key doctor-held --title "held" --message "held fired" >/dev/null 2>&1
put_bead fix-1 open
hold fnd-2 blocked fix-1
OUT=$("$SUT" --key doctor-held --title "held" --message "held fired" 2>&1); RC=$?
eq "$RC" "0" "(held/waiting) exit 0"
eq "$(findings doctor-held)" "2" "(held/waiting) no second bead beside the held one"
eq "$(meta fnd-2 'finding.occurrences')" "2" "(held/waiting) the recurrence is counted on the held bead"
has "$OUT" "fnd-2 already tracks" "(held/waiting) says the held bead tracks it"
hasnt "$OUT" "fnd-1" "(held/waiting) the older closed bead is not named"
eq "$(grep -c 'sling' "$STUB_PROACTIVE_LOG")" "2" "(held/waiting) no reaction is slung for a recurrence it absorbed"

OUT=$("$SUT" --key doctor-held --title "held" --message "held fired, wider" 2>&1)
eq "$(findings doctor-held)" "2" "(held/waiting) changed text files nothing new either"
has "$(notes fnd-2)" "held fired, wider" "(held/waiting) the changed text is a note on the held bead"

# The fix it waited on closes and the finding fires again. bd leaves the bead
# at blocked, so nothing will act on it again: the recurrence is news, and its
# predecessor is the held bead.
gc bd close fix-1 >/dev/null 2>&1
OUT=$("$SUT" --key doctor-held --title "held" --message "held fired, wider" 2>&1); RC=$?
eq "$RC" "0" "(held/released) exit 0"
eq "$(findings doctor-held)" "3" "(held/released) the recurrence after the wait ended files one new bead"
eq "$(meta fnd-3 'finding.recurrence_of')" "fnd-2" "(held/released) the new bead names the held bead"
has "$(body fnd-3)" "while fnd-2 was held at blocked" "(held/released) the body names the held bead"
has "$(body fnd-3)" "(fix-1) had closed" "(held/released) and the blocker that closed"
hasnt "$(body fnd-3)" "fnd-1" "(held/released) the older closed bead is not blamed"
has "$OUT" "recurrence of fnd-2" "(held/released) reported"
has "$(cat "$STUB_PROACTIVE_LOG")" "sling fnd-3" "(held/released) the new bead gets its first reaction"
"$SUT" --key doctor-held --title "held" --message "held fired, wider" >/dev/null 2>&1
eq "$(findings doctor-held)" "3" "(held/released) one new bead, not one per tick"
eq "$(meta fnd-3 'finding.occurrences')" "2" "(held/released) later ticks land on the new bead"

# Waiting means ANY blocker still open, not just one of them closed.
reset
"$SUT" --key doctor-two-blockers --title t --message m >/dev/null 2>&1
put_bead fix-a closed
put_bead fix-b open
hold fnd-1 blocked fix-a fix-b
"$SUT" --key doctor-two-blockers --title t --message m >/dev/null 2>&1
eq "$(findings doctor-two-blockers)" "1" "(held/one of two open) still waiting, so no new bead"
eq "$(meta fnd-1 'finding.occurrences')" "2" "(held/one of two open) the recurrence lands on it"

# A blocker no read resolves is not proven closed, so the held bead may still
# be waiting and keeps the recurrence.
reset
"$SUT" --key doctor-dangling --title t --message m >/dev/null 2>&1
hold fnd-1 blocked gone-1
"$SUT" --key doctor-dangling --title t --message m >/dev/null 2>&1
eq "$(findings doctor-dangling)" "1" "(held/unreadable blocker) no new bead"
eq "$(meta fnd-1 'finding.occurrences')" "2" "(held/unreadable blocker) the recurrence lands on it"

# The tracks edge --about adds names the subject. It is not a wait, so an open
# subject does not keep a held bead taking recurrences after its blocker closed.
reset
put_bead tk-subj open
"$SUT" --key witness-held --about tk-subj --title t --message m >/dev/null 2>&1
put_bead fix-1 closed
hold fnd-1 blocked fix-1
"$SUT" --key witness-held --about tk-subj --title t --message m >/dev/null 2>&1
eq "$(findings witness-held)" "2" "(held/tracks edge) an open subject is not a wait"
eq "$(meta fnd-2 'finding.recurrence_of')" "fnd-1" "(held/tracks edge) the recurrence names the held bead"

# A bead held at blocked with no edge waits on nothing, so nothing will release
# it; the recurrence is news and says so.
reset
"$SUT" --key doctor-edgeless --title t --message m >/dev/null 2>&1
hold fnd-1 blocked
OUT=$("$SUT" --key doctor-edgeless --title t --message m 2>&1)
eq "$(findings doctor-edgeless)" "2" "(held/no edge) a new bead is filed"
eq "$(meta fnd-2 'finding.recurrence_of')" "fnd-1" "(held/no edge) naming the held bead"
has "$(body fnd-2)" "with no blocker to" "(held/no edge) the body says it waited on nothing"
hasnt "$(body fnd-2)" "had closed" "(held/no edge) and claims no blocker closed"

# Two held beads for one key: a recurrence goes to the one still waiting, even
# when the one whose wait ended is listed first.
reset
"$SUT" --key doctor-two-held --title t --message m >/dev/null 2>&1
put_bead fix-1 closed
hold fnd-1 blocked fix-1
"$SUT" --key doctor-two-held --title t --message m >/dev/null 2>&1
put_bead fix-2 open
hold fnd-2 blocked fix-2
"$SUT" --key doctor-two-held --title t --message m >/dev/null 2>&1
eq "$(findings doctor-two-held)" "2" "(two held) no third bead while one still waits"
eq "$(meta fnd-2 'finding.occurrences')" "2" "(two held) the recurrence lands on the waiting one"

# ── 17. every other live status keeps its finding ────────────────────
# deferred, hooked and pinned beads are as invisible to an open,in_progress
# lookup as a blocked one. None of them is a wait on a blocker, so each keeps
# the recurrence whatever its edges say.
for st in in_progress deferred hooked pinned; do
  reset
  "$SUT" --key doctor-live --title t --message m >/dev/null 2>&1
  put_bead fix-1 closed
  hold fnd-1 "$st" fix-1
  "$SUT" --key doctor-live --title t --message m >/dev/null 2>&1
  eq "$(findings doctor-live)" "1" "(live/$st) no second bead"
  eq "$(meta fnd-1 'finding.occurrences')" "2" "(live/$st) the recurrence lands on it"
done

# ── 18. one situation re-reported under another key or subject ───────
# A patrol that types its key by hand picks it afresh on every pass, so one
# situation comes back under a new key with the same subject, or under the same
# key with another subject. The exact match cannot see either, and each would
# be a twin with its own first reaction. A new bead that shares either half
# with a live finding in its scope is refused, and those findings are listed.
SIT="21 open witness-refinery-queue visits carry malformed groups"
reset
"$SUT" --scope witness-findings --key stale-malformed-visits --about tk-visit \
  --title "$SIT" --message "21 visits, retract skips them" >/dev/null 2>&1
eq "$(beads)" "1" "(sibling) the first report files its bead"

# The subject half: a new key over the same subject.
OUT=$("$SUT" --scope witness-findings --key witness-refinery-queue-malformed-visits --about tk-visit \
        --title "$SIT" --message "21 visits, retract skips them" 2>&1); RC=$?
eq "$RC" "3" "(sibling/subject) a new key over a live finding's subject exits 3"
eq "$(beads)" "1" "(sibling/subject) and files nothing"
has "$OUT" "refusing to file a new bead" "(sibling/subject) says it refused"
has "$OUT" "fnd-1 [open] --key stale-malformed-visits --about tk-visit — $SIT" "(sibling/subject) lists the live finding with the key and subject to re-run with"
has "$OUT" "--distinct" "(sibling/subject) names the override for a different situation"
eq "$(grep -c 'sling' "$STUB_PROACTIVE_LOG")" "1" "(sibling/subject) a refused filing slings no reaction"

# Re-run with the listed key and subject: the report is an occurrence there.
OUT=$("$SUT" --scope witness-findings --key stale-malformed-visits --about tk-visit \
        --title "$SIT" --message "21 visits, still skipped" 2>&1); RC=$?
eq "$RC" "0" "(sibling/re-run) the listed key and subject land"
eq "$(beads)" "1" "(sibling/re-run) still one bead"
eq "$(meta fnd-1 'finding.occurrences')" "2" "(sibling/re-run) counted as an occurrence on it"

# The key half: the same key over another subject, or over none.
OUT=$("$SUT" --scope witness-findings --key stale-malformed-visits --about tk-handoff \
        --title "$SIT" --message "21 visits" 2>&1); RC=$?
eq "$RC" "3" "(sibling/key) the live key over another subject exits 3"
has "$OUT" "fnd-1 [open] --key stale-malformed-visits --about tk-visit" "(sibling/key) lists the finding holding the key"
OUT=$("$SUT" --scope witness-findings --key stale-malformed-visits \
        --title "$SIT" --message "21 visits" 2>&1); RC=$?
eq "$RC" "3" "(sibling/key) the live key with no subject exits 3"
eq "$(beads)" "1" "(sibling/key) neither files a bead"

# --distinct files it: the caller compared and the situation is another one.
OUT=$("$SUT" --scope witness-findings --key witness-salvage-refused --about tk-visit --distinct \
        --title "tk-visit salvage refused" --message "no worktree" 2>&1); RC=$?
eq "$RC" "0" "(sibling/--distinct) exit 0"
eq "$(beads)" "2" "(sibling/--distinct) files its own bead beside the live one"
has "$(cat "$STUB_PROACTIVE_LOG")" "sling fnd-2" "(sibling/--distinct) and slings its reaction"

# Only a live finding in the same scope is a sibling, and only one that shares
# a half: another patrol's finding, a closed one, or one that shares neither key
# nor subject files as before.
OUT=$("$SUT" --scope deacon-findings --key dolt-visit-lag --about tk-visit \
        --title "dolt lag" --message "lag" 2>&1); RC=$?
eq "$RC" "0" "(sibling/scope) another scope's finding on the subject is no sibling"
eq "$(beads)" "3" "(sibling/scope) it files"
OUT=$("$SUT" --scope witness-findings --key witness-crash-loop --about tk-other \
        --title "crash loop" --message "recovered twice" 2>&1); RC=$?
eq "$RC" "0" "(sibling/neither half) a new key over a new subject files"
eq "$(beads)" "4" "(sibling/neither half) as its own bead"
gc bd close fnd-1 >/dev/null 2>&1
gc bd close fnd-2 >/dev/null 2>&1
OUT=$("$SUT" --scope witness-findings --key witness-legacy-visits --about tk-visit \
        --title "$SIT" --message "21 visits" 2>&1); RC=$?
eq "$RC" "0" "(sibling/closed) a closed finding on the subject is no sibling"
eq "$(beads)" "5" "(sibling/closed) it files"

# Findings with no subject share only a key, so distinct keys stay distinct.
reset
"$SUT" --scope deacon-findings --key dolt-server-unreachable --title a --message a >/dev/null 2>&1
OUT=$("$SUT" --scope deacon-findings --key dolt-orphan-dbs --title b --message b 2>&1); RC=$?
eq "$RC" "0" "(sibling/no subject) two keys with no subject are two findings"
eq "$(beads)" "2" "(sibling/no subject) both file"

# A held sibling is still a live record of the situation, so it is listed, after
# the unheld one.
reset
"$SUT" --scope witness-findings --key k-first --about tk-visit --title "$SIT" --message m >/dev/null 2>&1
put_bead fix-1 open
hold fnd-1 blocked fix-1
"$SUT" --scope witness-findings --key k-second --about tk-visit --distinct --title "$SIT" --message m >/dev/null 2>&1
OUT=$("$SUT" --scope witness-findings --key k-third --about tk-visit --title "$SIT" --message m 2>&1); RC=$?
eq "$RC" "3" "(sibling/held) a held sibling still refuses the filing"
has "$OUT" "fnd-1 [blocked]" "(sibling/held) the held finding is listed"
FIRST=$(printf '%s\n' "$OUT" | grep -m1 '^  fnd-' | sed 's/^  \(fnd-[0-9]*\).*/\1/')
eq "$FIRST" "fnd-2" "(sibling/held) the unheld finding is listed first"

# The sibling lookup itself cannot be read: fail CLOSED, as the exact lookup
# does, rather than read a failed listing as "no sibling" and file the twin.
reset
"$SUT" --scope witness-findings --key k-live --about tk-visit --title "$SIT" --message m >/dev/null 2>&1
export STUB_LIST_FAIL_FIELD=finding.scope
OUT=$("$SUT" --scope witness-findings --key k-new --about tk-visit --title "$SIT" --message m 2>&1); RC=$?
eq "$RC" "1" "(sibling/unreadable) fails closed on an unreadable sibling lookup"
eq "$(beads)" "1" "(sibling/unreadable) files nothing"
has "$OUT" "sibling lookup failed" "(sibling/unreadable) says the lookup failed"
OUT=$("$SUT" --scope witness-findings --key k-live --about tk-visit --title "$SIT" --message m 2>&1); RC=$?
eq "$RC" "0" "(sibling/unreadable) an exact repeat never reaches the sibling lookup"
eq "$(meta fnd-1 'finding.occurrences')" "2" "(sibling/unreadable) and lands on its bead"
OUT=$("$SUT" --scope witness-findings --key k-other --about tk-visit --distinct --title "$SIT" --message m 2>&1); RC=$?
eq "$RC" "0" "(sibling/unreadable) --distinct skips the lookup"
eq "$(beads)" "2" "(sibling/unreadable) and files"

# ── 19. a wisp is no subject ─────────────────────────────────────────
# A patrol burns its wisp when the pass ends and the next pass pours another,
# so a finding about one would carry a new --about every pass and file a new
# bead each time. The wisp is dropped and the key alone is the identity.
reset
OUT=$("$SUT" --scope witness-findings --key witness-binding-prefix-empty --about tk-wisp-abc \
        --title "binding prefix empty" --message "wisp poured with an empty binding_prefix" 2>&1); RC=$?
eq "$RC" "0" "(wisp) a wisp subject still files"
has "$OUT" "tk-wisp-abc is a wisp" "(wisp) and says the subject was dropped"
eq "$(meta fnd-1 'finding.about')" "<absent>" "(wisp) no finding.about is stamped"
eq "$(cat "$STUB_DEPS")" "" "(wisp) no tracks edge to a bead about to vanish"
"$SUT" --scope witness-findings --key witness-binding-prefix-empty --about tk-wisp-def \
  --title "binding prefix empty" --message "wisp poured with an empty binding_prefix" >/dev/null 2>&1
eq "$(beads)" "1" "(wisp) the next pass's wisp lands on the same bead"
eq "$(meta fnd-1 'finding.occurrences')" "2" "(wisp) as an occurrence"
OUT=$("$SUT" --key witness-binding-prefix-empty --about tk-wisp-ghi --title t --message m --dry-run 2>&1)
hasnt "$OUT" "about=" "(wisp) a dry run shows no subject either"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
