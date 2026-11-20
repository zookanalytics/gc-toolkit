package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// A Call is one run of the fake: the name it ran under, its arguments after
// that name, its environment, and its standard streams.
type Call struct {
	// Name is the program's name. A call made as bd answers as `gc bd` does.
	Name   string
	Args   []string
	Env    []string
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer

	// Stall holds the call for d with SIGTERM ignored, as a stalled gc
	// command holds its lock. With none set, the process ignores SIGTERM and
	// sleeps.
	Stall func(d time.Duration)

	// home is the store the call acts in, once route has picked it.
	home store
}

// getenv is the value of name in the call's environment, the last one when
// it is set twice, as a process reads it.
func (c *Call) getenv(name string) string {
	v := ""
	for _, kv := range c.Env {
		if k, val, ok := strings.Cut(kv, "="); ok && k == name {
			v = val
		}
	}
	return v
}

// exit is an early end of a call with a status, after its message has been
// written.
type exit int

func (e exit) Error() string { return "exit " + strconv.Itoa(int(e)) }

// Run answers one call and returns its exit status.
func Run(c *Call) (status int) {
	if c.Stdin == nil {
		c.Stdin = strings.NewReader("")
	}
	err := run(c)
	var e exit
	var se *storeError
	switch {
	case err == nil:
		return 0
	case errors.As(err, &e):
		return int(e)
	case errors.As(err, &se):
		fmt.Fprintln(c.Stderr, se.Error())
		return exitStore
	default:
		fmt.Fprintln(c.Stderr, "fake gc:", err)
		return 1
	}
}

// fail writes msg to the call's stderr and ends it with status.
func (c *Call) fail(status int, msg string) error {
	fmt.Fprintln(c.Stderr, msg)
	return exit(status)
}

func (c *Call) out(s string) { _, _ = io.WriteString(c.Stdout, s) }

// required is a setting the harness always exports, read the way the stub's
// ${NAME:?} reads it.
func (c *Call) required(name string) (string, error) {
	v := c.getenv(name)
	if v == "" {
		return "", c.fail(127, "fake gc: "+name+": parameter null or not set")
	}
	return v, nil
}

func run(c *Call) error {
	if len(c.Args) > 0 && c.Args[0] == readFlag {
		return harnessRead(c, c.Args[1:])
	}
	if len(c.Args) > 0 && c.Args[0] == writeFlag {
		return harnessWrite(c, c.Args[1:])
	}
	asBd := c.Name == "bd"
	if asBd {
		c.Args = append([]string{"bd"}, c.Args...)
	}
	s, err := c.required("STUB_STORE")
	if err != nil {
		return err
	}
	d, err := c.required("STUB_DEPS")
	if err != nil {
		return err
	}
	logPath, err := c.required("STUB_GC_LOG")
	if err != nil {
		return err
	}
	if err := appendFile(logPath, strings.Join(c.Args, " ")+"\n"); err != nil {
		return err
	}
	if !asBd && c.getenv("STUB_GC_FAIL") != "" {
		return c.fail(1, "gc: simulated failure of every gc call")
	}
	if c.carries("STUB_FAIL_ON") {
		return c.fail(1, "gc: simulated failure of a call that carries '"+c.getenv("STUB_FAIL_ON")+"'")
	}
	if err := c.hook(); err != nil {
		return err
	}
	sub, args := shift(c.Args)
	switch sub {
	case "agent":
		if first(args) == "list" {
			return c.catOr(c.getenv("STUB_AGENTS"), `{"agents":[]}`)
		}
		return nil
	case "rig":
		if first(args) == "list" {
			if c.getenv("STUB_RIGS") == "" {
				c.out(`{"rigs":[]}` + "\n")
				return nil
			}
			return c.catOr(c.getenv("STUB_RIGS"), `{"rigs":[]}`)
		}
	case "config":
		if first(args) == "show" {
			if c.getenv("STUB_CONFIG") == "" {
				c.out(noConfig + "\n")
				return nil
			}
			return c.catOr(c.getenv("STUB_CONFIG"), noConfig)
		}
	case "convoy":
		if first(args) == "list" {
			return c.catOr(c.getenv("STUB_CONVOYS"), `{"convoys":[]}`)
		}
		return nil
	case "order":
		if first(args) == "list" {
			return c.catOr(c.getenv("STUB_ORDERS"), `{"orders":[]}`)
		}
	case "hook":
		if first(args) == "current" {
			return c.hookCurrent(args[1:])
		}
	case "runtime":
		if first(args) == "drain-ack" {
			return nil
		}
	case "session":
		return c.session(args)
	case "mail":
		return nil
	case "workflow":
		sid := ""
		if len(args) > 1 {
			sid = args[1]
		}
		st := c.route(c.defaultStore(s, d), "", "", sid)
		c.use(st)
		return c.workflow(st.beads, args)
	case "sling":
		rigName, bead := slingTarget(args)
		st := c.route(c.defaultStore(s, d), "", rigName, bead)
		c.use(st)
		return c.sling(st.beads, args)
	case "bd":
		return c.bd(s, d, args)
	}
	if sub == "gc-toolkit" && first(args) == "scripts-dir" && c.getenv("STUB_PACK") != "" {
		c.out(c.getenv("STUB_PACK") + "/assets/scripts\n")
		return nil
	}
	return c.fail(2, "gc stub: unsupported '"+sub+"'")
}

