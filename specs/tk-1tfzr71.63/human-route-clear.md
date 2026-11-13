---
name: The human route's clear — census, rule and procedure
description: The one-off migration of tk-1tfzr71.63, unit 5 of the dispatch effort (specs/tk-1tfzr71.54/design.md, call 1). It gives the rule for which open beads have gc.routed_to=human cleared, the commands that count, clear and count again in every store, what the run of 2026-11-09 found, cleared and moved on the board, and what the re-run after the effort lands must check. Read it to run the procedure again, or to check what this run did.
---

# The human route's clear

The dispatch effort retires the `human` route: a person's wait is the human gate
alone (call 1 of [the design](../tk-1tfzr71.54/design.md)). Units 3 and 4 stop
the pack writing the route, and this procedure takes it off the beads that
still carry it. It ships no script. The commands below are the procedure, and
the follow-up tk-1tfzr71.65 runs them again once the effort is on main.

## The rule

A bead is cleared when all of these hold:

- it is in any store the rig map lists, the city store and a suspended rig's
  included;
- its status is anything but closed;
- its `gc.routed_to` is exactly `human`;
- it has no assignee, no `merge_result` and no branch (`branch` or
  `gc.work_branch`).

A clear is one update that writes `gc.routed_to=""`, the pack's form of a route
clear, and appends one note saying why. It files no gate in the route's place.
A gate on an epic would hold every open bead under it, because bd reports each
member of a gated epic with no blocker of its own as blocked by the epic. A gate
filed from a ruled bead's headline would ask again what a sitting answered.

A bead that fails the last condition is not cleared, and the run puts it to a
person. Each case has a reader that acts on what the clear leaves:

- An assigned bead has a holder, and the holder's run may still read its route.
- An anchor in a detached state loses the route at pr-facts.sh's next plain
  self-transition, which the effort's lifecycle makes clear a `human` route.
  An anchor in a human state keeps its route, and its park is the human gate
  its parking filed. Clearing the route of one with no open gate leaves its
  wait with no record.
- A bead with a branch, once unrouted, is a candidate for Gas City's
  detached-orphan lane (`isDetachedHandoffOrphanCandidate`,
  `cmd/gc/pool_detached_orphan_sweep.go`), which restores a pool route from a
  session pin. pr-facts.sh's stranded-rework rescue can route a rework child
  that carries one.

## The procedure

Every read and write below goes through `gc bd`. A read that fails, or that
answers anything but a JSON array, means that store was not counted, so the run
stops there rather than reading it as none. A suspended rig's store is on the
city's one managed Dolt server, and on this run reading it started no other
server.

### 1. Count

```bash
SCRIPTS=$(gc gc-toolkit scripts-dir)
OUT="$HOME/.cache/<the bead running this>/census"; mkdir -p "$OUT"
"$SCRIPTS/rig-map.sh" > "$OUT/rig-map.json" || exit 1
CITY=$(jq -r '.rigs[] | select(.hq == true) | .path' "$OUT/rig-map.json")
FLAGS=(list --all --include-gates --include-ephemeral --include-infra
       --metadata-field gc.routed_to=human --json --limit 0)
count() { # <tag>: before or after
  local tag=$1 rig f
  for rig in $(jq -r '.rigs[] | select(.hq != true) | .name' "$OUT/rig-map.json"); do
    gc bd --rig "$rig" "${FLAGS[@]}" > "$OUT/$tag.$rig.json" || { echo "$rig: not counted"; return 1; }
  done
  (cd "$CITY" && env -u GC_RIG -u GC_RIG_ROOT -u BEADS_DIR gc bd "${FLAGS[@]}") > "$OUT/$tag.city.json" \
    || { echo "city: not counted"; return 1; }
  for f in "$OUT/$tag".*.json; do
    jq -e 'type == "array"' "$f" >/dev/null || { echo "$f: not counted"; return 1; }
    printf '%s %s\n' "$(basename "$f" .json)" "$(jq '[.[] | select(.status != "closed")] | length' "$f")"
  done
}
count before
```

The listing returns closed beads as well, because `--all` is the one scope that
leaves no live status out, and `jq` keeps the rest. This prints the clear's
input, one `<store> TAB <id>` row per live bead, with `city` for the city store:

```bash
for f in "$OUT"/before.*.json; do
  store=$(basename "$f" .json); store=${store#before.}
  jq -r --arg s "$store" '.[] | select(.status != "closed") | [$s, .id] | @tsv' "$f"
done > "$OUT/input.tsv"
```

### 2. Clear

Each bead is read again just before its clear, and the clear is guarded on an
empty assignee, so a bead that changed since the count is skipped and reported.

```bash
NOTE='gc.routed_to=human cleared by <the bead running this>. The human route retires, and a wait on a person is the human gate alone (call 1 of specs/tk-1tfzr71.54/design.md). No gate is filed in its place.'
while IFS=$'\t' read -r store id; do
  if [ "$store" = city ]; then on=(); else on=(--rig "$store"); fi
  row=$(gc bd "${on[@]}" show "$id" --json | jq -c '.[0] // empty')
  why=$(printf '%s' "${row:-null}" | jq -r '
    if . == null then "unread"
    elif .status == "closed" then "closed"
    elif (.metadata["gc.routed_to"] // "") != "human" then "route:" + (.metadata["gc.routed_to"] // "")
    elif (.assignee // "") != "" then "assigned:" + .assignee
    elif (.metadata.merge_result // "") != "" then "anchor:" + .metadata.merge_result
    elif ((.metadata.branch // "") != "") or ((.metadata["gc.work_branch"] // "") != "") then "branch"
    else "" end')
  if [ -n "$why" ]; then printf '%s\t%s\tskipped:%s\n' "$store" "$id" "$why"; continue; fi
  if gc bd "${on[@]}" update "$id" --if-assignee '' --set-metadata gc.routed_to="" \
       --append-notes "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $NOTE" >/dev/null; then
    printf '%s\t%s\tcleared\n' "$store" "$id"
  else
    printf '%s\t%s\tfailed:%s\n' "$store" "$id" "$?"
  fi
done < "$OUT/input.tsv" | tee "$OUT/clear.log"
```

