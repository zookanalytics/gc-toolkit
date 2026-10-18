#!/usr/bin/env bash
# Hermetic test for assets/scripts/feedback-miner.sh, the mechanical half of
# mol-feedback-miner. Stub gh serves a repository's PR listings and review
# streams from fixtures, stub gc serves a JSON observation store and records
# what it files, and a git fixture gives the checkout an origin of ours and an
# upstream of someone else's. No network, no live city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/feedback-miner.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-feedback-miner-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
# Substring tests, newlines included: a multi-line needle must match whole.
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2')" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

ago() { jq -nr --argjson t "$(( $(date -u +%s) - $1 * 86400 ))" '$t | todate'; }
ago_h() { jq -nr --argjson t "$(( $(date -u +%s) - $1 * 3600 ))" '$t | todate'; }

FIX="$TMP/fix"; STORE="$TMP/store"; BIN="$TMP/bin"
mkdir -p "$FIX" "$STORE" "$BIN"

# --- the checkout: origin is ours, upstream is a third party's ----------------
CO="$TMP/checkout"
git init -q -b main "$CO"
git -C "$CO" remote add upstream git@github.com:them/repo.git
git -C "$CO" remote add origin git@github.com:ours/repo.git

# --- stub gh ---------------------------------------------------------------------
# gh's own resolution order with no default set: a bare `gh repo view` answers
# for upstream. The PR listing is the GraphQL pullRequests connection, newest
# update first, served STUB_PAGE nodes at a time (default 100) from the
# owner's fixture; its cursor is the offset.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gh" <<'STUB'
set -u
printf '%s\n' "$*" >> "$STUB_LOG/gh.log"
case "${1:-} ${2:-}" in
  "repo view")
    case "${3:-}" in
      ""|-*) echo "them/repo" ;;
      *) printf '%s\n' "$3" | sed -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' ;;
    esac
    exit 0 ;;
  "api user") echo "city-bot"; exit 0 ;;
  "api graphql")
    owner=""; cursor=0
    shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        -f|-F) case "$2" in owner=*) owner="${2#owner=}" ;; cursor=*) cursor="${2#cursor=}" ;; esac; shift 2 ;;
        *) shift ;;
      esac
    done
    f="$STUB_FIX/prs.$owner.json"; [ -f "$f" ] || f="$STUB_FIX/empty.json"
    jq --argjson off "$cursor" --argjson size "${STUB_PAGE:-100}" '
      sort_by(.updatedAt) | reverse | . as $all
      | {data: {repository: {pullRequests: {nodes: $all[$off:($off + $size)],
         pageInfo: {hasNextPage: (($off + $size) < ($all | length)), endCursor: (($off + $size) | tostring)}}}}}' "$f"
    exit 0 ;;
