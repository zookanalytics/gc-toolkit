---
name: Work record — the no-history-in-prose audit counted its own exemptions
description: Why tk-xjekbl's headline count of ~29 bead ids in agent prompts was a token-matching artifact, what the four genuine citations were, and why the fix spans six mirrored copies of the gate-visit block plus the test that pins them.
---

# The audit counted `gc-toolkit` as a bead id

Work record for `tk-xjekbl`. The shipped change removes four bead-id citations
from the gate-visit block and the six files that carry a copy of it. This note
records how the bead's premise was re-derived and why the diff does not match
the file list the bead carries.

## What the bead claimed

The bead reported roughly 29 bead ids in body prose across nine files, 11 of
them in `agents/converse/prompt.template.md`, and drew its conclusion from that
ranking: converse leads the list, and converse is the agent the rule was adopted
to change. It reported a further 7 absolute dates and 4 PR references across
`template-fragments/`.

## What the measurement actually matched

The literal token `gc-toolkit` occurs exactly 29 times across exactly the nine
files the bead lists. A detection pattern of the shape `(tk|ga|gc)-[a-z0-9]{5,8}`
matches the pack's own name, and the pack's own name is what the count is
almost entirely made of:

| file | `gc-toolkit` | bead's figure |
|---|---|---|
| `agents/converse/prompt.template.md` | 9 | 11 |
| `agents/mechanik/prompt.template.md` | 6 | 5 |
| `agents/proactive/agent.toml` | 3 | 3 |
| `agents/proactive/prompt.template.md` | 1 | 5 |
| the remaining five files | 1 each | 1 each |

The residual differences are the real bead ids in `agents/proactive`, plus
approximate arithmetic. Converse's own figure is 9 occurrences of the pack name
and 2 references to a spec path.

The dates and PR references resolve the same way, and more sharply: all 7 dates
and all 4 PR references in `template-fragments/` sit inside HTML provenance
comments. That is precisely the set the bead's own "Out of scope" section
exempts, because the learning loop requires those anchors to name a source ref
and an adoption date. The count included the exemption it declared.

So the bead's ranking is inverted. Converse carries no violation, and the one
file that does is `agents/proactive/prompt.template.md`, which the bead ranked
joint-fourth.

## The genuine citations

Four, all in the marker-delimited `gate-visit` block: `tk-ax6y4` and `tk-msfmu`
in a comment explaining why the group stamp is read back, `tk-d6ddn` in the
comment's closing sentence, and `tk-ax6y4` and `tk-d6ddn` again inside two
runtime warnings on stderr. The surrounding sentences already state the
mechanism and the constraint in full, so every citation was removable without
rewriting an argument.

Two things in `agents/converse` are deliberately left alone. The two references
to `specs/tk-h9pq5/design-doc.md` are a path to a live document that
`agent.toml` names as design authority, which is where the rule says an
identifier belongs. The `--waiting-on tk-hgmob` pair is example command
arguments inside a code fence, which the bead exempts.

## Why the fix is wider than the bead's stated scope

Formula bodies are plain string substitution with no include mechanism, so the
gate-visit convention lives as marker-delimited copies. Six ship: three
formulas, two scripts, and the `agents/proactive` prompt. `gate-visit.test.sh`
extracts every copy and asserts the same invariants on each, and one of those
assertions grepped for the literal string `repairing (tk-ax6y4)`.

Editing only the in-scope copy would therefore have turned the suite red and
desynced a convention whose whole purpose is to stay identical across surfaces.
The bead's scope names `agents/**` and `template-fragments/**`; satisfying it
for the one file that violates the rule requires the other five copies and the
test in the same commit.

The test assertion now pins the behaviour instead of the citation: the warning
must name `gc.continuation_group` and end in `repairing`. Deleting the warning
text from a copy still fails the assertion, which was confirmed by mutating one
copy and observing the single expected failure.

## The boundary the fix does not cross

The same three bead ids are cited in the prose of four files that are not
gate-visit copies: `converse-claim.sh`, `converse-signoff.test.sh`,
`gc-helm-open.test.sh` and `liveness-sweep-precheck.test.sh`. They are left
alone. The bead's "Done when" names `agents/**` and `template-fragments/**`,
and nothing about those four forces them into this commit the way the mirrored
block forces its five siblings: each states its own constraint in its own
words, and editing one does not desync a convention or turn a suite red.

The wider sweep is its own job, and a costly one to specify. A pattern over
short hyphenated tokens cannot find its targets here, because the pack's
scripts are full of synthetic fixture ids of exactly that shape — `tk-work`,
`tk-foreign`, `tk-abc12`, `lx-codex` — which outnumber the real citations by
more than an order of magnitude. Separating a citation from a fixture is a
reading task, not a matching one.

Filed as `tk-n231a4`.

## A pre-existing hole the test rewrite did not close

The assertion that each copy repairs a lost stamp is a conjunction, and its
first half greps the whole block for `--set-metadata "gc.continuation_group=`.
Every block already contains that string in its INITIAL stamp, so the conjunct
is satisfied whether or not the read-back arm repairs anything. Deleting the
repair line outright leaves the suite green.

This is not a regression from the citation rewrite. The same mutation passes
against pristine `origin/main` with the old `repairing (tk-ax6y4)` assertion in
place, so the new assertion catches exactly what the old one caught and misses
exactly what it missed. Filed as `tk-fyapf0` rather than fixed here, to keep
this diff to the rewrite it is reviewed as.

## What a detector would have caught

The rule this bead enforces is not mechanically checkable by a pattern over
short hyphenated tokens, because the pack's name, several formula names, and
ordinary hyphenated English all share that shape. A count that quantifies a
violation is only meaningful once it excludes the exemptions the same document
declares, and once its pattern has been read back against the tokens it
actually matched.
