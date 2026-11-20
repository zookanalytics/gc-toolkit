#!/usr/bin/env bash
# Hermetic test for assets/scripts/converse-rework.sh — an operator ruling's entry
# to rework. Stubbed gc and gctk; no live city, Dolt, or network. An anchor on
# the pending record takes the ruling as an ask to its review run, with the
# checks the ruling names, read from the check index beside this checkout's
# scripts whatever the binding, and nothing filed, slung or superseded. The
# open-PR guards refuse, before the ask: an anchor off the pending record, one
# that is not live, carries a disposition, or names no branch, target or PR.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/converse-rework.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-rework-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# gctk, built from this checkout, reads the check index for the scripts under
# test.
( cd "$HERE/../../services/gctk" && go build -buildvcs=false -o "$TMP/gctk" ./cmd/gctk ) >"$TMP/gctk-build.log" 2>&1 \
  || { echo "gctk did not build: $(tail -3 "$TMP/gctk-build.log")" >&2; exit 1; }
export GCTK_BIN="$TMP/gctk"

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
# Two stores: with STUB_STORES_DIR set, each rig keeps its beads and edges in
# files of its own, and GC_RIG picks the store every write and list acts in, as
# it picks the store gc bd acts in. A show by id answers from whichever store
# holds the bead. An edge is added and listed only in a store that holds the
# bead it is about, so an edge onto another store's bead cannot be proved.
if [ -n "${STUB_STORES_DIR:-}" ]; then
  STORE="$STUB_STORES_DIR/${GC_RIG:-none}.json"; DEPS="$STUB_STORES_DIR/${GC_RIG:-none}.deps"
  [ -f "$STORE" ] || printf '[]\n' > "$STORE"
  [ -f "$DEPS" ] || : > "$DEPS"
