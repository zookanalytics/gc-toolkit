#!/usr/bin/env bash
# memory-intake.test.sh — the memory intake places each memory directory as
# Claude Code does, lists the due notes oldest first, records and removes
# what the judge decided under its checks, ends each wait that is done,
# keeps the index and collection notes free of links to gone notes, writes
# the guidance block, and reports a place it cannot resolve.
#
# Hermetic: a stub gc answers the rig list and each store's beads from files,
# a stub gh answers a PR's state, and a stub patrol-finding.sh logs what it is
# asked to file. Stub cp and mkdir, put on the path for one run, land an
# agent's edit while a unit is being removed. Each case builds its own city,
# home and memory directories in a sandbox, and the clock is fixed through
# MEMORY_INTAKE_NOW.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/memory-intake.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

for t in jq git flock; do command -v "$t" >/dev/null 2>&1 || { echo "$t is required for this test" >&2; exit 2; }; done
# touch -t reads its stamp in the local zone, and the ages below are UTC.
export TZ=UTC
unset "${!GC_@}" "${!BEADS_@}" "${!CLAUDE_@}" MEMORY_INTAKE_STATE MEMORY_INTAKE_NOW
SB="$(mktemp -d "${TMPDIR:-/tmp}/gctk-memory-intake-test.XXXXXX")" || exit 2
SB="$(cd -P "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT

# ── stubs ──────────────────────────────────────────────────────────────────
mkdir -p "$SB/bin"
cat > "$SB/bin/gc" <<'STUB'
#!/usr/bin/env bash
# gc rig list --json, and gc bd -C <store> show|dep list against <store>/beads.json.
case "$1 $2" in
  "rig list") cat "$STUB_RIGS"; exit 0 ;;
  "bd -C") store=$3; shift 3 ;;
  *) echo "stub gc: $*" >&2; exit 1 ;;
esac
f="$store/beads.json"
[ -f "$f" ] || { echo "stub gc: no store at $store" >&2; exit 1; }
case "$1" in
  show)
    shift; ids=()
    for a in "$@"; do case "$a" in --*) ;; *) ids+=("$a") ;; esac; done
    out=$(jq -c --args '[.[] | select(.id as $i | $ARGS.positional | index($i))]' "${ids[@]}" < "$f")
    if [ "$out" = "[]" ]; then echo '{"error": "no issues found matching the provided IDs"}'; exit 1; fi
    printf '%s\n' "$out" ;;
  dep)
    [ -z "${STUB_DEP_FAIL:-}" ] || { echo '{"error": "the store did not answer"}'; exit 1; }
    jq -c --arg id "$3" '(.[] | select(.id == $id) | .deps // []) as $d
      | [.[] | select(.id as $i | $d | index($i)) | . + {dependency_type: "blocks"}]' "$f" ;;
  *) echo "stub gc: bd $*" >&2; exit 1 ;;
