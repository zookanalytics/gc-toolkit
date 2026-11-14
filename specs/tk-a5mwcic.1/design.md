---
name: Design record — gc-toolkit's testing strategy and the five-minute suite
description: Use when you write or review a gc-toolkit test, build or adopt the compiled fake gc, file or review a unit of the Testing Strategy & Speed epic (tk-a5mwcic), change what a CI test check runs or the limits it runs under, or order the move into gctk by what its suites cost. The measurements it stands on, and how each was taken, are in measurements.md beside it.
---

# The pack's testing strategy, and the suite's five minutes

This is the design that epic tk-a5mwcic commissioned. It answers the six points
its design bead (tk-a5mwcic.1) asks, in that bead's order. Every number comes
from main at a4ee5ae43 and the CI run that tested it (43560099589), or from a
profile taken on the host at that commit, unless the text names another source.
[measurements.md](measurements.md) holds the tables and the method for each.

## What approving this decides

Every merge waits for the macOS check. On main from 2026-11-12 to 14 it took
26.8 to 44.0 minutes on the runner's usual three cores, and the epic's bar is
five minutes for each required check.

- **The cause.** The checks are CPU-bound, and the CPU goes to starting
  processes: bash, jq and the bash stand-ins for gc. Five minutes on the macOS
  runner's three cores leaves room for about 530 test-seconds, and the suite
  sums 5,059.
- **What the plans already in motion remove.** The deletion plan's whole files
  hold 1,848 of the 5,059, and the merge path's and deferred dispatch's other
  suites, which the epic's boundaries leave out, hold 306 more. The suites that
  stay hold about 2,900 by themselves, five and a half times the budget.
- **Why faster tests alone cannot reach it.** In the kept bash suites profiled,
  the scripts under test start 56% of the processes, and the test files and their
  stubs start the rest. A compiled fake and test code without jq remove about a
  quarter of such a suite's time. The other three quarters leave only when the
  script's logic moves into Go, where a rule's test runs inside one process.

Approving this record decides five things:

1. **The test approach** (section 2). A rule is tested where it lives: in Go
   against fakes once it is in gctk, and in its shell suite until then. What
   stays in shell is tested at its command line against one compiled fake gc,
   and no test code uses jq.
2. **The budget, and how a slower change shows** (section 3). The macOS check's
   suite sums at most about 530 test-seconds, with no run longer than about 178
   seconds, so that a run as slow as the slowest measured still ends within five
   minutes. Each PR's size comment shows what the PR does to the suite's time.
3. **The ask to the move into gctk** (section 4). This work does not wait for
   the move, and the move takes its domains in the order of what their suites
   cost wherever it has no stronger reason.
4. **What the macOS check runs** (section 5). It runs every test that runs code
   on the host's tools. That is every shell suite today, and it gains the Go
   tests of the adapters that start the host's tools, which today run only on
   Linux.
5. **The first Delivery** (section 6). It has six units, each its own change.

What it costs, and what waiting costs, are in section 6.

## 1. Why the whole suite takes more than five minutes

### A check's time is its CPU work divided by its cores

| Check | Job | Suite wall | Runs in parallel | Summed test-seconds | Summed ÷ parallel |
|---|---|---|---|---|---|
| test-macos | 28m51s | 1,687 s | 3 | 5,059 | 1,686 s |
| test (Linux) | 20m14s | 1,199 s | 4 | 4,115 | 1,029 s |
| go | 3m07s | — | — | about 25 s of tests | — |

The macOS suite's wall time equals its summed test-seconds divided by three, to
the second. Three runs were in flight from start to end, so the wall time is the
work divided by the cores, and laying the runs out differently cannot shorten
it. Run plain on the host, 24 of the costliest kept suites kept 0.81 of a core
busy on average, and 61% of that CPU time was kernel time.

The go check differs. Its tests ran in about 25 seconds across all the packages
of gctk and helm. Its other two and a half minutes are setup and compiling,
mostly helm's dependencies.

### The CPU goes to starting processes

