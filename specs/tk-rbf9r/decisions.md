---
name: Dynamic terminal attach target — spike evidence, guard design, and the city-repo half
description: What was measured about ttyd 1.7.7's ?arg= and --check-origin before the attach target was made selectable, why a rejected session name refuses instead of falling back to the mayor, and the exact setup/ patch this rig PR cannot land. Read before changing the terminal guard or enabling -O.
---

# Dynamic terminal attach target — decisions

Work record for `tk-rbf9r`. What is true *now* — the wiring, the guard's rules,
the widening — is in `services/helm/README.md` under *Terminal*. This file
records what was measured, what was decided against the bead's letter and why,
and the city-repo change that this rig's PR cannot carry.

The bead required a spike before committing to the approach, and required the
guard be proven by test rather than by inspection. Both are below.

## 1. The spike: `?arg=` works, and so does everything hostile

**The question** (bead, "Spike this FIRST"). `-a/--url-arg` is present on the
deployed binary, but the query-string wiring for `?arg=` on the `/ws` endpoint
in 1.7.7 was unverified. If it did not work as documented, the instruction was
to stop and hand back to `tk-mw9qz` rather than invent a substitute.

**Method.** A throwaway `ttyd 1.7.7` on a spare loopback port (`-b /terminal
-W -a <script>`), wrapping a script that prints its own argv; a Node WebSocket
client speaking the same handshake `web/src/terminal/protocol.ts` implements.
No live session, no city state, nothing attached.

**Result — it works, on the `/ws` request itself, not the page URL:**

| Query string on `/ws` | argv delivered to the command |
|---|---|
| *(none)* | `[]` |
| `?arg=hello-spike` | `[hello-spike]` |
| `?arg=one&arg=two` | `[one, two]` |
| `?arg=` | `[""]` — one EMPTY argument, not zero |
| `?arg=%2Dv` | `[-v]` |
| `?arg=a%20b` | `[a b]` |
| `?arg=..%2Fetc` | `[../etc]` |
| `?arg=x%3Bid` | `[x;id]` |
| `?arg=%24(id)` | `[$(id)]` |
| `?foo=bar` | `[]` — only `arg` is read |

Three of these rows changed the design rather than merely confirming it:

- **Every `arg` is appended.** So `?arg=<real>&arg=--flag` is a reachable shape,
  and "exactly one argument" is a rule the guard must enforce rather than an
  assumption it may make.
- **`?arg=` is one empty argument, not none.** The empty string is a client-
  reachable input and must mean "named nothing", or a URL the board can
  legitimately produce would take a different path than no URL at all.
- **A leading `-` arrives intact.** Without a guard, `gc` would read it as a
  flag rather than a session name.

## 2. Rejected names refuse; they do not fall back to the mayor

The bead said to "fail CLOSED to the mayor default, never pass an unvalidated
name through". The guard does the second absolutely. It deliberately does not
do the first for a name that is *present and invalid*, and this was measured
before deciding.

**Why the fallback is unsafe here.** `gc session attach` runs tmux. Anything the
guard prints before exec'ing it is wiped: on the wire, immediately after the
child's own output, tmux sends `ESC[?1049h` (alternate screen) and `ESC[2J`
(clear). Verified against a throwaway tmux session through the same ttyd
harness — the marker line was emitted and then erased by the repaint that
followed it in the same stream.

So a fallback would produce a **writable mayor terminal that the operator
believes is a different session**, with the explanation deleted before it could
be read, and the first keystroke going to the mayor. Refusing keeps the reason
on screen, because nothing repaints over it.

The distinction the guard actually draws:

- **No name** (no argument, or the empty argument ttyd sends for `?arg=`) →
  attach the default, exactly as the pre-`tk-rbf9r` invocation did. This path
  touches neither `jq` nor the session list, so the terminal still comes up on a
  city where those are unavailable.
- **A name that does not validate** → refuse, attach nothing, say why.

## 3. `/` is allowed, because the allowlist is the real control

