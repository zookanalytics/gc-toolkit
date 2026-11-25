---
name: Verification of the converse sittings' compaction (tk-kwnt509)
description: What Gas City resolves for every agent's context advisory on main and on this change, real compactions of Claude sessions carrying the converse-compact overlay with the summaries they produced, and the hook refusing a typed compaction once the session's tmux environment holds Gas City's drain flag, with the idle compaction that could not be staged. Read it when reviewing whether the advisory is off for the sittings alone, what the PreCompact steer does to a summary, or whether a finished sitting is compacted.
---

# Verification of the converse sittings' compaction

## The context advisory each agent resolves

Two scratch cities, never started, each import the pack into one rig, `probe`:
one from an archive of `origin/main` at 3a8eab943, one from this change's
worktree. Gas City's own resolver ran over each city's composed config: a test
in Gas City's `internal/config` package, injected with `go test -overlay` so
the checkout was untouched, loaded each city with `LoadWithIncludes` and called
`ResolveContextAdvisory` with the built-in default, the city's
`[agent_defaults]` and each agent's own table, the order
`contextInjectLineForSample` uses. The city's installed gc read the same
configs with `gc config show --json`.

| Agents | main | this change |
|---|---|---|
| converse-claude-opus, converse-claude-fable, converse-opus, converse-fable, converse-codex, converse-codex-sol, converse-codex-astra | enabled, tiers 60 and 80 | disabled |
| polecat, polecat-codex, proactive, refinery, witness, po, demo, deacon, mechanik, and gc's implicit provider agents claude, codex and gemini | enabled, tiers 60 and 80 | enabled, tiers 60 and 80 |

`gc config show --json` agrees. The composed agents differ between the two
sides in eleven fields and nowhere else: `ContextAdvisory` is
`{"Enabled": false}` on the seven converse agents and stays unset on every
other agent, and `OverlayDir` moves from `overlays/gh-origin-guard` to
`overlays/converse-compact` on the four Claude converse agents. The
`validation` block is the same on both sides. The live city sets no advisory
of its own (`.config.AgentDefaults.ContextAdvisory` is unset), so every agent
there resolves to the built-in default today.

## One real compaction with the steer

A scratch home held the overlay as Gas City stages it, `.claude/settings.json`
and `.claude/hooks/converse-compact.md`. Claude Code 2.1.330 ran there in print
mode on `claude-opus-5-5`, with `--setting-sources project`, so the overlay's
settings were the only ones loaded and Gas City's own PreCompact hook did not
run. The first turn gave the session a sitting's state: the entry command, the
lines the entry printed (`CONVERSATION=tk-demo1`, `SUBJECT=tk-subj1`,
`GATES=tk-gate7` and a `CONV` path) and a `holding:` line already on the
conversation's notes. The second turn was an operator ruling, typos included,
that nothing recorded, and the session answered it with a hand-back. A third
call ran `/compact` (trigger `manual`, 19,332 tokens before and 4,432 after).

The summary added these parts to its usual sections, quoted here as written
but for the `CONV` path, shortened to `<city>`:

```text
Part 1: What the operator said that the record does not hold yet (no time was shown):
   - "ok so merge it, but keep the old rankng path behind a flag for a week befor we delete it. and dont touch the helm board's colors in this PR, that goes in its own."

Part 2: Where the decision stands:
   - The decision held in the notes was: "Rule: merge the ranking move as it stands (recommended), or split the color change out first". The operator has ruled for splitting the colors out and then merging the ranking move, with the old path kept behind a flag for one week.
   - What is still open is carrying out the ruling and recording it. One option is to split the colors out first and then merge with the old path flagged; this costs an extra PR and a flag to maintain for a week. The other option, merging as it stands, is now ruled out. A follow-up to delete the old path after a week is still to come.
   - The last hand-back, word for word:
     "tk-subj1 — board ranking move
     You've ruled to merge the ranking move into gctk but keep the old ranking path behind a flag for one week before it's deleted. The helm board's color change comes out of this PR and goes into its own.
     Decision: Recommend splitting the color change out first, then merging the ranking move with the old path flagged. Once the week is up, delete the old path in a follow-up."

Part 3: The record's names (exactly as the entry last printed them):
   CONV=<city>/rigs/gc-toolkit/assets/scripts
   CONVERSATION=tk-demo1
   SUBJECT=tk-subj1
   GATES=tk-gate7
   (The entry printed no WORK or AGREED lines.) This sitting filed, sent or answered no other beads, gates or PRs.

9. Optional Next Step / Part 4: What to do first:
   Before anything else, run the converse entry again with the exact command this session used:
   "$(gc gc-toolkit scripts-dir)/converse-entry.sh"
   Then act on the ENTRY and NEXT lines it prints. The entry re-reads from the record where the sitting stands. After that, record the operator's ruling quoted in Part 1, since it is not in the notes yet.
```

