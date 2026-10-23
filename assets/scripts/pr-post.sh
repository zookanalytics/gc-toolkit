#!/usr/bin/env bash
# pr-post.sh — the single writer of the city's posts on a pull request, the
# owner of the provenance mark every one of them carries, and the owner of the
# one definition of which posts are feedback.
#
# The city posts under the bot account that backs every agent's gh token, so an
# author does not say whether a comment is a city notice or feedback for the
# city to answer. The mark says it. Every body this script posts carries the
# marker below, and a review, inline comment, or conversation comment without
# one is feedback, whoever wrote it, unless it is not for review (below). The
# readers ask that question through `own-def`, which prints the one definition
# of "the city's own post" and of feedback;
# tools/lint-learned.d/pr-post-bypass.sh fails a post anywhere in the pack that
# does not come through here.
#
# The definition also covers what the city posted before it marked anything.
# A post under the city's login that carries no mark is the city's own when it
# predates the anchor's provenance cutover (pr_provenance_since, stamped by
# pr-facts.sh the first time it reads the PR). With no cutover known, every
# post under that login is the city's own. Two purpose markers that only the
# city has written count as the mark too: the write-back reply marker and the
# visit-comment marker.
#
# A post that informs rather than asks is not for review, and is never feedback,
# whoever posted it. It says so at its start: its body opens with the no-review
# mark below, which a person or a workflow writes into it, or begins with a
# prefix the rig declares for a third-party integration in not-for-review.toml
# at the root of its checkout (docs/not-for-review.md). The checkout is
# GC_RIG_ROOT when it is set, and otherwise the repository the caller runs in.
# With nothing declared, a third-party post is feedback. A review's state is not
# its body: an approval or a change request counts whatever its body carries.
#
# Each verb keeps the gh call its callers make, with the marker appended:
#   comment  a conversation comment (gh pr comment), with an optional inline
#            attachment (--attach, gh >= 2.99.0).
#   review   a COMMENT review (gh pr review --comment). Never an approval or a
#            change request: the city does not approve its own pull requests.
#   reply    a reply into a review thread (addPullRequestReviewThreadReply).
#   edit     a conversation comment rewritten in place (PATCH
#            issues/comments/<id>).
#   file-comment
#            a review comment on one file of the diff as a whole (POST
#            pulls/<n>/comments, subject_type=file), which opens a review
#            thread on that file at the given commit.
#
# Usage:
#   pr-post.sh comment --repo <host/owner/name> --pr <n> (--body <text> | --body-file <path>) [--attach <file>]
#   pr-post.sh review  --repo <host/owner/name> --pr <n> (--body <text> | --body-file <path>)
#   pr-post.sh reply   --host <host> --thread <thread node id> (--body <text> | --body-file <path>)
#   pr-post.sh edit    --repo <host/owner/name> --comment <id> (--body <text> | --body-file <path>)
#   pr-post.sh file-comment --repo <host/owner/name> --pr <n> --commit <oid> --path <file> (--body <text> | --body-file <path>)
#   pr-post.sh mark      print the provenance marker
#   pr-post.sh not-for-review
#                        print the no-review mark and each prefix the rig
#                        declares, one per line
#   pr-post.sh own-def   print the jq definitions gc_city_marked,
#                        gc_city_cutover($since), gc_city_posted_at,
#                        gc_city_own($self; $since), gc_not_for_review and
#                        gc_feedback($self; $since), for a reader to prepend to
#                        its program
#
# gh's own output passes through on stdout, so a caller that reads the posted
# comment back still gets it: its URL from comment, the created comment's JSON
# from file-comment. not-for-review and own-def name on stderr each part of the
# rig's declaration they refuse, and a refused part declares nothing.
#
# Exit: 0 posted (or printed); 1 the post failed, with gh's error on stderr, or
#       not-for-review refused part of the declaration; 2 usage.
set -u

PROG=pr-post

MARK='<!-- gc:city -->'

