---
name: The pack-content section applied blind to #1303's reviewed head
description: Record of the check behind tk-yt6pmyv's done criterion, that a correctness review of #1303's reviewed head e81c447b4, run with gc-toolkit's extension section on the pack content every rig runs, returns the gc-toolkit-only lines #1303 wrote into skills/review-arch/SKILL.md and the arch row of review-checks.toml as a finding. Four fresh reviewers judged the same diff, one with the extension as main has it and three with the section, as first written and after each of two amendments. Read it for the method, the four verdicts, what each amendment answered, and the boundary rule every reviewer already held in its context.
---

# The pack-content section applied blind to #1303's reviewed head

## The question

tk-yt6pmyv is done when `docs/review-correctness.md` carries a section on the
pack content every rig runs, and a correctness review of #1303's reviewed head
e81c447b4, run with it, returns the gc-toolkit-only lines in
`skills/review-arch/SKILL.md` and the arch row of `review-checks.toml` as a
finding. The city's correctness review of that head, tk-vdiozfc, approved it
with no blocking finding. The operator's review of #1303 then flagged the
change's lines in those two files as gc-toolkit's own rule written into pack
content: the arch row's new purpose, the skill's new description, and the
divergence lens.

## Method

Four fresh reviewers, each a general-purpose subagent on the implementing
session's model (Opus 5.5), were told to follow only the method they were
given, to read nothing outside their own input directory, and to report a
verdict without posting it. Each had its own copy of the inputs.

All four had the same inputs, apart from the rig's guidance:

- the correctness method as main has it at 5ed3e80e1,
  `skills/review-correctness/SKILL.md`, with its references resolved;
- the anchor tk-1tfzr71.2's description as filed;
- #1303's diff from its base b399e485c to e81c447b4, and the branch's four
  commit messages;
- the tree at e81c447b4, exported without its git history.

Their guidance, `docs/review-correctness.md`, differed:

- **k3** had it as main has it at 5ed3e80e1, with no section on pack content.
- **p8** had it with this branch's section as first written. k3 and p8 ran
  side by side.
- **m5** had the section after a first amendment, made from p8's report. It
  added that the finding names every line that carries the rule, such as a
  skill's description or a check's purpose in `review-checks.toml`, and that
  making the rule apply only where a rig's own extension opts in is no fix.
  One phrase of the definition also changed, from "for a rig's work" to
  "which every rig shares".
- **n2** had the section as this branch lands it, at c462a4893. A second
  amendment, made from m5's report, added that a clause a change adds to a
  description or a purpose to announce the rule carries the rule, even when
  the clause read alone states a general principle.

Each was told to run no suite and to take the test evidence as a recorded
pass. Each skipped "The PR as published", because no PR or pending summary
existed, and did the sweep and the verification itself.

Every subagent the implementing session starts loads that session's project
instructions and memory index, and a probe subagent confirmed both. The
instructions are the pool checkout's `CLAUDE.md`, which imports `AGENTS.md` as
main has it. `AGENTS.md` says a rule that binds only work on gc-toolkit's
repository never goes into the skills, formulas, agent prompts and template
fragments the pack ships. A search of the memory index for the class's terms
found no entry. So every reviewer had the boundary rule in its context, as a
reviewer working in a gc-toolkit checkout has it today. The city's review of
#1303 ran before `AGENTS.md` existed.

## Results

**k3, without the section: request-changes, with the lens's reach as a
readiness defect.** It raised three P1s:

- The lens and its mandatory triggers apply in every rig that declares arch,
  though only gc-toolkit's extension names the platform, the rule and the
  warrant record they need (Readiness). Its fix keeps the lens in the pack
  skill and runs it only where a rig's extension names those inputs.
- Nothing tells triage where the warrant record is (Cross-file trace).
- "The first two make the check mandatory" names a set by its count
  (Work-quality standards).

It left "whether the lens should reach other rigs at all" to the arch and pm
checks. It named the arch row of `review-checks.toml` only as the reason a
later approve owes `--needs-you`, and raised no finding on it or on the
skill's description.

**p8, the section as first written: request-changes, with the lens as
gc-toolkit's rule in pack content.** Its first P1 said the skill every rig
loads states gc-toolkit's own boundary rule in wording that fits any
repository, and that the guidance's section on pack content makes it a P1. It
offered two fixes: run the lens only where a rig's extension adopts it, or
move it into gc-toolkit's `docs/review-arch.md`. Its other P1 was on
`docs/warrants.md`'s Covers paths. It raised no finding on the arch row or the
description.

**m5, after the first amendment: request-changes, with the lens moved out of
the pack.** Its first P1 named the skill's triage section, the lens with its
surface list and four checks, and the lens's two verdict bullets. It said the
pack skill every rig loads carries gc-toolkit's own discipline, and gave one
fix: move the lens, the warrant rules and the mandatory triggers into
gc-toolkit's `docs/review-arch.md` and a gc-toolkit `docs/review-triage.md`,
keeping in the skill only what holds for every rig. Its other P1 was triage's
missing route to the warrant record. It judged the clause about rebuilding
what the platform ships, in the skill's description and in the arch row's
purpose, to be the generic grain test, and said both could stay.

**n2, the section as this branch lands it: request-changes, with every line
#1303 wrote into the two files.** Its one P1 named the skill's description,
its triage section, its first question, the divergence lens and the lens's
verdict bullets, and the arch row's purpose in `review-checks.toml`. It said
the lens is gc-toolkit's own foundation rule, worded for any repository and
written into the pack skill that every rig declaring arch loads, and that the
P1 rests on the guidance's section on pack content. Its fix moves the lens into
`docs/review-arch.md` and the mandatory trigger into a gc-toolkit
`docs/review-triage.md`, and restores the description, the first question,
the verdict bullets and the purpose to text that holds for every rig. Its
verification read CONFIRMED. Its seven P2s were on the warrant register, the
arch extension, the skill's pointer to it, the earlier blind-review record and
the suite's pins.

## What it shows

- Without the section, a reviewer that already held the boundary rule in its
  context still found the lens's reach into every rig a blocking defect. It
  filed it as readiness, asked for a condition that keeps gc-toolkit's text in
  the pack, left where the lens belongs to the arch and pm checks, and passed
  the description and the arch row.
- With the section, every reviewer made the placement itself the correctness
  finding. The first text left the two summary clauses alone and offered the
  condition as one of two fixes. After the amendment on conditions, m5 asked
  only for the move, and still passed the summary clauses. After the
  amendment on announcing clauses, n2 named every line #1303 wrote into the
  two files and asked for the fix #1303's rework made.
- The done criterion holds for the text this branch lands. n2 returned the
  gc-toolkit-only lines in `skills/review-arch/SKILL.md` and the arch row of
  `review-checks.toml` as one P1 finding. The same-setup baseline, k3, did not
  return the description or the arch row, and did not ask for the move. The
  city's review, tk-vdiozfc, approved.

## Limits

- Each text ran once, and a model's review varies from run to run. Both
  amendments came from the runs before them, so n2 checks the final text
  against the same diff the text was refined on, not against a fresh case.
- The reviewers ran on Claude. The city's review pool runs codex, and
  tk-vdiozfc followed an older correctness method.
- The reviewed tree predates `AGENTS.md` and the architecture page's boundary
  paragraph, so the section's links named files the tree lacked. Every
  reviewer still read `AGENTS.md` as main has it, through the implementing
  session's project instructions.
- Each review took about 20 to 23 minutes and between 280k and 305k
  subagent tokens.
