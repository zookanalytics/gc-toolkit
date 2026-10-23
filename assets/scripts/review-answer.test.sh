#!/usr/bin/env bash
# Hermetic test for assets/scripts/review-answer.sh, what the living answer to a
# human review shows. Covers:
#   (DEF)     sourcing the file exposes $REVIEW_ANSWER_DEF, the defs compile, and
#             the program carries no apostrophe
#   (LABEL)   a point's label: the comment's bold lead stripped of severity marks
#             and boilerplate, else the validator's label, else the comment's
#             first sentence cut at a word boundary; brackets escaped
#   (SECTION) each ruling's section and sentence, a flagged fix worth a look, the
#             reference each carries, its fix's commits only once the fix has
#             landed, no point for a body ruled restates, and a decline or a
#             deferral whose thread waits on the reviewer needing them, asking
#             them to act
#   (URL)     a label links only to a comment the read of the PR holds, and the
#             thread a comment sits in is found open or resolved
#   (WAITS)   a thread waits on the reviewer while it is open, holds the answer
#             posted for the finding, and ends with a post of the city, as
#             gc_city_own tells one; a reply of theirs ends the wait until the
#             city answers it
#   (RENDER)  the human-gate callout on top, the count line counting the points that
#             need the reviewer and saying where the rest stand, the sections in
#             order, the entries, the folded notes and the trailing mark lines
#   (MODEL)   one model per review round: the comment already on the PR found
#             by its key, its digest and dismissed mark read back, what keeps it
#             live, the review body answers it delivers, the marks it keeps, each
#             fix unit's landing read from its close, and each point's thread
#             read from the PR
#   (ROUND)   the round a review belongs to, placed alike by the REST reviews
#             the intake reads and the GraphQL nodes the write-back reads: many
#             single-comment reviews against one commit answered by one comment,
#             one review rendered whole, a framing body adding no point, a later
#             commit or another reviewer starting a round of their own, each
#             review of a round dismissed on its own, and the copies of one round
#             folded into one comment losing no mark
#   (DISMISS) the one-line dismissal note
#   (READERS) pr-facts.sh is the one writer and sources this file
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/review-answer.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()   { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()    { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=review-answer.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
# The city-own rule the writer passes to ra_models, as pr-post.sh states it.
CITY_OWN_DEF=$("$HERE/pr-post.sh" own-def) || { echo "FAIL - pr-post.sh own-def did not print" >&2; exit 1; }
[ -n "${REVIEW_ANSWER_DEF:-}" ] && ok "(DEF) sourcing the file exposes \$REVIEW_ANSWER_DEF" \
  || bad "(DEF) sourcing the file exposes \$REVIEW_ANSWER_DEF"
eq "$(jq -n "$REVIEW_ANSWER_DEF"'"compiled"' 2>&1)" '"compiled"' "(DEF) the defs compile"
case "$REVIEW_ANSWER_DEF" in *"'"*) bad "(DEF) the program carries no apostrophe" ;; *) ok "(DEF) the program carries no apostrophe" ;; esac
case "$REVIEW_ANSWER_DEF" in "$REVIEW_OWED_REPLY_DEF"*) ok "(DEF) the defs open with the owed-reply defs every reader of an owed answer shares" ;;
  *) bad "(DEF) the defs open with the owed-reply defs every reader of an owed answer shares" ;; esac
ruled() { jq -rn --arg r "$1" "$REVIEW_OWED_REPLY_DEF"'$r | ra_ruled_reply("'"$2"'")'; }
eq "$(ruled "the cap is a budget" declined)" "Declined: the cap is a budget" "(DEF) a decline reply is led by its ruling"
eq "$(ruled "  declined, since the cap is a budget" declined)" "  declined, since the cap is a budget" "(DEF) …unless it already opens with the word, after any space"
eq "$(ruled "next release" deferred)|$(ruled "Deferred — tracked as follow-up tk-fu." deferred)" "Deferred: next release|Deferred — tracked as follow-up tk-fu." \
  "(DEF) …and a deferral reply the same way"
eq "$(jq -cn "$REVIEW_OWED_REPLY_DEF"'[ "declined", "deferred", "needs-you", "must-fix", "restates", "unvalidated" ] | map(ra_owes_disp)')" \
  '[true,true,true,false,false,false]' "(DEF) a decline, a deferral and a question for the operator owe their raiser an answer"
eq "$(jq -rn "$REVIEW_OWED_REPLY_DEF"'ra_open_ask("declined"), ra_open_ask("deferred")')" \
  "Resolving the thread accepts the decline. To push back, reply in the thread; your reply is ruled as new feedback.
Resolving the thread accepts the deferral. To push back, reply in the thread; your reply is ruled as new feedback." \
  "(DEF) a decline or a deferral answered in a thread says what resolving the thread and replying in it do"

MARKER='<!-- gc-writeback -->'
PRURL="https://github.com/o/r/pull/7"
# A finding record as ra_record builds it, from a few overrides.
rec() { jq -cn --argjson o "${1:-}" '{ id: "F", open: false, disp: "must-fix", message: "", title: "", label: "",
    answer: "", fix_answer: "", fix_flag: "", reply: "", posted: false, follow_up: "", gate: "",
    ruling_bead: "", fix_unit: "", cid: "11", rid: "10", body: false, url: "", waits: false, fix_landed: false } + $o'; }
label() { rec "$1" | jq -r "$REVIEW_ANSWER_DEF"'ra_label'; }
point() { rec "$1" | jq -c "$REVIEW_ANSWER_DEF"'[ ra_point ] | .[0] // "none"'; }
pfield() { point "$1" | jq -r --arg k "$2" 'if type == "object" then (if has($k) then (.[$k] | tostring) else "" end) else . end'; }

echo "# (LABEL)"
eq "$(label '{"message":"🔴 **When GitHub refuses a dismissal, nobody is told.**\n\nBefore this change..."}')" \
  "When GitHub refuses a dismissal, nobody is told." "(LABEL) the bold lead, its severity mark dropped"
eq "$(label '{"message":"**Please fix on this PR: a partial landing writes a mismatched work record.** Each key..."}')" \
  "A partial landing writes a mismatched work record." "(LABEL) …its boilerplate dropped and its first letter raised"
eq "$(label '{"message":"**Small doc fix:** this reads wrong."}')" "Small doc fix" "(LABEL) a bare bold lead is the label as written, less its colon"
eq "$(label '{"message":"Great case for a demo video","label":"A demo video for this change"}')" \
  "A demo video for this change" "(LABEL) no bold lead: the validator's label"
eq "$(label '{"message":"**The cap reads the wrong budget.**","label":"Cap budget"}')" \
  "The cap reads the wrong budget." "(LABEL) …which a bold lead takes precedence over"
