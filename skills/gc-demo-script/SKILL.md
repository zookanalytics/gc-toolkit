---
name: gc-demo-script
description: Generates a demo:capture-format script from a closed Gas City work bead by reading the bead tree, git commits, and PR diff
---

# GC Demo Script — Gas City Bead to Demo Script

Generate a `demo:capture`-format markdown script from a completed Gas City
work bead.
This skill is the Gas City-native sibling of `demo:epic`: it reads the bead
description, notes, parent molecule, sibling design-leg beads, and git/PR
diff, then produces a user-facing demo script that `demo:capture` can
execute.

**This skill DOES NOT run `demo:capture`.** It writes a script file and
returns the path.
The caller (human or another skill) invokes `demo:capture` separately on the
generated script.
This matches `demo:epic`'s separation between generation and execution.

## When to use

Use this skill when:

- A Gas City work bead is closed (usually with a merged or open PR)
- You want a user-facing demo of what the bead's work actually changed
- The bead does NOT have BMAD artifacts (use `demo:epic` for BMAD-driven
  work that lives under `_bmad-output/`)

## Input

You receive parsed arguments from the command wrapper:

- **Bead ID** (required) — e.g., `sl-8jv`
- **`--pr <number>`** (optional) — PR number, otherwise derived from
  `metadata.pr_number` on the bead
- **`--focus "area"`** (optional) — bias the demo narration toward a
  specific functional area (e.g., "mobile", "diff viewing")

If no bead ID is provided, ask the caller for one.

## Prerequisites Check

Before gathering context, verify:

1. **`bd` CLI is available** — `command -v bd` succeeds
2. **Bead exists** — `bd show <id>` returns a valid result

If the bead doesn't exist, stop and report:
"Bead `<id>` not found. Check the ID and try again."

Unlike `demo:epic`, this skill does NOT require Playwright MCP, ImageMagick,
or a running app — it only generates a script file.
The script can be executed later by `demo:capture` from a session that has
those prerequisites.

## Phase A: Gather Context (sequential reads)

Gas City sources are interconnected — the work bead references sibling
design-leg beads, parent molecules, and commits.
Read them in order; do NOT dispatch parallel subagents (the inputs are
small enough for direct reads, and ordering matters for cross-references).

### Step A1: Read the work bead

```bash
bd show "$BEAD"                               # Human-readable summary
bd show "$BEAD" --json > /tmp/bead-"$BEAD".json  # Full structured data
```

From the JSON, extract and keep in working memory:

- `title` — becomes part of the demo title
- `description` — original assignment (the "what to build"). Scan for:
  - Goals and scope priorities (TIER 1, TIER 2, MUST HAVE)
  - Locked decisions or must-have behaviors
  - References to sibling beads (e.g., `sl-9hi`, `sl-so9`)
  - Test strategies (hints about what to verify in the demo)
- `notes` — the polecat's implementation report. Scan for:
  - "Implemented:" section — lists what was actually built
  - File paths mentioned (narrows user-facing changes)
  - "Quality" / "Tests" section — hints at Scrutiny items
  - "Out of scope" / "deferred" — what was NOT done (do NOT demo it)
- `metadata.branch` — the implementation branch
- `metadata.target` — the target branch (usually `main`)
- `metadata.pr_number`, `metadata.pr_url` — PR location (if any)
- `metadata.worktree` — the polecat's worktree path
- `parent` — the convoy/molecule wrapping this work

### Step A2: Read the parent molecule (if any)

If the bead has a parent convoy or `metadata.molecule_id`, read it:

```bash
PARENT=$(bd show "$BEAD" --json | jq -r '.[0].parent // empty')
MOLECULE=$(bd show "$BEAD" --json | jq -r '.[0].metadata.molecule_id // empty')
[ -n "$MOLECULE" ] && bd show "$MOLECULE"
[ -n "$PARENT" ] && bd show "$PARENT"
```

The parent gives cross-bead context — the wider initiative, why this work
mattered, and how it fits with other beads.

