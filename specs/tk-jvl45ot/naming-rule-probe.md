---
name: A/B probe of the naming rule, tk-karx6a2
description: Read it to check the numbers in tk-jvl45ot's summary, to see which readers the naming rule moves and on which words, or to re-run the probe on a later wording.
---

# A/B probe of the naming rule

The proposal rests on two readings: an agent that asked the entry's question
would have caught each case, and the polecats fragment reaches the correctness
reviewer, "who sees the name in the diff". This measures both with the old text
and the filed text. It uses the one correction in the pattern's evidence that sits
on a public repository, and cases made up from the entry's own words. Author runs
are on Claude, the provider of the polecat pool. Reviewer runs are on codex, the
provider of the pool that runs every routed review, and on Claude for comparison.

The filed text moves authors off a collision they can see. All nine old runs wrote
`gctk bead blocked`, as the real design did, and all nine filed runs wrote another
word.

On codex, the filed text flags a name its own diff contradicts, in all six runs on
two made-up changes, and nothing else here. No run objects to `gctk bead blocked`
(0 of 9), to a name in the design the operator approved (0 of 18), or on the
controls (0 of 12).

Claude reviewers read it far more widely. No run objects to `gctk bead blocked`
there either, but on the approved design all 18 filed runs block under the entry on
its names, and 8 of those object to `holds`, the word the operator took. Every
objection to `holds` rests on `gc.hold`, a key only another rule's sentence still
names. With that word out of the sentence, 12 of 18 runs block, all on the status
`blocked`, and none on `holds`.

## What authors did

Each cell lists the name the runs chose. The last column holds the filed words in
the polecats' learned conventions instead of the work-quality fragment.

| Case | Task | Old text | Filed text | As a convention |
|---|---|---|---|---|
| A1 | Name the verb for "is this bead blocked?", from the design's own section | `blocked` 9 | `waits` 9 | `waits` 3 |
| A1b | The same, with `gc wait` added to the list of native commands | `blocked` 2, `blockers` 1 | `blockage` 2, `clearance` 1 | `blockage` 2, `clearance` 1 |
| A2 | Choose one word for three sets of sessions, none outranking another | `origin` 2, `lane` 1 | `launch` 2, `origin` 1 | not run |
| A3 | Name a subcommand that prints store connections, asked for as whether the store is OK | `conns` 2, `connections` 1 | `connections` 3 | not run |
| A4, control | Name a subcommand that runs every doctor check | `health` 3 | `health` 2, `doctor` 1 | not run |

A1's old text reproduces the real failure, so that move is real. It is not the
operator's word: they took `holds`, which no run chose. `waits` is the name of the
package in the section's own text. The sitting had ruled it out ("it's already our
skill's name"), and `gc wait` uses the word for session waits. A1's list of native
commands did not name `gc wait`, and these calls have no tools to find it. With it
on the list, no filed run takes `waits`. So the entry moves a run off a collision
in front of it, and finds none it cannot see.

A2's and A3's old text writes no misleading name, so those cases show nothing about
the entry. All three filed A2 runs and one old run also give a reason for the word, in
a commit message or a spec the task did not ask for. A4 is the control for a general
name on a general command. Five of six runs keep `health`. One filed run takes
`doctor` and says "`health` would claim a reach wider than the doctor checks", so the
entry's words can move a name that fits.

## What reviewers did

Each cell counts runs with a finding on a name. The old text has no such entry, so
its column counts an objection under any entry, and the filed column counts findings
under the new one. Verdicts are not the measure, because other entries block most of
these cases on both texts, for counted sets, a missing platform search or a comment
that misstates its code.

### On codex, the provider of the real check

