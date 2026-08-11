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
#   (14) FAIL CLOSED on the convoy bead's OWN read, five ways — the same fail-open
#        shape as (13), one bead up. Gate (a) lives in that bead's metadata, so a
#        `gc bd show` that fails WITH OUTPUT yields empty markers and reads as
#        "nobody gated this convoy". Each shape pins a different guard: a JSON
#        error object with a non-zero exit (the observed shape), a clean
#        marker-free array with a non-zero exit (pins the exit-status check), a
#        bare `null` (the projection SUCCEEDS on it, emitting an unheld row, so
#        only the payload-shape guard can reject it), an array of non-objects
#        (pins the projection's status), and `[]` (pins the `length > 0` half of
#        the shape guard: an absent bead has no metadata to clear the gate with).
#   (15) truthiness: an explicit off-spelling (merge_hold=false) does NOT hold
#   (16) marker TYPE: a hold stored as a JSON boolean rather than a string still
#        holds — `ascii_downcase` aborts the jq program on a boolean, and that
#        error is discarded, so an uncast comparison drops the veto silently.
#        Boolean `false` still reads as off.
# and NON-VACUOUS COMPLETION — "all members closed" is read as "all members
# MERGED", an inference the count cannot check, and a member closed having landed
# nothing makes it vacuously true forever (tk-q0uxl):
#   (17) THE OBSERVED FAILURE (tk-aezem4 / tk-8coyao): a complete owned convoy
#        whose integration branch has NO landing recorded anywhere in the ledger
#        is NOT graduated, and is counted apart from ordinary skips so a
#        population of them is visible rather than buried.
#   (18) merged_target ALONE is not evidence: it is stamped when the PR is
#        PUBLISHED (pre-open-resolve.sh, patrol merge-push), so a bead naming the
#        branch with merge_result=pull_request records an OPEN PR, not a merge.
#   (19) ONE landing suffices — a convoy that legitimately disposes of members
#        without landing them (tk-44xkw, folded into a sibling by operator
#        decision) still graduates on the members that did land.
#   (20) the probe reads CLOSED beads: close-on-land closes a bead AT its merge,
#        and `gc bd list --metadata-field` returns open beads only unless --status
#        says otherwise — a live-only probe finds no landing ever and refuses
#        every convoy in the city. The stub honors --status, so this is falsifiable.
#   (21) ...and not closed beads ONLY: a landed bead REOPENED for rework still
#        records the merge that put its work on the branch.
#   (22) marker TYPE and CASE, as (16) one field over: a merge_result stored as a
#        JSON boolean must not abort the projection and take the genuine landing
#        rows with it, and "MERGED" counts.
#   (23) FAIL CLOSED, four ways, as (13): a landing probe that fails WITH OUTPUT
#        yields zero rows, which reads as "nothing ever landed here" — and would
#        report a healthy convoy as permanently defective on a transient blip.
#        Each shape pins a different guard and none can be deleted without a red
#        test; a failed probe counts as a SKIP (retry next pass), never as vacuous.
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
#   tk-showfail  owned, integration/*, 2/2  -> bead show error object -> fail closed
#   tk-showrc    owned, integration/*, 2/2  -> bead show clean array + exit 1 -> closed
#   tk-shownull  owned, integration/*, 2/2  -> bead show 'null' -> fail closed
#   tk-showbad   owned, integration/*, 2/2  -> bead show [1,2] -> fail closed
#   tk-showgone  owned, integration/*, 2/2  -> bead show '[]' (absent) -> fail closed
#   tk-vacuous   owned, integration/*, 1/1  -> nothing ever landed on the branch
#   tk-pubonly   owned, integration/*, 2/2  -> branch named by an OPEN PR, no merge
#   tk-mixed     owned, integration/*, 3/3  -> GRADUATE (one member landed, others
#                                             closed without landing)
#   tk-reopened  owned, integration/*, 2/2  -> GRADUATE (landing bead reopened)
#   tk-landtype  owned, integration/*, 2/2  -> GRADUATE (boolean + "MERGED" rows)
#   tk-landfail  owned, integration/*, 2/2  -> landing error object -> fail closed
#   tk-landerr   owned, integration/*, 2/2  -> landing '[]' + exit 1 -> fail closed
#   tk-landbad   owned, integration/*, 2/2  -> landing [1,2] -> fail closed
#   tk-landmap   owned, integration/*, 2/2  -> landing id-keyed object -> fail closed
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
tk-showfail|true|integration/showfail|2|2
tk-showrc|true|integration/showrc|2|2
tk-shownull|true|integration/shownull|2|2
tk-showbad|true|integration/showbad|2|2
tk-showgone|true|integration/showgone|2|2
tk-vacuous|true|integration/vacuous|1|1
tk-pubonly|true|integration/pubonly|2|2
tk-mixed|true|integration/mixed|3|3
tk-reopened|true|integration/reopened|2|2
tk-landtype|true|integration/landtype|2|2
tk-landfail|true|integration/landfail|2|2
tk-landerr|true|integration/landerr|2|2
tk-landbad|true|integration/landbad|2|2
tk-landmap|true|integration/landmap|2|2
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
tk-showfail
tk-showrc
tk-shownull
tk-showbad
tk-showgone
tk-vacuous
tk-pubonly
tk-mixed
tk-reopened
tk-landtype
tk-landfail
tk-landerr
tk-landbad
tk-landmap
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

