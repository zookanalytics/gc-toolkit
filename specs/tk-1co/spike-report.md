---
name: Durable memory and learning capture — design spike
description: What the live Claude Code auto-memory corpus contains, measured and classified by durability need, and the recommendation on whether to version it, push its contents into rig artifacts, or both.
---

# Durable memory and learning capture — design spike

tk-1co asked four questions and parked itself for want of operating
experience. The corpus is now 96 days old and holds 708 files across seven
directories, so the questions are answerable. All measurements below were
taken on 2026-09-03 against the live host; §7 reproduces them.

The headline: durability is the smaller of the two problems. A quarter of
this rig's memories are already unreachable at session start, and 28% cite
machinery the pack deleted nine days ago. Backing the corpus up without
bounding it preserves the wrong thing.

## 1. What the corpus is

Seven populated directories under `~/.claude/projects/*/memory`, 708 files,
3,760,255 bytes. File counts are every file in the directory; gc-toolkit's 259
are 257 memories plus `MEMORY.md` and `MEMORY-hooks-archive.md`.

| Corpus | Files | Bytes | `MEMORY.md` |
|---|---|---|---|
| City root | 328 | 1,518,168 | 61 lines / 16,752 B |
| gc-toolkit (this rig) | 259 | 1,203,701 | 263 lines / 20,232 B |
| Other rig A | 64 | 201,155 | 63 lines / 13,170 B |
| Other rig B | 37 | 752,999 | 42 lines / 19,505 B |
| Other rig C | 16 | 77,575 | 36 lines / 9,129 B |
| dolt scratch dir | 2 | 5,573 | 3 lines / 256 B |
| User home | 2 | 1,084 | 3 lines / 159 B |

None of the seven is inside a git repository: `git -C <dir> rev-parse
--show-toplevel` fails for every one. The host has no backup tool installed
(no restic, borg, duplicity, snapper, or rsnapshot) and no backup systemd
unit. `~/.claude/backups` holds 464 KB of rotated `.claude.json` copies and
nothing else. `~/.claude` sits on a single ext4 volume at 94% use.
One `rm -rf`, one reinstall, or one full disk ends the corpus.

**Memory is shared per rig checkout, not per agent.** The directory keys on
the repository root rather than the session's working directory: this session
runs in a polecat worktree under the city's `.gc/worktrees/` tree and
was handed the rig-root memory directory. Of 96 project directories under
`~/.claude/projects`, 11 have a `memory/` subdirectory and 7 are populated,
while transcripts stay working-directory-keyed (this polecat's own transcript
directory holds 47 files and 33 MB). The gc-toolkit corpus names 170 distinct
`originSessionId` values across the 192 files that record one, nearly all
contributing a single file. Every role working the rig reads and writes one
pooled corpus.

**Growth.** The directory was created 2026-05-30 and holds 257 memories, a
net 2.7 additions per day. Since 2026-08-21, 93 files have been created or
rewritten, about 7 file-writes per day. The net figure assumes nothing was
deleted, which the index supports but does not prove.

## 2. Classification by durability need

Every memory in the gc-toolkit corpus is classified in
[corpus-classification.tsv](corpus-classification.tsv), one row per file,
with its index segment and whether it cites deleted machinery.

| Class | Count | What it is | Where else it could live |
|---|---|---|---|
| **A** Tool and shell lore | 54 (21%) | Behavior of `bd`, `gh`, `git`, `jq`, zsh, `go test`, coreutils, the agent harness | Nowhere in this repo. gc-toolkit does not own these tools. |
| **B** Gas City mechanism | 145 (56%) | How the refinery, polecat lifecycle, formulas, graph.v2, pools, convoys and bead routing actually behave | `docs/`, a formula step, a code comment |
| **C** Method and conduct | 49 (19%) | How to verify a claim, how to scope a finding, review discipline | A prompt fragment, via the feedback-learning loop |
| **D** Host and environment | 9 (4%) | This workstation's quotas, signing identity, disk, suite runtimes | Nowhere durable. Machine-scoped by nature. |

Three things follow.

**Class A is the pure durability case.** No artifact in any rig can hold
"`bd list --id a,b` drops unresolved ids at exit 0". It is expensive to learn,
cheap to store, and lost outright if the directory goes.

**Class B is the largest class and the most misfiled, but relocating it to
`docs/` costs reach.** These are operational sharp edges, and nothing inlines
a `docs/` file into an agent's context: the pack's fragments cite doc paths,
none includes their content, so a doc reaches an agent only when the agent
goes and reads it. Moving class B into `docs/` trades a reachable, fragile
store for a durable, unread one. It is also the class that rots fastest,
because it tracks pack internals that a rewrite moves wholesale: 44 of the 145
cite something deleted on 2026-08-25, against 13 of 54 in class A.

**Class C should not be in memory at all.** Forty-nine memories state a
standing rule about how an agent should work, and that class already has a
versioned, operator-gated home — an observation bead, the distiller, a
promotion PR into a prompt fragment. Each of these 49 is an observation that
was never filed. One of them, `process-rules-belong-in-config-not-memory`,
records the operator saying exactly this on 2026-07-22.

