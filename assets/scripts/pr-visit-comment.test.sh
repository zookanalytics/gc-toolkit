#!/usr/bin/env bash
# pr-visit-comment.test.sh — hermetic coverage of the visit→PR comment
# primitive. Self-locates the script under test, stubs gc and gh (the gh stub
# keeps a stateful comment store so upsert and update-only are provable), works
# in its own git repo with a fabricated origin, and exits nonzero on any failed
# assertion.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/pr-visit-comment.sh"
[ -x "$SUT" ] || { echo "not found or not executable: $SUT" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required for this test" >&2; exit 2; }

FAIL=0
ok()   { if eval "$2"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAIL=1; fi; }
has()   { case "$2" in *"$1"*) printf 'ok   - %s\n' "$3" ;; *) printf 'FAIL - %s\n     wanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'FAIL - %s\n     unwanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; *) printf 'ok   - %s\n' "$3" ;; esac; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/pr-visit-comment.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; mkdir -p "$BIN"

# A git repo whose origin fabricates our owned repository.
REPO="$TMPD/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" remote add origin https://github.com/acme/widgets.git

# gc stub: `gc bd show <id> --json` and `gc rig list --json`. A tk-vis* id is the
# visit — its status (does close refuse while the visit is open?) and the
# close-payload stash converse-signoff.sh writes (does close derive
# summary/actions/outcome?) come from $VISIT_STATUS / $VIS_OUTCOME / $VIS_SUMMARY
# / $VIS_ACTIONS. Any other id is the subject, whose PR binding ($PR_NUMBER /
# $PR_URL) is what a comment lands on. `rig list` answers a single fixture rig
# only when $RIG_PATH is planted (mapping $RIG_PREFIX to that path); empty
# otherwise, so the subject-rig lookup finds nothing and the helper falls back to
# the cwd origin — the path the git-repo-cwd cases below exercise.
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
  [ -n "${RIG_PATH:-}" ] || { printf '{"rigs":[]}\n'; exit 0; }
  jq -nc --arg p "${RIG_PREFIX:-tk}" --arg path "$RIG_PATH" '{rigs:[{name:"fixture",prefix:$p,path:$path}]}'
  exit 0
fi
[ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ] || exit 0
id="${3:-}"
case "$id" in
  tk-vis*)
    jq -nc --arg i "$id" --arg s "${VISIT_STATUS:-closed}" --arg o "${VIS_OUTCOME:-}" --arg sum "${VIS_SUMMARY:-}" --arg act "${VIS_ACTIONS:-}" \
      '[{id:$i, status:$s, metadata:(
          {} + (if $o=="" then {} else {"gc.outcome":$o} end)
             + (if $sum=="" then {} else {"gc.pr_visit_summary":$sum} end)
             + (if $act=="" then {} else {"gc.pr_visit_actions":$act} end) )}]' ;;
  *)
    jq -nc --arg n "${PR_NUMBER:-}" --arg u "${PR_URL:-}" \
      '[{id:"tk-sub", metadata:( ({} + (if $n=="" then {} else {pr_number:$n} end)) + (if $u=="" then {} else {pr_url:$u} end) )}]' ;;
esac
STUB
chmod +x "$BIN/gc"

# gh stub: a JSON array in $STATE is the PR's issue-comment thread.
#   pr comment  -> append {id, body}                 (create)
#   api GET .../issues/<n>/comments  -> print $STATE  (list)
#   api PATCH .../issues/comments/<id> -f body=..     -> replace that body (edit)
# Every call is logged to $GHLOG.
cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
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
rc=$(run c1 41 "https://github.com/acme/widgets/pull/41" -- engage --visit tk-vis1 --subject tk-sub --reason "why we are talking")
ok "engage exits 0" "[ '$rc' = 0 ]"
GH1="$(cat "$TMPD/gh.c1.log")"
has "pr comment 41" "$GH1" "engage posts a new comment on PR 41"
has "--repo github.com/acme/widgets" "$GH1" "the post is pinned to origin"
BODY1="$(jq -r '.[0].body' "$STATE")"
has "<!-- gc:visit:tk-vis1 -->" "$BODY1" "the comment carries the visit marker"
has "Visit tk-vis1 — open" "$BODY1" "the comment says the visit is open"
has "Reason: why we are talking" "$BODY1" "the reason is shown"

