---
name: Gas City search for the board's city page (tk-1tfzr71.178)
description: The Gas City surfaces searched before the helm service gained the city page, its route and its read of doctor's newest run, and before the doctor run's event gained an accepted entry on a check the run did not measure. Read it when judging whether the page should exist as the pack's, or when a Gas City release keeps a doctor result or shows one.
---

# Gas City search for the board's city page

The change adds operational surface:

- a route on the helm service, `GET /helm/city`, with a cache of the city's
  document (`services/helm/internal/server/citypage.go`);
- the read behind it, `services/helm/internal/cityboard`, which decodes the
  newest `gc-toolkit.doctor.ran` event's payload and decides which checks the
  page shows and counts, and `source.EventLog`, which reads that event from the
  supervisor;
- a key in `gctk doctor run`'s event: each `not_measured` entry that carries a
  failure also carries the accepted file's entry, `entry`, when that entry
  accepts the failure;
- a flag of `helm-fixture`, `--city`, the document its city route serves.

It adds no metadata key, bead kind, label or lifecycle state. Gas City is read
at upstream main `5f7cd988a6` (`gastownhall/gascity`), and the city runs gc
1.4.3. The live reads below were made on 2026-11-17 against the city's
supervisor.

## What the page needs

The design's section 5 (`specs/tk-1tfzr71.158/design.md`) asks for a page that
shows, from doctor's newest run: when it ran and whether it completed, late
once it is two hours old; each failing check that two runs in a row measured
and the operator has not accepted, with since when; each check the run did not
measure; the accepted checks, folded; and each monitor order's last good run.
The design's own search
([gas-city-search.md](../tk-1tfzr71.158/gas-city-search.md#the-doctor-order-gctk-doctor-run-and-its-event))
records why the run is the pack's event: Gas City keeps no doctor result.

## What was searched

| Primitive | What it gives | Why it does not cover the need |
|---|---|---|
| The supervisor's event list, `GET /v0/city/{cityName}/events` (`EventListInput` in `internal/api/huma_types_events.go`, `humaHandleEventList` in `internal/api/huma_handlers_events.go`) | Events filtered by `type`, newest first, with `limit`, and a custom event's payload passed through unchanged (`toWireEvent` in `internal/api/convoy_event_stream.go`) | It covers the read. The page composes it with `type=gc-toolkit.doctor.ran&limit=1` and no `since`, so a stopped doctor's last run still answers. Live, the read took 0.1 s. A read whose newest match is older than the active log file scans the archives: a type with no match took 8.7 s |
| `gc events --type <type>` (`cmd/gc/cmd_events.go`) | The same log through the CLI, which gctk's runtime adapter reads | It takes no limit (its flags are `--api`, `--type`, `--since`, `--watch`, `--follow`, `--seq`, `--timeout`, `--after`, `--after-cursor` and `--payload-match`), so it prints every match its read returns where the page needs one. helm-svc already reaches the supervisor over HTTP for its other backend |
| Gas City's dashboard, its Activity page (`internal/api/dashboardspa/web/frontend/src/routes/Activity.tsx`) | The city's events, filtered by type and actor, within a window | Its read is bounded to a window, 24 hours by default (`DEFAULT_EVENT_WINDOW` in `src/supervisor/eventReads.ts`), so a doctor that stopped a day ago shows nothing, and it shows each event's message (`supervisorEventDetail` in `src/supervisor/eventSignals.ts`), never its payload. None of the page's rules is there: which checks two runs measured failing, which the operator accepted, which the run could not measure, and whether the run is late |
| Gas City's dashboard, its Health view (`internal/api/dashboardbff/health.go`) | System health, local tool versions, each rig's store health and the dolt store's trend | It runs no doctor and reads no doctor result |
| A doctor route on the supervisor | None: `internal/api/openapi.json` names no path with `doctor` in it | Gas City keeps no doctor result to serve |
| `DoctorConfig` (`internal/config/config.go`) and `gc doctor`'s flags (`newDoctorCmd` in `cmd/gc/cmd_doctor.go`: `--fix`, `--verbose`, `--json`, `--check-timeout`, `--check`) | doctor's configuration: worktree size thresholds, the nested-worktree escalation and local checks | No way to accept a check's failure, so whether the operator accepted a failure is the pack's own data, `doctor/accepted.toml`, and the run's event is the only place a reader finds it. The new `entry` on a check the run did not measure is that data, for a failure the run carries but could not measure |

No Gas City surface keeps or shows a doctor result, so the page reads the
pack's event through the supervisor's event route and applies the design's
rules in the helm service, which is where the board's other pages apply
theirs (`docs/gctk-architecture.md`, Compositions). A supervisor route that
served doctor's last result would retire the doctor order, its event and this
read, as the design's first upstream ask says (`specs/tk-1tfzr71.158/design.md`,
section 14).

## The cache

Nothing upstream caches a composed answer for a caller, as the rig board's
search found ([specs/tk-yhquh93.2/gas-city-search.md](../tk-yhquh93.2/gas-city-search.md#the-cache)).
The city's document uses the cache the helm service keeps for its rig board
(`internal/server/rigboard.go`): a time to live, here five minutes, and one read
of a key at a time. The newest doctor run changes once an hour, so the page
shows a new run within five minutes of its record, and while reads succeed the
service reads the log at most twelve times an hour however many pages are
open. A failed read is not cached, so the next request reads again.

## The fixture's flag

`helm-fixture` is the pack's own server of the board on fixture data, which a
demo capture and a sitting's live copy of the board run as the rig's declared
serve command. Gas City serves no pack's page on fixture data, and the flag
gives the new route the document it answers, as `--rig-board` does for a
rig's.
