#!/usr/bin/env bash
# pr-post.test.sh — hermetic coverage of the city's single PR posting helper:
# each verb makes the gh call its callers made, with the provenance mark
# appended; the own-def predicates tell the city's own post, and a post not for
# review, from feedback on every shape the readers hand them; not-for-review
# reads the rig's declaration from its checkout; no reader carries the no-review
# rule of its own; and no file in the pack posts to a pull request any other
# way. A gh stub records each call's argv and the body it would post; no
# network, no city.
#
# run-tests-scope: tree
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
# git names a repository by its physical path, which the expected messages
# below are built from.
TMPD="$(cd "$TMPD" && pwd -P)"
BIN="$TMPD/bin"; mkdir -p "$BIN"
MARK='<!-- gc:city -->'

# gh stub: every call's argv lands in $GHLOG one argument per line, framed by a
# `--` line per call, and the content of a --body-file is copied to $GHBODY
# while the file still exists. $GH_RC fails the call; $GH_OUT is its stdout.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gh" <<'STUB'
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

echo "# file-comment: a review comment on a whole file of the diff, marked"
run GH_OUT='{"id":4242}' -- file-comment --repo github.com/o/r --pr 12 --commit abc123 --path assets/scripts/x.sh --body "Finding from the codex review"
eq "$RC" 0 "file-comment exits 0"
eq "$(calls)" 1 "one gh call"
has "$(argv)" "$(printf 'api\n--method\nPOST\nrepos/o/r/pulls/12/comments\n--hostname\ngithub.com\n-f\n')" "it is a POST of pulls/<n>/comments on the --repo host"
has "$(argv)" "$(printf 'body=Finding from the codex review\n\n%s' "$MARK")" "the body carries the mark"
has "$(argv)" "$(printf -- '-f\ncommit_id=abc123\n-f\npath=assets/scripts/x.sh\n-f\nsubject_type=file')" "…pinned to the commit and the file, as a comment on the file as a whole"
has "$OUT" '"id":4242' "gh's output passes through, so a caller reads the new comment's id"

echo "# a body that already carries the mark is posted as it is"
run -- comment --repo github.com/o/r --pr 12 --body "$(printf 'x\n\n%s' "$MARK")"
eq "$(grep -c -F -- "$MARK" "$GHLOG")" 1 "the mark is not doubled"

echo "# a gh failure is exit 1 for every verb"
run GH_RC=1 -- comment --repo github.com/o/r --pr 12 --body x;            eq "$RC" 1 "comment"
run GH_RC=1 -- review --repo github.com/o/r --pr 12 --body x;             eq "$RC" 1 "review"
run GH_RC=1 GH_OUT='{}' -- reply --host github.com --thread PRRT_x --body x; eq "$RC" 1 "reply"
run GH_RC=1 -- edit --repo github.com/o/r --comment 5 --body x;           eq "$RC" 1 "edit"
run GH_RC=1 -- file-comment --repo github.com/o/r --pr 12 --commit abc --path x.sh --body x; eq "$RC" 1 "file-comment"

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
usage_case "a file-comment with no commit" file-comment --repo github.com/o/r --pr 1 --path x.sh --body x
usage_case "a file-comment with no path"   file-comment --repo github.com/o/r --pr 1 --commit abc --body x
usage_case "--path on a comment"           comment --repo github.com/o/r --pr 1 --body x --path x.sh

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
# An inline comment is drafted inside a pending review and published with it, so
# its instant is the review's submission: a review drafted before the cutover and
# submitted after it is feedback whole, its inline comments included.
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"inline","created_at":"2026-10-06T23:00:00Z","gc_review_submitted_at":"2026-10-07T00:10:00Z"}')" false \
  "a REST inline comment drafted before the cutover, its review submitted after, is feedback"
eq "$(own bot "$CUT" '{"user":{"login":"bot"},"body":"inline","created_at":"2026-10-06T23:00:00Z","gc_review_submitted_at":"2026-10-06T23:30:00Z"}')" true \
  "a REST inline comment whose review was submitted before the cutover is ours"
eq "$(own bot "$CUT" '{"author":{"login":"bot"},"body":"inline","createdAt":"2026-10-06T23:00:00Z","pullRequestReview":{"submittedAt":"2026-10-07T00:10:00Z"}}')" false \
  "a GraphQL comment node is dated by its review's submittedAt"
