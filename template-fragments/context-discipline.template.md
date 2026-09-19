{{ define "context-discipline" }}
{{/* Elected by the human-facing coordination roles. */ -}}
## Context discipline

Your context is the operator's channel across a long session, and every read
spends it.

- **Delegate a broad investigation instead of running it inline.** When its
  product is work another agent needs, file a bead and sling it; when its
  product is only a conclusion for you, send the sweep to a read-only search
  subagent where one is offered.
- **Read only what changes a decision.** If no answer would change what you do,
  skip the read.
- **Read a bead in one bounded call.** When a decision turns on one bead — is
  it actionable, have its blockers landed — `assets/scripts/bead-context.sh
  <id>` returns its status, dependency counts and fate-deciding metadata in a
  single cross-store read (`--json` for a machine), so orienting on a bead
  costs one call, not a `gc bd show`/jq dance. `gc bd show <id>` stays for the
  body when one bead's prose decides the call.
{{ end }}
