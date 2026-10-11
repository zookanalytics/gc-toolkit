#!/usr/bin/env bash
# Hermetic test for assets/scripts/review-dismissal.sh, what dismissing a review
# retires and what the approval dismissers share. Covers:
#   (DEF)      sourcing the file exposes $REVIEW_DISMISSAL_DEF, pr_coords and
#              approval_phrase, and the defs compile behind pr-post.sh's own-def
#   (LIVE)     live_comments drops the comments of a dismissed review and keeps
#              every other one, standalone comments included, each stamped
#              with its review's submission instant
#   (UNROUTED) unrouted_comment_ids: the live comments under the named reviews
#              that are feedback, not the city's own post, and sit above the
#              higher of the anchor's two routing marks
#   (COORDS)   pr_coords: the host and owner/repo of a PR url naming the
#              number; a url naming another number, or no PR, sets neither
#   (PHRASE)   approval_phrase: each login once, noun and verb by count
#   (READERS)  every reader sources this file and applies what it reads
#   (NO-COPY)  no other file in the pack defines the rule, applies the
#              retirement inline, or carries the dismissers' PR-url parse or
#              approver list
# Reads the repo only; no gc, no city, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/review-dismissal.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=review-dismissal.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${REVIEW_DISMISSAL_DEF:-}" ] && ok "(DEF) sourcing the file exposes \$REVIEW_DISMISSAL_DEF" \
    || bad "(DEF) sourcing the file exposes \$REVIEW_DISMISSAL_DEF"
for f in pr_coords approval_phrase; do
    [ "$(type -t "$f")" = "function" ] && ok "(DEF) sourcing the file defines $f" || bad "(DEF) sourcing the file defines $f"
done
CITY_OWN_DEF=$("$HERE/pr-post.sh" own-def) || { echo "FAIL - pr-post.sh own-def did not print" >&2; exit 1; }
jq -n "$CITY_OWN_DEF$REVIEW_DISMISSAL_DEF"'1' >/dev/null 2>&1 \
    && ok "(DEF) the defs compile behind pr-post.sh's own-def" \
    || bad "(DEF) the defs compile behind pr-post.sh's own-def"

SELF="gc-city-bot"
rv() { # id login state submitted_at
    printf '{"id":%s,"user":{"login":"%s"},"state":"%s","submitted_at":"%s","body":""}' "$1" "$2" "$3" "$4"
}
cm() { # id review-id login body
    printf '{"id":%s,"pull_request_review_id":%s,"user":{"login":"%s"},"body":"%s","path":"a.sh","line":1}' "$1" "$2" "$3" "$4"
}
# An approval with a comment, a dismissed review with one, a standalone
# comment, a comment naming a review the list does not carry, and the city's
# own review carrying a marked post and an unmarked one.
REVS="[$(rv 11 human1 APPROVED 2026-10-01T00:00:00Z),$(rv 12 human2 DISMISSED 2026-10-02T00:00:00Z),$(rv 13 $SELF COMMENTED 2026-10-03T00:00:00Z)]"
CMTS="[$(cm 101 11 human1 'rename this'),$(cm 102 12 human2 'old point'),$(cm 103 null human3 'standalone'),$(cm 104 99 human4 'orphan'),$(cm 105 13 $SELF '<!-- gc:city --> reply'),$(cm 106 13 $SELF 'operator review on the city account')]"
live() { printf '%s' "$CMTS" | jq -c --argjson revs "$REVS" "$CITY_OWN_DEF$REVIEW_DISMISSAL_DEF"'live_comments($revs) | '"$1"; }
unrouted() { # <rids-json> <anchor-metadata-json>
    printf '%s' "$CMTS" | jq -c --argjson revs "$REVS" --argjson rids "$1" --argjson m "$2" --arg self "$SELF" \
        "$CITY_OWN_DEF$REVIEW_DISMISSAL_DEF"'unrouted_comment_ids($revs; $rids; $m; $self)'
}

echo "# the comments no dismissal has retired"
eq "$(live 'map(.id)')" '[101,103,104,105,106]' \
   "(LIVE) a dismissed review's comment is retired; a standalone comment and one naming an unlisted review stay"
eq "$(live '[ .[] | select(.id == 101) | .gc_review_submitted_at ]')" '["2026-10-01T00:00:00Z"]' \
   "(LIVE) a kept comment carries its review's submission instant"
eq "$(live '[ .[] | select(.id == 103) | has("gc_review_submitted_at") ]')" '[false]' \
   "(LIVE) a standalone comment carries none"

echo "# the feedback a dismissal would retire before it is routed"
eq "$(unrouted '[11]' '{}')" '[101]' "(UNROUTED) a comment under a named review above both marks"
eq "$(unrouted '["11"]' '{}')" '[101]' "(UNROUTED) review ids match as strings too"
eq "$(unrouted '[11]' '{"pr_comment_watermark":"101"}')" '[]' "(UNROUTED) the watermark routed it"
eq "$(unrouted '[11]' '{"pr_comment_watermark":"50","pr_comment_answered":"101"}')" '[]' \
   "(UNROUTED) its thread answered it past the watermark"
eq "$(unrouted '[11]' '{"pr_comment_watermark":"x","pr_comment_answered":""}')" '[101]' \
   "(UNROUTED) a mark that is not a whole number reads as 0"
