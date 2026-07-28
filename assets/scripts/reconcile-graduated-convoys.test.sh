#!/usr/bin/env bash
# Hermetic test for reconcile-graduated-convoys.sh (system-auto convoy
# graduation, the convoy half of close-on-land).
#
# Stubs `gc` (convoy list + rig convoy ledger + branch probe + bead show/update)
# on PATH. No live city, Dolt, or network. Covers the graduation gate end to end:
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
#   (8) convergence (run 2): a second pass does not re-graduate what the first
#       assigned
# and the operator gates — graduation makes the convoy actionable mr-mode work,
# so the next refinery pass REBASES the integration branch and lands it, which is
# exactly the work an operator holds a graduation to prevent:
#   (9)  merge_hold on the convoy bead itself -> HELD, not graduated
#   (10) rebase_hold on the convoy bead itself -> HELD (a hold on landing is
#        necessarily a hold on rewriting the branch underneath it)
#   (11) THE OBSERVED FAILURE (gc-8g41r / gc-1g2p1, 2026-06-30): the hold lives on
#        a SEPARATE bead naming the same integration branch, and that bead is
#        BLOCKED — the standard operator move. This case also pins LIVE_STATUSES:
#        the stub honors --status, so an open-only probe cannot see the blocked
#        holder and the convoy graduates straight past the gate.
#   (12) an UNHELD live bead already owning the branch -> not graduated (a second
#        assignment would duplicate its PR)
#   (13) FAIL CLOSED, four ways: a probe that FAILS WITH OUTPUT reads as "nobody
#        holds this branch" and graduates past the gate. Each shape defeats every
#        guard but one, so each pins a different guard and none can be deleted
#        without a red test: a JSON error object (the observed shape), `[]` with a
#        non-zero exit (pins the exit-status check), an array of non-objects (pins
#        the projection's status), and an id-keyed envelope whose values are
#        bead-shaped (pins the array type check — the projection SUCCEEDS on it).
#        Fail-closed is per convoy: the ungated convoys in the same pass still
#        graduate.
#   (15) truthiness: an explicit off-spelling (merge_hold=false) does NOT hold
#   (16) marker TYPE: a hold stored as a JSON boolean rather than a string still
#        holds — `ascii_downcase` aborts the jq program on a boolean, and that
#        error is discarded, so an uncast comparison drops the veto silently.
#        Boolean `false` still reads as off.
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
#   tk-ready     owned, integration/*, 3/3  -> GRADUATE (in this rig)
#   tk-half      owned, integration/*, 1/2  -> interlock skip (member still open)
#   tk-empty     owned, integration/*, 0/0  -> empty-convoy skip
#   tk-nonint    owned, target=main,   2/2  -> non-integration target skip
#   tk-auto      NOT owned, no target, 1/1  -> owned-only skip (per-sling bundle)
#   tk-grad      owned, integration/*, 2/2  -> idempotency skip (branch already set)
#   gc-other     owned, integration/*, 3/3  -> rig-scope skip (another rig's ledger)
#   tk-mhold     owned, integration/*, 2/2  -> operator gate: merge_hold on convoy
#   tk-rhold     owned, integration/*, 2/2  -> operator gate: rebase_hold on convoy
#   tk-sib       owned, integration/*, 2/2  -> operator gate: held SIBLING bead
#   tk-dup       owned, integration/*, 2/2  -> unheld owner already on the branch
#   tk-probefail owned, integration/*, 2/2  -> probe error object -> fail closed
#   tk-probeerr  owned, integration/*, 2/2  -> probe '[]' + exit 1 -> fail closed
#   tk-probebad  owned, integration/*, 2/2  -> probe [1,2] -> fail closed
#   tk-probemap  owned, integration/*, 2/2  -> probe id-keyed object -> fail closed
#   tk-boolhold  owned, integration/*, 2/2  -> sibling hold is a JSON boolean
#   tk-boolfree  owned, integration/*, 2/2  -> sibling hold is boolean false (off)
#   tk-offspell  owned, integration/*, 2/2  -> GRADUATE (merge_hold=false is off)
cat > "$TMP/convoys" <<'C'
tk-ready|true|integration/ready|3|3
tk-half|true|integration/half|1|2
tk-empty|true|integration/empty|0|0
tk-nonint|true|main|2|2
tk-auto|false||1|1
tk-grad|true|integration/grad|2|2
gc-other|true|integration/other|3|3
tk-mhold|true|integration/mhold|2|2
tk-rhold|true|integration/rhold|2|2
tk-sib|true|integration/sib|2|2
tk-dup|true|integration/dup|2|2
tk-probefail|true|integration/probefail|2|2
tk-probeerr|true|integration/probeerr|2|2
tk-probebad|true|integration/probebad|2|2
tk-probemap|true|integration/probemap|2|2
tk-boolhold|true|integration/boolhold|2|2
tk-boolfree|true|integration/boolfree|2|2
tk-offspell|true|integration/offspell|2|2
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
tk-mhold
tk-rhold
tk-sib
tk-dup
tk-probefail
tk-probeerr
tk-probebad
tk-probemap
tk-boolhold
tk-boolfree
tk-offspell
R

