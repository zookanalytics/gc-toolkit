---
name: Measurement — the harness seed floor and which spawn flags cut it
description: What the base system prompt + tool schemas actually cost per request, measured per flag and per tool against claude 2.1.241, with the two findings that dominate the answer. Read before changing spawn flags or .gc/settings.json.
---

# The harness seed floor — measured

Bead tk-yhwfv.2, measured 2026-08-23 against `claude` **2.1.241**. Sibling of
tk-yhwfv.1. Measurement only: **no config change is landed here**, per the
bead's own disposition clause.

## Headline

The three flags the bead asked about are worth **259**, **~70–122**, and
**0** tokens. They are not the lever.

The lever is **which tools are eagerly loaded**, and it is large: denying four
tools with *zero recorded uses across the whole city in 24 hours* removes
**12,750 tokens from every request**, cwd-independent and exactly additive.

And the thing nobody was looking for: **tool deferral is worth 15.1k–18.6k per
request and one flag away from being switched off.** `--disallowed-tools
ToolSearch` does not save tokens — it *adds* 15,803 (+42%), because denying
ToolSearch disables deferral and every deferred schema loads eagerly. That is a
config-safety finding, not an optimisation.

## Method

`specs/tk-yhwfv.2/seed-probe.sh`, one arm per invocation. Each arm spawns one
print-mode request with the **real spawn shape** — taken from a live agent's
process line, not guessed:

    claude --dangerously-skip-permissions --effort medium --model claude-sonnet-5 \
           --settings /home/zook/loomington/.gc/settings.json <arm flags> -p '<11 words>'

