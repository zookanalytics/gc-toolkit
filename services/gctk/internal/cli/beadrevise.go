package cli

import (
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/revise"
)

const beadReviseLong = `Revises what the work on a bead should do while that work runs. The revision
is appended to the bead's notes under a heading that says when and by whom,
then each session working the bead now is sent it with an immediate nudge
(gc session nudge --delivery immediate): the bead's own assignee, and whoever
holds a member of a live workflow that works the bead. A bead whose workflow
is running reads open and unassigned, so the workflow's members are where its
sessions are found. A holder the session list names no session for has gone,
and whoever takes its work next reads the notes. A session that runs no agent,
such as the control-dispatcher, is not sent it, and nor is this session. With
no session working the bead, the note is all the revision needs.

The nudge is one line of at most 800 bytes: who revised the work, that the
bead's notes hold the revision in full, then the revision, cut to fit. A
Claude Code session takes it inside its running turn, with its next tool
result. Gas City holds a nudge to a Codex session that is running a turn
until that turn ends, since Codex's submit keys would cancel the turn, so
until then such a session has the revision only where its run reads the
bead's notes. It prints a line that says the note landed, then a line for each
session working the bead, with what gc said of its nudge or why it was sent
none, or one line that says no session works the bead.

The note's writer is GC_ALIAS, else GC_SESSION_NAME, else host. --db names the
store, a store's .beads directory. Without it the bead's store is the one gc
routes the bead to.

exit: 0 the revision is on the bead's notes, and each session working the bead
        was sent it, or none works it
      1 nothing was written: the store did not read, or the note did not land
      2 usage, or refused: nothing written
      3 the revision is on the notes, but a session working the bead may not
        have it, and the message says what to send by hand`

func newBeadReviseCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	cmd := &cobra.Command{
		Use:   "revise <bead> <revision> [--db <path>]",
		Short: "revise what the work on a bead should do while it runs, and send the revision to the sessions doing it",
		Long:  beadReviseLong,
		Args:  cobra.ExactArgs(2),
		RunE: func(_ *cobra.Command, args []string) error {
			return beadRevise(revise.Request{Bead: strings.TrimSpace(args[0]), Text: args[1]}, db, stdout, stderr)
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	return cmd
}

// beadRevise opens the bead's store, --db or else the one gc routes the bead
// to, and revises its work, printing what landed on stdout and why it stopped
// on stderr.
func beadRevise(req revise.Request, db string, stdout, stderr io.Writer) error {
	const prog = "gctk bead revise"
	l, err := ledger.Open(db, req.Bead)
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not open %s's store (%v); nothing was written\n", prog, req.Bead, err)
		return exit(1)
	}
	v := &revise.Revisions{Ledger: l, City: gascity.New(), By: "host", Now: time.Now}
	for _, name := range []string{"GC_ALIAS", "GC_SESSION_NAME"} {
		if s := strings.TrimSpace(os.Getenv(name)); s != "" {
			v.By = s
			break
		}
	}
	for _, name := range []string{"GC_SESSION_NAME", "GC_SESSION_ID", "GC_ALIAS", "GC_AGENT"} {
		if s := strings.TrimSpace(os.Getenv(name)); s != "" {
			v.Self = append(v.Self, s)
		}
	}
	lines, err := v.Revise(req)
	for _, line := range lines {
		fmt.Fprintln(stdout, line)
	}
	switch {
	case err == nil:
		return nil
	case revise.Refused(err):
		fmt.Fprintf(stderr, "%s: %v\n", prog, err)
		return exit(2)
	case revise.IsUnsent(err):
		fmt.Fprintf(stderr, "%s: %v\n", prog, err)
		return exit(3)
	}
	fmt.Fprintf(stderr, "%s: %v\n", prog, err)
	return exit(1)
}
