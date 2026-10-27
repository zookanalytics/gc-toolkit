---
name: Gas City search for the seed audit's re-audit and its render modes
description: The search the arch check asks for before the pack adds seed-audit-reaudit.sh, the seed_audit_reaudit key, the --since and --base-stale-out modes of render-seed-audit.sh, and the merge gate's hand-off to the writer. What Gas City, bd and the packs Gas City publishes ship for filing one piece of work per key and dispatching it, for a scheduled or event-driven check, for pinning or fingerprinting the text the gc binary bundles, and for rendering and committing generated prompts, read at named upstream commits, and why the change composes what they ship instead. Read it when checking whether the re-audit or the render modes can move onto a Gas City primitive.
---

# Gas City search for the seed audit's re-audit and its render modes

`generated/seed-audit` commits the text every agent and formula of the pack
renders to. Part of that text ships inside the `gc` binary, in the packs it
bundles, so a newer build moves those pages on every branch at once with no
commit behind it. The operator ruled that such text lands through one re-audit
pull request of its own. This change builds that rule with four pieces of pack
surface:

- `assets/scripts/seed-audit-reaudit.sh` files and slings the re-audit: one bead
  per base branch, on `mol-polecat-work`, so the new text lands as a reviewed
  pull request.
- The `seed_audit_reaudit` metadata key, registered in
  `lifecycle/lifecycle.toml`, names the base a re-audit bead re-renders. The
  writer's dedup reads it.
- `render-seed-audit.sh` gains two modes. `--since <rev>`, which the pre-commit
  hook runs, keeps a commit to the renders its branch moves. `--base-stale-out
  <file>` names the files the base is already stale in when `--check-merge`
  renders a merge.
- `gctk merge` passes `--base-stale-out` to the merge gate's render and hands
  the files it names to the writer.

So the arch check asks what Gas City already ships for each of them
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships no primitive that covers any of the four. Orders come closest to
the writer, and for this work they cover neither its trigger, nor its dedup, nor
its dispatch. `GC_FORMULA_REF` reads formulas as of a commit, which is half of
the render `--since` runs at the fork point. The change does not compose it,
because no page documents it and it would replace no step. The writer composes
what Gas City and bd do ship for its parts: bd's metadata filter for the dedup
read, and `gc sling --on` for the pour and its per-bead guard. Gas City's own
GitHub PR monitor files its repair beads the same way, inside the binary. The
built-in packs' pins, which the bead first suggested pinning the render to,
keep that text tied to the running binary, so a pin cannot keep it out of a
commit.

## The need

- When a render finds the default branch's committed audit stale in files that
  no change in the repository moved, one bead re-renders that branch and lands
  the new text in a pull request of its own. The work is the pack's ordinary
  work: a bead on `mol-polecat-work` that a polecat builds and the refinery
  lands after review.
- A base has at most one live re-audit. A second finding of the same drift files
  nothing. That holds for a re-audit someone holds, routes or parks, and for one
  armed to re-sling after a person's ruling. A dedup read that does not answer
  files nothing.
- The finding comes from the render the merge gate already runs when it judges a
  landing, and the merge never waits on the re-audit.
- A commit carries only the renders its own branch moves. A page whose text
  moved with the `gc` binary stays as the branch's fork point commits it, so
  that text arrives through the re-audit and not as a passenger in an unrelated
  change.
- The merge gate's render names the files the base is already stale in, for the
  caller that acts on them.

## Where the search looked

Each source was read on 2026-10-27:

- Gas City (`gastownhall/gascity`) at main `f11f48825520`. That covered its
  documentation, the engineering docs under `engdocs/`, the bundled `core` pack
  under `internal/bootstrap/packs/core`, and the source of orders, sling, mail,
  molecule attach, the built-in pack registry and its pins, `gc prime`, formula
  sources, and the GitHub PR monitor. The live pages at docs.gascity.com cited
  below carry the passages quoted here.
