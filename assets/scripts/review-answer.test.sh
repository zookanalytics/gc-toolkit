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
#             landed, and no point for a body ruled restates
#   (URL)     a label links only to a comment the read of the PR holds
#   (RENDER)  the visit callout on top, the count line, the sections in order,
#             the entries, the folded notes and the trailing mark lines
#   (MODEL)   one model per review: the comment already on the PR found by its
#             key, its digest and dismissed mark read back, what keeps it live,
#             the review body answers it delivers, the marks it keeps, and each
#             fix unit's landing read from its close
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

MARKER='<!-- gc-writeback -->'
PRURL="https://github.com/o/r/pull/7"
# A finding record as ra_record builds it, from a few overrides.
rec() { jq -cn --argjson o "${1:-}" '{ id: "F", open: false, disp: "must-fix", message: "", title: "", label: "",
    answer: "", fix_answer: "", fix_flag: "", reply: "", posted: false, follow_up: "", visit: "",
    ruling_visit: "", fix_unit: "", cid: "11", rid: "10", body: false, url: "", fix_landed: false } + $o'; }
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
eq "$(pfield '{"disp":"needs-you","open":true,"visit":"tk-v","answer":"Ship it now?"}' section)" "needs" "(SECTION) an open needs-you finding needs the operator"
eq "$(pfield '{"disp":"needs-you","open":true,"visit":"tk-v","answer":"Ship it now?"}' ref)" "tk-v" "(SECTION) …naming its visit"
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
eq "$(pfield '{'"$BODY"',"disp":"needs-you","open":true,"visit":"tk-v","answer":"Ship it now?","reply":"This comment needs your decision — opened visit tk-v."}' extra)" "" \
  "(SECTION) a body question for the operator quotes nothing: the entry names its visit"
eq "$(pfield '{"disp":"needs-you","ruling_visit":"tk-v"}' sentence)" "Settled by your ruling on visit tk-v." "(SECTION) a needs-you finding the ruling settled is done"
eq "$(pfield '{"disp":"unvalidated","open":true}' section),$(pfield '{"disp":"unvalidated","open":true}' ruled)" "progress,false" "(SECTION) an unruled point is in progress"
eq "$(point '{"disp":"restates","body":true,"cid":"10"}')" '"none"' "(SECTION) a body ruled restates is no point"

echo "# (URL)"
VIEW='{"reviews":[{"databaseId":10,"url":""}],"threads":[{"comments":{"nodes":[{"databaseId":11,"url":"https://github.com/o/r/pull/7#discussion_r11"}]}}],"issue_comments":[]}'
url() { rec "$1" | jq -r --argjson v "$VIEW" --arg p "$PRURL" "$REVIEW_ANSWER_DEF"'ra_url($v; $p)'; }
eq "$(url '{"cid":"11"}')" "https://github.com/o/r/pull/7#discussion_r11" "(URL) an inline comment links to its thread as GitHub names it"
eq "$(url '{"cid":"10","body":true}')" "$PRURL#pullrequestreview-10" "(URL) a review body links to its review"
eq "$(url '{"cid":"99"}')" "" "(URL) a comment the read does not hold gets no link"

echo "# (RENDER)"
MODEL='{"rid":"10","head":"abcdef123456","self":false,"dismissed":"requeued",
  "points":[
    {"id":"a","section":"worth","label":"Guard rewrites the opt-out","url":"U1","sentence":"You asked for a decision, and the fix chose your second option.","ref":"","answered":true,"ruled":true,"extra":""},
    {"id":"b","section":"done","label":"A refused dismissal tells nobody.","url":"","sentence":"Fixed with your option (a).","ref":"{{gc-commits:k|3}}","answered":true,"ruled":true,"extra":""},
    {"id":"c","section":"worth","label":"Retry loop","url":"","sentence":"Deferred to tk-fu: later.","ref":"tk-fu","answered":true,"ruled":true,"extra":""}],
  "visits":[{"id":"tk-v1","question":"Should enforcement turn on now?"}],
  "notes":[{"by":"k","text":"Notes here."}],
  "marks":["resolved r10"]}'
