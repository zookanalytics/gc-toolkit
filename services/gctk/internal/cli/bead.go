package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"slices"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// `gctk bead holds <bead>...` answers what holds each bead, through the waits
// package, from one snapshot of the store (docs/gctk-architecture.md, "The
// bead holds contract"). It holds no rule: waits decides, and the command
// prints its answer.

const beadHoldsLong = `Prints what holds each bead named, from one read of the store: one JSON
object per line, in the order named, each bead once.

{"id", "status", "waits", "pending", "last_landed", "in_flight", "arm",
 "foreign"}

status is blocked when a wait of the bead's own holds it, held when only an
ancestor's wait holds it and its work has not started, unjudged when it has a
waits-for edge of its own, and clear otherwise. Work in flight is held only
by its own waits.

waits are the waits behind the status, each {"id", "type", "title",
"status"}, where title and status are those of the bead waited on, with
"ancestor" naming the ancestor whose wait it is. A waits-for wait is unjudged: the bd the city runs
judges it by its spawner's status rather than its gate, so a caller that acts
holds such a bead. pending is the bead's own waits that have not landed, and
last_landed is when the last of its own waits that landed did, "" when none
has. in_flight says why the bead is in flight: claimed, carrying branch,
merge_result or rejection_reason, or worked by a live workflow past
load-context, and is "" when it is not. arm is the arm on a bead armed to
start by itself, each value as the store holds it, and null when it carries
none. foreign is the bead's wait edges into another store, each {"id",
"type"}, which hold nothing.

A bead the store could not answer prints {"id", "error"} and no status, and
so does a bead the store does not hold.

--db names the store to read, a store's .beads directory, and every read of
the store names it with bd's own --db flag. Without it the command reads the
store gc resolves from the working directory and the environment, which it
asks gc bd where for, so no read that names a bead is routed to another
store.

exit: 0 every bead answered
      1 at least one bead's read failed, and its line carries the error
      2 usage`

func newBeadCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	holds := &cobra.Command{
		Use:   "holds [--db <path>] <bead>...",
		Short: "what holds each bead: one status, the waits behind it, its own pending waits, its arm and its edges into another store",
		Long:  beadHoldsLong,
		Args:  cobra.MinimumNArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			var ids []string
			for _, a := range args {
				id := strings.TrimSpace(a)
				if id == "" {
					return errors.New("name each bead by its id")
				}
				if !slices.Contains(ids, id) {
					ids = append(ids, id)
				}
			}
			return exit(beadHolds(db, ids, stdout, stderr))
		},
	}
	holds.Flags().StringVar(&db, "db", "", "the store to read, a store's .beads directory")
	return group("bead", "what holds a bead",
		"A bead's waits: what holds it, read from the store.", holds)
}

// failedLine is the line of a bead the store could not answer.
type failedLine struct {
	ID    string `json:"id"`
	Error string `json:"error"`
}

// beadHolds prints one line per bead, from one waits snapshot of them all,
// read from the store at db, or from the store gc resolves when db is empty.
func beadHolds(db string, ids []string, stdout, stderr io.Writer) int {
	snap, readErr := waits.ReadStore(db, ids...)
	code := 0
	for _, id := range ids {
		var line any
		h, err := waits.Holds{}, readErr
		if err == nil {
			h, err = snap.Holds(id)
		}
		if err != nil {
			line, code = failedLine{ID: id, Error: err.Error()}, 1
		} else {
			line = h
		}
		raw, err := json.Marshal(line)
		if err != nil {
			fmt.Fprintf(stderr, "gctk bead holds: could not encode the answer for %s: %v\n", id, err)
			return 1
		}
		fmt.Fprintf(stdout, "%s\n", raw)
	}
	return code
}
