#!/usr/bin/env bash
# dispatch-path.sh — the single definition of a dispatch path: the metadata that
# says how a bead will be dispatched, so whoever set it has already decided that
# dispatch. Two keys each give a bead one. gc.routed_to names a pool queue,
# which serves the bead once bd reports it ready. gc.dispatch_when_ready is an
# arm (deferred-dispatch.sh arm), which the deferred-dispatch order slings once
# the bead's own blockers close. gc.execution_routed_to is not one: it is
# execution provenance a formula pour leaves, and no queue reads it.
#
# Sourced (never executed) by the readers that ask whether a bead already has a
# dispatch path: the proactive scan (tools/gc-proactive.sh), which reacts only
# to input that has none, and the doctor checks check-blocked-work-armed, which
# flags blocked work that has none, and check-step-terminal, which counts a step
# as offerable only when it has one. One definition, no copies: a key added here
# is read by every one of them at once, and dispatch-path.test.sh fails when a
# reader stops sourcing this file or tests the keys itself.
#
# Usage follows the in-variable jq convention (standing-kinds.sh): prepend the
# defs to a jq program, e.g.
#   jq "$DISPATCH_PATH_JQ"' map(select(has_dispatch_path | not)) '
# A program built in a double-quoted string expands the variable in place.
# shellcheck disable=SC2034  # read by the scripts that source this file
DISPATCH_PATH_JQ='
  # The metadata keys that each give a bead a dispatch path.
  def dispatch_path_keys: [
    "gc.routed_to",            # a pool queue serves the bead once it is ready
    "gc.dispatch_when_ready"   # an arm the deferred-dispatch order slings once it is ready
  ];
  # True when this bead carries a dispatch path: a dispatch_path_keys key with a
  # non-blank value. A blank value names no queue and no sling target, so it is
  # no path. Reads .metadata only.
  def has_dispatch_path:
    (.metadata // {}) as $m
    | any(dispatch_path_keys[]; ($m[.] // "") | tostring | test("[^[:space:]]"));
'
