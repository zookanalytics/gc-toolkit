#!/usr/bin/env bash
# liveness-classify.sh — the one liveness classifier. It puts every bead in a
# rig's ready set into a named class, and a bead no class claims is an UNNAMED
# WAIT. liveness-sweep.sh reports the unnamed waits; its condition check,
# liveness-sweep-precheck.sh, runs the same classifier to prove there are none
# new before a pass runs. One definition, no copies: an exclusion added here
# applies to both, and liveness-classify.test.sh fails when either stops
# sourcing this file or a file carries a classifier def of its own.
#
# Sourced (never executed). Usage follows the in-variable jq convention
# (standing-kinds.sh): the classifier builds on open_human_gates and
# blocked_by_any (bd-lib.sh's $HUMAN_GATE_JQ), conversation (conversation.sh),
# standing_kinds (standing-kinds.sh) and awaiting_placement (placement.sh,
# which asks has_dispatch_path from dispatch-path.sh), so prepend those defs,
# then these, and call liveness_classify:
#   jq -n --slurpfile ready R --slurpfile live L --slurpfile alive A ... \
#     "$HUMAN_GATE_JQ$CONVERSATION_JQ$STANDING_KINDS_JQ$DISPATCH_PATH_JQ$PLACEMENT_JQ$LIVENESS_CLASSIFY_JQ"'liveness_classify'
# It emits one {id, title, type, class} row per ready bead.
#
# Every input below is required, and jq refuses the program when one is
# missing:
#   $ready $live $alive       slurped `bd ready --unassigned`, the
#                             open+in_progress listing, and every not-closed
#                             bead (that listing plus every other non-closed
#                             status), the two listings with gates included
#   $livesessions             every name a live session carries
#   $livenessknown            false when the session list was unreadable
#   $unreadable_liveness_covers
#                             whether a conversation a sitting holds still
#                             covers its subject when the session list was
#                             unreadable. The sweep passes true, since an
#                             unprovable death is not a death; the precheck
#                             passes false and fails closed. A conversation in
#                             the operator's queue covers either way.
#   $openprs $worked $husks $preopen_green
#                             the reads beyond the bead set: open PR urls,
#                             the ids of the beads live runs work, husk step
#                             ids, and the pre_open_gate anchors whose every
#                             pre-open gate derives green, as an {anchor-id:
#                             true} map the sweep builds through
#                             lane-state.sh, in which an anchor whose head the
#                             sweep could not read is "unread" instead. Each
#                             arm that reads one drops only the beads its
#                             input names, so an empty input drops nothing.
#                             That is what lets the precheck pass them empty
#                             and keep a survivor set that contains the
#                             sweep's candidates.
#
# Every drop is a NAMED class. Structural edges fold in from $alive: a parent
# is gated iff a not-closed child names it (the child holds the edge), and an
# outgoing tracks edge to a not-closed bead is a named wait. Every `// ""` is
# load-bearing: most beads carry no metadata key at all, and an empty hold is a
# CLEARED hold, not a hold.
#
# `gc.takeaway` is not read here. It is one field a sitting stamps when it
# begins and REPLACES with its outcome when it signs off, and nothing clears
# it, so its presence dates the last sitting rather than naming a live wait —
# read as a hold, one conversation exempts a bead from the census forever. The
# waits a sitting records are edges instead, and every edge shape already has
# an arm: a `blocks` blocker (what `takeaway --waiting-on` and a human gate
# write) takes the bead out of the ready set upstream of here, children reach
# the `gatedparents` arm, `tracks` targets reach the arm below it. A
# conversation task names its wait through that `tracks` arm while what it
# tracks is open. `triage.hold` still mutes on presence alone: no agent writes
# one any more, and the ones on the board name their wait in prose with no edge
# to discharge.
#
# A bead that an open human gate blocks is held by design. bd ready leaves such
# a bead out, so the arm names one only when the ready read was cut before the
# gate was filed: the not-closed listing, read after it, carries the bead's
# blocks edge onto the gate.
#
# A bead that waits for placement (placement.sh) is a named wait too: intake
# held it as new work for the operator's placement sitting, and
# `gc-helm.sh unplaced` lists it there, so the sweep's triage gate would ask
# the operator the same question a second time. The predicate reads the marker
# and every shape that places a bead, so a marker left on a bead the sitting
# already placed names no wait.
# shellcheck disable=SC2034  # read by the scripts that source this file
LIVENESS_CLASSIFY_JQ='
  def pr_key:
    [ ((. // "") | tostring | ascii_downcase)
      | capture("://(?<h>[^/]+)/(?<o>[^/]+/[^/]+)/pull/(?<n>[0-9]+)") ]
    | .[0] | if . == null then "" else (.h + "/" + .o + "/pull/" + .n) end;
  # A workflow root that has expanded into steps, a scope latch and a step-spec
  # sidecar are the structure of a run, not its work, so a route on such a root
  # names the run and is not an offer. Gas City checks for them in
  # workflowTopologyIsNonExecutable (cmd/gc/cmd_hook_claim.go), which the route
  # match in the hook (hookClaimMatchesRoute) and the demand count in the
  # controller (controllerDemandRouteCandidates, cmd/gc/build_desired_state.go)
  # both apply. It tells an expanded root by gc.workflow_expanded="true", which
  # the pour stamps on every root it expands into steps. This predicate reads
  # gc.kind alone, so it also takes in a workflow root without the stamp, which
  # Gas City offers and counts as work: the root of a root-only run is the work
  # itself. The list mirrors beadmeta.WorkflowTopologyKinds, which no command
  # reads out; a kind added there and not here falls through to the route arm.
  def topology_kind:
    (.metadata["gc.kind"] // "") as $k
    | ["workflow", "scope", "spec"] | index($k) != null;
  def machine_convoy:
    (.issue_type // "") == "convoy"
    and ((((.title // "") | startswith("sling-"))
          or ((.title // "") | startswith("input convoy for"))
          or (((.metadata["gc.synthetic"] // "") | tostring) == "true")));
  # The tracking bead of an order is a wisp: issue_type task, no metadata
  # until it closes, and no edges, so its id and its title are the only
  # durable structural signals it carries. Both are machine-minted and
  # immutable, which keeps the exclusion locally decidable and monotone.
  # Requiring BOTH is what keeps a human bead titled "order: ..." visible,
  # and a wisp of some other kind too.
  def order_wisp:
    ((.id // "") | contains("-wisp-"))
    and ((.title // "") | startswith("order:"));
  # A pre_open_gate anchor whose every pre-open gate derives green waits only
  # on pr-open.sh. The sweep derives it; an anchor it could not prove green is
  # absent from the map.
  def pre_open_all_green:
    ($preopen_green[(.id // "")] // false) == true;
  # A pre_open_gate anchor whose head the sweep could not read this pass, so
  # whether it waits only on pr-open.sh is unknown, and the sweep holds it.
  def pre_open_unread:
    ($preopen_green[(.id // "")] // false) == "unread";
  # A conversation that covers its subject. One in the queue of the operator
  # (`human`) covers it: a person is already asked, as human_side_on below and
  # the board read it. One a sitting holds covers it while that sitting
  # lives: its assignee is the alias of the sitting and a listed (live) session
  # carries that alias, bare or qualified; $livesessions holds every name a
  # listed session carries. $livenessknown false is an unreadable session list,
  # where $unreadable_liveness_covers decides for a held one.
  def conversation_covers:
    ((.assignee // "") | tostring) as $a
    | if $a == "human" then true
      elif $a == "" then false
      elif ($livenessknown | not) then $unreadable_liveness_covers
      else any(($a, (.id // ""), "c-" + (.id // "")); . as $n | ($livesessions | index($n)) != null)
      end;
  # Conversing subjects: the bead each covering conversation tracks. A ready
  # bead converses when it is one of them, or when its gc.root_bead_id is: a
  # sitting about a workflow root covers the steps of that workflow.
  def liveness_classify:
    ([ ($live[0] // [])[] | select(conversation) | select(conversation_covers)
       | conversation_subjects[] ]) as $convgroups
    | ([ ($openprs // [])[] | pr_key ] | map(select(. != ""))) as $openkeys
    | (($alive[0] // []) | open_human_gates) as $humangates
    | ([ ($alive[0] // [])[] | select(blocked_by_any($humangates)) | .id ] | unique) as $gateheld
    | (($alive[0] // []) | map({key: .id, value: true}) | from_entries) as $aliveset
    | ([ ($alive[0] // [])[] | .dependencies[]?
         | select((.type // "") == "parent-child") | (.depends_on_id // empty) ] | unique) as $gatedparents
    | [ ($ready[0] // [])[]
        | . as $b
        | (if machine_convoy or order_wisp then "machine"
           elif ($husks | index($b.id)) != null then "husk"
           elif topology_kind then "topology"
           elif ((.metadata["gc.routed_to"] // "") != "") then "routed-and-claimable"
           elif (($worked | index($b.id)) != null) then "worked"
           elif ((.metadata.task_kind // "") as $k | (standing_kinds | index($k)) != null) then "held-by-design"
           elif (($gateheld | index($b.id)) != null) then "held-by-design"
           elif ((.metadata["triage.hold"] // "") != "") then "held-by-design"
           elif awaiting_placement then "awaiting-placement"
           elif ((.metadata["gc.root_bead_id"] // "") as $r | $r != "" and (($convgroups | index($r)) != null)) then "conversing"
           elif (($convgroups | index($b.id)) != null) then "conversing"
           elif (((.metadata.merge_result // "") == "pull_request")
                 and (((.metadata.pr_url // "") | pr_key) as $k | $k != "" and ($openkeys | index($k)) != null))
                then "gated"
           elif (((.metadata.merge_result // "") == "pre_open_gate") and pre_open_all_green) then "gated"
           elif (((.metadata.merge_result // "") == "pre_open_gate") and pre_open_unread) then "unread"
           elif (($gatedparents | index($b.id)) != null) then "gated"
           elif ([ .dependencies[]? | select((.type // "") == "tracks")
                   | select(($aliveset[(.depends_on_id // "")] // false)) ] | length > 0) then "gated"
           else "unnamed" end) as $class
        | {id, title: (.title // ""), type: (.issue_type // ""), class: $class}
      ];
'

# The human side already on a subject: an open human gate that blocks it, or a
# conversation about it, read off one listing that includes gates. It names
# which ("an open human gate", "a conversation"), or prints "" for neither.
# liveness-sweep.sh asks it before it files a batch gate or a recurrence on a
# standing subject, and its precheck asks it the same way, so the two cannot
# disagree about whether a person is already on the subject. Both pass the
# listing of every bead not closed ($alive), since a human gate holds in every
# status but closed. A conversation counts only at open or in_progress, the
# statuses of the listing the classifier reads conversations from ($live), so
# the guard and the classifier agree on which conversations stand. It reads no
# input variable, so it runs apart from the classifier: prepend $HUMAN_GATE_JQ
# (bd-lib.sh) and $CONVERSATION_JQ (conversation.sh), then
#   jq -r --arg s <subject> "$HUMAN_GATE_JQ$CONVERSATION_JQ$LIVENESS_WAIT_JQ"'human_side_on($s)' <listing>
# shellcheck disable=SC2034  # read by the scripts that source this file
LIVENESS_WAIT_JQ='
  def human_side_on($s):
    open_human_gates as $g
    | if any(.[]; .id == $s and blocked_by_any($g)) then "an open human gate"
      elif any(.[]; ((.status // "open") as $st | $st == "open" or $st == "in_progress")
                    and conversation and ((conversation_subjects | index($s)) != null)) then "a conversation"
      else "" end;
'
