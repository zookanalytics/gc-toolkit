---
name: A/B probe of where the distiller puts a fix, tk-zlot608.10
description: Read it to check the probe numbers in tk-zlot608.10's summary, to see where the old and the new learning-distill rules put the fix for pattern tk-7t22ujj and for two control lessons, or to re-run the probe on a later wording.
---

# A/B probe of where the distiller puts a fix

The bead is done when a probe of the new rules on pattern tk-7t22ujj's three
observations puts the fix at a skill's trigger, not in a formula's text and not
in a guidance entry. This probe runs the distiller's judging and filing steps on
those observations with the rules on main and with the rules on this branch. Two
more cases check that the new rules do not pull a lesson away from a carrier
when it belongs in one.

## How it ran

Each arm is a fixture, a `git archive` of one commit with `.claude/skills`
linking each of its skills the way a session's skills are linked, plus the core
pack's skills. The control arm is `d2e123c5d`, the branch's merge base with
main, and the new arm is `5e5bf9459`, the branch's rule commit. The two trees
differ in four files: `skills/learning-distill/SKILL.md`,
`formulas/mol-feedback-distiller.toml`, `docs/feedback-learning.md` and the
formula's seed-audit render. Neither tree has PR #1562's sentence in
`skills/filing-documentation/SKILL.md`, and neither names any of the case's
beads.

A run's first message is built from its own arm's files, in this order:

1. The rendered polecat prompt, `generated/seed-audit/agents/polecat.md`, the
   prompt a distiller run's pool session reads. It is the same in both arms.
2. The judge-and-cluster step, rendered as its hook reminder renders it, with
   the formula's defaults filled in.
3. What the session has done so far. load-and-gate opened the run, section 1
   printed the rubric, section 2 found no pattern for these observations and
   seeded one, and sections 5 to 7 are done.
4. The instruction to take judge-and-cluster and then file-and-dispatch's
   sections 1 and 1b for this cluster, and to make every gc, bd and gh call
   anyway, since each comes back refused.
5. The pending observations as load-and-gate's rows, without their
   `obs.distilled` stamp.
6. The arm's rubric, then the file-and-dispatch step's rendered reminder.

The runs used `claude -p --model claude-opus-5-5 --tools
"Skill,Read,Grep,Glob,Bash" --setting-sources project --strict-mcp-config
--max-turns 40 --output-format stream-json --no-session-persistence`, under
`env -i` with only `HOME`, `USER`, `TMPDIR`, `LANG` and `PATH` set and
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, from the fixture. The distiller runs on
the polecat pool, and the session that ran this probe, a polecat of that pool,
runs that model. Every gc, bd and gh call stopped
at Claude Code's permission check, and stubs first on `PATH` would have logged any
that got past it. Their log stayed empty.

22 runs cost $13.65 and took 60 to 130 seconds each, two to six at a time.

## The case: pattern tk-7t22ujj

The pending set is the pattern's three observations, tk-22twign, tk-j334mkn
and tk-34gh3i3. Each records an arch finding that sent back a design for
leaving `docs/architecture.md` to a later unit. Two of them say the design
step's text is where the rule is missing.

| Arm | Runs | The fix goes in | The owning skill out of scope |
|---|---:|---|---:|
| control | 5 | the design convoy's brief, 5 of 5 | 2 of 5 |
| new | 5 | the filing-documentation pointer or the architecture-document description, 5 of 5 | 0 of 5 |

Every run in both arms routed the cluster to engineering and filed no
prompt-update, so both arms agree it is not a guidance entry. What the new rules
change is where the fix goes. Each new run names the design formula's text only
as a fallback for when neither skill can carry the pointer, and all five say
not to copy the rule. The control's five runs are the real
failure: each puts the rule's words in the brief, as tk-imdyf0d did.

Each run's own words for where the fix goes:

- **Control 1.** "**The fix is the design child's brief**, because that is
  what the author reads when they decide the work's breakdown." Its bead rules
  out "No new review rule or skill change."
- **Control 2.** "In the file-design step, add to the design child's
  `## Deliverable` text what the design's own change owes the repository's
  architecture document." Its bead rules out "Not a change to the
  architecture-document skill."
- **Control 3.** "**The design child's Deliverable** (`file-design-create`) adds
  this: when the design moves the architecture, its own change rewrites the
  statements of docs/architecture.md that the design makes false."
- **Control 4.** "Change the design child's Deliverable text in the
  file-design-create block to say three things:"
