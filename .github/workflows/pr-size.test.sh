#!/usr/bin/env bash
# pr-size.test.sh — pr-size.sh keeps one comment current with a pull request's
# size, measured with the merge base's tool and plan, and with the suite's time
# below it. It measures the head and base the pull request has when the run
# starts, and writes only while the pull request still has them. pr-size.yml
# runs as the default branch carries it, from the tip of the pull request's
# base branch, again when the pull request changes that branch, and again when
# one of its tests runs ends, and every run that measures one pull request takes
# that pull request's one concurrency group.
#
# The cases build a repository whose base commit carries tools/measure.sh and a
# deletion plan, and whose head adds lines to a file the plan retires while it
# edits the tool and empties the plan. pr-size.sh runs there against a stub gh
# that serves each case's comments, the pull request's head and base, and the
# tests runs, and records every call. It posts through the real
# assets/scripts/pr-post.sh, and the city's own feedback definition reads what
# it posted. What the suite's time section says is suite-time.test.sh's to pin.
# It sources test-harness.sh for the assertions only, because harness_init would
# stub git out.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/pr-size.sh"
WF="$HERE/pr-size.yml"
TOOL="$ROOT/tools/measure.sh"
PR_POST="$ROOT/assets/scripts/pr-post.sh"
for f in "$SUT" "$WF" "$TOOL" "$PR_POST"; do
  [ -f "$f" ] || { echo "pr-size.test.sh: cannot find $f" >&2; exit 2; }
done
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pr-size-test.XXXXXX")" || { echo "pr-size.test.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=../../assets/scripts/test-harness.sh
. "$ROOT/assets/scripts/test-harness.sh"   # assertions only; harness_init would stub git out
PASS=0; FAIL=0

# None of the session's repository settings may reach the git the script drives.
unset "${!GC_@}" "${!BEADS_@}" "${!GIT_@}" "${!GITHUB_@}" 2>/dev/null || true
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
git config --file "$GIT_CONFIG_GLOBAL" user.name T
git config --file "$GIT_CONFIG_GLOBAL" user.email t@e.com
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
commit() { git add -A && git commit -q -m "$1"; }

# The stub gh: each call's arguments, NUL-separated, in a file of its own. The
# comments read gets the case's pages. The pull request's first read gets
# GH_PR_HEAD and GH_PR_BASE as its head and base, and each later read gets
# GH_PR_HEAD_LATER and GH_PR_BASE_LATER where a case sets them. A tests run list
# gets GH_RUNS or no run, a run gets no jobs and no artifacts, and a write
# echoes what gh would. With GH_KEEP set, a post leaves the bot's comment 99
# among the comments the next run reads. GH_FAIL fails every call whose words
# hold it, and all fails every call.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$GH_LOG/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$GH_LOG/count"
printf '%s\0' "$@" > "$GH_LOG/call.$n"
case "${GH_FAIL:-}" in '') ;; all) exit 1 ;; *) case "$*" in *"$GH_FAIL"*) exit 1 ;; esac ;; esac
case "$1 $2" in
  "api --paginate") cat "$GH_COMMENTS" ;;
  "api repos/o/r/pulls/7")
    if [ -e "$GH_LOG/read" ]; then
      printf '{"head":{"sha":"%s"},"base":{"ref":"%s"}}' "${GH_PR_HEAD_LATER:-$GH_PR_HEAD}" "${GH_PR_BASE_LATER:-$GH_PR_BASE}"
    else
      : > "$GH_LOG/read"
      printf '{"head":{"sha":"%s"},"base":{"ref":"%s"}}' "$GH_PR_HEAD" "$GH_PR_BASE"
    fi ;;
  "api repos/o/r/actions/workflows/"*) if [ -n "${GH_RUNS:-}" ]; then printf '%s' "$GH_RUNS"; else echo '{"workflow_runs":[]}'; fi ;;
  "api repos/o/r/actions/runs/"*) case "$2" in */jobs*) echo '{"jobs":[]}' ;; *) echo '{"artifacts":[]}' ;; esac ;;
  "pr comment")
    [ -z "${GH_KEEP:-}" ] \
      || printf '[{"id":99,"user":{"login":"github-actions[bot]"},"body":"<!-- gc-toolkit:pr-size -->"}]' > "$GH_COMMENTS"
    echo "https://github.com/o/r/pull/7#issuecomment-99" ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "$BIN/gh"

