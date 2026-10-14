#!/usr/bin/env bash
# Hermetic test for assets/scripts/preexisting-failure.sh — one tracker per
# failure already red on a base branch. Stubbed gc over a JSON store; no live
# city, Dolt, or network.
#
# The load-bearing case is the RETITLE. A fixer renames the tracker to name the
# fix, so a lookup that matches only the title loses it, and the next gate to
# meet the red files a duplicate P1 while the fix is in review. The lookup
# matches the key stamped in the create, which a retitle leaves in place. The
# second is DRIFT: two gates that type their own tokens for one lint finding
# ("SC1087 gc-helm.sh", "SC1087 in gc-helm.sh") never meet, so the key is
# derived from the failure and a hand-typed one is refused. The third is a
# TITLE that merely contains the key ("Pre-existing failure:
# TestReconcileSessionBeads", "Fix TestFoo flake"): a bug is the key's tracker
# only by its stamp, so none of those is taken for it. The fourth is a FOLD: a
# triage closes trackers into a batch that clears them, and the batch carries
# no stamp, so a lookup that reads only live trackers files the red again while
# the batch is still open. The lookup follows the most recently closed
# tracker's gc.superseded_by to the live bead that carries the failure, and a
# tracker that was fixed or ruled not needed still lets the next red file.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/preexisting-failure.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-preexisting-failure-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"

# ── gc stub ──────────────────────────────────────────────────────────
# A JSON bead store with the list/create/show surface the script uses. List
# filters the way bd does: --status takes one comma list, --title-contains is a
# case-insensitive substring, --metadata-field is an exact match, and
# --closed-after compares the close time. --metadata rides the create, as bd
# merges it. Failure shapes:
#   STUB_LIST_FAIL     list exits non-zero
#   STUB_LIST_EMPTY    list exits 0 with empty stdout (bd's fail-open shape)
#   STUB_LIST_OBJECT   list answers an error object at exit 0
#   STUB_LIST_IGNORE   a filter the list silently drops: metadata-field or
#                      status
#   STUB_CREATE_FAIL   create refuses and files nothing
#   STUB_CREATE_NO_ID  create files the bead but answers an empty id
#   STUB_CREATE_DROP_META  create files the bead without its metadata
#   STUB_CREATE_META   create files the bead with this metadata instead
#   STUB_SHOW_FAILS    the first N shows fail, in the STUB_SHOW_SHAPE shape:
#                      exit (non-zero, nothing on stdout), empty (exit 0,
#                      nothing on stdout), object (an error object at exit 0)
#                      or other (the bead's row under another bead's id)
#   STUB_SHOW_FAIL_ID  every show of this id fails, in the same shapes
# A show of an id the store does not hold answers bd's error object at exit 1,
# or at STUB_SHOW_MISSING_RC.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
STORE="${STUB_STORE:?}"
printf '%s\n' "$*" >> "${STUB_LOG:?}"
[ "${1:-}" = "bd" ] || exit 0
shift
case "${1:-}" in
  list)
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "bd: down" >&2; exit 1; }
    [ -n "${STUB_LIST_EMPTY:-}" ] && exit 0
    [ -n "${STUB_LIST_OBJECT:-}" ] && { echo '{"error":"database is locked"}'; exit 0; }
    shift
    st=""; ty=""; tc=""; after=""; fields=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) st="${1#--status=}" ;;
        --status|-s) shift; st="${1:-}" ;;
        --type=*) ty="${1#--type=}" ;;
        --type|-t) shift; ty="${1:-}" ;;
        --title-contains) shift; tc="${1:-}" ;;
        --title-contains=*) tc="${1#--title-contains=}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
        --metadata-field=*) fields+=("${1#--metadata-field=}") ;;
        --closed-after) shift; after="${1:-}" ;;
        --closed-after=*) after="${1#--closed-after=}" ;;
      esac
      shift || true
    done
    ign="${STUB_LIST_IGNORE:-}"
    out=$(cat "$STORE")
    if [ -n "$st" ] && [ "$ign" != "status" ]; then
      out=$(printf '%s' "$out" | jq -c --arg st ",$st," '[ .[] | select((.status // "open") as $s | $st | contains("," + $s + ",")) ]')
    fi
    [ -n "$ty" ] && out=$(printf '%s' "$out" | jq -c --arg t "$ty" '[ .[] | select((.issue_type // "") == $t) ]')
    [ -n "$tc" ] && out=$(printf '%s' "$out" | jq -c --arg t "$tc" '[ .[] | select((.title // "") | ascii_downcase | contains($t | ascii_downcase)) ]')
    if [ "$ign" != "metadata-field" ]; then
      for f in ${fields[@]+"${fields[@]}"}; do
        out=$(printf '%s' "$out" | jq -c --arg k "${f%%=*}" --arg v "${f#*=}" '[ .[] | select(((.metadata // {})[$k] // "") == $v) ]')
      done
    fi
    [ -n "$after" ] && out=$(printf '%s' "$out" | jq -c --arg a "$after" '[ .[] | select((.closed_at // "") >= $a) ]')
    printf '%s\n' "$out" ;;
  show)
    shift; id="${1:-}"
    fail=""
    if [ -n "${STUB_SHOW_FAILS:-}" ]; then
      c=$(cat "$STUB_SEQ.show" 2>/dev/null || echo 0); c=$((c + 1)); printf '%s' "$c" > "$STUB_SEQ.show"
      [ "$c" -le "$STUB_SHOW_FAILS" ] && fail=1
    fi
    [ -n "${STUB_SHOW_FAIL_ID:-}" ] && [ "$id" = "$STUB_SHOW_FAIL_ID" ] && fail=1
    if [ -n "$fail" ]; then
      case "${STUB_SHOW_SHAPE:-exit}" in
        exit)   echo "bd: database is locked" >&2; exit 1 ;;
        empty)  exit 0 ;;
        object) echo '{"error":"database is locked"}'; exit 0 ;;
        other)  jq -c --arg id "$id" '[ .[] | select(.id == $id) | .id = "tk-elsewhere" ]' "$STORE"; exit 0 ;;
      esac
    fi
    out=$(jq -c --arg id "$id" '[ .[] | select(.id == $id) ]' "$STORE")
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      echo '{"error":"no issues found matching the provided IDs"}'
      exit "${STUB_SHOW_MISSING_RC:-1}"
    else
      printf '%s\n' "$out"
    fi ;;
  create)
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo "bd: create refused" >&2; exit 1; }
    shift
    title=""; body=""; design=""; ty="task"; prio=""; meta="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="${1:-}" ;;
        --title=*) title="${1#--title=}" ;;
        -d|--description) shift; body="${1:-}" ;;
        --design) shift; design="${1:-}" ;;
        --type|-t) shift; ty="${1:-}" ;;
        --type=*) ty="${1#--type=}" ;;
        --priority|-p) shift; prio="${1:-}" ;;
        --priority=*) prio="${1#--priority=}" ;;
        --metadata) shift; meta="${1:-}" ;;
      esac
      shift || true
    done
    [ -n "${STUB_CREATE_DROP_META:-}" ] && meta="{}"
    [ -n "${STUB_CREATE_META:-}" ] && meta="$STUB_CREATE_META"
    n=$(cat "${STUB_SEQ:?}" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    jq -c --arg id "tk-new$n" --arg t "$title" --arg d "$body" --arg g "$design" \
          --arg ty "$ty" --arg p "$prio" --argjson m "$meta" \
      '. + [{id: $id, status: "open", issue_type: $ty, priority: $p, title: $t,
             description: $d, design: $g, metadata: $m, closed_at: null}]' \
      "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
    if [ -n "${STUB_CREATE_NO_ID:-}" ]; then printf '{"id":""}\n'; else printf '{"id":"tk-new%s"}\n' "$n"; fi ;;