eq "$(own bot "$CUT" '{"author":{"login":"bot"},"body":"inline","createdAt":"2026-10-06T23:00:00Z","pullRequestReview":{"submittedAt":null}}')" true \
  "a comment whose review carries no submission falls back to its own createdAt"
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

echo "# own-def: a post not for review is not feedback, whoever posted it"
# gitq <dir> <git args...> — git in a fixture repository, unsigned, with no
# hooks and no line-end conversion.
gitq() {
  local d="$1"; shift
  git -C "$d" -c commit.gpgsign=false -c user.name=fixture -c user.email=fixture@example.com \
    -c core.hooksPath=/dev/null -c core.autocrlf=false "$@"
}
# rig_declares <dir> — commits standard input as the not-for-review.toml of the
# rig's repository at <dir>, and moves its default branch onto that commit, as
# a merge and the fetch after it would. Empty input commits no file. A <dir>
# that is not a repository yet becomes one, with origin/HEAD naming origin/main
# the way a clone records it.
rig_declares() {
  local d="$1"
  if [ ! -d "$d/.git" ]; then
    git init -q -b main "$d" && git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main || return 1
  fi
  cat >"$d/not-for-review.toml"
  if [ -s "$d/not-for-review.toml" ]; then gitq "$d" add not-for-review.toml
  else rm -f "$d/not-for-review.toml"; gitq "$d" rm -q --cached --ignore-unmatch not-for-review.toml; fi
  gitq "$d" commit -q --allow-empty -m declaration && gitq "$d" update-ref refs/remotes/origin/main HEAD
}
# def_in <repo> — own-def as a reader running in that rig's repository prints it.
def_in() { (cd "$1" && "$SUT" own-def 2>/dev/null); }
feedback() { # <def> <json> — prints gc_feedback for our login "bot" at $CUT
  printf '%s' "$2" | jq -r --arg self bot --arg since "$CUT" "$1"'gc_feedback($self; $since)'
}
nfr() { printf '%s' "$2" | jq -r "$1"'gc_not_for_review'; } # <def> <json>
RIG="$TMPD/rig"
printf '%s\n' '# Vercel' '[[marker]]' 'prefix = "[vc]: #"  # its deployment notice' | rig_declares "$RIG"
VDEF="$(def_in "$RIG")"
rig_declares "$TMPD/no-declaration" </dev/null
NDEF="$(def_in "$TMPD/no-declaration")"
VERCEL='{"user":{"login":"vercel[bot]","type":"Bot"},"body":"[vc]: #DEIJgls1qh2Jz\nThe latest updates on your projects."}'
eq "$(feedback "$VDEF" "$VERCEL")" false "a Vercel-shaped comment is not feedback on a rig that declares [vc]: #"
eq "$(feedback "$NDEF" "$VERCEL")" true "…and is feedback on a rig that declares nothing"
eq "$(feedback "$NDEF" '{"user":{"login":"preview[bot]","type":"Bot"},"body":"<!-- gc:no-review -->\nSchema diff"}')" false \
  "a Bot comment opening with the mark is not feedback, on a rig that declares nothing"
eq "$(feedback "$NDEF" '{"user":{"login":"johnzook","type":"User"},"body":"<!-- gc:no-review -->\nFYI only"}')" false \
  "a person's comment opening with the mark is not feedback"
eq "$(feedback "$NDEF" '{"user":{"login":"bot"},"body":"<!-- gc:no-review -->\nnote","created_at":"2026-10-08T00:00:00Z"}')" false \
  "a post under our login opening with the mark and not the city's is not feedback either"
eq "$(feedback "$NDEF" '{"user":{"login":"preview[bot]","type":"Bot"},"body":"Schema diff: two tables changed."}')" true \
  "an unmarked Bot comment is still feedback"
eq "$(feedback "$VDEF" '{"user":{"login":"johnzook","type":"User"},"body":"Quoting the bot: [vc]: #abc"}')" true \
  "a declared prefix past the start of the body leaves it feedback"
eq "$(feedback "$VDEF" '{"user":{"login":"vercel[bot]","type":"Bot"},"body":" [vc]: #abc"}')" true \
  "…and so does one after a leading space: the prefix is compared from the first character"
