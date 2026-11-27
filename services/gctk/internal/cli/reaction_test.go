package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/reaction"
)

// stubLoggingGC puts a gc on PATH that logs each call, answers the rig list
// with rigs, the city's config with $STUB_CONFIG and the store gc resolves here
// with $STUB_WHERE, and returns the log's path.
func stubLoggingGC(t *testing.T, rigs string) string {
	t.Helper()
	bin := t.TempDir()
	log := filepath.Join(bin, "log")
	stub := "#!/bin/sh\necho \"$*\" >> '" + log + "'\ncase \"$1 $2\" in \"rig list\") printf '%s' \"$STUB_RIGS\" ;; \"config show\") printf '%s' \"$STUB_CONFIG\" ;; \"bd where\") printf '%s' \"$STUB_WHERE\" ;; esac\nexit 0\n"
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_RIGS", rigs)
	return log
}

// A call the dispose refuses for what it asks exits 2 with the reason and the
// usage, before Gas City or the store is asked anything.
func TestReactionDisposeRefusesUsageBeforeAnyCall(t *testing.T) {
	log := stubLoggingGC(t, `{"rigs":[]}`)
	t.Setenv("GC_RIG", "gc-toolkit")
	for name, args := range map[string][]string{
		"an unknown exit":     {"reaction", "dispose", "tk-sub", "--disposition", "sideways", "--reason", "r", "--takeaway", "t"},
		"another exit's flag": {"reaction", "dispose", "tk-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat"},
		"the keeper":          {"reaction", "dispose", "tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.keeper"},
		"no bead":             {"reaction", "dispose", "--disposition", "ruling", "--reason", "r", "--takeaway", "t"},
	} {
		var out, errb bytes.Buffer
		if code := Run(args, "test", &out, &errb); code != 2 {
			t.Errorf("%s exited %d, want 2: %s", name, code, errb.String())
		}
		if !strings.Contains(errb.String(), "Usage:") {
			t.Errorf("%s printed no usage: %s", name, errb.String())
		}
	}
	if raw, _ := os.ReadFile(log); len(raw) != 0 {
		t.Errorf("a refused call asked gc %q", raw)
	}
}

// With no --db, a check, a sling and a dispose read their subject from the
// store gc routes it to, as every gctk verb that names a bead does: when gc
// resolves another store here, the store of the rig whose prefix is the longest
// that begins the subject's id, from the city's config.
func TestReactionVerbsReadTheStoreGcRoutesTheSubjectTo(t *testing.T) {
	dir := t.TempDir()
	short, long := filepath.Join(dir, "tk", ".beads"), filepath.Join(dir, "tk-x", ".beads")
	for _, d := range []string{short, long} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	log := stubLoggingGC(t, `{"rigs":[{"name":"town","prefix":"hq","path":"`+dir+`","hq":true},{"name":"tk","prefix":"tk","path":"`+filepath.Dir(short)+`"},{"name":"tk-x","prefix":"tk-x","path":"`+filepath.Dir(long)+`"}]}`)
	t.Setenv("STUB_CONFIG", `{"city_path":"`+dir+`","config":{"Workspace":{"Name":"town","Prefix":"hq"},"Rigs":[`+
		`{"Name":"tk","Prefix":"tk","Path":"`+filepath.Dir(short)+`"},{"Name":"tk-x","Prefix":"tk-x","Path":"`+filepath.Dir(long)+`"}]}}`)
	t.Setenv("STUB_WHERE", `{"path":"`+filepath.Join(dir, ".beads")+`","prefix":"hq"}`)
	t.Setenv("GC_RIG", "gc-toolkit")
	for name, args := range map[string][]string{
		"a check":   {"reaction", "check", "tk-x-sub", "--run", "tk-root"},
		"a sling":   {"reaction", "sling", "tk-x-sub"},
		"a dispose": {"reaction", "dispose", "tk-x-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", "t"},
	} {
		if err := os.WriteFile(log, nil, 0o644); err != nil {
			t.Fatal(err)
		}
		var out, errb bytes.Buffer
		Run(args, "test", &out, &errb)
		if len(calls(t, log, "bd --db "+long+" ")) == 0 || len(calls(t, log, "bd --db "+short+" ")) > 0 {
			t.Errorf("%s read %v, want reads of %s alone", name, calls(t, log, "bd "), long)
		}
	}
}

