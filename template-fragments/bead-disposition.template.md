{{ define "bead-disposition" }}
### Closing a bead whose work moved: stamp the successor

Not every close is a landing. A bead also closes because its work **moved** — a
pack defect **re-homed** into another rig's store, work **folded** into a bead
that absorbed it, a defect **fixed upstream** by a commit already landed, a
**duplicate**. Each hands the work to a **successor**, and a close that does not
name its successor is indistinguishable from a careless close in exactly the
place the question gets asked: the store the bead lived in.

**Never write that close by hand.** One writer:

```bash
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/bead-rehome.sh" ] && { REHOME="$cand/assets/scripts/bead-rehome.sh"; break; }
done
"$REHOME" --origin <bead-being-closed> --successor <bead-that-carries-it-now> \
  --kind re-homed|folded|fixed-upstream|duplicate --note "<why, one sentence>"
```

It derives both stores from the bead-id prefixes, stamps `gc.superseded_by` +
`gc.superseded_by_store` on the closing bead, **reads them back**, and only then
closes with a populated reason naming kind + successor + store. It refuses
rather than close a bead unpointed, so a failure leaves an open pointed bead —
visible and finishable — never a bare `[Closed]`. On an **already-closed** bead
it is the repair tool: pointer plus a note, nothing reopened.

**The read side: a missing successor is not proof of a false close.** Before you
reopen a closed bead, or escalate one as carelessly closed, ask the bead for its
pointer under **both** conventions in the wild — `jq -r
'.[0].metadata["gc.superseded_by"] // .[0].metadata.superseded_by'` (flat dotted
keys; `.metadata.gc.superseded_by` silently yields null) — then read its notes
and close reason, then search **every** store for a successor. Your rig store is
not the city:

```bash
gc rig list --json | jq -r '.rigs[].path' | while read -r RP; do
  bd --db "$RP/.beads" search "<distinctive words>" --status all --limit 20 --json 2>/dev/null \
    | jq -r --arg rp "$RP" '.[]? | $rp + " " + .id + " [" + .status + "] " + .title'
done
```

Reopening is a write against somebody else's decision. On 2026-08-09 a
single-store search produced **four wrong conclusions across two agents** over
eight beads — reopens, escalations, and retractions that were themselves wrong —
and every one of them would have been prevented by widening the search or by the
pointer above. A silent record is a reason to look wider, not evidence of a
false close; when you resolve one, stamp the pointer the bead should have
carried.

**Who closed it:** the `issues` row has no `closed_by`, and every Dolt write
commits as `beads@local`, so the commit log cannot attribute a close. The
per-store `events` table can — the database name is the bead prefix:

```bash
gc dolt sql -q "SELECT issue_id, event_type, actor, created_at FROM <prefix>.events WHERE issue_id = '<bead-id>' ORDER BY created_at"
```

Full doctrine: `docs/work-bead-state-machine.md` → "Disposition: a close that
hands the work to a successor".
{{ end }}
