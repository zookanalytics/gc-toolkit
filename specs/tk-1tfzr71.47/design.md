---
name: Deploying gc-toolkit by a pinned remote import
description: The design for running gc-toolkit from a commit Gas City fetches and pins, in place of the rig checkout that reconcile-rig-checkouts.sh fast-forwards. It settles the import source and pin, who moves the pin, and how a deploy reaches the controller and live sessions. It also settles which imports stay, what else reads a rig checkout as the deployed pack or as a working tree, what retires with the reconciler, the trial and the cutover, and the implementation units. Read it to rule on the deploy model or to build one of its units.
---

# Deploying gc-toolkit by a pinned remote import

## The decision

Today the city runs gc-toolkit from the rig checkout `rigs/gc-toolkit`, and the
reconciler fast-forwards every rig checkout every 15 minutes so that landed work
goes live. Under this design, every import of the pack names gc-toolkit's
GitHub repository and one commit, written as `version = "sha:<commit>"`. Gas
City keeps that commit as a clone in its pack cache and loads the pack from
there. Deploying landed work means moving the commit, which is one town commit
that one command makes. The reconciler retires, and nothing takes its place
that edits a rig checkout.

Your ruling is on who moves the pin.

1. **The mechanik moves it when a check asks (recommended).** Every 15
   minutes an order compares the pin with gc-toolkit's main. While main is
   ahead, it keeps one deploy bead open for the mechanik. The mechanik runs one
   command, `gc gc-toolkit deploy`, which moves every pin to main's head and
   commits the change. This ships the order, its script and the command. You do
   nothing per deploy, and town commits stay the mechanik's, as the authority
   map has them. Landed work goes live within about 15 minutes plus the
   mechanik's pickup, and each deploy costs one mechanik turn.
2. **The order moves it itself.** The same order runs the command and commits
   to the town repo. This ships the same parts. It also makes the order a
   writer of the town repo, a role the authority map gives only the mechanik.
   And the order would sign and push a town commit with no session behind it,
   which nothing has shown works yet. Landed work goes live within about 15
   minutes, with no agent turn.
3. **You move it.** You run `gc gc-toolkit deploy`, or ask the mechanik to,
   whenever you want landed work live. Only the command ships. Landed work
   waits until you run it.

Under options 1 and 2, a revert also holds automatic deploys until you resolve
the gate it files, because main still names the commit the revert took out
(section 2). Resolving it, once a fix is on main, is one act of yours per
revert. Under option 3 nothing deploys on its own, so a revert needs no hold.

Under every option, a deploy changes every pack agent's start-up config,
because each pinned commit lives in its own cache directory and that config
names the directory. Left to itself, Gas City would then restart the mechanik,
the refinery, the witness and the deacon in place, in the middle of a task when
one is working. It holds one back only while you are attached to it, while it
waits on an answer or while it is pinned awake (`gc session pin`), and for at
most 30 seconds while it is busy, or 2 minutes when its activity cannot be
read. The work a session holds does not hold it back. Under option 1, the
mechanik would restart in the middle of the deploy it is running.

So the deploy command has Gas City accept the change (`gc reload --soft`), and
a deploy restarts no session that is working. One that Gas City reads as idle
can still restart, when the controller reloads the new pin before the
command's request reaches it. Each session takes the new revision when it next
starts. The witness, the deacon and the refinery recycle at the end of their
next turn, through the pack's own drift check. Each new pool worker starts on
it, and the mechanik takes it at its next restart. Until then, a session's
prompt and hooks come from the revision it started from, while the scripts its
steps call come from the new one, as they come from the checkout today.

One change reaches you directly. Once this lands, rig checkouts stop advancing
on their own, and that includes the checkout of the Gas City fork you build gc
from. Only the keeper's step after a fork rebase still moves that one. Pull it
before you build.

The cutover keeps the content the city runs unchanged. It starts once the
checkout holds the effort's merge commit and nothing moves the checkout any
more, and every pin names the commit the checkout holds. Each step is a town
commit that `git revert` undoes.

## Facts this design rests on

Upstream facts were read on 2026-11-06 at Gas City upstream main
`8e75c50aa845` (gastownhall/gascity) and gascity-packs main `796d7ecd73cf`,
from a clone in scratch and through `gh api`. Facts about this repository were
read at main `6dfa90898`. The city's installed gc is the fork build
`e037526466c0`, and fact 12 lists where it was checked to agree.

1. **Sources and constraints.** An import's `source` is a local path, a
   GitHub tree URL, or a clone URL with an optional `//subpath` and `#ref`
   (`remotesource.Parse`, internal/remotesource/remotesource.go). Its
   `version` takes three forms, as docs/guides/understanding-packs.md says:
   none, a semver constraint, or `sha:<commit>`. `ResolveVersion`
   (internal/packman/resolve.go) takes a `sha:` pin as the commit with no
   network listing. Every other form lists the remote's semver tags with
   `git ls-remote --tags` and takes the highest match. A repository with no
   semver tags fails with `ErrNoSemverTags`. So "no constraint" means the
   newest tag, not the newest commit. `gc import add` promotes a local path
   inside a git worktree to a `file://` source locked to its HEAD
   (docs/reference/cli.md, "gc import add").
2. **The lock.** The city has one `packs.lock`, at its root. The loader finds
   the commit for a remote import by its source string,
   `lock.Packs[source]` (`resolveInstalledRemoteImport`,
   internal/config/pack_include.go). `gc import install` merges the
   constraints of every import that names one source, and it refuses two
   different `sha:` pins with "incompatible pinned versions"
   (`mergeConstraints`, internal/packman/install.go). One source string
   therefore resolves to one commit across the whole city. Every install
   rewrites the whole file. `WriteLockfile` (internal/packman/lockfile.go)
   renames a new file over the old one without comparing them, and writes one
   `[packs."<source>"]` table per remote source, holding its `version`,
   `commit` and `fetched` time. `doImportInstall` (cmd/gc/cmd_import.go) calls
   it on every run, and so does the `packv2-import-state` doctor fix that
   re-pins core and bd (`importStateDoctorCheck.Fix`,
   cmd/gc/import_state_doctor_check.go). The file's mtime therefore moves
   whether or not any pin changed.
3. **The cache.** A remote import resolves to
   `$GC_HOME/cache/repos/<sha256 of clone URL and commit>`
   (`GlobalRepoCacheRoot`, internal/config/implicit.go; `RepoCacheKey`,
   pack_include.go). The cache-key function strips the subpath, so a pack and a
   sub-pack of one repository at one commit share one clone. The clone is a
   full `git clone` checked out at the commit
   (`ensureRepoInCacheLocked`, internal/packman/cache.go). cli.md's
   `gc import prune` says the cache "is keyed by (source, commit), so commit
   churn accumulates stale clones". Prune keeps every clone a city's lock
   names and every clone modified in the last 7 days, and it deletes nothing
   without `--apply`.
