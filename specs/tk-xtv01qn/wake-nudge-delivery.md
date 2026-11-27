---
name: How a typed wake nudge reaches a Claude Code session
description: What happens between gc typing a pool slot's wake nudge and the session receiving it, where the polecat nudge's first 1022 bytes were lost, and why a nudge stays within 800 bytes. Read it before changing a nudge's size or how gc delivers one, or to rerun the census of wake-nudge delivery.
---

# How a typed wake nudge reaches a Claude Code session

The polecat wake nudge was 1156 bytes. From 2026-10-26, when it grew past 1022
bytes, until Claude Code 2.1.329, about half of polecat wakes received only its
last 134 bytes. Every wake that received the nudge's head got it as pasted
material rather than as the session's own instruction. The nudge now stays within 800
bytes, so it reaches the session in one read as typed text.

## The path a nudge takes

1. **gc types it.** At a session's start, `nudgeStartupSession` calls
   `nudgeSession` (gascity `internal/runtime/tmux/tmux.go`, the same at the
   installed build 6589a7df45 and at upstream main 21ad051d00). On an empty
   input box it types the nudge with `sendLiteralText`, waits 500 ms and sends
   Enter. `sendLiteralText` types text of at most 4096 bytes with
   `tmux send-keys -l`, unless it is multi-line text for Codex, and pastes
   longer text with `tmux paste-buffer -p`.
2. **The pty splits it.** A macOS pty hands the program at most 1022 bytes per
   read. A raw-mode reader in a tmux pane got each 1156-byte `send-keys -l` as
   reads of 1022 and 134 bytes, 0.12 ms apart, in 3 of 3 sends.
3. **Claude Code sorts each read.** In the Claude Code 2.1.330 bundle, the
   input hook takes a key event whose text is longer than 800 characters
   (`var jL=800`) as a paste. The prompt stores it behind a `[Pasted text #N]`
   placeholder, and on submit the stored text goes to the model inside
   `<pasted_content>` tags, which Claude Code's system prompt says may hold
   instructions the user did not write. A read of 800 characters or fewer is
   typed text. So the 1156-byte nudge became a paste of 1022 bytes and a typed
   tail of 134.
4. **The input box can keep only one piece.** The paste and the typed tail
   update the input box separately. Through Claude Code 2.1.328, the head
   was often lost (the census below). Probes on 2.1.330 still lost the tail
   in 2 of 46 trials.

## The census

Each wake is one Claude transcript of a polecat slot, in any rig, whose first
message is the slot's wake prompt. It is classed by the text delivered to the
session: queue-operation enqueues, queued_command attachments and string user
messages after the wake prompt, never tool output. The wakes from 2026-11-10
to 2026-11-23 07:10Z, by Claude Code version:

| Version | Wakes | Whole | Tail only | No nudge |
|---|---|---|---|---|
| 2.1.321 | 73 | 36 | 37 | 0 |
| 2.1.322 | 664 | 366 | 298 | 0 |
| 2.1.323 | 306 | 163 | 118 | 25 |
| 2.1.325 | 755 | 331 | 423 | 1 |
| 2.1.326 | 266 | 127 | 139 | 0 |
| 2.1.327 | 174 | 67 | 107 | 0 |
| 2.1.328 | 107 | 46 | 61 | 0 |
| 2.1.329 | 191 | 190 | 0 | 1 |
| 2.1.330 | 299 | 298 | 0 | 1 |

The tail-only wakes stopped when the host moved to Claude Code 2.1.329 on
2026-11-19. gc's installed build dates from 2026-11-13 and the nudge from
2026-10-26, so neither changed then. In all 1624 wakes that received the head,
the head arrived inside `<pasted_content>` tags, followed by the typed tail.

The two wakes on 2.1.329 or later that received no nudge each queued an entry
1.3 and 2.1 seconds after the wake prompt. The transcript records that entry
without its text and never delivers it, and nothing in either transcript holds
the nudge. Why is not known. A probe that queued the typed 766-byte nudge
behind a bash-mode command left the same textless record, so the record alone
does not show a paste.

## The probes