// hook runs the program STUB_HOOK names before the fake answers a call whose
// arguments carry the text STUB_HOOK_AT names, so a test can land another
// writer's change between two of a script's calls, or fail a call the n-th
// time it is made. The program gets the call's arguments as its own, and an
// environment without either setting, so its own gc calls do not run it
// again. Its output goes to the call's stderr. The call goes on when it exits
// 0, and otherwise fails with its exit status and answers nothing.
func (c *Call) hook() error {
	at, prog := c.getenv("STUB_HOOK_AT"), c.getenv("STUB_HOOK")
	if at == "" || prog == "" || !strings.Contains(strings.Join(c.Args, " "), at) {
		return nil
	}
	env, stdin := c.Env, c.Stdin
	c.Env, c.Stdin = withEnv(env, "STUB_HOOK_AT=", "STUB_HOOK="), strings.NewReader("")
	status, err := c.spawn(c.Stderr, append([]string{prog}, c.Args...)...)
	c.Env, c.Stdin = env, stdin
	if err != nil {
		return c.fail(status, "fake gc: the hook "+prog+": "+err.Error())
	}
	if status != 0 {
		return exit(status)
	}
	return nil
}

// noConfig is `gc config show --json` for a city whose config names no agent.
const noConfig = `{"ok":true,"config":{"Agents":[]}}`

// afterWrite runs the program STUB_AFTER_WRITE names once a bd call that writes
// the store has landed, so a test can run another process, such as the
// deferred-dispatch order's pass, at each moment a script's write leaves. The
// program gets the call's arguments as its own, and an environment without the
// setting, so its own writes do not run it again. Its output goes to the call's
// stderr. The write has landed, so the program's exit status leaves the call's
// as it is, and only a program that does not start fails the call.
func (c *Call) afterWrite() error {
	prog := c.getenv("STUB_AFTER_WRITE")
	if prog == "" {
		return nil
	}
	env, stdin := c.Env, c.Stdin
	c.Env, c.Stdin = withEnv(env, "STUB_AFTER_WRITE="), strings.NewReader("")
	status, err := c.spawn(c.Stderr, append([]string{prog}, c.Args...)...)
	c.Env, c.Stdin = env, stdin
	if err != nil {
		return c.fail(status, "fake gc: the program "+prog+" after the write: "+err.Error())
	}
	return nil
}

