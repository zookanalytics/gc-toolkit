---
name: The demo check on gc-toolkit
description: The guidance the demo check reads on gc-toolkit reviews, which the review formula prints from the reviewed commit. It names this rig's visual surfaces, one per kind of screenshot, and how to capture each from the reviewed commit on fixture data, since a capture cannot reach the live city.
---

# The demo check on gc-toolkit

gc-toolkit shows a person three kinds of surface, and `demo-screenshot.sh` has a
kind for each. Capture each one from the reviewed commit, and always use fake
data or gc-toolkit-only data. A capture is prevented from reaching live data.

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

Capture the board through `helm-fixture`, never through a running helm
service. A capture refuses a `--base-url` that any gc-toolkit server answers,
and the service's verbs act on the live city. The verdict says that the board
shows fixture data.

## Reports a command prints

Run the reviewed commit's script from the reviewed worktree, for example
`terminal --command "assets/scripts/gc-helm.sh unplaced" --cwd <worktree>`.
These scripts read the city through `gc`, which a capture cannot reach, so give
the command fixture data: put a `gc` stub first on its PATH that answers from
fixture JSON, as the script's own test suite does
(`assets/scripts/gc-helm-unplaced.test.sh` builds one for `gc-helm.sh
unplaced`). Keep the stub and its JSON in the review workspace beside the PNG.
The verdict says the report shows fixture data.

## The conversation form

`gc-helm.sh engage` and `gc-helm.sh attach` open a terminal form, helm-svc's
`form` command. It reads and writes only through the gc-helm.sh it is given, so
run it against the fixture stand-in, which answers from fixture data and writes
nothing: build `go build -o "$PWD/helm-svc" ./cmd/helm-svc` in
`<worktree>/services/helm`, then capture
`./helm-svc form --helm internal/form/testdata/helm-fixture.sh --models
opus,fable,codex --subject tk-demo1` for a subject, `--rig gc-toolkit` for a new
topic, `--subject 1446` for a PR two rigs record, or `--return` for the
conversations to return to. A terminal capture shows the form's first frame; a
state after keys, such as the acknowledgements after Ctrl+S, needs a recording
that types them (`demo:capture`). The verdict says the form shows fixture data.

## Markdown the city posts

Pack scripts compose the city's comments and PR bodies, so render what the
reviewed commit composes. A composer that prints, such as
`bring-current-audit.sh render --as comment`, reads its bead from the city's
store, so run it with `gc` stubbed on fixture data, as for a report. A composer
that posts, such as `signoff.sh`, writes to GitHub when it runs, so never run
it on a live bead. Build its markdown with `gh` stubbed, as its test suite
does.