Each probe ran Claude Code 2.1.330 in a tmux server on a private socket, in an
empty scratch directory, and typed the text the way gc does. It read the input
box from `tmux capture-pane` 500 ms later. A probe never submits the nudge to a
model, because the nudge tells the session to run `gc hook --claim`. To see what
a submit queues, it typed the nudge and Enter behind a bash-mode `!sleep` and
killed the session before the queue ran.

- **The 1156-byte nudge, typed:** both pieces in 44 of 46 trials (idle, behind
  a bash-mode command, as a fresh session's input box first appeared, and
  during a first model turn), and the placeholder alone in 2.
- **The same text as one bracketed paste:** one placeholder in 28 of 28 trials.
  Pasting the same text again expands a placeholder in place, and one such
  check expanded it to all 1156 bytes.
- **The 766-byte nudge, typed:** whole and typed, with no placeholder, in 10 of
  10 fresh sessions and in 4 of 4 during a first model turn. Behind a running
  command it queued as one typed message.

## Why the fix is the nudge's size

A nudge of at most 800 bytes reaches Claude Code in one read, within the pty's
1022 bytes, and Claude Code takes it as typed text. So it arrives whole, whatever
the input box does with two pieces, and in the session's own words. A
bracketed paste from gc would also deliver the whole nudge, but as pasted
material, which upstream gastownhall/gascity#7669 reports for gc's paste above
4096 bytes. `assets/scripts/pool-nudge-wiring.test.sh` holds every pack nudge
to 800 bytes.

## What stays open

- gc still types any message of at most 4096 bytes. Into a Claude Code pane,
  one over 800 bytes arrives as pasted material, and on macOS one over 1022
  bytes splits. This is gc-6wle4l in the Gas City fork's store, held for
  placement. gc-emhlct's opener design, whose wakes type an opener, carries a
  note on the same limit.
- Claude Code's input box keeping only one of two back-to-back pieces is the
  upstream finding tk-19xc6mt.

## Rerunning the census

The census reads the transcripts under `~/.claude/projects`, deduplicated by
real path because account homes can share one projects directory:

```python
"""python3 -I census.py <since, ISO-8601 UTC> [<projects dir>]"""
import glob, json, os, sys
from collections import Counter

since = sys.argv[1]
projects = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser('~/.claude/projects')
slots = os.path.join(projects, '*-polecats-gc-toolkit-polecat-[0-9]', '*.jsonl')
HEAD, TAIL = 'Claim and complete one work item', 'orphan recovery returns the'

def read(path):
    first, start, version, texts = None, None, '?', []
    with open(path, errors='replace') as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            start = start or d.get('timestamp')
            version = d.get('version') or version
            kind, att = d.get('type'), d.get('attachment') or {}
            content = (d.get('message') or {}).get('content')
            if kind == 'user' and isinstance(content, str):
                if first is None:
                    first = content
                else:
                    texts.append(content)
            elif kind == 'queue-operation' and d.get('operation') == 'enqueue' and isinstance(d.get('content'), str):
                texts.append(d['content'])
            elif kind == 'attachment' and att.get('type') == 'queued_command' and isinstance(att.get('prompt'), str):
                texts.append(att['prompt'])
    return first, start, version, texts

tally = Counter()
for path in sorted({os.path.realpath(p) for p in glob.glob(slots)}):
    try:
        first, start, version, texts = read(path)
    except OSError:  # a transcript removed since the glob
        continue
    if not first or 'gc-toolkit.polecat-' not in first[:120] or not start or start < since:
        continue
    heads = [t for t in texts if HEAD in t]
    tail = any(TAIL in t for t in texts)
    if heads:
        got = 'whole' if tail else 'head only'
        how = 'pasted' if any('<pasted_content' in t.split(HEAD)[0][-200:] for t in heads) else 'typed'
    else:
        got, how = ('tail only' if tail else 'no nudge'), '-'
    tally[(version, got, how)] += 1
for (version, got, how), n in sorted(tally.items()):
    print(f'{version}\t{got}\t{how}\t{n}')
```

Once the 766-byte nudge is live, every wake should read `whole` and `typed`.
