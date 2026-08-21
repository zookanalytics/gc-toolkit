#!/usr/bin/env bash
# Hermetic test for mol-refinery-patrol's ESCALATION WIRING (tk-76jxq).
#
# THE BUG THIS EXISTS TO PREVENT. The refinery re-derives its escalation triggers
# from live state on every idle wake, and the most common trigger — an mr-mode PR
# that is CI-green and waiting for the operator's signature — keeps re-deriving
# true for as long as the operator is away. So it mailed the mayor again, and
# again: EIGHT near-identical "PRs blocked on human approval" escalations in 2h
# (2026-08-09/10, signal-loom) and two more on 2026-08-13, against zero landings.
# The subjects varied only in the count as PRs accumulated — "3 CI-green PRs
# held", "6 merge-ready PRs blocked", "7 PRs green but parked" — so nothing was
# actionable differently at mail 8 than at mail 1.
#
# The cost was burial, not volume. The mayor's inbox reached 19 unread and two
# escalations that genuinely needed a mayor decision were TIME-BOXED and sat
# between the duplicates: a convoy duplicate disposition that expired after ~5.5h
# when one of its three options merged out from under it, and a false graduation
# hold that would have proposed reverting 5 landed PRs.
#
# The formula already SAID to stay silent in steady state (find-work idle-loop
# invariant 4). It was an instruction, and instructions are what failed — twice,
# three days apart. escalation-gate.sh is the mechanism, and mol-witness-patrol
# was wired to it by tk-z4aka; this file is the same enforcement for the refinery,
# which was still mailing bare.
#
# escalation-gate.sh has strong coverage of its own behaviour, but nothing covers
# the formula lines that CALL it — and the wiring is where the storm comes back.
# Every one of these edits leaves the script's tests green while reopening the bug:
#
#   - dropping `--anchor`      -> no dedup key at all
#   - dropping `--state`       -> the gate becomes a mute: real news (a new head
#                                 oid, an approval) waits out the full cooldown
#   - dropping `--kind`        -> the refinery escalates on the gate's DEFAULT
#                                 kind, which is the witness's. One anchor + kind
#                                 = one open escalation, and both roles escalate
#                                 about these same anchors (PR #35: five witness
#                                 mails, two refinery ones), so a shared kind lets
#                                 whichever got there first MUTE the other (KIND)
#   - moving the SCRIPTS_DIR resolution out of the sending shell -> each tool call
#     is a fresh shell, so `$SCRIPTS_DIR` is empty, `/escalation-gate.sh` fails,
#     and NOTHING is sent — a silent mute, worse than the storm
#   - replacing a gated call with a bare `gc mail send` -> the original bug,
#     verbatim (ALLOWLIST)
#   - putting the anchor's own `updated_at` in the fingerprint -> the gate stamps
#     that same anchor before mailing, so its own write makes the next cycle look
#     changed and the item re-mails forever (SELFREOPEN runs the wiring twice
#     against a stub that advances updated_at on every write)
#   - dropping `--cooldown` -> the configured escalation_cooldown is inert and
#     only the script's built-in default is ever in force (COOLDOWN)
#   - dropping the var from a wisp pour -> each wisp is ONE iteration and the next
#     is poured `--root-only`, which materializes no formula defaults, so an
#     unforwarded var arrives unrendered and every cycle after the first silently
#     runs the script's own fallback (PROPAGATE checks all five pour sites)
#   - fingerprinting `target` instead of `merged_target // target` -> a
#     `pre_open_gate` anchor records its landing target in `merged_target`, so the
#     component collapses to a constant on exactly the anchor kind the non-PR
#     fallback exists for, and a retarget waits out the cooldown (MERGEDTARGET)
#   - reading `gc bd show --json` without stripping control characters -> jq
#     fails, STATE is empty, and the gate reads that as "no state tracked": every
#     real change is then held for a full cooldown (CTRLJSON)
#   - substituting a differently-shaped fingerprint when `gh` fails -> it compares
#     unequal in BOTH directions, so the item mails when the outage starts and
#     again when it ends, a flap driven by GitHub's availability (DEGRADED)
#   - resolving the anchor's PR from `pr_number` alone -> the fork-sync flow stamps
#     fork_pr/fork_pr_url and no pr_number, so a live fork-keyed anchor takes the
#     no-PR branch and is fingerprinted from its bead: a head move, an approval or
#     a mergeStateStatus change on the PR actually holding it is invisible until
#     the cooldown expires (FORKPR, FORKPRURL)
#   - reading that number with an unpinned `gh pr view` -> gh resolves a bare
#     number in whatever repository it considers current, so a drifted default
#     fingerprints a stranger's same-numbered PR and both the suppression and the
#     news come from an unrelated repo (PINNED, NOORIGIN)
#   - calling the gate bare instead of `if ! ...; then echo` -> a gate that
#     refuses (it could not BOUND the escalation) takes the best-effort idle pass
#     down with it (GATEFAIL)
#   - dropping `--pr`/`--repo` -> the gate cannot tell that the anchor is held by
#     nothing worse than an unsigned PR, so the one class that is never news is
#     deduped instead of REFUSED and bills one mail per PR forever. Exactly-once
#     is a per-PR toll, not a bound: signal-loom was corrected about #541 and then
#     escalated #544 (PRWIRED, PRNONE, PRFORK). And an unpinned --repo hands the
#     gate a number resolved in whatever repository gh considers current, so the
#     refusal is decided against a stranger's PR (PRPINNED)
#
# So this executes the wiring EXTRACTED VERBATIM from the formula (between the
# `escalation-wiring-*` markers) against stubs, and asserts what reaches the gate.
# No live city, Dolt, mail, network, or real repo — `gc`, `gh` and `git` are all
# stubbed, and `git` is stubbed specifically so the "$(git rev-parse
# --show-toplevel)/assets/scripts" candidate cannot silently resolve to the real
# checkout this test is running inside.
#
# Companion: assets/scripts/witness-escalation-wiring.test.sh (same shape, for
# mol-witness-patrol). The GATE itself is covered by escalation-gate.test.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$2" in *"$1"*) ok "$3" ;; *) bad "$3 (not found in: $2)" ;; esac; }
hasnt() { case "$2" in *"$1"*) bad "$3 (unexpectedly found '$1' in: $2)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

