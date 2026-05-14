---
name: gascity reference index
description: Index of canonical Gas City documentation at https://docs.gascityhall.com/, plus the bar gc-toolkit applies before adding new gascity-* docs.
---

# gascity reference index

This file is an **index**, not a summary. Every link below points at
upstream documentation; gc-toolkit does not paraphrase or mirror it. If
a topic feels like it needs prose explanation here, that is a signal
the prose belongs in an upstream PR to `gastownhall/gascity`, not in
this index.

## The bar

A doc lives under `docs/gascity-*.md` only when **all four** hold:

1. **It's about gc-toolkit's _use_ of Gas City, not Gas City itself.**
   Generic Gas City knowledge belongs upstream — file a PR to
   `gastownhall/gascity`.
2. **The learning is durable, not bead-tied.** One-incident gotchas
   live in `specs/<bead-id>/` or working memory.
3. **Someone owns keeping it current** as upstream Gas City evolves.
4. **It's non-obvious** — a competent new contributor wouldn't infer
   it from upstream docs plus the code.

If any of the four fail, the content does not belong here. The
`gascity-*.md` series is gc-toolkit-specific learnings; broad Gas City
content goes upstream or stays out.

## Getting started

- Installation: https://docs.gascityhall.com/getting-started/installation
- Quickstart: https://docs.gascityhall.com/getting-started/quickstart
- Coming from Gas Town: https://docs.gascityhall.com/getting-started/coming-from-gastown
- Repository map: https://docs.gascityhall.com/getting-started/repository-map
- Install/setup troubleshooting: https://docs.gascityhall.com/getting-started/troubleshooting

## Architecture & concepts

- Internals overview: https://docs.gascityhall.com/internals
- Beads topology (one Dolt server, isolated beads): https://docs.gascityhall.com/internals/beads-topology

## Configuration

- Config reference (city.toml, pack.toml, rig configs): https://docs.gascityhall.com/reference/config

## CLI / API / events / formulas / providers / trust boundaries

- CLI reference: https://docs.gascityhall.com/reference/cli
- HTTP + SSE API (supervisor control plane): https://docs.gascityhall.com/reference/api
- Events (`gc events` output formats): https://docs.gascityhall.com/reference/events
- Formulas (structure and placement): https://docs.gascityhall.com/reference/formula
- Exec beads provider: https://docs.gascityhall.com/reference/exec-beads-provider
- Exec session provider: https://docs.gascityhall.com/reference/exec-session-provider
- Trust boundaries (command execution model): https://docs.gascityhall.com/reference/trust-boundaries

## Pack v2 (current pack model)

The migration guide and the shareable-packs guide are the canonical
narrative entry points; the design notes in `gastownhall/gascity` are
the deep reference.

- Migration guide (Gas City 0.14.0 city or pack → PackV2): https://docs.gascityhall.com/guides/migrating-to-pack-vnext
- Shareable packs (creating, importing, customizing PackV2 packs): https://docs.gascityhall.com/guides/shareable-packs
- Pack v2 design: https://github.com/gastownhall/gascity/blob/main/docs/packv2/doc-pack-v2.md
- Pack loader v2: https://github.com/gastownhall/gascity/blob/main/docs/packv2/doc-loader-v2.md
- Agent v2: https://github.com/gastownhall/gascity/blob/main/docs/packv2/doc-agent-v2.md
- Commands: https://github.com/gastownhall/gascity/blob/main/docs/packv2/doc-commands.md
- Directory conventions: https://github.com/gastownhall/gascity/blob/main/docs/packv2/doc-directory-conventions.md
- Packman (pack-management CLI): https://github.com/gastownhall/gascity/blob/main/docs/packv2/doc-packman.md
- Rig binding phases: https://github.com/gastownhall/gascity/blob/main/docs/packv2/doc-rig-binding-phases.md
- Conformance matrix: https://github.com/gastownhall/gascity/blob/main/docs/packv2/doc-conformance-matrix.md
- Consistency audit: https://github.com/gastownhall/gascity/blob/main/docs/packv2/doc-consistency-audit.md
- Migration source (MDX): https://github.com/gastownhall/gascity/blob/main/docs/packv2/migration.mdx
- Skew analysis: https://github.com/gastownhall/gascity/blob/main/docs/packv2/skew-analysis.md

## Guides

- Guides index: https://docs.gascityhall.com/guides
- Migrating to PackV2: https://docs.gascityhall.com/guides/migrating-to-pack-vnext
- Authoring and importing shareable packs: https://docs.gascityhall.com/guides/shareable-packs

## Troubleshooting

- Dolt bloat recovery: https://docs.gascityhall.com/troubleshooting/dolt-bloat-recovery

## Tutorials

Upstream owns hands-on walkthroughs. Consult these when bootstrapping;
gc-toolkit does not restate them.

- Tutorials index: https://docs.gascityhall.com/tutorials
- Cities and rigs: https://docs.gascityhall.com/tutorials/01-cities-and-rigs
- Agents: https://docs.gascityhall.com/tutorials/02-agents
- Sessions: https://docs.gascityhall.com/tutorials/03-sessions
- Communication: https://docs.gascityhall.com/tutorials/04-communication
- Formulas: https://docs.gascityhall.com/tutorials/05-formulas
- Beads (universal work primitive): https://docs.gascityhall.com/tutorials/06-beads
- Orders: https://docs.gascityhall.com/tutorials/07-orders

## Schemas

Machine-readable artifacts. Each link is the canonical download.

- Schemas index: https://docs.gascityhall.com/schema
- OpenAPI 3.1: https://docs.gascityhall.com/schema/openapi.json
- Events JSONL: https://docs.gascityhall.com/schema/events.json
- City config: https://docs.gascityhall.com/schema/city-schema.json

## Gaps

Topics gc-toolkit has hit in practice that have no upstream coverage
yet. Entries here are a TBD list; the resolution is to file an
upstream PR (per [`gascity-upstream-engagement.md`](./gascity-upstream-engagement.md))
rather than restate the content in this index.

- *(none recorded yet — when you find a gap, file the bead and add a
  pointer here)*

## Refresh procedure

This index is **manually maintained**. Upstream movement does not
auto-update it.

To detect drift:

1. **Link-check.** Walk every URL in this file and confirm it still
   returns 200:

   ```bash
   grep -oE 'https://[^ )]+' docs/gascity-reference.md \
     | sort -u \
     | while read u; do
         code=$(curl -sIfL -o /dev/null -w '%{http_code}' "$u" 2>/dev/null)
         printf '%s %s\n' "$code" "$u"
       done
   ```

   `301`/`302`/`308` redirects are fine; `404` means the page moved or
   was removed upstream.

2. **For maintainers with a local gascity checkout**, audit
   added/moved files since the last refresh:

   ```bash
   git -C <gascity-checkout> log --since='<last refresh date>' \
     --name-status -- docs/
   ```

   Reconcile new docs into the appropriate section; drop pointers to
   removed docs.

3. **Record renames.** When a URL has moved, update it here and leave
   a one-line memory entry so the next refresh remembers the rename.

The index does not claim to be exhaustive. If you discover an upstream
doc that isn't listed, add it. If a section here is empty, the topic
likely lives entirely upstream and needs no gc-toolkit-specific
framing.