- bd (`gastownhall/beads`) at main `5011528b3ad5`: `create`, `list`, the
  duplicate commands and `hooks`.
- The packs Gas City publishes (`gastownhall/gascity-packs`) at main
  `dac12a4a802c`, and at `66c672b5ed00`, the commit Gas City's `go.mod` at
  `f11f48825520` bundles. The sweep covered every pack directory, and the
  repository's `tests/` and `scripts/`, for keyed filing and dispatch, rendered
  prompts and generated files, git hooks, and a merge step that files a finding
  about its base.
- The cost of a render was measured on the city's host, at the branch head
  `cb979bee`, with the installed `gc`.

## What Gas City ships near the need

### Orders

An order pairs a trigger with an action. The controller evaluates every trigger
that is not manual on each pass of its orders lane, "about once per patrol
interval" (`engdocs/architecture/orders.md`), and the patrol interval defaults
to 30 seconds (`patrol_interval` in
[DaemonConfig](https://docs.gascity.com/reference/config#daemonconfig)). Three
parts of an order overlap the writer.

- **The trigger.** A `condition` order runs its `check` command on each pass and
  is due whenever the check exits 0
  ([Trigger types](https://docs.gascity.com/tutorials/07-orders#trigger-types);
  `checkCondition` in package `orders`). Here the fact that would make it due is
  that the default branch's audit is stale in files no change moved, and the
  only way to learn that is to render the branch. Three runs of
  `render-seed-audit.sh --check` at the branch head each took about 1.9 s of wall
  time and 14 s of CPU (4.0 s user, 10.0 s system) on the city's 18-core host,
  at a load of 6 to 7. A check that renders on every pass at the default
  interval would spend about 11 CPU-hours a day. The merge gate learns the same
  fact for nothing extra. `--check-merge` renders the merge result at every
  landing, and when a page of it does not render as committed, it renders the
  base as well, which is how it tells the base's own staleness from the merge's.
  The drift needs no faster discovery: a commit made in the meantime keeps gc's
  text out through the `--since` render, and the next landing's gate finds it. A
  `cron` or `cooldown` order would render less often and still repeat the gate's
  work. An `event` order runs its action for each matching event on the bus, and
  the bus delivers at least once. A gate that emitted an event at each landing
  that found the drift would run the action at each of them, and the action
  would still need the writer's dedup.
- **The dedup.** Before dispatching, the orchestrator skips an order that
  already has open work, and skips it too when that store check times out
  ([Duplicate prevention](https://docs.gascity.com/tutorials/07-orders#duplicate-prevention)).
  That open work is the order's own: its tracking beads, labeled
  `order-run:<name>`, and the workflow roots its formula dispatches stamp with
  that label (`orderTrackingSummary` and `openWorkGateShut` in package main). An
  exec order runs "no agent, no LLM, no work beads"
  ([Formula orders vs. exec orders](https://docs.gascity.com/tutorials/07-orders#formula-orders-vs-exec-orders)),
  and its tracking bead closes when the dispatch ends (`dispatchOne` defers
  `closeOrderTrackingBead`). So its open work ends when its script exits, and a
  bead the script files is not part of it. The gate would hold the re-audit only
  if the re-audit were the order's own formula run.
- **The dispatch.** A formula order cooks a wisp of its formula and routes the
  root to the order's pool. On a graph.v2 formula the order records its runtime
  vars, and it "deliberately omits the input-convoy and root-key identity
  metadata that the cook/sling stamps also write" (`stampOrderWispRuntimeVars`
  in package main). `mol-polecat-work` reads its work bead from its input
  convoy, and its `load-context` step stops when the convoy does not track
  exactly one bead, so it cannot be an order's formula. The re-audit has to be
  such a work bead, because that is how a change in this pack reaches the
  refinery and lands through a reviewed pull request. Carrying it as an order's
  own wisp would add a second landing route.

So an order covers none of the three for this work. The merge gate's hand-off
stays the trigger, and the writer keeps its dedup and its dispatch.

### Sling

The writer pours with `gc sling <pool> <bead> --on mol-polecat-work` and proves
the pour by reading `gc.execution_routed_to` back. Sling refuses to launch a
formula on a bead while an earlier run of that formula on it is live, unless it
is forced: [`gc sling`](https://docs.gascity.com/reference/cli#gc-sling) lists
`--force` as what allows "formulas v2 workflow replacement"
(`checkLegacySourceWorkflowConflict` in package `sling`). Its key is the bead
and the formula. It guards the writer's adopt path, which slings a bead that was
filed and never dispatched, against a second pour. It cannot tell two beads
filed for one base apart, so it does not replace the writer's key.

### Filing one piece of work per key

- bd's `create` has no form that finds a live bead before it files one. `--id`
  sets an explicit id, and an id stays taken after its bead closes, while a base
  needs a new re-audit each time gc moves its text. `--external-ref` is stored
  in an indexed column that is not unique (`idx_issues_external_ref` in bd's
  first schema migration).
- bd's `list --metadata-field key=value` filters by a metadata field. The
  writer's dedup read is that filter, through the pack's `bd_list`.
- bd's `duplicates`, `find-duplicates` and `duplicate --of` find or close
  duplicates once they exist, by content, by similarity or by hand. None of them
  stops a second filing.
- `gc mail send --dedup <key>` suppresses a send "while a live message with this
  dedup key is in the same mailbox"
  ([`gc mail send`](https://docs.gascity.com/reference/cli#gc-mail-send);
  `SendDeduped` in package `beadmail`). It keeps one live message, not one live
  piece of work a pool claims. The `core` pack's `escalate.sh` dedupes repeated
  notifications by an incident key kept in a state directory, and sends without
  the dedupe when that state cannot be read. The writer has to fail the other
  way and file nothing when its dedup read does not answer.
- Attaching a sub-workflow under an idempotency key reuses the one already
  attached (`findExistingAttach` in package `molecule`). That keys a workflow
  under a bead, not a bead per base.
- The nearest match is inside the binary. The GitHub PR monitor files one repair
  bead per pull request and head commit. It lists beads by its dedupe metadata,
  refreshes the first one that is not closed, and otherwise creates one carrying
  that metadata and instantiates the configured repair workflow on it
  (`ensureGitHubPRRepairBead` and `defaultAttachGitHubPRRepairWorkflow` in
  package main, run by
  [`gc github pr backfill`](https://docs.gascity.com/reference/cli#gc-github-pr-backfill)
  for a [GitHubPRMonitor](https://docs.gascity.com/reference/config#githubprmonitor)).
  It is wired to that monitor alone, and no command or config files another kind
  of bead through it. Its shape, a metadata key for the identity and a live bead
  that suppresses a second, is the writer's shape. The writer builds it from
  `bd list --metadata-field`, a create that carries its identity, and
  `gc sling --on`.

### The text the binary bundles

The renderer's synthetic city imports Gas City's built-in `core` and `bd` packs
by their bundled sources with no version, so the running binary serves its own
embedded copy. The bead first suggested pinning the render to the pack's commit,
so that an upstream adoption would become its own reviewed commit. Gas City's
pins do not do that.

- Built-in packs compose only through explicit pinned imports. The canonical
  pin "is served offline from the binary's embedded copy", and pins that earlier
  releases wrote keep being served from it, because "they always meant 'the
  built-in pack', not that commit's tree"
  ([Builtin Packs](https://docs.gascity.com/reference/system-packs)). The pin
  names a commit whose bundled trees match the embedded content as of a release:
  a release-candidate gate checks that, and the pin is bumped when a release's
  bundled content changes (the comment on `BundledPackImportVersion` in package
  `config`). A build between releases embeds whatever its tree holds under the
  same pin. So the text served under a canonical pin moves with the binary, and
  that movement is the drift this change handles.
- Pinning a bundled source at any other commit "makes it an ordinary remote
  import" (the same page), whose text stays put. Pinned that way in the
  synthetic city alone, the audit would stop mirroring the text agents receive,
  and gc's moves would go unseen instead of adopted. Pinned that way in a city as
  well, the city would run its built-in packs at a commit other than the one its
  binary embeds. That choice is about how a city runs, outside a pack's audit,
  and the operator's ruling asks for the opposite: adopt the binary's text when
  it moves.
- `gc import status --json` reports declared imports, `packs.lock` pins and the
  lockfile content hash, as "a stable machine-readable document for drift
  checkers" ([`gc import status`](https://docs.gascity.com/reference/cli#gc-import-status)).
  While the pin stands, it has no drift to report when the embedded text moves.
- The binary does fingerprint its embedded content. `SyntheticContentHash` in
  package `builtinpacks` hashes the files and modes of every bundled pack, and
  the bundled cache's marker and cache key carry the result. No page documents
  it, and the Builtin Packs page calls the cached files implementation assets
  owned by `gc`. It also spans every bundled pack (`core`, `bd`, `dolt`,
  `gastown` and `gascity`), so it moves when a pack the audit never renders
  moves, and it cannot say which page moved. The render the merge gate already
  runs answers that question.

### Rendering and committing

- [`gc prime`](https://docs.gascity.com/reference/cli#gc-prime) renders one
  agent's prompt in the city in scope, and the renderer composes it. Its
  `--json` summary carries the content, its size and the prompt budget, and
  nothing about which pack a line came from. It reads prompt templates and
  their fragments from disk (`renderPromptWithMeta` and `loadSharedTemplates`
  in package main), so it cannot render an agent as of an earlier commit.
- Formulas can be read as of a commit. With `GC_FORMULA_REF` set to a ref other
  than `HEAD`, a formula file inside a git repository is read at that ref, and
  one outside any repository, such as a built-in pack's in gc's cache, is read
  from disk (`SourceFromEnv` in package `formula`, which `gc formula show`
  uses). That reproduces the fork point's formula pages with the current
  binary's built-in text, which is half of what `--since` renders at the fork
  point. The change does not compose it, for three reasons. No page in
  Gas City's docs or engineering docs describes the variable. The agent pages
  still need the fork point's tree written out and rendered, and once it is,
  its formula pages render from it in the same pass, so the variable would add
  a second path for half the pages and remove no step. And each tree renders
  through its own copy of the renderer, whose scenario city is part of what
  every page renders to, which a formula ref does not reach.
- Nothing in Gas City tells the binary's text from a pack's. So `--since`
  renders the fork point's tree itself to learn which pages a change moved.
- Gas City installs no git hook for a pack and has no setting for one. When
  `gc pack release` runs git, it sets hooks aside with
  `core.hooksPath=/dev/null`. Its own repository keeps its generated reference
  pages in step with a pre-commit hook
  ([Reference](https://docs.gascity.com/reference)), the practice this pack's
  hook follows, and that hook stays in its repository rather than shipping.
- bd's `hooks install` writes thin shims that run bd's own pre-commit,
  post-merge, pre-push and post-checkout logic for beads integration and chain a
  hook that was already in place. Nothing in it decides which generated files a
  commit carries.

### The merge gate's hand-off

`--base-stale-out` and the hand-off pass a list from the pack's renderer,
through the pack's merge gate, to the pack's writer. Gas City's `core` pack
checks work before it lands through `mol-polecat-base`, whose setup, typecheck,
test, lint and build commands come from the rig's formula vars, and which
`mol-polecat-commit` extends to commit straight to the base branch. Its
`preflight-tests` step has Gas City's own shape for a finding about the base.
When the pre-flights fail on the base branch, the worker searches for a bug
already filed for the symptom, files a "Pre-existing failure" bug with the
symptom key in its title if none exists, and carries on with its own work. That
step is text a worker agent reads, it finds a duplicate by searching titles,
and it does not dispatch the bug it files. The re-audit needs a work bead
dispatched when the merge gate finds the drift, and found again by a field
rather than a title. So the step shows the shape the writer follows, and it
does not cover the need. The published refinery that files a finding about its
base is `gastown`'s, covered below.

### The packs Gas City publishes

No published pack ships a rendered-prompt audit or a git hook. The nearest
thing to keeping a commit's generated files to what its branch moved is
`compound-engineering`'s data-migration reviewer, a review persona that flags
changes in a generated schema dump that came from other branches, measured
against the review base. It is guidance for a reviewing agent about one kind of
file, not a mechanism. Two other needs have partial analogues.

- **Keyed filing and dispatch.** The `github` pack's intake finds a source by a
  metadata key across every status, skips one already dispatched or being
  dispatched, and slings a launch bead with `--force --on <formula>`, judging
  success by the sling's exit and the workflow it prints
  (`create_addressed_source` and `route_addressed_source` in its
  `github_intake_service.py`, at both commits). The `gascity` pack's GitHub
  workflows look a source bead up by four metadata fields, create or update it,
  and say not to route it. `gastown`'s patrols file a warrant only when no open
  warrant names the same target, at main only. The fix dispatches in `discord`
  and in the `github` pack reserve a request in a local file. Each keys its own
  kind of work inside its own pack, as the writer does. None is a primitive
  another pack can call, and none settles a priority before its sling.
- **A merge step that files a finding instead of holding.** `gastown`'s
  refinery patrol (`mol-refinery-patrol`, step `handle-failures`, at both
  commits) asks whether a failure is the branch's or already on the target. For
  one already on the target, it searches open bugs by text, files a
  "Pre-existing failure" bug when none matches, and merges. That is the decision
  the merge gate makes about the base's stale pages, made by an agent with a
  text search, and it dispatches nothing.

### The metadata key

`seed_audit_reaudit` names the base a re-audit re-renders, and it is the
writer's dedup identity. Gas City keys its repair beads with metadata the same
way (`githubPRRepairDedupeMetadata` in package main). The key is neither a bead
kind nor a lifecycle state, so it needs no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2). The re-audit
bead is an ordinary task on `mol-polecat-work`.

## What the change composes

- `bd list --metadata-field seed_audit_reaudit=<base>` over the live statuses,
  for the dedup read, through the pack's `bd_list`.
- A `bd create` that carries the bead's identity in the create, through the
  pack's `bd_create`.
- `gc sling <pool> <bead> --on mol-polecat-work` for the pour and the route,
  backed by sling's per-bead guard and read back through
  `gc.execution_routed_to`.
- The pack's own `queue-priority.sh settle` before the sling, `pool-route.sh`
  for the pool, and the pack's deferred dispatch, whose arm the writer counts as
  a hold. The writer writes no priority itself.
- `gc prime`, in the synthetic city the renderer already builds, for every
  render, including the fork point's.

## What would change the answer

- Gas City ships a way for a pack to file work once per key and dispatch it on a
  formula, such as a command or config form of the PR monitor's repair-bead
  writer. The writer then moves onto it.
- A formula order can pour its formula over a work bead's input convoy, or an
  order's open-work gate can count a bead that its exec files. The re-audit
  could then be an order, and the writer's dedup and dispatch would move into
  it.
- `gc` reports which text of a rendered prompt or formula came from a built-in
  pack, or documents a fingerprint of the built-in content the running binary
  embeds. `--since` could then ask gc which pages a change moved instead of
  rendering the fork point, and the merge gate could compare fingerprints
  instead of renders.
- Every build that embeds different built-in content carries a different pin. A
  pin check could then find gc's drift without a render.
- Gas City documents a way to read formulas, prompt templates and fragments as
  of a commit. `GC_FORMULA_REF` reads formulas that way today, and no page
  describes it. `--since` could then render the fork point through gc without
  writing its tree out.
