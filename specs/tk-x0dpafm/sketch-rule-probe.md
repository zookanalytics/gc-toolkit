---
name: A/B probe of the sketch rule in work-quality-base
description: Read it to check the numbers in tk-x0dpafm's summary, to see whether rule tk-4uw3cg3 moves a design and leaves a deliberate name alone, or to re-run the probe on a later wording.
---

# A/B probe of the sketch rule

The proposal clears Gate 3 on a reading: an entry read while designing supplies a
step the authors skipped. Reading well proves nothing about that, so this measures
what an agent designs with the old text and with the new. The agent has read-only
tools and a repository to look in, because the proposal says the failure was not
looking.

In the first corrected case, no new-text run keeps the sketch's `epic` command or
`<condition>`. In the second, every old-text run builds its check scripts under a name
from the sketch, two of them under `gc:` as the real design did. One new-text run still
does that, and two name the scripts for what they do. The new text keeps a name given on
purpose in both controls.

| Case | What the agent is given | Old text | New text |
|---|---|---|---|
| A, the first correction | An operator's review comment sketching `epic park <bead> <condition?>` | 3 of 3 keep the sketch's positional second argument, 2 of 3 keep the name `<condition>`, and 2 of 3 keep the bare `epic` command | None keeps `epic` or `<condition>`. 2 of 3 use the `--waiting-on` flag the neighbours have, 1 of 3 keeps a positional argument renamed `<blocker>`, and 3 of 3 say where they depart |
| B, the second correction in outline | A passing sketch of `npm run check` or `npm run gc:check` | 3 of 3 build their check scripts under a sketched name, 2 of 3 under `gc:` and 1 of 3 under `check:`. 3 of 3 add the sketched aggregate, which no city command calls | 1 of 3 builds them under `gc:`, and 2 of 3 name them for what they do. None adds the aggregate, and 3 of 3 say where they depart |
| C, control | A name given with a reason, against the neighbours | 3 of 3 keep `gc:reset-db` | 3 of 3 keep it, and say `data:reset` would match the neighbours |
| D, control | A bare rename in a review comment | 3 of 3 apply `--ruling`, 2 of 3 flag another script's flag of that name, and none proposes another name | 3 of 3 apply it, flag that clash and name another option. A run costs about 54% more |

Every run in both arms read or searched the neighbouring files. Old runs looked and
still kept the sketch, so in these cases the failure is what the run does with what
it reads. That differs from the proposal's "a missing step, not a wrong pick". All
three old runs in case B also call the sketched names examples and the result their own
choice, and two of them still take the prefix, so knowing that a sketch is not a
specification is not all the entry adds. The entry is tested whole, so this cannot say
which of its sentences moves a run. These readings are mine.

## Method

Each arm's system prompt held one role line and the whole "Standards for what you
produce" section of `template-fragments/work-quality-base.template.md`, without its
closing template marker. The old arm's copy came from `HEAD~1` of the rule's commit
and the new arm's from that commit. The two differ by exactly the added entry. The
role line:

> You write designs and specs for a software repository. Other agents build from
> what you write, and the operator reviews it and decides from it.

The user message was the same in both arms for a given case. Each run was one call
from the case's fixture directory, with the case on stdin and with every `GC_*` and
`BEADS_*` variable unset:

`claude -p --model claude-opus-5-5 --tools "Read,Glob,Grep" --max-turns 12 --max-budget-usd 0.90 --setting-sources "" --strict-mcp-config --disable-slash-commands --no-session-persistence --output-format stream-json --verbose --system-prompt "<arm>"`

Each arm ran three times on each of the four cases. That is 24 calls, for $5.79 in
all. I read every output, and I took the counts from that reading.

**Fixture for A and D.** `assets/scripts/` at a948aeb48, main about four hours
before the operator's review comment, without its test files, and
`specs/tk-rl8gz4b.2/steer-by-epic.md` at e4851071f, the version the operator
reviewed. That spec already calls its verbs `epic-steer.sh`.

**Fixture for B and C.** A web app written for this probe, `rig-a-web`, so that no
private repository feeds a public record. Its `package.json` has the scripts `start`,
`build`, `lint`, `typecheck`, `test`, `data:migrate` and `data:seed`. A README and a
CI workflow run all of them but `data:seed`, and a `knexfile.js` names the database. Its
`city-rig.toml` holds the commands Gas City runs:

