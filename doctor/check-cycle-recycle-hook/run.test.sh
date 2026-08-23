#!/usr/bin/env bash
# Hermetic test for doctor/check-cycle-recycle-hook/run.sh, focused on the
# DOCTRINE assertions added by tk-17wggn — that `heartbeat-no-consent-ui` is
# injected on the same three roles the hook recycles, and that the fragment
# still claims them.
#
# THE HOLE IT CLOSES. The overlay half of this check counts occurrences of a
# literal wiring line and accepts >= 3, which is honest for `overlay_dir`: that
# string appears nowhere in pack.toml except the three patches. The fragment
# NAME does not have that property — pack.toml's header comment lists every
# doctrine fragment the pack ships, `heartbeat-no-consent-ui` among them — so a
# count of 3 was reachable with only two agents wired, which is exactly the
# state that shipped for three months (case 7 below pins this). The assertion
# therefore resolves each [[patches.agent]] block by name and reads its own
# array, and this test is what keeps that from being quietly re-simplified
# back into a count.
#
# Every case mutates a throwaway copy of the SHIPPED pack artifacts, so the
# fixtures cannot drift from what the pack actually ships. No live city, Dolt,
# or network.
#
# Covered:
#   (1)  shipped pack satisfies every assertion -> OK (exit 0)
#   (2)  refinery injection removed -> ERROR naming refinery
#   (3)  witness injection removed -> ERROR naming witness
#   (4)  deacon injection removed -> ERROR naming deacon
#   (5)  all three removed -> ONE error naming all three (not three errors)
#   (6)  refinery patch block deleted outright -> ERROR naming refinery, and
#        saying the block is missing rather than reporting a clean list
#   (7)  refinery injection removed, yet `grep -c` on pack.toml still returns
#        >= 3 -> the count form would pass here; the per-agent form must not
#   (8)  the injection present but COMMENTED OUT inside the array -> ERROR
#        (the comment stripper is load-bearing: a commented entry injects
#        nothing, and pack.toml really does carry prose inside these brackets)
#   (9)  a fragment name quoted inside an array COMMENT is not read as an entry
#   (10) fragment file deleted -> ERROR
#   (11) fragment file empty -> ERROR
#   (12) fragment stops naming refinery -> ERROR (the closing sentence is what
#        a deacon or witness reads to conclude the refinery is covered)
#   (13) fragment loses AskUserQuestion -> ERROR
#   (14) hook self-gate line removed -> ERROR (pre-existing assertion, still
#        wired after the helpers were added)
#   (15) overlay_dir COMMENTED OUT on one patch -> ERROR, though the literal
#        text survives and the superseded count form still reads 3 (15b covers
#        the outright deletion the count form did catch)
#   (16) hook script missing -> ERROR (ditto)
#   (17) settings.json missing the "Stop" registration -> ERROR (ditto)
#
# Cases 14-17 are not redundant with the check's own history: the doctrine
# assertions introduced two awk helpers and a second `if` arm ahead of the
# summary, and a broken helper that aborts the script early would take the
# original assertions down with it while still exiting non-zero for the
# doctrine cases. They are the control that says the old half still fires.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { if grep -qF -- "$1" "$2"; then ok "$3"; else bad "$3 (missing '$1' in: $(cat "$2"))"; fi; }
hasnt() { if grep -qF -- "$1" "$2"; then bad "$3 (unexpected '$1' in: $(cat "$2"))"; else ok "$3"; fi; }

# pack <name> — throwaway GC_PACK_DIR holding pristine copies of the shipped
# pack.toml, doctrine fragment, and cycle-recycle overlay. Echoes the dir.
pack() {
    local d="$TMP/$1"
    mkdir -p "$d/template-fragments"
    cp "$ROOT/pack.toml" "$d/pack.toml"
    cp "$ROOT/template-fragments/heartbeat-no-consent-ui.template.md" \
       "$d/template-fragments/heartbeat-no-consent-ui.template.md"
    cp -r "$ROOT/overlays" "$d/overlays"
    echo "$d"
}
frag() { echo "$1/template-fragments/heartbeat-no-consent-ui.template.md"; }
hook() { echo "$1/overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh"; }

run_check() { # $1 = pack dir -> echoes exit code; output lands in <pack>/out
    GC_PACK_DIR="$1" bash "$SCRIPT" > "$1/out" 2>&1
    echo $?
}

