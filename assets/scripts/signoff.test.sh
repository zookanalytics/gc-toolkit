#!/usr/bin/env bash
# Hermetic test for assets/scripts/signoff.sh — the single gate-verdict writer.
# Stubbed gc/gh/git; no live city, Dolt, network, or PRs. Ports the load-bearing
# assertions of the retired signoff-round-cap and first-round-review-body
# suites: the cap writes exception EXACTLY ONCE and never also unsets the
# marker; the posted artifact carries the anchor link; --approve is NEVER used.
# It also pins what a round IS — an attempted rework child, never a review
# dispatch — and what it is counted from: the floor pr-facts.sh's record of
# operator feedback sets, written once per batch and never re-derived. The
# `reset` verb is the other way that floor moves, for the anchor whose cap
# fired before it had a PR to be commented on, and for the one whose batch was
# recorded while the park stood. Both retirements read the same discriminator:
# a live demand holds the anchor, a takeaway from a sitting that ended does not.
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
    # A read that stops working only AFTER the delete: keyed on the unset so the
    # SUT's first read of the bead still resolves. Both modes answer the same ''
    # through row_meta that a genuinely cleared key does.
    mode=$(awk -v i="$2" '$1 == i {print $2}' "${STUB_SHOW_DEAD:-/dev/null}" 2>/dev/null)
    if [ -n "$mode" ] && grep -qx "$2" "${STUB_UNSET_LOG:-/dev/null}" 2>/dev/null; then
      case "$mode" in
        garbage) printf 'not-json\n' ;;
        *)       echo '{"error":"no issues found"}' ;;
      esac
      exit 0
    fi
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
          printf '%s\n' "$id" >> "${STUB_UNSET_LOG:-/dev/null}"
          # A concurrent writer re-stamping the key loses the delete without
          # failing the call: rc 0, key untouched. Denial is STUB_UPD_FAIL.
          # A line is "<id>" to lose every unset on that bead, or "<id> <key>"
          # to lose exactly one while the rest of the write lands.
          if [ -n "${STUB_UNSET_NOOP:-}" ] &&
             { grep -qxF "$id" "$STUB_UNSET_NOOP" 2>/dev/null ||
               grep -qxF "$id $1" "$STUB_UNSET_NOOP" 2>/dev/null; }; then :
          else
            jq -c --arg id "$id" --arg k "$1" \
              'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
          fi ;;
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
  list)
    # Enough of `bd list` for the live-demand read: --status and repeated
    # --metadata-field, ANDed. STUB_LIST_FAIL models a ledger that will not
    # answer, which the discriminator must read as "held".
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "bd: list unavailable (stub)" >&2; exit 1; }
    shift
    statuses=""; fields=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --status) shift; statuses="${1:-}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
        --metadata-field=*) fields+=("${1#--metadata-field=}") ;;
      esac
      shift || true
    done
    out=$(jq -c --arg st "$statuses" '[ .[] | (.status // "open") as $b
      | select($st == "" or (($st | split(",")) | index($b))) ]' "$STORE")
    for f in ${fields[@]+"${fields[@]}"}; do
      out=$(printf '%s' "$out" | jq -c --arg k "${f%%=*}" --arg v "${f#*=}" \
        '[ .[] | select(((((.metadata // {})[$k]) // "") | tostring) == $v) ]')
    done
    printf '%s\n' "$out" ;;
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
      # The SUT asks with --jq '.merge_base_commit.sha'; serve the extracted
      # value, as the headRefOid arm above does. Empty = the compare 404'd.
      *"/compare/"*) [ -n "${STUB_COMPARE_MB:-}" ] && printf '%s\n' "$STUB_COMPARE_MB" ;;
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
# merge-base --is-ancestor: 0 ancestor, 1 not, 128 a commit git cannot resolve.
[ "${1:-}" = "merge-base" ] && exit "${STUB_MERGEBASE_RC:-0}"
exit 0
STUB
chmod +x "$BIN/gc" "$BIN/gh" "$BIN/git"
export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/store.json" STUB_DEPS="$TMP/deps" STUB_GC_LOG="$TMP/gc.log"
export STUB_GH_LOG="$TMP/gh.log" STUB_GH_BODY="$TMP/gh.body" STUB_CREATED="$TMP/created"
export STUB_SEQ="$TMP/seq" STUB_UPD_FAIL="$TMP/updfail" STUB_GH_ALL="$TMP/gh.all"
export STUB_UNSET_NOOP="$TMP/unsetnoop" STUB_UNSET_LOG="$TMP/unsetlog"
# "<id> norows|garbage": gc bd show stops resolving that id once the id
# has been unset, standing in for a read-back the store cannot answer.
export STUB_SHOW_DEAD="$TMP/showdead"
# Fixture oids are 40 lowercase hex — the grammar signoff.sh enforces before it
# stamps a marker; sha1sum mints a labelled one.
oid() { printf '%s' "$1" | sha1sum | cut -d' ' -f1; }
OID_HEAD=$(oid head); OID_OVR1=$(oid ovr1); OID_PIN=$(oid pin)
OID_OVR2=$(oid ovr2); OID_MOVED=$(oid moved); OID_NEWHEAD=$(oid newhead)
OID_OLD=$(oid old)
OID_DEAD=$(oid dead); OID_LIVE=$(oid live); OID_BASE=$(oid base)
OID_PRELIVE=$(oid prelive); OID_LIVEPIN=$(oid livepin)
OID_SHORT=$(printf '%s' "$OID_DEAD" | cut -c1-9)
export STUB_LSREMOTE="$OID_HEAD" STUB_AUTOMERGE_JSON='{"autoMergeRequest":null}'
: > "$STUB_GH_ALL"
unset GC_RIG GC_MAX_REVIEW_ROUNDS 2>/dev/null || true

