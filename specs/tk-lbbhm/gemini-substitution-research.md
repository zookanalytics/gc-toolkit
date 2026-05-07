# Gemini-CLI Command-Substitution Restriction: Refresh & Path Forward

**Bead:** tk-lbbhm
**Parent:** tk-mmny1 (parked since 2026-05-05; this doc is the input for an unpark
decision)
**Author:** polecat gc-toolkit/gc-toolkit.slit
**Surveyed:** 2026-05-07

## Provenance

| Doc-type or artifact | Producer (upstream PR / issue / release / CLI flag / repo path) | Source location | Surveyed at |
|---|---|---|---|
| Original security fix | PR #24170 "Fix/command injection shell" | `google-gemini/gemini-cli` PR #24170, merged 2026-04-22 (commit `2a52611`), shipped v0.40.0 | 2026-05-07 |
| Driving CVE-style report | Issue #14926 "Security Vulnerability: Command Injection in run_shell_command" (P1, area/security) | `google-gemini/gemini-cli` issue #14926, opened 2025-12-11, closed 2026-04-22 | 2026-05-07 |
| YOLO opt-out request (the exact ask) | Issue #6436 "YOLO mode should override block of command-substitution in bash" | `google-gemini/gemini-cli` issue #6436, opened 2025-08-17, closed 2025-12-03 (Stale) | 2026-05-07 |
| Workflow-failure report (GHA) | Issue #6389 "Workflow fails with run_shell_command: Command substitution is not allowed" (P2, area/non-interactive) | `google-gemini/gemini-cli` issue #6389, opened 2025-08-16, closed 2025-12-03 (Stale) | 2026-05-07 |
| Proposed YOLO opt-out PR | PR #8546 "feat(core): Enable command substitution in YOLO approval mode" | `google-gemini/gemini-cli` PR #8546, opened 2025-09-16, closed without merge 2025-12-02 | 2026-05-07 |
| v0.40.0 hardening | PR #25720 "feat(core): enhance shell command validation and add core tools allowlist" | `google-gemini/gemini-cli` PR #25720, merged 2026-04-23, shipped v0.40.0 | 2026-05-07 |
| v0.41.0 tightening | PR #25935 "fix(core): fail closed in YOLO mode when shell parsing fails for restricted rules" | `google-gemini/gemini-cli` PR #25935, merged 2026-04-24, shipped v0.41.0 | 2026-05-07 |
| v0.41.1 redirect carve-out | PR #26542 "fix(core): allow redirection in YOLO and AUTO_EDIT modes without sandboxing" | `google-gemini/gemini-cli` PR #26542, merged 2026-05-05, shipped v0.41.1 / v0.42.0-preview.1 | 2026-05-07 |
| Architectural rewrite (in flight) | PR #23041 "feat(policy): replace YOLO mode with data-driven wildcard policy" | `google-gemini/gemini-cli` PR #23041, opened 2026-03-19, OPEN | 2026-05-07 |
| Narrow PowerShell bypass (in flight) | PR #26317 "fix: bypass powershell command substitution check for setup-github" | `google-gemini/gemini-cli` PR #26317, opened 2026-05-01, OPEN | 2026-05-07 |
| Roadmap tracking issue | Issue #15542 "Fine-Grained, Pattern-Based Permission System" (P1, enterprise, maintainer-only) | `google-gemini/gemini-cli` issue #15542, opened 2025-12-25, OPEN | 2026-05-07 |
| Detector source location | `detectCommandSubstitution` / `parseCommandDetails` | `packages/core/src/utils/shell-utils.ts` and `packages/core/src/tools/shell.ts` (commit `49456e4`) | 2026-05-07 |
| Settings docs | `docs/cli/settings.md`, `docs/cli/trusted-folders.md`, `docs/cli/sandbox.md` | `google-gemini/gemini-cli` (default branch) | 2026-05-07 |
| Release index | "Latest stable release v0.41.2" / preview v0.42.0-preview.2 | `google-gemini/gemini-cli` releases (latest published 2026-05-06) | 2026-05-07 |
| Codex CLI docs | OpenAI Codex CLI sandbox + non-interactive docs | `developers.openai.com/codex/concepts/sandboxing`, `developers.openai.com/codex/noninteractive` | 2026-05-07 |