// A check of a subject in the store gc resolves here reads no rig list, so a
// rig list that never answers cannot hold it, and the check decides nothing
// once that store does not answer.
func TestReactionCheckEndsWhenTheRigListNeverAnswers(t *testing.T) {
	bin := t.TempDir()
	stub := "#!/bin/sh\ncase \"$1 $2\" in \"rig list\") exec sleep 60 ;; \"bd where\") printf '{\"path\":\"" + bin + "/.beads\",\"prefix\":\"tk\"}'; exit 0 ;; esac\nexit 1\n"
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GC_RIG_LIST_TIMEOUT", "")
	t.Setenv("GC_RIG", "gc-toolkit")
	start := time.Now()
	var out, errb bytes.Buffer
	if code := Run([]string{"reaction", "check", "tk-sub", "--run", "tk-root"}, "test", &out, &errb); code != 1 {
		t.Errorf("the check exited %d, want 1: %s", code, errb.String())
	}
	if took := time.Since(start); took > 20*time.Second {
		t.Fatalf("the check ended %s after it started", took)
	}
	if !strings.Contains(errb.String(), "decides nothing") {
		t.Errorf("the check said %q", errb.String())
	}
}

// A check, a sling, a sweep or a pool's answer refused for what it asks exits 2
// with the reason and the usage, before Gas City or the store is asked
// anything.
func TestReactionVerbsRefuseUsageBeforeAnyCall(t *testing.T) {
	log := stubLoggingGC(t, `{"rigs":[]}`)
	t.Setenv("GC_RIG", "gc-toolkit")
	for name, args := range map[string][]string{
		"a check with no run":     {"reaction", "check", "tk-sub"},
		"a check with a bad run":  {"reaction", "check", "tk-sub", "--run", "tk root"},
		"a check with no bead":    {"reaction", "check", "--run", "tk-root"},
		"a check of a blank bead": {"reaction", "check", " ", "--run", "tk-root"},
		"a sling with no bead":    {"reaction", "sling"},
		"a sling of a blank bead": {"reaction", "sling", ""},
		"a sling with two beads":  {"reaction", "sling", "tk-sub", "tk-other"},
		"a sling's unknown flag":  {"reaction", "sling", "tk-sub", "--nudge"},
		"a sling's dry run":       {"reaction", "sling", "tk-sub", "--dry-run"},
		"a sweep with a bead":     {"reaction", "sweep", "tk-sub"},
	} {
		var out, errb bytes.Buffer
		if code := Run(args, "test", &out, &errb); code != 2 {
			t.Errorf("%s exited %d, want 2: %s", name, code, errb.String())
		}
		if !strings.Contains(errb.String(), "Usage:") {
			t.Errorf("%s printed no usage: %s", name, errb.String())
		}
	}
	if raw, _ := os.ReadFile(log); len(raw) != 0 {
		t.Errorf("a refused call asked gc %q", raw)
	}
}

// With no GC_RIG there is no proactive pool to name, so a sling and a sweep
// fail with exit 1, saying so once, before anything is read. A sweep whose
// deadline does not read fails before anything is read, too.
func TestReactionVerbsFailClosedWithNoRigOrDeadline(t *testing.T) {
	log := stubLoggingGC(t, `{"rigs":[]}`)
	t.Setenv("GC_RIG", "")
	for _, args := range [][]string{{"reaction", "sling", "tk-sub"}, {"reaction", "sweep"}} {
		var out, errb bytes.Buffer
		if code := Run(args, "test", &out, &errb); code != 1 || strings.Count(errb.String(), "set GC_RIG") != 1 {
			t.Errorf("%v with no GC_RIG exited %d, saying %q", args, code, errb.String())
		}
	}
	t.Setenv("GC_RIG", "gc-toolkit")
	t.Setenv("GC_PROACTIVE_SWEEP_TIMEOUT", "soon")
	var out, errb bytes.Buffer
	if code := Run([]string{"reaction", "sweep"}, "test", &out, &errb); code != 1 || !strings.Contains(errb.String(), "GC_PROACTIVE_SWEEP_TIMEOUT must be a duration") {
		t.Errorf("a sweep with an unreadable deadline exited %d, saying %q", code, errb.String())
	}
	if raw, _ := os.ReadFile(log); len(raw) != 0 {
		t.Errorf("a call that failed closed asked gc %q", raw)
	}
}

