---
name: gh origin guard
description: The PreToolUse hook that refuses agent-typed gh writes aimed outside a repository we own, and posts on one we own that carry no city mark — which verbs it covers, how it resolves the target, what it deliberately does not cover. Read it before changing the guard or adding an agent.
---

# gh origin guard

One bot account backs every agent's `gh` token, so any agent can write to any
repository that token reaches. Filing an issue, opening a PR, or leaving a
comment on someone else's repository spends a stranger's attention. That
decision belongs to the operator, and the guard is where the boundary is
enforced rather than requested.

The implementation is a Claude Code `PreToolUse` hook at
`assets/scripts/gh-origin-guard.sh`, registered for every claude-provider agent
by the overlays in `pack.toml`.

## What it refuses

Five write verbs: `gh issue create`, `gh issue comment`, `gh pr create`,
`gh pr comment`, and `gh pr review`. Each is refused when the repository it
targets is not one the session owns. `gh issue new` and `gh pr new`, gh's
aliases for the two create verbs, are folded to `create` and refused the same
way.

`gh api` reaches the same REST endpoints. A call whose method writes — POST,
PATCH, PUT, or DELETE, set with `-X`/`--method` or defaulted to POST by gh when
fields are added — is refused when its endpoint names a repository the session
does not own. The repository comes from the endpoint path, not from a flag.

Reads are untouched. `gh issue view`, `gh pr view`, `gh pr diff`, `gh search`
and the rest reach any repository normally, so research on an upstream project
keeps working.

A refusal names the repository it stopped, names the repositories the session
may write to, and points at the prepare-a-command path so the agent learns the
route instead of only meeting a wall. When `gh` picked that repository from the
working directory's remotes, the refusal also says how it picks.

On a repository the session does own, a post is held to one more rule, below.

## Posts carry the city's mark

