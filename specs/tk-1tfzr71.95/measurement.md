---
name: Built-once target — the re-measure at 25cda8ace
description: The derivations behind docs/built-once-target.md at its baseline, main 25cda8ace, where stage 2 of the deletion schedule completed. It holds the baseline table, what moved since the d983f9f50 baseline, the schedule's sizes and the counts behind what has no place in the built-once shape. Read it to check or re-derive a number the doc states.
---

# The re-measure at 25cda8ace

Stage 2 of the deletion schedule, the removals the native-gates convoy's
landing released, completed when tk-kvdomjb landed on main as 25cda8ace (#1482,
2026-11-12). That commit was main's head when this was measured. The doc's rule
is that a change completing a stage re-measures the baseline, and tk-1tfzr71.95
carried it. Every number here was taken at 25cda8ace unless its row names
another commit, and where a command names `$C`, it is 25cda8ace.
`tools/measure.sh` produced the tables, and each other count comes from the
command shown with it, run from the repository root.

The measurements before this one are in
[the first record](../tk-11l1ejh/measurement.md): its sections 1 to 6 at
b09345315, and its section 7 at d983f9f50, the baseline this one replaces.
[What this record does not take again](#what-this-record-does-not-take-again)
names the doc's numbers that still come from there.

## The baseline table

```
$ tools/measure.sh 25cda8ace
lines at 25cda8ace

kind          lines
code          99114
flow          13584
text           9476
test         161721
docs          18906
tooling       15980
record        87336
generated      6949

subsystem      code     flow     text     test    total
board         20984       57        0    26428    47469
engagement    13639      426     2709    24983    41757
merge         13756     1478      197    25230    40661
shared        10346      216        0    23978    34540
patrol         6957     2145      410    16082    25594
review         7619     1924     2161    11774    23478
gctk          11258      264        0    10565    22087
doctor         7491       25        0     9297    16813
work           5049     1320       17    10381    16767
keeper          747     2072     1013     1081     4913
feedback       1140      883      391     1922     4336
config          128     2774        0        0     2902
doctrine          0        0     2578        0     2578
```

Runtime is code, flow and text: 122,174 lines. Pack weight adds tests: 283,895.
The doc's "human engagement" is the `engagement` row, the name component-model
§4 gives that workflow. The doc's rows, before it rounds them to 0.1k:

| Row | Runtime | Tests |
|---|---:|---:|
| work | 6,386 | 10,381 |
| review | 11,704 | 11,774 |
| merge | 15,431 | 25,230 |
| human engagement | 16,774 | 24,983 |
| board | 21,041 | 26,428 |
| patrol | 9,512 | 16,082 |
| doctor | 7,516 | 9,297 |
| shared glue | 10,562 | 23,978 |
| gctk | 11,522 | 10,565 |
| feedback | 2,414 | 1,922 |
| config | 2,902 | 0 |
| doctrine | 2,578 | 0 |
| keeper sub-pack | 3,832 | 1,081 |
| **total** | **122,174** | **161,721** |

Beside the pack are docs (18,906 lines), tooling (15,980), the record (87,336)
and generated files (6,949).

Component-model §4 has a row for 114 of the 140 runtime scripts under
`assets/scripts/`, which are the paths there that the tool counts as code. The
other 26, 6,381 lines, are placed by the `post` rules in `measure.sh`. The
largest are `bd-lib.sh` (1,025), `bead-context.sh` (747), `orphan-dispose.sh`
(606), `review-checks.sh` (438) and `self-review-check.sh` (404).

## What moved since d983f9f50

```
$ tools/measure.sh d983f9f50 25cda8ace
net lines from d983f9f50 to 25cda8ace

kind          lines
code           6504
flow          -1072
text           1932
test          10596
docs           2140
tooling          99
record        15047
generated     -1045

subsystem      code     flow     text     test    total
gctk           4605      264        0     5724    10593
board          3503        2        0     5466     8971
engagement     2317      175      808     4411     7711
review          171     -104      278      667     1012
doctrine          0        0      778        0      778
keeper           -6        4       -2        9        5
feedback         -2      -19        1       14       -6
config            0      -90        0        0      -90
patrol         -274        9        2        4     -259
doctor         -135       -1        0     -139     -275
visit          -412      -29        0     -697    -1138
merge         -1001        4       67    -1672    -2602
work            566    -1296        0    -2329    -3059
shared        -2828        9        0     -862    -3681
```

Pack weight rose by 17,960 lines, or 6.8%: runtime +7,364 and tests +10,596.
The `visit` row holds the paths deleted since d983f9f50, which keep the name §4
gave their workflow there. The paths still present take §4's name at
25cda8ace, `engagement`. The doc's human engagement row rose by the two rows'
sum, 6,573, from 35,184 to 41,757. gctk grew most, by 10,593 lines, and 5,357 of
them came with 7ed46e378, which added gctk's bead holds and moved the pack's
hold reads onto them.

The tool at 25cda8ace, run at d983f9f50, prints the table of the first record's
[section 7](../tk-11l1ejh/measurement.md#7-the-re-measure-at-d983f9f50) with
one difference. It splits that table's `visit` row (35,184) into `visit` 23,857,
the paths §4 placed there, and `engagement` 11,327, the paths the tool's own
rules place, which name the workflow engagement since 07777bb4b. Each kind and
every other row is as section 7 printed it.

Stage 2's landings, net lines by `measure.sh <commit>^ <commit>`, in the order
they reached main. A bead belongs to stage 2 when the doc's stage 2 table named
it at any first-parent commit from d983f9f50 to 25cda8ace.

| Commit | Bead | Runtime | Tests | Pack |
|---|---|---:|---:|---:|
| f78ca1f02 | tk-c8724xi | −100 | −36 | −136 |
| 86b4720ed | tk-1tfzr71.33 | −1,303 | −845 | −2,148 |
| 6dfa90898 | tk-1tfzr71.10 | +53 | +229 | +282 |
| 172b1d7bf | tk-1tfzr71.12 | +396 | −1,473 | −1,077 |
| 3e478cff8 | tk-1tfzr71.43 | +52 | +150 | +202 |
| 4ce7bd5da | tk-1tfzr71.45 | −7 | −2 | −9 |
| 6cb81633d | tk-1tfzr71.42 | −636 | −812 | −1,448 |
| 053c82e97 | tk-1tfzr71.39 | −1,100 | −1,640 | −2,740 |
| 25cda8ace | tk-kvdomjb | −142 | −305 | −447 |

Together they net −7,521: runtime −2,787 and tests −4,734. The other 91
first-parent commits since d983f9f50 net +25,481: runtime +10,151 and tests
+15,330. Of all 100, 70 grew the pack, 19 shrank it and 11 left it as it was.
The five that grew it most:

| Commit | Change | Runtime | Tests | Pack |
|---|---|---:|---:|---:|
| 7ed46e378 | feat(gctk): add gctk bead holds and move the pack's hold reads onto it | +2,535 | +3,685 | +6,220 |
| 545b60593 | feat(board): start and return to conversations from one terminal form | +2,453 | +3,574 | +6,027 |
| e94d68a65 | feat(engagement): hold new work on Gas City's hold, worked by the po | +1,231 | +1,106 | +2,337 |
| 827c06f1e | feat: name and offer every human gate that holds a PR | +584 | +1,274 | +1,858 |
| 7c5676b65 | feat(board): lay the board out as Needs you and the Work queue | +461 | +1,099 | +1,560 |

## The schedule's sizes

Each row of `tools/deletion-plan.tsv` is a whole file a bead retires, and a
bead's size is those files' lines at 25cda8ace:

```
git diff --numstat "$(git hash-object -t tree /dev/null)" $C | awk -F'\t' '
  NR == FNR { if (!/^#/ && NF) bead[$1] = $2; next }
  $3 in bead { n[bead[$3]] += $1; if ($3 ~ /\.test\.sh$|_test\.go$/) t[bead[$3]] += $1 }
  END { for (b in n) print b, n[b], t[b] + 0 }' <(git show $C:tools/deletion-plan.tsv) - | sort
```

| Bead | Lines (of which tests) | At d983f9f50 |
|---|---:|---:|
| tk-1tfzr71.17 | 189 (126) | 189 |
| tk-1tfzr71.18 | 5,838 (3,606) | 5,815 |
| tk-1tfzr71.19 | 7,855 (4,631) | 7,869 |
| tk-1tfzr71.20 | 10,912 (6,120) | 10,920 |
| tk-1tfzr71.21 | 15,411 (8,881) | 15,233 |
| tk-1tfzr71.22 | 10,894 (5,713) | 10,924 |
| tk-1tfzr71.25 | 1,490 (902) | 1,488 |

The last column is the same command over the same rows with d983f9f50 as the
diff's commit. The plan held these beads' rows unchanged between the two
commits, so it gives the size the doc carried at d983f9f50, and each change in a
size is lines that bead's files gained or lost.

These come to 52,589 lines, 588 of them the wrapper lint rules under
`tools/lint-learned.d/`, which are tooling. The doc sets them against the gap
between pack weight and the built-once estimate: 283,895 less 63,500 is
220,395. tk-1tfzr71.16, .23 and .24 have no row, since they rewrite parts of
files.

tk-1tfzr71.20's branch is in flight, as its integration effort's PR (#1488),
so the doc's lanes table gives it the measured net the doc gives a branch in
flight. Read on 2026-11-13 at the branch's head, 893215bd9:

```
$ tools/measure.sh --pr $C 893215bd9
Net lines from the merge base `bf4a299d8`: runtime +5164 and tests +1286.
```

That is +6,450 lines. Of the other members, only tk-1tfzr71.16 has a branch on
origin, its integration branch, which is still the main commit dbe034457, with
a design PR open into it.

## The counts

| Count | Result | Command |
|---|---|---|
| copies of the script-dir loop | 3 in 3 files: the hooks of the `cycle-recycle` and `work-context` overlays, and `pack-self-location.test.sh` | `git grep -c -E 'for c in "\$\{GC_(PACK_DIR\|RIG_ROOT):-\}"' $C -- . ':!specs' ':!generated'` |
| copies of the decline sequence | 2, both in `mol-validate.toml`; the one call in `mol-review.toml` is its failed gather's own cancel | `git grep -c -F 'run-cancel.sh" --step' $C -- formulas agents template-fragments packs` |
| comment share, runtime shell scripts under `assets/scripts/` | 20,687 of 58,249 lines (36%), shebangs excluded | lines matching `^[[:space:]]*#`, over the code-kind paths there less `demo-screenshot.mjs` |
| comment share, Go outside tests | 7,991 of 27,769 (29%) | lines matching `^[[:space:]]*//`, over the tracked `*.go` files that are not `*_test.go` |
| comment share, the key registry | 1,494 of 1,854 (81%) | lines matching `^[[:space:]]*#` in `lifecycle/lifecycle.toml` |
| comment share, orders | 280 of 430 (65%) | lines matching `^[[:space:]]*#` in `orders/*.toml` |
| shell inside formula code fences | 2,789 lines of 7,374 | lines between column-0 fence markers in `formulas/*.toml` |
| tests whose subject is formula step text | 41 files, 13,114 lines; 9 script tests also read a block | each `*.test.sh` outside `tools/` whose text holds both `formulas/` and `# >>>`, split by whether an `X.sh` sits beside `X.test.sh` |
| "legacy" in runtime code | 23 mentions in 12 files | `git grep -c -i legacy $C -- assets/scripts doctor formulas services`, keeping the paths `measure.sh` counts as runtime |
| commits on the Gas City fork's main that upstream main lacks | 77, with the rig's `origin/main` at 6589a7df4 and `upstream/main` at dba20336e, each its remote's main by `git ls-remote` on 2026-11-13 | `git -C rigs/gascity rev-list --count upstream/main..origin/main` |

Run at d983f9f50, each command but the fork's gives the result section 7 of the
first record gives, so the two measurements compare like with like. The fork's
names no commit of this repository. The percentages round
to the nearest whole percent. Runtime shell's move from 35% to 36% is 35.4% to
35.5%, and the key registry is 80.6% at both commits. Go's share fell from
32.8% to 28.8% because Go outside tests grew by 9,573 lines, 2,028 of them
comments.

## What this record does not take again

- The built-once estimates. The doc's estimate column, its 64k and the 15% of a
  runtime file it allows for comments stand as
  [section 2 of the first record](../tk-11l1ejh/measurement.md#2-how-each-estimate-was-derived)
  derived them at b09345315. Cutting an estimate again is a judgment about what
  survives, not a measurement, and tk-1tfzr71.95 asks for the baseline.
- The native primitives, verified at Gas City upstream main f78779e41 on
  2026-10-26
  ([section 4 of the first record](../tk-11l1ejh/measurement.md#4-the-counts-behind-what-has-no-place-in-the-built-once-shape)).
  The doc dates that check.
