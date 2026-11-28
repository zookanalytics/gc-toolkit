---
name: Gas City search for gctk github quote (tk-098e1s4)
description: The primitives searched in Gas City, bd and GitHub for each need of gctk github quote, the one reader of the text people post on GitHub, and of the follow-up it files for an outside account's post, with what each covers and why each gap is the reader's. Read it when reviewing the reader's surface, as AGENTS.md asks of a change that adds a gctk noun or verb.
---

# Gas City search for gctk github quote

This change adds a gctk noun, `github`, with one verb, `quote`, its
`--description` and `--json` flags, and the keys its JSON carries, which the
`quote` package declares. It files one human gate per outside account per PR,
through `human-gate.sh`, under the situation key `outside-post-<login>`. It adds
no order, no bead key and no lifecycle state. Each need names the primitive
searched at `gastownhall/gascity` main 6dce31bbb68e (2026-11-27), and GitHub's
own documentation where GitHub is the platform.

## Read a PR's or an issue's posted text for an agent

**Not covered.** No reader in Gas City's `cmd/` or `internal/` hands an issue's
or a PR's conversation to an agent. The PR monitor's read,
`internal/githubmonitor/client.go` `pullRequestsQuery`, takes each open PR's
number, title, URL, author, branches and check states, and
`githubPRRepairTitle` in `cmd/gc/cmd_github.go` puts the title in a repair
bead's title as GitHub gives it.

## Mark text from outside as untrusted

**Covered for another construct.** `SanitizeForSystemReminder` in
`internal/promptsafe/promptsafe.go` strips the literal system-reminder tags
from mail, nudge and external-message text before Gas City sets it in a
reminder block, and its comment scopes it narrowly: "This is not a general
HTML escape". It holds no post by its author's standing with the repository,
and it leaves every character a shell reads as it was. The quote's hold and its
inert form are the gap.

## Tell the repository's own accounts from outside ones

**Covered by GitHub, which the reader composes.** GitHub's GraphQL
`authorAssociation` on a PR, an issue, a review, a review comment and an issue
comment, and a repository's `viewerPermission` for the account the read runs
as, decide it. No code in Gas City's `cmd/` or `internal/`, tests aside, reads
either field. GitHub Actions posts as a Bot with no association, so the rule
names its account.

## Keep outside accounts from posting

**Not covered for the need.** GitHub's interaction limits ("Limiting
interactions in your repository", GitHub Docs) restrict commenting on one public
repository to its collaborators, for at most six months at a time. A limit
lapses, it covers one repository, and it does nothing for another repository's
text an agent must read, such as an upstream project's issues. The reader holds
a post whatever a limit's state.

## Tell the operator of each held post

**Covered by bd's human gate, which the reader files.** A gate `human-gate.sh`
files on the bead that owns the PR is what the helm board shows as a question
waiting on the operator (`askOf` in `services/gctk/standing/rules.go`). Gas
City's core orders that mail a gate's addressee,
`notify-on-human-gate-creation` and `renudge-stale-human-gates` under
`internal/bootstrap/packs/core/orders/`, are off in this city, which reaches
the operator through the board.

## File the follow-up once per account per PR

**Covered by the gate's key.** Gas City has no general upsert. `SendDeduped` in
`internal/mail/beadmail/beadmail.go` drops a repeated mail, and
`ensureGitHubPRRepairBead` in `cmd/gc/cmd_github.go` keeps one repair bead per
PR and head for the monitor alone. `human-gate.sh` files one open gate per
subject and key, so the key `outside-post-<login>` on the owning bead gives one
follow-up per account per PR, whichever read holds the post first.
