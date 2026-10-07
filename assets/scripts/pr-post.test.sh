#!/usr/bin/env bash
# pr-post.test.sh — hermetic coverage of the city's single PR posting helper:
# each verb makes the gh call its callers made, with the provenance mark
# appended; the own-def predicate tells the city's own post from feedback on
# every shape the readers hand it; and no file in the pack posts to a pull
# request any other way. A gh stub records each call's argv and the body it
# would post; no network, no city.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/pr-post.sh"
REPO="$(cd "$HERE/../.." && pwd)"
DETECTOR="$REPO/tools/lint-learned.d/pr-post-bypass.sh"
[ -x "$SUT" ] || { echo "not found or not executable: $SUT" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 2; }

PASS=0; FAIL=0
ok()    { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad()   { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n     %s\n' "$1" "$2"; }
eq()    { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pr-post-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; mkdir -p "$BIN"
MARK='<!-- gc:city -->'

# gh stub: every call's argv lands in $GHLOG one argument per line, framed by a
# `--` line per call, and the content of a --body-file is copied to $GHBODY
# while the file still exists. $GH_RC fails the call; $GH_OUT is its stdout.
cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
{ echo "--"; printf '%s\n' "$@"; } >>"${GHLOG:?}"
prev=""
for a in "$@"; do
  [ "$prev" = "--body-file" ] && { cat "$a" >"${GHBODY:?}"; printf '%s\n' "$a" >"${GHBODY}.path"; }
  prev="$a"
done
[ -n "${GH_OUT:-}" ] && printf '%s\n' "$GH_OUT"
exit "${GH_RC:-0}"
STUB
chmod +x "$BIN/gh"

GHLOG="$TMPD/gh.log"; GHBODY="$TMPD/gh.body"
# run [VAR=VAL ...] -- <sut args...> — sets RC and OUT, resets the gh record.
run() {
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  : >"$GHLOG"; : >"$GHBODY"; rm -f "$GHBODY.path"
  OUT="$(env PATH="$BIN:$PATH" GHLOG="$GHLOG" GHBODY="$GHBODY" ${envs[@]+"${envs[@]}"} "$SUT" "$@" 2>&1)"; RC=$?
}
argv() { cat "$GHLOG"; }
calls() { grep -c '^--$' "$GHLOG"; }

echo "# mark prints the provenance marker"
run -- mark
eq "$RC" 0 "mark exits 0"
eq "$OUT" "$MARK" "mark prints the marker"

echo "# comment: gh pr comment, pinned, with the mark appended"
run GH_OUT="https://github.com/o/r/pull/12#issuecomment-1" -- comment --repo github.com/o/r --pr 12 --body "hello there"
eq "$RC" 0 "comment exits 0"
eq "$(calls)" 1 "one gh call"
has "$(argv)" "$(printf 'pr\ncomment\n12\n--repo\ngithub.com/o/r\n--body\n')" "it is gh pr comment <n> --repo <host/owner/name> --body"
has "$(argv)" "$(printf 'hello there\n\n%s' "$MARK")" "the body ends with a blank line and the mark"
has "$OUT" "issuecomment-1" "gh's output passes through, so a caller still reads the comment url"

echo "# comment --attach rides through to gh"
printf 'bytes\n' >"$TMPD/clip.mp4"
run -- comment --repo github.com/o/r --pr 12 --body "demo" --attach "$TMPD/clip.mp4"
eq "$RC" 0 "comment --attach exits 0"
has "$(argv)" "$(printf -- '--attach\n%s' "$TMPD/clip.mp4")" "the attachment is passed to gh"
has "$(argv)" "$MARK" "an attached comment is marked too"
: >"$TMPD/empty.mp4"
run -- comment --repo github.com/o/r --pr 12 --body "demo" --attach "$TMPD/empty.mp4"
eq "$RC" 1 "an empty attachment fails"
eq "$(calls)" 0 "…before anything is posted"

echo "# comment --body-file posts the file's text, marked"
printf 'line one\nline two\n' >"$TMPD/b.md"
run -- comment --repo github.com/o/r --pr 12 --body-file "$TMPD/b.md"
eq "$RC" 0 "comment --body-file exits 0"
has "$(argv)" "$(printf 'line one\nline two\n\n%s' "$MARK")" "the file's text is the body, mark last"

echo "# review: a COMMENT review only, body through a file"
printf 'Signoff verdict: approve\n\nAnchor: tk-a — check.correctness @ abc\n' >"$TMPD/v.md"
run -- review --repo github.com/o/r --pr 42 --body-file "$TMPD/v.md"
eq "$RC" 0 "review exits 0"
has "$(argv)" "$(printf 'pr\nreview\n42\n--repo\ngithub.com/o/r\n--comment\n--body-file\n')" "it is gh pr review <n> --repo <q> --comment --body-file"
hasnt "$(argv)" "--approve" "never an approval"
hasnt "$(argv)" "--request-changes" "never a change request"
has "$(cat "$GHBODY")" "Anchor: tk-a — check.correctness @ abc" "the verdict text is posted"
has "$(cat "$GHBODY")" "$MARK" "the review body carries the mark"
eq "$(cat "$TMPD/v.md")" "$(printf 'Signoff verdict: approve\n\nAnchor: tk-a — check.correctness @ abc')" "the caller's body file is left as it was"
if [ -s "$GHBODY.path" ] && [ ! -e "$(cat "$GHBODY.path")" ]; then ok "the marked temp body is removed after the post"
else bad "the marked temp body is removed after the post" "temp file '$(cat "$GHBODY.path" 2>/dev/null)' remains"; fi

echo "# reply: a thread reply mutation, marked"
run GH_OUT='{"data":{"addPullRequestReviewThreadReply":{"clientMutationId":null}}}' -- reply --host github.com --thread PRRT_abc --body "Addressed in abc12345."
eq "$RC" 0 "reply exits 0"
has "$(argv)" "$(printf 'api\ngraphql\n--hostname\ngithub.com\n-f\n')" "it is gh api graphql --hostname <host>"
# The mutation name is held in a variable: spelled as a call here, the bypass
# detector the last section runs would read this assertion as a post.
MUT="addPullRequestReviewThreadReply"
has "$(argv)" "${MUT}(input:{pullRequestReviewThreadId:\$t,body:\$b})" "the mutation is the thread reply"
has "$(argv)" "$(printf -- '-f\nt=PRRT_abc\n-f\nb=Addressed in abc12345.\n\n%s' "$MARK")" "the thread id and the marked body are its variables"
run GH_OUT="" -- reply --host github.com --thread PRRT_abc --body "x"
eq "$RC" 1 "a mutation that answers nothing is a failure"

echo "# edit: a conversation comment rewritten in place, marked"
run -- edit --repo github.com/o/r --comment 991 --body "### Visit tk-v — closed"
eq "$RC" 0 "edit exits 0"
has "$(argv)" "$(printf 'api\n--method\nPATCH\nrepos/o/r/issues/comments/991\n--hostname\ngithub.com\n-f\n')" "it is a PATCH of issues/comments/<id> on the --repo host"
has "$(argv)" "$(printf 'body=### Visit tk-v — closed\n\n%s' "$MARK")" "the new body carries the mark"

echo "# a body that already carries the mark is posted as it is"
run -- comment --repo github.com/o/r --pr 12 --body "$(printf 'x\n\n%s' "$MARK")"
eq "$(grep -c -F -- "$MARK" "$GHLOG")" 1 "the mark is not doubled"

echo "# a gh failure is exit 1 for every verb"
run GH_RC=1 -- comment --repo github.com/o/r --pr 12 --body x;            eq "$RC" 1 "comment"
run GH_RC=1 -- review --repo github.com/o/r --pr 12 --body x;             eq "$RC" 1 "review"
run GH_RC=1 GH_OUT='{}' -- reply --host github.com --thread PRRT_x --body x; eq "$RC" 1 "reply"
run GH_RC=1 -- edit --repo github.com/o/r --comment 5 --body x;           eq "$RC" 1 "edit"

echo "# usage errors are exit 2 and post nothing"
usage_case() { # <label> <args...>
  local label="$1"; shift
  run -- "$@"
  eq "$RC" 2 "$label exits 2"
  eq "$(calls)" 0 "$label posts nothing"
}
usage_case "an unknown verb"            approve --repo github.com/o/r --pr 1 --body x
usage_case "a comment with no body"     comment --repo github.com/o/r --pr 1
usage_case "--body with --body-file"    comment --repo github.com/o/r --pr 1 --body x --body-file "$TMPD/b.md"
usage_case "a whitespace-only body"     comment --repo github.com/o/r --pr 1 --body "   "
usage_case "an unqualified --repo"      comment --repo o/r --pr 1 --body x
usage_case "a non-numeric --pr"         review --repo github.com/o/r --pr main --body x
usage_case "--attach on a review"       review --repo github.com/o/r --pr 1 --body x --attach "$TMPD/clip.mp4"
usage_case "a reply with no thread"     reply --host github.com --body x
usage_case "an edit with no comment id" edit --repo github.com/o/r --body x

echo "# own-def: the city's own post, and everything else is feedback"
DEF="$("$SUT" own-def)"
own() { # <self> <since> <json> — prints true/false
  printf '%s' "$3" | jq -r --arg self "$1" --arg since "$2" "$DEF"'gc_city_own($self; $since)'
}
marked() { printf '%s' "$1" | jq -r "$DEF"'gc_city_marked'; }
CUT="2026-10-07T00:00:00Z"
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"verdict\n\n<!-- gc:city -->","created_at":"2026-10-08T00:00:00Z"}')" true \
  "a marked post under our login is ours"
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"older notice","created_at":"2026-10-06T23:59:59Z"}')" true \
  "an unmarked post under our login from before the cutover is ours"
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"model review: fix the race","created_at":"2026-10-07T00:00:01Z"}')" false \
  "an unmarked post under our login after the cutover is feedback"
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"same second","created_at":"2026-10-07T00:00:00Z"}')" false \
  "a post at the cutover instant is past it"
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"undated"}')" false \
  "an unmarked post with no instant cannot be shown older, so it is feedback"
