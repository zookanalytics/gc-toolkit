package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// `gctk pr summary <bead>` is how a change's author records what the change
// does for its PR, and how a reader of the PR's text asks what that record
// says: work-submit.sh at a polecat's hand-off and an integration effort's
// summary task record it, and rig-mentions.sh and demo-repo-artifact.sh read
// it. The pr package owns the key and holds the rule; this command reads the
// file it names and prints the answer.

const prSummaryLong = `Records what a change does, for the PR of the bead that owns it, or prints
what the bead records.

With --file, the file's text is the bead's PR summary: the account of what the
finished change does, which the PR's managed summary region carries in place
of the dispatch text (gctk pr compose). - reads it from stdin, and the text
ends at its last line, as a shell's $(cat <file>) reads it. With --title, the
bead takes the change's subject line as its title, which the PR's title is
composed from. Whichever of the two is given is recorded in one write, whose
exit decides whether it landed, and a summary or a title with no words is
refused before it.

With neither, it prints the summary the bead records, and nothing when it
records none.

exit: 0 recorded, or printed
      1 usage, a summary or a title with no words among them: nothing was
        written
      2 the bead or the file did not read, or the write did not land`

func newPRSummaryCmd(stdout, stderr io.Writer) *cobra.Command {
	var file, title string
	cmd := &cobra.Command{
		Use:         "summary <bead>",
		Short:       "record what a change does, for its PR's summary and title, or print the summary recorded",
		Long:        prSummaryLong,
		Args:        cobra.ExactArgs(1),
		Annotations: map[string]string{usageExitKey: "1"},
		RunE: func(c *cobra.Command, args []string) error {
			bead := strings.TrimSpace(args[0])
			if bead == "" {
				return errors.New("name the bead that owns the PR")
			}
			fileGiven, titleGiven := c.Flags().Changed("file"), c.Flags().Changed("title")
			if !fileGiven && !titleGiven {
				return exit(prSummaryPrint(bead, stdout, stderr))
			}
			return exit(prSummaryRecord(bead, file, fileGiven, title, titleGiven, stderr))
		},
	}
	f := cmd.Flags()
	f.StringVar(&file, "file", "", "the summary to record, - for stdin")
	f.StringVar(&title, "title", "", "the change's subject line, for the bead's title")
	return cmd
}

// prSummaryPrint prints the summary the bead records.
func prSummaryPrint(bead string, stdout, stderr io.Writer) int {
	summary, err := pr.Summary(ledger.New(gcbd.New()), bead)
	if err != nil {
		fmt.Fprintf(stderr, "gctk pr summary: %s did not read: %v\n", bead, err)
		return 2
	}
	if summary = strings.TrimRight(summary, "\n"); summary != "" {
		fmt.Fprintln(stdout, summary)
	}
	return 0
}

// prSummaryRecord records the summary the file holds, when --file named one,
// and the title, when --title gave one, in one write. An empty value has no
// words, whichever flag gave it.
func prSummaryRecord(bead, file string, fileGiven bool, title string, titleGiven bool, stderr io.Writer) int {
	var a pr.Account
	if fileGiven {
		var raw []byte
		var err error
		switch file {
		case "":
			fmt.Fprintln(stderr, "gctk pr summary: --file names the summary's file, - for stdin; nothing was written")
			return 1
		case "-":
			raw, err = io.ReadAll(os.Stdin)
		default:
			raw, err = os.ReadFile(file)
		}
		if err != nil {
			fmt.Fprintf(stderr, "gctk pr summary: the summary did not read: %v; nothing was written\n", err)
			return 2
		}
		if a.Summary = strings.TrimRight(string(raw), "\n"); a.Summary == "" {
			fmt.Fprintln(stderr, "gctk pr summary: the summary has no words; nothing was written")
			return 1
		}
	}
	if titleGiven {
		if a.Title = title; a.Title == "" {
			fmt.Fprintln(stderr, "gctk pr summary: the title has no words; nothing was written")
			return 1
		}
	}
	if err := pr.Record(ledger.New(gcbd.New()), bead, a); err != nil {
		if errors.Is(err, pr.ErrNoWords) {
			fmt.Fprintf(stderr, "gctk pr summary: %v; nothing was written\n", err)
			return 1
		}
		fmt.Fprintf(stderr, "gctk pr summary: %v\n", err)
		return 2
	}
	var what []string
	if a.Summary != "" {
		what = append(what, "the summary")
	}
	if a.Title != "" {
		what = append(what, "the title")
	}
	fmt.Fprintf(stderr, "gctk pr summary: recorded %s on %s\n", strings.Join(what, " and "), bead)
	return 0
}
