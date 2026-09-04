#!/usr/bin/env bash
# Hermetic test for assets/scripts/signoff.sh — the single gate-verdict writer.
# Stubbed gc/gh/git; no live city, Dolt, network, or PRs. Ports the load-bearing
# assertions of the retired signoff-round-cap and first-round-review-body
# suites: the cap parks the anchor under merge_hold EXACTLY ONCE; the posted
# artifact carries the anchor link; --approve is NEVER used. A verdict records
# a lane state and binds to no commit, so the reviewed oid reaches the artifact
# and the review bead and nothing else, and a head that moved under the review
# refuses nothing.
# It also pins what a round IS — an attempted rework child, never a review
# dispatch — and what it is counted from: the floor pr-facts.sh's record of
# operator feedback sets, written once per batch and never re-derived. The
# `reset` verb is the other way that floor moves, for the anchor whose cap
# fired before it had a PR to be commented on, and for the one whose batch was
# recorded while the park stood. Both retirements read the same discriminator:
# a live demand holds the anchor, a takeaway from a sitting that ended does not.
# Both also take the cap's OWN takeaway with the park, and leave a sitting's,
# which gc.takeaway_by tells apart.
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
    # STUB_DROP_KEYS="id:key1,key2 id2:key" — apply the update but silently drop
    # the named keys, modelling a write that reported success and half-landed.
    drops=""
    for pair in ${STUB_DROP_KEYS:-}; do
      case "$pair" in "$id:"*) drops="${pair#*:}" ;; esac
    done
    tmp=$(mktemp); cp "$STORE" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          case ",$drops," in *",$k,"*) : ;; *)
          jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
            'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
          esac ;;
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
          # A line "<id>" in STUB_DROP_NOTES loses that bead's notes append
          # while the rest of the write lands: the notes sibling of
          # STUB_DROP_KEYS, modelling a write that reported success and
          # half-landed. Denial is STUB_UPD_FAIL.
          if grep -qxF "$id" "${STUB_DROP_NOTES:-/dev/null}" 2>/dev/null; then :
          else
            jq -c --arg id "$id" --arg n "$1" \
              'map(if .id == $id then .notes = ((.notes // "") + "\n" + $n) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
          fi ;;
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
export STUB_DROP_NOTES="$TMP/dropnotes"
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
  : > "$STUB_UNSET_LOG"; : > "$STUB_SHOW_DEAD"; : > "$STUB_DROP_NOTES"
}
meta()   { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
status() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .status) // "<absent>"' "$STUB_STORE"; }
notes()  { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STUB_STORE"; }
anchor_meta() { # <k=v>... — stamp the anchor before the run
  local kv
  for kv in "$@"; do
    jq -c --arg k "${kv%%=*}" --arg v "${kv#*=}" \
      'map(if .id == "tk-anc" then .metadata[$k] = $v else . end)' "$STUB_STORE" > "$STUB_STORE.n"
    mv "$STUB_STORE.n" "$STUB_STORE"
  done
}

# --- approve, post-open --------------------------------------------------------
echo "# approve post-open"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 0 "approve exits 0"
has "$(cat "$STUB_GH_LOG")" "pr review 42 --repo github.com/o/r --comment" "artifact posted as a pinned COMMENT"
has "$(cat "$STUB_GH_BODY")" "tk-anc" "the posted body carries the anchor link"
has "$(cat "$STUB_GH_BODY")" "VERDICT body: findings here" "the posted body carries the verdict notes"
eq "$(meta tk-anc check.codex)" "green" "check.codex records the lane green"
eq "$(status rv-1)" "closed" "review bead closed"
eq "$(meta rv-1 gc.outcome)" "recorded" "review bead closed with gc.outcome=recorded"
eq "$(meta rv-1 signoff_verdict)" "approve" "…and signoff_verdict=approve rides in the same close"

echo "# approve pre-open"
reset "$ANCHOR_PRE"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 0 "pre-open approve exits 0"
hasnt "$(cat "$STUB_GH_LOG")" "pr review" "pre-open posts no gh pr review (no PR yet)"
eq "$(meta rv-1 reviewed_oid)" "$OID_HEAD" "pre-open records reviewed_oid on the review bead"
has "$(notes rv-1)" "tk-anc" "pre-open verdict notes carry the anchor link"
eq "$(meta tk-anc check.codex)" "green" "pre-open still stamps the lane"
eq "$(status rv-1)" "closed" "pre-open closes the review bead"

echo "# --reviewed-oid override"
reset "$ANCHOR_PR"
"$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_OVR1 >/dev/null 2>&1
has "$(cat "$STUB_GH_BODY")" "$OID_OVR1" "the override names the commit in the artifact"

echo "# a dispatch-pinned reviewed_oid wins over a moved live head"
reset "$ANCHOR_PR"
jq -c --arg o "$OID_PIN" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
STUB_LSREMOTE="$OID_MOVED" "$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 0 "pinned-oid approve exits 0"
has "$(cat "$STUB_GH_BODY")" "$OID_PIN" "the artifact names the PINNED commit, not the moved live head"
eq "$(meta tk-anc check.codex)" "green" "…and the lane is green either way"

echo "# …and the explicit --reviewed-oid flag still outranks the bead pin"
reset "$ANCHOR_PR"
jq -c --arg o "$OID_PIN" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
"$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_OVR2 >/dev/null 2>&1
has "$(cat "$STUB_GH_BODY")" "$OID_OVR2" "the flag outranks the dispatch pin"

echo "# the oid is the artifact's audit trail, and holds no marker to a length"
reset "$ANCHOR_PR"
UPPER=$(printf '%s' "$OID_HEAD" | tr 'a-f' 'A-F')
"$SUT" --review-bead rv-1 --verdict approve --reviewed-oid "$UPPER" >/dev/null 2>&1; rc=$?
eq "$rc" 0 "an uppercase oid is accepted"
has "$(cat "$STUB_GH_BODY")" "$OID_HEAD" "…and normalized to lowercase in the artifact"

echo "# notes-file body"
reset "$ANCHOR_PR"
printf 'P2: nit at foo.sh:3\n' > "$TMP/notes"
"$SUT" --review-bead rv-1 --verdict approve --notes-file "$TMP/notes" >/dev/null 2>&1
has "$(cat "$STUB_GH_BODY")" "P2: nit at foo.sh:3" "--notes-file body reaches the artifact"

# --- the bead-side record of what was judged -------------------------------------
# The lane state names no commit, so check-gate-marker-provenance resolves a
# green lane only against a closed review bead that carries anchor_bead,
# reviewed_oid, check_name and signoff_verdict=approve. Nothing here ever posts
# an APPROVED GitHub review, so that bead is the only resolver a city verdict
# can reach: a marker stamped without the record is one merge.sh honours and
# nothing can account for.
seed_marker() { # <value>: give the anchor a marker a refusal must not touch
  jq -c --arg v "$1" 'map(if .id == "tk-anc" then .metadata["check.codex"] = $v else . end)' \
    "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
}

pin() { # <oid>: stand in for the reviewed_oid a dispatch pins on the review bead
  jq -c --arg o "$1" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' \
    "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
}
backed() { # <label>: a bare-green lane with a bead-side record to resolve it
  local m b
  m=$(meta tk-anc check.codex); b=$(meta rv-1 reviewed_oid)
  if [ "$b" != "<absent>" ] && [ "$m" = "green" ]; then ok "$1"
  else bad "$1 (check.codex='$m' reviewed_oid='$b')"; fi
}

echo "# post-open approve records the commit it judged"
reset "$ANCHOR_PR"; pin "$OID_PIN"
"$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1
eq "$(meta rv-1 reviewed_oid)" "$OID_PIN" "a dispatch-pinned oid stays the judged commit"
backed "…and the lane resolves against it"

echo "# …and so does the live-head fallback, which no dispatch pinned"
reset "$ANCHOR_PR"
"$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1
eq "$(meta rv-1 reviewed_oid)" "$OID_HEAD" "the fallback head is written back, not left implicit"
backed "…and the lane resolves against it"

echo "# …and so does a --reviewed-oid the caller pinned over the dispatch"
reset "$ANCHOR_PR"; pin "$OID_PIN"
"$SUT" --review-bead rv-1 --verdict approve --reviewed-oid "$OID_OVR1" >/dev/null 2>&1
eq "$(meta rv-1 reviewed_oid)" "$OID_OVR1" "the override replaces the pin with the commit actually judged"
backed "…and the lane resolves against it"

echo "# request-changes records it too, though it leaves no marker"
reset "$ANCHOR_PR"; seed_marker "green"
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1; rc=$?
eq "$rc" 0 "post-open request-changes exits 0"
eq "$(meta tk-anc check.codex)" "<absent>" "…clearing the lane rather than stamping one"
eq "$(meta rv-1 reviewed_oid)" "$OID_HEAD" "…and recording which commit the round judged, so the lane it cleared is still accountable"

echo "# a record that will not stick stamps nothing"
reset "$ANCHOR_PR"
printf 'rv-1\n' > "$STUB_UPD_FAIL"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 2 "a reviewed_oid that does not read back exits 2"
eq "$(meta tk-anc check.codex)" "<absent>" "…stamping no lane state over the missing record"
hasnt "$(cat "$STUB_GH_LOG")" "pr review" "…and posting nothing to the PR"
eq "$(status rv-1)" "in_progress" "…and leaving the review bead open for a retry"
has "$out" "did not read back on rv-1" "…naming the bead the record is owed on"

# --- pre-open, the verdict body is the bead's alone ------------------------------
# The record above says which commit was judged; the body says what the judgement
# was, and pre-open the review bead's notes are the only copy of it. pr-open.sh
# replays those notes as the new PR's first comment, and a request-changes child
# names the bead in source_review_bead and reads its findings nowhere else. So
# the append is read back on the same terms as the record: a body that did not
# land costs a re-run, not a marker or a rework child nobody can act on.
echo "# pre-open, a verdict body that did not land stamps nothing"
reset "$ANCHOR_PRE"
printf 'rv-1\n' > "$STUB_DROP_NOTES"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 2 "a pre-open body that does not read back exits 2"
eq "$(meta tk-anc check.codex)" "<absent>" "…stamping no lane state over findings nobody can read"
eq "$(status rv-1)" "in_progress" "…and leaving the review bead open for a retry"
has "$out" "did not read back on rv-1" "…naming the bead the body is owed on"
eq "$(meta rv-1 reviewed_oid)" "$OID_HEAD" "…while the record that did land stays, so the retry rebinds the same commit"

echo "# …and files no rework child against findings it could not write"
reset "$ANCHOR_PRE"
printf 'rv-1\n' > "$STUB_DROP_NOTES"
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1; rc=$?
eq "$rc" 2 "pre-open request-changes exits 2 when the body did not land"
eq "$(cat "$STUB_CREATED")" "" "…minting no rework child"
eq "$(meta tk-anc check.codex)" "<absent>" "…and clearing no lane state it did not replace"

echo "# post-open is unaffected — its artifact goes to the PR, not the bead"
reset "$ANCHOR_PR"
printf 'rv-1\n' > "$STUB_DROP_NOTES"
"$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 0 "post-open approve exits 0 with the bead's notes untouched"
eq "$(meta tk-anc check.codex)" "green" "…and stamps the lane state"

echo "# the landed body is what the check reads, not merely a non-empty note"
reset "$ANCHOR_PRE"
"$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 0 "pre-open approve exits 0 when the append lands"
has "$(notes rv-1)" "Anchor: tk-anc — check.codex @ $OID_HEAD" "the trailer the read-back keys on names anchor, check and commit"

# --- a pin the branch no longer carries ------------------------------------------
# Commits added on top keep the pin 'on' — the reviewed diff is still there,
# nothing compares a marker to a head, and the lane goes green regardless of
# what landed after. Only a REWRITE that drops the pinned commit from the
# branch's history is different: mol-review tested content nobody can merge,
# so the verdict is refused rather than recorded — no marker, no rework, no
# round spent — and the review bead closes superseded so gate-ensure pours a
# fresh review at the live head. A probe that cannot answer (unknown) proceeds
# rather than discard a review round that happened.
seed_marker() { # <value>: give the anchor a marker a refusal must not touch
  jq -c --arg v "$1" 'map(if .id == "tk-anc" then .metadata["check.codex"] = $v else . end)' \
    "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
}
pin() { jq -c --arg o "$1" 'map(if .id == "rv-1" then .metadata.reviewed_oid = $o else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"; }

echo "# a pin the branch no longer carries (gone) is refused, not recorded"
reset "$ANCHOR_PR"; seed_marker "green"; pin "$OID_PIN"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 0 "the refusal is the completed action: exit 0"
has "$out" "head moved" "…and says the head moved"
has "$out" "superseded" "…and names the disposition"
eq "$(meta tk-anc check.codex)" "green" "no marker is (re-)written; the seeded value is untouched"
eq "$(meta rv-1 reviewed_oid)" "<absent>" "the review bead's own dispatch pin is cleared"
eq "$(status rv-1)" "closed" "the review bead is closed…"
eq "$(meta rv-1 gc.outcome)" "superseded" "…as superseded, not recorded"
eq "$(cat "$STUB_GH_BODY")" "" "no artifact is posted"
hasnt "$(cat "$STUB_GH_LOG")" "pr review" "…and no PR comment goes out"

echo "# …and request-changes is refused on the same terms: no rework, no round spent"
reset "$ANCHOR_PR"; seed_marker "green"; pin "$OID_PIN"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes at a gone pin also exits 0"
eq "$(meta tk-anc check.codex)" "green" "the lane marker is untouched"
eq "$(cat "$STUB_CREATED")" "" "no rework child is filed"
eq "$(status rv-1)" "closed" "the review bead is closed…"
eq "$(meta rv-1 gc.outcome)" "superseded" "…never recorded"

echo "# commits added on top keep the pin 'on': the lane still goes green"
reset "$ANCHOR_PR"; pin "$OID_PIN"
out=$(STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_PIN" \
  "$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 0 "a pin still an ancestor of the live head is no refusal"
hasnt "$out" "head moved" "…and nothing reports a moved head"
eq "$(meta tk-anc check.codex)" "green" "the lane goes green"
eq "$(meta rv-1 reviewed_oid)" "$OID_PIN" "the dispatch pin stands — this is not a rewrite"

echo "# a probe that cannot reach the remote (unknown) proceeds"
reset "$ANCHOR_PRE"; pin "$OID_PIN"
out=$(STUB_LSREMOTE="" "$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 0 "an unanswerable probe does not discard a review round that happened"
eq "$(meta tk-anc check.codex)" "green" "…and the lane goes green"

echo "# …but a caller's dead --reviewed-oid never clears a live dispatch pin"
# The clear is the refusal's recovery path for the pin THIS verdict was bound
# to. A caller who pinned somewhere else refuses on its own oid and leaves the
# dispatch's record standing, so the re-claim still reads a live pin.
reset "$ANCHOR_PR"; pin "$OID_LIVEPIN"
STUB_PR_HEAD="$OID_LIVE" STUB_COMPARE_MB="$OID_BASE" \
  "$SUT" --review-bead rv-1 --verdict approve --reviewed-oid $OID_DEAD >/dev/null 2>&1
eq "$(meta rv-1 reviewed_oid)" "$OID_LIVEPIN" "the dispatch pin the caller overrode is left alone"

echo "# an abbreviated pin is accepted: nothing compares it to a head length-wise"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict approve --reviewed-oid 8d7f0cf3c 2>&1); rc=$?
eq "$rc" 0 "an abbreviated sha is no longer refused"
eq "$(meta tk-anc check.codex)" "green" "…and the lane goes green"
has "$(cat "$STUB_GH_BODY")" "8d7f0cf3c" "…with the artifact naming what it was given"

echo "# a non-hex oid still names no commit, and is refused"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict approve --reviewed-oid "not-an-oid" 2>&1); rc=$?
eq "$rc" 1 "a value that is no commit at all refuses"
eq "$(meta tk-anc check.codex)" "<absent>" "…and nothing was stamped"

# --- a legacy exception@<oid> park predates the migration -----------------------
# migrate-lane-states.sh rewrites exception@<oid> to merge_hold+signoff_cap
# after this cadence lands; until it runs, that marker is not lane vocabulary
# this verdict may read. Stamping green over it would silently release a park
# a human is relying on.
echo "# an approve over a legacy exception@<oid> marker refuses, not migrates"
reset "$ANCHOR_PR"; seed_marker "exception@$OID_OLD"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 2 "the legacy park refuses the verdict"
has "$out" "migrate-lane-states.sh" "…and names the migration that clears it"
eq "$(meta tk-anc check.codex)" "exception@$OID_OLD" "the legacy marker is left exactly as it stood"
eq "$(status rv-1)" "in_progress" "the review bead is left open, not recorded as approving"
eq "$(cat "$STUB_GH_BODY")" "" "no artifact is posted over an unmigrated park"

# --- a retired dispatch records no verdict ---------------------------------------
close_rv() { jq -c 'map(if .id == "rv-1" then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"; }

echo "# a closed review bead is refused"
reset "$ANCHOR_PR"; seed_marker "green"; close_rv
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 1 "request-changes on a closed review bead is refused"
eq "$(cat "$STUB_CREATED")" "" "a retired dispatch files no rework child"
eq "$(meta tk-anc check.codex)" "green" "a retired dispatch clears no marker"
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
eq "$(meta tk-anc check.codex)" "green" "the lane landed on the edge-resolved anchor"

echo "# marker read-back failure"
reset "$ANCHOR_PR"
printf 'tk-anc\n' > "$STUB_UPD_FAIL"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 2 "a marker that does not stick exits 2"
eq "$(status rv-1)" "in_progress" "the review bead is NOT closed over an unrecorded gate"

echo "# a signoff_verdict that does not read back on close is caught, not shipped"
reset "$ANCHOR_PR"
out=$(STUB_DROP_KEYS="rv-1:signoff_verdict" "$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 2 "a half-landed close exits 2"
has "$out" "did not read back" "…naming the close that did not stick"
eq "$(status rv-1)" "closed" "the status write landed even though the verdict field did not…"
eq "$(meta rv-1 signoff_verdict)" "<absent>" "…so this half-close is caught rather than trusted"

# --- request-changes, under the cap ---------------------------------------------
echo "# request-changes under cap"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "tk-anc" then .metadata["check.codex"] = "green" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
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
eq "$(meta rv-1 signoff_verdict)" "request-changes" "…and signoff_verdict=request-changes rides in the same close"

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
eq "$(meta tk-anc merge_hold)" "signoff_cap" "the cap parks the anchor under merge_hold=signoff_cap"
eq "$(meta tk-anc signoff_cap)" "codex" "…stamped with the gate whose rounds ran out"
eq "$(grep -c -- 'merge_hold=signoff_cap' "$STUB_GC_LOG")" "1" "the park is written EXACTLY once"
hasnt "$(cat "$STUB_GC_LOG")" "--unset-metadata check.codex" "the cap never ALSO unsets the marker"
eq "$(meta tk-anc gc.routed_to)" "human" "the anchor is routed to a human"
eq "$(meta tk-anc signoff_cap)" "codex" "…and signoff_cap names the gate the park belongs to"
has "$(meta tk-anc blocked_reason)" "did not converge" "blocked_reason says why it is held"
# The board spends gc.takeaway as the row's NEEDS sentence; a park that writes
# only blocked_reason reaches the operator saying no question was recorded. The
# two are not the same string: blocked_reason is the row's detail and names the
# case and the verb that retires it, which passes the board's cell, so the
# takeaway carries the headline both cases share.
eq "$(meta tk-anc gc.takeaway)" \
  "signoff did not converge after 3 rework rounds (cap 3); findings are in the review beads under this anchor" \
  "the park's takeaway is the headline the board can render"
has "$(meta tk-anc blocked_reason)" \
  "signoff did not converge after 3 rework rounds (cap 3)" \
  "…and blocked_reason opens on the same sentence before adding the detail"
eq "$(meta tk-anc gc.takeaway_by)" "signoff" "the takeaway names its writer"
has "$(meta tk-anc gc.takeaway_at)" "T" "…and stamps when the wait started"
eq "$(printf '%s' "$(meta tk-anc gc.takeaway)" | jq -Rsr 'length <= 140')" "true" \
  "the takeaway fits the 140-codepoint board cap"
eq "$(grep -c -- '--set-metadata gc.routed_to=human' "$STUB_GC_LOG")" "1" \
  "route and takeaway ride in ONE update"
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "0" "no rework child is filed past the cap"
eq "$(status rv-1)" "closed" "the review bead still closes (verdict recorded)"
eq "$(meta rv-1 signoff_verdict)" "request-changes" "…carrying signoff_verdict=request-changes, same as any other request-changes close"

# pr-facts.sh's retire arm reads gc.takeaway_by to tell the cap's own board
# sentence from a sitting's decision on the anchor. A takeaway that lands
# without its provenance reads as the sitting's, so the operator feedback meant
# to lift the park leaves the exception and the human route standing. The park
# is proven only when the whole triple reads back.
echo "# a cap park whose provenance stamp did not land is a read-back failure"
reset "$ANCHOR_PR" "$(kid 1 closed '"source_review_bead":"r1"')$(kid 2 closed '"source_review_bead":"r2"')$(kid 3 open '"source_review_bead":"r3"')"
seed_cap_deps c1 c2 c3
out=$(STUB_DROP_KEYS="tk-anc:gc.takeaway_by" "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a dropped gc.takeaway_by exits 2"
has "$out" "did not read back" "the refusal reports the half-landed park"
has "$out" "gc.takeaway_by" "…and names the field that went missing"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

echo "# …and so is a cap park with no gc.takeaway_at"
reset "$ANCHOR_PR" "$(kid 1 closed '"source_review_bead":"r1"')$(kid 2 closed '"source_review_bead":"r2"')$(kid 3 open '"source_review_bead":"r3"')"
seed_cap_deps c1 c2 c3
out=$(STUB_DROP_KEYS="tk-anc:gc.takeaway_at" "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a dropped gc.takeaway_at exits 2"
has "$out" "gc.takeaway_at" "the refusal names the missing timestamp"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

# A timestamp that is merely present is not the one this verdict wrote. An
# anchor parked before carries gc.takeaway_at already, so a cap update that
# lands the headline and its provenance and drops only the timestamp satisfies
# a non-empty check, and helm dates this wait to the earlier park and attributes
# it to whatever sitting spans the old value.
echo "# …and so is a cap park left holding a STALE gc.takeaway_at"
reset "$ANCHOR_PR" "$(kid 1 closed '"source_review_bead":"r1"')$(kid 2 closed '"source_review_bead":"r2"')$(kid 3 open '"source_review_bead":"r3"')"
seed_cap_deps c1 c2 c3
anchor_meta gc.takeaway_at=1999-01-01T00:00:00Z
out=$(STUB_DROP_KEYS="tk-anc:gc.takeaway_at" "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a cap park left on a stale gc.takeaway_at exits 2"
has "$out" "gc.takeaway_at" "the refusal names the timestamp field"
eq "$(meta tk-anc gc.takeaway_at)" "1999-01-01T00:00:00Z" "…and the stale value is what read back"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

# The cap park is a person owing an answer, and the anchor it lands on may
# carry the settled disposition of the sitting that ended before it. A clear
# that does not land leaves that "1" answering for this headline, and
# doctor/check-wait-is-an-edge — the reader that exists to find parks nothing
# re-asks — reads the cap as a wait already discharged. Only the CLEARED value
# proves the park.
echo "# …and so is a cap park that inherited a SETTLED disposition it did not clear"
reset "$ANCHOR_PR" "$(kid 1 closed '"source_review_bead":"r1"')$(kid 2 closed '"source_review_bead":"r2"')$(kid 3 open '"source_review_bead":"r3"')"
seed_cap_deps c1 c2 c3
anchor_meta gc.takeaway_settled=1
out=$(STUB_DROP_KEYS="tk-anc:gc.takeaway_settled" "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a cap park left on a stale gc.takeaway_settled exits 2"
has "$out" "gc.takeaway_settled" "the refusal names the disposition field"
eq "$(meta tk-anc gc.takeaway_settled)" "1" "…and the stale value is what read back"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

echo "# …while a cap park that clears it over a stale value parks normally"
reset "$ANCHOR_PR" "$(kid 1 closed '"source_review_bead":"r1"')$(kid 2 closed '"source_review_bead":"r2"')$(kid 3 open '"source_review_bead":"r3"')"
seed_cap_deps c1 c2 c3
anchor_meta gc.takeaway_settled=1
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "the cap path exits 0 with the disposition cleared"
eq "$(meta tk-anc gc.takeaway_settled)" "" "the park's own disposition replaces the sitting's before it"
eq "$(meta tk-anc gc.routed_to)" "human" "…and the park itself still lands"

echo "# …and so is a cap park with no takeaway at all"
reset "$ANCHOR_PR" "$(kid 1 closed '"source_review_bead":"r1"')$(kid 2 closed '"source_review_bead":"r2"')$(kid 3 open '"source_review_bead":"r3"')"
seed_cap_deps c1 c2 c3
out=$(STUB_DROP_KEYS="tk-anc:gc.takeaway" "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a dropped gc.takeaway exits 2"
has "$out" "did not read back" "the refusal reports the half-landed park"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

echo "# only rework children count as rounds"
reset "$ANCHOR_PR" "$(kid 1 open '"source_review_bead":"r1"')$(kid 2 open '')$(kid 3 open '"branch":"x"')"
seed_cap_deps c1 c2 c3
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(wc -l < "$STUB_CREATED" | tr -d ' ')" "1" "non-rework children do not inflate the count (child filed)"

echo "# cap is tunable via GC_MAX_REVIEW_ROUNDS"
reset "$ANCHOR_PR" "$(kid 1 open '"source_review_bead":"r1"')"
seed_cap_deps c1
GC_MAX_REVIEW_ROUNDS=1 "$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1
eq "$(meta tk-anc merge_hold)" "signoff_cap" "GC_MAX_REVIEW_ROUNDS=1 trips at 1"

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
eq "$(meta tk-anc merge_hold)" "signoff_cap" "a reset buys one more budget, not an exemption"
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
eq "$(meta tk-anc merge_hold)" "signoff_cap" "…and parks the anchor"
has "$(meta tk-anc blocked_reason)" "spent pre-open" "blocked_reason says the rounds were pre-open"
has "$(meta tk-anc blocked_reason)" "signoff.sh reset tk-anc" "…and names the verb that retires it"
# The pre-open detail is the longest the cap composes. The board still gets a
# sentence, and still gets one that fits.
eq "$(printf '%s' "$(meta tk-anc gc.takeaway)" | jq -Rsr 'length <= 140')" "true" \
  "a pre-open cap's takeaway fits the board cap the detail exceeds"
has "$(meta tk-anc gc.takeaway)" "did not converge" "…and still says what is owed"
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
  anchor_meta merge_hold=signoff_cap "signoff_cap=codex" \
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

echo "# …and the sentence the cap wrote for the board goes with that park"
# The cap is the only writer that stamps a takeaway describing a park rather
# than a sitting, so it is the only one this verb may clear. gc.takeaway_by is
# what says which it is holding.
capped_pre 3 "gc.takeaway=signoff did not converge after 3 rework rounds (cap 3)" \
  "gc.takeaway_at=2026-01-01T00:00:00Z" "gc.takeaway_by=signoff"
out=$("$SUT" reset tk-anc --reason "operator ruling" --batch ruling-ta 2>&1); rc=$?
eq "$rc" 0 "the reset exits 0"
eq "$(meta tk-anc gc.takeaway)" "<absent>" "the headline the board rendered for the park is retired with it"
eq "$(meta tk-anc gc.takeaway_at)" "<absent>" "…with the instant that dated the wait"
eq "$(meta tk-anc gc.takeaway_by)" "<absent>" "…and the provenance that told it from a sitting's"
has "$out" "the cap's takeaway" "…and the report names it among what was retired"

echo "# …and a takeaway unset that is silently lost is not a retirement"
# Same shape as the tally: a park released while the board still renders its
# question sends the operator to an anchor that is back in the cadence.
capped_pre 3 "gc.takeaway=signoff did not converge after 3 rework rounds (cap 3)" \
  "gc.takeaway_at=2026-01-01T00:00:00Z" "gc.takeaway_by=signoff"
printf 'tk-anc gc.takeaway\n' > "$STUB_UNSET_NOOP"
out=$("$SUT" reset tk-anc --reason "operator ruling" --batch ruling-ta2 2>&1); rc=$?
eq "$rc" 2 "a lost gc.takeaway unset exits 2"
has "$out" "did not read back on tk-anc (gc.takeaway)" "…naming the key the board still renders"
eq "$(meta tk-anc gc.takeaway)" "signoff did not converge after 3 rework rounds (cap 3)" "…which the anchor still carries"

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
anchor_meta merge_hold=signoff_cap "signoff_cap=codex" "gc.routed_to=human"
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
eq "$(meta tk-anc merge_hold)" "signoff_cap" "…the park stands"
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
eq "$(meta tk-anc merge_hold)" "signoff_cap" "…the park stands rather than be released on a guess"

echo "# a hold no signoff_cap claims is a person's: the counter resets, the park stays"
spent 3 "$ANCHOR_PRE"
anchor_meta merge_hold=true "gc.routed_to=human"
"$SUT" reset tk-anc --reason "operator ruling" --batch ruling-2 >/dev/null 2>&1; rc=$?
eq "$rc" 0 "the reset still exits 0"
eq "$(meta tk-anc signoff_round_floor)" "3@ruling-2" "the rounds are the cap's wherever the park came from"
eq "$(meta tk-anc merge_hold)" "true" "…but an unclaimed hold is not this verb's to lift"
eq "$(meta tk-anc gc.routed_to)" "human" "…and the route a person is waiting on stands"
has "$(notes tk-anc)" "No park was retired" "…and the anchor records that it kept the park"

echo "# …and a signoff_cap standing beside no hold retires nothing"
spent 3 "$ANCHOR_PRE"
anchor_meta "signoff_cap=codex" "gc.routed_to=human"
"$SUT" reset tk-anc --reason "operator ruling" --batch ruling-3 >/dev/null 2>&1
eq "$(meta tk-anc signoff_cap)" "codex" "a cap stamp whose hold is already lifted is left alone"
eq "$(meta tk-anc gc.routed_to)" "human" "…and so is the route beside it"
has "$(notes tk-anc)" "No park was retired" "…and the anchor records that nothing was retired"

# The regression this pairing exists to prevent: an operator lifts merge_hold
# by hand (signoff_cap stays behind, per the case above), then later sets
# merge_hold=true for an unrelated freeze while the orphaned signoff_cap is
# still standing. The old predicate (signoff_cap non-empty && merge_hold
# held-by-any-truthy-value) would read that freeze as this cap's own park and
# silently lift it on the next reset. The exact-pairing predicate must not.
echo "# an operator's merge_hold=true beside an orphaned signoff_cap is not this cap's pairing"
spent 3 "$ANCHOR_PRE"
anchor_meta merge_hold=true "signoff_cap=codex" "gc.routed_to=human"
out=$("$SUT" reset tk-anc --reason "operator ruling" --batch ruling-freeze 2>&1); rc=$?
eq "$rc" 0 "the reset still exits 0"
eq "$(meta tk-anc signoff_round_floor)" "3@ruling-freeze" "the rounds are the cap's wherever the orphaned stamp came from"
eq "$(meta tk-anc merge_hold)" "true" "…but merge_hold=true is a person's freeze, not the cap's signoff_cap pairing"
eq "$(meta tk-anc signoff_cap)" "codex" "…so the orphaned signoff_cap is left standing too"
eq "$(meta tk-anc gc.routed_to)" "human" "…and the human route stands"
has "$(notes tk-anc)" "a person's hold stays" "…and the note says a person's hold stays"

echo "# a reset that does not read back is never reported as retired"
capped_pre 3
printf 'tk-anc\n' > "$STUB_UPD_FAIL"
out=$("$SUT" reset tk-anc --reason "operator ruling" 2>&1); rc=$?
eq "$rc" 2 "a denied write exits 2"
has "$out" "did not read back" "…naming the failure"
eq "$(meta tk-anc merge_hold)" "signoff_cap" "…and the park still stands"

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
eq "$(meta tk-anc merge_hold)" "signoff_cap" "…the park stands"
eq "$(meta tk-anc gc.routed_to)" "human" "…the human route stands"
eq "$(meta tk-anc dispatch_count)" "5" "…and the tally stands"

echo "# …and a ledger naming no round is no cap to retire"
reset "$ANCHOR_PRE"
anchor_meta merge_hold=true "signoff_cap=codex" "gc.routed_to=human"
out=$("$SUT" reset tk-anc --reason "operator ruling" 2>&1); rc=$?
eq "$rc" 1 "an anchor with no rework child refuses"
has "$out" "no rework child" "…saying so"
eq "$(meta tk-anc signoff_round_floor)" "<absent>" "…and writes nothing"
eq "$(meta tk-anc merge_hold)" "true" "…retiring no park it cannot account for"

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
eq "$(meta tk-anc merge_hold)" "signoff_cap" "…and lifts no hold"

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
