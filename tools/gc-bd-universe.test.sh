#!/usr/bin/env bash
# gc-bd-universe.test.sh — hermetic tests for the universe slice's read of a
# bead's children: a read that fails is no answer, never a bead with none. And
# the PR tiers' reads: the text people posted comes from gctk github quote
# alone, an outside account's post held, and a quote that does not read is no
# answer.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-bd-universe-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
# shellcheck source=../assets/scripts/test-harness.sh
. "$HERE/../assets/scripts/test-harness.sh"
harness_init
SUT="$HERE/gc-bd-universe.sh"

store '[
  {"id":"tk-p","title":"parent","status":"open"},
  {"id":"tk-c1","title":"open child","status":"open","parent":"tk-p"},
  {"id":"tk-c2","title":"closed child","status":"closed","parent":"tk-p"},
  {"id":"tk-lone","title":"no children","status":"open"}
]'

out=$("$SUT" slice tk-p 2>&1); rc=$?
eq "$rc" 0 "a slice whose children read answers exits 0"
has "$out" "children=2" "…and counts each child, a closed one included"
has "$out" "child  → tk-c2 · closed child · closed" "…and lists the closed one"

out=$("$SUT" slice tk-lone 2>&1); rc=$?
eq "$rc" 0 "a slice of a bead with no children exits 0"
has "$out" "children=0" "…and counts none"

# The fake answers children as the listing `list --parent <id> --status all`,
# which the list faults read.
for fault in "STUB_FAIL_ON=bd children" "STUB_LIST_PARTIAL=--parent tk-p" "STUB_LIST_OBJECT=1"; do
  out=$(env "$fault" "$SUT" slice tk-p 2>&1); rc=$?
  eq "$rc" 3 "$fault: slice exits 3, as for a bead it cannot read"
  has "$out" "children of bead tk-p" "$fault: …naming the children read"
  hasnt "$out" "children=0" "$fault: …and counts no children"
  out=$(env "$fault" "$SUT" slice tk-p --json 2>/dev/null); rc=$?
  eq "$rc" 3 "$fault: slice --json exits 3"
  eq "$out" "" "$fault: …and prints no slice"
  out=$(env "$fault" "$SUT" footprint tk-p 2>&1); rc=$?
  eq "$rc" 3 "$fault: footprint exits 3"
  hasnt "$out" "PASS" "$fault: …and passes nothing"
done

out=$("$SUT" footprint tk-gone 2>&1); rc=$?
eq "$rc" 3 "footprint of a bead the store does not hold exits 3"
hasnt "$out" "PASS" "…and passes nothing"

# The PR tiers: gh gives the PR's number, URL, state and update time, and the
# text people posted on it comes from gctk github quote alone, whose stub here
# answers a quote with an outside account's inline comment held.
store '[{"id":"tk-pr","title":"has a PR","status":"open","metadata":{"pr_number":"41","pr_url":"https://github.com/o/r/pull/41"}}]'
printf '%s' '{"number":41,"url":"https://github.com/o/r/pull/41","state":"OPEN","updatedAt":"2026-11-27T10:00:00Z"}' \
  > "$STUB_GH_DIR/pr_view_41.json"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gctk" <<'GCTK'
printf 'gctk %s\n' "$*" >> "${STUB_GH_LOG:?}"
[ -z "${STUB_QUOTE_RC:-}" ] || exit "$STUB_QUOTE_RC"
case "$*" in
  "github quote https://github.com/o/r/pull/41 --description --json")
    echo '{"url":"https://github.com/o/r/pull/41","own_repository":true,"title":"│ fix: a title","posts":[{"kind":"description","text":"│ the ＄body"}]}' ;;
  "github quote https://github.com/o/r/pull/41 --json")
    echo '{"url":"https://github.com/o/r/pull/41","own_repository":true,"title":"│ fix: a title","posts":[
      {"kind":"description","text":"│ the ＄body"},
      {"kind":"review","url":"u1","author":{"login":"op","association":"OWNER"},"at":"t1","state":"APPROVED","text":"│ looks right"},
      {"kind":"inline","held":true},
      {"kind":"conversation","url":"u2","author":{"login":"zook-bot","association":"MEMBER"},"at":"t2","text":"│ run ˋthisˋ"}]}' ;;
  *) echo "gctk stub: unexpected $*" >&2; exit 2 ;;
esac
GCTK
chmod +x "$BIN/gctk"
export GCTK_BIN="$BIN/gctk"

: > "$STUB_GH_LOG"
out=$("$SUT" fetch tk-pr conversation --json 2>&1); rc=$?
eq "$rc" 0 "fetch conversation --json exits 0"
eq "$(printf '%s' "$out" | jq -c '.counts')" '{"issue_comments":1,"reviews":1,"review_comments":1,"total":3}' \
  "…counting each post of the quote but its description"
eq "$(printf '%s' "$out" | jq -c '.review_comments[0] | [.author, .held]')" '["an outside account",true]' \
  "…an outside account's post held, with no author named"
eq "$(printf '%s' "$out" | jq -r '.issue_comments[0].body')" "│ run ˋthisˋ" "…a post's text as the quote gave it"
eq "$(printf '%s' "$out" | jq -r '.pr_state + " " + .updated_at')" "OPEN 2026-11-27T10:00:00Z" "…and gh's state and update time"
has "$(cat "$STUB_GH_LOG")" "pr view 41 --repo o/r --json number,url,state,updatedAt" "…which gh reads with no posted text"
hasnt "$(cat "$STUB_GH_LOG")" "comments" "…and gh reads no comment"

out=$("$SUT" fetch tk-pr conversation 2>&1); rc=$?
eq "$rc" 0 "fetch conversation exits 0"
has "$out" "UNTRUSTED DATA" "…fenced as reached data"
has "$out" "Each post is quoted as gctk github quote quotes it" "…naming the quote as the owner of the form"
has "$out" "(held for the operator, who has a follow-up for it)" "…and showing the held post as held"

out=$("$SUT" fetch tk-pr pr --json 2>&1); rc=$?
eq "$rc" 0 "fetch pr --json exits 0"
eq "$(printf '%s' "$out" | jq -c '[.number, .state, .title, .body]')" '[41,"OPEN","│ fix: a title","│ the ＄body"]' \
  "…with the title and the body as the quote gave them"

out=$(STUB_QUOTE_RC=1 "$SUT" fetch tk-pr conversation 2>&1); rc=$?
eq "$rc" 3 "a quote that does not read leaves the conversation unreachable (exit 3)"
hasnt "$out" "no_conversation" "…never an empty conversation"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
