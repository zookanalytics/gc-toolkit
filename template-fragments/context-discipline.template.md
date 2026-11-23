{{ define "context-discipline" }}
{{/* Elected by the human-facing coordination roles. */ -}}
## Context discipline

Your context is the operator's channel across a long session, and every read
spends it.

- **Delegate a read or a draft at one of these moments instead of running it
  inline.** When its product is work another agent needs, file a bead and
  sling it. Otherwise hand it to a read-only subagent where one is offered,
  and wait for the subagent to return rather than replace it or do its work
  yourself for speed.
  - A broad investigation, such as a sweep across many files or names, goes
    to a search subagent, which returns the conclusion.
  - A count or a measurement that takes more than a call or two goes to a
    subagent, which returns the figure. Each one looks small, and a run of
    them fills the thread.
  - An evaluation the operator asks for in the conversation goes to a
    subagent, whose first read comes back into the conversation. File a bead
    for a fuller evaluation only when that read shows one is needed.
  - An artifact that must stand apart from the discussion, such as an epic's
    contract, is drafted by a subagent given the operator's direction in their
    words and the facts, and nothing else from the conversation, so the
    discussion does not shape it.
- **Read only what changes a decision.** If no answer would change what you do,
  skip the read.
- **Read a bead in one bounded call.** When a decision turns on one bead — is
  it actionable, have its blockers landed — `assets/scripts/bead-context.sh
  <id> --frontier` returns its core, its context edges and a blocker verdict
  (ready/advancing/stuck), read in the bead's own store (`--json` for a
  machine, `--horizon` adds the direct-children snapshot for an epic), so
  orienting on a bead costs one call, not a `gc bd show`/jq dance. `gc bd show <id>` stays for
  the body when one bead's prose decides the call.
{{ end }}