// made reports whether a call whose arguments carry text is in the call log,
// this call's own line included.
func (c *Call) made(text string) (bool, error) {
	logPath, err := c.required("STUB_GC_LOG")
	if err != nil {
		return false, err
	}
	lines, err := readLines(logPath)
	if err != nil {
		return false, err
	}
	return slices.ContainsFunc(lines, func(l string) bool { return strings.Contains(l, text) }), nil
}

// carries reports whether the setting names a text the call's arguments carry,
// as a fault matched by text reads it.
func (c *Call) carries(setting string) bool {
	on := c.getenv(setting)
	return on != "" && strings.Contains(strings.Join(c.Args, " "), on)
}

func shift(args []string) (string, []string) {
	if len(args) == 0 {
		return "", nil
	}
	return args[0], args[1:]
}

func first(args []string) string {
	if len(args) == 0 {
		return ""
	}
	return args[0]
}

// catOr prints the file a setting names, or when that names none, nothing;
// when the file cannot be read it prints fallback.
func (c *Call) catOr(path, fallback string) error {
	if path == "" {
		return nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		c.out(fallback + "\n")
		return nil
	}
	c.out(string(data))
	return nil
}

// status is a STUB_*_RC value as the stub's exit reads it.
func (c *Call) status(v string) error {
	n, err := strconv.Atoi(v)
	if err != nil {
		return c.fail(2, "fake gc: exit: "+v+": numeric argument required")
	}
	return exit(n & 0xff)
}

func (c *Call) session(args []string) error {
	logPath, err := c.required("STUB_SESSION_LOG")
	if err != nil {
		return err
	}
	if err := appendFile(logPath, "gc session "+strings.Join(args, " ")+"\n"); err != nil {
		return err
	}
	if first(args) != "list" {
		return nil
	}
	if rc := c.getenv("STUB_SESSION_LIST_RC"); rc != "" {
		fmt.Fprintln(c.Stderr, "gc: simulated session list failure")
		return c.status(rc)
	}
	if path := c.getenv("STUB_SESSIONS"); path != "" {
		if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() {
			data, err := os.ReadFile(path)
			if err != nil {
				return &storeError{path, err}
			}
			c.out(string(data))
		}
	}
	return nil
}

// hookCurrent answers `gc hook current`: the bead STUB_HOOK_CURRENT names, which
// stands for the claim gc stamps on the calling session's bead. As gc does, it
// exits 1 for a call with no session identity and for a session that has
// claimed nothing.
func (c *Call) hookCurrent(args []string) error {
	sid := strings.TrimSpace(c.getenv("GC_SESSION_ID"))
	if sid == "" {
		return c.fail(1, "gc hook current: no session identity (set $GC_SESSION_ID); only a session that claimed work has a current bead")
	}
	id := strings.TrimSpace(c.getenv("STUB_HOOK_CURRENT"))
	if id == "" {
		return c.fail(1, "gc hook current: session "+sid+" has no current claim (nothing claimed through gc hook --claim)")
	}
	if contains(args, "--id-only") {
		c.out(id + "\n")
		return nil
	}
	c.out(id + " (claimed by session " + sid + ")\n")
	return nil
}

// stall holds the call for the seconds a STUB_*_HANG or _STALL setting names.
func (c *Call) stall(secs string) {
	f, err := strconv.ParseFloat(secs, 64)
	if err != nil || f <= 0 {
		return
	}
	d := time.Duration(f * float64(time.Second))
	if c.Stall != nil {
		c.Stall(d)
		return
	}
	signal.Ignore(syscall.SIGTERM)
	time.Sleep(d)
}