eq "$(label '{"message":"Great case for a demo video\n\nAnd more."}')" "Great case for a demo video" "(LABEL) neither: the comment's first sentence"
eq "$(label '{"message":"Should this turn on now? I am not sure."}')" "Should this turn on now?" "(LABEL) …ending at its own mark"
L=$(label '{"message":"This is a very long first sentence that keeps going well past any length a reader would want to scan in one line of the summary."}')
case "$L" in *…) ok "(LABEL) a long first sentence is cut, the cut marked" ;; *) bad "(LABEL) a long first sentence is cut, the cut marked (got '$L')" ;; esac
hasnt "$L" "summary" "(LABEL) …before its end"
hasnt "$L" "scan in one" "(LABEL) …at a word boundary within its first hundred characters"
eq "$(label '{"message":"See [the doc](https://x/y) for why."}')" "See the doc for why." "(LABEL) a link's text stands for the link"
eq "$(label '{"message":"**Rename [a] to [b].**"}')" 'Rename \[a\] to \[b\].' "(LABEL) brackets are escaped for the link text"
eq "$(label '{"message":"","title":"finding[human]: The retry loop could back off"}')" "The retry loop could back off" "(LABEL) no message: the finding's title"

echo "# (SECTION)"
eq "$(pfield '{"disp":"needs-you","open":true,"gate":"tk-v","answer":"Ship it now?"}' section)" "needs" "(SECTION) an open needs-you finding needs the operator"
eq "$(pfield '{"disp":"needs-you","open":true,"gate":"tk-v","answer":"Ship it now?"}' ref)" "tk-v" "(SECTION) …naming its gate"
eq "$(pfield '{"disp":"declined","reply":"the guard already holds"}' section)" "worth" "(SECTION) a declined objection is worth a look"
eq "$(pfield '{"disp":"declined","reply":"the guard already holds"}' sentence)" "Declined: the guard already holds" "(SECTION) …answered by its reply, the ruling first"
eq "$(pfield '{"disp":"declined","reply":"Declined: kept as is"}' sentence)" "Declined: kept as is" "(SECTION) …never with the ruling twice"
eq "$(pfield '{"disp":"declined","reply":"long reason","answer":"Declined: kept as is."}' sentence)" "Declined: kept as is." "(SECTION) …or by the validator's own sentence"
eq "$(pfield '{"disp":"declined"}' section),$(pfield '{"disp":"declined"}' sentence)" "done,Noted; no change asked." "(SECTION) a comment that asked for nothing is done"
eq "$(pfield '{"disp":"deferred","follow_up":"tk-fu","reply":"Deferred — tracked as follow-up tk-fu: later."}' section)" "worth" "(SECTION) a deferral is worth a look"
eq "$(pfield '{"disp":"must-fix","open":true}' section),$(pfield '{"disp":"must-fix","open":true}' answered)" "progress,false" "(SECTION) a must-fix whose fix has not landed is in progress"
eq "$(pfield '{"disp":"must-fix","fix_unit":"tk-k","fix_answer":"Fixed as you suggested."}' section)" "done" "(SECTION) a landed must-fix is done"
eq "$(pfield '{"disp":"must-fix","fix_unit":"tk-k","fix_answer":"Fixed as you suggested."}' ref)" "{{gc-commits:tk-k|11}}" "(SECTION) …citing its fix unit's commits by token"
eq "$(pfield '{"disp":"must-fix","fix_answer":"Chose your option (b).","fix_flag":"1"}' section)" "worth" "(SECTION) a fix the fix unit flagged is worth a look"
eq "$(pfield '{"disp":"declined","fix_answer":"Changed anyway, though the ruling declined it.","fix_flag":"1"}' sentence)" \
  "Changed anyway, though the ruling declined it." "(SECTION) …in the fix unit's words, even over a decline"
FLAGGED='"fix_unit":"tk-k","fix_answer":"Changed anyway, though the ruling declined it.","fix_flag":"1"'
eq "$(pfield '{"disp":"must-fix",'"$FLAGGED"'}' ref)" "{{gc-commits:tk-k|11}}" "(SECTION) a flagged must-fix cites its fix unit's commits once its finding closes"
eq "$(pfield '{"disp":"must-fix","open":true,"fix_landed":true,'"$FLAGGED"'}' ref)" "" \
  "(SECTION) …and none while the finding is open, even once the fix unit it names has closed"
eq "$(pfield '{"disp":"declined","fix_landed":true,'"$FLAGGED"'}' ref)" "{{gc-commits:tk-k|11}}" \
  "(SECTION) a flagged decline cites its fix unit's commits once that fix unit has landed"
eq "$(pfield '{"disp":"declined",'"$FLAGGED"'}' ref)" "" \
  "(SECTION) …and none before, though the decline closed its finding at the ruling"
eq "$(pfield '{"disp":"deferred","follow_up":"tk-fu","fix_landed":true,'"$FLAGGED"'}' ref)" "tk-fu" "(SECTION) a flagged deferral keeps its follow-up"
# A review body sits in no thread, so its entry is the one place the decline or
# deferral it owes reaches the PR, and the entry carries that reply whole.
BODY='"body":true,"cid":"10","rid":"10"'
BFLAG='"fix_answer":"Changed it anyway.","fix_flag":"1"'
eq "$(pfield '{'"$BODY"',"disp":"declined","reply":"We keep Y because Z",'"$BFLAG"'}' sentence)" "Changed it anyway." \
  "(SECTION) a review body's flagged decline answers in the fix unit's words"
eq "$(pfield '{'"$BODY"',"disp":"declined","reply":"We keep Y because Z",'"$BFLAG"'}' extra)" "Declined: We keep Y because Z" \
  "(SECTION) …and still carries the decline it owes, quoted under the entry"
eq "$(pfield '{'"$BODY"',"disp":"deferred","follow_up":"tk-fu","reply":"Deferred — tracked as follow-up tk-fu: later.",'"$BFLAG"'}' extra)" \
  "Deferred — tracked as follow-up tk-fu: later." "(SECTION) …and so does a flagged deferral"
eq "$(pfield '{'"$BODY"',"disp":"declined","reply":"We keep Y because Z","answer":"Declined: kept as is."}' extra)" "Declined: We keep Y because Z" \
  "(SECTION) a body decline the validator answered in its own words quotes the reply it owes"
eq "$(pfield '{'"$BODY"',"disp":"declined","reply":"We keep Y because Z"}' sentence)|$(pfield '{'"$BODY"',"disp":"declined","reply":"We keep Y because Z"}' extra)" \
  "Declined: We keep Y because Z|" "(SECTION) a body decline whose sentence is the reply quotes nothing more"
LONGREPLY=$(jq -cn '{body: true, cid: "10", rid: "10", disp: "declined", reply: ("because " * 400)}')
eq "$(pfield "$LONGREPLY" sentence)" "Declined; the reason follows." "(SECTION) a body decline too long for a sentence leads with the ruling"
LONGQUOTE=$(pfield "$LONGREPLY" extra)
eq "${#LONGQUOTE}" "3209" "(SECTION) …and quotes its reply whole, never cut at the sentence cap"
eq "$(pfield '{"disp":"declined","reply":"We keep Y","fix_answer":"Changed anyway.","fix_flag":"1"}' extra)" "" \
  "(SECTION) an inline comment's decline quotes nothing: its thread carries the reply"
eq "$(pfield '{'"$BODY"',"disp":"needs-you","open":true,"gate":"tk-v","answer":"Ship it now?","reply":"This comment needs your decision — filed human gate tk-v."}' extra)" "" \
  "(SECTION) a body question for the operator quotes nothing: the entry names its gate"
eq "$(pfield '{"disp":"needs-you","ruling_bead":"tk-v"}' sentence)" "Settled by your ruling on tk-v." "(SECTION) a needs-you finding the ruling settled is done"
eq "$(pfield '{"disp":"unvalidated","open":true}' section),$(pfield '{"disp":"unvalidated","open":true}' ruled)" "progress,false" "(SECTION) an unruled point is in progress"
eq "$(point '{"disp":"restates","body":true,"cid":"10"}')" '"none"' "(SECTION) a body ruled restates is no point"
# The write-back never resolves a thread holding a decline or a deferral it
# answered there, so the point needs the reviewer while that thread waits on
# them (the record's waits, read off the thread by ra_thread_waits below), and
# is worth a look once it does not.
WAIT='"waits":true,"reply":"the guard already holds"'
eq "$(pfield '{"disp":"declined",'"$WAIT"'}' section)" "needs" "(SECTION) a decline whose thread waits on the reviewer needs them"
eq "$(pfield '{"disp":"declined",'"$WAIT"'}' sentence)" "Declined: the guard already holds" "(SECTION) …in the words it is answered with"
eq "$(pfield '{"disp":"declined",'"$WAIT"'}' ask)" "Resolving the thread accepts the decline. To push back, reply in the thread; your reply is ruled as new feedback." \
  "(SECTION) …asking them to accept it by resolving the thread, or to push back by replying there, which is ruled as new feedback"
WAITD='"disp":"deferred","follow_up":"tk-fu","waits":true,"reply":"Deferred — tracked as follow-up tk-fu: later."'
eq "$(pfield '{'"$WAITD"'}' section)|$(pfield '{'"$WAITD"'}' ask)" \
  "needs|Resolving the thread accepts the deferral. To push back, reply in the thread; your reply is ruled as new feedback." "(SECTION) …and so does a deferral whose thread waits on them"
eq "$(pfield '{"disp":"declined","reply":"the guard already holds"}' section)|$(pfield '{"disp":"declined","reply":"the guard already holds"}' ask)" \
  "worth|" "(SECTION) a decline whose thread does not wait on the reviewer is worth a look and asks nothing"
eq "$(pfield '{"disp":"declined","waits":true}' section)" "done" "(SECTION) a comment that asked for nothing is done, whatever its thread"
WAITF='"disp":"declined","waits":true,"reply":"kept as is","fix_unit":"tk-k","fix_answer":"Renamed anyway, though the ruling declined it.","fix_flag":"1"'
eq "$(pfield '{'"$WAITF"'}' section)|$(pfield '{'"$WAITF"'}' sentence)" "needs|Renamed anyway, though the ruling declined it." \
  "(SECTION) a flagged decline whose thread waits on the reviewer needs them, in the fix unit's words"
eq "$(pfield '{"disp":"must-fix","waits":true,"fix_unit":"tk-k","fix_answer":"Fixed."}' section)" "done" \
  "(SECTION) a landed must-fix waits on nobody, since the write-back resolves its thread"

echo "# (URL)"
VIEW='{"reviews":[{"databaseId":10,"url":""}],"threads":[{"comments":{"nodes":[{"databaseId":11,"url":"https://github.com/o/r/pull/7#discussion_r11"}]}}],"issue_comments":[]}'
url() { rec "$1" | jq -r --argjson v "$VIEW" --arg p "$PRURL" "$REVIEW_ANSWER_DEF"'ra_url($v; $p)'; }
eq "$(url '{"cid":"11"}')" "https://github.com/o/r/pull/7#discussion_r11" "(URL) an inline comment links to its thread as GitHub names it"
eq "$(url '{"cid":"10","body":true}')" "$PRURL#pullrequestreview-10" "(URL) a review body links to its review"
eq "$(url '{"cid":"99"}')" "" "(URL) a comment the read does not hold gets no link"
TVIEW='{"reviews":[{"databaseId":10}],"issue_comments":[],
  "threads":[{"id":"T1","isResolved":false,"comments":{"nodes":[{"databaseId":11}]}},{"id":"T2","isResolved":true,"comments":{"nodes":[{"databaseId":12},{"databaseId":13}]}}]}'
