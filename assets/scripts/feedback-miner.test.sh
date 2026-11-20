#!/usr/bin/env bash
# Hermetic test for assets/scripts/feedback-miner.sh, the mechanical half of
# mol-feedback-miner. Stub gh serves a repository's PR listings and review
# streams from fixtures, the compiled fake gc (test-harness.sh) serves the
# store and records each call, and a git fixture gives the checkout an origin
# of ours and an upstream of someone else's. No network, no live city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/feedback-miner.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-feedback-miner-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=assets/scripts/test-harness.sh
. "$HERE/test-harness.sh"
# The checkout fixture and the miner run the real git, which harness_init puts
# a stub in front of.
REAL_GIT="$(command -v git)" || { echo "git is required for this test" >&2; exit 1; }
# The flag files through the real patrol-finding.sh beside the miner, which asks
# the gctk built from this checkout what a held finding still waits on.
harness_build_gctk
harness_init
ln -sf "$REAL_GIT" "$BIN/git"
[ -n "${GCTK_BUILT:-}" ] || { echo "$PASS passed, $FAIL failed"; exit 1; }

# ago <days>, ago_h <hours> — a time that long before now, as GitHub writes one;
# day <days> — the day it falls on.
ago() { TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T\n' "$((EPOCHSECONDS - $1 * 86400))"; }
ago_h() { TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T\n' "$((EPOCHSECONDS - $1 * 3600))"; }
day() { TZ=UTC printf '%(%Y-%m-%d)T\n' "$((EPOCHSECONDS - $1 * 86400))"; }

FIX="$TMP/fix"
mkdir -p "$FIX"

# --- the checkout: origin is ours, upstream is a third party's ----------------
CO="$TMP/checkout"
git init -q -b main "$CO"
git -C "$CO" remote add upstream git@github.com:them/repo.git
git -C "$CO" remote add origin git@github.com:ours/repo.git
# default_branch <checkout> — commits its index and makes that commit the
# checkout's default branch, origin/main, which origin/HEAD names the way a
# clone records it: what a merge and the fetch after it leave.
default_branch() {
  git -C "$1" -c commit.gpgsign=false -c user.name=fixture -c user.email=fixture@example.com \
      -c core.hooksPath=/dev/null commit -q --allow-empty -m fixture \
    && git -C "$1" update-ref refs/remotes/origin/main HEAD \
    && git -C "$1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
# The rig declares Vercel's deployment notice not for review, by the prefix its
# first line opens with. A declaration counts as the default branch carries it.
printf '%s\n' '# Vercel' '[[marker]]' 'prefix = "[vc]: #"' > "$CO/not-for-review.toml"
git -C "$CO" add not-for-review.toml
default_branch "$CO"

# --- stub gh ---------------------------------------------------------------------
# gh's own resolution order with no default set: a bare `gh repo view` answers
# for upstream. The PR listing is the GraphQL pullRequests connection, newest
# update first, served STUB_PAGE nodes at a time (default 100) from the
# owner's fixture, one node a line, each opening with its updatedAt so that a
# reverse sort puts the newest first; its cursor is the offset. A review
# stream's fixture is one object a line.
{ _stub_shebang; cat; } > "$BIN/gh" <<'STUB'
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
    size="${STUB_PAGE:-100}"; all=()
    [ -f "$STUB_FIX/prs.$owner.jsonl" ] && mapfile -t all < <(LC_ALL=C sort -r "$STUB_FIX/prs.$owner.jsonl")
    nodes=("${all[@]:cursor:size}")
    more=false; [ $((cursor + size)) -lt "${#all[@]}" ] && more=true
    printf '{"data":{"repository":{"pullRequests":{"nodes":[%s],"pageInfo":{"hasNextPage":%s,"endCursor":"%s"}}}}}\n' \
      "$(IFS=,; printf '%s' "${nodes[*]}")" "$more" "$((cursor + size))"
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
  [ -f "$STUB_FIX/$n.$s.jsonl" ] && cat "$STUB_FIX/$n.$s.jsonl"
  exit 0
fi
echo "stub gh: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$BIN/gh"

# --- the rig of a call --------------------------------------------------------
# Once rigs_on names it, the fake runs this hook before each bd call, recording
# the rig the call ran under as "[<GC_RIG>] <arguments>" in $RIG_LOG. rig_of
# <text> is the rig of the last such call whose arguments carry the text.
export RIG_LOG="$TMP/rig.log"
cat > "$BIN/rig-hook" <<'HOOK'
#!/bin/sh
printf '[%s] %s\n' "${GC_RIG:-}" "$*" >> "$RIG_LOG"
HOOK
chmod +x "$BIN/rig-hook"
rigs_on() { : > "$RIG_LOG"; export STUB_HOOK_AT="bd " STUB_HOOK="$BIN/rig-hook"; }
rig_of() {
  local l r=""
  while IFS= read -r l; do case "$l" in *"$1"*) r=${l%%]*}; r=${r#\[} ;; esac; done < "$RIG_LOG"
  printf '%s\n' "$r"
}

# jq stand-in, put on PATH for one sweep only: it plays a sweep worker killed
# while it writes PR STUB_KILL_PR's posts, by printing part of a line and then
# killing the worker that started it. Every other call goes to the real jq.
KILLBIN="$TMP/killbin"; mkdir -p "$KILLBIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'REAL_JQ=%q\n' "$(command -v jq)"; cat; } > "$KILLBIN/jq" <<'STUB'
case " $* " in
  *" --argjson pr $STUB_KILL_PR "*)
    printf '{"key": "pr:ours/repo#%s:review:' "$STUB_KILL_PR"
    kill -9 "$PPID"; exit 137 ;;
esac
exec "$REAL_JQ" "$@"
STUB
chmod +x "$KILLBIN/jq"

# cat and jq stand-ins, put on PATH for one sweep only, that each fail one
# call. cat exits 1 on the file whose path ends in STUB_CAT_FAIL, the way a
# read that fails does. jq, when STUB_JQ_LIST_FAIL is set, prints the first
# number of the sweep's PR list and exits 5, the way a write that fails partway
# does. Every other call goes to the real tool.
FAULTBIN="$TMP/faultbin"; mkdir -p "$FAULTBIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'REAL_CAT=%q\n' "$(command -v cat)"; cat; } > "$FAULTBIN/cat" <<'STUB'
if [ -n "${STUB_CAT_FAIL:-}" ]; then
  case "${!#}" in
    *"$STUB_CAT_FAIL") echo "cat: ${!#}: Input/output error" >&2; exit 1 ;;
  esac
fi
exec "$REAL_CAT" "$@"
STUB
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'REAL_JQ=%q\n' "$(command -v jq)"; cat; } > "$FAULTBIN/jq" <<'STUB'
if [ -n "${STUB_JQ_LIST_FAIL:-}" ]; then
  case " $* " in
    *" -r .[].number "*) "$REAL_JQ" "$@" | head -n 1; exit 5 ;;
  esac
fi
exec "$REAL_JQ" "$@"
STUB
chmod +x "$FAULTBIN/cat" "$FAULTBIN/jq"

export STUB_LOG="$TMP" STUB_FIX="$FIX"
unset GC_PATROL_FINDING_TOOL GC_BD_LIB GC_FINDING_DEFAULT_RIG
# gctk's reaction verbs stand in for the real patrol-finding.sh's first
# reaction: the pool takes one, and each call is recorded. Every other verb is
# the build's.
cat > "$BIN/gctk" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = reaction ]; then
  shift
  printf '%s\\n' "\$*" >> "\$STUB_LOG/proactive.log"
  exit 0
fi
exec "$GCTK_BIN" "\$@"
STUB
chmod +x "$BIN/gctk"
export GCTK_BIN="$BIN/gctk"
export GC_RIG=fixture-rig
# The swept checkout is the repository pr-post.sh reads the rig's declaration
# from, whatever rig GC_RIG_ROOT names (case 111), so the session's own value
# is cleared rather than set.
unset GC_RIG_ROOT

MARK='<!-- gc:city -->'
CUT=$(ago 2)