esac
STUB
cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
# gh pr view <url> --json state,baseRefName -q ... against $STUB_PRS.
[ "$1 $2" = "pr view" ] || exit 1
jq -er --arg u "$3" '.[$u] | .state + " " + .baseRefName' "$STUB_PRS"
STUB
cat > "$SB/bin/pf" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_FINDINGS"
STUB
chmod +x "$SB/bin/gc" "$SB/bin/gh" "$SB/bin/pf"
mkdir -p "$SB/edit-bin"
cat > "$SB/edit-bin/cp" <<'STUB'
#!/usr/bin/env bash
# cp or mkdir by its name. When STUB_EDIT_AT names it and the call reaches a
# removed/ directory, it then makes, once, the edit an agent makes to $STUB_EDIT.
command -p "${0##*/}" "$@"; rc=$?
if [ "${0##*/}" = "${STUB_EDIT_AT:-}" ] && [ ! -e "$STUB_EDIT.fired" ]; then
  case "${*: -1}" in
    */removed|*/removed/*) printf 'An edit made while it was being removed.\n' >> "$STUB_EDIT"; : > "$STUB_EDIT.fired" ;;
  esac
fi
exit "$rc"
STUB
cp "$SB/edit-bin/cp" "$SB/edit-bin/mkdir"
chmod +x "$SB/edit-bin/cp" "$SB/edit-bin/mkdir"
export PATH="$SB/bin:$ROOT/tools/test-floor:$PATH"
export GC_PATROL_FINDING_TOOL="$SB/bin/pf"
export MEMORY_INTAKE_MANAGED_SETTINGS="$SB/managed.json"
export MEMORY_INTAKE_NOW=1794744000   # 2026-11-15T12:00:00Z
export STUB_PRS="$SB/prs.json"; echo '{}' > "$STUB_PRS"

mkdir -p "$SB/home-rig" "$SB/other-rig"
git -C "$SB/home-rig" init -q && printf 'name = "gc-toolkit"\n' > "$SB/home-rig/pack.toml"
git -C "$SB/other-rig" init -q && printf 'name = "other"\n' > "$SB/other-rig/pack.toml"

# city <name> — a fresh city: its root, home, rig list and logs, under $B.
city() {
  B="$SB/$1"
  mkdir -p "$B/city/.gc" "$B/home/.claude/projects" "$B/rigs"
  export HOME="$B/home" GC_CITY_PATH="$B/city" STUB_RIGS="$B/rigs.json" STUB_FINDINGS="$B/findings.log"
  : > "$STUB_FINDINGS"
  jq -n --arg c "$B/city" '{rigs: [{name: "town", path: $c, hq: true, prefix: "lx"}]}' > "$STUB_RIGS"
  STATE="$B/city/.gc/runtime/packs/gc-toolkit/memory-intake"
}
# rig <name> <prefix> — adds a rig whose checkout is $B/rigs/<name>.
rig() {
  mkdir -p "$B/rigs/$1"
  jq --arg n "$1" --arg p "$B/rigs/$1" --arg x "$2" '.rigs += [{name: $n, path: $p, prefix: $x}]' "$STUB_RIGS" > "$STUB_RIGS.next" \
    && mv "$STUB_RIGS.next" "$STUB_RIGS"
}
conv() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9' '-'; }
# memdir <checkout> — the default memory directory for a checkout, made.
memdir() { local d; d="$HOME/.claude/projects/$(conv "$1")/memory"; mkdir -p "$d"; printf '%s' "$d"; }
# run <verb> [args] — the script from the home rig; OUT, ERR and RC.
run() {
  OUT=$(cd "$SB/home-rig" && "$SUT" "$@" 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err")
}
apply_lines() { OUT=$(cd "$SB/home-rig" && printf '%s\n' "$@" | "$SUT" apply - 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err"); }
due_json() { (cd "$SB/home-rig" && "$SUT" due "$@" 2>/dev/null); }
ref_of() { due_json | jq -r --arg n "$1" '[.[] | select(.memory_file | endswith("/" + $n))][0].memory_ref // ""'; }
setting() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
# origin_head <rig> <branch> — makes the rig's checkout a repository whose
# origin/HEAD names <branch>, as a clone records its default branch.
origin_head() { git -C "$B/rigs/$1" init -q && git -C "$B/rigs/$1" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$2"; }

# ── placement: each input that moves a directory or turns memory off ───────
echo "── placement ──"
city place
for r in plain nodir localdir projdir reldir badjson blocked tracked untracked linked off offon; do rig "$r" tk; done
rig "$(printf 'l%.0s' $(seq 1 210))" tk
LONG="$(printf 'l%.0s' $(seq 1 210))"
memdir "$B/rigs/plain" >/dev/null; memdir "$B/rigs/offon" >/dev/null; memdir "$B/rigs/off" >/dev/null
mkdir -p "$B/mem/localdir" "$HOME/mem/projdir" "$B/mem/untracked" "$B/mem/tracked" "$B/mem/blocked"
setting "$B/rigs/localdir/.claude/settings.local.json" "{\"autoMemoryDirectory\": \"$B/mem/localdir\"}"
setting "$B/rigs/projdir/.claude/settings.json" '{"autoMemoryDirectory": "~/mem/projdir"}'
setting "$B/rigs/reldir/.claude/settings.json" '{"autoMemoryDirectory": "mem/rel"}'
setting "$B/rigs/badjson/.claude/settings.json" '{"autoMemoryDirectory": '
setting "$B/rigs/blocked/.claude/settings.json" "{\"autoMemoryDirectory\": \"$B/mem/blocked\", \"permissions\": {\"blockReadsOutsideWorkingDirectories\": true}}"
for r in tracked untracked; do
  git -C "$B/rigs/$r" init -q
  setting "$B/rigs/$r/.claude/settings.local.json" "{\"autoMemoryDirectory\": \"$B/mem/$r\", \"permissions\": {\"blockReadsOutsideWorkingDirectories\": true}}"
done
git -C "$B/rigs/tracked" add .claude/settings.local.json
mkdir -p "$B/linked-claude"
setting "$B/linked-claude/settings.local.json" "{\"autoMemoryDirectory\": \"$B/mem/untracked\", \"permissions\": {\"blockReadsOutsideWorkingDirectories\": true}}"
ln -s "$B/linked-claude" "$B/rigs/linked/.claude"
setting "$B/rigs/off/.claude/settings.json" '{"autoMemoryEnabled": false}'
setting "$B/rigs/offon/.claude/settings.json" '{"autoMemoryEnabled": false}'
setting "$B/rigs/offon/.claude/settings.local.json" '{"autoMemoryEnabled": true}'
run read
eq "$RC" 0 "read exits 0 with places it cannot resolve"
has "$OUT" "plain: $HOME/.claude/projects/$(conv "$B/rigs/plain")/memory (named for the checkout)" "a checkout's directory is named for its path"
has "$OUT" "nodir: absent: no directory there" "nothing at the place is an absent directory"
has "$OUT" "localdir: $B/mem/localdir (autoMemoryDirectory in the local settings)" "the local settings move it"
has "$OUT" "projdir: $HOME/mem/projdir (autoMemoryDirectory in the project settings)" "a ~/ value sits under the home"
has "$OUT" "reldir: cannot place it: autoMemoryDirectory \"mem/rel\" in the project settings is neither" "a relative value cannot be resolved"
has "$OUT" "badjson: cannot place it: $B/rigs/badjson/.claude/settings.json does not parse" "settings that do not parse cannot be resolved"
has "$OUT" "blocked: cannot place it: the project settings the repository supplies place the directory while permissions.blockReadsOutsideWorkingDirectories is on" "shared project settings under the read block cannot be resolved"
has "$OUT" "tracked: cannot place it: the local settings the repository supplies" "tracked local settings under the read block cannot be resolved"
has "$OUT" "untracked: $B/mem/untracked (autoMemoryDirectory in the local settings)" "untracked local settings place it under the read block"
has "$OUT" "linked: cannot place it: the local settings the repository supplies" "local settings under a linked .claude are the repository's"
has "$OUT" "off: absent: memory is off: autoMemoryEnabled is false" "autoMemoryEnabled false turns it off"
has "$OUT" "offon: $HOME/.claude/projects/$(conv "$B/rigs/offon")/memory (named for the checkout)" "a higher level's autoMemoryEnabled wins"
has "$OUT" "$LONG: cannot place it: the checkout path converts to" "a converted path past 200 characters cannot be resolved"
FOUND=$(grep -o -- '--key [^ ]*' "$STUB_FINDINGS" | LC_ALL=C sort | tr '\n' ' ')
WANT=$(printf -- '--key memory-intake.rig-%s\n' "$LONG" badjson blocked linked reldir tracked | LC_ALL=C sort | tr '\n' ' ')
eq "$FOUND" "$WANT" "one finding for each place it cannot resolve"
has "$(grep -- 'rig-reldir' "$STUB_FINDINGS")" "--scope memory-intake" "the finding is the intake's"
setting "$B/rigs/reldir/.claude/settings.json" "{\"autoMemoryDirectory\": \"$B/mem/rel\"}"; mkdir -p "$B/mem/rel"
: > "$STUB_FINDINGS"
run read
has "$(cat "$STUB_FINDINGS")" "--key memory-intake.rig-reldir --cleared" "a place resolved again clears its finding"
has "$OUT" "cleared the finding memory-intake.rig-reldir" "and says so"
eq "$(grep -c -- '--cleared' "$STUB_FINDINGS")" 1 "only that finding is cleared"
run read
eq "$(grep -c -- '--cleared' "$STUB_FINDINGS")" 1 "a cleared finding is not cleared twice"

echo "── placement: the city's --settings, the user and managed levels, the environment ──"
city levels
rig r1 tk; rig r2 tk
mkdir -p "$B/shared"; printf 'A note.\n' > "$B/shared/n.md"
setting "$B/city/.gc/settings.json" "{\"autoMemoryDirectory\": \"$B/shared\"}"
run read
has "$OUT" "town: $B/shared (autoMemoryDirectory in the city settings)" "the city's --settings file places it"
has "$OUT" "town, r1, r2: 1 notes and 0 entries" "a directory the --settings file places is read once for every place"
eq "$(find "$STATE" -mindepth 1 -maxdepth 1 -type d | grep -c .)" 1 "and keeps one list"
rm "$B/city/.gc/settings.json"
setting "$HOME/.claude/settings.json" '{"autoMemoryDirectory": "~/mem/user"}'
setting "$B/rigs/r2/.claude/settings.json" "{\"autoMemoryDirectory\": \"$B/shared\"}"
: > "$STUB_FINDINGS"
run read
has "$OUT" "r1: cannot place it: autoMemoryDirectory in the user settings places one directory for every project" "the user level is a place the run does not read"
has "$OUT" "r2: $B/shared (autoMemoryDirectory in the project settings)" "a project's own setting outranks the user's"
has "$(cat "$STUB_FINDINGS")" "--key memory-intake.user-level" "one finding for the user level"
has "$(cat "$STUB_FINDINGS")" "Claude Code memory of town, r1" "naming every place it holds"
setting "$HOME/.claude/settings.json" '{"autoMemoryDirectory": '
run read
has "$OUT" "r1: cannot place it: $HOME/.claude/settings.json does not parse (finding memory-intake.settings-user)" "user settings that do not parse cannot be resolved"
rm "$HOME/.claude/settings.json"
setting "$SB/managed.json" "{\"autoMemoryDirectory\": \"$B/managed\"}"
run read
has "$OUT" "r2: cannot place it: autoMemoryDirectory in the managed settings" "managed settings outrank the project's"
rm "$SB/managed.json"
memdir "$B/rigs/r1" >/dev/null
CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 run read
has "$OUT" "r1: absent: memory is off: CLAUDE_CODE_DISABLE_AUTO_MEMORY=1" "the environment turns memory off"
setting "$B/rigs/r1/.claude/settings.json" '{"autoMemoryEnabled": false}'
CLAUDE_CODE_DISABLE_AUTO_MEMORY=0 run read
has "$OUT" "r1: $HOME/.claude/projects/$(conv "$B/rigs/r1")/memory (named for the checkout)" "and 0 turns it on over autoMemoryEnabled false"
rm "$B/rigs/r1/.claude/settings.json"
mkdir -p "$B/cfg/projects/$(conv "$B/rigs/r1")/memory"
CLAUDE_CONFIG_DIR="$B/cfg" run read
has "$OUT" "r1: $B/cfg/projects/$(conv "$B/rigs/r1")/memory (named for the checkout)" "CLAUDE_CONFIG_DIR moves the config directory"
CLAUDE_CONFIG_DIR="$B/cfg" CLAUDE_CODE_PROJECT_DIR_NAME=proj run read
has "$OUT" "r1: cannot place it: CLAUDE_CODE_PROJECT_DIR_NAME names one directory for every project" "a named project directory is a place the run does not read"
CLAUDE_CODE_PROJECT_DIR_NAME=proj run read
has "$OUT" "r1: $HOME/.claude/projects/$(conv "$B/rigs/r1")/memory" "the name counts only beside CLAUDE_CONFIG_DIR"
CLAUDE_CONFIG_DIR="$B/cfg" CLAUDE_CODE_PROJECT_DIR_NAME='not ok' run read
has "$OUT" "r1: $B/cfg/projects/$(conv "$B/rigs/r1")/memory" "and only when Claude Code would take it"

# ── directories a character conversion would merge ─────────────────────────
echo "── directories whose real paths convert alike keep their own lists ──"
city keys
rig k1 tk; rig k2 tk; rig k3 tk
for p in "x/a.b" "x/a-b" "x-a/b"; do mkdir -p "$B/$p"; printf 'The same lesson.\n' > "$B/$p/same.md"; done
setting "$B/rigs/k1/.claude/settings.local.json" "{\"autoMemoryDirectory\": \"$B/x/a.b\"}"
setting "$B/rigs/k2/.claude/settings.local.json" "{\"autoMemoryDirectory\": \"$B/x/a-b\"}"
setting "$B/rigs/k3/.claude/settings.local.json" "{\"autoMemoryDirectory\": \"$B/x-a/b\"}"
eq "$(conv "$B/x/a.b")" "$(conv "$B/x-a/b")" "the three paths convert alike"
eq "$(conv "$B/x/a-b")" "$(conv "$B/x-a/b")" "all three"
run read
eq "$(find "$STATE" -mindepth 1 -maxdepth 1 -type d | grep -c .)" 3 "each directory keeps a list of its own"
KEYS=$(for p in "x/a.b" "x/a-b" "x-a/b"; do printf '%s' "$B/$p" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-64; done | sort | tr '\n' ' ')
eq "$(find "$STATE" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | tr '\n' ' ')" "$KEYS" "keyed by the SHA-256 of its real path"
eq "$(cat "$STATE"/*/path | sort | tr '\n' ' ')" "$B/x-a/b $B/x/a-b $B/x/a.b " "with that path written beside it"
DUE=$(due_json)
eq "$(printf '%s' "$DUE" | jq '[.[].memory_ref] | unique | length')" 3 "each holds a due note of its own"
eq "$(printf '%s' "$DUE" | jq -r '[.[].memory_ref | split("/")[1]] | unique | join(" ")')" "same.md@$(printf 'The same lesson.\n' | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-16)" "of one name and text"
R=$(printf '%s' "$DUE" | jq -r --arg d "$B/x/a.b" '.[] | select(.memory_dir == $d) | .memory_ref')
apply_lines "$R drop"
eq "$RC" 0 "dropping the note in one of them succeeds"
eq "$([ -e "$B/x/a.b/same.md" ] && echo kept || echo gone) $([ -e "$B/x/a-b/same.md" ] && echo kept || echo gone) $([ -e "$B/x-a/b/same.md" ] && echo kept || echo gone)" "gone kept kept" "and removes only its note"
eq "$(due_json | jq 'length')" 2 "the others stay due"