---

## 1. Upstream state refresh

**Current versions:** v0.41.2 stable (2026-05-06), v0.42.0-preview.2 preview
(2026-05-06). Source: `gh api repos/google-gemini/gemini-cli/releases/latest`.

**The detector is still in place and there is still no opt-out.** The check
lives in `packages/core/src/utils/shell-utils.ts` (function
`detectCommandSubstitution` / `parseCommandDetails`) and is invoked by
`PolicyEngine` before any approval mode is consulted. Blocked syntax (per PR
#24170 description):

> "shell substitution syntax (`$()`, backticks, `<()`) in command arguments was
> being executed by the shell instead of treated as literal strings."

**Specifically blocked:** `$(...)`, `` `...` `` (backticks), `<(...)` process
substitution. **Confirmed not blocked by the substitution detector:** redirects
(`>`, `>>`, `2>&1`), pipes (`|`), heredocs (`<<EOF`). PR #25537 ("use newline in
shell command wrapping to avoid breaking heredocs", merged 2026-04-21) treats
heredocs as legal; PR #26542 (v0.41.1) explicitly carved out redirects from a
*separate* sandbox-related downgrade. So tk-mmny1 open question 3 ("backticks,
heredocs, redirects?") resolves as: **backticks blocked, process subs blocked,
redirects/pipes/heredocs not blocked by this detector** (though redirects had
their own sandbox interlock until v0.41.1).

**Versions since v0.40.0 — anything that opened a hole?** No. Surveying every
release between v0.40.0 (2026-04-28) and v0.41.2 (2026-05-06):

- v0.40.0: PR #25720 *added* the allowlist (`settings.tools.core`, e.g.
  `run_shell_command(ls)`). The allowlist gates which commands a tool can
  invoke; the substitution detector runs *before* the allowlist and is not
  affected. PR description: "The `PolicyEngine` now utilizes
  `parseCommandDetails` from `shell-utils` to identify all nested parts of a
  shell command (substitutions, subshells, piped commands)."
- v0.41.0: PR #25935 "fail closed in YOLO mode when shell parsing fails for
  restricted rules" — *tightens* the path, doesn't loosen it.
- v0.41.0: PR #25814 "secure .env loading and enforce workspace trust in
  headless mode" — adds workspace-trust requirement for headless runs (relevant
  to gc-launcher, but orthogonal to substitution detection).
- v0.41.1 / v0.42.0-preview.1: PR #26542 carves redirects out of an
  unrelated sandbox interlock; substitution detector untouched.
- v0.41.2 / v0.42.0-preview.2: cherry-picks only.

**Settings.json keys that *might* look related (per `docs/cli/settings.md`) and
why none of them help:**

- `tools.core` (allowlist of `tool(args)` invocations) — gates which commands
  the *tool* permits; runs after the substitution detector.
- `general.defaultApprovalMode` ("default" / "auto_edit" / "plan"; YOLO is
  CLI-flag-only) — controls approval prompts; substitution detector runs
  before approval.
- `security.folderTrust.enabled`, `security.disableYoloMode`,
  `security.toolSandboxing` — orthogonal to substitution detection.
- `tools.shell.enableInteractiveShell`, `tools.sandbox` — orthogonal.

**Conclusion for §1:** No opt-out flag, env var, or settings.json key has been
added since v0.40.0. The detector is mandatory and has been *strengthened*
(allowlist + fail-closed) rather than relaxed.

---

## 2. Open issue / PR signal

**Direct opt-out asks: stalled, with a maintainer thumbs-up but no shipped
work.**

- **Issue #6436** (the exact YOLO-override request): a maintainer (cornmander)
  responded **2025-08-20**: *"I think this is a good idea."* No follow-up. The
  issue was auto-closed by the stale bot on **2025-12-03** with the "Stale"
  label, comment: *"It looks like this issue hasn't been active for a while, so
  we are closing it for now."* No replacement issue has been opened.
- **Issue #6389** (GHA workflow variant) followed the same auto-close path on
  the same day.