R=$(printf '%s' "$MODEL" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')
case "$R" in "> [!IMPORTANT]"*) ok "(RENDER) an open visit leads the comment" ;; *) bad "(RENDER) an open visit leads the comment (got: $R)" ;; esac
has "$R" "> **Needs you: visit tk-v1.** Should enforcement turn on now?" "(RENDER) …naming the visit and its question"
has "$R" "### Your review: 3 points, all answered at abcdef12" "(RENDER) the count line names the head the answers stand at"
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
R2=$(printf '%s' "$MODEL" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'.visits = [] | .dismissed = "" | .notes = [] | .points[0].sentence = "Guard rewrites the opt-out" | ra_render($m)')
case "$R2" in "### Your review"*) ok "(RENDER) with no open visit the count line leads" ;; *) bad "(RENDER) with no open visit the count line leads (got: $R2)" ;; esac
has "$R2" "- **[Guard rewrites the opt-out.](U1)**
" "(RENDER) a sentence that only repeats the label is left out"
hasnt "$R2" "Review dismissed" "(RENDER) an undismissed review says nothing of a dismissal"
hasnt "$R2" ":dismissed -->" "(RENDER) …and carries no dismissed mark"
P=$(printf '%s' "$MODEL" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'.visits = [] | .dismissed = "" | .points = [ .points[] | .ruled = false | .answered = false | .section = "progress" | .sentence = "" ] | ra_render($m)')
has "$P" "### Your review: 3 points, picked up; the ruling is in progress" "(RENDER) at pickup the count line says the ruling is in progress"
hasnt "$P" "Not ruled yet" "(RENDER) …and no entry repeats it"
hasnt "$P" "in progress." "(RENDER) …nor adds a count line"

BIG=$(jq -n --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'{rid:"1",head:"",self:false,dismissed:"",
  points:[{id:"a",section:"done",label:"L",url:"",sentence:("word " * 600),ref:"",answered:true,ruled:true,extra:""}],
  visits:[],notes:[{by:"k",text:("n " * 9000)}],marks:[]} | ra_render($m) | length')
[ "$BIG" -lt 15000 ] && ok "(RENDER) a long sentence and long notes are clipped, so the comment stays postable ($BIG characters)" \
  || bad "(RENDER) a long sentence and long notes are clipped, so the comment stays postable (got $BIG characters)"

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
  --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; "abc"; $vl; $b; $m)'; }
M=$(models "$VIEW2" '{}')
eq "$(printf '%s' "$M" | jq 'length')" "1" "(MODEL) one model per review: a machine finding and a Conversation comment belong to none"
eq "$(printf '%s' "$M" | jq -r '.[0].existing.db + " " + .[0].existing.digest')" "900 12345" "(MODEL) the comment on the PR is ours carrying the review key, with its digest read back"
eq "$(printf '%s' "$M" | jq -r '.[0].existing.url')" "$PRURL#issuecomment-900" "(MODEL) …and its link"
eq "$(printf '%s' "$M" | jq -r '.[0].dismissed')" "requeued" "(MODEL) a dismissed mark on it reads as the dismissal the writer made"
eq "$(printf '%s' "$M" | jq -r '.[0].marks | join(",")')" "resolved r10" "(MODEL) the marks it carries stand while the plan names none"
eq "$(models "$VIEW2" '{"10":{"marks":["awaiting:tk-v r10"],"visits":["tk-v"],"swaps":"-"}}' | jq -r '.[0].marks | join(",")')" "awaiting:tk-v r10" "(MODEL) …and give way to the ones it names"
eq "$(printf '%s' "$M" | jq -r '.[0].live')" "true" "(MODEL) an open finding keeps the review live"
eq "$(printf '%s' "$M" | jq -c '[ .[0].replied, .[0].unstamped ]')" '[["B"],["B"]]' "(MODEL) the review body's decline is an answer it delivers, not yet stamped"
eq "$(printf '%s' "$M" | jq -r '.[0].notes[0].text')" "notes from K" "(MODEL) the fix unit's notes come with it"
eq "$(printf '%s' "$M" | jq -r '[ .[0].points[].id ] | join(",")')" "B,I" "(MODEL) the body leads its inline comments"
DONE_ROWS=$(printf '%s' "$ROWS" | jq -c 'map(if .id == "I" then .status = "closed" else . end | if .id == "B" then .metadata["finding.reply_posted"] = "1" else . end)')
eq "$(printf '%s' "$DONE_ROWS" | jq -c --argjson v "$(printf '%s' "$VIEW2" | jq -c '.issue_comments = [] | .reviews[0].state = "DISMISSED"')" \
  --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; "abc"; {}; {}; $m) | .[0] | [ .live, .dismissed ]')" '[false,"plain"]' \
  "(MODEL) a dismissed review with every finding closed and nothing owed is not live, and reads dismissed without a re-request claim"
eq "$(printf '%s' "$DONE_ROWS" | jq -c --argjson v "$(printf '%s' "$VIEW2" | jq -c '.issue_comments = [] | .reviews[0].state = "COMMENTED"')" \
  --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; "abc"; {"10":{"marks":["resolved r10"],"visits":[],"swaps":"-"}}; {}; $m) | .[0].live')" "true" \
  "(MODEL) a mark the plan asks of it keeps it live, so a body answered after its findings closed still gets its answer"
