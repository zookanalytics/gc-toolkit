#!/usr/bin/env bash
# Hermetic test for reconcile-graduated-convoys.sh (system-auto convoy
# graduation, the convoy half of close-on-land).
#
# Stubs `gc` (convoy list + rig convoy ledger + bead show/update) on PATH. No
# live city, Dolt, or network. Covers the graduation gate end to end:
#   (1) owned + integration/* + ALL members closed -> convoy bead assigned to
#       the refinery with branch=integration/<id>, target=main, merge_strategy=mr
#       (a human-approved PR gates integration->main, NOT a direct FF)
#   (2) THE INTERLOCK: a half-built owned convoy (a member still open) is NOT
#       graduated — close-on-land makes "all closed" == "all merged", so this
#       never fires on a partial integration branch
#   (3) owned-only scope: a non-owned auto-convoy (per-sling bundle) is untouched
#   (4) rig scope: an owned+complete convoy in ANOTHER rig is NOT graduated
#   (5) empty guard: an owned convoy with no members (0/0) is NOT graduated
#   (6) target guard: an owned convoy whose target is not integration/* is skipped
#   (7) idempotency: an owned+complete convoy already carrying metadata.branch
#       (graduation already initiated / gating) is NOT re-assigned
#   (8) convergence: a second pass does not re-graduate what the first assigned
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-graduated-convoys.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# Convoy list (gc convoy list source): id|owned|target|closed|total
#   tk-ready  owned, integration/*, 3/3  -> GRADUATE (in this rig)
#   tk-half   owned, integration/*, 1/2  -> interlock skip (member still open)
#   tk-empty  owned, integration/*, 0/0  -> empty-convoy skip
#   tk-nonint owned, target=main,   2/2  -> non-integration target skip
#   tk-auto   NOT owned, no target, 1/1  -> owned-only skip (per-sling bundle)
#   tk-grad   owned, integration/*, 2/2  -> idempotency skip (branch already set)
#   gc-other  owned, integration/*, 3/3  -> rig-scope skip (another rig's ledger)
cat > "$TMP/convoys" <<'C'
tk-ready|true|integration/ready|3|3
tk-half|true|integration/half|1|2
tk-empty|true|integration/empty|0|0
tk-nonint|true|main|2|2
tk-auto|false||1|1
tk-grad|true|integration/grad|2|2
gc-other|true|integration/other|3|3
C

# This rig's convoy ledger (rig-scoped `gc bd list --type=convoy`): all tk-* but
# NOT gc-other. The intersection with the city-wide convoy list is what scopes
# graduation to this rig.
cat > "$TMP/rigconvoys" <<'R'
tk-ready
tk-half
tk-empty
tk-nonint
tk-auto
tk-grad
R

# Per-convoy bead metadata.branch (gc bd show source): id|branch
# Only tk-grad is already mid-graduation (branch set) — the idempotency case.
cat > "$TMP/meta" <<'M'
tk-grad|integration/grad
M

: > "$TMP/assigned"

# --- gc stub: convoy list / bd list (convoy ledger) / bd show / bd update. -----
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "convoy list")
    rows=""
    while IFS='|' read -r id owned target closed total; do
      [ -n "$id" ] || continue
      obj=$(jq -n --arg id "$id" --argjson owned "$owned" --arg target "$target" \
                  --argjson closed "$closed" --argjson total "$total" \
        '{id:$id, owned:$owned, fields:{target:$target}, progress:{closed:$closed, total:$total}}')
      if [ -z "$rows" ]; then rows="$obj"; else rows="$rows,$obj"; fi
    done < "$FAKE_CONVOYS"
    printf '{"convoys":[%s],"ok":true}\n' "$rows"
    exit 0 ;;
esac
[ "$1" = "bd" ] || exit 0
case "$2" in
  list)
    out=""
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      obj=$(printf '{"id":"%s"}' "$id")
      if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
    done < "$FAKE_RIG_CONVOYS"
    printf '[%s]\n' "$out" ;;
  show)
    id="$3"
    branch=$(grep "^$id|" "$FAKE_META" 2>/dev/null | head -1 | cut -d'|' -f2)
    jq -n --arg b "$branch" '[{metadata:{branch:(if $b=="" then null else $b end)}}]' ;;
  update)
    id="$3"; shift 3
    printf '%s\t%s\n' "$id" "$*" >> "$FAKE_ASSIGNED" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export GC_AGENT="gc-toolkit/gc-toolkit.refinery"
export FAKE_CONVOYS="$TMP/convoys" FAKE_RIG_CONVOYS="$TMP/rigconvoys" \
       FAKE_META="$TMP/meta" FAKE_ASSIGNED="$TMP/assigned"

assigned()     { grep -q "^$1	" "$TMP/assigned" 2>/dev/null; }
assigned_arg() { grep "^$1	" "$TMP/assigned" 2>/dev/null | grep -q -- "$2"; }

# --- Run 1: the graduation gate. ---------------------------------------------
OUT1="$(bash "$SCRIPT" --target main)"

assigned tk-ready && ok "(1) complete owned integration convoy -> graduated" \
                  || bad "(1) complete owned integration convoy -> graduated"
assigned_arg tk-ready 'branch=integration/ready' \
  && ok "(1) graduation sets branch=<integration branch> (source)" \
  || bad "(1) graduation sets branch=<integration branch>"
assigned_arg tk-ready 'target=main' \
  && ok "(1) graduation sets target=main (destination)" \
  || bad "(1) graduation sets target=main"
assigned_arg tk-ready 'merge_strategy=mr' \
  && ok "(1) integration->main is a human-approved PR (merge_strategy=mr)" \
  || bad "(1) integration->main must be mr (human-approved PR), never direct FF"
assigned_arg tk-ready "assignee=$GC_AGENT" \
  && ok "(1) convoy bead assigned to the refinery agent" \
  || bad "(1) convoy bead assigned to the refinery agent"

assigned tk-half  && bad "(2) interlock: half-built convoy must NOT graduate" \
                  || ok "(2) interlock: half-built convoy (1/2) not graduated"
assigned tk-auto  && bad "(3) owned-only: non-owned auto-convoy must NOT graduate" \
                  || ok "(3) owned-only: non-owned auto-convoy untouched"
assigned gc-other && bad "(4) rig-scope: another rig's convoy must NOT graduate" \
                  || ok "(4) rig-scope: other-rig convoy not graduated"
assigned tk-empty && bad "(5) empty convoy (0/0) must NOT graduate" \
                  || ok "(5) empty convoy (0/0) not graduated"
assigned tk-nonint && bad "(6) non-integration target must NOT graduate" \
                   || ok "(6) non-integration target (main) not graduated"
assigned tk-grad  && bad "(7) idempotency: already-graduating convoy must NOT re-assign" \
                  || ok "(7) idempotency: convoy with branch set not re-assigned"

eq "$(wc -l < "$TMP/assigned" | tr -d ' ')" "1" "(1) exactly one convoy graduated this pass"
printf '%s\n' "$OUT1" | grep -q "1 graduating" \
  && ok "run 1 summary reports 1 graduating" \
  || bad "run 1 summary (got: $OUT1)"

# --- Run 2: convergence. tk-ready now carries branch (assignment persisted) ----
# so the second pass must not re-graduate it.
printf 'tk-ready|integration/ready\n' >> "$TMP/meta"
bash "$SCRIPT" --target main >/dev/null
eq "$(grep -c '^tk-ready	' "$TMP/assigned")" "1" "(8) graduated convoy not re-assigned on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
