#!/usr/bin/env bash
# Hermetic test for doctor/check-review-verdict-recorded (I7 disposal). Stubs gc
# and bd; nothing here touches a network or a real store. The bd stub honours
# --status the way bd does, so a check that asked for the wrong status cannot
# pass: the closed-review listing and the open-anchor set come from the same
# store file and are separated only by that flag.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC

# One store file per rig; --status selects from it exactly as bd would. A
# --has-metadata-key filter is applied too, so a listing that forgot to narrow
# to anchor-carrying beads still sees only what bd would have returned.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
db=""; key=""; status=""; prev=""
for a in "$@"; do
  case "$prev" in --db) db="$a" ;; --has-metadata-key) key="$a" ;; --status|-s) status="$a" ;; esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
[ "$status" = "${BD_FAIL_STATUS:-}" ] && exit 3
f="$STORES/$name.json"
[ -f "$f" ] || { printf '[]'; exit 0; }
jq -c --arg s "$status" --arg k "$key" '[ .[]
  | select($s == "" or .status == $s)
  | select($k == "" or ((.metadata // {}) | has($k))) ]' "$f"
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

run_check() { RIGS_JSON="$TMP/rigs.json" bash "$CHECK" 2>&1; }
store() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.json"; }
# anchor <id> <status>
anchor() { printf '{"id":"%s","status":"%s","notes":"","metadata":{"merge_result":"pre_open_gate"}}' "$1" "$2"; }
# review <id> <anchor> <notes> <extra-metadata-body>
review() {
  local extra=""
  [ -z "${4:-}" ] || extra=$(printf ',%s' "$4")
  printf '{"id":"%s","status":"closed","closed_at":"2026-08-27T01:02:56Z","notes":"%s","metadata":{"task_kind":"review","anchor_bead":"%s","check_name":"codex","reviewed_oid":"ac847e80411ed68bc05c8bf5282da5ffc9775dee"%s}}' "$1" "$3" "$2" "$extra"
}

echo "# the defect: a closed review under an OPEN anchor that recorded nothing"
store "$(anchor a-open open)" "$(review rv-silent a-open '' '')"
out=$(run_check); rc=$?
eq "$rc" 2 "a silent close is an error"
has "$out" "rv-silent" "the finding names the review bead"
has "$out" "a-open" "…and the anchor still holding the gate"
has "$out" "closed on 2026-08-27" "…and when it closed"
has "$out" "1 finding(s)" "exactly one finding"

echo "# a clean baseline reports zero"
store "$(anchor a-open open)" "$(review rv-recorded a-open '' '"gc.outcome":"recorded"')"
out=$(run_check); rc=$?
eq "$rc" 0 "a store whose reviews all recorded a disposal passes"
has "$out" "OK:" "…and says so"
hasnt "$out" "rv-recorded" "…naming nothing"

echo "# each close-time record clears the review on its own"
for ev in '"gc.outcome":"recorded"' '"gc.outcome":"moot"' '"verdict":"COMMENT"' \
          '"review_state":"COMMENTED"' '"review_note":"superseded by a rebase"' \
          '"duplicate_of":"rv-other"' '"gc.work_outcome":"no-op"'; do
  store "$(anchor a-open open)" "$(review rv-1 a-open '' "$ev")"
  out=$(run_check)
  eq "$?" 0 "cleared by $ev"
done
store "$(anchor a-open open)" "$(review rv-1 a-open 'VERDICT: COMMENT' '')"
out=$(run_check); eq "$?" 0 "cleared by a verdict body in notes"

echo "# dispatch-time stamps are not a verdict"
# reviewed_oid and check_name are on every review in this file already: the
# silent case above carries both and still flags. review_branch/review_pool are
# the rest of the dispatcher's stamp and must not clear one either.
store "$(anchor a-open open)" "$(review rv-1 a-open '' '"review_branch":"polecat/x","review_base":"main","review_pool":"p","fix_target_pool":"p"')"
out=$(run_check); rc=$?
eq "$rc" 2 "a review carrying only the dispatcher's stamps has answered nothing"

echo "# whitespace is not a record"
store "$(anchor a-open open)" "$(review rv-1 a-open '   ' '"gc.outcome":"  "')"
out=$(run_check); rc=$?
eq "$rc" 2 "blank notes and a blank outcome do not clear it"

echo "# scope: the anchor must still be open"
store "$(anchor a-shut closed)" "$(review rv-1 a-shut '' '')"
out=$(run_check); rc=$?
eq "$rc" 0 "the same silence under a CLOSED anchor is history, not a finding"
store "$(review rv-1 a-gone '' '')"
out=$(run_check); rc=$?
eq "$rc" 0 "an anchor that does not resolve at all is out of scope"

echo "# scope: only review beads, only closed ones"
store "$(anchor a-open open)" '{"id":"w-1","status":"closed","notes":"","metadata":{"anchor_bead":"a-open"}}'
out=$(run_check); rc=$?
eq "$rc" 0 "a closed non-review bead carrying anchor_bead is not a review"
store "$(anchor a-open open)" '{"id":"rv-live","status":"open","notes":"","metadata":{"task_kind":"review","anchor_bead":"a-open"}}'
out=$(run_check); rc=$?
eq "$rc" 0 "an OPEN review has not closed silently — it is still owed"

echo "# a review naming no anchor is left alone"
store "$(anchor a-open open)" '{"id":"rv-noanchor","status":"closed","notes":"","metadata":{"task_kind":"review"}}'
out=$(run_check); rc=$?
eq "$rc" 0 "the scope condition cannot be tested, so it is not a finding"

echo "# unreadable stores warn, never pass"
store "$(anchor a-open open)" "$(review rv-1 a-open '' '')"
out=$(BD_FAIL_STORE=alpha run_check); rc=$?
eq "$rc" 1 "a store bd could not list warns"
has "$out" "NOT checked" "…and says the store was not checked"
hasnt "$out" "rv-1" "…and reports no finding from it"

out=$(BD_FAIL_STATUS=open run_check); rc=$?
eq "$rc" 1 "a readable review listing with an unreadable open-set warns"
has "$out" "whether their anchors are still open is unknown" "…naming what could not be decided"
hasnt "$out" "0 finding" "…and does not report a clean pass"

out=$(RIGS_RC=1 run_check); rc=$?
eq "$rc" 1 "an unreadable rig list warns"
has "$out" "no set of bead stores to scan" "…and says why"

echo "# a suspended rig is skipped, not scanned"
cat > "$TMP/rigs-susp.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
store "$(anchor a-open open)" "$(review rv-1 a-open '' '')"
out=$(RIGS_JSON="$TMP/rigs-susp.json" bash "$CHECK" 2>&1); rc=$?
eq "$rc" 0 "a suspended rig contributes no finding"
has "$out" "suspended" "…and is noted as skipped"

echo "# many findings are all reported"
store "$(anchor a-open open)" "$(anchor b-open open)" \
      "$(review rv-1 a-open '' '')" "$(review rv-2 b-open '' '')" \
      "$(review rv-3 a-open '' '"gc.outcome":"recorded"')"
out=$(run_check); rc=$?
eq "$rc" 2 "two silent reviews are an error"
has "$out" "2 finding(s)" "…counted"
has "$out" "rv-1" "…rv-1 named"
has "$out" "rv-2" "…rv-2 named"
hasnt "$out" "rv-3" "…and the one that recorded a verdict is not"

echo "check-review-verdict-recorded: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