Those 24 suites hold 1,571 of the kept ground's 2,905 macOS test-seconds. Run
on the host with every common command counted, they started at least 180,166
processes through PATH, and 16,394 stub processes more. jq was 36.5% of
the counted starts, then cat, tr and bash at 6 to 8% each, and grep, git,
dirname, rm and sed after them.

One start costs 2.7 to 9 ms on the host, depending on the program, and a start
inside `$( )` costs a fork more. At those costs, the counted starts account for
about three quarters of those suites' CPU time. That figure is an estimate,
because the costs were timed at a busier moment than the suites ran. The
kernel's 61% share was measured directly. The profile on tk-pgl0s8j found the
same: 89 to 97% of each suite's time is inside runs of the script under test,
and that time is process starts ([profile.md](../tk-pgl0s8j/profile.md)).

### Who starts them

In the 19 profiled suites whose script under test is bash:

| Started by | All processes | jq alone |
|---|---|---|
| the test file | 18% | 11% |
| the stubs that stand in for gc, bd, gh and git | 26% | 28% |
| the scripts under test | 56% | 60% |

The suites of `gc-helm.sh` and `gh-origin-guard.sh` are left out of that table,
because both scripts run under sh, which loads no profile, so their starts cannot
be told apart from their test files'.

A gc call through a bash stub costs 12.7 to 19.1 ms, and the same call through
a compiled stand-in costs 3.2 to 4.7 ms. A run of a script under test starts
tens to hundreds of processes: one `stand-down.sh` run took about a second.
A suite runs its script tens to hundreds of times, and the 24 profiled suites
make 76 to 658 assertions each.

### Why it grew

On Linux the suite summed 464 test-seconds over 110 files on 2026-09-06, and
4,115 over 263 files at a4ee5ae43. The macOS check, first run on 2026-10-08,
summed 2,636 on 2026-10-12 and 5,059 at a4ee5ae43, net of the cost fixes that
landed in between. Of that macOS rise, 1,260 test-seconds came from 95 files
new by path in the month, and 1,485 from the 168 files present at both ends,
which grew from 2,314 to 3,799. The 54 files gone by the end took 322 away.

New suites and heavier old ones each brought about half. Nothing in how a test
is written bounds what one case costs, and nothing shows a PR what it adds to
the suite.

### What the plans in motion leave

| Part of the suite | Files | macOS | Linux |
|---|---|---|---|
| Whole files the deletion plan retires (`tools/deletion-plan.tsv`) | 42 | 1,848 | 1,701 |
| The merge path's and deferred dispatch's other suites, which the epic's boundaries leave out: `merge.test.sh` (tk-1tfzr71.20), `deferred-dispatch.test.sh` (tk-1tfzr71.16), and ten suites the merge member's branch deletes that the plan's rows do not list | 12 | 306 | 233 |
| **The kept suites, this epic's ground** | 209 | **2,905** | **2,181** |

The ten are suites of the merge path, such as `unrecorded-direct-landing.test.sh`
and `pr-stack.test.sh`. The merge member's integration branch already deletes
them, and the epic's boundaries leave the merge path's suites out, so they are
not this epic's ground either.

The kept ground alone is five and a half times the macOS budget. Cutting call
sites in the shared scripts does not move it: tk-nalm16x cut the scripts the
suites run most, and its own paired runs measured the whole suite at 99.4% of
main's. The time is spread across the suite. On macOS, 162 kept files of under
20 seconds each hold 665 test-seconds between them, more than the whole budget.

### The Linux outlier