| Case | Source | Old text | Filed text | Filed, `gc.hold` out |
|---|---|---|---|---|
| R1, the design with `gctk bead blocked` | #1345 at 8fb013e89 | 0 of 3 | 0 of 9 | not run |
| R1c, the approved design, with `gctk bead holds` | #1345 at 4b324eb75 | 0 of 3 | 0 of 9 | 0 of 3 |
| R1d, R1c with the design's section on naming a verb | the same commit | not run | 0 of 9 | 0 of 3 |
| R2, `--level 1\|2` choosing between two peer check lists | made up | 1 of 3, under the entry on options | 3 of 3 | not run |
| R3, `health` for a count of store connections | made up | 0 of 3 | 3 of 3 | not run |
| R4, control: `health` that runs every doctor check | made up | not run | 0 of 3 | not run |
| R5, control: `gctk bead show`, byte for byte what `bd show` prints | made up | not run | 0 of 3 | not run |
| R6, control: a primary, and a secondary read only when it refuses | made up | not run | 0 of 3 | not run |
| R7, control: a new comment reusing the pack's `generated tier` | the pack's own lines | not run | 0 of 3 | not run |

### On Claude

| Case | Source | Old text | Filed text | Filed, `gc.hold` out |
|---|---|---|---|---|
| R1, the design with `gctk bead blocked` | #1345 at 8fb013e89 | 0 of 9 | 0 of 9 on the verb; 5 of 9 on a status: `held` 4, `blocked` 2 | 0 of 9 on the verb; 4 of 9 on a status: `blocked` 3, `held` 1 |
| R1b, only that verb's row and the adapter lines beside it | the same commit | 0 of 3 | 0 of 3 | not run |
| R1c, the approved design, with `gctk bead holds` | #1345 at 4b324eb75 | 0 of 3 | 9 of 9: `held` 9, `holds` 6, status `blocked` 3 | 5 of 9: status `blocked` 5, `held` 1, `holds` 0 |
| R1d, R1c with the design's section on naming a verb | the same commit | 0 of 3 | 9 of 9: status `blocked` 9, `held` 4, `holds` 2 | 7 of 9: status `blocked` 7, `held` 4, `holds` 0 |
| R2, `--level 1\|2` choosing between two peer check lists | made up | 1 of 3, under the entry on sketched names | 3 of 3 | not run |
| R3, `health` for a count of store connections | made up | 0 of 3 | 3 of 3 | not run |
| R4, control: `health` that runs every doctor check | made up | 0 of 3 | 0 of 3 | not run |
| R5, control: `gctk bead show`, byte for byte what `bd show` prints | made up | 0 of 3 | 0 of 3 | not run |
| R6, control: a primary, and a secondary read only when it refuses | made up | 0 of 3 | 0 of 3 | not run |
| R7, control: a new comment reusing the pack's `generated tier` | the pack's own lines | 0 of 3 | 0 of 3 | not run |

R2 and R3 are the cases the entry's own words name, and on both providers they move
from one run in six to all six. R7 shows that reusing an established word draws no
finding on either. The entry does not reach back over names already in the pack.

### The design the operator approved

R1c and R1d are the design at the head the operator approved (the reviews API reads
johnzook, 2026-10-30T00:41:51Z, at 4b324eb75). R1d is the fairness check on R1c, which
leaves out the design's own naming rule. On codex no run in any arm objects to a name
in either case, so the rest of this section is about Claude. A filed finding there
reads:

- R1c run 9: "The verb `bead holds` and the status `held` reuse the word of `gc.hold`, a passive note that leaves a bead live in `gc hook` and `bd ready`".

The sitting chose `holds` as "the vocabulary the helm board already speaks", where
"nothing native answers to the word", and the operator wrote "I can go with holds as
meaningful and unique". It treated status values as words already shared, and the
design says "A status value is the word the board's labels show for the same state".

All eight runs that object to `holds` name `gc.hold`, and so does every one of R1c's
nine. That key is not in use. Outside tests, specs and renders, the pack names it only
in two lines of rule tk-n7r69z in `template-fragments/work-quality-base.template.md`,
the fragment these reviewers read. No script or formula writes it, the gascity tree
has no hit for it, and no bead in any of the city's seven stores carries it as a
metadata key. So the runs learned the collision from that sentence. A reviewer with
tools could find this out, and these calls have none.

