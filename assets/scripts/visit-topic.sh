#!/usr/bin/env bash
# visit-topic.sh — the single definition of a visit's topic: what makes two
# visits the same sitting, and what a sitting files its demands under.
# Sourced, never executed.
#
# A visit's topic is one of these kinds, decided in this order:
#   key      the visit carries an escalation_key. escalate.sh files one visit
#            per situation, often under a shared subject, and the key is the
#            only stamp that tells two situations on one subject apart.
#   own      the visit carries visit_topic=own, which gc-helm.sh open
#            --allow-duplicate writes on a visit filed for a distinct concern.
#            Its topic is the visit itself, which no other visit shares.
#   subject  neither: an ordinary visit, whose subject names its situation.
# An escalation_key wins when a visit carries both stamps. An empty
# escalation_key is no key, and a visit_topic other than `own` is no topic of
# its own.
#
# Each consumer compares the topic with something different, so each encoding
# is a def of its own:
#   visit_fold_topic($subject)  what converse-fold.sh compares between a visit
#       and every live sitting on its subject: `key:<escalation_key>`,
#       `visit:<visit-id>`, or the subject. The prefixes keep a key, a visit's
#       own topic and a bead id from ever comparing equal.
#   visit_demand_topic  the gc.demand_topic of every demand a sitting files
#       (converse-hold.sh), and the topic its discharge looks its demands up
#       under (converse-signoff.sh): the escalation_key itself,
#       `visit:<visit-id>`, or empty. An empty topic files none, and a lookup
#       with no topic matches every demand on the gated bead. The key stays
#       bare because the open demands filed under a key carry it bare, and a
#       lookup matches a topic exactly.
#
# A topic is not coverage. What subject a visit covers is visit-identity.sh's
# rule, and no reader of coverage reads the topic.
#
# visit-topic.test.sh runs every def over visit-topic.fixture.json. It fails
# when a consumer stops sourcing this file, or when another file reads the
# visit_topic stamp itself. Each consumer's own suite runs that consumer over
# the same fixture.
#
# Usage follows the in-variable jq convention (visit-identity.sh): prepend the
# defs to a jq program that runs against one visit bead object, e.g.
#   jq -r "$VISIT_TOPIC_JQ"'.[0] | visit_demand_topic'

# shellcheck disable=SC2034  # read by the scripts that source this file
VISIT_TOPIC_JQ='
  # The kind of topic this visit carries: "key", "own" or "subject".
  def visit_topic_kind:
    if (.metadata.escalation_key // "") != "" then "key"
    elif (.metadata.visit_topic // "") == "own" then "own"
    else "subject" end;
  # The fold encoding, compared between a visit and every live sitting on its
  # subject.
  def visit_fold_topic($subject):
    visit_topic_kind as $kind
    | if $kind == "key" then "key:" + .metadata.escalation_key
      elif $kind == "own" then "visit:" + (.id // "")
      else $subject end;
  # The demand encoding, the topic a sitting files and discharges its demands
  # under.
  def visit_demand_topic:
    visit_topic_kind as $kind
    | if $kind == "key" then .metadata.escalation_key
      elif $kind == "own" then "visit:" + (.id // "")
      else "" end;
'
