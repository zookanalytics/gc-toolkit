#!/usr/bin/env bash
# Hermetic test for the FIRST-ROUND signoff dispatch carrying the review method
# (tk-dy7sb, formulas/mol-refinery-patrol.toml merge-push step 3).
#
# The defect: the dispatch that mints most review beads created them with
# `gc bd create "$REVIEW_TITLE" -t task` — a title and routing metadata, no
# description. The method emitter (assets/scripts/review-dispatch-body.sh, tk-jufvl)
# existed and was wired into the two REPAIR paths only (check-set-heal.sh,
# reconcile-merged-prs.sh), so the path that files the reviews never called it:
# 45 of the 60 most recent review beads in this rig carried an empty description.
# A reviewer handed a bare title picks its own method by catalog description-match
# — the drift that ran a 6-persona fan-out at ~4.7M tokens per review.
#
# The fix under test: resolve the emitter from agent-env paths, capture its
# output, and pass it as the created bead's body — FAIL-SOFT, because an
# un-dispatched signoff leaves the armed gate unsatisfiable and HOLDS the merge
# forever, which is strictly worse than a title-only bead.
#
# This EXECUTES the real snippet extracted verbatim from the formula (between the
# first-round-review-body markers) against a fake `gc` and a fake `git`, so it
# cannot drift from the shipped instruction. No live city, Dolt, network, or PRs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: records every `gc bd create`, and captures the body when one is
#     passed on stdin via --body-file -. Recording per-create is what lets the
#     assertions prove the dispatch names a method instead of shipping a bare
#     title. Mirrors the real command's contract: JSON with an id on stdout.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] && [ "$2" = "create" ] || exit 0
n=$(cat "$FAKE_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$FAKE_SEQ"
if grep -q -- '--body-file -' <<< "$*"; then
  printf 'rev-%s\tbody\n' "$n" >> "$FAKE_CREATES"
  cat > "$FAKE_BODY_DIR/rev-$n" 2>/dev/null || true
else
  printf 'rev-%s\ttitle-only\n' "$n" >> "$FAKE_CREATES"
fi
printf '%s\n' "$3" >> "$FAKE_TITLES"
printf '{"id":"rev-%s"}\n' "$n"
GC
chmod +x "$TMP/bin/gc"

# --- git stub: the snippet's second resolution candidate is
#     `$(git rev-parse --show-toplevel)/assets/scripts`. Stubbed so the test
#     controls it — unstubbed, the real toplevel is THIS repo, whose real
#     assets/scripts always holds the emitter, and the missing-emitter case
#     below could never be reached.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = "rev-parse" ] && [ "$2" = "--show-toplevel" ]; then
  [ -n "${FAKE_TOPLEVEL:-}" ] || exit 128
  printf '%s\n' "$FAKE_TOPLEVEL"; exit 0
fi
exit 0
GIT
chmod +x "$TMP/bin/git"

export PATH="$TMP/bin:$PATH"
export FAKE_SEQ="$TMP/seq" FAKE_CREATES="$TMP/creates" FAKE_TITLES="$TMP/titles"
export FAKE_BODY_DIR="$TMP/bodies"
mkdir -p "$FAKE_BODY_DIR"

# --- Extract the REAL dispatch snippet from the formula. ----------------------
SNIPPET="$(awk '
  /# >>> first-round-review-body/ {f=1; next}
  /# <<< first-round-review-body/ {f=0}
  f' "$TOML")"

[ -n "$SNIPPET" ] \
  && ok "(0) dispatch snippet extracted between first-round-review-body markers" \
  || bad "(0) snippet extraction EMPTY — markers missing from $TOML"

# The formula step description is a TOML basic multi-line string, where a
# line-ending backslash is an ESCAPE: it joins the two lines (dropping the
# newline and the next line's indent) before the agent ever sees the text. This
# test executes the RAW file text, so a backslash here means the two forms
# diverge and the assertions below stop covering what actually runs.
grep -q '\\' <<< "$SNIPPET" \
  && bad "(0b) snippet contains a backslash — TOML joins that line, so the executed text differs from the tested text" \
  || ok "(0b) snippet is backslash-free (rendered TOML text == the text this test runs)"

# `set -u` is deliberate: the snippet must be safe under a strict shell (an
# unguarded expansion here would kill the whole merge-push step, not just the
# dispatch).
{ printf 'set -u\n'; printf '%s\n' "$SNIPPET"; printf 'printf "BEAD=%%s\\n" "$REVIEW_BEAD"\n'; } > "$TMP/run.sh"

# dispatch <rig_root> <toplevel> <city_path> -> echoes the created bead id;
# stderr lands in $TMP/err, the per-run create log in $TMP/creates.
#
# The snippet's exit status goes to $TMP/rc rather than a variable: callers run
# this inside a command substitution, so anything assigned here dies with the
# subshell. It is asserted per-case below — a fail-soft arm that took the
# merge-push step down with it would be no better than the fail-stop it replaces.
dispatch() {
  : > "$FAKE_CREATES"; : > "$FAKE_TITLES"; rm -f "$FAKE_BODY_DIR"/*
  local rc=0
  GC_RIG_ROOT="$1" FAKE_TOPLEVEL="$2" GC_CITY_PATH="$3" \
    REVIEW_TITLE="Review PR#412: a change" \
    bash "$TMP/run.sh" > "$TMP/out" 2> "$TMP/err" || rc=$?
  printf '%s' "$rc" > "$TMP/rc"
  sed -n 's/^BEAD=//p' "$TMP/out" | tail -1
}
rc_is_zero() { eq "$(cat "$TMP/rc")" "0" "$1"; }

# --- Fixture emitters. -------------------------------------------------------
# (a) a stub emitter with a recognisable payload, under a fake rig root
mkdir -p "$TMP/rig/assets/scripts"
cat > "$TMP/rig/assets/scripts/review-dispatch-body.sh" <<'E'
#!/usr/bin/env bash
echo "## Review method (stub payload from RIG_ROOT)"
E
chmod +x "$TMP/rig/assets/scripts/review-dispatch-body.sh"

# (b) a distinguishable second emitter, under a fake git toplevel — proves which
#     candidate wins when more than one resolves
mkdir -p "$TMP/top/assets/scripts"
cat > "$TMP/top/assets/scripts/review-dispatch-body.sh" <<'E'
#!/usr/bin/env bash
echo "## Review method (stub payload from TOPLEVEL)"
E
chmod +x "$TMP/top/assets/scripts/review-dispatch-body.sh"

# (c) an emitter that FAILS — the `|| REVIEW_BODY=""` arm
mkdir -p "$TMP/broken/assets/scripts"
cat > "$TMP/broken/assets/scripts/review-dispatch-body.sh" <<'E'
#!/usr/bin/env bash
echo "review-dispatch-body: exploded" >&2
exit 3
E
chmod +x "$TMP/broken/assets/scripts/review-dispatch-body.sh"

# (d) an emitter that succeeds but prints NOTHING — an empty body must be
#     treated as no method, not dispatched as one
mkdir -p "$TMP/silent/assets/scripts"
cat > "$TMP/silent/assets/scripts/review-dispatch-body.sh" <<'E'
#!/usr/bin/env bash
exit 0
E
chmod +x "$TMP/silent/assets/scripts/review-dispatch-body.sh"

# (e) nowhere to resolve from
mkdir -p "$TMP/empty"

# --- (1) Emitter present: the create carries a non-empty body. ----------------
BEAD=$(dispatch "$TMP/rig" "" "$TMP/empty")
eq "$BEAD" "rev-1" "(1) emitter present -> a review bead is still minted"
rc_is_zero "(1) the wired dispatch exits clean under set -u"
grep -q '^rev-1	body$' "$FAKE_CREATES" \
  && ok "(1) the create carries a body (--body-file -), not a bare title" \
  || bad "(1) create must carry the emitted body (got: $(cat "$FAKE_CREATES"))"
[ -s "$FAKE_BODY_DIR/rev-1" ] \
  && ok "(1) the dispatched body is NON-EMPTY — this is the regression that files title-only beads" \
  || bad "(1) dispatched body must be non-empty"
grep -q 'stub payload from RIG_ROOT' "$FAKE_BODY_DIR/rev-1" \
  && ok "(1) the body is the emitter's own output (the method, not improvised prose)" \
  || bad "(1) body must be the emitter's output (got: $(cat "$FAKE_BODY_DIR/rev-1" 2>/dev/null))"
grep -q 'TITLE-ONLY' "$TMP/err" \
  && bad "(1) must not WARN when the method was emitted" \
  || ok "(1) no WARN on the happy path"
grep -q '^Review PR#412: a change$' "$FAKE_TITLES" \
  && ok "(1) the title is unchanged — the body is added, nothing is displaced" \
  || bad "(1) title must still be \$REVIEW_TITLE (got: $(cat "$FAKE_TITLES"))"

# --- (2) Resolution precedence: GC_RIG_ROOT wins over the git toplevel. -------
#     Both candidates resolve here; an importer rig relies on the LAST candidate,
#     so the order has to be the documented one rather than whichever happens to
#     exist on the box that ran the test.
dispatch "$TMP/rig" "$TMP/top" "$TMP/empty" >/dev/null
grep -q 'stub payload from RIG_ROOT' "$FAKE_BODY_DIR/rev-2" \
  && ok "(2) GC_RIG_ROOT/assets/scripts is preferred over the git toplevel" \
  || bad "(2) first candidate must win (got: $(cat "$FAKE_BODY_DIR/rev-2" 2>/dev/null))"

# --- (3) Importer-rig fallback: only GC_CITY_PATH resolves. -------------------
#     signal-loom, gascity and shutupandlisten import this pack; their agents
#     find the emitter at <city>/rigs/gc-toolkit, and nowhere else.
mkdir -p "$TMP/city/rigs/gc-toolkit/assets/scripts"
cp "$TMP/rig/assets/scripts/review-dispatch-body.sh" "$TMP/city/rigs/gc-toolkit/assets/scripts/"
dispatch "$TMP/empty" "" "$TMP/city" >/dev/null
grep -q '^rev-3	body$' "$FAKE_CREATES" \
  && ok "(3) importer rigs resolve the emitter under GC_CITY_PATH/rigs/gc-toolkit" \
  || bad "(3) third candidate must resolve for importer rigs (got: $(cat "$FAKE_CREATES"))"

# --- (4) FAIL-SOFT, emitter missing: the dispatch STILL happens. --------------
#     An un-dispatched signoff leaves the armed gate unsatisfiable and holds the
#     merge forever. A missing emitter degrades to today's behaviour, loudly.
BEAD=$(dispatch "$TMP/empty" "" "$TMP/empty")
eq "$BEAD" "rev-4" "(4) a missing emitter does NOT suppress the dispatch (the gate stays satisfiable)"
rc_is_zero "(4) a missing emitter does not fail the merge-push step"
grep -q '^rev-4	title-only$' "$FAKE_CREATES" \
  && ok "(4) missing emitter -> title-only create, exactly as before this wiring" \
  || bad "(4) missing emitter must fall back to a title-only create (got: $(cat "$FAKE_CREATES"))"
grep -q 'TITLE-ONLY' "$TMP/err" \
  && ok "(4) WARNs loudly that the dispatch carries no method" \
  || bad "(4) missing emitter must WARN (got: $(cat "$TMP/err"))"
grep -q 'review-dispatch-body' "$TMP/err" \
  && ok "(4) the WARN names the emitter it could not find" \
  || bad "(4) WARN must name the emitter (got: $(cat "$TMP/err"))"

# --- (5) FAIL-SOFT, emitter fails. -------------------------------------------
BEAD=$(dispatch "$TMP/broken" "" "$TMP/empty")
eq "$BEAD" "rev-5" "(5) an emitter that exits non-zero does not abort the dispatch"
rc_is_zero "(5) an emitter that exits non-zero does not fail the merge-push step"
grep -q '^rev-5	title-only$' "$FAKE_CREATES" \
  && ok "(5) a failing emitter degrades to title-only" \
  || bad "(5) failing emitter must degrade to title-only (got: $(cat "$FAKE_CREATES"))"
grep -q 'TITLE-ONLY' "$TMP/err" \
  && ok "(5) a failing emitter WARNs" \
  || bad "(5) failing emitter must WARN (got: $(cat "$TMP/err"))"

# --- (6) FAIL-SOFT, emitter emits nothing. -----------------------------------
#     `gc bd create --body-file -` on empty stdin is the case this arm exists to
#     avoid: it would file the same empty description the wiring is fixing, but
#     silently, with no WARN to show the method never arrived.
BEAD=$(dispatch "$TMP/silent" "" "$TMP/empty")
eq "$BEAD" "rev-6" "(6) an emitter that prints nothing does not abort the dispatch"
rc_is_zero "(6) an empty emission does not fail the merge-push step"
grep -q '^rev-6	title-only$' "$FAKE_CREATES" \
  && ok "(6) an empty body is treated as NO method (never dispatched as one)" \
  || bad "(6) empty body must degrade to title-only (got: $(cat "$FAKE_CREATES"))"
grep -q 'TITLE-ONLY' "$TMP/err" \
  && ok "(6) an empty emission WARNs" \
  || bad "(6) empty emission must WARN (got: $(cat "$TMP/err"))"

# --- (7) Against the REAL shipped emitter. -----------------------------------
#     Cases 1-6 run stubs, which prove the wiring's shape but would pass just as
#     well if the shipped emitter were unreadable, non-executable, or silent on
#     this box. This one points the FIRST candidate at the real pack.
[ -x "$ROOT/assets/scripts/review-dispatch-body.sh" ] \
  && ok "(7) the shipped emitter exists and is executable (a non-executable deploy is a silent title-only regression)" \
  || bad "(7) assets/scripts/review-dispatch-body.sh must be executable"
dispatch "$ROOT" "" "$TMP/empty" >/dev/null
grep -q '^rev-7	body$' "$FAKE_CREATES" \
  && ok "(7) the REAL emitter feeds the real dispatch — a live first-round review carries a method" \
  || bad "(7) real emitter must produce a body (stderr: $(cat "$TMP/err"))"
grep -qi 'review' "$FAKE_BODY_DIR/rev-7" 2>/dev/null \
  && ok "(7) the real dispatched body reads as a review method" \
  || bad "(7) real body must contain the review method"

# --- (8) Static: the wiring is on the FIRST-ROUND path, not a repair path. ----
#     The markers must sit in the `elif [ -z "$EXISTING_REVIEW" ]` arm that both
#     the PRE_OPEN (branch) and post-open (PR) dispatches funnel through — the
#     one create this bead exists to feed. If it moves out from under that arm,
#     the dedup is bypassed and every refinery pass mints a twin review.
M_START=$(grep -n '# >>> first-round-review-body' "$TOML" | head -1 | cut -d: -f1)
M_END=$(grep -n '# <<< first-round-review-body' "$TOML" | head -1 | cut -d: -f1)
ELIF_LINE=$(grep -n 'elif \[ -z "\$EXISTING_REVIEW" \]; then' "$TOML" | head -1 | cut -d: -f1)
ANCHOR_LINE=$(grep -n -- '--set-metadata anchor_bead="\$GATING_ANCHOR"' "$TOML" | head -1 | cut -d: -f1)
{ [ -n "$M_START" ] && [ -n "$M_END" ] && [ -n "$ELIF_LINE" ] && [ -n "$ANCHOR_LINE" ] \
  && [ "$M_START" -gt "$ELIF_LINE" ] && [ "$M_END" -lt "$ANCHOR_LINE" ]; } \
  && ok "(8) the wiring sits inside the first-round dispatch arm, ahead of the routing stamp" \
  || bad "(8) wiring must sit between the EXISTING_REVIEW elif and the routing stamp (elif=$ELIF_LINE start=$M_START end=$M_END stamp=$ANCHOR_LINE)"

# The formula must hold exactly ONE `gc bd create` for the signoff review, and it
# must be inside the markers: a second one outside them is a title-only dispatch
# that this test would never see.
CREATES_OUTSIDE=$(awk -v s="$M_START" -v e="$M_END" '
  NR > s && NR < e { next }
  /REVIEW_BEAD=\$\(gc bd create/ { print NR }' "$TOML")
[ -z "$CREATES_OUTSIDE" ] \
  && ok "(8) no second review-bead create outside the wired arm" \
  || bad "(8) a review-bead create escapes the wiring at line(s): $CREATES_OUTSIDE"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
