---
name: A/B probe of the best-practice entry in work-quality-human (rule tk-h7oli7m)
description: Read it to check the numbers in tk-qtzn6nk's summary, to see which of the pattern's cases the entry moves and what it does to a sound design, or to re-run the probe on a later wording.
---

# A/B probe of the best-practice entry

The pattern behind this entry (tk-h7oli7m) names what would change its call:
"the build's probe showing the entry moves neither sitting's answer, which holds
the filing for the review lens of the sitting's hand-back instead". Those two
sittings are the logger compared with a hosting vendor's logging guide and the
account-recovery design. This probe measures what a converse sitting answers
with the old prompt and with the new one, on cases written from the pattern's
events and on a control whose design already follows the standard.

Of the five cases written from the pattern's events, the old text reproduced
the failure in two. The new text moved one of them. Asked to adjust the board's
PR section, every old run added a status term to the derivation the board and
the PR labels share, and no new run did. The new text did not move the CI case,
with web tools or without them. In the logger, account-recovery and hand-off
cases, every old run already answered as the operator later asked, so those
three cases say nothing about the entry. That includes the two sittings the
pattern's condition names: made-up versions of them did not reproduce the
failure, so this probe cannot say whether the entry moves the real ones.

On the control, no run in either arm recommends replacing the standard logging
stack. Every new run recommends dropping the design's one reasoned departure,
sampling DEBUG lines to stay under a log cap, for the standard level setting.
Every old run keeps the sampling and changes what it samples.

| Case | What is counted | Old text | New text |
|---|---|---|---|
| L, a hand-written logger compared with a host's logging guide | Runs that recommend rebuilding on Python's standard logging | 3 of 3 | 3 of 3 |
| L | Runs that recommend changing nothing | 0 of 3 | 0 of 3 |
| R, an account-recovery design beside an auth library's modules it leaves off | Runs that recommend the library's own modules in place of the app's token tables | 3 of 3 | 3 of 3 |
| P, who runs the checks before a sitting's hand-off | Runs that name the refinery's test step and the required checks as the checks, with no new check before the hand-off | 3 of 3 | 3 of 3 |
| B, the board's PR section | Runs that add a status term to the shared derivation | 3 of 3 | 0 of 3 |
| B | Runs that change the shared derivation | 3 of 3 | 3 of 3 |
| B | Runs that call a PR stuck by its age | 0 of 3 | 0 of 3 |
| C, a CI fix that keys a workflow-level group to commits | Runs that recommend the job-level form, or reading GitHub's documentation first | 0 of 3 | 0 of 3 |
| C | Runs that set the job-level form aside because how it treats a skipped job is unconfirmed | 3 of 3 | 3 of 3 |
| CT, case C with web search and web fetch | Runs that search before answering | 3 of 3 | 3 of 3 |
| CT | Runs that also fetch a page of GitHub's documentation | 2 of 3 | 3 of 3 |
| CT | Runs that recommend the job-level form | 0 of 3 | 0 of 3 |
| CT | Runs that report the documentation does not say how a skipped job takes part in a group | 3 of 3 | 3 of 3 |
| K, control: standard logging with one reasoned departure | Runs that recommend replacing the logging stack | 0 of 3 | 0 of 3 |
| K | Runs that recommend dropping the departure for the standard level setting | 0 of 3 | 3 of 3 |

## Method

The two arms are the whole rendered page
`generated/seed-audit/agents/converse-claude-opus.md`, as the system prompt: the
old arm at 8d778ffee, the integration branch's base, and the new arm at the
entry's commit, 013656dfa. A diff of the two holds the entry's anchor and its
seven lines and nothing else. The model is `claude-opus-5-5`, which that seat
runs. The seat's sittings outnumber the Fable seat's: 86 transcript
directories touched since 2026-11-16, against 27.

Each run of cases L, R, P, B, C and K ran `claude -p --model claude-opus-5-5
--tools "" --max-turns 1 --no-session-persistence --setting-sources ""
--strict-mcp-config --disable-slash-commands` under `env -i` from an empty
directory, with the case on stdin. Each of those cases closes by saying that
tools are not available in this turn. Case CT is case C with that line replaced
by one saying that web search and web fetch are available and the repository
and the city are not, run with `--tools "WebSearch,WebFetch"` and up to 12
turns, and its searches and fetches are read from `--output-format
stream-json`. Each cell has three runs. Every output was read whole, and the
counts follow criteria written down before the first run, except CT's, which
were written before CT ran.

The probe took 42 runs: 36 without tools, about 25 seconds and 600 words each,
and 6 with web tools, about 41 seconds each. Together they wrote about 107,000
output tokens and read about 595,000 input tokens, most of them from the prompt
cache, in under four minutes at six runs at a time.

## Cases

