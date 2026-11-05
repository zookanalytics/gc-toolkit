---
name: external-issue
description: Use when you have identified a bug, gap or vulnerability in software this rig does not own, or when a gh write to such a repository was refused.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# External issue: a problem in software this rig does not own

A problem you find in someone else's software is worth keeping, and what to do
about it upstream is the operator's decision, made when they choose to look.
So you record it as an upstream finding and go back to your work. You draft
no issue, comment or command for the other project, and you ask the operator
nothing. The finding waits, set aside, in one list they open when they are
ready.

`gh-origin-guard.sh` refuses a `gh` write you type to a repository outside this
rig's origin. That refusal is the boundary, so answer it by recording the
finding, never by finding another way to send.

When a rig of this city owns the software, the problem is work for that rig
rather than an upstream finding: `gc rig list` names the rigs, and the
`gc-toolkit.work` skill files the bead there.

The pack's `docs/outbound-sends.md` holds the reasons and where the line sits.

## Record an upstream finding

First look for one already recorded on the same problem. This lists the
upstream findings in every store of the city, closed ones included:

```bash
gc beads list --label upstream-finding --all
```

When an open one covers your problem, add what you know to its notes and file
nothing:

```bash
gc bd update <finding> --append-notes "<what you found, where you hit it, and any new evidence>"
```

For a closed one, `gc bd show <finding>` gives the close reason, which says
what became of it. A decline stands, so file nothing. A problem that came back
after a fix is a new finding that names the closed one.

Otherwise file one. It lands in the store you are working in:

```bash
gc bd create "<project>: <what is wrong, in one line>" -t task --status deferred \
  -l upstream-finding --metadata '{"task_kind":"upstream-finding"}' \
  --deps "discovered-from:<your work bead>" --json -d "## What is wrong
<what you found>

## Where it was hit
<your work bead, and what you were doing when you hit it>

## Evidence
<a reproduction, the versions involved, links>

## Project
<the project it belongs to: owner/name on GitHub, or where it lives>

## Security
<whether it looks like a security flaw, and why>"
```

The deferred status keeps it out of every ready queue, the label puts it in the
operator's list, and the discovered-from edge ties it to the work where you hit
it. When your work bead lives in another store, leave `--deps` out: the
description names it. Read the finding back:

```bash
gc bd show <finding> --json | jq -r '.[0] | "\(.status) \(.metadata.task_kind // "-") \(any(.labels[]?; . == "upstream-finding"))"'
```

It prints `deferred upstream-finding true`. A create that printed no id filed
nothing, so run it again.

Whether a report goes out is the operator's call when they pick the finding
up, and whether it goes as a public issue or a private one follows that
project's security policy, read then. So nothing you write now chooses the
channel.

A vulnerability stays out of everything public until it is fixed: your commit
messages, your pull request's title and summary, your work bead's description,
which the pull request publishes, and any file in a public repository. Its
details go in the finding, which stays in the store.

## Then carry on

Go back to your bead. A workaround in our code is part of your work, built and
reviewed the usual way, and nothing waits on the finding.

## Pick an upstream finding up

The operator picks a finding up by holding a conversation on it, and you hold
that conversation. With them, check first that the problem still exists
upstream: read the project's latest release and its open and closed issues, and
run the reproduction again where you can.

Then read the project's security policy. The first call says whether the
repository has one, its owner's default included, and where it is: read the
page it names. The second answers `{"enabled":true}` where the repository takes
private vulnerability reports. For a repository on another GitHub host, add
`--hostname <host>` after `gh api`.

```bash
gh api graphql -f query='{repository(owner:"<owner>",name:"<name>"){isSecurityPolicyEnabled securityPolicyUrl}}'
gh api repos/<owner>/<name>/private-vulnerability-reporting
```

Draft the report the policy calls for, with the operator. It is private when
the policy asks for a finding like this one in private, and for a vulnerability
in a project with no policy, and it goes through the channel the policy names,
such as the repository's private vulnerability reporting or a security address.
Otherwise it is a public issue. The operator makes the send. You never do,
however it is routed.

Once the operator has sent it or decided not to, close the finding the way the
`gc-toolkit.work` skill closes a bead that needs no work, with this
conversation as its evidence. The note names what was sent and where, why it
was declined, or the upstream fix that made it moot.

When the operator wants to come back to it later, the finding stays as it is,
deferred and in the list. Nothing waits on it, so the sign-off takes
`--no-wait`, and nothing routes, arms or parks it.
