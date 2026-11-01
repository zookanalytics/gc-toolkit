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

echo "# engage on a subject with a PR"
printf '[]' >"$STATE"
rc=$(run c1 41 "https://github.com/acme/widgets/pull/41" -- engage --sitting tk-conv1 --subject tk-sub)
ok "engage exits 0" "[ '$rc' = 0 ]"
GH1="$(cat "$TMPD/gh.c1.log")"
has "pr comment 41" "$GH1" "engage posts a new comment on PR 41"
has "--repo github.com/acme/widgets" "$GH1" "the post is pinned to origin"
BODY1="$(jq -r '.[0].body' "$STATE")"
has "<!-- gc:sitting:tk-conv1 -->" "$BODY1" "the comment carries the sitting marker"
has "<!-- gc:city -->" "$BODY1" "the comment carries the city's provenance mark (posted through pr-post.sh)"
has "Sitting on tk-conv1 — open" "$BODY1" "the comment says the sitting is open"
has "Subject: tk-sub" "$BODY1" "the comment names the subject"

echo "# engage again is an upsert, not a duplicate"
rc=$(run c2 41 "https://github.com/acme/widgets/pull/41" -- engage --sitting tk-conv1 --subject tk-sub)
ok "second engage exits 0" "[ '$rc' = 0 ]"
GH2="$(cat "$TMPD/gh.c2.log")"
has "api" "$GH2" "the second engage edits via gh api"
has "PATCH" "$GH2" "the edit is a PATCH"
hasnt "pr comment" "$GH2" "the second engage does not post a second comment"
ok "still exactly one comment on the thread" "[ \$(jq 'length' '$STATE') -eq 1 ]"

echo "# close edits the same comment and adds the summary"
rc=$(run c3 41 "https://github.com/acme/widgets/pull/41" -- close --sitting tk-conv1 --subject tk-sub --outcome settled --summary "agreed to ship it" --actions "routed tk-work1")
ok "close exits 0" "[ '$rc' = 0 ]"
GH3="$(cat "$TMPD/gh.c3.log")"
has "PATCH" "$GH3" "close edits the comment in place"
hasnt "pr comment" "$GH3" "close never posts a new comment"
BODY3="$(jq -r '.[0].body' "$STATE")"
has "Sitting on tk-conv1 — ended (settled)" "$BODY3" "the comment now says the sitting ended, with its outcome"
has "Summary: agreed to ship it" "$BODY3" "the summary is added"
has "Actions Taken: routed tk-work1" "$BODY3" "the actions are added"
has "<!-- gc:city -->" "$BODY3" "the edited comment keeps the city's provenance mark"
ok "still exactly one comment after close" "[ \$(jq 'length' '$STATE') -eq 1 ]"

echo "# close with no prior comment is a silent no-op (no sitting engaged)"
printf '[]' >"$STATE"
rc=$(run c4 41 "https://github.com/acme/widgets/pull/41" -- close --sitting tk-conv2 --subject tk-sub --outcome moot --summary "premise died")
ok "close-without-comment exits 0" "[ '$rc' = 0 ]"
GH4="$(cat "$TMPD/gh.c4.log")"
hasnt "pr comment" "$GH4" "no comment is created on a close with no prior open"
hasnt "PATCH" "$GH4" "nothing is edited on a close with no prior open"
ok "the thread stays empty" "[ \$(jq 'length' '$STATE') -eq 0 ]"

echo "# a subject with no PR does nothing"
printf '[]' >"$STATE"
rc=$(run c5 "" "" -- engage --sitting tk-conv3 --subject tk-sub)
ok "no-PR engage exits 0" "[ '$rc' = 0 ]"
ok "no gh call was made for a PR-less subject" "[ ! -s '$TMPD/gh.c5.log' ]"

echo "# a PR that lives outside our origin is refused"
printf '[]' >"$STATE"
rc=$(run c6 7 "https://github.com/someone-else/theirs/pull/7" -- engage --sitting tk-conv4 --subject tk-sub)
ok "not-ours engage exits 0 (fail-safe)" "[ '$rc' = 0 ]"
ok "nothing was posted for a foreign PR" "[ ! -s '$TMPD/gh.c6.log' ]"
has "not ours" "$(cat "$TMPD/err.c6")" "it says why it refused"

