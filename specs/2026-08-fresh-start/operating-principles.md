---
name: Operating principles — operator statements, 2026-08-08
description: Three operator principles for the fresh start (any item can host a grounded discussion; ideas get processed before the conversation; no idle beads — every path terminates in a human gate or active work) plus one operator idea (conversations recommend applicable mols), each recorded in the operator's words with the mechanism it maps to and the gap it opens.
---

# Operating principles (operator, 2026-08-08)

Statuses per the working contract: **P1–P3 are OPERATOR PRINCIPLES**
(stated for review; the operator asked for them to be reviewed, and the
commentary below is that review). **P4 is an OPERATOR IDEA** ("arguably
more an idea than a stronger perspective," their words). Commentary and
gap-naming are the assistant's.

## P1 — Any item can host a grounded discussion

> "For most any item (usually these are blocked, not fully defined,
> broader in scope aka an Epic, etc), we can have a discussion grounded
> in that topic. I believe that's the 'turn' concept here."

**Mapping — built (the spine).** One terminology precision: the
*subject bead* is the conversation's identity and home (its id is the
continuation group); a **turn** is one *visit* within that conversation.
So: any bead can gain a conversation; turns are how visits happen; the
turn sequence is the durable record. Blocked, fuzzy, and epic-scale
items are exactly the beads the design expects to carry conversations —
and epics can only be conversed through turn-children (a core routing
constraint, not a style choice).

## P2 — Ideas get processed before the conversation

> "There is an easy path to record an idea, have an agent start
> processing that idea, and then execute (example clear bug), explore a
> few ideas (example a visual proposal), do research, etc. It should not
> assume all information is in the initial conversation … Think: I heard
> you, I looked around, now I'm ready to talk. Or: I heard you, that was
> a straightforward fix, done."

**Mapping — exists in pieces; the wiring is the gap.**
`mol-first-reaction` IS "I heard you, I looked around, now I'm ready to
talk": it reads the bead's universe, does the cheap reaction, writes the
card, and (since the flag removal) files the turn. The "straightforward
fix, done" leg is triage concluding the item is executable and routing
it to work — through the gated path. What's thin is the front of the
pipe: *recording an idea* must be nearly free (the nursery), and the
baseline processing should follow by default rather than by hand-sling
(`tools/gc-proactive.sh scan --sling` does this for movable-forward
beads but ships default-disabled). **Gap named:** the intake default —
new seed beads flow to baseline processing without operator ceremony.

## P3 — No idle beads: every path ends at a human gate or live work

> "Work / beads generally do not sit idle. All paths in the graph should
> eventually hit something that's waiting on a human or some work that's
> still being done. The main exception … ideas to be held but not acted
> on. They still should have a baseline research … but may be waiting on
> prioritizing … But arguably, that degrades down to a clear
> conversation to be had with the user, hence still a human gate."

**Mapping — the liveness invariant, and it is enforceable machinery,
not aspiration.** A bead that is open but unrouted, unassigned, ungated,
and turnless is an *unnamed wait* — a defect a patrol can hunt: classify
every open bead as (a) being worked, (b) gated on a named check, (c)
holding/awaiting a turn, or (d) unnamed — and normalize (d) into a turn.
This principle was independently ratified once before (the prior
attempt's liveness ruling, upstream-verified: an open human gate counts
as a legitimate named wait). **Gap named:** the sweep is not yet built
on this branch — it is the next increment after the gate fragment.

**One pressure point, raised rather than buried:** held-ideas-as-gates
scales badly if each idea holds its own conversation — a hundred parked
ideas must not become a hundred board rows. The scalable degradation is
a *batched* prioritization conversation: one recurring triage subject
whose turns sweep the held-idea pool ("these five look ripe — promote,
park, or kill"), so the backlog costs one conversation, not N.

**RESOLVED — OPERATOR POSITION (2026-08-08): batched triage subjects,
scoped, plural, on common patterns only.** The operator endorsed the
batched shape and sharpened it into the clean form of the mayor's triage
hat: *"something whose charge is the big picture and engaged to triage
broadly"* — but never as a single resident agent, whose known failure
mode is unbounded context growth and forced serialization (*"if you're
mid-conversation about one set of triage, then need something on a
different set … forced through a single agent, you end up forced to
resolve the one conversation first"*). Instead: **a triage conversation
is an ordinary subject bead scoped by its body** — "triage: all P1s of
this rig," "triage: held low-priority ideas" — living until its job is
done, several coexisting, each with its own continuation group, turns,
and context. The operator's constraint: *"just make sure we stick to
common patterns here."*

The design consequence, verified against what exists: **zero new
machinery.** The chassis is converse; the *scope is the lens*, carried
in the triage subject's own body (each turn's prep = enumerate the
scope, rank ripeness, frame promote/park/kill) — the one-chassis,
lens-from-the-bead pattern working as designed. Context cleanliness is
structural, not disciplinary: per-subject continuation groups mean
parallel triage conversations never share a session, and turn
boundaries shed context — the exact anti-mayor. Recurrence rides the
standard trigger shape (an order drives a formula; the formula files a
turn only if the scope has ripe candidates and no open triage turn
exists — a turn is a board row, never a ping), and lands with the P3
sweep increment. One convention to hold: scopes should be near-disjoint
by construction so a held bead has one obvious triage home.

This also answers the standing open question from the conversation
design (tk-h9pq5 OQ2, "how is the mayor engaged once coordination
distributes"): the mayor's triage hat decomposes into scoped triage
subjects; what remains of the mayor role is dispatch-of-the-unhosted,
which the P2 intake default covers mechanically.

## P4 — Conversations recommend the applicable mol (OPERATOR IDEA)

> "When actions are needed, I feel like recommended mol(s) that would
> apply are also critical. Too often it's sling this work — our
> conversations should better support: there is a planning mol, let's
> flesh out these questions and then send it to the planning mol, or
> even just send the idea to the planning mol as part of the initial
> triage, knowing the planning mol will have its own checks for when it
> needs more information."

**Mapping — this is "borrow before invent" applied internally, and the
trial demonstrated the receiving end works:** the build factory accepted
a brief and self-managed its stages; with the ratification graft, a
half-formed idea can be sent into a planning mol *safely* because the
gate catches it before beads land. Two concrete carriers: (1) the
converse prompt now instructs routing action through the applicable
formula rather than bare-slinging (change made with this record); (2)
triage's default disposition for a workable idea is "into the planning
mol," not "into a worker." The balancing note: a clear small fix routes
straight to the work mol — recommendation is judgment, not a mandatory
planning detour.
