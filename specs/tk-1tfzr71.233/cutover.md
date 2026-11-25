---
name: Cutover of the placement queue to hold:po (tk-1tfzr71.233)
description: The preconditions and exact commands that move the city's live placement queue from hold:mayor to hold:po once this branch has landed, how to tell the move has finished, the writers that can still write hold:mayor and how to find their beads, and when the pack's reading of hold:mayor can go. Read it before running the cutover, or before removing hold:mayor from the pack.
---

# Cutover of the placement queue to hold:po

The cutover moves each live bead the placement queue holds on `hold:mayor` onto
`hold:po`, in every store of the city, with `gctk bead move-placement-hold`.
Nothing about it is urgent: until it runs, every reader of the queue reads
`hold:mayor` beside `hold:po`, and the city's `gc` holds a bead on either, so
no bead leaves the po's queue, is served to a pool or reaches the mayor in the
meantime. It runs once the three preconditions hold, and runs again whenever a
writer below has written `hold:mayor` since.

## Preconditions

1. **The runtime holds `hold:po`.** The `gc` binaries agents run and the
   running supervisor are built from a fork commit that carries gc-uyshxy.
   This check, from the fork change's own summary, prints nothing when all
   three carry it:

   ```bash
   G=$(gc rig list --json | jq -r '.rigs[] | select(.name == "gascity") | .path')
   git -C "$G" fetch -q origin
   fix=$(git -C "$G" log origin/main --format=%H -1 --grep='(gc-uyshxy)')
   sup=$(curl -fsS "$(gc supervisor status --json | jq -r .api_url)/health" | jq -r .build_id | sed 's/-dirty$//')
   git -C "$G" merge-base --is-ancestor "$fix" "$sup" || echo "supervisor $sup lacks the fix"
   for b in "$HOME/.local/bin/gc" "$(command -v gc)"; do
     c=$("$b" version --json | jq -r .commit | sed 's/-dirty$//')
     git -C "$G" merge-base --is-ancestor "$fix" "$c" || echo "$b at $c lacks the fix"
   done
   ```

2. **The pack is live.** The pack checkout the city loads holds this branch's
   merge, and the deployed `gctk` has the verb:

   ```bash
   git -C "$(gc gc-toolkit scripts-dir)/../.." merge-base --is-ancestor <merge commit> HEAD && echo "pack live"
   GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
   "$GCTK" bead --help | grep -q '^  move-placement-hold ' && echo "gctk has the verb"
   ```

   `reconcile-rig-checkouts` fast-forwards the checkout every 15 minutes, and
   the `gctk-build` order rebuilds `gctk` once its sources move.

3. **No placement is half-made.** A bead a sitting is placing right now could
   take `hold:po` back in the window between the move's read and its write,
   which is why the move reads each bead again just before its write. Run it
   while no po sitting is placing, which `gc session list` shows. A hold
   another writer adds meanwhile stays on, because the move's write removes
   `hold:mayor` by name.

## The commands

```bash
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
"$GCTK" bead move-placement-hold --dry-run   # the inventory: writes nothing
"$GCTK" bead move-placement-hold             # the move
"$GCTK" bead move-placement-hold             # moves nothing and exits 0 once finished
```

Each run prints one line for each store, the HQ's and each rig's, suspended or
not: what it moved, or with `--dry-run` would move, what is on `hold:po`
already, and what it left. Its exit decides:

- **0**: every store read and no live bead is left on `hold:mayor`.
- **1**: a bead is left, on its own line with why and the write a person makes.
  A bead with a route or an assignee is placed with `gctk bead place`, or its
  route or assignee cleared, by a person's call. A route of `mayor`, or a
  binding's `mayor` with no rig, has the shape Gas City's removed doctor repair
  wrote from the label, but a writer can choose it too. So read who set it
  first, with the `gc bd history <bead> --events` its line names, and clear it
  without placing the bead only when `gc doctor --fix` set it. A bead that
  also carries another hold, or `hold:cleared`, or `hold:mayor` in another
  case, takes the one `gc bd update --add-label hold:po --remove-label ...`
  the line names, which keeps it held and leaves the other label on. Make each
  write, then run the move again.
- **3**: a store did not read, and the move has not finished. Run it again once
  the store answers.

The move never writes a closed bead: 287 closed records carried `hold:mayor`
on 2026-11-25, and they keep it.

## Telling it has finished

- The move exits 0.
- The census of every live hold label in each store shows no `hold:mayor`:

  ```bash
  gc rig list --json | jq -r '.rigs[] | "\(.name)\t\(.path)"' | while IFS=$'\t' read -r n p; do
    printf '%s ' "$n"; gc bd --db "$p/.beads" list --json --limit 0 --include-ephemeral --include-gates --include-infra --include-templates \
      | jq -c '[.[] | .labels // [] | .[] | select(ascii_downcase | startswith("hold:"))] | group_by(.) | map({(.[0]): length}) | add // {}'
  done
  ```

- Each rig's queue holds the same beads before and after: the po's queue read
  (`agents/po/prompt.template.md`, "Reads") lists the same ids, now on
  `hold:po`.

## Writers that can still write hold:mayor

- **The witness's `bug-file` block** (`formulas/mol-witness-patrol.toml`)
  files bugs with `--labels hold:mayor`. The formula is retired by
  tk-1tfzr71.174, which carries the note that its replacement writes
  `hold:po`.
- **A run poured before the merge** carries the step text it was poured with.
  The feedback distiller's filing step wrote `-l hold:mayor` until this branch,
  and its open runs show with
  `gc bd list --metadata-field gc.step_ref=mol-feedback-distiller.file-and-dispatch --status open,in_progress --json`.
- **A session started before the pack went live** keeps its prompt, such as a
  po sitting whose Hold lever still reads `hold=mayor`.
- **An open PR** that adds a `hold:mayor` writer merges main before it lands,
  and its writes then follow `hold:po`.

Each writes a bead the queue still reads and Gas City still holds, so a later
run of the move picks it up. A bead the move finds after the cutover names its
writer: `gc bd show <bead>` gives who filed it, and its newest
`State change: hold → mayor` event bead (`gc bd list --parent <bead> --type event --all`)
who held it.

## When the pack stops reading hold:mayor

The pack reads `hold:mayor` as the placement hold only while beads can carry it.
The bead that removes that reading, and this verb with it, waits on the
cutover and on tk-1tfzr71.174, and starts once both land. Its first act is the
move's dry run: exit 0 with nothing moved means no live bead is left to strand.
