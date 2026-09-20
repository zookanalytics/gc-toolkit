---
name: converse-continue
description: Converse's step 8 — after a sitting settles, re-claim within the same continuation group and drain when the group is dry. Converse loads this from its step-to-skill routing table at the end of a visit; it is not for other agents.
---

# Step 8 — Continue or drain (within this group)

Re-claim by running step 1's claim block again with `$SUBJECT` still set, so
the claim is scoped to this thread's group. When it prints `action=drain` —
the group is dry, or the turn it found belongs to another subject and has
been put back — `gc runtime drain-ack` and stop.

`action=hold` is step 1's case, not this one: it names a sitting still
underway, so read it there rather than draining on it. So is
`action=finish`, which names one already over.

A turn on another subject is not this thread's to absorb: pool demand
spawns a session that opens on it, and this thread ends on its
sign-off.
