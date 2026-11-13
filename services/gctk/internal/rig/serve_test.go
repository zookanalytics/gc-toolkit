package rig

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"testing/synctest"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host/fake"
)

// A copy's rules run on host/fake, inside a synctest bubble: each process is
// a goroutine running the program the fixture names for what was started, and
// the bubble's clock is fake, so a wait or a grace passes at once. What the
// fake stands in for, the real processes, groups, listeners and sandbox, is
// tested at the adapter, in internal/host.

// serveFixture is two checkouts, a scripts directory that holds SandboxLib,
// and a fake machine whose programs are:
//   - the leader, `<binary> rig serve --lead <record>`, which runs Lead;
//   - a serve command, by its text: "fail" says "cannot serve" and exits 3,
//     "hang" runs and never listens, "missing" names no program, and any other
//     listens on its sandbox's port until it ends;
//   - a publish command, any other `bash -c`, by its mode, "publish <mode>":
//     ok stays running; again-once refuses its first run as Tailscale does
//     while another client changes the serve config; taken-first refuses the
//     first port it is given as Tailscale refuses a port another mapping
//     holds; fails refuses for another reason; ignores-term stays running
//     through SIGTERM; any other is ok;
//   - `listen <port>`, a process outside any copy that listens on the port;
//   - `stubborn <record>`, a leader that ignores SIGTERM and does nothing else.
type serveFixture struct {
	dir     string
	repo    string
	repo2   string
	scripts string
	m       *fake.Machine
	me      *fake.Process
	copies  *Copies

	mu        sync.Mutex
	served    []string
	published []string
	again     bool
	firstPort int
}

// serveTest runs body in a synctest bubble, on a fixture of its own.
func serveTest(t *testing.T, body func(t *testing.T, f *serveFixture)) {
	t.Helper()
	synctest.Test(t, func(t *testing.T) {
		body(t, newServeFixture(t))
	})
}

func newServeFixture(t *testing.T) *serveFixture {
	t.Helper()
	dir := t.TempDir()
	f := &serveFixture{dir: dir, repo: filepath.Join(dir, "a"), repo2: filepath.Join(dir, "b"),
		scripts: filepath.Join(dir, "scripts"), m: fake.New()}
	for _, d := range []string{f.repo, f.repo2, f.scripts} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(f.scripts, SandboxLib), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	f.me = f.m.Caller()
	f.m.Programs = f.program
	f.copies = NewCopies(filepath.Join(dir, "common"), f.me)
	t.Cleanup(f.m.Halt)
	return f
}

func (f *serveFixture) program(s host.Spec) fake.Program {
	a := s.Argv
	switch {
	case len(a) == 5 && a[1] == "rig" && a[2] == "serve" && a[3] == "--lead":
		return func(p *fake.Process) int { return Lead(p, a[4]) }
	case len(a) == 3 && a[0] == "bash" && a[1] == "-c" && s.Sandbox != nil:
		return f.serveProgram(a[2])
	case len(a) == 3 && a[0] == "bash" && a[1] == "-c":
		return f.publishProgram(strings.TrimPrefix(a[2], "publish "))
	case len(a) == 2 && a[0] == "listen":
		port, _ := strconv.Atoi(a[1])
		return func(p *fake.Process) int { p.Listen(port); <-p.Done(); return 0 }
	case len(a) == 2 && a[0] == "stubborn":
		return func(p *fake.Process) int {
			p.Ignore(syscall.SIGTERM)
			rec := copyRec{dir: a[1], h: p}
			me, _ := p.Proc(p.Pid())
			_ = rec.write("start_id", me.Started)
			_ = rec.write("pid", strconv.Itoa(p.Pid()))
			<-p.Done()
			return 0
		}
	}
	return nil
}

func (f *serveFixture) serveProgram(command string) fake.Program {
	switch command {
	case "fail":
		return func(p *fake.Process) int { fmt.Fprintln(p.Out(), "cannot serve"); return 3 }
	case "hang":
		return func(p *fake.Process) int { <-p.Done(); return 0 }
	case "missing":
		return nil
	}
	return func(p *fake.Process) int {
		s := p.Spec()
		p.Listen(s.Sandbox.Port)
		f.mu.Lock()
		f.served = append(f.served, fmt.Sprintf("%s %d", s.Dir, s.Sandbox.Port))
		f.mu.Unlock()
		fmt.Fprintf(p.Out(), "serving on %d\n", s.Sandbox.Port)
		<-p.Done()
		return 0
	}
}

func (f *serveFixture) publishProgram(mode string) fake.Program {
	return func(p *fake.Process) int {
		port := envPort(p.Spec())
		f.mu.Lock()
		f.published = append(f.published, fmt.Sprintf("%s %d", mode, port))
		refusal := ""
		switch mode {
		case "again-once":
			if !f.again {
				f.again = true
				refusal = "Another client is changing the serve config; please try again."
			}
		case "taken-first":
			if f.firstPort == 0 {
				f.firstPort = port
			}
			if port == f.firstPort {
				refusal = fmt.Sprintf("error: listener already exists for port %d", port)
			}
		case "fails":
			refusal = "access denied"
		}
		f.mu.Unlock()
		if refusal != "" {
			fmt.Fprintln(p.Out(), refusal)
			return 1
		}
		if mode == "ignores-term" {
			p.Ignore(syscall.SIGTERM)
		}
		fmt.Fprintf(p.Out(), "Available within your tailnet: https://host.example:%d/\n", port)
		<-p.Done()
		return 0
	}
}

// envPort is the PORT a start sets.
func envPort(s host.Spec) int {
	for _, kv := range s.Env {
		if v, ok := strings.CutPrefix(kv, "PORT="); ok {
			n, _ := strconv.Atoi(v)
			return n
		}
	}
	return 0
}

func (f *serveFixture) opts(command string) ServeOpts {
	return ServeOpts{Command: command, Wait: 20 * time.Second, ScriptsDir: f.scripts}
}

func (f *serveFixture) publishing(mode, pattern string) ServeOpts {
	o := f.opts("serve")
	o.Publish, o.PublishCommand, o.AddressPattern = true, "publish "+mode, pattern
	return o
}

func (f *serveFixture) rec(checkout string) copyRec { return f.copies.rec(checkout) }

// copiesOn returns the fixture's copies' directory as another gctk process
// sees it, one whose calls run on h.
func (f *serveFixture) copiesOn(h host.Host) *Copies {
	return NewCopies(filepath.Join(f.dir, "common"), h)
}

// gated is the host one call runs on in a test that drives two calls through
// an interleaving: before each signal the call sends, hold runs, and before
// each process it starts, starting runs, and either can wait there for the
// other call to reach a point of its own.
type gated struct {
	host.Host
	hold     func(pid int, sig syscall.Signal)
	starting func(s host.Spec)
}

func (g gated) Signal(pid int, sig syscall.Signal) error {
	if g.hold != nil {
		g.hold(pid, sig)
	}
	return g.Host.Signal(pid, sig)
}

func (g gated) Start(s host.Spec) (host.Child, error) {
	if g.starting != nil {
		g.starting(s)
	}
	return g.Host.Start(s)
}

// unkillable is the host one call runs on in a test where a copy's process
// group outlives SIGTERM and SIGKILL, as one stuck in the kernel does: the
// signals the call sends the group pgid names are lost.
type unkillable struct {
	host.Host
	pgid func() int
}

func (u unkillable) SignalGroup(pgid int, sig syscall.Signal) error {
	if pgid == u.pgid() {
		return nil
	}
	return u.Host.SignalGroup(pgid, sig)
}