The last column holds the filed arm with `gc.hold` replaced by `hold` in those two
lines. Objections to `holds` go from 8 of 18 runs to 0 of 18. What remains, in 12 of
18, is the status `blocked`. Five of those runs also object to `held`, because the
verb `holds` in the same diff covers more than the status does:

- R1d run 9, with `gc.hold` out: "The status `blocked` reuses bd's word with a different meaning, as the diff itself says that `bd blocked` answers differently for work in flight and for a bead with a `waits-for` edge".

That is the collision the operator corrected on the verb, raised on a word the design
keeps on purpose as the board's. Whether it should change is a question for whoever
reads the finding, and no run has the board's labels in view. Giving the reason in the
change does not answer it in these calls. R1d's diff holds the design's sentence "A
status value is the word the board's labels show for the same state", and all nine
filed runs object to `blocked`, against three of nine on R1c. The same section's rule
that a verb whose answer can differ "gets a fresh word" gives some of them their
argument.

## Where the entry lives

The correctness check holds a diff to the `work-quality-*` fragments, and its method
names no other. `learned-conventions-polecat` is outside that list. Both polecat
prompts render it, though, and the polecat-codex pool runs every review with a recorded
route: all 539 in this rig's store since 2026-10-17, and all 256 read from four other
rig stores since 2026-10-01. So a reviewer carries those words in its prompt wherever
the entry lives.

Two arms measure what that does. Each is the old reviewer arm with the entry in the
conventions. "List open" keeps the arms' closing, "Report only what those entries
cover". "List named" closes with "Report only what the entries of the work-quality
fragments cover", which is nearer the method's own words.

| Case | Codex, list open | Codex, list named | Claude, list open | Claude, list named |
|---|---|---|---|---|
| R1c, the approved design | 0 of 3 | 0 of 3 | 3 of 3 | 0 of 3 |
| R1d, with its section on naming a verb | 0 of 3 | 0 of 3 | 3 of 3 | 0 of 3 |
| R2, `--level 1\|2` | 3 of 3 | 0 of 3 | 3 of 3 | 0 of 3 |
| R3, `health` | 3 of 3 | 0 of 3 | 3 of 3 | 0 of 3 |

With the list named, no run on either provider raises a name under those words (0 of
24). One codex R2 run still objects to `--level 1|2` under the entry on options, as one
old run does. With the list open, 18 of 24 do. A real review sits between the two: the
method names the fragments, and its fresh-eyes sweep, which takes a defect the hunt
missed, names none.

On A1 and A1b that placement chose the same words as the filed arm.
`docs/feedback-learning.md` keeps that carrier for a moment where "no reviewer sees the
moment it goes wrong", and a name shows in a diff, so placing it there departs from
that rule.

## Method

Every Claude call was `claude -p --model claude-opus-5-5 --tools "" --max-turns 1
--no-session-persistence --setting-sources "" --strict-mcp-config
--disable-slash-commands --output-format json --system-prompt "<arm>"`, from an empty
directory, with the case on stdin, `GC_*` and `BEADS_*` unset and
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. The 183 calls cost $8.93.

Every codex call was `codex exec --ephemeral --skip-git-repo-check --ignore-rules -s
read-only -C <empty directory> -m gpt-6.1-sol -c 'model_reasoning_effort="medium"' -c
"developer_instructions=<arm>"`, with the case on stdin, `GC_*`, `BEADS_*`,
`OPENAI_API_KEY` and the gh tokens unset, and an empty `GH_CONFIG_DIR`. That model is
the city's default for the codex provider and that effort is the host's. The 87 calls
used 1.84M input tokens, 1.27M of them cached, and 49k output tokens on the city's
ChatGPT login. Eight runs first looked for the diff's files in the empty directory and
found none.