# run <comments file> <head> [<repo dir>]: pr-size.sh for PR 7, whose head is
# <head> and whose base is GH_PR_BASE where a case sets it and main where it
# does not, leaving its exit code in RC and its output in OUT.
run() {
  GH_LOG="$TMP/log.$RANDOM$RANDOM"; mkdir -p "$GH_LOG"
  OUT=$(cd "${3:-$REPO}" && PATH="$BIN:$PATH" GH_LOG="$GH_LOG" GH_COMMENTS="$1" GH_PR_HEAD="$2" GH_PR_BASE="${GH_PR_BASE-main}" \
    "$SUT" --repo github.com/o/r --pr 7 2>&1)
  RC=$?
}
# Each call on a line of its own: its arguments joined by spaces, with each
# newline inside one read as |.
calls() {
  local i=1
  while [ -f "$GH_LOG/call.$i" ]; do tr '\000\n' ' |' < "$GH_LOG/call.$i"; echo; i=$((i + 1)); done
}
# The calls on the pull request and its comments, which are every call but the
# reads of the suite's time, each without the --hostname a read carries.
ccalls() { calls | grep -v ' repos/o/r/actions/' | sed -e 's/ *$//' -e 's/ --hostname github\.com$//'; }
# The body the one write posted: --body's value, or a body= field's.
posted() {
  local i=1 a prev
  while [ -f "$GH_LOG/call.$i" ]; do
    prev=""
    while IFS= read -r -d '' a; do
      [ "$prev" = --body ] && { printf '%s' "$a"; return; }
      case "$a" in body=*) printf '%s' "${a#body=}"; return ;; esac
      prev=$a
    done < "$GH_LOG/call.$i"
    i=$((i + 1))
  done
}
# Whether the city reads <body>, posted by the Actions bot, as feedback.
feedback() {
  jq -rn --arg b "$1" "$FDEF"'
    {user: {login: "github-actions[bot]"}, body: $b} | gc_feedback("city-bot"; "")'
}
page() { printf '%s' "$1" > "$TMP/$2"; printf '%s' "$TMP/$2"; }

REPO="$TMP/repo"; mkdir -p "$REPO/tools" "$REPO/assets/scripts"; cd "$REPO" && git init -q
# Read here, where no origin declares a prefix, so only the mark decides.
FDEF=$("$PR_POST" feedback-def 2>/dev/null) || { echo "pr-size.test.sh: pr-post.sh feedback-def failed" >&2; exit 2; }
cp "$TOOL" tools/measure.sh
printf 'assets/scripts/retiring.sh\ttk-retire\n' > tools/deletion-plan.tsv
printf 'a\n' > assets/scripts/retiring.sh
commit base
FORK=$(git rev-parse HEAD)
git checkout -q -b change
printf 'b\nc\n' >> assets/scripts/retiring.sh
printf 'printf "HACKED\\n"\n' > tools/measure.sh
: > tools/deletion-plan.tsv
commit "the head adds two lines, edits the tool and empties the plan"
HEAD_SHA=$(git rev-parse HEAD)
# The base branch moves on past the fork, its tool with it, and pr-size.sh
# finds its tip at the remote-tracking ref the checkout fetched for it.
git checkout -q --detach "$FORK"
printf '1\n2\n3\n4\n5\n' > assets/scripts/later.sh
printf 'true\n' > assets/scripts/later.test.sh
printf 'printf "TIP\\n"\n' > tools/measure.sh
commit "the base moves on"
git update-ref refs/remotes/origin/main HEAD
BASE=refs/remotes/origin/main
WANT=$(bash "$TOOL" --pr "$BASE" "$HEAD_SHA")
SHORT=$(git rev-parse --short=12 "$HEAD_SHA")
NONE=$(page '[]' none.json)

