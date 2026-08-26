#!/usr/bin/env bash
# Hermetic test for assets/scripts/signoff.sh — the single gate-verdict writer.
# Stubbed gc/gh/git; no live city, Dolt, network, or PRs. Ports the load-bearing
# assertions of the retired signoff-round-cap and first-round-review-body
# suites: the cap writes exception EXACTLY ONCE and never also unsets the
# marker; the posted artifact carries the anchor link; --approve is NEVER used.
# Also covers the triage widening (monotonic union, closed menu, per-gate
# justification, waiver warrants) and the escalate verdict.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/signoff.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"

cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
STORE="${STUB_STORE:?}"; DEPS="${STUB_DEPS:?}"
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
[ "${1:-}" = "bd" ] || exit 0
shift
bead_json() { jq -c --arg id "$1" '[.[] | select(.id == $id)]' "$STORE"; }
case "${1:-}" in
  show)
    out=$(bead_json "$2")
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      echo '{"error":"no issues found"}'
    else printf '%s\n' "$out"; fi ;;
  update)
    shift; id="$1"; shift
    if [ -n "${STUB_UPD_FAIL:-}" ] && grep -qx "$id" "$STUB_UPD_FAIL" 2>/dev/null; then
      echo "bd: denied (stub)" >&2; exit 1
    fi
    tmp=$(mktemp); cp "$STORE" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
            'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
        --unset-metadata) shift
          jq -c --arg id "$id" --arg k "$1" \
            'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
        --append-notes) shift
          jq -c --arg id "$id" --arg n "$1" \
            'map(if .id == $id then .notes = ((.notes // "") + "\n" + $n) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
        --status=*) st="${1#--status=}"
          jq -c --arg id "$id" --arg s "$st" \
            'map(if .id == $id then .status = $s else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
      shift || true
    done
    mv "$tmp" "$STORE"; echo "updated $id" ;;
  create)
    shift; title="$1"
    [ -n "${STUB_CREATE_FAIL:-}" ] && exit 1
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    printf '%s\n' "$title" >> "${STUB_CREATED:?}"
    tmp=$(mktemp)
    jq -c --arg id "fix-$n" '. + [{"id":$id,"status":"open","assignee":"","metadata":{},"notes":""}]' "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    printf '{"id":"fix-%s"}\n' "$n" ;;
  dep)
    shift
    # A row is "<dependent>|<blocker>|<type>", matching the real binary:
    # `dep add A B` is "A depends on B", `dep S --blocks D` is "D depends on S",
    # --direction=down lists what an id depends on and =up lists what depends
    # on it. Model these backwards and a reversed edge reads as correct.
    case "${1:-}" in
      add) printf '%s|%s|%s\n' "$2" "$3" "${4#--type=}" >> "$DEPS"; echo "dep added" ;;
      list)
        shift; id="$1"; shift
        dir=""; typ=""
        while [ $# -gt 0 ]; do
          case "$1" in --direction=*) dir="${1#--direction=}" ;; -t) shift; typ="$1" ;; esac
          shift || true
        done
        [ -n "${STUB_DEP_GARBAGE:-}" ] && { echo "not-json"; exit 0; }
        out="["
        first=1
        while IFS='|' read -r f t ty; do
          [ -n "$f" ] || continue
          [ "$ty" = "$typ" ] || continue
          other=""
          if [ "$dir" = "down" ] && [ "$f" = "$id" ]; then other="$t"; fi
          if [ "$dir" = "up" ] && [ "$t" = "$id" ]; then other="$f"; fi
          [ -n "$other" ] || continue
          row=$(jq -c --arg id "$other" '(.[] | select(.id == $id)) // {"id":$id,"metadata":{}}' "$STORE")
          [ "$first" = 1 ] || out="$out,"
          out="$out$row"; first=0
        done < "$DEPS"
        printf '%s]\n' "$out" ;;
      *)
        src="${1:-}"; shift || true
        [ -n "${STUB_DEP_NOOP:-}" ] && { echo "dep added"; exit 0; }
        [ "${1:-}" = "--blocks" ] && printf '%s|%s|blocks\n' "${2:-}" "$src" >> "$DEPS"
        echo "dep added" ;;
    esac ;;
  ready)
    # An open issue is ready when every blocker it depends on is closed.
    blocked=" "
    while IFS='|' read -r f t ty; do
      [ -n "$f" ] || continue
      [ "$ty" = "blocks" ] || continue
      st=$(jq -r --arg id "$t" 'first(.[] | select(.id == $id) | .status) // "open"' "$STORE")
      [ "$st" = "closed" ] || blocked="$blocked$f "
    done < "$DEPS"
    jq -c --arg bl "$blocked" '[ .[] | select(.status == "open")
      | select(.id as $i | ($bl | contains(" " + $i + " ")) | not) ]' "$STORE" ;;
