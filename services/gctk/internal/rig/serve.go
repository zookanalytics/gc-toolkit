package rig

// A copy of a rig's UI: the rig's serve command, run from a checkout on a
// loopback port of its own, inside the sandbox the pack's demo capture runs
// in, and published at an address of its own only when its caller asks. A
// demo capture points its engine at the copy's port, and a sitting gives the
// operator its address, so both see the UI through one path.
//
// A copy is a process group of its own, led by a gctk process that start
// leaves running in a new session. The leader runs the serve command, runs the
// publish command whenever start asks it to, and ends the whole group when the
// serve command ends or a signal ends the leader, so no address outlives its
// copy. It sends the group SIGTERM, then SIGKILL to any member still running
// after the grace, and it ends last, so a copy whose leader is gone has
// nothing left running.
//
// The serve command runs inside the sandbox that demo-engine-lib.sh, in the
// pack's scripts directory, defines for a capture: it cannot read the city's
// directories, reach a loopback port but its own or a Unix socket, or signal a
// process outside, and it runs with none of the variables that point a command
// at the city. The publish command is the city's, and it runs outside the
// sandbox, beside the leader.
//
// A copy ends when its caller stops it. It also ends once the session that
// started it has ended, through Gas City's orphan sweep, which this composes
// and does not rebuild. The sweep ends a process that left its session's
// process group, carries the session's GC_SESSION_ID and GC_CITY_PATH, and has
// been reparented to PID 1, once its session is closed, or stopped with no live
// pane, and for a stopped session it also needs the process's GC_RUNTIME_EPOCH.
// It signals the whole process group (`sweepProcessTableOrphans` and
// `processRootIncarnationOver` in Gas City's cmd/gc/session_beads.go). The
// leader keeps the three values from its caller's environment, leads the
// copy's group, and is a gctk binary, whose environment macOS lets ps read.

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// A copy's state, as a report names it.
const (
	CopyRunning      = "running"
	CopyNotAnswering = "not-answering"
	CopyDied         = "died"
	CopyNone         = "none"
	CopyStopped      = "stopped"
	CopyFailed       = "failed"
)

// SandboxLib is the file in the pack's scripts directory that defines the
// capture's sandbox, which a copy's serve command runs inside.
const SandboxLib = "demo-engine-lib.sh"

// serveDirName is the copies' directory under the git common directory, beside
// the check records.
const serveDirName = "gc-rig-serve"

// tries bounds the port moves and the publishes tried again.
const tries = 3

// SettleTime is how long a publish command must run before the copy counts as
// published. A variable so a test can shorten it.
var SettleTime = 3 * time.Second

// Report is what one serve call found or did.
type Report struct {
	State  string `json:"state"`
	Reason string `json:"reason,omitempty"`
	// Checkout is the top of the checkout the copy runs from, which names it.
	Checkout string `json:"checkout"`
	Port     int    `json:"port,omitempty"`
	// Address is set for a running copy, and empty when it has none.
	Address *string `json:"address,omitempty"`
	Log     string  `json:"log,omitempty"`
	// ExitCode is the serve command's exit status, for a copy that ended.
	ExitCode *int   `json:"exit_code,omitempty"`
	Detail   string `json:"detail,omitempty"`
	// Tail holds the last lines of the serve command's log, for the caller's
	// own lines. It is not part of the report.
	Tail string `json:"-"`
}

// ServeOpts is what a start is given.
type ServeOpts struct {
	// Command is the serve command, run with bash from the checkout's top with
	// the copy's port as $PORT.
	Command string
	// Publish asks for an address. PublishCommand publishes the copy's port, as
	// $PORT, for as long as it runs, and AddressPattern is the address it gives,
	// with $PORT or ${PORT} where the port goes. Either empty means no address
	// can be given.
	Publish        bool
	PublishCommand string
	AddressPattern string
	// Wait bounds how long start waits for the copy to answer on its port.
	Wait time.Duration
	// ScriptsDir is the pack's scripts directory, which holds SandboxLib.
	ScriptsDir string
}

// Copies is the copies' directory of one clone.
type Copies struct {
	root string
}

// NewCopies returns the copies' directory under commonDir, the clone's git
// common directory.
func NewCopies(commonDir string) *Copies {
	return &Copies{root: filepath.Join(commonDir, serveDirName)}
}