echo "# a pull request with no size comment gets one"
run "$NONE" "$HEAD_SHA"
eq "$RC" 0 "it exits 0"
eq "$(ccalls | cut -d' ' -f1-3)" "api repos/o/r/pulls/7
api repos/o/r/pulls/7
api --paginate repos/o/r/issues/7/comments
pr comment 7" "it reads the pull request's head and base before it measures and again before it writes, reads the comments, then posts once through pr-post.sh's comment"
BODY=$(posted)
eq "$(printf '%s\n' "$BODY" | sed -n '1,3p')" "<!-- gc-toolkit:pr-size -->
<!-- gc:no-review -->
## Size" "the body opens with the script's mark, the no-review mark and the heading"
has "$BODY" "$WANT" "…and carries the section the merge base's tool prints"
has "$BODY" "Net lines from the merge base \`$(git rev-parse --short "$FORK")\`: runtime +2 and tests 0." \
  "…counted from the fork, so the base's later commit is not the change's"
has "$BODY" '`assets/scripts/retiring.sh` gains 2 lines, and tk-retire retires it.' \
  "…naming the lines added to a file the merge base's plan retires, though the head emptied the plan"
hasnt "$BODY" HACKED "…and the head's edited tool never runs"
hasnt "$BODY" TIP "…nor the tool the base's tip carries"
has "$BODY" "Measured at head \`$SHORT\`." "…and it names the head it measured"
eq "$(printf '%s\n' "$BODY" | grep -n -e '^Measured at head' -e '^## Suite time$' | cut -d: -f2-)" "Measured at head \`$SHORT\`.
## Suite time" "…with the suite's time below the size"
has "$BODY" "No tests run has tested head \`$SHORT\`, so the suite's time is not shown." \
  "…which is suite-time.sh's section for the head"
has "$(calls)" "api repos/o/r/actions/workflows/tests.yml/runs?head_sha=$HEAD_SHA&event=pull_request" \
  "…read for the head it measured"
eq "$(feedback "$BODY")" false "the city does not read the post as feedback"
eq "$(feedback "$(printf '%s\n' "$BODY" | grep -v 'gc:no-review')")" true \
  "…which the no-review mark decides: without it the bot's post is feedback"

echo "# the bot's size comment is rewritten in place, and a person's never"
PAGES=$(page '[{"id":11,"user":{"login":"alice"},"body":"<!-- gc-toolkit:pr-size -->\nquoting the mark"}][{"id":22,"user":{"login":"github-actions[bot]"},"body":"<!-- gc-toolkit:pr-size -->\n<!-- gc:no-review -->\n## Size\n\nan earlier head"}]' pages.json)
GH_RUNS='{"workflow_runs":[{"id":900,"status":"completed","conclusion":"success","html_url":"u"}]}' run "$PAGES" "$HEAD_SHA"
eq "$RC" 0 "it exits 0"
eq "$(ccalls | tail -n 1 | cut -d' ' -f1-4)" "api --method PATCH repos/o/r/issues/comments/22" \
  "it rewrites the bot's comment from the second page of comments through pr-post.sh's edit"
eq "$(ccalls | wc -l | tr -d ' ')" 4 "…and posts nothing new"
has "$(posted)" "$WANT" "…with the size at this head"
has "$(posted)" "The change adds and removes no test file." \
  "…and the suite's time reads the change from the merge base, so a test file the base added later is not taken for one the change removes"

echo "# a size that cannot be measured says so where a comment stands, and posts nothing new"
run "$PAGES" 0123456789abcdef0123456789abcdef01234567
eq "$RC" 1 "an unreadable head exits 1"
eq "$(ccalls | tail -n 1 | cut -d' ' -f1-4)" "api --method PATCH repos/o/r/issues/comments/22" "it rewrites the bot's comment"
has "$(posted)" 'The size at head `0123456789ab` could not be measured.' "…to say the size at this head could not be measured"
has "$(posted)" 'The suite'"'"'s time at head `0123456789ab` could not be read.' "…and that its suite time could not be read"
run "$NONE" 0123456789abcdef0123456789abcdef01234567
eq "$RC" 1 "with no comment to rewrite it exits 1"
eq "$(ccalls | wc -l | tr -d ' ')" 3 "…and posts nothing"
has "$OUT" "the size of PR#7 at head 0123456789ab could not be measured" "…and its log says so"