// flags are the points calls in a test have reached.
type flags struct {
	mu  sync.Mutex
	set map[string]bool
}

func (fl *flags) mark(name string) {
	fl.mu.Lock()
	defer fl.mu.Unlock()
	if fl.set == nil {
		fl.set = map[string]bool{}
	}
	fl.set[name] = true
}

func (fl *flags) reached(name string) func() bool {
	return func() bool {
		fl.mu.Lock()
		defer fl.mu.Unlock()
		return fl.set[name]
	}
}

func (f *serveFixture) leader(checkout string) int {
	pid, _ := f.rec(checkout).num("pid")
	return pid
}

func (f *serveFixture) publisherOf(checkout string) int {
	_, pid := f.rec(checkout).publisher()
	return pid
}

func (f *serveFixture) running(pid int) bool {
	_, ok := f.me.Proc(pid)
	return ok
}

func (f *serveFixture) list(l *[]string) []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(*l)
}

// starts returns the starts of one kind: "leader", "serve" or "publish".
func (f *serveFixture) starts(kind string) []fake.Start {
	var out []fake.Start
	for _, s := range f.m.Starts() {
		a := s.Spec.Argv
		switch {
		case kind == "leader" && len(a) == 5 && a[3] == "--lead",
			kind == "serve" && s.Spec.Sandbox != nil,
			kind == "publish" && s.Spec.Sandbox == nil && len(a) == 3 && a[0] == "bash":
			out = append(out, s)
		}
	}
	return out
}

// endOf returns a process's end.
func (f *serveFixture) endOf(t *testing.T, pid int) fake.End {
	t.Helper()
	for _, e := range f.m.Ends() {
		if e.Pid == pid {
			return e
		}
	}
	t.Fatalf("process %d has not ended", pid)
	return fake.End{}
}

// claim writes a record as a start does before it runs the leader, with the
// values given on top.
func (f *serveFixture) claim(t *testing.T, checkout string, values map[string]string) copyRec {
	t.Helper()
	if err := os.MkdirAll(f.copies.root, 0o755); err != nil {
		t.Fatal(err)
	}
	rec := f.rec(checkout)
	if err := os.Mkdir(rec.dir, 0o755); err != nil {
		t.Fatal(err)
	}
	base := map[string]string{"checkout": checkout, "scripts": f.scripts,
		"grace_ms": strconv.FormatInt(StopGrace.Milliseconds(), 10)}
	for k, v := range values {
		base[k] = v
	}
	for k, v := range base {
		if err := rec.write(k, v); err != nil {
			t.Fatal(err)
		}
	}
	return rec
}

func readFile(path string) string {
	b, _ := os.ReadFile(path)
	return string(b)
}

func mustRun(t *testing.T, r Report) {
	t.Helper()
	if r.State != CopyRunning {
		t.Fatalf("state = %s (%s: %s), want running\n%s", r.State, r.Reason, r.Detail, r.Tail)
	}
}

func address(r Report) string {
	if r.Address == nil {
		return "<none>"
	}
	return *r.Address
}

// waitFor polls cond for up to bound, on the bubble's clock.
func waitFor(bound time.Duration, cond func() bool) bool {
	deadline := time.Now().Add(bound)
	for !cond() {
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(100 * time.Millisecond)
	}
	return true
}

func TestServeRunsTheCommandInTheSandboxFromTheCheckoutOnAPortOfItsOwn(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		r := f.copies.Serve(f.repo, f.opts("serve"))
		mustRun(t, r)
		if r.Port <= 0 || !f.me.Answers(r.Port) {
			t.Fatalf("the copy does not answer on the port it reports, %d", r.Port)
		}
		if address(r) != "" || !strings.Contains(r.Detail, "started without --publish-command") {
			t.Errorf("address %q, detail %q: want no address, and why", address(r), r.Detail)
		}
		if got, want := f.list(&f.served), []string{f.repo + " " + strconv.Itoa(r.Port)}; !slices.Equal(got, want) {
			t.Errorf("served %q, want %q: the command runs from the checkout on the copy's port", got, want)
		}

		// The serve command runs inside the sandbox, from the checkout, with the
		// copy's port as PORT and as the one port the sandbox opens, and writes
		// into the log through the leader's relay.
		serves := f.starts("serve")
		if len(serves) != 1 {
			t.Fatalf("%d serve commands started, want 1", len(serves))
		}
		s := serves[0].Spec
		want := host.Sandbox{Lib: filepath.Join(f.scripts, SandboxLib), Port: r.Port, Prog: "gctk rig serve"}
		if *s.Sandbox != want || s.Dir != f.repo || !slices.Equal(s.Argv, []string{"bash", "-c", "serve"}) ||
			!slices.Contains(s.Env, "PORT="+strconv.Itoa(r.Port)) || !s.Relay {
			t.Errorf("the serve command started as %+v in sandbox %+v, want bash -c serve from %s, PORT=%d, relayed, in %+v",
				s, *s.Sandbox, f.repo, r.Port, want)
		}
		if log := readFile(r.Log); !strings.Contains(log, "serving on "+strconv.Itoa(r.Port)) {
			t.Errorf("the serve command's output is not in the log %s: %q", r.Log, log)
		}
		if n := len(f.starts("publish")); n != 0 {
			t.Errorf("%d publish commands ran", n)
		}

		// The leader leads a group of its own as the start's child, with the
		// caller's environment whole, since the orphan sweep reads the session's
		// values from it, and the serve command is a member of its group.
		leader := f.leader(f.repo)
		leaders := f.starts("leader")
		if len(leaders) != 1 || leaders[0].Pid != leader || leaders[0].Parent != f.me.Pid() {
			t.Fatalf("leader starts %+v, want one, pid %d, the caller's child", leaders, leader)
		}
		if l := leaders[0].Spec; !l.Session || len(l.Env) != 0 || l.Sandbox != nil {
			t.Errorf("the leader started as %+v, want a session of its own and the caller's environment whole, outside the sandbox", l)
		}
		if p, _ := f.me.Proc(leader); p.Group != leader {
			t.Errorf("the leader's group is %d, want its own, %d", p.Group, leader)
		}
		if p, _ := f.me.Proc(serves[0].Pid); p.Group != leader {
			t.Errorf("the serve command runs in group %d, want the copy's, %d", p.Group, leader)
		}

		again := f.copies.Serve(f.repo, f.opts("serve"))
		mustRun(t, again)
		if again.Port != r.Port || f.leader(f.repo) != leader || len(f.list(&f.served)) != 1 {
			t.Errorf("a second start ran a second copy: port %d (was %d), leader %d (was %d), served %q",
				again.Port, r.Port, f.leader(f.repo), leader, f.list(&f.served))
		}
		// The start that ran the copy says so, and one that found it running does
		// not, so a caller stops only a copy its own start ran.
		if !r.Started || again.Started {
			t.Errorf("started = %v on the start that ran the copy and %v on the one that found it, want true and false", r.Started, again.Started)
		}
		for _, c := range []struct {
			rep  Report
			want bool
		}{{r, true}, {again, false}} {
			raw, err := json.Marshal(c.rep)
			if err != nil {
				t.Fatal(err)
			}
			if got := strings.Contains(string(raw), `"started":true`); got != c.want {
				t.Errorf("the report %s carries \"started\":true = %v, want %v", raw, got, c.want)
			}
		}
		if c := f.copies.Check(f.repo); c.State != CopyRunning || c.Port != r.Port {
			t.Errorf("check = %s on %d, want running on %d", c.State, c.Port, r.Port)
		}

		// A start with another command, such as a capture that adds the fixture's
		// flags, would show another app, so it fails and leaves the copy running.
		busy := f.copies.Serve(f.repo, f.opts("serve --answers x"))
		if busy.State != CopyFailed || busy.Reason != "other-command" || !strings.Contains(busy.Detail, "(serve)") {
			t.Errorf("a start with another command = %s %s (%s), want failed other-command naming the running command", busy.State, busy.Reason, busy.Detail)
		}
		if f.leader(f.repo) != leader || !f.me.Answers(r.Port) || len(f.starts("serve")) != 1 {
			t.Errorf("a start with another command touched the running copy: leader %d (was %d), serve starts %d", f.leader(f.repo), leader, len(f.starts("serve")))
		}

		other := f.copies.Serve(f.repo2, f.opts("serve"))
		mustRun(t, other)
		if other.Port == r.Port || !f.me.Answers(other.Port) || !f.me.Answers(r.Port) {
			t.Errorf("a second checkout's copy does not run beside the first: ports %d and %d", r.Port, other.Port)
		}

		if s := f.copies.Stop(f.repo); s.State != CopyStopped {
			t.Fatalf("stop = %s (%s), want stopped", s.State, s.Detail)
		}
		if !f.me.GroupGone(leader) {
			t.Errorf("members of the copy's group are left: %v", f.me.Members(leader))
		}
		if f.me.Answers(r.Port) {
			t.Error("the stopped copy's port still answers")
		}
		if c := f.copies.Check(f.repo); c.State != CopyNone {
			t.Errorf("check after stop = %s, want none", c.State)
		}
		if s := f.copies.Stop(f.repo); s.State != CopyNone {
			t.Errorf("a stop with no copy running = %s, want none", s.State)
		}
		if c := f.copies.Check(f.repo2); c.State != CopyRunning {
			t.Errorf("stopping one checkout's copy left the other's %s", c.State)
		}
		f.copies.Stop(f.repo2)
	})
}

