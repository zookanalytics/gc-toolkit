---
name: portfolio-sync
description: Use when you are the po in a portfolio sync, working your rig's epics with the operator, such as which epics the rig works on now and which are parked, the order within each, what an epic closed or shifted since the last sync changes, and which epics are due a review. For the queue of held new work, use backlog-refinement.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Portfolio sync

A portfolio sync works your rig's epics with the operator: which the rig works
on now, which wait, and in what order. You bring a recommendation for each epic,
with your reasons, and the operator rules. You apply each ruling through your
prompt's levers once they agree, and each write's exit says whether it landed.

## What a park says

A park separates whether the rig works on an epic from where the epic ranks. An
epic nothing parks is one the rig works on now. Every other epic is parked, and
its park says what releases it. Priority ranks the epics within each group, so
bd's five levels are enough. How many epics the rig works on is the operator's
choice as they prioritize, never a count, since one rig has room for five and
another for one. Propose no limit, and hold the portfolio to none.

## 1. Read the epics against the rig's goals

Open from your rig's goals, as your prompt's "The rig's goals" reads them. Then
read each open epic, its Deliveries among them, by the epic read in your
prompt's "Reads". An epic's frontier names the park that holds it, when one
does. Its horizon counts the work directly under it, open, closed, advancing
and stuck, and counts an open Delivery as stuck, because no pool takes an epic.

## 2. Weigh each epic closed or shifted since the last sync

A review of an epic rules continue, shift or close on the epic's own evidence.
That ruling is the operator's, made in the review and never in this sitting,
but a close or a shift can change what the rig works on and in what order, so
weigh each one. Every note a sync writes carries its date (section 4), so the
newest such date is the last sync's. This prints that date, then each epic
closed or shifted since, oldest first. It leaves out Deliveries, the epics under
another of the rig's epics with no hypothesis of their own, whose close is one
of the writes of their epic's ruling. A rig with no sync yet lists every one.
When the store does not answer, it lists nothing and says so, since a list it
could not read is not an empty one:

```bash
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
EPICS=$(gc bd --rig <rig> list --type epic --all --limit 0 --json) \
  && EPICS=$(printf '%s' "$EPICS" | scrub) \
  && printf '%s' "$EPICS" | jq -e 'type == "array"' >/dev/null \
  || { echo "The rig's epics did not read, so what closed or shifted is unknown. Run this again before you weigh any change." >&2; exit 1; }
printf '%s' "$EPICS" | jq -r '
  (reduce .[] as $e ({}; .[$e.id] = true)) as $epic
  | ([.[] | (.notes // "") | scan("Portfolio sync, po sitting ([0-9]{4}-[0-9]{2}-[0-9]{2})") | .[0]] | max // "") as $since
  | "last sync: \(if $since == "" then "none" else $since end)",
    ([.[] | select(($epic[.parent // ""] | not) or (.metadata.epic_hypothesis // "") != "")
      | select((.status == "closed" and (.closed_at // "") >= $since)
        or (.status != "closed" and .metadata.epic_ruling == "shift" and (.metadata.epic_ruling_at // "") >= $since))]
    | sort_by(.closed_at // .metadata.epic_ruling_at)[]
    | if .status == "closed" then "\(.closed_at) \(.id) closed: \(.close_reason // "")"
      else "\(.metadata.epic_ruling_at) \(.id) shifted: \(.metadata.epic_ruling_reason // "")" end)'
```

For each, read the newest `## Epic review` block in its notes, when it has one,
for what the ruling moved. A close can send the epic's work to another epic, and
a shift changes an epic's course and can change its hypothesis. Say what each
changes in the portfolio, such as a parked epic to bring forward now that a
worked one has closed, or a priority that no longer fits a shifted epic, and
propose the move.

## 3. Name the epics due a review

A review is the operator's judgment of an epic, in a sitting of its own. From
what the epic read showed, name each epic whose state calls for one, such as
these, and say why:

- one whose Delivery has landed: an open Delivery under it whose horizon counts
  work, none of it open;
- one with no open work: its own horizon counts none open;
- one that has stalled: nothing parks it, yet no open work under it advances.
  Read the work outside its Deliveries from its own horizon, and the rest from
  each open Delivery's.

Propose each review, and give the operator the command that calls it:
`gc-helm engage <epic> --reason "Review this epic: <why it is due>"`.

## 4. Bring the portfolio, and note each ruling

Bring which epics the rig works on now, which wait and the order within each,
by your prompt's "Sequencing: WSJF", with what sections 2 and 3 found. Each
piece fits one screen and carries a recommendation for each epic.

Note each ruling on its bead under the sync's date, with the operator's reason
in their words. On each epic that section 2 listed, note too what the sync made
of its close or shift, even when nothing moved, so the next sync's list starts
after this one:

```bash
gc bd --rig <rig> update <bead> --append-notes "Portfolio sync, po sitting $(date -u +%Y-%m-%d): <ruling: reason>"
```
