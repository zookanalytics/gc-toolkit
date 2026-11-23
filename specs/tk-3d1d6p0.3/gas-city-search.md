---
name: Gas City search — accepting a question's one recommendation
description: The search for the bd and Gas City primitives behind the surface the design for tk-3d1d6p0.3 adds (the gc.recommendation record on a human gate, gctk gate recommend, gctk gate accept and the board's POST /helm/accept), read at bd v1.3.4 and Gas City upstream main cb9a2621ae. Read it to check what the design composes and why each new element exists.
---

# Gas City search: accepting a question's one recommendation

The design ([design.md](design.md)) adds four elements:

- `gc.recommendation`, a metadata key on a human gate;
- `gctk gate recommend`, which writes it;
- `gctk gate accept`, which moves from `gctk reaction accept`;
- `POST /helm/accept`, the board's route to it.

It retires `gctk reaction accept`, the bead keys `gc.recommended_formula` and
`gc.recommended_formula_dispatched`, and
`converse-invalidate-recommendation.sh`. Each section below names a need, the
primitives searched for it, and what they leave. bd is cited by symbol at
v1.3.4, the version the city runs, and Gas City by symbol at upstream main
cb9a2621ae.

## 1. Recording the operator's yes

**Searched.**

- bd's `gate resolve` (`gateResolveCmd`, `cmd/bd/gate.go`) closes a gate with
  `--reason` as its close reason, and its help says it "is equivalent to
  'bd close <gate-id>'". It calls the store's `CloseIssue` with the reason.
- Gas City's `gc bd` passes `gate resolve` through as an allowed write, "closes
  a gate" (`bd_split_allowlist.go`, `cmd/gc`).
- Gas City's supervisor API has no route of its own for a gate. Its bead close
  route, `POST /v0/city/{cityName}/bead/{id}/close`
  (`supervisor_city_routes.go`; handler `humaHandleBeadClose` in
  `huma_handlers_beads.go`, `internal/api`), stamps the reason it is given and
  closes the bead through `BdStore.Close` (`internal/beads/bdstore.go`), which
  forwards the reason to bd's close. It refuses a row Gas City owns, such as a
  session or a message (`genericRefused`, `internal/api`), and a task that
  fails the work-record close contract (`Gated`, `internal/workrecord`). A
  human gate, whose type is `gate`, is neither.

**Covers.** The record of the yes: the gate's resolve reason, written by bd's
gate resolve. Accept composes it unchanged.

**Leaves.** None of them knows which answer is the question's recommendation,
refuses a yes to a recommendation that changed after the operator read it, or
runs what the yes needs. So `gctk gate accept` stays a verb, under the
defense today's `gctk reaction accept` row gives in docs/gctk-architecture.md.

## 2. Recording one recommendation on a question

**Searched.**

- bd's gate fields (`Issue`, `internal/types/types.go`): `await_type`,
  `await_id`, `timeout`, and `waiters`, the mail addresses told when the gate
  clears.
- bd's free-text fields on any issue: description, design,
  `acceptance_criteria` and notes. An issue's `payload` belongs to its event
  fields.
- Gas City's durable waits (`GET /v0/city/{cityName}/waits` and
  `/wait/{id}`), which its route table files under "Durable session waits
  (session coordination-class)": what a session waits on, not a question a
  bead puts to a person.
- `POST /v0/city/{cityName}/session/{id}/respond`, "Respond to a pending
  interaction", which answers a session's pending prompt, not a bead.

**Leaves.** No field or route holds "this question's one recommended answer,
and the act a yes to it runs". bd's text fields hold prose, and reading the
recommendation out of prose is what the design declines (decision 1). So the
asker writes the record as gate metadata, `gc.recommendation`, and gctk's
ledger declares the key, with gctk its only writer. `gctk gate recommend`
stays a verb because the native metadata write takes any value. The verb finds
or files the gate under the asker's situation key, checks the act can run on
the bead, and writes the record in one write.

## 3. Starting work on one answer and not another

**Searched.**

- bd's `blocks` edge releases the bead it holds when the gate closes, whatever
  the answer.
- bd's `conditional-blocks` edge ("B runs only if A fails",
  `DepConditionalBlocks`) releases only when the blocker's close reason
  contains one of `FailureCloseKeywords`, such as "rejected", "abandoned" or
  "canceled" (`IsFailureClose`, `internal/types/types.go`). It keys on words in
  the answer, so the wording of a yes could release the wrong work, and it
  answers to a failure, the opposite of a yes.
- bd's `approved-by` and `validates` edges are associations: they hold nothing
  (`AffectsReadyWork`, `internal/types/types.go`).
- `gc sling` refuses a second launch of a formula at a bead only while the
  first root is live, and no flag checks an earlier root by a caller's key
  ([the search for today's Accept](../tk-1tfzr71.226/gas-city-search.md#accept-gc-slings-launch-lock)).
- Gas City's dispatch holds, `hold:mayor` and `hold:external`
  (`DispatchHoldLabels`, `internal/beadmeta/hold_labels.go`), keep a bead out
  of every path that serves it as work, `gc hook --claim` among them, until
  the label goes. A hold answers to its label, not to the gate's answer, so it
  starts no work on one answer either. What it gives is a stop that outlives
  the process that wrote it, which no lock does.

**Leaves.** Nothing starts work, closes a bead or retires a PR on one answer of
a gate and not on another. So `gctk gate accept` runs the act itself, and only
once the gate took its own answer. It holds the lock today's Accept holds
([warrants.md](../../docs/warrants.md#accepts-lock)), and across the answer the
pack's locks that the answer's releases act under
([design.md](design.md), section 3). A pool's claim takes none of those locks,
and a lock ends with the run that holds it, so before it answers Accept also
puts the dispatch hold on the bead, and for `retire` the PR's merge hold, which
the landing order already honors. It lifts each once its act is done or
another answer stands. It runs each act through steps the pack already has:
`gc sling` with today's token for `sling`, gctk's disarm and takeaway with
`bead-rehome.sh` for `stand-down`, and `pr-dispose.sh` whole, after Accept's
own answer, for `retire`. `proceed` composes the wait the bead already has, a
`blocks` edge with what it releases, and adds nothing.

## 4. The board's door for the write

**Searched.** The supervisor API serves the board's reads, and its bead close
route of section 1 could answer a question whose act is `proceed`.

**Leaves.** The route cannot run the other three acts or check the record. So
the board's Accept calls the one verb every caller uses, through a write route
beside `/helm/open` and `/helm/engage`, which run their verbs the same way.
The route is the board's own code, in its service.