esac
STUB

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GH_LOG:?}"
printf '%s\n' "$*" >> "${STUB_GH_ALL:?}"
case "${1:-}" in
  pr)
    case "${2:-}" in
      review)
        prev=""
        for a in "$@"; do
          [ "$prev" = "--body-file" ] && cat "$a" >> "${STUB_GH_BODY:?}"
          prev="$a"
        done ;;
      view)
        case "$*" in
          *headRefOid*) printf '%s\n' "${STUB_PR_HEAD:-}" ;;
          *autoMergeRequest*) printf '%s\n' "${STUB_AUTOMERGE_JSON:-}" ;;
        esac ;;
    esac ;;
  api)
    case "$*" in
      *" user "*) printf '%s\n' "${STUB_LOGIN:-city-bot}" ;;
      *"/reviews?"*) [ -n "${STUB_REVIEWS:-}" ] && printf '%s\n' "$STUB_REVIEWS" ;;
    esac ;;
esac
exit 0
STUB

cat > "$BIN/git" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "ls-remote" ]; then
  [ -n "${STUB_LSREMOTE:-}" ] && printf '%s\trefs/heads/%s\n' "$STUB_LSREMOTE" "${3#refs/heads/}"
  exit 0
fi
exit 0
STUB
chmod +x "$BIN/gc" "$BIN/gh" "$BIN/git"
export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/store.json" STUB_DEPS="$TMP/deps" STUB_GC_LOG="$TMP/gc.log"
export STUB_GH_LOG="$TMP/gh.log" STUB_GH_BODY="$TMP/gh.body" STUB_CREATED="$TMP/created"
export STUB_SEQ="$TMP/seq" STUB_UPD_FAIL="$TMP/updfail" STUB_GH_ALL="$TMP/gh.all"
export STUB_LSREMOTE="aaa111" STUB_AUTOMERGE_JSON='{"autoMergeRequest":null}'
: > "$STUB_GH_ALL"
unset GC_RIG GC_MAX_REVIEW_ROUNDS 2>/dev/null || true

ANCHOR_PR='{"id":"tk-anc","status":"open","assignee":"","metadata":{"branch":"polecat/tk-1","target":"main","merged_target":"main","pr_number":"42","pr_url":"https://github.com/o/r/pull/42"},"notes":""}'
ANCHOR_PRE='{"id":"tk-anc","status":"open","assignee":"","metadata":{"branch":"polecat/tk-1","target":"main"},"notes":""}'
REVIEW='{"id":"rv-1","status":"in_progress","assignee":"pool/x","metadata":{"check_name":"codex","anchor_bead":"tk-anc","fix_target_pool":"rig/gc-toolkit.polecat"},"notes":"VERDICT body: findings here"}'

