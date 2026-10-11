---
name: Engage ordering — spawn then bind, with the alias as the reservation (tk-u2o7zu)
description: The two orders gc-helm engage could take between spawning a converse sitting and binding its visit, the failure modes of each, and why engage keeps spawn-then-bind. Read before changing how engage reserves or binds a visit.
---

# Engage ordering: spawn then bind, with the alias as the reservation

Bead: `tk-u2o7zu`, a review item left out of the cutover (PR #684). Deliverable:
this record, the losing-engage path in `cmd_engage`
(`assets/scripts/gc-helm.sh`), and the race tests in
`assets/scripts/gc-helm-engage.test.sh`.

## Decision

`gc-helm engage` keeps its order: it spawns the sitting, then binds the visit
with a conditional write. The spawn already reserves the visit before anything
is bound, because gascity reserves a session alias atomically and engage uses
the visit id as the alias. The defect was in the engage that loses: it guessed
at state instead of reading it, and its message could tell the operator to
close the sitting that had won. That engage now reads the visit and points at
whatever holds it.

## What the spawn already reserves

These facts were read in gascity at 92344d46d, the commit the city's `gc`
binary is built from, and checked against live sittings.

- `gc session new` checks that an alias is free and creates the session that
  holds it inside one city-wide file lock on the alias. The controller path and
  the direct-start path both do this (`cmdSessionNew` in
  `cmd/gc/cmd_session.go`; `WithCitySessionIdentifierLocks` and
  `ensureSessionAliasAvailable` in `internal/session/names.go`).
- An alias stays taken while a session bead that carries it has not closed. A
  refused spawn creates nothing, exits 1, and prints
  `gc session new: session alias already exists: "<alias>" already belongs to <session-id>`
  on stderr.
- engage always spawns under the visit id. It retries under `v-<visit-id>` only
  when gascity rejects the bare id as an invalid alias, and that depends on the
  id alone, so every engage of one visit asks for the same alias.
- gascity stores a converse sitting's alias qualified as
  `<rig>/<pack>.<visit-id>`. A live sitting shows
  `alias: gc-toolkit/gc-toolkit.tk-bhf8gn1` in `gc session list` and carries the
  same value in `GC_ALIAS`. `converse-reap.sh` already reads the visit id back
  as the alias's final dot-segment.

So of two engages of one visit, exactly one creates a sitting, and the other is
refused before it spawns anything. That is the pre-spawn reservation the review
asked for. A real session bead holds it, `gc session list` shows that bead, and
closing the session releases the reservation.

## Ordering A: spawn, then bind (kept)

1. The guards read the visit. It must be open and unblocked, and unassigned or
   bound to a sitting that is provably gone, which engage reclaims.
2. `gc session new --alias <visit-id>` creates the sitting and reserves the
   alias.
3. `gc bd update --if-assignee "" --if-status open --assignee <session-name>`
   binds the visit.
4. A read-back confirms the binding.

| Case | What happens |
|---|---|
| Two engages of one visit run at once | One spawns and binds. The other is refused at step 2 and spawns nothing. It waits for the visit to be bound, then points the operator at the sitting that holds it. |
| An engage stops between steps 2 and 3, because it was killed or its terminal closed | A sitting holds the alias and nothing else, and the visit stays parked. The next engage is refused at step 2. If the visit stays unbound for the whole wait, that engage names the sitting and says to close it, provided no other engage of the visit is still running. `converse-reap.sh` does not reap this sitting, because it only ends sittings whose visit has closed. |
| A writer other than engage closes or assigns the visit during the spawn | Step 3 writes nothing and exits 13. engage closes the sitting it spawned, then points at the visit's holder or reports its new status. This is the only case left in which a sitting is spawned and then closed. Another engage of the visit cannot cause it, because the alias refused that engage at step 2. |
| Step 3 fails for another reason, or the read-back disagrees | engage closes the sitting it spawned, then says to re-run or to attach to the holder. |

## Ordering B: reserve the visit, spawn, then finalize (not taken)

1. The guards read the visit.
2. `gc bd update --if-assignee "" --if-status open --assignee <placeholder>`
   reserves the visit.
3. `gc session new --alias <visit-id>` spawns the sitting.
4. `gc bd update --if-assignee <placeholder> --assignee <session-name>` binds
   the visit to it.

B's losing engage fails at step 2 before spawning, with an accurate message. A's
losing engage now does the same at its step 2. B's remaining gain over A is the
third row of A's table, a writer other than engage changing the visit during
the spawn, and B covers only part of it: a visit closed during the spawn still
fails step 4, and the sitting is closed anyway.

What B costs:

- Until the spawn returns, the placeholder is an assignee that no session
  carries. `sitting_is_gone` in `gc-helm.sh` reads exactly that as a gone
  sitting, so a second engage's reclaim path would clear a live reservation in
  the middle of a spawn. Making the reservation safe needs a liveness proof,
  such as a lease or a TTL, that every reader of the assignee would have to
  learn.
- The helm board reads any assigned open visit as engaged (`engagedVisit` in
  `services/helm/internal/board/derive.go`). An engage that stops after step 2
  leaves the visit off the parked backlog with nothing bound to it, until a
  reclaim decides the reservation is dead.
- An engage that stops between steps 3 and 4 leaves that stale reservation and
  a sitting holding the alias. That is A's leftover-sitting case with a stale
  reservation added.
- Using the intended alias as the placeholder does not help. The sitting's hook
  claim adopts a ready bead only when its assignee is one of the sitting's own
  identities (`claimFirstReadyHookAssignment` in gascity
  `cmd/gc/cmd_hook_claim.go`), and those carry the qualified alias, not the bare
  visit id. Predicting the qualified form in shell would copy gascity's naming
  rules into the pack. engage avoids that by reading the identity from
  `gc session new --json`.

## The losing engage

When `gc session new` is refused with the alias sentinel, `engage_alias_held`
reads the visit once a second for up to `GC_HELM_ENGAGE_BIND_WAIT` seconds
(default 20). A concurrent winner binds within one store write of its spawn
returning, so the wait ends as soon as that binding appears.

- If the visit gained an assignee, the engage reports it and prints
  `gc session attach <assignee>`.
- If the visit is no longer open, the engage reports its status.
- If the visit stayed open and unassigned through the wait, the engage finds the
  open session whose alias has the requested alias as its final segment. It
  names that session as left by an engage that stopped before binding, and says
  to close it if no other engage of the visit is still running. When no open
  session holds the alias any more, it says to re-run. When the session list
  cannot be read, it names no holder and says to re-run once the list answers.
- If the visit could not be read, the engage says so and names the holder
  without telling the operator to close it.

Every one of these paths exits 4, spawns nothing, writes nothing to the visit,
and closes nothing.

## Tests

`assets/scripts/gc-helm-engage.test.sh` stubs gascity's refusal with its real
text, including the alias in its qualified form.

- `ALIAS-BOUND` lands the winner's bind on the losing engage's second read of
  the visit. An engage that read the visit only once would name the winner as
  left over and say to close it.
- `ALIAS-LEFTOVER`, `ALIAS-GONE`, `ALIAS-LISTFAIL`, `ALIAS-CLOSED` and
  `ALIAS-UNREAD` cover the other ways the wait can end. Their session list also holds another visit's
  sitting whose alias shares the prefix, and a closed sitting that once held the
  alias. Neither is ever named as the holder.
- `RACE-CONCURRENT` runs two engages of one visit at once. The stub holds each
  spawn at a barrier until both have arrived, so both have passed the pre-spawn
  guards. It then reserves the alias under a lock and runs every bind as a
  compare-and-swap under a lock. Exactly one sitting spawns and binds, the other
  engage exits 4 pointing at it, and no sitting is closed.
- `TAKEN` and `TAKEN-CLOSED` cover the third row of A's table, the one path that
  still spawns a sitting and then closes it.

The earlier `RACE` case modelled a second engage that spawned and then lost the
bind, which gascity refuses at the spawn. That case is now `TAKEN`, with a
writer other than engage taking the visit.