esac
if [ "${1:-}" = api ]; then
  path="${2%%\?*}"
  case "$path" in
    repos/ours/repo/pulls/*/reviews)  n=${path#repos/ours/repo/pulls/}; n=${n%/reviews}; s=reviews ;;
    repos/ours/repo/pulls/*/comments) n=${path#repos/ours/repo/pulls/}; n=${n%/comments}; s=inline ;;
    repos/ours/repo/issues/*/comments) n=${path#repos/ours/repo/issues/}; n=${n%/comments}; s=issue ;;
    *) echo "stub gh: no fixture for $path" >&2; exit 1 ;;
  esac
  [ -f "$STUB_FIX/$n.fail" ] && { echo "HTTP 502" >&2; exit 1; }
  [ -f "$STUB_FIX/$n.$s.json" ] && jq -c '.[]' "$STUB_FIX/$n.$s.json"
  exit 0
fi
echo "stub gh: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$BIN/gh"

# --- stub gc ---------------------------------------------------------------------
# `bd list -l observation` reads the store; `--has-metadata-key
# pr_provenance_since` reads the anchors; `bd create` appends to the store so a
# later listing sees what was filed.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
printf '%s\n' "$*" >> "$STUB_LOG/gc.log"
[ "${1:-}" = bd ] || { echo "stub gc: unexpected call: $*" >&2; exit 1; }
shift
case "${1:-}" in
  list)
    case " $* " in
      *" --has-metadata-key pr_provenance_since "*) cat "$STUB_STORE/anchors.json"; exit 0 ;;
      *" -l observation "*)
        [ -n "${STUB_OBS_BROKEN:-}" ] && { echo "bd: store unreachable" >&2; exit 1; }
        cat "$STUB_STORE/obs.json"; exit 0 ;;
    esac ;;
  create)
    shift
    title="$1"; shift; body=""; meta='{}'; labels=(); status=open
    while [ $# -gt 0 ]; do
      case "$1" in
        -d) body="$2"; shift 2 ;;
        --metadata) meta="$2"; shift 2 ;;
        -l) labels+=("$2"); shift 2 ;;
        --status=*) status="${1#--status=}"; shift ;;
        *) shift ;;
      esac
    done
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo '{"error":"create refused"}'; exit 1; }
    n=$(( $(jq 'length' "$STUB_STORE/obs.json") + 1 ))
    id="tk-obs$n"
    jq --arg id "$id" --arg t "$title" --arg d "$body" --argjson m "$meta" --arg s "$status" \
       --arg l "$(printf '%s,' "${labels[@]}")" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '. + [{id: $id, title: $t, description: $d, status: $s, created_at: $at,
             labels: ($l | split(",") | map(select(. != ""))), metadata: $m}]' \
      "$STUB_STORE/obs.json" > "$STUB_STORE/obs.next" && mv "$STUB_STORE/obs.next" "$STUB_STORE/obs.json"
    printf '{"id":"%s"}\n' "$id"
    exit 0 ;;
esac
echo "stub gc: unexpected call: bd $*" >&2
exit 1
STUB
chmod +x "$BIN/gc"

# patrol-finding.sh stand-in: records its argv one argument per line.
cat > "$BIN/patrol-finding" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do printf '%s\n' "$a"; done > "$STUB_LOG/finding.args"
exit 0
STUB
chmod +x "$BIN/patrol-finding"

export PATH="$BIN:$PATH"
export STUB_LOG="$TMP" STUB_FIX="$FIX" STUB_STORE="$STORE"
export GC_PATROL_FINDING_TOOL="$BIN/patrol-finding"
export GC_RIG=fixture-rig

MARK='<!-- gc:city -->'
CUT=$(ago 2)

# --- fixtures --------------------------------------------------------------------
# PR 11 closed an hour ago, inside the standing window. PR 12 closed ten days
# ago, inside the back-fill window only. PR 13 closed and was last updated 40
# days ago, so the listing stops on it. PR 14 closed 40 days ago and drew a
# comment two hours ago, so it lists early but closed before every window.
# Upstream lists PR 99, which a run that lets gh pick the repository would read.
jq -n --arg r "$(ago_h 1)" --arg o "$(ago 10)" --arg a "$(ago 40)" --arg u "$(ago_h 2)" '[
  {number: 11, title: "Fix the frobnicator", closedAt: $r, mergedAt: $r, updatedAt: $r},
  {number: 12, title: "Old change", closedAt: $o, mergedAt: $o, updatedAt: $o},
  {number: 13, title: "Ancient change", closedAt: $a, mergedAt: null, updatedAt: $a},
  {number: 14, title: "Ancient but busy", closedAt: $a, mergedAt: $a, updatedAt: $u}]' > "$FIX/prs.ours.json"
jq -n --arg r "$(ago_h 1)" '[{number: 99, title: "Someone else", closedAt: $r, mergedAt: $r, updatedAt: $r}]' > "$FIX/prs.them.json"
echo '[]' > "$FIX/empty.json"

user() { jq -nc --arg l "$1" --arg t "${2:-User}" '{login: $l, type: $t}'; }
review() { # id login type state body submitted_at
  jq -nc --argjson id "$1" --argjson u "$(user "$2" "$3")" --arg st "$4" --arg b "$5" --arg at "$6" \
    '{id: $id, user: $u, state: $st, body: $b, submitted_at: $at,
      html_url: ("https://github.com/ours/repo/pull/11#pullrequestreview-" + ($id | tostring))}'
}
inline() { # id login review_id body created_at [reply_to]
  jq -nc --argjson id "$1" --argjson u "$(user "$2")" --argjson r "$3" --arg b "$4" --arg at "$5" --arg rt "${6:-}" \
    '{id: $id, user: $u, pull_request_review_id: $r, body: $b, created_at: $at, path: "lib/frob.sh", line: 7,
      in_reply_to_id: (if $rt == "" then null else ($rt | tonumber) end),
      html_url: ("https://github.com/ours/repo/pull/11#discussion_r" + ($id | tostring))}'
}
issue() { # id login type body created_at [pr]
  jq -nc --argjson id "$1" --argjson u "$(user "$2" "$3")" --arg b "$4" --arg at "$5" --arg pr "${6:-11}" \
    '{id: $id, user: $u, body: $b, created_at: $at,
      html_url: ("https://github.com/ours/repo/pull/" + $pr + "#issuecomment-" + ($id | tostring))}'
}

LONG=$(printf 'The quoted text runs long. %.0s' $(seq 1 120))
{
  review 101 johnzook User COMMENTED "Please split this function; it does three things." "$(ago_h 5)"
  review 102 city-bot User COMMENTED "VERDICT: approve
Reviewed commit: abc
$MARK" "$(ago_h 4)"
  review 103 city-bot User COMMENTED "Code review: 2 findings. The first one blocks." "$(ago_h 3)"
  review 104 city-bot User COMMENTED "A notice a city writer posted without the mark." "$(ago_h 2)"
  review 105 "copilot[bot]" Bot COMMENTED "Copilot found a possible null dereference." "$(ago_h 3)"
  review 106 "autoapprove[bot]" Bot APPROVED "Auto-approved: dependency bump." "$(ago_h 3)"
  review 107 johnzook User APPROVED "" "$(ago_h 1)"
  review 108 johnzook User COMMENTED "$LONG" "$(ago_h 2)"
} | jq -s . > "$FIX/11.reviews.json"
{
  inline 201 johnzook 101 "This loop never terminates on empty input." "$(ago_h 5)"
  inline 202 city-bot 102 "✅ Fixed in abc1234 (tk-x).
<!-- gc-writeback -->
$MARK" "$(ago_h 4)" 201
  inline 203 city-bot 103 "**The guard reads the wrong variable.** It checks \$a where \$b is meant." "$(ago_h 3)"
} | jq -s . > "$FIX/11.inline.json"
{
  issue 301 city-bot User "Pre-open signoff (comment-only — not an approval): VERDICT: approve" "$(ago 3)"
  issue 302 "vercel[bot]" Bot "[vc]: deployment preview ready" "$(ago_h 3)"
  issue 303 johnzook User "   " "$(ago_h 2)"
  issue 304 johnzook User "Could this use a demo video?" "$(ago_h 1)"
} | jq -s . > "$FIX/11.issue.json"
issue 401 johnzook User "Old feedback from last week." "$(ago 10)" 12 | jq -s . > "$FIX/12.issue.json"
# PR 12's city post is a review body.
issue 402 city-bot User "Triage: approve. $MARK" "$(ago 10)" 12 \
  | jq -s '[.[] | . + {state: "COMMENTED", submitted_at: .created_at}]' > "$FIX/12.reviews.json"
echo '[]' > "$FIX/12.inline.json"

# PR 11's anchor began expecting the mark two days ago: review 104 is after the
# cutover, issue 301 three days ago before it.
jq -n --arg c "$CUT" '[{id: "tk-anchor11", metadata: {pr_number: 11, pr_provenance_since: $c}}]' > "$STORE/anchors.json"
echo '[]' > "$STORE/obs.json"

key() { printf 'pr:ours/repo#%s:%s:%s' "$1" "$2" "$3"; }
class_of() { jq -r --arg k "$1" 'select(.key == $k) | .class' "$W/sweep.jsonl"; }
field_of() { jq -r --arg k "$1" --arg f "$2" 'select(.key == $k) | .[$f] | tostring' "$W/sweep.jsonl"; }
fresh_dir() { W="$TMP/work.$1"; rm -rf "$W"; mkdir -p "$W"; : > "$TMP/gh.log"; : > "$TMP/gc.log"; }

echo "── identity: the slug is origin's, never what gh picks by itself ──"
eq "$(gh repo view --json nameWithOwner -q .nameWithOwner)" "them/repo" \
   "(control) a bare gh repo view in this checkout answers for upstream"
OUT=$("$SUT" identity --checkout "$CO")
eq "$OUT" "ours/repo	city-bot" "(1) identity resolves origin's repository and the login gh posts as"
git -C "$CO" remote remove origin
"$SUT" identity --checkout "$CO" >/dev/null 2>&1; eq "$?" "1" "(2) a checkout with no origin resolves no identity"
git -C "$CO" remote add origin git@github.com:ours/repo.git

echo "── sweep, first run: no outside-review observation yet, so it back-fills ──"
fresh_dir a
OUT=$("$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(3) the first sweep exits 0"
has "$OUT" "younger than one 3-day window, so it reads the last 30 days" "(4) the first sweep says it back-fills"
eq "$(grep -c '^api graphql' "$TMP/gh.log")" "1" "(5) one page lists every PR the window can hold"
eq "$(grep '^api graphql' "$TMP/gh.log" | grep -c -- '-f owner=ours -f name=repo')" "1" "(6) the PR listing names origin's repository"
eq "$(grep '^api repos/' "$TMP/gh.log" | grep -vc '^api repos/ours/repo/')" "0" "(7) every stream read names origin's repository"
hasnt "$(cat "$W/sweep.jsonl")" '"pr":99' "(8) upstream's PR is never read"
eq "$(grep -c '^api repos/ours/repo/[a-z]*/1[34]/' "$TMP/gh.log" || true)" "0" "(8a) a PR closed before the window is never read, however recently it was updated"

eq "$(class_of "$(key 11 review 101)")" "outside" "(9) another login's review is outside"
eq "$(class_of "$(key 11 comment 201)")" "outside" "(10) another login's inline comment is outside"
eq "$(class_of "$(key 11 review 102)")" "city" "(11) a marked review is the city's"
eq "$(class_of "$(key 11 comment 202)")" "city" "(12) a write-back reply is the city's"
eq "$(class_of "$(key 11 review 103)")" "outside" "(13) a /code-review review under the city's login is outside"
eq "$(class_of "$(key 11 comment 203)")" "outside" "(14) that review's inline comment is outside too"
eq "$(field_of "$(key 11 review 103)" signed)" "true" "(15) it is marked as signed /code-review output"
eq "$(class_of "$(key 11 review 104)")" "city" "(16) an unmarked unsigned post under the city's login is the city's"
eq "$(field_of "$(key 11 review 104)" flag)" "true" "(17) posted after its PR's cutover, it is flagged"
eq "$(class_of "$(key 11 comment 301)")" "city" "(18) an unmarked city post from before the cutover is the city's"
eq "$(field_of "$(key 11 comment 301)" flag)" "false" "(19) it is not flagged"
eq "$(class_of "$(key 11 review 105)")" "outside" "(20) an app account's commenting review is outside"
eq "$(class_of "$(key 11 review 106)")" "notice" "(21) an app account's approval is a notice"
eq "$(class_of "$(key 11 comment 302)")" "notice" "(22) an app account's conversation comment is a notice"
eq "$(class_of "$(key 11 review 107)")" "" "(23) an approval with no body is not read"
eq "$(class_of "$(key 11 comment 303)")" "" "(24) a whitespace-only comment is not read"
eq "$(class_of "$(key 12 comment 401)")" "outside" "(25) a back-fill PR's outside comment is read"
eq "$(field_of "$(key 12 comment 401)" in_window)" "false" "(26) a back-fill PR is outside the standing window"
eq "$(field_of "$(key 11 comment 201)" in_window)" "true" "(27) a recent PR is inside the standing window"
eq "$(field_of "$(key 11 comment 201)" at)" "$(jq -r '.[] | select(.id == 101) | .submitted_at' "$FIX/11.reviews.json")" \
   "(28) an inline comment is dated by the submission of the review that carries it"
eq "$(field_of "$(key 11 comment 202)" reply_to)" "201" "(29) a reply records the comment it answers"

echo "── show ──"
OUT=$("$SUT" show --dir "$W" --outside --limit 50)
has "$OUT" "== 8 of 8 outside post(s) not yet recorded ==" "(30) show --outside counts the unrecorded outside posts"
hasnt "$OUT" "$(key 11 review 102)" "(31) show --outside leaves the city's posts out"
hasnt "$OUT" "$(key 11 comment 302)" "(32) show --outside leaves app notices out"
eq "$(printf '%s\n' "$OUT" | grep '^--- ' | head -1)" "--- $(key 11 comment 304)" "(33) the newest outside post is shown first"
eq "$("$SUT" show --dir "$W" --outside --limit 2 | grep -c '^--- ')" "2" "(34) --limit caps how many are shown"
OUT=$("$SUT" show --dir "$W" --city)
has "$OUT" "$(key 11 review 104)" "(35) show --city lists the city's posts in the standing window"
hasnt "$OUT" "$(key 12 review 402)" "(36) show --city leaves out a back-fill PR's city post"
has "$OUT" "[FLAGGED: unmarked]" "(37) a flagged post is labelled"

echo "── file: the outside capture ──"
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 review 101)", "statement": "The reviewer asks for the function to be split because it does three things.", "directive": "diff"}
{"key": "$(key 11 comment 201)", "statement": "The loop never ends on empty input.", "directive": "diff", "context": "The PR added the loop."}
{"key": "$(key 11 review 108)", "statement": "A long review.", "directive": "standing"}
ROWS_EOF
); RC=$?
eq "$RC" "0" "(38) filing outside rows exits 0"
has "$OUT" "filed 3, skipped 0" "(39) all three are filed"
OBS=$(jq -c --arg k "$(key 11 comment 201)" '.[] | select(.metadata["obs.provenance"] == $k)' "$STORE/obs.json")
eq "$(jq -r '.metadata["obs.category"]' <<< "$OBS")" "outside-review" "(40) the outside capture files under outside-review"
eq "$(jq -r '.metadata["obs.source"]' <<< "$OBS")" "miner" "(41) its source is the miner"
eq "$(jq -r '.metadata.task_kind' <<< "$OBS")" "observation" "(42) it is an observation"
eq "$(jq -r '.status' <<< "$OBS")" "closed" "(43) it is closed at creation"
eq "$(jq -r '.labels | join(",")' <<< "$OBS")" "learning,observation" "(44) it carries both labels"
eq "$(jq -r '.metadata["obs.scope"]' <<< "$OBS")" "repo:fixture-rig" "(45) its scope defaults to the rig"
eq "$(jq -r '.title' <<< "$OBS")" "obs: The loop never ends on empty input. (pr:ours/repo#11)" "(46) its title is the statement and the PR"
BODY=$(jq -r '.description' <<< "$OBS")
has "$BODY" "## Statement
The loop never ends on empty input." "(47) the body opens with the statement"
has "$BODY" "> This loop never terminates on empty input.
— johnzook, https://github.com/ours/repo/pull/11#discussion_r201" "(48) the quote carries its author and link"
has "$BODY" "PR #11, \"Fix the frobnicator\": an inline comment on \`lib/frob.sh\`, line 7. The PR added the loop." \
    "(49) the context names the PR, the locus and the row's context"
