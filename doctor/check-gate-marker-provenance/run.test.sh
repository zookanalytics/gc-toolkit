#!/usr/bin/env bash
# Hermetic test for doctor/check-gate-marker-provenance (I7 depth), a two-arm
# check: ARM A audits that every check.<lane>=green marker on an open gating
# anchor has a backing (a transition guard kept while gate-ensure.sh still reads
# the marker), resolving locally then against an APPROVED GitHub review; ARM B
# audits that every closed approve outcome bead lane-state.sh would derive green
# from records a coherent gc.outcome. Stubs gc, bd and gh; the rig checkout is a
# real throwaway git repo so ARM A's origin parse runs against the real tool. The
# bd stub honours --status/--all/--has-metadata-key the way bd does, so a query
# that forgot --all, or asked the wrong key, cannot pass.
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

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/gh" "$TMP/alpha"
git init -q "$TMP/alpha"
git -C "$TMP/alpha" remote add origin https://github.com/acme/alpha.git
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC

# Models the queries both arms depend on. --has-metadata-key merge_result serves
# the anchor file; reviewed_oid AND signoff_verdict both serve the review file, so
# ARM A's reviewed_oid index and ARM B's signoff_verdict candidate set read the
# same fixture through the key each asked for. --has-metadata-key returns only
# beads carrying that key, so a legacy bead with no signoff_verdict is NOT
# returned to ARM B — which is exactly why that arm never has to special-case it.
# --all returns every status; otherwise --status filters, defaulting to open.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
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
  reviewed_oid|signoff_verdict)  f="$STORES/$name.reviews.json" ;;
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

cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
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
# verdict "" omits signoff_verdict (a legacy bead); outcome "" omits gc.outcome.
rbead() {
  local id="$1" st="$2" anc="$3" v="$4" oc="$5" cn="${6:-}" oid="${7:-}" m
  m=$(printf '"task_kind":"review","anchor_bead":"%s"' "$anc")
  [ -n "$v" ]   && m="$m,$(printf '"signoff_verdict":"%s"' "$v")"
  [ -n "$oc" ]  && m="$m,$(printf '"gc.outcome":"%s"' "$oc")"
  [ -n "$cn" ]  && m="$m,$(printf '"check_name":"%s"' "$cn")"
  [ -n "$oid" ] && m="$m,$(printf '"reviewed_oid":"%s"' "$oid")"
  printf '{"id":"%s","status":"%s","metadata":{%s}}' "$id" "$st" "$m"
}
approvals() { printf '%s' "$2" > "$TMP/gh/reviews_$1.json"; }

OID=0123456789abcdef0123456789abcdef01234567
OTHER=fedcba9876543210fedcba9876543210fedcba98
GATING='"merge_result":"pull_request","check_set":"codex","branch":"b"'
anchors ""; reviews ""

echo "== ARM A: the transition missing-backing marker audit =="

# --- A1. RESOLVE A clears a green lane on a legacy closed backing ------------------
# A closed bead with gc.outcome=recorded and no signoff_verdict at all predates
# the verdict stamp; it still counts as evidence, at no GitHub cost.
anchors "$(anchor a-1 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\"")"
reviews "$(rbead r-1 closed a-1 "" recorded codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a legacy closed backing (gc.outcome=recorded, no signoff_verdict) backs the green lane"
has "$OUT" "OK:" "the pass message is the OK line"
eq "$(wc -l < "$GH_LOG")" "0" "RESOLVE A costs no GitHub call"

# --- A1b. an explicit approve verdict also backs the lane --------------------------
reviews "$(rbead r-1 closed a-1 approve recorded codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a closed review bead carrying signoff_verdict=approve backs the green lane"

# --- A2. an OPEN review bead does not back the lane --------------------------------
# gate-ensure stamps reviewed_oid at DISPATCH, before any verdict exists, so an
# open bead carrying reviewed_oid is not yet a verdict. --all must still be used
# to SEE it (and exclude it), rather than never fetching it at all.
reviews "$(rbead r-1 open a-1 "" "" codex "$OID")"
approvals 101 '[]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "an open review bead (dispatched, no verdict yet) does not back a green marker"
has "$OUT" "a-1" "the unbacked anchor is named"

# --- A2z. a closed request-changes verdict does not back the lane -----------------
reviews "$(rbead r-1 closed a-1 request-changes recorded codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a closed request-changes bead does not back a green marker"

# --- A2b. RESOLVE A binds a verdict to the LANE it was recorded for ----------------
# merge.sh gates each check_set member separately, so a verdict on one lane is
# not evidence for another lane on the same anchor.
anchors "$(anchor a-1b "$GATING,\"check_set\":\"codex,ci\",\"pr_number\":\"101\",\"check.codex\":\"green\",\"check.ci\":\"green\"")"
reviews "$(rbead r-1 closed a-1b approve recorded codex "$OID")"
approvals 101 '[]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a codex verdict does not clear the ci lane on the same anchor"
has "$OUT" "check.ci=" "the gate nobody reviewed is the one reported"
hasnt "$OUT" "check.codex=" "the gate that was reviewed is not reported"
has "$OUT" "check_name=ci" "the finding names the gate the missing verdict was owed for"