ANCHOR="tk-anch1"

# --- Stubs --------------------------------------------------------------------
# Each stub records its argv as a JSON array, one element per argument. A
# line-oriented log would be ambiguous here: the body is always multi-line, so
# "next line" cannot be told apart from "second line of this argument".
export STUB_LOG="$TMP/log"
mkdir -p "$STUB_LOG" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
# SELFREOPEN runs the REAL gate, which takes an anchor+kind mutex. Keep it inside
# this run's tmpdir so a live refinery patrolling the same anchor id — or a second
# copy of this test — cannot suppress it.
export GC_ESCALATION_GATE_LOCKDIR="$TMP/locks"

make_gate() { # make_gate <dir> [exit-code] — a stub gate the resolution loop finds
  mkdir -p "$1"
  cat > "$1/escalation-gate.sh" <<GATE
#!/usr/bin/env bash
for a in "\$@"; do printf '%s' "\$a" | jq -Rs .; done | jq -s . > "\$STUB_LOG/gate-args.json"
echo "gate" >> "\$STUB_LOG/calls"
exit ${2:-0}
GATE
  chmod +x "$1/escalation-gate.sh"
}

# `gc bd show` returns the anchor; PR_NUMBER (exported per case) decides whether
# it is PR-backed, which is what selects the STATE fingerprint branch.
#
# The stub is STATE-BACKED, and metadata writes ADVANCE `updated_at`. That is not
# incidental realism: a real `gc bd update` touches the bead it writes, and the
# gate stamps the anchor before mailing, so the anchor's modification time is
# downstream of the gate itself. A stub with a frozen timestamp cannot see the
# self-reopen bug at all — cycle 2 would look unchanged for the wrong reason and
# the test would pass over the defect.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
S="$STUB_LOG"
[ -f "$S/meta" ]   || : > "$S/meta"
[ -f "$S/writes" ] || printf '0\n' > "$S/writes"

if [ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ]; then
  # A payload no jq filter can parse: bd printing a diagnostic instead of JSON, or
  # a truncated read. Distinct from STUB_CTRL, which the wiring's `tr -d` cleans —
  # this one survives sanitizing, so the caller's own state build genuinely fails
  # and the never-empty-state guard is what has to hold (STATEGUARD).
  if [ -n "${STUB_BAD_JSON:-}" ]; then printf 'gc: unexpected error\n'; exit 0; fi
  w=$(cat "$S/writes")
  # `${STUB_TARGET-main}` (not `:-`) so a case can set it to "" to model a
  # pre_open_gate anchor that carries NO `target` at all — the shape that makes
  # reading `target` alone collapse the landing-target component to "-".
  meta=$(jq -nc --arg pr "${PR_NUMBER:-}" --arg tgt "${STUB_TARGET-main}" '
    { merge_result: "pre_open_gate", branch: "polecat/tk-anch1" }
    + (if $tgt == "" then {} else { target: $tgt } end)
    + (if $pr == "" then {} else { pr_number: $pr } end)')
  while IFS='|' read -r k v; do
    [ -n "$k" ] || continue
    meta=$(printf '%s' "$meta" | jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}')
  done < "$S/meta"
  row=$(jq -nc --arg id "$3" --arg ts "$(printf '2026-08-13T04:%02d:00Z' "$w")" --argjson meta "$meta" \
    '[{ id: $id, status: "open", updated_at: $ts, metadata: $meta }]')
  # STUB_CTRL splices a RAW control character into a notes field, which is what bd
  # does with prose. It cannot be built with jq: jq escapes a control character to
  # its \uXXXX form and emits VALID JSON, which is exactly the case that does NOT
  # reproduce the bug. Raw, it is invalid JSON an unsanitized read cannot parse.
  if [ -n "${STUB_CTRL:-}" ]; then
    row="${row%\}]}"
    row="$row,\"notes\":\"line$(printf '%b' "$STUB_CTRL")two\"}]"
  fi
  printf '%s\n' "$row"
  exit 0
fi

if [ "${1:-}" = "bd" ] && [ "${2:-}" = "update" ]; then
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --set-metadata)
        kv="$2"; k="${kv%%=*}"; v="${kv#*=}"
        grep -v "^$k|" "$S/meta" > "$S/meta.new" 2>/dev/null || true; mv "$S/meta.new" "$S/meta"
        printf '%s|%s\n' "$k" "$v" >> "$S/meta"
        shift 2 ;;
      --unset-metadata)
        grep -v "^$2|" "$S/meta" > "$S/meta.new" 2>/dev/null || true; mv "$S/meta.new" "$S/meta"
        shift 2 ;;
      *) shift ;;
    esac
  done
  printf '%s\n' "$(( $(cat "$S/writes") + 1 ))" > "$S/writes"   # the self-touch
  echo "update" >> "$S/calls"
  exit 0
