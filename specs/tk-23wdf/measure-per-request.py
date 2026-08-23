#!/usr/bin/env python3
"""Per-request context cost from Claude Code transcripts.

The tk-23wdf ledger measured BYTES PER SPAWN. That understates the real
cost: the seed (system prompt + tool schemas + skills appendix) is re-read
on EVERY request of a session, not once. This reports the per-request view.

Seed proxy per session = the minimum non-zero cache_read_input_tokens seen
across that session's assistant turns. The first cached request reads back
only the stable prefix; every later one reads that prefix plus accumulated
conversation, so the minimum isolates the prefix.

THE WINDOW BOUNDS THE COUNTS, NOT THE EVIDENCE. Two different questions are
being asked of the same records and they need different populations:

  * "how many requests, and how many tokens, in the last N hours?" — counts
    ONLY turns whose own timestamp is inside the window.
  * "what is this session's seed?" — needs the session's WHOLE history,
    including turns older than the cutoff.

Filtering both by the cutoff is wrong in a way that inflates the headline. A
session that started before the window and continued into it has only its
tail in view, and a tail's minimum cache_read is seed PLUS all the
conversation accumulated before the cutoff. Worked example (tk-yj432 signoff,
P1): one pre-window turn at 1,000 tokens and one in-window turn at 20,000
reports seed=20,000 and a 100% seed-reread share, where the truth is
seed=1,000 and 5%. So every record in a touched file is parsed; the cutoff is
applied per-turn, at the point of counting.

Usage: measure-per-request.py [hours_back] [projects_dir]
"""
import json, os, sys, time, statistics
from datetime import datetime, timezone

hours = float(sys.argv[1]) if len(sys.argv) > 1 else 24.0
root = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.claude/projects")
cutoff = time.time() - hours * 3600


def stamp(ts):
    """Epoch seconds for a transcript timestamp, or None if unreadable.

    THE FILE MTIME IS NOT THE TURN'S TIME. Filtering files by mtime only
    narrows which files are opened; a session that started three days ago and
    was touched five minutes ago carries every one of its old turns into a
    "trailing 24h" figure. Measured on this transcript set at the time this was
    fixed: 1,217 assistant records older than the cutoff were sitting inside
    recently-touched files, worth ~1.2k phantom requests and ~2 points of the
    seed-reread share (tk-yhwfv.1 signoff, P1).

    An UNDATED or unparseable record cannot be placed in or out of the window,
    so it is never counted as a request and never treated as a first turn. The
    number dropped is reported, so the exclusion is not silent.
    """
    if not ts:
        return None
    try:
        # Transcripts stamp UTC as "...Z"; fromisoformat wants an offset.
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


sessions = {}
files = 0
out_of_window = 0   # assistant turns in a touched file, older than the cutoff
undated = 0         # assistant turns with no readable timestamp
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
                t = stamp(d.get("timestamp", ""))
                if t is None:
                    undated += 1
                    continue
                inside = t >= cutoff
                if not inside:
                    out_of_window += 1
                sid = d.get("sessionId") or d.get("session_id") or p
                s = sessions.setdefault(sid, {
                    "reads": [],        # every observed cache_read > 0, in window or not
                    "n_win": 0,         # requests INSIDE the window
                    "tot_win": 0,       # cache-read tokens INSIDE the window
                    "reads_win": 0,     # in-window turns that read cache
                    "first_t": None,    # earliest observed turn, by timestamp
                    "first_val": 0,     # its cache_read + cache_creation
                })
                cr = int(u.get("cache_read_input_tokens") or 0)
                cc = int(u.get("cache_creation_input_tokens") or 0)
                # Seed evidence: collected from the WHOLE history.
                if cr > 0:
                    s["reads"].append(cr)
                if s["first_t"] is None or t < s["first_t"]:
                    s["first_t"], s["first_val"] = t, cr + cc
                # Counts: in-window turns only.
                if inside:
                    s["n_win"] += 1
                    s["tot_win"] += cr
                    if cr > 0:
                        s["reads_win"] += 1

# Only sessions ACTIVE in the window describe per-request cost in the window.
# Their seed is still estimated from full history above.
active = {sid: s for sid, s in sessions.items() if s["n_win"] > 0}

seeds, uppers, reqs, tot_reads, seed_rereads = [], [], 0, 0, 0
no_first_turn = 0
for sid, s in active.items():
    reqs += s["n_win"]
    tot_reads += s["tot_win"]
    if s["reads"]:
        seed = min(s["reads"])
        seeds.append(seed)
        seed_rereads += seed * s["reads_win"]
    # The upper bound is "the whole prompt at turn 1", so it must come from the
    # session's EARLIEST turn — not its earliest in-window one, which is the
    # substitution this fix exists to remove. A session's records live in one
    # transcript file and every file is read from byte 0, so the earliest dated
    # record IS that transcript's first turn. A session with no dated record at
    # all cannot supply one and is omitted, counted, and reported.
    #
    # REJECTED, and worth stating so it is not re-proposed: additionally
    # requiring that first turn to have cache_read == 0 (i.e. to have CREATED
    # its cache rather than read one). It sounds like a stronger proof of
    # turn-1-ness and is not — the cache is shared across sessions, so a genuine
    # turn 1 normally reads a warm prefix. Measured on this set it omitted 967
    # of 987 sessions and computed the median from the 20 survivors, which is a
    # worse statistic than the one it was meant to protect.
    if s["first_t"] is not None and s["first_val"] > 0:
        uppers.append(s["first_val"])
    else:
        no_first_turn += 1

print(f"files touched within {hours}h:      {files}")
print(f"sessions active in window:        {len(active)}")
print(f"assistant requests (in window):   {reqs}")
print(f"  turns seen but outside window:    {out_of_window:,} (kept as seed evidence, not counted)")
if undated:
    print(f"  turns dropped, undated:           {undated:,}")
if seeds:
    print(f"median seed (tokens/request):     {int(statistics.median(seeds)):,}")
    print(f"mean seed:                        {int(statistics.mean(seeds)):,}")
    if uppers:
        print(f"median turn-1 prompt (UPPER):     {int(statistics.median(uppers)):,}"
              f"  [n={len(uppers)}; {no_first_turn} session(s) omitted, turn 1 not observed]")
    else:
        print(f"median turn-1 prompt (UPPER):     n/a — turn 1 observed for 0 of {len(active)} sessions")
    med_reqs = statistics.median([s["n_win"] for s in active.values()])
    print(f"median requests/session:          {int(med_reqs)}")
    print(f"cache-read tokens total:          {tot_reads:,}")
    if tot_reads:
        print(f"  of which seed re-reads:         {seed_rereads:,} ({100*seed_rereads/tot_reads:.1f}%)")
    print()
    print(f"amplification: one byte cut from the seed is paid back")
    print(f"  1x on the cache write + 0.1x on each of ~{int(med_reqs)-1} re-reads")
    print(f"  => ~{1 + 0.1*(med_reqs-1):.2f}x its per-spawn face value")
