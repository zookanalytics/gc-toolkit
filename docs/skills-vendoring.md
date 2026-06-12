---
name: Skills Vendoring
description: How gc-toolkit vendors third-party skills via skills.lock.toml — when to use pack-wide vs agent-only scope, how to add an entry, how to refresh, and what licensing the vendored copy preserves.
---

# Skills Vendoring

External skills (Anthropic's catalog at `anthropics/skills`, community
collections, Claude Code plugins, bare GitHub repos containing a
`SKILL.md`) do not ship in Gas City pack shape. The reliable way to
consume them is to **vendor** the skill source into this pack at a
pinned upstream revision. The on-disk copy is then a normal file in
the pack tree, scoped via its location, audited via git history, and
refreshed only when the operator chooses to.

This doc covers the workflow. The mechanical contract is in the
header of [`skills.lock.toml`](../skills.lock.toml); the scripts that
exercise it are in [`tools/`](../tools/).

## Why vendor, not depend-at-runtime

Three properties matter and none of the alternatives give us all three:

1. **Scope.** A Gas City skill belongs to either the pack (every
   agent that imports the pack) or one agent. Path-based scoping is
   how that boundary is expressed. Runtime fetchers that drop skills
   into a user-global directory lose the boundary; everything becomes
   visible to every agent on the machine.
2. **Audit.** A skill is content the LLM reads as part of its
   instructions. A change to it is a behavior change. Vendoring puts
   the change in `git diff` where review happens; runtime fetches do
   not.
3. **Determinism.** A pinned upstream revision means yesterday's
   behavior is reproducible. Curl-installers and plugin marketplaces
   move under us.

Vendoring trades one cost — a refresh step — for those three. The
manifest + refresh script make the cost cheap.

## Pack-wide vs agent-only

The `vendor_at` field in the manifest decides scope:

- `vendor_at = "skills/<name>/"` — **pack-wide**. The skill is
  materialized for every agent that imports `gc-toolkit`. Use this
  for skills that are domain-general (code review heuristics,
  documentation conventions, refactoring playbooks) or that every
  agent in the pack might plausibly invoke.
- `vendor_at = "agents/<agent>/skills/<name>/"` — **agent-only**.
  The skill is materialized only for the named agent. Use this when
  the skill is meaningful for one role and noise for the rest —
  e.g. a brand-styling skill that belongs in a marketing agent's
  toolkit but not in the polecat's.

Default to agent-only when uncertain. Pack-wide is harder to undo
because removing the skill changes every agent's invocation surface.

## Adding a new entry

1. Find or pick the upstream source. The source must be a clonable
   `git` repo containing a `SKILL.md` (possibly at a subpath). For
   v1 the only supported fetcher is `git`.
2. Choose a pin: a release tag (`v1.2.0`), a full SHA, or — if the
   upstream has no tags and you accept the drift — a branch. The
   validator emits a warning, not an error, on branch pins.
3. Decide `vendor_at` per the scope rules above. Two manifest
   entries cannot share the same `vendor_at`.
4. Declare the upstream license. The refresh script does not
   auto-detect it; the field is operator-asserted and the
   `LICENSE` / `COPYING` / `NOTICE` files that exist alongside the
   skill are vendored verbatim for compliance.
5. Append the entry to `skills.lock.toml`. The header in that file
   documents the full schema.
6. Run `make refresh-skills SKILL=<name>` to materialize the skill.
7. Review the resulting diff and `git add` the vendored files
   alongside the manifest change.

The vendored SKILL.md gets a single-line HTML comment immediately
after the frontmatter:

```html
<!-- vendored from <source>@<ref> on <YYYY-MM-DD> by skills.lock.toml -->
```

It renders as nothing in markdown and tells future readers (and
future you) where the file came from without consulting git blame.
Re-running refresh updates the date and ref in place.

## Refreshing

```bash
make refresh-skills              # refresh every manifest entry
make refresh-skills SKILL=NAME   # refresh just one
make validate-skills             # validate on-disk tree against manifest
```

`make refresh-skills` clones each entry's source to a private temp
dir under `/tmp/gc-toolkit-skill-refresh-$$/`, copies the skill into
`vendor_at`, strips Claude-plugin distribution metadata
(`.claude-plugin/`, `plugin.json`, `marketplace.json`), and runs the
validator. It does **not** commit; the resulting working-tree diff
is for the operator (or a polecat) to review and land via the
normal PR flow.

A per-entry failure (clone failure, missing `SKILL.md`, bad
frontmatter) does not abort the run — the rest of the manifest
still refreshes — but the script exits non-zero so CI / wrappers
can tell the difference.

The validator (`make validate-skills`) is also useful standalone:
it confirms every `vendor_at` exists with a valid `SKILL.md`, that
no on-disk vendored skill is missing from the manifest (no
orphans), that there are no `vendor_at` collisions, and that
unknown fetchers or shape-violating entries get rejected.

## License compliance

The `license` field is operator-declared. The script copies any
`LICENSE`, `LICENSE.txt`, `LICENSE.md`, `COPYING`, `COPYING.txt`,
`NOTICE`, or `NOTICE.txt` file found alongside the skill into the
vendored directory verbatim. If the upstream puts its license at
the repo root instead of alongside the skill, copy it manually into
`vendor_at` after refresh — the refresh script only walks the
declared `subpath`.

The vendored skill inherits the upstream license. The header
comment plus the manifest entry give a reader the source and the
revision; the LICENSE file gives them the terms.

## Open follow-ups

This v1 lands the structural piece — manifest format, refresh and
validate scripts, a single mock entry. The follow-ups are
intentionally out of scope here:

- **Other fetchers.** `skills-sh` (curl-installer scripts), `curl`
  (bare URL), and `plugin` (Claude Code plugin marketplaces) are
  reserved in the schema and rejected by the validator. Each is its
  own follow-up bead, gated on demand.
- **CLI surface.** A `gc skill import` / `gc skill sync` subcommand
  would centralize the workflow across packs. That's a separate
  upstream consult; for now, `make` targets and the in-tree scripts
  are sufficient.
- **Auto-refresh.** Cron / CI runs that auto-bump pins are
  intentionally deferred. The current model — operator-driven
  refresh, diff for review, PR for landing — matches the rest of
  the pack's change discipline.
- **Per-skill follow-up beads.** Each real ecosystem skill the
  operator wants to vendor (review, simplify, claude-api, etc.)
  gets its own bead. The mock entry that ships with this bead is
  for end-to-end validation, not as the canonical set.

## Anti-patterns

- **Don't hand-edit a vendored SKILL.md.** The next refresh
  overwrites it. If a local tweak is needed, fork the skill into a
  pack-native `skills/<name>/` (no vendored-from marker, no
  manifest entry) and own it.
- **Don't promote a vendored skill into pack-native scope by
  removing the marker.** The orphan check in the validator catches
  this — every directory with a vendored-from marker must trace to
  the manifest. If you really mean to fork, delete the marker and
  remove the manifest entry in the same change.
- **Don't ship a branch pin to land work.** Use a tag or full SHA.
  Branch pins are allowed (the validator warns rather than errors)
  for cases where the operator is tracking a moving upstream
  deliberately, not as a shortcut.