```toml
[rigs.formula_vars]
setup_command = 'npm ci && npm run data:migrate'
typecheck_command = 'npx tsc --noEmit'
lint_command = 'npx biome lint . --error-on-warnings'
build_command = 'npx webpack --mode production'
test_command = 'npx jest --ci'
affected_tests_command = 'npx jest --ci --changedSince=origin/main'
```

**Case A** is the operator's review thread on PR #1220, on that spec's line 177. Its
words are the real comment. The rework that answered it wrote
`epic-steer.sh park <bead> <condition>`, and the operator's answer in visit tk-vijqp9x
opens this rule's evidence. Observation tk-hmorsoz records the signature that replaced
it: `gc-helm.sh park <bead-id> "<text>" [--body "<detail>"]` and `--waiting-on <bead-id>`.

> You are reworking a design spec after the operator's review. The repository is the
> current directory, and the spec is specs/tk-rl8gz4b.2/steer-by-epic.md.
>
> One review thread, by the operator, sits on the spec's line 177, the paragraph that
> opens "**The moves.**":
>
> > I'm not sure we should have special logic at all for a park and unpark of an epic.
> > It's just when an Epic has a blocker added to it. We might choose to formalize it
> > with a singular command, just because the
> > epic park <bead> <condition?>
> > reads cleaner and is semantically more clear.
>
> Answer this thread in the spec. Write the replacement text for the park and unpark
> moves, with the exact command line the operator would run.

**Case B** is written for this probe from the outline in the bead's description: the
operator sketched two possible forms of a script name in passing, one carrying a `gc:`
prefix, and a design put the prefix on every check script it defined. The name `check`
comes from that outline.

> You are filing the design for a change. The repository is the current directory, and
> city-rig.toml is the block of the city's config that Gas City reads for this
> repository.
>
> The operator said in a session:
>
> > Give the city package scripts to run for this repo's checks, something like npm run
> > check or npm run gc:check.
>
> Write the design: the exact scripts to add or change in package.json, and what each
> command in city-rig.toml becomes.

**Case C** is written for this probe, as a control. The name is deliberate and goes
against the neighbours, whose prefix names a domain.

> You are filing the design for a change. The repository is the current directory, and
> city-rig.toml is the block of the city's config that Gas City reads for this
> repository.
>
> The operator said in a session:
>
> > Add a script the city calls to wipe and re-seed its own test database between
> > worker runs. Name it gc:reset-db. Only Gas City should ever run it, and nobody
> > should run it by hand, so I want the prefix to say that.
>
> Write the design: the exact script to add to package.json, and how the city calls it.

**Case D** is written for this probe, as a control with no stated reason. The rename
is an instruction, and the name it gives already means something else in
`assets/scripts/converse-signoff.sh`. The sentence sits on the spec's lines 196 and 197.
The case's line number is two off, and every run found the sentence by its text.

> You are reworking a design spec after the operator's review. The repository is the
> current directory, and the spec is specs/tk-rl8gz4b.2/steer-by-epic.md.
>
> One review thread, by the operator, sits on the spec's line 198, the sentence that
> says "Given `--evidence <visit>`, it also records `epic_steer_evidence` (section 6)":
>
> > Rename --evidence to --ruling.
>
> Answer this thread in the spec. Write the replacement text for that sentence.

## Results

### Case A: the placeholder in a review comment

The old runs reproduce the failure the operator corrected: a positional condition,
taken from the comment, in every run. All three new runs list where they depart from the
sketch. Two reach the `--waiting-on` half of the signature that
replaced it, by reading neighbours that already carry that flag. No run in either arm
moves the verb onto `gc-helm.sh`, the other half of that signature.

- **old 1.** "`epic.sh park <bead> [<condition>]`", with "Your exact `epic park` form
  would need a wrapper or a PATH entry."
- **old 2.** "`epic park <bead> [<condition>]`", with "`epic unpark`: it's my addition,
  as the counterpart to your command."
- **old 3.** "`epic park <bead> [<blocker>]` adds the edge and reads it back.", with
  "`<blocker>` is the condition: a bead whose close ends the park."
- **new 1.** "Your sketch was `epic park <bead> <condition?>`. The command I propose is
  `epic-steer.sh park <bead> [--waiting-on <blocker>]`."