# Beads recording a merge ONTO an integration branch (the `gc bd list
# --metadata-field merged_target=<b>` probe source): branch|id|status|merge_result|json
# `json` non-empty emits merge_result as RAW JSON rather than as a string.
#
# Every genuine landing row is CLOSED, because close-on-land is what closes it —
# so a probe that forgot --status (the CLI returns OPEN beads only by default)
# sees none of these and every convoy below reads as vacuous. Cases (20)/(23) are
# only falsifiable because the stub honors --status exactly as the CLI does.
#
#   tk-mixedland    — one landing in a convoy whose other members closed without
#                     landing anything: the disposal case (tk-44xkw). ONE suffices.
#   tk-reopland     — a landed bead REOPENED for rework. The merge it records
#                     happened; a closed-only probe would miss it.
#   tk-pubopen      — names the branch with merge_result=pull_request: merged_target
#                     is stamped when the PR is PUBLISHED, so this is an OPEN PR.
#                     The one row that must NOT read as evidence.
#   tk-typebool     — merge_result as a JSON BOOLEAN. `ascii_downcase` aborts the
#                     whole jq program on it, and that error is discarded, so an
#                     uncast projection drops tk-typecase alongside it and the
#                     convoy reads as vacuous.
#   tk-typecase     — "MERGED": the case-folded spelling ascii_downcase is there for.
cat > "$TMP/landed" <<'L'
integration/ready|tk-readyland|closed|merged|
integration/offspell|tk-offspellland|closed|merged|
integration/mixed|tk-mixedland|closed|merged|
integration/reopened|tk-reopland|in_progress|merged|
integration/pubonly|tk-pubopen|open|pull_request|
integration/landtype|tk-typebool|closed|true|1
integration/landtype|tk-typecase|closed|MERGED|
L

