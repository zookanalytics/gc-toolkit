package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/rig"
)

// `gctk rig` carries the actions gctk takes on a rig, and its first are the
// checks. test, lint and typecheck run the command their caller passes and
// record the result against the commit it ran at (internal/rig). setup and
// build run the command their caller passes and record nothing: setup leaves
// environment state behind, and a build makes itself current.
//
// gctk reads no formula var and works out no diff. The caller passes the
// command, a test caller declares which of the two test runs it is, and a
// caller whose rig declares no command for a check says so with
// --nothing-declared. A command that works out its own subset, such as an
// affected test command, takes its diff where it runs.
//
// The command's output passes through untouched. rig's own lines go to
// stderr, and --check prints the record it found on stdout as one JSON line.

const rigUsage = `usage:
  gctk rig test --scope full|affected --command <command> [--force]
                [--publish-bead <id>] [--timeout <duration>]
  gctk rig lint|typecheck --command <command> [--force]
                [--publish-bead <id>] [--timeout <duration>]
  gctk rig test|lint|typecheck --nothing-declared [--publish-bead <id>]
  gctk rig test|lint|typecheck --check
  gctk rig setup|build --command <command> [--timeout <duration>]

Runs <command> with bash at the top of the checkout the current directory sits
in. test, lint and typecheck record the result against HEAD; setup and build
record nothing.

  --command <command>    the command line to run
  --scope full|affected  which test run the command is: the whole suite, or the
                         subset the commit's diff selects
  --nothing-declared     the rig declares no command for this check: record a
                         pass that ran nothing
  --check                print the result recorded at HEAD and run nothing
  --force                run even when a result is already recorded
  --publish-bead <id>    copy the result onto the bead's rig_check.<check> key
  --timeout <duration>   stop a run still going after this long; 0 never
                         (default 2h)

A recorded result answers a call that declares the same run, without running
it again: the same command line and, for test, the same scope. A full-suite
pass also answers for every commit with the same tree. A pass passes and a fail
fails. A call that declares another run runs, and its result replaces the
record. --check needs no command: it reports whatever is recorded at HEAD, and
calls nothing but git.

A checkout with changes HEAD does not hold is refused, except by setup and
build: a record certifies a commit.

exit: 0 pass · 1 fail · 2 usage · 3 nothing recorded (--check)
      4 machine failure: nothing is recorded or published, because the run
        says nothing about the code. That is a refused checkout, a command bash
        cannot parse, not found or not executable (126, 127), ended by a
        signal, or still running at the timeout, and a result the record store
        did not take.
      128+N stopped by signal N
`

// The exit codes rigUsage states.
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

