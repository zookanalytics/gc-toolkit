package cli

import (
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/rig"
)

const rigPreExistingLong = `Asks whether a recorded fail of a check at HEAD is pre-existing on the bead
--bead names, or, with --commit and --tracker, marks it so there. Like the
other rig verbs it reads the checkout the current directory sits in.

A fail is pre-existing when the same failure is red on the target and a tracker
carries it. A caller that finds a recorded fail red on the target too, with a
tracker for it (preexisting-failure.sh), marks it with --commit, the full sha
of HEAD, and --tracker, once for each tracker or as one list. The fail is the
one recorded at HEAD: for test, lint and typecheck the record --check reads,
and for setup and build, which record nothing, the bead's note of what they did
there. The mark is refused when HEAD holds no such fail, and when a tracker it
names is not open: a tracker that closed names the open bead its failure moved
to, to mark against instead, or says to merge the base in when no open bead
carries it. A second mark of the same fail keeps the trackers already marked,
and a mark of another fail replaces the one there.

Without --tracker it asks whether the bead's mark holds: only at its commit,
for the fail recorded there, and while a tracker it names is open. It prints
what it found as one line on stdout: "pre-existing, tracked by <the open
trackers>" when the mark holds, why when it does not, and nothing when the bead
has no mark at HEAD. A tracker that does not read is not open, and is reported
as unread, never as closed.

Each bead is read in the store gc routes its id to.

exit: 0 the mark holds, or it was written
      1 the mark does not hold, or it was refused, and the line says why
      2 usage
      4 a read did not answer, so nothing shows the mark holds, or the mark was
        not written`

// trackerID is the shape of a bead id a mark names.
var trackerID = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)

func newRigPreExistingCmd(stdout, stderr io.Writer) *cobra.Command {
	var bead, commit string
	var trackers []string
	c := &cobra.Command{
		Use:   "pre-existing <test|lint|typecheck|setup|build> --bead <bead> [--commit <sha> --tracker <bead>...]",
		Short: "whether a recorded fail at HEAD is pre-existing on a bead, or mark it so",
		Long:  rigPreExistingLong,
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			check := args[0]
			if !rig.Marked(check) {
				return fmt.Errorf("%q is not test, lint, typecheck, setup or build", check)
			}
			if strings.TrimSpace(bead) == "" {
				return errors.New("--bead names the bead the mark is on")
			}
			var named []string
			for _, t := range trackers {
				for _, id := range strings.FieldsFunc(t, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' || r == '\n' }) {
					if !trackerID.MatchString(id) {
						return fmt.Errorf("--tracker %q is not a bead id", id)
					}
					named = append(named, id)
				}
			}
			if cmd.Flags().Changed("tracker") && len(named) == 0 {
				return errors.New("--tracker names at least one tracker bead")
			}
			if len(named) == 0 {
				if cmd.Flags().Changed("commit") {
					return errors.New("--commit goes with --tracker: a question asks about HEAD")
				}
				return exit(rigAskPreExisting(bead, check, stdout, stderr))
			}
			if !git.IsObjectID(commit) {
				return fmt.Errorf("--commit %q is not a full commit sha", commit)
			}
			return exit(rigMarkPreExisting(bead, check, commit, named, stdout, stderr))
		},
	}
	f := c.Flags()
	f.StringVar(&bead, "bead", "", "the `bead` the mark is on: the work bead, or the anchor a review reads")
	f.StringVar(&commit, "commit", "", "the full `sha` of HEAD, whose fail a mark is about")
	f.StringArrayVar(&trackers, "tracker", nil, "a tracker `bead` that carries the failure: mark the fail against it")
	return c
}

// rigAskPreExisting prints whether bead's mark of check holds the fail
// recorded at HEAD.
func rigAskPreExisting(bead, check string, stdout, stderr io.Writer) int {
	co, err := git.Open(".")
	if err != nil {
		fmt.Fprintf(stderr, "gctk rig pre-existing: %v\n", err)
		return rigExitMachine
	}
	j := rig.Judge(ledger.New(gcbd.New()), co, bead, check)
	for _, w := range j.Warnings {
		fmt.Fprintf(stderr, "gctk rig pre-existing: WARN %s\n", w)
	}
	if j.Line != "" {
		fmt.Fprintln(stdout, j.Line)
	}
	switch j.Answer {
	case rig.Holds:
		return rigExitPass
	case rig.Unread:
		return rigExitMachine
	}
	return rigExitFail
}

// rigMarkPreExisting marks on bead that check's fail at commit, HEAD, is
// pre-existing, carried by trackers.
func rigMarkPreExisting(bead, check, commit string, trackers []string, stdout, stderr io.Writer) int {
	co, err := git.Open(".")
	if err != nil {
		fmt.Fprintf(stderr, "gctk rig pre-existing: %v, so nothing was written\n", err)
		return rigExitMachine
	}
	m, err := rig.MarkFail(ledger.New(gcbd.New()), co, bead, check, commit, trackers)
	var refused *rig.Refusal
	switch {
	case errors.As(err, &refused):
		fmt.Fprintf(stderr, "gctk rig pre-existing: %v\n", err)
		return rigExitFail
	case err != nil:
		fmt.Fprintf(stderr, "gctk rig pre-existing: %v\n", err)
		return rigExitMachine
	}
	fmt.Fprintf(stdout, "%s marks %s's fail at %s pre-existing, tracked by %s\n", bead, check, commit,
		strings.Join(m.Trackers, ", "))
	return rigExitPass
}