# Per-convoy bead metadata (gc bd show source): id|branch|merge_hold|rebase_hold
#   tk-grad     — already mid-graduation (branch set): the idempotency case
#   tk-mhold    — operator gate on the convoy itself
#   tk-rhold    — narrower operator gate on the convoy itself
#   tk-offspell — marker present but explicitly OFF: must not hold
cat > "$TMP/meta" <<'M'
tk-grad|integration/grad||
tk-mhold||true|
tk-rhold|||true
tk-offspell||false|
M

# Live beads naming an integration branch (the `gc bd list --metadata-field
# branch=<b>` probe source): branch|id|status|merge_hold|rebase_hold|json
# `json` non-empty emits the two markers as RAW JSON rather than as strings.
#   tk-sibhold  — the observed shape: a held rebase bead for the branch, BLOCKED
#                 by the operator. Invisible to an open-only probe.
#   tk-dupowner — live and unheld: already owns graduating this branch.
#   tk-boolholdsib — the marker is a JSON BOOLEAN, not a string. A writer that
#                 stores metadata as JSON produces this, and it must hold exactly
#                 as "true" does.
#   tk-boolfreesib — the boolean OFF spelling: must NOT hold. It still trips the
#                 unheld-owner veto, so case (16) reads the reason, not the
#                 outcome, to tell the two arms apart.
cat > "$TMP/branchbeads" <<'B'
integration/sib|tk-sibhold|blocked|operator-gated-graduation||
integration/dup|tk-dupowner|open|||
integration/boolhold|tk-boolholdsib|blocked|true|null|1
integration/boolfree|tk-boolfreesib|open|false|null|1
B

: > "$TMP/assigned"

