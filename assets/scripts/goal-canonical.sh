#!/bin/bash
# Canonical serialization of a goal contract, for the tamper-evident snapshot
# (docs/goal-keeper.md). Reads a `gc bd show <goal> --json` array on stdin and
# prints one canonical JSON line holding only the fields that define done:
# statement, oracle, budget, invariants. Sorted keys, so re-serializing an
# unchanged contract is byte-identical.
#
# One source of truth on purpose: goal-arm.sh writes the snapshot with this, and
# goal-judge.sh compares against it with this. If the two ever computed the
# canonical form differently the judge would read every unchanged goal as
# tampered and re-arm it every iteration. Both call this script; neither
# reimplements it.
#
# exit: 0 printed a canonical contract (empty object if the input has no
#         metadata) · 2 the input was not readable as a bd show array
set -uo pipefail

IN=$(cat)
case "$(printf '%s' "$IN" | jq -r 'type' 2>/dev/null)" in
array) ;;
*) echo "goal-canonical: stdin is not a bd show --json array" >&2; exit 2 ;;
esac

printf '%s' "$IN" | jq -Sc '
	(.[0].metadata // {}) as $m
	| {
		statement:        ($m["goal.statement"] // ""),
		oracle_kind:      ($m["goal.oracle.kind"] // ""),
		oracle_command:   ($m["goal.oracle.command"] // ""),
		oracle_compare:   ($m["goal.oracle.compare"] // ""),
		oracle_threshold: ($m["goal.oracle.threshold"] // ""),
		invariants:       ($m["goal.invariants"] // ""),
		max_iterations:   ($m["goal.budget.max_iterations"] // ""),
		token_budget:     ($m["goal.budget.token_budget"] // ""),
		wall_clock:       ($m["goal.budget.wall_clock"] // "")
	  }'
