package memory

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	cfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/claudecode/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// noon is the intake's clock in every test unless it names another.
var noon = time.Date(2026, 11, 15, 12, 0, 0, 0, time.UTC)

// A city is a test's city: its root, each rig's checkout and store, the memory
// directory Claude Code names for each place, and the clock.
type city struct {
	t      *testing.T
	root   string
	rt     *gfake.Runtime
	claude *cfake.Claude
	stores map[string]*fake.Store
	now    time.Time
	in     *Intake
}

// newCity is a city whose HQ, the city's root, keeps no memory directory.
func newCity(t *testing.T) *city {
	t.Helper()
	root := realDir(t, t.TempDir())
	c := &city{t: t, root: root, now: noon, stores: map[string]*fake.Store{}}
	c.rt = &gfake.Runtime{Root: root, Settings: filepath.Join(root, ".gc", "settings.json"),
		RigList: []gascity.Rig{{Name: "town", Path: root, Prefix: "lx", HQ: true}}}
	c.claude = &cfake.Claude{Dirs: map[string]string{root: filepath.Join(root, "memory", "town") + "/"}, Version: "2.1.326"}
	c.stores[filepath.Join(root, ".beads")] = fake.New()
	c.in = &Intake{Runtime: c.rt, Claude: c.claude, Now: func() time.Time { return c.now }, LockWait: time.Second,
		Store: func(db string) (*ledger.Ledger, error) {
			s, ok := c.stores[db]
			if !ok {
				return nil, fmt.Errorf("no store at %s", db)
			}
			return ledger.New(s), nil
		}}
	return c
}

func realDir(t *testing.T, d string) string {
	t.Helper()
	r, err := filepath.EvalSymlinks(d)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

// rig adds a rig whose sessions keep memory in a directory of its own, and
// returns that directory, made.
func (c *city) rig(name, prefix string) string {
	c.t.Helper()
	co := c.checkout(name)
	mem := filepath.Join(c.root, "memory", name)
	for _, d := range []string{co, mem} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			c.t.Fatal(err)
		}
	}
	c.rt.RigList = append(c.rt.RigList, gascity.Rig{Name: name, Path: co, Prefix: prefix})
	c.claude.Dirs[co] = mem + "/"
	c.stores[filepath.Join(co, ".beads")] = fake.New()
	return mem
}

func (c *city) checkout(name string) string { return filepath.Join(c.root, "rigs", name) }

func (c *city) store(name string) *fake.Store {
	return c.stores[filepath.Join(c.checkout(name), ".beads")]
}

// state is the state of the memory directory dir.
func (c *city) state(dir string) string {
	return filepath.Join(append(append([]string{c.root}, stateDir...), sum(realDir(c.t, dir)))...)
}

func (c *city) due() []Due {
	c.t.Helper()
	d, err := c.in.Due()
	if err != nil {
		c.t.Fatal(err)
	}
	return d.Due
}

func (c *city) apply(decisions ...string) Applied {
	c.t.Helper()
	a, err := c.in.Apply(strings.Join(decisions, "\n") + "\n")
	if err != nil {
		c.t.Fatal(err)
	}
	return a
}

func (c *city) settle() Settled {
	c.t.Helper()
	s, err := c.in.Settle()
	if err != nil {
		c.t.Fatal(err)
	}
	return s
}

// refOf is the ref the due list gives the note name, "" when it is not due.
func refOf(ds []Due, name string) string {
	for _, d := range ds {
		if d.Kind == Note && filepath.Base(d.File) == name {
			return d.Ref
		}
	}
	return ""
}

// entryRef is the ref of the due entry whose text holds text.
func entryRef(ds []Due, text string) string {
	for _, d := range ds {
		if d.Kind == Entry && strings.Contains(d.Text, text) {
			return d.Ref
		}
	}
	return ""
}

// dueOf is why the note name is due, "" when it is not.
func dueOf(ds []Due, name string) string {
	for _, d := range ds {
		if filepath.Base(d.File) == name {
			return d.Why
		}
	}
	return ""
}

func names(ds []Due) string {
	var out []string
	for _, d := range ds {
		out = append(out, filepath.Base(d.File)+":"+d.Why)
	}
	return strings.Join(out, " ")
}

// write writes text to file, and sets its modification time to at when given.
func write(t *testing.T, file, text string, at ...time.Time) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	if len(at) > 0 {
		if err := os.Chtimes(file, at[0], at[0]); err != nil {
			t.Fatal(err)
		}
	}
}

func appendTo(t *testing.T, file, text string) {
	t.Helper()
	f, err := os.OpenFile(file, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	if _, err := f.WriteString(text); err != nil {
		t.Fatal(err)
	}
}

// openAppend opens file to append to, as a writer holds it open, and closes it
// when the test ends.
func openAppend(t *testing.T, file string) *os.File {
	t.Helper()
	f, err := os.OpenFile(file, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = f.Close() })
	return f
}

// saveByRename saves text to file through a new file beside it, renamed onto
// the name, as an atomic save does.
func saveByRename(t *testing.T, file, text string) {
	t.Helper()
	write(t, file+".tmp.0a1b2c3d", text)
	if err := os.Rename(file+".tmp.0a1b2c3d", file); err != nil {
		t.Fatal(err)
	}
}

// landAt runs land the first time a write reaches step, as an agent's save
// would land there, with the file the write is on.
func landAt(t *testing.T, step string, land func(file string)) {
	t.Helper()
	prev, done := beforeStep, false
	beforeStep = func(s, file string) {
		prev(s, file)
		if s == step && !done {
			done = true
			land(file)
		}
	}
	t.Cleanup(func() { beforeStep = func(string, string) {} })
}

