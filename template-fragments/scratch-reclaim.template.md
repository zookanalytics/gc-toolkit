{{ define "scratch-reclaim" }}
## Scratch is reclaimed

Your scratchpad is private to this session and removed after a day idle, so
durable work belongs in the repo (docs/file-structure.md) and a returning
session may need `mkdir -p` first. Keep build artifacts and whole-store bead
dumps out of scratch: reference a binary at its build path, and ask for the
narrow `gc bd list` rather than writing `--all` to a file.
{{ end }}