ANCHOR_PR='{"id":"tk-anc","status":"open","assignee":"","metadata":{"branch":"polecat/tk-1","target":"main","merged_target":"main","pr_number":"42","pr_url":"https://github.com/o/r/pull/42"},"notes":""}'
ANCHOR_PRE='{"id":"tk-anc","status":"open","assignee":"","metadata":{"branch":"polecat/tk-1","target":"main"},"notes":""}'
REVIEW='{"id":"rv-1","status":"in_progress","assignee":"pool/x","metadata":{"check_name":"codex","anchor_bead":"tk-anc","fix_target_pool":"rig/gc-toolkit.polecat"},"notes":"VERDICT body: findings here"}'

reset() { # $1 = anchor json, extra beads appended via $2
  printf '[%s,%s%s]' "$1" "$REVIEW" "${2:-}" > "$STUB_STORE"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_GH_LOG"; : > "$STUB_GH_BODY"
  : > "$STUB_CREATED"; : > "$STUB_UPD_FAIL"; : > "$STUB_UNSET_NOOP"; printf '0' > "$STUB_SEQ"
  : > "$STUB_UNSET_LOG"; : > "$STUB_SHOW_DEAD"
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
eq "$(meta tk-anc check.codex)" "green@$OID_HEAD" "check.codex stamped green at the live head"
eq "$(status rv-1)" "closed" "review bead closed"
eq "$(meta rv-1 gc.outcome)" "recorded" "review bead closed with gc.outcome=recorded"

echo "# approve pre-open"
reset "$ANCHOR_PRE"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 0 "pre-open approve exits 0"
hasnt "$(cat "$STUB_GH_LOG")" "pr review" "pre-open posts no gh pr review (no PR yet)"
eq "$(meta rv-1 reviewed_oid)" "$OID_HEAD" "pre-open records reviewed_oid on the review bead"
has "$(notes rv-1)" "tk-anc" "pre-open verdict notes carry the anchor link"
eq "$(meta tk-anc check.codex)" "green@$OID_HEAD" "pre-open still stamps the marker"
eq "$(status rv-1)" "closed" "pre-open closes the review bead"

echo "# --reviewed-oid override"
reset "$ANCHOR_PR"
"$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_OVR1 >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "green@$OID_OVR1" "the override pins the stamped oid"

echo "# a dispatch-pinned reviewed_oid wins over a moved live head"
reset "$ANCHOR_PR"
jq -c --arg o "$OID_PIN" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
STUB_LSREMOTE="$OID_MOVED" "$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 0 "pinned-oid approve exits 0"
eq "$(meta tk-anc check.codex)" "green@$OID_PIN" "green is stamped at the PINNED oid, not the moved live head (merge then holds on head mismatch)"

echo "# …and the explicit --reviewed-oid flag still outranks the bead pin"
reset "$ANCHOR_PR"
jq -c --arg o "$OID_PIN" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
"$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_OVR2 >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "green@$OID_OVR2" "the flag outranks the dispatch pin"

echo "# the marker grammar is enforced at the writer"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict approve --reviewed-oid 8d7f0cf3c 2>&1); rc=$?
eq "$rc" 1 "an abbreviated sha refuses — it would mint a marker no live head can match"
eq "$(meta tk-anc check.codex)" "<absent>" "…and nothing was stamped"
has "$out" "requires the full 40" "…and the refusal names the grammar"

reset "$ANCHOR_PR"
UPPER=$(printf '%s' "$OID_HEAD" | tr 'a-f' 'A-F')
"$SUT" --review-bead rv-1 --verdict approve --reviewed-oid "$UPPER" >/dev/null 2>&1; rc=$?
eq "$rc" 0 "an uppercase oid is accepted"
eq "$(meta tk-anc check.codex)" "green@$OID_HEAD" "…and normalized to the lowercase grammar"

echo "# notes-file body"
reset "$ANCHOR_PR"
printf 'P2: nit at foo.sh:3\n' > "$TMP/notes"
"$SUT" --review-bead rv-1 --verdict approve --notes-file "$TMP/notes" >/dev/null 2>&1
has "$(cat "$STUB_GH_BODY")" "P2: nit at foo.sh:3" "--notes-file body reaches the artifact"

# --- the pin must still be on the branch ---------------------------------------
seed_marker() { # <value>: give the anchor a marker the refusal must not touch
  jq -c --arg v "$1" 'map(if .id == "tk-anc" then .metadata["check.codex"] = $v else . end)' \
    "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
}

