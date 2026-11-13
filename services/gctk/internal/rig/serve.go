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
//
// Every process a copy starts, signals or reads, and every connection it
// opens, goes through the host adapter (internal/host), so each decision here
// is tested on its fake.
//
// Starts and stops of one checkout take turns under the checkout's lock, so
// each reads the record the one before it left and none acts on a record
// another is changing.

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
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
	ExitCode *int `json:"exit_code,omitempty"`
	// Started is set on the report of a start that found no copy running and
	// ran one, so its caller knows the copy is its own to stop. A start that
	// found the copy running leaves it unset.
	Started bool   `json:"started,omitempty"`
	Detail  string `json:"detail,omitempty"`
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

// Copies is the copies' directory of one clone, and the host they run on.
type Copies struct {
	root string
	h    host.Host
}

// NewCopies returns the copies' directory under commonDir, the clone's git
// common directory, whose copies run on h.
func NewCopies(commonDir string, h host.Host) *Copies {
	return &Copies{root: filepath.Join(commonDir, serveDirName), h: h}
}

// Dir is the record directory of the copy of checkout, the hash of its path.
func (c *Copies) Dir(checkout string) string {
	sum := sha256.Sum256([]byte(checkout))
	return filepath.Join(c.root, hex.EncodeToString(sum[:16]))
}

// lockPoll is how often a start or a stop that finds the checkout's lock held
// tries it again.
const lockPoll = 200 * time.Millisecond

// lock takes the checkout's lock, waiting while another start or stop holds
// it, and returns its release. A start holds it from its first read of the
// record to its report, and a stop from its first read to its last removal,
// so two starts that find a copy that died run one copy in its place, two that
// publish a running copy run one publish command, and a stop ends the copy a
// start left. The call that holds it ends within its own waits.
//
// The lock is an flock(2) of a file beside the record directory, outside what
// a start removes when it replaces a copy that died, and the kernel releases it
// when its holder ends, so a start cut off partway holds up no later one. Go
// opens the file close-on-exec, and the host passes a process it starts only
// its output, so the copy's leader never holds it. The release removes the
// file once the checkout has no record, and a call that took the lock on a
// file removed meanwhile takes the file that replaced it.
func (c *Copies) lock(checkout string) (func(), error) {
	dir := c.Dir(checkout)
	path := dir + ".lock"
	for {
		f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
		if err != nil {
			return nil, err
		}
		fd := int(f.Fd())
		for {
			err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB)
			if !errors.Is(err, syscall.EWOULDBLOCK) && !errors.Is(err, syscall.EINTR) {
				break
			}
			time.Sleep(lockPoll)
		}
		if err != nil {
			_ = f.Close()
			return nil, err
		}
		held, err := f.Stat()
		if err != nil {
			_ = f.Close()
			return nil, err
		}
		now, err := os.Stat(path)
		if err == nil && os.SameFile(held, now) {
			return func() {
				if _, err := os.Stat(dir); errors.Is(err, fs.ErrNotExist) {
					_ = os.Remove(path)
				}
				_ = syscall.Flock(fd, syscall.LOCK_UN)
				_ = f.Close()
			}, nil
		}
		_ = f.Close()
		if err != nil && !errors.Is(err, fs.ErrNotExist) {
			return nil, err
		}
	}
}

// copyRec is one copy's record directory, a file per value, and the host the
// copy runs on.
type copyRec struct {
	dir string
	h   host.Host
}

func (c *Copies) rec(checkout string) copyRec { return copyRec{dir: c.Dir(checkout), h: c.h} }

func (r copyRec) path(name string) string { return filepath.Join(r.dir, name) }

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

// --- the record --------------------------------------------------------------

// alive reports whether the copy's leader runs and is the process its record
// names: a process that started later under a pid the kernel reused is not.
func (r copyRec) alive() bool {
	pid, ok := r.num("pid")
	if !ok || r.h.Signal(pid, 0) != nil {
		return false
	}
	p, ok := r.h.Proc(pid)
	if !ok {
		return false
	}
	want := r.read("start_id")
	return want == "" || p.Started == "" || p.Started == want
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
	p, ok := r.h.Proc(pid)
	return ok && p.Parent == leader
}

// ready reports whether the copy answers on its port and holds it.
func (r copyRec) ready() (bool, string) {
	port, ok := r.num("port")
	pid, okp := r.num("pid")
	if !ok || !okp {
		return false, "its record names no port or no leader"
	}
	if !r.h.Answers(port) {
		return false, fmt.Sprintf("nothing answers on port %d", port)
	}
	return r.owned(port, pid)
}