tfind() { jq -rn --argjson v "$TVIEW" --arg c "$1" "$REVIEW_OWED_REPLY_DEF"'ra_comment_thread($v; $c) | if . == null then "none" else .id + ":" + (if ra_thread_open then "open" else "resolved" end) end'; }
eq "$(tfind 11)|$(tfind 13)" "T1:open|T2:resolved" "(URL) the thread a comment sits in is found wherever in it the comment sits, open or resolved"
eq "$(tfind 99)|$(tfind "")" "none|none" "(URL) …and a comment the read does not hold has none"
eq "$(rec '{"cid":"13"}' | jq -r --argjson v "$TVIEW" --arg p "$PRURL" "$REVIEW_ANSWER_DEF"'ra_url($v; $p; ra_comment_thread($v; "13"))')" "$PRURL#discussion_r13" \
  "(URL) the link reads a thread already found, which is how a record looks its thread up once"

echo "# (WAITS)"
# A point waits on the reviewer while its thread is open, holds the answer
# posted for its finding, and ends with a post of the city. The writer passes
# gc_city_own, the rule the routing arm tells feedback by.
ANS='{"author":{"login":"bot"},"body":"❓ Declined: the guard already holds\n\nResolving the thread accepts the decline. To push back, reply in the thread; your reply is ruled as new feedback.\n<!-- gc-writeback -->\n<!-- gc-writeback-finding:F -->"}'
REPLY='{"databaseId":20,"author":{"login":"op"},"body":"I still think the guard should go."}'
FIXED='{"author":{"login":"bot"},"body":"✅ Fixed in 6c6c6c6c (tk-k2).\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:resolved -->"}'
thread() { # comments-after-the-raising-one [resolved]
  jq -cn --argjson cs "$1" --argjson r "${2:-false}" \
    '{id:"T1",isResolved:$r,comments:{nodes:([{databaseId:11,author:{login:"op"},body:"**Keep the guard?**"}] + $cs)}}'
}
waits() { # thread-json [cutover] — whether it waits on the reviewer for finding F
  jq -rn --argjson t "$1" --arg since "${2:-}" "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'
    ra_thread_waits($t; "bot"; "<!-- gc-writeback -->"; "F"; "the guard already holds"; gc_city_own("bot"; $since))'
}
eq "$(waits "$(thread "[$ANS]")")" "true" "(WAITS) an open thread holding the answer, and ending with it, waits on the reviewer"
eq "$(waits "$(thread "[$ANS]" true)")" "false" "(WAITS) …and once they resolve it, does not"
eq "$(waits "$(thread "[$ANS,$REPLY]")")" "false" "(WAITS) a reply of theirs after the answer ends the wait, since the reply is a point of its own"
eq "$(waits "$(thread "[$ANS,$REPLY,$FIXED]")")" "true" \
  "(WAITS) …until the city answers the reply: the thread it leaves open, holding the decline, waits on them again"
eq "$(waits "$(thread '[]')")|$(waits null)" "false|false" "(WAITS) a thread the answer never reached asks nothing, and nor does a comment in no thread"
CITYPOST='{"author":{"login":"bot"},"body":"More on why the guard stays.\n<!-- gc:city -->","createdAt":"2026-02-01T00:00:00Z"}'
UNMARKED='{"author":{"login":"bot"},"body":"Please drop the guard anyway.","createdAt":"2026-02-01T00:00:00Z"}'
eq "$(waits "$(thread "[$ANS,$CITYPOST]")" 2026-01-01T00:00:00Z)" "true" "(WAITS) a post of the city after the answer leaves it waiting"
eq "$(waits "$(thread "[$ANS,$UNMARKED]")" 2026-01-01T00:00:00Z)" "false" \
  "(WAITS) …but an unmarked post under the city login after the cutover is feedback, as the routing arm reads it, and ends the wait"
OTHER='{"author":{"login":"bot"},"body":"❓ Declined: the guard already holds\n<!-- gc-writeback -->\n<!-- gc-writeback-finding:G -->"}'
OLDFORM='{"author":{"login":"bot"},"body":"Declined: the guard already holds\n<!-- gc-writeback -->"}'
REPLACED='{"author":{"login":"bot"},"body":"❓ Declined: an older reason\n<!-- gc-writeback -->\n<!-- gc-writeback-finding:F -->"}'
eq "$(waits "$(thread "[$OTHER]")")" "false" "(WAITS) an answer naming another finding is not this one"
eq "$(waits "$(thread "[$OLDFORM]")")" "true" "(WAITS) an answer posted before answers named their finding is this one when it carries its text"
eq "$(waits "$(thread "[$REPLACED]")")" "false" "(WAITS) …and the answer to a ruling since replaced, whose text differs, is not"

echo "# (RENDER)"
MODEL='{"rid":"10","rids":["10"],"self":false,"members":[{"rid":"10","state":"CHANGES_REQUESTED","dismissed":"requeued"}],
  "points":[
    {"id":"a","section":"worth","label":"Guard rewrites the opt-out","url":"U1","sentence":"You asked for a decision, and the fix chose your second option.","ref":"","answered":true,"ruled":true,"extra":""},
    {"id":"b","section":"done","label":"A refused dismissal tells nobody.","url":"","sentence":"Fixed with your option (a).","ref":"{{gc-commits:k|3}}","answered":true,"ruled":true,"extra":""},
    {"id":"c","section":"worth","label":"Retry loop","url":"","sentence":"Deferred to tk-fu: later.","ref":"tk-fu","answered":true,"ruled":true,"extra":""}],
  "gates":[{"id":"tk-v1","question":"Should enforcement turn on now?"}],
  "notes":[{"by":"k","text":"Notes here."}],
  "marks":["resolved r10"]}'
R=$(printf '%s' "$MODEL" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
case "$R" in "> [!IMPORTANT]"*) ok "(RENDER) an open human gate leads the comment" ;; *) bad "(RENDER) an open human gate leads the comment (got: $R)" ;; esac
has "$R" "> **Needs you: human gate tk-v1.** Should enforcement turn on now?" "(RENDER) …naming the gate and its question"
has "$R" "### Your review: 3 points, all answered
" "(RENDER) the count line says every point is answered"
hasnt "$R" "answered at" "(RENDER) …naming no commit, so a push leaves a settled review comment as it stands"
has "$R" "Review dismissed; your review is requested again. 2 worth a look, 1 done." "(RENDER) the dismissal and the section counts follow it"
has "$R" "**Worth a look**
- **[Guard rewrites the opt-out.](U1)** You asked for a decision, and the fix chose your second option." "(RENDER) an entry: a linked label, its sentence"
has "$R" "- **Retry loop.** Deferred to tk-fu: later." "(RENDER) a reference the sentence already names is left out"
has "$R" "**Done**
- **A refused dismissal tells nobody.** Fixed with your option (a).{{gc-commits:k|3}}" "(RENDER) a commit token rides after the sentence for the writer to cite"
case "$R" in *"**Worth a look**"*"**Done**"*) ok "(RENDER) the sections come in order" ;; *) bad "(RENDER) the sections come in order" ;; esac
has "$R" "<details>
<summary>Notes from the fix</summary>

