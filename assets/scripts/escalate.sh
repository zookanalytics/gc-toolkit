#!/usr/bin/env bash
# escalate.sh — the old name of human-gate.sh, kept as a hand-off that runs it
# with the same arguments and does nothing of its own. A run keeps the text its
# steps were poured with, so a step poured before the rename still calls this
# path, and mol-polecat-work's load-context looks for it on every such run.
# It goes once no open step bead's description names escalate.sh and no session
# that read the old name in its prompt still runs (the debt and its trigger are
# in specs/tk-0ur8r9p/design.md, section 10).
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/human-gate.sh" "$@"
