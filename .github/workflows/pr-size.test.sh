#!/usr/bin/env bash
# pr-size.test.sh — pr-size.sh keeps one comment current with a pull request's
# size, measured with the merge base's tool and plan, and with the suite's time
# below it. It measures the head and base the pull request has when the run
# starts, and writes only while the pull request still has them. pr-size.yml
# runs as the default branch carries it, from the tip of the pull request's
# base branch. It measures when a pull request's run of pr-size-start.yml
# succeeds, which each push and each change of that branch start, and when one
# of its tests runs passes or fails. Every run that measures one pull request
# takes that pull request's one concurrency group, and every other run a group
# of its own.
# pr-size-start.yml runs on a pull request into any branch and runs nothing
# from it, and no workflow runs on pull_request_target.
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
#
# The workflow cases read every YAML file under .github/ with Psych, the YAML
# parser Ruby ships, so a workflow added later is held to them with no edit
# here. A judge evaluates the expressions that decide whether a run measures
# and which concurrency group it takes, for a sample of each event that starts
# one, and fixture cases first prove the judge on the rules GitHub's
# expressions reference states. Needs ruby, with the Psych it bundles.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/pr-size.sh"
WF="$HERE/pr-size.yml"
START_WF="$HERE/pr-size-start.yml"
TOOL="$ROOT/tools/measure.sh"
PR_POST="$ROOT/assets/scripts/pr-post.sh"
for f in "$SUT" "$WF" "$START_WF" "$TOOL" "$PR_POST"; do
  [ -f "$f" ] || { echo "pr-size.test.sh: cannot find $f" >&2; exit 2; }
done
ruby -e 'require "psych"' 2>/dev/null \
  || { echo "pr-size.test.sh: needs ruby with Psych, its YAML parser, to read the workflows" >&2; exit 2; }
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