Notes here.

</details>" "(RENDER) the fix notes are folded"
has "$R" "$MARKER
<!-- gc-writeback-mark:resolved r10 -->
<!-- gc-review-answer:r10 -->
<!-- gc-review-answer:r10:dismissed -->" "(RENDER) it ends with the marker, its mark lines, its review key and the dismissed mark"
hasnt "$R" "in its thread" "(RENDER) no sentence points at a reply or thread"
R2=$(printf '%s' "$MODEL" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'.gates = [] | .members[0].dismissed = "" | .notes = [] | .points[0].sentence = "Guard rewrites the opt-out" | ra_render($m)')
case "$R2" in "### Your review"*) ok "(RENDER) with no open human gate the count line leads" ;; *) bad "(RENDER) with no open human gate the count line leads (got: $R2)" ;; esac
has "$R2" "- **[Guard rewrites the opt-out.](U1)**
" "(RENDER) a sentence that only repeats the label is left out"
hasnt "$R2" "Review dismissed" "(RENDER) an undismissed review says nothing of a dismissal"
hasnt "$R2" ":dismissed -->" "(RENDER) …and carries no dismissed mark"
P=$(printf '%s' "$MODEL" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'.gates = [] | .members[0].dismissed = "" | .points = [ .points[] | .ruled = false | .answered = false | .section = "progress" | .sentence = "" ] | ra_render($m)')
has "$P" "### Your review: 3 points, picked up; the ruling is in progress" "(RENDER) at pickup the count line says the ruling is in progress"
hasnt "$P" "Not ruled yet" "(RENDER) …and no entry repeats it"
hasnt "$P" "in progress." "(RENDER) …nor adds a count line"
heading() { jq -rn --argjson ps "$1" "$REVIEW_ANSWER_DEF"'{ points: $ps } | ra_heading'; }
eq "$(heading '[{"section":"needs","answered":true,"ruled":true},{"section":"needs","answered":false,"ruled":true}]')" \
  "Your review: 2 points, 2 need you" "(RENDER) the count line counts the points that need the reviewer, answered or not"
eq "$(heading '[{"section":"needs","answered":true,"ruled":true},{"section":"done","answered":true,"ruled":true}]')" \
  "Your review: 2 points, 1 needs you, 1 answered" "(RENDER) …and never reads all answered while one does"
eq "$(heading '[{"section":"needs","answered":true,"ruled":true},{"section":"done","answered":true,"ruled":true},{"section":"progress","answered":false,"ruled":true}]')" \
  "Your review: 3 points, 1 needs you, 1 answered, the rest not answered yet" "(RENDER) …and says the rest are not answered yet, once every point is ruled"
NEEDS1='{"section":"needs","answered":false,"ruled":true}'
UNRULED='{"section":"progress","answered":false,"ruled":false}'
eq "$(heading "[$NEEDS1,$UNRULED,$UNRULED]")" "Your review: 3 points, 1 needs you, the rest in progress" \
  "(RENDER) a point that needs the reviewer beside two not yet ruled leaves the rest in progress, not unsaid"