`step-number-citation.test.sh` took 204 to 256 seconds on each of the five
Linux runs read since it landed on 2026-11-06 (#1411), and 5 seconds on macOS.
It is 6% of the Linux check's test-seconds. Its one awk pass over every tracked file, with
a regular expression built from every formula and skill name, is the likely
cause on GNU awk. Unit 2 confirms the cause and removes it.

## 2. The test approach

### Where behavior is tested

A behavior is tested where its code lives, and the cost of its test follows
from that.

1. **A rule in gctk is tested in Go, in one process, against the adapters'
   fakes.** That is already rule 5 of a domain move
   ([gctk-architecture.md](../../docs/gctk-architecture.md#the-rules-a-domain-move-follows)).
   This design adds that a rule's test starts no process: no `os/exec`, and no
   stub `gc` on PATH. A case then costs microseconds. The exceptions are the
   adapters' own tests, which start the real tool to pin what its fake stands
   in for, and the three verbs the page's Debt section names (`epic create`,
   `session title` and `rig`), until tk-ssm8qns.16 puts them behind adapters.
2. **A rule still in shell is tested in its shell suite until it moves.** When
   it moves, its shell cases leave with the shell and its Go test replaces them
   ([built-once-target.md](../../docs/built-once-target.md), "Tests follow
   code"). No suite is rewritten in Go while its script stays in shell. A Go test
   that runs the script pays the same process starts per case, and a Go test of a
   Go copy of the rule would hold two copies equal.
3. **What stays in shell is tested at its command line.** That covers a script
   no move reaches yet, and a bridge a moved domain keeps for its callers. Its
   test runs the script against the compiled fake gc.

### What a test at the shell command line covers

- its arguments: each flag, and the usage errors;
- its exits: one case for each distinct exit path;
- the output its callers read, such as a formula step or a prompt;
- the calls it makes, read from the fake's record of them;
- its use of the host's tools, which is why it also runs on macOS;
- what only the shell process does: traps, signals, locks, time limits and
  cleanup.

A command-line test does not walk a rule's table of cases. That table belongs to
the rule's Go test once the rule moves, and until then it stays in the shell
suite.

### How the store, gc, bd and the rest are faked

Each outside system has one fake, as each of gctk's adapters does:

| Outside system | Its fake | What pins the fake to the real system |
|---|---|---|
| The bead store, and gc's other verbs a script calls (sling, session, mail, convoy, agent, workflow) | The compiled fake gc: one Go program, built once per run and put on PATH as `gc`, answering gc's command line from a store the test sets | A contract test that runs the same calls against the fake and against a scratch store of the bd the city runs |
| GitHub | Recorded responses, as the harness's gh stub serves them today | Nothing yet. gctk has no github adapter, and its architecture gives the one it plans recorded responses as its fake |
| git | Real git in a scratch repository | git itself |
| The host's processes | gctk's host adapter fake, in Go | The host adapter's own tests, which start real processes, on both platforms |
| Time | The bubble clock of `testing/synctest`, in Go | Go's testing package |

The fake gc holds state and refuses what bd refuses, such as a second
dependency on one pair of beads or a write to a bead the store does not hold. A
test sets rows and edges, runs the code, and asserts on the state that results
and on the calls recorded. No test scripts a canned answer for each store call.
A fault, such as a failed list or a failed update, stays a setting the test
makes, as the harness's `STUB_*` settings are today.

The fake is compiled because a call through it costs 3.2 to 4.7 ms against 12.7
to 19.1 ms through the bash stub. It is one fake because 126 of the 209 kept
suites each write a gc stub of their own. Those suites hold 2,408 of the kept
ground's 2,905 macOS test-seconds. A stub that answers differently from bd has been
fixed one stub at a time: tk-8gradm4.3 lists ten such patches. One fake fixes
each difference once, for every suite.

The fake lives in `services/gctk`, beside the store adapter's fake, so the
store's behavior is modeled once for the Go tests and the shell tests, and the
go check builds and tests it on every PR. It reads and writes the harness's
store files, so a suite on `assets/scripts/test-harness.sh` moves onto it
without rewriting its fixtures.

**What the platform provides.** Gas City upstream, at dc5486b99, tests its own
store this way. `internal/beads/memstore.go` keeps beads in memory as "a test
double in cross-package tests". `internal/beads/beadstest/conformance.go` runs
one suite against every store implementation. `internal/beads/beadstest/fake_bd.go`
is "a minimal, stateful stand-in for the bd CLI, backed by a MemStore", and
`test/acceptance/beads_cli_contract_test.go` exercises each bd command Gas City
depends on whenever the beads pin moves. None of these can answer a shell
script that runs `gc`. FakeBd answers inside Gas City's own process, as the
store's command runner. All four live in Gas City's own module: three under its
`internal` tree, which another module cannot import, and one as an acceptance
test. The fake gc applies the same
pattern at the process boundary: a model in memory, a conformance suite run
against the real bd, and a contract test run when the bd the city runs changes.

### No jq in test code

Test files and fakes start no jq. The fake answers in Go. A shell test reads
the state it asserts on through the fake, one value or several per call, and a
Go test reads it in its own process. jq stays in the shipped scripts until they
move, and in the profiled bash suites those scripts start 60% of the jq.

### Where this departs from the operator's sketch

The operator's words, in sitting tk-vjdc8es: "The insane number of forks
hopefully goes down if we don't need jq to test code. ... probably within Go
with a few looking at the bash CLI surface."

1. **Tests reach Go with the code, not ahead of it.** "Within Go" arrives as the
   move into gctk moves each rule, because a test pins the copy where the rule
   lives.
2. **The command-line tests stay bash suites, run by `tools/run-tests.sh`.**
   Driving a script from Go would not cut the script's own starts, and every
   kept suite would need a rewrite to get there.
3. **Taking jq out of test code removes about 40% of the jq.** That is the
   share the stubs and the test files start in the profiled bash suites: 28%
   and 11%. By itself it cuts about a quarter of such a suite's time.
4. **The five minutes depend on the move into gctk.** This epic orders that
   move by cost, and it does not do the move.

## 3. The budget, and how a slower change shows in its PR

### The budget

The bar is the epic's closure condition: each required check finishes within
five minutes over a week of runs on main, and none takes more than ten. Each
number below is derived from that bar and from a measurement.

- **The spread between runs.** Two consecutive runs on main, whose suites cost
  the Linux check within 1% of each other, took the macOS check 26.8 and 36.2
  minutes, a factor of 1.35. Between them the time of one test run, a file or
  one of its parts, moved on macOS by a median of 1.27 times, and the 95th
  percentile was 1.62. The whole run moves together, because the runner's own
  speed varies. On Linux the median was 1.00 and the 95th percentile 1.09.
- **The suite's share of the macOS check.** For the slowest run to end within
  five minutes, a typical run must end within 5 ÷ 1.35, which is about 3.7
  minutes. The job spends 44 seconds outside its suite, 37 of them before it
  starts, so the suite gets about 178 seconds.
- **The macOS budget.** The suite sums at most about 530 test-seconds, which is
  three cores times 178 seconds. No single run is longer than about 178
  seconds, because no run starts before the suite does. `tools/run-tests.sh`
  starts the files with the most source first, as its proxy for the slowest.
- **The runner's cores.** The budget is set for three cores, which every main
  run from 2026-11-12 to a4ee5ae43 had. The next main run, at 45e9ddb41, got
  five on the same image and took 16.4 minutes for 4,705 test-seconds, while
  the PR runs on either side of it got three. The closure's backstop wants the
  minutes to come from what the tests cost, not from more or larger runners,
  so a run that gets more cores shows no progress, and the budget stays in
  test-seconds on three.
- **The Linux check.** Its spread is about 1.1, and its job spends about 15
  seconds outside its suite. That gives its suite about 258 seconds on four cores,
  about 1,030 test-seconds. The same suite costs Linux about three quarters of
  its macOS test-seconds, leaving out the outlier, so the macOS budget is the
  one that binds.
- **The go check.** It ran in 3m07s, of which its tests took about 25 seconds.
  Go tests that start no process add little. If its compiling grows, the
  module and build cache that `actions/setup-go` keeps is the platform's way to
  cut it.

**The cost of being wrong.** If the true spread is wider than 1.35, some runs
take longer than five minutes and stay under ten. The epic's first indicator,
the share of a week's runs within five minutes, shows that within a week, and
the budget is then derived again from that week's spread.

### How a slower change shows in its PR

The sitting proposed this part, not the operator.

- **Every PR shows what it does to the suite's time.** Its size comment already
  carries the PR's size change, and rule 3 of
  [built-once-target.md](../../docs/built-once-target.md#the-rules) lets the
  PR's CI test time sit beside it. For each test check, the comment shows the
  PR's summed test-seconds beside main's latest completed run, with the factor
  by which the whole run moved. It lists the test files the PR adds or removes,
  with their seconds, and the files whose time moved by more than the spread
  measured between runs. The Linux check is the reference for one file's change,
  because its runs hold within 10%.
- **The hard limit is the closure's.** Once the suite meets the budget, each test
  job's `timeout-minutes` becomes 10, the closure's "none takes more than ten".
  Until then the macOS check keeps the limit it needs to pass (60, tk-d9u6tmm).
- **No threshold below the hard limit stops a merge.** The macOS check's own time
  moved by a third between two runs whose suites cost Linux the same, so a gate
  on time would fail sound PRs.

## 4. The move into gctk

### This work does not wait for the move

The first Delivery's units land on today's code. The rules of section 2 hold
for any test written from now on, whichever side of the move its code is on.

### What it needs from the move

The five minutes need most of the kept shell to move. What this design needs
from the move:

1. **The order of the domain moves follows what their suites cost**, wherever
   the move has no stronger reason. In macOS test-seconds at a4ee5ae43:

   | Kept suites | macOS | Linux | Carried by |
   |---|---|---|---|
   | `gc-helm.sh`'s engage, open and conversations | 244 | 208 | tk-ssm8qns.15 |
   | Its other verbs: accept, place, dismiss, park, seats and the rest | 209 | 143 | no Feature yet; tk-1tfzr71.24 rewrites the verbs that only call Gas City |
   | The engagement scripts: `stand-down.sh`, `bead-rehome.sh`, `converse-signoff.sh`, `bead-context.sh`, `first-reaction-dispose.sh`, `converse-rework.sh`, `operator-intake.sh` and the tmux bindings | 489 | 332 | no Feature yet |
   | The seed audit | 105 | 73 | tk-ssm8qns.10 |
   | Priority following | 78 | 46 | tk-ssm8qns.7 |
   | PR posts and the gh write guard | 76 | 57 | tk-ssm8qns.8 |
   | Dolt reclaim, and the epic, session and rig verbs | 9 | 5 | tk-ssm8qns.9, .16 |
   | The rest of the kept shell, 168 files | 1,695 | 1,317 | the move's later domains |

2. **Each move takes its shell suite with it.** The move deletes the suite with
   the shell it replaces, which is already rule 1 of a domain move. A bridge the
   move keeps gets only command-line cases against the fake.
3. **A moved rule's tests start no process**, as section 2 says. The three verbs
   in the Debt section are the exceptions, until tk-ssm8qns.16.
4. **An adapter that starts a host tool keeps a test that starts it.** That test
   stays in the adapter's own package, where unit 6 runs it on the macOS check
   as well.

### The code that stays in shell

Until a domain moves, its suite moves onto the compiled fake and stops starting
jq of its own. Units 4 and 5 move the suites with the most stub time whose
scripts no Feature or retirement names. A suite whose script a scheduled move
or retirement deletes stays as it is, so that no work goes into a suite that is
about to leave.

## 5. What the macOS check is for

The city's host is macOS, so code the host runs meets BSD sed, grep, awk, date
and stat, Homebrew's bash 5 in a UTF-8 locale, and macOS's ps, lsof and process
groups. The macOS check exists so that code which works under Linux's tools
and fails under the host's still fails a required check.

It has done that. Of the 1,000 most recent PR runs, from 2026-10-08 to
2026-11-14, 28 failed. In 2 of them only the macOS check failed, in 3 only the
Linux check, and in 21 both. The 2 macOS-only failures were one defect: an
unbraced variable followed by an ellipsis, whose first byte the host's bash,
in a UTF-8 locale, reads into the variable's name. One was in a shipped script
(`preexisting-failure.sh`, fixed in 87936ea3a) and one in a test file
(`liveness-sweep.test.sh`, fixed in 13fa10a16). So the host's tools include its
bash and its locale, not only the BSD userland.

**It keeps running every test that runs code on the host's tools.** Today that
is every shell suite. Nearly every one runs shipped shell, or formula step text
an agent runs on the host, through those tools. The few that check CI's own
files cost seconds and stay in, unmarked. It does not run a sample of the
suites, because a sample keeps the backstop only for the code the sample
reaches.

**It gains the Go tests that start the host's tools.** gctk's host adapter runs
ps, lsof and kill, and its git adapter runs git, and CI runs their tests only
on Linux today. That is a gap in the same backstop, and unit 6 closes it.

**It never runs Go tests on fakes.** Those behave the same on both platforms
and run once, on the go check.

So the macOS check shrinks as the shell does. A rule that moves into Go leaves
the macOS check altogether, and that is why the move does more for this check
than for the others.

## 6. The first Delivery

### The units, in order

Each unit is its own change, filed as a Story once this design is approved.

| # | Unit | Effect | Waits on |
|---|---|---|---|
| 1 | **Each PR shows what it does to the suite's time.** The test jobs keep each run's seconds, in the job's summary and as a run artifact. The PR's size comment shows, for each check, the summed test-seconds beside main's latest completed run, and the files added, removed and moved beyond the measured spread. | No seconds of its own. It makes every later unit's effect, and every regression, visible in its own PR. | — |
| 2 | **`step-number-citation.test.sh` costs Linux what it costs macOS.** Confirm the GNU-side cause and remove it. | About 250 Linux test-seconds, 6% of the Linux check, and about a minute of its wall time. | — |
| 3 | **The compiled fake gc and its contract test.** A Go program in `services/gctk` answers the gc command line that the harness's bash stub answers, over the same store files and fault settings, and `test-harness.sh` installs it. Its contract test runs the same calls against a scratch store of the bd the city runs, as the store adapter's acceptance test does. `docs/testing.md` states the approach for whoever writes a test. | Each harness stub call goes from 12.7–19.1 ms to 3.2–4.7 ms. The kept harness suites spend few seconds in stubs: of those profiled, `pr-open.test.sh` spends about 10 and each of the others under 4, so the kept ground gains about 17 test-seconds here, and most of the fake's gain comes in units 4 and 5. While `pr-facts.test.sh` lives, its 35% stub share makes it about a quarter faster. | 1 |
| 4 | **The engagement and conversation suites no Feature names move onto the fake:** stand-down, bead-rehome, converse-signoff, bead-context, conversation-merge-hold, first-reaction-dispose and converse-rework. | About 120 macOS test-seconds, projected from each suite's measured stub time and jq. | 3 |
| 5 | **The work, shared and doctor suites with the most stub time move onto the fake:** work-submit, patrol-finding, check-armed-dispatch-owed, work-setup, feedback-miner, self-review-check and check-session-store-scope. | About 75 macOS test-seconds, projected the same way. | 3 |
| 6 | **The macOS check runs the Go tests that start the host's tools:** gctk's host and git adapters, and the store adapter's tests that drive a stub gc. | It adds those packages' tests, each under a second on the go check, and their compiling, which for gctk took 4.3 s cold on the host. It closes the backstop gap in section 5. | — |

Once this design is approved, tk-ssm8qns also gets the cost order of section 4
as a note, for its next checkpoint.

Units 3 to 5 change files that two live integration branches change too. The
deferred-dispatch member's (tk-1tfzr71.16) and the merge member's
(tk-1tfzr71.20) both edit `test-harness.sh`, and between them they rewrite
parts of nine of the suites units 4 and 5 name: stand-down, bead-rehome,
converse-signoff, bead-context, conversation-merge-hold, first-reaction-dispose,
converse-rework, work-submit and check-armed-dispatch-owed. Neither deletes
one. No unit waits for them. Each unit merges main in first, builds beside a
branch that has not landed, and plans the merge with whichever lands second.
The projections come from main's copies of those suites, so each unit measures
its suites again when it starts, and unit 1 shows what it saved.

### The path to the budget

| Step | Who | macOS summed after it | Typical macOS job |
|---|---|---|---|
| Today, a4ee5ae43 | — | 5,059 | 28.9 min, measured |
| The deletion plan's whole files leave | the tk-1tfzr71 lanes | 3,211 | about 18.6 min |
| The merge path's and deferred dispatch's other suites leave | tk-1tfzr71.20, tk-1tfzr71.16 | 2,905 | about 16.9 min |
| The first Delivery | this epic | about 2,700 | about 15.7 min |
| The move's queued Features and tasks | tk-ssm8qns.7, .8, .9, .10, .15, .16 | about 2,190 | about 13 min |
| `gc-helm.sh`'s other verbs, and the engagement scripts no Feature names yet | the move, in Features not yet filed | about 1,590 | about 9.6 min |
| The rest of the kept shell | the move's later domains, with the fake for what stays | at most 530 | about 3.7 min |

A typical job takes about the summed test-seconds divided by three, plus 44
seconds, which reproduces a4ee5ae43's 28m51s. The first row is a measured run,
the next two take measured files away from it, and the rest are projections.
The first Delivery's effect comes from the host profile, and the move's from
deleting the suites each Feature names.

The first Delivery alone takes about 7% of the kept ground. The budget is
reached when the move has taken nearly all of the kept shell's cost, and that
was already the move's direction: an `assets/scripts` that is gone
(tk-ssm8qns). What this epic adds is the rule that each moved rule is tested
in-process, the order that puts the costliest suites first, a cheap way to
test what stays, and a PR comment that keeps the time from growing back unseen.

### What each part costs

- **Units 1 and 6** are CI changes, small. Unit 1 adds a step to read the run's
  times, and a section to the size comment.
- **Unit 2** is one suite.
- **Unit 3** is the largest. It reimplements the harness stub's verbs and fault
  settings in Go, about 700 lines of bash today, and adds a contract test that
  needs bd and dolt where it runs, as the store adapter's acceptance test does.
- **Units 4 and 5** rewrite each named suite's stub use and its jq reads, one
  suite or one domain per change.
- **For the operator**, the cost is reading six Stories and one comment section
  that appears on every PR.

### The cost of waiting

From 2026-10-12 to 2026-11-14 the macOS suite grew by 2,423 test-seconds, net
of the fixes that landed in that time: about 73 a day, or 25 seconds of the
macOS check a day. At that pace the check reaches its 60-minute limit in about
eleven weeks, and every PR waits for it before it merges. The deletion plan's
1,848 test-seconds, once they leave, buy about 25 days of that growth. Each
suite written in the meantime gets a bash stub and jq of its own, and units 4
and 5 then move it onto the fake.

## Constraints, and the beads this touches

- **Code the deletion plan retires gets no new work.** No unit edits a suite of
  retiring code, and the cost table leaves those suites out. Unit 3 changes
  only the shared harness, which the plan keeps. The retiring suites that use
  the harness run faster while they live and need no change.
- **A test pins the behavior of the one copy where it lives.** Nothing here
  tests a second copy. The fake stands in for bd, an outside system, and its
  contract test pins it to bd, as the store adapter's acceptance test pins the
  adapter.
- **A change that speeds up tests adds no production setting whose only
  non-default user is the test suite** (tk-1g0sgyg). The fake reaches a script
  through PATH, the seam the stubs already use, and no unit adds a setting to
  shipped code.
- **tk-8gradm4.3.** This design needs that bead's aim: stubs that behave like
  real bd, held to it by a contract test, with the per-suite stubs moved onto
  the shared harness. Units 3 to 5 deliver it on the compiled fake, not on the
  bash stubs. Proposed: once unit 3 is filed, tk-8gradm4.3 closes as replaced by
  units 3 to 5. It is parked behind tk-u5t8h6x, so that is the operator's call.
- **tk-dqc1ere** (P1) carries the target of half of 2026-11-05's summed
  test-seconds, through cuts to the suites tk-nalm16x left: `gc-helm.sh`'s, the
  seed audit's, `work-submit.test.sh`'s and others. tk-nalm16x's own paired runs
  measured its cuts to the shared scripts at under 1% of the whole suite. The
  suites tk-dqc1ere names are the ones this design sends to the move or onto the
  fake. Proposed: the operator closes it into this epic, so that two beads do
  not work the same suites two ways.
