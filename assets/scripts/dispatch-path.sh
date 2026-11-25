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
# next actor: any hold:<value> whose value is not cleared, and Gas City serves
# a bead carrying one to no hook, pool or route-restore sweep. has_dispatch_hold
# reads a row's labels the way the city's gc reads one (ActiveHoldValue in its
# package beadmeta, rendered in jq as activeHoldLabelJQ in
# internal/config/workquery.go, at zookanalytics/gascity d62873fce6): the label
# trimmed, its hold: prefix in any case, and its value trimmed, not empty and
# not cleared in any case. Gas City offers that test only in Go and inside the
# work queries it generates, and the readers here test JSON rows they have
# already read. Intake holds new work for placement with `hold:po`, and
# `hold:mayor` is the placement hold's earlier spelling, which a bead held before
# the move to hold:po carries until gctk bead move-placement-hold moves it
# (docs/steering.md). placement_hold_spellings names both.
#
# Sourced (never executed) by the readers that ask whether a bead already has a
# dispatch path: the doctor checks check-blocked-work-armed, which flags blocked
# work that has none, and check-step-terminal, which counts a step as offerable
# only when it has one.
# The readers that leave a held bead alone source it too:
# check-blocked-work-armed, which owes one no arm; check-po-queue-only, which
# reads a bead routed or assigned to the po as reaching it only when no hold
# holds it, since a held bead reaches no seat; and the liveness classifier
# (liveness-classify.sh, which liveness-sweep.sh and its precheck compose) and
# the re-check a liveness gate's message carries (liveness-recheck.sh), which
# name the hold as a wait.
# The deferred-dispatch order's start (gctk bead start-armed) reads no row here:
# it selects armed beads by Gas City's own serve rule and holds one carrying a
# hold label in any case, as Gas City's hook does, and check-armed-dispatch-owed
# reads its dry run. The first reaction's check, sling and sweep (gctk reaction)
# read no row here either: they ask the arm's record and the runtime adapter's
# dispatch hold (services/gctk/internal/gascity/hold.go).
# gctk bead place, gctk reaction accept and gctk bead takeaway, which lift
# the placement hold when they send a bead on, read no row here: they take its
# spellings from the runtime adapter (services/gctk/internal/gascity/hold.go).
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
  # The value of the label in scope when it is a dispatch hold, lower case, or
  # null: the label trimmed, its hold: prefix in any case, and its value
  # trimmed, not empty and not cleared. hold:cleared is the value
  # `bd set-state <id> hold=cleared` leaves, and holds nothing.
  def dispatch_hold_value:
    (tostring | gsub("^[[:space:]]+|[[:space:]]+$"; "")) as $l
    | if ($l | ascii_downcase | startswith("hold:"))
      then ($l[5:] | gsub("^[[:space:]]+|[[:space:]]+$"; "") | ascii_downcase)
           | if . == "" or . == "cleared" then null else . end
      else null end;
  # True when this bead carries a dispatch hold, whatever its value. Reads
  # .labels only.
  def has_dispatch_hold: any((.labels // [])[]?; dispatch_hold_value != null);
  # The values of the placement hold, which holds a bead for the po of its rig
  # to place: po, and mayor, its earlier spelling.
  def placement_hold_values: ["po", "mayor"];
  # The labels on this bead that spell the placement hold, as has_dispatch_hold
  # reads a hold, each as the bead carries it. bd removes a label by its exact
  # text, so a write that lifts the placement hold removes each of these, and no
  # other hold. Reads .labels only.
  def placement_hold_spellings:
    [ (.labels // [])[]? | tostring
      | select(dispatch_hold_value as $v | $v != null and any(placement_hold_values[]; . == $v)) ];
'
