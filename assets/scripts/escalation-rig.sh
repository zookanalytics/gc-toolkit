#!/usr/bin/env bash
# escalation-rig.sh — kept as a hand-off that runs bead-store.sh with the same
# arguments and does nothing of its own:
#   escalation-rig.sh <bead-id>        the rig whose store holds it
#   escalation-rig.sh --db <bead-id>   that store's path, <rig path>/.beads
# A run keeps the text its steps were poured with, and a session keeps the
# prompt it read when it started. A dog run poured before the rename to
# human-gate.sh, and a deacon session started before then, still bind GC_RIG
# through this path, and their call to escalate.sh files only once it answers.
# human-gate.sh files in the subject's own store whatever GC_RIG says. The
# hand-off goes once no open step bead's description names escalation-rig.sh
# and no session that read the old name in its prompt still runs (the debt and
# its trigger are in specs/tk-0ur8r9p/design.md, section 10).
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/bead-store.sh" "$@"