# ── due notes, decisions, use lines, links and the guidance block ──────────
echo "── due notes oldest first, and what the judge decided ──"
city flow
rig main tk
M=$(memdir "$B/rigs/main")
echo '[{"id": "tk-p1", "status": "open", "metadata": {"task_kind": "feedback-pattern"}}]' > "$B/rigs/main/beads.json"
printf 'Old lesson.\n' > "$M/old.md"; touch -t 202610011200 "$M/old.md"
printf 'Mid lesson.\n' > "$M/mid.md"; touch -t 202611051200 "$M/mid.md"
printf 'New lesson.\n' > "$M/new.md"; touch -t 202611101200 "$M/new.md"
printf 'Intro.\n\n- [[new]] (New): n\n- (no file) A fact of its own.\n  - its detail\n' > "$M/hub-a.md"; touch -t 202611081200 "$M/hub-a.md"
printf '# Memory Index\n\n- [Old](old.md) — o · [Gone](gone.md) — g · [Mid](mid.md) — m\n- [New](new.md) — n\n- [Hub](hub-a.md) — topics\n' > "$M/MEMORY.md"
run read
has "$OUT" "main: 3 notes and 1 entries" "notes and an entry with text of its own are units; a pointer line is not"
has "$OUT" "4 due" "every unit is due when the list holds none"
eq "$(head -1 "$M/MEMORY.md")" "<!-- memory-intake: rewritten from the gc-toolkit pack each run -->" "the guidance block opens the index"
has "$(cat "$M/MEMORY.md")" "- [Old](old.md) — o · [Mid](mid.md) — m" "a link to a gone note leaves its line, the rest stays"
DUE=$(due_json)
eq "$(printf '%s' "$DUE" | jq -r '[.[] | (.memory_file | split("/") | last) + ":" + .memory_kind] | join(" ")')" "old.md:note mid.md:note hub-a.md:entry new.md:note" "oldest first"
eq "$(printf '%s' "$DUE" | jq -r '.[0].created_at')" "2026-10-01T12:00:00Z" "as old as its last change"
eq "$(printf '%s' "$DUE" | jq -r '.[] | select(.memory_kind == "entry") | .memory_text')" "$(printf -- '- (no file) A fact of its own.\n  - its detail')" "an entry carries its text"
eq "$(due_json --limit 2 | jq -r '[.[] | .memory_file | split("/") | last] | join(" ")')" "old.md mid.md" "a limit takes the oldest"
eq "$(due_json --count)" 4 "the count is every due unit"
RO=$(ref_of old.md); RM=$(ref_of mid.md); RN=$(ref_of new.md); RE=$(printf '%s' "$DUE" | jq -r '.[] | select(.memory_kind == "entry") | .memory_ref')
apply_lines "$RO next 2026-11-20" "$RM waits tk-p1" "$RE waits tk-p1" "$RN drop"
eq "$RC" 0 "apply records and removes"
has "$OUT" "recorded $RO: due again on 2026-11-20" "a note kept until a date"
has "$OUT" "recorded $RM: waits on tk-p1" "a note on a pattern"
has "$OUT" "removed $RN, its text kept at" "a dropped note is removed"
K=$(printf '%s' "$RN" | cut -c1-16); SD=$(find "$STATE" -mindepth 1 -maxdepth 1 -type d -name "$K*")
eq "$(cat "$SD"/removed/new.md@*)" "New lesson." "its text is kept"
eq "$([ -e "$M/new.md" ] && echo kept || echo gone)" "gone" "the note file is gone"
hasnt "$(cat "$M/MEMORY.md")" "(new.md)" "the index line that linked it is taken out"
hasnt "$(cat "$M/hub-a.md")" "[[new]]" "and the collection-note line"
eq "$(due_json --count)" 0 "nothing is due once judged"

