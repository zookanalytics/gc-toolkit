#!/usr/bin/env python3
"""Per-request context cost from Claude Code transcripts.

The tk-23wdf ledger measured BYTES PER SPAWN. That understates the real
cost: the seed (system prompt + tool schemas + skills appendix) is re-read
on EVERY request of a session, not once. This reports the per-request view.

Seed proxy per session = the minimum non-zero cache_read_input_tokens seen
across that session's assistant turns. The first cached request reads back
only the stable prefix; every later one reads that prefix plus accumulated
conversation, so the minimum isolates the prefix.

Usage: measure-per-request.py [hours_back] [projects_dir]
"""
import json, os, sys, time, statistics
from datetime import datetime, timezone

hours = float(sys.argv[1]) if len(sys.argv) > 1 else 24.0
root = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.claude/projects")
cutoff = time.time() - hours * 3600


def in_window(ts):
    """Is this assistant turn inside the window?

    THE FILE MTIME IS NOT THE TURN'S TIME. Filtering files by mtime only
    narrows which files are opened; a session that started three days ago and
    was touched five minutes ago carries every one of its old turns into a
    "trailing 24h" figure. Measured on this transcript set at the time this was
    fixed: 1,217 assistant records older than the cutoff were sitting inside
    recently-touched files, worth ~1.2k phantom requests and ~2 points of the
    seed-reread share (tk-yhwfv.1 signoff, P1).

    An UNDATED or unparseable record is not counted. It cannot be shown to be
    in the window, and this figure is quoted as a windowed one; the count of
    what was dropped is reported so the exclusion is never silent.
    """
    if not ts:
        return False
    try:
        # Transcripts stamp UTC as "...Z"; fromisoformat wants an offset.
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() >= cutoff
    except ValueError:
        return False


sessions = {}   # sid -> {"reads": [...], "n": int, "cache_read_total": int}
files = 0
out_of_window = 0   # assistant turns inside a touched file but older than the cutoff
undated = 0         # assistant turns with no readable timestamp — excluded, and said so
for dirpath, _, names in os.walk(root):
    for n in names:
        if not n.endswith(".jsonl"):
            continue
        p = os.path.join(dirpath, n)
        try:
            if os.path.getmtime(p) < cutoff:
                continue
        except OSError:
            continue
        files += 1
        try:
            fh = open(p, "r", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                msg = d.get("message")
                if not isinstance(msg, dict) or msg.get("role") != "assistant":
                    continue
                u = msg.get("usage")
                if not isinstance(u, dict):
                    continue
                ts = d.get("timestamp", "")
                if not in_window(ts):
                    undated += 1 if not ts else 0
                    out_of_window += 1 if ts else 0
                    continue
                sid = d.get("sessionId") or d.get("session_id") or p
                s = sessions.setdefault(sid, {"reads": [], "n": 0, "tot": 0, "first": None})
                cr = int(u.get("cache_read_input_tokens") or 0)
                cc = int(u.get("cache_creation_input_tokens") or 0)
                s["n"] += 1
                s["tot"] += cr
                if cr > 0:
                    s["reads"].append(cr)
                if s["first"] is None:
                    s["first"] = cr + cc   # turn-1 prompt = seed + first user msg

seeds, uppers, reqs, tot_reads, seed_rereads = [], [], 0, 0, 0
for sid, s in sessions.items():
    reqs += s["n"]
    tot_reads += s["tot"]
    if s["reads"]:
        seed = min(s["reads"])
        seeds.append(seed)
        seed_rereads += seed * len(s["reads"])
    if s["first"]:
        uppers.append(s["first"])

print(f"files touched within {hours}h:      {files}")
print(f"sessions with usage records:      {len(sessions)}")
print(f"assistant requests (in window):   {reqs}")
print(f"  turns dropped, older than cutoff: {out_of_window:,}")
if undated:
    print(f"  turns dropped, undated:           {undated:,}")
if seeds:
    print(f"median seed (tokens/request):     {int(statistics.median(seeds)):,}")
    print(f"mean seed:                        {int(statistics.mean(seeds)):,}")
    if uppers:
        print(f"median turn-1 prompt (UPPER):     {int(statistics.median(uppers)):,}")
    print(f"median requests/session:          {int(statistics.median([s['n'] for s in sessions.values()]))}")
    print(f"cache-read tokens total:          {tot_reads:,}")
    print(f"  of which seed re-reads:         {seed_rereads:,} ({100*seed_rereads/tot_reads:.1f}%)" if tot_reads else "")
    med = statistics.median(seeds)
    med_reqs = statistics.median([s['n'] for s in sessions.values()])
    print()
    print(f"amplification: one byte cut from the seed is paid back")
    print(f"  1x on the cache write + 0.1x on each of ~{int(med_reqs)-1} re-reads")
    print(f"  => ~{1 + 0.1*(med_reqs-1):.2f}x its per-spawn face value")
