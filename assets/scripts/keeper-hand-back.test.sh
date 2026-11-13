#!/usr/bin/env bash
# Hermetic test: the gascity-keeper sub-pack hands a bead back to its owner by
# an assignment and its notice, or asks a person through a human gate, and
# never writes a route.
#
# mol-upstream-gc-sync's three stops are extracted from the formula as Python's
# tomllib decodes it, rendered as a pour renders them, and run against a stub gc
# and a stub decline.sh. With no keeper named, or `human`, a stop declines
# through a human gate the bead waits on, re-slung through the sync, and assigns
# nothing. With a keeper named, it assigns the bead to the keeper, mails the
# keeper with --notify, which requests its turn, and drains. No stop writes a
# route or a headline. mol-upstream-gc-pr-prep's hand-backs are read in its
# text: no write of gc.routed_to, and every mail to the keeper requests its
# turn. formula-git-rig.test.sh runs pr-prep's workspace-setup hand-back. No
# live city, store or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SYNC_TOML="$ROOT/packs/gascity-keeper/formulas/mol-upstream-gc-sync.toml"
PRPREP_TOML="$ROOT/packs/gascity-keeper/formulas/mol-upstream-gc-pr-prep.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-keeper-hand-back-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # ok, bad, eq, has, hasnt and tomllib_python
for f in "$SYNC_TOML" "$PRPREP_TOML"; do
  [ -s "$f" ] || { echo "formula not found: $f" >&2; exit 1; }
done
if ! PY="$(tomllib_python)"; then
  echo "skip - keeper hand-backs: $PY"
  exit 0
fi

# step_block <toml> <step id> <text> : the step's one bash block that holds
# <text>, as the agent reads it. It fails unless exactly one block does.
cat > "$TMP/block.py" <<'PY'
import re
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    formula = tomllib.load(f)
steps = [s for s in formula.get("steps") or [] if s.get("id") == sys.argv[2]]
if len(steps) != 1:
    sys.exit(f"{sys.argv[2]}: {len(steps)} steps by that id")
blocks = [b for b in re.findall(r"```bash\n(.*?)```", steps[0].get("description", ""), re.S)
          if sys.argv[3] in b]
if len(blocks) != 1:
    sys.exit(f"{sys.argv[2]}: {len(blocks)} bash blocks hold {sys.argv[3]!r}")
sys.stdout.write(blocks[0])
PY
step_block() { "$PY" "$TMP/block.py" "$@"; }

# The stub gc logs each call on one line, answers the pack's scripts-dir with
# the stub pack, and succeeds. The stub pack's decline.sh logs its call, and its
# rig-root.sh names a rig, so the survey's run reaches the detector.
BIN="$TMP/bin"; PACK="$TMP/pack"; mkdir -p "$BIN" "$PACK"
cat > "$BIN/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1 $2" = "gc-toolkit scripts-dir" ]; then printf '%s\n' "$STUB_PACK"; exit 0; fi
printf '%s\n' "$*" | tr '\n' ' ' >> "$LOG"; echo >> "$LOG"
exit 0
GC
cat > "$PACK/decline.sh" <<'SH'
#!/usr/bin/env bash
printf 'decline %s\n' "$*" | tr '\n' ' ' >> "$LOG"; echo >> "$LOG"
SH
cat > "$PACK/rig-root.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$STUB_RIG"
SH
chmod +x "$BIN/gc" "$PACK/decline.sh" "$PACK/rig-root.sh"
# A detector that fails, with a line on each stream, and one no one may run.
printf '#!/usr/bin/env bash\necho "report so far"\necho "detector broke" >&2\nexit 3\n' > "$TMP/failing-detector.sh"
chmod +x "$TMP/failing-detector.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/not-executable.sh"

KEEPER="gascity/gascity-keeper.keeper"
# render <block file> <owner> <detector> : the block as a pour renders it.
render() {
  sed -e 's|{{issue}}|tk-iss|g' -e "s|{{notify_recipient}}|$2|g" -e 's|{{binding_prefix}}|gc-toolkit.|g' \
      -e 's|{{upstream_rig}}|gascity|g' -e 's|{{upstream_ref}}|origin/main|g' -e 's|{{with_diff}}|0|g' \
      -e "s|{{sync_script}}|$3|g" "$1"
}
# stop <label> <step> <text> <owner> <detector> : run that stop's block; sets LOGTEXT.
stop() {
  local d="$TMP/$1"
  mkdir -p "$d/cwd"
  if ! step_block "$SYNC_TOML" "$2" "$3" > "$d/block.tmpl"; then
    bad "$1: the $2 step holds the block"; LOGTEXT=""; return 0
  fi
  render "$d/block.tmpl" "$4" "$5" > "$d/block.sh"
  case "$(cat "$d/block.sh")" in
    *'{{'*) bad "$1: the block renders with every placeholder filled" ;;
    *)      ok "$1: the block renders with every placeholder filled" ;;
  esac
  : > "$d/gc.log"
  ( cd "$d/cwd" && env PATH="$BIN:$PATH" LOG="$d/gc.log" STUB_PACK="$PACK" STUB_RIG="$d/rig" bash "$d/block.sh" ) >"$d/out" 2>&1
  LOGTEXT="$(cat "$d/gc.log")"
}