# A post's instant is when it became public. A review is public when it is
# submitted (submitted_at, or submittedAt on a GraphQL node). An inline comment is
# public when the review carrying it is submitted, which can be long after the
# comment was drafted: a GraphQL comment node names that review
# (pullRequestReview.submittedAt), and a REST comment row does not, so a reader
# holding the review list stamps the row with its review's submitted_at as
# gc_review_submitted_at. Any other post is public when it is created (created_at,
# or createdAt). All are UTC in the same YYYY-MM-DDTHH:MM:SSZ shape the cutover
# stamp is written in, so a string comparison orders them.
#
# gc_city_cutover owns the cutover's shape test. A stamp that is not a UTC
# instant reads as no cutover at all, which makes every post under the city's
# login its own, so a reader passes the stamp as it found it.
OWN_DEF='def gc_city_marked:
  ((.body // "") | tostring) as $b
  | ($b | contains("<!-- gc:city -->"))
    or ($b | contains("<!-- gc-writeback -->"))
    or ($b | contains("<!-- gc:visit:"));
def gc_city_cutover($since):
  ($since | tostring) as $s
  | if ($s | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) then $s else "" end;
def gc_city_posted_at:
  (.gc_review_submitted_at // .pullRequestReview.submittedAt // .submitted_at // .submittedAt
   // .created_at // .createdAt // "") | tostring;
def gc_city_own($self; $since):
  gc_city_cutover($since) as $cut
  | ($self != "")
    and (((.user.login // .author.login // "") | tostring) == $self)
    and (gc_city_marked
         or ($cut == "")
         or (gc_city_posted_at as $t | ($t != "") and ($t < $cut)));
'

NO_REVIEW_MARK='<!-- gc:no-review -->'
NFR_FILE=not-for-review.toml

# The rig's declaration read raw: a run of [[marker]] tables, each setting one
# prefix as a one-line TOML string. Prints {prefixes, refused}, where refused
# names each part read no prefix from. A table with any fault declares nothing,
# and neither does an empty prefix, which would take every comment out of
# review. A basic string may escape only a double quote and a backslash.
NFR_PARSE='([39] | implode) as $sq
| def tstring:
    if test("^\"(?:[^\"\\\\]|\\\\[\"\\\\])*\"\\s*(?:#.*)?$")
    then (capture("^\"(?<s>(?:[^\"\\\\]|\\\\[\"\\\\])*)\"").s | gsub("\\\\(?<c>[\"\\\\])"; .c))
    elif test("^" + $sq + "[^" + $sq + "]*" + $sq + "\\s*(?:#.*)?$")
    then capture("^" + $sq + "(?<s>[^" + $sq + "]*)" + $sq).s
    else null end;
  [ split("\n") | to_entries[] | { n: (.key + 1), l: (.value | sub("\r$"; "")) } ]
  | reduce .[] as $x ({ t: [], c: null, bad: [] };
      if ($x.l | test("^\\s*(?:#.*)?$")) then .
      elif ($x.l | test("^\\s*\\[\\[\\s*marker\\s*\\]\\]\\s*(?:#.*)?$")) then
        .t += [ .c | select(. != null) ] | .c = { n: $x.n, p: [], bad: [] }
      elif ($x.l | test("^\\s*\\[")) then
        .t += [ .c | select(. != null) ] | .c = null
        | .bad += [ "line \($x.n): this file holds only [[marker]] tables" ]
      elif .c == null then
        .bad += [ "line \($x.n): this file holds only [[marker]] tables" ]
      elif ($x.l | test("^\\s*prefix\\s*=")) then
        ($x.l | sub("^\\s*prefix\\s*=\\s*"; "") | tstring) as $v
        | if $v == null
          then .c.bad += [ "line \($x.n): the prefix is not a one-line string in double quotes, escaping only \\\" and \\\\, or in single quotes" ]
          else .c.p += [ $v ] end
      else
        .c.bad += [ "line \($x.n): a [[marker]] table sets its prefix and nothing else" ]
      end)
  | (.t + [ .c | select(. != null) ]) as $tables
  | { prefixes: [ $tables[] | select((.bad | length) == 0 and (.p | length) == 1 and (.p[0] | test("\\S"))) | .p[0] ],
      refused: (.bad + [ $tables[]
        | if (.bad | length) > 0 then .bad[]
          elif (.p | length) == 0 then "the [[marker]] at line \(.n) sets no prefix"
          elif (.p | length) > 1 then "the [[marker]] at line \(.n) sets its prefix twice"
          elif (.p[0] | test("\\S") | not) then "the [[marker]] at line \(.n) sets an empty prefix, which would take every comment out of review"
          else empty end ]) }'

# NFR_PREFIXES, the prefixes the rig declares as a JSON array, and NFR_REFUSED,
# one line per part of its declaration that declares nothing, each naming
# NFR_PATH. No file is a rig that declares nothing.
nfr_load() {
  local root parsed
  NFR_PATH=""; NFR_PREFIXES='[]'; NFR_REFUSED=""
  if [ -n "${GC_RIG_ROOT:-}" ]; then
    root="$GC_RIG_ROOT"
  else
    root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
  fi
  [ -n "$root" ] || return 0
  NFR_PATH="${root%/}/$NFR_FILE"
  [ -e "$NFR_PATH" ] || return 0
  if parsed=$(jq -Rsc "$NFR_PARSE" "$NFR_PATH" 2>/dev/null) && [ -n "$parsed" ]; then
    NFR_PREFIXES=$(printf '%s' "$parsed" | jq -c '.prefixes')
    NFR_REFUSED=$(printf '%s' "$parsed" | jq -r --arg f "$NFR_PATH" '.refused[] | "\($f): \(.)"')
  else
    NFR_REFUSED="$NFR_PATH: it could not be read, so it declares nothing"
  fi
}

# Not for review, and feedback. gc_not_for_review reads a post's body alone,
# so it is the same test on a review, an inline comment and a conversation
# comment. gc_feedback is the question every reader of feedback asks of a post:
# not the city's own, and not marked as not for review. A review's state is not
# its body, so a reader that counts an approval or a change request asks
# gc_city_own alone.
#
# The mark counts only among the HTML comments a body opens with: the comments
# from its start up to the first text that is neither a comment nor whitespace,
# where a comment that begins a line is indented three spaces or less. Markdown
# passes them through as raw HTML, so GitHub shows nothing for them. Anywhere
# later, the markdown before the mark decides what it is. In code, such as a
# fence in a list item or a suggested change, GitHub shows it as text, and only
# a full markdown parser tells that code from prose. A partial one that misses a
# form silences a reviewer with no trace. In a quote, it is the mark of the
# comment quoted. So no later mark counts, and a comment that quotes or
# discusses the mark stays feedback. A comment ends at its first --> or --!>, as
# an HTML parser ends it, and <!--> and <!---> are whole comments. Markdown ends
# the raw HTML at the end of a line holding -->, so a comment still open on such
# a line ends the opening there. gc_opens_with_mark reads the body a line at a
# time, with one regex match per comment and no string positions.
NFR_DEF='def gc_opens_with_mark:
  def comments($l):
    (if .open then
       ([$l | capture("^(?<c>.*?(?:-->|--!>))(?<r>.*)$")][0]) as $m
       | if $m == null then .s = null
         else .hit = (.hit or ($m.c | contains(gc_no_review_mark))) | .open = false | .s = $m.r end
     else .s = $l end)
    | if .s == null then del(.s)
      else (.s | capture("^(?<run>(?:[ \t]*<!--(?:>|->|.*?(?:-->|--!>)))*)[ \t]*(?<rest>.*)$")) as $m
        | .hit = (.hit or ($m.run | contains(gc_no_review_mark)))
        | (if $m.rest == "" then .
           elif ($m.rest | startswith("<!--")) then .open = true
           else .stop = true end)
        | del(.s)
      end;
  reduce (split("\n")[] | rtrimstr("\r")) as $l ({ open: false, hit: false, stop: false };
    if .stop or .hit then .
    elif .open or ($l | test("^ {0,3}<!--")) then
      comments($l)
      | if .open and ($l | contains("-->")) then .stop = true else . end
    elif ($l | test("^[ \t]*$")) then .
    else .stop = true end)
  | .hit;
def gc_not_for_review:
  ((.body // "") | tostring) as $b
  | ($b | contains(gc_no_review_mark) and gc_opens_with_mark)
    or any(gc_not_for_review_prefixes[]; . as $p | $b | startswith($p));
def gc_feedback($self; $since):
  (gc_city_own($self; $since) | not) and (gc_not_for_review | not);
'
nfr_defs() {
  printf 'def gc_no_review_mark: %s;\n' "$(jq -cn --arg m "$NO_REVIEW_MARK" '$m')"
  printf 'def gc_not_for_review_prefixes: %s;\n' "$NFR_PREFIXES"
  printf '%s' "$NFR_DEF"
}

usage() { sed -n '/^# Usage:/,/^# gh.s own output/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
die_usage() { echo "$PROG: $1" >&2; usage >&2; exit 2; }

VERB="${1:-}"
case "$VERB" in
  mark)    printf '%s\n' "$MARK"; exit 0 ;;
  not-for-review)
    nfr_load
    [ -z "$NFR_REFUSED" ] || printf '%s\n' "$NFR_REFUSED" | sed "s/^/$PROG: /" >&2
    printf '%s\n' "$NO_REVIEW_MARK"
    printf '%s' "$NFR_PREFIXES" | jq -r '.[]'
    [ -z "$NFR_REFUSED" ]; exit $? ;;
  own-def)
    nfr_load
    [ -z "$NFR_REFUSED" ] || printf '%s\n' "$NFR_REFUSED" | sed "s/^/$PROG: /" >&2
    printf '%s\n' "$OWN_DEF"; nfr_defs; exit 0 ;;
  comment|review|reply|edit|file-comment) shift ;;
  -h|--help) usage; exit 0 ;;
  *) die_usage "first argument must be comment, review, reply, edit, file-comment, mark, not-for-review or own-def" ;;
esac

REPO_Q=""; HOST=""; PR=""; THREAD=""; COMMENT=""; BODY=""; BODY_FILE=""; ATTACH=""
COMMIT_OID=""; FILE_PATH=""
HAVE_BODY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)      [ $# -ge 2 ] || die_usage "--repo needs a value"; REPO_Q="$2"; shift 2 ;;
    --host)      [ $# -ge 2 ] || die_usage "--host needs a value"; HOST="$2"; shift 2 ;;
    --pr)        [ $# -ge 2 ] || die_usage "--pr needs a value"; PR="$2"; shift 2 ;;
    --thread)    [ $# -ge 2 ] || die_usage "--thread needs a value"; THREAD="$2"; shift 2 ;;
    --comment)   [ $# -ge 2 ] || die_usage "--comment needs a value"; COMMENT="$2"; shift 2 ;;
    --body)      [ $# -ge 2 ] || die_usage "--body needs a value"; BODY="$2"; HAVE_BODY=1; shift 2 ;;
    --body-file) [ $# -ge 2 ] || die_usage "--body-file needs a value"; BODY_FILE="$2"; shift 2 ;;
    --attach)    [ $# -ge 2 ] || die_usage "--attach needs a value"; ATTACH="$2"; shift 2 ;;
    --commit)    [ $# -ge 2 ] || die_usage "--commit needs a value"; COMMIT_OID="$2"; shift 2 ;;
    --path)      [ $# -ge 2 ] || die_usage "--path needs a value"; FILE_PATH="$2"; shift 2 ;;
    *) die_usage "unknown argument '$1'" ;;
  esac
done

if [ -n "$HAVE_BODY" ] && [ -n "$BODY_FILE" ]; then
  die_usage "give --body or --body-file, not both"
elif [ -n "$BODY_FILE" ]; then
  [ -f "$BODY_FILE" ] || { echo "$PROG: --body-file '$BODY_FILE' does not exist" >&2; exit 2; }
  BODY=$(cat "$BODY_FILE") || { echo "$PROG: could not read --body-file '$BODY_FILE'" >&2; exit 1; }
elif [ -z "$HAVE_BODY" ]; then
  die_usage "$VERB needs --body or --body-file"
fi
[ -n "$(printf '%s' "$BODY" | tr -d '[:space:]')" ] || die_usage "$VERB refuses an empty body"
[ -z "$ATTACH" ] || [ "$VERB" = comment ] || die_usage "--attach is a comment option"
[ -z "$COMMIT_OID$FILE_PATH" ] || [ "$VERB" = file-comment ] || die_usage "--commit and --path are file-comment options"

# The mark goes last, after a blank line, so it opens an HTML block of its own
# and renders as nothing. A body that already carries it is posted as it is.
case "$BODY" in *"$MARK"*) : ;; *) BODY="$BODY"$'\n\n'"$MARK" ;; esac

