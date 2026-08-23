---
name: Work record — closed is not landed, and a dedup marker has to be able to be wrong
description: Why detect-parked-dispositions fired on a transient close during the polecat→review handoff, why the fix is a settle on the observation's inputs plus a self-invalidating marker rather than a landedness oracle, the 786/531 measurement that ruled the oracle out, and the mutation matrix.
---

# Closed is not landed

Work record for `tk-vathjv`. What is authoritative about the resulting
behaviour lives in `docs/gascity-human-engagement.md`, *"Closed is not
landed"*; this file is the reasoning, the measurements, and the shapes that
were rejected.

## The bead's premise, re-derived

Confirmed, with one correction to its framing.

`detect-parked-dispositions.sh` filed visit `tk-phbwfu` on subject `tk-jr8rw`
saying every piece of work it routed had landed. PR #445 was open, unmerged,
zero reviews. The observed window:

| time (2026-08-23) | event |
|---|---|
| 17:05:51Z | `tk-b3rga` closed, reason *"PR #445 opened (mr strategy)"* |
| 17:07:41Z | this pass sampled — read the set as fully landed, filed `tk-phbwfu` |
| 17:11:30Z | `check-set-heal.sh` reopened `tk-b3rga` |
| 17:49:34Z | `tk-b3rga` closed for real, `merged_sha=6a21282a` |

**The correction.** The bead attributes the transient close to
`mol-polecat-work` closing the work bead at PR-open. It is not the formula.
That reason string appears in no pack script, no `gc` source and no `gc`
binary — `specs/tk-fip23/closed-anchor-incident.md` establishes it was composed
by a refinery *agent* falling back to stock-GasTown behaviour that
`mol-refinery-patrol.toml` overrides in three places. `tk-b3rga` still carries
the repair's fingerprints: `reopened_not_landed=PR#445@open`,
`merge_result_healed`, `check_set_healed`.

This matters for where the fix goes. The transient close is a defect that
already has an owner and a working repair — it was reversed in 5m39s. What has
no owner is that a detector sampling inside that window was permanently
poisoned by it. So this pass should not try to re-derive whether work landed;
it needs to stop being poisoned.

## Why the burn is worse than the wrong visit

`disposition_flagged` is a one-shot keyed to the sorted id set of the landed
work. The ids do not change when a bead goes closed → open → closed. So the
false filing stamped `tk-b3rga`, and the real landing would compute
`tk-b3rga` again, match, and take the `already` branch forever. The subject
also carries a `gc.takeaway`, which mutes the stall detector. Every path to a
push was closed, and nothing anywhere records that a push was owed — which is
the same self-concealing shape as the 4h19m `tk-z9nln` incident this pass was
built to prevent, reached through a different door.

## What was built

**The settle.** A wait member that closed within `GC_PARKED_SETTLE_SECONDS`
(default 900) counts as still open. The script's header used to say *"There is
deliberately NO staleness window"*, and that objection is answered rather than
overridden: it argues against a window on the **trigger**, which would delay a
push whose whole value is promptness. This is a settle on the observation's
**inputs** — a close that recent has not yet been past the repair passes that
would reverse it. Folded into `WAIT_OPEN` in one place, so both arms and
`--wait-spent` inherit it without knowing it exists.

**The re-arm.** `disposition_flagged` equal to the *current* landed key over a
wait that is not spent is cleared. That state cannot be reached honestly: a
genuine filing leaves every member closed, and closed beads stay closed. So
reaching it means the ids went closed → open after the stamp, and the marker
will read identically when the work really lands.

It cannot loop. Clearing writes an **absent** marker, so the next pass has
nothing to clear. It fires only when the marker *equals* the current key, which
the ordinary "a second round of work was routed" case never satisfies — there
the key already differs and the existing REFLAG path handles it with no write.
`hold_flagged` is deliberately not cleared alongside: the hold arm is gated on
an empty `WAIT_OPEN` so it cannot fire while this condition holds, and when the
wait does land the disposition arm runs first by precedence and re-stamps both.

The two are complementary, and the second is what makes the first's
fail-direction safe. The settle makes the misread rare; the re-arm makes *any*
misread — this one, or one nobody has thought of — cost one visit instead of
the wake-up.

## Rejected: derive landedness from the member itself

The bead's first candidate: fire only when a closed member shows it landed.
Measured against the live store before writing any of it (2026-08-23,
gc-toolkit, closed beads carrying a `pr_number`):

| | count |
|---|---|
| total | 786 |
| `merged_sha` present | 250 |
| `merge_result == merged` | 248 |
| either | 255 |
| **neither** | **531** |

