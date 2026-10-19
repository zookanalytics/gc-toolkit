---
name: The divergence lens applied blind to the gate-to-visit converter
description: Record of the check behind tk-1tfzr71.2's done criterion, that a reviewer following the arch check's divergence lens would have flagged the gate-to-visit converter (#655) at review time. Two fresh reviewers judged #655's diff against upstream as of its review date, one with the arch skill before the lens and one with it. Read it for the method, the two verdicts, and what upstream already shipped on 2026-09-05.
---

# The divergence lens applied blind to the gate-to-visit converter

## The question

tk-1tfzr71.2 is done when the arch skill states the divergence lens and a
reviewer following it would have flagged the gate-to-visit converter at review
time. That converter is `gate-visit-sweep.sh` and its order, added by #655
(1635a9bb7, merged 2026-09-05). It files a converse visit, a pack bead kind, on
the gated bead of every open native human gate, and stamps `gc.gate_visit` on
the gate.

No arch review ran on #655. Its anchor (tk-wr8r21) carried `check_set=codex`,
and the arch check did not exist yet. So the evidence has to come from running
the lens on the diff now, with only what a reviewer could have read then.

## Method

Two fresh reviewers, each a general-purpose subagent on the implementing
session's model, were told to follow only the method they were given, to read
nothing else, and to report a verdict without posting it.

- **A** had the arch skill as it stands on main before this change (last
  changed at 9db3fea95, unchanged at b399e485c).
- **B** had the arch skill with the lens, gc-toolkit's extension
  (`docs/review-arch.md`), the Boundaries section of `docs/foundation.md`, and a
  note that the warrant record holds no entry covering the diff. The
  extension's converter example, "a sweep that files a pack bead for each gate
  or session", names #655's own shape, so B's copy read "for each object of one
  kind" instead. B's copies are this branch's first commit of the lens. The
  skill's "When triage adds it" section, which tells triage when to add the
  check and does not bear on the arch verdict, came later, as did wording
  edits to the extension.

Both had the same inputs otherwise:

- #655's commit, message and diff.
- The architecture docs at its base 9fe3eeb07: `architecture.md`,
  `foundation.md` and `component-model.md`.
- Read access to gc-toolkit at the base and the reviewed commit only.
- Gas City as of the review date: upstream `main` at 76d37b9b9, its tip at the
  end of 2026-09-05, read from the local clone at that commit only.
  The web docs were out of bounds, because they show today's upstream.

## Results

**A, the arch skill before the lens: request-changes, for documentation
only.** It asked for:

- a component row for the sweep and its order;
- registration of the two new keys, `gc.demand_kind` and `gc.gate_visit`;
- updates to the design docs the change made stale, component-model's I1 and
  the authority map's demand writers.

It judged the move onto native gates as fitting the architecture. It judged
the sweep as fitting too, because it "files visits through `gc-helm.sh open`,
which the docs name as the one place visit filing lives". It read the core
gate orders at 76d37b9b9 and cited them in support of the change. Once the
docs were updated, nothing in its verdict would have held the converter back.

**B, the lens: request-changes, with the converter as its lead finding.**

- **Check 3, converter.** `gate-visit-sweep` keeps a visit, the pack's noun,
  in step with the human gate, Gas City's: one visit through `gc-helm.sh open`
  for each open human gate, linked back by `gc.gate_visit`. The platform
  primitive is the human gate, which core already puts in front of a person
  through its notify and re-nudge orders. The fix is to take the sweep, its
  order, its test, the key and its doc paragraph out of the change, and to
  file the move onto the gate as its own bead.
- **Check 1, search.** The commit justified the visit as "the operator's
  attention channel (the "human" mailbox is unread)". At 76d37b9b9 the
  `human` mailbox is only the notify order's default. The order resolves the
  addressee from the gate's assignee, then `gc.deferred_assignee`, then
  `$GC_ESCALATION_RECIPIENT`, which defaults to `human`
  (`notify-on-human-gate-creation.sh`). An order override can set its
  environment (`docs/tutorials/07-orders.md`), and `gc mail send --notify`
  requests a turn from a recipient that is not running
  (`docs/reference/cli.md`). The change never showed why a configured
  addressee could not carry the reach.
- **Checks 1 and 2, `gc.demand_kind`.** It is a new key with no search and no
  warrant, and nothing reads it.
- **Question 2.** The same documentation gaps A found.

B kept the parts that move onto the platform: filing the demand with
`gc bd gate create`, and the readers' `--include-gates`.

## What upstream shipped at review time

At 76d37b9b9, `internal/bootstrap/packs/core/README.md` lists two core orders:

- `notify-on-human-gate-creation`, on `bead.created`, mails and nudges the
  addressee when a human gate is created.
- `renudge-stale-human-gates`, on a 5m cooldown, re-mails and re-nudges the
  addressee of a human gate left open past a staleness threshold.

Both landed upstream on 2026-07-23 (741a2d9de, gastownhall/gascity#4553). The
visit spine landed in the pack on 2026-08-09 (#259). So the evaluation record's
premise that the visit noun was born when upstream had no human gate (tk-xexv7bo
notes, turn 3) does not hold for upstream: the gate and the orders that put it
in front of a person were both already shipped.

## Conclusion

The lens is what makes the difference. Both reviewers read the same diff, the
same docs and the same upstream orders. A read the orders as support, because
it measured the change against the pack's architecture docs, which already
named the visit as the place a person is engaged. B measured the new surface
against Gas City's own primitives and found the converter, the missing search,
and an unwarranted key. A reviewer following the lens would have flagged the
converter at review time, and the evidence it needed was in upstream's
repository that day.

Two limits:

- B's copy of the extension had its converter example made generic. The real
  extension names a sweep that files a pack bead for each gate or session, so a
  live review would meet #655's shape spelled out.
- This is one run per method on one diff. It shows the lens can catch this
  converter, not how reliably every reviewer will.