hasnt "$BODY" "## Proposed norm" "(50) the outside capture proposes no norm"
LONG_BODY=$(jq -r --arg k "$(key 11 review 108)" '.[] | select(.metadata["obs.provenance"] == $k) | .description' "$STORE/obs.json")
has "$LONG_BODY" " …
— johnzook" "(51) a long quote is cut, and the link carries the rest"
eq "$(jq -r --arg k "$(key 11 review 108)" '.[] | select(.metadata["obs.provenance"] == $k) | .metadata["obs.directive"]' "$STORE/obs.json")" \
   "standing" "(52) the row's directive is kept"

CREATES=$(grep -c '^bd create' "$TMP/gc.log")
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 comment 201)", "statement": "Captured again.", "directive": "diff"}
ROWS_EOF
)
has "$OUT" "already recorded under outside-review" "(53) a post already recorded is skipped"
eq "$(grep -c '^bd create' "$TMP/gc.log")" "$CREATES" "(54) and nothing is created for it"
OUT=$("$SUT" show --dir "$W" --outside --limit 50)
has "$OUT" "== 5 of 5 outside post(s) not yet recorded ==" "(55) show --outside drops what this run filed"

OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 comment 304)", "statement": "Asks for a demo video.", "directive": "diff"}
{"key": "$(key 11 comment 304)", "statement": "Asks for a demo video again.", "directive": "diff"}
ROWS_EOF
)
has "$OUT" "already filed under outside-review by an earlier row of this call" "(56) a second row on one post in one call is skipped"
eq "$(jq --arg k "$(key 11 comment 304)" '[.[] | select(.metadata["obs.provenance"] == $k)] | length' "$STORE/obs.json")" "1" \
   "(57) one observation per outside post"

