# Spec: gascity upstream lifecycle — mols + on-demand keeper agent

## Background

gascity is forked at `origin` (zookanalytics) from `upstream` (gastownhall).
References: `gascity-local-patching.md`, memory `project_gascity_upstream_fork.md`,
`project_gascity_upstream_pr_candidates.md`. Currently 23 commits ahead of upstream.

We're formalizing two operator-on-demand workflows as mols, behind an on-demand
keeper agent (rig-scoped to gascity). PR/issue creation is **blocked** for now;
the workflows produce ready-to-paste `gh` commands instead.

The `mol-upstream-gc-…` prefix marks the gascity-management family. If the family
grows past 3-4 mols, extract to a sub-pack loaded only into gascity (note in
`PROVENANCE.md`).

## Files to create

All under `rigs/gc-toolkit/`:

1. `specs/<this-impl-bead-id>/spec.md` — drop this entire spec text here (first commit on the feature branch)
2. `formulas/mol-upstream-gc-rebase.toml`
3. `formulas/mol-upstream-gc-pr-prep.toml`
4. `agents/gascity-keeper/agent.toml`
5. `agents/gascity-keeper/prompt.template.md`
6. `agents/gascity-keeper/PROVENANCE.md`

**Do not** modify `pack.toml`. Do not add a `[[named_session]]` for
gascity-keeper — it is on-demand only (matches concierge / architect / consult-host).
Do not modify any gascity rig files.

## mol-upstream-gc-rebase

Extends `mol-polecat-base`. **Autonomous through push.** Operator-state at completion: "everything is up to date" or "I've been mailed to take action."

### Vars

| Var | Default | Notes |
|---|---|---|
| `upstream_remote` | `upstream` | |
| `origin_remote` | `origin` | |
| `upstream_branch` | `main` | |
| `test_command` | `make test` | |
| `install_command` | `make install` | local rebuild of `gc` into `$INSTALL_DIR` |
| `notify_recipient` | `overseer` | mail target on completion / abort |

### Steps (in order; each `needs` the previous)

#### `workspace-setup` (overrides base)
- Worktree at gascity rig at `origin/{{upstream_branch}}`. Record `metadata.work_dir`.
- `git fetch {{upstream_remote}} --prune`
- Write safety backup ref: `git update-ref refs/backups/main-pre-rebase-$(date -u +%Y%m%dT%H%M%SZ) HEAD` and record name in `metadata.backup_ref`.

#### `survey`
- `git range-diff {{upstream_remote}}/{{upstream_branch}}...{{origin_remote}}/{{upstream_branch}}` (or equivalent) and `git log --oneline {{upstream_remote}}/{{upstream_branch}}..{{origin_remote}}/{{upstream_branch}}`.
- For each origin commit, decide: **drop-merged-upstream** (exact patch-id), **drop-supplanted** (upstream solves the same problem differently), **keep**. Use LLM judgment for "supplanted." Document each decision (sha, subject, verdict, one-line rationale).
- Persist verdict table to bead notes (markdown table) AND to `metadata.commit_verdicts` as JSON.

#### `rebase`
- `git rebase {{upstream_remote}}/{{upstream_branch}}` — patch-id matches drop automatically.
- For commits flagged **drop-supplanted**, rewrite via `git rebase -i` (mark `drop`).
- Sanity check: `git log {{upstream_remote}}/{{upstream_branch}}..HEAD --oneline` matches the kept set.

#### `test` (after `self-review` from base, or in place of it)
- Run `{{test_command}}`.
- On failure: mail `{{notify_recipient}}` with subject `gascity rebase: tests failed`, body containing the failure tail, the worktree path, the backup ref, and the verdict table. Set `metadata.aborted_at=test`. Drain-ack + exit. Bead stays open.

#### `install`
- Run `{{install_command}}`.
- On failure: same pattern as `test` failure but `aborted_at=install`. Drain-ack + exit.

#### `push`
- `git push {{origin_remote}} HEAD:{{upstream_branch}} --force-with-lease`
- On rejection: mail `{{notify_recipient}}` with subject `gascity rebase: push race`, body explaining force-with-lease was rejected (someone else pushed). Do NOT retry. Set `metadata.aborted_at=push`. Drain-ack + exit.