# Deliberately ABSENT from the table above: every branch whose convoy is vetoed by
# an operator gate or a branch-probe guard (mhold, rhold, sib, dup, boolhold,
# boolfree, probe*, show*). Those convoys never reach the landing probe, because
# the vacuity check runs LAST — after every veto that names another actor, which
# is what a human looking at the convoy right now needs told. Withholding their
# rows is what pins that order: move the check any earlier and cases (9)-(16) go
# red instead of silently reporting the wrong reason.

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
    # Three different `bd list` callers: the rig convoy ledger (--type=convoy),
    # the branch probe (--metadata-field branch=<b>), and the landing probe
    # (--metadata-field merged_target=<b>). Discriminate on the flag and its KEY,
    # and capture --status so both probes can honor it — a stub that ignored the
    # status filter would make the LIVE_STATUSES case (11) and the ALL_STATUSES
    # case (20) equally unfalsifiable.
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
    # The real CLI returns OPEN beads only when --status is absent. Model that,
    # so a probe that omits the flag gets the CLI's answer and not a free pass.
    [ -n "$statuses" ] || statuses="open"
    case "$mfield" in
      merged_target=*)
        br="${mfield#merged_target=}"
        # Injected ledger failures, exactly as for the branch probe below and for
        # the same reason: `gc ... --json` reports its own errors as a non-empty
        # JSON object on stdout, and every shape here then yields zero landing
        # rows — which reads as "nothing ever landed on this branch", i.e. reports
        # a healthy convoy as permanently defective. Each shape defeats every
        # guard but one. (`[]` with a zero exit is NOT here: that is the genuine
        # "nothing landed" answer, which tk-vacuous exercises.)
        case "$br" in
          # The observed shape: a JSON error OBJECT plus a non-zero exit.
          integration/landfail) printf '{"error":"invalid --metadata-field","schema_version":1}\n'; exit 1 ;;
          # A well-formed EMPTY array with a non-zero exit. Isolates the
          # exit-status guard: the payload is exactly the value that legitimately
          # means "nothing landed", so nothing else can reject it — and the two
          # readings differ, since one is a skip and the other a standing defect.
          integration/landerr)  printf '[]\n'; exit 1 ;;
          # An array of non-objects: passes the type guard, then blows up the
          # projection. Isolates the jq-status guard.
          integration/landbad)  printf '[1, 2]\n'; exit 0 ;;
          # An OBJECT whose values are bead-shaped — a --json envelope keyed by id
          # rather than a list. `.[]` iterates an object's values happily, so the
          # projection SUCCEEDS and emits a landing row; only "is the payload an
          # array?" rejects it. The row carries merge_result=merged, so the pass
          # would graduate on it and the test cannot go green by accident.
          integration/landmap)
            printf '{"tk-x": {"id": "tk-x", "metadata": {"merged_target": "%s", "merge_result": "merged"}}}\n' \
              "$br"; exit 0 ;;
        esac
        out=""
        while IFS='|' read -r fbr fid fstatus fresult fjson; do
          [ -n "$fbr" ] || continue
          [ "$fbr" = "$br" ] || continue
          grep -qF -- ",$fstatus," <<< ",$statuses," || continue
          if [ -n "$fjson" ]; then
            obj=$(jq -n --arg id "$fid" --arg b "$fbr" --argjson m "$fresult" \
              '{id:$id, metadata:{merged_target:$b, merge_result:$m}}')
          else
            obj=$(jq -n --arg id "$fid" --arg b "$fbr" --arg m "$fresult" \
              '{id:$id, metadata:{merged_target:$b, merge_result:$m}}')
          fi
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_LANDED"
        printf '[%s]\n' "$out"
        exit 0 ;;
    esac
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
        grep -qF -- ",$fstatus," <<< ",$statuses," || continue
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
    # Injected bead-read failures, mirroring the branch-probe injections above.
    # Gate (a) is read out of THIS payload, so a `gc bd show` that fails while
    # writing to stdout yields empty markers and reads as an ungated convoy. As
    # with the probe, each shape defeats every guard but one. (A well-formed
    # non-empty array with a ZERO exit is NOT here: that is the legitimate answer
    # every other convoy in this fixture already exercises.)
    case "$id" in
      # The observed shape, as `gc bd show` really reports a bad id: a JSON error
      # OBJECT plus a non-zero exit.
      tk-showfail) printf '{"error":"bead not found","schema_version":1}\n'; exit 1 ;;
      # A well-formed, marker-free array with a NON-ZERO exit — the read died
      # after emitting. Isolates the exit-status guard: the payload is exactly
      # what an ungated convoy legitimately looks like, so nothing else rejects
      # it. (An empty-output variant would be caught by the emptiness guard
      # instead, leaving the rc check unpinned.)
      tk-showrc)   printf '[{"id":"tk-showrc","metadata":{}}]\n'; exit 1 ;;
      # A bare `null` with a zero exit — the only shape here that the projection
      # cannot catch: `null | .[0].metadata.merge_hold // ""` is "" all the way
      # down, so the projection SUCCEEDS and emits a clean unheld row, i.e. reads
      # as an ungated convoy. Only the payload-shape guard rejects it.
      tk-shownull) printf 'null\n'; exit 0 ;;
      # An array of non-objects: passes the type guard, then blows up the
      # projection. Isolates the jq-status guard.
      tk-showbad)  printf '[1, 2]\n'; exit 0 ;;
      # `[]` with a zero exit — the bead is not there at all. Unlike the branch
      # probe, where "[]" legitimately means "nobody holds this branch", an absent
      # convoy bead carries no metadata that could clear gate (a). Pins the
      # `length > 0` half of the type guard.
      tk-showgone) printf '[]\n'; exit 0 ;;
    esac
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
       FAKE_BRANCH_BEADS="$TMP/branchbeads" FAKE_LANDED="$TMP/landed"

