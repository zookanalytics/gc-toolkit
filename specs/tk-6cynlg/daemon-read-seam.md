---
name: gctk daemon read seam
description: Why and how gctk's bead-read seam (gcbd.Show) reads through the supervisor API's pooled connection with a gc-bd fallback, the read-back carve-out, and the reusable daemon discovery the Go migration adopts.
---

# gctk reads through the supervisor API

## Why

Per-call `gc bd` reads drive the live Dolt CPU storm (finding tk-sezabk): every
invocation forks and opens a fresh Dolt connection. The supervisor daemon
already holds a pooled, process-lifetime connection and answers bead reads
in-process over HTTP. Moving gctk's reads onto that connection removes both the
fork and the new connection on the healthy path.

Operator ruling (converse tk-t6ytvz): prove the daemon-read path by converting
one valuable location with a reusable discovery, no beads-library link, no
throwaway shell swap. This converts the gctk read seam `gcbd.Client.Show` and
leaves the ~295 shell `gc bd` sites and the write path for later, per that
ruling.

## What reads through the daemon, and what does not

`Show` prefers the supervisor API: `GET {base}/v0/city/{city}/bead/{id}`, which
returns one `beads.Bead` object. Only a 200 that decodes to a bead with an id is
trusted; a non-200 (including a 404 miss), a transport failure, or an
undecodable body falls through to `gc bd show`. The daemon can therefore only
make a read faster, never change its answer — `gc bd` remains the authority on
whether a bead exists.

A write's read-back verification does **not** use the daemon. `lifecycle`
re-reads a bead after its atomic `gc bd update` to confirm every written field
landed, and that read must observe the write it just made and must carry the
bead's appended notes. The daemon fails both:

- **Notes.** The supervisor's `beads.Bead` has no `notes` field; the payload
  omits notes entirely. Verified live: `tk-vbeklo` carries notes via
  `gc bd show`, and the daemon's response for it has no `notes` key.
- **Freshness.** The daemon serves from a cache that lags a fresh write.
  Verified live: a metadata key written via `gc bd update` was absent from the
  daemon's response for the same bead read immediately after.

So read-backs call `ShowDirect`, which always forks `gc bd` — authoritative,
uncached, notes-carrying. Cold reads (the state a decision is made from) call
`Show`. Only the two read-backs in `lifecycle.go` changed callers; every cold
read keeps calling `Show` with its signature unchanged.

## Discovery (the keystone the migration reuses)

`internal/daemon` resolves the base URL from config, not from any runtime
advertisement — the supervisor writes no port or URL file. `BaseURL` reads
`[supervisor] bind`/`port` from `$GC_HOME/supervisor.toml`, each defaulting to
the supervisor's own `127.0.0.1:8372`, and normalizes a wildcard bind to
loopback. `City` resolves the `{city}` path segment from the city's
`[workspace].name`, else the basename of `$GC_CITY_PATH` — the same
workspace-name-else-basename rule the supervisor's own effective-name
resolution uses. A wrong city name makes the daemon answer 404, which falls
back, so a bad guess costs a fork, never a wrong read. The resolver is stdlib
only: `gctk`'s `go.mod` gains no dependency.

`GC_NO_API` is the escape hatch, read the same way `gc beads` reads it:
`1`/`true`/`yes` turn the daemon read path off and send every read straight to
`gc bd`.

## Proof

Built binary, live city, daemon up:

```
$ GC_DEBUG=1 gctk lifecycle state tk-6cynlg
gctk gcbd: show tk-6cynlg route=api
unanchored
```

`route=api` is the read answered from the pooled connection with no fork. The
unit test `TestShowReadsViaDaemonWithoutForkingBd` asserts the same with a fake
server and a fork marker the subprocess would have written: the marker is
absent, so the healthy read never forked `gc bd`.

Fallback preserved — discovery pointed at a dead port:

```
$ GC_DEBUG=1 gctk lifecycle state tk-6cynlg   # supervisor.toml port unreachable
gctk gcbd: show tk-6cynlg route=fallback reason=transport
```

and `GC_NO_API=1` returns the same `unanchored` the daemon did, the parity the
fallback preserves. `TestShowFallsBackToBdWhenDaemonUnavailable` covers the four
fall-through modes (non-200, transport failure, undecodable body, a 200 with no
id).

## Tests off the live supervisor

The daemon path is exercised by an injectable `httptest` fake in
`internal/gcbd`, not a PATH stub. The subprocess-path suites — the `gcbd` exec
and List tests, the `cli` lifecycle and pr-status tests, and the shell
`lifecycle.test.sh` acceptance — set `GC_NO_API=1` so a stubbed `gc`, not the
live supervisor the ambient session points at, answers. Without it a synthetic
test id could collide with a real bead and read live state.