// A stop sends the copy's group SIGTERM. The members end, and the leader ends
// last, once none is left, without waiting out the grace.
func TestServeAStopEndsTheMembersFirstAndTheLeaderLast(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		mustRun(t, f.copies.Serve(f.repo, f.publishing("ok", "https://host.example:$PORT/")))
		leader, pub, served := f.leader(f.repo), f.publisherOf(f.repo), f.starts("serve")[0].Pid
		start := time.Now()
		if s := f.copies.Stop(f.repo); s.State != CopyStopped {
			t.Fatalf("stop = %s (%s), want stopped", s.State, s.Detail)
		}
		ends := f.m.Ends()
		at := func(pid int) int {
			return slices.IndexFunc(ends, func(e fake.End) bool { return e.Pid == pid })
		}
		if at(leader) < at(served) || at(leader) < at(pub) {
			t.Errorf("ends %+v: want the serve command %d and the publish command %d before the leader %d", ends, served, pub, leader)
		}
		if e := f.endOf(t, leader); e.Status != 128+int(syscall.SIGTERM) || e.At.Sub(start) >= StopGrace {
			t.Errorf("the leader ended %+v, %s after the stop: want 143, before the grace of %s", e, e.At.Sub(start), StopGrace)
		}
	})
}

func TestServePublishesOnlyWhenAskedAndTiesThePublisherToTheCopy(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		pattern := "https://host.example:$PORT/x/${PORT}"
		r := f.copies.Serve(f.repo, f.publishing("ok", pattern))
		mustRun(t, r)
		want := "https://host.example:" + strconv.Itoa(r.Port) + "/x/" + strconv.Itoa(r.Port)
		if address(r) != want {
			t.Errorf("address = %q, want the pattern with the port for each $PORT and ${PORT}, %q", address(r), want)
		}
		if got := f.list(&f.published); !slices.Equal(got, []string{"ok " + strconv.Itoa(r.Port)}) {
			t.Errorf("published %q, want one run with the port as PORT", got)
		}
		leader, pub := f.leader(f.repo), f.publisherOf(f.repo)
		if p, ok := f.me.Proc(pub); !ok || p.Group != leader || p.Parent != leader {
			t.Errorf("the publish command runs as %+v, want the leader's child in the copy's group, %d", p, leader)
		}
		if s := f.starts("publish")[0].Spec; s.Dir != f.repo || s.Session || s.Relay {
			t.Errorf("the publish command started as %+v, want it from the checkout, in the copy's group", s)
		}
		if c := f.copies.Check(f.repo); address(c) != want {
			t.Errorf("check reports address %q, want %q", address(c), want)
		}

		// A publish command that ends alone leaves the copy running with no
		// address, until a start publishes it again.
		_ = f.me.Signal(pub, syscall.SIGKILL)
		c := f.copies.Check(f.repo)
		if c.State != CopyRunning || address(c) != "" || !strings.Contains(c.Detail, "publish command ended") {
			t.Errorf("check = %s, address %q, detail %q: want running, no address, and why", c.State, address(c), c.Detail)
		}
		// A pid the record names for its publisher that a process outside the
		// copy took gives no address either.
		if err := f.rec(f.repo).write("publisher", "1 "+strconv.Itoa(f.me.Pid())); err != nil {
			t.Fatal(err)
		}
		if c := f.copies.Check(f.repo); address(c) != "" {
			t.Errorf("a publisher pid that is not the leader's child gives the address %q", address(c))
		}
		again := f.copies.Serve(f.repo, f.publishing("ok", pattern))
		mustRun(t, again)
		if again.Port != r.Port || address(again) != want || f.leader(f.repo) != leader || len(f.list(&f.published)) != 2 {
			t.Errorf("a start did not publish the copy again: port %d, address %q, leader %d (was %d), published %q",
				again.Port, address(again), f.leader(f.repo), leader, f.list(&f.published))
		}
		if again.Started {
			t.Error("a start that published a running copy again says it ran the copy")
		}
		pub = f.publisherOf(f.repo)
		f.copies.Stop(f.repo)
		if !f.me.GroupGone(leader) || f.running(pub) {
			t.Error("stop left the publish command running")
		}
	})
}

