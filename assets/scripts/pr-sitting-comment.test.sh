#!/usr/bin/env bash
# pr-sitting-comment.test.sh — hermetic coverage of the sitting→PR comment
# primitive. Self-locates the script under test, stubs gc and gh (the gh stub
# keeps a stateful comment store so upsert and update-only are provable), works
# in its own git repo with a fabricated origin, and exits nonzero on any failed
# assertion.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/pr-sitting-comment.sh"
[ -x "$SUT" ] || { echo "not found or not executable: $SUT" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required for this test" >&2; exit 2; }

FAIL=0
ok()   { if eval "$2"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAIL=1; fi; }
has()   { case "$2" in *"$1"*) printf 'ok   - %s\n' "$3" ;; *) printf 'FAIL - %s\n     wanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'FAIL - %s\n     unwanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; *) printf 'ok   - %s\n' "$3" ;; esac; }
same()  { if [ "$1" = "$2" ]; then printf 'ok   - %s\n' "$3"; else printf 'FAIL - %s\n     wanted: %s\n     got:    %s\n' "$3" "$1" "$2"; FAIL=1; fi; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/pr-sitting-comment.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; mkdir -p "$BIN"

# A git repo whose origin fabricates our owned repository.
REPO="$TMPD/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" remote add origin https://github.com/acme/widgets.git

# gc stub: `gc bd show <id> --json` and `gc rig list --json`. The subject's PR
# binding ($PR_NUMBER / $PR_URL) is what a comment lands on. `rig list` counts
# each read in $RIG_LIST_LOG and answers the city: the subject's rig, `fixture`,
# mapping $RIG_PREFIX to $RIG_PATH, and one other rig, `rig-b`, prefix `rb`. With
# no $RIG_PATH planted, fixture's path is not a directory, so the helper falls
# back to the cwd origin, the path the git-repo-cwd cases below exercise. $RIG_LIST
# changes the answer: `empty` lists no rigs, and `fail` does not answer.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
  printf 'read\n' >>"${RIG_LIST_LOG:-/dev/null}"
  case "${RIG_LIST:-}" in
    empty) printf '{"rigs":[]}\n'; exit 0 ;;
    fail)  echo "the store did not answer" >&2; exit 1 ;;
  esac
  jq -nc --arg p "${RIG_PREFIX:-tk}" --arg path "${RIG_PATH:-/nonexistent/fixture}" \
    '{rigs:[{name:"fixture",prefix:$p,path:$path},{name:"rig-b",prefix:"rb",path:"/nonexistent/rig-b"}]}'
  exit 0
fi
[ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ] || exit 0
jq -nc --arg n "${PR_NUMBER:-}" --arg u "${PR_URL:-}" \
  '[{id:"tk-sub", metadata:( ({} + (if $n=="" then {} else {pr_number:$n} end)) + (if $u=="" then {} else {pr_url:$u} end) )}]'
STUB
chmod +x "$BIN/gc"

# gh stub: a JSON array in $STATE is the PR's issue-comment thread.
#   pr comment  -> append {id, body}                 (create)
#   api GET .../issues/<n>/comments  -> print $STATE  (list)
#   api PATCH .../issues/comments/<id> -f body=..     -> replace that body (edit)
# Every call is logged to $GHLOG.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gh" <<'STUB'
printf '%s\0' "$@" >>"${GHLOG:?}.argv"
printf '%s\n' "$*" >>"${GHLOG:?}"
STATE="${STATE:?}"
[ -s "$STATE" ] || printf '[]' >"$STATE"
verb="${1:-}"; shift || true
case "$verb" in
  pr)
    [ "${1:-}" = "comment" ] || exit 0
    body=""; while [ $# -gt 0 ]; do case "$1" in --body) shift; body="$1" ;; esac; shift; done
    id=$(( $(jq 'length' "$STATE") + 100 ))
    jq --argjson id "$id" --arg b "$body" '. + [{id:$id, body:$b}]' "$STATE" >"$STATE.t" && mv "$STATE.t" "$STATE"
    ;;
  api)
    method="GET"; path=""; field=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --method) shift; method="$1" ;;
        --hostname) shift ;;
        --paginate) : ;;
        -f|-F|--field|--raw-field) shift; field="$1" ;;
        -*) : ;;
        *) [ -z "$path" ] && path="$1" ;;
      esac
      shift
    done
    if [ "$method" = "GET" ]; then
      cat "$STATE"
    else
      cid="${path##*/}"; body="${field#body=}"
      jq --argjson id "$cid" --arg b "$body" 'map(if .id==$id then .body=$b else . end)' "$STATE" >"$STATE.t" && mv "$STATE.t" "$STATE"
    fi
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN/gh"