esac
exit 0
STUB
chmod +x "$BIN/gc"

export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/store.json" STUB_LOG="$TMP/gc.log" STUB_SEQ="$TMP/seq"

# bead <id> <status> <type> <title> [<metadata json>] [<closed_at>]
bead() {
  jq -nc --arg id "$1" --arg st "$2" --arg ty "$3" --arg t "$4" \
        --argjson m "${5:-null}" --arg c "${6:-}" \
    '{id: $id, status: $st, issue_type: $ty, title: $t, metadata: $m,
      closed_at: (if $c == "" then null else $c end)}'
}
# store <bead json>... — reset the store, the call log and the id sequence.
store() {
  local IFS=,
  printf '[%s]\n' "$*" > "$STUB_STORE"
  : > "$STUB_LOG"; rm -f "$STUB_SEQ" "$STUB_SEQ.show"
}
run() {
  OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
creates() { grep -c '^bd create' "$STUB_LOG"; }
shows() { grep -c '^bd show' "$STUB_LOG"; }
field() { jq -r --arg id "$1" ".[] | select(.id == \$id) | $2" "$STUB_STORE"; }
# closed <id> <closed_at> <metadata json> [<close reason>] [<notes>] — a closed
# bead carrying the close reason and the notes bd shows for it.
closed() {
  jq -nc --arg id "$1" --arg c "$2" --argjson m "$3" --arg r "${4:-}" --arg n "${5:-}" \
    '{id: $id, status: "closed", issue_type: "bug", title: "A closed bead", metadata: $m,
      closed_at: $c, close_reason: $r, notes: $n}'
}
# ptr <key> <successor> — the metadata bead-rehome.sh leaves on a bead it closed
# into <successor>, with the tracker stamp for <key> when <key> is not empty.
ptr() {
  jq -nc --arg k "$1" --arg s "$2" \
    '(if $k == "" then {} else {failure_key: $k} end)
     + {"gc.superseded_by": $s, "gc.superseded_by_store": "rig:gc-toolkit"}'
}
# reason <kind phrase> <successor> — the close reason bead-rehome.sh writes.
reason() { printf '%s %s in rig:gc-toolkit — closed by a triage sitting' "$1" "$2"; }

