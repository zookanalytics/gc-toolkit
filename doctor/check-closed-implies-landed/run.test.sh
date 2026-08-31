#!/usr/bin/env bash
# Hermetic test for doctor/check-closed-implies-landed (I5). Stub gc/bd only.
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
# Deliberately looser than bd: it serves the whole store whatever the query
# filters on, so a fixture can feed the check rows the real `--has-metadata-key`
# would have withheld. That is what proves the check's own anchor test rather
# than the query's.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BD_ARGS:-/dev/null}"
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores" BD_ARGS="$TMP/bd-args.log"
run_check() { : > "$BD_ARGS"; RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }
bead() { printf '{"id":"%s","status":"closed","parent":null,"metadata":%s}' "$1" "$2"; }
# The full shape: a bead's status and parent decide whether it is the anchor.
beadx() { printf '{"id":"%s","status":"%s","parent":%s,"metadata":%s}' "$1" "$2" \
    "$(if [ "$3" = "-" ]; then printf 'null'; else printf '"%s"' "$3"; fi)" "$4"; }
store() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.json"; }

# --- 1. healthy terminal shapes pass -----------------------------------------
store "$(bead c-1 '{"merge_result":"merged","merged_sha":"abc123"}')" \
      "$(bead c-2 '{"merge_result":"abandoned"}')" \
      "$(bead c-3 '{"merge_result":"blocked"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "merged+sha and explicit terminal states pass"
has "$OUT" "OK:" "the pass message is the OK line"
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--all" "the scan spans every status — an OPEN parent is what proves a closed bead is not the anchor"
has "$ARGS" "--has-metadata-key merge_result" "merge_result is the candidate net, not the anchor test"
has "$ARGS" "--limit 0" "the scan is not truncated by a default limit"

# --- 2. closed but not landed (the 2026-08-23 shape) --------------------------
store "$(bead c-4 '{"merge_result":"pull_request","pr_url":"https://x/pr/4"}')" \
      "$(bead c-5 '{"merge_result":"pre_open_gate"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "closed with merge_result=pull_request/pre_open_gate is an ERROR"
has "$OUT" "c-4" "the pull_request husk is named"
has "$OUT" "https://x/pr/4" "the stranded PR is named"
has "$OUT" "c-5" "the pre_open_gate husk is named"

# --- 3. merged with no evidence -----------------------------------------------
store "$(bead c-6 '{"merge_result":"merged"}')"
OUT=$(run_check); RC=$?
eq "$RC" "1" "closed merged with NO merged_sha is a WARNING, not an error"
has "$OUT" "c-6" "the unevidenced landing is named"
has "$OUT" "merged_sha" "the warning names the missing evidence"

# --- 4. unanchored closed beads are out of scope --------------------------------
store "$(bead c-7 '{"merge_result":""}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an empty merge_result on a closed bead is not a finding here"

# --- 5. carrying merge_result is not being an anchor ----------------------------
# A rework child of an OPEN anchor: same branch, stamped by the same machinery.
# merge.sh enumerates the anchor, so the child's stamp strands nothing.
store "$(beadx a-1 open - '{"merge_result":"pre_open_gate","branch":"polecat/a-1"}')" \
      "$(beadx k-1 closed a-1 '{"merge_result":"pre_open_gate","branch":"polecat/a-1"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a rework child sharing its open anchor's branch is not a finding"
hasnt "$OUT" "k-1" "the child is not named"
has "$OUT" "1 closed bead(s) carry merge_result but are not anchors" "the exemption is counted, not silent"

# A chain of them: each child is cleared by the parent one hop up.
store "$(beadx a-1 open - '{"merge_result":"pre_open_gate","branch":"polecat/a-1"}')" \
      "$(beadx k-1 closed a-1 '{"merge_result":"pre_open_gate","branch":"polecat/a-1"}')" \
      "$(beadx k-2 closed k-1 '{"merge_result":"pre_open_gate","branch":"polecat/a-1"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a rework chain clears one hop at a time, not just the first child"

