---
name: Helm board subject-topic rendering — visual capture (tk-fadpiz)
description: Before/after capture of the Helm board Sittings section showing the tk-fadpiz renderer change — SUBJECT renders the subject's topic (title) instead of a bare id, and HEADLINE falls back to that topic for a takeaway-less row. Captured from the live loomington city, scoped to the gc-toolkit rig.
---

# Helm board subject-topic rendering — visual capture (tk-fadpiz)

`screenshots/helm-board-cli-before.png` and `screenshots/helm-board-cli-after.png`
capture the change in tk-fadpiz on the Helm board's **Sittings** section. The
`.txt` siblings hold the same rows as plain text.

The board renders on two surfaces from one gather and one derivation: the CLI
`helm-svc board` and the web dashboard. The capture is the CLI Sittings section,
which the CLI renderer documents as "the CLI view of the same gather and
derivation the Helm dashboard serves". Both surfaces call the same model helpers
this change adds, `board.Sitting.Topic()` and `board.Sitting.Headline()`, so the
CLI capture shows the derivation the web board renders as well.

## What changed

- **SUBJECT** was the bare subject-bead id. It is now the subject's **topic** —
  the subject bead's title (`Sitting.Topic()`, the title else the id), clipped
  to the column width.
- **HEADLINE** was the takeaway, falling back to the visit bead's own title. It
  now falls back to the topic first (`Sitting.Headline()`: the takeaway, else
  the topic, else the visit title). On an old-path first reaction the visit
  title is the generic pool-offer line "first reaction ready: accept or
  redirect", which a takeaway-less row no longer shows.

A row with an attributed takeaway keeps that takeaway as its headline, so the
change adds context without regressing the rows that already read well.

## Representative rows (from the capture)

Same live gc-toolkit sittings, rendered by each binary:

```
tk-v7nqry  has a takeaway — SUBJECT gains the topic, HEADLINE is unchanged
  before: SUBJECT tk-hok6w    HEADLINE liveness-sweep exec order owns this standing subject; held on live census visit…
  after:  SUBJECT triage: unnamed waits (this rig)
                             HEADLINE liveness-sweep exec order owns this standing subject; held on live census visit…

tk-79s11x  no takeaway — topic replaces the bare id AND the generic visit title
  before: SUBJECT tk-ob7npn   HEADLINE visit: tk-ob7npn — 13 workflow-finalize beads (gc.routed_to=gc-toolkit/core.control-dispatcher)…
  after:  SUBJECT Finalize workflow
                             HEADLINE Finalize workflow

tk-gb2tgn  no takeaway
  before: SUBJECT tk-nqvm2e   HEADLINE visit: tk-nqvm2e — The 'Work beads waiting for merge' deferred reminder has fired 4 times…
  after:  SUBJECT triage: escalations raised from an ephemeral subject (this rig)
                             HEADLINE triage: escalations raised from an ephemeral subject (this rig)
```

## Reproduction

Both binaries read the live loomington city; `GC_HELM_CITY_PATH` pointed at the
rig directory is the scoping lever. The board has no rig flag — it enumerates
`<city>/.beads` and `<city>/rigs/*/.beads`, so pointing it at
`rigs/gc-toolkit` makes it read that one store and nothing else. This is what
keeps the capture to gc-toolkit beads only.

```bash
# after — this branch (polecat/tk-fadpiz):
cd services/helm && go build -o /tmp/helm-svc.after ./cmd/helm-svc
GC_CITY_PATH=/home/zook/loomington \
  GC_HELM_CITY_PATH=/home/zook/loomington/rigs/gc-toolkit \
  /tmp/helm-svc.after board --limit=0

# before — origin/main, built from a checkout of the base:
#   cd services/helm && go build -o /tmp/helm-svc.before ./cmd/helm-svc
#   (same invocation as above)
```

The two renderers gather the same rows in the same order, so the before and
after line up row for row; only the SUBJECT and HEADLINE cells differ. The
images render the terminal output verbatim.