echo "# every YAML file under .github/ is read as a YAML parser reads it"
# yaml_json <file>...: one line for each file, the JSON of what Psych reads from
# it, with on under its own name, since YAML 1.1, which Psych follows, reads
# that key as true. A file that does not parse gets its error instead.
yaml_json() {
  ruby -rpsych -rjson -e '
    ARGV.each do |f|
      begin
        d = Psych.safe_load(File.read(f), aliases: true)
        d["on"] = d.delete(true) if d.is_a?(Hash) && d.key?(true)
        puts JSON.generate("file" => f, "doc" => d)
      rescue StandardError => e
        puts JSON.generate("file" => f, "error" => "#{e.class}: #{e.message}")
      end
    end' "$@"
}
YML=()
while IFS= read -r f; do YML+=("$f"); done < <(find "$ROOT/.github" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
YAMLS=$(yaml_json "${YML[@]}")
doc_of() { printf '%s\n' "$YAMLS" | jq -c --arg f "$1" 'select(.file == $f) | .doc'; }
SIZE_DOC=$(doc_of "$WF")
START_DOC=$(doc_of "$START_WF")
TESTS_NAME=$(doc_of "$HERE/tests.yml" | jq -r '.name // empty')
START_NAME=$(printf '%s' "$START_DOC" | jq -r '.name // empty')
eq "$(printf '%s\n' "$YAMLS" | jq -r 'select(.error) | "\(.file): \(.error)"')" "" "each of them parses"

# The judge: for each sample event on stdin, a github context on a JSON line of
# its own with the case it stands for, whether the workflow's one job runs, the
# concurrency group the run takes, and the env of its steps, as GitHub renders
# them. Its argument is the workflow, as a JSON file. It evaluates as much of
# GitHub's expression syntax as these workflows use: string, number, boolean and
# null literals, property and index access, !, == and !=, && and ||, parentheses
# and format(). Anything else is an error, so an expression that outgrows it
# fails the suite instead of being misread. It follows the rules of GitHub's
# expressions reference: && and || each return one of their operands, false, 0,
# '' and null are falsy, a property that is not there is null, strings compare
# ignoring case, and operands of two types compare as numbers.
JUDGE="$TMP/judge.rb"
cat > "$JUDGE" <<'RUBY'
require 'json'

module Expr
  module_function

  def lex(src)
    toks = []
    rest = src
    until rest.empty?
      if (m = rest.match(/\A\s+/))
        nil
      elsif (m = rest.match(/\A'((?:[^']|'')*)'/))
        toks << [:lit, m[1].gsub("''", "'")]
      elsif (m = rest.match(/\A(?:==|!=|&&|\|\||[!()\[\].,])/))
        toks << [:op, m[0]]
      elsif (m = rest.match(/\A\d+/))
        toks << [:lit, m[0].to_i]
      elsif (m = rest.match(/\A[A-Za-z_][\w-]*/))
        word = { 'true' => [:lit, true], 'false' => [:lit, false], 'null' => [:lit, nil] }
        toks << word.fetch(m[0], [:id, m[0]])
      else
        raise "cannot read #{rest.inspect} in #{src.inspect}"
      end
      rest = m.post_match
    end
    toks
  end

  class Parser
    def initialize(src)
      @src = src
      @toks = Expr.lex(src)
    end

    def parse
      tree = disjunction
      raise "#{@src.inspect} goes on past its expression" unless @toks.empty?
      tree
    end

    private

    def at?(op)
      @toks.first == [:op, op]
    end

    def take(op = nil)
      t = @toks.shift
      raise "#{@src.inspect} ends before its expression does" if t.nil?
      raise "#{@src.inspect} has #{t[1].inspect} where #{op} goes" if op && t != [:op, op]
      t
    end

    def disjunction
      tree = conjunction
      while at?('||')
        take
        tree = [:or, tree, conjunction]
      end
      tree
    end

    def conjunction
      tree = comparison
      while at?('&&')
        take
        tree = [:and, tree, comparison]
      end
      tree
    end

    def comparison
      tree = negation
      while at?('==') || at?('!=')
        op = take[1] == '==' ? :eq : :ne
        tree = [op, tree, negation]
      end
      tree
    end

    def negation
      return access unless at?('!')
      take
      [:not, negation]
    end

    def access
      tree = primary
      loop do
        if at?('.')
          take
          t = take
          raise "#{@src.inspect} has #{t[1].inspect} after a dot" unless t[0] == :id
          tree = [:prop, tree, t[1]]
        elsif at?('[')
          take
          tree = [:index, tree, disjunction]
          take(']')
        else
          return tree
        end
      end
    end

    def primary
      t = take
      return [:lit, t[1]] if t[0] == :lit
      if t[0] == :id
        return [:ctx, t[1]] unless at?('(')
        take('(')
        args = []
        until at?(')')
          take(',') unless args.empty?
          args << disjunction
        end
        take(')')
        return [:call, t[1], args]
      end
      raise "#{@src.inspect} has #{t[1].inspect} where a value goes" unless t == [:op, '(']
      tree = disjunction
      take(')')
      tree
    end
  end

  def kind(v)
    case v
    when nil then :null
    when true, false then :bool
    when Numeric then :number
    when String then :string
    else :object
    end
  end

  def truthy(v)
    case kind(v)
    when :null then false
    when :bool then v
    when :number then !(v.zero? || v.to_f.nan?)
    when :string then !v.empty?
    else true
    end
  end

  def number(v)
    case kind(v)
    when :null then 0.0
    when :bool then v ? 1.0 : 0.0
    when :number then v.to_f
    when :string
      s = v.strip
      return 0.0 if s.empty?
      s.match?(/\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/) ? s.to_f : Float::NAN
    else Float::NAN
    end
  end

  def same(a, b)
    return number(a) == number(b) unless kind(a) == kind(b)
    case kind(a)
    when :string then a.casecmp(b).zero?
    when :object then a.equal?(b)
    else a == b
    end
  end

  def text(v)
    case kind(v)
    when :null then ''
    when :number then v.is_a?(Integer) || !v.finite? || v != v.floor ? v.to_s : v.to_i.to_s
    when :object then v.is_a?(Array) ? 'Array' : 'Object'
    else v.to_s
    end
  end

  def value(tree, ctx)
    case tree[0]
    when :lit then tree[1]
    when :ctx then ctx[tree[1]]
    when :prop
      o = value(tree[1], ctx)
      o.is_a?(Hash) ? o[tree[2]] : nil
    when :index
      o = value(tree[1], ctx)
      i = value(tree[2], ctx)
      if o.is_a?(Array) && i.is_a?(Integer) && i >= 0 then o[i]
      elsif o.is_a?(Hash) && i.is_a?(String) then o[i]
      end
    when :not then !truthy(value(tree[1], ctx))
    when :eq then same(value(tree[1], ctx), value(tree[2], ctx))
    when :ne then !same(value(tree[1], ctx), value(tree[2], ctx))
    when :and
      l = value(tree[1], ctx)
      truthy(l) ? value(tree[2], ctx) : l
    when :or
      l = value(tree[1], ctx)
      truthy(l) ? l : value(tree[2], ctx)
    when :call
      raise "#{tree[1]}() is not a function the judge evaluates" unless tree[1].casecmp('format').zero?
      args = tree[2].map { |a| text(value(a, ctx)) }
      args.fetch(0, '').gsub(/\{\{|\}\}|\{(\d+)\}/) do |m|
        if m == '{{' then '{'
        elsif m == '}}' then '}'
        else args.fetch(Regexp.last_match(1).to_i + 1) { raise "format() has no argument for #{m}" }
        end
      end
    end
  end

  def evaluate(src, ctx)
    value(Parser.new(src).parse, ctx)
  end

  # The index of the }} that closes an expression begun before from, past any
  # }} inside a string.
  def close(s, from)
    quoted = false
    (from...s.length).each do |i|
      if s[i] == "'"
        quoted = !quoted
      elsif !quoted && s[i, 2] == '}}'
        return i
      end
    end
    raise "#{s.inspect} leaves an expression open"
  end

  # A value with ${{ }} in it, as GitHub renders it: the text around each
  # expression, and each expression's value as text.
  def render(s, ctx)
    out = String.new
    rest = s.to_s
    while (i = rest.index('${{'))
      out << rest[0, i]
      j = close(rest, i + 3)
      out << text(evaluate(rest[(i + 3)...j], ctx))
      rest = rest[(j + 2)..-1]
    end
    out << rest
  end

  # A job's if:, which GitHub reads with or without ${{ }} around it. A job
  # with no if: runs.
  def runs?(cond, ctx)
    return true if cond.nil?
    s = cond.to_s.strip
    s = s[3...-2] if s.start_with?('${{') && close(s, 3) == s.length - 2
    truthy(evaluate(s, ctx))
  end
