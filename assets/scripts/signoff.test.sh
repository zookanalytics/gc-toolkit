#!/usr/bin/env bash
# Hermetic test for assets/scripts/signoff.sh — the single gate-verdict writer.
# Stubbed gc/gh/git; no live city, Dolt, network, or PRs. The posted artifact
# carries the anchor link; --approve is NEVER used. A verdict records a lane
# state and binds to no commit, so the reviewed oid reaches the artifact and the
# review bead and nothing else, and a head that moved under the review refuses
# nothing. request-changes always files exactly one rework child — convergence
# is judged by the validator, not counted here — and is idempotent on
# source_review_bead, so a re-pool adopts the child it already filed rather than
# minting a twin.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/signoff.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-signoff-test.XXXXXX")"
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
if [ "${1:-}" = "sling" ]; then
  # `gc sling [--rig X] <pool> <bead> --on <formula>`: a graph.v2 pour retires
  # gc.routed_to on the work bead and stamps gc.execution_routed_to=<pool>, the
  # read-back signoff.sh proves the pour by. STUB_SLING_NOPOUR models a pour
  # that exits success but never stamps the route (a partial pour), so the SUT
  # must refuse a bare-route fallback rather than double-dispatch the work.
  shift; pool=""; bead=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --rig|--on) shift ;;
      -*) ;;
      *) if [ -z "$pool" ]; then pool="$1"; elif [ -z "$bead" ]; then bead="$1"; fi ;;
    esac
    shift || true
  done
  if [ -z "${STUB_SLING_NOPOUR:-}" ] && [ -n "$bead" ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-signoff-test.XXXXXX")
    jq -c --arg id "$bead" --arg p "$pool" \
      'map(if .id == $id then (.metadata["gc.execution_routed_to"] = $p | .metadata |= del(.["gc.routed_to"])) else . end)' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
  fi
  exit 0
fi
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
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-signoff-test.XXXXXX"); cp "$STORE" "$tmp"
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
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-signoff-test.XXXXXX")
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
    # A `bd list` shim: --status and repeated --metadata-field, ANDed, over the
    # seeded store. STUB_LIST_FAIL models a ledger that will not answer.
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
cat > "$BIN/finding" <<'STUB'
#!/usr/bin/env bash
# Stub for finding.sh: records signoff's calls and mints a stable id per
# objection. finding.sh's own suite (finding.test.sh) proves the key, the dedup
# and the edges; here we need only that signoff reaches for it with the right
# shape — files each objection, wires the fix unit to what it filed, and closes
# the lane's unvalidated findings on approve.
set -u
verb="${1:-}"; shift || true
printf '%s %s\n' "$verb" "$*" >> "${STUB_FINDING_LOG:?}"
case "$verb" in
  upsert)
    anchor=""; locus=""; message=""
    while [ $# -gt 0 ]; do case "$1" in
      --anchor) anchor="${2:-}"; shift 2 ;; --locus) locus="${2:-}"; shift 2 ;;
      --message) message="${2:-}"; shift 2 ;; --lane|--source) shift 2 ;; *) shift ;;
    esac; done
    printf 'fnd-%s\n' "$(printf '%s\037%s\037%s' "$anchor" "$locus" "$message" | sha1sum | cut -c1-8)" ;;
esac
exit 0
STUB
chmod +x "$BIN/gc" "$BIN/gh" "$BIN/git" "$BIN/finding"
export PATH="$BIN:$PATH"
# request-changes files findings and approve closes them through finding.sh;
# point signoff at the stub so the real primitive never runs here.
export GC_FINDING_TOOL="$BIN/finding" STUB_FINDING_LOG="$TMP/finding.log"
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
unset GC_RIG 2>/dev/null || true

