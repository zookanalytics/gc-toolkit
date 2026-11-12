package rig

import (
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// A copy's leader is this test binary, run again with GCTK_RIG_TEST_LEAD
// naming the record, as gctk runs itself with --lead.
func TestMain(m *testing.M) {
	if dir := os.Getenv("GCTK_RIG_TEST_LEAD"); dir != "" {
		os.Exit(Lead(dir))
	}
	os.Exit(m.Run())
}

// stubLib stands in for demo-engine-lib.sh. Its demo_engine_sandboxed logs
// its port, its directory and the command, then runs the command in the
// directory, as the real one does inside the sandbox.
const stubLib = `demo_engine_sandboxed() {
  printf '%s|%s|%s\n' "$1" "$2" "$*" >> "$SANDBOXED"
  local dir=$2
  shift 2
  cd "$dir" && exec "$@"
}
`

// serveScript is a serve command: an HTTP server on loopback at $PORT that
// records its working directory and port.
const serveScript = `import http.server, os
port = int(os.environ["PORT"])
with open(os.environ["SERVED"], "a") as f:
    f.write("%s %d\n" % (os.getcwd(), port))
http.server.HTTPServer(("127.0.0.1", port), http.server.SimpleHTTPRequestHandler).serve_forever()
`

// publishScript is a publish command, by mode: ok stays running; again-once
// refuses its first run as Tailscale does while another client changes the
// serve config; taken-first refuses the first port it is given as Tailscale
// refuses a port another mapping holds; fails refuses for another reason;
// ignores-term stays running through SIGTERM. Each run logs its mode and $PORT.
const publishScript = `#!/usr/bin/env bash
printf '%s %s\n' "$1" "$PORT" >> "$PUBLISHED"
case "$1" in
  ignores-term) trap '' TERM ;;
  again-once)
    if [ ! -e "$PUBLISHED.again" ]; then
      : > "$PUBLISHED.again"
      echo "Another client is changing the serve config; please try again." >&2
      exit 1
    fi ;;
  taken-first)
    [ -e "$PUBLISHED.first" ] || printf '%s\n' "$PORT" > "$PUBLISHED.first"
    if [ "$(cat "$PUBLISHED.first")" = "$PORT" ]; then
      echo "error: listener already exists for port $PORT" >&2
      exit 1
    fi ;;
  fails) echo "access denied" >&2; exit 1 ;;
esac
echo "Available within your tailnet: https://host.example:$PORT/"
while :; do sleep 0.2 & wait $!; done
`

type serveFixture struct {
	t       *testing.T
	dir     string
	repo    string
	repo2   string
	scripts string
	copies  *Copies
}

func newServeFixture(t *testing.T) *serveFixture {
	t.Helper()
	for _, tool := range []string{"python3", "lsof", "git"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skipf("%s is not on PATH", tool)
		}
	}
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	f := &serveFixture{t: t, dir: dir, repo: filepath.Join(dir, "a"), repo2: filepath.Join(dir, "b"), scripts: filepath.Join(dir, "scripts")}
	gitConfig := filepath.Join(dir, "gitconfig")
	f.write(gitConfig, "")
	for k, v := range map[string]string{
		"GIT_CONFIG_GLOBAL": gitConfig, "GIT_CONFIG_NOSYSTEM": "1",
		"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
		"GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com",
		"SERVED": filepath.Join(dir, "served"), "PUBLISHED": filepath.Join(dir, "published"),
		"SANDBOXED":     filepath.Join(dir, "sandboxed"),
		"GC_SESSION_ID": "serve-test-session", "GC_CITY_PATH": filepath.Join(dir, "no-city"), "GC_RUNTIME_EPOCH": "7",
	} {
		t.Setenv(k, v)
	}
	for _, r := range []string{f.repo, f.repo2} {
		f.git(r, "init", "-q", "-b", "main", r)
		f.write(filepath.Join(r, "serve.py"), serveScript)
		f.git(r, "-C", r, "add", "-A")
		f.git(r, "-C", r, "commit", "-q", "-m", "one")
	}
	f.write(filepath.Join(f.scripts, SandboxLib), stubLib)
	f.write(filepath.Join(dir, "publish.sh"), publishScript)
	if err := os.Chmod(filepath.Join(dir, "publish.sh"), 0o755); err != nil {
		t.Fatal(err)
	}
	f.copies = NewCopies(filepath.Join(dir, "common"))

	oldLeader, oldSettle, oldGrace := leaderCommand, SettleTime, StopGrace
	leaderCommand = func(rec string) (*exec.Cmd, error) {
		cmd := exec.Command(os.Args[0])
		cmd.Env = append(os.Environ(), "GCTK_RIG_TEST_LEAD="+rec)
		return cmd, nil
	}
	SettleTime = time.Second
	StopGrace = 3 * time.Second
	t.Cleanup(func() {
		// A copy a failed assertion left running is ended with its group.
		matches, _ := filepath.Glob(filepath.Join(dir, "common", serveDirName, "*", "pid"))
		for _, m := range matches {
			if pid, err := strconv.Atoi(strings.TrimSpace(readFile(m))); err == nil && pid > 1 {
				_ = syscall.Kill(-pid, syscall.SIGKILL)
			}
		}
		leaderCommand, SettleTime, StopGrace = oldLeader, oldSettle, oldGrace
	})
	return f
}

