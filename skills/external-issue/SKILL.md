---
name: external-issue
description: Use when you have identified a bug, gap or vulnerability in software this rig does not own, or when a gh write to such a repository was refused.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# External issue: a problem in software this rig does not own

An issue, a pull request, a comment or a review on a repository outside this
rig's origin spends someone else's time, so the operator makes that send. You
prepare it and park it, ready to paste, and they decide whether it goes.
`gh-origin-guard.sh` refuses the write when an agent types it. That refusal is
the boundary, so answer it by parking the command, never by finding another way
to send it.

When a rig of this city owns the software, the finding is work for that rig
rather than a send: `gc rig list` names the rigs, and the `gc-toolkit.work`
skill files the bead there.

The pack's `docs/outbound-sends.md` holds the reasons, where the line sits,
everything the script refuses and what the operator gets.

The writers are the gc-toolkit pack's own scripts.
`gc <binding> scripts-dir` prints their directory in the pack as gc loaded it,
so each example calls the pack's copy inside the command itself, and runs in a
fresh shell. `<binding>` is the name the city imports the pack under, which gc
puts in front of this skill's name: `gc-toolkit` in `gc-toolkit.external-issue`.
`gc skill list` prints it in this skill's FROM column.

## Read the target's security policy first

A public send is published as written the moment it is pasted, so read the
target's security policy before you park anything. The first call says whether
a repository has a policy, its owner's default included, and where it is. Read
the page it names. The second answers `{"enabled":true}` where the repository
takes private vulnerability reports:

```bash
gh api graphql -f query='{repository(owner:"<owner>",name:"<name>"){isSecurityPolicyEnabled securityPolicyUrl}}'
gh api repos/<owner>/<name>/private-vulnerability-reporting
```

For a repository on another GitHub host, add `--hostname <host>` after `gh api`.

When the policy asks for a finding like yours in private, use the private
channel it names. A vulnerability in a project with no policy goes the same way:
a private report where that is enabled, and otherwise the operator. Anything
else is a public send.

## Park a public send

```bash
"$(gc <binding> scripts-dir)/upstream-finding.sh" \
  --message "<what you found, where you hit it, why it earns the send>" \
  --security-policy "<the target's security policy as you read it, and why it lets this report be public>" \
  -- gh issue create --repo <owner>/<name> --title "<title>" --body "<body>"
```

This files one bead carrying the exact command, ready to paste, and a visit
asks a human for the send. A pull request or a comment parks the same way.
`--message` is what the operator reads to decide, and the `gh` body is written
for the maintainer. Name the target with `--repo` and write the body inline: the
operator pastes the command later, from their own shell, where an implicit
repository resolves somewhere else and a file you wrote is gone. A refusal from
the script says what to change.

## Park a private vulnerability report

```bash
"$(gc <binding> scripts-dir)/upstream-finding.sh" \
  --message "<what you found, where you hit it, why it earns the send>" \
  -- gh api --method POST repos/<owner>/<name>/security-advisories/reports \
       -f summary="<one line>" -f description="<the report>"
```

The report goes to the repository's maintainers, not to a public page, so it
needs no `--security-policy`. Write the owner and name out in the endpoint: `gh
api` has no `--repo`, and a `{owner}` or `{repo}` placeholder fills in from
wherever the command is pasted.

A vulnerability stays out of everything public until it is fixed: your commit
messages, your pull request's title and summary, your bead's description, which
the pull request publishes, and any file in a public repository.

## Hand a channel `gh` cannot reach to the operator

A private channel `gh` cannot reach, such as a security email address, is the
operator's to use, and so is a project hosted off GitHub. Park nothing public.
File a bead of its own for the finding (the `gc-toolkit.work` skill), because an
open visit holds its subject's merge and your work does not wait on this. Then
ask on that bead:

```bash
"$(gc <binding> scripts-dir)/escalate.sh" --subject <that bead> --key report-owed \
  --message "<the channel the policy names, and the report to send there>. Closing <that bead> answers this, sent or declined."
```

## Then carry on

Go back to your bead. The send is not yours to wait on.