eq "$(heading "[$NEEDS1,{\"section\":\"done\",\"answered\":true,\"ruled\":true},$UNRULED]")" "Your review: 3 points, 1 needs you, 1 answered, the rest in progress" \
  "(RENDER) …and so does one beside an answered point and an unruled one"
eq "$(heading "[$NEEDS1,{\"section\":\"progress\",\"answered\":false,\"ruled\":true}]")" "Your review: 2 points, 1 needs you, the rest not answered yet" \
  "(RENDER) …and a fix in progress beside it is the rest not answered yet"

BIG=$(jq -n --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'{rid:"1",self:false,
  points:[{id:"a",section:"done",label:"L",url:"",sentence:("word " * 600),ref:"",answered:true,ruled:true,extra:""}],
  gates:[],notes:[{by:"k",text:("n " * 9000)}],marks:[]} | ra_render($m) | length')
[ "$BIG" -lt 15000 ] && ok "(RENDER) a long sentence and long notes are clipped, so the comment stays postable ($BIG characters)" \
  || bad "(RENDER) a long sentence and long notes are clipped, so the comment stays postable (got $BIG characters)"
CLIPPED=$(jq -rn --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'{rid:"1",self:false,
  points:[{id:"tk-f1",section:"done",label:"L",url:"",sentence:("word " * 600),ref:"",answered:true,ruled:true,extra:""}],
  gates:[],notes:[{by:"tk-k",text:("n " * 9000)}],marks:[]} | ra_render($m)')
has "$CLIPPED" "… (the full text is on tk-f1)" "(RENDER) a clipped sentence names the finding that holds it whole"
has "$CLIPPED" "… (the full text is on tk-k)" "(RENDER) …and clipped notes name the fix unit that holds them"
FENCE=$(jq -rn --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'{rid:"1",self:false,points:[],gates:[],
  notes:[{by:"tk-k",text:("Before.\n\n```\n" + ("line\n" * 4000) + "```\n\nAfter.")}],marks:[]} | ra_render($m)')
eq "$(printf '%s' "$FENCE" | grep -c '^```$')" "2" "(RENDER) notes cut inside a code block get the block closed, so the cut swallows nothing after it"
has "$FENCE" "</details>" "(RENDER) …and the notes block still closes"

echo "# (BUDGET)"
eq "$(jq -rn "$REVIEW_ANSWER_DEF"'"{{gc-commits:tk-k|11}}" | ra_size')" "102" \
  "(BUDGET) a commit token counts its own 22 bytes plus room for the longest citation it can expand to"
eq "$(jq -rn "$REVIEW_ANSWER_DEF"'"✅" | ra_size')" "3" "(BUDGET) the size is UTF-8 bytes, never fewer than characters"
# A review too long for one comment at the loosest caps: forty points, each
# with a long sentence and a long quoted reply, and long notes from two fix units.
HUGE=$(jq -cn '{rid:"9",self:false,members:[{rid:"9",state:"DISMISSED",dismissed:"requeued"}],
  points:[ range(40) as $i | {id:("tk-p" + ($i|tostring)),section:(if $i < 5 then "worth" else "done" end),label:("Point " + ($i|tostring)),
           url:"",sentence:("said " * 400),ref:"{{gc-commits:tk-k|1}}",answered:true,ruled:true,extra:("quoted " * 700)} ],
  gates:[{id:"tk-v9",question:"Ship it now?"}],
  notes:[{by:"tk-k",text:("n " * 9000)},{by:"tk-k2",text:("m " * 9000)}],marks:["resolved r9"]}')
HR=$(printf '%s' "$HUGE" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
HS=$(printf '%s' "$HR" | jq -Rs "$REVIEW_ANSWER_DEF"'ra_size')
[ "$HS" -le 60000 ] && ok "(BUDGET) a review too long for one comment renders within the budget ($HS bytes)" \
  || bad "(BUDGET) a review too long for one comment renders within the budget (got $HS bytes)"
has "$HR" "The notes from the fix are on tk-k, tk-k2, left out here to fit the size GitHub allows a comment." \
  "(BUDGET) the notes go first, naming the fix units they are on"
has "$HR" "(the full text is on tk-p0)" "(BUDGET) …then quotes and sentences are cut harder, each cut naming its finding"
has "$HR" "- **Point 39.**" "(BUDGET) …and every point still has its entry"
has "$HR" "### Your review: 40 points, all answered" "(BUDGET) the count line still covers every point"
has "$HR" "> **Needs you: human gate tk-v9.** Ship it now?" "(BUDGET) …and the callout still leads"
case "$HR" in *"$MARKER
<!-- gc-writeback-mark:resolved r9 -->
<!-- gc-review-answer:r9 -->
<!-- gc-review-answer:r9:dismissed -->") ok "(BUDGET) the trailing lines stay whole" ;; *) bad "(BUDGET) the trailing lines stay whole" ;; esac
# Past the tightest caps, the points are listed from the top until they fit.
MANY=$(jq -cn '{rid:"8",self:false,
  points:[ range(400) as $i | {id:("tk-q" + ($i|tostring)),section:(if $i == 0 then "worth" else "done" end),label:("A point whose label runs long enough to matter " + ($i|tostring)),
           url:"https://github.com/o/r/pull/7#discussion_r1234567890",sentence:("said " * 400),ref:"{{gc-commits:tk-k|1}}",answered:true,ruled:true,extra:""} ],
  gates:[],notes:[],marks:[]}')
MR=$(printf '%s' "$MANY" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
MS=$(printf '%s' "$MR" | jq -Rs "$REVIEW_ANSWER_DEF"'ra_size')
[ "$MS" -le 60000 ] && ok "(BUDGET) four hundred points render within the budget ($MS bytes)" \
  || bad "(BUDGET) four hundred points render within the budget (got $MS bytes)"
has "$MR" "### Your review: 400 points, all answered" "(BUDGET) the count line covers every point"
has "$MR" "- **[A point whose label runs long enough to matter 0.]" "(BUDGET) the points worth a look come first"
has "$MR" "more points are left out here to fit the size GitHub allows a comment; their findings are tk-q" "(BUDGET) …and a line names the findings of the points left out"
hasnt "$MR" "A point whose label runs long enough to matter 399." "(BUDGET) …the last of which have no entry"

echo "# (MODEL)"
ROWS='[
 {"id":"B","status":"closed","title":"finding[human]: s","description":"Locus: PR review\n\nSummary of the inline points.\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"declined","finding.comment_id":"10","finding.review_id":"10","finding.reply":"the cap is a budget"}},
 {"id":"I","status":"open","title":"finding[human]: i","description":"Locus: a.sh:1\n\n**Fix the cap.**\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"must-fix","finding.comment_id":"11","finding.review_id":"10","finding.fix_unit":"K"}},
 {"id":"M","status":"open","title":"finding[correctness]: m","metadata":{"task_kind":"finding","finding.lane":"correctness","finding.disposition":"must-fix"}},
 {"id":"C","status":"open","title":"finding[human]: c","description":"Locus: PR conversation\n\nand rename it\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"unvalidated","finding.comment_id":"50"}}]'
VIEW2='{"reviews":[{"databaseId":10,"state":"COMMENTED","author":{"login":"op"},"url":""}],
  "threads":[{"comments":{"nodes":[{"databaseId":11}]}}],
  "issue_comments":[
    {"databaseId":900,"author":{"login":"bot"},"body":"x\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:resolved r10 -->\n<!-- gc-review-answer:r10 -->\n<!-- gc-review-answer:r10:dismissed -->\n<!-- gc-review-answer:r10:digest:12345 -->"},
    {"databaseId":901,"author":{"login":"op"},"body":"<!-- gc-writeback -->\n<!-- gc-review-answer:r10 -->"}]}'
models() { printf '%s' "$ROWS" | jq -c --argjson v "$1" --argjson vl "${2:-}" --argjson b '{"K":{"title":"rework","fix_notes":"notes from K"}}' \
  --arg m "$MARKER" "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; $vl; $b; $m; gc_city_own("bot"; ""))'; }
M=$(models "$VIEW2" '{}')
eq "$(printf '%s' "$M" | jq 'length')" "1" "(MODEL) one model per review: a machine finding and a Conversation comment belong to none"
eq "$(printf '%s' "$M" | jq -r '.[0].existing.db + " " + .[0].existing.digest')" "900 12345" "(MODEL) the comment on the PR is ours carrying the review key, with its digest read back"
eq "$(printf '%s' "$M" | jq -r '.[0].existing.url')" "$PRURL#issuecomment-900" "(MODEL) …and its link"
eq "$(printf '%s' "$M" | jq -r "$REVIEW_ANSWER_DEF"'.[0] | ra_dismissal')" "requeued" "(MODEL) a dismissed mark on it reads as the dismissal the writer made"
eq "$(printf '%s' "$M" | jq -r '.[0].marks | join(",")')" "resolved r10" "(MODEL) the marks it carries stand while the plan names none"
eq "$(models "$VIEW2" '{"10":{"marks":["awaiting:tk-v r10"],"gates":["tk-v"],"swaps":"-"}}' | jq -r '.[0].marks | join(",")')" "awaiting:tk-v r10" "(MODEL) …and give way to the ones it names"
eq "$(printf '%s' "$M" | jq -r '.[0].live')" "true" "(MODEL) an open finding keeps the review live"
eq "$(printf '%s' "$M" | jq -c '[ .[0].replied, .[0].unstamped ]')" '[["B"],["B"]]' "(MODEL) the review body's decline is an answer it delivers, not yet stamped"
eq "$(printf '%s' "$M" | jq -r '.[0].notes[0].text')" "notes from K" "(MODEL) the fix unit's notes come with it"
eq "$(printf '%s' "$M" | jq -r '[ .[0].points[].id ] | join(",")')" "B,I" "(MODEL) the body leads its inline comments"
DONE_ROWS=$(printf '%s' "$ROWS" | jq -c 'map(if .id == "I" then .status = "closed" else . end | if .id == "B" then .metadata["finding.reply_posted"] = "1" else . end)')
eq "$(printf '%s' "$DONE_ROWS" | jq -c --argjson v "$(printf '%s' "$VIEW2" | jq -c '.issue_comments = [] | .reviews[0].state = "DISMISSED"')" \
  --arg m "$MARKER" "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; {}; {}; $m; gc_city_own("bot"; "")) | .[0] | [ .live, ra_dismissal ]')" '[false,"plain"]' \
  "(MODEL) a dismissed review with every finding closed and nothing owed is not live, and reads dismissed without a re-request claim"
eq "$(printf '%s' "$DONE_ROWS" | jq -c --argjson v "$(printf '%s' "$VIEW2" | jq -c '.issue_comments = [] | .reviews[0].state = "DISMISSED" | .requested = ["op"]')" \
  --arg m "$MARKER" "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; {}; {}; $m; gc_city_own("bot"; "")) | .[0] | ra_dismissal')" '"requeued"' \
  "(MODEL) …and reads re-requested when its author has a pending review request, though no comment carries the dismissed mark"
eq "$(printf '%s' "$DONE_ROWS" | jq -c --argjson v "$(printf '%s' "$VIEW2" | jq -c '.issue_comments = [] | .reviews[0].state = "COMMENTED"')" \
  --arg m "$MARKER" "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; {"10":{"marks":["resolved r10"],"gates":[],"swaps":"-"}}; {}; $m; gc_city_own("bot"; "")) | .[0].live')" "true" \
  "(MODEL) a mark the plan asks of it keeps it live, so a body answered after its findings closed still gets its answer"
eq "$(printf '%s' "$DONE_ROWS" | jq -c --argjson v "$(printf '%s' "$VIEW2" | jq -c '.issue_comments = [] | .reviews[0].state = "CHANGES_REQUESTED"')" \
  --arg m "$MARKER" "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; {}; {}; $m; gc_city_own("bot"; "")) | .[0].live')" "true" \
  "(MODEL) a standing changes-requested block keeps it live"
FL_ROWS='[{"id":"D","status":"closed","title":"finding[human]: d","description":"Locus: a.sh:2\n\n**Rename the cap.**\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"declined","finding.comment_id":"11","finding.review_id":"10",
              "finding.fix_unit":"K","finding.fix_flag":"1","finding.fix_answer":"Renamed anyway, though the ruling declined it."}}]'
flref() { printf '%s' "$FL_ROWS" | jq -r --argjson v "$VIEW2" --argjson b "$1" --arg m "$MARKER" \
  "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; {}; $b; $m; gc_city_own("bot"; "")) | .[0].points[0].ref'; }
eq "$(flref '{"K":{"title":"rework","fix_notes":"","closed":true}}')" "{{gc-commits:K|11}}" \
  "(MODEL) a flagged decline reads its fix unit's landing from the close read for it"
eq "$(flref '{"K":{"title":"rework","fix_notes":"","closed":false}}')" "" "(MODEL) …so a fix unit still open cites nothing"
eq "$(flref '{}')" "" "(MODEL) …and neither does one that did not read back"
# The writer stamps each review body answer in unstamped delivered once the
# comment carries the rendering, so the rendering has to hold every one.
DL_ROWS='[{"id":"D2","status":"closed","title":"finding[human]: d2","description":"Locus: PR review\n\nA summary with a point of its own.\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"declined","finding.comment_id":"10","finding.review_id":"10",
              "finding.reply":"We keep Y because Z","finding.fix_unit":"K","finding.fix_flag":"1","finding.fix_answer":"Changed it anyway."}}]'