eq "$(feedback "$NDEF" '{"user":{"login":"bot"},"body":"verdict\n\n<!-- gc:city -->","created_at":"2026-10-08T00:00:00Z"}')" false \
  "the city's own post is not feedback"
eq "$(feedback "$NDEF" '{"user":{"login":"bot"},"body":"model review: fix the race","created_at":"2026-10-08T00:00:00Z"}')" true \
  "an unmarked post under our login after the cutover is still feedback"
eq "$(feedback "$NDEF" '{"user":{"login":"op"},"state":"APPROVED","body":"<!-- gc:no-review -->\nShip it."}')" false \
  "a review's body opening with the mark is not feedback: its state is for the reader that counts states"
eq "$(nfr "$NDEF" '{"author":{"login":"x"},"body":"<!-- gc:no-review --> on a GraphQL node"}')" true \
  "a GraphQL node reads the same way"
eq "$(nfr "$NDEF" '{"body":null}')" false "a null body carries no mark"
eq "$(printf '%s' "$VERCEL" | jq -r --arg self bot --arg since "$CUT" "$VDEF"'gc_city_own($self; $since)')" false \
  "the city's own rule is unchanged by a declaration"

echo "# own-def: the mark counts only among the HTML comments a body opens with"
row() { jq -nc --arg l "$1" --arg t "$2" --arg b "$3" '{user: {login: $l, type: $t}, body: $b}'; } # <login> <type> <body>
NR='<!-- gc:no-review -->'
GF_REPORT=$(printf '%s\n' '<!-- growth-factor:schema-diff -->' "$NR" '### Schema diff' '' '| table | change |' '|---|---|' \
  '| `app.practices` | added |' '' '```sql' 'ALTER TABLE app.practices ADD tz text;' '```')
eq "$(feedback "$NDEF" "$(row 'github-actions[bot]' Bot "$GF_REPORT")")" false \
  "a workflow's report whose mark follows its own marker line is not for review, whatever follows them"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '\n\n%s\nPreview deployed.' "$NR")")")" false \
  "blank lines before the mark leave it opening the body"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '<!--\nbuilt by preview.yml\n-->\n%s\nPreview deployed.' "$NR")")")" false \
  "…and so does a comment over several lines before it"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '<!-- run 7 --> %s' "$NR")")")" false \
  "…and one on the same line"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '<!-- generated by preview.yml, %s\n-->' "$NR")")")" false \
  "a mark inside an opening comment counts, since it is hidden with it"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '<!-- run 7\n```\n%s' "$NR")")")" false \
  "a fence inside an opening comment is the comment's text, so it does not hide the mark from the comment"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '%s Deployment ready' "$NR")")")" false \
  "the mark counts as the first thing on a line that goes on past it"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '   %s' "$NR")")")" false \
  "a mark indented three spaces still opens the body"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '<!-->\n<!--->\n<!-- a --!>\n%s' "$NR")")")" false \
  "a comment ends where an HTML parser ends it, at --> or --!>, the empty forms included"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '<!-- run 7 -->\r\n%s\r\nReport\r\n' "$NR")")")" false \
  "a body with CRLF line ends reads the same"
eq "$(nfr "$NDEF" "$(jq -nc --arg b "$(printf '<!-- Déjà vu — 😀 -->\n%s' "$NR")" '{body: $b}')")" true \
  "characters past ASCII in an opening comment read the same"
eq "$(nfr "$NDEF" "$(jq -nc --arg b "$(printf '😀 %s' "$NR")" '{body: $b}')")" false \
  "…and before the mark, they are text, which ends the opening"

echo "# own-def: a mark that does not open the body is feedback, whatever markdown carries it"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf -- '- ```html\n\n  %s\n  ```\n\nPlease add this.' "$NR")")")" true \
  "a person who quotes the mark in a fence inside a list item is giving feedback"