echo "── a note kept for a moment waits for its date, then behind those due before it ──"
printf 'Fresh lesson.\n' > "$M/fresh.md"; touch -t 202611121200 "$M/fresh.md"
printf 'Later lesson.\n' > "$M/later.md"; touch -t 202611210000 "$M/later.md"
eq "$(due_json | jq -r '[.[] | .memory_file | split("/") | last] | join(" ")')" "fresh.md later.md" "before its date it is not due"
eq "$(MEMORY_INTAKE_NOW=1795262400 due_json | jq -r '[.[] | (.memory_file | split("/") | last) + ":" + .memory_due] | join(" ")')" "fresh.md:new old.md:date later.md:new" "on it, it is due as old as that date"

echo "── a note changed since it was judged ──"
printf 'Mid lesson, edited.\n' > "$M/mid.md"
DUE=$(due_json)
eq "$(printf '%s' "$DUE" | jq -r '.[] | select(.memory_file | endswith("/mid.md")) | .memory_due + " / " + .memory_prior')" "changed / waited on tk-p1" "is due again, with what it waited on"
RF=$(ref_of fresh.md)
printf 'Fresh lesson, edited after the listing.\n' > "$M/fresh.md"
apply_lines "$RF drop"
eq "$RC" 0 "a refusal is not a failure"
has "$OUT" "refused $RF" "a note changed after it was listed is refused"
eq "$(cat "$M/fresh.md")" "Fresh lesson, edited after the listing." "and left in place"
eq "$(due_json | jq -r '[.[] | select(.memory_file | endswith("/fresh.md"))] | length')" 1 "and due"

echo "── a note kept to record its uses ──"
RF=$(ref_of fresh.md)
apply_lines "$RF next 2026-12-01 ask-use"
has "$OUT" "with a request to record each use" "ask-use is recorded"
eq "$(tail -1 "$M/fresh.md")" "<!-- memory-intake: use --> When this note steers your work, add a line at its end: used <YYYY-MM-DD>: <what it changed>" "the note gains the line that asks for its uses"
printf 'used 2026-11-16: chose the lock path\n' >> "$M/fresh.md"
eq "$(due_json | jq -r '[.[] | select(.memory_file | endswith("/fresh.md"))] | length')" 0 "a recorded use does not make it due"
eq "$(MEMORY_INTAKE_NOW=1796212800 due_json | jq -r '.[] | select(.memory_file | endswith("/fresh.md")) | .memory_due')" "date" "it comes due on its date"
printf 'A new line.\n' >> "$M/fresh.md"
eq "$(due_json | jq -r '.[] | select(.memory_file | endswith("/fresh.md")) | .memory_due')" "changed" "any other change makes it due"

echo "── decisions the script refuses ──"
apply_lines "$RE next 2026-12-01 ask-use" "nonsense" "$RO next 2026-11-15" "$RO waits zz-1" "$RO waits tk-nope" "0000000000000000/old.md@0000000000000000 drop" "$RO drop extra"
eq "$RC" 1 "a bad decision fails the apply"
has "$ERR" "ask-use takes a whole note" "ask-use on an entry"
has "$ERR" "not a decision" "a line that is no decision"
has "$ERR" "not a decision (<ref> waits <bead> | <ref> next <YYYY-MM-DD after today> [ask-use] | <ref> drop): $RO next 2026-11-15" "a date not after today"
has "$ERR" "no store of the city carries zz-1" "a bead no store carries"
has "$ERR" "tk-nope is not in its store" "a bead its store does not hold"
has "$ERR" "no memory directory the run reads now has that key" "a key no directory has"
eq "$([ -e "$M/old.md" ] && echo kept || echo gone)" "kept" "and nothing is removed for it"

echo "── an entry dropped, and a collection note left with none ──"
apply_lines "$RE drop"
has "$OUT" "removed $RE" "the entry is removed"
has "$OUT" "removed hub-a.md, which has no entries left" "its collection note goes with its last entry"
eq "$(cat "$SD"/removed/hub-a.md@"$(printf '%s' "$RE" | sed 's/.*@//')"*)" "$(printf -- '- (no file) A fact of its own.\n  - its detail')" "the entry's text is kept"
eq "$(find "$SD/removed" -name 'hub-a.md@*' | grep -c .)" 2 "and the collection note's"
hasnt "$(cat "$M/MEMORY.md")" "(hub-a.md)" "the index line that linked it is taken out"

echo "── the guidance block ──"
run read
hasnt "$OUT" "guidance block rewritten" "a current block is left as it is"
sed -i.bak 's/^Write a lesson so it can be acted on.*/Write whatever./' "$M/MEMORY.md" && rm -f "$M/MEMORY.md.bak"
run read
has "$OUT" "guidance block rewritten" "an edited block is rewritten"
eq "$(sed -n '1,/^<!-- \/memory-intake -->$/p' "$M/MEMORY.md")" "$(sed -n '1,/^<!-- \/memory-intake -->$/p' "$HERE/memory-guidance.md")" "from the pack's guidance file"
eq "$(grep -c 'memory-intake: rewritten' "$M/MEMORY.md")" 1 "once"
city guide
rig g1 tk; rig g2 tk
G1=$(memdir "$B/rigs/g1"); G2=$(memdir "$B/rigs/g2")
printf -- '---\ntitle: index\n---\n# Index\n' > "$G2/MEMORY.md"
run read
eq "$(sed -n '1,/^<!-- \/memory-intake -->$/p' "$G1/MEMORY.md")" "$(sed -n '1,/^<!-- \/memory-intake -->$/p' "$HERE/memory-guidance.md")" "an index is made when there is none"
eq "$(sed -n '1,3p;4p' "$G2/MEMORY.md" | tr '\n' '|')" "---|title: index|---|<!-- memory-intake: rewritten from the gc-toolkit pack each run -->|" "the block follows front matter"
eq "$(tail -1 "$G2/MEMORY.md")" "# Index" "and the index keeps the rest"

