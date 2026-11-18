---
name: Testing gc-toolkit — where a behavior is tested and what stands in for gc
description: Use when you write or change a gc-toolkit test, decide whether a behavior's test belongs in Go or in a shell suite, put a suite on the compiled fake gc or teach the fake something it lacks, or run the fake's contract test against the bd the city runs.
---

# Testing gc-toolkit

A behavior is tested where its code lives. A rule in gctk is tested in Go, in
one process. A rule still in shell is tested in its shell suite, and what stays
in shell is tested at its command line against the compiled fake gc, which
answers gc's command line the way bd and gc do.

## Scope

**Mandate.** How a gc-toolkit test is written: where a behavior's test lives,
what a test at a script's command line covers, the fake that stands in for each
outside system and what holds that fake to the real one, and how a test reads
the state it asserts on.

**Boundaries.** How tests are run in parallel, their parts and their time
limits are [tools/run-tests.sh](../tools/run-tests.sh)'s header. What a CI
check runs is [.github/workflows/tests.yml](../.github/workflows/tests.yml).
The rules a gctk domain follows as it moves out of shell are
[gctk-architecture.md](gctk-architecture.md#the-rules-a-domain-move-follows),
and which code is retired, with its tests, is
[built-once-target.md](built-once-target.md).

## Where a behavior is tested

1. **A rule in gctk is tested in Go, in one process, against the adapters'
   fakes.** Its test starts no process: no `os/exec`, and no stub `gc` on PATH,
   so a case costs microseconds. An adapter's own tests are the exception,
   because they start the real tool to pin what the adapter's fake stands in
   for, and so are the verbs the
   [Debt section of gctk-architecture.md](gctk-architecture.md#debt) names
   until they stand behind adapters.
2. **A rule still in shell is tested in its shell suite until it moves.** When
   it moves into gctk, its shell cases leave with the shell and its Go test
   takes their place. A suite is not rewritten in Go while its script stays in
   shell: a Go test that runs the script pays the same process starts, and a Go
   test of a Go copy of the rule would test a second copy.
3. **What stays in shell is tested at its command line**, against the compiled
   fake gc. That covers a script no move reaches yet and a bridge a moved
   domain keeps for its callers.

## What a command-line test covers

- the script's arguments: each flag, and the usage errors;
- its exits: one case for each distinct exit path;
- the output its callers read, such as a formula step or a prompt;
- the calls it makes, read from the fake's record of them;
- its use of the host's tools, which is why the shell suites also run on macOS;
- what only the shell process does: traps, signals, locks, time limits and
  cleanup.

A command-line test does not walk a rule's table of cases. That table belongs
to the rule's Go test once the rule moves, and until then it stays in the shell
suite.

## The fakes

Each outside system has one fake:

| Outside system | Its fake | What holds the fake to the real system |
|---|---|---|
| The bead store, and the other gc verbs a script calls | The compiled fake gc, [services/gctk/internal/gcbd/fakegc](../services/gctk/internal/gcbd/fakegc/doc.go), on PATH as `gc` | Its contract test, which runs the same calls against the fake and a scratch store of the bd the city runs |
| GitHub | The recorded responses the harness's gh stub serves | Nothing yet |
| git | Real git in a scratch repository | git itself |
| The host's processes | gctk's host adapter fake, in Go | The host adapter's own tests, which start real processes |
| Time | The bubble clock of `testing/synctest`, in Go | Go's testing package |

## The compiled fake gc

The fake keeps the store's state in files and keeps bd's rules over it, such as
one dependency per pair of beads, metadata values typed as bd types them, and a
create refused whole when a dependency it names is missing. Its package doc,
[doc.go](../services/gctk/internal/gcbd/fakegc/doc.go), lists the verbs it
answers, the store files, the fault settings, and where it departs from bd.

A shell suite reaches it through the shared harness,
[assets/scripts/test-harness.sh](../assets/scripts/test-harness.sh):

1. Source the harness and call `harness_init`, which puts the fake on PATH as
   `gc`, beneath it the test floor, and exports the settings the fake reads.
2. Set the state the case starts from: rows with `store`, edges as lines in
   `$STUB_DEPS`, and a fault, such as a failed list or a refused update, as a
   `STUB_*` setting.
3. Run the script under test.
4. Assert on the state that results, through the harness's readers (`meta`,
   `bstatus`, `bassignee`, `bprio`, `bpoured`, `bparents` and `notes`), and on
   the calls the script made, in `$STUB_GC_LOG`.

A test sets state and asserts on state and calls. It does not script a canned
answer for each call. A store file the fake cannot read or write ends the call
at exit 3 with a line naming the file, so a failed write never reads as one that
landed.

[tools/run-tests.sh](../tools/run-tests.sh) builds the fake once for a run that
has a suite on the harness, and a suite run by itself builds its own. Either way
it is built from the tree under test.

When a script needs a gc behavior the fake lacks, add it to the fake with a Go
test beside it, and a contract case when bd has a rule for it, rather than a
stub of the suite's own.

## No jq in test code

Test files and fakes start no jq. The fake answers in Go, and a shell test reads
the state it asserts on through the harness's readers, which ask the fake. jq
stays in the shipped scripts until their logic moves into gctk.

## The contract test

`TestContract` runs each bd call the fake models against the fake and against a
scratch store of the bd the city runs, and compares the exit, the answer and the
state each leaves. It needs bd and dolt on PATH, so it runs only when asked:

```bash
cd services/gctk && GCTK_STORE_ACCEPTANCE=1 go test ./internal/gcbd/fakegc -run TestContract -v
```

Run it with every change to the fake, and whenever the bd the city runs
changes. A case it fails is a difference between the fake and bd: change the
fake to bd's rule, or, where a suite still depends on the fake's own rule, list
the difference in the fake's package doc.

## A test's time

Each PR's size comment shows what the PR does to the suite's time, beside main's
latest completed run ([suite-time.sh](../.github/workflows/suite-time.sh)), and
nothing in it fails a check or holds a merge. tools/run-tests.sh ends a run only
when it writes nothing for its silence limit.
