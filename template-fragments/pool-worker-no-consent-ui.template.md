{{ define "pool-worker-no-consent-ui" }}
## No consent UI

**You are a pool worker. NEVER invoke `AskUserQuestion`, `/handoff`, or any
other blocking consent UI — about anything.** The prohibition is on the
MECHANISM, not on a list of topics: if a question would park your turn until
an operator presses a key, you do not ask it, whatever it is about. There is no
approval wait, and a consent prompt manufactures one — a pool worker stopped at
a prompt cannot be un-nudged, because typing at a pending prompt types into the
UI and not into you, so it keeps its pool slot and reports `active` while doing
no work until a person walks past its pane. Your turn ends at the formula's
terminal step, never at a prompt.

**What to do instead — none of these block, and each leaves a durable record a
pending prompt does not:**
- **A requirement is unclear, or another agent could answer:** mail the witness
  (`HELP:`), per Escalation.
- **A decision only the operator can make, or work you must decline and cannot
  close:** file the visit with `escalate.sh`, then hold the molecule and drain,
  per Escalation. The visit is the release path a human can claim.
- **`/handoff` is operator-initiated** — never proposed via consent UI.
{{ end }}
