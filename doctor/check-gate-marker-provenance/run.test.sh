#!/usr/bin/env bash
# Hermetic test for doctor/check-gate-marker-provenance (I7 depth). Stubs gc, bd
# and gh; the rig checkout is a real throwaway git repo so the origin parse runs
# against the real tool. The bd stub honours --status/--all the way bd does, so a
# resolver that forgot --all cannot pass: 518 of 525 review beads in the live
# store are closed, and an open-only index would clear nothing.
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
  *) exit 0 ;;
esac
GC

# Models the two filters this check depends on. --status open serves the anchor
# file; --all serves every review bead; asking for reviewed_oid WITHOUT --all
# serves only the open ones, which is what bd itself would do.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
db=""; key=""; status=""; all=0; prev=""
for a in "$@"; do
  case "$prev" in --db) db="$a" ;; --has-metadata-key) key="$a" ;; --status|-s) status="$a" ;; esac
  [ "$a" = "--all" ] && all=1
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
case "$key" in
  merge_result) f="$STORES/$name.anchors.json" ;;
  reviewed_oid) f="$STORES/$name.reviews.json" ;;
  *) printf '[]'; exit 0 ;;
esac
[ -f "$f" ] || { printf '[]'; exit 0; }
if [ "$key" = "reviewed_oid" ] && [ "$all" -eq 0 ]; then
  jq -c '[.[] | select(.status != "closed")]' "$f"; exit 0
fi
if [ "$key" = "merge_result" ] && [ -n "$status" ] && [ "$status" != "all" ]; then
  jq -c --arg s "$status" '[.[] | select(.status == $s)]' "$f"; exit 0
fi
cat "$f"
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
# rbead <id> <status> <anchor> <oid>
rbead() { printf '{"id":"%s","status":"%s","metadata":{"task_kind":"review","anchor_bead":"%s","reviewed_oid":"%s"}}' "$1" "$2" "$3" "$4"; }
approvals() { printf '%s' "$2" > "$TMP/gh/reviews_$1.json"; }

OID=0123456789abcdef0123456789abcdef01234567
OTHER=fedcba9876543210fedcba9876543210fedcba98
GATING='"merge_result":"pull_request","check_set":"codex","branch":"b"'
reviews ""

# --- 1. RESOLVE A clears a green marker ------------------------------------------
anchors "$(anchor a-1 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green@$OID\"")"
reviews "$(rbead r-1 closed a-1 "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a green marker bound by a review bead at the same oid passes"
has "$OUT" "OK:" "the pass message is the OK line"
eq "$(wc -l < "$GH_LOG")" "0" "RESOLVE A costs no GitHub call"

# --- 2. the review bead must be found even though it is CLOSED ----------------------
# Guard mutation: the same fixture with the bead OPEN must also pass, so the
# closed case above is proving --all and not merely proving the join.
reviews "$(rbead r-1 open a-1 "$OID")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open review bead resolves too (the join itself is sound)"

# --- 3. no evidence anywhere is an ERROR ---------------------------------------------
reviews "$(rbead r-2 closed a-1 "$OTHER")"
approvals 101 '[]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a green marker no review bead and no approval covers is an ERROR"
has "$OUT" "a-1" "the unbacked anchor is named"
has "$OUT" "nothing reviewed" "the finding says what is missing"
eq "$(wc -l < "$GH_LOG")" "1" "RESOLVE B is consulted only for what A left over"

# --- 4. RESOLVE B: an approval AT the marker oid clears it ------------------------------
approvals 101 "[{\"state\":\"APPROVED\",\"commit_id\":\"$OID\"}]"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a head-bound GitHub approval at the marker oid clears it"

# --- 5. RESOLVE B compares the APPROVAL'S OWN oid, never \"the PR is approved\" ----------
# tk-4yl2c: approval here is not head-bound, so an approval at an earlier commit
# survives later pushes and must not clear the marker at the new head.
approvals 101 "[{\"state\":\"APPROVED\",\"commit_id\":\"$OTHER\"},{\"state\":\"CHANGES_REQUESTED\",\"commit_id\":\"$OID\"}]"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an approval at a DIFFERENT commit does not clear the marker"
has "$OUT" "no approval on PR 101 sits at that commit" "the finding says the approval was not head-bound"
# and a non-APPROVED review at the right oid is not evidence either
approvals 101 "[{\"state\":\"COMMENTED\",\"commit_id\":\"$OID\"}]"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a COMMENTED review at the marker oid is not an approval"

# --- 6. FILTER 1: a review bead carrying its own green marker is not an anchor ---------
anchors "$(anchor a-2 "$GATING,\"task_kind\":\"review\",\"pr_number\":\"102\",\"check.codex\":\"green@$OID\"")"
reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "a task_kind=review bead is skipped, not treated as an unbacked anchor"
hasnt "$OUT" "a-2" "the review bead is not reported"

