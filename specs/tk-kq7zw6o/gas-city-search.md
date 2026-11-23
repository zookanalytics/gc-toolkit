---
name: Gas City search for showing a change's images on its PR
description: The search the arch check asks for on `gctk review images`, which posts on a pull request each image its change adds, changes, moves or removes, a changed one before and after. Read it when deciding whether that verb can move onto something Gas City, bd or GitHub ships.
---

# Gas City search for showing a change's images on its PR

`gctk review images` posts on a pull request each image its change adds,
changes, moves or removes, a changed one before and after, so a reader sees
them on the PR's conversation. The demo check calls it when a diff commits an
image, and the common case is a golden image, the picture a browser test
compares the app's rendering with. The verb is a new command of a service, so
the arch check asks what Gas City, bd and GitHub ship for the need
([review-arch.md](../../docs/review-arch.md)).

## Where the search looked

Read on 2026-11-23:

- Upstream `gastownhall/gascity` at `main` 572f981c61: `docs/`,
  `internal/bootstrap/packs/` and `examples/` for `pull request`,
  `pull_request`, `gh pr comment`, `--attach`, `image` and `screenshot`, and
  `cmd/` and `internal/` for a `gh` call that posts on an issue or a PR.
- Upstream `gastownhall/gascity-packs` at `main` 44b9db7168: `gascity/` for
  `attach`, `image`, `screenshot`, `png`, `golden` and a raw file's address, and
  its GitHub scripts for what they post.
- GitHub's documentation on images in comments and on Camo, and the help of
  `gh` 2.104.0, the version on this host.
- GitHub's own renderer, through its markdown API, for what a comment's image
  address becomes, and a PR page's content security policy.

## What ships near the need

- **Gas City's GitHub monitor.** `[[github.pr_monitor]]` and
  `gc github pr backfill` read whether each open PR is ready and file repair
  beads for those that are not
  ([Configuration, GitHubPRMonitor](https://docs.gascity.com/reference/config),
  `docs/reference/config.md`, and
  [CLI, gc github pr backfill](https://docs.gascity.com/reference/cli),
  `docs/reference/cli.md`). They post nothing on a PR and read no file its
  change commits.
- **Gas City's review formula.** The core pack's `mol-review-quorum`
  (`internal/bootstrap/packs/core/formulas/mol-review-quorum.toml`) keeps its
  review as output JSON on beads. It posts nothing on GitHub. The only posts on
  a PR in Gas City's tree are a CI workflow of its own repository
  (`.github/workflows/worker-env-notify-beads-pr.yml`).
- **gascity-packs' PR review.** Its `github-pr-review` workflow posts one text
  report on a PR and edits it in place (`comment_create` and `comment_update`
  in `gascity/assets/scripts/github_api.py`, and `render_pr_review_comment` in
  `gascity/assets/scripts/github_reports.py`). Nothing in the pack draws an
  image or attaches a file.
- **bd.** It keeps beads, and reaches no GitHub.
- **GitHub's Files tab.** It draws an image the diff adds or changes, among the
  rest of the diff. The PR's conversation, which a reader approves from, shows
  none, and the need is that a reader never opens the Files tab to see one.
- **gh's attachments.** `gh pr comment --attach` uploads up to 50 files a call
  to GitHub's user attachments and rewrites a reference to each in the body
  (`gh pr comment --help`, gh 2.104.0). The pack posts on a PR only through
  `pr-post.sh`, whose `comment` takes one attachment, and the move of that
  writer into gctk is tk-ssm8qns.8. An upload is also a copy of every image,
  sent from this host on every run.
- **A repository's images, by address.** GitHub "supports embedding images
  into your issues, pull requests, discussions, comments and .md files", and
  shows an image "from your repository" by its address, a link that works "in
  a private repository only if the viewer has at least read access" to it
  ([Basic writing and formatting syntax, Images](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#images)).
  An image from another host is proxied through Camo
  ([About anonymized URLs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-anonymized-urls)),
  which reads it without the viewer's session. The markdown API, rendering in a
  public and in a private repository's context, rewrote an image on
  example.com to a `camo.githubusercontent.com` address and left one at
  `https://github.com/<owner>/<repo>/raw/<commit>/<path>` as it was. That
  address redirects to `raw.githubusercontent.com`, and a PR page's content
  security policy lets an image load from `github.com` and from
  `*.githubusercontent.com`. So a reader's own session loads the file a commit
  holds, at that commit.

## What the verb adds

Nothing above shows a change's images on its conversation. The verb composes
the last two: it reads the change with git, writes each image's address at the
commit the change branches from and at the reviewed commit, groups the images by
directory and by the stem their names share, keeps each comment under GitHub's
limit on a body's length, and posts each comment through `pr-post.sh comment`,
the writer that carries the city's mark. It uploads nothing, so it needs no
growth of that writer, and an image shows the file the reviewed commit holds,
not a copy taken on this host.