eq "$(own bot "$CUT" '{"user":{"login":"johnzook"},"body":"quoting you: <!-- gc:city -->","created_at":"2026-10-08T00:00:00Z"}')" false \
  "a post under any other login is feedback, even carrying the mark"
eq "$(own bot "$CUT" '{"user":{"login":"johnzook"},"body":"old","created_at":"2026-10-01T00:00:00Z"}')" false \
  "the cutover never makes another login's post ours"
eq "$(own bot "" '{"user":{"login":"bot"},"body":"anything","created_at":"2026-10-09T00:00:00Z"}')" true \
  "with no cutover known, every post under our login is ours"
eq "$(own "" "$CUT" '{"user":{"login":""},"body":"<!-- gc:city -->"}')" false \
  "with no acting login nothing is ours"
eq "$(own bot "$CUT" '{"author":{"login":"bot"},"body":"b","createdAt":"2026-10-06T00:00:00Z"}')" true \
  "a GraphQL node (author.login, createdAt) reads the same way"
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"r","state":"COMMENTED","submitted_at":"2026-10-06T00:00:00Z"}')" true \
  "a REST review's instant is submitted_at"
eq "$(own bot "$CUT" '{"author":{"login":"bot"},"body":"r","submittedAt":"2026-10-08T00:00:00Z","createdAt":"2026-10-06T00:00:00Z"}')" false \
  "a GraphQL review's instant is submittedAt, ahead of createdAt"
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"Addressed in abc.\n<!-- gc-writeback -->","created_at":"2026-10-08T00:00:00Z"}')" true \
  "the write-back reply marker counts as the city's mark"
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"<!-- gc:visit:tk-v -->\n### Visit","created_at":"2026-10-08T00:00:00Z"}')" true \
  "the visit-comment marker counts as the city's mark"
