---
name: The operator's ruling that a missing architecture document lands ahead (tk-ilh8rgh)
description: What the operator ruled on a missing architecture document, quoted from the record, and the route this change reads that ruling to admit, the review run sending the document to its repair pool at once while the change waits for it. Read it when you weigh the intake rule's admission of a fix sent ahead, or change the arch method's rule for a missing document.
---

# The ruling on a missing architecture document

## What the operator ruled

The operator's comment on gc-toolkit PR #1310 (discussion r4355436717) set the
arch method's rule for a missing document: "Absence of a docs/architecture.md
shoudl be a blocker and one shoudl be added, that then includes a passable
version for what's covered in the PR. And a follow-up should be created to
address the broader architecture lacking."

A sitting on a PR to the city's Gas City fork, whose arch review had asked that
PR to add the repository's architecture document, put the rule to the operator
again. On 2026-11-18 the operator ruled "Yes as recommended." on the sitting's
recommendation, which said, in the sitting's words:

- "Split the PR. The architecture document, its pointer and the docs-test
  exception become their own fork PR, describing main as it is today, on the
  polecat pool's usual PR workflow (mol-polecat-work). It merges first."
- "Rewrite the arch review's rule. Today it asks the PR under review to add a
  missing architecture document. It becomes: the document opens as its own PR,
  and the change waits for it, through the held toolkit bug filed when this
  PR's arch finding was ruled."

The held toolkit bug is this bead. The operator's own words in that sitting:
"This PR covers multiple areas. We can't have a PR that's expected to be pushed
for upstrema that also adds unrelated documentation." and "I thought the
guidance was to open a new pr to address when missing, not add in the PR first
found." The sitting recorded the ruling on that PR's bead, and this bead's
notes carry it with its source.

From the first comment, the rest stands: a missing document is still a
blocker, the document still holds a passable account of the part the change
covers, and the rest of the architecture is still a follow-up.

## The route this change reads the ruling to admit

This section is the change's reading of the ruling, which the operator approves
or rejects at its PR. It is not the operator's words.

The intake rule holds new work for placement unless it admits the work's route
([steering.md](../../docs/steering.md#the-intake-rule)). The ruling sent the
fork's document to the polecat pool at once, on mol-polecat-work, and it asks
that the document open as its own PR when a change finds it missing. A document
held for placement would hold the change behind a placement sitting as well, so
this change reads the ruling as admitting one route: the review run slings the
document's bead to its repair pool at once (`gctk review ahead`), and the
change waits for it. The intake rule names that route.

The reading reaches the architecture document alone. A fix of another kind that
a lane's rule lands ahead of a PR needs a route the intake rule admits on a
ruling of its own.

The route overrides no hold and no wait. A found bead of the document's title
that a hold label holds, such as the `hold:mayor` of work waiting for
placement, is sent nowhere, because a sling reads no hold, and the change waits
on it while the hold stands. One that a wait holds, such as a prerequisite or a
person's gate, is armed for the repair pool instead, because a sling reads no
wait either, and the deferred-dispatch order sends it once nothing holds it.
