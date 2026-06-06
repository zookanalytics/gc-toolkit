#!/usr/bin/env bash
# Hermetic test for reconcile-rig-checkouts.sh.
#
# Uses real temp git repos as stand-in rigs and a fake `gc` (a text-file bead
# ledger) on PATH. No dependency on the live city, Dolt, the mayor, or the
# network. Covers: (a) a clean-behind rig advances; (b) a diverged rig is NOT
# mutated and produces exactly one mayor escalation; (c) a re-run does not
# duplicate it; (d) the escalation auto-closes once the rig ff-s cleanly;
# (e) the HQ root is excluded.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-rig-checkouts.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

commit() { echo "$2" > "$1/f.txt"; git -C "$1" add -A; git -C "$1" commit -qm "$2"; }
# count OPEN escalation beads in the fake ledger for a given rig key.
open_count() { awk -F'|' -v k="$1" '$2==k && $3=="open"' "$TMP/ledger" 2>/dev/null | wc -l | tr -d ' '; }

# --- Build a remote with two commits, then derive three checkouts. ----------
SRC="$TMP/src"; git init -q -b main "$SRC"; commit "$SRC" c1; commit "$SRC" c2
git clone -q --bare "$SRC" "$TMP/remote.git"

git clone -q "$TMP/remote.git" "$TMP/alpha"            # clean-behind: rewind to c1
git -C "$TMP/alpha" reset --hard -q HEAD~1
git clone -q "$TMP/remote.git" "$TMP/beta"             # diverged: own commit on c2
commit "$TMP/beta" c3-local
BETA_DIVERGED="$(git -C "$TMP/beta" rev-parse HEAD)"
git clone -q "$TMP/remote.git" "$TMP/hqrepo"           # diverged too, but is HQ -> skipped
commit "$TMP/hqrepo" c3-hq

commit "$SRC" c3-remote                                # advance the remote past c2
git -C "$SRC" push -q "$TMP/remote.git" main
REMOTE_HEAD="$(git -C "$TMP/remote.git" rev-parse main)"

# --- Fake gc + rig list (only the surface the script touches). ---------------
mkdir -p "$TMP/bin"
cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"loomington","path":"$TMP/hqrepo","hq":true},
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"}
]}
JSON
: > "$TMP/ledger"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1" in
  rig) cat "$FAKE_RIGS_JSON" ;;
  bd)
    shift; [ "$1" = "--rig" ] && shift 2; sub="$1"; shift
    case "$sub" in
      list)
        key=""; while [ $# -gt 0 ]; do [ "$1" = "--metadata-field" ] && key="${2#reconcile_rig=}"; shift; done
        id=$(awk -F'|' -v k="$key" '$2==k && $3=="open"{print $1; exit}' "$FAKE_LEDGER" 2>/dev/null)
        [ -n "$id" ] && printf '[{"id":"%s"}]\n' "$id" || printf '[]\n' ;;
      create)
        n=$(( $(wc -l < "$FAKE_LEDGER" 2>/dev/null || echo 0) + 1 )); id="esc-$n"
        printf '%s||open\n' "$id" >> "$FAKE_LEDGER"; printf '{"id":"%s"}\n' "$id" ;;
      update)
        id="$1"; shift; key=""
        while [ $# -gt 0 ]; do [ "$1" = "--set-metadata" ] && key="${2#reconcile_rig=}"; shift; done
        [ -n "$key" ] && sed -i "s/^${id}|[^|]*|/${id}|${key}|/" "$FAKE_LEDGER" ;;
      close) sed -i "s/^\($1\)|\([^|]*\)|open/\1|\2|closed/" "$FAKE_LEDGER" ;;
    esac ;;
  session) : ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" FAKE_RIGS_JSON="$TMP/rigs.json" FAKE_LEDGER="$TMP/ledger"

# --- Run 1: alpha advances, beta escalates, hq is skipped. -------------------
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/alpha" rev-parse HEAD)" "$REMOTE_HEAD" "clean-behind rig advances to origin"
eq "$(git -C "$TMP/beta"  rev-parse HEAD)" "$BETA_DIVERGED" "diverged rig is not mutated"
git -C "$TMP/beta" log --oneline | grep -q c3-local && ok "diverged rig keeps local commit" || bad "diverged rig keeps local commit"
eq "$(open_count beta)"  "1" "diverged rig produces exactly one escalation"
eq "$(open_count alpha)" "0" "advanced rig produces no escalation"
eq "$(open_count loomington)" "0" "HQ root is excluded (not reconciled)"

# --- Run 2: idempotent — no duplicate escalation. ----------------------------
bash "$SCRIPT" >/dev/null
eq "$(open_count beta)" "1" "re-run does not duplicate the escalation"

# --- Run 3: rig resolved -> escalation auto-closes. --------------------------
git -C "$TMP/beta" reset --hard -q origin/main
bash "$SCRIPT" >/dev/null
eq "$(open_count beta)" "0" "escalation auto-closes after a clean fast-forward"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
