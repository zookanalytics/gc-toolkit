---
name: Catch-up of subjects a sign-off left waiting on work
description: The census and the writes that gave each open subject a converse sign-off had left waiting on work its close brief and validating-closer arm. Read this before re-running that catch-up, as tk-8iaccir's follow-up does once the sign-off's own arm is live, or when asking whether any subject is still left that way.
---

# Catch-up of subjects a sign-off left waiting on work

Before tk-8iaccir, a `--ruled yes` sign-off with `--waiting-on <work>` gave
its subject a `blocks` edge onto the work and nothing else. Once the work
closed, the subject read ready with no route, no arm and a headline saying it
was ruled on, and nothing checked or closed it. tk-8iaccir has the sign-off arm
the subject's validating closer from then on. The catch-up gives each subject
already left that way the same two writes, once: its close brief and the arm.

## The state the census finds

A subject in that state is open and unassigned, a converse sign-off wrote its
headline (`gc.takeaway_by=converse`) with a wait rather than `--no-wait` (no
`gc.takeaway_settled`), and it has a `blocks` edge onto at least one bead that
is no gate. It carries no `gc.dispatch_when_ready` arm, no `gc.routed_to` and
no `merge_result`, and it is neither an epic nor a gate. Its work blockers may
all have closed, so it reads ready with nothing to send it, or some may still be
open, so it will read that way once they close. Both get the writes.

The census leaves three kinds of subject alone. One that an open human gate
also holds waits on a person first, and the person's answer decides what
follows. One that an open conversation tracks has a sitting, or a sitting to
come, that signs it off again. One that an open input convoy tracks has a run
on it already, such as the closer a reconcile pass slung once its arm cleared:
the pass retires the arm when it slings, so the subject reads unarmed again.

## The census

`census.sh <store>` prints one row for each subject in that store's state: its
id and type, its open work blockers, its closed work blockers, its open gate
blockers, the open conversations and input convoys that track it, and the start
of its headline.
Run it with `--db <rig path>/.beads` for each rig the rig map lists, the city's
own row included, since `--db` reaches every store and a suspended rig's store
reads too.

```bash
#!/usr/bin/env bash
set -uo pipefail
DB="$1"
q() { gc bd --db "$DB" sql "$1" --json 2>/dev/null; }
arr() { printf '%s' "$1" | jq -e 'type == "array"' >/dev/null 2>&1; }
SUBJ=$(q "select i.id, i.issue_type as type, json_unquote(json_extract(i.metadata,'$.\"gc.takeaway\"')) as takeaway
  from issues i
  where i.status = 'open'
    and json_unquote(json_extract(i.metadata,'$.\"gc.takeaway_by\"')) = 'converse'
    and coalesce(json_unquote(json_extract(i.metadata,'$.\"gc.takeaway_settled\"')),'') = ''
    and coalesce(json_unquote(json_extract(i.metadata,'$.\"gc.dispatch_when_ready\"')),'') = ''
    and coalesce(json_unquote(json_extract(i.metadata,'$.\"gc.routed_to\"')),'') = ''
    and coalesce(json_unquote(json_extract(i.metadata,'$.merge_result')),'') = ''
    and coalesce(i.assignee,'') = ''
    and i.issue_type not in ('epic','gate')
    and exists (select 1 from dependencies d join issues w on w.id = d.depends_on_issue_id
                where d.issue_id = i.id and d.type = 'blocks' and w.issue_type <> 'gate')")
arr "$SUBJ" || { echo "UNREAD $DB" >&2; exit 3; }
IDS=$(printf '%s' "$SUBJ" | jq -r --arg q "'" '[.[].id | $q + . + $q] | join(",")')
[ -n "$IDS" ] || exit 0
BL=$(q "select d.issue_id as s, w.id as w, w.issue_type as t, w.status as st from dependencies d
  join issues w on w.id = d.depends_on_issue_id where d.type = 'blocks' and d.issue_id in ($IDS)")
arr "$BL" || { echo "UNREAD blockers $DB" >&2; exit 3; }
CV=$(q "select d.depends_on_issue_id as s, c.id as c from dependencies d join issues c on c.id = d.issue_id
  where d.type = 'tracks' and c.issue_type in ('task','convoy') and c.status <> 'closed' and d.depends_on_issue_id in ($IDS)")
arr "$CV" || { echo "UNREAD trackers $DB" >&2; exit 3; }
printf '%s' "$SUBJ" | jq -r --argjson bl "$BL" --argjson cv "$CV" '.[] | .id as $s
  | [ $bl[] | select(.s == $s) ] as $b
  | [ .id, .type,
      ([ $b[] | select(.t != "gate" and .st != "closed") | .w ] | join(",")),
      ([ $b[] | select(.t != "gate" and .st == "closed") | .w ] | join(",")),
      ([ $b[] | select(.t == "gate" and .st != "closed") | .w ] | join(",")),
      ([ $cv[] | select(.s == $s) | .c ] | join(",")),
      ((.takeaway // "") | .[0:110]) ] | @tsv'
```

A row with an open gate blocker (the fifth column), or an open conversation or
input convoy (the sixth), is left alone, as the state above says.

## The writes for each subject

Each brief is written by hand. Read the subject's notes, where the sitting
recorded its ruling and what it sent, and each work blocker's title and close
reason. Then say what the work's landing settles on the subject and what the
closer checks once it has, and name a landing that already went wrong, such as
a blocker that closed as not needed, so the closer puts the subject to the
operator. The writes run in the subject's own rig, the brief first and the arm
once the brief has landed:

```bash
gc bd --db <rig path>/.beads update <subject> --append-notes "## Close brief (held on <work ids, comma-separated>, $(date -u +%Y-%m-%dT%H:%M:%SZ))
<what the work's landing settles on the subject, and what to check once it has>"
(cd <rig path> && GC_RIG=<rig> GC_RIG_ROOT=<rig path> "$(gc gc-toolkit scripts-dir)/deferred-dispatch.sh" arm <subject> \
  --db <rig path>/.beads --target <rig>/gc-toolkit.polecat \
  --sling-arg --on --sling-arg mol-validate-close \
  --reason "waits for <work ids>; the validating closer checks it once that lands")
```

The `blocks` edges are already in place, written by the sign-off's headline, so
the catch-up writes none. `deferred-dispatch.sh list --db <rig path>/.beads`
then names each arm `DISPATCHABLE NOW`, when every wait has closed, or `HELD`
with the wait that holds it. A census run after the writes lists only the
subjects it left alone.

## What the 2026-11-09 run found

The census ran over all seven of the city's stores at 2026-11-09T19:41:58Z,
after a first pass whose results matched it.

- gc-toolkit's store held 14 subjects, and each got its brief and arm. The work
  of 11 had all closed, so the next pass sends their closers. Two wait on work
  still open, and one on a park gate that holds its parent's ancestor.
- Another rig's store held 8. Seven got the brief and arm: the work of 5 had
  all closed, and 2 wait on work still open. One was left, because an open
  human gate holds it. Of the six beads the operator's ruling named in that
  store, one had closed by the time of the census, and the other five are among
  the seven.
- The other five stores held none.

tk-8iaccir's notes name each subject, its waits and its state.
