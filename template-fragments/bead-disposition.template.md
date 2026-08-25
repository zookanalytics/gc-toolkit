{{ define "bead-disposition" }}
### Closing a bead whose work moved: stamp the successor

Not every close is a landing. A bead also closes because its work MOVED —
re-homed to another rig's store, folded into an absorbing bead, fixed
upstream, a duplicate. Each hands the work to a successor, and a close that
does not name its successor is indistinguishable from a careless close.

**Never write that close by hand.** One writer:

```bash
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/bead-rehome.sh" ] && { REHOME="$cand/assets/scripts/bead-rehome.sh"; break; }
done
"$REHOME" --origin <bead-being-closed> --successor <bead-that-carries-it-now> \
  --kind re-homed|folded|fixed-upstream|duplicate --note "<why, one sentence>"
```

It stamps `gc.superseded_by` + `gc.superseded_by_store`, reads them back,
and only then closes with a reason naming kind + successor + store; it
refuses to close a bead unpointed. On an already-closed bead it is the
repair tool (pointer + note, nothing reopened).

**The read side: a missing successor is not proof of a false close.**
Before reopening or escalating a closed bead, read the pointer under both
conventions (`.metadata["gc.superseded_by"] // .metadata.superseded_by`),
read notes and close reason, then search EVERY store — your rig store is
not the city:

```bash
gc rig list --json | jq -r '.rigs[].path' | while read -r RP; do
  bd --db "$RP/.beads" search "<distinctive words>" --status all --limit 20 --json 2>/dev/null \
    | jq -r --arg rp "$RP" '.[]? | $rp + " " + .id + " [" + .status + "] " + .title'
done
```

Reopening is a write against somebody else's decision; a silent record is a
reason to look wider, not evidence of a false close. Who closed it: the
per-store `events` table (`SELECT issue_id, event_type, actor, created_at
FROM <prefix>.events WHERE issue_id = '<bead-id>'`).
{{ end }}