# --- gc stub: convoy list / bd list (convoy ledger + branch probe) / show / update
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
    # Two different `bd list` callers: the rig convoy ledger (--type=convoy) and
    # the branch probe (--metadata-field branch=<b>). Discriminate on the flag,
    # and capture --status so the probe can honor it — a probe that ignored the
    # status filter would make the LIVE_STATUSES case (11) unfalsifiable.
    mfield=""; statuses=""; prev=""
    for a in "$@"; do
      case "$prev" in
        --metadata-field) mfield="$a" ;;
        --status) statuses="$a" ;;
      esac
      case "$a" in
        --metadata-field=*) mfield="${a#--metadata-field=}" ;;
        --status=*) statuses="${a#--status=}" ;;
      esac
      prev="$a"
    done
    if [ -n "$mfield" ]; then
      br="${mfield#branch=}"
      # Injected ledger failures. `gc ... --json` reports its own errors as a
      # non-empty JSON object on stdout, so "did anything come back?" answers YES
      # for a read that wholly failed — and every shape below then yields zero
      # vetoing rows, i.e. reads as "nobody holds this branch". Each shape defeats
      # every guard but one, so each pins a DIFFERENT guard. (`[]` with a zero exit
      # is NOT here: that is the legitimate "nobody holds it" answer, which the
      # graduating convoys already exercise.)
      case "$br" in
        # The observed shape, as `gc bd list` really reports a bad flag: a JSON
        # error OBJECT plus a non-zero exit.
        integration/probefail) printf '{"error":"invalid --metadata-field","schema_version":1}\n'; exit 1 ;;
        # A well-formed EMPTY array with a non-zero exit — the read died after
        # emitting. Isolates the exit-status guard: the payload is exactly the
        # value that legitimately means "nobody holds it", so nothing else can
        # reject it. (An empty-output variant would be caught by the emptiness
        # guard instead, leaving the rc check unpinned.)
        integration/probeerr)  printf '[]\n'; exit 1 ;;
        # An array of non-objects: passes the type guard, then blows up the
        # projection. Isolates the jq-status guard.
        integration/probebad)  printf '[1, 2]\n'; exit 0 ;;
        # The nastiest shape, and the only one the projection cannot catch: an
        # OBJECT whose values are bead-shaped — a --json envelope keyed by id
        # rather than a list. `.[]` iterates an object's values happily, so the
        # projection SUCCEEDS and emits a well-formed row; only "is the payload an
        # array?" rejects it. The row is deliberately the CONVOY'S OWN bead, with
        # no hold markers: it passes the frozen filter and is excluded by the
        # in-flight filter's id check, so the pass would graduate on it and the
        # test cannot go green by accident.
        integration/probemap)
          printf '{"tk-%s": {"id": "tk-%s", "metadata": {"branch": "%s"}}}\n' \
            "${br#integration/}" "${br#integration/}" "$br"; exit 0 ;;
      esac
      out=""
      while IFS='|' read -r fbr fid fstatus fhold frhold fjson; do
        [ -n "$fbr" ] || continue
        [ "$fbr" = "$br" ] || continue
        # Honor --status exactly as the real `bd list` would: a bead whose status
        # is not in the requested list is simply not returned.
        printf '%s' ",$statuses," | grep -qF ",$fstatus," || continue
        if [ -n "$fjson" ]; then
          # Markers as RAW JSON (booleans/null), not strings.
          obj=$(jq -n --arg id "$fid" --arg b "$fbr" --argjson h "$fhold" --argjson r "$frhold" \
            '{id:$id, metadata:{branch:$b, merge_hold:$h, rebase_hold:$r}}')
        else
          obj=$(jq -n --arg id "$fid" --arg b "$fbr" --arg h "$fhold" --arg r "$frhold" \
            '{id:$id, metadata:{branch:$b, merge_hold:$h, rebase_hold:$r}}')
        fi
        if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
      done < "$FAKE_BRANCH_BEADS"
      printf '[%s]\n' "$out"
      exit 0
    fi
    out=""
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      obj=$(printf '{"id":"%s"}' "$id")
      if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
    done < "$FAKE_RIG_CONVOYS"
    printf '[%s]\n' "$out" ;;
  show)
    id="$3"
    row=$(grep "^$id|" "$FAKE_META" 2>/dev/null | head -1)
    branch=$(printf '%s' "$row" | cut -d'|' -f2)
    hold=$(printf '%s' "$row" | cut -d'|' -f3)
    rhold=$(printf '%s' "$row" | cut -d'|' -f4)
    jq -n --arg b "$branch" --arg h "$hold" --arg r "$rhold" \
      '[{metadata:{branch:(if $b=="" then null else $b end),
                   merge_hold:(if $h=="" then null else $h end),
                   rebase_hold:(if $r=="" then null else $r end)}}]' ;;
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
       FAKE_META="$TMP/meta" FAKE_ASSIGNED="$TMP/assigned" \
       FAKE_BRANCH_BEADS="$TMP/branchbeads"

assigned()     { grep -q "^$1	" "$TMP/assigned" 2>/dev/null; }
assigned_arg() { grep "^$1	" "$TMP/assigned" 2>/dev/null | grep -q -- "$2"; }

# --- Run 1: the graduation gate. ---------------------------------------------
OUT1="$(bash "$SCRIPT" --target main 2>&1)"

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

# --- Operator gates. ----------------------------------------------------------
assigned tk-mhold && bad "(9) merge_hold on the convoy must NOT graduate" \
                  || ok "(9) merge_hold on the convoy bead -> held"
printf '%s\n' "$OUT1" | grep -q "tk-mhold — merge_hold set on the convoy (operator gate)" \
  && ok "(9) held convoy names the gate in the log (diagnosable, not a silent skip)" \
  || bad "(9) merge_hold hold reason (got: $OUT1)"

