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

hours = float(sys.argv[1]) if len(sys.argv) > 1 else 24.0
root = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.claude/projects")
cutoff = time.time() - hours * 3600

sessions = {}   # sid -> {"reads": [...], "n": int, "cache_read_total": int}
files = 0
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

print(f"files scanned (mtime < {hours}h):  {files}")
print(f"sessions with usage records:      {len(sessions)}")
print(f"assistant requests:               {reqs}")
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
