---
name: Gas City search for reading a failed rig fetch (tk-r8e3dub)
description: The Gas City surfaces searched before doctor/check-pour-text-current began reading an empty FETCH_HEAD as a failed fetch. Read it when judging whether a rig whose fetch keeps failing should reach a person through Gas City's order checks instead, or when a Gas City release starts reading an order's partial runs or a checkout's fetch.
---

# Gas City search for reading a failed rig fetch

The change grows `doctor/check-pour-text-current` (I9). Its UNFETCHED finding
now also fires when the checkout's last `git fetch` left `.git/FETCH_HEAD`
empty, not only when nothing has fetched there past the threshold. The check's
first line names an UNFETCHED checkout instead of calling the pack current. The
change adds no script, order, metadata key, bead kind or lifecycle state, and
`assets/scripts/reconcile-rig-checkouts.sh` changes only its header. Gas City is
read at upstream main `572f981c61` (`gastownhall/gascity`, 2026-11-23).

## What the change needs

A rig whose fetch keeps failing has to reach a person through a surface that
already exists, while a single failed pass, such as a network blip, does not.
`reconcile-rig-checkouts.sh` skips such a rig, as the ruling it was built on
keeps, and its run still exits 0. A failed fetch exits 128 and leaves
FETCH_HEAD at 0 bytes with a fresh mtime. The check dated a fetch by that
mtime alone, so it read the failed fetch as fresh. The remote-tracking ref did
not move either, so the behind-count read 0, and the check printed OK.

## What was searched

| Primitive | What it gives | Why it does not cover the need |
|---|---|---|
| `order-outcome-healthy` (`consecutiveOrderFailures` and `orderOutcomeFailureThreshold` in `internal/doctor/checks_order_outcome.go`) | Flags an order once its last three runs recorded `order.failed`, so a network transient does not trip it. An exec order that exits non-zero records `order.failed` with the tail of its output (`dispatchExec` in `cmd/gc/order_dispatch.go`) | It reads an order's runs, and the reconcile's run exits 0, so it never fires. To use it, the pass would exit non-zero whenever one rig's fetch failed. That would mark as failed a run that advanced every other rig and escalated what it could not do, and it would put a second board row for the same stall beside the I9 check's row |
| The exec order outcome file, `GC_ORDER_OUTCOME_FILE` (`ExecOutcomeFileEnv` and `ExecOutcomePartial` in `internal/orders/exec_outcome.go`, `recordOrderOutcome` in `cmd/gc/order_outcome.go`) | A run that exits 0 declares itself `partial`, naming each scope that did not run and why, and Gas City records an `order.skipped` event | It fits a pass that could not fetch one rig, but nothing reads `order.skipped` to raise it. `order-outcome-healthy` reads only `order.completed`, `order.failed` and `controller.started`, and no other check names the event. Declared alone, it reaches nobody |
| A Gas City doctor check on a rig checkout's fetch or currency | None. No check under `internal/doctor/` runs `git fetch` or `git rev-list` or reads a remote-tracking ref, and `FETCH_HEAD` appears in no Go file but one test (`examples/routing_namespace_test.go`) | Gas City does not judge whether a checkout it runs a pack from is current |

## What the change composes

The stall is the checkout's state, which git records in FETCH_HEAD. The I9
check already reads that file, and its findings already reach the operator.
The doctor order records the check's result every hour (`gctk doctor run`,
`orders/doctor-run.toml`). The helm board's city page shows a check that two
runs in a row found failing (`services/helm/README.md`, "The city page"). A
blip clears at the next reconcile pass, so at most one doctor run sees it and
the page does not show it. A fetch that keeps failing shows after the second
run. A fetch caught while it runs reads as failed for the seconds it takes, and
the same two-run rule absorbs it.

The deacon's doctor sweep, which the deletion plan retires
(`tools/deletion-plan.tsv`), files a check it finds failing as a finding for a
first reaction. While it runs, a blip that one sweep happens to catch reaches
that agent, as any other check's transient does.

## Measured

At load-context, on git 2.56.1, a good fetch left FETCH_HEAD at 222 bytes. A
failed fetch exited 128 and left 0 bytes, and a fetch still running read 0
bytes until it ended. A fetch in a linked worktree wrote only that worktree's
FETCH_HEAD and left the main checkout's file alone. The bead's own runs saw the
same empty file on git 2.56.0 and on Apple's git 2.54.0. Every live rig root's
FETCH_HEAD was 204 to 34858 bytes, so the change raises nothing on landing.