assigned tk-rhold && bad "(10) rebase_hold on the convoy must NOT graduate" \
                  || ok "(10) rebase_hold on the convoy bead -> held"
printf '%s\n' "$OUT1" | grep -q "tk-rhold — rebase_hold set on the convoy (operator gate)" \
  && ok "(10) rebase_hold hold reason names the gate" \
  || bad "(10) rebase_hold hold reason (got: $OUT1)"

assigned tk-sib && bad "(11) held BLOCKED sibling bead on the branch must NOT graduate" \
                || ok "(11) held sibling bead (blocked) on the branch -> held"
printf '%s\n' "$OUT1" | grep -q "tk-sibhold holds branch 'integration/sib'" \
  && ok "(11) hold reason names the holding bead and the branch" \
  || bad "(11) sibling hold reason (got: $OUT1)"

assigned tk-dup && bad "(12) branch already owned: must NOT graduate a second time" \
                || ok "(12) unheld live owner of the branch -> not graduated"
printf '%s\n' "$OUT1" | grep -q "tk-dupowner already owns branch 'integration/dup'" \
  && ok "(12) duplicate-PR veto names the owning bead" \
  || bad "(12) duplicate owner reason (got: $OUT1)"

assigned tk-probefail && bad "(13/error-obj) fail closed: error-object probe must NOT graduate" \
                      || ok "(13/error-obj) fail closed: JSON error object -> not graduated"
assigned tk-probeerr  && bad "(13/array-rc1) fail closed: non-zero probe must NOT graduate" \
                      || ok "(13/array-rc1) fail closed: '[]' with non-zero exit -> not graduated"
assigned tk-probebad  && bad "(13/bad-array) fail closed: unprojectable payload must NOT graduate" \
                      || ok "(13/bad-array) fail closed: array of non-objects -> not graduated"
assigned tk-probemap  && bad "(13/object-map) fail closed: id-keyed envelope must NOT graduate" \
                      || ok "(13/object-map) fail closed: object whose values are bead-shaped -> not graduated"
printf '%s\n' "$OUT1" | grep -q "branch probe on 'integration/probefail' failed" \
  && ok "(13) failed probe is reported, not swallowed" \
  || bad "(13) failed probe report (got: $OUT1)"
# Fail-closed is PER CONVOY, not a pass-wide abort: the ungated convoys in the
# same run still graduated (asserted by the count below).

assigned tk-offspell && ok "(15) merge_hold=false is an OFF spelling -> graduated" \
                     || bad "(15) merge_hold=false must not hold graduation"

assigned tk-boolhold && bad "(16) JSON-boolean hold must NOT graduate" \
                     || ok "(16) hold stored as a JSON boolean still holds"
printf '%s\n' "$OUT1" | grep -q "tk-boolholdsib holds branch 'integration/boolhold'" \
  && ok "(16) boolean hold is caught by the OPERATOR-GATE arm, not incidentally" \
  || bad "(16) boolean hold must trip the operator gate (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "tk-boolfreesib already owns branch 'integration/boolfree'" \
  && ok "(16) boolean false reads as OFF (falls through to the unheld-owner arm)" \
  || bad "(16) boolean false must not read as held (got: $OUT1)"

eq "$(wc -l < "$TMP/assigned" | tr -d ' ')" "2" "(1) exactly the two ungated convoys graduated"
printf '%s\n' "$OUT1" | grep -q "2 graduating" \
  && ok "run 1 summary reports 2 graduating" \
  || bad "run 1 summary graduating count (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "4 held" \
  && ok "run 1 summary reports 4 held (operator gates counted apart from skips)" \
  || bad "run 1 summary held count (got: $OUT1)"

# --- Run 2: convergence. tk-ready now carries branch (assignment persisted) ----
# so the second pass must not re-graduate it.
printf 'tk-ready|integration/ready||\n' >> "$TMP/meta"
bash "$SCRIPT" --target main >/dev/null 2>&1
eq "$(grep -c '^tk-ready	' "$TMP/assigned")" "1" "(8) graduated convoy not re-assigned on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
