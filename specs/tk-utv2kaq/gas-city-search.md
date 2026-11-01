---
name: Gas City search for carrying out a ruling that gated work will not go on
description: Use when you are judging whether stand-down.sh, bead-rehome.sh's --check under --except-key, or the reconcile pass's re-read of an arm should give way to something Gas City or bd ships, or when one of the triggers at its end may have fired.
---

# Gas City search for carrying out a ruling that gated work will not go on

This change adds `assets/scripts/stand-down.sh`, grows `bead-rehome.sh --check`
with a mode that reads what would hold the close when it is given `--except-key`,
and has the deferred-dispatch reconcile pass read an arm again before it slings.
So the arch check asks what Gas City and bd already ship for each need
([review-arch.md](../../docs/review-arch.md#the-checks), checks 1 and 2).

Nothing upstream ends a human gate with a "no". A gate closes one way, any close
releases what it blocks, and the arm that would send the work is the pack's own. So
stand-down.sh composes bd's and Gas City's calls and the pack's writers in the one
order that works, and keeps no state. It adds no metadata key, bead kind or
lifecycle state, so it is glue with no pack noun and needs no warrant.

## Where the search looked

All three were read on 2026-11-01, UTC:

- Gas City at `gastownhall/gascity` 688b5c4e0acd: `docs/`, `engdocs/`, the core
  pack under `internal/bootstrap/packs/core`, and the Go source.
- bd at `gastownhall/beads` 6ebaacba8f5f.
- `gastownhall/gascity-packs` at 0b0d96250f66, every pack directory.

## What each need found

**Answering a gate.** `bd gate resolve <gate-id> --reason` (package `main`,
`gateResolveCmd`) says it is "equivalent to 'bd close <gate-id>' but with a more
explicit name", and the reason is free text. Core's
`notify-on-human-gate-creation` order tells the addressee the same thing, "Resolve
with: gc bd gate resolve". This covers the answer, and stand-down.sh calls it. It
does not cover the "no": a `blocks` edge clears on any close, so the bead a gate
blocks becomes ready whatever the reason says.

**A "no" for one of the beads a gate holds.** `gateResolveCmd` takes a gate and a
reason and closes the gate, so it has no form that answers for one blocked bead. `bd
dep remove` (package `main`, `depRemoveCmd`) takes one bead off one blocker, and
stand-down.sh calls it for a gate that also holds another open bead, after the arm
and the route are gone. Run alone it is a release like any other, so the order is
the part the script holds. It adds no flag: `--successor` already names evidence
other than the gate, and a gate that stays open needs exactly that.

**An edge that holds after a "no".** bd's `conditional-blocks` (package `types`,
`DepConditionalBlocks`, "B runs only if A fails") reads the close reason for
failure words (`FailureCloseKeywords`). It releases on a failure, which is the
opposite sense: this wait releases on a person's "go on". Answering "go on" with
a failure word to suit it would invert the gate for every reader of the reason, and
it would leave the arm's sling alone anyway. `waits-for` is a fan-out gate over
dynamic children and does not apply.

**Closing a bead a gate blocks.** `bd close --force` (package `main`, `closeCmd`)
gets past the refusal, and Gas Town's `mol-witness-patrol` uses `gc bd close --force`
for an orphan whose branch is already on main. The same flag waives bd's refusal
of a bead with open children (the warning in `closeCmd`) and of a bead assigned to
someone else, and it leaves the gate open and owed. The patrol's own text calls the
flag "what makes this destructive against a *live* agent". The pack's close that is
not a landing goes through `bead-rehome.sh`, which deliberately does not pass it, so
this composes the answer first and leaves the close unforced.

**Closing with a pointer.** `bd supersede <id> --with <new>` and
`bd duplicate <id> --of <canonical>` (package `main`, `runSupersede`,
`runDuplicate`) close a bead with a reference to its replacement. A ruling that
work will not go on has no replacement. `bead-rehome.sh` stays the writer here, and
this change does not touch that choice.

**Stopping the run.** Gas City's run cancel, `POST /runs/{run_id}/cancel` (package
`api`, `humaHandleRunCancel`), ends a run. The pack already reaches it through
`run-cancel.sh` and `gc-helm.sh takeaway --release`, and stand-down.sh calls the
latter.

**Withdrawing a pending dispatch.** `gc sling`'s flags on the
[CLI page](https://docs.gascity.com/reference/cli#gc-sling) name no dispatch that
waits for a bead to be ready, and the Go source at that commit has no such option
(no `DispatchWhenReady`, `SlingWhenReady` or `OnUnblock`). Because the arm is the
pack's, so is its removal, and `deferred-dispatch.sh disarm` already writes it.

**A check before the pass's sling.** `gc beads metadata-cas`
([CLI page](https://docs.gascity.com/reference/cli#gc-beads-metadata-cas)) compares
and sets one key, atomically. The pass stamps one key, its marker, on the strength
of another, the arm, so a single-key compare does not express it. It does not need
to: the stand-down disarms before it answers. A pass reaches its sling only after
reading the gate closed, the disarm landed before that close, and the re-read comes
after that read, so the re-read always finds the disarm. The wider re-read, of a
bead's blockers, is tk-dgb8fqb's.

**What the packs do.** No pack runs `bd gate create`, so none has a human gate's
"no" to carry out. "Stand down" appears in no pack. "Abandon" appears in bmad,
compound-engineering and gstack as prose about something else, in the slack packs
about connections and turn records, and once in `gascity`'s `wait-for-drain` as a
manifest row's outcome; none is about a gate. Gas Town's `mol-polecat-work` hands a
bead it stopped to a person with "and re-sling", so it has no pending dispatch to
withdraw.

## When this answer changes

- bd or Gas City ships an answer to a human gate that leaves the beads it blocks
  held, or an edge that releases only on such an answer. stand-down.sh's step 3 and
  step 4 then become that one call.
- Gas City ships a dispatch that waits for a bead to be ready. The arm goes, with
  stand-down.sh's step 1 and the pass's re-read, and the rest stays.
