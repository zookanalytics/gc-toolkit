package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/claudecode"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/memory"
)

// The exit codes the memory verbs share.
const (
	memoryExitDone    = 0
	memoryExitFailed  = 1
	memoryExitUnknown = 3
)

// newIntake builds the memory intake over the city. A variable so a test can
// give it fakes.
var newIntake = func() *memory.Intake {
	return &memory.Intake{
		Runtime: gascity.New(),
		Claude:  claudecode.New(),
		Store:   func(db string) (*ledger.Ledger, error) { return ledger.Open(db) },
		Now:     now,
	}
}

func newMemoryCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("memory",
		"the learning loop's memory intake: the agent memory notes due for the distiller, and its decisions",
		`The learning loop's second intake (specs/tk-zlot608.2/design.md). Each verb
asks Claude Code where a session started in each rig's checkout and in the
city's root keeps its memory, and keeps one list per memory directory under
<city>/.gc/runtime/packs/gc-toolkit/memory-intake/<SHA-256 of its real path>/.
The feedback distiller runs settle first, lists the due notes with due, and
records its judge's decisions with apply (the learning-distill skill).`,
		newMemoryDueCmd(stdout, stderr),
		newMemoryApplyCmd(stdout, stderr),
		newMemorySettleCmd(stdout, stderr),
	)
}

func newMemoryDueCmd(stdout, stderr io.Writer) *cobra.Command {
	var limit int
	var count bool
	cmd := &cobra.Command{
		Use:   "due [--limit N | --count]",
		Short: "the memory notes due for the judge, oldest first, as JSON",
		Long: `Prints the units due for the judge as a JSON array, oldest first: each note,
or entry of a collection note with text of its own, that its directory's list
does not hold at its hash, and each kept until a day that has come. A unit is
as old as its file's last change, or as the day it came due. Each object holds
memory_ref, memory_kind, memory_dir, memory_file, memory_due (new, changed or
date), memory_prior, created_at and, for an entry, memory_text. --limit prints
the oldest N, and --count prints how many are due.

A place it cannot learn, or a directory it cannot read, is named on stderr and
left out, and the rest print.

exit: 0 every place read
      1 a directory or the city did not read
      2 usage
      3 a place whose memory directory it could not learn`,
		Args: cobra.NoArgs,
		RunE: func(c *cobra.Command, _ []string) error {
			if c.Flags().Changed("limit") && count {
				return fmt.Errorf("--limit and --count go alone")
			}
			if limit < 0 {
				return fmt.Errorf("--limit takes a count")
			}
			return exit(memoryDue(newIntake(), c.Flags().Changed("limit"), limit, count, stdout, stderr))
		},
	}
	cmd.Flags().IntVar(&limit, "limit", 0, "print the oldest `N` due")
	cmd.Flags().BoolVar(&count, "count", false, "print how many are due")
	return cmd
}

func memoryDue(in *memory.Intake, limited bool, limit int, count bool, stdout, stderr io.Writer) int {
	due, err := in.Due()
	if err != nil {
		fmt.Fprintf(stderr, "gctk memory due: no memory directory was placed: %v\n", err)
		printDue(nil, count, stdout)
		return memoryExitFailed
	}
	code := memoryExitDone
	for _, why := range due.Unread {
		fmt.Fprintf(stderr, "gctk memory due: %s; its due notes are not listed\n", why)
		code = memoryExitFailed
	}
	if unknown(due.Places, "gctk memory due", stderr) {
		code = memoryExitUnknown
	}
	notes := due.Due
	if limited && limit < len(notes) {
		notes = notes[:limit]
	}
	printDue(notes, count, stdout)
	return code
}

func printDue(notes []memory.Due, count bool, stdout io.Writer) {
	if count {
		fmt.Fprintln(stdout, len(notes))
		return
	}
	if notes == nil {
		notes = []memory.Due{}
	}
	raw, _ := json.MarshalIndent(notes, "", "  ")
	fmt.Fprintln(stdout, string(raw))
}

// unknown names each place whose memory directory the intake could not learn,
// and reports whether there was one.
func unknown(ps memory.Places, prog string, stderr io.Writer) bool {
	for _, u := range ps.Unknown {
		fmt.Fprintf(stderr, "%s: %s: cannot learn where its sessions keep memory: %s\n", prog, u.Name, u.Why)
	}
	return len(ps.Unknown) > 0
}

func newMemoryApplyCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "apply <decisions-file | ->",
		Short: "record the judge's decision on each memory note it judged",
		Long: `Records one decision a line, by the ref due gave the unit:

  <ref> waits <bead>                 it waits on the bead
  <ref> next <YYYY-MM-DD> [ask-use]  it is due again that day, after today
  <ref> drop                         it leaves memory

ask-use, for a whole note, adds the line that asks its users to record the days
they use it, one dated line a day, and a decision without it takes that line
out and leaves the use lines. A drop keeps the unit's text under its
directory's state, removes it, and takes the pointers to a removed note out of
the index and the collection notes while its name holds no file. A pointer
that does not come out goes on the next apply or settle. A decision acts only
on the text its ref names, so one whose unit changed since due listed it is
refused and stays due.

exit: 0 each decision recorded, removed or refused as changed
      1 a decision could not be read or done, as stderr says
      2 usage`,
		Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			return exit(memoryApply(newIntake(), args[0], stdout, stderr))
		},
	}
}

func memoryApply(in *memory.Intake, src string, stdout, stderr io.Writer) int {
	var raw []byte
	var err error
	if src == "-" {
		raw, err = io.ReadAll(os.Stdin)
	} else {
		raw, err = os.ReadFile(src)
	}
	if err != nil {
		fmt.Fprintf(stderr, "gctk memory apply: cannot read %s: %v\n", src, err)
		return memoryExitFailed
	}
	a, err := in.Apply(string(raw))
	for _, l := range a.Said {
		fmt.Fprintln(stdout, l)
	}
	for _, l := range a.Failed {
		fmt.Fprintln(stderr, "gctk memory apply: "+l)
	}
	if err != nil {
		fmt.Fprintf(stderr, "gctk memory apply: no memory directory was placed, so nothing is recorded: %v\n", err)
		return memoryExitFailed
	}
	if len(a.Failed) > 0 {
		return memoryExitFailed
	}
	return memoryExitDone
}

func newMemorySettleCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "settle",
		Short: "end each memory note's wait that is done",
		Long: `Ends each wait that is done, in every memory directory it learns. A unit
whose bead closed on a merge that reached its repository's default branch is
removed with its text kept, for a feedback pattern once a follow-up has landed
and none is on its way, and a merge into an integration branch counts once the
effort's landing bead has. A unit whose wait ended with no fix landed is due at
once, as old as the day it ended. A row whose unit is gone leaves the list,
and a pointer to a removed note that an earlier run could not take out goes.
It prints each place and what it ended.

A place whose memory directory Claude Code does not name is one patrol finding,
memory-intake.places, filed through the pack's patrol-finding.sh in the scripts
directory GCTK_SCRIPTS_DIR names, and cleared once every place is learned.

exit: 0 done
      1 something could not be read or written, as stderr says
      3 a place whose memory directory it could not learn; the rest settled`,
		Args: cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return exit(memorySettle(newIntake(), stdout, stderr))
		},
	}
}

func memorySettle(in *memory.Intake, stdout, stderr io.Writer) int {
	s, err := in.Settle()
	if err != nil {
		fmt.Fprintf(stderr, "gctk memory settle: no memory directory was placed: %v\n", err)
		return memoryExitFailed
	}
	for _, a := range s.Places.Absent {
		fmt.Fprintf(stdout, "%s: no memory directory at %s\n", a.Name, a.Dir)
	}
	for _, l := range s.Said {
		fmt.Fprintln(stdout, l)
	}
	fmt.Fprintf(stdout, "waits ended: %s removed with a fix landed, each one's text kept; %s due again with no fix landed\n",
		units(s.Left), units(s.Due))
	for _, l := range s.Failed {
		fmt.Fprintln(stderr, "gctk memory settle: "+l)
	}
	switch {
	case unknown(s.Places, "gctk memory settle", stderr):
		return memoryExitUnknown
	case len(s.Failed) > 0:
		return memoryExitFailed
	}
	return memoryExitDone
}

func units(n int) string {
	if n == 1 {
		return "1 unit"
	}
	return strconv.Itoa(n) + " units"
}