echo "# key: one failure, one key"
run key --test TestReconcile/drain_ack_async
eq "$RC/$OUT" "0/TestReconcile" "a Go subtest suffix is dropped at the first slash"
run key --test "    --- FAIL: TestReconcile/other_case (0.21s)"
eq "$RC/$OUT" "0/TestReconcile" "a pasted --- FAIL line yields the same function key"
run key --test test_widget_rebase
eq "$RC/$OUT" "0/test_widget_rebase" "a pytest function is its own key"
run key --test assets/scripts/pr-facts.test.sh
eq "$RC" "2" "a suite path is refused as a test function"
has "$ERR" "--target" "the refusal names --target for a suite file"
run key --test timeout
eq "$RC" "2" "a word that is no test function is refused"
run key --target ./assets//scripts/pr-facts.test.sh/
eq "$RC/$OUT" "0/assets/scripts/pr-facts.test.sh" "a target path is spelled repo-relative: no ./, no //, no trailing /"
run key --target internal/api/genclient:14:2
eq "$RC/$OUT" "0/internal/api/genclient" "a trailing :line:col is dropped from a target"
run key --lint ShellCheck ./assets/scripts/gc-helm.sh:120:5
A="$OUT"
run key --lint shellcheck assets/scripts/gc-helm.sh:88
eq "$A" "shellcheck assets/scripts/gc-helm.sh" "a lint key is the linter, lower-cased, and the flagged file's path"
eq "$OUT" "$A" "two lint findings in one file, spelled two ways, meet at one key"
run key --lint "go vet" services/helm
eq "$RC/$OUT" "0/go-vet services/helm" "a two-word linter is joined into one word"
run key --lint doc-filing docs/design-convoy.md:1:
eq "$RC/$OUT" "0/doc-filing docs/design-convoy.md" "a learned-rule finding keys on the rule and the file"
run key --target "<repo-relative path>"
eq "$RC" "2" "an unsubstituted placeholder is refused, never keyed"
run key --target /etc/hosts
eq "$RC" "2" "an absolute path outside the checkout is refused"
run key --target ../elsewhere/x.sh
eq "$RC" "2" "a path that climbs out of the checkout is refused"
run key --lint shellcheck
eq "$RC" "2" "--lint without a path is a usage error"
mkdir -p "$TMP/repo/sub"
git -C "$TMP/repo" init -q 2>/dev/null
TOP=$(git -C "$TMP/repo" rev-parse --show-toplevel)
OUT=$(cd "$TMP/repo" && "$SUT" key --target "$TOP/sub/x.sh:3" 2>/dev/null); RC=$?
eq "$RC/$OUT" "0/sub/x.sh" "an absolute path inside the checkout is made repo-relative"

echo "# find: the stamp alone, never a title"
store "$(bead tk-fix open bug 'Reconcile scans the process table only when a prune consults it' '{"failure_key":"TestReconcile"}')"
run find TestReconcile
eq "$RC/$OUT" "0/tk-fix" "a RETITLED tracker is found by its stamp"
hasnt "$(cat "$STUB_LOG")" "--title-contains" "the lookup never lists by title"
store "$(bead tk-old in_progress bug 'Pre-existing failure: TestReconcile — misses the async window')"
run find TestReconcile
eq "$RC/$OUT" "0/" "an unstamped bug titled with the key is not its tracker"
store "$(bead tk-long open bug 'Pre-existing failure: TestReconcileSessionBeads_drain')"
run find TestReconcile
eq "$RC/$OUT" "0/" "a title naming a longer test function is not the tracker of its prefix"
store "$(bead tk-gen open bug 'Pre-existing failure: internal/api/genclient')"
run find internal/api
eq "$RC/$OUT" "0/" "a title naming a path below the key is not the key's tracker"
store "$(bead tk-flake open bug 'Fix TestFoo flake by raising timeout')"
run find TestFoo
eq "$RC/$OUT" "0/" "a bug whose title merely mentions the key is not its tracker"
store "$(bead tk-other open bug 'Pre-existing failure: TestReconcileAll' '{"failure_key":"TestReconcileAll"}')"
run find TestReconcile
eq "$RC/$OUT" "0/" "a bead stamped with another key is not this key's tracker, though its title contains it"
run find TestReconcileAll
eq "$RC/$OUT" "0/tk-other" "the same bead is its own key's tracker"
store "$(bead tk-old open bug 'Pre-existing failure: TestReconcile')" \
      "$(bead tk-fix open bug 'Fix the reconcile window' '{"failure_key":"TestReconcile"}')"