echo "# engage again is an upsert, not a duplicate"
rc=$(run c2 41 "https://github.com/acme/widgets/pull/41" -- engage --visit tk-vis1 --subject tk-sub --reason "why we are talking")
ok "second engage exits 0" "[ '$rc' = 0 ]"
GH2="$(cat "$TMPD/gh.c2.log")"
has "api" "$GH2" "the second engage edits via gh api"
has "PATCH" "$GH2" "the edit is a PATCH"
hasnt "pr comment" "$GH2" "the second engage does not post a second comment"
ok "still exactly one comment on the thread" "[ \$(jq 'length' '$STATE') -eq 1 ]"

echo "# close edits the same comment, preserves the reason, adds the summary"
rc=$(run c3 41 "https://github.com/acme/widgets/pull/41" -- close --visit tk-vis1 --subject tk-sub --outcome settled --summary "agreed to ship it" --actions "routed tk-work1")
ok "close exits 0" "[ '$rc' = 0 ]"
GH3="$(cat "$TMPD/gh.c3.log")"
has "PATCH" "$GH3" "close edits the comment in place"
hasnt "pr comment" "$GH3" "close never posts a new comment"
BODY3="$(jq -r '.[0].body' "$STATE")"
has "Visit tk-vis1 — closed (settled)" "$BODY3" "the comment now says closed with the outcome"
has "Reason: why we are talking" "$BODY3" "the original reason is preserved on close"
has "Summary: agreed to ship it" "$BODY3" "the summary is added"
has "Actions Taken: routed tk-work1" "$BODY3" "the actions are added"
ok "still exactly one comment after close" "[ \$(jq 'length' '$STATE') -eq 1 ]"

echo "# close with no prior comment is a silent no-op (visit never engaged)"
printf '[]' >"$STATE"
rc=$(run c4 41 "https://github.com/acme/widgets/pull/41" -- close --visit tk-vis2 --subject tk-sub --outcome moot --summary "premise died")
ok "close-without-comment exits 0" "[ '$rc' = 0 ]"
GH4="$(cat "$TMPD/gh.c4.log")"
hasnt "pr comment" "$GH4" "no comment is created on a close with no prior open"
hasnt "PATCH" "$GH4" "nothing is edited on a close with no prior open"
ok "the thread stays empty" "[ \$(jq 'length' '$STATE') -eq 0 ]"

echo "# a subject with no PR does nothing"
printf '[]' >"$STATE"
rc=$(run c5 "" "" -- engage --visit tk-vis3 --subject tk-sub --reason "no pr here")
ok "no-PR engage exits 0" "[ '$rc' = 0 ]"
GH5="$(cat "$TMPD/gh.c5.log")"
ok "no gh call was made for a PR-less subject" "[ ! -s '$TMPD/gh.c5.log' ]"

echo "# a PR that lives outside our origin is refused"
printf '[]' >"$STATE"
rc=$(run c6 7 "https://github.com/someone-else/theirs/pull/7" -- engage --visit tk-vis4 --subject tk-sub --reason "not ours")
ok "not-ours engage exits 0 (fail-safe)" "[ '$rc' = 0 ]"
ok "nothing was posted for a foreign PR" "[ ! -s '$TMPD/gh.c6.log' ]"
has "not ours" "$(cat "$TMPD/err.c6")" "it says why it refused"

echo "# the marker keys per visit — one id being a prefix of another does not collide"
printf '[]' >"$STATE"
run p1 41 "https://github.com/acme/widgets/pull/41" -- engage --visit tk-vis1  --subject tk-sub --reason "first"
run p2 41 "https://github.com/acme/widgets/pull/41" -- engage --visit tk-vis10 --subject tk-sub --reason "tenth"
ok "two visit comments coexist on the thread" "[ \$(jq 'length' '$STATE') -eq 2 ]"
run p3 41 "https://github.com/acme/widgets/pull/41" -- close --visit tk-vis1 --subject tk-sub --outcome settled --summary "done"
CLOSED_N="$(jq '[.[] | select((.body|contains("— closed")))] | length' "$STATE")"
ok "closing tk-vis1 closes exactly one comment" "[ \"$CLOSED_N\" -eq 1 ]"
has "Visit tk-vis1 — closed" "$(jq -r '.[] | select(.body|contains("— closed")) | .body' "$STATE")" "the closed comment is tk-vis1's own"
TEN_OPEN="$(jq '[.[] | select((.body|contains("Visit tk-vis10 — open")))] | length' "$STATE")"
ok "tk-vis10 stays open — its marker did not match the tk-vis1 close" "[ \"$TEN_OPEN\" -eq 1 ]"

