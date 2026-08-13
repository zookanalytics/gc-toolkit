---
name: tk-roz7f — "gc doctor --json emits invalid JSON" is a misdiagnosis
description: Byte-level proof that gc doctor --json's serializer is correct (Go json.Encoder), that the deacon's unparseable payloads were corrupted downstream by a backslash-collapse (not double-escaping in the producer), and why no code change to the serializer or the pipefail check is warranted. Recommends close-as-no-op or re-scope.
---

# tk-roz7f — the doctor payload is corrupted *after* the binary, not by it

## Scope

Record of the investigation into P1 **tk-roz7f** ("gc doctor --json emits
invalid JSON: shell-script finding content is double-escaped so jq/json.loads
reject the payload"). It holds the evidence and the disposition
recommendation. It is **not** authoritative on how `gc doctor` should behave —
it documents what one investigation found on this bead.

## Verdict

**The bead's root-cause diagnosis is wrong.** `gc doctor --json` does not
double-escape and does not emit invalid JSON. Its serializer is Go's
`encoding/json` encoder and is structurally incapable of producing the reported
corruption. The unparseable payloads the deacon captured were corrupted
*downstream of the binary* by a backslash-collapse (the signature of a JSON
payload round-tripped through a backslash-interpreting command such as zsh
`echo`). The one byte the deacon read as evidence — `\"$CALLS\"` — is
**correct** JSON escaping; the actual break is a *different*, under-escaped byte
76 columns later.

No defect exists in the named fix locus (the JSON serializer, or the
`check-pipefail-grep-q` check). Recommendation: close as no-op, or re-scope to
"guard agents against transporting the payload through backslash-unsafe
commands." See [Recommendation](#recommendation).

## What the bead claimed

- Symptom: `gc doctor --json` returns rc=1 (normal — findings present) but the
  JSON is unparseable; `jq: parse error: Invalid numeric literal at line 1,
  column 32456`.
- Diagnosis (deacon): the bytes around the failure are `\"$CALLS\"` "embedded
  inside a finding … a shell-quoted string … that was DOUBLE-ESCAPED incorrectly
  when serialized into the JSON payload."
- Fix locus (deacon): "the JSON serializer for whatever check emits the
  escaped-shell-content field (likely the pipefail/grep-q script-scan check) —
  ensure finding message/detail strings are JSON-encoded once via the encoder,
  not hand-escaped/double-escaped."

## The serializer cannot produce this corruption

The `gc doctor --json` path, traced in gascity (`rigs/gascity`):

- `cmd/gc/cmd_doctor.go` `doDoctor`: in `--json` mode it calls
  `d.RunCollect(ctx, fix)` (which is **not** handed `stdout`) and then
  `writeDoctorJSON(stdout, report)` — stdout receives exactly **one** write, of
  the whole report. Progress/log lines (`order "…" declares scope = "rig"`) go
  to **stderr**, so nothing interleaves into the JSON line.
- `writeDoctorJSON` copies each check's `Message`/`Details []string` into a
  struct and calls `writeCLIJSONLine` (`cmd/gc/json_schema.go:525`):
  `json.NewEncoder(stdout)` with `SetEscapeHTML(false)`, then `enc.Encode(...)`.
- Each pack check's stdout is captured with `cmd.CombinedOutput()`
  (`internal/doctor/pack_checks.go`) into a buffer and split by
  `parseScriptOutput` with plain `strings.Split(output, "\n")` +
  `strings.TrimSpace`. No hand-escaping anywhere.

`encoding/json` produces valid JSON for **any** Go string: control bytes become
`\uXXXX`, invalid UTF-8 becomes U+FFFD, and every `"`/`\` is balanced. It can
**never** emit a lone `\` immediately before a closing `"`. A grep of the whole
gascity doctor tree for hand-rolled escaping (`strconv.Quote`, `ReplaceAll`,
`Sprintf(... \" ...)`) finds only test files. There is no second JSON path.

This serializer has been `json.Encoder`-based since gascity #2349 (old,
stable). The running binary is `v1.4.1-…-85cd90de6695+dirty`; commit
`85cd90de6` is an **ancestor** of gascity HEAD (`6f9fd18e0`, one commit ahead),
and `git diff 85cd90de6695 HEAD -- cmd/gc/cmd_doctor.go cmd/gc/json_schema.go
internal/doctor/pack_checks.go` is **empty** — the serializer is byte-identical
in the built binary and at HEAD. The `+dirty` suffix touched nothing on this
path (see the empirical runs below).

## Empirical: current output is valid

- Three direct `gc doctor --json > file` runs with this exact binary: all
  **valid** JSON (`jq -e .` passes).
