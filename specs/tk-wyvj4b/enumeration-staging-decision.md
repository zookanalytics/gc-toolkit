---
name: Doctor-check enumeration staging — checked-mktemp over process substitution
description: Why the doctor/check-*/run.sh `<<<` false-empty-queue fix stages enumerations through a checked mktemp rather than process substitution — the hermetic-testability evidence that decides it — plus the idiom, per-check assessment rule, test method, and the series cannot-recur capstone.
---

# Doctor-check enumeration staging — checked-mktemp over process substitution

## The defect
`doctor/check-*/run.sh` checks feed enumeration loops from `done <<< "$VAR"`
here-strings. bash backs a `<<<` here-string with a temp file in `$TMPDIR`; when
that file cannot be created (a full `/tmp`, an expected condition — tk-lt4rc) the
redirection fails silently, because these checks are `set -u`, not `set -e`. The
loop runs zero times. Each such loop sits behind a proven-non-empty guard and
falls through to the check's `OK` verdict, so a disk-pressure blackout of a
non-empty store is byte-indistinguishable from a healthy all-clear. Sibling of
tk-10690; same class as tk-lslk2 (pre-open-resolve.sh).

## Two candidate remedies
- **Process substitution** — `done < <(printf '%s\n' "$VAR")`. Already used in
  two doctor checks (check-step-terminal, check-recycle-capable). Keeps the loop
  in the current shell and uses a `/dev/fd` pipe with no temp file, so it removes
  the failure mode in production.
- **Checked mktemp** — stage `"$VAR"` into a checked, templated `mktemp` file and
  read it with a plain `< "$file"`. The landed idiom for the tk-10690 family
  (molecule-hold.sh:~333-369; sibling beads tk-9ng86u, tk-48z7tc).

## Why checked-mktemp wins: hermetic testability
The bead requires a disk-pressure test that **fails against the pre-fix code**.
That decides it, because a process-substitution fix cannot be given one:

- A bash here-string's temp file is created internally, not via the `mktemp`
  command, so a failing-`mktemp`-command shim is a no-op against both the pre-fix
  `<<<` and a process-sub fix — it discriminates neither.
- The only trigger that reaches bash's internal here-string temp file is an
  unwritable temp dir, and on this host's bash (5.3.9) an unwritable `$TMPDIR`
  falls back to `/tmp`, which is writable — so the here-string **succeeds**
  (verified: 3 iterations, no error). The failure is not hermetically
  reproducible without filling the real `/tmp`.
- Confirmation: both doctor checks that already use process substitution shipped
  **without** any disk-pressure test. There was no way to write one.

Checked-mktemp routes enumeration through the external `mktemp` command, which a
shim **can** intercept, so the failure is both caught in production (a full
`/tmp` fails `mktemp`) and reproducible in a hermetic test.

## The idiom
Exemplars: `doctor/check-state-space/run.sh`,
`doctor/check-closed-implies-landed/run.sh` (this bead); `molecule-hold.sh` on
main.

1. Once, after the scopes guard:
   `ENUM_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gctk-<check>.XXXXXX" 2>/dev/null) || { <cannot-scan message>; exit 1; }`
   then `trap 'rm -rf "$ENUM_TMP" 2>/dev/null' EXIT`. Template every mktemp
   (lint rule mktemp-untemplated).
2. Each false-clean loop: `printf '%s\n' "$VAR" > "$ENUM_TMP/<name>"` (checked),
   then `done < "$ENUM_TMP/<name>"`. A plain file redirect keeps the loop in the
   current shell, so the finding arrays survive it. The outer store loop aborts
   the run non-clean (exit 1) on a staging failure; an inner loop warns "this
   store was NOT checked" and continues, matching each check's existing
   unreadable-store arm.

## Per-check assessment
Only a `done <<< "$VAR"` that (a) sits behind a proven-non-empty guard and
(b) falls through to a clean verdict on zero iterations is a false-clean. A
`read -r a b <<< "$pair"` single-value split, or a loop whose zero-iteration is a
safe refusal, needs no change. Assess each here-string before converting it.

## Test method
Each touched check's `run.test.sh` gains a disk-pressure case: a failing `mktemp`
shim on PATH, plus a mirror run proving the fixture is not vacuously empty. Assert
the check goes non-clean (never exit 0 / `OK:`). Verify it fails against the
pre-fix script in a parallel tree (`CHECK="$HERE/run.sh"`, a two-file temp tree
suffices).

## Cannot-recur capstone
The strongest guarantee is a `tools/lint-learned.d/` detector forbidding
`done <<< ` enumeration in `doctor/check-*/run.sh`, which stops a new check from
reintroducing the class. It must land **last** in the series — it fails on any
un-converted check.