end

wf = JSON.parse(File.read(ARGV[0]))
jobs = wf['jobs']
unless jobs.is_a?(Hash) && jobs.size == 1
  raise "#{ARGV[0]} holds #{jobs.is_a?(Hash) ? jobs.size : 'no'} jobs, and the judge reads a workflow of one"
end
job = jobs.values.first
conc = wf['concurrency']
group = conc.is_a?(Hash) ? conc['group'] : conc
STDIN.each_line do |line|
  sample = JSON.parse(line)
  ctx = { 'github' => sample['github'] }
  env = {}
  (job['steps'] || []).each { |st| (st['env'] || {}).each { |k, v| env[k] = Expr.render(v, ctx) } }
  puts JSON.generate('case' => sample['case'], 'job' => Expr.runs?(job['if'], ctx) ? 'runs' : 'skips',
                     'group' => group.nil? ? nil : Expr.render(group, ctx), 'env' => env)
end
RUBY

echo "# the judge follows GitHub's rules for expressions"
# Each fixture: what it shows, the value GitHub renders, and the value with
# expressions in it, rendered as a step's env against a github context that
# holds n, a list and an empty list.
FIXTURES=$(cat <<'EOF'
[
  ["strings compare ignoring case", "true", "${{ 'tests' == 'TESTS' }}"],
  ["!= is the negation of ==", "false", "${{ 'tests' != 'Tests' }}"],
  ["|| returns its first truthy operand", "x", "${{ github.none || 'x' }}"],
  ["&& returns its first falsy operand", "", "${{ '' && 'x' }}"],
  ["…and its last operand when both are truthy", "7", "${{ 'x' && github.n }}"],
  ["&& binds tighter than ||", "true", "${{ true || false && false }}"],
  ["! negates whether a value is truthy", "true", "${{ !github.none }}"],
  ["operands of two types compare as numbers, '' as 0", "true", "${{ 0 == '' }}"],
  ["…true as 1", "true", "${{ 1 == true }}"],
  ["…and a string that is no number as no number at all", "false", "${{ 'x' == 0 }}"],
  ["a property that is not there is null, which renders as nothing", "", "${{ github.no.such.property }}"],
  ["an object is truthy", "yes", "${{ github.list[0] && 'yes' }}"],
  ["an index past an array's end is null", "", "${{ github.empty[0] && 'yes' }}"],
  ["an index and a property read into the context", "7", "${{ github.list[0].n }}"],
  ["format() puts its arguments in place of {N}, and {{ and }} stand for braces", "{-7}", "${{ format('{{-{0}}}', github.n) }}"],
  ["'' stands for a quote inside a string", "it's", "${{ 'it''s' }}"],
  ["the text around each expression is kept", "pr-size-7-x", "pr-size-${{ github.n }}-${{ 'x' }}"]
]
EOF
)
printf '%s' "$FIXTURES" | jq -c '{jobs: {fixtures: {steps: [{env: (to_entries | map({key: "F\(.key)", value: .value[2]}) | from_entries)}]}}}' > "$TMP/fixtures.json"
RENDERED=$(printf '%s\n' '{"case": "fixtures", "github": {"n": 7, "list": [{"n": 7}], "empty": []}}' | ruby "$JUDGE" "$TMP/fixtures.json" 2>&1)
for ((i = 0; i < $(printf '%s' "$FIXTURES" | jq length); i++)); do
  eq "$(printf '%s' "$RENDERED" | jq -r --arg k "F$i" '.env[$k]' 2>&1)" "$(printf '%s' "$FIXTURES" | jq -r ".[$i][1]")" \
    "$(printf '%s' "$FIXTURES" | jq -r ".[$i][0]")"
