Formula: mol-refinery-patrol
Description: Refinery patrol loop. Poured as a root-only wisp on startup:

  gc bd mol wisp mol-refinery-patrol --root-only --var target_branch={{target_branch}} --var rig_name={{rig_name}} --var binding_prefix={{binding_prefix}} --var default_merge_strategy={{default_merge_strategy}} --var escalation_cooldown={{escalation_cooldown}}
  gc bd update $WISP --assignee=$GC_AGENT

Each wisp is ONE iteration: check for work, merge one branch, pour
the next iteration. On crash, re-read the formula steps and determine
where you left off from context (git state, bead state, last action).

Formula steps are NOT materialized as child beads. Read the step
descriptions below and work through them in order.

The loop mechanism: every exit path (happy or early) pours the next
wisp before burning this one. The prompt only bootstraps the first wisp.

Work beads flow directly: pool → polecat → refinery → closed.
No separate MR beads. The polecat sets metadata (branch, target) on
the work bead and assigns it to the refinery. On rejection, the
refinery puts the bead back in the pool with rejection metadata.

Merge strategy is per-work-bead metadata:
- `direct` (default): fast-forward merge to target and push
- `mr` / `pr`: publish a GitHub pull request instead of landing directly

In `mr` mode, refinery does NOT land the branch directly. It publishes a
pull request, records the PR on the anchor bead, and transitions it to a
GATING state — it stays OPEN. The anchor closes later, on a verified merge to
its target (close-on-land), reconciled in the find-work idle loop. The anchor
is typically a CONVOY graduating its branch to the target (every PR is an
owned convoy; see docs/work-bead-state-machine.md), but the mechanism is the
same for any mr-mode bead. Stock GasTown closes at PR-creation; this pack
keeps the bead open so `closed` always means landed.

## Escalation discipline — read this before ANY `gc mail send`

This applies to every step, not just the ones that document an escalation
command.

You re-derive your triggers from live state on every idle wake, and a PR
waiting for the operator's signature keeps re-deriving true for as long as
the operator is away. Mailing on each pass is how a queue of TWO blocked
PRs produced EIGHT near-identical escalations in 2h (2026-08-09/10,
signal-loom), and two more on 2026-08-13 against zero landings. The
subjects varied only in the count as PRs accumulated — "3 CI-green PRs
held", "6 merge-ready PRs blocked", "7 PRs green but parked" — so nothing
was actionable differently at mail 8 than at mail 1.

**A PR awaiting operator approval is a HEALTHY state, not an anomaly, and
the number of escalations it is worth is ZERO.** It cannot change without
a GitHub-side event, the city structurally cannot approve its own PRs,
and the operator reviews the queue on their own cadence — that IS the
workflow, not a backlog anyone is unblocking. Telling them about it tells
them nothing they did not already know.

This paragraph used to end "so the escalation is worth sending exactly
once", which does not follow from its own premise: a state that is not an
anomaly does not warrant one mail either. Exactly-once was not even a
bound. The gate's stamp is keyed on the ANCHOR, so "once per PR" is a
toll that scales with throughput — signal-loom's refinery was corrected
about PR #541 and then escalated PR #544 hours later, a different anchor
at a different head and so genuinely new to every fingerprint the gate
compares. The better this city gets at producing PRs, the worse the drip
(tk-qe2tv).

**You do not have to remember this.** `escalation-gate.sh` REFUSES the
class outright when the held-anchor block below hands it `--pr`: it
re-reads the PR itself and sends nothing if GitHub says the PR is
mergeable, green on every check that gates its merge, unobjected-to and
merely unapproved. A refusal exits 0,
prints `REFUSED`, and stamps nothing. It is not the gate failing and it
is not a licence to mail anyway — there is nothing being held back to
retry.

**What still escalates, and must.** The class is narrow, and the gate
proves each of these is outside it rather than trusting you to:

- a PR that is APPROVED and green and still not landing — that is a real
  fault, and the remedy is not a signature;
