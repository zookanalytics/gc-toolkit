Formula: mol-dog-shutdown-dance
Description: Shutdown dance — due process for one wedged session, run by the dog pool
against a claimed warrant bead. Port of the pre-rewrite mol-shutdown-dance,
scoped to warrant execution only (specs/2026-08-rewrite TODO-4 gap 4;
authority: docs/authority-map.md). Judgment only: the mechanical half of
each interrogation round (quota-park check, challenge nudge, bounded wait,
bounded peek) is ONE call to assets/scripts/dance-probe.sh, and this formula
judges its closed-field verdict.

KEY RENAME from the old warrants: bare target/reason/requester became
warrant.target / warrant.reason / warrant.requester ([metadata.warrant] in
lifecycle/lifecycle.toml) — bare `target` collides with the merge-identity
registry key of the same name. The ADDRESSING is unchanged from the old
detectors (it demonstrably worked in this city): city bead store, route
gc.routed_to={{binding_prefix}}dog, --label=warrant:

  gc bd create --type=task --title="Stuck: <agent>" --metadata '{"warrant.target":"<session>","warrant.reason":"<reason>","warrant.requester":"<who>","gc.routed_to":"{{binding_prefix}}dog"}' --label=warrant

The claimed warrant bead is the dance's identity: use $GC_BEAD_ID for
verification, evidence, and closure. Pardon-biased: one `alive` verdict ends
the dance. EVERY stop path either closes the warrant with
gc.outcome=pardoned|executed|refused or files escalate.sh
(--key wedged-<session>) — never both silence and an open claim.

Step-close discipline, same as the sibling formulas: when this runs as a
poured molecule each step closes its own bead via
assets/scripts/step-close.sh --step mol-dog-shutdown-dance.<id>, never by an
environment id. Warrants normally arrive as PLAIN routed beads with no step
beads at all; step-close then refuses (exit 2, nothing written), which is
the designed no-op — never improvise a close in its place.

Round timeouts: 60s / 120s / 240s (cumulative 7m), carried by dance-probe.sh
(env-tunable there). On crash, re-read the steps and resume from live state:
the warrant's status, notes, and the target's session state.

Variables:
  {{binding_prefix}}: Agent identity prefix, including trailing dot when bound. (default=)

Steps (6):
  ├── mol-dog-shutdown-dance.receive-warrant: Validate the warrant
  ├── mol-dog-shutdown-dance.interrogate-1: First interrogation (60s bound) [needs: mol-dog-shutdown-dance.receive-warrant]
  ├── mol-dog-shutdown-dance.interrogate-2: Second interrogation (120s bound) [needs: mol-dog-shutdown-dance.interrogate-1]
  ├── mol-dog-shutdown-dance.interrogate-3: Final interrogation (240s bound) [needs: mol-dog-shutdown-dance.interrogate-2]
  ├── mol-dog-shutdown-dance.execute: Execute the warrant — kill the session [needs: mol-dog-shutdown-dance.interrogate-3]
  └── mol-dog-shutdown-dance.epitaph: Record evidence, close the warrant, notify [needs: mol-dog-shutdown-dance.execute]
