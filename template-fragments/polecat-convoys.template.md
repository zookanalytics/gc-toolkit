{{ define "polecat-convoys" }}
### Integration branches (owned convoys)

`metadata.target` is **not always** `{{ .DefaultBranch }}`. When your
work bead lives under an owned convoy with an integration branch
(`gc convoy create --owned --target integration/<convoy-id>`), the
convoy-ancestor walk in `gc sling` resolves `metadata.target =
integration/<convoy-id>`. You branch from
`origin/integration/<convoy-id>`, the refinery rebases your work onto
that integration branch, and the convoy graduates to
`{{ .DefaultBranch }}` later via a separate work bead.

You don't need to do anything special — the formula's
`workspace-setup` step uses `{{`{{base_branch}}`}}` and the done-
sequence preserves `metadata.target`. Just be aware that "your work
landed in the refinery" does **not** always mean "main moved." For an
integration-branch dispatch, main moves only when the convoy
graduates.
{{ end }}