# --- fixtures --------------------------------------------------------------------
# PR 11 closed an hour ago, inside the standing window. PR 12 closed ten days
# ago, inside the back-fill window only. PR 13 closed and was last updated 40
# days ago, so the listing stops on it. PR 14 closed 40 days ago and drew a
# comment two hours ago, so it lists early and is read, though it closed before
# every window.
# Upstream lists PR 99, which a run that lets gh pick the repository would read.
# The fixtures' JSON, written in bash: a user, a review, an inline comment and a
# conversation comment, each one line, and a node of the PR listing, which
# opens with its updatedAt.
user() { printf '{"login":%s,"type":%s}' "$(json_str "$1")" "$(json_str "${2:-User}")"; }
review() { # id login type state body submitted_at
  printf '{"id":%s,"user":%s,"state":%s,"body":%s,"submitted_at":%s,"html_url":"https://github.com/ours/repo/pull/11#pullrequestreview-%s"}\n' \
    "$1" "$(user "$2" "$3")" "$(json_str "$4")" "$(json_str "$5")" "$(json_str "$6")" "$1"
}
inline() { # id login review_id body created_at [reply_to]
  printf '{"id":%s,"user":%s,"pull_request_review_id":%s,"body":%s,"created_at":%s,"path":"lib/frob.sh","line":7,"in_reply_to_id":%s,"html_url":"https://github.com/ours/repo/pull/11#discussion_r%s"}\n' \
    "$1" "$(user "$2")" "$3" "$(json_str "$4")" "$(json_str "$5")" "${6:-null}" "$1"
}
issue() { # id login type body created_at [pr]
  printf '{"id":%s,"user":%s,"body":%s,"created_at":%s,"html_url":"https://github.com/ours/repo/pull/%s#issuecomment-%s"}\n' \
    "$1" "$(user "$2" "$3")" "$(json_str "$4")" "$(json_str "$5")" "${6:-11}" "$1"
}
pr_node() { # number title closedAt mergedAt updatedAt; a mergedAt of null is none
  local merged=null
  [ "$4" = null ] || merged=$(json_str "$4")
  printf '{"updatedAt":%s,"number":%s,"title":%s,"closedAt":%s,"mergedAt":%s}\n' \
    "$(json_str "$5")" "$1" "$(json_str "$2")" "$(json_str "$3")" "$merged"
}

R1=$(ago_h 1) O10=$(ago 10) A40=$(ago 40) U2=$(ago_h 2)
{
  pr_node 11 "Fix the frobnicator" "$R1" "$R1" "$R1"
  pr_node 12 "Old change" "$O10" "$O10" "$O10"
  pr_node 13 "Ancient change" "$A40" null "$A40"
  pr_node 14 "Ancient but busy" "$A40" "$A40" "$U2"
} > "$FIX/prs.ours.jsonl"
pr_node 99 "Someone else" "$R1" "$R1" "$R1" > "$FIX/prs.them.jsonl"

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
  review 109 johnzook User COMMENTED "<!-- gc:no-review -->
FYI: the preview is up, nothing to change." "$(ago_h 2)"
} > "$FIX/11.reviews.jsonl"
{
  inline 201 johnzook 101 "This loop never terminates on empty input." "$(ago_h 5)"
  inline 202 city-bot 102 "✅ Fixed in abc1234 (tk-x).
<!-- gc-writeback -->
$MARK" "$(ago_h 4)" 201
  inline 203 city-bot 103 "**The guard reads the wrong variable.** It checks \$a where \$b is meant." "$(ago_h 3)"
  inline 204 johnzook 101 "<!-- gc:no-review -->
Context only, nothing to change." "$(ago_h 5)"
} > "$FIX/11.inline.jsonl"
{
  issue 301 city-bot User "Pre-open signoff (comment-only — not an approval): VERDICT: approve" "$(ago 3)"
  issue 302 "vercel[bot]" Bot "[vc]: #dkbu2MRiHxbtC
The latest updates on your projects." "$(ago_h 3)"
  issue 303 johnzook User "   " "$(ago_h 2)"
  issue 304 johnzook User "Could this use a demo video?" "$(ago_h 1)"
  issue 305 "reviewer[bot]" Bot "The query interpolates the user's input into its SQL; bind it as a parameter.
[vc]: # is mentioned here, not at the top." "$(ago_h 2)"
  issue 306 "previewbot[bot]" Bot "<!-- gc:no-review -->
Schema diff: no changes." "$(ago_h 2)"
} > "$FIX/11.issue.jsonl"
issue 401 johnzook User "Old feedback from last week." "$(ago 10)" 12 > "$FIX/12.issue.jsonl"
# PR 12's city post is a review body.
R402_AT=$(ago 10)
R402=$(issue 402 city-bot User "Triage: approve. $MARK" "$R402_AT" 12)
printf '%s,"state":"COMMENTED","submitted_at":%s}\n' "${R402%\}}" "$(json_str "$R402_AT")" > "$FIX/12.reviews.jsonl"
: > "$FIX/12.inline.jsonl"

# PR 11's anchor began expecting the mark two days ago: review 104 is after the
# cutover, issue 301 three days ago before it. An anchor no longer listed is one
# whose pr_provenance_since the case removes.
anchor() { brow "$1" "metadata:={\"pr_number\":$2,\"pr_provenance_since\":$(json_str "$CUT")}"; }
anchor tk-anchor11 11
KV_KEY="feedback_miner.outside_since.ours_repo"
# kv <key> — the value the kv store holds under the key, or nothing.
kv() {
  local l
  while IFS= read -r l; do case "$l" in "$1="*) printf '%s\n' "${l#"$1="}"; return 0 ;; esac; done < "$STUB_KV"
}
kv_day() { kv "$KV_KEY"; }
kv_put() {
  local l rest=""
  while IFS= read -r l; do case "$l" in "$KV_KEY="*) ;; *) rest+="$l"$'\n' ;; esac; done < "$STUB_KV"
  printf '%s%s=%s\n' "$rest" "$KV_KEY" "$1" > "$STUB_KV"
}
updated_on() {
  local l
  while IFS= read -r l; do
    case "$l" in *"\"number\":$1,"*) l=$(json_get "$l" updatedAt); printf '%s\n' "${l:0:10}"; return 0 ;; esac
  done < "$FIX/prs.ours.jsonl"
}

