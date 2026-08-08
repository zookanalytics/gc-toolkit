# Provenance

Status: native

Authored for gc-toolkit from the reviewed realization on the quarry
branch `claude/gas-city-pack-architecture-1uyfq2`
(`packs/gc-next/agents/converse/`), itself built to the ratified design
`specs/tk-h9pq5/design-doc.md` and re-verified against the upstream
`gc-role-worker` contract. Adaptations from the quarry version, each
argued in `specs/2026-08-fresh-start/spine-port.md`:

- Provisional `nx-`/`gc-next` naming stripped; pool binding is
  `gc-toolkit.converse`.
- Drain made explicit (`gc runtime drain-ack`, main's idiom).
- The `.nx-recycle-now` marker guard replaced by a marker-free context
  stewardship clause (no dependency on an overlay main does not stage
  for this role).
- Dispatch example re-pointed from `wright` to the worker pool.