reset() { # $1 = anchor json, extra beads appended via $2
  printf '[%s,%s%s]' "$1" "$REVIEW" "${2:-}" > "$STUB_STORE"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_GH_LOG"; : > "$STUB_GH_BODY"
  : > "$STUB_CREATED"; : > "$STUB_UPD_FAIL"; printf '0' > "$STUB_SEQ"
}
meta()   { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
status() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .status) // "<absent>"' "$STUB_STORE"; }
notes()  { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STUB_STORE"; }

# --- approve, post-open --------------------------------------------------------
echo "# approve post-open"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 0 "approve exits 0"
has "$(cat "$STUB_GH_LOG")" "pr review 42 --repo github.com/o/r --comment" "artifact posted as a pinned COMMENT"
has "$(cat "$STUB_GH_BODY")" "tk-anc" "the posted body carries the anchor link"
has "$(cat "$STUB_GH_BODY")" "VERDICT body: findings here" "the posted body carries the verdict notes"
eq "$(meta tk-anc check.codex)" "green@aaa111" "check.codex stamped green at the live head"
eq "$(status rv-1)" "closed" "review bead closed"
eq "$(meta rv-1 gc.outcome)" "recorded" "review bead closed with gc.outcome=recorded"

echo "# approve pre-open"
reset "$ANCHOR_PRE"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 0 "pre-open approve exits 0"
hasnt "$(cat "$STUB_GH_LOG")" "pr review" "pre-open posts no gh pr review (no PR yet)"
eq "$(meta rv-1 reviewed_oid)" "aaa111" "pre-open records reviewed_oid on the review bead"
has "$(notes rv-1)" "tk-anc" "pre-open verdict notes carry the anchor link"
eq "$(meta tk-anc check.codex)" "green@aaa111" "pre-open still stamps the marker"
eq "$(status rv-1)" "closed" "pre-open closes the review bead"

echo "# --reviewed-oid override"
reset "$ANCHOR_PR"
"$SUT" --review-bead rv-1 --verdict approve --reviewed-oid beef01 >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "green@beef01" "the override pins the stamped oid"

echo "# a dispatch-pinned reviewed_oid wins over a moved live head"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "rv-1" then .metadata.reviewed_oid = "ccc111" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
STUB_LSREMOTE="moved222" "$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 0 "pinned-oid approve exits 0"
eq "$(meta tk-anc check.codex)" "green@ccc111" "green is stamped at the PINNED oid, not the moved live head (merge then holds on head mismatch)"

echo "# …and the explicit --reviewed-oid flag still outranks the bead pin"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "rv-1" then .metadata.reviewed_oid = "ccc111" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
"$SUT" --review-bead rv-1 --verdict approve --reviewed-oid beef02 >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "green@beef02" "the flag outranks the dispatch pin"

echo "# notes-file body"
reset "$ANCHOR_PR"
printf 'P2: nit at foo.sh:3\n' > "$TMP/notes"
"$SUT" --review-bead rv-1 --verdict approve --notes-file "$TMP/notes" >/dev/null 2>&1
has "$(cat "$STUB_GH_BODY")" "P2: nit at foo.sh:3" "--notes-file body reaches the artifact"

# --- fail-closed refusals ------------------------------------------------------
echo "# refusals"
reset "$ANCHOR_PR"
printf '[%s]' "$REVIEW" | jq -c 'map(.metadata |= del(.anchor_bead))' > "$STUB_STORE"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 1 "no anchor (no metadata, no edge) refuses"
hasnt "$(cat "$STUB_GC_LOG")" "update" "the refusal wrote nothing"

reset "$ANCHOR_PR"
STUB_LSREMOTE="" "$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 1 "no live head and no --reviewed-oid refuses"

reset "$ANCHOR_PR"
printf '[%s,%s]' "${ANCHOR_PR/https:\/\/github.com\/o\/r\/pull\/42/not-a-url}" "$REVIEW" > "$STUB_STORE"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 1 "post-open with no parseable pr_url refuses (unpinned gh calls)"

echo "# anchor resolves via the blocks edge when metadata is absent"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "rv-1" then (.metadata |= del(.anchor_bead)) else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
printf 'tk-anc|rv-1|blocks\n' > "$STUB_DEPS"
"$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 0 "edge-resolved anchor accepted"
eq "$(meta tk-anc check.codex)" "green@aaa111" "marker landed on the edge-resolved anchor"

echo "# marker read-back failure"
reset "$ANCHOR_PR"
printf 'tk-anc\n' > "$STUB_UPD_FAIL"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 2 "a marker that does not stick exits 2"
eq "$(status rv-1)" "in_progress" "the review bead is NOT closed over an unrecorded gate"

# --- request-changes, under the cap ---------------------------------------------
echo "# request-changes under cap"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "tk-anc" then .metadata["check.codex"] = "green@old000" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes exits 0"
eq "$(meta tk-anc check.codex)" "<absent>" "the green marker is cleared"
has "$(cat "$STUB_GH_LOG")" "--comment" "the changes artifact is a comment"
hasnt "$(cat "$STUB_GH_LOG")" "--request-changes" "never a blocking GitHub review"
eq "$(cat "$STUB_CREATED")" "Rework PR#42: address signoff findings" "exactly one rework child, PR-titled"
eq "$(meta fix-1 branch)" "polecat/tk-1" "child resumes the anchor's branch"
eq "$(meta fix-1 target)" "main" "child carries the landing target"
eq "$(meta fix-1 source_review_bead)" "rv-1" "child names the source review"
eq "$(meta fix-1 merge_strategy)" "mr" "child stays on the PR path"
eq "$(meta fix-1 existing_pr)" "https://github.com/o/r/pull/42" "child reworks THIS PR, not a fresh one"
eq "$(meta fix-1 pr_number)" "42" "child carries the PR number"
eq "$(meta fix-1 gc.routed_to)" "rig/gc-toolkit.polecat" "child routed to the fix pool (stamp, not sling)"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "stamp-don't-sling: no gc sling issued"
has "$(cat "$STUB_DEPS")" "tk-anc|fix-1|blocks" "child blocks the anchor"
has "$(gc bd ready --json)" '"id":"fix-1"' "the rework child is in bd ready"
hasnt "$(gc bd ready --json)" '"id":"tk-anc"' "the anchor waits on the child, not the reverse"
has "$(meta fix-1 rejection_reason)" "signoff requested changes" "rejection_reason carries the round context"
eq "$(status rv-1)" "closed" "review bead closed after the dispatch"

echo "# pre-open request-changes"
reset "$ANCHOR_PRE"
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1; rc=$?
eq "$rc" 0 "pre-open request-changes exits 0"
eq "$(cat "$STUB_CREATED")" "Rework branch polecat/tk-1: address pre-open signoff findings" "pre-open child is branch-titled"
eq "$(meta fix-1 existing_pr)" "<absent>" "pre-open child carries no PR fields"

echo "# incomplete child work order is exit 2, review stays open"
reset "$ANCHOR_PR"
printf 'fix-1\n' > "$STUB_UPD_FAIL"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "an unstamped child work order exits 2"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

echo "# a child whose blocks edge did not land is caught, not shipped"
reset "$ANCHOR_PR"
out=$(STUB_DEP_NOOP=1 "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a child with no blocks edge exits 2"
has "$out" "blocks_edge" "the refusal names the missing edge"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

# --- the round cap ---------------------------------------------------------------
kid() { printf ',{"id":"c%s","status":"%s","assignee":"","metadata":{%s},"notes":""}' "$1" "$2" "$3"; }
seed_cap_deps() { for c in "$@"; do printf 'tk-anc|%s|blocks\n' "$c" >> "$STUB_DEPS"; done; }

echo "# round cap trips at 3 (default)"
reset "$ANCHOR_PR" "$(kid 1 closed '"source_review_bead":"r1"')$(kid 2 closed '"source_review_bead":"r2"')$(kid 3 open '"source_review_bead":"r3"')"
seed_cap_deps c1 c2 c3
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "the cap path exits 0"
eq "$(meta tk-anc check.codex)" "exception@aaa111" "the cap records exception@<head>"
eq "$(grep -c -- 'check.codex=exception@' "$STUB_GC_LOG")" "1" "exception is written EXACTLY once"
hasnt "$(cat "$STUB_GC_LOG")" "--unset-metadata check.codex" "the cap never ALSO unsets the marker"
eq "$(meta tk-anc gc.routed_to)" "human" "the anchor is routed to a human"
has "$(meta tk-anc blocked_reason)" "did not converge" "blocked_reason says why it is held"
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "0" "no rework child is filed past the cap"
eq "$(status rv-1)" "closed" "the review bead still closes (verdict recorded)"

echo "# only rework children count as rounds"
reset "$ANCHOR_PR" "$(kid 1 open '"source_review_bead":"r1"')$(kid 2 open '')$(kid 3 open '"branch":"x"')"
seed_cap_deps c1 c2 c3
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "non-rework children do not inflate the count (child filed)"

echo "# cap is tunable via GC_MAX_REVIEW_ROUNDS"
reset "$ANCHOR_PR" "$(kid 1 open '"source_review_bead":"r1"')"
seed_cap_deps c1
GC_MAX_REVIEW_ROUNDS=1 "$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "exception@aaa111" "GC_MAX_REVIEW_ROUNDS=1 trips at 1"

echo "# dispatch_count.<gate> on the ANCHOR (gate-ensure's writer) also counts"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "tk-anc" then .metadata["dispatch_count.codex"] = "4" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "exception@aaa111" "anchor dispatch_count.<gate> past the cap trips it with no children"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "rv-1" then .metadata["dispatch_count.codex"] = "4" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "a stray dispatch_count on the REVIEW bead does not cap (wrong writer)"

echo "# the counter is per gate: another gate's rounds never cap this one"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "tk-anc" then .metadata["dispatch_count.arch"] = "9" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "<absent>" "arch's spent rounds do not cap codex"
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "…and codex still files its rework child"
eq "$(meta fix-1 check_name)" "codex" "the rework child names the gate whose findings it answers"

echo "# rework children are counted per gate too"
reset "$ANCHOR_PR" "$(printf ',{"id":"c1","status":"closed","assignee":"","metadata":{"source_review_bead":"r1","check_name":"arch"},"notes":""}')$(printf ',{"id":"c2","status":"closed","assignee":"","metadata":{"source_review_bead":"r2","check_name":"arch"},"notes":""}')$(printf ',{"id":"c3","status":"open","assignee":"","metadata":{"source_review_bead":"r3","check_name":"arch"},"notes":""}')"
printf 'c1|tk-anc|blocks\nc2|tk-anc|blocks\nc3|tk-anc|blocks\n' > "$STUB_DEPS"
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "<absent>" "three arch rework rounds do not cap the codex gate"
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "…and codex files its first child"

echo "# an unreadable dep list never caps"
reset "$ANCHOR_PR"
STUB_DEP_GARBAGE=1 "$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "garbage dep list reads as 0 rounds (child filed, no cap)"

# --- supersede-dismiss -----------------------------------------------------------
echo "# supersede: dismiss own stale CHANGES_REQUESTED only"
reset "$ANCHOR_PR"
export STUB_PR_HEAD="aaa111"
export STUB_REVIEWS='{"id":111,"user":{"login":"city-bot"},"state":"CHANGES_REQUESTED","commit_id":"old000"}
{"id":222,"user":{"login":"a-human"},"state":"CHANGES_REQUESTED","commit_id":"old000"}
{"id":333,"user":{"login":"city-bot"},"state":"CHANGES_REQUESTED","commit_id":"aaa111"}'
"$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1
has "$(cat "$STUB_GH_LOG")" "reviews/111/dismissals" "own stale CHANGES_REQUESTED is dismissed"
hasnt "$(cat "$STUB_GH_LOG")" "reviews/222/dismissals" "a human's block is NEVER dismissed"
hasnt "$(cat "$STUB_GH_LOG")" "reviews/333/dismissals" "a block at the reviewed commit stands"
eq "$(meta tk-anc signoff_dismissed)" "111@aaa111" "signoff_dismissed pairs the retraction"

echo "# supersede holds on a moved head"
reset "$ANCHOR_PR"
STUB_PR_HEAD="bbb222" "$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1
hasnt "$(cat "$STUB_GH_LOG")" "dismissals" "a moved head keeps the block"

echo "# supersede holds while auto-merge is armed"
reset "$ANCHOR_PR"
STUB_AUTOMERGE_JSON='{"autoMergeRequest":{"enabledAt":"x"}}' "$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1
hasnt "$(cat "$STUB_GH_LOG")" "dismissals" "armed auto-merge blocks the dismissal"
unset STUB_PR_HEAD STUB_REVIEWS

# --- triage: the check_set widening ------------------------------------------------
# The charter is a FIXTURE, reached through GC_PACK_DIR (first rung of
# signoff.sh's ladder), so these cases never read the repo's own menu.
mkdir -p "$TMP/pack/docs"
cat > "$TMP/pack/docs/review-charter.md" <<'CHARTER'
# Fixture charter

| Gate | Applies when | Method | Mandatory paths | Waivable |
|---|---|---|---|---|
| `codex` | always | `formulas/mol-review.toml` | `-` | no |
| `triage` | always | `skills/review-triage/SKILL.md` | `-` | no |
| `arch` | layer changes | `skills/arch-review/SKILL.md` | `lifecycle/**` `assets/scripts/merge.sh` | no |
| `demo` | operator-visible | `skills/demo-capture/SKILL.md` | `-` | yes |
CHARTER
export GC_PACK_DIR="$TMP/pack"

REVIEW_TRIAGE='{"id":"rv-t","status":"in_progress","assignee":"pool/x","metadata":{"check_name":"triage","anchor_bead":"tk-anc","fix_target_pool":"rig/gc-toolkit.polecat"},"notes":"triage body"}'
setcs() { jq -c --arg v "$1" 'map(if .id == "tk-anc" then .metadata.check_set = $v else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"; }

echo "# triage widens check_set and records why"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex,triage"
out=$("$SUT" --review-bead rv-t --verdict approve --add-gates arch --justification "diff rewrites merge.sh" 2>&1); rc=$?
eq "$rc" 0 "an approve carrying --add-gates exits 0"
eq "$(meta tk-anc check_set)" "codex,triage,arch" "the added gate is unioned into check_set"
eq "$(meta tk-anc check.triage)" "green@aaa111" "triage's own gate goes green at the reviewed commit"
has "$(notes tk-anc)" "triage-add: arch @aaa111 — diff rewrites merge.sh" "one justification line per added gate lands on the anchor"
eq "$(status rv-t)" "closed" "the triage review bead closes"
has "$out" "check_set now codex,triage,arch" "the summary names the new set"

echo "# widening is a UNION — it can never drop a declared gate"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex,triage,demo"
"$SUT" --review-bead rv-t --verdict approve --add-gates arch --justification "why" >/dev/null 2>&1
eq "$(meta tk-anc check_set)" "codex,triage,demo,arch" "every previously declared gate survives the widen"

echo "# re-running the same widen is a no-op, not a duplicate"
"$SUT" --review-bead rv-t --verdict approve --add-gates arch --justification "why" >/dev/null 2>&1
eq "$(meta tk-anc check_set)" "codex,triage,demo,arch" "an already-declared gate is not appended twice"

echo "# a whitespace-padded check_set still splits per gate"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex, triage"
"$SUT" --review-bead rv-t --verdict approve --add-gates arch --justification "why" >/dev/null 2>&1
eq "$(meta tk-anc check_set)" "codex,triage,arch" "the split is per gate, not one fused token"

echo "# the menu is CLOSED"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex,triage"
out=$("$SUT" --review-bead rv-t --verdict approve --add-gates telepathy --justification "vibes" 2>&1); rc=$?
eq "$rc" 1 "a gate the charter does not declare is refused"
eq "$(meta tk-anc check_set)" "codex,triage" "…and check_set is untouched"
eq "$(meta tk-anc check.triage)" "<absent>" "…and no verdict marker was written"
eq "$(status rv-t)" "in_progress" "…and the review stays open"
hasnt "$(cat "$STUB_GH_LOG")" "pr review" "…and nothing was posted"

echo "# widening needs a justification, and needs to come from triage"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex,triage"
out=$("$SUT" --review-bead rv-t --verdict approve --add-gates arch 2>&1); rc=$?
eq "$rc" 1 "--add-gates without --justification is refused"
has "$out" "not auditable" "…and says why"
out=$("$SUT" --review-bead rv-1 --verdict approve --add-gates arch --justification "x" 2>&1); rc=$?
eq "$rc" 1 "a non-triage gate may not widen the check_set"
out=$("$SUT" --review-bead rv-t --verdict request-changes --add-gates arch --justification "x" 2>&1); rc=$?
eq "$rc" 1 "--add-gates only rides an approve verdict"

echo "# the none opt-out is human-only: triage records the verdict without widening"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "none"
out=$("$SUT" --review-bead rv-t --verdict approve --add-gates arch --justification "why" 2>&1); rc=$?
eq "$rc" 0 "the verdict is still recorded"
eq "$(meta tk-anc check_set)" "none" "…and the opt-out is left alone"
eq "$(meta tk-anc check.triage)" "green@aaa111" "…and triage's marker still lands"

# --- triage: waivers, the one sanctioned narrowing ----------------------------------
echo "# a waiver is recorded for a gate the charter marks waivable"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex,triage"
out=$("$SUT" --review-bead rv-t --verdict approve --waive-gates demo --justification "docs only" 2>&1); rc=$?
eq "$rc" 0 "a waived gate exits 0"
has "$(notes tk-anc)" "triage-waive: demo @aaa111 — docs only" "the waiver is recorded on the anchor"
eq "$(meta tk-anc check_set)" "codex,triage" "a waiver never adds to check_set"
# The doctor honours a waiver only at the commit check.triage passed at, so
# the two oids have to be the same one.
eq "$(meta tk-anc check.triage)" "green@aaa111" "the waiver's oid is the one triage's own marker records"

echo "# a gate the charter does NOT mark waivable cannot be waived"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex,triage"
out=$("$SUT" --review-bead rv-t --verdict approve --waive-gates arch --justification "trust me" 2>&1); rc=$?
eq "$rc" 1 "waiving a non-waivable gate is refused"
has "$out" "does not mark 'arch' waivable" "…and names the missing warrant"
eq "$(status rv-t)" "in_progress" "…and the review stays open"

echo "# a waiver cannot remove a gate already declared"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex,triage,demo"
out=$("$SUT" --review-bead rv-t --verdict approve --waive-gates demo --justification "changed my mind" 2>&1); rc=$?
eq "$rc" 1 "waiving a declared gate is refused"
has "$out" "monotonic" "…because widening is monotonic"
eq "$(meta tk-anc check_set)" "codex,triage,demo" "…and check_set is untouched"

echo "# with no readable charter: widening is accepted, narrowing is not"
NOC="$TMP/noc/assets/scripts"
mkdir -p "$NOC"
cp "$HERE/signoff.sh" "$HERE/review-charter.sh" "$HERE/escalate.sh" "$NOC/"
chmod +x "$NOC"/*.sh
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex,triage"
out=$(GC_PACK_DIR="$TMP/noc" "$NOC/signoff.sh" --review-bead rv-t --verdict approve --add-gates arch --justification "why" 2>&1); rc=$?
eq "$rc" 0 "an unvalidated widen is accepted"
eq "$(meta tk-anc check_set)" "codex,triage,arch" "…and lands"
has "$out" "unvalidated" "…and says the menu could not be checked"
reset "$ANCHOR_PR" ",$REVIEW_TRIAGE"; setcs "codex,triage"
out=$(GC_PACK_DIR="$TMP/noc" "$NOC/signoff.sh" --review-bead rv-t --verdict approve --waive-gates demo --justification "why" 2>&1); rc=$?
eq "$rc" 1 "a waiver with no declared warrant is refused"
eq "$(meta tk-anc check.triage)" "<absent>" "…and nothing was recorded"

# --- escalate: a decision, not a defect ----------------------------------------------
echo "# escalate stamps an exception and files ONE visit"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict escalate 2>&1); rc=$?
eq "$rc" 0 "escalate exits 0"
eq "$(meta tk-anc check.codex)" "exception@aaa111" "the gate records exception at the reviewed commit"
has "$(meta tk-anc blocked_reason)" "a decision, not a defect" "the anchor says why it is held"
eq "$(jq -r '[.[] | select(.metadata.escalation_key == "gate-escalation.codex")] | length' "$STUB_STORE")" "1" "exactly one visit carries the situation key"
eq "$(jq -r 'first(.[] | select(.metadata.escalation_key == "gate-escalation.codex") | .metadata["gc.continuation_group"])' "$STUB_STORE")" "tk-anc" "the visit is grouped on the anchor"
eq "$(status rv-1)" "closed" "the review bead closes"
has "$(cat "$STUB_GH_LOG")" "--comment" "the findings are posted as a comment"
eq "$(meta tk-anc 'gc.routed_to')" "<absent>" "the anchor is not also routed: the visit is the one human door"

echo "# escalate never files a rework child"
eq "$(grep -c 'Rework PR#42' "$STUB_CREATED")" "0" "no rework child is filed for a design decision"

echo "# an escalation that cannot reach a human leaves the review open"
NOESC="$TMP/noesc/assets/scripts"
mkdir -p "$NOESC"
cp "$HERE/signoff.sh" "$HERE/review-charter.sh" "$NOESC/"
chmod +x "$NOESC"/*.sh
reset "$ANCHOR_PR"
out=$(GC_PACK_DIR="$TMP/pack" "$NOESC/signoff.sh" --review-bead rv-1 --verdict escalate 2>&1); rc=$?
eq "$rc" 2 "a missing escalate.sh exits 2"
eq "$(status rv-1)" "in_progress" "…and the review is left open for a retry"
has "$out" "NO visit was filed" "…and says no human was asked"

echo "# an unknown verdict is still refused"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict maybe 2>&1); rc=$?
eq "$rc" 1 "an undeclared verdict verb is refused"
unset GC_PACK_DIR

# --- the standing prohibition: the city never approves its own PRs ----------------
if grep -q -- '--approve' "$STUB_GH_ALL" 2>/dev/null; then
  bad "no gh invocation across this whole suite ever passed --approve"
else
  ok "no gh invocation across this whole suite ever passed --approve"
fi

echo
echo "signoff.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