echo "# close with no payload args derives the outcome, summary and actions from the visit's stamps"
printf '[]' >"$STATE"
run d0 41 "https://github.com/acme/widgets/pull/41" -- engage --visit tk-visD --subject tk-sub --reason "let us talk"
export VISIT_STATUS=closed VIS_OUTCOME=settled VIS_SUMMARY="agreed to ship it" VIS_ACTIONS="routed tk-w1"
rc=$(run d1 41 "https://github.com/acme/widgets/pull/41" -- close --visit tk-visD --subject tk-sub)
unset VISIT_STATUS VIS_OUTCOME VIS_SUMMARY VIS_ACTIONS
ok "payload-less close exits 0" "[ '$rc' = 0 ]"
BODYD="$(jq -r '.[] | select(.body|contains("tk-visD")) | .body' "$STATE")"
has "Visit tk-visD — closed (settled)" "$BODYD" "the outcome word comes from the visit's gc.outcome"
has "Summary: agreed to ship it" "$BODYD" "the summary comes from gc.pr_visit_summary"
has "Actions Taken: routed tk-w1" "$BODYD" "the actions come from gc.pr_visit_actions"

echo "# close refuses to mark the reminder closed while the visit is still open"
printf '[]' >"$STATE"
run o0 41 "https://github.com/acme/widgets/pull/41" -- engage --visit tk-visO --subject tk-sub --reason "mid conversation"
export VISIT_STATUS=open
rc=$(run o1 41 "https://github.com/acme/widgets/pull/41" -- close --visit tk-visO --subject tk-sub --outcome settled --summary "done")
unset VISIT_STATUS
ok "open-visit close exits 0 (fail-safe)" "[ '$rc' = 0 ]"
GHO="$(cat "$TMPD/gh.o1.log")"
hasnt "PATCH" "$GHO" "no edit is made while the visit is open"
BODYO="$(jq -r '.[] | select(.body|contains("tk-visO")) | .body' "$STATE")"
has "Visit tk-visO — open" "$BODYO" "the reminder stays in its open shape"
hasnt "closed" "$BODYO" "nothing says the visit closed ahead of its close"

echo "# engage from a NON-git cwd resolves origin off the subject's rig (board-launched engage/dismiss)"
# The board runs engage/dismiss from the city root, outside any rig checkout.
# Prove the real helper — not a recorder stub — still posts there, resolving the
# origin from the subject's rig ($RIG_PATH) rather than the git-less cwd.
printf '[]' >"$STATE"
NONGIT="$TMPD/nongit"; mkdir -p "$NONGIT"   # deliberately not a git repo
GHLOG="$TMPD/gh.rig.log"; : >"$GHLOG"; : >"$GHLOG.argv"
( cd "$NONGIT" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" \
    PR_NUMBER=55 PR_URL="https://github.com/acme/widgets/pull/55" RIG_PATH="$REPO" RIG_PREFIX=tk \
    bash "$SUT" engage --visit tk-visR --subject tk-sub --reason "from the board" ) >"$TMPD/out.rig" 2>"$TMPD/err.rig"
rc=$?
ok "non-git-cwd engage exits 0" "[ '$rc' = 0 ]"
GHR="$(cat "$GHLOG")"
has "pr comment 55" "$GHR" "the reminder posts even though cwd is not a git repo"
has "--repo github.com/acme/widgets" "$GHR" "the post is pinned to the subject's rig origin"
BODYR="$(jq -r '.[] | select(.body|contains("tk-visR")) | .body' "$STATE")"
has "Visit tk-visR — open" "$BODYR" "the comment lands in its open shape"

echo "# non-git cwd with no rig match self-silences — no crash, nothing posted"
printf '[]' >"$STATE"
GHLOG="$TMPD/gh.norig.log"; : >"$GHLOG"; : >"$GHLOG.argv"
( cd "$NONGIT" && PATH="$BIN:$PATH" STATE="$STATE" GHLOG="$GHLOG" \
    PR_NUMBER=55 PR_URL="https://github.com/acme/widgets/pull/55" \
    bash "$SUT" engage --visit tk-visN --subject tk-sub --reason "no rig, no git" ) >"$TMPD/out.norig" 2>"$TMPD/err.norig"
rc=$?
ok "no-rig non-git engage exits 0 (fail-safe)" "[ '$rc' = 0 ]"
ok "nothing posted when neither rig nor cwd resolves an origin" "[ ! -s '$TMPD/gh.norig.log' ]"
has "cannot resolve the subject's rig origin" "$(cat "$TMPD/err.norig")" "it says why it could not post"

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all pr-visit-comment assertions passed"; else echo "FAIL: pr-visit-comment had failures"; fi
exit "$FAIL"