- **PR #8546** ("Enable command substitution in YOLO approval mode") was
  opened 2025-09-16 by an external contributor and closed unmerged on
  **2025-12-02** by maintainer scidomino with: *"This looked good but I see in
  the merge conflicts that we removed `detectCommandSubstitution` some time
  ago. I'll close this PR for now but if you still think it's necessary and
  want to get it working with the new structure, create a new PR..."* The
  detector was reintroduced (more thoroughly) by PR #24170 in April 2026; **no
  one has yet reopened the YOLO opt-out PR against the new structure.**
- **PR #25544** "security: improve dangerous command detection for rm and fix
  YOLO bypass" (closed unmerged 2026-04-16) — a third-party tried a YOLO
  bypass in a different area; maintainers rejected it. Direction is consistent.

**Indirect / adjacent signal:**

- **PR #23041** "feat(policy): replace YOLO mode with data-driven wildcard
  policy" — OPEN, marked maintainer-only. From the body: *"This PR radically
  simplifies the `PolicyEngine` by removing the hardcoded concept of
  `ApprovalMode.YOLO`. Instead, the `--yolo` flag is natively mapped to a
  standard data-driven wildcard policy array (`allowedTools: ["*"]`)."* If this
  lands, `--yolo` becomes sugar for an `allowedTools` policy entry; the
  substitution detector still runs before policy, so this **does not** by
  itself create an opt-out, but it is the architecture into which a
  fine-grained "permit substitution" knob would naturally fit.
- **Issue #15542** "Fine-Grained, Pattern-Based Permission System" — OPEN, P1,
  area/enterprise, maintainer-only, type/feature. This is the maintainer
  roadmap slot for a real allowlist/denylist surface. Substitution opt-out is
  not called out by name but would land here if it lands at all.
- **PR #26317** "bypass powershell command substitution check for
  setup-github" — OPEN. Scope is **one specific built-in command** on
  PowerShell only; not a general opt-out. Body: *"By changing
  `(${commands.join(' && ')})` to `commands.join(' && ')`, the built-in command
  avoids the PowerShell block while preserving the same execution behavior."*
- **PR #9934** "Added warning to avoid command substitution in
  run_shell_command tool" (merged 2025-09-26) — added a system-prompt
  *warning* to the tool docstring telling the model not to emit `$()`. Body:
  *"Disallowed command substitution is a leading cause of run_shell_command
  failures, so this should hopefully decrease the failure rate."* This is the
  maintainers' answer to the model-side problem: train the model out of it,
  not unblock it.

**Summary:** The maintainers' revealed direction is **harden the detector,
push the model away from `$()`, and route fine-grained control through a
future pattern-based permission system**. The one cheap opt-out PR was closed
on a code-drift technicality with a polite re-invitation, but no one has
reopened it against the post-#24170 code, and there is no public timeline for
the wider permission system in #15542.

---

## 3. Workaround analysis

For each path the bead lists, what it would cost us and how well it works.

### 3a. Script-file wrapper

**What:** Replace lines like
`WISP=$(gc bd mol wisp ... | jq -r '.new_epic_id')` with a two-step pattern
that writes the substitution result to a file, then reads the file in the
next command (no `$()` on the literal command line).

**Feasibility:** High. The detector parses the literal argument string and
flags `$()`. Splitting the work into two `run_shell_command` calls — one that
redirects to a temp file and one that reads it — sidesteps the parser. Output
redirection is *not* blocked by the substitution detector and as of v0.41.1
also clears the separate sandbox interlock in YOLO/AUTO_EDIT modes.

**Cost:** Medium-high in *prompt-engineering churn* and ongoing maintenance.

- Every multi-step polecat preamble that uses `$()` (claim, wisp, branch
  setup, refinery handoff) needs a rewrite. The current preamble has ~6–8
  `$()` sites.
- The two-step pattern is harder to reason about (extra files, cleanup), so
  the polecat prompt and `mol-polecat-work` formula become noisier.
- Diverges from gastown's polecat prompt — every gastown sync needs to
  re-translate.
- Doesn't solve the *general* problem: any new bead description or formula
  that introduces `$()` will fail in gemini polecats and pass in claude.

