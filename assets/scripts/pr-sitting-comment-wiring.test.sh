#!/usr/bin/env bash
# pr-sitting-comment-wiring.test.sh — proves the sign-off's PR-reminder update
# reaches the real pr-sitting-comment.sh with arguments it takes, end to end. A
# sitting's engage posts the reminder in its open shape; converse-signoff.sh,
# once the conversation reads closed, edits it to say the sitting ended with its
# summary and actions, and once a cut-short conversation reads back in the
# operator's queue, edits it to say it was handed back. The engage and dismiss
# call sites are covered by gc-helm-engage.test.sh and gc-helm-dismiss.test.sh,
# which own those harnesses.
#
# Hermetic: stubs gc, gh and the sign-off's other pack scripts; the candidate
# root carries the real pr-sitting-comment.sh, pr-post.sh and rig-mentions.sh, so
# what the sign-off hands the reminder meets the real check. No city, no network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNOFF="$HERE/converse-signoff.sh"
REMINDER="$HERE/pr-sitting-comment.sh"
for f in "$SIGNOFF" "$REMINDER" "$HERE/pr-post.sh"; do [ -r "$f" ] || { echo "not found: $f" >&2; exit 2; }; done
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 2; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n       %s\n' "$1" "${2:-}"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3' in: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "found '$3' in: $2" ;; *) ok "$1" ;; esac; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/pr-sitting-comment-wiring.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; mkdir -p "$BIN" "$TMPD/store/b" "$TMPD/cwd"

# The subject's rig: a git repo whose origin is the owned repository.
REPO="$TMPD/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" remote add origin https://github.com/acme/widgets.git

# The candidate root the sign-off searches first: the real reminder, the poster
# and the rig-mention check it calls, and stubs for the headline writer and
# lifecycle.sh.
SR="$TMPD/rig/assets/scripts"; mkdir -p "$SR"
for f in pr-sitting-comment.sh pr-post.sh rig-map.sh rig-mentions.sh bd-lib.sh; do ln -s "$HERE/$f" "$SR/$f"; done
cat > "$SR/gc-helm.sh" <<'H'
#!/usr/bin/env bash
[ "$1" = takeaway ] && gc bd update "$2" --set-metadata "gc.takeaway=$3" >/dev/null
exit 0
H
cat > "$SR/lifecycle.sh" <<'L'
#!/usr/bin/env bash
[ "$1" = state ] && echo unanchored
exit 0
L
chmod +x "$SR/gc-helm.sh" "$SR/lifecycle.sh"

# gc stub: one JSON file per bead under $STORE/b, its edges as deps [{type, on}].
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'GC'
B="$STORE/b"
row() { cat "$B/$1.json" 2>/dev/null; }
put() { cat > "$B/$1.json.tmp" && mv "$B/$1.json.tmp" "$B/$1.json"; }
case "$1 ${2:-}" in
  "rig list") jq -n --arg p "$REPO" '{rigs:[{name:"gc-toolkit", prefix:"tk", path:$p}, {name:"rig-b", prefix:"rb", path:"/nonexistent/rig-b"}]}' ;;
  "bd show")
    [ -f "$B/$3.json" ] || { printf '{"error":"no issues found"}\n'; exit 1; }
    row "$3" | jq -c '[. + {dependencies: [ .deps[] | {id: .on, dependency_type: .type} ]} | del(.deps)]' ;;
  "bd list")
    _id=""; _p=""; for a in "$@"; do [ "$_p" = "--id" ] && _id="$a"; _p="$a"; done
    row "$_id" | jq -c '[. + {dependencies: [ .deps[] as $d | {issue_id: .id, depends_on_id: $d.on, type: $d.type} ]} | del(.deps)]' ;;
  "bd dep") printf '[]\n' ;;
  "bd gate")
    _r=""; _p=""; for a in "$@"; do [ "$_p" = "--reason" ] && _r="$a"; _p="$a"; done
    row "$4" | jq --arg r "$_r" '.status = "closed" | .close_reason = $r' | put "$4" ;;
  "bd close")
    _r=""; _p=""; for a in "$@"; do [ "$_p" = "--reason" ] && _r="$a"; _p="$a"; done
    row "$3" | jq --arg r "$_r" '.status = "closed" | .close_reason = $r' | put "$3" ;;
  "bd update")
    _id="$3"; shift 3; _r=$(row "$_id")
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) _r=$(printf '%s' "$_r" | jq --arg k "${2%%=*}" --arg v "${2#*=}" '.metadata[$k] = $v'); shift 2 ;;
        --assignee)     _r=$(printf '%s' "$_r" | jq --arg v "$2" '.assignee = $v'); shift 2 ;;
        --status)       _r=$(printf '%s' "$_r" | jq --arg v "$2" '.status = $v'); shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s' "$_r" | put "$_id" ;;
esac
exit 0
GC
chmod +x "$BIN/gc"