# Rewrite pack.toml in place, applying <action> only inside the [[patches.agent]]
# block whose name is <role>. Scoping is load-bearing: the injection line is
# byte-identical in three blocks, so an unscoped sed mutates all of them and a
# case that then "passes" is passing on another block's fallout.
#   drop     — delete the injection line
#   comment  — turn it into a TOML comment (still present as text, injects nothing)
#   quote    — leave it, and add a comment inside the array that quotes another
#              fragment name (case 9's decoy)
in_block() { # $1 = pack.toml, $2 = role, $3 = action
    local f="$1" tmp; tmp="$(mktemp)"
    awk -v role="$2" -v action="$3" '
        /^[[:space:]]*name[[:space:]]*=[[:space:]]*"/ {
            cur = $0; sub(/^[^"]*"/, "", cur); sub(/".*$/, "", cur)
        }
        {
            if (cur == role && $0 ~ /^[[:space:]]*"heartbeat-no-consent-ui",[[:space:]]*$/) {
                if (action == "drop")    next
                if (action == "comment") { print "    # \"heartbeat-no-consent-ui\","; next }
                if (action == "quote")   { print "    # a decoy naming \"canonical-self-rename\" inside the array"; print; next }
            }
            print
        }
    ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# Delete the whole [[patches.agent]] block for <role>.
drop_block() { # $1 = pack.toml, $2 = role
    local f="$1" tmp; tmp="$(mktemp)"
    awk -v role="$2" '
        /^\[\[patches\.agent\]\][[:space:]]*$/ {
            if (buf != "" && !kill) printf "%s", buf
            buf = $0 "\n"; inb = 1; kill = 0; next
        }
        /^\[/ && !/^\[\[patches\.agent\]\]/ {
            if (inb) { if (!kill) printf "%s", buf; buf = ""; inb = 0; kill = 0 }
            print; next
        }
        inb {
            buf = buf $0 "\n"
            if ($0 ~ ("^[[:space:]]*name[[:space:]]*=[[:space:]]*\"" role "\"[[:space:]]*$")) kill = 1
            next
        }
        { print }
        END { if (inb && !kill) printf "%s", buf }
    ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# ---------------------------------------------------------------- (1) shipped
d="$(pack shipped)"
eq "$(run_check "$d")" 0 "(1) shipped pack passes every assertion"
has "all three read heartbeat-no-consent-ui" "$d/out" "(1) summary reports the doctrine half too"

# ------------------------------------------------- (2)-(4) one role un-wired
for role in refinery witness deacon; do
    d="$(pack "drop-$role")"; in_block "$d/pack.toml" "$role" drop
    eq "$(run_check "$d")" 2 "($role) dropping the injection is an ERROR"
    has "does not inject heartbeat-no-consent-ui on: $role" "$d/out" "($role) the finding names the un-wired role"
done

# --------------------------------------------------------- (5) all three gone
d="$(pack drop-all)"
for role in refinery witness deacon; do in_block "$d/pack.toml" "$role" drop; done
eq "$(run_check "$d")" 2 "(5) dropping all three is an ERROR"
has "on: witness deacon refinery" "$d/out" "(5) one finding names all three roles in hook order"
eq "$(grep -c 'does not inject heartbeat-no-consent-ui' "$d/out")" 1 "(5) reported once, not once per role"

# ---------------------------------------------------- (6) patch block deleted
d="$(pack no-block)"; drop_block "$d/pack.toml" refinery
eq "$(run_check "$d")" 2 "(6) deleting the refinery patch block is an ERROR"
has "no [[patches.agent]] block for: refinery" "$d/out" "(6) the finding says the block is missing, not the entry"

# ------------------------------------- (7) the count form would have passed
d="$(pack count-trap)"; in_block "$d/pack.toml" refinery drop
n="$(grep -c 'heartbeat-no-consent-ui' "$d/pack.toml")"
if [ "${n:-0}" -ge 3 ]; then
    ok "(7) pack.toml still mentions the fragment ${n}x with refinery un-wired — a count>=3 assertion would pass"
else
    bad "(7) expected >=3 mentions with refinery un-wired, got ${n:-0}; the count-trap this assertion guards no longer exists — re-derive before simplifying the check"
fi
eq "$(run_check "$d")" 2 "(7) the per-agent assertion fails where a count would not"

# ------------------------------------------------ (8) injection commented out
d="$(pack commented)"; in_block "$d/pack.toml" refinery comment
has '# "heartbeat-no-consent-ui",' "$d/pack.toml" "(8) fixture really does still contain the name as text"
eq "$(run_check "$d")" 2 "(8) a commented-out entry injects nothing and is an ERROR"
has "does not inject heartbeat-no-consent-ui on: refinery" "$d/out" "(8) the finding names refinery"

# -------------------------------------------- (9) quoted name inside a comment
d="$(pack decoy)"; in_block "$d/pack.toml" refinery quote
eq "$(run_check "$d")" 0 "(9) a fragment name quoted inside an array comment does not break the read"

# ------------------------------------------------------- (10)-(13) the fragment
d="$(pack no-frag)"; rm "$(frag "$d")"
eq "$(run_check "$d")" 2 "(10) deleting the fragment is an ERROR"
has "missing or empty doctrine fragment" "$d/out" "(10) the finding names the fragment file"

d="$(pack empty-frag)"; : > "$(frag "$d")"
eq "$(run_check "$d")" 2 "(11) an empty fragment is an ERROR"

d="$(pack unclaimed)"
# shellcheck disable=SC2016  # the backticks are literal markdown in the fragment
sed -i 's/(witness, deacon, refinery)/(witness, deacon)/; s/`witness | deacon | refinery`/`witness | deacon`/' "$(frag "$d")"
hasnt "refinery" "$(frag "$d")" "(12) fixture really did remove every mention of refinery"
eq "$(run_check "$d")" 2 "(12) a fragment that stops naming an injected role is an ERROR"
has "does not name refinery among the heartbeat agents it governs" "$d/out" "(12) the finding names the unclaimed role"

d="$(pack no-tool)"; sed -i 's/AskUserQuestion/AskTheOperator/g' "$(frag "$d")"
eq "$(run_check "$d")" 2 "(13) a fragment that stops naming AskUserQuestion is an ERROR"
has "does not name AskUserQuestion" "$d/out" "(13) the finding names the tool"

# -------------------------------- (14)-(17) the pre-existing overlay assertions
d="$(pack no-gate)"; sed -i 's/^  witness | deacon | refinery) : ;;/  patrol) : ;;/' "$(hook "$d")"
eq "$(run_check "$d")" 2 "(14) hook losing its patrol-role self-gate is still an ERROR"
has "does not self-gate to witness/deacon/refinery roles" "$d/out" "(14) the original finding still renders"

# The FIRST overlay_dir in pack.toml belongs to the deacon patch. Commenting it
# out (rather than deleting it) is the mutation the old count form could not
# see: the literal text survives, so `grep -c` still returned 3 and the check
# stayed green with the deacon un-wired.
d="$(pack commented-overlay)"
python3 - "$d/pack.toml" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
old = 'overlay_dir = "overlays/cycle-recycle"'
open(p, 'w', encoding='utf-8').write(s.replace(old, '# ' + old, 1))
PY
eq "$(grep -c 'overlay_dir = "overlays/cycle-recycle"' "$d/pack.toml")" 3 "(15) fixture still counts 3 — the count form would pass"
eq "$(run_check "$d")" 2 "(15) a commented-out overlay_dir is an ERROR"
has "does not wire overlay_dir=overlays/cycle-recycle on: deacon" "$d/out" "(15) the finding names the un-wired role"

d="$(pack deleted-overlay)"
sed -i '0,\|^overlay_dir = "overlays/cycle-recycle"$|{/^overlay_dir = "overlays\/cycle-recycle"$/d}' "$d/pack.toml"
eq "$(grep -c 'overlay_dir = "overlays/cycle-recycle"' "$d/pack.toml")" 2 "(15b) fixture really deleted one wiring line"
eq "$(run_check "$d")" 2 "(15b) deleting an overlay_dir is an ERROR"

d="$(pack no-hook)"; rm "$(hook "$d")"
eq "$(run_check "$d")" 2 "(16) a missing hook script is still an ERROR"
has "missing or empty hook script" "$d/out" "(16) the original finding still renders"

d="$(pack no-stop)"
sed -i 's/"Stop"/"NotStop"/' "$d/overlays/cycle-recycle/.claude/settings.json"
eq "$(run_check "$d")" 2 "(17) settings.json losing its Stop registration is still an ERROR"
has 'does not register a "Stop" hook' "$d/out" "(17) the original finding still renders"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