STATE="$TMPD/comments.json"
run() { # <ghlog-tag> <pr_number> <pr_url> -- <sut args...>
  local tag="$1" prn="$2" pru="$3"; shift 3; [ "${1:-}" = "--" ] && shift
  GHLOG="$TMPD/gh.$tag.log"; : >"$GHLOG"; : >"$GHLOG.argv"
  ( cd "$REPO" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" PR_NUMBER="$prn" PR_URL="$pru" bash "$SUT" "$@" ) >"$TMPD/out.$tag" 2>"$TMPD/err.$tag"
  echo $?
}
PR41="https://github.com/acme/widgets/pull/41"
body_of() { jq -r --arg m "<!-- gc:sitting:$1 -->" '.[] | select(.body|contains($m)) | .body' "$STATE"; }
# The lines this script composes, without the mark pr-post.sh adds below them.
lines_of() { body_of "$1" | head -n "$2"; }
nl=$'\n'
# A comment already on the thread: what an earlier post left, this script's or
# one of the shapes it wrote before.
plant() { # <conversation> <body lines after the marker>
  jq -n --arg b "<!-- gc:sitting:$1 -->$nl$2$nl" '[{id:100, body:$b}]' >"$STATE"
}
# An open comment, as `topic` leaves one, then a close of it.
open_then_close() { # <tag> <conversation> <topic> <close args...>
  local tag=$1 conv=$2 topic=$3; shift 3
  printf '[]' >"$STATE"
  run "$tag-t" 41 "$PR41" -- topic --sitting "$conv" --subject tk-sub --topic "$topic" >/dev/null
  run "$tag" 41 "$PR41" -- close --sitting "$conv" --subject tk-sub "$@"
}

echo "# topic on a subject with a PR posts the open comment"
printf '[]' >"$STATE"
rc=$(run c1 41 "$PR41" -- topic --sitting tk-conv1 --subject tk-sub --topic "what the PR reminder fix solves")
ok "topic exits 0" "[ '$rc' = 0 ]"
GH1="$(cat "$TMPD/gh.c1.log")"
has "pr comment 41" "$GH1" "topic posts a new comment on PR 41"
has "--repo github.com/acme/widgets" "$GH1" "the post is pinned to origin"
same "<!-- gc:sitting:tk-conv1 -->$nl### Under discussion: what the PR reminder fix solves$nl(visit tk-conv1 · updated with the action taken when it ends)" \
  "$(lines_of tk-conv1 3)" "the comment names the topic under discussion and the visit, and says it is updated when the visit ends"
has "<!-- gc:city -->" "$(body_of tk-conv1)" "the comment carries the city's provenance mark (posted through pr-post.sh)"

echo "# naming a new topic refreshes the same comment"
rc=$(run c2 41 "$PR41" -- topic --sitting tk-conv1 --subject tk-sub --topic "whether to retire it")
ok "a second topic exits 0" "[ '$rc' = 0 ]"
GH2="$(cat "$TMPD/gh.c2.log")"
has "PATCH" "$GH2" "the second topic edits the comment"
hasnt "pr comment" "$GH2" "...and posts no second comment"
ok "still exactly one comment on the thread" "[ \$(jq 'length' '$STATE') -eq 1 ]"
has "### Under discussion: whether to retire it" "$(body_of tk-conv1)" "the comment names the new topic"
hasnt "what the PR reminder fix solves" "$(body_of tk-conv1)" "...in place of the old one"

echo "# close edits the same comment: the topic discussed and the action taken"
rc=$(run c3 41 "$PR41" -- close --sitting tk-conv1 --subject tk-sub --outcome rework --summary "this comment shows a visit's topic and the action taken")
ok "close exits 0" "[ '$rc' = 0 ]"
GH3="$(cat "$TMPD/gh.c3.log")"
has "PATCH" "$GH3" "close edits the comment in place"
hasnt "pr comment" "$GH3" "close never posts a new comment"
same "<!-- gc:sitting:tk-conv1 -->$nl### Discussed: whether to retire it${nl}Action taken: sent back for rework; this comment shows a visit's topic and the action taken.$nl(visit tk-conv1)" \
  "$(lines_of tk-conv1 4)" "the comment names the last topic, the action taken with the sitting's outcome, and the visit"
has "<!-- gc:city -->" "$(body_of tk-conv1)" "the edited comment keeps the city's provenance mark"
ok "still exactly one comment after close" "[ \$(jq 'length' '$STATE') -eq 1 ]"

echo "# each act reads as its plain action"
for pair in "rework|sent back for rework" "retired|retired" "accepted|its recommended work started" \
            "ruled|none" "moot|none" "benign|none" \
            "handed back|none; the visit went back to the operator's queue undecided" \
            "dismissed|none; the visit was dismissed"; do
  word=${pair%%|*}; said=${pair#*|}
  rc=$(open_then_close a1 tk-convA "explain the warrant" --outcome "$word")
  ok "close --outcome '$word' exits 0" "[ '$rc' = 0 ]"
  BODYA="$(lines_of tk-convA 4)"
  same "<!-- gc:sitting:tk-convA -->$nl### Discussed: explain the warrant${nl}Action taken: $said.$nl(visit tk-convA)" \
    "$BODYA" "'$word' reads: Action taken: $said."
  for word_out in "Sitting on" "Subject:" "Reason" "Summary" "Actions Taken" "settled" "ruled" "$word"; do
    case "$said" in *"$word_out"*) continue ;; esac
    hasnt "$word_out" "$BODYA" "'$word' leaves '$word_out' off the post"
  done
done
rc=$(open_then_close a2 tk-convA "explain the warrant" --outcome ruled --summary "the question was answered")
same "Action taken: none; the question was answered." "$(lines_of tk-convA 3 | tail -n1)" "a ruling that changed nothing reads none, then the sitting's outcome"
rc=$(open_then_close a3 tk-convA "explain the warrant" --outcome retired --summary "the work moved to its successor!")
same "Action taken: retired; the work moved to its successor!" "$(lines_of tk-convA 3 | tail -n1)" "an outcome that ends a sentence takes no second stop"

echo "# nothing but the act words says what the visit did"
printf '[]' >"$STATE"
run x0 41 "$PR41" -- topic --sitting tk-convU --subject tk-sub --topic "a topic" >/dev/null
for word in settled "a word naming rig-b" ""; do
  rc=$(run x1 41 "$PR41" -- close --sitting tk-convU --subject tk-sub --outcome "$word" --summary "plain")
  ok "close refuses --outcome '$word' as a usage error" "[ '$rc' = 2 ]"
  ok "...and makes no gh call ('$word')" "[ ! -s '$TMPD/gh.x1.log' ]"
done
rc=$(run x2 41 "$PR41" -- close --sitting tk-convU --subject tk-sub --summary "plain")
ok "close with no --outcome is a usage error" "[ '$rc' = 2 ]"
rc=$(run x3 41 "$PR41" -- topic --sitting tk-convU --subject tk-sub)
ok "topic with no --topic is a usage error" "[ '$rc' = 2 ]"
rc=$(run x3 41 "$PR41" -- topic --sitting tk-convU --subject tk-sub --topic " "$'\n'"  ")
ok "topic with a blank --topic is a usage error" "[ '$rc' = 2 ]"
ok "...and makes no gh call" "[ ! -s '$TMPD/gh.x3.log' ]"
has "### Under discussion: a topic" "$(body_of tk-convU)" "the open comment is left as it was"

echo "# a visit that closes before its sitting names a topic posts nothing"
for word in moot benign dismissed; do
  printf '[]' >"$STATE"
  rc=$(run n1 41 "$PR41" -- close --sitting tk-conv2 --subject tk-sub --outcome "$word" --summary "premise died")
  ok "a $word close with no comment exits 0" "[ '$rc' = 0 ]"
  GHN="$(cat "$TMPD/gh.n1.log")"
  hasnt "pr comment" "$GHN" "no comment is created by a $word close"
  hasnt "PATCH" "$GHN" "nothing is edited by a $word close"
  ok "the thread stays empty after a $word close" "[ \$(jq 'length' '$STATE') -eq 0 ]"
done

echo "# a subject with no PR does nothing"
printf '[]' >"$STATE"
rc=$(run c5 "" "" -- topic --sitting tk-conv3 --subject tk-sub --topic "a topic")
ok "no-PR topic exits 0" "[ '$rc' = 0 ]"
ok "no gh call was made for a PR-less subject" "[ ! -s '$TMPD/gh.c5.log' ]"

echo "# a PR that lives outside our origin is refused"
printf '[]' >"$STATE"
rc=$(run c6 7 "https://github.com/someone-else/theirs/pull/7" -- topic --sitting tk-conv4 --subject tk-sub --topic "a topic")
ok "not-ours topic exits 0 (fail-safe)" "[ '$rc' = 0 ]"
ok "nothing was posted for a foreign PR" "[ ! -s '$TMPD/gh.c6.log' ]"
has "not ours" "$(cat "$TMPD/err.c6")" "it says why it refused"

echo "# the marker keys per conversation — one id being a prefix of another does not collide"
printf '[]' >"$STATE"
run p1 41 "$PR41" -- topic --sitting tk-conv1  --subject tk-sub --topic "topic one" >/dev/null
run p2 41 "$PR41" -- topic --sitting tk-conv10 --subject tk-sub --topic "topic ten" >/dev/null
ok "two sitting comments coexist on the thread" "[ \$(jq 'length' '$STATE') -eq 2 ]"
run p3 41 "$PR41" -- close --sitting tk-conv1 --subject tk-sub --outcome ruled --summary "done" >/dev/null
CLOSED_N="$(jq '[.[] | select((.body|contains("### Discussed")))] | length' "$STATE")"
ok "closing tk-conv1 ends exactly one comment" "[ \"$CLOSED_N\" -eq 1 ]"
has "### Discussed: topic one" "$(body_of tk-conv1)" "the ended comment is tk-conv1's own"
has "### Under discussion: topic ten" "$(body_of tk-conv10)" "tk-conv10 stays open — its marker did not match the tk-conv1 close"

echo "# topic from a NON-git cwd resolves origin off the subject's rig"
# A board-launched dismiss runs from the city root, outside any rig checkout.
# Prove the real helper — not a recorder stub — still posts there, resolving the
# origin from the subject's rig ($RIG_PATH) rather than the git-less cwd.
printf '[]' >"$STATE"
NONGIT="$TMPD/nongit"; mkdir -p "$NONGIT"   # deliberately not a git repo
GHLOG="$TMPD/gh.rig.log"; : >"$GHLOG"; : >"$GHLOG.argv"
( cd "$NONGIT" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" \
    PR_NUMBER=55 PR_URL="https://github.com/acme/widgets/pull/55" RIG_PATH="$REPO" RIG_PREFIX=tk \
    bash "$SUT" topic --sitting tk-convR --subject tk-sub --topic "a topic" ) >"$TMPD/out.rig" 2>"$TMPD/err.rig"
rc=$?
ok "non-git-cwd topic exits 0" "[ '$rc' = 0 ]"
GHR="$(cat "$GHLOG")"
has "pr comment 55" "$GHR" "the reminder posts even though cwd is not a git repo"
has "--repo github.com/acme/widgets" "$GHR" "the post is pinned to the subject's rig origin"
has "### Under discussion: a topic" "$(body_of tk-convR)" "the comment lands in its open shape"

echo "# non-git cwd with no rig match self-silences — no crash, nothing posted"
printf '[]' >"$STATE"
GHLOG="$TMPD/gh.norig.log"; : >"$GHLOG"; : >"$GHLOG.argv"
( cd "$NONGIT" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" RIG_LIST=empty \
    PR_NUMBER=55 PR_URL="https://github.com/acme/widgets/pull/55" \
    bash "$SUT" topic --sitting tk-convN --subject tk-sub --topic "a topic" ) >"$TMPD/out.norig" 2>"$TMPD/err.norig"
rc=$?
ok "no-rig non-git topic exits 0 (fail-safe)" "[ '$rc' = 0 ]"
ok "nothing posted when neither rig nor cwd resolves an origin" "[ ! -s '$TMPD/gh.norig.log' ]"
has "cannot resolve the subject's rig origin" "$(cat "$TMPD/err.norig")" "it says why it could not post"

echo "# no typed text reaches the post: no flag takes it"
printf '[]' >"$STATE"
for args in "topic --topic a-topic --reason typed-words-naming-rig-b" \
            "topic --topic a-topic --summary typed-words-naming-rig-b" \
            "topic --topic a-topic --outcome ruled" \
            "close --outcome ruled --reason typed-words-naming-rig-b" \
            "close --outcome ruled --actions typed-words-naming-rig-b" \
            "close --outcome ruled --topic typed-words-naming-rig-b" \
            "engage"; do
  # shellcheck disable=SC2086 # each case is its own words
  rc=$(run t1 41 "$PR41" -- $args --sitting tk-convT --subject tk-sub)
  ok "refused as a usage error: $args" "[ '$rc' = 2 ]"
  ok "...with no gh call: $args" "[ ! -s '$TMPD/gh.t1.log' ]"
done
ok "...so nothing is posted" "[ \$(jq 'length' '$STATE') -eq 0 ]"

echo "# no typed text reaches the post: an old comment's lines are replaced, never carried"
OLD_OPEN="### Sitting on tk-convF — open$nl- Subject: tk-sub$nl- Reason: typed words naming rig-b and rb-abc12"
OLD_ENDED="### Sitting on tk-convF — ended (settled)$nl- Subject: tk-sub$nl- Reason: typed words naming rig-b$nl- Summary: ruled — fix it$nl- Actions Taken: ruling: fix it (released to human)"
for old in "$OLD_OPEN" "$OLD_ENDED"; do
  plant tk-convF "$old"
  run o1 41 "$PR41" -- topic --sitting tk-convF --subject tk-sub --topic "a fresh topic" >/dev/null
  same "<!-- gc:sitting:tk-convF -->$nl### Under discussion: a fresh topic$nl(visit tk-convF · updated with the action taken when it ends)" \
    "$(lines_of tk-convF 3)" "topic over an old comment writes its own shape"
  hasnt "typed words" "$(body_of tk-convF)" "...and the old comment's reason is gone"
  plant tk-convF "$old"
  rc=$(run o2 41 "$PR41" -- close --sitting tk-convF --subject tk-sub --outcome ruled --summary "fixed on the branch")
  ok "close over an old comment exits 0" "[ '$rc' = 0 ]"
  same "<!-- gc:sitting:tk-convF -->$nl### Discussed${nl}Action taken: none; fixed on the branch.$nl(visit tk-convF)" \
    "$(lines_of tk-convF 4)" "close over an old comment, which names no topic, says the visit ended and the action taken"
  for gone in "typed words" "rig-b" "Sitting on" "Subject:" "Summary" "Actions Taken" "settled" "released to human"; do
    hasnt "$gone" "$(body_of tk-convF)" "...and carries none of the old comment's lines: $gone"
  done
  hasnt "typed words" "$(cat "$TMPD/gh.o2.log")" "...which never reach gh"
done

echo "# a topic or an outcome the check clears reaches the post, and one it lists is left out"
# The subject's own rig and ids, and the rigs the pack runs on or with, are not
# another rig, and a word that only resembles a prefix is not an id.
for clean in "routed tk-work1 in fixture" "shipped on gascity and gc-toolkit" "the rib cage held"; do
  printf '[]' >"$STATE"
  rc=$(run k1 41 "$PR41" -- topic --sitting tk-convC --subject tk-sub --topic "$clean")
  ok "a clean topic posts (exit 0): $clean" "[ '$rc' = 0 ]"
  has "### Under discussion: $clean" "$(body_of tk-convC)" "the topic reaches the post: $clean"
  rc=$(run k1c 41 "$PR41" -- close --sitting tk-convC --subject tk-sub --outcome rework --summary "$clean")
  same "### Discussed: $clean${nl}Action taken: sent back for rework; $clean." "$(lines_of tk-convC 3 | tail -n2)" \
    "the topic and the outcome reach the ended post: $clean"
done
for named in "the same defect on rig-b" "the same defect on Rig B" "see rb-abc12 for it" "see rb-abc12.3 for it" "under /nonexistent/rig-b/assets"; do
  printf '[]' >"$STATE"
  rc=$(run k2 41 "$PR41" -- topic --sitting tk-convC --subject tk-sub --topic "$named")
  ok "a topic naming another rig still posts (exit 0): $named" "[ '$rc' = 0 ]"
  same "<!-- gc:sitting:tk-convC -->$nl### Under discussion$nl(visit tk-convC · updated with the action taken when it ends)" \
    "$(lines_of tk-convC 3)" "the comment still says the visit is open, without the topic: $named"
  hasnt "$named" "$(cat "$TMPD/gh.k2.log")" "the topic never reaches gh: $named"
  has "left the topic off the reminder on PR#41: it names another rig" "$(cat "$TMPD/err.k2")" "it says what it left out: $named"
  rc=$(open_then_close k3 tk-convC "a plain topic" --outcome rework --summary "$named")
  ok "an outcome naming another rig still closes (exit 0): $named" "[ '$rc' = 0 ]"
  same "### Discussed: a plain topic${nl}Action taken: sent back for rework." "$(lines_of tk-convC 3 | tail -n2)" \
    "the action stays and the outcome is left out: $named"
  hasnt "$named" "$(cat "$TMPD/gh.k3.log")" "the outcome never reaches gh: $named"
  has "left the summary off the reminder on PR#41: it names another rig" "$(cat "$TMPD/err.k3")" "it says what it left out: $named"
done
hasnt "rig-b" "$(cat "$TMPD/err.k2" "$TMPD/err.k3")" "the messages do not repeat the text they left out"
printf '[]' >"$STATE"
rc=$(run k4t 41 "$PR41" -- topic --sitting tk-convC --subject tk-sub --topic "the same defect on Rig"$'\n'"B and elsewhere")
same "### Under discussion" "$(lines_of tk-convC 2 | tail -n1)" "a topic naming a rig across two lines is still a name, and is left out"
rc=$(run k4u 41 "$PR41" -- topic --sitting tk-convC --subject tk-sub --topic "  a plain"$'\n'"topic  ")
same "### Under discussion: a plain topic" "$(lines_of tk-convC 2 | tail -n1)" "a topic over two lines posts as one line"
rc=$(open_then_close k4 tk-convC "a plain topic" --outcome ruled --summary "the same defect on Rig"$'\n'"B and elsewhere")
same "Action taken: none." "$(lines_of tk-convC 3 | tail -n1)" "the check reads the text as it would post, so a name split across lines is still a name"
# A topic posted before the check knew a rig, or edited on the PR, is checked
# again when the visit ends.
plant tk-convC "### Under discussion: the same defect on rig-b$nl(visit tk-convC · updated with the action taken when it ends)"
rc=$(run k5 41 "$PR41" -- close --sitting tk-convC --subject tk-sub --outcome ruled --summary "plain outcome")
same "### Discussed${nl}Action taken: none; plain outcome." "$(lines_of tk-convC 3 | tail -n2)" "a topic the comment carries is checked again at close, and left out"
hasnt "rig-b" "$(cat "$TMPD/gh.k5.log")" "...so it never reaches gh again"

echo "# when the check cannot answer, the topic and the outcome are left out and the comment says where the visit stands"
cannot_answer() { # <tag> <what>
  printf '[]' >"$STATE"
  rc=$(run "$1-t" 41 "$PR41" -- topic --sitting tk-convX --subject tk-sub --topic "a plain topic")
  ok "$2: topic exits 0" "[ '$rc' = 0 ]"
  same "### Under discussion" "$(lines_of tk-convX 2 | tail -n1)" "$2: the comment says the visit is open, without the topic"
  has "could not answer" "$(cat "$TMPD/err.$1-t")" "$2: topic says why"
  plant tk-convX "### Under discussion: a plain topic"
  rc=$(run "$1" 41 "$PR41" -- close --sitting tk-convX --subject tk-sub --outcome rework --summary "plain outcome")
  ok "$2: close exits 0" "[ '$rc' = 0 ]"
  same "### Discussed${nl}Action taken: sent back for rework." "$(lines_of tk-convX 3 | tail -n2)" \
    "$2: the comment says the visit ended and the action taken, without the topic or the outcome"
  has "could not answer" "$(cat "$TMPD/err.$1")" "$2: close says why"
}
export RIG_LIST=fail;  cannot_answer x1 "the listing does not read"; unset RIG_LIST
export RIG_LIST=empty; cannot_answer x2 "the city lists no rigs";    unset RIG_LIST
export RIG_PREFIX=zz;  cannot_answer x3 "no rig holds the subject";  unset RIG_PREFIX
# A copy of the script with no check beside it, the way a broken pack would be.
NOCHECK="$TMPD/nocheck"; mkdir -p "$NOCHECK"
cp "$SUT" "$HERE/rig-map.sh" "$HERE/pr-post.sh" "$NOCHECK/"
printf '[]' >"$STATE"
GHLOG="$TMPD/gh.x4.log"; : >"$GHLOG"; : >"$GHLOG.argv"
( cd "$REPO" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" PR_NUMBER=41 PR_URL="$PR41" \
    bash "$NOCHECK/pr-sitting-comment.sh" topic --sitting tk-convY --subject tk-sub --topic "a plain topic" ) >"$TMPD/out.x4" 2>"$TMPD/err.x4"
rc=$?
ok "no check to run: topic exits 0" "[ '$rc' = 0 ]"
same "### Under discussion" "$(lines_of tk-convY 2 | tail -n1)" "no check to run: the topic is left out"
( cd "$REPO" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" PR_NUMBER=41 PR_URL="$PR41" \
    bash "$NOCHECK/pr-sitting-comment.sh" close --sitting tk-convY --subject tk-sub --outcome ruled --summary "plain outcome" ) >"$TMPD/out.x4" 2>"$TMPD/err.x4"
rc=$?
ok "no check to run: close exits 0" "[ '$rc' = 0 ]"
same "Action taken: none." "$(lines_of tk-convY 3 | tail -n1)" "no check to run: the outcome is left out"

echo "# the check adds no read of the slow listing, in either mode"
printf '[]' >"$STATE"
export RIG_LIST_LOG="$TMPD/rig-list.log"
: >"$RIG_LIST_LOG"
run l1 41 "$PR41" -- topic --sitting tk-convL --subject tk-sub --topic "a plain topic" >/dev/null
ok "topic reads the listing once, with the topic checked" "[ \$(wc -l <'$RIG_LIST_LOG') -eq 1 ]"
: >"$RIG_LIST_LOG"
run l2 41 "$PR41" -- close --sitting tk-convL --subject tk-sub --outcome ruled --summary "plain outcome" >/dev/null
ok "close reads the listing once, with the topic and the outcome checked" "[ \$(wc -l <'$RIG_LIST_LOG') -eq 1 ]"
same "### Discussed: a plain topic${nl}Action taken: none; plain outcome." "$(lines_of tk-convL 3 | tail -n2)" "...and the check did answer"
unset RIG_LIST_LOG

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all pr-sitting-comment assertions passed"; else echo "FAIL: pr-sitting-comment had failures"; fi
exit "$FAIL"