// owned reports whether the copy whose group pgid names holds the port: at
// least one process listens there, and each one a connection to loopback
// reaches is a member of the group. It says why when it does not.
func (r copyRec) owned(port, pgid int) (bool, string) {
	pids, err := r.h.Listeners(port)
	if err != nil {
		return false, err.Error()
	}
	if len(pids) == 0 {
		return false, fmt.Sprintf("nothing listens on port %d", port)
	}
	for _, pid := range pids {
		if p, ok := r.h.Proc(pid); !ok || p.Group != pgid {
			return false, fmt.Sprintf("process %d, which listens on port %d, is not one of the copy's", pid, port)
		}
	}
	return true, ""
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
	_ = r.h.SignalGroup(pid, syscall.SIGTERM)
	deadline := time.Now().Add(StopGrace)
	for !r.h.GroupGone(pid) && time.Now().Before(deadline) {
		time.Sleep(200 * time.Millisecond)
	}
	if !r.h.GroupGone(pid) {
		_ = r.h.SignalGroup(pid, syscall.SIGKILL)
		for i := 0; i < 10 && !r.h.GroupGone(pid); i++ {
			time.Sleep(200 * time.Millisecond)
		}
	}
	return r.h.GroupGone(pid)
}

// addressFor fills the address pattern with the port.
func addressFor(pattern string, port int) string {
	p := strconv.Itoa(port)
	return strings.ReplaceAll(strings.ReplaceAll(pattern, "${PORT}", p), "$PORT", p)
}

// --- start, check and stop ---------------------------------------------------

// leaderArgv is the command that runs a copy's leader over its record: this
// binary, as `gctk rig serve --lead <record>`.
func leaderArgv(dir string) ([]string, error) {
	exe, err := os.Executable()
	if err != nil {
		return nil, err
	}
	return []string{exe, "rig", "serve", "--lead", dir}, nil
}