# signoff.sh defaults an absent check_name to codex and stamps check.codex for
# that bead, so RESOLVE A reads it back the same way.
anchors "$(anchor a-1c "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\"")"
reviews "$(rbead r-1 closed a-1c approve recorded "" "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a review bead with no check_name resolves the codex gate"
anchors "$(anchor a-1d "$GATING,\"check_set\":\"ci\",\"pr_number\":\"101\",\"check.ci\":\"green\"")"
reviews "$(rbead r-1 closed a-1d approve recorded "" "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "that default does not let it clear a gate other than codex"

# --- A2c. RESOLVE A does not compare the review bead's oid to a head ---------------
# A lane state names no commit, so which commit the recorded verdict read is not
# part of the key: any non-empty reviewed_oid backs the lane.
anchors "$(anchor a-1e "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\"")"
reviews "$(rbead r-1 closed a-1e approve recorded codex "$OTHER")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a verdict recorded at a commit the branch has moved past still backs the lane"
eq "$(wc -l < "$GH_LOG")" "0" "…and it costs no GitHub call"

# --- A3. no evidence anywhere is an ERROR -----------------------------------------
anchors "$(anchor a-1 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\"")"
reviews "$(rbead r-2 closed some-other-anchor approve recorded codex "$OID")"
approvals 101 '[]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a green marker no review bead and no approval covers is an ERROR"
has "$OUT" "a-1" "the unbacked anchor is named"
has "$OUT" "nothing reviewed" "the finding says what is missing"
eq "$(wc -l < "$GH_LOG")" "1" "RESOLVE B is consulted only for what A left over"

# --- A4. RESOLVE B: an APPROVED review on the PR clears the lane -------------------
approvals 101 "[{\"state\":\"APPROVED\",\"commit_id\":\"$OID\"}]"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an APPROVED GitHub review on the anchor's PR clears it"

# --- A5. RESOLVE B is not head-bound, and only APPROVED counts --------------------
approvals 101 "[{\"state\":\"APPROVED\",\"commit_id\":\"$OTHER\"}]"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an approval given at an earlier commit still clears the lane"
approvals 101 "[{\"state\":\"COMMENTED\",\"commit_id\":\"$OID\"},{\"state\":\"CHANGES_REQUESTED\",\"commit_id\":\"$OID\"}]"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a PR carrying only COMMENTED and CHANGES_REQUESTED reviews is not approved"
has "$OUT" "carries no APPROVED review" "the finding says the approval is missing"

# --- A6. a review bead carrying its own green marker is not an anchor --------------
anchors "$(anchor a-2 "$GATING,\"task_kind\":\"review\",\"pr_number\":\"102\",\"check.codex\":\"green\"")"
reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "a task_kind=review bead is skipped, not treated as an unbacked anchor"
hasnt "$OUT" "a-2" "the review bead is not reported"

# --- A7. undetermined, not cleared and not an error -------------------------------
anchors "$(anchor a-3 "$GATING,\"check.codex\":\"green\"")"
reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unbacked marker on an anchor with no pr_number is a WARNING"
has "$OUT" "UNDETERMINED" "the warning says the verdict could not be determined"

anchors "$(anchor a-4 "$GATING,\"pr_number\":\"404\",\"check.codex\":\"green\"")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a failed PR review query is a WARNING, never a pass"
has "$OUT" "could not be read" "the warning names the unread review list"

anchors "$(anchor a-5 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\"")"
approvals 101 "[{\"state\":\"APPROVED\",\"commit_id\":\"$OID\"}]"
OUT=$(GH_ABSENT=1 run_check); RC=$?
eq "$RC" "1" "an unusable gh is a WARNING, never a pass"

git -C "$TMP/alpha" remote set-url origin https://gitlab.example/acme/alpha.git
OUT=$(run_check); RC=$?
eq "$RC" "1" "a non-github origin leaves RESOLVE B unavailable — WARNING"
git -C "$TMP/alpha" remote set-url origin https://github.com/acme/alpha.git

# --- A8. one GitHub call per PR, not one per gate ---------------------------------
anchors "$(anchor a-6 "$GATING,\"check_set\":\"codex,other\",\"pr_number\":\"101\",\"check.codex\":\"green\",\"check.other\":\"green\"")"
reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "two gates on one approved head both clear"
eq "$(sort -u "$GH_LOG" | wc -l)" "1" "the PR review list is fetched once and reused"

