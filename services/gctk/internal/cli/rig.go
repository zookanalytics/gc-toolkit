package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/rig"
)

// `gctk rig` is the one gate that runs a rig's declared check commands and
// keeps the record of their results. A rig declares its commands as formula
// vars under [rigs.formula_vars] in city.toml, and the gate reads them when it
// runs, so a value changed after a molecule was poured is the value that runs.
//
// test, lint and typecheck are properties of a commit. Each run is recorded
// against the commit it ran at (internal/rig), and a recorded result answers
// for that commit without running again: a pass passes and a fail fails. A
// full-suite test pass also answers for any commit with the same tree. --force
// runs regardless, and --check only reports. setup and build record nothing:
// setup leaves environment state behind, and a build makes itself current.
//
// The gate's own lines go to stderr; the command's output passes through
// untouched. --check prints the record it found on stdout as one JSON line.

const rigUsage = `usage:
  gctk rig test [--affected [--base <branch>]] [--check | --force | --pre-existing <tracker>]
                [--publish-bead <id>] [--rig <rig>] [--timeout <duration>]
  gctk rig lint|typecheck [--check | --force | --pre-existing <tracker>]
                [--publish-bead <id>] [--rig <rig>] [--timeout <duration>]
  gctk rig setup|build [--rig <rig>] [--timeout <duration>]

Runs the rig's declared check command in the checkout the current directory
sits in, and records the result against HEAD. A recorded result answers for
HEAD without running again.

  --affected         run affected_tests_command, or test_command when that is
                     empty or the diff against origin/<base> names no file
  --base <branch>    the base the affected diff is taken against; default: the
                     rig's base_branch, else the branch origin/HEAD names
  --check            report the recorded result and run nothing
  --force            run even when a result is recorded, and record the new one
  --pre-existing <tracker>
                     mark the fail recorded at HEAD as red on the base too,
                     carried by the tracker bead
  --publish-bead <id>  copy the result onto the bead's rig_check.<check> key
  --rig <rig>        the rig whose vars to read; default: $GC_RIG
  --timeout <duration>  stop a run still going after this long; 0 never
                     (default 2h)

exit: 0 pass · 1 fail · 2 usage · 3 nothing recorded (--check, --pre-existing)
      4 machine failure, nothing recorded · 128+N stopped by signal N
`

// The gate's exit codes. A machine failure is any outcome the gate does not
// record as the code's result: a dirty tree, a command that could not run, a
// timeout, a kill, vars that could not be read, a result the record store did
// not take.
const (
	rigExitPass    = 0
	rigExitFail    = 1
	rigExitUsage   = 2
	rigExitNone    = 3
	rigExitMachine = 4
)

// rigDefaultTimeout bounds a run when the caller names no bound. The refinery
// stops its own gate at two hours, and a check still running then has stopped
// answering.
const rigDefaultTimeout = 2 * time.Hour

// rigCheckVar is the var each recorded check runs.
var rigCheckVar = map[string]string{
	rig.CheckTest:      rig.VarTest,
	rig.CheckLint:      rig.VarLint,
	rig.CheckTypecheck: rig.VarTypecheck,
}

type rigOpts struct {
	affected    bool
	check       bool
	force       bool
	preExisting string
	publish     string
	base        string
	rigName     string
	timeout     time.Duration
	// set records which flags were given, for the checks of what goes with
	// what.
	set map[string]bool
}

// Rig dispatches `gctk rig <verb>`, returning a process exit code so the
// surface stays testable in-process.
func Rig(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, rigUsage)
		return rigExitUsage
	}
	verb := args[0]
	switch verb {
	case "-h", "--help", "help":
		fmt.Fprint(stdout, rigUsage)
		return rigExitPass
	case rig.CheckTest, rig.CheckLint, rig.CheckTypecheck, "setup", "build":
	default:
		fmt.Fprintf(stderr, "gctk rig: unknown verb %q\n\n%s", verb, rigUsage)
		return rigExitUsage
	}
	o, msg := parseRigArgs(verb, args[1:])
	if msg != "" {
		fmt.Fprintf(stderr, "gctk rig %s: %s\n\n%s", verb, msg, rigUsage)
		return rigExitUsage
	}
	if verb == "setup" || verb == "build" {
		return rigRunOnly(verb, o, stdout, stderr)
	}
	return rigRecorded(verb, o, stdout, stderr)
}