// A start for a published copy decides on its publish command and address
// pattern before the record changes, while the publisher the record names
// runs.
func TestServeRefusesAnotherPublicationWhileThePublishCommandRuns(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		old := "https://old.example:$PORT/"
		r := f.copies.Serve(f.repo, f.publishing("ok", old))
		mustRun(t, r)
		want := addressFor(old, r.Port)
		if address(r) != want {
			t.Fatalf("address = %q, want %q", address(r), want)
		}
		leader, pub := f.leader(f.repo), f.publisherOf(f.repo)

		// While the publish command runs, a start that asks for another publish
		// command, another address pattern or none changes nothing: it fails, and
		// the copy keeps its publish command and the address that command gives.
		noPublisher := f.opts("serve")
		noPublisher.Publish = true
		for name, o := range map[string]ServeOpts{
			"another publish command": f.publishing("other", old),
			"another address pattern": f.publishing("ok", "https://new.example:$PORT/"),
			"no publish command":      noPublisher,
		} {
			busy := f.copies.Serve(f.repo, o)
			if busy.State != CopyFailed || busy.Reason != "other-publisher" || !strings.Contains(busy.Detail, want) || !strings.Contains(busy.Detail, "--stop") {
				t.Errorf("a start with %s = %s %s (%s), want failed other-publisher naming the address it is published at and how to stop it", name, busy.State, busy.Reason, busy.Detail)
			}
			if busy.Address != nil || busy.Started {
				t.Errorf("a start with %s reports address %q, started %v, want neither", name, address(busy), busy.Started)
			}
			c := f.copies.Check(f.repo)
			if c.State != CopyRunning || address(c) != want {
				t.Errorf("after a start with %s, check = %s at %q, want running at %q", name, c.State, address(c), want)
			}
			if now := f.publisherOf(f.repo); now != pub || !f.rec(f.repo).publisherAlive() {
				t.Errorf("after a start with %s the publish command is %d (alive %v), want the first one, %d, still running", name, now, f.rec(f.repo).publisherAlive(), pub)
			}
			for k, v := range map[string]string{"publish_command": "publish ok", "address_pattern": old, "address": want} {
				if got := f.rec(f.repo).read(k); got != v {
					t.Errorf("after a start with %s the record's %s is %q, want %q", name, k, got, v)
				}
			}
			if got := f.list(&f.published); !slices.Equal(got, []string{"ok " + strconv.Itoa(r.Port)}) {
				t.Errorf("after a start with %s the publish commands run are %q, want only the first", name, got)
			}
			if f.leader(f.repo) != leader || !f.me.Answers(r.Port) {
				t.Errorf("a start with %s touched the copy: leader %d (was %d)", name, f.leader(f.repo), leader)
			}
		}

		// The same values report the copy at its address, and publish nothing more.
		same := f.copies.Serve(f.repo, f.publishing("ok", old))
		mustRun(t, same)
		if address(same) != want || len(f.list(&f.published)) != 1 {
			t.Errorf("a start with the same values: address %q, published %q, want %q and one run", address(same), f.list(&f.published), want)
		}

		// Once the publish command has ended, a start publishes the copy again with
		// the values it passes, and reports the address they give.
		_ = f.me.Signal(pub, syscall.SIGKILL)
		newer := "https://new.example:$PORT/"
		again := f.copies.Serve(f.repo, f.publishing("ok", newer))
		mustRun(t, again)
		if want := addressFor(newer, r.Port); address(again) != want || address(f.copies.Check(f.repo)) != want {
			t.Errorf("a start once the publish command ended: address %q, check %q, want %q", address(again), address(f.copies.Check(f.repo)), want)
		}
		if got := f.list(&f.published); len(got) != 2 {
			t.Errorf("published %q, want a second run", got)
		}
		f.copies.Stop(f.repo)
	})
}

func TestServeACopyThatEndsTakesItsPublishCommandWithIt(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		mustRun(t, f.copies.Serve(f.repo, f.publishing("ok", "https://host.example:$PORT/")))
		leader, pub := f.leader(f.repo), f.publisherOf(f.repo)
		start := time.Now()
		_ = f.me.Signal(f.starts("serve")[0].Pid, syscall.SIGTERM)
		if !waitFor(StopGrace+10*time.Second, func() bool { return f.me.GroupGone(leader) }) {
			t.Fatalf("the leader did not end the group once the serve command ended: %v", f.me.Members(leader))
		}
		if p, l := f.endOf(t, pub), f.endOf(t, leader); !p.At.Equal(start) || !l.At.Equal(start) || p.Status != 143 {
			t.Errorf("the publish command ended %+v and the leader %+v, %s and %s after the serve command: want the group ended at once by SIGTERM",
				p, l, p.At.Sub(start), l.At.Sub(start))
		}
		c := f.copies.Check(f.repo)
		if c.State != CopyDied || c.ExitCode == nil || *c.ExitCode != 143 {
			t.Errorf("check = %s, exit %v: want died, with the serve command's 143", c.State, c.ExitCode)
		}
		r := f.copies.Serve(f.repo, f.opts("serve"))
		mustRun(t, r)
		if f.leader(f.repo) == leader {
			t.Error("the new copy runs under the old leader's pid")
		}
		if !r.Started {
			t.Error("the start that ran a new copy in place of the one that ended does not say it started it")
		}
		f.copies.Stop(f.repo)
	})
}

// Two starts at once find no copy running, and the one that takes the
// checkout's lock first runs the copy. The other reports that copy, so exactly
// one says it started it.
func TestServeTwoStartsAtOnceRunOneCopyAndOneSaysItStartedIt(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		reps := make(chan Report, 2)
		for i := 0; i < 2; i++ {
			go func() { reps <- f.copies.Serve(f.repo, f.opts("serve")) }()
		}
		a, b := <-reps, <-reps
		mustRun(t, a)
		mustRun(t, b)
		if a.Port != b.Port || len(f.list(&f.served)) != 1 {
			t.Errorf("two starts at once ran two copies: ports %d and %d, served %q", a.Port, b.Port, f.list(&f.served))
		}
		if a.Started == b.Started {
			t.Errorf("started = %v and %v, want exactly one start to say it ran the copy", a.Started, b.Started)
		}
		f.copies.Stop(f.repo)
	})
}

// Two starts that find a copy that died take turns under the checkout's lock,
// so one runs a copy in its place and the other reports that copy. The test
// drives the interleaving the lock rules out: each start's check of the dead
// leader waits until the other start has checked it too, and the second waits
// until the first's copy runs. A start that went on without the lock would
// remove the running copy's record and run a second copy, which the
// checkout's stop would leave running.
func TestServeTwoStartsThatFindACopyThatDiedRunOneCopyInItsPlace(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		rec := f.claim(t, f.repo, map[string]string{"command": "serve", "port": "1"})
		dead, err := f.me.Start(host.Spec{Argv: []string{"stubborn", rec.dir}, Session: true})
		if err != nil {
			t.Fatal(err)
		}
		if !rec.awaitLeader(15 * time.Second) {
			t.Fatal("the leader of the copy that dies did not record its pid")
		}
		_ = f.me.Signal(dead.Pid(), syscall.SIGKILL)
		if c := f.copies.Check(f.repo); c.State != CopyDied {
			t.Fatalf("check = %s, want died", c.State)
		}

		var at flags
		replaced := func() bool {
			pid := f.leader(f.repo)
			return pid > 0 && pid != dead.Pid() && f.running(pid)
		}
		first := gated{Host: f.me, hold: func(pid int, sig syscall.Signal) {
			if pid == dead.Pid() && sig == 0 {
				at.mark("first checked")
				waitFor(10*time.Second, at.reached("second checked"))
			}
		}}
		second := gated{Host: f.me, hold: func(pid int, sig syscall.Signal) {
			if pid == dead.Pid() && sig == 0 {
				at.mark("second checked")
				waitFor(10*time.Second, replaced)
			}
		}}
		reps := make(chan Report, 2)
		for _, h := range []host.Host{first, second} {
			copies := f.copiesOn(h)
			go func() { reps <- copies.Serve(f.repo, f.opts("serve")) }()
		}
		a, b := <-reps, <-reps
		mustRun(t, a)
		mustRun(t, b)
		if leaders, served := len(f.starts("leader")), f.list(&f.served); a.Port != b.Port || leaders != 1 || len(served) != 1 {
			t.Errorf("two starts over a copy that died ran %d leaders and served %q, and report ports %d and %d: want one copy both report",
				leaders, served, a.Port, b.Port)
		}
		if a.Started == b.Started {
			t.Errorf("started = %v and %v, want exactly one start to say it ran the copy", a.Started, b.Started)
		}
		if s := f.copies.Stop(f.repo); s.State != CopyStopped {
			t.Fatalf("stop = %s (%s), want stopped", s.State, s.Detail)
		}
		for _, s := range f.starts("serve") {
			if f.running(s.Pid) {
				t.Errorf("the serve command %d still runs after the checkout's stop", s.Pid)
			}
		}
		if entries, _ := os.ReadDir(f.copies.root); len(entries) != 0 {
			t.Errorf("the stop left %v in the copies' directory", entries)
		}
	})
}