echo "── file: refused rows ──"
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "pr:ours/repo#11:comment:999", "statement": "No such post."}
{"key": "$(key 11 comment 302)", "statement": "A deploy preview."}
{"key": "$(key 11 review 105)", "statement": ""}
{"key": "$(key 11 review 105)", "statement": "Copilot flags a null dereference.", "directive": "loud"}
not json
{"key": "$(key 11 review 105)", "statement": "Copilot flags a possible null dereference."}
ROWS_EOF
); RC=$?
eq "$RC" "1" "(58) a call with refused rows exits 1"
has "$OUT" "no swept post has this key" "(59) an unknown key is refused"
has "$OUT" "an app account notice is not review feedback" "(60) an app notice is refused"
has "$OUT" "the row has no statement" "(61) an empty statement is refused"
has "$OUT" "directive must be standing or diff" "(62) a bad directive is refused"
has "$OUT" "row is not a JSON object" "(63) a line that is not JSON is refused"
has "$OUT" "filed 1," "(64) the valid row in the same call is still filed"

echo "── file: the standing-behavior capture on the city's posts ──"
OUT=$("$SUT" file --dir "$W" --max-standing 1 <<ROWS_EOF 2>&1
{"key": "$(key 11 review 104)", "statement": "Verdicts should name the commit.", "category": "verdict-names-commit", "norm": "Name the reviewed commit in every verdict.", "directive": "diff"}
{"key": "$(key 11 comment 301)", "statement": "A second standing point.", "category": "second-point", "norm": "Do the second thing."}
ROWS_EOF
)
has "$OUT" "dropped for the 1-per-run standing cap" "(65) --max-standing drops the row past the cap"
STD=$(jq -c --arg k "$(key 11 review 104)" '.[] | select(.metadata["obs.provenance"] == $k)' "$STORE/obs.json")
eq "$(jq -r '.metadata["obs.category"]' <<< "$STD")" "verdict-names-commit" "(66) a standing capture files under its own category"
has "$(jq -r '.description' <<< "$STD")" "## Proposed norm
Name the reviewed commit in every verdict." "(67) a standing capture carries its proposed norm"
OUT=$("$SUT" file --dir "$W" --max-standing 1 <<ROWS_EOF 2>&1
{"key": "$(key 11 comment 301)", "statement": "Still over the cap.", "category": "second-point", "norm": "Do it."}
ROWS_EOF
)
has "$OUT" "dropped for the 1-per-run standing cap" "(68) the cap counts what earlier calls of the run filed"
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 review 102)", "statement": "No norm here.", "category": "some-slug"}
{"key": "$(key 11 review 102)", "statement": "Wrong category.", "category": "outside-review", "norm": "N."}
ROWS_EOF
)
has "$OUT" "a city post needs a proposed norm" "(69) a standing row with no norm is refused"
has "$OUT" "a city post needs its own category, other than outside-review" "(70) a standing row cannot take the outside category"

