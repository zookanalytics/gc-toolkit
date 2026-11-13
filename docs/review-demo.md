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
it (`services/helm/README.md`). The command that runs it is the rig's declared
serve command, `ui_serve_command`, which the city sets among gc-toolkit's
formula vars and which a sitting's live copy of the board runs too, through
`gctk rig serve`. It runs from the worktree's root. A capture of the board needs
that value as gc reads it: the city sets it for gc-toolkit, and the
`mol-rig-demo` that gc loads declares the var, since `gc formula show` lists
only the vars a formula declares. Read it as that var's `rig_default`, and
capture the board from the review workspace under the keepalive, as every
capture runs, with the pack's `demo-screenshot.sh`. Where gc reads no value, the
block captures nothing and says why:

```bash
SERVE=$(gc formula show mol-rig-demo --rig gc-toolkit --json | jq -r '[.vars[] | select(.name == "ui_serve_command")][0].rig_default // empty')
if [ -z "$SERVE" ]; then
  echo "no capture of the board: gc reads no ui_serve_command for gc-toolkit; the city sets none for it, or the mol-rig-demo that gc loads declares none" >&2
  false
else
  demo-screenshot.sh page --script board.md --serve "$SERVE" --cwd <worktree> --output board.png
fi
```

The page shows the gc-toolkit rig's document,
`services/helm/internal/rigboard/testdata/gc-toolkit.board.json`, which the rig
read builds from the committed fixture of real gc-toolkit beads, so the
script's start path is `/?rig=gc-toolkit`. To show another rig's document,
write it in the shape `services/helm/web/src/rigboard/document.gen.ts` names
and add `--rig-board $PWD/<file>` to the command. `demo-screenshot.sh` serves
the command as a copy that `gctk rig serve` runs from the worktree, inside the
capture's sandbox, on a free port of its own that the command gets as `$PORT`,
where `helm-fixture` reads it. A worktree has one copy, so take its captures one
after another. A capture whose command differs from a copy that still runs
there is refused until `gctk rig serve --stop`, run in the worktree, ends it.
On a cold Go build cache the first run compiles Go's HTTP stack, and the copy's
start waits up to three minutes for it to answer.

A state that a verb leads to needs that verb's answer. Add
`--answers $PWD/answers` to the command. A file there named for the verb, such
as `engage.json`, is the answer a click on Start the conversation or Rejoin
the conversation gets, in the shape `services/helm/web/src/actuate/client.ts`
reads, or `open/client.ts` for the form Discuss opens. Name it
`engage.409.json` and it answers with status 409, as a refusal does. A verb
answers the same way on every click. A verb with no answer is refused as
unavailable, so the board shows the refusal and nothing runs. Details reads a
bead's description from the supervisor, which a fixture cannot reach, so the
page says it cannot read the description and shows the rest of Details.

Capture the board through `helm-fixture`, never through a running helm
service. A capture refuses a `--base-url` that any gc-toolkit server answers,
and the service's verbs act on the live city. The verdict says that the board
shows fixture data.

## Reports a command prints

Run the reviewed commit's script from the reviewed worktree, for example
`terminal --command "doctor/check-po-queue-only/run.sh" --cwd <worktree>`.
These scripts read the city through `gc`, which a capture cannot reach, so give
the command fixture data: put a `gc` stub first on its PATH that answers from
fixture JSON, as the script's own test suite does
(`doctor/check-po-queue-only/run.test.sh` builds one for that check). Keep the stub and its JSON in the review workspace beside the PNG.
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
