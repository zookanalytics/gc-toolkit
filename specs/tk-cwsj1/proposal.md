---
name: Worktree + Branch Cleanup — Structural Proposal
description: Decides the five research questions on tk-cwsj1 for all three leaked resource families (git worktrees, branches, backup refs) — picks hybrid ownership with a per-family split, names the staleness signal for each, sets the safety contract, and scopes the sweep. Proposal only; no reaper is implemented here.
---

# Worktree + Branch Cleanup — Structural Proposal

## Scope

**Mandate.** Decide *what should own* the teardown of agent-created git
worktrees, branches, and backup refs, and *what evidence* that owner may
act on. This is the "should" that tk-cwsj1 asks for before any "how".

**Boundaries.** Proposal only — no reaper formula, no predicate patch, no
deletion performed. It commits to ownership, signals, a safety contract,
and scope; it does not specify formula step bodies. The `/tmp` leak
family (`tk-ib3x6`, `gc-kegcf`) is referenced for a boundary decision,
not subsumed.

## The decision in one paragraph

All three families leak for the same reason — **terminal transitions have
no owner** — but they do not leak at the same *end*, so one uniform answer
is wrong. Branches have a flawless happy path and two unowned failure
paths. Worktrees have the inverse: their failure path is owned and their
**happy path is not**, which is where nearly all the volume comes from.
Backup refs have neither. The proposal is therefore a **hybrid split
per-family, not per-spectrum-point**: teardown fires at the transition
whose acting agent still knows the fate, a bounded central sweep covers
only what the transitions cannot reach, and branch fate stops being
inferred at all — it becomes a written-down disposition. Worktrees are the
one family a central sweep may judge from state, because a worktree is a
*cache* and its safety question is decidable locally.

## Evidence base

Two censuses. Neither should be re-run.

**Branch census (inherited).** Recorded in this bead's notes, from a
converse on `tk-zmrui`, 2026-08-14: every `refs/heads/polecat/*` on origin
in `zookanalytics/gc-toolkit`, joined against 354 PRs and the bead store.
37 survivors: 4 in flight, **23 whose PR closed unmerged**, **10 that never
had a PR**. `delete_branch_on_merge=true` and squash-only are set on both
audited repos, and the merged path is flawless — zero merged-yet-alive
branches.

**Worktree / local-branch / backup-ref census (this bead, 2026-08-14).**
Method in the appendix. City-wide across four rigs. Headline numbers:

| Measure | gascity | gc-toolkit | shutupandlisten | signal-loom | total |
|---|---:|---:|---:|---:|---:|
| Registered worktrees | 42 | 344 | 22 | 15 | **423** |
| `.gc/worktrees/<rig>` on disk | 4.2 G | 2.6 G | 3.1 G | 2.3 G | **12.2 G** |
| Local heads | 332 | 555 | 152 | 57 | 1096 |
| …with no origin counterpart | 235 | 518 | 148 | 53 | **954** |
| Ad-hoc ref namespaces | 7 | 3 | 2 | 1 | **10 distinct** |

Nothing reclaims any of it. `git worktree prune` in `gc-toolkit` reports
**0 prunable** — every one of the 344 registrations has a live directory
behind it, so the built-in is a no-op here by construction.

## Five findings that decide the questions

**1. The worktree gap is the mirror image of the branch gap.** The branch
census found the *happy* path covered and the failure paths bare. For
worktrees it is reversed. Teardown exists only in the witness's
orphan-recovery path (`mol-witness-patrol`, `recover-orphaned-beads` →
`git worktree remove --force` + `prune`) — a *failure* path. The success
path does not clean up: `mol-polecat-work`'s `submit-and-exit` pushes,
re-stamps metadata, hands the bead to the refinery, and drains, never
removing the worktree it created in `workspace-setup`. That single
omission accounts for the bulk of the 344: 211 are per-bead worktrees
under `polecats/<agent>/worktrees/<bead>`, the exact path
`workspace-setup` mints. Two agents dominate — `furiosa` (116) and `nux`
(91).

**2. The fix already exists in-tree; the dominant formula just omits
it.** `mol-polecat-commit` step 3 does exactly the right thing — `git
worktree remove "$WORKTREE_PATH" --force` followed by `gc bd update
--unset-metadata work_dir` — and `mol-scoped-work` does the same. The
operational fix for the largest single family is copying a sibling
formula's step, not designing a mechanism.

