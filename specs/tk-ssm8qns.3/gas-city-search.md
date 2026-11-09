---
name: Gas City search for unit 1 of the gctk architecture (tk-ssm8qns.3)
description: The upstream primitives searched before unit 1 built the store adapter's blocked-set read and the ledger's generated key registry, read on 2026-11-08 at gastownhall/gascity main 9f1abb50188b and gastownhall/beads 7ef2fd05e (the bd 1.3.4 the city runs), with what each covers and what it leaves to gctk, and the figures the adapter's reads took on the gc-toolkit store.
---

# Gas City search: unit 1 of the gctk architecture

Unit 1 builds what [docs/gctk-architecture.md](../../docs/gctk-architecture.md)
draws: the command tree, the store adapter with its fake, and the ledger with
its key registry. Two of them read or record something a platform could hold:
the store's blocked set, and the registry of the keys gctk's domains declare.
Both were searched for on 2026-11-08.

## The blocked set

- **Searched for.** A Gas City route that serves which beads are blocked and
  on what, and a bd answer for a bead with a `waits-for` edge of its own.
- **Gas City.** The supervisor's city routes serve `/beads`, `/beads/graph/{rootID}`
  and `/beads/ready`, and no blocked route (`internal/api/supervisor_city_routes.go`
  at gascity 9f1abb50188b). So the adapter reads the blocked set through
  `gc bd blocked`, as the design's census found at 221b1476dc10.
- **bd.** `GetBlockedIssuesInTx` (`internal/storage/issueops/blocked.go` at
  beads 7ef2fd05e) is as [blocked-census.md](../tk-ssm8qns.2/blocked-census.md#the-stores-rules)
  states for 1.3.2. Its first read is the ids marked blocked, `is_blocked = 1`
  with a status neither `closed` nor `pinned`, from the issues and the wisps
  table, and it returns that read's errors. It judges a bead's own
  `blocks`, `waits-for` and `conditional-blocks` edges by the far bead's
  status, attributes a bead with none live to its parent, and discards a
  failed parent read. The marks read is that first query, run through
  `gc bd sql`, and it ran in every store the pack serves.
- **What it leaves to gctk.** bd's own listing cannot answer a bead with a
  `waits-for` edge of its own, and can lose a bead held through its parent
  with exit 0, so the adapter's two compensations stand (the `waits-for` error
  and the read error), until tk-ssm8qns.5's repair reaches the city's bd and
  tk-ssm8qns.6 drops them. The acceptance test in
  `services/gctk/internal/gcbd/acceptance_test.go` pins each answer on the
  city's bd.

The adapter's two reads, timed on the gc-toolkit store on 2026-11-08, five
runs each, at a one-minute host load of 3.4:

| Read | Time | Beads |
|---|---|---|
| `gc bd blocked --json` | 0.46 to 0.54 s | 403 to 404 |
| the marks read, `gc bd sql --json` | 0.27 to 0.33 s | 403 to 404 |

The design's figures, read on 2026-10-27, were 1.0 to 1.6 s for the listing at
a load of 24, and 0.49 to 0.59 s for the listing beside 0.26 to 0.31 s for the
marks at a load of 12 to 16. The marks read costs what it did, and the
listing at a low load costs what it did at a moderate one.

## The key registry

- **Searched for.** A Gas City or bd registry of the metadata keys a pack
  writes, with each key's owner.
- **bd.** `validation.metadata.fields` (`MetadataSchemaFields` in
  `internal/config/config.go`, and `validation.metadata.mode` in
  `docs/reference/configuration.md`, at beads 7ef2fd05e) declares, in one
  store's config, a field's type, values and bounds, and checks a write
  against them in `warn` or `error` mode. It names no owner, reader or alias,
  and it lives in each store's config rather than in the code that writes the
  key, so it cannot say which package is a key's one writer, which is what
  the ledger's declarations and the compiler hold.
- **Gas City.** GitHub's code search over gastownhall/gascity finds no
  metadata registry, no read of `validation.metadata` and no call of
  `MetadataSchemaFields`.
- **What it leaves to gctk.** The registry, generated from the declarations
  into `services/gctk/key-registry.json`. Its entries carry the type a
  `validation.metadata.fields` entry takes, so a later change can feed bd's
  check from it.