eq "$(unrouted '[11]' '{"pr_comment_watermark":100}')" '[101]' "(UNROUTED) a numeric mark below it leaves it unrouted"
eq "$(unrouted '[12]' '{}')" '[]' "(UNROUTED) a dismissed review's comments are already retired"
eq "$(unrouted '[14]' '{}')" '[]' "(UNROUTED) a review carrying no comment has none"
eq "$(unrouted '[13]' '{}')" '[]' \
   "(UNROUTED) with no provenance cutover, every post under the city's login is its own"
eq "$(unrouted '[13]' '{"pr_provenance_since":"2026-10-01T00:00:00Z"}')" '[106]' \
   "(UNROUTED) after the cutover the city's marked post is its own, and an unmarked one on its account is feedback"
eq "$(unrouted '[11,13]' '{"pr_provenance_since":"2026-10-01T00:00:00Z"}')" '[101,106]' \
   "(UNROUTED) every named review counts"

echo "# the PR a url names"
coords() { if pr_coords "$1" "$2"; then printf '0|%s|%s' "$PR_HOST" "$PR_REPO"; else printf '1|%s|%s' "$PR_HOST" "$PR_REPO"; fi; }
eq "$(coords https://github.com/zook/gc-toolkit/pull/7 7)" '0|github.com|zook/gc-toolkit' "(COORDS) a PR url naming the number"
eq "$(coords https://ghe.example.com/org/repo/pull/12/files 12)" '0|ghe.example.com|org/repo' "(COORDS) a deeper PR url on another host"
eq "$(coords https://github.com/zook/gc-toolkit/pull/8 7)" '1||' "(COORDS) a url naming another number sets neither"
eq "$(coords https://github.com/zook/gc-toolkit/issues/7 7)" '1||' "(COORDS) a url naming no PR sets neither"
eq "$(coords '' 7)" '1||' "(COORDS) no url sets neither"

echo "# the words naming the approvals"
phrase() { approval_phrase "$1"; printf '%s|%s|%s' "$APPROVERS" "$APPROVAL_NOUN" "$APPROVAL_VERB"; }
eq "$(phrase '[{"id":1,"login":"a"}]')" 'a|approval|is' "(PHRASE) one approval"
eq "$(phrase '[{"id":1,"login":"a"},{"id":2,"login":"a"}]')" 'a|approvals|are' \
   "(PHRASE) an account that approved twice is named once and counted twice"
eq "$(phrase '[{"id":1,"login":"b"},{"id":2,"login":"a"}]')" 'a and b|approvals|are' "(PHRASE) two accounts"
eq "$(phrase '[{"id":1,"login":"c"},{"id":2,"login":"a"},{"id":3,"login":"b"}]')" 'a, b and c|approvals|are' "(PHRASE) three accounts"

echo "# every reader sources the one definition"
reads() { # <file> <what> <pattern>
    grep -qE -- "$3" "$ROOT/$1" && ok "(READERS) $1 $2" || bad "(READERS) $1 $2"
}
for r in assets/scripts/pr-facts.sh assets/scripts/approval-withdraw.sh assets/scripts/bring-current-guard.sh; do
    reads "$r" "sources review-dismissal.sh" '^[[:space:]]*\.[[:space:]].*review-dismissal\.sh'
done
reads assets/scripts/pr-facts.sh "reads the comment space through live_comments" 'REVIEW_DISMISSAL_DEF.*live_comments\(\$revs\)'
reads assets/scripts/approval-withdraw.sh "asks unrouted_comment_ids" 'unrouted_comment_ids\('
for r in assets/scripts/approval-withdraw.sh assets/scripts/bring-current-guard.sh; do
    reads "$r" "names its PR through pr_coords" '^[[:space:]]*(if ! )?pr_coords '
    reads "$r" "names its approvals through approval_phrase" '^[[:space:]]*approval_phrase '
done

echo "# no private copies"
# A copy is a jq def of the rule under any of its names, or the dismissers'
# PR-url parse or approver list. Specs and generated renders are history and
# output, not readers.
copies() { # <regex>
    local d hits out=""
    for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
        [ -d "$ROOT/$d" ] || continue
        hits=$(grep -rlE -- "$1" "$ROOT/$d" 2>/dev/null | grep -vxF "$LIB" | grep -v '\.test\.sh$' || true)
        [ -n "$hits" ] && out="$out $hits"
    done
    printf '%s' "$out" | sed 's#'"$ROOT"'/##g' | tr -s ' ' | sed 's/^ //'
}
eq "$(copies 'def (live_comments|unrouted_comment_ids|comment_routed_through)[[:space:]]*\(')" "" \
   "(NO-COPY) no file but review-dismissal.sh defines the rule"
eq "$(copies 'index\(\$parent\)\) == null')" "" \
   "(NO-COPY) no file but review-dismissal.sh retires a dismissed review's comments inline"
eq "$(copies 's#\^https://\\\(\[\^/\]\*\\\)/\[\^/\]\*/\[\^/\]\*/pull/')" "" \
   "(NO-COPY) no file but review-dismissal.sh parses a PR url the dismissers' way"
eq "$(copies 'join\(", "\)\) \+ " and "')" "" \
   "(NO-COPY) no file but review-dismissal.sh builds the approver list"

echo
echo "review-dismissal: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