**3. Worktrees and local branches are one leak with two surfaces.**
`worktree-setup.sh` mints an anchor branch `gc-<agent>-<hash>` per
worktree. In `gc-toolkit`, **234 of the 518** origin-less local heads have
exactly that shape, and 236 of 344 worktrees hold a branch. Those
branches are not independently leaked — they are *pinned* by a worktree
and become deletable the moment it is removed. Worktree teardown reclaims
roughly 45% of the local-branch leak for free, which is an argument for
sequencing worktrees first.

**4. Local branches are a third family, and it is 26× the size of the
one already surveyed.** The inherited census covered origin only. Origin
carries 37 survivors; the *local* refs carry **954** with no origin
counterpart, 518 in `gc-toolkit` alone. Neither mechanism that exists
touches them: `delete_branch_on_merge` acts server-side, and `git fetch
--prune` prunes remote-tracking refs, never local heads.

**5. Under squash-only merge, git state cannot testify to fate — a
second, independent confirmation of the census's Q2 answer.** 240 of 344
worktrees sit on a HEAD that is not an ancestor of `origin/main`, and
**229 of those hold commits reachable from no origin ref at all**. That
looks like 229 pockets of unlanded work. It is not: squash-merge
guarantees a landed branch's commits never appear on `origin/main`, so
"unmerged commits" is the *expected* post-success state. Commit
reachability is therefore as useless a staleness signal as
"branch with no open bead" — the predicate the census already ruled out,
and the one `recover-stranded-branches` currently uses.

## Q1 — Operational, centralized, or hybrid?

**Hybrid, with an asymmetric per-family split.** The spectrum framing in
the bead assumes one answer applies to all resources; the evidence says
each family needs its own end covered.

| Family | Happy path | Failure paths |
|---|---|---|
| Origin branch | **covered** — `delete_branch_on_merge`, zero misses in 354 PRs | **bare** — PR closed unmerged (23), never had a PR (10) → new operational owner at each transition |
| Worktree | **bare** — `mol-polecat-work` never removes → new operational owner in `submit-and-exit` | partly covered — witness orphan-reset; remainder → bounded central sweep |
| Local branch | mostly reclaimed as a *side effect* of worktree teardown (234/518) | unpinned remainder → same central sweep |
| Backup / scratch ref | bare | bare → TTL declared at the minting site + namespace policy |

The operational half is load-bearing because of the census's core insight:
teardown must fire while the acting agent still *knows* the fate.
Everything after that moment is archaeology. The centralized half is
deliberately small — it exists to catch what crashes and restarts leak
past the transitions, not to be the primary mechanism.

## Q2 — What signals "stale"?

Three different answers, and the difference is the substantive result.

**Branches: the transition, never the state.** Adopt no state predicate.
The census ruled out "no associated open bead" (33 of 37 survivors match
it and most are correctly dead), and finding 5 rules out commit
reachability on independent grounds. The signal is the event — a PR
closing unmerged, a bead reaching a terminal state — consumed at the
moment it happens.

**Worktrees: state is safe here, and this is the asymmetry that matters.**
A worktree is a *cache*: it is fully derivable from `(branch, commit)`,
so removing one destroys nothing that git still holds. The only
irreplaceable thing it can contain is content git does not have. That
question is decidable locally and cheaply, which is precisely what makes
worktrees centrally reapable when branches are not. The predicate is
"holds nothing unrecoverable" — see the safety contract for its exact
shape. Age is not part of it, and the data is blunt about why: only **14 of the
211** per-bead worktrees in `gc-toolkit` are older than 30 days. The
population spans 2026-06-14 to today, so any defensible age threshold
leaves ~93% of the leak in place. Age is a proxy for the real test and a
poor one.

**Backup and scratch refs: a TTL declared where the ref is minted.** A
backup ref is bounded-duration insurance by definition; the script that
creates one is the only actor that knows how long it is worth keeping.
No sweep should have to guess.

## Q3 — The safety contract

Four clauses. The first three are forced by evidence; the fourth mirrors
`mol-dog-reaper`'s parent-closed gate.

**C1 — Branch deletion is never inferred from branch state.** From the
census's verified near-miss: `claude/ios-voice-transcription-review-9ss6cj`
in `suandl/shutupandlisten` was *deliberately retained* as the pre-port
source of truth by a recorded decision (`su-xkmq.2`) while its content
reached main on a different branch. An age-based or no-bead-based reaper
would have deleted the only copy.

**C2 — A worktree may be removed only when it holds nothing
unrecoverable, and the check must classify its dirt, not count it.**
Three conditions: no uncommitted modifications to tracked files; no
untracked content outside a declared-ignorable set; HEAD reachable from
a ref that survives the removal. The "classify, don't count" clause is
not pedantry — it is the single most important implementation detail
here. A naive `git status`-is-empty gate reads **196 of 344** worktrees
as holding operator work. Filter two classes of systemic noise and the
real number is **9**:

