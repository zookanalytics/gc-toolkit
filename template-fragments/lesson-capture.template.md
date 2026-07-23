{{/*
Activation (deliberately NOT applied at ship time): add "lesson-capture"
to the consuming city's [agent_defaults] append_fragments in city.toml —
    append_fragments = ["command-glossary", "operational-awareness", "lesson-capture"]
Deferred because city.toml edits drift session CoreFingerprints and drain
detached manual sessions; the operator/mechanik wires it at a safe moment
after merge. Provenance: thread lo-d5by, 2026-06-03 (correction→bake-in v1).
*/}}
{{ define "lesson-capture" }}
---

## Capture Operator Corrections

When the operator (human) gives **explicit corrective feedback** on how
you worked — "this isn't right", "don't do X", "you should have done Y
first", "stop doing Z", a redirect after a mistake — capture it before
it evaporates with this conversation. Explicit corrections only: routine
instructions, preferences you already honored, and agent-to-agent
feedback do NOT qualify.

**A — agent-local (only if you have auto-memory):** write a
`feedback`-type memory now, per your memory conventions — include the
why and the how-to-apply; quote the operator where short. This makes
the lesson durable for your future sessions.

**B — city-level (always, when the lesson should change shared
process):** if the correction implies a change to shared machinery — an
agent prompt, a formula step, a convention doc, a review check — file a
lesson bead in HQ:

```bash
# -C "$GC_CITY" forces the HQ store — without it, rig agents file
# into their rig's bead DB and the mechanik never sees the lesson.
gc bd create -C "$GC_CITY" "LESSON: <one-line imperative form of the correction>" \
  -t task -l lesson -a gc-toolkit.mechanik \
  -d "<operator's correction as close to verbatim as practical>
Context: <what you were doing when corrected; bead/PR/session refs>
Suggested durable home: <prompt amendment | fragment | formula step | convention doc | review check — best guess>"
```

**The bar:** real corrections only — a lesson bead is a claim that the
process should change. Before filing, check
`gc bd list -C "$GC_CITY" -l lesson --status open,in_progress` (same HQ
store; open AND in_progress — claim flips status) and extend an existing
bead's notes instead of duplicating. Do not file statistics, scores, or
"the operator approved this" — approvals are not lessons.

The mechanik triages lesson beads, picks the durable home, dispatches
the change, and closes the bead with a pointer to the shipped change.
{{ end }}
