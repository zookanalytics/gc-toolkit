#!/usr/bin/env bash
# A pool worker that cannot finish its claim hands the bead back the way its
# agent's nudge says, and the nudge is all a woken slot has read before it loads
# its prompt. A hand-back that clears the assignee alone leaves the bead
# in_progress, which no pool's work query serves, so the bead sits stranded
# until a person finds it. This test holds the pack's instructions to the one
# guarded write that reopens the bead and releases the claim together:
#
#   1. Every agent nudge that tells a worker what to do with its assignee names
#      that write as one backticked `gc bd update` command: a holder guard
#      (--if-assignee=), the status guard (--if-status=in_progress), the reopen
#      (--status=open), the cleared assignee (--assignee="") and both session
#      pins unset. No nudge names gc bd release-if-current, whose gaps
#      assets/scripts/hand-back.sh's header names.
#   2. The polecat and polecat-codex nudges are identical, as both agent files
#      say they are, and they carry the hand-back.
#   3. No tracked file under agents/, formulas/, template-fragments/, skills/,
#      packs/, assets/scripts/, doctor/, tools/ or overlays/, tests aside,
#      tells its reader to clear its assignee in those words, and no `bd
#      update` command in one clears an assignee unless the same command
#      reopens the bead (--status=open) or is guarded to an open bead
#      (--if-status open), which cannot leave an in_progress bead unassigned.
#      The text is read with shell and TOML line continuations joined, and the
#      phrase with line wraps joined too, so a phrase or a command that a line
#      break splits is still found.
#   4. Each nudge's hand-back command runs, in bash and in zsh where zsh is
#      installed, against a stub store that enforces bd's --if-status and
#      --if-assignee: a mismatch writes nothing and exits 13. gc hook records a
#      claim under the worker's alias when it has one, else under its session
#      id, and the command releases it in both forms, an empty alias included,
#      leaving the bead open and unassigned, with no session pins, on its
#      route. It writes nothing to a bead another session or another alias
#      holds, or to one already closed.
#
# run-tests-scope: tree
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pool-nudge-wiring.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"