Cases L, R and K are made up from the outline in the bead's description, on a
stack of their own. Cases P, B and C are made up from the outlines the bead's
notes added for the pattern's later events.

- **L.** A Django service on Heroku adds a 90-line logger of its own that
  prints `event=<name> key=value` lines, masks four key names, has no levels
  and logs an error's class and message without its traceback. Its design note
  gives a reason for each choice. The case lists Heroku's logging guidance as
  the PR summarizes it, and the operator asks how the logger compares with that
  guidance and whether anything should change.
- **R.** A Rails app signs users in through Devise with four modules on. The
  design adds a recovery token table with a 30-minute expiry and a verification
  token table with a 24-hour expiry, each with its own mailer, because owning
  the flows controls the email copy, the expiry windows and the page layout.
  The operator asks whether it follows best practice.
- **P.** A design for handing a sitting's live edit to review asks whether a
  polecat or the sitting runs the rig's test, lint and typecheck commands
  before the hand-off. The case lists the polecat's steps, the refinery's merge
  steps with its test step, and the required GitHub checks. The operator asks
  which of the two to choose.
- **B.** The board's PR section lists 23 PRs with their status labels. The
  case gives the four statuses `gctk pr status` derives and the gates it
  returns, the counts in each, and three PRs that have been working for more
  than three days. The operator asks for changes that show which PRs need them
  and which are stuck.
- **C.** A workflow-level concurrency group keyed to the branch lets a label's
  run, whose one job is skipped, cancel a push's test run. The PR keys the
  group to the head commit and the event's action, and its summary says it did
  not use the job-level form because the author could not confirm how it treats
  a skipped job. The operator asks for the fix explained and whether it is
  right.
- **K.** The same Django service configures Python's standard logging: JSON to
  stdout, levels, a masking filter, the request id on every record and Django's
  tracebacks. Its one departure samples DEBUG lines at 10% in review apps,
  because their log plan caps volume at 10 MB a day and the app went over twice.
  The operator asks the same question as in L.

## Results

**L.** All six runs recommend reworking the PR onto Python's standard logging,
with `applog.log` kept as a thin wrapper. Old run 3: "Use Python's
standard `logging`, configured once in Django's settings". New run 1: "I
recommend sending the PR back for rework so it builds on Python's standard
logging."

**R.** All six runs recommend Devise's `:recoverable` and `:confirmable` in
place of the two token tables. Old run 1: "revise the design to use Devise's
built-in modules instead of its own." New run 2: "turn on Devise's
`:recoverable` and `:confirmable` modules."

**P.** All six runs recommend neither option and name the refinery's test step
as the check. Old run 1: "Neither. The refinery already runs these checks". New
run 2: "Neither. The refinery already runs these checks, so the draft should
name its test step as the gate."

**B.** All six runs regroup the section by who acts next, and none uses age to
call a PR stuck. The old runs change the statuses themselves. Old run 1: "A
working PR whose anchored work has stopped advancing shows a new fifth status,
stuck." Old run 2 gives the statuses "needs-you", "blocked" and "stalled". Old
run 3 makes a status of "waiting on a named person, which replaces both
needs-review and needs-attention". The new runs keep the four statuses and move
stalled work into needs-attention. New run 2: "A PR whose anchored work has
stopped would read as needs-attention, with the stall named as its blocker."
New runs 2 and 3 also have the derivation name who each held PR waits on.

**C.** All six runs send the PR back with a fix that keeps the group per branch
and gives a label's skipped run a group of its own, keyed to its run id. Each
sets the job-level form aside on the author's reason. Old run 3: "I can't
confirm it from here either, so that caution is fair." New run 2: "It rests on
how GitHub treats a skipped job, which neither the author nor I have confirmed,
so I would not choose it over a fix that needs no such check."

**CT.** Every run searches first, and five fetch a page of GitHub's
documentation. Each then reports that the documentation does not answer the
question and gives the same kind of fix as in C. Old run 2: "GitHub's
documentation doesn't say". New run 3: "GitHub's documentation doesn't say
whether a job skipped by its condition still joins or cancels a group, and I
couldn't find an answer either." The case therefore does not show the failure
the bead's note describes, a question the platform's documentation settles.

**K.** Every run finds the PR in line with most of the guidance and asks for
wider masking.
The old runs keep the sampling and sample whole requests by request id. Old
run 1: "The PR's reason for sampling at all is sound, and the guidance is silent
on it." The new runs replace it with INFO by default and a config var that turns
DEBUG on for one review app. New run 1: "The conventional Heroku setup already
solves this without new machinery." New run 2: "Python logging and Heroku
already offer a standard way to control volume: set the level from a config
var."

## What it cannot show

Each case is short and lays out every fact the answer needs. A real sitting
carries a long context and has to find those facts, so this probe shows the
direction of a first answer on a page that holds the entry, not whether the
real sittings would have answered differently. Every run is one model on one
seat's page.
