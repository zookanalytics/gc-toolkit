---
name: Visit-to-PR comment reminder
description: A visit posts a comment on its subject's PR when it engages and updates that comment when it closes, leaving a context reminder on the PR that the conversation happened. Covers the engage and the three close writers, the marker-keyed comment upsert, and origin safety.
---

# Visit-to-PR comment reminder

A visit is a bounded human conversation filed against a subject bead
(`docs/gascity-human-engagement.md`). When that subject has an open PR, the
conversation happens off to the side and leaves no trace on the PR itself, so
someone reading the PR later has no reminder that a discussion took place or
what came of it.

This adds that trace. When a visit **engages** — an operator draws it off the
helm board and a sitting spawns — a comment is posted to the subject's PR:

```
### Visit <visit-id> — open
- Subject: <subject-id>
- Reason: <reason>
```

When the visit **closes**, that same comment is updated in place:

```
### Visit <visit-id> — closed (<outcome>)
- Subject: <subject-id>
- Reason: <reason>
- Summary: <the sitting's takeaway>
- Actions Taken: <what the sitting did>
```

The comment carries a hidden marker `<!-- gc:visit:<visit-id> -->` so the
close finds the exact comment the engage posted. One comment per visit: a
subject with several visits over its life accumulates one open/closed comment
each.

## Why this is useful beyond a reminder

An open visit on a PR-bearing bead already holds the PR's merge:
`merge.sh`'s in-flight-holder filter reads the subject's `pr_number`, finds
the open visit tracking it, and holds the merge until the visit closes
(`assets/scripts/merge.sh`, the `PR#... held by ...; merge held` arm). Before
this change, that hold is invisible on the PR — the merge is paused with
nothing on the PR to say why. The "Visit … open" comment is that explanation,
and the "closed" update is the signal that the hold has lifted.

## The events it hooks

The engage is one chokepoint; the close is three writers, because a visit
closes three ways and the normal one never runs a helm verb.

| Event | Writer | Where |
|---|---|---|
| engage | `gc-helm.sh cmd_engage` | after the sitting binds the visit |
| close (normal sign-off) | `converse-signoff.sh` | after the takeaway is written, before the agent closes the visit |
| close (operator dismiss) | `gc-helm.sh cmd_dismiss` | after each visit closes |
| close (moot / benign) | `converse-close-out.sh` | after the visit closes |

The normal close is done by the converse agent itself
(`agents/converse/prompt.template.md`: run `converse-signoff.sh`, stamp
`gc.outcome`, `gc bd close`), not by a helm verb. `converse-signoff.sh` is the
reliable point on that path: it always runs immediately before the close and
holds the visit id, the subject, and the outcome. Hooking it needs no change
to the converse prompt.

The Go helm service owns no visit logic — `POST /helm/open` is a thin exec
wrapper around `gc-helm.sh open` (`services/helm/internal/visit/opener.go`),
and there is no Go-native engage, dismiss, or close. So `gc-helm.sh` is the
sole engage and dismiss chokepoint and no Go change is required.

## The comment primitive

`assets/scripts/pr-visit-comment.sh` is a new standalone script with two
modes:

- `engage --visit <id> --subject <id> [--reason <text>]` — upsert: find the
  marked comment, create it with `gh pr comment` if absent, edit it with
  `gh api --method PATCH /repos/{owner}/{repo}/issues/comments/{id}` if present.
  Leaves the comment in its "open" shape.
- `close --visit <id> --subject <id> [--outcome <word>] [--summary <text>] [--actions <text>]`
  — update-only: find the marked comment and edit it to its "closed" shape. If
  no marked comment exists, do nothing.

`close` is update-only, never create, for two reasons. A visit that closed
moot or benign usually never engaged (its premise died between filing and
claiming), so there is no comment and nothing to say on the PR. A visit that
did engage and then benign-closed has an "open" comment that must not be left
saying "open" forever. Update-only satisfies both: it closes the comment when
one exists and is silent when none does. That is why all three close writers
call the same `close` mode, including `converse-close-out.sh`, whose own thread
output stays silent by design — the PR comment is a different surface from the
conversation thread.

`close` does not take a reason. It preserves the `Reason:` line from the
comment the engage wrote, so the reason a visit opened with is the reason its
closed comment still shows. Each field is written on one line (newlines
collapsed to spaces), which keeps that read-back exact.

## PR discovery and origin safety

The subject carries `pr_number` / `pr_url`, written by `pr-open.sh` when the
PR opens and documented in `lifecycle/lifecycle.toml`. The script reads them
with the same `jq` the conversation reader uses
(`assets/scripts/converse-pr-conversation.sh`): prefer `pr_number`, fall back
to the integer after `/pull/` in `pr_url`. A subject with neither is a bead
with no PR, and the script exits 0 having done nothing.

Every `gh` call is pinned to the origin the checkout resolves, the way
`pr-open.sh` proves: `ORIGIN_HOST` / `ORIGIN_REPO` / `ORIGIN_REPO_Q` from
`git remote get-url origin`, and `gh pr comment --repo "$ORIGIN_REPO_Q"`. Where
the subject carries a `pr_url`, its repository is checked against
`ORIGIN_REPO_Q` before anything is posted, and a PR that resolves elsewhere is
refused. `gh api` is not one of the five verbs the `gh-origin-guard.sh`
PreToolUse hook covers and it runs inside a script in any case, so the pin is
the guard here, exactly as it is for the other in-script `gh` writes.

The script fails safe. A missing `gh` (`command -v gh || exit 0`), an
unresolved origin, a subject with no PR, or a `gh` call that errors all leave
the visit lifecycle untouched: the comment is a reminder, and a reminder that
cannot be posted must never break an engage or a close.

## Summary and Actions Taken

The close writers pass what they hold. `converse-signoff.sh` passes its
`--outcome` — the sitting's takeaway, the agent-generated one-line conclusion
already bounded to 140 characters — as the Summary, and composes Actions Taken
from what it did: the ruling and release on `--ruled yes`, the beads it routed
work into on `--waiting-on`, or what is still owed. `cmd_dismiss` passes the
dismissal reason. `converse-close-out.sh` passes its reading.

The takeaway is the Summary the shell has in hand. The richer sign-off prose
the agent posts to the conversation thread is its stdout, not a value a script
can capture, so carrying it to the PR would need a new passthrough on the
sign-off and a converse-prompt change. That is a later enhancement, not a
requirement of the reminder.

## Files

- `assets/scripts/pr-visit-comment.sh` — new; the comment primitive.
- `assets/scripts/pr-visit-comment.test.sh` — new; hermetic coverage of engage,
  close, upsert, update-only, no-PR, and not-ours.
- `assets/scripts/gc-helm.sh` — `cmd_engage` posts on engage; `cmd_dismiss`
  updates on dismiss.
- `assets/scripts/converse-signoff.sh` — updates on the normal close.
- `assets/scripts/converse-close-out.sh` — updates on moot / benign close.
