#!/usr/bin/env bash
# review-answer.sh — the city's one living answer to a human pull request
# review: what it says, built from bead state. Sourced, never executed.
#
# The answer's unit is the reviewer's round: the reviews one reviewer submitted
# against one commit (ra_round_key). A client can submit one pass as one GitHub
# review or as many, one per comment, and the round is that pass however many
# reviews carry it. A review submitted against a later commit starts a round of
# its own. Every round of a human review gets one Conversation comment, created
# when the city picks the round up and edited in place on every change after
# that. pr-facts.sh's write-back is its only writer: it builds a model per round
# from the round's findings and the PR it read (ra_models), renders the comment
# from it (ra_render), and edits the comment only when the rendering changed.
# GitHub dismisses review objects, so each review of a round is dismissed on its
# own, and the note that clears it is one line naming the round's comment
# (ra_dismiss_note).
#
# A comment belongs to the round of the review its key names. When the city
# holds more than one comment for a round, each keyed to one of its reviews, the
# round keeps one: the copy a dismissal note names, if one does, else the
# earliest. That copy takes every mark the others carry, and the writer deletes
# the others once it carries them.
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
# A review body ruled restates frames the inline comments of its round and is
# no point of its own, so it has no entry and no count.
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
# deferral's reply, so its entry carries that reply, quoted under the entry
# whenever the sentence is not the reply itself, and the comment is what
# delivers it, as it delivers the mark that records the body answered. A
# round stays live, and gets its comment, while a finding is open, a
# changes-requested block of one of its reviews stands, or the comment owes it
# an answer or a mark.
#
# The comment always fits the size GitHub takes in one comment, because the
# dismissal waits on it (ra_render). A long review shortens its notes from the
# fix first, then its quoted replies, then its sentences, and each cut names
# the bead that holds the whole text. Past the tightest caps it lists the
# points that fit and names the findings of the rest.
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
#
# Which rulings owe a human finding raiser an answer on the PR, and how that
# answer reads there, are REVIEW_OWED_REPLY_DEF. pr-facts.sh posts the answer in
# a thread or on the Conversation tab, the living answer carries a review body
# answer, and the review dismissal waits until each is delivered. All three read
# these defs, and REVIEW_ANSWER_DEF opens with them.
# shellcheck disable=SC2034  # read by the scripts that source this file
REVIEW_OWED_REPLY_DEF='
  # A ruling that owes its raiser an answer when the finding carries one
  # (finding.reply): a decline, a deferral, or a question for the operator.
  def ra_owes_disp: . == "declined" or . == "deferred" or . == "needs-you";
  # A decline or a deferral reply as the PR shows it: led by its ruling, unless
  # it already opens with that word.
  def ra_ruled_reply($disp):
    if $disp == "declined" then (if test("^\\s*declin"; "i") then . else "Declined: " + . end)
    elif $disp == "deferred" then (if test("^\\s*defer"; "i") then . else "Deferred: " + . end)
    else . end;