fi
in_store() { jq -e --arg id "$1" 'any(.[]; .id == $id)' "$STORE" >/dev/null 2>&1; }
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-}" = "sling" ]; then
  # `gc sling [--rig X] <pool> <bead> --on <formula>`: a graph.v2 pour retires
  # gc.routed_to and stamps gc.execution_routed_to=<pool>, the read-back the SUT
  # proves the pour by. STUB_SLING_NOPOUR models a pour that exits success but
  # never stamps the route (a partial pour), so the SUT must refuse a bare-route
  # fallback rather than double-dispatch the work.
  shift; pool=""; bead=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --rig|--on) shift ;;
      -*) ;;
      *) if [ -z "$pool" ]; then pool="$1"; elif [ -z "$bead" ]; then bead="$1"; fi ;;
    esac
    shift || true
  done
  # A pour copies the bead's priority into its workflow once: poured_priority
  # records it, bd's default 2 when none was written.
  if [ -z "${STUB_SLING_NOPOUR:-}" ] && [ -n "$bead" ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-cr.XXXXXX")
    jq -c --arg id "$bead" --arg p "$pool" \
      'map(if .id == $id then (.metadata["gc.execution_routed_to"] = $p | .metadata |= del(.["gc.routed_to"]) | .poured_priority = (.priority // 2)) else . end)' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
  fi
  exit 0
fi
# The rig list the SUT finds the anchor's rig checkout in (bead-store.sh): the
# anc prefix is the rig at STUB_RIG_PATH, unless STUB_RIG_UNLISTED leaves it out.
# Over two stores it lists rig-a (ra) and rig-b (rb) as well, each at that same
# checkout, since the run reads only the anchor branch's head there.
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
  if [ -n "${STUB_RIG_UNLISTED:-}" ]; then echo '{"rigs":[]}'
  elif [ -n "${STUB_STORES_DIR:-}" ]; then
    printf '{"rigs":[{"name":"anc-rig","prefix":"anc","path":"%s"},{"name":"rig-a","prefix":"ra","path":"%s"},{"name":"rig-b","prefix":"rb","path":"%s"}]}\n' \
      "${STUB_RIG_PATH:?}" "$STUB_RIG_PATH" "$STUB_RIG_PATH"
  else printf '{"rigs":[{"name":"anc-rig","prefix":"anc","path":"%s"}]}\n' "${STUB_RIG_PATH:?}"; fi
  exit 0
fi
# Any other non-bd command (agent list for pool-route, session wake/nudge) is a
# quiet success: pool-route reads an empty agent set as UNREADABLE and returns
# the route UNVERIFIED (exit 0), which is enough for the dispatch to proceed.
[ "${1:-}" = "bd" ] || exit 0
shift
# Every bead bd prints carries a priority, P2 unless one was written.
bead_json() { jq -c --arg id "$1" '[.[] | select(.id == $id) | .priority //= 2]' "$STORE"; }
case "${1:-}" in
  show)
    out=$(bead_json "$2")
    if [ -n "${STUB_STORES_DIR:-}" ] && [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      for f in "$STUB_STORES_DIR"/*.json; do
        o=$(jq -c --arg id "$2" '[.[] | select(.id == $id) | .priority //= 2]' "$f")
        [ "$(printf '%s' "$o" | jq 'length')" = "0" ] || { out="$o"; break; }
      done
    fi
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      echo '{"error":"no issues found"}'
    else printf '%s\n' "$out"; fi ;;
  update)
    shift; id="$1"; shift
    [ -n "${STUB_UPD_FAIL:-}" ] && grep -qx "$id" "$STUB_UPD_FAIL" 2>/dev/null && { echo "bd: denied (stub)" >&2; exit 1; }
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-cr.XXXXXX"); cp "$STORE" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
            'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
        --status=*) st="${1#--status=}"
          jq -c --arg id "$id" --arg s "$st" \
            'map(if .id == $id then .status = $s else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
        --append-notes) shift
          jq -c --arg id "$id" --arg n "${1:-}" \
            'map(if .id == $id then .notes = (((.notes // "") | if . == "" then "" else . + "\n" end) + $n) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
        --priority|-p) shift
          jq -c --arg id "$id" --arg p "${1#P}" \
            'map(if .id == $id then .priority = ($p | tonumber) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
      shift || true
    done
    mv "$tmp" "$STORE"; echo "updated $id" ;;
  create)
    shift; title="$1"; shift
    [ -n "${STUB_CREATE_FAIL:-}" ] && exit 1
    # --metadata lands in the same insert as the bead, as bd applies it, and so
    # does --parent <id>: .parent and a parent-child edge row onto <id>.
    cmeta='{}'; cparent=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --metadata) shift; cmeta="${1:-}" ;;
        --metadata=*) cmeta="${1#--metadata=}" ;;
        --parent) shift; cparent="${1:-}" ;;
      esac
      shift || true
    done
    printf '%s' "$cmeta" | jq -e 'type == "object"' >/dev/null 2>&1 \
      || { echo "bd: --metadata is not a JSON object (stub)" >&2; exit 1; }
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    printf '%s\n' "$title" >> "${STUB_CREATED:?}"
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-cr.XXXXXX")
    jq -c --arg id "fix-$n" --argjson m "$cmeta" --arg par "$cparent" '. + [{"id":$id,"status":"open","assignee":"","metadata":$m,"notes":""} + (if $par == "" then {} else {parent: $par} end)]' "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    [ -z "$cparent" ] || printf 'fix-%s|%s|parent-child\n' "$n" "$cparent" >> "$DEPS"
    # STUB_CREATE_NOID: the insert lands but no id comes back, as when the call
    # is killed after its write commits.
    [ -n "${STUB_CREATE_NOID:-}" ] && exit 1
    printf '{"id":"fix-%s"}\n' "$n" ;;
  dep)
    shift
    # `dep S --blocks D` is "D depends on S"; --direction=down lists what an id
    # depends on, =up what depends on it.
    case "${1:-}" in
      list)
        shift; id="$1"; shift
        if [ -n "${STUB_STORES_DIR:-}" ] && ! in_store "$id"; then echo "bd: no issue $id in this store (stub)" >&2; exit 1; fi
        dir=""; typ=""
        while [ $# -gt 0 ]; do
          case "$1" in --direction=*) dir="${1#--direction=}" ;; -t) shift; typ="$1" ;; esac
          shift || true
        done
        out="["; first=1
        while IFS='|' read -r f t ty; do
          [ -n "$f" ] || continue
          [ "$ty" = "$typ" ] || continue
          other=""
          [ "$dir" = "down" ] && [ "$f" = "$id" ] && other="$t"
          [ "$dir" = "up" ] && [ "$t" = "$id" ] && other="$f"
          [ -n "$other" ] || continue
          row=$(jq -c --arg id "$other" '(.[] | select(.id == $id)) // {"id":$id,"metadata":{}}' "$STORE")
          [ "$first" = 1 ] || out="$out,"
          out="$out$row"; first=0
        done < "$DEPS"
        printf '%s]\n' "$out" ;;
      *)
        src="${1:-}"; shift || true
        if [ -n "${STUB_STORES_DIR:-}" ] && { ! in_store "$src" || ! in_store "${2:-}"; }; then
          echo "bd: no issue $src or ${2:-} in this store (stub)" >&2; exit 1
        fi
        [ "${1:-}" = "--blocks" ] && printf '%s|%s|blocks\n' "${2:-}" "$src" >> "$DEPS"
        echo "dep added" ;;
    esac ;;
  list)
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
      | select($st == "" or (($st | split(",")) | index($b))) | .priority //= 2 ]' "$STORE")
    for f in ${fields[@]+"${fields[@]}"}; do
      out=$(printf '%s' "$out" | jq -c --arg k "${f%%=*}" --arg v "${f#*=}" \
        '[ .[] | select(((((.metadata // {})[$k]) // "") | tostring) == $v) ]')
    done
    printf '%s\n' "$out" ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
export GC_RIG="gc-toolkit"
export STUB_STORE="$TMP/store.json"
export STUB_DEPS="$TMP/deps"
export STUB_GC_LOG="$TMP/gc.log"
export STUB_SEQ="$TMP/seq"
export STUB_CREATED="$TMP/created"

# reset <anchor-json>: seed the store with one anchor and clear the logs.
reset() {
  printf '%s\n' "$1" > "$STUB_STORE"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_CREATED"; printf '0' > "$STUB_SEQ"
  unset STUB_SLING_NOPOUR STUB_UPD_FAIL STUB_CREATE_FAIL STUB_CREATE_NOID STUB_LIST_FAIL STUB_RIG_UNLISTED 2>/dev/null || true
}
meta()    { jq -r --arg id "$1" --arg k "$2" 'first(.[] | select(.id == $id) | .metadata[$k]) // ""' "$STUB_STORE"; }
created() { wc -l < "$STUB_CREATED" | tr -d ' '; }
ANCHOR_PR='[{"id":"anc-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request_pending","branch":"polecat/anc-1","target":"main","existing_pr":"https://github.com/o/r/pull/42","pr_url":"https://github.com/o/r/pull/42","pr_number":"42","check_set":"correctness,arch"}}]'
echo "# --- an open PR on the pending record takes the ruling as an ask to its review run ---"
# The ask's writer is gctk review ask, whose rules its own suite proves, so a
# stub stands in for it here: it logs its call and answers as the real one does.
cat > "$TMP/gctk-ask" <<'ASK'
#!/usr/bin/env bash
echo "$*" >> "$TMP_ASK_LOG"
echo "${GCTK_SCRIPTS_DIR:-unset}" >> "$TMP_ASK_LOG.env"
[ "${STUB_ASK_RC:-0}" = 0 ] || { echo "gctk review ask: anc-1: the check index at the head declares no check \"nope\"" >&2; exit 3; }
echo "ask-1 ${STUB_ASK_HOW:-filed}"
ASK
chmod +x "$TMP/gctk-ask"
export TMP_ASK_LOG="$TMP/ask.log"
for rec in "pull_request_pending blocked" "pull_request_head_changed open"; do
  set -- $rec
  reset "$(printf '%s' "$ANCHOR_PR" | jq -c --arg mr "$1" --arg st "$2" 'map(.metadata.merge_result = $mr | .status = $st)')"
  : > "$TMP_ASK_LOG"; : > "$TMP_ASK_LOG.env"
  OUT=$(env -u GCTK_SCRIPTS_DIR GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment directly to docs/material-layers.md" --check arch 2>&1); RC=$?
  eq "$RC" "0" "$1: exit 0 once the ask stands"
  eq "$(cat "$TMP_ASK_LOG.env")" "$HERE" "$1: the checked ask names the pack's scripts beside converse-rework.sh, with none in the caller's environment"
  eq "$(created)" "0" "$1: no rework child is filed"
  eq "$(cat "$TMP_ASK_LOG")" "review ask anc-1 --reason operator ruling (conversation vis-1): apply the amendment directly to docs/material-layers.md --source vis-1 --check arch" "$1: the ask carries the ruling, the conversation as its source, and the checks it names"
  eq "$(printf '%s\n' "$OUT" | tail -n 1)" "ask-1 ask filed" "$1: the last line names the ask, as a child's line names the child"
  hasnt "$(cat "$STUB_GC_LOG")" "sling" "$1: nothing is slung"
  hasnt "$OUT" "returned anc-1's lanes to unreviewed" "$1: nothing is superseded"
done
OUT=$(STUB_ASK_HOW=found GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment directly to docs/material-layers.md" 2>&1); RC=$?
eq "$RC $(printf '%s\n' "$OUT" | tail -n 1)" "0 ask-1 ask found" "a re-run names the ask the first filed"
OUT=$(STUB_ASK_RC=3 GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" --check nope 2>&1); RC=$?
eq "$RC" "2" "an ask the writer refuses exits 2"
has "$OUT" "declares no check" "…naming why"

echo "# --- guard: a non-PR anchor is refused, nothing filed ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"","branch":"polecat/anc-1","target":"main"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor is not an open PR"
eq "$(created)" "0" "no child filed for a non-PR anchor"
has "$OUT" "not an open PR's (pull_request_pending or pull_request_head_changed)" "says why it refused"

echo "# --- guard: an open PR with no branch is refused ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"pull_request_pending","target":"main"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor names no branch"
eq "$(created)" "0" "no child filed when the branch is unknown"

echo "# --- guard: an open PR with no landing target is refused ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"pull_request_pending","branch":"polecat/anc-1"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor names no target"
eq "$(created)" "0" "no child filed when the target is unknown"

echo "# --- guard: an anchor still on the record but not an open PR is refused ---"
# merge_result alone does not prove the PR open: a hand-closed anchor keeps the
# field, and a disposed one keeps its record until the landing order
# consummates the close. Each is refused before the writer runs.
guard() { # <label> <jq edit of the anchor row> <expected message fragment>
  reset "$(printf '%s' "$ANCHOR_PR" | jq -c "$2")"
  OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
  eq "$RC" "2" "exit 2 when $1"
  has "$OUT" "$3" "…saying why"
  eq "$(created)" "0" "…and no child filed"
  eq "$(grep -c '^bd list' "$STUB_GC_LOG")" "0" "…before the writer's dedup read"
}
guard "the anchor is closed" '.[0].status = "closed"' "status='closed', not live"
guard "pr-dispose.sh has disposed the anchor" '.[0].metadata["gc.pr_close_disposition_kind"] = "not-needed"' "gc.pr_close_disposition_kind=not-needed"
guard "the anchor is superseded" '.[0].dependencies = [{id: "anc-2", dependency_type: "supersedes"}]' "superseded by anc-2"
guard "the anchor is a duplicate" '.[0].dependencies = [{id: "anc-2", dependency_type: "duplicates"}]' "superseded by anc-2"
guard "the anchor names no PR" '.[0].metadata |= del(.existing_pr, .pr_url)' "names no PR"

echo
echo "===================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
