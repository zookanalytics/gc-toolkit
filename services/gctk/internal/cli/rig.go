package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/rig"
)

// `gctk rig` carries the actions gctk takes on a rig, and its first are the
// checks. test, lint and typecheck run the command their caller passes and
// record the result against the commit it ran at (internal/rig). setup and
// build run the command their caller passes and record nothing: setup leaves
// environment state behind, and a build makes itself current. serve runs a
// copy of the rig's UI (rig_serve.go).
//
// gctk reads no formula var and works out no diff. The caller passes the
// command, a test caller declares which of the two test runs it is, and a
// caller whose rig declares no command for a check says so with
// --nothing-declared. A command that works out its own subset, such as an
// affected test command, takes its diff where it runs.
//
// The command's output passes through untouched. rig's own lines go to
// stderr, and --check prints the record it found on stdout as one JSON line.

// rigRecordedLong is the help of the verbs whose result is recorded: test,
// lint and typecheck.
const rigRecordedLong = `Runs the check's command with bash at the top of the checkout the current
directory sits in, and records the result against HEAD. A call passes the
command with --command, says with --nothing-declared that the rig declares
none, or asks with --check what is recorded and runs nothing. test also
declares which of its two runs the command is, with --scope.

A recorded result answers a call that declares the same run, without running
it again: the same command line and, for test, the same scope. A full-suite
pass also answers for every commit with the same tree. A pass passes and a fail
fails. A call that declares another run runs, and its result replaces the
record. --check needs no command: it reports whatever is recorded at HEAD, and
calls nothing but git.

A checkout with changes HEAD does not hold is refused: a record certifies a
commit. A run that moves HEAD or changes a tracked file records nothing, pass
or fail. Untracked files a run leaves behind do not stop its record, but the
next call refuses them, so a check command leaves none that git does not
ignore.

` + rigSlotsHelp + `

exit: 0 pass · 1 fail · 2 usage · 3 nothing recorded (--check)
      4 machine failure, nothing recorded or published: a refused checkout, a
        command bash cannot parse, find or execute (126, 127), a command ended
        by a signal or still running at the timeout, a wait for slots still
        going at the timeout, a command that moved HEAD or changed a tracked
        file, a checkout rig cannot read after the run, or a result the
        record store did not take. Such a run says nothing about the code.
      128+N stopped by signal N`

// rigRunOnlyLong is the help of setup and build, which record nothing.
const rigRunOnlyLong = `Runs --command with bash at the top of the checkout the current directory
sits in, and records nothing: setup leaves environment state behind, and a
build makes itself current. In a checkout they find clean, they put back what
their command changes, other than files git ignores, so the recorded checks
after them can run.

` + rigSlotsHelp + `

exit: 0 pass · 1 fail · 2 usage
      4 machine failure: a command bash cannot parse, find or execute, one
        still running at the timeout, or a wait for slots still going at it
      128+N stopped by signal N`

// rigSlotsHelp is what the help of each verb that runs a command says of the
// machine's slots (internal/rig, slots.go).
const rigSlotsHelp = `A run holds slots on the machine while its command runs, so that the checks
every session on it runs at once fit in its memory. A slot stands for 4 GiB,
and a run takes one for each 4 GiB the last ten runs of its check in this
repository used at most, or every slot while none of them is measured. The
machine has GCTK_RIG_SLOTS slots, else as many as five eighths of its memory
holds. They are Gas City's push-gate slots, in the city's .gc/gate-slots, so a
push's test suites and the checks share them. A run that finds too few free
waits its turn and says what holds them, and --timeout counts the wait with
the run. GC_PUSH_GATE_NO_CAP=1 takes no slots, and every command runs with it
set, because the slots its run holds cover what it starts.`

// The exit codes rigRecordedLong states.
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
	// given reports whether a flag was on the command line, for the checks of
	// what goes with what.
	given func(name string) bool
}