'
# Which round a review belongs to is REVIEW_ROUND_DEF. pr-facts.sh stamps it on
# each human finding as it files one (finding.review_round), which is how
# finding.sh tells a review body that frames its round from one that is a whole
# review, and the write-back reads it off the PR to group the living answers and
# to hold a framing body review until its round is answered. REVIEW_ANSWER_DEF
# carries these defs too.
# shellcheck disable=SC2034  # read by the scripts that source this file
REVIEW_ROUND_DEF='
  # The round of a review submitted by $login against commit $oid, named by
  # both, or empty when either is unknown.
  def ra_round_key($login; $oid):
    (($login // "") | tostring) as $l | (($oid // "") | tostring) as $o
    | if $l != "" and $o != "" then $l + "@" + $o else "" end;
  # The round of every review the read of the PR holds ($view.reviews), by
  # review id. A review the read cannot place by author and commit is a round
  # of its own, r<id>.
  def ra_rounds($view):
    reduce ($view.reviews[]?) as $r ({};
      (($r.databaseId // 0) | tostring) as $id
      | .[$id] = (ra_round_key($r.author.login; $r.commit.oid) | if . != "" then . else "r" + $id end));
'
# shellcheck disable=SC2034  # read by the scripts that source this file
REVIEW_ANSWER_DEF="$REVIEW_OWED_REPLY_DEF$REVIEW_ROUND_DEF"'
  def ra_squash: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
  # At most $n characters, cut at a word boundary when one falls in the second
  # half, with an ellipsis marking the cut.
  def ra_cut($n):
    if length <= $n then .
    else .[0:$n] as $h | ($h | sub("\\s+\\S*$"; "")) as $w
      | (if ($w | length) >= ($n / 2) then $w else $h end) + "…" end;
  # The caps each rendering tries, loosest first (ra_render): a review too long
  # for one comment is shortened in its notes from the fix first, then in its
  # quoted replies, then in its sentences. A notes cap of 0 leaves the notes out
  # and names the fix units they are on.
  def ra_tiers: [ { notes: 12000, quote: 4000, sentence: 1500 },
                  { notes: 2000, quote: 4000, sentence: 1500 },
                  { notes: 0, quote: 4000, sentence: 1500 },
                  { notes: 0, quote: 1000, sentence: 1500 },
                  { notes: 0, quote: 1000, sentence: 400 },
                  { notes: 0, quote: 300, sentence: 200 } ];
  # At most about $n characters, cut the way ra_cut cuts, the cut naming the bead
  # that holds the whole text.
  def ra_clip($n; $where):
    if length <= $n then .
    else ra_cut($n) + (if $where != "" then " (the full text is on " + $where + ")" else "" end) end;
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
  # living comment delivers, since the comment sits in no thread.
  def ra_owes_reply: .body and .reply != "" and (.disp | ra_owes_disp);
  # A finding record as its point, or nothing for a body ruled restates. A
  # review body owed a decline or a deferral gets that reply whole in its entry:
  # as the sentence when the sentence is the reply and fits in one, and quoted
  # under the entry otherwise. A needs-you body answer is its visit, which the
  # entry names and the callout on top carries.
  def ra_point:
    . as $f
    | .disp as $d
    | ((.fix_answer // "") | ra_squash) as $fa
    | ((.answer // "") | ra_squash) as $an
    | ((.reply // "") | ra_squash) as $rp
    | ($rp | ra_ruled_reply($d)) as $ruled
    | ($f.body and ($d == "declined" or $d == "deferred") and $rp != "") as $carries
    | (if $carries and ($ruled | length) > ra_tiers[0].sentence then "" else $ruled end) as $said
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
          sentence: (if $an != "" then $an elif $said != "" then $said else "Declined; the reason follows." end),
          ref: "", answered: true }
      elif $d == "declined" then
        { section: "done", sentence: (if $an != "" then $an else "Noted; no change asked." end), ref: "", answered: true }
      elif $d == "deferred" then
        { section: "worth",
          sentence: (if $an != "" then $an elif $said != "" then $said
                     elif $rp != "" then "Deferred; the reason follows." else "Deferred to a follow-up." end),
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
            extra: (if $carries and .sentence != $ruled then $ruled else "" end) };
  # What follows the last write-back marker in a comment of ours: on a living
  # answer, the lines ra_trailer writes and the digest line after them. Its key
  # and its marks are read there alone, because the text above quotes what
  # reviewers and fix units wrote.
  def ra_tail($marker): (.body // "") | tostring | split($marker) | if length > 1 then .[-1] else "" end;
  # The review ids a mark line names.
  def ra_mark_rids: [ split(" ")[1:][] | select(startswith("r")) | .[1:] ];
  # Each value once, in the order it first comes.
  def ra_once: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [ $x ] end);
  # One model per round the human findings on input name. rid is its lowest
  # review id, the one its comment is keyed by, rids every review of it with a
  # finding, and members the same reviews, each with the state GitHub reads and
  # how it reads dismissed. Then its points, the visits waiting on the operator,
  # the fix notes, the mark lines the plan owes it, the comment it keeps
  # (existing) and the ids of the other copies the city holds (strays). $vl maps
  # a review id to the mark lines and batch visits the write-back plan asks of
  # it ({marks, visits, swaps}), and $beads maps a bead id to the title, fix
  # notes and close read for it. A review dismissed with every finding of its
  # own closed reads as re-requested when a copy carries its dismissed mark, or
  # when the read of the PR lists its author among the pending review requests
  # ($view.requested). So a dismissal whose edit of the comment failed still
  # says so on the next pass.
  def ra_models($view; $prurl; $self; $vl; $beads; $marker):
    ra_rounds($view) as $rounds
    | [ $view.issue_comments[]?
        | select(((.author.login // "") == $self) and ((.body // "") | contains($marker)))
        | ra_tail($marker) as $t
        | (($t | capture("<!-- gc-review-answer:r(?<k>[0-9]+) -->") | .k) // "") as $k
        | select($k != "")
        | { dbn: (.databaseId // 0), db: ((.databaseId // 0) | tostring), key: $k, tail: $t,
            url: (if ((.url // "") | tostring) != "" then .url else $prurl + "#issuecomment-" + ((.databaseId // 0) | tostring) end),
            round: ($rounds[$k] // ("r" + $k)) } ] as $answers
    | [ .[]? | select(((.metadata.task_kind // "") | tostring) == "finding")
             | select(((.metadata["finding.lane"] // "") | tostring) == "human")
             | ra_record($view; $prurl; $beads) | select(.rid != "")
             | . + { round: ($rounds[.rid] // ("r" + .rid)) } ]
    | group_by(.round)
    | map(
        .[0].round as $round
        | . as $fs
        | ([ $fs[].rid ] | unique | sort_by(tonumber? // 0)) as $rids
        | $rids[0] as $rid
        | (first($view.reviews[]? | select(((.databaseId // 0) | tostring) == $rid)) // {}) as $rv
        | ((($rv.author.login // "") | tostring)) as $login
        | ($login != "" and $login == $self) as $selfrev
        | ([ $answers[] | select(.round == $round) ] | sort_by(.dbn)) as $copies
        | [ $rids[] as $r
            | (((first($view.reviews[]? | select(((.databaseId // 0) | tostring) == $r)) // {}).state // "") | tostring) as $st
            | { rid: $r, state: $st,
                dismissed: (if any($copies[]; .tail | contains("<!-- gc-review-answer:r" + $r + ":dismissed -->"))
                              then (if $selfrev then "self" else "requeued" end)
                            elif $st == "DISMISSED" and all($fs[] | select(.rid == $r); .open | not)
                              then (if $login != "" and any(($view.requested // [])[]; . == $login) then "requeued" else "plain" end)
                            else "" end) } ] as $members
        # The copy the round keeps is the one a dismissal note names: it carries
        # a dismissed mark, or the key of a review GitHub reads dismissed. Else
        # it is the earliest.
        | (first($copies[] | select(.tail | test("<!-- gc-review-answer:r[0-9]+:dismissed -->")))
           // first($copies[] | . as $c | select(any($members[]; .rid == $c.key and .state == "DISMISSED")))
           // $copies[0]) as $ex
        | (if $ex == null then null
           else { db: $ex.db, url: $ex.url,
                  digest: (($ex.tail | capture("<!-- gc-review-answer:r[0-9]+:digest:(?<d>[0-9]+) -->") | .d) // "") } end) as $have
        # The mark lines its copies carry stand until the plan names new ones for
        # the review they mark: a review body leaves the plan once its review is
        # dismissed, and dropping its mark then would only rewrite the comment.
        | ([ ($ex // empty), ($copies[] | select(.db != $ex.db)) | .tail
             | scan("<!-- gc-writeback-mark:([^ >]+(?: [ri][0-9]+)*) -->") | .[0] ] | ra_once) as $exmarks
        | ([ $rids[] as $r | ((($vl[$r] // {}).marks // [])) as $w
             | if ($w | length) > 0 then $w[] else ($exmarks[] | select(ra_mark_rids | any(.[]; . == $r))) end ]
           + [ $exmarks[] | select(ra_mark_rids | all(.[]; . as $x | all($rids[]; . != $x))) ]
           | ra_once) as $marks
        | ($fs | sort_by([ (if .body then 0 else 1 end), ((.cid | tonumber?) // 0) ])) as $sorted
        | [ $sorted[] | ra_point ] as $ps
        | ([ $fs[] | select(.disp == "needs-you" and .open and .visit != "")
             | { id: .visit, question: (if (.answer | ra_squash) != "" then (.answer | ra_squash) else "This comment needs your decision." end) } ]
           + [ $rids[] as $r | ((($vl[$r] // {}).visits // []))[] | { id: ., question: ((($beads[.] // {}).title // "") | tostring | ra_squash) } ]
           | reduce .[] as $x ([]; if any(.[]; .id == $x.id) then . else . + [ $x ] end)) as $visits
        | ([ $fs[] | .fix_unit | select(. != "") ] | unique
           | map({ by: ., text: ((($beads[.] // {}).fix_notes // "") | tostring) }) | map(select(.text | test("\\S")))) as $notes
        | ([ $fs[] | select(ra_owes_reply) | .id ]) as $replied
        | { rid: $rid, rids: $rids, members: $members, self: $selfrev, author: $login,
            points: $ps, visits: $visits, notes: $notes, marks: $marks,
            swaps: ([ $rids[] as $r | ((($vl[$r] // {}).swaps // "-")) | select(. != "-") ] | if length > 0 then join(",") else "-" end),
            replied: $replied,
            unstamped: [ $fs[] | select(ra_owes_reply and (.posted | not)) | .id ],
            existing: $have,
            strays: [ $copies[] | select(.db != ($have.db // "")) | .db ],
            live: (any($fs[]; .open) or any($members[]; .state == "CHANGES_REQUESTED")
                   or any($fs[]; ra_owes_reply and (.posted | not))
                   or any($rids[]; ((($vl[.] // {}).marks // []) | length) > 0)) });
  # How the round reads dismissed: not at all while a review of it still stands
  # changes-requested, and otherwise the most any review of it reads, a
  # re-request first.
  def ra_dismissal:
    (.members // []) as $ms
    | if any($ms[]; .state == "CHANGES_REQUESTED" and (.dismissed // "") == "") then ""
      else (first(("requeued", "self", "plain") as $d | select(any($ms[]; .dismissed == $d)) | $d) // "") end;
  # The model once the writer has dismissed its review $rid.
  def ra_dismiss_member($rid):
    .self as $s
    | .members = [ (.members // [])[] | if .rid == $rid then .dismissed = (if $s then "self" else "requeued" end) else . end ];
  def ra_count($n; $word): "\($n) \($word)" + (if $n == 1 then "" else "s" end);
  # The count line: how many points the review raised and how far they are. It
  # names no commit, so a push leaves a settled review comment as it stands;
  # each point cites the commits that answered it.
  def ra_heading:
    (.points // []) as $ps | ($ps | length) as $n
    | ([ $ps[] | select(.answered) ] | length) as $k
    | "Your review: " + ra_count($n; "point")
      + (if $n > 0 and $k == $n then ", all answered"
         elif $k > 0 then ", \($k) answered so far"
         elif any($ps[]; .ruled | not) then ", picked up; the ruling is in progress"
         else ", none answered yet" end);
  def ra_sections: [ { key: "needs", title: "Needs you", one: "needs you", many: "need you" },
                     { key: "worth", title: "Worth a look", one: "worth a look", many: "worth a look" },
                     { key: "progress", title: "In progress", one: "in progress", many: "in progress" },
                     { key: "done", title: "Done", one: "done", many: "done" } ];
  def ra_same: ascii_downcase | gsub("[^\\p{L}\\p{N}]+"; "");
  # One point as a list entry at the caps $c (ra_tiers). A sentence that only
  # repeats the label is left out, and so is a reference the sentence already
  # names; a sentence several times the label length is never only a repeat of
  # it. A clipped sentence or quoted reply names the finding holding it whole.
  def ra_entry($c):
    (.label | if test("[.?!…]$") then . else . + "." end) as $l
    | ((.id // "") | tostring) as $id
    | ((.ref // "") | tostring) as $ref
    | ((.sentence // "") | ra_clip($c.sentence; $id) | ra_squash) as $s
    | (if ($s | length) <= 4 * ((.label | length) + 8) and ($s | ra_same) == (.label | ra_same) then "" else $s end) as $say
    | "- **" + (if (.url // "") != "" then "[" + $l + "](" + .url + ")" else $l end) + "**"
      + (if $say != "" then " " + $say else "" end)
      + (if $ref == "" or (($say | contains($ref)) and ($ref | startswith("{{") | not)) then ""
         elif ($ref | startswith("{{")) then $ref
         else " (" + $ref + ")" end)
      + (if (.extra // "") != "" then "\n" + ([ .extra | ra_clip($c.quote; $id) | split("\n")[] | "  > " + . ] | join("\n")) else "" end);
  # Text cut inside a fenced code block gets the fence closed, so the cut does
  # not swallow the markup after it.
  def ra_fence_closed: if ([ scan("(?:^|\\n)[ \\t]*```") ] | length) % 2 == 1 then . + "\n```" else . end;
  # The notes from the fix at the caps $c: folded under the points, each fix
  # unit notes clipped to the cap and naming the fix unit holding them whole, or
  # at a cap of 0 one line naming the fix units they are on.
  def ra_notes($c):
    .notes as $ns
    | if ($ns | length) == 0 then empty
      elif $c.notes == 0 then
        "The notes from the fix are on " + ([ $ns[].by ] | join(", ")) + ", left out here to fit the size GitHub allows a comment."
      else
        "<details>\n<summary>Notes from the fix</summary>\n\n"
        + ([ $ns[] | .by as $by
             | (if ($ns | length) > 1 then "**" + $by + "**\n\n" else "" end)
               + (.text | ra_clip($c.notes; $by) | ra_fence_closed | gsub("</details>"; "&lt;/details&gt;")) ] | join("\n\n"))
        + "\n\n</details>"
      end;
  # The comment above its trailing lines at the caps $c, listing the points in
  # $shown (ra_render orders and fills them): every point, or the first ones
  # when even the tightest caps leave the comment too long, with a line naming
  # the findings of the points left out. The counts always cover every point.
  # $c.bare leaves out the callout and the notes, the last resort ra_render has.
  def ra_body($c; $shown):
    . as $m
    | ($m.points // []) as $ps
    | any($ps[]; .ruled) as $anyruled
    | ($m | ra_dismissal) as $dm
    | (($ps | map(.id)) - ($shown | map(.id))) as $out
    | [ if ($m.visits | length) > 0 and ($c.bare | not) then
          "> [!IMPORTANT]\n" + ([ $m.visits[] | . as $v | "> **Needs you: visit " + $v.id + ".**"
                                  + (if ($v.question // "") != "" then " " + ($v.question | ra_clip($c.sentence; $v.id)) else "" end) ]
                                | join("\n>\n"))
        else empty end,
        "### " + ($m | ra_heading),
        ([ (if $dm == "requeued" then "Review dismissed; your review is requested again."
            elif $dm != "" then "Review dismissed." else empty end),
           (if $anyruled then
              ([ ra_sections[] | . as $s | ([ $ps[] | select(.section == $s.key) ] | length) as $nc
                 | select($nc > 0) | "\($nc) " + (if $nc == 1 then $s.one else $s.many end) ] | join(", ")) + "."
            else empty end) ] | join(" ") | select(. != "")),
        (ra_sections[] | . as $s | [ $shown[] | select(.section == $s.key) ]
           | select(length > 0)
           | "**" + $s.title + "**\n" + (map(ra_entry($c)) | join("\n"))),
        (($out | length) as $no
         | if $no == 0 then empty
           else (if $no == 1 then "1 more point is left out here to fit the size GitHub allows a comment; its finding is "
                 else "\($no) more points are left out here to fit the size GitHub allows a comment; their findings are " end)
             + ($out[0:30] | join(", ")) + (if $no > 30 then " and \($no - 30) more" else "" end) + "."
           end),
        (if $c.bare then empty else $m | ra_notes($c) end) ]
    | join("\n\n");
  # The lines the comment ends with: the write-back marker, the mark lines the
  # plan owes it, the key of the lowest review of the round, which it is found
  # again by, and a dismissed mark for each review of the round the writer
  # dismissed.
  def ra_trailer($marker):
    $marker
    + ([ (.marks // [])[] | "\n<!-- gc-writeback-mark:" + . + " -->" ] | join(""))
    + "\n<!-- gc-review-answer:r" + .rid + " -->"
    + ([ (.members // [])[] | select(.dismissed == "requeued" or .dismissed == "self")
         | "\n<!-- gc-review-answer:r" + .rid + ":dismissed -->" ] | join(""));
  # GitHub refuses a comment over 65,536 characters, and the dismissal waits on
  # the comment, so a comment that outgrew it would hold its review forever. The
  # comment stays under ra_budget, counted in UTF-8 bytes, never fewer than its
  # characters, with each commit token at the longest citation wb_expand
  # (pr-facts.sh) can turn it into. The room above the budget holds the digest
  # line and the city mark added after it.
  def ra_budget: 60000;
  def ra_size: utf8bytelength + 80 * ((split("{{gc-commits:") | length) - 1);
  # The comment body at the loosest caps under which it fits ra_budget, ending
  # with its trailing lines. Past the tightest caps, the points are listed in
  # section order for as long as they fit, and the rest are named. The writer
  # appends the digest line. $marker is the write-back reply marker.
  def ra_render($marker):
    . as $m
    | ($m | ra_trailer($marker)) as $tail
    | any(($m.points // [])[]; .ruled) as $anyruled
    | [ ra_sections[] as $s | ($m.points // [])[] | select(.section == $s.key)
        | if (.ruled | not) and .sentence == "" and $anyruled then .sentence = "Not ruled yet." else . end ] as $all
    | first( ra_tiers[] as $c | ($m | ra_body($c; $all)) + "\n\n" + $tail | select(ra_size <= ra_budget) )
      // ( ra_tiers[-1] as $c
           | (ra_budget - ((($m | ra_body($c; [])) + "\n\n" + $tail) | ra_size) - 200) as $room
           | (reduce ($all[] | ra_entry($c) | ra_size + 1) as $z ({ sum: 0, k: 0, full: false };
                if .full or .sum + $z > $room then .full = true else .sum += $z | .k += 1 end) | .k) as $k
           | ($m | ra_body($c; $all[0:$k])) + "\n\n" + $tail | select(ra_size <= ra_budget) )
      // (($m | ra_body(ra_tiers[-1] + { bare: true }; [])) + "\n\n" + $tail);
  # The one-line note a dismissal of the review carries: the count line, the
  # comment holding the answer, and that dismissal is not approval.
  def ra_dismiss_note($url):
    (ra_heading) + " (" + $url + ")."
    + (if .self then " It was posted under the city account, so no fresh review is requested." else "" end)
    + " Dismissal is not approval; the merge still gates on an explicit approving review.";
'