4. **The loader validates the clone and never fetches.** On load, the
   clone's HEAD must equal the locked commit, and `git status --porcelain`
   (ignored files excluded) must be empty. Otherwise the load fails with
   "cached import ... has local worktree changes; run gc import install"
   (`validateLockedRemoteCache`, pack_include.go). A locked commit whose
   clone is missing fails the load with "is locked but not cached", and the
   remediation names `gc import install` (`validateInstalledRemoteCache`), so
   the load leaves fetching to install.
5. **Install.** `doImportInstall` (cmd/gc/cmd_import.go) resolves the imports,
   writes `packs.lock`, materializes the clones, and then validates the
   composed config. A failed validation is not rolled back: the command says
   "packs.lock is written and any fetched packs remain in the cache".
   `gc import upgrade [name]` re-resolves within the constraints, so it has no
   range to move a `sha:` pin through.
6. **Reload.** The controller watches config source directories, the city
   root among them, and every pack directory recursively (`WatchTargets`,
   internal/config/revision.go; `watchConfigTargets`, cmd/gc/controller.go).
   It ignores only paths under `.gc` and `.beads`
   (`shouldIgnoreConfigWatchEvent`). A write to the city root's `packs.lock`
   therefore marks config dirty, and the next tick reloads it. A failed reload
   keeps the running config: cmd/gc/city_runtime.go logs "config reload: ...
   (keeping old config)". Every reload also re-points each rig's
   `.beads/formulas/` symlinks at the winning layer files
   (`ResolveFormulas`, cmd/gc/formula_resolve.go, called from
   city_runtime.go).
7. **Paths in agent config.** For an imported pack's agent, `{{.ConfigDir}}`
   is the agent's source directory (`resolveConfigDir`, cmd/gc/prompt.go). That
   directory is inside the clone for a remote import. The command,
   `session_setup`, `pre_start` and `session_live` are expanded with it
   (cmd/gc/template_resolve.go). An overlay is copied into the work dir with no
   template pass, and the copy follows symlinks (`copyDirRecursive` and
   `copyFile`, internal/overlay/overlay.go).
8. **What restarts a session.** `CoreFingerprint`
   (internal/runtime/fingerprint.go) hashes the command, `pre_start`,
   `session_setup`, the session setup script, the overlay directory as a path
   string, config-derived copy-file paths, and an allow-list of env keys. A
   session whose stored hash differs has drifted. The v2 reconciler
   (`armConfigDrift`, cmd/gc/reconcile_arms_drift.go) and the legacy one (the
   drift block in `reconcileSessionBeadsTracedWithNamedDemand`,
   cmd/gc/session_reconciler.go) handle a drifted session alike. A session
   that is attached, or whose attach cannot be read, waits. A named session
   pinned awake is never restarted by drift. Any other named session is
   restarted in place, and only its use holds it back: a pending interaction
   holds it, recent activity (output within 2 minutes) holds it for at most 30
   seconds, and activity that cannot be read holds it for at most 2 minutes,
   each counted from the controller's first sight of the drift
   (`driftDeferStep` and `driftBoundedDefer`,
   cmd/gc/reconcile_effect_restart.go; `shouldDeferNamedSessionConfigDrift`,
   session_reconciler.go). Its open work is not read: `driftNeeds` reads no
   work for a named restart, and the legacy restart comes before the work
   check that guards only an ordinary session. An ordinary session is drained
   instead, and its drain waits while it has a pending interaction or open
   assigned work, which the drain's claim fence reads again
   (`configDriftSeatHasLiveWork`). `gc reload --soft` accepts the drift: it
   records the reloaded config's hash as each open session's own, and it
   cancels queued drift drains (cmd/gc/cmd_reload.go). The legacy reconciler
   applies that acceptance in the tick that runs the reload, ahead of the
   tick's drift checks, and also after a reload that found no change
   (`legacyTickPhases` and `softReloadPending`, cmd/gc/city_runtime.go). Under
   v2, an open soft reload accepts each drifted session in the baseline arm,
   which comes before the drift arm (`armBaseline`,
   cmd/gc/reconcile_arms_baseline.go; cmd/gc/reconcile_soft_reload.go).
9. **Import scope.** A city-level import gives the pack's non-city agents to
   every rig that declares no import of that binding
   (`expandCityImportedAgentsForRigs` and `rigDeclaresImportBinding`,
   internal/config/pack.go). Pack commands come only from city-level imports:
   the rig-import loop in `expandPacks` stamps its commands' binding but
   appends none to `cfg.PackCommands`. A rig-imported pack that declares
   `[[service]]` fails to load with "[[service]] is only allowed in
   city-scoped packs". Rig orders are found only in each rig's own pack
   directories and formula layers (`ScanAll`,
   internal/orderdiscovery/discovery.go). So a rig-scoped order in a pack runs
   per rig only through that rig's import. `[defaults.rig.imports]` "ensures
   every new rig automatically imports" the pack
   (docs/guides/gastown-config-recipes.md), and docs/reference/config.md
   describes the defaults table as defaults "that seed generated config". It
   does not stand in for an existing rig's import.
10. **What a session can learn about its pack.** Gas City sets `GC_PACK_DIR`
    for pack commands, orders and doctor checks (cmd/gc/cmd_commands.go,
    cmd/gc/order_store.go, internal/doctor/pack_checks.go), and for no agent
    session. Agent env values are not template-expanded (fact 7). A call to
    `gc gc-toolkit scripts-dir` took 0.18 to 0.20 seconds when measured on
    2026-11-06.
11. **How upstream deploys the packs it develops.** The bundled packs, core and
    bd, ride the gc binary: a city pins each one to the binary's canonical
    commit, and `gc doctor --fix` re-pins it after an upgrade
    (`notCachedRemediation`, pack_include.go). The gascity-packs repository
    publishes content-addressed registry releases, one version per commit with
    a content hash (registry.toml, `make registry-publish`). A city moves to a
    release with `gc import upgrade <binding>`. Its README says "contributors
    hacking on the packs themselves can point `source` at a local clone
    instead". Upstream has no automatic pin bump on merge. Its city shape
    (docs/guides/shareable-packs.md) puts the same remote source and `sha:`
    pin on the city import and on the rig imports.
12. **The deployed fork build.** These were checked to agree at the fork build
    `e037526466c0`: the per-commit cache key, the refusal of a clone with
    local changes, "incompatible pinned versions",
    `expandCityImportedAgentsForRigs`, rig orders found only through a rig's
    pack directories, `gc reload --soft`, and the overlay path in the
    fingerprint. They are leads for the trial and carry no weight as upstream
    evidence.
13. **The town today.** pack.toml imports core and bd from
    `https://github.com/gastownhall/gascity.git//<subpath>` with `sha:` pins,
    and gc-toolkit from `source = "rigs/gc-toolkit"`. Each rig in city.toml
    imports gc-toolkit from the same path. One rig also imports gascity-keeper
    from `rigs/gc-toolkit/packs/gascity-keeper`. The helm `[[service]]` runs
    `["bash", "rigs/gc-toolkit/assets/scripts/gc-helm-svc.sh"]` from the city
    root. The pack's rig-scoped orders are deferred-dispatch,
    feedback-distiller, feedback-miner, liveness-sweep, proactive-scan-sling,
    queue-priority and refinery-reconcile. gc-toolkit's repository is public
    and carries no semver tag.