run find TestReconcile
eq "$OUT" "tk-fix" "the stamped tracker is found, never an unstamped bug titled with the key"
for st in open in_progress blocked deferred hooked pinned; do
  store "$(bead tk-live "$st" bug 'Renamed by its fixer' '{"failure_key":"TestReconcile"}')"
  run find TestReconcile
  eq "$OUT" "tk-live" "a $st tracker is live"
done
store "$(bead tk-done closed bug 'Renamed by its fixer' '{"failure_key":"TestReconcile"}' 2026-10-09T08:00:00Z)"
run find TestReconcile
eq "$RC/$OUT" "0/" "a closed tracker is not live"
run find TestReconcile --closed-after 2026-10-04
eq "$RC/$OUT" "0/tk-done" "the landed-fix check finds the closed tracker by its stamp"
run find TestReconcile --closed-after 2026-10-10
eq "$RC/$OUT" "0/" "a tracker closed before the cutoff is not a recent fix"
store "$(bead tk-done closed bug 'Pre-existing failure: TestReconcile' null 2026-10-09T08:00:00Z)"
run find TestReconcile --closed-after 2026-10-04
eq "$RC/$OUT" "0/" "the landed-fix check takes no unstamped closed bug by its title"
run find TestReconcile --closed-after "last week"
eq "$RC" "2" "--closed-after takes a date"

echo "# find: an unread store is unknown, never none"
store "$(bead tk-fix open bug 'Renamed' '{"failure_key":"TestReconcile"}')"
STUB_LIST_FAIL=1 run find TestReconcile
eq "$RC/$OUT" "1/" "a list that exits non-zero fails the lookup"
STUB_LIST_EMPTY=1 run find TestReconcile
eq "$RC/$OUT" "1/" "an empty stdout fails the lookup"
STUB_LIST_OBJECT=1 run find TestReconcile
eq "$RC/$OUT" "1/" "an error object fails the lookup"
has "$ERR" "not proof the tracker is missing" "the failure says why it is not an all-clear"
store "$(bead tk-stranger open bug 'Unrelated bug' '{"failure_key":"TestOther"}')"
STUB_LIST_IGNORE=metadata-field run find TestReconcile
eq "$OUT" "" "a listing that dropped the stamp filter cannot pass a stranger off as the tracker"
store "$(bead tk-twin open bug 'Pre-existing failure: TestReconcile')"
STUB_LIST_IGNORE=metadata-field run find TestReconcile
eq "$OUT" "" "nor an unstamped bug titled with the key"
store "$(bead tk-done closed bug 'Renamed' '{"failure_key":"TestReconcile"}' 2026-10-09T08:00:00Z)"
STUB_LIST_IGNORE=status run find TestReconcile
eq "$OUT" "" "a listing that dropped the status filter cannot pass a closed tracker off as live"

echo "# find and file take only a key the script derives"
store
for k in "SC1087 in gc-helm.sh" "SC1087 gc-helm.sh" "<failing test name>" "" "shellcheck  x.sh" "shellcheck " "./x.sh"; do
  run find "$k"
  eq "$RC" "2" "find refuses the hand-typed key '$k'"
done
run file "SC1087 in gc-helm.sh" --message "log"
eq "$RC/$(creates)" "2/0" "file refuses a hand-typed key and files nothing"