echo "── a note whose name holds spaces is judged by the ref due gives ──"
city spaces
rig sp tk
M=$(memdir "$B/rigs/sp")
echo '[{"id": "tk-p1", "status": "open", "metadata": {"task_kind": "feedback-pattern"}}]' > "$B/rigs/sp/beads.json"
printf 'A spaced lesson.\n' > "$M/my lesson.md"
printf 'Another, spaced twice.\n' > "$M/two  spaces.md"
run read
R1=$(ref_of "my lesson.md"); R2=$(ref_of "two  spaces.md")
has "$R1" "/my lesson.md@" "due gives the name as it is"
apply_lines "$R1 waits tk-p1" "$R2 drop"
eq "$RC" 0 "apply takes a decision on each"
has "$OUT" "recorded $R1: waits on tk-p1" "a wait is recorded"
has "$OUT" "removed $R2" "a drop is applied"
eq "$([ -e "$M/my lesson.md" ] && echo kept || echo gone) $([ -e "$M/two  spaces.md" ] && echo kept || echo gone)" "kept gone" "and removes only the dropped note"
eq "$(due_json --count)" 0 "nothing is due once judged"

echo "── a directory that cannot be listed keeps its links and every judgment ──"
city unread
rig u tk
U=$(memdir "$B/rigs/u")
echo '[{"id": "tk-p1", "status": "open", "metadata": {"task_kind": "feedback-pattern"}}]' > "$B/rigs/u/beads.json"
printf 'u lesson.\n' > "$U/u.md"
printf 'w lesson.\n' > "$U/w.md"
printf '# Memory Index\n\n- [U](u.md) — u\n' > "$U/MEMORY.md"
run read
apply_lines "$(ref_of u.md) waits tk-p1" "$(ref_of w.md) next 2026-12-01"
eq "$RC" 0 "one note waits on its pattern and one on a date"
LIST=$(find "$STATE" -name list.tsv); cp "$LIST" "$B/list.before"
chmod 300 "$U"   # its files open by name, but the directory cannot be listed
run read
chmod 700 "$U"
has "$(cat "$U/MEMORY.md")" "- [U](u.md) — u" "the index keeps its links"
has "$ERR" "the links in $U/MEMORY.md were not tidied" "and says so"
eq "$RC" 1 "the read fails"
has "$ERR" "cannot list $U; nothing there is removed, and its list stays as it is" "saying it cannot list the directory"
eq "$(cmp -s "$LIST" "$B/list.before" && echo same || echo changed)" "same" "and its list reads back unchanged"
eq "$(due_json --count)" 0 "so the wait and the date hold once it can be listed"
chmod 000 "$U/w.md"   # listed, but its text cannot be read
run read
chmod 644 "$U/w.md"
has "$ERR" "cannot read every note in $U" "a note that cannot be read stops the read of its directory"
eq "$(cmp -s "$LIST" "$B/list.before" && echo same || echo changed)" "same" "and its list stays as it was"
eq "$(due_json --count)" 0 "with every judgment held"

# ── waits that end ─────────────────────────────────────────────────────────
echo "── a wait ends once its pattern's fix has landed ──"
city settle
rig s tk; rig o sl; rig n nl
M=$(memdir "$B/rigs/s")
origin_head s main
origin_head o trunk
# n's upstream defaults to trunk, and its checkout records no origin/HEAD.
git init -q --bare "$B/up-n" && git -C "$B/up-n" symbolic-ref HEAD refs/heads/trunk
git -C "$B/rigs/n" init -q && git -C "$B/rigs/n" remote add origin "$B/up-n"
for n in a b c d e f g i y w x m; do printf '%s lesson.\n' "$n" > "$M/$n.md"; done
printf -- '- (no file) An entry on P1.\n' > "$M/hub-h.md"
printf '# Memory Index\n\n- [A](a.md) — a\n- [H](hub-h.md) — h\n' > "$M/MEMORY.md"
cat > "$B/rigs/s/beads.json" <<'JSON'
[{"id": "tk-p1", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p2", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p3", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p4", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p5", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p6", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p7", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p8", "status": "open", "metadata": {"task_kind": "feedback-pattern"}}]
JSON
echo '[{"id": "sl-x", "status": "open"}, {"id": "sl-y", "status": "open"}]' > "$B/rigs/o/beads.json"
echo '[{"id": "nl-w", "status": "open"}]' > "$B/rigs/n/beads.json"
run read
LINES=()
for n in a b c d f g i x m; do
  case $n in a|i) p=tk-p1 ;; b) p=tk-p2 ;; c) p=tk-p3 ;; d) p=tk-p4 ;; f) p=tk-p5 ;; g) p=tk-p6 ;; x) p=tk-p7 ;; m) p=tk-p8 ;; esac
  LINES+=("$(ref_of "$n.md") waits $p")
done
LINES+=("$(ref_of e.md) waits sl-x" "$(ref_of y.md) waits sl-y" "$(ref_of w.md) waits nl-w" "$(due_json | jq -r '.[] | select(.memory_kind == "entry") | .memory_ref') waits tk-p1")
apply_lines "${LINES[@]}"
eq "$RC" 0 "every note waits on its bead"
printf 'i lesson, changed after it was judged.\n' > "$M/i.md"
cat > "$B/rigs/s/beads.json" <<'JSON'
[{"id": "tk-p1", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "close_reason": "resolved: rule adopted", "metadata": {"task_kind": "feedback-pattern", "proposal_bead": "tk-f1"}},
 {"id": "tk-f1", "status": "closed", "metadata": {"merge_result": "merged", "merged_target": "main"}},
 {"id": "tk-p2", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "metadata": {"task_kind": "feedback-pattern"}, "deps": ["tk-f2"]},
 {"id": "tk-f2", "status": "closed", "metadata": {"merge_result": "merged", "merged_target": "integration/tk-l1"}},
 {"id": "tk-l1", "status": "open", "metadata": {}},
 {"id": "tk-p3", "status": "closed", "closed_at": "2026-11-13T09:00:00Z", "close_reason": "dismissed: the hold's window passed with no line matching '^\\t- used' in C:\\new", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p4", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p5", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "metadata": {"task_kind": "feedback-pattern", "proposal_bead": "tk-f5"}},
 {"id": "tk-f5", "status": "closed", "metadata": {"merge_result": "pull_request", "pr_url": "https://example.test/pull/5"}},
 {"id": "tk-p6", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "close_reason": "resolved: follow-ups closed", "metadata": {"task_kind": "feedback-pattern", "proposal_bead": "tk-f6"}},
 {"id": "tk-f6", "status": "closed", "metadata": {"merge_result": "pull_request", "pr_url": "https://example.test/pull/6"}},
 {"id": "tk-p7", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "metadata": {"task_kind": "feedback-pattern", "proposal_bead": "tk-f7"}},
 {"id": "tk-f7", "status": "closed", "metadata": {"merge_result": "pull_request"}},
 {"id": "tk-p8", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "metadata": {"task_kind": "feedback-pattern", "eng_bead": "tk-f8"}},
 {"id": "tk-f8", "status": "closed", "metadata": {"merge_result": "mr_merged", "merged_target": "main", "merged_sha": "8a1c0de8a1c0de8a1c0de8a1c0de8a1c0de8a1c0", "pr_state": "merged"}}]