echo "# the marker keys per conversation — one id being a prefix of another does not collide"
printf '[]' >"$STATE"
run p1 41 "https://github.com/acme/widgets/pull/41" -- engage --sitting tk-conv1  --subject tk-sub
run p2 41 "https://github.com/acme/widgets/pull/41" -- engage --sitting tk-conv10 --subject tk-sub
ok "two sitting comments coexist on the thread" "[ \$(jq 'length' '$STATE') -eq 2 ]"
run p3 41 "https://github.com/acme/widgets/pull/41" -- close --sitting tk-conv1 --subject tk-sub --outcome settled --summary "done"
CLOSED_N="$(jq '[.[] | select((.body|contains("— ended")))] | length' "$STATE")"
ok "closing tk-conv1 ends exactly one comment" "[ \"$CLOSED_N\" -eq 1 ]"
has "Sitting on tk-conv1 — ended" "$(jq -r '.[] | select(.body|contains("— ended")) | .body' "$STATE")" "the ended comment is tk-conv1's own"
TEN_OPEN="$(jq '[.[] | select((.body|contains("Sitting on tk-conv10 — open")))] | length' "$STATE")"
ok "tk-conv10 stays open — its marker did not match the tk-conv1 close" "[ \"$TEN_OPEN\" -eq 1 ]"

echo "# engage from a NON-git cwd resolves origin off the subject's rig (board-launched engage and dismiss)"
# The board runs engage/dismiss from the city root, outside any rig checkout.
# Prove the real helper — not a recorder stub — still posts there, resolving the
# origin from the subject's rig ($RIG_PATH) rather than the git-less cwd.
printf '[]' >"$STATE"
NONGIT="$TMPD/nongit"; mkdir -p "$NONGIT"   # deliberately not a git repo
GHLOG="$TMPD/gh.rig.log"; : >"$GHLOG"; : >"$GHLOG.argv"
( cd "$NONGIT" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" \
    PR_NUMBER=55 PR_URL="https://github.com/acme/widgets/pull/55" RIG_PATH="$REPO" RIG_PREFIX=tk \
    bash "$SUT" engage --sitting tk-convR --subject tk-sub ) >"$TMPD/out.rig" 2>"$TMPD/err.rig"
rc=$?
ok "non-git-cwd engage exits 0" "[ '$rc' = 0 ]"
GHR="$(cat "$GHLOG")"
has "pr comment 55" "$GHR" "the reminder posts even though cwd is not a git repo"
has "--repo github.com/acme/widgets" "$GHR" "the post is pinned to the subject's rig origin"
BODYR="$(jq -r '.[] | select(.body|contains("tk-convR")) | .body' "$STATE")"
has "Sitting on tk-convR — open" "$BODYR" "the comment lands in its open shape"

echo "# non-git cwd with no rig match self-silences — no crash, nothing posted"
printf '[]' >"$STATE"
GHLOG="$TMPD/gh.norig.log"; : >"$GHLOG"; : >"$GHLOG.argv"
( cd "$NONGIT" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" RIG_LIST=empty \
    PR_NUMBER=55 PR_URL="https://github.com/acme/widgets/pull/55" \
    bash "$SUT" engage --sitting tk-convN --subject tk-sub ) >"$TMPD/out.norig" 2>"$TMPD/err.norig"
rc=$?
ok "no-rig non-git engage exits 0 (fail-safe)" "[ '$rc' = 0 ]"
ok "nothing posted when neither rig nor cwd resolves an origin" "[ ! -s '$TMPD/gh.norig.log' ]"
has "cannot resolve the subject's rig origin" "$(cat "$TMPD/err.norig")" "it says why it could not post"

PR41="https://github.com/acme/widgets/pull/41"
body_of() { jq -r --arg m "<!-- gc:sitting:$1 -->" '.[] | select(.body|contains($m)) | .body' "$STATE"; }
# A comment already on the thread: what an earlier post of this script left.
plant() { # <conversation> <reason line>
  jq -n --arg b "<!-- gc:sitting:$1 -->"$'\n'"### Sitting on $1 — open"$'\n'"- Subject: tk-sub"$'\n'"- Reason: $2"$'\n' \
    '[{id:100, body:$b}]' >"$STATE"
}

echo "# no reason reaches the post: a caller cannot hand one in"
printf '[]' >"$STATE"
rc=$(run r1 41 "$PR41" -- engage --sitting tk-convA --subject tk-sub --reason "a reason naming rig-b")
ok "engage refuses a reason as a usage error" "[ '$rc' = 2 ]"
ok "...and makes no gh call" "[ ! -s '$TMPD/gh.r1.log' ]"
ok "...so nothing is posted" "[ \$(jq 'length' '$STATE') -eq 0 ]"
rc=$(run r2 41 "$PR41" -- close --sitting tk-convA --subject tk-sub --reason "a reason naming rig-b")
ok "close refuses one too" "[ '$rc' = 2 ]"

