---
name: One board, two renderers — parity evidence and cold-run benchmark
description: How the CLI board was verified equal to gc-helm.sh on live data, what the two cost, and the divergences that were chosen rather than missed. Read before changing either board's derivation or retiring the bash one.
---

# tk-134d7 — parity evidence and benchmark

Record of the verification behind "the CLI is a second VIEW of the dashboard's
board, not a second implementation of it". The change itself is in
`services/helm/`; this file is the evidence and the judgement calls, which do
not belong in a bead comment.

Measured 2026-08-22 on the `loomington` city — 8 CPU, 30G RAM, 5 bead stores
(`lx` HQ, `tk`, `sl`, `gc`, `su`), 55 anchors.

## What was compared

`gc-helm.sh --json --limit=0 --refresh` against
`helm-svc board --json --limit=0`, same city, minutes apart.

| | result |
|---|---|
| anchor sets | **identical** — 55 ids, empty diff both directions |
| per-row field sets | **identical** — 34 keys |
| field VALUES | **all 34 equal on all 55 rows** |

The value comparison sorted both boards by id and compared key by key, counting
mismatches per field. The only field that ever differed was `open_heads`, and
only in ORDER — see below.

Reproduce:

```bash
gc-helm.sh --json --limit=0 --refresh > sh.json
helm-svc board --json --limit=0       > go.json
diff <(jq -r '.[].id' sh.json | sort) <(jq -r '.[].id' go.json | sort)
jq -n --slurpfile a <(jq -S 'sort_by(.id)' sh.json) --slurpfile b <(jq -S 'sort_by(.id)' go.json) '
  def norm: .open_heads |= sort | .dead_owner_heads |= sort
          | .in_flight_heads |= sort | .cross_rig_refs |= sort;
  ($a[0]|map(norm)) as $sh | ($b[0]|map(norm)) as $go
  | reduce range(0; ($sh|length)) as $i ({};
      . as $acc | ($sh[$i]) as $s | ($go[$i]) as $g
      | reduce ($s|keys_unsorted[]) as $k ($acc;
          if ($s[$k]) == ($g[$k]) then . else .[$k] = ((.[$k] // 0) + 1) end))'
```

This is a point-in-time check, not a standing one — it depends on live session
state and cannot be deterministic. What guards the boards afterwards is
`cmd/helm-svc/contract_parity_test.go`, which parses the key set out of
gc-helm.sh's jq object literal and compares it to what the CLI serializes. That
guard was mutation-checked in both directions (a field added to the script; a
`json:` tag renamed on the Go side); each mutation failed the test with a
message naming the side that was behind, and the restore went green.

## Benchmark

Three runs each, `--limit=0` (uncapped) so neither board is doing less work.

| | run 1 | run 2 | run 3 |
|---|---|---|---|
| `gc-helm.sh` cold (`--refresh`) | 26.58 s | 22.16 s | 19.94 s |
| `gc-helm.sh` warm (45s file cache) | 1.75 s | 1.82 s | 1.77 s |
| `helm-svc board` (no cache — always cold) | 3.27 s | 2.76 s | 2.73 s |

**Verdict: yes, comfortably.** The bar in the bead was ~12s. Cold-to-cold the Go
path is ~7.8x faster (≈22.9s → ≈2.9s), and it has no cache to miss: the bash
board pays its 20-27s on every glance more than 45s apart, where this pays ~2.9s
on every glance, always.

Where the difference comes from: the bash board spends one `gc bd` subprocess
per rig per anchor kind plus one `gc bd show` per convoy, each paying process
startup and a fresh Dolt connection. The Go path reads beads in-process through
the beads library and shells out only for what no bead carries — one
`gc session list`, one `gc convoy list`, and one `gc convoy status` per LIVE
workflow root (the liveness filter runs first, so the city's husk roots cost
nothing).

**No cache was added, deliberately.** It would buy about a second against the
bash board's warm path and re-introduce a staleness surface, which is the thing
this epic exists to reduce (`tk-y3tks`, `tk-5nm0p`).

## Divergences chosen, not missed

Three places where the Go board does NOT do what the bash board does. Each is a
decision, and each is commented at its site.

1. **Head-list ordering.** `open_heads`, `in_flight_heads` and `dead_owner_heads`
   are emitted by gc-helm.sh in child-enumeration order — whatever order the
   store returned the dependency rows in — so the bash board's own output for
   these is not stable run to run. The Go board sorts them. Parity on these three
   fields is therefore by SET; every other field matches element for element.
   (This is the entire `open_heads` mismatch in the comparison above: same
   members, different sequence, on 8 of 55 rows.)

2. **The empty cross-rig prefix set.** gc-helm.sh builds its scan regex as
   `"(?:" + ($others|join("|")) + ")-[a-z0-9]{3,8}"`. In a single-rig city
   `$others` is empty, the alternation degenerates to `(?:)`, and the pattern
   matches a bare `-abc` — so every hyphenated word in an anchor's prose becomes
   a phantom cross-rig reference and inflates the weight lane. The Go
   `crossRigRefs` returns no refs for an empty prefix set. This did not show in
   the comparison because loomington has five prefixes.

3. **The weight lane cap.** `rankScore` caps weight at 999 so it cannot bleed
   into the severity lane; gc-helm.sh does not cap. Unreachable in practice (it
   needs ~1000 children) and pre-existing Go behaviour, kept.

## Two things this fixed that were not asked for

Both surfaced while proving parity, and both were gaps in the DASHBOARD:

- **The HQ bead store was never gathered.** `gc rig list` reports the city root
  itself as a rig (`"hq": true`, prefix `lx`) and gc-helm.sh gathers it, but
  `BeadsSource.rigs()` scanned only `<city>/rigs/*/.beads`. Three
  `gc.routed_to=human` beads — city-scope work provably waiting on the operator,
  which is the highest-value row this board has — were invisible on the
  dashboard and present on the bash board. This is the whole 55-vs-52 row gap in
  the first comparison run.

- **The false-stranded defect, Go side.** `tk-fkeft` fixed it in `gc-helm.sh`
  only. Because a slung bead never leaves `status=open` (the in-flight state
  lives on the workflow), the Go board read a polecat mid-implementation as
  "stranded — assign or visit". The in-flight join fixes it here too, and it was
  confirmed live: epic `tk-9tbbk` reported `in_flight: 1` with
  `in_flight_heads: ["tk-134d7"]` — this bead's own workflow — and banded NORMAL
  rather than HIGH.

## Scope note for whoever picks up tk-x55wt

`tk-x55wt` ("a tile tells you nothing about its subject — NEEDS is a
deterministic phrase") is partly landed here, unavoidably: field parity means
the takeaway-driven NEEDS sentence, because that is what gc-helm.sh's `needs`
field contains. What landed is the DATA half — an anchor carrying `gc.takeaway`
spends it as its NEEDS, on both renderers. What remains is that bead's actual
subject: the web tile's presentation, and the numeric columns that carry no
meaning to a reader.
