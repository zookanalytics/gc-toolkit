---
name: Outbound sends
description: Use when you need to know what becomes of a problem an agent finds in software the rig does not own, why no agent writes to that project's repository, or how the operator takes such a problem up when they are ready.
---

# Outbound sends

Filing an issue, opening a PR, or leaving a comment on a repository the rig
does not own spends someone else's time. That is a higher bar than spending
ours, and it is the operator's bar to set: whether to send anything, what, and
through which channel. So an agent that finds a problem in someone else's
software records it and goes back to its work, and the problem waits for the
operator, set aside, until they choose to look.

## Scope

**Mandate.** What becomes of a problem an agent finds in software the rig does
not own: how it is recorded, how it waits, and how the operator takes it up.

**Boundaries.** This covers GitHub writes issued through `gh`. It does not
speak for our own repository — a send to the rig's origin is ordinary work,
and PRs on it go through [`pr-open.sh`](../assets/scripts/pr-open.sh). A
problem in software another rig of this city owns is work for that rig. The
commands an agent runs are the
[`gc-toolkit.external-issue`](../skills/external-issue/SKILL.md) skill, how the
guard refuses an agent's own write is [gh-origin-guard.md](gh-origin-guard.md),
and who may act on what is [authority-map.md](authority-map.md).

## The boundary is the rig's own origin

The line is per-rig, drawn at the origin remote of the checkout the agent is
standing in — never an organization allowlist. Rig origins do not share one
org: a rig whose origin sits outside the city's usual org would have its whole
PR workflow refused by an org-keyed rule, while an upstream repo inside that
org would sail through it. The origin remote is the only reading that matches
what "we own this" means, and it is the reading
[`pr-open.sh`](../assets/scripts/pr-open.sh) already pins its own `gh pr
create` to.

## An agent records an upstream finding

The agent files an upstream finding: a bead in the store it works in, carrying
`task_kind=upstream-finding` and the `upstream-finding` label, created in bd's
`deferred` status. Its description says what is wrong, where the agent hit it,
the evidence (a reproduction, the versions involved, links), the project it
belongs to, and whether it looks like a security flaw. A `discovered-from`
edge ties it to the work bead where it was hit. When one already covers the
same problem, the agent adds to its notes instead.

Nothing is drafted for the other project, and nothing asks the operator
anything:

- **Out of every ready queue.** bd's deferred status is its own state for work
  deliberately set aside to be revisited, and neither `bd ready` nor Gas
  City's `gc ready` serves a deferred bead, so no pool claims a finding.
- **Off the list of what the operator owes.** No human gate is filed, and no
  reader that offers work or asks the operator takes a finding for demand. The
  liveness sweep and the proactive scan read only ready work, and the helm
  board and the doctor checks admit a bead on a mark a finding does not carry,
  such as a human gate, a route to the operator, an arm or a merge state.
- **The agent's own work carries on.** A workaround in our code is that work's
  business, built and reviewed the usual way, and nothing waits on the
  finding.

Drafting a report at finding time would make the agent that found the problem
choose its channel, a public issue or a private report, before anyone has read
the project's security policy. Nothing is drafted until the operator picks the
finding up, so that choice is made once, there, from the policy.

## The operator's list

One command lists every upstream finding across the rig stores and the city
store: `gc beads list --label upstream-finding`. Gas City reports bd's
deferred status as `open`, so a finding waiting in the list shows as open.
`--all` adds the closed ones, and each one's close reason says what became of
it.

## Picking one up

The operator opens a conversation on a finding through the engage path:
`gc-helm engage <finding> --skill external-issue`. The sitting checks that the
problem still exists upstream and reads the project's security policy. With
the operator it drafts the report that policy calls for, a public issue or a
private report through the channel the policy names. The operator makes the
send. Sent, declined, or found fixed upstream, the sitting then closes the
finding with a note saying which, and a finding the operator wants to come
back to stays in the list as it was.

The keeper's fork workflow prepares its own `gh` commands inline, in
`packs/gascity-keeper/formulas/mol-upstream-gc-pr-prep.toml`, where the PR
title and body are drafted with the operator over several turns before either
exists. That path is its own, and this one is for a problem an agent hits
while working something else.

## What the path does not do

No agent sends, however a write is routed: the operator makes every send, and
the guard refuses a write an agent types to a repository the rig does not own.
Recording a finding judges nothing about whether it deserves an upstream
report, which is the operator's call when they pick it up. And it is scoped to
`gh`: other outbound writes are not covered here.