func newRigCmd(stdout, stderr io.Writer) *cobra.Command {
	verbs := []*cobra.Command{
		rigVerb(rig.CheckTest, "run the rig's test command and record the result at the commit", rigRecordedLong, stdout, stderr),
		rigVerb(rig.CheckLint, "run the rig's lint command and record the result at the commit", rigRecordedLong, stdout, stderr),
		rigVerb(rig.CheckTypecheck, "run the rig's typecheck command and record the result at the commit", rigRecordedLong, stdout, stderr),
		rigVerb("setup", "run the rig's setup command, recording nothing", rigRunOnlyLong, stdout, stderr),
		rigVerb("build", "run the rig's build command, recording nothing", rigRunOnlyLong, stdout, stderr),
		newRigServeCmd(stdout, stderr),
	}
	return group("rig", "actions on the rig an agent works in",
		`Actions on the rig an agent works in. Its first are the checks: test, lint and
typecheck run the command their caller passes and record the result against
the commit it ran at, and setup and build run theirs and record nothing. serve
runs a copy of the rig's UI from a checkout, for a demo capture or a person.

gctk reads no formula var and works out no diff. The caller passes the command,
a test caller declares which of the two test runs it is, and a caller whose rig
declares no command for a check says so with --nothing-declared. A check's
output passes through untouched. rig's own lines go to stderr, and --check
prints what it found on stdout as one JSON line. Each verb that runs a command
holds slots on the machine for the memory its check uses, and waits its turn
when they are taken.`, verbs...)
}

// rigVerb builds one rig verb and its flags.
func rigVerb(verb, short, long string, stdout, stderr io.Writer) *cobra.Command {
	o := rigOpts{}
	c := &cobra.Command{
		Use:   verb,
		Short: short,
		Long:  long,
		Args:  cobra.NoArgs,
	}
	f := c.Flags()
	f.StringVar(&o.command, "command", "", "the `command` line to run")
	f.DurationVar(&o.timeout, "timeout", rigDefaultTimeout, "stop a call still waiting for slots or running after this long, such as 90m; 0 never")
	recorded := verb != "setup" && verb != "build"
	if recorded {
		f.BoolVar(&o.nothing, "nothing-declared", false, "the rig declares no command for this check: record a pass that ran nothing")
		f.BoolVar(&o.check, "check", false, "print the result recorded at HEAD and run nothing")
		f.BoolVar(&o.force, "force", false, "run even when a result is already recorded")
		f.StringVar(&o.publish, "publish-bead", "", "copy the result onto this `bead`'s rig_check.<check> key")
	}
	if verb == rig.CheckTest {
		f.StringVar(&o.scope, "scope", "", "which test run the command is, `full|affected`: the whole suite, or the subset the commit's diff selects")
	}
	c.RunE = func(cmd *cobra.Command, _ []string) error {
		o.given = cmd.Flags().Changed
		if msg := checkRigOpts(verb, o); msg != "" {
			return errors.New(msg)
		}
		if !recorded {
			return exit(rigRunOnly(verb, o, stdout, stderr))
		}
		return exit(rigRecorded(verb, o, stdout, stderr))
	}
	return c
}

// checkRigOpts says why verb's flags do not go together, or returns "".
func checkRigOpts(verb string, o rigOpts) string {
	if o.given("command") && o.command == "" {
		return "--command needs a command line; when the rig declares none, pass --nothing-declared"
	}
	for name, v := range map[string]string{"scope": o.scope, "publish-bead": o.publish} {
		if o.given(name) && v == "" {
			return "flag --" + name + " needs a value"
		}
	}
	if o.scope != "" && o.scope != rig.ScopeFull && o.scope != rig.ScopeAffected {
		return fmt.Sprintf("--scope %q is not full or affected", o.scope)
	}
	if o.timeout < 0 {
		return fmt.Sprintf("--timeout %s is not a duration such as 90m or 2h", o.timeout)
	}
	if verb == "setup" || verb == "build" {
		if !o.given("command") {
			return verb + " needs --command"
		}
		return ""
	}
	// A mode is chosen by its value, so --check=false or --nothing-declared=false
	// chooses none, as leaving the flag out would.
	modes := 0
	for _, on := range []bool{o.command != "", o.nothing, o.check} {
		if on {
			modes++
		}
	}
	switch {
	case modes == 0:
		return "pass --command, --nothing-declared or --check"
	case modes > 1:
		return "--command, --nothing-declared and --check exclude one another"
	case o.check && o.publish != "":
		return "--check runs no gc, so it publishes nothing; drop --publish-bead"
	case o.check && (o.force || o.given("scope") || o.given("timeout")):
		return "--check runs nothing, so it takes no --force, --scope or --timeout"
	case o.nothing && (o.force || o.given("scope") || o.given("timeout")):
		return "--nothing-declared runs nothing, so it takes no --force, --scope or --timeout"
	case verb == rig.CheckTest && o.command != "" && o.scope == "":
		return "test --command needs --scope full or --scope affected"
	}
	return ""
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
			rigPublish(o.publish, rec, say)
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
		rigPublish(o.publish, rec, say)
		return rigExitPass
	}

	if ok, reason := rig.Parses(o.command); !ok {
		return machine("%s; the command is %q", reason, o.command)
	}
	held, runFor, code, ended := rigTake(check, co, o.timeout, say, machine)
	if ended {
		return code
	}
	say("running %s at %s", runLabel(scope, o.command), co.Commit)
	out := rig.Run(co.Top, o.command, runFor, stdout, stderr)
	held.Release()
	rigKeepPeak(check, co, out, say)
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
	// A run speaks for co.Commit only while it leaves HEAD and every tracked
	// file as it found them, so a command that commits, checks out or writes a
	// tracked file records nothing, pass or fail. An untracked file it leaves
	// behind changes neither, so its result stands, and the next call here
	// refuses the file.
	moved, left, err := co.Changes()
	if err != nil {
		return machine("cannot read the checkout after the run: %v", err)
	}
	if moved != "" {
		return machine("the command changed the checkout it ran in, so its %s (exit %d) says nothing about %s:\n%s", result, out.ExitCode, co.Commit, firstLines(moved, 10))
	}
	rec := newRecord(check, result, scope, co, o.command, out.ExitCode, out.Duration)
	if err := store.Put(rec); err != nil {
		say("machine failure: the record store did not take the %s at %s (%s): %v", result, co.Commit, outcomeLabel(rec), err)
		return rigExitMachine
	}
	say("%s at %s (%s); recorded", result, co.Commit, outcomeLabel(rec))
	if left != "" {
		say("WARN the run left files git does not ignore, and the next call in this checkout is refused until they are gone:\n%s", firstLines(left, 10))
	}
	rigPublish(o.publish, rec, say)
	return resultExit(rec)
}