// parseRigArgs reads verb's flags, or returns why they do not parse.
func parseRigArgs(verb string, args []string) (rigOpts, string) {
	o := rigOpts{timeout: rigDefaultTimeout, set: map[string]bool{}}
	value := func(i int) (string, string) {
		if i+1 >= len(args) {
			return "", "flag " + args[i] + " needs a value"
		}
		return args[i+1], ""
	}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if o.set[a] {
			return o, "flag " + a + " given twice"
		}
		o.set[a] = true
		var v, msg string
		switch a {
		case "--affected":
			o.affected = true
		case "--check":
			o.check = true
		case "--force":
			o.force = true
		case "--pre-existing", "--publish-bead", "--base", "--rig", "--timeout":
			if v, msg = value(i); msg != "" {
				return o, msg
			}
			i++
		default:
			return o, fmt.Sprintf("unknown argument %q", a)
		}
		switch a {
		case "--pre-existing":
			o.preExisting = v
		case "--publish-bead":
			o.publish = v
		case "--base":
			o.base = v
		case "--rig":
			o.rigName = v
		case "--timeout":
			d, err := time.ParseDuration(v)
			if err != nil || d < 0 {
				return o, fmt.Sprintf("--timeout %q is not a duration such as 90m or 2h", v)
			}
			o.timeout = d
		}
		if v == "" && (a == "--pre-existing" || a == "--publish-bead" || a == "--base" || a == "--rig") {
			return o, "flag " + a + " needs a value"
		}
	}
	allowed := map[string]bool{"--rig": true, "--timeout": true}
	if verb != "setup" && verb != "build" {
		for _, f := range []string{"--check", "--force", "--pre-existing", "--publish-bead"} {
			allowed[f] = true
		}
	}
	if verb == rig.CheckTest {
		allowed["--affected"] = true
		allowed["--base"] = true
	}
	for f := range o.set {
		if !allowed[f] {
			return o, fmt.Sprintf("%s does not take %s", verb, f)
		}
	}
	modes := 0
	for _, f := range []string{"--check", "--force", "--pre-existing"} {
		if o.set[f] {
			modes++
		}
	}
	switch {
	case modes > 1:
		return o, "--check, --force and --pre-existing exclude one another"
	case o.check && o.publish != "":
		return o, "--check runs no gc, so it publishes nothing; drop --publish-bead"
	case o.set["--base"] && !o.affected:
		return o, "--base names the base of the affected diff, so it needs --affected"
	}
	return o, ""
}

