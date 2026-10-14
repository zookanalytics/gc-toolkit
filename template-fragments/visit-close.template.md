{{ define "visit-close" }}
### Closing a visit: never by hand

A closed visit records why it closed in two keys: `gc.outcome`, one word,
and `gc.outcome_reason`, one sentence. The board takes a finished sitting's
outcome from them, so a visit closed without them looks like a need nobody
met. A bare `gc bd close` or `--status=closed` on a visit records neither.

A sitting closes the visit it works. Outside a sitting, a visit is closed
only by the role that raised it, and only when it was filed in error, when
another visit already carries its need, or when its premise is gone. That
close goes through one of two writers:

```bash
for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$cand/assets/scripts/visit-close.sh" ] && { SCRIPTS="$cand/assets/scripts"; break; }
done
# An open escalation you raised on a bead:
"$SCRIPTS/escalate.sh" --retract --subject <bead> --key <situation-key> --message "<why it needs nobody now>"
# Any other visit you raised:
"$SCRIPTS/visit-close.sh" --visit <visit> --outcome <word> --reason "<one sentence>"
```

`escalate.sh --retract` finds the open visit by the subject and key it was
filed under, and closes it `moot` through `visit-close.sh`. It leaves a visit
with an assignee or a bound session open for whoever holds it.
`visit-close.sh` stamps both keys and reads them back before it closes. On a
visit that is already closed it records the two keys and leaves the close as
it was, so it also repairs a visit closed by hand.

The word carries weight. `moot` (the premise is gone) and `benign` (it holds
but needs nobody) stop `escalate.sh` filing the same key and subject again
for a day. Any other word means someone acted. Use `duplicate` when another
visit carries the need, and `resolved` when you acted to end it.

A visit another role raised, or one a sitting has claimed, is the sitting's
to close, even after you resolve its situation. Append what you did to its
notes and leave it open. Close it yourself only when the operator tells you
to, and then through `visit-close.sh`.
{{ end }}
