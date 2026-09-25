#!/usr/bin/env bash
# visit-identity.sh — the single definition of what subject a visit covers.
#
# Sourced (never executed) by every script that must agree on visit coverage:
# gc-helm.sh (open, dismiss, engage), converse-fold.sh and converse-claim.sh
# (sitting membership), and the sweeps (gate-visit-sweep.sh, liveness-sweep.sh,
# liveness-sweep-precheck.sh). One definition, no copies.
#
# Coverage is a visit's DIRECT graph-native identity to its subject: the outgoing
# `tracks` edge, with the `gc.continuation_group` stamp as the recovery fallback
# the gate-visit block writes beside it (formulas/mol-visit.toml). It is bounded
# to that one edge — a visit covers the bead it tracks, never that bead's blocker
# tree or descendants.
#
# The tracks edge renders under two key spellings by read verb: `gc bd show`
# gives {dependency_type, id}; `gc bd list` gives {type, depends_on_id}. The defs
# accept both, so one predicate serves every caller regardless of its source.
#
# stall_root is not part of this identity: no script writes it, and the ruling
# (tk-fhlqce, converse tk-s9hkev) keeps it advisory. The sweeps read it for a
# separate liveness question (workflow-root membership), never for coverage.
#
# Usage follows the in-variable jq convention (bead-context.sh $ADV): prepend the
# defs to a jq program that runs against one visit bead object, e.g.
#   jq -r "$VISIT_IDENTITY_JQ"' select(visit_covers($s)) | .id '
VISIT_IDENTITY_JQ='
  # The subject ids this visit tracks via its outgoing tracks edge(s).
  def visit_tracked_subjects:
    [ (.dependencies // [])[]
      | select(((.dependency_type // .type) // "") == "tracks")
      | ((.id // .depends_on_id) // "") ]
    | map(select(. != ""));
  # The gc.continuation_group stamp: the recovery fallback for an empty edge.
  def visit_group_subject:
    (.metadata["gc.continuation_group"] // "");
  # The one subject this visit covers: its tracks target, else its stamp.
  def visit_subject:
    (visit_tracked_subjects | .[0] // "") as $t
    | if $t != "" then $t else visit_group_subject end;
  # Every subject id this visit resolves to (edge targets plus the stamp), for
  # callers that build a set of covered subjects across many visits.
  def visit_identity_subjects:
    (visit_tracked_subjects + [visit_group_subject]) | map(select(. != "")) | unique;
  # Which identity covers $subject: "tracks", "continuation_group", or "".
  def visit_identity_match($subject):
    if $subject == "" then ""
    elif (visit_tracked_subjects | any(. == $subject)) then "tracks"
    elif visit_group_subject == $subject then "continuation_group"
    else "" end;
  # Does this visit cover $subject by its direct identity edge or stamp?
  def visit_covers($subject): visit_identity_match($subject) != "";
'
