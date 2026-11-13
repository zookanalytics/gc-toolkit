#!/usr/bin/env bash
# dispatch-path.sh — the single definition of a dispatch path: the metadata that
# says how a bead will be dispatched, so whoever set it has already decided that
# dispatch. Two keys each give a bead one. gc.routed_to names a pool queue,
# which serves the bead once bd reports it ready. gc.dispatch_when_ready is an
# arm (gctk bead arm), which the deferred-dispatch order slings once nothing
# holds the bead, by the answer of `gctk bead holds`.
# gc.execution_routed_to is not one: it is execution provenance a formula pour
# leaves, and no queue reads it.
#
# It also defines a dispatch hold, the label that says no worker is the bead's
# next actor. Gas City's two hold labels (DispatchHoldLabels in its package
# beadmeta) are `hold:mayor` and `hold:external`, and Gas City serves a bead
# carrying either to no hook, pool or route-restore sweep. Intake holds new
# work with `hold:mayor` (docs/steering.md). has_dispatch_hold compares a row's
# labels the way Gas City's HasDispatchHold does, each label trimmed and in any
# case. Gas City offers that test only in Go and as a query's --exclude-label,
# and the readers here test JSON rows they have already read.
#
# Sourced (never executed) by the readers that ask whether a bead already has a
# dispatch path: the proactive scan and sling (tools/gc-proactive.sh), which
# react only to input that has none, and the doctor checks
# check-blocked-work-armed, which flags blocked work that has none, and
# check-step-terminal, which counts a step as offerable only when it has one.
# The readers that leave a held bead alone source it too: the proactive scan and
# sling, which file no first reaction for one; check-blocked-work-armed, which
# owes one no arm; check-po-queue-only, which reads a bead routed or assigned to
# the po as reaching it only when no hold holds it, since a held bead reaches no
# seat; and the liveness classifier (liveness-classify.sh, which
# liveness-sweep.sh and its precheck compose) and the re-check a liveness gate's
# message carries (liveness-recheck.sh), which name the hold as a wait.
# The deferred-dispatch order's start (gctk bead start-armed) reads no row here:
# it selects armed beads by Gas City's own serve rule and holds one carrying a
# hold label in any case, as Gas City's hook does, and check-armed-dispatch-owed
# reads its dry run.
# gc-helm.sh sources it to place a held bead: place reports a bead with no hold
# that a route or an arm already dispatches as placed, and refuses one that
# another hold also holds. place, and takeaway and accept when they send a bead
# on, lift `hold:mayor` by removing the spellings dispatch_hold_spellings names.
# One definition, no copies: a key or a label added here is read by every one
# of them at once, and dispatch-path.test.sh fails when a reader stops sourcing
# this file or tests the keys or the labels itself.
#
# Usage follows the in-variable jq convention (standing-kinds.sh): prepend the
# defs to a jq program, e.g.
#   jq "$DISPATCH_PATH_JQ"' map(select((has_dispatch_path or has_dispatch_hold) | not)) '
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
  # The labels Gas City reads as a dispatch hold, lower case.
  def dispatch_hold_labels: [
    "hold:mayor",              # the next actor is the coordinator; intake holds new work with it
    "hold:external"            # the next actor or condition is outside this bd instance
  ];
  # True when this bead carries a dispatch hold: a label that, trimmed and in
  # any case, is one of dispatch_hold_labels. Reads .labels only.
  def has_dispatch_hold:
    any((.labels // [])[]?;
        (tostring | gsub("^[[:space:]]+|[[:space:]]+$"; "") | ascii_downcase) as $l
        | any(dispatch_hold_labels[]; . == $l));
  # The labels on this bead that spell the dispatch hold $hold, one of
  # dispatch_hold_labels, as has_dispatch_hold reads them: each label that,
  # trimmed and in any case, is $hold. bd removes a label by its exact text, so
  # a write that lifts the hold removes each of these. Reads .labels only.
  def dispatch_hold_spellings($hold):
    [ (.labels // [])[]? | tostring
      | select((gsub("^[[:space:]]+|[[:space:]]+$"; "") | ascii_downcase) == $hold) ];
'