// Dir is the record directory of the copy of checkout, the hash of its path.
func (c *Copies) Dir(checkout string) string {
	sum := sha256.Sum256([]byte(checkout))
	return filepath.Join(c.root, hex.EncodeToString(sum[:16]))
}

// copyRec is one copy's record directory, a file per value.
type copyRec string

func (r copyRec) path(name string) string { return filepath.Join(string(r), name) }

// read returns a value as write wrote it, or "" when the file is absent.
func (r copyRec) read(name string) string {
	b, err := os.ReadFile(r.path(name))
	if err != nil {
		return ""
	}
	return strings.TrimSuffix(string(b), "\n")
}

func (r copyRec) num(name string) (int, bool) {
	n, err := strconv.Atoi(strings.TrimSpace(r.read(name)))
	return n, err == nil && n > 0
}

func (r copyRec) has(name string) bool {
	_, err := os.Stat(r.path(name))
	return err == nil
}

// write writes a file by rename, so a reader never sees half of it.
func (r copyRec) write(name, value string) error {
	tmp := r.path(name + ".tmp")
	if err := os.WriteFile(tmp, []byte(value+"\n"), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, r.path(name))
}

func (r copyRec) remove(names ...string) {
	for _, n := range names {
		_ = os.Remove(r.path(n))
	}
}

// --- the host ----------------------------------------------------------------

// freePort picks a loopback port that nothing listens on. A variable so a test
// can make the pick fail.
var freePort = func() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}

// answers reports whether something accepts a connection on the loopback port.
func answers(port int) bool {
	c, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), time.Second)
	if err != nil {
		return false
	}
	c.Close()
	return true
}

// listeners returns the processes that listen on the TCP port at an address a
// connection to loopback reaches: a loopback address or every address. One that
// listens on another address, as a publisher's daemon listens on the host's
// network address, is left out.
func listeners(port int) ([]int, error) {
	out, err := exec.Command("lsof", "-nP", "-iTCP:"+strconv.Itoa(port), "-sTCP:LISTEN", "-F", "pn").Output()
	var ee *exec.ExitError
	if err != nil && !(errors.As(err, &ee) && len(out) == 0) {
		return nil, fmt.Errorf("lsof did not list the listeners on port %d: %v", port, err)
	}
	seen := map[int]bool{}
	var pids []int
	pid := 0
	for _, line := range strings.Split(string(out), "\n") {
		switch {
		case strings.HasPrefix(line, "p"):
			pid, _ = strconv.Atoi(line[1:])
		case strings.HasPrefix(line, "n") && pid > 0 && reachedFromLoopback(line[1:]) && !seen[pid]:
			seen[pid] = true
			pids = append(pids, pid)
		}
	}
	return pids, nil
}

// reachedFromLoopback reports whether a listening address, host:port as lsof
// names it, takes a connection to loopback.
func reachedFromLoopback(addr string) bool {
	host := addr
	if i := strings.LastIndex(addr, ":"); i >= 0 {
		host = addr[:i]
	}
	host = strings.Trim(host, "[]")
	switch host {
	case "*", "0.0.0.0", "::", "localhost", "::1":
		return true
	}
	return strings.HasPrefix(host, "127.")
}

// pgidOf returns a process's group, or 0 when ps does not name it.
func pgidOf(pid int) int {
	out, err := exec.Command("ps", "-o", "pgid=", "-p", strconv.Itoa(pid)).Output()
	if err != nil {
		return 0
	}
	n, _ := strconv.Atoi(strings.TrimSpace(string(out)))
	return n
}

// owned reports whether the copy whose group pgid names holds the port: at
// least one process listens there, and each one a connection to loopback
// reaches is a member of the group. It says why when it does not.
func owned(port, pgid int) (bool, string) {
	pids, err := listeners(port)
	if err != nil {
		return false, err.Error()
	}
	if len(pids) == 0 {
		return false, fmt.Sprintf("nothing listens on port %d", port)
	}
	for _, p := range pids {
		if g := pgidOf(p); g != pgid {
			return false, fmt.Sprintf("process %d, which listens on port %d, is not one of the copy's", p, port)
		}
	}
	return true, ""
}

