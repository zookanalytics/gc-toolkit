---
name: converse-recheck-premise
description: Converse's premise re-check, and the close of a conversation whose premise died or needs no person, with nothing posted.
---

# Re-check the premise

Each call starts a fresh shell, so set `CONV`, `CONVERSATION` and `SUBJECT`
literally, from the entry's output, at the top of every call below.

The condition that justified a conversation, or a gate it replies to, often
dies before the operator engages it. Test it against live state before you
prep, so a conversation that closes here has not moved the operator's session
title or posted on the subject's PR.

The premise is the conversation's ask, its description, with the title and
description of each gate it replies to, the entry's `GATES`:

```bash
gc bd show "$CONVERSATION"
gc bd show <each gate GATES names>
```

Their stated conditions are the premise, often bulleted literally, such as
*"no `triage.hold` and no `gc.takeaway` on the root"*. Check each one still
holds, on the subject and on whatever bead it is about:

```bash
gc bd show "$SUBJECT" --json | jq -r '.[0].metadata
  | "hold=\(.["triage.hold"] // "") takeaway=\(.["gc.takeaway"] // "")"'
```

A non-empty `triage.hold` is a live hold, and an empty one is cleared. A
`gc.takeaway` dates the last sitting rather than naming a live wait: read it,
then check whether that wait is still open.

Two readings end the question with nothing posted:

- **moot**: the premise no longer holds. The frontier was routed, the bead
  closed, or another answer settled it.
- **benign**: the premise holds but needs no person. A non-empty
  `triage.hold` or another open human gate already names the wait, or the
  condition is a known acceptable state. An open PR awaiting the operator's
  review is the canonical case: it is in their own review queue, and handing
  it back to them is the mistake this check prevents. A takeaway alone is
  never a benign wait, because nothing clears it: re-check the ids in its body
  (`gc bd show`, and `gc bd list --parent "$SUBJECT" --all`), and it is moot
  only if something is open again.

Either reading names the stamp or state it rests on. When you cannot, hold the
sitting: uncertain is not benign.

Clear each gate the reading answers, with the reading as its answer, and read
it back. A gate another answer already closed keeps that answer, and a gate
assigned to a person is theirs to clear:

```bash
gc bd gate resolve <gate> --reason "<moot|benign>: <the premise, and what is true instead>" \
  && gc bd show <gate> --json | jq -r '.[0] | "\(.status) \(.close_reason // "")"'
```

When the conversation's own ask dies with them, close the conversation with
its record. The reading goes on the subject's notes, the conversation closes
with the reading as its reason, and the close is recorded among the visit's
actions, which the comment on the subject's PR then shows, so write it as one
plain sentence that names no other rig or its beads. The close writes no
headline, since one for a conversation that needs nobody spends the attention
it saves, except over a headline an earlier sitting's hold left waiting on
nothing. That is a headline with no `gc.takeaway_settled`, on a subject none of
whose own waits is pending, and it is replaced with the reading. `gctk bead
holds` answers what still holds the subject, and the block leaves this
conversation out of it, because its close frees an open PR's merge. Each write
takes its exit, and the conversation closes only after them:

```bash
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
KIND="<moot|benign>"; WHY="<the premise, and what is true instead>"
ACTION="<what ended the visit, in one plain sentence>"
ROW=$(gc bd show "$SUBJECT" --json) \
  && WAITS=$(printf '%s\n' "$ROW" | jq -er --arg s "$SUBJECT" 'if type == "array" and length == 1 and .[0].id == $s then (.[0].metadata // {}) | if ((.["gc.takeaway"] // "") | tostring) != "" and ((.["gc.takeaway_settled"] // "") | tostring) == "" then "waits" else "settled" end else error("unread") end') \
  && HOLDS=$("$GCTK" bead holds "$SUBJECT") \
  && OPEN=$(printf '%s\n' "$HOLDS" | jq -er --arg c "$CONVERSATION" 'if .error == null and (.pending | type) == "array" then [ .pending[].id | select(. != $c) ] | join(" ") else error("unread") end') \
  && if [ "$WAITS" != waits ] || [ -n "$OPEN" ]; then echo "$SUBJECT keeps its headline${OPEN:+: $OPEN still holds it}"; else
       "$CONV/gc-helm.sh" takeaway "$SUBJECT" "${KIND}: ${WHY}" --by converse --no-wait \
         && echo "replaced the headline of $SUBJECT, which waited on nothing"
     fi \
  && gc bd update "$SUBJECT" --append-notes "$KIND (conversation $CONVERSATION): $WHY" \
  && gc bd update "$CONVERSATION" --set-metadata gc.work_outcome=no-op \
  && { gc bd close "$CONVERSATION" --reason "${KIND}: ${WHY}" \
       || gc bd close "$CONVERSATION" --reason "${KIND}: ${WHY}" --force; } \
  && { gc bd comment "$CONVERSATION" "$ACTION" >/dev/null \
       || echo "the close was not recorded among the actions of $CONVERSATION"; } \
  && { "$CONV/pr-sitting-comment.sh" refresh --sitting "$CONVERSATION" || true; } \
  && echo "closed $CONVERSATION as $KIND"
```

When it prints its `closed` line, drain (the prompt's How a sitting ends), and
post nothing, not even "this turned out to be fine". No `closed` line means the
close stopped short, and the conversation stays open under this sitting,
still holding an open PR's merge. Say in the thread what the block printed,
fix what it names, and re-run it: the gates cleared above stay cleared, and
each write is safe to repeat.

When the premise holds and needs a person, the conversation earns a sitting:
prepare it (`converse-prep`). A gate this check cleared stays cleared.
