---
name: Settling check-agent-prompt-integrity — does a pack-qualified prompt_template fail loud?
description: Evidence and verdict for tk-5wdy8 — what gascity actually does with `<pack>//<subpath>`, which configurations really render the 16-line stub, and why the doctor check was rewritten to test resolution instead of spelling.
---

# Does a pack-qualified `prompt_template` fail loud, or fall back to a stub?

**Verdict: it fails loud. The check was a false positive; the code comment
it contradicted was right.** The check has been rewritten rather than
retired, because a real (narrower) stub hazard does exist — just not the
one the check was looking for, and not one that reading `agent.toml` can
ever detect.

The bead framed this as an exclusive-or: either (a) the check is wrong and
the comment is right, or (b) the comment is stale and there is a real
silent-degradation bug. The answer is (a) on the contested claim, plus a
genuine defect elsewhere that (b) was groping toward.

## What was contested

`doctor/check-agent-prompt-integrity` warned that two agents carried a
cross-pack `prompt_template` and were therefore exposed to "stub fallback":

- `agents/mayor-thread/agent.toml` → `gastown//agents/mayor/prompt.template.md`
- `agents/polecat-codex/agent.toml` → `gastown//agents/polecat/prompt.template.md`

Its stated premise: gascity resolves that form against the pack dir, and
when the path is absent it "silently renders the 16-line generic stub
instead of failing config load."

`agents/polecat-codex/agent.toml` asserted the opposite: the form resolves
via `resolvePackQualifiedAgentPaths`, and "an unknown pack fails config
load rather than silently falling back to the default agent prompt."

## What the resolver actually does

`resolvePackQualifiedAgentPaths` lives in
`internal/config/pack_qualified_path.go` (the bead cited `compose.go`,
which is the *call site*, at `compose.go:734`). It resolves `<pack>//<sub>`
against `cfg.PackDirs` / `cfg.RigPackDirs` — the **import closure**, i.e.
the content-addressed cache — and returns an error for an unknown pack
name, and a second error for an *ambiguous* one (a name resolving to more
than one imported dir).

Both halves of the check's premise are therefore wrong:

| Check's claim | Reality |
|---|---|
| resolves against the pack dir, "not the import cache" | resolves against the import cache |
| unknown pack degrades silently | unknown **and** ambiguous pack are hard config-load errors |

gascity asserts this itself, in
`internal/config/pack_qualified_path_test.go`:
`TestResolvePackQualifiedAgentPaths_UnknownPack` and
`..._AmbiguousPack` both require a non-nil error.

Confirmed live: every one of the city's 65 agent `prompt_template` values
resolves to an absolute path under `~/.gc/cache/repos/<sha>/…`, and both
contested files exist — 243 lines (mayor) and 326 lines (polecat), against
the check's own ">100 lines, 16 means the stub" criterion.

## The real hazard

Resolution validates the **pack name**. It does not validate the
**subpath**: the success path is a bare `filepath.Join(dir, sub)` with no
existence test. So a valid pack plus a stale subpath resolves happily to a
file that is not there — and the consequence is severe:

- `renderPromptWithMeta` returns an empty result whenever the template
  cannot be read (`cmd/gc/prompt.go`).
- `gc prime` treats empty as "legitimate minimal config" and falls
  through. The builtin worker-prompt branch below it is gated on
  `a.PromptTemplate == ""`, so an agent that *declares* a broken template
  skips that too and lands on `defaultPrimePrompt` — the 16-line stub.
- The readability precondition that would catch this is inside
  `if strictMode` (`cmd/gc/cmd_prime.go`), so only `gc prime --strict`
  is loud.

Verified against a scratch city (`[[agent]]` with a relative
`prompt_template`, provider catalog present so the config genuinely loads):

| Scenario | stdout | stderr | exit |
|---|---|---|---|
| template present | real prompt (3 lines) | — | 0 |
| template **missing** | 16-line stub | **empty** | **0** |
| template missing, `--strict` | — | `prompt_template … no such file or directory` | 1 |
| unknown pack, `gc config show` | — | `references unknown imported pack "nosuchpack"` | 1 |
| unknown pack, `gc prime` | 16-line stub | — | **0** |

Two things fall out of that last pair. The unknown-pack error is real and
loud — but it is loud in `gc config show`, **not** in `gc prime`, which
does not inherit the config-load failure and stubs anyway. And the
missing-file row needs no `//` at all: a plain relative path reproduces it.
The cross-pack form was never the variable.

## Why the check was rewritten, not retired

Retiring it would have been defensible — its premise was false and its two
findings were both false positives. But the property it was named for is
worth holding: *no agent silently renders the stub*. The old check could
not test that property, because the failure is invisible in `agent.toml`;
it is only observable after resolution.

So the check now asks gascity for the resolved config and asserts that
every agent's `prompt_template` names a readable file — whatever form it
was written in. That change:

- turns the two false positives green (they resolve; that is now *proven*
  per run rather than assumed);
- catches the actual hazard, including the plain-relative-path version the
  old check could never see;
- treats an unresolvable config as a finding rather than a skip, because
  `gc prime` degrades to the stub on exactly that condition.

It is city-wide by nature: an unreadable prompt is a defect wherever the
agent is declared, and scoping to this pack's own agents would miss
precisely the cross-pack references that motivated the check. Outside a
city — no `gc` on PATH, or no `GC_CITY_PATH` — it reports OK, because
resolution is a runtime property and a static reference alone is not
evidence of anything. That is the same "warn on what you have not
observed" mistake the rewrite exists to remove.

`doctor/check-agent-prompt-integrity/run.test.sh` covers it hermetically
in 13 cases; case 1 is the regression (a resolvable cross-pack reference
must be OK) and cases 9–10 are the fail-closed pair (an unverified check
must never report OK).

## Loose end, deliberately not fixed here

The gascity behaviour is arguably wrong: a declared-but-unreadable
`prompt_template` is never an intentional configuration, and defaulting it
to the stub at exit 0 discards the operator's stated intent in silence.
The narrow fix would be to apply the strict-mode readability precondition
whenever `PromptTemplate != ""`, so a broken reference fails at spawn
rather than producing a doctrine-less agent.

That is a change to gascity, not to this pack, and it is out of scope for
this bead. It is recorded here rather than filed as a bead because the
exposure is now *detected* — the rewritten check fails loudly on any
instance of it — so the remaining gap is quality-of-error, not silence.

## The deacon's suggested repro

The bead notes flagged it already, and it is worth keeping flagged:
`gc agent render <name> | wc -l` is not a real command — `gc agent` has
only `add`/`list`/`suspend`/`resume`. The working probes are
`gc config show` (resolved paths) and `gc prime --strict <agent>` (fails
on exactly the unreadable-template condition). The check's own output now
names the second one.