// Two starts that ask for an address for a running copy with none take turns
// under the checkout's lock. The first publishes the copy with its own publish
// command and address pattern and reports the address they give, and the
// second, which asks for others, finds that publish command running and fails
// other-publisher. The test drives the interleaving the lock rules out: each
// start decides that no publish command runs before either asks the leader to
// run one, and the first's request waits until the second's start has ended.
// Starts that went on without the lock would each run a publish command, and
// the first would report the address the second asked for.
func TestServeTwoStartsThatPublishARunningCopyRunOnePublishCommand(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		r := f.copies.Serve(f.repo, f.opts("serve"))
		mustRun(t, r)
		leader := f.leader(f.repo)

		var at flags
		first := gated{Host: f.me, hold: func(pid int, sig syscall.Signal) {
			if pid == leader && sig == syscall.SIGUSR1 {
				at.mark("first asked")
				waitFor(30*time.Second, at.reached("second ended"))
			}
		}}
		second := gated{Host: f.me, hold: func(pid int, sig syscall.Signal) {
			if pid == leader && sig == syscall.SIGUSR1 {
				waitFor(30*time.Second, at.reached("first asked"))
			}
		}}
		patterns := map[string]string{"first": "https://first.example:$PORT/", "second": "https://second.example:$PORT/"}
		firstCopies, secondCopies := f.copiesOn(first), f.copiesOn(second)
		firstRep, secondRep := make(chan Report, 1), make(chan Report, 1)
		go func() { firstRep <- firstCopies.Serve(f.repo, f.publishing("ok", patterns["first"])) }()
		go func() {
			rep := secondCopies.Serve(f.repo, f.publishing("other", patterns["second"]))
			at.mark("second ended")
			secondRep <- rep
		}()
		reps := map[string]Report{"first": <-firstRep, "second": <-secondRep}

		won := ""
		for name, rep := range reps {
			if rep.State == CopyRunning {
				won += name
			}
		}
		lost := map[string]string{"first": "second", "second": "first"}[won]
		if lost == "" {
			var got []string
			for _, name := range []string{"first", "second"} {
				rep := reps[name]
				got = append(got, fmt.Sprintf("%s %s %s at %q", name, rep.State, rep.Reason, address(rep)))
			}
			t.Fatalf("starts report %q and publish commands run %q: want one start to publish the copy and the other to fail other-publisher", got, f.list(&f.published))
		}
		want := addressFor(patterns[won], r.Port)
		if address(reps[won]) != want {
			t.Errorf("the %s start, which published the copy, reports the address %q, want the one its pattern gives, %q", won, address(reps[won]), want)
		}
		if l := reps[lost]; l.State != CopyFailed || l.Reason != "other-publisher" || !strings.Contains(l.Detail, want) {
			t.Errorf("the %s start = %s %s (%s), want failed other-publisher naming %s", lost, l.State, l.Reason, l.Detail, want)
		}
		if got := f.list(&f.published); len(got) != 1 {
			t.Errorf("publish commands run: %q, want one", got)
		}
		rec := f.rec(f.repo)
		if got := rec.read("address"); got != want || !rec.publisherAlive() {
			t.Errorf("the record holds the address %q (publisher running %v), want %q and its publish command running", got, rec.publisherAlive(), want)
		}
		if c := f.copies.Check(f.repo); c.State != CopyRunning || address(c) != want || f.leader(f.repo) != leader {
			t.Errorf("check = %s at %q under leader %d, want running at %q under the copy's leader, %d", c.State, address(c), f.leader(f.repo), want, leader)
		}
		f.copies.Stop(f.repo)
	})
}

// A stop holds the checkout's lock too, so one that comes while a start is
// under way waits for that start to report, and then ends the copy it left.
func TestServeAStopWaitsForAStartUnderWayAndEndsTheCopyItLeft(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		var at flags
		starting := gated{Host: f.me, hold: func(pid int, sig syscall.Signal) {
			if sig == 0 && pid > 0 && pid == f.leader(f.repo) && !at.reached("start under way")() {
				at.mark("start under way")
				waitFor(10*time.Second, at.reached("stop ended"))
			}
		}}
		startCopies := f.copiesOn(starting)
		started := make(chan Report, 1)
		go func() {
			rep := startCopies.Serve(f.repo, f.opts("serve"))
			at.mark("start ended")
			started <- rep
		}()
		if !waitFor(10*time.Second, at.reached("start under way")) {
			t.Error("the start did not reach its wait for the copy")
		}
		stopped := make(chan Report, 1)
		go func() {
			rep := f.copies.Stop(f.repo)
			at.mark("stop ended")
			stopped <- rep
		}()
		r, s := <-started, <-stopped
		mustRun(t, r)
		if !r.Started {
			t.Error("the start that ran the copy does not say so")
		}
		if s.State != CopyStopped {
			t.Errorf("stop = %s (%s), want stopped: the stop ends the copy the start left", s.State, s.Detail)
		}
		for _, sv := range f.starts("serve") {
			if f.running(sv.Pid) {
				t.Errorf("the serve command %d still runs after the stop", sv.Pid)
			}
		}
	})
}

// A check waits for no start, and a start's record has no leader while the
// start runs one: at a copy's first launch, and when it moves the copy it ran
// off a port another mapping holds. A check then reads the copy as
// not-answering, with the start under way, where reading the record as it
// stands would report a copy that died. Once the start reports, the check
// reads the copy it ran.
func TestServeACheckDuringAStartReadsACopyWithNoLeaderAsNotAnswering(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		var at flags
		var mu sync.Mutex
		launches := 0
		starting := gated{Host: f.me, starting: func(s host.Spec) {
			if len(s.Argv) != 5 || s.Argv[3] != "--lead" {
				return
			}
			mu.Lock()
			launches++
			name := fmt.Sprintf("launch %d", launches)
			mu.Unlock()
			at.mark(name)
			waitFor(10*time.Second, at.reached(name+" checked"))
		}}
		started := make(chan Report, 1)
		go func() {
			started <- f.copiesOn(starting).Serve(f.repo, f.publishing("taken-first", "https://host.example:$PORT/"))
		}()
		for _, name := range []string{"launch 1", "launch 2"} {
			if !waitFor(10*time.Second, at.reached(name)) {
				t.Errorf("the start did not reach its %s", name)
				break
			}
			if c := f.copies.Check(f.repo); c.State != CopyNotAnswering || !strings.Contains(c.Detail, "under way") {
				t.Errorf("a check at the start's %s = %s (%s), want not-answering, with the start under way", name, c.State, c.Detail)
			}
			at.mark(name + " checked")
		}
		r := <-started
		mustRun(t, r)
		if c := f.copies.Check(f.repo); c.State != CopyRunning || c.Port != r.Port {
			t.Errorf("a check after the start = %s on port %d, want running on port %d", c.State, c.Port, r.Port)
		}
		f.copies.Stop(f.repo)
	})
}

