---
name: Outbound sends
description: Writing to a GitHub repository the rig does not own is the operator's send, not an agent's. How an agent preserves such a finding — a bead carrying the ready-to-paste command, and a visit that asks a human — and what the path refuses so the parked command still works when it is pasted.
---

# Outbound sends

Filing an issue, opening a PR, or leaving a comment on a repository the rig
does not own spends someone else's time. That is a higher bar than spending
ours, and it is the operator's bar to set, so the send is theirs to make. An
agent that finds an upstream bug prepares the command and stops.

Stopping is not dropping. The finding is worth keeping whether or not it is
ever sent, so it lands as a bead carrying the exact command a human can paste,
and a visit asks for the send.

## Scope

**Mandate.** What an agent does with a write aimed outside the rig's own
repository: where the finding lands, what makes the parked command pasteable,
and how a human is asked.

**Boundaries.** This covers GitHub writes issued through `gh`. It does not
speak for our own repository — a send to the rig's origin is ordinary work,
and PRs on it go through [`pr-open.sh`](../assets/scripts/pr-open.sh). Who may
act on what is [authority-map.md](authority-map.md); how a visit reaches a
person is [gascity-human-engagement.md](gascity-human-engagement.md).

## The boundary is the rig's own origin

The line is per-rig, drawn at the origin remote of the checkout the agent is
standing in — never an organization allowlist. Rig origins do not share one
org: a rig whose origin sits outside the city's usual org would have its whole
PR workflow refused by an org-keyed rule, while an upstream repo inside that
org would sail through it. The origin remote is the only reading that matches
what "we own this" means, and it is the reading
[`pr-open.sh`](../assets/scripts/pr-open.sh) already pins its own `gh pr
create` to.

## Preparing a send

[`assets/scripts/upstream-finding.sh`](../assets/scripts/upstream-finding.sh)
takes the command the agent wanted to run and parks it:

```bash
assets/scripts/upstream-finding.sh \
  --message "Hit while working <bead>; the bug is in the pinned <dep> runtime." \
  -- gh issue create --repo <owner>/<name> --title "<title>" --body "<body>"
```

Everything after `--` is the command, verbatim; the script runs no `gh` and
reaches no network. `--message` is separate from the `gh` body on purpose: the
body is written for the upstream maintainer, and the operator is deciding
something else — whether this is worth another project's attention — so they
need what was found, where it was hit, and why it earns the send.

Three refusals keep the parked command honest, because it is pasted later, by
a person, somewhere else:

- **No `--repo`, no parking.** `gh` resolves an implicit repository against
  the current directory, and the operator's directory is not the agent's.
- **No `--body-file`.** A path is not a body; the file is gone by the time
  anyone pastes the command.
- **One target, named once.** A command carrying two different repositories is
  refused rather than resolved by guessing, which is the one mistake that
  sends a report to the wrong project.

The command is quoted with `printf %q`, which collapses a multi-line body to
one pasteable line, and the script then re-splits what it quoted and requires
the original arguments back. Nothing is parked that does not reproduce.

Aiming the path at the rig's own origin is also refused: that send needs no
approval, so asking for one spends the operator for nothing.

## What the operator gets

One bead per situation, carrying the finding in its description and the
command in metadata:

| Key | Value |
|---|---|
| `task_kind` | `upstream-send` |
| `gh_command` | the pasteable command, quoted and round-trip verified |
| `gh_target_repo` | the repository the command writes to |
| `gh_verb` | the `gh` verb, for the board label |
| `upstream_send_key` | the situation key that keeps one ask from becoming three |

The ask itself is a visit, filed through
[`escalate.sh`](../assets/scripts/escalate.sh), which owns the route and its
own dedup. Answering is closing the bead — sent, or declined. A re-run against
an open bead refreshes that one ask; a re-run against a closed one files
nothing, because a settled question is not re-asked.

The keeper's fork workflow prepares its own `gh` commands inline, in
`packs/gascity-keeper/formulas/mol-upstream-gc-pr-prep.toml`, where the PR
title and body are drafted with the operator over several turns before either
exists. That path stays its own; this one is for a finding an agent hits while
working something else.

## What the path does not do

It does not send, and it is not a send path a guard can be talked through: it
never invokes `gh`. It does not judge whether the finding deserves an upstream
report — that judgment is the operator's, and the bead exists so they can make
it. And it is scoped to `gh`: other outbound writes are not covered here.
