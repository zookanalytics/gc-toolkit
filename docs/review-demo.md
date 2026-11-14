---
name: The demo guide for gc-toolkit
description: Use when you demo a gc-toolkit change, write a demo script for one, or bring its helm board up for a capture, as the demo check, the demo drafter, mol-rig-demo and a capture given --guide do at the commit they show.
---

# The demo guide for gc-toolkit

gc-toolkit shows a person three kinds of surface, and `demo-screenshot.sh` has a
kind for each. Capture each one from the commit the demo shows, and always use
fake data or gc-toolkit-only data. A capture is prevented from reaching live
data.

## Scope

**Mandate.** gc-toolkit's own visual surfaces, and how a demo captures each
one: the helm board, the reports the pack's commands print, the conversation
form, and the markdown the city posts on GitHub. The demo check, the drafter
`gc-demo-script`, `mol-rig-demo` and a capture given `--guide` read it at the
commit they show.

**Boundaries.** What a demo guide holds is pack content, in
`skills/demo-capture/SKILL.md`, and so are the demo check's method, its
modalities and the capture scripts, in `skills/review-demo/SKILL.md`. This page
adds only what is particular to this rig.

## Surfaces

- **The helm board**, the page the helm service embeds, which
  `services/helm/web/` draws. It is the app a capture brings up.
- **Reports a command prints**, the output of a pack script under
  `assets/scripts/` in a terminal.
- **The conversation form**, the terminal form `gc-helm.sh engage` and
  `gc-helm.sh attach` open, which helm-svc's `form` command in
  `services/helm/` draws.
- **Markdown the city posts**, the comments and PR bodies the pack's scripts
  compose.

The sections after [Worked examples](#worked-examples) say how to capture each.

## Bring the app up

**Serve:** `cd services/helm && exec go run ./cmd/helm-fixture`
**Cwd:** `services/helm`

The app is the helm board on fixture data. The service's `helm-fixture` command
serves the board of the commit it runs from, with no city behind it
(`services/helm/README.md`). A capture serves the command as a copy that
`gctk rig serve` runs from the worktree's root, inside the capture's sandbox, on
a free port of its own that the command gets as `$PORT`, where `helm-fixture`
reads it. A worktree has one copy, so take its captures one after another. A
capture whose command differs from a copy that still runs there is refused until
`gctk rig serve --stop`, run in the worktree, ends it. On a cold Go build cache
the first run compiles Go's HTTP stack, and the copy's start waits up to three
minutes for it to answer. A sitting's live copy of the board runs the command
the `**Serve:**` line names, as a capture does.

Capture the board through `helm-fixture`, never through a running helm
service. A capture refuses a `--base-url` that any gc-toolkit server answers,
and the service's verbs act on the live city. The verdict says that the board
shows fixture data.

A terminal capture given `--guide` starts its shell in `services/helm`, which
is where the conversation form runs. A report runs from the worktree's root, so
give its capture `--cwd <worktree>` instead.

## A known state

**Start:** `/?rig=gc-toolkit`

The board shows the gc-toolkit rig's document,
`services/helm/internal/rigboard/testdata/gc-toolkit.board.json`, which the rig
read builds from the committed fixture of real gc-toolkit beads, so a script's
start path is `/?rig=gc-toolkit`. To show another rig's document, write it in
the shape `services/helm/web/src/rigboard/document.gen.ts` names and add
`--rig-board $PWD/<file>` to the command, which a capture then names with
`--serve` and `--cwd <worktree>` in place of `--guide`.

A state that a verb leads to needs that verb's answer. Add
`--answers $PWD/answers` to the command, named with the flags as above. A file
there named for the verb, such
as `engage.json`, is the answer a click on Start the conversation or Rejoin
the conversation gets, in the shape `services/helm/web/src/actuate/client.ts`
reads, or `open/client.ts` for the form Discuss opens. Name it
`engage.409.json` and it answers with status 409, as a refusal does. A verb
answers the same way on every click. A verb with no answer is refused as
unavailable, so the board shows the refusal and nothing runs. Details reads a
bead's description from the supervisor, which a fixture cannot reach, so the
page says it cannot read the description and shows the rest of Details.

## Sign-in

None. `helm-fixture` serves the board on this host's loopback with no sign-in,
and the reports and the form run as commands.

## Worked examples

gc-toolkit keeps no committed demo script. Each capture call below is one to
copy, run from the review workspace under the keepalive, as every capture runs.
The board, with a script whose start path is `/?rig=gc-toolkit`:
`demo-screenshot.sh page --script board.md --guide <worktree> --output
board.png`, or for a clip, `rig-demo-capture.sh --script board.md --output
board.mp4 --guide <worktree>`.

## Reports a command prints

Run the reviewed commit's script from the reviewed worktree, for example
`terminal --command "assets/scripts/deferred-dispatch.sh list" --cwd <worktree>`.
These scripts read the city through `gc`, which a capture cannot reach, so give
the command fixture data: put a `gc` stub first on its PATH that answers from
fixture JSON, as the script's own test suite does
(`assets/scripts/deferred-dispatch.test.sh` builds one for `deferred-dispatch.sh
list`). Keep the stub and its JSON in the review workspace beside the PNG.
The verdict says the report shows fixture data.

## The conversation form

`gc-helm.sh engage` and `gc-helm.sh attach` open a terminal form, helm-svc's
`form` command. It reads and writes only through the gc-helm.sh it is given, so
run it against the fixture stand-in, which answers from fixture data and writes
nothing. Build helm-svc into the review workspace, beside the capture, since no
ignore rule covers a binary in the worktree. Every compile of `services/helm`
needs ICU's cgo flags on macOS, so pass it the flags `icu4c_cgo_flags` works out,
as `gc-build.sh` and `tools/lint.sh` do:

```bash
. <worktree>/assets/scripts/icu4c-cgo.sh && icu4c_cgo_flags review-demo
(cd <worktree>/services/helm && CGO_CPPFLAGS="$ICU4C_CGO_CPPFLAGS" CGO_LDFLAGS="$ICU4C_CGO_LDFLAGS" go build -o <workspace>/helm-svc ./cmd/helm-svc)
```

Then capture it with `--cwd <worktree>/services/helm`:
`terminal --command "<workspace>/helm-svc form --helm
internal/form/testdata/helm-fixture.sh --models
claude-opus,claude-fable,codex-astra,codex-sol --subject tk-demo1"` for a
subject, `--rig gc-toolkit` for a new topic, `--subject 1446` for a PR two rigs
record, `--subject tk-demo10` for a gate two beads wait on, which the form reads
from tk-demo1 once it is chosen among what holds tk-demo1, or `--return` for the
conversations to return to. The People page is reached on the form's tabs, so
with no subject flag a recording presses ↑ to reach the tabs and ← to wrap
around to People, then ↓ to gc-toolkit's po and Enter, and the fixture names
the seat's verb it was handed in place of attaching. A
terminal capture shows the form's first frame, drawn before the fixture answers
its reads a second later. What those reads fill in, such as tk-demo1's
conversations and what holds it, a gate and the PR's own review threads, and a
state after keys, such as the acknowledgements after Ctrl+S, need a recording
(`demo:capture`). The verdict says the form shows fixture data.

## Markdown the city posts

Pack scripts compose the city's comments and PR bodies, so render what the
reviewed commit composes. A composer that prints, such as
`bring-current-audit.sh render --as comment`, reads its bead from the city's
store, so run it with `gc` stubbed on fixture data, as for a report. A composer
that posts, such as `signoff.sh`, writes to GitHub when it runs, so never run
it on a live bead. Build its markdown with `gh` stubbed, as its test suite
does.