// A check takes the checkout's lock shared, so checks never read one another
// as a start or a stop under way: with another check's hold on the lock, a
// check of a copy that died reads died. With a start's or a stop's hold, which
// is exclusive, it reads not-answering, and a stop waits out every check that
// holds the lock.
func TestServeChecksShareTheLockAndAStopWaitsThemOut(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		port, _ := f.me.FreePort()
		f.claim(t, f.repo, map[string]string{"command": "serve", "port": strconv.Itoa(port),
			"pid": strconv.Itoa(f.me.Pid()), "start_id": "the start of a leader that ended"})
		// A start's lock leaves its file once the checkout has a record.
		unlock, err := f.copies.lock(f.repo)
		if err != nil {
			t.Fatal(err)
		}
		unlock()

		other, busy, err := f.copies.tryShared(f.repo)
		if err != nil || busy {
			t.Fatalf("a check's try: busy %v, %v; want the lock, which no start or stop holds", busy, err)
		}
		if c := f.copies.Check(f.repo); c.State != CopyDied {
			t.Errorf("a check beside another check's hold = %s (%s), want died", c.State, c.Detail)
		}
		stopped := make(chan Report, 1)
		go func() { stopped <- f.copies.Stop(f.repo) }()
		time.Sleep(5 * time.Second)
		select {
		case s := <-stopped:
			t.Errorf("a stop ended (%s) while a check held the lock", s.State)
		default:
		}
		other()
		if s := <-stopped; s.State != CopyNone {
			t.Errorf("stop = %s (%s), want none: the copy had died", s.State, s.Detail)
		}

		f.claim(t, f.repo, map[string]string{"command": "serve", "port": strconv.Itoa(port),
			"pid": strconv.Itoa(f.me.Pid()), "start_id": "the start of a leader that ended"})
		held, err := f.copies.lock(f.repo)
		if err != nil {
			t.Fatal(err)
		}
		if c := f.copies.Check(f.repo); c.State != CopyNotAnswering || !strings.Contains(c.Detail, "under way") {
			t.Errorf("a check beside a start's or a stop's hold = %s (%s), want not-answering, with the call under way", c.State, c.Detail)
		}
		held()
		if c := f.copies.Check(f.repo); c.State != CopyDied {
			t.Errorf("a check once the hold is released = %s, want died", c.State)
		}
	})
}

// The release removes the lock's file once the checkout has no record, and a
// call that was waiting on that file takes the lock again on the file at the
// lock's path, whether a later call made it or it makes it, so no two calls
// hold the checkout's lock at once.
func TestServeTheLockHoldsAcrossTheRemovalOfItsFile(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		if err := os.MkdirAll(f.copies.root, 0o755); err != nil {
			t.Fatal(err)
		}
		path := f.copies.Dir(f.repo) + ".lock"
		release, err := f.copies.lock(f.repo)
		if err != nil {
			t.Fatal(err)
		}
		var at flags
		go func() {
			next, err := f.copies.lock(f.repo)
			if err != nil {
				t.Error(err)
				return
			}
			at.mark("second holds")
			waitFor(time.Minute, at.reached("third tried"))
			time.Sleep(5 * time.Second)
			at.mark("second releases")
			next()
		}()
		time.Sleep(time.Second)
		// The release removes the file the second call waits on, and a call
		// that comes before the second tries it again makes the file anew.
		release()
		later, err := f.copies.lock(f.repo)
		if err != nil {
			t.Fatal(err)
		}
		time.Sleep(5 * time.Second)
		if at.reached("second holds")() {
			t.Error("the call that waited on the removed file took the lock while a later call held it")
		}
		later()
		if !waitFor(10*time.Second, at.reached("second holds")) {
			t.Fatal("the call waiting on the lock did not take it once it was released")
		}
		if _, err := os.Stat(path); err != nil {
			t.Errorf("the lock's file %s is gone while a call holds the lock: %v", path, err)
		}
		at.mark("third tried")
		third, err := f.copies.lock(f.repo)
		if err != nil {
			t.Fatal(err)
		}
		if !at.reached("second releases")() {
			t.Error("a third call took the checkout's lock while the second held it")
		}
		third()
		if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
			t.Errorf("the lock's file outlives its last holder with no record: %v", err)
		}
	})
}

// A start or a stop that cannot take the checkout's lock acts on nothing: the
// start fails, and the stop reports the copy still running, and why.
func TestServeACallThatCannotTakeTheLockLeavesTheCopyAsItIs(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		r := f.copies.Serve(f.repo, f.opts("serve"))
		mustRun(t, r)
		leader := f.leader(f.repo)
		path := f.copies.Dir(f.repo) + ".lock"
		if err := os.Remove(path); err != nil {
			t.Fatal(err)
		}
		if err := os.Mkdir(path, 0o755); err != nil {
			t.Fatal(err)
		}
		s := f.copies.Stop(f.repo)
		if s.State != CopyRunning || !strings.Contains(s.Detail, "could not be taken") {
			t.Errorf("a stop that cannot take the lock = %s (%s), want running, and why", s.State, s.Detail)
		}
		again := f.copies.Serve(f.repo, f.opts("serve"))
		if again.State != CopyFailed || again.Reason != "no-state" || !strings.Contains(again.Detail, "could not be taken") {
			t.Errorf("a start that cannot take the lock = %s %s (%s), want failed no-state, and why", again.State, again.Reason, again.Detail)
		}
		if f.leader(f.repo) != leader || !f.running(leader) || !f.me.Answers(r.Port) {
			t.Error("a call that could not take the lock changed the copy")
		}
		if err := os.Remove(path); err != nil {
			t.Fatal(err)
		}
		if s := f.copies.Stop(f.repo); s.State != CopyStopped {
			t.Errorf("stop = %s (%s), want stopped once the lock can be taken", s.State, s.Detail)
		}
	})
}

// A member that outlives SIGTERM gets SIGKILL once the leader's grace is up,
// and the KILL ends the leader with it, so the leader never ends while a
// member runs.
func TestServeAPublishCommandThatIgnoresTermEndsWithTheLeaderAfterTheGrace(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		mustRun(t, f.copies.Serve(f.repo, f.publishing("ignores-term", "https://host.example:$PORT/")))
		leader, pub := f.leader(f.repo), f.publisherOf(f.repo)
		start := time.Now()
		_ = f.me.Signal(leader, syscall.SIGTERM)
		if !waitFor(StopGrace+10*time.Second, func() bool { return !f.running(leader) }) {
			t.Fatal("the leader did not end")
		}
		l, p := f.endOf(t, leader), f.endOf(t, pub)
		if p.At.After(l.At) || p.Status != 128+int(syscall.SIGKILL) {
			t.Errorf("the publish command ended %+v, the leader %+v: want it killed, no later than the leader", p, l)
		}
		if l.At.Sub(start) != StopGrace {
			t.Errorf("the leader ended %s after SIGTERM, want at its grace of %s", l.At.Sub(start), StopGrace)
		}
		if !f.me.GroupGone(leader) {
			t.Errorf("members of the copy's group are left: %v", f.me.Members(leader))
		}
		if s := f.copies.Stop(f.repo); s.State != CopyNone {
			t.Errorf("stop = %s, want none", s.State)
		}
	})
}

