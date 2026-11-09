#!/usr/bin/env bash
# pr-sitting-comment.test.sh — hermetic coverage of the comment that shows a
# visit on its subject's PR, a view of the conversation's own bead. Self-locates
# the script under test, stubs gc (the conversation, its comments and the
# subject) and gh (a stateful comment thread, so a post, an edit and an
# untouched PR are provable), works in its own git repo with a fabricated
# origin, and exits nonzero on any failed assertion.
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
BIN="$TMPD/bin"; FIX="$TMPD/fix"; mkdir -p "$BIN" "$FIX"

# A git repo whose origin fabricates our owned repository, and one with none.
REPO="$TMPD/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" remote add origin https://github.com/acme/widgets.git
BARE="$TMPD/bare"; mkdir -p "$BARE"

# gc stub. `bd list --id <conv> --all --json` answers the conversation's row
# from $FIX/conv.json, `bd comments <conv> --json` its comments from
# $FIX/comments.json, and `bd show <subject> --json` the subject with the PR
# binding $PR_NUMBER / $PR_URL. CONV_READ=fail and COMMENTS_READ=fail make those
# reads answer nothing. Every call is logged, so a rig lookup would show.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
printf '%s\n' "$*" >>"${GCLOG:?}"
case "${1:-} ${2:-}" in
  "bd list")
    [ "${CONV_READ:-}" = fail ] && exit 1
    printf 'gc bd: answering from the rig "fixture" store\n'
    jq -c '[.]' "$FIX/conv.json" ;;
  "bd comments")
    [ "${COMMENTS_READ:-}" = fail ] && { printf '{"error":"the store did not answer"}\n'; exit 1; }
    cat "$FIX/comments.json" ;;
  "bd show")
    jq -nc --arg id "${3:-}" --arg n "${PR_NUMBER:-}" --arg u "${PR_URL:-}" \
      '[{id:$id, metadata:( ({} + (if $n=="" then {} else {pr_number:$n} end)) + (if $u=="" then {} else {pr_url:$u} end) )}]' ;;
esac
exit 0
STUB
chmod +x "$BIN/gc"

# gh stub: a JSON array in $STATE is the PR's issue-comment thread.
#   pr comment  -> append {id, body}                 (create)
#   api GET .../issues/<n>/comments  -> print $STATE  (list); GH_READ=fail fails it
#   api PATCH .../issues/comments/<id> -f body=..     -> replace that body (edit)
# Every call is logged to $GHLOG.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gh" <<'STUB'
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
      [ "${GH_READ:-}" = fail ] && exit 1
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
PR41="https://github.com/acme/widgets/pull/41"
OPENER="Why does the retry loop spin? I typed this to open the visit"
nl=$'\n'