14. **State on 2026-11-06.** The gc-toolkit store holds no open reconciler
    subject bead (19 closed, `reconcile_rig` set), and no open human gate under
    a `reconcile-diverged-<rig>` key. No rig checkout holds
    `.git/gc-toolkit-reconcile-kept`. The rig checkouts hold 884
    `refs/gc-toolkit/reconcile-set-aside/*` refs, which keep content the
    reconciler moved aside.

## 1. The source and the pin

The pack's imports take the repository's clone URL, and the sub-pack's import
takes the same URL with its subpath:

```toml
# pack.toml (city root)
[imports.gc-toolkit]
source = "https://github.com/<owner>/gc-toolkit.git"
version = "sha:<commit>"

# city.toml, under each [[rigs]]
[rigs.imports.gc-toolkit]
source = "https://github.com/<owner>/gc-toolkit.git"
version = "sha:<commit>"

# city.toml, under the rig that keeps the Gas City fork
[rigs.imports.gascity-keeper]
source = "https://github.com/<owner>/gc-toolkit.git//packs/gascity-keeper"
version = "sha:<commit>"
```

`<owner>` is the repository's origin owner, and `<commit>` is the same full sha
everywhere. The clone-URL form matches the town's core and bd imports. A tree
URL resolves the same way (fact 1), but its `tree/main` reads as though the
import follows main, which a `sha:` pin does not.

**Why a `sha:` pin.** It names the commit a deploy chose, needs no tag or
release, and resolves without listing the remote (fact 1). A semver
constraint would ask three things of this repository:

- a tag on main for each deploy, written by the refinery or an order after a
  landing and pushed under the repository's signing rules;
- a version scheme, which for a pack deployed many times a day carries no
  meaning beyond "newer";
- an answer for a bad tag, since `gc import upgrade` takes the highest
  matching tag, so a revert means deleting a published tag or pinning a sha
  anyway.

In return, `gc import upgrade` would move the pack and its sub-pack together
with no TOML edit. One command that rewrites every pin (section 2) gets the
same result without the tags.

**Why GitHub rather than a `file://` URL of a local clone.** A `file://`
source resolves its pin from the clone's own objects. A deploy would then have
to fetch that clone first, and the deployed pack would depend again on a local
clone's state, which is the coupling the initiative removes. gc-toolkit is
public, so a GitHub source needs no credential (understanding-packs.md,
"Private Packs And Credentials").

**Every import carries the pin.** All of the pack's imports name one source
string, so they share one lock entry and one clone (facts 2 and 3). Writing
the pin on each of them keeps each block readable on its own. A deploy that
missed one would fail `gc import install` with "incompatible pinned versions"
and change nothing. The sub-pack's source string is different, so it has a
lock entry of its own. Install cannot catch a sub-pack pin that differs from
the pack's, and the deploy command's check does (section 2).

## 2. Who moves the pin, and how a deploy goes live

The decision above gives the options. The recommended one rests on three
parts.

**The deploy command, `gc gc-toolkit deploy`.** A pack command, so it runs
from the deployed revision with `GC_PACK_DIR` set (fact 10) and needs no build.
One command owns every step of a deploy, so whoever deploys runs one command
and the steps change in one place:

1. Resolve the target: main's head by `git ls-remote <source> refs/heads/main`
   by default, a named commit with `--to <commit>`, or the commit before the
   last deploy with `--revert`. While deploys are held, a run that would
   deploy main's head refuses, and so does `--revert` ("Reverting a bad
   revision" below).
2. Refuse to run when the town's `pack.toml`, `city.toml` or `packs.lock` holds
   an uncommitted change, since step 6 commits those files whole. Fetch the
   town's origin too, and refuse when the town's branch is behind it, since
   step 6's push would then be refused after the new pin is live.
3. Replace the current pin with the target in every import whose source is
   gc-toolkit's repository, the sub-pack's import included, in `pack.toml` and
   `city.toml`.
