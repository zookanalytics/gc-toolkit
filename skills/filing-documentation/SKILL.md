---
name: filing-documentation
description: Use when you are about to write or file a durable document — an analysis, decision record, research synthesis, spec, or design note. Fires before you create the file so it lands in the right place (central docs/ vs local specs/<bead-id>/), gets committed to the repo, and is never left as a bead comment. Applies to any agent producing a durable written artifact.
---

# Filing Documentation

A decision procedure for *where* a durable document goes, applied at the
moment you write it. The full conventions — the two tiers, bead-keyed
naming, the no-archiving rule, frontmatter — live in the gc-toolkit
pack's `docs/file-structure.md` (at the repo root, not under this skill
directory), which is the authority. This skill applies those rules at
write-time; it is not a second copy of them.

## 1. Is this a committed file at all?

A durable analysis, decision record, research synthesis, or spec is a
**repo artifact** — commit it. Ephemeral status, or a note that only
coordinates the task while it is in flight, can stay a bead comment.

The line that matters: **a durable document must never live only as a
bead comment.** Bead comments are operational state, not the record. If
someone would want to read it after the bead closes, it is a file.

## 2. Which tier?

- Authoritative — **what's true now**, that someone owns keeping current
  → `docs/<topic>.md`.
- A record of work — **what was thought, decided, or explored** on a bead
  → `specs/<bead-id>/`.

Unsure? Ask which claim the document makes. *What is true* is central;
*what was considered while doing this bead* is local. The gc-toolkit
pack's `docs/file-structure.md` carries the tier rules in full, including
the bead-ID-alone directory naming.

## 3. Commit it

Write the file on your work branch and commit it with the rest of your
work. That commit is what makes it durable and reviewable — the point of
step 1.

For anything past this procedure — directory naming, frontmatter,
timestamps, cross-doc references, the no-archiving rule — read the
gc-toolkit pack's `docs/file-structure.md` (at the repo root).
