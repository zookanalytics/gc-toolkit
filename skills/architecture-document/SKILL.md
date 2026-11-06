---
name: architecture-document
description: Use when you write, change or review a repository's architecture document, such as its docs/architecture.md, or decide whether something belongs in one.
---

# The architecture document

A repository's architecture document states the architecture of the whole
repository in concise form. Its writers hold every line to this standard, and
the arch check holds every change to the document to it, both by judgment. A
finding cites the part of the standard it rules from: a heading below, or the
bold lead of a rule.

The sections are borrowed rather than invented: the
[arc42](https://arc42.org/overview) template, the first two levels of the
[C4 model](https://c4model.com/), domain-driven design's
[bounded contexts](https://martinfowler.com/bliki/BoundedContext.html), and
[architecture decision records](https://adr.github.io/).

## What the document is

- **The whole repository.** The document is the architecture of the whole
  repository, not of the part a change reached first. Its title, description
  and mandate frame the whole, and a change that moves the structure of any
  part changes the document.
- **The big picture first.** It opens on what the system is for and the
  domains it is made of, such as its schemas, before any one part's detail.
- **The architecture's altitude.** A line states a fact at the level where it
  holds. A rule for a class of things is stated for the class, with a library
  or a component named only as an instance of it. A fact about one part names
  that part, and no part stands for the whole.
- **Facts, not explanation.** A decision is stated as a fact, and the line
  stops there. A reason appears only where a reader would otherwise get it
  wrong, in one short line.
- **Its own home.** The document itself states what the architecture needs,
  or links the living doc that owns the depth. A spec, such as a page under
  `specs/`, records one moment and is not reviewed when the code changes. So a
  spec is never the home of a fact the document needs, never one of its
  boundaries, and never where its reasoning lives.
- **Each element defends itself.** Every element the document names is a
  feature, whose entry says what it gives, or debt, named with what retires
  it.

## The scope

The document's `## Scope` is its charter. The mandate is the architecture of
the whole repository. Each boundary names a topic the document leaves out and
the living doc that holds it, such as the reasoning behind each decision, held
in its decision record. No boundary names a spec.

## The skeleton

Below the scope come these sections, in this order, and every other line of
the document sits in one of them.

1. **Purpose and quality goals.** What the system is for, and its top three
   quality goals, ranked. A change is weighed against these goals. (arc42
   sections 1 and 10)
2. **Context.** What the system talks to, people and other systems, and where
   its boundary lies. (arc42 section 3, C4 level 1)
3. **Domains.** One entry per domain or major part, each filling the same
   slots: its responsibility in one line, the data it owns, and what it must
   not do. A domain is named for the data it models, and a stated
   responsibility shows when one part takes on another's job. Product
   verticals, the areas of the product a user sees, are described apart from
   the domain entries, each naming the domains it draws on, because a vertical
   and a domain need not be the same thing. (arc42 section 5, C4 level 2,
   bounded contexts)
4. **Cross-cutting rules.** Rules every part follows, such as how the parts
   talk to each other. (arc42 section 8)
5. **Decisions.** Each decision as a one-line fact, with a one-line reason
   only where a reader would otherwise get it wrong, and a link to its
   decision record when it has one, never to a spec. (arc42 section 9,
   decision records)
6. **Debt.** Each compromise, named, with what retires it. (arc42 section 11)

A runtime or a deployment view is a section of its own, after Domains, only
when the system has that story. Constraints, the solution strategy and a glossary fold into
the sections above.

## The admission test

A line belongs only if it shapes more than one part or would be costly to
reverse, and a reader could not learn it from the code. Anything else goes in
the code, in that part's own doc, or nowhere. A component's behavior, a
script's guards and a suite's coverage are all learned from the code, so none
of them passes.

## Entry shape and budget

- Each entry is one bullet stating one fact, under the section and the entry
  it is about.
- Domain entries fill the same fixed slots.
- Each section fits on one screen.
- Depth is linked, not copied.