- **194 worktrees report the identical pair of tracked-file deletions** —
  `specs/tk-1k0fay/superpowers.md` and `specs/tk-yiwfz.2/superpowers.md`
  — for files that are present in `origin/main`'s tree and were removed
  by no commit. Identical across the population, therefore systemic, and
  not work. *(Worth its own bead; out of scope here. Flagged because any
  safety gate built before it is understood will refuse to reap
  essentially everything.)*
- **Nested worktrees show up as untracked directories in their parent.**
  Review and rework worktrees are created *inside* another worktree's
  directory, so the parent reports them as `??` dirt. They are registered
  worktrees in their own right and must be resolved as such.

Of the 9 that survive both filters, **6 are agent homes or the canonical
rig checkout** (`rigs/gc-toolkit`, `coord-bead-universe`, and the
`hicks` / `ripley` / `furiosa` / `nux` homes) — never reapable by
definition and worth an explicit never-touch list rather than a
predicate. Only **3** are per-bead worktrees holding genuine uncommitted
work.

**C3 — Deliberate retention must be expressible and durable.** The
asymmetry the census named: beads have a first-class disposition
(`bead-rehome.sh` writes `gc.superseded_by` plus store plus a populated
close reason); branches have none, so branch fate is the thing every
patrol reasons about and the one thing nobody writes down. `su-xkmq.2`'s
retention decision lived only in prose in a bead that is now closed.
Propose a first-class branch disposition — `landed` / `abandoned` /
`retained:<reason>` / `superseded_by:<ref>` — written by whichever agent
performs the terminal transition, plus a `preserve/` ref namespace whose
published contract is "never reaped". Both must outlive the bead that
decided them. The namespace is not an invention — `gc-toolkit` already
carries two `preserve/*` branches created organically by an agent
reaching for exactly this expressiveness. What is missing is the
published guarantee that anything reaping branches will honour it.

**C4 — Dry-run first, report before act.** Any sweep reports its
candidate set and reclaimable bytes for a cycle before it is permitted to
delete, and a suspended rig (`gc rig list`) is skipped outright.

## Q4 — Per-rig or city-wide?

**One implementation, invoked per rig, with per-rig policy.** Not
per-rig formulas. The precedent is already established:
`mol-refinery-patrol.toml` is a single shared file, symlinked into each
rig and rig-scoped through `city.toml`. Duplicating a reaper per rig
would fork four copies of the C1–C4 contract, which is the part that must
not drift.

Per-rig *policy* is still required, because the leak rates differ by more
than an order of magnitude (344 worktrees in `gc-toolkit` against 15 in
`signal-loom`) and because suspension state gates the sweep per C4.

## Q5 — Should one reaper also cover the `/tmp` leak families?

**Keep them separate, with one hard interlock.** Different owner (a
process tempdir versus a git object), different safety bar (`/tmp` has no
git-recoverability test to appeal to), different retention.

The interlock: **7 registered worktrees in `gc-toolkit` live outside the
city tree** — five under `/tmp/gc-review-*`, one under `/var/tmp`, one
under `~/tmp`. These are real entries in the rig's worktree registry. A
`/tmp` reaper that `rm -rf`s a `gc-review-*` directory corrupts that
registry. So the boundary is by *identity*, not by path: anything git
holds a worktree registration for belongs to the worktree family
regardless of where it sits, and the `/tmp` sweep must consult the
registry before deleting. The two should share a reporting surface so an
operator sees one reclamation figure, and nothing else.

## How this subsumes tk-zmrui

Per this bead's instruction, `recover-stranded-branches`'s predicate is
not patched independently — its problem is that it infers branch fate at
all, and a fourth inference key makes it worse.

Under this proposal it stops inferring: it **reads the disposition** from
C3. `retained` or `superseded_by` → skip. `landed` → skip. Absent →
that is the pre-disposition population, and only for it is the
content-equivalence probe `tk-zmrui` proposed the right guard — attached
as `likely_superseded=true` plus the present/total ratio so the refinery
triages, rather than suppressing the hand-off. That probe is a
**migration aid with a sunset**, not a permanent fourth key: once every
terminal transition writes a disposition, the no-disposition branch of
the logic is dead code and should be deleted.

Backfill is a separate, operator-reviewed pass. 37 origin branches and
954 local heads exist today with no disposition; per C1 the steady-state
reaper must not be the thing that drains them.

## Follow-up work this proposal implies

Sequenced by value-to-risk. Each is a separate bead; none is done here.