key() { printf 'pr:ours/repo#%s:%s:%s' "$1" "$2" "$3"; }
# field_of <key> <field> — a field of the sweep's line for a post: a string's
# text as the line writes it, and any other value as written. class_of <key> is
# its class.
field_of() {
  local l r
  [ -f "$W/sweep.jsonl" ] || return 0
  while IFS= read -r l; do
    case "$l" in
      *"\"key\":\"$1\""*)
        r=${l#*\""$2"\":}
        [ "$r" = "$l" ] && return 0
        case "$r" in \"*) r=${r#\"}; printf '%s\n' "${r%%\"*}" ;; *) printf '%s\n' "${r%%[,\}]*}" ;; esac
        return 0 ;;
    esac
  done < "$W/sweep.jsonl"
}
class_of() { field_of "$1" class; }
fresh_dir() { W="$TMP/work.$1"; rm -rf "$W"; mkdir -p "$W"; : > "$TMP/gh.log"; : > "$TMP/gc.log"; }
# The findings: how many the flag's key holds, and the id of the n-th one filed,
# in the order the store holds them.
findings_n() { local ids; ids=$(bids metadata.finding.key=unmarked-city-post); set -- $ids; echo $#; }
finding() {
  local n="$1" ids
  ids=$(bids metadata.finding.key=unmarked-city-post); set -- $ids
  [ "$n" -le $# ] 2>/dev/null && printf '%s\n' "${!n}"
}
# set_status <status> [<n>]: the n-th finding's status, or every finding's. A
# closed one carries the close time bd stamps.
set_status() {
  local f ids
  local -a stamp=()
  [ "$1" = closed ] && stamp=(closed_at=2026-01-01T00:00:00Z)
  if [ -n "${2:-}" ]; then ids=$(finding "$2"); else ids=$(bids metadata.finding.key=unmarked-city-post); fi
  for f in $ids; do bset "$f" "status=$1" "${stamp[@]}"; done
}
post_record() { kv "feedback_miner.unmarked_post.$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"; }
# The observations: the id of the one the store records on a post, and the
# labels a row carries, comma-joined. obs_reset retires every observation, so
# the miner, which reads only rows whose task_kind is observation, sees none.
obs_of() { bids metadata.task_kind=observation "metadata.obs.provenance=$1"; }
obs_n() { local ids; ids=$(obs_of "$1"); set -- $ids; echo $#; }
labels_of() { local l; l=$(bfield "$1" labels); l=${l#[}; l=${l%]}; printf '%s\n' "${l//\"/}"; }
obs_reset() { local id; for id in $(bids metadata.task_kind=observation); do bset "$id" metadata.task_kind=retired; done; }
# add_review <id> <body>: an unmarked review under the city's login on PR 11,
# posted an hour ago, after the PR's cutover.
add_review() { review "$1" city-bot User COMMENTED "$2" "$(ago_h 1)" >> "$FIX/11.reviews.jsonl"; }

echo "── identity: the slug is origin's, never what gh picks by itself ──"
eq "$(gh repo view --json nameWithOwner -q .nameWithOwner)" "them/repo" \
   "(control) a bare gh repo view in this checkout answers for upstream"
OUT=$("$SUT" identity --checkout "$CO")
eq "$OUT" "ours/repo	city-bot" "(1) identity resolves origin's repository and the login gh posts as"
git -C "$CO" remote remove origin
"$SUT" identity --checkout "$CO" >/dev/null 2>&1; eq "$?" "1" "(2) a checkout with no origin resolves no identity"
git -C "$CO" remote add origin git@github.com:ours/repo.git
# Removing origin took its remote-tracking refs, the default branch among them.
default_branch "$CO"

echo "── sweep, first run: no outside capture day recorded yet, so it back-fills ──"
fresh_dir a
OUT=$(rigs_on; "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(3) the first sweep exits 0"
has "$OUT" "still owes a read of every PR updated since $(day 30), so the sweep reads back to then" "(4) the first sweep says it back-fills"
eq "$(kv_day)" "$(day 30)" "(4a) it records the back-fill's start as the outside capture's day, under origin's repository"
eq "$(rig_of 'bd kv')" "fixture-rig" "(4b) in the store of the rig it sweeps"
eq "$(grep -c '^api graphql' "$TMP/gh.log")" "1" "(5) one page lists every PR the window can hold"
eq "$(grep '^api graphql' "$TMP/gh.log" | grep -c -- '-f owner=ours -f name=repo')" "1" "(6) the PR listing names origin's repository"
eq "$(grep '^api repos/' "$TMP/gh.log" | grep -vc '^api repos/ours/repo/')" "0" "(7) every stream read names origin's repository"
hasnt "$(cat "$W/sweep.jsonl")" '"pr":99' "(8) upstream's PR is never read"
eq "$(grep -c '^api repos/ours/repo/[a-z]*/14/' "$TMP/gh.log" || true)" "3" "(8a) a PR that closed before every window is read when it was updated since"
eq "$(grep -c '^api repos/ours/repo/[a-z]*/13/' "$TMP/gh.log" || true)" "0" "(8b) and a PR last updated before the back-fill's start is never read"

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
eq "$(class_of "$(key 11 comment 302)")" "notice" "(22) a deploy notice opening with a prefix the rig declares is a notice"
eq "$(class_of "$(key 11 comment 305)")" "outside" "(22a) an app account's conversation comment that only carries that prefix past its start is outside"
eq "$(class_of "$(key 11 comment 306)")" "notice" "(22b) an app account's comment opening with the no-review mark is a notice"
eq "$(class_of "$(key 11 review 109)")" "notice" "(22c) so is a person's review body opening with it"
eq "$(class_of "$(key 11 comment 204)")" "notice" "(22d) and a person's inline comment opening with it"
eq "$(class_of "$(key 11 review 107)")" "" "(23) an approval with no body is not read"
eq "$(class_of "$(key 11 comment 303)")" "" "(24) a whitespace-only comment is not read"
eq "$(class_of "$(key 12 comment 401)")" "outside" "(25) a back-fill PR's outside comment is read"
eq "$(field_of "$(key 12 comment 401)" in_window)" "false" "(26) a back-fill PR is outside the standing window"
eq "$(field_of "$(key 11 comment 201)" in_window)" "true" "(27) a recent PR is inside the standing window"
eq "$(field_of "$(key 11 comment 201)" at)" "$(json_get "$(grep '^{"id":101,' "$FIX/11.reviews.jsonl")" submitted_at)" \
   "(28) an inline comment is dated by the submission of the review that carries it"
eq "$(field_of "$(key 11 comment 202)" reply_to)" "201" "(29) a reply records the comment it answers"

echo "── show ──"
eq "$("$SUT" show --dir "$W" --outside --limit 2 | grep -c '^--- ')" "2" "(34) --limit caps how many are shown"
# The rest of the section reads as a run whose first show call comes next.
: > "$W/shown.tsv"
OUT=$("$SUT" show --dir "$W" --outside --limit 50)
has "$OUT" "== 9 of 9 unrecorded outside post(s) not yet shown whole ==" "(30) show --outside counts the unrecorded outside posts"
hasnt "$OUT" "$(key 11 review 102)" "(31) show --outside leaves the city's posts out"
hasnt "$OUT" "$(key 11 comment 302)" "(32) show --outside leaves notices out"
has "$OUT" "--- $(key 11 comment 305)" "(32a) and shows an app account's conversation comment that is not a deploy notice"
eq "$(printf '%s\n' "$OUT" | grep '^--- ' | head -1)" "--- $(key 11 comment 304)" "(33) the newest outside post is shown first"
OUT=$("$SUT" show --dir "$W" --city)
has "$OUT" "$(key 11 review 104)" "(35) show --city lists the city's posts in the standing window"
hasnt "$OUT" "$(key 12 review 402)" "(36) show --city leaves out a back-fill PR's city post"
has "$OUT" "[FLAGGED: unmarked]" "(37) a flagged post is labelled"

echo "── file: the outside capture ──"
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 review 101)", "statement": "The reviewer asks for the function to be split because it does three things.", "directive": "diff"}
{"key": "$(key 11 comment 201)", "statement": "The loop never ends on empty input.", "directive": "diff", "context": "The PR added the loop."}
{"key": "$(key 11 review 108)", "statement": "A long review.", "directive": "standing", "correction": "keep-reviews-short"}
ROWS_EOF
); RC=$?
eq "$RC" "0" "(38) filing outside rows exits 0"
has "$OUT" "filed 3, skipped 0" "(39) all three are filed"
OBS=$(obs_of "$(key 11 comment 201)")
eq "$(meta "$OBS" obs.category)" "outside-review" "(40) the outside capture files under outside-review"
eq "$(meta "$OBS" obs.source)" "miner" "(41) its source is the miner"
eq "$(meta "$OBS" task_kind)" "observation" "(42) it is an observation"
eq "$(bstatus "$OBS")" "closed" "(43) it is closed at creation"
eq "$(labels_of "$OBS")" "learning,observation" "(44) it carries both labels"
eq "$(meta "$OBS" obs.scope)" "repo:fixture-rig" "(45) its scope defaults to the rig"
eq "$(bfield "$OBS" title)" "obs: The loop never ends on empty input. (pr:ours/repo#11)" "(46) its title is the statement and the PR"
BODY=$(bfield "$OBS" description)
has "$BODY" "## Statement
The loop never ends on empty input." "(47) the body opens with the statement"
has "$BODY" "> This loop never terminates on empty input.
— johnzook, https://github.com/ours/repo/pull/11#discussion_r201" "(48) the quote carries its author and link"
has "$BODY" "PR #11, \"Fix the frobnicator\": an inline comment on \`lib/frob.sh\`, line 7. The PR added the loop." \
    "(49) the context names the PR, the locus and the row's context"
hasnt "$BODY" "## Proposed norm" "(50) the outside capture proposes no norm"
LONG_BODY=$(bfield "$(obs_of "$(key 11 review 108)")" description)
has "$LONG_BODY" " …
— johnzook" "(51) a long quote is cut, and the link carries the rest"
eq "$(meta "$(obs_of "$(key 11 review 108)")" obs.directive)" \
   "standing" "(52) the row's directive is kept"
eq "$(meta "$(obs_of "$(key 11 review 108)")" obs.correction)" \
   "keep-reviews-short" "(52a) a row's correction is filed as obs.correction"
eq "$(meta "$(obs_of "$(key 11 review 108)")" obs.category)" \
   "outside-review" "(52b) under the outside capture's category still"
eq "$(meta "$OBS" obs.correction)" "<absent>" "(52c) and a row with no correction files none"

CREATES=$(grep -c '^bd create' "$TMP/gc.log")
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 comment 201)", "statement": "Captured again.", "directive": "diff"}
ROWS_EOF
)
has "$OUT" "already recorded under outside-review" "(53) a post already recorded is skipped"
eq "$(grep -c '^bd create' "$TMP/gc.log")" "$CREATES" "(54) and nothing is created for it"
OUT=$("$SUT" show --dir "$W" --outside --limit 50)
has "$OUT" "== 0 of 0 unrecorded outside post(s) not yet shown whole ==" "(55) show --outside prints no post an earlier call printed whole"
has "$OUT" "== 6 outside post(s) an earlier call showed whole are not recorded yet; file each from what that call printed: " \
    "(55a) and names the ones not recorded yet"
hasnt "$OUT" "$(key 11 comment 201)" "(55b) leaving out what this run filed"
has "$OUT" "== corrections outside posts already name, to reuse when one fits: keep-reviews-short (1) ==" \
    "(55c) and it lists the corrections this run's outside posts named"

OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 comment 304)", "statement": "Asks for a demo video.", "directive": "diff"}
{"key": "$(key 11 comment 304)", "statement": "Asks for a demo video again.", "directive": "diff"}
ROWS_EOF
)
has "$OUT" "already filed under outside-review by an earlier row of this call" "(56) a second row on one post in one call is skipped"
eq "$(obs_n "$(key 11 comment 304)")" "1" \
   "(57) one observation per outside post"
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 comment 305)", "statement": "The query interpolates the user's input into SQL; bind it as a parameter.", "directive": "diff"}
ROWS_EOF
)
has "$OUT" "filed 1, skipped 0" "(57a) an app account's conversation comment that is not a deploy notice is filed"