type rigOpts struct {
	command string
	scope   string
	nothing bool
	check   bool
	force   bool
	publish string
	timeout time.Duration
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
	for i := 0; i < len(args); i++ {
		a := args[i]
		if o.set[a] {
			return o, "flag " + a + " given twice"
		}
		o.set[a] = true
		switch a {
		case "--nothing-declared":
			o.nothing = true
			continue
		case "--check":
			o.check = true
			continue
		case "--force":
			o.force = true
			continue
		case "--command", "--scope", "--publish-bead", "--timeout":
		default:
			return o, fmt.Sprintf("unknown argument %q", a)
		}
		if i+1 >= len(args) || args[i+1] == "" {
			if a == "--command" {
				return o, "--command needs a command line; when the rig declares none, pass --nothing-declared"
			}
			return o, "flag " + a + " needs a value"
		}
		i++
		v := args[i]
		switch a {
		case "--command":
			o.command = v
		case "--scope":
			if v != rig.ScopeFull && v != rig.ScopeAffected {
				return o, fmt.Sprintf("--scope %q is not full or affected", v)
			}
			o.scope = v
		case "--publish-bead":
			o.publish = v
		case "--timeout":
			d, err := time.ParseDuration(v)
			if err != nil || d < 0 {
				return o, fmt.Sprintf("--timeout %q is not a duration such as 90m or 2h", v)
			}
			o.timeout = d
		}
	}
	allowed := map[string]bool{"--command": true, "--timeout": true}
	if verb != "setup" && verb != "build" {
		for _, f := range []string{"--nothing-declared", "--check", "--force", "--publish-bead"} {
			allowed[f] = true
		}
	}
	if verb == rig.CheckTest {
		allowed["--scope"] = true
	}
	for f := range o.set {
		if !allowed[f] {
			return o, fmt.Sprintf("%s does not take %s", verb, f)
		}
	}
	if verb == "setup" || verb == "build" {
		if !o.set["--command"] {
			return o, verb + " needs --command"
		}
		return o, ""
	}
	modes := 0
	for _, f := range []string{"--command", "--nothing-declared", "--check"} {
		if o.set[f] {
			modes++
		}
	}
	switch {
	case modes == 0:
		return o, "pass --command, --nothing-declared or --check"
	case modes > 1:
		return o, "--command, --nothing-declared and --check exclude one another"
	case o.check && o.publish != "":
		return o, "--check runs no gc, so it publishes nothing; drop --publish-bead"
	case o.check && (o.force || o.set["--scope"] || o.set["--timeout"]):
		return o, "--check runs nothing, so it takes no --force, --scope or --timeout"
	case o.nothing && (o.force || o.set["--scope"] || o.set["--timeout"]):
		return o, "--nothing-declared runs nothing, so it takes no --force, --scope or --timeout"
	case verb == rig.CheckTest && o.command != "" && o.scope == "":
		return o, "test --command needs --scope full or --scope affected"
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
	found, err := store.Lookup(check, co.Commit, co.Tree)
	if err != nil {
		return machine("cannot read the record store %s: %v", store.Root(), err)
	}
	for _, p := range found.Ignored {
		say("WARN %s is not a readable record for this commit and was read as absent", p)
	}

	if o.check {
		rec, src := found.Recorded()
		if rec == nil {
			say("nothing is recorded at %s", co.Commit)
			return rigExitNone
		}
		printRecord(stdout, rec)
		say("%s", describeRecord(rec, src, co.Commit))
		return resultExit(rec)
	}

	scope := o.scope
	if o.nothing {
		scope = rig.ScopeNone
	}
	if !o.force {
		if rec, src := found.Answer(scope, o.command); rec != nil {
			say("%s; not run again%s", describeRecord(rec, src, co.Commit), forceHint(rec))
			rigPublish(check, o.publish, rec, say)
			return resultExit(rec)
		}
		if r := found.Commit; r != nil {
			say("%s is another run's, so this call runs and records its own", describeRecord(r, rig.FromCommit, co.Commit))
		}
	}

	if o.nothing {
		rec := newRecord(check, rig.ResultPass, rig.ScopeNone, co, "", 0, 0)
		if err := store.Put(rec); err != nil {
			say("machine failure: the record store did not take the pass that ran nothing at %s: %v", co.Commit, err)
			return rigExitMachine
		}
		say("nothing declared to run; recorded at %s as a pass that ran nothing", co.Commit)
		rigPublish(check, o.publish, rec, say)
		return rigExitPass
	}

	if ok, reason := rig.Parses(o.command); !ok {
		return machine("%s; the command is %q", reason, o.command)
	}
	say("running %s at %s", runLabel(scope, o.command), co.Commit)
	out := rig.Run(co.Top, o.command, o.timeout, stdout, stderr)
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
	rec := newRecord(check, result, scope, co, o.command, out.ExitCode, out.Duration)
	if err := store.Put(rec); err != nil {
		say("machine failure: the record store did not take the %s at %s (%s): %v", result, co.Commit, outcomeLabel(rec), err)
		return rigExitMachine
	}
	say("%s at %s (%s); recorded", result, co.Commit, outcomeLabel(rec))
	rigPublish(check, o.publish, rec, say)
	return resultExit(rec)
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
	if ok, reason := rig.Parses(o.command); !ok {
		return machine("%s; the command is %q", reason, o.command)
	}
	say("running %s", o.command)
	out := rig.Run(co.Top, o.command, o.timeout, stdout, stderr)
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

func newRecord(check, result, scope string, co *git.Checkout, command string, exit int, d time.Duration) *rig.Record {
	return &rig.Record{
		Check:      check,
		Result:     result,
		Scope:      scope,
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

// runLabel names the run a call makes, for the line that starts it.
func runLabel(scope, command string) string {
	if scope == "" {
		return command
	}
	return command + " (scope " + scope + ")"
}

// outcomeLabel says how a run a call just made came out.
func outcomeLabel(r *rig.Record) string {
	var b strings.Builder
	if r.Scope != "" {
		fmt.Fprintf(&b, "scope %s, ", r.Scope)
	}
	fmt.Fprintf(&b, "exit %d, %s", r.ExitCode, (time.Duration(r.DurationMS) * time.Millisecond).Round(time.Millisecond))
	return b.String()
}

// describeRecord says what a found record holds, for rig's own lines. head is
// the commit the call is at.
func describeRecord(r *rig.Record, src, head string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s recorded at %s", r.Result, r.Commit)
	if src == rig.FromTree {
		fmt.Fprintf(&b, ", whose tree %s is HEAD's (%s)", r.Tree, head)
	}
	b.WriteString(" (")
	if r.Scope != "" {
		fmt.Fprintf(&b, "scope %s, ", r.Scope)
	}
	if r.Result == rig.ResultFail {
		fmt.Fprintf(&b, "exit %d, ", r.ExitCode)
	}
	fmt.Fprintf(&b, "%s, by %s at %s)", (time.Duration(r.DurationMS) * time.Millisecond).Round(time.Millisecond), r.Runner, r.RecordedAt)
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
// record in the store is what answers a later call, so a publish that fails is
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