ANCHOR_PR='{"id":"tk-anc","status":"open","assignee":"","metadata":{"branch":"polecat/tk-1","target":"main","merged_target":"main","pr_number":"42","pr_url":"https://github.com/o/r/pull/42"},"notes":""}'
ANCHOR_PRE='{"id":"tk-anc","status":"open","assignee":"","metadata":{"branch":"polecat/tk-1","target":"main"},"notes":""}'
REVIEW='{"id":"rv-1","status":"in_progress","assignee":"pool/x","metadata":{"check_name":"codex","anchor_bead":"tk-anc","fix_target_pool":"rig/gc-toolkit.polecat"},"notes":"VERDICT body: findings here"}'

reset() { # $1 = anchor json, extra beads appended via $2
  printf '[%s,%s%s]' "$1" "$REVIEW" "${2:-}" > "$STUB_STORE"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_GH_LOG"; : > "$STUB_GH_BODY"
  : > "$STUB_CREATED"; : > "$STUB_UPD_FAIL"; : > "$STUB_UNSET_NOOP"; printf '0' > "$STUB_SEQ"
  : > "$STUB_UNSET_LOG"; : > "$STUB_SHOW_DEAD"; : > "$STUB_DROP_NOTES"
  : > "$STUB_FINDING_LOG"
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
# A rework child of tk-anc as store JSON, and the blocks edge that hangs it on
# the anchor. The idempotency guard reads this walk to find an open child that
# already answers a review.
kid() { printf ',{"id":"c%s","status":"%s","assignee":"","metadata":{%s},"notes":""}' "$1" "$2" "$3"; }
seed_cap_deps() { for c in "$@"; do printf 'tk-anc|%s|blocks\n' "$c" >> "$STUB_DEPS"; done; }

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
# The lane state names no commit, so lane-state.sh derives a lane green only
# from a closed review bead that carries anchor_bead, reviewed_oid, check_name
# and signoff_verdict=approve. Nothing here ever posts an APPROVED GitHub
# review, so that bead is the only backing a city verdict leaves: an approve
# closed without the record derives no green and cannot land.
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

# --- a legacy exception@<oid> park predates the migration -----------------------
# migrate-lane-states.sh rewrites an exception@<oid> marker to merge_hold=true
# plus a board visit over a store still carrying one; until it runs, that marker
# is not lane vocabulary this verdict may read. Stamping green over it would
# silently release a park a human is relying on, so approve refuses before it
# posts or stamps anything.
echo "# an approve over a legacy exception@<oid> marker refuses, not migrates"
reset "$ANCHOR_PR"; seed_marker "exception@$OID_OLD"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 2 "the legacy park refuses the verdict"
has "$out" "migrate-lane-states.sh" "…and names the migration that clears it"
eq "$(meta tk-anc check.codex)" "exception@$OID_OLD" "the legacy marker is left exactly as it stood"
eq "$(status rv-1)" "in_progress" "the review bead is left open, not recorded as approving"
eq "$(cat "$STUB_GH_BODY")" "" "no artifact is posted over an unmigrated park"

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

# --- request-changes files ONE rework child ------------------------------------
echo "# request-changes files one rework child"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "tk-anc" then .metadata["check.codex"] = "green" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes exits 0"
eq "$(meta tk-anc check.codex)" "<absent>" "the green marker is cleared"
has "$(cat "$STUB_GH_LOG")" "--comment" "the changes artifact is a comment"
hasnt "$(cat "$STUB_GH_LOG")" "--request-changes" "never a blocking GitHub review"
eq "$(grep '^Rework' "$STUB_CREATED")" "Rework PR#42: address signoff findings" "exactly one rework child, PR-titled"
eq "$(meta fix-1 task_kind)" "rework" "child carries the rework role marker"
eq "$(meta fix-1 anchor_bead)" "tk-anc" "child names the anchor it belongs to"
eq "$(meta fix-1 branch)" "polecat/tk-1" "child resumes the anchor's branch"
eq "$(meta fix-1 target)" "main" "child carries the landing target"
eq "$(meta fix-1 source_review_bead)" "rv-1" "child names the source review"
eq "$(meta fix-1 merge_strategy)" "mr" "child stays on the PR path"
eq "$(meta fix-1 existing_pr)" "https://github.com/o/r/pull/42" "child reworks THIS PR, not a fresh one"
eq "$(meta fix-1 pr_number)" "42" "child carries the PR number"
eq "$(meta fix-1 gc.execution_routed_to)" "rig/gc-toolkit.polecat" "the pour routes the child to the fix pool"
eq "$(meta fix-1 gc.routed_to)" "<absent>" "the pour retires the bare route — no driverless stamp"
has "$(cat "$STUB_GC_LOG")" "sling rig/gc-toolkit.polecat fix-1 --on mol-polecat-work" "the child is slung as a driven mol-polecat-work molecule"
has "$(cat "$STUB_GC_LOG")" "session wake rig/gc-toolkit.polecat" "the pool is woken to claim the rework"
has "$(cat "$STUB_DEPS")" "tk-anc|fix-1|blocks" "child blocks the anchor"
has "$(gc bd ready --json)" '"id":"fix-1"' "the rework child stays open and unblocked"
hasnt "$(gc bd ready --json)" '"id":"tk-anc"' "the anchor waits on the child, not the reverse"
has "$(meta fix-1 rejection_reason)" "signoff requested changes" "rejection_reason carries the summary"
eq "$(status rv-1)" "closed" "review bead closed after the dispatch"
eq "$(meta rv-1 signoff_verdict)" "request-changes" "…and signoff_verdict=request-changes rides in the same close"

echo "# request-changes files a child at any round count — GC_MAX_REVIEW_ROUNDS is inert, no park written"
# The round cap is retired: no counter, no floor, no signoff_cap park. Even with
# rework children from prior rounds already on the anchor and GC_MAX_REVIEW_ROUNDS
# exported below that count, request-changes files one more child and parks
# nothing — the env var names a mechanism this verdict no longer has.
reset "$ANCHOR_PR" ',{"id":"old-1","status":"closed","assignee":"","metadata":{"task_kind":"rework","anchor_bead":"tk-anc","source_review_bead":"rv-0a"},"notes":""},{"id":"old-2","status":"closed","assignee":"","metadata":{"task_kind":"rework","anchor_bead":"tk-anc","source_review_bead":"rv-0b"},"notes":""}'
jq -c 'map(if .id == "tk-anc" then .metadata["check.codex"] = "green" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
out=$(GC_MAX_REVIEW_ROUNDS=1 "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes exits 0 at a round count past any legacy cap"
eq "$(grep '^Rework' "$STUB_CREATED")" "Rework PR#42: address signoff findings" "one more rework child is filed, uncapped"
eq "$(meta fix-1 source_review_bead)" "rv-1" "the new child names this review, not a prior round's"
eq "$(meta tk-anc signoff_cap)" "<absent>" "no signoff_cap park is written"
eq "$(meta tk-anc signoff_round_floor)" "<absent>" "no round floor is written"
eq "$(meta tk-anc merge_hold)" "<absent>" "no merge_hold park is written"
eq "$(meta tk-anc gc.takeaway)" "<absent>" "no cap takeaway is written"
eq "$(meta tk-anc blocked_reason)" "<absent>" "no blocked_reason is written"
eq "$(meta tk-anc gc.routed_to)" "<absent>" "no human park route is written on the anchor"
eq "$(status rv-1)" "closed" "the review bead closes on the dispatch"

echo "# request-changes refuses a bare-route fallback when the pour will not read back (double-dispatch guard)"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "tk-anc" then .metadata["check.codex"] = "green" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
out=$(STUB_SLING_NOPOUR=1 "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "an unproven pour is a retryable failure, not a bare-route success"
has "$(cat "$STUB_GC_LOG")" "sling rig/gc-toolkit.polecat fix-1 --on mol-polecat-work" "the sling is attempted first"
eq "$(meta fix-1 gc.execution_routed_to)" "<absent>" "no pour read back"
eq "$(meta fix-1 gc.routed_to)" "<absent>" "no bare route is stamped — a partial pour plus a pool claim would double-dispatch the work"
has "$out" "double-dispatch hazard" "the refusal names the double-dispatch hazard"
has "$(cat "$STUB_DEPS")" "tk-anc|fix-1|blocks" "the child still blocks the anchor"
eq "$(status rv-1)" "in_progress" "the review is left unclosed — the failed dispatch is retryable, not consumed as a completed dispatch"

echo "# pre-open request-changes"
reset "$ANCHOR_PRE"
"$SUT" --review-bead rv-1 --verdict request-changes >/dev/null 2>&1; rc=$?
eq "$rc" 0 "pre-open request-changes exits 0"
eq "$(grep '^Rework' "$STUB_CREATED")" "Rework branch polecat/tk-1: address pre-open signoff findings" "pre-open child is branch-titled"
eq "$(meta fix-1 existing_pr)" "<absent>" "pre-open child carries no PR fields"

echo "# incomplete child work order is exit 2, review stays open"
reset "$ANCHOR_PR"
printf 'fix-1\n' > "$STUB_UPD_FAIL"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "an unstamped child work order exits 2"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

echo "# …and a role marker that half-lands is caught by the same read-back"
reset "$ANCHOR_PR"
out=$(STUB_DROP_KEYS="fix-1:task_kind,anchor_bead" "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a child with no role marker exits 2"
has "$out" "task_kind" "the refusal names the missing marker"
has "$out" "anchor_bead" "…and its other half"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

echo "# a child whose blocks edge did not land is caught, not shipped"
reset "$ANCHOR_PR"
out=$(STUB_DEP_NOOP=1 "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a child with no blocks edge exits 2"
has "$out" "blocks_edge" "the refusal names the missing edge"
eq "$(status rv-1)" "in_progress" "the review bead stays open for a retry"

# --- request-changes is idempotent on source_review_bead ------------------------
# One review owns one rework child. The verdict path is re-runnable — close is
# its last write, and the exits above it leave the review OPEN with a child
# already filed and its edge already hung — so a re-pool must adopt that child,
# never mint a twin the landing sibling's close cannot cancel.

echo "# the exit-2-then-retry sequence adopts the orphan instead of filing a second child"
reset "$ANCHOR_PR"
jq -c 'map(if .id == "tk-anc" then .metadata["check.codex"] = "green" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
# First pass: the pour reports success but never stamps the route, so signoff
# files the child, hangs its edge, and exits 2 with the review left open.
out=$(STUB_SLING_NOPOUR=1 "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "first pass exits 2 — the pour did not read back"
eq "$(status rv-1)" "in_progress" "the review is left open for a retry"
eq "$(cat "$STUB_CREATED")" "Rework PR#42: address signoff findings" "the first pass filed exactly one child"
eq "$(meta fix-1 source_review_bead)" "rv-1" "the orphan names this review"
eq "$(meta fix-1 gc.execution_routed_to)" "<absent>" "the orphan was never dispatched"
# Second pass: the same review, re-pooled and re-claimed, re-enters here. Forget
# the first pass's create/sling logs so the assertions read only the retry.
: > "$STUB_CREATED"; : > "$STUB_GC_LOG"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "the retry exits 0"
eq "$(grep -c '^Rework' "$STUB_CREATED")" "0" "the retry files NO second rework child"
has "$out" "adopting existing open rework child fix-1" "…it adopts the orphan by name"
eq "$(meta fix-1 gc.execution_routed_to)" "rig/gc-toolkit.polecat" "the adopted orphan is dispatched on the retry"
has "$(cat "$STUB_GC_LOG")" "sling rig/gc-toolkit.polecat fix-1 --on mol-polecat-work" "…the retry slings the SAME child"
eq "$(status rv-1)" "closed" "the review closes once the adopted child is dispatched"
eq "$(grep -c 'tk-anc|fix-1|blocks' "$STUB_DEPS")" "1" "exactly one edge holds the anchor — no duplicate accrued"

echo "# an open child for a DIFFERENT review is not adopted — a genuine next round files its own"
reset "$ANCHOR_PR" "$(kid 9 open '"source_review_bead":"rv-OLD","branch":"polecat/tk-1","target":"main"')"
seed_cap_deps c9
jq -c 'map(if .id == "tk-anc" then .metadata["check.codex"] = "green" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes for a new review exits 0"
eq "$(grep '^Rework' "$STUB_CREATED")" "Rework PR#42: address signoff findings" "a fresh child is filed for this review"
eq "$(meta fix-1 source_review_bead)" "rv-1" "…naming THIS review, not the older one"
eq "$(meta c9 gc.execution_routed_to)" "<absent>" "the other review's child is left untouched"
eq "$(meta c9 task_kind)" "<absent>" "…and its work order is not rewritten"

echo "# an adopted child a prior pass already dispatched is not re-slung (no double-dispatch)"
reset "$ANCHOR_PR" "$(kid 9 open '"source_review_bead":"rv-1","branch":"polecat/tk-1","target":"main","gc.execution_routed_to":"rig/gc-toolkit.polecat"')"
seed_cap_deps c9
jq -c 'map(if .id == "tk-anc" then .metadata["check.codex"] = "green" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "exits 0 — only the review close was still owed"
eq "$(grep -c '^Rework' "$STUB_CREATED")" "0" "no second rework child is filed"
hasnt "$(cat "$STUB_GC_LOG")" "sling rig/gc-toolkit.polecat c9" "the in-flight child is not re-slung"
has "$out" "already dispatched" "…the notice says the child was already dispatched"
eq "$(status rv-1)" "closed" "the review is closed"
eq "$(jq -r '[ .[] | select((.metadata.task_kind // "") == "validation") ] | length' "$STUB_STORE")" "1" "the lane's validation pass is opened even on the already-dispatched exit"

echo "# the orphan's recorded reason survives adoption — it is not overwritten"
reset "$ANCHOR_PR" "$(kid 9 open '"source_review_bead":"rv-1","branch":"polecat/tk-1","target":"main","rejection_reason":"signoff requested changes: first pass"')"
seed_cap_deps c9
jq -c 'map(if .id == "tk-anc" then .metadata["check.codex"] = "green" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "adopt-and-dispatch exits 0"
eq "$(meta c9 gc.execution_routed_to)" "rig/gc-toolkit.polecat" "the orphan is adopted and dispatched"
eq "$(meta c9 rejection_reason)" "signoff requested changes: first pass" "its recorded reason is preserved, not overwritten"
eq "$(grep -c '^Rework' "$STUB_CREATED")" "0" "no second rework child is filed"

# --- request-changes opens the machine lane's validation pass -------------------
# The gap the retired round cap left: a codex request-changes batch filed
# findings and a fix unit but opened no pass, so gate-ensure had nothing to
# dispatch mol-validate onto and the machine lane's convergence was judged by
# nobody. request-changes now ensures one task_kind=validation bead per (anchor,
# lane) — the shape pr-facts.sh opens for a human batch — that gate-ensure's
# open_validation_passes dispatches the validator onto and its quiescence reads
# to hold a fresh review off the anchor while the pass is open.
echo "# request-changes opens the machine lane's validation pass on the anchor"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes exits 0"
eq "$(jq -r '[ .[] | select((.metadata.task_kind // "") == "validation") ] | length' "$STUB_STORE")" "1" "exactly one validation pass is opened"
VP=$(jq -r 'first(.[] | select((.metadata.task_kind // "") == "validation") | .id) // ""' "$STUB_STORE")
eq "$(meta "$VP" check_name)" "codex" "the pass names the machine lane the validator rules by"
eq "$(meta "$VP" anchor_bead)" "tk-anc" "the pass is anchored to the review's anchor"
eq "$(meta "$VP" reviewed_oid)" "$OID_HEAD" "the pass pins the head the batch was reviewed at"
has "$(cat "$STUB_CREATED")" "Validate PR#42 codex review @ $OID_HEAD" "the pass is PR-titled for the lane and head"
has "$(cat "$STUB_DEPS")" "tk-anc|$VP|blocks" "the pass blocks the anchor — the merge is held until the validator closes it"

echo "# request-changes reuses an open pass for the lane — no twin, one edge, head preserved"
reset "$ANCHOR_PR" ',{"id":"vp-open","status":"open","assignee":"","metadata":{"task_kind":"validation","anchor_bead":"tk-anc","check_name":"codex","reviewed_oid":"'"$OID_OLD"'"},"notes":""}'
printf 'tk-anc|vp-open|blocks\n' >> "$STUB_DEPS"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes exits 0"
has "$out" "reusing open validation pass vp-open" "the open pass is reused by name"
hasnt "$(cat "$STUB_CREATED")" "Validate" "no second validation pass is minted"
eq "$(jq -r '[ .[] | select((.metadata.task_kind // "") == "validation") ] | length' "$STUB_STORE")" "1" "still exactly one validation pass on the anchor"
eq "$(grep -c 'tk-anc|vp-open|blocks' "$STUB_DEPS")" "1" "exactly one validation-pass edge holds the anchor — no duplicate accrued"
eq "$(meta vp-open reviewed_oid)" "$OID_OLD" "the reused pass keeps the head it opened at — a validator mid-rule is not moved"

echo "# request-changes adopts a same-title unstamped orphan instead of minting a twin"
# A prior attempt that created the bead but never stamped its shape leaves an
# orphan the lane probe cannot see; it is adopted by exact title and stamped
# into shape rather than twinned into a second anchor blocker.
reset "$ANCHOR_PR" ',{"id":"vp-orphan","status":"open","assignee":"","title":"Validate PR#42 codex review @ '"$OID_HEAD"'","metadata":{},"notes":""}'
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes exits 0"
has "$out" "adopting unstamped validation-pass orphan vp-orphan" "the unstamped orphan is adopted by title"
hasnt "$(cat "$STUB_CREATED")" "Validate" "no twin pass is minted"
eq "$(meta vp-orphan task_kind)" "validation" "the adopted orphan is stamped into shape"
eq "$(meta vp-orphan check_name)" "codex" "…with the lane"
eq "$(meta vp-orphan anchor_bead)" "tk-anc" "…and the anchor"
has "$(cat "$STUB_DEPS")" "tk-anc|vp-orphan|blocks" "…and it is hung on the anchor"

echo "# a different lane's open pass is not reused — one pass per lane"
reset "$ANCHOR_PR" ',{"id":"vp-arch","status":"open","assignee":"","metadata":{"task_kind":"validation","anchor_bead":"tk-anc","check_name":"arch","reviewed_oid":"'"$OID_HEAD"'"},"notes":""}'
printf 'tk-anc|vp-arch|blocks\n' >> "$STUB_DEPS"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes exits 0"
has "$(cat "$STUB_CREATED")" "Validate PR#42 codex review" "a codex pass is opened beside the arch pass"
eq "$(jq -r '[ .[] | select((.metadata.task_kind // "") == "validation") ] | length' "$STUB_STORE")" "2" "the codex pass and the arch pass coexist — a pass is per lane"

echo "# a validation pass whose shape does not read back is exit 2, review left open"
reset "$ANCHOR_PR"
# The pass is the second bead created (after the rework child fix-1); dropping
# its task_kind models a shaping write that half-landed and the validator path
# could never see, so the verdict must not close past it.
out=$(STUB_DROP_KEYS="fix-2:task_kind" "$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 2 "a pass missing its task_kind exits 2"
has "$out" "did not record the batch shape" "…naming the shape that did not stick"
eq "$(status rv-1)" "in_progress" "the review is left open for a retry"

echo "# pre-open request-changes opens a branch-titled validation pass"
reset "$ANCHOR_PRE"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "pre-open request-changes exits 0"
VP=$(jq -r 'first(.[] | select((.metadata.task_kind // "") == "validation") | .id) // ""' "$STUB_STORE")
eq "$(meta "$VP" check_name)" "codex" "the pre-open pass names the lane"
eq "$(meta "$VP" anchor_bead)" "tk-anc" "the pre-open pass is anchored"
has "$(cat "$STUB_CREATED")" "Validate branch polecat/tk-1 codex review @ $OID_HEAD" "the pre-open pass is branch-titled"
has "$(cat "$STUB_DEPS")" "tk-anc|$VP|blocks" "the pre-open pass blocks the anchor"

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

# --- request-changes files the objections as findings beside the fix unit -------
echo "# request-changes files findings beside the fix unit"
reset "$ANCHOR_PR"
FF="$TMP/findings.json"
cat > "$FF" <<'JSON'
[
  {"locus":"assets/scripts/foo.sh:bar()","message":"unquoted expansion in the loop","severity":"P1"},
  {"locus":"docs/x.md","message":"stale reference to a retired script","severity":"P2"}
]
JSON
out=$("$SUT" --review-bead rv-1 --verdict request-changes --findings-file "$FF" 2>&1); rc=$?
eq "$rc" 0 "request-changes with --findings-file exits 0"
has "$(cat "$STUB_FINDING_LOG")" "upsert --anchor tk-anc --lane codex --locus assets/scripts/foo.sh:bar() --message unquoted expansion in the loop" "signoff files the first objection as a finding on the reviewed lane"
has "$(cat "$STUB_FINDING_LOG")" "upsert --anchor tk-anc --lane codex --locus docs/x.md --message stale reference to a retired script" "signoff files the second objection as a finding"
FIX=$(jq -r '[ .[] | select(.id | startswith("fix-")) ] | .[0].id // empty' "$STUB_STORE")
hasnt "$(cat "$STUB_FINDING_LOG")" "wire-fix-unit" "signoff does NOT wire the fix unit to the unvalidated findings — the validator hangs that edge as it rules each one must-fix, so a later declined ruling can still close its finding"
has "$(cat "$STUB_DEPS")" "tk-anc|$FIX|blocks" "the fix unit still blocks the anchor (the merge is held)"
has "$(meta "$FIX" rejection_reason)" "address the 2 finding(s) this bead blocks" "rejection_reason points the worker at the findings, not the objection prose"

# --- request-changes WITHOUT --findings-file is unchanged (backward compat) ------
echo "# request-changes without findings-file"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict request-changes 2>&1); rc=$?
eq "$rc" 0 "request-changes without findings exits 0"
hasnt "$(cat "$STUB_FINDING_LOG")" "upsert" "no findings are filed when no --findings-file is passed"
FIX2=$(jq -r '[ .[] | select(.id | startswith("fix-")) ] | .[0].id // empty' "$STUB_STORE")
has "$(meta "$FIX2" rejection_reason)" "signoff requested changes:" "rejection_reason keeps its one-line prose summary"
hasnt "$(meta "$FIX2" rejection_reason)" "finding(s) this bead blocks" "…and names no findings when none were filed"

# --- a malformed findings file never costs the rework dispatch ------------------
echo "# a malformed findings file is best-effort"
reset "$ANCHOR_PR"
printf 'not json' > "$TMP/bad.json"
out=$("$SUT" --review-bead rv-1 --verdict request-changes --findings-file "$TMP/bad.json" 2>&1); rc=$?
eq "$rc" 0 "a malformed findings file still lands the verdict"
has "$(cat "$STUB_CREATED")" "Rework PR#42" "…and still files the rework child that holds the merge"

# --- approve closes the lane's still-unruled findings ---------------------------
echo "# approve closes the lane's unvalidated findings"
reset "$ANCHOR_PR"
out=$("$SUT" --review-bead rv-1 --verdict approve 2>&1); rc=$?
eq "$rc" 0 "approve exits 0"
has "$(cat "$STUB_FINDING_LOG")" "close-unvalidated --anchor tk-anc --lane codex" "approve closes the lane's still-unruled findings"

# --- the standing prohibition: the city never approves its own PRs ----------------
if grep -q -- '--approve' "$STUB_GH_ALL" 2>/dev/null; then
  bad "no gh invocation across this whole suite ever passed --approve"
else
  ok "no gh invocation across this whole suite ever passed --approve"
fi

echo
echo "signoff.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