- a head move that strands a gate (`check.<name>=green@<old-head>` on the
  anchor while the PR sits at a newer head);
- a merge that errors, or a PR GitHub reports as CONFLICTING;
- a failing or still-running REQUIRED check, a CHANGES_REQUESTED review, a
  draft, a closed PR. The gate asks `gh pr checks --required`, which is
  GitHub's own answer to which checks gate this merge and what each one's
  CURRENT run said — so an ADVISORY check that is red is not a hold (it
  cannot block the merge), and a required check that failed and was re-run
  green is green (tk-ayt0n);
- an anchor a previous pass already blocked — `blocked_reason` or
  `merge_result=blocked`, which is where "Existing PR metadata needs
  human correction" lands.

**The cost is burial, not volume.** Those duplicates pushed the mayor's
inbox to 19 unread, and two escalations that genuinely needed a mayor
decision were TIME-BOXED and sat between them: a convoy duplicate
disposition that expired after ~5.5h when one of its three options merged
out from under it, and a false graduation hold that would have proposed
reverting 5 landed PRs. High-value escalations competing with a repeating
low-value one is the actual failure. Each `gc mail send` is also a
permanent bead plus a Dolt commit, billed for as long as the human is away.

**Any escalation that is ABOUT A BEAD goes through the gate instead of
straight to `gc mail send`:**

```bash
# >>> escalation-wiring-discipline
SCRIPTS_DIR=""
for cand in "${GC_RIG_ROOT:-}/assets/scripts" "$(git rev-parse --show-toplevel 2>/dev/null)/assets/scripts" "${GC_CITY_PATH:-}/rigs/gc-toolkit/assets/scripts"; do
  if [ -x "$cand/escalation-gate.sh" ]; then SCRIPTS_DIR="$cand"; break; fi
done
BODY="Observation: <what you found>
Recommendation: <what should happen>"
if [ -n "$SCRIPTS_DIR" ]; then
  if ! "$SCRIPTS_DIR/escalation-gate.sh" --anchor "<bead-id>" --kind refinery --state "<what is HOLDING it>" --cooldown "{{escalation_cooldown}}" --subject "<subject>" --body "$BODY"; then
    echo "refinery: escalation-gate did not send (see its stderr); NOT falling back to a bare mail. Next cycle retries." >&2
  fi
else
  gc mail send mayor/ -s "<subject>" -m "$BODY" || echo "refinery: fallback 'gc mail send' failed; next cycle retries." >&2
fi
# <<< escalation-wiring-discipline
```

It mails the first time, then stays quiet until `--state` changes or the
cooldown elapses. It suppresses REPETITION, never news — with one class it
declines outright rather than deduping, the mergeable-and-merely-unapproved
PR described above, and only where the held-anchor block names the PR. A rig
that has not synced the script falls back to mailing directly — the old
behavior, not a dropped escalation.

