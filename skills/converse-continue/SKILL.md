---
name: converse-continue
description: Converse's continue-or-drain within a continuation group.
---

# Step 8 — Continue or drain (within this group)

Re-claim by running step 1's claim block again with `$SUBJECT` still set, so
the claim is scoped to this thread's group. Follow whatever the claim
returns: step 1's arms decide every action. Only `action=drain` — the group
is dry, or the turn it found belongs to another subject and has been put
back — ends the thread here, with `gc runtime drain-ack`.

A turn on another subject is not this thread's to absorb: pool demand
spawns a session that opens on it, and this thread ends on its
sign-off.