echo "# no reason reaches the post: engage writes none, on a new comment or over an old one"
printf '[]' >"$STATE"
run r3 41 "$PR41" -- engage --sitting tk-convE --subject tk-sub >/dev/null
hasnt "Reason" "$(body_of tk-convE)" "a new open comment has no reason line"
plant tk-convF "a reason naming rig-b and rb-abc12"
run r4 41 "$PR41" -- engage --sitting tk-convF --subject tk-sub >/dev/null
BODYF="$(body_of tk-convF)"
has "Sitting on tk-convF — open" "$BODYF" "a refreshed comment stays open"
hasnt "Reason" "$BODYF" "...and loses the reason an earlier post left on it"
hasnt "rig-b" "$BODYF" "...so the rig it named is gone from the comment"

echo "# engage posts only its state, whatever else it is handed"
printf '[]' >"$STATE"
run r6 41 "$PR41" -- engage --sitting tk-convH --subject tk-sub --outcome "rig-b" --summary "a summary naming rig-b" --actions "routed rb-abc12" >/dev/null
has "Sitting on tk-convH — open" "$(body_of tk-convH)" "engage handed a close's fields still posts its open shape"
hasnt "rig-b" "$(cat "$TMPD/gh.r6.log")" "...and neither the outcome nor the summary reaches gh"
hasnt "rb-abc12" "$(cat "$TMPD/gh.r6.log")" "...nor the actions"

echo "# no reason reaches the post: close reads none back from the comment it edits"
for why in "a reason naming rig-b and rb-abc12" "an ordinary reason"; do
  plant tk-convG "$why"
  rc=$(run r5 41 "$PR41" -- close --sitting tk-convG --subject tk-sub --outcome settled --summary "agreed to ship it")
  ok "close over a comment carrying a reason exits 0" "[ '$rc' = 0 ]"
  BODYG="$(body_of tk-convG)"
  has "Sitting on tk-convG — ended (settled)" "$BODYG" "the comment says the sitting ended"
  has "Summary: agreed to ship it" "$BODYG" "...with the summary"
  hasnt "Reason" "$BODYG" "...and no reason line, whatever the old one said ($why)"
  hasnt "$why" "$(cat "$TMPD/gh.r5.log")" "...which never reaches gh ($why)"
done

echo "# a close publishes each field the check clears, and leaves out each it does not"
# The subject's own rig and ids, and the rigs the pack runs on or with, are not
# another rig, and a word that only resembles a prefix is not an id.
close_with() { # <tag> <flag> <text>
  printf '[]' >"$STATE"
  run "$1-e" 41 "$PR41" -- engage --sitting tk-convC --subject tk-sub >/dev/null
  run "$1" 41 "$PR41" -- close --sitting tk-convC --subject tk-sub --outcome settled --summary "plain summary" --actions "plain actions" "$2" "$3"
}
for clean in "routed tk-work1 in fixture" "shipped on gascity and gc-toolkit" "the rib cage held"; do
  rc=$(close_with k1 --summary "$clean")
  ok "a clean summary closes (exit 0): $clean" "[ '$rc' = 0 ]"
  has "Summary: $clean" "$(body_of tk-convC)" "it reaches the post: $clean"
done
for named in "the same defect on rig-b" "the same defect on Rig B" "see rb-abc12 for it" "see rb-abc12.3 for it" "under /nonexistent/rig-b/assets"; do
  rc=$(close_with k2 --summary "$named")
  ok "a summary naming another rig still closes (exit 0): $named" "[ '$rc' = 0 ]"
  BODYK="$(body_of tk-convC)"
  has "Sitting on tk-convC — ended (settled)" "$BODYK" "the comment says the sitting ended: $named"
  hasnt "Summary" "$BODYK" "the summary is left out: $named"
  has "Actions Taken: plain actions" "$BODYK" "the other field stays: $named"
  hasnt "$named" "$(cat "$TMPD/gh.k2.log")" "the text never reaches gh: $named"
  has "left the summary off the reminder on PR#41: it names another rig" "$(cat "$TMPD/err.k2")" "it says what it left out: $named"
