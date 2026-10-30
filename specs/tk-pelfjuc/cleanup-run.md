---
name: Dead-branch cleanup run on gc-toolkit's origin, tk-pelfjuc
description: The record of the one-time run on 2026-10-30 that ended 127 dead branches on gc-toolkit's origin and left no archive tags. It gives the ruling the run followed, how each branch was ended, the counts, what the run left alone, and each ended branch's full tip. Read it to find where a deleted branch pointed, or before running another bulk branch cleanup.
---

# Dead-branch cleanup run on gc-toolkit's origin

Bead: `tk-pelfjuc`. The run ended 127 branches on gc-toolkit's origin on
2026-10-30, from 01:46Z to 02:09Z (UTC), while main was at `57780964`. It
followed the operator's ruling on visit `tk-w9qvc3k`, which the bead's notes
record under "Approved 2026-10-30". The list came from the bead's "Derived
list, 2026-10-29T23:16Z" note, a read-only sweep made on that visit with
`assets/scripts/branch-end.sh --dry-run`.

## The ruling

- End the 127 branches in classes 1 to 5 of the derived list, each at the tip
  listed for it.
- Leave no archive tags, because nothing on the list is wanted later. This
  holds for this run only. `branch-end.sh` still pins an unpinned tip with a
  tag when the city retires work.
- Leave alone every branch that is not on the list.

The run departs from the bead's description in two places. The description's
census counted 125 dead branches, and the list held 127, because
`polecat/tk-al69qz` and `polecat/tk-z1wjjcn` were retired after the census.
The description also asked for every tip to be pinned before its delete, and
the ruling dropped that for this run.

## How each branch was ended

Before each delete, the run read the branch's full tip with
`git ls-remote origin refs/heads/<branch>`. It went on only when that tip
started with the 12-hex tip on the list.

- **A PR head equals the tip (classes 1 and 3, 95 branches).** The run called
  `branch-end.sh --rig gc-toolkit --branch <branch> --bead <id>`. The helper
  checked that no live owner names the branch and found the PR's
  `refs/pull/<n>/head` at the tip. It then deleted the branch with a lease on
  that tip and read origin back. Every call reported
  `ended <branch> at <tip>; its tip is kept by refs/pull/<n>/head`, naming the
  PR the list named, so the helper pushed no tag.
- **No PR head equals the tip (classes 2, 4 and 5, 32 branches).** The helper
  refuses to delete a tip that nothing pins, so here it ran only as the owner
  guard. `branch-end.sh ... --dry-run` had to exit 0 and report that it would
  push a tag, which means no live owner names the branch. The run then deleted
  the branch with
  `git push --force-with-lease=refs/heads/<branch>:<full tip> origin :refs/heads/<branch>`
  and read `git ls-remote origin refs/heads/<branch>` back as empty.

The run passed `--bead` for each `polecat/<id>` branch whose bead read in the
rig store. All 120 of those beads read `closed`. The seven strays in class 5
have no bead that reads there, so they ran without it.

A full read of origin at 01:43:56Z, before the first delete, matched the list.
All 127 branches were at their listed tips. The listed PR ref of each branch in
classes 1 and 3 pointed at its tip, and no PR ref pointed at the tip of a
branch in classes 2, 4 or 5.

## Counts

| Class in the derived list | Ended | How |
|---|---|---|
| 1. Closed without landing; its closed PR pins the tip | 75 | helper |
| 2. Closed without landing; no PR pins the tip | 15 | guard, then a leased delete |
| 3. Merged; a merged PR pins the tip | 20 | helper |
| 4. Merged; no PR head equals the tip | 10 | guard, then a leased delete |
| 5. Strays; no live owner and no PR | 7 | guard, then a leased delete |
| Total | 127 | |

No listed branch is left on origin. None had moved, the guard kept none, and no
read failed. The run pushed no tag. Origin held the same three tags before and
after it: `archive/polecat/tk-wwmxpe@9478569997e3` and
`archive/polecat/tk-wx5ybh@118fa2d2176a` from automatic retirements, and
`rescue/integration-refinery-script-fixes-pre-rebase`.

## What the run left alone

Origin held 150 branches at 01:43:56Z, `main` included, and 23 at 02:09:20Z.
The 127 the run ended are the whole difference: no other branch appeared or
went in between.

These 22 branches besides `main` remain, and none was on the list:

- `gctk-lane-state-port`, outside the census classes, which holds work from
  the operator's own session.
- The eight `claude/*` branches from the operator's interactive sessions:
  `claude/bead-host-naming-nhyhzs`,
  `claude/gas-city-pack-architecture-1uyfq2`,
  `claude/gc-toolkit-architecture-uhm0hx`,
  `claude/gc-toolkit-collaborative-ui-9qwdmf`,
  `claude/gc-toolkit-spec-roles-m668at`,
  `claude/merge-conflict-resolution-mfdqpa`, `claude/sweet-dijkstra-5ngrrr`
  and `claude/validation-agent-results-ygg2fm`.
- Twelve branches that the visit's sweep found kept by a live owner:
  `integration/review-engagement`, `integration/tk-alyaztk`,
  `integration/tk-iirrmiw`, `integration/tk-ssm8qns.1`, `polecat/tk-0o4wmna`,
  `polecat/tk-15c10m`, `polecat/tk-gfb2hbq`, `polecat/tk-i17pn6e`,
  `polecat/tk-iirrmiw.1`, `polecat/tk-iunfnh`, `polecat/tk-pxfpxt` and
  `polecat/tk-r5ofy4t`.
- `polecat/tk-vd66j1.11`, pushed after that sweep.

Four more branches that the sweep found kept by a live owner had left origin
before the run began, and the run did not touch them: `polecat/tk-kfte3b`,
`polecat/tk-n18e15`, `polecat/tk-ssm8qns.2` and `polecat/tk-wmwcdlc.1`.

## Other rigs

The description also says that other rigs' backlogs are counted at run time,
and that each is cleared only if the operator agrees. A read-only count from
02:12Z to 02:15Z ran the same guard dry run over every `polecat/*` and
`integration/*` branch on the origins of the six other rigs in the city's rig
map. It found 87 branches the guard would end, 70 of them pinned by a PR ref
and 17 pinned by nothing, and 29 that a live owner keeps. The run wrote nothing
to those origins. Clearing them waits on the operator, rig by rig, in
`tk-d7sa474`, whose notes carry the per-rig counts.

## The ended branches and their tips

Each row gives a branch, its full tip when the run deleted it, and what keeps
that commit on origin now. "Nothing" means no ref on origin points at the tip,
as the ruling chose. One stray in class 5 was named after a bead in the city's
own store. A gc-toolkit file carries no other rig's bead ids, so its row writes
that part of the name as `<city-store bead>`, and its tip identifies it.