JSON
echo '[{"id": "sl-x", "status": "closed", "metadata": {"merge_result": "merged", "merged_target": "trunk"}}, {"id": "sl-y", "status": "closed", "metadata": {"merge_result": "merged", "merged_target": "main"}}]' > "$B/rigs/o/beads.json"
echo '[{"id": "nl-w", "status": "closed", "metadata": {"merge_result": "merged", "merged_target": "main"}}]' > "$B/rigs/n/beads.json"
echo '{"https://example.test/pull/5": {"state": "OPEN", "baseRefName": "main"}, "https://example.test/pull/6": {"state": "CLOSED", "baseRefName": "main"}}' > "$STUB_PRS"
run read
eq "$RC" 0 "read settles the waits"
has "$OUT" "waits ended: 4 unit(s) removed with a fix landed, their text kept; 2 due again with no fix landed" "and counts them"
left() { local n; for n in "$@"; do if [ -e "$M/$n" ]; then printf '%s:kept ' "$n"; else printf '%s:gone ' "$n"; fi; done; }
eq "$(left a.md b.md c.md d.md e.md f.md g.md i.md y.md hub-h.md)" "a.md:gone b.md:kept c.md:kept d.md:kept e.md:gone f.md:kept g.md:kept i.md:kept y.md:kept hub-h.md:gone " \
  "a fix on the default branch removes a note; one on its way, an open pattern, a changed note and a merge off the default branch keep theirs"
eq "$(left w.md)" "w.md:kept " "a merge into main keeps its note where origin/HEAD names no default branch"
has "$ERR" "the origin/HEAD of $B/rigs/n names no branch, so no merge there is taken as landed and each wait on one stays; set it with git -C '$B/rigs/n' remote set-head origin --auto" "and the run names the repair"
eq "$(left x.md)" "x.md:kept " "a fix merged by a PR its record does not name keeps its note"
has "$ERR" "tk-f7 has merge_result pull_request and no pr_url, so the wait it decides stays" "and the run says what the record lacks"
eq "$(left m.md)" "m.md:gone " "a fix that landed through Gas Town's pending record (mr_merged) removes its note"
SD=$(find "$STATE" -mindepth 1 -maxdepth 1 -type d | head -1)
eq "$(cat "$SD"/removed/a.md@*)" "a lesson." "a removed note's text is kept"
hasnt "$(cat "$M/MEMORY.md")" "(a.md)" "and its index line is taken out"
hasnt "$(cat "$M/MEMORY.md")" "(hub-h.md)" "as is the line of a collection note its last entry left"
DUE=$(due_json)
eq "$(printf '%s' "$DUE" | jq -r '[.[] | (.memory_file | split("/") | last) + ":" + .memory_due] | join(" ")')" "c.md:date g.md:date i.md:changed" "a wait that ended with no fix landed makes its note due"
eq "$(printf '%s' "$DUE" | jq -r '.[] | select(.memory_file | endswith("/c.md")) | .created_at + " / " + .memory_prior')" \
  "2026-11-13T00:00:00Z / waited on tk-p3, which closed with no fix landed: dismissed: the hold's window passed with no line matching '^\t- used' in C:\new" \
  "as old as the day it ended, saying why in the close reason's own words, backslashes and all"
echo "── a merge into an effort's branch lands with the effort's landing bead ──"
jq '(.[] | select(.id == "tk-l1")) |= . + {status: "closed", metadata: {merge_result: "merged", merged_target: "main"}}' "$B/rigs/s/beads.json" > "$B/beads.next" && mv "$B/beads.next" "$B/rigs/s/beads.json"
echo '{"https://example.test/pull/5": {"state": "MERGED", "baseRefName": "main"}, "https://example.test/pull/6": {"state": "CLOSED", "baseRefName": "main"}}' > "$STUB_PRS"
run read
eq "$(left b.md f.md)" "b.md:gone f.md:gone " "once the landing bead merges, and once the PR merges into the default branch"