// rigRunOnly runs setup or build, which record nothing. In a checkout it finds
// clean, it puts back what the command changes there, other than files git
// ignores, because the recorded checks that follow in the same checkout refuse
// changes HEAD does not hold. A checkout that already has such changes keeps
// what the command leaves, since its changes cannot be told from the caller's.
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
	// A status git cannot read proves nothing clean, so nothing is put back.
	before, err := co.Dirty()
	clean := err == nil && before == ""
	held, runFor, code, ended := rigTake(verb, co, o.timeout, say, machine)
	if ended {
		return code
	}
	say("running %s", o.command)
	out := rig.Run(co.Top, o.command, runFor, stdout, stderr)
	held.Release()
	rigKeepPeak(verb, co, out, say)
	code = rigExitPass
	switch out.Kind {
	case rig.Interrupted:
		say("stopped by signal %d (%s); the command's process group was stopped", int(out.Signal), out.Signal)
		return 128 + int(out.Signal)
	case rig.Machine:
		code = machine("%s, after %s", out.Reason, out.Duration.Round(time.Millisecond))
	case rig.Failed:
		say("fail (exit %d, %s)", out.ExitCode, out.Duration.Round(time.Millisecond))
		code = rigExitFail
	default:
		say("pass (%s)", out.Duration.Round(time.Millisecond))
	}
	if clean {
		rigPutBack(co, say)
	}
	return code
}