# --- A8b. a PAGINATED review list is flattened before it is judged -----------------
anchors "$(anchor a-6b "$GATING,\"pr_number\":\"103\",\"check.codex\":\"green\"")"
reviews ""
printf '[{"state":"COMMENTED","commit_id":"%s"}]\n[{"state":"APPROVED","commit_id":"%s"}]\n' "$OTHER" "$OID" > "$TMP/gh/reviews_103.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an approval on the SECOND page of reviews still clears the lane"

# --- A9. out of scope for the marker arm ------------------------------------------
anchors "$(anchor a-7 "\"merge_result\":\"abandoned\",\"check.codex\":\"green\"")" \
        "$(anchor a-8 "\"merge_result\":\"merged\",\"check.codex\":\"green\"")" \
        "$(anchor a-9 "$GATING,\"check.codex\":\"fixing\"")" \
        "$(anchor a-10 "$GATING,\"check.codex\":\"unreviewed\"")" \
        "$(anchor a-10b "$GATING,\"check.codex\":\"validating\"")"
reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "non-gating states and lanes short of green carry no provenance obligation"

# A marker outside the lane vocabulary belongs to check-gate-integrity; an
# unmigrated green@<oid> is exactly that shape and must not be double-reported.
anchors "$(anchor a-11 "$GATING,\"check.codex\":\"green@$OID\"")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an unmigrated green@<oid> is left to check-gate-integrity, not double-reported"

# Sidecar keys are prose about a gate, not markers.
anchors "$(anchor a-12 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\",\"check.codex.reason\":\"green is prose here\"")"
approvals 101 "[{\"state\":\"APPROVED\",\"commit_id\":\"$OID\"}]"
OUT=$(run_check); RC=$?
eq "$RC" "0" "check.<g>.<sidecar> keys are not treated as markers"

echo "== ARM B: the markerless outcome-coherence audit =="
anchors "$(anchor a-1 "$GATING")"; reviews ""

# --- B1. a well-formed approve backing passes (approve + recorded) ----------------
reviews "$(rbead r-1 closed a-1 approve recorded codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an approve outcome stamped gc.outcome=recorded is well-formed"

# --- B1b. a superseded approve is retired, not malformed --------------------------
reviews "$(rbead r-1 closed a-1 approve superseded codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an approve retired with gc.outcome=superseded passes (it no longer derives green)"

# --- B2. an approve with NO gc.outcome is the finding (unstamped) ------------------
# lane-state.sh greens on (signoff_verdict=approve and gc.outcome != superseded),
# so an approve with no outcome at all still derives green while recording nothing.
reviews "$(rbead r-1 closed a-1 approve "" codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an approve carrying no gc.outcome is malformed and errors"
has "$OUT" "a-1" "the anchor is named"
has "$OUT" "r-1" "the malformed outcome bead is named"
has "$OUT" "codex" "the lane it backs is named"
has "$OUT" "<unset>" "the missing outcome is reported as unset"

# --- B2b. an approve with an outcome no writer produces errors too -----------------
reviews "$(rbead r-1 closed a-1 approve moot codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an approve carrying gc.outcome=moot (not recorded/superseded) errors"
has "$OUT" "moot" "the offending outcome value is reported"

# --- B2c. reviewed_oid alignment: a malformed approve with NO oid is not audited ---
# lane-state.sh:derivation requires a non-empty reviewed_oid before a local
# review bead derives green, so a no-oid approve is not green evidence and the
# outcome arm must not flag it (aligning the doctor with the merge path).
reviews "$(rbead r-1 closed a-1 approve "" codex)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a malformed approve carrying no reviewed_oid is not a backing lane-state greens, so it is not flagged"

# --- B3. a request-changes bead never backs a lane --------------------------------
reviews "$(rbead r-1 closed a-1 request-changes recorded codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a closed request-changes bead is not a backing and passes"
reviews "$(rbead r-1 closed a-1 request-changes "" codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a request-changes bead with no outcome is still not a backing (verdict is not approve)"

# --- B4. a legacy no-verdict recorded bead is well-formed and never fetched --------
reviews "$(rbead r-1 closed a-1 "" recorded codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a legacy backing (gc.outcome=recorded, no signoff_verdict) is well-formed"

# --- B5. an OPEN approve bead is not a backing ------------------------------------
reviews "$(rbead r-1 open a-1 approve "" codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open approve bead (dispatched, not closed) is not audited as a backing"

# --- B6. lane default: an approve with no check_name backs the codex lane ----------
reviews "$(rbead r-1 closed a-1 approve moot "" "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an approve with no check_name is audited for the codex lane"
has "$OUT" "lane codex" "the defaulted lane is named codex"
anchors "$(anchor a-1 "$GATING,\"check_set\":\"ci\"")"
reviews "$(rbead r-1 closed a-1 approve moot ci "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an approve for the ci lane names ci"
has "$OUT" "lane ci" "the explicit lane is named"