# Each stop, by the step that holds it, the text that finds its block, the key
# its gate asks under, and the detector it runs against.
STOPS="workspace-setup|case \"{{notify_recipient}}\"|upstream-gc-sync-no-rig|$TMP/failing-detector.sh
survey|if [ ! -x \"{{sync_script}}\" ]|upstream-gc-sync-no-detector|$TMP/not-executable.sh
survey|> \"\$REPORT_FILE\" 2> \"\$ERR_FILE\"|upstream-gc-sync-detector-failed|$TMP/failing-detector.sh"

echo "── mol-upstream-gc-sync: a stop with no keeper named asks a person ──"
while IFS='|' read -r step text key detector; do
  for owner in "" human; do
    label="sync-$key-${owner:-unnamed}"
    stop "$label" "$step" "$text" "$owner" "$detector"
    has "$LOGTEXT" "decline --step mol-upstream-gc-sync.$step " "$label: the stop declines its run at the step it holds"
    has "$LOGTEXT" " --subject tk-iss --key $key --message " "$label: …through a human gate on the bead, under $key"
    has "$LOGTEXT" " --formula mol-upstream-gc-sync" "$label: …which the bead waits on, re-slung through the sync once it clears"
    hasnt "$LOGTEXT" "--assignee" "$label: no write assigns the bead to anyone"
    hasnt "$LOGTEXT" "mail send" "$label: nobody is mailed, since the gate asks"
  done
done <<< "$STOPS"

echo "── mol-upstream-gc-sync: a stop with a keeper named hands it the bead ──"
while IFS='|' read -r step text key detector; do
  label="sync-$key-keeper"
  stop "$label" "$step" "$text" "$KEEPER" "$detector"
  has "$LOGTEXT" "--status=open --assignee=$KEEPER" "$label: the bead goes back open, assigned to the keeper"
  has "$LOGTEXT" "--set-metadata aborted_at=$step" "$label: …naming the step it stopped at"
  has "$LOGTEXT" "mail send $KEEPER --notify -s upstream-gc-sync: tk-iss stopped at $step" \
    "$label: the keeper is mailed with --notify, the notice its assignment owes"
  has "$LOGTEXT" "runtime drain-ack" "$label: …and the session drains"
  hasnt "$LOGTEXT" "decline " "$label: no gate asks a person"
done <<< "$STOPS"

echo "── mol-upstream-gc-sync: the detector's failure reaches either owner ──"
for owner in "" "$KEEPER"; do
  label="sync-detector-failed-${owner:+keeper}"
  stop "$label" survey "> \"\$REPORT_FILE\" 2> \"\$ERR_FILE\"" "$owner" "$TMP/failing-detector.sh"
  eq "$(head -n 1 <<< "$LOGTEXT" | cut -d' ' -f1-6)" "bd update tk-iss --set-metadata aborted_at=survey --append-notes" \
    "$label: the failure goes to the bead's notes before the hand-back"
  has "$LOGTEXT" "detector broke" "$label: …carrying the detector's stderr"
done

echo "── the keeper pack writes no route ──"
for f in "$SYNC_TOML" "$PRPREP_TOML"; do
  eq "$(grep -c 'gc\.routed_to' "$f" || true)" 0 "${f##*/}: no step writes gc.routed_to"
  eq "$(grep -c 'takeaway' "$f" || true)" 0 "${f##*/}: no step parks the bead on a headline"
done

echo "── mol-upstream-gc-pr-prep: every mail to the keeper is its notice ──"
MAILS=$(grep -c 'gc mail send "\$REQUESTING_KEEPER"' "$PRPREP_TOML" || true)
[ "$MAILS" -ge 5 ] && ok "pr-prep: each hand-back mails the keeper ($MAILS mails)" || bad "pr-prep: each hand-back mails the keeper (found $MAILS)"
eq "$(grep 'gc mail send "\$REQUESTING_KEEPER"' "$PRPREP_TOML" | grep -cv -- ' --notify ' || true)" 0 \
  "pr-prep: every mail to the keeper requests its turn"
eq "$(grep -c 'gc session nudge' "$PRPREP_TOML" || true)" 0 "pr-prep: the hand-back notifies by mail, not by a nudge"

echo "-----"
echo "keeper-hand-back: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