assigned()     { grep -q "^$1	" "$TMP/assigned" 2>/dev/null; }
assigned_arg() { grep -q -- "$2" < <(grep "^$1	" "$TMP/assigned" 2>/dev/null); }

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
grep -q "tk-mhold — merge_hold set on the convoy (operator gate)" <<< "$OUT1" \
  && ok "(9) held convoy names the gate in the log (diagnosable, not a silent skip)" \
  || bad "(9) merge_hold hold reason (got: $OUT1)"

assigned tk-rhold && bad "(10) rebase_hold on the convoy must NOT graduate" \
                  || ok "(10) rebase_hold on the convoy bead -> held"
grep -q "tk-rhold — rebase_hold set on the convoy (operator gate)" <<< "$OUT1" \
  && ok "(10) rebase_hold hold reason names the gate" \
  || bad "(10) rebase_hold hold reason (got: $OUT1)"

assigned tk-sib && bad "(11) held BLOCKED sibling bead on the branch must NOT graduate" \
                || ok "(11) held sibling bead (blocked) on the branch -> held"
grep -q "tk-sibhold holds branch 'integration/sib'" <<< "$OUT1" \
  && ok "(11) hold reason names the holding bead and the branch" \
  || bad "(11) sibling hold reason (got: $OUT1)"

assigned tk-dup && bad "(12) branch already owned: must NOT graduate a second time" \
                || ok "(12) unheld live owner of the branch -> not graduated"
grep -q "tk-dupowner already owns branch 'integration/dup'" <<< "$OUT1" \
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
grep -q "branch probe on 'integration/probefail' failed" <<< "$OUT1" \
  && ok "(13) failed probe is reported, not swallowed" \
  || bad "(13) failed probe report (got: $OUT1)"
# Fail-closed is PER CONVOY, not a pass-wide abort: the ungated convoys in the
# same run still graduated (asserted by the count below).

assigned tk-showfail && bad "(14/error-obj) fail closed: error-object bead read must NOT graduate" \
                     || ok "(14/error-obj) fail closed: JSON error object from bd show -> not graduated"
assigned tk-showrc   && bad "(14/array-rc1) fail closed: non-zero bead read must NOT graduate" \
                     || ok "(14/array-rc1) fail closed: clean array with non-zero exit -> not graduated"
assigned tk-shownull && bad "(14/null) fail closed: 'null' payload must NOT graduate" \
                     || ok "(14/null) fail closed: bare 'null' (projects to an unheld row) -> not graduated"
assigned tk-showbad  && bad "(14/bad-array) fail closed: unprojectable bead read must NOT graduate" \
                     || ok "(14/bad-array) fail closed: array of non-objects -> not graduated"
assigned tk-showgone && bad "(14/absent) fail closed: absent convoy bead must NOT graduate" \
                     || ok "(14/absent) fail closed: '[]' (bead not there) -> not graduated"
grep -q "tk-showfail — convoy bead read failed" <<< "$OUT1" \
  && ok "(14) failed bead read is reported, not swallowed" \
  || bad "(14) failed bead read report (got: $OUT1)"

assigned tk-offspell && ok "(15) merge_hold=false is an OFF spelling -> graduated" \
                     || bad "(15) merge_hold=false must not hold graduation"

assigned tk-boolhold && bad "(16) JSON-boolean hold must NOT graduate" \
                     || ok "(16) hold stored as a JSON boolean still holds"
grep -q "tk-boolholdsib holds branch 'integration/boolhold'" <<< "$OUT1" \
  && ok "(16) boolean hold is caught by the OPERATOR-GATE arm, not incidentally" \
  || bad "(16) boolean hold must trip the operator gate (got: $OUT1)"