# gh stub: a JSON array in $STATE is the PR's issue-comment thread.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gh" <<'GH'
STATE="${STATE:?}"
[ -s "$STATE" ] || printf '[]' >"$STATE"
verb="${1:-}"; shift || true
case "$verb" in
  pr)
    [ "${1:-}" = "comment" ] || exit 0
    body=""; while [ $# -gt 0 ]; do case "$1" in --body) shift; body="$1" ;; esac; shift; done
    id=$(( $(jq 'length' "$STATE") + 100 ))
    jq --argjson id "$id" --arg b "$body" '. + [{id:$id, body:$b}]' "$STATE" >"$STATE.t" && mv "$STATE.t" "$STATE" ;;
  api)
    method="GET"; path=""; field=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --method) shift; method="$1" ;;
        --hostname) shift ;;
        -f|-F|--field|--raw-field) shift; field="$1" ;;
        -*) : ;;
        *) [ -z "$path" ] && path="$1" ;;
      esac
      shift
    done
    if [ "$method" = "GET" ]; then cat "$STATE"
    else
      cid="${path##*/}"; body="${field#body=}"
      jq --argjson id "$cid" --arg b "$body" 'map(if .id==$id then .body=$b else . end)' "$STATE" >"$STATE.t" && mv "$STATE.t" "$STATE"
    fi ;;
esac
exit 0
GH
chmod +x "$BIN/gh"

export PATH="$BIN:$PATH" STORE="$TMPD/store" REPO STATE="$TMPD/comments.json" GC_RIG_ROOT="$TMPD/rig"
unset GC_CITY_PATH 2>/dev/null || true

# fixture: the subject tk-subj with PR 41 and a review gate, and the
# conversation tk-conv a sitting holds, replying to that gate.
fixture() {
  rm -rf "$STORE"; mkdir -p "$STORE/b"; printf '[]' > "$STATE"
  jq -n '{id:"tk-subj", issue_type:"task", status:"open", assignee:"", metadata:{pr_number:"41", pr_url:"https://github.com/acme/widgets/pull/41"}, deps:[{type:"blocks", on:"tk-gate"}]}' > "$STORE/b/tk-subj.json"
  jq -n '{id:"tk-gate", issue_type:"gate", await_type:"human", await_id:"review-needs-you.tk-f", status:"open", assignee:"", metadata:{}, deps:[]}' > "$STORE/b/tk-gate.json"
  jq -n '{id:"tk-conv", issue_type:"task", status:"in_progress", assignee:"gc-toolkit/gc-toolkit.tk-conv", metadata:{}, deps:[{type:"tracks", on:"tk-subj"}, {type:"replies-to", on:"tk-gate"}]}' > "$STORE/b/tk-conv.json"
  ( cd "$TMPD/cwd" && bash "$REMINDER" engage --sitting tk-conv --subject tk-subj ) >/dev/null 2>&1
}

echo "── a ruled sign-off edits the reminder to say the sitting ended, with its summary and actions ──"
fixture
has "the engage posted the open reminder" "$(jq -r '.[0].body // ""' "$STATE")" "Sitting on tk-conv — open"
( cd "$TMPD/cwd" && bash "$SIGNOFF" --conversation tk-conv --outcome "we fix the retry first" \
    --ruled yes --ruling "fix the retry" --route human --no-wait ) >/dev/null 2>&1
BODY="$(jq -r '.[0].body // ""' "$STATE")"
has "the same comment now says the sitting ended, settled" "$BODY" "Sitting on tk-conv — ended (settled)"
has "the headline is its summary" "$BODY" "Summary: we fix the retry first"
has "the ruling is among its actions" "$BODY" "ruling: fix the retry (released to human)"
has "…as is the gate it resolved" "$BODY" "resolved gate tk-gate"
[ "$(jq 'length' "$STATE")" = 1 ] && ok "still one comment on the thread" || bad "still one comment on the thread" "$(cat "$STATE")"

echo "── what the sign-off hands the reminder meets the real rig-mention check ──"
fixture
( cd "$TMPD/cwd" && bash "$SIGNOFF" --conversation tk-conv --outcome "the same defect on rig-b" \
    --ruled yes --ruling "fix the retry" --route human --no-wait ) >/dev/null 2>&1
BODY="$(jq -r '.[0].body // ""' "$STATE")"
has "the comment still says the sitting ended, settled" "$BODY" "Sitting on tk-conv — ended (settled)"
hasnt "a summary naming another rig is left out" "$BODY" "Summary:"
hasnt "…so the rig never reaches the PR" "$BODY" "rig-b"
has "the actions it clears stay" "$BODY" "ruling: fix the retry (released to human)"

echo "── a cut-short sign-off edits it to say the conversation was handed back ──"
fixture
( cd "$TMPD/cwd" && bash "$SIGNOFF" --conversation tk-conv --outcome "the rollout question is still owed" --ruled no ) >/dev/null 2>&1
BODY="$(jq -r '.[0].body // ""' "$STATE")"
has "the comment says the sitting ended, handed back" "$BODY" "Sitting on tk-conv — ended (handed back)"
has "…that the conversation waits in the operator's queue" "$BODY" "conversation back in the operator's queue"
has "…and which gate is still owed" "$BODY" "left tk-gate open and owed"

echo
echo "pr-sitting-comment-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