#### `notify-and-close`
- Mail `{{notify_recipient}}` with subject `gascity rebase: complete`, body with: dropped commits (sha, subject, verdict reason), upstream commits absorbed (sha, subject), test/install/push outcomes, backup ref name.
- Append a clean copy of the same content to bead notes.
- Close bead. Drain-ack + exit.

## mol-upstream-gc-pr-prep

Extends `mol-polecat-base`. Mechanical work through branch-push, then **hands the bead back to the keeper** for the title/body conversation. PR/issue creation is operator-gated and currently blocked.

### Vars

| Var | Default | Notes |
|---|---|---|
| `commit_sha` | required (from `metadata.commit_sha`) | the local commit to extract |
| `upstream_remote` | `upstream` | |
| `origin_remote` | `origin` | |
| `upstream_branch` | `main` | |
| `test_command` | `make test` | |
| `requesting_keeper` | required (from `metadata.requesting_keeper`) | who to hand back to |

### Steps

#### `workspace-setup` (overrides base)
- Worktree at gascity rig at `{{upstream_remote}}/{{upstream_branch}}`. Record `metadata.work_dir`.
- Branch: `upstream-pr/<short-sha-or-slug>`. Record `metadata.branch`.

#### `cherry-pick`
- `git cherry-pick {{commit_sha}}`
- On conflict: mail keeper AND operator with conflict details. Set `metadata.aborted_at=cherry-pick`. Drain-ack + exit. Bead stays open.

#### `scrub-commit-message`
- Read commit message. LLM scan for:
  - bead-ID patterns (regex-ish): `\b(lx|gc|tk|sl)-[a-z0-9]+\b`
  - rig names: `gc-toolkit`, `signal-loom`, `loomington`
  - city refs: `loomington`, "this city", "our city"
  - internal handle names: `mechanik`, `mayor`, `deacon`, `polecat`, `witness`, `refinery`, `boot`, `concierge`, `consult-host`, `keeper`
- If any found: rewrite to remove or generalize. `git commit --amend` with cleaned message. If nothing found, leave message untouched.
- Record `metadata.scrub_diff` (before/after summary).

#### `test`
- Run `{{test_command}}`.
- On failure: mail keeper AND operator. Set `metadata.aborted_at=test`. Drain-ack + exit. Bead stays open.

#### `push-branch`
- `git push {{origin_remote}} HEAD`
- Record `metadata.branch_url` (compose from origin remote URL + branch name).

#### `prepare-pr-handoff`
- Draft `suggested_pr_title` (typically the cleaned commit subject).
- Draft `suggested_pr_body` (commit body + a short "## Why this PR" stub the keeper can iterate on with the operator).
- Judge whether an issue would help upstream (e.g., RFC-shaped change, behavioural decision worth surfacing). If yes, draft `suggested_issue_title` and `suggested_issue_body`. Always record `issue_advice` (yes/no + reason).
- Construct ready-to-paste commands and store as `gh_pr_command` and (optionally) `gh_issue_command`.
- Persist all of: `branch_url`, `suggested_pr_title`, `suggested_pr_body`, `suggested_issue_title`, `suggested_issue_body`, `issue_advice`, `gh_pr_command`, `gh_issue_command` to bead metadata.

#### `handback-to-keeper`
- `gc bd update <bead> --assignee={{requesting_keeper}} --set-metadata gc.routed_to={{requesting_keeper}}` (matches the polecat→refinery contract)
- `gc session nudge {{requesting_keeper}} "PR prep ready: <bead>"`
- Mail operator a brief backstop note pointing to the bead and the keeper (durable record in case the keeper session was closed mid-flight).
- Bead stays **open** — keeper closes after refinement.
- Drain-ack + exit.

## gascity-keeper agent

On-demand, rig-scoped to gascity. Operator-facing conversational front-end.

### `agent.toml`

```toml
scope = "rig"
wake_mode = "fresh"
work_dir = ".gc/agents/gascity-keeper"
nudge = "Check for PR-prep handback beads, then engage the operator."
idle_timeout = "2h"
```

### `prompt.template.md`

Persona / role: "I manage the upstream lifecycle for gascity. I know the
origin/upstream fork convention, the operator-gated PR rule, and the two mols
(`mol-upstream-gc-rebase`, `mol-upstream-gc-pr-prep`). I dispatch polecats for
mechanical work and handle the conversational tail myself."

Reference docs the keeper should consult on prime: `docs/gascity-local-patching.md`
in this pack (path `rigs/gc-toolkit/docs/gascity-local-patching.md`).

