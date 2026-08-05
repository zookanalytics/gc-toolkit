# Ecosystem fit — research findings (2026-08-05)

Two research passes run against the operator's questions after the phase-3
branch landed: how gc-next sits with the Gas City dashboard and upstream
direction, and how it composes with published mols, third-party skills,
and big-picture orchestration. Distilled here; the raw evidence citations
live in the session record. Three findings warrant beads; each is named.

## Upstream alignment verdict

| Signal | gc-next posture | Risk |
|---|---|---|
| `gc.routed_to` as sole persisted routing key (upstream #2779) | Rides — run_target compile-time-only; routed+unassigned stamps everywhere | Low |
| Continuation groups | Rides — the whole conversation layer bets on the shipping primitive, not advisory session_affinity | Low |
| Formula v2-for-orchestration / v1-for-patrols | Rides — matches "peers, choose by shape" exactly | Low |
| Builtin pack embedding | Rides — collision audit covers core/bd/dolt; graph-worker idiom; dispatcher dependency named | Low |
| `default_sling_formula` | Rides the mechanism (stage-4 repoint to `mol-nx-work`); stamps around its Lane-4 silence for internal plumbing | Medium — raw `bd update` stamps bypass sling-path guards upstream keeps improving; `gc sling --no-formula` is the sanctioned Lane-1 restorer, unused |
| `default_sling_targets` (#3670, multi-target random dispatch) | Ignored | Low — but a natural fit for the one-third-validation direction |
| gc-roles / run-operator importability | Adopts the idiom, refuses the pack; zero-imports is pack identity | **Medium-high** — seven hand-authored roles vs tk-h9pq5's own "revisit when roles multiply" tripwire |
| Attention Canvas (tk-eemvf / tk-sy3vj) | Carries the Go sidecar unchanged; the O2 turn rewire ships in a new bash copy of a script the Canvas plan's R5 retires | Medium — the rewire must be re-done in the service layer when the Canvas frontend (unbuilt) lands |

**Dashboard facts:** upstream ships `gc dashboard` (a Vite SPA, embedded,
served on :8080, talking to the supervisor :8372); the pack's sanctioned
augmentation seam is the `proxy_process` `/svc/` route the Go helm sidecar
already uses; the bash board is a PoC the Attention Canvas plan explicitly
kills ("the bash dies," R5). The bash `nx-helm.sh` rewire is therefore a
bridge, valid under operator ruling #7 (helm frozen), with the durable
home being sidecar write-verbs + the Canvas pick-a-row.

## Composing with published mols

Imports live at the **rig/city layer** (`[rigs.imports.<binding>]`,
`source`+`version`, cache-materialized, pinned) — gc-next's zero-imports
identity governs its *own* pack.toml (no roster inheritance) and does not
constrain what a rig imports beside it. A formula-only pack is the safe
shape (agent-shipping packs risk qualified-name load failures). The real
friction: published mols bake pool targets; anything aimed at another
roster (`gastown.polecat`) needs a var or a thin wrapper formula to hit
`gc-next.wright` — the same `binding_prefix` idiom gc-next's own formulas
use. A v2 import inherits the dispatcher requirement gc-next already
names.

## Third-party skills, and the review-skill case

Imported packs surface skills namespaced (`<pack>.<skill>`, visible via
`gc skill list --agent …`; collisions doctor-checked). Two sanctioned
paths for a favorite review skill:

- **(a) Doctrine** — one line in `nx-signoff-gate` ("run skill
  `<pack>.<name>` as part of the review"): rides into every reviewing
  session via the existing `append_fragments`; strengthens the signoff
  gate, creates no new gate. A rig can do it without editing the pack via
  `[[rigs.patches]]` fragment injection.
- **(b) A check-set member** — the architecturally sanctioned path for an
  *independent* condition of landing: add the name to `check_set`, ship
  the step that stamps `check.<name>=green@<sha>`; the merge skill is
  unchanged by design. Caveats: the pre-open subset is hardcoded `{codex}`
  (data-driven membership is recorded upstream intent, not built), so a
  second gate runs at merge time unless the pre-open resolver is
  extended; and the lander's cycle needs the dispatch line.

Path (b) is also the natural vehicle for the one-third-validation
direction (decisions.md #4): more validating legs are more check-set
members.

## Brief → epics → stories (the BMAD question)

Every downstream piece ships: the graph vocabulary (fan-out explores →
choose fan-in → implement, per the state machine), convoys as the
initiative container with integration branches and no-coordinator
graduation, epics as pure structure conversed about through turn-children,
`mol-nx-work` per story, the gating machine. **The one missing artifact is
the decomposition formula** — nothing here or upstream files a *tree*.
The shape is fully composable from shipped pieces: a `mol-nx-plan` that
reads the brief, writes the proposed epic/convoy/story structure as a
keepable artifact, files a confirmation *turn* (the operator's choose
fan-in), and on ratification `bd create`s the children with
parent-child/blocks edges and convoy targets. This is the intake open
area landing exactly where the outcome doc predicted; it is not blocked
by any gc-next decision.

## Beads to file at intake

1. **`mol-nx-plan`** — the decomposition formula above (closes the BMAD
   gap and most of the seeding-UX gap: thread-ops or a turn invokes it).
2. **Sidecar turn-verbs** — move the pick-a-row file-or-attach into
   `services/helm` (retiring the bash bridge on the Canvas plan's own
   schedule).
3. **gc-roles adoption review** — when upstream's roles pack covers a
   role gc-next hand-authors, re-argue the zero-imports stance for
   *role* packs specifically (the tk-h9pq5 Q5 tripwire, now on the
   record here).