1. **Worktree teardown in `mol-polecat-work`'s `submit-and-exit`**, copied
   from `mol-polecat-commit` step 3. Largest single family, lowest risk,
   no new mechanism. Do this first.
2. **Branch disposition (C3)** — define the key and the `preserve/`
   namespace contract; write it at the three terminal transitions
   (refinery land, PR close, bead terminal).
3. **`recover-stranded-branches` consumes the disposition** and carries
   the `tk-zmrui` probe as the sunset-scoped transitional guard. Closes
   `tk-zmrui`.
4. **The bounded sweep** — worktrees under the C2 predicate plus the
   unpinned local-branch remainder; dry-run-first, suspended-rig skip,
   never-touch list for agent homes and canonical checkouts.
5. **Backup/scratch-ref policy** — a TTL at each minting site across the
   10 namespaces, and a decision on whether they should be consolidated
   under one prefix.
6. **One-time backfill pass**, operator-reviewed, for the existing
   population.
7. **Root-cause the phantom `superpowers.md` deletions** (C2). A
   prerequisite for 4, since it dominates the dirty signal.

## Appendix — census method and raw counts

Run 2026-08-14 against the live city at `/home/zook/loomington`, four
rigs. Worktrees enumerated with `git worktree list --porcelain` per rig
repo; per-worktree state with `git -C <wt> status --porcelain` and
`git merge-base --is-ancestor HEAD origin/main`; local-branch survival by
testing each `refs/heads/*` for a `refs/remotes/origin/*` counterpart;
ref namespaces from `git for-each-ref` bucketed on the second path
segment. Disk from `du -sh` on each `.gc/worktrees/<rig>`.

*Caveat, inherited from the branch census and confirmed here: local refs
lie. That census found two apparently "merged yet alive" branches that
were stale local refs whose PRs had merged mid-run. Always `ls-remote`;
never trust a local scan ref for a question about origin.*

**Worktree composition, `gc-toolkit` (344 total, 0 prunable):**

| Class | Count |
|---|---:|
| Per-bead polecat worktrees (`polecats/<agent>/worktrees/<bead>`) | 211 |
| Codex review worktrees (`polecat-codex/<agent>/<slug>`) | 83 |
| Flat-named polecat worktrees (`polecats/<agent>/<slug>`) | 29 |
| Agent homes (5 polecat, 2 codex) | 7 |
| Outside the city tree (`/tmp`, `/var/tmp`, `~/tmp`) | 7 |
| Canonical checkout, refinery, coord, 2× proactive | 5 |
| Third-level nests (a worktree inside a per-bead worktree) | 2 |

**Uncommitted-content funnel, `gc-toolkit`:** 196 of 344 dirty by raw
`git status` → 194 carry only the systemic `superpowers.md` deletion pair
→ nested-worktree `??` entries resolved to their own registrations →
**9 remain**, of which 6 are agent homes or the canonical checkout and 3
are per-bead worktrees.

**Commit reachability, `gc-toolkit`:** 240 of 344 worktrees hold a HEAD
that is not an ancestor of `origin/main`; 229 of those hold a HEAD on no
origin ref at all — the expected state after a squash merge, not evidence
of unlanded work.

**Origin-less local heads by prefix, `gc-toolkit` (518 of 555):**
`gc-<agent>-<hash>` worktree anchors 234, `polecat/` 243, and 41 across
`rework/`, `preserve/`, `fix/`, `salvage/`, `resume/`, `mechanik/`,
`integration/`, `feat/`, `claude/` and unprefixed one-offs.

**Ad-hoc ref namespaces (121 refs, 10 distinct namespaces):** gascity —
`refs/backups` 53, `refs/prs` 10, `refs/tmp` 6, `refs/review` 2,
`refs/backup` 1, `refs/original` 1, `refs/staged` 1; gc-toolkit —
`refs/review` 15, `refs/witness-check` 2, `refs/recovery` 1;
shutupandlisten — `refs/witness-salvage` 18, `refs/review` 10;
signal-loom — `refs/review` 1. Note that `gc-toolkit` holds **zero**
`refs/backups` — the namespace this bead named from the `gc-x15c6`
incident is empty here, and the leak has since reappeared under other
names. That is the argument for a namespace *policy* rather than a
sweep hardcoded to one prefix.

**Correction to a premise in the bead description.** The bead cites
`grep -lE "worktree|stale_branch|orphan_branch" .beads/formulas/` as
returning zero hits. It no longer does — ten or more formulas match today.
The substantive claim survives: every match is worktree *creation*, or
the one-off teardowns in `mol-polecat-commit` / `mol-scoped-work` /
`mol-witness-patrol`. None is a reaper, and the `dog-*` line remains
exclusively Dolt and wisps.