// stubCity is a city for the reaction's verbs to run in end to end, through the
// real adapters: a gc on PATH that logs each call and answers the rig list, the
// roster, the config, a sling, and the store's reads of the subject tk-sub, an
// open task nobody has decided on whose title carries a raw control byte. Its
// blocked set is blocked, its roster read prints STUB_WARN on standard error
// when it is set, and its sling exits STUB_SLING_RC printing STUB_SLING_OUT.
// The pack's scripts are stubs that log and exit 0. It returns the log's path
// and the rig's store.
func stubCity(t *testing.T, blocked []byte) (log, store string) {
	t.Helper()
	dir := t.TempDir()
	rig, town := filepath.Join(dir, "rig"), filepath.Join(dir, "town")
	for _, d := range []string{filepath.Join(rig, ".beads"), filepath.Join(town, ".beads"), filepath.Join(town, ".gc"), filepath.Join(dir, "bin"), filepath.Join(dir, "scripts")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	log = filepath.Join(dir, "log")
	subject := "[{\"id\":\"tk-sub\",\"title\":\"the subject\x01\",\"status\":\"open\",\"issue_type\":\"task\",\"priority\":2,\"description\":\"a raw input bead\",\"metadata\":{}}]"
	for name, body := range map[string][]byte{"subject.json": []byte(subject), "blocked.json": blocked} {
		if err := os.WriteFile(filepath.Join(dir, name), body, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	gc := `#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$1" in
  rig) printf '{"rigs":[{"name":"town","prefix":"hq","path":"%s","hq":true},{"name":"gc-toolkit","prefix":"tk","path":"%s"}]}' "$STUB_TOWN" "$STUB_RIG"; exit 0 ;;
  agent) [ -n "$STUB_WARN" ] && echo "$STUB_WARN" >&2; printf '%s' "$STUB_AGENTS"; exit 0 ;;
  config) printf '{"config":{"NamedSessions":[],"Agents":[]}}'; exit 0 ;;
  sling) printf '%s\n' "${STUB_SLING_OUT:-Slung}"; exit "${STUB_SLING_RC:-0}" ;;
  bd) shift ;;
  *) echo "unexpected call: gc $*" >&2; exit 1 ;;
esac
[ "$1" = --db ] && shift 2
case "$1" in
  list) case " $* " in *" --id tk-sub "*) cat "$STUB_DIR/subject.json" ;; *) printf '[]' ;; esac ;;
  show) cat "$STUB_DIR/subject.json" ;;
  ready) cat "$STUB_DIR/subject.json" ;;
  dep) printf '[]' ;;
  blocked) cat "$STUB_DIR/blocked.json" ;;
  sql) printf '[]' ;;
  where) printf '{"path":"%s/.beads","prefix":"tk"}' "$STUB_RIG" ;;
  update) ;;
  *) echo "unexpected call: gc bd $*" >&2; exit 1 ;;
esac
`
	script := "#!/bin/sh\necho \"script $(basename \"$0\") $*\" >> \"$STUB_LOG\"\n"
	for path, body := range map[string]string{filepath.Join(dir, "bin", "gc"): gc,
		filepath.Join(dir, "scripts", "human-gate.sh"): script, filepath.Join(dir, "scripts", "run-cancel.sh"): script} {
		if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", filepath.Join(dir, "bin")+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GCTK_SCRIPTS_DIR", filepath.Join(dir, "scripts"))
	// The city's root is the town the stub's rig list names as its HQ, which
	// holds the dispatch locks a release's disarm takes, and never the city
	// this test runs in.
	for _, v := range []string{"GC_CITY_PATH", "GC_CITY", "GC_CITY_ROOT"} {
		t.Setenv(v, "")
	}
	t.Setenv("STUB_LOG", log)
	t.Setenv("STUB_DIR", dir)
	t.Setenv("STUB_RIG", rig)
	t.Setenv("STUB_TOWN", town)
	t.Setenv("STUB_AGENTS", `{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.proactive","name":"proactive","dir":"gc-toolkit","scope":"rig","pool":{"max":2}},{"qualified_name":"gc-toolkit/gc-toolkit.polecat","name":"polecat","dir":"gc-toolkit","scope":"rig","pool":{"max":2}}]}`)
	t.Setenv("STUB_WARN", "")
	t.Setenv("STUB_SLING_RC", "0")
	t.Setenv("STUB_SLING_OUT", "")
	t.Setenv("GC_RIG", "gc-toolkit")
	t.Setenv("GC_PROACTIVE_SWEEP_TIMEOUT", "")
	return log, filepath.Join(rig, ".beads")
}

// argMax is the host's cap on a command's arguments, read when the test runs so
// the test holds on any host.
func argMax(t *testing.T) int {
	t.Helper()
	out, err := exec.Command("getconf", "ARG_MAX").Output()
	if err != nil {
		t.Fatalf("getconf ARG_MAX: %v", err)
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(out)))
	if err != nil || n <= 0 {
		t.Fatalf("getconf ARG_MAX printed %q", out)
	}
	return n
}

// bigBlocked is a blocked set, in `gc bd blocked --json`'s shape, of more bytes
// than max, none of whose beads is the subject.
func bigBlocked(max int) []byte {
	pad := strings.Repeat("x", 4096)
	var b strings.Builder
	b.WriteString("[")
	for i := 0; b.Len() <= max; i++ {
		if i > 0 {
			b.WriteString(",")
		}
		fmt.Fprintf(&b, `{"id":"tk-held-%d","title":"%s","blocked_by":["tk-blocker-%d"]}`, i, pad, i)
	}
	b.WriteString("]")
	return []byte(b.String())
}

// calls is the log's lines that open with prefix.
func calls(t *testing.T, log, prefix string) []string {
	t.Helper()
	raw, _ := os.ReadFile(log)
	var out []string
	for _, l := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(l, prefix) {
			out = append(out, l)
		}
	}
	return out
}

// The check asks waits what holds its subject through the store's blocked set,
// which grows with the store, and decodes it from the read's output, never
// from a command line: over a blocked set larger than ARG_MAX, the check runs
// end to end through the real adapters and the subject takes the reaction.
func TestReactionCheckReadsABlockedSetLargerThanArgMax(t *testing.T) {
	max := argMax(t)
	blocked := bigBlocked(max)
	log, store := stubCity(t, blocked)
	if len(blocked) <= max {
		t.Fatalf("the blocked set is %d bytes, no more than ARG_MAX's %d", len(blocked), max)
	}
	var out, errb bytes.Buffer
	if code := Run([]string{"reaction", "check", "tk-sub", "--run", "tk-root"}, "test", &out, &errb); code != 0 {
		t.Fatalf("the check exited %d: %s%s", code, out.String(), errb.String())
	}
	if !strings.Contains(out.String(), "tk-sub takes this first reaction (run tk-root)") {
		t.Errorf("the check said %q", out.String())
	}
	if len(calls(t, log, "bd --db "+store+" blocked --json")) != 1 {
		t.Errorf("the check made no read of the blocked set: %v", calls(t, log, ""))
	}
}

// The sweep's dry run, over the same city, lists the subject as a candidate it
// would sling, from one read of the ready set by priority, and slings nothing.
func TestReactionSweepDryRunListsTheSubject(t *testing.T) {
	log, _ := stubCity(t, bigBlocked(argMax(t)))
	var out, errb bytes.Buffer
	if code := Run([]string{"reaction", "sweep", "--dry-run"}, "test", &out, &errb); code != 0 {
		t.Fatalf("the dry run exited %d: %s", code, errb.String())
	}
	var line reaction.Swept
	if err := json.Unmarshal(out.Bytes(), &line); err != nil || line.ID != "tk-sub" || line.Outcome != reaction.WouldSling || line.Priority != 2 {
		t.Errorf("the dry run printed %q (%v)", out.String(), err)
	}
	if ready := calls(t, log, "bd "); len(calls(t, log, "sling")) > 0 || !slices.ContainsFunc(ready, func(l string) bool {
		return strings.HasSuffix(l, "ready --unassigned --exclude-type=epic --sort priority --json --limit 0")
	}) {
		t.Errorf("the dry run's calls were %v", calls(t, log, ""))
	}
}

// No command reads the city's rig list, however many questions it asks: the
// dispose slings its closer with no question about the pool first, the sling's
// subject is in the store gc resolves here, and the order gives the sweep its
// store. Each makes one ready read at most.
func TestReactionVerbsReadNoRigList(t *testing.T) {
	log, store := stubCity(t, []byte("[]"))
	for name, c := range map[string]struct {
		args  []string
		sling string
	}{
		"a sling":   {[]string{"reaction", "sling", "tk-sub"}, "sling --rig gc-toolkit gc-toolkit/gc-toolkit.proactive tk-sub --on mol-first-reaction"},
		"a sweep":   {[]string{"reaction", "sweep", "--db", store}, "sling --rig gc-toolkit gc-toolkit/gc-toolkit.proactive tk-sub --on mol-first-reaction"},
		"a dispose": {[]string{"reaction", "dispose", "tk-sub", "--disposition", "close", "--reason", "nothing to do", "--takeaway", "nothing to do"}, "sling --rig gc-toolkit gc-toolkit/gc-toolkit.polecat tk-sub --on mol-validate-close"},
	} {
		if err := os.WriteFile(log, nil, 0o644); err != nil {
			t.Fatal(err)
		}
		var out, errb bytes.Buffer
		if code := Run(c.args, "test", &out, &errb); code != 0 {
			t.Errorf("%s exited %d: %s", name, code, errb.String())
			continue
		}
		if got := calls(t, log, "rig list"); len(got) != 0 {
			t.Errorf("%s read the rig list %d times: %v", name, len(got), calls(t, log, ""))
		}
		if got := len(calls(t, log, "bd --db "+store+" ready")); got > 1 {
			t.Errorf("%s read the ready set %d times", name, got)
		}
		if !slices.Contains(calls(t, log, "sling"), c.sling) {
			t.Errorf("%s slung %v, want %q", name, calls(t, log, "sling"), c.sling)
		}
	}
}

// gc sling's refusal of a second live reaction reaches the sling's caller as
// 3, naming the run it names, and any other failure as 1.
func TestReactionSlingPassesGcSlingsRefusalThrough(t *testing.T) {
	stubCity(t, []byte("[]"))
	t.Setenv("STUB_SLING_RC", "3")
	t.Setenv("STUB_SLING_OUT", "gc sling: source bead tk-sub already has live workflow(s): tk-root-race")
	var out, errb bytes.Buffer
	if code := Run([]string{"reaction", "sling", "tk-sub"}, "test", &out, &errb); code != 3 || !strings.Contains(errb.String(), "gc sling found a first reaction already running on it (tk-root-race)") {
		t.Errorf("a sling gc sling refused for a live run exited %d: %s", code, errb.String())
	}
	t.Setenv("STUB_SLING_RC", "1")
	t.Setenv("STUB_SLING_OUT", "gc sling: no such target")
	errb.Reset()
	if code := Run([]string{"reaction", "sling", "tk-sub"}, "test", &out, &errb); code != 1 || !strings.Contains(errb.String(), "gc sling refused or failed on tk-sub (exit 1: gc sling: no such target)") {
		t.Errorf("a sling gc sling failed exited %d: %s", code, errb.String())
	}
}

// withMetadata makes the stub city's subject carry metadata, a JSON object as
// bd prints it, each value typed as bd stores it, and empties the log.
func withMetadata(t *testing.T, log, metadata string) {
	t.Helper()
	subject := `[{"id":"tk-sub","title":"the subject","status":"open","issue_type":"task","priority":2,"description":"a raw input bead","metadata":` + metadata + `}]`
	if err := os.WriteFile(filepath.Join(filepath.Dir(log), "subject.json"), []byte(subject), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(log, nil, 0o644); err != nil {
		t.Fatal(err)
	}
}

// Intake reads a subject's anchor as the scripts read it. bd stores an anchor
// spelled false as JSON false, and a false or null anchor names no bead, so a
// subject with no parent that carries one is held for placement instead of
// reaching the pool. An anchor that names a bead admits the subject to the
// pool as PR-finishing work.
func TestReactionDisposeReadsAFalseAnchorAsNone(t *testing.T) {
	log, _ := stubCity(t, []byte("[]"))
	for anchor, admitted := range map[string]bool{`false`: false, `null`: false, `"tk-anchor"`: true} {
		withMetadata(t, log, `{"anchor_bead":`+anchor+`}`)
		var out, errb bytes.Buffer
		if code := Run([]string{"reaction", "dispose", "tk-sub", "--disposition", "actionable", "--reason", "ordinary work", "--takeaway", "ordinary work"}, "test", &out, &errb); code != 0 {
			t.Errorf("an anchor of %s: the dispose exited %d: %s", anchor, code, errb.String())
			continue
		}
		routed := slices.ContainsFunc(calls(t, log, "sling "), func(l string) bool {
			return strings.Contains(l, "sling gc-toolkit/gc-toolkit.polecat tk-sub --no-formula --no-convoy")
		})
		held := slices.ContainsFunc(calls(t, log, "bd "), func(l string) bool { return strings.Contains(l, " update tk-sub --add-label hold:mayor ") })
		if routed != admitted || held == admitted {
			t.Errorf("an anchor of %s was routed %t and held %t, want routed %t: %v", anchor, routed, held, admitted, calls(t, log, ""))
		}
	}
}

// The check reads a subject's route as the scripts read it: a route bd stored
// as JSON false names no pool queue, so the subject takes the reaction, and a
// route that names one is a dispatch path, which refuses it.
func TestReactionCheckReadsAFalseRouteAsNone(t *testing.T) {
	log, _ := stubCity(t, []byte("[]"))
	withMetadata(t, log, `{"gc.routed_to":false}`)
	var out, errb bytes.Buffer
	if code := Run([]string{"reaction", "check", "tk-sub", "--run", "tk-root"}, "test", &out, &errb); code != 0 || !strings.Contains(out.String(), "tk-sub takes this first reaction") {
		t.Errorf("a route of false: exit %d, %q %q", code, out.String(), errb.String())
	}
	withMetadata(t, log, `{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}`)
	out.Reset()
	errb.Reset()
	if code := Run([]string{"reaction", "check", "tk-sub", "--run", "tk-root"}, "test", &out, &errb); code != reaction.Decided || !strings.Contains(errb.String(), "it already has a dispatch path (gc.routed_to=gc-toolkit/gc-toolkit.polecat)") {
		t.Errorf("a route to a pool: exit %d, %q", code, errb.String())
	}
}

// The sweep reads the keys that set a bead apart from raw input as the scripts
// read them, `(.metadata[k] // "")`, over values bd stored typed: false and null
// hold no value, so a ready bead whose keys hold only those is a candidate, and
// any other value, true, a number and the string "false" among them, passes the
// bead over.
func TestReactionSweepReadsTypedKeysAsTheScriptsDo(t *testing.T) {
	log, store := stubCity(t, []byte("[]"))
	keys := []string{"gc.routed_to", "gc.step_ref", "gc.step_id", "gc.root_bead_id", "gc.takeaway", "gc.takeaway_by",
		"branch", "merge_result", "work_dir", "pr_url", "pr_number", "check_name", "anchor_bead"}
	listed := func(metadata string) bool {
		t.Helper()
		withMetadata(t, log, metadata)
		var out, errb bytes.Buffer
		if code := Run([]string{"reaction", "sweep", "--dry-run", "--db", store}, "test", &out, &errb); code != 0 {
			t.Fatalf("the dry run over %s exited %d: %s", metadata, code, errb.String())
		}
		return strings.Contains(out.String(), `"id":"tk-sub"`)
	}
	for _, unset := range []string{"false", "null"} {
		fields := make([]string, len(keys))
		for i, k := range keys {
			fields[i] = strconv.Quote(k) + ":" + unset
		}
		if !listed("{" + strings.Join(fields, ",") + "}") {
			t.Errorf("a bead whose keys all hold %s was passed over", unset)
		}
	}
	for _, k := range keys {
		for _, set := range []string{"true", "0", `"false"`} {
			if listed("{" + strconv.Quote(k) + ":" + set + "}") {
				t.Errorf("a bead whose %s holds %s was listed", k, set)
			}
		}
	}
}
