---
name: The accommodation check replayed on #1376's first head
description: Read it to check the done-when replay in tk-7js3qft's summary, to see what the arch check's fifth check asked of #1376 at 71e22021 and what the text before it let through, or to re-run the replay on a later wording.
---

# The accommodation check replayed on #1376's first head

tk-7js3qft's second done-when item asks that a reviewer run of the new lens
text on #1376's reviewed head, 71e22021, send it back for the untested reason,
and that a run of the current text not do so. This replay ran the arch check
three times under each text, holding everything else the same.

| Run | Verdict | Finding: the skip's reason is untested here | Finding: the fix at the source is owed | Other findings |
|---|---|---|---|---|
| current 1 | request-changes | no | no | search not shown; no gctk sentence |
| current 2 | request-changes | no | no | search not shown; no gctk sentence; two deferred |
| current 3 | request-changes | no (noted, left to correctness) | no | search not shown; no gctk sentence; one deferred |
| new 1 | request-changes | yes | yes | search not shown; no gctk sentence; one deferred |
| new 2 | request-changes | yes | yes | search not shown; no gctk sentence |
| new 3 | request-changes | yes | yes, as a finding of its own | search not shown; no gctk sentence |

Every run under the new text sent the change back because the reason Gas City
gives for skipping a suspended rig's store was never tested in this city. Each
quoted that reason from upstream's `mol-dog-backup.sh` ("nothing writes to it
while it is suspended") and asked for a census of the writes the three
suspended stores took. One run put it this way: "The commit measures alarm
firings (291 occurrences), not the writes the suspended stores took while
skipped, which is the census that tests that reason." Each also asked for the
fix at the source and a bead filed for it where the `gc-toolkit.external-issue`
skill sends it, two of them for the fix's size as well. Every new run put
the operator's 2026-10-30 ruling in `needs_you`, because that ruling accepted
the skip while it was unclear whether those stores took writes.

No run under the current text raised it as a finding. The third saw the
contradiction and handed it on: "Correctness is left to the correctness check:
whether a suspended store can still take writes ... The commit says a suspended
store can still take writes. Upstream's `mol-dog-backup.sh` comment says
nothing writes to it while it is suspended." The text it held gave the arch
check no ground to hold the change for it. The real lane at that head (review
tk-hpz40my) raised one finding, the missing search (tk-h5f44bf), as all three
current runs did.

## Method

- **The change under review.** A `git archive` of 71e2202185f1, the first
  commit of `polecat/tk-vqexoxe`, with `AGENTS.md`, `docs/review-arch.md` and
  `docs/review-triage.md` laid over it from each arm: main at 3ee4ea590 for the
  current text, and 6afcadd86 on this branch for the new text. The change is
  `git diff f6965764bc0f 71e2202185f1` and that commit's message. No pull
  request was open at that head, so the anchor's description, the Dispatch
  section of #1376's body as first published, says what the change is for.
- **The method.** The pack's `review-arch`, `specialist-stance` and
  `architecture-document` skills as main carries them at 3ee4ea590, the same in
  both arms.
- **The prompt.** It follows the lane step of `formulas/mol-pr-review-lane.toml`:
  the arm's `AGENTS.md` as the project's instructions, the method, then what
  `review-run.sh lane` prints (the anchor, the rig's guidance for arch, the
  change), and the lane's output fields. The two arms' prompts differ only in
  the changed text.
- **Gas City beside it.** `gastownhall/gascity` at main d1a150cac8f8, the commit
  #1376's own search later cited, read-only through `--add-dir`. Its
  `examples/bd/dolt/assets/scripts/mol-dog-backup.sh` states the skip's reason
  beside the rig-list filter.
- **The run.** A clean headless Claude Opus 5.5 run per review, with no memory,
  hooks, skills or MCP and file tools only, in the arm's snapshot:

  ```bash
  env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Users/gc/.local/bin \
    TMPDIR="$TMPDIR" LANG=en_US.UTF-8 \
    claude -p --safe-mode --restricted --strict-mcp-config --disable-slash-commands \
      --no-session-persistence --permission-prompts none --tools "Read,Grep,Glob" \
      --model claude-opus-5-5 --max-turns 80 --output-format stream-json --verbose \
      --add-dir <gascity snapshot> < <arm prompt>
  ```

  Six runs ran in parallel on 2026-11-23 from 10:57:26Z to 10:58:57Z. Each took
  11 to 22 turns and 60 to 90 seconds. Together they read 3.46M input tokens,
  3.22M of them from cache, and wrote 48k output tokens.

## What this shows and what it does not

- The new text reaches the case it was written from. Its examples, an alarm that
  leaves out what one of Gas City's orders skips and a census of the writes a
  skipped store took, describe this case, so the replay does not show that the
  check reaches an accommodation unlike it.
- The new text's fifth check moved each run from no finding to a blocking one on
  this head. All six runs request changes either way, because the search is
  missing here, so the replay shows the check's finding, not a verdict that
  turns on it.
- Laying main's `AGENTS.md` over a 2026-10-31 snapshot gave every run, in both
  arms, a rule that did not exist then: a new script says why gctk cannot hold
  its logic. Three runs also deferred a link to `docs/gctk-architecture.md`,
  which the snapshot predates. Both arms carry these alike.
- A clean run cannot run a command, so no run looked a bead up, as the fifth
  check asks. A lane in the city can.
- After the replay, check 5 gained "its size" beside the fix at the source, which
  `AGENTS.md` already asked for. The text the runs read is 6afcadd86.