A reviewer arm held a role line, the whole of `AGENTS.md`, the Work-quality standards
dimension cut from `skills/review-correctness/SKILL.md`, the work-quality fragments
(base, human, polecats, system) and the exemplar corpus. It then asked for each
violation with the entry's words and a closing verdict line. An author arm held a role
line and the same files, and asked for the text to commit. The old arms took those
files from cb2863f27 and the filed arms from 2af4376e3. They differ only by the entry.
The convention arm is the old author arm plus `learned-conventions-polecat` with the
entry appended, and the two reviewer convention arms are built the same way. The
"`gc.hold` out" column is the filed arm with the two-line change described above.

R1 holds lines 91, 345 to 347 and 392 to 420 of `docs/gctk-architecture.md` at
8fb013e89, the last commit before the rename, as added lines. R1b holds lines 91 and
345 to 347. R1c holds the same three pieces at 4b324eb75, and R1d adds that head's
section "The rule that names a verb". A1 gives R1's section with the verb's name
blanked out, and A1b adds one clause naming `gc wait`. On Claude R1, A1, and the filed
cells of R1c and R1d have nine runs because the headline rests on them, and on codex
the filed cells of R1, R1c and R1d do.

The `gc.hold` search was `git grep -E 'gc\.hold([^_a-z]|$)'` in this tree, leaving out
tests, specs and renders, and in the gascity rig's checkout, and
`gc bd list --has-metadata-key gc.hold --all` in each of the city's stores.
`gc.hold_demand` is a different key, and it is in use.

I read every author run's choice and every reviewer run's findings, and classed each
by reading it. A search for the entry's words finds a run only if it quotes the clause
searched for, and several runs quote only a later one, so no count here rests on a
script.

## Limits

- A real review has tools, the whole diff and a step that can drop a finding. These
  calls see a hunk, and no case shows the board's `held:` labels. So these counts say
  what a reviewer raises, and say nothing about what would survive that step.
- A real author has a far longer prompt and tools, and could find `gc wait`.
- Author runs are on Claude only. The polecat-codex pool can also claim implementation
  work, and its authors were not measured.
- The real evidence here is one public correction. The pattern's other corrections
  are on a private repository, so no case uses them. The made-up cases come from the
  entry's own words.
- Three runs a cell is thin, and only the cells named in the method have nine.
- The correctness check reads the fragments from the installed pack, so the entry
  does not judge the effort's own PR.

## The made-up cases

Each is the text the runs received.

### R2

```text
Purpose of the change: a doctor run on a host with no city store should not have to open that store, so the runner can run the checks for one store at a time.

--- a/tools/doctor-run.sh
+++ b/tools/doctor-run.sh
@@ -12,6 +12,13 @@ usage() {
   doctor-run.sh [--json] [--quiet]
+  doctor-run.sh --level 1|2 [--json] [--quiet]
+
+      --level 1   run the checks that read the city store
+      --level 2   run the checks that read the rig store
+
+      The two lists share no check, neither runs the other's, and a failure
+      in either fails the run the same way.
 }
@@ -41,6 +48,11 @@ parse_args() {
+case "$LEVEL" in
+  1) CHECKS=$(checks_for_store city) ;;
+  2) CHECKS=$(checks_for_store rig) ;;
+  "") CHECKS=$(all_checks) ;;
+esac
```

### R3

```text
Purpose of the change: agents need to read how many store connections are in use before a heavy query.

--- a/tools/city.sh
+++ b/tools/city.sh
@@ -8,6 +8,7 @@ usage() {
   city.sh rigs       list the city's rigs
   city.sh sessions   list live sessions
   city.sh orders     list the orders and their last run
+  city.sh health     print the store connections in use and the limit
 }
@@ -30,6 +31,9 @@ case "$1" in
   orders)   list_orders ;;
+  health)
+    store_connections_in_use "$PORT"
+    ;;
 esac
```