eq "$(feedback "$NDEF" "$(row 'reviewer[bot]' Bot "$(printf -- '- ```html\n\n  %s\n  ```\n\nPlease add this.' "$NR")")")" true \
  "…and so is a review app"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf -- '- ```html\n  %s\n  ```\n\nPlease add this.' "$NR")")")" true \
  "…with no blank line opening the fence"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf -- '1. ```\n   %s\n   ```\n\nPlease add this.' "$NR")")")" true \
  "…in an ordered list item"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf -- '* ~~~\n  %s\n  ~~~\n\nPlease add this.' "$NR")")")" true \
  "…in a tilde fence"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf -- '- Add it:\n  ```\n```\n%s\n```\n\nPlease add this.' "$NR")")")" true \
  "…and in the fence a column-0 line opens as it ends the list item and the item's fence"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf -- '> - ```\n>   %s\n>   ```' "$NR")")")" true \
  "…in a fence in a list item in a quote"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf -- '1. Add it:\n\n   ```\n   %s\n   ```' "$NR")")")" true \
  "…in a fence in an ordered list item, a blank line after its marker"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf -- '- > ```\n  > %s' "$NR")")")" true \
  "…in a fence in a quote in a list item"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf 'Should the report carry `%s` on its first line?' "$NR")")")" true \
  "…in a code span"
eq "$(feedback "$NDEF" "$(row 'reviewer[bot]' Bot "$(printf '`%s` is missing from the template.' "$NR")")")" true \
  "…in a code span that opens the body"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf 'Use `` %s `` here.' "$NR")")")" true \
  "…in a code span of two backticks"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf 'Like this:\n```html\n%s\n```' "$NR")")")" true \
  "…in a fenced code block"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf '```suggestion\n%s\n```' "$NR")")")" true \
  "…in a suggested change"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf 'Like this:\n~~~\n%s' "$NR")")")" true \
  "…in a fence never closed, which runs to the end of the body"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf 'Like this:\n\n    %s' "$NR")")")" true \
  "…in an indented code block"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf '    %s' "$NR")")")" true \
  "…indented four spaces at the top of the body, which is code"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf '\t%s' "$NR")")")" true \
  "…or a tab, which reaches four columns"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf '> ```\n> %s\n> ```' "$NR")")")" true \
  "…in a fenced block inside a quote"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf '`start\n%s\nend`' "$NR")")")" true \
  "…in a code span across lines"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf '> %s\n> Preview deployed.\n\nThis notice is wrong: the preview never built.' "$NR")")")" true \
  "a reply that quotes a marked comment is feedback, though GitHub hides the quoted mark"
eq "$(feedback "$NDEF" "$(row johnzook User "$(printf -- '- %s' "$NR")")")" true \
  "…and so is a mark in a list item"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf 'Schema diff\n\n%s' "$NR")")")" true \
  "a mark after the body's text is feedback, though GitHub hides it there"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf 'Preview deployed. %s' "$NR")")")" true \
  "…and so is one at the end of a line of text"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf 'Report:\n```\nok\n```\n%s' "$NR")")")" true \
  "…and one after a closed fence"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '<!-- run 7 -->Report\n%s' "$NR")")")" true \
  "text after an opening comment on its line ends the opening"
eq "$(feedback "$NDEF" "$(row 'previewbot[bot]' Bot "$(printf '<!-- run 7 --> <!-- open\n%s' "$NR")")")" true \
  "a comment left open on a line that holds --> ends the opening, as markdown ends the raw HTML there"
eq "$(nfr "$NDEF" "$(jq -nc --arg b "$(printf '`%s` is not <!-- gc:`x`no-review -->' "$NR")" '{body: $b}')")" false \
  "a code span cut out of a body does not join what is left into a mark"

echo "# not-for-review: what the rig declares, read from its default branch"
# nfr_run <repo> — run in that rig's repository; sets RC, NOUT (stdout) and
# NERR (stderr).
nfr_run() { NOUT="$(cd "$1" && "$SUT" not-for-review 2>"$TMPD/nfr.err")"; RC=$?; NERR="$(cat "$TMPD/nfr.err")"; }
NO_REVIEW='<!-- gc:no-review -->'
nfr_run "$RIG"
eq "$RC" 0 "a declaration that reads whole exits 0"
eq "$NOUT" "$(printf '%s\n%s' "$NO_REVIEW" '[vc]: #')" "it prints the mark, then each declared prefix"
eq "$NERR" "" "…and names nothing refused"
nfr_run "$TMPD/no-declaration"
eq "$RC|$NOUT|$NERR" "0|$NO_REVIEW|" "a rig with no file declares nothing, and that is no fault"
SHAPES="$TMPD/shapes"
rig_declares "$SHAPES" <<'TOML'
# Comments and blank lines are allowed.

