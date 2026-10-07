---
name: review-triage
description: The method for the triage check — a broad, cheap scan that does not judge a change but decides which specialist checks it needs, then records that decision by widening the anchor's check_set from the check index's declared checks. Use when you hold a review bead whose check_name is triage, or when asked which review checks a diff warrants. Covers the index contract, the monotonic-widen rule, and the expected common case of adding nothing.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Review triage

You are classifying, not judging. Whether the change is correct is the
`correctness` check's question and it is already dispatched. Yours is narrower:
**which specialist checks does this diff warrant?** The usual honest answer is
none.

## Inputs — three, in this order

1. **The check index** — `review-checks.toml` at the commit under review. It
   declares the checks you may add. Read it first; it is the one place the
   available checks are declared.
2. **The review bead** — `check_name`, `anchor_bead`, `review_branch` /
   `review_base` or `pr_number`, and the dispatch-pinned `reviewed_oid`. The
   anchor states what the change was for.
3. **The diff, at the pinned commit** — `git diff --stat` first, then a skim of
   the files the stat names. A skim is the method here; reading every hunk is
   the specialist reviewer's job, not yours.

## The index contract

The check index is closed: you may add any check it declares and you may not
invent one. Parse it rather than eyeballing it. The parser and the index come
from different places and must be resolved separately: the parser is a pack
script, the index is the reviewed repo's own. A pack rung on the index ladder
would classify this rig against gc-toolkit's checks. The index comes out of the
dispatch-pinned commit, `$REVIEWED_OID` from input 2, not off disk — the tree
you stand in is your own worktree, not the commit you are classifying, and a
branch may change the index it is judged against:

```bash
PARSER=""
for c in "${GC_PACK_DIR:-}" "${GC_RIG_ROOT:-}"; do
  [ -n "$c" ] && [ -x "$c/assets/scripts/review-checks.sh" ] && { PARSER="$c/assets/scripts/review-checks.sh"; break; }
done
INDEX=$(mktemp); FOUND=""
for c in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do
  [ -n "$c" ] || continue
  git -C "$c" show "$REVIEWED_OID:review-checks.toml" >"$INDEX" 2>/dev/null && { FOUND=1; break; }
done
[ -n "$FOUND" ] && [ -n "$PARSER" ] && "$PARSER" --file "$INDEX"
```

Each row gives you the check, its method, one line of purpose, and its phase —
the stage transition by which it must read green. When a check applies is a
judgment its method states, so read the method; the phase is fixed per check and
not triage's to choose, and there is no applies-when column in the index.

A commit that carries no index is the no-index case below, not a reason to reach
for the pack's copy or the tree you happen to be in. `signoff.sh` resolves it the
same way: it validates `--add-gates` against the reviewed commit's own index, and
widens nothing when that commit carries none — the added checks are dropped and
correctness carries the change.

## Deciding

For each check the index declares, read its method and ask whether the diff you
skimmed warrants it. Add the check when the answer is yes. Two rules bound the
judgment:

- **A check's method may name paths that make it mandatory.** When the diff
  touches such a path, the check is added whatever the rest of the method would
  argue. Nothing re-derives the diff behind you, so a miss here is a check the
  anchor never gets.
- **Adding nothing is the expected common case.** A one-file fix inside one
  component, a test addition, a doc correction, a formula-poured mechanical
  change — none earns a specialist review. Widening costs a cadence hop and a
  session per anchor, and the feedback distiller watches the add-rate for exactly
  that drift.

When the repo has no readable index, there is no menu to classify over: widen
nothing, let the standing `correctness` review carry the change, and file the
index gap as an observation (below).

## Recording the decision

One `signoff.sh` call carries the verdict and the widening together. The verdict
is `approve`: triage passed at this commit, which is what makes `check.triage`
green and lets the rest of the cadence proceed.

```bash
signoff.sh --review-bead "$REVIEW_BEAD" --verdict approve \
  --add-gates demo
```

- **Widening is monotonic and `signoff.sh` enforces it.** The write is a set
  union with read-back: nothing you pass can remove a check already declared,
  and no dispatcher, formula, or other reviewer may pre-set or shrink
  `check_set`. The checks-needed decision lives here, in one place a human can
  audit.
- **Every added check is recorded** on the anchor's notes as a `triage-add:`
  line, so the add-rate the distiller watches stays countable. Name the check
  you added and what in the diff warranted it, in your verdict body.
- **Adding nothing needs no flag** — approve on its own is the full verdict.

## The index gap

An index that is missing, or that describes checks the repo no longer has, is
your first finding — file it as an observation and carry on with the fallback
above. Filing is recording, not proposing: the distiller judges it and a
reviewed PR writes the index.

```bash
OBS=$(gc bd create "obs: check index is missing or stale for <repo> (bead:$ANCHOR)" \
  -t task -l learning -l observation -d "## Statement
<what a reviewer could not classify the diff against>

## Quote
Triage on $ANCHOR at $REVIEWED_OID.

## Proposed norm
<draft — explicitly non-binding>" --json | jq -r '.id // .[0].id')
gc bd update "$OBS" --set-metadata task_kind=observation \
  --set-metadata obs.category=review-index-gap \
  --set-metadata "obs.scope=repo:${GC_RIG:-unknown}" \
  --set-metadata obs.source=self --set-metadata obs.directive=standing \
  --set-metadata "obs.provenance=bead:$ANCHOR:turn:$(date -u +%Y-%m-%d)" \
  --set-metadata gc.outcome=recorded --status=closed
```

## What triage never does

- It never judges correctness, and it never files findings about the code. A
  defect you notice while skimming belongs in the `correctness` review, not here;
  say so in the verdict body and let that check hold it.
- It never fixes anything, and it never touches the anchor other than through
  `signoff.sh`.
- It never re-runs because the branch grew. Its verdict binds no marker to a
  commit: an appended commit does not re-stale `check.triage`, and no pass
  re-classifies the grown diff. Only a rewrite that takes the reviewed commit off
  the branch supersedes the review, and gate-ensure then pours a fresh triage at
  the live head.