The city posts under the same GitHub login an operator's review tools can use,
so `assets/scripts/pr-facts.sh` tells the city's own posts from feedback by the
mark `assets/scripts/pr-post.sh` appends, not by the author
([state-machine.md](state-machine.md#operator-feedback)). An unmarked post under
the city's login reads back as feedback, and the reconcile routes it into a
rework child whose fixer answers the city's own words. A write that passes the
origin rule and posts is therefore refused unless its body carries the mark.
`tools/lint-learned.d/pr-post-bypass.sh` holds the pack's scripts and recipes to
the same rule; the guard holds the commands an agent types, which no lint sees.

The posts it reads:

- `gh pr comment`, `gh issue comment` and `gh pr review`. The body comes from
  `--body`/`-b` or from the file `--body-file`/`-F` names, the last one given
  winning, the way gh reads them. `--delete-last` posts nothing and passes.
- `gh api` with a writing method on a comment, reply or review endpoint:
  `issues/<n>/comments`, `issues/comments/<id>`, `pulls/<n>/comments` and the
  paths under it, and `pulls/<n>/reviews` and the paths under it. The body is
  the `body` field, or the file a typed `body=@<path>` field or `--input` names.
  A reaction, a dismissal, a reviewer re-request and a DELETE carry no body and
  pass.
- `gh api graphql` with a mutation that posts or edits a comment or review
  body, such as a thread reply. Its body rides in a variable of any name, so the
  call passes when any field value, or a file a typed field names, carries the
  mark. It names no repository, so the origin rule does not measure it.

A body carries the mark by `pr-post.sh`'s own definition (`gc_city_marked`, which
`pr-post.sh own-def` prints and the guard reads from beside itself):
`<!-- gc:city -->`, or the write-back's `<!-- gc-writeback -->`. The guard reads
a body it can see: an inline value, or a file it can open, resolved against the
directory the call runs in. A body the shell builds as the command runs
(`--body "$(cat f)"`, `--body "$B"`), standard input, and an editor or browser
body cannot be read, so they are refused. An approval and a change request are
refused whatever their body carries, because the city posts COMMENT reviews
only.

A post found inside a here-document body is not held to the mark. A body is far
more often text an agent is writing, a note or a doc that names these commands,
than commands it runs, and the mark rule would refuse every such mention. The
origin rule still reads a body, so a body fed to a shell is measured as before.
Quote state starts fresh on each side of a body, so a quote inside one cannot
hide the commands after it.

The refusal names `pr-post.sh` by its path beside the guard. The helper appends
the mark, so posting through it is the fix, and a body that already carries the
mark may be posted as it is.

## The boundary is an origin, not an organization

The allowed repository is resolved from a rig's own `origin` remote. This is
the same shape `assets/scripts/pr-open.sh` already proves, where every read and
the create are pinned to `ORIGIN_REPO_Q` derived from `git remote get-url
origin`.

An organization-keyed rule would be wrong in both directions. The
`shutupandlisten` rig's origin is `suandl/shutupandlisten`, outside the
operator's org, so an org allowlist would refuse that rig's entire PR flow.
Meanwhile an unrelated repository inside the org is still not a repository that
rig should write to.

## How a target is resolved

The guard resolves the target the way `gh` itself does, in the same order:

1. A `<url>` operand on `gh issue comment`, `gh pr comment`, or `gh pr review`.
   These verbs take a `{<number> | <url>}` argument, and given a URL `gh` reads
   the repository straight from it — so the URL is the target even when a
   `--repo` disagrees. A bare number or a branch name names no repository and
   falls through to the steps below.
2. An explicit `--repo` or `-R` on the command, in any of gh's spellings and
   whether it stands before or after the noun. A selector given more than once
   binds to its last value, the way gh lets a command-level flag override a
   global one.
3. `GH_REPO`, whether set inline on the `gh` command, exported earlier on the
   same command line, or ambient in the environment.
4. The repository `gh` picks from the working directory's remotes, described
   below.

The working-directory step is the one that matters most. `gh` with no `--repo`
writes to whatever repository the working directory belongs to, so an agent
standing in a clone of someone else's project sends there with no flag to
inspect. A guard that read only the explicit flag would wave that through.

`gh` does not read the `origin` remote first. It ranks the remotes upstream,
github, origin, then the rest by name. It takes the first of them that
`gh repo set-default` marked, which is a remote whose
`remote.<name>.gh-resolved` git config is set. A value of `base` means that
remote's repository, and an OWNER/REPO value means that repository on the
remote's host. With no remote marked, and no terminal to ask in, `gh` takes the
first remote in that order. A clone whose `origin` is ours and whose `upstream`
is someone else's therefore writes to the upstream repository unless `origin`
is marked, and the guard measures that repository, not `origin`.

`gh` skips a remote whose URL names no repository, such as a local path, and
reads a remote's push URL when its fetch URL names none. Before choosing, it
narrows the remotes by forge, using the hosts it is logged in to, or `GH_HOST`
alone when that is set. The guard does not read `gh`'s login configuration, so
it makes the choice twice: among every remote, and among the remotes on the
forge the call uses, which is `GH_HOST` or else `github.com`. The two agree in
any checkout whose remotes all live on that forge. When they disagree, the
repository `gh` writes to depends on configuration the guard does not read, and
the write is refused. An SSH host alias counts as a forge of its own, because
the guard reads a remote's host as written.

The guard reads a remote URL the way `gh` does, but it does not follow every
form Go's URL parser accepts. A URL carrying a percent escape, a query, or a
port that is not a number is never skipped, so if it would come first the
write is refused. A checkout with more than twelve remotes is refused as well,
because with more than twelve, `gh`'s sort can reorder remotes of equal rank.

An owner/name given without a host is completed with the host `gh` would use:
`GH_HOST` set inline on the command, exported earlier on the same line, or
ambient in the environment, and `github.com` when none is set. The same owner
and name on another forge is therefore not a repository we own.

The working directory is not always the one the hook is told about. A `cd`,
`pushd`, or `env -C` earlier on the same command line moves where `gh`
resolves, so the guard follows it: `cd ../their-clone && gh issue create` is
measured against `their-clone`, not against the directory the session was
sitting in. A destination the guard cannot expand, such as `cd "$SOMEWHERE"`,
resolves to no repository and is refused, as do `popd` and the stack-rotation
forms of `pushd`, which return somewhere this single-line scan does not track. A
`cd` inside a subshell is scoped to that subshell, so `(cd elsewhere); gh issue
create` still resolves against the outer directory — the move does not outlast
the parentheses.

Wrappers in front of the command are stepped through to reach it: `env` with its
options and `NAME=VALUE` assignments, and `command`, `nohup`, `exec` and `time`
with the option forms that still run the wrapped command, such as `time -p`, the
`command --` sentinel, and `exec -l`. A `GH_REPO` or `GH_HOST` assignment carried
by one of them counts as if it stood as an inline prefix. `command -v gh` looks
the command up and runs nothing, so it is not a send and is left alone.

Host, owner, and name are all compared, lowercased. The host is part of the
identity, because dropping it would let the same owner and name on a different
forge read as a repository we own.

`gh api` is resolved from its endpoint, because it names the repository there
rather than in `--repo`. The guard reads `repos/OWNER/REPO` from the endpoint
path, accepting a leading slash and a full REST URL, and maps the api host
(`api.github.com`, or `HOST/api/v3` on an enterprise forge) back to the forge
host a remote names. A full URL names its own host. Any other endpoint resolves
on the forge `--hostname` names, or else on the host an unqualified owner/name
is completed with.

The method, the fields, and the endpoint are read from the flags the way gh
parses them. A single-dash token is a run of shorthand flags, so `-iX POST` sets
the method and `-iftitle=x` adds a field, just as `-i -X POST` and
`-i -f title=x` do.

`{owner}` and `{repo}` placeholders, and gh's older `:owner` and `:repo`
spellings, are filled from the repository `GH_REPO` names, or else from the
repository gh picks from the working directory's remotes. A `--hostname` does
not change that pick, because only `GH_HOST` narrows the remotes. gh fills the
placeholders before it reads the host or the
path, and the guard does the same. Only the owner and the name come from that
repository. The host stays the one the endpoint names, and a concrete owner or
name beside a placeholder stays in the target. So
`https://gitlab.example.com/api/v3/repos/{owner}/{repo}/issues` run from our
checkout is a write to `gitlab.example.com`, not to our origin, and
`repos/someone/{repo}/issues` is a write to `someone`'s repository. An endpoint
naming no repository is handled under what the guard does not cover.

## What the session owns

`GC_RIG_ROOT` is authoritative and narrow. A rig agent is measured against its
own rig even while standing in a checkout of something else, and another rig in
the same city is still someone else's repository for it. A rig root that is set
but resolves no origin is broken, not permissive: the owned set is empty and
every write fails closed, rather than widening to the city or the working
directory.

City-scope agents such as the deacon and mechanik carry no rig root and
legitimately work across rigs, so for them the owned set is the origin of every
rig under `$GC_CITY_PATH/rigs`. The working directory's `origin` is the last
resort, used only when neither a rig root nor a city resolves. The owned set is
always read from `origin`, while the target is the repository `gh` picks, so a
fork clone whose `upstream` is someone else's does not own that upstream.

Resolving to the working directory earlier would make the guard vacuous exactly
where it is needed, since a checkout of someone else's repository would then
authorize its own writes.

## Failing closed

A write verb whose target cannot be established is refused. If no repository we
own can be resolved, or the target resolves to nothing, there is no way to show
the write lands somewhere we own, and "outside" is the safe reading.

The subject of that rule is a write aimed at a repository. A `gh api` write to a
`repos/OWNER/REPO` endpoint with no concrete owner and name, including one whose
placeholders have no `GH_REPO` or working-directory repository to fill them, is
such a write and is refused; an endpoint that names no repository at all is
not, and is left alone rather than refused.

The cost of that choice is small. Every `gh` write in this repo lives inside a
script, and those scripts run in a rig checkout where the origin resolves.

## What it does not cover

The hook inspects the command an agent types into Bash. These are outside it:

- **`gh` inside a script.** Running `assets/scripts/pr-open.sh` shows the hook
  that command, not the `gh` calls the script makes. Those scripts already pin
  `--repo` to an origin they resolve themselves.
- **graphql and non-repository `gh api` endpoints.** A `gh api` write to a
  `repos/OWNER/REPO` endpoint is covered, but a graphql mutation carries its
  repository in the query body, and an endpoint such as `gists` or `user` names
  no repository to measure. The origin rule leaves both alone; a graphql
  mutation that posts is still held to the mark.
- **Codex agents.** `dog` and `polecat-codex` never read
  `.claude/settings.json`, so no `.claude` hook reaches them.
- **A missing `jq`.** The hook parses its payload with `jq` and stays silent
  without it.
- **A determined bypass.** `bash -c`, a wrapper script, or a here-doc all reach
  `gh` without matching. This guards reach by accident, and it is not a sandbox.

## Wiring

An agent takes exactly one `overlay_dir`. Agents that already ship a hook get
the guard registered inside their own overlay's `settings.json`, and the rest
take `overlays/gh-origin-guard`:

| Overlay | Agents |
|---|---|
| `overlays/work-context` | polecat |
| `overlays/cycle-recycle` | refinery, witness, deacon |
| `overlays/gh-origin-guard` | converse-opus, converse-fable, mechanik, proactive, demo |

Every registration runs the same command, which resolves the script from
`$GC_RIG_ROOT` and then from `$GC_CITY_PATH/rigs/gc-toolkit`. Both are set by
gc. The working directory is deliberately not consulted: the guard is a
security control, and resolving it out of whatever repository an agent happens
to stand in would let that repository supply the code deciding whether its own
writes are allowed.

## Tests

`assets/scripts/gh-origin-guard.test.sh` runs the shipped script against local
repositories with fabricated remotes. It asserts both directions, because a
guard that refuses everything and a guard that refuses nothing are equally
broken and equally quiet.

`assets/scripts/gh-origin-guard-wiring.test.sh` enumerates `agents/` and fails
when a claude-provider agent is left uncovered. An unwired agent is invisible at
runtime, since it looks exactly like one whose writes were all legitimate.