grep -q "tk-boolfreesib already owns branch 'integration/boolfree'" <<< "$OUT1" \
  && ok "(16) boolean false reads as OFF (falls through to the unheld-owner arm)" \
  || bad "(16) boolean false must not read as held (got: $OUT1)"

# --- Non-vacuous completion. ---------------------------------------------------
assigned tk-vacuous && bad "(17) convoy with nothing landed on its branch must NOT graduate" \
                    || ok "(17) complete convoy, no landing recorded on the branch -> not graduated"
grep -q "tk-vacuous — no bead records a merge onto 'integration/vacuous'" <<< "$OUT1" \
  && ok "(17) vacuous convoy names the branch and what is missing" \
  || bad "(17) vacuous veto reason (got: $OUT1)"
grep -q "gc convoy land" <<< "$OUT1" \
  && ok "(17) veto points at the deliberate manual path" \
  || bad "(17) vacuous veto must name the operator's override (got: $OUT1)"

assigned tk-pubonly && bad "(18) merged_target from a PUBLISHED PR must not read as a merge" \
                    || ok "(18) merged_target + merge_result=pull_request is not landing evidence"

assigned tk-mixed && ok "(19) one landed member is enough (others closed without landing)" \
                  || bad "(19) a convoy that disposes of members without landing them must still graduate"
assigned tk-reopened && ok "(21) a REOPENED landed bead still records its merge" \
                     || bad "(21) landing evidence must not be restricted to closed beads"
# (20) needs no assertion of its own: it is pinned by every graduating case above.
# Their landing rows are CLOSED and the stub returns open beads only when --status
# is absent, so a probe that dropped the flag reports all of them vacuous. (21)
# pins the other half — tk-reopened's row is in_progress, so `--status closed`
# alone fails too. Only the superset passes both.
assigned tk-landtype && ok "(22) JSON-boolean merge_result does not abort the projection" \
                     || bad "(22) boolean merge_result must not take the genuine landing rows with it"

assigned tk-landfail && bad "(23/error-obj) fail closed: error-object landing probe must NOT graduate" \
                     || ok "(23/error-obj) fail closed: JSON error object -> not graduated"
assigned tk-landerr  && bad "(23/array-rc1) fail closed: non-zero landing probe must NOT graduate" \
                     || ok "(23/array-rc1) fail closed: '[]' with non-zero exit -> not graduated"
assigned tk-landbad  && bad "(23/bad-array) fail closed: unprojectable landing payload must NOT graduate" \
                     || ok "(23/bad-array) fail closed: array of non-objects -> not graduated"
assigned tk-landmap  && bad "(23/object-map) fail closed: id-keyed envelope must NOT graduate" \
                     || ok "(23/object-map) fail closed: object whose values are bead-shaped -> not graduated"
grep -q "landing probe on 'integration/landfail' failed" <<< "$OUT1" \
  && ok "(23) failed landing probe is reported, not swallowed" \
  || bad "(23) failed landing probe report (got: $OUT1)"
grep -q "no bead records a merge onto 'integration/landerr'" <<< "$OUT1" \
  && bad "(23) a FAILED probe must not be reported as a vacuous convoy" \
  || ok "(23) a failed probe is a retry, never a standing-defect report"

eq "$(wc -l < "$TMP/assigned" | tr -d ' ')" "5" "(1) exactly the five ungated convoys graduated"
grep -q "5 graduating" <<< "$OUT1" \
  && ok "run 1 summary reports 5 graduating" \
  || bad "run 1 summary graduating count (got: $OUT1)"
grep -q "4 held" <<< "$OUT1" \
  && ok "run 1 summary reports 4 held (operator gates counted apart from skips)" \
  || bad "run 1 summary held count (got: $OUT1)"
grep -q "2 vacuous" <<< "$OUT1" \
  && ok "(17) vacuous convoys counted apart from skips (a population is visible)" \
  || bad "run 1 summary vacuous count (got: $OUT1)"

# --- Run 2: convergence. tk-ready now carries branch (assignment persisted) ----
# so the second pass must not re-graduate it.
printf 'tk-ready|integration/ready||\n' >> "$TMP/meta"
bash "$SCRIPT" --target main >/dev/null 2>&1
eq "$(grep -c '^tk-ready	' "$TMP/assigned")" "1" "(8) graduated convoy not re-assigned on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
