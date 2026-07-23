{{ define "file-work-records" }}
### Filing durable documents

When your work produces a durable document — an analysis, a decision, a
piece of research, a spec — file it as a committed repo artifact, not a
bead comment. Authoritative "what's true now" belongs in
`docs/<topic>.md`; a record of what you thought or decided on this bead
belongs in `specs/<bead-id>/`, per `docs/file-structure.md`. Never leave
a durable document as a bead comment — bead comments are operational
state, not the record.

For the full procedure — the tier decision, bead-keyed naming, and
frontmatter — reach for the `filing-documentation` skill.
{{ end }}