// Serve starts a copy of the checkout whose top is checkout, or reports the
// copy of it that runs. A checkout has at most one copy, so a start for one
// whose copy runs starts no other, and a start after a session wakes is safe to
// repeat. The report of a start that ran the copy says so, in Started. A start
// whose command differs from the running copy's fails and leaves that copy
// running, and so does one that asks for an address while the copy's publish
// command runs, with another publish command or address pattern. A start
// reports a copy once it answers on its port and holds it, and stops a copy of
// its command that does not within the wait, whether it ran the copy or found
// it. A start holds the checkout's lock throughout, so one that finds another
// start or a stop of the checkout under way waits for it to end first.
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
	unlock, err := c.lock(checkout)
	if err != nil {
		return failed("no-state", fmt.Sprintf("the lock on the copy's record %s could not be taken: %v", c.Dir(checkout), err))
	}
	defer unlock()
	rec := c.rec(checkout)
	for claims := 0; ; claims++ {
		if err := os.Mkdir(rec.dir, 0o755); err == nil {
			break
		}
		if claims >= tries {
			return failed("no-state", fmt.Sprintf("the record %s could neither be claimed nor read", rec.dir))
		}
		// A record that holds no leader yet is one whose start ended before its
		// leader recorded its pid: the leader may still record it, or never will.
		if !rec.awaitLeader(30*time.Second) || !rec.alive() {
			_ = os.RemoveAll(rec.dir)
			continue
		}
		// A copy that runs another serve command shows another app, such as the
		// board with other fixture flags, so this start neither reports it nor
		// stops it.
		if running := rec.read("command"); running != o.Command {
			return failed("other-command", fmt.Sprintf("a copy of this checkout already runs another serve command (%s); stop it with gctk rig serve --stop, or serve from another checkout", running))
		}
		// The checkout's copy runs. It is reported once it answers, published
		// first when an address is asked for. The start that ran it may have
		// been cut off before its wait ended, so this start's wait decides, as a
		// new copy's does.
		if o.Publish {
			// A copy whose publish command runs is reported at the address its
			// record holds for that command. A start that asks for another
			// publish command or address pattern, an empty one included, would
			// record an address no publish command gives, so it is decided
			// before the record changes: it fails, and leaves the copy and its
			// publish command running, as a start with another serve command
			// does.
			if rec.publisherAlive() {
				if rec.read("publish_command") != o.PublishCommand || rec.read("address_pattern") != o.AddressPattern {
					return failed("other-publisher", fmt.Sprintf("a copy of this checkout is already published at %s, by another publish command or address pattern (%s); stop it with gctk rig serve --stop and start it again to publish it with these", rec.read("address"), rec.read("publish_command")))
				}
			} else {
				if reason, detail := rec.ask(o); reason != "" {
					return failed(reason, detail)
				}
				if port, ok := rec.num("port"); ok {
					if err := rec.write("address", addressFor(o.AddressPattern, port)); err != nil {
						return failed("no-state", fmt.Sprintf("the record %s could not be written: %v", rec.dir, err))
					}
				}
				if o.PublishCommand != "" && o.AddressPattern != "" && rec.publish() == publishTaken {
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
			_ = os.RemoveAll(rec.dir)
			return failed("no-state", fmt.Sprintf("the record %s could not be written: %v", rec.dir, err))
		}
	}
	if o.Publish {
		if reason, detail := rec.ask(o); reason != "" {
			_ = os.RemoveAll(rec.dir)
			return failed(reason, detail)
		}
	}
	rep := c.launch(rec, checkout, o)
	rep.Started = rep.State == CopyRunning
	return rep
}

// ask records that a start asks for an address, with the publish command and
// the address pattern it passes, which the leader's next publish runs. It says
// why when the record could not be written.
func (r copyRec) ask(o ServeOpts) (string, string) {
	for _, kv := range [][2]string{{"asked", ""}, {"publish_command", o.PublishCommand}, {"address_pattern", o.AddressPattern}} {
		if err := r.write(kv[0], kv[1]); err != nil {
			return "no-state", fmt.Sprintf("the record %s could not be written: %v", r.dir, err)
		}
	}
	return "", ""
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
		if !ok || r.h.Signal(pid, syscall.SIGUSR1) != nil {
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
		_ = os.RemoveAll(rec.dir)
		return Report{State: CopyFailed, Reason: reason, Checkout: checkout, Detail: detail}
	}
	publishable := rec.has("asked") && rec.read("publish_command") != "" && rec.read("address_pattern") != ""
	for try := 1; try <= tries; try++ {
		port, err := c.h.FreePort()
		if err != nil {
			return failed("no-free-port", fmt.Sprintf("no free loopback port could be picked: %v", err))
		}
		rec.remove("pid", "start_id", "publisher", "rc", "serve.log", "publish.log", "address")
		if err := rec.write("port", strconv.Itoa(port)); err != nil {
			return failed("no-state", fmt.Sprintf("the record %s could not be written: %v", rec.dir, err))
		}
		if publishable {
			_ = rec.write("address", addressFor(rec.read("address_pattern"), port))
		}
		if reason, detail := rec.startLeader(); reason != "" {
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
func (r copyRec) startLeader() (string, string) {
	argv, err := leaderArgv(r.dir)
	if err != nil {
		return "not-started", fmt.Sprintf("the copy's leader could not be named: %v", err)
	}
	logf, err := os.OpenFile(r.path("serve.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return "no-state", fmt.Sprintf("the copy's log could not be opened: %v", err)
	}
	defer logf.Close()
	leader, err := r.h.Start(host.Spec{Argv: argv, Out: logf, Session: true})
	if err != nil {
		return "not-started", fmt.Sprintf("the copy's leader did not start: %v", err)
	}
	// The leader is this process's child until this process exits, so one
	// that ends while a start waits is reaped here, and reads as gone.
	go leader.Wait()
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
			_ = os.RemoveAll(r.dir)
			return rep
		}
		if !time.Now().Before(deadline) {
			r.stopGroup()
			rep := Report{State: CopyFailed, Reason: "not-answering", Checkout: checkout,
				Detail: fmt.Sprintf("the copy did not answer on port %d within %s (%s), so it was stopped", port, wait, why),
				Tail:   tail(r.path("serve.log"), 20)}
			_ = os.RemoveAll(r.dir)
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
	rec := c.rec(checkout)
	if _, err := os.Stat(rec.dir); err != nil {
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

// Stop ends the checkout's copy and its record. It holds the checkout's lock
// throughout, so one that finds a start of the checkout under way waits for it
// to end, and then ends the copy that start left.
func (c *Copies) Stop(checkout string) Report {
	rec := c.rec(checkout)
	if _, err := os.Stat(c.root); err != nil {
		return Report{State: CopyNone, Checkout: checkout}
	}
	unlock, err := c.lock(checkout)
	if err != nil {
		if !rec.alive() {
			return Report{State: CopyNone, Checkout: checkout}
		}
		return Report{State: CopyRunning, Checkout: checkout,
			Detail: fmt.Sprintf("the lock on the copy's record could not be taken, so the copy was not stopped: %v", err)}
	}
	defer unlock()
	if _, err := os.Stat(rec.dir); err != nil {
		return Report{State: CopyNone, Checkout: checkout}
	}
	if !rec.alive() {
		_ = os.RemoveAll(rec.dir)
		return Report{State: CopyNone, Checkout: checkout}
	}
	if rec.stopGroup() {
		_ = os.RemoveAll(rec.dir)
		return Report{State: CopyStopped, Checkout: checkout}
	}
	return Report{State: CopyRunning, Checkout: checkout, Detail: "the copy's process group survived SIGTERM and SIGKILL"}
}

// --- the leader --------------------------------------------------------------

// Lead runs the copy whose record is dir, on h, the host as the leader sees
// it: the serve command, inside the sandbox, and the publish command each time
// the leader gets SIGUSR1. It ends the copy's whole process group when the
// serve command ends or a signal ends the leader, and returns the code the
// leader exits with. It sets its signals up before it records its pid, so a
// signal start sends once it reads the pid reaches it.
func Lead(h host.Host, dir string) int {
	rec := copyRec{dir: dir, h: h}
	sigs := make(chan os.Signal, 8)
	h.Notify(sigs, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP, syscall.SIGUSR1)
	me := h.Pid()
	grace := StopGrace
	if ms, ok := rec.num("grace_ms"); ok {
		grace = time.Duration(ms) * time.Millisecond
	}
	// relayed closes once the serve command's output is all in the log.
	var relayed <-chan struct{}
	end := func(code int) int {
		h.Ignore(syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP, syscall.SIGUSR1)
		_ = h.SignalGroup(me, syscall.SIGTERM)
		deadline := time.Now().Add(grace)
		for len(rec.others(me)) > 0 && time.Now().Before(deadline) {
			time.Sleep(200 * time.Millisecond)
		}
		if len(rec.others(me)) > 0 {
			// The KILL ends the leader with the group, so the leader never ends
			// while a member runs.
			_ = h.SignalGroup(me, syscall.SIGKILL)
		}
		// The group has ended, so the relay has no writer left, and the copy of
		// its output finishes at once.
		select {
		case <-relayed:
		case <-time.After(time.Second):
		}
		return code
	}
	port, ok := rec.num("port")
	checkout := rec.read("checkout")
	if !ok || checkout == "" {
		return end(1)
	}
	started := ""
	if p, ok := h.Proc(me); ok {
		started = p.Started
	}
	_ = rec.write("start_id", started)
	if err := rec.write("pid", strconv.Itoa(me)); err != nil {
		return end(1)
	}

	logf, err := os.OpenFile(rec.path("serve.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return end(1)
	}
	defer logf.Close()
	// The serve command writes through a relay the leader copies into the
	// log, so the sandbox never has to grant a write to the record. A serve
	// command whose leader is gone dies at its next write.
	serve, err := h.Start(host.Spec{
		Argv:    []string{"bash", "-c", rec.read("command")},
		Dir:     checkout,
		Env:     []string{"PORT=" + strconv.Itoa(port)},
		Out:     logf,
		Relay:   true,
		Sandbox: &host.Sandbox{Lib: filepath.Join(rec.read("scripts"), SandboxLib), Port: port, Prog: "gctk rig serve"},
	})
	if err != nil {
		fmt.Fprintf(logf, "gctk rig serve: the serve command did not start: %v\n", err)
		_ = rec.write("rc", "127")
		return end(127)
	}
	relayed = serve.Relayed()
	done := make(chan int, 1)
	go func() { done <- serve.Wait() }()

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

// others lists the members of the leader's group other than the leader.
func (r copyRec) others(leader int) []int {
	var pids []int
	for _, p := range r.h.Members(leader) {
		if p != leader {
			pids = append(pids, p)
		}
	}
	return pids
}

// leadPublish runs the publish command for the copy's port, in the copy's
// group, and records which run it is and its pid.
func leadPublish(rec copyRec, port, gen int) {
	logf, err := os.Create(rec.path("publish.log"))
	if err != nil {
		return
	}
	defer logf.Close()
	pub, err := rec.h.Start(host.Spec{
		Argv: []string{"bash", "-c", rec.read("publish_command")},
		Dir:  rec.read("checkout"),
		Env:  []string{"PORT=" + strconv.Itoa(port)},
		Out:  logf,
	})
	if err != nil {
		fmt.Fprintf(logf, "gctk rig serve: the publish command did not start: %v\n", err)
		_ = rec.write("publisher", fmt.Sprintf("%d 0", gen))
		return
	}
	_ = rec.write("publisher", fmt.Sprintf("%d %d", gen, pub.Pid()))
	go pub.Wait()
}
