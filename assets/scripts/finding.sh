#!/usr/bin/env bash
# finding.sh — the finding-bead primitive for the review cycle.
#
# A finding is a review objection with an identity of its own: a bead, not a
# line in a review body. It survives the rebase that destroys a commit oid, and
# one objection cannot be filed twice, because the cardinality is many findings
# to one fix unit — one work bead may answer three related findings and close
# them together. The bead's shape (docs/component-model.md, lifecycle.toml
# [metadata.review_findings]):
#
#   task_kind            finding
#   anchor_bead          the gating anchor, which the finding also has its
#                        membership edge onto (bd-lib.sh's anchor graph)
#   finding.lane         the lane whose review raised it, or `human`
#   finding.key          lane name + normalized locus + message; the dedup handle
#   finding.disposition  unvalidated | must-fix | deferred | declined | needs-you
#                        | restates
#   finding.source       machine:<lane> | human:<login>
#   finding.comment_id   the GitHub comment databaseId that raised it (stamped by
#                        pr-facts.sh for a human finding): an inline comment, whose
#                        thread the write-back posts an owed reply into, a review
#                        body, or a Conversation comment
#   finding.reply        the answer a HUMAN objection owes its raiser, which
#                        pr-facts.sh's write-back delivers: a reply in the inline
#                        comment's thread, the review's living answer for a review
#                        body, or a Conversation comment linking a Conversation
#                        comment. A declined finding's overrule, a deferred
#                        finding's follow-up id, or a needs-you finding's visit id.
#                        A machine or no-objection finding owes none and sets it not,
#                        and a ruling that owes none clears one an earlier ruling set
#   finding.label        a few words naming the point, which the validator writes as
#                        it rules (--label); the review's living answer shows it when
#                        the comment opens with no bold headline of its own
#   finding.answer       the one sentence the validator answers the point with in the
#                        review's living answer (--answer): a decline's reason, a
#                        deferral, or for needs-you the question (its --reason when
#                        no --answer is given). Each ruling sets or clears both, so
#                        neither outlives the ruling that wrote it
#   finding.fix_answer   the fix unit's own sentence on how it answered the point
#                        compared with what was asked (the answer verb)
#   finding.fix_flag     1 when the fix unit flags the point for the reviewer's look:
#                        it chose among options they left open, departed from their
#                        suggestion, or changed code the ruling declined
#   finding.follow_up    the deferred finding's later-work bead, armed to its fix
#                        pool (deferred-dispatch) to dispatch once the anchor merges
#   finding.visit        the open visit that carries a needs-you finding's decision:
#                        one the ruling filed, or one already open on the anchor's
#                        feedback that the ruling named
#   finding.ruling_visit the visit whose recorded ruling released a needs-you
#                        finding: its finding.visit, or the visit a fold handed
#                        the question on to (close-answered)
#   finding.fix_unit     the rework child dispatched with the batch that raised it
#                        (`upsert --fix-unit`, from pr-facts.sh for a human batch);
#                        a later batch re-raising the finding records its own child
#
# The fix unit keeps its own notes on the round as fix_notes (the fix-notes verb),
# which the review's living answer shows folded under the points.
#
# What a ruled finding holds, and how it ends (component-model I1: no wait lives
# only in a metadata string):
#
#   must-fix   finding --blocks anchor    holds the merge and the close until the
#                                         fix unit answering it lands; then closed
#   deferred   closed; a follow-up bead   the objection is not fixed in this PR — the
#              gated behind the anchor,   follow-up carries the later work and is armed
#              armed to its fix pool,     to dispatch to the fix pool once the anchor
#              --discovered-from finding  merges; the finding closes holding nothing
#   declined   closed, no edge            not an objection: closed with the reason
#   restates   closed, no edge            a human review body that only frames the
#                                         review's own inline comments, each a finding
#                                         of its own: no point of its own, no answer
#                                         owed, and no entry in the living answer
#   needs-you  stays open, no edge        only the operator can judge it — a visit
#                                         carries the decision and the open finding
#                                         holds the review until the operator rules
#                                         that visit, or the one a fold handed it to,
#                                         and no fix unit on its lane, nor a ruling's
#                                         rework child, is in flight; then closed
#                                         (close-answered)
#
# `blocks` is the type must-fix uses, and not because it is the only edge that
# blocks a close: merge.sh reads exactly `blocks` downward, so a finding held by
# any other type would leave the PR free to land with the objection still open.
# Every ruling ends the finding closed or converts it to a visit: a deferred,
# declined or restates finding closes, so the human review it belongs to
# auto-dismisses once every finding clears (pr-facts.sh); a needs-you finding
# stays open, which is what holds that review until the operator rules its visit
# and the work their ruling calls for lands. The discovered-from edge is the
# follow-up's own — a dispatchable bead — and points at the finding it carries
# forward. bd keeps one edge per (issue, depends_on) pair, and the
# follow-up/anchor pair is the gate's.
# Both edges ride the create that files the follow-up, and so does its
# source_finding stamp naming the finding. A deferral retried after a failure
# finds the follow-up the failed attempt filed by that stamp, so the retry files
# no second one.
#
# The route never lives on a finding. A finding states an objection; the bead
# that is dispatched is the fix unit, which carries two `blocks` edges — one
# onto every finding it answers (the many-to-one relation and the close
# ordering), one onto the anchor (the routed live blocker merge.sh already
# reads). The finding edge is hung as the validator rules that finding
# must-fix, never at dispatch: a fix unit wired to a still-unvalidated finding
# would block the very close a later declined ruling needs, and bd refuses to
# close a blocked issue. Routing a finding would make each its own claim and
# break that cardinality. upsert hangs one such edge outside a ruling: a later
# batch's child onto a finding already ruled must-fix that the batch re-raised.
# The ruling is never re-run, and that child was dispatched to answer it too.
#
# Which fix unit answers a finding is recorded on the finding as it is filed
# (finding.fix_unit), because only the filer knows which child carries its batch:
# pr-facts.sh records the child it dispatched with a human feedback batch. An
# anchor can carry other rework children beside that one: earlier batches'
# children, a stale-base merge-in, a red-check rework. A finding wired to one of
# those closes as answered the moment that child lands, before the work answering
# it does. The lane-level match (anchor_fix_unit) is the fallback for a finding
# filed without one.
#
# A human finding's question can reach the operator before this ruling does: the
# rework minted for its feedback batch put it to them in a visit, which tracks the
# rework or holds it through a blocks edge. A merits ruling then answers a
# decision the operator holds. A decline or a deferral overrules it, and restates
# rules it no point of its own; each closes the finding, which lets pr-facts.sh
# dismiss their review while they are still deciding. must-fix settles it as
# "keep the change and fix it", and a fresh needs-you visit asks them the same
# question twice. So set-disposition refuses each of those while such a visit is
# open (exit 3), naming it. needs-you --visit <that
# visit> is the ruling that defers to it, and --unrelated-visit names a visit that
# asks something else, so the ruling proceeds past it with that judgment on record.
#
# Verbs:
#   finding.sh key           --lane L --locus LOC --message MSG
#   finding.sh upsert        --anchor A --lane L --locus LOC --message MSG [--source S] [--fix-unit FU]
#   finding.sh set-disposition --finding F --anchor A --disposition D [--reason R] [--reply TEXT] [--fix-pool POOL]
#                              [--visit V] [--unrelated-visit V1,V2,...] [--label L] [--answer TEXT]
#   finding.sh answer        --finding F --answer TEXT [--flag]
#   finding.sh fix-notes     --fix-unit FU (--notes TEXT | --notes-file PATH)
#   finding.sh open-visits   --anchor A
#   finding.sh wire-fix-unit --fix-unit FU --anchor A --findings F1,F2,...
#   finding.sh open-must-fix --anchor A [--lane L]
#   finding.sh fix-in-flight --anchor A
#   finding.sh close-unvalidated --anchor A --lane L | --lanes L1,L2,... [--reason R]
#   finding.sh shed-orphaned [--reason R]
#   finding.sh close-answered --anchor A [--reason R]
#
# Callers: signoff.sh (upsert on request-changes), pr-facts.sh (upsert
# --fix-unit for each item of a human feedback batch), the validator through
# set-disposition — which hangs the fix unit's edge onto a finding only as it
# rules that finding must-fix, so the fix unit blocks only the findings it must
# answer — and through open-visits, which it reads beside the batch it rules;
# the fix unit answering a human batch (answer and fix-notes, as the rework
# child's description from pr-facts.sh says);
# pr-open.sh (open-must-fix holds a publish while the city has ruled the diff must
# change), and gate-ensure, the sole owner of stage-3 resolution (fix-in-flight
# names the fix unit quiescence holds on; close-answered releases a must-fix
# finding once that fix unit lands, and a needs-you finding once the operator has
# ruled the visit holding its question, with none in flight; close-unvalidated
# resolves a green lane's still-unvalidated findings as moot; shed-orphaned
# resolves them when the anchor closes before a pass revisits it).
# Exit 0 on success; a read verb exits 1 when its predicate is false, 2 when the
# store would not read. set-disposition exits 1 on a usage error, 2 when a read or
# write fails, and 3 when an open visit already carries the finding's question.
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=visit-identity.sh
. "${GC_VISIT_IDENTITY_LIB:-$_bd_lib_dir/visit-identity.sh}" || { echo "cannot source visit-identity.sh beside this script" >&2; exit 1; }
warn() { echo "finding: $*" >&2; }

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
ALL_STATUSES="$LIVE_STATUSES,closed"

usage() {
  cat >&2 <<'USAGE'
usage:
  finding.sh key --lane <lane> --locus <locus> --message <msg>
  finding.sh upsert --anchor <id> --lane <lane> --locus <locus> --message <msg> [--source <src>] [--fix-unit <id>]
  finding.sh set-disposition --finding <id> --anchor <id> --disposition must-fix|deferred|declined|needs-you|restates [--reason <r>] [--reply <text>] [--fix-pool <pool>]
                             [--visit <visit-id>] [--unrelated-visit <visit-id,...>] [--label <label>] [--answer <sentence>]
  finding.sh answer --finding <id> --answer <sentence> [--flag]
  finding.sh fix-notes --fix-unit <id> (--notes <text> | --notes-file <path>)
  finding.sh open-visits --anchor <id>
  finding.sh wire-fix-unit --fix-unit <id> --anchor <id> --findings <id,id,...>
  finding.sh open-must-fix --anchor <id> [--lane <lane>]
  finding.sh fix-in-flight --anchor <id>
  finding.sh close-unvalidated --anchor <id> --lane <lane> | --lanes <l,l,...> [--reason <r>]
  finding.sh shed-orphaned [--reason <r>]
  finding.sh close-answered --anchor <id> [--reason <r>]
USAGE
}