echo "# a suite time that cannot be read is said, and changes no exit"
GH_FAIL=/actions/ run "$NONE" "$HEAD_SHA"
eq "$RC" 0 "it exits 0"
eq "$(ccalls | tail -n 1 | cut -d' ' -f1-2)" "pr comment" "…and posts"
has "$(posted)" "$WANT" "…the size"
has "$(posted)" "The suite's time at head \`$SHORT\` could not be read." "…and says the suite's time could not be read"

echo "# a run whose pull request moves while it measures writes nothing"
GH_PR_HEAD_LATER=fedcba9876543210fedcba9876543210fedcba98 run "$PAGES" "$HEAD_SHA"
eq "$RC" 0 "a run whose head moves while it measures exits 0"
eq "$(ccalls)" "api repos/o/r/pulls/7
api repos/o/r/pulls/7" "…after reading the pull request again, and reads and writes no comment"
has "$OUT" "PR#7 is now head fedcba987654 into main, so nothing is written for head $SHORT into main" "…and its log says why"
GH_PR_BASE_LATER=integration run "$PAGES" "$HEAD_SHA"
eq "$RC" 0 "a run whose pull request changes the branch it merges into while it measures exits 0"
eq "$(ccalls | wc -l | tr -d ' ')" 2 "…and reads and writes no comment"
has "$OUT" "PR#7 is now head ${HEAD_SHA:0:12} into integration, so nothing is written for head $SHORT into main" "…and its log says why"

echo "# runs of one pull request, which its concurrency group runs one at a time, keep one comment"
KEEP=$(page '[]' keep.json)
GH_KEEP=1 GH_RUNS='{"workflow_runs":[{"id":901,"status":"in_progress","conclusion":null,"html_url":"u"}]}' run "$KEEP" "$HEAD_SHA"
eq "$(ccalls | tail -n 1 | cut -d' ' -f1-2)" "pr comment" "the first run posts the comment"
has "$(posted)" "has not finished" "…while the tests run it read has not finished"
GH_RUNS='{"workflow_runs":[{"id":901,"status":"completed","conclusion":"success","html_url":"u"}]}' run "$KEEP" "$HEAD_SHA"
eq "$(ccalls | tail -n 1 | cut -d' ' -f1-4)" "api --method PATCH repos/o/r/issues/comments/99" \
  "the run after it rewrites that comment and posts no second one"
has "$(posted)" "From the [tests run](u) at head \`$SHORT\`" "…with the time of the tests run as it read it, finished"
hasnt "$(posted)" "has not finished" "…and nothing of what the run before it read"

echo "# a pull request or comments that cannot be read get no post"
GH_FAIL=all run "$NONE" "$HEAD_SHA"
eq "$RC" 1 "a pull request whose head and base cannot be read exits 1"
eq "$(ccalls)" "api repos/o/r/pulls/7" "…after that one read"
GH_PR_BASE='' run "$NONE" "$HEAD_SHA"
eq "$RC" 1 "a read of the pull request that names no base exits 1"
eq "$(ccalls)" "api repos/o/r/pulls/7" "…after that one read"
GH_FAIL=issues/7/comments run "$NONE" "$HEAD_SHA"
eq "$RC" 1 "comments that cannot be read exit 1"
eq "$(ccalls | wc -l | tr -d ' ')" 3 "…after that read, with no write"

echo "# a merge base that carries no tool has no size to show"
OLD="$TMP/old"; mkdir -p "$OLD/tools"; cd "$OLD" && git init -q
printf 'a\n' > a.sh && commit base
OBASE=$(git rev-parse HEAD)
cp "$TOOL" tools/measure.sh && printf 'b\n' >> a.sh && commit "the head adds the tool"
OHEAD=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$OBASE"
run "$NONE" "$OHEAD" "$OLD"
eq "$RC" 0 "it exits 0"
eq "$(ccalls | cut -d' ' -f1-3)" "api repos/o/r/pulls/7
api repos/o/r/pulls/7
api --paginate repos/o/r/issues/7/comments" \
  "…and only reads the pull request and its comments, so a pull request with none gets none"
