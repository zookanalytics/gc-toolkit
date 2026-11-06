#!/usr/bin/env bash
# pr-sitting-comment-wiring.test.sh — proves, end to end, that the writes which
# change what a visit's PR comment shows draw it again from the conversation.
# converse-prep's title step, run as the skill prints it, writes the topic as
# the conversation's title and posts the comment. converse-signoff.sh records
# the ruling and each act it takes on the conversation, then draws the comment
# in its ended shape once the conversation reads closed. The real
# pr-sitting-comment.sh and pr-post.sh run against stubs of gc and gh, so what
# the callers write meets the real view. The dismiss and hand-back call sites
# are covered by gc-helm-dismiss.test.sh and gc-helm-handback.test.sh, which own
# those harnesses, and gc-helm-engage.test.sh proves engage posts nothing.
#
# Hermetic: the sign-off runs from a pack directory that links the real scripts
# it composes and stubs the headline writer, lifecycle.sh and the rework's
# writers. No city, no network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PREP="$ROOT/skills/converse-prep/SKILL.md"
for f in "$HERE/converse-signoff.sh" "$HERE/pr-sitting-comment.sh" "$HERE/pr-post.sh" "$PREP"; do
  [ -r "$f" ] || { echo "not found: $f" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 2; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n       %s\n' "$1" "${2:-}"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3' in: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "found '$3' in: $2" ;; *) ok "$1" ;; esac; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/pr-sitting-comment-wiring.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; mkdir -p "$BIN" "$TMPD/store/b"

# The sitting's checkout: a git repo whose origin is the owned repository.
REPO="$TMPD/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" remote add origin https://github.com/acme/widgets.git

# The pack the sign-off runs from: the real scripts it composes, and stubs for
# the headline writer, lifecycle.sh, the rework's filer and the store resolver.
SR="$TMPD/pack/assets/scripts"; mkdir -p "$SR"
for f in converse-signoff.sh pr-sitting-comment.sh pr-post.sh bd-lib.sh conversation.sh work-outcome.sh; do
  ln -s "$HERE/$f" "$SR/$f"
done
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
cat > "$SR/converse-rework.sh" <<'R'
#!/usr/bin/env bash
echo "filed rework tk-rw on $2"
R
cat > "$SR/bead-store.sh" <<'S'
#!/usr/bin/env bash
case "$1" in --path) echo "$REPO" ;; *) echo fixture ;; esac
S
chmod +x "$SR/gc-helm.sh" "$SR/lifecycle.sh" "$SR/converse-rework.sh" "$SR/bead-store.sh"

# gc stub: one JSON file per bead under $STORE/b, its edges as deps [{type, on}],
# and its comments in <id>.comments.json.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'GC'
B="$STORE/b"
row() { cat "$B/$1.json" 2>/dev/null; }
put() { cat > "$B/$1.json.tmp" && mv "$B/$1.json.tmp" "$B/$1.json"; }
case "$1 ${2:-}" in
  "session rename") ;;
  "bd show")
    [ -f "$B/$3.json" ] || { printf '{"error":"no issues found"}\n'; exit 1; }
    row "$3" | jq -c '[. + {dependencies: [ .deps[] | {id: .on, dependency_type: .type} ]} | del(.deps)]' ;;
  "bd list")
    _id=""; _p=""; for a in "$@"; do [ "$_p" = "--id" ] && _id="$a"; _p="$a"; done
    row "$_id" | jq -c '[. + {dependencies: [ .deps[] as $d | {issue_id: .id, depends_on_id: $d.on, type: $d.type} ]} | del(.deps)]' ;;
  "bd dep") printf '[]\n' ;;
  "bd comments") cat "$B/$3.comments.json" 2>/dev/null || printf '[]\n' ;;
  "bd comment")
    _c=$(cat "$B/$3.comments.json" 2>/dev/null || printf '[]')
    printf '%s' "$_c" | jq -c --arg t "$4" '. + [{id: ("c" + (length | tostring)), text: $t, created_at: ("2026-11-05T10:00:" + (length + 10 | tostring) + "Z")}]' \
      > "$B/$3.comments.json" ;;
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
        --title)        _r=$(printf '%s' "$_r" | jq --arg v "$2" '.title = $v'); shift 2 ;;
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

export PATH="$BIN:$PATH" STORE="$TMPD/store" REPO STATE="$TMPD/comments.json"
unset GC_CITY_PATH 2>/dev/null || true
OPENER="Why does the retry spin? the words I typed to open this"
TOPIC="how the retry should work"
nl=$'\n'

# The title step as converse-prep prints it, with the topic filled in.
awk '
  /^[ \t]*```/ { if (inb) { if (hit) { printf "%s", buf; exit } inb = 0; buf = ""; hit = 0 }
                 else if ($0 ~ /```bash[ \t]*$/) inb = 1; next }
  inb { buf = buf $0 "\n"; if (index($0, "pr-sitting-comment.sh\" post")) hit = 1 }
' "$PREP" | sed "s#<topic>#$TOPIC#" > "$TMPD/title-step.sh"
[ -s "$TMPD/title-step.sh" ] && ok "converse-prep's title step is found" \
  || bad "converse-prep's title step is found" "no fenced bash block in $PREP runs pr-sitting-comment.sh post"