[[marker]]
prefix = "a \"quoted\" \\ prefix"   # a basic string's two escapes
[[ marker ]]
prefix = 'C:\literal "as written"'
[[marker]]
prefix = "## Deploy Preview"   # a prefix may open with a hash
TOML
nfr_run "$SHAPES"
eq "$RC|$NERR" "0|" "every string shape the doc names reads"
eq "$NOUT" "$(printf '%s\n%s\n%s\n%s' "$NO_REVIEW" 'a "quoted" \ prefix' 'C:\literal "as written"' '## Deploy Preview')" \
  "…a basic string unescaped, a literal one as written, and a hash inside the quotes kept"
printf '[[marker]]\r\nprefix = "[vc]: #"\r\n' | rig_declares "$SHAPES"
nfr_run "$SHAPES"
eq "$RC|$NOUT" "0|$(printf '%s\n%s' "$NO_REVIEW" '[vc]: #')" "a file with CRLF line ends reads the same"
FAULTS="$TMPD/faults"
rig_declares "$FAULTS" <<'TOML'
prefix = "outside any table"
[[marker]]
prefix = "  "
[[marker]]
prefix = "tab\there"
[[marker]]
name = "Vercel"
prefix = "[vc]: #"
[[marker]]
# no prefix here
[[marker]]
prefix = "one"
prefix = "two"
[markers]
[[marker]]
prefix = "kept"
TOML
nfr_run "$FAULTS"
eq "$RC" 1 "a declaration with a fault exits 1"
eq "$NOUT" "$(printf '%s\n%s' "$NO_REVIEW" kept)" "…and declares only the table with none"
has "$NERR" "not-for-review.toml on origin/main: line 1: this file holds only [[marker]] tables" "a key outside a table is named"
has "$NERR" "the [[marker]] at line 2 sets an empty prefix, which would take every comment out of review" "an empty prefix is refused"
has "$NERR" "line 5: the prefix is not a one-line string" "an escape the parser does not take is refused, not guessed"
has "$NERR" "line 7: a [[marker]] table sets its prefix and nothing else" "a stray key refuses its table"
hasnt "$NOUT" "[vc]: #" "…prefix and all"
has "$NERR" "the [[marker]] at line 9 sets no prefix" "a table with no prefix is named"
has "$NERR" "the [[marker]] at line 11 sets its prefix twice" "a prefix set twice is refused"
has "$NERR" "line 14: this file holds only [[marker]] tables" "another table is named"
FDEF="$(cd "$FAULTS" && "$SUT" own-def 2>"$TMPD/fdef.err")"; FRC=$?
eq "$FRC" 0 "own-def still prints its definitions over a faulty declaration"
has "$FDEF" 'def gc_not_for_review_prefixes: ["kept"];' "…holding only the prefixes that read"
has "$(cat "$TMPD/fdef.err")" "pr-post: $FAULTS/not-for-review.toml on origin/main: line 1:" \
  "…and names each refused part on stderr, with the file and the branch it was read from"

echo "# not-for-review: the repository the caller runs in declares, and GC_RIG_ROOT's only outside one"
OTHER="$TMPD/other"
printf '%s\n' '[[marker]]' 'prefix = "from GC_RIG_ROOT"' | rig_declares "$OTHER"
OUT="$(cd "$RIG" && GC_RIG_ROOT="$OTHER" "$SUT" not-for-review 2>&1)"
has "$OUT" "[vc]: #" "a caller in a rig's repository reads that rig's declaration, whatever GC_RIG_ROOT names"
hasnt "$OUT" "from GC_RIG_ROOT" "…and not GC_RIG_ROOT's"
VIA_ROOT="$(cd "$RIG" && GC_RIG_ROOT="$OTHER" "$SUT" own-def 2>/dev/null)"
has "$VIA_ROOT" 'def gc_not_for_review_prefixes: ["[vc]: #"];' "…and own-def embeds the same"
# GIT_CEILING_DIRECTORIES keeps git from finding a repository above the test's
# temp directory, so the caller runs in none.
mkdir -p "$TMPD/outside"
OUT="$(cd "$TMPD/outside" && GIT_CEILING_DIRECTORIES="$TMPD" GC_RIG_ROOT="$OTHER" "$SUT" not-for-review 2>&1)"
has "$OUT" "from GC_RIG_ROOT" "a caller in no repository reads GC_RIG_ROOT's"
OUT="$(cd "$TMPD/outside" && GIT_CEILING_DIRECTORIES="$TMPD" env -u GC_RIG_ROOT "$SUT" not-for-review 2>&1)"; ORC=$?
eq "$ORC|$OUT" "0|$NO_REVIEW" "…and with neither, nothing is declared, and that is no fault"