### Step A3: Read sibling design-leg beads

Scan the work bead's `description` and `notes` for bead IDs referenced in
prose (e.g., "per sl-so9 §6", "sl-9hi G2.1").
Extract them with a regex and read each one:

```bash
bd show "$BEAD" --json \
  | jq -r '.[0].description, (.[0].notes // "")' \
  | grep -oE '\b(lx|gc|tk|sl|su)-[a-z0-9]+\b' \
  | sort -u \
  | grep -v "^$BEAD$"
# Then for each sibling ID found:
bd show "$SIBLING"
```

Design-leg beads (typically produced by `mol-review-leg` wisps) contain
detailed pre-implementation analysis: type signatures, file:line citations,
test strategies, risk areas.
They are rich sources for:

- Locked decisions the demo narration must not contradict
- Behavior specifics (e.g., "tab switches preserve in-flight state")
- Test scenarios you can lift into Scrutiny items
- Risk descriptions that become Scrutiny items

### Step A4: Read git history on the branch

```bash
BRANCH=$(bd show "$BEAD" --json | jq -r '.[0].metadata.branch // empty')
TARGET=$(bd show "$BEAD" --json | jq -r '.[0].metadata.target // "main"')
if [ -n "$BRANCH" ]; then
  git fetch origin "$BRANCH" "$TARGET" 2>/dev/null || true
  git log --oneline "origin/$TARGET..origin/$BRANCH" 2>/dev/null \
    || git log --oneline "$TARGET..$BRANCH" 2>/dev/null
  git log "origin/$TARGET..origin/$BRANCH" --stat 2>/dev/null \
    || git log "$TARGET..$BRANCH" --stat 2>/dev/null
fi
```

For each significant commit, examine the user-facing portion of the diff:

```bash
git show "$COMMIT" -- \
  'src/app/**' 'src/components/**' '**/*.css' '**/*.tsx' 'public/**'
```

If the branch is not accessible, fall back to bead description and notes
only — those are usually detailed enough for script outlining.

### Step A5: Read the PR diff (if the bead has one)

Honor the `--pr` override if the caller passed one; otherwise derive the
PR number from the bead's metadata.

```bash
PR="${PR_OVERRIDE:-$(bd show "$BEAD" --json | jq -r '.[0].metadata.pr_number // empty')}"
if [ -n "$PR" ]; then
  gh pr view "$PR" --json title,body,state,url,headRefName
  gh pr diff "$PR" > /tmp/pr-"$BEAD".diff
fi
```

The PR body often contains a condensed human-readable summary that is
useful for framing the demo narration.
The diff is the ground truth for what the user will see.

## Phase B: Identify User-Facing Changes

Categorize every changed file from Phase A using this table:

| Category       | Paths                                                                                        | Demo relevance                     |
| -------------- | -------------------------------------------------------------------------------------------- | ---------------------------------- |
| User-facing UI | `src/app/**/page.tsx`, `src/app/**/layout.tsx`, `src/components/**`, `**/*.css`, `public/**` | HIGH — show these                  |
| API surface    | `src/app/api/**`, `convex/**` mutations/queries, `src/server/**`                             | MEDIUM — visible via behavior only |
| Infrastructure | `eslint.config.mjs`, `*.config.*`, `scripts/**`, tests, types, generated files               | LOW — skip in narration            |
| Documentation  | `docs/**`, `*.md`, `README*`                                                                 | LOW — not visible in UI            |

For every user-facing file, extract the diff intent:

- **New file**: "Introduces a new `<what>`"
- **Modified file**: "Changes how `<what>` behaves" — describe the user
  observable difference, not the code change
- **Deleted file**: "Removes `<feature>`" — only demo if the removal is
  the point of the work

**Pull quotes from bead notes.**
The polecat's notes often say things like "the mobile branch now keeps both
panes mounted" — these are already in user-facing language and are gold for
step narration.

If Phase B identifies zero user-facing changes (all infrastructure), stop
and report:

```text
Bead <id> has no user-facing changes to demo.
Categorized files:
  - User-facing UI: 0
  - API surface: <N>
  - Infrastructure: <N>
  - Documentation: <N>

No script generated.
```

## Phase C: Generate the Script

### Step C1: Pick the entry URL

Scan the user-facing file list for the most natural entry point:

1. If the bead touches a specific route (`src/app/<route>/page.tsx`),
   start there (e.g., `/compare`, `/dashboard`).
2. Otherwise, start at `/` or the app's default landing page.
3. If `--focus "area"` biases toward a specific route family, prefer that.
4. When multiple routes are plausible, pick the one whose changes are
   most user-observable (modified > new > unchanged).

### Step C2: Outline 5–12 steps

Each step should exercise one user-observable behavior.
Draw from, in order:

1. The bead's `description` scope section (what was supposed to be built)
2. The bead's `notes` implementation section (what was actually built)
3. The PR diff user-facing changes
4. The design-leg beads' test scenarios (often have concrete user flows)

Step count guidance:

- **Under 5 steps**: the work is too small for its own demo — add
  context-setting steps at the start (navigate, show baseline) to reach
  5 minimum
- **Over 12 steps**: the work spans multiple workflows — either split
  into multiple scripts OR narrow focus with `--focus` and drop
  peripheral steps
- **Sweet spot**: 6–9 steps

### Step C3: Write user-facing narration

Each step needs a **bold narration heading** that describes what the user
sees, NOT what the code does.
This is the text that burns onto the video overlay.
Keep each heading under 80 characters.

**Good narration:**

- "Dashboard shows your recent documents"
- "Switching to Chat tab keeps document state"
- "Diff view highlights only changed lines"

**Bad narration (jargon — will fail validation):**

- "useChat hook streams tokens via the API route"
- "Convex mutation fires on form submit"
- "SplitPaneLayout toggles display: none"