done
printf '%s' '{"jobs": {"fixtures": {"steps": [{"env": {"F": "${{ contains(github.list, 7) }}"}}]}}}' > "$TMP/unknown.json"
printf '%s\n' '{"case": "unknown", "github": {}}' | ruby "$JUDGE" "$TMP/unknown.json" >/dev/null 2>&1
eq "$?" 1 "a function the judge does not evaluate is an error, not a guess"

echo "# pr-size.yml starts when a run of tests.yml or pr-size-start.yml ends, and runs as the default branch carries it"
eq "$(printf '%s' "$SIZE_DOC" | jq -c '.on | keys')" '["workflow_run"]' \
  "it runs on workflow_run alone, which takes the job from the default branch, and on no event that runs the pull request's own copy of it"
eq "$(printf '%s' "$SIZE_DOC" | jq -cS '.on.workflow_run | .workflows |= sort')" \
  "$(jq -ncS --arg t "$TESTS_NAME" --arg s "$START_NAME" '{workflows: ([$t, $s] | sort), types: ["completed"]}')" \
  "…when a run of tests.yml or of pr-size-start.yml completes, whatever branch it ran on"
eq "$(grep -cE '^[[:space:]]*ref:' "$WF")" 0 "its checkout takes no ref, so it checks out the default branch and never the head"
CODE=$(grep -vE '^[[:space:]]*#' "$WF")
has "$CODE" '--repo "${GITHUB_SERVER_URL#https://}/$GITHUB_REPOSITORY" --pr "$PR_NUMBER"' "it hands pr-size.sh the pull request"
eq "$(printf '%s\n' "$CODE" | grep -cE 'head\.sha|head_sha|base\.ref|--head|--base')" 0 \
  "…and no head or base from the event, which can be older than the pull request"
hasnt "$CODE" GITHUB_SHA "…nor GITHUB_SHA, which is the default branch's tip under workflow_run"
has "$CODE" "  actions: read" "…and may read a run's jobs and artifacts"

echo "# pr-size-start.yml runs on every pull request and runs nothing from it"
eq "$(printf '%s' "$START_DOC" | jq -cS '.on')" '{"pull_request":{"types":["opened","synchronize","reopened","edited"]}}' \
  "it runs on pull_request when a pull request opens, reopens, takes a push or is edited, and filters no branch, so a pull request into any branch runs it"