echo "# a pin the branch no longer carries is refused (post-open)"
reset "$ANCHOR_PR"; seed_marker "green@old000"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict request-changes --reviewed-oid $OID_DEAD 2>&1); rc=$?
eq "$rc" 1 "a pin rebased off the branch refuses"
has "$out" "head moved" "the refusal is the phrase mol-review's failure arm keys on"
has "$out" "$OID_LIVE" "…and names the live head to re-pin at"
eq "$(meta tk-anc check.codex)" "green@old000" "the marker is untouched — no clear, no stamp"
hasnt "$(cat "$STUB_GC_LOG")" "update tk-anc" "the anchor is never written"
hasnt "$(cat "$STUB_GH_LOG")" "pr review" "no verdict posted to the PR"
eq "$(cat "$STUB_CREATED")" "" "no rework child minted from a dead pin"
eq "$(status rv-1)" "in_progress" "the review bead stays open for the re-pin"
has "$(notes rv-1)" "signoff refused a verdict at $OID_DEAD" "the refusal is recorded on the review bead"

echo "# …and the dead dispatch pin is cleared so a re-claim cannot loop on it"
reset "$ANCHOR_PR"
jq -c --arg o "$OID_DEAD" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" "$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 1 "the bead-pinned dead oid refuses too"
eq "$(meta rv-1 reviewed_oid)" "<absent>" "the dead pin is cleared; mol-review re-resolves the live head"

echo "# …but a caller's dead --reviewed-oid never clears a live dispatch pin"
reset "$ANCHOR_PR"
jq -c --arg o "$OID_LIVEPIN" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" "$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_DEAD >/dev/null 2>&1
eq "$(meta rv-1 reviewed_oid)" "$OID_LIVEPIN" "the dispatch pin the caller overrode is left alone"

echo "# approve is refused on the same terms"
reset "$ANCHOR_PR"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_DEAD 2>&1); rc=$?
eq "$rc" 1 "approve at a pin off the branch refuses"
eq "$(meta tk-anc check.codex)" "<absent>" "no green stamped for a commit the branch lost"

echo "# a branch that only GREW still binds at the reviewed commit"
reset "$ANCHOR_PR"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_DEAD" \
  "$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_DEAD 2>&1); rc=$?
eq "$rc" 0 "an ancestor pin is still evidence"
eq "$(meta tk-anc check.codex)" "green@$OID_DEAD" "green lands on the reviewed commit; merge.sh holds on the head mismatch"

