---
name: Non-string bead metadata in the hook claim path — verification
description: Evidence that the running gc tolerates non-string metadata in `gc hook --claim`, and the measured `bd` metadata write-path typing that supersedes the normalization method recorded on tk-v3jwg.
---

# Non-string bead metadata in the hook claim path

`gc hook --claim` decodes the whole `work_query` result set before it picks a
candidate. A bead carrying a JSON number where the decoder expects a string
once failed that decode for the entire set, so no worker sharing the query
could claim anything.

## The two layers that carry the fix

`beads.Bead.Metadata` is `beads.StringMap` (`internal/beads/bdstore.go`).
Its `UnmarshalJSON` decodes into `map[string]json.RawMessage`, keeps values
that are already strings, and coerces every other value to its JSON text
form. A number, a boolean, an object, or an array in metadata therefore
decodes to a string instead of failing.

`decodeHookClaimBeads` (`cmd/gc/cmd_hook_claim.go`) splits the result array
into `json.RawMessage` elements before typed decoding and decodes each one
independently. A bead that still fails is collected as a skip with a
diagnostic naming its id, and the remaining beads stay in the candidate set.
This layer covers type errors outside metadata, which the coercion does not
repair.

## Measured behaviour

Run through `gc hook --claim --json` against a synthetic city whose agent
`work_query` emits a literal JSON array, so the decoder input is controlled
exactly. The control binary is built from `c02b3be84^`, the parent of the
commit that changed `Bead.Metadata` to `StringMap`.

| `work_query` element | gc 1.4.1 | control, pre-fix |
|---|---|---|
| `"pr_number": 163` | claim proceeds, `ok: true` | `cannot unmarshal number into Go struct field .0.metadata.pr_number of type string` |
| `"pr_number": "163"` | claim proceeds, `ok: true` | claim proceeds, `ok: true` |
| `"dead_sessions": ["a","b"]` | claim proceeds, `ok: true` | `cannot unmarshal array into Go struct field .0.metadata.dead_sessions of type string` |
| `"status": 999` | skips that bead, batch survives | whole batch fails |

The string row is the negative control. It passes on both binaries, so the
three failures isolate to the non-string value rather than to the probe
setup or to the age of the control binary.

On the `"status": 999` row the running binary emits
`skipping undecodable bead probe-numeric-1` and still returns
`action: drain, reason: no_work`, which is the batch surviving a bead the
coercion cannot repair.

The array row has no counterpart in `cmd/gc/cmd_hook_claim_metadata_test.go`,
which pins the number and boolean cases. Arrays are live in the store, so the
shape is worth holding.

## Non-string metadata that is live now

`tk-ae96t` carries `host_session_epoch` as JSON number `1`. `tk-xatdy`
carries `dead_sessions` and `recovered` as JSON arrays. Both read back at
those types through `bd`, so the store genuinely holds them and the reader
does not stringify on the way out.

Neither bead was in the polecat `work_query` result set when this was
measured, so a successful live claim says nothing about either one. The
controlled probe above is what covers their shapes.

## `bd --set-metadata` does not type-infer

Measured on bd 1.2.2, through both `bd update` and `gc bd update`, reading
back with `bd show --json`:

| write | stored value | stored type |
|---|---|---|
| `--set-metadata k=163` | `"163"` | string |
| `--set-metadata k=true` | `"true"` | string |
| `--set-metadata k=abc` | `"abc"` | string |
| `--set-metadata 'k="163"'` | `"\"163\""` | string |
| `--metadata @blob.json` with `999` | `999` | number |

Two consequences.

The literal-JSON-quote form stores the quote characters as part of the value.
Applying it to normalize a key produces a doubly-quoted string, so it
corrupts the value it is meant to repair. The method recorded on tk-v3jwg
rests on `--set-metadata` inferring a number from a bare value, which this
bd does not do.

`--metadata` preserves a JSON number as written, so it remains a route by
which a non-string value enters metadata. It is the write path left to reason
about, and the reader coercion above is what keeps it harmless.

## Scope note

Stringifying at call sites is not pursued. `host_session_epoch` is a counter
whose numeric type is meaningful, and the reader already tolerates every
shape measured here.

The typing contract itself — which keys hold which types, and what enforces
it — belongs to the metadata registry in `lifecycle/lifecycle.toml` and is
carried by tk-qf055w.
