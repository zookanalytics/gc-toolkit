---
name: Verification of the converse sittings' compaction (tk-kwnt509)
description: What Gas City resolves for every agent's context advisory on main and on this change, and one real compaction of a Claude session carrying the converse-compact overlay, with the summary it produced. Read it when reviewing whether the advisory is off for the sittings alone, or what the PreCompact steer does to a summary.
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