The bead asked for `/` to be rejected outright. Taken literally that breaks the
feature: real rig-scoped sessions are named `gc-toolkit/gc-toolkit.witness`, so
a blanket ban would restrict the terminal to city-scoped sessions (mayor,
deacon, mechanik) — the ones the operator least needs to dive into.

What the ban was proxying for is traversal, and that is refused directly: `..`
anywhere, a leading `-`, a leading `.`, whitespace, every shell metacharacter,
more than one path segment, and anything over 128 characters. Then the rule that
actually decides — **exact membership in the live `gc session list`**, matched
against the three identifiers `gc session attach` itself accepts (id, alias,
session name). A name is never accepted on the strength of its spelling.

That ordering is why `gc-toolkit.ghost` is refused: it passes every character
rule and is still not a session.

## 4. `-O/--check-origin`: recommended, with one thing to verify on the box

The bead asked for an evaluation. Measured on the deployed 1.7.7 binary:

| `Origin` header | `-O` off | `-O` on |
|---|---|---|
| absent | 101 Switching Protocols | **refused** |
| `http://evil.test` | 101 | **refused** |
| matches `Host` | 101 | 101 |

ttyd logs `refuse to serve WS client from different origin due to the
--check-origin option`.

**This is worth having.** WebSockets are not subject to CORS: without `-O`, any
page an operator visits can open a socket to the tailnet host and — because
`-W` is set — drive a writable terminal. `-a` widens that from one session to
any live session, which is precisely what makes the origin check worth its
cost now.

**The one risk, and how to retire it.** ttyd compares `Origin` against `Host` as
*it* receives them, and in deployment those arrive through `tailscale serve`.
Whether tailscale forwards the original `Host` was not verifiable without
modifying the live mapping, which this bead put out of scope. So `-O` is
recommended but **not** included in the patch below as an unconditional change:
whoever applies the city change is already restarting the service, and one curl
against the tailnet origin settles it:

```bash
# With -O added to ExecStart and the service restarted:
curl -si -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Sec-WebSocket-Protocol: tty" -H "Origin: https://<tailnet-host>" \
  "https://<tailnet-host>/terminal/ws" | head -1     # want: 101
```

101 means keep it. Anything else means tailscale is not presenting the origin
ttyd expects, and `-O` must come back out until that is reconciled — the board's
terminal would otherwise stop attaching for everyone.

The dev-server half is already handled in this PR: `vite.config.ts` now rewrites
`Origin` on the `/terminal` upgrade to the proxy target, because `changeOrigin`
rewrites `Host` and leaves `Origin` alone, which is exactly the mismatch `-O`
refuses. It is inert while `-O` is off.

## 5. What this PR could not land: the city repo

The bead's file list spans two repositories. `services/helm/**` and the guard
are in this rig and are in this PR. `setup/steps/96-gc-terminal.sh` and
`setup/files/systemd/gc-terminal.service` are in the **city repo**
(`zookanalytics/loomington`), which has no refinery pipeline here, so a polecat
branch cannot carry them. **Until the patch below is applied, nothing in this
PR changes what the live terminal attaches** — the frontend sends `?arg=`, and
a ttyd without `-a` ignores it.

Tracked as `tk-xlup8`; the exact patch is `city-repo.patch` beside this file. It installs the guard rather than pointing at the rig checkout, so the
dependency is resolved once at setup time with a loud failure, instead of
per-connection with a broken terminal (`rigs/<rig>/` lags `main`).

**Apply it only after this PR lands and `rigs/gc-toolkit` is updated**, or the
install step will not find the guard to install:

```bash
cd "$GC_CITY"                                  # the city repo, not this rig
git apply --check rigs/gc-toolkit/specs/tk-rbf9r/city-repo.patch   # verified clean 2026-08-14
git apply         rigs/gc-toolkit/specs/tk-rbf9r/city-repo.patch
bash setup/steps/96-gc-terminal.sh             # installs the guard, restarts the unit
```

The step restarts `gc-terminal.service`, which only affects panels open during
the bounce. After it, `…/terminal/` with no `?session=` must still come up on
the mayor — that is the regression to watch, because it is the path every
existing consumer of this terminal takes.
