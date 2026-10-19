---
name: Gas City platform facts and reference index
description: What the pages in docs/gascity/ are and what each covers, the bar a page meets to be one, and the index of canonical Gas City documentation at https://docs.gascity.com/ that they supplement.
---

# Gas City

The pages in this directory are about Gas City itself, the platform
gc-toolkit runs on, and never about the pack. Each states what Gas City
does where upstream's docs leave it unsaid or state it wrongly, under
[the bar](#the-bar), with the source it was read from and the date.
gc-toolkit's own conventions are the pages in `docs/` outside this
directory, such as [human-engagement.md](../human-engagement.md),
[pack-authoring.md](../pack-authoring.md),
[deferred-dispatch.md](../deferred-dispatch.md) and
[fork-patching.md](../fork-patching.md).

Upstream's documentation stays the authority on Gas City, and the index
after the bar points at it. Every link in the index is upstream
documentation; gc-toolkit does not paraphrase or mirror it. If a topic
feels like it needs prose explanation in the index, that is a signal the
prose belongs in an upstream PR to `gastownhall/gascity`.

## Scope

**Mandate.** What the pages in this directory are: the bar a page meets to
be one, and what each covers. It is also the grounding in canonical Gas
City documentation that the rest of gc-toolkit's Gas City material is
built on — the reference point that ties this toolkit back to the upstream
source of truth at https://docs.gascity.com/ — and it marks where upstream
coverage falls short.

**Boundaries.** The index links to upstream docs and does not paraphrase
or mirror them. Prose that explains rather than indexes belongs upstream,
and the Gas City facts upstream leaves unsaid are on the pages listed
below, not here. gc-toolkit's own conventions are the pages outside this
directory.

## The pages here

Each page here is a local supplement: a topic gc-toolkit has captured
where upstream coverage is missing, partial, or contradicted by a more
recent maintainer ruling. It is gc-toolkit-authored prose that states Gas
City behavior only, under [the bar](#the-bar).

- [Gas City and human engagement](human-engagement.md) — the Gas City primitives a human conversation can ride and how a session and its pane end: human gates and the core orders that surface them, where a question surfaces, the idle ladder, max age, manual sessions, the stop and the backstops.
- [Gas City agent types](agent-types.md) — the agent variants where upstream's docs leave them unsaid: scope expansion, named-session demand and patches, wake reasons and turns, pool slots and names, kill and close, the control-dispatcher, `gc session new`, nudge fences, and which fields name a bead's holder.
- [Gas City routing model](routing-model.md) — how Gas City delivers a bead to the session that acts on it: what the sling router writes, the claim predicate, how a graph.v2 pour routes its records, what holds a bead, the bd guard that can refuse a detach, and the route the controller restores.
- [Gas City pack & formula authoring](packs.md) — what Gas City does with a pack and a formula that its specs leave unsaid: how a v2 step advances and a run is cancelled, what processes `workflow-finalize`, when a check loop gets a fresh context, how a directory import goes live, how builtin pins resolve, and what a formula body can expand.

[dispatch-containment.md](dispatch-containment.md) is retired, and points
to where its topic is documented now.

## The bar

A page lives in `docs/gascity/` only when **all** of these hold:

1. **It states Gas City behavior and nothing else.** A page here says
   what the platform does: the `gc` and `bd` binaries and the packs
   Gas City bundles, such as `core`. gc-toolkit's own conventions — its
   agents, formulas, scripts, orders and skills, and this city's
   configuration — belong to the page that owns that subsystem, never to
   a page here, not even as an example of the behavior. A page here may
   link to a pack page, labeled as gc-toolkit's.
2. **Upstream's docs do not already say it.** Lean on upstream Gas City
   documentation where it exists. A fact upstream documents is a link
   here, not a restatement of it.
3. **Each section carries its evidence and its date.** It names the
   upstream doc it supplements, and, where no doc says it, the source it
   was read from as a symbol and file at a named commit rather than a
   line number. It says when it was verified, and a fact verified only on
   this city's gascity fork says so.
4. **The learning is durable, not bead-tied.** One-incident gotchas
   live in `specs/<bead-id>/` or working memory.
5. **Someone owns keeping it current** as upstream Gas City evolves.
6. **It's non-obvious** — a competent new contributor wouldn't infer
   it from upstream docs plus the code.

If any of these fails, the content does not belong here.

## Getting started

- Installation: https://docs.gascity.com/getting-started/installation
- Quickstart: https://docs.gascity.com/getting-started/quickstart
- Coming from Gas Town: https://docs.gascity.com/getting-started/coming-from-gastown
- How Gas City works: https://docs.gascity.com/getting-started/how-gas-city-works
- Install/setup troubleshooting: https://docs.gascity.com/getting-started/troubleshooting

## Architecture & concepts

- Reference overview (incl. internals): https://docs.gascity.com/reference/index
- Beads topology (one Dolt server, isolated beads): https://docs.gascity.com/reference/internal/beads-topology

## Configuration

- Config reference (city.toml, pack.toml, rig configs): https://docs.gascity.com/reference/config

## CLI / API / events / formulas / providers / trust boundaries

- CLI reference: https://docs.gascity.com/reference/cli
- HTTP + SSE API (supervisor control plane): https://docs.gascity.com/reference/api
- Events (`gc events` output formats): https://docs.gascity.com/reference/events
- Formulas — the contract guide (v1 and v2 are peers): https://docs.gascity.com/guides/understanding-formulas
- Formula spec — v2 (graph / orchestrated contract): https://docs.gascity.com/reference/specs/formula-spec-v2
- Formula spec — v1 (default contract): https://docs.gascity.com/reference/specs/formula-spec-v1
- Specs register (index of reference specs): https://docs.gascity.com/reference/specs
- Formulas architecture (implementation internals, deep reference): https://github.com/gastownhall/gascity/blob/main/engdocs/architecture/formulas.md
- Exec beads provider: https://docs.gascity.com/reference/exec-beads-provider
- Exec session provider: https://docs.gascity.com/reference/exec-session-provider
- Trust boundaries (command execution model): https://docs.gascity.com/reference/trust-boundaries

## Pack v2 (current pack model)

The pack spec is the authoritative reference and the understanding-packs
guide is the narrative entry point; the shareable-packs guide covers the
create / import / customize workflow. The design notes in
`gastownhall/gascity` are deep reference. There is no standalone
migration guide — PackV2 migration lives in `gc doctor` (`gc doctor
--fix` repairs legacy `pack.toml`) and the shareable-packs guide.

- Pack spec (authoritative `pack.toml` + layout reference): https://docs.gascity.com/reference/specs/pack-spec
- Understanding packs (pack model, imports, scope, patches, loading order): https://docs.gascity.com/guides/understanding-packs
- Shareable packs (creating, importing, customizing PackV2 packs): https://docs.gascity.com/guides/shareable-packs

Deep reference — PackV2 design notes in `gastownhall/gascity`:

- Pack v2 design: https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/doc-pack-v2.md
- Pack loader v2: https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/doc-loader-v2.md
- Agent v2: https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/doc-agent-v2.md
- Commands: https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/doc-commands.md
- Directory conventions: https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/doc-directory-conventions.md
- Packman (pack-management CLI): https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/doc-packman.md
- Rig binding phases: https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/doc-rig-binding-phases.md
- Conformance matrix: https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/doc-conformance-matrix.md
- Consistency audit: https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/doc-consistency-audit.md
- Migration source (MDX): https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/migration.mdx
- Skew analysis: https://github.com/gastownhall/gascity/blob/main/engdocs/design/packv2/skew-analysis.md

## Guides

- Guides index: https://docs.gascity.com/guides
- Authoring and importing shareable packs: https://docs.gascity.com/guides/shareable-packs

## Troubleshooting

- Dolt bloat recovery: https://docs.gascity.com/troubleshooting/dolt-bloat-recovery

## Tutorials

Upstream owns hands-on walkthroughs. Consult these when bootstrapping;
gc-toolkit does not restate them.

- Tutorials index: https://docs.gascity.com/tutorials
- Cities and rigs: https://docs.gascity.com/tutorials/01-cities-and-rigs
- Agents: https://docs.gascity.com/tutorials/02-agents
- Sessions: https://docs.gascity.com/tutorials/03-sessions
- Communication: https://docs.gascity.com/tutorials/04-communication
- Formulas: https://docs.gascity.com/tutorials/05-formulas
- Beads (universal work primitive): https://docs.gascity.com/tutorials/06-beads
- Orders: https://docs.gascity.com/tutorials/07-orders

## Schemas

Machine-readable artifacts. Each link is the canonical download.

- Schemas index: https://docs.gascity.com/reference/schema/index
- OpenAPI 3.1: https://docs.gascity.com/reference/schema/openapi.json
- Events JSONL: https://docs.gascity.com/reference/schema/events.json
- City config: https://docs.gascity.com/reference/schema/city-schema.json

## Gaps

Topics gc-toolkit has hit in practice that have no upstream coverage
yet. Entries here are a TBD list; the resolution is to file an
upstream PR (per the upstream-engagement doctrine (mechanik prompt; keeper sub-pack)
into the mechanik prompt) rather than restate the content
in this index.

- *(none recorded yet — when you find a gap, file the bead and add a
  pointer here)*

## Refresh procedure

This index is **manually maintained**. Upstream movement does not
auto-update it.

To detect drift:

1. **Link-check.** Walk every URL in this file and confirm it still
   returns 200:

   ```bash
   grep -oE 'https://[^ )]+' docs/gascity/README.md \
     | sort -u \
     | while read u; do
         code=$(curl -sIfL -o /dev/null -w '%{http_code}' "$u" 2>/dev/null)
         printf '%s %s\n' "$code" "$u"
       done
   ```

   `301`/`302`/`308` redirects are fine; `404` means the page moved or
   was removed upstream.

   **A green link-check is not proof of coverage.** A `301`/`302`/`308`
   redirect — or even a `200` — can mask an upstream *content
   restructure*: the URL still resolves, but its target no longer covers
   the same topic. This is exactly how the #3461 formula move slipped past
   the last refresh — `reference/formula` kept resolving while its content
   was split into the v1/v2 specs and the understanding-formulas guide. For
   any topic that matters, open the target and confirm it still says what
   this index claims it does.

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