| Class | Branch | Tip | Kept by |
|---|---|---|---|
| 1 | `polecat/tk-10521` | `b09e3fe2baef5b3918edf9442cb6c7508d21afa3` | `refs/pull/454/head` |
| 1 | `polecat/tk-1xapp9` | `5b4f3b6750a4b2f5f2908393d5da90ad7bca5964` | `refs/pull/76/head` |
| 1 | `polecat/tk-2hl20j` | `99fbe14ba908071679e74811937e838f358f2a1c` | `refs/pull/786/head` |
| 1 | `polecat/tk-39tv12` | `dabb7a5f8dfee26e73d67feed343334d43f82137` | `refs/pull/462/head` |
| 1 | `polecat/tk-3yrll` | `c904617ce599dce16d4c58672fde9f443994f653` | `refs/pull/107/head` |
| 1 | `polecat/tk-492ssx` | `bd5a82e941874dbb75c04771eea59465c668261b` | `refs/pull/767/head` |
| 1 | `polecat/tk-4jz9s` | `2d06892b76650a24975dc1d01653074eef8b9b97` | `refs/pull/217/head` |
| 1 | `polecat/tk-5w3boh` | `d5bbbf079f45698a755e2051e5ea93f00b9c5dff` | `refs/pull/457/head` |
| 1 | `polecat/tk-65dyok` | `f881f41bc5f56db157f23baa77664b091bd5556c` | `refs/pull/513/head` |
| 1 | `polecat/tk-6bji7k.6` | `0a224c8705bace04491e0ddf360e2bdce6f6ece8` | `refs/pull/870/head` |
| 1 | `polecat/tk-6d0vb.3.1` | `409524824b4b0da2df4a1d18b5c6e352f5421abe` | `refs/pull/133/head` |
| 1 | `polecat/tk-7druqk` | `920789313e6d3a021050022f3fe4c7a565104e85` | `refs/pull/88/head` |
| 1 | `polecat/tk-9e1y2v` | `4043c954bb0ce231740087c046dfab27da9d400c` | `refs/pull/824/head` |
| 1 | `polecat/tk-9heqfh` | `799ae7b7dd3ea2b92538f6dc24fd96a06b77c763` | `refs/pull/477/head` |
| 1 | `polecat/tk-9obwui` | `f223fcb62afc78d36b972f1d3ce5a715ccbdeb05` | `refs/pull/80/head` |
| 1 | `polecat/tk-9tbbk.3` | `9cb9efea78eeb699004208cd93339b1fef9d63ee` | `refs/pull/447/head` |
| 1 | `polecat/tk-9vbg5` | `71b13802549d40e7d013aa20e26fff7ee5da660b` | `refs/pull/624/head` |
| 1 | `polecat/tk-a0g130j` | `9e6c1271273c5df5425deadf42083dff408d142a` | `refs/pull/1150/head` |
| 1 | `polecat/tk-ae96t.1` | `b1072b11d8521e67fc30b39ede3266e6382bde5e` | `refs/pull/132/head` |
| 1 | `polecat/tk-ae96t.2` | `dba41c255c8fae8ca3c842db658f538a4a7fc910` | `refs/pull/166/head` |
| 1 | `polecat/tk-al69qz` | `d59f192d51e8e5e7bab320708f8c6f9d67a488b6` | `refs/pull/992/head` |
| 1 | `polecat/tk-ax6y4` | `7da0055e08cc1d838a564c2c246a8207c429d8cf` | `refs/pull/466/head` |
| 1 | `polecat/tk-ay3wv` | `a197bd0ed80f5b8f63bd6650a3af00b1bb5f3bea` | `refs/pull/623/head` |
| 1 | `polecat/tk-banku` | `470b164a5d3b4de5d1d24029f0e4c9ff647acdac` | `refs/pull/187/head` |
| 1 | `polecat/tk-bcb6n1` | `d1a6cf6e3782128a72b8e9970ae04d6712aca530` | `refs/pull/583/head` |
| 1 | `polecat/tk-blp842` | `8c57c36b5effaeb8fe3905d3ed613ffb9e21b364` | `refs/pull/778/head` |
| 1 | `polecat/tk-clvkf6` | `18e26cc7c4d32d49a4cf49268be9dbb874c04d7e` | `refs/pull/456/head` |
| 1 | `polecat/tk-cypm0c` | `9f658c108c9ce3489056f83bb42a26ea83609ccf` | `refs/pull/551/head` |
| 1 | `polecat/tk-czh6y` | `7f3039c4501edd544c2ee7e48f46f79990ff15c1` | `refs/pull/616/head` |
| 1 | `polecat/tk-d9g0x` | `7f9021320688ac312268cf768d6db367179ddb1d` | `refs/pull/330/head` |
| 1 | `polecat/tk-dks4kk` | `6ef6c66855a710aa3df7576f3d13766ca2cb5120` | `refs/pull/496/head` |
| 1 | `polecat/tk-f2wpu` | `e0b05de29c8a9f8a5ae1b50139e3c88d4e330a91` | `refs/pull/23/head` |
| 1 | `polecat/tk-f8cxq` | `a705e0ceafc693d2010bed494797e82b4f20164f` | `refs/pull/993/head` |
| 1 | `polecat/tk-fwcdtl` | `7da56a7968bd0dd83e703f9b14501527a8df3c96` | `refs/pull/694/head` |
| 1 | `polecat/tk-g6xcwi` | `d1fa1237ead6396dc9d3f66828042d5bfa4f2b57` | `refs/pull/915/head` |
| 1 | `polecat/tk-guztrs` | `d828ba08219a13a2095c35619a512906e5060856` | `refs/pull/1096/head` |
| 1 | `polecat/tk-hmuame` | `f7640f92a874c76e70ad8b5ae5a66a7a0025b126` | `refs/pull/683/head` |
| 1 | `polecat/tk-hnrind` | `34c07e2e58823a91f6f310942b1389cabe8d8e6f` | `refs/pull/969/head` |
| 1 | `polecat/tk-hq4v3l` | `117181aa76da4282f50a19fd1f82f21fd46b678a` | `refs/pull/459/head` |
| 1 | `polecat/tk-i21z7` | `c8f23f3a64ace46a3278921fba0d5975a69ace7d` | `refs/pull/154/head` |
| 1 | `polecat/tk-ic9odt` | `e8b242089054c0360da4f84d9ed2626db72ec7f7` | `refs/pull/461/head` |
| 1 | `polecat/tk-iguy2a` | `b4157f2c5dd76fbbdde35a7c23404e3b2f9aa949` | `refs/pull/787/head` |
| 1 | `polecat/tk-iqwxq` | `53b45161bb549d2c1ace0c73e4a962bb9275e1ec` | `refs/pull/620/head` |
| 1 | `polecat/tk-j81t84` | `d90999ef399326e32c778d44a9ade962414442ba` | `refs/pull/473/head` |
| 1 | `polecat/tk-jozah0` | `2b7c8a073e827e578f86829d77ffbcc8ea20b39e` | `refs/pull/463/head` |
| 1 | `polecat/tk-kcr8v6` | `41964a6a9202185b4aac4771fe619551b63fd07a` | `refs/pull/77/head` |
| 1 | `polecat/tk-kt4ubc` | `66f0d0a6db9c574d12c984c7809c9188a1abe403` | `refs/pull/615/head` |
| 1 | `polecat/tk-ku1uvv` | `1dcec58ad00dbd0f88f18643a772ba9cd0e12290` | `refs/pull/464/head` |
| 1 | `polecat/tk-l5s13` | `e5cc496cde7f2a7440ff536873a9090c8ed3443e` | `refs/pull/141/head` |
| 1 | `polecat/tk-l8t5n` | `a964771477ebe740648cc9ec47c51d0d58b79a48` | `refs/pull/167/head` |
| 1 | `polecat/tk-lgybmu` | `9d357fcc5ca88e59360d0ab2679cf5bca7611f89` | `refs/pull/502/head` |
| 1 | `polecat/tk-mtz7xt8` | `109ecf4b31b42424acd0e46ba46261afdb4606cb` | `refs/pull/1144/head` |
| 1 | `polecat/tk-mvc72` | `d08e04b5064dd932957be237c4cc19c814ebd801` | `refs/pull/467/head` |
| 1 | `polecat/tk-o28ci` | `ffab3ba96a70771ad1bc5fcda236baa72b33cd31` | `refs/pull/126/head` |
| 1 | `polecat/tk-oe5bc3` | `72bf5990dfc425189ef2ee6b7e93a27197783ac0` | `refs/pull/84/head` |
| 1 | `polecat/tk-oe8o0` | `dbf140b16fc1aba77650bb5ab5c796df7e7ab35c` | `refs/pull/123/head` |
| 1 | `polecat/tk-ohrlc` | `8e40bdc2257b5da33c2b60ade83ce7c0b631dbf3` | `refs/pull/130/head` |
| 1 | `polecat/tk-oqseh6` | `2637920b8acea53f73d9880469bcc0d7a9c5ea00` | `refs/pull/470/head` |
| 1 | `polecat/tk-qf055w` | `baad734bc8b988a543cab9e57f13a9329a43fd41` | `refs/pull/742/head` |
| 1 | `polecat/tk-qz6081` | `297c0d6e01206b7f7db8da727205123a76e6ed0d` | `refs/pull/458/head` |
| 1 | `polecat/tk-sfg2e` | `43993d6934f676b43e42fa126afb448169816377` | `refs/pull/439/head` |
| 1 | `polecat/tk-tu5g3` | `cc25d9fe57087853d3107c0439eafbdccdde3030` | `refs/pull/468/head` |
| 1 | `polecat/tk-tutb46` | `375719cbd0c78a2e95956d8cd5544448bff72ea1` | `refs/pull/885/head` |
| 1 | `polecat/tk-twp697` | `d3739cce05c681985639e77a4a7a9c94d8de771e` | `refs/pull/455/head` |
| 1 | `polecat/tk-umkk4d` | `7c4bbec0772c00214ab0180987a5dfa8afdc965a` | `refs/pull/925/head` |
| 1 | `polecat/tk-v3jwg` | `61ab00960ecc228591edf8b47f8341bd2dc536f0` | `refs/pull/592/head` |
| 1 | `polecat/tk-vathjv` | `62af659d5a55f02d41e930e38255ff698bed030f` | `refs/pull/449/head` |
| 1 | `polecat/tk-vn78c` | `c290cdd48854574dd98422a789bbca4a4ce914b6` | `refs/pull/181/head` |
| 1 | `polecat/tk-wfufb9` | `fa68fc4c6956562508caf9878b3b3b7e905b7e59` | `refs/pull/448/head` |
| 1 | `polecat/tk-wz4igt` | `29dc362887fa21068087ee446c3b8629e64daeef` | `refs/pull/469/head` |
| 1 | `polecat/tk-xhwits` | `9ebab091eceb15b4a978a1c16a71b2a6cdf0cb1a` | `refs/pull/564/head` |
| 1 | `polecat/tk-yhwfv.5` | `512e99fb9a2dd1681e73e9a9885da252e720ce28` | `refs/pull/460/head` |
| 1 | `polecat/tk-zdkfe` | `cb3d36afb0688cd9f8fb4df12410342a459dd56a` | `refs/pull/203/head` |
| 1 | `polecat/tk-zf4vm` | `e47c9f1ebf864b4d8cf8d2bf528a18c0023d458c` | `refs/pull/243/head` |
| 1 | `polecat/tk-zz1yy` | `e95a4a505061b48c0be4080e159ba4eee0066713` | `refs/pull/746/head` |
| 2 | `polecat/tk-8u81bo` | `d2103e0b8b0780f1180dc1c91709e553c95b9434` | nothing |
| 2 | `polecat/tk-9ntg93` | `d82af132852123477b125f61842525dadc78e687` | nothing |
| 2 | `polecat/tk-doo0x` | `e6fd488c4801a858a482c4a097fb4f0f70aa2ee9` | nothing |
| 2 | `polecat/tk-fvqn0` | `2b44d7fbcfd66e927400aea619d8e468c576d0f1` | nothing |
| 2 | `polecat/tk-gu2ctv` | `71341ac322aa888e32ca33d5135ef1fe442defde` | nothing |
| 2 | `polecat/tk-lcv9a` | `f2a29cd1bbb4b72c8a77b1dccef48d4fb0d58ba0` | nothing |
| 2 | `polecat/tk-lobcs` | `5542fadecb4a0f262e652e1dd83328ea9114e95a` | nothing |
| 2 | `polecat/tk-maxwy7z` | `280a7a3c31374b2b53f9c96f7823068f1d61f15a` | nothing |
| 2 | `polecat/tk-mq9bvj` | `86629c74b80a3e39fc3481b3466dfcb0789add4e` | nothing |
| 2 | `polecat/tk-mt1ey` | `6c212914017df88b6e2187ba5ceebd8b83445393` | nothing |
| 2 | `polecat/tk-uy7tc` | `f8ca27b7395e2c8b39e10c1061e97bf204df48e5` | nothing |
| 2 | `polecat/tk-y3tks` | `ea986d458acbb599930a6389c1e121a254a34b60` | nothing |
| 2 | `polecat/tk-z1wjjcn` | `48450b7448def935ae3f43ad189dce90cec04846` | nothing |
| 2 | `polecat/tk-zflam` | `3e93d2b83ea7f4fbbad98ee818b1c3f461839e1d` | nothing |
| 2 | `polecat/tk-zgueia` | `5ec521b339cc9a7c935ae5b27da5a941ee4f9943` | nothing |
| 3 | `polecat/tk-03wjb` | `bc9bebec82b72c29f841fdf2c59ea63e995a03e3` | `refs/pull/430/head` |
| 3 | `polecat/tk-2cy79` | `b15d41b487813d90fbd62228ff5d7a29fec3698a` | `refs/pull/426/head` |
| 3 | `polecat/tk-2cyxo` | `b8985a49079573679455c2cbcda467ae7792114b` | `refs/pull/423/head` |
| 3 | `polecat/tk-2v08m` | `389ab80977b6bc0b385a81ccdbe1ae95b31e30b8` | `refs/pull/402/head` |
| 3 | `polecat/tk-3lvtr` | `0289b7bab7c750a570cef051f556de84c917819c` | `refs/pull/158/head` |
| 3 | `polecat/tk-5kfhl` | `90228af141f0ebba61f9d0dffab519d7f9fb2e43` | `refs/pull/440/head` |
| 3 | `polecat/tk-d6ddn` | `6905a6e9ecd34843db28c203fe7a11a333d70f1d` | `refs/pull/410/head` |
| 3 | `polecat/tk-fkeft` | `74d490cc30dfb9f190085eabb9247f2e38d0be5d` | `refs/pull/404/head` |
| 3 | `polecat/tk-hscs0` | `e7ff831f4cb26063f7f5e7eda62a8f0a4eb7f9d6` | `refs/pull/436/head` |
| 3 | `polecat/tk-mlacu` | `a49e0fb52c64ac852a687b4904fdab5a233342d0` | `refs/pull/162/head` |
| 3 | `polecat/tk-mtuej` | `d315a732e29d8b6573d17198ec80bb756ccfac38` | `refs/pull/417/head` |
| 3 | `polecat/tk-qf2l0j` | `31ebfe8b891726e5e661d2f0705719c2a554cadf` | `refs/pull/442/head` |
| 3 | `polecat/tk-s2uy9h` | `ee4dee673cad84cdbf52cd9f656960c386f111f7` | `refs/pull/546/head` |
| 3 | `polecat/tk-st143` | `73a05279957f20c7e6bf3182b619107eba78f351` | `refs/pull/414/head` |
| 3 | `polecat/tk-vvnkj` | `d81b6d571bbdf80a29469e45b5ff6c14d6d12a12` | `refs/pull/424/head` |
| 3 | `polecat/tk-w4dp4` | `c54b217621c1205acca705d1f95133882ca1a1ec` | `refs/pull/407/head` |
| 3 | `polecat/tk-wvrga` | `236fa095d4ee0cd18a677f30cf85cbaf29d27761` | `refs/pull/428/head` |
| 3 | `polecat/tk-yc00g` | `11cc7980b61cee4cc7c33bfbd23b24f6953087c7` | `refs/pull/421/head` |
| 3 | `polecat/tk-yhwfv.2` | `b755692f3a15d2cf00d2c2f40bc1be2479110e87` | `refs/pull/429/head` |
| 3 | `polecat/tk-hi95z` | `4036f138118fc9153b42a416bc87e7f8a0c59329` | `refs/pull/116/head` |
| 4 | `polecat/tk-2plde` | `e8049f471018a172d181421f7aca184b9d9ed31f` | nothing |
| 4 | `polecat/tk-7yuemr` | `083f9b308541c94909620c4e3a3e8dddad73b937` | nothing |
| 4 | `polecat/tk-a9k0l` | `90ed3a5e55e5d144010f8f36583644bf93fd047a` | nothing |
| 4 | `polecat/tk-ezgr2` | `3085fc248e362869adeac6cb4c926925e1f9639c` | nothing |
| 4 | `polecat/tk-hadhh` | `9128e956f4c78ea17f6d35fb3697ad22ae6c75fd` | nothing |
| 4 | `polecat/tk-vie5k` | `e9c03e6c6e9ca1b869587d9e8e84533a423400f4` | nothing |
| 4 | `polecat/tk-w6mqaw` | `c16e9e70205284d56861e21559534eb752b144bd` | nothing |
| 4 | `polecat/tk-yhwfv.1` | `574ed4e223e5d7dbec48169dbcabe97b1eb7692c` | nothing |
| 4 | `polecat/tk-yw3zb.11` | `c52dd8f954fd386cf109fe777b8150800c3e4722` | nothing |
| 4 | `polecat/tk-yw3zb.12` | `62dfe7cef0919a52b173cf6665abbbb69e089123` | nothing |
| 5 | `integration/smoke-tests` | `2c774279fd1be6a2dd63da3615c758c252c3b256` | nothing |
| 5 | `integration/tk-hold-sweep` | `08196b1afde69281d1ef13706ff7828af2b46dec` | nothing |
| 5 | `polecat/<city-store bead>` | `0aeacacd282cabb612f0787c2d1597433f80d227` | nothing |
| 5 | `polecat/tk-hmd5o5` | `abd758458a9c9b08a71a07a19a8bca0ffbe9f3da` | nothing |
| 5 | `polecat/tk-qf055w-arm` | `a79cf2c80f99a78287d897c0075d4a6a4d0f4d5c` | nothing |
| 5 | `recovery/tk-t88hg-furiosa-0ccd844` | `0ccd8443c2566f7de16949d34ae457cb670a927f` | nothing |
| 5 | `gc-gc-toolkit.polecat-1-906a79e31bfd` | `b7f540d23239b26720af2025cbdf29961c49a165` | `main`, which contains it |