Two disjoint reasons for the 531. Review beads carry a `pr_number` and close
against an open PR by design (`tk-vjo2gf`, `tk-3rexni`, close reason *"review
complete"*). And genuinely-merged anchors keep stale handoff spellings —
`tk-wvrga` is closed with `close_reason` *"merged to main via PR, verified
ancestor of origin/main at d66dded"* and `merge_result` still `pull_request`;
PR #428 merged at 08:10:51Z.

So that predicate reads 68% of landed work as never-landed. Applied, it would
silently mute this pass on `tk-z9nln` — the very subject the 4h19m incident was
measured on, whose recorded wait includes `tk-wvrga`. A guard that turns the
detector off is a worse outcome than the bug it fixes, and it fails quiet.

Asking `gh` per member instead was rejected on two counts: a network call per
candidate inside a patrol pass, and re-deriving — badly, from one script over —
a closed-but-not-landed judgement `check-set-heal.sh` phase 0a already owns,
with the PR-identity certification, ambiguity and operator-hold guards this
pass has none of. The header records both refusals so the next reader does not
re-propose them.

Also rejected: the bead's third candidate, holding the marker until the visit
closes with an outcome other than `moot`. It reaches the same place by a longer
route — a new read of closed visits and their outcomes — and it *can* loop: a
premise that is genuinely true but whose visit is closed moot for an unrelated
reason would re-file every pass, once per round, forever. The re-arm keys on the
observation instead of on what someone did about it, and so cannot.

## The bug the mutation matrix found

`m3` — flipping `unsettled`'s fail-direction so an absent `closed_at` *holds*
its subject — **survived the first matrix run**, passing 138/138. It should have
broken almost everything, since every pre-existing fixture is dateless.

The cause was in the fix, not the test. GNU `date -u -d "" +%s` does not fail:
it returns **today at midnight, rc=0**. So an absent `closed_at` was being read
as a real instant around 00:00Z. At the hour the suite ran that is ~19h ago —
comfortably settled — and the intended contract held **by accident**. It would
have inverted for the first `SETTLE_SECONDS` of every UTC day: a dateless closed
member holding its subject, invisibly, for fifteen minutes daily.

`epoch_of` now rejects a blank argument before `date` ever sees it. The same
latent trap was already present in `held_for`, where it could have rendered a
fabricated *"19h42m"* for an undated hold; sharing the guarded helper fixes both.

Two further defects surfaced the same way:

- `m4` (delete the re-arm) *truncated* the suite rather than failing it:
  `CLEARS=$(grep -c … )` exits 1 on zero matches, and an assignment from a
  failing command substitution aborts the run under `set -e`. Every later case
  silently stopped running. Fixed with `|| true`.
- `m5` (re-arm on any marker, dropping the equality half) survived, because the
  case written for it — `s-reflag` — has a fully closed wait and takes the
  dispose path, never reaching the branch the re-arm lives in. It was not a
  discriminator. `s-rearmnot` was added: a first round flagged, a second round
  still in flight, so the key already differs and nothing is falsified.

## Verification

**Mutation matrix**, nine mutations, each caught by its own named assertion
(141 assertions total, 0 failures unmutated):

| mutation | result |
|---|---|
| `m1` settling members not folded into `WAIT_OPEN` | 8 failed — SETTLE ×4, CENSUS, NOCLEAR, SPENTSETTLE ×2 |
| `m2` `unsettled()` always answers settled | 8 failed — same set, different site |
| `m3` absent `closed_at` holds instead of settling | 30 failed — incl. NOCLOSEDAT |
| `m4` re-arm deleted | 10 failed — REARM ×3, REARMONCE ×3, REARMHOLD, CENSUS, NOCLEAR ×2 |
| `m5` re-arm on any marker, not one equal to the key | 6 failed — REARMNOT ×3, CENSUS, NOCLEAR ×2 |
| `m6` re-arm also clears `hold_flagged` | 3 failed — REARMHOLD, VERIFY, HELMFAIL |
| `m7` settling folded back into `waiting` | 2 failed — SETTLE census, CENSUS |
| `m8` `--wait-spent` opts out of the settle | 2 failed — SPENTSETTLE ×2 |
| `m9` re-arm ignores `--dry-run` | 2 failed — NOHELM, DRY |

**Live paired control**, HEAD's script vs the patched one, both `--dry-run`
against the real gc-toolkit rig: byte-identical selection (0 filed, 5 waiting,
1 with no recorded wait), differing only by the two new census fields.

**Live positive control**, so the settle is proved wired to real store data
rather than to fixtures — `--wait-spent tk-z9nln`, whose three children closed
17–26 hours ago:

```
HEAD                        rc=0  SPENT — all landed: tk-wvrga,tk-z9nln.1,tk-z9nln.2
PATCHED, default 900s       rc=0  SPENT — (matches HEAD)
PATCHED, settle 30d         rc=1  NOT spent — closed within the 2592000s settle:
                                  tk-wvrga,tk-z9nln.1,tk-z9nln.2
```

**Suites:** `detect-parked-dispositions.test.sh` 141/0;
`detect-stalled-workflows.test.sh` (the `--wait-spent` consumer) 86/0.
`bash -n` clean; `shellcheck -S warning` (containerised) clean on both changed
files, and clean at `origin/main` too, so nothing new was introduced.

## Not done

- **No repair of already-burned markers.** The bead measured 3 open subjects
  carrying `disposition_flagged` and only `tk-jr8rw` affected; it was hand-cleared
  by converse, `tk-b3rga` has since genuinely closed, and the marker was re-stamped
  on a true observation. Re-checked live: nothing is currently poisoned, and the
  re-arm handles it from here without a migration.
- **Nothing about the transient close itself.** It belongs to the refinery's
  close-on-land contract (`specs/tk-fip23/closed-anchor-incident.md`), which
  already detects and reverses it. The bead's fourth candidate — "have the work
  bead not close at PR-open" — is that contract, and it is already the rule.