fi

if [ "${1:-}" = "mail" ] && [ "${2:-}" = "send" ]; then
  # Drop the "mail send" subcommand so element 0 is the recipient.
  for a in "${@:3}"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$STUB_LOG/mail-args.json"
  echo "mail" >> "$STUB_LOG/calls"
  exit "${STUB_MAIL_RC:-0}"
fi
exit 0
GC

# The fingerprint the formula asks for: headRefOid/reviewDecision/mergeStateStatus.
# Records its argv so the WIRING's gh call can be asserted exactly — a stub that
# only echoes proves the gate got a fingerprint, not that the wiring asked for the
# right three fields. `${GH_FINGERPRINT-<default>}` (not `:-`) so a case can set it
# to the empty string to model a PR lookup that returns nothing.
make_gh() { # make_gh [exit-code]
  cat > "$TMP/bin/gh" <<GH
#!/usr/bin/env bash
for a in "\$@"; do printf '%s' "\$a" | jq -Rs .; done | jq -s . > "\$STUB_LOG/gh-args.json"
[ "${1:-0}" -ne 0 ] && exit ${1:-0}
echo "\${GH_FINGERPRINT-oid123/APPROVED/BLOCKED}"
GH
  chmod +x "$TMP/bin/gh"
}
make_gh 0

# Not a repo, unless a case exports STUB_TOPLEVEL. Without this the middle
# resolution candidate would find the real gc-toolkit checkout and the
# "nothing resolves" case could never be tested.
#
# It DOES have an origin remote, because the wiring pins its PR reads to the
# repository that remote names. `${STUB_ORIGIN_URL-<default>}` (not `:-`) so a
# case can set it to "" to model a checkout with no origin at all — the shape
# that must degrade rather than read a number in whatever repo gh points at.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "${1:-}" = "rev-parse" ] && [ "${2:-}" = "--show-toplevel" ]; then
  [ -n "${STUB_TOPLEVEL:-}" ] || exit 128
  echo "$STUB_TOPLEVEL"; exit 0
fi
if [ "${1:-}" = "remote" ] && [ "${2:-}" = "get-url" ]; then
  url="${STUB_ORIGIN_URL-https://github.com/zookanalytics/gc-toolkit.git}"
  [ -n "$url" ] || exit 128
  printf '%s\n' "$url"; exit 0
fi
exit 0
GIT
chmod +x "$TMP/bin/gc" "$TMP/bin/gh" "$TMP/bin/git"

