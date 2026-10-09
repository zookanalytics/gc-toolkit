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
registry key of the same name. Detectors file through the shared
assets/scripts/file-warrant.sh, which resolves the wedged owner to a live
session id — warrant.target must be one, since this dance's probe rejects any
other value — routes gc.routed_to={{binding_prefix}}dog, labels it warrant, and
dedups on the session id:

  file-warrant.sh --owner <owner> --role <agent> --reason <reason> --requester <who> --dog <resolved-dog-route>

The claimed warrant bead is the dance's identity, and `gc hook current
--id-only` is what names it — it reads back the id this session claimed. A
pool session never receives $GC_BEAD_ID, so a close written against that
variable writes nothing and still exits 0, leaving the warrant open and
silent. Every step that touches the warrant re-derives the id in its own
shell. Pardon-biased: one `alive` verdict ends the dance. EVERY stop path
either closes the warrant with gc.outcome=pardoned|executed|refused or files
escalate.sh (--key wedged-<session>) — never both silence and an open claim.

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
  {{binding_prefix}}: Agent identity prefix with trailing dot. Non-empty default on purpose: it renders the dog route (this prefix plus `dog`) named in this dance's warrant contract, and an empty prefix renders a bare dog address that no agent holds. (default=gc-toolkit.)

Steps (6):
  ├── mol-dog-shutdown-dance.receive-warrant: Validate the warrant
  ├── mol-dog-shutdown-dance.interrogate-1: First interrogation (60s bound) [needs: mol-dog-shutdown-dance.receive-warrant]
  ├── mol-dog-shutdown-dance.interrogate-2: Second interrogation (120s bound) [needs: mol-dog-shutdown-dance.interrogate-1]
  ├── mol-dog-shutdown-dance.interrogate-3: Final interrogation (240s bound) [needs: mol-dog-shutdown-dance.interrogate-2]
  ├── mol-dog-shutdown-dance.execute: Execute the warrant — kill the session [needs: mol-dog-shutdown-dance.interrogate-3]
  └── mol-dog-shutdown-dance.epitaph: Record evidence, close the warrant, notify [needs: mol-dog-shutdown-dance.execute]
