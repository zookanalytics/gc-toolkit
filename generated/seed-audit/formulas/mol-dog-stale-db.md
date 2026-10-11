Formula: mol-dog-stale-db
Description: Detect and clean stale Dolt databases and orphan Dolt processes.

After claiming this vapor wisp, run:

```bash
gc bd formula show mol-dog-stale-db --json
```

Follow the step descriptions in order. When finished, close this bead, then run:

```bash
gc runtime drain-ack
```

The drain-ack tells the controller this session is done.

This formula shells out to `gc dolt-cleanup --json`, parses the
`gc.dolt.cleanup.v1` envelope, and emits one summary line per stage
to `gc events` so operators skimming a long scrollback can spot
trends. The full JSON report is appended to the work bead so a
follow-up reader can `bd show <id>` to see details.

## Dog Contract

This is infrastructure work. You:
1. Run a dry-run `gc dolt-cleanup --json --probe` scan.
2. Decide: no work -> report, at/below stale-DB threshold -> apply, above threshold -> escalate.
3. Apply with `gc dolt-cleanup --json --probe --force` only when safe.
4. Report findings, send optional maintenance notices if configured, exit.
5. Return to kennel.

## Variables

| Variable | Source | Description |
|----------|--------|-------------|
| max_orphans_for_sql | formula default | Max stale dropped databases before escalating instead of forcing (default 20) |
| warn_threshold | formula default | Orphan count that triggers a warning maintenance notice (default 5) |

## Safety

`gc dolt-cleanup` resolves the Dolt port via the AD-04 chain
(--port flag > city dolt.port > <rigRoot>/.beads/dolt-server.port >
legacy 3307). Invalid explicit ports and unreadable or invalid rig
port files fail closed; only absent rig port files can reach the
legacy default. It cross-references registered rigs (HQ-first) and
will not drop any database whose name matches a registered rig DB,
nor any Dolt internals (`information_schema`, `mysql`,
`dolt_cluster`, `__gc_probe`). Orphan-process kills are restricted
to processes whose `--config` path lives under the test-config
allowlist (`/tmp/Test*`, `os.TempDir()/Test*`, `~/.gotmp/Test*`).
Database identifiers used for destructive DROP and purge calls must
contain only ASCII letters, digits, underscores, and non-leading
hyphens; rigs with other `dolt_database` names should be renamed or
handled manually so the cleanup can stay SQL-injection safe.

The apply branch treats a non-zero `gc dolt-cleanup --probe --force`
exit as an operator escalation. Do not retry from this formula with
the separate `gc dolt cleanup --server-down-ok` fallback; that is a
TTY-only human action after independently verifying the dolt server
process is stopped and the port is closed.

The runtime work is intentionally one formula step. Formula steps are
separate agent interactions, so scan, decision, apply, and report state
must stay inside one shell execution instead of relying on variables to
cross step boundaries.
Phase: vapor
Root only: true

Variables:
  {{max_orphans_for_sql}}: Maximum stale dropped database count the formula auto-applies; above this, it escalates instead (default=20)
  {{warn_threshold}}: Orphan count that triggers a warning maintenance notice (default=5)

Steps (1):
  └── mol-dog-stale-db.cleanup: Scan, decide, apply, and report stale Dolt cleanup
