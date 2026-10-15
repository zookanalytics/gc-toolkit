#!/usr/bin/env bash
# Hermetic test for doctor/check-gate-marker-provenance (I7 depth): every closed
# approve outcome bead lane-state.sh would derive green from records a coherent
# gc.outcome. Stubs gc, bd and gh; gh only records a call, which the check never
# makes. The bd stub honours --status/--all/--has-metadata-key the way bd does,
# so a query that forgot --status closed, or asked the wrong key, cannot pass.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-gate-marker-provenance-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }
# BSD wc pads its count with spaces, and eq compares strings.
wc() { command wc "$@" | tr -d ' '; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/gh" "$TMP/alpha"
git init -q "$TMP/alpha"
git -C "$TMP/alpha" remote add origin https://github.com/acme/alpha.git
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC

# Models the queries the check depends on. --has-metadata-key merge_result serves
# the anchor file; signoff_verdict serves the review file. --has-metadata-key
# returns only beads carrying that key, so a bead with no signoff_verdict is NOT
# returned — which is exactly why the audit never has to special-case it.
# --all returns every status; otherwise --status filters, defaulting to open.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
db=""; key=""; status=""; all=0; prev=""
for a in "$@"; do
  case "$prev" in --db) db="$a" ;; --has-metadata-key) key="$a" ;; --status|-s) status="$a" ;; esac
  [ "$a" = "--all" ] && all=1
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
case "$key" in
  merge_result)                 f="$STORES/$name.anchors.json" ;;
  signoff_verdict)               f="$STORES/$name.reviews.json" ;;
  *) printf '[]'; exit 0 ;;
esac
[ -f "$f" ] || { printf '[]'; exit 0; }
# Pass an unparseable fixture through raw so the CHECK's own jq is what fails,
# exercising its parse-failure arm rather than this stub's.
jq -e . "$f" >/dev/null 2>&1 || { cat "$f"; exit 0; }
out=$(jq -c --arg k "$key" '[.[] | select(.metadata | has($k))]' "$f")
if [ "$all" -eq 1 ]; then
  :
elif [ -n "$status" ] && [ "$status" != "all" ]; then
  out=$(printf '%s' "$out" | jq -c --arg s "$status" '[.[] | select(.status == $s)]')
else
  out=$(printf '%s' "$out" | jq -c '[.[] | select(.status == "open")]')
fi
printf '%s' "$out"
BD

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gh" <<'GH'
[ "${GH_ABSENT:-0}" = "1" ] && exit 127
path=""
for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
pr="${path##*/pulls/}"; pr="${pr%%/*}"
echo "$path" >> "$GH_LOG"
f="$GH_DIR/reviews_$pr.json"
[ -f "$f" ] || exit 1
cat "$f"
GH
chmod +x "$TMP/bin/gc" "$TMP/bin/bd" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores" GH_DIR="$TMP/gh" GH_LOG="$TMP/gh.log"

run_check() { : > "$GH_LOG"; RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }
anchors() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.anchors.json"; }
reviews() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.reviews.json"; }
# anchor <id> <extra-metadata-json-body>
anchor() { printf '{"id":"%s","status":"open","metadata":{%s}}' "$1" "$2"; }
# rbead <id> <status> <anchor> <verdict> <outcome> [check_name] [reviewed_oid]
# verdict "" omits signoff_verdict (names no verdict); outcome "" omits gc.outcome.
rbead() {
  local id="$1" st="$2" anc="$3" v="$4" oc="$5" cn="${6:-}" oid="${7:-}" m
  m=$(printf '"task_kind":"review","anchor_bead":"%s"' "$anc")
  [ -n "$v" ]   && m="$m,$(printf '"signoff_verdict":"%s"' "$v")"
  [ -n "$oc" ]  && m="$m,$(printf '"gc.outcome":"%s"' "$oc")"
  [ -n "$cn" ]  && m="$m,$(printf '"check_name":"%s"' "$cn")"
  [ -n "$oid" ] && m="$m,$(printf '"reviewed_oid":"%s"' "$oid")"
  printf '{"id":"%s","status":"%s","metadata":{%s}}' "$id" "$st" "$m"
}