echo "── flag ──"
"$SUT" flag --dir "$W" >/dev/null 2>&1; RC=$?
eq "$RC" "0" "(71) flag exits 0"
ARGS=$(cat "$TMP/finding.args" 2>/dev/null)
has "$ARGS" "unmarked-city-post" "(72) the finding is keyed on the situation"
has "$ARGS" "miner-findings" "(73) it is filed in the miner's scope"
has "$ARGS" "https://github.com/ours/repo/pull/11#pullrequestreview-104" "(74) it names the flagged post"
hasnt "$ARGS" "#issuecomment-301" "(75) it leaves out the post from before the cutover"
has "$ARGS" "fixture-rig" "(76) it lands in the swept rig's store"

echo "── sweep, a paged listing stops at the first PR updated before the window ──"
fresh_dir p
STUB_PAGE=1 "$SUT" sweep --checkout "$CO" --days 30 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(grep -c '^api graphql' "$TMP/gh.log")" "4" "(76a) the 30-day listing pages until a PR updated before the window"
eq "$(class_of "$(key 12 comment 401)")" "outside" "(76b) and reads the window's PRs on every page"
fresh_dir q
STUB_PAGE=1 "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
eq "$(grep -c '^api graphql' "$TMP/gh.log")" "3" "(76c) a 3-day listing stops at PR 12, ten days old, and never asks for PR 13"

