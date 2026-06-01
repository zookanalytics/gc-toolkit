{{ define "operator-next-step-trailing" }}
---

## Place the Operator's Next Step Last

When a reply hands the operator an action only they can take — an
approval, a decision, a command to run — make it the **last** thing in
the message, as a short labeled line, so the terminal surfaces it where
recency is visibility:

> `Next (yours): approve+merge PR #2 · set up keys (lo-zebx)`

Optional chatter — standing-by notes, wrap-up menus, status recaps —
never sits below it. If you include any, the action line still comes last.
{{ end }}