# conv <status> <title> [hand-back] — the conversation tk-conv, a task that
# tracks tk-sub, held by its sitting's alias, opened with $OPENER as its ask.
conv() {
  jq -n --arg s "$1" --arg t "$2" --arg h "${3:-}" --arg d "$OPENER" '{
      id: "tk-conv", issue_type: "task", status: $s, title: $t, description: $d,
      assignee: "fixture/gc-toolkit.tk-conv",
      close_reason: (if $s == "closed" then "dismissed by the operator: an operator typed this reason" else null end),
      dependencies: [{issue_id: "tk-conv", depends_on_id: "tk-sub", type: "tracks"}],
      metadata: (if $h == "" then {} else {"gc.handback": $h} end)}' >"$FIX/conv.json"
}
# acts <text>... — the conversation's comments, one per argument, in order.
acts() {
  local i=0 t out='[]'
  for t in "$@"; do
    i=$((i + 1))
    out=$(printf '%s' "$out" | jq -c --arg t "$t" --arg at "2026-11-05T10:00:0${i}Z" --arg id "c$i" \
      '. + [{id: $id, issue_id: "tk-conv", author: "Zook Bot", text: $t, created_at: $at}]')
  done
  printf '%s\n' "$out" >"$FIX/comments.json"
}
run() { # <tag> [--in <dir>] [NAME=VALUE...] -- <sut args...>
  local tag="$1" dir="$REPO"; shift
  [ "${1:-}" = "--in" ] && { dir="$2"; shift 2; }
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  GHLOG="$TMPD/gh.$tag.log"; : >"$GHLOG"; GCLOG="$TMPD/gc.$tag.log"; : >"$GCLOG"
  ( cd "$dir" && env PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" GCLOG="$GCLOG" FIX="$FIX" \
      PR_NUMBER="${PR_NUMBER-41}" PR_URL="${PR_URL-$PR41}" ${envs[@]+"${envs[@]}"} bash "$SUT" "$@" ) \
    >"$TMPD/out.$tag" 2>"$TMPD/err.$tag"
  echo $?
}
body_of() { jq -r --arg m "<!-- gc:sitting:$1 -->" '.[] | select(.body|contains($m)) | .body' "$STATE"; }
# The lines this script composes, without the mark pr-post.sh adds below them.
# A command substitution drops the blank lines it leaves at the end.
drawn() { body_of tk-conv | grep -vx '<!-- gc:city -->'; }
OPEN_LINES="<!-- gc:sitting:tk-conv -->$nl### Visit tk-conv on tk-sub${nl}Topic: how the retry should work"

echo "# post puts the open comment up, showing the conversation's title"
printf '[]' >"$STATE"; conv in_progress "how the retry should work"; acts
rc=$(run p1 -- post --sitting tk-conv)
ok "post exits 0" "[ '$rc' = 0 ]"
GH1="$(cat "$TMPD/gh.p1.log")"
has "pr comment 41" "$GH1" "post puts a new comment on PR 41"
has "--repo github.com/acme/widgets" "$GH1" "…pinned to the origin of the checkout it runs in"
same "$OPEN_LINES" "$(drawn)" "the comment names the visit, the bead it is on and the topic, the conversation's title word for word"
has "<!-- gc:city -->" "$(body_of tk-conv)" "the comment carries the city's provenance mark (posted through pr-post.sh)"
hasnt "rig list" "$(cat "$TMPD/gc.p1.log")" "…and nothing looks up the city's rigs"

echo "# a new topic redraws the same comment, and the same one changes nothing"
printf '[]' >"$STATE"; conv in_progress "how the retry should work"
run p3a -- post --sitting tk-conv >/dev/null
conv in_progress "whether to retire it"
rc=$(run p3 -- post --sitting tk-conv)
ok "a second topic exits 0" "[ '$rc' = 0 ]"
has "PATCH" "$(cat "$TMPD/gh.p3.log")" "the new topic edits the comment"
hasnt "pr comment" "$(cat "$TMPD/gh.p3.log")" "…and posts no second comment"
ok "still exactly one comment on the thread" "[ \$(jq 'length' '$STATE') -eq 1 ]"
has "Topic: whether to retire it" "$(body_of tk-conv)" "the comment shows the new title"
rc=$(run p4 -- post --sitting tk-conv)
hasnt "PATCH" "$(cat "$TMPD/gh.p4.log")" "the same topic again edits nothing"
has "already shows its bead" "$(cat "$TMPD/out.p4")" "…and says the comment already shows it"

echo "# refresh on an open conversation keeps the open lines, whatever the bead holds for later"
printf '[]' >"$STATE"; conv in_progress "how the retry should work"
run r0 -- post --sitting tk-conv >/dev/null
conv in_progress "how the retry should work" "an earlier framing's hand-back"; acts "Sent work: a retry with a cap."
rc=$(run r1 -- refresh --sitting tk-conv)
ok "refresh exits 0" "[ '$rc' = 0 ]"
same "$OPEN_LINES" "$(drawn)" "an open visit shows no conclusion and no actions"
hasnt "bd comments" "$(cat "$TMPD/gc.r1.log")" "…and reads no actions it would not show"

echo "# once the conversation closes, the open lines stay and the conclusion and actions follow"
HANDBACK="tk-sub — the retry loop${nl}${nl}The retry now stops after five tries.${nl}  It is back with a builder."
conv closed "how the retry should work" "$HANDBACK"
acts "Ruled: cap the retry at five tries" "Sent PR #41 back for rework."
rc=$(run r2 -- refresh --sitting tk-conv)
ok "refresh exits 0" "[ '$rc' = 0 ]"
has "PATCH" "$(cat "$TMPD/gh.r2.log")" "refresh edits the comment in place"
ENDED="$OPEN_LINES$nl${nl}Conclusion:$nl> tk-sub — the retry loop$nl>$nl> The retry now stops after five tries.$nl>   It is back with a builder.$nl${nl}Actions:$nl- Ruled: cap the retry at five tries$nl- Sent PR #41 back for rework."
same "$ENDED" "$(drawn)" "the conclusion is the hand-back and the actions are the comments, each word for word"
case "$(drawn)" in
  "$OPEN_LINES$nl"*) printf 'ok   - %s\n' "the ended comment begins with the open comment's lines, unchanged" ;;
  *) printf 'FAIL - %s\n' "the ended comment begins with the open comment's lines, unchanged"; FAIL=1 ;;
