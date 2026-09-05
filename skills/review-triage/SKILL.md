---
name: review-triage
description: The method for the triage gate — a broad, cheap scan that does not judge a change but decides which dedicated reviews it needs, then records that decision by widening the anchor's check_set from the charter's declared gate menu. Use when you hold a review bead whose check_name is triage, or when asked which review gates a diff warrants. Covers the menu contract, the monotonic-widen rule, per-gate justification, waivers, and the expected common case of adding nothing.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Review triage

You are classifying, not judging. Whether the change is correct is the
`codex` gate's question and it is already dispatched. Yours is narrower:
**which dedicated reviews does this diff warrant?** The usual honest answer
is none.

## Inputs — three, in this order

1. **The charter** — `docs/review-charter.md` at the commit under review. It
   carries the layer map, the admission test, and the gate menu you classify
   over. Read it first; it is the only place the menu is declared.
2. **The review bead** — `check_name`, `anchor_bead`, `review_branch` /
   `review_base` or `pr_number`, and the dispatch-pinned `reviewed_oid`. The
   anchor states what the change was for.
3. **The diff, at the pinned commit** — `git diff --stat` first, then a skim
   of the files the stat names. A skim is the method here; reading every
   hunk is the dedicated reviewer's job, not yours.

## The menu contract

The charter's gate menu is closed. You may add any gate it declares and you
may not invent one. Parse it rather than eyeballing it. The parser and the
charter come from different places and must be resolved separately: the parser
is a pack script, the charter is the reviewed repo's own. A pack rung on the
charter ladder would classify this rig against gc-toolkit's menu. The charter
comes out of the dispatch-pinned commit, `$REVIEWED_OID` from input 2, and not
off disk. The tree you stand in is your own worktree rather than the commit you
are classifying, and a branch may change the menu it is judged against:

```bash
PARSER=""
for c in "${GC_PACK_DIR:-}" "${GC_RIG_ROOT:-}"; do
  [ -n "$c" ] && [ -x "$c/assets/scripts/review-charter.sh" ] && { PARSER="$c/assets/scripts/review-charter.sh"; break; }
done
CHARTER=$(mktemp); FOUND=""
for c in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do
  [ -n "$c" ] || continue
  git -C "$c" show "$REVIEWED_OID:docs/review-charter.md" >"$CHARTER" 2>/dev/null && { FOUND=1; break; }
done
[ -n "$FOUND" ] && [ -n "$PARSER" ] && "$PARSER" --file "$CHARTER"
```

A commit that carries no charter is the no-charter case below, not a reason to
reach for the pack's copy or for the tree you happen to be in. `signoff.sh`
resolves it the same way, so a waiver it cannot warrant from the reviewed
commit's own menu is refused at the verdict.

Each row gives you the gate, when it applies, its method, the paths that make
it mandatory, and whether it may be waived.

## Deciding

For each row, ask the applies-when column against the diff you skimmed. Add
the gate when the answer is yes. Two rules bound the judgment:

- **A mandatory path is not a judgment call.** When the diff touches a path
  the row declares mandatory, the gate is added — the applies-when column does
  not get a vote. Nothing re-derives the diff behind you, so a miss here is a
  gate the anchor never gets.
- **Adding nothing is the expected common case.** A one-file fix inside one
  component, a test addition, a doc correction, a formula-poured mechanical
  change — none of these earn a dedicated review. Gate inflation costs a
  cadence hop and a session per anchor, and the feedback distiller watches
  the add-rate for exactly that drift.

When the repo has no readable charter, add `arch` if the diff creates a file,
crosses a top-level directory, or changes a public interface — then file the
charter gap as an observation (below).

## Recording the decision

One `signoff.sh` call carries the verdict and the widening together. The
verdict is `approve`: triage passed at this commit, which is what makes
`check.triage` green and lets the rest of the cadence proceed.

```bash
signoff.sh --review-bead "$REVIEW_BEAD" --verdict approve \
  --add-gates arch \
  --justification "diff rewrites lifecycle.sh's transition write (charter: single writer)"
```

- **Widening is monotonic and `signoff.sh` enforces it.** The write is a
  set union with read-back: nothing you pass can remove a gate already
  declared, and no dispatcher, formula or other reviewer may pre-set or
  shrink `check_set`. The checks-needed decision lives here, in one place a
  human can audit.
- **Every added gate carries a one-line justification**, appended to the
  anchor's notes as a `triage-add:` line. Say which charter row fired and
  what in the diff fired it. "Looked risky" is not a justification.
- **Adding nothing needs no flag** — approve on its own is the full verdict.

## Waivers

A waiver is the only sanctioned narrowing, and only for a gate the charter
marks waivable:

```bash
signoff.sh --review-bead "$REVIEW_BEAD" --verdict approve \
  --waive-gates demo --justification "docs-only; nothing the operator watches happen changed"
```

`signoff.sh` refuses a waiver for a gate the charter does not mark waivable,
and refuses every waiver when no charter is readable. Waivers are expected to
be rare; the distiller watches their rate beside the add-rate.

## The charter gap

A charter that is missing, or that describes a structure the repo no longer
has, is your first finding — file it as an observation and carry on with the
fallback above. Filing is recording, not proposing: the distiller judges it
and a reviewed PR writes the charter.

```bash
OBS=$(gc bd create "obs: review charter is missing or stale for <repo> (bead:$ANCHOR)" \
  -t task -l learning -l observation -d "## Statement
<what a reviewer could not hold the diff against>

## Quote
Triage on $ANCHOR at $REVIEWED_OID.

## Proposed norm
<draft — explicitly non-binding>" --json | jq -r '.id // .[0].id')
gc bd update "$OBS" --set-metadata task_kind=observation \
  --set-metadata obs.category=charter-gap \
  --set-metadata "obs.scope=repo:${GC_RIG:-unknown}" \
  --set-metadata obs.source=self --set-metadata obs.directive=standing \
  --set-metadata "obs.provenance=bead:$ANCHOR:turn:$(date -u +%Y-%m-%d)" \
  --set-metadata gc.outcome=recorded --status=closed
```

## What triage never does

- It never judges correctness, and it never files findings about the code.
  A defect you notice while skimming belongs in the `codex` review, not
  here; say so in the verdict body and let that gate hold it.
- It never fixes anything, and it never touches the anchor other than
  through `signoff.sh`.
- It never re-runs because the branch grew. Its verdict binds no marker to a
  commit: an appended commit does not re-stale `check.triage`, and no pass
  re-classifies the grown diff. Only a rewrite that takes the reviewed commit
  off the branch supersedes the review, and gate-ensure then pours a fresh
  triage at the live head.