done
hasnt "rig-b" "$(cat "$TMPD/err.k2")" "the message does not repeat the text it left out"
close_with k3 --actions "routed work to rb-abc12" >/dev/null
BODYK="$(body_of tk-convC)"
hasnt "Actions" "$BODYK" "actions naming another rig's bead are left out"
has "Summary: plain summary" "$BODYK" "...and the summary stays"
close_with k4 --outcome "rig-b" >/dev/null
BODYK="$(body_of tk-convC)"
has "Sitting on tk-convC — ended" "$BODYK" "an outcome naming another rig: the comment still says the sitting ended"
hasnt "rig-b" "$BODYK" "...with the word left out"
has "Summary: plain summary" "$BODYK" "...and the summary stays"
close_with k5 --summary "the same defect on Rig"$'\n'"B and elsewhere" >/dev/null
hasnt "Summary" "$(body_of tk-convC)" "the check reads the text as it would post, so a name split across lines is still a name"
close_with k6 --outcome "handed back" >/dev/null
has "Sitting on tk-convC — ended (handed back)" "$(body_of tk-convC)" "the sign-off's two-word outcome still reads"

echo "# when the check cannot answer, a close leaves the free text out and still says the sitting ended"
cannot_answer() { # <tag> <what>
  printf '[]' >"$STATE"
  run "$1-e" 41 "$PR41" -- engage --sitting tk-convX --subject tk-sub >/dev/null
  rc=$(run "$1" 41 "$PR41" -- close --sitting tk-convX --subject tk-sub --outcome settled --summary "plain summary" --actions "plain actions")
  ok "$2: close exits 0" "[ '$rc' = 0 ]"
  BODYX="$(body_of tk-convX)"
  has "Sitting on tk-convX — ended" "$BODYX" "$2: the comment says the sitting ended"
  hasnt "settled" "$BODYX" "$2: the outcome is left out"
  hasnt "Summary" "$BODYX" "$2: the summary is left out"
  hasnt "Actions" "$BODYX" "$2: the actions are left out"
  has "could not answer" "$(cat "$TMPD/err.$1")" "$2: it says why"
}
export RIG_LIST=fail;  cannot_answer x1 "the listing does not read"; unset RIG_LIST
export RIG_LIST=empty; cannot_answer x2 "the city lists no rigs";    unset RIG_LIST
export RIG_PREFIX=zz;  cannot_answer x3 "no rig holds the subject";  unset RIG_PREFIX
# A copy of the script with no check beside it, the way a broken pack would be.
NOCHECK="$TMPD/nocheck"; mkdir -p "$NOCHECK"
cp "$SUT" "$HERE/rig-map.sh" "$HERE/pr-post.sh" "$NOCHECK/"
printf '[]' >"$STATE"
run x4-e 41 "$PR41" -- engage --sitting tk-convY --subject tk-sub >/dev/null
GHLOG="$TMPD/gh.x4.log"; : >"$GHLOG"; : >"$GHLOG.argv"
( cd "$REPO" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" PR_NUMBER=41 PR_URL="$PR41" \
    bash "$NOCHECK/pr-sitting-comment.sh" close --sitting tk-convY --subject tk-sub --outcome settled --summary "plain summary" --actions "plain actions" ) >"$TMPD/out.x4" 2>"$TMPD/err.x4"
rc=$?
ok "no check to run: close exits 0" "[ '$rc' = 0 ]"
BODYY="$(body_of tk-convY)"
has "Sitting on tk-convY — ended" "$BODYY" "no check to run: the comment says the sitting ended"
hasnt "Summary" "$BODYY" "no check to run: the free text is left out"

echo "# the check adds no read of the slow listing, in either mode"
printf '[]' >"$STATE"
export RIG_LIST_LOG="$TMPD/rig-list.log"
: >"$RIG_LIST_LOG"
run l1 41 "$PR41" -- engage --sitting tk-convL --subject tk-sub >/dev/null
ok "engage reads the listing once" "[ \$(wc -l <'$RIG_LIST_LOG') -eq 1 ]"
: >"$RIG_LIST_LOG"
run l2 41 "$PR41" -- close --sitting tk-convL --subject tk-sub --outcome settled --summary "plain summary" --actions "plain actions" >/dev/null
ok "close reads the listing once, with three fields checked" "[ \$(wc -l <'$RIG_LIST_LOG') -eq 1 ]"
has "Summary: plain summary" "$(body_of tk-convL)" "...and the check did answer"
unset RIG_LIST_LOG

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all pr-sitting-comment assertions passed"; else echo "FAIL: pr-sitting-comment had failures"; fi
exit "$FAIL"
