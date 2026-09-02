{{ define "scratch-reclaim" }}
## Scratch is reclaimed

Your scratchpad is private to this session, and the pack removes a session's
scratch once the session has been inactive for a day. Nothing there survives a
gap that long. Durable work belongs in the repo (docs/file-structure.md), and
a scratchpad you come back to may need a `mkdir -p` first.

Scratch sits on a per-uid tmpfs quota shared by the whole city, and a single
turn can exhaust it between reaps. Past the quota every command that prints
fails with empty output while silent ones still succeed, so the city loses its
shell all at once and the failure never names itself. Keep build artifacts and
whole-store bead dumps out of scratch: reference a binary at its build path,
and ask `gc bd list` the narrow question rather than writing `--all` to a file.
{{ end }}
