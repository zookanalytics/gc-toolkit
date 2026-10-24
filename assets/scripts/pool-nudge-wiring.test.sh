#!/usr/bin/env bash
# A pool worker that cannot finish its claim hands the bead back the way its
# agent's nudge says, and the nudge is all a woken slot has read before it loads
# its prompt. A hand-back that clears the assignee alone leaves the bead
# in_progress, which no pool's work query serves, so the bead sits stranded
# until a person finds it. This test holds the pack's instructions to the one
# guarded write that reopens the bead and releases the claim together:
#
#   1. Every agent nudge that tells a worker what to do with its assignee names
#      that write as one backticked `gc bd update` command: the holder guard on
#      the worker's own session id (--if-assignee="$GC_SESSION_ID"), the status
#      guard (--if-status=in_progress), the reopen (--status=open), the cleared
#      assignee (--assignee="") and both session pins unset. A guard on whatever
#      assignee the bead shows would let the write unassign another session's
#      claim, because a write guarded on the assignee skips bd's reassign
#      fence. No nudge names gc bd release-if-current, which leaves the pins
#      and, given a pool session's id as the holder, releases a rig bead
#      against the city store, where it finds nothing and still exits 0.
#   2. The polecat and polecat-codex nudges are identical, as both agent files
#      say they are, and they carry the hand-back.
#   3. No tracked file under agents/, formulas/, template-fragments/, skills/,
#      packs/, assets/scripts/, doctor/, tools/ or overlays/, tests aside,
#      tells its reader to clear its assignee in those words, and no `bd
#      update` command in one clears an assignee unless the same command
#      reopens the bead (--status=open) or is guarded to an open bead
#      (--if-status open), which cannot leave an in_progress bead unassigned.
#      orphan-dispose.sh, the witness's release of a dead owner's claim, still
#      splits its reopen and its clear, and a fix of its own owns that. It is
#      listed by name, and the check fails once it no longer splits, so the
#      listing goes with the split. The text is read with shell and TOML line
#      continuations joined, and the phrase with line wraps joined too, so a
#      phrase or a command that a line break splits is still found.
#
# run-tests-scope: tree
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # tomllib_python only; the assertions below are this suite's own