// rigRecorded runs a check whose result is recorded: test, lint or typecheck.
func rigRecorded(check string, o rigOpts, stdout, stderr io.Writer) int {
	say := func(format string, a ...any) {
		fmt.Fprintf(stderr, "gctk rig %s: %s\n", check, fmt.Sprintf(format, a...))
	}
	machine := func(format string, a ...any) int {
		say("machine failure, nothing recorded: "+format, a...)
		return rigExitMachine
	}
	co, err := git.Open(".")
	if err != nil {
		return machine("%v", err)
	}
	dirty, err := co.Dirty()
	if err != nil {
		return machine("%v", err)
	}
	if dirty != "" {
		return machine("the checkout has changes HEAD does not hold, so no result here certifies %s:\n%s", co.Commit, firstLines(dirty, 10))
	}
	store := rig.NewStore(co.Common)

	if o.preExisting != "" {
		rec, err := store.MarkPreExisting(check, co.Commit, o.preExisting)
		if errors.Is(err, rig.ErrNoFail) {
			say("no fail is recorded at %s, so nothing was marked pre-existing", co.Commit)
			return rigExitNone
		}
		if err != nil {
			return machine("cannot mark the recorded fail: %v", err)
		}
		printRecord(stdout, rec)
		say("the fail recorded at %s is marked pre-existing, carried by %s", co.Commit, o.preExisting)
		rigPublish(check, o.publish, rec, say)
		return rigExitPass
	}

	found, err := store.Lookup(check, co.Commit, co.Tree)
	if err != nil {
		return machine("cannot read the record store %s: %v", store.Root(), err)
	}
	for _, p := range found.Ignored {
		say("WARN %s is not a readable record for this commit and was read as absent", p)
	}

	if o.check {
		if found.Record == nil {
			say("nothing is recorded at %s", co.Commit)
			return rigExitNone
		}
		printRecord(stdout, found.Record)
		say("%s", describeRecord(found, co.Commit))
		return resultExit(found.Record)
	}

	// A record of nothing run is not reused: what to run is cheap to work out
	// again, and the rig may declare a command now.
	if !o.force && found.Record != nil && found.Record.Method != rig.MethodNone {
		say("%s; not run again%s", describeRecord(found, co.Commit), forceHint(found.Record))
		rigPublish(check, o.publish, found.Record, say)
		return resultExit(found.Record)
	}

	rigName, msg := resolveRigName(o, co)
	if msg != "" {
		return machine("%s", msg)
	}
	vars, err := rig.Resolve(rigName)
	if err != nil {
		return machine("cannot read rig %s's check commands: %v", rigName, err)
	}
	command, method, why, msg := selectCommand(check, o, vars, co)
	if msg != "" {
		return machine("%s", msg)
	}

	if command == "" {
		own := found.Record != nil && found.Source == rig.FromCommit
		switch {
		case own && found.Record.Method != rig.MethodNone:
			// A run of nothing never replaces the record of a run, and that
			// record is not this call's answer, so it is not published either.
			say("nothing to run: %s. The record of the last run stands, and nothing was published: %s", why, describeRecord(found, co.Commit))
			return rigExitPass
		case own:
			say("nothing to run: %s. %s", why, describeRecord(found, co.Commit))
			rigPublish(check, o.publish, found.Record, say)
			return rigExitPass
		}
		rec := newRecord(check, rig.ResultPass, rig.MethodNone, co, "", 0, 0)
		if err := store.Put(rec); err != nil {
			say("machine failure: nothing to run (%s), and the record store did not take the pass with method none: %v", why, err)
			return rigExitMachine
		}
		say("nothing to run: %s. Recorded at %s as a pass with method none", why, co.Commit)
		rigPublish(check, o.publish, rec, say)
		return rigExitPass
	}

	if ok, reason := rig.Parses(command); !ok {
		return machine("%s; the command is %s's %q", reason, rigName, command)
	}
	say("running %s (method %s) at %s", command, method, co.Commit)
	out := rig.Run(co.Top, command, o.timeout, stdout, stderr)
	switch out.Kind {
	case rig.Interrupted:
		say("stopped by signal %d (%s); the command's process group was stopped, and nothing was recorded", int(out.Signal), out.Signal)
		return 128 + int(out.Signal)
	case rig.Machine:
		return machine("%s, after %s", out.Reason, out.Duration.Round(time.Millisecond))
	}
	result := rig.ResultPass
	if out.Kind == rig.Failed {
		result = rig.ResultFail
	}
	rec := newRecord(check, result, method, co, command, out.ExitCode, out.Duration)
	if err := store.Put(rec); err != nil {
		say("machine failure: the record store did not take the %s at %s (method %s, exit %d, %s): %v", result, co.Commit, method, out.ExitCode, out.Duration.Round(time.Millisecond), err)
		return rigExitMachine
	}
	say("%s at %s (method %s, exit %d, %s); recorded", result, co.Commit, method, out.ExitCode, out.Duration.Round(time.Millisecond))
	rigPublish(check, o.publish, rec, say)
	return resultExit(rec)
}