The operator's words came through with their typos, the hand-back came through
whole, the four entry lines came through as printed, and the summary ended on
the entry command. Claude Code then appended its own closing lines, which tell
the session to pick up the last task, so the steer's instruction to run the
entry first comes before them.

## A finished sitting is not compacted

Run on 2026-11-25 with Claude Code 2.1.332 on `claude-haiku-5-5` and tmux 3.8,
on a private tmux server (`tmux -L kwnt-proof -f /dev/null`). Each session ran
interactively in a pane of its own, in a scratch home that held this change's
`.claude/settings.json` byte for byte and its steer, as Gas City stages the
overlay, with `GC_DIR` naming the home. The pane's command passed on the
`TMUX` and `TMUX_PANE` tmux gave it and none of the caller's Gas City
variables. `--setting-sources project,local` kept the user's settings out, and
Gas City's own hooks, which it hands a sitting with `--settings`, were not
loaded. The home's `.claude/settings.local.json` held a second PreCompact hook
that only appends the hook's input to a log, so each run of the hook is counted
with its trigger. The flag was written the way Gas City writes it,
`set-environment -t =<session> GC_DRAIN_ACK 1`, and removed the way
`gc runtime undrain` removes it, `set-environment -t =<session> -u
GC_DRAIN_ACK`. The log of each step, the session ids and each session's hook
log are in `/Users/gc/.cache/tk-kwnt509/refuse-2026-11-25/`.

**A typed `/compact`.** Session C took two turns standing in for a sitting's
thread: the entry's lines with the hand-back and the fact it rests on, and an
operator ruling with typos that nothing recorded. With the flag set,
`/compact` was refused. The hook ran once, with the trigger `manual`, the
transcript holds no compaction, and Claude Code printed the hook's command and
its stderr line:

```text
❯ /compact
  ⎿  Compaction blocked by PreCompact hook: [<the hook's command>]: This sitting has ended (its tab reads done), so it is not compacted.
```

With the flag removed, the next `/compact` ran, the hook's second run
(`manual`, 38,064 tokens before and 5,688 after). Its summary quoted the
ruling with its typos, the hand-back and the four entry lines, and carried the
steer's newer parts:

```text
   - Supporting fact: 41 of 110 long waits were not compacted. Source: tk-subj2 notes, census block of 2026-11-25.
[...]
9. Optional Next Step:
   - Run the converse entry again before anything else, using the same command this session used (not shown in this transcript, so the sitting must reuse the exact command it has). Act on the ENTRY and NEXT lines it prints.
   - Work from this summary and from what the entry prints. Re-read only what the operator's message needs.
```

The same summary also listed the steps a sign-off owes, though no sign-off had
run in the session, which part 4 asks for only when one has.

**The idle compaction could not be staged.** Sessions A and B were built like
C, except that each first read nine files of the repository's docs, about 550
KB, before C's two turns. That left threads of 242,569 and 242,617 tokens on
the one-hour cache, over the idle compaction's threshold, which
`CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=100000` lowered to 100,000. A's flag was
set at 18:54:49Z, after its last turn ended at 18:54:29Z, and B had none.
Claude Code times an idle compaction at 0.9 of the cache's hour after the last
activity, about 19:48:30Z here. By 19:54:03Z neither session had run a
PreCompact hook or compacted, so Claude Code passed over the idle compaction
before any hook ran, in both, for a reason it records nowhere on the host. On
the same version a sitting of this city was compacted with the trigger `auto`
at 2026-11-25T05:32:42Z, at 249,201 tokens, far below a full window, so the
idle compaction still fires there. The idle path rests on the documentation:
the `auto` matcher covers idle compaction, and "If compaction was triggered
proactively before the context limit, Claude Code skips it and the conversation
continues uncompacted" ([hooks](https://code.claude.com/docs/en/hooks),
"PreCompact"). The hook runs the same command for every trigger, and the typed
refusal above shows its read and its exit in a live session. In the refused
session C the hook ran once on the refused `/compact` and once on the one that
compacted. Whether Claude Code tries a refused idle compaction again rests on
the binary: its idle timer is cleared when it fires and is armed again only
from a new request's saved state (`EVn`, Claude Code 2.1.332).
