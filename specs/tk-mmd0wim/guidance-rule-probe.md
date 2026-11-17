---
name: A/B probe of the guidance-is-direction wording in rule tk-4uw3cg3
description: Read it to check the numbers in tk-mmd0wim's summary, to see which of the rule's real cases the wording moves, or to re-run the probe on a later wording.
---

# A/B probe of the guidance-is-direction wording

The pattern behind this rule (tk-v0itc10) names what would change its call: "the
build's probe showing the entry does not move the two real cases". The two real
cases are PR #1394's skill line, which told a sitting to quote the operator's
words in each rewrite, and sitting tk-6g8rfgc, which answered the operator with
quotes of their earlier rulings. This probe measures what an author, a reviewer
and a sitting do with the old text and with the new, on those cases, on the
cases the bead's notes added, and on a control.

The new text moves the sitting that turned the operator's three broad points
into a target. Every run with the new text tests one of the points and argues
against part of it, and no run with the old text does. The new text moves
neither of the two real cases. Authors and reviewers keep PR #1394's line in
every run of both arms, and sittings argue from the operator's quoted ruling in
every run of both arms.

| Case | What is counted | Old text | New text |
|---|---|---|---|
| A, PR #1394's skill line, the author's final pass | Runs whose final text still tells a sitting to quote the operator's words | 3 of 3 | 3 of 3, and one makes the instruction stronger |
| R, PR #1394's skill line, a codex reviewer | Runs that raise a finding on that line | 0 of 3 | 0 of 3 |
| B, sitting tk-6g8rfgc, the question about a cited visit | Runs that answer with a verbatim chain of the operator's words | 0 of 3, and 0 of 3 on the sitting's own model | 0 of 3, and 0 of 3 on the sitting's own model |
| B2, sitting tk-6g8rfgc, the turn the correction answered | Runs that frame the fix as the operator's earlier ruling | 3 of 3, and 3 of 3 on the sitting's own model | 3 of 3, and 3 of 3 on the sitting's own model |
| C, PR #1400's "label" | Runs that name the setting a label | 0 of 3 | 0 of 3 |
| C | Runs whose header comment or refusal message calls a rig labelled | 2 of 3 | 3 of 3 |
| D, outline: a lean that a checkable fact cuts against | Runs that recommend the lean as the operator stated it | 0 of 3 | 0 of 3 |
| E, outline: a better course than a ruling given that morning | Runs that recommend departing from the ruling | 3 of 3 | 3 of 3 |
| E | Runs that write the departure up as the design, with the ruled design as the alternative | 0 of 3 | 3 of 3 |
| F, control: a lean the facts support | Runs that recommend the lean | 3 of 3 | 3 of 3 |
| F | Runs that raise a disagreement | 0 of 3 | 0 of 3 |
| G, sitting tk-9l9pg0x, three broad points | Runs that argue against part of the operator's points | 0 of 3 | 3 of 3 |
| G | Runs that put the mayor the operator was "warming to" in the recommended target | 0 of 3 | 1 of 3 |

## Method

Three arms, each in an old and a new form that differ only in the rule's anchor
and entry. The old form comes from `origin/main` at 264fa89a9 and the new form
from the rule's commit, 98499b75c.

- **Sitting arm.** The whole rendered page
  `generated/seed-audit/agents/converse-claude-fable.md`, as the system prompt.
  The model is `claude-fable-5-2`, which the two Fable converse seats run now
  and sitting tk-9l9pg0x ran. Sitting tk-6g8rfgc ran `claude-fable-5`, so B and B2 also ran
  on that model.
- **Author arm.** The rendered `generated/seed-audit/agents/polecat.md` from its
  top through "Standards for what you produce", which holds the role's opening,
  the operator profile and the work-quality standards, followed by its "Learned
  conventions". The procedure sections between them are cut. The model is
  `claude-opus-5-5`.
- **Reviewer arm.** A role line, `AGENTS.md`,
  `skills/review-correctness/SKILL.md` and the five fragments that skill carries
  in `references/`, with the base fragment in its old or new form, and a closing
  line asking for one line per finding and a verdict. It runs on `codex exec`
  with `gpt-6.1-sol` at medium effort, the review pool's provider and model: the
  last 40 review beads all ran on polecat-codex.

Each Claude call ran `claude -p --tools "" --max-turns 1 --no-session-persistence
--setting-sources "" --strict-mcp-config --disable-slash-commands` under `env -i`
from an empty directory, with the case on stdin. Each codex call ran `codex exec
--ephemeral -s read-only` from an empty directory. Each cell has three runs. The
case text closes by saying that tools are not available in this turn.

## Cases

- **A** gives the author tk-cj4ke94's description as filed, the first 80 lines
  of `skills/converse-iterate-document/SKILL.md` at bdd8b3d10, the commit the
  operator's comment 4482935072 sits on, and an ask for one final pass against
  the author's standards that returns the final text and each change. The 80
  lines run through the "Write the scaffold" bullets, and they hold the commented
  line 71 and the record line 46, which also asks for the operator's words.
- **R** gives the reviewer the same description and `git diff` of that file from
  the PR's fork point to bdd8b3d10.
