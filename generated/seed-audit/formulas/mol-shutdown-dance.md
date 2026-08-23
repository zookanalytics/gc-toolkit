Formula: mol-shutdown-dance
Description: Shutdown dance — due process for stuck agents.

Dispatched by filing a warrant bead routed to the dog pool:

```bash
gc bd create --type=task --title="Stuck: <agent>" --metadata '{"target":"<session>","reason":"<reason>","requester":"<who>","gc.routed_to":"<binding-prefix>dog"}' --label=warrant
```

The dog pool picks up the warrant and runs this formula against the
claimed warrant bead. The claimed bead is the warrant id; use
`$GC_BEAD_ID` for warrant verification, closure, and audit output.
Existing warrant producers provide `target`, `reason`, and `requester`
metadata, not a separate `warrant_id`. Each warrant is one shutdown dance
for one target. On crash, re-read formula steps and resume from context
(check target state, attempt history).

Before running command snippets in any step, load warrant metadata into quoted
shell variables:

```bash
warrant_json="$(gc bd show "$GC_BEAD_ID" --json)"
target="$(printf '%s' "$warrant_json" | jq -r '.[0].metadata.target // empty')"
reason="$(printf '%s' "$warrant_json" | jq -r '.[0].metadata.reason // empty')"
requester="$(printf '%s' "$warrant_json" | jq -r '.[0].metadata.requester // "deacon"')"
requester_endpoint="${requester%/}/"
if [ -z "$target" ] || [ -z "$reason" ]; then
  echo "warrant $GC_BEAD_ID is missing target or reason" >&2
  gc bd close "$GC_BEAD_ID" --reason "MALFORMED_WARRANT: missing target or reason metadata"
  gc session nudge "$requester_endpoint" "DOG_DONE: warrant $GC_BEAD_ID - MALFORMED_WARRANT (missing target or reason)" || true
  gc runtime drain-ack
  exit 1
fi
```

## State Machine

```
RECEIVE → INTERROGATE (1) → INTERROGATE (2) → INTERROGATE (3) → EXECUTE → EPITAPH
              ↓                   ↓                   ↓
           ALIVE?             ALIVE?              ALIVE?
              ↓                   ↓                   ↓
           [yes → EPITAPH with PARDONED]          [no → EXECUTE]
```

## Timeouts

| Attempt | Timeout | Cumulative |
|---------|---------|------------|
| 1       | 60s     | 60s        |
| 2       | 120s    | 180s (3m)  |
| 3       | 240s    | 420s (7m)  |

## Who files warrants

| Detector | Stuck agent | Detection method |
|----------|-------------|-----------------|
| Deacon health-scan | Witness | Stale patrol wisp |
| Deacon health-scan | Refinery | Stale wisp + queue has work |
| Deacon utility-agent-health | Dog | Stale wisp/bead |
| Witness check-polecat-health | Polecat | Stale work bead, no progress |

No agent kills anything directly. The shutdown dance is the single
recovery mechanism for all stuck agents.

Read each step's description before acting — Config values override defaults.

Steps (6):
  ├── mol-shutdown-dance.receive-warrant: Validate warrant and confirm target alive
  ├── mol-shutdown-dance.interrogate-1: First health check (60s timeout) [needs: mol-shutdown-dance.receive-warrant]
  ├── mol-shutdown-dance.interrogate-2: Second health check (120s timeout) [needs: mol-shutdown-dance.interrogate-1]
  ├── mol-shutdown-dance.interrogate-3: Final health check (240s timeout) [needs: mol-shutdown-dance.interrogate-2]
  ├── mol-shutdown-dance.execute: Execute warrant — kill session [needs: mol-shutdown-dance.interrogate-3]
  └── mol-shutdown-dance.epitaph: Log outcome, notify, and exit [needs: mol-shutdown-dance.execute]
