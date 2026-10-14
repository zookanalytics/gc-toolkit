#!/usr/bin/env bash
# review-answer.sh — the city's one living answer to a human pull request
# review: what it says, built from bead state. Sourced, never executed.
#
# Every human review gets one Conversation comment, created when the city picks
# the review up and edited in place on every change after that. pr-facts.sh's
# write-back is its only writer: it builds a model per review from the review's
# findings and the PR it read (ra_models), renders the comment from it
# (ra_render), and edits the comment only when the rendering changed. The
# dismissal note that clears a review once its findings close is one line
# naming the comment (ra_dismiss_note).
#
# One point per finding, in four sections that appear only when non-empty:
#   Needs you     a needs-you finding whose visit is still open
#   Worth a look  a declined or deferred finding, and any point whose fix
#                 flagged it (finding.fix_flag): the fix chose among options
#                 the reviewer left open, departed from their suggestion, or
#                 changed code the ruling declined
#   In progress   a point not yet ruled, or a must-fix whose fix has not landed
#   Done          a must-fix whose fix landed, a needs-you finding the
#                 operator's ruling settled, and a comment that asked for
#                 nothing (declined with no reply)
# A review body ruled restates frames the review's inline comments and is no
# point of its own, so it has no entry and no count.
#
# Each point is a label linked to the comment it answers, one sentence, and the
# commit, follow-up or visit that carries it. The label is the comment's own
# bold lead with its severity marks and "Please fix on this PR:" stripped, else
# the label the validator wrote (finding.label), else the comment's first
# sentence. The sentence is whoever answered, in their own words: the fix
# unit's result (finding.fix_answer), or the validator's ruling-side answer
# (finding.answer, falling back to the owed reply it recorded). A point not yet
# answered says which stage it is at. A link goes only to a comment the read of
# the PR found, and no sentence points at a reply or thread: the answer is in
# the entry itself. A review body has no thread to carry a decline's or a
# deferral's full reply, so its entry carries that reply too, and the comment is
# what delivers it, as it delivers the mark that records the body answered. A
# review stays live, and gets its comment, while a finding is open, its
# changes-requested block stands, or the comment owes it an answer or a mark.
#
# A point cites the commits that made its fix only once the fix has landed. The
# rendering holds a token for them, which the writer expands as it posts, and
# the writer edits only when the rendering changes, so a token rendered before
# its commits reached the PR would stay uncited until some other change edited
# the comment. A must-fix point cites them once its finding closes, which waits
# on every fix unit answering it. A declined point its fix unit flagged, for
# code the ruling declined, cites them once that fix unit closes, because a
# decline closes its finding at the ruling, before any fix is pushed. A flagged
# deferral keeps its follow-up.
#
# Usage follows the in-variable jq convention (review-verdict.sh): prepend the
# defs to a jq program. No comment or string inside the program may carry an
# apostrophe, since the program is one single-quoted shell word.
#   jq -n "$REVIEW_ANSWER_DEF"'... | ra_render($marker)'
# shellcheck disable=SC2034  # read by the scripts that source this file
REVIEW_ANSWER_DEF='
  def ra_squash: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
  # At most $n characters, cut at a word boundary when one falls in the second
  # half, with an ellipsis marking the cut.
  def ra_cut($n):
    if length <= $n then .
    else .[0:$n] as $h | ($h | sub("\\s+\\S*$"; "")) as $w
      | (if ($w | length) >= ($n / 2) then $w else $h end) + "…" end;
  # The run of marks a comment can open with: severity emoji, bullets,
  # punctuation and space. Letters, digits, emphasis, code and links survive.
  def ra_unmark: sub("^[^\\p{L}\\p{N}*_`\\[]+"; "");
  def ra_upfirst: if length > 0 then (.[0:1] | ascii_upcase) + .[1:] else . end;
  # The opening a reviewer puts before the point itself.
  def ra_unboiler:
    sub("^(please\\s+)?(fix|address)(\\s+this)?(\\s+(on|in)\\s+this\\s+pr)?\\s*:\\s*"; ""; "i")
    | sub("^(nit|blocking|non-blocking|must[- ]fix)\\s*:\\s*"; ""; "i");
  # The bold run a comment opens with, stripped of severity marks and of its
  # boilerplate, or the empty string.
  def ra_lead:
    (ra_unmark | (capture("^\\*\\*(?<l>[^\\n]+?)\\*\\*") // capture("^__(?<l>[^\\n]+?)__") // null)) as $c
    | if $c == null then ""
      else $c.l | ra_squash | ra_unboiler | sub("[\\s:]+$"; "") | ra_upfirst end;
  def ra_first_sentence:
    ra_unmark
    | gsub("\\[(?<t>[^\\]\\n]*)\\]\\([^)\\n]*\\)"; "\(.t)")
    | gsub("\\*\\*|__"; "")
    | ([ split("\n")[] | select(test("\\S")) ] | .[0] // "")
    | ((capture("^(?<s>.+?[.?!])(\\s|$)") | .s) // .)
    | ra_squash | ra_upfirst | ra_cut(100);
  # The label of a finding record (ra_record): its comment bold lead, else the
  # validator label, else the comment first sentence. Emphasis is dropped and
  # brackets escaped, so the label is safe inside a link and a bold run.
  def ra_label:
    ((.message // "") | ra_lead) as $lead
    | ((.label // "") | ra_squash) as $own
    | (if $lead != "" then $lead
       elif $own != "" then $own
       else (if ((.message // "") | test("\\S")) then .message
             else ((.title // "") | sub("^finding\\[[^\\]]*\\]:\\s*"; "")) end) | ra_first_sentence end)
    | gsub("\\*"; "") | ra_squash | ra_cut(120)
    | gsub("\\["; "\\[") | gsub("\\]"; "\\]");
  # Where a finding comment sits, from the read of the PR: the review for a
  # review body, the inline comment (its thread) otherwise. Empty when the read
  # does not hold it, so no link names a comment that is not there.
  def ra_url($view; $prurl):
    .cid as $c
    | if $c == "" then ""
      elif .body then
        (first($view.reviews[]? | select(((.databaseId // 0) | tostring) == $c)
          | (if ((.url // "") | tostring) != "" then .url else $prurl + "#pullrequestreview-" + $c end)) // "")
      else
        (first($view.threads[]? | (.comments.nodes // [])[] | select(((.databaseId // 0) | tostring) == $c)
          | (if ((.url // "") | tostring) != "" then .url else $prurl + "#discussion_r" + $c end)) // "")
      end;
  # A human finding bead row as the record the points are made from. $beads
  # maps a bead id to what was read of it (ra_models). A rework child closes
  # when its branch lands, so a fix unit read closed has its commits on the PR.
  def ra_record($view; $prurl; $beads):
    (.metadata // {}) as $m
    | ((.description // "") | tostring) as $desc
    | { id: ((.id // "") | tostring),
        open: (((.status // "") | tostring | ascii_downcase) != "closed"),
        disp: ((($m["finding.disposition"] // "") | tostring) | if . == "" then "unvalidated" else . end),
        message: ($desc | if startswith("Locus: ") then sub("^Locus: [^\\n]*\\n*"; "") else . end
                        | sub("\\n*Raised by [^\\n]* reviewing anchor [^\\n]*$"; "")),
        title: ((.title // "") | tostring),
        label: (($m["finding.label"] // "") | tostring),
        answer: (($m["finding.answer"] // "") | tostring),
        fix_answer: (($m["finding.fix_answer"] // "") | tostring),
        fix_flag: (($m["finding.fix_flag"] // "") | tostring),
        reply: (($m["finding.reply"] // "") | tostring),
        posted: ((($m["finding.reply_posted"] // "") | tostring) == "1"),
        follow_up: (($m["finding.follow_up"] // "") | tostring),
        visit: (($m["finding.visit"] // "") | tostring),
        ruling_visit: (($m["finding.ruling_visit"] // "") | tostring),
        fix_unit: (($m["finding.fix_unit"] // "") | tostring),
        cid: (($m["finding.comment_id"] // "") | tostring),
        rid: (($m["finding.review_id"] // "") | tostring) }
    | . + { body: (.rid != "" and .rid == .cid) }
    | . + { url: ra_url($view; $prurl), fix_landed: (($beads[.fix_unit] // {}).closed == true) };
  # A review body finding whose ruling owes its raiser an answer, which the
  # living comment delivers: the set WB_OWED_REPLY_DEF names, for a comment
  # that sits in no thread.
  def ra_owes_reply: .body and .reply != "" and (.disp == "declined" or .disp == "deferred" or .disp == "needs-you");
  # A finding record as its point, or nothing for a body ruled restates.
  def ra_point:
    . as $f
    | .disp as $d
    | ((.fix_answer // "") | ra_squash) as $fa
    | ((.answer // "") | ra_squash) as $an
    | ((.reply // "") | ra_squash) as $rp
    | (((.fix_flag // "") | tostring) == "1" and $fa != "") as $flag
    | (if .fix_unit != "" and .cid != "" then "{{gc-commits:" + .fix_unit + "|" + .cid + "}}" else "" end) as $commits
    | if $d == "restates" then empty
      elif $d == "needs-you" and .open then
        { section: "needs", sentence: (if $an != "" then $an else "This comment needs your decision." end),
          ref: .visit, answered: false }
      elif $flag then
        { section: "worth", sentence: $fa,
          ref: (if $d == "must-fix" then (if .open then "" else $commits end)
                elif $d == "declined" then (if .fix_landed then $commits else "" end)
                elif $d == "deferred" then .follow_up
                else "" end),
          answered: (.open | not) }
      elif $d == "must-fix" and .open then
        { section: "progress", sentence: (if $fa != "" then $fa else "Ruled must-fix; the fix is in progress." end),
          ref: "", answered: false }
      elif $d == "must-fix" then
        { section: "done", sentence: (if $fa != "" then $fa else "Fixed." end), ref: $commits, answered: true }
      elif $d == "declined" and $rp != "" then
        { section: "worth",
          sentence: (if $an != "" then $an elif ($rp | test("^declin"; "i")) then $rp else "Declined: " + $rp end),
          ref: "", answered: true }
      elif $d == "declined" then
        { section: "done", sentence: (if $an != "" then $an else "Noted; no change asked." end), ref: "", answered: true }
      elif $d == "deferred" then
        { section: "worth", sentence: (if $an != "" then $an elif $rp != "" then $rp else "Deferred to a follow-up." end),
          ref: .follow_up, answered: true }
      elif $d == "needs-you" then
        { section: "done",
          sentence: (if $fa != "" then $fa
                     elif .ruling_visit != "" then "Settled by your ruling on visit " + .ruling_visit + "."
                     else "Closed with no ruling recorded." end),
          ref: "", answered: true }
      else
        { section: "progress", sentence: $fa, ref: "", answered: false }
      end
    | . + { id: $f.id, label: ($f | ra_label), url: $f.url, ruled: ($d != "unvalidated"),
            extra: (if $f.body and ($d == "declined" or $d == "deferred") and $an != "" and $rp != "" and $an != $rp
                    then $rp else "" end) };
  # One model per human review the findings on input name: its points, the
  # visits waiting on the operator, the fix notes, the mark lines the plan owes
  # it, and the comment already on the PR. $vl maps a review id to the mark lines
  # and batch visits the write-back plan asks of it ({marks, visits, swaps}),
  # and $beads maps a bead id to the title, fix notes and close read for it.
  def ra_models($view; $prurl; $self; $head; $vl; $beads; $marker):
    [ .[]? | select(((.metadata.task_kind // "") | tostring) == "finding")
           | select(((.metadata["finding.lane"] // "") | tostring) == "human")
           | ra_record($view; $prurl; $beads) | select(.rid != "") ]
    | group_by(.rid)
    | map(
        .[0].rid as $rid
        | . as $fs
        | (first($view.reviews[]? | select(((.databaseId // 0) | tostring) == $rid)) // {}) as $rv
        | ((($rv.author.login // "") | tostring)) as $login
        | ($login != "" and $login == $self) as $selfrev
        | ("<!-- gc-review-answer:r" + $rid + " -->") as $key
        | ([ $view.issue_comments[]?
             | select(((.author.login // "") == $self) and ((.body // "") | contains($marker)) and ((.body // "") | contains($key))) ]
           | sort_by(.databaseId // 0) | .[0] // null) as $ex
        # The mark lines the comment already carries stand until the plan names
        # new ones: a review body leaves the plan once its review is dismissed,
        # and dropping its mark then would only rewrite the comment.
        | ([ ($ex.body // "") | scan("<!-- gc-writeback-mark:([^ >]+(?: [ri][0-9]+)*) -->") | .[0] ]) as $exmarks
        | (if $ex == null then null
           else { db: (($ex.databaseId // 0) | tostring),
                  url: (if (($ex.url // "") | tostring) != "" then $ex.url else $prurl + "#issuecomment-" + (($ex.databaseId // 0) | tostring) end),
                  digest: ((($ex.body // "") | capture("<!-- gc-review-answer:r[0-9]+:digest:(?<d>[0-9]+) -->") | .d) // ""),
                  dismissed: (($ex.body // "") | contains("<!-- gc-review-answer:r" + $rid + ":dismissed -->")) } end) as $have
        | ($vl[$rid] // { marks: [], visits: [], swaps: "-" }) as $v
        | ($fs | sort_by([ (if .body then 0 else 1 end), ((.cid | tonumber?) // 0) ])) as $sorted
        | [ $sorted[] | ra_point ] as $ps
        | ([ $fs[] | select(.disp == "needs-you" and .open and .visit != "")
             | { id: .visit, question: (if (.answer | ra_squash) != "" then (.answer | ra_squash) else "This comment needs your decision." end) } ]
           + [ ($v.visits // [])[] | { id: ., question: ((($beads[.] // {}).title // "") | tostring | ra_squash) } ]
           | reduce .[] as $x ([]; if any(.[]; .id == $x.id) then . else . + [ $x ] end)) as $visits
        | ([ $fs[] | .fix_unit | select(. != "") ] | unique
           | map({ by: ., text: ((($beads[.] // {}).fix_notes // "") | tostring) }) | map(select(.text | test("\\S")))) as $notes
        | ([ $fs[] | select(ra_owes_reply) | .id ]) as $replied
        | { rid: $rid, head: $head, self: $selfrev, author: $login,
            state: ((($rv.state // "") | tostring)),
            points: $ps, visits: $visits, notes: $notes,
            marks: (if (($v.marks // []) | length) > 0 then $v.marks else $exmarks end), swaps: ($v.swaps // "-"),
            replied: $replied,
            unstamped: [ $fs[] | select(ra_owes_reply and (.posted | not)) | .id ],
            existing: $have,
            dismissed: (if $have != null and $have.dismissed then (if $selfrev then "self" else "requeued" end)
                        elif ((($rv.state // "") | tostring) == "DISMISSED") and all($fs[]; .open | not) then "plain"
                        else "" end),
            live: (any($fs[]; .open) or ((($rv.state // "") | tostring) == "CHANGES_REQUESTED")
                   or any($fs[]; ra_owes_reply and (.posted | not))
                   or ((($v.marks // []) | length) > 0)) });
  def ra_count($n; $word): "\($n) \($word)" + (if $n == 1 then "" else "s" end);
  # The count line: how many points the review raised and how far they are.
  def ra_heading:
    (.points // []) as $ps | ($ps | length) as $n
    | ([ $ps[] | select(.answered) ] | length) as $k
    | "Your review: " + ra_count($n; "point")
      + (if $n > 0 and $k == $n then ", all answered" + (if (.head // "") != "" then " at " + .head[0:8] else "" end)
         elif $k > 0 then ", \($k) answered so far"
         elif any($ps[]; .ruled | not) then ", picked up; the ruling is in progress"
         else ", none answered yet" end);
  def ra_sections: [ { key: "needs", title: "Needs you", one: "needs you", many: "need you" },
                     { key: "worth", title: "Worth a look", one: "worth a look", many: "worth a look" },
                     { key: "progress", title: "In progress", one: "in progress", many: "in progress" },
                     { key: "done", title: "Done", one: "done", many: "done" } ];
  def ra_same: ascii_downcase | gsub("[^\\p{L}\\p{N}]+"; "");
  # One point as a list entry. A sentence that only repeats the label is left
  # out, and so is a reference the sentence already names. A sentence, a carried
  # reply and the fix notes are clipped, so no comment outgrows what GitHub
  # takes and fails on every pass.
  def ra_entry:
    (.label | if test("[.?!…]$") then . else . + "." end) as $l
    | ((.ref // "") | tostring) as $ref
    | ((.sentence // "") | ra_squash | ra_cut(1500)) as $s
    | (if ($s | ra_same) == (.label | ra_same) then "" else $s end) as $say
    | "- **" + (if (.url // "") != "" then "[" + $l + "](" + .url + ")" else $l end) + "**"
      + (if $say != "" then " " + $say else "" end)
      + (if $ref == "" or (($say | contains($ref)) and ($ref | startswith("{{") | not)) then ""
         elif ($ref | startswith("{{")) then $ref
         else " (" + $ref + ")" end)
      + (if (.extra // "") != "" then "\n" + ([ .extra | ra_cut(4000) | split("\n")[] | "  > " + . ] | join("\n")) else "" end);
  # The comment body, ending with the write-back marker, the mark lines the plan
  # owes it and the review key it is found again by. The writer appends the
  # digest line. $marker is the write-back reply marker.
  def ra_render($marker):
    . as $m
    | ($m.points // []) as $ps
    | ([ if ($m.visits | length) > 0 then
           "> [!IMPORTANT]\n" + ([ $m.visits[] | "> **Needs you: visit " + .id + ".**"
                                   + (if (.question // "") != "" then " " + .question else "" end) ] | join("\n>\n"))
         else empty end,
         "### " + ($m | ra_heading),
         ([ (if $m.dismissed == "requeued" then "Review dismissed; your review is requested again."
             elif $m.dismissed != "" then "Review dismissed." else empty end),
            (if any($ps[]; .ruled) then
               ([ ra_sections[] | . as $s | ([ $ps[] | select(.section == $s.key) ] | length) as $c
                  | select($c > 0) | "\($c) " + (if $c == 1 then $s.one else $s.many end) ] | join(", ")) + "."
             else empty end) ] | join(" ") | select(. != "")),
         (any($ps[]; .ruled)) as $anyruled
         | (ra_sections[] | . as $s | [ $ps[] | select(.section == $s.key)
              | if (.ruled | not) and .sentence == "" and $anyruled then .sentence = "Not ruled yet." else . end ]
            | select(length > 0)
            | "**" + $s.title + "**\n" + (map(ra_entry) | join("\n"))),
         (if ($m.notes | length) > 0 then
            "<details>\n<summary>Notes from the fix</summary>\n\n"
            + ([ $m.notes[] | (if ($m.notes | length) > 1 then "**" + .by + "**\n\n" else "" end)
                 + (.text | ra_cut(12000) | gsub("</details>"; "&lt;/details&gt;")) ] | join("\n\n"))
            + "\n\n</details>"
          else empty end) ]
       | join("\n\n"))
      + "\n\n" + $marker
      + ([ ($m.marks // [])[] | "\n<!-- gc-writeback-mark:" + . + " -->" ] | join(""))
      + "\n<!-- gc-review-answer:r" + $m.rid + " -->"
      + (if $m.dismissed == "requeued" or $m.dismissed == "self" then "\n<!-- gc-review-answer:r" + $m.rid + ":dismissed -->" else "" end);
  # The one-line note a dismissal of the review carries: the count line, the
  # comment holding the answer, and that dismissal is not approval.
  def ra_dismiss_note($url):
    (ra_heading) + " (" + $url + ")."
    + (if .self then " It was posted under the city account, so no fresh review is requested." else "" end)
    + " Dismissal is not approval; the merge still gates on an explicit approving review.";
'
