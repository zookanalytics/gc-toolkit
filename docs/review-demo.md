---
name: The demo check on gc-toolkit
description: The guidance the demo check reads on gc-toolkit reviews, which the review formula prints from the reviewed commit. It names this rig's visual surfaces, one per kind of screenshot, and how to capture each from the reviewed commit without writing to the live city.
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

The board is the app the helm service embeds. The service's `helm-fixture`
command serves the reviewed commit's board on fixture data, with no city behind
it (`services/helm/README.md`). Capture it from the review workspace under the
keepalive, as every capture runs, with the pack's `demo-screenshot.sh`:
`demo-screenshot.sh page --script board.md --serve "go run ./cmd/helm-fixture"
--port 0 --cwd <worktree>/services/helm --output board.png`.

The board shows `services/helm/web/src/board.fixture.json`, the contract sample,
which carries every key of the board contract. To show another board, write it
in the shape `services/helm/web/src/contract.ts` names and add
`--board $PWD/<file>` to the command. `demo-screenshot.sh` turns `--port 0` into
a free port and hands it to the command as `$PORT`, where `helm-fixture` reads
it, so two captures each get a server of their own. On a cold Go build cache the
first run compiles Go's HTTP stack and can take most of the 30 s the engine
waits for the command. When the engine reports that the command did not answer
in time, capture again, because what the first run compiled stays cached.

A state that a verb leads to needs that verb's answer. Add
`--answers $PWD/answers` to the command. A file there named for the verb, such
as `dismiss.json`, is the answer a click on Dismiss gets, in the shape
`services/helm/web/src/actuate/client.ts` reads, or `open/client.ts` for open.
Name it `dismiss.409.json` and it answers with status 409, as a refusal does. A
verb answers the same way on every click. A verb with no answer is refused as
unavailable, so the board shows the refusal and nothing runs. `?drill=<id>` in
the script's start path opens a row's drill panel. The panel's own reads go to
the supervisor and fail against a fixture, and the panel still offers its
actions.

Never point a capture at a running helm service. Its verbs file and close
conversations, clear human gates and dispatch work in the live city, and a
script that clicks one does that for real.
The verdict says that the board shows fixture data.

## Reports a command prints

Run the reviewed commit's script from the reviewed worktree, for example
`terminal --command "assets/scripts/gc-helm.sh unplaced" --cwd <worktree>`.
These scripts read the live city, so capture only a verb that only reads, such
as `gc-helm.sh unplaced` or `deferred-dispatch.sh list`.

## Markdown the city posts

Pack scripts compose the city's comments and PR bodies, so render what the
reviewed commit composes. A composer that prints, such as
`bring-current-audit.sh render --as comment`, can run from the reviewed
worktree. A composer that posts, such as `signoff.sh`, writes to GitHub when it
runs, so never run it on a live bead. Build its markdown with `gh` stubbed, as
its test suite does.