echo "# an unanswerable probe never discards a round that happened"
reset "$ANCHOR_PR"
out=$(STUB_PR_HEAD="" STUB_COMPARE_MB="" \
  "$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_DEAD 2>&1); rc=$?
eq "$rc" 0 "no readable live head proceeds"
eq "$(meta tk-anc check.codex)" "green@$OID_DEAD" "…binding the pin it was handed"

echo "# pre-open falls back to git ancestry"
reset "$ANCHOR_PRE"
out=$(STUB_LSREMOTE="$OID_PRELIVE" STUB_MERGEBASE_RC=1 \
  "$SUT" --review-bead rv-1 --verdict request-changes --reviewed-oid $OID_DEAD 2>&1); rc=$?
eq "$rc" 1 "pre-open refuses a pin git says is no ancestor"
eq "$(cat "$STUB_CREATED")" "" "…and mints no rework child"
eq "$(status rv-1)" "in_progress" "…and leaves the review open"

echo "# …and an unresolvable commit is unknown, not gone"
reset "$ANCHOR_PRE"
out=$(STUB_LSREMOTE="$OID_PRELIVE" STUB_MERGEBASE_RC=128 \
  "$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_DEAD 2>&1); rc=$?
eq "$rc" 0 "git rc=128 proceeds"
eq "$(meta tk-anc check.codex)" "green@$OID_DEAD" "…and the verdict binds"

echo "# an abbreviated pin that has ALSO left the branch is refused on the grammar"
reset "$ANCHOR_PR"
jq -c --arg o "$OID_SHORT" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 1 "the grammar refusal wins when both guards would fire"
has "$out" "requires the full 40" "…and names the grammar, not the head move"
hasnt "$out" "head moved" "…because the branch probe is never reached"
eq "$(meta rv-1 reviewed_oid)" "$OID_SHORT" "a malformed pin is left for its writer, not cleared as a dead one"

# --- clearing the dead pin is the refusal's whole recovery path ------------------
# mol-review re-reads the pin on the next claim, so one that survives the clear
# sends every later claim back to the same departed commit. Both arms below leave
# it in place — one by failing the call, one by returning success and changing
# nothing — and only a read-back tells either from a clear that worked.
pin() { jq -c --arg o "$1" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"; }

echo "# a dead pin the clear could not remove is a read-back failure, not a plain refusal"
reset "$ANCHOR_PR"; seed_marker "green@keepme"; pin "$OID_DEAD"
printf 'rv-1\n' > "$STUB_UPD_FAIL"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a dispatch pin that survives the clear exits 2, not the head-moved 1"
eq "$(meta rv-1 reviewed_oid)" "$OID_DEAD" "the dead pin is still on the bead"
has "$out" "did not read back" "the refusal reports the failed clear, not a moved head"
has "$out" "--unset-metadata reviewed_oid" "…and names the manual repair"
hasnt "$(notes rv-1)" "the dispatch pin is cleared" "…and never records that the pin was cleared"
eq "$(meta tk-anc check.codex)" "green@keepme" "the gate marker is still untouched"
eq "$(cat "$STUB_CREATED")" "" "no rework child is filed"
eq "$(status rv-1)" "in_progress" "the review bead stays open so the gate stays owed"

echo "# …including when the clear reports success and the pin does not move"
reset "$ANCHOR_PR"; seed_marker "green@keepme"; pin "$OID_DEAD"
printf 'rv-1\n' > "$STUB_UNSET_NOOP"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a silently-lost clear is caught by the read-back, not by the write's exit status"
eq "$(meta rv-1 reviewed_oid)" "$OID_DEAD" "the dead pin is still on the bead"
hasnt "$(notes rv-1)" "the dispatch pin is cleared" "the bead is never told the pin was cleared"
has "$out" "did not read back" "the operator is told the clear failed"

# A read-back that cannot answer reads exactly like a key that is gone: both
# give row_meta ''. Absence only proves the clear from a row that resolved.
echo "# …and a read-back that resolves no row is unproven, not a clear"
reset "$ANCHOR_PR"; seed_marker "green@keepme"; pin "$OID_DEAD"
printf 'rv-1 norows\n' > "$STUB_SHOW_DEAD"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a read-back the store cannot answer exits 2, not the head-moved 1"
has "$out" "would not resolve" "the refusal names the unreadable bead, not a surviving pin"
has "$out" "--unset-metadata reviewed_oid" "…and still names the manual repair"
hasnt "$(notes rv-1)" "the dispatch pin is cleared" "…and never records that the pin was cleared"
eq "$(meta tk-anc check.codex)" "green@keepme" "the gate marker is untouched"
eq "$(cat "$STUB_CREATED")" "" "no rework child is filed"
eq "$(status rv-1)" "in_progress" "the review bead stays open so the gate stays owed"

echo "# …and unparseable read-back output is unproven on the same terms"
reset "$ANCHOR_PR"; seed_marker "green@keepme"; pin "$OID_DEAD"
printf 'rv-1 garbage\n' > "$STUB_SHOW_DEAD"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "unparseable read-back output exits 2"
has "$out" "would not resolve" "…on the same unproven-clear refusal"
hasnt "$(notes rv-1)" "the dispatch pin is cleared" "the bead is never told the pin was cleared"
eq "$(meta tk-anc check.codex)" "green@keepme" "the gate marker is untouched"
eq "$(status rv-1)" "in_progress" "the review bead stays open so the gate stays owed"

# --- a retired dispatch records no verdict ---------------------------------------
close_rv() { jq -c 'map(if .id == "rv-1" then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"; }

echo "# a closed review bead is refused"
reset "$ANCHOR_PR"; seed_marker "green@keepme"; close_rv
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 1 "request-changes on a closed review bead is refused"
eq "$(cat "$STUB_CREATED")" "" "a retired dispatch files no rework child"
eq "$(meta tk-anc check.codex)" "green@keepme" "a retired dispatch clears no marker"
has "$out" "already closed" "the refusal says why"

echo "# …and approve on a closed review bead writes no marker either"
reset "$ANCHOR_PRE"; close_rv
"$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 1 "approve on a closed review bead is refused"
eq "$(meta tk-anc check.codex)" "<absent>" "no green is stamped for a retired dispatch"

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
eq "$(meta tk-anc check.codex)" "green@$OID_HEAD" "marker landed on the edge-resolved anchor"

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
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "the cap records exception@<head>"
eq "$(grep -c -- 'check.codex=exception@' "$STUB_GC_LOG")" "1" "exception is written EXACTLY once"
hasnt "$(cat "$STUB_GC_LOG")" "--unset-metadata check.codex" "the cap never ALSO unsets the marker"
eq "$(meta tk-anc gc.routed_to)" "human" "the anchor is routed to a human"
eq "$(meta tk-anc signoff_cap)" "codex@$OID_HEAD" "…and signoff_cap names the exception that park belongs to"
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
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "GC_MAX_REVIEW_ROUNDS=1 trips at 1"

echo "# dispatch_count is not a round count: reviews of one commit never cap"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "tk-anc" then .metadata.dispatch_count = "4" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "a dispatch_count past the cap with no rework children exits 0"
eq "$(meta tk-anc check.codex)" "<absent>" "…does not trip the cap"
eq "$(meta tk-anc gc.routed_to)" "<absent>" "…does not route the anchor to a human"
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "…and the first rework round is filed"
has "$(meta fix-1 rejection_reason)" "round 1" "…numbered by attempts, not by dispatches"

echo "# an unreadable dep list never caps"
reset "$ANCHOR_PR"
STUB_DEP_GARBAGE=1 "$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "garbage dep list reads as 0 rounds (child filed, no cap)"

# --- operator feedback resets the count ------------------------------------------
# The cap measures the city failing to converge against its own reviewer. A
# review the branch has never been answered against is not one of those rounds,
# so pr-facts.sh records the batch that carried it and the rounds spent before
# it become a floor this script subtracts.
spent() { # <n> [anchor-json] — n closed rework children, edged to the anchor
  local i extra=""
  for i in $(seq 1 "$1"); do extra="$extra$(kid "$i" closed "\"source_review_bead\":\"r$i\"")"; done
  reset "${2:-$ANCHOR_PR}" "$extra"
  for i in $(seq 1 "$1"); do printf 'tk-anc|c%s|blocks\n' "$i" >> "$STUB_DEPS"; done
}
anchor_meta() { # <k=v>... — stamp the anchor before the run
  local kv
  for kv in "$@"; do
    jq -c --arg k "${kv%%=*}" --arg v "${kv#*=}" \
      'map(if .id == "tk-anc" then .metadata[$k] = $v else . end)' "$STUB_STORE" > "$STUB_STORE.n"
    mv "$STUB_STORE.n" "$STUB_STORE"
  done
}

echo "# a recorded floor is subtracted: the rounds before the feedback do not cap"
spent 3
anchor_meta signoff_rounds_reset=0.5001 signoff_round_floor=3@0.5001
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "three spent rounds under a recorded floor exit 0"
eq "$(meta tk-anc check.codex)" "<absent>" "…the gate is cleared for a rework, not capped"
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "…and a rework child is filed"
has "$(meta fix-1 rejection_reason)" "round 1" "…numbered from the feedback, not from the branch"

echo "# a batch with no floor yet re-baselines, and records what the counter was"
spent 3
anchor_meta signoff_rounds_reset=0.5001
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "the cap does not fire at the batch that reset it"
eq "$(meta tk-anc signoff_round_floor)" "3@0.5001" "the floor is written, pinned to the batch it answers"
has "$(notes tk-anc)" "reset to 0 of 3 by operator feedback batch 0.5001" "the reset names its cause"
has "$(notes tk-anc)" "The 3 rework round(s) filed before" "…and what the counter was"
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "…and the released round is spent on a rework child"

echo "# …and the floor stands next verdict: re-deriving it would swallow every new round"
spent 4
anchor_meta signoff_rounds_reset=0.5001 signoff_round_floor=3@0.5001
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(meta tk-anc signoff_round_floor)" "3@0.5001" "the floor is unchanged at the same batch"
has "$(meta fix-1 rejection_reason)" "round 2" "…so the round after the reset counts as the second"

echo "# …and the cap trips again once the feedback's own rounds are spent"
spent 6
anchor_meta signoff_rounds_reset=0.5001 signoff_round_floor=3@0.5001
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "a reset buys one more budget, not an exemption"
has "$(meta tk-anc blocked_reason)" "after 3 rework rounds" "…and the reason counts from the reset"

echo "# a floor that names no batch is ignored rather than trusted"
spent 3
anchor_meta signoff_rounds_reset=0.5001 signoff_round_floor=3
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(meta tk-anc signoff_round_floor)" "3@0.5001" "the malformed floor is replaced by one bound to the batch"
eq "$(meta tk-anc check.codex)" "<absent>" "…and it did not cap on a value it could not read"

echo "# a floor whose write does not land refuses the verdict rather than mis-count"
spent 3
anchor_meta signoff_rounds_reset=0.5001
printf 'tk-anc\n' > "$STUB_UPD_FAIL"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "an unrecorded floor exits 2"
has "$out" "signoff_round_floor did not read back" "…naming the write that did not stick"
eq "$(status rv-1)" "in_progress" "…and the review bead stays open, the gate still owed"

# --- a cap that fires before the PR exists ---------------------------------------
# The release the cap is designed for is the next operator comment on the PR.
# An anchor capped pre-open has no conversation that could carry one, so the
# park it writes has to say which case it is.
echo "# a cap fired pre-open reports as pre-open and names the verb that retires it"
spent 3 "$ANCHOR_PRE"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "the pre-open cap path exits 0"
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "…and records the exception"
has "$(meta tk-anc blocked_reason)" "spent pre-open" "blocked_reason says the rounds were pre-open"
has "$(meta tk-anc blocked_reason)" "signoff.sh reset tk-anc" "…and names the verb that retires it"
has "$out" "pre-open (no PR)" "the report tells a pre-open cap from a PR one"

echo "# …while a cap on an open PR still points at the conversation that releases it"
spent 3
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
has "$(meta tk-anc blocked_reason)" "operator feedback on PR#42" "a post-open cap names the feedback that retires it"
hasnt "$(meta tk-anc blocked_reason)" "signoff.sh reset" "…and does not send a human to the verb"

# --- reset: the cap retirement a PR cannot deliver -------------------------------
# Clearing the exception by hand leaves the rounds standing, so the next pass
# recomputes the same count and re-caps. The verb writes the floor itself.
capped_pre() { # <n spent> [extra k=v]... — a pre-open anchor parked by its own cap
  local n="$1"; shift
  spent "$n" "$ANCHOR_PRE"
  anchor_meta "check.codex=exception@$OID_HEAD" "signoff_cap=codex@$OID_HEAD" \
    "gc.routed_to=human" "blocked_reason=signoff did not converge after $n rework rounds (cap 3)" "$@"
}

echo "# reset retires a pre-open cap: floor, exception, park, route and tally in one write"
capped_pre 3 dispatch_count=5 dispatch_backstop.codex=1
out=$("$SUT" reset tk-anc --reason "operator ruling: the findings were answered" --batch ruling-1 2>&1); rc=$?
eq "$rc" 0 "reset exits 0"
eq "$(meta tk-anc signoff_round_floor)" "3@ruling-1" "the floor advances to the rounds already spent"
eq "$(meta tk-anc signoff_rounds_reset)" "ruling-1" "…pinned to the same batch, so the next verdict does not move it again"
eq "$(meta tk-anc check.codex)" "<absent>" "the exception is retired"
eq "$(meta tk-anc signoff_cap)" "<absent>" "…with the stamp that claimed it"
eq "$(meta tk-anc blocked_reason)" "<absent>" "…and the reason that named it"
eq "$(meta tk-anc gc.routed_to)" "" "the human route is cleared"
eq "$(meta tk-anc dispatch_count)" "<absent>" "the dispatch tally goes with the park"
eq "$(meta tk-anc dispatch_backstop.codex)" "<absent>" "…and its backstop stamp"
has "$(notes tk-anc)" "operator ruling: the findings were answered" "the ruling is recorded on the anchor"
has "$out" "reset to 0 of 3" "…and reported"

echo "# …and the next verdict does not re-cap — the deadlock this verb exists to break"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "the verdict after a reset exits 0"
eq "$(meta tk-anc check.codex)" "<absent>" "…stamps no exception"
eq "$(meta tk-anc signoff_cap)" "<absent>" "…re-writes no park"
eq "$(meta tk-anc gc.routed_to)" "" "…and does not route the anchor back to a human"
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "…the released round is spent on a rework child"
has "$(meta fix-1 rejection_reason)" "round 1" "…numbered from the ruling"

echo "# reset writes to the anchor and to nothing else"
capped_pre 3
"$SUT" reset tk-anc --reason "operator ruling" >/dev/null 2>&1
eq "$(grep -c 'bd update' "$STUB_GC_LOG")" "1" "exactly one write"
hasnt "$(grep 'bd update' "$STUB_GC_LOG")" "rv-1" "…never to a review bead"
eq "$(status rv-1)" "in_progress" "…which is left open for the dispatch it still owes"
eq "$(cat "$STUB_GH_LOG")" "" "…and nothing is posted to GitHub"

echo "# an omitted --batch mints one, so the floor is always pinned to a batch"
capped_pre 2
"$SUT" reset tk-anc --reason "operator ruling" >/dev/null 2>&1
case "$(meta tk-anc signoff_round_floor)" in
  2@reset-*) ok "the floor names the rounds spent and a minted batch" ;;
  *)         bad "the floor names the rounds spent and a minted batch (got '$(meta tk-anc signoff_round_floor)')" ;;
esac
eq "$(meta tk-anc signoff_rounds_reset)" "$(meta tk-anc signoff_round_floor | cut -d@ -f2-)" "…and signoff_rounds_reset carries that batch"

echo "# the verb is PR-blind: a post-open cap retires the same way"
spent 3
anchor_meta "check.codex=exception@$OID_HEAD" "signoff_cap=codex@$OID_HEAD" "gc.routed_to=human"
"$SUT" reset tk-anc --reason "operator ruling" --batch ruling-pr >/dev/null 2>&1; rc=$?
eq "$rc" 0 "reset on an anchor with a PR exits 0"
eq "$(meta tk-anc check.codex)" "<absent>" "…and retires that park too"

# --- what a hold is: the demand bead, never the takeaway headline ---------------
# A sitting stamps gc.takeaway when it begins and replaces it with the outcome
# at sign-off, so the field outlives every sitting that touches an anchor. Read
# as a hold it shuts this verb permanently, and this verb is the only way back
# for an anchor whose feedback reset already fired.
demand() { # <status> — a demand bead gating tk-anc, in the store
  jq -c --arg st "$1" '. + [{"id":"dm-1","status":$st,"assignee":"",
    "metadata":{"gc.demand_for":"tk-anc","gc.routed_to":"human"},"notes":""}]' \
    "$STUB_STORE" > "$STUB_STORE.n"
  mv "$STUB_STORE.n" "$STUB_STORE"
}