OID=0123456789abcdef0123456789abcdef01234567
GATING='"merge_result":"pull_request","check_set":"correctness","branch":"b"'
anchors ""; reviews ""

echo "== the outcome-coherence audit =="
anchors "$(anchor a-1 "$GATING")"; reviews ""

# --- B1. a well-formed approve backing passes (approve + recorded) ----------------
reviews "$(rbead r-1 closed a-1 approve recorded correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an approve outcome stamped gc.outcome=recorded is well-formed"

# --- B1b. a superseded approve is retired, not malformed --------------------------
reviews "$(rbead r-1 closed a-1 approve superseded correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an approve retired with gc.outcome=superseded passes (it no longer derives green)"

# --- B2. an approve with NO gc.outcome is the finding (unstamped) ------------------
# lane-state.sh greens on (signoff_verdict=approve and gc.outcome != superseded),
# so an approve with no outcome at all still derives green while recording nothing.
reviews "$(rbead r-1 closed a-1 approve "" correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an approve carrying no gc.outcome is malformed and errors"
has "$OUT" "a-1" "the anchor is named"
has "$OUT" "r-1" "the malformed outcome bead is named"
has "$OUT" "correctness" "the lane it backs is named"
has "$OUT" "<unset>" "the missing outcome is reported as unset"

# --- B2b. an approve with an outcome no writer produces errors too -----------------
reviews "$(rbead r-1 closed a-1 approve moot correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an approve carrying gc.outcome=moot (not recorded/superseded) errors"
has "$OUT" "moot" "the offending outcome value is reported"

# --- B2c. reviewed_oid alignment: a malformed approve with NO oid is not audited ---
# lane-state.sh:derivation requires a non-empty reviewed_oid before a local
# review bead derives green, so a no-oid approve is not green evidence and the
# audit must not flag it (aligning the doctor with the merge path).
reviews "$(rbead r-1 closed a-1 approve "" correctness)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a malformed approve carrying no reviewed_oid is not a backing lane-state greens, so it is not flagged"

# --- B3. a request-changes bead never backs a lane --------------------------------
reviews "$(rbead r-1 closed a-1 request-changes recorded correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a closed request-changes bead is not a backing and passes"
reviews "$(rbead r-1 closed a-1 request-changes "" correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a request-changes bead with no outcome is still not a backing (verdict is not approve)"

# --- B4. a close with no signoff_verdict is never fetched ------------------------
# recorded names no verdict, so such a close backs no lane; the audit is keyed on
# signoff_verdict, so it never fetches one and has nothing to flag.
reviews "$(rbead r-1 closed a-1 "" recorded correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a close with no signoff_verdict (gc.outcome=recorded) backs no lane and is never fetched"

# --- B5. an OPEN approve bead is not a backing ------------------------------------
reviews "$(rbead r-1 open a-1 approve "" correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open approve bead (dispatched, not closed) is not audited as a backing"

# --- B6. lane default: an approve with no check_name backs the correctness lane ----------
reviews "$(rbead r-1 closed a-1 approve moot "" "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an approve with no check_name is audited for the correctness lane"
has "$OUT" "lane correctness" "the defaulted lane is named correctness"
anchors "$(anchor a-1 "$GATING,\"check_set\":\"ci\"")"
reviews "$(rbead r-1 closed a-1 approve moot ci "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an approve for the ci lane names ci"
has "$OUT" "lane ci" "the explicit lane is named"

# --- B7. scope: only OPEN GATING anchors' backings are audited --------------------
anchors "$(anchor a-2 "\"merge_result\":\"merged\",\"check_set\":\"correctness\",\"branch\":\"b\"")" \
        "$(anchor a-3 "\"merge_result\":\"abandoned\",\"check_set\":\"correctness\",\"branch\":\"b\"")"