func (f *serveFixture) write(path, body string) {
	f.t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		f.t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		f.t.Fatal(err)
	}
}

func (f *serveFixture) git(_ string, args ...string) {
	f.t.Helper()
	if out, err := exec.Command("git", args...).CombinedOutput(); err != nil {
		f.t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func readFile(path string) string {
	b, _ := os.ReadFile(path)
	return string(b)
}

func (f *serveFixture) opts(command string) ServeOpts {
	return ServeOpts{Command: command, Wait: 20 * time.Second, ScriptsDir: f.scripts}
}

func (f *serveFixture) published(mode, pattern string) ServeOpts {
	o := f.opts("exec python3 serve.py")
	o.Publish, o.PublishCommand, o.AddressPattern = true, filepath.Join(f.dir, "publish.sh")+" "+mode, pattern
	return o
}

func (f *serveFixture) rec(checkout string) copyRec { return copyRec(f.copies.Dir(checkout)) }

func (f *serveFixture) leader(checkout string) int {
	pid, _ := f.rec(checkout).num("pid")
	return pid
}

func (f *serveFixture) lines(name string) []string {
	s := strings.TrimSpace(readFile(filepath.Join(f.dir, name)))
	if s == "" {
		return nil
	}
	return strings.Split(s, "\n")
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

// waitFor polls cond for up to bound.
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

// environ is a process's environment as the orphan sweep reads it: /proc on
// Linux, ps on macOS.
func environ(pid int) string {
	if b, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/environ"); err == nil {
		return strings.ReplaceAll(string(b), "\x00", "\n")
	}
	out, _ := exec.Command("ps", "eww", "-o", "command=", "-p", strconv.Itoa(pid)).Output()
	return strings.ReplaceAll(string(out), " ", "\n")
}

func TestServeRunsTheCommandInTheSandboxFromTheCheckoutOnAPortOfItsOwn(t *testing.T) {
	f := newServeFixture(t)
	command := "exec python3 serve.py"
	r := f.copies.Serve(f.repo, f.opts(command))
	mustRun(t, r)
	if r.Port <= 0 || !answers(r.Port) {
		t.Fatalf("the copy does not answer on the port it reports, %d", r.Port)
	}
	if address(r) != "" || !strings.Contains(r.Detail, "started without --publish-command") {
		t.Errorf("address %q, detail %q: want no address, and why", address(r), r.Detail)
	}
	if got, want := f.lines("served"), []string{f.repo + " " + strconv.Itoa(r.Port)}; strings.Join(got, ";") != strings.Join(want, ";") {
		t.Errorf("served %q, want %q: the command runs from the checkout with the port as PORT", got, want)
	}
	if got, want := f.lines("sandboxed"), strconv.Itoa(r.Port)+"|"+f.repo+"|"; len(got) != 1 || !strings.HasPrefix(got[0], want) || !strings.HasSuffix(got[0], "bash -c "+command) {
		t.Errorf("the sandbox ran %q, want one run of %q ... bash -c %q", got, want, command)
	}
	if len(f.lines("published")) != 0 {
		t.Errorf("a publish command ran: %q", f.lines("published"))
	}

	leader := f.leader(f.repo)
	if g := pgidOf(leader); g != leader {
		t.Errorf("the leader's group is %d, want its own, %d", g, leader)
	}
	if _, stat, _ := procStat(leader); !strings.Contains(stat, "s") {
		t.Errorf("the leader leads no session of its own: stat %q", stat)
	}
	if pgidOf(os.Getpid()) == leader {
		t.Error("the copy is in the caller's process group")
	}
	env := environ(leader)
	for _, kv := range []string{"GC_SESSION_ID=serve-test-session", "GC_CITY_PATH=" + filepath.Join(f.dir, "no-city"), "GC_RUNTIME_EPOCH=7"} {
		if !strings.Contains(env, kv) {
			t.Errorf("the leader does not carry %s where the orphan sweep reads it", kv)
		}
	}

	again := f.copies.Serve(f.repo, f.opts(command))
	mustRun(t, again)
	if again.Port != r.Port || f.leader(f.repo) != leader || len(f.lines("served")) != 1 {
		t.Errorf("a second start ran a second copy: port %d (was %d), leader %d (was %d), served %q",
			again.Port, r.Port, f.leader(f.repo), leader, f.lines("served"))
	}
	if c := f.copies.Check(f.repo); c.State != CopyRunning || c.Port != r.Port {
		t.Errorf("check = %s on %d, want running on %d", c.State, c.Port, r.Port)
	}

	// A start with another command, such as a capture that adds the fixture's
	// flags, would show another app, so it fails and leaves the copy running.
	busy := f.copies.Serve(f.repo, f.opts(command+" --answers x"))
	if busy.State != CopyFailed || busy.Reason != "other-command" || !strings.Contains(busy.Detail, command) {
		t.Errorf("a start with another command = %s %s (%s), want failed other-command naming the running command", busy.State, busy.Reason, busy.Detail)
	}
	if f.leader(f.repo) != leader || !answers(r.Port) || len(f.lines("served")) != 1 {
		t.Errorf("a start with another command touched the running copy: leader %d (was %d), served %q", f.leader(f.repo), leader, f.lines("served"))
	}

	other := f.copies.Serve(f.repo2, f.opts(command))
	mustRun(t, other)
	if other.Port == r.Port || !answers(other.Port) || !answers(r.Port) {
		t.Errorf("a second checkout's copy does not run beside the first: ports %d and %d", r.Port, other.Port)
	}

	if s := f.copies.Stop(f.repo); s.State != CopyStopped {
		t.Fatalf("stop = %s (%s), want stopped", s.State, s.Detail)
	}
	if !groupGone(leader) {
		t.Errorf("members of the copy's group are left: %v", members(leader, 0))
	}
	if answers(r.Port) {
		t.Error("the stopped copy's port still answers")
	}
	if c := f.copies.Check(f.repo); c.State != CopyNone {
		t.Errorf("check after stop = %s, want none", c.State)
	}
	if s := f.copies.Stop(f.repo); s.State != CopyNone {
		t.Errorf("a stop with no copy running = %s, want none", s.State)
	}
	f.copies.Stop(f.repo2)
}

func TestServePublishesOnlyWhenAskedAndTiesThePublisherToTheCopy(t *testing.T) {
	f := newServeFixture(t)
	r := f.copies.Serve(f.repo, f.published("ok", "https://host.example:$PORT/x/${PORT}"))
	mustRun(t, r)
	want := "https://host.example:" + strconv.Itoa(r.Port) + "/x/" + strconv.Itoa(r.Port)
	if address(r) != want {
		t.Errorf("address = %q, want the pattern with the port for each $PORT and ${PORT}, %q", address(r), want)
	}
	if got := f.lines("published"); len(got) != 1 || got[0] != "ok "+strconv.Itoa(r.Port) {
		t.Errorf("published %q, want one run with the port as PORT", got)
	}
	leader := f.leader(f.repo)
	if _, pub := f.rec(f.repo).publisher(); pgidOf(pub) != leader {
		t.Errorf("the publish command runs in group %d, want the copy's, %d", pgidOf(pub), leader)
	}
	if c := f.copies.Check(f.repo); address(c) != want {
		t.Errorf("check reports address %q, want %q", address(c), want)
	}

	// A publish command that ends alone leaves the copy running with no
	// address, until a start publishes it again.
	_, pub := f.rec(f.repo).publisher()
	_ = syscall.Kill(pub, syscall.SIGKILL)
	if !waitFor(5*time.Second, func() bool { return !f.rec(f.repo).publisherAlive() }) {
		t.Fatal("the publish command did not end")
	}
	c := f.copies.Check(f.repo)
	if c.State != CopyRunning || address(c) != "" || !strings.Contains(c.Detail, "publish command ended") {
		t.Errorf("check = %s, address %q, detail %q: want running, no address, and why", c.State, address(c), c.Detail)
	}
	again := f.copies.Serve(f.repo, f.published("ok", "https://host.example:$PORT/x/${PORT}"))
	mustRun(t, again)
	if again.Port != r.Port || address(again) != want || f.leader(f.repo) != leader || len(f.lines("published")) != 2 {
		t.Errorf("a start did not publish the copy again: port %d, address %q, leader %d (was %d), published %q",
			again.Port, address(again), f.leader(f.repo), leader, f.lines("published"))
	}
	_, pub = f.rec(f.repo).publisher()
	f.copies.Stop(f.repo)
	if !groupGone(leader) || syscall.Kill(pub, 0) == nil {
		t.Error("stop left the publish command running")
	}
}

func TestServeACopyThatEndsTakesItsPublishCommandWithIt(t *testing.T) {
	f := newServeFixture(t)
	mustRun(t, f.copies.Serve(f.repo, f.published("ok", "https://host.example:$PORT/")))
	leader := f.leader(f.repo)
	_, pub := f.rec(f.repo).publisher()
	served := ""
	for _, p := range members(leader, leader) {
		if out, _ := exec.Command("ps", "-o", "command=", "-p", strconv.Itoa(p)).Output(); strings.Contains(string(out), "serve.py") {
			served = strconv.Itoa(p)
		}
	}
	if served == "" {
		t.Fatal("no serve command in the copy's group")
	}
	n, _ := strconv.Atoi(served)
	_ = syscall.Kill(n, syscall.SIGTERM)
	if !waitFor(10*time.Second, func() bool { return groupGone(leader) }) {
		t.Fatalf("the leader did not end the group once the serve command ended: %v", members(leader, 0))
	}
	if syscall.Kill(pub, 0) == nil {
		t.Error("the publish command outlived its copy")
	}
	c := f.copies.Check(f.repo)
	if c.State != CopyDied || c.ExitCode == nil || *c.ExitCode != 143 {
		t.Errorf("check = %s, exit %v: want died, with the serve command's 143", c.State, c.ExitCode)
	}
	r := f.copies.Serve(f.repo, f.opts("exec python3 serve.py"))
	mustRun(t, r)
	if f.leader(f.repo) == leader {
		t.Error("the new copy runs under the old leader's pid")
	}
	f.copies.Stop(f.repo)
}

func TestServeAPublishCommandThatIgnoresTermEndsBeforeTheLeader(t *testing.T) {
	f := newServeFixture(t)
	mustRun(t, f.copies.Serve(f.repo, f.published("ignores-term", "https://host.example:$PORT/")))
	leader := f.leader(f.repo)
	_, pub := f.rec(f.repo).publisher()
	start := time.Now()
	_ = syscall.Kill(leader, syscall.SIGTERM)
	if !waitFor(StopGrace+10*time.Second, func() bool { return syscall.Kill(leader, 0) != nil }) {
		t.Fatal("the leader did not end")
	}
	if syscall.Kill(pub, 0) == nil {
		t.Error("the publish command outlived the leader")
	}
	if !groupGone(leader) {
		t.Errorf("members of the copy's group are left: %v", members(leader, 0))
	}
	if time.Since(start) < StopGrace-500*time.Millisecond {
		t.Errorf("the leader ended %s after SIGTERM, before the grace of %s gave the member its SIGKILL", time.Since(start), StopGrace)
	}
	if s := f.copies.Stop(f.repo); s.State != CopyNone {
		t.Errorf("stop = %s, want none", s.State)
	}
}

func TestServeTriesAgainAPublishRefusedWhileTheConfigChanges(t *testing.T) {
	f := newServeFixture(t)
	r := f.copies.Serve(f.repo, f.published("again-once", "https://host.example:$PORT/"))
	mustRun(t, r)
	if want := "https://host.example:" + strconv.Itoa(r.Port) + "/"; address(r) != want {
		t.Errorf("address = %q, want %q", address(r), want)
	}
	if got := f.lines("published"); len(got) != 2 || got[0] != got[1] {
		t.Errorf("published %q, want the same port tried twice", got)
	}
	f.copies.Stop(f.repo)
}

func TestServeMovesACopyWhosePortIsRefusedAsTaken(t *testing.T) {
	f := newServeFixture(t)
	r := f.copies.Serve(f.repo, f.published("taken-first", "https://host.example:$PORT/"))
	mustRun(t, r)
	first, _ := strconv.Atoi(strings.TrimSpace(readFile(filepath.Join(f.dir, "published.first"))))
	if first == 0 || r.Port == first {
		t.Fatalf("the copy runs on port %d, refused port %d", r.Port, first)
	}
	if want := "https://host.example:" + strconv.Itoa(r.Port) + "/"; address(r) != want {
		t.Errorf("address = %q, want %q", address(r), want)
	}
	if n := len(f.lines("served")); n != 2 {
		t.Errorf("the serve command ran %d times, want twice", n)
	}
	if answers(first) || !answers(r.Port) {
		t.Errorf("the refused port %d answers, or the new port %d does not", first, r.Port)
	}
	f.copies.Stop(f.repo)
}

func TestServeAPublishRefusedForAnotherReasonLeavesTheCopyRunning(t *testing.T) {
	f := newServeFixture(t)
	r := f.copies.Serve(f.repo, f.published("fails", "https://host.example:$PORT/"))
	mustRun(t, r)
	if address(r) != "" || !strings.Contains(r.Detail, "access denied") {
		t.Errorf("address %q, detail %q: want no address, and what the publish command said", address(r), r.Detail)
	}
	f.copies.Stop(f.repo)
}

func TestServeWithNoPublisherGivesNoAddress(t *testing.T) {
	f := newServeFixture(t)
	o := f.opts("exec python3 serve.py")
	o.Publish = true
	r := f.copies.Serve(f.repo, o)
	mustRun(t, r)
	if address(r) != "" || !strings.Contains(r.Detail, "no address can be given") || len(f.lines("published")) != 0 {
		t.Errorf("address %q, detail %q, published %q: want no address, why, and no publish", address(r), r.Detail, f.lines("published"))
	}
	f.copies.Stop(f.repo)
}

func TestServeRefusesWhatCannotRunAndLeavesNoRecord(t *testing.T) {
	f := newServeFixture(t)
	o := f.opts("exec python3 serve.py")
	o.ScriptsDir = ""
	if r := f.copies.Serve(f.repo, o); r.State != CopyFailed || r.Reason != "no-sandbox" {
		t.Errorf("no scripts directory: %s %s, want failed no-sandbox", r.State, r.Reason)
	}
	o.ScriptsDir = f.dir
	if r := f.copies.Serve(f.repo, o); r.State != CopyFailed || r.Reason != "no-sandbox" {
		t.Errorf("a scripts directory with no %s: %s %s, want failed no-sandbox", SandboxLib, r.State, r.Reason)
	}
	old := freePort
	freePort = func() (int, error) { return 0, errors.New("no port") }
	r := f.copies.Serve(f.repo, f.opts("exec python3 serve.py"))
	freePort = old
	if r.State != CopyFailed || r.Reason != "no-free-port" {
		t.Errorf("no free port: %s %s, want failed no-free-port", r.State, r.Reason)
	}
	if entries, _ := os.ReadDir(f.copies.root); len(entries) != 0 {
		t.Errorf("a refusal left a record: %v", entries)
	}
}

func TestServeStopsACopyThatNeverComesUp(t *testing.T) {
	f := newServeFixture(t)
	r := f.copies.Serve(f.repo, f.opts("echo cannot serve; exit 3"))
	if r.State != CopyFailed || r.Reason != "serve-exited" || r.ExitCode == nil || *r.ExitCode != 3 || !strings.Contains(r.Tail, "cannot serve") {
		t.Errorf("a serve command that ends at once: %s %s exit %v tail %q", r.State, r.Reason, r.ExitCode, r.Tail)
	}
	o := f.opts("echo $$ > " + filepath.Join(f.dir, "never.pid") + "; exec sleep 60")
	o.Wait = 2 * time.Second
	r = f.copies.Serve(f.repo, o)
	if r.State != CopyFailed || r.Reason != "not-answering" {
		t.Errorf("a copy that never answers: %s %s, want failed not-answering", r.State, r.Reason)
	}
	never, _ := strconv.Atoi(strings.TrimSpace(readFile(filepath.Join(f.dir, "never.pid"))))
	if never == 0 || syscall.Kill(never, 0) == nil {
		t.Errorf("the copy that never answered, %d, was not stopped", never)
	}
	if entries, _ := os.ReadDir(f.copies.root); len(entries) != 0 {
		t.Errorf("a copy that failed left a record: %v", entries)
	}
}

func TestServeAStartThatFindsACopyNotAnsweringStopsItAfterItsOwnWait(t *testing.T) {
	f := newServeFixture(t)
	// A start cut off after its leader ran: the record is claimed and the
	// leader started, and nothing waits for the copy to answer.
	if err := os.MkdirAll(f.copies.root, 0o755); err != nil {
		t.Fatal(err)
	}
	rec := f.rec(f.repo)
	if err := os.Mkdir(string(rec), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, v := range map[string]string{"checkout": f.repo, "command": "exec sleep 120", "scripts": f.scripts,
		"grace_ms": strconv.FormatInt(StopGrace.Milliseconds(), 10), "port": "1"} {
		if err := rec.write(name, v); err != nil {
			t.Fatal(err)
		}
	}
	port, _ := freePort()
	_ = rec.write("port", strconv.Itoa(port))
	if reason, detail := startLeader(rec); reason != "" {
		t.Fatalf("%s: %s", reason, detail)
	}
	if !rec.awaitLeader(15 * time.Second) {
		t.Fatal("the leader did not start")
	}
	leader := f.leader(f.repo)
	if c := f.copies.Check(f.repo); c.State != CopyNotAnswering {
		t.Errorf("check = %s, want not-answering", c.State)
	}
	o := f.opts("exec sleep 120")
	o.Wait = 2 * time.Second
	r := f.copies.Serve(f.repo, o)
	if r.State != CopyFailed || r.Reason != "not-answering" {
		t.Errorf("a start that finds it: %s %s, want failed not-answering", r.State, r.Reason)
	}
	if !groupGone(leader) {
		t.Errorf("the copy that did not answer was not stopped: %v", members(leader, 0))
	}
	if _, err := os.Stat(string(rec)); err == nil {
		t.Error("its record is left")
	}
}

func TestOwnedNeedsEachListenerALoopbackConnectionReachesInTheCopysGroup(t *testing.T) {
	if _, err := exec.LookPath("lsof"); err != nil {
		t.Skip("lsof is not on PATH")
	}
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	port := l.Addr().(*net.TCPAddr).Port
	mine := pgidOf(os.Getpid())
	if ok, why := owned(port, mine); !ok {
		t.Errorf("a listener in the group is not owned: %s", why)
	}
	if ok, _ := owned(port, mine+100000); ok {
		t.Error("a listener outside the group counts as the copy's")
	}
	free, _ := freePort()
	if ok, why := owned(free, mine); ok || !strings.Contains(why, "nothing listens") {
		t.Errorf("a port nothing listens on: owned %v, %q", ok, why)
	}
	for addr, want := range map[string]bool{
		"127.0.0.1:80": true, "*:80": true, "[::1]:80": true, "[::]:80": true, "localhost:80": true,
		"100.64.1.2:80": false, "[fd7a:115c::1]:80": false, "192.168.1.5:80": false,
	} {
		if got := reachedFromLoopback(addr); got != want {
			t.Errorf("reachedFromLoopback(%q) = %v, want %v", addr, got, want)
		}
	}
}