# Normalize a locus or message into a rebase-stable token stream: lowercase,
# drop the line-number suffixes a rebase renumbers (`path:123`, `#L123`), and
# reduce every run of non-alphanumerics to one space. The result names no
# commit and no line, so the same objection keys the same after a rebase moves
# the code. What a locus normalizes to when the file is later renamed is the one
# case the design leaves open; this handles the common one, a diff that only
# renumbers.
normalize() {
  printf '%s' "${1:-}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/#l[0-9]+//g; s/:[0-9]+/ /g' \
    | tr -c 'a-z0-9' ' ' \
    | tr -s ' ' \
    | sed -E 's/^ +//; s/ +$//'
}

# finding.key = <lane>:<12 hex of sha256(normalized locus + US + message)>. The
# lane prefix keeps two reviewers' findings at one locus distinct; the hash is
# the dedup handle re-raising an objection collides on. GitHub's own review and
# comment ids would not serve: a re-review re-raises a still-standing objection
# under a fresh id, so an id key twins it every pass where the content key
# re-adopts.
compute_key() {
  local lane="$1" locus="$2" msg="$3" nloc nmsg h
  nloc=$(normalize "$locus")
  nmsg=$(normalize "$msg")
  h=$(printf '%s\037%s' "$nloc" "$nmsg" | sha256sum | cut -c1-12)
  printf '%s:%s' "$lane" "$h"
}

# The open finding on this anchor carrying this key, or empty. Dedup is against
# open findings only: a re-review while the objection still stands files
# nothing new, and an objection that recurs after its finding closed is a fresh
# one. Exits 2 (empty stdout) when the store would not read, so a caller can
# tell "no such finding" from "could not ask".
find_open_by_key() {
  local anchor="$1" key="$2" rows
  rows=$(bd_anchor_children "$anchor" "$LIVE_STATUSES") || return 2
  printf '%s' "$rows" | jq -r --arg k "$key" '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.key"] // "") | tostring) == $k) ]
    | .[0].id // empty' 2>/dev/null
}

edge_exists() { # <blocker> blocks <blocked> ?  (reads the blocked's down-blockers)
  local blocker="$1" blocked="$2"
  bd_json dep list "$blocked" --direction=down -t blocks \
    | jq -e --arg b "$blocker" 'type == "array" and any(.[]?; .id == $b)' >/dev/null 2>&1
}