// rigTake holds the machine's slots for a run of verb in co (internal/rig,
// slots.go) within timeout, where a zero timeout waits as long as it takes. It
// returns the slots it holds and what the wait for them left of timeout for
// the run. When
// the wait ends the call, it says why and returns the call's exit and true: a
// machine failure for a wait that ran out of time, and 128 plus the signal
// for one a signal stopped. A machine whose memory or slot files cannot be
// read runs the command with no slots, and says so.
func rigTake(verb string, co *git.Checkout, timeout time.Duration, say func(string, ...any), machine func(string, ...any) int) (*rig.Held, time.Duration, int, bool) {
	if os.Getenv(rig.NoCapVar) == "1" {
		return nil, timeout, 0, false
	}
	start := time.Now()
	h := host.Local()
	mem, err := h.Memory()
	if err != nil {
		say("WARN runs with no slots, since the machine's memory could not be read: %v", err)
		return nil, timeout, 0, false
	}
	count, note := rig.SlotCount(os.Getenv, mem)
	if note != "" {
		say("WARN %s", note)
	}
	weight, err := rig.NewPeaks(co.Common).Weight(verb)
	if err != nil {
		say("WARN the memory its last runs used could not be read, so it runs alone: %v", err)
	}
	n := rig.SlotsFor(weight, count)
	taking := fmt.Sprintf("takes %s of the machine's %d, %s each,", rig.SlotCountText(n), count, gib(rig.SlotSize))
	switch {
	case weight == 0:
		say("%s since no run of this check is measured in this repository, so it runs alone", taking)
	case weight > int64(count)*rig.SlotSize:
		say("WARN %s for the %s its last runs here used at most, which is more than they stand for, so it runs alone and can still use up the machine's memory beside the city's other work", taking, gib(weight))
	default:
		say("%s for the %s its last runs here used at most", taking, gib(weight))
	}
	var until time.Time
	if timeout > 0 {
		until = start.Add(timeout)
	}
	stop := make(chan os.Signal, 1)
	for _, s := range []os.Signal{syscall.SIGTERM, syscall.SIGINT} {
		if !signal.Ignored(s) {
			signal.Notify(stop, s)
		}
	}
	slots := rig.NewSlots(h, rig.SlotDir(os.Getenv, co.Top, co.Common), count, slotLabel(verb, co))
	held, sig, err := slots.Take(n, until, stop, say)
	signal.Stop(stop)
	if sig == nil {
		// A signal that came as the slots were taken still stops the call.
		select {
		case sig = <-stop:
			held.Release()
		default:
		}
	}
	var timedOut *rig.SlotTimeout
	switch {
	case sig != nil:
		n, _ := sig.(syscall.Signal)
		say("stopped by signal %d (%s) while it waited for slots, before its command ran", int(n), n)
		return nil, 0, 128 + int(n), true
	case errors.As(err, &timedOut):
		return nil, 0, machine("%v", err), true
	case err != nil:
		say("WARN runs with no slots, since the slots could not be taken: %v", err)
		return nil, timeout, 0, false
	}
	if timeout <= 0 {
		return held, 0, 0, false
	}
	left := timeout - held.Waited
	if left <= 0 {
		held.Release()
		return nil, 0, machine("its slots came after %s, with none of its --timeout %s left", held.Waited.Round(time.Second), timeout), true
	}
	return held, left, 0, false
}

// slotLabel is what a stamp says the run is, as one word, then the machine's
// name: the session, as the push gate names one, the verb and the
// repository.
func slotLabel(verb string, co *git.Checkout) string {
	session := "unknown"
	for _, v := range []string{"GC_SESSION_NAME", "GC_AGENT", "GC_TEMPLATE"} {
		if s := os.Getenv(v); s != "" {
			session = s
			break
		}
	}
	repo := filepath.Base(co.Common)
	if repo == ".git" {
		repo = filepath.Base(filepath.Dir(co.Common))
	}
	name, err := os.Hostname()
	if err != nil || name == "" {
		name = "unknown"
	}
	return strings.Join(strings.Fields(fmt.Sprintf("%s:gctk-rig-%s:%s", session, verb, repo)), "_") + " " + name
}

// rigKeepPeak keeps the memory the run used, which the slots of the next run
// of verb in this repository are taken for.
func rigKeepPeak(verb string, co *git.Checkout, out rig.Outcome, say func(string, ...any)) {
	if out.Peak <= 0 {
		return
	}
	if err := rig.NewPeaks(co.Common).Add(verb, time.Now(), out.Peak); err != nil {
		say("WARN the %s this run used at most was not kept: %v", gib(out.Peak), err)
	}
}

// gib gives a size in GiB.
func gib(n int64) string { return fmt.Sprintf("%.1f GiB", float64(n)/(1<<30)) }

// rigPutBack puts back what a run left in a checkout that was clean before
// it, and says what it put back and what it could not.
func rigPutBack(co *git.Checkout, say func(string, ...any)) {
	left, err := co.Dirty()
	if err != nil {
		say("WARN nothing was put back: %v", err)
		return
	}
	if left == "" {
		return
	}
	remains, err := co.PutBack()
	if err != nil {
		say("WARN the run left changes HEAD does not hold, and they were not put back (%v), so a recorded check here is refused until they are gone:\n%s", err, firstLines(left, 10))
		return
	}
	say("put back what the run left that git does not ignore, since a recorded check refuses it:\n%s", firstLines(left, 10))
	if remains != "" {
		say("WARN these could not be put back, so a recorded check here is refused until they are gone:\n%s", firstLines(remains, 10))
	}
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

// rigPublish copies rec onto the bead through rig's publish, which writes its
// check's key through the ledger. rec is a record the store holds: one it just
// took, or one a lookup returned. The copy is for whoever reads the bead; the
// record in the store is what answers a later call, so a publish that fails is
// reported and changes nothing else.
func rigPublish(bead string, rec *rig.Record, say func(string, ...any)) {
	if bead == "" {
		return
	}
	key, err := rig.Publish(ledger.New(gcbd.New()), bead, rec)
	if err != nil {
		say("WARN the result was not published to %s: %v", bead, err)
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