echo "# a live demand outranks the ruling"
capped_pre 3 "gc.takeaway=holding — needs a ruling"
demand open
out=$("$SUT" reset tk-anc --reason "operator ruling" 2>&1); rc=$?
eq "$rc" 1 "an anchor a person still owes an answer on refuses the reset"
eq "$(meta tk-anc signoff_round_floor)" "<absent>" "…and nothing is written, not even the floor"
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "…the park stands"
has "$out" "live demand" "…and the refusal names the hold"

echo "# …but a takeaway recording a sitting that ENDED does not"
capped_pre 3 "gc.takeaway=approved as-is on GitHub; merge still held by the gate"
out=$("$SUT" reset tk-anc --reason "operator ruling" --batch ruling-3 2>&1); rc=$?
eq "$rc" 0 "a takeaway no demand backs is a record, not a hold"
eq "$(meta tk-anc signoff_round_floor)" "3@ruling-3" "…the floor advances"
eq "$(meta tk-anc check.codex)" "<absent>" "…and the park is retired"
eq "$(meta tk-anc 'gc.takeaway')" "approved as-is on GitHub; merge still held by the gate" "…while the sitting's record is left alone"

echo "# …and a demand the ruling already closed is such a sitting"
capped_pre 3 "gc.takeaway=holding — needs a ruling"
demand closed
out=$("$SUT" reset tk-anc --reason "operator ruling" --batch ruling-4 2>&1); rc=$?
eq "$rc" 0 "a closed demand holds nothing"
eq "$(meta tk-anc check.codex)" "<absent>" "…so the park is retired"