# The cutover's shape is tested inside the definition, so a reader passes the
# stamp as it found it and a malformed one fails open the same way everywhere.
eq "$(own bot "2026-10-07" '{"user":{"login":"bot"},"body":"anything","created_at":"2026-10-09T00:00:00Z"}')" true \
  "a cutover that is not a UTC instant reads as none: every post under our login is ours"
eq "$(own bot "1970-01-01 00:00:00" '{"user":{"login":"bot"},"body":"anything","created_at":"2026-10-09T00:00:00Z"}')" true \
  "a misshapen cutover reads as none, never as a lexical bound"
cutover() { jq -rn --arg s "$1" "$DEF"'gc_city_cutover($s)'; }
eq "$(cutover "$CUT")" "$CUT" "gc_city_cutover passes a UTC instant through"
eq "$(cutover "2026-10-07T00:00:00+00:00")" "" "gc_city_cutover drops an offset form"
eq "$(cutover " $CUT")" "" "gc_city_cutover drops a padded stamp"
eq "$(cutover "")" "" "gc_city_cutover of nothing is nothing"
eq "$(marked '{"body":"plain"}')" false "an unmarked body carries no mark"
eq "$(marked '{"body":null}')" false "a null body carries no mark"
eq "$(marked "{\"body\":\"x $MARK\"}")" true "gc_city_marked reads the body alone"

echo "# no file in the pack posts to a pull request outside pr-post.sh"
if [ -x "$DETECTOR" ] && git -C "$REPO" rev-parse --show-toplevel >/dev/null 2>&1; then
  FILES="$TMPD/files"
  if git -C "$REPO" ls-files -z >"$FILES"; then
    BYPASS="$(cd "$REPO" && xargs -0 "$DETECTOR" <"$FILES" 2>&1)"; DRC=$?
    eq "$DRC" 0 "the bypass detector is clean over every tracked file"
    [ "$DRC" -eq 0 ] || printf '%s\n' "$BYPASS" | sed 's/^/     /'
  else
    bad "the bypass detector is clean over every tracked file" "git ls-files failed"
  fi
else
  bad "the bypass detector is clean over every tracked file" "no detector at $DETECTOR, or $REPO is not a checkout"
fi

echo
echo "pr-post.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