### R4

```text
Purpose of the change: the operator wants one command that says whether the city as a whole is well.

--- a/tools/city.sh
+++ b/tools/city.sh
@@ -8,6 +8,7 @@ usage() {
   city.sh rigs       list the city's rigs
   city.sh sessions   list live sessions
   city.sh orders     list the orders and their last run
+  city.sh health     run every doctor check and print one overall pass or fail
 }
@@ -30,6 +31,9 @@ case "$1" in
   orders)   list_orders ;;
+  health)
+    run_all_doctor_checks --summary
+    ;;
 esac
```

### R5

```text
Purpose of the change: gctk gains the bead read agents already use, so they need not work out which store holds a bead first.

--- a/docs/gctk-architecture.md
+++ b/docs/gctk-architecture.md
@@ surface table @@
+| `gctk bead show <bead>` | agent | what `bd show <bead>` prints, byte for byte, from the store that holds the bead | `bd show` answers only from the store it is pointed at, so a caller has to find the store first. This finds it and hands the read to `bd show`, whose answer it never changes. |
```

### R6

```text
Purpose of the change: a store read goes on working while the main store server restarts.

--- a/tools/store-read.sh
+++ b/tools/store-read.sh
@@ -5,6 +5,12 @@
+# Every read goes to the primary. The secondary is a read-only replica that
+# lags by up to a minute, and it is read only when the primary refuses the
+# connection.
+PRIMARY_PORT="${STORE_PRIMARY_PORT:-32831}"
+SECONDARY_PORT="${STORE_SECONDARY_PORT:-32832}"
+
 read_row() {
-  dolt_query "$PORT" "$1"
+  dolt_query "$PRIMARY_PORT" "$1" || dolt_query "$SECONDARY_PORT" "$1"
 }
```

### R7

```text
Purpose of the change: say why a conflicted render owes no audit entry when a merge also moved its source.

--- a/assets/scripts/bring-current-guard.sh
+++ b/assets/scripts/bring-current-guard.sh
@@ -77,6 +77,8 @@
 # are named as such. Paths in the generated tier (linguist-generated in
 # .gitattributes) are renders the pack writes and nobody edits by hand, and
 # merge.sh refuses a merge whose seed-audit render is not current, so they owe
 # no entry and are listed as evidence only.
+# A path in the generated tier stays exempt when the same merge also moves its
+# source, because the render is written again from that source.
@@ -186,3 +188,3 @@
 # NUL-separated paths on stdin; prints those .gitattributes at <commit> does not
 # mark linguist-generated (the reviewed tier) to stdout and the generated ones to
 # <generated-file>, both NUL-separated. An attribute read that fails exempts
```

### A2

```text
The city's sessions fall into three sets by how they start: sittings a person attends, pool workers, and order runs. Add a limit on concurrent sessions for each set to the pack config in pack.toml. No set outranks another: when one set reaches its limit, the controller stops starting sessions in that set only, and the other two go on as before.

The config, the controller's log lines, the board and the docs will all need one word for which of these sets a session is in, so choose that word and the name of each set. Write the TOML, one log line, and the paragraph for docs/sessions.md that explains it.
```

### A3

```text
Agents need a quick way to see whether the city's store is OK before a heavy read. In practice that means the number of store connections in use, against the limit. Add a subcommand to tools/city.sh that prints those two numbers. Its subcommands are one short word each: rigs, sessions, orders. Write the usage line and the case arm, calling a helper named store_connections_in_use, and choose the subcommand's name.
```

### A4

```text
The operator wants one command that says whether the city as a whole is well: it runs every doctor check and prints one overall pass or fail. Add a subcommand to tools/city.sh. Its subcommands are one short word each: rigs, sessions, orders. Write the usage line and the case arm, calling a helper named run_all_doctor_checks, and choose the subcommand's name.
```