## 3. What is actually broken

### 3a. A quarter of this rig's memories are unreachable

`MEMORY.md` is 263 lines against a 200-line cap. Seven lines are preamble, so
the file holds 256 entries and the cap admits 193. The index this session
received ends at line 200; lines 201–263 are absent. **63 of the 256 indexed
memories are invisible to every session that starts in this rig**, and the
index is the only surface any session sees automatically. Individual files
are read on demand, by name, which requires knowing the name.

The cap is enforced inside the Claude Code binary; the warning text and
`lines (limit: ${M0})` are in the 2.1.259 bundle, and no key in
`~/.claude/settings.json` or variable in this session's environment exposes
it. The only lever the city holds is the number of entries.

The loss is arbitrary, not oldest-first. Mean age of the loaded 193 is 8 days
by mtime and 10 by birth time; the dropped 63 are 7 and 8. Both proxies reset
when a memory is rewritten, so neither separates the segments — position in
the file decides, and the dropped set spans all four classes (14 of 54 in A,
28 of 145 in B, 17 of 49 in C, 4 of 9 in D).

Index hygiene is otherwise sound: no broken links, and one file on disk
missing from the index (`refinery-tier2-shortcircuit-orphans-wisps.md`).

### 3b. The index holds about ten weeks of writing, so curation has to recur

The cap admits 193 entries and the corpus adds a net 2.7 a day, so an index
emptied to zero refills to the cap in 71 days. Every target is a matter of
weeks: compacting to 200 lines overflows with the next memory written, and
compacting to 150 lines leaves 50 entries of headroom, about 18 days.

A one-time cleanup is therefore not a fix, whatever number it hits. The only
thing that holds is a pass that runs more often than the corpus refills.

### 3c. 28% of the corpus cites machinery that no longer exists

Seventy-two of 257 memories name at least one artifact PR #465 deleted on
2026-08-25: `check-set-heal` in 24 files, `doc-keeper` in 20,
`reconcile-merged-prs` in 17, `quiesce-completed-workflows` in 9,
`mol-liveness-sweep` in 8.