reviews "$(rbead r-2 closed a-2 approve "" correctness "$OID")" "$(rbead r-3 closed a-3 approve moot correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a malformed approve on a merged or abandoned anchor is out of scope"

anchors "$(anchor a-1 "$GATING")"
reviews "$(rbead r-9 closed some-other-anchor approve "" correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a malformed approve whose anchor is not an open gating anchor is not flagged"

# --- B8. pre_open_gate anchors are in scope too -----------------------------------
anchors "$(anchor a-4 "\"merge_result\":\"pre_open_gate\",\"check_set\":\"correctness\",\"branch\":\"b\"")"
reviews "$(rbead r-4 closed a-4 approve "" correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a malformed approve on a pre_open_gate anchor errors"

# --- B9. a task_kind=review bead is not itself an anchor ---------------------------
anchors "$(anchor a-5 "$GATING,\"task_kind\":\"review\"")"
reviews "$(rbead r-5 closed a-5 approve "" correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a task_kind=review bead carrying merge_result is skipped, not treated as an anchor"
hasnt "$OUT" "a-5" "the review-shaped anchor is not reported"

# --- B10. count and multiple findings ---------------------------------------------
anchors "$(anchor a-1 "$GATING")" "$(anchor a-6 "\"merge_result\":\"pre_open_gate\",\"check_set\":\"correctness\",\"branch\":\"b\"")"
reviews "$(rbead r-1 closed a-1 approve "" correctness "$OID")" "$(rbead r-6 closed a-6 approve moot correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "two malformed approves error"
has "$OUT" "2 finding(s)" "the finding count is reported"

echo "== a stored marker is not read =="

# --- M1. a check.<lane>=green marker with no backing is no finding ----------------
# Nothing reads a stored lane value: the merge path, pr-open.sh and gate-ensure.sh
# all derive a lane from its reviews, so a marker over no review backs nothing
# and holds nothing, and the check never consults GitHub to account for one.
anchors "$(anchor a-w "$GATING,\"pr_number\":\"101\",\"check.correctness\":\"green\"")"; reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "a bare green marker with no backing is no finding"
hasnt "$OUT" "a-w" "…and its anchor is not named"
eq "$(cat "$GH_LOG" | wc -l)" "0" "…and no GitHub call is made"

# --- M2. a malformed backing is one finding, marker or not ------------------------
anchors "$(anchor a-x "$GATING,\"pr_number\":\"101\",\"check.correctness\":\"green\"")"
reviews "$(rbead r-x closed a-x approve moot correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a malformed approve backing errors beside a marker"
has "$OUT" "1 finding(s)" "…reported once"
anchors "$(anchor a-y "$GATING")"
reviews "$(rbead r-y closed a-y approve moot correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "…and with no marker at all"
has "$OUT" "a-y" "the anchor is named"

echo "== fail-closed, suspended, executable =="

# --- fail-CLOSED ------------------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
anchors "$(anchor a-1 "$GATING")"; reviews "$(rbead r-1 closed a-1 approve moot correctness "$OID")"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns rather than clearing the finding"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.anchors.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable anchor listing warns"
anchors "$(anchor a-1 "$GATING")"
printf 'not json' > "$TMP/stores/alpha.reviews.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable review listing warns rather than clearing every backing"

# --- suspended rigs are skipped, not scanned --------------------------------------
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
anchors "$(anchor a-1 "$GATING")"; reviews "$(rbead r-1 closed a-1 approve moot correctness "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped rather than queried"
has "$OUT" "suspended" "the skip is reported as a note"

# --- the check ships executable ---------------------------------------------------
if [ -x "$CHECK" ]; then ok "run.sh ships with its execute bit"; else bad "run.sh ships with its execute bit"; fi

echo
echo "check-gate-marker-provenance: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