echo "── sweep, a resumed first run: the outside capture began today ──"
fresh_dir r
OUT=$("$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1)
has "$OUT" "reads the last 30 days" "(77a) a run inside the capture's first window still back-fills"
eq "$(class_of "$(key 12 comment 401)")" "outside" "(77b) so a back-fill a session could not finish is finished"

echo "── sweep, a later run: the outside capture is a window old ──"
fresh_dir b
rm -f "$TMP/finding.args"
jq --arg old "$(ago 5)" 'map(if .metadata["obs.category"] == "outside-review" then . + {created_at: $old} else . end)' \
  "$STORE/obs.json" > "$STORE/obs.next" && mv "$STORE/obs.next" "$STORE/obs.json"
OUT=$("$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1)
hasnt "$OUT" "reads the last 30 days" "(78) a sweep once the capture is a window old reads the normal window"
eq "$(class_of "$(key 12 comment 401)")" "" "(79) the back-fill PR is out of the window"
eq "$(field_of "$(key 11 comment 201)" captured)" "true" "(80) a post recorded by an earlier run reads as captured"
has "$("$SUT" show --dir "$W" --city)" "already recorded on this post: tk-obs" "(81) show names what is already recorded on a post"
"$SUT" flag --dir "$W" >/dev/null 2>&1
has "$(cat "$TMP/finding.args" 2>/dev/null)" "pullrequestreview-104" "(82) the flag is raised again while the post is in the window"

echo "── sweep, an outside-review observation whose date does not read ──"
fresh_dir g
cp "$STORE/obs.json" "$STORE/obs.keep"
jq 'map(if .metadata["obs.category"] == "outside-review" then . + {created_at: "not a date"} else . end)' \
  "$STORE/obs.keep" > "$STORE/obs.json"
OUT=$("$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1)
hasnt "$OUT" "reads the last 30 days" "(82a) an undated outside capture counts as old, so it never back-fills again"
mv "$STORE/obs.keep" "$STORE/obs.json"

echo "── sweep, failures ──"
fresh_dir c
: > "$FIX/11.fail"
OUT=$("$SUT" sweep --checkout "$CO" --days 30 --backfill-days 30 --dir "$W" 2>&1); RC=$?
rm -f "$FIX/11.fail"
eq "$RC" "0" "(83) a PR that does not read does not stop the sweep"
has "$OUT" "did not read, left for the next run: 11" "(84) the PR that did not read is named"
eq "$(class_of "$(key 12 comment 401)")" "outside" "(85) the other PRs are still swept"
: > "$TMP/gh.log"
"$SUT" sweep --checkout "$CO" --days 30 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(class_of "$(key 11 comment 201)")" "outside" "(85a) a sweep re-run into the same dir reads the PR it missed"
eq "$(grep -c '^api repos/ours/repo/issues/12/' "$TMP/gh.log" || true)" "0" "(85b) and keeps the PRs it already read"
fresh_dir d
OUT=$(STUB_OBS_BROKEN=1 "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1); RC=$?
eq "$RC" "1" "(86) an unreadable observation store stops the sweep"
has "$OUT" "nothing can be deduped" "(87) and says why"
eq "$(grep -c '^pr list' "$TMP/gh.log")" "0" "(88) it reads no PR before it can dedup"

echo "── summary ──"
fresh_dir e
echo '[]' > "$STORE/obs.json"
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
"$SUT" file --dir "$W" >/dev/null 2>&1 <<ROWS_EOF
{"key": "$(key 11 comment 201)", "statement": "The loop never ends on empty input."}
ROWS_EOF
OUT=$("$SUT" summary --dir "$W")
has "$OUT" "outside window 3 day(s)" "(89) with no back-fill window the first run reads the normal window"
has "$OUT" "outside posts: 7 read, 0 recorded before this run, 1 filed now, 6 left unrecorded" "(90) the summary counts the outside capture"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