4. Run `gc import install`, and `gc reload --soft` as soon as it returns.
   Install fetches the target into the cache, writes the lock and validates
   the composed config (fact 5). The soft reload has Gas City accept the
   changed start-up config of every session, so that no working session
   restarts for the deploy ("How a new revision reaches the controller and
   live sessions", below). Every install the command runs is followed by a
   soft reload.
5. Verify. The soft reload succeeded, `gc import check` passes, both lock
   entries name the target, and `gc gc-toolkit scripts-dir` prints a
   directory inside the target's clone. A refused soft reload is a failed
   verification, because Gas City would then restart the named sessions,
   under option 1 the mechanik running this command among them.
6. Commit the three files to the town repo as one signed commit, and push it
   to the town's origin, as other town commits are. Its message lists
   `git log --oneline <old>..<new>` from the target's clone. Then restart each
   service that resolves the pack when it starts (`gc service restart helm`,
   section 4).
7. If step 4 or 5 fails, or step 6's commit does, the town's HEAD has not
   moved. The command restores the three files from it, runs
   `gc import install` and `gc reload --soft` again, and exits non-zero with
   the reason: the old pin runs again. The old clone is still in the cache,
   so the restore needs no network.
8. Once the commit is made, the new pin stays. The command restarts the
   services even when the push fails, so helm runs the revision the agents
   run. When the push or a restart fails, it exits non-zero, saying that the
   new pin is live and committed, whether it is pushed and why a push was
   refused, and which service did not restart. The message ends with the
   command that finishes the deploy, `gc gc-toolkit deploy --to <target>`.

**A run converges.** When every pin already names the target, steps 3 to 5
leave every pin as it is, and step 6 has no commit to make. The run then
pushes what the town's branch holds that its origin lacks, and restarts the
services. So the command a failed run prints finishes the deploy, and running
a deploy twice leaves the city as one run does.

**The deploy check.** This is an exec order, city scope, on a 15-minute
cooldown. It reads the pack's own pin with `gc import status --json` and main's
head with `git ls-remote`. When the pack is imported by path, or the pin
equals main's head, it does nothing. When main is ahead, it keeps one open
bead labeled `deploy` and assigned to the mechanik. On the first pass it files
the bead with the exact command to run, `gc gc-toolkit deploy`, and nudges the
mechanik. On a later pass it appends main's new head to the open bead.
Several landings before the mechanik acts become one deploy. A held bead
(below) is open too, so a pass during a hold only appends, and the first pass
that finds the bead ready again sends the mechanik the notice the revert
recorded on it.

**The mechanik.** It takes the bead from its hook, runs the command, and
closes the bead with the deploy commit as its outcome. A failed run leaves the
bead open, and the mechanik reports on it what the command printed. When
verification or the commit failed, the old pin runs again, in helm too, since
helm was not restarted. A later run starts the deploy over. When the push or a
restart failed, the new pin runs. A refused push leaves the town's origin
without the commit, and a failed restart leaves that service on the revision
it started from, or stopped. The printed `--to` command, run once the cause is
fixed, finishes the deploy. The bead's description carries the command, so the
mechanik's prompt gains nothing.

Under option 2, the order runs the command itself. Under option 3, you run
it. Both keep the command and drop the bead, except that under option 2 a
revert files one to carry its hold (below).

### How a new revision reaches the controller and live sessions

1. The command's `gc import install` writes `packs.lock` in the city root.
   The controller's watcher marks config dirty, and the next tick reloads
   (fact 6). Every gc CLI call reads the lock when it loads config, so
   `gc gc-toolkit scripts-dir`, formula resolution and prompt rendering take the
   new revision at once. A reload that fails keeps the old config running,
   though the command's own verification catches a revision that fails to load
   before it commits. The new revision is therefore live from step 4, before
   the commit and the push, which is why steps 7 and 8 say which pin runs
   after a failure.
2. The reload re-points the rigs' `.beads/formulas/` symlinks into the new
   clone (fact 6). New molecules pour from it.
3. Each pack agent's `pre_start` names `{{.ConfigDir}}/assets/scripts/...`,
   and each overlay patch names a directory in the pack. All of those now
   resolve inside the new clone, so every pack session's config fingerprint
   changes (facts 7 and 8). Gas City's own handling would restart every named
   session in place, the mechanik, the refinery, the witness and the deacon,
   with no read of the work it holds, and a working one within 30 seconds.
   Under option 1 that includes the mechanik in the middle of its own deploy,
   with the new pin live and the town commit not yet made. The soft reload in
   step 4 keeps that from happening: Gas City records the new config as each
   open session's own, so no working session restarts for the deploy.
   Under the reconciler, the pack's directory never moved, so a landing
   restarted only the sessions whose config text changed. Under the pin, those
   too wait for their next start.
4. A running molecule keeps the step text it was poured with. That is true
   today as well (I9, section 4).

**The soft reload and the controller's own reload.** The watcher sees the
lock that install writes and wakes the controller too (fact 6), so the
controller can reload the new pin before the soft reload reaches it. A named
session that Gas City then reads as idle, with no output for 2 minutes, nobody
attached and no answer awaited, restarts at once, and an idle pool session's
drain can begin. The soft reload cancels a drain that has not finished, and
the command does nothing more about the idle case, which is Gas City's ordinary
handling of an idle session and which the canary watches (section 7). A working
named session's restart comes no sooner than 30 seconds after the controller
first sees the drift (fact 8), and the soft reload is requested as soon as
install returns. Install fetches a new commit's clone before it writes the
lock (`walkImport`, internal/packman/install.go), and after the write it only
checks the cache and validates the composed config (`doImportInstall`).
Validating the city's config with `gc config show --validate` took under half
a second when timed on 2026-11-06. The request therefore reaches the
controller well inside the 30 seconds, and both reconcilers apply the
acceptance ahead of their drift checks (fact 8).

**When sessions take the new revision.** Each session takes it at its next
start, as it took a checkout's new content before. Each new pool worker starts
on it. The witness, the deacon and the refinery recycle at the end of their
next turn, through pack drift, which unit 1 points at the pack's entry in the
lock (section 4). The mechanik takes it at its next restart. Until a session
restarts, its prompt and hooks come from the revision it started from, and
every `gc gc-toolkit scripts-dir` call it makes resolves to the new one. The
soft reload also accepts any other change to the city's config that has not
yet restarted a session, and that change, too, reaches each session at its
next start.

### Reverting a bad revision

`gc gc-toolkit deploy --revert` moves the pin back to the previous commit. Its
clone is still cached, since prune never runs on its own and keeps any clone
younger than 7 days, so the revert needs no network.

**A revert holds automatic deploys.** Main still names the commit the revert
took out, so under option 1 the check's next pass would ask for that commit
again, and under option 2 the order would deploy it again by itself. Before it
moves the pin, the revert therefore files a human gate on the deploy bead with
`human-gate.sh`, under the key `deploy-held`, and files the deploy bead first
when none is open. The gate's message names the rejected commit and says how
to resume.

While the gate is open, a run of the command that would deploy main's head
refuses and prints the gate, and so does a second `--revert`, whose previous
commit is the rejected one. `--to <commit>` still deploys a commit you name.
Under option 1 the deploy bead is labeled `deploy` and assigned to the
mechanik, as the check files it. The gate keeps it out of `bd ready`, so the
mechanik's hook does not offer it, and the check's passes only append main's
new head to it. Under option 2 the order reads the gate before each run and
runs nothing while it is open.

Resolving the gate (`bd gate resolve`) is the resume. You resolve it once a
fix for the rejected commit is on main, or to deploy main as it stands. Under
option 1, once the gate holds the deploy bead, the revert also records a
ready-notice for the mechanik on it (`deferred-dispatch.sh notify`). No
deferred-dispatch pass would send that notice. The order runs per rig, against
each rig's own store (`orders/deferred-dispatch.toml`), and the deploy bead is
in the city's store, because the check is a city-scope order
(`orderExecEnvWithError`, cmd/gc/order_store.go, points `BEADS_DIR` at the
city root's `.beads`). So the check's first pass that finds the bead ready runs
the same `notify`, which mails the mechanik at once and clears the record. The
resolution reaches the mechanik within one cooldown, and its next run deploys
main's head. Under option 2 the bead the revert files is the only deploy bead,
it has no assignee, and the order closes it with its next deploy. Under
option 3 nothing deploys on its own, so the revert files no hold.

**By hand.** If the bad revision broke the deploy command, the revert is done
by hand, and the hold still comes first: file the deploy bead if none is open,
as the revert does, the same gate on it with `human-gate.sh`, and under
option 1 the same notice. Then `git revert` the deploy commit in the town repo,
run `gc import install` and `gc reload --soft`, push the town commit, and run
`gc service restart helm`. With the gate filed before the pin moves, the next
pass of the check, or of the order under option 2, finds the hold.

The fix itself then lands on gc-toolkit's main, and the first deploy after the
gate's resolution carries it. A revision that fails to load never deploys,
because step 7 restores the old pin before anything commits.

### Where this departs from upstream

- **No release.** Upstream's own packs move by a gc upgrade (core, bd) or by a
  registry release that `gc import upgrade` takes (fact 11). Here the pin names
  a commit on main, because a release per landing would be a version scheme
  with no meaning and a publish step with no reader.
- **The pin moves after each landing, not at release time.** Upstream bumps a
  pin when a person upgrades. Here a check asks for a deploy once main moves,
  because the pack is developed in the same city it runs in, and its fixes are
  for that city.
- **The city stops running upstream's contributor flow.** Upstream's
  contributors point `source` at a local clone (fact 11), which is what the
  city does today. That flow needs a person to keep the clone current, and the
  reconciler was the pack's stand-in for that person.
- **A deploy accepts the drift it causes.** Upstream leaves changed start-up
  config to its reconciler, which restarts a drifted named session in place
  whatever work it holds (fact 8). Every deploy here drifts every pack
  session, because each pin is a new cache directory, so the command follows
  each install with `gc reload --soft`, and the patrols take the new revision
  through pack drift at the end of a turn. Once Gas City holds a named
  session's drift restart for the work it holds, the soft reload can go, and
  Gas City's own handling restarts each session.

## 3. Which imports stay, and how the cutover goes

All of them stay, rewritten as in section 1.

- **The city-level import** is the only source of pack commands (fact 9). Every
  formula step, prompt and skill reaches the pack's scripts through
  `gc gc-toolkit scripts-dir`. It also loads the pack's city agents: deacon,
  mechanik and dog.
- **Each rig's import** is what runs the pack's rig-scoped orders in that rig
  (fact 9). Without it, the merge cadence, deferred dispatch, liveness sweep
  and the others run nowhere for that rig. `expandCityImportedAgentsForRigs`
  would still give the rig the pack's agents, and that is why the agents alone
  are no reason to drop the rig blocks. `[defaults.rig.imports]` seeds new
  rigs and does not replace these blocks.
- **The keeper import** stays on the rig that keeps the Gas City fork. It
  stays on the pack's revision for three reasons. The deploy command writes
  the same commit on it and checks both lock entries (section 2). The cache
  key ignores the subpath, so the sub-pack resolves inside the same clone as
  the pack (fact 3). And every reference the sub-pack makes to its parent
  resolves inside that one checkout: the three fragment symlinks into
  `../../../template-fragments/`, `rebase-check.sh`'s
  `../../../../assets/scripts/run-lib.sh`, the keeper prompt's
  `{{ .ConfigDir }}/../../docs/fork-patching.md`, and its formulas' calls
  through the parent's `scripts-dir`.

**Two revisions of one binding.** They can load at once only through two
source strings. During a cutover one import at a time, that means a remote pin
on some imports and the checkout path on others. If the two held different
commits, a rig would run one revision's formulas from its rig import, while
every step's `gc gc-toolkit scripts-dir` call ran the other revision's scripts
from the city import. Prompt fragments render from both directories, and the
rig's directory wins a name defined in both (`PackDirsForRig`,
internal/config/config.go). A formula and the script it calls can no longer
be assumed to come from one commit. The cutover avoids that state. It starts
after the effort's merge commit `M` is live in the checkout, and the retired
reconciler no longer moves the checkout. Every pin then names the commit the
checkout holds, `C`, so the two directories hold the same files while the
cutover runs. `C` is `M`, or a later main when another landing came before the
reconciler's last pass. Section 7 gives the order.

## 4. What else reads the rig checkout as the deployed pack

| Reader | What it reads | Home under the pin |
|---|---|---|
| The helm service | `bash rigs/gc-toolkit/assets/scripts/gc-helm-svc.sh`, a path relative to the city root. `gc-helm-svc.sh` takes only its own directory, for `GC_HELM_OPEN_TOOL` (`:60-62`). | **The deployed revision.** The town's service command becomes `["sh", "-c", "exec bash \"$(gc gc-toolkit scripts-dir)/gc-helm-svc.sh\""]`, resolved once per service start. The deploy command restarts the service. The service stays in city.toml, because a rig-imported pack may not declare one (fact 9). |
| `gc-build.sh` building helm and gctk | `services/<component>` under the pack's own directory (`:117-118`), and `HEAD:./` of that subtree (`:234`). | **The deployed revision**, unchanged: it builds what is deployed. `go build` writes only into the state root (`:599-603`). The trial confirms the clone stays clean after both builds. |
| `gc-build.sh`'s `behind_main` | A fetch of origin into the pack's own repository every 30 minutes (`:293`), counted against HEAD (`:298`). The helm board bands its PACK rows on it. | **Retirement.** Under the pin, it would fetch into a clone that Gas City shares across cities and validates on every load. Its premise is gone too: a checkout parked off main cannot happen when the served code is always exactly the pin. Deploy lag shows as the open deploy bead. `FETCH_TTL`, the `origin-fetch-at` marker, the record's `behind_main` field and helm's `BehindMain` band retire with it. |
| I9's LAGGED and UNFETCHED (`doctor/check-pour-text-current`) | Each rig checkout's lag behind its origin ref, and that ref's fetch time, against the reconciler's 15-minute cadence. | **Retirement.** They measure whether the reconciler is keeping up, and nothing advances a checkout any more. |
| I9's STALE-TEXT | The formula a running molecule was poured from (`gc.formula_source`), dated by `git log` in the checkout that owns the path (`:314`). | **The cached revision.** A source under a cache clone never changes in place, so staleness becomes "the deployed revision's copy differs from the poured one". The check compares the poured file with the same path under its own `GC_PACK_DIR`. The checkout arm stays for a city that imports by path. |
| The overlays' hooks | The gh-origin-guard PreToolUse command in all three overlays, `patrol-continue.sh`'s ledger (`:118-120`), `work-context.sh`'s `run-lib.sh` (`:97-99`) and `cycle-recycle.sh`'s `scratch-reap.sh` (`:268-270`). Each takes its script from the first of `$GC_RIG_ROOT` and `$GC_CITY_PATH/rigs/gc-toolkit` that holds it, and the guard exits 0 when neither does. `work-context.sh` tries `$GC_RUN_LIB` and `$GC_PACK_DIR` first, and nothing sets either one for a session. | **The revision the session started from.** `worktree-setup.sh`, which runs as `pre_start` with its path under `{{.ConfigDir}}`, records its own scripts directory in the work dir, with the commit checked out there (`git rev-parse HEAD`). The hooks read that record. deacon, mechanik and dog do not run `worktree-setup.sh`, so each gains a `pre_start` step that writes the same record. `gh-origin-guard-codex.sh` copies the overlay's guard command into the Codex home, so the Codex agents take the change with it. A session with no record, such as one started before unit 1 went live, asks `gc gc-toolkit scripts-dir` instead. A per-hook `gc gc-toolkit scripts-dir` would be a Gas City query on every Bash call, which the operator ruled out: "Any query to gas city is expensive if done often, so it needs to be a push change vs a pull to check if anything changed" (converse sitting tk-vu6faf2, 2026-11-05, recorded in observation tk-dbsf5cu). |
| `cycle-recycle.sh`'s pack drift | The mtimes of the role's prompt, patrol formula and fragments in the checkout, against the session's first prompt (`:95-111`). | **The pack's entry in the lock.** The session's record (the row above) holds the commit the session started from, because the cache directory's name is a hash and does not give the commit back. A check `stat`s the city's `packs.lock`. Only when the file is newer than the session's first prompt, the time today's check compares against, does it read the pack's `[packs."<source>"]` entry and compare that `commit` with the recorded one. Drift is a different commit. The mtime alone proves nothing, because every install rewrites the file and a re-pin of core or bd changes it too (fact 2). A check stays one `stat`, plus a read of the local file once it has been written since the session started, with no query. Under a path import, the recorded directory's mtimes keep today's check. |
| The demo engine's own-source rule | `_demo_engine_rig_of` treats the rig whose repository holds the pack's directory as one whose app reads the city (`:404-412`). | **No code change.** The clone belongs to no rig, so the rule finds nothing. The town already sets `app_reads_city = "true"` on the gc-toolkit rig. install.md's line that the rig the pack is imported from "needs no setting" changes to say a URL import needs the setting. |

**Git history in the cache.** The clone is a full clone (fact 3), so a script
may read its history with commands that write nothing, such as `git log`,
`git show`, `git rev-parse`, and `git diff` between two commits. A script must
not fetch into the clone, check out, run `git status` (which can rewrite the
index), or write a file there. Gas City shares the clone among the host's
cities and checks its HEAD and its clean tree on every load (fact 4).

**Writes into the pack's own directory.** The census at `6dfa90898` found no
runtime write into the pack's working tree through `$PACK_DIR`,
`$GC_PACK_DIR`, `{{.ConfigDir}}` or a script's own location. The one write
into its git directory is `behind_main`'s fetch, which retires. Other writes
reach the pack's directory today only because it is the gc-toolkit rig's
checkout: bd's store under `.beads`, agent homes, worktrees and fetches. They
keep landing in that checkout, which stops being the pack.
`render-seed-audit.sh` writes `generated/` in a developer's checkout, which is
a developer tool. A file written into the clone that git does not ignore would
stop every gc command until `gc import install` cleaned it (fact 4). The trial
asserts the clone stays clean.

## 5. Every rig's checkout

Once the pack loads from the cache, nothing advances any rig checkout's
working tree. The table lists what still reads a checkout and what each reader
needs.

| Reader | Needs | Change |
|---|---|---|
| Agent homes, `worktree-setup.sh --sync` at session start | Origin refs. It fetches, then fast-forwards the linked home worktree and never the checkout (`:158`, `:163`, `:273`). | None. |
| Per-bead worktrees, workspace-setup in `mol-polecat-work` | Origin refs. It fetches, then cuts the worktree from `origin/<base>`. | None. |
| The refinery's prep worktree, merges and lifecycle fetches | Origin refs. | None. |
| Review workspaces and `review-checks.sh` | Origin refs and fetched commits. | None. |
| The feedback distiller and `learning-recurrence.sh` | `origin/main`, by `--ref`. | None. |
| bd stores under each rig's `.beads/`, and their readers | Runtime state kept in the rig's directory, whatever commit the checkout is at. | None. |
| `worktree-setup.sh`'s read of `.agents/skills/.gc-skill-ownership.json` | A file gc writes. | None. |
| The refinery's busy check (`cycle-recycle.sh` `_git_busy`, `check-recycle-capable`) | The checkout's git state, such as a rebase in progress. | None. |
| `refinery-reconcile.sh`'s `RIG_HEAD` (`:59`), named in a dropped-tail finding as "the base its anchors would have landed on" | Main's head, read from the checkout's HEAD. | The tree lags after the retirement. The file is tk-1tfzr71.20's to retire, so the problem is recorded in that bead's notes instead of fixed here. |
| The demo engine (`demo_engine_find`, `:160-202`) | Its own rig's checkout tree: `package.json`, the engine's CLI, `npm install` and browser provisioning. | **Needs the tree current.** It moves to a worktree of that rig cut at the fetched `origin/<default>`, kept current the way agent homes are. |
| The overlays' hooks and pack drift | The pack, from the gc-toolkit checkout. | Section 4. |
| The refinery's `auto_ff_rig_main` step (`mol-refinery-patrol.toml:88-90`, `:1011-1014`) | It **writes** the checkout: after a direct merge, the refinery agent fast-forwards the rig's checkout. | **Retires** with the reconciler, since it is a pass that edits a rig checkout. |
| The keeper's post-rebase step (`refinery-rebase-handling.template.md:135-196`) | It **writes** the fork rig's checkout, resetting it to the rebased main after a force-push, because "the operator builds from and references that checkout". | **Stays.** It runs once per rebase landing as that procedure's repair of a force-push, not as a pass. After ordinary merges, that checkout advances only when you pull it. |

**Who fetches.** No pass fetches on a schedule. Each reader that needs origin
refs fetches them itself before it reads. Worktrees share their repository's
refs, so any fetch from a home, a per-bead worktree or the refinery refreshes
the rig's `origin/*`. The checkout itself stays a plain clone, at whatever
commit it held when the reconciler stopped. An agent that wants current
content reads `origin/<default>` or its own worktree.

## 6. What retires, and what changes with it

**Files.** `assets/scripts/reconcile-rig-checkouts.sh` (906 lines), its test
(1,787) and `orders/reconcile-rig-checkouts.toml` (11) are
tools/deletion-plan.tsv's rows for this effort and docs/built-once-target.md's
stage B row, 2,704 lines. The change that deletes them removes those rows, as
the page's rule asks. `behind_main` and its knobs and tests also retire from
`gc-build.sh`, `gc-build.test.sh`, `gc-helm-svc.test.sh`,
`services/helm/internal/source/packhealth.go` and the board's banding, along
with I9's LAGGED and UNFETCHED arms and their tests. So does the refinery
formula's `auto_ff_rig_main` var and its step.

**Registry.** `reconcile_rig` leaves `[metadata.patrol_bookkeeping]` in
lifecycle/lifecycle.toml (`:1845`), and the comment at `:1851-1852` goes with
it. The comment says the script "enumerates the mayor's beads". The approved
native-hold design leaves it for this bead to remove. The closed subject beads
keep the key as history.

**Docs.** These name the reconciler or a checkout as the deployed pack, and
each states the pinned import once the units land: architecture.md
(`:170-172`), authority-map.md (`:15`, `:51`, the "Powers over the live rig
checkouts" section at `:83-93`), component-model.md (`:217`, `:443`, `:465`,
`:574-577`), cycle-recycle.md (`:92-94`, `:105-107`), install.md (`:58-104`,
`:120`, `:165`, `:193`, `:224`, `:326-327`), pack-authoring.md (`:176-205`),
refinery-merge-cadence.md (`:901-933`), design-convoy.md (`:97-98`),
fork-patching.md (`:370-372`), gascity/packs.md (`:220-231`),
review-correctness.md (`:222`), gh-origin-guard.md (`:346-347`),
services/helm/README.md (`:1047-1060`, the `behind_main` row and
`:1203-1216`), the headers of `gc-helm-svc.sh` (`:5-7`, `:53-54`) and
`converse-capability.sh` (`:8-11`), and the mtime comment in `cycle-recycle.sh`
(`:84-86`).

**The reconciler's escalations.** It files one kind. For a rig it cannot
advance or heal, it files a subject bead in the gc-toolkit store. The subject is
a task with metadata `reconcile_rig=<rig>`, titled "Reconcile: rigs/<rig>
cannot fast-forward to <remote>" or "Reconcile: rigs/<rig> holds a kept file
it could not put back". `human-gate.sh` then files a gate on that bead under
the key `reconcile-diverged-<rig>`, with a 24-hour quiet window. A clean pass
retracts the gate as moot and closes the subject. None was open on 2026-11-06
(fact 14). The deleting unit counts them again when it runs. For any open
subject, it salvages what the subject's body lists, including a copy under
`.git/gc-toolkit-reconcile-kept`. Then it retracts the gate with
`human-gate.sh --retract --subject <bead> --key reconcile-diverged-<rig>
--message "<the reconciler is retired; the checkout is no longer the deployed
pack>"`, and closes the subject with that reason. The 884 set-aside refs stay
in the checkouts. They are the only copy of what they hold, so deleting them is
your call, outside this effort.

**The beads that wait on this effort.** Each has a `blocks` edge onto
tk-1tfzr71.14.

- tk-9hs7mxv and tk-kcq4246 are found problems in the reconciler. Each is
  armed to `mol-validate-close`, so when tk-1tfzr71.14 closes, the validating
  closer checks each one against the landed retirement, which deletes the code
  each describes. Nothing else is owed. The deleting unit's commit names both.
- tk-1tfzr71.13 is lane B's next member, armed to sling once tk-1tfzr71.14
  closes. It proceeds unchanged, and its own landing goes live by a deploy.
- tk-1tfzr71.25 waits on every member. This effort retires its own registry
  entry, so the sweep inherits nothing from it.

## 7. Proof, cutover and revert

### The trial

The trial is a hermetic suite that unit 5 adds. It extends the git-import
scratch city in `pack-self-location.test.sh`, so it runs at every self-review
and in CI rather than once. The scratch city imports the branch's own commit
from a `file://` repository built from the tree. It has a city import, two rigs
with rig imports, one of them with the keeper import, and the core import. It
asserts these things:

1. `gc gc-toolkit scripts-dir` prints a directory inside the clone.
2. In `gc config show --json`, every pack agent's `pre_start` and overlay
   directory render inside the clone.
3. The keeper's agents load from `<clone>/packs/gascity-keeper`, and their
   parent references resolve inside the same clone.
4. Each rig gets its own instance of every rig-scoped order (`gc order list`).
5. An exec order runs from `$PACK_DIR` (`gc order run`) on an arm that needs no
   store, such as the deploy check finding the pin current.
6. Running `gc-build.sh helm` and `gc-build.sh gctk` from the clone leaves
   `git status --porcelain` empty there.
7. Installing a second commit moves every rendered path to the second clone,
   and pinning back to the first resolves with no fetch.
8. A file written into the clone makes `gc config show` fail with "local
   worktree changes", which is the contract section 4 relies on.
9. The deploy command, run against the scratch city, rewrites every pin and
   follows each install with a soft reload. The suite runs no controller, so
   its runs answer `gc reload` with a stub that records each call and can be
   made to refuse. What a controller does with the request is the canary's to
   watch (the cutover's step 7). On a forced verification failure, on a
   refused soft reload, and on a commit its signing program refuses, the
   command restores the previous pin, runs the soft reload again and leaves
   the town's HEAD where it was. When the town's origin, a bare repository in
   scratch, refuses the push, the new pin stays live and committed, the service
   restart still runs, and the exit names the unpushed commit. When the service
   restart is made to fail, the new pin stays live and pushed, and the exit
   names the service. In both cases the printed `--to` command, run once the
   cause is gone, finishes the deploy and moves no pin.
10. A revert holds automatic deploys, by either route. After the command
    deploys a second commit over the first and `--revert` puts the first back,
    a pass of the deploy check with main still at the second commit nudges no
    one and leaves the held bead out of `bd ready`. A run with no `--to`
    refuses, and so does a second `--revert`. The same holds after the by-hand
    route. Once the gate is resolved, the check's next pass sends the
    recorded notice, and the next run deploys main's head. These runs may file
    their bead and gate in a stub store, as long as the command, the check and
    their reads of the hold are the pack's own.

### The cutover

The mechanik runs the cutover on a town bead (unit 6), each step as one town
commit. It follows each step's `gc import install` with `gc reload --soft`, as
a deploy does (section 2), because moving an import from the checkout to the
clone changes the start-up config of every agent that import loads, its own
included:

1. **Precondition.** The effort's merge commit `M` is live:
   `git -C rigs/gc-toolkit merge-base --is-ancestor M HEAD` succeeds, and
   `gc order list` no longer shows reconcile-rig-checkouts. The reconciler's
   last pass is the one that moves the checkout to `M`, or to a later main when
   another landing came first. The commit the checkout then holds,
   `git -C rigs/gc-toolkit rev-parse HEAD`, is `C`, and every step pins `C`.
   Pinning `M` when the checkout holds a later commit would take the landings
   after `M` back out of the city. If that pass cannot fast-forward, it files
   its gate as usual, and resolving that gate comes first.
2. **The city import.** Rewrite `[imports.gc-toolkit]` as in section 1,
   pinned to `C`. Run `gc import install`, then confirm that
   `gc gc-toolkit scripts-dir` prints the clone and `gc config show --validate`
   is clean.
3. **The gc-toolkit rig's own import.** It goes first among the rigs, because
   its agents build the pack. Rewrite it, install, and confirm in
   `gc config show --json` that its agents' `pre_start` names the clone and
   that its rig orders are listed.
4. **The other rigs' imports,** one at a time with the same checks.
5. **The keeper import,** with the same checks for the keeper's agents.
6. **The helm service command** (section 4), then `gc service restart helm`,
   then a board read.
7. **The first deploy.** When main moves past `C`, the deploy check files its
   bead and the mechanik deploys. Watch which sessions restart and when. The
   mechanik's run should finish in the session that started it, no working
   session should restart, and the witness, the deacon and the refinery should
   each recycle at the end of a turn. The watching is the canary for section
   2's soft reload.

### Revert

Before step 6, any step reverts with `git revert` of its town commit,
`gc import install` and `gc reload --soft`. After step 6, the revert also
restarts the helm service.
Reverting every step returns the city to a path import of the checkout at `C`.
Nothing advances that checkout, so a landing after `C` goes live only if
someone runs `git -C rigs/gc-toolkit merge --ff-only origin/main` by hand.
That is the stopgap while a failed cutover is fixed.

## 8. The units

The pack half lands on integration/tk-1tfzr71.14. The implementation child,
tk-1tfzr71.48, files the units below and builds none. Units 1 to 5 each have
`target=integration/tk-1tfzr71.14` in their create. tk-1tfzr71.14 and the
summary task, tk-1tfzr71.49, wait on each of them with a `blocks` edge, and
each unit waits on the one before it. The child slings unit 1 on
`mol-polecat-work`, and units 2 to 5 are armed to the polecat pool on it.
Running them in order keeps their shared docs from conflicting.

| Unit | What it changes | Who | Waits on |
|---|---|---|---|
| 1. A session finds the pack it started from | `worktree-setup.sh` records its scripts directory, and the commit checked out there, in the work dir. deacon, mechanik and dog gain a `pre_start` step that does the same. The three overlays' hook commands, `patrol-continue.sh`, `work-context.sh` and `cycle-recycle.sh` read the record in place of `$GC_RIG_ROOT` and `rigs/gc-toolkit`. Pack drift compares the recorded commit with the pack's entry in the lock, which it reads only once the lock has been written since the session started. Pack drift is how the patrols take a deploy, since the deploy's soft reload restarts no session (section 2). Its tests show that a moved pin recycles a patrol once, and that an install that changes nothing, and a re-pin of core or bd, recycle nothing. Also cycle-recycle.md, gh-origin-guard.md, and the tests. | polecat | nothing |
| 2. Build and check what is deployed | `gc-build.sh` loses `behind_main`. helm's packhealth loses its band. I9 loses LAGGED and UNFETCHED, and its STALE-TEXT gains the cached-revision arm. Also the helm README, the I9 rows in component-model.md and install.md, and the tests. | polecat | unit 1 |
| 3. Deploy by pin | `gc gc-toolkit deploy`, with the soft reload after each install, each failure's outcome and the run that finishes it, and a revert's hold, the deploy check order and its script, with tests. Also install.md's import and deploy sections, and pack-authoring.md's "A landed pack change is confirmed on the deployed pin". | polecat | unit 2 |
| 4. Retire the healer | Delete the reconciler, its test and its order, with their deletion-plan rows and the stage B schedule row. Retire `auto_ff_rig_main`. Move the demo engine to a worktree of its rig. Remove `reconcile_rig` and its comment from lifecycle.toml. Sweep the docs in section 6. Count the reconciler's open subjects again. | polecat | unit 3 |
| 5. Prove it from the cache | The suite in section 7. | polecat | unit 4 |
| 6. Cut the city over | The town commits in section 7. | mechanik, on a bead assigned to `gc-toolkit.mechanik` | tk-1tfzr71.14, which closes when the effort's PR merges. A ready-notice is armed to the mechanik. |

Unit 6 is a town bead. It is not on the integration branch, and the landing
bead does not wait on it. tk-1tfzr71.14's "Done" holds once unit 6 finishes.
Until then, the merge commit is live in a checkout that nothing advances.

Under option 2, unit 3's order runs the command itself and reads a revert's
hold before each run, and unit 3 adds the order to authority-map.md's
town-repo row. Under option 3, unit 3 ships only the command, whose revert
then files no hold, and unit 6's step 7 becomes your first deploy.

## Gas City search

Units 1 and 3 add operational surface: the deploy command, the deploy check
order and its script, the `deploy` label on one bead, the `deploy-held` key of
the gate a revert files, the recorded scripts directory and commit in a
session's work dir, and a `pre_start` step on deacon, mechanik and dog. Units 2
and 4 remove surface. Upstream is gastownhall/gascity at `8e75c50aa845`.

- **Moving a pin.** Searched: `gc import install`, `gc import upgrade`,
  `gc import add --version`, `gc pack fetch`, and registry releases with
  `gc pack registry publish` (cli.md). Install resolves, locks and fetches, and
  the command composes it. `gc pack fetch` fetches only the legacy `[packs]`
  table, which schema-2 config replaces with `[imports]` (`doPackFetch`,
  cmd/gc/cmd_pack.go, reads `cfg.Packs`). Upgrade moves only within a
  constraint, and a `sha:` pin has no range (fact 5). A semver constraint would
  need tags this repository does not publish (section 1). A registry release is
  a publish step per deploy. The gap is rewriting every import of one
  repository to one commit, restoring the old pin when verification or the
  commit fails, since install does not roll back (fact 5), and saying which
  pin runs when a later step fails.
- **Knowing main has moved past the pin.** Searched: `gc import check` and
  `gc import status`. Check reports missing, stale or uncached state against
  the authored imports, and status reports the declared pins. Neither compares
  a pin with its source's branch, and upstream has no outdated report. Also
  searched the `[[webhook]]` receiver with `trigger = "webhook"` orders, which
  could push a GitHub push event, but it needs a public endpoint this city does
  not run. The check is therefore an exec order on Gas City's cooldown trigger,
  whose script does one `git ls-remote`.
- **Telling the mechanik.** Searched: assignment, `gc hook`, `gc session nudge`
  and bd labels. They cover it. The bead is assigned to the mechanik, found
  again by its label and assignee, and announced by a nudge when filed. After
  a revert's hold, it is announced by the pack's ready-notice
  (`deferred-dispatch.sh notify`, which composes `gc mail send --notify` and
  `gc session nudge`), and the check sends it, because the order that sends
  recorded notices reads only rig stores (section 2). No new metadata key is
  needed.
- **Holding deploys after a revert.** Searched: `gc import` and `gc order`
  (cli.md). None of their subcommands holds a pin or pauses an order. Also
  searched the canonical dispatch hold labels, `hold:mayor` and
  `hold:external` (`DispatchHoldLabels`, internal/beadmeta/hold_labels.go),
  and bd's human gate, `bd gate create --type=human --blocks <bead>`
  (`gateCreateCmd`, cmd/bd/gate.go at steveyegge/beads v1.3.2). A hold label
  names the next actor or an outside condition, and carries no question or
  answer. The human gate fits, because a person decides when deploys resume,
  its message carries the rejected commit, and `bd gate resolve` records the
  answer. A bead the gate blocks leaves `bd ready` (cmd/bd/ready.go) and the
  hook's offer (`filterUnreadyHookCandidates`, cmd/gc/cmd_hook.go), so the
  hold composes the gate through `human-gate.sh`. The new surface is the
  gate's key, `deploy-held`, and the read of that gate that the command, and
  under option 2 the order, makes before deploying main's head.
- **A session finding its pack.** Searched: `GC_PACK_DIR`, which is set for
  pack commands, orders and doctor checks but not for sessions (fact 10);
  agent `[env]`, which is not template-expanded; and overlays, which are copied
  with no template pass (fact 7). `gc gc-toolkit scripts-dir` answers, but
  calling it from a hook is the per-hook query the operator ruled out
  (section 4). `pre_start` is the one place Gas City renders `{{.ConfigDir}}`
  and runs a command at a session's start, so the record is written there.
- **A running session learning that a deploy happened.** Searched: the
  config-drift handling and `gc reload --soft` (fact 8). Drift restarts a
  named session from outside it, whatever it is doing, so the deploy accepts
  the drift with the soft reload, and a patrol learns of the deploy from pack
  drift instead, which recycles it at the end of a turn, its own safe point.
  Its signal under the pin is the pack's entry in `packs.lock`, which is Gas
  City's record of the deployed revision. A `stat` tells whether the file was
  written since the session started, and only then is the entry read and its
  commit compared with the session's, because every install rewrites the file
  (fact 2). The canary in section 7 watches that no working session restarts
  and that each patrol recycles at the end of a turn. Once Gas City holds a
  named session's drift restart for the work it holds, its own handling can
  replace the soft reload and pack drift, and unit 6 appends what the canary
  shows to tk-1tfzr71.18, the member that re-derives the pack's
  session-lifecycle machinery against the controller's.