- **Control 5.** "Keep it to a duty plus the skill's name". It is the nearest
  control run to the new rules, and its place is still the brief.
- **New 1.** "widening the pointer in filing-documentation, a skill the moment
  already loads, so it fires when a design moves the architecture, not only
  when the author has already chosen to edit the document;" and "The design
  child's description in mol-design-convoy.toml names the owner only if neither
  of those reaches the author."
- **New 2.** "Likely fix: key the filing-documentation pointer, the owner's
  description, or both to the moment when a design moves a responsibility, a
  boundary or a collaboration between parts." and "Do not copy the rule into
  the formula."
- **New 3.** "the pointer in filing-documentation, widened to fire when the
  document being filed is a design record;" with the brief as "the design child
  Deliverable in file-design-create, when neither skill can carry the pointer."
- **New 4.** "One candidate is the pointer filing-documentation already
  carries, keyed to a design or spec that moves the architecture." and "The
  brief names the owner only if neither can carry the pointer."
- **New 5.** "the filing-documentation pointer widens to a design that moves the
  architecture;" and "or, only if neither skill reaches the moment, the design
  child's Deliverable in mol-design-convoy's file-design step names the skill."

The filing-documentation pointer is the place the sitting chose for PR #1562,
and the architecture-document description is the other trigger the new beads
name. New run 2 also noticed that file-and-dispatch records every such fix as
`remedy_class=structural`, which reads oddly for a pointer. The lifecycle
registry defines that value as a remedy in code rather than a prompt rule, and
nothing reads it, so this branch leaves it.

## Control: a naming lesson the pack already owns

The pending set is tk-ksvcqz9, the operator's naming ruling in sitting
tk-weluos5 and the evidence rule tk-karx6a2 was adopted from. Both fixtures
drop that rule's entry from `template-fragments/work-quality-polecats.template.md`
and the polecat renders, and drop `specs/tk-jvl45ot/` and
`specs/tk-zlot608.1/notes.tsv`, which name it. The real outcome was the
work-quality entry the operator merged.

| Arm | Runs | Outcome |
|---|---:|---|
| control | 3 | surface, held on Gate 1, 3 of 3 |
| new | 3 | NOOP, 2 of 3; a fix in the arch check's method, 1 of 3 |

Neither arm reproduced the real outcome, so this case cannot show whether the
new rules keep such a lesson in a carrier. The control held it as one event
whose voice the refused transcript read could not confirm. The new runs found
that the "The rule that names a verb" section of `docs/gctk-architecture.md`
owns it. Two closed the pattern as already covered: "I judged the cluster as
**NOOP**: the rule is already covered where it belongs". The third filed a fix
whose "likely place is a check in docs/review-arch.md's divergence lens that
links the section." That run filed on a single observation, because the
promotion gates do not guard a fix, and the bead waits for the operator's
placement like any other.

## Control: a lesson any turn needs

This case is synthetic, so it shows the shape of a judgment and nothing about a
real failure. Its three observations are made up for the probe. They ask for
clock times in UTC with a trailing Z, wherever an agent writes one, from a "learn
this:" endorsement, a PR summary and a mail. No file in the pack owns such a
rule, and the endorsement clears Gate 1, so the carrier is the only thing the
case decides.

| Arm | Runs | Outcome |
|---|---:|---|
| control | 3 | a `work-quality-base` entry, 3 of 3 |
| new | 3 | a `work-quality-base` entry, 3 of 3 |

The new rules kept the lesson in its carrier, and two runs give the moment as
the reason: "No single skill or step covers all of those, so a fix in one file
wouldn't reach the others. It needs a standing carrier." and "an agent can need
the rule at any turn."

## What it cannot show

- A real run takes judge-and-cluster and file-and-dispatch as two claims in one
  session. Here both steps' text arrives in the first message, so a run reads
  file-and-dispatch before it judges.
- The cluster is formed for the run, and the reads that need the store, such as
  a quote's voice and the dedup against open work, are stated or refused.
- Five runs a cell show a direction. The headline case is 5 of 5 against 0 of 5,
  and each control case is three runs.

## Re-running it

The harness is in the implement session's scratch, `~/.cache/tk-zlot608.10/probe/`
in the polecat's home, and a later session may find it reclaimed.
`build_case.py <probe> <arm> [<pending.json> <count>]` writes the case,
`run-one.sh <probe> <arm> <n>` runs one and keeps a finished output, and
`show.py <output>` prints a run's tool calls and its last message. A rebuilt
harness asserts that the new arm's tree is the branch's commit before it spends
a call.
