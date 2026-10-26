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
# (visit-identity.sh): the classifier builds on visit_identity_subjects
# (visit-identity.sh), standing_kinds (standing-kinds.sh) and
# awaiting_placement (placement.sh, which asks has_dispatch_path from
# dispatch-path.sh), so prepend those defs, then these, and call
# liveness_classify:
#   jq -n --slurpfile ready R --slurpfile live L --slurpfile alive A ... \
#     "$VISIT_IDENTITY_JQ$STANDING_KINDS_JQ$DISPATCH_PATH_JQ$PLACEMENT_JQ$LIVENESS_CLASSIFY_JQ"'liveness_classify'
# It emits one {id, title, type, class} row per ready bead.
#
# Every input below is required, and jq refuses the program when one is
# missing:
#   $ready $live $alive       slurped `bd ready --unassigned`, the
#                             open+in_progress listing, and every not-closed
#                             bead (that listing plus every other non-closed
#                             status)
#   $livesessions             every name a live session carries
#   $livenessknown            false when the session list was unreadable
#   $unreadable_liveness_covers
#                             whether a CLAIMED visit still covers its subject
#                             when the session list was unreadable. The sweep
#                             passes true, since an unprovable death is not a
#                             death; the precheck passes false and fails closed.
#   $openprs $worked $husks $preopen_green
#                             the reads beyond the bead set: open PR urls,
#                             convoy-worked bead ids, husk step ids, and the
#                             pre_open_gate anchors whose every pre-open gate
#                             derives green, as an {anchor-id: true} map the
#                             sweep builds through lane-state.sh, in which an
#                             anchor whose head the sweep could not read is
#                             "unread" instead. Each arm that reads one drops
#                             only the beads its input names, so an empty
#                             input drops nothing. That is what lets the
#                             precheck pass them empty and keep a survivor set
#                             that contains the sweep's candidates.
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
# an arm: a `blocks` blocker (what `takeaway --waiting-on` and `demand` write)
# takes the bead out of the ready set upstream of here, children reach the
# `gatedparents` arm, `tracks` targets reach the arm below it. `triage.hold`
# still mutes on presence alone: no agent writes one any more, and the ones on
# the board name their wait in prose with no edge to discharge.
#
# $demanded is the one non-edge read of the bead set, and it exists for one
# case: gc-helm.sh warns on stderr when a demand's `blocks` edge does not land,
# and nothing repairs it, so that bead reads ready while a person owes an
# answer on it.
#
# A bead that waits for placement (placement.sh) is a named wait too: intake
# held it as new work for the operator's placement sitting, and
# `gc-helm.sh unplaced` lists it there, so the sweep's triage visit would ask
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
  # A visit holder is live, or it has none. A claim writes one of assignee /
  # gc.session_id / gc.session_name; $livesessions holds every name a listed
  # (live) session carries. No holder is an UNCLAIMED visit, a pending
  # escalation that still covers. $livenessknown false is an unreadable session
  # list, where $unreadable_liveness_covers decides.
  def holder_live:
    ([ (.assignee // ""), (.metadata["gc.session_id"] // ""), (.metadata["gc.session_name"] // "") ]
     | map(select(. != ""))) as $holders
    | if ($holders | length) == 0 then true
      elif ($livenessknown | not) then $unreadable_liveness_covers
      else any($holders[]; . as $h | ($livesessions | index($h)) != null)
      end;
  # Live-visit subjects: every subject a live visit covers by its shared identity
  # (tracks edge, gc.continuation_group fallback — the stamp alone has landed
  # empty on a live visit). visit_identity_subjects is visit-identity.sh.
  # A ready bead converses when it is one of them, or when its gc.root_bead_id
  # is: a sitting about a workflow root covers the steps of that workflow.
  def liveness_classify:
    ([ ($live[0] // [])[]
       | select((.metadata.task_kind // "") == "visit")
       | select(holder_live)
       | visit_identity_subjects[] ]) as $convgroups
    | ([ ($openprs // [])[] | pr_key ] | map(select(. != ""))) as $openkeys
    | ([ ($alive[0] // [])[]
       | (.metadata["gc.demand_for"] // "") | select(. != "") ] | unique) as $demanded
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
           elif ((.metadata.task_kind // "") == "visit") and holder_live then "conversing"
           elif ((.metadata.task_kind // "") as $k | (standing_kinds | index($k)) != null) then "held-by-design"
           elif (($demanded | index($b.id)) != null) then "held-by-design"
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