#### On wake / prime
1. `gc prime` (role context)
2. `gc bd prime` (beads context)
3. Check for handback beads: `gc bd list --assignee=$GC_AGENT --status=open --json | jq '.[] | select(.metadata.suggested_pr_title)'`. If any, that's a handback awaiting refinement — surface it when the operator engages.

#### Operator commands

**"rebase" / "sync from upstream":**
1. `cd rigs/gascity` (to route bead to gascity rig store) and `gc bd create "Rebase gascity from upstream" -t task --set-metadata notify_recipient=overseer`.
2. `gc sling gascity/polecat <bead> --var formula=mol-upstream-gc-rebase`.
3. Tell operator: "Polecat dispatched on bead `<id>`. Autonomous run — rebase, test, install, push. You'll get a 'complete' mail or an action-required mail."

**"prep PR for <commit-sha>":**
1. Validate sha: `git -C rigs/gascity show <sha> --stat` — fail fast if it doesn't exist.
2. `cd rigs/gascity` and `gc bd create "Prep upstream PR for <short-sha>" -t task --set-metadata commit_sha=<sha> --set-metadata requesting_keeper=$GC_AGENT`.
3. `gc sling gascity/polecat <bead> --var formula=mol-upstream-gc-pr-prep`.
4. Tell operator: "Polecat dispatched on bead `<id>`. I'll come back when the branch is ready."

#### Handback conversation

When a bead with `metadata.suggested_pr_title` is your assignment (whether discovered on prime or via nudge):

1. Read all metadata fields (branch_url, suggested_pr_title, suggested_pr_body, suggested_issue_title, suggested_issue_body, issue_advice, gh_pr_command, gh_issue_command).
2. Surface the artifacts to the operator in a clear block:
   ```
   Polecat done. Branch pushed: <branch_url>

   Suggested PR title: <title>
   Suggested PR body:
     <body>

   Issue advice: <yes/no + reason>
   <if yes:>
     Suggested issue title: <title>
     Suggested issue body: <body>

   Want to tweak any of these before I finalize?
   ```
3. Iterate with the operator on title / body / issue decision. Keep the conversation in this session.
4. When operator says "good": persist `final_pr_title`, `final_pr_body`, `final_pr_command`, `final_issue_command` to bead metadata. PR creation is blocked, so:
   - Mail operator the ready-to-paste `gh pr create` (and `gh issue create` if applicable) commands.
   - Close the bead.
5. **Future** (when PRs unblock): replace step 4 with running `gh pr create` directly, recording `metadata.pr_url`, then closing.

#### Conventions
- All gascity-management beads file in the gascity rig bead store (`cd rigs/gascity` before `gc bd create`, per memory `feedback_bead_store_matches_scope.md`).
- Don't push origin/main yourself — that's the rebase mol's job. PR-prep mol pushes feature branches only.

### `PROVENANCE.md`

Native gc-toolkit. Part of the gascity-management family (`mol-upstream-gc-…` mols + this keeper). Future option: extract the family to a sub-pack loaded only into the gascity rig if it grows past 3-4 mols.

## Implementation notes for the polecat

- This is a creates-only PR. No edits to existing files.
- Drop the spec text first as `specs/<bead-id>/spec.md` (the bead notes contain it).
- Pack-level validation from inside `rigs/gc-toolkit`:
  - `gc config show` should not error
  - `gc bd mol show mol-upstream-gc-rebase` and `gc bd mol show mol-upstream-gc-pr-prep` should resolve
- Per memory `feedback_pack_toml_test_from_rig.md`, run validation from inside the rig — city-root `gc config show` is insufficient.
- gc-toolkit runs a deliberately low CI bar (memory `project_gc_toolkit_low_ci_bar.md`) — don't add heavy gates.
- Standard polecat→refinery flow. The refinery will open the PR and close this impl bead with `merge_result=pull_request` when it's mergeable.

## Review chain (informational)

This impl bead is followed by:
1. **Codex review** (`mol-review-leg`, `polecat-codex`) — reviews the impl PR for spec adherence, formula schema correctness, agent prompt quality, edge cases.
2. **Validation** (`mol-polecat-work`, claude polecat) — reads the codex review notes, addresses each finding either with a fix commit on the PR branch or with a documented WONT-FIX rationale, then re-handsoff to the refinery.