echo "# a ledger that will not answer reads as held"
capped_pre 3
out=$(STUB_LIST_FAIL=1 "$SUT" reset tk-anc --reason "operator ruling" 2>&1); rc=$?
eq "$rc" 1 "an unreadable demand ledger refuses the reset"
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "…the park stands rather than be released on a guess"

echo "# an exception no signoff_cap claims is a person's: the counter resets, the park stays"
spent 3 "$ANCHOR_PRE"
anchor_meta "check.codex=exception@$OID_HEAD" "gc.routed_to=human"
"$SUT" reset tk-anc --reason "operator ruling" --batch ruling-2 >/dev/null 2>&1; rc=$?
eq "$rc" 0 "the reset still exits 0"
eq "$(meta tk-anc signoff_round_floor)" "3@ruling-2" "the rounds are the cap's wherever the park came from"
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "…but an unclaimed exception is not this verb's to clear"
eq "$(meta tk-anc gc.routed_to)" "human" "…and the route a person is waiting on stands"
has "$(notes tk-anc)" "No park was retired" "…and the anchor records that it kept the park"

echo "# …and a signoff_cap that no longer matches the standing marker retires nothing"
spent 3 "$ANCHOR_PRE"
anchor_meta "check.codex=exception@$OID_MOVED" "signoff_cap=codex@$OID_HEAD" "gc.routed_to=human"
"$SUT" reset tk-anc --reason "operator ruling" --batch ruling-3 >/dev/null 2>&1
eq "$(meta tk-anc check.codex)" "exception@$OID_MOVED" "an exception at another oid is left alone"
eq "$(meta tk-anc signoff_cap)" "codex@$OID_HEAD" "…and the stamp that disagrees with it"

