#!/usr/bin/env bash
# feedback-miner.sh — the mechanical half of formulas/mol-feedback-miner.toml:
# it reads the review conversations of a window's merged and closed pull
# requests, tells the city's own posts from feedback posted from outside the
# city, and files the observations the miner's agent condenses.
#
# Where a post comes from is decided in this order:
#   1. A post carrying the city's mark is the city's (gc_city_marked, from
#      `pr-post.sh own-def`, the one definition of the mark).
#   2. An unmarked post from any login other than the one gh posts as is
#      outside, except a GitHub App account's approval and its deploy notice,
#      which are notices, not review feedback. A deploy notice is told by what
#      it says: Vercel's opens with its "[vc]:" link-reference line. Any other
#      post an app makes, a conversation comment among them, is outside.
#   3. An unmarked post under the city's own login is outside when it is the
#      output of Claude Code's /code-review: a review whose body names itself a
#      code review or Claude Code in its first line, or carries the "Generated
#      with Claude Code" line, together with that review's inline comments.
#   4. Any other unmarked post under the city's login is the city's. One posted
#      after its PR's provenance cutover is flagged, because a city writer
#      posted it without the mark: the cutover is the anchor's
#      pr_provenance_since, from which gc_city_own counts an unmarked post under
#      the city's login as not the city's own.
#
# Every outside post becomes one observation, obs.category=outside-review,
# filed whether or not it is about standing behavior. The city's own posts in
# the standing window are the miner's standing-behavior capture, which files
# under a category the agent picks.
#
# The outside capture's progress outlives the run. The store's key-value table
# holds, for each repository, the day from which the capture still owes every
# PR closed. A rig's first sweep records the start of the back-fill window
# there. Every sweep reads the PRs closed since that day, or since the standing
# window's start when that is earlier. At the end of a run the day moves to the
# close of the oldest PR the run still owes, one that did not read or carries an
# outside post the store does not record, or to the sweep's own day when it owes
# none. So a back-fill, a PR that did not read, and a post left unfiled are all
# read again by the next run, however long after it comes.
#
# Usage:
#   feedback-miner.sh identity --checkout <dir>
#       Print `<owner/name><TAB><login>`: origin's repository and the login gh
#       posts as. A bare gh call picks the repository from `gh repo
#       set-default`, and with none set from the first remote in its own order,
#       which puts upstream ahead of origin, so the slug is resolved from
#       origin's URL.
#   feedback-miner.sh sweep --checkout <dir> --days <n> --backfill-days <n> --dir <work-dir> [--jobs <n>]
#       Read every PR merged or closed since the outside capture's day, or since
#       the standing window's start (--days back) when that is earlier, and
#       write one JSON line per non-empty post to <work-dir>/sweep.jsonl, with
#       its class (outside, city or notice), whether the standing window covers
#       it, the observations already recorded on it, and whether it is flagged.
#       A rig with no day recorded yet records --backfill-days back. The PRs are
#       read in --jobs parallel workers (default 8). A sweep re-run into the
#       same --dir keeps the PRs it already read, so one a tool call's time
#       limit cut short resumes.
#   feedback-miner.sh show --dir <work-dir> (--outside | --city) [--limit <n>] [--max-chars <n>]
#       Print posts for the agent to read, newest first and each one whole:
#       --outside the outside posts no observation records yet, --city the
#       city's posts in the standing window that no earlier call printed whole.
#       A call prints at most --limit posts (default 25), and stops before the
#       post that would take its bodies past --max-chars characters (default
#       16000). A post longer than that is printed in parts, one part a call,
#       each call going on where the last one stopped.
#   feedback-miner.sh file --dir <work-dir> [--max-standing <n>]
#       Read one JSON row per line on stdin and file an observation for each:
#         {"key": <provenance>, "statement": <text>, "directive": "standing|diff",
#          "context": <text, optional>, "scope": <obs.scope, optional>}
#       A row on an outside post files the outside capture. A row on a city post
#       is a standing-behavior capture and also needs "category" and "norm".
#       A row on a post that show has not printed whole in this --dir is
#       refused. --max-standing caps the standing-behavior captures this run
#       files.
#   feedback-miner.sh flag --dir <work-dir>
#       Name each flagged post once, on the patrol finding under its key: a
#       first raise files the finding, and a post flagged while it is live is
#       added to its notes. The store's key-value table records every post
#       named, with the finding that names it, and a recorded post is never
#       raised again.
#   feedback-miner.sh advance --dir <work-dir>
#       Move the outside capture's day to the close of the oldest PR the run
#       still owes, one that did not read or carries an outside post the store
#       does not record, or to the sweep's day when it owes none, and say why.
#   feedback-miner.sh summary --dir <work-dir>
#       Print what the sweep read and what this run filed.
#
# Exit: 0 done · 1 a read or write failed (the message says which) · 2 usage.
set -uo pipefail

PROG=feedback-miner
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME="$HERE/$(basename "${BASH_SOURCE[0]}")"
PR_POST="$HERE/pr-post.sh"
PATROL_FINDING="${GC_PATROL_FINDING_TOOL:-$HERE/patrol-finding.sh}"

# The outside capture's fixed category: one observation per outside post, so
# the pair the dedup reads, (obs.provenance, obs.category), is unique per post.
OUTSIDE_CATEGORY=outside-review
# A quote longer than this is cut, and the observation links the whole post.
QUOTE_MAX=1500

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$ME" | sed '$d' | sed 's/^# \{0,1\}//'; }
die_usage() { echo "$PROG: $1" >&2; usage >&2; exit 2; }
err() { echo "$PROG: $*" >&2; }
warn() { echo "$PROG: WARN $*" >&2; }

VERB="${1:-}"
case "$VERB" in
  identity|sweep|show|file|flag|advance|summary|fetch-pr) shift ;;
  -h|--help) usage; exit 0 ;;
  *) die_usage "first argument must be identity, sweep, show, file, flag, advance or summary" ;;
esac

