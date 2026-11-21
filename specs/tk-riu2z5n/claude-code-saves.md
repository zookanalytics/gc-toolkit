---
name: What a Claude Code save rewrites in a memory note (tk-riu2z5n)
description: The probes and code reading behind the memory intake's list hash, which reads a note's body alone because Claude Code writes only its front matter when an agent saves it. Read it before changing that hash, or when a Claude Code release may have changed how it stamps memory notes.
---

# What a Claude Code save rewrites in a memory note

Measured on 2026-11-14 with Claude Code 2.1.325, for the rework of the memory
intake's use record (tk-riu2z5n, PR #1507). The intake's list hash must leave
out what Claude Code itself writes on a save, so a recorded use does not bring a
note due. `gctk memory` (tk-zlot608.8) takes this record as the evidence for
hashing a note's body alone.

## How it was measured

Four headless runs (`claude -p`, haiku, Read, Edit and Write only, no settings
files, no MCP servers, every `GC_*` and `BEADS_*` variable unset) were given a
scratch directory as `autoMemoryDirectory`. Each run's first record named that
directory as its memory directory. Each run read throwaway notes there and used
its Edit tool, or once its Write tool, to add a use line. The notes were copied
before and after every run and compared with `diff`. The scratch directory sat
under a symlinked path, and a path that runs through a `.claude` folder must be
given resolved: Claude Code refused an Edit through the symlinked form as a
sensitive file.

The stamping code was then read in the Claude Code binary, whose bundled source
is minified. It sits beside the warning `stampNewMemoryContent: not dating`.

## What a save rewrites

| The note | What the save wrote besides the agent's line |
|---|---|
| Front matter with `originSessionId` (stamped), Edit by the session that stamped it or by another | `metadata.modified` set to the save's time, in place. `originSessionId` kept its first session. Nothing else moved. |
| Front matter without `originSessionId`, Edit (the first save) | The front matter written again as YAML: `node_type: memory` first under `metadata`, `originSessionId` and `modified` last, a value quoted where it needs it (`'`, `: `, `,`, `"`, `#`), single quotes made double, the name made a slug (`G Note With Caps` became `g-note-with-caps`), top-level keys other than the name and description moved under `metadata` ahead of its own keys, a list indented under its key, a comment line and an empty key dropped, and one blank line before the body. A long value stayed on one line. |
| The same, with CRLF line endings | The three keys inserted as lines ending in CR, the rest left as it was. |
| No front matter | Nothing. |
| Front matter that an agent's Write replaced without the stamp | Stamped again with the writing session's id, as a first save. |

The code agrees with the runs. A save of content whose metadata holds no
`originSessionId` stamps it, and its main path writes the front matter again
from its parsed values. The CRLF note shows a path that inserts the keys
instead, which this reading did not trace. Any other save only sets or adds the
`modified` line, and leaves the file as written when it finds no faithful place
for that line. Claude Code treats five metadata keys as its own:
`node_type`, `originSessionId`, `modified`, and `claudeCodeItem` and
`typedTurn`, which belong to a provenance record that none of these runs wrote.

## What the list hash reads

`gctk memory` hashes a note's body: the text after its front matter, without
its leading blank lines or its use lines. A save writes only front matter, the
blank line before the body included, and leaves a note with no front matter
alone, so no save above changes that hash, and only the agent's Write that
changed the body would. A change to the front matter alone, such as a reworded
description, does not bring a note due either, which is the cost of not
parsing front matter at all.

## A side observation

In one run the prompt told haiku to add a given line and change nothing else.
It added the line and said that it ignored the note's request to record uses as
an embedded instruction. That run tested nothing about whether agents record
their uses.