eq "$(printf '%s' "$START_DOC" | jq -c '.permissions')" '{}' \
  "…and holds no permissions, since pull_request runs it as the pull request's merge commit carries it"
eq "$(printf '%s' "$START_DOC" | jq -c 'keys_unsorted - ["name", "on", "permissions", "jobs"]')" '[]' \
  "…and sets no env, defaults or concurrency group, so no run of it cancels another"
eq "$(printf '%s' "$START_DOC" | jq -c '[(.jobs | length), (.jobs[] | keys_unsorted - ["name", "if", "runs-on", "timeout-minutes", "steps"])]')" '[1,[]]' \
  "…and its one job grants itself no permissions, takes no env and calls no other workflow"
eq "$(printf '%s' "$START_DOC" | jq -c '[.jobs[].steps | length, (.[] | keys_unsorted - ["name", "run"])]')" '[1,[]]' \
  "…and has one step, which uses no action, so nothing is checked out"
eq "$(printf '%s' "$START_DOC" | jq -r '.jobs[].steps[].run | contains("${{")')" false \
  "…and whose command takes no expression, so nothing of the pull request's reaches the shell"

echo "# no workflow runs on pull_request_target"
eq "$(printf '%s\n' "$YAMLS" | jq -r '
    select((if (.doc | type) == "object" then .doc.on else null end)
           | if type == "string" then [.] elif type == "array" then . elif type == "object" then keys else [] end
           | index("pull_request_target"))
    | .file')" "" \
  "no workflow under .github/ runs on pull_request_target, which GitHub's default event policy blocks in a public repository"

echo "# pr-size-start.yml's job runs when a pull request's head or base moves, and skips any other edit"
printf '%s' "$START_DOC" > "$TMP/start.json"
# pr_event <case> <action> [<draft>] [<changes>]: the github context of a
# pull_request event on pull request 7.
pr_event() {
  jq -nc --arg c "$1" --arg a "$2" --argjson d "${3:-false}" --argjson ch "${4:-null}" \
    '{case: $c, github: {event_name: "pull_request", run_id: "500",
      event: ({action: $a, number: 7, pull_request: {number: 7, draft: $d}}
              + (if $ch == null then {} else {changes: $ch} end))}}'
}
STARTS=$( {
  pr_event opened opened true
  pr_event draft-push synchronize true
  pr_event ready-push synchronize false
  pr_event reopened reopened
  pr_event title-edit edited false '{"title": {"from": "an earlier title"}}'
  pr_event body-edit edited false '{"body": {"from": "an earlier body"}}'
  pr_event base-change edited false '{"base": {"ref": {"from": "main"}, "sha": {"from": "0123456789abcdef0123456789abcdef01234567"}}}'
} | ruby "$JUDGE" "$TMP/start.json" 2>"$TMP/judge.err")
eq "$?:$(cat "$TMP/judge.err")" "0:" "the judge reads pr-size-start.yml"
job_of() { printf '%s\n' "$2" | jq -r --arg c "$1" 'select(.case == $c) | .job'; }
eq "$(job_of opened "$STARTS")" runs "a pull request that opens runs the job"
eq "$(job_of draft-push "$STARTS")" runs "…and so does a push to a draft, whose tests run skips every job"
eq "$(job_of ready-push "$STARTS")" runs "…a push to a pull request that is ready"
eq "$(job_of reopened "$STARTS")" runs "…a pull request that reopens"
eq "$(job_of base-change "$STARTS")" runs "…and an edit that changes the branch the pull request merges into"
eq "$(job_of title-edit "$STARTS")" skips "an edit of the title skips the job"
eq "$(job_of body-edit "$STARTS")" skips "…and so does an edit of the body"

