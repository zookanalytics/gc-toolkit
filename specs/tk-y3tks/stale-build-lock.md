---
name: Decision record — the gc-helm-svc build lock identifies a request, not a process
description: Why gc-helm-svc.sh's detached-build lock had to be keyed on a per-request token rather than on a live pid, what a pid alone cannot distinguish (a reused pid, a foreign builder, a verdict already published), the rule the launcher now follows, and the mutation evidence behind each STALELOCK case. Read alongside the tk-y3tks review trail when changing the attach/rebuild arms.
---

# The build lock identifies a request, not a process

Bead: tk-kbb8s (rework of tk-y3tks) · review: tk-e0l83 · branch: polecat/tk-y3tks

## The defect

`gc-helm-svc.sh` detaches its build so a start killed by the supervisor's
readiness window does not take the build with it, and the next start **attaches**
to the running build instead of starting a second one. Attachment was decided by
one fact: `.build.pid` names a live process.

A pid is not an identity. The lock is *designed* to outlive the start that wrote
it, and it is only ever released by a start that took the build branch — so a
normal successful build routinely leaves it behind: the parent is killed by
readiness, the builder later writes `.build.result=ok`, and the next no-build
start skips the whole block and never clears the dead lock. Once that pid is
recycled, a later start with newer sources reads a live pid, concludes a build is
already running, does **not** start the rebuild it had just decided it needed,
falls through to the leftover `ok`, logs `rebuilt`, and execs the stale binary.

That is the silent stale-artifact failure tk-y3tks exists to close, reached
through the guard meant to close it. Reproduced by the reviewer with a live
`sleep` in `.build.pid`, `.build.result=ok`, a touched source and
`GC_HELM_BUILD_WAIT=0`: the old binary was served and the toolchain ran zero
times.

## Why a token alone is not the fix

The obvious remedy — stamp each build with a token, match it before consuming
the verdict — does **not** close this on its own. In the failing scenario the
lock and the leftover verdict come from the *same* build, so their tokens match.
Matching tokens proves the verdict answers the locked build; it says nothing
about whether that build is still running.

The discriminator is the pair. A verdict for the locked token that is *already
on disk when we first look* proves the locked build has **finished** — so the
lock is residue and the live pid holding it is an impostor. A build genuinely in
flight has a tokened lock and **no verdict yet**.

## The rule

Attach only to a lock that is (1) alive, (2) tokened, and (3) has not yet
published a verdict for its token. Believe a verdict only when its token is the
one this start is waiting on. Clear a lock whose builder is dead on sight —
including on no-build starts, which is the path that never used to look, and so
the path that let a dead lock live long enough to collide with a recycled pid.

A pre-token (pid-only) lock is refused rather than trusted: nothing distinguishes
its verdict from an older one. That costs at most one redundant build on the
first start after upgrade, and it is the only safe reading.

## Evidence

`assets/scripts/gc-helm-svc.test.sh` — 60 passed, 0 failed (was 54).

Against the pre-fix script (`f53e9349`) in a parallel tree, `(STALELOCK-PIDONLY)`
fails with the reviewer's exact symptom — `build_count=0` and `cached-binary
ran:` — and `(STALELOCK-FOREIGN)` and `(STALELOCK-SWEEP)` fail too.

`(STALELOCK)` passes there **vacuously**: it writes a tokened lock, which the old
script cannot parse, so it ignores the lock and rebuilds for the wrong reason. It
was therefore mutation-tested against the fixed script instead — disabling the
"verdict already published ⇒ stale" arm makes it the only failing case, with the
same 0-builds/cached-binary symptom. Recorded because a case that is green in
both directions proves nothing until you know which mutation it is holding.

`(CONCURRENT)` was rewritten: its fixture wrote the verdict *before* the run,
which describes a build that already finished — the stale shape, not a
concurrent one. It now models a build genuinely in flight.

Shellcheck was run this round (`podman`, `koalaman/shellcheck:stable`) — the
reviewer could not, it is absent from the review worktree: clean at `-S warning`,
and byte-identical to HEAD at info level. `go vet ./...` passes; the diff touches
no Go.