esac
ok "still exactly one comment on the thread" "[ \$(jq 'length' '$STATE') -eq 1 ]"

echo "# nothing typed to open the visit or to dismiss it reaches the comment"
hasnt "$OPENER" "$(body_of tk-conv)" "the words the visit opened with stay on the bead as its description"
hasnt "an operator typed this reason" "$(body_of tk-conv)" "…and a dismiss's reason, which is in the close reason, is not shown"
acts "Dismissed by the operator."
conv closed "how the retry should work" "$HANDBACK"
run r3 -- refresh --sitting tk-conv >/dev/null
has "- Dismissed by the operator." "$(drawn)" "a dismissed visit lists the dismissal its writer recorded"
hasnt "an operator typed this reason" "$(body_of tk-conv)" "…without the reason typed beside it"

echo "# the actions keep the bead's order and its line breaks"
acts "Sent work: a cap on the retry,${nl}checked by the suite." "Ruled: the cap stays at five"
jq '.[0].created_at = "2026-11-05T10:00:09Z"' "$FIX/comments.json" >"$FIX/c.t" && mv "$FIX/c.t" "$FIX/comments.json"
run r4 -- refresh --sitting tk-conv >/dev/null
has "Actions:$nl- Ruled: the cap stays at five$nl- Sent work: a cap on the retry,$nl  checked by the suite." "$(drawn)" \
  "actions list oldest first, and a comment's second line stays inside its item"

echo "# an ended visit with nothing recorded says so"
conv closed "how the retry should work"; acts
run r5 -- refresh --sitting tk-conv >/dev/null
same "$OPEN_LINES$nl${nl}Conclusion: none recorded$nl${nl}Actions: none" "$(drawn)" "no hand-back reads none recorded, and no comments read none"

echo "# a topic is shown as the bead holds it, a rig's name included"
printf '[]' >"$STATE"; conv in_progress "the same defect on rig-b"
run t1 -- post --sitting tk-conv >/dev/null
has "Topic: the same defect on rig-b" "$(body_of tk-conv)" "no filter stands between the bead and the comment"

echo "# a visit that never named its topic has no comment, and its close posts nothing"
printf '[]' >"$STATE"; conv closed "$OPENER" "the sign-off"; acts "Ruled: nothing changes"
rc=$(run n1 -- refresh --sitting tk-conv)
ok "refresh exits 0" "[ '$rc' = 0 ]"
ok "nothing is posted" "[ \$(jq 'length' '$STATE') -eq 0 ]"
hasnt "pr comment" "$(cat "$TMPD/gh.n1.log")" "…and no comment is created"

echo "# a comment in an earlier shape is redrawn from the bead"
jq -n --arg b "<!-- gc:sitting:tk-conv -->$nl### Sitting on tk-conv — open$nl- Subject: tk-sub$nl" '[{id:100, body:$b}]' >"$STATE"
conv closed "how the retry should work" "$HANDBACK"; acts "Ruled: cap the retry at five tries"
run o1 -- refresh --sitting tk-conv >/dev/null
hasnt "Sitting on" "$(body_of tk-conv)" "the earlier shape is gone"
has "$OPEN_LINES" "$(body_of tk-conv)" "…and the comment shows the bead"

