---
name: Gas City search for the rig board's page (tk-yhquh93.9)
description: The Gas City primitives searched before the board's page read one bead's description from the supervisor and before helm-fixture answered the rig board's routes, what each covers, and why the fixture keeps a route of its own. Read it when judging whether the page's supervisor read or the fixture's rig routes should exist.
---

# Gas City search for the rig board's page

The change adds no route, order, metadata key, bead kind, label or lifecycle
state to the helm service. It grows two things:

- the page's one read of the supervisor itself: a bead's whole description,
  read when its row's Details opens (`services/helm/web/src/supervisor/`);
- `helm-fixture`, the helm service's command that serves the page on fixture
  data for a demo capture, which now answers `GET /helm/rigs` and
  `GET /helm/rigs/{rig}` from a rig document file, named by a new
  `--rig-board` flag (`services/helm/internal/fixture`,
  `services/helm/cmd/helm-fixture`).

Read on 2026-11-11 at Gas City upstream `f143846427` (`gastownhall/gascity`).
The routes `helm-fixture` mirrors are helm-svc's own, and their search is
[specs/tk-yhquh93.2/gas-city-search.md](../tk-yhquh93.2/gas-city-search.md).

## A bead's description

The rig's document leaves out every piece of work's description, so Details
reads that one bead's text when it opens.

| Primitive | What it gives | Covers the need? |
|---|---|---|
| The supervisor's `GET /v0/city/{cityName}/bead/{id}` (`humaHandleBeadGet` in `internal/api/huma_handlers_beads.go`, registered by `cityGet(sm, "/bead/{id}", ...)` in `internal/api/supervisor_city_routes.go`) | One bead of any rig in the city, as `beads.Bead`, whose `description` is the whole text, served on the origin the page is served from | Yes. The page composes it through the typed client it generates from the supervisor's own OpenAPI document, pruned to this one operation |

## The page on fixture data

A demo capture shows the page the reviewed commit builds, with no city behind
it, because the helm service's write routes act on the live city.

| Primitive | What it gives | Covers the need? |
|---|---|---|
| The supervisor's workspace service proxy (`serviceSubpath` in `internal/workspacesvc/manager.go`) | Mounts a running workspace service at `/v0/city/{city}/svc/{name}/` | No. It serves a service that runs against the city, and the page's reads would reach the live store |
| Gas City's dashboard bundle (`internal/api/dashboardspa`) | Serves Gas City's own dashboard, which reads the live API | No. It serves Gas City's page, not the pack's, and reads the live city |

Neither serves a pack's page on fixture data, so `helm-fixture` keeps that job,
and answers the rig board's routes in the shapes helm-svc answers them, from a
file. It links nothing that reads a store, as its import-graph test holds it.