CHECKOUT=""; DAYS=""; BACKFILL=""; DIR=""; JOBS=8; WHICH=""; LIMIT=25; MAX_CHARS=16000; MAX_STANDING=""
while [ $# -gt 0 ]; do
  case "$1" in
    --checkout)      [ $# -ge 2 ] || die_usage "--checkout needs a value"; CHECKOUT="$2"; shift 2 ;;
    --days)          [ $# -ge 2 ] || die_usage "--days needs a value"; DAYS="$2"; shift 2 ;;
    --backfill-days) [ $# -ge 2 ] || die_usage "--backfill-days needs a value"; BACKFILL="$2"; shift 2 ;;
    --dir)           [ $# -ge 2 ] || die_usage "--dir needs a value"; DIR="$2"; shift 2 ;;
    --jobs)          [ $# -ge 2 ] || die_usage "--jobs needs a value"; JOBS="$2"; shift 2 ;;
    --outside)       WHICH=outside; shift ;;
    --city)          WHICH=city; shift ;;
    --limit)         [ $# -ge 2 ] || die_usage "--limit needs a value"; LIMIT="$2"; shift 2 ;;
    --max-chars)     [ $# -ge 2 ] || die_usage "--max-chars needs a value"; MAX_CHARS="$2"; shift 2 ;;
    --max-standing)  [ $# -ge 2 ] || die_usage "--max-standing needs a value"; MAX_STANDING="$2"; shift 2 ;;
    --) shift; break ;;
    -*) die_usage "unknown argument '$1'" ;;
    *) break ;;
  esac
done

is_count() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; }
is_day() { case "${1:-}" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;; esac; return 1; }
day_start() { # <days-ago> -> YYYY-MM-DD, GNU/BSD-portable
  local e=$(( $(date -u +%s) - $1 * 86400 ))
  date -u -d "@$e" +%Y-%m-%d 2>/dev/null || date -u -r "$e" +%Y-%m-%d
}

# --- the store's key-value table -----------------------------------------------------
# The table of the store the observations are filed in holds the day from which
# the outside capture still owes every PR closed, one key per repository, and
# each unmarked city post the flag has named, one key per post, whose value
# names the finding that names it. A post's key is its provenance key with
# every character outside [A-Za-z0-9._-] turned into "_", after this prefix.
POST_KEY_PREFIX=feedback_miner.unmarked_post.
day_key() { printf 'feedback_miner.outside_since.%s' "$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"; }
# kv_all <out-file> writes the whole table there as one JSON object and returns
# 0, or returns 1 when the listing did not answer with one.
kv_all() {
  gc bd kv list --json </dev/null 2>/dev/null | scrub > "$1"
  jq -e 'type == "object"' "$1" >/dev/null 2>&1
}
# day_get <key> prints the day and returns 0, returns 3 when no day is
# recorded, and 1 when the read did not answer. `kv get` exits 1 for an unset
# key and still prints {"found": false}, so the answer is read from the JSON.
day_get() {
  local out
  out=$(gc bd kv get "$1" --json </dev/null 2>/dev/null | scrub)
  printf '%s' "$out" | jq -e 'type == "object" and has("found")' >/dev/null 2>&1 || return 1
  [ "$(printf '%s' "$out" | jq -r '.found')" = true ] || return 3
  printf '%s' "$out" | jq -r '.value // "" | tostring'
}
# day_set <key> <day> returns 0 only when the day reads back.
day_set() {
  gc bd kv set "$1" "$2" </dev/null >/dev/null 2>&1 || return 1
  [ "$(day_get "$1")" = "$2" ]
}