**`--kind refinery`, always.** The gate's default kind is `witness`, and
one anchor + kind = one open escalation. The witness escalates about these
same anchors (PR #35: five witness mails, two refinery ones), so sharing a
kind would let whichever role got there first mute the other. The kind
names the sending ROLE, never the topic — splitting "queue health" and
"stranded PR" into separate kinds just restores the storm one framing at a
time.

**Gate PER ANCHOR, not per queue.** The tempting reading of those eight
mails is "fingerprint the whole gating set". Do not: adding a fourth PR to
a set of three changes a set fingerprint, so the whole set re-mails and
the three unchanged PRs are re-escalated for the fourth's sake — which is
exactly the observed pattern where the subject line was just a rising
count. One gated call per held anchor gives each PR one mail, and a newly
blocked PR speaks only for itself. Per-rig namespacing comes free: the
stamp lives on the anchor bead, and anchors are rig-scoped, so the four
co-tenant refineries on this host cannot collide.

Keep the resolution loop in the SAME shell as the send. Each tool call is
a fresh shell, so a `SCRIPTS_DIR` you resolved earlier is gone, and an
empty one expands to `/escalation-gate.sh` — which fails and sends
nothing. Only the gc-toolkit rig has its own `assets/scripts`; the other
three resolve through the `GC_CITY_PATH` candidate.

A non-zero exit from the gate is NOT fatal and NOT a licence to mail
anyway. A NON-ZERO exit means one thing only — it could not bound the
escalation (unreadable anchor, unwritable stamp) — and mailing past that
is the unbounded storm. Log it, keep patrolling, let the next cycle retry.
That is why the call above is wrapped in `if ! ...; then echo` rather than
run bare: the idle reconcile is a best-effort pass and must reach its
later passes.

**"Next cycle retries" is only true while the TRIGGER survives the pass.**
Most escalations here are RE-DERIVED from live state — a held anchor is
still held, a capped signoff is still capped, an unsupported
`merge_strategy=local` still refuses to merge and deliberately transitions
nothing — so the next idle wake genuinely re-derives them and calls the
gate again. `block_existing_pr` is the exception: it writes
`merge_result=blocked` and `assignee=""` in the same breath, and the
find-work query excludes both, so the pass that escalates is also the pass
that clears the trigger. That one says BEST-EFFORT and does not print a
retry promise the code cannot keep. It is deliberately NOT the
`ORPHAN_CLOSED` shape — withholding the block to protect a mail would
leave a bead with invalid PR metadata being re-selected and re-processed
every cycle, and the durable record already outlives the mail: the reason
is on the bead in `blocked_reason` with `gc.routed_to=human`.

A refusal message that promises a retry which cannot happen is worse than
one that admits the loss — it reads as handled in the patrol log.

Things that are easy to get wrong:

- **Do not reword your way past it.** Reaching for `gc mail send` directly
  because "this framing is new" IS the bug. The gate keys on the ANCHOR
  and the channel, never on the message, precisely so rephrasing cannot
  reopen the storm.
- **Put the real hold inputs in `--state`.** Head oid, `reviewDecision`,
  `mergeStateStatus` — whatever would make you say "this is genuinely
  different now". That fingerprint is what lets real news through
  immediately, so a lazy `--state` turns the gate into a mute.
- **Sanitize any `gc bd show --json` you build `--state` from:**
  `gc bd show <bead> --json 2>/dev/null | tr -d '[:cntrl:]'`. jq rejects
  every unescaped control character — including a plain tab, which prose
  notes do contain — and a failed parse leaves `--state` EMPTY, which the
  gate reads as "no state tracked" and suppresses real news for a whole
  cooldown. A lost parse must not look like a lost fingerprint.
- **Never pass an EMPTY `--state` when you meant to track state, and never
  substitute a differently-shaped one on the same `--kind`.** A substitute
  (the bead's fields standing in for a PR's, because `gh pr view` failed)
  compares unequal in BOTH directions, so the item mails when the outage
  starts and again when it ends — a flap through the cooldown driven by
  GitHub's availability rather than by news. Send that observation on its
  own channel (`--kind refinery-degraded`, with a value naming what is
  unavailable and nothing that varies while it is) and leave the real
  channel's stamp alone. The held-anchor block in `find-work` does this;
  copy that shape.
- **Never put a timestamp in `--state` — least of all the anchor's own
  `updated_at`.** The gate stamps `escalated.<kind>` ON THE ANCHOR before
  it mails, and that write bumps `updated_at`. A fingerprint containing it
  differs on the very next pass *because the gate ran*, so an unchanged
  item re-mails forever: the storm, now with a dedup step in front of it.
  Fingerprint only inputs the gate does not itself write — `status`,
  `merge_result`, `branch`, the landing target (`merged_target // target`,
  the pre-open order), the `check.<gate>` markers, the PR's own fields.

`--cooldown "{{escalation_cooldown}}"` is passed on every gated call, and
every pour of the next wisp forwards the var — both halves are needed for
a configured value to be honored end to end. The call alone only honors it
for one cycle: a `--root-only` pour materializes no defaults, so a value a
pour drops arrives unrendered at the next wisp and every later cycle
silently runs the script's own 24h default instead. Where the var was
never set at all it still arrives unrendered, and the script recognizes
that shape and falls back to that default rather than failing the send.

`--force` is for a situation that truly worsened in a way the fingerprint
does not capture. Using it every cycle is the storm again.

Suppressed escalations still print a verdict line — the item is still
held, and your patrol log still says so. Silence toward the mayor is not
silence in the log.

**The rule is enforced, not merely documented.**
`assets/scripts/refinery-escalation-wiring.test.sh` scans this file for
every `gc mail send` and fails on any that is neither inside a gated
`escalation-wiring-*` block nor on its exception list. Exactly one is
exempt: the `validate-identity` empty-`GC_AGENT` escalation, because it
fires before any work bead is selected and there is no bead to key a stamp
on — and it exits the session, so it cannot re-fire on a cadence anyway.
Every other escalation here is bead-scoped and gated. Adding a second bare
bead-scoped mail fails that test — gate it instead, or the storm comes
back through the new one.

Regression test for the gate itself:
`assets/scripts/escalation-gate.test.sh` (hermetic; stubs `gc`, covers the
subject-drift case, state-change and cooldown re-opening, stamp-before-mail,
and the refuse-to-send-when-unbounded rule).

Read each step's description before acting — Config values override defaults.

Variables:
  {{auto_ff_rig_main}}: After a successful direct merge, attempt to fast-forward the rig's canonical checkout (\$GC_RIG_ROOT) when it is on the target branch with a clean tree. Best-effort; never blocks the merge. (default=true)
  {{binding_prefix}}: Import binding prefix for gastown agent identities, including trailing dot when bound. (default=)
  {{build_command}}: Build command (e.g., go build ./...). Empty = skip. (default=)
  {{check_set}}: Merge gating check-set for mr-mode PRs: a comma-separated list of gate names that must each be green at the live head before the merge fires. Each gate records a per-gate marker check.<name>=green@<sha> on the gating anchor, and merge-skill.sh holds the merge until every named gate is green at the live head. 'codex' dispatches a review bead to the rig's codex polecat pool as a check-set member. 'approval' is the one member evidenced by GitHub review state instead of a stamped marker (merge-skill.sh drops it from the marker loop, the way it drops the 'none' sentinel, since nothing can stamp check.approval). It requires an APPROVED latest-review that is ALL THREE of: (a) attached to the PR's LIVE head — an approval of an earlier commit re-gates exactly like a stale check.<name>=green@<old-sha>, so any push after the approval re-arms the gate; (b) from an account other than the one the city acts as (the city posts COMMENT signoffs and never approves its own PRs); and (c) from a TRUSTED approver, which is a stronger bar than merely non-self — on a public repo any account can submit an APPROVED review, and this gate matters precisely where GitHub enforces nothing server-side. Trust has two policies: when MERGE_TRUSTED_APPROVERS is set in the refinery's environment (comma-separated logins) that allowlist IS the policy and no permission probe runs; otherwise the approver must hold admin/maintain/write permission on the repo (read from repos/{owner}/{repo}/collaborators/<login>/permission). Anything else HOLDS the merge, fail-closed — including a permission probe that cannot be READ, since unreadable is indistinguishable from 'no access' and guessing lands unreviewed work. Separately from this member — and from check_set entirely — a standing CHANGES_REQUESTED from ANY non-self reviewer vetoes the merge on EVERY PR, whoever approved: one reviewer's approval does not answer another's unresolved objection, and a rig that never declares 'approval' is not a rig where a human's 'not this' stops counting (tk-bdfww). Unlike the approval the veto is not head-bound — an objection stands until its author supersedes it or it is dismissed. If the refinery's token cannot read collaborator permissions, set MERGE_TRUSTED_APPROVERS rather than leaving the gate permanently held. Declare 'approval' on a rig whose repo does NOT require reviews — there mergeStateStatus=CLEAN is true with zero approvals, so without it merge-skill.sh will land unreviewed work (tk-5niup). It is also armed automatically, whatever check_set says, on an anchor carrying signoff_dismissed (the re-gate retracted the city's own blocking review, so CLEAN is partly our own doing). To run a rig GATELESS, set the explicit sentinel 'none' (or 'off'): the merge-push step normalizes it to the canonical 'none', which is STAMPED on the anchor and which merge-skill.sh reads as 'no gates' (merge then governed only by CI + no-open-child + whatever mergeStateStatus=CLEAN folds on that repo). An EMPTY value is NOT an opt-out — it is treated as absent and recovers this default, because {{check_set}} is hand-substituted from raw TOML on the --root-only patrol path and a mis-substitution would otherwise silently un-gate every PR (tk-4na1b). The sentinel is stamped rather than collapsed to empty so that 'gateless by choice' and 'never normalized' are DISTINCT on the anchor: a hand-recovered bead bypasses this formula entirely and arrives carrying an empty check_set, which check-set-heal.sh repairs at the refinery boundary before the merge skill can read it as ungated (tk-i48ca). Replaces the retired review_gate string + signoff_head side-channel. (default=codex)
  {{default_merge_strategy}}: Default when bead metadata.merge_strategy is unset. 'direct' = FF + push to target. 'mr'/'pr' = open pull request. (default=mr)
  {{delete_merged_branches}}: Whether to delete source branches after merge (default=true)
  {{escalation_cooldown}}: Seconds before an UNCHANGED situation may be escalated again (see 'Escalation discipline'). A CHANGED state fingerprint always re-escalates immediately, so this bounds repetition only, never news. Default 24h: at the 60s idle cadence that is a 1440x reduction on an approval-gated queue, while still resurfacing it daily so it cannot fall silent. Lower it only if a real escalation was noticed too late — not to make the patrol chattier. (default=86400)
  {{integration_branch_auto_land}}: System-auto convoy graduation. When an OWNED integration convoy's members are all closed AND the ledger records at least one merge onto its integration branch, the refinery assigns the convoy bead to itself and lands integration->main through the same work-bead machine (a human-approved PR). Default on; set 'false' as a kill-switch. Non-owned auto-convoys (per-sling tracking bundles) are never affected. (default=true)
  {{lint_command}}: Lint command (e.g., eslint .). Empty = skip. (default=)
  {{run_tests}}: Whether to run tests before merging (default=true)
  {{setup_command}}: Setup/install command (e.g., pnpm install). Empty = skip. (default=)
  {{target_branch}}: Default target branch for merges (default=main)
  {{test_command}}: Test command to run (if run_tests is true) (default=)
  {{typecheck_command}}: Type check command (e.g., tsc --noEmit). Empty = skip. (default=)

Steps (10):
  ├── mol-refinery-patrol.validate-identity: Validate canonical agent identity
  ├── mol-refinery-patrol.check-inbox: Check mail [needs: mol-refinery-patrol.validate-identity]
  ├── mol-refinery-patrol.find-work: Find next work bead assigned to me [needs: mol-refinery-patrol.check-inbox]
  ├── mol-refinery-patrol.rebase: Rebase branch on target [needs: mol-refinery-patrol.find-work]
  ├── mol-refinery-patrol.run-tests: Run quality checks and tests [needs: mol-refinery-patrol.rebase]
  ├── mol-refinery-patrol.handle-failures: Handle quality check or test failures [needs: mol-refinery-patrol.run-tests]
  ├── mol-refinery-patrol.merge-push: Merge and push [needs: mol-refinery-patrol.handle-failures]
  ├── mol-refinery-patrol.patrol-summary: Record patrol cycle summary [needs: mol-refinery-patrol.merge-push]
  ├── mol-refinery-patrol.next-iteration: Prepare next patrol iteration [needs: mol-refinery-patrol.patrol-summary]
  └── mol-refinery-patrol.workflow-finalize: Finalize workflow [needs: mol-refinery-patrol.next-iteration]