// landOn runs land each time a write to file reaches step, as an agent's saves
// would land there.
func landOn(t *testing.T, step, file string, land func()) {
	t.Helper()
	prev := beforeStep
	beforeStep = func(s, f string) {
		prev(s, f)
		if s == step && f == file {
			land()
		}
	}
	t.Cleanup(func() { beforeStep = func(string, string) {} })
}

// killedAt runs write and stops it the first time it reaches step, as a kill
// there would, so the test reads what the kill leaves.
func killedAt(t *testing.T, step string, write func()) {
	t.Helper()
	type kill struct{}
	landAt(t, step, func(string) { panic(kill{}) })
	defer func() {
		switch r := recover(); r.(type) {
		case kill:
		case nil:
			t.Errorf("the write never reached %q", step)
		default:
			panic(r)
		}
	}()
	write()
}

// beside is the text of each file in file's directory other than file, by
// name.
func beside(t *testing.T, file string) map[string]string {
	t.Helper()
	entries, err := os.ReadDir(filepath.Dir(file))
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for _, e := range entries {
		if p := filepath.Join(filepath.Dir(file), e.Name()); p != file && !e.IsDir() {
			out[e.Name()] = read(t, p)
		}
	}
	return out
}

// displaced is the text of each file in the aside folder of file's directory,
// by name.
func displaced(t *testing.T, file string) map[string]string {
	t.Helper()
	dir := filepath.Join(filepath.Dir(file), asideDir)
	entries, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for _, e := range entries {
		out[e.Name()] = read(t, filepath.Join(dir, e.Name()))
	}
	return out
}

// holds reports whether one of files holds text.
func holds(files map[string]string, text string) bool {
	for _, got := range files {
		if got == text {
			return true
		}
	}
	return false
}

func read(t *testing.T, file string) string {
	t.Helper()
	raw, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

func exists(file string) bool {
	_, err := os.Stat(file)
	return err == nil
}

func day(s string) time.Time {
	d, err := time.Parse(time.DateOnly, s)
	if err != nil {
		panic(err)
	}
	return d.Add(12 * time.Hour)
}

// said reports whether any line of lines holds text.
func said(lines []string, text string) bool {
	return slices.ContainsFunc(lines, func(l string) bool { return strings.Contains(l, text) })
}

// pattern is an open feedback pattern.
func openPattern(id string) fake.Bead {
	return fake.Bead{ID: id, Status: "open", Metadata: map[string]string{"task_kind": pattern}}
}

// stamped is a note whose front matter carries Claude Code's stamp, as it
// writes a note it has saved.
func stamped(name, body string) string {
	return "---\nname: " + name + "\ndescription: \"" + name + ": a lesson\"\nmetadata:\n  node_type: memory\n" +
		"  type: feedback\n  originSessionId: 7c4d1d53-ce89-4d01-a65c-0710d826477c\n" +
		"  modified: 2026-11-12T12:00:00.000Z\n---\n\n" + body + "\n"
}

// save is an agent's save of a stamped note through Claude Code: the line added
// at its end, and its modified stamp set to at.
func save(t *testing.T, file, at, line string) {
	t.Helper()
	var out []string
	done := false
	for _, l := range lines(read(t, file)) {
		if !done && strings.HasPrefix(l, "  modified: ") {
			l, done = "  modified: "+at, true
		}
		out = append(out, l)
	}
	write(t, file, joined(append(out, line)))
}

// gitIn runs git in dir.
func gitIn(t *testing.T, dir string, args ...string) string {
	t.Helper()
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

// origin makes dir a clone whose origin/HEAD names branch, with one commit on
// origin's branch and one off it, and returns both.
func origin(t *testing.T, dir, branch string) (on, off string) {
	t.Helper()
	gitEnv(t)
	run := func(args ...string) string { return gitIn(t, dir, args...) }
	run("init", "-q", "-b", branch)
	run("commit", "-q", "--allow-empty", "-m", "on")
	on = run("rev-parse", "HEAD")
	run("update-ref", "refs/remotes/origin/"+branch, on)
	run("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/"+branch)
	run("checkout", "-q", "-b", "side")
	run("commit", "-q", "--allow-empty", "-m", "off")
	off = run("rev-parse", "HEAD")
	return on, off
}

// gitEnv makes git read no config of the host's.
func gitEnv(t *testing.T) {
	t.Helper()
	cfg := filepath.Join(t.TempDir(), "gitconfig")
	if err := os.WriteFile(cfg, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for k, v := range map[string]string{
		"GIT_CONFIG_GLOBAL": cfg, "GIT_CONFIG_NOSYSTEM": "1",
		"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
		"GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com",
	} {
		t.Setenv(k, v)
	}
}

// merged is a closed bead whose merge commit sha landed on target.
func merged(id, sha, target string, meta ...string) fake.Bead {
	m := map[string]string{"merge_result": "merged", "merged_target": target, "merged_sha": sha}
	for i := 0; i+1 < len(meta); i += 2 {
		m[meta[i]] = meta[i+1]
	}
	return fake.Bead{ID: id, Status: "closed", ClosedAt: "2026-11-14T10:00:00Z", Metadata: m}
}

// closedPattern is a feedback pattern closed on 2026-11-14 with the keys given.
func closedPattern(id string, meta ...string) fake.Bead {
	m := map[string]string{"task_kind": pattern}
	for i := 0; i+1 < len(meta); i += 2 {
		m[meta[i]] = meta[i+1]
	}
	return fake.Bead{ID: id, Status: "closed", ClosedAt: "2026-11-14T10:00:00Z", Metadata: m}
}