has "$OUT" "carries no tools/measure.sh, so it has no size to show" "…and its log says why"

echo "# a size comment says so when the head moves to a merge base that carries no tool"
# The base branch has moved on and carries the tool, and the head's merge base
# with it does not.
git checkout -q --detach "$OBASE" && mkdir -p tools && cp "$TOOL" tools/measure.sh && commit "the base branch gains the tool"
git update-ref refs/remotes/origin/main HEAD
EARLIER=$(page "$(jq -n --arg b "$BODY" '[{id: 22, user: {login: "github-actions[bot]"}, body: $b}]')" earlier.json)
run "$EARLIER" "$OHEAD" "$OLD"
eq "$RC" 0 "it exits 0"
eq "$(ccalls | tail -n 1 | cut -d' ' -f1-4)" "api --method PATCH repos/o/r/issues/comments/22" \
  "it rewrites the comment the first case posted"
eq "$(ccalls | wc -l | tr -d ' ')" 4 "…and posts nothing new"
GONE=$(posted)
eq "$(printf '%s\n' "$GONE" | sed -n '1,3p')" "<!-- gc-toolkit:pr-size -->
<!-- gc:no-review -->
## Size" "…keeping the marks the next run finds it by"
has "$GONE" "The size at head \`$(git rev-parse --short=12 "$OHEAD")\` is not shown, because its merge base \`$(git rev-parse --short=12 "$OBASE")\` carries no \`tools/measure.sh\`." \
  "…to say this head's merge base has no size to show"
hasnt "$GONE" "Measured at head" "…so the earlier head's size is no longer shown"
eq "$(feedback "$GONE")" false "…and the city does not read it as feedback"

echo "# a tool that fails is not taken for a missing one"
BAD="$TMP/bad"; mkdir -p "$BAD/tools"; cd "$BAD" && git init -q
printf 'exit 3\n' > tools/measure.sh && printf 'a\n' > a.sh && commit base
git update-ref refs/remotes/origin/main HEAD
printf 'b\n' >> a.sh && commit "the head adds a line"
run "$EARLIER" "$(git rev-parse HEAD)" "$BAD"
eq "$RC" 1 "a merge base's tool that exits 3 makes the run exit 1"
has "$(posted)" "could not be measured" "…and the comment says the size could not be measured"
hasnt "$(posted)" "carries no" "…never that the merge base carries no tool"

echo "# a pull request that changes its base branch is measured from the new one, by any run after the change"
RT="$TMP/retarget"; mkdir -p "$RT/tools" "$RT/assets/scripts"; cd "$RT" && git init -q
cp "$TOOL" tools/measure.sh && : > tools/deletion-plan.tsv && printf 'a\n' > assets/scripts/x.sh && commit base
git update-ref refs/remotes/origin/main HEAD
printf 'b\nc\nd\n' >> assets/scripts/x.sh && commit "the integration branch adds three lines"
git update-ref refs/remotes/origin/integration HEAD
printf 'e\n' >> assets/scripts/x.sh && commit "the head adds one more"
RHEAD=$(git rev-parse HEAD)
INTO_MAIN=$(bash "$TOOL" --pr refs/remotes/origin/main "$RHEAD")
INTO_INT=$(bash "$TOOL" --pr refs/remotes/origin/integration "$RHEAD")
has "$INTO_INT" "runtime +1" "the tool counts one line from the integration branch's merge base"
hasnt "$INTO_MAIN" "runtime +1" "…and more from main's"
run "$NONE" "$RHEAD" "$RT"
has "$(posted)" "$INTO_MAIN" "into main, the comment carries the size from main's merge base"
INTO=$(page "$(jq -n --arg b "$(posted)" '[{id: 33, user: {login: "github-actions[bot]"}, body: $b}]')" into.json)
GH_PR_BASE=integration run "$INTO" "$RHEAD" "$RT"
eq "$RC" 0 "retargeted to the integration branch, it exits 0"
eq "$(ccalls | tail -n 1 | cut -d' ' -f1-4)" "api --method PATCH repos/o/r/issues/comments/33" \
  "…rewriting the comment the run into main posted"