# The anchor's own state is judged on its own: exempting children never
# silences the bead merge.sh would actually have enumerated.
store "$(beadx a-2 closed - '{"merge_result":"pull_request","pr_number":"9","pr_url":"https://x/pr/9"}')" \
      "$(beadx k-3 closed a-2 '{"merge_result":"pull_request","pr_number":"9"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a closed unlanded ANCHOR is still an error when its children are exempt"
has "$OUT" "a-2" "the anchor is named"
hasnt "$OUT" "bead k-3" "its child is not reported as a second copy of the same defect"

# The anchor may have landed since: the child's stale stamp is still not the
# thing that strands a PR, and its parent needs no state test to prove it.
store "$(beadx a-3 closed - '{"merge_result":"merged","merged_sha":"deadbee","pr_number":"568"}')" \
      "$(beadx k-4 closed a-3 '{"merge_result":"pull_request","pr_number":"568"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a child of an anchor that has since landed is not a finding"

# The guard: a parent edge alone exempts nothing. A convoy child is an anchor
# in its own right, and its parent names different work.
store "$(beadx p-1 open - '{"merge_result":"pre_open_gate","branch":"polecat/p-1"}')" \
      "$(beadx c-8 closed p-1 '{"merge_result":"pull_request","branch":"polecat/c-8","pr_url":"https://x/pr/8"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a child whose parent names DIFFERENT work is judged as the anchor it is"
has "$OUT" "c-8" "the convoy child is named"

# A parent that carries no merge_result is no anchor either.
store "$(beadx p-2 open - '{"branch":"polecat/p-2"}')" \
      "$(beadx c-9 closed p-2 '{"merge_result":"pull_request","branch":"polecat/p-2"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a parent with no merge_result cannot clear its child"

# --- 6. a disposed bead carries its own terminal state ---------------------------
store "$(bead c-10 '{"merge_result":"pull_request","gc.superseded_by":"s-1","gc.superseded_by_store":"rig:alpha"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "gc.superseded_by IS the explicit terminal state the OK line promises"
hasnt "$OUT" "c-10" "the disposed bead is not named"
has "$OUT" "disposed via gc.superseded_by" "the disposal is counted"

# --- 7. the remedy states the ledger's fact, never the PR's -----------------------
store "$(bead c-11 '{"merge_result":"pull_request","existing_pr":"https://x/pr/11"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a stranded anchor is an error however it records its PR"
has "$OUT" "https://x/pr/11" "existing_pr identifies the PR when pr_url is absent"

store "$(bead c-11b '{"merge_result":"pull_request","pr_url":"","existing_pr":"https://x/pr/11"}')"
OUT=$(run_check); RC=$?
has "$OUT" "https://x/pr/11" "a pr_url stamped EMPTY reads the same as an absent one"
has "$OUT" "--to merged --close --set merged_sha" "a stale stamp after a real landing is recorded, not reopened"
has "$OUT" "reopen c-11" "an unlanded anchor is still reopenable"
hasnt "$OUT" "will never merge" "the check is ledger-only; it does not assert what the PR did"

store "$(bead c-12 '{"merge_result":"pre_open_gate"}')"
OUT=$(run_check); RC=$?
has "$OUT" "no PR was ever opened" "pre_open_gate has no PR to read"
hasnt "$OUT" "merged_sha" "and so is offered no record-the-landing repair"

# --- 8. fail-CLOSED ------------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"

# --- 9. offline-safe: the check never calls gh ----------------------------------
if grep -qE '(^|[^a-z])gh[[:space:]]' < <(grep -vE '^[[:space:]]*#' "$CHECK"); then
    bad "the check shells out to gh — it is specified ledger-only"
else
    ok "the check is ledger-only (no gh calls)"
fi

echo
echo "check-closed-implies-landed: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