// startID is a process's start, in a form that stays the same for as long as it
// runs, so a pid the kernel reused, which belongs to a process that started
// later, is told from the leader: the starttime field of /proc/<pid>/stat where
// that exists, else ps's start time in the C locale and UTC.
func startID(pid int) string {
	if b, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid)); err == nil {
		s := string(b)
		if i := strings.LastIndex(s, ") "); i >= 0 {
			if f := strings.Fields(s[i+2:]); len(f) > 19 {
				return f[19]
			}
		}
		return ""
	}
	cmd := exec.Command("ps", "-o", "lstart=", "-p", strconv.Itoa(pid))
	cmd.Env = append(os.Environ(), "LC_ALL=C", "TZ=UTC")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.Join(strings.Fields(string(out)), " ")
}

// procStat returns a process's parent and its ps state, or false when ps does
// not name it.
func procStat(pid int) (int, string, bool) {
	out, err := exec.Command("ps", "-o", "ppid=,stat=", "-p", strconv.Itoa(pid)).Output()
	if err != nil {
		return 0, "", false
	}
	f := strings.Fields(string(out))
	if len(f) < 2 {
		return 0, "", false
	}
	ppid, err := strconv.Atoi(f[0])
	return ppid, f[1], err == nil
}

// members returns the processes of the group other than skip, leaving out any
// that has exited and waits to be reaped. ps runs in a group of its own, so it
// never lists itself among a group it is asked about.
func members(pgid, skip int) []int {
	cmd := exec.Command("ps", "-A", "-o", "pgid=,pid=,stat=")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	out, err := cmd.Output()
	if err != nil {
		return nil
	}
	var pids []int
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) < 3 || f[0] != strconv.Itoa(pgid) || strings.HasPrefix(f[2], "Z") {
			continue
		}
		if p, err := strconv.Atoi(f[1]); err == nil && p != skip {
			pids = append(pids, p)
		}
	}
	return pids
}

// groupGone reports whether no live process is left in the group. kill answers
// ESRCH for an empty group, and on darwin EPERM for one whose only members have
// exited and wait to be reaped.
func groupGone(pgid int) bool {
	err := syscall.Kill(-pgid, 0)
	if errors.Is(err, syscall.ESRCH) {
		return true
	}
	return errors.Is(err, syscall.EPERM) && len(members(pgid, 0)) == 0
}

// --- the record --------------------------------------------------------------

// alive reports whether the copy's leader runs and is the process its record
// names.
func (r copyRec) alive() bool {
	pid, ok := r.num("pid")
	if !ok || syscall.Kill(pid, 0) != nil {
		return false
	}
	if _, stat, ok := procStat(pid); !ok || strings.HasPrefix(stat, "Z") {
		return false
	}
	want := r.read("start_id")
	if want == "" {
		return true
	}
	got := startID(pid)
	return got == "" || got == want
}

// publisher returns the run of the publish command the record names and its
// pid.
func (r copyRec) publisher() (int, int) {
	f := strings.Fields(r.read("publisher"))
	if len(f) != 2 {
		return 0, 0
	}
	gen, _ := strconv.Atoi(f[0])
	pid, _ := strconv.Atoi(f[1])
	return gen, pid
}

// publisherAlive reports whether that run of the publish command still runs,
// as the leader's child.
func (r copyRec) publisherAlive() bool {
	_, pid := r.publisher()
	leader, ok := r.num("pid")
	if pid <= 0 || !ok {
		return false
	}
	ppid, stat, ok := procStat(pid)
	return ok && ppid == leader && !strings.HasPrefix(stat, "Z")
}

// ready reports whether the copy answers on its port and holds it.
func (r copyRec) ready() (bool, string) {
	port, ok := r.num("port")
	pid, okp := r.num("pid")
	if !ok || !okp {
		return false, "its record names no port or no leader"
	}
	if !answers(port) {
		return false, fmt.Sprintf("nothing answers on port %d", port)
	}
	return owned(port, pid)
}