// selectCommand picks what a run of check executes, the method it records,
// and, when the command is empty, why there is nothing to run. msg is a
// machine failure.
func selectCommand(check string, o rigOpts, vars rig.Vars, co *git.Checkout) (command, method, why, msg string) {
	full := vars.Value(rigCheckVar[check])
	if check != rig.CheckTest || !o.affected {
		return full, methodOf(full, rig.MethodFull), rigCheckVar[check] + " is not set", ""
	}
	affected := vars.Value(rig.VarAffected)
	if affected == "" {
		return full, methodOf(full, rig.MethodFull), rig.VarAffected + " and " + rig.VarTest + " are not set", ""
	}
	base := o.base
	if base == "" {
		base = rig.DefaultBase(co, vars)
	}
	empty, err := rig.DiffScopeEmpty(co, base)
	if err != nil {
		return "", "", "", fmt.Sprintf("cannot work out the affected subset: %v", err)
	}
	if empty {
		return full, methodOf(full, rig.MethodFull), "the diff against origin/" + base + " names no file and " + rig.VarTest + " is not set", ""
	}
	return affected, rig.MethodAffected, "", ""
}

func methodOf(command, method string) string {
	if command == "" {
		return rig.MethodNone
	}
	return method
}

// resolveRigName is the rig whose vars the gate reads: --rig, else $GC_RIG.
// $GC_RIG and $GC_RIG_ROOT describe one rig, so when both name it the checkout
// must be a worktree of the clone at $GC_RIG_ROOT: one rig's commands are never
// run against another rig's checkout and recorded there.
func resolveRigName(o rigOpts, co *git.Checkout) (string, string) {
	if o.rigName != "" {
		return o.rigName, ""
	}
	name := strings.TrimSpace(os.Getenv("GC_RIG"))
	if name == "" {
		return "", "no rig named: pass --rig <rig>, or run where $GC_RIG names one"
	}
	root := strings.TrimSpace(os.Getenv("GC_RIG_ROOT"))
	if root == "" {
		return name, ""
	}
	clone, err := git.Open(root)
	if err != nil {
		return "", fmt.Sprintf("$GC_RIG_ROOT %s is not a checkout of rig %s, so this checkout cannot be matched to it: %v", root, name, err)
	}
	if !samePath(clone.Common, co.Common) {
		return "", fmt.Sprintf("this checkout belongs to the clone at %s, not to rig %s's clone at %s; pass --rig to name the rig whose commands to run", co.Common, name, clone.Common)
	}
	return name, ""
}

func samePath(a, b string) bool {
	ra, errA := filepath.EvalSymlinks(a)
	rb, errB := filepath.EvalSymlinks(b)
	if errA != nil || errB != nil {
		return filepath.Clean(a) == filepath.Clean(b)
	}
	return ra == rb
}

// rigRunOnly runs setup or build, which record nothing.
func rigRunOnly(verb string, o rigOpts, stdout, stderr io.Writer) int {
	say := func(format string, a ...any) {
		fmt.Fprintf(stderr, "gctk rig %s: %s\n", verb, fmt.Sprintf(format, a...))
	}
	machine := func(format string, a ...any) int {
		say("machine failure: "+format, a...)
		return rigExitMachine
	}
	co, err := git.Open(".")
	if err != nil {
		return machine("%v", err)
	}
	rigName, msg := resolveRigName(o, co)
	if msg != "" {
		return machine("%s", msg)
	}
	vars, err := rig.Resolve(rigName)
	if err != nil {
		return machine("cannot read rig %s's check commands: %v", rigName, err)
	}
	name := rig.VarSetup
	if verb == "build" {
		name = rig.VarBuild
	}
	command := vars.Value(name)
	if command == "" {
		say("nothing to run: %s is not set", name)
		return rigExitPass
	}
	if ok, reason := rig.Parses(command); !ok {
		return machine("%s; the command is %s's %q", reason, rigName, command)
	}
	say("running %s", command)
	out := rig.Run(co.Top, command, o.timeout, stdout, stderr)
	switch out.Kind {
	case rig.Interrupted:
		say("stopped by signal %d (%s); the command's process group was stopped", int(out.Signal), out.Signal)
		return 128 + int(out.Signal)
	case rig.Machine:
		return machine("%s, after %s", out.Reason, out.Duration.Round(time.Millisecond))
	case rig.Failed:
		say("fail (exit %d, %s)", out.ExitCode, out.Duration.Round(time.Millisecond))
		return rigExitFail
	}
	say("pass (%s)", out.Duration.Round(time.Millisecond))
	return rigExitPass
}

