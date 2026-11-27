package cli

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/note"
)

const beadNoteLong = `Appends a note to a bead's notes, as written, in the one write bd's own
append makes (gc bd update <bead> --append-notes). It is how an agent puts any
note on a bead, whether or not anyone is working the bead.

Flags go before the bead. Whatever follows the bead is the note, read as no
flag even when it starts with a dash, as a Markdown list or frontmatter does.

--notify is for a note that changes what the work on the bead should do. Once
the note lands, whoever is working the bead now is told of it: the bead's own
assignee, and whoever holds a member of a live workflow that works the bead,
since a bead whose workflow is running reads open and unassigned. Each such
session is sent an immediate nudge (gc session nudge --delivery immediate), one
line of at most 800 bytes: who wrote the note, that the bead's notes hold it in
full, then the note, cut to fit. A Claude Code session takes it inside its
running turn, with its next tool result. Gas City holds a nudge to a Codex
session that is running a turn until that turn ends, since Codex's submit keys
would cancel the turn, so until then such a session has the note only where its
run reads the bead's notes. A holder the session list names no session for has
gone, and whoever takes its work next reads the notes. A session that runs no
agent, such as the control-dispatcher, is not told, and nor is this session.
With nobody working the bead, the note waits for whoever picks the bead up, and
a closed bead has no work on it to tell.

It prints a line that says the note landed. With --notify it then prints a line
for each session working the bead, with what gc said of its nudge or why it was
sent none, or one line that says why nobody was told.

The note's writer, whom the nudge names, is GC_ALIAS, else GC_SESSION_NAME,
else host. --db names the store, a store's .beads directory. Without it the
bead's store is the one gc routes the bead to.

exit: 0 the note is on the bead's notes, and with --notify each session working
        the bead was told, or none works it
      1 nothing was written: the store did not read, or the note did not land
      2 usage, or refused: nothing written
      3 the note is on the bead's notes, but a session working the bead may not
        have been told, and the message says what to send by hand`

func newBeadNoteCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	var notify bool
	cmd := &cobra.Command{
		Use:   "note [--notify] [--db <path>] <bead> <note>",
		Short: "append a note to a bead, and with --notify tell whoever is working the bead now",
		Long:  beadNoteLong,
		Args:  cobra.ExactArgs(2),
		RunE: func(_ *cobra.Command, args []string) error {
			return beadNote(note.Request{Bead: strings.TrimSpace(args[0]), Text: args[1], Notify: notify}, db, stdout, stderr)
		},
	}
	cmd.Flags().BoolVar(&notify, "notify", false, "tell whoever is working the bead now, for a note that changes what that work should do")
	cmd.Flags().StringVar(&db, "db", "", "the store, a store's .beads directory")
	cmd.Flags().SetInterspersed(false)
	return cmd
}

// beadNote opens the bead's store, --db or else the one gc routes the bead to,
// and puts the note on the bead, printing what landed on stdout and why it
// stopped on stderr.
func beadNote(req note.Request, db string, stdout, stderr io.Writer) error {
	const prog = "gctk bead note"
	l, err := ledger.Open(db, req.Bead)
	if err != nil {
		fmt.Fprintf(stderr, "%s: could not open %s's store (%v); nothing was written\n", prog, req.Bead, err)
		return exit(1)
	}
	n := &note.Notes{Ledger: l, City: gascity.New(), By: "host"}
	for _, name := range []string{"GC_ALIAS", "GC_SESSION_NAME"} {
		if s := strings.TrimSpace(os.Getenv(name)); s != "" {
			n.By = s
			break
		}
	}
	for _, name := range []string{"GC_SESSION_NAME", "GC_SESSION_ID", "GC_ALIAS", "GC_AGENT"} {
		if s := strings.TrimSpace(os.Getenv(name)); s != "" {
			n.Self = append(n.Self, s)
		}
	}
	lines, err := n.Note(req)
	for _, line := range lines {
		fmt.Fprintln(stdout, line)
	}
	switch {
	case err == nil:
		return nil
	case note.Refused(err):
		fmt.Fprintf(stderr, "%s: %v\n", prog, err)
		return exit(2)
	case note.IsUntold(err):
		fmt.Fprintf(stderr, "%s: %v\n", prog, err)
		return exit(3)
	}
	fmt.Fprintf(stderr, "%s: %v\n", prog, err)
	return exit(1)
}