# fixture [no-topic] [open-pr]: the subject tk-subj with PR 41 and a review
# gate, and the conversation tk-conv a sitting holds, replying to that gate and
# opened with $OPENER. Unless no-topic is given, the sitting's title step has
# run. open-pr makes the subject an open PR the ruling must answer for.
fixture() {
  rm -rf "$STORE"; mkdir -p "$STORE/b"; printf '[]' > "$STATE"
  local mr=""; [ "${2:-}" = open-pr ] && mr=pull_request
  jq -n --arg mr "$mr" '{id:"tk-subj", issue_type:"task", status:"open", assignee:"", metadata:({pr_number:"41", pr_url:"https://github.com/acme/widgets/pull/41"} + (if $mr == "" then {} else {merge_result:$mr} end)), deps:[{type:"blocks", on:"tk-gate"}]}' > "$STORE/b/tk-subj.json"
  jq -n '{id:"tk-gate", issue_type:"gate", await_type:"human", await_id:"review-needs-you.tk-f", status:"open", assignee:"", metadata:{}, deps:[]}' > "$STORE/b/tk-gate.json"
  jq -n --arg o "$OPENER" '{id:"tk-conv", issue_type:"task", status:"in_progress", title:$o, description:$o, assignee:"gc-toolkit/gc-toolkit.tk-conv", metadata:{}, deps:[{type:"tracks", on:"tk-subj"}, {type:"replies-to", on:"tk-gate"}]}' > "$STORE/b/tk-conv.json"
  [ "${1:-}" = no-topic ] && return 0
  ( cd "$REPO" && env -u BASH_ENV -u ENV CONV="$SR" CONVERSATION=tk-conv SUBJECT=tk-subj GC_SESSION_ID=s-1 \
      bash "$TMPD/title-step.sh" ) >/dev/null 2>&1
}
signoff() { ( cd "$REPO" && bash "$SR/converse-signoff.sh" --conversation tk-conv "$@" ) >"$TMPD/signoff.out" 2>&1; }
body() { jq -r '.[0].body // ""' "$STATE"; }
actions() { jq -r '[.[].text] | join("|")' "$STORE/b/tk-conv.comments.json" 2>/dev/null; }
OPEN_LINES="<!-- gc:sitting:tk-conv -->$nl### Visit tk-conv on tk-subj${nl}Topic: $TOPIC"

echo "── the title step writes the topic onto the conversation and posts the comment ──"
fixture
[ "$(jq -r '.title' "$STORE/b/tk-conv.json")" = "$TOPIC" ] && ok "the conversation's title is the topic" \
  || bad "the conversation's title is the topic" "$(cat "$STORE/b/tk-conv.json")"
has "the comment shows the visit, the bead it is on and the topic" "$(body)" "$OPEN_LINES"
hasnt "…and not the words the visit opened with" "$(body)" "$OPENER"

echo "── a ruled sign-off records the ruling, then draws the ended comment ──"
fixture
signoff --outcome "ruled — we fix the retry first" --ruled yes --ruling "fix the retry first" --route human --no-wait
[ "$(actions)" = "Ruled: fix the retry first" ] && ok "the ruling is recorded on the conversation as its action" \
  || bad "the ruling is recorded on the conversation as its action" "$(actions)"
has "the comment keeps its open lines and adds the conclusion and the actions" "$(body)" \
  "$OPEN_LINES$nl${nl}Conclusion: none recorded$nl${nl}Actions:$nl- Ruled: fix the retry first"
hasnt "…and the headline, which is the subject's, does not reach it" "$(body)" "we fix the retry first"
[ "$(jq 'length' "$STATE")" = 1 ] && ok "still one comment on the thread" || bad "still one comment on the thread" "$(cat "$STATE")"

echo "── a re-run of the sign-off records no second action ──"
signoff --outcome "ruled — we fix the retry first" --ruled yes --ruling "fix the retry first" --route human --no-wait
[ "$(actions)" = "Ruled: fix the retry first" ] && ok "the ruling is recorded once" || bad "the ruling is recorded once" "$(actions)"

echo "── a rework sign-off records the PR it sent back and the ruling the gate carries ──"
fixture "" open-pr
signoff --outcome "ruled — the retry gets a cap" --ruled yes --ruling "cap the retry" --route human --no-wait --rework
[ "$(actions)" = "Sent PR #41 back for rework.|Ruled: cap the retry" ] && ok "the rework, then the ruling, in the order they landed" \
  || bad "the rework, then the ruling, in the order they landed" "$(actions) / $(cat "$TMPD/signoff.out")"
has "the comment lists both" "$(body)" "Actions:$nl- Sent PR #41 back for rework.$nl- Ruled: cap the retry"

echo "── a cut-short sign-off leaves the open comment as it is ──"
fixture
BEFORE="$(body)"
signoff --outcome "cut short — the rollout question is still owed" --ruled no
[ "$(jq -r '"\(.assignee)/\(.status)"' "$STORE/b/tk-conv.json")" = human/open ] && ok "the conversation is back in the operator's queue" \
  || bad "the conversation is back in the operator's queue" "$(cat "$STORE/b/tk-conv.json")"
[ "$(body)" = "$BEFORE" ] && ok "…and its comment is unchanged" || bad "…and its comment is unchanged" "$(body)"

echo "── a sign-off on a conversation whose sitting named no topic posts nothing ──"
fixture no-topic
signoff --outcome "ruled — we fix the retry first" --ruled yes --ruling "fix the retry first" --route human --no-wait
[ "$(jq 'length' "$STATE")" = 0 ] && ok "nothing is posted" || bad "nothing is posted" "$(cat "$STATE")"
[ "$(jq -r '.status' "$STORE/b/tk-conv.json")" = closed ] && ok "…though the sign-off closed the conversation" \
  || bad "…though the sign-off closed the conversation" "$(cat "$STORE/b/tk-conv.json")"
[ "$(actions)" = "Ruled: fix the retry first" ] && ok "…and the ruling is on the conversation all the same" \
  || bad "…and the ruling is on the conversation all the same" "$(actions)"

echo
echo "pr-sitting-comment-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