TOMLS=()
for T in "$ROOT"/agents/*/agent.toml "$ROOT"/packs/*/agents/*/agent.toml; do
  [ -s "$T" ] && TOMLS+=("$T")
done
[ "${#TOMLS[@]}" -gt 0 ] || { echo "no agent TOMLs under $ROOT" >&2; exit 1; }

# Tests and the shared harness spell out the very writes check 3 forbids, as the
# fixtures and controls that prove it, so they are left out.
TEXTS=$(git -C "$ROOT" ls-files -- agents formulas template-fragments skills packs assets/scripts doctor tools overlays \
  | grep -vE '(\.test\.sh|_test\.go|/test-harness\.sh)$')
[ -n "$TEXTS" ] || { echo "git ls-files lists nothing under agents/, formulas/, template-fragments/, skills/, packs/, assets/scripts/, doctor/, tools/ or overlays/ in $ROOT" >&2; exit 1; }

if ! TOML_PY="$(tomllib_python)"; then
  echo "skip - every check: $TOML_PY"
  exit 0
fi

# Each result line is "ok|<message>" or "bad|<message>". The agent TOMLs are the
# arguments, and the tracked text files for check 3 arrive in WIRING_TEXTS, one
# per line, because the program itself is the reader's stdin.
RESULTS=$(WIRING_TEXTS="$TEXTS" "$TOML_PY" - "$ROOT" "${TOMLS[@]}" <<'PY'
import os, re, sys, tomllib

root, paths = sys.argv[1], sys.argv[2:]

# --- 1. The hand-back each nudge names. ---
# The holder guard names the worker's own session id, the identity gc hook
# records a pool worker's claim under.
OWN_GUARD = '--if-assignee="$GC_SESSION_ID"'
PARTS = [
    OWN_GUARD,
    "--if-status=in_progress",
    "--status=open",
    '--assignee=""',
    "--unset-metadata gc.session_id",
    "--unset-metadata gc.session_name",
]
nudges = {}
for path in paths:
    name = os.path.relpath(os.path.dirname(path), root)
    try:
        with open(path, "rb") as f:
            nudge = tomllib.load(f).get("nudge", "")
    except tomllib.TOMLDecodeError as e:
        print("bad|%s: agent.toml does not parse: %s" % (name, e))
        continue
    nudges[name] = nudge
    if "assignee" not in nudge.lower():
        continue
    if "release-if-current" in nudge:
        print("bad|%s: the nudge names gc bd release-if-current" % name)
    commands = [c for c in re.findall(r"`([^`]*)`", nudge) if c.startswith("gc bd update ")]
    if any(all(p in c for p in PARTS) for c in commands):
        print("ok|%s: the nudge's hand-back is one guarded gc bd update that reopens the bead and releases the claim" % name)
    elif commands:
        missing = [p for p in PARTS if not any(p in c for c in commands)]
        print("bad|%s: the nudge's gc bd update hand-back lacks %s" % (name, ", ".join(missing) or "its parts in one command"))
    else:
        print("bad|%s: the nudge tells the worker what to do with its assignee but names no backticked gc bd update hand-back" % name)

# --- 2. The two pool nudges. ---
pool = ["agents/polecat", "agents/polecat-codex"]
if all(p in nudges for p in pool):
    a, b = (nudges[p] for p in pool)
    print(("ok|" if a == b else "bad|") + "the polecat and polecat-codex nudges are %s" % ("identical" if a == b else "different"))
    carries = OWN_GUARD in a
    print(("ok|" if carries else "bad|") + "the polecat nudge %s the hand-back" % ("carries" if carries else "does not carry"))
else:
    print("bad|the polecat and polecat-codex nudges are missing: agents/polecat or agents/polecat-codex has no agent.toml")

# --- 3. No instruction to clear an assignee alone. ---
# An empty assignee value: "" or '' or nothing before a space, a backtick or
# the end of the command. --if-assignee= is a guard, not a write, and the
# lookbehind keeps it out. A clear guarded to an open bead cannot leave an
# in_progress bead unassigned, so it needs no reopen beside it.
CLEAR = re.compile(r"(?<![\w-])(--assignee|-a)(=(\"\"|''|(?=[\s`]|$))|\s+(\"\"|''))")
OPEN_GUARD = re.compile(r"--if-status(=|\s+)[\"']?open\b")
# The witness's release of a dead owner's claim, which reopens it and clears its
# assignee in two writes until a fix of its own makes them one.
KNOWN_SPLIT = {"assets/scripts/orphan-dispose.sh"}
texts = [t for t in os.environ.get("WIRING_TEXTS", "").splitlines() if t]
hits, split, known = [], [], set()
for rel in texts:
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        continue
    text = re.sub(r"\\\n[ \t]*", "", text)
    for line in text.splitlines():
        for cmd in re.split(r";|&&|\|\||\|", line):
            if re.search(r"\bbd update\b", cmd) and CLEAR.search(cmd) and "--status=open" not in cmd and not OPEN_GUARD.search(cmd):
                if rel in KNOWN_SPLIT:
                    known.add(rel)
                else:
                    split.append("%s: %s" % (rel, cmd.strip()[:160]))
    if re.search(r"clear your (own )?assignee", re.sub(r"\s+", " ", text), re.IGNORECASE):
        hits.append(rel)
if hits:
    print("bad|an instruction tells its reader to clear its assignee: %s" % ", ".join(hits))
else:
    print("ok|none of the %d tracked files tells its reader to clear its assignee" % len(texts))
if split:
    print("bad|a bd update clears an assignee without reopening the bead in the same write: %s" % "; ".join(split))
else:
    print("ok|every bd update in them that clears an assignee reopens the bead in the same write, or is guarded to an open bead")
for rel in sorted(KNOWN_SPLIT):
    if rel in known:
        print("ok|%s, the one release listed by name, still splits, so its listing stands" % rel)
    else:
        print("bad|%s no longer clears an assignee in a write of its own: take it out of KNOWN_SPLIT" % rel)
PY
); PY_RC=$?

# A reader that dies reports nothing, which would otherwise read as no finding.
[ "$PY_RC" -eq 0 ] || bad "the reader exited $PY_RC"
case "$RESULTS" in
  *"polecat and polecat-codex nudges are"*) ;;
  *) bad "the reader reported nothing about the polecat and polecat-codex nudges" ;;
esac
case "$RESULTS" in
  *"tells its reader to clear its assignee"*) ;;
  *) bad "the reader reported nothing about instructions to clear an assignee" ;;
esac
case "$RESULTS" in
  *"clears an assignee"*) ;;
  *) bad "the reader reported nothing about bd update commands that clear an assignee" ;;
esac
while IFS='|' read -r verdict message; do
  case "$verdict" in
    ok)  ok "$message" ;;
    bad) bad "$message" ;;
    *)   [ -z "$verdict" ] || bad "unreadable result line: $verdict|$message" ;;
  esac
done <<< "$RESULTS"

echo
echo "pool-nudge-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
