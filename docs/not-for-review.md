---
name: Comments not for review
description: Which pull-request comments the city never reads as review feedback, for a rig whose workflows or integrations comment on its pull requests. The mark a comment opens with, the third-party markers a rig declares in not-for-review.toml, and what the city does with a comment that matches.
---

# Comments not for review

The city reads every review, inline comment and conversation comment on a pull
request that it did not post itself as feedback, whoever wrote it
([state-machine.md](state-machine.md#operator-feedback)). Each piece of
feedback becomes a finding a validator rules, and the batch it arrives in
becomes a rework child that takes a polecat. A comment that informs rather than
asks, such as a deployment notice or a report a workflow posts on every pull
request, would cost that round each time it appears. Such a comment is not for
review, and a comment not for review is never feedback, whoever posted it.

## Scope

**Mandate.** What makes a pull-request comment not for review: the mark a
comment opens with, the third-party markers a rig declares and the file it
declares them in, and what the city does with a comment that matches either.

**Boundaries.** How the city tells its own posts from feedback, and what it
does with feedback, is [state-machine.md](state-machine.md#operator-feedback).
The definitions themselves are `feedback-def` in
[`assets/scripts/pr-post.sh`](../assets/scripts/pr-post.sh), which every reader
of feedback prepends to its program. Whether an integration comments at all is
the rig's own setting, outside this doc.

## The mark

A comment whose body opens with this text is not for review:

```
<!-- gc:no-review -->
```

It is an HTML comment, so GitHub renders nothing for it. Whoever writes the
body adds it: a person, or a workflow or bot whose text the rig controls. It
counts the same on a conversation comment, an inline comment and a review
body, under any login.

The mark opens the body when it is the first thing in it, or when only blank
lines and other HTML comments come before it. A byte-order mark at the very
start of the body counts for nothing, since GitHub's renderer drops it. Put
the mark on a line of its own at the top, indented three spaces or less, as in
this report a workflow posts:

```
<!-- growth-factor:schema-diff -->
<!-- gc:no-review -->
### Schema diff
```

The mark counts nowhere else in the body, even where GitHub hides it. Further
down, the markdown before it decides whether it is a hidden comment or text
inside code, such as a fence in a list item or a suggested change. Inside a
quote, it is the mark of the comment quoted. So a reviewer who quotes the mark
while discussing it, and a reply that quotes a marked comment, stay feedback. A
workflow that writes the mark below its text keeps its comments feedback, so
each one costs the round any feedback does.

The city's own posts are not feedback either. They carry the city's mark,
`<!-- gc:city -->`, which [`pr-post.sh`](../assets/scripts/pr-post.sh) appends
to every post the pack makes.

## Markers a rig declares

An integration the rig installs writes text the rig cannot add the mark to. The
rig declares instead how that text begins, in `not-for-review.toml` at the root
of its repository. A comment whose body begins with a declared prefix is not for
review:

```toml
# Vercel's deployment notice opens with a hidden markdown link reference.
[[marker]]
prefix = "[vc]: #"
```

- Each `[[marker]]` table sets `prefix` and nothing else. The file holds nothing
  but those tables and comments.
- A prefix is literal text, compared with the start of the body, case
  included. It is not a pattern. Leading whitespace counts for nothing, in the
  prefix and in the body, and neither does a byte-order mark that opens the
  body.
- A prefix is one line. In double quotes, `\"` and `\\` are its only escapes.
  In single quotes, it is taken as written.
- An empty prefix would take every comment out of review, so it is refused. A
  table with any other fault is refused too, and the rest of the file still
  counts.
- A prefix matches any comment that opens with it, a person's included, so
  declare text that only the integration writes.

A rig whose default branch carries no such file declares nothing, and every
comment an integration posts on its pull requests is feedback.

The city reads the file as the rig's default branch carries it: at
`origin/HEAD`, as the rig's repository last fetched it. A change to the file
counts once it merges, and neither a pull request's own copy of the file nor
an uncommitted edit to it changes which comments count. The rig's repository
is the one the reader runs in, or the one `GC_RIG_ROOT` names when the reader
runs in none. To see what a rig declares, run this in its checkout:

```bash
"$(gc gc-toolkit scripts-dir)/pr-post.sh" not-for-review
```

`gc-toolkit` there is the name the city imports the pack under. The command
prints the mark and each declared prefix, one per line. When it refuses part of
the file, or finds no default branch to read it from, it says so on stderr and
exits 1.

## What the city does with a comment not for review

Nothing. It is never feedback, so:

- it raises no unanswered feedback, so it neither holds the merge nor moves a
  watermark;
- it files no finding, rework child, validation pass or visit;
- the write-back neither acknowledges nor answers it, and in a review thread it
  neither asks the city for an answer nor ends a wait on the reviewer;
- it is nothing said, so a pull request whose only comments are not for review
  reads quiet;
- the feedback miner skips it as a notice, and files no observation from it.

A review's state is not its body. An approval still counts as an approval, and a
change request still holds the merge, whatever the review's body carries. Only
the body is not read as feedback. The inline comments a review carries are each
read on their own.
