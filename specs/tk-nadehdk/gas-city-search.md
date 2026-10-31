---
name: Gas City search for a security-policy check and a private report in upstream sends
description: The search the arch check asks for before upstream-finding.sh requires the preparer's reading of the target's security policy on every public send and gains a mode that parks GitHub's private vulnerability report. What Gas City, the packs it publishes and bd ship for checking a target's security policy before an agent writes to another project's repository, and for sending a vulnerability report through a private channel, read at named upstream commits, and why none of it covers the need. Read it when checking whether the gate or the report mode can move onto a Gas City primitive.
---

# Gas City search for a security-policy check and a private report in upstream sends

`upstream-finding.sh` parks an agent's `gh` write to a repository the rig does
not own, for the operator to paste unedited
([outbound-sends.md](../../docs/outbound-sends.md)). This change grows it in
two ways. A send that publishes its text, which is every send but one, is
parked only with `--security-policy`, the preparer's reading of the target's
security policy, and the bead and the visit carry that reading beside the
command. The script also parks one `gh api` write, GitHub's private
vulnerability report (`POST repos/<owner>/<name>/security-advisories/reports`),
and reads its target from the endpoint path. So the arch check asks what Gas
City already ships for each need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships neither. Nothing in Gas City, its published packs or bd reads a
repository's security policy, asks whether a finding belongs in private, or
files a private vulnerability report. The one published pack that files issues
to another project's repository files them in public and asks no such question,
although the repository it files to asks for vulnerabilities in private. The
change adds no pack noun, and it touches no path or key that a warrant in
[warrants.md](../../docs/warrants.md) covers.

## The need

- Before a finding is parked as a public issue, PR or comment on a repository
  the rig does not own, someone has read that repository's security policy, and
  the operator sees what it says when they decide whether to paste.
- A finding the policy asks to receive privately goes through the private
  channel the policy names, as a command the operator can paste unedited. On
  GitHub that channel is private vulnerability reporting, where the repository
  enables it.

## Where the search looked

Each was read on 2026-10-30:

- Gas City at `gastownhall/gascity` main `adf99aa6c84d`: its source, its
  `docs/` (the site at docs.gascity.com) and its `engdocs/`.
- `gastownhall/gascity-packs` at main `0b0d96250f66`, every pack in it.
- bd at `gastownhall/beads` main `f7b94653eb89`.

The terms, matched without case: `SECURITY.md`, security policy, security
advisories, private vulnerability reporting, vulnerability report, disclosure
and `GHSA`. Then every `gh issue create`, `gh pr create`, `gh issue comment`,
`gh pr comment`, and `gh api` call with a POST or PATCH method, to find each
place that writes to GitHub and read what it does before the write.

`gh` 2.103.2 has no command for a security advisory or a private report, so
`gh api` is how a pasteable command reaches the endpoint. Its own help lists no
`--repo` flag, and a pasted `gh api --repo` fails with "unknown flag".

## What Gas City ships near the need

### Gas City's own security policy

Gas City's repository carries a `SECURITY.md`. It asks for vulnerabilities
through GitHub private vulnerability reporting and for no public issue,
discussion or pull request before a fix, and its issue templates tell a person
filing an issue the same. That is guidance for people reporting to Gas City. No
code or agent prompt reads it, or any other repository's policy.

### Writes to GitHub in the published packs

- `contributing-to-gascity`'s `write-issue` skill is the nearest analog: an
  agent preparing an issue for another project's repository. It triages the
  observation, confirms it on main, searches for duplicates and drafts the
  body, then runs `gh issue create --repo gastownhall/gascity` from a body file.
  Neither its workflow nor its checklist asks whether the finding is a
  vulnerability, although that repository's own policy asks for one in private.
- `gstack`'s `spec` skill scans an issue body for credentials, personal data
  and confidential context before it files the issue to the current repository,
  and it keys how strict the scan is on that repository's visibility. It judges
  what the text contains, not whether the finding belongs in a private channel.
- `pr-review` (`mol-adopt-pr`, `mol-pr-merge-only`, `mol-pr-revert` and the
  `review-pr` skill), `pr-pipeline` (`mol-pr-from-issue` and `mol-pr-ship`),
  `gastown` (the refinery patrol and the mayor's prompt), and the skills in
  `compound-engineering`, `gstack` and `superpowers` that file a plan or a
  deferred task as an issue or open a PR, all write to the repository the work
  belongs to. Several hold the write for the mayor or the user to run or
  confirm. None asks about a disclosure channel.
- `compound-engineering`'s code review has a security lane, and `gstack`'s
  review has a security specialist. Both judge a diff for security problems.
  Neither sends a report anywhere.

### Gas City's trust model and outbound messaging

[Trust Boundaries](https://docs.gascity.com/reference/trust-boundaries) covers
which commands run and which secrets reach them, and has nothing that scopes or
checks where an agent writes on GitHub, as the gh write containment warrant
records. External messaging (`/v0/city/{cityName}/extmsg/outbound`, in the
[Connect an external client](https://docs.gascity.com/guides/connected-clients)
guide) delivers an agent's reply to a connected client's callback. It is not a
send to a repository.

### bd

bd's matches are its own `SECURITY.md` and the word disclose in its HTTP API
and CLI, for what a response reveals to its reader. bd has nothing about a send
to another project.

## What the change adds

It adds no pack noun: no bead kind, lifecycle state or metadata key, so it takes
no warrant. The surface is an option and a mode of a script the pack already
ships. The reading rides the parked bead's description and the visit's message,
and the report mode keeps the bead's existing keys. The answer changes when Gas
City, or a pack it publishes, checks a target's security policy before an
agent's write to another project, or files a private vulnerability report. The
gate or the report mode then moves onto it.
