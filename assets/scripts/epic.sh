#!/usr/bin/env bash
# epic.sh — files an epic with its contract.
#   epic.sh create <title> [--hypothesis <sentence>] [--handle <words>]
#                  [--boundaries <text>] [--closure-condition <text>]
#                  [--indicators <text>] [--parent <bead-id>] [-d <text>]
#                  [--rig <rig>]
# Each contract field lands in its own key on the epic in the create itself.
# An epic whose parent is not an epic is refused without --hypothesis, and
# nothing is filed. An epic under an epic with no hypothesis is a Delivery,
# which takes no contract field. `epic.sh create --help` states the flags, the
# rule and the exit codes.
#
# `gctk epic` (services/gctk/internal/cli/epic.go) implements it, and this
# script execs it. The work skill calls it through the pack command, the way a
# skill's example calls every writer. The gctk-build order publishes the
# binary. With no binary to exec the call exits 1, names that order, and files
# nothing.
set -u

# gctk-resolve.sh resolves the binary and execs `gctk epic`, or refuses the
# call when there is none to run. It never returns here.
# shellcheck source=gctk-resolve.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/gctk-resolve.sh" || { echo "epic: cannot source gctk-resolve.sh beside this script" >&2; exit 1; }
gctk_require epic "$@"