# The rework fix units answering <finding-lane>'s objections on <anchor>, one
# "<id> <status>" per line, across ALL statuses. A fix unit carries
# task_kind=rework. signoff stamps source_review_bead on the child it files for a
# machine review's findings; pr-facts files one child per human batch, carrying
# the batch's review ids in source_review and no source_review_bead. pr-facts'
# stale-base merge-in and red-check children carry no source_review_bead either,
# so they share the human set. A finding is answered by the child of its own lane,
# so match on the lane — a human finding takes a child with no source_review_bead,
# a machine finding one that carries it — and no lane's finding is wired to
# another lane's child.
#
# Read as the anchor's children (anchor_bead + task_kind=rework), not by the
# anchor's blocks edges: the fix-unit->anchor blocks edge is itself sometimes
# absent, so a blocks walk would miss the very landed fix unit the
# close-answered backstop must see. Every status is read, because a landed fix
# unit is closed. Non-zero rc = the ledger would not read.
_anchor_reworks() { # <anchor-id> <finding-lane>
  local rows
  rows=$(bd_anchor_children "$1" "$ALL_STATUSES") || return 2
  # A ruling's rework child carries no source_review_bead either, but it answers
  # the ruling its source_ruling_bead names, not a finding, so no lane takes it.
  printf '%s' "$rows" | jq -r --arg lane "${2:-}" '
    .[]
    | select(((.metadata.task_kind // "") | tostring) == "rework")
    | select(((.metadata.source_ruling_bead // "") | tostring) == "")
    | select(
        if $lane == "human"
        then ((.metadata.source_review_bead // "") | tostring) == ""
        else ((.metadata.source_review_bead // "") | tostring) != ""
        end)
    | "\(.id) \((.status // "open") | ascii_downcase)"' 2>/dev/null
}

# The fix unit to hang a must-fix finding's close-ordering edge onto when the
# finding records none, or empty: a still-live one if any, else one that has
# already LANDED. The lane cannot tell the batch's own child from another child
# on the same lane, which is why a recorded finding.fix_unit wins. The landed
# fallback is what makes the wiring reliable — the dispatch of a fix unit and the
# validator's must-fix ruling race, so a fix unit can close before its finding is
# ruled, and hanging the edge only to a live fix unit (the old behavior) then left
# the finding edge-less and wedged the re-gate. A landed fix unit still blocking
# the finding is closeable (bd refuses a close only on an OPEN blocker), so
# close-answered closes the finding on the next pass. Non-zero rc = the ledger
# would not read.
anchor_fix_unit() { # <anchor-id> <finding-lane>
  local rw id
  rw=$(_anchor_reworks "$1" "${2:-}") || return 2
  id=$(printf '%s\n' "$rw" | awk 'NF && $2!="closed" {print $1; exit}')
  [ -n "$id" ] || id=$(printf '%s\n' "$rw" | awk 'NF && $2=="closed" {print $1; exit}')
  [ -n "$id" ] && printf '%s\n' "$id"
  return 0
}

# How many fix units answer <finding-lane> on <anchor>, as "<n_live> <n_landed>".
# close-answered reads this to disambiguate an edge-less must-fix finding: a landed
# fix unit with none still live means the close-ordering edge was missed and the
# fix is on the branch, so the finding must close rather than wedge the re-gate; a
# live fix unit means the fix is still in flight and the finding holds; no fix unit
# at all means an objection nothing has answered yet, which also holds. Non-zero rc
# = the ledger would not read.
anchor_fix_unit_census() { # <anchor-id> <finding-lane>
  local rw
  rw=$(_anchor_reworks "$1" "${2:-}") || return 2
  printf '%s\n' "$rw" | awk 'NF{ if ($2=="closed") c++; else l++ } END{ print (l+0)" "(c+0) }'
}

# Remove every blocks edge INTO <finding> — the beads that block it. A finding
# being declined or reclassified deferred holds nothing and answers no work, so
# nothing may block it: a fix unit wired to it before the validator ruled (or an
# edge left from an earlier must-fix ruling this pass overturns) would refuse the
# close with "cannot close blocked issue" and stall the validator's triage.
# Idempotent and best-effort per edge — the caller's own guard fails closed if the
# subsequent close does not stick.
strip_inbound_blocks() { # <finding>
  local blockers b
  blockers=$(bd_json dep list "$1" --direction=down -t blocks \
    | jq -r 'if type == "array" then .[]?.id else empty end' 2>/dev/null)
  for b in $blockers; do
    [ -n "$b" ] || continue
    gc bd dep remove "$1" "$b" >/dev/null 2>&1 \
      || gc bd dep remove "$b" "$1" >/dev/null 2>&1 || true
  done
}

# Drop the hold a must-fix ruling hung from <finding> onto <anchor>: the pair with
# the anchor depending on the finding. Only that pair is removed; the reverse pair
# is the finding's membership edge onto its anchor, which the anchor's
# closed-children read follows. A ruling that replaces must-fix calls this only
# after its own commit. Exit 1 when the hold survives.
release_hold() { # <finding> <anchor>
  edge_exists "$1" "$2" || return 0
  gc bd dep remove "$2" "$1" >/dev/null 2>&1 || true
  ! edge_exists "$1" "$2"
}

# The live follow-up a deferral of <finding> already filed, or empty. A follow-up
# is born discovered-from the finding it carries forward and stamped
# source_finding=<finding>, and the stamp is what marks it as the deferral's.
# Other beads are born discovered-from a finding too: scaffolding-sweep.sh files
# the bug that carries a disposed anchor's finding forward that way, and that bug
# takes its own route to a first reaction, so a dependent without the stamp is
# never taken for the follow-up. A closed one is not returned: a deferral must
# leave a follow-up that can still dispatch, and a closed bead never will. One
# deferral files one follow-up; if more are live, the first in id order is
# returned. Non-zero rc = the edges would not read, which is not "none filed".
deferred_follow_up() { # <finding>
  local rows
  rows=$(bd_json dep list "$1" --direction=up -t discovered-from) || return 2
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$rows" | jq -r --arg live "$LIVE_STATUSES" --arg f "$1" '
    ($live | split(",")) as $l
    | [ .[] | select(((.metadata.source_finding // "") | tostring) == $f)
            | select(((.status // "open") | tostring | ascii_downcase) as $s | $l | index($s)) | .id ]
    | sort | .[0] // empty' 2>/dev/null
}

# The open visits already on <anchor>'s feedback, as one JSON array of
# {id, key, title, on: [{bead, kind, how}]}. A visit is on the feedback when it
# covers the anchor or one of its rework children by the shared visit identity
# (visit-identity.sh: its tracks edge, or its gc.continuation_group stamp when it
# has none), or when it holds a rework child through a blocks edge, the way a bare
# rework parks itself on the question it put to the operator. kind is anchor or
# rework, and how is tracks or holds.
#
# Given a human finding's row (`gc bd show --json`), it keeps only the visits on
# the rework children minted for that finding's own feedback batch, the case
# set-disposition refuses on. The anchor's batch ledger names the bead each routed
# comment's batch went to (pr-facts.sh, comment-batch-ledger: one
# `<disposition>|<floor>|<mark>` record per batch in pr_comment_batch,
# pr_review_batch or pr_issue_comment_batch, each keyed by its own comment id
# space), and a comment rework's source_review names the reviews its batch
# carried. The ledger reaches a Conversation comment, which names no review, and
# source_review still names the batch after the ledger retires the record of an
# answered one. A visit on the anchor itself is left to the validator's judgment,
# because an anchor gathers visits about anything: a merge gate, a red check, a
# stuck dispatch.
#
# Reads the anchor's children of every status (bd_anchor_children) and every live
# visit in the store, plus, given a finding, the anchor's own row for its ledger.
# Exits 2 with nothing printed when any read fails, so no caller takes an unread
# store for an empty one.
_FEEDBACK_VISITS_JQ='
  def blockers: [ (.dependencies // [])[]
                  | select(((.dependency_type // .type) // "") == "blocks")
                  | ((.id // .depends_on_id) // "") | select(. != "") ];
  def ledger($l): [ ($l // "" | tostring) | split(";")[] | select(length > 0)
                    | split("|") | select(length == 3)
                    | { disp: .[0], lo: (.[1] | tonumber? // null), hi: (.[2] | tonumber? // null) }
                    | select(.lo != null and .hi != null) ];
  def among($xs): . as $x | any($xs[]; . == $x);
  .[0] as $beads | .[1] as $visits | (.[2][0] // null) as $fd | (.[3][0] // null) as $an
  | [ $beads[] | select(((.metadata.task_kind // "") | tostring) == "rework")
               | { id: ((.id // "") | tostring), held: blockers } ] as $rw
  | (if $f == "" then [ $rw[].id ]
     else
       (($fd.metadata["finding.comment_id"] // "") | tostring) as $c
       | (($fd.metadata["finding.review_id"] // "") | tostring) as $r
       | ($c | tonumber? // null) as $cn
       | (if $r != "" and $r == $c then ["pr_review_batch"]
          elif $r != "" then ["pr_comment_batch"]
          else ["pr_comment_batch", "pr_issue_comment_batch"] end) as $spaces
       | ( [ if $cn == null then empty
             else $spaces[] as $k | ledger(($an // {}).metadata[$k])[]
                  | select(.lo < $cn and $cn <= .hi) | .disp
                  | select(startswith("rework:")) | ltrimstr("rework:") end ]
         + [ $beads[] | select(((.metadata.task_kind // "") | tostring) == "rework")
                      | ((.metadata.source_review // "") | tostring | split(",")) as $sr
                      | select($r != "" and ($r | among($sr)))
                      | ((.id // "") | tostring) ] )
       | unique
     end) as $mine
  | [ $visits[]
      | select(((.metadata.task_kind // "") | tostring) == "visit")
      | select(((.status // "open") | tostring | ascii_downcase) != "closed")
      | ((.id // "") | tostring) as $v
      | visit_identity_subjects as $subj
      | ( (if $f == "" then [ $subj[] | select(. == $a) | { bead: ., kind: "anchor", how: "tracks" } ] else [] end)
        + [ $rw[] | select(.id | among($mine)) | .held as $held
                  | (if (.id | among($subj)) then { bead: .id, kind: "rework", how: "tracks" } else empty end),
                    (if ($v | among($held)) then { bead: .id, kind: "rework", how: "holds" } else empty end) ] ) as $on
      | select(($on | length) > 0)
      | { id: $v, key: ((.metadata.escalation_key // "") | tostring),
          title: ((.title // "") | tostring), on: $on } ]'
feedback_visits() { # <anchor-id> [<finding-row-json>]
  local beads visits frow="${2:-[]}" arow='[]'
  printf '%s' "$frow" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  beads=$(bd_anchor_children "$1" "$ALL_STATUSES") || return 2
  visits=$(bd_list --metadata-field task_kind=visit --status="$LIVE_STATUSES") || return 2
  if [ -n "${2:-}" ]; then
    arow=$(bd_json show "$1")
    printf '%s' "$arow" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || return 2
  fi
  # The reads reach jq on stdin, not as arguments: an anchor's beads can outgrow
  # the OS limit on one argument.
  printf '%s\n%s\n%s\n%s\n' "$beads" "$visits" "$frow" "$arow" \
    | jq -cs --arg a "$1" --arg f "${2:+finding}" "$VISIT_IDENTITY_JQ$_FEEDBACK_VISITS_JQ" 2>/dev/null \
    || return 2
}

# One line per visit in a feedback_visits array: the visit, how it sits on the
# anchor's feedback, its escalation_key ("-" for none), and its title.
visit_lines() { jq -r '.[] | [ .id, ([ .on[] | "\(.how) \(.kind) \(.bead)" ] | join(", ")),
                                (if .key == "" then "-" else .key end), .title ] | @tsv'; }

cmd_key() {
  local lane="" locus="" msg=""
  while [ $# -gt 0 ]; do case "$1" in
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --locus) locus="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --message) msg="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$lane" ] && [ -n "$locus" ] && [ -n "$msg" ] || { warn "key needs --lane, --locus, --message"; exit 1; }
  compute_key "$lane" "$locus" "$msg"
}

# A re-raised finding answers the child of the latest batch that raised it: that
# batch re-raised the objection after the earlier child was dispatched, and its
# child carries the objection in its own work order. Record that child, and when
# the finding is already ruled must-fix also hang its close-ordering edge, so the
# finding closes only once the latest child carrying it lands. The edge an earlier
# child hung stays, and close-answered closes the finding when every blocker has
# closed. Fail closed (exit 2): a finding left recording the earlier child closes
# as answered when that child lands, and the caller's retry re-adopts it.
#
# The disposition is read after the record is written, never before. A must-fix
# ruling can be in flight on the same finding, and it re-reads the record after it
# commits (set-disposition). Whichever side reads second sees the other's write,
# so one of them always hangs this child.
readopt_fix_unit() { # <finding> <fix-unit>
  local f="$1" fu="$2" row got disp wrote=""
  row=$(bd_json show "$f")
  printf '%s' "$row" | jq -e --arg id "$f" '.[0].id == $id' >/dev/null 2>&1 \
    || { warn "could not read re-raised finding $f to record fix unit $fu"; return 2; }
  got=$(printf '%s' "$row" | jq -r '(.[0].metadata["finding.fix_unit"] // "") | tostring' 2>/dev/null)
  if [ "$got" != "$fu" ]; then
    gc bd update "$f" --set-metadata finding.fix_unit="$fu" >/dev/null 2>&1 || true
    row=$(bd_json show "$f")
    got=$(printf '%s' "$row" | jq -r '(.[0].metadata["finding.fix_unit"] // "") | tostring' 2>/dev/null)
    [ "$got" = "$fu" ] \
      || { warn "re-raised finding $f did not record finding.fix_unit=$fu (got '$got')"; return 2; }
    wrote=1
  fi
  disp=$(printf '%s' "$row" | jq -r '(.[0].metadata["finding.disposition"] // "") | tostring' 2>/dev/null)
  if [ "$disp" = "must-fix" ] && ! edge_exists "$fu" "$f"; then
    gc bd dep "$fu" --blocks "$f" >/dev/null 2>&1 || true
    edge_exists "$fu" "$f" \
      || { warn "could not hang fix unit $fu --blocks re-raised must-fix finding $f"; return 2; }
    wrote=1
  fi
  [ -z "$wrote" ] || bd_cache_clear
  return 0
}

cmd_upsert() {
  local anchor="" lane="" locus="" msg="" source="" fix_unit=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --locus) locus="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --message) msg="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --source) source="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --fix-unit) fix_unit="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] && [ -n "$lane" ] && [ -n "$locus" ] && [ -n "$msg" ] \
    || { warn "upsert needs --anchor, --lane, --locus, --message"; exit 1; }
  [ -n "$source" ] || source="machine:$lane"
  local key existing
  key=$(compute_key "$lane" "$locus" "$msg")
  existing=$(find_open_by_key "$anchor" "$key"); local rc=$?
  if [ "$rc" -eq 2 ]; then
    warn "could not read findings on $anchor to dedup key $key; nothing filed"
    exit 2
  fi
  if [ -n "$existing" ]; then
    # re-raise: the existing finding, nothing created
    if [ -n "$fix_unit" ]; then readopt_fix_unit "$existing" "$fix_unit" || exit 2; fi
    printf '%s\n' "$existing"
    return 0
  fi
  # The title carries the human-readable objection; the locus and full message
  # live in the description. The key, not the title, is the dedup handle.
  local title desc meta id
  title="finding[$lane]: $(printf '%s' "$msg" | tr '\n' ' ' | cut -c1-120)"
  desc=$(printf 'Locus: %s\n\n%s\n\nRaised by %s reviewing anchor %s.' "$locus" "$msg" "$source" "$anchor")
  # The identity rides the create, one insert, so a finding bead exists fully
  # stamped or not at all, and so does its edge onto the anchor
  # (bd_create_child), which the anchor's closed-children read follows. A bead
  # stamped in a second write is left with no metadata when that write fails: no
  # finding reader selects it, and with no finding.key the next pass's dedup
  # misses it and files a stamped twin. The fix unit rides it too, so no ruling
  # can find the finding without its record.
  meta=$(jq -nc --arg ab "$anchor" --arg ln "$lane" --arg k "$key" --arg src "$source" --arg fu "$fix_unit" \
    '{task_kind: "finding", anchor_bead: $ab, "finding.lane": $ln, "finding.key": $k,
      "finding.disposition": "unvalidated", "finding.source": $src}
     + (if $fu == "" then {} else {"finding.fix_unit": $fu} end)' 2>/dev/null)
  [ -n "$meta" ] || { warn "could not build finding metadata for key $key on $anchor; nothing filed"; exit 2; }
  id=$(bd_create_child "$anchor" "$title" -t task -d "$desc" --metadata "$meta" --json 2>/dev/null | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
  # A new finding changes this anchor's findings list; drop the per-pass bd_list
  # cache so a same-pass re-read sees it (pr-facts files a finding for a human
  # comment, then re-reads to wire its fix unit). No-op outside a reconcile pass.
  bd_cache_clear
  # A create whose reply did not parse may still have landed, and the key it was
  # born with finds it.
  [ -n "$id" ] || id=$(find_open_by_key "$anchor" "$key")
  [ -n "$id" ] || { warn "could not create finding bead for key $key on $anchor"; exit 2; }
  local row got
  row=$(bd_json show "$id")
  got=$(printf '%s' "$row" | jq -r '(.[0].metadata["finding.key"] // "") | tostring' 2>/dev/null)
  if [ "$got" != "$key" ]; then
    # A bead that reads back with no key is a create whose payload did not land.
    # It is closed rather than left open where no finding reader sees it. A read
    # that failed proves nothing about the bead, so it closes nothing.
    if [ -z "$got" ] && printf '%s' "$row" | jq -e --arg id "$id" '.[0].id == $id' >/dev/null 2>&1; then
      bd_unmake "$id" "Unmade by finding.sh upsert: the create landed without its metadata, so no finding reader could see this bead. The next upsert of key $key on $anchor files the finding afresh." \
        || warn "could not close $id, which landed without its metadata"
    fi
    warn "finding $id key did not read back (got '$got', want '$key')"
    exit 2
  fi
  printf '%s\n' "$id"
}

cmd_set_disposition() {
  local finding="" anchor="" disp="" reason="" reply="" fix_pool="" visit="" unrelated="" label="" answer=""
  while [ $# -gt 0 ]; do case "$1" in
    --finding) finding="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --disposition) disp="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reply) reply="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --fix-pool) fix_pool="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --visit) visit="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --unrelated-visit) unrelated="${unrelated:+$unrelated,}${2:-}"; shift 2 || { usage; exit 1; } ;;
    --label) label="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --answer) answer="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$finding" ] && [ -n "$anchor" ] && [ -n "$disp" ] \
    || { warn "set-disposition needs --finding, --anchor, --disposition"; exit 1; }
  if [ -n "$visit" ] && [ "$disp" != needs-you ]; then
    warn "--visit names the open visit a needs-you ruling defers to; it does not apply to --disposition $disp"; exit 1
  fi
  # The words the review's living answer shows for this point ride the write
  # that commits the ruling, and that write clears each one the ruling does not
  # supply, so a ruled finding never shows an earlier ruling's words. A needs-you
  # ruling's question defaults to its reason. The reply is cleared the same way
  # by a ruling that owes none, below: a must-fix, a restates, and a decline
  # given no --reply.
  [ -n "$answer" ] || [ "$disp" != needs-you ] || answer="$reason"
  local words=()
  if [ -n "$label" ]; then words+=(--set-metadata "finding.label=$label"); else words+=(--unset-metadata finding.label); fi
  if [ -n "$answer" ]; then words+=(--set-metadata "finding.answer=$answer"); else words+=(--unset-metadata finding.answer); fi
  # restates is a review body that only frames its own inline comments, so it
  # takes a human finding raised by a review body (its comment is the review
  # itself) whose review raised at least one other finding on the anchor.
  if [ "$disp" = restates ]; then
    local rrow rrid rcid rsib
    rrow=$(bd_json show "$finding")
    rrid=$(printf '%s' "$rrow" | jq -r '(.[0].metadata["finding.review_id"] // "") | tostring' 2>/dev/null)
    rcid=$(printf '%s' "$rrow" | jq -r '(.[0].metadata["finding.comment_id"] // "") | tostring' 2>/dev/null)
    [ -n "$rrid" ] && [ "$rrid" = "$rcid" ] \
      || { warn "restates rules a review body, and $finding is not one (finding.review_id '$rrid', finding.comment_id '$rcid'); nothing ruled"; exit 1; }
    rsib=$(bd_list --metadata-field anchor_bead="$anchor" --status="$ALL_STATUSES" \
      | jq -r --arg r "$rrid" --arg f "$finding" '[ .[]? | select(.id != $f)
          | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.review_id"] // "") | tostring) == $r) ] | length' 2>/dev/null) \
      || { warn "could not read the findings on anchor $anchor to check $finding's review; nothing ruled"; exit 2; }
    case "$rsib" in ''|*[!0-9]*) warn "could not count the findings review $rrid raised on anchor $anchor; nothing ruled"; exit 2 ;; esac
    [ "$rsib" -gt 0 ] \
      || { warn "review $rrid raised no inline comment beside its body, so its body is the whole review and is ruled on its points; nothing ruled"; exit 1; }
  fi
  # Every ruling of a human finding but needs-you --visit first meets the visits
  # already carrying its question: an open visit on a rework child minted for the
  # finding's own feedback batch (feedback_visits). Each one the caller has not
  # named --unrelated-visit refuses the ruling, exit 3, before any write, so the
  # finding keeps its current disposition and the validator re-rules it. A merits
  # ruling would answer the operator's pending decision for them: a decline or a
  # deferral overrules it, restates rules it no point of its own, and must-fix
  # settles it as "keep the change and fix it". A decline, a deferral and a
  # restates ruling also close the finding, which lets the review dismiss while
  # the operator is still deciding. needs-you --visit is the deferral, so it skips
  # the check. A machine finding passes: no human raised it, so no visit holds its
  # question.
  local past=""
  case "$disp" in
    must-fix|declined|deferred|needs-you|restates)
      if [ -z "$visit" ]; then
        local frow held standing
        frow=$(bd_json show "$finding")
        printf '%s' "$frow" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
          || { warn "could not read finding $finding; nothing ruled"; exit 2; }
        if printf '%s' "$frow" | jq -e '.[0].metadata as $m
             | ((($m["finding.lane"] // "") | tostring) == "human")
               or ((($m["finding.source"] // "") | tostring) | startswith("human:"))' >/dev/null 2>&1; then
          held=$(feedback_visits "$anchor" "$frow") \
            || { warn "could not read the open visits on anchor $anchor's feedback; refusing to rule $finding $disp past them unread"; exit 2; }
          standing=$(printf '%s' "$held" | jq -c --arg u "$unrelated" \
            '($u | split(",") | map(select(. != ""))) as $un | [ .[] | select(.id as $v | any($un[]; . == $v) | not) ]' 2>/dev/null) \
            || { warn "could not filter the open visits on anchor $anchor's feedback"; exit 2; }
          if printf '%s' "$standing" | jq -e 'length > 0' >/dev/null 2>&1; then
            warn "$finding is a human comment whose question is already with the operator, in the open visit(s) below; nothing ruled."
            printf '%s' "$standing" | visit_lines | sed 's/^/  /' >&2
            warn "Rule it needs-you --visit <visit>: the finding stays open and its review changes-requested until that visit is ruled. A visit that asks something else is named with --unrelated-visit <visit>, and the ruling then proceeds past it."
            exit 3
          fi
          past=$(printf '%s' "$held" | jq -r '[ .[].id ] | join(", ")' 2>/dev/null)
        fi
      fi ;;
  esac
  # finding.disposition is the committing write of each arm, stamped last — never
  # up front. A disposition recorded before the ruling's follow-up, visit, or edge
  # exists outlives a fail-closed exit as a validated value, and the validator
  # retries only findings still `unvalidated` (formulas/mol-validate.toml), so the
  # half-done ruling is off the retry set and silently dropped — the orphan this
  # whole change retires. Until an arm reaches its commit the finding keeps its
  # current disposition (`unvalidated` on a first ruling), so any failure leaves it
  # retryable. The arms carry the per-disposition stamp; `*` rejects a bad name
  # before any write.
  #
  # The finding keeps what its current disposition holds until the commit, too. An
  # arm that replaces a must-fix ruling releases that ruling's hold on the anchor
  # only after its own commit lands, so a failure anywhere before the commit leaves
  # the finding must-fix and still holding the merge. A deferral, decline or
  # restates ruling closes the finding in its commit, and the edge left on a
  # closed finding holds nothing: bd refuses a close only on a live blocker, and
  # the merge counts only live blockers.
  case "$disp" in
    must-fix)
      # The hold merge.sh's blocker probe already reads. Idempotent: a re-run
      # over a finding already blocking the anchor adds no second edge.
      if ! edge_exists "$finding" "$anchor"; then
        gc bd dep "$finding" --blocks "$anchor" >/dev/null 2>&1 \
          || { warn "could not wire $finding --blocks $anchor for must-fix"; exit 2; }
      fi
      edge_exists "$finding" "$anchor" \
        || { warn "$finding does not block $anchor after must-fix wiring"; exit 2; }
      # The fix unit answers only the findings ruled must-fix, so its close-ordering
      # edge onto this finding is hung HERE, from the ruling — never at dispatch,
      # when the finding was still unvalidated and a later declined ruling could not
      # close it past that block. The fix unit is the one the finding records
      # (finding.fix_unit), live or already landed. A finding filed without one
      # takes anchor_fix_unit's lane match: a live fix unit, or the one that already
      # LANDED when the dispatch won the race with this ruling. A landed fix unit
      # still blocks the finding (bd refuses a close only on an OPEN blocker), so
      # close-answered closes the finding on the next pass rather than leaving it
      # edge-less and wedging the re-gate. Best-effort: the finding's own anchor edge
      # above is the hold, so a fix unit whose edge cannot be hung costs the close
      # ordering, never the merge hold. The anchor edge is the fix unit's own (hung
      # at dispatch), not re-hung here.
      local fu flane frow fu_now
      frow=$(bd_json show "$finding")
      fu=$(printf '%s' "$frow" | jq -r '(.[0].metadata["finding.fix_unit"] // "") | tostring' 2>/dev/null)
      flane=$(printf '%s' "$frow" | jq -r '(.[0].metadata["finding.lane"] // "") | tostring' 2>/dev/null)
      [ -n "$fu" ] || fu=$(anchor_fix_unit "$anchor" "$flane") || fu=""
      if [ -n "$fu" ] && ! edge_exists "$fu" "$finding"; then
        gc bd dep "$fu" --blocks "$finding" >/dev/null 2>&1 \
          || warn "could not hang fix unit $fu --blocks must-fix finding $finding; the finding's own anchor edge still holds the merge"
      fi
      # Commit the disposition now the anchor-blocking hold is proven wired.
      gc bd update "$finding" --set-metadata finding.disposition=must-fix ${words[@]+"${words[@]}"} --unset-metadata finding.reply >/dev/null 2>&1 \
        || { warn "could not record finding.disposition=must-fix on $finding"; exit 2; }
      # A later batch can re-raise this finding during the ruling and record its own
      # child after the read above. Its re-adoption reads the disposition only after
      # that write, and hangs the child once it reads must-fix. A child recorded
      # while the disposition still read unvalidated is hung here, from a re-read
      # after the commit. Best-effort like the edge above, since the ruling is
      # already committed.
      fu_now=$(bd_json show "$finding" | jq -r '(.[0].metadata["finding.fix_unit"] // "") | tostring' 2>/dev/null)
      if [ -n "$fu_now" ] && [ "$fu_now" != "$fu" ] && ! edge_exists "$fu_now" "$finding"; then
        gc bd dep "$fu_now" --blocks "$finding" >/dev/null 2>&1 \
          || warn "could not hang fix unit $fu_now --blocks must-fix finding $finding; the finding's own anchor edge still holds the merge"
      fi
      ;;
    deferred)
      # A real objection not fixed in this PR: it becomes tracked later-work. File a
      # follow-up bead carrying the objection and the deferral reason, gate it behind
      # the anchor, hang its discovered-from provenance onto the finding, record the
      # follow-up id as the reply the raiser's thread receives, and CLOSE the finding.
      # The close is what lets the human review auto-dismiss once every finding
      # clears; a deferral holds neither the merge nor the review.
      #
      # The follow-up must be a DISPATCHABLE unit, not a bare open task: pool workers
      # consume only routed or armed work, so a plain `gc bd create` leaves the
      # promised fix unclaimable — the silent drop this retires. Resolve the fix pool
      # and the dispatcher FIRST, before touching any edge or filing anything, so the
      # common "no pool" refusal leaves the finding exactly as it was (a prior must-fix
      # still holding the merge) rather than a half-done deferral, and files no orphan.
      # Fail closed throughout — a deferral whose follow-up cannot be proven
      # dispatchable does not close. The pool comes from --fix-pool, else the anchor
      # carries it (fix_target_pool, else the gc.execution_routed_to its pour stamped).
      local fixpool="$fix_pool"
      [ -n "$fixpool" ] || fixpool=$(bd_json show "$anchor" \
        | jq -r '(.[0].metadata["fix_target_pool"] // .[0].metadata["gc.execution_routed_to"] // "") | tostring' 2>/dev/null)
      { [ -n "$fixpool" ] && [ "$fixpool" != "null" ]; } \
        || { warn "deferred $finding: no fix pool to make its follow-up dispatchable (pass --fix-pool, or carry fix_target_pool / gc.execution_routed_to on anchor $anchor); NOT closing (an unroutable follow-up is the orphan this retires)"; exit 2; }
      local dispatcher="${GC_DEFERRED_DISPATCH_SH:-$_bd_lib_dir/deferred-dispatch.sh}"
      [ -x "$dispatcher" ] \
        || { warn "deferred $finding: deferred-dispatch.sh not executable at $dispatcher; cannot arm its follow-up; NOT closing"; exit 2; }
      # One finding has one follow-up. Every step after the follow-up is filed can
      # fail and exit 2, which leaves the finding at its prior disposition, so the
      # validator rules it again. That retry reuses the follow-up the failed attempt
      # filed. A second one would be armed beside the first, and both would dispatch
      # the same later-work once the anchor merges. A read that cannot tell whether
      # one was filed files nothing.
      local followup
      followup=$(deferred_follow_up "$finding") \
        || { warn "deferred $finding: could not read whether an earlier attempt filed its follow-up; NOT filing one"; exit 2; }
      if [ -z "$followup" ]; then
        # The follow-up carries the objection and the deferral reason, and it is
        # filed whole. Its gate rides the create: the anchor blocks it, so bd holds
        # it unready until merge-push closes the anchor. Its discovered-from edge
        # onto the finding rides the create too, and so does its source_finding
        # stamp. bd writes a create's bead, metadata and --deps edges in one
        # transaction, so no follow-up exists ungated or unstamped, and every one is
        # a stamped discovered-from dependent of the finding, which is how a retry
        # finds it. bd keeps one dependency per (issue, depends_on) pair, so the two
        # edges take two pairs, and the follow-up/anchor pair carries the gate
        # alone. A deferral with no tracked follow-up is the orphan this retires, so
        # fail closed if it cannot be filed.
        local ftitle fdesc fmeta
        ftitle=$(bd_json show "$finding" | jq -r '(.[0].title // "") | tostring' 2>/dev/null)
        [ -n "$ftitle" ] || ftitle="finding[$finding]"
        ftitle="follow-up: $(printf '%s' "$ftitle" | sed -E 's/^finding\[[^]]*\]: //')"
        fdesc=$(printf 'Deferred from the review of anchor %s (finding %s), to be picked up after the PR merges.\n\n%s' \
          "$anchor" "$finding" "${reason:-No reason recorded.}")
        fmeta=$(jq -nc --arg f "$finding" '{source_finding: $f}' 2>/dev/null)
        [ -n "$fmeta" ] \
          || { warn "deferred $finding: could not build its follow-up's metadata; NOT filing one"; exit 2; }
        followup=$(gc bd create "$ftitle" -t task -d "$fdesc" --metadata "$fmeta" --deps "blocked-by:$anchor,discovered-from:$finding" --json 2>/dev/null \
          | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
        # A create whose reply did not parse may still have landed, and the stamped
        # edge it was born with finds it.
        [ -n "$followup" ] || followup=$(deferred_follow_up "$finding")
        [ -n "$followup" ] \
          || { warn "could not file a follow-up bead for deferred finding $finding; NOT closing (a deferral with no tracked later-work is the orphan this retires)"; exit 2; }
      fi
      # The follow-up waits for the merge, then dispatches itself: deferred-dispatch's
      # reconcile slings it to the fix pool (--on mol-polecat-work) the moment its
      # gate clears. A reused follow-up whose gate is gone gets it back BEFORE it is
      # armed, so no reconcile pass dispatches it early, and one already armed to
      # the pool is not armed twice. Fail closed if the gate or the arm does not
      # hold, and read the arm back off the bead: an un-gated or un-armed follow-up
      # is the unclaimable orphan again, and the finding is about to close off the
      # validator's unvalidated set where nothing re-attempts it.
      if ! edge_exists "$anchor" "$followup"; then
        gc bd dep "$anchor" --blocks "$followup" >/dev/null 2>&1 \
          || { warn "deferred $finding: could not wire anchor $anchor --blocks follow-up $followup; NOT closing"; exit 2; }
      fi
      edge_exists "$anchor" "$followup" \
        || { warn "deferred $finding: anchor $anchor does not block follow-up $followup; NOT closing"; exit 2; }
      local armed
      armed=$(bd_json show "$followup" | jq -r '(.[0].metadata["gc.dispatch_when_ready"] // "") | tostring' 2>/dev/null)
      if [ "$armed" != "$fixpool" ]; then
        "$dispatcher" arm "$followup" --target "$fixpool" --sling-arg --on --sling-arg mol-polecat-work \
          --reason "deferred from the review of anchor $anchor (finding $finding); dispatch once the anchor merges" >/dev/null 2>&1 \
          || { warn "deferred $finding: could not arm follow-up $followup to '$fixpool'; NOT closing"; exit 2; }
        armed=$(bd_json show "$followup" | jq -r '(.[0].metadata["gc.dispatch_when_ready"] // "") | tostring' 2>/dev/null)
      fi
      [ "$armed" = "$fixpool" ] \
        || { warn "deferred $finding: follow-up $followup did not read back armed (gc.dispatch_when_ready='$armed', want '$fixpool'); NOT closing"; exit 2; }
      gc bd update "$finding" --set-metadata finding.follow_up="$followup" >/dev/null 2>&1 \
        || warn "could not stamp finding.follow_up=$followup on $finding"
      # The follow-up id is the answer the raiser is owed: pr-facts.sh's write-back
      # posts it into finding.comment_id's thread. Stamp it BEFORE the close and
      # fail closed if it does not stick — a finding closed without the reply is a
      # silent deferral the write-back can no longer post, and a closed finding is
      # off the validator's unvalidated set so nothing re-attempts it.
      local dreply="Deferred — tracked as follow-up $followup"
      [ -n "$reason" ] && dreply="$dreply: $reason"
      dreply="$dreply. It will be picked up after this merges."
      gc bd update "$finding" --set-metadata finding.reply="$dreply" >/dev/null 2>&1 \
        || { warn "could not stamp finding.reply on $finding; NOT closing (a silent deferral)"; exit 2; }
      # Nothing may block the finding at its close: a fix unit wired onto it by an
      # earlier must-fix ruling, or cross-wired at dispatch, would have bd refuse
      # the close with "cannot close blocked issue".
      strip_inbound_blocks "$finding"
      local dnote="deferred: tracked as follow-up $followup"
      [ -n "$reason" ] && dnote="$dnote — $reason"
      gc bd update "$finding" --set-metadata finding.disposition=deferred ${words[@]+"${words[@]}"} --status=closed --append-notes "$dnote" >/dev/null 2>&1 \
        || { warn "could not close deferred finding $finding"; exit 2; }
      release_hold "$finding" "$anchor" \
        || warn "deferred $finding still blocks $anchor after its close; the edge on a closed finding holds nothing"
      ;;
    declined)
      # No objection to answer: close it with the reason. A declined finding
      # holds nothing and nothing holds it, so both sides go: every blocker wired
      # INTO it just before the close, and its own must-fix hold on the anchor
      # once the close lands. The inbound strip is what the close depends on — a
      # fix unit wired onto this finding (from an earlier must-fix ruling, or a
      # dispatch that cross-wired before the validator ran) would make bd refuse
      # the close with "cannot close blocked issue" and stall the whole triage.
      #
      # A declined HUMAN objection owes its raiser an answer on the PR: the
      # operator read the diff and objected, so overruling them in silence is the
      # gap the peer model closes. Stamp the owed reply BEFORE the close, and fail
      # closed if it does not stick — a finding closed without the reply the
      # caller asked for is a silent decline the write-back can no longer post,
      # and a closed finding is off the validator's unvalidated set so nothing
      # re-attempts it. A machine or no-objection decline passes no --reply and
      # owes nothing, so its close clears any reply an earlier ruling stamped.
      local unreply=(--unset-metadata finding.reply)
      if [ -n "$reply" ]; then
        gc bd update "$finding" --set-metadata finding.reply="$reply" >/dev/null 2>&1 \
          || { warn "could not stamp finding.reply on $finding; NOT closing (a silent decline)"; exit 2; }
        unreply=()
      fi
      strip_inbound_blocks "$finding"
      local note="declined"
      [ -n "$reason" ] && note="declined: $reason"
      gc bd update "$finding" --set-metadata finding.disposition=declined ${words[@]+"${words[@]}"} ${unreply[@]+"${unreply[@]}"} --status=closed --append-notes "$note" >/dev/null 2>&1 \
        || { warn "could not close declined finding $finding"; exit 2; }
      release_hold "$finding" "$anchor" \
        || warn "declined $finding still blocks $anchor after its close; the edge on a closed finding holds nothing"
      ;;
    restates)
      # No point of its own: the inline comments it frames are each ruled, and
      # this closes holding nothing and owing no answer, like a no-objection
      # decline, but it reads as neither a refusal nor a second hold. As with a
      # decline, every blocker wired INTO it goes just before the close, and its
      # own must-fix hold on the anchor once the close lands.
      strip_inbound_blocks "$finding"
      local rnote="restates its review's inline comments"
      [ -n "$reason" ] && rnote="$rnote: $reason"
      gc bd update "$finding" --set-metadata finding.disposition=restates ${words[@]+"${words[@]}"} --unset-metadata finding.reply --status=closed --append-notes "$rnote" >/dev/null 2>&1 \
        || { warn "could not close restates finding $finding"; exit 2; }
      release_hold "$finding" "$anchor" \
        || warn "restates $finding still blocks $anchor after its close; the edge on a closed finding holds nothing"
      ;;
    needs-you)
      # The objection turns on a call only the operator can make, so this ruling
      # does not close the finding — it converts it to a visit, records the visit's
      # id as the reply the raiser's thread receives, and leaves the finding OPEN.
      # An open finding keeps pr-facts.sh from auto-dismissing the human review, so
      # the review holds the merge changes-requested until the operator rules the
      # visit; close-answered then closes the finding once no fix unit on its lane,
      # nor a ruling's rework child, is still in flight, which is when the work the
      # ruling calls for has landed. needs-you holds nothing of its own, so once the
      # ruling is committed it releases the hold a prior must-fix ruling hung and
      # strips inbound blocks: the hold is the review, carried by this finding
      # staying open.
      #
      # The visit is resolved before anything is written. --visit names one already
      # open on the anchor's feedback, which this ruling defers to rather than ask
      # the operator the same question twice; it must be on the anchor or one of
      # its rework children, so a mistyped or closed id cannot leave the finding
      # waiting on a visit nobody will rule. Without --visit, escalate.sh files one
      # visit per finding, keyed on its id; it dedups on the (escalation_key,
      # subject) pair, so a re-ruled finding reuses its open visit rather than
      # filing a second. The escalate path is overridable for the hermetic test.
      local vid vreply nnote
      if [ -n "$visit" ]; then
        local onfb
        onfb=$(feedback_visits "$anchor") \
          || { warn "could not read the open visits on anchor $anchor's feedback, so --visit $visit cannot be verified; nothing ruled"; exit 2; }
        printf '%s' "$onfb" | jq -e --arg v "$visit" 'any(.[]; .id == $v)' >/dev/null 2>&1 \
          || { warn "--visit $visit is not an open visit on anchor $anchor or one of its rework children; nothing ruled"; exit 1; }
        vid="$visit"
        vreply="This comment needs your decision, and visit $vid already asks you for it. The review stays changes-requested until you rule that visit and the work your ruling calls for lands."
        nnote="needs-you: deferred to open visit $vid, which already carries this question"
      else
        local vkey="review-needs-you.$finding" vmsg escalate
        vmsg="A review comment on anchor $anchor needs your decision; the review pass cannot judge it."
        [ -n "$reason" ] && vmsg="$vmsg $reason"
        escalate="${GC_ESCALATE_SH:-$_bd_lib_dir/escalate.sh}"
        [ -x "$escalate" ] \
          || { warn "escalate.sh not found beside this script; cannot file the needs-you visit for $finding"; exit 2; }
        "$escalate" --subject "$anchor" --key "$vkey" --message "$vmsg" >/dev/null 2>&1 \
          || { warn "could not file the needs-you visit for $finding (escalate.sh failed)"; exit 2; }
        # The open visit on this subject carrying our key — escalate.sh filed or
        # found exactly one. Its id is the answer the raiser is owed on the PR.
        vid=$(bd_list --metadata-field escalation_key="$vkey" --status="$LIVE_STATUSES" 2>/dev/null \
          | jq -r --arg a "$anchor" '[ .[]? | select(((.metadata["gc.continuation_group"] // "") | tostring) == $a) ] | .[0].id // empty' 2>/dev/null)
        [ -n "$vid" ] \
          || { warn "needs-you visit filed for $finding but its id did not read back; NOT recording a reply"; exit 2; }
        vreply="This comment needs your decision — opened visit $vid. The review stays changes-requested until you rule it and the work your ruling calls for lands."
        nnote="needs-you: opened visit $vid"
      fi
      gc bd update "$finding" \
        --set-metadata finding.disposition=needs-you \
        --set-metadata finding.visit="$vid" \
        --set-metadata finding.reply="$vreply" ${words[@]+"${words[@]}"} >/dev/null 2>&1 \
        || { warn "could not stamp finding.disposition/finding.visit/finding.reply on $finding"; exit 2; }
      release_hold "$finding" "$anchor" \
        || warn "needs-you $finding still blocks $anchor; that edge holds the merge until the finding closes"
      strip_inbound_blocks "$finding"
      [ -n "$reason" ] && nnote="$nnote — $reason"
      gc bd update "$finding" --append-notes "$nnote" >/dev/null 2>&1 \
        || warn "could not record the needs-you note on $finding"
      ;;
    *) warn "--disposition must be must-fix, deferred, declined, needs-you or restates (got '$disp')"; exit 1 ;;
  esac
  # A ruling that went past open visits the caller judged to ask something else
  # records that judgment on the finding, so a reader of the finding can weigh it.
  if [ -n "$past" ]; then
    gc bd update "$finding" --append-notes "ruled $disp past open visit(s) $past, judged by the validator not to carry this question" >/dev/null 2>&1 \
      || warn "could not record on $finding the open visits this ruling went past"
  fi
}

# The fix unit's own answer to one finding, which the review's living answer
# shows: one sentence on how the point was answered compared with what was
# asked (finding.fix_answer), and whether the reviewer should look at it
# (finding.fix_flag): the fix chose among options they left open, departed from
# their suggestion, or changed code the ruling declined. Each call states the
# whole answer, so one without --flag clears an earlier flag. Exit 1 on a usage
# error or a bead that is not a finding, 2 when a read or the write fails.
cmd_answer() {
  local finding="" answer="" flag=""
  while [ $# -gt 0 ]; do case "$1" in
    --finding) finding="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --answer) answer="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --flag) flag=1; shift ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$finding" ] && [ -n "$(printf '%s' "$answer" | tr -d '[:space:]')" ] \
    || { warn "answer needs --finding and a non-empty --answer"; exit 1; }
  local kind
  kind=$(bd_json show "$finding" | jq -r 'if type == "array" and length > 0 then ((.[0].metadata.task_kind // "") | tostring) else "?" end' 2>/dev/null) \
    || { warn "could not read $finding; nothing recorded"; exit 2; }
  case "$kind" in
    finding) : ;;
    "?") warn "could not read $finding; nothing recorded"; exit 2 ;;
    *) warn "$finding is not a finding (task_kind '$kind'); nothing recorded"; exit 1 ;;
  esac
  local fl=(--unset-metadata finding.fix_flag)
  [ -z "$flag" ] || fl=(--set-metadata finding.fix_flag=1)
  gc bd update "$finding" --set-metadata "finding.fix_answer=$answer" "${fl[@]}" >/dev/null 2>&1 \
    || { warn "could not record the answer on $finding"; exit 2; }
}

# The fix unit's notes on its round (fix_notes on the fix unit), which the
# review's living answer shows folded under the points. Each call replaces the
# notes. Exit 1 on a usage error or a bead that is not a fix unit, 2 when a read
# or the write fails.
cmd_fix_notes() {
  local fu="" notes="" nfile="" have=""
  while [ $# -gt 0 ]; do case "$1" in
    --fix-unit) fu="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --notes) notes="${2:-}"; have=1; shift 2 || { usage; exit 1; } ;;
    --notes-file) nfile="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$fu" ] || { warn "fix-notes needs --fix-unit"; exit 1; }
  if [ -n "$have" ] && [ -n "$nfile" ]; then
    warn "give --notes or --notes-file, not both"; exit 1
  elif [ -n "$nfile" ]; then
    [ -f "$nfile" ] || { warn "--notes-file '$nfile' does not exist"; exit 1; }
    notes=$(cat "$nfile") || { warn "could not read --notes-file '$nfile'"; exit 2; }
  fi
  [ -n "$(printf '%s' "$notes" | tr -d '[:space:]')" ] || { warn "fix-notes needs non-empty notes"; exit 1; }
  local kind
  kind=$(bd_json show "$fu" | jq -r 'if type == "array" and length > 0 then ((.[0].metadata.task_kind // "") | tostring) else "?" end' 2>/dev/null) \
    || { warn "could not read $fu; nothing recorded"; exit 2; }
  case "$kind" in
    rework) : ;;
    "?") warn "could not read $fu; nothing recorded"; exit 2 ;;
    *) warn "$fu is not a fix unit (task_kind '$kind'); nothing recorded"; exit 1 ;;
  esac
  gc bd update "$fu" --set-metadata "fix_notes=$notes" >/dev/null 2>&1 \
    || { warn "could not record the notes on $fu"; exit 2; }
}

# The open visits already on <anchor>'s feedback (feedback_visits), one per line:
#   <visit> TAB <how it sits there, e.g. "holds rework tk-r"> TAB <escalation_key or -> TAB <title>
# mol-validate prints this beside the batch it rules, so the validator sees the
# questions the operator already holds before it rules a human finding. It lists
# the anchor's own visits too, which set-disposition leaves to that judgment.
# Exit 0 when one or more is open, 1 when none is, 2 when the store would not read.
cmd_open_visits() {
  local anchor="" rows
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "open-visits needs --anchor"; exit 1; }
  rows=$(feedback_visits "$anchor") \
    || { warn "could not read the open visits on anchor $anchor's feedback"; return 2; }
  printf '%s' "$rows" | jq -e 'length > 0' >/dev/null 2>&1 || return 1
  printf '%s' "$rows" | visit_lines
}

cmd_wire_fix_unit() {
  local fu="" anchor="" findings=""
  while [ $# -gt 0 ]; do case "$1" in
    --fix-unit) fu="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --findings) findings="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$fu" ] && [ -n "$anchor" ] || { warn "wire-fix-unit needs --fix-unit and --anchor"; exit 1; }
  # Edge onto the anchor: the routed live blocker merge.sh reads. Idempotent —
  # signoff.sh may have wired it already.
  if ! edge_exists "$fu" "$anchor"; then
    gc bd dep "$fu" --blocks "$anchor" >/dev/null 2>&1 \
      || { warn "could not wire fix unit $fu --blocks anchor $anchor"; exit 2; }
  fi
  # An edge onto every finding it answers: the many-to-one relation, and the
  # close ordering — bd refuses to close a blocked issue, so no finding closes
  # before the work answering it does.
  local f rc=0
  local IFS=','
  for f in $findings; do
    [ -n "$f" ] || continue
    if ! edge_exists "$fu" "$f"; then
      gc bd dep "$fu" --blocks "$f" >/dev/null 2>&1 || { warn "could not wire fix unit $fu --blocks finding $f"; rc=2; }
    fi
  done
  return "$rc"
}

cmd_open_must_fix() {
  local anchor="" lane=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "open-must-fix needs --anchor"; exit 1; }
  local rows ids
  rows=$(bd_anchor_children "$anchor" "$LIVE_STATUSES") \
    || { warn "could not read findings on $anchor"; return 2; }
  ids=$(printf '%s' "$rows" | jq -r --arg lane "$lane" '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.disposition"] // "") | tostring) == "must-fix")
          | select($lane == "" or ((.metadata["finding.lane"] // "") | tostring) == $lane) ]
    | .[].id' 2>/dev/null)
  if [ -n "$ids" ]; then
    printf '%s\n' "$ids"
    return 0
  fi
  return 1
}

# The fix unit in flight answering an open must-fix or needs-you finding on
# <anchor>, the actor gate-ensure's quiescence holds on. An open must-fix finding
# is a demand on the anchor, not an actor on it: the fix unit answering it is what
# changes the diff. A needs-you finding waits on the operator's ruling, and the fix
# unit on its lane is the work that ruling releases, often parked on that very
# visit, so a review poured meanwhile would read a diff the ruling may yet change.
# A finding's blocks-blockers are its fix units (wire-fix-unit, set-disposition),
# so a live one is the fix in flight. A finding with NO blocker edge is matched by
# lane, through the same census close-answered disambiguates it with. A finding
# whose blockers have all closed has no fix in flight: its fix landed, and
# close-answered closes it. A finding no fix unit answers has none either.
# Exit 0 prints "<fix-unit> <status> <finding>" for the first pair found. Exit 1
# prints the open must-fix findings no fix unit is answering, one per line, and
# nothing when none is open; a needs-you finding is never listed, because it waits
# on a person and holds no merge. Exit 2 means the store would not read, including
# one finding's blockers, so a failed read never passes for "no fix unit".
cmd_fix_in_flight() {
  local anchor=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "fix-in-flight needs --anchor"; exit 1; }
  local rows ids id blk n_all hit flane rw unanswered=""
  rows=$(bd_anchor_children "$anchor" "$LIVE_STATUSES") \
    || { warn "could not read findings on $anchor"; return 2; }
  ids=$(printf '%s' "$rows" | jq -r '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.disposition"] // "") | tostring) as $d
                   | $d == "must-fix" or $d == "needs-you") ]
    | .[].id') \
    || { warn "could not filter must-fix and needs-you findings on $anchor"; return 2; }
  for id in $ids; do
    blk=$(bd_json dep list "$id" --direction=down -t blocks)
    printf '%s' "$blk" | jq -e 'type == "array"' >/dev/null 2>&1 \
      || { warn "could not read blockers of finding $id"; return 2; }
    n_all=$(printf '%s' "$blk" | jq -r 'length' 2>/dev/null)
    if [ "${n_all:-0}" -gt 0 ]; then
      hit=$(printf '%s' "$blk" | jq -r '
        [ .[] | ((.status // "open") | tostring | ascii_downcase) as $s
              | select($s != "closed") | "\(.id) \($s)" ] | .[0] // empty' 2>/dev/null)
    else
      flane=$(printf '%s' "$rows" | jq -r --arg id "$id" '.[] | select(.id == $id) | (.metadata["finding.lane"] // "") | tostring' 2>/dev/null)
      rw=$(_anchor_reworks "$anchor" "$flane") || { warn "could not read the fix units on $anchor"; return 2; }
      hit=$(printf '%s\n' "$rw" | awk 'NF && $2!="closed" {print $1" "$2; exit}')
    fi
    if [ -n "$hit" ]; then
      printf '%s %s\n' "$hit" "$id"
      return 0
    fi
    printf '%s' "$rows" | jq -e --arg id "$id" \
      'any(.[]; .id == $id and ((.metadata["finding.disposition"] // "") | tostring) == "must-fix")' >/dev/null 2>&1 \
      && unanswered="$unanswered$id
"
  done
  printf '%s' "$unanswered"
  return 1
}

cmd_close_unvalidated() {
  local anchor="" lanes="" reason=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lane)   lanes="${lanes:+$lanes,}${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lanes)  lanes="${lanes:+$lanes,}${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] && [ -n "$lanes" ] || { warn "close-unvalidated needs --anchor and --lane/--lanes"; exit 1; }
  # A lane found clean answers its own still-unruled findings: close the
  # unvalidated ones the lane raised. A validated finding (must-fix, deferred,
  # declined) belongs to the validator and is left alone; a finding a fix unit
  # still blocks refuses to close and is left for that unit's landing. Lanes are
  # passed and resolved together: gate-ensure hands every green lane of the
  # anchor at once, so a settled board reads the finding set once per pass, not
  # once per green lane.
  local rows pairs id flane note
  rows=$(bd_anchor_children "$anchor" "$LIVE_STATUSES") || { warn "could not read findings on $anchor"; return 2; }
  # A failed filter is NOT a clean lane. The jq exit status rides pipefail (set
  # above), so a parse error or a non-string disposition returns 2 here rather
  # than the empty list the early return below would read as nothing to resolve.
  # Each row carries its own lane into the note so a batched call keyed on many
  # lanes still records which lane cleared each finding.
  pairs=$(printf '%s' "$rows" | jq -r --arg lanes "$lanes" '
    ($lanes | split(",") | map(select(. != ""))) as $ls
    | .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.disposition"] // "") | tostring) == "unvalidated")
          | ((.metadata["finding.lane"] // "") | tostring) as $l
          | select($ls | index($l))
          | "\(.id) \($l)"') \
    || { warn "could not filter unvalidated findings on $anchor (lanes: $lanes)"; return 2; }
  # Nothing to resolve: return before the cache invalidation below, exactly as
  # close-answered does. gate-ensure runs this every pass for each green anchor,
  # so a clean board is the common case; clearing the per-pass cache when no
  # finding closed would reopen the read window the cache exists to collapse.
  [ -n "$pairs" ] || return 0
  printf '%s\n' "$pairs" | while IFS=' ' read -r id flane; do
    [ -n "$id" ] || continue
    note="resolved: lane $flane found clean"
    [ -n "$reason" ] && note="$note — $reason"
    gc bd update "$id" --status=closed --append-notes "$note" >/dev/null 2>&1 || true
  done
  # Closed findings leave the LIVE set; drop the per-pass bd_list cache so a
  # same-pass re-read does not still see them. No-op outside a reconcile pass.
  bd_cache_clear
}

# An anchor that leaves the open set — merged, disposed, closed by hand — can no
# longer be revisited by gate-ensure (which reads open anchors only), so a lane's
# still-unvalidated findings would sit open forever. They are moot the moment the
# anchor closes: no validator will ever run on closed work. This sheds them, the
# close-transition counterpart to the green-lane moot close above. A needs-you
# finding is shed the same way: an anchor that merged on an approval, or was
# disposed, while the finding waited on its visit leaves nothing for its review to
# hold, and close-answered, which reads open anchors only, never reaches it. Its
# visit is the operator's conversation and is left standing. It keys on the
# anchor being gone, NOT on any approve signal, so it rebuilds no re-approval
# proxy: a human GitHub approval does not close a finding here either — the anchor
# leaving the open set does.
cmd_shed_orphaned() {
  local reason=""
  while [ $# -gt 0 ]; do case "$1" in
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  local rows pairs anchor fid note astatus disp seen=""
  for disp in unvalidated needs-you; do
    # Live findings of this disposition across every anchor — --status scopes out
    # closed ones, so a finding already shed is not re-read. The set is small in
    # steady state: a finding is transient, ruled or moot-closed.
    rows=$(bd_list --metadata-field "finding.disposition=$disp" --status="$LIVE_STATUSES") || { warn "could not read $disp findings"; return 2; }
    pairs=$(printf '%s' "$rows" | jq -r '
      .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | ((.metadata.anchor_bead // "") | tostring) as $a
          | select($a != "")
          | "\(.id) \($a)"') \
      || { warn "could not filter $disp findings"; return 2; }
    [ -n "$pairs" ] || continue
    seen=1
    printf '%s\n' "$pairs" | while IFS=' ' read -r fid anchor; do
      [ -n "$fid" ] && [ -n "$anchor" ] || continue
      # Shed only when the anchor is gone. An unreadable anchor row is left for the
      # next pass rather than closing the finding on an absence (fail closed).
      astatus=$(bd_json show "$anchor" | jq -r '(.[0].status // "") | tostring | ascii_downcase' 2>/dev/null) || continue
      [ "$astatus" = closed ] || continue
      if [ "$disp" = needs-you ]; then
        note="resolved: anchor $anchor closed while this finding waited on its visit — moot (the diff it objected to no longer awaits a merge)"
      else
        note="resolved: anchor $anchor closed before this finding was validated — moot (no validator runs on closed work)"
      fi
      [ -n "$reason" ] && note="$note ($reason)"
      gc bd update "$fid" --status=closed --append-notes "$note" >/dev/null 2>&1 || true
    done
  done
  [ -n "$seen" ] || return 0
  bd_cache_clear
}

# The visit whose recorded ruling answers the question <visit> carried, printed,
# or nothing (exit 1) while no ruling answers it. Only the operator's ruling
# answers a needs-you finding's question, and converse-signoff.sh records it on
# the visit as gc.ruling when a sitting signs off --ruled yes. A visit also closes
# without one: moot, benign, dismissed by the operator, or a sitting cut short,
# and none of those answers the question. A fold hands the question on to the
# visit that now holds it: visit-close.sh records that holder on the folded visit
# as gc.folded_into, and bead-rehome.sh records a re-homed visit's successor as
# gc.superseded_by. The question is followed through each hand-off to the visit
# holding it now, which answers only once it has closed carrying a ruling of its
# own. An open visit, a close with no ruling and no successor, a successor that is
# not a visit, a row that will not read, and a hand-off back to a visit already
# passed all answer nothing, so the finding keeps holding its review.
ruled_visit() { # <visit-id>
  local v="$1" seen=" " row
  while [ -n "$v" ]; do
    case "$seen" in *" $v "*) return 1 ;; esac
    seen="$seen$v "
    row=$(bd_json show "$v")
    printf '%s' "$row" | jq -e --arg v "$v" '
      type == "array" and ((.[0].id // "") == $v)
      and (((.[0].metadata.task_kind // "") | tostring) == "visit")
      and (((.[0].status // "") | tostring | ascii_downcase) == "closed")' >/dev/null 2>&1 || return 1
    if printf '%s' "$row" | jq -e '((.[0].metadata["gc.ruling"] // "") | tostring | test("[^[:space:]]"))' >/dev/null 2>&1; then
      printf '%s\n' "$v"
      return 0
    fi
    v=$(printf '%s' "$row" | jq -r '.[0].metadata as $m
      | [ ($m["gc.folded_into"] // ""), ($m["gc.superseded_by"] // "") ]
      | map(tostring | select(. != "")) | .[0] // empty' 2>/dev/null)
  done
  return 1
}

# A must-fix finding is closed once every fix unit answering it has landed. The
# fix unit blocks the finding (wire-fix-unit), and bd refuses to close a blocked
# issue, so the finding is closeable exactly when all its blockers have closed —
# which is the fix unit's landing (merge-push closes the rework once its commit
# is on the branch). Nothing else performs that close, so the finding otherwise
# stays open and holds the publish (pr-open.sh) and the merge (merge.sh) with its
# fix already on the branch, wedging a landed fix at pre_open_gate. gate-ensure
# runs this per anchor, and its quiescence reads the same blockers through
# fix-in-flight: the reader that holds review dispatch while a fix unit is in
# flight is the one that releases the finding once that unit lands, so the two
# cannot disagree. A finding still blocked by a live fix unit is left for that
# unit's landing. A finding with NO blocker edge is the ambiguous case: usually
# an objection no fix unit answers yet (left open), but also the shape a missed
# close-ordering edge leaves behind when a fix landed — so it is closed only when
# the lane's fix unit census shows one landed and none still live, the same fact
# the edge would have carried.
#
# A needs-you finding is closed once the operator has ruled the visit holding its
# question (ruled_visit: its finding.visit, followed through every fold) and no
# fix unit answers it any more: nothing blocks it, none on its lane is live, and
# no ruling's rework child is live on the anchor. A ruling's child
# (converse-rework.sh, source_ruling_bead) answers no lane, but it is the work an
# operator's ruling calls for, and a ruling rules the whole diff, so a needs-you
# finding on any lane waits for it. The operator has then ruled, and the work
# their ruling calls for is on the branch, or the ruling called for none. The
# close records the ruled visit as finding.ruling_visit, which pr-facts.sh's
# review dismissal names. Until then the finding holds its review
# changes-requested, and a visit that closed without a ruling (moot, benign,
# dismissed, cut short) never releases it; the operator's own approval is then
# what replaces the review. A sitting cut short moves its wait to the subject,
# and the later sitting that rules on it closes a visit of its own, which this
# does not follow. Review dispatch is held meanwhile too: by fix-in-flight while
# a fix unit on its lane is live, and by gate-ensure's open_rework_child while a
# ruling's child is. A visit, blocker list, census or rework read that will not
# answer leaves it open.
cmd_close_answered() {
  local anchor="" reason=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "close-answered needs --anchor"; exit 1; }
  local rows ids nyids id note cnote blk n_all n_live flane census c_live c_landed nyvisit ruled
  rows=$(bd_anchor_children "$anchor" "$LIVE_STATUSES") || { warn "could not read findings on $anchor"; return 2; }
  ids=$(printf '%s' "$rows" | jq -r '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.disposition"] // "") | tostring) == "must-fix") ]
    | .[].id') \
    || { warn "could not filter must-fix findings on $anchor"; return 2; }
  nyids=$(printf '%s' "$rows" | jq -r '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.disposition"] // "") | tostring) == "needs-you") ]
    | .[].id') \
    || { warn "could not filter needs-you findings on $anchor"; return 2; }
  [ -n "$ids$nyids" ] || return 0
  note="resolved: fix unit landed — every blocker closed, so the objection's fix is on the branch"
  [ -n "$reason" ] && note="$note ($reason)"
  for id in $ids; do
    # The finding's blocks-blockers are its fix units. Read them with status so a
    # still-live one leaves the finding open rather than being attempted and
    # warned every pass.
    blk=$(bd_json dep list "$id" --direction=down -t blocks)
    printf '%s' "$blk" | jq -e 'type == "array"' >/dev/null 2>&1 \
      || { warn "could not read blockers of finding $id; leaving it open"; continue; }
    n_all=$(printf '%s' "$blk" | jq -r 'length' 2>/dev/null)
    n_live=$(printf '%s' "$blk" | jq -r '[ .[] | select(((.status // "open") | tostring | ascii_downcase) != "closed") ] | length' 2>/dev/null)
    cnote="$note"
    if [ "${n_all:-0}" -gt 0 ]; then
      # Edges present: close exactly when every fix unit answering it has landed.
      [ "${n_live:-1}" -eq 0 ] || continue
    else
      # No blocker edge at all. This is the shape a missed close-ordering edge
      # leaves (anchor_fix_unit was open-only, so a fix unit that closed before the
      # ruling was never wired), and also the shape of a live objection no fix unit
      # has answered yet. The lane's fix-unit census tells them apart: close only
      # when one has LANDED and none is still live. A live fix unit (fix in flight)
      # or no fix unit (unanswered objection) leaves the finding holding. An
      # unreadable census leaves it open.
      flane=$(printf '%s' "$rows" | jq -r --arg id "$id" '.[] | select(.id == $id) | (.metadata["finding.lane"] // "") | tostring' 2>/dev/null)
      census=$(anchor_fix_unit_census "$anchor" "$flane") || continue
      c_live="${census%% *}"; c_landed="${census##* }"
      { [ "${c_live:-0}" -eq 0 ] && [ "${c_landed:-0}" -gt 0 ]; } || continue
      cnote="resolved: fix unit landed (no close-ordering edge; matched by lane $flane) — the objection's fix is on the branch"
      [ -n "$reason" ] && cnote="$cnote ($reason)"
    fi
    gc bd update "$id" --status=closed --append-notes "$cnote" >/dev/null 2>&1 \
      || warn "could not close answered finding $id"
  done
  for id in $nyids; do
    nyvisit=$(printf '%s' "$rows" | jq -r --arg id "$id" '.[] | select(.id == $id) | (.metadata["finding.visit"] // "") | tostring' 2>/dev/null)
    [ -n "$nyvisit" ] || continue
    ruled=$(ruled_visit "$nyvisit") || continue
    blk=$(bd_json dep list "$id" --direction=down -t blocks)
    printf '%s' "$blk" | jq -e 'type == "array"' >/dev/null 2>&1 \
      || { warn "could not read blockers of finding $id; leaving it open"; continue; }
    n_live=$(printf '%s' "$blk" | jq -r '[ .[] | select(((.status // "open") | tostring | ascii_downcase) != "closed") ] | length' 2>/dev/null)
    [ "${n_live:-1}" -eq 0 ] || continue
    flane=$(printf '%s' "$rows" | jq -r --arg id "$id" '.[] | select(.id == $id) | (.metadata["finding.lane"] // "") | tostring' 2>/dev/null)
    census=$(anchor_fix_unit_census "$anchor" "$flane") || continue
    c_live="${census%% *}"
    [ "${c_live:-1}" -eq 0 ] || continue
    printf '%s' "$rows" | jq -e 'all(.[]; ((.metadata.task_kind // "") | tostring) != "rework"
                                         or ((.metadata.source_ruling_bead // "") | tostring) == "")' >/dev/null 2>&1 \
      || continue
    if [ "$ruled" = "$nyvisit" ]; then
      cnote="resolved: the operator ruled its visit $nyvisit, and no fix unit on lane $flane, nor a ruling's rework child, is still in flight"
    else
      cnote="resolved: its question moved from visit $nyvisit to visit $ruled, the operator ruled that visit, and no fix unit on lane $flane, nor a ruling's rework child, is still in flight"
    fi
    [ -n "$reason" ] && cnote="$cnote ($reason)"
    gc bd update "$id" --status=closed --set-metadata "finding.ruling_visit=$ruled" --append-notes "$cnote" >/dev/null 2>&1 \
      || warn "could not close needs-you finding $id after the operator ruled visit $ruled"
  done
  # Closed findings leave the LIVE set; drop the per-pass bd_list cache so the
  # same-pass re-read (gate-ensure recomputes quiescence right after) does not
  # still see them. No-op outside a reconcile pass.
  bd_cache_clear
}

[ $# -ge 1 ] || { usage; exit 1; }
VERB="$1"; shift
case "$VERB" in
  key)               cmd_key "$@" ;;
  upsert)            cmd_upsert "$@" ;;
  set-disposition)   cmd_set_disposition "$@" ;;
  answer)            cmd_answer "$@" ;;
  fix-notes)         cmd_fix_notes "$@" ;;
  open-visits)       cmd_open_visits "$@" ;;
  wire-fix-unit)     cmd_wire_fix_unit "$@" ;;
  open-must-fix)     cmd_open_must_fix "$@" ;;
  fix-in-flight)     cmd_fix_in_flight "$@" ;;
  close-unvalidated) cmd_close_unvalidated "$@" ;;
  shed-orphaned)     cmd_shed_orphaned "$@" ;;
  close-answered)    cmd_close_answered "$@" ;;
  *) warn "unknown verb '$VERB'"; usage; exit 1 ;;
esac