`gc bd update` routes a bead id to its own store, so a city bead's clear needs
no flag. Each clear's exit is its record. A `skipped` row is a bead the rule
does not clear: ask a person about it with a human gate on that bead, and leave
its route.

```bash
"$SCRIPTS/human-gate.sh" --subject <id> --key human-route-clear \
  --message "<id> still carries gc.routed_to=human and is <what the skip names>, so its route was not cleared. <What reads it once it is cleared.> Clear the route, or say what should hold the bead instead."
```

### 3. Count again

Run `count after`. It reads none in every store when the run is done.

## The run of 2026-11-09

The run read, cleared and read again between 08:12Z and 08:15Z. The count read
38 live beads, the same 38 the design counted on 2026-11-08.

| Store | Live beads on the route |
|---|---|
| gc-toolkit | 27: 12 tasks, 6 bugs, 5 decisions and 4 epics |
| `<rig>` | 8: 6 tasks, one of them deferred, and 2 epics |
| `<rig>` | 2 tasks |
| `<rig>` | 1 epic |
| two other rig stores, and the city store | none |

None was assigned, an anchor, on a branch or pinned to a session, so the rule
cleared all 38, and every update exited 0. The count at 2026-11-09T08:14:27Z
read none in all seven stores. The ids cleared in gc-toolkit's store are
tk-1tfzr71, tk-qjdt90g, tk-8gradm4.1, tk-38ca3g, tk-ssm8qns.5, tk-p28xr6g,
tk-8tw7f73, tk-ytf539e, tk-e8t8pen, tk-ccvo9d5, tk-ssm8qns, tk-6el2crr,
tk-w4ppjrn, tk-sydobsl, tk-9013wju, tk-7uluoii, tk-luzd9z, tk-ikpyzn,
tk-georjc, tk-ez2kgo, tk-7rea7j, tk-r05k0v, tk-f8ifu1, tk-ajov59, tk-hok6w,
tk-idodu4v and tk-471k364. The other stores' ids are in tk-1tfzr71.63's notes.

The helm board was read before the clear, at 08:12:12Z, and after it, at
08:15:10Z. No row outside the 38 changed its section or whether it is owed.

- 12 rows moved from cleanup, where they read "ruled — close or extend", into
  the gate section as disposition due, owed, reading "blocker landed — dispose
  or resume": tk-7uluoii, tk-8gradm4.1, tk-8tw7f73, tk-ccvo9d5, tk-e8t8pen,
  tk-luzd9z, tk-p28xr6g, tk-sydobsl and tk-ytf539e, and 3 in another rig's
  store. The design counted 16 on 2026-11-08.
- 5 rows stay in cleanup, not owed, and show their own headline in place of
  "ruled — close or extend": tk-38ca3g, tk-7rea7j, tk-georjc and tk-r05k0v, and
  1 in another rig's store. The board makes a row disposition due only when it
  records a wait on work that has landed, and these record none it counts:
  tk-38ca3g waits on nothing, and the others wait on closed human gates, on
  beads in another store, or under an ancestor that still holds them.
- tk-ssm8qns.5 moved from the active section to cleanup, reading "queued
  behind" the bead it still waits on. It is owed neither before nor after.
- The 9 rows an open human gate holds stay in the gate section, each owed or
  not as before, and the 5 decisions and the 5 epics with no gate keep their
  rows.

## What the re-run after the effort lands checks

tk-1tfzr71.65 waits on the effort's landing bead and runs the procedure again
once main carries it, because main's writers can park a bead on the route until
then. It checks:

1. That no writer of the route is left: in the rig checkout at the merge, no
   pack file writes `gc.routed_to=human`, passes `--route human`, or declares a
   `park_route`. A writer that is left brings the route back, so it is a bead
   to file, not a reason to clear again.
2. The count in every store, as in step 1.
3. Each bead it finds against the rule, and against this run's ids, here and in
   tk-1tfzr71.63's notes. A bead this run did not clear, or one it cleared that
   carries the route again, was parked after 2026-11-09T08:14:27Z by one of
   main's writers (the design's section 2). Lifecycle's human states, through
   the refinery patrol and pr-facts.sh's red-check parks, file a human gate
   beside the route. work-setup.sh's stop with no molecule, the keeper's sync
   and the heartbeat fragment's park file none. Clear such a bead when an open
   human gate holds it. When none does, the route is the only record of its
   ask: file that ask as a human gate on the bead with `human-gate.sh`, in the
   words of its headline, then clear the route. An epic takes no gate, because
   a gate on it holds every member, so ask a person about it as for a skipped
   bead.
4. That `count after` reads none in every store, and the ids it cleared, with
   gc-toolkit's in its own record and another rig's in its bead's notes.