echo "# a reset that does not read back is never reported as retired"
capped_pre 3
printf 'tk-anc\n' > "$STUB_UPD_FAIL"
out=$("$SUT" reset tk-anc --reason "operator ruling" 2>&1); rc=$?
eq "$rc" 2 "a denied write exits 2"
has "$out" "did not read back" "…naming the failure"
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "…and the park still stands"

# The tally is the half of the park gate-ensure.sh reads. A reset whose floor,
# marker and route all land while one tally unset is lost releases an anchor
# nobody may dispatch, and says it retired the tally.
echo "# a tally unset that is silently lost is not a retirement"
capped_pre 3 dispatch_count=5 dispatch_backstop.codex=1
printf 'tk-anc dispatch_count\n' > "$STUB_UNSET_NOOP"
out=$("$SUT" reset tk-anc --reason "operator ruling" --batch ruling-tally 2>&1); rc=$?
eq "$rc" 2 "a lost dispatch_count unset exits 2"
has "$out" "did not read back on tk-anc (dispatch_count)" "…naming the key that still stands"
eq "$(meta tk-anc dispatch_count)" "5" "…which the anchor still carries"
hasnt "$out" "reset to 0 of" "…and the retirement is never reported"

echo "# …and a lost backstop unset is caught on the same terms"
capped_pre 3 dispatch_count=5 dispatch_backstop.codex=1
printf 'tk-anc dispatch_backstop.codex\n' > "$STUB_UNSET_NOOP"
out=$("$SUT" reset tk-anc --reason "operator ruling" --batch ruling-tally2 2>&1); rc=$?
eq "$rc" 2 "a lost backstop unset exits 2"
has "$out" "did not read back on tk-anc (dispatch_backstop.codex)" "…naming the backstop stamp"
eq "$(meta tk-anc dispatch_count)" "<absent>" "…while the tally key that did land is gone"

# The floor is written from the ledger count, so reset reads it strictly: 0 from
# a walk that glitched writes signoff_round_floor=0@<batch>, and the next
# verdict counts the real children from 0 and re-caps immediately.
echo "# a rework ledger reset cannot read refuses before it writes anything"
capped_pre 3 dispatch_count=5
out=$(STUB_DEP_GARBAGE=1 "$SUT" reset tk-anc --reason "operator ruling" --batch ruling-garbage 2>&1); rc=$?
eq "$rc" 1 "an unparseable dep listing refuses the reset"
has "$out" "rework ledger" "…naming what it could not read"
eq "$(meta tk-anc signoff_round_floor)" "<absent>" "…and writes no floor"
eq "$(meta tk-anc signoff_rounds_reset)" "<absent>" "…nor the batch it would pin it to"
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "…the park stands"
eq "$(meta tk-anc gc.routed_to)" "human" "…the human route stands"
eq "$(meta tk-anc dispatch_count)" "5" "…and the tally stands"

