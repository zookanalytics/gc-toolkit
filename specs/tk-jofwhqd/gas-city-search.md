---
name: Gas City search for a rig named in the conversation form's subject
description: The search the arch check asks for before gc-helm.sh conversations gains a prefix on each rig it lists and a rig_suspended key on the subject it reads, which the conversation form uses to take a rig's name or prefix typed as its subject and to save in a suspended rig without starting a sitting. What Gas City ships for naming a rig by its prefix and for telling whether a sitting can start in a rig, read at a named upstream commit, and why the form reads both through the verb it already calls. Read it when checking whether the form's rig matching or its suspension check can move onto a Gas City primitive.
---

# Gas City search for a rig named in the conversation form's subject

The conversation form takes a rig's whole name or prefix typed as its subject,
which starts a new topic in that rig, and in a suspended rig it saves the
question with attaching off and starts no sitting. The change adds this surface
to `gc-helm.sh conversations`, the verb the form reads:

- `prefix` on each rig that `conversations --json` lists, so the form can match
  a rig typed by its prefix.
- `rig_suspended` on `conversations <ref> --json`, which says the subject's rig
  is suspended. The verb gave that case as its `refusal`, and it refuses
  nothing now: the form files the question there and starts no sitting.

Gas City read at upstream main `e349bc2703` (gastownhall/gascity, fetched
2026-11-10).

## What was searched, and what each leaves

**A rig's prefix.** `gc rig list --json` gives each rig its `prefix` beside its
`name`, `hq` and `suspended` (`RigListItem` in `cmd/gc/cmd_rig.go`). The pack
reads that listing through `rig-map.sh`, and gc-helm.sh's `RIGS` rows already
carry the prefix (`RIG_PROJECTION_JQ` in `city-liveness.sh`). The new key passes
that field through as Gas City gives it. The form does not run `gc rig list`
itself, because it reads and writes only through gc-helm.sh's verbs, and
`conversations --json` already reads the listing for the rigs it lists.

**Naming a rig by its name or prefix.** Gas City resolves a rig by name or by
path for `--rig` (`resolveRigToContext` in `cmd/gc/main.go`). It matches a rig
by prefix, ignoring case, only inside `gc sling` (`findRigByPrefix` in
`cmd/gc/cmd_sling.go`, which calls `FindRigByPrefix` in
`internal/sling/sling.go`). Neither is a command whose answer a caller reads,
and neither can tell the form, while the operator types, whether the text names
a rig or a bead to look up. So the form matches the text against the listed
rigs' names and prefixes, ignoring case as `FindRigByPrefix` does, and text that
two rigs carry names neither.

**Whether a sitting can start in a suspended rig.** None can. The allocator
honors an explicit wake only for an agent that is not suspended
(`honorsExplicitWake` in `cmd/gc/allocator_decide.go`), and `agentSuspended`
there counts an agent in a suspended rig (`agentInSuspendedRig` in
`cmd/gc/build_desired_state.go`). `gc rig list --json` gives the rig's flag as
`suspended`, which gc-helm.sh reads through `rig_suspended` in
`city-liveness.sh`, and `sitting_refusal` already refused on it. The new key
reports that same reading for the subject's rig, apart from the refusal, so the
form can file the question there and start nothing.

`gc agent list --json` gives each agent's effective suspension as `suspended`
(`isAgentEffectivelySuspendedWith` in `cmd/gc/cmd_suspend.go`), which counts a
suspended city, agent or rig. Reading it would add a second Gas City listing to
each lookup, of the converse agent for each model, to answer the rig's part of
the question that the listing the verb already reads answers. engage's refusal
reads the rig's flag, and the form reads it the same way, so the two cannot
disagree about a rig.
