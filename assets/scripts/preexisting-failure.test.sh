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
# derived from the failure and a hand-typed one is refused.
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
#   STUB_LIST_IGNORE   a filter the list silently drops: metadata-field,
#                      title-contains or status
#   STUB_CREATE_FAIL   create refuses and files nothing
#   STUB_CREATE_NO_ID  create files the bead but answers an empty id
#   STUB_CREATE_DROP_META  create files the bead without its metadata
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
    if [ -n "$tc" ] && [ "$ign" != "title-contains" ]; then
      out=$(printf '%s' "$out" | jq -c --arg t "$tc" '[ .[] | select((.title // "") | ascii_downcase | contains($t | ascii_downcase)) ]')
    fi
    if [ "$ign" != "metadata-field" ]; then
      for f in ${fields[@]+"${fields[@]}"}; do
        out=$(printf '%s' "$out" | jq -c --arg k "${f%%=*}" --arg v "${f#*=}" '[ .[] | select(((.metadata // {})[$k] // "") == $v) ]')
      done
    fi
    [ -n "$after" ] && out=$(printf '%s' "$out" | jq -c --arg a "$after" '[ .[] | select((.closed_at // "") >= $a) ]')
    printf '%s\n' "$out" ;;
  show)
    shift; id="${1:-}"
    out=$(jq -c --arg id "$id" '[ .[] | select(.id == $id) ]' "$STORE")
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      echo '{"error":"no issues found matching the provided IDs"}'
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
  : > "$STUB_LOG"; rm -f "$STUB_SEQ"
}
run() {
  OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
creates() { grep -c '^bd create' "$STUB_LOG"; }
field() { jq -r --arg id "$1" ".[] | select(.id == \$id) | $2" "$STUB_STORE"; }

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

echo "# find: the stamp, then the title of an unstamped bug"
store "$(bead tk-fix open bug 'Reconcile scans the process table only when a prune consults it' '{"failure_key":"TestReconcile"}')"
run find TestReconcile
eq "$RC/$OUT" "0/tk-fix" "a RETITLED tracker is found by its stamp"
store "$(bead tk-old in_progress bug 'Pre-existing failure: TestReconcile — misses the async window')"
run find TestReconcile
eq "$RC/$OUT" "0/tk-old" "an unstamped tracker filed before the stamp is found by its title"
store "$(bead tk-task open task 'Pre-existing failure: TestReconcile — misses the async window')"
run find TestReconcile
eq "$RC/$OUT" "0/" "a title match counts only on a bug"
store "$(bead tk-other open bug 'Pre-existing failure: TestReconcileAll' '{"failure_key":"TestReconcileAll"}')"
run find TestReconcile
eq "$RC/$OUT" "0/" "a bead stamped with another key is not this key's tracker, though its title contains it"
run find TestReconcileAll
eq "$RC/$OUT" "0/tk-other" "the same bead is its own key's tracker"
store "$(bead tk-old open bug 'Pre-existing failure: TestReconcile')" \
      "$(bead tk-fix open bug 'Fix the reconcile window' '{"failure_key":"TestReconcile"}')"
run find TestReconcile
eq "$OUT" "tk-fix" "the stamped tracker is preferred over a title match"
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
eq "$OUT" "tk-done" "the landed-fix check finds an unstamped closed tracker by its title"
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
store "$(bead tk-stranger open bug 'Unrelated bug')"
STUB_LIST_IGNORE=title-contains run find TestReconcile
eq "$OUT" "" "a listing that dropped the title filter cannot either"
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
store "$(bead tk-old blocked bug 'Pre-existing failure: TestReconcile — misses the window')"
run file TestReconcile --message "seen"
eq "$RC/$OUT/$(creates)" "0/tk-old/0" "an unstamped live twin filed since the caller's lookup is found, not duplicated"
store "$(bead tk-done closed bug 'Fixed it' '{"failure_key":"TestReconcile"}' 2026-10-09T08:00:00Z)"
run file TestReconcile --message "red again after the fix landed"
eq "$RC/$(creates)" "0/1" "a closed tracker does not suppress the filing: a red that outlives a fix is new"

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
[ "${#T}" -le 200 ] && ok "the title fits 200 characters" || bad "the title is ${#T} characters"
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
eq "$RC" "1" "a stamp that did not land fails the filing"
has "$ERR" "--set-metadata \"failure_key=TestReconcile\"" "the failure names the repair"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