# The repository, as owner/name, and the host it lives on, from --repo's
# host/owner/name. Anything else is refused: a write the caller cannot pin to a
# repository is not one this script guesses at.
split_repo() {
  case "$REPO_Q" in
    */*/*) HOST="${REPO_Q%%/*}"; REPO="${REPO_Q#*/}" ;;
    *) die_usage "--repo must be host/owner/name, got '$REPO_Q'" ;;
  esac
  case "$REPO" in */*/*|/*|*/|'') die_usage "--repo must be host/owner/name, got '$REPO_Q'" ;; esac
}

case "$VERB" in
  comment)
    split_repo
    case "$PR" in ''|*[!0-9]*) die_usage "comment needs --pr <number>" ;; esac
    ATTACH_ARGS=()
    if [ -n "$ATTACH" ]; then
      [ -s "$ATTACH" ] || { echo "$PROG: --attach '$ATTACH' is missing or empty" >&2; exit 1; }
      ATTACH_ARGS=(--attach "$ATTACH")
    fi
    gh pr comment "$PR" --repo "$REPO_Q" --body "$BODY" ${ATTACH_ARGS[@]+"${ATTACH_ARGS[@]}"} || exit 1
    ;;
  review)
    split_repo
    case "$PR" in ''|*[!0-9]*) die_usage "review needs --pr <number>" ;; esac
    TMPB=$(mktemp "${TMPDIR:-/tmp}/gctk-pr-post.XXXXXX") || { echo "$PROG: cannot create a temp file for the review body" >&2; exit 1; }
    trap 'rm -f "$TMPB"' EXIT
    printf '%s\n' "$BODY" > "$TMPB" || { echo "$PROG: cannot write the review body" >&2; exit 1; }
    gh pr review "$PR" --repo "$REPO_Q" --comment --body-file "$TMPB" || exit 1
    ;;
  reply)
    [ -n "$HOST" ] || die_usage "reply needs --host"
    [ -n "$THREAD" ] || die_usage "reply needs --thread <thread node id>"
    # A mutation that exits 0 with nothing on stdout did not answer, the same
    # test pr-facts.sh applies to every GraphQL write.
    out=$(gh api graphql --hostname "$HOST" \
      -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){clientMutationId}}' \
      -f t="$THREAD" -f b="$BODY") || exit 1
    [ -n "$out" ] || { echo "$PROG: the thread reply returned nothing" >&2; exit 1; }
    printf '%s\n' "$out"
    ;;
  edit)
    split_repo
    case "$COMMENT" in ''|*[!0-9]*) die_usage "edit needs --comment <id>" ;; esac
    gh api --method PATCH "repos/$REPO/issues/comments/$COMMENT" --hostname "$HOST" -f body="$BODY" || exit 1
    ;;
  file-comment)
    split_repo
    case "$PR" in ''|*[!0-9]*) die_usage "file-comment needs --pr <number>" ;; esac
    [ -n "$COMMIT_OID" ] || die_usage "file-comment needs --commit <oid>"
    [ -n "$FILE_PATH" ] || die_usage "file-comment needs --path <file>"
    gh api --method POST "repos/$REPO/pulls/$PR/comments" --hostname "$HOST" \
      -f body="$BODY" -f commit_id="$COMMIT_OID" -f path="$FILE_PATH" -f subject_type=file || exit 1
    ;;
esac
exit 0
