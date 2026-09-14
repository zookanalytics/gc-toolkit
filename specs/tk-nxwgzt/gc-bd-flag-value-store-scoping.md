---
name: gc bd flag-value store scoping
description: Why `gc bd list` silently answers from the wrong store for a spaced id-shaped flag value, where the durable fix lives, and what the gc-toolkit pack ships for it.
---

## Scope

The bug tk-nxwgzt reports, the reasoning that placed the durable fix upstream,
and the record of what this bead delivers on the pack side. The present-tense
statement of the resulting rule lives in
[`docs/bead-store-resolution.md`](../../docs/bead-store-resolution.md); this
file is the investigation behind it.

## What was reported

`gc bd list` chooses the store by sniffing a bead id out of its arguments, and
the flag-value spelling decides the answer. Both failures are a silent empty
array at exit 0, indistinguishable from a genuine miss:

    gc bd list --assignee lx-...   -> []            (space form, wrong store)
    gc bd list --assignee=lx-...   -> [tk-...]       (equals form, correct)

    gc bd list --id gc-... --all   -> [gc-...]       (space form, resolves foreign)
    gc bd list --id=gc-... --all   -> []            (equals form, answers locally)

The two forms fail in opposite directions, so there is no single safe habit: a
value flag needs `--flag=value`, while `--id` needs the spaced form or the
wrapper never sees the foreign prefix.

## Confirmed live 2026-09-14

Reproduced from this rig against the running binary, both directions:

- `gc bd list --assignee <this session id> --json` returned `[]` while
  `--assignee=<same id>` returned the step bead the session held.
- `gc bd list --id <foreign gc- id> --json` resolved the foreign bead while
  `--id=<same id>` returned `[]`.

The original report measured it on 2026-09-03; the eleven-day gap and an
intervening gascity release did not change the behavior.

## Mechanism

The scope selector is `resolveBdScopeTarget` in the gc binary
(`rigs/gascity/cmd/gc/cmd_bd.go:857`). Two loops walk the command's arguments,
skip every element beginning with `-`, and retarget the whole command to the
store owning the first bare element that resolves as a bead — the city-prefix
loop at `:883-891`, then the rig-prefix loop at `:897-910`. A flag's value is
its own argument, so `--assignee <v>` exposes `<v>` to the walk and
`--assignee=<v>` hides it behind the leading `-`. `--id` inverts because its
whole purpose is to name a bead that may live in another store: the spaced
value is the only form the walk can see and route on.

The existence check the loops apply to each candidate is `bdBeadExists`
(`cmd/gc/cmd_bd.go:138-145`), a bare `store.Get` that returns true for any
resolvable id, with no class discrimination. The loop comment at `:893-895`
says this check keeps hyphenated flag values and other non-ID args from
retargeting the command; it cannot, because a session id *is* a bead —
`issue_type: session`, one per live session in the city store, and its id is
exactly the assignee `gc hook --claim` stamps. So the one assignee value a pool
worker would ever query, its own session id, is the value that defeats the
check.

## Where the durable fix lives

The parser is in the `gc` binary, whose source is the **gascity** rig
(`github.com/zookanalytics/gascity`). This pack has no `go.mod` and cannot
change the binary, and a gc-toolkit polecat cannot push to gascity.

The binary-side fix is filed upstream as **gc-rwa68** (gascity, open as of
2026-09-14). It carries the reproduction, the mechanism at symbol and line, the
root cause, why the failure is silent to a `--json` consumer that never reads
stderr, and two fix options: skip the values of known value-taking flags before
the prefix-detect loops, or reject a candidate whose `issue_type` is `session`
in the scope probe. It also suggests carrying the resolved scope in the
`--json` payload so a consumer that never sees the stderr banner can still tell
which store answered. tk-nxwgzt carries `gc.filed_as = gc-rwa68`.

## What the pack ships

The gc-toolkit pack's own callers are already safe. Every `gc bd list`/`bd
ready` query keyed on an assignee uses the `--assignee=` equals form
(the polecat and refinery formulas, `boot-health.sh`, the keeper prompt, the
`bead-store.sh` resolver, which reads only positional ids). An audit on
2026-09-14 found no spaced id-shaped value flag and no `--id=` in executable
pack code, so there is no live call site to repair.

The rule that keeps them safe is guidance, not a lint invariant, so it is not a
`tools/lint-learned.d` detector. The detector directory's admission test asks
whether the flagged shape is ever correct: `gc bd update <bead> --assignee
<named-session>` spaced is correct and canonical (a session name is not
id-shaped), and `--id=<local-id>` is correct for a same-store id. The bug bites
only when the value is id-shaped *and* names another store, which a static
scan cannot tell from a variable. A detector for it would produce judgment-call
findings, which is what the admission test rejects.

So the pack-side deliverable is the present-tense rule stated in
`docs/bead-store-resolution.md`, in the doc that already owns "given an id,
which store answers for it, and what its silence means". When gc-rwa68 lands,
the commit that fixes the binary is what updates that doc.

## Disposition

tk-nxwgzt hands off to the refinery with this spec and the doc change. The
symptom is tracked to its durable fix at gc-rwa68; nothing further is owed on
the pack side until that lands.
