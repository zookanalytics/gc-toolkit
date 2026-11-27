package cli

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/gate"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

func newGateCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("gate", "the gate types the pack defines, which the city closes itself",
		"The bd gates the pack defines, which the city closes itself and no person answers: "+
			"gctk:needs-review, a staying conversation's gate on the one piece of work it stays for.",
		newGateCreateCmd(stdout, stderr))
}

const gateCreateLong = `Files a gate of a type the pack defines, with one bd gate create, or finds the
open one the bead it blocks already waits on for the same work. bd's own flags
name its parts:

  gctk gate create --type gctk:needs-review --await-id <work-bead-id> --blocks <conversation-bead-id>

A gctk:needs-review gate is a staying conversation's promise: its await id is
the one piece of work the stay is for, and it blocks the conversation. The
landing order resolves it once the work's PR reads needs-review or merging in
its own right, putting the conversation's hold on the PR first, or once the work
closes. The conversation is then ready work, so Gas City wakes its sitting. The
sitting runs this right after it sends a piece of work itself.

It refuses, writing nothing: a type the pack does not define; a conversation
that is not open or in progress under the caller's alias, $GC_ALIAS, which a
sitting's claim records as its conversation's assignee; work in another store,
work that has closed, and work in the city's own store, which the landing order
does not read; a conversation that already waits on an open gate of this type
for other work; and work that waits on the conversation through another bead,
which could not move until something the conversation holds has landed.

It prints the gate's id. bd files the gate and then the conversation's edge onto
it, so a create that stops between the two leaves a gate nothing waits on, which
resolves at its condition and holds nothing; run the call again to file one that
holds the conversation.

--db names the conversation's store, a store's .beads directory. Without it the
call works in the store gc routes the conversation to.

exit: 0 the gate holds the conversation, filed now or found open
      2 usage, or the gate was refused, and it says why
      4 a read or a write did not land, and it says which`

func newGateCreateCmd(stdout, stderr io.Writer) *cobra.Command {
	var typ, work, conv, db string
	cmd := &cobra.Command{
		Use:   "create --type <type> --await-id <work-bead-id> --blocks <conversation-bead-id> [--db <path>]",
		Short: "file a gate the city closes itself on a piece of work, blocking a conversation, or find the open one",
		Long:  gateCreateLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			const prog = "gctk gate create"
			req := gate.Request{Type: strings.TrimSpace(typ), Work: strings.TrimSpace(work), Conversation: strings.TrimSpace(conv)}
			if err := gate.Validate(req); err != nil {
				fmt.Fprintf(stderr, "%s: %v. Nothing was written\n", prog, err)
				return exit(2)
			}
			l, err := ledger.Open(db, req.Conversation)
			if err != nil {
				fmt.Fprintf(stderr, "%s: could not open %s's store (%v). Nothing was written\n", prog, req.Conversation, err)
				return exit(4)
			}
			client := gcbd.New()
			if db != "" {
				client = client.In(db)
			}
			p := &gate.Promises{Ledger: l, InRig: client.InRig, Alias: os.Getenv("GC_ALIAS")}
			out, err := p.Create(req)
			switch {
			case gate.Refused(err):
				fmt.Fprintf(stderr, "%s: %v. Nothing was written\n", prog, err)
				return exit(2)
			case err != nil:
				fmt.Fprintf(stderr, "%s: %v\n", prog, err)
				return exit(4)
			case out.Found:
				fmt.Fprintf(stderr, "%s: %s already waits on the open gate %s for %s; no second gate filed\n", prog, req.Conversation, out.Gate, req.Work)
			default:
				fmt.Fprintf(stderr, "%s: filed %s, which holds %s until %s's PR reads needs-review or merging in its own right, or %s closes\n",
					prog, out.Gate, req.Conversation, req.Work, req.Work)
			}
			fmt.Fprintln(stdout, out.Gate)
			return nil
		},
	}
	cmd.Flags().StringVar(&typ, "type", "", "the gate's type, one the pack defines: "+strings.Join(gate.Types, ", "))
	cmd.Flags().StringVar(&work, "await-id", "", "the bead of the work the gate waits on")
	cmd.Flags().StringVar(&conv, "blocks", "", "the bead the gate blocks, the conversation")
	cmd.Flags().StringVar(&db, "db", "", "the conversation's store, a store's .beads directory")
	return cmd
}
