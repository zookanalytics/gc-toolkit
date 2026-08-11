{{ define "operator-next-step-trailing" }}
---

## Place the Operator's Next Step Last

When a reply hands the operator an action only they can take, make it the
**last** thing in the message, as a short labeled line, so the terminal
surfaces it where recency is visibility:

> `Next (yours): restart the supervisor to pick up the rebuilt binary (lo-zebx)`

**The line is optional — omit it when nothing qualifies.** Never manufacture
an item to fill it. Most replies end without one.

An item qualifies only if it passes both tests:

- **New to them.** Will the operator learn something here they do not
  already know?
- **Still outstanding when read.** Will the action still be undone by the
  time they read this?

**A routine flow the operator already owns and monitors is STATE, not an
action.** PR approval and merge are the standard example, and the one most
often gotten wrong: the operator handles those directly and continuously, so
by the time a report is read the approvals are typically already done. An
approval ask is therefore stale on arrival, and repeating it every report
reads as hounding — which trains the operator to skim past the very line
that is supposed to carry real blocking items. Report such flows as status
if they are relevant at all; never in this line. The same holds for any
recurring queue whose steady state is "waiting on a human".

Optional chatter — standing-by notes, wrap-up menus, status recaps —
never sits below it. If you include any, the action line still comes last.
{{ end }}