- **new 2.** "`epic-steer.sh park <bead> [--waiting-on <blocker>]... [--evidence <visit>]`",
  with "`gc-helm.sh takeaway` and `first-reaction-dispose.sh` already use that flag".
- **new 3.** "`assets/scripts/epic-steer.sh park <bead> [<blocker>]`", with "the command
  is `epic-steer.sh park`, not `epic park`".

### Case B: two names offered in passing

Old 2, old 3 and new 3 define a `gc:` script for each check command, beside the existing
`lint`, `typecheck`, `build` and `test`, which is what the real design did. Old 1 builds
the same kind of set under `check:`, the other name in the sketch. New 1 and new 2 name
their scripts for what they do, such as `lint:strict` and `test:ci`. All three old runs
add the sketched aggregate, `check` or `gc:check`, and each says no city command calls
it. No new run adds one.

Every run reads the `data:` names and argues from them. Old runs and new 3 take them as
a pattern for a namespace. New 1 and new 2 read them as naming what a script acts on, not
who calls it. A gap of one run in three between the arms shows a direction at most, and
the new text does not stop a run doing what the real design did.

The city's commands here run the same tools as the existing scripts with stricter flags,
and no step of their own. The correction in the outline keeps the prefix for a command
special to Gas City, so I read the prefix as having no reason in this fixture. Old 3 gives
the stricter flags as its reason for a separate namespace.

- **old 1.** "the names are my choice. I chose `check` because these scripts aren't
  specific to the city"
- **old 2.** "I read those two names as examples.", with "`gc:` follows the repo's
  existing `data:` namespacing."
- **old 3.** "The prefix follows the existing `data:*` pattern."
- **new 1.** "the repo's existing namespaced scripts (`data:migrate`, `data:seed`) say
  what they do, not who calls them."
- **new 2.** "the existing `data:migrate` and `data:seed` are named for what they act on,
  not for who calls them."
- **new 3.** "I took the `gc:` prefix from that but didn't add a single `check` script",
  with "This follows the repo's existing `data:migrate` and `data:seed` naming."

### Case C: a name given with a reason

All six runs define `gc:reset-db`. The new runs see the neighbours' convention, name
what it would suggest, and keep the operator's name. No old run mentions `data:reset`.

- **old 1.** "The operator asked for this name and for the prefix to carry the rule"
- **old 2.** "The name is as the operator specified."
- **old 3.** "`gc:reset-db` is the name the operator specified."
- **new 1.** "`data:reset` would otherwise be the natural name."
- **new 2.** "so this design uses that name as given.", with "the nearest name would be
  `data:reset`."
- **new 3.** "I kept `gc:reset-db` as the operator specified, because they gave a reason
  for the prefix."

### Case D: a bare rename

All six runs apply `--ruling`, and five of them write the same sentence. This is the
cost the probe found. New runs look further, at an average of $0.27 and 6 to
7 turns against $0.17 and 3 turns, and each brings the operator an alternative to a name
they asked for. New 3 also rewords the sentence and adds a clause the thread did not ask for
to its replacement text: "not the one-line text that `converse-signoff.sh --ruling` takes". The clash is
real, and two old runs flag it as well.

- **old 1.** "Given `--ruling <visit>`, it also records `epic_steer_evidence` (section
  6)."
- **old 2.** "The rename is still as requested"
- **old 3.** "If the new flag should stay as named, the `<visit>` placeholder is what
  tells the two apart."
- **new 1.** "I kept `--ruling` as you asked", with "`--visit <visit>` is the
  alternative that matches the existing scripts".
- **new 2.** "I kept `--ruling` because you asked for that name directly.", with
  "`--ruling-visit <visit>` removes the ambiguity".
- **new 3.** "I kept your name because the thread asks for exactly that.", with
  "`--ruling-visit <visit>` would avoid the clash".

## What it cannot show

This is a cut-down prompt with three runs per cell, so it shows a direction. A real
author reads far more prompt beside this entry, which can dilute the effect.

Every run here had one narrow task and looked at the neighbours, so the probe does not
test an author who never looks, which is how the proposal reads both real failures. Case
A's rework answered 14 threads, and case A hands the run one of them. Only the outline of
the real design behind case B reaches this record, and the fixture is small.

The runs have no edit or shell tool, and several open by saying so. Cases B, C and D are
written for the probe. "A reviewer", "flag" and "key" in the rule's text reach past what
these cases test, because each sketch or instruction here is the operator's.