echo "# pr-size.yml measures when a pull request's run ends with something to show, and only then takes the pull request's group"
printf '%s' "$SIZE_DOC" > "$TMP/size.json"
# run_ended <case> <workflow> <conclusion> <event> <pull requests> <run id>: the
# github context of a workflow_run event for a run that completed.
run_ended() {
  jq -nc --arg c "$1" --arg w "$2" --arg k "$3" --arg e "$4" --argjson p "$5" --arg id "$6" \
    '{case: $c, github: {event_name: "workflow_run", run_id: $id,
      event: {action: "completed",
              workflow_run: {name: $w, status: "completed", conclusion: $k, event: $e, pull_requests: $p}}}}'
}
PR7='[{"number": 7, "head": {"ref": "polecat/tk-x", "sha": "fedcba9876543210fedcba9876543210fedcba98"}, "base": {"ref": "integration/tk-y", "sha": "0123456789abcdef0123456789abcdef01234567"}}]'
ENDS=$( {
  run_ended start-success "$START_NAME" success pull_request "$PR7" 601
  run_ended start-skipped "$START_NAME" skipped pull_request "$PR7" 602
  run_ended start-failure "$START_NAME" failure pull_request "$PR7" 603
  run_ended start-cancelled "$START_NAME" cancelled pull_request "$PR7" 604
  run_ended tests-success "$TESTS_NAME" success pull_request "$PR7" 605
  run_ended tests-failure "$TESTS_NAME" failure pull_request "$PR7" 606
  run_ended tests-skipped "$TESTS_NAME" skipped pull_request "$PR7" 607
  run_ended tests-cancelled "$TESTS_NAME" cancelled pull_request "$PR7" 608
  run_ended tests-on-main "$TESTS_NAME" success push '[]' 609
  run_ended tests-push-names-pr "$TESTS_NAME" success push "$PR7" 612
  run_ended tests-no-pr "$TESTS_NAME" success pull_request '[]' 610
  run_ended start-no-pr "$START_NAME" success pull_request '[]' 611
} | ruby "$JUDGE" "$TMP/size.json" 2>"$TMP/judge.err")
eq "$?:$(cat "$TMP/judge.err")" "0:" "the judge reads pr-size.yml"
end_of() { printf '%s\n' "$2" | jq -r --arg c "$1" 'select(.case == $c) | "\(.job) \(.group)"'; }
eq "$(end_of start-success "$ENDS")" "runs pr-size-7" \
  "the end of a pr-size-start.yml run that succeeded, which a push or a change of base branch starts, measures the pull request in its group"
eq "$(end_of tests-success "$ENDS")" "runs pr-size-7" "…and so does the end of a tests run that passed, which brings the suite's time"
eq "$(end_of tests-failure "$ENDS")" "runs pr-size-7" "…or that failed"
eq "$(printf '%s\n' "$ENDS" | jq -r 'select(.job == "runs") | .env.PR_NUMBER' | sort -u)" 7 \
  "…and each hands pr-size.sh the pull request that GitHub names in the run's pull_requests"
eq "$(end_of tests-skipped "$ENDS")" "skips pr-size-607" \
  "the end of a draft's tests run, whose jobs all skip, measures nothing and takes a group of its own, so it cannot cancel the run that the end of the same push's pr-size-start.yml run started"
eq "$(end_of tests-cancelled "$ENDS")" "skips pr-size-608" "…and so does the end of a tests run that was cancelled"
eq "$(end_of start-skipped "$ENDS")" "skips pr-size-602" "…of a pr-size-start.yml run that an edit of the title or body skipped"
eq "$(end_of start-failure "$ENDS")" "skips pr-size-603" "…of one that failed"
eq "$(end_of start-cancelled "$ENDS")" "skips pr-size-604" "…or that was cancelled"
eq "$(end_of tests-on-main "$ENDS")" "skips pr-size-609" "…of a tests run that a push to main started"
eq "$(end_of tests-push-names-pr "$ENDS")" "skips pr-size-612" "…even one whose run names a pull request, since a pull request did not start it"
eq "$(end_of tests-no-pr "$ENDS")" "skips pr-size-610" "…and of a tests run or a pr-size-start.yml run that names no pull request, as a fork's does"
eq "$(end_of start-no-pr "$ENDS")" "skips pr-size-611" "…whichever workflow it is"
eq "$(printf '%s\n' "$ENDS" | jq -r 'select((.job == "runs") != (.group == "pr-size-7")) | .case')" "" \
  "a run takes the pull request's group exactly when its job measures, so the group's expression and the job's condition agree"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
