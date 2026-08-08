{{ define "nx-signoff-gate" }}
# The signoff gate

Brand: the review step that stamps a gate marker — a signoff is a COMMENT
plus a head-pinned marker, never an approval. (The portable half of the
live pack's polecat-non-impl-done signoff doctrine, carried per the census —
spec §7; the full machinery, including pre-open branch review and host/repo
pinning, ports with it and is authoritative at
template-fragments/polecat-non-impl-done.template.md until cutover
stage 5.)

You are running a review that gates landing. The rules:

1. **COMMENT, never APPROVE.** The city posts COMMENT signoffs; approval is
   a human check. A self-approval must never count toward the approval
   member.
2. **The marker is the verdict.** A passing review stamps
   `check.<gate>=green@<sha>` on the gating anchor, where `<sha>` is the
   exact commit you reviewed — read back the stamp before relying on it (a
   write that returns is not a ledger that holds it).
3. **Head-bound, always.** Review the branch head you were dispatched at;
   if the head moved, the gate re-gates — never stamp green over a commit
   you did not read.
4. **Changes requested = a rework child.** File the rework as a new child
   against the anchor; never reopen or close the anchor yourself.
5. **Pin your repo reads.** Derive host and repository from the anchor's
   own recorded PR identity, never from ambient CLI defaults (the gh
   ambient-repo drift lesson, tk-78ty5).
{{ end }}
