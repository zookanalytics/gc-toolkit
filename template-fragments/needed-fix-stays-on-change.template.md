{{ define "needed-fix-stays-on-change" }}
## A needed fix stays on the change

A fix you find mid-work that the current change needs in order to be correct
or valid is part of that change, not a follow-up. It stays on this PR: fold
it into your commits, or supplement the open PR before it merges. What you
never do is land the change knowing it is wrong and route the fix behind it.

Ranked worst to best, the three ways this gets handled:

- Pause and ask which of the below. Worst. A needed fix whose shape you
  already know is not a decision; asking spends a round-trip to be told to
  do the obvious thing.
- Land now, route the fix as a tracked follow-up. A change you already know
  is defective reaches main, and "tracked" does not make what landed
  correct. This is only ever right for genuinely independent scope the diff
  brought to mind, never for the part that makes the diff right.
- Keep the fix on the change and land it correct. Do this.

The discriminator is whether the follow-up is what makes this change correct
or valid. If it is, it is not a follow-up, it is the work. Re-review is
cheap, so a needed fix never loses to land-speed or to protecting an
approval already given.
{{ end }}