// A stop whose SIGTERM the copy's group outlives, as one whose leader does not
// end it would, sends the group SIGKILL once the grace is up.
func TestServeAStopKillsAGroupThatOutlivesSigterm(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		rec := f.claim(t, f.repo, map[string]string{"command": "serve", "port": "1"})
		if _, err := f.me.Start(host.Spec{Argv: []string{"stubborn", rec.dir}, Session: true}); err != nil {
			t.Fatal(err)
		}
		if !rec.awaitLeader(15 * time.Second) {
			t.Fatal("the leader did not record its pid")
		}
		leader := f.leader(f.repo)
		start := time.Now()
		if s := f.copies.Stop(f.repo); s.State != CopyStopped {
			t.Fatalf("stop = %s (%s), want stopped", s.State, s.Detail)
		}
		if e := f.endOf(t, leader); e.Status != 128+int(syscall.SIGKILL) || e.At.Sub(start) != StopGrace {
			t.Errorf("the leader ended %+v, %s after the stop: want SIGKILL once the grace of %s was up", e, e.At.Sub(start), StopGrace)
		}
	})
}

func TestServeTriesAgainAPublishRefusedWhileTheConfigChanges(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		r := f.copies.Serve(f.repo, f.publishing("again-once", "https://host.example:$PORT/"))
		mustRun(t, r)
		if want := "https://host.example:" + strconv.Itoa(r.Port) + "/"; address(r) != want {
			t.Errorf("address = %q, want %q", address(r), want)
		}
		if got := f.list(&f.published); len(got) != 2 || got[0] != got[1] {
			t.Errorf("published %q, want the same port tried twice", got)
		}
		f.copies.Stop(f.repo)
	})
}

func TestServeMovesACopyWhosePortIsRefusedAsTaken(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		r := f.copies.Serve(f.repo, f.publishing("taken-first", "https://host.example:$PORT/"))
		mustRun(t, r)
		first := f.firstPort
		if first == 0 || r.Port == first {
			t.Fatalf("the copy runs on port %d, refused port %d", r.Port, first)
		}
		if want := "https://host.example:" + strconv.Itoa(r.Port) + "/"; address(r) != want {
			t.Errorf("address = %q, want %q", address(r), want)
		}
		if n := len(f.list(&f.served)); n != 2 {
			t.Errorf("the serve command ran %d times, want twice", n)
		}
		if f.me.Answers(first) || !f.me.Answers(r.Port) {
			t.Errorf("the refused port %d answers, or the new port %d does not", first, r.Port)
		}
		if !r.Started {
			t.Error("the start that ran the copy and moved it does not say it started it")
		}
		f.copies.Stop(f.repo)
	})
}

// A start that cannot stop a copy, because the copy's process group outlives
// SIGTERM and SIGKILL, fails not-stopped and keeps the copy's record, so a
// check still reports the copy and a stop ends it once its group can be ended.
// No second leader runs over that record. A start stops a copy when it moves
// one it ran off a port another mapping holds, and when one does not answer
// within its wait.
func TestServeAStartThatCannotStopACopyKeepsItsRecord(t *testing.T) {
	for _, tc := range []struct {
		name string
		opts func(f *serveFixture) ServeOpts
	}{
		{"moved off a taken port", func(f *serveFixture) ServeOpts {
			return f.publishing("taken-first", "https://host.example:$PORT/")
		}},
		{"not answering", func(f *serveFixture) ServeOpts { return f.opts("hang") }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			serveTest(t, func(t *testing.T, f *serveFixture) {
				first := func() int {
					if s := f.starts("leader"); len(s) > 0 {
						return s[0].Pid
					}
					return 0
				}
				r := f.copiesOn(unkillable{Host: f.me, pgid: first}).Serve(f.repo, tc.opts(f))
				leader := first()
				if r.State != CopyFailed || r.Reason != "not-stopped" || !strings.Contains(r.Detail, "--stop") {
					t.Errorf("the start = %s %s (%s), want failed not-stopped, and how to end the copy", r.State, r.Reason, r.Detail)
				}
				if n := len(f.starts("leader")); n != 1 {
					t.Errorf("leaders started: %d, want only the one whose group survived", n)
				}
				if f.leader(f.repo) != leader || !f.running(leader) {
					t.Errorf("the record names leader %d (running %v), want the copy's, %d", f.leader(f.repo), f.running(leader), leader)
				}
				if c := f.copies.Check(f.repo); c.State == CopyNone || c.State == CopyDied {
					t.Errorf("check = %s, want the copy reported while its group runs", c.State)
				}
				if s := f.copies.Stop(f.repo); s.State != CopyStopped || !f.me.GroupGone(leader) {
					t.Errorf("stop = %s (%s), want stopped, and the copy's group gone", s.State, s.Detail)
				}
			})
		})
	}
}

// A copy a start found may serve another caller on its port, such as a
// capture's engine, so a start that asks for its address, refused because
// another mapping holds that port, fails and leaves the copy where it runs.
// A check then says why the copy has no address.
func TestServeLeavesACopyItFoundOnItsPortWhenAnotherMappingHoldsIt(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		r := f.copies.Serve(f.repo, f.opts("serve"))
		mustRun(t, r)
		leader := f.leader(f.repo)

		busy := f.copies.Serve(f.repo, f.publishing("taken-first", "https://host.example:$PORT/"))
		if busy.State != CopyFailed || busy.Reason != "address-taken" || busy.Started ||
			!strings.Contains(busy.Detail, strconv.Itoa(r.Port)) || !strings.Contains(busy.Detail, "--stop") {
			t.Errorf("the start = %s %s, started %v (%s), want failed address-taken, naming the port and how to stop the copy",
				busy.State, busy.Reason, busy.Started, busy.Detail)
		}
		if got := f.list(&f.published); !slices.Equal(got, []string{"taken-first " + strconv.Itoa(r.Port)}) {
			t.Errorf("published %q, want one run on the copy's port, %d", got, r.Port)
		}
		if f.leader(f.repo) != leader || !f.running(leader) || !f.me.Answers(r.Port) ||
			len(f.starts("leader")) != 1 || len(f.list(&f.served)) != 1 {
			t.Errorf("the start moved or ended the copy it found: leader %d (was %d, running %v), port %d answers %v, leaders started %d, serve commands run %d",
				f.leader(f.repo), leader, f.running(leader), r.Port, f.me.Answers(r.Port), len(f.starts("leader")), len(f.list(&f.served)))
		}
		c := f.copies.Check(f.repo)
		if c.State != CopyRunning || c.Port != r.Port || address(c) != "" || !strings.Contains(c.Detail, "another mapping") {
			t.Errorf("check = %s on port %d at %q (%s), want running on port %d with no address, and why", c.State, c.Port, address(c), c.Detail, r.Port)
		}
		f.copies.Stop(f.repo)
	})
}

func TestServeAPublishRefusedForAnotherReasonLeavesTheCopyRunning(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		r := f.copies.Serve(f.repo, f.publishing("fails", "https://host.example:$PORT/"))
		mustRun(t, r)
		if address(r) != "" || !strings.Contains(r.Detail, "access denied") {
			t.Errorf("address %q, detail %q: want no address, and what the publish command said", address(r), r.Detail)
		}
		if n := len(f.list(&f.published)); n != 1 {
			t.Errorf("the publish command ran %d times, want once", n)
		}
		f.copies.Stop(f.repo)
	})
}

func TestServeWithNoPublisherGivesNoAddress(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		o := f.opts("serve")
		o.Publish = true
		r := f.copies.Serve(f.repo, o)
		mustRun(t, r)
		if address(r) != "" || !strings.Contains(r.Detail, "no address can be given") || len(f.starts("publish")) != 0 {
			t.Errorf("address %q, detail %q, publish starts %d: want no address, why, and no publish", address(r), r.Detail, len(f.starts("publish")))
		}
		f.copies.Stop(f.repo)
	})
}

