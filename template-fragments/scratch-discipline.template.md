{{ define "scratch-discipline" }}
## Scratch discipline

Your scratchpad sits on a per-uid tmpfs quota shared by every agent in the
city. Filling it is not a disk problem. Past the quota, every command that
prints fails with empty output while silent ones still succeed, so the city
loses its shell all at once and the failure never names itself. `df` reports
free space the quota will not hand out, because the quota binds first.

Two habits account for most of the floor, and neither buys anything.

**Keep build artifacts out of scratch.** A compiled binary runs to hundreds
of megabytes and is a second copy of something that already exists. Build to
the build path and reference it there. `assets/scripts/gc-helm-build.sh` owns
the helm binary; nothing else builds it.

**Ask a bead store the narrow question.** `gc bd list` defaults to the open
board, which costs a couple of megabytes. `--all` and `--status=closed` are
more than twenty times that, because the closed history is the bulk of a
store, and both write tens of megabytes to answer a question about a handful
of beads. Reach for either only when the question is genuinely about history,
narrow it in the same breath with `--id`, `-l`, `--metadata-field`,
`--assignee` or `--title-contains`, and pipe the result through `jq` instead
of landing the array in a file.

Write inside the scratchpad you were given, never at the scratch root. A file
loose at the root outlives the session that wrote it and belongs to no one.

Scratch is reclaimed on a retention horizon, so anything worth having after
this turn belongs in the repo (docs/file-structure.md), not in scratch.
{{ end }}