That count is an upper bound on damage, not a count of wrong memories. In a
systematic sample of eight, two carry a claim whose subject is a deleted
script (`preopen-handback-machinery-dispatches-the-regate` asserts that
`reconcile-merged-prs.sh` dispatches the re-review), two carry a worked
example the deletion invalidates, and four name the deleted artifact only as
an illustration while their claim still holds. Separately, 32 memories carry
an explicit self-obsolescence marker (`SUPERSEDED`, `RESOLVED <date>`, "now
CLOSED", "retired"), flagged in place rather than removed.

Nothing has ever maintained this corpus. The pack's
`mol-doc-keeper-memory-audit` (added 2026-06-18, deleted 2026-08-25) was a
*consumer*: read-only by its own charter, it proposed `doc-update` beads
against the agent briefs and never edited memory. It also read only the city
root directory. Its removal was an operator scope decision
(`specs/2026-08-rewrite/plan.md:220`, the whole `mol-doc-keeper-*` family),
so restoring it is not the answer and would not have helped if it had
survived.

## 4. The bead's four questions, answered

**Which learning needs memory rather than a rig artifact?** Class A, and
class B until something makes `docs/` reachable. Class C belongs in prompt
fragments and class D belongs nowhere durable.

**How often is memory read versus written, and what goes stale fastest?**
Written about 7 file-writes a day on this rig. Read once per session start
for the index, plus on-demand reads of named files. Class B rots fastest,
at 30% citing deleted machinery.

**Version the directory, or push durable items out of it?** Both, and neither
alone. Versioning a corpus that is 28% stale-citing and 25% unreachable
preserves the wrong thing; discipline alone has already failed, since the
corpus reached 257 entries under the current discipline, and class A has no
rig home to be pushed into.

**Does learning have cross-agent value that per-agent memory cannot
deliver?** The premise is wrong in one direction and right in another.
Memory is not per-agent: 170 sessions across every role write this one rig
corpus, so within a rig the sharing already works. What does not cross is
*rigs*. Exactly one slug appears in two corpora
(`bd-close-actor-identity-mismatch`), yet the same tool facts are being
learned twice under different names:

- one rig's `gh-rollup-keeps-stale-check-runs` and gc-toolkit's
  `gh-pr-checks-vs-statuscheckrollup` are both "statusCheckRollup carries
  superseded check runs; filter or use `gh pr checks --required`".
- another rig's `jq-index-rebinds-dot` and gc-toolkit's
  `jq-index-arg-evaluated-against-the-array` are both "jq's `index()`
  rebinds `.` to the array".

gc-toolkit holds 33 tool-lore memories; every other rig holds 0 to 3. Class A
is rig-independent knowledge that each rig pays to re-derive.

## 5. Recommendation

**Hybrid: export the corpus to git without hosting git inside it, and bound
what goes in.** Three moves, in the order they pay off.

### Move 1 — export, do not host

A nightly read-only copy of every `~/.claude/projects/*/memory` into a git
repo, one commit per run, nothing written back.

Never `git init` inside the live directory. 170 distinct sessions write this
corpus, Claude Code owns the directory's lifecycle, and an agent-run `git add
-A` under concurrent writers is a corruption path. An export has no such
coupling and no failure mode that reaches a running agent.

Destination is the town repo, not gc-toolkit: the corpus carries private rig
names and absolute host paths, which the tk-6s5 public-pack primitive keeps
out of gc-toolkit artifacts. Cost is 3.76 MB at the first commit, then a daily
delta this spike measured only for this rig: about 7 files a day (§1 — 93
created or rewritten in the 13 days to 2026-09-03). The other six corpora were
not measured, so the all-corpus daily total runs higher and is not derived
here.

This is the smallest of the three moves and the only one that addresses the
concern the bead was filed for. It should not be mistaken for the fix.

### Move 2 — bound the index

A recurring pass that merges related memories and retires the ones whose
subject the pack deleted. Per §3b the cadence is the load-bearing part: the
index refills from empty in 71 days, so a pass that runs monthly holds and a
one-time compaction does not, whatever number it hits. Per §3c there is a
large, identifiable retirement set for the first run to work from.

This is new work, not a restoration. The dropped memory audit never
maintained the corpus and its removal was a deliberate scope decision; a
curator is a different job from the consumer that was cut.

### Move 3 — send conduct rules to the learning loop

Class C is 49 misfiled observations. The change is guidance, not machinery:
the memory-writing instructions and the agents' feedback-observation section
both need to say that a rule about how an agent works is an observation bead,
not a memory file. That rides the ordinary promotion pipeline under D3.

### Not recommended yet — cross-rig sharing

The two duplicate-fact pairs in §4 are real but they are two instances. If
the operator wants class A shared across rigs, the design is already on file
as option C's `lessons/all/` surface, and it depends on the hot tier deferred
under D2. This spike does not reopen that.

## 6. Work filed

| Move | Bead | Status |
|---|---|---|
| Move 2, one-time compaction of this rig's index |  **tk-mb8pp3** | filed, routed to the gc-toolkit polecat pool |
| Move 1, export | none | needs the operator's destination decision (§5) |
| Move 2, recurring curator | none | file once the operator accepts §5 |
| Move 3, guidance change | **tk-e9j751** | filed as an observation; enters the distiller's promotion pipeline, not the polecat pool |

The one-time compaction is filed now because it needs no decision: 63
memories are unreachable whichever way §5 is answered, and the remedy is
fewer index entries.

It also retires memories from a store with no backup, so tk-mb8pp3 requires
the full text of every retired file to be committed under `specs/tk-mb8pp3/`.
That makes the retirement reversible without waiting on Move 1. If the
operator would rather the export land first, hold tk-mb8pp3 until it does.

## 7. Reproducing the measurements

Read-only. Runs anywhere on the city host.

```bash
# §1 corpus size, and that nothing is versioned
for d in ~/.claude/projects/*/memory; do
  [ -d "$d" ] || continue
  printf '%4d files %8d bytes  %s  git=%s\n' \
    "$(find "$d" -type f | wc -l)" "$(du -sb "$d" | cut -f1)" \
    "$(basename "$(dirname "$d")")" \
    "$(git -C "$d" rev-parse --show-toplevel 2>&1 | head -c 24)"
done

# §3a index over cap, and which entries fall past line 200
M=$(echo ~/.claude/projects/*-rigs-gc-toolkit/memory/MEMORY.md)
wc -l "$M"; sed -n '201,$p' "$M" | grep -c '](.*\.md)'

# §3c memories citing machinery deleted in PR #465
D=$(dirname "$M")
grep -rlE 'check-set-heal|reconcile-merged-prs|reconcile-gate-verdicts|quiesce-completed-workflows|recover-stranded-branches|escalation-gate\.sh|doc-keeper|mol-liveness-sweep|mol-triage-recurrence' \
  "$D" | grep -v MEMORY | wc -l
```

Compaction, when it runs, writes to a directory with live concurrent writers.
Snapshot first and reconcile afterwards, because another session may append
an entry mid-pass:

```bash
PRE=/tmp/MEMORY.pre.$(date +%s).md
cp "$M" "$PRE"                              # before editing
diff <(grep -o '](.*\.md)' "$PRE" | sort -u) \
     <(grep -o '](.*\.md)' "$M" | sort -u)  # after: only intended drops
```

## 8. What this spike did not measure

- **Recall usefulness.** Nothing records which memories an agent actually
  used. The index is injected every session and individual files are read by
  name, but no counter distinguishes a memory that changes behavior from one
  that is never opened. Option C's `events.jsonl` is the design that would
  answer it.
- **Correctness of the 185 memories that cite nothing deleted.** §3c bounds
  staleness from one direction only, by citation of removed artifacts.
- **The byte arm of the index cap.** The binary enforces a line-length and
  byte limit alongside the 200-line one; only the line cap bound here, and its
  companion values were not determined.
- **The other six corpora.** §2's classification covers gc-toolkit's 257
  memories. §1 and §4 cover all seven directories, but the city root's 328
  files are unclassified.
