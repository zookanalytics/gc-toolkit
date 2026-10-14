---
name: The demo check on gc-toolkit
description: The method extension the demo check appends on gc-toolkit reviews. It names this rig's visual surfaces, one per kind of screenshot, and how to capture each from the reviewed commit without writing to the live city.
---

# The demo check on gc-toolkit

gc-toolkit shows a person three kinds of surface, and `demo-screenshot.sh` has a
kind for each. Capture each one from the reviewed commit, and never through a
path that writes to the live city.

## Scope

**Mandate.** gc-toolkit's own visual surfaces, and how a demo review captures
each one: the helm board, the reports the pack's commands print, and the
markdown the city posts on GitHub.

**Boundaries.** The demo check's method, its modalities and the capture scripts
are pack content, in `skills/review-demo/SKILL.md`. This page adds only what is
particular to this rig.

## The helm board

The board is a static build that the Go service embeds, committed at
`services/helm/web/dist`. It reads the board from the document-relative path
`helm`, and its actuation verbs (accept, engage and dismiss) post to
`helm/<verb>`. The engine's file server answers any request with the file at its
path, whatever the method, and answers a directory with its `index.html`. So a
capture serves a copy of the reviewed commit's build, with fixture files at
those paths:

```bash
cd "$(dirname "$REVIEW_WT")"
mkdir -p helm-app/helm
cp -R "$REVIEW_WT/services/helm/web/dist/." helm-app/
cp "$REVIEW_WT/services/helm/web/src/board.fixture.json" helm-app/helm/index.html
hb "$SCRIPTS/demo-screenshot.sh" page --script board.md --serve-dir helm-app --output board.png
```

A state that a verb leads to needs that verb's answer at `helm-app/helm/<verb>`,
in the shape the reviewed commit's `services/helm/web/src/actuate/client.ts`
reads. `?drill=<id>` in the script's start path opens a row's drill panel. The
panel's own reads go to the supervisor and fail against a fixture, and the panel
still offers its actions.

Never point a capture at a running helm service. Its verbs file, dispatch and
close visits in the live city, and a script that clicks one does that for real.
The verdict says that the board shows fixture data.

## Reports a command prints

Run the reviewed commit's script from the reviewed worktree, for example
`terminal --command "assets/scripts/gc-helm.sh unplaced" --cwd "$REVIEW_WT"`.
These scripts read the live city, so capture only a verb that only reads, such
as `gc-helm.sh unplaced` or `deferred-dispatch.sh list`.

## Markdown the city posts

Pack scripts compose the city's comments and PR bodies, so render what the
reviewed commit composes. A composer that prints, such as
`bring-current-audit.sh render --as comment`, can run from the reviewed
worktree. A composer that posts, such as `signoff.sh`, writes to GitHub when it
runs, so never run it on a live bead. Build its markdown with `gh` stubbed, as
its test suite does.