DLM=$(printf '%s' "$DL_ROWS" | jq -c --argjson v "$VIEW2" --arg m "$MARKER" "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; {}; {}; $m; gc_city_own("bot"; "")) | .[0]')
eq "$(printf '%s' "$DLM" | jq -c '.unstamped')" '["D2"]' "(MODEL) a flagged review body decline is an answer the comment delivers"
has "$(printf '%s' "$DLM" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')" "  > Declined: We keep Y because Z" \
  "(MODEL) …and the rendering it is stamped against carries it"
# A decline answered in its thread, beside a landed fix, as the read of the PR
# finds the decline's thread: waiting on the reviewer while it is open, holds
# the answer and ends with a post of the city, and not once they resolve it,
# reply in it, or when the answer never reached it.
WROWS='[{"id":"W1","status":"closed","title":"finding[human]: w1","description":"Locus: a.sh:1\n\n**The barrier now runs once per page.**\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"declined","finding.comment_id":"11","finding.review_id":"10","finding.reply":"the count query is paged, so the barrier runs per page.","finding.reply_posted":"1"}},
 {"id":"W2","status":"closed","title":"finding[human]: w2","description":"Locus: a.sh:2\n\n**Fix the cap.**\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"must-fix","finding.comment_id":"12","finding.review_id":"10","finding.fix_unit":"K","finding.fix_answer":"Fixed as you suggested."}}]'
WANS='{"author":{"login":"bot"},"body":"❓ Declined: the count query is paged, so the barrier runs per page.\n\nResolving the thread accepts the decline. To push back, reply in the thread; your reply is ruled as new feedback.\n<!-- gc-writeback -->\n<!-- gc-writeback-finding:W1 -->"}'
wview() { # whether the read finds the decline thread resolved, and the posts after its comment
  jq -cn --argjson r "$1" --argjson cs "${2:-[]}" '{ reviews: [{databaseId:10,state:"COMMENTED",author:{login:"op"},commit:{oid:"c1"},url:""}],
    threads: [{isResolved:$r,comments:{nodes:([{databaseId:11,author:{login:"op"},url:"https://github.com/o/r/pull/7#discussion_r11"}] + $cs)}},
              {isResolved:true,comments:{nodes:[{databaseId:12,url:"https://github.com/o/r/pull/7#discussion_r12"}]}}],
    issue_comments: [] }'
}
wmodel() { printf '%s' "$WROWS" | jq -c --argjson v "$(wview "$1" "${2:-[$WANS]}")" --arg m "$MARKER" \
  "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; {}; {"K":{"closed":true}}; $m; gc_city_own("bot"; "")) | .[0]'; }
WOPEN=$(wmodel false | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
has "$WOPEN" "### Your review: 2 points, 1 needs you, 1 answered
" "(MODEL) a decline whose open thread holds its answer, and ends with it, is counted as needing the reviewer"
hasnt "$WOPEN" "all answered" "(MODEL) …so the count line does not read all answered while it waits"
has "$WOPEN" "**Needs you**
- **[The barrier now runs once per page.](https://github.com/o/r/pull/7#discussion_r11)** Declined: the count query is paged, so the barrier runs per page.
  Resolving the thread accepts the decline. To push back, reply in the thread; your reply is ruled as new feedback.

**Done**" "(MODEL) …and listed under Needs you, what it asks on a line of its own"
hasnt "$WOPEN" "[!IMPORTANT]" "(MODEL) …with no gate callout, since no gate carries it"
WDONE=$(wmodel true | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
WLOOK="**Worth a look**
- **[The barrier now runs once per page.](https://github.com/o/r/pull/7#discussion_r11)** Declined: the count query is paged, so the barrier runs per page.

**Done**"
has "$WDONE" "### Your review: 2 points, all answered
" "(MODEL) once the reviewer resolves the thread, the count line reads all answered"
has "$WDONE" "$WLOOK" "(MODEL) …and the decline is worth a look"
hasnt "$WDONE" "Needs you" "(MODEL) …with nothing shown as needing the reviewer"
hasnt "$WDONE" "Resolving the thread" "(MODEL) …and nothing asked of them"
WREPLY='{"databaseId":13,"author":{"login":"op"},"body":"Paging is fine, but say so in a comment."}'
WREPLIED=$(wmodel false "[$WANS,$WREPLY]" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
has "$WREPLIED" "$WLOOK" "(MODEL) a reply of the reviewer after the decline puts it under Worth a look, since the reply is a point of its own"
hasnt "$WREPLIED" "Resolving the thread" "(MODEL) …asking them nothing more"
WUNPOSTED=$(wmodel false '[]' | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
has "$WUNPOSTED" "$WLOOK" "(MODEL) an open thread the decline never reached leaves it worth a look"
hasnt "$WUNPOSTED" "Resolving the thread" "(MODEL) …with no request, since the thread holds nothing to accept"
WFIX='{"author":{"login":"bot"},"body":"✅ Fixed in 6c6c6c6c (tk-k2).\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:resolved -->"}'
WAGAIN=$(wmodel false "[$WANS,$WREPLY,$WFIX]" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
has "$WAGAIN" "### Your review: 2 points, 1 needs you, 1 answered
" "(MODEL) once the city answers the reply, the thread it leaves open waits on the reviewer again"
has "$WAGAIN" "**Needs you**
- **[The barrier now runs once per page.](https://github.com/o/r/pull/7#discussion_r11)** Declined: the count query is paged, so the barrier runs per page.
  Resolving the thread accepts the decline." "(MODEL) …and the decline needs them again, asking them to resolve it"

echo "# (ROUND)"
eq "$(jq -nc "$REVIEW_ROUND_DEF"'[ ra_round_key("op"; "c1"), ra_round_key("op"; null), ra_round_key(""; "c1") ]')" '["op@c1","",""]' \
  "(ROUND) a review round is named by its reviewer and its commit, and by nothing when either is unknown"
eq "$(jq -nc "$REVIEW_ROUND_DEF"'{reviews:[{databaseId:5,author:{login:"op"},commit:{oid:"c1"}},{databaseId:6,author:{login:"op"},commit:null}]} | ra_rounds(.)')" \
  '{"5":"op@c1","6":"r6"}' "(ROUND) a review the read cannot place by author and commit is a round of its own"
eq "$(jq -nc "$REVIEW_ROUND_DEF"'[ ([{id:5,user:{login:"op"},commit_id:"c1"},{id:6,user:{login:"op"},commit_id:null}] | ra_review_rounds),
      ([{id:"PRR_5",databaseId:5,author:{login:"op"},commit:{oid:"c1"}},{id:"PRR_6",databaseId:6,author:{login:"op"},commit:null}] | ra_review_rounds) ]')" \
  '[{"5":"op@c1"},{"5":"op@c1"}]' "(ROUND) the REST reviews the intake reads and the GraphQL nodes the write-back reads place a review in one round, and leave out one they cannot place"
case "$REVIEW_ANSWER_DEF" in *"$REVIEW_ROUND_DEF"*) ok "(ROUND) the living answer reads the same round defs the intake stamps" ;;
  *) bad "(ROUND) the living answer reads the same round defs the intake stamps" ;; esac
# A human finding on review <rid>, raised by its comment <cid> (a body when the
# two are one id), and the read of a PR whose reviews are <id>:<login>:<commit>:<state>.
rrow() { # id rid cid disposition status [extra-metadata-object]
  local x="${6:-}"; [ -n "$x" ] || x='{}'
  jq -cn --arg id "$1" --arg r "$2" --arg c "$3" --arg d "$4" --arg st "$5" --argjson x "$x" '
    { id: $id, status: $st, title: ("finding[human]: " + $id),
      description: ("Locus: " + (if $c == $r then "PR review" else "a.sh:" + $c end) + "\n\n**Point " + $id + ".**\n\nRaised by human:op reviewing anchor A."),
      metadata: ({ task_kind: "finding", "finding.lane": "human", "finding.disposition": $d,
                   "finding.comment_id": $c, "finding.review_id": $r } + $x) }'
}
rview() { # issue-comments-json review-spec...
  local ics="$1"; shift
  jq -cn --argjson ics "$ics" '{ reviews: [ $ARGS.positional[] | split(":") as $p
      | { databaseId: ($p[0] | tonumber), author: { login: $p[1] }, commit: (if $p[2] == "" then null else { oid: $p[2] } end),
          state: $p[3], url: "" } ], threads: [], issue_comments: $ics }' --args "$@"
}
rmodels() { # rows-json view-json [plan-marks-json] [beads-json]
  printf '%s' "$1" | jq -c --argjson v "$2" --argjson vl "${3:-"{}"}" --argjson b "${4:-"{}"}" --arg m "$MARKER" \
    "$CITY_OWN_DEF$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; $vl; $b; $m; gc_city_own("bot"; ""))'
}
KB='{"K":{"title":"rework","fix_notes":"Notes from K.","closed":false}}'
RROWS="[$(rrow F1 501 51 must-fix open '{"finding.fix_unit":"K"}'),$(rrow F2 502 52 must-fix open '{"finding.fix_unit":"K"}'),$(rrow F3 503 53 must-fix open '{"finding.fix_unit":"K"}')]"
RV=$(rview '[]' 501:op:c1:COMMENTED 502:op:c1:COMMENTED 503:op:c1:COMMENTED)
RM=$(rmodels "$RROWS" "$RV" '{}' "$KB")
eq "$(printf '%s' "$RM" | jq -c '[ length, .[0].rid, .[0].rids, (.[0].points | length) ]')" '[1,"501",["501","502","503"],3]' \
  "(ROUND) three single-comment reviews against one commit are one round: one model, keyed by its lowest review, with three points"
RR=$(printf '%s' "$RM" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'.[0] | ra_render($m)')
has "$RR" "### Your review: 3 points" "(ROUND) …one comment counting every point of the round"
eq "$(printf '%s' "$RR" | grep -c '<summary>Notes from the fix</summary>')" "1" "(ROUND) …with the notes from the fix once"
eq "$(printf '%s' "$RR" | grep -c '<!-- gc-review-answer:r[0-9]* -->')|$(printf '%s' "$RR" | grep -c 'gc-review-answer:r501 -->')" "1|1" \
  "(ROUND) …and one key, the lowest review's"
# One review with a body and inline comments is one round, rendered whole: the
# golden below is ra_render over this input, byte for byte.
GROWS='[
 {"id":"B","status":"closed","title":"finding[human]: s","description":"Locus: PR review\n\nRename the flag before this lands.\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"declined","finding.comment_id":"10","finding.review_id":"10","finding.reply":"the name matches the other scripts"}},
 {"id":"I","status":"closed","title":"finding[human]: i","description":"Locus: a.sh:1\n\n**Fix the cap.**\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"must-fix","finding.comment_id":"11","finding.review_id":"10","finding.fix_unit":"K","finding.fix_answer":"Fixed as you suggested."}},
 {"id":"J","status":"open","title":"finding[human]: j","description":"Locus: b.sh:2\n\nShould the retry back off?\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"needs-you","finding.comment_id":"12","finding.review_id":"10","finding.gate":"tk-v","finding.answer":"Should the retry back off?"}}]'
GVIEW='{"reviews":[{"databaseId":10,"state":"CHANGES_REQUESTED","author":{"login":"op"},"commit":{"oid":"c1"},"url":""}],
  "threads":[{"comments":{"nodes":[{"databaseId":11,"url":"https://github.com/o/r/pull/7#discussion_r11"}]}},{"comments":{"nodes":[{"databaseId":12,"url":"https://github.com/o/r/pull/7#discussion_r12"}]}}],
  "issue_comments":[{"databaseId":900,"author":{"login":"bot"},"body":"old\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:resolved r10 -->\n<!-- gc-review-answer:r10 -->\n<!-- gc-review-answer:r10:digest:1 -->"}]}'
GOLDEN='> [!IMPORTANT]
> **Needs you: human gate tk-v.** Should the retry back off?

### Your review: 3 points, 1 needs you, 2 answered

1 needs you, 1 worth a look, 1 done.

**Needs you**
- **[Should the retry back off?](https://github.com/o/r/pull/7#discussion_r12)** (tk-v)

**Worth a look**
- **[Rename the flag before this lands.](https://github.com/o/r/pull/7#pullrequestreview-10)** Declined: the name matches the other scripts

**Done**
- **[Fix the cap.](https://github.com/o/r/pull/7#discussion_r11)** Fixed as you suggested.{{gc-commits:K|11}}

<details>
<summary>Notes from the fix</summary>

Notes from K.

</details>

<!-- gc-writeback -->
<!-- gc-writeback-mark:resolved r10 -->
<!-- gc-review-answer:r10 -->'
GM=$(rmodels "$GROWS" "$GVIEW" '{"10":{"marks":["resolved r10"],"gates":[],"swaps":"-"}}' '{"K":{"title":"rework","fix_notes":"Notes from K.","closed":true}}')
eq "$(printf '%s' "$GM" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'.[0] | ra_render($m)')" "$GOLDEN" \
  "(ROUND) one review with a body and inline comments renders whole, as one round"
eq "$(printf '%s' "$GM" | jq -c '.[0] | [ .existing.db, .existing.digest, .strays ]')" '["900","1",[]]' "(ROUND) …finding its one comment, with no copy to fold"
# A body review that only frames the round: ruled restates, it is no point.
FROWS="[$(rrow F1 501 51 must-fix open),$(rrow F2 502 52 must-fix open),$(rrow F4 504 504 restates closed)]"
FRM=$(rmodels "$FROWS" "$(rview '[]' 501:op:c1:COMMENTED 502:op:c1:COMMENTED 504:op:c1:CHANGES_REQUESTED)")
eq "$(printf '%s' "$FRM" | jq -c '[ length, .[0].rids, [ .[0].points[].id ] ]')" '[1,["501","502","504"],["F1","F2"]]' \
  "(ROUND) a body review framing the round is in the round and adds no point"
has "$(printf '%s' "$FRM" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'.[0] | ra_render($m)')" "### Your review: 2 points" "(ROUND) …and no count"
# A later commit, or another reviewer, starts a round of its own.
NRM=$(rmodels "[$(rrow F1 501 51 must-fix open),$(rrow F2 502 52 must-fix open),$(rrow F6 601 61 must-fix open),$(rrow F7 701 71 must-fix open)]" \
  "$(rview '[]' 501:op:c1:COMMENTED 502:op:c1:COMMENTED 601:op:c2:COMMENTED 701:op2:c1:COMMENTED)")
eq "$(printf '%s' "$NRM" | jq -c '[ .[].rids ] | sort')" '[["501","502"],["601"],["701"]]' \
  "(ROUND) a review against a new commit, and another reviewer on the same commit, each get a model of their own"
# Each review of a round is dismissed on its own; the round reads dismissed once
# no review of it stands changes-requested.
DROWS="[$(rrow F1 501 51 must-fix closed),$(rrow F4 504 504 must-fix closed),$(rrow F5 505 505 must-fix open)]"
DM=$(rmodels "$DROWS" "$(rview '[]' 501:op:c1:COMMENTED 504:op:c1:CHANGES_REQUESTED 505:op:c1:CHANGES_REQUESTED)" | jq -c '.[0]')
eq "$(printf '%s' "$DM" | jq -r "$REVIEW_ANSWER_DEF"'ra_dismissal')" "" "(ROUND) a round whose changes-requested reviews stand reads undismissed"
D1=$(printf '%s' "$DM" | jq -c "$REVIEW_ANSWER_DEF"'ra_dismiss_member("504")')
eq "$(printf '%s' "$D1" | jq -c '[ .members[] | [ .rid, .dismissed ] ]')" '[["501",""],["504","requeued"],["505",""]]' \
  "(ROUND) dismissing one review marks that review alone"
eq "$(printf '%s' "$D1" | jq -r "$REVIEW_ANSWER_DEF"'ra_dismissal')" "" "(ROUND) …and the round still reads undismissed while another review of it stands"
DR1=$(printf '%s' "$D1" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
has "$DR1" "<!-- gc-review-answer:r501 -->
<!-- gc-review-answer:r504:dismissed -->" "(ROUND) …though the comment carries that review's dismissed mark under the round's key"
hasnt "$DR1" "Review dismissed" "(ROUND) …and says nothing of a dismissal yet"
D2=$(printf '%s' "$D1" | jq -c "$REVIEW_ANSWER_DEF"'ra_dismiss_member("505")')
has "$(printf '%s' "$D2" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')" "Review dismissed; your review is requested again." \
  "(ROUND) once every changes-requested review of it is dismissed, the round says so"
eq "$(printf '%s' "$D1" | jq -r "$REVIEW_ANSWER_DEF"'ra_dismiss_note("U")')" \
  "Your review: 3 points, 2 answered so far (U). Dismissal is not approval; the merge still gates on an explicit approving review." \
  "(ROUND) a review's dismissal note carries the count line of its round and the round's comment"
# The copies of one round: the city answered each review on its own. The round
# keeps the copy a dismissal note names, takes every mark the copies carry, and
# names the others to delete. A comment keyed to another round, or quoting a key
# above its own trailer, is no copy.
HROWS="[$(rrow F1 501 51 must-fix closed),$(rrow B2 502 502 declined closed '{"finding.reply":"kept as is","finding.reply_posted":"1"}'),$(rrow F2 502 52 must-fix closed),$(rrow B3 503 503 must-fix closed),$(rrow G1 777 77 must-fix open)]"
HICS='[{"databaseId":900,"author":{"login":"bot"},"body":"a\n<!-- gc-writeback -->\n<!-- gc-review-answer:r501 -->\n<!-- gc-review-answer:r501:digest:1 -->"},
  {"databaseId":901,"author":{"login":"bot"},"body":"b\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:resolved r502 -->\n<!-- gc-review-answer:r502 -->\n<!-- gc-review-answer:r502:digest:2 -->"},
  {"databaseId":902,"author":{"login":"bot"},"body":"c\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:resolved r503 -->\n<!-- gc-review-answer:r503 -->\n<!-- gc-review-answer:r503:dismissed -->\n<!-- gc-review-answer:r503:digest:3 -->"},
  {"databaseId":903,"author":{"login":"bot"},"body":"d\n<!-- gc-writeback -->\n<!-- gc-review-answer:r777 -->\n<!-- gc-review-answer:r777:digest:4 -->"},
  {"databaseId":904,"author":{"login":"bot"},"body":"quoting <!-- gc-review-answer:r501 --> in a note\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:resolved i5 -->"}]'
HV=$(rview "$HICS" 501:op:c1:COMMENTED 502:op:c1:COMMENTED 503:op:c1:DISMISSED 777:op2:c1:COMMENTED)
HM=$(rmodels "$HROWS" "$HV" | jq -c '.[] | select(.rid == "501")')
eq "$(printf '%s' "$HM" | jq -c '[ .rids, .existing.db, .existing.digest, .strays ]')" '[["501","502","503"],"902","3",["900","901"]]' \
  "(ROUND) the round keeps the copy its dismissal note names, its digest read back, and names the others to delete"
eq "$(printf '%s' "$HM" | jq -c '.marks')" '["resolved r502","resolved r503"]' "(ROUND) …every mark its copies carry"
eq "$(printf '%s' "$HM" | jq -c '[ .members[] | [ .rid, .dismissed ] ]')" '[["501",""],["502",""],["503","requeued"]]' "(ROUND) …and every dismissed mark"
has "$(printf '%s' "$HM" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')" "$MARKER
<!-- gc-writeback-mark:resolved r502 -->
<!-- gc-writeback-mark:resolved r503 -->
<!-- gc-review-answer:r501 -->
<!-- gc-review-answer:r503:dismissed -->" "(ROUND) …all of which the comment it keeps carries, under the round's key"
eq "$(rmodels "$HROWS" "$HV" | jq -c '[ .[] | select(.rid == "777") | .existing.db, .strays ]')" '["903",[]]' \
  "(ROUND) a comment keyed to another round stays that round's"
eq "$(rmodels "$HROWS" "$(printf '%s' "$HV" | jq -c '.issue_comments |= map(select(.databaseId != 902))')" | jq -c '.[] | select(.rid == "501") | [ .existing.db, .strays ]')" \
  '["900",["901"]]' "(ROUND) with no copy a dismissal note names, the round keeps the earliest"
# Once the copy it keeps has been edited, it carries the round's key; a pass
# whose deletes failed finds it again by its dismissed mark.
HEDIT='{"databaseId":902,"author":{"login":"bot"},"body":"c\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:resolved r503 -->\n<!-- gc-review-answer:r501 -->\n<!-- gc-review-answer:r503:dismissed -->\n<!-- gc-review-answer:r501:digest:9 -->"}'
eq "$(rmodels "$HROWS" "$(printf '%s' "$HV" | jq -c --argjson e "$HEDIT" '.issue_comments |= map(if .databaseId == 902 then $e else . end)')" | jq -c '.[] | select(.rid == "501") | [ .existing.db, .existing.digest, .strays ]')" \
  '["902","9",["900","901"]]' "(ROUND) a copy keyed to the round and carrying a dismissed mark is still the one the round keeps"
eq "$(rmodels "$HROWS" "$HV" '{"502":{"marks":["awaiting:tk-v r502"],"gates":["tk-v"],"swaps":"-"}}' | jq -c '.[] | select(.rid == "501") | .marks')" \
  '["awaiting:tk-v r502","resolved r503"]' "(ROUND) a mark the plan names for a review replaces that review's marks alone"

echo "# (DISMISS)"
N=$(printf '%s' "$MODEL" | jq -r "$REVIEW_ANSWER_DEF"'ra_dismiss_note("U")')
eq "$N" "Your review: 3 points, all answered (U). Dismissal is not approval; the merge still gates on an explicit approving review." \
  "(DISMISS) one line: the count line, the living answer, and that dismissal is not approval"
has "$(printf '%s' "$MODEL" | jq -r "$REVIEW_ANSWER_DEF"'.self = true | ra_dismiss_note("U")')" "no fresh review is requested" \
  "(DISMISS) a review under the city's own account says no fresh review is requested"
eq "$(jq -rn --argjson n "$NEEDS1" --argjson u "$UNRULED" "$REVIEW_ANSWER_DEF"'{ self: false, points: [ $n, $u, $u ] } | ra_dismiss_note("U")')" \
  "Your review: 3 points, 1 needs you, the rest in progress (U). Dismissal is not approval; the merge still gates on an explicit approving review." \
  "(DISMISS) a note dismissing a review while other points of its round are unruled says the rest are in progress"
eq "$(wmodel false | jq -r "$REVIEW_ANSWER_DEF"'ra_dismiss_note("U")')" \
  "Your review: 2 points, 1 needs you, 1 answered (U). Dismissal is not approval; the merge still gates on an explicit approving review." \
  "(DISMISS) a note dismissing a review whose decline waits in an open thread says a point needs the reviewer"

echo "# (READERS)"
PF="$HERE/pr-facts.sh"
has "$(cat "$PF")" '. "$_bd_lib_dir/review-answer.sh"' "(READERS) pr-facts.sh sources this file"
for d in ra_models ra_render ra_dismiss_note ra_dismiss_member ra_rounds; do
  has "$(cat "$PF")" "$d(" "(READERS) pr-facts.sh reads $d"
done
has "$(cat "$PF")" "| ra_review_rounds)" "(READERS) pr-facts.sh reads ra_review_rounds"
eq "$(grep -c '"$CITY_OWN_DEF$REVIEW_ROUND_DEF"\|"$WB_OWED_REPLY_DEF$REVIEW_ROUND_DEF"\|jq -rn "$REVIEW_ROUND_DEF"' "$PF")" "3" \
  "(READERS) the intake, the write-back's round record and the review dismissal place a review in its round through these defs"
has "$(cat "$PF")" 'WB_OWED_REPLY_DEF="$REVIEW_OWED_REPLY_DEF"' \
  "(READERS) the owed-reply set the reply arm and the dismissal read is built on these defs, so it cannot drift from the living answer's"
has "$(cat "$PF")" 'ra_ruled_reply($disp)' "(READERS) …and a thread reply leads with its ruling through the same def"
has "$(cat "$PF")" 'ra_open_ask($disp)' "(READERS) …and says what resolving its thread does through the def the living answer reads"
has "$(cat "$PF")" 'ra_comment_thread($v; $cid) as $t' "(READERS) …finding the thread through the lookup the living answer reads, so the two read one thread"
has "$(cat "$PF")" '($t | ra_thread_open)' "(READERS) …asking for nothing in a thread already resolved, by the same reading of its state"
has "$(cat "$PF")" 'ra_answer_post($self; $m; $id; $reply)' "(READERS) …and reading its answer back by the test the living answer tells a waiting thread by"
has "$(cat "$PF")" 'ra_models($view; $prurl; $self; $vl; $beads; $marker; gc_city_own($self; $since))' \
  "(READERS) the living answer tells a post of the city by gc_city_own, the rule the routing arm tells feedback by"
OTHERS=$(cd "$ROOT" && git grep -l -F 'gc-review-answer:' -- . ':!assets/scripts/review-answer.sh' ':!assets/scripts/pr-facts.sh' ':!*.test.sh' ':!docs/**' ':!specs/**' ':!lifecycle/**' 2>/dev/null)
eq "$OTHERS" "" "(READERS) no other file writes a living answer's review key"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