reset() { rm -f "$STUB_LOG"/*; }
arg_after() { jq -r --arg k "$2" 'index($k) as $i | if $i == null then "" else (.[$i+1] // "") end' \
                "$STUB_LOG/$1" 2>/dev/null; }
gate_arg() { arg_after gate-args.json "$1"; }
gh_argv()  { jq -r 'join(" ")' "$STUB_LOG/gh-args.json" 2>/dev/null; }
mail_arg() { arg_after mail-args.json "$1"; }
count()    { local n; n=$(grep -c "^$1\$" "$STUB_LOG/calls" 2>/dev/null); printf '%s' "${n:-0}"; }

# --- Extract the wiring from the formula --------------------------------------
extract() { # extract <marker> -> the block, placeholders substituted
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML" | sed "s/<anchor>/$ANCHOR/g; s/<bead-id>/$ANCHOR/g"
}

# A literal list, not a variable to word-split: the same structural check every
# gated block in this formula must pass.
for marker in escalation-wiring-discipline escalation-wiring-held-anchor \
              escalation-wiring-existing-pr escalation-wiring-signoff-cap \
              escalation-wiring-strategy-local; do
  block="$(extract "$marker")"
  [ -n "$block" ] && ok "$marker: extracted between markers" \
    || bad "$marker: extraction EMPTY — markers missing from $TOML"
  printf '%s\n' "$block" > "$TMP/$marker.sh"

  # A TOML `"""` block silently collapses a trailing backslash continuation, so
  # syntax-check what actually ships, not what it looks like in the editor.
  bash -n "$TMP/$marker.sh" \
    && ok "$marker: extracted wiring is valid bash" \
    || bad "$marker: extracted wiring failed bash -n"

  # NO BACKSLASHES IN A MARKED BLOCK. This test reads the raw TOML, but the
  # refinery reads the RENDERED description — and a `"""` string transforms
  # escapes, so `tr -d '\\000-\\037'` in the source ships as `\000-\037` and the
  # two differ. The test would then be green against a command the refinery never
  # runs (and the shipped one can be the broken half: an unrendered `\\000-\\037`
  # is a reverse tr range that deletes nothing and errors out). Nothing here needs
  # a backslash, so ban them and keep source and shipped byte-identical.
  case "$block" in
    *\\*) bad "$marker: contains a backslash — TOML \"\"\" will transform it, so what ships differs from what this test runs. Use an escape-free form ([:cntrl:], [:space:])." ;;
    *)    ok "$marker: escape-free, so the extracted block is what actually ships" ;;
  esac

  # The resolution loop must live in the SAME block as the send.
  has 'escalation-gate.sh' "$block" "$marker: resolves the gate script"
  has 'if [ -x "$cand/escalation-gate.sh" ]' "$block" "$marker: resolution loop is in the sending shell"

  # The gated call must be non-fatal. The gate exits non-zero only when it could
  # not BOUND the escalation, and the idle pass has to reach its later passes — a
  # bare call makes one refusal the block's exit status.
  has 'if ! "$SCRIPTS_DIR/escalation-gate.sh"' "$block" \
      "$marker: the gated call is wrapped non-fatally (if ! ...)"

  # Every gated call must name the refinery's own channel. The gate's default kind
  # is "witness"; inheriting it lets the witness's stamp for an anchor suppress the
  # refinery's escalation about that same anchor, and vice versa.
  has '--kind' "$block" "$marker: passes --kind (never inherits the witness default)"
  has '--cooldown "{{escalation_cooldown}}"' "$block" \
      "$marker: forwards the configured cooldown"

  # Ordering: the gated call comes first, the bare mail only in the else arm.
  gate_line=$(grep -n 'SCRIPTS_DIR/escalation-gate.sh' "$TMP/$marker.sh" | head -1 | cut -d: -f1)
  mail_line=$(grep -n 'gc mail send' "$TMP/$marker.sh" | head -1 | cut -d: -f1)
  if [ -n "$gate_line" ] && [ -n "$mail_line" ] && [ "$gate_line" -lt "$mail_line" ]; then
    ok "$marker: gated call comes first; the bare mail is the fallback arm"
  else
    bad "$marker: gate must precede the fallback mail (gate@${gate_line:-none} mail@${mail_line:-none})"
  fi
done

# --- RIGROOT: the gc-toolkit rig resolves through GC_RIG_ROOT -----------------
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=55 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "RIGROOT: escalates through the gate"
eq "$(count mail)" "0" "RIGROOT: sends no bare mail"
eq "$(gate_arg --anchor)" "$ANCHOR" "RIGROOT: passes --anchor (the dedup key)"
eq "$(gate_arg --state)" "oid123/APPROVED/BLOCKED" \
   "RIGROOT: --state is the PR fingerprint that lets real news through"
eq "$(gate_arg --kind)" "refinery" "RIGROOT: escalates on the refinery's own channel"
has "MERGE_HELD" "$(gate_arg --subject)" "RIGROOT: passes --subject"
has "Recommendation" "$(gate_arg --body)" "RIGROOT: passes --body intact (multi-line)"

# --- PRWIRED: the gate is told WHICH PR, so it can refuse the resting state ---
# Without this the gate can only dedup, and dedup is keyed on the anchor: "once
# per PR awaiting approval" then scales with throughput instead of bounding
# anything (tk-qe2tv). The gate re-reads the PR itself and refuses only when
# GitHub says nothing is wrong, so passing it cannot mute a real fault — but not
# passing it silently restores the drip.
eq "$(gate_arg --pr)" "55" "PRWIRED: names the PR whose holding state this reports"

# --- PRPINNED: and pins it to the same repository the fingerprint came from ---
# `gh pr view <n>` inside the gate resolves a bare number in whatever repository
# gh considers current, exactly as it does in the wiring itself (PINNED above).
# Unpinned, the refusal would be decided against a stranger's PR #55.
eq "$(gate_arg --repo)" "github.com/zookanalytics/gc-toolkit" \
   "PRPINNED: pins the gate's own PR read to the origin remote's repository"

# --- CITYPATH: the other three rigs have no assets/scripts of their own -------
reset
make_gate "$TMP/city/rigs/gc-toolkit/assets/scripts"
PR_NUMBER=55 GC_RIG_ROOT="" GC_CITY_PATH="$TMP/city" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "CITYPATH: a co-tenant rig resolves the gate through GC_CITY_PATH"
eq "$(count mail)" "0" "CITYPATH: sends no bare mail"

# --- GHCALL: the wiring must ask gh for the right three fields ----------------
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=55 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
GHARGV="$(gh_argv)"
has "headRefOid"       "$GHARGV" "GHCALL: fingerprints the head oid (a push is news)"
has "reviewDecision"   "$GHARGV" "GHCALL: fingerprints the review decision (an approval is news)"
has "mergeStateStatus" "$GHARGV" "GHCALL: fingerprints the merge state (a gate clearing is news)"

# --- PINNED: the PR read is pinned to the ORIGIN remote's repository ----------
# `gh pr view <n>` resolves a bare number in whatever repository gh considers
# current — set-default, GH_REPO, GH_HOST and cwd all move it — and every other
# PR read in this rig is pinned for exactly that reason. Unpinned, a drifted gh
# fingerprints a stranger's PR #55: the gate then mails on ITS head moves and
# stays silent through the real one's, suppression and news both decided by an
# unrelated repository.
has "--repo" "$GHARGV" "PINNED: the PR read carries --repo"
eq "$(arg_after gh-args.json --repo)" "github.com/zookanalytics/gc-toolkit" \
   "PINNED: pinned to the origin remote's repository, host-qualified"

# --- FORKPR: an anchor keyed by fork_pr is PR-backed --------------------------
# THE REVIEWED DEFECT (tk-97tdf). The fork-sync flow stamps fork_pr/fork_pr_url
# and NO pr_number at all, so a resolver reading pr_number alone sends a live
# fork-keyed anchor down the no-PR branch and fingerprints it from its bead —
# where a head move, an approval, or a mergeStateStatus change does not appear.
# The PR holding it can go from BLOCKED to clean and this gate cannot tell.
reset
make_gate "$TMP/rig/assets/scripts"
printf 'fork_pr|77\n' >> "$STUB_LOG/meta"
PR_NUMBER="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(gate_arg --state)" "oid123/APPROVED/BLOCKED" \
   "FORKPR: a fork_pr anchor is fingerprinted from its PR, not from its bead"
eq "$(arg_after gh-args.json view)" "77" "FORKPR: and the number read is fork_pr's"
eq "$(gate_arg --pr)" "77" "PRFORK: and the gate is told the same number, not pr_number's"
has "77" "$(gate_arg --body)" "FORKPR: the body names the PR too (it said 'none' before)"

# --- FORKPRURL: the number scanned out of fork_pr_url, repo-filtered ----------
reset
make_gate "$TMP/rig/assets/scripts"
printf 'fork_pr_url|https://github.com/zookanalytics/gc-toolkit/pull/88\n' >> "$STUB_LOG/meta"
PR_NUMBER="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(arg_after gh-args.json view)" "88" "FORKPRURL: an in-repo fork_pr_url names the anchor's PR"
eq "$(gate_arg --kind)" "refinery" "FORKPRURL: on the real channel, not the degraded one"
# ...and a fork_pr_url pointing somewhere else is NOT this anchor's PR. It is the
# one key that carries a repository in its own value, so it is the one that can be
# checked — reading its number anyway would fingerprint a foreign PR.
reset
make_gate "$TMP/rig/assets/scripts"
printf 'fork_pr_url|https://github.com/someone/elsewhere/pull/88\n' >> "$STUB_LOG/meta"
PR_NUMBER="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
has "pre_open_gate" "$(gate_arg --state)" \
    "FORKPRURL: a foreign fork_pr_url does not make the anchor PR-backed here"
[ ! -s "$STUB_LOG/gh-args.json" ] \
  && ok "FORKPRURL: and no PR in another repository was read" \
  || bad "FORKPRURL: read PR 88 out of a repository this checkout does not own ($(gh_argv))"
# --- PRNONE: an anchor that names no PR passes an EMPTY --pr ------------------
# The gate treats empty as "no PR named" and never considers the class, which is
# what keeps a bead-fingerprinted anchor decided by the ordinary dedup. A wiring
# that forwarded some other value here would hand the gate a PR the anchor does
# not own.
eq "$(gate_arg --pr)" "" "PRNONE: a bead-fingerprinted anchor names no PR to the gate"

# --- NOORIGIN: an unresolvable origin degrades, it does not read unpinned -----
# Fail closed, as merge-skill.sh and reconcile-merged-prs.sh do: a repository this
# checkout cannot name is one the number cannot be pinned to, and an unpinned read
# is the drift hazard itself. One degraded escalation costs a cooldown; a wrong
# fingerprint mutes the real anchor for one.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=55 STUB_ORIGIN_URL="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(gate_arg --kind)" "refinery-degraded" \
   "NOORIGIN: no resolvable origin -> the degraded channel, not an ambient read"
# ...and it must not hand the gate the number either. The gate does its OWN
# `gh pr view` to decide the awaiting-approval class, so an unpinned number there
# is this same drift hazard one layer down: the class would be decided against a
# stranger's PR #55, and a refusal decided that way mutes the real anchor.
eq "$(gate_arg --pr)" "" \
   "NOORIGIN: and names no PR to the gate, whose own read would be unpinned too"
has "unavailable" "$(gate_arg --state)" "NOORIGIN: --state names what is unavailable"
has "pr-55" "$(gate_arg --state)" "NOORIGIN: and which PR could not be pinned"
hasnt "pre_open_gate" "$(gate_arg --state)" \
      "NOORIGIN: does NOT borrow the bead shape on the PR channel"
[ ! -s "$STUB_LOG/gh-args.json" ] \
  && ok "NOORIGIN: gh was never called without a pin" \
  || bad "NOORIGIN: gh ran unpinned ($(gh_argv))"

# --- AMBIG: two in-repo numbers is not an invitation to pick one --------------
reset
make_gate "$TMP/rig/assets/scripts"
printf 'fork_pr|77\n' >> "$STUB_LOG/meta"
PR_NUMBER=55 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(gate_arg --kind)" "refinery-degraded" \
   "AMBIG: an anchor naming two PRs here degrades rather than choosing arbitrarily"
hasnt "pre_open_gate" "$(gate_arg --state)" \
      "AMBIG: and does not substitute the bead fingerprint on the PR channel"
[ ! -s "$STUB_LOG/gh-args.json" ] \
  && ok "AMBIG: neither candidate was read" \
  || bad "AMBIG: read one of two ambiguous candidates ($(gh_argv))"

# --- NOPR: a pre-open anchor with no PR still gets a real fingerprint ---------
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "NOPR: an anchor with no PR still escalates through the gate"
S="$(gate_arg --state)"
[ -n "$S" ] && ok "NOPR: --state is non-empty (empty would read as 'no state tracked')" \
  || bad "NOPR: --state came out EMPTY — the gate would suppress real news for a full cooldown"
has "pre_open_gate" "$S" "NOPR: fingerprints merge_result"
has "polecat/tk-anch1" "$S" "NOPR: fingerprints the branch"
eq "$(gate_arg --kind)" "refinery" "NOPR: still the refinery's normal channel (this is not a degraded read)"

# --- CHECKMARK: the gate markers are part of the non-PR fingerprint -----------
# A check.<gate> flipping green is the single most important piece of news about a
# pre-open anchor, and it is invisible in status/merge_result/branch/target alone.
reset
make_gate "$TMP/rig/assets/scripts"
printf 'check.codex|green@oid9\n' >> "$STUB_LOG/meta"
PR_NUMBER="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
has "check.codex=green@oid9" "$(gate_arg --state)" \
    "CHECKMARK: a gate marker going green changes the fingerprint"

# --- MERGEDTARGET: the landing target is `merged_target // target` ------------
# A pre_open_gate anchor records where it will land in `merged_target` and may
# carry no `target` at all. Reading `target` alone collapses this component to a
# constant on exactly the anchor kind the non-PR branch exists for.
reset
make_gate "$TMP/rig/assets/scripts"
printf 'merged_target|integration/tk-conv1\n' >> "$STUB_LOG/meta"
PR_NUMBER="" STUB_TARGET="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
has "integration/tk-conv1" "$(gate_arg --state)" \
    "MERGEDTARGET: reads merged_target when the anchor carries no target"

# --- DEGRADED: a gh outage moves to its own channel, it does not flap ---------
# Substituting the bead-shaped fingerprint on the PR channel compares unequal in
# BOTH directions: the item mails when the outage starts and again when it ends.
reset
make_gate "$TMP/rig/assets/scripts"
make_gh 1
PR_NUMBER=55 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(gate_arg --kind)" "refinery-degraded" \
   "DEGRADED: a failed gh lookup escalates on its OWN kind, leaving the real channel's stamp alone"
has "unavailable" "$(gate_arg --state)" "DEGRADED: --state names what is unavailable"
has "pr-55" "$(gate_arg --state)" "DEGRADED: --state names which PR could not be read"
DEG1="$(gate_arg --state)"
# ...and it must not vary while the outage lasts, or it chatters on its own channel.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=55 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(gate_arg --state)" "$DEG1" \
   "DEGRADED: the degraded fingerprint is CONSTANT while the outage lasts (rides its own cooldown)"
make_gh 0

# --- GHEMPTY: a lookup that succeeds but returns nothing is also degraded -----
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=55 GH_FINGERPRINT="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(gate_arg --kind)" "refinery-degraded" \
   "GHEMPTY: an empty gh result degrades too (exit 0 is not proof of a fingerprint)"
S="$(gate_arg --state)"
[ -n "$S" ] && ok "GHEMPTY: --state is still non-empty" \
  || bad "GHEMPTY: --state EMPTY — the gate would stamp 'no state tracked' durably"

# --- CTRLJSON: raw control characters in the bead read ------------------------
# bd emits them from prose notes and jq rejects every unescaped one, including a
# plain tab. Unsanitized, the state build fails and STATE is empty — which the
# gate reads as "no state tracked" and then holds real news for a full cooldown.
# A lost parse must not look like a lost fingerprint.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER="" STUB_CTRL='\t' GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
has "pre_open_gate" "$(gate_arg --state)" \
    "CTRLJSON: a tab in the bead's notes does not destroy the fingerprint"
eq "$(gate_arg --kind)" "refinery" "CTRLJSON: a sanitized read is NOT a degraded read"

# --- STATEGUARD: the block must never hand the gate an EMPTY --state ----------
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER="" STUB_BAD_JSON=1 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
S="$(gate_arg --state)"
[ -n "$S" ] && ok "STATEGUARD: an unparseable bead read still yields a non-empty --state" \
  || bad "STATEGUARD: --state EMPTY on an unparseable read — the gate stamps 'no state tracked' and mutes every real change for a cooldown"
eq "$(gate_arg --kind)" "refinery-degraded" \
   "STATEGUARD: and it goes on the degraded channel, not the real one"

# --- GATEFAIL: a refusing gate must not take the idle pass down ---------------
reset
make_gate "$TMP/rig/assets/scripts" 1
PR_NUMBER=55 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
RC=$?
eq "$RC" "0" "GATEFAIL: a gate refusal does not fail the block (best-effort pass reaches its later checks)"
eq "$(count mail)" "0" "GATEFAIL: a refusal is NOT a licence to mail anyway — that is the unbounded storm"

# --- FALLBACK: an unsynced rig mails directly, it does not go silent ----------
reset
PR_NUMBER=55 GC_RIG_ROOT="$TMP/absent" GC_CITY_PATH="$TMP/absent" \
  bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(count mail)" "1" "FALLBACK: a rig with no gate script still escalates (old behavior, not a dropped escalation)"
eq "$(count gate)" "0" "FALLBACK: and no gate ran"

# --- COOLDOWN: the configured value must actually reach the gate --------------
# The gated calls carry the literal `{{escalation_cooldown}}` placeholder in the
# raw TOML; what matters is that the flag is THERE and carries the placeholder
# rather than a hardcoded number, which would freeze every rig at one value.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=55 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
eq "$(gate_arg --cooldown)" "{{escalation_cooldown}}" \
   "COOLDOWN: the configured escalation_cooldown is what reaches the gate, not a literal"

# --- SELFREOPEN: the gate's own stamp must not reopen the fingerprint ---------
# THE REGRESSION. This runs the REAL gate, not the recording stub, twice over an
# unchanged non-PR anchor. The gate stamps `escalated.refinery` on that anchor
# before mailing, and the `gc` stub advances `updated_at` on every write — so any
# fingerprint built from the anchor's modification time differs on cycle 2 BECAUSE
# THE GATE RAN, and the item re-mails every idle wake forever.
#
# It also exercises the unrendered `--cooldown {{escalation_cooldown}}` the
# --root-only pour actually ships: cycle 1 must still deliver.
if [ -x "$HERE/escalation-gate.sh" ]; then
  mkdir -p "$TMP/realrig/assets/scripts"
  cp "$HERE/escalation-gate.sh" "$TMP/realrig/assets/scripts/escalation-gate.sh"
  chmod +x "$TMP/realrig/assets/scripts/escalation-gate.sh"
  reset
  PR_NUMBER="" GC_RIG_ROOT="$TMP/realrig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
  eq "$(count mail)" "1" "SELFREOPEN: cycle 1 escalates (an unrendered --cooldown still delivers)"
  PR_NUMBER="" GC_RIG_ROOT="$TMP/realrig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
  eq "$(count mail)" "1" "SELFREOPEN: cycle 2 over an unchanged anchor is SUPPRESSED, not re-mailed"
  # ...and a genuine change still gets through on the very next cycle.
  printf 'check.codex|green@oid9\n' >> "$STUB_LOG/meta"
  PR_NUMBER="" GC_RIG_ROOT="$TMP/realrig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-held-anchor.sh" >/dev/null 2>&1
  eq "$(count mail)" "2" "SELFREOPEN: a real state change still escalates immediately — dedup, not mute"
else
  bad "SELFREOPEN: escalation-gate.sh not found next to this test — the wiring has no gate to call"
fi

# --- EXISTINGPR: the invalid-existing_pr escalation ---------------------------
reset
make_gate "$TMP/rig/assets/scripts"
WORK="$ANCHOR" EXISTING_PR="https://github.com/o/r/pull/9" BRANCH="polecat/tk-anch1" \
  TARGET="main" reason="PR is CLOSED" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-existing-pr.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "EXISTINGPR: escalates through the gate"
eq "$(count mail)" "0" "EXISTINGPR: sends no bare mail"
eq "$(gate_arg --anchor)" "$ANCHOR" "EXISTINGPR: keys the stamp on the work bead"
eq "$(gate_arg --kind)" "refinery" "EXISTINGPR: on the refinery channel"
S="$(gate_arg --state)"
has "pull/9" "$S" "EXISTINGPR: fingerprints the offending existing_pr (a corrected one is news)"
has "main"   "$S" "EXISTINGPR: fingerprints the target (a retarget is news)"
has "PR is CLOSED" "$(gate_arg --body)" "EXISTINGPR: the reason reaches the body"

# --- SIGNOFFCAP: the convergence-cap escalation -------------------------------
reset
make_gate "$TMP/rig/assets/scripts"
GATING_ANCHOR="$ANCHOR" ROUNDS=3 BRANCH="polecat/tk-anch1" PR_NUMBER=55 \
  GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-signoff-cap.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "SIGNOFFCAP: escalates through the gate"
eq "$(count mail)" "0" "SIGNOFFCAP: sends no bare mail"
eq "$(gate_arg --anchor)" "$ANCHOR" "SIGNOFFCAP: keys the stamp on the gating anchor"
eq "$(gate_arg --kind)" "refinery" "SIGNOFFCAP: on the refinery channel"
has "3" "$(gate_arg --state)" "SIGNOFFCAP: the round count is in the fingerprint (another round is news)"
has "Rounds spent" "$(gate_arg --body)" "SIGNOFFCAP: the body survives intact"

# --- STRATEGYLOCAL: the unsupported-merge_strategy escalation -----------------
reset
make_gate "$TMP/rig/assets/scripts"
WORK="$ANCHOR" MERGE_STRATEGY="local" BRANCH="polecat/tk-anch1" TARGET="main" \
  GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-strategy-local.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "STRATEGYLOCAL: escalates through the gate"
eq "$(count mail)" "0" "STRATEGYLOCAL: sends no bare mail"
eq "$(gate_arg --anchor)" "$ANCHOR" "STRATEGYLOCAL: keys the stamp on the work bead"
has "local" "$(gate_arg --state)" "STRATEGYLOCAL: fingerprints the strategy (an edit to a supported one is news)"

# --- NOTIMESTAMP: no fingerprint may carry a clock ----------------------------
# A timestamp in --state re-opens the gate on the next pass no matter what, and
# the anchor's own updated_at is downstream of the gate's stamp. SELFREOPEN proves
# the held-anchor block; this catches the same mistake in the other three, whose
# fingerprints are built from shell variables rather than from a bead read.
for marker in escalation-wiring-existing-pr escalation-wiring-signoff-cap \
              escalation-wiring-strategy-local escalation-wiring-held-anchor; do
  blk="$(extract "$marker")"
  STATE_LINES=$(printf '%s\n' "$blk" | grep -c '^ *STATE=')
  [ "${STATE_LINES:-0}" -ge 1 ] && ok "NOTIMESTAMP: $marker builds a STATE fingerprint" \
    || bad "NOTIMESTAMP: $marker builds no STATE — the gate would dedup on the cooldown alone"
  # `date +`, not a bare `%s`: a fingerprint built with `printf '%s'` from a bead
  # read is the correct shape and must not trip this.
  BADFIELD=$(printf '%s\n' "$blk" | grep '^ *STATE=' | grep -c 'updated_at\|date +\|EPOCHSECONDS')
  [ "${BADFIELD:-0}" -eq 0 ] \
    && ok "NOTIMESTAMP: $marker keeps clocks out of the fingerprint" \
    || bad "NOTIMESTAMP: $marker puts a timestamp in --state — the gate's own stamp then re-opens it every pass"
done

# --- PROPAGATE: every wisp pour must carry the cooldown to the next iteration --
# Passing --cooldown only makes the configured value good for ONE cycle. Each wisp
# is one iteration, and every exit path pours the next one `--root-only` — which
# materializes no formula defaults — so a pour that drops the var hands the next
# wisp an unrendered placeholder and every later cycle silently runs the script's
# own 86400 fallback instead. A setting that survives only the first cycle is not a
# setting, and nothing about it looks broken from the outside: the gate still runs,
# still dedups, just on the wrong number. This formula pours from FIVE places
# (the bootstrap in the header plus four exit paths), so it is checked by count,
# not by marker — a sixth pour added later without the var fails here.
POURS=$(grep -c 'gc bd mol wisp mol-refinery-patrol --root-only' "$TOML")
[ "${POURS:-0}" -ge 1 ] && ok "PROPAGATE: found $POURS wisp pour(s) in $TOML" \
  || bad "PROPAGATE: found no 'gc bd mol wisp mol-refinery-patrol --root-only' — the check below would be vacuous"
WITH_VAR=$(grep 'gc bd mol wisp mol-refinery-patrol --root-only' "$TOML" \
           | grep -c -- '--var escalation_cooldown={{escalation_cooldown}}')
eq "${WITH_VAR:-0}" "${POURS:-0}" \
   "PROPAGATE: every pour forwards escalation_cooldown (a --root-only wisp materializes no defaults)"
# The value must be the placeholder, not a literal: hardcoding the default here
# would freeze every downstream cycle at that number no matter what the bootstrap
# set, which is the same bug wearing a plausible-looking fix.
HARDCODED=$(grep 'gc bd mol wisp mol-refinery-patrol --root-only' "$TOML" \
            | grep -c -- '--var escalation_cooldown=[0-9]')
eq "${HARDCODED:-0}" "0" "PROPAGATE: no pour hardcodes a cooldown value in place of the placeholder"

# --- ALLOWLIST: no NEW ungated bead-scoped mail may appear in the formula ------
# The discipline section states the rule; this enforces it. Every `gc mail send`
# in the file must be inside a gated `escalation-wiring-*` block (where it is the
# documented fallback arm) or be the one escalation that has no bead to key a
# stamp on. A second bare bead-scoped mail is a new storm channel, and it is
# exactly the kind of thing that gets added later by someone reading the OTHER
# examples in this file.
ALLOWED_1='ESCALATION: refinery started with empty GC_AGENT'  # fires before any bead is selected; exits the session
UNGATED=0
while IFS='	' read -r ln inblock content; do
  [ -n "$ln" ] || continue
  [ "$inblock" = "1" ] && continue
  case "$content" in
    *"$ALLOWED_1"*) continue ;;
  esac
  UNGATED=$((UNGATED + 1))
  bad "ALLOWLIST: ungated bead-scoped 'gc mail send' at $TOML:$ln — route it through escalation-gate.sh (or add it to the allowlist with a reason)"
done <<EOF
$(awk '
  /^ *# >>> escalation-wiring-/ {inblock=1}
  /^ *# <<< escalation-wiring-/ {inblock=0; next}
  # Match the call ANYWHERE on the line, not just at its start: a send is just as
  # ungated when it is a conditional or a chained clause, and an anchored scan
  # reports those as clean. Prose quotes commands in backticks and the discipline
  # section is full of it, so strip backtick-quoted spans from a COPY of the line
  # first (the report still shows the original). A prose mention outside backticks
  # would false-positive, which is the right way to be wrong here: it is loud and
  # one allowlist entry fixes it, while a missed call is a silent storm channel.
  {
    code = $0
    gsub(/`[^`]*`/, "", code)
    if (code ~ /gc mail send/) printf "%d\t%d\t%s\n", NR, inblock, $0
  }
' "$TOML")
EOF
[ "$UNGATED" -eq 0 ] && ok "ALLOWLIST: every bead-scoped 'gc mail send' goes through the gate"
# A stale allowlist entry hides nothing but rots, so require it to still match.
grep -qF "$ALLOWED_1" "$TOML" \
  && ok "ALLOWLIST: exception still present in the formula ($ALLOWED_1)" \
  || bad "ALLOWLIST: exception no longer exists — drop it from the list ($ALLOWED_1)"

# --- DEFAULTDRIFT: the two cooldown defaults must agree -----------------------
# `[vars.escalation_cooldown] default` is what the formula documents and renders
# as Config; DEFAULT_COOLDOWN is what actually governs whenever the var reaches
# the script unrendered — which is the common case on a --root-only pour. If they
# drift, the documented value is a lie in exactly the situation nobody tests.
TOML_COOLDOWN=$(awk '/^\[vars\.escalation_cooldown\]/{f=1; next} f && /^default =/{gsub(/[^0-9]/, "", $0); print; exit}' "$TOML")
SCRIPT_COOLDOWN=$(grep -oE '^DEFAULT_COOLDOWN=[0-9]+' "$HERE/escalation-gate.sh" | cut -d= -f2)
[ -n "$TOML_COOLDOWN" ] && ok "DEFAULTDRIFT: found the formula's escalation_cooldown default" \
  || bad "DEFAULTDRIFT: could not read [vars.escalation_cooldown] default from $TOML"
[ -n "$SCRIPT_COOLDOWN" ] && ok "DEFAULTDRIFT: found the script's DEFAULT_COOLDOWN" \
  || bad "DEFAULTDRIFT: could not read DEFAULT_COOLDOWN from escalation-gate.sh"
eq "$SCRIPT_COOLDOWN" "$TOML_COOLDOWN" "DEFAULTDRIFT: script default matches the formula's documented default"

echo
echo "refinery-escalation-wiring.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