then reads the FIRST assistant record of the new transcript and sums
`input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. Raw
results: `specs/tk-yhwfv.2/results.tsv`.

**The measurement is exactly deterministic.** `control` and `control-repeat`
returned 37,344 both times, to the token. Every delta below is therefore a real
effect, not a sample.

Two caveats stated up front:

- Print mode (`-p`), not an interactive session. Every arm shares it, so the
  DELTAS transfer; the absolute floor may not.
- The prompt is 11 words where a real agent's is 10k–40k. The deltas are
  independent of that — confirmed by re-running two arms in a real agent home
  (`.gc/agents/gc-toolkit/witness`, control 47,263) and getting **identical**
  deltas to the bare directory, to the token.

## The three questions the bead asked

### 1. Does denying a tool remove its schema, or only its use?

**It removes the schema, exactly and additively — but only for tools that were
eagerly loaded in the first place.**

| denied | seed | Δ |
|---|---:|---:|
| *(control)* | 37,344 | — |
| `Workflow` | 29,444 | **−7,900** |
| `Task` | 33,720 | **−3,624** |
| `Skill` | 34,612 | −2,732 |
| `Bash` | 35,117 | −2,227 |
| `ScheduleWakeup` | 35,649 | −1,695 |
| `Read` | 36,438 | −906 |
| `ReportFindings` | 36,523 | −821 |
| `Edit` | 36,765 | −579 |
| `ListAgents` | 36,939 | −405 |
| `Write` | 36,984 | −360 |
| `Glob` / `Grep` / `TodoWrite` / `Artifact` / `AskUserQuestion` / `SlashCommand` | 37,344 | **0** |
| `WebSearch WebFetch NotebookEdit` (3 at once) | 37,324 | −20 |
| `ToolSearch` | 53,147 | **+15,803** |

The zeros are the finding. Those tools are **deferred** in this build: the seed
carries their NAMES (~7 tokens each) and nothing else, and `ToolSearch` fetches
a schema on demand. Denying a deferred tool saves nothing because it was never
there. Denying an eager one saves its whole schema.

Additivity was checked three times and holds exactly:

| combination | seed | Δ | sum of parts |
|---|---:|---:|---:|
| `Workflow Task ReportFindings ListAgents` | 24,594 | −12,750 | −12,750 |
| `Workflow ScheduleWakeup ReportFindings ListAgents` | 26,523 | −10,821 | −10,821 |
| …+ `--exclude-dynamic…` + `--strict-mcp-config` | 26,264 | −11,080 | −11,080 |
| `Workflow Task Skill ScheduleWakeup ReportFindings ListAgents` | 20,167 | −17,177 | −17,177 |

So: **yes, per-role tool trimming is a lever**, worth up to ~17k/request, and it
is bounded by the eager set — roughly 21k of the 37.3k floor.

### 2. `--exclude-dynamic-system-prompt-sections` — what does it drop?

**Nothing. It moves.** 37,085 vs 37,344: **−259 tokens**, and its own help text
says why — it relocates cwd/env/memory/git-status sections *from the system
prompt into the first user message*, "improves cross-user prompt-cache reuse".
It is a cache-locality flag, not a seed flag. Nothing observably stopped
working, and its real value (cache hit rate across machines) is not measurable
by this method.

### 3. `--strict-mcp-config` — what do the rig `.mcp.json` servers cost?

**68–122 tokens. The bead's premise does not hold in this build.**

| cwd | deferral | control | `--strict-mcp-config` | MCP cost |
|---|---|---:|---:|---:|
| `rigs/gascity` (excalidraw, HTTP) | on | 64,052 | 63,930 | **122** |
| `rigs/signal-loom` (next-devtools, playwright) | on | 54,045 | 53,977 | **68** |
| `rigs/signal-loom` | **off** (`ToolSearch` denied) | 72,638 | 70,620 | **2,018** |

The servers really do connect — verified with `claude --settings … mcp list`:
excalidraw ✔, next-devtools ✔, **playwright ✘ (CONNECTION_CLOSED)**. Their
schemas really are worth ~2,018 tokens. They cost 68 anyway, because **MCP tools
ride the same deferral mechanism as the built-ins.** The last row is the proof:
turn deferral off and the MCP cost appears in full.

(Worth noting separately: without `--settings`, the same servers report "⏸
Pending approval". `enableAllProjectMcpServers: true` in
`.gc/settings.json` is what connects them, so this only applies to
city-spawned sessions — and `playwright` has been failing to connect in every
one of them.)

## Two findings the bead did not ask for

### Deferral is the whole game, and it is one flag from off

`--disallowed-tools ToolSearch` costs **+15,803** on sonnet-5 (+42%) and
**+15,069** on opus-5; in `rigs/signal-loom` it costs **+18,593**, because the
MCP schemas come back too. Nothing in the city denies ToolSearch today. The
recommendation below therefore carries a hard constraint: **whatever tool
trimming is adopted, ToolSearch must never be in the deny list**, and any
future `--allowed-tools` allowlist must include it. An allowlist that forgets it
would silently raise every request in the city by ~40%.

### The model changes the floor by 11k

Same cwd, same flags, same prompt:

| model | seed | with `ToolSearch` denied |
|---|---:|---:|
| claude-opus-5 | **26,102** | 41,171 |
| claude-sonnet-5 | **37,344** | 53,147 |

**11,242 tokens per request, on identical inputs.** The same direction shows in
the 24h census (sonnet-5 mean first-request 72,095 vs opus-5 64,050). This is a
large share of the "34,018 to 74,685" spread the bead says nobody has explained
— the rest is role prompt, CLAUDE.md and hook output, all of which vary by role.

It bears directly on a decision the city already made: `claude-watch`
(sonnet-5) was adopted for witness/refinery/deacon to cut spend, and those are
the highest-volume seed payers in the census (2,599 of 2,954 sampled sessions).
The per-token price is lower; the per-request token count is **11k higher**.
Whether that trade is still positive is tk-yhwfv.1's arithmetic, not this
bead's — but it should be re-checked with this number in hand.

## What the city actually uses

Every `tool_use` across every local transcript in the trailing 24h
(67,579 assistant requests):

| tool | uses |
|---|---:|
| Bash | 32,275 |
| Read | 2,622 |
| Monitor | 163 |
| Edit | 106 |
| ToolSearch | 89 |
| Write | 41 |
| ScheduleWakeup | 37 |
| Skill | 12 |
| TaskOutput / TaskStop | 9 |
| AskUserQuestion | 1 |
| **Workflow** | **0** |
| **Task** | **0** |
| **ReportFindings** | **0** |
| **ListAgents** | **0** |

`Workflow`, `Task`, `ReportFindings` and `ListAgents` cost **12,750 tokens on
every one of those 67,579 requests** and were used zero times. `Task`'s zero is
not an accident — the polecat prompt says "Do not call the AgentTool unless the
user requested it".

## Scale

Measured over the same 24h window: 67,579 requests, **8,446.6M** context tokens
(0.1M fresh input, 212.8M cache-creation, **8,233.8M cache-read** — 97.5% of
every seed token is a cache read, which is what makes the seed a volume problem
rather than a latency one).

| change | Δ/request | Δ/day | share of all context tokens |
|---|---:|---:|---:|
| deny the four zero-use tools | −12,750 | −861.6M | **−10.2%** |
| …+ `Skill` + `ScheduleWakeup` (both ARE used) | −17,177 | −1,160.9M | −13.7% |
| `--exclude-dynamic…` + `--strict-mcp-config` | −~330 | −22.3M | −0.3% |
| **deny `ToolSearch` (do not)** | **+15,803** | **+1,068.1M** | **+12.6%** |

Deliberately given in tokens and percentages, not dollars: 97.5% of the volume
is cache-read, which is priced differently from fresh input and differently
again per model, and tk-yhwfv.1 owns the rate card. Applying it to the token
figures above is one multiplication.

## Recommended config change — NOT landed here

**Change:** add to the claude provider's spawn args (gascity
`internal/worker/builtin/profiles.go`, or per-agent `option_defaults` in
`city.toml`):

    --disallowed-tools "Workflow Task ReportFindings ListAgents"

**Not** in `.gc/settings.json`: that file is read by every agent in the city, so
a bad entry there is a city-wide outage rather than a rig-local one — the bead
says so, and this measurement agrees.

**Expected:** −12,750 tokens/request, ~−10.2% of all context tokens/day.
Cwd-independent and additive, verified in two directories.

**Blast radius, honestly:**

- **`Task`** removes subagents entirely. Zero uses in 24h, but an operator who
  asks for one gets a refusal instead of a subagent. This is the only entry with
  a plausible on-demand use, and it is also the second-largest saving (3,624).
  It could be kept out of the deny list for 3,624 tokens.
- **`Workflow`** (7,900 — the largest single item) removes multi-agent
  orchestration. It is opt-in by design and the pack references it nowhere.
- **`ReportFindings`** (821) is the structured-output tool for `/code-review`;
  denying it makes that command fall back to prose. The city's codex reviews do
  not go through it.
- **`ListAgents`** (405) is the address book for `SendMessage`, which also has
  zero uses.
- **`ToolSearch` MUST NOT be denied** — see above. +15,803.
- 24h of zero use is not proof of never-needed. A per-role deny list (polecats
  and witnesses trimmed; mechanik/mayor left whole) is the conservative shape
  and gets most of the saving, since those roles are the volume.

**Not recommended:** `--exclude-dynamic-system-prompt-sections` (−259) and
`--strict-mcp-config` (−68/−122) are within noise of free. `--strict-mcp-config`
has an unrelated argument for it — `playwright` has been failing to connect on
every signal-loom session — but that is a broken-config bug to fix at the
`.mcp.json`, not a token lever.

## Reproducing

    specs/tk-yhwfv.2/seed-probe.sh <label> <cwd> [flags...]    # one arm, one request
    specs/tk-yhwfv.2/seed-census.sh <out.tsv>                  # first-request census, free

`PROBE_MODEL` overrides the model; `RESULTS` sets the output file. Each arm
costs one request at the seed size being measured. The census reads local
transcripts only and costs nothing.
