---
name: U9 terminal embed — decisions, evidence, and rejected alternatives
description: What was measured about ttyd's deployment before the terminal was embedded, why the reachability check tests content type rather than status, and the live proof that closing a tile detaches instead of killing. Read before changing how the board attaches to ttyd.
---

# U9 terminal embed — decisions

Work record for `tk-eemvf.4` (U9 of the Attention Canvas plan,
`specs/tk-eemvf/2026-06-30-001-feat-attention-canvas-plan.md`). What is true
*now* — the deployment shape, the reachability check, the detach invariant — is
in `services/helm/README.md` under *Terminal*. This file records what was
measured, what was decided, and what was rejected.

The bead named two constraints and two test scenarios. Both constraints were
open questions the plan flagged as untested; both are now answered with
evidence, below.

## 1. Origin reachability: confirmed, and the obvious probe is a false positive

**The question** (bead constraint 1). The plan flagged that the dashboard
tailscale config routes only `/`, `/v0` and `/health`, while ttyd is a separate
`tailscale serve` mapping — so it was not known whether the terminal is
reachable on the SPA's origin. "Verify it, do not assume it."

**Answer: yes, on the published origin.** The live mappings:

```
$ tailscale serve status
https://<host> (tailnet only)
|-- /         proxy http://127.0.0.1:8372
|-- /v0       proxy http://127.0.0.1:8372/v0
|-- /health   proxy http://127.0.0.1:8372/health
|-- /terminal proxy http://127.0.0.1:7681/terminal
```

The board lives under `/v0/city/<city>/svc/helm/` and ttyd under `/terminal/`,
both on `https://<host>` — one origin. Verified directly:

```
$ curl -sI https://<host>/terminal/token
HTTP/2 200
content-type: application/json;charset=utf-8      # real ttyd

$ curl -s https://<host>/v0/city/<city>/svc/helm/
{"generated_at":"2026-08-11T15:51:13Z","total":20,...}   # the board
```

Two consequences worth stating, because both could have gone the other way:

- **No CSP change was needed.** The app ships `connect-src 'self'`, and CSP's
  `'self'` admits a `wss:` socket to the same host and port from an `https:`
  document. Same-origin is what makes the strict policy survivable; a
  cross-origin ttyd would have forced a policy widening, which is a security
  decision this leg should not be making.
- **No CORS is involved**, for the same reason.

**But the naive probe lies.** The supervisor serves a SPA at its root whose
catch-all answers *every* unmatched path with `200 text/html`:

```
$ curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8372/terminal
200                                     # looks reachable
$ curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8372/nonsense-xyz-12345
200                                     # ...so does anything else
$ curl -sI http://127.0.0.1:8372/terminal/token | grep content-type
content-type: text/html; charset=utf-8  # the dashboard shell, not ttyd
```

So on the supervisor's own origin — where ttyd is *not* routed — a status-code
probe reports a healthy terminal. Had the check been written the obvious way it
would have passed everywhere and told us nothing.

**Decision.** `probeTerminal()` requires `application/json` from
`<base>/token`, not merely a 2xx, and runs before any socket is opened. A
misrouted origin yields a sentence naming the cause instead of a socket that
hangs and dies. `endpoint.test.ts` pins both directions, including the exact
`{"token": ""}` the deployed ttyd returns.

**Rejected: probing by status code.** Cheaper, and wrong on the one origin an
operator is most likely to try first (loopback).

**Rejected: a build-time or server-injected terminal URL.** The bundle is
committed and served by `go:embed`, so a build-time constant cannot be changed
without a rebuild, and having helm-svc inject one would make the board's server
responsible for ttyd's deployment — a coupling U10 (deploy/tailscale) owns, not
this leg. The path is an origin-absolute default with a `?terminal=` override
restricted to same-origin paths; a full URL or a protocol-relative host is
refused, since honouring one would turn a config knob into a way to aim an
operator's terminal session at another host.