TOMLS=()
for T in "$ROOT"/agents/*/agent.toml "$ROOT"/packs/*/agents/*/agent.toml; do
  [ -s "$T" ] && TOMLS+=("$T")
done
[ "${#TOMLS[@]}" -gt 0 ] || { echo "no agent TOMLs under $ROOT" >&2; exit 1; }

# Tests and the shared harness spell out the very writes check 3 forbids, as the
# fixtures and controls that prove it, so they are left out. The listing runs
# before harness_init, whose git stub answers nothing.
TEXTS=$(git -C "$ROOT" ls-files -- agents formulas template-fragments skills packs assets/scripts doctor tools overlays \
  | grep -vE '(\.test\.sh|_test\.go|/test-harness\.sh)$')
[ -n "$TEXTS" ] || { echo "git ls-files lists nothing under agents/, formulas/, template-fragments/, skills/, packs/, assets/scripts/, doctor/, tools/ or overlays/ in $ROOT" >&2; exit 1; }

if ! TOML_PY="$(tomllib_python)"; then
  echo "skip - every check: $TOML_PY"
  exit 0
fi

# Each result line is "ok|<message>", "bad|<message>", or "run|<agent>|<command>"
# for check 4. The agent TOMLs are the arguments, and the tracked text files for
# check 3 arrive in WIRING_TEXTS, one per line, because the program itself is
# the reader's stdin.
RESULTS=$(WIRING_TEXTS="$TEXTS" "$TOML_PY" - "$ROOT" "${TOMLS[@]}" <<'PY'
import os, re, sys, tomllib

root, paths = sys.argv[1], sys.argv[2:]

# --- 1. The hand-back each nudge names. ---
# Check 4 runs each command found here, so it is check 4 that decides whose
# claim the holder guard names.
PARTS = [
    "--if-assignee=",
    "--if-status=in_progress",
    "--status=open",
    '--assignee=""',
    "--unset-metadata gc.session_id",
    "--unset-metadata gc.session_name",
]
nudges, handbacks = {}, {}
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
    whole = [c for c in commands if all(p in c for p in PARTS)]
    if whole:
        handbacks[name] = whole[0]
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
    carries = pool[0] in handbacks
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
texts = [t for t in os.environ.get("WIRING_TEXTS", "").splitlines() if t]
hits, split = [], []
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

# --- 4. The commands the shell runs. ---
for name in sorted(handbacks):
    print("run|%s|%s" % (name, handbacks[name]))
PY
); PY_RC=$?

# harness_init zeroes the tallies, clears GC_* and BEADS_*, and puts the stub gc
# ahead of the test floor on PATH, so it runs before the first result counts.
harness_init

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
# The lines are read back from a checked file, so a loop that reads nothing
# cannot pass for one that found nothing wrong.
RUNS=(); LINES=0
WANT=$(printf '%s\n' "$RESULTS" | grep -c .)
if printf '%s\n' "$RESULTS" > "$TMP/results"; then
  while IFS='|' read -r verdict message; do
    [ -n "$verdict" ] && LINES=$((LINES + 1))
    case "$verdict" in
      ok)  ok "$message" ;;
      bad) bad "$message" ;;
      run) RUNS+=("$message") ;;
      *)   [ -z "$verdict" ] || bad "unreadable result line: $verdict|$message" ;;
    esac
  done < "$TMP/results"
fi
[ "$LINES" -gt 0 ] && [ "$LINES" -eq "$WANT" ] || bad "read back $LINES of the reader's $WANT result lines"

# --- 4. Each nudge's hand-back, run. ---
# The wrapper ahead of the stub gc enforces --if-status and --if-assignee the way
# bd does, where a mismatch writes nothing and exits 13.
mkdir -p "$TMP/guard"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/guard/gc" <<WRAP
if [ "\${1:-} \${2:-}" = "bd update" ]; then
  id="\${3:-}"; has_s=0; want_s=""; has_a=0; want_a=""
  for a in "\$@"; do
    case "\$a" in
      --if-status=*)   has_s=1; want_s="\${a#--if-status=}" ;;
      --if-assignee=*) has_a=1; want_a="\${a#--if-assignee=}" ;;
    esac
  done
  if [ "\$has_s" = 1 ] || [ "\$has_a" = 1 ]; then
    row=\$("$BIN/gc" bd show "\$id" --json)
    cur_s=\$(printf '%s' "\$row" | jq -r '.[0].status // ""')
    cur_a=\$(printf '%s' "\$row" | jq -r '.[0].assignee // ""')
    if { [ "\$has_s" = 1 ] && [ "\$want_s" != "\$cur_s" ]; } || { [ "\$has_a" = 1 ] && [ "\$want_a" != "\$cur_a" ]; }; then
      printf 'Error updating %s: precondition failed: it shows status "%s" and assignee "%s"\n' "\$id" "\$cur_s" "\$cur_a" >&2
      exit 13
    fi
  fi
fi
exec "$BIN/gc" "\$@"
WRAP
chmod +x "$TMP/guard/gc"

POOL="gc-toolkit/gc-toolkit.polecat-codex"
# bead <status> <assignee> <session id> — the bead W1 a hook claim stamped with
# its session pins, on its pool's route.
bead() {
  store "$(jq -nc --arg st "$1" --arg as "$2" --arg sid "$3" --arg pool "$POOL" '
    [{id: "W1", status: $st, assignee: $as, title: "work", notes: "",
      metadata: {"gc.session_id": $sid, "gc.session_name": ("gc-toolkit__polecat-codex-" + $sid),
                 "gc.routed_to": $pool}}]')"
}
# claim — what W1 shows: status, assignee, both pins and the route.
claim() { printf '%s|%s|%s|%s|%s' "$(bstatus W1)" "$(bassignee W1)" "$(meta W1 gc.session_id)" "$(meta W1 gc.session_name)" "$(meta W1 gc.routed_to)"; }
RELEASED="open||<absent>|<absent>|$POOL"
# run <shell> <command> [VAR=val ...] — the command in a fresh <shell> that reads
# no startup file and whose only session identity is the assignments. Prints
# the exit status.
run() {
  local sh="$1" cmd="$2"; shift 2
  local rc=0
  case "$sh" in
    bash) env -u BASH_ENV -u GC_ALIAS -u GC_SESSION_ID PATH="$TMP/guard:$PATH" "$@" bash --norc --noprofile -c "$cmd" >/dev/null 2>&1 || rc=$? ;;
    zsh)  env -u GC_ALIAS -u GC_SESSION_ID PATH="$TMP/guard:$PATH" "$@" zsh -f -c "$cmd" >/dev/null 2>&1 || rc=$? ;;
  esac
  printf '%s' "$rc"
}

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then SHELLS+=(zsh); else echo "skip - check 4 in zsh: zsh is not installed"; fi
[ "${#RUNS[@]}" -gt 0 ] || bad "no nudge names a whole hand-back command, so check 4 ran nothing"
for entry in ${RUNS[@]+"${RUNS[@]}"}; do
  agent="${entry%%|*}"
  cmd="${entry#*|}"
  cmd="${cmd//<bead>/W1}"
  for sh in "${SHELLS[@]}"; do
    at="$agent in $sh"
    bead in_progress gc-toolkit/gc-toolkit.hicks hq-wisp-o8f8w
    rc=$(run "$sh" "$cmd" GC_ALIAS=gc-toolkit/gc-toolkit.hicks GC_SESSION_ID=hq-wisp-o8f8w)
    eq "$rc|$(claim)" "0|$RELEASED" "$at: a worker with an alias hands back the bead gc hook claimed under its alias"

    bead in_progress hq-wisp-me hq-wisp-me
    rc=$(run "$sh" "$cmd" GC_SESSION_ID=hq-wisp-me)
    eq "$rc|$(claim)" "0|$RELEASED" "$at: a worker with no alias hands back the bead claimed under its session id"

    bead in_progress hq-wisp-me hq-wisp-me
    rc=$(run "$sh" "$cmd" GC_ALIAS= GC_SESSION_ID=hq-wisp-me)
    eq "$rc|$(claim)" "0|$RELEASED" "$at: an empty alias counts as none, so the session id is the guard"

    bead in_progress hq-wisp-other hq-wisp-other
    rc=$(run "$sh" "$cmd" GC_SESSION_ID=hq-wisp-me)
    eq "$rc|$(claim)" "13|in_progress|hq-wisp-other|hq-wisp-other|gc-toolkit__polecat-codex-hq-wisp-other|$POOL" \
      "$at: a bead another session holds is left as it was"

    bead in_progress gc-toolkit/gc-toolkit.ripley hq-wisp-other
    rc=$(run "$sh" "$cmd" GC_ALIAS=gc-toolkit/gc-toolkit.hicks GC_SESSION_ID=hq-wisp-o8f8w)
    eq "$rc|$(claim)" "13|in_progress|gc-toolkit/gc-toolkit.ripley|hq-wisp-other|gc-toolkit__polecat-codex-hq-wisp-other|$POOL" \
      "$at: a bead another alias holds is left as it was"

    bead closed hq-wisp-me hq-wisp-me
    rc=$(run "$sh" "$cmd" GC_SESSION_ID=hq-wisp-me)
    eq "$rc|$(claim)" "13|closed|hq-wisp-me|hq-wisp-me|gc-toolkit__polecat-codex-hq-wisp-me|$POOL" \
      "$at: a bead the worker already closed stays closed"
  done
done

echo
echo "pool-nudge-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