func (c *Call) workflow(s string, args []string) error {
	verb := first(args)
	sid := ""
	if len(args) > 1 {
		sid = args[1]
	}
	switch verb {
	case "delete-source":
		if rc := c.getenv("STUB_DELETE_SOURCE_RC"); rc != "" {
			fmt.Fprintln(c.Stderr, "gc: simulated delete-source failure")
			return c.status(rc)
		}
		line := c.getenv("STUB_DELETE_SOURCE_OUT")
		if line == "" {
			line = "result=already_clean source_bead_id=" + sid + " matched_roots=0 matched_beads=0 closed=0 deleted=0 metadata_cleared=false"
		}
		c.out(line + "\n")
		if hang := c.getenv("STUB_DELETE_SOURCE_HANG"); hang != "" {
			c.stall(hang)
		}
		return nil
	case "reopen-source":
		if rc := c.getenv("STUB_REOPEN_SOURCE_RC"); rc != "" {
			fmt.Fprintln(c.Stderr, "gc: simulated reopen-source failure")
			return c.status(rc)
		}
		if st := c.getenv("STUB_REOPEN_SOURCE_STALL"); st != "" {
			c.stall(st)
		}
		err := c.rewrite(s, func(rows []*Object) error {
			for _, o := range rows {
				if !idIs(o, sid) {
					continue
				}
				for _, k := range []string{"workflow_id", "gc.session_affinity", "gc.continuation_group"} {
					if err := delMetadata(o, k); err != nil {
						return err
					}
				}
				o.Set("status", "open")
				o.Set("assignee", "")
			}
			return nil
		})
		if err != nil {
			return err
		}
		c.out("result=reopened source_bead_id=" + sid + "\n")
		if hang := c.getenv("STUB_REOPEN_SOURCE_HANG"); hang != "" {
			c.stall(hang)
		}
		return nil
	}
	return c.fail(2, "gc stub: unsupported 'workflow "+verb+"'")
}

// dropsFor is the keys STUB_DROP_KEYS names for id: its pairs are
// "<id>:<key>,<key>", split at blanks, and the last pair that names id wins.
func (c *Call) dropsFor(id string) []string {
	drops := ""
	for _, pair := range strings.Fields(c.getenv("STUB_DROP_KEYS")) {
		if strings.HasPrefix(pair, id+":") {
			_, drops, _ = strings.Cut(pair, ":")
		}
	}
	if drops == "" {
		return nil
	}
	return strings.Split(drops, ",")
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func (c *Call) sling(s string, args []string) error {
	if c.getenv("STUB_SLING_FAIL") != "" {
		return c.fail(1, "gc: simulated sling failure")
	}
	if contains(args, "--no-formula") {
		target, bead := first(args), ""
		if len(args) > 1 {
			bead = args[1]
		}
		if target == "" {
			return c.fail(1, `gc sling: agent "" not found in city.toml`)
		}
		if bead == "" {
			return nil
		}
		route := !contains(c.dropsFor(bead), "gc.routed_to")
		return c.rewrite(s, func(rows []*Object) error {
			for _, o := range rows {
				if !idIs(o, bead) {
					continue
				}
				m, err := metadataOf(o)
				if err != nil {
					return err
				}
				if route {
					if m, err = metadataFor(o); err != nil {
						return err
					}
					m.Set("gc.routed_to", target)
				}
				exec, root := get(m, "gc.execution_routed_to"), get(m, "gc.root_bead_id")
				if Truthy(exec) && notEmpty(exec) && !(Truthy(root) && notEmpty(root)) {
					m.Set("gc.execution_routed_to", "")
				}
			}
			return nil
		})
	}
	target, bead := "", ""
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--rig" || a == "--on":
			i++
		case strings.HasPrefix(a, "--"):
		case target == "":
			target = a
		case bead == "":
			bead = a
		}
	}
	if bead == "" {
		return nil
	}
	stamp := !contains(c.dropsFor(bead), "gc.execution_routed_to")
	return c.rewrite(s, func(rows []*Object) error {
		for _, o := range rows {
			if !idIs(o, bead) {
				continue
			}
			if err := delMetadata(o, "gc.routed_to"); err != nil {
				return err
			}
			if stamp {
				m, err := metadataFor(o)
				if err != nil {
					return err
				}
				m.Set("gc.execution_routed_to", target)
			}
			o.Set("poured_priority", orDefault(get(o, "priority"), Number("2")))
		}
		return nil
	})
}