eq "$(printf '%s' "$DONE_ROWS" | jq -c --argjson v "$(printf '%s' "$VIEW2" | jq -c '.issue_comments = [] | .reviews[0].state = "CHANGES_REQUESTED"')" \
  --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; "abc"; {}; {}; $m) | .[0].live')" "true" \
  "(MODEL) a standing changes-requested block keeps it live"
FL_ROWS='[{"id":"D","status":"closed","title":"finding[human]: d","description":"Locus: a.sh:2\n\n**Rename the cap.**\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"declined","finding.comment_id":"11","finding.review_id":"10",
              "finding.fix_unit":"K","finding.fix_flag":"1","finding.fix_answer":"Renamed anyway, though the ruling declined it."}}]'
flref() { printf '%s' "$FL_ROWS" | jq -r --argjson v "$VIEW2" --argjson b "$1" --arg m "$MARKER" \
  "$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; "abc"; {}; $b; $m) | .[0].points[0].ref'; }
eq "$(flref '{"K":{"title":"rework","fix_notes":"","closed":true}}')" "{{gc-commits:K|11}}" \
  "(MODEL) a flagged decline reads its fix unit's landing from the close read for it"
eq "$(flref '{"K":{"title":"rework","fix_notes":"","closed":false}}')" "" "(MODEL) …so a fix unit still open cites nothing"
eq "$(flref '{}')" "" "(MODEL) …and neither does one that did not read back"
# The writer stamps each review body answer in unstamped delivered once the
# comment carries the rendering, so the rendering has to hold every one.
DL_ROWS='[{"id":"D2","status":"closed","title":"finding[human]: d2","description":"Locus: PR review\n\nA summary with a point of its own.\n\nRaised by human:op reviewing anchor A.",
  "metadata":{"task_kind":"finding","finding.lane":"human","finding.disposition":"declined","finding.comment_id":"10","finding.review_id":"10",
              "finding.reply":"We keep Y because Z","finding.fix_unit":"K","finding.fix_flag":"1","finding.fix_answer":"Changed it anyway."}}]'
DLM=$(printf '%s' "$DL_ROWS" | jq -c --argjson v "$VIEW2" --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_models($v; "'"$PRURL"'"; "bot"; "abc"; {}; {}; $m) | .[0]')
eq "$(printf '%s' "$DLM" | jq -c '.unstamped')" '["D2"]' "(MODEL) a flagged review body decline is an answer the comment delivers"
has "$(printf '%s' "$DLM" | jq -r --arg m "$MARKER" "$REVIEW_ANSWER_DEF"'ra_render($m)')" "  > Declined: We keep Y because Z" \
  "(MODEL) …and the rendering it is stamped against carries it"

echo "# (DISMISS)"
N=$(printf '%s' "$MODEL" | jq -r "$REVIEW_ANSWER_DEF"'ra_dismiss_note("U")')
eq "$N" "Your review: 3 points, all answered at abcdef12 (U). Dismissal is not approval; the merge still gates on an explicit approving review." \
  "(DISMISS) one line: the count line, the living answer, and that dismissal is not approval"
has "$(printf '%s' "$MODEL" | jq -r "$REVIEW_ANSWER_DEF"'.self = true | ra_dismiss_note("U")')" "no fresh review is requested" \
  "(DISMISS) a review under the city's own account says no fresh review is requested"

echo "# (READERS)"
PF="$HERE/pr-facts.sh"
has "$(cat "$PF")" '. "$_bd_lib_dir/review-answer.sh"' "(READERS) pr-facts.sh sources this file"
for d in ra_models ra_render ra_dismiss_note; do
  has "$(cat "$PF")" "$d(" "(READERS) pr-facts.sh reads $d"
done
has "$(cat "$PF")" 'WB_OWED_REPLY_DEF="$REVIEW_OWED_REPLY_DEF"' \
  "(READERS) the owed-reply set the reply arm and the dismissal read is built on these defs, so it cannot drift from the living answer's"
has "$(cat "$PF")" 'ra_ruled_reply($disp)' "(READERS) …and a thread reply leads with its ruling through the same def"
OTHERS=$(cd "$ROOT" && git grep -l -F 'gc-review-answer:' -- . ':!assets/scripts/review-answer.sh' ':!assets/scripts/pr-facts.sh' ':!*.test.sh' ':!docs/**' ':!specs/**' ':!lifecycle/**' 2>/dev/null)
eq "$OTHERS" "" "(READERS) no other file writes a living answer's review key"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
