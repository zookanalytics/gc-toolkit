Formula: mol-digest-generate
Description: Generate activity digest for the mayor.

After claiming this vapor wisp, run:

```bash
gc bd formula show mol-digest-generate --json
```

Follow the step descriptions in order. When finished, close this bead, then run:

```bash
gc runtime drain-ack
```

The drain-ack tells the controller this session is done.

This is a **periodic formula** — dispatched by the deacon's
`periodic-formulas` step when the cooldown trigger elapses. Configured
in `city.toml` under `[formulas]`:

```toml
[[formulas.periodic]]
formula = "mol-digest-generate"
trigger = "cooldown"
interval = "24h"
pool = "dog"
```

The deacon checks if enough time has passed since the last run
(tracked via `type:order-run` beads), pours a wisp, and labels it
for the dog pool. A dog picks it up and runs this formula.

## What it produces

A formatted markdown digest covering:
- Issues filed and closed (by rig, by type)
- Merge activity
- Incidents and escalations
- Agent health summary
- Trends (backlog direction, throughput)

The digest is mailed to the mayor and archived as a digest bead.

Read each step's description before acting — Config values override defaults.
Phase: vapor
Root only: true

Variables:
  {{event_timeout}}: Seconds to wait for slow queries before giving up (default=30)
  {{period}}: The digest period type (daily, weekly) (default=daily)

Steps (3):
  ├── mol-digest-generate.determine-period: Determine digest time range
  ├── mol-digest-generate.collect-data: Collect activity data from all rigs
  └── mol-digest-generate.generate-and-send: Generate digest, send to mayor, archive