- The live gate cache `/home/zook/loomington/.gc/runtime/doctor-findings.json`
  (written by the deacon patrol at 22:50Z) is **valid**.
- The `check-pipefail-grep-q` result *is* present in the valid output, with the
  same `$CALLS`-bearing findings the deacon saw — correctly single-escaped.

## The actual corruption (byte-level)

The deacon's failing payloads survive in deacon session scratchpads, e.g.
`…/gc-agents-deacon/5299128e-…/scratchpad/doctor.json` (39901 bytes), which
`jq` rejects at column 32456. Python is more precise:

```
JSONDecodeError: Expecting ',' delimiter at pos=32340
context: …gc-helm-open.test.sh:120:printf '%s' \"$CALLS\" | grep -q |<<HERE>>|'bd create …tk-real1' \"
```

The `\"$CALLS\"` the deacon flagged is **correct** — `\"` is the JSON escape for
`"`, and it decodes to `"$CALLS"`. The real defect is the **end** of that same
detail line. Diffing the first `details` element (source line
`gc-helm-open.test.sh:120`) between a corrupt and a valid capture, the *only*
difference is one byte:

```
INVALID:  …grep -q 'bd create .*--title visit: tk-real1' \","…   (one backslash)
VALID:    …grep -q 'bd create .*--title visit: tk-real1' \\","…   (two backslashes)
```

The source line ends in a shell line-continuation `\`. Valid JSON must encode a
trailing backslash as `\\`; the corrupt payload has a single `\`, so the
following `"` reads as an **escaped quote** — the string never closes, parsing
runs into the next element, and the structure desynchronizes until `jq`/Python
give up (at column ~32340–32456, ~7 KB before EOF — *not* a truncation).

`json.Encoder` never emits that single trailing backslash. So the corrupt
payloads are **not** the raw stdout of `gc doctor --json`.

## Root cause: a downstream backslash-collapse

A full payload that is byte-perfect except for collapsed backslashes is the
signature of the JSON being passed through a **backslash-interpreting command**.
This environment's shell is **zsh**, whose `echo` interprets escape sequences
(`\\` → `\`, `\n` → newline). Capturing `V=$(gc doctor --json)` and re-emitting
it with `echo "$V"` — or any equivalent round-trip — collapses every `\\` to
`\`, which breaks the first `\\` that precedes a `"` (the trailing
line-continuation backslash above). A direct pipe or redirect
(`gc doctor --json | jq .`, `gc doctor --json > f`) preserves bytes and does
**not** reproduce it — consistent with the interleaving of valid and invalid
captures across the same binary on the same day (08:31 valid, 13:29 invalid,
18:21 valid, 18:38/18:44/20:57 invalid, 21:43/23:27 valid).

## Production consumers are already byte-safe

Nothing in the production path round-trips the payload unsafely:

- Deacon patrol (`formulas/mol-deacon-patrol.toml`): captures with
  `DOCTOR_JSON=$(timeout 300 gc doctor --json)` (command substitution preserves
  backslashes) and feeds the gate with `printf '%s' "$DOCTOR_JSON" | … publish -`
  (`printf '%s'` is literal). It also validates with `jq -e 'has("results")'`
  and, on failure, refuses to publish and mails an alert — fail-loud, correct.
- `assets/scripts/doctor-finding-gate.sh`: `publish` buffers, runs `payload_ok`
  (`jq -e 'type=="object" and (.results|type=="array")'`), and installs via
  `cp`/`mv` (byte-exact). An unparseable payload is refused, leaving the prior
  cache in place; `probe --no-run` returns indeterminate. Fail-soft, correct.

So the bead's stated impact ("the patrol cannot validate the payload … the gate
cache goes stale") does not occur through production code: the patrol's `$( … )`
capture is valid, and the current cache is fresh and valid. The stale-cache risk
only materializes for an ad-hoc capture that round-trips the payload unsafely —
which is what produced the deacon's scratchpad files.

## Recommendation

1. **Close tk-roz7f as no-op / not-a-defect** on the serializer and the
   `check-pipefail-grep-q` check — both are correct. Do **not** "encode once
   instead of twice"; the encoder already encodes exactly once, correctly.
2. If any residual hardening is wanted, the *only* honest target is the capture
   discipline: agents (and any future consumer) must transport the doctor
   payload byte-safely — `printf '%s'`, a redirect, or a pipe — and never
   `echo "$VAR"` a JSON payload under zsh. That is guidance/behavior, not a
   serializer or check bug.
3. The deacon's diagnostic step that read `\"$CALLS\"` as "double-escaped"
   should treat a mid-payload `jq` failure as *possibly its own capture method*,
   not necessarily the producer — re-capture with a redirect before filing.