echo "# not-for-review: only the default branch declares, so a branch's copy and an uncommitted edit count for nothing"
BR="$TMPD/branch"
printf '%s\n' '[[marker]]' 'prefix = "merged"' | rig_declares "$BR"
gitq "$BR" checkout -q -b polecat/x
printf '%s\n' '[[marker]]' 'prefix = "on the branch"' >"$BR/not-for-review.toml"
gitq "$BR" commit -q -am "the branch declares its own"
nfr_run "$BR"
eq "$RC|$NOUT" "0|$(printf '%s\n%s' "$NO_REVIEW" merged)" "a checkout of a pull request's branch reads the default branch's declaration"
gitq "$BR" worktree add -q --detach "$TMPD/branch-worktree" polecat/x
nfr_run "$TMPD/branch-worktree"
eq "$RC|$NOUT" "0|$(printf '%s\n%s' "$NO_REVIEW" merged)" "…and so does a worktree of it"
printf '%s\n' '[[marker]]' 'prefix = "uncommitted"' >"$BR/not-for-review.toml"
nfr_run "$BR"
hasnt "$NOUT" "uncommitted" "an uncommitted edit to the file counts for nothing"
gitq "$BR" checkout -q -- not-for-review.toml
gitq "$BR" update-ref refs/remotes/origin/main polecat/x
nfr_run "$BR"
eq "$RC|$NOUT" "0|$(printf '%s\n%s' "$NO_REVIEW" 'on the branch')" "the branch's declaration counts once the default branch carries it"
NOHEAD="$TMPD/no-origin-head"
printf '%s\n' '[[marker]]' 'prefix = "from main"' | rig_declares "$NOHEAD"
git -C "$NOHEAD" symbolic-ref --delete refs/remotes/origin/HEAD
nfr_run "$NOHEAD"
eq "$RC|$NOUT" "0|$(printf '%s\n%s' "$NO_REVIEW" 'from main')" "with origin/HEAD unset, origin/main is the default branch"
git -C "$NOHEAD" update-ref -d refs/remotes/origin/main
nfr_run "$NOHEAD"
eq "$RC|$NOUT" "1|$NO_REVIEW" "a repository with no default branch to read declares nothing, and exits 1"
has "$NERR" "pr-post: $NOHEAD/not-for-review.toml on origin/main: the repository has no such branch, so nothing is declared" \
  "…naming the branch it could not read"

echo "# one definition: no reader carries the no-review rule of its own"
if git -C "$REPO" rev-parse --show-toplevel >/dev/null 2>&1; then
  eq "$(git -C "$REPO" grep -l -F -e 'gc:no-review' -- 'assets/' 'formulas/' 'services/' 'tools/' ':!assets/scripts/pr-post.sh' ':!*.test.sh' ':!*_test.go' 2>/dev/null)" "" \
    "no file but pr-post.sh tests for the no-review mark"
  eq "$(git -C "$REPO" grep -l -E -e 'def (gc_not_for_review|gc_feedback|gc_no_review_mark|gc_opens_with_mark)[:(]' -- . ':!assets/scripts/pr-post.sh' 2>/dev/null)" "" \
    "no file but pr-post.sh defines the rule"
  eq "$(git -C "$REPO" grep -l -F -e '[vc]' -- 'assets/scripts/' ':!*.test.sh' 2>/dev/null)" "" \
    "no script recognises a third-party marker of its own: a rig declares it"
else
  bad "one definition: no reader carries the no-review rule of its own" "$REPO is not a checkout"
fi

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