has "$(posted)" "$INTO_INT" \
  "…with the size from the integration branch's merge base, read from the pull request, so no event that saw it merge into main, such as the end of a tests run that waited for a runner, brings main's size back"

echo "# usage"
# Against the stub gh, so a script that gets past its usage check reaches no
# host.
UL="$TMP/log.usage"; mkdir -p "$UL"
alone() { (cd "$REPO" && PATH="$BIN:$PATH" GH_LOG="$UL" "$SUT" "$@" >/dev/null 2>&1); }
alone --repo github.com/o/r; eq "$?" 2 "a missing --pr is a usage error"
alone --repo o/r --pr 7; eq "$?" 2 "--repo must name its host"
alone --repo github.com/o/r --pr 7 --base refs/remotes/origin/main --head "$HEAD_SHA"
eq "$?" 2 "it takes no head or base from its caller, since it reads both from the pull request"

echo "# pr-size.yml runs as the default branch carries it"
ON=$(awk '/^on:/ { on = 1; next } on && /^[^[:space:]#]/ { on = 0 } on' "$WF")
has "$ON" "pull_request_target:" "it runs on pull_request_target, which takes the job from the default branch"
eq "$(printf '%s\n' "$ON" | grep -vE '^[[:space:]]*#' | grep -E '^  [a-z_]+:' | tr '\n' ' ')" "  pull_request_target:   workflow_run: " \
  "…and on workflow_run, which does too, and on no event that runs the pull request's own copy of it"
eq "$(grep -cE '^[[:space:]]*ref:' "$WF")" 0 "its checkout takes no ref, so it checks out the default branch and never the head"
CODE=$(grep -vE '^[[:space:]]*#' "$WF")
has "$CODE" '--repo "${GITHUB_SERVER_URL#https://}/$GITHUB_REPOSITORY" --pr "$PR_NUMBER"' "it hands pr-size.sh the pull request"
eq "$(printf '%s\n' "$CODE" | grep -cE 'head\.sha|head_sha|base\.ref|--head|--base')" 0 \
  "…and no head or base from the event, which can be older than the pull request"
hasnt "$CODE" GITHUB_SHA "…nor GITHUB_SHA, the default branch's tip under both events"

echo "# pr-size.yml runs again when a tests run of a pull request ends"
has "$ON" "  workflow_run:
    workflows: [tests]
    types: [completed]" "it runs when the tests workflow completes"
has "$CODE" "  actions: read" "…and may read a run's jobs and artifacts"

echo "# pr-size.yml measures again when a pull request changes its base branch"
has "$ON" "types: [opened, synchronize, reopened, edited]" \
  "it runs on edited, which is how GitHub reports a change of the base branch"
eq "$(grep -E '^    if:' "$WF")" "    if: github.event_name == 'workflow_run' && github.event.workflow_run.event == 'pull_request' && github.event.workflow_run.pull_requests[0] || github.event_name == 'pull_request_target' && (github.event.action != 'edited' || github.event.changes.base)" \
  "…and the job runs for an edit only when the edit changes the base branch, and for a tests run only when a pull request started it"
GROUP=$(grep -E '^  group:' "$WF")
eq "$GROUP" "  group: pr-size-\${{ github.event.pull_request.number || github.event.workflow_run.event == 'pull_request' && github.event.workflow_run.pull_requests[0].number || github.run_id }}\${{ github.event.action == 'edited' && !github.event.changes.base && format('-{0}', github.run_id) || '' }}" \
  "…and every run whose job measures takes its pull request's concurrency group, while any other edit and the end of a tests run no pull request started take groups of their own, so they cancel no run that measures"
hasnt "$GROUP" event_name "…so the event that started a run never sets it apart, and no two runs write one pull request's comment at once"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
