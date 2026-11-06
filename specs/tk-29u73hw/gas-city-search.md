---
name: Gas City search for a visit's PR comment as a view of its bead
description: The search the arch check asks for before pr-sitting-comment.sh draws a visit's PR comment from its conversation, through its post and refresh modes, with the conversation's title as the topic, its comments as the actions and its hand-back as the conclusion. What Gas City, the packs it publishes and bd ship for showing a bead on a pull request and for recording a topic and actions on a bead, read at named upstream commits, and why the change composes bd's title and comments and keeps one projection of the pack's own. Read it when checking whether the visit's comment still needs a script of the pack's.
---

# Gas City search for a visit's PR comment as a view of its bead

The operator ruled that a visit's comment on its subject's pull request is a
view of the visit's own bead, showing that bead's values word for word, with
no filter. This change grows operational surface, so the arch check asks what
Gas City already ships for each part of it
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

## The surface and the need

- `pr-sitting-comment.sh post --sitting <task> --topic <text>` and
  `pr-sitting-comment.sh refresh --sitting <task>` replace main's `engage` and
  `close` modes and their `--subject`, `--reason`, `--outcome`, `--summary` and
  `--actions` flags. Each draws the comment from the conversation alone: its id,
  the bead it tracks, its title as the topic and, once it closes, its
  `gc.handback` as the conclusion and its comments as the actions. `post`
  creates the comment once the title reads back as the topic the sitting wrote,
  and `refresh` only edits one that exists.
- The conversation's title is the visit's topic. converse-prep's title step
  writes it with `bd update --title`.
- The conversation's comments are the visit's actions. converse-signoff.sh
  writes one for the ruling and one for each act it takes, `gc-helm.sh dismiss`
  writes one for the dismissal, and the sitting writes one for work it sends
  and one for a close at its premise re-check, each with `bd comment`.
- No metadata key, bead kind or lifecycle state is added. `rig-mentions.sh`
  loses `--rig-map`, which only the filter used, so the search its first commit
  recorded for that flag no longer applies.

The need has three parts. A comment on a pull request is kept in place and
shows a bead's values, drawn again after each write that changes them. The bead
has a place for a topic the visit names, written again only when the topic
moves. It also has a place for actions in plain words, added as they happen,
which a re-run can tell it already added.

## Where the search looked

Each source was read on 2026-11-05 (UTC):

- Gas City (`gastownhall/gascity`) at main `357c30c631cf`: `cmd/gc/cmd_github.go`
  and `internal/githubmonitor`, its GitHub integration; `cmd/gc/cmd_session.go`
  and `internal/worker/handle_lifecycle.go`, behind `gc session rename`; and
  `docs/reference/cli.md` and `docs/reference/config.md`.
- The packs Gas City publishes (`gastownhall/gascity-packs`) at main
  `796d7ecd73cf`: every pack, searched for a write to a pull request's comments
  (`gh pr comment`, `gh api` on a comments path, `--edit-last`, a PATCH of an
  issue comment) and for a comment kept in place under a marker.
- bd (`gastownhall/beads`) at main `6d713a74849f`: `docs/cli-reference/comments.md`,
  `docs/multi-agent/coordination.md`, and the fields a bead carries.

## What it found

**Showing a bead on a pull request: nothing ships it.** Gas City's GitHub
integration reads pull requests into beads, and never the reverse.
`internal/githubmonitor`'s `GraphQLClient` queries GitHub's GraphQL API for a
pull request's readiness and sends no mutation, and `gc github pr backfill`
files and refreshes repair beads from that state
(`ensureGitHubPRRepairBead` in `cmd/gc/cmd_github.go`). The packs post one-shot
comments a formula composes, such as pr-review's `mol-pr-revert`
(`gh pr comment {{pr}} --body-file`) and pr-pipeline's adoption review comment.
None edits a comment in place from a bead's values. oversight-rig's
executive-status skill keeps a brief between markers, in a file of its own. So
the projection stays the pack's: `pr-sitting-comment.sh`, posting and editing
through `pr-post.sh`, as main's reminder did.

**A topic: bd's title.** A bead's title is bd's field for what the bead is
about, and a conversation's ask stays its description, which the sitting reads.
`gc session rename` titles the session through the session manager
(`SessionHandle.Rename`), not the conversation, and the session's record goes
when its session does. So the visit writes its topic as the conversation's
title, and the change adds no key for it.

**Actions: bd's comments.** bd ships comments, an append-only list on a bead in
which each entry keeps its text, author and time (`bd comment <id> <text>`,
`bd comments <id> --json`). Its coordination guide uses them for the note an
agent leaves about what it did: `bd comment bd-42 "Completed API, needs frontend
integration"`. So the actions are the conversation's comments, and the change
adds no key for them. A re-run of the sign-off reads them first and adds no
second copy of one it finds. The conversation's notes stay the thread's record,
which the view does not show.

**The conclusion: an existing key.** `gc.handback` is the pack's key for the
hand-back a sitting last recorded (`lifecycle/lifecycle.toml`), the text the
operator's tab prints when a sitting ends. The comment reads it once the
conversation closes, and the key gains a reader and no writer.

## What the pack's own projection holds

Nothing the search found renders a bead on a pull request, so the script keeps
the part the need leaves: one comment per conversation under its marker, the
two ids, the title, and, once the conversation closes, the hand-back and the
comments, laid out under fixed labels. Every gh call is pinned to the origin of
the checkout the caller runs in, a sitting's worktree of the subject's rig or,
for a dismiss, the subject's rig checkout, so the comment reads no rig map, and
a PR the subject records on another repository is left alone, as main's
reminder left it. It writes no bead, filters nothing and composes no text of
its own beyond those labels and the `none recorded` and `none` an empty field
reads. It names no pack noun, so it takes no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2).
