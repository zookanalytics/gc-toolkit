---
name: Gas City graph.v2 dispatch containment
description: The recovery procedure for a formula dispatch that was poured before it should have been — how to find every record the pour created, take delivery away from all of them, and tell a record that is contained from one that only reads that way. Read it when the sling already happened.
---

# Containing a graph.v2 dispatch already in flight

A `blocks` dep between work beads does not hold a graph.v2 formula
dispatch, and nothing on the sling path checks for one either: sling a
blocked bead and the molecule pours immediately, routes the workflow
root, and a worker claims it. Sequencing lives in the *order you
dispatch*, not in the dep graph — so a dispatch that must wait is
recorded on the bead and performed later
([deferred-dispatch.md](deferred-dispatch.md)) rather than held in the
dispatcher's context. The mechanism — which record is routed, and why
none of the edges the read side walks reach the work bead — is
the routing contract's question and lives in
[gascity-routing-model.md](gascity-routing-model.md#a-blocks-dep-between-work-beads-does-not-hold-a-graphv2-dispatch).

This doc starts one step later: the pour already happened, and you are
racing the pool.

**If you are a polecat holding your OWN dispatch, do not hand-run this.**
`assets/scripts/hold-dispatch.sh` is the one writer for that case: it records
the reason, parks the anchor, and quiesces the molecule's steps in a single
call, with the anchor-match and finalize guards below already applied. This
recipe is the incident procedure for a dispatch nobody is holding — a pour that
must be recalled from outside the session that received it. The hold path had
no writer until tk-oqseh6, and hand-parking it is what produced that bug: the
anchor was parked, the molecule was not, and the dead step chain was re-offered
to a fresh polecat every cycle thereafter.

## Scope

**Mandate.** Recovering from a graph.v2 formula dispatch that was poured
before it should have been — finding every record the pour created,
taking delivery away from all of them, and reading the result honestly:
which rows mean contained, which mean run it again, and which mean the
work is already gone.

**Boundaries.** This is the incident procedure only. *Why* a dependency
edge does not gate a dispatch, which field each delivery lane is
responsible for setting, and how to hold a bead you have **not** yet
slung are the routing contract's, and live in
[gascity-routing-model.md](gascity-routing-model.md). It is not a
tutorial for `gc bd` or `gc sling`.

## Containment is every record the pour created

Clearing delivery on the bead you can see is not containment. The pour
creates a tree — every workflow root and all of their descendants — and
each record in it is separately deliverable.

Every delivery channel also comes as a **live/deferred pair**: the live
key is what the offer reads now, and its `gc.deferred_*` twin is
*withheld* delivery that activation later promotes **into** the live key
(`internal/molecule/graph_apply.go:320-329` defers;
`cmd/gc/convergence_store.go:213-240` and
`internal/molecule/molecule.go:1399-1406` promote). Clear only the live
key and the record re-delivers itself the moment it activates. Three
channels, five keys to clear:

| Channel | Live key | Deferred twin |
|---|---|---|
| Pool routing — the minimum pair, on every poured record | `gc.routed_to` | `gc.deferred_routed_to` |
| Execution routing | `gc.execution_routed_to` | `gc.deferred_execution_routed_to` |
| Named-session assignee | `assignee` (a column, not metadata) | `gc.deferred_assignee` |

Only the pool-routing pair is stamped on every record; the other two
appear just on nodes the recipe routes for execution or pins to a named
session (`deferGraphNodeRouting`, `graph_apply.go:320-329`, defers an
assignee only when the node has one). Clear all five regardless — a key
that was never set costs one no-op write, whereas guessing which nodes
are singletons costs a containment failure.

The live `assignee` is the one entry the script deliberately **reports
instead of clearing**: once it is stamped, delivery has already happened
and clearing it recalls nothing (see [What containment cannot
undo](#what-containment-cannot-undo)). Its deferred twin is the opposite
case — `gc.deferred_assignee` has *not* delivered yet, so clearing it
genuinely holds the record. Leave it behind and activation promotes it
straight into `assignee`, handing the work to a named session after you
believed the record was contained.

## The containment script

Run the block below as a script rather than pasting it into a live shell
— the guards `exit` instead of continuing on a root that never resolved.

```bash
# 0. "Live" is every NON-CLOSED status, not just open/in_progress. This
#    recipe exists precisely because you are racing an active dispatch,
#    so a record is in scope unless it is terminal. `hooked` and
#    `blocked` are bd's "wip" category and `pinned` its "frozen" one
#    (internal/beads/native_dolt_store.go:125-130), and a graph node in
#    `hooked` is exactly as live as one in `in_progress`
#    (cmd/gc/cmd_graph.go:482). Filtering to `open,in_progress` silently
#    drops a hooked root or step from BOTH the clear and the verify —
#    and a verify that never looked at a record reports it as contained.
LIVE=open,in_progress,hooked,blocked,deferred,pinned

# 1. Resolve the workflow root(s) the pour created for this bead. Under
#    the current convoy-first attach there is no pointer *pair* to
#    follow: the bead carries no workflow_id and the root no
#    gc.source_bead_id (both are written only when the pour carries a
#    source bead — internal/sling/sling_core.go:741-755). The durable
#    link is the synthetic one-item input convoy that `tracks` the
#    bead (internal/graphv2/invocation.go:415-446, whose TrackItem
#    adds convoy --tracks--> bead at internal/convoy/membership.go:36),
#    named on the root as gc.input_convoy_id. The root lookup below is
#    the same two-key match the pour's own test asserts
#    (cmd/gc/cmd_sling_test.go:4481).
#
#    Collect EVERY tracking convoy, never just the first. The pour mints
#    a fresh one unconditionally — CreateSingleItemInputConvoy calls
#    store.Create with no reuse lookup (invocation.go:428) and closes it
#    only on its own failure paths (sling_core.go:494, :531) — so a
#    re-poured bead ends up tracked by one convoy per pour, each naming a
#    different root. Selecting `.[0]` is the same multi-root collapse the
#    note below warns about, one step earlier and harder to see: a root
#    dropped here never reaches the clear in step 2 OR the verify in
#    step 3, so the verify prints nothing and reads as contained.
#
#    The gc.kind=workflow term is exhaustive for this lookup, not a
#    narrowing of it: a gc.kind=wisp root can never carry
#    gc.input_convoy_id, so adding it here would match nothing. The
#    compiler sets the two kinds on mutually exclusive branches —
#    workflow when the recipe is graph.v2, wisp only when it is
#    root-only and NOT graph.v2 (internal/formula/compile.go:351-356) —
#    and the sole writer of gc.input_convoy_id on a poured root,
#    stampGraphV2RootMetadata, runs only on the graph.v2 branch
#    (internal/sling/sling.go:1318-1322, defined at :1520-1534).
#    Root-only wisps are contained elsewhere, by shape:
#      * ATTACHED wisp (`gc sling --on <bead>`): the WORK BEAD is the
#        routed claimable unit and the wisp root is deliberately left
#        unrouted (internal/sling/sling_core.go:569-578); an attached
#        root-only wisp is additionally privatized out of Ready() with
#        its gc.kind stripped (privatizeAttachedRootOnlyWisp,
#        internal/sling/sling.go:1575-1585). Contain it by clearing the
#        five delivery keys on the work bead itself — there is no root
#        tree to walk, so step 1 resolving no root is the CORRECT answer
#        for that shape, not a failed lookup.
#      * STANDALONE wisp launch (`gc sling <formula>`, no --on): the
#        wisp root is the routed record, but there is no work bead to
#        walk from, so this recipe never reaches it. Find it directly
#        (`gc bd list --metadata-field "gc.kind=wisp" --status "$LIVE"`)
#        and clear the same five keys on it.
CONVOYS=$(gc bd dep list <work-bead> --direction=up -t tracks --json \
  | jq -r '.[] | select((.issue_type // .type) == "convoy") | .id')
ROOTS=$(for convoy in $CONVOYS; do
    gc bd list --metadata-field "gc.input_convoy_id=$convoy" \
      --metadata-field "gc.kind=workflow" --status "$LIVE" \
      --json --limit 0 | jq -r '.[].id'
  done)
# Legacy source-workflow roots carry the pointer instead — UNION it in
# rather than consulting it only when the convoy path came back empty. A
# bead can be tracked by a real convoy AND still be running under a
# legacy-shape workflow, and either lookup alone leaves the other root
# routed. Filter it through the same non-closed rule step 0 uses, so a
# long-since-closed legacy root cannot rejoin the set and report itself
# as "not contained" forever.
LEGACY=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.workflow_id // empty')
[ -n "$LEGACY" ] && ROOTS=$(printf '%s\n%s\n' "$ROOTS" \
  "$(gc bd show "$LEGACY" --json \
     | jq -r '.[0] | select((.status // "") != "closed") | .id')")
ROOTS=$(printf '%s\n' "$ROOTS" | awk 'NF' | sort -u)
# Only the UNION being empty means no graph.v2 root exists. For a
# graph.v2 pour that is a lookup failure and nothing below can contain
# anything, so stop; for the wisp shapes noted above it is the expected
# answer, and the containment target is the work bead (attached) or the
# wisp root (standalone) itself.
[ -z "$ROOTS" ] && { echo "STOP: no graph.v2 workflow root resolved — see the wisp note above before concluding nothing needs containing" >&2; exit 1; }
# A re-pour leaves more than one live root. EVERY one of them is a
# separate routed record with its own descendant tree, so all of them
# go into the id set below — never just the first. Collapsing to one
# root here is the failure this note exists to prevent: the extra roots
# stay routed while step 3, verifying only the one you kept, prints
# nothing and reads as "contained".
[ "$(printf '%s\n' "$ROOTS" | wc -l)" -gt 1 ] && echo "NOTE: multiple roots: $ROOTS" >&2

# 2. Build ONE id set — EVERY root plus every descendant of EVERY root
#    — and clear all five delivery keys on each. The roots are in the
#    set because they are the routed records; the descendants because a
#    step re-delivers itself from its deferred keys on activation.
IDS=$( { printf '%s\n' "$ROOTS"
  for root in $ROOTS; do
    gc bd list --metadata-field "gc.root_bead_id=$root" \
      --status "$LIVE" --json --limit 0 | jq -r '.[].id'
  done; } | awk 'NF' | sort -u)
for id in $IDS; do
  gc bd update "$id" \
    --set-metadata gc.routed_to="" \
    --set-metadata gc.deferred_routed_to="" \
    --set-metadata gc.execution_routed_to="" \
    --set-metadata gc.deferred_execution_routed_to="" \
    --set-metadata gc.deferred_assignee=""
done

# 3. Verify that SAME id set — every root included. A descendants-only
#    query cannot prove containment: gc.root_bead_id is stamped on
#    non-root nodes, so it comes back empty while a root itself is
#    still routed or assigned. Check all five delivery keys plus the
#    live assignee, and report a bead you could not read rather than
#    skipping it — only a bead you actually read can be called
#    contained. Verifying a NARROWER set than you cleared is the same
#    bug as clearing a narrower set than exists: both print empty.
#
#    Decide readability in the SHELL, before jq. `gc bd show … | jq …`
#    cannot report an unreadable bead by itself: when the show fails or
#    prints nothing, jq receives no input, emits no row and exits 0 — the
#    unreadable branch inside the filter never runs, and the bead reads as
#    contained precisely because it could not be read. Only a non-empty
#    document reaches jq below; the in-filter branch still covers the
#    valid-JSON `[]` (bead genuinely absent).
#
#    Columns: ID, ASSIGNEE, gc.routed_to, FLAGS. FLAGS names every
#    reason the row printed, and it is what you triage on — the row
#    classes need DIFFERENT actions, and only some of them are fixed by
#    re-running (see "Reading step 3's output" below). Without it a row
#    flagged solely by a key this line does not print (any of the three
#    execution/deferred keys) shows up as all dashes and reads as noise.
for id in $IDS; do
  if ! shown=$(gc bd show "$id" --json 2>/dev/null) \
     || [ -z "$(printf '%s' "$shown" | tr -d '[:space:]')" ]; then
    printf '%s\t?\t?\tUNREADABLE\n' "$id"
    continue
  fi
  printf '%s' "$shown" | jq -r --arg id "$id" '
    def dash: if (. // "") == "" then "-" else . end;
    (if type == "array" and length > 0 then .[0] else {id: $id, unreadable: true} end)
    | . as $b
    | (["gc.routed_to", "gc.deferred_routed_to", "gc.execution_routed_to",
        "gc.deferred_execution_routed_to", "gc.deferred_assignee"]
       | map(select(($b.metadata[.] // "") != ""))) as $routing
    | (if ($b.assignee // "") != "" then ["assignee"] else [] end) as $claimed
    | (if ($b.unreadable // false) then ["UNREADABLE"] else [] end) as $unread
    | ($unread + $claimed + $routing) as $flags
    | select(($flags | length) > 0)
    | "\($b.id)\t\($b.assignee | dash)\t\($b.metadata["gc.routed_to"] | dash)\t\($flags | join(","))"' \
    || printf '%s\t?\t?\tUNREADABLE\n' "$id"
done
# That trailing `||` covers the third failure mode: output that arrives
# but jq cannot parse (a raw control character in a bead's notes is the
# usual cause). An UNREADABLE row is a false alarm you re-run; a silently
# skipped bead is a containment claim you never earned.
# Empty output = contained. Any row is still routed, still carries
# withheld delivery, is already claimed (assignee), or is unreadable —
# none of those is containment, and FLAGS says which, because the
# classes need different actions.
```

## Reading step 3's output

Step 3 is not optional: the read in step 2 and the writes that follow are
not atomic, so a worker can claim between them. But "re-run until it
comes back empty" is a valid stop condition only for the rows a re-run
can actually change, and one class is not among them. Triage on the
FLAGS column:

- **Routing/deferred rows** (`gc.routed_to`, `gc.deferred_routed_to`,
  `gc.execution_routed_to`, `gc.deferred_execution_routed_to`,
  `gc.deferred_assignee`). Step 2 clears exactly these keys, so a row
  still carrying one means the record re-acquired delivery after you
  cleared it — a write raced the non-atomic read, or an activation
  promoted a deferred key. **Re-run steps 2 and 3.** These are the rows
  the loop is for, and for them "empty" is the right target. Re-run
  step 1 too if a re-pour could have added a root since.
- **`assignee` rows.** Delivery has already happened, and step 2
  deliberately does *not* clear a live `assignee` — clearing it recalls
  nothing (see [What containment cannot
  undo](#what-containment-cannot-undo)), so the script leaves it visible
  rather than erasing the evidence. **Re-running will never clear
  these**, and the loop does not converge while one is present: waiting
  for empty output here is waiting forever. Contain them at the worker
  instead — peek the session named in the ASSIGNEE column (`gc session
  peek <session>`) to see what it is doing, stop it there, and write the
  hold into the work bead's `notes`, which is what a worker actually
  reads. A row flagged with **both** an assignee and a routing key still
  needs the re-run for its routing half.
- **`UNREADABLE` rows.** These prove nothing either way. Re-run them;
  if one stays unreadable, read that bead directly — a raw control
  character in `notes` is the usual cause, and
  `gc bd show <id> --json | tr -d '\001-\010\013\014\016-\037' | jq .`
  gets past it.

You are done when every remaining row is an `assignee` row you have
handled at the worker — not necessarily when the output is empty, which
for an already-claimed record it never becomes.

## Never close these beads to contain them

A force-closed step leaves an orphaned husk that re-runs as duplicate
work. Clear the routing and leave the records open.

## What containment cannot undo

Once the `assignee` is stamped, delivery has happened; clearing the
routing fields only affects the next offer. De-routing does not recall
work a worker already holds — that is the routing model's "metadata is
not enforcement", one step later in the lifecycle
([gascity-routing-model.md](gascity-routing-model.md#metadata-is-not-enforcement)).

For those records the durable mitigation is the work bead's `notes`: a
"do not start until `<bead>` lands" line is what a worker actually reads,
precisely because the dep graph is not consulted on the records the pour
delivers.
