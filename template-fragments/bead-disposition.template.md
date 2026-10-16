{{ define "bead-disposition" }}
### Closing a bead that did not land: stamp the successor

A bead that closes without landing, because its work moved or is not needed,
closes through the disposition writer and never by hand (the `work` skill,
closing a bead that needs no work). The writer runs only once the no-op record
landed:

```bash
gc bd update <bead> --set-metadata gc.work_outcome=no-op \
  && "{{ .ConfigDir }}/assets/scripts/bead-rehome.sh" --origin <bead> --successor <carrier-or-evidence> \
  --kind re-homed|folded|fixed-upstream|duplicate|not-needed --note "<why, one sentence>"
```

**The read side: a missing successor is not proof of a false close.**
Before reopening or escalating a closed bead, read the pointer under both
conventions (`.metadata["gc.superseded_by"] // .metadata.superseded_by`),
read notes and close reason, then search EVERY store — your rig store is
not the city:

```bash
gc rig list --json | jq -r '.rigs[].path' | while read -r RP; do
  gc bd --db "$RP/.beads" search "<distinctive words>" --status all --limit 20 --json 2>/dev/null \
    | jq -r --arg rp "$RP" '.[]? | $rp + " " + .id + " [" + .status + "] " + .title'
done
```

Reopening is a write against somebody else's decision; a silent record is a
reason to look wider, not evidence of a false close. Who closed it: the
per-store `events` table (`SELECT issue_id, event_type, actor, created_at
FROM <prefix>.events WHERE issue_id = '<bead-id>'`).
{{ end }}