func TestServeRefusesWhatCannotRunAndLeavesNoRecord(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		o := f.opts("serve")
		o.ScriptsDir = ""
		if r := f.copies.Serve(f.repo, o); r.State != CopyFailed || r.Reason != "no-sandbox" {
			t.Errorf("no scripts directory: %s %s, want failed no-sandbox", r.State, r.Reason)
		}
		o.ScriptsDir = f.dir
		if r := f.copies.Serve(f.repo, o); r.State != CopyFailed || r.Reason != "no-sandbox" {
			t.Errorf("a scripts directory with no %s: %s %s, want failed no-sandbox", SandboxLib, r.State, r.Reason)
		}
		f.m.FreePortErr = errors.New("no port")
		r := f.copies.Serve(f.repo, f.opts("serve"))
		f.m.FreePortErr = nil
		if r.State != CopyFailed || r.Reason != "no-free-port" {
			t.Errorf("no free port: %s %s, want failed no-free-port", r.State, r.Reason)
		}
		if entries, _ := os.ReadDir(f.copies.root); len(entries) != 0 {
			t.Errorf("a refusal left a record: %v", entries)
		}
		if n := len(f.m.Starts()); n != 0 {
			t.Errorf("a refusal started %d processes", n)
		}
	})
}

func TestServeStopsACopyThatNeverComesUp(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		r := f.copies.Serve(f.repo, f.opts("fail"))
		if r.State != CopyFailed || r.Reason != "serve-exited" || r.ExitCode == nil || *r.ExitCode != 3 || !strings.Contains(r.Tail, "cannot serve") {
			t.Errorf("a serve command that ends at once: %s %s exit %v tail %q", r.State, r.Reason, r.ExitCode, r.Tail)
		}
		r = f.copies.Serve(f.repo, f.opts("missing"))
		if r.State != CopyFailed || r.Reason != "serve-exited" || r.ExitCode == nil || *r.ExitCode != 127 || !strings.Contains(r.Tail, "the serve command did not start") {
			t.Errorf("a serve command that cannot start: %s %s exit %v tail %q", r.State, r.Reason, r.ExitCode, r.Tail)
		}
		o := f.opts("hang")
		o.Wait = 2 * time.Second
		start := time.Now()
		r = f.copies.Serve(f.repo, o)
		if r.State != CopyFailed || r.Reason != "not-answering" {
			t.Errorf("a copy that never answers: %s %s, want failed not-answering", r.State, r.Reason)
		}
		if waited := time.Since(start); waited < o.Wait {
			t.Errorf("the start gave up after %s, before its wait of %s", waited, o.Wait)
		}
		for _, s := range f.starts("serve") {
			if f.running(s.Pid) {
				t.Errorf("the serve command %d of a copy that failed was not stopped", s.Pid)
			}
		}
		if entries, _ := os.ReadDir(f.copies.root); len(entries) != 0 {
			t.Errorf("a copy that failed left a record: %v", entries)
		}
	})
}

func TestServeAStartThatFindsACopyNotAnsweringStopsItAfterItsOwnWait(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		// A start cut off after its leader ran: the record is claimed and the
		// leader started, and nothing waits for the copy to answer.
		port, _ := f.me.FreePort()
		rec := f.claim(t, f.repo, map[string]string{"command": "hang", "port": strconv.Itoa(port)})
		if reason, detail := rec.startLeader(); reason != "" {
			t.Fatalf("%s: %s", reason, detail)
		}
		if !rec.awaitLeader(15 * time.Second) {
			t.Fatal("the leader did not start")
		}
		leader := f.leader(f.repo)
		if c := f.copies.Check(f.repo); c.State != CopyNotAnswering || !strings.Contains(c.Detail, "nothing answers") {
			t.Errorf("check = %s (%s), want not-answering, and why", c.State, c.Detail)
		}
		o := f.opts("hang")
		o.Wait = 2 * time.Second
		r := f.copies.Serve(f.repo, o)
		if r.State != CopyFailed || r.Reason != "not-answering" {
			t.Errorf("a start that finds it: %s %s, want failed not-answering", r.State, r.Reason)
		}
		if !f.me.GroupGone(leader) {
			t.Errorf("the copy that did not answer was not stopped: %v", f.me.Members(leader))
		}
		if _, err := os.Stat(rec.dir); err == nil {
			t.Error("its record is left")
		}
	})
}

// A copy runs only while its port answers and every process listening there,
// on an address loopback reaches, is a member of its group.
func TestServeACopyHoldsItsPortOnlyWhileEachListenerIsItsOwn(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		r := f.copies.Serve(f.repo, f.opts("serve"))
		mustRun(t, r)
		other, err := f.me.Start(host.Spec{Argv: []string{"listen", strconv.Itoa(r.Port)}})
		if err != nil {
			t.Fatal(err)
		}
		synctest.Wait()
		c := f.copies.Check(f.repo)
		why := fmt.Sprintf("process %d, which listens on port %d, is not one of the copy's", other.Pid(), r.Port)
		if c.State != CopyNotAnswering || !strings.Contains(c.Detail, why) {
			t.Errorf("check with another process on the copy's port = %s (%s), want not-answering: %s", c.State, c.Detail, why)
		}
		_ = f.me.Signal(other.Pid(), syscall.SIGTERM)
		if c := f.copies.Check(f.repo); c.State != CopyRunning {
			t.Errorf("check once the other process ended = %s (%s), want running", c.State, c.Detail)
		}

		rec := f.rec(f.repo)
		leader := f.leader(f.repo)
		if ok, why := rec.owned(r.Port, leader); !ok {
			t.Errorf("a port the copy's serve command listens on is not owned: %s", why)
		}
		if ok, _ := rec.owned(r.Port, f.me.Pid()); ok {
			t.Error("a listener outside the group counts as the group's")
		}
		free, _ := f.me.FreePort()
		if ok, why := rec.owned(free, leader); ok || !strings.Contains(why, "nothing listens") {
			t.Errorf("a port nothing listens on: owned %v, %q", ok, why)
		}
		f.copies.Stop(f.repo)
	})
}

// A record whose leader's pid now names another process, one that started
// later under a pid the kernel reused, is a copy that died: no call signals
// that process, and a start runs a copy in the record's place.
func TestServeARecordWhosePidWasReusedIsACopyThatDied(t *testing.T) {
	serveTest(t, func(t *testing.T, f *serveFixture) {
		port, _ := f.me.FreePort()
		f.claim(t, f.repo, map[string]string{"command": "serve", "port": strconv.Itoa(port),
			"pid": strconv.Itoa(f.me.Pid()), "start_id": "the start of a leader that ended"})
		if c := f.copies.Check(f.repo); c.State != CopyDied {
			t.Errorf("check = %s, want died", c.State)
		}
		r := f.copies.Serve(f.repo, f.opts("serve"))
		mustRun(t, r)
		if !r.Started || f.leader(f.repo) == f.me.Pid() {
			t.Errorf("a start over the record: started %v, leader %d, want a copy of its own", r.Started, f.leader(f.repo))
		}
		f.copies.Stop(f.repo)
		f.claim(t, f.repo, map[string]string{"command": "serve", "port": strconv.Itoa(port),
			"pid": strconv.Itoa(f.me.Pid()), "start_id": "the start of a leader that ended"})
		if s := f.copies.Stop(f.repo); s.State != CopyNone {
			t.Errorf("stop = %s, want none", s.State)
		}
		if !f.running(f.me.Pid()) {
			t.Error("a call signalled the process that took the dead leader's pid")
		}
	})
}