# --- identity ----------------------------------------------------------------
identity() {
  local url slug self
  url=$(git -C "$CHECKOUT" remote get-url origin 2>/dev/null)
  [ -n "$url" ] || { err "no origin remote in $CHECKOUT"; return 1; }
  slug=$(gh repo view "$url" --json nameWithOwner -q .nameWithOwner 2>/dev/null)
  case "$slug" in
    */*/*|/*|*/) slug="" ;;
    */*) : ;;
    *) slug="" ;;
  esac
  [ -n "$slug" ] || { err "could not resolve owner/name from origin ($url)"; return 1; }
  self=$(gh api user --jq .login 2>/dev/null)
  [ -n "$self" ] || { err "could not resolve the login gh posts as"; return 1; }
  printf '%s\t%s\n' "$slug" "$self"
}

if [ "$VERB" = identity ]; then
  [ -n "$CHECKOUT" ] || die_usage "identity needs --checkout"
  identity || exit 1
  exit 0
fi

[ -n "$DIR" ] || die_usage "$VERB needs --dir"

# The observation surface, keyed by provenance: every observation already
# recorded on a post, in every live status and closed, which is the norm.
# A listing that does not read stops the run: without it nothing can be deduped.
read_surface() { # <out-file>
  local raw="$DIR/obs.raw"
  gc bd list -l observation --status open,in_progress,blocked,deferred,closed --json --limit=0 2>/dev/null | scrub > "$raw"
  if ! jq -e 'type == "array"' "$raw" >/dev/null 2>&1; then
    err "the observation listing did not read, so nothing can be deduped; nothing filed"
    return 1
  fi
  jq '[ .[]
        | select(((.metadata // {}).task_kind // "") == "observation")
        | { id, title: (.title // ""),
            provenance: ((.metadata["obs.provenance"] // "") | tostring),
            category: ((.metadata["obs.category"] // "") | tostring) }
        | select(.provenance != "") ]
      | group_by(.provenance)
      | map({key: .[0].provenance, value: map({id, category, title})})
      | from_entries' "$raw" > "$1"
}

meta() { jq -r --arg k "$1" '.[$k] // "" | tostring' "$DIR/meta.json"; }

# --- fetch-pr: one PR's three streams, classified (a sweep worker) ------------
# Each worker reads the PR's reviews, its inline review comments and its
# conversation comments at once, and writes the PR's posts, classified, to
# prs/<n>.jsonl. A PR any read failed on is marked failed and contributes
# nothing, and the next run reads it again. A PR already written is kept.
# A worker writes under its own pid and renames the posts file into place
# whole, so a worker killed partway, or one still running when a resumed sweep
# reads the PR again, never leaves a partial posts file for the resume to keep.
if [ "$VERB" = fetch-pr ]; then
  N="${1:-}"
  is_count "$N" || die_usage "fetch-pr needs a PR number"
  base="$DIR/prs/$N"
  [ -f "$base.jsonl" ] && exit 0
  part="$base.$$"
  rm -f "$base.failed"
  SLUG=$(meta repo); SELF=$(meta self)
  gh api "repos/$SLUG/pulls/$N/reviews?per_page=100" --paginate --jq '.[]' > "$part.reviews" 2>/dev/null & r1=$!
  gh api "repos/$SLUG/pulls/$N/comments?per_page=100" --paginate --jq '.[]' > "$part.inline" 2>/dev/null & r2=$!
  gh api "repos/$SLUG/issues/$N/comments?per_page=100" --paginate --jq '.[]' > "$part.issue" 2>/dev/null & r3=$!
  read_ok=1
  for r in "$r1" "$r2" "$r3"; do wait "$r" || read_ok=0; done
  if [ "$read_ok" = 0 ]; then
    : > "$base.failed"
    exit 0
  fi
  OWN_DEF=$(cat "$DIR/own-def.jq") || { : > "$base.failed"; exit 0; }
  if ! jq -nc --arg self "$SELF" --arg repo "$SLUG" --argjson pr "$N" \
       --slurpfile prs "$DIR/prs.json" --slurpfile seen "$DIR/obs.json" \
       --slurpfile reviews "$part.reviews" --slurpfile inline "$part.inline" --slurpfile issue "$part.issue" \
       --arg outside_category "$OUTSIDE_CATEGORY" "$OWN_DEF"'
    def has_text: ((.body // "") | tostring | test("\\S"));
    def first_line: ((.body // "") | tostring | split("\n") | map(select(test("\\S"))) | (.[0] // ""));
    def code_review_signed:
      (first_line | test("(?i)code[ -]?review|claude code"))
      or ((.body // "") | tostring | test("(?i)generated with \\[?claude code"));
    def app_notice:
      ((.user.type // "") == "Bot")
      and ((.gc_stream == "review" and (.state // "") == "APPROVED")
           or (.gc_stream == "issue" and (first_line | test("^\\s*\\[vc\\]:"))));
    ($prs[0] | map(select(.number == $pr)) | .[0] // {}) as $p
    | ($seen[0] // {}) as $obs
    | ($reviews | map(select(((.user.login // "") == $self) and (gc_city_marked | not) and code_review_signed) | .id)) as $signed
    | ($reviews | map({key: (.id | tostring), value: (.submitted_at // "")}) | from_entries) as $submitted
    | [ ($reviews[] | . + {gc_stream: "review", gc_kind: "review"}),
        ($inline[]  | . + {gc_stream: "inline", gc_kind: "comment",
                           gc_review_submitted_at: ($submitted[(.pull_request_review_id // "") | tostring] // null)}),
        ($issue[]   | . + {gc_stream: "issue", gc_kind: "comment"}) ]
    | .[]
    | select(has_text)
    | ((.user.login // "") | tostring) as $login
    | gc_city_marked as $marked
    | (if .gc_stream == "review" then (.id as $i | any($signed[]; . == $i))
       elif .gc_stream == "inline" then (.pull_request_review_id as $r | any($signed[]; . == $r))
       else false end) as $is_signed
    | (if $marked then "city"
       elif $login != $self then (if app_notice then "notice" else "outside" end)
       elif $is_signed then "outside"
       else "city" end) as $class
    | ("pr:" + $repo + "#" + ($pr | tostring) + ":" + .gc_kind + ":" + (.id | tostring)) as $key
    | ($obs[$key] // []) as $recorded
    | { key: $key, pr: $pr, title: ($p.title // ""), in_window: ($p.in_window // false),
        stream: .gc_stream, kind: .gc_kind, id: .id, login: $login, at: gc_city_posted_at,
        url: (.html_url // ""), path: (.path // null), line: (.line // .original_line // null),
        reply_to: (.in_reply_to_id // null), review_state: (.state // null),
        class: $class, marked: $marked, signed: $is_signed, flag: false,
        recorded: $recorded, captured: any($recorded[]; .category == $outside_category),
        body: (.body | tostring) }' > "$part.jsonl" 2> "$part.err"; then
    rm -f "$part.jsonl"
    : > "$base.failed"
  else
    mv -f "$part.jsonl" "$base.jsonl" || : > "$base.failed"
  fi
  exit 0
fi

# --- sweep -----------------------------------------------------------------------
if [ "$VERB" = sweep ]; then
  [ -n "$CHECKOUT" ] || die_usage "sweep needs --checkout"
  is_count "$DAYS" && [ "$DAYS" -gt 0 ] || die_usage "--days must be a positive integer"
  is_count "$BACKFILL" || die_usage "--backfill-days must be a non-negative integer"
  is_count "$JOBS" && [ "$JOBS" -gt 0 ] || die_usage "--jobs must be a positive integer"
  [ -x "$PR_POST" ] || { err "the PR posting helper is missing ($PR_POST); cannot tell the city's posts from feedback"; exit 1; }
  mkdir -p "$DIR/prs" || { err "cannot create $DIR/prs"; exit 1; }
  DIR=$(cd "$DIR" && pwd) && CHECKOUT=$(cd "$CHECKOUT" && pwd) || { err "cannot resolve the work dir or the checkout"; exit 1; }
  # unread.txt is written once every listed PR has been tried, so a sweep cut
  # short leaves none, and advance then keeps the outside capture's day.
  rm -f "$DIR/unread.txt"
  cd "$CHECKOUT" || { err "cannot enter $CHECKOUT"; exit 1; }
  "$PR_POST" own-def > "$DIR/own-def.jq" && [ -s "$DIR/own-def.jq" ] \
    || { err "the PR posting helper did not print its provenance definition; cannot tell the city's posts from feedback"; exit 1; }
  ID=$(identity) || exit 1
  SLUG=${ID%%$'\t'*}; SELF=${ID#*$'\t'}

  read_surface "$DIR/obs.json" || exit 1
  # A rig with no day recorded starts its outside capture --backfill-days back,
  # and records that day before it reads, so a run cut short keeps the same
  # start. A recorded day that is not a date starts the capture again.
  DAY_KEY=$(day_key "$SLUG")
  CAPTURE_DAY=$(day_get "$DAY_KEY"); KV_RC=$?
  if [ "$KV_RC" = 0 ] && ! is_day "$CAPTURE_DAY"; then
    warn "the outside capture's day ($DAY_KEY) reads '$CAPTURE_DAY', which is not a date, so the capture starts again"
    KV_RC=3
  fi
  case "$KV_RC" in
    0) : ;;
    3) CAPTURE_DAY=$(day_start "$BACKFILL")
       day_set "$DAY_KEY" "$CAPTURE_DAY" \
         || { err "could not record where the outside capture starts ($DAY_KEY=$CAPTURE_DAY); nothing read"; exit 1; }
       echo "$PROG: this rig's outside capture starts with this run, at $CAPTURE_DAY ($DAY_KEY)" ;;
    *) err "the outside capture's day ($DAY_KEY) did not read, so which PRs the capture owes is unknown; nothing read"; exit 1 ;;
  esac
  TODAY=$(day_start 0); WINDOW_SINCE=$(day_start "$DAYS"); SINCE="$WINDOW_SINCE"
  if [[ "$CAPTURE_DAY" < "$WINDOW_SINCE" ]]; then
    SINCE="$CAPTURE_DAY"
    echo "$PROG: the outside capture still owes every PR closed since $CAPTURE_DAY, so the sweep reads back to then"
  fi

  # The merged and closed PRs, newest update first. Closing a PR updates it, so
  # once a page ends on a PR last updated before the window, every PR after it
  # closed before the window too, and the listing stops there. GitHub's search
  # index is not read: its closed: qualifier leaves out some closed PRs.
  Q='query($owner:String!,$name:String!,$cursor:String){repository(owner:$owner,name:$name){pullRequests(states:[MERGED,CLOSED],first:100,after:$cursor,orderBy:{field:UPDATED_AT,direction:DESC}){pageInfo{hasNextPage endCursor} nodes{number title closedAt mergedAt updatedAt}}}}'
  : > "$DIR/prs.raw"
  CURSOR=""
  while :; do
    CURSOR_ARGS=(); [ -n "$CURSOR" ] && CURSOR_ARGS=(-f cursor="$CURSOR")
    PAGE=$(gh api graphql -f query="$Q" -f owner="${SLUG%%/*}" -f name="${SLUG#*/}" ${CURSOR_ARGS[@]+"${CURSOR_ARGS[@]}"} 2>/dev/null) \
      && printf '%s' "$PAGE" | jq -e '.data.repository.pullRequests.nodes | type == "array"' >/dev/null 2>&1 \
      || { err "could not list $SLUG's merged and closed PRs"; exit 1; }
    printf '%s' "$PAGE" | jq -c '.data.repository.pullRequests.nodes[]' >> "$DIR/prs.raw"
    LAST=$(printf '%s' "$PAGE" | jq -r '.data.repository.pullRequests.nodes[-1].updatedAt // "" | .[0:10]')
    [ "$(printf '%s' "$PAGE" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage')" = true ] && [ -n "$LAST" ] || break
    [[ "$LAST" < "$SINCE" ]] && break
    CURSOR=$(printf '%s' "$PAGE" | jq -r '.data.repository.pullRequests.pageInfo.endCursor // ""')
    [ -n "$CURSOR" ] || break
  done
  jq -s --arg s "$SINCE" --arg w "$WINDOW_SINCE" '
    map(. + {closed: ((.closedAt // .mergedAt // "") | tostring | .[0:10])})
    | map(select(.closed != "" and .closed >= $s)) | unique_by(.number)
    | map({number, title: (.title // ""), closed, in_window: (.closed >= $w)})' "$DIR/prs.raw" > "$DIR/prs.json" \
    || { err "could not read $SLUG's PR listing"; exit 1; }
  jq -n --arg repo "$SLUG" --arg self "$SELF" --arg checkout "$(pwd)" --arg rig "${GC_RIG:-}" \
        --argjson days "$DAYS" --arg since "$SINCE" --arg window_since "$WINDOW_SINCE" \
        --arg day_key "$DAY_KEY" --arg capture_day "$CAPTURE_DAY" --arg swept_on "$TODAY" \
    '{repo: $repo, self: $self, checkout: $checkout, rig: $rig, days: $days, since: $since,
      window_since: $window_since, day_key: $day_key, capture_day: $capture_day, swept_on: $swept_on}' > "$DIR/meta.json" \
    || { err "cannot write $DIR/meta.json"; exit 1; }

  jq -r '.[].number' "$DIR/prs.json" > "$DIR/prs.txt"
  : > "$DIR/sweep.jsonl"
  if [ -s "$DIR/prs.txt" ]; then
    xargs -n 1 -P "$JOBS" "$ME" fetch-pr --dir "$DIR" < "$DIR/prs.txt"
    while IFS= read -r n; do
      [ -f "$DIR/prs/$n.jsonl" ] && cat "$DIR/prs/$n.jsonl" >> "$DIR/sweep.jsonl"
    done < "$DIR/prs.txt"
  fi
  # A PR whose worker wrote no posts file did not read, whether a read failed
  # or the worker never ran. Its posts are missing from this sweep only:
  # unread.txt keeps the outside capture's day from moving past the PR's
  # close, so the next run reads the PR again.
  UNREAD=""
  while IFS= read -r n; do
    [ -f "$DIR/prs/$n.jsonl" ] || UNREAD="$UNREAD $n"
  done < "$DIR/prs.txt"
  for n in $UNREAD; do echo "$n"; done > "$DIR/unread.txt" || { err "cannot write $DIR/unread.txt"; exit 1; }
  [ -z "$UNREAD" ] || warn "PR(s) that did not read, left for the next run:$UNREAD"

  # The flag needs each PR's provenance cutover, read only when some unmarked
  # city post makes it matter: one listing of every anchor that carries one.
  if jq -e -s 'any(.[]; .class == "city" and (.marked | not))' "$DIR/sweep.jsonl" >/dev/null 2>&1; then
    CUT_RAW="$DIR/cutover.raw"
    gc bd list --all --has-metadata-key pr_provenance_since --json --limit 0 2>/dev/null | scrub > "$CUT_RAW"
    if jq -e 'type == "array"' "$CUT_RAW" >/dev/null 2>&1; then
      jq '[ .[] | {pr: ((.metadata.pr_number // "") | tostring), since: ((.metadata.pr_provenance_since // "") | tostring)}
            | select(.pr != "" and .since != "") ]
          | group_by(.pr) | map({key: .[0].pr, value: (map(.since) | min)}) | from_entries' "$CUT_RAW" > "$DIR/cutover.json"
      jq -c --arg self "$SELF" --slurpfile cut "$DIR/cutover.json" "$(cat "$DIR/own-def.jq")"'
        if .class == "city" and (.marked | not)
        then ($cut[0][.pr | tostring] // "") as $since
             | . + {flag: ({body, user: {login}, created_at: .at} | gc_city_own($self; $since) | not)}
        else . end' "$DIR/sweep.jsonl" > "$DIR/sweep.next" && mv "$DIR/sweep.next" "$DIR/sweep.jsonl" \
        || { err "could not mark the flagged posts"; exit 1; }
    else
      warn "the anchors' provenance cutovers did not read, so no unmarked city post is flagged this run"
    fi
  fi

  jq -rs --arg slug "$SLUG" --arg since "$SINCE" --arg ws "$WINDOW_SINCE" --argjson listed "$(jq 'length' "$DIR/prs.json")" '
    "\($slug): read \($listed) PR(s) merged or closed since \($since); the standing window starts \($ws)",
    "  outside: \(map(select(.class == "outside")) | length) post(s), \(map(select(.class == "outside" and (.captured | not))) | length) not yet recorded",
    "  city: \(map(select(.class == "city")) | length) post(s), \(map(select(.class == "city" and .in_window)) | length) in the standing window",
    "  app notices skipped: \(map(select(.class == "notice")) | length); unmarked city posts flagged: \(map(select(.flag)) | length)"' "$DIR/sweep.jsonl"
  exit 0
fi

[ -f "$DIR/sweep.jsonl" ] && [ -f "$DIR/meta.json" ] || { err "$DIR holds no sweep; run sweep first"; exit 1; }
touch "$DIR/filed.tsv" "$DIR/shown.tsv"

# How far show has printed each post: shown.tsv holds one line per post a call
# printed, its key and the characters printed through, and a post's last line
# is where it stands.
SHOWN_POS='reduce ($shown | split("\n") | map(select(length > 0) | split("\t")))[] as $s
             ({}; .[$s[0]] = ($s[1] | tonumber))'

# --- show ------------------------------------------------------------------------
# The agent condenses or judges a post from what show prints, so show prints
# every post whole. The bodies of one call stay under --max-chars, so its output
# comes back whole from a tool call, and a post longer than that is printed in
# parts across calls. An outside post stays on offer until it is recorded, and a
# city post until a call has printed it whole.
if [ "$VERB" = show ]; then
  [ -n "$WHICH" ] || die_usage "show needs --outside or --city"
  is_count "$LIMIT" && [ "$LIMIT" -gt 0 ] || die_usage "--limit must be a positive integer"
  is_count "$MAX_CHARS" && [ "$MAX_CHARS" -gt 0 ] || die_usage "--max-chars must be a positive integer"
  PLAN="$DIR/plan.$$.json"
  jq -s --arg which "$WHICH" --argjson limit "$LIMIT" --argjson budget "$MAX_CHARS" \
        --rawfile filed "$DIR/filed.tsv" --rawfile shown "$DIR/shown.tsv" '
    ($filed | split("\n") | map(select(length > 0) | split("\t")[0])) as $done
    | ('"$SHOWN_POS"') as $pos
    | map(. + {len: (.body | length), through: ($pos[.key] // 0)})
    | (if $which == "outside"
       then map(select(.class == "outside" and (.captured | not) and (.key as $k | ($done | index([$k])) == null)))
       else map(select(.class == "city" and .in_window and .through < .len)) end)
    | map(. + {from: (if .through < .len then .through else 0 end)})
    | (sort_by(.at) | reverse) as $set
    | reduce $set[] as $p ({used: 0, out: [], full: false};
        if .full or (.out | length) >= $limit then .full = true
        elif .used + ($p.len - $p.from) <= $budget then .out += [$p + {to: $p.len}] | .used += ($p.len - $p.from)
        elif .used == 0 then .out += [$p + {to: ($p.from + $budget)}] | .used = $budget | .full = true
        else .full = true end)
    | {total: ($set | length), out}' "$DIR/sweep.jsonl" > "$PLAN" \
    || { err "could not read the sweep in $DIR"; rm -f "$PLAN"; exit 1; }
  jq -r --arg which "$WHICH" '
    "== \(.out | length) of \(.total) \(if $which == "outside" then "outside post(s) not yet recorded" else "city post(s) in the standing window not yet shown whole" end) ==",
    (.out[]
     | "--- \(.key)",
       "by \(.login), \(.at), \(.url)",
       "PR #\(.pr) \"\(.title)\": \(if .stream == "inline" then "inline on \(.path // "?")\(if .line then ":\(.line)" else "" end)\(if .reply_to then ", in reply to comment \(.reply_to)" else "" end)" elif .stream == "review" then "review body (\(.review_state // "?"))" else "conversation comment" end)\(if .flag then " [FLAGGED: unmarked]" else "" end)",
       (.recorded[]? | "already recorded on this post: \(.id) (\(.category)) \(.title)"),
       (if .from == 0 and .to == .len then .body
        else "[characters \(.from + 1) to \(.to) of \(.len)\(if .to < .len then "; the rest comes in the next show call, and this post is filed only after its last part" else ", its last part" end)]",
             .body[.from:.to] end),
       ""),
    (if .total > (.out | length) then "== \(.total - (.out | length)) more after these: run show again ==" else empty end)' "$PLAN" \
    && jq -r '.out[] | "\(.key)\t\(.to)"' "$PLAN" >> "$DIR/shown.tsv" \
    || { err "could not print the posts, or record what was printed"; rm -f "$PLAN"; exit 1; }
  rm -f "$PLAN"
  exit 0
fi

# --- file --------------------------------------------------------------------------
if [ "$VERB" = file ]; then
  [ -z "$MAX_STANDING" ] || is_count "$MAX_STANDING" || die_usage "--max-standing must be a non-negative integer"
  SLUG=$(meta repo); RIG=$(meta rig)
  cd "$(meta checkout)" 2>/dev/null || { err "cannot enter the swept checkout"; exit 1; }
  ROWS="$DIR/rows.$$.jsonl"; : > "$ROWS"
  BAD=0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$(printf '%s' "$line" | tr -d '[:space:]')" ] || continue
    if printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then
      printf '%s\n' "$line" | jq -c . >> "$ROWS"
    else
      err "row is not a JSON object, skipped: $line"; BAD=$((BAD + 1))
    fi
  done
  [ -s "$ROWS" ] || { rm -f "$ROWS"; [ "$BAD" = 0 ] || exit 1; echo "$PROG: no rows to file"; exit 0; }
  read_surface "$DIR/obs.now.json" || { rm -f "$ROWS"; exit 1; }
  DEFAULT_SCOPE="repo:${RIG:-${SLUG#*/}}"
  # One action per row: what to file, or why not. Bodies and metadata are
  # composed here, so every observation of a kind has the same shape.
  ACTIONS="$DIR/actions.$$.jsonl"
  jq -c -n --slurpfile rows "$ROWS" --slurpfile obs "$DIR/obs.now.json" \
        --arg slug "$SLUG" --arg scope "$DEFAULT_SCOPE" --arg oc "$OUTSIDE_CATEGORY" --argjson qmax "$QUOTE_MAX" \
        --slurpfile items "$DIR/sweep.jsonl" --rawfile shown "$DIR/shown.tsv" '
    def trim: tostring | gsub("^\\s+|\\s+$"; "");
    def one_line($n): trim | gsub("\\s+"; " ") | if length > $n then (.[0:$n] | sub(" [^ ]*$"; "")) + " …" else . end;
    def quote: (.body | trim) as $b
      | (if ($b | length) > $qmax then ($b[0:$qmax] + " …") else $b end)
      | split("\n") | map("> " + .) | join("\n");
    def locus: if .stream == "inline"
        then "an inline comment on `\(.path // "?")`\(if .line then ", line \(.line)" else "" end)\(if .reply_to then ", replying in the thread at https://github.com/\($slug)/pull/\(.pr)#discussion_r\(.reply_to)" else "" end)"
        elif .stream == "review" then "the body of a review (\(.review_state // "?" | ascii_downcase | gsub("_"; " ")))"
        else "a conversation comment" end;
    ($items | map({key: .key, value: .}) | from_entries) as $byKey
    | ('"$SHOWN_POS"') as $pos
    | ($obs[0] // {}) as $recorded
    | $rows | to_entries[] | .key as $i | .value as $r
    | ($r.key // "" | tostring) as $k
    | $byKey[$k] as $it
    | if $it == null then {i: $i, key: $k, act: "error", why: "no swept post has this key"}
      elif ($r.statement // "" | trim) == "" then {i: $i, key: $k, act: "error", why: "the row has no statement"}
      elif (($r.directive // "diff") | IN("standing", "diff") | not) then {i: $i, key: $k, act: "error", why: "directive must be standing or diff"}
      elif $it.class == "notice" then {i: $i, key: $k, act: "error", why: "an app account notice is not review feedback"}
      else
        (if $it.class == "outside" then "outside" else "standing" end) as $kind
        | (if $kind == "outside" then $oc else ($r.category // "" | trim) end) as $cat
        | if $kind == "standing" and ($cat == "" or $cat == $oc) then {i: $i, key: $k, act: "error", why: "a city post needs its own category, other than \($oc)"}
          elif $kind == "standing" and (($r.norm // "" | trim) == "") then {i: $i, key: $k, act: "error", why: "a city post needs a proposed norm"}
          elif any(($recorded[$k] // [])[]; .category == $cat) then {i: $i, key: $k, act: "skip", why: "already recorded under \($cat)"}
          elif ($pos[$k] // 0) < ($it.body | length) then {i: $i, key: $k, act: "error",
            why: (if ($pos[$k] // 0) == 0 then "show has not printed this post in this run; read it with show, then file it"
                  else "show has printed this post only through character \($pos[$k]) of \($it.body | length); run show for the rest, then file it" end)}
          else
            ($r.statement | trim) as $st
            | ($r.context // "" | trim) as $cx
            | {i: $i, key: $k, act: "file", kind: $kind, cat: $cat,
               title: ("obs: " + ($st | one_line(160)) + " (pr:" + $slug + "#" + ($it.pr | tostring) + ")"),
               body: ("## Statement\n" + $st + "\n\n## Quote\n" + ($it | quote) + "\n— " + $it.login + ", " + $it.url + "\n\n"
                      + (if $kind == "standing" then "## Proposed norm\n" + ($r.norm | trim) + "\n\n(Draft rule text only — explicitly non-binding; the distiller judges.)\n\n" else "" end)
                      + "## Context\nPR #" + ($it.pr | tostring) + ", \"" + $it.title + "\": " + ($it | locus) + "." + (if $cx != "" then " " + $cx else "" end)),
               meta: {task_kind: "observation", "obs.category": $cat,
                      "obs.scope": ($r.scope // $scope | trim | if . == "" then $scope else . end),
                      "obs.source": "miner", "obs.directive": ($r.directive // "diff"),
                      "obs.provenance": $k, "gc.outcome": "recorded", "gc.work_outcome": "no-op"}}
          end
      end' > "$ACTIONS" 2>"$DIR/actions.err" \
    || { err "could not compose the rows: $(head -c 300 "$DIR/actions.err")"; rm -f "$ROWS" "$ACTIONS"; exit 1; }

  STANDING_DONE=$(awk -F'\t' '$2 == "standing" { n++ } END { print n + 0 }' "$DIR/filed.tsv")
  FILED=0; SKIPPED=0; CAPPED=0; FAILED=0
  # The posts skipped because the store records them and this run did not file
  # them: another run recorded them after the sweep read the store, or a create
  # whose answer was lost did.
  REFRESH="$DIR/refresh.$$"; : > "$REFRESH"
  # The store read above dedups against what earlier calls filed; this list
  # dedups two rows of this call that name one post and one category.
  THIS_CALL=$'\n'
  while IFS= read -r a; do
    key=$(printf '%s' "$a" | jq -r '.key'); act=$(printf '%s' "$a" | jq -r '.act')
    case "$act" in
      error) err "row for $key not filed: $(printf '%s' "$a" | jq -r '.why')"; BAD=$((BAD + 1)); continue ;;
      skip)  echo "$PROG: $key $(printf '%s' "$a" | jq -r '.why') — skipped"; SKIPPED=$((SKIPPED + 1))
             awk -F'\t' -v k="$key" '$1 == k { f = 1 } END { exit !f }' "$DIR/filed.tsv" || printf '%s\n' "$key" >> "$REFRESH"
             continue ;;
    esac
    kind=$(printf '%s' "$a" | jq -r '.kind'); cat_=$(printf '%s' "$a" | jq -r '.cat')
    case "$THIS_CALL" in *$'\n'"$key|$cat_"$'\n'*)
      echo "$PROG: $key already filed under $cat_ by an earlier row of this call — skipped"; SKIPPED=$((SKIPPED + 1)); continue ;;
    esac
    if [ "$kind" = standing ] && [ -n "$MAX_STANDING" ] && [ "$STANDING_DONE" -ge "$MAX_STANDING" ]; then
      echo "$PROG: $key dropped for the $MAX_STANDING-per-run standing cap; the window re-covers it next run"
      CAPPED=$((CAPPED + 1)); continue
    fi
    title=$(printf '%s' "$a" | jq -r '.title'); body=$(printf '%s' "$a" | jq -r '.body'); m=$(printf '%s' "$a" | jq -c '.meta')
    # The observation is filed whole and closed in one create: its provenance
    # and category, the pair the dedup reads, ride the create.
    out=$(gc bd create "$title" -t task -l learning -l observation -d "$body" --metadata "$m" --status=closed --json 2>"$DIR/create.err")
    id=$(printf '%s' "$out" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
    if [ -z "$id" ] || [ "$id" = null ]; then
      err "could not file the observation for $key: $(printf '%s' "$out" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null) $(tail -c 300 "$DIR/create.err" 2>/dev/null)"
      FAILED=$((FAILED + 1)); continue
    fi
    THIS_CALL="$THIS_CALL$key|$cat_"$'\n'
    printf '%s\t%s\t%s\n' "$key" "$kind" "$id" >> "$DIR/filed.tsv"
    [ "$kind" = standing ] && STANDING_DONE=$((STANDING_DONE + 1))
    echo "$PROG: filed $id ($kind) for $key"
    FILED=$((FILED + 1))
  done < "$ACTIONS"
  # Each such post takes the store's record into the sweep, so show stops
  # offering it and the summary counts it as recorded before this run, not as
  # filed now. It reads as captured only when the store holds its
  # outside-review observation.
  if [ -s "$REFRESH" ]; then
    jq -c --slurpfile obs "$DIR/obs.now.json" --rawfile keys "$REFRESH" --arg oc "$OUTSIDE_CATEGORY" '
      ($keys | split("\n") | map(select(length > 0))) as $ks
      | if (.key as $k | $ks | index([$k])) != null
        then ($obs[0][.key] // []) as $r | . + {recorded: $r, captured: any($r[]; .category == $oc)}
        else . end' "$DIR/sweep.jsonl" > "$DIR/sweep.next" && mv -f "$DIR/sweep.next" "$DIR/sweep.jsonl" \
      || warn "could not take the store's record of the skipped post(s) into the sweep, so show may offer them again"
  fi
  rm -f "$ROWS" "$ACTIONS" "$DIR/actions.err" "$DIR/obs.now.json" "$DIR/create.err" "$REFRESH"
  echo "$PROG: filed $FILED, skipped $SKIPPED already recorded, dropped $CAPPED for the cap, $BAD row(s) refused, $FAILED create(s) failed"
  [ "$BAD" = 0 ] && [ "$FAILED" = 0 ] || exit 1
  exit 0
fi

# --- flag ----------------------------------------------------------------------------
# Each flagged post is named once, on the finding that holds the
# unmarked-city-post key when the post is first raised. patrol-finding.sh puts a
# raise either on a new finding, whose body lists the posts, or on the live one
# as a recurrence, which it notes as the message's first 200 characters on one
# line. The message opens with a longer paragraph, so that line names no post,
# and on a recurrence the flag appends its own note listing the posts. The store's key-value table then records each post with the finding
# that names it, and a recorded post is never raised again: not while that
# finding is open, where the raise would only repeat, and not after it closes,
# where patrol-finding.sh would file a new bead reporting that the fix did not
# hold. A post is recorded only once a finding names it, so a raise that stops
# partway leaves the post for the next run, which raises it again while it is in
# the window.
if [ "$VERB" = flag ]; then
  SLUG=$(meta repo); SELF=$(meta self); RIG=$(meta rig)
  FLAG_KEY=unmarked-city-post
  jq -s 'map(select(.flag)) | sort_by(.at) | reverse' "$DIR/sweep.jsonl" > "$DIR/flagged.json" \
    || { err "could not read the flagged posts"; exit 1; }
  if [ "$(jq 'length' "$DIR/flagged.json")" = 0 ]; then
    echo "$PROG: no unmarked city post to flag"
    exit 0
  fi
  # The store the sweep read, which holds the record and the findings.
  [ -n "$RIG" ] && export GC_RIG="$RIG"
  cd "$(meta checkout)" 2>/dev/null || { err "cannot enter the swept checkout"; exit 1; }
  kv_all "$DIR/kv.json" || { err "the record of the unmarked posts already named did not read, so none is raised this run"; exit 1; }
  jq --slurpfile kv "$DIR/kv.json" --arg prefix "$POST_KEY_PREFIX" '
    map(. + {record: ($prefix + (.key | gsub("[^A-Za-z0-9._-]"; "_")))})
    | map(select(.record as $r | $kv[0] | has($r) | not))' "$DIR/flagged.json" > "$DIR/raise.json" \
    || { err "could not compare the flagged posts with the record of those already named"; exit 1; }
  N=$(jq 'length' "$DIR/raise.json")
  if [ "$N" = 0 ]; then
    echo "$PROG: every unmarked city post in the window is already named in a finding under $FLAG_KEY"
    exit 0
  fi
  LIST=$(jq -r '.[] | "- \(.url) (posted \(.at)): \(.body | split("\n") | map(select(test("\\S"))) | (.[0] // "") | gsub("\\s+"; " ") | .[0:120])"' "$DIR/raise.json") \
    || { err "could not list the unmarked posts to raise"; exit 1; }
  [ -x "$PATROL_FINDING" ] || { err "patrol-finding.sh is missing ($PATROL_FINDING); the unmarked posts below are unrecorded:"; printf '%s\n' "$LIST" >&2; exit 1; }
  # The live findings under the key, read before and after the raise: the one
  # the raise filed, or whose finding.last_seen or finding.occurrences it moved,
  # holds the raise.
  live_findings() { # <out-file>
    gc bd list --status=open,in_progress,blocked,deferred,hooked,pinned --metadata-field "finding.key=$FLAG_KEY" --json --limit 0 </dev/null 2>/dev/null | scrub > "$1"
    jq -e 'type == "array"' "$1" >/dev/null 2>&1
  }
  live_findings "$DIR/findings.before" \
    || { err "the findings under $FLAG_KEY did not read, so none is raised this run"; exit 1; }
  MSG="These posts on $SLUG's pull requests are under the city's login ($SELF), carry no city mark, are not Claude Code /code-review output, and were posted after their PR's provenance cutover, when every city post on that PR carries the mark:
$LIST

Every pack script posts through assets/scripts/pr-post.sh, which tools/lint-learned.d/pr-post-bypass.sh enforces, and gh-origin-guard.sh refuses an unmarked post an agent types, so each of these came from a writer neither covered when it posted. Find what posted each one. A writer that neither covers yet needs its posts sent through pr-post.sh, and one that they cover now needs nothing more. Until a writer is covered, pr-facts.sh reads each post it makes as feedback for the city to answer, and the feedback miner leaves those posts out of the outside capture. A post flagged while this finding is open is added to its notes."
  ARGS=(--scope miner-findings --key "$FLAG_KEY" --title "City posts on $SLUG pull requests without the city's mark" --message "$MSG" --type bug --priority 2)
  [ -n "$RIG" ] && ARGS+=(--rig "$RIG")
  "$PATROL_FINDING" "${ARGS[@]}" || { err "the unmarked-post finding did not record"; exit 1; }
  live_findings "$DIR/findings.after" \
    || { err "the unmarked-post finding recorded, but the findings under $FLAG_KEY did not read back, so these posts are not recorded as named and the next run raises them again:"; printf '%s\n' "$LIST" >&2; exit 1; }
  HOLDER=$(jq -r --slurpfile before "$DIR/findings.before" '
    def seen: (.metadata // {}) | [.["finding.last_seen"], .["finding.occurrences"]] | map(. // "" | tostring);
    ($before[0] | map({key: .id, value: seen}) | from_entries) as $was
    | map(select($was[.id] != seen) | .id)
    | if length == 1 then .[0] else empty end' "$DIR/findings.after")
  [ -n "$HOLDER" ] \
    || { err "the unmarked-post finding recorded, but no single finding under $FLAG_KEY shows the raise, so these posts are not recorded as named and the next run raises them again:"; printf '%s\n' "$LIST" >&2; exit 1; }
  if jq -e --arg h "$HOLDER" 'any(.[]; .id == $h)' "$DIR/findings.before" >/dev/null 2>&1; then
    NOTE="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $PROG: $N more unmarked city post(s) on $SLUG's pull requests, flagged while this finding is open:
$LIST"
    gc bd update "$HOLDER" --append-notes "$NOTE" </dev/null >/dev/null 2>&1 \
      || { err "the raise landed on $HOLDER, but the note naming these posts did not, so they are not recorded as named and the next run raises them again:"; printf '%s\n' "$LIST" >&2; exit 1; }
  fi
  jq -r '.[].record' "$DIR/raise.json" | while IFS= read -r r; do
    gc bd kv set "$r" "named in $HOLDER" </dev/null >/dev/null 2>&1
  done
  kv_all "$DIR/kv.json" || echo '{}' > "$DIR/kv.json"
  UNRECORDED=$(jq -r --slurpfile kv "$DIR/kv.json" --arg v "named in $HOLDER" '.[] | select($kv[0][.record] != $v) | "- \(.url)"' "$DIR/raise.json") \
    || UNRECORDED=$(jq -r '.[] | "- \(.url)"' "$DIR/raise.json")
  if [ -n "$UNRECORDED" ]; then
    err "$HOLDER names these posts, but the record of them did not read back, so the next run raises them again:"; printf '%s\n' "$UNRECORDED" >&2; exit 1
  fi
  echo "$PROG: named $N unmarked city post(s) in $HOLDER"
  exit 0
fi

# --- advance -------------------------------------------------------------------------
# The run still owes each PR that did not read, and each PR with an outside post
# the store does not record. The outside capture's day moves to the close of
# the oldest of them, so the next run reads every one again, or to the sweep's
# own day when the run owes none. A day that another run moved after this sweep
# read it is left alone.
if [ "$VERB" = advance ]; then
  RIG=$(meta rig); DAY_KEY=$(meta day_key); CAPTURE_DAY=$(meta capture_day); SWEPT=$(meta swept_on)
  [ -n "$DAY_KEY" ] && is_day "$SWEPT" || { err "$DIR's sweep records no outside capture day; run sweep again"; exit 1; }
  [ -f "$DIR/unread.txt" ] || { err "the sweep in $DIR did not finish, so the outside capture stays at $CAPTURE_DAY"; exit 1; }
  # The store the sweep read, which is the one the day was read from.
  [ -n "$RIG" ] && export GC_RIG="$RIG"
  cd "$(meta checkout)" 2>/dev/null || { err "cannot enter the swept checkout"; exit 1; }
  read_surface "$DIR/obs.now.json" || exit 1
  OWED=$(jq -sc --slurpfile obs "$DIR/obs.now.json" --slurpfile prs "$DIR/prs.json" --rawfile unread "$DIR/unread.txt" \
              --arg oc "$OUTSIDE_CATEGORY" '
    ($unread | split("\n") | map(select(length > 0) | tonumber)) as $u
    | map(select(.class == "outside" and (.key as $k | any(($obs[0][$k] // [])[]; .category == $oc) | not))) as $left
    | ($prs[0] | map({key: (.number | tostring), value: (.closed // "")}) | from_entries) as $closed
    | (($u + ($left | map(.pr))) | unique) as $owed
    | {owed: $owed, unread: ($u | length), unrecorded: ($left | length),
       oldest: ($owed | map($closed[tostring] // "") | if length == 0 then "" else min end)}' "$DIR/sweep.jsonl") \
    || { err "could not compare the sweep with the store, so the outside capture stays at $CAPTURE_DAY"; exit 1; }
  if [ "$(printf '%s' "$OWED" | jq '.owed | length')" = 0 ]; then
    NEW_DAY="$SWEPT"; WHY="every PR the sweep listed read, and the store records every outside post it found"
  else
    NEW_DAY=$(printf '%s' "$OWED" | jq -r '.oldest')
    is_day "$NEW_DAY" || { err "could not date the PRs this run still owes, so the outside capture stays at $CAPTURE_DAY"; exit 1; }
    WHY=$(printf '%s' "$OWED" | jq -r '"\(.owed | length) PR(s) still owe a read (\(.owed | map("#\(.)") | join(", "))): \(.unread) did not read, and \(.unrecorded) outside post(s) are not recorded yet"')
  fi
  NOW=$(day_get "$DAY_KEY"); KV_RC=$?
  case "$KV_RC" in
    0|3) : ;;
    *) err "the outside capture's day ($DAY_KEY) did not read, so it stays where it is"; exit 1 ;;
  esac
  if [ "$KV_RC" != 0 ] || [ "$NOW" != "$CAPTURE_DAY" ]; then
    echo "$PROG: the outside capture's day reads ${NOW:-unset}, not the $CAPTURE_DAY this sweep read, so something moved it after the sweep and this run leaves it"
    exit 0
  fi
  if [ "$NEW_DAY" = "$NOW" ]; then
    echo "$PROG: the outside capture stays at $NOW: $WHY"
    exit 0
  fi
  day_set "$DAY_KEY" "$NEW_DAY" \
    || { err "could not move the outside capture's day to $NEW_DAY ($DAY_KEY), so the next run reads from $NOW"; exit 1; }
  # The run's own sweep now stands at the new day, so a second advance in this
  # dir reads the day as this run's, not as another run's.
  jq --arg d "$NEW_DAY" '.capture_day = $d' "$DIR/meta.json" > "$DIR/meta.next" && mv "$DIR/meta.next" "$DIR/meta.json" \
    || warn "could not note the new day in $DIR/meta.json"
  echo "$PROG: the outside capture moves to $NEW_DAY: $WHY"
  exit 0
fi

# --- summary -------------------------------------------------------------------------
if [ "$VERB" = summary ]; then
  jq -rs --rawfile filed "$DIR/filed.tsv" --slurpfile m "$DIR/meta.json" '
    ($filed | split("\n") | map(select(length > 0) | split("\t"))) as $f
    | "feedback-miner: \($m[0].repo), outside capture from \($m[0].since), standing window \($m[0].days) day(s)",
      "  outside posts: \(map(select(.class == "outside")) | length) read, \(map(select(.class == "outside" and .captured)) | length) recorded before this run, \($f | map(select(.[1] == "outside")) | length) filed now, \(map(select(.class == "outside" and (.captured | not))) | length - ($f | map(select(.[1] == "outside")) | length)) left unrecorded",
      "  standing-behavior observations filed from city posts: \($f | map(select(.[1] == "standing")) | length)",
      "  unmarked city posts flagged: \(map(select(.flag)) | length)"' "$DIR/sweep.jsonl"
  exit 0
fi