echo "# …and a ledger naming no round is no cap to retire"
reset "$ANCHOR_PRE"
anchor_meta "check.codex=exception@$OID_HEAD" "signoff_cap=codex@$OID_HEAD" "gc.routed_to=human"
out=$("$SUT" reset tk-anc --reason "operator ruling" 2>&1); rc=$?
eq "$rc" 1 "an anchor with no rework child refuses"
has "$out" "no rework child" "…saying so"
eq "$(meta tk-anc signoff_round_floor)" "<absent>" "…and writes nothing"
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "…retiring no park it cannot account for"

# The strict read belongs to reset alone. The cap path reads the same ledger
# leniently, and the floor it re-baselines under a broken walk is a count rather
# than the blank a strict reader would leave.
echo "# the cap path still reads that same ledger leniently"
spent 3
anchor_meta signoff_rounds_reset=0.5001
STUB_DEP_GARBAGE=1 "$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(meta tk-anc signoff_round_floor)" "0@0.5001" "a broken walk floors at 0 rounds, never at nothing"
eq "$(meta tk-anc check.codex)" "<absent>" "…and parks nothing"

echo "# reset refuses what it cannot record or cannot read"
capped_pre 3
out=$("$SUT" reset tk-anc 2>&1); rc=$?
eq "$rc" 1 "no --reason refuses"
eq "$(meta tk-anc signoff_round_floor)" "<absent>" "…and writes nothing"
has "$out" "needs --reason" "…saying what is missing"
out=$("$SUT" reset tk-nope --reason "operator ruling" 2>&1); rc=$?
eq "$rc" 1 "an anchor that does not resolve refuses"
has "$out" "does not resolve" "…saying so"
out=$("$SUT" reset --reason "operator ruling" 2>&1); rc=$?
eq "$rc" 1 "reset with no anchor refuses"
has "$out" "anchor bead id" "…rather than reading the next flag as one"
out=$("$SUT" reset tk-anc --reason "operator ruling" --verdict approve 2>&1); rc=$?
eq "$rc" 1 "reset carrying verdict flags refuses — it answers no review bead"
eq "$(meta tk-anc signoff_round_floor)" "<absent>" "…and writes nothing"
out=$("$SUT" --review-bead rv-1 --verdict approve --reason "operator ruling" 2>&1); rc=$?
eq "$rc" 1 "a verdict carrying --reason refuses"
eq "$(meta tk-anc check.codex)" "exception@$OID_HEAD" "…and stamps no marker"

# --- supersede-dismiss -----------------------------------------------------------
echo "# supersede: dismiss own stale CHANGES_REQUESTED only"
reset "$ANCHOR_PR"
export STUB_PR_HEAD="$OID_HEAD"
export STUB_REVIEWS='{"id":111,"user":{"login":"city-bot"},"state":"CHANGES_REQUESTED","commit_id":"'"$OID_OLD"'"}
{"id":222,"user":{"login":"a-human"},"state":"CHANGES_REQUESTED","commit_id":"'"$OID_OLD"'"}
{"id":333,"user":{"login":"city-bot"},"state":"CHANGES_REQUESTED","commit_id":"'"$OID_HEAD"'"}'
"$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1
has "$(cat "$STUB_GH_LOG")" "reviews/111/dismissals" "own stale CHANGES_REQUESTED is dismissed"
hasnt "$(cat "$STUB_GH_LOG")" "reviews/222/dismissals" "a human's block is NEVER dismissed"
hasnt "$(cat "$STUB_GH_LOG")" "reviews/333/dismissals" "a block at the reviewed commit stands"
eq "$(meta tk-anc signoff_dismissed)" "111@$OID_HEAD" "signoff_dismissed pairs the retraction"

echo "# supersede holds on a moved head"
reset "$ANCHOR_PR"
STUB_PR_HEAD="$OID_NEWHEAD" "$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1
hasnt "$(cat "$STUB_GH_LOG")" "dismissals" "a moved head keeps the block"

echo "# supersede holds while auto-merge is armed"
reset "$ANCHOR_PR"
STUB_AUTOMERGE_JSON='{"autoMergeRequest":{"enabledAt":"x"}}' "$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1
hasnt "$(cat "$STUB_GH_LOG")" "dismissals" "armed auto-merge blocks the dismissal"
unset STUB_PR_HEAD STUB_REVIEWS

# --- the standing prohibition: the city never approves its own PRs ----------------
if grep -q -- '--approve' "$STUB_GH_ALL" 2>/dev/null; then
  bad "no gh invocation across this whole suite ever passed --approve"
else
  ok "no gh invocation across this whole suite ever passed --approve"
fi

echo
echo "signoff.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
