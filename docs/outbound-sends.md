---
name: Outbound sends
description: Writing to a GitHub repository the rig does not own is the operator's send, not an agent's. How an agent preserves such a finding — a bead carrying the ready-to-paste command, and a visit that asks a human — how the target's security policy decides between a public send and a private vulnerability report, and what the path refuses so the parked command still works when it is pasted.
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
repository: where the finding lands, whether its text may be public, what makes
the parked command pasteable, and how a human is asked.

**Boundaries.** This covers GitHub writes issued through `gh`. It does not
speak for our own repository — a send to the rig's origin is ordinary work,
and PRs on it go through [`pr-open.sh`](../assets/scripts/pr-open.sh). Who may
act on what is [authority-map.md](authority-map.md); how a visit reaches a
person is [human-engagement.md](human-engagement.md).

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
  --security-policy "<owner>/<name> has no security policy, and this is a rendering bug." \
  -- gh issue create --repo <owner>/<name> --title "<title>" --body "<body>"
```

Everything after `--` is the command, verbatim; the script runs no `gh` and
reaches no network. `--message` is separate from the `gh` body on purpose: the
body is written for the upstream maintainer, and the operator is deciding
something else — whether this is worth another project's attention — so they
need what was found, where it was hit, and why it earns the send.

## Public or private

A parked send is pasted as it stands, so whether its text may be public is
settled before it is parked. An issue, a PR or a comment is public the moment
it is pasted, so the script parks one only with `--security-policy`: the
target's security policy as the preparer read it, and why it lets this report
be public. GitHub says whether a repository has a policy, its owner's default
included, and where it is:

```bash
gh api graphql -f query='{repository(owner:"<owner>",name:"<name>"){isSecurityPolicyEnabled securityPolicyUrl}}'
```

The reading rides the bead and the visit beside the command, so the operator
weighs it before pasting. A public send without one is refused, and the refusal
names the commands below for its target.

When the policy asks for a finding like this one to be reported privately, the
parked send is the private channel the policy names. GitHub's private
vulnerability reporting is one, where the repository enables it, which
`gh api repos/<owner>/<name>/private-vulnerability-reporting` reports as
`{"enabled":true}`. The report goes to the repository's maintainers, not to a
public page, and parks as a `gh api` call:

```bash
assets/scripts/upstream-finding.sh \
  --message "<what was found, where it was hit, why it earns the send>" \
  -- gh api --method POST repos/<owner>/<name>/security-advisories/reports \
       -f summary="<one line>" -f description="<the report>"
```

It needs no `--security-policy`, and a reading given with it is recorded the
same way. `gh api` has no `--repo`, so the report names its repository in the
endpoint path, and literally: a `{owner}` or `{repo}` placeholder fills in from
the directory the command is pasted in. GitHub requires the `summary` and
`description` fields, so a report without either is refused, as is a method
other than POST. The private report is the one `gh api` write the path parks.

A private channel `gh` cannot reach, such as an email address, is the
operator's to use. Ask through [`escalate.sh`](../assets/scripts/escalate.sh)
with the report in the message, and park nothing public.

## What keeps the command pasteable

These refusals keep the parked command honest, because it is pasted later, by
a person, somewhere else:

- **No named repository, no parking.** `gh` resolves an implicit repository
  against the current directory, and the operator's directory is not the
  agent's. A command names its target with `--repo`, and a private report in
  its endpoint path. A `--repo` present but naming no repository — a following
  flag taken as its value, or a bare word that is not `owner/name` — is refused
  the same way, because `gh` cannot resolve that either. So is a `--repo` on
  `gh api`, which has no such flag.
- **No value read from a file.** A path is not a body; the file is gone by the
  time anyone pastes the command. `--body-file` and `-F` are refused in every
  spelling. So are `gh api`'s `--input`, which reads the whole request body
  from a file, and its `--field`, which also fills `{owner}` and `{repo}` from
  the directory it runs in. `gh` reads a single-dash word one short flag at a
  time, so `-cF` is `-c -F` and is refused too. A value that begins with F
  therefore goes after a space, not attached to its flag.
- **One target, named once.** A command carrying two different repositories is
  refused rather than resolved by guessing, which is the one mistake that
  sends a report to the wrong project.
- **No interactive prompt.** A write verb that stops to prompt for a field it
  was not given — `gh issue create` with no `--title` or `--body` value, a
  comment with no `--body` — is refused. `gh` reads the omitted field from a
  prompt, so a parked command missing it would wait instead of carrying the
  prepared text. A flag whose value is the next flag counts as missing: `gh`
  takes that flag as the value and prompts anyway.

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
| `gh_verb` | the `gh` verb, for the board label (`api` for a private report) |
| `upstream_send_key` | the situation key that keeps one ask from becoming three |

The description says whether the send is public or a private report, and
carries the security-policy reading when one was given. The visit says both
beside the command.

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
it. It does not read the target's security policy either. It contacts nothing,
so the preparer reads the policy, and the script holds a public send until that
reading is on it. And it is scoped to `gh`: other outbound writes are not
covered here.
