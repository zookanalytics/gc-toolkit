---
name: architecture-document
description: Use when you write, change or review a repository's architecture document, such as its docs/architecture.md, direct its text through a brief such as a rework's, or decide whether something belongs in one.
---

# The architecture document

A repository's architecture document states the architecture of the whole
repository in concise form. Its writers hold it to this standard line by line
and as a whole, and the arch check holds every change to the document to it,
both by judgment. A finding cites the part of the standard it rules from: a
heading below, or the bold lead of a rule.

A brief that directs the document's text, such as a rework's, is held to this
standard as the document's own lines are.

The sections are borrowed rather than invented: the
[arc42](https://arc42.org/overview) template, the first two levels of the
[C4 model](https://c4model.com/), and domain-driven design's
[bounded contexts](https://martinfowler.com/bliki/BoundedContext.html).

## What the document is

- **The whole repository.** The document is the architecture of the whole
  repository, not of the part a change reached first. Its title, description
  and mandate frame the whole, and a change that moves the structure of any
  part changes the document.
- **The architecture as desired.** The document describes the architecture as
  desired, grounded in what exists today: the design the built parts expect,
  including any part not built yet. Where the implementation has not caught
  up, the document still describes that design, not the system as it works
  around the gap, and Debt names the gap.
- **What a change owes the document.** A change that moves the architecture,
  a design included, changes the document by the smallest statement of what
  moved at the architecture's altitude: a domain added or removed, a
  responsibility a part takes on or gives up, what the system talks to or where
  its boundary lies, data a boundary must keep out, a cross-cutting rule, an
  architecture decision, or debt taken on or retired. A boundary is stated by
  the data it keeps out. How a part will carry out the move, including where or
  how it keeps a boundary's data out, stays in the design's record until the
  part is built.
- **The big picture first.** It opens on what the system is for and the
  domains it is made of, such as its schemas, before any one part's detail.
- **The architecture's altitude.** The document goes down to its parts and
  stops there: what a part is responsible for is the document's, and how the
  part carries it out is the part's own. A line states a fact at the level
  where it holds. A rule for a class of things is stated for the class, with a
  library or a component named only as an instance of it. A fact about one part
  names that part, and no part stands for the whole.
- **Facts, not explanation.** A decision is stated as a fact, and the line
  stops there. A reason appears only where a reader would otherwise get it
  wrong, in one short line.
- **Its own home.** The document itself states what the architecture needs,
  or links the living doc that owns the depth. A spec, such as a page under
  `specs/`, records one moment and is not reviewed when the code changes. So a
  spec is never the home of a fact the document needs, never one of its
  boundaries, and never where its reasoning lives.
- **Each element defends itself.** Every element the document names is a
  feature, whose entry says what it gives. Where what is built falls short of
  an element, the gap belongs under Debt.

## The scope

The document's `## Scope` is its charter. The mandate is the architecture of
the whole repository. Each boundary names a topic the document leaves out and
the living doc that holds it, such as how a part carries out its
responsibility, held in that part's own doc. No boundary names a spec.

## The skeleton

Below the scope come these sections, in this order, and every other line of
the document sits in one of them.

1. **Purpose and quality goals.** What the system is for, and its top three
   quality goals, ranked. A change is weighed against these goals, so each
   goal tells an acceptable outcome from an unacceptable one in a situation
   the system faces, with a short criterion or scenario where its name alone
   would not. A criterion states what the system already holds to, and the
   document invents no threshold and no policy. The ranking says which goal
   weighs more when a change gains on one at another's cost, and the weighing
   stays a judgment of how much each goal gains or loses. (arc42 sections 1
   and 10)
2. **Context.** What the system talks to, people and other systems, and where
   its boundary lies. (arc42 section 3, C4 level 1)
3. **Domains.** One entry per domain or major part, each filling the same
   slots: its responsibility in one line, the data it owns, and what it must
   not do. A domain is named for the data it models, and a stated
   responsibility shows when one part takes on another's job. The section
   also shows how the parts work together: which relies on which and for
   what, whose data each reads, and which writes commit together. A map of
   the domains, a line per collaboration, or a walk through one
   representative request can carry it, at the grain of the parts and never
   of the steps inside one. Product verticals, the areas of the product a
   user sees, are described apart from the domain entries, each naming the
   domains it draws on, because a vertical and a domain need not be the same
   thing. (arc42 section 5, C4 level 2, bounded contexts)
4. **Cross-cutting rules.** Rules every part follows, such as how the parts
   talk to each other. (arc42 section 8)
5. **Decisions.** Each architecture decision as a one-line fact, with a
   one-line reason only where a reader would otherwise get it wrong. A part's
   own choice is not one (The admission test). A decision's reasoning stays
   with the bead and commit that made it, so the document links nothing for
   it. (arc42 section 9)
6. **Debt.** Each place where what is built falls short of the architecture
   the sections above describe. An entry names the gap, why a reader must know
   it, and the work that retires it, such as the epic or bead that carries that
   work. A gap no reader needs to know stays out, and so does backlog: work the
   document does not describe as part of the architecture is tracked in beads,
   not in the document. (arc42 section 11)

A runtime or a deployment view is a section of its own, after Domains, only
when the system has that story, and a runtime view keeps only what shows one
part relying on another. Constraints, the solution strategy and a glossary fold
into the sections above.

## The admission test

A line belongs only if it shapes more than one part, or the system as a whole,
and a reader could not learn it from the code. Anything else goes in the code,
in that part's own doc, or nowhere. A component's behavior, a script's guards
and a suite's coverage are all learned from the code, so none of them passes.
The test reads each fact a line states, not the line as a whole: a fact it
admits does not carry in the clauses around it. A part not built yet is judged
as though it were, so what its code will show once it is built fails now, even
when a design states it as a requirement the part must meet. A fact passes
once, in the section that holds it: stated again in another section, it tells
a reader nothing the first statement did not.

A decision is held to the same test. How a part carries out a responsibility
the document gives it, such as the mechanism or the vendor feature it does the
job with, is that part's own choice. It stays the part's own when another
part's code calls it or another system keeps what it records, and it fails the
test even when its design weighed alternatives, reversing it would be costly,
or its reason is one the code cannot show. Its home is that part's own doc.
What the choice changes at the architecture's altitude stays, such as a
responsibility the part takes on or data a boundary must keep out.

## The sufficiency test

The admission test judges each line, and this test judges the document whole.
A maintainer new to the repository who reads only the document can:

- say what the system is for, and whom and what it serves;
- name the part that owns each kind of data, and what each part must not do;
- trace how the parts work together: which relies on which, whose data each
  reads, which writes commit together, and where trust changes hands, such as
  input the system cannot trust or data a boundary keeps out;
- take a representative change and weigh it against the quality goals: tell
  whether its outcome is acceptable, and which goal weighs more when it gains
  on one at another's cost.

A document that leaves its reader to assemble any of these from the code falls
short, however well each line passes. The test asks for no section, form or
length of its own, since the skeleton's sections carry each of these, and it
admits nothing the admission test refuses. A collaboration is stated as what
one part relies on another for, and how either part does its share stays
that part's own, as The admission test says of a part's own choice.

## Entry shape and budget

The admission test governs what a section says. Its form is whichever of a
table, a diagram or bullets carries the section's facts at the highest
bandwidth to the document's readers: the agents it directs, and a person who
scans it to see when a change moves the architecture.

- A table gives one row per entry and a column per slot. It is the natural
  form for Domains: one row per domain keeps each entry concise, and a change
  to the structure shows in a diff as a row added, removed or changed.
- A diagram is drawn at its section's grain, such as C4's system context
  diagram for Context, or a map of the domains and how they relate for
  Domains. A drawing at the code's grain, such as an entity-relationship
  diagram of tables and columns, restates the schema and fails the admission
  test.
- A bullet states one fact, under the section and the entry it is about.

Whatever the form:

- Every row of a table and every element of a diagram passes the admission
  test, as a bullet does.
- Domain entries fill the same fixed slots.
- Each section fits on one screen.
- Depth is linked, not copied.