# --- B7. scope: only OPEN GATING anchors' backings are audited --------------------
anchors "$(anchor a-2 "\"merge_result\":\"merged\",\"check_set\":\"codex\",\"branch\":\"b\"")" \
        "$(anchor a-3 "\"merge_result\":\"abandoned\",\"check_set\":\"codex\",\"branch\":\"b\"")"
reviews "$(rbead r-2 closed a-2 approve "" codex "$OID")" "$(rbead r-3 closed a-3 approve moot codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a malformed approve on a merged or abandoned anchor is out of scope"

anchors "$(anchor a-1 "$GATING")"
reviews "$(rbead r-9 closed some-other-anchor approve "" codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a malformed approve whose anchor is not an open gating anchor is not flagged"

# --- B8. pre_open_gate anchors are in scope too -----------------------------------
anchors "$(anchor a-4 "\"merge_result\":\"pre_open_gate\",\"check_set\":\"codex\",\"branch\":\"b\"")"
reviews "$(rbead r-4 closed a-4 approve "" codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a malformed approve on a pre_open_gate anchor errors"

# --- B9. a task_kind=review bead is not itself an anchor ---------------------------
anchors "$(anchor a-5 "$GATING,\"task_kind\":\"review\"")"
reviews "$(rbead r-5 closed a-5 approve "" codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a task_kind=review bead carrying merge_result is skipped, not treated as an anchor"
hasnt "$OUT" "a-5" "the review-shaped anchor is not reported"

# --- B10. count and multiple findings ---------------------------------------------
anchors "$(anchor a-1 "$GATING")" "$(anchor a-6 "\"merge_result\":\"pre_open_gate\",\"check_set\":\"codex\",\"branch\":\"b\"")"
reviews "$(rbead r-1 closed a-1 approve "" codex "$OID")" "$(rbead r-6 closed a-6 approve moot codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "two malformed approves error"
has "$OUT" "2 finding(s)" "the finding count is reported"

echo "== transition and arm interaction =="

# --- T1. the wedge: a green marker with NO backing is flagged, not passed ----------
# This is why ARM A survives: gate-ensure.sh reads this marker and skips dispatch,
# while lane-state.sh (the merge path) sees no backing and holds. With a
# pr_number to consult and no GitHub approval, the wedge is a hard ERROR.
anchors "$(anchor a-w "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\"")"; reviews ""
approvals 101 '[]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bare green marker with no backing and no approval is the wedge ARM A still catches"
has "$OUT" "a-w" "the wedged anchor is named"
# Without a pr_number, the operator-approval path cannot be ruled out — UNDETERMINED.
anchors "$(anchor a-w "$GATING,\"check.codex\":\"green\"")"; reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "1" "the same wedge with no pr_number is UNDETERMINED, not silently cleared"

# --- T2. a green marker OVER a malformed backing is ONE finding, from ARM B --------
# ARM A sees a backing exists (approve present) and stays silent; ARM B rules the
# outcome malformed. The two never double-report the same bead.
anchors "$(anchor a-x "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\"")"
reviews "$(rbead r-x closed a-x approve moot codex "$OID")"
approvals 101 '[]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a green marker over a malformed approve backing errors"
has "$OUT" "1 finding(s)" "it is reported once, not double-counted across arms"
has "$OUT" "gc.outcome" "the single finding is ARM B's outcome-coherence one"

# --- T3. a malformed backing with NO marker is caught markerlessly by ARM B --------
# In the markerless future gate-ensure will not write a marker at all; ARM B must
# still catch a malformed backing lane-state would derive green from.
anchors "$(anchor a-y "$GATING")"
reviews "$(rbead r-y closed a-y approve moot codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a malformed backing with no green marker is still caught by the outcome arm"
has "$OUT" "a-y" "the anchor is named even with no marker present"

echo "== fail-closed, suspended, executable =="

# --- fail-CLOSED ------------------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
anchors "$(anchor a-1 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\"")"; reviews "$(rbead r-1 closed a-1 approve moot codex "$OID")"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns rather than clearing the finding"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.anchors.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable anchor listing warns"
anchors "$(anchor a-1 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green\"")"
printf 'not json' > "$TMP/stores/alpha.reviews.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable review listing warns rather than clearing every backing"

# --- suspended rigs are skipped, not scanned --------------------------------------
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
anchors "$(anchor a-1 "$GATING,\"check.codex\":\"green\"")"; reviews "$(rbead r-1 closed a-1 approve moot codex "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped rather than queried"
has "$OUT" "suspended" "the skip is reported as a note"

# --- the check ships executable ---------------------------------------------------
if [ -x "$CHECK" ]; then ok "run.sh ships with its execute bit"; else bad "run.sh ships with its execute bit"; fi

echo
echo "check-gate-marker-provenance: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