echo "# file: the stamp rides the create"
store
run file "shellcheck assets/scripts/gc-helm.sh" --message 'SC1087 at line 120: `$x[1]` reads as $x then [1]'
eq "$RC/$OUT" "0/tk-new1" "file prints the new tracker's id"
eq "$(creates)" "1" "exactly one bead is created"
eq "$(field tk-new1 .title)" "Pre-existing failure: shellcheck assets/scripts/gc-helm.sh" "the title carries the key"
eq "$(field tk-new1 .issue_type)/$(field tk-new1 .priority)" "bug/1" "it is a P1 bug"
eq "$(field tk-new1 '.metadata.failure_key')" "shellcheck assets/scripts/gc-helm.sh" "the key is stamped as failure_key"
hasnt "$(cat "$STUB_LOG")" "bd update" "the stamp rides the create, not a second write"
has "$(field tk-new1 .description)" 'SC1087 at line 120: `$x[1]` reads as $x then [1]' "the evidence is the body, verbatim"
has "$(field tk-new1 .description)" '`failure_key` metadata, `shellcheck assets/scripts/gc-helm.sh`' "the body names the key a gate finds it by"
eq "$(field tk-new1 .design)" "" "nothing is filed in .design, which no reader reads"
REGISTERED=$(sed -n '/^# The metadata-key registry/,$p' "$HERE/../../lifecycle/lifecycle.toml" \
  | sed 's/#.*//' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
UNREGISTERED=$(field tk-new1 '.metadata | keys[]' | grep -Fxv -f <(printf '%s\n' "$REGISTERED") | tr '\n' ' ') || true
eq "$UNREGISTERED" "" "every metadata key the filing writes is registered in lifecycle.toml"

echo "# file: the retitled tracker is still the key's tracker"
jq -c 'map(if .id == "tk-new1" then .title = "Quote the array reads in gc-helm.sh" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
run find "shellcheck assets/scripts/gc-helm.sh"
eq "$OUT" "tk-new1" "after its fixer retitles it, the lookup still finds it"
: > "$STUB_LOG"
run file "shellcheck assets/scripts/gc-helm.sh" --message "seen again"
eq "$RC/$OUT/$(creates)" "0/tk-new1/0" "a second filing files nothing and prints the live tracker"
has "$ERR" "already tracked as tk-new1" "it says the key was already tracked"

echo "# file: a live twin found at filing time, a closed one not"
store "$(bead tk-twin blocked bug 'Renamed by its fixer' '{"failure_key":"TestReconcile"}')"
run file TestReconcile --message "seen"
eq "$RC/$OUT/$(creates)" "0/tk-twin/0" "a live twin filed since the caller's lookup is found by its stamp, not duplicated"
store "$(bead tk-old blocked bug 'Pre-existing failure: TestReconcile — misses the window')"
run file TestReconcile --message "seen"
eq "$RC/$OUT/$(creates)" "0/tk-new1/1" "an unstamped bug titled with the key does not stop the filing"
eq "$(field tk-new1 '.metadata.failure_key')" "TestReconcile" "the tracker filed beside it carries the stamp"
store "$(bead tk-done closed bug 'Fixed it' '{"failure_key":"TestReconcile"}' 2026-10-09T08:00:00Z)"
run file TestReconcile --message "red again after the fix landed"
eq "$RC/$(creates)" "0/1" "a closed tracker with no successor does not suppress the filing: a red that outlives a fix is new"

echo "# find and file: a tracker a fold closed answers through the live bead its failure moved to"
K="shellcheck assets/scripts/gc-helm.sh"
store "$(closed tk-folded 2026-10-09T07:17:10Z "$(ptr "$K" tk-batch)" "$(reason "folded into" tk-batch)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')"
run find "$K"
eq "$RC/$OUT" "0/tk-batch" "a closed twin folded into a live batch answers with the batch"
has "$ERR" "closed tracker tk-folded moved the failure to tk-batch" "the answer names the closed tracker it came through"
hasnt "$(cat "$STUB_LOG")" "--title-contains" "the successor is reached by its pointer, never by a title"
run file "$K" --message "seen again"
eq "$RC/$OUT/$(creates)" "0/tk-batch/0" "a closed twin with a live successor files nothing"
has "$ERR" "tracked by tk-batch" "the filing says which bead tracks the key"
for st in in_progress blocked deferred hooked pinned; do
  store "$(closed tk-folded 2026-10-09T07:17:10Z "$(ptr "$K" tk-batch)" "$(reason "folded into" tk-batch)")" \
        "$(bead tk-batch "$st" task 'batch: clear the pre-existing shellcheck tracker set')"
  run find "$K"
  eq "$OUT" "tk-batch" "a $st successor is live"
done
store "$(closed tk-fixed 2026-10-09T08:00:00Z "{\"failure_key\":\"$K\"}" "Fixed on main")"
run find "$K"
eq "$RC/$OUT" "0/" "a closed twin with no successor tracks nothing"
run file "$K" --message "red again after the fix landed"
eq "$RC/$(creates)" "0/1" "a closed twin with no successor still files"

echo "# find: the chain runs through every bead that closed onward"
store "$(closed tk-folded 2026-10-09T07:17:10Z "$(ptr "$K" tk-batch1)" "$(reason "folded into" tk-batch1)")" \
      "$(closed tk-batch1 2026-10-10T07:00:00Z "$(ptr "" tk-batch2)" "$(reason "re-homed to" tk-batch2)")" \
      "$(bead tk-batch2 open task 'batch: the lint debt, re-homed')"
run find "$K"
eq "$RC/$OUT" "0/tk-batch2" "a batch that re-homed onward passes the failure to the bead it moved to"
has "$ERR" "tk-folded moved the failure to tk-batch2" "the answer names the tracker the chain began at"
store "$(closed tk-folded 2026-10-09T07:17:10Z "$(ptr "$K" tk-batch1)" "$(reason "folded into" tk-batch1)")" \
      "$(closed tk-batch1 2026-10-10T07:00:00Z '{"gc.work_outcome":"shipped"}' "Merged to main")"
run find "$K"
eq "$RC/$OUT" "0/" "a batch that landed ends the chain: the failure was fixed there"
run file "$K" --message "red after the batch landed"
eq "$RC/$(creates)" "0/1" "so a red after the batch landed is filed"
store "$(closed tk-dup 2026-10-10T07:00:00Z "$(ptr "$K" tk-fix)" "$(reason "duplicate of" tk-fix)")" \
      "$(closed tk-fix 2026-10-10T06:00:00Z '{"merge_result":"merged"}' "Merged")"
run find "$K"
eq "$RC/$OUT" "0/" "a duplicate of a fix that merged ends at the fix: nothing tracks the key"
store "$(closed tk-up 2026-10-10T07:00:00Z "$(ptr "$K" tk-fixpr)" "$(reason "fixed upstream by" tk-fixpr)")" \
      "$(bead tk-fixpr in_progress bug 'Quote the array reads in gc-helm.sh')"
run find "$K"
eq "$RC/$OUT" "0/tk-fixpr" "a fixed-upstream pointer to a fix still in flight answers with the fix"

echo "# find and file: a mixed run files its new finding, one key per flagged file"
KA="shellcheck assets/scripts/liveness-sweep-precheck.test.sh"
KB="shellcheck assets/scripts/liveness-sweep.test.sh"
store "$(closed tk-folded 2026-10-09T07:18:35Z "$(ptr "$KA" tk-batch)" "$(reason "folded into" tk-batch)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')"
run find "$KA"
eq "$OUT" "tk-batch" "the folded file's finding answers with the batch"
run find "$KB"
eq "$RC/$OUT" "0/" "the other file's finding is tracked by nothing"
run file "$KB" --message "SC2034 at line 275: ERR appears unused"
eq "$RC/$OUT/$(creates)" "0/tk-new1/1" "the new finding is filed"
eq "$(field tk-new1 '.metadata.failure_key')" "$KB" "under its own file's key"
run file "$KA" --message "SC2120 and SC2034, seen again"
eq "$RC/$OUT/$(creates)" "0/tk-batch/1" "the folded finding in the same run files nothing"

echo "# find: the most recently closed tracker decides"
store "$(closed tk-old 2026-10-09T09:01:03Z "$(ptr "$K" tk-batch)" "$(reason "folded into" tk-batch)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')" \
      "$(closed tk-new 2026-10-10T06:35:03Z "$(ptr "$K" tk-fix)" "$(reason "duplicate of" tk-fix)")" \
      "$(closed tk-fix 2026-10-10T06:00:00Z '{"merge_result":"merged"}' "Merged")"
run find "$K"
eq "$RC/$OUT" "0/" "an older twin folded into a live batch does not outrank a newer twin whose fix landed"
run file "$K" --message "red after the macOS fix landed"
eq "$RC/$(creates)" "0/1" "so the recurrence is filed"
store "$(closed tk-old 2026-10-09T08:00:00Z "{\"failure_key\":\"$K\"}" "Fixed on main")" \
      "$(closed tk-new 2026-10-10T08:00:00Z "$(ptr "$K" tk-batch)" "$(reason "folded into" tk-batch)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')"
run find "$K"
eq "$OUT" "tk-batch" "a newer twin folded into a live batch outranks an older fixed one"
store "$(bead tk-live open bug 'Renamed by its fixer' "{\"failure_key\":\"$K\"}")" \
      "$(closed tk-folded 2026-10-10T08:00:00Z "$(ptr "$K" tk-batch)" "$(reason "folded into" tk-batch)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')"
run find "$K"
eq "$OUT" "tk-live" "a live tracker answers before any closed twin's successor"
hasnt "$ERR" "moved the failure" "and nothing says it came through a chain"

echo "# find and file: a not-needed ruling names its evidence, never a filing"
store "$(closed tk-ruled 2026-10-10T08:00:00Z "$(ptr "$K" tk-visit)" "$(reason "not needed, per" tk-visit)")" \
      "$(bead tk-visit open task 'visit: the gc-helm.sh shellcheck trackers' '{"task_kind":"visit"}')"
run find "$K"
eq "$RC/$OUT" "0/" "a tracker ruled not needed is not tracked by the open visit that ruled it"
run file "$K" --message "red again after the ruling"
eq "$RC/$(creates)" "0/1" "so a red after the ruling is filed"
store "$(closed tk-ruled 2026-10-10T08:00:00Z "$(ptr "$K" tk-visit)" "Closed" \
          "Disposition recorded 2026-10-10T09:00Z: $(reason "not needed, per" tk-visit). (Pointer added after the close; the close reason above predates it.)")" \
      "$(bead tk-visit open task 'visit: the gc-helm.sh shellcheck trackers' '{"task_kind":"visit"}')"
run find "$K"
eq "$RC/$OUT" "0/" "a ruling recorded in the note of an earlier close ends the chain too"
store "$(closed tk-moved 2026-10-10T08:00:00Z "$(ptr "$K" tk-batch)" "Closed" \
          "Disposition recorded 2026-10-10T09:00Z: $(reason "not needed, per" tk-other). (Pointer added after the close; the close reason above predates it.)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')"
run find "$K"
eq "$OUT" "tk-batch" "a ruling that names another bead does not end this pointer's chain"

echo "# the not-needed reading matches what bead-rehome.sh writes"
REHOME="$HERE/bead-rehome.sh"
# shellcheck disable=SC2016  # the dollar signs are bead-rehome.sh's own text
for line in 'PHRASE="not needed, per"' 'REASON="$PHRASE $SUCCESSOR in $SUCCESSOR_STORE"' \
            'Disposition recorded $(date -u +%Y-%m-%dT%H:%MZ): $REASON.'; do
  if grep -qF -- "$line" "$REHOME"; then
    ok "bead-rehome.sh writes: $line"
  else
    bad "bead-rehome.sh no longer writes: $line (tracked_by reads a not-needed close by it)"
  fi
done

echo "# find and file: a chain that cannot be read is unknown, one that names nothing tracks nothing"
store "$(closed tk-folded 2026-10-09T07:17:10Z "$(ptr "$K" tk-batch)" "$(reason "folded into" tk-batch)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')"
for shape in exit empty object other; do
  STUB_SHOW_FAIL_ID=tk-batch STUB_SHOW_SHAPE=$shape run find "$K"
  eq "$RC/$OUT" "1/" "a successor read that fails ($shape) fails the lookup"
done
has "$ERR" "not proof the tracker is missing" "the failure says why it is not an all-clear"
STUB_SHOW_FAIL_ID=tk-folded run find "$K"
eq "$RC/$OUT" "1/" "a tracker read that fails fails the lookup"
STUB_SHOW_FAIL_ID=tk-batch run file "$K" --message "seen"
eq "$RC/$OUT/$(creates)" "1//0" "an unread chain files nothing"
store "$(closed tk-folded 2026-10-09T07:17:10Z "$(ptr "$K" tk-gone)" "$(reason "folded into" tk-gone)")"
for rc in 1 0; do
  STUB_SHOW_MISSING_RC=$rc run find "$K"
  eq "$RC/$OUT" "0/" "a pointer to a bead the store does not hold tracks nothing (bd answers at exit $rc)"
done
has "$ERR" "tk-folded names tk-gone in gc.superseded_by, but the store holds no such bead" "the dangling pointer is reported"
run file "$K" --message "seen"
eq "$RC/$(creates)" "0/1" "so the red is filed"
store "$(closed tk-a 2026-10-10T08:00:00Z "$(ptr "$K" tk-b)" "$(reason "folded into" tk-b)")" \
      "$(closed tk-b 2026-10-10T07:00:00Z "$(ptr "" tk-a)" "$(reason "re-homed to" tk-a)")"
run find "$K"
eq "$RC/$OUT" "0/" "a chain that loops tracks nothing"
has "$ERR" "loops back to tk-a" "the loop is reported"
ROWS=("$(closed tk-c0 2026-10-10T08:00:00Z "$(ptr "$K" tk-c1)" "$(reason "folded into" tk-c1)")")
for i in $(seq 1 21); do
  ROWS+=("$(closed "tk-c$i" 2026-10-10T07:00:00Z "$(ptr "" "tk-c$((i + 1))")" "$(reason "folded into" "tk-c$((i + 1))")")")
done
ROWS+=("$(bead tk-c22 open task 'the end of a long chain')")
store "${ROWS[@]}"
run find "$K"
eq "$RC/$OUT" "0/" "a chain past the pointer cap tracks nothing"
has "$ERR" "runs past 20 pointers" "the cap is reported"
ROWS=("$(closed tk-c0 2026-10-10T08:00:00Z "$(ptr "$K" tk-c1)" "$(reason "folded into" tk-c1)")")
for i in $(seq 1 19); do
  ROWS+=("$(closed "tk-c$i" 2026-10-10T07:00:00Z "$(ptr "" "tk-c$((i + 1))")" "$(reason "folded into" "tk-c$((i + 1))")")")
done
ROWS+=("$(bead tk-c20 open task 'the end of a chain at the cap')")
store "${ROWS[@]}"
run find "$K"
eq "$OUT" "tk-c20" "a chain of exactly the cap reaches its live bead"

echo "# find: a listing that dropped a filter cannot pass another bead off as the key's"
store "$(closed tk-stranger 2026-10-11T08:00:00Z "$(ptr TestOther tk-batch)" "$(reason "folded into" tk-batch)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')"
STUB_LIST_IGNORE=metadata-field run find "$K"
eq "$OUT" "" "another key's closed tracker is not followed for this key"
store "$(closed tk-folded 2026-10-09T07:17:10Z "$(ptr "$K" tk-batch)" "$(reason "folded into" tk-batch)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')"
STUB_LIST_IGNORE=status run find "$K"
eq "$OUT" "tk-batch" "a closed tracker a listing returned as live is not taken for a live one"
store "$(closed tk-folded 2026-10-09T07:17:10Z "$(ptr "$K" tk-batch)" "$(reason "folded into" tk-batch)")" \
      "$(bead tk-batch open task 'batch: clear the pre-existing shellcheck tracker set')" \
      "$(bead tk-gone tombstone bug 'Renamed by its fixer' "{\"failure_key\":\"$K\"}" 2026-10-12T08:00:00Z)"
STUB_LIST_IGNORE=status run find "$K"
eq "$OUT" "tk-batch" "a bead in a status the closed listing was not asked for does not decide the chain"
run find "$K" --closed-after 2026-10-04
eq "$RC/$OUT" "0/tk-folded" "the landed-fix check prints the closed tracker and follows no chain"

echo "# file: the title"
store
run file TestReconcile --summary "  misses the
async window  " --message "log"
eq "$(field "$OUT" .title)" "Pre-existing failure: TestReconcile — misses the async window" "a summary joins the title after the key, on one line"
store
LONG=$(printf 'word%.0s ' $(seq 1 80))
run file TestReconcile --summary "$LONG" --message "log"
T=$(field "$OUT" .title)
case "$T" in "Pre-existing failure: TestReconcile — word"*"…") ok "a long summary is cut at a word, after the whole key" ;; *) bad "a long summary is cut at a word, after the whole key (got '$T')" ;; esac
# jq counts characters in every locale, where ${#T} counts bytes under C.
TLEN=$(field "$OUT" '.title | length')
[ -n "$T" ] && [ "${TLEN:-0}" -le 200 ] && ok "the title fits 200 characters" || bad "the title is ${TLEN:-0} characters, want 1 to 200"
store
run file TestReconcile --summary "<short description>" --message "log"
eq "$RC/$(creates)" "2/0" "a summary still carrying its placeholder files nothing"
run file TestReconcile --message "   "
eq "$RC/$(creates)" "2/0" "a filing with no evidence files nothing"
run file TestReconcile
eq "$RC/$(creates)" "2/0" "--message is required"

echo "# file: fail closed"
store
STUB_LIST_FAIL=1 run file TestReconcile --message "log"
eq "$RC/$(creates)" "1/0" "an unread lookup files nothing"
store
STUB_CREATE_FAIL=1 run file TestReconcile --message "log"
eq "$RC/$OUT" "1/" "a refused create fails the filing"
store
STUB_CREATE_NO_ID=1 run file TestReconcile --message "log"
eq "$RC/$OUT/$(creates)" "0/tk-new1/1" "a create that answers no id is recovered by its stamp, not re-filed"
has "$ERR" "returned no id" "the recovery is reported"
store
STUB_CREATE_DROP_META=1 run file TestReconcile --message "log"
eq "$RC/$OUT" "1/" "a read-back that shows the stamp missing fails the filing"
has "$ERR" "--set-metadata \"failure_key=TestReconcile\"" "the failure names the repair"
store
STUB_CREATE_META='{"failure_key":"TestOther"}' run file TestReconcile --message "log"
eq "$RC/$OUT" "1/" "a read-back that shows another key fails the filing"
has "$ERR" "read back as 'TestOther'" "the failure names the key it read"

echo "# file: a read-back that fails is not a failed filing"
store
STUB_SHOW_FAILS=1 run file TestReconcile --message "log"
eq "$RC/$OUT/$(creates)/$(shows)" "0/tk-new1/1/2" "one failed read is retried, and the retry confirms the stamp"
hasnt "$ERR" "could not read" "a retry that reads the stamp warns nothing"
for shape in exit empty object other; do
  store
  STUB_SHOW_FAILS=2 STUB_SHOW_SHAPE=$shape run file TestReconcile --message "log"
  eq "$RC/$OUT/$(creates)" "0/tk-new1/1" "two failed reads ($shape) still print the filed tracker"
  has "$ERR" "could not read tk-new1 back" "the unconfirmed stamp is reported ($shape)"
done
has "$ERR" "--set-metadata \"failure_key=TestReconcile\"" "the warning names the repair"
store
STUB_SHOW_FAILS=1 STUB_CREATE_DROP_META=1 run file TestReconcile --message "log"
eq "$RC/$OUT" "1/" "a retry that reads the stamp missing still fails the filing"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