## 2. Close means detach, not kill — verified against real ttyd

**The question** (bead test scenarios). "CLOSE MEANS DETACH, NOT KILL. Killing a
live agent session by closing a tile is the destructive failure mode for this
leg; test it explicitly."

**Why it is safe.** ttyd spawns one `gc session attach <session>` process per
connected client, and that process is a *tmux client* of a session that already
exists and outlives every client. Closing the socket hangs up that one client;
tmux detaches it and the session carries on. What *would* kill the session is
writing to the PTY on the way out — an `exit`, a `^C`, a `^D`, a
`tmux kill-session` — which is indistinguishable from the operator typing it.

**Decision.** The invariant is narrow and absolute: **teardown never writes to
the socket.** `detach()` closes with code 1000 and does nothing else, and
`send()`/`resize()` refuse to write once teardown has begun, so a keystroke
racing the unmount cannot slip through. Four tests in `session.test.ts` cover
it, including the race.

**Live proof.** A private ttyd on a spare port wrapping a throwaway tmux session
— the same invocation shape as the city's, and never the real mayor session:

```
== attach, run a command, close cleanly ==
  -> handshake sent
  -> INPUT frame sent (touch during.txt)
  -> closed with code 1000; frames written during teardown: 0
  -> received 2553 bytes of terminal output while attached

== after close: did the session survive? ==
  PASS  tmux session still exists (yes)
  PASS  session shell process still running (yes)
  PASS  command sent while attached executed (yes)
  PASS  session still executes commands after detach (yes)
  PASS  no clients remain attached (we detached, not lingered)
```

The last two assertions are the ones that matter. "Session still exists" alone
would also be true of a wedged session, so the probe sends a command *after*
detaching and confirms it runs; and it confirms no client was left attached, so
the pass is not just a socket that failed to close.

**Rejected: committing that probe as a test.** It needs ttyd, tmux and a live
city; this repo has no CI and no such fixtures. The system property it proves
belongs to the deployment, not to this code — the code's half of it is the
no-write invariant, which is unit-tested. The evidence is recorded here instead.

**Rejected: testing against the city's live ttyd on 7681.** It is wired to the
mayor's real session. Attaching would have resized a working agent's terminal,
and a mistake would have ended it — exactly the failure being tested for.

## 3. A size floor, because the PTY is shared

tmux sizes a window to fit its clients. A tile reporting its own small pixel
size would therefore reflow the terminal of a human attached to the same
session. The client clamps every reported size to 80x24, so an embedded
terminal can be smaller than its content (it scrolls) but can never shrink
somebody else's session below a standard terminal.

## 4. Scope held: one terminal, no canvas

**Single session** (bead constraint 2). The ttyd invocation bakes in one target
(`gc session attach <session>`), so per-tile terminals would need a ttyd or
wiring change. The plan defers that decision to the design handoff, which has
not happened. This leg attaches the existing single target and the app renders
one terminal; the follow-up is filed separately rather than absorbed, as
`tk-mw9qz` (child of the epic, unrouted — it is design-gated, not ready work).

**No visual design.** Like U5, this is structure only: a bordered panel with two
states and enough CSS to tell them apart. The spatial placement a terminal tile
eventually gets is U6, which is design-gated and deliberately not filed.

**No reconnect loop.** A dropped socket rests in `detached` and waits for the
operator. Reattaching re-runs `gc session attach`, which *resumes a suspended
session* — a side effect that should follow a deliberate act, not a timer.

## 5. Protocol source

ttyd's wire protocol is not specified or versioned anywhere, so the constants in
`protocol.ts` were read out of the running server's own bundled client (ttyd
1.7.7) rather than from documentation: the command bytes, the bare-JSON opening
frame, the `tty` subprotocol, and the `<base>/ws` and `<base>/token` paths. The
comment in that file records the shape so the next reader does not have to
re-derive it.