echo "── file: refused rows ──"
# This call runs in a shell whose GC_RIG names another rig.
OUT=$(rigs_on; GC_RIG=another-rig "$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "pr:ours/repo#11:comment:999", "statement": "No such post."}
{"key": "$(key 11 comment 302)", "statement": "A deploy preview."}
{"key": "$(key 11 review 105)", "statement": ""}
{"key": "$(key 11 review 105)", "statement": "Copilot flags a null dereference.", "directive": "loud"}
not json
{"key": "$(key 11 review 105)", "statement": "Copilot flags a possible null dereference."}
{"key": "$(key 11 comment 203)", "statement": "The guard reads the wrong variable.", "correction": "Read The Right Variable"}
{"key": "$(key 11 comment 203)", "statement": "The guard reads the wrong variable.", "correction": "outside-review"}
{"key": "$(key 11 review 104)", "statement": "A point.", "category": "a-point", "norm": "N.", "correction": "a-point"}
ROWS_EOF
); RC=$?
eq "$RC" "1" "(58) a call with refused rows exits 1"
has "$OUT" "no swept post has this key" "(59) an unknown key is refused"
has "$OUT" "a notice is not review feedback" "(60) a notice is refused"
has "$OUT" "the row has no statement" "(61) an empty statement is refused"
has "$OUT" "directive must be standing or diff" "(62) a bad directive is refused"
has "$OUT" "row is not a JSON object" "(63) a line that is not JSON is refused"
has "$OUT" "correction must be a lowercase slug" "(63a) a correction that is not a slug is refused"
has "$OUT" "correction names the standing correction the post makes, not outside-review" "(63b) as is outside-review as a correction"
has "$OUT" "a city post names its correction in its category; leave correction out" "(63c) and a correction on a city post"
has "$OUT" "filed 1," "(64) the valid row in the same call is still filed"
eq "$(rig_of 'list -l observation')" "fixture-rig" "(64a) file dedups against the swept rig's store, whatever GC_RIG its shell carries"
eq "$(rig_of 'bd create')" "fixture-rig" "(64b) and files the observation there"

echo "── file: the standing-behavior capture on the city's posts ──"
OUT=$("$SUT" file --dir "$W" --max-standing 1 <<ROWS_EOF 2>&1
{"key": "$(key 11 review 104)", "statement": "Verdicts should name the commit.", "category": "verdict-names-commit", "norm": "Name the reviewed commit in every verdict.", "directive": "diff"}
{"key": "$(key 11 comment 301)", "statement": "A second standing point.", "category": "second-point", "norm": "Do the second thing."}
ROWS_EOF
)
has "$OUT" "dropped for the 1-per-run standing cap" "(65) --max-standing drops the row past the cap"
STD=$(obs_of "$(key 11 review 104)")
eq "$(meta "$STD" obs.category)" "verdict-names-commit" "(66) a standing capture files under its own category"
has "$(bfield "$STD" description)" "## Proposed norm
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