// notEmpty is jq's `(x // "") != ""` once x is known to be truthy.
func notEmpty(v Value) bool {
	s, ok := v.(string)
	return !ok || s != ""
}

// get is jq's .[k] on an object, and null for a key it does not hold.
func get(o *Object, k string) Value {
	if o == nil {
		return nil
	}
	v, _ := o.Get(k)
	return v
}

// idIs is jq's `.id == $id` for a string id.
func idIs(o *Object, id string) bool {
	v, _ := o.Get("id")
	s, ok := v.(string)
	return ok && s == id
}

// orDefault is jq's `x // d`.
func orDefault(v, d Value) Value {
	if Truthy(v) {
		return v
	}
	return d
}

// metadataOf is the row's metadata object for a read, nil for a missing or
// null one, and an error for one jq cannot index.
func metadataOf(o *Object) (*Object, error) {
	switch t := get(o, "metadata").(type) {
	case *Object:
		return t, nil
	case nil:
		return nil, nil
	default:
		return nil, fmt.Errorf("cannot index %s with a string", jqType(t))
	}
}

// metadataFor is the row's metadata object as jq's `.metadata[$k] = v` reaches
// it: a missing or null metadata becomes an empty object first.
func metadataFor(o *Object) (*Object, error) {
	m, _ := o.Get("metadata")
	switch t := m.(type) {
	case *Object:
		return t, nil
	case nil:
		n := NewObject()
		o.Set("metadata", n)
		return n, nil
	}
	return nil, fmt.Errorf("cannot index %s with a string", jqType(m))
}

// delMetadata is jq's `.metadata |= del(.[$k])`, which leaves a null
// metadata in place of a missing one.
func delMetadata(o *Object, k string) error {
	m, _ := o.Get("metadata")
	switch t := m.(type) {
	case *Object:
		t.Del(k)
	case nil:
		o.Set("metadata", nil)
	default:
		return fmt.Errorf("cannot delete fields from %s", jqType(m))
	}
	return nil
}

func jqType(v Value) string {
	switch v.(type) {
	case nil:
		return "null"
	case bool:
		return "boolean"
	case Number:
		return "number"
	case string:
		return "string"
	case []Value:
		return "array"
	}
	return "object"
}

// rewrite applies f to the store's rows and writes them back, holding the
// store's lock from the read to the write. An error from f writes nothing.
func (c *Call) rewrite(s string, f func(rows []*Object) error) error {
	release, err := lockDir(s)
	if err != nil {
		return err
	}
	defer release()
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	if err := f(rows); err != nil {
		return err
	}
	return writeRows(s, rows)
}

// spawn runs argv as a child with the call's environment and streams, finding
// a bare program name on the call's PATH, and returns its exit status.
func (c *Call) spawn(stdout io.Writer, argv ...string) (int, error) {
	path := argv[0]
	if !strings.Contains(path, "/") {
		found, err := lookPath(path, c.getenv("PATH"))
		if err != nil {
			return 127, err
		}
		path = found
	}
	cmd := exec.Command(path, argv[1:]...)
	cmd.Args[0] = argv[0]
	cmd.Env, cmd.Stdin, cmd.Stderr = c.Env, c.Stdin, c.Stderr
	if stdout != io.Discard {
		cmd.Stdout = stdout
	}
	err := cmd.Run()
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		if ws, ok := ee.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
			return 128 + int(ws.Signal()), nil
		}
		return ee.ExitCode(), nil
	}
	if err != nil {
		return 126, err
	}
	return 0, nil
}

// lookPath finds name on pathEnv as a shell finds a command.
func lookPath(name, pathEnv string) (string, error) {
	for _, dir := range filepath.SplitList(pathEnv) {
		if dir == "" {
			dir = "."
		}
		p := filepath.Join(dir, name)
		if info, err := os.Stat(p); err == nil && info.Mode().IsRegular() && info.Mode()&0o111 != 0 {
			return p, nil
		}
	}
	return "", fmt.Errorf("%s: command not found", name)
}
