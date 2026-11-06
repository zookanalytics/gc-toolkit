---
name: Gas City search for the refinery's re-run of a required check that failed for a non-code cause
description: The search the arch check asks for before the pack adds surface of its own. What Gas City, the packs it publishes and bd ship for re-running a GitHub Actions job that timed out, was cancelled or failed to start, and for recording that the re-run was made at a PR's head, read at named upstream commits, and why none of it covers the re-run pr-facts.sh's red-check arm makes or its pr_check_rerun key. Read it when checking whether that re-run still needs to be the pack's own.
---

# Gas City search for the refinery's re-run of a timed-out required check

This change adds pack surface. pr-facts.sh's red-check arm gains an act: when
every failing required check timed out, was cancelled or failed to start in a
GitHub Actions run, it re-runs the failed jobs of each run with
`gh run rerun <id> --failed`, once per PR head. The anchor gains a metadata
key, `pr_check_rerun`, which holds the head that re-run was made at. So the
arch check asks what Gas City already ships for each need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

The rest of the change composes what the pack already has. Parking only an
approved PR reads the approval rule review-verdict.sh defines. Clearing the
park route when its gate is withdrawn is a `--route ""` write through
lifecycle.sh. Neither adds surface.

The search found nothing that re-runs a check. Gas City's own PR monitor counts
a timed-out or cancelled check as a failed one and mints repair work for it.
bd's `gh:run` gate waits on a run and escalates a cancelled one to a person,
which is the behavior this change replaces. No published pack re-runs a check.
The record is bd's own primitive, a metadata key on the bead.

## What was read

- `gastownhall/gascity` at 9f807760c1914a79326c35029e0a9c1600d14ee8, a local
  clone's `upstream/main`. Upstream `main` was
  8e75c50aa84540eaaf185db3cb9b103d04d6aa3f when this was read on 2026-11-06,
  and the six commits between them change none of the files cited below.
- `gastownhall/gascity-packs` at 796d7ecd73cf36792e5aa8ec771bcc33ee68cd00, its
  `HEAD` when read, every pack in it.
- `gastownhall/beads` at ac3416ced777f1a25d6c910bce1781241ec1757b, upstream
  `main` when read.

## Re-running a check that failed for a non-code cause

- **Gas City's GitHub PR monitor.** The
  [GitHubPRMonitor](https://docs.gascity.com/reference/config#githubprmonitor)
  config "declares how one repository/base-branch set is monitored and where
  durable repair work should be routed when readiness fails". In package
  `internal/githubmonitor`, `checkFailed` counts a check concluded `CANCELED`,
  `TIMED_OUT`, `STARTUP_FAILURE`, `ACTION_REQUIRED` or `STALE` as failed, the
  same as `FAILURE`, and `classifyPullRequest` then reads the PR as
  `checks_failed`, actionable, which routes repair work to the monitor's
  `repair_route`. It cannot tell a timeout from a code failure. Nothing in
  `internal/githubmonitor/client.go` or `cmd/gc/cmd_github.go` calls GitHub's
  re-run endpoint: neither names `rerun` or `actions/runs`.
- **Webhook rules.** A
  [WebhookRule](https://docs.gascity.com/reference/config#webhookrule) "maps
  one verified provider event to a dispatch target". It starts work in the
  city and does nothing at GitHub.
- **bd's `gh:run` gate.** `bd gate check`'s help in `cmd/bd/gate.go` says a
  `gh:run` gate reads `gh run view <id> --json status,conclusion`, is resolved
  when the run completed with conclusion success, and is escalated when it
  completed with conclusion failure or canceled. It waits on a run and never
  re-runs one, and its answer to a cancelled run is an escalation to a person.
- **The `core` pack Gas City bundles.** No order or formula under
  `internal/bootstrap/packs` re-runs a check. A search there for `gh run`,
  `rerun`, `re-run` and `actions/runs` finds only prose: re-running a pre-flight
  in `mol-polecat-base`, re-running a step in `mol-prompt-synth`, and the
  controller's autoclose sweep in `convoy-autoclose-backstop`.
- **The published packs.** No pack in `gascity-packs` calls `gh run rerun`, the
  `rerun-failed-jobs` endpoint or a `--failed` re-run. The `pr-review` pack's
  `mol-pr-ci-diagnose` formula classifies each failed check from its log, a
  timeout among the categories, and writes a `failing_infra` verdict to the
  run's notes. It is read-only by its own description and re-runs nothing. Its
  `mol-adopt-pr` and `mol-pr-merge-only` formulas stop at a CI failure, report
  it, and wait for a nudge or a human gate.
- **Gas City's own repository.** `.github/workflows/advisory-probes.yml`
  mentions the "adopt-pr gate's infrastructure rerun". That is the repository's
  own CI tooling, which no gc or bd binary and no bundled pack ships.

## Recording that the re-run was made

The arm needs to know, at a later pass, whether it already re-ran the failed
jobs at the PR's current head. That record is a fact about one anchor, and bd's
primitive for such a fact is a metadata key on the bead (`bd update
--set-metadata`), which the arm writes through lifecycle.sh as it writes its
sibling `pr_unengaged_threads`. A `gh:run` gate could stand for the re-run while
it runs, but the arm needs no wait: the re-run's new attempt takes the failed
row's place in the PR's status check rollup, so a pass during it reads the check
pending. A gate closes when its run ends and does not say which head was
re-run, which is the one thing the arm reads.

## Warrants

The change adds no bead kind and no lifecycle state, so it adds no pack noun and
no warrant ([review-arch.md](../../docs/review-arch.md#the-checks), check 2).
Two warrants in [warrants.md](../../docs/warrants.md) name parts of
pr-facts.sh: "Owed status label clear" names `clear_status_label` and its retry
section, and "Unanswered review threads" names `WB_RESOLVED_REACTION`. The
change reaches neither part, so neither is re-verified here.

## What would change the answer

The re-run moves off the pack when Gas City's PR monitor re-runs a check that
failed for a non-code cause, or when the GitHub intake that retires pr-facts.sh
(tk-1tfzr71.21) carries PR checks onto a primitive that does.