echo "# what the comment cannot read leaves the PR as it is"
printf '[]' >"$STATE"; conv in_progress "how the retry should work"
run b0 -- post --sitting tk-conv >/dev/null
BEFORE="$(body_of tk-conv)"
conv closed "how the retry should work" "$HANDBACK"; acts "Ruled: cap the retry at five tries"
rc=$(run b1 COMMENTS_READ=fail -- refresh --sitting tk-conv)
ok "unreadable actions exit 0" "[ '$rc' = 0 ]"
same "$BEFORE" "$(body_of tk-conv)" "…and leave the comment as it was"
has "could not read the comments" "$(cat "$TMPD/err.b1")" "…saying why"
rc=$(run b2 CONV_READ=fail -- refresh --sitting tk-conv)
ok "an unreadable conversation exits 0" "[ '$rc' = 0 ]"
same "$BEFORE" "$(body_of tk-conv)" "…and changes nothing"
rc=$(run b3 GH_READ=fail -- refresh --sitting tk-conv)
ok "an unreadable thread exits 0" "[ '$rc' = 0 ]"
hasnt "PATCH" "$(cat "$TMPD/gh.b3.log")" "…and edits nothing"
printf '[]' >"$STATE"; conv in_progress "how the retry should work"
rc=$(run b4 GH_READ=fail -- post --sitting tk-conv)
hasnt "pr comment" "$(cat "$TMPD/gh.b4.log")" "post skips an unreadable thread rather than risk a second comment"

echo "# a bead that is not a conversation is not drawn"
jq '.dependencies = []' "$FIX/conv.json" >"$FIX/c.t" && mv "$FIX/c.t" "$FIX/conv.json"
rc=$(run x1 -- post --sitting tk-conv)
ok "it exits 0" "[ '$rc' = 0 ]"
ok "…and nothing is posted" "[ \$(jq 'length' '$STATE') -eq 0 ]"

echo "# the PR is ours to comment on only where the subject and the checkout agree"
conv in_progress "how the retry should work"
rc=$(PR_NUMBER="" PR_URL="" run s1 -- post --sitting tk-conv)
ok "a subject with no PR exits 0" "[ '$rc' = 0 ]"
ok "…and makes no gh call" "[ ! -s '$TMPD/gh.s1.log' ]"
rc=$(PR_URL="https://github.com/other/thing/pull/41" run s2 -- post --sitting tk-conv)
ok "a PR in another repository exits 0" "[ '$rc' = 0 ]"
hasnt "pr comment" "$(cat "$TMPD/gh.s2.log")" "…and posts nothing there"
rc=$(PR_URL="" run s3 -- post --sitting tk-conv)
has "pr comment 41" "$(cat "$TMPD/gh.s3.log")" "a bare pr_number posts on the checkout's origin"
printf '[]' >"$STATE"
rc=$(run s4 --in "$BARE" -- post --sitting tk-conv)
ok "a checkout with no GitHub origin exits 0" "[ '$rc' = 0 ]"
ok "…and makes no gh call" "[ ! -s '$TMPD/gh.s4.log' ]"

echo "# usage"
for args in "" "close --sitting tk-conv" "post" "refresh --sitting tk-conv --topic x" \
    "post --sitting tk-conv --topic x" "post --sitting tk-conv --subject tk-sub" "refresh tk-conv"; do
  rc=$(run u1 -- $args)
  ok "'$args' is a usage error (exit 2)" "[ '$rc' = 2 ]"
done
rc=$(run u2 -- refresh --help)
ok "--help exits 0" "[ '$rc' = 0 ]"
has "post --sitting <task>" "$(cat "$TMPD/out.u2")" "…and prints the usage"

echo
[ "$FAIL" -eq 0 ] && echo "pr-sitting-comment: all passed" || echo "pr-sitting-comment: FAILURES"
exit "$FAIL"