Below each bold heading, write a short action description for the executor
(one or two sentences). Then, for **every** step, write the two REQUIRED
lines that `demo:capture` consumes to score the frame (see
`skills/demo-capture/SKILL.md` §"Demo Script Format" — the executor treats
`_Prove:_` as the contract and marks the frame an error if it isn't met):

- `_Prove:_ <criterion>` — what the captured frame must **visibly**
  demonstrate to pass. Make it concrete and observable (a value on screen, a
  state change, a highlighted diff), never "the page loads".
- `_Fail if:_ <condition>` — the condition(s) that mean the frame failed its
  purpose even though the page rendered (e.g. "only additions, no modified
  lines", "empty list", "spinner still visible").

Draw both from the same evidence you use for Scrutiny (Step C4): the bead
notes' "tested" claims, its "fragile"/"silent bug" language, and the
design-leg beads' risk sections. A step with a vague or unachievable
`_Prove:_` yields a superficial demo — without a sharp criterion the
executor can only screenshot a page, not prove a feature.

### Step C4: Add Scrutiny items

Scrutiny items are things the demo should verify visually.
Draw them from:

- Bead notes' "tested" claims (e.g., "state persists across tab
  switches" → scrutiny: "Tool-call stream continues after tab switch")
- Bead notes' "fragile" or "silent bug" language (e.g., "silent
  correctness bug" → scrutiny: "No silent data loss when switching tabs
  mid-stream")
- Design-leg beads' risk sections
- The PR body's "Quality" section

Aim for 2–4 scrutiny items — sharp, verifiable, focused on risk.

### Step C5: Assemble the script

Use this template (matches `demo:capture`'s expected format exactly):

```markdown
# Demo: <human-readable title, drawn from bead title and focus>

**Start:** <entry URL>
**Auth:** yes

## Steps

1. **<user-facing narration heading>**
   <action description for the executor>
   _Prove:_ <what the frame must visibly demonstrate to pass>
   _Fail if:_ <condition that means the frame failed its purpose>

2. **<next heading>**
   <action description for the executor>
   _Prove:_ <criterion>
   _Fail if:_ <condition>

...

## Scrutiny

- <verifiable thing to check>
- <another verifiable thing>
```

## Phase D: Validate the Script

Before saving, verify each of these checks.
If any fails, fix inline and re-check (up to 2 rewrite attempts).

1. **Format** — presence of:
   - `# Demo:` heading on the first non-blank line
   - `**Start:**` URL line
   - `**Auth:**` line
   - `## Steps` section with numbered items
   - Each step has a bold-heading narration line
   - Each step has a `_Prove:_` line and a `_Fail if:_` line

2. **Proof/fail contract** — **every** step MUST carry both a `_Prove:_`
   line and a `_Fail if:_` line. This is the field `demo:capture` evaluates
   per frame; a step missing either cannot be scored and produces a
   superficial or failing frame. For each step confirm:
   - a `_Prove:_ <criterion>` line is present and names something visibly
     observable (reject "page loads" / "no errors")
   - a `_Fail if:_ <condition>` line is present and names a concrete failure
     state
   If any step is missing a field, add it (drawing from the bead notes and
   design-leg risk sections as in Step C3) and re-validate.

3. **Step count** — between 5 and 12 inclusive.
   If outside, adjust (collapse similar steps or split overly dense
   ones) and re-validate.

4. **Jargon scan** — scan ALL bold narration headings for these forbidden
   terms (case-insensitive):

   ```text
   SDK, API, schema, migration, hook, mutation, query, endpoint,
   route, handler, middleware, Convex, Vercel, streamText, useChat,
   Automerge, Playwright, TypeScript, TSX, JSX, Next.js, React
   ```

   If any are found, rewrite the headings in user-facing language and
   re-validate.

5. **Start URL plausibility** — the URL should start with `/` and look
   like a real route (match a path you saw in `src/app/`).
   If the URL is obviously fabricated, fall back to `/` and note it in
   the summary.

If validation still fails after 2 rewrite attempts, save the script
anyway but print a warning listing the unresolved validation failures so
the caller can fix manually.

## Phase E: Save and Report

### Step E1: Create output directory

```bash
mkdir -p .captures/demo-scripts
```

Note: `.captures/` is gitignored; generated scripts are local artifacts.

### Step E2: Derive filename slug

Derive a short kebab-case slug from the bead title (first 3–5 meaningful
words, lowercased, punctuation stripped, hyphenated).
Filename: `<bead-id>-<slug>.md`.

Examples:

- `sl-8jv-conv-ui-polish.md`
- `sl-ya9-gc-demo-script.md`

### Step E3: Write the file

Save the validated script to `.captures/demo-scripts/<bead-id>-<slug>.md`
using the `Write` tool.

### Step E4: Print summary to caller

Print exactly this summary format (do not add extra commentary before or
after):

```text
## Demo Script Generated: <bead-id>

Script: .captures/demo-scripts/<bead-id>-<slug>.md
Bead:   <id> — <title>
PR:     #<num> (or "none" if no PR)
Steps:  <N>
Start:  <URL>

To capture: invoke demo:capture with this script.
```

If validation had unresolved failures, append a `## Warnings` section
listing them before the "To capture" line.

## Integration with `demo:capture`

This skill intentionally does NOT invoke `demo:capture`.
The caller is responsible for the handoff, usually by running:

```text
/demo:capture <paste contents of .captures/demo-scripts/<id>-<slug>.md>
```

This matches how `demo:epic` separates script generation from execution,
and lets a caller review the script before committing to a long-running
video capture session.

## Failure Modes Summary

| Condition                         | Action                                                 |
| --------------------------------- | ------------------------------------------------------ |
| Bead not found                    | Stop with clear error                                  |
| Bead has zero user-facing changes | Stop with Phase B report, no script                    |
| Branch not fetchable              | Fall back to description + notes only                  |
| No PR on bead                     | Skip Step A5, proceed with other sources               |
| Validation fails after 2 rewrites | Save anyway + warn in summary                          |
| More than 12 steps after dedup    | Narrow with implicit `--focus` on highest-impact route |