**Verdict:** Works, but the cost compounds with every new gastown-derived
prompt change. Bad fit unless gemini provider becomes load-bearing.

### 3b. MCP tool wrapper

**What:** Wrap `gc` (and any other tools the polecat shells out to) behind an
MCP server. Polecat calls the MCP tool by name with structured arguments;
substitution happens inside the MCP server process, never on the gemini-cli
shell command line.

**Feasibility:** High in principle — gemini-cli has first-class MCP support.
But it's a real engineering project: define a tool schema for every gc
subcommand we use (or a generic "run gc" tool that takes the subcommand +
args as JSON), host it, supervise it, route trust through `security.folderTrust`.

**Cost:** High up-front, low per-prompt-change.

- New rig component to build, deploy, and supervise.
- `gc` evolves frequently; the MCP wrapper either stays current
  (maintenance burden) or becomes a generic "exec gc <args>" tool (which
  reintroduces the same shell-quoting problems we're trying to avoid).
- `security.folderTrust.enabled = true` is a prerequisite for MCP servers to
  load workspace-specific config; that's a one-time setup but adds a moving
  part.
- Polecat prompt would need to learn a parallel MCP-call surface.

**Verdict:** Architecturally clean and the maintainers' preferred direction
(MCP is the official escape hatch for shell ergonomics). Worth doing **only
if** we want gemini polecats long-term; not justified for a parked agent.

### 3c. Prompt rewrite (eliminate `$()` from the polecat preamble)

**What:** Restructure the polecat prompt so it never emits `$()` to
`run_shell_command`. Translate every substitution into either (a) explicit
multi-step bd lookups (claim ID, then read the resulting bead, then issue the
next command with the literal value), or (b) helper subcommands that bake the
chained logic into `gc` itself.

**Feasibility:** Medium. (a) bloats the prompt and slows every step (more
turns per claim/branch/handoff). (b) requires investing in `gc` subcommands
that take *no* substitution-y arguments — e.g. `gc bd claim --next-routed`,
`gc handoff --to-refinery`. We've already moved in this direction with the
done-sequence and the work-discovery `sh -c '...'` blob in CLAUDE.md.

**Cost:** Medium in the prompt; low-medium in `gc`.

- The existing `sh -c '...'` discovery shim is already a workaround for a
  different reason, but it itself contains `$(...)` (`r=$(bd list ...)`).
  It would have to be rewritten to use a series of single-line `bd list`
  calls and `jq` filters, or moved into a `gc` helper.
- Every formula step that constructs an intermediate value via `$()` needs a
  paired `gc` helper.
- Diverges sharply from the gastown polecat prompt — significant ongoing
  drift cost (already called out as the key cost in tk-mmny1's open
  question 2).

**Verdict:** Works, but the divergence from gastown is the dealbreaker
operator already flagged. Not worth it unless paired with an upstream
gastown change.

### 3d. Wait for upstream opt-out

**What:** File a fresh issue/PR against post-#24170 code (re-do the work in
PR #8546 against the new structure), or wait for #23041 + #15542 to land and
expose a pattern-based opt-out.

**Feasibility:** Low-effort to file (one issue + one PR mirroring #8546's
diff, retargeted at the new `parseCommandDetails` site). High-uncertainty on
landing — the maintainer who said "I think this is a good idea" hasn't
prioritised it in 9 months, and the security-tightening direction (#25935,
#25544 rejection) suggests review will be conservative.

**Cost:** Hours to file, indeterminate wait. If we file, our PR competes for
attention with the in-flight #23041 architectural rewrite, which may
reasonably block any opt-out work until the YOLO->policy refactor settles.

**Verdict:** Cheap to attempt, but we should not block on it.

---

## 4. Codex tool runner contrast (brief)

Why does `polecat-codex` work where `polecat-gemini` doesn't?

Codex CLI's shell tool **does not run a pre-execution AST/regex check for
substitution syntax**. Instead, Codex runs commands inside a sandbox
(workspace-write by default) and lets the shell evaluate `$()` normally; the
*sandbox* is what bounds blast radius (filesystem scope, network policy).
For full unrestricted shell access, Codex offers `danger-full-access` mode,
which is the rough analog of `gemini -y` — except it actually disables the
boundary it controls. Codex's docs ([sandboxing] / [non-interactive]) frame
this as "sandbox policy + per-command rules," not "ban specific shell
syntax." So `$(...)`, backticks, and process subs are all legal in Codex
because the question is "what can the resulting process touch?", not "does
the literal source string match a forbidden pattern?"

Gemini-cli took the opposite design: parse the literal command string,
reject anything that the parser thinks could elevate, and rely on
non-bypassability as the safety story. PR #24170's framing — *"was being
executed by the shell instead of treated as literal strings"* — only makes
sense in a model that doesn't trust the sandbox to contain the consequences.

For polecat selection: codex is the right runner whenever the work needs
chained shell with substitution (i.e., almost always for our preamble).
Gemini becomes safe to route to only for tasks that fit Gemini's safer-by-
default shape — which today means tool-call-heavy, file-edit-heavy, low-
shell-substitution work. That's a narrower slice than our current pool
expects, which is why first-test failed.

[sandboxing]: https://developers.openai.com/codex/concepts/sandboxing
[non-interactive]: https://developers.openai.com/codex/noninteractive

---

## 5. Recommended path

**Stay parked.** Specifically: keep `_polecat-gemini` disabled and **revisit
when one of these signals lands**:

1. **Trigger A (cheapest):** An opt-out flag, env var, or settings.json key
   appears in a gemini-cli release. Probability: low in the next 1–2
   releases; the maintainers' active direction is hardening + #23041 +
   #15542. We can detect this passively — the witness or deacon can subscribe
   to gemini-cli releases.
2. **Trigger B (medium):** PR #23041 lands AND #15542's pattern-based
   permission system gains a "permit shell substitution in trusted
   workspaces" pattern. Probability: medium over months. Reassess at next
   Lane C / provider-diversity review.
3. **Trigger C (operator-driven):** We decide gemini provider diversity is
   load-bearing enough to justify the **MCP tool wrapper** investment
   (option 3b). At that point the substitution restriction stops mattering
   because we route around `run_shell_command` entirely. This should be a
   conscious investment decision, not a workaround.

**Cost-benefit of the recommendation:**

- Cost of staying parked: ~zero. `polecat-codex` already covers
  multi-provider needs (Lane C cutover proved this). `_polecat-gemini` is
  inert (`agent_discovery.go` skips `_`-prefixed dirs); no runtime cost.
- Cost of the workarounds: §3a/3c diverge the polecat prompt from gastown
  with ongoing maintenance tax for an agent that isn't load-bearing. §3b is
  real engineering work that doesn't pay back unless gemini becomes a
  required provider. §3d is ~free to file but blocks on indeterminate
  upstream timeline.
- Cost of waiting: ~zero, plus we get to spend the time elsewhere. The
  maintainer-side architectural rewrite (#23041 + #15542) is *more likely*
  to give us a clean opt-out than our own one-off PR is to land.

**Optional cheap action while parked:** open a new gemini-cli issue
referencing #6436 / PR #8546 and the v0.40.0 reintroduction, asking whether
the YOLO opt-out is welcome against the new `parseCommandDetails` structure.
Low cost, may surface a maintainer signal that flips trigger A. Filing this
is the operator's call (the bead lists "filing an upstream gemini-cli issue"
as out of scope for this research bead).

**What this resolves on tk-mmny1's open questions:**

- **Q1 (configurable?):** No. As of v0.41.2, no flag/env/setting bypasses
  the detector.
- **Q2 (no-`$()` rewrite cost?):** High — see §3a/3c. Diverges from gastown
  prompt with compounding maintenance.
- **Q3 (backticks / heredocs / etc.?):** Backticks blocked, `<()` blocked,
  `>()` blocked. Heredocs, pipes, redirects not blocked by this detector
  (redirects had a separate sandbox interlock that v0.41.1 cleared in YOLO/
  AUTO_EDIT).
- **Q4 (codex contrast?):** Codex relies on sandbox boundaries, not literal-
  string parsing — which is why it executes `$()` fine.

Recommendation in one line: **stay parked, monitor #23041 / #15542, do not
invest in a workaround unless gemini becomes a required provider.**