func newRecord(check, result, method string, co *git.Checkout, command string, exit int, d time.Duration) *rig.Record {
	return &rig.Record{
		Check:      check,
		Result:     result,
		Method:     method,
		Commit:     co.Commit,
		Tree:       co.Tree,
		ExitCode:   exit,
		DurationMS: d.Milliseconds(),
		Runner:     rig.Runner(),
		RecordedAt: time.Now().UTC().Format(time.RFC3339),
		Command:    command,
	}
}

func resultExit(rec *rig.Record) int {
	if rec.Result == rig.ResultPass {
		return rigExitPass
	}
	return rigExitFail
}

// describeRecord says what a found record holds, for the gate's own lines.
func describeRecord(f rig.Found, commit string) string {
	r := f.Record
	var b strings.Builder
	fmt.Fprintf(&b, "%s recorded at %s", r.Result, r.Commit)
	if f.Source == rig.FromTree {
		fmt.Fprintf(&b, ", whose tree %s is HEAD's (%s)", r.Tree, commit)
	}
	fmt.Fprintf(&b, " (method %s", r.Method)
	if r.Result == rig.ResultFail {
		fmt.Fprintf(&b, ", exit %d", r.ExitCode)
	}
	if r.Disposition != "" {
		fmt.Fprintf(&b, ", %s, carried by %s", r.Disposition, r.Tracker)
	}
	fmt.Fprintf(&b, ", %s, by %s at %s)", (time.Duration(r.DurationMS) * time.Millisecond).Round(time.Millisecond), r.Runner, r.RecordedAt)
	return b.String()
}

func forceHint(r *rig.Record) string {
	if r.Result == rig.ResultFail {
		return "; --force runs it again to show what failed"
	}
	return ""
}

// printRecord writes rec as one JSON line.
func printRecord(w io.Writer, rec *rig.Record) {
	raw, err := json.Marshal(rec)
	if err != nil {
		return
	}
	fmt.Fprintf(w, "%s\n", raw)
}

// rigPublish copies rec onto the bead's rig_check.<check> key through the gcbd
// write path and reads it back. rec is a record the store holds: one it just
// took, or one a lookup returned. The copy is for whoever reads the bead; the
// record in the store is what answers the gate, so a publish that fails is
// reported and changes nothing else.
func rigPublish(check, bead string, rec *rig.Record, say func(string, ...any)) {
	if bead == "" {
		return
	}
	raw, err := json.Marshal(rec)
	if err != nil {
		say("WARN the result was not published to %s: %v", bead, err)
		return
	}
	key := "rig_check." + check
	client := gcbd.New()
	if out, err := client.Update(bead, "--set-metadata", key+"="+string(raw)); err != nil {
		say("WARN the result was not published to %s (gc bd update exit %d): %s", bead, gcbd.ExitCode(err), firstLines(out, 3))
		return
	}
	if b := client.ShowDirect(bead); b == nil || b.Meta(key) != string(raw) {
		say("WARN the result was written to %s's %s, but did not read back as written", bead, key)
		return
	}
	say("published to %s as %s", bead, key)
}

func firstLines(s string, n int) string {
	lines := strings.Split(s, "\n")
	if len(lines) > n {
		lines = append(lines[:n], fmt.Sprintf("… %d more", len(lines)-n))
	}
	return strings.Join(lines, "\n")
}