// tail returns the last n lines of a file.
func tail(path string, n int) string {
	b, err := os.ReadFile(path)
	if err != nil || len(b) == 0 {
		return ""
	}
	lines := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

func (r copyRec) running(checkout string) Report {
	port, _ := r.num("port")
	addr := ""
	if r.publisherAlive() {
		addr = r.read("address")
	}
	rep := Report{State: CopyRunning, Checkout: checkout, Port: port, Address: &addr, Log: r.path("serve.log")}
	if addr == "" {
		rep.Detail = r.noAddressWhy()
	}
	return rep
}

// noAddressWhy says why a running copy has no address.
func (r copyRec) noAddressWhy() string {
	switch {
	case !r.has("asked"):
		return "it was started without --publish-command, so it has no address"
	case r.read("publish_command") == "" || r.read("address_pattern") == "":
		return "no publish command or no address pattern was given, so no address can be given"
	}
	last := strings.TrimSpace(tail(r.path("publish.log"), 1))
	if last != "" {
		last = fmt.Sprintf(" (%q)", last)
	}
	return "its publish command ended" + last + ", so it has no address until a start with --publish-command publishes it again"
}

// stopGroup ends the copy's process group, which its leader leads. Only a
// leader proved alive names a group that is still this copy's, since a dead
// leader's pid can be reused. It returns false when the group survived SIGTERM
// and SIGKILL.
func (r copyRec) stopGroup() bool {
	pid, ok := r.num("pid")
	if !ok || !r.alive() {
		return true
	}
	_ = syscall.Kill(-pid, syscall.SIGTERM)
	deadline := time.Now().Add(StopGrace)
	for !groupGone(pid) && time.Now().Before(deadline) {
		time.Sleep(200 * time.Millisecond)
	}
	if !groupGone(pid) {
		_ = syscall.Kill(-pid, syscall.SIGKILL)
		for i := 0; i < 10 && !groupGone(pid); i++ {
			time.Sleep(200 * time.Millisecond)
		}
	}
	return groupGone(pid)
}

// addressFor fills the address pattern with the port.
func addressFor(pattern string, port int) string {
	p := strconv.Itoa(port)
	return strings.ReplaceAll(strings.ReplaceAll(pattern, "${PORT}", p), "$PORT", p)
}

// --- start, check and stop ---------------------------------------------------

// leaderCommand is the command that runs a copy's leader over its record. A
// variable so a test can run its own binary as the leader.
var leaderCommand = func(dir string) (*exec.Cmd, error) {
	exe, err := os.Executable()
	if err != nil {
		return nil, err
	}
	return exec.Command(exe, "rig", "serve", "--lead", dir), nil
}

// Serve starts a copy of the checkout whose top is checkout, or reports the
// copy of it that runs. A checkout has at most one copy, so a start for one
// whose copy runs starts no other, and a start after a session wakes is safe to
// repeat. A start reports a copy once it answers on its port and holds it, and
// stops a copy that does not within the wait, whether it ran the copy or found
// it.
func (c *Copies) Serve(checkout string, o ServeOpts) Report {
	failed := func(reason, detail string) Report {
		return Report{State: CopyFailed, Reason: reason, Checkout: checkout, Detail: detail}
	}
	if o.ScriptsDir == "" {
		return failed("no-sandbox", "GCTK_SCRIPTS_DIR names no scripts directory, so the sandbox the copy runs in ("+SandboxLib+") cannot be found; set it to the pack's scripts directory, which gc <binding> scripts-dir prints")
	}
	if st, err := os.Stat(filepath.Join(o.ScriptsDir, SandboxLib)); err != nil || st.IsDir() {
		return failed("no-sandbox", fmt.Sprintf("%s holds no %s, which defines the sandbox the copy runs in", o.ScriptsDir, SandboxLib))
	}
	if err := os.MkdirAll(c.root, 0o755); err != nil {
		return failed("no-state", fmt.Sprintf("the copies' directory %s could not be made: %v", c.root, err))
	}
	rec := copyRec(c.Dir(checkout))
	for claims := 0; ; claims++ {
		if err := os.Mkdir(string(rec), 0o755); err == nil {
			break
		}
		if claims >= tries {
			return failed("no-state", fmt.Sprintf("the record %s could neither be claimed nor read", rec))
		}
		// A record that holds no leader yet is a start in progress, or one that
		// died before its leader ran.
		if !rec.awaitLeader(30*time.Second) || !rec.alive() {
			_ = os.RemoveAll(string(rec))
			continue
		}
		// The checkout's copy runs. It is reported once it answers, published
		// first when an address is asked for. The start that ran it may have
		// been cut off before its wait ended, so this start's wait decides, as a
		// new copy's does.
		if o.Publish {
			_ = rec.write("asked", "")
			_ = rec.write("publish_command", o.PublishCommand)
			_ = rec.write("address_pattern", o.AddressPattern)
			if port, ok := rec.num("port"); ok {
				_ = rec.write("address", addressFor(o.AddressPattern, port))
			}
			if o.PublishCommand != "" && o.AddressPattern != "" && !rec.publisherAlive() {
				if rec.publish() == publishTaken {
					rec.stopGroup()
					return c.launch(rec, checkout, o)
				}
			}
		}
		return rec.await(checkout, o.Wait)
	}
	for name, v := range map[string]string{"checkout": checkout, "command": o.Command, "scripts": o.ScriptsDir,
		"grace_ms": strconv.FormatInt(StopGrace.Milliseconds(), 10)} {
		if err := rec.write(name, v); err != nil {
			_ = os.RemoveAll(string(rec))
			return failed("no-state", fmt.Sprintf("the record %s could not be written: %v", rec, err))
		}
	}
	if o.Publish {
		_ = rec.write("asked", "")
		_ = rec.write("publish_command", o.PublishCommand)
		_ = rec.write("address_pattern", o.AddressPattern)
	}
	return c.launch(rec, checkout, o)
}

// publishResult is how a publish ended.
type publishResult int

const (
	publishOK publishResult = iota + 1
	publishTaken
	publishRefused
)

// awaitLeader waits until the copy's leader has recorded its pid, and reports
// whether it did within the bound.
func (r copyRec) awaitLeader(bound time.Duration) bool {
	deadline := time.Now().Add(bound)
	for !r.has("pid") && time.Now().Before(deadline) {
		time.Sleep(200 * time.Millisecond)
	}
	return r.has("pid")
}

// publish has the copy's leader run the publish command again, and waits for
// that run to settle. A publish refused while another client changes the
// publisher's config, which Tailscale answers with "please try again", is
// tried again on the same port. One refused because another mapping holds the
// port, which Tailscale answers with "listener already exists for port", is
// taken.
func (r copyRec) publish() publishResult {
	for try := 1; try <= tries; try++ {
		gen, _ := r.publisher()
		pid, ok := r.num("pid")
		if !ok || syscall.Kill(pid, syscall.SIGUSR1) != nil {
			return publishRefused
		}
		deadline := time.Now().Add(10 * time.Second)
		for {
			if g, _ := r.publisher(); g == gen+1 {
				break
			}
			if time.Now().After(deadline) {
				return publishRefused
			}
			time.Sleep(100 * time.Millisecond)
		}
		settle := time.Now().Add(SettleTime)
		for r.publisherAlive() && time.Now().Before(settle) {
			time.Sleep(200 * time.Millisecond)
		}
		if r.publisherAlive() {
			return publishOK
		}
		log, _ := os.ReadFile(r.path("publish.log"))
		switch {
		case strings.Contains(string(log), "already exists for port"):
			return publishTaken
		case strings.Contains(string(log), "try again"):
			time.Sleep(time.Second)
		default:
			return publishRefused
		}
	}
	return publishRefused
}

// launch runs a copy over the claimed record, on a free port, publishing it
// when its record asks for an address the caller could give, and reports it
// once it answers.
func (c *Copies) launch(rec copyRec, checkout string, o ServeOpts) Report {
	failed := func(reason, detail string) Report {
		_ = os.RemoveAll(string(rec))
		return Report{State: CopyFailed, Reason: reason, Checkout: checkout, Detail: detail}
	}
	publishable := rec.has("asked") && rec.read("publish_command") != "" && rec.read("address_pattern") != ""
	for try := 1; try <= tries; try++ {
		port, err := freePort()
		if err != nil {
			return failed("no-free-port", fmt.Sprintf("no free loopback port could be picked: %v", err))
		}
		rec.remove("pid", "start_id", "publisher", "rc", "serve.log", "publish.log", "address")
		if err := rec.write("port", strconv.Itoa(port)); err != nil {
			return failed("no-state", fmt.Sprintf("the record %s could not be written: %v", rec, err))
		}
		if publishable {
			_ = rec.write("address", addressFor(rec.read("address_pattern"), port))
		}
		if reason, detail := startLeader(rec); reason != "" {
			return failed(reason, detail)
		}
		if !rec.awaitLeader(15 * time.Second) {
			return failed("not-started", "the copy's leader did not start within 15 seconds")
		}
		if publishable && rec.publish() == publishTaken && try < tries {
			rec.stopGroup()
			continue
		}
		break
	}
	return rec.await(checkout, o.Wait)
}

// startLeader starts the copy's leader in a session of its own, so it leads a
// process group that outlives this call, and is reparented to PID 1 once this
// process exits. Its environment is the caller's, whole, because the orphan
// sweep reads the session's values from it.
func startLeader(rec copyRec) (string, string) {
	cmd, err := leaderCommand(string(rec))
	if err != nil {
		return "not-started", fmt.Sprintf("the copy's leader could not be named: %v", err)
	}
	logf, err := os.OpenFile(rec.path("serve.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return "no-state", fmt.Sprintf("the copy's log could not be opened: %v", err)
	}
	defer logf.Close()
	cmd.Stdin = nil
	cmd.Stdout = logf
	cmd.Stderr = logf
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return "not-started", fmt.Sprintf("the copy's leader did not start: %v", err)
	}
	// The leader is this process's child until this process exits, so one
	// that ends while a start waits is reaped here, and reads as gone.
	go func() { _ = cmd.Wait() }()
	return "", ""
}

// await waits for the copy to answer on its port and hold it, and reports it.
// A copy whose leader ends first, or that does not answer within the wait, is
// stopped, and its record goes.
func (r copyRec) await(checkout string, wait time.Duration) Report {
	port, _ := r.num("port")
	deadline := time.Now().Add(wait)
	for {
		ok, why := r.ready()
		if ok && r.alive() {
			return r.running(checkout)
		}
		if !r.alive() {
			rep := Report{State: CopyFailed, Reason: "serve-exited", Checkout: checkout,
				Detail: fmt.Sprintf("the serve command ended before the copy answered on port %d", port),
				Tail:   tail(r.path("serve.log"), 20)}
			if rc, okRC := r.exitCode(); okRC {
				rep.ExitCode = &rc
			}
			_ = os.RemoveAll(string(r))
			return rep
		}
		if !time.Now().Before(deadline) {
			r.stopGroup()
			rep := Report{State: CopyFailed, Reason: "not-answering", Checkout: checkout,
				Detail: fmt.Sprintf("the copy did not answer on port %d within %s (%s), so it was stopped", port, wait, why),
				Tail:   tail(r.path("serve.log"), 20)}
			_ = os.RemoveAll(string(r))
			return rep
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func (r copyRec) exitCode() (int, bool) {
	rc, err := strconv.Atoi(strings.TrimSpace(r.read("rc")))
	return rc, err == nil
}

// Check reports the state of the checkout's copy, and starts nothing.
func (c *Copies) Check(checkout string) Report {
	rec := copyRec(c.Dir(checkout))
	if _, err := os.Stat(string(rec)); err != nil {
		return Report{State: CopyNone, Checkout: checkout}
	}
	if rec.alive() {
		ok, why := rec.ready()
		if ok {
			return rec.running(checkout)
		}
		port, _ := rec.num("port")
		return Report{State: CopyNotAnswering, Checkout: checkout, Port: port, Log: rec.path("serve.log"),
			Detail: fmt.Sprintf("the copy runs and does not answer on port %d as its own (%s); a start waits for it to, and stops it when it does not", port, why),
			Tail:   tail(rec.path("serve.log"), 20)}
	}
	rep := Report{State: CopyDied, Checkout: checkout, Log: rec.path("serve.log"), Tail: tail(rec.path("serve.log"), 20)}
	if rc, ok := rec.exitCode(); ok {
		rep.ExitCode = &rc
	}
	return rep
}

// Stop ends the checkout's copy and its record.
func (c *Copies) Stop(checkout string) Report {
	rec := copyRec(c.Dir(checkout))
	if _, err := os.Stat(string(rec)); err != nil {
		return Report{State: CopyNone, Checkout: checkout}
	}
	if !rec.alive() {
		_ = os.RemoveAll(string(rec))
		return Report{State: CopyNone, Checkout: checkout}
	}
	if rec.stopGroup() {
		_ = os.RemoveAll(string(rec))
		return Report{State: CopyStopped, Checkout: checkout}
	}
	return Report{State: CopyRunning, Checkout: checkout, Detail: "the copy's process group survived SIGTERM and SIGKILL"}
}

// --- the leader --------------------------------------------------------------

// sandboxed runs the serve command, given after the port and the checkout,
// inside the capture's sandbox, which demo-engine-lib.sh composes for the one
// loopback port and the checkout.
const sandboxed = `. "$1/` + SandboxLib + `" || exit 126; shift; demo_engine_sandboxed "$@"`

// Lead runs the copy whose record is dir: the serve command, inside the
// sandbox, and the publish command each time the leader gets SIGUSR1. It ends
// the copy's whole process group when the serve command ends or a signal ends
// the leader, and returns the code the leader exits with. It sets its signals
// up before it records its pid, so a signal start sends once it reads the pid
// reaches it.
func Lead(dir string) int {
	rec := copyRec(dir)
	sigs := make(chan os.Signal, 8)
	signal.Notify(sigs, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP, syscall.SIGUSR1)
	me := os.Getpid()
	grace := StopGrace
	if ms, ok := rec.num("grace_ms"); ok {
		grace = time.Duration(ms) * time.Millisecond
	}
	// copied closes once the serve command's output is all in the log.
	var copied chan struct{}
	end := func(code int) int {
		signal.Ignore(syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP, syscall.SIGUSR1)
		_ = syscall.Kill(-me, syscall.SIGTERM)
		deadline := time.Now().Add(grace)
		for len(members(me, me)) > 0 && time.Now().Before(deadline) {
			time.Sleep(200 * time.Millisecond)
		}
		if len(members(me, me)) > 0 {
			// The KILL ends the leader with the group, so the leader never ends
			// while a member runs.
			_ = syscall.Kill(-me, syscall.SIGKILL)
		}
		// The group has ended, so the pipe has no writer left, and the copy of
		// its output finishes at once.
		select {
		case <-copied:
		case <-time.After(time.Second):
		}
		return code
	}
	port, ok := rec.num("port")
	checkout := rec.read("checkout")
	if !ok || checkout == "" {
		return end(1)
	}
	_ = rec.write("start_id", startID(me))
	if err := rec.write("pid", strconv.Itoa(me)); err != nil {
		return end(1)
	}

	logf, err := os.OpenFile(rec.path("serve.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return end(1)
	}
	// The serve command writes through a pipe, which the leader copies to the
	// log, so the sandbox never has to grant a write to the record. A serve
	// command whose leader is gone dies at its next write.
	pr, pw, err := os.Pipe()
	if err != nil {
		return end(1)
	}
	copied = make(chan struct{})
	go func() { _, _ = io.Copy(logf, pr); close(copied) }()
	serve := exec.Command("bash", "-c", sandboxed, "gctk rig serve", rec.read("scripts"), strconv.Itoa(port), checkout,
		"bash", "-c", rec.read("command"))
	serve.Dir = checkout
	serve.Env = append(os.Environ(), "PORT="+strconv.Itoa(port), "PROG=gctk rig serve")
	serve.Stdout, serve.Stderr = pw, pw
	if err := serve.Start(); err != nil {
		fmt.Fprintf(logf, "gctk rig serve: the serve command did not start: %v\n", err)
		_ = rec.write("rc", "127")
		return end(127)
	}
	pw.Close()
	done := make(chan int, 1)
	go func() {
		err := serve.Wait()
		done <- exitStatus(serve.ProcessState, err)
	}()

	gen := 0
	for {
		select {
		case s := <-sigs:
			if s == syscall.SIGUSR1 {
				gen++
				leadPublish(rec, port, gen)
				continue
			}
			return end(128 + int(s.(syscall.Signal)))
		case rc := <-done:
			_ = rec.write("rc", strconv.Itoa(rc))
			return end(rc)
		}
	}
}

// leadPublish runs the publish command for the copy's port, in the copy's
// group, and records which run it is and its pid.
func leadPublish(rec copyRec, port, gen int) {
	pub := exec.Command("bash", "-c", rec.read("publish_command"))
	pub.Dir = rec.read("checkout")
	pub.Env = append(os.Environ(), "PORT="+strconv.Itoa(port))
	logf, err := os.Create(rec.path("publish.log"))
	if err != nil {
		return
	}
	defer logf.Close()
	pub.Stdout, pub.Stderr = logf, logf
	if err := pub.Start(); err != nil {
		fmt.Fprintf(logf, "gctk rig serve: the publish command did not start: %v\n", err)
		_ = rec.write("publisher", fmt.Sprintf("%d 0", gen))
		return
	}
	_ = rec.write("publisher", fmt.Sprintf("%d %d", gen, pub.Process.Pid))
	go func() { _ = pub.Wait() }()
}

// exitStatus is a finished command's status as a shell reports it: its exit
// code, or 128 plus the signal that ended it.
func exitStatus(ps *os.ProcessState, err error) int {
	if ps == nil {
		return 127
	}
	if ws, ok := ps.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
		return 128 + int(ws.Signal())
	}
	if code := ps.ExitCode(); code >= 0 {
		return code
	}
	if err != nil {
		return 1
	}
	return 0
}