echo "── advance: the outside capture's day moves to what the run still owes ──"
OUT=$("$SUT" advance --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(70a) advance exits 0 while the capture is unfinished"
has "$OUT" "moves to $(updated_on 12): 2 PR(s) still owe a read (#11, #12): 0 did not read, and 3 outside post(s) are not recorded yet" \
    "(70b) it says what the run still owes"
eq "$(kv_day)" "$(updated_on 12)" "(70c) and moves the day to the oldest last update among the PRs it owes, past the back-fill PRs it finished"
"$SUT" file --dir "$W" >/dev/null 2>&1 <<ROWS_EOF
{"key": "$(key 11 review 103)", "statement": "Two findings, the first of which blocks.", "directive": "diff"}
{"key": "$(key 11 comment 203)", "statement": "The guard reads the wrong variable.", "directive": "diff"}
{"key": "$(key 12 comment 401)", "statement": "Old feedback from last week.", "directive": "diff"}
ROWS_EOF
OUT=$(rigs_on; GC_RIG=another-rig "$SUT" advance --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(70d) advance exits 0 once every outside post is recorded"
has "$OUT" "moves to $(day 0): every PR the sweep listed read, and the store records every outside post it found" "(70e) and moves the day to the sweep's"
eq "$(kv_day)" "$(day 0)" "(70f) the store holds the new day"
eq "$(rig_of 'bd kv')" "fixture-rig" "(70g) in the swept rig's store"
kv_put "$(day -1)"
OUT=$("$SUT" advance --dir "$W" 2>&1)
has "$OUT" "so something moved it after the sweep and this run leaves it" "(70h) a day that moved after the sweep read it is left alone"
eq "$(kv_day)" "$(day -1)" "(70i) as it stands"
kv_put "$(day 0)"

echo "── flag: the real patrol-finding.sh files the finding ──"
OUT=$(rigs_on; "$SUT" flag --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(71) flag exits 0"
eq "$(findings_n)" "1" "(71a) it files one finding"
eq "$(meta "$(finding 1)" finding.key)" "unmarked-city-post" "(72) the finding is keyed on the situation"
eq "$(meta "$(finding 1)" finding.scope)" "miner-findings" "(73) it is filed in the miner's scope"
has "$(bfield "$(finding 1)" description)" "- https://github.com/ours/repo/pull/11#pullrequestreview-104 (posted" "(74) it names the flagged post"
hasnt "$(bfield "$(finding 1)" description)" "#issuecomment-301" "(75) it leaves out the post from before the cutover"
eq "$(rig_of 'bd create')" "fixture-rig" "(76) it lands in the swept rig's store"
eq "$(post_record "$(key 11 review 104)")" "named in $(finding 1)" "(76d) the store records the post with the finding that names it"
has "$(cat "$TMP/proactive.log" 2>/dev/null)" "sling $(finding 1)" "(76e) the finding goes to its first reaction"
has "$OUT" "named 1 unmarked city post(s) in $(finding 1)" "(76f) flag says where it named the post"

echo "── sweep, a paged listing stops at the first PR updated before the window ──"
fresh_dir p
STUB_PAGE=1 "$SUT" sweep --checkout "$CO" --days 30 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(grep -c '^api graphql' "$TMP/gh.log")" "4" "(76a) the 30-day listing pages until a PR updated before the window"
eq "$(class_of "$(key 12 comment 401)")" "outside" "(76b) and reads the window's PRs on every page"
fresh_dir q
STUB_PAGE=1 "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
eq "$(grep -c '^api graphql' "$TMP/gh.log")" "3" "(76c) a 3-day listing stops at PR 12, ten days old, and never asks for PR 13"

echo "── sweep, a back-fill cut short and resumed four days later ──"
# The first run, four days ago, recorded its start, filed outside posts and
# stopped before PR 12's. Every observation it filed is four days old, older
# than the window.
fresh_dir r
kv_put "$(day 34)"
cp "$STUB_STORE" "$TMP/store.keep"
OLD=$(ago 4)
for id in $(bids metadata.task_kind=observation); do
  if [ "$(meta "$id" obs.provenance)" = "$(key 12 comment 401)" ]; then bset "$id" metadata.task_kind=retired
  else bset "$id" "created_at=$OLD"; fi
done
OUT=$("$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1)
has "$OUT" "still owes a read of every PR updated since $(day 34), so the sweep reads back to then" \
    "(77a) a resumed back-fill reads back to its recorded start, however old its observations"
eq "$(field_of "$(key 12 comment 401)" captured)" "false" "(77b) so the ten-day-old PR's unrecorded post is read again"
OUT=$("$SUT" advance --dir "$W" 2>&1)
has "$OUT" "moves to $(updated_on 12): 1 PR(s) still owe a read (#12): 0 did not read, and 1 outside post(s) are not recorded yet" \
    "(77c) and the day keeps that PR in reach until its post is recorded"
eq "$(kv_day)" "$(updated_on 12)" "(77d) the store holds the day that PR was last updated"
cp "$TMP/store.keep" "$STUB_STORE"
OUT=$("$SUT" advance --dir "$W" 2>&1)
has "$OUT" "moves to $(day 0): every PR the sweep listed read" "(77e) once the store records it, the day moves to the sweep's"

echo "── sweep, a later run: the outside capture's day is the last finished run's ──"
fresh_dir b
OUT=$("$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1)
hasnt "$OUT" "so the sweep reads back to then" "(78) a sweep after a finished run reads the standing window"
eq "$(class_of "$(key 12 comment 401)")" "" "(79) the back-fill PR is out of the window"
eq "$(field_of "$(key 11 comment 201)" captured)" "true" "(80) a post recorded by an earlier run reads as captured"
has "$("$SUT" show --dir "$W" --city)" "already recorded on this post: new-" "(81) show names what is already recorded on a post"
has "$("$SUT" show --dir "$W" --outside)" "== corrections outside posts already name, to reuse when one fits: keep-reviews-short (1) ==" \
    "(81a) a later run's show lists the corrections the store records"
OUT=$(rigs_on; GC_RIG=another-rig "$SUT" flag --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(82) a flag whose posts a finding already names exits 0"
has "$OUT" "already named in a finding under unmarked-city-post" "(82a) and says so"
eq "$(meta "$(finding 1)" finding.occurrences)" "1" "(82b) a post the store records as named is not raised again"
eq "$(rig_of 'bd kv')" "fixture-rig" "(82c) the record is read in the swept rig's store"
set_status closed
"$SUT" flag --dir "$W" >/dev/null 2>&1
eq "$(findings_n)" "1" "(82d) nor once its finding is closed, where a raise would file a recurrence of it"
STUB_KV_FAIL=1 "$SUT" flag --dir "$W" >/dev/null 2>&1; RC=$?
eq "$RC" "1" "(82e) a record that does not read stops the flag"
eq "$(findings_n)" "1" "(82f) and it raises nothing"
# A new unmarked post: review 10, whose link is a prefix of review 104's.
cp "$FIX/11.reviews.jsonl" "$FIX/11.reviews.keep"
add_review 10 "Another notice a city writer posted without the mark."
fresh_dir n
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
"$SUT" flag --dir "$W" >/dev/null 2>&1
eq "$(findings_n)" "2" "(82g) a post no finding names yet is raised, though its link is a prefix of a named one"
has "$(bfield "$(finding 2)" description)" "- https://github.com/ours/repo/pull/11#pullrequestreview-10 (posted" "(82g2) the new finding names it"
hasnt "$(bfield "$(finding 2)" description)" "pullrequestreview-104" "(82h) and only it"
eq "$(meta "$(finding 2)" finding.recurrence_of)" "$(finding 1)" \
   "(82h2) a post first flagged after the finding closed files a new one that names the closed one"

echo "── flag: a post flagged while its finding is open joins that finding, once ──"
# The second finding is open. Review 9 is posted while it is.
add_review 9 "A third notice a city writer posted without the mark."
fresh_dir s
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
OUT=$("$SUT" flag --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(82s1) a raise while the finding is open exits 0"
eq "$(findings_n)" "2" "(82s2) it files no new finding"
eq "$(meta "$(finding 2)" finding.occurrences)" "2" "(82s3) the finding writer counts it on the open finding"
has "$(notes "$(finding 2)")" "- https://github.com/ours/repo/pull/11#pullrequestreview-9 (posted" \
    "(82s4) whose notes name the new post whole, past the 200 characters the writer notes"
hasnt "$(notes "$(finding 2)")" "#pullrequestreview-10 (posted" "(82s5) and only the new post"
eq "$(post_record "$(key 11 review 9)")" "named in $(finding 2)" "(82s6) the store records it with the open finding"
has "$OUT" "named 1 unmarked city post(s) in $(finding 2)" "(82s7) flag says where it named the post"
OUT=$("$SUT" flag --dir "$W" 2>&1)
has "$OUT" "already named in a finding under unmarked-city-post" "(82s8) the same scan again raises nothing"
eq "$(meta "$(finding 2)" finding.occurrences)" "2" "(82s9) so the open finding counts no third occurrence"
set_status closed
"$SUT" flag --dir "$W" >/dev/null 2>&1
eq "$(findings_n)" "2" "(82s10) and once it closes, no new finding is filed as its recurrence"
# The rest of the section raises onto the second finding, open again.
set_status open 2
# A note that does not land records nothing, so the next run names the post.
add_review 8 "A fourth notice."
fresh_dir s2
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
OUT=$(STUB_UPDATE_FAIL_ON="more unmarked city post(s)" "$SUT" flag --dir "$W" 2>&1); RC=$?
eq "$RC" "1" "(82s11) a raise whose note does not land exits 1"
eq "$(post_record "$(key 11 review 8)")" "" "(82s12) and records nothing"
"$SUT" flag --dir "$W" >/dev/null 2>&1
has "$(notes "$(finding 2)")" "- https://github.com/ours/repo/pull/11#pullrequestreview-8 (posted" "(82s13) the next run names the post"
eq "$(post_record "$(key 11 review 8)")" "named in $(finding 2)" "(82s14) and records it"
# A record that does not land leaves the post to the next run, not lost.
add_review 7 "A fifth notice."
fresh_dir s3
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
OUT=$(STUB_FAIL_ON="kv set" "$SUT" flag --dir "$W" 2>&1); RC=$?
eq "$RC" "1" "(82s15) a raise whose record does not land exits 1"
has "$OUT" "the store refused the record of them, so the next run raises them again" "(82s16) and says so"
"$SUT" flag --dir "$W" >/dev/null 2>&1
eq "$(post_record "$(key 11 review 7)")" "named in $(finding 2)" "(82s17) the next run records it"
# Findings that do not read stop a raise before it starts.
add_review 6 "A sixth notice."
fresh_dir s4
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
OCC=$(meta "$(finding 2)" finding.occurrences)
OUT=$(STUB_LIST_FAIL_ON=finding.key= "$SUT" flag --dir "$W" 2>&1); RC=$?
eq "$RC" "1" "(82s18) findings that do not read stop the flag"
eq "$(meta "$(finding 2)" finding.occurrences)" "$OCC" "(82s19) before anything is raised"
eq "$(post_record "$(key 11 review 6)")" "" "(82s20) or recorded"
# A finding held at blocked with nothing open to wait on takes no raise: the
# writer files a new finding beside it, and the flag names the post there.
set_status blocked 2
OUT=$("$SUT" flag --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(82s21) a raise beside a finding held at blocked exits 0"
eq "$(meta "$(finding 3)" finding.recurrence_of)" "$(finding 2)" "(82s22) the writer files a new finding beside the held one"
has "$(bfield "$(finding 3)" description)" "- https://github.com/ours/repo/pull/11#pullrequestreview-6 (posted" "(82s23) which names the post"
hasnt "$(notes "$(finding 2)")" "#pullrequestreview-6 (posted" "(82s24) and the held finding's notes do not"
eq "$(post_record "$(key 11 review 6)")" "named in $(finding 3)" "(82s25) the store records the post with the new finding"
mv "$FIX/11.reviews.keep" "$FIX/11.reviews.jsonl"

echo "── flag: one raise names every new post, however many ──"
set_status closed
cp "$FIX/prs.ours.jsonl" "$FIX/prs.ours.keep"
R=$(ago_h 1); pr_node 16 "A busy writer" "$R" "$R" "$R" >> "$FIX/prs.ours.jsonl"
anchor tk-anchor16 16
for i in $(seq 1 25); do review $((600 + i)) city-bot User COMMENTED "Unmarked notice $i." "$(ago_h 1)"; done > "$FIX/16.reviews.jsonl"
: > "$FIX/16.inline.jsonl"; : > "$FIX/16.issue.jsonl"
fresh_dir t
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
OUT=$("$SUT" flag --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(82t1) a raise of 25 posts exits 0"
eq "$(bfield "$(finding 4)" description | grep -c '^- https://github.com/ours/repo/pull/11#pullrequestreview-6[0-9][0-9] (posted')" "25" \
   "(82t2) the new finding names all 25"
eq "$(grep -c '^feedback_miner\.unmarked_post\.pr_ours_repo_16_' "$STUB_KV")" "25" \
   "(82t3) and the store records all 25"
mv "$FIX/prs.ours.keep" "$FIX/prs.ours.jsonl"; bunset tk-anchor16 metadata.pr_provenance_since
rm -f "$FIX/16.reviews.jsonl" "$FIX/16.inline.jsonl" "$FIX/16.issue.jsonl"

echo "── the /code-review signature: its footer or its heading, in the post's own body ──"
# PR 17's posts are all unmarked, under the city's login, and after the PR's
# cutover. Reviews 703 to 706 have empty bodies: each carries one standalone
# inline comment, the way `gh api .../pulls/<n>/comments` posts one.
cp "$FIX/prs.ours.jsonl" "$FIX/prs.ours.keep"
R=$(ago_h 1); pr_node 17 "Signatures" "$R" "$R" "$R" >> "$FIX/prs.ours.jsonl"
anchor tk-anchor17 17
{
  review 701 city-bot User COMMENTED "Code review gates: correctness PASS, arch PASS." "$(ago_h 1)"
  review 702 city-bot User COMMENTED "### Code review

Found 1 issue:

1. The loop never ends on empty input.

🤖 Generated with [Claude Code](https://claude.ai/code)" "$(ago_h 1)"
  for r in 703 704 705 706; do review "$r" city-bot User COMMENTED "" "$(ago_h 1)"; done
} > "$FIX/17.reviews.jsonl"
{
  inline 801 city-bot 703 "**Must fix: the guard reads the wrong variable.**

---
_Generated by [Claude Code](https://claude.ai/code)_" "$(ago_h 1)"
  inline 802 city-bot 704 "Validated — no change needed. Claude Code has three skill-invocation paths." "$(ago_h 1)"
  inline 803 city-bot 705 "Fixed in abc1234. The comment it answers ended:
> _Generated by [Claude Code](https://claude.ai/code)_" "$(ago_h 1)"
  inline 804 city-bot 706 "Code review: 1 finding. The cache is never cleared." "$(ago_h 1)"
} > "$FIX/17.inline.jsonl"
issue 811 city-bot User "One more point on the latest head: the retry has no backoff.

_Generated by [Claude Code](https://claude.ai/code)_" "$(ago_h 1)" 17 > "$FIX/17.issue.jsonl"
fresh_dir sig
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(class_of "$(key 17 comment 801)")" "outside" "(82u1) a standalone inline comment signed by its own footer is outside"
eq "$(field_of "$(key 17 comment 801)" flag)" "false" "(82u2) and is not flagged"
eq "$(class_of "$(key 17 comment 811)")" "outside" "(82u3) so is a conversation comment signed by its own footer"
eq "$(class_of "$(key 17 comment 804)")" "outside" "(82u4) and a standalone inline comment that opens as a code review"
eq "$(class_of "$(key 17 review 702)")" "outside" "(82u5) a review with /code-review's heading and footer is outside"
eq "$(class_of "$(key 17 review 701)")" "city" "(82u6) a city post that opens with the words code review but not as one is the city's"
eq "$(field_of "$(key 17 review 701)" flag)" "true" "(82u7) so it is flagged when it lacks the mark"
eq "$(class_of "$(key 17 comment 802)")" "city" "(82u8) a city post whose first line only mentions Claude Code is the city's"
eq "$(class_of "$(key 17 comment 803)")" "city" "(82u9) and a city post quoting the footer is not signed by it"
mv "$FIX/prs.ours.keep" "$FIX/prs.ours.jsonl"; bunset tk-anchor17 metadata.pr_provenance_since
rm -f "$FIX/17.reviews.jsonl" "$FIX/17.inline.jsonl" "$FIX/17.issue.jsonl"

echo "── sweep, an outside capture day that is not a date, or does not read ──"
fresh_dir g
kv_put "not a date"
OUT=$("$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1); RC=$?
eq "$RC" "0" "(82i) a recorded day that is not a date does not stop the sweep"
has "$OUT" "which is not a date, so the capture starts again" "(82j) it says the capture starts again"
eq "$(kv_day)" "$(day 30)" "(82k) and records the back-fill's start"
fresh_dir g2
OUT=$(STUB_KV_FAIL=1 "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1); RC=$?
eq "$RC" "1" "(82l) a day that does not read stops the sweep"
has "$OUT" "did not read, so which PRs the capture owes is unknown" "(82m) and says why"
eq "$(grep -c '^api graphql' "$TMP/gh.log")" "0" "(82n) before it lists a PR"
fresh_dir g3
: > "$STUB_KV"
STUB_FAIL_ON="kv set" "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1; RC=$?
eq "$RC" "1" "(82o) a first run that cannot record its start stops"
eq "$(grep -c '^api graphql' "$TMP/gh.log")" "0" "(82p) before it lists a PR"
kv_put "$(day 0)"

echo "── sweep, failures ──"
fresh_dir c
: > "$FIX/11.fail"
kv_put "$(day 30)"
OUT=$("$SUT" sweep --checkout "$CO" --days 30 --backfill-days 30 --dir "$W" 2>&1); RC=$?
rm -f "$FIX/11.fail"
eq "$RC" "0" "(83) a PR that does not read does not stop the sweep"
has "$OUT" "did not read, left for the next run: 11" "(84) the PR that did not read is named"
eq "$(class_of "$(key 12 comment 401)")" "outside" "(85) the other PRs are still swept"
OUT=$("$SUT" advance --dir "$W" 2>&1)
has "$OUT" "moves to $(updated_on 11): 1 PR(s) still owe a read (#11): 1 did not read, and 0 outside post(s) are not recorded yet" \
    "(85f) a PR that did not read holds the day at its last update"
eq "$(kv_day)" "$(updated_on 11)" "(85g) so the next run reads it again"
: > "$TMP/gh.log"
"$SUT" sweep --checkout "$CO" --days 30 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(class_of "$(key 11 comment 201)")" "outside" "(85a) a sweep re-run into the same dir reads the PR it missed"
eq "$(grep -c '^api repos/ours/repo/issues/12/' "$TMP/gh.log" || true)" "0" "(85b) and keeps the PRs it already read"
"$SUT" advance --dir "$W" >/dev/null 2>&1
eq "$(kv_day)" "$(day 0)" "(85h) once the PR has read and its posts are recorded, the day is the sweep's"
fresh_dir k
OUT=$(PATH="$KILLBIN:$PATH" STUB_KILL_PR=11 "$SUT" sweep --checkout "$CO" --days 30 --backfill-days 30 --dir "$W" --jobs 1 2>&1)
has "$OUT" "did not read, left for the next run: 11" "(85c) a worker killed while it writes a PR's posts leaves that PR unread"
"$SUT" sweep --checkout "$CO" --days 30 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(class_of "$(key 11 review 101)")" "outside" "(85d) so a resumed sweep into the same dir reads it again"
# A whole line is one post: it opens with the post's key, closes its object,
# and opens no second post, as a cut line joined to the next line does. A last
# line with no newline is read too.
WHOLE=0
while IFS= read -r l || [ -n "$l" ]; do
  case "$l" in '{"key":"'*'}') ;; *) WHOLE=1 ;; esac
  case "${l#\{}" in *'{"key":'*) WHOLE=1 ;; esac
done < "$W/sweep.jsonl"
eq "$WHOLE" "0" "(85e) and every line of the resumed sweep is one whole post"
# A sweep cut short before it finished writes no read.txt.
rm -f "$W/read.txt"
kv_put "$(day 30)"
OUT=$("$SUT" advance --dir "$W" 2>&1); RC=$?
eq "$RC" "1" "(85i) advance after a sweep that did not finish exits 1"
has "$OUT" "the sweep in $W did not finish, so the outside capture stays at" "(85i2) and says the sweep did not finish"
eq "$(kv_day)" "$(day 30)" "(85j) and keeps the day"
# A sweep removes read.txt before anything that can stop it. Otherwise one
# that stops partway in a dir where an earlier sweep finished would leave that
# sweep's list for advance to read beside its own partial posts.
fresh_dir u
read_list() { [ -f "$W/read.txt" ] && echo written || echo none; }
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(read_list)" "written" "(85m) a sweep that finishes writes read.txt"
STUB_KV_FAIL=1 "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(read_list)" "none" "(85n) a sweep that stops partway in the same dir removes it"
"$SUT" advance --dir "$W" >/dev/null 2>&1; eq "$?" "1" "(85o) so advance refuses to move the day"
eq "$(kv_day)" "$(day 30)" "(85p) which stays where it was"
# PR 12 was last updated before the recorded day, and a 30-day window still
# lists it.
# When it does not read, the day moves back to its last update, so a run whose
# standing window has passed it still reads it.
fresh_dir o
kv_put "$(day 5)"
: > "$FIX/12.fail"
"$SUT" sweep --checkout "$CO" --days 30 --backfill-days 30 --dir "$W" >/dev/null 2>&1
rm -f "$FIX/12.fail"
OUT=$("$SUT" advance --dir "$W" 2>&1)
has "$OUT" "moves to $(updated_on 12): 1 PR(s) still owe a read (#12): 1 did not read" "(85k) a PR the day had passed that did not read moves the day back to its last update"
fresh_dir o2
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(class_of "$(key 12 comment 401)")" "outside" "(85l) so a later run with a 3-day window reads it again"
# A PR's posts that do not copy into the sweep whole stop the sweep with no
# read.txt, so advance cannot move the day past that PR. The cat stand-in fails
# on PR 12's posts, the ten-day-old PR only the back-fill reads.
fresh_dir catfail
kv_put "$(day 30)"
OUT=$(PATH="$FAULTBIN:$PATH" STUB_CAT_FAIL=/prs/12.jsonl "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1); RC=$?
eq "$RC" "1" "(85q) a PR's posts that do not copy into the sweep stop the sweep"
has "$OUT" "could not add PR #12's posts to the sweep" "(85r) and it names the PR"
eq "$(read_list)" "none" "(85s) with no read.txt"
eq "$([ -f "$W/sweep.jsonl" ] && echo published || echo none)" "none" "(85t) and no sweep.jsonl for show or file to read"
"$SUT" advance --dir "$W" >/dev/null 2>&1; eq "$?" "1" "(85u) so advance refuses to move the day"
eq "$(kv_day)" "$(day 30)" "(85v) which stays before PR 12's last update"
# A PR list that does not write whole stops the sweep before it reads a PR.
fresh_dir listfail
OUT=$(PATH="$FAULTBIN:$PATH" STUB_JQ_LIST_FAIL=1 "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1); RC=$?
eq "$RC" "1" "(85w) a PR list that does not write whole stops the sweep"
has "$OUT" "could not list the PRs to read" "(85x) and says why"
eq "$(grep -c '^api repos/' "$TMP/gh.log" || true)|$(read_list)" "0|none" "(85y) before it reads a PR, with no read.txt"
# advance owes every PR the sweep listed that read.txt does not name, so a PR
# that leaves the sweep by any path holds the day at its last update.
fresh_dir held
kv_put "$(day 30)"
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
awk '$0 != "12"' "$W/read.txt" > "$W/read.next" && mv "$W/read.next" "$W/read.txt"
OUT=$("$SUT" advance --dir "$W" 2>&1)
has "$OUT" "moves to $(updated_on 12): 1 PR(s) still owe a read (#12): 1 did not read, and 0 outside post(s) are not recorded yet" \
    "(85z) a listed PR that read.txt does not name is owed"
eq "$(kv_day)" "$(updated_on 12)" "(85z2) so the day holds at its last update"
kv_put "$(day 0)"
fresh_dir d
OUT=$(STUB_LIST_FAIL_ON="-l observation" "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" 2>&1); RC=$?
eq "$RC" "1" "(86) an unreadable observation store stops the sweep"
has "$OUT" "nothing can be deduped" "(87) and says why"
eq "$(grep -c '^api graphql' "$TMP/gh.log")" "0" "(88) it lists no PR before it can dedup"

echo "── sweep, an outside post on a PR that closed before the capture day ──"
# PR 14 closed 40 days ago. The capture's day is five days back, past that
# close, and a comment two hours ago updated the PR.
issue 901 johnzook User "A late point on an old change." "$(ago_h 2)" 14 > "$FIX/14.issue.jsonl"
cp "$STUB_STORE" "$TMP/store.keep"
fresh_dir v
kv_put "$(day 5)"
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 30 --dir "$W" >/dev/null 2>&1
eq "$(class_of "$(key 14 comment 901)")" "outside" "(88a) the outside post is swept, though its PR closed before the capture day"
eq "$(field_of "$(key 14 comment 901)" in_window)" "false" "(88b) the PR's close is still outside the standing window"
OUT=$("$SUT" advance --dir "$W" 2>&1)
has "$OUT" "1 PR(s) still owe a read (#14): 0 did not read, and 1 outside post(s) are not recorded yet" "(88c) advance counts the PR as owed"
eq "$(kv_day)" "$(updated_on 14)" "(88d) and dates it by its last update, which the next run's listing reads back to"
"$SUT" show --dir "$W" --outside >/dev/null
"$SUT" file --dir "$W" >/dev/null 2>&1 <<ROWS_EOF
{"key": "$(key 14 comment 901)", "statement": "A late point on an old change."}
ROWS_EOF
OUT=$("$SUT" advance --dir "$W" 2>&1)
has "$OUT" "every PR the sweep listed read, and the store records every outside post it found" "(88e) once the post is recorded, the run owes nothing"
eq "$(kv_day)" "$(day 0)" "(88f) and the day is the sweep's"
rm -f "$FIX/14.issue.jsonl"
cp "$TMP/store.keep" "$STUB_STORE"
kv_put "$(day 0)"

echo "── summary ──"
fresh_dir e
obs_reset
: > "$STUB_KV"
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
"$SUT" show --dir "$W" --outside >/dev/null
"$SUT" file --dir "$W" >/dev/null 2>&1 <<ROWS_EOF
{"key": "$(key 11 comment 201)", "statement": "The loop never ends on empty input."}
ROWS_EOF
OUT=$("$SUT" summary --dir "$W")
has "$OUT" "outside capture from $(day 3)" "(89) with no back-fill window the first run reads the standing window"
has "$OUT" "outside posts: 8 read, 0 recorded before this run, 1 filed now, 7 left unrecorded" "(90) the summary counts the outside capture"

echo "── file: a post the store already records leaves show's list ──"
"$SUT" file --dir "$W" >/dev/null 2>&1 <<ROWS_EOF
{"key": "$(key 11 comment 201)", "statement": "Again."}
ROWS_EOF
has "$("$SUT" summary --dir "$W")" "outside posts: 8 read, 0 recorded before this run, 1 filed now, 7 left unrecorded" \
    "(90a) a post this run filed, filed again, is still counted once, as filed now"
# Another writer records review 101 after the sweep read the store.
store_obs() { # <id> <post key> <category>
  brow "$1" status=closed "title=obs: recorded elsewhere" 'labels:=["learning","observation"]' \
    "metadata:={\"task_kind\":\"observation\",\"obs.provenance\":$(json_str "$2"),\"obs.category\":$(json_str "$3")}"
}
store_obs tk-other1 "$(key 11 review 101)" outside-review
# Every outside post here was printed whole by the run's first show call, so a
# later call names the ones it reads as unrecorded at its end.
unfiled_line() { "$SUT" show --dir "$W" --outside --limit 50 | grep '^== .* an earlier call showed whole are not recorded yet'; }
has "$(unfiled_line)" "$(key 11 review 101)" "(90b) show names a post the store recorded after the sweep as not recorded yet"
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 review 101)", "statement": "Asks for the function to be split."}
ROWS_EOF
)
has "$OUT" "filed 0, skipped 1" "(90c) file skips it as already recorded"
hasnt "$("$SUT" show --dir "$W" --outside --limit 50)" "$(key 11 review 101)" "(90d) and show no longer names it"
has "$("$SUT" summary --dir "$W")" "outside posts: 8 read, 1 recorded before this run, 1 filed now, 6 left unrecorded" \
    "(90e) the summary counts it as recorded, not as filed now"
# A create whose observation landed but whose answer was lost.
OUT=$(STUB_CREATE_GARBAGE=1 "$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 review 105)", "statement": "Copilot found a possible null dereference."}
ROWS_EOF
); RC=$?
eq "$RC" "1" "(90f) a create that answers with no id fails the call"
has "$(unfiled_line)" "$(key 11 review 105)" "(90g) and show still names the post as not recorded yet"
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 11 review 105)", "statement": "Copilot found a possible null dereference."}
ROWS_EOF
)
has "$OUT" "filed 0, skipped 1" "(90h) the retry finds the observation the create left"
hasnt "$("$SUT" show --dir "$W" --outside --limit 50)" "$(key 11 review 105)" "(90i) and show no longer names the post"
# A city post the store records under its own category is not captured.
store_obs tk-other2 "$(key 11 review 104)" verdict-names-commit
"$SUT" file --dir "$W" >/dev/null 2>&1 <<ROWS_EOF
{"key": "$(key 11 review 104)", "statement": "Verdicts should name the commit.", "category": "verdict-names-commit", "norm": "Name the reviewed commit."}
ROWS_EOF
eq "$(field_of "$(key 11 review 104)" captured)" "false" "(90j) a city post skipped under its own category does not read as captured"
has "$("$SUT" show --dir "$W" --city)" "already recorded on this post: tk-other2" "(90k) and show names the record it skipped on"

echo "── show prints every post whole, and a long one in parts ──"
# PR 15 joins the fixture for this section: a review whose point sits past
# character 2,000, and a conversation comment longer than one call's budget.
cp "$FIX/prs.ours.jsonl" "$FIX/prs.ours.keep"
R=$(ago_h 1); pr_node 15 "A long review" "$R" "$R" "$R" >> "$FIX/prs.ours.jsonl"
TAIL_REVIEW="$(printf 'A sentence that fills the long review out. %.0s' $(seq 1 60))TAIL_FINDING: the retry loop never backs off."
HUGE="$(printf 'Paragraph %05d of the huge comment, padded out to sixty characters.\n' $(seq 1 600))LAST_POINT: drop the cache."
review 501 johnzook User COMMENTED "$TAIL_REVIEW" "$(ago_h 1)" > "$FIX/15.reviews.jsonl"
: > "$FIX/15.inline.jsonl"
issue 502 johnzook User "$HUGE" "$(ago 0)" 15 > "$FIX/15.issue.jsonl"
slice() { printf '%s' "${1:$2:$(( $3 - $2 ))}"; }
HUGE_LEN=${#HUGE}
fresh_dir l
obs_reset
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 15 review 501)", "statement": "Filed unread."}
ROWS_EOF
)
has "$OUT" "show has not printed this post in this run" "(91) file refuses a row on a post show never printed"
OUT1=$("$SUT" show --dir "$W" --outside)
has "$OUT1" "== 1 of 10 unrecorded outside post(s) not yet shown whole ==" "(92) a post longer than the budget is printed alone"
has "$OUT1" "[characters 1 to 16000 of $HUGE_LEN; the rest comes in the next show call" "(93) its first part is labelled with the characters it holds"
has "$OUT1" "$(slice "$HUGE" 0 16000)" "(94) and holds the first 16,000 characters"
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 15 comment 502)", "statement": "Half read."}
ROWS_EOF
)
has "$OUT" "show has printed this post only through character 16000 of $HUGE_LEN" "(95) file refuses a row on a post shown only in part"
OUT2=$("$SUT" show --dir "$W" --outside)
has "$OUT2" "--- $(key 15 comment 502)" "(96) the next call continues the unfinished post first"
has "$OUT2" "$(slice "$HUGE" 16000 32000)" "(97) with the next 16,000 characters"
OUT3=$("$SUT" show --dir "$W" --outside)
has "$OUT3" "[characters 32001 to $HUGE_LEN of $HUGE_LEN, its last part]" "(98) the last part is labelled as last"
has "$OUT3" "$(slice "$HUGE" 32000 "$HUGE_LEN")" "(99) and holds the rest, LAST_POINT included, so no character is lost between parts"
has "$OUT3" "TAIL_FINDING: the retry loop never backs off." "(100) a post past the old 2,000-character cut is printed to its end"
# The agent runs show again before it files the long post.
OUT4=$("$SUT" show --dir "$W" --outside)
hasnt "$OUT4" "--- $(key 15 comment 502)" "(100a) a long post printed whole is not printed again"
hasnt "$OUT4" "$(slice "$HUGE" 0 200)" "(100b) so its opening is not offered from character 0"
has "$(printf '%s\n' "$OUT4" | grep 'an earlier call showed whole are not recorded yet')" "$(key 15 comment 502)" \
    "(100c) show names it as printed whole and not recorded yet"
hasnt "$OUT4" "more after these: run show again" "(100d) and the posts left after it all fit in this one call"
# A post stands at the furthest position any call printed it to.
printf '%s\t%s\n' "$(key 15 comment 502)" 16000 >> "$W/shown.tsv"
OUT=$("$SUT" file --dir "$W" <<ROWS_EOF 2>&1
{"key": "$(key 15 comment 502)", "statement": "Asks to drop the cache, after a long walk through the paragraphs."}
{"key": "$(key 15 review 501)", "statement": "The retry loop never backs off."}
ROWS_EOF
); RC=$?
eq "$RC" "0" "(101) once each post was printed to its end, its row files, a later show call and a smaller position after it notwithstanding"
has "$OUT" "filed 2, skipped 0" "(102) both rows file"
# The city's posts: each call prints what no earlier call printed whole.
SEEN=""; CALLS=0
while [ "$CALLS" -lt 10 ]; do
  OUT=$("$SUT" show --dir "$W" --city --max-chars 70)
  CALLS=$((CALLS + 1))
  case "$OUT" in "== 0 of 0 "*) break ;; esac
  SEEN="$SEEN$(printf '%s\n' "$OUT" | sed -n 's/^--- //p')"$'\n'
done
eq "$(printf '%s' "$SEEN" | grep -c .)" "4" "(103) the --city calls print each of the window's 4 city posts"
eq "$(printf '%s' "$SEEN" | grep . | sort | uniq -d | grep -c . || true)" "0" "(104) and none of them twice"
if [ "$CALLS" -gt 2 ]; then ok "(105) a call stops before the post that would take it past --max-chars"
else bad "(105) a call stops before the post that would take it past --max-chars (took $CALLS call(s))"; fi
"$SUT" show --dir "$W" --outside --max-chars 0 >/dev/null 2>&1; eq "$?" "2" "(106) --max-chars must be a positive integer"
mv "$FIX/prs.ours.keep" "$FIX/prs.ours.jsonl"
rm -f "$FIX/15.reviews.jsonl" "$FIX/15.inline.jsonl" "$FIX/15.issue.jsonl"

echo "── show counts each correction once per observation ──"
fresh_dir z
obs_reset
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
"$SUT" show --dir "$W" --outside >/dev/null
"$SUT" file --dir "$W" >/dev/null 2>&1 <<ROWS_EOF
{"key": "$(key 11 comment 201)", "statement": "The loop never ends on empty input.", "correction": "guard-empty-input"}
{"key": "$(key 11 comment 304)", "statement": "Asks for a demo video.", "correction": "guard-empty-input"}
{"key": "$(key 11 review 101)", "statement": "Asks for the function to be split.", "correction": "split-long-functions"}
ROWS_EOF
NAMED="== corrections outside posts already name, to reuse when one fits: guard-empty-input (2), split-long-functions (1) =="
has "$("$SUT" show --dir "$W" --outside)" "$NAMED" "(107) show counts this run's corrections, most used first"
"$SUT" sweep --checkout "$CO" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
has "$("$SUT" show --dir "$W" --outside)" "$NAMED" "(108) and a sweep re-run into the run's dir, which reads them from the store too, counts each once"

echo "── what is not for review follows the swept rig's declaration ──"
fresh_dir nfr
UNDECLARED="$TMP/undeclared"
git init -q -b main "$UNDECLARED"
git -C "$UNDECLARED" remote add origin git@github.com:ours/repo.git
default_branch "$UNDECLARED"
"$SUT" sweep --checkout "$UNDECLARED" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
eq "$(class_of "$(key 11 comment 302)")" "notice" \
  "(109) on a rig that declares nothing, Vercel's deploy notice is still a notice, by the miner's own fallback"
eq "$(class_of "$(key 11 comment 305)")" "outside" "(109a) …while an app's comment that only mentions [vc]: past its first line is outside"
eq "$(class_of "$(key 11 comment 306)")" "notice" "(110) and a comment opening with the no-review mark is a notice on any rig"
fresh_dir nfr-other
OTHERDECL="$TMP/other-declaration"
git init -q -b main "$OTHERDECL"
git -C "$OTHERDECL" remote add origin git@github.com:ours/repo.git
printf '%s\n' '[[marker]]' 'prefix = "Schema diff:"' > "$OTHERDECL/not-for-review.toml"
git -C "$OTHERDECL" add not-for-review.toml
default_branch "$OTHERDECL"
"$SUT" sweep --checkout "$OTHERDECL" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
eq "$(class_of "$(key 11 comment 302)")" "outside" \
  "(110a) a rig that declares any prefix decides for itself, so a deploy notice it has not declared is outside"
fresh_dir nfr-root
GC_RIG_ROOT="$UNDECLARED" "$SUT" sweep --checkout "$CO" --days 3 --backfill-days 0 --dir "$W" >/dev/null 2>&1
eq "$(class_of "$(key 11 comment 302)")" "notice" \
  "(111) a session whose GC_RIG_ROOT names another rig still reads the swept checkout's declaration"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