echo "── a veto marks the note, its pointers and an entry in the run that ends the wait ──"
city veto
rig v tk
M=$(memdir "$B/rigs/v")
origin_head v main
VL=$(grep -F '<!-- memory-intake: veto -->' "$HERE/memory-guidance.md" | sed 's|<PR>|https://example.test/pull/7|')
VM=$(grep -F '<!-- memory-intake: veto mark -->' "$HERE/memory-guidance.md" | sed 's|^<!-- memory-intake: veto mark --> ||')
printf -- '---\nname: v\n---\nV lesson: do the vetoed thing.\n' > "$M/v.md"
for n in d e k; do printf '%s lesson.\n' "$n" > "$M/$n.md"; done
printf -- '- [[v]] (V): see v\n- (no file) An entry on P7.\n  - its detail\n' > "$M/hub-v.md"
printf '# Memory Index\n\n- [V](v.md) — v · [D](d.md) — d\n- [E](e.md) — e\n- [Hub](hub-v.md) — topics\n' > "$M/MEMORY.md"
cat > "$B/rigs/v/beads.json" <<'JSON'
[{"id": "tk-p7", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p8", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p9", "status": "open", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p10", "status": "open", "metadata": {"task_kind": "feedback-pattern"}}]
JSON
run read
apply_lines "$(ref_of v.md) waits tk-p7" "$(due_json | jq -r '.[] | select(.memory_kind == "entry") | .memory_ref') waits tk-p7" \
  "$(ref_of d.md) waits tk-p8" "$(ref_of k.md) waits tk-p9" "$(ref_of e.md) waits tk-p10"
eq "$RC" 0 "each unit waits on its pattern"
printf 'V lesson, edited after it was judged.\n' >> "$M/v.md"
cat > "$B/rigs/v/beads.json" <<'JSON'
[{"id": "tk-p7", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "close_reason": "resolved: follow-ups closed", "metadata": {"task_kind": "feedback-pattern", "proposal_bead": "tk-f7"}},
 {"id": "tk-f7", "status": "closed", "metadata": {"task_kind": "prompt-update", "merge_result": "pull_request", "pr_url": "https://example.test/pull/7"}},
 {"id": "tk-p8", "status": "closed", "closed_at": "2026-11-13T09:00:00Z", "close_reason": "dismissed: the hold's window passed", "metadata": {"task_kind": "feedback-pattern"}},
 {"id": "tk-p9", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "metadata": {"task_kind": "feedback-pattern", "proposal_bead": "tk-f9", "eng_bead": "tk-g9"}},
 {"id": "tk-f9", "status": "closed", "metadata": {"task_kind": "prompt-update", "merge_result": "pull_request", "pr_url": "https://example.test/pull/9"}},
 {"id": "tk-g9", "status": "closed", "metadata": {"merge_result": "merged", "merged_target": "main"}},
 {"id": "tk-p10", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "metadata": {"task_kind": "feedback-pattern", "proposal_bead": "tk-f10"}},
 {"id": "tk-f10", "status": "closed", "metadata": {"task_kind": "task", "merge_result": "pull_request", "pr_url": "https://example.test/pull/10"}}]
JSON
echo '{"https://example.test/pull/7": {"state": "CLOSED", "baseRefName": "main"}, "https://example.test/pull/9": {"state": "CLOSED", "baseRefName": "main"}, "https://example.test/pull/10": {"state": "CLOSED", "baseRefName": "main"}}' > "$STUB_PRS"
chmod 500 "$M"   # nothing in the directory can be written
run read
chmod 700 "$M"
has "$ERR" "$M/v.md is not marked as vetoed, so it waits until a run marks it" "a note that cannot be marked says so"
eq "$RC" 1 "and fails the run"
hasnt "$(cat "$M/v.md")" "memory-intake: veto" "it stays unmarked"
eq "$(due_json | jq -r '.[] | select(.memory_file | endswith("/v.md")) | .memory_due + " / " + .memory_prior')" "changed / waited on tk-p7" "and keeps its wait"
run read
eq "$RC" 0 "the next run marks it"
has "$OUT" "waits ended: 1 unit(s) removed with a fix landed, their text kept; 2 due again with no fix landed" "and counts what it marks among the due"
has "$OUT" "vetoed: 2 of those due again marked" "and says how many it marked"
eq "$(cat "$M/v.md")" "$(printf -- '---\nname: v\n---\n%s\nV lesson: do the vetoed thing.\nV lesson, edited after it was judged.' "$VL")" \
  "the note gains the veto line under its front matter, though it changed since it was judged"
has "$(cat "$M/MEMORY.md")" "- [V](v.md) — v $VM · [D](d.md) — d" "its index pointer gains the veto mark, and the pointer beside it does not"
has "$(cat "$M/hub-v.md")" "- [[v]] (V): see v $VM" "and so does its collection-note pointer"
eq "$(sed -n '2,4p' "$M/hub-v.md")" "$(printf -- '- (no file) An entry on P7.\n  %s\n  - its detail' "$VL")" "an entry gains the veto line under its first line"
eq "$(left k.md d.md e.md)" "k.md:gone d.md:kept e.md:kept " "a fix that landed beside a vetoed proposal removes its note"
hasnt "$(cat "$M/d.md" "$M/e.md")" "memory-intake: veto" "a dismissal, and a closed PR that is no prompt-update, mark no note"
eq "$(grep -F '(e.md)' "$M/MEMORY.md")" "- [E](e.md) — e" "and no pointer"
DUE=$(due_json)
eq "$(printf '%s' "$DUE" | jq -r '[.[] | (.memory_file | split("/") | last) + ":" + .memory_due] | join(" ")')" "d.md:date e.md:date hub-v.md:date v.md:date" \
  "each unit whose wait ended with no fix landed is due, the marked ones at the hash they hold now"
eq "$(printf '%s' "$DUE" | jq -r '.[] | select(.memory_file | endswith("/v.md")) | .created_at + " / " + .memory_prior')" \
  "2026-11-14T00:00:00Z / waited on tk-p7, which closed with no fix landed after the operator vetoed https://example.test/pull/7: resolved: follow-ups closed" \
  "as old as the day the pattern closed, saying the operator vetoed it"
cp "$M/v.md" "$B/v.before"; cp "$M/MEMORY.md" "$B/index.before"; cp "$M/hub-v.md" "$B/hub.before"
run read
hasnt "$OUT" "vetoed:" "a later run marks nothing again"
eq "$(cmp -s "$M/v.md" "$B/v.before" && cmp -s "$M/MEMORY.md" "$B/index.before" && cmp -s "$M/hub-v.md" "$B/hub.before" && echo same)" "same" "and leaves each mark as it is"

echo "── a pattern whose edges were not read keeps its notes ──"
city edges
rig s tk
M=$(memdir "$B/rigs/s")
origin_head s main
printf 'z lesson.\n' > "$M/z.md"
echo '[{"id": "tk-p1", "status": "open", "metadata": {"task_kind": "feedback-pattern"}}]' > "$B/rigs/s/beads.json"
run read
apply_lines "$(ref_of z.md) waits tk-p1"
cat > "$B/rigs/s/beads.json" <<'JSON'
[{"id": "tk-p1", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "metadata": {"task_kind": "feedback-pattern", "proposal_bead": "tk-f1"}},
 {"id": "tk-f1", "status": "closed", "metadata": {"merge_result": "merged", "merged_target": "main"}}]
JSON
STUB_DEP_FAIL=1 run read
has "$ERR" "did not answer for the follow-ups of tk-p1" "a follow-up named only by an edge may be on its way"
eq "$(left z.md)" "z.md:kept " "so the note stays"
run read
eq "$(left z.md)" "z.md:gone " "until the edges are read"

# ── what an entry is, and what leaves ──────────────────────────────────────
echo "── an item with lines under a blank line is an entry, though it opens with a link to a gone note ──"
city boundary
rig b tk
M=$(memdir "$B/rigs/b")
ENTRY=$(printf -- '- [Lesson](gone.md) — the lesson\n\n  What the lesson holds, under a blank line.')
printf '%s\n' "$ENTRY" > "$M/hub-b.md"
printf '# Memory Index\n\n- [Gone](gone.md) — g\n  what the gone note held\n- [Hub](hub-b.md) — b\n' > "$M/MEMORY.md"
run read
eq "$(cat "$M/hub-b.md" 2>/dev/null)" "$ENTRY" "read keeps the entry whole, its first line included, and leaves its collection note"
has "$OUT" "b: 0 notes and 1 entries" "it is one unit"
eq "$(due_json | jq -r '.[0].memory_text')" "$ENTRY" "listed with all its text"
has "$(cat "$M/MEMORY.md")" "$(printf -- '- [Gone](gone.md) — g\n  what the gone note held')" "an index item with a line under it is kept whole"
R=$(due_json | jq -r '.[0].memory_ref'); K=$(printf '%s' "$R" | cut -c1-16); SD=$(find "$STATE" -mindepth 1 -maxdepth 1 -type d -name "$K*")
apply_lines "$R drop"
has "$OUT" "removed hub-b.md, which has no entries left" "dropped, the entry leaves with its collection note"
eq "$(cat "$SD"/removed/hub-b.md@"${R##*@}"*)" "$ENTRY" "its whole text kept"

echo "── nothing leaves while its text cannot be kept ──"
city keep
rig k tk
M=$(memdir "$B/rigs/k")
origin_head k main
echo '[{"id": "tk-p1", "status": "open", "metadata": {"task_kind": "feedback-pattern"}}]' > "$B/rigs/k/beads.json"
printf 'k lesson.\n' > "$M/k.md"
printf -- '- (no file) An entry to drop.\n- (no file) An entry that waits.\n' > "$M/hub-k.md"
run read
RD=$(due_json | jq -r '.[] | select((.memory_text // "") | contains("to drop")) | .memory_ref')
RW=$(due_json | jq -r '.[] | select((.memory_text // "") | contains("that waits")) | .memory_ref')
apply_lines "$RD next 2026-11-20" "$RW waits tk-p1" "$(ref_of k.md) waits tk-p1"
SD=$(find "$STATE" -mindepth 1 -maxdepth 1 -type d | head -1)
# The row of an entry: its kind, collection note and the hash its ref begins.
row() { awk -F'\t' -v n="$1" -v h="${2##*@}" '$1 == "entry" && $2 == n && index($3, h) == 1' "$SD/list.tsv"; }
rm -rf "$SD/removed"; : > "$SD/removed"   # removed/ cannot be made
MEMORY_INTAKE_NOW=1795262400 apply_lines "$RD drop"   # 2026-11-21, the entry due on its date
eq "$RC" 1 "an entry whose text cannot be kept fails the apply"
has "$ERR" "could not remove $RD" "and says so"
hasnt "$OUT" "kept at" "with no word of its text kept"
has "$(cat "$M/hub-k.md")" "- (no file) An entry to drop." "the entry stays in its collection note"
has "$(row hub-k.md "$RD")" "2026-11-20" "and its row stays on the list"
printf -- '- [P](gone.md) — a pointer to a gone note\n' > "$M/hub-p.md"
run read
eq "$RC" 1 "a collection note its last pointer leaves fails the read when its text cannot be kept"
has "$ERR" "hub-p.md has no entries left and stays" "and says so"
eq "$([ -e "$M/hub-p.md" ] && echo kept || echo gone)" "kept" "and it stays"
cat > "$B/rigs/k/beads.json" <<'JSON'
[{"id": "tk-p1", "status": "closed", "closed_at": "2026-11-14T10:00:00Z", "metadata": {"task_kind": "feedback-pattern", "proposal_bead": "tk-f1"}},
 {"id": "tk-f1", "status": "closed", "metadata": {"merge_result": "merged", "merged_target": "main"}}]
JSON
run read
eq "$RC" 1 "a wait that ends while the text cannot be kept fails the read"
has "$OUT" "waits ended: 0 unit(s) removed" "nothing is removed"
eq "$(left k.md)" "k.md:kept " "the note stays"
has "$(cat "$M/hub-k.md")" "- (no file) An entry that waits." "and so does the entry"
has "$(row hub-k.md "$RW")" "tk-p1" "with its row still waiting"
rm -f "$SD/removed"
run read
eq "$RC" 0 "once the text can be kept"
eq "$(left k.md)" "k.md:gone " "the note leaves"
hasnt "$(cat "$M/hub-k.md")" "An entry that waits." "and so does the entry"
eq "$(cat "$SD"/removed/k.md@*)" "k lesson." "each with its text kept"

echo "── a note an agent edits while it is being removed stays ──"
city race
rig r tk
M=$(memdir "$B/rigs/r")
origin_head r main
echo '[{"id": "tk-p1", "status": "open", "metadata": {"task_kind": "feedback-pattern"}}, {"id": "tk-p2", "status": "open", "metadata": {"task_kind": "feedback-pattern"}}]' > "$B/rigs/r/beads.json"
for n in d s t; do printf '%s lesson.\n' "$n" > "$M/$n.md"; done
EDITED=$(printf 'An edit made while it was being removed.')
run read
apply_lines "$(ref_of s.md) waits tk-p1" "$(ref_of t.md) waits tk-p2"
RD=$(ref_of d.md)
STUB_EDIT="$M/d.md" STUB_EDIT_AT=mkdir PATH="$SB/edit-bin:$PATH" apply_lines "$RD drop"
has "$OUT" "refused $RD" "a drop is refused when the note changes after the scan, before its text is kept"
has "$(cat "$M/d.md")" "$EDITED" "the note stays with the edit"
eq "$(due_json | jq -r '.[] | select(.memory_file | endswith("/d.md")) | .memory_due')" "new" "and is due"
eq "$(find "$STATE" -path '*/removed/d.md@*' | grep -c .)" 0 "no text is kept for it"
# landed <pattern>... — each pattern closes with its fix landed on main.
landed() {
  local p; for p in "$@"; do
    jq --arg p "$p" '(.[] | select(.id == $p)) |= . + {status: "closed", closed_at: "2026-11-14T10:00:00Z", metadata: {task_kind: "feedback-pattern", proposal_bead: ($p + "f")}}
      | . + [{id: ($p + "f"), status: "closed", metadata: {merge_result: "merged", merged_target: "main"}}]' "$B/rigs/r/beads.json" > "$B/beads.next" && mv "$B/beads.next" "$B/rigs/r/beads.json"
  done
}
landed tk-p1
STUB_EDIT="$M/s.md" STUB_EDIT_AT=mkdir PATH="$SB/edit-bin:$PATH" run read
eq "$(left s.md)" "s.md:kept " "a wait that ends keeps a note that changes after the scan, before its text is kept"
has "$(cat "$M/s.md")" "$EDITED" "with the edit"
eq "$(due_json | jq -r '.[] | select(.memory_file | endswith("/s.md")) | .memory_due + " / " + .memory_prior')" "changed / waited on tk-p1" "due as changed"
landed tk-p2
STUB_EDIT="$M/t.md" STUB_EDIT_AT=cp PATH="$SB/edit-bin:$PATH" run read
eq "$(left t.md)" "t.md:kept " "and one that changes after its text is kept, before it goes"
has "$(cat "$M/t.md")" "$EDITED" "with the edit"
eq "$(due_json | jq -r '.[] | select(.memory_file | endswith("/t.md")) | .memory_due')" "changed" "due as changed"
eq "$(find "$STATE" -path '*/removed/[st].md@*' | grep -c .)" 0 "the text kept for them is taken back"

echo "── off the home rig ──"
city offhome
rig q tk
Q=$(memdir "$B/rigs/q"); printf 'q lesson.\n' > "$Q/q.md"
OUT=$(cd "$SB/other-rig" && "$SUT" read 2>&1); RC=$?
eq "$RC" 0 "read off the home rig exits 0"
has "$OUT" "off-home" "and says why"
eq "$([ -e "$STATE" ] && echo made || echo none) $([ -e "$Q/MEMORY.md" ] && echo written || echo untouched)" "none untouched" "and changes nothing"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