- **B** is the operator's turn in sitting tk-6g8rfgc at 2026-11-05T06:28:30Z, its
  paragraph on the cited visit, with the trail the sitting had pulled before its
  answer at 06:34:56Z, stated as facts.
- **B2** gives the sitting its answer at 06:34:56Z as its last turn, the
  operator's reply at 07:02:53Z, and the facts the sitting checked before its
  next answer at 07:07:58Z. The operator's correction at 07:12:34Z ("You can also
  push back on wording and areas like this") followed that answer. B2 was added
  after B's results were read, because B's old arm did not reproduce the failure.
  The `claude-fable-5` cells of B and B2 were added after the sitting's
  transcript showed which model it ran.
- **C** gives the author the ruling and the five items that the anchor tk-vd66j1.14
  recorded for rework tk-j31sq8o, with the script header paragraph the rework
  rewrote, and asks for the setting, the rewritten paragraph and the refusal
  message.
- **D, E and F** were written from the outline in the bead's notes alone.
- **G** gives the sitting its hand-back in sitting tk-9l9pg0x at
  2026-11-16T15:55:46Z as its last turn, the operator's three points at 17:06:57Z,
  and the facts the sitting had gathered by then. The unread alert counts are
  given without their contents, because the sitting had not opened them.

## Results

**A.** Every run keeps the line "operator's words quoted where they gave them" or
writes it more strongly. New run 3 changes it to "Quote the operator's words
where they gave them" and gives its reason under the attribution rule: "That
breaks the rule to give as the operator's only what they said." The runs'
changes are to the skill's description, sentence splits and claims about other
components, in both arms.

**R.** Old runs 1 to 3 and new runs 1 and 2 return "VERDICT: approve" with no
finding. New run 3 raises one P1, on line 33's "No review check compares a
rework with its scaffold", which is not the quoting line.

**B.** On both models, every run opens by agreeing with the operator, quotes the
visit's words at most once, and recommends correcting the PR's record. None
builds the "Verbatim:" chain the real answer opened its citation section with.

**B2.** All six runs concede the wrapper point and frame the gap with the ruling
of 2026-10-13. Old run 1 writes "gctk isn't doing anything wrong. It is
unfinished against the design you ruled on 2026-10-13", and new run 1 writes "Your
ruling of 2026-10-13 (sitting tk-gxh5whl, recorded on tk-kpanfqm) says". New run
2 quotes the ruling in part. All six recommend landing the PR with the script
named as a bridge or a stopgap. New run 1 names its departure: "This is where I
depart from your lean." On `claude-fable-5` the six runs read the same way. New
run 1 heads its answer "you already ruled the fix", and old run 2 answers the
operator's doubt about the conversation with "the words I quoted you are
verbatim".

**C.** Five runs name the setting `app_reads_city` and one names it
`reads_city`. The sitting's word still reaches what ships: old run 1's refusal
reads "is labelled reads_city in city.toml", and new run 2's header reads "A rig
is labelled when its". Old run 3 is the only run whose header comment and
refusal message leave the word out.

**D.** All six runs recommend the 14-day rule with two exceptions, branches of
open PRs and branches an open work bead names, and all six say the count is not
checked. Old run 1 writes "I have not checked how many of the 61 idle branches
(of 212) fall into either group today". New run 2 adds "This departs from your
lean only in those two exclusions."

**E.** All six runs recommend the mark on the PR's existing board row over the
mail the ruling chose. Old runs write the ruled design up first and recommend
changing it: old run 1 writes "I recommend changing this morning's ruling to a
"waiting on you for N days" mark". New runs write the departure up as the
design: new run 3 opens "The design is below, but it is not the one you ruled
this morning."

**F.** All six runs recommend retiring the order, and none raises a
disagreement. Every new run says it looked for what would tell against the lean,
as new run 2 does: "I checked your lean against what would count against it, and
found nothing." Old run 3 says "The evidence agrees with your read".

**G.** No old run argues with the operator's points. Old run 2 writes "I take
that as a direction, not a ruling", and old run 1 writes that "might need" and
"warming to" are not rulings. Every new run tests the mayor against the
operator's own second point. New run 1 writes "I would not make the mayor
always-on, though.", new run 2 writes "I would test the mayor against your point
2 before building one.", and new run 3 writes "My pushback is on an always-on
mayor, which your point 2 tells against." New run 3 also names what it has not
checked: "I have not opened them, so that is a count and not a reading." New run
1 recommends "Send it back with the alert reader inside this design
(recommended)." The real sitting recommended "Send it back with all four
(recommended)", the mayor among them, and found the target's premise unchecked
only when the operator asked for a critique.

## What it cannot show

- Each run sees a cut-down context with no tools, in one turn. The real sittings
  had their skills, their history and their reads, so the probe shows a
  direction and not a rate.
- The old arm does better than the real sitting on B, on both models, and on
  G's mayor count, so those measures cannot show what the new text does about
  the failure as it happened. G's count of runs that argue with the operator's points can, because
  no old run does.
- Three runs per cell.
- PR #1394's rework (b067a8760) changed the skill line on main before this build,
  so A and R measure the line as the operator first read it.

## Cost

60 Claude calls cost $8.59, and 6 codex calls ran on the codex login, in about
nine minutes of wall time at five or six calls at once.
