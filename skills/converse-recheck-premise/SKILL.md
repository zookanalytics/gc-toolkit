---
name: converse-recheck-premise
description: Converse's step 2 — re-check a claimed visit's premise against live state before prepping, and take the moot/benign close-out exit that ends a visit with nothing posted. Converse loads this from its step-to-skill routing table when a fresh claim returns action=work; it is not for other agents.
---

# Step 2 — Re-check the premise

The condition that justified filing a visit routinely dies before anyone
claims it. Test the VISIT's own premise against live state before you prep,
and before the rename: a visit that closes here should not have moved the
operator's session title.

`$CONV`, `$VISIT`, and `$SUBJECT` are resolved in step 1's claim block.

Re-read the visit body. Its stated conditions ARE the premise, often
bulleted literally — *"no `triage.hold` and no `gc.takeaway` on the
root"*, *"its frontier is [...] UNASSIGNED"*. Check each one still
holds, on the subject and on whatever bead the premise is about (a
stalled-workflow visit names that bead in its own `stall_root`):
```bash
gc bd show "$SUBJECT" --json | jq -r '.[0].metadata
  | "hold=\(.["triage.hold"] // "") takeaway=\(.["gc.takeaway"] // "")"'
```
NON-EMPTY is the test for `triage.hold` — an EMPTY stamp is a CLEARED
hold. A `gc.takeaway` dates the last sitting rather than naming a live
wait: read what it says, then check whether that wait is still open.

Two readings end the visit here, with nothing posted:

- **moot** — the premise no longer holds. The frontier was routed,
  the bead was closed, another visit already settled it.
- **benign** — the premise holds but needs no human: the wait is
  already named by a non-empty `triage.hold` or an open demand bead,
  or the condition is a known acceptable state. **An open PR
  awaiting the operator's review is the canonical case** — their own
  review queue, and handing it back is the bug this step prevents.

  **A takeaway is never a benign wait on its own**, because nothing
  clears it. Re-check the ids in the body (`bd show`, and
  `gc bd list --parent "$SUBJECT" --all`); it is moot only if
  something is open again.

Close it out with `converse-close-out.sh`, which appends the reading to
the subject's notes, stamps `gc.outcome=<moot|benign>` on the visit,
reads it back, and closes the visit — no takeaway, nothing posted:
```bash
VISIT="$VISIT" SUBJECT="$SUBJECT" \
  "$CONV/converse-close-out.sh" <moot|benign> "<the premise, and what is true instead>"
```
Then go to step 8 and claim again. **Post nothing** — no framing, no
sign-off, not even "this turned out to be fine". Deliberately **no
takeaway stamp** either: it is the subject's headline of what it
NEEDS, and one for a visit that needs nobody spends the attention this
exit saves.

The exit is gated on being *named*: if you cannot point at the stamp
or state that makes this benign, you hold the sitting.
Uncertain is not benign.

When the premise still holds and needs a human, this visit earns a sitting:
prep it (steps 3–4, the `converse-prep` skill).