# --- 7. undetermined, not cleared and not an error --------------------------------------
anchors "$(anchor a-3 "$GATING,\"check.codex\":\"green@$OID\"")"
reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unbacked marker on an anchor with no pr_number is a WARNING"
has "$OUT" "UNDETERMINED" "the warning says the verdict could not be determined"

anchors "$(anchor a-4 "$GATING,\"pr_number\":\"404\",\"check.codex\":\"green@$OID\"")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a failed PR review query is a WARNING, never a pass"
has "$OUT" "could not be read" "the warning names the unread review list"

anchors "$(anchor a-5 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green@$OID\"")"
approvals 101 "[{\"state\":\"APPROVED\",\"commit_id\":\"$OID\"}]"
OUT=$(GH_ABSENT=1 run_check); RC=$?
eq "$RC" "1" "an unusable gh is a WARNING, never a pass"

git -C "$TMP/alpha" remote set-url origin https://gitlab.example/acme/alpha.git
OUT=$(run_check); RC=$?
eq "$RC" "1" "a non-github origin leaves RESOLVE B unavailable — WARNING"
git -C "$TMP/alpha" remote set-url origin https://github.com/acme/alpha.git

# --- 8. one GitHub call per PR, not one per gate ------------------------------------------
anchors "$(anchor a-6 "$GATING,\"check_set\":\"codex,other\",\"pr_number\":\"101\",\"check.codex\":\"green@$OID\",\"check.other\":\"green@$OID\"")"
reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "two gates on one approved head both clear"
eq "$(sort -u "$GH_LOG" | wc -l)" "1" "the PR review list is fetched once and reused"

# --- 8b. a PAGINATED review list is flattened before the oid is looked for -------------
# gh api --paginate emits one array per page; the approval can land on any page.
anchors "$(anchor a-6b "$GATING,\"pr_number\":\"103\",\"check.codex\":\"green@$OID\"")"
reviews ""
printf '[{"state":"APPROVED","commit_id":"%s"}]\n[{"state":"APPROVED","commit_id":"%s"}]\n' "$OTHER" "$OID" > "$TMP/gh/reviews_103.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an approval on the SECOND page of reviews still clears the marker"

# --- 9. out of scope -----------------------------------------------------------------------
anchors "$(anchor a-7 "\"merge_result\":\"abandoned\",\"check.codex\":\"green@$OID\"")" \
        "$(anchor a-8 "\"merge_result\":\"merged\",\"check.codex\":\"green@$OID\"")" \
        "$(anchor a-9 "$GATING,\"check.codex\":\"fixable@$OID\"")" \
        "$(anchor a-10 "$GATING,\"check.codex\":\"exception@$OID\"")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "non-gating states and non-green verdicts carry no provenance obligation"

# A malformed marker belongs to check-gate-integrity (I7 surface); this check
# must not restate it as a provenance finding.
anchors "$(anchor a-11 '"merge_result":"pull_request","check_set":"codex","branch":"b","check.codex":"green@abc123"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a malformed marker is left to check-gate-integrity, not double-reported"

# Sidecar keys are prose about a gate, not markers.
anchors "$(anchor a-12 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green@$OID\",\"check.codex.reason\":\"green@$OTHER is prose\"")"
approvals 101 "[{\"state\":\"APPROVED\",\"commit_id\":\"$OID\"}]"
OUT=$(run_check); RC=$?
eq "$RC" "0" "check.<g>.<sidecar> keys are not treated as markers"

# --- 10. fail-CLOSED -------------------------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
anchors "$(anchor a-13 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green@$OID\"")"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.anchors.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable anchor listing warns"
anchors "$(anchor a-13 "$GATING,\"pr_number\":\"101\",\"check.codex\":\"green@$OID\"")"
printf 'not json' > "$TMP/stores/alpha.reviews.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable review index warns rather than clearing every marker"

# --- 11. the quiet path stays quiet ------------------------------------------------------------
anchors ""
reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store with no gating anchors passes silently"
anchors "$(anchor a-14 '"merge_result":"pull_request","check_set":"none","branch":"b"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a gating anchor carrying no green marker passes"

# --- 12. suspended rigs are skipped, not scanned -------------------------------------------------
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
anchors "$(anchor a-15 "$GATING,\"check.codex\":\"green@$OID\"")"
reviews ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped rather than queried"
has "$OUT" "suspended" "the skip is reported as a note"

# --- 13. the check ships executable ------------------------------------------------
# Every case above runs the check through bash, which ignores the mode bit. The
# doctor runner executes the script path itself, so a run.sh committed 100644
# fails with permission denied.
if [ -x "$CHECK" ]; then ok "run.sh ships with its execute bit"; else bad "run.sh ships with its execute bit"; fi

echo
echo "check-gate-marker-provenance: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
