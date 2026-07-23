---
name: demo:capture
description: Records a UX demo as a narrated MP4 video by driving the browser via Playwright MCP
---

# Demo Capture (Playwright MCP)

Capture a narrated demo video that **proves features work**, not just shows screens where features live.

## Input

You MUST receive a complete markdown demo script.
Do not invent or improvise a demo — if no script is provided, ask the caller for one.

### Demo Script Format

The script must contain these sections:

- `# Demo: <title>` — title, used in the output filename
- `**Start:** <url>` — URL where the demo begins
- `**Auth:** yes|no` — whether authenticated session is needed (default: yes).
  Auth is handled automatically by the Playwright MCP server.
- `## Steps` — ordered list where each item has:
  - **Bold heading** = narration text (burned into video overlay)
  - Body text = action description for the executor
  - `_Prove:_` = what the frame must demonstrate to pass (REQUIRED)
  - `_Fail if:_` = conditions that mean the frame failed its purpose (REQUIRED)
- `## Scrutiny` (optional) — items to actively investigate.
  These make demos critical rather than superficial.

### Script Validation (Before Execution)

**The caller is responsible for validating the script before dispatching.**
For each step, the caller must verify:

1. The `_Prove:_` criterion is **achievable** with the current app state and data
2. The navigation path will reach a page state that satisfies the proof
3. Seed data or existing documents contain the necessary content

**Example of a bad script step (caught by validation):**

```markdown
3. **Word-level diff highlighting**
   Open Compare to Original on the blog post document.
   _Prove:_ Colored spans within a line show which words changed
   _Fail if:_ All changes are pure additions with no modified lines
```

If the document was created from empty, Compare to Original will only show additions.
The caller should check this before writing the step — navigate to the page, inspect
the data, and choose a path that exercises the feature (e.g., Version History diffs
between intermediate versions where text was modified).

**Do not dispatch the executor until every `_Prove:_` criterion is confirmed achievable.**

## Execution

### Prerequisites Check

Before dispatching the executor, verify:

1. Playwright MCP server is available (test with `browser_snapshot`)
2. The app is accessible (the executor subagent will navigate to the start URL as its first action)
3. ImageMagick 7 is installed (`magick --version` — required for text overlays)

If any check fails, report the issue and stop.

### Dispatch Executor Subagent

Generate a timestamp slug for this capture session (e.g., `20260327T143022`).

Dispatch a **general-purpose subagent** with the following prompt:

````text
You are a demo executor. Drive the browser via Playwright MCP tools to capture a narrated demo.

## Demo Script

<paste the full markdown demo script here>

## Your Task

Execute this demo by driving the browser. Your job is to capture frames that
**prove each feature works** — not just show the page where the feature lives.

**First, resize the browser viewport** to 1440x900 using `browser_resize` with width 1440 and height 900.
This ensures screenshots are large enough for readable narration overlays and the app renders its full desktop layout.

For each step:

1. `browser_navigate` to the start URL (first step only)
2. `browser_snapshot` — read the page, understand what's actually there
3. Execute the action: `browser_click`, `browser_fill_form`, `browser_navigate`, etc.
4. `browser_wait_for` the page to settle after actions
5. `browser_snapshot` again — **evaluate the proof criterion**
6. **Proof check:** Does the current page state satisfy the `_Prove:_` criterion?
   - **YES:** `browser_take_screenshot`, set `proof` to `"passed"`
   - **NO — adaptable:** Try an alternative path (different data, different navigation) to satisfy the proof. You have up to 2 adaptation attempts per step. If an adaptation succeeds, `browser_take_screenshot` and set `proof` to `"adapted"`.
   - **NO — unadaptable:** `browser_take_screenshot` the failure state, set `proof` to `"failed"`, set `"severity": "error"`, and note what's missing
7. Note narration, the final `proof` value written for the step, and any observations

**Adaptation examples:**
- Proof requires "modified lines with word-level highlights" but current view shows only additions → navigate to Version History, find a version with modifications, click "Show diff" there instead
- Proof requires "3 documents on dashboard" but only 2 visible → note the discrepancy, screenshot what exists, mark as error

You are NOT bound rigidly to the script actions. The `_Prove:_` criterion is the contract — the action is a suggestion. If you need to take a different path to satisfy the proof, do it.

**IMPORTANT: "Feature not demonstrated" is an error, not a warning.**
If a frame's purpose is to showcase a feature and the screenshot doesn't visibly prove
the feature works, that is `"severity": "error"`. Warnings are for cosmetic issues
(visual oddity, unexpected layout) where the feature IS demonstrated but looks off.

## Viewport Changes

When the script calls for viewport resize (e.g., mobile at 375px):
- The screenshots will be a different resolution than desktop frames
- This is expected — the video assembler handles letterboxing
- Always `browser_resize` back to 1440x900 before any subsequent desktop steps

## Screenshot Capture

The Playwright MCP server is configured with `--output-dir ./.captures`.
Use `browser_take_screenshot` with the `filename` parameter set to
`<timestamp>/01-slug.png`, `<timestamp>/02-slug.png`, etc.
This saves screenshots directly into the captures subdirectory — no copying needed.

After ALL browser work is complete, use the Write tool to create these files
in `.captures/<timestamp>/`:

**manifest.json:**
```json
{
  "title": "<from demo script title>",
  "frames": [
    {
      "file": "01-description.png",
      "narration": "Short narration text",
      "duration": 3,
      "observation": null,
      "proof": "passed",
      "severity": null
    }
  ]
}
```

**Frame fields:**
- `narration`: Under 80 characters. Use the **bold heading** from the demo script step.
- `observation`: Details, discrepancies, or what was adapted. Use for context that doesn't fit in narration.
- `proof`: `"passed"` if the `_Prove:_` criterion is satisfied, `"failed"` if not, `"adapted"` if an alternative path was used to satisfy it.
- `severity`: `null` (normal), `"warning"` (cosmetic issue, feature IS demonstrated), `"error"` (feature NOT demonstrated or broken functionality).

**CRITICAL: `"severity": "error"` whenever `"proof": "failed"`.**
A frame that fails its proof is always an error, never a warning.

Default frame duration is 3 seconds. Use 4-5 seconds for complex screens.

**issues.json:**
```json
[]
```

If issues were found:
```json
[
  {
    "severity": "warning",
    "step": 1,
    "description": "what went wrong",
    "screenshot": "filename.png",
    "adapted": false
  }
]
```

## Scrutiny Phase

After all scripted steps, work through each Scrutiny item. Each gets its own screenshot(s) and annotation. Look critically — the goal is to find issues, not just confirm happy paths.

### issues.json Fields

- `severity`: `"warning"` (cosmetic) or `"error"` (feature not demonstrated / blocking)
- `step`: Step number where the issue occurred
- `description`: What went wrong
- `screenshot`: Filename of the screenshot capturing the issue
- `adapted`: `true` if the step reached its proof criterion via an adaptation path, `false` otherwise

## Failure Handling

- Cosmetic issues (visual oddity, element in unexpected position): screenshot it, note severity "warning", continue
- Feature not demonstrated (proof criterion not met after 2 adaptation attempts): screenshot failure state, note severity "error", continue with remaining steps
- Blocking issues (404, auth failure, app crash): screenshot the failure, note severity "error", STOP and return what you have

## Important

- Take your time. Use `browser_snapshot` before every action to see the real page state.
- Always wait for the page to fully render before taking screenshots — use `browser_wait_for` with a short timeout (1-2s) to let animations, lazy-loaded content, and styles settle.
- Number screenshots sequentially: 01-, 02-, 03-, etc.
- Write manifest.json and issues.json as actual files using the Write tool.
- Screenshots save directly to `.captures/<timestamp>/` via the MCP `--output-dir` config.
````

### Post-Execution: Review Phase

After the subagent returns, **review the results before assembling**:

1. Read `manifest.json` and `issues.json` from the captures directory
2. Check for any frames with `"proof": "failed"`:
   - If failed frames exist, report them to the caller **before** assembling
   - The caller decides: re-run with an updated script, accept the gaps, or skip the video
3. If all proofs passed (or caller accepted gaps), assemble:
   ```bash
   pnpm tsx scripts/assembleDemoVideo.ts .captures/<timestamp>
   ```
   To disable audio narration, pass `--no-narrate`.

### Audio Narration (automatic)

When `OPENAI_API_KEY` is set in the environment, the assembly script automatically
generates spoken narration for each step and produces a `-narrated.mp4` alongside
the silent video. No extra flags are needed.

**How it works:**

1. Each frame's narration text is sent to the OpenAI TTS API (`tts-1` model, `nova` voice)
2. Frame durations are extended if the spoken audio is longer than the default
3. Audio segments are concatenated with silence for the cover frame
4. The narration track is muxed into a separate `<name>-narrated.mp4`

**Environment variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | _(none)_ | Required for TTS. Without it, only the silent video is produced |
| `DEMO_TTS_MODEL` | `tts-1` | OpenAI TTS model (`tts-1` or `tts-1-hd`) |
| `DEMO_TTS_VOICE` | `nova` | Voice ID (`alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`) |

**Cost:** ~$0.01 per demo at `tts-1` rates (~500-800 characters of narration total).

**Graceful degradation:** If `OPENAI_API_KEY` is not set, or if TTS generation fails
for any reason, the script silently falls back to producing only the silent video.
No error is raised.

### Reporting

**On success (all proofs passed):**

```markdown
## Demo Result

**Status:** complete
**Video:** e2e/demos/<date>-<title-slug>.mp4
**Narrated:** e2e/demos/<date>-<title-slug>-narrated.mp4 _(if TTS available)_
**Frames:** <N> captured (<N> passed, <N> adapted)
**Duration:** ~<N>s
**Issues:** <N> warnings, <N> errors

### Adaptations (if any)

- Step <N>: <what was changed to satisfy proof>

### Warnings (if any)

- <description> (frame <N>)
```

**On partial success (some proofs failed):**

```markdown
## Demo Result

**Status:** incomplete — <N> frames failed proof criteria
**Video:** NOT assembled (failed proofs must be resolved first)

### Failed Proofs

| Step | Criterion | What happened |
| ---- | --------- | ------------- |
| <N>  | <prove>   | <description> |

### Options

1. Update demo script to use a path that satisfies the proof
2. Accept the gap and assemble anyway
3. Fix the underlying feature
```

**On complete failure (no screenshots captured):**

```markdown
## Demo Result

**Status:** failed
**Error:** <description>
```
