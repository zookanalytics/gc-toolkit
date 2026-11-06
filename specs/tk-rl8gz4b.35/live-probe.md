---
name: Live probe of the check that the po receives only its queue
description: Use when checking what doctor/check-po-queue-only reports on a real store, such as a run poured to the po with gc sling --on, mail to it, an assignment, or a held bead that is not new work or that something already sends, and what clears each.
---

# Live probe of the check that the po receives only its queue

Unit 4 of the native-hold effort (tk-rl8gz4b.35) builds `doctor/check-po-queue-only`.
Its done-when asks for a run poured to the seat with `gc sling --on`, a read that the
check names the run's steps, and then a cancel of the run, where this branch's pack is
loaded. This is that record. The live city runs main's pack, which has no po yet, so
the probe ran in a scratch city.

## Where it ran

A scratch city, `pq4`, made with `gc init --template minimal --no-start` and run by
its own supervisor (`gc supervisor run` with its own `GC_HOME` and API port). Its
`pack.toml` imported this branch's worktree as `gc-toolkit` at city level, at
05b9905ee. Its `city.toml` set `[agent_defaults] default_sling_formula =
"mol-polecat-work"` and `formula_v2 = true`, suspended mechanik, the deacon, the dog,
the po and `core.control-dispatcher`, and skipped every order. A sling to a suspended
agent pours its run and only warns, so no session ever started, and the probe spent no
model turns. The installed gc was 1.4.3 (`e03752646`). It ran on 2026-11-06 from
09:36Z to 09:40Z, and each reading below is `gc doctor --check
gc-toolkit:check-po-queue-only`.

## Results

| Step | Result |
|---|---|
| The city before anything reached the po | OK: one po seat read and an empty queue. |
| `gc sling gc-toolkit.po <bead> --on mol-polecat-work` | The run poured as in unit 3's probe: its root and six steps carried `gc.routed_to=gc-toolkit.po`, its two control steps went to `core.control-dispatcher`, and the work bead took `gc.execution_routed_to=gc-toolkit.po`. The check reported one error naming the run's root and each of the six steps by its step ref, with `run-cancel.sh --root <root>` as the remedy. |
| `gc mail send gc-toolkit.po`, sent with no session identity | Named as unread mail from `human`, with the note that `human` is any caller with no session identity. |
| `gc bd update <bead> --assignee gc-toolkit.po` | Named as a bead assigned to the po. |
| Held beads: one carrying `anchor_bead`, one carrying `merge_result=merged`, one armed, one assigned, and one slung by hand to a suspended seat while held | Each named: the PR-finishing work, the landing state, the arm, the assignee, and the live run that works the last. A held bead with none of those was not named. |
| `run-cancel.sh --root` on both runs | Each closed its ten beads as `canceled`, and the run finding and the live-run finding went. |
| The remaining remedies the findings name: `gc mail archive`, `gc bd update --remove-label hold:mayor`, `deferred-dispatch.sh disarm`, and clearing the two assignees | OK: one po seat read and four queued beads, each new work that nothing sends. |

## What the probe did not cover

`gc beads list --label hold:mayor --format=json` printed a bare array in this city
with its supervisor up, and in the live city as well, so the
`{"beads": [...], "_cache_age_s": n}` shape the check also takes was exercised only by
`run.test.sh`. The live city itself read clean, with an empty queue and the note that
no po is configured there, in about 3 seconds.
